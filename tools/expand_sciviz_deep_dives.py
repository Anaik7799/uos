#!/usr/bin/env python3
"""
Expands extension_deep_dive.gleam with 22 additional bespoke flagship profiles,
bringing the total bespoke flagship count to 52 packages across all categories.
"""

import re
import sys

TARGET_FILE = "/home/an/NAS-setup/uos/apps/cepaf_gleam/src/cepaf_gleam/sciviz/extension_deep_dive.gleam"

with open(TARGET_FILE, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Update the case statement in build_deep_dive
old_case = """    "treemapify" -> treemapify_deep_dive(ext)
    "ggstatsplot" -> ggstatsplot_deep_dive(ext)
    _ -> build_category_deep_dive(ext)"""

new_cases = """    "treemapify" -> treemapify_deep_dive(ext)
    "ggstatsplot" -> ggstatsplot_deep_dive(ext)
    "ggridges" -> ggridges_deep_dive(ext)
    "ggraph" -> ggraph_deep_dive(ext)
    "gganimate" -> gganimate_deep_dive(ext)
    "gghalves" -> gghalves_deep_dive(ext)
    "ggnewscale" -> ggnewscale_deep_dive(ext)
    "gginnards" -> gginnards_deep_dive(ext)
    "ggpubr" -> ggpubr_deep_dive(ext)
    "ggdendro" -> ggdendro_deep_dive(ext)
    "ggh4x" -> ggh4x_deep_dive(ext)
    "ggmagnify" -> ggmagnify_deep_dive(ext)
    "gganatogram" -> gganatogram_deep_dive(ext)
    "ggTimeSeries" -> ggtimeseries_deep_dive(ext)
    "ggChernoff" -> ggchernoff_deep_dive(ext)
    "ggnetwork" -> ggnetwork_deep_dive(ext)
    "ggdag" -> ggdag_deep_dive(ext)
    "see" -> see_deep_dive(ext)
    "modelbased" -> modelbased_deep_dive(ext)
    "bayesplot" -> bayesplot_deep_dive(ext)
    "ggparty" -> ggparty_deep_dive(ext)
    "gggenes" -> gggenes_deep_dive(ext)
    "ggalign" -> ggalign_deep_dive(ext)
    "ggblanket" -> ggblanket_deep_dive(ext)
    _ -> build_category_deep_dive(ext)"""

if old_case not in content:
    print("ERROR: old_case not found in file!")
    sys.exit(1)

content = content.replace(old_case, new_cases, 1)

# 2. Add the 22 new flagship functions before `// Category-Informed Deep-Dive Generator (Full 16-Category Coverage)`
anchor = "// Category-Informed Deep-Dive Generator (Full 16-Category Coverage)"
if anchor not in content:
    print("ERROR: anchor not found in file!")
    sys.exit(1)

new_functions = """fn ggridges_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Uncertainty & Distribution",
    url: ext.url,
    key_features: [
      "Ridgeline Density Tracks: Partially overlapping elevation ridges for distribution comparison",
      "Elevation gradient fills mapping statistical quantiles or probability densities",
      "Scale height parameter controlling inter-ridge overlap factor without visual occlusion",
      "Jittered point clouds along the baseline displaying raw underlying observations",
      "Support for multiple probability distribution models (Gaussian, log-normal, Cauchy)",
    ],
    visual_graph_types: [
      "Overlapping Elevation Ridgeline Plots",
      "Quantile-Shaded Density Ribbons",
      "Seasonal Temperature Elevation Ridges",
      "Multi-Sensor Jittered Density Tracks",
    ],
    dataset_name: "NOAA Global Historical Climatology Network (climatology_120k)",
    dataset_record_count: 120_000,
    dataset_dimensions: [
      "station_id", "month", "temp_celsius", "elevation_m", "quantile_bracket",
    ],
    dataset_schema_summary:
      "120,000 global weather station temperature distributions evaluated across 12 monthly overlapping ridgeline tracks.",
    bdd_scenarios: [
      "Scenario: Calculate kernel density estimates across 12 overlapping monthly elevation ridges",
      "Scenario: Apply quantile shading gradient across 25th, 50th, and 75th percentiles",
      "Scenario: Verify overlap scaling factor maintains label readability on high-density peaks",
    ],
    svg_rich_aspect: generate_uncertainty_svg(ext.name, "Uncertainty & Distribution"),
    fractal_coordinates: "#fractal-l2 #fractal-l3",
  )
}

fn ggraph_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Network & Graph Topology",
    url: ext.url,
    key_features: [
      "Relational Graph Layouts: Circular, dendrogram, hive, and force-directed algorithms",
      "Edge bundling geometry routing high-density links along shared spline paths",
      "Hierarchical tree and nested node-link packing representations",
      "Node centrality color scales and degree-weighted vertex sizing",
      "Integration with tidygraph relational data structures",
    ],
    visual_graph_types: [
      "Circular Concentric Network Graphs",
      "Hierarchical Edge-Bundled Trees",
      "Hive Plot Tri-Axis Coordinate Networks",
      "Force-Directed Dynamic Spring Layouts",
    ],
    dataset_name: "Autonomous Agent Mesh Topology & Link Telemetry (uos_mesh_85k)",
    dataset_record_count: 85_000,
    dataset_dimensions: [
      "source_node", "target_node", "link_type", "weight", "latency_us", "cluster_id",
    ],
    dataset_schema_summary:
      "85,000 peer-to-peer telemetry links mapped to circular concentric and force-directed graph representations.",
    bdd_scenarios: [
      "Scenario: Compute circular chord coordinates for 128 distributed peer nodes",
      "Scenario: Bundle edges connecting high-degree cluster hubs to reduce visual clutter",
      "Scenario: Scale node circle radius proportionally to eigenvector centrality score",
    ],
    svg_rich_aspect: generate_network_svg(ext.name, "Network & Graph Topology"),
    fractal_coordinates: "#fractal-l3 #fractal-l6",
  )
}

fn gganimate_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Flow, Alluvial & Sankey",
    url: ext.url,
    key_features: [
      "Kinematic Frame Transitions: State tweens interpolating smooth temporal kinematics",
      "Shadow trails (wake, mark) revealing historical trajectory paths of moving coordinates",
      "Dynamic view limits tracking roaming focus windows across animated dimensions",
      "Time-stepped aesthetic transitions with linear, cubic, and elastic easing functions",
      "Deterministic frame index generation ensuring reproducible rendering pipelines",
    ],
    visual_graph_types: [
      "Kinematic Particle Trajectory Animations",
      "Time-Varying Phase Space Orbits",
      "Dynamic Bar Chart Race Progressions",
      "Fading Historical Wake Traces",
    ],
    dataset_name: "High-Frequency Kinematic Telemetry Stream (kinematics_140k)",
    dataset_record_count: 140_000,
    dataset_dimensions: [
      "timestamp_ms", "frame_idx", "coord_x", "coord_y", "velocity", "acceleration",
    ],
    dataset_schema_summary:
      "140,000 sub-millisecond kinematic states evaluating particle trajectories with fading wake trails.",
    bdd_scenarios: [
      "Scenario: Interpolate intermediate particle positions using cubic spline easing",
      "Scenario: Render fading wake shadow with decaying alpha across 10 previous frames",
      "Scenario: Reframe coordinate viewport dynamically around active cluster centroid",
    ],
    svg_rich_aspect: generate_alluvial_svg(ext.name, "Flow, Alluvial & Sankey"),
    fractal_coordinates: "#fractal-l2 #fractal-l4",
  )
}

fn gghalves_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Uncertainty & Distribution",
    url: ext.url,
    key_features: [
      "Hybrid Half-Plots: Left-half violin density paired with right-half jitter points",
      "Asymmetric boxplot halves displaying summary statistics beside raw data",
      "Customizable horizontal displacement offsets preventing geom collisions",
      "Seamless integration with ggplot2 grouping and facet wrapping",
      "Enhanced visual clarity for bimodal and skewed distribution inspection",
    ],
    visual_graph_types: [
      "Asymmetric Raincloud Hybrids",
      "Half-Boxplot Half-Jitter Distributions",
      "Split Violin Comparative Cohort Plots",
      "Bimodal Phenotype Half-Density Visualizers",
    ],
    dataset_name: "MIMIC-III ICU Vital Signs Clinical Registry (vitals_110k)",
    dataset_record_count: 110_000,
    dataset_dimensions: [
      "subject_id", "vital_metric", "reading_val", "cohort_group", "is_outlier",
    ],
    dataset_schema_summary:
      "110,000 patient vital measurements displayed as asymmetric half-violins and half-boxplots.",
    bdd_scenarios: [
      "Scenario: Render left half-violin with kernel density bandwidth = 1.2",
      "Scenario: Render right half-boxplot aligned along central grouping coordinate",
      "Scenario: Offset raw scatter points to avoid occlusion with distribution envelope",
    ],
    svg_rich_aspect: generate_uncertainty_svg(ext.name, "Uncertainty & Distribution"),
    fractal_coordinates: "#fractal-l2 #fractal-l3",
  )
}

fn ggnewscale_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Theming, Palettes & Aesthetics",
    url: ext.url,
    key_features: [
      "Multiple Color Scales: Inserting new_scale_color() to reset scale mappings",
      "Independent legends generated for each layered scale segment",
      "Support for multiple fill scales across layered geospatial polygons",
      "Prevention of aesthetic collisions across heterogeneous geom tiers",
      "Pure functional declarative layering without mutating underlying grobs",
    ],
    visual_graph_types: [
      "Dual-Scale Overlay Heatmaps",
      "Multi-Palette Geospatial Boundary Plots",
      "Stratified Multi-Metric Scatter Displays",
      "Independent Fill and Color Diagnostic Boards",
    ],
    dataset_name: "Multi-Sensor Environmental Monitoring Grid (multisensor_90k)",
    dataset_record_count: 90_000,
    dataset_dimensions: [
      "sensor_id", "temperature_c", "humidity_pct", "co2_ppm", "battery_v",
    ],
    dataset_schema_summary:
      "90,000 multi-variable sensor readings mapped simultaneously to independent color and fill scales.",
    bdd_scenarios: [
      "Scenario: Reset fill scale aesthetic using new_scale_fill() between layers",
      "Scenario: Render distinct legends for temperature (Plasma) and humidity (Viridis)",
      "Scenario: Verify zero aesthetic bleed between successive geom declarations",
    ],
    svg_rich_aspect: generate_theming_svg(ext.name, "Theming, Palettes & Aesthetics"),
    fractal_coordinates: "#fractal-l2 #fractal-l3",
  )
}

fn gginnards_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Introspection & Layer Editing",
    url: ext.url,
    key_features: [
      "AST Scene Graph Introspection: Inspecting and manipulating ggproto layer hierarchies",
      "Selective layer deletion, insertion, and substitution at arbitrary indices",
      "Extracting computed stat data frames from evaluated plot objects",
      "Auditing aesthetic mappings and parameter settings across complex plots",
      "Zero-downtime hot modification of visualization scene graphs",
    ],
    visual_graph_types: [
      "Scene Graph Abstract Syntax Tree Hierarchy",
      "Computed Stat Data Inspection Tables",
      "Layer Transformation Diff Panels",
      "Auditing Diagnostic Visual Trees",
    ],
    dataset_name: "Grammar of Graphics AST Scene Graph Mutations (ast_mutations_40k)",
    dataset_record_count: 40_000,
    dataset_dimensions: [
      "plot_id", "layer_index", "geom_class", "stat_class", "data_rows", "mapping_keys",
    ],
    dataset_schema_summary:
      "40,000 plot layer modifications evaluating runtime scene graph manipulation and computed stat extraction.",
    bdd_scenarios: [
      "Scenario: Inspect plot layers and extract computed stat data at index 1",
      "Scenario: Substitute geom_point with geom_smooth dynamically without full rebuild",
      "Scenario: Audit aesthetic mappings to ensure required X and Y keys are present",
    ],
    svg_rich_aspect: generate_introspection_svg(ext.name, "Introspection & Layer Editing"),
    fractal_coordinates: "#fractal-l3 #fractal-l5",
  )
}

fn ggpubr_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Statistical Diagnosis & Inference",
    url: ext.url,
    key_features: [
      "Publication-Ready Statistical Figures: Automated comparison brackets and p-value labels",
      "Parametric and non-parametric tests (t-test, Wilcoxon, ANOVA, Kruskal-Wallis)",
      "Arranging multiple plots into publication-quality scientific grids",
      "Standard journal theme styling (Nature, Science, Lancet) with minimal ink",
      "Correlation scatter plots with automatic regression equations and R² badges",
    ],
    visual_graph_types: [
      "Significance-Bracketed Comparison Boxplots",
      "Publication-Styled Multi-Panel Figures",
      "Annotated Linear Regression Diagnostic Plots",
      "Standardized Clinical Cohort Bar Charts",
    ],
    dataset_name: "Oncology Drug Efficacy Comparative Cohort (drug_trials_80k)",
    dataset_record_count: 80_000,
    dataset_dimensions: [
      "patient_id", "treatment_arm", "biomarker_level", "tumor_reduction_pct", "p_value",
    ],
    dataset_schema_summary:
      "80,000 clinical observation rows comparing therapeutic response across treatment arms with automated statistical tests.",
    bdd_scenarios: [
      "Scenario: Compute Wilcoxon rank-sum test between control and treatment groups",
      "Scenario: Render comparison brackets with significance stars above boxplot whiskers",
      "Scenario: Export multi-panel publication figure formatted for Lancet submission",
    ],
    svg_rich_aspect: generate_statistical_svg(ext.name, "Statistical Diagnosis & Inference"),
    fractal_coordinates: "#fractal-l2 #fractal-l3 #fractal-l5",
  )
}

fn ggdendro_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Hierarchical Partition",
    url: ext.url,
    key_features: [
      "Hierarchical Clustering Dendrograms: Extracting tree coordinates from hclust objects",
      "Rectangular and triangular tree branch segments with customizable branch heights",
      "Integration of cluster dendrograms beside expression heatmaps",
      "Leaf node label alignment and categorical cluster color coding",
      "Support for agglomerative and divisive clustering linkages",
    ],
    visual_graph_types: [
      "Agglomerative Cluster Dendrograms",
      "Heatmap-Bordering Linkage Trees",
      "Cut-Tree Cluster Group Highlight Panels",
      "Phylogenetic Hierarchical Branch Plots",
    ],
    dataset_name: "Single-Cell Transcriptomic Hierarchical Clustering (sc_cluster_70k)",
    dataset_record_count: 70_000,
    dataset_dimensions: [
      "cell_id", "cluster_id", "branch_height", "parent_cluster", "marker_gene",
    ],
    dataset_schema_summary:
      "70,000 single-cell profiles mapped to hierarchical dendrogram trees detailing cell-state differentiation.",
    bdd_scenarios: [
      "Scenario: Extract branch line segment coordinates from Ward linkage matrix",
      "Scenario: Align dendrogram leaf tips to matching rows in expression heatmap",
      "Scenario: Color tree branches by k-means cluster assignment (k = 5)",
    ],
    svg_rich_aspect: generate_hierarchical_svg(ext.name, "Hierarchical Partition"),
    fractal_coordinates: "#fractal-l2 #fractal-l3",
  )
}

fn ggh4x_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Multi-Scale & Coordinates",
    url: ext.url,
    key_features: [
      "Extended Facet Strips: Nested facet labels with hierarchical grouping headers",
      "Independent scale transformations and tick styling per facet panel",
      "Custom guide axes with truncated, mirrored, and manual break positions",
      "Multi-panel sizing control setting arbitrary width/height ratios",
      "Force-balance aspect ratio preservation across facet matrices",
    ],
    visual_graph_types: [
      "Nested Hierarchical Facet Grids",
      "Custom Truncated Axis Visualizers",
      "Heterogeneous Per-Panel Scale Plots",
      "Complex Multi-Facet Biological Panels",
    ],
    dataset_name: "Semiconductor Multi-Chamber Fab Metrology (semifab_160k)",
    dataset_record_count: 160_000,
    dataset_dimensions: [
      "wafer_id", "chamber_tier1", "chamber_tier2", "etch_rate_nm_s", "uniformity",
    ],
    dataset_schema_summary:
      "160,000 wafer processing records displayed across nested multi-tier facet strips with per-chamber scales.",
    bdd_scenarios: [
      "Scenario: Render nested facet strip headers with shared upper-tier category spanning",
      "Scenario: Apply independent logarithmic y-scale to individual facet sub-panels",
      "Scenario: Truncate axis line to exact data range avoiding empty tick mark extensions",
    ],
    svg_rich_aspect: generate_multiscale_svg(ext.name, "Multi-Scale & Coordinates"),
    fractal_coordinates: "#fractal-l2 #fractal-l3",
  )
}

fn ggmagnify_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Multi-Scale & Coordinates",
    url: ext.url,
    key_features: [
      "Inset Magnifying Glass: Zooming in on high-density coordinate sub-regions",
      "Connecting leader lines projecting source bounding box to magnified loupe",
      "Customizable magnification factor (e.g. 2x, 5x, 10x) with separate aspect ratios",
      "Circular and rectangular loupe viewports with adjustable border styling",
      "Zero distortion of surrounding global plot elements",
    ],
    visual_graph_types: [
      "Magnified Cluster Inset Viewports",
      "Micro-Structure Loupe Inspection Displays",
      "Astrometric Dense Field Insets",
      "ECG Waveform Peak Inset Magnifiers",
    ],
    dataset_name: "Deep Space Astrometry & Star Cluster Survey (astrometry_130k)",
    dataset_record_count: 130_000,
    dataset_dimensions: [
      "star_id", "ra_deg", "dec_deg", "flux_mag", "parallax_mas", "is_dense_core",
    ],
    dataset_schema_summary:
      "130,000 stellar coordinates with magnified insets detailing dense globular cluster cores.",
    bdd_scenarios: [
      "Scenario: Define target zoom bounding box [X1, Y1, X2, Y2] and loupe placement",
      "Scenario: Project leader lines from source bounding box corners to magnified inset",
      "Scenario: Render high-resolution star points inside loupe with 5x magnification",
    ],
    svg_rich_aspect: generate_multiscale_svg(ext.name, "Multi-Scale & Coordinates"),
    fractal_coordinates: "#fractal-l2 #fractal-l4",
  )
}

fn gganatogram_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Spatial & Vector Field",
    url: ext.url,
    key_features: [
      "Biological Anatomy Schematics: Human, mouse, and plant modular anatomical diagrams",
      "Color-coding organs and tissue compartments based on expression levels or pathology",
      "Male, female, and organism-specific developmental stage templates",
      "Multi-organ expression comparison panels with calibrated color scales",
      "SVG vector tissue boundaries supporting interactive hover inspection",
    ],
    visual_graph_types: [
      "Human Body Multi-Organ Expression Anatograms",
      "Murine Model Tissue Pathology Maps",
      "Botanical Cellular Compartment Displays",
      "Comparative Organ-Level Drug Bio-Distribution Plots",
    ],
    dataset_name: "Human Protein Atlas Tissue Specificity Corpus (anatogram_95k)",
    dataset_record_count: 95_000,
    dataset_dimensions: [
      "gene_id", "organ_system", "tissue_name", "expression_tpm", "cell_type",
    ],
    dataset_schema_summary:
      "95,000 gene expression observations mapped directly to modular human organ silhouettes.",
    bdd_scenarios: [
      "Scenario: Map expression levels to human body organ SVG polygon fills",
      "Scenario: Highlight target brain, liver, and kidney tissues with high-contrast palette",
      "Scenario: Verify tissue polygon coordinates align seamlessly on base anatomical silhouette",
    ],
    svg_rich_aspect: generate_spatial_svg(ext.name, "Spatial & Vector Field"),
    fractal_coordinates: "#fractal-l2 #fractal-l3",
  )
}

fn ggtimeseries_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Quality Control & Time-Series",
    url: ext.url,
    key_features: [
      "Calendar Heatmaps: Calendar-grid visualization of daily event frequencies",
      "Water-level time-series plots with dynamic threshold flooding fills",
      "Seasonal trend decomposition displaying trend, seasonal, and residual components",
      "Multi-resolution time grouping (hourly, daily, weekly, quarterly)",
      "High-density financial and server log timeline representation",
    ],
    visual_graph_types: [
      "Yearly Calendar Heatmap Grids",
      "Water-Level Threshold Flood Plots",
      "STL Seasonal Decomposition Graphs",
      "High-Frequency Financial Tick Streams",
    ],
    dataset_name: "Server Infrastructure 365-Day Incident Telemetry (server_incidents_105k)",
    dataset_record_count: 105_000,
    dataset_dimensions: [
      "timestamp", "day_of_year", "hour", "incident_count", "severity", "cpu_peak_pct",
    ],
    dataset_schema_summary:
      "105,000 incident events represented as calendar heatmaps and water-level time-series.",
    bdd_scenarios: [
      "Scenario: Map daily incident counts to 52-week calendar grid with month separators",
      "Scenario: Shade water-level time series area above 90% CPU threshold in warning red",
      "Scenario: Decompose seasonal periodic pattern from long-term infrastructure drift",
    ],
    svg_rich_aspect: generate_qc_svg(ext.name, "Quality Control & Time-Series"),
    fractal_coordinates: "#fractal-l2 #fractal-l4",
  )
}

fn ggchernoff_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Theming, Palettes & Aesthetics",
    url: ext.url,
    key_features: [
      "Chernoff Faces: Multi-dimensional data mapped to human facial features",
      "Parametric mapping of variables to eye size, smile curvature, face shape, and nose width",
      "Rapid holistic visual recognition of complex multi-attribute states",
      "Clustering analysis comparing multivariate similarity via facial expressions",
      "Calibrated feature scaling preventing visual bias towards dominant facial metrics",
    ],
    visual_graph_types: [
      "Multivariate Chernoff Face Grids",
      "Holistic System Health Facial Dashboards",
      "Multi-Attribute Portfolio Face Glyphs",
      "Subjective State Classification Face Boards",
    ],
    dataset_name: "Autonomous Agent Holistic Health States (chernoff_agent_45k)",
    dataset_record_count: 45_000,
    dataset_dimensions: [
      "agent_id", "smile_happiness", "eye_alertness", "face_stress", "eyebrow_slant",
    ],
    dataset_schema_summary:
      "45,000 agent health evaluations mapped to Chernoff face features for rapid cognitive assessment.",
    bdd_scenarios: [
      "Scenario: Map agent memory load to face height and queue length to smile curvature",
      "Scenario: Render facial feature SVG arcs with smooth bezier curves",
      "Scenario: Verify extreme stress states trigger visible frown and narrow eye glyphs",
    ],
    svg_rich_aspect: generate_theming_svg(ext.name, "Theming, Palettes & Aesthetics"),
    fractal_coordinates: "#fractal-l2 #fractal-l5",
  )
}

fn ggnetwork_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Network & Graph Topology",
    url: ext.url,
    key_features: [
      "Tidy Network Graphing: Direct ggplot2 geoms for nodes, edges, and arrows",
      "Curved bidirectional edge arrows avoiding overlapping reverse pathways",
      "Edge weight mapping to linewidth and transparency gradients",
      "Node attribute mapping to shape, fill, and size aesthetics",
      "Seamless integration with igraph and network R packages",
    ],
    visual_graph_types: [
      "Curved Multi-Edge Network Topologies",
      "Weighted Flow Network Routing Displays",
      "Decentralized Swarm Communication Meshes",
      "Social Interaction Directed Graphs",
    ],
    dataset_name: "Distributed P2P Communication Link Graphs (p2p_network_80k)",
    dataset_record_count: 80_000,
    dataset_dimensions: [
      "node_a", "node_b", "bandwidth_mbps", "is_bidirectional", "link_status",
    ],
    dataset_schema_summary:
      "80,000 peer communication events evaluating curved directional edges and vertex properties.",
    bdd_scenarios: [
      "Scenario: Compute quadratic bezier curve offsets for bidirectional edge pairs",
      "Scenario: Scale edge linewidth continuously based on observed bandwidth throughput",
      "Scenario: Highlight isolated sub-networks lacking consensus connections",
    ],
    svg_rich_aspect: generate_network_svg(ext.name, "Network & Graph Topology"),
    fractal_coordinates: "#fractal-l3 #fractal-l6",
  )
}

fn ggdag_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Network & Graph Topology",
    url: ext.url,
    key_features: [
      "Directed Acyclic Graphs (DAGs): Visualizing causal inference relationships",
      "Confounder and collider node identification with automated coloring",
      "Instrumental variable detection and minimal adjustment set computation",
      "Backdoor and frontdoor path isolation preventing spurious correlation bias",
      "Clear visual distinction between exposures, outcomes, and latent variables",
    ],
    visual_graph_types: [
      "Causal Inference Directed Acyclic Graphs",
      "Confounder & Collider Diagnostic Diagrams",
      "Epidemiological Risk Factor Flow Trees",
      "Minimal Adjustment Set Path Networks",
    ],
    dataset_name: "Epidemiological Causal Inference Pathway Corpus (causal_dag_60k)",
    dataset_record_count: 60_000,
    dataset_dimensions: [
      "variable_id", "node_role", "path_type", "is_confounder", "adjustment_status",
    ],
    dataset_schema_summary:
      "60,000 causal DAG path evaluations isolating confounding bias and identifying minimal adjustment sets.",
    bdd_scenarios: [
      "Scenario: Identify backdoor confounding paths connecting exposure to outcome",
      "Scenario: Color minimal adjustment set nodes in warning amber with thick borders",
      "Scenario: Verify graph topology has zero directed cycles (strictly acyclic)",
    ],
    svg_rich_aspect: generate_network_svg(ext.name, "Network & Graph Topology"),
    fractal_coordinates: "#fractal-l3 #fractal-l5",
  )
}

fn see_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Statistical Diagnosis & Inference",
    url: ext.url,
    key_features: [
      "Model Visualization Engine: Visualizing parameters from easystats ecosystem",
      "Posterior distribution intervals, point estimates, and ROPE zones",
      "Model performance radar plots and multi-metric comparison bars",
      "Check model diagnostics (collinearity, normality, heteroscedasticity)",
      "Consistent cohesive palette and typography styling across all models",
    ],
    visual_graph_types: [
      "Model Parameter Posterior Forest Plots",
      "Multivariate Model Performance Radar Charts",
      "Residual Normality & Homoscedasticity Visualizers",
      "ROPE (Region of Practical Equivalence) Diagnostics",
    ],
    dataset_name: "Bayesian Multi-Level Regression Diagnostics (easystats_75k)",
    dataset_record_count: 75_000,
    dataset_dimensions: [
      "model_id", "param_name", "median_est", "ci_low", "ci_high", "rope_percentage",
    ],
    dataset_schema_summary:
      "75,000 model evaluation metrics displaying posterior parameter distributions and diagnostic checks.",
    bdd_scenarios: [
      "Scenario: Compute 95% Highest Density Interval (HDI) for model regression coefficients",
      "Scenario: Highlight Region of Practical Equivalence (ROPE) with shaded vertical band",
      "Scenario: Render multi-panel diagnostic figure checking collinearity and residual variance",
    ],
    svg_rich_aspect: generate_statistical_svg(ext.name, "Statistical Diagnosis & Inference"),
    fractal_coordinates: "#fractal-l2 #fractal-l5",
  )
}

fn modelbased_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Statistical Diagnosis & Inference",
    url: ext.url,
    key_features: [
      "Model-Based Predictions: Estimated marginal means and conditional slopes",
      "Nonlinear spline and polynomial prediction curves with confidence bands",
      "Counterfactual simulation lines evaluating hypothetical intervention impacts",
      "Interaction contrast plots showing slope divergence across moderator levels",
      "Seamless integration with GLM, GAM, and Bayesian regression objects",
    ],
    visual_graph_types: [
      "Estimated Marginal Means Interaction Plots",
      "Nonlinear Spline Prediction Trajectories",
      "Conditional Slope Contrast Visualizers",
      "Counterfactual Outcome Scenario Bands",
    ],
    dataset_name: "Clinical Drug Dosage Response Curves (dosage_response_85k)",
    dataset_record_count: 85_000,
    dataset_dimensions: [
      "dose_mg", "predicted_response", "ci_95_low", "ci_95_high", "age_bracket",
    ],
    dataset_schema_summary:
      "85,000 predicted clinical outcomes evaluated across drug dose levels and patient demographics.",
    bdd_scenarios: [
      "Scenario: Compute model predictions and 95% delta-method confidence intervals",
      "Scenario: Render conditional slope lines for three interaction moderator levels",
      "Scenario: Display counterfactual trajectories showing expected survival gains",
    ],
    svg_rich_aspect: generate_statistical_svg(ext.name, "Statistical Diagnosis & Inference"),
    fractal_coordinates: "#fractal-l2 #fractal-l5",
  )
}

fn bayesplot_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Uncertainty & Distribution",
    url: ext.url,
    key_features: [
      "MCMC Diagnostic Plots: Markov Chain Monte Carlo trace lines and rank histograms",
      "Posterior density intervals with shaded central 50% and outer 90% bands",
      "Energy transition distribution overlays checking HMC sampler convergence",
      "Autocorrelation step functions diagnosing parameter chain mixing speed",
      "Posterior predictive check (PPC) overlays comparing observed data to replicates",
    ],
    visual_graph_types: [
      "MCMC Multi-Chain Parameter Trace Plots",
      "Posterior Predictive Distribution Overlays",
      "Hamiltonian Energy Transition Histograms",
      "Chain Autocorrelation Decay Curves",
    ],
    dataset_name: "Hamiltonian Monte Carlo Convergence Diagnostics (hmc_mcmc_125k)",
    dataset_record_count: 125_000,
    dataset_dimensions: [
      "chain", "iteration", "parameter", "val", "divergence_flag", "energy",
    ],
    dataset_schema_summary:
      "125,000 HMC iterations evaluating convergence, chain mixing, and energy distribution stability.",
    bdd_scenarios: [
      "Scenario: Draw 4 parallel MCMC chain trace lines with distinct color palette",
      "Scenario: Highlight divergent transitions with red vertical marker spikes",
      "Scenario: Compare observed empirical density with 50 posterior predictive replicates",
    ],
    svg_rich_aspect: generate_uncertainty_svg(ext.name, "Uncertainty & Distribution"),
    fractal_coordinates: "#fractal-l2 #fractal-l4 #fractal-l5",
  )
}

fn ggparty_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Hierarchical Partition",
    url: ext.url,
    key_features: [
      "Recursive Partitioning Decision Trees: Tree structures from partykit models",
      "Embedded terminal subgroup plots (boxplots, bar charts, scatter plots in leaves)",
      "Inner split condition labels displaying variable names and threshold values",
      "P-value and test statistic annotations at each decision node junction",
      "Customizable edge styles, node shapes, and horizontal/vertical orientations",
    ],
    visual_graph_types: [
      "Decision Trees with Embedded Leaf Plots",
      "Subgroup Classification Partition Trees",
      "Survival Tree Terminal Hazard Graphs",
      "Regression Tree Stepwise Mean Forecasts",
    ],
    dataset_name: "Patient Stratification Decision Tree Corpus (decision_tree_65k)",
    dataset_record_count: 65_000,
    dataset_dimensions: [
      "node_id", "split_var", "split_val", "p_val", "is_terminal", "sample_n",
    ],
    dataset_schema_summary:
      "65,000 clinical decision rows evaluating recursive partitioning trees with leaf distributions.",
    bdd_scenarios: [
      "Scenario: Render recursive decision tree branches with split threshold labels",
      "Scenario: Embed miniature boxplots inside terminal leaf nodes displaying subgroup response",
      "Scenario: Calculate p-value for split significance and format above branch connector",
    ],
    svg_rich_aspect: generate_hierarchical_svg(ext.name, "Hierarchical Partition"),
    fractal_coordinates: "#fractal-l2 #fractal-l3",
  )
}

fn gggenes_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Bioinformatics & Genomics",
    url: ext.url,
    key_features: [
      "Gene Arrow Tracks: Arrow-shaped polygon glyphs displaying gene genomic locations",
      "Directional arrowheads indicating 5'-to-3' or 3'-to-5' transcription strands",
      "Sub-gene segment rendering detailing exon, intron, and promoter domains",
      "Operon and gene cluster alignment across multiple bacterial or viral genomes",
      "Dynamic label placement within or above gene arrows with automatic fitting",
    ],
    visual_graph_types: [
      "Directional Gene Arrow Genomic Tracks",
      "Multi-Genome Operon Synteny Diagrams",
      "Exon-Intron Splice Variant Silhouettes",
      "Bacterial Biosynthetic Gene Cluster Maps",
    ],
    dataset_name: "Comparative Microbial Genomic Synteny Tracks (synteny_genes_70k)",
    dataset_record_count: 70_000,
    dataset_dimensions: [
      "genome_id", "gene_id", "start_bp", "end_bp", "strand", "feature_type", "color_code",
    ],
    dataset_schema_summary:
      "70,000 gene coordinate features displayed as directional arrows with exon/intron annotations.",
    bdd_scenarios: [
      "Scenario: Render gene arrow polygon pointing right for positive strand (+) features",
      "Scenario: Render gene arrow polygon pointing left for negative strand (-) features",
      "Scenario: Align gene cluster synteny across 4 bacterial genomes to reference locus",
    ],
    svg_rich_aspect: generate_genomics_svg(ext.name, "Bioinformatics & Genomics"),
    fractal_coordinates: "#fractal-l2 #fractal-l3",
  )
}

fn ggalign_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Composite & Multi-Panel",
    url: ext.url,
    key_features: [
      "Multi-Track Genomic Alignment: Aligning diverse plots to shared genomic or matrix axes",
      "Hierarchical dendrograms aligned to top and left borders of complex heatmaps",
      "Multi-omics side-car panels displaying bar charts, line tracks, and point annotations",
      "Exact coordinate synchronization across heterogeneous plot engines",
      "Dynamic panel ordering preserving clustered row and column relationships",
    ],
    visual_graph_types: [
      "Multi-Track Aligned Heatmap Figures",
      "Multi-Omic Integrated Epigenetic Displays",
      "Synchronized Coordinate Side-Car Panels",
      "Clustered Matrix Bordering Visualizers",
    ],
    dataset_name: "Multi-Omics Integrated Cancer Epigenome Matrix (multiomics_135k)",
    dataset_record_count: 135_000,
    dataset_dimensions: [
      "patient_id", "gene_symbol", "methylation_beta", "copy_number", "expression_log2",
    ],
    dataset_schema_summary:
      "135,000 multi-omics observations aligned across central heatmap, dendrogram, and side tracks.",
    bdd_scenarios: [
      "Scenario: Synchronize X-axis coordinates between top dendrogram and central heatmap",
      "Scenario: Align right-side clinical covariate bar charts with matching matrix rows",
      "Scenario: Maintain exact pixel registration across 5 combined plot viewports",
    ],
    svg_rich_aspect: generate_composite_svg(ext.name, "Composite & Multi-Panel"),
    fractal_coordinates: "#fractal-l2 #fractal-l3",
  )
}

fn ggblanket_deep_dive(ext: ExtensionMetadata) -> ExtensionDeepDive {
  ExtensionDeepDive(
    name: ext.name,
    author: ext.author,
    category: ext.category,
    category_name: "Theming, Palettes & Aesthetics",
    url: ext.url,
    key_features: [
      "Opinionated Fast Visualizations: Clean simplified API wrapper around ggplot2",
      "Automated intelligent aesthetic mapping and legend generation",
      "Built-in professional typography hierarchy and clean dark/light themes",
      "Automatic color palette selection calibrated for high data visibility",
      "Rapid prototyping producing publication-grade figures in single-line calls",
    ],
    visual_graph_types: [
      "Clean Opinionated Scatter-Boxplot Hybrids",
      "Automated Fast-Prototyping Figures",
      "High-Contrast Minimalist Aesthetic Panels",
      "Zero-Configuration Scientific Data Boards",
    ],
    dataset_name: "Rapid Scientific Prototyping Benchmark Corpus (prototyping_50k)",
    dataset_record_count: 50_000,
    dataset_dimensions: [
      "benchmark_id", "geom_type", "arg_count", "compilation_ms", "visual_clarity_score",
    ],
    dataset_schema_summary:
      "50,000 rapid prototyping evaluations measuring figure readability and ergonomic speed.",
    bdd_scenarios: [
      "Scenario: Generate publication-ready scatter plot using single gg_point() wrapper call",
      "Scenario: Automatically assign high-contrast color palette based on factor level count",
      "Scenario: Apply minimalist theme with calibrated font hierarchy and subtle gridlines",
    ],
    svg_rich_aspect: generate_theming_svg(ext.name, "Theming, Palettes & Aesthetics"),
    fractal_coordinates: "#fractal-l2 #fractal-l3",
  )
}
"""

content = content.replace(anchor, new_functions + "\n" + anchor, 1)

with open(TARGET_FILE, "w", encoding="utf-8") as f:
    f.write(content)

print("SUCCESS: 22 bespoke flagship profiles added to extension_deep_dive.gleam!")
