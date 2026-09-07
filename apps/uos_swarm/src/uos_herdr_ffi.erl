%% Herdr port interpreter. Only the four fixed agent commands are accepted.
%% No shell, no terminal keys, no agent spawning/stopping, and no prompt retry.
%% The deadline kills only the invoked Herdr CLI client, never its server/agents.
%% This is a transport adapter; CLI observation is not atomic session authority.
-module(uos_herdr_ffi).
-export([run/1]).

-define(TIMEOUT_MS, 12000).
-define(OUTPUT_BYTES, 65536).

-spec run([binary()]) -> {ok, binary()} | {error, binary()}.
run(Args) ->
    case {os:getenv("HERDR_ENV"), allowed(Args), os:find_executable("herdr")} of
        {"1", true, Exe} when is_list(Exe) ->
            case os:find_executable("kill") of
                false -> {error, <<"client_cleanup_unavailable">>};
                _ -> bounded(Exe, [binary_to_list(A) || A <- Args],
                             ?TIMEOUT_MS, ?OUTPUT_BYTES)
            end;
        {"1", true, false} -> {error, <<"herdr_not_found">>};
        {"1", false, _} -> {error, <<"command_not_allowed">>};
        _ -> {error, <<"not_in_herdr">>}
    end.

-spec allowed(term()) -> boolean().
allowed([<<"agent">>, <<"list">>]) -> true;
allowed([<<"agent">>, <<"get">>, Target]) -> identifier(Target);
allowed([<<"agent">>, <<"read">>, Target, <<"--source">>,
         <<"recent-unwrapped">>, <<"--lines">>, <<"80">>]) -> identifier(Target);
allowed([<<"agent">>, <<"prompt">>, Target, Message]) ->
    identifier(Target) andalso is_binary(Message) andalso byte_size(Message) > 0
    andalso byte_size(Message) =< 4096 andalso printable(Message, true);
allowed(_) -> false.

-spec identifier(term()) -> boolean().
identifier(Bin) when is_binary(Bin), byte_size(Bin) > 0, byte_size(Bin) =< 256 ->
    binary:first(Bin) =/= $- andalso binary:match(Bin, <<" ">>) =:= nomatch
    andalso printable(Bin, false);
identifier(_) -> false.

-spec printable(binary(), boolean()) -> boolean().
printable(<<>>, _) -> true;
printable(<<Byte, Rest/binary>>, Multiline) when Byte < 32; Byte =:= 127 ->
    Multiline andalso (Byte =:= 9 orelse Byte =:= 10) andalso printable(Rest, Multiline);
printable(<<_, Rest/binary>>, Multiline) -> printable(Rest, Multiline).

-spec bounded(string(), [string()], pos_integer(), pos_integer()) ->
    {ok, binary()} | {error, binary()}.
bounded(Exe, Args, Timeout, Limit) ->
    try open_port({spawn_executable, Exe},
                  [binary, exit_status, use_stdio, stderr_to_stdout, {args, Args}]) of
        Port ->
            Deadline = erlang:monotonic_time(millisecond) + Timeout,
            collect(Port, Deadline, Limit, 0, [])
    catch
        error:_ -> {error, <<"herdr_spawn_failed">>}
    end.

-spec collect(port(), integer(), pos_integer(), non_neg_integer(), [binary()]) ->
    {ok, binary()} | {error, binary()}.
collect(Port, Deadline, Limit, Size, Chunks) ->
    Remaining = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {Port, {data, Bytes}} ->
            NewSize = Size + byte_size(Bytes),
            case NewSize =< Limit of
                true -> collect(Port, Deadline, Limit, NewSize, [Bytes | Chunks]);
                false -> terminate_client(Port), {error, <<"herdr_output_limit">>}
            end;
        {Port, {exit_status, 0}} ->
            valid_utf8(iolist_to_binary(lists:reverse(Chunks)));
        {Port, {exit_status, Code}} ->
            {error, <<"herdr_exit_", (integer_to_binary(Code))/binary>>}
    after Remaining ->
        terminate_client(Port),
        {error, <<"herdr_timeout_outcome_unknown">>}
    end.

-spec valid_utf8(binary()) -> {ok, binary()} | {error, binary()}.
valid_utf8(Bytes) ->
    case unicode:characters_to_binary(Bytes, utf8, utf8) of
        Text when is_binary(Text) -> {ok, Text};
        _ -> {error, <<"herdr_invalid_utf8">>}
    end.

%% Keep the port open while sending SIGKILL to its child. The PID is obtained
%% only from this owned port, never supplied by a caller. Herdr CLI does not
%% spawn the agents: terminating this client must not terminate peer sessions.
-spec terminate_client(port()) -> ok.
terminate_client(Port) ->
    receive
        {Port, {exit_status, _}} -> ok
    after 0 ->
        case erlang:port_info(Port, os_pid) of
            {os_pid, Pid} -> kill_client(Pid);
            undefined -> ok
        end
    end,
    _ = catch erlang:port_close(Port),
    drain(Port),
    ok.

-spec kill_client(pos_integer()) -> ok.
kill_client(Pid) ->
    case os:find_executable("kill") of
        false -> ok;
        Kill ->
            try open_port({spawn_executable, Kill},
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

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

command_surface_test() ->
    ?assert(allowed([<<"agent">>, <<"get">>, <<"w2:p4">>])),
    ?assertNot(allowed([<<"agent">>, <<"send-keys">>, <<"w2:p4">>, <<"enter">>])),
    ?assertNot(allowed([<<"agent">>, <<"start">>, <<"peer">>])),
    ?assertNot(allowed([<<"server">>, <<"stop">>])),
    ?assertNot(allowed([<<"agent">>, <<"get">>, <<"--current">>])),
    ?assertNot(allowed([<<"agent">>, <<"prompt">>, <<"w2:p4">>, <<27, "[201~">>])),
    ?assertNot(allowed([<<"agent">>, <<"prompt">>, <<"w2:p4">>, binary:copy(<<"x">>, 4097)])).

timeout_kills_owned_client_test() ->
    Port = open_port({spawn_executable, "/bin/sleep"},
                     [binary, exit_status, {args, ["5"]}]),
    {os_pid, Pid} = erlang:port_info(Port, os_pid),
    Start = erlang:monotonic_time(millisecond),
    ?assertEqual({error, <<"herdr_timeout_outcome_unknown">>},
                 collect(Port, Start + 30, 256, 0, [])),
    ?assert(erlang:monotonic_time(millisecond) - Start < 1000),
    timer:sleep(20),
    ?assertEqual({error, enoent}, file:read_file_info("/proc/" ++ integer_to_list(Pid))).

output_limit_discards_body_test() ->
    ?assertEqual({error, <<"herdr_output_limit">>},
                 bounded("/usr/bin/printf", ["%s", lists:duplicate(4096, $x)], 1000, 256)).

argument_bytes_are_literal_test() ->
    Text = <<"$(touch /tmp/herdr-forbidden) `echo injected` ; echo no">>,
    ?assertEqual({ok, Text}, bounded("/usr/bin/printf", ["%s", binary_to_list(Text)], 1000, 256)).
-endif.
