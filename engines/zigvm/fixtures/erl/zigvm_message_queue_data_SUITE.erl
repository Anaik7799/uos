%% zigvm_message_queue_data_SUITE — a PURE-BUT-CONCURRENT subset of
%% erts/emulator/test/message_queue_data_SUITE, in the common_test SUITE shape
%% (`all/0` + `Case(Config)` funs) with NO common_test / test_server dependency
%% (CT-on-zigvm is Epoch E7). Every case is runnable on the zigvm CLI byte-EQ
%% vs the pinned OTP-30 oracle: a case returns the atom `true` on success; the
%% runner (zigvm_message_queue_data_suite_runner) counts a case EQ only when
%% BOTH VMs' `Suite:Case([])` returns `true`.
%%
%% SCOPE HONESTY (probed on the prebuilt zigvm CLI before curation):
%%   * The DEFAULT message_queue_data read is EQ: process_info(Pid,
%%     message_queue_data) =:= {message_queue_data, on_heap} for self AND for
%%     spawned children (E7.5 default) — curated below.
%%   * SETTING the flag does NOT round-trip on zigvm: process_flag(
%%     message_queue_data, off_heap) AND ... on_heap both raise badarg (the
%%     oracle returns the previous value). EXCLUDED: basic_test's
%%     set/read-back ladder, change_to_off_heap*, and every off_heap-delivery
%%     assertion. Only the INVALID-value rejection (blupp -> error:badarg) is
%%     EQ on both VMs and curated (c_flag_badarg).
%%   * spawn_opt {message_queue_data, _} options are IGNORED by zigvm (a bad
%%     value does not raise; an off_heap request reads back on_heap). EXCLUDED.
%%   * erlang:system_info(message_queue_data) raises badarg on zigvm;
%%     garbage_collect/0 is undef. EXCLUDED (blocks change_to_off_heap_gc).
%%   * process_info(P, messages) ({messages, [...]}) is outside the permitted
%%     process_info surface. The parent suite's process_info_messages ORDER
%%     facts are curated instead as actual-delivery FIFO cases
%%     (c_fifo_order_self / c_fifo_order_cross / c_selective_receive).
%%
%% Every case is self-contained + deterministic: children terminate, the
%% mailbox is proven empty before returning (mbox_empty/0), trap_exit is
%% reset, and every potentially-unfulfilled receive is bounded by `after`
%% (the zigvm virtual clock fires `after` deterministically; no elapsed-time
%% VALUES are asserted — ordering/delivery facts only). Pure-value operands
%% that constant folding could bypass are routed through ?MODULE:id/1.
-module(zigvm_message_queue_data_SUITE).

