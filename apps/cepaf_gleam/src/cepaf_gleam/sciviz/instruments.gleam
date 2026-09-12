// instruments.gleam — Pre-Built Scientific Cybernetic Flight Instruments
// Composes Grammar of Graphics, SciChart buffers, deck.gl layers, and PixiJS
// scene graphs into production control center flight instruments.

import cepaf_gleam/sciviz/dsl
import cepaf_gleam/sciviz/renderer
import cepaf_gleam/sciviz/schema.{
  type Point2D, type SciChartFifoBuffer, type SciVizPlot, ArcLayer, GeomLine,
  GeomPhasePortrait, HeatmapMatrixLayer, Point2D, ScatterplotLayer,
  TopologyGraphLayer,
}
import lustre/element.{type Element}

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
