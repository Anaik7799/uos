%% eco_random — a reduced ecosystem app exercising the `rand` PRNG and the
%% `math` module. rand is Erlang code (undef before this slice, DIVERGENCE 671);
%% math is ALREADY fully native (every math fn is a BIF) so its preload is a
%% completeness no-op.
%%
%% Run as `zigvm run eco_random.beam suite`. HONESTY BOUNDS: rand is exercised
%% ONLY through EXPLICITLY-SEEDED state (rand:seed_s + the _s/2 variants) — a
%% seeded sequence is deterministic and byte-EQ (the exsss algorithm matches the
%% oracle); the unseeded rand:uniform/0 (host entropy) is NEVER asserted, and the
%% rand STATE term (embeds funs) is NEVER compared — only the drawn VALUES.
-module(eco_random).
-export([suite/0]).

seq(S, N) -> seq(S, N, []).
seq(_S, 0, Acc) -> lists:reverse(Acc);
seq(S, N, Acc) -> {V, S2} = rand:uniform_s(1000, S), seq(S2, N - 1, [V | Acc]).

suite() ->
    %% rand — deterministic seeded draws (values only, never the state).
    S0 = rand:seed_s(exsss, {1, 2, 3}),
    {V1, S1} = rand:uniform_s(S0),
    C1  = (is_float(V1)) andalso (V1 >= 0.0) andalso (V1 < 1.0),
    {V2, _} = rand:uniform_s(S1),
    C2  = (is_float(V2)) andalso (V2 >= 0.0) andalso (V2 < 1.0) andalso (V1 =/= V2),
    C3  = (element(1, rand:uniform_s(1000, rand:seed_s(exsss, {42, 42, 42}))) =:= 484),
    C4  = (seq(rand:seed_s(exsss, {100, 200, 300}), 5) =:= seq(rand:seed_s(exsss, {100, 200, 300}), 5)),
    Seq = seq(rand:seed_s(exsss, {5, 5, 5}), 4),
    C5  = (length(Seq) =:= 4) andalso lists:all(fun(X) -> is_integer(X) andalso X >= 1 andalso X =< 1000 end, Seq),
    C6  = (element(1, rand:uniform_s(6, rand:seed_s(exsss, {7, 7, 7}))) >= 1),
    C7  = (byte_size(element(1, rand:bytes_s(8, rand:seed_s(exsss, {9, 9, 9})))) =:= 8),
    %% same seed -> same bytes (determinism)
    C8  = (element(1, rand:bytes_s(8, rand:seed_s(exsss, {9, 9, 9}))) =:= element(1, rand:bytes_s(8, rand:seed_s(exsss, {9, 9, 9})))),

    %% math — native BIFs (exact where the IEEE result is exact; trunc otherwise).
    C9  = (math:sqrt(144.0) =:= 12.0),
    C10 = (math:pow(2.0, 10.0) =:= 1024.0),
    C11 = (math:floor(3.7) =:= 3.0) andalso (math:ceil(3.2) =:= 4.0),
    C12 = (trunc(math:pi() * 1000000) =:= 3141592),
    C13 = (round(math:log(math:exp(1.0))) =:= 1),
    C14 = (math:log2(8.0) =:= 3.0) andalso (math:log10(1000.0) =:= 3.0),

    case
        C1 andalso C2 andalso C3 andalso C4 andalso C5 andalso C6 andalso C7
        andalso C8 andalso C9 andalso C10 andalso C11 andalso C12 andalso C13
        andalso C14
    of
        true -> ok;
        false -> fail
    end.
