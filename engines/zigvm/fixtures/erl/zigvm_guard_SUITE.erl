%% Curated PURE subset of erts/emulator/test/guard_SUITE.erl (E7 suite closure).
%% The real suite exercises guard semantics: a guard-BIF error is a QUIET guard
%% failure (fall to the next clause), never an exception — plus type-test
%% totality, guard-BIF results on nasty-but-legal arguments, andalso/orelse in
%% guard position, and binary_part/2,3 as a guard BIF. These cases MIRROR
%% bad_arith, bad_tuple, type_tests, guard_bifs (succeed + fail halves),
%% guard_bif_binary_part (incl. the 2^64/-2^63 overflow probes, which badarg →
%% guard-fail on both VMs), and the gh_6634 `is_tuple andalso not ok`
%% regression, as self-contained BOOLEAN assertions. The exception-shape checks
%% (?assertError/function_clause catches) are re-expressed as clause
%% FALL-THROUGH to a default clause — same semantic truth, no dependence on the
%% divergent catch-wrap/stacktrace shape. Excluded: test_heap_guards (spawn/
%% receive/GC-filler driver), self()/node() value checks, float(Big) exactness,
%% round/2.5 ties. All runtime operands are routed through the EXPORTED
%% ?MODULE:id/1 so erlc cannot constant-fold the guard under test.
-module(zigvm_guard_SUITE).
-export([all/0, id/1, c_bad_arith/1, c_bad_tuple/1, c_type_tests/1,
         c_guard_bifs/1, c_guard_bifs_fail/1, c_trunc_round/1,
         c_andalso_orelse/1, c_guard_arith/1, c_binary_part/1,
         c_map_guards/1, c_term_order/1, c_semicolon_guards/1]).

all() ->
    [c_bad_arith, c_bad_tuple, c_type_tests, c_guard_bifs, c_guard_bifs_fail,
     c_trunc_round, c_andalso_orelse, c_guard_arith, c_binary_part,
     c_map_guards, c_term_order, c_semicolon_guards].

%% External call erlc cannot inline or constant-fold (see zigvm_big_SUITE).
id(X) -> X.

%% bad_arith: arithmetic on a non-number in a guard fails the guard quietly.
c_bad_arith(_) ->
    (bad_arith1(?MODULE:id(2), ?MODULE:id(3)) =:= 5)
        andalso (bad_arith1(?MODULE:id(1), ?MODULE:id(infinity)) =:= 10)
        andalso (bad_arith1(?MODULE:id(infinity), ?MODULE:id(1)) =:= 10)
        andalso (bad_arith1(?MODULE:id(20), ?MODULE:id(30)) =:= 10)
        andalso (bad_arith1(?MODULE:id(2.5), ?MODULE:id(3)) =:= 5.5).

bad_arith1(T1, T2) when T1 + T2 < 10 -> T1 + T2;
bad_arith1(_, _) -> 10.

%% bad_tuple: element/2 on a non-tuple / out-of-range index fails the guard
%% quietly and clause selection proceeds (the real case's guard half; its
%% ?assertError(badarg) body half is excluded — exception-shape divergence).
c_bad_tuple(_) ->
    (bad_tuple1(?MODULE:id(a)) =:= error)
        andalso (bad_tuple1(?MODULE:id({a, b})) =:= error)
        andalso (bad_tuple1(?MODULE:id({x, b})) =:= x)
        andalso (bad_tuple1(?MODULE:id({a, b, y})) =:= y)
        andalso (bad_tuple1(?MODULE:id([])) =:= error)
        andalso (bad_tuple1(?MODULE:id({})) =:= error).

bad_tuple1(T) when element(1, T) == x -> x;
bad_tuple1(T) when element(3, T) == y -> y;
bad_tuple1(_) -> error.

