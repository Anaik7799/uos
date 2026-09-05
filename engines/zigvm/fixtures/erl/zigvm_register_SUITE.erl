%% zigvm_register_SUITE — a PURE-BUT-CONCURRENT curated subset of the
%% register/whereis/unregister surface exercised by
%% third_party/otp/erts/emulator/test/register_SUITE.erl, in the common_test
%% SUITE shape (`all/0` + `Case(Config)` funs) with NO common_test /
%% test_server dependency (CT-on-zigvm is Epoch E7). The real register_SUITE
%% has exactly ONE case, otp_8099 — a 1,000,000-iteration racy
%% register/kill/re-register loop; c_otp8099_bounded below is its
%% DETERMINISTIC bounded adaptation (monitor-confirmed death instead of the
%% catch-race, 20 iterations), and the remaining cases curate the name-table
%% semantics that suite exists to protect: register/whereis/unregister
%% round-trip, registered/0 membership, named send delivery (both directions
%% + selective receive), the non-atom/non-pid badarg arms, name-freed-on-death
%% (monitored), and process_info(_, registered_name).
%%
%% Every case is SELF-CONTAINED and DETERMINISTIC on the zigvm
%% scheduler-as-driver (virtual clock): spawned children terminate and their
%% 'DOWN' is consumed before the case returns, names are unregistered (or
%% freed by confirmed death), and the mailbox is flushed, so no case leaks
%% state into the next. Every blocking receive is bounded (`after 1000 ->
%% false`) so a bug is a false-return, never a hang. A case returns the atom
%% `true` on success; the runner (zigvm_register_suite_runner) counts a case
%% EQ only when BOTH VMs' `Suite:Case([])` returns `true`.
%%
%% SCOPE HONESTY — probed on the zigvm CLI and EXCLUDED as real, reportable
%% divergences (NOT silent gaps; the integrator triages; see the curation
%% notes): zigvm does not raise badarg for (a) register(undefined, Pid),
%% (b) register of a DEAD pid, (c) re-register of an already-registered NAME,
%% (d) a second name for an already-named PID, (e) unregister of an
%% unregistered name, (f) `Name ! Msg` to an unregistered name; and (g)
%% exit(P, kill) delivers 'DOWN' reason `kill` where OTP delivers `killed`
%% (c_otp8099_bounded therefore wildcards the reason — the name-table facts it
%% checks are EQ).
-module(zigvm_register_SUITE).

