%% Port adapter for tools/validation/verify_guardian.exe (/verify gate runs).
%% The guardian, not this module, owns the child: it forks, makes the child a
%% process-group leader, enforces the deadline, SIGKILLs the group and reaps
%% with waitpid. This module only:
%%   E1 verifies the guardian binary against its pin before spawning it;
%%   E2 keeps the port (the guardian's control stdin) OPEN for the whole run.
%%      Closing it, or this process dying, is the guardian's abort signal, so
%%      a dead caller cannot leave an unsupervised gate running;
%%   E3 on its own overall timeout signals abort WITHOUT closing, waits a
%%      bounded grace for exit_status, and reports cleanup_unknown if none
%%      arrives. It never signals a remembered OS pid (see
%%      sa_plan_observer_ffi.erl A2 for why);
%%   E4 accepts a receipt only when its result, cleanup and exit status form
%%      one of the guardian's exact pairings, the declared byte count equals
%%      the payload and the payload hashes to the declared output_sha256.
%%      Partial output from killed or failing gates is returned, not dropped.
-module(telegram_verify_exec_ffi).
-export([run/7, write_new/2, make_dir/1]).

-define(MARKER, <<"uos.telegram.verify.guardian.v1">>).
-define(GUARDIAN_MAX_BYTES, 67108864).
-define(RECEIPT_OVERHEAD, 1024).
%% The guardian's own reap budget is up to 2 s after its deadline.
-define(REAP_GRACE_MS, 3000).
-define(ABORT_GRACE_MS, 2000).
-define(PRELAUNCH, [<<"exe_not_regular_file">>, <<"exe_too_large">>,
                    <<"exe_unreadable">>, <<"exe_digest_mismatch">>,
                    <<"deadline_during_digest">>, <<"deadline_before_spawn">>,
                    <<"fork_failed">>]).

run(Guardian, GuardianSha, Exe, ExeSha, Args, DeadlineMs, MaxBytes)
  when is_binary(Guardian), is_binary(GuardianSha), is_binary(Exe),
       is_binary(ExeSha), is_list(Args), is_integer(DeadlineMs),
       DeadlineMs >= 1, DeadlineMs =< 60000, is_integer(MaxBytes),
       MaxBytes >= 1, MaxBytes =< 4194304 ->
    case lists:all(fun(A) -> is_binary(A) andalso byte_size(A) =< 4096
                             andalso binary:match(A, <<0>>) =:= nomatch end, Args)
         andalso length(Args) =< 16 of
        false -> {error, <<"invalid_request">>};
        true ->
            case telegram_verify_loader_ffi:file_sha256(Guardian, ?GUARDIAN_MAX_BYTES) of
                {ok, GuardianSha} -> spawn_guardian(Guardian, Exe, ExeSha, Args,
                                                    DeadlineMs, MaxBytes);
                {ok, _} -> {error, <<"guardian_pin_mismatch">>};
                {error, E} -> {error, <<"guardian_", E/binary>>}
            end
    end;
run(_, _, _, _, _, _, _) -> {error, <<"invalid_request">>}.

spawn_guardian(Guardian, Exe, ExeSha, Args, DeadlineMs, MaxBytes) ->
    Argv = [<<"--exe">>, Exe, <<"--sha256">>, ExeSha,
            <<"--deadline-ms">>, integer_to_binary(DeadlineMs),
            <<"--max-bytes">>, integer_to_binary(MaxBytes), <<"--">> | Args],
    Started = erlang:monotonic_time(millisecond),
    Port = erlang:open_port({spawn_executable, binary_to_list(Guardian)},
                            [stream, binary, exit_status, use_stdio,
                             {args, [binary_to_list(A) || A <- Argv]}]),
    Cap = MaxBytes + ?RECEIPT_OVERHEAD,
    Until = Started + DeadlineMs + ?REAP_GRACE_MS,
    case collect(Port, Until, <<>>, Cap) of
        {exited, Code, Acc} ->
            Elapsed = erlang:monotonic_time(millisecond) - Started,
            interpret(Code, Acc, MaxBytes, Elapsed);
        {no_exit, Acc} ->
            %% E3 abort without closing, then a bounded wait for exit.
            _ = (catch erlang:port_command(Port, <<"A">>)),
            Grace = erlang:monotonic_time(millisecond) + ?ABORT_GRACE_MS,
            case collect(Port, Grace, Acc, Cap) of
                {exited, _Code, _} -> {error, <<"guardian_overran_deadline">>};
                {no_exit, _} ->
                    _ = (catch erlang:port_close(Port)),
                    {error, <<"cleanup_unknown">>}
            end
    end.

%% Bounded accumulation: bytes past the cap are dropped while still waiting
%% for exit_status, so an over-producing guardian cannot exhaust memory.
collect(Port, Until, Acc, Cap) ->
    Left = Until - erlang:monotonic_time(millisecond),
    case Left =< 0 of
        true -> {no_exit, Acc};
        false ->
            receive
                {Port, {data, C}} ->
                    Keep = max(0, min(byte_size(C), Cap - byte_size(Acc))),
                    collect(Port, Until, <<Acc/binary, (binary:part(C, 0, Keep))/binary>>, Cap);
                {Port, {exit_status, Code}} -> {exited, Code, Acc}
            after Left -> {no_exit, Acc}
            end
    end.

interpret(Code, Acc, MaxBytes, Elapsed) ->
    case binary:match(Acc, <<"\n">>) of
        nomatch -> {error, <<"guardian_receipt_missing">>};
        {Pos, 1} when Pos > ?RECEIPT_OVERHEAD -> {error, <<"guardian_receipt_too_large">>};
        {Pos, 1} ->
            Line = binary:part(Acc, 0, Pos),
            Payload = binary:part(Acc, Pos + 1, byte_size(Acc) - Pos - 1),
            case catch json:decode(Line) of
                #{<<"guardian">> := ?MARKER} = M -> check(Code, M, Payload, MaxBytes, Elapsed);
                #{<<"guardian">> := _} -> {error, <<"guardian_marker_mismatch">>};
                _ -> {error, <<"guardian_receipt_unparsable">>}
            end
    end.

check(Code, M, Payload, MaxBytes, Elapsed) ->
    Result = maps:get(<<"result">>, M, none),
    Cleanup = maps:get(<<"cleanup">>, M, none),
    ChildExit = maps:get(<<"child_exit">>, M, -1),
    Declared = maps:get(<<"output_bytes">>, M, -1),
    Sha = maps:get(<<"output_sha256">>, M, none),
    Truncated = maps:get(<<"truncated">>, M, none),
    Actual = binary:encode_hex(crypto:hash(sha256, Payload), lowercase),
    Paired =
        case {Code, Result, Cleanup} of
            {0, <<"child_exited">>, <<"confirmed">>} -> ChildExit =:= 0;
            {3, <<"child_exited">>, <<"confirmed">>} ->
                is_integer(ChildExit) andalso ChildExit >= 1 andalso ChildExit =< 255;
            {3, <<"refused">>, <<"n/a">>} ->
                lists:member(maps:get(<<"reason">>, M, none), ?PRELAUNCH);
            {4, <<"killed_deadline">>, <<"confirmed">>} -> true;
            {5, <<"killed_parent_eof">>, <<"confirmed">>} -> true;
            {6, <<"killed_output_bound">>, <<"confirmed">>} -> true;
            {7, <<"child_signalled">>, <<"confirmed">>} -> true;
            _ -> false
        end,
    if
        not Paired -> {error, <<"cleanup_unknown">>};
        Declared =/= byte_size(Payload) -> {error, <<"guardian_output_bytes_mismatch">>};
        byte_size(Payload) > MaxBytes -> {error, <<"output_exceeds_bound">>};
        Sha =/= Actual -> {error, <<"guardian_output_digest_mismatch">>};
        not is_boolean(Truncated) -> {error, <<"guardian_receipt_unparsable">>};
        Result =:= <<"refused">> ->
            {error, <<"refused:", (maps:get(<<"reason">>, M))/binary>>};
        true ->
            Exit = case is_integer(ChildExit) of true -> ChildExit; false -> -1 end,
            {ok, {observation, Result, Exit, Payload, Actual, Truncated, Elapsed}}
    end.

%% Exclusive, fsynced creation of an evidence file; never overwrites.
%% Exclusive and atomic: the bytes are written and synced to a sibling temp
%% file created exclusively, then renamed over the final name only if that
%% name does not exist yet. A crash mid-write leaves a .tmp file, never a
%% truncated receipt that a reconciler could mistake for Complete.
write_new(Path, Bytes) when is_binary(Path), is_binary(Bytes) ->
    Tmp = <<Path/binary, ".tmp">>,
    case file:read_file_info(Path) of
        {ok, _} -> {error, <<"evidence_exists">>};
        {error, enoent} ->
            case file:open(Tmp, [write, binary, raw, exclusive]) of
                {ok, Fd} ->
                    R = case file:write(Fd, Bytes) of
                            ok -> file:sync(Fd);
                            E -> E
                        end,
                    _ = file:close(Fd),
                    case R of
                        ok ->
                            case file:read_file_info(Path) of
                                {error, enoent} ->
                                    case file:rename(Tmp, Path) of
                                        ok -> {ok, nil};
                                        _ -> _ = file:delete(Tmp),
                                             {error, <<"evidence_write_failed">>}
                                    end;
                                _ -> _ = file:delete(Tmp),
                                     {error, <<"evidence_exists">>}
                            end;
                        _ -> _ = file:delete(Tmp),
                             {error, <<"evidence_write_failed">>}
                    end;
                {error, eexist} -> {error, <<"evidence_exists">>};
                {error, _} -> {error, <<"evidence_create_failed">>}
            end;
        {error, _} -> {error, <<"evidence_create_failed">>}
    end.

%% Creates a new evidence directory; an existing one is refused so two runs
%% can never share or overwrite evidence.
make_dir(Path) when is_binary(Path) ->
    case file:make_dir(Path) of
        ok -> {ok, nil};
        {error, _} -> {error, nil}
    end.
