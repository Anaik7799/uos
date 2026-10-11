%% PRIVATE CANDIDATE adapter, iteration 5 (frozen handoff). Thin spawn transport.
%%
%% Layering after review:
%%   POLICY  -> gleam/src/observer_policy.gleam (pins, identity, deadline, argv)
%%   OWNED   -> src/obs_guardian.ml (fork, setsid, group SIGKILL, waitpid reap)
%%   ADAPTER -> this module: verify the GUARDIAN binary, spawn it, bound the
%%              wait, hand ownership to the caller, drain only own tags.
%%
%% The previous iteration (preserved as sa_plan_observer_ffi.ab87e5dd.FAILED)
%% tried to own the child from Erlang. It could not: port_close is not a signal,
%% so a blocking child persisted and the best it could report was
%% cleanup_unknown. That path is removed, not documented.
%%
%% Cancellation protocol, corrected after review:
%%   A1 ABORT IS SIGNALLED WITHOUT RELEASING OWNERSHIP. The adapter writes one
%%      byte to the guardian's control stdin. The guardian treats readiness on
%%      that channel as an abort: it SIGKILLs its child process group, reaps
%%      with waitpid, and exits. The port stays OPEN so the adapter still owns
%%      the os pid and still receives exit_status.
%%   A2 If the guardian does not exit within grace, the outcome is
%%      cleanup_unknown and NOTHING is signalled. Retaining an Erlang port does
%%      NOT pin the numeric OS pid against reuse: once the OS process has
%%      exited and been reaped the number can be recycled, and exit_status may
%%      already be queued. Signalling a remembered number could therefore hit
%%      an unrelated process. The kill fallback is REMOVED, not merely delayed.
%%   A3 Cleanup is confirmed only from a PARSED guardian receipt that says
%%      cleanup=confirmed together with an exit status consistent with it. An
%%      arbitrary exit code proves nothing: a crashed or signalled guardian
%%      cannot have reaped its child.
%%   REMOVED: the previous iteration closed the port FIRST, waited, and only
%%   then signalled the remembered os pid. After port_close the pid is no longer
%%   owned, so that signal could have hit an unrelated reused pid, and
%%   port_close may mean exit_status is never delivered at all. Both defects are
%%   gone; the old file is preserved as sa_plan_observer_ffi.2844fa2b.HOLD.
-module(sa_plan_observer_ffi).

-export([observe/1, observe_checked/1, observe_checked/5]).

-define(DIGEST_CHUNK, 65536).
-define(MAX_BINARY_BYTES, 134217728).
-define(GUARDIAN_EXIT_GRACE_MS, 1000).
-define(KILL_WAIT_MS, 250).
%% T1 the guardian marker must match EXACTLY; any other value is not our tool.
-define(GUARDIAN_MARKER, <<"uos.sa_plan.observer.guardian.v1">>).
%% T6 receipt overhead is bounded and accounted SEPARATELY from the payload
%% budget, so a maximum-size valid payload is not rejected by header bytes.
-define(RECEIPT_OVERHEAD_BYTES, 512).

%% observe_checked/1 is the entrypoint the Gleam policy calls. The argv is
%% built by Gleam from a checked request; the shape is re-validated here as
%% defence in depth so a direct Erlang caller cannot pass anything.
observe(#{guardian := GExe, guardian_sha256 := GSha, argv := Argv,
          deadline_ms := D, max_bytes := M}) when is_binary(GExe),
                                                  is_binary(GSha),
                                                  is_list(Argv),
                                                  is_integer(D), D >= 1, D =< 60000,
                                                  is_integer(M), M >= 1, M =< 4194304 ->
    Deadline = erlang:monotonic_time(millisecond) + D,
    Caller = self(),
    {R, RRef} = spawn_monitor(
                  fun() -> runner(Caller, GExe, GSha, Argv, Deadline, M) end),
    await_owned(R, RRef, Deadline, M);
observe(_) -> {error, <<"invalid_request">>}.

