-module(mylists).
-export([sum/1, len/1, rev/1, seq/1]).

sum([]) -> 0;
sum([H|T]) -> H + sum(T).

len([]) -> 0;
len([_|T]) -> 1 + len(T).

rev(L) -> rev(L, []).
rev([], Acc) -> Acc;
rev([H|T], Acc) -> rev(T, [H|Acc]).

seq(0) -> [];
seq(N) -> [N | seq(N - 1)].
