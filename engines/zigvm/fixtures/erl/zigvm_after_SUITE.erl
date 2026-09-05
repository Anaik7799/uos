%% zigvm_after_SUITE — a PURE-BUT-CONCURRENT subset of
%% erts/emulator/test/after_SUITE.erl, in the common_test SUITE shape
%% (`all/0` + `Case(Config)` funs) with NO common_test / test_server dependency
%% (CT-on-zigvm is Epoch E7). Every case exercises `receive ... after` timeout
%% semantics the zigvm scheduler-as-driver executes deterministically under the
%% virtual clock: `after 0` non-blocking polls (empty vs matching vs
%% non-matching queue), a runtime-variable-0 timeout (routed through
%% ?MODULE:id/1 so constant folding cannot fold the operand out of the VM), an
%% unconditional `receive after 0` that always takes the timeout branch while
%% messages sit queued (queue order preserved), the timeout branch firing on a
%% genuinely empty queue, `after N` racing an arriving message (delivery wins —
%% both a small and a 32-bit-wide timeout 16#f7654321, the receive_after_big
%% shape), `after` inside a spawned process, lexically nested receive-after, the
%% receive_after1 halving-recursion (after N -> after N/2 -> ... -> after 1,
%% terminates), and the multi_timeout shape (messages queued to a process that
%% then passes through a receive-after, drained FIFO). Delivery/ordering FACTS
%% only — never an elapsed-time value.
%%
%% MIRRORED FROM after_SUITE, transformed:
%%   t_after (wall-clock accuracy, monotonic_time %)          -> EXCLUDED (timing)
%%   receive_after / receive_after1 (halving recursion)       -> c_after_halving
%%   receive_after_big (32-bit timeout, delivery wins)        -> c_delivery_wins_big
%%   receive_var_zero (after Z, Z==0 via a runtime var)       -> c_var_zero_selective
%%   receive_zero (after 0 selective + unconditional)         -> c_after_zero_* + c_uncond_after_zero
%%   multi_timeout (queue msgs to a proc crossing an after)   -> c_multi_timeout
%%   receive_after_32bit / receive_after_blast (2048/10000    -> EXCLUDED (mass spawn +
%%     procs, 'too early' wall-clock watchdog)                     wall-clock watchdog)
%%   receive_after_errors ({timeout_value,_} for bad timeouts)-> c_bad_timeout_raises
%%
%% REAL zigvm DIVERGENCES found while curating (probed on the prebuilt CLI, not
%% guessed) — BOTH FIXED in E34-T1 (DIVERGENCE_LOG entry 559) and now mirrored
%% byte-EQ (the shapes that used to be EXCLUDED are the last three cases):
%%   DIVERGENCE 1 [FIXED]: an UNCONDITIONAL `receive after T` (no message clauses)
%%     with a NON-EMPTY mailbox HUNG on zigvm when T reached the wait_timeout
%%     opcode — i.e. T>0, or a runtime-variable T=0 (the compiler's immediate-poll
%%     fast path only fires for a *literal* 0). The `wait_timeout` lost-wakeup
%%     guard misfired: it jumped to its label (the wait itself — no loop_rec to
%%     advance the cursor) and re-hit forever. Now gated on `recv_scanned` (a
%%     loop_rec ran ⇒ selective receive ⇒ the guard is valid); unconditional
%%     receives fall through to fire the timeout. OTP takes the timeout branch at
%%     once, leaving the messages queued — matched by c_uncond_after_var/_pos.
%%     (Selective `receive Pat after T` over a non-matching non-empty queue was
%%     always FINE on both — c_var_zero_selective / c_after_zero_nonmatching.)
%%   DIVERGENCE 2 [FIXED]: an INVALID `receive after` timeout (-1, 3.14, an atom,
%%     or an out-of-range bignum) silently took the after branch on zigvm. Now it
%%     raises error:timeout_value exactly as OTP does — see c_bad_timeout_raises.
%%
%% Discipline: every case is self-contained + deterministic — spawned children
%% terminate by construction, every receive is bounded (`after` a modest N, so a
%% bug is a false return, never a hang), the mailbox is verified EMPTY before
%% returning (a leftover message would poison the NEXT case), and pure-value
%% seeds/timeouts are routed through the exported ?MODULE:id/1 so constant
%% folding cannot bypass the VM. A case returns the atom `true` on success; the
%% runner (zigvm_after_suite_runner) counts a case EQ only when BOTH VMs'
%% `Suite:Case([])` return `true`.
-module(zigvm_after_SUITE).

