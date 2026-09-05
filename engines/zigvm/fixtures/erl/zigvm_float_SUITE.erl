%% Curated PURE subset of erts/emulator/test/float_SUITE.erl (E7 suite closure).
%% The real suite exercises float arithmetic consistency (arith), FP-exception
%% delivery (fpe, hidden_inf), the negative-zero sign bit (negative_zero),
%% denormal round-trips (denormalized), float clause matching (match), the
%% NaN-rejecting 64-bit float unpack (bad_float_unpack), and the float<->integer
%% comparison lattice (cmp_zero/cmp_integer/cmp_bignum) — plus driver/port and
%% io_lib formatting cases. These cases MIRROR the pure algebraic groups as
%% self-contained BOOLEAN assertions both VMs must compute bit-for-bit: exact
%% IEEE-754 arithmetic on dyadically-representable operands, negation/abs,
%% the ==-vs-=:= number lattice across smalls/bignums/floats, trunc/round/float
%% conversions, badarith via try (both /0.0 and hidden-infinity overflow),
%% float clause match + function_clause fallthrough, the <<-1:64>> float-match
%% rejection, the -0.0 sign bit observed through 64-bit float construction,
%% 64-bit float bit-syntax round-trips, denormals (built at RUNTIME by
%% division, round-tripped through bit syntax — never term_to_binary), and the
%% strict-IEEE mul-add chain of t_mul_add_ops pinned to exact doubles.
%% Every operand is routed through the EXPORTED ?MODULE:id/1 — an external
%% call erlc cannot inline or constant-fold — so the RUNTIME arithmetic,
%% comparison and bit-syntax kernels are exercised (the zigvm_big_SUITE
%% c_bitwise_2pow pattern).
%%
%% EXCLUSIONS (per the documented divergences + CT dependence):
%%   - write/1, the cmp/2 io_lib:format diagnostics, list_to_float (otp_7178):
%%     ALL float formatting/parsing (DIVERGENCE "E2.5 float_to_list/1").
%%   - fpe's math:log probes (math module), fp_drv/fp_drv_thread (driver,
%%     port, peer node), denormalized's term_to_binary round-trip (replaced
%%     with a bit-syntax round-trip of runtime-built denormals).
%%   - The {'EXIT',{Reason,_Stack}} catch-wrap shapes: zigvm's E1 exception
%%     model lands bare reasons — all exception cases here use try with class
%%     discrimination (error:badarith / error:function_clause), which IS EQ.
-module(zigvm_float_SUITE).
-export([all/0, id/1,
         c_arith_exact/1, c_negation_abs/1, c_cmp_zero/1, c_cmp_integer/1,
         c_cmp_bignum/1, c_conversions/1, c_div_zero/1, c_hidden_inf/1,
         c_float_match/1, c_bad_float_unpack/1, c_negative_zero/1,
         c_bs_roundtrip/1, c_denormalized/1, c_mul_add/1]).

all() ->
    [c_arith_exact, c_negation_abs, c_cmp_zero, c_cmp_integer,
     c_cmp_bignum, c_conversions, c_div_zero, c_hidden_inf,
     c_float_match, c_bad_float_unpack, c_negative_zero,
     c_bs_roundtrip, c_denormalized, c_mul_add].

%% External-call identity: operands routed through here reach the VM as
%% runtime values, never as compile-time constants.
id(X) -> X.

%% arith/1 (pure arm): +,-,*,/ are EXACT on dyadically-representable operands,
%% for float/float and the mixed int/float instructions alike; int/int `/`
%% yields a float; and the one classic inexact sum (0.1 + 0.2) is pinned to
%% its exact double value on both VMs.
c_arith_exact(_) ->
    ((?MODULE:id(0.5) + ?MODULE:id(0.25)) =:= 0.75)
        andalso ((?MODULE:id(7.0) - ?MODULE:id(2.5)) =:= 4.5)
        andalso ((?MODULE:id(2.5) * ?MODULE:id(4.0)) =:= 10.0)
        andalso ((?MODULE:id(3.0) / ?MODULE:id(4.0)) =:= 0.75)
        andalso ((?MODULE:id(17) + ?MODULE:id(0.25)) =:= 17.25)
        andalso ((?MODULE:id(2) * ?MODULE:id(1.5)) =:= 3.0)
        andalso ((?MODULE:id(7.0) - ?MODULE:id(2)) =:= 5.0)
        andalso ((?MODULE:id(3.0) / ?MODULE:id(4)) =:= 0.75)
        andalso ((?MODULE:id(1) / ?MODULE:id(8)) =:= 0.125)
        andalso ((?MODULE:id(0.1) + ?MODULE:id(0.2)) =:= 0.30000000000000004).

