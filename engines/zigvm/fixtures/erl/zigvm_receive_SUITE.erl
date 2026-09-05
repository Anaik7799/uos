%% zigvm_receive_SUITE — a PURE-BUT-CONCURRENT subset of
%% erts/emulator/test/receive_SUITE-class behaviour, in the common_test SUITE
%% shape (`all/0` + `Case(Config)` funs) with NO common_test / test_server
%% dependency (CT-on-zigvm is Epoch E7). Every case exercises receive-queue
%% semantics the zigvm scheduler-as-driver executes deterministically under the
%% virtual clock: selective receive (the matching message is removed, the rest
%% keep their queue order), `receive after 0` non-blocking polls,
%% `receive after N` racing an arriving message (delivery wins; the timeout
%% branch is only taken on a genuinely empty/non-matching queue), per-sender
%% FIFO signal order, mailbox flush patterns, receive-with-guard, the
%% make_ref()-selective-receive shape (the recv-marker optimization pattern:
%% Ref created immediately before the receive that matches on it), and the
%% timer-service delivery verbs (erlang:send_after / cancel_timer).
%%
%% The REAL receive_SUITE is dominated by recv-marker *performance* cases
%% (call_with_huge_message_queue, multi_recv_opt*, receive_opt_deferred_save)
%% that assert wall-clock timing ratios and inspect scheduler internals — those
%% are excluded here (no wall-clock DURATION assertion survives the virtual
%% clock; ordering/delivery facts only). What remains is the SEMANTIC content:
%% which message a receive picks, what stays queued, and when `after` fires.
%%
%% Discipline: every case is self-contained + deterministic — spawned children
%% terminate by construction, every receive is bounded (`after` a modest N, so
%% a bug is a false return, never a hang), the mailbox is verified EMPTY before
%% returning (a leftover message would poison the NEXT case), and pure-value
%% seeds are routed through the exported ?MODULE:id/1 so constant folding
%% cannot bypass the VM. A case returns the atom `true` on success; the runner
%% (zigvm_receive_suite_runner) counts a case EQ only when BOTH VMs'
%% `Suite:Case([])` returns `true`.
-module(zigvm_receive_SUITE).

