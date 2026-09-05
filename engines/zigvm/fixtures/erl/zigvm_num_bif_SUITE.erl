%% Curated PURE subset of erts/emulator/test/num_bif_SUITE.erl (E7 suite closure).
%% The real suite exercises the numeric BIFs abs/1, float/1, round/1, trunc/1,
%% floor/1, ceil/1, integer_to_list/{1,2}, list_to_integer/{1,2},
%% float_to_list/{1,2}, list_to_float/1 and their binary twins. These cases
%% MIRROR the pure algebraic groups (t_abs, t_float, t_round incl. the OTP-3722
%% boundary block, t_trunc_and_friends incl. its coherence lattice,
%% t_integer_to_string base 10 + bases 2..36) as self-contained BOOLEAN
%% assertions both VMs must compute bit-for-bit. Every operand is routed
%% through the EXPORTED ?MODULE:id/1 so erlc cannot constant-fold the
%% arithmetic — the RUNTIME BIFs are what is under test.
%%
%% EXCLUSIONS (probed empirically on the zigvm CLI, 2026-07-23):
%%   - float_to_list/float_to_binary/list_to_float (ALL float formatting):
%%     zigvm's default format is a DOCUMENTED DIVERGENCE (shortest round-trip
%%     vs BEAM's 20-digit scientific; DIVERGENCE_LOG "E2.5 float_to_list/1").
%%   - list_to_integer/binary_to_integer: NOT bif.tab rows on the pin (they
%%     are erlang.erl library wrappers) — undef from a compiled beam on zigvm;
%%     the underlying erts_internal:list_to_integer/2 primitive returns
%%     {Int,Rest} on OTP but a bare Int on zigvm (shape divergence). Excluded.
%%   - integer_to_list/integer_to_binary on BIGNUM operands: zigvm's codec is
%%     small-int-domain (documented badarith defer, bifs/conv.zig scope note),
%%     so all operands here stay within the +-(2^59-1) small range (boundary
%%     value itself included and probed EQ).
%%   - The 2000-digit bignum probes and the {'EXIT',{badarg,_}} shape asserts
%%     (zigvm E1 exception model: bare-reason catch, nil stacktraces).
-module(zigvm_num_bif_SUITE).
-export([all/0, id/1, c_abs/1, c_float/1, c_round/1, c_round_boundary/1,
         c_trunc/1, c_trunc_and_friends/1, c_int_identity/1,
         c_integer_to_string/1, c_integer_to_string_bases/1, c_float_arith/1]).

%% erlc constant-folds literal arithmetic; an external call through the
%% exported id/1 is opaque to the compiler, so the operands below reach the
%% runtime BIFs unevaluated (the zigvm_big_SUITE c_bitwise_2pow pattern).
id(X) -> X.

all() ->
    [c_abs, c_float, c_round, c_round_boundary, c_trunc,
     c_trunc_and_friends, c_int_identity, c_integer_to_string,
     c_integer_to_string_bases, c_float_arith].

%% t_abs: floats, integers, the fixnum boundary (zigvm/erts MaxSmall =
%% (1 bsl 59) - 1 — abs at/across it must escape into big exactly), and a
%% genuine 2^100 bignum. Mirrors t_abs's OTP-3190 block at OUR boundary.
c_abs(_) ->
    X = ?MODULE:id((1 bsl 59) - 1),
    Big = ?MODULE:id(1 bsl 100),
    (abs(?MODULE:id(5.5)) =:= 5.5)
        andalso (abs(?MODULE:id(0.0)) =:= +0.0)
        andalso (abs(?MODULE:id(-100.0)) =:= 100.0)
        andalso (abs(?MODULE:id(5)) =:= 5)
        andalso (abs(?MODULE:id(0)) =:= 0)
        andalso (abs(?MODULE:id(-100)) =:= 100)
        andalso (abs(X) =:= X)
        andalso ((abs(X - 1) + 1) =:= X)
        andalso ((abs(X + 1) - 1) =:= X)
        andalso (abs(-X) =:= X)
        andalso ((abs(-X - 1) - 1) =:= X)
        andalso ((abs(-X + 1) + 1) =:= X)
        andalso (abs(?MODULE:id(13984792374983749)) =:= 13984792374983749)
        andalso (abs(-Big) =:= Big)
        andalso (abs(Big) =:= Big).

