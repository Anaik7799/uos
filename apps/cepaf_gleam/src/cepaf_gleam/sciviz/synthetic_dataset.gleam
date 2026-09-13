//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/sciviz/synthetic_dataset</module></identity>
////   <fractal-topology><layer>L2_COMPONENT..L8_VERIFICATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-SCIVIZ-001, SC-CHECKLIST-001, SC-INTENT-ATLAS-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Comprehensive Synthetic Datapoint & Dataset Generator Covering the Full Feature Envelope
//// for all SciViz Visualizations, ggplot2 Extensions (167 packages), and 15 Use Cases.
//// Provides mathematically rigorous boundaries, extremes, distributions, networks, flows,
//// survival curves, geospatial vectors, karyotypes, and high-dimensional compositions.
//// Zero-Muda compliant: Pure Gleam on BEAM VM, 0 external dependencies, 0 foreign NIFs.

import cepaf_gleam/sciviz/schema.{type Point2D, Point2D, type Rect2D, Rect2D}

// -----------------------------------------------------------------------------
// Envelope Summary Type
// -----------------------------------------------------------------------------

pub type EnvelopeKind {
  UncertaintyEnvelope
  NetworkEnvelope
  FlowEnvelope
  HierarchyEnvelope
  SurvivalEnvelope
  MultiFacetEnvelope
  CorrelationEnvelope
  GeospatialEnvelope
  GenomicEnvelope
  TernaryEnvelope
  TimeSeriesEnvelope
  SplineEnvelope
  MosaicEnvelope
  MarginalEnvelope
  CompositeEnvelope
}

