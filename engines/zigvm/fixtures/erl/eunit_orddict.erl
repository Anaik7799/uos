%% eunit_orddict — pure-stdlib eunit EQ target (OTP30_E2_PLAN.md Task 15).
%% See eunit_lists.erl's header for the division of labor / feasibility note.
-module(eunit_orddict).
-export([]).

-include_lib("eunit/include/eunit.hrl").

store_find_test() ->
    D = orddict:store(a, 1, orddict:new()),
    {ok, 1} = orddict:find(a, D).

to_list_test() ->
    D = orddict:store(b, 2, orddict:store(a, 1, orddict:new())),
    [{a, 1}, {b, 2}] = orddict:to_list(D).

erase_test() ->
    D = orddict:erase(a, orddict:store(a, 1, orddict:new())),
    error = orddict:find(a, D).

is_key_test() ->
    D = orddict:store(a, 1, orddict:new()),
    true = orddict:is_key(a, D).
