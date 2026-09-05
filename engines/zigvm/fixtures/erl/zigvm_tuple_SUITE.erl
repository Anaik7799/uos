%% Curated PURE subset of erts/emulator/test/tuple_SUITE.erl (E7 suite closure).
%% The real suite exercises the tuple BIFs (element/2, setelement/3,
%% tuple_size/1, erlang:make_tuple/2,3, append_element/2, insert_element/3,
%% delete_element/2), the list_to_tuple/tuple_to_list round-trip, and tuple
%% term ordering. These cases assert REPRESENTATION-INDEPENDENT, VALUE-STABLE
%% truths that both VMs must compute identically (byte-EQ), mirroring the
%% suite's build_and_match, t_tuple_size, t_element, t_setelement,
%% t_list_to_tuple, t_tuple_to_list, t_make_tuple_2/3, t_append_element,
%% t_insert_element, t_delete_element, tuple_in_guard cases. Error-path
%% (badarg/catch), huge-tuple (1 bsl 20+), destructive record_update GC,
%% and JIT get_two_tuple_elements cases are EXCLUDED (need catch/exceptions,
%% enormous heaps, forced GC, or on-disk compilation). No ct/port/node
%% dependency and no lists:* calls — runnable on zigvm.
-module(zigvm_tuple_SUITE).
-export([all/0, c_build_and_match/1, c_tuple_size/1, c_element/1,
         c_setelement/1, c_list_to_tuple/1, c_tuple_to_list/1, c_round_trip/1,
         c_make_tuple_2/1, c_make_tuple_3/1, c_append_element/1,
         c_insert_element/1, c_delete_element/1, c_tuple_in_guard/1,
         c_tuple_ordering/1]).

all() ->
    [c_build_and_match, c_tuple_size, c_element, c_setelement,
     c_list_to_tuple, c_tuple_to_list, c_round_trip, c_make_tuple_2,
     c_make_tuple_3, c_append_element, c_insert_element, c_delete_element,
     c_tuple_in_guard, c_tuple_ordering].

%% build_and_match: tuples of assorted arities build and match structurally.
c_build_and_match(_) ->
    ({} =:= {})
        andalso ({1} =:= {1})
        andalso ({1, 2, 3} =:= {1, 2, 3})
        andalso ({1, 2, 3, 4, 5, 6, 7, 8} =:= {1, 2, 3, 4, 5, 6, 7, 8})
        andalso ({1, 2, 3} =/= {1, 2, 4})
        andalso ({a, {b}, c} =:= {a, {b}, c}).

%% t_tuple_size: tuple_size/1 counts arity, including nested tuples as one slot.
c_tuple_size(_) ->
    (tuple_size({}) =:= 0)
        andalso (tuple_size({a}) =:= 1)
        andalso (tuple_size({{a}}) =:= 1)
        andalso (tuple_size({{a}, {b}}) =:= 2)
        andalso (tuple_size({1, 2, 3}) =:= 3)
        andalso (tuple_size({1, 2, 3, 4, 5, 6, 7, 8}) =:= 8).

%% t_element: element/2 selects the 1-based position.
c_element(_) ->
    (element(1, {a}) =:= a)
        andalso (element(1, {a, b}) =:= a)
        andalso (element(2, {a, b, c}) =:= b)
        andalso (element(3, {a, b, c}) =:= c)
        andalso (element(8, {1, 2, 3, 4, 5, 6, 7, 8}) =:= 8)
        andalso (element(2, {a, {b, b}, c}) =:= {b, b}).

%% t_setelement: setelement/3 replaces one slot, functionally (incl. nesting).
c_setelement(_) ->
    Big = 93748793749387837476555412,
    T0 = {0, 0, a, b, c},
    (setelement(1, {1}, x) =:= {x})
        andalso (setelement(1, {1, 2}, x) =:= {x, 2})
        andalso (setelement(2, {1, 2}, x) =:= {1, x})
        andalso (setelement(3, {a, b, c, d}, z) =:= {a, b, z, d})
        andalso (setelement(1, setelement(2, setelement(3, T0, gurka), 3.0), Big)
                     =:= {Big, 3.0, gurka, b, c}).

%% t_list_to_tuple: list_to_tuple/1 builds a tuple from a proper list.
c_list_to_tuple(_) ->
    (list_to_tuple([]) =:= {})
        andalso (list_to_tuple([a]) =:= {a})
        andalso (list_to_tuple([a, b]) =:= {a, b})
        andalso (list_to_tuple([a, b, c, d, e]) =:= {a, b, c, d, e})
        andalso (list_to_tuple([1, 2, 3]) =:= {1, 2, 3}).

