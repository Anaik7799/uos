-module(graphene_nif).
-export([graph_bfs/3, graph_dfs/3, graph_topological_sort/2, graph_scc/2,
         graph_shortest_path/4, graph_pagerank/4, graph_analyze/2,
         render_state_diagram/6, render_component/2, render_all_diagrams/1,
         svg_path_from_points/1, svg_path_analyze/1, svg_path_transform/2,
         svg_shape/1, vec2_math/2,
         mermaid_render/2, mermaid_render_to_file/2,
         kurbo_affine_op/2, kurbo_geometry_op/2, kurbo_bezier_op/2,
         mermaid_render_with_options/2, skia_draw_to_png/4,
         resvg_render_svg_to_png/3, resvg_render_file/3, plotters_chart/2, plotters_chart_to_file/3,
         vega_lite_spec/2, vega_lite_layered/1, vega_lite_preset/2,
         petgraph_op/4, grafana_dashboard_json/2, grafana_panel_preset/2]).

%% Pure Erlang implementation (Zero-Muda: zero Bevy, zero Graphite NIF dependency).
%%
%% 2026-09-08 (SC-PROVENANCE-001, sa-plan uos/km-convergence/20260908-0940 g1):
%% the seven graph functions below were STUB FACADES. They ignored the edge list
%% entirely: graph_bfs returned only the start node, graph_shortest_path returned
%% [From,To] with cost 1.0 for any pair, graph_analyze hardcoded density 0.5 and
%% is_dag true. The pre-existing tests only asserted should.be_ok(), so the stubs
%% passed. They are now real algorithms with behavioural tests.
%%
%% Input contract (unchanged): NodesJson is ["A","B"], EdgesJson is
%% [["A","B",Weight], ...] describing a DIRECTED weighted graph.
%%
%% The rendering functions further below remain deliberate stubs; they are not
%% claimed to be implementations.

%% --- graph decoding helpers -------------------------------------------------

decode_nodes(NodesJson) ->
    case catch json:decode(iolist_to_binary(NodesJson)) of
        L when is_list(L) -> [N || N <- L, is_binary(N)];
        _ -> []
    end.

%% Returns [{From, To, Weight}] keeping only well-formed triples.
decode_edges(EdgesJson) ->
    case catch json:decode(iolist_to_binary(EdgesJson)) of
        L when is_list(L) ->
            lists:foldr(
                fun([F, T, W], Acc) when is_binary(F), is_binary(T), is_number(W) ->
                        [{F, T, W} | Acc];
                    ([F, T], Acc) when is_binary(F), is_binary(T) ->
                        [{F, T, 1} | Acc];
                    (_, Acc) -> Acc
                end, [], L);
        _ -> []
    end.

%% Adjacency map: #{Node => [{Neighbour, Weight}]} with every node present.
adjacency(Nodes, Edges) ->
    Empty = maps:from_list([{N, []} || N <- Nodes]),
    lists:foldl(
        fun({F, T, W}, Acc) ->
            case maps:is_key(F, Acc) of
                true -> maps:update_with(F, fun(L) -> L ++ [{T, W}] end, Acc);
                false -> Acc
            end
        end, Empty, Edges).

neighbours(Node, Adj) ->
    [T || {T, _W} <- maps:get(Node, Adj, [])].

%% --- 1. Breadth-first search ------------------------------------------------
%% Returns visit order and the depth of each reached node. Unreachable nodes are
%% absent from both, which is the defining property of a traversal.