%% type_tests: the suite's allowed-types matrix over the PURE rows of
%% all_types() (port row excluded — needs a live port), function_clause
%% re-expressed as fall-through to `no`.
c_type_tests(_) ->
    Small = ?MODULE:id(42),
    Big = ?MODULE:id(392742928742947293873938792874019287447829874290742),
    Flt = ?MODULE:id(3.14156),
    Nil = ?MODULE:id([]),
    Cons = ?MODULE:id([a]),
    Tup = ?MODULE:id({a, b}),
    Atom = ?MODULE:id(xxxx),
    Ref = make_ref(),
    Pid = self(),
    Fun = ?MODULE:id(fun(X) -> X end),
    Bin = ?MODULE:id(<<1, 2>>),
    Bits = ?MODULE:id(<<0:7>>),
    (tt(integer, Small) =:= yes) andalso (tt(integer, Big) =:= yes)
        andalso (tt(integer, Flt) =:= no)
        andalso (tt(float, Flt) =:= yes) andalso (tt(float, Small) =:= no)
        andalso (tt(number, Small) =:= yes) andalso (tt(number, Big) =:= yes)
        andalso (tt(number, Flt) =:= yes) andalso (tt(number, Atom) =:= no)
        andalso (tt(atom, Atom) =:= yes) andalso (tt(atom, Nil) =:= no)
        andalso (tt(list, Nil) =:= yes) andalso (tt(list, Cons) =:= yes)
        andalso (tt(list, Tup) =:= no)
        andalso (tt(nonempty_list, Cons) =:= yes)
        andalso (tt(nonempty_list, Nil) =:= no)
        andalso (tt(nil, Nil) =:= yes) andalso (tt(nil, Cons) =:= no)
        andalso (tt(tuple, Tup) =:= yes) andalso (tt(tuple, Cons) =:= no)
        andalso (tt(pid, Pid) =:= yes) andalso (tt(pid, Ref) =:= no)
        andalso (tt(reference, Ref) =:= yes) andalso (tt(reference, Pid) =:= no)
        andalso (tt(function, Fun) =:= yes) andalso (tt(function, Tup) =:= no)
        andalso (tt(binary, Bin) =:= yes) andalso (tt(binary, Bits) =:= no)
        andalso (tt(bitstring, Bin) =:= yes)
        andalso (tt(bitstring, Bits) =:= yes)
        andalso (tt(bitstring, Cons) =:= no).

tt(integer, X) when is_integer(X) -> yes;
tt(float, X) when is_float(X) -> yes;
tt(number, X) when is_number(X) -> yes;
tt(atom, X) when is_atom(X) -> yes;
tt(list, X) when is_list(X) -> yes;
tt(nonempty_list, [_ | _]) -> yes;
tt(nil, []) -> yes;
tt(tuple, X) when is_tuple(X) -> yes;
tt(pid, X) when is_pid(X) -> yes;
tt(reference, X) when is_reference(X) -> yes;
tt(function, X) when is_function(X) -> yes;
tt(binary, X) when is_binary(X) -> yes;
tt(bitstring, X) when is_bitstring(X) -> yes;
tt(_, _) -> no.

