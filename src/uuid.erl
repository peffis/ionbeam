-module(uuid).
-behaviour(gen_server).

%% A UUID is a 16-byte (128-bit) number. The number of theoretically possible 
%% UUIDs is therefore about 3 × 1038. In its canonical form, a UUID is 
%% represented by 32 hexadecimal digits, displayed in 5 groups separated by 
%% hyphens, in the form 8-4-4-4-12 for a total of 36 characters (32 digits and 
%% 4 hyphens).
%%
%% Version 4 UUIDs use a scheme relying only on random numbers. This algorithm 
%% sets the version number as well as two reserved bits. All other bits are set
%% using a random or pseudorandom data source. Version 4 UUIDs have the form 
%% xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx where x is any hexadecimal digit and y 
%% is one of 8, 9, A, or B.


-export([new/0, to_string/1, to_binary/1]).
-export([start_link/0, init/1, handle_call/3, handle_cast/2, code_change/3, handle_info/2, terminate/2]).

-define(Y, ["8", "9", "A", "B"]).

-record(state, {}).

%% @doc returns a new unique uuid
new() ->
    gen_server:call(?MODULE, generate).


%% @doc returns a uuid in string representation
to_string(UUID) when is_binary(UUID) ->
    binary_to_list(UUID).


%% @doc returns a uuid in binary representation
to_binary(UUID) when is_binary(UUID) ->
    UUID.

    

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% initialization
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init(_) ->
    {ok, #state{}}.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%% the gen_server functions supporting the api %%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

handle_call(generate, _From, State) ->
    {reply, list_to_binary(generate_unique()), State}.

handle_cast(_, State) ->
    {noreply, State}.

terminate(_, _State) ->
    ok.

code_change(_, _, _) ->
    ok.

handle_info(_, State) ->
    {noreply, State}.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% internal helper functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

					       
%% @doc XXXXXXXX-XXXX-4XXX-YXXX-XXXXXXXXXXXX

generate_unique() ->
    G0 = make_group(8),
    G1 = make_group(4),
    G2 = "4" ++ make_group(3),
    G3 = lists:nth(rand:uniform(length(?Y)), ?Y) ++ make_group(3),
    G4 = make_group(12),
    G0 ++ "-" ++ G1 ++ "-" ++ G2 ++ "-" ++ G3 ++ "-" ++ G4.


%% @doc makes a random digit group string where length(Result) = Digits
make_group(Digits) ->
    Max = trunc(math:pow(16,Digits)) - 1,
    fill(Digits, integer_to_list(rand:uniform(Max), 16)).


%% @doc fill pads a list, Stream, with "0" from the left so that resulting
%% list length is ExpectedDigits
fill(ExpectedDigits, Stream) ->
    case ExpectedDigits - length(Stream) of
	0 ->
	    Stream;
	N ->
	    Filling = ["0" || _ <- lists:seq(1, N)],
	    lists:flatten(Filling) ++ Stream
    end.



%%% EUNIT tests %%%%
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

generate_test() ->
    Uuid1 = list_to_binary(generate_unique()),
    Uuid2 = list_to_binary(generate_unique()),
    ?assertEqual(size(Uuid1), size(Uuid2)),
    ?assertNotEqual(Uuid1, Uuid2),
    ?assertEqual(Uuid1, to_binary(Uuid1)),
    Uuid1s = to_string(Uuid1),
    Uuid2s = to_string(Uuid2),
    ?assertEqual(length(Uuid1s), length(Uuid2s)),
    ?assertNotEqual(Uuid1s, Uuid2s),
    ?assertEqual(36, length(Uuid1s)).
    
    
    

-endif.