%% arith/1 (negation arm): unary minus and abs on runtime floats — involution,
%% sign stripping, and exactness through a dyadic subtraction.
c_negation_abs(_) ->
    ((-?MODULE:id(3.5)) =:= -3.5)
        andalso ((-(-?MODULE:id(2.25))) =:= 2.25)
        andalso (abs(?MODULE:id(-7.5)) =:= 7.5)
        andalso (abs(?MODULE:id(7.5)) =:= 7.5)
        andalso (abs(?MODULE:id(-0.125)) =:= 0.125)
        andalso ((-(?MODULE:id(0.5) - ?MODULE:id(0.25))) =:= -0.25).

%% cmp_zero/1: the smallest denormal (0.5e-323) against integer 0 — strictly
%% greater, never less, never arithmetically equal, from both sides.
c_cmp_zero(_) ->
    D = ?MODULE:id(0.5e-323),
    Z = ?MODULE:id(0),
    (D > Z) andalso (not (D < Z))
        andalso (Z < D) andalso (not (Z > D))
        andalso (not (D == Z)) andalso (not (Z == D)).

%% cmp_integer/1: the 2^53 imprecision axis — Axis = (1 bsl 53) - 2.0 is the
%% suite's own probe point; ints beyond it order correctly against the float,
%% Axis*Axis dominates round(Axis); plus the ==-vs-=:= distinction (2 == 2.0
%% but never exactly equal) and small int/float orderings.
c_cmp_integer(_) ->
    Axis = ?MODULE:id(1 bsl 53) - ?MODULE:id(2.0),
    R = round(Axis),
    (Axis =:= 9007199254740990.0)
        andalso ((R + 2) > Axis) andalso (Axis < (R + 2))
        andalso (not ((R + 2) < Axis)) andalso (not ((R + 2) == Axis))
        andalso ((Axis * Axis) > R) andalso (R < (Axis * Axis))
        andalso (R == Axis)
        andalso (?MODULE:id(2.0) == ?MODULE:id(2))
        andalso (?MODULE:id(2) == ?MODULE:id(2.0))
        andalso (not (?MODULE:id(2.0) =:= ?MODULE:id(2)))
        andalso (?MODULE:id(2.0) =/= ?MODULE:id(2))
        andalso (?MODULE:id(3) > ?MODULE:id(2.5))
        andalso (?MODULE:id(2.5) < ?MODULE:id(3))
        andalso (?MODULE:id(2) < ?MODULE:id(2.5)).

