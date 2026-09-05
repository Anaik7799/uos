%% zigvm_timer_bif_SUITE — a PURE-BUT-CONCURRENT curated subset of
%% erts/emulator/test/timer_bif_SUITE.erl in the common_test SUITE shape
%% (`all/0` + `Case(Config)` boolean funs) with NO common_test / test_server
%% dependency. Every case exercises the BIF timer family the zigvm
%% scheduler-as-driver executes deterministically against its VIRTUAL clock
%% (E6.2 timer engine): `erlang:send_after/3,4` delivers Msg to Dest after N,
%% `erlang:start_timer/3,4` delivers `{timeout, TRef, Msg}`, `cancel_timer/1,2`
%% retires a live timer returning remaining-ms (or `ok`/`false` per options),
%% `read_timer/1` reports remaining-ms | `false` without cancelling.
%%
%% DETERMINISM RULES OBEYED: every assertion is a DELIVERY / ordering /
%% return-domain fact — never an elapsed-time measurement (the virtual clock
%% makes `after` fire deterministically but elapsed values are not comparable
%% across VMs). Every blocking receive is bounded (`after` <= 1000) so a bug is
%% a false-return, never a hang. Each case flushes its mailbox and unregisters
%% its names before returning. Pure-value operands that constant-folding could
%% bypass are routed through the exported ?MODULE:id/1.
%%
%% CURATION HONESTY (probed on the prebuilt zigvm CLI + the pinned OTP-30
%% oracle before inclusion):
%%   - EXCLUDED dead-destination arming (timer_bif_SUITE `cleanup`-class): OTP
%%     creates NO timer for an already-dead local pid (`read_timer` -> false);
%%     zigvm arms it and reports the full remaining time, dropping the message
%%     only at fire time. REAL DIVERGENCE, probed both sides — for the
%%     integrator to triage, not silently absorbed here.
%%   - EXCLUDED same-timeout ordering (send_after_3's commented-out block: OTP
%%     itself does not guarantee it), read_timer/cancel_timer `{async,true}`
%%     message shape (probeable but the async reply interleaving with the
%%     virtual clock is scheduler-timing-adjacent), `{abs,true}` timers (they
%%     require comparing monotonic-clock READINGS, which differ by design),
%%     and cross-node/`?CT_PEER` error arms (no distribution here).
%%   - EXCLUDED wall-clock remainder-window checks (start_timer_big-class
%%     `Big - Left >= 200` bounds): elapsed-time comparisons, banned above.
-module(zigvm_timer_bif_SUITE).

-export([all/0,
         c_send_after_delivery/1, c_start_timer_delivery/1,
         c_send_after_zero/1, c_send_after_ordering/1,
         c_mixed_kind_ordering/1,
         c_cancel_before_expiry/1, c_cancel_after_delivery/1,
         c_read_timer_live/1, c_read_timer_expired/1,
         c_cancel_timer2_options/1, c_timer_badargs/1,
         c_send_after_name/1,
         id/1]).

%% The suite manifest (common_test `all/0` contract). MIRRORED in order by
%% harness/suite_runner.ml's timer_bif_suite.case_names (ncases/1 lockstep).
all() ->
    [c_send_after_delivery, c_start_timer_delivery,
     c_send_after_zero, c_send_after_ordering,
     c_mixed_kind_ordering,
     c_cancel_before_expiry, c_cancel_after_delivery,
     c_read_timer_live, c_read_timer_expired,
     c_cancel_timer2_options, c_timer_badargs,
     c_send_after_name].

%% Constant-folding barrier: pure-value operands go through this export.
id(X) -> X.

