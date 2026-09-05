%% eunit_demo — a tiny hand-written pure module + eunit tests, used as the
%% demonstration target for `--run-eunit` (E2.14). Deliberately NOT a stdlib
%% module: pulling in a real lib/stdlib/src/*.erl eunit suite is E2.15's job
%% (chasing real EQ rows on pure stdlib modules); this fixture's only purpose
%% is to prove the `--run-eunit` MODE works end-to-end against a real oracle
%% with a small, fast, fully-passing suite (three test cases, all pure
%% arithmetic, no process/spawn dependency on the test-subject side).
-module(eunit_demo).
-export([add/2, double/1]).

-include_lib("eunit/include/eunit.hrl").

add(A, B) -> A + B.
double(X) -> X * 2.

add_test() -> 3 = add(1, 2).
double_test() -> 8 = double(4).
add_negative_test() -> -1 = add(2, -3).
