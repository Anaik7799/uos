@sciviz @features-offered #fractal-l2 #fractal-l3 #fractal-l4
Feature: SciViz All 167 Registered Extensions Primary Features Offered
  As a SciViz Visual Analytics Engineer
  I want each extension to declare its exact features offered and fractal coordinates
  So that capabilities are formally observable across the C3I mesh

  Background:
    Given I am on the page "http://127.0.0.1:4100/sciviz/extensions"

  Scenario Outline: SciViz Extension <name> Core Feature Offered Verification
    Then the sciviz card for "<name>" should offer feature "<primary_feature>"
    And the sciviz card for "<name>" should carry fractal layer "<fractal_layer>"

    Examples:
      | name | primary_feature | fractal_layer |
      | ggram | Multi-panel plot assembly and mathematical composition | #fractal-l2 #fractal-l4 |
      | ggQQunif | Statistical distribution parameter visualization | #fractal-l2 #fractal-l3 |
      | ggupset | Combination matrix axis for set intersections | #fractal-l2 #fractal-l3 #fractal-l4 |
      | xmrr | Statistical Process Control (SPC) Shewhart charts | #fractal-l2 #fractal-l3 #fractal-l5 |
      | gg3D | 3D perspective and isometric projections | #fractal-l2 #fractal-l3 |
      | ggQC | Statistical Process Control (SPC) Shewhart charts | #fractal-l2 #fractal-l3 #fractal-l5 |
      | ggdist | Slab-interval geoms (half-eye, violin, continuous probability gradients) | #fractal-l2 #fractal-l3 #fractal-l4 |
      | ggedit | Interactive and programmatic layer inspection | #fractal-l3 #fractal-l5 |
      | ggpage | Non-overlapping text label placement algorithms | #fractal-l2 #fractal-l3 |
      | ggpca | PCA biplots and eigenvector loadings | #fractal-l2 #fractal-l3 |
      | ggbreak | Discontinuous axis scale breaks (scale_x_break, scale_y_break) | #fractal-l2 #fractal-l3 |
      | ggimg | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | gganatogram | Genomic sequence and variant locus visualization | #fractal-l2 #fractal-l3 #fractal-l6 |
      | ggforce | Delaunay triangulation and Voronoi tessellation | #fractal-l2 #fractal-l3 |
      | ggalt | Real-time statistical hypothesis testing annotations | #fractal-l2 #fractal-l3 #fractal-l5 |
      | ggiraph | Interactive and programmatic layer inspection | #fractal-l3 #fractal-l5 |
      | ggmuller | Multi-stage categorical flow tracking | #fractal-l3 #fractal-l4 |
      | ggstance | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | ggrepel | Force-directed non-overlapping text and label placement | #fractal-l2 #fractal-l3 |
      | ggraph | Node-link graphs with layout engines (stress, circular, bipartite, dendrogram) | #fractal-l2 #fractal-l3 #fractal-l6 |
      | gginnards | AST inspection and editing of ggproto plot layers | #fractal-l3 #fractal-l5 |
      | ggpp | Statistical distribution parameter visualization | #fractal-l2 #fractal-l3 |
      | ggpmisc | Statistical distribution parameter visualization | #fractal-l2 #fractal-l3 |
      | geomnet | Graph node and edge layout algorithms | #fractal-l2 #fractal-l3 #fractal-l6 |
      | ggExtra | Statistical distribution parameter visualization | #fractal-l2 #fractal-l3 |
      | ggfortify | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | autoplotly | Interactive and programmatic layer inspection | #fractal-l3 #fractal-l5 |
      | gganimate | Grammar of animated graphics transitions (transition_time, transition_states) | #fractal-l3 #fractal-l4 |
      | ggfx | Shader-based image filters for ggplot2 layers | #fractal-l2 #fractal-l4 |
      | plotROC | Interactive and publication-quality ROC curves | #fractal-l2 #fractal-l3 |
      | ggbump | Smooth bump charts for ranking over time | #fractal-l2 #fractal-l3 |
      | ggthemes | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | ggspectra | Statistical distribution parameter visualization | #fractal-l2 #fractal-l3 |
      | ggstatsplot | Statistical inference hypothesis testing embedded in visualizations | #fractal-l2 #fractal-l3 #fractal-l5 |
      | ggnetwork | Graph node and edge layout algorithms | #fractal-l2 #fractal-l3 #fractal-l6 |
      | ggtech | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | ggradar | Spider and radar charts with polar spokes | #fractal-l2 #fractal-l3 |
      | ggx | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | ggTimeSeries | Statistical Process Control (SPC) Shewhart charts | #fractal-l2 #fractal-l3 #fractal-l5 |
      | ggtree | Phylogenetic cladogram and phylogram visualization | #fractal-l2 #fractal-l3 #fractal-l6 |
      | ggseas | Statistical Process Control (SPC) Shewhart charts | #fractal-l2 #fractal-l3 #fractal-l5 |
      | ggsci | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | ggmosaic | Mosaic plots for multi-way contingency tables | #fractal-l2 #fractal-l3 |
      | survminer | Kaplan-Meier survival probability step curves | #fractal-l2 #fractal-l3 |
      | ggeasy | Interactive and programmatic layer inspection | #fractal-l3 #fractal-l5 |
      | ggside | Multi-panel plot assembly and mathematical composition | #fractal-l2 #fractal-l4 |
      | ggcorrplot | Correlation matrix heatmaps with coefficient labels | #fractal-l2 #fractal-l3 |
      | ggpubr | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | ggthemr | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | GGally | PCA biplots and eigenvector loadings | #fractal-l2 #fractal-l3 |
      | ggseqlogo | Genomic sequence and variant locus visualization | #fractal-l2 #fractal-l3 #fractal-l6 |
      | ggChernoff | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | ggridges | Partially overlapping density ridgelines across ordered strata | #fractal-l2 #fractal-l3 |
      | lemon | Non-Cartesian coordinate system transformations | #fractal-l2 #fractal-l3 |
      | cowplot | Publication-ready figure grid composition | #fractal-l2 #fractal-l4 |
      | qqplotr | Statistical distribution parameter visualization | #fractal-l2 #fractal-l3 |
      | ggalluvial | Multi-stratum alluvial flow diagrams and Sankey stream tracking | #fractal-l3 #fractal-l4 |
      | patchwork | Mathematical plot composition operators (+, / | #fractal-l2 #fractal-l4 |
      | ggquiver | Vector field direction and magnitude glyphs | #fractal-l2 #fractal-l3 |
      | ggsignif | Real-time statistical hypothesis testing annotations | #fractal-l2 #fractal-l3 #fractal-l5 |
      | ggdag | Graph node and edge layout algorithms | #fractal-l2 #fractal-l3 #fractal-l6 |
      | ggformula | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | ggbeeswarm | Columnar categorical beeswarm point layouts | #fractal-l2 #fractal-l3 |
      | ggperiodic | Non-Cartesian coordinate system transformations | #fractal-l2 #fractal-l3 |
      | ggpol | Hierarchical nested partition layouts | #fractal-l2 #fractal-l3 |
      | ggpirate | Statistical distribution parameter visualization | #fractal-l2 #fractal-l3 |
      | esquisse | Interactive and programmatic layer inspection | #fractal-l3 #fractal-l5 |
      | ggerror | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | ggdark | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | sugrrants | Statistical Process Control (SPC) Shewhart charts | #fractal-l2 #fractal-l3 #fractal-l5 |
      | tvthemes | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | ggfittext | Non-overlapping text label placement algorithms | #fractal-l2 #fractal-l3 |
      | ggparty | Genomic sequence and variant locus visualization | #fractal-l2 #fractal-l3 #fractal-l6 |
      | gggenes | Genomic sequence and variant locus visualization | #fractal-l2 #fractal-l3 #fractal-l6 |
      | gggenomes | Genomic sequence and variant locus visualization | #fractal-l2 #fractal-l3 #fractal-l6 |
      | treemapify | Squarified treemap hierarchical layouts | #fractal-l2 #fractal-l3 |
      | lindia | Real-time statistical hypothesis testing annotations | #fractal-l2 #fractal-l3 #fractal-l5 |
      | gghalves | Half-half hybrid geoms (geom_half_violin, geom_half_point) | #fractal-l2 #fractal-l3 |
      | ggrastr | Pattern fills (stripes, dots, crosshatch) for accessibility | #fractal-l2 #fractal-l4 |
      | ggpointdensity | Statistical distribution parameter visualization | #fractal-l2 #fractal-l3 |
      | ggsom | PCA biplots and eigenvector loadings | #fractal-l2 #fractal-l3 |
      | ggnewscale | Multiple color and fill scales on a single ggplot | #fractal-l2 #fractal-l3 |
      | ggh4x | Non-Cartesian coordinate system transformations | #fractal-l2 #fractal-l3 |
      | ggarrow | Vector field direction and magnitude glyphs | #fractal-l2 #fractal-l3 |
      | legendry | Non-Cartesian coordinate system transformations | #fractal-l2 #fractal-l3 |
      | ggcharts | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | humapr | Genomic sequence and variant locus visualization | #fractal-l2 #fractal-l3 #fractal-l6 |
      | ggshadow | Pattern fills (stripes, dots, crosshatch) for accessibility | #fractal-l2 #fractal-l4 |
      | ggseg | Genomic sequence and variant locus visualization | #fractal-l2 #fractal-l3 #fractal-l6 |
      | mdthemes | Non-overlapping text label placement algorithms | #fractal-l2 #fractal-l3 |
      | ggwordcloud | Non-overlapping text label placement algorithms | #fractal-l2 #fractal-l3 |
      | ggasym | Non-Cartesian coordinate system transformations | #fractal-l2 #fractal-l3 |
      | gglorenz | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | hrbrthemes | Non-overlapping text label placement algorithms | #fractal-l2 #fractal-l3 |
      | ggpattern | Pattern fills (stripes, dots, crosshatch) for accessibility | #fractal-l2 #fractal-l4 |
      | ggtext | Non-overlapping text label placement algorithms | #fractal-l2 #fractal-l3 |
      | calendR | Statistical Process Control (SPC) Shewhart charts | #fractal-l2 #fractal-l3 #fractal-l5 |
      | ggip | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | gglm | Real-time statistical hypothesis testing annotations | #fractal-l2 #fractal-l3 #fractal-l5 |
      | econocharts | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | ComplexUpset | Hierarchical nested partition layouts | #fractal-l2 #fractal-l3 |
      | ggchromatic | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | ggheatmap | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | see | Statistical distribution parameter visualization | #fractal-l2 #fractal-l3 |
      | directlabels | Non-overlapping text label placement algorithms | #fractal-l2 #fractal-l3 |
      | ggHoriPlot | Statistical Process Control (SPC) Shewhart charts | #fractal-l2 #fractal-l3 #fractal-l5 |
      | ggtrace | Interactive and programmatic layer inspection | #fractal-l3 #fractal-l5 |
      | ggESDA | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | geomtextpath | Text flowing along arbitrary geometric paths and splines | #fractal-l2 #fractal-l3 |
      | ggdensity | Statistical distribution parameter visualization | #fractal-l2 #fractal-l3 |
      | ggtranscript | Genomic sequence and variant locus visualization | #fractal-l2 #fractal-l3 #fractal-l6 |
      | piecepackr | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | oblicubes | 3D perspective and isometric projections | #fractal-l2 #fractal-l3 |
      | ggDoubleHeat | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | nflplotR | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | ggbraid | Multi-stage categorical flow tracking | #fractal-l3 #fractal-l4 |
      | ggblanket | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | ggpie | Hierarchical nested partition layouts | #fractal-l2 #fractal-l3 |
      | ggstar | Interactive and programmatic layer inspection | #fractal-l3 #fractal-l5 |
      | ggarchery | Vector field direction and magnitude glyphs | #fractal-l2 #fractal-l3 |
      | tidyterra | Vector field direction and magnitude glyphs | #fractal-l2 #fractal-l3 |
      | ggseqplot | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | ggsurvfit | Genomic sequence and variant locus visualization | #fractal-l2 #fractal-l3 #fractal-l6 |
      | ggsector | Vector field direction and magnitude glyphs | #fractal-l2 #fractal-l3 |
      | ggterror | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | ggragged | Multi-panel plot assembly and mathematical composition | #fractal-l2 #fractal-l4 |
      | ggmapinset | Vector field direction and magnitude glyphs | #fractal-l2 #fractal-l3 |
      | ggmagnify | Non-Cartesian coordinate system transformations | #fractal-l2 #fractal-l3 |
      | ggblend | Pattern fills (stripes, dots, crosshatch) for accessibility | #fractal-l2 #fractal-l4 |
      | ggflowchart | Graph node and edge layout algorithms | #fractal-l2 #fractal-l3 #fractal-l6 |
      | ggrain | Statistical distribution parameter visualization | #fractal-l2 #fractal-l3 |
      | ggoutlierscatterplot | Real-time statistical hypothesis testing annotations | #fractal-l2 #fractal-l3 #fractal-l5 |
      | ggautothemes | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | AMR | Genomic sequence and variant locus visualization | #fractal-l2 #fractal-l3 #fractal-l6 |
      | ichimoku | Statistical Process Control (SPC) Shewhart charts | #fractal-l2 #fractal-l3 #fractal-l5 |
      | eheat | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | ggstats | Real-time statistical hypothesis testing annotations | #fractal-l2 #fractal-l3 #fractal-l5 |
      | ggfoundry | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | ggalign | Non-Cartesian coordinate system transformations | #fractal-l2 #fractal-l3 |
      | ggreveal | Interactive and programmatic layer inspection | #fractal-l3 #fractal-l5 |
      | geofacet | Vector field direction and magnitude glyphs | #fractal-l2 #fractal-l3 |
      | tidyplots | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | rphylopic | Genomic sequence and variant locus visualization | #fractal-l2 #fractal-l3 #fractal-l6 |
      | deeptime | Statistical Process Control (SPC) Shewhart charts | #fractal-l2 #fractal-l3 #fractal-l5 |
      | ggpcp | PCA biplots and eigenvector loadings | #fractal-l2 #fractal-l3 |
      | ggvolcano | Genomic sequence and variant locus visualization | #fractal-l2 #fractal-l3 #fractal-l6 |
      | ggfootball | Real-time statistical hypothesis testing annotations | #fractal-l2 #fractal-l3 #fractal-l5 |
      | ggfields | Vector field direction and magnitude glyphs | #fractal-l2 #fractal-l3 |
      | ggsankeyfier | Graph node and edge layout algorithms | #fractal-l2 #fractal-l3 #fractal-l6 |
      | ggpath | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | gglinedensity | Statistical distribution parameter visualization | #fractal-l2 #fractal-l3 |
      | ggsurveillance | Statistical Process Control (SPC) Shewhart charts | #fractal-l2 #fractal-l3 #fractal-l5 |
      | gguapo | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | ggDNAvis | Genomic sequence and variant locus visualization | #fractal-l2 #fractal-l3 #fractal-l6 |
      | ggdibbler | Statistical distribution parameter visualization | #fractal-l2 #fractal-l3 |
      | ggprop.test | Real-time statistical hypothesis testing annotations | #fractal-l2 #fractal-l3 #fractal-l5 |
      | ggsky | Vector field direction and magnitude glyphs | #fractal-l2 #fractal-l3 |
      | ggpop | Hierarchical nested partition layouts | #fractal-l2 #fractal-l3 |
      | ggpointless | Real-time statistical hypothesis testing annotations | #fractal-l2 #fractal-l3 #fractal-l5 |
      | ggincerta | Statistical distribution parameter visualization | #fractal-l2 #fractal-l3 |
      | ggRandomForests | Genomic sequence and variant locus visualization | #fractal-l2 #fractal-l3 #fractal-l6 |
      | ggcube | 3D perspective and isometric projections | #fractal-l2 #fractal-l3 |
      | ggtaichi | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
      | ggchord2 | Graph node and edge layout algorithms | #fractal-l2 #fractal-l3 #fractal-l6 |
      | ggtintshade | Pattern fills (stripes, dots, crosshatch) for accessibility | #fractal-l2 #fractal-l4 |
      | glydraw | Non-overlapping text label placement algorithms | #fractal-l2 #fractal-l3 |
      | ggmultiglyph | Scientifically calibrated perceptually uniform color palettes | #fractal-l2 #fractal-l4 |
