%% Curated PURE subset of erts/emulator/test/ref_SUITE.erl (E7 suite closure).
%% The real suite checks that refs don't wrap (wrap_1, a 30s spawn/timer probe),
%% that ref ORDERING is total and ets-visible (compare_list/compare_ets over
%% hand-built EXTERNAL refs via binary_to_term), and that internal/external ref
%% HEAP SIZES match the efficiency guide (erts_debug:size + a peer node). None
%% of those observations are portable: ref VALUES, sizes and wrap horizons are
%% VM-private. These cases mirror the suite's algebraic content instead —
%% make_ref/0 PROPERTIES only: reflexive equality, pairwise freshness,
%% is_reference/1 type membership (pos+neg), total-order CONSISTENCY among refs
%% (never specific values), the cross-type term-order rank of references
%% (number < atom < reference < tuple < map < nil < list < bitstring), and
%% exact round-trips of refs through tuples, maps (as key AND value), and
%% pattern matches. No ref value is ever printed or compared across VMs, so
%% every case is deterministic-boolean on both VMs. Runtime operands are routed
%% through the EXPORTED ?MODULE:id/1 (an external call erlc cannot fold — the
%% zigvm_big_SUITE c_bitwise_2pow pattern). No ct/port/node/spawn/ets/io
%% dependency — runnable directly on the zigvm CLI byte-EQ vs OTP-30.
-module(zigvm_ref_SUITE).
-export([all/0, id/1, c_identity/1, c_distinct/1, c_many_unique/1,
         c_is_reference/1, c_guard_dispatch/1, c_order_consistency/1,
         c_order_types/1, c_tuple_roundtrip/1, c_map_roundtrip/1,
         c_pattern_match/1]).

all() ->
    [c_identity, c_distinct, c_many_unique, c_is_reference, c_guard_dispatch,
     c_order_consistency, c_order_types, c_tuple_roundtrip, c_map_roundtrip,
     c_pattern_match].

%% External-call identity: operands routed through here reach the VM as
%% runtime values, never as compile-time constants.
id(X) -> X.

%% A ref is equal to itself under both =:= and ==, and not unequal to itself
%% (reflexivity of exact and arithmetic equality on the reference type).
c_identity(_) ->
    R = ?MODULE:id(make_ref()),
    (R =:= R) andalso (R == R)
        andalso (not (R =/= R)) andalso (not (R /= R)).

%% Two make_ref/0 results are FRESH: unequal under =:= and ==, while each
%% still equals itself (the wrap_1 spirit at n=2, no timer).
c_distinct(_) ->
    R1 = ?MODULE:id(make_ref()),
    R2 = ?MODULE:id(make_ref()),
    (R1 =/= R2) andalso (R1 /= R2)
        andalso (not (R1 =:= R2)) andalso (not (R1 == R2))
        andalso (R1 =:= R1) andalso (R2 =:= R2).

%% Bounded freshness: 12 consecutive refs are PAIRWISE distinct (the wrap_1
%% no-early-repeat property, bounded and timerless).
c_many_unique(_) ->
    Refs = mk_refs(?MODULE:id(12)),
    all_distinct(Refs) andalso (len(Refs, 0) =:= 12).

mk_refs(0) -> [];
mk_refs(N) when N > 0 -> [make_ref() | mk_refs(N - 1)].

all_distinct([]) -> true;
all_distinct([R | T]) -> none_eq(R, T) andalso all_distinct(T).

none_eq(_R, []) -> true;
none_eq(R, [X | T]) -> (R =/= X) andalso none_eq(R, T).

