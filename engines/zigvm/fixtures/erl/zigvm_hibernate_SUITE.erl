%% zigvm_hibernate_SUITE — a PURE-BUT-CONCURRENT subset of
%% erts/emulator/test/hibernate_SUITE in the common_test SUITE shape (`all/0` +
%% `Case(Config)` funs) with NO common_test / test_server dependency (the real
%% suite `-include_lib("common_test/include/ct.hrl")` and leans on heap-size /
%% current_function / trace observations that are out of scope here). Every
%% case exercises `erlang:hibernate/3` re-entry semantics the zigvm
%% scheduler-as-driver executes END-TO-END from a compiled `.beam` (E7.5
%% doHibernate, the `phibernate` corpus precedent): hibernate DISCARDS the call
%% stack (even a surrounding try/catch frame — hibernate never "returns") and
%% RE-ENTERS M:F/A on the next delivered message with the MAILBOX PRESERVED.
%% A case returns the atom `true` on success; the runner
%% (zigvm_hibernate_suite_runner) counts a case EQ only when BOTH VMs'
%% `Suite:Case([])` returns `true`.
%%
%% Observation discipline: ordering/delivery facts ONLY — no heap sizes, no
%% process_info beyond what the driver models, no wall-clock durations (the
%% virtual clock makes `receive after N` fire deterministically; elapsed-time
%% VALUES are never compared). Every case is self-contained: children are
%% monitored to observed termination, receives are bounded (`after 1000` -> a
%% bug is a false return, never a hang), and the mailbox is flushed before
%% returning so no leftover message can poison the next case.
%%
%% SCOPE HONESTY (probed on the zigvm CLI against the pinned OTP-30 oracle
%% before inclusion; probe = zprobe_hib*.erl, 2026-07-23):
%%   - `erlang:hibernate/0` (the OTP in-place variant, hibernate_SUITE
%%     `in_place`) is UNIMPLEMENTED on zigvm (child exits `undef`; oracle
%%     resumes in place) -> EXCLUDED.
%%   - `erlang:hibernate(xx, name, glurf)` (non-LIST Args) raises a catchable
%%     `badarg` on the oracle but KILLS the zigvm caller with `undef` (would
%%     kill the shared runner process, breaking every later case) -> that one
%%     variant is EXCLUDED from c_bad_args; the atom/tuple/list/float
%%     module/function variants probed EQ (`badarg`) and are included.
%%   - c_undefined_mfa is INCLUDED but KNOWN-DIVERGENT: the oracle's exit
%%     reason is `{undef,[{M,F,A,_}|_]}` (stacktrace-carrying) where zigvm's is
%%     the bare atom `undef` — reported for integrator triage, not censored.
%%   - Heap-size assertions (maximum_hibernate_heap_size, min_heap_size,
%%     no_heap), erlang:trace-based cases, and dirty-scheduler cases
%%     (stuck_dirty_hibernate) of the real suite are out of scope by rule.
-module(zigvm_hibernate_SUITE).

-export([all/0, id/1,
         c_wake_by_send/1, c_stack_discard/1, c_mailbox_preserved/1,
         c_multi_queued/1, c_hibernate_loop/1, c_state_args/1,
         c_dynamic_call/1, c_selective_wake/1, c_receive_after_in_wake/1,
         c_timer_wake/1, c_exit_hibernated/1, c_bad_args/1,
         c_undefined_mfa/1,
         %% spawned entry points + hibernate re-entry targets (exported so
         %% spawn/3's and hibernate/3's MFA resolve).
         ps_hib/1, hib_wake/1,
         ps_nr/1, nr_wake/1,
         ps_queue/2, queue_restart/2,
         ps_multi/1, multi_wake/1,
         ps_loop/1, loop_wake/1,
         ps_args/2, args_wake/2,
         ps_dyn/1,
         ps_sel/1, sel_wake/1,
         ps_timo/1, timo_wake/1,
         ps_sleep/0, sleep_wake/0,
         ps_undef/0]).

%% The suite manifest (common_test `all/0` contract). MIRRORED in order by
%% harness/suite_runner.ml's case_names (ncases/1 lockstep).
all() ->
    [c_wake_by_send, c_stack_discard, c_mailbox_preserved,
     c_multi_queued, c_hibernate_loop, c_state_args,
     c_dynamic_call, c_selective_wake, c_receive_after_in_wake,
     c_timer_wake, c_exit_hibernated, c_bad_args,
     c_undefined_mfa].

