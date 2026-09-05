%% eco_coll — a reduced ecosystem app exercising the `sets`, `gb_trees`,
%% `ordsets`, `queue`, `dict`, and `orddict` collection modules zigvm now hosts
%% via the preloaded stock stdlib (gap-hof-coll DIVERGENCE 663; ordsets/queue
%% DIVERGENCE 665; dict/orddict DIVERGENCE 666). All are Erlang code, not BIFs —
%% undef before these slices. `sets` is maps-backed (rides the already-preloaded
%% maps); `gb_trees`/`ordsets`/`queue`/`dict`/`orddict` are self-contained (over
%% lists/erlang guards).
%%
%% Run as `zigvm run eco_coll.beam suite` — the END-TO-END proof the `run` CLI
%% preloads these. HONESTY BOUNDS: NEVER compares the opaque set/tree term
%% itself — only observable outputs (sorted element lists via lists:sort, sizes,
%% booleans, and gb_trees' DETERMINISTIC key-ordered lists). So the EQ turns on
%% the module semantics, not the internal representation (which is version- and
%% impl-coupled).
-module(eco_coll).
-export([suite/0]).

suite() ->
    %% sets — observable outputs only (sorted, never the opaque set).
    S = sets:from_list([3, 1, 2, 1, 3]),
    C1  = (sets:size(S) =:= 3),
    C2  = (sets:is_element(2, S)) andalso (not sets:is_element(9, S)),
    C3  = (lists:sort(sets:to_list(S)) =:= [1, 2, 3]),
    C4  = (lists:sort(sets:to_list(sets:union(sets:from_list([1, 2]), sets:from_list([2, 3])))) =:= [1, 2, 3]),
    C5  = (lists:sort(sets:to_list(sets:intersection(sets:from_list([1, 2, 3]), sets:from_list([2, 3, 4])))) =:= [2, 3]),
    C6  = (lists:sort(sets:to_list(sets:subtract(sets:from_list([1, 2, 3]), sets:from_list([2])))) =:= [1, 3]),
    C7  = (sets:is_subset(sets:from_list([1, 2]), sets:from_list([1, 2, 3]))),
    C8  = (sets:size(sets:add_element(5, S)) =:= 4),
    C9  = (sets:size(sets:del_element(1, S)) =:= 2),
    %% sets:fold works; sets:map/filter need erts_internal:mc_iterator/1 (a
    %% native BIF zigvm lacks — a SEPARATE gap, DIVERGENCE 663), so those are
    %% deliberately NOT asserted here (fold reaches every element instead).
    C10 = (sets:fold(fun(X, A) -> X + A end, 0, S) =:= 6),

    %% gb_trees — ordered ops are DETERMINISTIC (key order is total).
    T = gb_trees:from_orddict([{1, a}, {2, b}, {3, c}]),
    C11 = (gb_trees:get(2, T) =:= b),
    C12 = (gb_trees:size(T) =:= 3),
    C13 = (gb_trees:keys(gb_trees:insert(4, d, T)) =:= [1, 2, 3, 4]),
    C14 = (gb_trees:values(T) =:= [a, b, c]),
    C15 = (gb_trees:lookup(2, T) =:= {value, b}) andalso (gb_trees:lookup(9, T) =:= none),
    C16 = (gb_trees:is_defined(3, T)) andalso (not gb_trees:is_defined(9, T)),
    C17 = (gb_trees:get(2, gb_trees:update(2, bb, T)) =:= bb),
    C18 = (gb_trees:size(gb_trees:delete(1, T)) =:= 2),
    C19 = (gb_trees:smallest(T) =:= {1, a}) andalso (gb_trees:largest(T) =:= {3, c}),
    C20 = (gb_trees:to_list(T) =:= [{1, a}, {2, b}, {3, c}]),

    %% ordsets — an ordset IS a sorted list, so the term itself is observable
    %% and deterministic (no opaque-representation caveat).
    OS = ordsets:from_list([3, 1, 2, 1, 3]),
    C21 = (ordsets:to_list(OS) =:= [1, 2, 3]),
    C22 = (ordsets:is_element(2, OS)) andalso (not ordsets:is_element(9, OS)),
    C23 = (ordsets:union(ordsets:from_list([1, 2]), ordsets:from_list([2, 3])) =:= [1, 2, 3]),
    C24 = (ordsets:intersection(ordsets:from_list([1, 2, 3]), ordsets:from_list([2, 3, 4])) =:= [2, 3]),
    C25 = (ordsets:subtract(ordsets:from_list([1, 2, 3]), ordsets:from_list([2])) =:= [1, 3]),
    C26 = (ordsets:add_element(5, OS) =:= [1, 2, 3, 5]),
    C27 = (ordsets:is_subset(ordsets:from_list([1, 2]), OS)),

    %% queue — FIFO; to_list/len/in/out/get/reverse are all deterministic.
    Q = queue:from_list([1, 2, 3]),
    C28 = (queue:to_list(Q) =:= [1, 2, 3]),
    C29 = (queue:len(Q) =:= 3),
    C30 = (queue:to_list(queue:in(4, Q)) =:= [1, 2, 3, 4]),
    C31 = (begin {{value, V}, Q2} = queue:out(Q), (V =:= 1) andalso (queue:to_list(Q2) =:= [2, 3]) end),
    C32 = (queue:get(Q) =:= 1) andalso (queue:get_r(Q) =:= 3),
    C33 = (queue:to_list(queue:reverse(Q)) =:= [3, 2, 1]),
    C34 = (queue:is_empty(queue:new())) andalso (not queue:is_empty(Q)),

    %% dict — hash-based; element ORDER is representation-coupled, so every
    %% enumeration is lists:sort-normalised (never the raw dict order).
    D = dict:from_list([{a, 1}, {b, 2}, {c, 3}]),
    C35 = (dict:fetch(b, D) =:= 2),
    C36 = (dict:find(a, D) =:= {ok, 1}) andalso (dict:find(z, D) =:= error),
    C37 = (dict:size(D) =:= 3),
    C38 = (lists:sort(dict:fetch_keys(D)) =:= [a, b, c]),
    C39 = (lists:sort(dict:to_list(D)) =:= [{a, 1}, {b, 2}, {c, 3}]),
    C40 = (dict:fetch(d, dict:store(d, 4, D)) =:= 4),
    C41 = (dict:fetch(a, dict:update_counter(a, 10, D)) =:= 11),
    C42 = (dict:is_key(c, D)) andalso (not dict:is_key(z, D)),
    C43 = (lists:sort(dict:to_list(dict:erase(b, D))) =:= [{a, 1}, {c, 3}]),

    %% orddict — an ordered assoc-list; the term IS sorted (observable directly).
    OD = orddict:from_list([{c, 3}, {a, 1}, {b, 2}]),
    C44 = (orddict:to_list(OD) =:= [{a, 1}, {b, 2}, {c, 3}]),
    C45 = (orddict:fetch(b, OD) =:= 2),
    C46 = (orddict:to_list(orddict:store(d, 4, OD)) =:= [{a, 1}, {b, 2}, {c, 3}, {d, 4}]),
    C47 = (orddict:to_list(orddict:map(fun(_K, Vv) -> Vv * 10 end, OD)) =:= [{a, 10}, {b, 20}, {c, 30}]),
    C48 = (orddict:fold(fun(_K, Vv, A) -> Vv + A end, 0, OD) =:= 6),

    %% array — the extensible functional array (default-valued, HOF map/foldl).
    AR = array:from_list([10, 20, 30]),
    C49 = (array:get(1, AR) =:= 20),
    C50 = (array:size(AR) =:= 3),
    C51 = (array:to_list(array:set(1, 99, AR)) =:= [10, 99, 30]),
    C52 = (array:to_list(array:map(fun(_I, Va) -> Va + 1 end, AR)) =:= [11, 21, 31]),
    C53 = (array:foldl(fun(_I, Va, A) -> Va + A end, 0, AR) =:= 60),
    C54 = (array:get(5, array:new(10)) =:= undefined),

    case
        C1 andalso C2 andalso C3 andalso C4 andalso C5 andalso C6 andalso C7
        andalso C8 andalso C9 andalso C10 andalso C11 andalso C12 andalso C13
        andalso C14 andalso C15 andalso C16 andalso C17 andalso C18 andalso C19
        andalso C20 andalso C21 andalso C22 andalso C23 andalso C24 andalso C25
        andalso C26 andalso C27 andalso C28 andalso C29 andalso C30 andalso C31
        andalso C32 andalso C33 andalso C34 andalso C35 andalso C36 andalso C37
        andalso C38 andalso C39 andalso C40 andalso C41 andalso C42 andalso C43
        andalso C44 andalso C45 andalso C46 andalso C47 andalso C48
        andalso C49 andalso C50 andalso C51 andalso C52 andalso C53 andalso C54
    of
        true -> ok;
        false -> fail
    end.
