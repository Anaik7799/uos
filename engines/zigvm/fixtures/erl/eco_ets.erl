%% eco_ets — a reduced ecosystem app exercising the ETS surface zigvm genuinely
%% hosts today (gap-erlang-cover-ets, DIVERGENCE 656).
%%
%% DIVISION OF LABOR (OTP30_PARITY_PLAN.md §3): an Erlang FIXTURE, not harness
%% logic. Self-contained single module run as `zigvm run eco_ets.beam suite` — no
%% spawn, no --pa closure. Exercises the implemented `ets:` BIF envelope
%% (src/bifs/bif_table.zig: new/2, insert/2, insert_new/2, lookup/2,
%% lookup_element/3, member/2, delete/1,2, delete_object/2, update_counter/3,
%% update_element/3, info/2, first/1, next/2, last/1, prev/2, select/2,
%% match_object/2, match/2) — the key/value store a poolboy/registry-style app hits.
%%
%% HONESTY BOUND — the ORDER TRAP: a `set`'s enumeration order is erts hash-slot
%% order (representation-coupled, NOT byte-EQ). So EVERY order-exposing op
%% (first/next/last/prev/select/match_object/match) here runs on an `ordered_set`
%% (deterministic key order); a plain `set` is used ONLY for order-free ops
%% (lookup/member/size/update). This keeps the fixture STRICTLY inside the
%% observationally-EQ envelope — real EQ, never a masked repr-coupled gap.
-module(eco_ets).
-export([suite/0]).

suite() ->
    S = ets:new(s, [set]),
    %% insert + overwrite (set: last write to a key wins).
    ets:insert(S, {a, 1}), ets:insert(S, {b, 2}), ets:insert(S, {a, 9}),
    C1  = (ets:lookup(S, a) =:= [{a, 9}]),
    C2  = (ets:lookup(S, z) =:= []),
    C3  = (ets:member(S, b) =:= true) andalso (ets:member(S, z) =:= false),
    C4  = (ets:lookup_element(S, b, 2) =:= 2),
    C5  = (ets:info(S, size) =:= 2),
    %% insert_new: honors existing key.
    C6  = (ets:insert_new(S, {a, 100}) =:= false) andalso (ets:lookup(S, a) =:= [{a, 9}]),
    C7  = (ets:insert_new(S, {d, 4}) =:= true) andalso (ets:lookup(S, d) =:= [{d, 4}]),
    %% update_element / update_counter.
    C8  = (ets:update_element(S, d, {2, 44}) =:= true) andalso (ets:lookup(S, d) =:= [{d, 44}]),
    ets:insert(S, {ctr, 0}),
    C9  = (ets:update_counter(S, ctr, 5) =:= 5) andalso (ets:update_counter(S, ctr, 3) =:= 8),
    %% delete key + object.
    ets:delete(S, b),
    C10 = (ets:member(S, b) =:= false),
    ets:insert(S, {e, 7}),
    ets:delete_object(S, {e, 7}),
    C11 = (ets:member(S, e) =:= false),

    %% ordered_set: DETERMINISTIC key order for every enumeration op.
    O = ets:new(o, [ordered_set]),
    [ets:insert(O, {K, K * 10}) || K <- [3, 1, 4, 1, 5, 2]],   %% dup key 1 overwrites
    C12 = (ets:info(O, size) =:= 5),                            %% {1,2,3,4,5}
    C13 = (ets:first(O) =:= 1) andalso (ets:last(O) =:= 5),
    C14 = (ets:next(O, 1) =:= 2) andalso (ets:prev(O, 5) =:= 4),
    C15 = (ets:select(O, [{{'$1', '$2'}, [], ['$1']}]) =:= [1, 2, 3, 4, 5]),
    C16 = (ets:match_object(O, {'_', '_'}) =:= [{1, 10}, {2, 20}, {3, 30}, {4, 40}, {5, 50}]),
    C17 = (ets:match(O, {'$1', 30}) =:= [[3]]),
    C18 = (ets:select(O, [{{'$1', '$2'}, [{'>', '$1', 3}], ['$2']}]) =:= [40, 50]),

    %% info(type) reflects the table kind (deterministic).
    C19 = (ets:info(O, type) =:= ordered_set) andalso (ets:info(S, type) =:= set),

    case
        C1 andalso C2 andalso C3 andalso C4 andalso C5 andalso C6 andalso C7
        andalso C8 andalso C9 andalso C10 andalso C11 andalso C12 andalso C13
        andalso C14 andalso C15 andalso C16 andalso C17 andalso C18 andalso C19
    of
        true -> ok;
        false -> fail
    end.
