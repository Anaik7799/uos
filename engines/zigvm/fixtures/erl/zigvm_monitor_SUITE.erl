%% zigvm_monitor_SUITE — a curated PURE-BUT-CONCURRENT subset of erts
%% emulator monitor_SUITE (third_party/otp/erts/emulator/test/monitor_SUITE.erl)
%% in the common_test SUITE shape (`all/0` + `c_Case(Config)` boolean funs) with
%% NO common_test / test_server dependency. Every case exercises ONLY the
%% monitor/demonitor/DOWN semantics the zigvm scheduler-as-driver executes
%% identically to the pinned OTP-30 oracle, end-to-end from a compiled `.beam`:
%% monitor/2 + the 5-tuple 'DOWN' {'DOWN',Ref,process,Pid,Reason} on normal and
%% custom (immediate and compound) exit reasons, immediate DOWN noproc on an
%% already-dead target, demonitor/1 no-op/idempotence, demonitor(Ref,[flush])
%% purging an already-delivered DOWN, wrong-monitor-end demonitor as a true
%% no-op, spawn_monitor/1 atomicity, and the send-before-exit signal-order
%% guarantee (a message sent before death is received BEFORE the DOWN).
%%
%% Each case is SELF-CONTAINED + DETERMINISTIC: every spawned child terminates
%% within the case (self-exit, or exit/2 from the parent), no name stays
%% registered, and the mailbox is drained before returning. Bounded selective
%% `receive ... after N` is used so a bug is a false-return, never a hang (the
%% zigvm virtual clock fires `after` deterministically).
%%
%% SCOPE HONESTY (probed on the zigvm CLI before curation; the divergent
%% primitives are EXCLUDED here and reported to the integrator, not silently
%% dropped):
%%   - monitor(process, Name) / monitor(process, {Name,Node}) (named monitors,
%%     the mon_1 "named process" + named_down class): zigvm raises badarg —
%%     named-monitor targets are unimplemented. EXCLUDED.
%%   - demonitor(Ref, [info]) after the monitor fired: oracle returns false,
%%     zigvm returns true (the local_remove_monitor class). EXCLUDED.
%%   - demonitor arg validation: demonitor(make_ref(), flush) (option-list not
%%     a list) and demonitor(x, [flush]) (non-ref first arg) are badarg on the
%%     oracle but succeed (return true) on zigvm. EXCLUDED.
%%   - clause-less `receive after N -> ok end` sleeps while a message sits in
%%     the mailbox DEADLOCK zigvm (RunDidNotTerminate), so no case uses a
%%     clause-less sleep; the demonitor_flush case proves DOWN delivery through
%%     a second monitor's selective receive instead of the upstream suite's
%%     `receive after 100` pacing.
-module(zigvm_monitor_SUITE).

-export([all/0,
         c_mon_normal/1, c_mon_exit_reason/1, c_mon_noproc/1, c_mon_badarg/1,
         c_spawn_monitor/1,
         c_demon_fresh/1, c_demon_twice/1, c_demon_before_down/1,
         c_demonitor_flush/1, c_wrong_end_demon/1,
         c_msg_before_down/1, c_large_reason/1,
         %% exported so pure-value operands route through the VM (no
         %% compile-time constant folding of the observed terms).
         id/1]).

%% The suite manifest (common_test `all/0` contract). MIRRORED in order by the
%% harness suite_spec's case_names (the ncases/1 lockstep law).
all() ->
    [c_mon_normal, c_mon_exit_reason, c_mon_noproc, c_mon_badarg,
     c_spawn_monitor,
     c_demon_fresh, c_demon_twice, c_demon_before_down,
     c_demonitor_flush, c_wrong_end_demon,
     c_msg_before_down, c_large_reason].

%% Constant-folding firewall: pure-value operands pass through this exported
%% identity so the compiler cannot evaluate the observation at compile time.
id(X) -> X.

%% --- monitor/2 + 'DOWN' (mon_1-class) --------------------------------------

%% Normal case: monitor a live child, wake it, observe the full 5-tuple
%% 'DOWN' {'DOWN', R, process, P, normal} binding the SAME Ref and Pid.
c_mon_normal(_) ->
    P = spawn(fun () -> receive go -> ok end end),
    R = erlang:monitor(process, P),
    P ! go,
    receive {'DOWN', R, process, P, normal} -> true
    after 1000 -> false
    end.

%% 'DOWN' with another (immediate) reason: exit/2 on a monitored, NON-linked
%% child delivers {'DOWN', R, process, P, frop} — the exit signal reason is
%% carried into the DOWN verbatim.
c_mon_exit_reason(_) ->
    P = spawn(fun () -> receive never -> ok end end),
    R = erlang:monitor(process, P),
    exit(P, ?MODULE:id(frop)),
    receive {'DOWN', R, process, P, frop} -> true
    after 1000 -> false
    end.

%% Monitoring an already-dead pid delivers an immediate 'DOWN' with reason
%% noproc (the target's death is FIRST proven by its own monitor's DOWN, so
%% the second monitor observes a certainly-dead pid — no timing race).
c_mon_noproc(_) ->
    {P, R0} = spawn_monitor(fun () -> ok end),
    Dead = receive {'DOWN', R0, process, P, normal} -> true
           after 1000 -> false
           end,
    R = erlang:monitor(process, P),
    Dead andalso
        receive {'DOWN', R, process, P, noproc} -> true
        after 1000 -> false
        end.

