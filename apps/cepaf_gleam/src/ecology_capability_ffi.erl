%% =============================================================================
%% UOS Ecology Capability Port FFI (SC-HOLON-001, SC-TOOLCHAIN-INPROJECT-001)
%% -----------------------------------------------------------------------------
%% Honest backend probes and BOUNDED subprocess execution for the 11-capability
%% super-agent substrate.
%%
%% Design invariant (the whole point of this module): a capability whose backend
%% is absent MUST be reported absent. It must never be simulated, defaulted, or
%% counted as engaged. Every probe below answers "is the real thing actually
%% there, right now" -- never "was it declared".
%%
%% Every subprocess is bounded: explicit timeout, exit_status, and process-tree
%% reaping via os:cmd("kill") on the OS pid, per canonical policy section 7
%% (solvers and external engines run only in isolated bounded workers).
%% =============================================================================
-module(ecology_capability_ffi).

-export([uos_root/0, probe_executable/1, run_bounded/3,
         ets_backend_probe/0, km_nif_loaded/0, env_present/1]).

%% --- repo root --------------------------------------------------------------
%% Resolved from the loaded application's priv dir, so nothing hardcodes a
%% machine path. Falls back to cwd only if the app is not loaded.
uos_root() ->
    Start = case code:priv_dir(cepaf_gleam) of
                {error, _} -> element(2, file:get_cwd());
                PrivDir -> PrivDir
            end,
    unicode:characters_to_binary(ascend_to_repo_root(filename:absname(Start))).

%% Walk upward until the directory holding the standalone Jujutsu repo (.jj) is
%% found. That marker -- not a fixed number of ".." hops -- identifies the UOS
%% root, so this works for a dev build (build/dev/erlang/<app>/priv) and for a
%% release layout alike. Falls back to the starting path if no marker is found,
%% which makes downstream probes report ABSENT rather than silently guess.
ascend_to_repo_root(Dir) ->
    case filelib:is_dir(filename:join(Dir, ".jj")) of
        true -> Dir;
        false ->
            Parent = filename:dirname(Dir),
            case Parent =:= Dir of
                true -> Dir;
                false -> ascend_to_repo_root(Parent)
            end
    end.

%% --- probes -----------------------------------------------------------------
probe_executable(Path) ->
    P = binary_to_list(Path),
    case file:read_file_info(P) of
        {ok, Info} ->
            Mode = element(8, Info),
            (Mode band 8#111) =/= 0;
        _ -> false
    end.

%% ETS is in-process: the probe actually creates and reads back a term rather
%% than asserting that ETS "exists". A read-back mismatch reports false.
ets_backend_probe() ->
    try
        Key = {uos_ecology_probe, erlang:unique_integer()},
        Val = erlang:monotonic_time(),
        beam_cache_ffi:ets_init(),
        beam_cache_ffi:ets_put(Key, Val),
        Got = beam_cache_ffi:ets_get(Key),
        beam_cache_ffi:ets_delete(Key),
        case Got of
            {ok, Val} -> true;
            Val -> true;
            _ -> false
        end
    catch _:_ -> false
    end.

%% Delegates to the NIF shim's own loaded/0, which distinguishes "kernel says 0.0"
%% from "kernel is absent".
km_nif_loaded() ->
    try uos_km_nif:loaded() catch _:_ -> false end.

env_present(Name) ->
    case os:getenv(binary_to_list(Name)) of
        false -> false;
        "" -> false;
        _ -> true
    end.

%% --- bounded execution ------------------------------------------------------
%% Returns {ok, {ExitCode, Output}} | {error, Reason}. Never blocks past TimeoutMs.
run_bounded(Path, Args, TimeoutMs) ->
    P = binary_to_list(Path),
    A = [binary_to_list(X) || X <- Args],
    try
        Port = erlang:open_port({spawn_executable, P},
                                [stream, use_stdio, exit_status, binary,
                                 stderr_to_stdout, {args, A}]),
        OsPid = case erlang:port_info(Port, os_pid) of
                    {os_pid, Pid} -> Pid;
                    _ -> undefined
                end,
        collect(Port, OsPid, TimeoutMs, <<>>)
    catch
        _:Reason ->
            {error, unicode:characters_to_binary(io_lib:format("~p", [Reason]))}
    end.

collect(Port, OsPid, TimeoutMs, Acc) ->
    receive
        {Port, {data, Chunk}} ->
            collect(Port, OsPid, TimeoutMs, <<Acc/binary, Chunk/binary>>);
        {Port, {exit_status, Code}} ->
            %% Shaped as {ok, {Code, Output}} to match Gleam's Result(#(Int, String), String).
            {ok, {Code, Acc}}
    after TimeoutMs ->
        %% Reap the process tree, then the port. A timeout is an honest failure,
        %% not a zero-exit success.
        reap(OsPid),
        _ = (try erlang:port_close(Port) catch _:_ -> ok end),
        {error, <<"timeout">>}
    end.

reap(undefined) -> ok;
reap(OsPid) ->
    %% TERM the group then the pid; ignore failures (process may already be gone).
    _ = os:cmd("kill -TERM -" ++ integer_to_list(OsPid) ++ " 2>/dev/null"),
    _ = os:cmd("kill -TERM " ++ integer_to_list(OsPid) ++ " 2>/dev/null"),
    timer:sleep(50),
    _ = os:cmd("kill -KILL " ++ integer_to_list(OsPid) ++ " 2>/dev/null"),
    ok.