%% guard_bifs (succeeding half): each guard BIF computes the expected value in
%% guard position, on the suite's own operands (incl. abs of a 197-bit big).
c_guard_bifs(_) ->
    Big = ?MODULE:id(-237849247829874297658726487367328971246284736473821617265433),
    (gbif(abs1, Big, -Big) =:= ok)
        andalso (gbif(abs1, ?MODULE:id(-5), 5) =:= ok)
        andalso (gbif(len, ?MODULE:id([]), 0) =:= ok)
        andalso (gbif(len, ?MODULE:id([a]), 1) =:= ok)
        andalso (gbif(len, ?MODULE:id([a, b]), 2) =:= ok)
        andalso (gbif(hd1, ?MODULE:id([a]), a) =:= ok)
        andalso (gbif(hd1, ?MODULE:id([a, b]), a) =:= ok)
        andalso (gbif(tl1, ?MODULE:id([a]), []) =:= ok)
        andalso (gbif(tl1, ?MODULE:id([a, b, c]), [b, c]) =:= ok)
        andalso (gbif(size1, ?MODULE:id({}), 0) =:= ok)
        andalso (gbif(size1, ?MODULE:id({a, b, c}), 3) =:= ok)
        andalso (gbif(size1, ?MODULE:id(<<>>), 0) =:= ok)
        andalso (gbif(size1, ?MODULE:id(<<1, 2, 3>>), 3) =:= ok)
        andalso (gbif(bitsize, ?MODULE:id(<<0:7>>), 7) =:= ok)
        andalso (gbif(bitsize, ?MODULE:id(<<1, 2>>), 16) =:= ok)
        andalso (gbif(elem, ?MODULE:id({x}), {1, x}) =:= ok)
        andalso (gbif(elem, ?MODULE:id({x, y}), {2, y}) =:= ok)
        andalso (gbif(tsize, ?MODULE:id({a, b}), 2) =:= ok).

gbif(abs1, X, Y) when abs(X) == Y -> ok;
gbif(len, X, Y) when length(X) == Y -> ok;
gbif(hd1, X, Y) when hd(X) == Y -> ok;
gbif(tl1, X, Y) when tl(X) == Y -> ok;
gbif(size1, X, Y) when size(X) == Y -> ok;
gbif(bitsize, X, Y) when bit_size(X) == Y -> ok;
gbif(elem, X, {Pos, Expected}) when element(Pos, X) == Expected -> ok;
gbif(tsize, X, Y) when tuple_size(X) == Y -> ok;
gbif(_, _, _) -> fail.

