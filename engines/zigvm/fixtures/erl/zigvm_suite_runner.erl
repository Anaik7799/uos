%% zigvm_suite_runner — the conformance driver for a PURE emulator-test SUITE
%% (OTP30_E3_PLAN.md Task 19 Step 1). It calls `Suite:all()` and runs each case
%% fun with a minimal `Config` (`[]`), with NO common_test dependency (CT itself
%% is Epoch E7). It is a FIXTURE, not harness logic: the OCaml harness
%% (harness/suite_runner.ml) compiles this + the suite, then runs THIS on BOTH
%% VMs and byte-compares the per-case verdict.
%%
%% zigvm has no io protocol until Epoch E4, so the runner cannot `io:format` a
%% `CASE <name> <ok|fail>` line on zigvm — instead it encodes the verdict in its
%% RETURN VALUE (the `zigvm run` CLI prints the denoted term; the harness
%% byte-compares that against the oracle). To keep the comparison on the
%% safest printable domain (a plain integer — the E0 CLI calling convention),
%% the runner reports ONE case per invocation:
%%
%%   `case_n(Idx)` -> 1 if the Idx-th case of the pure suite passes (its
%%   `Suite:Case([])` returns the atom `true`), else 0. A case that raises
%%   (e.g. a `call_ext` `undef` for a BIF the VM lacks) is caught and reported
%%   `0` — a visible per-case divergence, never a silent skip.
%%
%%   `count(_)` -> the number of passing cases (a whole-suite summary line).
%%
%% Everything is self-contained: the runner uses its OWN `nth`/`fold`
%% recursion rather than `lists:*` (the real `lists` module is not loaded on
%% zigvm until E4's code server; only bif.tab BIFs resolve via `call_ext`).
-module(zigvm_suite_runner).

-export([case_n/1, count/1, ncases/1]).

%% The pinned pure suite this runner drives. `--run-suite pure` selects it;
%% additional pure suites would add a sibling exported entry point.
suite() -> zigvm_pure_SUITE.

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
