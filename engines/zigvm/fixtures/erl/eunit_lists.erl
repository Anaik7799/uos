%% eunit_lists — pure-stdlib eunit EQ target (OTP30_E2_PLAN.md Task 15).
%%
%% Small hand-written eunit suite exercising `lists` module functions whose
%% underlying semantics are covered by zigvm's BIF families (E2.4-E2.12) and
%% the term/list algebra laws. This module is a FIXTURE (real Erlang, really
%% run by real `eunit` on the oracle), not harness logic — see
%% harness/eunit.ml's header for the division of labor and the FEASIBILITY
%% note explaining why every case is expected to record UNTESTED on zigvm at
%% E2 (no process spawn, no cross-module dispatch — see task-15-e2-report.md).
-module(eunit_lists).
-export([]).

-include_lib("eunit/include/eunit.hrl").

map_test() -> [2, 4, 6] = lists:map(fun(X) -> X * 2 end, [1, 2, 3]).
filter_test() -> [2, 4] = lists:filter(fun(X) -> X rem 2 =:= 0 end, [1, 2, 3, 4]).
foldl_test() -> 10 = lists:foldl(fun(X, Acc) -> X + Acc end, 0, [1, 2, 3, 4]).
reverse_test() -> [3, 2, 1] = lists:reverse([1, 2, 3]).
sort_test() -> [1, 2, 3] = lists:sort([3, 1, 2]).
sum_test() -> 6 = lists:sum([1, 2, 3]).
member_test() -> true = lists:member(2, [1, 2, 3]).
flatten_test() -> [1, 2, 3] = lists:flatten([[1, 2], [3]]).
