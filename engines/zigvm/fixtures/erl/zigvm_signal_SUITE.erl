%% zigvm_signal_SUITE — a PURE-BUT-CONCURRENT subset of
%% erts/emulator/test/signal_SUITE, in the common_test SUITE shape (`all/0` +
%% `Case(Config)` funs) but with NO common_test / test_server dependency
%% (CT-on-zigvm is Epoch E7). The real signal_SUITE is dominated by dirty
%% schedulers, drivers, distribution carriers, and multi-scheduler race
%% hammers; the curated cases below keep its exit-SIGNAL SEMANTICS — the part
%% the zigvm scheduler-as-driver executes end-to-end deterministically:
%%
%%   - exit/2 kills a non-trapping process (DOWN carries the exact reason);
%%   - trap_exit converts an exit/2 signal to {'EXIT', From, Reason};
%%   - exit(Pid, normal) is dropped by a live non-trapping process, but IS
%%     delivered as {'EXIT', From, normal} to a trapping one;
%%   - exit(Pid, kill) is untrappable, and the victim's reason is 'killed'
%%     (the kill2killed distinction: exit/1's `exit(kill)` stays 'kill');
%%   - exit(self(), Reason) while trapping delivers {'EXIT', Self, Reason};
%%   - link propagation of an abnormal exit; unlink severs it (no 'EXIT'
%%     after unlink/1 returns — the OTP-21+ unlink guarantee);
%%   - pairwise signal-order: an exit signal sent between message batches is
%%     received in order (signal_SUITE:xm_sig_order, single local shot);
%%   - signals to a dead pid: exit/2 returns true; monitor -> DOWN noproc.
%%
%% Every case is SELF-CONTAINED + DETERMINISTIC: children are always brought
%% to termination, every receive is bounded (`after 1000` — the zigvm virtual
%% clock fires it deterministically; a bug is a false return, never a hang),
%% and each case flushes its mailbox before returning so no residue can leak
%% into the next case. A case returns the atom `true` on success; the runner
%% (zigvm_signal_suite_runner) counts a case EQ only when BOTH VMs'
%% `Suite:Case([])` returns `true`. Pure-value operands that a compiler could
%% constant-fold are routed through the exported ?MODULE:id/1.
-module(zigvm_signal_SUITE).

-export([all/0,
         c_exit2_down_reason/1, c_exit2_trap_converts/1,
         c_exit2_normal_ignored/1, c_exit2_normal_trapped/1,
         c_exit2_kill/1, c_exit2_kill_trapping/1, c_kill2killed/1,
         c_exit_self_trap/1, c_link_exit_propagates/1, c_unlink_no_exit/1,
         c_sig_order/1, c_exit2_noproc/1,
         %% identity barrier + spawned entry points (exported so spawn/3's
         %% MFA resolves against the linked export index).
         id/1, sp_wait/0, sp_normal/0, sp_trap_echo/1, sp_pingpong/0,
         sp_boom_on_go/0, sp_exit1_kill/0, sp_exit2_self_kill/0,
         sp_sig_order/0, sp_bridge/1]).

%% The suite manifest (common_test `all/0` contract).
all() ->
    [c_exit2_down_reason, c_exit2_trap_converts,
     c_exit2_normal_ignored, c_exit2_normal_trapped,
     c_exit2_kill, c_exit2_kill_trapping, c_kill2killed,
     c_exit_self_trap, c_link_exit_propagates, c_unlink_no_exit,
     c_sig_order, c_exit2_noproc].

%% Constant-folding barrier.
id(X) -> X.

%% --- exit/2 kills a non-trapping process ----------------------------------
%% The victim is blocked in a plain receive; the monitor 'DOWN' carries the
%% EXACT exit/2 reason (not a wildcard).
c_exit2_down_reason(_) ->
    P = spawn(?MODULE, sp_wait, []),
    Ref = monitor(process, P),
    true = exit(P, ?MODULE:id(boom)),
    D = receive {'DOWN', Ref, process, P, R} -> R
        after 1000 -> exit(P, kill), timeout
        end,
    flush(),
    D =:= boom.

%% --- trap_exit converts exit/2 to {'EXIT', From, Reason} ------------------
%% The child traps FIRST, then signals readiness (so the exit/2 can never
%% race the flag), echoes the converted tuple back, and terminates normally.
c_exit2_trap_converts(_) ->
    {P, Ref} = spawn_monitor(?MODULE, sp_trap_echo, [self()]),
    Ready = receive {ready, P} -> ok after 1000 -> timeout end,
    true = exit(P, ?MODULE:id(sig_convert)),
    Echo = receive {got_exit, P, From, Reason} -> {From, Reason}
           after 1000 -> timeout
           end,
    Down = receive {'DOWN', Ref, process, P, R} -> R
           after 1000 -> exit(P, kill), timeout
           end,
    flush(),
    (Ready =:= ok) andalso (Echo =:= {self(), sig_convert})
        andalso (Down =:= normal).

%% --- exit(Pid, normal) is dropped by a live non-trapping process ----------
%% Proven WITHOUT wall-time: the normal signal and the subsequent ping are
%% pairwise-ordered from the same sender, so a pong PROVES the process
%% survived the normal signal. Then it is shut down cleanly (DOWN normal).
c_exit2_normal_ignored(_) ->
    P = spawn(?MODULE, sp_pingpong, []),
    Ref = monitor(process, P),
    true = exit(P, ?MODULE:id(normal)),
    P ! {ping, self()},
    Pong = receive {pong, P} -> pong after 1000 -> timeout end,
    P ! stop,
    Down = receive {'DOWN', Ref, process, P, R} -> R
           after 1000 -> exit(P, kill), timeout
           end,
    flush(),
    (Pong =:= pong) andalso (Down =:= normal).

%% --- ... but a TRAPPING process receives {'EXIT', From, normal} -----------
c_exit2_normal_trapped(_) ->
    {P, Ref} = spawn_monitor(?MODULE, sp_trap_echo, [self()]),
    Ready = receive {ready, P} -> ok after 1000 -> timeout end,
    true = exit(P, ?MODULE:id(normal)),
    Echo = receive {got_exit, P, From, Reason} -> {From, Reason}
           after 1000 -> timeout
           end,
    Down = receive {'DOWN', Ref, process, P, R} -> R
           after 1000 -> exit(P, kill), timeout
           end,
    flush(),
    (Ready =:= ok) andalso (Echo =:= {self(), normal})
        andalso (Down =:= normal).

%% --- exit(Pid, kill): non-trapping victim dies with reason 'killed' -------
c_exit2_kill(_) ->
    P = spawn(?MODULE, sp_wait, []),
    Ref = monitor(process, P),
    true = exit(P, ?MODULE:id(kill)),
    D = receive {'DOWN', Ref, process, P, R} -> R after 1000 -> timeout end,
    flush(),
    D =:= killed.

%% --- exit(Pid, kill) is UNTRAPPABLE ---------------------------------------
%% The child traps exits, yet the kill still terminates it with 'killed'
%% (a trapped conversion would instead echo and exit normally -> DOWN normal,
%% so the reason check alone discriminates).
c_exit2_kill_trapping(_) ->
    {P, Ref} = spawn_monitor(?MODULE, sp_trap_echo, [self()]),
    Ready = receive {ready, P} -> ok after 1000 -> timeout end,
    true = exit(P, ?MODULE:id(kill)),
    Down = receive {'DOWN', Ref, process, P, R} -> R
           after 1000 -> timeout
           end,
    flush(),
    (Ready =:= ok) andalso (Down =:= killed).

%% --- the kill2killed distinction (signal_SUITE:kill2killed, local) --------
%% exit/1 `exit(kill)` terminates with reason 'kill' (an exception, not a
%% signal); the SIGNAL path `exit(self(), kill)` terminates with 'killed'.
c_kill2killed(_) ->
    {P1, R1} = spawn_monitor(?MODULE, sp_exit1_kill, []),
    D1 = receive {'DOWN', R1, process, P1, Ra} -> Ra after 1000 -> timeout end,
    {P2, R2} = spawn_monitor(?MODULE, sp_exit2_self_kill, []),
    D2 = receive {'DOWN', R2, process, P2, Rb} -> Rb
         after 1000 -> exit(P2, kill), timeout
         end,
    flush(),
    (D1 =:= kill) andalso (D2 =:= killed).

%% --- exit(self(), Reason) while trapping ----------------------------------
%% Returns true and delivers {'EXIT', Self, Reason} to one's own mailbox.
c_exit_self_trap(_) ->
    _ = process_flag(trap_exit, true),
    True1 = exit(self(), ?MODULE:id(self_sig)),
    Self = self(),
    Got = receive {'EXIT', F, R} -> {F, R} after 1000 -> timeout end,
    _ = process_flag(trap_exit, false),
    flush(),
    (True1 =:= true) andalso (Got =:= {Self, self_sig}).

%% --- link propagation of an abnormal exit ---------------------------------
%% A (non-trapping) links B; exit(B, Reason) kills B and the link propagates
%% the SAME reason to A, observed via a monitor on A. Both children die.
c_link_exit_propagates(_) ->
    {A, ARef} = spawn_monitor(?MODULE, sp_bridge, [self()]),
    B = receive {bridge_ready, A, Bp} -> Bp after 1000 -> none end,
    true = exit(B, ?MODULE:id(prop_boom)),
    D = receive {'DOWN', ARef, process, A, R} -> R
        after 1000 -> exit(A, kill), exit(B, kill), timeout
        end,
    flush(),
    D =:= prop_boom.

%% --- unlink severs exit propagation ---------------------------------------
%% After unlink(P) returns, the trapping parent must NOT receive an 'EXIT'
%% for P's later abnormal death (OTP-21+ unlink guarantee); the death is
%% still observable via a monitor (DOWN boom).
c_unlink_no_exit(_) ->
    _ = process_flag(trap_exit, true),
    P = spawn_link(?MODULE, sp_boom_on_go, []),
    true = unlink(P),
    Ref = monitor(process, P),
    P ! go,
    Down = receive {'DOWN', Ref, process, P, R} -> R
           after 1000 -> exit(P, kill), timeout
           end,
    NoExit = receive {'EXIT', P, _} -> got_exit after 200 -> clean end,
    _ = process_flag(trap_exit, false),
    flush(),
    (Down =:= boom) andalso (NoExit =:= clean).

%% --- pairwise signal order (signal_SUITE:xm_sig_order, one local shot) ----
%% Three may_reach messages, then the exit signal, then three may_not_reach:
%% same-sender signal order guarantees the victim can never observe a
%% may_not_reach before the exit signal, so the DOWN reason MUST be
%% good_signal_order (the victim exits bad_signal_order otherwise).
c_sig_order(_) ->
    {P, Ref} = spawn_monitor(?MODULE, sp_sig_order, []),
    P ! may_reach, P ! may_reach, P ! may_reach,
    true = exit(P, ?MODULE:id(good_signal_order)),
    P ! may_not_reach, P ! may_not_reach, P ! may_not_reach,
    D = receive {'DOWN', Ref, process, P, R} -> R
        after 1000 -> exit(P, kill), timeout
        end,
    flush(),
    D =:= good_signal_order.

%% --- signals to a DEAD pid -------------------------------------------------
%% exit/2 on a terminated pid returns true (a no-op signal); a fresh monitor
%% on it delivers an immediate DOWN with reason noproc.
c_exit2_noproc(_) ->
    {P, Ref} = spawn_monitor(?MODULE, sp_normal, []),
    D1 = receive {'DOWN', Ref, process, P, R} -> R after 1000 -> timeout end,
    True1 = exit(P, ?MODULE:id(late_boom)),
    Ref2 = monitor(process, P),
    D2 = receive {'DOWN', Ref2, process, P, R2} -> R2 after 1000 -> timeout end,
    flush(),
    (D1 =:= normal) andalso (True1 =:= true) andalso (D2 =:= noproc).

%% --- spawned entry points -------------------------------------------------
sp_wait() -> receive sp_wait_never -> ok end.
sp_normal() -> ok.
sp_pingpong() ->
    receive
        {ping, From} -> From ! {pong, self()}, sp_pingpong();
        stop -> ok
    end.
sp_trap_echo(Parent) ->
    _ = process_flag(trap_exit, true),
    Parent ! {ready, self()},
    receive {'EXIT', From, Reason} -> Parent ! {got_exit, self(), From, Reason} end.
sp_boom_on_go() -> receive go -> exit(boom) end.
sp_exit1_kill() -> exit(kill).
sp_exit2_self_kill() ->
    true = exit(self(), kill),
    receive sp_k_never -> ok end.
sp_sig_order() ->
    receive
        may_not_reach -> exit(bad_signal_order);
        may_reach -> sp_sig_order()
    end.
sp_bridge(Parent) ->
    B = spawn_link(?MODULE, sp_wait, []),
    Parent ! {bridge_ready, self(), B},
    receive sp_bridge_never -> ok end.

%% --- local helpers --------------------------------------------------------
%% Mailbox hygiene: a leftover message must never leak into the NEXT case.
flush() -> receive _ -> flush() after 0 -> ok end.
