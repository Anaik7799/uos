-module(graphene_nif).
-export([graph_bfs/3, graph_dfs/3, graph_topological_sort/2, graph_scc/2,
         graph_shortest_path/4, graph_pagerank/4, graph_analyze/2,
         render_state_diagram/6, render_component/2, render_all_diagrams/1,
         svg_path_from_points/1, svg_path_analyze/1, svg_path_transform/2,
         svg_shape/1, vec2_math/2,
         ecs_spawn/1, ecs_query_all/0, ecs_clear/0,
         bevy_math_op/2, bevy_color_convert/2,
         mermaid_render/2, mermaid_render_to_file/2,
         kurbo_affine_op/2, kurbo_geometry_op/2, kurbo_bezier_op/2,
         mermaid_render_with_options/2, skia_draw_to_png/4,
         resvg_render_svg_to_png/3, resvg_render_file/3, plotters_chart/2, plotters_chart_to_file/3,
         vega_lite_spec/2, vega_lite_layered/1, vega_lite_preset/2,
         petgraph_op/4, grafana_dashboard_json/2, grafana_panel_preset/2]).
-on_load(init/0).

init() ->
    SoPath = case code:priv_dir(cepaf_gleam) of
        {error, _} -> "priv/graphene_nif";
        PrivDir -> filename:join(PrivDir, "graphene_nif")
    end,
    case erlang:load_nif(SoPath, 0) of
        ok -> ok;
        {error, {reload, _}} -> ok;
        {error, Reason} ->
            io:format("[graphene_nif] NIF load failed: ~p (path: ~s)~n", [Reason, SoPath]),
            ok
    end.

graph_bfs(_N, _E, _S) -> {error, <<"NIF not loaded">>}.
graph_dfs(_N, _E, _S) -> {error, <<"NIF not loaded">>}.
graph_topological_sort(_N, _E) -> {error, <<"NIF not loaded">>}.
graph_scc(_N, _E) -> {error, <<"NIF not loaded">>}.
graph_shortest_path(_N, _E, _F, _T) -> {error, <<"NIF not loaded">>}.
graph_pagerank(_N, _E, _D, _I) -> {error, <<"NIF not loaded">>}.
graph_analyze(_N, _E) -> {error, <<"NIF not loaded">>}.
render_state_diagram(_Title, _NodesJson, _EdgesJson, _OutputPath, _Width, _Height) -> {error, <<"NIF not loaded">>}.
render_component(_Component, _OutputPath) -> {error, <<"NIF not loaded">>}.
render_all_diagrams(_OutputDir) -> {error, <<"NIF not loaded">>}.
svg_path_from_points(_PointsJson) -> {error, <<"NIF not loaded">>}.
svg_path_analyze(_SvgD) -> {error, <<"NIF not loaded">>}.
svg_path_transform(_SvgD, _TransformJson) -> {error, <<"NIF not loaded">>}.
svg_shape(_ShapeJson) -> {error, <<"NIF not loaded">>}.
vec2_math(_Operation, _ParamsJson) -> {error, <<"NIF not loaded">>}.
ecs_spawn(_ComponentsJson) -> {error, <<"NIF not loaded">>}.
ecs_query_all() -> {error, <<"NIF not loaded">>}.
ecs_clear() -> {error, <<"NIF not loaded">>}.
bevy_math_op(_Operation, _ParamsJson) -> {error, <<"NIF not loaded">>}.
bevy_color_convert(_Operation, _ParamsJson) -> {error, <<"NIF not loaded">>}.
mermaid_render(_MermaidText, _OutputFormat) -> {error, <<"NIF not loaded">>}.
mermaid_render_to_file(_MermaidText, _OutputPath) -> {error, <<"NIF not loaded">>}.
kurbo_affine_op(_Op, _Params) -> {error, <<"NIF not loaded">>}.
kurbo_geometry_op(_Op, _Params) -> {error, <<"NIF not loaded">>}.
kurbo_bezier_op(_Op, _Params) -> {error, <<"NIF not loaded">>}.
mermaid_render_with_options(_Text, _Opts) -> {error, <<"NIF not loaded">>}.
skia_draw_to_png(_Ops, _Path, _W, _H) -> {error, <<"NIF not loaded">>}.
vega_lite_spec(_ChartType, _ParamsJson) -> {error, <<"NIF not loaded">>}.
vega_lite_layered(_LayersJson) -> {error, <<"NIF not loaded">>}.
vega_lite_preset(_Preset, _DataJson) -> {error, <<"NIF not loaded">>}.
petgraph_op(_Op, _Nodes, _Edges, _Params) -> {error, <<"NIF not loaded">>}.
grafana_dashboard_json(_Title, _PanelsJson) -> {error, <<"NIF not loaded">>}.
grafana_panel_preset(_Preset, _ParamsJson) -> {error, <<"NIF not loaded">>}.
resvg_render_svg_to_png(_Svg, _Path, _Width) -> {error, <<"NIF not loaded">>}.
resvg_render_file(_SvgPath, _PngPath, _Width) -> {error, <<"NIF not loaded">>}.
plotters_chart(_Type, _Params) -> {error, <<"NIF not loaded">>}.
plotters_chart_to_file(_Type, _Params, _Path) -> {error, <<"NIF not loaded">>}.
do_resvg_render(_Svg, _Path, _Width) -> {error, <<"NIF not loaded">>}.
do_plotters_chart(_Type, _Params) -> {error, <<"NIF not loaded">>}.
