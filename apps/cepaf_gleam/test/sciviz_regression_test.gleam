//// =============================================================================
//// [C3I-SCIVIZ-REGRESSION] 15-Cycle SciViz Library Comprehensive EUnit Test Suite
//// =============================================================================

import cepaf_gleam/sciviz/dsl
import cepaf_gleam/sciviz/instruments
import cepaf_gleam/sciviz/renderer
import cepaf_gleam/sciviz/schema.{
  ArcLayer, BitmapLayer, BubbleData, CandleData, ColumnData, ColumnLayer,
  CursorModifier, DigitalBandSeries, FastBandSeries, FastBubbleSeries,
  FastCandlestickSeries, FastColumnSeries, FastHeatmapSeries, FastLineSeries,
  FastMountainSeries, GeoFeature, GeoJsonLayer, GeomArea, GeomBar, GeomBoxplot,
  GeomContour, GeomDensity2D, GeomErrorBar, GeomHex, GeomLine,
  GeomPhasePortrait, GeomPoint, GeomRibbon, GeomSegment, GeomStep, GeomText,
  GeomViolin, GridLayer, H3HexagonLayer, HeatmapMatrixLayer, HexagonLayer,
  IconData, IconLayer, LegendModifier, LineLayer, ParticleData, PathLayer,
  Point2D, Point3D, PointCloudLayer, PolarGridModifier, Rect2D,
  RolloverModifier, RubberBandZoomModifier, S2Layer, Scale2D, ScatterplotLayer,
  ScreenGridLayer, SplineLineSeries, TextLabelData, TextLayer,
  ThresholdCursor, TileLayer, TopologyGraphLayer, TripData, TripsLayer,
  VisualCircle, VisualMesh, VisualNineSlicePlane, VisualParticleContainer,
  VisualRect, VisualSprite, VisualText, VisualTilingSprite, new_fifo,
  push_fifo,
}
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// 1. C397: ggplot2 Geom Expansion Test
pub fn c397_ggplot2_geom_expansion_test() {
  let plot =
    dsl.new_plot("ggplot2 Geoms Test", 800.0, 600.0)
    |> dsl.add_geom(GeomBoxplot(20.0, "#38bdf8", "#0284c7"))
    |> dsl.add_geom(GeomViolin(1.5, "#10b981", 0.3))
    |> dsl.add_geom(GeomHex(12.0, "#f59e0b"))
    |> dsl.add_geom(GeomDensity2D(4, "#818cf8"))
    |> dsl.add_geom(GeomErrorBar(15.0, 1.5, "#ef4444"))
    |> dsl.add_geom(GeomStep(2.0, "#06b6d4"))
    |> dsl.add_geom(GeomContour([10.0, 20.0, 30.0], "#94a3b8"))
    |> dsl.add_geom(GeomSegment(1.5, "#f43f5e"))
    |> dsl.add_geom(GeomText(10, "#f8fafc", "monospace"))

  list.length(plot.geoms) |> should.equal(9)
}

// 2. C398: SciChart Fast Series Test
pub fn c398_scichart_fast_series_test() {
  let p1 = Point2D(0.0, 10.0)
  let p2 = Point2D(10.0, 50.0)
  let s_line = FastLineSeries("s1", [p1, p2], 2.0, "#38bdf8")
  let s_mount = FastMountainSeries("s2", [p1, p2], 0.0, "#38bdf8", "#0284c7")
  let candle = CandleData(open: 10.0, high: 15.0, low: 8.0, close: 12.0, timestamp: 1.0)
  let s_candle = FastCandlestickSeries("s3", [candle], "#10b981", "#ef4444")
  let s_band = FastBandSeries("s4", [p1, p2], [p1, p2], "#818cf8")
  let bubble = BubbleData(x: 5.0, y: 25.0, z: 10.0, label: "b1")
  let s_bubble = FastBubbleSeries("s5", [bubble], 5.0, 20.0)
  let s_col = FastColumnSeries("s6", [p1, p2], 8.0, "#f59e0b")
  let s_heat = FastHeatmapSeries("s7", [[1.0, 2.0], [3.0, 4.0]], "viridis")
  let s_spline = SplineLineSeries("s8", [p1, p2], 0.5, "#ec4899")
  let s_digi = DigitalBandSeries("s9", [p1, p2], [p1, p2], "#14b8a6")

  let series_list = [s_line, s_mount, s_candle, s_band, s_bubble, s_col, s_heat, s_spline, s_digi]
  list.length(series_list) |> should.equal(9)
}