%% Exported identity: routes pure-value operands through a remote call so
%% constant folding cannot bypass the VM.
id(X) -> X.

%% --- basic wake-by-send (hibernate_SUITE `basic`-class) -------------------
%% A hibernated child wakes on a delivered message and RE-ENTERS M:F/A; the
%% waking message itself is what the re-entered function receives. Terminal
%% 'DOWN' proves the child ended (normal) after its re-entered function
%% returned.
c_wake_by_send(_) ->
    {P, Ref} = spawn_monitor(?MODULE, ps_hib, [self()]),
    P ! ?MODULE:id(ping),
    R1 = receive {woke, ping} -> true after 1000 -> timeout end,
    R2 = receive {'DOWN', Ref, process, P, normal} -> true
         after 1000 -> timeout end,
    flush(),
    (R1 =:= true) andalso (R2 =:= true).

ps_hib(Parent) -> erlang:hibernate(?MODULE, hib_wake, [Parent]).
hib_wake(Parent) -> receive M -> Parent ! {woke, M} end.

%% --- hibernate never returns (basic_hibernator `hibernate_returned`) ------
%% hibernate/3 DISCARDS the call stack including a surrounding try frame: the
%% code after the hibernate call is unreachable, so `{returned,_}` must never
%% arrive — even after the child's death ('DOWN' orders after every message the
%% child sent, so the `after 0` probe is race-free).
c_stack_discard(_) ->
    {P, Ref} = spawn_monitor(?MODULE, ps_nr, [self()]),
    P ! ping,
    R1 = receive woke -> true after 1000 -> timeout end,
    R2 = receive {'DOWN', Ref, process, P, normal} -> true
         after 1000 -> timeout end,
    R3 = receive {returned, _} -> hibernate_returned after 0 -> true end,
    flush(),
    (R1 =:= true) andalso (R2 =:= true) andalso (R3 =:= true).

ps_nr(Parent) ->
    try erlang:hibernate(?MODULE, nr_wake, [Parent]) of
        X -> Parent ! {returned, X}
    catch C:R -> Parent ! {returned, {C, R}}
    end.
nr_wake(Parent) -> receive ping -> Parent ! woke end.

%% --- mailbox preserved across hibernate (`messages_in_queue`-class) -------
%% A message queued BEFORE the hibernate call survives it: the child
%% selectively receives `go_ahead` (leaving Msg queued), hibernates, wakes
%% immediately (non-empty queue), and the re-entered function receives exactly
%% the pre-hibernate Msg.
c_mailbox_preserved(_) ->
    Ref = make_ref(),
    Msg = {self(), Ref, ?MODULE:id(a), message},
    {P, Mon} = spawn_monitor(?MODULE, ps_queue, [self(), Msg]),
    P ! Msg,
    P ! go_ahead,
    R1 = receive done -> true after 1000 -> timeout end,
    R2 = receive {'DOWN', Mon, process, P, normal} -> true
         after 1000 -> timeout end,
    flush(),
    (R1 =:= true) andalso (R2 =:= true).

ps_queue(Parent, Msg) ->
    receive go_ahead -> ok end,
    erlang:hibernate(?MODULE, queue_restart, [Parent, Msg]).
queue_restart(Parent, Expected) ->
    receive Expected -> Parent ! done end.

%% --- multiple queued messages preserved IN ORDER --------------------------
%% Three messages queued before hibernate are received after re-entry in FIFO
%% order.
c_multi_queued(_) ->
    {P, Mon} = spawn_monitor(?MODULE, ps_multi, [self()]),
    P ! {m, ?MODULE:id(1)},
    P ! {m, 2},
    P ! {m, 3},
    P ! go,
    R1 = receive {order, L} -> L =:= [1, 2, 3] after 1000 -> timeout end,
    R2 = receive {'DOWN', Mon, process, P, normal} -> true
         after 1000 -> timeout end,
    flush(),
    (R1 =:= true) andalso (R2 =:= true).

ps_multi(Parent) ->
    receive go -> ok end,
    erlang:hibernate(?MODULE, multi_wake, [Parent]).
multi_wake(Parent) ->
    A = receive {m, X} -> X end,
    B = receive {m, Y} -> Y end,
    C = receive {m, Z} -> Z end,
    Parent ! {order, [A, B, C]}.

