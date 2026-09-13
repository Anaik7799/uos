//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/sciviz/extension_features</module></identity>
////   <fractal-topology><layer>L2_COMPONENT..L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-SCIVIZ-001, SC-CHECKLIST-001, SC-INTENT-ATLAS-001</stamp-controls></compliance>
//// </c3i-module>
////
//// 1x1 Full Fractal Feature Map Specification & Comprehensive Profile Substrate
//// for all 167 Registered ggplot2 Extensions in the Gallery.
//// Describes Features Offered, Fractal Coordinates, Technical Aspects, Functional
//// Aspects, and UI/UX Ergonomics with Zero-Muda purity (Pure Gleam on BEAM).

import cepaf_gleam/sciviz/extension_catalog.{
  type ExtensionMetadata, BioinformaticsGenomics,
  CompositeMultiPanel, DimensionalityReduction, FlowAlluvialSankey,
  HierarchicalPartition, IntrospectionLayerEditing, MultiScaleCoordinate,
  NetworkGraphTopology, PatternFilterShader, QualityControlTimeSeries,
  SpatialVectorField, StatisticalDiagnosisInference, ThemingPaletteAesthetic,
  ThreeDimensionalProjection, TypographyTextRepel, UncertaintyDistribution,
}

pub type ExtensionFeatureProfile {
  ExtensionFeatureProfile(
    features_offered: List(String),
    fractal_layer: String,
    technical_aspects: String,
    functional_aspects: String,
    ui_ux_aspects: String,
  )
}

