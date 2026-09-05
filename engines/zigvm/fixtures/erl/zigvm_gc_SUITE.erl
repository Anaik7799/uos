%% zigvm_gc_SUITE — a PURE-BUT-CONCURRENT curated subset of
%% erts/emulator/test/gc_SUITE.erl in the common_test SUITE shape (`all/0` +
%% `Case(Config)` funs) with NO common_test / test_server dependency
%% (CT-on-zigvm is Epoch E7). A case returns the atom `true` on success; the
%% runner (zigvm_gc_suite_runner) counts a case EQ only when BOTH VMs'
%% `Suite:Case([])` returns `true`. A case that needs a BIF/opcode a VM lacks
%% raises -> caught -> counted `fail` (a visible divergence, never silent).
%%
%% THE GC VERB (probed 2026-07-23 on the prebuilt zigvm CLI + pinned OTP-30
%% oracle): `erlang:garbage_collect/0,1,2` are preloaded-erlang.erl WRAPPERS
%% (not bif.tab rows) and resolve `undef` from a compiled beam on zigvm today.
%% Their definitional expansion IS implemented and EQ on both VMs:
%% `erlang:garbage_collect() -> erts_internal:garbage_collect(major)`
%% (third_party/otp/erts/preloaded/src/erlang.erl), and
%% `erts_internal:garbage_collect(major|minor)` returns `true` on BOTH VMs
%% (and `badarg`s on any other atom on BOTH). Every case below therefore
%% requests GC through the internal verb — the same operation gc_SUITE's
%% `garbage_collect()` performs, minus the un-expanded wrapper.
%%
%% What the curation KEEPS from gc_SUITE's spirit: GC returns `true` and the
%% process continues with its live data INTACT (grow_heap/grow_stack_heap-class
%% build-collect-verify, made DETERMINISTIC — no erlang:timestamp/
%% unique_integer make_arbit), GC inside a spawned process, repeated-GC
%% idempotence on live data, GC with the mailbox non-empty (messages survive),
%% and closure/ref/pid/binary/map survival across a collection.
%%
%% EXCLUDED (probed or rule-bound, visible here, never silent):
%%  - garbage_collect(OtherPid) / garbage_collect(Pid, Opts): the substrate
%%    `erts_internal:request_system_task(P, inherit, {garbage_collect, Ref,
%%    major})` DIVERGES (probed: oracle -> `ok` + reply message
%%    `{garbage_collect, Ref, true}`; zigvm -> returns `true`, NO reply ever
%%    delivered). Real divergence, reported to the integrator — not curated
%%    into a case that would count a false `fail`.
%%  - max_heap_size / max_heap_size_large_hfrag: `process_flag(max_heap_size,_)`
%%    kill semantics unprobeable and `process_flag(fullsweep_after, 0)` is
%%    `badarg` on zigvm (probed).
%%  - minor_major_gc_option_self/async, gc_dirty_exec_proc: need
%%    `erlang:trace/3` garbage_collection tracing + erts_debug (banned).
%%  - gc_signal_order: needs `{scheduler,1}`/priority flags + async GC (above).
%%  - alias_signals_in_gc: needs alias/unalias + scheduler pinning.
%%  - show_heap heap_size/stack_size assertions: impl-specific counters, banned.
-module(zigvm_gc_SUITE).