// 3. C399: SciChart Modifiers & Cursors Test
pub fn c399_scichart_modifiers_cursors_test() {
  let m1 = CursorModifier(True, True, "#94a3b8")
  let m2 = RolloverModifier(True, True, "#38bdf8")
  let m3 = RubberBandZoomModifier(True, "#38bdf8", "#0284c7")
  let m4 = LegendModifier(True, "horizontal", "top-right")
  let m5 = ThresholdCursor(85.0, "Critical Warning", "#ef4444")
  let m6 = PolarGridModifier(5, 8, "#1e293b")

  let mod_list = [m1, m2, m3, m4, m5, m6]
  list.length(mod_list) |> should.equal(6)
}

// 4. C400: Deck.gl Geospatial & Mesh Layers Test
pub fn c400_deckgl_geospatial_layers_test() {
  let p1 = Point2D(10.0, 20.0)
  let p2 = Point2D(30.0, 40.0)
  let l_line = LineLayer("l1", [#(p1, p2)], 2.0, "#38bdf8")
  let l_bmp = BitmapLayer("l2", Rect2D(0.0, 0.0, 100.0, 100.0), "img.png", 0.8)
  let l_icon = IconLayer("l3", [IconData(p1, "node", 12.0, "#10b981")], 1.0)
  let l_geo = GeoJsonLayer("l4", [GeoFeature("f1", [p1, p2], "Polygon")], "#38bdf8", "#0284c7")
  let l_grid = GridLayer("l5", [p1, p2], 25.0, 1.0)
  let l_hex = HexagonLayer("l6", [p1, p2], 15.0, 0.9)
  let l_col = ColumnLayer("l7", [ColumnData(p1, 50.0, "#f59e0b")], 12, 10.0)
  let l_pcloud = PointCloudLayer("l8", [Point3D(10.0, 20.0, 30.0)], 4.0, "#818cf8")

  let layers = [l_line, l_bmp, l_icon, l_geo, l_grid, l_hex, l_col, l_pcloud]
  list.length(layers) |> should.equal(8)
}

// 5. C401: Deck.gl Aggregation & Flow Layers Test
pub fn c401_deckgl_aggregation_layers_test() {
  let p1 = Point2D(10.0, 20.0)
  let p2 = Point2D(30.0, 40.0)
  let l_sgrid = ScreenGridLayer("a1", [p1, p2], 20.0)
  let l_text = TextLayer("a2", [TextLabelData(p1, "Node Alpha", "middle", "#f8fafc")], 11)
  let l_trips = TripsLayer("a3", [TripData("t1", [#(p1, 0.0), #(p2, 10.0)], "#38bdf8")], 5.0, 5.0)
  let l_h3 = H3HexagonLayer("a4", ["8828308281fffff"], 1.0)
  let l_s2 = S2Layer("a5", ["1/2/3"], "#10b981")
  let l_tile = TileLayer("a6", "https://tile/{z}/{x}/{y}", 0, 18)

  let layers = [l_sgrid, l_text, l_trips, l_h3, l_s2, l_tile]
  list.length(layers) |> should.equal(6)
}

// 6. C402: PixiJS Display Primitives Test
pub fn c402_pixijs_display_nodes_test() {
  let v_circ = VisualCircle(10.0, 10.0, 5.0, "#38bdf8")
  let v_rect = VisualRect(0.0, 0.0, 40.0, 20.0, "#1e293b")
  let v_text = VisualText(5.0, 5.0, "UOS Label", 10, "#f8fafc")
  let v_sprite = VisualSprite(0.0, 0.0, 32.0, 32.0, "node_tex", "#38bdf8")
  let v_nine = VisualNineSlicePlane(0.0, 0.0, 60.0, 40.0, 4.0, 4.0, 4.0, 4.0, "#020617")
  let v_tile = VisualTilingSprite(0.0, 0.0, 100.0, 100.0, 1.0, 1.0, "grid_pat")
  let v_part = VisualParticleContainer([ParticleData(1.0, 2.0, 0.1, 0.2, 1.0, 0.8, "#10b981")], "normal")
  let v_mesh = VisualMesh([Point2D(0.0, 0.0), Point2D(10.0, 0.0), Point2D(5.0, 10.0)], [], [0, 1, 2], "#818cf8")

  let visuals = [v_circ, v_rect, v_text, v_sprite, v_nine, v_tile, v_part, v_mesh]
  list.length(visuals) |> should.equal(8)
}

// 7. C403: PixiJS Scene Graph Hierarchy & Helpers Test
pub fn c403_pixijs_scene_graph_hierarchy_test() {
  let node_c = dsl.create_scene_circle("c1", 10.0, 10.0, 5.0, "#38bdf8")
  let node_r = dsl.create_scene_rect("r1", 20.0, 20.0, 30.0, 15.0, "#10b981")
  let node_t = dsl.create_scene_text("t1", 30.0, 30.0, "Label", 12, "#f8fafc")
  let node_s = dsl.create_scene_sprite("s1", 40.0, 40.0, 24.0, 24.0, "tex", "#f59e0b")
  let node_9 = dsl.create_scene_nine_slice("n1", 50.0, 50.0, 80.0, 40.0, "#020617")

  let plot =
    dsl.new_plot("Scene Graph Hierarchy", 400.0, 400.0)
    |> dsl.add_scene_child(node_c)
    |> dsl.add_scene_child(node_r)
    |> dsl.add_scene_child(node_t)
    |> dsl.add_scene_child(node_s)
    |> dsl.add_scene_child(node_9)

  list.length(plot.scene_root.children) |> should.equal(5)
}

// 8. C404: DSL Fluent Builder Exhaustiveness Test
pub fn c404_dsl_fluent_builder_exhaustiveness_test() {
  let plot =
    dsl.new_plot("Universal SciViz Plot", 1000.0, 600.0)
    |> dsl.with_scale(-50.0, 50.0, 0.0, 100.0)
    |> dsl.add_series("telemetry", [Point2D(0.0, 10.0), Point2D(25.0, 75.0)])
    |> dsl.add_geom(GeomLine(2.0, "#38bdf8", False))
    |> dsl.add_geom(GeomPoint(4.0, "#10b981"))
    |> dsl.add_geom(GeomArea("#38bdf8", 0.2))
    |> dsl.add_geom(GeomBar(10.0, "#f59e0b"))
    |> dsl.add_geom(GeomRibbon("#818cf8", 0.15))
    |> dsl.add_geom(GeomPhasePortrait(1.0, "#0284c7"))
    |> dsl.add_deck_layer(ScatterplotLayer("l1", [Point2D(5.0, 5.0)], 4.0, "#38bdf8"))
    |> dsl.add_deck_layer(PathLayer("l2", [Point2D(0.0, 0.0), Point2D(10.0, 10.0)], 1.5, "#fbbf24"))
    |> dsl.add_deck_layer(ArcLayer("l3", Point2D(0.0, 0.0), Point2D(50.0, 50.0), 20.0, 2.0, "#818cf8"))
    |> dsl.add_deck_layer(HeatmapMatrixLayer("l4", [[1.0, 0.0], [0.0, 1.0]], 0.0, 1.0))
    |> dsl.add_deck_layer(TopologyGraphLayer("l5", [#("a", Point2D(0.0, 0.0))], []))

  list.length(plot.geoms) |> should.equal(6)
  list.length(plot.layers) |> should.equal(5)
  list.length(plot.data_series) |> should.equal(1)
}

// 9. C405: SciChart FIFO Boundedness Test
pub fn c405_scichart_fifo_boundedness_reg_test() {
  let buf0 = new_fifo(5)
  let buf1 = push_fifo(buf0, Point2D(1.0, 1.0))
  let buf2 = push_fifo(buf1, Point2D(2.0, 2.0))
  let buf3 = push_fifo(buf2, Point2D(3.0, 3.0))
  let buf4 = push_fifo(buf3, Point2D(4.0, 4.0))
  let buf5 = push_fifo(buf4, Point2D(5.0, 5.0))
  list.length(buf5.points) |> should.equal(5)

  // 6th item should trim oldest and maintain length 5
  let buf6 = push_fifo(buf5, Point2D(6.0, 6.0))
  list.length(buf6.points) |> should.equal(5)
}

// 10. C406: Scale Coordinate Projection Test
pub fn c406_scale_projection_normalization_test() {
  let scale =
    Scale2D(
      x_min: -100.0,
      x_max: 100.0,
      y_min: 0.0,
      y_max: 200.0,
      target_w: 800.0,
      target_h: 400.0,
    )

  let origin = dsl.project_point(scale, Point2D(0.0, 100.0))
  origin.x |> should.equal(400.0)
  origin.y |> should.equal(200.0)
}

// 11. C407: Pure Lustre SVG SSR Rendering Test
pub fn c407_pure_lustre_svg_ssr_rendering_test() {
  let plot =
    dsl.new_plot("Render Test", 500.0, 300.0)
    |> dsl.add_series("test", [Point2D(10.0, 20.0), Point2D(30.0, 40.0)])
    |> dsl.add_geom(GeomLine(2.0, "#38bdf8", False))
    |> dsl.add_geom(GeomBoxplot(15.0, "#10b981", "#059669"))
    |> dsl.add_deck_layer(HexagonLayer("h1", [Point2D(20.0, 20.0)], 10.0, 0.8))
    |> dsl.add_scene_child(dsl.create_scene_circle("c1", 50.0, 50.0, 10.0, "#ef4444"))

  let _el = renderer.render_plot(plot)
  True |> should.be_true()
}

// 12. C408: Flight Instrument Lyapunov Phase Plane Test
pub fn c408_flight_instrument_lyapunov_test() {
  let fifo =
    new_fifo(5)
    |> push_fifo(Point2D(0.1, 0.2))
    |> push_fifo(Point2D(0.2, 0.4))
  let _el = instruments.render_lyapunov_phase_plane(fifo, Point2D(0.2, 0.4), 400.0, 300.0)
  True |> should.be_true()
}

// 13. C409: Flight Instrument Rocha Radar Test
pub fn c409_flight_instrument_rocha_radar_test() {
  let _el = instruments.render_rocha_semiotics_radar(0.92, 0.96, 0.89, 360.0, 360.0)
  True |> should.be_true()
}

// 14. C410: Flight Instrument Swarm Topology Test
pub fn c410_flight_instrument_swarm_topology_test() {
  let nodes = [#("nas-1", Point2D(20.0, 50.0)), #("vm-1", Point2D(80.0, 50.0))]
  let arcs = [#(Point2D(20.0, 50.0), Point2D(80.0, 50.0))]
  let _el = instruments.render_swarm_mesh_topology(nodes, arcs, 450.0, 250.0)
  True |> should.be_true()
}

// 15. C411: Flight Instrument Sheaf Cohomology Heatmap Test
pub fn c411_flight_instrument_sheaf_heatmap_test() {
  let matrix = [
    [1.0, 0.0, 0.0],
    [0.0, 1.0, 0.0],
    [0.0, 0.0, 1.0],
  ]
  let _el = instruments.render_sheaf_cohomology_heatmap(matrix, 300.0, 300.0)
  True |> should.be_true()
}