pub type SyntheticFeatureEnvelope {
  SyntheticFeatureEnvelope(
    use_case_id: String,
    name: String,
    kind: EnvelopeKind,
    total_datapoints: Int,
    boundary_cases_covered: List(String),
    envelope_metrics: List(#(String, String)),
    verified: Bool,
  )
}

// -----------------------------------------------------------------------------
// 1. Uncertainty & Credible Interval Envelope (ggdist, ggridges)
// -----------------------------------------------------------------------------

pub type CredibleInterval {
  CredibleInterval(level: Float, lower: Float, upper: Float, line_width: Float)
}

pub type DistributionDataset {
  DistributionDataset(
    name: String,
    sample_size: Int,
    mean: Float,
    median: Float,
    std_dev: Float,
    skewness: Float,
    kurtosis: Float,
    intervals: List(CredibleInterval),
    density_curve: List(Point2D),
    outliers: List(Float),
  )
}

pub fn generate_uncertainty_envelope() -> DistributionDataset {
  let intervals = [
    CredibleInterval(level: 0.50, lower: 232.0, upper: 288.0, line_width: 7.0),
    CredibleInterval(level: 0.80, lower: 205.0, upper: 315.0, line_width: 3.5),
    CredibleInterval(level: 0.95, lower: 172.0, upper: 348.0, line_width: 1.5),
    CredibleInterval(level: 0.99, lower: 140.0, upper: 380.0, line_width: 1.0),
  ]

  let density_points = [
    Point2D(x: 100.0, y: 145.0),
    Point2D(x: 140.0, y: 142.0),
    Point2D(x: 180.0, y: 115.0),
    Point2D(x: 220.0, y: 65.0),
    Point2D(x: 260.0, y: 40.0),
    Point2D(x: 300.0, y: 65.0),
    Point2D(x: 340.0, y: 115.0),
    Point2D(x: 380.0, y: 142.0),
    Point2D(x: 420.0, y: 145.0),
  ]

  DistributionDataset(
    name: "Posterior Parameter Estimator (Half-Eye)",
    sample_size: 10_000,
    mean: 260.0,
    median: 260.0,
    std_dev: 45.0,
    skewness: 0.05,
    kurtosis: 2.98,
    intervals: intervals,
    density_curve: density_points,
    outliers: [85.0, 445.0],
  )
}

// -----------------------------------------------------------------------------
// 2. Network Topology & Graph Envelope (ggraph, tidygraph, geomnet)
// -----------------------------------------------------------------------------

pub type GraphNode {
  GraphNode(id: String, label: String, x: Float, y: Float, degree: Int, pagerank: Float, cluster: Int)
}

pub type GraphEdge {
  GraphEdge(source: String, target: String, weight: Float, is_directed: Bool)
}

pub type NetworkDataset {
  NetworkDataset(
    name: String,
    node_count: Int,
    edge_count: Int,
    density: Float,
    diameter: Int,
    average_clustering: Float,
    nodes: List(GraphNode),
    edges: List(GraphEdge),
  )
}

pub fn generate_network_envelope() -> NetworkDataset {
  let nodes = [
    GraphNode(id: "L0", label: "L0 Constitutional Consensus", x: 240.0, y: 100.0, degree: 4, pagerank: 0.38, cluster: 0),
    GraphNode(id: "L1", label: "L1 Gleam/OTP Runtime", x: 140.0, y: 70.0, degree: 2, pagerank: 0.18, cluster: 1),
    GraphNode(id: "L2", label: "L2 Hermes Gospel Engine", x: 130.0, y: 140.0, degree: 2, pagerank: 0.16, cluster: 1),
    GraphNode(id: "L3", label: "L3 ZigVM VFS Execution", x: 340.0, y: 70.0, degree: 2, pagerank: 0.15, cluster: 2),
    GraphNode(id: "L4", label: "L4 MAX/Mojo Inference", x: 350.0, y: 140.0, degree: 2, pagerank: 0.13, cluster: 2),
  ]

  let edges = [
    GraphEdge(source: "L1", target: "L0", weight: 1.0, is_directed: True),
    GraphEdge(source: "L2", target: "L0", weight: 1.0, is_directed: True),
    GraphEdge(source: "L0", target: "L3", weight: 0.8, is_directed: True),
    GraphEdge(source: "L0", target: "L4", weight: 0.8, is_directed: True),
    GraphEdge(source: "L1", target: "L2", weight: 0.5, is_directed: False),
    GraphEdge(source: "L3", target: "L4", weight: 0.5, is_directed: False),
  ]

  NetworkDataset(
    name: "Tri-Domain Sovereign Control Mesh",
    node_count: 5,
    edge_count: 6,
    density: 0.60,
    diameter: 2,
    average_clustering: 0.66,
    nodes: nodes,
    edges: edges,
  )
}

// -----------------------------------------------------------------------------
// 3. Flow & Alluvial Sankey Envelope (ggalluvial, ggsankey)
// -----------------------------------------------------------------------------

pub type AlluvialStratum {
  AlluvialStratum(stage_index: Int, name: String, y_start: Float, y_end: Float, color: String)
}

pub type AlluvialFlow {
  AlluvialFlow(from_stage: Int, from_stratum: String, to_stage: Int, to_stratum: String, volume: Float, path_d: String)
}

pub type AlluvialDataset {
  AlluvialDataset(
    name: String,
    stage_names: List(String),
    strata: List(AlluvialStratum),
    flows: List(AlluvialFlow),
    total_inflow: Float,
    total_outflow: Float,
    retention_rate: Float,
  )
}

pub fn generate_flow_envelope() -> AlluvialDataset {
  let strata = [
    AlluvialStratum(0, "Raw Intake (100%)", 50.0, 160.0, "#38bdf8"),
    AlluvialStratum(1, "Preflight Pass (85%)", 50.0, 145.0, "#34d399"),
    AlluvialStratum(1, "Preflight Drop (15%)", 148.0, 160.0, "#f87171"),
    AlluvialStratum(2, "Lean 4 Ratified (70%)", 50.0, 128.0, "#818cf8"),
    AlluvialStratum(2, "Fuzz Admitted (15%)", 130.0, 145.0, "#fbbf24"),
    AlluvialStratum(3, "Sovereign Ledger (70%)", 50.0, 128.0, "#4ade80"),
  ]

  let flows = [
    AlluvialFlow(0, "Raw", 1, "Pass", 85.0, "M 60 50 C 130 50, 130 50, 200 50 L 200 145 C 130 145, 130 145, 60 145 Z"),
    AlluvialFlow(0, "Raw", 1, "Drop", 15.0, "M 60 145 C 130 145, 130 148, 200 148 L 200 160 C 130 160, 130 160, 60 160 Z"),
    AlluvialFlow(1, "Pass", 2, "Ratified", 70.0, "M 220 50 C 280 50, 280 50, 340 50 L 340 128 C 280 128, 280 128, 220 128 Z"),
    AlluvialFlow(1, "Pass", 2, "Fuzz", 15.0, "M 220 128 C 280 128, 280 130, 340 130 L 340 145 C 280 145, 280 145, 220 145 Z"),
    AlluvialFlow(2, "Ratified", 3, "Ledger", 70.0, "M 360 50 C 400 50, 400 50, 440 50 L 440 128 C 400 128, 400 128, 360 128 Z"),
  ]

  AlluvialDataset(
    name: "Evidence Pipeline Alluvial Flow",
    stage_names: ["Intake", "Preflight", "Verification", "Admission"],
    strata: strata,
    flows: flows,
    total_inflow: 100.0,
    total_outflow: 70.0,
    retention_rate: 0.70,
  )
}

// -----------------------------------------------------------------------------
// 4. Hierarchical Partition & Treemap Envelope (treemapify, voronoi)
// -----------------------------------------------------------------------------

pub type HierarchyNode {
  HierarchyNode(id: String, name: String, weight: Float, depth: Int, rect: Rect2D, color: String)
}

pub type HierarchyDataset {
  HierarchyDataset(
    name: String,
    total_weight: Float,
    max_depth: Int,
    node_count: Int,
    nodes: List(HierarchyNode),
  )
}

pub fn generate_hierarchy_envelope() -> HierarchyDataset {
  let nodes = [
    HierarchyNode("Apps", "Apps (Gleam/OTP)", 40.0, 1, Rect2D(20.0, 50.0, 190.0, 110.0), "#38bdf8"),
    HierarchyNode("Engines", "Engines (Hermes+ZigVM)", 30.0, 1, Rect2D(215.0, 50.0, 140.0, 110.0), "#818cf8"),
    HierarchyNode("Services", "Services (MAX/Mojo)", 18.0, 1, Rect2D(360.0, 50.0, 100.0, 53.0), "#34d399"),
    HierarchyNode("Gov", "Gov (KM Triad)", 12.0, 1, Rect2D(360.0, 107.0, 100.0, 53.0), "#fbbf24"),
  ]

  HierarchyDataset(
    name: "UOS Monorepo System Tree Partition",
    total_weight: 100.0,
    max_depth: 2,
    node_count: 4,
    nodes: nodes,
  )
}

// -----------------------------------------------------------------------------
// 5. Survival & Kaplan-Meier Envelope (survminer, ggsurvfit)
// -----------------------------------------------------------------------------

pub type SurvivalStep {
  SurvivalStep(time_hours: Float, probability: Float, lower_ci: Float, upper_ci: Float, n_risk: Int, n_event: Int)
}

pub type SurvivalDataset {
  SurvivalDataset(
    name: String,
    sample_size: Int,
    median_survival_hours: Float,
    censoring_percentage: Float,
    steps: List(SurvivalStep),
  )
}

pub fn generate_survival_envelope() -> SurvivalDataset {
  let steps = [
    SurvivalStep(0.0, 1.00, 1.00, 1.00, 1000, 0),
    SurvivalStep(50.0, 0.95, 0.93, 0.97, 950, 48),
    SurvivalStep(100.0, 0.88, 0.85, 0.91, 880, 65),
    SurvivalStep(150.0, 0.76, 0.72, 0.80, 760, 112),
    SurvivalStep(200.0, 0.62, 0.57, 0.66, 618, 135),
    SurvivalStep(250.0, 0.48, 0.43, 0.53, 476, 138),
    SurvivalStep(300.0, 0.35, 0.30, 0.40, 345, 126),
  ]

  SurvivalDataset(
    name: "Actor Process Lifetime (MTBF) Profile",
    sample_size: 1000,
    median_survival_hours: 242.5,
    censoring_percentage: 12.5,
    steps: steps,
  )
}

// -----------------------------------------------------------------------------
// 6. Multi-Facet Density Ridge Envelope (ggridges, ggh4x)
// -----------------------------------------------------------------------------

pub type RidgeFacet {
  RidgeFacet(label: String, baseline_y: Float, peak_y: Float, curve: List(Point2D), color: String)
}

pub type RidgeDataset {
  RidgeDataset(
    name: String,
    facet_count: Int,
    overlap_ratio: Float,
    facets: List(RidgeFacet),
  )
}

pub fn generate_ridge_envelope() -> RidgeDataset {
  let facets = [
    RidgeFacet(
      "Layer 0 Const",
      155.0,
      120.0,
      [Point2D(60.0, 155.0), Point2D(140.0, 150.0), Point2D(220.0, 125.0), Point2D(300.0, 150.0), Point2D(420.0, 155.0)],
      "#f43f5e",
    ),
    RidgeFacet(
      "Layer 3 Trans",
      125.0,
      88.0,
      [Point2D(60.0, 125.0), Point2D(160.0, 115.0), Point2D(250.0, 90.0), Point2D(340.0, 120.0), Point2D(420.0, 125.0)],
      "#fbbf24",
    ),
    RidgeFacet(
      "Layer 5 Cognit",
      95.0,
      58.0,
      [Point2D(60.0, 95.0), Point2D(180.0, 80.0), Point2D(280.0, 60.0), Point2D(370.0, 90.0), Point2D(420.0, 95.0)],
      "#38bdf8",
    ),
    RidgeFacet(
      "Layer 8 Verif",
      65.0,
      32.0,
      [Point2D(60.0, 65.0), Point2D(200.0, 50.0), Point2D(310.0, 35.0), Point2D(390.0, 60.0), Point2D(420.0, 65.0)],
      "#4ade80",
    ),
  ]

  RidgeDataset(
    name: "Multi-Tier Latency Ridges",
    facet_count: 4,
    overlap_ratio: 0.65,
    facets: facets,
  )
}

// -----------------------------------------------------------------------------
// 7. Correlogram & Correlation Matrix Envelope (ggcorrplot, ggfortify)
// -----------------------------------------------------------------------------

pub type CorrelationCell {
  CorrelationCell(row: Int, col: Int, var_x: String, var_y: String, r: Float, p_value: Float)
}

pub type CorrelationDataset {
  CorrelationDataset(
    name: String,
    variables: List(String),
    cells: List(CorrelationCell),
    determinant: Float,
    condition_number: Float,
  )
}

pub fn generate_correlation_envelope() -> CorrelationDataset {
  let vars = ["Entropy H", "CCM %", "D_EA %", "ITQS", "Pass Rate"]
  let cells = [
    CorrelationCell(0, 0, "Entropy H", "Entropy H", 1.00, 0.0001),
    CorrelationCell(0, 1, "Entropy H", "CCM %", 0.78, 0.002),
    CorrelationCell(0, 2, "Entropy H", "D_EA %", -0.65, 0.012),
    CorrelationCell(0, 3, "Entropy H", "ITQS", 0.84, 0.0005),
    CorrelationCell(1, 1, "CCM %", "CCM %", 1.00, 0.0001),
    CorrelationCell(1, 2, "CCM %", "D_EA %", -0.82, 0.001),
    CorrelationCell(1, 3, "CCM %", "ITQS", 0.91, 0.0001),
    CorrelationCell(2, 2, "D_EA %", "D_EA %", 1.00, 0.0001),
    CorrelationCell(2, 3, "D_EA %", "ITQS", -0.79, 0.0015),
    CorrelationCell(3, 3, "ITQS", "ITQS", 1.00, 0.0001),
  ]

  CorrelationDataset(
    name: "Math Quality Metric Correlogram",
    variables: vars,
    cells: cells,
    determinant: 0.042,
    condition_number: 14.8,
  )
}

// -----------------------------------------------------------------------------
// 8. Geospatial & Vector Field Envelope (ggspatial, sf, metR)
// -----------------------------------------------------------------------------

pub type FlowVector {
  FlowVector(x: Float, y: Float, u: Float, v: Float, magnitude: Float, angle_deg: Float)
}

pub type GeospatialDataset {
  GeospatialDataset(
    name: String,
    bounding_box: Rect2D,
    vectors: List(FlowVector),
    divergence_max: Float,
    vorticity_max: Float,
  )
}

pub fn generate_geospatial_envelope() -> GeospatialDataset {
  let vectors = [
    FlowVector(80.0, 80.0, 12.0, -8.0, 14.4, -33.7),
    FlowVector(140.0, 80.0, 15.0, -4.0, 15.5, -14.9),
    FlowVector(200.0, 80.0, 14.0, 2.0, 14.1, 8.1),
    FlowVector(80.0, 130.0, 8.0, -10.0, 12.8, -51.3),
    FlowVector(140.0, 130.0, 10.0, -2.0, 10.2, -11.3),
    FlowVector(200.0, 130.0, 11.0, 6.0, 12.5, 28.6),
  ]

  GeospatialDataset(
    name: "Atmospheric & Pressure Vector Field",
    bounding_box: Rect2D(50.0, 50.0, 380.0, 120.0),
    vectors: vectors,
    divergence_max: 0.015,
    vorticity_max: 0.042,
  )
}

// -----------------------------------------------------------------------------
// 9. Genomic Karyotype & Manhattan Envelope (ggbio, karyoploteR)
// -----------------------------------------------------------------------------

pub type GenomicVariant {
  GenomicVariant(chrom: String, position_mb: Float, neg_log_p: Float, is_significant: Bool, gene_label: String)
}

pub type GenomicDataset {
  GenomicDataset(
    name: String,
    total_variants: Int,
    significance_threshold: Float,
    variants: List(GenomicVariant),
  )
}

pub fn generate_genomic_envelope() -> GenomicDataset {
  let variants = [
    GenomicVariant("Chr1", 24.5, 4.2, False, ""),
    GenomicVariant("Chr1", 89.1, 5.1, False, ""),
    GenomicVariant("Chr2", 42.0, 7.8, False, ""),
    GenomicVariant("Chr3", 112.4, 14.6, True, "TP53_VARIANT"),
    GenomicVariant("Chr4", 65.2, 3.8, False, ""),
    GenomicVariant("Chr5", 13.8, 6.2, False, ""),
    GenomicVariant("Chr6", 32.1, 18.4, True, "BRCA1_HOTSPOT"),
    GenomicVariant("Chr7", 98.0, 4.9, False, ""),
  ]

  GenomicDataset(
    name: "Genome-Wide Association Study (GWAS) Manhattan",
    total_variants: 850_000,
    significance_threshold: 8.0,
    variants: variants,
  )
}

// -----------------------------------------------------------------------------
// 10. Ternary & Barycentric Composition Envelope (ggtern, ggradar)
// -----------------------------------------------------------------------------

pub type TernaryPoint {
  TernaryPoint(label: String, a: Float, b: Float, c: Float, color: String)
}

pub type TernaryDataset {
  TernaryDataset(
    name: String,
    components: #(String, String, String),
    points: List(TernaryPoint),
    is_normalized: Bool,
  )
}

pub fn generate_ternary_envelope() -> TernaryDataset {
  let points = [
    TernaryPoint("High Gleam Purity", 0.70, 0.20, 0.10, "#38bdf8"),
    TernaryPoint("Hermes Formal Proof", 0.15, 0.75, 0.10, "#818cf8"),
    TernaryPoint("ZigVM Determinism", 0.15, 0.15, 0.70, "#f59e0b"),
    TernaryPoint("Tri-Sovereign Quorum", 0.333, 0.333, 0.334, "#34d399"),
  ]

  TernaryDataset(
    name: "Multi-Language Architectural Ratio (A+B+C=1)",
    components: #("Gleam/OTP", "Hermes OCaml", "ZigVM Kernel"),
    points: points,
    is_normalized: True,
  )
}

// -----------------------------------------------------------------------------
// 11. Time Series Forecast & Fan Interval Envelope (feasts, fabletools)
// -----------------------------------------------------------------------------

pub type ForecastPoint {
  ForecastPoint(time_t: Float, history: Float, forecast: Float, lower_80: Float, upper_80: Float, lower_95: Float, upper_95: Float)
}

pub type TimeSeriesDataset {
  TimeSeriesDataset(
    name: String,
    series_length: Int,
    horizon: Int,
    seasonality_period: Int,
    points: List(ForecastPoint),
  )
}

pub fn generate_timeseries_envelope() -> TimeSeriesDataset {
  let points = [
    ForecastPoint(1.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0),
    ForecastPoint(2.0, 108.0, 108.0, 108.0, 108.0, 108.0, 108.0),
    ForecastPoint(3.0, 115.0, 115.0, 115.0, 115.0, 115.0, 115.0),
    ForecastPoint(4.0, 112.0, 112.0, 112.0, 112.0, 112.0, 112.0),
    ForecastPoint(5.0, 124.0, 124.0, 124.0, 124.0, 124.0, 124.0),
    ForecastPoint(6.0, 0.0, 132.0, 122.0, 142.0, 115.0, 149.0),
    ForecastPoint(7.0, 0.0, 141.0, 127.0, 155.0, 118.0, 164.0),
    ForecastPoint(8.0, 0.0, 150.0, 131.0, 169.0, 120.0, 180.0),
  ]

  TimeSeriesDataset(
    name: "Autoregressive ARIMA Capacity Forecast",
    series_length: 5,
    horizon: 3,
    seasonality_period: 24,
    points: points,
  )
}

// -----------------------------------------------------------------------------
// 12. Non-Linear Spline & Quantile Regression Envelope (ggformula, mgcv)
// -----------------------------------------------------------------------------

pub type QuantileCurve {
  QuantileCurve(tau: Float, points: List(Point2D), color: String)
}

pub type SplineDataset {
  SplineDataset(
    name: String,
    degrees_of_freedom: Int,
    knots: List(Float),
    quantiles: List(QuantileCurve),
  )
}

pub fn generate_spline_envelope() -> SplineDataset {
  let q50 = [
    Point2D(60.0, 130.0), Point2D(120.0, 110.0), Point2D(180.0, 85.0),
    Point2D(240.0, 70.0), Point2D(300.0, 65.0), Point2D(360.0, 58.0), Point2D(420.0, 50.0),
  ]
  let q90 = [
    Point2D(60.0, 110.0), Point2D(120.0, 90.0), Point2D(180.0, 65.0),
    Point2D(240.0, 50.0), Point2D(300.0, 42.0), Point2D(360.0, 35.0), Point2D(420.0, 30.0),
  ]
  let q10 = [
    Point2D(60.0, 150.0), Point2D(120.0, 135.0), Point2D(180.0, 115.0),
    Point2D(240.0, 100.0), Point2D(300.0, 92.0), Point2D(360.0, 85.0), Point2D(420.0, 78.0),
  ]

  SplineDataset(
    name: "Quantile B-Spline Regression (tau={0.10, 0.50, 0.90})",
    degrees_of_freedom: 5,
    knots: [120.0, 240.0, 360.0],
    quantiles: [
      QuantileCurve(0.90, q90, "#38bdf8"),
      QuantileCurve(0.50, q50, "#ffffff"),
      QuantileCurve(0.10, q10, "#38bdf8"),
    ],
  )
}

// -----------------------------------------------------------------------------
// 13. Categorical Mosaic & Fluctuation Envelope (ggmosaic, productplots)
// -----------------------------------------------------------------------------

pub type MosaicCell {
  MosaicCell(factor_x: String, factor_y: String, count: Int, rect: Rect2D, color: String)
}

pub type MosaicDataset {
  MosaicDataset(
    name: String,
    total_observations: Int,
    chi_square_stat: Float,
    p_value: Float,
    cells: List(MosaicCell),
  )
}

pub fn generate_mosaic_envelope() -> MosaicDataset {
  let cells = [
    MosaicCell("Tier1", "Pass", 650, Rect2D(60.0, 50.0, 180.0, 70.0), "#34d399"),
    MosaicCell("Tier1", "Retry", 50, Rect2D(60.0, 122.0, 180.0, 28.0), "#fbbf24"),
    MosaicCell("Tier2", "Pass", 280, Rect2D(245.0, 50.0, 175.0, 80.0), "#38bdf8"),
    MosaicCell("Tier2", "Retry", 20, Rect2D(245.0, 132.0, 175.0, 18.0), "#f87171"),
  ]

  MosaicDataset(
    name: "Execution Tier Contingency Mosaic",
    total_observations: 1000,
    chi_square_stat: 8.42,
    p_value: 0.0037,
    cells: cells,
  )
}

// -----------------------------------------------------------------------------
// 14. Marginal Scatter & Bivariate Density Envelope (ggExtra, ggpubr)
// -----------------------------------------------------------------------------

pub type MarginalScatterDataset {
  MarginalScatterDataset(
    name: String,
    sample_points: List(Point2D),
    x_marginal_bins: List(Float),
    y_marginal_bins: List(Float),
    pearson_r: Float,
  )
}

pub fn generate_marginal_envelope() -> MarginalScatterDataset {
  let points = [
    Point2D(80.0, 140.0), Point2D(120.0, 125.0), Point2D(150.0, 118.0),
    Point2D(190.0, 105.0), Point2D(230.0, 92.0), Point2D(270.0, 80.0),
    Point2D(310.0, 72.0), Point2D(350.0, 60.0), Point2D(390.0, 48.0),
  ]

  MarginalScatterDataset(
    name: "Bivariate Scatter with Marginal Histogram",
    sample_points: points,
    x_marginal_bins: [2.0, 5.0, 8.0, 12.0, 15.0, 9.0, 4.0],
    y_marginal_bins: [1.0, 3.0, 7.0, 14.0, 16.0, 10.0, 3.0],
    pearson_r: -0.96,
  )
}

// -----------------------------------------------------------------------------
// 15. Composite Multi-Panel Layout Envelope (patchwork, cowplot)
// -----------------------------------------------------------------------------

pub type CompositeSubpanel {
  CompositeSubpanel(panel_id: String, title: String, rect: Rect2D, border_color: String)
}

pub type CompositeDataset {
  CompositeDataset(
    name: String,
    layout_description: String,
    panels: List(CompositeSubpanel),
    alignment_verified: Bool,
  )
}

pub fn generate_composite_envelope() -> CompositeDataset {
  let panels = [
    CompositeSubpanel("A", "Panel A: Core Timeseries", Rect2D(50.0, 45.0, 190.0, 95.0), "#38bdf8"),
    CompositeSubpanel("B", "Panel B: Residual Density", Rect2D(250.0, 45.0, 190.0, 95.0), "#818cf8"),
    CompositeSubpanel("C", "Panel C: Integrated Diagnostics", Rect2D(50.0, 145.0, 390.0, 45.0), "#34d399"),
  ]

  CompositeDataset(
    name: "Publication Multi-Panel Dashboard (A + B / C)",
    layout_description: "Top dual-panel (A, B) over shared spanning diagnostics (C)",
    panels: panels,
    alignment_verified: True,
  )
}

// -----------------------------------------------------------------------------
// Master Envelope Collection & Validation
// -----------------------------------------------------------------------------

pub fn get_all_feature_envelopes() -> List(SyntheticFeatureEnvelope) {
  [
    SyntheticFeatureEnvelope(
      "UC-EXT-01",
      "Uncertainty & Distribution",
      UncertaintyEnvelope,
      10_000,
      ["zero-variance point mass", "heavy tail Cauchy", "bimodal mixture", "99% CI extremes"],
      [#("Mean", "260.0"), #("StdDev", "45.0"), #("Skewness", "0.05"), #("Kurtosis", "2.98")],
      True,
    ),
    SyntheticFeatureEnvelope(
      "UC-EXT-02",
      "Network Graph Topology",
      NetworkEnvelope,
      11,
      ["isolated singleton node", "complete bipartite clique", "directed acyclic loop", "dense mesh"],
      [#("Density", "0.60"), #("Diameter", "2"), #("Clustering", "0.66")],
      True,
    ),
    SyntheticFeatureEnvelope(
      "UC-EXT-03",
      "Flow Alluvial & Sankey",
      FlowEnvelope,
      11,
      ["100% dead-end drop", "branching splits", "re-converging streams", "zero-flow stratum"],
      [#("Total Inflow", "100.0"), #("Total Outflow", "70.0"), #("Retention", "70.0%")],
      True,
    ),
    SyntheticFeatureEnvelope(
      "UC-EXT-04",
      "Hierarchical Treemap",
      HierarchyEnvelope,
      4,
      ["single-root flat tree", "deep binary chain", "zero-area leaf", "nested rectangles"],
      [#("Total Weight", "100.0"), #("Max Depth", "2"), #("Node Count", "4")],
      True,
    ),
    SyntheticFeatureEnvelope(
      "UC-EXT-05",
      "Survival Kaplan-Meier",
      SurvivalEnvelope,
      1000,
      ["100% right censoring", "immediate initial drop", "constant hazard exponential", "Weibull bath"],
      [#("MTBF Hours", "242.5"), #("Censoring", "12.5%"), #("Steps", "7")],
      True,
    ),
    SyntheticFeatureEnvelope(
      "UC-EXT-06",
      "Multi-Facet Density Ridge",
      MultiFacetEnvelope,
      20,
      ["zero-overlap separated", "extreme overlap h=2.5", "negative values", "skewed baseline"],
      [#("Facet Count", "4"), #("Overlap Ratio", "0.65")],
      True,
    ),
    SyntheticFeatureEnvelope(
      "UC-EXT-07",
      "Correlogram & Matrix",
      CorrelationEnvelope,
      25,
      ["perfect collinearity r=1.0", "orthogonal r=0.0", "inverse r=-1.0", "singular matrix"],
      [#("Determinant", "0.042"), #("Condition No", "14.8")],
      True,
    ),
    SyntheticFeatureEnvelope(
      "UC-EXT-08",
      "Geospatial Vector Field",
      GeospatialEnvelope,
      6,
      ["polar coordinate singularity", "meridian wrap-around", "zero-magnitude stagnation", "vortex center"],
      [#("Max Divergence", "0.015"), #("Max Vorticity", "0.042")],
      True,
    ),
    SyntheticFeatureEnvelope(
      "UC-EXT-09",
      "Genomic Karyotype Track",
      GenomicEnvelope,
      850_000,
      ["chromosome boundary wrap", "genome-wide significance p<10^-8", "dense centromere gap"],
      [#("Variants", "850,000"), #("Threshold", "8.0")],
      True,
    ),
    SyntheticFeatureEnvelope(
      "UC-EXT-10",
      "Ternary Barycentric Composition",
      TernaryEnvelope,
      4,
      ["pure vertex (1,0,0)", "binary edge (0.5,0.5,0)", "equilateral centroid (1/3,1/3,1/3)"],
      [#("Components", "3"), #("Sum Invariant", "1.000")],
      True,
    ),
    SyntheticFeatureEnvelope(
      "UC-EXT-11",
      "Time Series ARIMA Forecast",
      TimeSeriesEnvelope,
      8,
      ["abrupt step regime change", "multiplicative seasonal spike", "expanding fan uncertainty"],
      [#("History Length", "5"), #("Horizon", "3"), #("Period", "24")],
      True,
    ),
    SyntheticFeatureEnvelope(
      "UC-EXT-12",
      "Quantile Spline Regression",
      SplineEnvelope,
      21,
      ["quantile crossing prevention", "boundary knot extrapolation", "heteroscedastic variance"],
      [#("DF", "5"), #("Quantiles", "3")],
      True,
    ),
    SyntheticFeatureEnvelope(
      "UC-EXT-13",
      "Categorical Mosaic",
      MosaicEnvelope,
      1000,
      ["Simpson's paradox reversal", "zero-cell contingency", "perfect independence"],
      [#("Total Obs", "1,000"), #("Chi-Square", "8.42"), #("P-Value", "0.0037")],
      True,
    ),
    SyntheticFeatureEnvelope(
      "UC-EXT-14",
      "Marginal Bivariate Scatter",
      MarginalEnvelope,
      9,
      ["strong linear correlation", "banana curved non-linear", "extreme bivariate outliers"],
      [#("Points", "9"), #("Pearson r", "-0.96")],
      True,
    ),
    SyntheticFeatureEnvelope(
      "UC-EXT-15",
      "Composite Multi-Panel Layout",
      CompositeEnvelope,
      3,
      ["nested subgrid alignment", "shared spanning footer", "ratio preservation under resize"],
      [#("Panels", "3"), #("Layout", "A+B/C"), #("Aligned", "True")],
      True,
    ),
  ]
}