%% t_float: integer -> float conversion is exact for exactly-representable
%% values, identity on floats, and covers a genuine bignum operand (2^64).
c_float(_) ->
    (float(?MODULE:id(0)) =:= +0.0)
        andalso (float(?MODULE:id(2.5)) =:= 2.5)
        andalso (float(?MODULE:id(0.0)) =:= +0.0)
        andalso (float(?MODULE:id(-100.55)) =:= -100.55)
        andalso (float(?MODULE:id(42)) =:= 42.0)
        andalso (float(?MODULE:id(-100)) =:= -100.0)
        andalso (float(?MODULE:id(4294967305)) =:= 4294967305.0)
        andalso (float(?MODULE:id(-4294967305)) =:= -4294967305.0)
        andalso (float(?MODULE:id(1 bsl 53)) =:= 9007199254740992.0)
        andalso (float(?MODULE:id(1 bsl 64)) =:= 18446744073709551616.0)
        andalso is_float(float(?MODULE:id(7))).

%% t_round: round-half-AWAY-FROM-ZERO (BEAM semantics, never banker's
%% rounding), negatives, and exactly-representable large values.
c_round(_) ->
    (round(?MODULE:id(0.0)) =:= 0)
        andalso (round(?MODULE:id(0.4)) =:= 0)
        andalso (round(?MODULE:id(0.5)) =:= 1)
        andalso (round(?MODULE:id(-0.4)) =:= 0)
        andalso (round(?MODULE:id(-0.5)) =:= -1)
        andalso (round(?MODULE:id(2.5)) =:= 3)
        andalso (round(?MODULE:id(-2.5)) =:= -3)
        andalso (round(?MODULE:id(255.3)) =:= 255)
        andalso (round(?MODULE:id(255.6)) =:= 256)
        andalso (round(?MODULE:id(-1033.3)) =:= -1033)
        andalso (round(?MODULE:id(-1033.6)) =:= -1034)
        andalso (round(?MODULE:id(4294967296.1)) =:= 4294967296)
        andalso (round(?MODULE:id(4294967296.9)) =:= 4294967297)
        andalso (-round(?MODULE:id(4294967296.9)) =:= -4294967297)
        andalso (round(?MODULE:id(6209607916799025.0)) =:= 6209607916799025)
        andalso (round(?MODULE:id(-6209607916799025.0)) =:= -6209607916799025).

%% t_round's OTP-3722 block, verbatim shape: X = (1 bsl 27) - 1 exactly
%% representable as a float; round through +-1 / +-0.1 perturbations lands on
%% the integer lattice identically, and the half-point distance is exactly 0.5.
c_round_boundary(_) ->
    X = ?MODULE:id((1 bsl 27) - 1),
    MX = -X,
    MXm1 = -X - 1,
    MXp1 = -X + 1,
    F = ?MODULE:id(X + 0.0),
    (round(F) =:= X)
        andalso ((round(F + 1) - 1) =:= X)
        andalso ((round(F - 1) + 1) =:= X)
        andalso (round(-F) =:= MX)
        andalso (round(-F - 1) =:= MXm1)
        andalso (round(-F + 1) =:= MXp1)
        andalso (round(F + 0.1) =:= X)
        andalso ((round(F + 1 + 0.1) - 1) =:= X)
        andalso ((round(F - 1 + 0.1) + 1) =:= X)
        andalso (round(F - 0.1) =:= X)
        andalso (round(-F - 0.1) =:= MX)
        andalso (round(-F + 0.1) =:= MX)
        andalso (abs(round(F + 0.5) - (F + 0.5)) =:= 0.5)
        andalso (abs(round(F - 0.5) - (F - 0.5)) =:= 0.5)
        andalso (abs(round(-F - 0.5) - (-F - 0.5)) =:= 0.5)
        andalso (abs(round(-F + 0.5) - (-F + 0.5)) =:= 0.5).

