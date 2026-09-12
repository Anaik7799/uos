// dsl.gleam — Declarative Intent-Based API Builder for SciViz Library
// Enables fluent, type-safe composition of Grammar of Graphics geoms,
// SciChart data buffers, deck.gl layers, and PixiJS scene nodes.

import cepaf_gleam/sciviz/schema.{
  type DarkCockpitTheme, type DeckLayer, type GeomType, type Point2D,
  type Scale2D, type SceneNode, type SciVizPlot, DataSeries, Point2D, Scale2D,
  SceneNode, SciVizPlot, VisualCircle, default_dark_cockpit_theme,
}

pub fn new_plot(title: String, width: Float, height: Float) -> SciVizPlot {
  let initial_scale =
    Scale2D(
      x_min: 0.0,
      x_max: 100.0,
      y_min: 0.0,
      y_max: 100.0,
      target_w: width,
      target_h: height,
    )
  let root_node =
    SceneNode(
      id: "root",
      translate: Point2D(0.0, 0.0),
      rotate_deg: 0.0,
      scale: 1.0,
      visual: VisualCircle(0.0, 0.0, 0.0, "none"),
      children: [],
    )
  SciVizPlot(
    title: title,
    width: width,
    height: height,
    theme: default_dark_cockpit_theme(),
    scale: initial_scale,
    data_series: [],
    geoms: [],
    layers: [],
    scene_root: root_node,
  )
}

pub fn with_scale(
  plot: SciVizPlot,
  x_min: Float,
  x_max: Float,
  y_min: Float,
  y_max: Float,
) -> SciVizPlot {
  let updated_scale =
    Scale2D(
      ..plot.scale,
      x_min: x_min,
      x_max: x_max,
      y_min: y_min,
      y_max: y_max,
    )
  SciVizPlot(..plot, scale: updated_scale)
}

pub fn with_theme(plot: SciVizPlot, theme: DarkCockpitTheme) -> SciVizPlot {
  SciVizPlot(..plot, theme: theme)
}

pub fn add_series(
  plot: SciVizPlot,
  name: String,
  points: List(Point2D),
) -> SciVizPlot {
  let series = DataSeries(name: name, points: points)
  SciVizPlot(..plot, data_series: [series, ..plot.data_series])
}

pub fn add_geom(plot: SciVizPlot, geom: GeomType) -> SciVizPlot {
  SciVizPlot(..plot, geoms: [geom, ..plot.geoms])
}

pub fn add_deck_layer(plot: SciVizPlot, layer: DeckLayer) -> SciVizPlot {
  SciVizPlot(..plot, layers: [layer, ..plot.layers])
}

pub fn add_scene_child(plot: SciVizPlot, node: SceneNode) -> SciVizPlot {
  let updated_root =
    SceneNode(..plot.scene_root, children: [node, ..plot.scene_root.children])
  SciVizPlot(..plot, scene_root: updated_root)
}

pub fn project_point(scale: Scale2D, p: Point2D) -> Point2D {
  let x_span = scale.x_max -. scale.x_min
  let y_span = scale.y_max -. scale.y_min
  let safe_x_span = case x_span == 0.0 {
    True -> 1.0
    False -> x_span
  }
  let safe_y_span = case y_span == 0.0 {
    True -> 1.0
    False -> y_span
  }
  let norm_x = { p.x -. scale.x_min } /. safe_x_span
  let norm_y = { p.y -. scale.y_min } /. safe_y_span
  let screen_x = norm_x *. scale.target_w
  let screen_y = scale.target_h -. { norm_y *. scale.target_h }
  Point2D(x: screen_x, y: screen_y)
}