%% t_tuple_to_list: tuple_to_list/1 flattens the top level to a list.
c_tuple_to_list(_) ->
    (tuple_to_list({}) =:= [])
        andalso (tuple_to_list({a}) =:= [a])
        andalso (tuple_to_list({a, b, c, d}) =:= [a, b, c, d])
        andalso (tuple_to_list({1, {2}, 3}) =:= [1, {2}, 3]).

%% list_to_tuple/tuple_to_list are mutual inverses (round-trip law).
c_round_trip(_) ->
    L = [a, b, c, d, e, f, g],
    (tuple_to_list(list_to_tuple(L)) =:= L)
        andalso (list_to_tuple(tuple_to_list({1, 2, 3, 4})) =:= {1, 2, 3, 4})
        andalso (tuple_to_list(list_to_tuple([])) =:= []).

%% t_make_tuple_2: erlang:make_tuple/2 fills every slot with one element.
c_make_tuple_2(_) ->
    (erlang:make_tuple(0, a) =:= {})
        andalso (erlang:make_tuple(1, a) =:= {a})
        andalso (erlang:make_tuple(3, x) =:= {x, x, x})
        andalso (erlang:make_tuple(5, 0) =:= {0, 0, 0, 0, 0})
        andalso (tuple_size(erlang:make_tuple(4, def)) =:= 4).

%% t_make_tuple_3: erlang:make_tuple/3 seeds a default then applies overrides,
%% last write per index winning.
c_make_tuple_3(_) ->
    (erlang:make_tuple(0, def, []) =:= {})
        andalso (erlang:make_tuple(1, def, []) =:= {def})
        andalso (erlang:make_tuple(1, def, [{1, a}]) =:= {a})
        andalso (erlang:make_tuple(5, def, [{5, e}, {1, a}, {3, c}])
                     =:= {a, def, c, def, e})
        andalso (erlang:make_tuple(5, def, [{1, blurf}, {5, e}, {3, blurf}, {1, a}, {3, c}])
                     =:= {a, def, c, def, e}).

%% t_append_element: erlang:append_element/2 grows the tuple by one at the end.
c_append_element(_) ->
    (erlang:append_element({}, a) =:= {a})
        andalso (erlang:append_element({a}, b) =:= {a, b})
        andalso (erlang:append_element({1, 2}, 3) =:= {1, 2, 3})
        andalso (erlang:append_element({a, b, c}, d) =:= {a, b, c, d}).

%% t_insert_element: erlang:insert_element/3 inserts before the given position.
c_insert_element(_) ->
    (erlang:insert_element(1, {}, a) =:= {a})
        andalso (erlang:insert_element(1, {a}, {b, b}) =:= {{b, b}, a})
        andalso (erlang:insert_element(2, {a}, b) =:= {a, b})
        andalso (erlang:insert_element(2, {a, c}, b) =:= {a, b, c})
        andalso (erlang:insert_element(4, {a, b, c}, d) =:= {a, b, c, d}).

%% t_delete_element: erlang:delete_element/2 removes the slot at the position.
c_delete_element(_) ->
    (erlang:delete_element(1, {a}) =:= {})
        andalso (erlang:delete_element(1, {a, {b, b}, c}) =:= {{b, b}, c})
        andalso (erlang:delete_element(2, {a, c, b}) =:= {a, b})
        andalso (erlang:delete_element(3, {a, b, c, d}) =:= {a, b, d}).

%% tuple_in_guard: a tuple built inside a guard from element/2 calls equals the
%% original (the historic BEAM circular-build regression).
c_tuple_in_guard(_) ->
    T2 = {a, b, c},
    G1 = if {a, b} == {element(1, T2), element(2, T2)} -> true; true -> false end,
    G2 = if T2 == {element(1, T2), element(2, T2), element(3, T2)} -> true; true -> false end,
    G1 andalso G2.

%% tuple ordering: Erlang orders tuples first by arity, then element-wise.
c_tuple_ordering(_) ->
    ({} < {a})
        andalso ({a} < {a, a})
        andalso ({1, 2} < {1, 3})
        andalso ({1, 2, 3} < {1, 3, 0})
        andalso ({a} < {b})
        andalso ({2, 1} > {1, 9})
        andalso ({1, 2} =< {1, 2})
        andalso ({1, 2} =:= {1, 2}).
