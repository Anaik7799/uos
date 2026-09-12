//// =============================================================================
//// [C3I-SCIVIZ-TEST] SciViz Scientific Visualization Library EUnit Test Suite
//// =============================================================================

import cepaf_gleam/sciviz/dsl
import cepaf_gleam/sciviz/instruments
import cepaf_gleam/sciviz/renderer
import cepaf_gleam/sciviz/schema.{
  ArcLayer, GeomArea, GeomLine, GeomPhasePortrait, GeomPoint,
  HeatmapMatrixLayer, PathLayer, Point2D, Scale2D, ScatterplotLayer,
  SceneNode, TopologyGraphLayer, VisualCircle, VisualRect, VisualText,
  new_fifo, push_fifo,
}
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn scichart_fifo_boundedness_test() {
  // Test capacity 3 FIFO
  let fifo0 = new_fifo(3)
  list.length(fifo0.points) |> should.equal(0)
  fifo0.capacity |> should.equal(3)

  let fifo1 = push_fifo(fifo0, Point2D(1.0, 10.0))
  list.length(fifo1.points) |> should.equal(1)

  let fifo2 = push_fifo(fifo1, Point2D(2.0, 20.0))
  list.length(fifo2.points) |> should.equal(2)

  let fifo3 = push_fifo(fifo2, Point2D(3.0, 30.0))
  list.length(fifo3.points) |> should.equal(3)

  // Exceed capacity: should stay at 3 and newest point is head
  let fifo4 = push_fifo(fifo3, Point2D(4.0, 40.0))
  list.length(fifo4.points) |> should.equal(3)

  case fifo4.points {
    [head, ..] -> {
      head.x |> should.equal(4.0)
      head.y |> should.equal(40.0)
    }
    _ -> should.fail()
  }
}

pub fn dsl_scale_and_projection_test() {
  let scale =
    Scale2D(
      x_min: 0.0,
      x_max: 100.0,
      y_min: 0.0,
      y_max: 50.0,
      target_w: 1000.0,
      target_h: 500.0,
    )

  // Origin (0, 0) should map to bottom-left screen (0, 500)
  let p_origin = dsl.project_point(scale, Point2D(0.0, 0.0))
  p_origin.x |> should.equal(0.0)
  p_origin.y |> should.equal(500.0)

  // Max (100, 50) should map to top-right screen (1000, 0)
  let p_max = dsl.project_point(scale, Point2D(100.0, 50.0))
  p_max.x |> should.equal(1000.0)
  p_max.y |> should.equal(0.0)

  // Midpoint (50, 25) should map to center screen (500, 250)
  let p_mid = dsl.project_point(scale, Point2D(50.0, 25.0))
  p_mid.x |> should.equal(500.0)
  p_mid.y |> should.equal(250.0)
}

pub fn dsl_fluent_plot_builder_test() {
  let plot =
    dsl.new_plot("Telemetry Mesh Monitor", 800.0, 400.0)
    |> dsl.with_scale(0.0, 10.0, 0.0, 100.0)
    |> dsl.add_series("vibration", [Point2D(0.0, 5.0), Point2D(10.0, 95.0)])
    |> dsl.add_geom(GeomLine(2.0, "#38bdf8", False))
    |> dsl.add_geom(GeomPoint(4.0, "#10b981"))
    |> dsl.add_geom(GeomArea("#38bdf8", 0.2))
    |> dsl.add_geom(GeomPhasePortrait(3.0, "#ef4444"))

  plot.title |> should.equal("Telemetry Mesh Monitor")
  plot.width |> should.equal(800.0)
  plot.height |> should.equal(400.0)
  list.length(plot.data_series) |> should.equal(1)
  list.length(plot.geoms) |> should.equal(4)
}

pub fn deck_gl_and_pixi_scene_graph_test() {
  let p1 = Point2D(10.0, 10.0)
  let p2 = Point2D(20.0, 30.0)

  let node_circle =
    SceneNode(
      id: "c1",
      translate: Point2D(50.0, 50.0),
      rotate_deg: 0.0,
      scale: 1.0,
      visual: VisualCircle(0.0, 0.0, 15.0, "#22c55e"),
      children: [],
    )
  let node_rect =
    SceneNode(
      id: "r1",
      translate: Point2D(100.0, 100.0),
      rotate_deg: 0.0,
      scale: 1.0,
      visual: VisualRect(0.0, 0.0, 40.0, 20.0, "#a855f7"),
      children: [],
    )
  let node_text =
    SceneNode(
      id: "t1",
      translate: Point2D(150.0, 150.0),
      rotate_deg: 0.0,
      scale: 1.0,
      visual: VisualText(0.0, 0.0, "UOS Node", 12, "#f8fafc"),
      children: [],
    )

  let plot =
    dsl.new_plot("Integrated Composite Display", 600.0, 400.0)
    |> dsl.add_deck_layer(ScatterplotLayer("scatter-1", [p1, p2], 5.0, "#38bdf8"))
    |> dsl.add_deck_layer(PathLayer("path-1", [p1, p2], 2.0, "#fbbf24"))
    |> dsl.add_deck_layer(ArcLayer("arc-1", p1, p2, 25.0, 2.0, "#818cf8"))
    |> dsl.add_deck_layer(
      HeatmapMatrixLayer("heat-1", [[1.0, 0.5], [0.2, 0.9]], 0.0, 1.0),
    )
    |> dsl.add_deck_layer(
      TopologyGraphLayer(
        "topo-1",
        [#("nas-1", p1), #("vm-1", p2)],
        [#(0, 1)],
      ),
    )
    |> dsl.add_scene_child(node_circle)
    |> dsl.add_scene_child(node_rect)
    |> dsl.add_scene_child(node_text)

  list.length(plot.layers) |> should.equal(5)
  list.length(plot.scene_root.children) |> should.equal(3)

  // Verify pure Lustre SVG render output without panic
  let _el = renderer.render_plot(plot)
  True |> should.be_true()
}

pub fn flight_instruments_render_test() {
  let fifo =
    new_fifo(10)
    |> push_fifo(Point2D(0.1, 0.2))
    |> push_fifo(Point2D(0.3, 0.5))
    |> push_fifo(Point2D(0.4, 0.7))

  let current = Point2D(0.4, 0.7)

  // 1. Lyapunov Phase Plane
  let _lyapunov_el =
    instruments.render_lyapunov_phase_plane(fifo, current, 400.0, 300.0)

  // 2. Rocha Semiotics Radar
  let _rocha_el =
    instruments.render_rocha_semiotics_radar(0.9, 0.95, 0.88, 350.0, 350.0)

  // 3. Swarm Mesh Topology
  let _swarm_el =
    instruments.render_swarm_mesh_topology(
      [#("nas-1", Point2D(50.0, 100.0)), #("vm-1", Point2D(200.0, 100.0))],
      [#(Point2D(50.0, 100.0), Point2D(200.0, 100.0))],
      400.0,
      250.0,
    )

  // 4. Sheaf Cohomology Heatmap
  let _sheaf_el =
    instruments.render_sheaf_cohomology_heatmap(
      [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]],
      300.0,
      300.0,
    )

  True |> should.be_true()
}
