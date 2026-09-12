// instruments.gleam — Pre-Built Scientific Cybernetic Flight Instruments
// Composes Grammar of Graphics, SciChart buffers, deck.gl layers, and PixiJS
// scene graphs into production control center flight instruments across all
// 10 fractal layers (L0..L9) and cross-cutting aspects.

import cepaf_gleam/sciviz/dsl
import cepaf_gleam/sciviz/renderer
import cepaf_gleam/sciviz/schema.{
  type Point2D, type SciChartFifoBuffer, type SciVizPlot, ArcLayer, GeomArea,
  GeomLine, GeomPhasePortrait, HeatmapMatrixLayer, PathLayer, Point2D,
  ScatterplotLayer, TopologyGraphLayer,
}
import gleam/int
import gleam/list
import lustre/element.{type Element}

@external(erlang, "math", "sin")
fn erlang_sin(x: Float) -> Float

@external(erlang, "math", "cos")
fn erlang_cos(x: Float) -> Float

pub fn render_lyapunov_phase_plane(
  fifo: SciChartFifoBuffer,
  current_state: Point2D,
  width: Float,
  height: Float,
) -> Element(msg) {
  let plot =
    dsl.new_plot("LYAPUNOV PHASE-SPACE TRAJECTORY (x, x_dot)", width, height)
    |> dsl.with_scale(-2.0, 2.0, -2.0, 2.0)
    |> dsl.add_series("history", fifo.points)
    |> dsl.add_geom(GeomLine(stroke_width: 1.5, color: "#38bdf8", dashed: False))
    |> dsl.add_geom(GeomPhasePortrait(vector_scale: 0.8, color: "#0284c7"))
    |> dsl.add_deck_layer(
      ScatterplotLayer(
        id: "current_state",
        points: [current_state],
        radius: 6.0,
        color: "#10b981",
      ),
    )
  renderer.render_plot(plot)
}