-export([all/0,
         c_default_read/1, c_default_spawned/1, c_default_child_self_report/1,
         c_flag_badarg/1,
         c_fifo_order_self/1, c_fifo_order_cross/1, c_selective_receive/1,
         c_recv_after_fires/1, c_exit_self_trap/1,
         c_read_stable_across_traffic/1, c_deep_message_intact/1,
         %% spawned entry points (exported so spawn/3's MFA resolves) + the
         %% constant-fold shield.
         ps_hold/0, ps_mqd_reporter/1, ps_seq_sender/1, ps_echo/1, id/1]).

%% The suite manifest (common_test `all/0` contract). MIRRORED in order by
%% harness/suite_runner.ml's suite_spec.case_names (ncases/1 lockstep).
all() ->
    [c_default_read, c_default_spawned, c_default_child_self_report,
     c_flag_badarg,
     c_fifo_order_self, c_fifo_order_cross, c_selective_receive,
     c_recv_after_fires, c_exit_self_trap,
     c_read_stable_across_traffic, c_deep_message_intact].

%% --- the default flag read (basic_test's first ladder rung) ----------------
%% {message_queue_data, on_heap} is the read for a default-spawned process on
%% both VMs (OTP default +hmqd on_heap == zigvm E7.5 default). The expected
%% atom is routed through ?MODULE:id/1 so the comparison happens in the VM.
c_default_read(_) ->
    process_info(self(), message_queue_data)
        =:= {message_queue_data, ?MODULE:id(on_heap)}.

%% A spawned child's flag, read CROSS-PROCESS by the parent, is the same
%% default (basic_test's P1 rung, minus the spawn_opt mqd options).
c_default_spawned(_) ->
    P = spawn(?MODULE, ps_hold, []),
    R = process_info(P, message_queue_data),
    P ! stop,
    (R =:= {message_queue_data, ?MODULE:id(on_heap)}) andalso mbox_empty().

%% The child reads its OWN flag and reports it as a message — proving both the
%% default read in a non-root process and message delivery of the reading.
c_default_child_self_report(_) ->
    _ = spawn(?MODULE, ps_mqd_reporter, [self()]),
    R = receive {mqd, V} -> V after 1000 -> timeout end,
    (R =:= {message_queue_data, ?MODULE:id(on_heap)}) andalso mbox_empty().

%% --- invalid-value rejection (basic_test's blupp rung) ---------------------
%% process_flag(message_queue_data, blupp) raises error:badarg on BOTH VMs.
%% (Setting a VALID value is a known zigvm divergence — see the scope-honesty
%% header — so only the rejection arm is curated.)
c_flag_badarg(_) ->
    try process_flag(message_queue_data, ?MODULE:id(blupp)) of
        _ -> false
    catch
        error:badarg -> true;
        _:_ -> false
    end.

%% --- delivery-order facts (process_info_messages, as actual receives) ------
%% Self-sends arrive FIFO under the default flag.
c_fifo_order_self(_) ->
    self() ! m1, self() ! m2, self() ! m3, self() ! m4,
    L = [recv_any(), recv_any(), recv_any(), recv_any()],
    (L =:= [m1, m2, m3, m4]) andalso mbox_empty().

%% Cross-process sends from one child arrive FIFO in the parent.
c_fifo_order_cross(_) ->
    _ = spawn(?MODULE, ps_seq_sender, [self()]),
    L = [recv_any(), recv_any(), recv_any()],
    (L =:= [s1, s2, s3]) andalso mbox_empty().

%% Selective receive picks matching messages (in FIFO order among matches)
%% past a non-matching one; the leftover is still deliverable afterwards.
c_selective_receive(_) ->
    self() ! {k, 1}, self() ! other, self() ! {k, 2},
    A = receive {k, N1} -> N1 after 1000 -> timeout end,
    B = receive {k, N2} -> N2 after 1000 -> timeout end,
    C = receive other -> other after 1000 -> timeout end,
    ({A, B, C} =:= {1, 2, other}) andalso mbox_empty().

%% --- receive-after under the default flag ----------------------------------
%% An empty-mailbox `receive after 10` fires (deterministically, virtual
%% clock — the FACT that it fires is asserted, never an elapsed-time value),
%% and the mailbox still delivers normally afterwards.
c_recv_after_fires(_) ->
    R1 = receive never -> bad after 10 -> fired end,
    self() ! msg,
    R2 = receive msg -> got after 1000 -> timeout end,
    ({R1, R2} =:= {fired, got}) andalso mbox_empty().

%% --- exit/2-to-self as a mailbox message (make_misc_messages' first row) ---
%% A trapping process's exit(self(), Reason) lands as {'EXIT', Self, Reason}
%% in its own (on_heap) message queue. trap_exit is reset before returning.
c_exit_self_trap(_) ->
    process_flag(trap_exit, true),
    exit(self(), tjena),
    R = receive {'EXIT', P, tjena} -> P =:= self() after 1000 -> false end,
    _ = process_flag(trap_exit, false),
    R andalso mbox_empty().

%% --- flag-read stability across message traffic ----------------------------
%% The read is the same before and after a send/receive round (no traffic-
%% induced flag drift).
c_read_stable_across_traffic(_) ->
    R0 = process_info(self(), message_queue_data),
    self() ! ping,
    ok = receive ping -> ok after 1000 -> timeout end,
    R1 = process_info(self(), message_queue_data),
    (R0 =:= {message_queue_data, ?MODULE:id(on_heap)}) andalso (R1 =:= R0)
        andalso mbox_empty().

%% --- message-copy homomorphism (on_heap delivery preserves the term) -------
%% A deep mixed term (tuple/list/map/binary/bignum-free ints) survives TWO
%% deliveries (parent -> echo child -> parent) content-identical.
c_deep_message_intact(_) ->
    P = spawn(?MODULE, ps_echo, [self()]),
    T = {deep, [1, [2, 3], {4, <<5, 6, 7>>}], #{k => [8, 9], <<"b">> => ten}},
    P ! {echo, T},
    R = receive {echoed, Back} -> Back =:= T after 1000 -> false end,
    R andalso mbox_empty().

%% --- spawned entry points ---------------------------------------------------
ps_hold() -> receive stop -> ok end.
ps_mqd_reporter(Parent) ->
    Parent ! {mqd, process_info(self(), message_queue_data)}.
ps_seq_sender(Parent) -> Parent ! s1, Parent ! s2, Parent ! s3.
ps_echo(Parent) -> receive {echo, T} -> Parent ! {echoed, T} end.

%% --- local helpers (self-contained; nothing external to load) ---------------
%% Exported identity: routes pure operands through the VM so constant folding
%% cannot decide a case at compile time.
id(X) -> X.

%% The mailbox is empty NOW (a leftover message would poison the next case).
mbox_empty() -> receive _ -> false after 0 -> true end.

%% Bounded any-receive: a delivery bug yields the atom `timeout` (a visible
%% order mismatch), never a hang.
recv_any() -> receive X -> X after 1000 -> timeout end.