%% --- several hibernate/wake rounds (`hibernate_wake_up` loop-class) -------
%% The wake function re-hibernates to itself after every pong: 5 rounds of
%% ping/pong, then a quit wake that ends the child normally.
c_hibernate_loop(_) ->
    {P, Mon} = spawn_monitor(?MODULE, ps_loop, [self()]),
    R1 = rounds(P, 1, 5),
    P ! quit,
    R2 = receive {'DOWN', Mon, process, P, normal} -> true
         after 1000 -> timeout end,
    flush(),
    (R1 =:= true) andalso (R2 =:= true).

rounds(_, K, Max) when K > Max -> true;
rounds(P, K, Max) ->
    P ! {ping, K},
    receive {pong, K} -> rounds(P, K + 1, Max)
    after 1000 -> {timeout_round, K}
    end.

ps_loop(Parent) -> erlang:hibernate(?MODULE, loop_wake, [Parent]).
loop_wake(Parent) ->
    receive
        {ping, K} ->
            Parent ! {pong, K},
            erlang:hibernate(?MODULE, loop_wake, [Parent]);
        quit -> ok
    end.

%% --- hibernate args survive the stack discard -----------------------------
%% The A of hibernate(M, F, A) is live data carried through the discard: a
%% compound term (list/map/binary/atom) round-trips exactly (=:=) through
%% hibernation.
c_state_args(_) ->
    T = {?MODULE:id([1, 2, 3]), #{k => ?MODULE:id(v)}, <<1, 2, 3>>,
         ?MODULE:id(atom_x)},
    {P, Mon} = spawn_monitor(?MODULE, ps_args, [self(), T]),
    P ! go,
    R1 = receive {carried, Got} -> Got =:= T after 1000 -> timeout end,
    R2 = receive {'DOWN', Mon, process, P, normal} -> true
         after 1000 -> timeout end,
    flush(),
    (R1 =:= true) andalso (R2 =:= true).

ps_args(Parent, Term) -> erlang:hibernate(?MODULE, args_wake, [Parent, Term]).
args_wake(Parent, Term) -> receive go -> Parent ! {carried, Term} end.

%% --- dynamic call (hibernate_SUITE `dynamic_call`-class) ------------------
%% apply(erlang, hibernate, [M,F,A]) through a VARIABLE function name — the
%% path the compiler/loader cannot translate to the hibernate instruction —
%% behaves identically to the direct call.
c_dynamic_call(_) ->
    {P, Mon} = spawn_monitor(?MODULE, ps_dyn, [self()]),
    P ! ping,
    R1 = receive {woke, ping} -> true after 1000 -> timeout end,
    R2 = receive {'DOWN', Mon, process, P, normal} -> true
         after 1000 -> timeout end,
    flush(),
    (R1 =:= true) andalso (R2 =:= true).

ps_dyn(Parent) ->
    F = ?MODULE:id(hibernate),
    apply(erlang, F, [?MODULE, hib_wake, [Parent]]).

%% --- selective receive after re-entry -------------------------------------
%% The re-entered function selectively receives `{want,_}` PAST two earlier
%% queued messages; the skipped messages remain queued in order for later
%% receives. (The first delivered message — junk1 — is what wakes the child.)
c_selective_wake(_) ->
    {P, Mon} = spawn_monitor(?MODULE, ps_sel, [self()]),
    P ! junk1,
    P ! {want, ?MODULE:id(7)},
    P ! junk2,
    R1 = receive {got, 7} -> true after 1000 -> timeout end,
    R2 = receive {rest, [junk1, junk2]} -> true after 1000 -> timeout end,
    R3 = receive {'DOWN', Mon, process, P, normal} -> true
         after 1000 -> timeout end,
    flush(),
    (R1 =:= true) andalso (R2 =:= true) andalso (R3 =:= true).

ps_sel(Parent) -> erlang:hibernate(?MODULE, sel_wake, [Parent]).
sel_wake(Parent) ->
    R = receive {want, X} -> X end,
    Parent ! {got, R},
    A = receive M1 -> M1 end,
    B = receive M2 -> M2 end,
    Parent ! {rest, [A, B]}.

