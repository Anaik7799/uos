%% Curated PURE subset of erts/emulator/test/big_SUITE.erl (E7 suite closure).
%% The real suite exercises bignum arithmetic (+,-,*,div,rem,band/bor/bxor,
%% bnot,bsl/bsr), the small<->big boundary, negatives, and the multiply/square
%% optimizations, driven off large .dat equation files and multi-node rpc.
%% These cases MIRROR the same arithmetic-correctness groups (t_div, eq_big,
%% eq_math via fac/fib/gcd/lcm, borders, negative, mul/div roundtrip, rem/div
%% law, powmod, bxor_2pow/band_2pow, bnot/De Morgan, shifts, properties/
%% confused_squaring) as self-contained BOOLEAN assertions of representation-
%% independent, value-stable truths that BOTH VMs must compute bit-for-bit.
%% All magnitudes are held well under zigvm's documented <=512-bit bignum
%% ceiling (largest intermediate ~2^480). No ct/port/node/rpc/file dependency,
%% no float, no phash, no rep guards — runnable directly on the zigvm CLI.
-module(zigvm_big_SUITE).
-export([all/0, id/1, c_t_div/1, c_eq_big/1, c_eq_math/1, c_borders/1,
         c_negative/1, c_mul_div/1, c_div_rem/1, c_powmod/1, c_bitwise_2pow/1,
         c_bnot_demorgan/1, c_shift/1, c_squaring/1]).

%% bitwise-big (2026-07-23): the bitwise/shift cases route their operands
%% through the EXPORTED ?MODULE:id/1 — an external call erlc cannot inline or
%% constant-fold — so they exercise zigvm's RUNTIME two's-complement limb
%% kernels. (The pre-fix versions passed by folding alone: every literal-built
%% big was computed by the COMPILER, and the runtime bitwise family was a
%% small-only badarith deferral the folded results never touched.)
id(X) -> X.

%% c_eq_math and c_powmod RE-ADDED (triage-big-divergences, 2026-07-23): their
%% exclusion had flagged REAL zigvm divergences, now fixed — (1) mixed small/big
%% and big/big runtime `*`/`div`/`rem` were a documented badarith deferral
%% (term_algebra mul/idiv/irem "deferred to the bignum-arith slice"), discharged
%% by the mulMag/divRemMag limb kernels; (2) integer OPERANDS outside the small
%% range panicked resolve (or were silently TRUNCATED at decode when >8 bytes) —
%% the loader now materializes them as synthesized SMALL_BIG_EXT literals.
%% Both cases flip DIVERGENT->EQ. (fib kept at depth 20: naive fib(30)'s ~2.7M
%% calls stress the fuel budget, not the arithmetic under test.)

all() ->
    [c_t_div, c_eq_big, c_eq_math, c_borders, c_negative,
     c_mul_div, c_div_rem, c_powmod, c_bitwise_2pow,
     c_bnot_demorgan, c_shift, c_squaring].

%% t_div: div edge cases lifted verbatim from big_SUITE:t_div/1.
c_t_div(_) ->
    ((98765432101234 div 98765432101235) =:= 0)
        andalso ((339254531512 div 68719476736) =:= 4)
        andalso ((68719476736 * 4 + (339254531512 rem 68719476736))
                     =:= 339254531512).

%% eq_big: small-magnitude +,-,*,div,neg equations lifted verbatim from the
%% head of big_SUITE_data/eq_big.dat.
c_eq_big(_) ->
    (3627225882 =:= ((-697) + 3627226579))
        andalso (-3627227276 =:= ((-697) - 3627226579))
        andalso (-2528176925563 =:= ((-697) * 3627226579))
        andalso (697 =:= -(-697))
        andalso (0 =:= ((-697) div 3627226579)).

