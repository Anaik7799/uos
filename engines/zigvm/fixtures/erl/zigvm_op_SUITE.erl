%% Curated PURE subset of erts/emulator/test/op_SUITE.erl (E7 suite closure).
%% The real suite exercises operator semantics — bsl/bsr (incl. negative shift
%% counts), the strict boolean operators and/or/xor/not, and the relational
%% operators ==//=/=:=/=/=/</=</>/>= over every type pair (relop_simple's
%% coherence identities, relop/complex_relop's literal matrices, typed/combined
%% relops) — via generated modules, erl_eval, random terms, and catch'd EXITs.
%% These cases MIRROR the same operator-semantics groups as self-contained
%% BOOLEAN assertions of representation-independent truths both VMs must agree
%% on bit-for-bit: boolean truth tables, andalso/orelse short-circuit,
%% cross-type term order (number < atom < tuple < map < nil < list < binary),
%% the relop coherence laws (antisymmetry, trichotomy, =:= implies ==, =< as
%% < orelse ==) over a pairwise term matrix, arith vs exact equality on mixed
%% int/float structures, structural tuple/list/binary ordering, bignum
%% comparisons, mixed int/float arithmetic (values, never formatting), unary
%% minus, div/rem sign rules, and bsl/bsr with negative shifts. All operands
%% route through the EXPORTED ?MODULE:id/1 so erlc cannot constant-fold — the
%% RUNTIME comparison/arith kernels are what is exercised. No ct/port/node/
%% catch/float-formatting/phash dependency — runnable on the zigvm CLI.
-module(zigvm_op_SUITE).
-export([all/0, id/1, c_logical/1, c_t_not/1, c_shortcircuit/1,
         c_relop_types/1, c_relop_simple/1, c_eq_exact/1,
         c_relop_structured/1, c_relop_bignum/1, c_arith_mixed/1,
         c_unary_ops/1, c_div_rem_sign/1, c_bsl_bsr/1]).

%% Exported identity: an external call erlc cannot inline or constant-fold, so
%% every operand below reaches the operator as a RUNTIME value (the
%% zigvm_big_SUITE c_bitwise_2pow pattern).
id(X) -> X.

all() ->
    [c_logical, c_t_not, c_shortcircuit, c_relop_types, c_relop_simple,
     c_eq_exact, c_relop_structured, c_relop_bignum, c_arith_mixed,
     c_unary_ops, c_div_rem_sign, c_bsl_bsr].

%% logical: the full and/or/xor truth tables on runtime booleans (mirrors
%% logical/1's Op x {true,false} matrix; the 'bad' badarg rows are excluded —
%% error shapes are out of scope for the pure subset).
c_logical(_) ->
    T = ?MODULE:id(true),
    F = ?MODULE:id(false),
    ((T and T) =:= true) andalso ((T and F) =:= false)
        andalso ((F and T) =:= false) andalso ((F and F) =:= false)
        andalso ((T or T) =:= true) andalso ((T or F) =:= true)
        andalso ((F or T) =:= true) andalso ((F or F) =:= false)
        andalso ((T xor T) =:= false) andalso ((T xor F) =:= true)
        andalso ((F xor T) =:= true) andalso ((F xor F) =:= false).

%% t_not: not on runtime booleans, involution, and De Morgan over and/or.
c_t_not(_) ->
    T = ?MODULE:id(true),
    F = ?MODULE:id(false),
    ((not T) =:= false) andalso ((not F) =:= true)
        andalso ((not (not T)) =:= T) andalso ((not (not F)) =:= F)
        andalso ((not (T and F)) =:= ((not T) or (not F)))
        andalso ((not (T or F)) =:= ((not T) and (not F))).

%% andalso/orelse short-circuit: the right operand is NOT evaluated when the
%% left decides — (1 div 0) would raise badarith if it ever ran.
c_shortcircuit(_) ->
    T = ?MODULE:id(true),
    F = ?MODULE:id(false),
    Z = ?MODULE:id(0),
    ((F andalso ((1 div Z) > 0)) =:= false)
        andalso ((T orelse ((1 div Z) > 0)) =:= true)
        andalso ((T andalso F) =:= false)
        andalso ((F orelse T) =:= true)
        andalso ((T andalso T) =:= true)
        andalso ((F orelse F) =:= false).

