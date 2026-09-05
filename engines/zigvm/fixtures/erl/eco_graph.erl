%% eco_graph — a reduced ecosystem app exercising the `gb_sets` and `digraph`
%% modules zigvm now hosts via the preloaded stock stdlib (gap-hof-graph,
%% DIVERGENCE 668). gb_sets is a general-balanced-tree set (self-contained);
%% digraph is an ETS-BACKED, STATEFUL directed graph (digraph:new mints ETS
%% tables via the native ets BIFs).
%%
%% Run as `zigvm run eco_graph.beam suite`. HONESTY BOUNDS: never compares the
%% digraph HANDLE term (it embeds ETS Tids — zigvm's are ints, OTP's #Refs,
%% repr-coupled) nor a gb_sets opaque term — only OBSERVABLE outputs (sorted
%% element lists, sizes, bools, vertex/path/neighbour lists that are plain atoms).
-module(eco_graph).
-export([suite/0]).

suite() ->
    %% gb_sets — observable via sorted to_list / sizes / bools.
    S = gb_sets:from_list([3, 1, 2, 1, 3]),
    C1  = (gb_sets:to_list(S) =:= [1, 2, 3]),
    C2  = (gb_sets:size(S) =:= 3),
    C3  = (gb_sets:is_member(2, S)) andalso (not gb_sets:is_member(9, S)),
    C4  = (gb_sets:to_list(gb_sets:union(gb_sets:from_list([1, 2]), gb_sets:from_list([2, 3]))) =:= [1, 2, 3]),
    C5  = (gb_sets:to_list(gb_sets:intersection(gb_sets:from_list([1, 2, 3]), gb_sets:from_list([2, 3, 4]))) =:= [2, 3]),
    C6  = (gb_sets:to_list(gb_sets:subtract(gb_sets:from_list([1, 2, 3]), gb_sets:from_list([2]))) =:= [1, 3]),
    C7  = ({gb_sets:smallest(S), gb_sets:largest(S)} =:= {1, 3}),
    C8  = (gb_sets:to_list(gb_sets:add_element(5, S)) =:= [1, 2, 3, 5]),
    C9  = (gb_sets:to_list(gb_sets:delete(1, S)) =:= [2, 3]),
    C10 = (gb_sets:is_subset(gb_sets:from_list([1, 2]), S)),
    C11 = (gb_sets:to_list(gb_sets:filter(fun(X) -> X > 1 end, S)) =:= [2, 3]),

    %% digraph — ETS-backed; query results are observable (never the handle).
    G = digraph:new(),
    [digraph:add_vertex(G, V) || V <- [a, b, c, d]],
    digraph:add_edge(G, a, b),
    digraph:add_edge(G, b, c),
    digraph:add_edge(G, a, d),
    C12 = (lists:sort(digraph:vertices(G)) =:= [a, b, c, d]),
    C13 = (digraph:no_vertices(G) =:= 4),
    C14 = (digraph:no_edges(G) =:= 3),
    C15 = (digraph:get_path(G, a, c) =:= [a, b, c]),
    C16 = (digraph:get_path(G, c, a) =:= false),
    C17 = (lists:sort(digraph:out_neighbours(G, a)) =:= [b, d]),
    C18 = (digraph:in_neighbours(G, c) =:= [b]),
    C19 = (digraph:in_degree(G, c) =:= 1) andalso (digraph:out_degree(G, a) =:= 2),
    %% digraph:del_vertex/del_edge need ets:select_delete/2 (a native ETS BIF
    %% zigvm lacks — a SEPARATE gap, DIVERGENCE 668), so deletion is NOT asserted
    %% here; edge COUNT (length of the opaque edge-id list — the ids themselves
    %% are never compared) exercises the graph instead.
    C20 = (length(digraph:edges(G)) =:= 3) andalso (digraph:get_path(G, a, b) =:= [a, b]),

    case
        C1 andalso C2 andalso C3 andalso C4 andalso C5 andalso C6 andalso C7
        andalso C8 andalso C9 andalso C10 andalso C11 andalso C12 andalso C13
        andalso C14 andalso C15 andalso C16 andalso C17 andalso C18 andalso C19
        andalso C20
    of
        true -> ok;
        false -> fail
    end.
