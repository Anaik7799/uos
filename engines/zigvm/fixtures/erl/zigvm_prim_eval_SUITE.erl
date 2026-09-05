%% Curated subset in the SPIRIT of erts/emulator/test/prim_eval_SUITE.erl
%% (E7 suite closure). The REAL suite contains exactly one case, 'ERL-365',
%% a scheduler regression: it drives the INTERNAL primitive prim_eval:'receive'/2
%% together with erlang:bump_reductions/1 to force a process to be scheduled
%% out *inside* a `receive after` block, proving that def_arg_reg[0] (which
%% holds the pending timeout instruction) is not clobbered by the save/restore
%% of live registers across the scheduling boundary. That case is NOT directly
%% curatable: prim_eval:'receive'/2 is an unexported erts-internal module that
%% zigvm does not link, and the assertion is about register-file internals, not
%% an observable value. So this file mirrors the SEMANTIC content the suite
%% guards — basic evaluation (apply/2,3 in all its forms) and receive-primitive
%% behaviour that must survive a scheduling boundary — as representation-
%% independent boolean truths both VMs compute identically (byte-EQ).
%%
%% Scope / honesty limits:
%%   * prim_eval:'receive'/2 (the internal recv primitive) is EXCLUDED — not
%%     linkable on zigvm; the c_after_survives_* cases capture its OBSERVABLE
%%     content (a `receive after N` set up before, and surviving across,
%%     function calls / a scheduling boundary still takes its timeout branch).
%%   * apply/3 targets are erlang: BIFs only. zigvm links the `erlang` module
%%     but NOT library modules (`lists`, ...), so apply(lists, ...) is EXCLUDED
%%     (PROBED: apply(lists,reverse,_) / apply(lists,seq,_) both fail to resolve
%%     on the zigvm CLI — the module is not loaded; erlang: applies resolve).
%%   * erlang:bump_reductions/1 IS reachable on zigvm (PROBED: returns `true`),
%%     so c_bump_reductions exercises the exact ERL-365 primitive, though not
%%     the register-clobber timing it was written to catch.
%%
%% Discipline: every case is self-contained + deterministic — spawned children
%% terminate by construction, every receive is bounded (`after` a modest N, so a
%% bug is a false return, never a hang), the mailbox is verified EMPTY before
%% returning (a leftover message would poison the NEXT case), and pure-value
%% seeds/operands are routed through the exported ?MODULE:id/1 so constant
%% folding cannot bypass the VM. A case returns the atom `true` on success; the
%% runner (zigvm_prim_eval_suite_runner) counts a case EQ only when BOTH VMs'
%% `Suite:Case([])` returns `true`. all/0 order is MIRRORED in
%% harness/suite_runner.ml's prim_eval spec (ncases/1 lockstep).
-module(zigvm_prim_eval_SUITE).