%% --- `receive after N` inside the re-entered function ---------------------
%% The virtual clock fires a bounded receive deterministically after re-entry:
%% the timeout BRANCH is the observable (never an elapsed-time value).
c_receive_after_in_wake(_) ->
    {P, Mon} = spawn_monitor(?MODULE, ps_timo, [self()]),
    P ! go,
    R1 = receive {r, timed_out} -> true after 1000 -> timeout end,
    R2 = receive {'DOWN', Mon, process, P, normal} -> true
         after 1000 -> timeout end,
    flush(),
    (R1 =:= true) andalso (R2 =:= true).

ps_timo(Parent) -> erlang:hibernate(?MODULE, timo_wake, [Parent]).
timo_wake(Parent) ->
    receive go -> ok end,
    R = receive never_sent -> no after 30 -> timed_out end,
    Parent ! {r, R}.

%% --- timer-message wake (send_after) --------------------------------------
%% An erlang:send_after timer message is an ordinary delivery: it wakes the
%% hibernated child exactly like a direct send.
c_timer_wake(_) ->
    {P, Mon} = spawn_monitor(?MODULE, ps_hib, [self()]),
    _T = erlang:send_after(30, P, tick),
    R1 = receive {woke, tick} -> true after 1000 -> timeout end,
    R2 = receive {'DOWN', Mon, process, P, normal} -> true
         after 1000 -> timeout end,
    flush(),
    (R1 =:= true) andalso (R2 =:= true).

%% --- exit/2 reaches a hibernated process ----------------------------------
%% A hibernated (waiting) process is killable: exit(P, boom) on the
%% non-trapping child yields 'DOWN' with exactly reason boom.
c_exit_hibernated(_) ->
    {P, Mon} = spawn_monitor(?MODULE, ps_sleep, []),
    exit(P, ?MODULE:id(boom)),
    R = receive {'DOWN', Mon, process, P, boom} -> true
        after 1000 -> timeout end,
    flush(),
    R =:= true.

ps_sleep() -> erlang:hibernate(?MODULE, sleep_wake, []).
sleep_wake() -> receive never -> ok end.

%% --- bad arguments (hibernate_SUITE `bad_args`-class, probed-EQ subset) ---
%% Non-atom module/function arguments raise a CATCHABLE badarg in the caller,
%% which survives. The non-LIST Args variant (`glurf`) is EXCLUDED: probed
%% DIVERGENT (oracle badarg vs zigvm caller-killing undef — see module head).
c_bad_args(_) ->
    ba(?MODULE:id(42), name, [0]) andalso
        ba(xx, ?MODULE:id(42), [1]) andalso
        ba({1, 2, 3}, name, [4]) andalso
        ba([1, 2], name, [9]) andalso
        ba(55.0, name, [9]).

ba(M, F, A) ->
    try erlang:hibernate(M, F, A) of
        _ -> false
    catch
        error:badarg -> true;
        _:_ -> false
    end.

%% --- undefined MFA (hibernate_SUITE `undefined_mfa`-class) ----------------
%% KNOWN-DIVERGENT (kept deliberately — see module head): hibernating to an
%% undefined MFA must exit the process with an `{undef,_}` (stacktrace-shaped)
%% reason once it wakes. The oracle delivers {'EXIT',P,{undef,[...]}}; zigvm
%% currently delivers the bare atom `undef` -> this case returns false there.
c_undefined_mfa(_) ->
    %% Best-effort: silence the oracle's asynchronous "Error in process" crash
    %% report (it goes to STDOUT under -noshell and would otherwise pollute the
    %% byte-compared output with a timestamped report). Guarded: on zigvm the
    %% logger module is not linked -> undef -> caught -> no-op.
    _ = try logger:remove_handler(default) catch _:_ -> ok end,
    Prev = process_flag(trap_exit, true),
    P = spawn_link(?MODULE, ps_undef, []),
    P ! {a, message},
    R = receive
            {'EXIT', P, {undef, _}} -> true;
            {'EXIT', P, _Other} -> wrong_reason
        after 1000 -> timeout
        end,
    flush(),
    process_flag(trap_exit, Prev),
    R =:= true.

ps_undef() -> erlang:hibernate(?MODULE, blarf_does_not_exist, []).

%% --- local helpers --------------------------------------------------------
%% Drain the mailbox so no case can leak a message into the next one.
flush() -> receive _ -> flush() after 0 -> ok end.
