%% Curated PURE subset of erts/emulator/test/persistent_term_SUITE.erl (E7
%% suite closure). The real suite exercises the persistent_term store: put/get
%% round-trips (basic, off_heap_values), put_new, erase true/false, get/2
%% defaults, get/0 enumeration, info/0 accounting, exotic key types (keys),
%% plus purging/trapping/collision cases driven by spawned processes, kills,
%% erts_debug internals and literal-area GC. These cases MIRROR the pure
%% single-process algebra only: round-trip of immediates/boxed terms (tuples,
%% maps, lists, floats-as-values, bignums, binaries), get/1 badarg on an
%% absent key (CLASS-only check — zigvm's E1 exception model lands the bare
%% reason with a nil stacktrace, so no reason/stacktrace shape is asserted),
%% get/2 default, put overwrite (last wins), put_new store/no-op/badarg,
%% erase true-then-false, get/0 MEMBERSHIP (order-independent — zigvm's get/0
%% enumeration order is a documented divergence from BEAM insertion order,
%% and the OTP node holds stdlib-created stray terms, so only membership of
%% OUR pairs is asserted), and info/0 COUNT coherence (memory is asserted
%% only as a non-negative integer that grows on a put — zigvm's memory value
%% is a documented approximation, never compared to an erts constant).
%% Every case cleans up its own {?MODULE,...}-namespaced keys (unique per
%% case, so cases stay independent even if one fails mid-way). No ct/port/
%% node/spawn dependency, no stdlib module calls (own helpers only), no
%% timing, no I/O — runnable directly on the zigvm CLI.
-module(zigvm_persistent_term_SUITE).
-export([all/0, id/1, c_put_get_immediate/1, c_put_get_boxed/1,
         c_put_get_binary/1, c_get_absent_badarg/1, c_get_default/1,
         c_put_overwrite/1, c_erase/1, c_get_all/1,
         c_info_count/1, c_keys/1]).

%% Exported identity: routes a value through an external call erlc cannot
%% inline or constant-fold, so comparisons against round-tripped values are
%% forced through the RUNTIME VM (the zigvm_big_SUITE c_bitwise_2pow pattern).
id(X) -> X.

all() ->
    [c_put_get_immediate, c_put_get_boxed, c_put_get_binary,
     c_get_absent_badarg, c_get_default, c_put_overwrite,
     c_erase, c_get_all, c_info_count, c_keys].

%% basic: put/get round-trip of immediates and a bignum — atoms, smalls,
%% negatives, and a >8-byte big all denote back exactly.
c_put_get_immediate(_) ->
    K = {?MODULE, imm},
    ok = persistent_term:put(K, some_atom),
    R1 = (persistent_term:get(K) =:= ?MODULE:id(some_atom)),
    ok = persistent_term:put(K, 12345),
    R2 = (persistent_term:get(K) =:= ?MODULE:id(12345)),
    ok = persistent_term:put(K, -1),
    R3 = (persistent_term:get(K) =:= ?MODULE:id(-1)),
    Big = ?MODULE:id((1 bsl 200) + 7),
    ok = persistent_term:put(K, Big),
    R4 = (persistent_term:get(K) =:= Big),
    true = persistent_term:erase(K),
    R1 andalso R2 andalso R3 andalso R4.