-export([all/0,
         c_selective_basic/1, c_selective_ref/1,
         c_after_zero_poll/1, c_after_zero_nonmatching/1,
         c_after_msg_arrives/1, c_after_timeout_fires/1,
         c_sender_fifo/1, c_two_senders_fifo/1,
         c_flush_pattern/1, c_guard_receive/1,
         c_receive_in_between/1,
         c_send_after_delivery/1, c_cancel_timer/1,
         %% exported spawned entry points (so spawn/3's MFA resolves) + id/1
         %% (the constant-folding firewall).
         id/1, ref_responder/2, seq_sender/2, ping_sender/1]).

%% The suite manifest (common_test `all/0` contract). MIRRORED in order by
%% harness/suite_runner.ml's receive-suite spec case_names (ncases/1 lockstep).
all() ->
    [c_selective_basic, c_selective_ref,
     c_after_zero_poll, c_after_zero_nonmatching,
     c_after_msg_arrives, c_after_timeout_fires,
     c_sender_fifo, c_two_senders_fifo,
     c_flush_pattern, c_guard_receive,
     c_receive_in_between,
     c_send_after_delivery, c_cancel_timer].

%% Identity through an exported call — the compiler cannot constant-fold
%% across it, so seed values genuinely travel through the VM's send/receive
%% machinery.
id(X) -> X.

%% --- selective receive: pattern picks the match, the rest keep their order --
%% Queue [a1, b2, a3]; a selective receive of {b, V} removes ONLY b2; the two
%% a-messages are then received in their original relative order.
c_selective_basic(_) ->
    Me = self(),
    Me ! {id(a), id(1)},
    Me ! {id(b), id(2)},
    Me ! {id(a), id(3)},
    B = receive {b, V} -> V after 1000 -> timeout end,
    A1 = receive {a, W1} -> W1 after 1000 -> timeout end,
    A2 = receive {a, W2} -> W2 after 1000 -> timeout end,
    (B =:= 2) andalso (A1 =:= 1) andalso (A2 =:= 3) andalso mbox_empty().

%% --- make_ref selective receive (the recv-marker optimization shape) --------
%% Ref is created immediately before the request/receive pair — the exact shape
%% the compiler's receive optimization rewrites to a recv-marker — with decoy
%% messages queued BEFORE and AROUND the reply. The reply is picked by Ref;
%% both decoys stay queued in self-send order.
c_selective_ref(_) ->
    Me = self(),
    Me ! id(decoy1),
    Ref = make_ref(),
    _P = spawn(zigvm_receive_SUITE, ref_responder, [Me, Ref]),
    Me ! id(decoy2),
    R = receive {Ref, ref_reply} -> ok after 1000 -> timeout end,
    D1 = receive decoy1 -> ok after 1000 -> timeout end,
    D2 = receive decoy2 -> ok after 1000 -> timeout end,
    (R =:= ok) andalso (D1 =:= ok) andalso (D2 =:= ok) andalso mbox_empty().

%% --- receive after 0: a non-blocking poll -----------------------------------
%% Empty mailbox -> the after-0 branch; a queued message -> received, never the
%% timeout branch.
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

%% --- receive after N with a message arriving: delivery beats the timer ------
%% A child sends `ping`; the bounded receive takes the DELIVERY branch, never
%% the timeout branch (ordering/delivery fact only — no elapsed-time value).
c_after_msg_arrives(_) ->
    _P = spawn(zigvm_receive_SUITE, ping_sender, [self()]),
    R = receive ping -> delivered after 1000 -> timeout end,
    (R =:= delivered) andalso mbox_empty().

%% --- receive after N over an empty queue: the timeout branch fires ----------
%% Nothing is ever sent, so the ONLY exit is the after-branch (the virtual
%% clock fires it deterministically; on the oracle, after 30ms of wall time).
c_after_timeout_fires(_) ->
    R = receive never_sent -> wrong after 30 -> timed_out end,
    (R =:= timed_out) andalso mbox_empty().

%% --- per-sender FIFO: one sender's messages arrive in send order ------------
c_sender_fifo(_) ->
    _P = spawn(zigvm_receive_SUITE, seq_sender, [self(), id(s)]),
    X1 = receive {s, N1} -> N1 after 1000 -> timeout end,
    X2 = receive {s, N2} -> N2 after 1000 -> timeout end,
    X3 = receive {s, N3} -> N3 after 1000 -> timeout end,
    (X1 =:= 1) andalso (X2 =:= 2) andalso (X3 =:= 3) andalso mbox_empty().

%% --- two senders: FIFO holds per sender regardless of interleaving ----------
%% Two children each send {Tag,1},{Tag,2},{Tag,3}; the global interleave is not
%% asserted (a scheduler freedom), but a selective receive on each tag must see
%% 1,2,3 — the per-sender signal order is invariant on both VMs.
c_two_senders_fifo(_) ->
    _Pa = spawn(zigvm_receive_SUITE, seq_sender, [self(), id(ta)]),
    _Pb = spawn(zigvm_receive_SUITE, seq_sender, [self(), id(tb)]),
    A = [receive {ta, Na} -> Na after 1000 -> timeout end || _ <- [x, x, x]],
    B = [receive {tb, Nb} -> Nb after 1000 -> timeout end || _ <- [x, x, x]],
    (A =:= [1, 2, 3]) andalso (B =:= [1, 2, 3]) andalso mbox_empty().

%% --- mailbox flush pattern: drain everything, preserving queue order --------
c_flush_pattern(_) ->
    Me = self(),
    Me ! {m, id(10)},
    Me ! {m, id(20)},
    Me ! {m, id(30)},
    Flushed = flush([]),
    (Flushed =:= [{m, 10}, {m, 20}, {m, 30}]) andalso mbox_empty().

%% --- receive with a guard: first message SATISFYING the guard is picked -----
%% Queue [1,2,3,4,5]; `X when X > 3` skips 1..3 (they stay queued, in order)
%% and picks 4; the flush then sees [1,2,3,5].
c_guard_receive(_) ->
    Me = self(),
    send_each(Me, id([1, 2, 3, 4, 5])),
    V = receive X when is_integer(X), X > 3 -> X after 1000 -> timeout end,
    Rest = flush([]),
    (V =:= 4) andalso (Rest =:= [1, 2, 3, 5]) andalso mbox_empty().

%% --- receive in between sends: each scan starts from the queue head ---------
%% m1,m2 queued; receive m1; enqueue m3 BEHIND m2; selectively receive m3
%% (skipping the older m2, which stays); then receive m2. Every receive
%% re-scans from the head — a stale continuation would pick wrongly.
c_receive_in_between(_) ->
    Me = self(),
    Me ! id(m1),
    Me ! id(m2),
    R1 = receive m1 -> ok after 1000 -> timeout end,
    Me ! id(m3),
    R3 = receive m3 -> ok after 1000 -> timeout end,
    R2 = receive m2 -> ok after 1000 -> timeout end,
    (R1 =:= ok) andalso (R3 =:= ok) andalso (R2 =:= ok) andalso mbox_empty().

%% --- erlang:send_after/3: the timer service delivers the message ------------
%% Delivery fact only: the timer fires (virtual clock: deterministically;
%% oracle: within the 1000ms bound) and the message lands in the mailbox. The
%% timer ref is a reference. No elapsed-time value is compared.
c_send_after_delivery(_) ->
    T = erlang:send_after(id(10), self(), id(tmsg)),
    R = receive tmsg -> fired after 1000 -> timeout end,
    is_reference(T) andalso (R =:= fired) andalso mbox_empty().

%% --- erlang:cancel_timer/1: a cancelled timer never delivers ----------------
%% The cancel result is time-dependent in VALUE (remaining ms) so only its TYPE
%% is asserted (integer = was pending | false = already fired/cancelled); the
%% delivery fact — no `never` message ever arrives — is the law.
c_cancel_timer(_) ->
    T = erlang:send_after(id(60000), self(), id(never)),
    C = erlang:cancel_timer(T),
    Ok = is_integer(C) orelse (C =:= false),
    Ok andalso mbox_empty().

%% --- spawned entry points (terminate by construction) -----------------------
ref_responder(Parent, Ref) -> Parent ! {Ref, ref_reply}.
seq_sender(Parent, Tag) ->
    Parent ! {Tag, 1},
    Parent ! {Tag, 2},
    Parent ! {Tag, 3}.
ping_sender(Parent) -> Parent ! ping.

%% --- local helpers (self-contained; no lists:* to load) ---------------------
mbox_empty() -> receive _ -> false after 0 -> true end.

flush(Acc) -> receive X -> flush([X | Acc]) after 0 -> rev(Acc, []) end.

rev([], Acc) -> Acc;
rev([H | T], Acc) -> rev(T, [H | Acc]).

send_each(_Me, []) -> ok;
send_each(Me, [H | T]) -> Me ! H, send_each(Me, T).