%% Typed entrypoint for the Gleam policy. Re-validates the argv shape.
observe_checked(Req) ->
    case validate_argv(Req) of
        {error, E} -> {error, E};
        ok -> observe(Req)
    end.

validate_argv(#{argv := Argv, deadline_ms := D, max_bytes := M})
  when is_list(Argv), is_integer(D), is_integer(M) ->
    case D >= 1 andalso D =< 60000 andalso M >= 1 andalso M =< 4194304 of
        false -> {error, <<"invalid_request">>};
        true ->
            case length(Argv) >= 8 andalso length(Argv) =< 40
                 andalso lists:all(fun(A) -> is_binary(A) andalso byte_size(A) =< 4096 end, Argv) of
                false -> {error, <<"invalid_request">>};
                true -> ok
            end
    end;
validate_argv(_) -> {error, <<"invalid_request">>}.

%% Arity-5 form so the Gleam policy binds it with typed arguments instead of
%% constructing an Erlang map.
observe_checked(GExe, GSha, Argv, D, M) ->
    observe_checked(#{guardian => GExe, guardian_sha256 => GSha,
                      argv => Argv, deadline_ms => D, max_bytes => M}).

%% Ownership handoff: the caller learns the exact port and os pid BEFORE the
%% runner starts collecting, so runner death does not leave an untracked child.
await_owned(R, RRef, Deadline, Max) ->
    Wait = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {owned, R, Port, OsPid} -> await_result(R, RRef, Port, OsPid, Deadline, Max);
        {obs_result, R, Res} -> demonitor(RRef, [flush]), _ = drain(R), Res;
        {'DOWN', RRef, process, R, _} -> _ = drain(R), {error, <<"adapter_failed">>}
    after Wait ->
        exit(R, kill),
        receive {'DOWN', RRef, process, R, _} -> ok
        after ?KILL_WAIT_MS -> demonitor(RRef, [flush]), ok end,
        case drain(R) of
            {owned, Port, OsPid} ->
                %% Late handoff: the caller aborts what it just learned about.
                _ = abort_owned(Port, OsPid, Max, <<>>),
                {error, <<"cleanup_unknown">>};
            none -> {error, <<"timeout">>}
        end
    end.

await_result(R, RRef, Port, OsPid, Deadline, Max) ->
    Wait = max(0, Deadline - erlang:monotonic_time(millisecond))
           + ?GUARDIAN_EXIT_GRACE_MS + ?KILL_WAIT_MS,
    receive
        {obs_result, R, Res} -> demonitor(RRef, [flush]), _ = drain(R), Res;
        {'DOWN', RRef, process, R, _} ->
            _ = drain(R),
            case abort_owned(Port, OsPid, Max, <<>>) of
                confirmed -> {error, <<"adapter_failed">>};
                unknown -> {error, <<"cleanup_unknown">>}
            end
    after Wait ->
        exit(R, kill),
        receive {'DOWN', RRef, process, R, _} -> ok
        after ?KILL_WAIT_MS -> demonitor(RRef, [flush]), ok end,
        _ = drain(R),
        case abort_owned(Port, OsPid, Max, <<>>) of
            confirmed -> {error, <<"timeout">>};
            unknown -> {error, <<"cleanup_unknown">>}
        end
    end.

%% Consume ONLY this runner's tagged messages.
drain(R) -> drain(R, none).
drain(R, Acc) ->
    receive
        {owned, R, P, O} -> drain(R, {owned, P, O});
        {obs_result, R, _} -> drain(R, Acc)
    after 0 -> Acc
    end.

