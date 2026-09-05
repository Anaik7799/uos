%% eunit_proplists — pure-stdlib eunit EQ target (OTP30_E2_PLAN.md Task 15).
%% See eunit_lists.erl's header for the division of labor / feasibility note.
-module(eunit_proplists).
-export([]).

-include_lib("eunit/include/eunit.hrl").

get_value_test() -> 1 = proplists:get_value(a, [{a, 1}, {b, 2}]).
get_value_default_test() -> none = proplists:get_value(c, [{a, 1}], none).
delete_test() -> [{b, 2}] = proplists:delete(a, [{a, 1}, {b, 2}]).
lookup_test() -> {a, 1} = proplists:lookup(a, [{a, 1}, {b, 2}]).
is_defined_test() -> true = proplists:is_defined(a, [{a, 1}]).