%% eq_math: the built-in fac/fib/gcd/lcm functions the real suite computes over,
%% asserted by exact known values plus algebraic coherence. The 26-digit fac(25)
%% constant doubles as the >8-byte-operand decode regression check.
c_eq_math(_) ->
    (fac(20) =:= 2432902008176640000)
        andalso (fac(25) =:= 15511210043330985984000000)
        andalso (fac(30) =:= (30 * fac(29)))
        andalso (fib(10) =:= 89)
        andalso (fib(20) =:= (fib(19) + fib(18)))
        andalso (gcd(1071, 462) =:= 21)
        andalso (gcd(12345678901234567890, 987654321098765432) =:= 2)
        %% lcm(A,B) * gcd(A,B) =:= A*B  (fundamental identity).
        andalso ((lcm(123456, 789012) * gcd(123456, 789012))
                     =:= (123456 * 789012)).

%% borders: exact arithmetic straddling the small/big fixnum boundary
%% (zigvm/erts MaxSmall = (1 bsl 59) - 1), mirroring borders.dat's +/- probes.
c_borders(_) ->
    B = 1 bsl 59,
    (((B - 1) + 1) =:= B)
        andalso ((B + (-1)) =:= (B - 1))
        andalso (((-B) - 1) =:= (-(B + 1)))
        andalso (((B - 1) * 2) =:= ((B * 2) - 2))
        %% product of two just-sub-boundary smalls escapes into big, exactly.
        andalso (((1 bsl 40) * (1 bsl 40)) =:= (1 bsl 80)).

%% negative: negation is an involution and distributes over multiply, across
%% the boundary into big magnitudes (mirrors negative.dat / negative/1).
c_negative(_) ->
    X = (1 bsl 200) + 999,
    ((-(-X)) =:= X)
        andalso (((-X) + X) =:= 0)
        andalso (((-X) * (-1)) =:= X)
        andalso (((-X) * X) =:= (-(X * X)))
        andalso ((X * X) > 0)
        andalso ((-X) < 0).

%% eq_big_mul_div / karatsuba: multiply two bignums then divide back is the
%% identity, and each factor divides the product with zero remainder.
c_mul_div(_) ->
    A = (1 bsl 130) + 1234567,
    Bb = (1 bsl 137) + 7654321,
    P = A * Bb,
    ((P div Bb) =:= A)
        andalso ((P div A) =:= Bb)
        andalso ((P rem A) =:= 0)
        andalso ((P rem Bb) =:= 0)
        andalso ((Bb * A) =:= P).

