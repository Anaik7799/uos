-module(telegram_service_ffi).
-export([
    system_now_utc_us/0,
    system_now_ns/0,
    set_worker_subject/3,
    get_worker_subject/2,
    clear_worker_subjects/1,
    stop_supervisor/1
]).

%% @doc Returns current UTC time in microseconds from monotonic system clock.
-spec system_now_utc_us() -> integer().
system_now_utc_us() ->
    erlang:system_time(microsecond).

%% @doc Returns current UTC time in nanoseconds from monotonic system clock.
-spec system_now_ns() -> integer().
system_now_ns() ->
    erlang:system_time(nanosecond).

-spec set_worker_subject(term(), binary(), term()) -> ok.
set_worker_subject(BotId, Role, Subject) ->
    persistent_term:put({telegram_worker, BotId, Role}, Subject),
    ok.

-spec get_worker_subject(term(), binary()) -> {ok, term()} | {error, nil}.
get_worker_subject(BotId, Role) ->
    try
        {ok, persistent_term:get({telegram_worker, BotId, Role})}
    catch
        error:badarg -> {error, nil}
    end.

-spec clear_worker_subjects(term()) -> ok.
clear_worker_subjects(BotId) ->
    lists:foreach(fun(Role) ->
        try persistent_term:erase({telegram_worker, BotId, Role}) catch _:_ -> ok end
    end, [<<"authority">>, <<"store">>, <<"poller">>, <<"coordinator">>]),
    ok.

-spec stop_supervisor(term()) -> ok.
stop_supervisor(Supervisor) ->
    Pid = case Supervisor of
        {supervisor, P} when is_pid(P) -> P;
        P when is_pid(P) -> P;
        _ -> undefined
    end,
    case Pid of
        undefined -> ok;
        _ ->
            exit(Pid, shutdown),
            ok
    end.
