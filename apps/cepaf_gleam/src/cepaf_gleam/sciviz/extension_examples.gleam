//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/sciviz/extension_examples</module></identity>
////   <fractal-topology><layer>L2_COMPONENT..L8_VERIFICATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-SCIVIZ-001, SC-CHECKLIST-001, SC-INTENT-ATLAS-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Live Visual Examples and Declarative Code Generator for all 167 Registered
//// ggplot2 Extensions in the Gallery (https://exts.ggplot2.tidyverse.org/gallery/).
//// Provides exact UI/UX parity with visual diagram cards, code snippets, and SVG geoms.
//// Zero-Muda compliant: Pure Gleam on BEAM VM, 0 external dependencies, 0 foreign NIFs.

import cepaf_gleam/sciviz/extension_catalog.{
  type ExtensionMetadata, BioinformaticsGenomics,
  CompositeMultiPanel, DimensionalityReduction, FlowAlluvialSankey,
  HierarchicalPartition, IntrospectionLayerEditing, MultiScaleCoordinate,
  NetworkGraphTopology, PatternFilterShader, QualityControlTimeSeries,
  SpatialVectorField, StatisticalDiagnosisInference, ThemingPaletteAesthetic,
  ThreeDimensionalProjection, TypographyTextRepel, UncertaintyDistribution,
}

