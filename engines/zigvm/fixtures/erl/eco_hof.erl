%% eco_hof — a reduced ecosystem app exercising the HIGHER-ORDER `lists:`/`maps:`
%% functions zigvm now hosts via the preloaded stock stdlib (gap-hof-stdlib,
%% DIVERGENCE 661).
%%
%% DIVISION OF LABOR (OTP30_PARITY_PLAN.md §3): an Erlang FIXTURE, not harness
%% logic. Run as `zigvm run eco_hof.beam suite` — the `run` CLI subcommand now
%% preloads the HOF-bearing stock stdlib (real OTP-30 `lists`/`maps`), so the
%% fun-taking functions (map/filter/foldl/foldr/all/any/foreach, maps:map/fold/
%% filter) — which are Erlang code in OTP, NOT BIFs, and were `undef` on zigvm
%% before this slice — resolve to the real implementation.
%%
%% This is the END-TO-END differential proving the CLI wiring (the in-process
%% LAW gap-hof-stdlib in src/cli.zig proves runMulti(preload_stdlib=true); THIS
%% fixture proves `zigvm run` actually SETS the flag). Every assertion compares
%% pure data (int lists, maps) — no repr-coupling, so the EQ is real.
-module(eco_hof).
-export([suite/0]).

suite() ->
    %% higher-order lists (fun-taking, Erlang code in OTP)
    C1  = (lists:map(fun(X) -> X * X end, [1, 2, 3, 4]) =:= [1, 4, 9, 16]),
    C2  = (lists:filter(fun(X) -> X rem 2 =:= 0 end, [1, 2, 3, 4, 5, 6]) =:= [2, 4, 6]),
    C3  = (lists:foldl(fun(X, A) -> X + A end, 0, [1, 2, 3, 4, 5]) =:= 15),
    C4  = (lists:foldr(fun(X, A) -> [X | A] end, [], [1, 2, 3]) =:= [1, 2, 3]),
    C5  = (lists:all(fun(X) -> X > 0 end, [1, 2, 3]))
              andalso (not lists:all(fun(X) -> X > 0 end, [1, -2, 3])),
    C6  = (lists:any(fun(X) -> X < 0 end, [1, -2, 3]))
              andalso (not lists:any(fun(X) -> X < 0 end, [1, 2, 3])),
    C7  = (lists:foreach(fun(_X) -> ok end, [1, 2, 3]) =:= ok),

    %% higher-order maps
    C8  = (maps:map(fun(_K, V) -> V * 10 end, #{a => 1, b => 2}) =:= #{a => 10, b => 20}),
    C9  = (maps:fold(fun(_K, V, A) -> V + A end, 0, #{a => 1, b => 2, c => 3}) =:= 6),
    C10 = (maps:filter(fun(_K, V) -> V > 1 end, #{a => 1, b => 2, c => 3}) =:= #{b => 2, c => 3}),

    %% native lists BIFs (member/reverse) STILL win alongside the loaded module
    C11 = (lists:reverse([1, 2, 3]) =:= [3, 2, 1]) andalso lists:member(2, [1, 2, 3]),

    %% composition through the stock stdlib: sort (Erlang) then map (Erlang)
    C12 = (lists:map(fun(X) -> X + 1 end, lists:sort([3, 1, 2])) =:= [2, 3, 4]),

    %% mapfoldl: threads an accumulator AND builds a list (a stricter HOF)
    C13 = (lists:mapfoldl(fun(X, A) -> {X * 2, A + X} end, 0, [1, 2, 3]) =:= {[2, 4, 6], 6}),

    case
        C1 andalso C2 andalso C3 andalso C4 andalso C5 andalso C6 andalso C7
        andalso C8 andalso C9 andalso C10 andalso C11 andalso C12 andalso C13
    of
        true -> ok;
        false -> fail
    end.
