-module(task_handler).
-behaviour(gen_server).

%% API.
-export([start_link/0]).

%% gen_server.
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).

-export([add/1, get/1, update/2, delete/1, list/0]).

-record(state, {
          tasks = #{}
         }).

%% API.

-spec start_link() -> {ok, pid()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

add(T) ->
    gen_server:call(?MODULE, {add, T}).

get(TID) ->
    gen_server:call(?MODULE, {get, TID}).

update(TID, T) ->
    gen_server:call(?MODULE, {update, TID, T}).

list() ->
    gen_server:call(?MODULE, list).

delete(TID) ->
    gen_server:call(?MODULE, {get, TID}).




%% gen_server.

init([]) ->
    {ok, #state{}}.

handle_call({add, T}, _From, #state{tasks = Tasks} = State) ->
    Uuid = unique_id(Tasks),
    T_with_id = T#{id => Uuid},
    {reply, Uuid, State#state{tasks = Tasks#{Uuid => T_with_id}}};

handle_call({get, TID}, _From, #state{tasks = Tasks} = State) ->
    {reply, maps:get(TID, Tasks, not_found), State};

handle_call({update, TID, T}, _From, #state{tasks = Tasks} = State) ->
    case maps:get(TID, Tasks, not_found) of
        not_found ->
            {reply, not_found, State};

        _ ->
            {reply, ok, State#state{tasks = Tasks#{TID => T}}}
    end;

handle_call({delete, TID}, _From, #state{tasks = Tasks} = State) ->
    {reply, maps:get(TID, Tasks, not_found), State#state{tasks = maps:remove(TID, Tasks)}};

handle_call(list, _From, #state{tasks = Tasks} = State) ->
    {reply, maps:keys(Tasks), State}.





handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% helpers
unique_id(Tasks) ->
    Uuid = uuid:new(),
    unique_id(Uuid, maps:get(Uuid, Tasks, is_unique), Tasks).

unique_id(Uuid, is_unique, _) ->
    Uuid;
unique_id(_, _, Tasks) ->
    Uuid = uuid:new(),
    unique_id(Uuid, maps:get(Uuid, Tasks, is_unique), Tasks).
