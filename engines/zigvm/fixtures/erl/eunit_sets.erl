%% eunit_sets — pure-stdlib eunit EQ target (OTP30_E2_PLAN.md Task 15).
%% See eunit_lists.erl's header for the division of labor / feasibility note.
-module(eunit_sets).
-export([]).

-include_lib("eunit/include/eunit.hrl").

add_is_element_test() ->
    S = sets:add_element(a, sets:new()),
    true = sets:is_element(a, S).

to_list_test() ->
    S = sets:from_list([1, 2, 3]),
    [1, 2, 3] = lists:sort(sets:to_list(S)).

size_test() -> 3 = sets:size(sets:from_list([1, 2, 3])).

union_test() ->
    S = sets:union(sets:from_list([1, 2]), sets:from_list([2, 3])),
    [1, 2, 3] = lists:sort(sets:to_list(S)).

del_element_test() ->
    S = sets:del_element(a, sets:from_list([a, b])),
    false = sets:is_element(a, S).
