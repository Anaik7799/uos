%% eunit_maps — pure-stdlib eunit EQ target (OTP30_E2_PLAN.md Task 15).
%% See eunit_lists.erl's header for the division of labor / feasibility note.
-module(eunit_maps).
-export([]).

-include_lib("eunit/include/eunit.hrl").

put_get_test() ->
    M = maps:put(a, 1, #{}),
    1 = maps:get(a, M).

remove_test() ->
    M = maps:remove(a, #{a => 1, b => 2}),
    false = maps:is_key(a, M).

size_test() -> 2 = maps:size(#{a => 1, b => 2}).

to_list_test() -> [{a, 1}] = maps:to_list(#{a => 1}).

from_list_test() -> #{a := 1, b := 2} = maps:from_list([{a, 1}, {b, 2}]).

merge_test() -> #{a := 1, b := 2} = maps:merge(#{a => 1}, #{b => 2}).