%% relop across TYPES: the total term order
%% number < atom < tuple < map < nil < list < binary (mirrors relop/
%% complex_relop's cross-type rows).
c_relop_types(_) ->
    Int = ?MODULE:id(42),
    Flt = ?MODULE:id(1.5),
    Atom = ?MODULE:id(zzz),
    Tup = ?MODULE:id({1, 2}),
    Map = ?MODULE:id(#{a => 1}),
    Nil = ?MODULE:id([]),
    Lst = ?MODULE:id([1]),
    Bin = ?MODULE:id(<<1, 2, 3>>),
    (Int < Atom) andalso (Flt < Atom)
        andalso (Atom < Tup) andalso (Tup < Map)
        andalso (Map < Nil) andalso (Nil < Lst) andalso (Lst < Bin)
        andalso (Int < Tup) andalso (Int < Bin) andalso (Atom < Bin)
        andalso (Bin > Int) andalso (Nil > Map) andalso (Atom > Flt)
        andalso (Int =< Atom) andalso (Bin >= Lst)
        andalso (not (Atom < Int)) andalso (not (Bin < Map)).

%% relop_simple: the coherence identities of relop_simple_do/1 — antisymmetry
%% (X < Y iff not X >= Y iff Y > X), =< as (< orelse ==), trichotomy (exactly
%% one of <, ==, > holds), symmetry of ==/=:=, and =:= implies == — checked
%% over EVERY ordered pair of a mixed-type term matrix (smalls, bignums,
%% floats, atoms, tuple, list, binary).
c_relop_simple(_) ->
    Terms = [?MODULE:id(-33), ?MODULE:id(-33.0), ?MODULE:id(0),
             ?MODULE:id(42), ?MODULE:id(42.0),
             ?MODULE:id(1 bsl 70), ?MODULE:id(-(1 bsl 70)),
             ?MODULE:id(a), ?MODULE:id(b),
             ?MODULE:id({3, 4}), ?MODULE:id([5]), ?MODULE:id(<<6>>)],
    all_pairs(Terms, Terms).

%% eq vs exact-eq: == compares arithmetically across int/float (deeply, inside
%% tuples and lists), =:= does not; X /= Y is not (X == Y); X =/= Y is
%% not (X =:= Y).
c_eq_exact(_) ->
    A = ?MODULE:id(42),
    B = ?MODULE:id(42.0),
    (A == B) andalso (not (A =:= B))
        andalso (A =/= B) andalso (not (A /= B))
        andalso (?MODULE:id(1.0) == ?MODULE:id(1))
        andalso (?MODULE:id({1, 2.0}) == ?MODULE:id({1.0, 2}))
        andalso (not (?MODULE:id({1, 2.0}) =:= ?MODULE:id({1.0, 2})))
        andalso (?MODULE:id([1, 2.0]) == ?MODULE:id([1.0, 2]))
        andalso (not (?MODULE:id([1, 2.0]) =:= ?MODULE:id([1.0, 2])))
        andalso (?MODULE:id(atom) =:= ?MODULE:id(atom))
        andalso (?MODULE:id(<<1, 2>>) =:= ?MODULE:id(<<1, 2>>))
        andalso (?MODULE:id({a, 1}) =:= ?MODULE:id({a, 1})).

%% complex_relop (structural): tuples order by size first then element-wise;
%% lists element-wise with a proper prefix smaller; binaries byte-wise with a
%% proper prefix smaller.
c_relop_structured(_) ->
    (?MODULE:id({1, 2}) < ?MODULE:id({1, 2, 3}))
        andalso (?MODULE:id({9, 9}) < ?MODULE:id({1, 1, 1}))
        andalso (?MODULE:id({1, 2}) < ?MODULE:id({1, 3}))
        andalso (?MODULE:id({1, 2}) < ?MODULE:id({2, 1}))
        andalso (?MODULE:id([1, 2]) < ?MODULE:id([1, 3]))
        andalso (?MODULE:id([1, 2]) < ?MODULE:id([1, 2, 3]))
        andalso (?MODULE:id([1, 2, 3]) < ?MODULE:id([2]))
        andalso (?MODULE:id(<<1, 2>>) < ?MODULE:id(<<1, 3>>))
        andalso (?MODULE:id(<<1, 2>>) < ?MODULE:id(<<1, 2, 0>>))
        andalso (?MODULE:id(<<9>>) < ?MODULE:id(<<10>>))
        andalso (?MODULE:id({1, a}) < ?MODULE:id({1, b})).

%% relop on bignums: the relop_simple Big1/Big2 constants, id-routed so the
%% RUNTIME bignum compare kernel (not the compiler) does the work; spans the
%% small/big boundary and both signs.
c_relop_bignum(_) ->
    Big1 = ?MODULE:id(19738924729729787487784874),
    Big2 = ?MODULE:id(38374938373887374983978484),
    MaxSmall = ?MODULE:id((1 bsl 59) - 1),
    (Big1 < Big2) andalso (Big2 > Big1)
        andalso ((-Big1) > (-Big2))
        andalso (Big1 =:= Big1) andalso (Big1 == Big1)
        andalso (MaxSmall < Big1) andalso ((-Big1) < (-MaxSmall))
        andalso ((-Big1) < MaxSmall) andalso (Big2 > 0)
        andalso ((Big1 + 1) > Big1) andalso (not (Big1 < Big1))
        andalso ((Big2 - Big1) > 0).

%% arithmetic with mixed int/float operands: contagion to float, and / is
%% always float division (values only — float FORMATTING is out of scope).
c_arith_mixed(_) ->
    I = ?MODULE:id(7),
    F = ?MODULE:id(2.0),
    ((I + F) =:= 9.0) andalso is_float(I + F)
        andalso ((I - F) =:= 5.0)
        andalso ((I * F) =:= 14.0)
        andalso ((I / F) =:= 3.5)
        andalso ((?MODULE:id(4) / ?MODULE:id(2)) =:= 2.0)
        andalso is_float(?MODULE:id(4) / ?MODULE:id(2))
        andalso ((F + F) =:= 4.0)
        andalso ((?MODULE:id(0.5) + ?MODULE:id(0.25)) =:= 0.75)
        andalso ((?MODULE:id(1) + ?MODULE:id(2)) =:= 3)
        andalso is_integer(?MODULE:id(1) + ?MODULE:id(2)).

%% unary minus: involution, agreement with binary subtraction, on smalls,
%% floats, and bignums (the runtime negate kernel).
c_unary_ops(_) ->
    X = ?MODULE:id(5),
    Fl = ?MODULE:id(2.5),
    B = ?MODULE:id(1 bsl 200),
    ((-X) =:= (0 - X)) andalso ((-(-X)) =:= X)
        andalso ((-Fl) =:= (0.0 - Fl)) andalso ((-(-Fl)) =:= Fl)
        andalso ((-B) < 0) andalso ((-(-B)) =:= B)
        andalso ((-B) =:= (0 - B))
        andalso ((-?MODULE:id(0)) =:= 0)
        andalso ((bnot X) =:= ((-X) - 1)).

%% div/rem sign rules: truncation toward zero, remainder carries the
%% dividend's sign, and the fundamental law X = (X div D)*D + (X rem D) for
%% every sign combination (id-routed so the runtime kernels run).
c_div_rem_sign(_) ->
    P = ?MODULE:id(7),
    N = ?MODULE:id(-7),
    D = ?MODULE:id(2),
    Dn = ?MODULE:id(-2),
    ((P div D) =:= 3) andalso ((P rem D) =:= 1)
        andalso ((N div D) =:= -3) andalso ((N rem D) =:= -1)
        andalso ((P div Dn) =:= -3) andalso ((P rem Dn) =:= 1)
        andalso ((N div Dn) =:= 3) andalso ((N rem Dn) =:= -1)
        andalso (P =:= ((P div Dn) * Dn + (P rem Dn)))
        andalso (N =:= ((N div D) * D + (N rem D))).

%% bsl_bsr: shifts with runtime operands — growth into big, NEGATIVE shift
%% counts reverse direction (X bsl -N =:= X bsr N), and bsr on negatives is
%% arithmetic (floor) shift (mirrors bsl_bsr/1's RawValues probes).
c_bsl_bsr(_) ->
    X = ?MODULE:id(16#8000000),
    ((?MODULE:id(1) bsl ?MODULE:id(10)) =:= 1024)
        andalso ((?MODULE:id(1) bsl ?MODULE:id(73)) =:= 9444732965739290427392)
        andalso ((X bsl ?MODULE:id(7)) =:= (X * 128))
        andalso ((?MODULE:id(-2) bsl ?MODULE:id(73)) =:= (-(1 bsl 74)))
        andalso ((X bsl ?MODULE:id(-2)) =:= (X bsr 2))
        andalso ((X bsr ?MODULE:id(-3)) =:= (X bsl 3))
        andalso ((?MODULE:id(-1) bsr ?MODULE:id(100)) =:= -1)
        andalso ((?MODULE:id(-16) bsr ?MODULE:id(2)) =:= -4)
        andalso ((?MODULE:id(-7) bsr ?MODULE:id(1)) =:= -4)
        andalso (((?MODULE:id(1) bsl ?MODULE:id(64)) bsr ?MODULE:id(5)) =:= (1 bsl 59)).

%% ---- helpers (mirror relop_simple_do/1's identity block) ----

%% Coherence of the eight relational operators on one ordered pair.
relop_ok(V1, V2) ->
    L = V1 < V2,
    G = V1 > V2,
    Eq = V1 == V2,
    Id = V1 =:= V2,
    (L =:= (not (V1 >= V2)))
        andalso (L =:= (V2 > V1))
        andalso (L =:= (not (V2 =< V1)))
        andalso (G =:= (not (V1 =< V2)))
        andalso (G =:= (V2 < V1))
        andalso ((V1 =< V2) =:= (L orelse Eq))
        andalso ((V1 >= V2) =:= (G orelse Eq))
        andalso (Eq =:= (V2 == V1))
        andalso (Id =:= (V2 =:= V1))
        andalso (Eq =:= (not (V1 /= V2)))
        andalso (Id =:= (not (V1 =/= V2)))
        andalso ((not Id) orelse Eq)
        andalso trichotomy(L, Eq, G).

trichotomy(true, false, false) -> true;
trichotomy(false, true, false) -> true;
trichotomy(false, false, true) -> true;
trichotomy(_, _, _) -> false.

all_pairs(_Vs, []) -> true;
all_pairs(Vs, [V | T]) -> pairs1(V, Vs) andalso all_pairs(Vs, T).

pairs1(_V, []) -> true;
pairs1(V, [W | T]) -> relop_ok(V, W) andalso pairs1(V, T).