pub fn render_rocha_semiotics_radar(
  syntax: Float,
  semantics: Float,
  pragmatics: Float,
  width: Float,
  height: Float,
) -> Element(msg) {
  let p_syntax = Point2D(50.0, 90.0 *. syntax)
  let p_semantics = Point2D(20.0, 40.0 *. semantics)
  let p_pragmatics = Point2D(80.0, 40.0 *. pragmatics)

  let plot =
    dsl.new_plot("ROCHA BIOSEMIOTIC TRIAD (PEIRCE COHERENCE)", width, height)
    |> dsl.with_scale(0.0, 100.0, 0.0, 100.0)
    |> dsl.add_deck_layer(
      TopologyGraphLayer(
        id: "peirce_triangle",
        nodes: [
          #("Syntax", p_syntax),
          #("Semantics", p_semantics),
          #("Pragmatics", p_pragmatics),
        ],
        edges: [#(0, 1), #(1, 2), #(2, 0)],
      ),
    )
  renderer.render_plot(plot)
}

pub fn render_swarm_mesh_topology(
  nodes: List(#(String, Point2D)),
  active_arcs: List(#(Point2D, Point2D)),
  width: Float,
  height: Float,
) -> Element(msg) {
  let initial_plot =
    dsl.new_plot("SWARM MESH TOPOLOGY & ERGODIC ROUTING (SCC=1)", width, height)
    |> dsl.with_scale(0.0, 100.0, 0.0, 100.0)
    |> dsl.add_deck_layer(
      TopologyGraphLayer(
        id: "cluster_nodes",
        nodes: nodes,
        edges: [#(0, 1), #(1, 2), #(2, 0)],
      ),
    )

  let final_plot =
    active_arcs
    |> dsl_append_arcs(initial_plot, 0)

  renderer.render_plot(final_plot)
}

fn dsl_append_arcs(
  arcs: List(#(Point2D, Point2D)),
  plot: SciVizPlot,
  idx: Int,
) -> SciVizPlot {
  case arcs {
    [] -> plot
    [arc, ..rest] -> {
      let layer =
        ArcLayer(
          id: "arc_" <> idx_to_string(idx),
          source: arc.0,
          target: arc.1,
          tilt: 25.0,
          stroke_width: 2.0,
          color: "#f59e0b",
        )
      dsl_append_arcs(rest, dsl.add_deck_layer(plot, layer), idx + 1)
    }
  }
}

fn idx_to_string(idx: Int) -> String {
  case idx {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    _ -> "n"
  }
}

pub fn render_sheaf_cohomology_heatmap(
  matrix_10x10: List(List(Float)),
  width: Float,
  height: Float,
) -> Element(msg) {
  let plot =
    dsl.new_plot("PRESHEAF COHOMOLOGY OBSTRUCTION MATRIX (H^1=0)", width, height)
    |> dsl.with_scale(0.0, 10.0, 0.0, 10.0)
    |> dsl.add_deck_layer(
      HeatmapMatrixLayer(
        id: "h1_matrix",
        matrix: matrix_10x10,
        min_val: 0.0,
        max_val: 1.0,
      ),
    )
  renderer.render_plot(plot)
}

// -----------------------------------------------------------------------------
// Unbounded Fractal Passes Flight Instruments (C412..C426)
// -----------------------------------------------------------------------------

// Pass 1 (C412): L0 Constitutional 2oo3 Interlock
pub fn render_constitutional_interlock(
  v1: Bool,
  v2: Bool,
  v3: Bool,
  width: Float,
  height: Float,
) -> Element(msg) {
  let color1 = case v1 { True -> "#10b981" False -> "#ef4444" }
  let color2 = case v2 { True -> "#10b981" False -> "#ef4444" }
  let color3 = case v3 { True -> "#10b981" False -> "#ef4444" }
  let plot =
    dsl.new_plot("L0 CONSTITUTIONAL 2oo3 CONSENSUS INTERLOCK", width, height)
    |> dsl.with_scale(0.0, 100.0, 0.0, 100.0)
    |> dsl.add_deck_layer(
      TopologyGraphLayer(
        id: "guardians",
        nodes: [
          #("AGY-Guardian", Point2D(30.0, 70.0)),
          #("Claude-Guardian", Point2D(70.0, 70.0)),
          #("Codex-Guardian", Point2D(50.0, 30.0)),
        ],
        edges: [#(0, 1), #(1, 2), #(2, 0)],
      ),
    )
    |> dsl.add_scene_child(dsl.create_scene_circle("v1_orb", 30.0, 70.0, 8.0, color1))
    |> dsl.add_scene_child(dsl.create_scene_circle("v2_orb", 70.0, 70.0, 8.0, color2))
    |> dsl.add_scene_child(dsl.create_scene_circle("v3_orb", 50.0, 30.0, 8.0, color3))
  renderer.render_plot(plot)
}

// Pass 2 (C413): L1 Continuous Homotopy Morph
pub fn render_homotopy_deformation(
  start_path: List(Point2D),
  end_path: List(Point2D),
  t: Float,
  width: Float,
  height: Float,
) -> Element(msg) {
  let morphed_points =
    list.map2(start_path, end_path, fn(p0, p1) {
      let x = p0.x *. { 1.0 -. t } +. p1.x *. t
      let y = p0.y *. { 1.0 -. t } +. p1.y *. t
      Point2D(x, y)
    })
  let plot =
    dsl.new_plot("L1 HOMOTOPY GEODESIC DEFORMATION H(x, t)", width, height)
    |> dsl.with_scale(0.0, 100.0, 0.0, 100.0)
    |> dsl.add_deck_layer(PathLayer("start_path", start_path, 1.0, "#64748b"))
    |> dsl.add_deck_layer(PathLayer("end_path", end_path, 1.0, "#64748b"))
    |> dsl.add_deck_layer(PathLayer("morphed_path", morphed_points, 2.5, "#38bdf8"))
  renderer.render_plot(plot)
}

// Pass 4 (C415): L3 Strange Attractor Scope
pub fn render_strange_attractor_scope(
  trajectory: List(Point2D),
  width: Float,
  height: Float,
) -> Element(msg) {
  let plot =
    dsl.new_plot("L3 STRANGE ATTRACTOR PHASE SCOPE (LORENZ PROJECTION)", width, height)
    |> dsl.with_scale(-30.0, 30.0, 0.0, 60.0)
    |> dsl.add_series("attractor_orbit", trajectory)
    |> dsl.add_geom(GeomLine(stroke_width: 1.2, color: "#a855f7", dashed: False))
    |> dsl.add_deck_layer(ScatterplotLayer("orbit_pts", trajectory, 1.5, "#c084fc"))
  renderer.render_plot(plot)
}

// Pass 5 (C416): L4 Lyapunov Damping Funnel
pub fn render_lyapunov_damping_funnel(
  envelope: List(Point2D),
  current_energy: Float,
  width: Float,
  height: Float,
) -> Element(msg) {
  let plot =
    dsl.new_plot("L4 LYAPUNOV MONOTONIC DISSIPATION FUNNEL", width, height)
    |> dsl.with_scale(0.0, 100.0, 0.0, 100.0)
    |> dsl.add_series("dissipation_bound", envelope)
    |> dsl.add_geom(GeomArea(fill_color: "#0369a1", opacity: 0.25))
    |> dsl.add_geom(GeomLine(stroke_width: 2.0, color: "#38bdf8", dashed: False))
    |> dsl.add_deck_layer(
      ScatterplotLayer("current_e", [Point2D(50.0, current_energy)], 5.0, "#f59e0b"),
    )
  renderer.render_plot(plot)
}

// Pass 6 (C417): L5 Quantum Bloch Sphere Projection Scope
pub fn render_bloch_sphere_scope(
  theta: Float,
  phi: Float,
  width: Float,
  height: Float,
) -> Element(msg) {
  let r = 40.0
  let cx = 50.0
  let cy = 50.0
  let sin_theta = erlang_sin(theta)
  let cos_theta = erlang_cos(theta)
  let cos_phi = erlang_cos(phi)
  let px = cx +. r *. sin_theta *. cos_phi
  let py = cy -. r *. cos_theta

  let plot =
    dsl.new_plot("L5 QUANTUM STATE BLOCH SPHERE PROJECTION", width, height)
    |> dsl.with_scale(0.0, 100.0, 0.0, 100.0)
    |> dsl.add_scene_child(dsl.create_scene_circle("bloch_equator", cx, cy, r, "#1e293b"))
    |> dsl.add_scene_child(dsl.create_scene_circle("qubit_state", px, py, 6.0, "#06b6d4"))
  renderer.render_plot(plot)
}

// Pass 8 (C419): L7 Work-Stealing Mesh Flow Matrix
pub fn render_work_stealing_mesh_flow(
  queues: List(#(String, Float, Float)),
  width: Float,
  height: Float,
) -> Element(msg) {
  let nodes =
    list.map(queues, fn(q) {
      #(q.0, Point2D(q.1, q.2))
    })
  let plot =
    dsl.new_plot("L7 ERGODIC WORK-STEALING SWARM FLOW MATRIX", width, height)
    |> dsl.with_scale(0.0, 100.0, 0.0, 100.0)
    |> dsl.add_deck_layer(
      TopologyGraphLayer(
        id: "work_queues",
        nodes: nodes,
        edges: [#(0, 1), #(1, 2), #(2, 0)],
      ),
    )
  renderer.render_plot(plot)
}

// Pass 9 (C420): L8 Byzantine Quorum Venn Intersection
pub fn render_byzantine_quorum_venn(
  f_count: Int,
  width: Float,
  height: Float,
) -> Element(msg) {
  let label = "Byzantine Fault Tolerance f=" <> int.to_string(f_count)
  let plot =
    dsl.new_plot("L8 BYZANTINE QUORUM INTERSECTION VENN (" <> label <> ")", width, height)
    |> dsl.with_scale(0.0, 100.0, 0.0, 100.0)
    |> dsl.add_scene_child(dsl.create_scene_circle("q1", 40.0, 50.0, 25.0, "#0369a1"))
    |> dsl.add_scene_child(dsl.create_scene_circle("q2", 60.0, 50.0, 25.0, "#047857"))
    |> dsl.add_scene_child(dsl.create_scene_circle("intersect", 50.0, 50.0, 10.0, "#f59e0b"))
  renderer.render_plot(plot)
}

// Pass 10 (C421): L9 Century Ephemeris Telescoping Chrono-Map
pub fn render_century_ephemeris_timeline(
  epoch_sec: Float,
  width: Float,
  height: Float,
) -> Element(msg) {
  let plot =
    dsl.new_plot("L9 CENTURY EPHEMERIS MULTI-SCALE CHRONO-MAP", width, height)
    |> dsl.with_scale(0.0, 1000.0, 0.0, 100.0)
    |> dsl.add_series("century_arc", [Point2D(0.0, 50.0), Point2D(1000.0, 50.0)])
    |> dsl.add_geom(GeomLine(stroke_width: 2.0, color: "#6366f1", dashed: False))
    |> dsl.add_deck_layer(
      ScatterplotLayer("epoch_marker", [Point2D(epoch_sec, 50.0)], 6.0, "#ec4899"),
    )
  renderer.render_plot(plot)
}

// Pass 11 (C422): Dark Cockpit Contrast Ratio Meter
pub fn render_dark_cockpit_contrast_meter(
  contrast_ratio: Float,
  width: Float,
  height: Float,
) -> Element(msg) {
  let bar_color = case contrast_ratio >=. 7.0 {
    True -> "#10b981"
    False -> "#ef4444"
  }
  let plot =
    dsl.new_plot("DARK COCKPIT WCAG AAA CONTRAST METER", width, height)
    |> dsl.with_scale(0.0, 21.0, 0.0, 100.0)
    |> dsl.add_scene_child(dsl.create_scene_rect("contrast_bar", 2.0, 20.0, contrast_ratio *. 4.0, 40.0, bar_color))
    |> dsl.add_scene_child(dsl.create_scene_rect("threshold_line", 28.0, 15.0, 2.0, 50.0, "#f59e0b"))
  renderer.render_plot(plot)
}

// Pass 12 (C423): Zero-GC Lockless Ring Buffer Scope
pub fn render_lockless_ring_buffer_scope(
  head_idx: Int,
  tail_idx: Int,
  capacity: Int,
  width: Float,
  height: Float,
) -> Element(msg) {
  let title =
    "LOCKLESS RING BUFFER SCOPE (H:" <> int.to_string(head_idx) <> " T:" <> int.to_string(tail_idx) <> " C:" <> int.to_string(capacity) <> ")"
  let plot =
    dsl.new_plot(title, width, height)
    |> dsl.with_scale(0.0, 100.0, 0.0, 100.0)
    |> dsl.add_scene_child(dsl.create_scene_circle("ring", 50.0, 50.0, 35.0, "#1e293b"))
    |> dsl.add_scene_child(dsl.create_scene_circle("head_ptr", 50.0, 15.0, 6.0, "#38bdf8"))
    |> dsl.add_scene_child(dsl.create_scene_circle("tail_ptr", 85.0, 50.0, 6.0, "#f59e0b"))
  renderer.render_plot(plot)
}

// Pass 15 (C426): Sovereign Merkle Provenance Ledger Visualizer
pub fn render_sovereign_merkle_provenance(
  seq: Int,
  digest_prefix: String,
  width: Float,
  height: Float,
) -> Element(msg) {
  let title = "SOVEREIGN MERKLE PROVENANCE [SEQ:" <> int.to_string(seq) <> " " <> digest_prefix <> "]"
  let plot =
    dsl.new_plot(title, width, height)
    |> dsl.with_scale(0.0, 100.0, 0.0, 100.0)
    |> dsl.add_scene_child(dsl.create_scene_nine_slice("block_1", 10.0, 30.0, 70.0, 40.0, "#0f172a"))
    |> dsl.add_scene_child(dsl.create_scene_text("hash_text", 15.0, 50.0, digest_prefix, 10, "#38bdf8"))
  renderer.render_plot(plot)
}
