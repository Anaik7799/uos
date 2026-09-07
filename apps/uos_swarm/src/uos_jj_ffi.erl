%% Pure-Erlang port transport for the Jujutsu (`jj`) binary. No shell string is
%% ever built: `erlang:open_port/2` is invoked with `{spawn_executable, Exe}`
%% and a literal `{args, Args}` list, so there is no interpolation surface and
%% therefore no injection path, regardless of what bytes a caller supplies in
%% a revset, message, or path. This module never shells out to `git`.
-module(uos_jj_ffi).
-export([run/4, which/1]).

-define(OUTPUT_LIMIT_BYTES, 16777216).

%% `os:find_executable/1` walks $PATH; no default `jj` location is assumed.
-spec which(binary()) -> {ok, binary()} | {error, nil}.
which(Name) ->
    case os:find_executable(unicode:characters_to_list(Name)) of
        false -> {error, nil};
        Path -> {ok, unicode:characters_to_binary(Path)}
    end.

%% Exe and Cwd are binaries at the Gleam boundary; Erlang's `open_port/2`
%% accepts binaries for `spawn_executable`, `{cd, _}`, and each element of
%% `{args, _}` since OTP 24. stdout and stderr are merged so callers see the
%% same diagnostic text `jj` would print to a terminal; the exit status is
%% surfaced separately from the byte stream it decorates.
-spec run(binary(), [binary()], binary(), integer()) ->
    {ok, {integer(), binary()}} | {error, binary()}.
run(Exe, Args, Cwd, TimeoutMs) ->
    Opts = [{args, Args}, {cd, Cwd}, exit_status, binary,
             stderr_to_stdout, use_stdio, hide],
    try erlang:open_port({spawn_executable, Exe}, Opts) of
        Port ->
            Deadline = erlang:monotonic_time(millisecond) + TimeoutMs,
            collect(Port, Deadline, 0, [])
    catch
        error:_ -> {error, <<"jj_spawn_failed">>}
    end.

-spec collect(port(), integer(), non_neg_integer(), [binary()]) ->
    {ok, {integer(), binary()}} | {error, binary()}.
collect(Port, Deadline, Size, Chunks) ->
    Remaining = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {Port, {data, Bytes}} ->
            NewSize = Size + byte_size(Bytes),
            case NewSize =< ?OUTPUT_LIMIT_BYTES of
                true -> collect(Port, Deadline, NewSize, [Bytes | Chunks]);
                false -> terminate(Port), {error, <<"jj_output_limit">>}
            end;
        {Port, {exit_status, Code}} ->
            {ok, {Code, iolist_to_binary(lists:reverse(Chunks))}}
    after Remaining ->
        terminate(Port),
        {error, <<"jj_timeout">>}
    end.

%% Keep the port open while sending SIGKILL to its owned child, then drain
%% and close. The pid is read only from this port, never supplied by a caller.
-spec terminate(port()) -> ok.
terminate(Port) ->
    receive
        {Port, {exit_status, _}} -> ok
    after 0 ->
        case erlang:port_info(Port, os_pid) of
            {os_pid, Pid} -> kill(Pid);
            undefined -> ok
        end
    end,
    _ = catch erlang:port_close(Port),
    drain(Port),
    ok.

-spec kill(pos_integer()) -> ok.
kill(Pid) ->
    case os:find_executable("kill") of
        false -> ok;
        Kill ->
            try erlang:open_port({spawn_executable, Kill},
                    [binary, exit_status, use_stdio, stderr_to_stdout,
                     {args, ["-KILL", "--", integer_to_list(Pid)]}]) of
                Killer ->
                    receive {Killer, {exit_status, _}} -> ok
                    after 250 -> _ = catch erlang:port_close(Killer), ok
                    end,
                    drain(Killer)
            catch error:_ -> ok
            end
    end.

-spec drain(port()) -> ok.
drain(Port) ->
    receive {Port, _} -> drain(Port)
    after 0 -> ok
    end.