%% guard_bifs (failing half): a guard BIF applied to a wrong-typed argument
%% (or yielding a non-matching value) FAILS the guard — clause falls through,
%% no exception escapes (mirrors try_fail_gbif's function_clause assertion).
c_guard_bifs_fail(_) ->
    (gbif(abs1, ?MODULE:id([]), 1) =:= fail)
        andalso (gbif(abs1, ?MODULE:id(-5), 1) =:= fail)
        andalso (gbif(len, ?MODULE:id([]), 1) =:= fail)
        andalso (gbif(len, ?MODULE:id(a), 0) =:= fail)
        andalso (gbif(len, ?MODULE:id({a}), 0) =:= fail)
        andalso (gbif(hd1, ?MODULE:id([]), 0) =:= fail)
        andalso (gbif(hd1, ?MODULE:id(x), x) =:= fail)
        andalso (gbif(tl1, ?MODULE:id([]), 0) =:= fail)
        andalso (gbif(tl1, ?MODULE:id(x), x) =:= fail)
        andalso (gbif(size1, ?MODULE:id({}), 1) =:= fail)
        andalso (gbif(size1, ?MODULE:id([]), 0) =:= fail)
        andalso (gbif(size1, ?MODULE:id([a]), 1) =:= fail)
        andalso (gbif(elem, ?MODULE:id({}), {1, x}) =:= fail)
        andalso (gbif(elem, ?MODULE:id({x}), {1, y}) =:= fail)
        andalso (gbif(elem, ?MODULE:id([]), {1, z}) =:= fail).

%% trunc/round/float guard BIFs on unambiguous operands (the suite's Float =
%% 387924.874 rows; the 6209607916799025.0 row is < 2^53 so exactly
%% representable; .5-tie rounding rows excluded).
c_trunc_round(_) ->
    F = ?MODULE:id(387924.874),
    (gbif2(trunc1, F, 387924.0) =:= ok)
        andalso (gbif2(trunc1, F, 387924) =:= ok)
        andalso (gbif2(round1, F, 387925.0) =:= ok)
        andalso (gbif2(round1, ?MODULE:id(6209607916799025.0), 6209607916799025) =:= ok)
        andalso (gbif2(float1, ?MODULE:id(2), 2.0) =:= ok)
        andalso (gbif2(trunc1, ?MODULE:id(-1.5), -1) =:= ok)
        andalso (gbif2(trunc1, F, 0.0) =:= fail)
        andalso (gbif2(trunc1, ?MODULE:id([]), 0.0) =:= fail)
        andalso (gbif2(round1, F, 1.0) =:= fail)
        andalso (gbif2(round1, ?MODULE:id([]), a) =:= fail)
        andalso (gbif2(float1, ?MODULE:id([]), 42) =:= fail).

gbif2(trunc1, X, Y) when trunc(X) == Y -> ok;
gbif2(round1, X, Y) when round(X) == Y -> ok;
gbif2(float1, X, Y) when float(X) == Y -> ok;
gbif2(_, _, _) -> fail.

%% andalso/orelse in guard position: short-circuit, non-boolean operands fail
%% the guard quietly, and the gh_6634 `is_tuple(X) andalso not ok` clause can
%% never match (JIT is_eq_exact regression, re-expressed as fall-through).
c_andalso_orelse(_) ->
    (ao1(?MODULE:id(5)) =:= yes)
        andalso (ao1(?MODULE:id(-1)) =:= no)
        andalso (ao1(?MODULE:id(a)) =:= no)
        andalso (ao2(?MODULE:id(a)) =:= yes)
        andalso (ao2(?MODULE:id(b)) =:= yes)
        andalso (ao2(?MODULE:id(c)) =:= no)
        andalso (ao3(?MODULE:id(true)) =:= yes)
        andalso (ao3(?MODULE:id(false)) =:= no)
        andalso (ao3(?MODULE:id(1)) =:= no)
        andalso (gh6634(?MODULE:id({a, b})) =:= no)
        andalso (gh6634(?MODULE:id(42)) =:= no)
        andalso (ao4(?MODULE:id([]), ?MODULE:id(0)) =:= yes)
        andalso (ao4(?MODULE:id(x), ?MODULE:id([0])) =:= yes)
        andalso (ao4(?MODULE:id(x), ?MODULE:id(5)) =:= no).

ao1(X) when is_integer(X) andalso X > 0 -> yes;
ao1(_) -> no.

ao2(X) when X =:= a orelse X =:= b -> yes;
ao2(_) -> no.

ao3(X) when X andalso true -> yes;
ao3(_) -> no.

gh6634(X) when is_tuple(X) andalso not ok -> yes;
gh6634(_) -> no.

%% orelse short-circuits before its (possibly erroring) right operand; an
%% erroring right operand fails the guard quietly.
ao4(L, N) when is_list(L) orelse hd(N) =:= 0 -> yes;
ao4(_, _) -> no.

%% Guard arithmetic/comparison on id-routed runtime operands, incl. a
%% small->big boundary crossing computed INSIDE the guard, and div-by-zero as
%% a quiet guard failure.
c_guard_arith(_) ->
    MaxSmall = ?MODULE:id((1 bsl 59) - 1),
    (ga1(?MODULE:id(7), ?MODULE:id(3)) =:= yes)
        andalso (ga1(?MODULE:id(7), ?MODULE:id(4)) =:= no)
        andalso (ga2(?MODULE:id(7), ?MODULE:id(3)) =:= yes)
        andalso (ga2(?MODULE:id(4), ?MODULE:id(5)) =:= no)
        andalso (ga3(?MODULE:id(7), ?MODULE:id(3)) =:= yes)
        andalso (ga3(?MODULE:id(7), ?MODULE:id(0)) =:= no)
        andalso (ga4(MaxSmall) =:= yes)
        andalso (ga4(?MODULE:id(0.5)) =:= yes)
        andalso (ga4(?MODULE:id(apa)) =:= no)
        andalso (ga5(?MODULE:id(7), ?MODULE:id(3)) =:= yes)
        andalso (ga5(?MODULE:id(8), ?MODULE:id(3)) =:= no).

ga1(A, B) when A + B =:= 10 -> yes;
ga1(_, _) -> no.

ga2(A, B) when A * B > 20 -> yes;
ga2(_, _) -> no.

ga3(A, B) when A div B =:= 2, A rem B =:= 1 -> yes;
ga3(_, _) -> no.

%% X + 1 > X: for MaxSmall the sum escapes into a big inside the guard.
ga4(A) when A + 1 > A -> yes;
ga4(_) -> no.

ga5(A, B) when (A band B) =:= 3, (A bor B) =:= 7, (A bsl B) =:= 56 -> yes;
ga5(_, _) -> no.

%% guard_bif_binary_part: the bptest ladder (2-tuple form, 3-arity form,
%% erlang:-qualified form) with error -> fall-through, plus the suite's
%% 2^64/-2^63 overflow probes (badarg in guard -> quiet failure) and direct
%% body-position calls on id-routed (non-folded) operands.
c_binary_part(_) ->
    (bpt(?MODULE:id(<<1, 2, 3>>)) =:= 1)
        andalso (bpt(?MODULE:id(<<2, 1, 3>>)) =:= 2)
        andalso (bpt(?MODULE:id(<<1>>)) =:= error)
        andalso (bpt(?MODULE:id(<<>>)) =:= error)
        andalso (bpt(?MODULE:id(apa)) =:= error)
        andalso (bpt(?MODULE:id(<<2, 3, 3>>)) =:= 3)
        andalso (bpt3(?MODULE:id(<<1, 2, 3>>), ?MODULE:id(1), ?MODULE:id(1)) =:= 1)
        andalso (bpt3(?MODULE:id(<<2, 1, 3>>), ?MODULE:id(1), ?MODULE:id(1)) =:= 2)
        andalso (bpt3(?MODULE:id(<<1>>), ?MODULE:id(1), ?MODULE:id(1)) =:= error)
        andalso (bpt3(?MODULE:id(apa), ?MODULE:id(1), ?MODULE:id(1)) =:= error)
        andalso (bpt3(?MODULE:id(<<2, 3, 3>>), ?MODULE:id(1), ?MODULE:id(2)) =:= 3)
        andalso (bpt_over(?MODULE:id(<<1, 2, 3>>)) =:= no)
        andalso (binary_part(?MODULE:id(<<1, 2, 3>>), 1, 1) =:= <<2>>)
        andalso (binary_part(?MODULE:id(<<2, 3, 3>>), {1, 2}) =:= <<3, 3>>).

bpt(B) when length(B) =:= 1337 -> impossible;
bpt(B) when binary_part(B, {1, 1}) =:= <<2>> -> 1;
bpt(B) when erlang:binary_part(B, 1, 1) =:= <<1>> -> 2;
bpt(B) when erlang:binary_part(B, {1, 2}) =:= <<3, 3>> -> 3;
bpt(_) -> error.

bpt3(B, A, _C) when length(B) =:= A -> impossible;
bpt3(B, A, C) when binary_part(B, {A, C}) =:= <<2>> -> 1;
bpt3(B, A, C) when erlang:binary_part(B, A, C) =:= <<1>> -> 2;
bpt3(B, A, C) when erlang:binary_part(B, {A, C}) =:= <<3, 3>> -> 3;
bpt3(_, _, _) -> error.

%% The suite's "overflow tests that need to be unoptimized": bignum pos/len
%% badarg inside the guard, never crash, never match.
bpt_over(B) when binary_part(B, {16#FFFFFFFFFFFFFFFF,
                                 -16#7FFFFFFFFFFFFFFF - 1}) =:= <<>> -> yes;
bpt_over(B) when binary_part(B, {16#FFFFFFFFFFFFFFFF,
                                 16#7FFFFFFFFFFFFFFF}) =:= <<>> -> yes;
bpt_over(_) -> no.

%% Map guard BIFs: is_map, map_size, is_map_key, map_get — errors (badmap /
%% badkey) are quiet guard failures.
c_map_guards(_) ->
    M = ?MODULE:id(#{a => 1, b => 2}),
    E = ?MODULE:id(#{}),
    (mg1(M) =:= yes) andalso (mg1(?MODULE:id({a})) =:= no)
        andalso (mg2(M) =:= yes) andalso (mg2(E) =:= no)
        andalso (mg2(?MODULE:id([])) =:= no)
        andalso (mg3(M) =:= yes) andalso (mg3(E) =:= no)
        andalso (mg3(?MODULE:id(x)) =:= no)
        andalso (mg4(M) =:= yes) andalso (mg4(E) =:= no)
        andalso (mg4(?MODULE:id(#{a => 2})) =:= no).

mg1(M) when is_map(M) -> yes;
mg1(_) -> no.

mg2(M) when map_size(M) =:= 2 -> yes;
mg2(_) -> no.

mg3(M) when is_map_key(a, M) -> yes;
mg3(_) -> no.

mg4(M) when map_get(a, M) =:= 1 -> yes;
mg4(_) -> no.

%% Cross-type term order evaluated in guard position:
%% number < atom < reference < fun < pid < tuple < map < nil < list < bitstring,
%% plus mixed-numeric == vs =:= as guards.
c_term_order(_) ->
    Ref = make_ref(),
    Pid = self(),
    Fun = ?MODULE:id(fun(X) -> X end),
    (lt(?MODULE:id(1), ?MODULE:id(a)) =:= yes)
        andalso (lt(?MODULE:id(a), ?MODULE:id(1)) =:= no)
        andalso (lt(?MODULE:id(1), ?MODULE:id(1.5)) =:= yes)
        andalso (lt(?MODULE:id(1.5), ?MODULE:id(2)) =:= yes)
        andalso (lt(?MODULE:id(a), Ref) =:= yes)
        andalso (lt(Ref, Fun) =:= yes)
        andalso (lt(Fun, Pid) =:= yes)
        andalso (lt(Pid, ?MODULE:id({})) =:= yes)
        andalso (lt(?MODULE:id({}), ?MODULE:id(#{})) =:= yes)
        andalso (lt(?MODULE:id(#{}), ?MODULE:id([])) =:= yes)
        andalso (lt(?MODULE:id([]), ?MODULE:id([a])) =:= yes)
        andalso (lt(?MODULE:id([a]), ?MODULE:id(<<1>>)) =:= yes)
        andalso (lt(?MODULE:id({z}), ?MODULE:id({a, b})) =:= yes)
        andalso (eqsoft(?MODULE:id(1), ?MODULE:id(1.0)) =:= yes)
        andalso (eqhard(?MODULE:id(1), ?MODULE:id(1.0)) =:= no)
        andalso (eqhard(?MODULE:id(1), ?MODULE:id(1)) =:= yes).

lt(A, B) when A < B -> yes;
lt(_, _) -> no.

eqsoft(A, B) when A == B -> yes;
eqsoft(_, _) -> no.

eqhard(A, B) when A =:= B -> yes;
eqhard(_, _) -> no.

%% Semicolon (or) guard sequences: an erroring alternative is skipped and the
%% other alternatives are still tried; comma sequences require every test.
c_semicolon_guards(_) ->
    (sg(?MODULE:id({a, b})) =:= yes)
        andalso (sg(?MODULE:id({a, b, c})) =:= no)
        andalso (sg(?MODULE:id({q1, q2, q3, q4, q})) =:= yes)
        andalso (sg(?MODULE:id(x)) =:= no)
        andalso (cg(?MODULE:id({a, b})) =:= yes)
        andalso (cg(?MODULE:id({a})) =:= no)
        andalso (cg(?MODULE:id([a, b])) =:= no).

sg(T) when element(5, T) =:= q; tuple_size(T) =:= 2 -> yes;
sg(_) -> no.

cg(T) when is_tuple(T), tuple_size(T) > 1 -> yes;
cg(_) -> no.
