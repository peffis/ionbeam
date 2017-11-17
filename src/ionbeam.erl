-module(ionbeam).

-export([run_script/1]).

run_script(Script) ->
    run_script(Script, #{}).


run_script([], _) ->
    ok;

run_script([{T, InContextKey, OutCtxKey} | Rest], Contexts) ->
    InCtx = make_ctx(InContextKey, Contexts),
    NextContexts = execute_task(T, InCtx, OutCtxKey, Contexts),
    run_script(Rest, NextContexts).


make_ctx('_', _Contexts) ->
    #{};

make_ctx(Map, _Contexts) when is_map(Map) ->
    Map;

make_ctx(Key, Contexts) when is_atom(Key) ->
    case maps:get(Key, Contexts, undefined) of
        undefined ->
            {error, {ctx_not_found, Key}};

        Ctx ->
            Ctx
    end;

make_ctx(KeyFun, Contexts) when is_function(KeyFun) ->
    KeyFun(Contexts).



execute_task(T, InCtx, OutCtxKey, Contexts) ->
    Ctx = ionbeam_task:execute(ionbeam_task:create(T), InCtx),
    store_ctx(OutCtxKey, Ctx, Contexts).


store_ctx('_', _, Contexts) ->
    Contexts;
store_ctx(Key, Ctx, Contexts) ->
    Contexts#{Key => Ctx}.