%% ---------------------------------------------------------------- runner
runner(Caller, GExe, GSha, Argv, Deadline, Max) ->
    CallerRef = monitor(process, Caller),
    %% Digest work happens HERE, in the owned worker, bounded, with the
    %% deadline live and a regular-file plus size check.
    case digest_bounded(GExe, GSha, Deadline) of
        {error, E} -> Caller ! {obs_result, self(), {error, E}}, exit(normal);
        ok ->
            %% Re-check immediately before spawning.
            case erlang:monotonic_time(millisecond) >= Deadline of
                true ->
                    Caller ! {obs_result, self(), {error, <<"deadline_before_spawn">>}},
                    exit(normal);
                false ->
                    Port = erlang:open_port(
                             {spawn_executable, binary_to_list(GExe)},
                             [stream, use_stdio, exit_status, binary,
                              {args, [binary_to_list(A) || A <- Argv]}]),
                    OsPid = case erlang:port_info(Port, os_pid) of
                                {os_pid, P} -> P; _ -> undefined
                            end,
                    Caller ! {owned, self(), Port, OsPid},
                    Res = collect(Port, OsPid, Deadline, Max, <<>>),
                    Caller ! {obs_result, self(), Res},
                    demonitor(CallerRef, [flush]),
                    exit(normal)
            end
    end.

digest_bounded(Exe, Expected, Deadline) ->
    case file:read_file_info(binary_to_list(Exe)) of
        {error, _} -> {error, <<"exe_unreadable">>};
        {ok, FI} ->
            case {element(3, FI), element(2, FI)} of
                {regular, Size} when Size =< ?MAX_BINARY_BYTES ->
                    case file:open(binary_to_list(Exe), [read, binary, raw]) of
                        {error, _} -> {error, <<"exe_unreadable">>};
                        {ok, Fd} ->
                            R = hash_loop(Fd, crypto:hash_init(sha256), Deadline),
                            _ = file:close(Fd),
                            case R of
                                {error, E} -> {error, E};
                                {ok, Ctx} ->
                                    Hex = list_to_binary(
                                            [io_lib:format("~2.16.0b", [B])
                                             || <<B>> <= crypto:hash_final(Ctx)]),
                                    case Hex =:= Expected of
                                        true -> ok;
                                        false -> {error, <<"exe_digest_mismatch">>}
                                    end
                            end
                    end;
                {regular, _} -> {error, <<"exe_too_large">>};
                _ -> {error, <<"exe_not_regular_file">>}
            end
    end.

hash_loop(Fd, Ctx, Deadline) ->
    case erlang:monotonic_time(millisecond) >= Deadline of
        true -> {error, <<"deadline_during_digest">>};
        false ->
            case file:read(Fd, ?DIGEST_CHUNK) of
                eof -> {ok, Ctx};
                {ok, Bin} -> hash_loop(Fd, crypto:hash_update(Ctx, Bin), Deadline);
                {error, _} -> {error, <<"exe_unreadable">>}
            end
    end.

collect(Port, OsPid, Deadline, Max, Acc) ->
    Remaining = Deadline - erlang:monotonic_time(millisecond),
    case Remaining =< 0 of
        true -> finish_cancel(Port, OsPid, <<"timeout">>, Max, Acc);
        false ->
            receive
                {Port, {data, Chunk}} ->
                    New = <<Acc/binary, Chunk/binary>>,
                    case byte_size(New) > Max + ?RECEIPT_OVERHEAD_BYTES of
                        true ->
                            finish_cancel(Port, OsPid, <<"output_exceeds_bound">>,
                                          Max, New);
                        false -> collect(Port, OsPid, Deadline, Max, New)
                    end;
                {Port, {exit_status, Code}} -> interpret(Code, Acc, Max);
                {'DOWN', _, process, _, _} ->
                    finish_cancel(Port, OsPid, <<"caller_died">>, Max, Acc)
            after Remaining -> finish_cancel(Port, OsPid, <<"timeout">>, Max, Acc)
            end
    end.

%% T5 the bytes already collected are carried in, so a receipt that arrived
%% before the deadline is not lost.
finish_cancel(Port, OsPid, Reason, Max, Acc) ->
    case abort_owned(Port, OsPid, Max, Acc) of
        confirmed -> {error, Reason};
        unknown -> {error, <<"cleanup_unknown">>}
    end.

