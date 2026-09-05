%% eunit_ordsets — pure-stdlib eunit EQ target (OTP30_E2_PLAN.md Task 15).
%% See eunit_lists.erl's header for the division of labor / feasibility note.
-module(eunit_ordsets).
-export([]).

-include_lib("eunit/include/eunit.hrl").

add_is_element_test() ->
    S = ordsets:add_element(a, ordsets:new()),
    true = ordsets:is_element(a, S).

to_list_test() -> [1, 2, 3] = ordsets:to_list(ordsets:from_list([3, 1, 2])).

union_test() ->
    S = ordsets:union(ordsets:from_list([1, 2]), ordsets:from_list([2, 3])),
    [1, 2, 3] = ordsets:to_list(S).

intersection_test() ->
    S = ordsets:intersection(ordsets:from_list([1, 2, 3]), ordsets:from_list([2, 3, 4])),
    [2, 3] = ordsets:to_list(S).

del_element_test() ->
    S = ordsets:del_element(a, ordsets:from_list([a, b])),
    false = ordsets:is_element(a, S).