%% eq_big_rem: the fundamental div/rem law X =:= (X div D)*D + (X rem D) holds
%% for bignums and every sign combination (Erlang rem truncates toward zero, so
%% the remainder carries the dividend's sign) — mirrors otp_6692/eq_big_rem.
c_div_rem(_) ->
    X = (1 bsl 120) + 123456789,
    D = (1 bsl 61) + 7,
    (X =:= ((X div D) * D + (X rem D)))
        andalso ((X rem D) >= 0)
        andalso ((X rem D) < D)
        andalso (((-X) div D) =:= -(X div D))
        andalso (((-17) rem 5) =:= -2)
        andalso ((17 rem (-5)) =:= 2)
        andalso (((-17) rem (-5)) =:= -2)
        andalso ((17 div (-5)) =:= -3).

%% powmod: the suite's modular-exponentiation kernel, cross-checked against full
%% exponentiation (pow(A,E) rem M) — no hardcoded oracle constant. Exercises
%% small×big multiply, big rem big, and big rem with a no-reduction modulus.
c_powmod(_) ->
    M = (1 bsl 130) + 12345,
    (powmod(7, 150, M) =:= ((pow(7, 150)) rem M))
        andalso (powmod(7, 150, M) < M)
        andalso (powmod(7, 150, M) >= 0)
        andalso (powmod(7, 15, (1 bsl 200)) =:= pow(7, 15)).

%% bxor_2pow / band_2pow (ERL-450, ERL-804): bitwise ops on powers of two and
%% low-bit masks are exact into big magnitudes, and sign extension of negatives
%% behaves as two's-complement over an unbounded word.
c_bitwise_2pow(_) ->
    Hi = ?MODULE:id(1 bsl 200),
    Lo = ?MODULE:id(1 bsl 100),
    ((Hi bor Lo) =:= (Hi + Lo))
        andalso ((Hi band Lo) =:= 0)
        andalso ((Hi bxor Lo) =:= (Hi + Lo))
        andalso (((Hi - 1) band (Lo - 1)) =:= (Lo - 1))
        andalso (((Hi - 1) bor Lo) =:= (Hi - 1))
        andalso ((bnot 0) =:= -1)
        andalso (((-1) bxor 0) =:= -1)
        andalso (((-1) band Hi) =:= Hi)
        andalso (((-1) bor Hi) =:= -1).

%% bnot identities and De Morgan on bignums.
c_bnot_demorgan(_) ->
    X = ?MODULE:id((1 bsl 150) + 42),
    Y = ?MODULE:id((1 bsl 155) + 17),
    ((bnot X) =:= ((-X) - 1))
        andalso ((X band (bnot X)) =:= 0)
        andalso ((X bor (bnot X)) =:= -1)
        andalso ((X bxor (bnot X)) =:= -1)
        andalso ((bnot (X bor Y)) =:= ((bnot X) band (bnot Y)))
        andalso ((bnot (X band Y)) =:= ((bnot X) bor (bnot Y))).

%% shift_limit / shifts: bsl grows and bsr shrinks bignums exactly, the two are
%% mutually inverse, and shifting relates to multiply/divide by powers of two.
c_shift(_) ->
    X = ?MODULE:id((1 bsl 150) + 12345),
    (((X bsl 50) bsr 50) =:= X)
        andalso (((1 bsl 100) bsl 100) =:= (1 bsl 200))
        andalso (((1 bsl 300) bsr 100) =:= (1 bsl 200))
        andalso ((X bsl 1) =:= (X * 2))
        andalso ((X bsr 1) =:= (X div 2))
        andalso ((X bsl (-10)) =:= (X bsr 10))
        andalso ((X bsr (-10)) =:= (X bsl 10)).

%% properties / confused_squaring: squaring near the boundary is not truncated,
%% and the binomial identities hold for bignum operands (the real suite's
%% test_squaring / test_properties in equational form).
c_squaring(_) ->
    A = (1 bsl 100) + 7,
    Bb = (1 bsl 90) + 3,
    MaxSmall = (1 bsl 59) - 1,
    ((A * A) =:= (A * ((A + 1) - 1)))
        andalso (((A + Bb) * (A + Bb)) =:= (A * A + 2 * A * Bb + Bb * Bb))
        andalso (((A + Bb) * (A - Bb)) =:= (A * A - Bb * Bb))
        andalso ((MaxSmall * MaxSmall) > MaxSmall)
        andalso (((1 bsl 30) + 7) * ((1 bsl 30) + 7)
                     =:= ((1 bsl 60) + (14 bsl 30) + 49)).

%% ---- built-in helpers (mirror big_SUITE's fac/fib/gcd/lcm/pow) ----

fac(0) -> 1;
fac(N) when N > 0 -> N * fac(N - 1).

fib(0) -> 1;
fib(1) -> 1;
fib(N) when N > 1 -> fib(N - 1) + fib(N - 2).

gcd(Q, 0) -> Q;
gcd(Q, R) -> gcd(R, Q rem R).

lcm(Q, R) -> Q * R div gcd(Q, R).

pow(_, 0) -> 1;
pow(X, N) when N > 0 -> X * pow(X, N - 1).

powmod(_, 0, _) -> 1;
powmod(A, E, M) when (E band 1) =:= 1 ->
    (A * powmod(A, E - 1, M)) rem M;
powmod(A, E, M) ->
    P = powmod(A, E div 2, M),
    (P * P) rem M.