-export([all/0,
         c_after_zero_poll/1, c_after_zero_nonmatching/1,
         c_var_zero_selective/1, c_uncond_after_zero/1,
         c_uncond_after_var/1, c_uncond_after_pos/1, c_bad_timeout_raises/1,
         c_timeout_fires_empty/1, c_delivery_wins/1,
         c_delivery_wins_big/1, c_after_in_spawn/1,
         c_nested_after/1, c_after_halving/1, c_multi_timeout/1,
         %% exported spawned entry points (so spawn/3's MFA resolves) + id/1
         %% (the constant-folding firewall).
         id/1, ping_sender/1, timeout_reporter/1, drain_after/1]).

%% The suite manifest (common_test `all/0` contract). MIRRORED in order by
%% harness/suite_runner.ml's after-suite spec case_names (ncases/1 lockstep).
all() ->
    [c_after_zero_poll, c_after_zero_nonmatching,
     c_var_zero_selective, c_uncond_after_zero,
     c_uncond_after_var, c_uncond_after_pos, c_bad_timeout_raises,
     c_timeout_fires_empty, c_delivery_wins,
     c_delivery_wins_big, c_after_in_spawn,
     c_nested_after, c_after_halving, c_multi_timeout].

%% Identity through an exported call — the compiler cannot constant-fold across
%% it, so seed values / timeouts genuinely travel through the VM.
id(X) -> X.

%% --- receive after 0: a non-blocking poll -----------------------------------
%% Empty mailbox -> the after-0 branch; a queued matching message -> received,
%% never the timeout branch.
c_after_zero_poll(_) ->
    E = receive _ -> got after 0 -> empty end,
    self() ! id(pmsg),
    G = receive pmsg -> got after 0 -> empty end,
    (E =:= empty) andalso (G =:= got) andalso mbox_empty().

%% --- receive after 0 over a NON-matching queue ------------------------------
%% A queued non-matching message does not satisfy a selective after-0 poll (the
%% timeout branch fires) and it STAYS queued for a later matching receive.
c_after_zero_nonmatching(_) ->
    self() ! id(other),
    R = receive wanted -> wrong after 0 -> polled_empty end,
    S = receive other -> ok after 1000 -> gone end,
    (R =:= polled_empty) andalso (S =:= ok) andalso mbox_empty().

%% --- receive after Z, Z a runtime-variable 0 (receive_var_zero) -------------
%% Z travels through ?MODULE:id/1 so the compiler cannot fold the operand to the
%% literal-0 immediate-poll path — the timeout value is genuinely evaluated at
%% run time. Over a non-matching queue [x, y] the selective receive of `z` takes
%% the after-Z branch (timeout), and x then y are still received in queue order.
c_var_zero_selective(_) ->
    self() ! id(x),
    self() ! id(y),
    Z = id(0),
    R = receive z -> wrong after Z -> timeout end,
    A = receive x -> ok after 1000 -> gone end,
    B = receive y -> ok after 1000 -> gone end,
    (R =:= timeout) andalso (A =:= ok) andalso (B =:= ok) andalso mbox_empty().

%% --- unconditional receive after 0 with a non-empty mailbox (receive_zero) --
%% An `after 0` receive with NO message clauses always takes the timeout branch,
%% regardless of what is queued; the queued messages stay, in FIFO order.
c_uncond_after_zero(_) ->
    self() ! id(a),
    self() ! id(b),
    U = receive after 0 -> timeout end,
    F = flush([]),
    (U =:= timeout) andalso (F =:= [a, b]) andalso mbox_empty().

%% --- unconditional receive after a RUNTIME-variable 0 over a non-empty queue -
%% The DIVERGENCE-1 repro that used to HANG on zigvm: with the timeout routed
%% through ?MODULE:id/1 the compiler's literal-0 fast path does NOT fire, so the
%% `wait_timeout` opcode is genuinely reached with messages queued. It must take
%% the timeout branch AT ONCE (leaving the messages in FIFO order), never spin.
c_uncond_after_var(_) ->
    self() ! id(a),
    self() ! id(b),
    Z = id(0),
    U = receive after Z -> timeout end,
    F = flush([]),
    (U =:= timeout) andalso (F =:= [a, b]) andalso mbox_empty().

%% --- unconditional receive after a POSITIVE T over a non-empty queue ---------
%% The other DIVERGENCE-1 shape: T>0 (id-routed) with messages already queued.
%% The after-branch fires when the timer elapses; the queued messages are left
%% untouched. Delivery/branch FACT only — never an elapsed-time value.
c_uncond_after_pos(_) ->
    self() ! id(a),
    self() ! id(b),
    U = receive after id(5) -> timeout end,
    F = flush([]),
    (U =:= timeout) andalso (F =:= [a, b]) andalso mbox_empty().

%% --- invalid receive-after timeouts raise error:timeout_value (DIVERGENCE 2) --
%% A negative int, a float, and a non-`infinity` atom are each an invalid
%% timeout; erts (and now zigvm) raise `error:timeout_value` rather than silently
%% taking the after branch. Each value is id-routed so the operand travels
%% through the VM. The mailbox is empty throughout.
c_bad_timeout_raises(_) ->
    R1 = try (receive after id(-1) -> no end)
             catch error:timeout_value -> caught end,
    R2 = try (receive after id(3.14) -> no end)
             catch error:timeout_value -> caught end,
    R3 = try (receive after id(not_an_int) -> no end)
             catch error:timeout_value -> caught end,
    (R1 =:= caught) andalso (R2 =:= caught) andalso (R3 =:= caught)
        andalso mbox_empty().

%% --- receive after N over an empty queue: the timeout branch fires ----------
%% Nothing is ever sent, so the ONLY exit is the after-branch (the virtual clock
%% fires it deterministically; on the oracle, after 30ms of wall time).
c_timeout_fires_empty(_) ->
    R = receive never_sent -> wrong after 30 -> timed_out end,
    (R =:= timed_out) andalso mbox_empty().

%% --- receive after N with a message arriving: delivery beats the timer ------
%% A child sends `ping`; the bounded receive takes the DELIVERY branch, never
%% the timeout branch (ordering/delivery fact only — no elapsed-time value).
c_delivery_wins(_) ->
    _P = spawn(zigvm_after_SUITE, ping_sender, [self()]),
    R = receive ping -> delivered after 1000 -> timeout end,
    (R =:= delivered) andalso mbox_empty().

%% --- receive after a 32-bit-wide timeout, delivery wins (receive_after_big) --
%% 16#f7654321 (~48 days) is a valid timeout on both VMs; the arriving `ping`
%% takes the delivery branch so the ~48-day timer is never observed. The big
%% timeout travels through ?MODULE:id/1 (runtime operand). We assert only that
%% the timeout can be set and delivery wins — never that a timeout occurs.
c_delivery_wins_big(_) ->
    _P = spawn(zigvm_after_SUITE, ping_sender, [self()]),
    R = receive ping -> delivered after id(16#f7654321) -> timeout end,
    (R =:= delivered) andalso mbox_empty().

%% --- receive-after inside a spawned process ---------------------------------
%% The child runs its OWN bounded receive-after over an empty queue, takes the
%% timeout branch, and reports the branch it took back to the parent.
c_after_in_spawn(_) ->
    _P = spawn(zigvm_after_SUITE, timeout_reporter, [self()]),
    R = receive {child, V} -> V after 1000 -> timeout end,
    (R =:= timed_out) andalso mbox_empty().

%% --- lexically nested receive-after: the inner timers run to completion ------
c_nested_after(_) ->
    R = receive after 4 ->
            receive after 2 ->
                receive after 1 -> done end end end,
    (R =:= done) andalso mbox_empty().

%% --- receive_after1: a halving-recursion of receive-after that terminates ----
%% after 8 -> after 4 -> after 2 -> after 1 -> ok. The real suite's proof that
%% `receive after N` works and does not hang; here it must return `ok`.
c_after_halving(_) ->
    R = halving(8),
    (R =:= ok) andalso mbox_empty().

%% --- multi_timeout: messages queued to a process crossing a receive-after ----
%% Three {n,_} messages plus a `go` marker are sent to the child; it drains the
%% numbers FIFO by selective receive (1,2,3), consumes `go`, then passes through
%% an unconditional receive-after on a now-empty mailbox before reporting the
%% sum. (Draining first keeps the unconditional after off DIVERGENCE 1.)
c_multi_timeout(_) ->
    Me = self(),
    P = spawn(zigvm_after_SUITE, drain_after, [Me]),
    P ! {n, id(1)},
    P ! {n, id(2)},
    P ! {n, id(3)},
    P ! go,
    R = receive {sum, S} -> S after 1000 -> timeout end,
    (R =:= 6) andalso mbox_empty().

%% --- spawned entry points (terminate by construction) -----------------------
ping_sender(Parent) -> Parent ! ping.

timeout_reporter(Parent) ->
    R = receive never -> wrong after 20 -> timed_out end,
    Parent ! {child, R}.

drain_after(Parent) ->
    A = receive {n, X} -> X after 1000 -> 0 end,
    B = receive {n, Y} -> Y after 1000 -> 0 end,
    C = receive {n, W} -> W after 1000 -> 0 end,
    receive go -> ok after 1000 -> ok end,
    receive after 5 -> ok end,
    Parent ! {sum, A + B + C}.

%% --- local helpers (self-contained; no lists:* to load) ---------------------
halving(1) -> receive after 1 -> ok end;
halving(N) when N > 1 -> receive after N -> halving(N div 2) end.

mbox_empty() -> receive _ -> false after 0 -> true end.

flush(Acc) -> receive X -> flush([X | Acc]) after 0 -> rev(Acc, []) end.

rev([], Acc) -> Acc;
rev([H | T], Acc) -> rev(T, [H | Acc]).
