%% zigvm_e4_suite_runner — the conformance driver for zigvm_e4_SUITE (the
%% E4-reachable pure SUITE). IDENTICAL in shape to zigvm_suite_runner (which
%% drives zigvm_pure_SUITE); the ONLY difference is `suite/0` — this is the
%% "sibling exported entry point" the pure runner's header anticipated for
%% additional pure suites. It is a FIXTURE, not harness logic: the OCaml
%% harness (harness/suite_runner.ml) compiles this + the suite, runs THIS on
%% BOTH VMs, and byte-compares the per-case verdict.
%%
%% As with zigvm_suite_runner, the verdict is encoded in the RETURN VALUE (a
%% plain integer 1|0 — the E0 CLI calling convention), one case per
%% invocation, so the comparison stays on the safest printable domain. The
%% runner uses its OWN nth/len recursion rather than lists:* (the real lists
%% module is not loaded on zigvm).
-module(zigvm_e4_suite_runner).

-export([case_n/1, count/1, ncases/1]).

suite() -> zigvm_e4_SUITE.

%% case_n(Idx) -> 1 | 0  (the per-case verdict, 1-based index).
case_n(Idx) ->
    S = suite(),
    C = nth(Idx, S:all()),
    try S:C([]) of
        true -> 1;
        _ -> 0
    catch
        _:_ -> 0
    end.

%% count(_) -> number of passing cases (whole-suite summary).
count(_) ->
    S = suite(),
    fold_ok(S, S:all(), 0).

%% ncases(_) -> the suite's declared case count (a totality cross-check).
ncases(_) ->
    S = suite(),
    len(S:all(), 0).

fold_ok(_S, [], Acc) -> Acc;
fold_ok(S, [C | T], Acc) ->
    Acc1 =
        try S:C([]) of
            true -> Acc + 1;
            _ -> Acc
        catch
            _:_ -> Acc
        end,
    fold_ok(S, T, Acc1).

nth(1, [X | _]) -> X;
nth(N, [_ | T]) when N > 1 -> nth(N - 1, T).

len([], Acc) -> Acc;
len([_ | T], Acc) -> len(T, Acc + 1).
