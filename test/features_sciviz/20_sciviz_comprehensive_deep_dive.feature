@sciviz @comprehensive-deep-dive @ggram #fractal-l2 #fractal-l3 #fractal-l4
Feature: SciViz 167 Extensions Comprehensive Aspect Explorer and ggram Deep Dive
  As a Scientific Visualization Engineer and C3I Mesh Operator
  I want a dedicated comprehensive aspect exploration path for all 167 ggplot2 extensions
  So that I can verify full feature surfaces, visual graph taxonomies, high-dimensional datasets, and BDD scenarios

  Background:
    Given I am on the page "http://127.0.0.1:4100/sciviz/comprehensive"

  Scenario: ggram Flagship Architecture and StatCode Syntactic Parsing
    Then the page title should contain "SciViz 167 Extensions Comprehensive Aspect Explorer"
    And I should see the sciviz card for "ggram" with author "EvaMaeRey" and category "Composite & Multi-Panel"
    And the ggram flagship should parse code with StatCode and detect token "#<<"
    And the sciviz card for "ggram" should render a live SVG preview

  Scenario: ggram Flagship Visual Graph Types and Lined Paper Synthesis
    Then the ggram flagship should display visual type "Ruled Notebook Paper Annotated Code Visualizations"
    And the ggram flagship should display visual type "Side-by-Side Code + Plot Greeting Cards"
    And the ggram flagship should display visual type "Dark-Mode IDE Code-Execution Dashboard Panels"

  Scenario: ggram Flagship Architectural Primitives and Patchwork Stitch
    Then the sciviz card for "ggram" should offer feature "StatCode"
    And the sciviz card for "ggram" should offer feature "stamp_notebook"
    And the sciviz card for "ggram" should offer feature "stamp_graph_paper"
    And the sciviz card for "ggram" should offer feature "stamp_punched_holes"
    And the sciviz card for "ggram" should offer feature "patchwork"

  Scenario: ggram High-Dimensional Dataset Binding with Kaggle Diamond Corpus
    Then the sciviz card for "ggram" should bind dataset "diamonds_50k"
    And the sciviz card for "ggram" should detail technical aspect "ggram" "53,940"
    And the sciviz card for "ggram" should detail functional aspect "ggram" "carat"

  Scenario: Comprehensive Explorer 5-Domain 18-Checkpoint Verification
    Then the sciviz card for "ggram" should detail technical aspect "ggram" "CHK-01-TIME"
    And the sciviz card for "ggram" should detail technical aspect "ggram" "CHK-02-TAIL"
    And the sciviz card for "ggram" should detail technical aspect "ggram" "CHK-05-MUDA"
    And the sciviz card for "ggram" should detail technical aspect "ggram" "CHK-07-DRIVE"
    And the sciviz card for "ggram" should detail technical aspect "ggram" "CHK-12-GLEAM"
    And the sciviz card for "ggram" should detail technical aspect "ggram" "CHK-18-JJ"

  Scenario: High-Dimensional Empirical and Synthetic Dataset Binding Matrix
    Then the sciviz card for "ggram" should detail technical aspect "ggram" "240,000"
    And the sciviz card for "ggram" should detail technical aspect "ggram" "150,000"
    And the sciviz card for "ggram" should detail technical aspect "ggram" "100,000"
    And the sciviz card for "ggram" should detail technical aspect "ggram" "120,000"
    And the sciviz card for "ggram" should detail technical aspect "ggram" "75,000"

  Scenario Outline: Category Deep-Dive Aspect Verification for <name> in <category>
    Then the sciviz card for "<name>" should bind dataset "<dataset>"
    And the sciviz card for "<name>" should render a live SVG preview
    And the sciviz card for "<name>" should offer feature "<name>" "<feature>"

    Examples:
      | name | category | dataset | feature |
      | ggram | Composite & Multi-Panel | diamonds_50k | StatCode |
      | ggdist | Uncertainty & Distribution | MCMC Posterior Trace | Slab-Interval |
      | ggQQunif | Uncertainty & Distribution | MCMC Posterior Trace | Quantile-Uniform |
      | ggnetwork | Network & Graph Topology | uos_swarm_mesh | Node-Edge Graph |
      | geomnet | Network & Graph Topology | uos_swarm_mesh | Direct Adjacency |
      | ggalluvial | Flow, Alluvial & Sankey | Clinical Trial Patient Cohort | Alluvial Strata |
      | ggbump | Flow, Alluvial & Sankey | Clinical Trial Patient Cohort | Sigmoid Bump Curves |
      | treemapify | Hierarchical Partition | uos_telemetry_100k | Voronoi Treemap |
      | ggmosaic | Hierarchical Partition | uos_telemetry_100k | Contingency Mosaic |
      | ggtree | Bioinformatics & Genomics | TCGA Pan-Cancer | Phylogenetic Tree |
      | survminer | Bioinformatics & Genomics | TCGA Pan-Cancer | Kaplan-Meier Survival |
      | ggspatial | Spatial & Vector Field | Global Atmospheric Pressure | Spatial Geodesic Vector |
      | ggseas | Quality Control & Time-Series | uos_telemetry_100k | Seasonal Trend Decomposition |
      | ggTimeSeries | Quality Control & Time-Series | uos_telemetry_100k | Calendar Heatmap |
      | ggthemes | Theming, Palettes & Aesthetics | uos_telemetry_100k | Production Display Theme |
      | ggrepel | Typography & Text Repel | uos_telemetry_100k | Force-Directed Label Repel |
      | plotROC | Statistical Diagnosis & Inference | uos_telemetry_100k | Empirical ROC Curve |
      | ggbreak | Multi-Scale & Coordinates | uos_telemetry_100k | Scale Axis Break |
      | ggedit | Introspection & Layer Editing | uos_telemetry_100k | Interactive Layer Mutation |
      | gg3D | 3D & Perspective Projection | uos_telemetry_100k | Isometric 3D Projection |
      | ggfx | Pattern, Filter & Shaders | uos_telemetry_100k | GPU Shader Effects |