-export([all/0,
         c_apply_mfa/1, c_apply_fun/1, c_apply_dynamic/1, c_apply_chained/1,
         c_apply_guard_bif/1,
         c_basic_recv/1, c_recv_after_timeout/1, c_recv_delivery/1,
         c_recv_after_survives_calls/1, c_after_survives_reductions/1,
         c_bump_reductions/1, c_spawn_apply/1,
         %% exported spawned entry points (so spawn/3's MFA resolves) + id/1
         %% (the constant-folding firewall).
         id/1, worker_ping/1, worker_apply/2, worker_recv_after/2]).

all() ->
    [c_apply_mfa, c_apply_fun, c_apply_dynamic, c_apply_chained,
     c_apply_guard_bif,
     c_basic_recv, c_recv_after_timeout, c_recv_delivery,
     c_recv_after_survives_calls, c_after_survives_reductions,
     c_bump_reductions, c_spawn_apply].

%% Identity through an exported call — the compiler cannot constant-fold across
%% it, so operands genuinely travel through the VM's apply/send machinery.
id(X) -> X.

%% --- apply/3 to an erlang: BIF, in module/fun/args form ----------------------
c_apply_mfa(_) ->
    (apply(erlang, '+', [id(2), id(3)]) =:= 5)
        andalso (apply(erlang, abs, [id(-9)]) =:= 9)
        andalso (apply(erlang, hd, [id([a, b, c])]) =:= a).

%% --- apply/2 to a fun value (closure invoked via apply) ----------------------
c_apply_fun(_) ->
    F = fun(X, Y) -> X + Y end,
    G = fun(L) -> length(L) end,
    (apply(F, [id(4), id(5)]) =:= 9)
        andalso (erlang:apply(F, [id(10), id(20)]) =:= 30)
        andalso (apply(G, [id([x, y, z, w])]) =:= 4).

%% --- apply/3 with the module AND function name arriving as runtime atoms -----
%% (routed through id/1 so the target is resolved dynamically, not inlined).
c_apply_dynamic(_) ->
    M = id(erlang), Fn = id(element),
    (apply(M, Fn, [id(2), id({a, b, c})]) =:= b)
        andalso (apply(id(erlang), id(tuple_size), [id({1, 2, 3, 4})]) =:= 4).

%% --- nested apply: the result of one apply feeds the arguments of another ----
c_apply_chained(_) ->
    A = apply(erlang, '+', [apply(erlang, '*', [id(3), id(4)]), id(5)]),
    B = apply(erlang, element,
              [apply(erlang, '-', [id(3), id(1)]), id({a, b, c})]),
    (A =:= 17) andalso (B =:= b).

%% --- apply/3 to type-test guard BIFs returns the boolean unchanged -----------
c_apply_guard_bif(_) ->
    (apply(erlang, is_integer, [id(7)]) =:= true)
        andalso (apply(erlang, is_atom, [id(foo)]) =:= true)
        andalso (apply(erlang, is_list, [id(42)]) =:= false).

%% --- basic receive: a self-sent message is received; mailbox drains ----------
c_basic_recv(_) ->
    self() ! id(hello),
    R = receive X -> X after 1000 -> timeout end,
    (R =:= hello) andalso mbox_empty().

%% --- receive after N over an empty queue: the timeout branch fires -----------
%% (the ERL-365 core instruction — a bare `receive after`).
c_recv_after_timeout(_) ->
    R = receive never_sent -> wrong after 30 -> timed_out end,
    (R =:= timed_out) andalso mbox_empty().

%% --- receive after N with a message arriving: delivery beats the timer -------
c_recv_delivery(_) ->
    _ = spawn(zigvm_prim_eval_SUITE, worker_ping, [self()]),
    R = receive ping -> got after 1000 -> timeout end,
    (R =:= got) andalso mbox_empty().
worker_ping(P) -> P ! ping.

%% --- ERL-365 spirit: a `receive after N` whose timeout survives the function
%% calls made around it (the pending-timeout register is not clobbered by the
%% save/restore of live registers across the calls). ----------------------------
c_recv_after_survives_calls(_) ->
    N = burn(id(50), 0),
    R = receive never2 -> wrong after N -> ok end,
    K = burn(id(50), 0),
    (R =:= ok) andalso (K =:= 1275) andalso mbox_empty().
burn(0, Acc) -> Acc;
burn(N, Acc) -> burn(N - 1, Acc + N).

%% --- ERL-365 spirit (closer): a spawned proc sits in `receive after N` while a
%% NON-matching message is delivered to it mid-flight; the after branch still
%% fires (the timeout is not lost when a signal is enqueued before it). --------
c_after_survives_reductions(_) ->
    Me = self(),
    P = spawn(zigvm_prim_eval_SUITE, worker_recv_after, [Me, id(40)]),
    receive after 5 -> ok end,
    P ! {wont, match},
    R = receive {done, V} -> V after 1000 -> timeout end,
    (R =:= timed_out_branch) andalso mbox_empty().
worker_recv_after(Parent, T) ->
    R = receive matches_nothing -> wrong after T -> timed_out_branch end,
    Parent ! {done, R}.

%% --- erlang:bump_reductions/1 (the exact ERL-365 primitive) returns `true` ---
c_bump_reductions(_) ->
    R = erlang:bump_reductions(id((1 bsl 20))),
    R =:= true.

%% --- spawn a process that applies a BIF and replies with the result ----------
c_spawn_apply(_) ->
    Me = self(),
    _ = spawn(zigvm_prim_eval_SUITE, worker_apply, [Me, id(6)]),
    R = receive V -> V after 1000 -> timeout end,
    (R =:= 42) andalso mbox_empty().
worker_apply(Parent, X) -> Parent ! apply(erlang, '*', [X, id(7)]).

%% --- local helper (self-contained; no lists:* to load) -----------------------
mbox_empty() -> receive _ -> false after 0 -> true end.
