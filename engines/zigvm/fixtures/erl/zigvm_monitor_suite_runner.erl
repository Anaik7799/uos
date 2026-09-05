-module(zigvm_monitor_suite_runner).
-export([case_n/1, count/1, ncases/1]).
suite() -> zigvm_monitor_SUITE.
case_n(Idx) -> S = suite(), C = nth(Idx, S:all()), try S:C([]) of true -> 1; _ -> 0 catch _:_ -> 0 end.
count(_) -> S = suite(), fold_ok(S, S:all(), 0).
ncases(_) -> S = suite(), len(S:all(), 0).
fold_ok(_S, [], Acc) -> Acc;
fold_ok(S, [C | T], Acc) -> Acc1 = try S:C([]) of true -> Acc + 1; _ -> Acc catch _:_ -> Acc end, fold_ok(S, T, Acc1).
nth(1, [X | _]) -> X;
nth(N, [_ | T]) when N > 1 -> nth(N - 1, T).
len([], Acc) -> Acc;
len([_ | T], Acc) -> len(T, Acc + 1).