%% is_reference/1 membership: true exactly on refs, false on every other
%% type probed (atom, integer, float, tuple, list, nil, map, binary, fun).
c_is_reference(_) ->
    R = ?MODULE:id(make_ref()),
    is_reference(R)
        andalso (not is_reference(?MODULE:id(an_atom)))
        andalso (not is_reference(?MODULE:id(42)))
        andalso (not is_reference(?MODULE:id(3.5)))
        andalso (not is_reference(?MODULE:id({R})))
        andalso (not is_reference(?MODULE:id([R])))
        andalso (not is_reference(?MODULE:id([])))
        andalso (not is_reference(?MODULE:id(#{a => R})))
        andalso (not is_reference(?MODULE:id(<<1,2,3>>)))
        andalso (not is_reference(?MODULE:id(fun ?MODULE:id/1))).

%% is_reference/1 as a GUARD steers clause selection (the guard kernel, not
%% just the BIF value).
c_guard_dispatch(_) ->
    (kind(?MODULE:id(make_ref())) =:= reference)
        andalso (kind(?MODULE:id(hello)) =:= other)
        andalso (kind(?MODULE:id({make_ref()})) =:= other)
        andalso (kind(?MODULE:id(7)) =:= other).

kind(X) when is_reference(X) -> reference;
kind(_) -> other.

%% Total-order CONSISTENCY among refs (compare_list's law without its pinned
%% external-ref values): exactly one of R1 < R2 / R2 < R1 holds; < agrees
%% with its converse >, with =< / >=, and with min/2 + max/2; and a 3-ref
%% insertion sort is =<-sorted while preserving membership.
c_order_consistency(_) ->
    R1 = ?MODULE:id(make_ref()),
    R2 = ?MODULE:id(make_ref()),
    R3 = ?MODULE:id(make_ref()),
    Lo = min(R1, R2),
    Hi = max(R1, R2),
    Sorted = isort(?MODULE:id([R3, R1, R2])),
    ((R1 < R2) xor (R2 < R1))
        andalso ((R1 < R2) =:= (R2 > R1))
        andalso ((R1 =< R2) =:= (not (R2 < R1)))
        andalso ((R1 >= R2) =:= (not (R1 < R2)))
        andalso ((Lo =:= R1) xor (Lo =:= R2))
        andalso ((Hi =:= R1) xor (Hi =:= R2))
        andalso (Lo =/= Hi) andalso (Lo < Hi)
        andalso is_sorted(Sorted)
        andalso member(R1, Sorted) andalso member(R2, Sorted)
        andalso member(R3, Sorted) andalso (len(Sorted, 0) =:= 3).

isort([]) -> [];
isort([X | T]) -> insert(X, isort(T)).

insert(X, []) -> [X];
insert(X, [Y | T]) when X =< Y -> [X, Y | T];
insert(X, [Y | T]) -> [Y | insert(X, T)].

is_sorted([]) -> true;
is_sorted([_]) -> true;
is_sorted([X, Y | T]) -> (X =< Y) andalso is_sorted([Y | T]).

member(_X, []) -> false;
member(X, [Y | T]) -> (X =:= Y) orelse member(X, T).

%% Cross-type term-order RANK of references: every number and atom sorts
%% below any ref; every tuple, map, nil, list and bitstring sorts above it
%% (the standard number < atom < reference < ... rank, value-free).
c_order_types(_) ->
    R = ?MODULE:id(make_ref()),
    (?MODULE:id(42) < R) andalso (?MODULE:id(3.5) < R)
        andalso (?MODULE:id(-1) < R)
        andalso (?MODULE:id(an_atom) < R) andalso (?MODULE:id(zzzz) < R)
        andalso (R < ?MODULE:id({})) andalso (R < ?MODULE:id({0}))
        andalso (R < ?MODULE:id(#{})) andalso (R < ?MODULE:id(#{a => 1}))
        andalso (R < ?MODULE:id([])) andalso (R < ?MODULE:id([0]))
        andalso (R < ?MODULE:id(<<>>)) andalso (R < ?MODULE:id(<<1>>)).

%% Refs round-trip through tuples EXACTLY: element/2 returns the same ref,
%% setelement/3 replaces one slot without disturbing the ref, and a tuple
%% pattern match rebinds it intact.
c_tuple_roundtrip(_) ->
    R = ?MODULE:id(make_ref()),
    T = ?MODULE:id({a, R, 1}),
    T2 = setelement(3, T, ?MODULE:id(b)),
    {a, X, 1} = T,
    (element(2, T) =:= R)
        andalso (X =:= R)
        andalso (T2 =:= {a, R, b})
        andalso (element(2, T2) =:= R)
        andalso (tuple_size(T) =:= 3).

%% Refs round-trip through maps as VALUE and as KEY (the compare_ets
%% "invisible term" hazard, keyed on exact equality instead of an ets table):
%% a ref key looks itself up, a FRESH ref is not a key, two ref keys coexist,
%% and updating one ref key leaves the other binding intact.
c_map_roundtrip(_) ->
    R1 = ?MODULE:id(make_ref()),
    R2 = ?MODULE:id(make_ref()),
    M = ?MODULE:id(#{k => R1}),
    MK = ?MODULE:id(#{R1 => a, R2 => b}),
    MK2 = MK#{R1 := c},
    (maps:get(k, M) =:= R1)
        andalso (map_size(MK) =:= 2)
        andalso maps:is_key(R1, MK) andalso maps:is_key(R2, MK)
        andalso (not maps:is_key(?MODULE:id(make_ref()), MK))
        andalso (maps:get(R1, MK) =:= a) andalso (maps:get(R2, MK) =:= b)
        andalso (maps:get(R1, MK2) =:= c) andalso (maps:get(R2, MK2) =:= b)
        andalso (map_size(MK2) =:= 2).

%% Refs as MATCH PATTERNS (bound-variable case discrimination) and captured
%% in a closure: an equal ref selects its clause, a fresh ref falls through,
%% and a fun capturing a ref recognises exactly that ref.
c_pattern_match(_) ->
    R1 = ?MODULE:id(make_ref()),
    R2 = ?MODULE:id(make_ref()),
    F = fun(Q) -> case Q of R1 -> yes; _ -> no end end,
    (pick(R1, ?MODULE:id(R1)) =:= hit)
        andalso (pick(R1, ?MODULE:id(R2)) =:= miss)
        andalso (F(?MODULE:id(R1)) =:= yes)
        andalso (F(?MODULE:id(R2)) =:= no)
        andalso (F(?MODULE:id(not_a_ref)) =:= no).

pick(R, R) -> hit;
pick(_, _) -> miss.

len([], Acc) -> Acc;
len([_ | T], Acc) -> len(T, Acc + 1).
