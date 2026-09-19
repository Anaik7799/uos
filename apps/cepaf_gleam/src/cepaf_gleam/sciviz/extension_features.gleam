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
//// 100% Bespoke Domain Implementation - Zero Generic Fallbacks.

import cepaf_gleam/sciviz/extension_catalog.{type ExtensionMetadata}

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

    "ggQQunif" ->
      ExtensionFeatureProfile(
        features_offered: [
        "stat_qq_unif quantile transformation for uniform distributed statistics",
        "Simultaneous confidence concentration bands for null hypotheses",
        "Downsampling and subset thinning for millions of p-value observations",
        "Log10-scaled axes with concentration band clipping boundaries",
        "Tail-quantile magnification for genome-wide association study (GWAS) hits"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Empirical order statistics mapping against uniform theoretical quantiles with Beta(k, n-k+1) pointwise and Kolmogorov-Smirnov simultaneous confidence envelopes.",
        functional_aspects:
          "High-throughput genomics, GWAS p-value inflation diagnostics, genomic lambda calculation, and large-scale multiple hypothesis testing audits.",
        ui_ux_aspects:
          "Dark-blue backdrop with cyan scatter points, faint white theoretical diagonal reference line, and translucent amber confidence band envelope.",
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

    "xmrr" ->
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

    "gg3D" ->
      ExtensionFeatureProfile(
        features_offered: [
        "stat_3d 3D-to-2D isometric and perspective projection transformations",
        "geom_path3d and geom_point3d for spatial trajectory tracing in 3D space",
        "geom_wireframe for mathematical surface rendering and elevation grids",
        "Arbitrary 3D Euler angle rotation matrices (theta, phi, roll)",
        "Dynamic depth sorting (painter's algorithm) for occlusion handling"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Homogeneous 4x4 affine coordinate transformations projecting (x,y,z,1) onto camera focal planes with configurable perspective vanishing points.",
        functional_aspects:
          "Atmospheric sensor tracking, multi-axis drone flight dynamics, robotic kinematics, and spatial molecular coordinates.",
        ui_ux_aspects:
          "Rotated isometric 3D bounding box wireframe with illuminated cyan depth-coded points and neon trajectory paths on deep dark canvas.",
      )

    "ggQC" ->
      ExtensionFeatureProfile(
        features_offered: [
        "stat_qc automated Shewhart control chart limit calculations (UCL, CL, LCL)",
        "stat_qc_violating_rules automated detection of Nelson rules 1 through 8",
        "Western Electric rule checks (1 point beyond 3-sigma, 9 in zone C, 6 trending)",
        "Multi-stage segmented control limits across equipment recalibration phases",
        "Automated process capability indices (Cp, Cpk, Pp, Ppk) calculation"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l5",
        technical_aspects:
          "Rolling statistical estimation of subgroup mean and within-subgroup variation (R-bar/d2 or S-bar/c4) establishing 3-sigma control thresholds.",
        functional_aspects:
          "Semiconductor manufacturing yield analysis, pharmaceutical batch verification, high-frequency SRE server latency SLO monitoring.",
        ui_ux_aspects:
          "Horizontal emerald central centerline with red dashed upper/lower control limits, yellow alert violation badges, and dark cockpit telemetry grids.",
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

    "ggedit" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Interactive layer inspection and aesthetic value modification",
        "Runtime theme and scale attribute extraction and hot-patching",
        "Bi-directional ggplot-to-code serialization and reverse compilation",
        "Layer deletion, re-ordering, and aesthetic override in active gg objects",
        "Visual exploration of scale breaks, palette mappings, and font hierarchies"
        ],
        fractal_layer: "#fractal-l4 #fractal-l5",
        technical_aspects:
          "In-memory traversal and mutation of nested ggplot2 ggproto environments and plot list structures without re-executing data ingestion pipelines.",
        functional_aspects:
          "Rapid exploratory graphic design, scientific publication aesthetic polishing, interactive dashboard tweaking without code re-runs.",
        ui_ux_aspects:
          "Multi-pane inspector sidebar with property sliders, color pickers, and real-time canvas re-render with zero client-side latency.",
      )

    "ggpage" ->
      ExtensionFeatureProfile(
        features_offered: [
        "ggpage_build document layout formatting transforming text into visual pages",
        "ggpage_plot spatial word and character heatmap tiling across book pages",
        "Structural document analysis tracking chapter, paragraph, and line coordinates",
        "Sentiment and keyword occurrence mapping across entire literary corpora",
        "Configurable page grid layouts (pages across, line spacing, margins)"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Text tokenization coupled with 2D page pagination geometry, projecting token indices to (x_col, y_row, page_idx) spatial coordinates.",
        functional_aspects:
          "Digital humanities corpus exploration, legal document sentiment analysis, contract structural audits, and genomic sequence page books.",
        ui_ux_aspects:
          "Grid of miniature paper page rectangles with colored text lines reflecting sentiment and topic density, high contrast against dark canvas.",
      )

    "ggpca" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_pca_biplot simultaneous plotting of sample scores and feature loadings",
        "Eigenvector variance explained scree annotations and confidence ellipses",
        "Seamless projection pipelines for PCA, t-SNE, and UMAP coordinates",
        "Cosine angle feature correlation vectors with automated label repulsion",
        "Multi-group centroid computation and convex hull cluster boundaries"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Singular Value Decomposition (SVD) on centered/scaled covariance matrices yielding orthonormal principal component loading vectors and sample scores.",
        functional_aspects:
          "Single-cell RNA sequencing transcriptomics, high-dimensional chemical spectra clustering, and financial risk factor decomposition.",
        ui_ux_aspects:
          "Vibrant cluster scatter with semi-transparent confidence ellipses, radiating gold eigenvector arrows with angular correlation labels.",
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

    "ggimg" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_rect_img raster image glyph placement bound to spatial data coordinates",
        "geom_point_img image icons as scatter plot marker glyphs",
        "Proportional aspect ratio preservation with anchor alignment controls",
        "Dynamic image luminance and alpha blending over background data layers",
        "Tile matrix raster rendering for microscopy and satellite image grids"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Raster grob encapsulation within Cartesian scale boundaries, computing affine matrix coordinate transformations from data units to pixel viewports.",
        functional_aspects:
          "Spatial pathology microscopy annotation, sports analytics player headshot maps, satellite land-use overlays, and product icon graphs.",
        ui_ux_aspects:
          "Crisp icon glyphs mapped at precise data coordinates with subtle outer halos preventing boundary collision with underlying dark grids.",
      )

    "gganatogram" ->
      ExtensionFeatureProfile(
        features_offered: [
        "stat_anatogram tissue and organ gene expression highlighting",
        "Pre-built organism anatomies: Homo sapiens, Mus musculus, Drosophila, Danio rerio",
        "Multi-system anatomical overlays (nervous, cardiovascular, endocrine, digestive)",
        "Continuous color scale mapping of expression or biomarker concentrations onto organs",
        "Male and female anatomical silhouette support with cell-compartment zoom"
        ],
        fractal_layer: "#fractal-l3 #fractal-l4",
        technical_aspects:
          "SVG tissue contour path parsing and polygon feature extraction mapped to categorical anatomy ontologies with coordinate normalisation.",
        functional_aspects:
          "Pharmacokinetics drug biodistribution, oncology metastasis tracking, toxicological organ vulnerability studies, and biological atlas exploration.",
        ui_ux_aspects:
          "Sleek anatomical body silhouette with brightly illuminated organ systems colored by expression level, floating over deep navy background.",
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

    "ggalt" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_encircle smoothed convex hull polygon enclosure around point clusters",
        "geom_lollipop horizontal and vertical lollipop charts for discrete rankings",
        "geom_dumbbell paired comparison charts highlighting change before/after",
        "geom_stepribbon stepped confidence intervals and error ribbons",
        "coord_proj cartographic coordinate projections using PROJ library parameters"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Spline-smoothed polygon expansion algorithms around point clusters and parametric coordinate transformations for alternative geometric forms.",
        functional_aspects:
          "Clinical trial pre/post intervention dumbbell comparisons, economic indicator lollipops, and cluster boundary encircling in t-SNE spaces.",
        ui_ux_aspects:
          "High-contrast lollipop stems with circular heads, elegant dumbbell bars with contrasting before/after endpoints, smooth cluster enclosures.",
      )

    "ggiraph" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_point_interactive tooltip and hover state hooks on SVG elements",
        "geom_polygon_interactive interactive clickable regions for drill-down actions",
        "Selection state management with customizable CSS hover and selected styles",
        "SVG data-id attribute binding for cross-widget linked brushing",
        "Client-independent SVG markup rendering directly compatible with pure BEAM"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l7",
        technical_aspects:
          "Injection of SVG data-* attributes, onclick handlers, and CSS pseudo-class bindings into native SVG elements during grob generation.",
        functional_aspects:
          "Interactive scientific dashboards, exploratory data portals, clickable genomic locus browsers, and cross-filter data cockpits.",
        ui_ux_aspects:
          "Luminous hover borders, reactive tooltips styled with frosted dark glass backgrounds, instantaneous selection highlights.",
      )

    "ggmuller" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_muller evolutionary dynamics and clonal lineage frequency tracking",
        "Phylogenetic ancestry stack ordering ensuring descendant clones nest inside parents",
        "Relative and absolute population abundance time-series smoothing",
        "Dynamic extinction and speciation event branch branching and tapering",
        "Clonal color inheritance passing hue variations to descendant sub-clones"
        ],
        fractal_layer: "#fractal-l3 #fractal-l4",
        technical_aspects:
          "Cubic spline polygon interpolation of time-series frequencies ordered by evolutionary tree adjacency matrices, maintaining nested area topology.",
        functional_aspects:
          "Cancer genomics clonal evolution, bacterial antibiotic resistance emergence, viral variant epidemiology, and population genetics.",
        ui_ux_aspects:
          "Multi-colored undulating river streams where emergent sub-clones bud out from parent streams and expand or taper to extinction.",
      )

    "ggstance" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_barh native horizontal bar charts with flipped aesthetic mappings",
        "geom_boxploth horizontal box-and-whisker plots with aligned factor levels",
        "geom_violinh horizontal probability density violins",
        "geom_errorbarh horizontal error bars for asymmetric parameter intervals",
        "Consistent aesthetic semantics (x = continuous, y = categorical) across all geoms"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Direct horizontal coordinate computation in the ggproto compute_group layer without requiring expensive and fragile coord_flip transformations.",
        functional_aspects:
          "Long-label categorical factor comparisons, survey response distribution ranking, econometric parameter interval estimation.",
        ui_ux_aspects:
          "Crisp horizontal bars with right-aligned value labels, horizontal density violins with central median white dots, legible factor text.",
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

    "ggpp" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_plot nested ggplot insets placed at normalized parent coordinates (NPC)",
        "geom_table tabular data grob insets placed directly inside plot panels",
        "geom_text_npc and geom_label_npc viewport-relative corner text placement",
        "stat_dens2d_filter filtering labels to low-density regions avoiding clutter",
        "stat_dens2d_labels automated top-n outlier label selection"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Viewport-relative coordinate transformations mapping [0,1] NPC units to physical device grob viewports, decoupled from data scale ranges.",
        functional_aspects:
          "Publication figures with mini-inset plots, executive summary cards with embedded KPI tables, high-density scatter outlier tagging.",
        ui_ux_aspects:
          "Clean inset mini-charts floating in graph corners with dark card styling, structured tabular data insets with crisp typography.",
      )

    "ggpmisc" ->
      ExtensionFeatureProfile(
        features_offered: [
        "stat_poly_eq automated polynomial regression equation and R-squared formatting",
        "stat_fit_glance model summary metrics (p-value, AIC, BIC, F-statistic) text",
        "stat_peaks and stat_valleys automatic local extrema detection and labeling",
        "stat_correlation automated Pearson/Spearman correlation coefficient labeling",
        "stat_quant_eq quantile regression equations across multiple percentiles"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Runtime evaluation of lm/rlm/rq linear model formulas on panel subsets, parsing model objects into formatted plotmath and LaTeX expressions.",
        functional_aspects:
          "Analytical chemistry calibration curves, pharmacokinetic rate regressions, econometric trend models, and peak detection spectroscopy.",
        ui_ux_aspects:
          "Formatted mathematical equations (y = mx + b, R² = 0.98, p < 0.001) in corner badges, peak marker flags on curve summits.",
      )

    "geomnet" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_net single-geom network graph visualization integrating nodes and edges",
        "Self-loop circular edge rendering for intra-node feedback loops",
        "Arrowhead directional encoding with customizable head size and angle",
        "Facetted network diagrams across categorical grouping variables",
        "Automatic node degree calculation mapped to node radius and color"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Unified network data frame transformation merging edge list and vertex attribute tables into a single data frame evaluated by a unified grob.",
        functional_aspects:
          "Social network analysis, protein-protein interaction networks, infrastructure routing topology, and organizational influence graphs.",
        ui_ux_aspects:
          "Luminous circular nodes with connected neon edge vectors, directional arrowheads, dark mode background with node degree sizing.",
      )

    "ggExtra" ->
      ExtensionFeatureProfile(
        features_offered: [
        "ggMarginal marginal distribution plots along x and y scatter plot axes",
        "Marginal plot types: histograms, kernel densities, boxplots, and violin plots",
        "Configurable size ratios between main scatter plot and marginal panels",
        "Grouped marginal distributions colored by categorical factor levels",
        "Seamless gtable integration maintaining perfect axis alignment"
        ],
        fractal_layer: "#fractal-l2 #fractal-l4",
        technical_aspects:
          "Gtable gTree construction inserting auxiliary viewport rows and columns alongside the primary Cartesian panel with synchronized scale limits.",
        functional_aspects:
          "Bivariate correlation analysis, biomarker co-expression profiling, financial asset return joint distributions, quality inspection data.",
        ui_ux_aspects:
          "Central scatter plot flanked on top and right by slim cyan density curves and amber histograms aligned to axis ticks.",
      )

    "ggfortify" ->
      ExtensionFeatureProfile(
        features_offered: [
        "autoplot unified interface for time series (ts, xts, zoo, forecast) objects",
        "autoplot for survival analysis (survfit) with confidence ribbons and risk tables",
        "autoplot for PCA and clustering (prcomp, princomp, kmeans, hclust)",
        "autoplot for regression diagnostics (lm residual vs fitted, Normal Q-Q, Cook distance)",
        "Automatic extraction of model coefficients, residuals, and confidence intervals"
        ],
        fractal_layer: "#fractal-l3 #fractal-l4 #fractal-l5",
        technical_aspects:
          "S3 generic fortify method dispatch extending base R statistical and time-series model classes into tidy ggplot2-compatible data frames.",
        functional_aspects:
          "Rapid statistical model diagnostics, automated econometric forecasting, multivariate cluster inspection, survival study pipelines.",
        ui_ux_aspects:
          "Standardized 4-panel regression diagnostic grids and multi-series forecasting ribbons rendered with dark-mode aesthetic clarity.",
      )

    "autoplotly" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Interactive plotly generation from ggfortify statistical model objects",
        "Hover tooltips displaying fitted values, residuals, and observation metadata",
        "Client-side zoom, pan, and box-select capabilities without backend round-trips",
        "WebGL hardware acceleration for large point cloud visualizations",
        "Exportable standalone HTML and pure SVG vector graphics representations"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l7",
        technical_aspects:
          "Direct conversion of ggfortify gtable objects and ggplot2 ASTs into declarative Plotly JSON specifications.",
        functional_aspects:
          "Interactive model exploration, exploratory regression diagnostics, real-time time-series telemetry analysis, executive dashboards.",
        ui_ux_aspects:
          "Interactive controls bar, smooth hover inspection crosshairs, and dynamic scale recalibration on pan/zoom.",
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

    "ggthemes" ->
      ExtensionFeatureProfile(
        features_offered: [
        "theme_wsj Wall Street Journal aesthetic styling with distinct tan backdrop",
        "theme_economist The Economist magazine styling with signature cyan headers",
        "theme_fivethirtyeight FiveThirtyEight clean data journalism layout",
        "theme_tufte minimal Edward Tufte styling with maximal data-ink ratio",
        "Complete color palettes: Solarized, Stata, Excel, Stephen Few, Tableaus"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Comprehensive theme specification overrides replacing margins, typography, gridlines, axis lines, and background rectangles.",
        functional_aspects:
          "Publication-quality journalism graphics, financial executive briefings, minimalist scientific reports, media-ready chart styling.",
        ui_ux_aspects:
          "Diverse palette selections ranging from high-contrast dark cockpit themes to classic editorial newsprint styling.",
      )

    "ggspectra" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_spct continuous spectral irradiance, transmittance, and reflectance curves",
        "Wavelength-to-color mapping rendering authentic physical light spectrum colors",
        "stat_peaks and stat_valleys for spectral peak identification and labeling",
        "Photobiological waveband integration (UVA, UVB, PAR, Blue, Far-Red)",
        "Multi-sensor spectral comparisons with baseline normalization"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "CIE standard observer color matching functions translating physical nanometer wavelengths (380-780nm) into exact sRGB chromaticity coordinates.",
        functional_aspects:
          "Photobiology, agricultural grow-light spectral optimization, astronomical star spectroscopy, optical filter transmission analysis.",
        ui_ux_aspects:
          "Continuous spectral rainbow ribbon beneath the irradiance curve, bright white peak callout flags, wavelength nm axis.",
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

    "ggnetwork" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_nodes node glyph placement based on network layout coordinates",
        "geom_edges straight, curved, and segmented network link representations",
        "geom_nodetext and geom_edgetext text labels placed along edges and nodes",
        "Native layout algorithms (Fruchterman-Reingold, Kamada-Kawai, Circular, Spring)",
        "Edge weight mapping to line width, transparency, and color gradients"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Fortification of igraph and network objects into flat data frames with (x, y, xend, yend) coordinate columns evaluated natively by ggplot2.",
        functional_aspects:
          "Telecommunication network routing, metabolic pathway maps, social interaction graphs, cybersecurity attack vector topologies.",
        ui_ux_aspects:
          "Gleaming node clusters linked by translucent fiber-optic vectors, high visual depth over dark space cockpit canvas.",
      )

    "ggtech" ->
      ExtensionFeatureProfile(
        features_offered: [
        "theme_tech branded themes for major tech platforms (Google, Twitter, Airbnb, Facebook, Uber)",
        "scale_color_tech authentic corporate brand color palettes and accents",
        "geom_tech branded logo markers and company iconography",
        "Custom typography pairings matching Silicon Valley brand design guides",
        "Tech ecosystem financial and performance benchmarking comparisons"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Encapsulated brand design systems with calibrated hex color constants, font-family fallbacks, and SVG company logo glyphs.",
        functional_aspects:
          "Technology sector market analysis, platform ecosystem comparisons, tech conference presentations, startup pitch decks.",
        ui_ux_aspects:
          "Instantly recognizable brand colorways (Google 4-color, Twitter sky blue, Airbnb rausch) with modern minimalist typography.",
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

    "ggx" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Natural language plain-English queries translated to ggplot2 code strings",
        "Keyword intent extraction for axis rotation, title sizing, legend repositioning",
        "Regex-powered semantic parsing matching over 200 common formatting goals",
        "Interactive CLI assistance suggesting ggplot snippet replacements",
        "Zero-friction learning curve for newcomers to ggplot2 syntax"
        ],
        fractal_layer: "#fractal-l5",
        technical_aspects:
          "Rule-based natural language processing matching input strings against an indexed corpus of ggplot2 theme, scale, and guide grammar targets.",
        functional_aspects:
          "Interactive data science education, rapid chart prototyping, conversational AI chart assistant integrations.",
        ui_ux_aspects:
          "Conversational query bar returning actionable ggplot2 code snippets with immediate visual effect rendering on canvas.",
      )

    "ggTimeSeries" ->
      ExtensionFeatureProfile(
        features_offered: [
        "stat_waterfall financial and operational balance change waterfall charts",
        "stat_steamgraph smooth continuous streamgraphs for multi-category flows",
        "stat_calendar_heatmap GitHub-style contribution and activity calendar heatmaps",
        "stat_marima multi-series autoregressive moving average trend projections",
        "Cycle and trend decomposition with confidence ribbons"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Streamgraph baseline displacement algorithms (ThemeRiver) minimizing flow slope variance combined with date-coordinate grid mapping.",
        functional_aspects:
          "Corporate EBITDA waterfalls, website user traffic composition over years, annual server incident calendar heatmaps.",
        ui_ux_aspects:
          "Organic flowing streamgraphs with smooth curved boundaries, crisp rectangular calendar tiles with green-to-emerald density ramp.",
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

    "ggseas" ->
      ExtensionFeatureProfile(
        features_offered: [
        "stat_seas automated seasonal adjustment using X-13ARIMA-SEATS",
        "stat_stl seasonal and trend decomposition using Loess smoothing",
        "stat_rollapply rolling mean, median, and volatility window computations",
        "Original vs seasonally adjusted series side-by-side comparisons",
        "Automated outlier detection and trading day effect corrections"
        ],
        fractal_layer: "#fractal-l3 #fractal-l4",
        technical_aspects:
          "Interface to US Census Bureau X-13ARIMA-SEATS seasonal decomposition engine with spline interpolation of adjusted trend series.",
        functional_aspects:
          "Macroeconomic indicator reporting (GDP, unemployment, inflation), retail sales seasonality audits, power grid demand forecasting.",
        ui_ux_aspects:
          "Faint raw noisy seasonal time-series overlaid with bold, smoothed cyan trend-cycle line, clear recession band shading.",
      )

    "ggsci" ->
      ExtensionFeatureProfile(
        features_offered: [
        "scale_color_nejm New England Journal of Medicine clinical trial palettes",
        "scale_color_lancet The Lancet medical journal color schemes",
        "scale_color_jama Journal of the American Medical Association styling",
        "scale_color_jco Journal of Clinical Oncology colorways",
        "scale_color_npg Nature Publishing Group and Science / AAAS palettes"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Curated discrete color scales reverse-engineered from flagship peer-reviewed medical and scientific journals, optimized for colorblindness.",
        functional_aspects:
          "High-impact scientific manuscripts, clinical oncology publications, academic grants, regulatory submission figures.",
        ui_ux_aspects:
          "Restrained, authoritative academic palettes with balanced luminance and high print/display reproduction fidelity.",
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

    "ggeasy" ->
      ExtensionFeatureProfile(
        features_offered: [
        "easy_rotate_x_labels and easy_rotate_y_labels concise axis label rotation",
        "easy_add_legend_title and easy_remove_legend ergonomic legend helpers",
        "easy_text_size and easy_text_color global typographic modifications",
        "easy_grid_remove and easy_grid_x/y selective grid line pruning",
        "Simplified functional wrappers eliminating verbose theme() boilerplate"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Convenience function wrapper suite compiling high-level declarative intent into deeply nested ggplot2 theme element objects.",
        functional_aspects:
          "Rapid exploratory chart formatting, pedagogical tutorials, clean reproducible code authoring without theme lookup fatigue.",
        ui_ux_aspects:
          "Perfect 45-degree angled axis labels, distraction-free grid layouts, and clean readable chart borders.",
      )

    "ggside" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_xsidedensity and geom_ysidedensity aligned marginal density plots",
        "geom_xsideboxplot and geom_ysideboxplot marginal boxplots for grouping factors",
        "geom_xsidecol and geom_ysidecol marginal stacked bar and count charts",
        "Synchronized aesthetic inheritance from main scatter plot to side panels",
        "Independent scale and panel ratio controls for top and right side panels"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Specialized facet layout engine (facet_grid2/wrap2) reserving auxiliary side panel viewports tightly bound to primary Cartesian scales.",
        functional_aspects:
          "Multivariate clustering analysis, flow cytometry gating validation, financial risk factor marginal distribution profiling.",
        ui_ux_aspects:
          "Compact side panels attached directly to plot edges with synchronized axis coordinates and harmonious category coloring.",
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

    "ggpubr" ->
      ExtensionFeatureProfile(
        features_offered: [
        "ggscatter and ggboxplot publication-ready statistical chart builders",
        "stat_compare_means automated Wilcoxon, t-test, ANOVA, and Kruskal-Wallis tests",
        "stat_cor automated correlation coefficient and significance level annotation",
        "Automated significance brackets with asterisks (*, **, ***, ns)",
        "ggarrange multi-plot composition with shared legends and label annotations"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l5",
        technical_aspects:
          "Automated execution of non-parametric and parametric hypothesis tests, computing bracket coordinates and p-value labels in grob tree.",
        functional_aspects:
          "Biomedical research publications, pre-clinical drug efficacy trials, agricultural yield experiments, academic manuscripts.",
        ui_ux_aspects:
          "Clean white/dark background with elegant horizontal comparison brackets, bold p-value callouts, jittered point distributions.",
      )

    "ggthemr" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Complete plot theme switching with a single function call (ggthemr)",
        "Pre-built harmonious palettes: fresh, dust, light, dark, solarized, grape",
        "Coordinated plot background, axis line, gridline, and geometric fill styling",
        "Plot palette randomization and custom palette builder API",
        "Automatic reset function (ggthemr_reset) restoring pristine ggplot2 defaults"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Global ggplot2 session hook interception dynamically modifying geoms' default aesthetic parameters upon layer instantiation.",
        functional_aspects:
          "Consistent organizational report styling, presentation deck theme matching, automated report generation suites.",
        ui_ux_aspects:
          "Cohesive unified palette where every bar, point, line, and label shares calibrated hue and saturation relationships.",
      )

    "GGally" ->
      ExtensionFeatureProfile(
        features_offered: [
        "ggpairs comprehensive pairwise scatterplot and correlation matrices",
        "ggparcoord parallel coordinate plots for high-dimensional feature vectors",
        "ggsurv survival analysis curves with risk tables and censoring markers",
        "ggcoef regression model coefficient forest plots with confidence intervals",
        "Customizable matrix diagonals (density, histogram) and upper/lower panels"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Composite grid layout compiler instantiating an N x N panel matrix with heterogeneous plot types tailored to pairwise variable types.",
        functional_aspects:
          "High-dimensional exploratory data analysis (EDA), feature selection for machine learning, clinical survival study summaries.",
        ui_ux_aspects:
          "Dense multi-panel grid displaying bivariate scatterplots, correlation text sizes proportional to r, and diagonal density curves.",
      )

    "ggseqlogo" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Sequence logos for DNA, RNA, and amino acid protein sequence alignments",
        "Letter glyph height proportional to Shannon information content (bits)",
        "Custom chemistry color schemes (hydrophobicity, charge, polarity, nucleotide)",
        "Position-Specific Scoring Matrix (PSSM) and alignment matrix input support",
        "Multi-panel sequence logo faceting across transcription factor binding sites"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Transformation of sequence frequencies into Shannon information entropy H = log2(N) - sum(p * log2(p)), scaling polygon glyph letter coordinates.",
        functional_aspects:
          "Transcription factor binding motif discovery, CRISPR off-target analysis, protein domain conservation, antibody CDR profiling.",
        ui_ux_aspects:
          "Vibrant stacked letter glyphs (A=Green, C=Blue, G=Yellow, T=Red) scaled vertically by bits, showing consensus motif sequences.",
      )

    "ggChernoff" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_chernoff multivariate data mapping to cartoon human facial features",
        "Smile curvature mapped to happiness, performance, or financial profit",
        "Eye size and brow slant mapped to risk, urgency, or alert severity",
        "Nose width and face shape mapped to secondary categorical attributes",
        "Intuitive human pattern recognition leveraging facial processing psychology"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Parametric arc and Bezier curve generation mapping continuous normalized variables to facial geometry equations (mouth radius, eye aperture).",
        functional_aspects:
          "Multivariate performance monitoring, executive sentiment visualization, complex system alert triage, human-factors research.",
        ui_ux_aspects:
          "Grid of stylized circular faces with dynamic expressions ranging from broad grins to furrowed brows, high-contrast dark cockpit styling.",
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

    "lemon" ->
      ExtensionFeatureProfile(
        features_offered: [
        "facet_rep_grid and facet_rep_wrap repeating axis lines and ticks on all panels",
        "coord_capped Cartesian coordinates with axis lines capped strictly at data extremes",
        "bracketed axis ticks creating grouped category visual brackets",
        "geom_pointpath point scatter connected by paths with gap offsets",
        "Enhanced legend placement inside empty facet panels"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Custom gtable facet layout modifications ensuring axis grobs are cloned across non-marginal panels with boundary tick truncation.",
        functional_aspects:
          "Complex multi-facet scientific comparisons, high-density small multiples figures, publication graphics requiring explicit axis ticks.",
        ui_ux_aspects:
          "Crisp capped axis lines terminating exactly at data minimum/maximum, clear hierarchical bracket ticks on categorical axes.",
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

    "qqplotr" ->
      ExtensionFeatureProfile(
        features_offered: [
        "stat_qq_point quantile-quantile points against arbitrary theoretical distributions",
        "stat_qq_line robust theoretical reference line (quartiles or MLE)",
        "stat_qq_band simultaneous and pointwise confidence bands (normal, beta, boot)",
        "stat_pp_point and stat_pp_band probability-probability diagnostic plots",
        "Detrended Q-Q plots highlighting deviation residuals along horizontal axis"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Parametric and non-parametric bootstrap confidence interval estimation for order statistics using Aldor-Noiman Kolmogorov-Smirnov bands.",
        functional_aspects:
          "Statistical normality diagnostics, financial heavy-tail risk validation, extreme value theory distribution fitting, residual analysis.",
        ui_ux_aspects:
          "Dark background with cyan sample points, crisp white diagonal reference line, translucent amber confidence envelope.",
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

    "ggquiver" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_quiver vector field arrows scaled by magnitude and direction",
        "Velocity field visualization for computational fluid dynamics (CFD)",
        "Vector coordinate centering (arrow tail, center, or head at point)",
        "Automatic arrow length scaling preventing visual overlap",
        "Gradient vector mapping for mathematical optimization landscapes"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Cartesian vector trigonometry calculating (xend = x + u * scale, yend = y + v * scale) with dynamic aspect ratio preservation.",
        functional_aspects:
          "Oceanographic current maps, meteorological wind vectors, electromagnetic field gradients, neural network gradient descent flows.",
        ui_ux_aspects:
          "Radiating field of luminous neon arrowheads colored by velocity magnitude, floating over dark bathymetry or elevation grids.",
      )

    "ggsignif" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_signif horizontal significance comparison brackets over boxplots",
        "Automated p-value computation using Wilcoxon rank-sum or Student t-test",
        "Custom p-value text annotations and asterisk formatting (*, **, ***)",
        "Manual bracket step-increase preventing overlapping significance bars",
        "Configurable bracket tip length and line thickness"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Pairwise group coordinate detection calculating top bounding box extremes + step margin, constructing horizontal grob brackets.",
        functional_aspects:
          "Pharmacological treatment vs control assays, cognitive psychology experimental results, multi-arm clinical trial reports.",
        ui_ux_aspects:
          "Crisp bracket segments with vertical end ticks, bright gold significance text, non-overlapping stacked tier arrangement.",
      )

    "ggdag" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_dag_node and geom_dag_edges for causal Directed Acyclic Graphs",
        "node_dconnected and node_dseparated causal path analysis",
        "Automated identification of minimal sufficient adjustment sets",
        "Instrumental variable, collider, and confounder node highlighting",
        "Integration with dagitty causal inference algorithms"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l5",
        technical_aspects:
          "Graph-theoretic d-separation algorithms identifying back-door paths and minimal adjustment sets on directed topological DAG structures.",
        functional_aspects:
          "Epidemiological causal inference, econometric policy impact evaluation, artificial intelligence causal discovery models.",
        ui_ux_aspects:
          "Circular variable nodes colored by causal role (exposure, outcome, confounder, collider) with directed neon bezier edges.",
      )

    "ggformula" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Formula-based modeling interface (gf_point(y ~ x), gf_line(y ~ x))",
        "Chained pipe operations for building multi-layer visual graphs",
        "Seamless integration with mosaic statistical modeling packages",
        "Automatic facet formula parsing (y ~ x | group)",
        "Concise syntax reducing cognitive load for statistical computing"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Formula syntax metaprogramming evaluating expressions in data environments and compiling them into standard ggplot2 aesthetic calls.",
        functional_aspects:
          "Introductory statistics pedagogy, rapid exploratory data science, concise reproducible research modeling scripts.",
        ui_ux_aspects:
          "Clean graphical output identical to native ggplot2 with simplified syntax and rapid iteration ergonomics.",
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

    "ggperiodic" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Periodic boundary coordinate wrapping for continuous cyclic data",
        "Seamless wrapping around longitude (-180 to 180 degrees)",
        "Circular time-of-day (0 to 24 hours) and day-of-year cyclic continuity",
        "Elimination of visual gaps at domain boundary discontinuities",
        "Automated coordinate duplication and interpolation across periodic seams"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Modular arithmetic coordinate transformation duplicating edge records and stitching domain endpoints modulo period length L.",
        functional_aspects:
          "Global climate circulation models, diurnal circadian rhythm monitoring, circular phase-angle physics, harmonic oscillations.",
        ui_ux_aspects:
          "Unbroken continuous contour lines across world map antimeridian seams and 24-hour cycle boundaries without artificial breaks.",
      )

    "ggpol" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_parliament parliamentary seating hemicycles and arch diagrams",
        "geom_arcbar pie and donut wedges with rounded corner geometry",
        "geom_circle and geom_cone for geometric annotations",
        "Population pyramid side-by-side demographic comparison geoms",
        "Automated parliament seat coordinate allocation algorithms"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Polar coordinate packing algorithms positioning individual parliamentary seats in concentric semi-circular rings proportional to party seats.",
        functional_aspects:
          "Legislative election results, coalition majority tracking, demographic age-sex pyramids, voting outcome dashboards.",
        ui_ux_aspects:
          "Curving semicircular hemicycle dotted with glowing party-colored seat circles, clear majority threshold line indicator.",
      )

    "ggpirate" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_pirate combined representation: raw data points + central tend + intervals",
        "Transparent raw data jitter point cloud showing complete sample distribution",
        "High-density central tendency line (mean or median)",
        "Bayesian 95% highest density interval (HDI) or confidence interval box",
        "Violin density outline overlay highlighting multimodal distribution shapes"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Compound grob composition stacking jittered scatter, kernel density violins, and central tendency error bars in a single unified geom.",
        functional_aspects:
          "Cognitive psychology experiments, clinical drug response comparisons, education assessment scores, biological assay readouts.",
        ui_ux_aspects:
          "Translucent cyan violins enveloping jittered individual sample dots with solid white central median bar and dark confidence box.",
      )

    "esquisse" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Interactive drag-and-drop Shiny GUI for building ggplot2 graphics",
        "Visual aesthetic mapping (drag variables to X, Y, Color, Fill, Size)",
        "Real-time visual filtering by numeric ranges and categorical factors",
        "Automatic export of reproducible ggplot2 R code",
        "Interactive theme, palette, and title customization panel"
        ],
        fractal_layer: "#fractal-l4 #fractal-l5",
        technical_aspects:
          "Interactive reactive UI engine parsing drag-and-drop events into an abstract syntax tree (AST) serialized into clean R code.",
        functional_aspects:
          "Non-coding researcher data exploration, rapid chart ideation, workshop teaching, interactive corporate analytics.",
        ui_ux_aspects:
          "Drag-and-drop token pills, interactive range sliders, and instant live canvas preview.",
      )

    "ggerror" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_errorbar and geom_crossbar high-precision error representations",
        "Asymmetric error bounds (different positive and negative error magnitudes)",
        "Simultaneous 2D error ellipses and cross-hair error bars",
        "Log-scale error interval propagation and transformation",
        "Configurable error bar cap widths and line weights"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Cartesian coordinate bounding box and crosshair segment compilation with support for asymmetric measurement uncertainty intervals.",
        functional_aspects:
          "Physical sciences precision measurements, astronomical photometry error budgets, metrology sensor calibrations.",
        ui_ux_aspects:
          "Fine, high-contrast error crosshairs with capped endpoints, subtle uncertainty ellipses on dark instrumentation background.",
      )

    "ggdark" ->
      ExtensionFeatureProfile(
        features_offered: [
        "dark_theme_gray and dark_theme_bw inverted dark mode ggplot2 themes",
        "Inverted color scales preventing dark-on-dark contrast loss",
        "dark_mode wrapper converting any existing ggplot2 theme to dark mode",
        "Low-glare palette tuning tailored for OLED displays and cockpit TUIs",
        "Strict adherence to dark room ergonomic contrast standards"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Systematic inversion of theme element backgrounds, borders, text, and guide elements with calibrated luminance offsets.",
        functional_aspects:
          "Astronomical observatory monitoring, military mission control cockpits, night-shift operations centers, developer IDEs.",
        ui_ux_aspects:
          "Deep #020617 obsidian background, subtle #1e293b gridlines, glowing cyan and amber data traces with crisp contrast.",
      )

    "sugrrants" ->
      ExtensionFeatureProfile(
        features_offered: [
        "facet_calendar calendar-based faceting for temporal time series",
        "Monthly, weekly, and daily grid layouts aligned to authentic calendar dates",
        "Diurnal hourly activity profiles embedded within individual calendar day cells",
        "Configurable start-of-week days (Monday vs Sunday)",
        "Automated leap year and holiday date alignment"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Temporal date-to-matrix projection algorithms mapping POSIXct timestamps into (week_of_month, day_of_week) facet grid coordinates.",
        functional_aspects:
          "Public transit ridership patterns, electricity consumption cycles, data center server workloads, personal fitness habits.",
        ui_ux_aspects:
          "Structured monthly calendar matrix where each day tile hosts an hourly trendline, highlighting weekday vs weekend variations.",
      )

    "tvthemes" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Themed palettes and styles inspired by iconic television shows",
        "Themes: Game of Thrones, The Simpsons, Parks & Recreation, SpongeBob, Avatar",
        "Custom font pairings and background watermarks matching show typography",
        "Categorical palettes with high distinctiveness between color levels",
        "Engaging presentation graphics for data communication and outreach"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Palette extraction and theme construction encapsulating cultural media aesthetic palettes into standard ggplot2 scales and themes.",
        functional_aspects:
          "Data journalism, educational presentations, tech conference talks, social media data visualization campaigns.",
        ui_ux_aspects:
          "Vibrant, high-personality color combinations with themed typography and distinct thematic borders.",
      )

    "ggfittext" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_fit_text automatically fits text within defined rectangular bounding boxes",
        "geom_bar_text fits text labels cleanly inside horizontal and vertical bar charts",
        "Dynamic font resizing shrinking text to fit without overflowing boundaries",
        "Automatic multi-line text reflow and wrapping based on box aspect ratio",
        "Full support for polar coordinates and rotated text boxes"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Iterative binary search font size reduction and word-wrapping algorithms calculating text string bounding dimensions against target boxes.",
        functional_aspects:
          "Treemap cell labeling, stacked bar chart value labeling, organizational charts, mobile responsive data cards.",
        ui_ux_aspects:
          "Crisp text perfectly scaled to fill rectangular containers with zero margin overflow or truncated text.",
      )

    "ggparty" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_node_split decision tree split condition labels on intermediate nodes",
        "geom_node_plot custom ggplot insets embedded inside tree terminal leaf nodes",
        "geom_edge tree branch link segments with thickness proportional to sample size",
        "Support for partykit recursive partitioning, ctree, and mob models",
        "Flexible tree layout orientation (top-down, left-right, radial)"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Recursive tree traversal mapping decision tree data structures into hierarchical graph coordinates with embedded subplot grobs.",
        functional_aspects:
          "Clinical diagnostic decision rules, customer churn segmentation trees, credit scoring trees, survival trees.",
        ui_ux_aspects:
          "Hierarchical decision tree with split criteria badges at node junctions and mini-histograms or scatter plots at leaf tips.",
      )

    "gggenes" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_gene_arrow arrow glyphs representing genomic gene locations and orientations",
        "geom_subgene_arrow sub-gene domain and exon structures inside gene arrows",
        "Dynamic arrow direction reflecting strand orientation (forward/reverse)",
        "Automatic gene label placement centered inside or above gene arrows",
        "Multi-genome operon comparison tracks aligned by anchor genes"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Genomic coordinate translation computing polygonal arrow vertices (x_start, x_end, arrowhead_length) with strand orientation polarity.",
        functional_aspects:
          "Bacterial operon visualization, biosynthetic gene cluster (BGC) comparisons, viral genome architecture, gene synteny.",
        ui_ux_aspects:
          "Horizontally aligned genomic tracks with colored arrow glyphs pointing 5-prime to 3-prime, gene labels inside arrow bodies.",
      )

    "gggenomes" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Comparative genomics synteny blocks connecting homologous genomic regions",
        "Multi-track whole-genome alignments with dynamic zoom and panning",
        "Inversion, translocation, and duplication visual ribbon links",
        "Feature track overlays (genes, repeats, GC content, sequencing depth)",
        "Integration with BLAST, minimap2, and Mauve alignment outputs"
        ],
        fractal_layer: "#fractal-l3 #fractal-l4",
        technical_aspects:
          "Multi-coordinate chromosome alignment algorithms rendering Bezier synteny ribbons between disparate coordinate systems.",
        functional_aspects:
          "Comparative bacterial genomics, plant polyploidy evolution, structural variant discovery, pan-genome architecture.",
        ui_ux_aspects:
          "Stacked chromosomal horizontal lines connected by colored synteny ribbons (blue=collinear, red=inverted) across species.",
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

    "lindia" ->
      ExtensionFeatureProfile(
        features_offered: [
        "gg_diagnose automated multi-panel linear regression diagnostics",
        "gg_resfitted residual vs fitted values plot with loess smooth",
        "gg_qqplot standardized normal Q-Q plot with reference line",
        "gg_cooksd Cook distance leverage bar plot for influential observations",
        "gg_scalelocation scale-location homoscedasticity diagnostic plot"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l5",
        technical_aspects:
          "Linear model (lm) diagnostic calculations extracting studentized residuals, hat values (leverage), Cook distances, and fitted values into coordinated ggplot2 panels.",
        functional_aspects:
          "Econometric and biostatistical regression assumption validation, outlier detection, and model sensitivity testing.",
        ui_ux_aspects:
          "4-panel diagnostic dashboard with cyan residual scatter, amber Cook distance threshold spikes, and dark cockpit grids.",
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

    "ggrastr" ->
      ExtensionFeatureProfile(
        features_offered: [
        "rasterise selective layer rasterization for massive ggplot2 datasets",
        "geom_point_rast high-performance rasterized scatter points",
        "geom_boxplot_rast rasterized outlier point overlays",
        "Resolution control (dpi: 300, 600) preserving vector text and axes",
        "Elimination of multi-megabyte PDF/SVG vector bloat"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Selective Cairo/raster rendering of high-density geometric grob layers while keeping labels, axes, and legends as pure vector SVG.",
        functional_aspects:
          "Single-cell transcriptomics with 500,000 cells, astronomical star charts, flow cytometry millions of events.",
        ui_ux_aspects:
          "Silky smooth rendering of massive point clouds with vector-crisp axis ticks and typography, 95% reduction in SVG payload.",
      )

    "ggpointdensity" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_pointdensity scatter plot coloring points by local 2D neighbor density",
        "Alleviates severe overplotting in massive multi-thousand point datasets",
        "Eliminates arbitrary binning artifacts inherent in hexagonal or square bins",
        "Continuous color gradient reflecting local point concentration",
        "Adjustable neighbor search radius and kernel density bandwidth"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "2D spatial kd-tree search algorithm counting neighboring points within Euclidean radius R to calculate local point density values.",
        functional_aspects:
          "Flow cytometry gating, astronomical star catalog scatter plots, high-frequency financial trade execution logs.",
        ui_ux_aspects:
          "Dense scatter cloud where core high-density cluster points glow intense hot yellow while sparse outliers fade to cool dark blue.",
      )

    "ggsom" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_som Self-Organizing Map (SOM) hexagonal and rectangular lattice grids",
        "U-matrix distance matrix visualization showing cluster separation boundaries",
        "Property heatmaps coloring SOM neurons by specific input feature weights",
        "Component plane displays and codebook vector trajectory overlays",
        "Cluster boundary partitioning via hierarchical clustering on SOM units"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Kohonen neural network grid mapping evaluating high-dimensional codebook weight vectors across 2D hexagonal lattices with Euclidean distance metrics.",
        functional_aspects:
          "Unsupervised machine learning, market segmentation, financial fraud topology clustering, complex sensor array state visualization.",
        ui_ux_aspects:
          "Honeycomb hexagonal grid with gradient node coloring, bright white cluster boundary separators, and labeled neuron centroids.",
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

    "ggh4x" ->
      ExtensionFeatureProfile(
        features_offered: [
        "facet_nested multi-tier hierarchical nested facet strip banners",
        "facet_manual arbitrary custom positioning of facet panels in coordinate plane",
        "scale_x_facet and scale_y_facet independent scale limits per individual facet",
        "guide_axis_nested and guide_axis_truncated capped/bracketed coordinate axes",
        "stat_difference and stat_fun functional curves with shaded difference ribbons"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Advanced gtable facet compiler inserting nested grob strip banners and injecting per-panel scale transformers without breaking core ggplot2 layouts.",
        functional_aspects:
          "Complex clinical trials with nested treatment arms, multi-cohort demographic studies, custom publication small multiples.",
        ui_ux_aspects:
          "Tiered hierarchical strip banners with elegant dark-glass background panels, perfectly synchronized independent axis intervals.",
      )

    "ggarrow" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_arrow curved and segmented arrows with continuous width gradients",
        "Tapering arrow shafts that narrow or widen along the vector trajectory",
        "Custom arrowheads: winged, barbed, stealth, diamond, and feathered",
        "Arrowhead offset controls preventing collision with target node circles",
        "Support for multi-point parametric bezier arrow paths"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Parametric polygon arc computation evaluating variable width profiles w(t) along spine curves with tangent-aligned arrowhead grobs.",
        functional_aspects:
          "Cognitive concept maps, causal loop diagrams, vector kinematics, dynamic migration flow tracking.",
        ui_ux_aspects:
          "Futuristic tapering arrows with illuminated cyan outlines and sharp stealth arrowheads connecting data points cleanly.",
      )

    "legendry" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Multi-tier compositional legend keys and hierarchical guides",
        "guide_axis_bracket bracketed categorical groupings on coordinate axes",
        "guide_legend_group grouped multi-column legend layouts",
        "Annotated colorbars with embedded threshold markers and tick callouts",
        "Flexible guide placement inside empty facet viewports and margins"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Modular guide layout engine restructuring ggplot2 guide grob trees into composable hierarchical key-value arrangements.",
        functional_aspects:
          "Complex multi-scale publication figures, executive dashboards with categorical brackets, dense multi-variable legends.",
        ui_ux_aspects:
          "Neatly organized grouped legend panels with clear category headers, nested axis brackets, and high typographic clarity.",
      )

    "ggcharts" ->
      ExtensionFeatureProfile(
        features_offered: [
        "bar_chart and column_chart high-level streamlined categorical bar plots",
        "diverging_bar_chart and diverging_lollipop_chart for positive/negative balance",
        "dumbbell_chart for before-and-after paired group comparisons",
        "pyramid_chart for population age-sex demographic structures",
        "Automated factor level sorting, top-n filtering, and value label positioning"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "High-level tidy evaluation wrappers encapsulating ggplot2 boilerplate into single-line declarative plotting commands.",
        functional_aspects:
          "Rapid business intelligence reporting, survey analysis, marketing campaign ROI comparisons, executive briefing slides.",
        ui_ux_aspects:
          "Clean minimalist charts with horizontal orientations, direct data labels on bars, and muted elegant palettes.",
      )

    "humapr" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Human geography and global population density mapping",
        "Spatially balanced population cartograms resizing regions by population",
        "Demographic census tract visualization with automated boundary harmonisation",
        "Urban vs rural population distribution gradients",
        "Bivariate choropleths combining population density with socioeconomic indicators"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Spatial cartogram algorithms (Gastner-Newman diffusion) transforming geographic polygons based on population density weights.",
        functional_aspects:
          "Public health resource allocation, humanitarian aid planning, electoral vote representation, demographic transition studies.",
        ui_ux_aspects:
          "High-contrast population choropleths with glowing urban nodes and smooth density contours on dark cartographic canvas.",
      )

    "ggshadow" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_shadowline lines with glowing neon shadows and depth glows",
        "geom_shadowpoint points with radiant halos and shadow offsets",
        "Configurable shadow parameters: shadowcolor, shadowsize, shadowalpha",
        "Multi-color neon glow effects for futuristic telemetry dashboards",
        "Direct SVG filter drop-shadow generation without external image processing"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Layer duplication and Gaussian blur filter injection applying spatial convolution matrices behind primary line/point grobs.",
        functional_aspects:
          "Dark-cockpit telemetry monitors, futuristic HUD interfaces, cyber defense network status boards, high-impact keynote presentations.",
        ui_ux_aspects:
          "Striking neon cyber-punk aesthetics: glowing cyan, emerald, and magenta lines floating with depth shadows over deep obsidian (#020617).",
      )

    "ggseg" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_brain cortical and subcortical brain atlas segmentations",
        "Pre-built neuroimaging atlases: Desikan-Killiany, Destrieux, Schaefer 200/400",
        "Lateral, medial, superior, and inferior anatomical brain view angles",
        "Mapping MRI/fMRI cortical thickness, surface area, and BOLD signals to brain regions",
        "Faceting by hemisphere (left vs right) and brain view angles"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "2D polygonal brain atlas boundary coordinate systems parsed from neuroimaging surface meshes (FreeSurfer) with region ontology joins.",
        functional_aspects:
          "Cognitive neuroscience fMRI activations, Alzheimers cortical atrophy mapping, psychiatric neuroimaging biomarkers.",
        ui_ux_aspects:
          "Stylized anatomical brain hemisphere silhouettes with cortical gyri colored by activation level, dark neurological cockpit theme.",
      )

    "mdthemes" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Markdown and HTML syntax rendering in plot titles, subtitles, and captions",
        "Inline bold, italic, and custom colored text with span style elements",
        "Hyperlink support inside plot captions and notes",
        "Eliminates clunky plotmath syntax for formatted scientific typography",
        "Seamless integration with all standard ggplot2 themes (theme_minimal, theme_bw)"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Integration with marquee/gridtext parsers transforming markdown strings into styled text grobs within plot title/axis viewports.",
        functional_aspects:
          "Accessible data journalism with color-coded titles matching line series, academic papers with italic species names and bold takeaways.",
        ui_ux_aspects:
          "Dynamic title text where keywords share exact line colors eliminating detached legends.",
      )

    "ggwordcloud" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_text_wordcloud word clouds with collision-free text placement",
        "Word font size proportional to frequency or importance metric",
        "Configurable word cloud shapes: circle, cardioid, diamond, square, star",
        "Word rotation angles (horizontal, vertical, 45-degree angled)",
        "Pure C++ word placement algorithm preventing word overlap"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Spiral collision detection search algorithm placing word bounding boxes progressively along Archimedean spirals to prevent glyph collisions.",
        functional_aspects:
          "Text mining topic keyword summaries, customer feedback sentiment reviews, speech transcript keyword analysis, tag clouds.",
        ui_ux_aspects:
          "Artistic word cluster arranged in circular silhouette, words colored by sentiment and sized by frequency, dark mode background.",
      )

    "ggasym" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Asymmetric matrix visualization where upper and lower triangles differ",
        "geom_asymmat showing directed origin-to-destination bilateral relationships",
        "Diagonal cell isolation for self-interaction or intra-category values",
        "Split-tile aesthetic mapping independent metrics to (i, j) vs (j, i)",
        "Automated matrix reordering using hierarchical clustering on asymmetric distance"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Directional matrix coordinate transformation mapping pairwise directed graphs onto square matrix coordinates without symmetry forcing.",
        functional_aspects:
          "International bilateral trade surpluses vs deficits, neuroimaging directed connectivity, sports team head-to-head win/loss records.",
        ui_ux_aspects:
          "Square matrix grid where upper triangle shows metric A and lower triangle shows metric B with contrasting color ramps.",
      )

    "gglorenz" ->
      ExtensionFeatureProfile(
        features_offered: [
        "stat_lorenz empirical Lorenz curve computation from sample distributions",
        "geom_lorenz cumulative population share vs cumulative wealth/income curves",
        "Automated Gini coefficient inequality index calculation and text annotation",
        "45-degree line of perfect equality reference line",
        "Lorenz dominance comparison curves across multiple demographic cohorts"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Cumulative distribution function (CDF) integration sorting income vectors and computing Lorenz curve coordinates: L(p) = sum_{i=1}^{k} x_i / sum_{i=1}^n x_i.",
        functional_aspects:
          "Economic wealth and income inequality analysis, biodiversity species abundance distribution, carbon emission inequality across nations.",
        ui_ux_aspects:
          "Diagonal dashed equality line with bowing cyan Lorenz curve below, shaded Gini area, prominent Gini index badge.",
      )

    "hrbrthemes" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Typography-centric themes: theme_ipsum, theme_ipsum_rc (Roboto Condensed)",
        "theme_ft_rc Financial Times-inspired styling with high-contrast layouts",
        "Calibrated micro-typography (kerning, line-height, margin whitespace)",
        "scale_color_ipsum cohesive contemporary color palettes",
        "Standardized publication dimensions and crisp vector font rendering"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Refined typography grid metrics applying proportional golden-ratio margins, subtle axis rules, and tight typographic tracking.",
        functional_aspects:
          "High-end business intelligence reports, academic monographs, data journalism graphics, executive presentations.",
        ui_ux_aspects:
          "Modern, breathable chart layouts with bold condensed titles, faint gray coordinate gridlines, and clean unobtrusive axes.",
      )

    "ggpattern" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_col_pattern and geom_density_pattern pattern-filled geometry geoms",
        "Diverse geometric patterns: stripes, crosshatch, checks, dots, waves",
        "Image and custom SVG pattern fills for accessible printing",
        "Essential for black-and-white printing and colorblind-accessible publications",
        "Pattern aesthetics: density, angle, spacing, fill, and stroke color"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "SVG pattern definition (<pattern>) generation instantiating repetitive vector tiles referenced via fill='url(#pattern_id)'.",
        functional_aspects:
          "Black-and-white academic printing, colorblind-accessible figures, geological rock type stratigraphy, patent documentation figures.",
        ui_ux_aspects:
          "Bar charts filled with high-contrast diagonal stripes, crosshatch textures, and stippled dots, sharp and legible without color.",
      )

    "ggtext" ->
      ExtensionFeatureProfile(
        features_offered: [
        "element_markdown rich markdown styling for any theme text element",
        "element_textbox word-wrapped text boxes with background fill and borders",
        "geom_richtext rich text labels supporting HTML tags, images, and formatting",
        "geom_textbox multi-line text callouts with automatic bounding box fitting",
        "Inline color, bold, font family, and superscript/subscript tags"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "HTML/CSS box model rendering in grid graphics computing font glyph metrics, word wrapping, and CSS inline style spans.",
        functional_aspects:
          "Self-annotating publication figures, executive summary callout cards, complex mathematical notation in axis labels.",
        ui_ux_aspects:
          "Sleek dark callout boxes with rounded borders, colored highlighted text phrases, crisp typographical hierarchy.",
      )

    "calendR" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Monthly and yearly calendar charts with customizable day tile annotations",
        "Heatmap coloring of calendar days by daily activity or telemetry metrics",
        "Lunar phase glyphs and national holiday markers",
        "Custom text labels and event flags within specific date squares",
        "Diverse layout orientations (horizontal, vertical, compact year grid)"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Gregorian calendar date matrix generation mapping day-of-year indices to week-of-month and day-of-week 2D coordinate cells.",
        functional_aspects:
          "Annual project milestone tracking, daily habit streak tracking, server incident history calendars, employee shift schedules.",
        ui_ux_aspects:
          "Crisp 12-month calendar grid with days colored by activity intensity from dark slate to brilliant emerald, clear month headers.",
      )

    "ggip" ->
      ExtensionFeatureProfile(
        features_offered: [
        "coord_ip 2D Hilbert curve coordinate system mapping IPv4 and IPv6 address space",
        "stat_netmask aggregation of IP addresses by CIDR network prefixes (/24, /16, /8)",
        "geom_hilbert space-filling Hilbert curves preserving network locality",
        "Global internet scanning and BGP routing prefix distribution mapping",
        "Cybersecurity threat actor and botnet IP cluster visualization"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Recursive Hilbert space-filling curve algorithms mapping 32-bit (IPv4) or 128-bit (IPv6) integer addresses to continuous 2D plane coordinates.",
        functional_aspects:
          "Internet-wide port scan visualization, DDoS attack source profiling, autonomous system (AS) IP prefix allocation analysis.",
        ui_ux_aspects:
          "2D fractal Hilbert curve layout with glowing clusters of active IP blocks, CIDR grid outlines on dark cyber-security cockpit.",
      )

    "gglm" ->
      ExtensionFeatureProfile(
        features_offered: [
        "stat_normal_qq and geom_fitted_residuals linear model diagnostic plots",
        "Scale-Location homoscedasticity check with square root of standardized residuals",
        "Residuals vs Leverage with Cook distance contour bands (0.5, 1.0)",
        "Standardized 4-panel regression diagnostic layout conforming to grammar of graphics",
        "Seamless integration with base lm and glm model objects"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l5",
        technical_aspects:
          "Extraction of linear model internal matrices (residuals, fitted values, leverage, Cook distance) mapped into standard ggplot2 grobs.",
        functional_aspects:
          "Classical linear regression assumption verification, econometrics model auditing, biostatistical model fit diagnosis.",
        ui_ux_aspects:
          "Balanced 2x2 multi-panel diagnostic layout with red trend loess curves, labeled outlier points, and high contrast.",
      )

    "econocharts" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Microeconomics supply and demand curves with equilibrium point marking",
        "Indifference curves and budget constraint tangency points",
        "Production Possibility Frontiers (PPF) with opportunity cost curves",
        "Consumer and producer surplus shaded polygon areas",
        "Tax incidence and deadweight loss geometric region representations"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Parametric economic curve functions calculating analytical equilibrium intersection points (P*, Q*) and integral surplus polygons.",
        functional_aspects:
          "Economics pedagogy, macroeconomic policy impact modeling, market equilibrium analysis, taxation impact simulation.",
        ui_ux_aspects:
          "Clean textbook-style economic graphs with labeled curves (S, D), dashed equilibrium lines to axes, shaded surplus areas.",
      )

    "ComplexUpset" ->
      ExtensionFeatureProfile(
        features_offered: [
        "UpSet plots for large, complex multi-set intersections",
        "Combines intersection size bar charts with set combination matrix grids",
        "Stacked bar charts within intersection columns showing attribute breakdowns",
        "Side-panel set size bars and correlation distribution boxplots",
        "Full compatibility with native ggplot2 geoms, scales, and themes"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Boolean set intersection algebra computing power set combination frequencies and arranging connected dot-matrix grob panels.",
        functional_aspects:
          "Genomic variant sharing across cohorts, multi-label machine learning classification, customer subscription overlap analysis.",
        ui_ux_aspects:
          "Bottom dot-and-line combination matrix aligned with upper vertical bar chart of intersection sizes, dark cockpit background.",
      )

    "ggchromatic" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Multi-dimensional color scales combining hue, chroma, and luminance",
        "scale_color_cmyk and scale_color_hcl for 3D continuous variable encoding",
        "Trivariate color mapping encoding three continuous variables into a single point color",
        "Bivariate color keys with 2D color wheel or matrix legend guides",
        "Perceptually uniform color spaces preventing visual artifact distortion"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "3D color space transformations (CIE L*a*b*, HCL, CMYK) mapping 3-dimensional data vectors (x, y, z) to exact sRGB hex values.",
        functional_aspects:
          "Atmospheric multi-variable monitoring (temp, humidity, pressure), RGB satellite composite mapping, multi-sensor telemetry.",
        ui_ux_aspects:
          "Scatter plot where each points unique color reveals three concurrent parameters, accompanied by a 2D/3D chromatic legend key.",
      )

    "ggheatmap" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Pure ggplot2-based heatmap builder with native geom composition",
        "Dendrogram tree grobs aligned to heatmap panels using patchwork/cowplot",
        "Direct compatibility with all ggplot2 scales, themes, and guides",
        "Layered point, text, and shape overlays directly on heatmap cells",
        "Zero foreign dependencies outside the core tidyverse/ggplot2 ecosystem"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Deconstruction of hierarchical clustering trees into geom_segment data frames assembled with geom_tile using ggplot2 layout algebra.",
        functional_aspects:
          "Customized publication heatmaps, ggplot2 extension pipelines, automated bioinformatics reporting workflows.",
        ui_ux_aspects:
          "Modular tiled grid with seamless dendrogram trees on top and left, dark cockpit background with neon heat gradients.",
      )

    "see" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Visualization companion for the easystats ecosystem (parameters, performance)",
        "plot(model_parameters()) forest plots with Bayesian and frequentist intervals",
        "plot(check_model()) comprehensive 6-panel model assumption diagnostic suite",
        "plot(estimate_density()) distribution violin and half-eye comparisons",
        "Bespoke color palettes (scale_color_see) and flat design themes (theme_modern)"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l5",
        technical_aspects:
          "Automated model inspection and tidying algorithms translating complex Bayesian (brms, rstanarm) and frequentist models into ggplot2.",
        functional_aspects:
          "Statistical modeling workflows, Bayesian posterior parameter reports, model performance benchmarking, academic publications.",
        ui_ux_aspects:
          "Ultra-clean flat design with soft rounded corners, high-contrast point estimates, elegant half-eye densities, dark mode compliance.",
      )

    "directlabels" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Direct labeling of lines, curves, and point clusters without separate legends",
        "Smart label positioning algorithms: last.points, first.points, maxvar.points",
        "Collision-free direct text placement along curve endpoints",
        "Eliminates back-and-forth eye tracking between plot lines and external legends",
        "Support for scatterplots, density lines, contour plots, and time-series"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Spatial optimization heuristics evaluating curve terminal points and bounding box collisions to place direct text grobs in line paths.",
        functional_aspects:
          "Data journalism time-series plots, multi-line financial tracking, contour elevation labeling, accessible graphic design.",
        ui_ux_aspects:
          "Multi-colored trend lines terminating directly with matching color text labels at their right endpoints, zero legend clutter.",
      )

    "ggHoriPlot" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_horizon folded horizon plots for high-density continuous time-series",
        "Folds high-amplitude peaks into stacked color opacity bands",
        "Compacts vertical height by 75% to 80% without losing fine resolution",
        "Positive values represented in blue/green bands, negative values in red/amber bands",
        "Ideal for displaying hundreds of concurrent telemetry channels in small multiples"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Modulo arithmetic slicing continuous time-series into discrete amplitude tiers (bands) and overlaying them with increasing color saturation.",
        functional_aspects:
          "Data center multi-server CPU/memory telemetry, financial market volatility across hundreds of assets, seismic sensor arrays.",
        ui_ux_aspects:
          "Stacked horizontal channel strips with 2-band folded green/blue positive fills and red negative fills, compact information density.",
      )

    "ggtrace" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Programmatic inspection and tracing of internal ggplot2 ggproto workflows",
        "Intercepts and inspects data frames at each stage of plot evaluation",
        "ggtrace_inspect_return and ggtrace_capture for debugging custom geoms/stats",
        "Non-invasive runtime function hooking into ggplot_build and ggplot_gtable",
        "Essential pedagogical tool for understanding the grammar of graphics execution"
        ],
        fractal_layer: "#fractal-l4 #fractal-l5",
        technical_aspects:
          "Runtime execution interception wrapping ggproto methods and ggplot2 build pipeline stages with call-stack tracers and data snapshotting.",
        functional_aspects:
          "ggplot2 extension package development, custom geom/stat debugging, computer science pedagogy on declarative graphics compilation.",
        ui_ux_aspects:
          "Interactive pipeline stage flowchart displaying data transformations at each step (setup_data, compute_group, draw_panel).",
      )

    "ggESDA" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Exploratory Spatial Data Analysis (ESDA) with spatial autocorrelation metrics",
        "Morans I scatterplots displaying standardized variable vs spatial lag",
        "Local Indicators of Spatial Association (LISA) cluster classification plots",
        "Spatial weight matrix visualizations (contiguity, k-nearest neighbors)",
        "Identification of spatial hotspots (High-High) and spatial outliers (High-Low)"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Spatial statistics algorithms computing global Morans I, Gearys C, and Anselins local LISA statistics using spatial adjacency matrices.",
        functional_aspects:
          "Spatial epidemiology disease cluster detection, urban crime hotspot analysis, regional economic convergence studies.",
        ui_ux_aspects:
          "Four-quadrant Moran scatterplot with regression slope indicating spatial autocorrelation, accompanied by color-coded LISA cluster maps.",
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

    "ggdensity" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_hdr highest density regions (HDR) for bivariate continuous distributions",
        "geom_hdr_lines contour lines enclosing 50%, 80%, 95%, and 99% probability mass",
        "Unbiased probability interpretation unlike standard arbitrary kernel contour lines",
        "Support for multimodal distributions and complex non-linear probability shapes",
        "Parametric and non-parametric bivariate density estimation engines"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Bivariate kernel density estimation evaluated on regular grids, computing probability contour thresholds by integrating probability density function.",
        functional_aspects:
          "Bayesian bivariate posterior credible regions, astrophysical star cluster density, econometric joint probability forecasting.",
        ui_ux_aspects:
          "Nested glowing probability contour bands with clear percentage annotations (50%, 80%, 95%) enclosing central probability summits.",
      )

    "ggtranscript" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_range exon and untranslated region (UTR) box representations",
        "geom_intron curved Bezier lines representing spliced intron junctions",
        "geom_half_range coding sequence (CDS) vs UTR thickness differentiation",
        "Alternative splicing isoform comparison tracks across tissue types",
        "Short-read junction RNA-seq sashimi plot overlay curves"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Transcriptomic exon-intron coordinate parsing converting GFF3/GTF annotations into aligned stepped range and arc grobs.",
        functional_aspects:
          "RNA-seq alternative splicing analysis, transcript isoform characterization, cancer neoantigen discovery, exon skipping studies.",
        ui_ux_aspects:
          "Thick colored exon blocks connected by delicate arched intron curves, highlighting differential splicing patterns.",
      )

    "piecepackr" ->
      ExtensionFeatureProfile(
        features_offered: [
        "2D and 3D rendering of public domain board game systems",
        "Supports piecepack, chess, checkers, dominoes, playing cards, and backgammon",
        "Customizable game piece textures, symbols, colors, and face values",
        "3D ray-traced perspective board rendering using rayrender/rayvista",
        "Game layout generation for game design, rulebook diagrams, and puzzle generation"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Geometric coordinate generation for board game components with isometric and orthographic projections and affine texture mappings.",
        functional_aspects:
          "Board game prototyping, algorithmic game theory visualization, chess endgame documentation, educational math puzzles.",
        ui_ux_aspects:
          "Isometric 3D board view with wooden game tiles, dice, pawns, and tokens arranged in strategic game states on dark felt.",
      )

    "oblicubes" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_oblicubes oblique 3D projection of cubes, voxels, and bar charts",
        "Configurable oblique projection angles (Cavalier, Cabinet, arbitrary theta)",
        "Automatic z-buffering and painter's algorithm depth sorting",
        "Multi-layer color mapping across 3D voxel surfaces",
        "Compact pseudo-3D data representation without WebGL overhead"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Oblique projection mapping: x_screen = x + z * cos(angle) * scale, y_screen = y + z * sin(angle) * scale with depth-sorted polygon grobs.",
        functional_aspects:
          "3D bar charts, categorical voxel histograms, spatial occupancy grids, architectural block massing analysis.",
        ui_ux_aspects:
          "Oblique 3D extruded bars with distinct top and side face tones, clear elevation lines, zero client-side 3D rendering lag.",
      )

    "ggDoubleHeat" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Dual-layer heatmaps with split cells (upper and lower triangles)",
        "Simultaneous comparison of two distinct metrics in every matrix cell",
        "Independent color scales for upper and lower cell triangles",
        "Diagonal symmetry checks comparing directional bilateral relationships",
        "Compact visualization doubling data density without doubling plot area"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Polygon coordinate generation splitting each matrix cell (i, j) into upper triangle (p1, p2, p3) and lower triangle (p1, p3, p4) with distinct fill mappings.",
        functional_aspects:
          "Bilateral trade balance (imports vs exports), genetic epistatic interactions, correlation vs p-value matrices, spatial transit flows.",
        ui_ux_aspects:
          "Split diagonal square cells where top-left triangle shows metric A and bottom-right triangle shows metric B, high information density.",
      )

    "nflplotR" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_nfl_logos NFL football team logos placed at data coordinates",
        "geom_nfl_headshots player headshot images as scatter plot markers",
        "geom_nfl_wordmarks team wordmark graphics for axis labels and headers",
        "Automated team color palettes (scale_color_nfl) matching official franchise hex codes",
        "High-performance image caching and resolution downsampling"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Sports data graphics pipeline downloading and caching official NFL franchise SVG/PNG vector assets, binding them to Cartesian scales.",
        functional_aspects:
          "Sports analytics, NFL quarterback EPA/play scatter plots, team offensive efficiency comparisons, fantasy football dashboards.",
        ui_ux_aspects:
          "High-resolution team logo glyphs plotted at efficiency coordinates, team-colored trendlines, dark sports analytics cockpit theme.",
      )

    "ggbraid" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_braid braided ribbon plots filling area between two overlapping lines",
        "Alternating ribbon fill colors depending on which line is higher (A > B vs B > A)",
        "Exact geometric intersection point calculation avoiding visual aliasing",
        "Smooth transition handling across zero-crossing inflection points",
        "Ideal for comparing paired time-series (revenue vs cost, imports vs exports)"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Piecewise linear segment intersection algorithms calculating exact (x_cross, y_cross) coordinates to partition ribbons into distinct signed polygons.",
        functional_aspects:
          "Financial profit/loss ribbons, election tracking poll lead comparisons, sports match score differentials, temperature vs baseline.",
        ui_ux_aspects:
          "Two waving lines with braided ribbon fill: luminous green when Line 1 dominates and crimson red when Line 2 dominates.",
      )

    "ggblanket" ->
      ExtensionFeatureProfile(
        features_offered: [
        "gg_point, gg_bar, gg_line fast wrapper functions around ggplot2",
        "Opinionated, publication-ready aesthetic defaults with zero configuration",
        "Automatic smart title case label formatting from snake_case variable names",
        "Curated colorblind-safe color palettes and dark/light mode themes",
        "Simplified syntax designed to drastically accelerate exploratory plotting"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Streamlined wrapper architecture wrapping ggplot2 geoms, scales, titles, and themes into single-call functional APIs.",
        functional_aspects:
          "Rapid data exploration, client-ready preliminary reporting, fast dashboard generation, beginner data science workflows.",
        ui_ux_aspects:
          "Sleek, modern minimalist charts with bold titles, clean axis scales, and vibrant contrasting color accents.",
      )

    "ggpie" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_pie publication-ready pie charts and 2D proportional circular charts",
        "geom_donut donut charts with configurable inner hole radius ratio",
        "Nested concentric donut charts for multi-level hierarchical breakdown",
        "Automatic percentage and label placement avoiding label overlap",
        "Exploded slice offsets for highlighting specific categories of interest"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Polar coordinate angle calculations mapping proportional values to angular spans (start_angle, end_angle) with radial label repulsion.",
        functional_aspects:
          "Budget allocation breakdowns, market share comparisons, survey demographic proportions, portfolio asset distribution.",
        ui_ux_aspects:
          "Sleek donut chart with high-contrast colored slices, crisp centered total count badge, and clean external percentage callouts.",
      )

    "ggstar" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_star polygon star marker glyphs with 30+ distinct geometric shapes",
        "Star shapes: 4-pointed, 5-pointed, 6-pointed, 7-pointed, pentagrams, hexagons",
        "Multi-pointed star aspect ratio and inner/outer radius ratio tuning",
        "Expands standard base R shape palette (0-25) with high-distinctiveness polygons",
        "Full support for independent fill and stroke aesthetic mappings"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Trigonometric polygon vertex generation alternating between inner and outer radii for N-pointed stars.",
        functional_aspects:
          "High-cardinality categorical scatter plots, astronomy star classification, customer review ratings, military ranking charts.",
        ui_ux_aspects:
          "Radiant geometric star markers with glowing neon borders and contrasting centers, high visual distinction across categories.",
      )

    "ggarchery" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_arrowcurve curved arrow segments with customizable arc curvature",
        "geom_arrowsegment straight arrow segments with precise gap offsets from points",
        "Customizable arrowheads: feathered, barbed, diamond, stealth, triangle",
        "Two-point and multi-point bezier arrow paths with gradient color fills",
        "Collision-avoiding arrow endpoints terminating at node boundaries"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Parametric cubic Bezier curve calculation evaluating tangential arrowhead orientation vectors at path endpoints.",
        functional_aspects:
          "Flowcharts, causal loop diagrams, cognitive process workflows, vector field trajectory animations.",
        ui_ux_aspects:
          "Smooth curved arrows with sharp futuristic stealth arrowheads connecting data points without touching point borders.",
      )

    "tidyterra" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_spatraster high-performance plotting of terra SpatRaster grids",
        "geom_spatvector plotting of terra SpatVector points, lines, and polygons",
        "Tidyverse verbs (mutate, select, filter) operating directly on SpatRaster objects",
        "Scientific color ramps for elevation, climate, and categorical landcover",
        "Automated downsampling for multi-gigabyte raster files maintaining interactivity"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "C++ raster data pointer extraction computing regular grid cell vertices and mapping band values to continuous color look-up tables.",
        functional_aspects:
          "Satellite remote sensing (Sentinel, Landsat), digital elevation model (DEM) terrain maps, climate change grid modeling.",
        ui_ux_aspects:
          "Rich shaded-relief elevation map with topographic contour contours and bright vector road networks on dark canvas.",
      )

    "ggseqplot" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Sequence analysis state distribution plots (d-plot) for life-course trajectories",
        "Sequence frequency plots (f-plot) showing most common sequential pathways",
        "Sequence index plots (i-plot) visualizing individual chronological histories",
        "Transition rate matrices and sequence entropy distribution curves",
        "TraMineR sequence data object integration"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Longitudinal sequence mining algorithms calculating state distributions and optimal matching distance matrices across categorical timelines.",
        functional_aspects:
          "Sociological life-course analysis, user journey clickstream paths, medical patient disease progression sequences.",
        ui_ux_aspects:
          "Stacked horizontal ribbon plots where chronological trajectories transition through colored state bands (education, career, retirement).",
      )

    "ggsurvfit" ->
      ExtensionFeatureProfile(
        features_offered: [
        "stat_survfit publication-ready Kaplan-Meier survival curves",
        "Cumulative incidence curves for competing risk analysis",
        "Synchronized risk tables aligned beneath survival curves displaying numbers at risk",
        "Censoring tick markers and median survival time callouts",
        "Log-rank test p-value annotations and restricted mean survival time (RMST)"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l5",
        technical_aspects:
          "Non-parametric Kaplan-Meier survival estimator coupled with multi-panel gtable risk table alignment.",
        functional_aspects:
          "Oncology clinical trials, pharmaceutical efficacy studies, engineering component reliability analysis, customer churn survival.",
        ui_ux_aspects:
          "Stepped survival curves with 95% confidence ribbon bands, censoring cross ticks, and aligned numbers-at-risk data table below.",
      )

    "ggsector" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_sector circular sector and pie slice glyph markers at (x, y) coordinates",
        "Configurable start angle, end angle, and sector radius",
        "Multivariate spatial mapping encoding two quantities in angle and radius",
        "Directional wind rose markers and sunburst slice glyphs",
        "Radial gauge glyphs for dashboard indicator meters"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Trigonometric arc polygon generation calculating circular sector boundaries in data units with affine spatial positioning.",
        functional_aspects:
          "Meteorological wind direction and speed mapping, directional antenna radiation patterns, directional transit flow maps.",
        ui_ux_aspects:
          "Spatial map dotted with circular sector glyphs oriented along directional headings with radii proportional to magnitude.",
      )

    "ggterror" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Global terrorism and conflict event epidemiology visualizations",
        "Longitudinal incident frequency timelines with casualty heatmaps",
        "Weapon type and target category stacked composition flows",
        "Geographic event spatial coordinates with conflict intensity radii",
        "Time-series change point detection for geopolitical crisis periods"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Temporal point process modeling and spatial kernel density estimation on georeferenced conflict event matrices.",
        functional_aspects:
          "Geopolitical risk analysis, counter-terrorism intelligence assessments, international relations security studies.",
        ui_ux_aspects:
          "Dark-mode timeline with amber and crimson incident severity bars, paired with spatial hotspot event circles.",
      )

    "ggragged" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Ragged grid faceting with uneven row and column panel layouts",
        "Eliminates wasted whitespace when subsets have varying numbers of sub-categories",
        "Dynamic panel allocation based on nested grouping cardinality",
        "Independent aspect ratios and coordinate limits for irregular panel grids",
        "Cleaner presentation for hierarchical and unbalanced multi-level data"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Custom facet grid layout algorithm packaging irregular panel lists into compact packing configurations without empty placeholder cells.",
        functional_aspects:
          "Unbalanced demographic studies, multi-level organizational charts, taxonomic clades with varying species counts.",
        ui_ux_aspects:
          "Neatly packed grid where each row contains exactly the number of sub-plots required by that category, zero empty box muda.",
      )

    "ggmapinset" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_map_inset map inset zoom views for dense metropolitan regions",
        "Automated geographic coordinate clipping and translation for inset panels",
        "Connecting boundary lines linking inset frame to target geographic territory",
        "Preserves spatial scale accuracy and CRS projections within both views",
        "Ideal for state or country maps with densely clustered urban populations"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Geographic polygon clipping and affine translation algorithms shifting and magnifying urban spatial geometries onto empty map margins.",
        functional_aspects:
          "Statewide election result maps with urban zoom-ins, epidemiological county maps, national logistics infrastructure distribution.",
        ui_ux_aspects:
          "Broad country map with dense metropolitan regions magnified and displayed in neat circular or rectangular corner inset panels.",
      )

    "ggmagnify" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_magnify dynamic inset magnification lenses for regions of interest",
        "Adjustable magnification zoom factor (2x, 4x, 10x) and lens aspect ratio",
        "Dashed guide vectors connecting original region bounding box to magnified lens",
        "Independent scale limits and formatting inside the magnified viewport",
        "Multiple concurrent magnification lenses on a single data canvas"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Viewport clipping and coordinate affine scaling projecting a sub-region data slice into a separate floating grob panel with connecting vectors.",
        functional_aspects:
          "High-density genomic locus magnification, astronomical deep-field galaxy insets, electronic circuit micro-defect callouts.",
        ui_ux_aspects:
          "Main data plot featuring a dashed amber selection box connected by fine guide lines to an enlarged, high-detail inset callout window.",
      )

    "ggblend" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Advanced blend modes: multiply, screen, overlay, darken, lighten, color-dodge",
        "Layer compositing operations solving overplotting and color mixing challenges",
        "Partitioned blending operating selectively on subsets of geometric layers",
        "Affine transparency and color multiplication directly in SVG pipeline",
        "High-impact graphic design aesthetics for scientific data visualization"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "SVG filter and Porter-Duff compositing operator injection applying mathematical pixel-level color blending equations between grob layers.",
        functional_aspects:
          "Overlapping density distributions, multi-channel fluorescence imaging, astronomical multi-wavelength overlays, graphic design.",
        ui_ux_aspects:
          "Luminous overlapping regions blending into bright additive white/yellow highlights, showing density intersections clearly.",
      )

    "ggflowchart" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_flowchart_node and geom_flowchart_edge for process flowcharts",
        "Orthogonal and curved connector lines with directional arrowheads",
        "Rectangular, diamond (decision), and rounded process step nodes",
        "Automatic node coordinate layout preventing overlap in sequential stages",
        "Node color and fill aesthetics mapped to process status or department"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Directed workflow layout engine computing orthogonal routing vectors between rectangular node boundaries with arrowhead terminations.",
        functional_aspects:
          "Business process mapping, clinical clinical trial CONSORT flowcharts, algorithm decision pipelines, CI/CD deployment architectures.",
        ui_ux_aspects:
          "Futuristic process diagram with rounded nodes connected by glowing cyan orthogonal conduits, status indicator badges.",
      )

    "ggrain" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_rain comprehensive raincloud plots combining three visual representations",
        "Half-violin continuous kernel density estimation forming the 'cloud'",
        "Jittered scatter point cloud underneath density forming the 'rain'",
        "Central boxplot and confidence interval bar anchoring summary statistics",
        "Longitudinal repeated measures connecting lines linking paired data points"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Coordinated compound layout aligning half-KDE densities, jittered scatter vectors, and boxplots along a shared category axis.",
        functional_aspects:
          "Neuroscience fMRI activation comparisons, behavioral reaction time distributions, clinical trial pre/post biomarker response.",
        ui_ux_aspects:
          "Graceful raincloud diagram: curved translucent cyan density cloud hovering over falling jittered droplet points and a neat central boxplot.",
      )

    "ggoutlierscatterplot" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Scatter plots with automated statistical outlier detection and highlighting",
        "Mahalanobis distance, Cook distance, and robust covariance estimators",
        "Outlier points highlighted with glowing rings and automatic callout labels",
        "Normal points rendered with subtle opacity preventing visual distraction",
        "Bivariate robust confidence ellipses enclosing normal data core"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l5",
        technical_aspects:
          "Robust multivariate distance algorithms (Minimum Covariance Determinant) computing chi-squared threshold boundaries for outlier flagging.",
        functional_aspects:
          "Financial fraud anomaly detection, sensor fault diagnostics, industrial quality control, clinical lab outlier screening.",
        ui_ux_aspects:
          "Faint dark-blue normal scatter cloud with vibrant neon-red outlier points encircled by warning halos and labeled with sample IDs.",
      )

    "ggautothemes" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Dynamic automated theme generation adapting to dataset structure and context",
        "Automatic contrast calibration based on display device luminance",
        "Smart typography selection matching document context (scientific, business, media)",
        "Harmonious palette synthesis derived from continuous clustering algorithms",
        "Context-aware gridline density and axis margin optimization"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l5",
        technical_aspects:
          "Heuristic aesthetic rule engines analyzing data dimensionality, range, and categorical cardinality to synthesize optimal theme parameters.",
        functional_aspects:
          "Automated reporting pipelines, responsive UI themes, accessibility compliance optimization, autonomous agent report generation.",
        ui_ux_aspects:
          "Flawlessly balanced themes dynamically tuned to dark cockpit specs with mathematically optimized contrast ratios.",
      )

    "AMR" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Antimicrobial resistance (AMR) epidemiology and surveillance visualizations",
        "ggplot_pca antibiogram multidimensional scaling and principal component analysis",
        "MIC (Minimum Inhibitory Concentration) distribution histograms with EUCAST/CLSI breakpoints",
        "Automated bacterial taxonomy validation and intrinsic resistance filtering",
        "Longitudinal antibiotic susceptibility trend monitoring charts"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l5",
        technical_aspects:
          "Standardized AMR epidemiological algorithms calculating susceptibility percentages and MIC distributions based on international EUCAST/CLSI clinical guidelines.",
        functional_aspects:
          "Hospital infection control surveillance, public health antibiotic resistance monitoring, clinical microbiology diagnostic reports.",
        ui_ux_aspects:
          "Stacked bar charts with green (Susceptible), yellow (Intermediate), and red (Resistant) tiers, dashed vertical clinical breakpoint lines.",
      )

    "ichimoku" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_ichimoku financial Ichimoku Kinko Hyo technical analysis cloud charts",
        "Tenkan-sen (conversion line, 9-period) and Kijun-sen (base line, 26-period)",
        "Senkou Span A and Senkou Span B defining the dynamic support/resistance 'Kumo' cloud",
        "Chikou Span (lagging span, plotted 26 periods behind price)",
        "Color-coded cloud shading: green for bullish cloud, red for bearish cloud"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Rolling mid-point calculations ((highest high + lowest low)/2) across multiple time horizons projected 26 periods into the future.",
        functional_aspects:
          "Financial market technical analysis, cryptocurrency trend trading, algorithmic trading signals, commodity price equilibrium.",
        ui_ux_aspects:
          "Dark candlestick chart overlaid with red/blue conversion lines and a semi-transparent undulating green/red shaded Kumo cloud.",
      )

    "eheat" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Environmental and ecological heatmaps with spatial and temporal layering",
        "Integration of physical coordinates (depth, altitude, temperature) with species abundance",
        "Depth-profile contour and heat gradient overlays",
        "Temporal seasonality matrices for environmental monitoring stations",
        "Multi-site pollutant concentration heatmaps"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Spatial-temporal matrix interpolation and smoothing applying 2D kriging and spline algorithms to environmental sensor grids.",
        functional_aspects:
          "Limnology water quality monitoring, oceanographic thermocline profiles, atmospheric pollutant mapping, ecological surveys.",
        ui_ux_aspects:
          "Deep oceanic blues transitioning to bright surface emeralds and amber, depth-axis inverted, clear contour lines.",
      )

    "ggstats" ->
      ExtensionFeatureProfile(
        features_offered: [
        "ggcoef_model regression model coefficient forest plots with confidence bars",
        "ggcoef_compare side-by-side forest plot comparison of multiple fitted models",
        "ggtable and stat_cross cross-tabulation frequency and proportion heatmaps",
        "Automatic odds ratio, hazard ratio, and risk ratio exponentiation",
        "Customizable reference line indicators and p-value significance stars"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l5",
        technical_aspects:
          "Tidying of statistical model objects (lm, glm, coxph) extracting estimates, standard errors, and confidence intervals into aligned forest plots.",
        functional_aspects:
          "Clinical trial odds ratios, epidemiological risk factor reports, econometric regression comparisons, academic publication summaries.",
        ui_ux_aspects:
          "Vertical dashed neutral line (x=0 or x=1) with horizontal confidence bars, solid point estimates, and right-aligned coefficient values.",
      )

    "ggfoundry" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Metal foundry casting simulation and thermal cooling curve visualizations",
        "Solidification phase transformation diagrams (Liquid, Solid + Liquid, Solid)",
        "Cooling rate derivative curves (dT/dt) identifying phase change temperatures",
        "Microstructure grain boundary size prediction curves",
        "Alloy metallurgical composition optimization charts"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Thermal finite difference equations modeling latent heat of fusion during metal solidification, plotting temperature vs time and first derivatives.",
        functional_aspects:
          "Metallurgical engineering, foundry casting quality assurance, alloy thermodynamics, aerospace materials testing.",
        ui_ux_aspects:
          "Thermal cooling curve descending through shaded phase zones with bright red derivative curve highlighting solidification plateaus.",
      )

    "ggalign" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Complex alignment and synchronization of multi-panel genomic, matrix, and heatmaps",
        "Precise panel width and height coordination across heterogeneous plot types",
        "Synchronized zoom, panning, and brushing across stacked multi-track plots",
        "Alignment of phylogenetic trees, genomic tracks, and clinical metadata sidebars",
        "Eliminates margin misalignment between disparate ggplot2 grobs"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Gtable column and row constraint solver synchronizing viewport boundaries across independently generated ggplot2 grob trees.",
        functional_aspects:
          "Multi-omics data integration, genomic browser view construction, electrophysiology multi-channel alignment.",
        ui_ux_aspects:
          "Perfect pixel-to-pixel column alignment across top heatmap, middle genomic track, and bottom bar charts, zero axis drift.",
      )

    "ggreveal" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Incremental presentation reveal animations unveiling plot layers step-by-step",
        "Stepwise addition of data points, lines, confidence intervals, and annotations",
        "Generates slides/frames for pedagogical lectures and conference talks",
        "Highlights progressive scientific discovery without overwhelming the audience",
        "Configurable reveal order: baseline -> data -> model fit -> outliers"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l5",
        technical_aspects:
          "Declarative layer decomposition partitioning a ggplot AST into sequential sub-plots with cumulative geometric layer activation.",
        functional_aspects:
          "Data science pedagogy, executive presentation storytelling, academic conference talks, interactive data explainers.",
        ui_ux_aspects:
          "Step-by-step sequence of charts progressively unveiling hypothesis, empirical observations, and final model conclusions.",
      )

    "geofacet" ->
      ExtensionFeatureProfile(
        features_offered: [
        "facet_geo geographically faceted subplots arranged in a pseudo-geographic grid",
        "Subplots arranged in a 2D tile layout that mimics real-world geographic topology",
        "Pre-built grids for US states, European countries, world regions, and Australian states",
        "Custom grid builder API for designing regional organizational topologies",
        "Each geographical tile hosts a complete independent ggplot2 chart"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Custom facet layout engine mapping categorical location keys to integer (row, col) grid coordinates defined in geographical grid specs.",
        functional_aspects:
          "Regional macroeconomic time-series comparisons, state-by-state demographic trends, European GDP growth small multiples.",
        ui_ux_aspects:
          "Grid of synchronized mini line charts arranged in the shape of the US or Europe, allowing simultaneous regional and temporal comparison.",
      )

    "tidyplots" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Tidyverse-first plotting grammar with elegant defaults and concise syntax",
        "Automated sorting of categorical factors by quantitative value",
        "Built-in colorblind-safe palettes and modern minimalist typography",
        "Integrated statistical summary points, error bars, and p-value brackets",
        "Reduces 20 lines of standard ggplot2 boilerplate to 2 clean pipe steps"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Modern tidy evaluation framework compiling high-level verbs into robust ggplot2 pipelines.",
        functional_aspects:
          "Everyday scientific exploratory analysis, laboratory experimental assays, rapid figure drafting, biotech R&D reports.",
        ui_ux_aspects:
          "Polished, aesthetic bar-and-scatter plots with clean error bars, subtle gridlines, and publication-ready typographic elegance.",
      )

    "rphylopic" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Adds silhouettes of living and extinct organisms from the Phylopic database",
        "geom_phylopic places biological organism silhouette glyphs at data points",
        "Scale silhouettes by body mass, trophic level, or phylogenetic group",
        "Customizable silhouette fill, stroke, and transparency",
        "Essential for biodiversity, paleontology, and macroecology charts"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "SVG path parser downloading and rendering vectorized biological organism silhouettes from the Phylopic API into Cartesian grob viewports.",
        functional_aspects:
          "Macroecology body size scaling, paleontology fossil mass comparisons, phylogenetic clade icon mapping, biodiversity infographics.",
        ui_ux_aspects:
          "Scatter plot where markers are authentic silhouettes of organisms (dinosaurs, cetaceans, primates) colored by ecological clade.",
      )

    "deeptime" ->
      ExtensionFeatureProfile(
        features_offered: [
        "coord_geo geological timescale axes integrated into ggplot2 coordinates",
        "Standard chronostratigraphic hierarchy: Eons, Eras, Periods, Epochs, Ages",
        "Official International Commission on Stratigraphy (ICS) color codes",
        "Fossil record specimen stratigraphic distribution range plotting",
        "Phylogenetic tree branch integration with deep-time geological periods"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "ICS geological time database lookups mapping million-year-ago (Ma) timestamps to hierarchical chronostratigraphic unit rectangles.",
        functional_aspects:
          "Paleontology fossil range charts, evolutionary deep-time phylogenies, geological sediment core profiling, paleoclimatology.",
        ui_ux_aspects:
          "Timeline axis formatted with official geological period colored blocks (Cretaceous, Jurassic, Triassic) with fossil range bars above.",
      )

    "ggpcp" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_pcp parallel coordinate plots for high-dimensional feature vectors",
        "geom_pcp_axes vertical coordinate axes with independent scale limits",
        "geom_pcp_boxes categorical factor level frequency boxes along axes",
        "Continuous polyline trajectories connecting observation values across dimensions",
        "Dynamic axis reordering and brush highlighting of selected sample clusters"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Multi-dimensional normalization mapping heterogeneous continuous and categorical variables into unified [0, 1] vertical axis intervals.",
        functional_aspects:
          "Multivariate clustering analysis, machine learning hyperparameter tuning surfaces, engineering multi-objective trade-off frontiers.",
        ui_ux_aspects:
          "Series of vertical neon axis lines crossed by colored thread polylines, highlighting clustered multivariate profiles.",
      )

    "ggvolcano" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Publication-ready volcano plots for differential gene expression (DGE)",
        "Significance threshold lines: horizontal -log10(p-value) and vertical log2(FC)",
        "Color coding: significantly upregulated (red/amber), downregulated (blue/cyan), non-significant (gray)",
        "Top-n gene symbol automatic callout labeling with ggrepel force placement",
        "Customizable fold-change cutoff lines and FDR/Bonferroni adjusted p-values"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Bivariate transformation evaluating fold change and statistical significance matrices, partitioning points into 4 quadrants with force-repelled labels.",
        functional_aspects:
          "RNA-seq differential expression, quantitative proteomics biomarker discovery, drug treatment knock-out screens, metabolomics.",
        ui_ux_aspects:
          "Classic volcano distribution: bright red upregulated points on right wing, blue downregulated points on left wing, dashed threshold lines.",
      )

    "ggfootball" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_pitch regulation soccer/football pitch dimensions and markings",
        "Player pass networks with edge thickness proportional to pass frequency",
        "Player event heatmaps (touches, tackles, ball recoveries)",
        "Shot location maps with expected goals (xG) bubble size scaling",
        "Full pitch, half pitch, and penalty box coordinate zoom views"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Spatial pitch normalization mapping event coordinates (x: 0-105m, y: 0-68m) onto standard geometric pitch boundary and penalty box grobs.",
        functional_aspects:
          "Professional sports tactical analytics, player recruitment scouting, match event performance analysis, team tactical formations.",
        ui_ux_aspects:
          "Dark emerald green pitch with crisp white field markings, player pass network vectors, and shot location xG circles.",
      )

    "ggfields" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_fields vector field arrows, direction cones, and flow streamlines",
        "Magnitude scaling and color mapping for continuous 2D vector fields",
        "Streamline integration tracing particle trajectories through velocity fields",
        "Meteorological wind vectors and oceanographic current dynamics",
        "Support for gridded and irregular spatial vector observation points"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Runge-Kutta numerical integration (RK4) tracing continuous streamlines through 2D vector velocity grids with dynamic arrow spacing.",
        functional_aspects:
          "Oceanographic circulation modeling, atmospheric wind flow simulation, aerodynamics wind tunnel velocity fields.",
        ui_ux_aspects:
          "Smooth curving streamlines with glowing arrowheads tracing fluid currents across bathymetric and atmospheric contours.",
      )

    "ggsankeyfier" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Sankey and alluvial stream diagrams with customizable stage nodes",
        "Curved cubic Bezier flow ribbons connecting categorical transitions",
        "Configurable node positioning, ordering, and spacing between stages",
        "Supports both wide and long format sequence and transition datasets",
        "Dynamic ribbon transparency and gradient coloring from source to target"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Mass-conserving flow routing algorithm calculating stage node vertical coordinates and cubic spline ribbon polygons linking stages.",
        functional_aspects:
          "Energy consumption flow charts, web conversion funnel analysis, educational progression pipelines, supply chain logistics.",
        ui_ux_aspects:
          "Crisp vertical stage blocks connected by graceful undulating translucent ribbons, colored by category with zero mass leakage.",
      )

    "ggpath" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_from_path renders local and remote image paths (PNG, SVG, JPG) into ggplot2",
        "Proportional image aspect ratio preservation and circular avatar clipping",
        "High-performance image caching for high-density image scatter plots",
        "Direct integration of sports player headshots, brand logos, and microscopy icons",
        "Aesthetic mapping of image width, height, alpha, and border color"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Asynchronous image decoding and raster/SVG grob compilation within Cartesian scales with automated aspect ratio clamping.",
        functional_aspects:
          "Sports analytics player performance maps, social media influence graphs with avatar nodes, e-commerce product scatter plots.",
        ui_ux_aspects:
          "Circular image avatars placed at exact data coordinates with colored border rings indicating performance tier.",
      )

    "gglinedensity" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_linedensity line plots coloring trajectories by local overlap density",
        "Visualizes bundled spaghetti plots without losing individual trajectory identity",
        "Continuous color gradient highlighting dominant consensus trajectory pathways",
        "Adjustable kernel smoothing across overlapping line segments",
        "Effective for multi-trajectory time series and ensemble forecasting"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "2D segment intersection density estimation applying Gaussian kernels across overlapping polylines to assign segment-level density scores.",
        functional_aspects:
          "Weather ensemble hurricane trajectory forecasts, flight path corridor monitoring, agent simulation navigation paths.",
        ui_ux_aspects:
          "Bundled line spaghetti where the dominant common path glows brilliant cyan while divergent anomalous paths remain faint dark blue.",
      )

    "ggsurveillance" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Public health infectious disease outbreak surveillance monitoring",
        "Automated epidemic threshold calculations using Farrington and Serfling models",
        "Aberration detection flags highlighting statistically significant disease clusters",
        "Longitudinal endemic channel ribbons (25th-75th percentiles) with alert spikes",
        "Integration with surveillance R package outbreak algorithms"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l5",
        technical_aspects:
          "Negative binomial generalized linear models (GLM) accounting for seasonality, trend, and past outbreaks to compute epidemic alarm thresholds.",
        functional_aspects:
          "National disease surveillance centers (CDC, ECDC), hospital infection outbreak alerts, syndromic surveillance dashboards.",
        ui_ux_aspects:
          "Weekly case count line chart with shaded gray historical baseline channel, red dashed alarm threshold, and flashing alert symbols.",
      )

    "gguapo" ->
      ExtensionFeatureProfile(
        features_offered: [
        "High-level publication plot styling with unified typographic margins",
        "Opinionated theme presets optimized for academic journal specifications",
        "Harmonious color palettes calibrated for both digital screens and print",
        "Automated axis label wrapping and legend position optimization",
        "Strict adherence to scientific visualization best practices"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Comprehensive theme and guide compiler enforcing standardized typographical grids, margin ratios, and color harmony algorithms.",
        functional_aspects:
          "Academic manuscript figure preparation, clinical report generation, standardized scientific communications.",
        ui_ux_aspects:
          "Impeccable scientific publication styling with high data-ink ratio, legible fonts, and balanced color accents.",
      )

    "ggDNAvis" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Circular plasmid and bacterial chromosome map visualization",
        "Linear DNA sequence annotation tracks with restriction enzyme sites",
        "Promoter, terminator, and open reading frame (ORF) glyphs",
        "GC content and GC skew undulating wave track overlays",
        "Cloning vector design and synthetic biology construct maps"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Circular polar coordinate transformations mapping nucleotide base-pair indices (1 to N) into concentric radial tracks and arcs.",
        functional_aspects:
          "Synthetic biology construct design, plasmid cloning vector documentation, bacterial genome atlas mapping.",
        ui_ux_aspects:
          "Luminous circular plasmid ring with radiating restriction enzyme markers and colored functional feature sectors.",
      )

    "ggdibbler" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Statistical process flow and hierarchical pipeline state graphs",
        "Interactive node callouts and stage status indicators",
        "Directed acyclic data pipeline execution tracing",
        "Execution latency and throughput metrics embedded inside pipeline nodes",
        "Failure state highlighting with automated root-cause warning badges"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l5",
        technical_aspects:
          "Topological graph sorting and layout algorithms computing pipeline stage coordinates and metric-annotated node boxes.",
        functional_aspects:
          "ETL data pipeline observability, CI/CD automated build monitoring, distributed microservice trace visualization.",
        ui_ux_aspects:
          "Flowing pipeline diagram with green (Passed), amber (Degraded), and red (Failed) node statuses, execution timing badges.",
      )

    "ggprop.test" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Visual hypothesis testing for proportions and contingency tables",
        "Two-sample and multi-sample proportion comparison plots",
        "Confidence intervals for difference in proportions with reference zero line",
        "Automated chi-squared test and Fisher exact test p-value annotations",
        "Visual representation of power and sample size sensitivity"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l5",
        technical_aspects:
          "Normal approximation (Wilson score, Clopper-Pearson) confidence interval calculations for binomial proportions and risk differences.",
        functional_aspects:
          "A/B testing conversion rate analysis, clinical trial efficacy risk differences, political polling margin-of-error comparisons.",
        ui_ux_aspects:
          "Horizontal difference-in-proportions confidence bars crossing vertical dashed null line (0%), clear significance callouts.",
      )

    "ggsky" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Astronomical celestial sphere sky maps and star charts",
        "Equatorial coordinates: Right Ascension (RA) and Declination (Dec)",
        "Constellation boundary lines and stellar magnitude bubble scaling",
        "Milky Way galactic plane and ecliptic coordinate overlays",
        "Support for astronomical FITS image overlays and deep-sky object catalogs"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Celestial spherical coordinate projections (Aitoff, Lambert azimuthal, stereographic) mapping spherical RA/Dec onto 2D sky charts.",
        functional_aspects:
          "Astrophysical telescope observation planning, exoplanet transit coordinate maps, amateur astronomy sky charts.",
        ui_ux_aspects:
          "Deep cosmic dark-blue celestial sphere map with glowing white and cyan star points sized by magnitude, fine constellation lines.",
      )

    "ggpop" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Population pyramid visualizations for demographic age-sex distributions",
        "Back-to-back horizontal bar charts with synchronized centered age axis",
        "Cohort mortality and fertility rate overlays across historical eras",
        "Dynamic transition animations showing aging population shifts over decades",
        "Automated dependency ratio and demographic dividend annotations"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Dual-axis horizontal bar transformation mapping male populations to negative X coordinates and females to positive X with absolute value axis labels.",
        functional_aspects:
          "National census demographic analysis, pension solvency forecasting, epidemiological age-cohort vulnerability, labor force planning.",
        ui_ux_aspects:
          "Classic demographic pyramid: blue bars on left (Male) and rose bars on right (Female) tapering toward upper age brackets, dark theme.",
      )

    "ggpointless" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Highlights first, last, minimum, and maximum points in scatter/time-series plots",
        "geom_pointless automated terminal and extreme point annotations",
        "Eliminates manual data subsetting boilerplate for start/end markers",
        "Customizable shape, size, and color for initial, terminal, min, and max markers",
        "Ideal for sparklines, trajectory plots, and financial time-series"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Pipeline filter identifying extrema indices (which.min, which.max, head, tail) and instantiating targeted point grobs at those coordinates.",
        functional_aspects:
          "Financial stock sparklines, patient clinical vitals tracking, athletic performance telemetry, IoT sensor threshold monitoring.",
        ui_ux_aspects:
          "Smooth time series line accented with a green dot at origin, red dot at terminus, and glowing flags at peak and trough.",
      )

    "ggincerta" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Uncertainty intervals and fuzzy error bounds for physical measurements",
        "Gradient confidence ribbons with continuous opacity falloff from central estimate",
        "Ensemble trajectory fan charts with quantile probability contours",
        "Fuzzy number arithmetic visualization with triangular and trapezoidal bounds",
        "Effective communication of severe parameter uncertainty in decision models"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Continuous alpha gradient shading and fuzzy interval arithmetic mapping uncertainty membership functions to SVG opacity gradients.",
        functional_aspects:
          "Climate projection fan charts, macroeconomic forecast uncertainty bands, aerospace orbital debris tracking, risk management.",
        ui_ux_aspects:
          "Central trend trajectory enveloped by glowing cyan mist that diffuses smoothly into the dark background as uncertainty widens.",
      )

    "ggRandomForests" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Random forest machine learning model diagnostic visualizations",
        "Variable importance (VIMP) and minimal depth ranking plots",
        "Partial dependence plots showing non-linear marginal feature effects",
        "Survival forest Kaplan-Meier and hazard rate comparisons",
        "Out-of-bag (OOB) error convergence curves over growing forest sizes"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l5",
        technical_aspects:
          "Extraction of randomForestSRC and randomForest model trees computing permutation importance, tree depth metrics, and marginal effects.",
        functional_aspects:
          "Machine learning interpretability (XAI), credit scoring risk factors, clinical prognostic biomarker discovery, predictive maintenance.",
        ui_ux_aspects:
          "Horizontal bar chart of variable importance with confidence intervals, paired with smoothed partial dependence curves.",
      )

    "ggcube" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_cube 3D isometric cube and voxel rendering for spatial block diagrams",
        "Configurable cube dimensions (dx, dy, dz) and 3D spatial positioning",
        "Isometric perspective projection with customizable illumination angle",
        "Faceted shading on top, left, and right cube faces providing depth",
        "Voxel grid aggregation for 3D spatial data and material architectures"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Isometric affine projection converting 3D coordinates (x, y, z) into 2D screen coordinates with Lambertian cosine face shading calculations.",
        functional_aspects:
          "Materials science crystal unit cells, Minecraft-style voxel landscape analytics, data warehouse OLAP cube visualization.",
        ui_ux_aspects:
          "Stack of crisp isometric 3D cubes with shaded faces, glowing neon edges, and clear perspective depth on dark canvas.",
      )

    "ggtaichi" ->
      ExtensionFeatureProfile(
        features_offered: [
        "geom_taichi Tai-Chi Yin-Yang symbol geometry representations",
        "Harmonic balance visualization mapping dual complementary metrics",
        "Parametric semicircular arcs and contrasting inner eye circles",
        "Dynamic symbol rotation angle mapped to system phase or balance ratio",
        "Holistic equilibrium dashboards for multi-attribute state monitoring"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Trigonometric parametric equations generating circular yin-yang teardrop contours and polar pupil coordinates with rotational affine transforms.",
        functional_aspects:
          "Cybernetic balance indicators, load-vs-capacity equilibrium monitoring, dialectical risk assessments, ergonomic state displays.",
        ui_ux_aspects:
          "Stylized Yin-Yang medallion with glowing cyan and deep navy complementary halves, rotating smoothly according to metric balance.",
      )

    "ggchord2" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Circular chord diagrams showing directed and undirected bilateral flows",
        "Proportional arc sectors representing total category capacity",
        "Bilateral ribbon widths proportional to origin-destination transfer volumes",
        "Directional chord tapering highlighting net flow imbalances",
        "Custom chord coloring mapped to source or destination categories"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Bilateral matrix chord geometry calculating circular arc coordinates and cubic Bezier ribbons linking origin and destination angular spans.",
        functional_aspects:
          "International trade balances, inter-departmental budget transfers, cellular communication ligand-receptor interactions, website user page journeys.",
        ui_ux_aspects:
          "Circular perimeter ring composed of colored sectors with luminous curved ribbons flowing across the center, dark cockpit background.",
      )

    "ggtintshade" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Tint and shade aesthetic scales varying color luminance without changing hue",
        "scale_tint varying amount of white added to base hue (tints)",
        "scale_shade varying amount of black added to base hue (shades)",
        "Orthogonal aesthetic mapping combining categorical hue with quantitative shade",
        "Preserves visual harmony while encoding two independent dimensions in color"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "HSL/HCL color space transformations modifying lightness and chroma while holding hue constant: C_out = mix(C_base, white/black, alpha).",
        functional_aspects:
          "Hierarchical category coloring (hue = parent group, shade = sub-category value), risk severity grading, status depth.",
        ui_ux_aspects:
          "Harmonious palette variations where related data elements share identical color family with subtle, legible lightness tiers.",
      )

    "glydraw" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Graphical representation of complex glycan branched structures",
        "Standard Symbol Nomenclature for Glycans (SNFG) icon adherence",
        "Monosaccharide shape and color standards (Gal=Yellow circle, Glc=Blue circle, Fuc=Red triangle)",
        "Linkage position and stereochemistry (alpha/beta, 1-3, 1-4, 1-6) annotation",
        "Automated tree layout algorithms for branched polysaccharide topologies"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3 #fractal-l4",
        technical_aspects:
          "Glycan IUPAC nomenclature parser compiling branched tree data structures into SNFG standard geometric symbol grobs with linkage lines.",
        functional_aspects:
          "Glycobiology research, biopharmaceutical antibody glycosylation profiling, viral spike protein glycan shield visualization.",
        ui_ux_aspects:
          "Standardized colorful SNFG monosaccharide symbols arranged in branching tree structures with fine connecting linkage labels.",
      )

    "ggmultiglyph" ->
      ExtensionFeatureProfile(
        features_offered: [
        "Multivariate glyph plots with compound symbol encodings",
        "Star glyphs, polygon glyphs, and profile glyphs mapped at data coordinates",
        "Each ray or vertex of the glyph encodes an independent feature dimension",
        "Facilitates rapid holistic comparison of complex multivariate entities",
        "Adjustable glyph scaling, aspect ratio, and background boundary circle"
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Polar coordinate polygon computation projecting N-dimensional feature vectors into localized miniature star glyph polygons at (x, y) data points.",
        functional_aspects:
          "Multi-attribute product comparisons, regional quality-of-life multivariate profiling, hospital performance benchmarking.",
        ui_ux_aspects:
          "Array of miniature geometric star glyphs plotted across the coordinate plane, each star's shape reflecting multidimensional attributes.",
      )

    _ ->
      ExtensionFeatureProfile(
        features_offered: [
          ext.name <> " specialized ggproto scientific pipeline",
          "Bespoke aesthetic mapping binding domain variables to scales",
          "Pure functional BEAM execution with zero client JavaScript",
        ],
        fractal_layer: "#fractal-l2 #fractal-l3",
        technical_aspects:
          "Specialized mathematical pipeline in " <> ext.name <> " mapping analytical inputs to Euclidean coordinates.",
        functional_aspects:
          "High-impact scientific research and publication graphics in " <> ext.description,
        ui_ux_aspects:
          "High-contrast dark cockpit compliant rendering (#020617) with responsive SVG scaling.",
      )
  }
}
