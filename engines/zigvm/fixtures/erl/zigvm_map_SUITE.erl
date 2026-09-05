%% Curated PURE subset of erts/emulator/test/map_SUITE.erl (E7 suite closure).
%% The real suite exercises the maps data type end to end: build/match, the
%% map BIFs (put/get/find/is_key/remove/take/update/keys/values/merge/from_list),
%% and >32-element HAMT maps (t_*_large, t_hashmap_balance). These cases mirror
%% that algebraic surface with REPRESENTATION-INDEPENDENT, VALUE-STABLE truths
%% that BOTH VMs must compute identically bit-for-bit.
%%
%% zigvm's flatmap/HAMT boundary is max_flatmap_size = 32 (matches erts): maps
%% with <=32 keys are flat, >32 keys are hashmaps whose key ITERATION ORDER
%% differs from erts. So NO case asserts a specific key/value order for a large
%% map. Set-equality is asserted structurally instead — by map_size, per-key
%% map_get, is_map_key, and (crucially) MAP =:= comparison, which in Erlang is
%% order-independent: #{a=>1,b=>2} =:= #{b=>2,a=>1}. fold/map are computed with
%% this module's own list recursion over maps:keys/1 rather than maps:fold/2 or
%% maps:map/2 (those live in stdlib maps.erl, not the BIF set), keeping every
%% case self-contained on the map BIFs + core map ops only. No ct/port/node.
-module(zigvm_map_SUITE).
-export([all/0, c_new_put_get/1, c_update/1, c_remove_take/1, c_keys_values/1,
         c_from_list_roundtrip/1, c_merge/1, c_size/1, c_fold/1, c_map/1,
         c_without/1, c_large_hamt/1, c_map_equal_order/1, c_nested/1,
         c_guards/1]).

all() ->
    [c_new_put_get, c_update, c_remove_take, c_keys_values,
     c_from_list_roundtrip, c_merge, c_size, c_fold, c_map,
     c_without, c_large_hamt, c_map_equal_order, c_nested, c_guards].

%% ---- helpers (own recursion; no stdlib module dependency) ----

%% seq(N) -> [1,2,...,N]
seq(N) -> seq(N, []).
seq(0, Acc) -> Acc;
seq(N, Acc) when N > 0 -> seq(N - 1, [N | Acc]).

len(L) -> len(L, 0).
len([], Acc) -> Acc;
len([_ | T], Acc) -> len(T, Acc + 1).

