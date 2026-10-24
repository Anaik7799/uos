-module(telegram_service_ffi).
-export([
    system_now_utc_us/0,
    system_now_ns/0,
    ensure_worker_scope/0,
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

%% Called only by child-start closures executing in their OTP supervisor.
%% RestForOne restarts reuse this supervisor-local table; any supervisor death
%% deletes it automatically. No global registry, handoff or cleanup process.
-spec ensure_worker_scope() -> ets:tid().
ensure_worker_scope() ->
    case erlang:get(telegram_worker_scope) of
        undefined ->
            Scope = ets:new(telegram_worker_subjects, [set, public]),
            erlang:put(telegram_worker_scope, Scope),
            Scope;
        Scope -> Scope
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
    %% Compatibility cleanup for caller-owned test scopes; operational scope
    %% lifetime belongs exclusively to the supervisor.
    try ets:delete(Scope) catch error:badarg -> ok end,
    ok.

-spec stop_supervisor(pid()) -> {ok, nil} | {error, binary()}.
stop_supervisor(Pid) when is_pid(Pid) ->
    try gen_server:stop(Pid, shutdown, 5000) of
        ok -> {ok, nil}
    catch
        exit:noproc -> {ok, nil};
        exit:{noproc, _} -> {ok, nil};
        exit:Reason -> {error, iolist_to_binary(io_lib:format("supervisor_stop_failed: ~p", [Reason]))}
    end;
stop_supervisor(_) -> {error, <<"invalid_supervisor_pid">>}.