/// Retrieves the comprehensive 1x1 fractal feature profile for any of the 167 extensions.
pub fn get_feature_profile(ext: ExtensionMetadata) -> ExtensionFeatureProfile {
  case ext.name {
    "ggram" ->
      ExtensionFeatureProfile(
        features_offered: [
          "StatCode character-by-character R/ggplot2 code parsing to spatial coordinate grid",
          "StatCodeLineNumbers right-aligned margin code line numbering engine",
          "stamp_notebook and stamp_graph_paper realistic paper styling overlays with punched binder holes",
          "Inline token syntax highlighting using #<< comment notation with customizable highlight strips",
          "patchwork side-by-side meta-plot assembly binding executable code on left with generated ggplot on right",
          "Multi-environment code ingestion supporting code strings, .Rhistory sessions, and clipboard buffers",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l5",
        technical_aspects:
          "StatCode ggproto transformation splitting multi-line code into characters, mapping lines to Y coordinates and character offsets to X coordinates, detecting #<< tokens to generate highlight bounding tiles, while StatCodeLineNumbers offsets line indices to X=-0.5 for margin alignment before patchwork stitches the code plot and ggplot output into a compound patchwork grob.",
        functional_aspects:
          "Interactive teaching tutorials, reproducible computational research notebooks, software documentation cards, code-to-plot pedagogical greetings, and step-by-step graphical grammar evolution.",
        ui_ux_aspects:
          "Dual-card side-by-side layout: left panel simulates lined ruled notebook or dark-mode IDE window with traffic-light chrome, yellow highlight strips on active lines, and right panel renders crisp, full-fidelity output plot.",
      )

    "ggrepel" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Force-directed non-overlapping text and label placement",
          "Custom arrowheads, elbow leader segments, and curved pointers",
          "Point-to-box and box-to-box collision avoidance algorithms",
          "Boundary clamping within plot margins and coordinate limits",
          "Directional nudging with prioritized x/y axis repulsion",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Simulated annealing spring-force physics engine treating text bounding boxes as repulsive particles connected to anchors via Hooke's law springs.",
        functional_aspects:
          "Transcriptomic volcano plots, astronomical star catalogs, and high-density outlier labeling where overlapping text obscures critical discoveries.",
        ui_ux_aspects:
          "Crisp text badges with fine leader segments, high contrast on dark cockpit background (#020617), zero text collisions, responsive auto-reflow.",
      )

    "ggdist" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Slab-interval geoms (half-eye, violin, continuous probability gradients)",
          "Dotplot and dotsinterval quasi-random quantile dot arrays",
          "Nested interval lines (50%, 80%, 95% Bayesian credible intervals)",
          "Analytical and sample empirical distribution visualizations",
          "Seamless integration with Stan, brms, and MCMC posterior distributions",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Continuous kernel density estimation (KDE) and analytical probability density functions coupled with discrete quantile interval calculus.",
        functional_aspects:
          "Bayesian posterior parameter estimation, decision-making under severe uncertainty, clinical trial risk assessment, and econometric forecasting.",
        ui_ux_aspects:
          "Translucent cyan density slabs with deep blue interior confidence bars and bright white median anchor points; dark cockpit compliant.",
      )

    "ggridges" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Partially overlapping density ridgelines across ordered strata",
          "Cyclical time-series ridges with continuous baseline offsets",
          "Quantile line annotations and probability coloring",
          "Dynamic vertical scale baselines (scale parameter tuning)",
          "Jittered point clouds under density curves",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Kernel density estimation evaluated across partitioned categorical strata with vertical baseline translation y_i = i * delta + f(x) * scale.",
        functional_aspects:
          "Seasonal temperature variations, multi-stage latency distributions, demographic age cohorts, and high-dimensional vibration harmonics.",
        ui_ux_aspects:
          "Layered semi-transparent colored ribbons with contrasting ridge borders, gradient fill according to value or quantile, dark cockpit depth perception.",
      )

    "ggalluvial" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Multi-stratum alluvial flow diagrams and Sankey stream tracking",
          "Cubic Bezier spline stream connections across temporal waves",
          "Strict categorical mass conservation across strata",
          "Lode-form and alluvium-form data structuring",
          "Stratum and alluvium visual aesthetics customization",
        ],
        fractal_layer: "#fractal-l3 #fractal-l4",
        technical_aspects:
          "Cubic Bezier curve interpolation preserving stratum thickness along the x-axis, enforcing sum(inflow) = sum(outflow) across all stages.",
        functional_aspects:
          "Customer cohort retention, election vote switching, industrial manufacturing state transitions, and medical patient treatment pathways.",
        ui_ux_aspects:
          "Vibrant flowing ribbons with soft opacity, contrasting stratum boundary blocks, intuitive left-to-right cognitive flow, zero visual twisting.",
      )

    "ggraph" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Node-link graphs with layout engines (stress, circular, bipartite, dendrogram)",
          "Edge bundling and curved connection geoms",
          "Node centrality attribute mappings",
          "Tidygraph integration for relational networks",
          "Hierarchical circle packing and treemaps",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l6",
        technical_aspects:
          "Stress-majorization, Fruchterman-Reingold force-directed, and Kamada-Kawai graph layout algorithms operating on vertex and edge attribute graphs.",
        functional_aspects:
          "Distributed microservice mesh topology, biochemical metabolic pathways, social network interaction analysis, and cybersecurity attack graphs.",
        ui_ux_aspects:
          "Curved glowing edges connecting circular nodes sized by degree centrality, node color-coded by cluster partition, dark space background.",
      )

    "treemapify" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Squarified treemap hierarchical layouts",
          "Sub-group border nesting and labeling",
          "Automatic text resizing within rectangular tiles",
          "Area-proportional quantitative visualization",
          "Zero aspect ratio distortion optimization",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Bruls-Huizing-van Wijk squarified treemap algorithm recursively dividing rectangular viewports to minimize cell aspect ratio max(w/h, h/w).",
        functional_aspects:
          "Budget allocations, disk storage usage diagnostics, software monorepo code size auditing, and corporate asset portfolios.",
        ui_ux_aspects:
          "Tile boundaries with varying line weights denoting hierarchy depth, high-contrast auto-fitting labels, palette grouping per parent domain.",
      )

    "patchwork" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Mathematical plot composition operators (+, /, |)",
          "Nested sub-panel layout specifications",
          "Automatic scale and guide collection (guides = 'collect')",
          "Aligned plotting regions across disparate coordinate systems",
          "Comprehensive title, subtitle, and caption annotations",
        ],
        fractal_layer: "#fractal-l2 #fractal-l4",
        technical_aspects:
          "Constraint-solving layout engine unifying grid dimensions, margin alignment, and guide merging into a unified view hierarchy without distortion.",
        functional_aspects:
          "Scientific publication figures, executive dashboards, multi-angle telemetry panels, and comparative experiment summaries.",
        ui_ux_aspects:
          "Harmonious unified margins, consistent typography, unified legend panel, clean grid lines, cohesive dark cockpit layout.",
      )

    "ggstatsplot" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Statistical inference hypothesis testing embedded in visualizations",
          "Parametric, non-parametric, robust, and Bayesian tests",
          "Automatic statistical test annotations (t, F, chi^2, p, r, omega^2)",
          "Violin + boxplot + jittered point composite geoms",
          "Effect size confidence intervals",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l5",
        technical_aspects:
          "Executes statistical hypothesis testing in real-time, computing test statistics, degrees of freedom, p-values, and effect size intervals.",
        functional_aspects:
          "Biomedical comparative studies, A/B testing evaluations, psychological research, and exploratory data analysis with statistical rigor.",
        ui_ux_aspects:
          "Clean hybrid violin-boxplot glyphs with embedded statistical summary cards, color-coded significance indicators, readable mathematical notation.",
      )

    "survminer" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Kaplan-Meier survival probability step curves",
          "Pointwise confidence interval envelopes",
          "Cumulative event and hazard curves",
          "Synchronized bottom number-at-risk tables",
          "Log-rank test p-value annotations",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Non-parametric Kaplan-Meier estimator S(t) = prod(1 - d_i/n_i) with Greenwood's formula for standard error confidence bands.",
        functional_aspects:
          "Clinical survival trials, hardware component MTBF reliability engineering, and customer subscription churn analysis.",
        ui_ux_aspects:
          "Step-function trajectories with shaded confidence intervals, censored event cross ticks, synchronized tabular risk counts beneath x-axis.",
      )

    "gganimate" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Grammar of animated graphics transitions (transition_time, transition_states)",
          "Temporal tweening and interpolation",
          "Shadow trails and historical ghost trajectories",
          "Frame rate and easing controls",
          "Dynamic view zooming and following",
        ],
        fractal_layer: "#fractal-l3 #fractal-l4",
        technical_aspects:
          "State interpolation and tweening algorithms generating intermediary animation keyframes between discrete data states along a temporal continuum.",
        functional_aspects:
          "Dynamic planetary orbits, spread of epidemiological contagions, algorithmic execution visualization, and historical trend analysis.",
        ui_ux_aspects:
          "Smooth motion paths with trailing ghost traces, interactive timeline scrubbers, animated status indicators.",
      )

    "ggforce" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Delaunay triangulation and Voronoi tessellation",
          "Convex and concave hull enclosures (geom_mark_hull)",
          "Spline curves and Bezier interpolation",
          "Zoom facets and magnifying sub-views",
          "Parallel coordinates and sina plots",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Computational geometry algorithms including Fortune's Voronoi sweepline, Graham scan convex hulls, and Catmull-Rom cubic splines.",
        functional_aspects:
          "Cluster boundary discovery, spatial partitioning, multidimensional feature inspection, and focus-and-context visual exploration.",
        ui_ux_aspects:
          "Polygonal Voronoi wireframes, translucent shaded cluster bubbles with leader callout tags, modern geometric aesthetic.",
      )

    "ggcorrplot" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Correlation matrix heatmaps with coefficient labels",
          "Hierarchical clustering reordering (hclust)",
          "Significance level masking and p-value crosses",
          "Square and circle glyph representations",
          "Upper, lower, and full triangular layouts",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Bivariate Pearson/Spearman correlation coefficient calculation r_xy in [-1, 1] coupled with agglomerative hierarchical clustering distance matrices.",
        functional_aspects:
          "Multivariate feature selection, collinearity diagnosis in regression modeling, and gene expression correlation networks.",
        ui_ux_aspects:
          "Divergent cool-to-warm color gradients (cyan to crimson), proportional circle radii denoting correlation magnitude, diagonal variable labels.",
      )

    "ggspatial" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Map tiles and spatial projections (geom_spatial_point, layer_spatial)",
          "Automatic north arrow compass roses",
          "Cartographic metric scale bars",
          "Simple Features (sf) geometry integration",
          "Bounding box coordinate reference system reprojections",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "PROJ-based geospatial coordinate transformation and spatial projection mapping, polygon clipping, and cartographic element sizing.",
        functional_aspects:
          "Geographic GIS mapping, environmental sensor telemetry, geopolitical boundaries, and fleet tracking logistics.",
        ui_ux_aspects:
          "Cartographic fidelity with clean metric scale indicators, stylized north arrow compass, tile overlays, dark-theme geospatial maps.",
      )

    "gghighlight" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Conditional series and point highlighting",
          "Automatic background dimming of non-matching observations",
          "Direct inline label placement on highlighted series",
          "Multi-predicate filtering expressions",
          "Preservation of overall distribution context",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "AST predicate evaluation filtering foreground datasets while cloning and style-overriding background layers with muted desaturated aesthetics.",
        functional_aspects:
          "Outlier anomaly investigation, highlighting focal entities among thousands of background traces, and financial benchmark comparisons.",
        ui_ux_aspects:
          "High visual pop with glowing neon cyan foreground line/points against muted slate background curves; direct inline labeling.",
      )

    "ggtern" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Ternary plot simplex coordinates (a + b + c = 100%)",
          "Tri-axial grid lines and ticks (Top, Left, Right)",
          "Ternary contour, point, and path geoms",
          "Isometric barycentric coordinate transformations",
          "Specialized ternary zoom and themes",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Barycentric projection (a, b, c) -> (x, y) onto an equilateral triangle: x = 0.5 * (2b + c)/(a+b+c), y = (sqrt(3)/2) * c/(a+b+c).",
        functional_aspects:
          "Petrology rock compositions, metallurgical phase diagrams, demographic age distributions, and genetics allele frequencies.",
        ui_ux_aspects:
          "Equilateral triangle frame with three 60-degree angled coordinate axes, color-coded simplex points, concentric triangular grid lines.",
      )

    "gghalves" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Half-half hybrid geoms (geom_half_violin, geom_half_point)",
          "Side-by-side distribution and raw data display",
          "Independent positioning and nudging per half",
          "Boxplot and dot cloud combinations",
          "Left/right orientation toggles",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Asymmetric kernel density projection clipping half-kernels along vertical centroid axis, paired with bounded 1D jitter displacement.",
        functional_aspects:
          "Raincloud plots, small-sample distribution comparisons where showing raw datapoints alongside density estimates prevents over-interpretation.",
        ui_ux_aspects:
          "Left half smooth shaded density violin, right half scattered individual raw observations with central median marker; clean visual balance.",
      )

    "ggbeeswarm" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Columnar categorical beeswarm point layouts",
          "Quasirandom van der Corput sequence point packing",
          "Zero-overlap point placement within columns",
          "Compact swarm geometry (geom_quasirandom, geom_beeswarm)",
          "Priority ordering by density or value",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "1D circle packing and deterministic van der Corput low-discrepancy sequences preventing point overlap along categorical strips.",
        functional_aspects:
          "Clinical biomarker levels per treatment group, gene expression per cell type, and latency benchmarking per algorithm.",
        ui_ux_aspects:
          "Organic swarm cloud showing both overall distribution shape and every individual observation with zero point collisions.",
      )

    "ggstream" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Streamgraph stacked flow visualizations",
          "Center-weighted baseline undulation algorithms",
          "Smoothed polynomial spline ribbon borders",
          "Proportional categorical thickness across time",
          "Sorting methods for ribbon visual stability",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Byron-Wattenberg streamgraph baseline minimization algorithm to minimize visual silhouette wobble and artificial oscillations.",
        functional_aspects:
          "Music genre popularity over decades, news topic volume over time, and server cluster resource consumption breakdowns.",
        ui_ux_aspects:
          "Organic flowing undulating ribbons in gradient palettes, serene fluid aesthetic, legible centered stream silhouette.",
      )

    "ggbreak" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Discontinuous axis scale breaks (scale_x_break, scale_y_break)",
          "Multiple breaks per axis",
          "Subplot width and height proportion control",
          "Zigzag, diagonal, and straight break line markers",
          "Independent scale formatting per break segment",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Affine piecewise coordinate mapping with discontinuity interval excised, translating upper interval coordinates.",
        functional_aspects:
          "Comparing massive outliers alongside fine baseline fluctuations without log-transform compression, genomic copy number variations.",
        ui_ux_aspects:
          "Clean double-tick or diagonal hatch markers separating discontinuous scale sections, maintaining readable scale ratios.",
      )

    "ggupset" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Combination matrix axis for set intersections",
          "Multi-set intersection size bar charts",
          "Connected dot combination matrix layout",
          "Seamless ggplot2 scale and axis replacement",
          "Exact UpSet plot representation for categorical intersections",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Power set boolean combination matrix generation, computing exact intersection cardinalities and ordering by set frequency.",
        functional_aspects:
          "Genomics gene set overlaps, survey multi-choice response analysis, customer multi-product ownership combinations.",
        ui_ux_aspects:
          "Top intersection bar chart perfectly aligned with bottom combination matrix dots connected by vertical line segments.",
      )

    "ggtree" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Phylogenetic cladogram and phylogram visualization",
          "Rectangular, circular, radial, and fan tree layouts",
          "Node branch lengths and bootstrap support annotations",
          "Tip labels, clade highlighting, and ancestral state mapping",
          "Multiple sequence alignment (MSA) integration",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l6",
        technical_aspects:
          "Tree traversal algorithms mapping phylogenetic distance matrices to branch lengths and bifurcation coordinates in Cartesian or polar space.",
        functional_aspects:
          "Evolutionary genomics, viral variant epidemiology tracking (SARS-CoV-2 lineages), taxonomic cladistics.",
        ui_ux_aspects:
          "Radial circular tree with divergent colored clades, crisp tip labels, high visual density with legible topology.",
      )

    "geomtextpath" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Text flowing along arbitrary geometric paths and splines",
          "Curved text along circles, sine waves, and contour lines",
          "Direct contour labeling (geom_textcontour)",
          "Text tracking, kerning, and smoothing along curves",
          "Label segment replacement and gap insertion",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Differential geometry arc-length parameterization placing individual glyphs tangential to path tangent vectors.",
        functional_aspects:
          "Topographic contour maps, river and road geographic labeling, mathematical function wave annotations.",
        ui_ux_aspects:
          "Smooth curving typography that follows data flow lines naturally, eliminating clumsy straight-line labels.",
      )

    "gghoriplot" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Horizon charts with folded density bands",
          "Positive and negative value band stacking",
          "Multi-tier opacity levels per horizon band",
          "Compact vertical space consumption (1/4 standard height)",
          "Time-series comparison across hundreds of entities",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Value range folding into K bands of height H: value v is mapped to band k = floor(|v|/H) with residual v mod H and color-coded sign.",
        functional_aspects:
          "Financial market tickers, server CPU core utilization monitoring (128+ cores), environmental sensor arrays.",
        ui_ux_aspects:
          "Dense horizontally striped charts with layered deep-to-light hues for positive and negative values, maximum information density.",
      )

    "ggnewscale" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Multiple color and fill scales on a single ggplot",
          "Independent scale domains and palettes per layer",
          "Multiple colorbar legends rendered side-by-side",
          "Seamless integration with any geom",
          "Clean grammar of graphics extension",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Dynamic scale environment isolation intercepting ggplot2 scale training, creating new scale namespaces for subsequent plot layers.",
        functional_aspects:
          "Overlaying distinct datasets (heat flux on topography, gene expression on spatial coordinates) requiring independent color maps.",
        ui_ux_aspects:
          "Side-by-side differentiated colorbars, zero palette conflict, clear visual association between layers and their respective legends.",
      )

    "ggfx" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Shader-based image filters for ggplot2 layers",
          "Drop shadows, outer glows, and Gaussian blurs",
          "Blend modes (multiply, screen, overlay)",
          "Color manipulation and displacement maps",
          "Rasterized shader effects rendered within vector outputs",
        ],
        fractal_layer: "#fractal-l2 #fractal-l4",
        technical_aspects:
          "Pixel-level raster convolution kernels applied to intermediate layer rendering buffers before compositing onto the canvas.",
        functional_aspects:
          "Highlighting critical anomalies with outer glows, depth layering with drop shadows, artistic data journalism.",
        ui_ux_aspects:
          "Glowing neon aesthetics, dark cockpit cyberpunk visual effects, subtle depth and layered elevation.",
      )

    "gginnards" ->
      ExtensionFeatureProfile(
        features_offered: [
          "AST inspection and editing of ggproto plot layers",
          "Querying and filtering data embedded in plot objects",
          "Deleting, reordering, and replacing specific layers",
          "Debugging complex multi-layer visualization pipelines",
          "Automated plot auditing and validation",
        ],
        fractal_layer: "#fractal-l3 #fractal-l5",
        technical_aspects:
          "Reflective introspection of the ggplot2 abstract syntax tree and R environment closures, exposing layer data frames and mapping expressions.",
        functional_aspects:
          "Automated plot testing, programmatic modification of third-party plots, compliance auditing in regulated reporting.",
        ui_ux_aspects:
          "Hierarchical tree visualization of plot layers, visual state inspection badges, transparent internal structure.",
      )

    "ggQC" | "xmrr" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Statistical Process Control (SPC) Shewhart charts",
          "Upper Control Limit (UCL), Lower Control Limit (LCL), and Center Line (CL)",
          "Western Electric and Nelson out-of-control violation rules",
          "Moving range (mR) and individual measurement (X) tracking",
          "Multi-faceted process stability inspection",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l5",
        technical_aspects:
          "Statistical process control limit calculation: CL = mu, UCL = mu + 3*sigma, LCL = mu - 3*sigma, with rolling variance estimators.",
        functional_aspects:
          "Manufacturing quality assurance, semiconductor yield tracking, server SLA latency monitoring, industrial telemetry.",
        ui_ux_aspects:
          "Prominent dashed control limit threshold lines, crimson violation markers on out-of-control anomalies, stable green center line.",
      )

    "cowplot" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Publication-ready figure grid composition",
          "Panel labeling (A, B, C tags) with uniform font size",
          "Plot inset embedding and annotation grobs",
          "Clean minimalist publication theme without background grey",
          "Image and vector drawing overlays",
        ],
        fractal_layer: "#fractal-l2 #fractal-l4",
        technical_aspects:
          "Grid-based viewport arrangement allocating explicit sub-canvases with margin compensation and label positioning.",
        functional_aspects:
          "Assembling multi-panel figures for academic journals (Nature, Science, Cell), combining disparate plot types into a single plate.",
        ui_ux_aspects:
          "Bold capital letter tags (A, B, C) in the top-left of each sub-panel, elegant balanced spacing, clean vector lines.",
      )

    "ggmosaic" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Mosaic plots for multi-way contingency tables",
          "Area-proportional tile partitioning",
          "Hierarchical categorical variable nesting",
          "Pearson residual shading for independence testing",
          "Product plot grammar integration",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Recursive orthogonal area partitioning where tile area A_ij is proportional to joint probability P(X=i, Y=j).",
        functional_aspects:
          "Categorical survey analysis, cross-tabulation exploration, testing statistical independence in multi-way contingency tables.",
        ui_ux_aspects:
          "Neatly tessellated rectangular blocks with clear variable hierarchy, residual color coding, zero overlapping lines.",
      )

    "ggradar" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Spider and radar charts with polar spokes",
          "Multi-attribute multivariate profile comparisons",
          "Concentric polygon grid rings with percentage labels",
          "Custom fill opacity and line stroke weights",
          "Entity color coding and legend integration",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Polar coordinate mapping (r_i, theta_i) connecting normalized attributes into closed polygons across N radial dimensions.",
        functional_aspects:
          "Athlete skill profile assessments, cyber defense vulnerability vectors, multi-criteria decision evaluations.",
        ui_ux_aspects:
          "Equiangular polygon web with glowing translucent colored entity overlays, bold spoke axes, readable perimeter labels.",
      )

    "plotROC" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Interactive and publication-quality ROC curves",
          "Empirical ROC curve calculation",
          "Confidence regions for ROC curves",
          "Integrated Area Under Curve (AUC) calculation",
          "Cutoff threshold markers along the curve",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "True Positive Rate vs False Positive Rate computation over all possible decision thresholds, trapezoidal rule AUC integration.",
        functional_aspects:
          "Diagnostic test evaluation, machine learning classifier comparison, biomarker cutoff determination in clinical oncology.",
        ui_ux_aspects:
          "Smooth stepped ROC curve with 45-degree diagonal chance line, shaded AUC region, annotated optimal sensitivity/specificity operating point.",
      )

    "ggbump" ->
      ExtensionFeatureProfile(
        features_offered: [
          "Smooth bump charts for ranking over time",
          "Sigmoid curve rank transitions",
          "Point markers at rank nodes",
          "Custom ranking colors per entity",
          "Zero-crossing rank trajectory visualizations",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Sigmoid curve interpolation providing smooth horizontal-to-horizontal transitions between discrete integer rank positions.",
        functional_aspects:
          "League table sports rankings, popularity rankings of programming languages over years, country GDP rankings.",
        ui_ux_aspects:
          "Vibrant colored ribbons weaving smoothly across discrete time intervals, node circles with rank numbers, high visual flow.",
      )

    _ ->
      // Algorithmic Fractal Synthesis by Taxonomic Category
      synthesize_category_profile(ext)
  }
}