%% --- send_after/3 delivery (send_after_1-class) ---------------------------
%% The armed message is delivered VERBATIM (a composite payload, compared
%% structurally) and the ref is a reference; after delivery read_timer is
%% false. DELIVERY + payload facts only — never elapsed time.
c_send_after_delivery(_) ->
    Msg = id({hello, [1, 2, 3], #{k => v}}),
    R = erlang:send_after(id(50), self(), Msg),
    IsR = is_reference(R),
    Got = receive X -> X after 1000 -> timeout end,
    IsR andalso (Got =:= Msg) andalso (erlang:read_timer(R) =:= false)
        andalso flushed().

%% --- start_timer/3 delivery (start_timer_1-class) -------------------------
%% start_timer wraps: the delivered term is {timeout, TRef, Msg} binding the
%% SAME reference start_timer returned.
c_start_timer_delivery(_) ->
    R = erlang:start_timer(id(50), self(), id(plopp)),
    Got = receive {timeout, R, plopp} -> true after 1000 -> false end,
    Got andalso (erlang:read_timer(R) =:= false) andalso flushed().

%% --- zero timeout ---------------------------------------------------------
%% send_after(0, ...) delivers the bare message; the timer is spent after.
c_send_after_zero(_) ->
    R = erlang:send_after(id(0), self(), id(zero)),
    Got = receive X -> X after 1000 -> timeout end,
    (Got =:= zero) andalso (erlang:read_timer(R) =:= false)
        andalso (erlang:cancel_timer(R) =:= false) andalso flushed().

%% --- ordering of two timers (send_after_2-class) --------------------------
%% Two timers armed OUT of deadline order arrive IN deadline order (an
%% ordering fact, not a duration fact). Distinct timeouts only — OTP does not
%% guarantee ordering for equal timeouts (send_after_3's commented block).
c_send_after_ordering(_) ->
    _ = erlang:send_after(id(300), self(), id(b300)),
    _ = erlang:send_after(id(100), self(), id(a100)),
    F = receive X -> X after 1000 -> timeout end,
    S = receive Y -> Y after 1000 -> timeout end,
    (F =:= a100) andalso (S =:= b300) andalso flushed().

%% --- mixed send_after/start_timer ordering --------------------------------
%% Both timer kinds share one deadline order: 50 (send_after) < 150
%% (start_timer) < 250 (send_after), armed in reverse order.
c_mixed_kind_ordering(_) ->
    _ = erlang:send_after(id(250), self(), id(third)),
    R = erlang:start_timer(id(150), self(), id(second)),
    _ = erlang:send_after(id(50), self(), id(first)),
    M1 = receive X -> X after 1000 -> timeout end,
    M2 = receive Y -> Y after 1000 -> timeout end,
    M3 = receive Z -> Z after 1000 -> timeout end,
    (M1 =:= first) andalso (M2 =:= {timeout, R, second}) andalso (M3 =:= third)
        andalso flushed().

%% --- cancel before expiry (start_timer_1 / cancel_timer_1-class) ----------
%% cancel_timer/1 on a LIVE timer returns the remaining time as an integer in
%% (0, N] (a return-DOMAIN fact — the exact value is not asserted); the
%% message is never delivered; a second cancel returns false. Both kinds.
c_cancel_before_expiry(_) ->
    N = id(60000),
    R1 = erlang:send_after(N, self(), never1),
    R2 = erlang:start_timer(N, self(), never2),
    C1 = erlang:cancel_timer(R1),
    C2 = erlang:cancel_timer(R2),
    Dom = is_integer(C1) andalso C1 > 0 andalso C1 =< N
          andalso is_integer(C2) andalso C2 > 0 andalso C2 =< N,
    Again = (erlang:cancel_timer(R1) =:= false)
            andalso (erlang:cancel_timer(R2) =:= false),
    NoDeliver = receive never1 -> false; {timeout, R2, never2} -> false
                after 30 -> true end,
    Dom andalso Again andalso NoDeliver andalso flushed().

%% --- cancel after delivery ------------------------------------------------
%% Once the message has been delivered the timer is spent: cancel_timer ->
%% false, read_timer -> false; cancel_timer on a never-armed ref -> false
%% (cancel_timer_1-class trivial arm).
c_cancel_after_delivery(_) ->
    R = erlang:send_after(id(30), self(), gone),
    ok = receive gone -> ok after 1000 -> timeout end,
    (erlang:cancel_timer(R) =:= false)
        andalso (erlang:read_timer(R) =:= false)
        andalso (erlang:cancel_timer(make_ref()) =:= false)
        andalso flushed().

%% --- read_timer/1 on a live timer (read_timer-class) ----------------------
%% read_timer on a LIVE timer is an integer in (0, N] and does NOT cancel
%% (a second read still reports an integer); cancel then returns the
%% remaining integer, after which read reports false.
c_read_timer_live(_) ->
    N = id(60000),
    R = erlang:send_after(N, self(), never),
    V1 = erlang:read_timer(R),
    V2 = erlang:read_timer(R),
    C = erlang:cancel_timer(R),
    V3 = erlang:read_timer(R),
    is_integer(V1) andalso V1 > 0 andalso V1 =< N
        andalso is_integer(V2) andalso V2 > 0 andalso V2 =< N
        andalso is_integer(C)
        andalso (V3 =:= false) andalso flushed().

%% --- read_timer/1 on an expired timer (read_timer_trivial-class) ----------
%% A live timer reads as an integer; after its delivery it reads false; a
%% never-armed ref reads false.
c_read_timer_expired(_) ->
    R = erlang:start_timer(id(30), self(), tick),
    Live = is_integer(erlang:read_timer(R)),
    ok = receive {timeout, R, tick} -> ok after 1000 -> timeout end,
    Live andalso (erlang:read_timer(R) =:= false)
        andalso (erlang:read_timer(make_ref()) =:= false)
        andalso flushed().

%% --- cancel_timer/2 option gates (cancel_timer_sync-class, sync subset) ----
%% {info,false} -> ok whether or not the timer is live; {info,true} -> the
%% remaining integer on a live timer, false on an unknown ref.
c_cancel_timer2_options(_) ->
    N = id(60000),
    R1 = erlang:send_after(N, self(), o1),
    R2 = erlang:send_after(N, self(), o2),
    A = erlang:cancel_timer(R1, id([{info, false}])),
    B = erlang:cancel_timer(R2, id([{info, true}])),
    C = erlang:cancel_timer(make_ref(), id([{info, true}])),
    D = erlang:cancel_timer(make_ref(), id([{info, false}])),
    (A =:= ok) andalso is_integer(B) andalso B > 0 andalso B =< N
        andalso (C =:= false) andalso (D =:= ok) andalso flushed().

%% --- error arms (start_timer_e / send_after_e / cancel_timer_e /
%% read_timer_trivial-class, local subset — no ?CT_PEER cross-node arms) -----
%% Negative, float, atom and >= 2^64 Time -> badarg; non-ref arguments to
%% cancel_timer/read_timer -> badarg. All operands through id/1.
c_timer_badargs(_) ->
    bad(fun() -> erlang:send_after(id(-4), self(), x) end)
        andalso bad(fun() -> erlang:send_after(id(4.5), self(), x) end)
        andalso bad(fun() -> erlang:send_after(id(a), self(), x) end)
        andalso bad(fun() -> erlang:send_after(id(1) bsl 64, self(), x) end)
        andalso bad(fun() -> erlang:start_timer(id(-4), self(), x) end)
        andalso bad(fun() -> erlang:start_timer(id(4.5), self(), x) end)
        andalso bad(fun() -> erlang:start_timer(id(a), self(), x) end)
        andalso bad(fun() -> erlang:cancel_timer(id(1)) end)
        andalso bad(fun() -> erlang:cancel_timer(id(a)) end)
        andalso bad(fun() -> erlang:read_timer(id(42)) end)
        andalso bad(fun() -> erlang:read_timer(id(ab)) end)
        andalso flushed().

%% --- registered-NAME destination (registered_process-class, live subset) ---
%% send_after to an atom Dest routes through the registry at FIRE time; a
%% name registered to self receives the message.
c_send_after_name(_) ->
    register(ztb_name, self()),
    _ = erlang:send_after(id(30), id(ztb_name), id(hello_name)),
    Got = receive X -> X after 1000 -> timeout end,
    unregister(ztb_name),
    (Got =:= hello_name) andalso flushed().

%% --- local helpers (self-contained; nothing external to load) -------------
%% True iff the throwing thunk raises error:badarg.
bad(F) -> try F() of _ -> false catch error:badarg -> true; _:_ -> false end.

%% Mailbox hygiene: TRUE iff the mailbox is empty (a leftover message is a
%% case failure here, not a poisoned NEXT case). `after 0` is deterministic
%% on the virtual clock.
flushed() -> receive _ -> false after 0 -> true end.
