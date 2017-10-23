-module(ionbeam).

-export([run_script/1]).

run_script(Script) ->
    run_script(Script, #{}).


run_script([], _) ->
    ok;

run_script([{T, '_', OutCtxKey} | Rest], Contexts) ->
    NextContexts = execute_task(T, #{}, OutCtxKey, Contexts),
    run_script(Rest, NextContexts);

run_script([{T, InCtxKey, OutCtxKey} | Rest], Contexts) when is_atom(InCtxKey) ->
    case maps:get(InCtxKey, Contexts, undefined) of
        undefined ->
            {error, {ctx_not_found, InCtxKey}};

        InCtx ->
            NextContexts = execute_task(T, InCtx, OutCtxKey, Contexts),
            run_script(Rest, NextContexts)
    end;

run_script([{T, InCtxFun, OutCtxKey} | Rest], Contexts) when is_function(InCtxFun) ->
    InCtx = InCtxFun(Contexts),
    NextContexts = execute_task(T, InCtx, OutCtxKey, Contexts),
    run_script(Rest, NextContexts).



execute_task(T, InCtx, OutCtxKey, Contexts) ->
    Ctx = ionbeam_task:execute(ionbeam_task:create(T), InCtx),
    store_ctx(OutCtxKey, Ctx, Contexts).


store_ctx('_', _, Contexts) ->
    Contexts;
store_ctx(Key, Ctx, Contexts) ->
    Contexts#{Key => Ctx}.