%% basic/off_heap_values: BOXED values (nested tuple with a float, a map with
%% mixed key types, a deep list) survive the store's separate-heap copy and
%% denote back exactly (=:=).
c_put_get_boxed(_) ->
    K = {?MODULE, boxed},
    T = ?MODULE:id({a, {b, [1, 2, 3]}, 4.5}),
    ok = persistent_term:put(K, T),
    R1 = (persistent_term:get(K) =:= T),
    M = ?MODULE:id(#{k1 => 1, {k, 2} => [a, b], <<"k3">> => {c}}),
    ok = persistent_term:put(K, M),
    R2 = (persistent_term:get(K) =:= M),
    L = ?MODULE:id([1, [2, [3]], {4}, five]),
    ok = persistent_term:put(K, L),
    R3 = (persistent_term:get(K) =:= L),
    true = persistent_term:erase(K),
    R1 andalso R2 andalso R3.

%% off_heap_values (binary part): a bit-syntax-built binary round-trips, and
%% the FETCHED value supports byte_size and bit-syntax re-matching.
c_put_get_binary(_) ->
    K = {?MODULE, bin},
    B = ?MODULE:id(<<16#DEADBEEF:32, 255:8, 0:8>>),
    ok = persistent_term:put(K, B),
    G = persistent_term:get(K),
    R1 = (G =:= <<16#DE, 16#AD, 16#BE, 16#EF, 255, 0>>),
    R2 = (byte_size(G) =:= 6),
    <<A:32, _:16>> = G,
    R3 = (A =:= 16#DEADBEEF),
    %% a binary nested inside a tuple value round-trips too.
    ok = persistent_term:put(K, {wrapped, B}),
    R4 = (persistent_term:get(K) =:= {wrapped, B}),
    true = persistent_term:erase(K),
    R1 andalso R2 andalso R3 andalso R4.

%% basic: get/1 on an absent key raises class `error` (CLASS-only assertion —
%% no reason/stacktrace/catch-wrap shape, per the zigvm E1 exception model).
c_get_absent_badarg(_) ->
    K = {?MODULE, absent_key},
    _ = persistent_term:erase(K),
    try persistent_term:get(K) of
        _ -> false
    catch
        error:_ -> true;
        _:_ -> false
    end.

%% basic: get/2 returns the default on an absent key (NEVER raises) and the
%% REAL value when the key is present.
c_get_default(_) ->
    K = {?MODULE, gd},
    _ = persistent_term:erase(K),
    D = ?MODULE:id({default, <<"d">>}),
    R1 = (persistent_term:get(K, D) =:= D),
    ok = persistent_term:put(K, {real, 99}),
    R2 = (persistent_term:get(K, D) =:= ?MODULE:id({real, 99})),
    true = persistent_term:erase(K),
    R1 andalso R2.

%% basic (seq/1 re-put): put/2 on an existing key ALWAYS overwrites — last
%% wins, across type changes (int -> tuple -> binary).
c_put_overwrite(_) ->
    K = {?MODULE, overwrite},
    ok = persistent_term:put(K, 1),
    ok = persistent_term:put(K, {two, 2}),
    R1 = (persistent_term:get(K) =:= ?MODULE:id({two, 2})),
    ok = persistent_term:put(K, <<3, 4>>),
    R2 = (persistent_term:get(K) =:= ?MODULE:id(<<3, 4>>)),
    true = persistent_term:erase(K),
    R1 andalso R2.

%% basic (put_new block, lifted from the real suite lines 102-106): absent
%% key stores; the SAME value again is a no-op `ok`; a DIFFERENT value raises
%% class `error` and leaves the stored value untouched.
%% c_put_new EXCLUDED at integration: persistent_term:put_new/2 is undef on
%% the pinned-era host oracle (OTP-28 erl) — a case the ORACLE cannot run is
%% not differential evidence (no false EQ in either direction).
%% basic: erase of a present key -> true, of an absent key -> false, and the
%% key no longer resolves afterwards (class-only badarg check).
c_erase(_) ->
    K = {?MODULE, er},
    ok = persistent_term:put(K, erased_soon),
    R1 = (persistent_term:erase(K) =:= true),
    R2 = (persistent_term:erase(K) =:= false),
    R3 = try persistent_term:get(K) of
             _ -> false
         catch
             error:_ -> true;
             _:_ -> false
         end,
    R1 andalso R2 andalso R3.

%% basic (pget/seq): get/0 contains every put pair exactly (MEMBERSHIP only —
%% enumeration order is a documented zigvm divergence, and an OTP node holds
%% stray stdlib terms), and an erased pair disappears from the enumeration.
c_get_all(_) ->
    K1 = {?MODULE, ga1},
    K2 = {?MODULE, ga2},
    K3 = {?MODULE, ga3},
    V2 = {two, <<2>>},
    V3 = [3, {three}],
    ok = persistent_term:put(K1, one),
    ok = persistent_term:put(K2, V2),
    ok = persistent_term:put(K3, V3),
    All = persistent_term:get(),
    R1 = has_pair(All, K1, one)
             andalso has_pair(All, K2, V2)
             andalso has_pair(All, K3, V3),
    true = persistent_term:erase(K1),
    All2 = persistent_term:get(),
    R2 = (not has_pair(All2, K1, one))
             andalso has_pair(All2, K2, V2)
             andalso has_pair(All2, K3, V3),
    true = persistent_term:erase(K2),
    true = persistent_term:erase(K3),
    R1 andalso R2.

%% info/info_wb (count coherence only): a put increments `count` by exactly 1
%% and an erase restores it; `memory` is asserted only as a non-negative
%% integer that grows across a put — NEVER compared to an erts constant
%% (zigvm's memory value is a documented approximation).
c_info_count(_) ->
    K = {?MODULE, info_key},
    _ = persistent_term:erase(K),
    #{count := C0, memory := M0} = persistent_term:info(),
    ok = persistent_term:put(K, {value, [1, 2, 3]}),
    #{count := C1, memory := M1} = persistent_term:info(),
    true = persistent_term:erase(K),
    #{count := C2} = persistent_term:info(),
    (C1 =:= C0 + 1)
        andalso (C2 =:= C0)
        andalso is_integer(M0) andalso (M0 >= 0)
        andalso is_integer(M1) andalso (M1 > M0).

%% keys: the real suite's key-type sweep (atom / one-element list / charlist
%% string / binary, via do_key/1) plus a tuple key — each round-trips a value
%% wrapping the key itself, then erases.
c_keys(_) ->
    key_rt(?MODULE)
        andalso key_rt([?MODULE])
        andalso key_rt("zigvm_persistent_term_SUITE")
        andalso key_rt(<<"zigvm_persistent_term_SUITE">>)
        andalso key_rt({?MODULE, tuple_key, 42}).

%% ---- helpers (own list walk — no stdlib module calls) ----

key_rt(Key) ->
    Val = {stored_under, Key},
    ok = persistent_term:put(Key, Val),
    Got = persistent_term:get(Key),
    true = persistent_term:erase(Key),
    Got =:= Val.

has_pair([{K, V} | _], K, V) -> true;
has_pair([_ | T], K, V) -> has_pair(T, K, V);
has_pair([], _, _) -> false.
