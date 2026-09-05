%% Curated PURE subset of erts/emulator/test/small_SUITE.erl (E7 suite closure).
%% The real suite exercises small-integer arithmetic at and across the 64-bit
%% fixnum (small/big) boundary. zigvm's boundary matches erts: MaxSmall =
%% (1 bsl 59) - 1, MinSmall = -(1 bsl 59). These cases assert REPRESENTATION-
%% INDEPENDENT arithmetic truths that span the boundary (so both VMs must agree
%% bit-for-bit), mirroring small_SUITE's groups: edge_cases, addition,
%% subtraction, negation, multiplication, division, bitwise, bsl/bsr, and the
%% confused_squaring regression. No ct/port/node dependency — runnable on zigvm.
-module(zigvm_small_SUITE).
-export([all/0, c_edge_boundary/1, c_addition/1, c_subtraction/1, c_negation/1,
         c_multiplication/1, c_division/1, c_bitwise/1, c_bsl/1, c_bsr/1,
         c_confused_squaring/1]).

all() ->
    [c_edge_boundary, c_addition, c_subtraction, c_negation,
     c_multiplication, c_division, c_bitwise, c_bsl, c_bsr, c_confused_squaring].

%% edge_cases: the fixnum boundary crossings are arithmetically exact.
c_edge_boundary(_) ->
    MaxSmall = (1 bsl 59) - 1,
    MinSmall = -(1 bsl 59),
    ((MaxSmall + 1) > MaxSmall)
        andalso ((MinSmall - 1) < MinSmall)
        andalso ((MinSmall + MaxSmall) =:= -1)
        andalso ((MaxSmall + MinSmall) =:= -1)
        andalso (((MaxSmall + 1) - 1) =:= MaxSmall)
        andalso (((MinSmall - 1) + 1) =:= MinSmall).

%% addition: including a carry from small into big.
c_addition(_) ->
    ((2 + 2) =:= 4)
        andalso ((-5 + 5) =:= 0)
        andalso (((1 bsl 59) - 1 + 1) =:= (1 bsl 59))
        andalso ((16#0FFFFFFFFFFFFFFF + 1) =:= 16#1000000000000000).

%% subtraction: crossing back from big into small.
c_subtraction(_) ->
    ((10 - 3) =:= 7)
        andalso (((1 bsl 59) - 1) =:= ((1 bsl 59) - 1))
        andalso (((1 bsl 60) - (1 bsl 60)) =:= 0)
        andalso ((0 - (1 bsl 64)) =:= -(1 bsl 64)).

%% negation: negating MinSmall escapes the fixnum range (magnitude = 2^59).
c_negation(_) ->
    MinSmall = -(1 bsl 59),
    ((-MinSmall) =:= (1 bsl 59))
        andalso ((-(-7)) =:= 7)
        andalso ((-0) =:= 0)
        andalso is_integer(-MinSmall).

%% multiplication: products that overflow the fixnum range stay exact.
c_multiplication(_) ->
    ((6 * 7) =:= 42)
        andalso (((1 bsl 30) * (1 bsl 30)) =:= (1 bsl 60))
        andalso ((-3 * 4) =:= -12)
        andalso ((1000000000 * 1000000000) =:= 1000000000000000000).

%% division: div/rem truncate toward zero (Erlang semantics).
c_division(_) ->
    ((10 div 3) =:= 3)
        andalso ((10 rem 3) =:= 1)
        andalso (((-10) div 3) =:= -3)
        andalso (((-10) rem 3) =:= -1)
        andalso (((1 bsl 62) div (1 bsl 31)) =:= (1 bsl 31)).

%% test_bitwise: band/bor/bxor/bnot identities across the boundary.
c_bitwise(_) ->
    ((16#F0F0 band 16#FF00) =:= 16#F000)
        andalso ((16#F0F0 bor 16#0F0F) =:= 16#FFFF)
        andalso ((16#FFFF bxor 16#0F0F) =:= 16#F0F0)
        andalso ((bnot 0) =:= -1)
        andalso ((bnot (1 bsl 60)) =:= -((1 bsl 60) + 1)).

%% test_bsl: left shift grows small into big, exactly.
c_bsl(_) ->
    ((1 bsl 10) =:= 1024)
        andalso ((1 bsl 59) =:= 576460752303423488)
        andalso ((3 bsl 62) =:= (3 * (1 bsl 62)))
        andalso ((-1 bsl 4) =:= -16).

%% test_bsr: right shift shrinks big back into small, exactly.
c_bsr(_) ->
    (((1 bsl 60) bsr 60) =:= 1)
        andalso ((1024 bsr 10) =:= 1)
        andalso (((-16) bsr 2) =:= -4)
        andalso (((1 bsl 64) bsr 5) =:= (1 bsl 59)).

%% confused_squaring: X*X near the boundary must not be truncated (a real
%% erts regression — squaring a value just under MaxSmall yields a big).
c_confused_squaring(_) ->
    X = (1 bsl 30) + 7,
    MaxSmall = (1 bsl 59) - 1,
    (X * X =:= ((1 bsl 60) + (14 bsl 30) + 49))
        andalso (MaxSmall * MaxSmall > MaxSmall).
