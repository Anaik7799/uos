%% eco_lists_maps — a reduced ecosystem app exercising the stdlib DATA surface
%% that zigvm genuinely hosts today (e21-t3, DIVERGENCE 230/420-amend).
%%
%% DIVISION OF LABOR (OTP30_PARITY_PLAN.md §3, DIVERGENCE 199/202): this is an
%% Erlang FIXTURE, not harness logic. Like eco_fixture, it is a SELF-CONTAINED
%% single module run as `zigvm run <one .beam> suite` — no spawn, no --pa
%% dependency closure. Unlike eco_fixture (which stays inside the local-op/BIF
%% envelope with zero cross-module calls), this fixture deliberately exercises
%% the CROSS-MODULE `lists:`/`maps:` library calls that resolve to zigvm's
%% implemented BIF envelope (`src/bifs/bif_table.zig`: lists:reverse/2,
%% member/2, keyfind/3, keymember/3, keysearch/3; maps:from_list/1, from_keys/2,
%% get/2, find/2, is_key/2, put/3, update/3, remove/2, take/2, merge/2,
%% values/1, keys/1). This is the pure data-transformation surface a gleam-stdlib
%% style suite asserts — genuinely runnable and byte-EQ vs pinned OTP-30.
%%
%% HONESTY BOUND: only the functions above are zigvm BIFs. Library helpers like
%% lists:sort/1, lists:sum/1, lists:map/2, lists:foldl/3 are NOT BIFs — they
%% dispatch `undef` on the single-beam surface (they need the stdlib beam loaded
%% via --pa + the E7 closure, DIVERGENCE 97). This fixture stays STRICTLY inside
%% the implemented BIF envelope so its EQ is real, never a masked gap.
-module(eco_lists_maps).
-export([suite/0]).

suite() ->
    %% lists: the implemented BIF envelope.
    C1  = (lists:reverse([1, 2, 3], []) =:= [3, 2, 1]),
    C2  = (lists:member(2, [1, 2, 3]) =:= true),
    C3  = (lists:member(9, [1, 2, 3]) =:= false),
    C4  = (lists:keyfind(b, 1, [{a, 1}, {b, 2}]) =:= {b, 2}),
    C5  = (lists:keyfind(z, 1, [{a, 1}, {b, 2}]) =:= false),
    C6  = (lists:keymember(a, 1, [{a, 1}, {b, 2}]) =:= true),
    C7  = (lists:keysearch(b, 1, [{a, 1}, {b, 2}]) =:= {value, {b, 2}}),
    %% maps: the implemented BIF envelope.
    M   = maps:from_list([{a, 1}, {b, 2}, {c, 3}]),
    C8  = (maps:get(a, M) =:= 1),
    C9  = (maps:find(z, M) =:= error),
    C10 = (maps:is_key(b, M) =:= true),
    C11 = (maps:is_key(z, M) =:= false),
    M2  = maps:put(d, 4, M),
    C12 = (maps:get(d, M2) =:= 4),
    M3  = maps:update(a, 10, M2),
    C13 = (maps:get(a, M3) =:= 10),
    {TV, M4} = maps:take(b, M3),
    C14 = (TV =:= 2) andalso (maps:is_key(b, M4) =:= false),
    M5  = maps:remove(c, M4),
    C15 = (maps:is_key(c, M5) =:= false),
    Mm  = maps:merge(maps:from_list([{x, 1}]), maps:from_list([{y, 2}])),
    C16 = (maps:get(x, Mm) =:= 1) andalso (maps:get(y, Mm) =:= 2),
    Mk  = maps:from_keys([p, q, r], 0),
    C17 = (maps:get(p, Mk) =:= 0) andalso (maps:get(r, Mk) =:= 0),
    C18 = (maps:values(maps:from_list([{a, 1}, {b, 2}])) =:= [1, 2]),
    C19 = (maps:keys(maps:from_list([{a, 1}, {b, 2}])) =:= [a, b]),
    case
        C1 andalso C2 andalso C3 andalso C4 andalso C5 andalso C6 andalso C7
        andalso C8 andalso C9 andalso C10 andalso C11 andalso C12 andalso C13
        andalso C14 andalso C15 andalso C16 andalso C17 andalso C18 andalso C19
    of
        true -> ok;
        false -> fail
    end.