-export([all/0, id/1,
         c_reg_roundtrip/1, c_whereis_undef/1, c_registered_membership/1,
         c_reg_other_pid/1, c_named_send_to_child/1, c_named_send_to_parent/1,
         c_named_send_selective/1, c_reg_badarg_nonatom/1,
         c_name_freed_on_death/1, c_otp8099_bounded/1,
         c_pinfo_registered_name/1, c_reregister_after_unregister/1,
         %% spawned entry points (exported so spawn/3's MFA resolves).
         ps_waiter/0, ps_echo/0, ps_to_parent/0, ps_two_msgs/0]).

%% The suite manifest (common_test `all/0` contract). MIRRORED in order by
%% harness/suite_runner.ml's register_suite case_names (ncases/1 lockstep).
all() ->
    [c_reg_roundtrip, c_whereis_undef, c_registered_membership,
     c_reg_other_pid, c_named_send_to_child, c_named_send_to_parent,
     c_named_send_selective, c_reg_badarg_nonatom,
     c_name_freed_on_death, c_otp8099_bounded,
     c_pinfo_registered_name, c_reregister_after_unregister].

%% Exported identity: routes pure-value operands through a remote call so
%% constant folding cannot bypass the VM's register/whereis argument checks.
id(X) -> X.

%% --- register/whereis/unregister round-trip (self) ------------------------
%% register/2 returns `true`; the name maps to self exactly while registered.
c_reg_roundtrip(_) ->
    N = ?MODULE:id(zrs_rt),
    true = register(N, self()),
    R1 = whereis(N) =:= self(),
    true = unregister(N),
    R2 = whereis(N) =:= undefined,
    R1 andalso R2.

%% --- whereis of a never-registered name -----------------------------------
c_whereis_undef(_) ->
    whereis(?MODULE:id(zrs_never)) =:= undefined.

%% --- registered/0 membership ----------------------------------------------
%% A name is a member of registered() exactly while it is registered.
c_registered_membership(_) ->
    register(zrs_mem, self()),
    R1 = mem(zrs_mem, registered()),
    unregister(zrs_mem),
    R2 = not mem(zrs_mem, registered()),
    R1 andalso R2.

%% --- registering ANOTHER process's pid ------------------------------------
%% register/unregister of a child pid; the child is then stopped and its
%% 'DOWN' consumed (clean, monitored teardown).
c_reg_other_pid(_) ->
    P = spawn(?MODULE, ps_waiter, []),
    Ref = monitor(process, P),
    true = register(zrs_other, P),
    R1 = whereis(zrs_other) =:= P,
    true = unregister(zrs_other),
    R2 = whereis(zrs_other) =:= undefined,
    P ! stop,
    R3 = receive {'DOWN', Ref, process, P, normal} -> true
         after 1000 -> false end,
    flush(),
    R1 andalso R2 andalso R3.

%% --- named send delivery, parent -> registered child ----------------------
%% `Name ! Msg` resolves the name at send time and delivers to the child; the
%% child echoes the payload back, then dies, freeing the name (checked after
%% its confirmed 'DOWN').
c_named_send_to_child(_) ->
    P = spawn(?MODULE, ps_echo, []),
    Ref = monitor(process, P),
    true = register(zrs_echo, P),
    zrs_echo ! {echo, self(), ?MODULE:id(payload_42)},
    R1 = receive {echoed, payload_42} -> true after 1000 -> false end,
    R2 = receive {'DOWN', Ref, process, P, normal} -> true
         after 1000 -> false end,
    R3 = whereis(zrs_echo) =:= undefined,
    flush(),
    R1 andalso R2 andalso R3.

%% --- named send delivery, child -> registered parent ----------------------
c_named_send_to_parent(_) ->
    true = register(zrs_parent, self()),
    _ = spawn(?MODULE, ps_to_parent, []),
    R = receive zrs_hello -> true after 1000 -> false end,
    true = unregister(zrs_parent),
    flush(),
    R.

%% --- named delivery preserves order under SELECTIVE receive ---------------
%% The child sends {m,1} then {m,2} to the parent's name; the parent picks
%% {m,2} FIRST by selective receive, then {m,1} — both arrive via the name.
c_named_send_selective(_) ->
    true = register(zrs_sel, self()),
    _ = spawn(?MODULE, ps_two_msgs, []),
    R1 = receive {m, 2} -> true after 1000 -> false end,
    R2 = receive {m, 1} -> true after 1000 -> false end,
    true = unregister(zrs_sel),
    flush(),
    R1 andalso R2.

%% --- badarg arms: non-atom name / non-pid value ---------------------------
%% (The already-registered-name / already-named-pid / atom-`undefined` badarg
%% arms are probed DIVERGENT on zigvm today and excluded — see the module
%% header's scope-honesty list.)
c_reg_badarg_nonatom(_) ->
    A = try register(?MODULE:id("zrs_str"), self()) of _ -> false
        catch error:badarg -> true end,
    B = try register(zrs_np, ?MODULE:id(42)) of _ -> false
        catch error:badarg -> true end,
    A andalso B.

%% --- name freed when the process dies -------------------------------------
%% Monitor the registered child, let it terminate NORMALLY, consume the
%% 'DOWN' (so the death is complete), then whereis -> undefined.
c_name_freed_on_death(_) ->
    P = spawn(?MODULE, ps_waiter, []),
    true = register(zrs_die, P),
    Ref = monitor(process, P),
    R1 = whereis(zrs_die) =:= P,
    P ! stop,
    R2 = receive {'DOWN', Ref, process, P, normal} -> true
         after 1000 -> false end,
    R3 = whereis(zrs_die) =:= undefined,
    flush(),
    R1 andalso R2 andalso R3.

%% --- otp_8099, bounded deterministic adaptation ---------------------------
%% The real case loops 1,000,000 times racing register/2 against the death of
%% the PREVIOUS holder (OTP-8099 was a name-table corruption under that
%% race). Deterministic form: each iteration registers a fresh child under
%% the SAME name, kills it, confirms the death via 'DOWN' (reason wildcarded:
%% kill-vs-killed is a probed zigvm divergence, and the reason is not what
%% this case is about), and checks the name is freed before re-registering.
c_otp8099_bounded(_) ->
    R = otp8099_loop(20),
    flush(),
    R.

otp8099_loop(0) ->
    true;
otp8099_loop(N) ->
    P = spawn(?MODULE, ps_waiter, []),
    Ref = monitor(process, P),
    true = register(zrs_8099, P),
    R1 = whereis(zrs_8099) =:= P,
    exit(P, kill),
    R2 = receive {'DOWN', Ref, process, P, _} -> true after 1000 -> false end,
    R3 = whereis(zrs_8099) =:= undefined,
    case R1 andalso R2 andalso R3 of
        true -> otp8099_loop(N - 1);
        false -> false
    end.

%% --- process_info(_, registered_name) -------------------------------------
%% {registered_name, Name} while registered; the empty list [] (NOT
%% {registered_name, []}) after unregister — OTP's documented quirk.
c_pinfo_registered_name(_) ->
    true = register(zrs_pi, self()),
    A = process_info(self(), registered_name) =:= {registered_name, zrs_pi},
    true = unregister(zrs_pi),
    B = process_info(self(), registered_name) =:= [],
    A andalso B.

%% --- a name is reusable after unregister ----------------------------------
%% register -> unregister on self, then the SAME name registers a child; the
%% child is stopped and the name confirmed freed.
c_reregister_after_unregister(_) ->
    true = register(zrs_re, self()),
    true = unregister(zrs_re),
    P = spawn(?MODULE, ps_waiter, []),
    Ref = monitor(process, P),
    true = register(zrs_re, P),
    R1 = whereis(zrs_re) =:= P,
    P ! stop,
    R2 = receive {'DOWN', Ref, process, P, normal} -> true
         after 1000 -> false end,
    R3 = whereis(zrs_re) =:= undefined,
    flush(),
    R1 andalso R2 andalso R3.

%% --- spawned entry points -------------------------------------------------
ps_waiter() -> receive stop -> ok end.
ps_echo() -> receive {echo, From, M} -> From ! {echoed, M} end.
ps_to_parent() -> zrs_parent ! zrs_hello.
ps_two_msgs() -> zrs_sel ! {m, 1}, zrs_sel ! {m, 2}.

%% --- local helpers (self-contained; no lists:* to load) -------------------
%% Defensive mailbox drain: every case already consumes everything it
%% provokes, but a leftover message would break the NEXT case, so drain
%% unconditionally before returning.
flush() -> receive _ -> flush() after 0 -> ok end.

mem(_, []) -> false;
mem(X, [X | _]) -> true;
mem(X, [_ | T]) -> mem(X, T).
