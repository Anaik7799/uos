-module(telegram_service_ffi).
-export([
    system_now_utc_us/0,
    system_now_ns/0,
    new_worker_scope/0,
    adopt_worker_scope/2,
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

%% Anonymous ETS references are owned by the service supervisor after startup.
%% OTP deletes the table on any owner termination, including kill.
-spec new_worker_scope() -> ets:tid().
new_worker_scope() ->
    ets:new(telegram_worker_subjects, [set, public]).

-spec adopt_worker_scope(ets:tid(), pid()) -> {ok, nil} | {error, binary()}.
adopt_worker_scope(Scope, Owner) ->
    try
        true = ets:give_away(Scope, Owner, nil),
        {ok, nil}
    catch
        error:badarg -> {error, <<"worker_scope_handoff_failed">>}
    end.

-spec set_worker_subject(term(), binary(), term()) -> ok.
set_worker_subject(Scope, Role, Subject) when is_reference(Scope) ->
    true = ets:insert(Scope, {Role, Subject}),
    ok;
%% Standalone component workers have no shared discovery registry.
set_worker_subject(_ComponentId, _Role, _Subject) -> ok.

-spec get_worker_subject(term(), binary()) -> {ok, term()} | {error, nil}.
get_worker_subject(Scope, Role) ->
    try
        case ets:lookup(Scope, Role) of
            [{Role, Subject}] -> {ok, Subject};
            [] -> {error, nil}
        end
    catch
        error:badarg -> {error, nil}
    end.

-spec clear_worker_subjects(term()) -> ok.
clear_worker_subjects(Scope) ->
    %% Failed startup: the caller still owns the table. Successful handoff:
    %% stop_instance waits for supervisor DOWN; OTP has already deleted it.
    try ets:delete(Scope) catch error:badarg -> ok end,
    ok.

-spec stop_supervisor(term()) -> {ok, nil} | {error, binary()}.
stop_supervisor(Supervisor) ->
    Pid = case Supervisor of
        {supervisor, P} when is_pid(P) -> P;
        P when is_pid(P) -> P;
        _ -> undefined
    end,
    case Pid of
        undefined -> {error, <<"invalid_supervisor_handle">>};
        _ ->
            try gen_server:stop(Pid, shutdown, 5000) of
                ok -> {ok, nil}
            catch
                exit:noproc -> {ok, nil};
                exit:{noproc, _} -> {ok, nil};
                exit:Reason -> {error, iolist_to_binary(io_lib:format("supervisor_stop_failed: ~p", [Reason]))}
            end
    end.
