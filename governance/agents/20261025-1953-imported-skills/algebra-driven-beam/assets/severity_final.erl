%%% Final encoding: a severity IS its denotation (the level itself).
-module(severity_final).
-behaviour(severity_algebra).
-export([none/0, at/1, worst/2, level/1, eql/2]).

none() -> ok.
at(L) -> L.
worst(A, B) -> severity_algebra:max_level(A, B).
level(L) -> L.
eql(A, B) -> A =:= B.
