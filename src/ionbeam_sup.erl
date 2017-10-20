-module(ionbeam_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
	supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
	Procs = [
                 {uuid, {uuid, start_link, []},
                  permanent, 10000, worker, [uuid]},
                 {task_handler, {task_handler, start_link, []},
                  permanent, 10000, worker, [task_handler]}
                ],
	{ok, {{one_for_one, 1, 5}, Procs}}.