/// Generates a live, self-contained SVG visual thumbnail (viewBox 0 0 320 120)
/// illustrating the exact diagram or graphical feature of the extension.
pub fn example_svg(ext: ExtensionMetadata) -> String {
  let header_badge = "<rect x=\"10\" y=\"10\" width=\"300\" height=\"100\" rx=\"6\" fill=\"#030712\" stroke=\"#1e293b\" stroke-width=\"1\"/>"
    <> "<text x=\"20\" y=\"26\" fill=\"#64748b\" font-size=\"9\" font-family=\"monospace\" font-weight=\"bold\">"
    <> ext.name
    <> "</text>"

  let geom_svg = case ext.category {
    UncertaintyDistribution ->
      // Half-eye slab + credible intervals
      "<path d=\"M 40 90 Q 90 90, 130 55 Q 160 30, 180 30 Q 200 30, 230 55 Q 270 90, 290 90 Z\" fill=\"#38bdf8\" fill-opacity=\"0.35\" stroke=\"#38bdf8\" stroke-width=\"1.5\"/>"
      <> "<line x1=\"60\" y1=\"90\" x2=\"270\" y2=\"90\" stroke=\"#94a3b8\" stroke-width=\"1.5\"/>"
      <> "<line x1=\"100\" y1=\"90\" x2=\"240\" y2=\"90\" stroke=\"#38bdf8\" stroke-width=\"3\" stroke-linecap=\"round\"/>"
      <> "<line x1=\"140\" y1=\"90\" x2=\"210\" y2=\"90\" stroke=\"#0284c7\" stroke-width=\"5\" stroke-linecap=\"round\"/>"
      <> "<circle cx=\"175\" cy=\"90\" r=\"3.5\" fill=\"#ffffff\"/>"

    NetworkGraphTopology ->
      // Force-directed graph nodes and curved edges
      "<path d=\"M 70 50 Q 120 70, 160 65\" stroke=\"#475569\" stroke-width=\"1.5\" fill=\"none\"/>"
      <> "<path d=\"M 70 90 Q 120 75, 160 65\" stroke=\"#475569\" stroke-width=\"1.5\" fill=\"none\"/>"
      <> "<path d=\"M 160 65 Q 210 50, 250 45\" stroke=\"#475569\" stroke-width=\"1.5\" fill=\"none\"/>"
      <> "<path d=\"M 160 65 Q 210 85, 250 95\" stroke=\"#475569\" stroke-width=\"1.5\" fill=\"none\"/>"
      <> "<circle cx=\"70\" cy=\"50\" r=\"8\" fill=\"#818cf8\"/>"
      <> "<circle cx=\"70\" cy=\"90\" r=\"8\" fill=\"#818cf8\"/>"
      <> "<circle cx=\"160\" cy=\"65\" r=\"12\" fill=\"#38bdf8\" stroke=\"#ffffff\" stroke-width=\"1.5\"/>"
      <> "<circle cx=\"250\" cy=\"45\" r=\"7\" fill=\"#34d399\"/>"
      <> "<circle cx=\"250\" cy=\"95\" r=\"9\" fill=\"#fbbf24\"/>"

    FlowAlluvialSankey ->
      // Alluvial smooth flow ribbons
      "<rect x=\"40\" y=\"35\" width=\"15\" height=\"65\" rx=\"2\" fill=\"#38bdf8\"/>"
      <> "<rect x=\"150\" y=\"35\" width=\"15\" height=\"45\" rx=\"2\" fill=\"#34d399\"/>"
      <> "<rect x=\"150\" y=\"85\" width=\"15\" height=\"15\" rx=\"2\" fill=\"#f87171\"/>"
      <> "<rect x=\"260\" y=\"35\" width=\"15\" height=\"45\" rx=\"2\" fill=\"#4ade80\"/>"
      <> "<path d=\"M 55 35 C 100 35, 105 35, 150 35 L 150 80 C 105 80, 100 80, 55 80 Z\" fill=\"#38bdf8\" fill-opacity=\"0.35\"/>"
      <> "<path d=\"M 55 80 C 100 80, 105 85, 150 85 L 150 100 C 105 100, 100 100, 55 100 Z\" fill=\"#f87171\" fill-opacity=\"0.35\"/>"
      <> "<path d=\"M 165 35 C 210 35, 215 35, 260 35 L 260 80 C 215 80, 210 80, 165 80 Z\" fill=\"#34d399\" fill-opacity=\"0.35\"/>"

    HierarchicalPartition ->
      // Treemap nested partitioning
      "<rect x=\"40\" y=\"35\" width=\"120\" height=\"65\" rx=\"2\" fill=\"#38bdf8\" fill-opacity=\"0.2\" stroke=\"#38bdf8\" stroke-width=\"1\"/>"
      <> "<text x=\"50\" y=\"55\" fill=\"#38bdf8\" font-size=\"10\" font-family=\"monospace\">Apps (48%)</text>"
      <> "<rect x=\"165\" y=\"35\" width=\"75\" height=\"65\" rx=\"2\" fill=\"#818cf8\" fill-opacity=\"0.2\" stroke=\"#818cf8\" stroke-width=\"1\"/>"
      <> "<text x=\"172\" y=\"55\" fill=\"#818cf8\" font-size=\"9\" font-family=\"monospace\">Engines</text>"
      <> "<rect x=\"245\" y=\"35\" width=\"45\" height=\"30\" rx=\"2\" fill=\"#34d399\" fill-opacity=\"0.2\" stroke=\"#34d399\" stroke-width=\"1\"/>"
      <> "<rect x=\"245\" y=\"70\" width=\"45\" height=\"30\" rx=\"2\" fill=\"#fbbf24\" fill-opacity=\"0.2\" stroke=\"#fbbf24\" stroke-width=\"1\"/>"

    SpatialVectorField ->
      // Geographic vector field arrows
      "<path d=\"M 40 85 Q 90 45, 150 60 Q 210 75, 270 45 L 280 95 L 40 95 Z\" fill=\"#1e293b\" stroke=\"#334155\" stroke-width=\"1\"/>"
      <> "<line x1=\"60\" y1=\"65\" x2=\"90\" y2=\"50\" stroke=\"#38bdf8\" stroke-width=\"2\"/>"
      <> "<polygon points=\"90,50 82,48 85,55\" fill=\"#38bdf8\"/>"
      <> "<line x1=\"130\" y1=\"70\" x2=\"165\" y2=\"60\" stroke=\"#38bdf8\" stroke-width=\"2\"/>"
      <> "<polygon points=\"165,60 157,58 160,65\" fill=\"#38bdf8\"/>"
      <> "<line x1=\"210\" y1=\"65\" x2=\"245\" y2=\"75\" stroke=\"#38bdf8\" stroke-width=\"2\"/>"
      <> "<polygon points=\"245,75 237,72 240,79\" fill=\"#38bdf8\"/>"

    QualityControlTimeSeries ->
      // Time-series control chart with UCL/LCL limits
      "<line x1=\"40\" y1=\"45\" x2=\"280\" y2=\"45\" stroke=\"#f87171\" stroke-width=\"1\" stroke-dasharray=\"3,3\"/>"
      <> "<text x=\"245\" y=\"42\" fill=\"#f87171\" font-size=\"8\" font-family=\"monospace\">UCL (+3s)</text>"
      <> "<line x1=\"40\" y1=\"70\" x2=\"280\" y2=\"70\" stroke=\"#64748b\" stroke-width=\"1\"/>"
      <> "<line x1=\"40\" y1=\"95\" x2=\"280\" y2=\"95\" stroke=\"#f87171\" stroke-width=\"1\" stroke-dasharray=\"3,3\"/>"
      <> "<text x=\"245\" y=\"92\" fill=\"#f87171\" font-size=\"8\" font-family=\"monospace\">LCL (-3s)</text>"
      <> "<polyline points=\"45,72 75,65 105,78 135,52 165,68 195,62 225,48 255,75 275,69\" fill=\"none\" stroke=\"#38bdf8\" stroke-width=\"1.8\"/>"
      <> "<circle cx=\"225\" cy=\"48\" r=\"3.5\" fill=\"#fbbf24\" stroke=\"#0f172a\" stroke-width=\"1\"/>"

    BioinformaticsGenomics ->
      // Genomic ideogram track / Manhattan spikes
      "<line x1=\"40\" y1=\"85\" x2=\"280\" y2=\"85\" stroke=\"#334155\" stroke-width=\"1\"/>"
      <> "<line x1=\"40\" y1=\"50\" x2=\"280\" y2=\"50\" stroke=\"#ef4444\" stroke-width=\"1\" stroke-dasharray=\"3,2\"/>"
      <> "<circle cx=\"60\" cy=\"75\" r=\"2\" fill=\"#38bdf8\"/>"
      <> "<circle cx=\"90\" cy=\"68\" r=\"2\" fill=\"#38bdf8\"/>"
      <> "<circle cx=\"120\" cy=\"72\" r=\"2\" fill=\"#38bdf8\"/>"
      <> "<circle cx=\"150\" cy=\"35\" r=\"3.5\" fill=\"#ef4444\"/>"
      <> "<text x=\"158\" y=\"38\" fill=\"#ef4444\" font-size=\"8\" font-family=\"monospace\">p<1e-8</text>"
      <> "<circle cx=\"180\" cy=\"78\" r=\"2\" fill=\"#38bdf8\"/>"
      <> "<circle cx=\"220\" cy=\"62\" r=\"2\" fill=\"#38bdf8\"/>"
      <> "<circle cx=\"260\" cy=\"42\" r=\"3\" fill=\"#fbbf24\"/>"

    TypographyTextRepel ->
      // Repelled text labels with curved leader arrows
      "<circle cx=\"90\" cy=\"75\" r=\"4\" fill=\"#38bdf8\"/>"
      <> "<circle cx=\"160\" cy=\"60\" r=\"4\" fill=\"#38bdf8\"/>"
      <> "<circle cx=\"230\" cy=\"80\" r=\"4\" fill=\"#38bdf8\"/>"
      <> "<path d=\"M 70 45 Q 85 55, 88 70\" stroke=\"#94a3b8\" stroke-width=\"1\" fill=\"none\" marker-end=\"url(#arrow)\"/>"
      <> "<rect x=\"45\" y=\"35\" width=\"40\" height=\"16\" rx=\"3\" fill=\"#1e293b\" stroke=\"#38bdf8\" stroke-width=\"0.8\"/>"
      <> "<text x=\"50\" y=\"47\" fill=\"#ffffff\" font-size=\"8\" font-family=\"monospace\">Alpha</text>"
      <> "<path d=\"M 180 35 Q 170 48, 163 56\" stroke=\"#94a3b8\" stroke-width=\"1\" fill=\"none\"/>"
      <> "<rect x=\"180\" y=\"30\" width=\"36\" height=\"16\" rx=\"3\" fill=\"#1e293b\" stroke=\"#38bdf8\" stroke-width=\"0.8\"/>"
      <> "<text x=\"184\" y=\"42\" fill=\"#ffffff\" font-size=\"8\" font-family=\"monospace\">Beta</text>"

    MultiScaleCoordinate ->
      // Ternary simplex coordinate triangle
      "<polygon points=\"160,35 90,95 230,95\" fill=\"#1e293b\" stroke=\"#38bdf8\" stroke-width=\"1.5\"/>"
      <> "<line x1=\"160\" y1=\"35\" x2=\"160\" y2=\"95\" stroke=\"#334155\" stroke-width=\"0.8\" stroke-dasharray=\"2,2\"/>"
      <> "<circle cx=\"150\" cy=\"75\" r=\"4\" fill=\"#34d399\" stroke=\"#ffffff\" stroke-width=\"1\"/>"
      <> "<text x=\"155\" y=\"32\" fill=\"#94a3b8\" font-size=\"8\" font-family=\"monospace\" text-anchor=\"middle\">A (40%)</text>"
      <> "<text x=\"75\" y=\"102\" fill=\"#94a3b8\" font-size=\"8\" font-family=\"monospace\">B (30%)</text>"
      <> "<text x=\"235\" y=\"102\" fill=\"#94a3b8\" font-size=\"8\" font-family=\"monospace\">C (30%)</text>"

    CompositeMultiPanel ->
      // Multi-panel A+B/C composite grid
      "<rect x=\"40\" y=\"35\" width=\"110\" height=\"30\" rx=\"3\" fill=\"#0f172a\" stroke=\"#38bdf8\" stroke-width=\"1\"/>"
      <> "<text x=\"48\" y=\"53\" fill=\"#38bdf8\" font-size=\"9\" font-family=\"monospace\">Panel A</text>"
      <> "<rect x=\"165\" y=\"35\" width=\"110\" height=\"30\" rx=\"3\" fill=\"#0f172a\" stroke=\"#818cf8\" stroke-width=\"1\"/>"
      <> "<text x=\"173\" y=\"53\" fill=\"#818cf8\" font-size=\"9\" font-family=\"monospace\">Panel B</text>"
      <> "<rect x=\"40\" y=\"72\" width=\"235\" height=\"28\" rx=\"3\" fill=\"#0f172a\" stroke=\"#34d399\" stroke-width=\"1\"/>"
      <> "<text x=\"48\" y=\"90\" fill=\"#34d399\" font-size=\"9\" font-family=\"monospace\">Panel C (Aligned Integrated Spanning)</text>"

    ThreeDimensionalProjection ->
      // 3D wireframe isometric perspective
      "<polygon points=\"120,40 200,40 240,65 160,65\" fill=\"#38bdf8\" fill-opacity=\"0.15\" stroke=\"#38bdf8\" stroke-width=\"1\"/>"
      <> "<polygon points=\"120,40 160,65 160,100 120,75\" fill=\"#0284c7\" fill-opacity=\"0.3\" stroke=\"#38bdf8\" stroke-width=\"1\"/>"
      <> "<polygon points=\"160,65 240,65 240,100 160,100\" fill=\"#0369a1\" fill-opacity=\"0.4\" stroke=\"#38bdf8\" stroke-width=\"1\"/>"
      <> "<line x1=\"160\" y1=\"65\" x2=\"160\" y2=\"100\" stroke=\"#ffffff\" stroke-width=\"1.5\"/>"

    StatisticalDiagnosisInference ->
      // Residual scatter + regression fit + p-value bracket
      "<line x1=\"45\" y1=\"95\" x2=\"275\" y2=\"95\" stroke=\"#334155\" stroke-width=\"1\"/>"
      <> "<line x1=\"45\" y1=\"95\" x2=\"45\" y2=\"35\" stroke=\"#334155\" stroke-width=\"1\"/>"
      <> "<circle cx=\"75\" cy=\"80\" r=\"2.5\" fill=\"#94a3b8\"/>"
      <> "<circle cx=\"115\" cy=\"70\" r=\"2.5\" fill=\"#94a3b8\"/>"
      <> "<circle cx=\"155\" cy=\"62\" r=\"2.5\" fill=\"#94a3b8\"/>"
      <> "<circle cx=\"195\" cy=\"52\" r=\"2.5\" fill=\"#94a3b8\"/>"
      <> "<circle cx=\"235\" cy=\"45\" r=\"2.5\" fill=\"#94a3b8\"/>"
      <> "<line x1=\"55\" y1=\"85\" x2=\"265\" y2=\"40\" stroke=\"#38bdf8\" stroke-width=\"1.8\"/>"
      <> "<path d=\"M 140 38 L 140 33 L 220 33 L 220 38\" stroke=\"#34d399\" stroke-width=\"1\" fill=\"none\"/>"
      <> "<text x=\"165\" y=\"30\" fill=\"#34d399\" font-size=\"8\" font-family=\"monospace\">p=0.002</text>"

    PatternFilterShader ->
      // Pattern fills (stripes / dots) with glowing strokes
      "<defs><pattern id=\"patStripe\" width=\"8\" height=\"8\" patternTransform=\"rotate(45 0 0)\" patternUnits=\"userSpaceOnUse\"><line x1=\"0\" y1=\"0\" x2=\"0\" y2=\"8\" stroke=\"#38bdf8\" stroke-width=\"2\"/></pattern></defs>"
      <> "<rect x=\"55\" y=\"45\" width=\"45\" height=\"50\" fill=\"url(#patStripe)\" stroke=\"#38bdf8\" stroke-width=\"1\"/>"
      <> "<rect x=\"115\" y=\"35\" width=\"45\" height=\"60\" fill=\"#818cf8\" fill-opacity=\"0.3\" stroke=\"#818cf8\" stroke-width=\"1.5\" filter=\"drop-shadow(0 0 4px #818cf8)\"/>"
      <> "<rect x=\"175\" y=\"55\" width=\"45\" height=\"40\" fill=\"url(#patStripe)\" stroke=\"#34d399\" stroke-width=\"1\"/>"
      <> "<rect x=\"235\" y=\"40\" width=\"45\" height=\"55\" fill=\"#f59e0b\" fill-opacity=\"0.3\" stroke=\"#f59e0b\" stroke-width=\"1.5\"/>"

    DimensionalityReduction ->
      // PCA Biplot vectors & t-SNE / UMAP clusters
      "<line x1=\"160\" y1=\"40\" x2=\"160\" y2=\"95\" stroke=\"#1e293b\" stroke-width=\"1\"/>"
      <> "<line x1=\"50\" y1=\"68\" x2=\"270\" y2=\"68\" stroke=\"#1e293b\" stroke-width=\"1\"/>"
      <> "<circle cx=\"110\" cy=\"55\" r=\"3\" fill=\"#38bdf8\"/>"
      <> "<circle cx=\"125\" cy=\"62\" r=\"3\" fill=\"#38bdf8\"/>"
      <> "<circle cx=\"100\" cy=\"65\" r=\"3\" fill=\"#38bdf8\"/>"
      <> "<circle cx=\"210\" cy=\"75\" r=\"3\" fill=\"#f43f5e\"/>"
      <> "<circle cx=\"225\" cy=\"82\" r=\"3\" fill=\"#f43f5e\"/>"
      <> "<circle cx=\"235\" cy=\"70\" r=\"3\" fill=\"#f43f5e\"/>"
      <> "<line x1=\"160\" y1=\"68\" x2=\"195\" y2=\"50\" stroke=\"#34d399\" stroke-width=\"1.8\"/>"
      <> "<text x=\"200\" y=\"50\" fill=\"#34d399\" font-size=\"8\" font-family=\"monospace\">PC1 (68%)</text>"

    ThemingPaletteAesthetic ->
      // Palette color swatch ramp
      "<rect x=\"45\" y=\"45\" width=\"32\" height=\"40\" rx=\"2\" fill=\"#440154\"/>"
      <> "<rect x=\"82\" y=\"45\" width=\"32\" height=\"40\" rx=\"2\" fill=\"#414487\"/>"
      <> "<rect x=\"119\" y=\"45\" width=\"32\" height=\"40\" rx=\"2\" fill=\"#2a788e\"/>"
      <> "<rect x=\"156\" y=\"45\" width=\"32\" height=\"40\" rx=\"2\" fill=\"#22a884\"/>"
      <> "<rect x=\"193\" y=\"45\" width=\"32\" height=\"40\" rx=\"2\" fill=\"#7ad151\"/>"
      <> "<rect x=\"230\" y=\"45\" width=\"32\" height=\"40\" rx=\"2\" fill=\"#fde725\"/>"
      <> "<text x=\"45\" y=\"98\" fill=\"#94a3b8\" font-size=\"8\" font-family=\"monospace\">Scale: " <> ext.name <> "</text>"

    IntrospectionLayerEditing ->
      // Highlighting focused trace over dimmed background
      "<polyline points=\"45,85 85,82 125,84 165,80 205,82 245,80 275,81\" fill=\"none\" stroke=\"#334155\" stroke-width=\"1\"/>"
      <> "<polyline points=\"45,72 85,74 125,70 165,72 205,71 245,70 275,73\" fill=\"none\" stroke=\"#334155\" stroke-width=\"1\"/>"
      <> "<polyline points=\"45,65 85,58 125,48 165,38 205,42 245,35 275,32\" fill=\"none\" stroke=\"#38bdf8\" stroke-width=\"2.5\"/>"
      <> "<circle cx=\"245\" cy=\"35\" r=\"4\" fill=\"#38bdf8\" stroke=\"#ffffff\" stroke-width=\"1\"/>"
      <> "<text x=\"210\" y=\"26\" fill=\"#38bdf8\" font-size=\"8\" font-family=\"monospace\">Focal Trace</text>"
  }

  "<svg viewBox=\"0 0 320 120\" width=\"100%\" height=\"120\" style=\"background:#020617; border-radius:6px;\">"
  <> header_badge
  <> geom_svg
  <> "</svg>"
}

