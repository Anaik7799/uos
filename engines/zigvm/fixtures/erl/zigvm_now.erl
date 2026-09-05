%% gap-justified-bif-sweep (DIVERGENCE 653): erlang:now/0 runs truthfully on zigvm
%% (was undef — `.justified`/unreachable). The SHAPE + validity are byte-EQ vs OTP-30
%% (a {Mega,Sec,Micro} erts-split timestamp, ranges valid, recent epoch); the exact
%% VALUE is host time (not byte-EQ) — the disclosed residual keeping the row justified.
-module(zigvm_now).
-export([t/0]).
t() ->
    {Mega, Sec, Micro} = erlang:now(),
    {shape, is_integer(Mega) andalso is_integer(Sec) andalso is_integer(Micro),
     ranges, Sec >= 0 andalso Sec < 1000000 andalso Micro >= 0 andalso Micro < 1000000,
     recent, (Mega * 1000000 + Sec) > 1700000000}.