-export([all/0, id/1,
         c_gc_major/1, c_gc_minor/1, c_gc_reject/1,
         c_gc_data_intact/1, c_gc_binaries_intact/1, c_gc_maps_intact/1,
         c_gc_grow_shrink/1, c_gc_idempotent/1, c_gc_after_drop/1,
         c_gc_closure_env/1, c_gc_ref_pid_survive/1,
         c_gc_in_spawned/1, c_gc_mailbox_intact/1,
         %% spawned entry points (exported so spawn/3's MFA resolves).
         ps_gc_child/2, ms_sender/1]).

%% The suite manifest (common_test `all/0` contract). MIRRORED in order by
%% harness/suite_runner.ml's spec case_names (ncases/1 lockstep) on integration.
all() ->
    [c_gc_major, c_gc_minor, c_gc_reject,
     c_gc_data_intact, c_gc_binaries_intact, c_gc_maps_intact,
     c_gc_grow_shrink, c_gc_idempotent, c_gc_after_drop,
     c_gc_closure_env, c_gc_ref_pid_survive,
     c_gc_in_spawned, c_gc_mailbox_intact].

%% Exported identity — routes pure-value operands through the VM so
%% constant-folding can never bypass it.
id(X) -> X.

%% The gc verb under test: `erlang:garbage_collect()`'s preloaded definition.
gc() -> erts_internal:garbage_collect(major).
gc(Type) -> erts_internal:garbage_collect(Type).

%% --- gc returns exactly `true` (garbage_collect/0 contract) ----------------
c_gc_major(_) ->
    (gc(id(major)) =:= true) andalso (gc(id(major)) =:= true).

c_gc_minor(_) ->
    (gc(id(minor)) =:= true) andalso (gc(id(minor)) =:= true).

%% --- rejection: any non-major/minor request is badarg on both VMs ----------
c_gc_reject(_) ->
    try gc(id(bogus_gc_type)) of
        _ -> false
    catch
        error:badarg -> true;
        _:_ -> false
    end.

%% --- nested-term survival: build, collect, deep-compare against a rebuild --
c_gc_data_intact(_) ->
    T = mk_tree(id(6)),
    G = gc(),
    (G =:= true) andalso (T =:= mk_tree(id(6))).

%% --- binaries: heap/refc binaries, sub-binaries, and concats survive -------
c_gc_binaries_intact(_) ->
    B = list_to_binary(mk_bytes(id(255))),
    <<H:8, Rest/binary>> = B,
    C = <<Rest/binary, H:8>>,
    Small = <<(id(5)):3, (id(9)):5>>,
    G = gc(),
    B2 = list_to_binary(mk_bytes(id(255))),
    <<H2:8, Rest2/binary>> = B2,
    (G =:= true)
        andalso (B =:= B2)
        andalso (H =:= H2) andalso (Rest =:= Rest2)
        andalso (C =:= <<Rest2/binary, H2:8>>)
        andalso (byte_size(B) =:= 255) andalso (byte_size(Rest) =:= 254)
        andalso (Small =:= <<(id(5)):3, (id(9)):5>>).

%% --- maps: every key/value pair survives a collection ----------------------
c_gc_maps_intact(_) ->
    M = mk_map(id(40)),
    G = gc(),
    (G =:= true)
        andalso (map_size(M) =:= 40)
        andalso chk_map(M, 40)
        andalso (M =:= mk_map(id(40))).

%% --- grow_heap-class: grow live data, collect, verify; shrink, collect,
%% verify (deterministic replacement for grow_heap1's random walk) -----------
c_gc_grow_shrink(_) ->
    L = mk_list(id(128)),
    G1 = gc(),
    Ok1 = (G1 =:= true) andalso (L =:= mk_list(id(128))),
    L2 = drop(id(64), L),
    G2 = gc(),
    Ok1 andalso (G2 =:= true) andalso (L2 =:= mk_list(id(64))).

%% --- repeated-gc idempotence on live data (major/minor alternation) --------
c_gc_idempotent(_) ->
    L = mk_list(id(12)),
    gc_n(10) andalso (L =:= mk_list(id(12))).

gc_n(0) -> true;
gc_n(N) ->
    T = case N rem 2 of 0 -> major; 1 -> minor end,
    (gc(T) =:= true) andalso gc_n(N - 1).

%% --- garbage is dropped without touching the live value --------------------
c_gc_after_drop(_) ->
    Live = mk_item(id(5)),
    ok = mk_drop(id(64)),
    G = gc(),
    (G =:= true) andalso (Live =:= mk_item(id(5))).

mk_drop(N) -> _ = mk_list(N), ok.

%% --- a closure's captured environment survives relocation ------------------
c_gc_closure_env(_) ->
    Env = mk_list(id(8)),
    F = fun (X) -> {X, Env} end,
    G = gc(),
    (G =:= true) andalso (F(ok) =:= {ok, mk_list(id(8))}).

%% --- refs and pids survive a collection (identity, not just shape) ---------
c_gc_ref_pid_survive(_) ->
    R = make_ref(),
    M = #{r => R, p => self()},
    G = gc(),
    (G =:= true)
        andalso (maps:get(r, M) =:= R)
        andalso (maps:get(p, M) =:= self())
        andalso (R =/= make_ref()).

%% --- gc INSIDE a spawned process: the child collects, verifies its own live
%% data, and reports; the child terminates after its single send -------------
c_gc_in_spawned(_) ->
    _P = spawn(zigvm_gc_SUITE, ps_gc_child, [self(), id(24)]),
    R = receive {gc_child, Ok} -> Ok after 1000 -> false end,
    flush(),
    R.

ps_gc_child(Parent, N) ->
    T = mk_list(N),
    G = erts_internal:garbage_collect(major),
    Parent ! {gc_child, (G =:= true) andalso (T =:= mk_list(N))}.

%% --- gc with a NON-EMPTY mailbox: queued messages survive the collection,
%% in order, deep-intact. The `sent` sync is a SELECTIVE receive (skips the
%% queued m-messages); the sender terminates after its last send -------------
c_gc_mailbox_intact(_) ->
    _P = spawn(zigvm_gc_SUITE, ms_sender, [self()]),
    Synced = receive sent -> true after 1000 -> false end,
    G = gc(),
    R1 = receive {m, 1, I1} -> I1 =:= mk_item(id(1)) after 1000 -> false end,
    R2 = receive {m, 2, I2} -> I2 =:= mk_item(id(2)) after 1000 -> false end,
    R3 = receive {m, 3, I3} -> I3 =:= mk_item(id(3)) after 1000 -> false end,
    flush(),
    Synced andalso (G =:= true) andalso R1 andalso R2 andalso R3.

ms_sender(Parent) ->
    Parent ! {m, 1, mk_item(1)},
    Parent ! {m, 2, mk_item(2)},
    Parent ! {m, 3, mk_item(3)},
    Parent ! sent.

%% --- deterministic data builders (make_arbit/make_string replacements; no
%% erlang:timestamp, no unique_integer — same value every run on every VM) ---
mk_item(N) -> {N, N * N, <<N:32>>, [a, N], #{k => N}}.

mk_list(0) -> [];
mk_list(N) -> [mk_item(N) | mk_list(N - 1)].

mk_tree(0) -> {leaf, <<0:8>>};
mk_tree(N) ->
    {node, N, <<N:16, (N * 7):16>>,
     #{l => mk_tree(N - 1), r => mk_tree(N - 1)},
     [N, {N, N}]}.

mk_map(0) -> #{};
mk_map(N) -> maps:put({k, N}, [N, N * N, <<N:16>>], mk_map(N - 1)).

chk_map(_M, 0) -> true;
chk_map(M, N) ->
    (maps:get({k, N}, M) =:= [N, N * N, <<N:16>>]) andalso chk_map(M, N - 1).

mk_bytes(0) -> [];
mk_bytes(N) -> [N band 255 | mk_bytes(N - 1)].

drop(0, L) -> L;
drop(N, [_ | T]) -> drop(N - 1, T).

%% --- mailbox hygiene: a leftover message must never leak into the NEXT case
flush() ->
    receive _ -> flush() after 0 -> ok end.
