%% eco_fixture — the in-tree machinery proof for `--run-ecosystem` (E18 Task 6).
%%
%% DIVISION OF LABOR (OTP30_PARITY_PLAN.md §3, DIVERGENCE 199/202): this is an
%% Erlang FIXTURE, not harness logic. The real E12 ecosystem apps (cowboy,
%% poolboy, meck, gleam-stdlib) are large multi-module suites whose test
%% drivers (`make eunit`, `rebar3 eunit`, `gleam test`) require process spawn +
%% the stdlib dependency closure that zigvm cannot yet host end-to-end
%% (DIVERGENCE 97) — and whose sources are not vendored in-tree. Those apps
%% therefore record honest UNTESTED-with-reason rows, never mocked `ok`.
%%
%% This fixture exists so the DRIVER MACHINERY itself (compile -> oracle run ->
%% zigvm run -> byte-compare -> ledger verdict) is proven on a suite that is
%% genuinely inside the E0 CLI surface (`zigvm run <one .beam> <fn>`, no spawn,
%% no cross-module `lists:`/`maps:` calls — those dispatch `undef` on zigvm
%% today, DIVERGENCE 97). Every check is written as SELF-CONTAINED local
%% recursion, exactly like corpus_seed.erl, so it compiles to only the op/BIF
%% envelope the VM implements. Both the oracle (`io:format("~w",
%% [eco_fixture:suite()])`) and zigvm (`zigvm run eco_fixture.beam suite`) run
%% this SAME entry point; the harness byte-compares their printed result. An EQ
%% row here proves the `ecosystem` kind's evidence path is real, not vacuous.
-module(eco_fixture).
-export([suite/0]).

%% Local sum over a proper list (no lists:sum/1 — that would dispatch undef).
sum([]) -> 0;
sum([H | T]) -> H + sum(T).

%% Local length (no length/1 BIF dependency in the result path).
len([]) -> 0;
len([_ | T]) -> 1 + len(T).

%% Local reverse via an accumulator.
rev(L) -> rev(L, []).
rev([], Acc) -> Acc;
rev([H | T], Acc) -> rev(T, [H | Acc]).

%% Local element-equality for two proper lists.
eq([], []) -> true;
eq([H | A], [H | B]) -> eq(A, B);
eq(_, _) -> false.

%% Run a handful of pure library-style checks (the shape an ecosystem app's
%% unit suite asserts) and collapse to `ok` iff every check holds, else `fail`.
suite() ->
    C1 = (sum([1, 2, 3, 4, 5]) =:= 15),
    C2 = eq(rev([1, 2, 3]), [3, 2, 1]),
    C3 = (len([1, 2, 3, 4]) =:= 4),
    C4 = (sum(rev([10, 20, 30])) =:= 60),
    case C1 andalso C2 andalso C3 andalso C4 of
        true -> ok;
        false -> fail
    end.