%% t_trunc_and_friends (trunc arm): truncation is TOWARD ZERO for both signs,
%% minus zero truncates to 0, and a float above 2^63 truncates into a bignum
%% exactly (trunc(float(2^64)) =:= 2^64 — float->big result path).
c_trunc(_) ->
    MinusZero = ?MODULE:id(0.0) / ?MODULE:id(-1.0),
    (trunc(MinusZero) =:= 0)
        andalso (trunc(?MODULE:id(0.0)) =:= 0)
        andalso (trunc(?MODULE:id(5.3333)) =:= 5)
        andalso (trunc(?MODULE:id(-10.978987)) =:= -10)
        andalso (trunc(?MODULE:id(1.5)) =:= 1)
        andalso (trunc(?MODULE:id(-1.5)) =:= -1)
        andalso (trunc(?MODULE:id(4294967305.7)) =:= 4294967305)
        andalso (trunc(?MODULE:id(-4294967305.7)) =:= -4294967305)
        andalso (trunc(float(?MODULE:id(1 bsl 64))) =:= (1 bsl 64))
        andalso (trunc(-float(?MODULE:id(1 bsl 64))) =:= -(1 bsl 64)).

%% t_trunc_and_friends's coherence lattice, as the helper taf/1 below: for
%% every probe float, floor =< trunc =< ceil, ceil - floor =< 1, round lands
%% on floor or ceil, trunc agrees with ceil (negative) / floor (non-negative),
%% each op is idempotent, and each survives a float round-trip of its result.
c_trunc_and_friends(_) ->
    all_taf(?MODULE:id([0.0, 5.3333, -10.978987, 0.5, -0.5, 1.5, -1.5,
                        2.5, -2.5, 255.6, -1033.6, 4294967305.7,
                        -4294967305.7]))
        andalso (floor(?MODULE:id(-1.5)) =:= -2)
        andalso (ceil(?MODULE:id(-1.5)) =:= -1)
        andalso (floor(?MODULE:id(1.5)) =:= 1)
        andalso (ceil(?MODULE:id(1.5)) =:= 2).

%% round/trunc/floor/ceil/abs are the IDENTITY on integer arguments — smalls
%% and bignums alike (the real suite asserts this via Trunc = trunc(Trunc)).
c_int_identity(_) ->
    S = ?MODULE:id(-17),
    B = ?MODULE:id(1 bsl 100),
    (round(S) =:= S) andalso (trunc(S) =:= S)
        andalso (floor(S) =:= S) andalso (ceil(S) =:= S)
        andalso (round(B) =:= B) andalso (trunc(B) =:= B)
        andalso (floor(B) =:= B) andalso (ceil(B) =:= B)
        andalso (round(-B) =:= -B) andalso (trunc(-B) =:= -B).

%% t_integer_to_string, base-10 arm: exact digit strings for both signs, up to
%% and INCLUDING the small/big boundary value (1 bsl 59) - 1 (all operands
%% stay in the small range — the documented zigvm codec domain).
c_integer_to_string(_) ->
    (integer_to_list(?MODULE:id(0)) =:= "0")
        andalso (integer_to_list(?MODULE:id(42)) =:= "42")
        andalso (integer_to_list(?MODULE:id(-42)) =:= "-42")
        andalso (integer_to_list(?MODULE:id(32768)) =:= "32768")
        andalso (integer_to_list(?MODULE:id(268435455)) =:= "268435455")
        andalso (integer_to_list(?MODULE:id(-268435455)) =:= "-268435455")
        andalso (integer_to_list(?MODULE:id(8589934592)) =:= "8589934592")
        andalso (integer_to_list(?MODULE:id(-8589934592)) =:= "-8589934592")
        andalso (integer_to_list(?MODULE:id((1 bsl 59) - 1))
                     =:= "576460752303423487")
        andalso (integer_to_list(?MODULE:id(-((1 bsl 59) - 1)))
                     =:= "-576460752303423487").

