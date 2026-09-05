%% zigvm_e4_SUITE — the E4-reachable successor to zigvm_pure_SUITE. Same
%% common_test SUITE shape (`all/0` + `Case(Config)` funs) with NO common_test /
%% test_server dependency (CT-on-zigvm is Epoch E7), but every case exercises
%% functionality that Epoch E4 (the "boot the world" epoch) made reachable
%% END-TO-END from a compiled `.beam`: the scheduler-as-driver process family
%% (spawn/link/monitor/register — E4.1), the group-leader protocol (E4.6), the
%% module-metadata surface (get_module_info/module_info — E4.2), registered/0,
%% and the native-name codec (E4.4). A case returns the atom `true` on success;
%% the runner (zigvm_e4_suite_runner) counts a case EQ only when BOTH VMs'
%% `Suite:Case([])` returns `true`. A case that needs a BIF/opcode the VM lacks
%% raises -> caught -> counted `fail` (a visible divergence, never silent).
%%
%% SCOPE HONESTY (SC-8.2 totality — the not-yet-EQ residuals are recorded
%% VISIBLY, in harness/suite_runner.ml's `e4_suite.untested` list + DIVERGENCE
%% entry 50, never dropped): the remaining E4-adjacent verbs NOT observationally
%% EQ from a real erlc `.beam` is `erts_internal:beamfile_chunk/2` over a
%% synthetic IFF (the oracle parser is stricter than zigvm's). Its owner is
%% named in entry 50. E5.3 (Task 3) DISCHARGED the io OUTPUT-verb residual
%% (c_io_put_chars below): `io:put_chars`/`io:nl` are STDLIB LIBRARY wrappers
%% (not bif.tab rows), now expanded inline onto the E4.6 group-leader protocol
%% by the loader (bifs/dispatch.resolveLibrary), so they resolve from a compiled
%% beam and their output byte-matches on both VMs (DIVERGENCE entry 41).
%% E5.8 (Task 8) DISCHARGED the three signal-routing residuals of entry 50 as the
%% runnable cases below: `Name ! Msg` registered-name send delivery
%% (c_named_send), `exit/2` cross-process signal delivery (c_exit2_signal), and
%% `spawn_monitor/3` (c_spawn_monitor). Each is proven by a CROSS-PROCESS wakeup +
%% a blocking `receive` (no finite `after` — the E6 receive timer is not modeled;
%% the peer's send / exit signal / 'DOWN' wakes the suspended receiver).
-module(zigvm_e4_SUITE).

-export([all/0,
         c_group_leader/1, c_module_info/1, c_module_info_exports/1,
         c_registered/1, c_native_name/1, c_make_ref/1, c_process_flag/1,
         c_spawn_link_normal/1, c_monitor_demonitor/1, c_multi_spawn/1,
         c_named_send/1, c_exit2_signal/1, c_spawn_monitor/1, c_io_put_chars/1,
         %% spawned entry points (exported so spawn/3's MFA resolves).
         ps_child/2, ps_normal/0, ps_waiter/0, ns_sender/0]).

%% The suite manifest (common_test `all/0` contract). MIRRORED in order by
%% harness/suite_runner.ml's e4_suite.case_names — the ncases/1 cross-check
%% (SC-8.2 totality) keeps them in lockstep.
all() ->
    [c_group_leader, c_module_info, c_module_info_exports,
     c_registered, c_native_name, c_make_ref, c_process_flag,
     c_spawn_link_normal, c_monitor_demonitor, c_multi_spawn,
     c_named_send, c_exit2_signal, c_spawn_monitor, c_io_put_chars].

%% --- group-leader protocol (E4.6) -----------------------------------------
%% A top-level process's group leader is a DISTINCT io server (not self) once
%% the standard_io GL fixture is installed by cli.runMulti. Observed by
%% INEQUALITY (the pid VALUE still differs from OTP's <0.N.0>).
c_group_leader(_) ->
    is_pid(group_leader()) andalso (group_leader() =/= self()).

%% --- module metadata (E4.2: get_module_info via the auto-generated
%% module_info/0,1) ---------------------------------------------------------
c_module_info(_) ->
    (zigvm_e4_SUITE:module_info(module) =:= zigvm_e4_SUITE).

c_module_info_exports(_) ->
    Exports = zigvm_e4_SUITE:module_info(exports),
    mem({c_group_leader, 1}, Exports) andalso mem({all, 0}, Exports).

%% --- registration (E4.1) --------------------------------------------------
%% register/whereis/registered bijection: a registered name is a member of
%% registered/0 exactly while it is registered.
c_registered(_) ->
    register(zes_reg, self()),
    R1 = mem(zes_reg, registered()),
    unregister(zes_reg),
    R2 = not mem(zes_reg, registered()),
    R1 andalso R2.

%% --- native-name codec (E4.4) ---------------------------------------------
%% The encoding is a fixed system property; both VMs agree it is one of the
%% two legal atoms (value-independent so a latin1/utf8 host difference cannot
%% make this a flake).
c_native_name(_) ->
    E = file:native_name_encoding(),
    (E =:= utf8) orelse (E =:= latin1).

%% --- references -----------------------------------------------------------
c_make_ref(_) ->
    is_reference(make_ref()) andalso (make_ref() =/= make_ref()).

%% --- process flags --------------------------------------------------------
%% Deterministic round-trip (never reads the ambient initial trap_exit, which
%% is process/context-dependent): set trap_exit to true, then set it to false
%% and observe the PREVIOUS value we just wrote.
c_process_flag(_) ->
    _ = process_flag(trap_exit, true),
    process_flag(trap_exit, false) =:= true.

%% --- link + trap_exit (E4.1) ----------------------------------------------
%% A linked NORMAL exit arrives as {'EXIT', Pid, normal} when trapping, binding
%% the specific child pid.
c_spawn_link_normal(_) ->
    process_flag(trap_exit, true),
    P = spawn_link(zigvm_e4_SUITE, ps_normal, []),
    receive {'EXIT', P, normal} -> true end.

%% --- monitor + demonitor(flush) (E4.1) ------------------------------------
%% After demonitor(Ref, [flush]) the child's 'DOWN' is never observed; the
%% mailbox stays clear of it.
c_monitor_demonitor(_) ->
    P = spawn(zigvm_e4_SUITE, ps_waiter, []),
    Ref = monitor(process, P),
    true = demonitor(Ref, [flush]),
    P ! go,
    receive {'DOWN', _, _, _, _} -> false after 20 -> true end.

%% --- multi-child spawn + aggregation (E4.1) -------------------------------
c_multi_spawn(_) ->
    Me = self(),
    _ = [spawn(zigvm_e4_SUITE, ps_child, [Me, K]) || K <- [1, 2, 3]],
    collect(3, 0) =:= 6.

%% --- registered-name send delivery (E5.8: DIVERGENCE entry 50(a)) ----------
%% `Name ! Msg` routes to the pid `Name` is registered to. Proven CROSS-PROCESS:
%% self registers a name, a child sends to that NAME, and the (suspended) self is
%% woken by the delivered message. A blocking `receive` (no `after`) — the child
%% WILL send, so the receiver never sleeps over an unseen message.
c_named_send(_) ->
    register(zes_ns, self()),
    _ = spawn(zigvm_e4_SUITE, ns_sender, []),
    receive ns_ok -> true end.

%% --- exit/2 cross-process signal delivery (E5.8: DIVERGENCE entry 50(b)) ----
%% `exit(Pid, Reason)` signals a linked trapping process `{'EXIT',Pid,Reason}`.
%% The child (not trapping) dies of `killme`; the signal propagates over the link
%% to the trapping self, waking it.
c_exit2_signal(_) ->
    process_flag(trap_exit, true),
    P = spawn_link(zigvm_e4_SUITE, ps_waiter, []),
    exit(P, killme),
    receive {'EXIT', P, killme} -> true end.

%% --- spawn_monitor/3 (E5.8: DIVERGENCE entry 50(c)) ------------------------
%% `spawn_monitor(M,F,A) == spawn_opt(M,F,A,[monitor])`: spawns + monitors
%% atomically, returning `{Pid, Ref}`. The child exits `normal`, whose 'DOWN'
%% (5-tuple, binding the SAME Pid+Ref) wakes the blocking receiver.
c_spawn_monitor(_) ->
    {P, Ref} = spawn_monitor(zigvm_e4_SUITE, ps_normal, []),
    IsP = is_pid(P),
    IsR = is_reference(Ref),
    receive {'DOWN', Ref, process, P, normal} -> IsP andalso IsR end.

%% --- io OUTPUT verb reachability (E5.3 / Task 3) --------------------------
%% `io:put_chars/1` is a STDLIB LIBRARY wrapper (io.erl), not a bif.tab BIF, so
%% before E5.3 it resolved `undef` from a compiled beam (entry 49 blocker (2) /
%% the u_io_put_chars residual). The loader now expands it inline onto the E4.6
%% group-leader request protocol (bifs/dispatch.resolveLibrary), so the verb is
%% REACHABLE and returns `ok`. The put_chars output ("io_ok") lands on stdout on
%% BOTH VMs (zigvm flushes the captured GL sink ahead of the result), so the
%% full stdout byte-matches; the case returns `true`.
c_io_put_chars(_) ->
    ok = io:put_chars("io_ok"),
    ok = io:nl(),
    true.

%% --- spawned entry points -------------------------------------------------
ps_child(Parent, N) -> Parent ! N.
ps_normal() -> ok.
ps_waiter() -> receive go -> exit(done) end.
ns_sender() -> zes_ns ! ns_ok.

%% --- local helpers (self-contained; no lists:* to load) -------------------
collect(0, Acc) -> Acc;
collect(N, Acc) -> receive X -> collect(N - 1, Acc + X) end.

mem(_, []) -> false;
mem(X, [X | _]) -> true;
mem(X, [_ | T]) -> mem(X, T).