%% Error cases for monitor/2 (mon_e_1-class, local subset): a bad monitor
%% type and a bad process designator both raise badarg.
c_mon_badarg(_) ->
    T1 = try erlang:monitor(?MODULE:id(plutt), self()) of
             _ -> false
         catch error:badarg -> true; _:_ -> false
         end,
    T2 = try erlang:monitor(process, ?MODULE:id(1)) of
             _ -> false
         catch error:badarg -> true; _:_ -> false
         end,
    T1 andalso T2.

%% --- spawn_monitor/1 (case_1a/mon_1-class) ---------------------------------

%% spawn_monitor/1 spawns + monitors ATOMICALLY, returning {Pid, Ref}; the
%% child's normal exit delivers the DOWN binding that same pair.
c_spawn_monitor(_) ->
    {P, R} = spawn_monitor(fun () -> ok end),
    IsP = is_pid(P),
    IsR = is_reference(R),
    receive {'DOWN', R, process, P, normal} -> IsP andalso IsR
    after 1000 -> false
    end.

%% --- demonitor (demon_1/demon_2-class) -------------------------------------

%% demonitor of a never-used ref is a no-op returning true.
c_demon_fresh(_) ->
    erlang:demonitor(make_ref()) =:= true.

%% Self-monitor + demonitor idempotence: both the first and the EXTRA
%% demonitor return true, and no 'DOWN' is ever delivered.
c_demon_twice(_) ->
    R = erlang:monitor(process, self()),
    T1 = erlang:demonitor(R),
    T2 = erlang:demonitor(R),
    NoMsg = receive {'DOWN', R, _, _, _} -> false after 0 -> true end,
    (T1 =:= true) andalso (T2 =:= true) andalso NoMsg.

%% Demonitor BEFORE the target dies: the subsequent death delivers no 'DOWN'
%% (demon_2's "Demonitor before 'DOWN'" leg, with the upstream 100s sleeper
%% replaced by a receive-blocked child killed via exit/2).
c_demon_before_down(_) ->
    P = spawn(fun () -> receive never -> ok end end),
    R = erlang:monitor(process, P),
    true = erlang:demonitor(R),
    exit(P, ?MODULE:id(frop)),
    receive {'DOWN', R, _, _, _} -> false
    after 200 -> true
    end.

%% demonitor(Ref, [flush]) purges an ALREADY-DELIVERED 'DOWN' from the
%% mailbox (demonitor_flush-class). Two monitors watch the same child; the
%% death delivers both DOWNs together, so selectively receiving M2's DOWN
%% proves M1's is sitting in the mailbox — then the flush removes it.
c_demonitor_flush(_) ->
    P = spawn(fun () -> receive go -> ok end end),
    M1 = erlang:monitor(process, P),
    M2 = erlang:monitor(process, P),
    P ! go,
    Got2 = receive {'DOWN', M2, process, P, normal} -> true
           after 1000 -> false
           end,
    true = erlang:demonitor(M1, [flush]),
    NoM1 = receive {'DOWN', M1, _, _, _} -> false after 0 -> true end,
    Got2 andalso NoM1.

%% Demonitor with a ref created at the WRONG monitor end (demon_e_1/case_2
%% class): B demonitoring A's ref returns true but is a no-op — A still
%% observes B's 'DOWN' normal.
c_wrong_end_demon(_) ->
    Me = self(),
    B = spawn(fun () ->
                      receive {ref, R0} ->
                              V = try erlang:demonitor(R0) of X -> X
                                  catch C:E -> {C, E}
                                  end,
                              Me ! {res, V}
                      end
              end),
    R = erlang:monitor(process, B),
    B ! {ref, R},
    Res = receive {res, V} -> V after 1000 -> timeout end,
    Down = receive {'DOWN', R, process, B, normal} -> true
           after 1000 -> false
           end,
    (Res =:= true) andalso Down.

%% --- signal ordering + exit-reason fidelity --------------------------------

%% A message sent BEFORE the sender exits is received BEFORE the 'DOWN'
%% (same-sender signal order). Non-selective receives pin the strict order.
c_msg_before_down(_) ->
    Me = self(),
    {P, R} = spawn_monitor(fun () -> Me ! hello, exit(bye) end),
    First = receive X1 -> X1 after 1000 -> timeout end,
    Second = receive X2 -> X2 after 1000 -> timeout end,
    (First =:= hello) andalso (Second =:= {'DOWN', R, process, P, bye}).

%% A compound (heap-allocated) exit reason is copied into the 'DOWN' intact
%% (large_exit-class, structural equality of the received reason).
c_large_reason(_) ->
    S = {big, tuple, with, [list, 4563784278]},
    P = spawn(fun () -> receive go -> exit(?MODULE:id(S)) end end),
    R = erlang:monitor(process, P),
    P ! go,
    receive {'DOWN', R, process, P, Why} -> Why =:= S
    after 1000 -> false
    end.