%% A1/A3. Signal abort on the control channel WITHOUT closing, then keep
%% reading until the guardian exits, so its receipt is captured.
abort_owned(Port, _OsPid, Max, Acc0) ->
    _ = (try erlang:port_command(Port, <<"A">>) catch _:_ -> ok end),
    Deadline = erlang:monotonic_time(millisecond) + ?GUARDIAN_EXIT_GRACE_MS,
    Cap = Max + ?RECEIPT_OVERHEAD_BYTES,
    Prefix = binary:part(Acc0, 0, min(byte_size(Acc0), Cap)),
    case drain_until_exit(Port, Deadline, Prefix, Cap) of
        {exited, Code, Acc} ->
            close_quietly(Port),
            %% A3 EXACT pairing. A code set is not enough: the receipt must say
            %% cleanup=confirmed AND its result must be the one that code means.
            %% An independent falsifier used a guardian that read the abort and
            %% exited 77 without reaping; that must be cleanup_unknown.
            receipt_agrees(Code, Acc);
        {no_exit, _Acc} ->
            %% A2 nothing is signalled here. See the header.
            close_quietly(Port),
            unknown
    end.

%% T4 bounded: once the cap is reached further bytes are DROPPED rather than
%% accumulated, while still waiting for exit_status. The receipt is the first
%% line, so it is always within the retained prefix.
drain_until_exit(Port, Deadline, Acc, Cap) ->
    Left = Deadline - erlang:monotonic_time(millisecond),
    case Left =< 0 of
        true -> {no_exit, Acc};
        false ->
            receive
                {Port, {data, C}} ->
                    Next = case byte_size(Acc) >= Cap of
                               true -> Acc;
                               false ->
                                   Keep = min(byte_size(C), Cap - byte_size(Acc)),
                                   <<Acc/binary, (binary:part(C, 0, Keep))/binary>>
                           end,
                    drain_until_exit(Port, Deadline, Next, Cap);
                {Port, {exit_status, Code}} -> {exited, Code, Acc}
            after Left -> {no_exit, Acc}
            end
    end.

close_quietly(Port) -> _ = (try erlang:port_close(Port) catch _:_ -> ok end), ok.

%% ---------------------------------------------------------------- receipt
%% The guardian prints exactly one receipt line, then the child payload.
split_receipt(Bin) ->
    case binary:match(Bin, <<"\n">>) of
        nomatch -> {error, <<"guardian_receipt_missing">>};
        {Pos, 1} when Pos > ?RECEIPT_OVERHEAD_BYTES ->
            {error, <<"guardian_receipt_too_large">>};
        {Pos, 1} ->
            Line = binary:part(Bin, 0, Pos),
            Rest = binary:part(Bin, Pos + 1, byte_size(Bin) - Pos - 1),
            case catch json:decode(Line) of
                #{<<"guardian">> := ?GUARDIAN_MARKER} = M -> {ok, M, Rest};
                #{<<"guardian">> := _} -> {error, <<"guardian_marker_mismatch">>};
                _ -> {error, <<"guardian_receipt_unparsable">>}
            end
    end.

