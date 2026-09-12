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

pub type Rect2D {
  Rect2D(x: Float, y: Float, width: Float, height: Float)
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
  GeomBoxplot(width: Float, fill_color: String, stroke_color: String)
  GeomViolin(bandwidth: Float, fill_color: String, opacity: Float)
  GeomHex(radius: Float, stroke_color: String)
  GeomDensity2D(levels: Int, color: String)
  GeomErrorBar(width: Float, stroke_width: Float, color: String)
  GeomStep(stroke_width: Float, color: String)
  GeomContour(thresholds: List(Float), color: String)
  GeomSegment(stroke_width: Float, color: String)
  GeomText(size: Int, color: String, font_family: String)
}

pub type DataSeries {
  DataSeries(name: String, points: List(Point2D))
}

// -----------------------------------------------------------------------------
// 2. SciChart High-Performance Scientific Buffers, Series & Modifiers
// -----------------------------------------------------------------------------

pub type CandleData {
  CandleData(open: Float, high: Float, low: Float, close: Float, timestamp: Float)
}

pub type BubbleData {
  BubbleData(x: Float, y: Float, z: Float, label: String)
}

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

pub type SciChartSeries {
  FastLineSeries(name: String, points: List(Point2D), stroke_width: Float, color: String)
  FastMountainSeries(name: String, points: List(Point2D), zero_line: Float, fill_color: String, stroke_color: String)
  FastCandlestickSeries(name: String, candles: List(CandleData), up_color: String, down_color: String)
  FastBandSeries(name: String, high_points: List(Point2D), low_points: List(Point2D), band_fill: String)
  FastBubbleSeries(name: String, bubbles: List(BubbleData), min_radius: Float, max_radius: Float)
  FastColumnSeries(name: String, points: List(Point2D), column_width: Float, fill_color: String)
  FastHeatmapSeries(name: String, matrix: List(List(Float)), color_map: String)
  SplineLineSeries(name: String, points: List(Point2D), tension: Float, color: String)
  DigitalBandSeries(name: String, high_points: List(Point2D), low_points: List(Point2D), color: String)
}

pub type SciChartModifier {
  CursorModifier(axis_crosshair: Bool, show_tooltip: Bool, line_color: String)
  RolloverModifier(snap_to_data: Bool, show_series_markers: Bool, line_color: String)
  RubberBandZoomModifier(is_animated: Bool, fill_color: String, stroke_color: String)
  LegendModifier(show_checkboxes: Bool, orientation: String, position: String)
  ThresholdCursor(threshold: Float, label: String, alert_color: String)
  PolarGridModifier(radial_rings: Int, angular_sectors: Int, grid_color: String)
}

// -----------------------------------------------------------------------------
// 3. Deck.gl Reactive Layer Taxonomy
// -----------------------------------------------------------------------------

pub type IconData {
  IconData(position: Point2D, icon_name: String, size: Float, color: String)
}

pub type GeoFeature {
  GeoFeature(id: String, coordinates: List(Point2D), feature_type: String)
}

pub type ColumnData {
  ColumnData(position: Point2D, elevation: Float, color: String)
}

pub type TextLabelData {
  TextLabelData(position: Point2D, text: String, anchor: String, color: String)
}

pub type TripData {
  TripData(id: String, path_with_timestamps: List(#(Point2D, Float)), color: String)
}

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
  LineLayer(id: String, lines: List(#(Point2D, Point2D)), stroke_width: Float, color: String)
  BitmapLayer(id: String, bounds: Rect2D, image_url: String, opacity: Float)
  IconLayer(id: String, icons: List(IconData), size_scale: Float)
  GeoJsonLayer(id: String, features: List(GeoFeature), fill_color: String, stroke_color: String)
  GridLayer(id: String, points: List(Point2D), cell_size: Float, elevation_scale: Float)
  HexagonLayer(id: String, points: List(Point2D), radius: Float, coverage: Float)
  ColumnLayer(id: String, columns: List(ColumnData), disk_resolution: Int, radius: Float)
  PointCloudLayer(id: String, points: List(Point3D), point_size: Float, color: String)
  ScreenGridLayer(id: String, points: List(Point2D), cell_size_pixels: Float)
  TextLayer(id: String, labels: List(TextLabelData), font_size: Int)
  TripsLayer(id: String, trips: List(TripData), trail_length: Float, current_time: Float)
  H3HexagonLayer(id: String, hex_ids: List(String), elevation_scale: Float)
  S2Layer(id: String, s2_tokens: List(String), fill_color: String)
  TileLayer(id: String, tile_url_template: String, min_zoom: Int, max_zoom: Int)
}

// -----------------------------------------------------------------------------
// 4. PixiJS Scene Graph Display Nodes & Filters
// -----------------------------------------------------------------------------

pub type ParticleData {
  ParticleData(x: Float, y: Float, vx: Float, vy: Float, scale: Float, alpha: Float, color: String)
}

pub type PixiFilter {
  PixiFilter(filter_type: String, intensity: Float, enabled: Bool)
}

pub type SceneVisual {
  VisualCircle(cx: Float, cy: Float, r: Float, fill: String)
  VisualRect(x: Float, y: Float, w: Float, h: Float, fill: String)
  VisualText(x: Float, y: Float, content: String, size: Int, color: String)
  VisualComposite(geoms: List(GeomType))
  VisualSprite(x: Float, y: Float, w: Float, h: Float, texture_id: String, tint: String)
  VisualNineSlicePlane(x: Float, y: Float, w: Float, h: Float, left: Float, top: Float, right: Float, bottom: Float, fill: String)
  VisualTilingSprite(x: Float, y: Float, w: Float, h: Float, tile_scale_x: Float, tile_scale_y: Float, pattern_id: String)
  VisualParticleContainer(particles: List(ParticleData), blend_mode: String)
  VisualMesh(vertices: List(Point2D), uvs: List(Point2D), indices: List(Int), color: String)
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