%% cmp_bignum/1 (bounded): every power of two through 2^200 is ==-equal to its
%% float image with both signs (the suite's 1 bsl N == (1 bsl N)*1.0 walk);
%% bignum-vs-float orderings both ways around the 64/100/200-bit marks.
c_cmp_bignum(_) ->
    pow2_eq(?MODULE:id(200))
        andalso (((?MODULE:id(1) bsl 64) - 1) < ((?MODULE:id(1) bsl 64) * 1.0))
        andalso (((?MODULE:id(1) bsl 64) * 1.0) > ((?MODULE:id(1) bsl 64) - 1))
        andalso (((?MODULE:id(1) bsl 100) * 1.0) > (?MODULE:id(1) bsl 99))
        andalso ((?MODULE:id(1) bsl 200) > ((?MODULE:id(1) bsl 100) * 1.0))
        andalso (((?MODULE:id(1) bsl 100) * 1.0) < (?MODULE:id(1) bsl 200)).

pow2_eq(N) when N < 0 -> true;
pow2_eq(N) ->
    P = ?MODULE:id(1) bsl N,
    (P == P * 1.0) andalso (P * 1.0 == P)
        andalso ((P * -1) == (P * -1.0))
        andalso pow2_eq(N - 8).

%% t_float/t_round/t_trunc in float_SUITE's own register: int->float is exact
%% for representable values (incl. 2^53), trunc is toward zero, round is
%% half-away-from-zero, the 2^53-2 axis round-trips onto its own integer, and
%% trunc of a big float lands in the bignum domain exactly.
c_conversions(_) ->
    (float(?MODULE:id(5)) =:= 5.0)
        andalso (float(?MODULE:id(-5)) =:= -5.0)
        andalso (float(?MODULE:id(1 bsl 53)) =:= 9007199254740992.0)
        andalso (trunc(?MODULE:id(2.75)) =:= 2)
        andalso (trunc(?MODULE:id(-2.75)) =:= -2)
        andalso (round(?MODULE:id(2.5)) =:= 3)
        andalso (round(?MODULE:id(-2.5)) =:= -3)
        andalso (round(?MODULE:id(9007199254740990.0)) =:= 9007199254740990)
        andalso (trunc(float(?MODULE:id(1 bsl 64))) =:= (1 bsl 64))
        andalso is_float(float(?MODULE:id(7)))
        andalso is_integer(trunc(?MODULE:id(7.5))).

%% fpe/1 (pure arm): division by zero raises badarith — float/float, int/float,
%% float/int, 0.0/0.0, and division by MINUS zero — observed through try with
%% class discrimination; a legal division afterwards still computes exactly.
c_div_zero(_) ->
    ba(fun() -> ?MODULE:id(5.0) / ?MODULE:id(0.0) end)
        andalso ba(fun() -> ?MODULE:id(5) / ?MODULE:id(0.0) end)
        andalso ba(fun() -> ?MODULE:id(5.0) / ?MODULE:id(0) end)
        andalso ba(fun() -> ?MODULE:id(0.0) / ?MODULE:id(0.0) end)
        andalso ba(fun() -> ?MODULE:id(1.0) / (?MODULE:id(-1.0) * ?MODULE:id(0.0)) end)
        andalso ((?MODULE:id(5.0) / ?MODULE:id(2.0)) =:= 2.5).

%% badarith observer: the guarded computation must RAISE error:badarith; any
%% value produced instead is a failure.
ba(F) -> try F() of _ -> false catch error:badarith -> true end.

%% hidden_inf/1 (bounded): operations whose intermediate result is infinite
%% must not hide the badarith — overflowing *, +, unary-negated -, and the
%% B/(inf) / B*(inf) compositions; while a HUGE value that does NOT overflow
%% absorbs 1.0 exactly.
c_hidden_inf(_) ->
    Huge = ?MODULE:id(9.23e307),
    B = ?MODULE:id(1.0),
    ba(fun() -> ?MODULE:id(3.23e133) * ?MODULE:id(3.57e257) end)
        andalso ba(fun() -> Huge + Huge end)
        andalso ba(fun() -> Huge * Huge end)
        andalso ba(fun() -> -Huge - Huge end)
        andalso ba(fun() -> B / (Huge * Huge) end)
        andalso ba(fun() -> B * (Huge + Huge) end)
        andalso ba(fun() -> B / (?MODULE:id(1.0) / ?MODULE:id(0.0)) end)
        andalso ((Huge + B) =:= Huge).

%% match/1: float literal clause matching selects the right clause for runtime
%% arguments, and a non-matching float raises function_clause (class-and-reason
%% via try — never the catch-wrap shape).
c_float_match(_) ->
    (match_1(?MODULE:id(1.0)) =:= one)
        andalso (match_1(?MODULE:id(2.0)) =:= two)
        andalso (match_1(?MODULE:id(1000.0)) =:= a_lot)
        andalso (try match_1(?MODULE:id(0.5)) of
                     _ -> false
                 catch
                     error:function_clause -> true
                 end).

match_1(1.0) -> one;
match_1(2.0) -> two;
match_1(1000.0) -> a_lot.

%% bad_float_unpack/1: <<-1:64>> is an all-ones bit pattern (a NaN as a float)
%% — the 64-bit float match clause must REJECT it and fall through to the
%% signed-integer clause, yielding -1; a genuine float payload takes the float
%% clause. The -1 is id-routed so the RUNTIME construction path performs the
%% two's-complement truncation (and no compile-time truncation warning fires).
c_bad_float_unpack(_) ->
    (bad_float_unpack_match(?MODULE:id(<<(?MODULE:id(-1)):64>>)) =:= -1)
        andalso (bad_float_unpack_match(?MODULE:id(<<1.5:64/float>>)) =:= 1.5).

bad_float_unpack_match(<<F:64/float>>) -> F;
bad_float_unpack_match(<<I:64/integer-signed>>) -> I.

%% negative_zero/1: the sign bit survives negation and multiplication into the
%% constructed 64-bit image — '-'(0.0), -1 * 0.0 and -1.0 * 0.0 all produce
%% exactly <<16#8000000000000000:64>>, while +0.0 is all-zero bits; and -0.0
%% is arithmetically equal to 0.0 yet not exactly equal (OTP-27+ semantics).
c_negative_zero(_) ->
    Z = ?MODULE:id(0.0),
    NegZ = -Z,
    (<<NegZ/float>> =:= <<16#8000000000000000:64>>)
        andalso (<<(?MODULE:id(-1.0) * Z)/float>> =:= <<16#8000000000000000:64>>)
        andalso (<<(?MODULE:id(-1) * Z)/float>> =:= <<16#8000000000000000:64>>)
        andalso (<<Z/float>> =:= <<0:64>>)
        andalso (NegZ == Z)
        andalso (not (NegZ =:= Z)).

%% 64-bit float bit-syntax round-trip: construct-then-match is the identity on
%% runtime floats (dyadic and non-dyadic alike), the constructed image is
%% byte-stable, and a known IEEE-754 image (16#3ff8...) decodes to exactly 1.5.
c_bs_roundtrip(_) ->
    rt(?MODULE:id(1.5)) andalso rt(?MODULE:id(-2.25))
        andalso rt(?MODULE:id(0.1)) andalso rt(?MODULE:id(1.0e10))
        andalso rt(?MODULE:id(123456.789))
        andalso rt(?MODULE:id(0.30000000000000004))
        andalso begin
                    <<F:64/float>> = ?MODULE:id(<<16#3ff8000000000000:64>>),
                    F =:= 1.5
                end.

rt(V) ->
    <<F:64/float>> = ?MODULE:id(<<V:64/float>>),
    (F =:= V) andalso (<<F/float>> =:= <<V:64/float>>).

%% denormalized/1 (bit-syntax register): denormals built at RUNTIME by division
%% round-trip exactly through 64-bit float construction/matching, order
%% correctly against zero and a normal float, and negate exactly.
c_denormalized(_) ->
    D = ?MODULE:id(1.0e-307) / ?MODULE:id(1000.0),
    NegD = ?MODULE:id(-1.0e-307) / ?MODULE:id(1000.0),
    <<RD:64/float>> = ?MODULE:id(<<D:64/float>>),
    <<RN:64/float>> = ?MODULE:id(<<NegD:64/float>>),
    (RD =:= D) andalso (RN =:= NegD)
        andalso (D > 0.0) andalso (NegD < 0.0)
        andalso (D =:= -NegD)
        andalso (D < 1.0e-300).

%% t_mul_add_ops/1: the strict-IEEE (never fused) R*A+B chain under is_float
%% guards — the 2.0/1.0 ladder is exactly 2^N - 1, the dyadic 0.5/0.25 chain
%% is exact, and the non-dyadic 2.03/1.3 chain is pinned to the exact double
%% the oracle computes (no epsilon).
c_mul_add(_) ->
    (op_mul_add(?MODULE:id(1), 2.0, 1.0, 0.0) =:= 1.0)
        andalso (op_mul_add(?MODULE:id(4), 2.0, 1.0, 0.0) =:= 15.0)
        andalso (op_mul_add(?MODULE:id(6), 2.0, 1.0, 0.0) =:= 63.0)
        andalso (op_mul_add(?MODULE:id(3), 0.5, 0.25, 0.0) =:= 0.4375)
        andalso (op_mul_add(?MODULE:id(6), 2.03, 1.3, 0.0)
                     =:= 87.06260151458997).

op_mul_add(0, _, _, R) -> R;
op_mul_add(N, A, B, R) when is_float(A), is_float(B), is_float(R) ->
    op_mul_add(N - 1, A, B, R * A + B).