%% t_integer_to_string, base-2..36 arm: the exact base-N digit strings the
%% real suite pins (base 2 and 16 verbatim), plus the base-36 alphabet edges.
c_integer_to_string_bases(_) ->
    (integer_to_list(?MODULE:id(0), 2) =:= "0")
        andalso (integer_to_list(?MODULE:id(1), 2) =:= "1")
        andalso (integer_to_list(?MODULE:id(54), 2) =:= "110110")
        andalso (integer_to_list(?MODULE:id(-64), 2) =:= "-1000000")
        andalso (integer_to_list(?MODULE:id(0), 16) =:= "0")
        andalso (integer_to_list(?MODULE:id(10), 16) =:= "A")
        andalso (integer_to_list(?MODULE:id(54462), 16) =:= "D4BE")
        andalso (integer_to_list(?MODULE:id(-54462), 16) =:= "-D4BE")
        andalso (integer_to_list(?MODULE:id(1099511627775), 16)
                     =:= "FFFFFFFFFF")
        andalso (integer_to_list(?MODULE:id(35), 36) =:= "Z")
        andalso (integer_to_list(?MODULE:id(36), 36) =:= "10")
        andalso (integer_to_list(?MODULE:id(255), 8) =:= "377").

%% Float ARITHMETIC identities (never formatting): exact IEEE-754 results for
%% dyadically-representable operands, `/` always yields a float, int/float
%% arithmetic equality (==) vs exact inequality (=:=), and the one inexact
%% classic (0.1 + 0.2) pinned to its exact double value on both VMs.
c_float_arith(_) ->
    ((?MODULE:id(0.5) + ?MODULE:id(0.25)) =:= 0.75)
        andalso ((?MODULE:id(2.5) * ?MODULE:id(4.0)) =:= 10.0)
        andalso ((?MODULE:id(7.0) - ?MODULE:id(2.5)) =:= 4.5)
        andalso ((?MODULE:id(1.0) / ?MODULE:id(4.0)) =:= 0.25)
        andalso ((?MODULE:id(1) / ?MODULE:id(2)) =:= 0.5)
        andalso ((?MODULE:id(0.1) + ?MODULE:id(0.2))
                     =:= 0.30000000000000004)
        andalso (?MODULE:id(2.0) == ?MODULE:id(2))
        andalso (not (?MODULE:id(2.0) =:= ?MODULE:id(2)))
        andalso (float(?MODULE:id(2)) == ?MODULE:id(2))
        andalso (abs(?MODULE:id(-2.5)) =:= 2.5).

%% ---- helpers (mirror t_trunc_and_friends's trunc_and_friends/1) ----

all_taf([]) -> true;
all_taf([F | T]) -> taf(F) andalso all_taf(T).

taf(F) ->
    Trunc = trunc(F),
    Floor = floor(F),
    Ceil = ceil(F),
    Round = round(F),
    (Trunc =:= trunc(Trunc))
        andalso (Floor =:= floor(Floor))
        andalso (Ceil =:= ceil(Ceil))
        andalso (Round =:= round(Round))
        andalso (Trunc =:= trunc(float(Trunc)))
        andalso (Floor =:= floor(float(Floor)))
        andalso (Ceil =:= ceil(float(Ceil)))
        andalso (Round =:= round(float(Round)))
        andalso (Floor =< Trunc) andalso (Trunc =< Ceil)
        andalso ((Ceil - Floor) =< 1)
        andalso ((Round =:= Floor) orelse (Round =:= Ceil))
        andalso (if F < 0 -> Trunc =:= Ceil; true -> Trunc =:= Floor end).