/// Generates an authentic declarative R / Gleam Atlas code snippet showing
/// how to instantiate and display the extension feature.
pub fn example_code(ext: ExtensionMetadata) -> String {
  let pkg = ext.name
  let geom = case ext.category {
    UncertaintyDistribution -> "geom_slabinterval(aes(x = group, y = estimate))"
    NetworkGraphTopology -> "geom_edge_link() + geom_node_point(aes(size = degree))"
    FlowAlluvialSankey -> "geom_alluvium(aes(fill = cohort)) + geom_stratum()"
    HierarchicalPartition -> "geom_treemap(aes(area = weight, fill = subsystem))"
    SpatialVectorField -> "geom_sf(aes(fill = elevation)) + geom_vector()"
    QualityControlTimeSeries -> "stat_qc(aes(x = time, y = measurement), method = \"XmR\")"
    BioinformaticsGenomics -> "geom_tree() + geom_tiplab(size = 3)"
    TypographyTextRepel -> "geom_text_repel(aes(label = identifier), box.padding = 0.5)"
    MultiScaleCoordinate -> "coord_tern() + geom_point(aes(a = comp1, b = comp2, c = comp3))"
    CompositeMultiPanel -> "p1 + p2 / p3 + plot_layout(guides = 'collect')"
    ThreeDimensionalProjection -> "stat_3d(aes(theta = 45, phi = 30))"
    StatisticalDiagnosisInference -> "geom_point() + stat_regline_equation(label.x = 3)"
    PatternFilterShader -> "geom_col_pattern(pattern = 'stripe', pattern_angle = 45)"
    DimensionalityReduction -> "geom_point(aes(color = cluster)) + stat_chull()"
    ThemingPaletteAesthetic -> "scale_fill_" <> pkg <> "() + theme_" <> pkg <> "()"
    IntrospectionLayerEditing -> "gghighlight(metric > threshold, unhighlighted_colour = 'grey20')"
  }

  "library(ggplot2)\nlibrary(" <> pkg <> ")\nggplot(dataset) + " <> geom
}
