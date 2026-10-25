%%% Initial encoding (the oracle): tagged tuples, exhaustive interpreter.
-module(severity_initial).
-behaviour(severity_algebra).
-export([none/0, at/1, worst/2, level/1, eql/2]).

none() -> none.
at(L) -> {at, L}.
worst(A, B) -> {worst, A, B}.

%% [[.]] — exhaustive: deliberately no catch-all clause.
level(none) -> ok;
level({at, L}) -> L;
level({worst, A, B}) -> severity_algebra:max_level(level(A), level(B)).

eql(A, B) -> level(A) =:= level(B).   %% observational (doctrine rule 1)