%% T7 EXIT CODE 3 IS OVERLOADED by the guardian and the two cases are not the
%% same fact:
%%   (a) Ok_exit(C) with C =/= 0 -> result=child_exited, cleanup=confirmed,
%%       child_exit=C. The observer ran and WAS REAPED; it simply exited
%%       nonzero, for example a wrong-plan refusal. Cleanup is genuinely
%%       confirmed and the outcome is an observer-level error.
%%   (b) Refused W -> result=refused, cleanup=n/a. The guardian refused before
%%       creating any child, so there is nothing to reap. cleanup=n/a is honest
%%       and is NOT unknown.
%% Treating both as "refused" rejected (a) as cleanup_unknown, which was a
%% truthfulness defect in the opposite direction from the earlier ones.
%%
%% classify/2 returns {Verdict, CleanupState} where Verdict is
%% {ok, Receipt} | {error, Code} and CleanupState is confirmed | no_child
%% | unknown.
classify(Code, M) ->
    Result = maps:get(<<"result">>, M, <<"?">>),
    Cleanup = maps:get(<<"cleanup">>, M, <<"?">>),
    ChildExit = maps:get(<<"child_exit">>, M, -1),
    case {Code, Result, Cleanup} of
        {0, <<"child_exited">>, <<"confirmed">>} when ChildExit =:= 0 ->
            {ok, confirmed};
        {3, <<"child_exited">>, <<"confirmed">>} when is_integer(ChildExit), ChildExit >= 1, ChildExit =< 255 ->
            {{error, <<"observer_failed">>}, confirmed};
        {3, <<"refused">>, <<"n/a">>} ->
            case lists:member(maps:get(<<"reason">>, M, <<>>),
                 [<<"exe_not_regular_file">>, <<"exe_too_large">>, <<"exe_unreadable">>,
                  <<"exe_digest_mismatch">>, <<"deadline_during_digest">>,
                  <<"deadline_before_spawn">>, <<"fork_failed">>]) of
                true -> {{error, <<"guardian_refusal">>}, no_child};
                false -> {{error, <<"cleanup_unknown">>}, unknown}
            end;
        {4, <<"killed_deadline">>, <<"confirmed">>} ->
            {{error, <<"guardian_killed_deadline">>}, confirmed};
        {5, <<"killed_parent_eof">>, <<"confirmed">>} ->
            {{error, <<"guardian_killed_parent_eof">>}, confirmed};
        {7, <<"child_signalled">>, <<"confirmed">>} ->
            {{error, <<"observer_signalled">>}, confirmed};
        %% G9 a reaped output-bound cancellation is confirmed, not n/a.
        {6, <<"killed_output_bound">>, <<"confirmed">>} ->
            {{error, <<"output_exceeds_bound">>}, confirmed};
        _ ->
            {{error, <<"cleanup_unknown">>}, unknown}
    end.

receipt_agrees(Code, Bin) ->
    case split_receipt(Bin) of
        {ok, M, _} ->
            case classify(Code, M) of
                {_, confirmed} -> confirmed;
                {_, no_child} -> confirmed;
                _ -> unknown
            end;
        _ -> unknown
    end.

%% A3 success requires the receipt to agree with the exit status.
interpret(Code, Acc, Max) ->
    case split_receipt(Acc) of
        {error, E} -> {error, E};
        {ok, M, Payload} ->
            Result = maps:get(<<"result">>, M, <<"?">>),
            Cleanup = maps:get(<<"cleanup">>, M, <<"?">>),
            ChildExit = maps:get(<<"child_exit">>, M, -1),
            Declared = maps:get(<<"output_bytes">>, M, -1),
            %% T2 the guardian must not under- or over-declare its payload.
            SizeOk = Declared =:= byte_size(Payload),
            %% T6 the payload alone is measured against the caller budget.
            WithinBudget = (Max =:= infinity) orelse (byte_size(Payload) =< Max),
            case classify(Code, M) of
                {ok, confirmed} when SizeOk, WithinBudget ->
                    {ok, {observation, Result, Cleanup, ChildExit, Payload}};
                {ok, confirmed} when not SizeOk ->
                    {error, <<"guardian_output_bytes_mismatch">>};
                {ok, confirmed} ->
                    {error, <<"output_exceeds_bound">>};
                {{error, E}, _} -> {error, E}
            end
    end.

%% guardian_error/2 is superseded by classify/2 and removed; the preserved
%% iteration 4 file retains it.

%% await_exit/2 and kill_os/1 are REMOVED. await_exit treated any exit code as
%% proof of cleanup, and kill_os signalled a remembered numeric pid that the
%% kernel may already have recycled. Both are preserved in
%% sa_plan_observer_ffi.it3.HOLD.preserved.erl.