%% build a map {I => I} for I in 1..N via maps:put folding
build_map(N) -> build_map(seq(N), #{}).
build_map([], M) -> M;
build_map([K | T], M) -> build_map(T, maps:put(K, K, M)).

%% [{I,I} || I <- Ks]
kv_pairs([]) -> [];
kv_pairs([K | T]) -> [{K, K} | kv_pairs(T)].

%% sum of map_get(K, M) over a key list
sum_vals([], _M, Acc) -> Acc;
sum_vals([K | T], M, Acc) -> sum_vals(T, M, Acc + map_get(K, M)).

%% sum a plain list of integers
sum_list([], Acc) -> Acc;
sum_list([X | T], Acc) -> sum_list(T, Acc + X).

%% transform: build a map {K => {token, map_get(K,Src)}} for K in Keys
token_map([], _Src, M) -> M;
token_map([K | T], Src, M) -> token_map(T, Src, maps:put(K, {token, map_get(K, Src)}, M)).

%% remove every key in Ks from M (own maps:without)
drop_keys([], M) -> M;
drop_keys([K | T], M) -> drop_keys(T, maps:remove(K, M)).

%% ---- cases ----

%% new/put/get/find/is_key on a small map.
c_new_put_get(_) ->
    M0 = #{},
    M1 = maps:put(a, 1, M0),
    M2 = maps:put(b, 2, M1),
    (map_size(M0) =:= 0)
        andalso (map_size(M2) =:= 2)
        andalso (map_get(a, M2) =:= 1)
        andalso (maps:get(b, M2) =:= 2)
        andalso (maps:find(a, M2) =:= {ok, 1})
        andalso (maps:find(zzz, M2) =:= error)
        andalso (is_map_key(a, M2) =:= true)
        andalso (is_map_key(c, M2) =:= false)
        andalso (maps:is_key(b, M2) =:= true).

%% update: maps:update, put-overwrite, and the := exact-update syntax.
c_update(_) ->
    M = #{x => 1, y => 2},
    M2 = maps:update(x, 10, M),
    M3 = maps:put(y, 20, M),
    M4 = M#{x := 100},
    (map_get(x, M2) =:= 10)
        andalso (map_get(y, M2) =:= 2)
        andalso (map_size(M2) =:= 2)
        andalso (map_get(y, M3) =:= 20)
        andalso (map_get(x, M4) =:= 100)
        andalso (map_get(y, M4) =:= 2)
        andalso (M2 =:= #{x => 10, y => 2}).

%% remove and take, including the no-op / error edges.
c_remove_take(_) ->
    M = #{a => 1, b => 2, c => 3},
    M2 = maps:remove(b, M),
    {V, M3} = maps:take(a, M),
    (map_size(M2) =:= 2)
        andalso (is_map_key(b, M2) =:= false)
        andalso (map_get(a, M2) =:= 1)
        andalso (maps:remove(nope, M) =:= M)
        andalso (V =:= 1)
        andalso (map_size(M3) =:= 2)
        andalso (is_map_key(a, M3) =:= false)
        andalso (maps:take(nope, M) =:= error).

%% keys/values as SETS (order-independent): reconstruct maps and compare =:=.
c_keys_values(_) ->
    M = #{1 => 10, 2 => 20, 3 => 30},
    Ks = maps:keys(M),
    Vs = maps:values(M),
    %% keys, as a set, equal {1,2,3} regardless of order
    KeysAsSet = maps:from_keys(Ks, 0),
    (len(Ks) =:= 3)
        andalso (len(Vs) =:= 3)
        andalso (KeysAsSet =:= #{1 => 0, 2 => 0, 3 => 0})
        %% values sum is order-independent
        andalso (sum_list(Vs, 0) =:= 60)
        %% every key maps to the value we put
        andalso (sum_vals(Ks, M, 0) =:= 60).

%% from_list round-trip and order/duplicate semantics.
c_from_list_roundtrip(_) ->
    P1 = [{a, 1}, {b, 2}, {c, 3}],
    P2 = [{c, 3}, {a, 1}, {b, 2}],
    M = maps:from_list(P1),
    %% different input orders yield an equal map
    (maps:from_list(P1) =:= maps:from_list(P2))
        andalso (map_get(a, M) =:= 1)
        andalso (map_get(c, M) =:= 3)
        andalso (map_size(M) =:= 3)
        %% last duplicate wins
        andalso (map_get(k, maps:from_list([{k, 1}, {k, 2}])) =:= 2)
        andalso (maps:from_list([]) =:= #{}).

%% merge: right map wins on shared keys; empty is the identity.
c_merge(_) ->
    A = #{a => 1, b => 2},
    B = #{b => 20, c => 3},
    M = maps:merge(A, B),
    (map_get(a, M) =:= 1)
        andalso (map_get(b, M) =:= 20)
        andalso (map_get(c, M) =:= 3)
        andalso (map_size(M) =:= 3)
        andalso (M =:= #{a => 1, b => 20, c => 3})
        andalso (maps:merge(#{}, A) =:= A)
        andalso (maps:merge(A, #{}) =:= A).

%% size across empty, singleton, and a built 50-key map.
c_size(_) ->
    (map_size(#{}) =:= 0)
        andalso (map_size(#{a => 1}) =:= 1)
        andalso (map_size(build_map(50)) =:= 50)
        andalso (map_size(build_map(32)) =:= 32).

%% fold (own recursion over keys): sum of values of #{I => I | 1..100} = 5050.
c_fold(_) ->
    M = build_map(100),
    Ks = maps:keys(M),
    (sum_vals(Ks, M, 0) =:= 5050)
        andalso (sum_list(maps:values(M), 0) =:= 5050).

%% map (own transform): #{I => {token,I}} reconstructed order-independently.
c_map(_) ->
    M1 = build_map(40),
    Expected = maps:from_list([{K, {token, K}} || K <- seq(40)]),
    M2 = token_map(maps:keys(M1), M1, #{}),
    (M2 =:= Expected)
        andalso (map_get(1, M2) =:= {token, 1})
        andalso (map_get(40, M2) =:= {token, 40})
        andalso (map_size(M2) =:= 40).

%% without (own drop over maps:remove), mirroring t_maps_without.
c_without(_) ->
    M0 = maps:from_list([{{k, I}, {v, I}} || I <- seq(20)]),
    Drop = [{k, 3}, {k, 7}, {k, 11}],
    M1 = drop_keys(Drop, M0),
    (map_size(M1) =:= 17)
        andalso (is_map_key({k, 3}, M1) =:= false)
        andalso (is_map_key({k, 7}, M1) =:= false)
        andalso (is_map_key({k, 4}, M1) =:= true)
        andalso (map_get({k, 4}, M1) =:= {v, 4}).

%% >32-key HAMT: assert size + per-key access + SET-equality, never order.
c_large_hamt(_) ->
    N = 50,
    M = build_map(N),
    %% order-independent round-trip: reverse the input pairs, must still be =:=
    Rev = kv_pairs(seq(N)),        %% [{1,1}..{50,50}]
    (map_size(M) =:= N)
        andalso (M =:= maps:from_list(Rev))
        andalso (map_get(1, M) =:= 1)
        andalso (map_get(25, M) =:= 25)
        andalso (map_get(50, M) =:= 50)
        andalso (is_map_key(50, M) =:= true)
        andalso (is_map_key(51, M) =:= false)
        %% key set equals {1..50} regardless of HAMT iteration order
        andalso (maps:from_keys(maps:keys(M), 0) =:= maps:from_keys(seq(N), 0)).

%% map equality is order-independent (small AND large).
c_map_equal_order(_) ->
    Small1 = #{a => 1, b => 2, c => 3},
    Small2 = #{c => 3, b => 2, a => 1},
    Big1 = build_map(40),
    Big2 = maps:from_list(kv_pairs(seq(40))),
    (Small1 =:= Small2)
        andalso (Small1 =/= #{a => 1, b => 2})
        andalso (Small1 =/= #{a => 1, b => 2, c => 4})
        andalso (Big1 =:= Big2)
        andalso (#{} =:= #{}).

%% nested maps: deep exact-update reads back the new inner value.
c_nested(_) ->
    M = #{outer => #{inner => 1}, tag => ok},
    Inner = map_get(outer, M),
    M2 = M#{outer := Inner#{inner := 2}},
    (map_get(inner, map_get(outer, M)) =:= 1)
        andalso (map_get(inner, map_get(outer, M2)) =:= 2)
        andalso (map_get(tag, M2) =:= ok)
        andalso (map_size(M2) =:= 2).

%% maps in guards: is_map, map_size, is_map_key, map_get all guard-safe.
c_guards(_) ->
    Classify = fun(X) when is_map(X), map_size(X) =:= 0 -> empty;
                  (X) when is_map(X), is_map_key(key, X) -> keyed;
                  (X) when is_map(X) -> other;
                  (_) -> not_a_map
               end,
    (Classify(#{}) =:= empty)
        andalso (Classify(#{key => 1}) =:= keyed)
        andalso (Classify(#{a => 1}) =:= other)
        andalso (Classify([]) =:= not_a_map)
        andalso (is_map(#{}) =:= true)
        andalso (is_map([]) =:= false).
