%% zigvm_bitsyntax_diff — bit-syntax integer-field DECODE differential
%% (bs-int-128-topbit, DIVERGENCE 592). Decoding an UNSIGNED 128-bit field with
%% the top bit set (>= 2^127) used to PANIC (@intCast u128->i128). Now byte-EQ
%% vs OTP. Uses band/bsr to read the value (avoids >128-bit integer literals,
%% which zigvm's loader/bit-syntax mis-handle — a SEPARATE known bug). Run:
%%   erl -run zigvm_bitsyntax_diff g  vs  zigvm run f.beam g
-module(zigvm_bitsyntax_diff).
-export([g/0]).
chk(Tag, Bin, N) ->
    <<X:N>> = Bin,
    erlang:display({Tag, X band 255, X bsr (N-8), <<X:N>> =:= Bin}).
g() ->
    chk(w128_lo, <<0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,42>>, 128),          %% top bit 0
    chk(w128_topbit, <<255,0,0,0,0,0,0,0,0,0,0,0,0,0,0,7>>, 128),     %% top bit 1 (was PANIC)
    chk(w128_max, <<255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255>>, 128),
    chk(w136_topbit, <<255,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16>>, 136),
    chk(w256_topbit, <<255,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,99>>, 256),
    halt(0).
