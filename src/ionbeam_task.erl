-module(ionbeam_task).

-compile([{parse_transform, lager_transform}]).
-export([create/1, add_subtask/2, execute/1, execute/2, show_result/2]).

-define(DEFAULT_VALUES,
        #{subtasks => [],
          description => "task not described",
          request => #{
            method => "GET",
            host => "localhost",
            port => "443",
            path => "/",
            headers => "\r\n",
            body => ""
           },

          response => #{
            status => undefined,
            headers => undefined,
            body => undefined
           }
         }).


create({sleep, _T} = SleepTask) ->
    SleepTask;
create(TaskData) ->
    apply_defaults(TaskData).


apply_defaults(TaskData) ->
    Root = maps:merge(?DEFAULT_VALUES, TaskData),
    Root#{request => maps:merge(maps:get(request, ?DEFAULT_VALUES),
                                maps:get(request, TaskData, #{})),
          response => maps:merge(maps:get(response, ?DEFAULT_VALUES),
                                 maps:get(response, TaskData, #{}))}.


add_subtask(Child, #{subtasks := Subs} = Parent) ->
    Parent#{subtasks => Subs ++ [Child]}.


show_result(T, ResultCtx) when is_map(T), is_map(ResultCtx) ->
    D = maps:get(description, T),
    ST = maps:get(subtasks, T),
    Indentation = case ST of
                      [] ->
                          "   ";
                      _ -> ""
                  end,

    lager:info("~scompleted \"~s\"", [Indentation, D]),
    show_result(Indentation, maps:to_list(ResultCtx));

show_result(Indentation, TupleList) when is_list(Indentation), is_list(TupleList) ->
    lists:foreach(fun({K, V}) -> lager:info("~s~s~s => ~s", [Indentation, Indentation, K, V]) end,
                  lists:filter(fun({K, _V}) ->
                                       [First | _] = K,
                                       case First of
                                           $_ ->
                                               false;
                                           _ -> true
                                       end
                               end, TupleList)).



%% execute runs a task given a context, if successful it returns the new context or throws an {error, Reason, Stack} tuple
execute(T) ->
    execute(T, #{}).

execute({sleep, T}, Context) ->
    timer:sleep(T),
    Context;

execute(T, Context) ->
    Desc = maps:get(description, T),
    Subtasks = maps:get(subtasks, T),
    lager:info("   running \"~s\"", [Desc]),

    try
        case Subtasks of
            [] ->
                Response = execute_task(T, Context),
                validate(Response, T, Context);

            _ when is_list(Subtasks)  ->
                lists:foldl(fun(ST, Ctx) -> execute(ST, Ctx) end, Context, Subtasks)
        end

    catch
        error:Reason:Stacktrace ->
            lager:error("stack: ~p", [Stacktrace]),
            throw({error, Reason, [{Desc, Context}]})
    end.


execute_task(#{request := Request}, C) ->
    MethodTemplate = maps:get(method, Request),
    HostTemplate = maps:get(host, Request),
    PortTemplate = maps:get(port, Request),
    PathTemplate = maps:get(path, Request),
    HeadersTemplate = maps:get(headers, Request),
    BodyTemplate = maps:get(body, Request),

    Host = template:replace(HostTemplate, C),
    Port = list_to_integer(template:replace(PortTemplate, C)),
    Path = template:replace(PathTemplate, C),
    Headers = template:replace(HeadersTemplate, C),
    Body = case BodyTemplate of
               {file, _} -> BodyTemplate;
               _ -> template:replace(BodyTemplate, C)
           end,
    Method = template:replace(MethodTemplate, C),

    do_request(Method, Host, Port, Path, Headers, Body, C).





do_request(Method, Host, Port, Path, Headers, Body, C) ->
    lager:info("     request: ~s ~s://~s:~p~s",
               [Method, case Port of 80 -> "http";_ -> "https" end, Host, Port, Path]),
    {ok, ConnPid} = gun:open(Host, Port),
    ParsedHeaders = parse_headers(Headers),
    StreamRef = make_request(Method, ConnPid, Path, ParsedHeaders, Body, C),
    receive_response(StreamRef).

make_request("GET", ConnPid, Path, Headers, _Body, _C) ->
    gun:get(ConnPid, Path, Headers);
make_request("POST", ConnPid, Path, Headers, {file, Fname}, _C) ->
    StreamRef = gun:post(ConnPid, Path, Headers),
    ok = stream_file(StreamRef, ConnPid, Fname),
    StreamRef;
make_request("POST", ConnPid, Path, Headers, Body, _C) ->
    gun:post(ConnPid, Path, Headers, Body);
make_request("PUT", ConnPid, Path, Headers, Body, _C) ->
    gun:put(ConnPid, Path, Headers, Body);
make_request("DELETE", ConnPid, Path, Headers, _Body, _C) ->
    gun:delete(ConnPid, Path, Headers);
make_request("PATCH", ConnPid, Path, Headers, Body, _C) ->
    gun:patch(ConnPid, Path, Headers, Body);
make_request(Method, ConnPid, _, _, _, C) ->
    gun:close(ConnPid),
    throw({error, {http_method_not_implemented, Method}, C}).

stream_file(StreamRef, ConnPid, Fname) when is_list(Fname) ->
    stream_file(StreamRef, ConnPid, file:open(Fname, [read, binary]));
stream_file(_StreamRef, _ConnPid, {error, Reason}) ->
    Reason;
stream_file(StreamRef, ConnPid, {ok, IoDevice}) ->
    stream_file(StreamRef, ConnPid, IoDevice, file:read(IoDevice, 1024)).

stream_file(StreamRef, ConnPid, IoDevice, {ok, Data}) when is_binary(Data) ->
    gun:data(ConnPid, StreamRef, nofin, Data),
    stream_file(StreamRef, ConnPid, IoDevice, file:read(IoDevice, 1024));
stream_file(StreamRef, ConnPid, _IoDevice, eof)  ->
    gun:data(ConnPid, StreamRef, fin, <<"">>),
    ok;
stream_file(_StreamRef, _ConnPid, _IoDevice, {error, Reason}) ->
    Reason.



receive_response(StreamRef) ->
    receive
        {gun_response, ConnPid, StreamRef, fin, Status, Headers} ->
            gun:close(ConnPid),
            #{status => Status, headers => convert_headers(Headers), body => ""};
        {gun_response, ConnPid, StreamRef, nofin, Status, Headers} ->
            receive_data(ConnPid, Status, Headers, StreamRef, []);
        {'DOWN', _MRef, process, _ConnPid, Reason} ->
            throw({error, Reason})
    after 10000 ->
            throw({error, timeout})
    end.


receive_data(ConnPid, Status, Headers, StreamRef, Res) ->
    receive
        {gun_data, ConnPid, StreamRef, nofin, Data} ->
            receive_data(ConnPid, Status, Headers, StreamRef, [Data | Res]);
        {gun_data, ConnPid, StreamRef, fin, Data} ->
            Body = lists:flatten([binary_to_list(B) || B <- lists:reverse([Data | Res])]),
            gun:close(ConnPid),
            #{status => Status, headers => convert_headers(Headers), body => Body};
        {'DOWN', _MRef, process, ConnPid, Reason} ->
            throw({error, Reason})
    after 1000 ->
            throw({error, timeout})
    end.


convert_headers(Headers) ->
    lists:map(fun({BinKey, BinVal}) ->
                      H = <<BinKey/binary, ": ", BinVal/binary, "\r\n\r\n">>,
                      {ok, {http_header, _, Key, undefined, Val}, <<"\r\n">>} =
                          erlang:decode_packet(httph, H, []),
                      decode_key(Key) ++ ": " ++ decode_value(Val)
              end, Headers).



validate(#{status := Status, headers := Headers, body := Body}, T, Context) ->
    ContextAfterStatusValidation = validate_status(Status, T, Context),
    ContextAfterHeadersValidation = validate_headers(Headers, T, ContextAfterStatusValidation),
    ContextAfterBodyValidation = validate_body(Body, T, ContextAfterHeadersValidation),
    ContextAfterBodyValidation.

validate_status(_, #{response := #{status := undefined}}, Ctx) ->
    Ctx;
validate_status(Status, #{response := #{status := SC}} = T, Ctx) ->
    case lists:member(Status, SC) of
        true ->
            Ctx;
        _ ->
            Descr = maps:get(description, T),
            throw({error, {status, {Status, SC}}, [{Descr, Ctx}]})
    end.

validate_headers(_, #{response := #{headers := undefined}}, Ctx) ->
    Ctx;
validate_headers([], _, Ctx) ->
    Ctx;
validate_headers([H | Headers], #{response := #{headers := HC}} = T, Ctx) ->
    #{match := ML} = HC,
    Descr = maps:get(description, T),
    Ctx2 = match_header(H, ML, Ctx, Descr),
    ok = validate_matched_values(Ctx2, HC, Descr, Ctx2),
    validate_headers(Headers, T, merge_contexts(Ctx2, Ctx, Descr)).


validate_body(_, #{response := #{body := undefined}}, Ctx) ->
    Ctx;

validate_body(Body, #{response := #{body := BC}, description := Descr}, Ctx) when is_function(BC) ->
    case BC(Body, Ctx) of
        {error, Reason} ->
            throw({error, Reason, [{Descr, Ctx}]});

        Ctx2 ->
            merge_contexts(Ctx2, Ctx, Descr)
    end;

validate_body(Body, #{response := #{body := BC}, description := Descr}, Ctx) when is_map(BC) ->
    #{match := BodyTemplate} = BC,

    case template:match(BodyTemplate, Body) of
        {error, Reason} ->
            throw({error, Reason, [{Descr, Ctx}]});

        Ctx2 ->
            ok = validate_matched_values(Ctx2, BC, Descr, Ctx2),
            merge_contexts(Ctx2, Ctx, Descr)
    end.




validate_matched_values(MatchResult, HC, Descr, Ctx) when is_map(MatchResult) ->
    validate_matched_values(maps:to_list(MatchResult), HC, Descr, Ctx);
validate_matched_values([], _HC, _, _) ->
    ok;
validate_matched_values([{Key, Val} | Rest], HC, Descr, Ctx) ->
    case maps:get(Key, HC, undefined) of
        Val ->
            validate_matched_values(Rest, HC, Descr, Ctx);

        undefined ->
            validate_matched_values(Rest, HC, Descr, Ctx);

        OtherVal ->
            throw({error, {mismatch, Val, OtherVal}, [{Descr, Ctx}]})
    end.




match_header(_, [], Ctx, _Descr) ->
    Ctx;
match_header(H, [HTempl | Rest], Ctx, Descr) ->
    case template:match(HTempl, H) of
        {error, _} ->
            match_header(H, Rest, Ctx, Descr);
        Ctx2 ->
            merge_contexts(Ctx2, Ctx, Descr)
    end.


merge_contexts(Addition, Current, Descr) ->
    lists:foldl(fun({Key, Val}, Ctx) ->
                        [First | _] = Key, %% extract the first char
                        case First of
                            $_ -> Ctx#{Key => Val}; %% let variables starting with _ override existing variables of same name
                            _ ->
                                case maps:get(Key, Ctx, undefined) of
                                    undefined ->
                                        Ctx#{Key => Val};
                                    Val ->
                                        Ctx;
                                    OtherVal ->
                                        throw({error, {value_mismatch, Val, OtherVal}, [{Descr, Ctx}]})
                                end
                        end
                end, Current, maps:to_list(Addition)).



parse_headers(Headers) ->
    parse_headers_internal(erlang:decode_packet(httph, list_to_binary(Headers), []), []).


parse_headers_internal({ok,http_eoh,<<>>}, Result) ->
    lists:reverse(Result);

parse_headers_internal({ok, {http_header, _, Key, undefined, Value}, Rest}, Result) ->
    parse_headers_internal(erlang:decode_packet(httph, Rest, []),
                           [{encode_key(Key), encode_value(Value)} | Result]).

decode_key(Key) when is_list(Key) ->
    Key;
decode_key(Key) when is_binary(Key) ->
    binary_to_list(Key);
decode_key(Key) when is_atom(Key) ->
    atom_to_list(Key).

decode_value(Val) when is_list(Val) ->
    Val;
decode_value(Val) when is_binary(Val) ->
    binary_to_list(Val).


encode_key(Key) when is_atom(Key) ->
    encode_key(atom_to_list(Key));
encode_key(Key) when is_list(Key) ->
    list_to_binary(Key).

encode_value(Value) when is_list(Value) ->
    list_to_binary(Value).


%%% eunit tests
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

parse_headers_test() ->
    ?assertEqual([{<<"Accept">>, <<"application/json">>}],
                 parse_headers("accept: application/json\r\n\r\n")),

    ?assertEqual([{<<"Accept">>, <<"application/json">>},
                  {<<"Content-Type">>, <<"application/json">>},
                  {<<"X-Token">>, <<"token">>}],
                 parse_headers("accept: application/json\r\n" ++
                                   "content-type: application/json\r\n" ++
                                   "X-Token: token\r\n" ++
                                   "\r\n")).


-endif.