fn synthesize_category_profile(ext: ExtensionMetadata) -> ExtensionFeatureProfile {
  case ext.category {
    UncertaintyDistribution ->
      ExtensionFeatureProfile(
        features_offered: [
          "Statistical distribution parameter visualization",
          "Density estimators and probability interval mapping",
          "Confidence interval and credible interval rendering",
          "Parametric and non-parametric distribution comparisons",
          "Integration with statistical modeling workflows",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Mathematical density estimation and parametric quantile transformation mapping continuous probability distributions to geometric interval bounds.",
        functional_aspects:
          "Quantifying statistical uncertainty, risk modeling, scientific parameter estimation, and posterior distribution assessment.",
        ui_ux_aspects:
          "Translucent density fills, crisp confidence bars, high contrast on dark cockpit surfaces, clean interval hierarchy.",
      )

    NetworkGraphTopology ->
      ExtensionFeatureProfile(
        features_offered: [
          "Graph node and edge layout algorithms",
          "Topological network structure representation",
          "Vertex centrality and edge weight aesthetic mappings",
          "Cluster partitioning and community detection styling",
          "Directional arrowheads and edge bundling",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l6",
        technical_aspects:
          "Relational graph algorithms (force-directed, stress-majorization, circular) mapping network topologies to 2D coordinates.",
        functional_aspects:
          "Network infrastructure topology, biochemical metabolic graphs, social connectivity, and distributed systems interaction.",
        ui_ux_aspects:
          "Curved edge connections with node size scaling by centrality, distinct cluster hues, dark space canvas.",
      )

    FlowAlluvialSankey ->
      ExtensionFeatureProfile(
        features_offered: [
          "Multi-stage categorical flow tracking",
          "Cubic Bezier stream ribbon interpolation",
          "Stratum categorical conservation across stages",
          "Proportional flow volume thickness",
          "Attrition and retention cohort visualization",
        ],
        fractal_layer: "#fractal-l3 #fractal-l4",
        technical_aspects:
          "Smooth polynomial spline interpolation preserving mass conservation across discrete categorical strata.",
        functional_aspects:
          "Process pipelines, patient journey tracking, state transition monitoring, and energy flow auditing.",
        ui_ux_aspects:
          "Vibrant flowing ribbons with soft opacity, contrasting stratum boundary blocks, intuitive left-to-right cognitive flow.",
      )

    HierarchicalPartition ->
      ExtensionFeatureProfile(
        features_offered: [
          "Hierarchical nested partition layouts",
          "Area-proportional quantitative subdivision",
          "Multi-level grouping borders and labels",
          "Aspect ratio optimization algorithms",
          "Tree structured data representation",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Recursive rectangular area partitioning algorithms minimizing aspect ratio distortion across hierarchical tree depths.",
        functional_aspects:
          "Resource allocation auditing, file system disk space diagnostics, taxonomy hierarchies, and financial portfolio sizing.",
        ui_ux_aspects:
          "High-contrast nested tile borders, auto-scaling typography, harmonious parent-child color ramps.",
      )

    SpatialVectorField ->
      ExtensionFeatureProfile(
        features_offered: [
          "Vector field direction and magnitude glyphs",
          "Spatial coordinate system reprojections",
          "Fluid flow and gradient visualizations",
          "Geographic spatial feature integration",
          "Cartographic scale bars and compass annotations",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Differential vector calculus v(x,y) rendering directional arrowheads with magnitude-scaled lengths and color fills.",
        functional_aspects:
          "Fluid dynamics, meteorological wind vectors, electromagnetic field mapping, and geospatial logistics.",
        ui_ux_aspects:
          "Clear vector arrowheads, magnitude color ramps, crisp spatial axes, dark cockpit geographic contrast.",
      )

    QualityControlTimeSeries ->
      ExtensionFeatureProfile(
        features_offered: [
          "Statistical Process Control (SPC) Shewhart charts",
          "Upper and lower control limit boundaries (UCL/LCL)",
          "Anomaly and out-of-control violation detection",
          "Temporal moving average and range tracking",
          "Industrial quality metrics monitoring",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l5",
        technical_aspects:
          "Rolling statistical parameter calculations (mean, standard deviation, moving range) generating 3-sigma control limits.",
        functional_aspects:
          "Semiconductor manufacturing quality control, DevOps server latency monitoring, sensor calibration verification.",
        ui_ux_aspects:
          "Prominent dashed control limit threshold lines, crimson violation markers on out-of-control anomalies, stable green center line.",
      )

    BioinformaticsGenomics ->
      ExtensionFeatureProfile(
        features_offered: [
          "Genomic sequence and variant locus visualization",
          "Phylogenetic cladogram and tree representations",
          "High-density chromosomal coordinate mappings",
          "Biological ontology and pathway highlights",
          "Multiple sequence alignment integration",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l6",
        technical_aspects:
          "Chromosomal base-pair coordinate mapping, log-p value scaling, and phylogenetic distance matrix tree traversal.",
        functional_aspects:
          "GWAS variant discovery, pathogen evolutionary tracking, transcriptomic gene expression profiling, and oncology diagnostics.",
        ui_ux_aspects:
          "High-density coordinate tracks, crisp chromosome demarcations, distinct clade coloring, legible biological annotations.",
      )

    TypographyTextRepel ->
      ExtensionFeatureProfile(
        features_offered: [
          "Non-overlapping text label placement algorithms",
          "Leader lines and pointers to data coordinates",
          "Curved text along geometric trajectories",
          "Typography formatting and font scaling",
          "Collision-free annotation in crowded plots",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Force-directed repulsion optimization and differential geometry arc-length glyph placement.",
        functional_aspects:
          "Outlier labeling in dense scatter plots, publication figures, cartographic labeling, and educational diagramming.",
        ui_ux_aspects:
          "Crisp legible typography, elegant pointer lines, responsive margin clamping, zero visual overlap.",
      )

    MultiScaleCoordinate ->
      ExtensionFeatureProfile(
        features_offered: [
          "Non-Cartesian coordinate system transformations",
          "Ternary triangular simplex coordinates (a+b+c=1)",
          "Discontinuous axis scale breaks and zoom windows",
          "Polar, radar, and cylindrical coordinates",
          "Independent dual coordinate scaling",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Non-linear coordinate projections and affine transformations mapping multi-dimensional data to specialized visual frames.",
        functional_aspects:
          "Compositional data analysis (metallurgy, soil science), extreme value comparison across broken axes, radar profiling.",
        ui_ux_aspects:
          "Specialized geometric frames (equilateral triangles, polar webs, split axes), precision tick marks, clear scale guides.",
      )

    CompositeMultiPanel ->
      ExtensionFeatureProfile(
        features_offered: [
          "Multi-panel plot assembly and mathematical composition",
          "Unified margin and coordinate alignment",
          "Merged and shared scale legends",
          "Panel labeling (A, B, C tags) and figure captioning",
          "Inset plots and miniature detail sub-views",
        ],
        fractal_layer: "#fractal-l2 #fractal-l4",
        technical_aspects:
          "Constraint-solving viewport hierarchy unifying grid dimensions, margin spacing, and guide merging.",
        functional_aspects:
          "Scientific publication plates, multi-modal executive dashboards, comparative experiment reviews.",
        ui_ux_aspects:
          "Harmonious aligned borders, unified typography, consistent legend placement, cohesive presentation.",
      )

    ThreeDimensionalProjection ->
      ExtensionFeatureProfile(
        features_offered: [
          "3D perspective and isometric projections",
          "Surface contours, wireframes, and meshes",
          "Viewing angle rotation (theta, phi, zoom)",
          "Depth cues and perspective point scaling",
          "3D bounding box coordinate frames",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "3D-to-2D projection matrix multiplication with depth-buffer sorting and isometric rotational transformations.",
        functional_aspects:
          "Engineering response surfaces, chemical molecular structures, 3D sensor coordinates, topography.",
        ui_ux_aspects:
          "Wireframe perspective frames, depth-sorted visual elements, clear rotational cues, dark cockpit aesthetics.",
      )

    StatisticalDiagnosisInference ->
      ExtensionFeatureProfile(
        features_offered: [
          "Real-time statistical hypothesis testing annotations",
          "Regression diagnostic plots (residuals, Q-Q, leverage)",
          "Correlation matrix heatmaps and clustering",
          "ROC and AUC curve performance calculations",
          "Effect size and confidence interval indicators",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l5",
        technical_aspects:
          "Statistical estimation algorithms calculating test statistics, degrees of freedom, p-values, and diagnostic residual matrices.",
        functional_aspects:
          "Model validation, clinical trial comparative evaluation, machine learning classifier auditing, scientific reporting.",
        ui_ux_aspects:
          "Integrated statistical summary cards, color-coded significance badges, diagnostic reference lines, clear mathematical notation.",
      )

    PatternFilterShader ->
      ExtensionFeatureProfile(
        features_offered: [
          "Pattern fills (stripes, dots, crosshatch) for accessibility",
          "Shader-based image filter effects (glows, blurs, shadows)",
          "Blend modes and luminosity compositing",
          "Color-blind accessible visual differentiation",
          "Vector pattern definition integration",
        ],
        fractal_layer: "#fractal-l2 #fractal-l4",
        technical_aspects:
          "SVG pattern element definitions and raster convolution image filters applied to vector layer rendering buffers.",
        functional_aspects:
          "Black-and-white printing accessibility, highlighting anomalous entities with glowing halos, artistic infographics.",
        ui_ux_aspects:
          "High tactile texture contrast, neon glowing accent outlines, accessible distinction independent of color vision.",
      )

    DimensionalityReduction ->
      ExtensionFeatureProfile(
        features_offered: [
          "PCA biplots and eigenvector loadings",
          "t-SNE and UMAP manifold cluster visualization",
          "Variance explained scree plots and contributions",
          "Cluster confidence ellipses and convex hulls",
          "High-dimensional feature space compression",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Eigen-decomposition and non-linear manifold dimension reduction projecting high-dimensional matrices to 2D scatter coordinates.",
        functional_aspects:
          "Single-cell transcriptomics, customer segmentation, image embedding exploration, multivariate feature selection.",
        ui_ux_aspects:
          "Distinct cluster color mapping with translucent enclosing hulls, origin crosshairs, directional loading vectors.",
      )

    ThemingPaletteAesthetic ->
      ExtensionFeatureProfile(
        features_offered: [
          "Scientifically calibrated perceptually uniform color palettes",
          "Prestige publication themes (Economist, Tufte, WSJ)",
          "Color-vision deficiency (CVD) safe color ramps",
          "Dark cockpit and high-contrast theme overrides",
          "Typography, grid, and margin aesthetic controls",
        ],
        fractal_layer: "#fractal-l2 #fractal-l4",
        technical_aspects:
          "CIE-L*a*b* and CAM02-UCS perceptually uniform color space interpolation ensuring monotonic lightness progression.",
        functional_aspects:
          "Publication-ready figure styling, dark cockpit UI harmonization, accessible scientific communication.",
        ui_ux_aspects:
          "Flawless color ramps, zero perceptual artifacts, high contrast ratios exceeding WCAG 2.1 AAA, refined typography.",
      )

    IntrospectionLayerEditing ->
      ExtensionFeatureProfile(
        features_offered: [
          "Interactive and programmatic layer inspection",
          "Selective foreground highlighting with dimmed background",
          "Abstract Syntax Tree (AST) query and modification",
          "Layer reordering and property override",
          "Plot auditing and compliance verification",
        ],
        fractal_layer: "#fractal-l3 #fractal-l5",
        technical_aspects:
          "Reflective introspection of the visualization scene graph, evaluating predicates to partition layers into active/inactive sets.",
        functional_aspects:
          "Interactive visual debugging, exploratory focus-and-context inspection, automated plot quality auditing.",
        ui_ux_aspects:
          "High-contrast accent colors on focal traces with desaturated slate grey on background context, transparent hierarchy.",
      )
  }
}
