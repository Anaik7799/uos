// schema.gleam — Scientific Visualization (SciViz) Core Schema
// Synthesizes Grammar of Graphics (ggplot2), SciChart, deck.gl, and PixiJS
// into a unified pure Gleam Lustre WebUI visual computation model.
//
// Governing Standards:
// - SC-SCIVIZ-001 (Unified Graphics Grammar & SciChart FIFO Synthesis)
// - SC-GLM-UI-001 (Pure Lustre First Mandate / Zero Client JS)
// - SC-HMI-010 (Dark Cockpit Ergonomics)
// - ZERO-MUDA: 0 External JavaScript, 0 npm packages, 0 foreign NIFs

import gleam/list

pub type Point2D {
  Point2D(x: Float, y: Float)
}

pub type Point3D {
  Point3D(x: Float, y: Float, z: Float)
}

pub type RgbaColor {
  RgbaColor(r: Int, g: Int, b: Int, a: Float)
}

// -----------------------------------------------------------------------------
// 1. Grammar of Graphics (ggplot2 / Plotly) Layer
// -----------------------------------------------------------------------------

pub type AestheticMapping {
  AestheticMapping(
    x_field: String,
    y_field: String,
    color_field: String,
    size_field: String,
  )
}

pub type GeomType {
  GeomPoint(size: Float, color: String)
  GeomLine(stroke_width: Float, color: String, dashed: Bool)
  GeomArea(fill_color: String, opacity: Float)
  GeomBar(bar_width: Float, fill_color: String)
  GeomRibbon(fill_color: String, opacity: Float)
  GeomPhasePortrait(vector_scale: Float, color: String)
}

pub type DataSeries {
  DataSeries(name: String, points: List(Point2D))
}

// -----------------------------------------------------------------------------
// 2. SciChart High-Performance Scientific Buffers
// -----------------------------------------------------------------------------

pub type SciChartFifoBuffer {
  SciChartFifoBuffer(capacity: Int, points: List(Point2D))
}

pub fn new_fifo(capacity: Int) -> SciChartFifoBuffer {
  SciChartFifoBuffer(capacity: capacity, points: [])
}

pub fn push_fifo(
  buf: SciChartFifoBuffer,
  point: Point2D,
) -> SciChartFifoBuffer {
  case list.length(buf.points) < buf.capacity {
    True -> SciChartFifoBuffer(..buf, points: [point, ..buf.points])
    False -> {
      let trimmed = list.take(buf.points, buf.capacity - 1)
      SciChartFifoBuffer(..buf, points: [point, ..trimmed])
    }
  }
}

// -----------------------------------------------------------------------------
// 3. Deck.gl Reactive Layer Taxonomy
// -----------------------------------------------------------------------------

pub type DeckLayer {
  ScatterplotLayer(
    id: String,
    points: List(Point2D),
    radius: Float,
    color: String,
  )
  PathLayer(
    id: String,
    path: List(Point2D),
    stroke_width: Float,
    color: String,
  )
  ArcLayer(
    id: String,
    source: Point2D,
    target: Point2D,
    tilt: Float,
    stroke_width: Float,
    color: String,
  )
  HeatmapMatrixLayer(
    id: String,
    matrix: List(List(Float)),
    min_val: Float,
    max_val: Float,
  )
  TopologyGraphLayer(
    id: String,
    nodes: List(#(String, Point2D)),
    edges: List(#(Int, Int)),
  )
}

// -----------------------------------------------------------------------------
// 4. PixiJS Scene Graph Display Nodes
// -----------------------------------------------------------------------------

pub type SceneVisual {
  VisualCircle(cx: Float, cy: Float, r: Float, fill: String)
  VisualRect(x: Float, y: Float, w: Float, h: Float, fill: String)
  VisualText(x: Float, y: Float, content: String, size: Int, color: String)
  VisualComposite(geoms: List(GeomType))
}

pub type SceneNode {
  SceneNode(
    id: String,
    translate: Point2D,
    rotate_deg: Float,
    scale: Float,
    visual: SceneVisual,
    children: List(SceneNode),
  )
}

// -----------------------------------------------------------------------------
// 5. Scales, Coordinates & Dark Cockpit Theming
// -----------------------------------------------------------------------------

pub type Scale2D {
  Scale2D(
    x_min: Float,
    x_max: Float,
    y_min: Float,
    y_max: Float,
    target_w: Float,
    target_h: Float,
  )
}

pub type DarkCockpitTheme {
  DarkCockpitTheme(
    bg_color: String,
    grid_color: String,
    axis_color: String,
    text_color: String,
    primary_color: String,
    accent_color: String,
    warning_color: String,
    alert_color: String,
  )
}

pub fn default_dark_cockpit_theme() -> DarkCockpitTheme {
  DarkCockpitTheme(
    bg_color: "#020617",
    grid_color: "#1e293b",
    axis_color: "#334155",
    text_color: "#94a3b8",
    primary_color: "#38bdf8",
    accent_color: "#10b981",
    warning_color: "#f59e0b",
    alert_color: "#f43f5e",
  )
}

pub type SciVizPlot {
  SciVizPlot(
    title: String,
    width: Float,
    height: Float,
    theme: DarkCockpitTheme,
    scale: Scale2D,
    data_series: List(DataSeries),
    geoms: List(GeomType),
    layers: List(DeckLayer),
    scene_root: SceneNode,
  )
}
