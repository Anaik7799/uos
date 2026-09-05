%% eunit_string — pure-stdlib eunit EQ target (OTP30_E2_PLAN.md Task 15).
%% Only the PURE subset of `string` (no I/O, no locale/OS dependence).
%% See eunit_lists.erl's header for the division of labor / feasibility note.
-module(eunit_string).
-export([]).

-include_lib("eunit/include/eunit.hrl").

uppercase_test() -> "ABC" = string:uppercase("abc").
lowercase_test() -> "abc" = string:lowercase("ABC").
trim_test() -> "abc" = string:trim("  abc  ").
concat_test() -> "ab" = string:concat("a", "b").
length_test() -> 3 = string:length("abc").
split_test() -> ["a", "b"] = string:split("a,b", ",").
