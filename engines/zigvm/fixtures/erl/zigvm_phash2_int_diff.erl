%% zigvm_phash2_int_diff — compiled differential for erlang:phash2/1,2 of INTEGERS
%% (DIVERGENCE 737). `phash2` is a PORTABLE, node-independent hash (used for
%% consistent hashing / ETS distribution); zigvm computed it with its OWN internal
%% `hashTerm`, so EVERY phash2 value diverged from erts (`make_hash2`). This ports the
%% erts small-integer sub-algorithm byte-EQ (SINT32_HASH for ≤28-bit, NOT_SSMALL28
%% for 28..60-bit). Non-integer terms (atoms need the erts atom-table hvalue;
%% tuples/lists/maps/binaries/floats/bignums need the full make_hash2 walk) stay on
%% the internal hash — an HONEST residual, disclosed, not claimed EQ.
%%
%% VALUE differential: phash2 of a RUNTIME int list (base-shifted via t/1's arg so
%% the compiler cannot constant-fold), both /1 and /2. Byte-EQ across the SINT32 +
%% NOT_SSMALL28 ranges incl. negatives + the 2^59-1 max-small boundary.
%%
%% Run on BOTH VMs (no stdlib needed):
%%   third_party/otp/bin/erlc -o OUT fixtures/erl/zigvm_phash2_int_diff.erl
%%   third_party/otp/bin/erl -noshell -pa OUT -eval 'zigvm_phash2_int_diff:t(0), init:stop().'
%%   zig-out/bin/zigvm run OUT/zigvm_phash2_int_diff.beam t 0
%% Byte-EQ verdict (both): {phash2_int,[846366,115015680,88723725,2614250,
%%   112602999,12354923,101464513,13893919,67006816,27520264],r2,[18,324,7064,251650]}
-module(zigvm_phash2_int_diff).
-export([t/1]).
t(N) ->
    Vs = [X + N || X <- [7, -5, 0, 1, 134217727, 134217728, 1000000000,
                         1099511627776, 288230376151711743, 576460752303423487]],
    H1 = [ erlang:phash2(V) || V <- Vs ],
    R2 = [ erlang:phash2(V, M) || {V, M} <- lists:zip([7 + N, 1000000 + N, -42 + N, 12345678 + N],
                                                       [100, 1000, 65536, 999983]) ],
    erlang:display({phash2_int, H1, r2, R2}).