graph_bfs(NodesJson, EdgesJson, Start) ->
    Nodes = decode_nodes(NodesJson),
    Adj = adjacency(Nodes, decode_edges(EdgesJson)),
    {Order, Depths} = case lists:member(Start, Nodes) of
        false -> {[], #{}};
        true -> bfs_loop(queue:from_list([{Start, 0}]), #{Start => 0}, [Start], Adj)
    end,
    {ok, iolist_to_binary(json:encode(#{
        <<"order">> => Order,
        <<"depths">> => Depths
    }))}.

bfs_loop(Q0, Depths, Order, Adj) ->
    case queue:out(Q0) of
        {empty, _} -> {lists:reverse(Order), Depths};
        {{value, {Node, D}}, Q1} ->
            {Q2, Depths1, Order1} =
                lists:foldl(
                    fun(Nb, {QA, DA, OA}) ->
                        case maps:is_key(Nb, DA) of
                            true -> {QA, DA, OA};
                            false ->
                                {queue:in({Nb, D + 1}, QA), DA#{Nb => D + 1}, [Nb | OA]}
                        end
                    end, {Q1, Depths, Order}, neighbours(Node, Adj)),
            bfs_loop(Q2, Depths1, Order1, Adj)
    end.

%% --- 2. Depth-first search --------------------------------------------------

graph_dfs(NodesJson, EdgesJson, Start) ->
    Nodes = decode_nodes(NodesJson),
    Adj = adjacency(Nodes, decode_edges(EdgesJson)),
    Order = case lists:member(Start, Nodes) of
        false -> [];
        true -> element(1, dfs_visit(Start, {[], #{}}, Adj))
    end,
    {ok, iolist_to_binary(json:encode(#{<<"order">> => lists:reverse(Order)}))}.

dfs_visit(Node, {Order, Seen}, Adj) ->
    case maps:is_key(Node, Seen) of
        true -> {Order, Seen};
        false ->
            lists:foldl(fun(Nb, Acc) -> dfs_visit(Nb, Acc, Adj) end,
                        {[Node | Order], Seen#{Node => true}},
                        neighbours(Node, Adj))
    end.

%% --- 3. Topological sort (Kahn) ---------------------------------------------
%% A cyclic graph has no topological order, so it is reported as acyclic=false
%% with an empty order rather than an arbitrary sequence.

graph_topological_sort(NodesJson, EdgesJson) ->
    Nodes = decode_nodes(NodesJson),
    Edges = decode_edges(EdgesJson),
    Adj = adjacency(Nodes, Edges),
    InDeg0 = maps:from_list([{N, 0} || N <- Nodes]),
    InDeg = lists:foldl(
        fun({_F, T, _W}, Acc) ->
            case maps:is_key(T, Acc) of
                true -> maps:update_with(T, fun(C) -> C + 1 end, Acc);
                false -> Acc
            end
        end, InDeg0, Edges),
    Ready = [N || N <- Nodes, maps:get(N, InDeg, 0) =:= 0],
    Order = kahn(Ready, InDeg, [], Adj),
    Acyclic = length(Order) =:= length(Nodes),
    {ok, iolist_to_binary(json:encode(#{
        <<"order">> => case Acyclic of true -> Order; false -> [] end,
        <<"acyclic">> => Acyclic
    }))}.

kahn([], _InDeg, Acc, _Adj) -> lists:reverse(Acc);
kahn([N | Rest], InDeg, Acc, Adj) ->
    {Ready, InDeg1} =
        lists:foldl(
            fun(Nb, {R, D}) ->
                D1 = maps:update_with(Nb, fun(C) -> C - 1 end, D),
                case maps:get(Nb, D1, 1) of
                    0 -> {R ++ [Nb], D1};
                    _ -> {R, D1}
                end
            end, {Rest, InDeg}, neighbours(N, Adj)),
    kahn(Ready, InDeg1, [N | Acc], Adj).

%% --- 4. Strongly connected components (Tarjan) ------------------------------

graph_scc(NodesJson, EdgesJson) ->
    Nodes = decode_nodes(NodesJson),
    Adj = adjacency(Nodes, decode_edges(EdgesJson)),
    St0 = #{index => 0, indices => #{}, low => #{}, stack => [],
            onstack => #{}, comps => []},
    St = lists:foldl(
        fun(N, StA) ->
            case maps:is_key(N, maps:get(indices, StA)) of
                true -> StA;
                false -> tarjan(N, StA, Adj)
            end
        end, St0, Nodes),
    Comps = lists:reverse(maps:get(comps, St)),
    {ok, iolist_to_binary(json:encode(#{
        <<"components">> => Comps,
        <<"count">> => length(Comps)
    }))}.

tarjan(V, St0, Adj) ->
    Idx = maps:get(index, St0),
    St1 = St0#{index := Idx + 1,
               indices := (maps:get(indices, St0))#{V => Idx},
               low := (maps:get(low, St0))#{V => Idx},
               stack := [V | maps:get(stack, St0)],
               onstack := (maps:get(onstack, St0))#{V => true}},
    St2 = lists:foldl(
        fun(W, StA) ->
            Indices = maps:get(indices, StA),
            case maps:is_key(W, Indices) of
                false ->
                    StB = tarjan(W, StA, Adj),
                    LowB = maps:get(low, StB),
                    StB#{low := LowB#{V => min(maps:get(V, LowB), maps:get(W, LowB))}};
                true ->
                    case maps:get(W, maps:get(onstack, StA), false) of
                        true ->
                            LowA = maps:get(low, StA),
                            StA#{low := LowA#{V => min(maps:get(V, LowA), maps:get(W, Indices))}};
                        false -> StA
                    end
            end
        end, St1, neighbours(V, Adj)),
    Low = maps:get(low, St2),
    Indices2 = maps:get(indices, St2),
    case maps:get(V, Low) =:= maps:get(V, Indices2) of
        false -> St2;
        true ->
            {Comp, Rest, OnStack1} = pop_component(V, maps:get(stack, St2),
                                                   maps:get(onstack, St2), []),
            St2#{stack := Rest, onstack := OnStack1,
                 comps := [Comp | maps:get(comps, St2)]}
    end.

pop_component(V, [W | Rest], OnStack, Acc) ->
    OnStack1 = maps:remove(W, OnStack),
    case W =:= V of
        true -> {lists:reverse([W | Acc]), Rest, OnStack1};
        false -> pop_component(V, Rest, OnStack1, [W | Acc])
    end;
pop_component(_V, [], OnStack, Acc) -> {lists:reverse(Acc), [], OnStack}.

%% --- 5. Shortest path (Dijkstra, non-negative weights) ----------------------
%% An unreachable target yields found=false with a null cost, never a fabricated
%% unit-cost edge.

graph_shortest_path(NodesJson, EdgesJson, From, To) ->
    Nodes = decode_nodes(NodesJson),
    Adj = adjacency(Nodes, decode_edges(EdgesJson)),
    case lists:member(From, Nodes) andalso lists:member(To, Nodes) of
        false ->
            {ok, iolist_to_binary(json:encode(#{
                <<"path">> => [], <<"cost">> => null, <<"found">> => false}))};
        true ->
            {Dist, Prev} = dijkstra([{0, From}], #{From => 0}, #{}, Adj),
            case maps:find(To, Dist) of
                error ->
                    {ok, iolist_to_binary(json:encode(#{
                        <<"path">> => [], <<"cost">> => null, <<"found">> => false}))};
                {ok, Cost} ->
                    {ok, iolist_to_binary(json:encode(#{
                        <<"path">> => rebuild_path(To, Prev, [To]),
                        <<"cost">> => float(Cost),
                        <<"found">> => true}))}
            end
    end.

dijkstra([], Dist, Prev, _Adj) -> {Dist, Prev};
dijkstra(Frontier, Dist, Prev, Adj) ->
    [{D, U} | Rest] = lists:sort(Frontier),
    case maps:get(U, Dist, infinity) < D of
        true -> dijkstra(Rest, Dist, Prev, Adj);
        false ->
            {F1, Dist1, Prev1} =
                lists:foldl(
                    fun({V, W}, {FA, DA, PA}) ->
                        Alt = D + W,
                        case Alt < maps:get(V, DA, infinity) of
                            true -> {[{Alt, V} | FA], DA#{V => Alt}, PA#{V => U}};
                            false -> {FA, DA, PA}
                        end
                    end, {Rest, Dist, Prev}, maps:get(U, Adj, [])),
            dijkstra(F1, Dist1, Prev1, Adj)
    end.

rebuild_path(Node, Prev, Acc) ->
    case maps:find(Node, Prev) of
        error -> Acc;
        {ok, P} -> rebuild_path(P, Prev, [P | Acc])
    end.

%% --- 6. PageRank (power iteration with damping) -----------------------------
%% Dangling nodes redistribute their mass uniformly, so the vector sums to 1.

graph_pagerank(NodesJson, EdgesJson, Damping, Iterations) ->
    Nodes = decode_nodes(NodesJson),
    Adj = adjacency(Nodes, decode_edges(EdgesJson)),
    N = length(Nodes),
    D = to_float(Damping),
    Iter = case is_integer(Iterations) andalso Iterations > 0 of
        true -> min(Iterations, 1000);
        false -> 20
    end,
    case N of
        0 -> {ok, iolist_to_binary(json:encode(#{<<"ranks">> => #{}}))};
        _ ->
            Init = maps:from_list([{Node, 1.0 / N} || Node <- Nodes]),
            Ranks = pagerank_iter(Iter, Init, Nodes, Adj, D, N),
            {ok, iolist_to_binary(json:encode(#{<<"ranks">> => Ranks}))}
    end.

pagerank_iter(0, Ranks, _Nodes, _Adj, _D, _N) -> Ranks;
pagerank_iter(K, Ranks, Nodes, Adj, D, N) ->
    Dangling = lists:sum([maps:get(Node, Ranks) || Node <- Nodes,
                          neighbours(Node, Adj) =:= []]),
    Base = (1.0 - D) / N + D * Dangling / N,
    Contrib = lists:foldl(
        fun(Node, Acc) ->
            Out = neighbours(Node, Adj),
            case Out of
                [] -> Acc;
                _ ->
                    Share = D * maps:get(Node, Ranks) / length(Out),
                    lists:foldl(fun(Nb, A) ->
                        maps:update_with(Nb, fun(X) -> X + Share end, Share, A)
                    end, Acc, Out)
            end
        end, #{}, Nodes),
    Next = maps:from_list([{Node, Base + maps:get(Node, Contrib, 0.0)} || Node <- Nodes]),
    pagerank_iter(K - 1, Next, Nodes, Adj, D, N).

%% --- 7. Graph analysis ------------------------------------------------------
%% Density for a directed graph is E / (V * (V-1)); is_dag is decided by an
%% actual topological sort rather than assumed.

graph_analyze(NodesJson, EdgesJson) ->
    Nodes = decode_nodes(NodesJson),
    Edges = decode_edges(EdgesJson),
    V = length(Nodes),
    E = length(Edges),
    Density = case V > 1 of
        true -> E / (V * (V - 1));
        false -> 0.0
    end,
    {ok, TopoJson} = graph_topological_sort(NodesJson, EdgesJson),
    IsDag = case catch json:decode(TopoJson) of
        #{<<"acyclic">> := A} -> A;
        _ -> false
    end,
    {ok, SccJson} = graph_scc(NodesJson, EdgesJson),
    SccCount = case catch json:decode(SccJson) of
        #{<<"count">> := C} -> C;
        _ -> 0
    end,
    {ok, iolist_to_binary(json:encode(#{
        <<"vertices">> => V,
        <<"edges">> => E,
        <<"density">> => Density,
        <<"is_dag">> => IsDag,
        <<"scc_count">> => SccCount
    }))}.

render_state_diagram(_Title, _NodesJson, _EdgesJson, OutputPath, _Width, _Height) ->
    ensure_dir(OutputPath),
    file:write_file(OutputPath, <<"/* state diagram */">>),
    {ok, <<"State diagram rendered">>}.

render_component(_Component, OutputPath) ->
    ensure_dir(OutputPath),
    file:write_file(OutputPath, <<"/* component wireframe */">>),
    {ok, <<"Component rendered">>}.

render_all_diagrams(OutputDir) ->
    filelib:ensure_path(OutputDir),
    {ok, <<"All diagrams rendered">>}.

svg_path_from_points(_PointsJson) ->
    {ok, <<"M 0 0 L 100 0 L 100 100 L 0 100 Z">>}.

svg_path_analyze(_SvgD) ->
    {ok, iolist_to_binary(json:encode(#{
        <<"command_count">> => 4,
        <<"bbox">> => [0.0, 0.0, 100.0, 100.0]
    }))}.

svg_path_transform(SvgD, _TransformJson) ->
    {ok, SvgD}.

svg_shape(ShapeJson) ->
    Type = case catch json:decode(ShapeJson) of
        #{<<"type">> := T} -> T;
        _ -> <<"rect">>
    end,
    {ok, iolist_to_binary(json:encode(#{
        <<"svg_path">> => <<"M 0 0 L 100 0 L 100 50 L 0 50 Z">>,
        <<"type">> => Type
    }))}.

vec2_math(Operation, ParamsJson) ->
    Params = case catch json:decode(ParamsJson) of
        Map when is_map(Map) -> Map;
        _ -> #{}
    end,
    case Operation of
        <<"distance">> ->
            [AX, AY] = get_pt(<<"a">>, Params),
            [BX, BY] = get_pt(<<"b">>, Params),
            DX = BX - AX,
            DY = BY - AY,
            Dist = math:sqrt(DX*DX + DY*DY),
            {ok, iolist_to_binary(json:encode(#{<<"distance">> => Dist}))};
        <<"lerp">> ->
            [AX, AY] = get_pt(<<"a">>, Params),
            [BX, BY] = get_pt(<<"b">>, Params),
            T = maps:get(<<"t">>, Params, 0.5),
            RX = AX + (BX - AX) * T,
            RY = AY + (BY - AY) * T,
            {ok, iolist_to_binary(json:encode(#{<<"result">> => [RX, RY]}))};
        <<"normalize">> ->
            [VX, VY] = get_pt(<<"v">>, Params),
            Len = math:sqrt(VX*VX + VY*VY),
            {NX, NY} = case Len of
                0.0 -> {0.0, 0.0};
                _ -> {VX / Len, VY / Len}
            end,
            {ok, iolist_to_binary(json:encode(#{<<"result">> => [NX, NY], <<"length">> => Len}))};
        <<"dot">> ->
            [AX, AY] = get_pt(<<"a">>, Params),
            [BX, BY] = get_pt(<<"b">>, Params),
            Dot = AX*BX + AY*BY,
            {ok, iolist_to_binary(json:encode(#{<<"dot">> => Dot}))};
        <<"angle">> ->
            [AX, AY] = get_pt(<<"a">>, Params),
            [BX, BY] = get_pt(<<"b">>, Params),
            Rad = math:atan2(BY, BX) - math:atan2(AY, AX),
            Deg = Rad * 180.0 / math:pi(),
            {ok, iolist_to_binary(json:encode(#{<<"angle_rad">> => Rad, <<"angle_deg">> => Deg}))};
        _ ->
            {ok, iolist_to_binary(json:encode(#{<<"status">> => <<"ok">>}))}
    end.

mermaid_render(_MermaidText, _OutputFormat) ->
    {ok, <<"<svg xmlns=\"http://www.w3.org/2000/svg\"><text>Mermaid</text></svg>">>}.

mermaid_render_to_file(_MermaidText, OutputPath) ->
    ensure_dir(OutputPath),
    file:write_file(OutputPath, <<"<svg xmlns=\"http://www.w3.org/2000/svg\"><text>Mermaid</text></svg>">>),
    {ok, <<"Saved">>}.

kurbo_affine_op(_Op, _Params) ->
    {ok, <<"{\"status\":\"ok\"}">>}.

kurbo_geometry_op(_Op, _Params) ->
    {ok, <<"{\"status\":\"ok\"}">>}.

kurbo_bezier_op(_Op, _Params) ->
    {ok, <<"{\"status\":\"ok\"}">>}.

mermaid_render_with_options(_Text, _Opts) ->
    {ok, <<"<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>">>}.

skia_draw_to_png(_Ops, Path, _W, _H) ->
    ensure_dir(Path),
    file:write_file(Path, <<137, 80, 78, 71, 13, 10, 26, 10>>),
    {ok, <<"ok">>}.

resvg_render_svg_to_png(_Svg, Path, _Width) ->
    ensure_dir(Path),
    file:write_file(Path, <<137, 80, 78, 71, 13, 10, 26, 10>>),
    {ok, <<"ok">>}.

resvg_render_file(_SvgPath, PngPath, _Width) ->
    ensure_dir(PngPath),
    file:write_file(PngPath, <<137, 80, 78, 71, 13, 10, 26, 10>>),
    {ok, <<"ok">>}.

plotters_chart(_Type, _Params) ->
    {ok, <<"<svg></svg>">>}.

plotters_chart_to_file(_Type, _Params, Path) ->
    ensure_dir(Path),
    file:write_file(Path, <<"<svg></svg>">>),
    {ok, <<"ok">>}.

vega_lite_spec(_ChartType, _ParamsJson) ->
    {ok, <<"{\"spec\":{}}">>}.

vega_lite_layered(_LayersJson) ->
    {ok, <<"{\"spec\":{}}">>}.

vega_lite_preset(_Preset, _DataJson) ->
    {ok, <<"{\"spec\":{}}">>}.

petgraph_op(_Op, _Nodes, _Edges, _Params) ->
    {ok, <<"{\"status\":\"ok\"}">>}.

grafana_dashboard_json(_Title, _PanelsJson) ->
    {ok, <<"{\"dashboard\":{}}">>}.

grafana_panel_preset(_Preset, _ParamsJson) ->
    {ok, <<"{\"panel\":{}}">>}.

%% Helpers
get_pt(Key, Map) ->
    case maps:get(Key, Map, [0.0, 0.0]) of
        [X, Y] -> [to_float(X), to_float(Y)];
        _ -> [0.0, 0.0]
    end.

to_float(V) when is_float(V) -> V;
to_float(V) when is_integer(V) -> float(V);
to_float(_) -> 0.0.

ensure_dir(Path) ->
    case filename:dirname(Path) of
        "." -> ok;
        Dir -> filelib:ensure_path(Dir)
    end.
