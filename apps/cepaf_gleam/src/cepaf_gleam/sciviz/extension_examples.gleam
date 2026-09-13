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

  let geom_svg = case ext.name {
    "ggram" ->
      // Side-by-side code notebook on left + generated ggplot on right (patchwork stitch)
      "<rect x=\"25\" y=\"32\" width=\"130\" height=\"72\" rx=\"4\" fill=\"#0f172a\" stroke=\"#334155\" stroke-width=\"1\"/>"
      <> "<circle cx=\"32\" cy=\"48\" r=\"2.5\" fill=\"#1e293b\" stroke=\"#475569\" stroke-width=\"0.8\"/>"
      <> "<circle cx=\"32\" cy=\"68\" r=\"2.5\" fill=\"#1e293b\" stroke=\"#475569\" stroke-width=\"0.8\"/>"
      <> "<circle cx=\"32\" cy=\"88\" r=\"2.5\" fill=\"#1e293b\" stroke=\"#475569\" stroke-width=\"0.8\"/>"
      <> "<line x1=\"38\" y1=\"32\" x2=\"38\" y2=\"104\" stroke=\"#dc2626\" stroke-width=\"0.8\" stroke-opacity=\"0.6\"/>"
      <> "<line x1=\"38\" y1=\"46\" x2=\"155\" y2=\"46\" stroke=\"#3b82f6\" stroke-width=\"0.5\" stroke-opacity=\"0.3\"/>"
      <> "<line x1=\"38\" y1=\"60\" x2=\"155\" y2=\"60\" stroke=\"#3b82f6\" stroke-width=\"0.5\" stroke-opacity=\"0.3\"/>"
      <> "<line x1=\"38\" y1=\"74\" x2=\"155\" y2=\"74\" stroke=\"#3b82f6\" stroke-width=\"0.5\" stroke-opacity=\"0.3\"/>"
      <> "<line x1=\"38\" y1=\"88\" x2=\"155\" y2=\"88\" stroke=\"#3b82f6\" stroke-width=\"0.5\" stroke-opacity=\"0.3\"/>"
      <> "<rect x=\"39\" y=\"62\" width=\"115\" height=\"12\" fill=\"#fef08a\" fill-opacity=\"0.25\"/>"
      <> "<text x=\"42\" y=\"44\" fill=\"#94a3b8\" font-size=\"6.5\" font-family=\"monospace\">1: ggplot(cars) +</text>"
      <> "<text x=\"42\" y=\"58\" fill=\"#94a3b8\" font-size=\"6.5\" font-family=\"monospace\">2:   aes(speed, dist) +</text>"
      <> "<text x=\"42\" y=\"72\" fill=\"#facc15\" font-size=\"6.5\" font-family=\"monospace\" font-weight=\"bold\">3:   geom_smooth() #&lt;&lt;</text>"
      <> "<text x=\"42\" y=\"86\" fill=\"#38bdf8\" font-size=\"6.5\" font-family=\"monospace\">4: ggram(&quot;Cars&quot;)</text>"
      <> "<rect x=\"165\" y=\"32\" width=\"135\" height=\"72\" rx=\"4\" fill=\"#020617\" stroke=\"#38bdf8\" stroke-width=\"1\"/>"
      <> "<text x=\"172\" y=\"42\" fill=\"#38bdf8\" font-size=\"7\" font-family=\"monospace\" font-weight=\"bold\">Cars Output Plot</text>"
      <> "<circle cx=\"185\" cy=\"85\" r=\"2\" fill=\"#94a3b8\"/><circle cx=\"195\" cy=\"78\" r=\"2\" fill=\"#94a3b8\"/><circle cx=\"210\" cy=\"80\" r=\"2\" fill=\"#94a3b8\"/><circle cx=\"225\" cy=\"65\" r=\"2\" fill=\"#94a3b8\"/><circle cx=\"240\" cy=\"58\" r=\"2\" fill=\"#94a3b8\"/><circle cx=\"260\" cy=\"48\" r=\"2\" fill=\"#94a3b8\"/>"
      <> "<path d=\"M 180 90 Q 215 78, 240 60 T 285 45\" fill=\"none\" stroke=\"#38bdf8\" stroke-width=\"2\"/>"
      <> "<path d=\"M 180 94 Q 215 82, 240 64 T 285 49 L 285 41 Q 240 56, 215 74 T 180 86 Z\" fill=\"#38bdf8\" fill-opacity=\"0.2\"/>"

    "ggrepel" ->
      // Repelled labels with leader segments and anchor points
      "<circle cx=\"80\" cy=\"85\" r=\"4\" fill=\"#38bdf8\"/>"
      <> "<circle cx=\"170\" cy=\"75\" r=\"4\" fill=\"#38bdf8\"/>"
      <> "<circle cx=\"240\" cy=\"90\" r=\"4\" fill=\"#f43f5e\"/>"
      <> "<line x1=\"80\" y1=\"85\" x2=\"60\" y2=\"50\" stroke=\"#94a3b8\" stroke-width=\"1.2\" stroke-dasharray=\"2,2\"/>"
      <> "<rect x=\"35\" y=\"38\" width=\"50\" height=\"16\" rx=\"3\" fill=\"#0f172a\" stroke=\"#38bdf8\" stroke-width=\"1\"/>"
      <> "<text x=\"42\" y=\"50\" fill=\"#f8fafc\" font-size=\"8\" font-family=\"monospace\">Gene A</text>"
      <> "<line x1=\"170\" y1=\"75\" x2=\"195\" y2=\"45\" stroke=\"#94a3b8\" stroke-width=\"1.2\" stroke-dasharray=\"2,2\"/>"
      <> "<rect x=\"170\" y=\"33\" width=\"50\" height=\"16\" rx=\"3\" fill=\"#0f172a\" stroke=\"#38bdf8\" stroke-width=\"1\"/>"
      <> "<text x=\"177\" y=\"45\" fill=\"#f8fafc\" font-size=\"8\" font-family=\"monospace\">Gene B</text>"
      <> "<line x1=\"240\" y1=\"90\" x2=\"260\" y2=\"55\" stroke=\"#94a3b8\" stroke-width=\"1.2\" stroke-dasharray=\"2,2\"/>"
      <> "<rect x=\"235\" y=\"43\" width=\"52\" height=\"16\" rx=\"3\" fill=\"#0f172a\" stroke=\"#f43f5e\" stroke-width=\"1\"/>"
      <> "<text x=\"242\" y=\"55\" fill=\"#f8fafc\" font-size=\"8\" font-family=\"monospace\">Outlier!</text>"

    "ggridges" ->
      // Multiple overlapping density ridgelines
      "<path d=\"M 40 95 Q 80 95, 110 75 Q 140 55, 170 85 Q 210 95, 270 95 Z\" fill=\"#0284c7\" fill-opacity=\"0.4\" stroke=\"#38bdf8\" stroke-width=\"1.5\"/>"
      <> "<path d=\"M 40 78 Q 90 78, 120 50 Q 150 25, 190 65 Q 230 78, 270 78 Z\" fill=\"#6366f1\" fill-opacity=\"0.4\" stroke=\"#818cf8\" stroke-width=\"1.5\"/>"
      <> "<path d=\"M 40 60 Q 100 60, 140 32 Q 170 12, 200 45 Q 240 60, 270 60 Z\" fill=\"#10b981\" fill-opacity=\"0.4\" stroke=\"#34d399\" stroke-width=\"1.5\"/>"
      <> "<line x1=\"150\" y1=\"25\" x2=\"150\" y2=\"78\" stroke=\"#fbbf24\" stroke-width=\"1\" stroke-dasharray=\"2,2\"/>"
      <> "<text x=\"245\" y=\"55\" fill=\"#34d399\" font-size=\"8\" font-family=\"monospace\">Cohort 3</text>"
      <> "<text x=\"245\" y=\"73\" fill=\"#818cf8\" font-size=\"8\" font-family=\"monospace\">Cohort 2</text>"
      <> "<text x=\"245\" y=\"90\" fill=\"#38bdf8\" font-size=\"8\" font-family=\"monospace\">Cohort 1</text>"

    "patchwork" ->
      // Multi-panel composition (Panel A + Panel B / Panel C)
      "<rect x=\"40\" y=\"35\" width=\"105\" height=\"32\" rx=\"2\" fill=\"#0b132b\" stroke=\"#38bdf8\" stroke-width=\"1\"/>"
      <> "<text x=\"45\" y=\"46\" fill=\"#38bdf8\" font-size=\"8\" font-weight=\"bold\">A</text>"
      <> "<circle cx=\"80\" cy=\"52\" r=\"2\" fill=\"#38bdf8\"/><circle cx=\"100\" cy=\"46\" r=\"2\" fill=\"#38bdf8\"/><circle cx=\"120\" cy=\"58\" r=\"2\" fill=\"#38bdf8\"/>"
      <> "<rect x=\"155\" y=\"35\" width=\"115\" height=\"32\" rx=\"2\" fill=\"#0b132b\" stroke=\"#34d399\" stroke-width=\"1\"/>"
      <> "<text x=\"160\" y=\"46\" fill=\"#34d399\" font-size=\"8\" font-weight=\"bold\">B</text>"
      <> "<rect x=\"180\" y=\"45\" width=\"10\" height=\"18\" fill=\"#34d399\" fill-opacity=\"0.5\"/><rect x=\"195\" y=\"39\" width=\"10\" height=\"24\" fill=\"#34d399\" fill-opacity=\"0.5\"/><rect x=\"210\" y=\"48\" width=\"10\" height=\"15\" fill=\"#34d399\" fill-opacity=\"0.5\"/>"
      <> "<rect x=\"40\" y=\"72\" width=\"230\" height=\"30\" rx=\"2\" fill=\"#0b132b\" stroke=\"#f59e0b\" stroke-width=\"1\"/>"
      <> "<text x=\"45\" y=\"83\" fill=\"#f59e0b\" font-size=\"8\" font-weight=\"bold\">C</text>"
      <> "<path d=\"M 65 92 Q 110 78, 150 88 T 240 80\" fill=\"none\" stroke=\"#f59e0b\" stroke-width=\"1.5\"/>"

    "ggstatsplot" ->
      // Violin-boxplot with hypothesis testing subtitle
      "<text x=\"40\" y=\"38\" fill=\"#34d399\" font-size=\"8\" font-family=\"monospace\">F(2, 45) = 14.2, p &lt; 0.001, &#969;&#178; = 0.35</text>"
      <> "<path d=\"M 85 50 C 70 65, 70 80, 85 95 C 100 80, 100 65, 85 50 Z\" fill=\"#38bdf8\" fill-opacity=\"0.3\" stroke=\"#38bdf8\" stroke-width=\"1\"/>"
      <> "<rect x=\"82\" y=\"65\" width=\"6\" height=\"16\" fill=\"#0f172a\" stroke=\"#ffffff\" stroke-width=\"1\"/>"
      <> "<circle cx=\"85\" cy=\"73\" r=\"2\" fill=\"#fbbf24\"/>"
      <> "<path d=\"M 185 45 C 165 60, 165 85, 185 95 C 205 85, 205 60, 185 45 Z\" fill=\"#34d399\" fill-opacity=\"0.3\" stroke=\"#34d399\" stroke-width=\"1\"/>"
      <> "<rect x=\"182\" y=\"60\" width=\"6\" height=\"20\" fill=\"#0f172a\" stroke=\"#ffffff\" stroke-width=\"1\"/>"
      <> "<circle cx=\"185\" cy=\"70\" r=\"2\" fill=\"#fbbf24\"/>"

    "survminer" ->
      // Kaplan-Meier stepped survival curve + risk table indicators
      "<path d=\"M 40 45 L 80 45 L 80 55 L 120 55 L 120 68 L 160 68 L 160 82 L 210 82 L 210 92 L 260 92\" fill=\"none\" stroke=\"#38bdf8\" stroke-width=\"2\"/>"
      <> "<line x1=\"80\" y1=\"42\" x2=\"80\" y2=\"48\" stroke=\"#38bdf8\" stroke-width=\"1.5\"/>"
      <> "<line x1=\"140\" y1=\"65\" x2=\"140\" y2=\"71\" stroke=\"#38bdf8\" stroke-width=\"1.5\"/>"
      <> "<path d=\"M 40 45 L 70 45 L 70 62 L 110 62 L 110 78 L 150 78 L 150 90 L 260 90\" fill=\"none\" stroke=\"#f43f5e\" stroke-width=\"1.5\" stroke-dasharray=\"3,2\"/>"
      <> "<text x=\"40\" y=\"103\" fill=\"#64748b\" font-size=\"7\" font-family=\"monospace\">Risk:  Cohort 1 (n=50)  Cohort 2 (n=48)</text>"

    "gganimate" ->
      // Frame motion path with ghost trails and time indicator
      "<path d=\"M 50 85 Q 110 35, 170 70 T 260 45\" fill=\"none\" stroke=\"#1e293b\" stroke-width=\"2\"/>"
      <> "<circle cx=\"195\" cy=\"58\" r=\"3\" fill=\"#38bdf8\" fill-opacity=\"0.2\"/>"
      <> "<circle cx=\"215\" cy=\"50\" r=\"4\" fill=\"#38bdf8\" fill-opacity=\"0.4\"/>"
      <> "<circle cx=\"235\" cy=\"46\" r=\"5\" fill=\"#38bdf8\" fill-opacity=\"0.7\"/>"
      <> "<circle cx=\"255\" cy=\"45\" r=\"6\" fill=\"#38bdf8\" stroke=\"#ffffff\" stroke-width=\"1.5\"/>"
      <> "<rect x=\"45\" y=\"35\" width=\"48\" height=\"15\" rx=\"2\" fill=\"#0284c7\"/>"
      <> "<text x=\"50\" y=\"46\" fill=\"#ffffff\" font-size=\"8\" font-family=\"monospace\">t = 4.2s</text>"

    "ggforce" ->
      // Voronoi tessellation cells + spline hull
      "<polygon points=\"60,45 100,35 120,65 90,85 50,75\" fill=\"#38bdf8\" fill-opacity=\"0.15\" stroke=\"#38bdf8\" stroke-width=\"1\"/>"
      <> "<polygon points=\"100,35 160,35 170,70 120,65\" fill=\"#818cf8\" fill-opacity=\"0.15\" stroke=\"#818cf8\" stroke-width=\"1\"/>"
      <> "<polygon points=\"120,65 170,70 160,95 90,85\" fill=\"#34d399\" fill-opacity=\"0.15\" stroke=\"#34d399\" stroke-width=\"1\"/>"
      <> "<circle cx=\"80\" cy=\"60\" r=\"3\" fill=\"#38bdf8\"/><circle cx=\"135\" cy=\"50\" r=\"3\" fill=\"#818cf8\"/><circle cx=\"135\" cy=\"78\" r=\"3\" fill=\"#34d399\"/>"
      <> "<path d=\"M 190 55 Q 230 35, 260 55 Q 270 85, 230 90 Q 190 85, 190 55 Z\" fill=\"#fbbf24\" fill-opacity=\"0.2\" stroke=\"#fbbf24\" stroke-width=\"1.5\"/>"
      <> "<text x=\"210\" y=\"72\" fill=\"#fbbf24\" font-size=\"8\" font-family=\"monospace\">Hull Cluster</text>"

    "ggcorrplot" ->
      // Correlation matrix upper triangle circles
      "<line x1=\"50\" y1=\"95\" x2=\"240\" y2=\"95\" stroke=\"#1e293b\" stroke-width=\"1\"/>"
      <> "<line x1=\"50\" y1=\"35\" x2=\"50\" y2=\"95\" stroke=\"#1e293b\" stroke-width=\"1\"/>"
      <> "<circle cx=\"75\" cy=\"80\" r=\"10\" fill=\"#38bdf8\"/>"
      <> "<circle cx=\"115\" cy=\"80\" r=\"6\" fill=\"#38bdf8\" fill-opacity=\"0.6\"/>"
      <> "<circle cx=\"155\" cy=\"80\" r=\"8\" fill=\"#f43f5e\" fill-opacity=\"0.8\"/>"
      <> "<circle cx=\"115\" cy=\"60\" r=\"10\" fill=\"#38bdf8\"/>"
      <> "<circle cx=\"155\" cy=\"60\" r=\"4\" fill=\"#38bdf8\" fill-opacity=\"0.4\"/>"
      <> "<circle cx=\"155\" cy=\"42\" r=\"10\" fill=\"#38bdf8\"/>"
      <> "<text x=\"190\" y=\"50\" fill=\"#38bdf8\" font-size=\"8\" font-family=\"monospace\">+1.0 (blue)</text>"
      <> "<text x=\"190\" y=\"65\" fill=\"#f43f5e\" font-size=\"8\" font-family=\"monospace\">-0.8 (red)</text>"

    "ggspatial" ->
      // Map tile projection with north arrow and metric scale bar
      "<path d=\"M 60 70 Q 90 50, 130 60 T 210 45 T 260 65 L 260 90 L 60 90 Z\" fill=\"#065f46\" fill-opacity=\"0.4\" stroke=\"#34d399\" stroke-width=\"1.2\"/>"
      <> "<polygon points=\"60,40 56,48 60,46 64,48\" fill=\"#f43f5e\"/>"
      <> "<text x=\"58\" y=\"37\" fill=\"#f43f5e\" font-size=\"7\" font-weight=\"bold\">N</text>"
      <> "<line x1=\"180\" y1=\"85\" x2=\"240\" y2=\"85\" stroke=\"#ffffff\" stroke-width=\"2\"/>"
      <> "<line x1=\"180\" y1=\"82\" x2=\"180\" y2=\"88\" stroke=\"#ffffff\" stroke-width=\"1\"/>"
      <> "<line x1=\"240\" y1=\"82\" x2=\"240\" y2=\"88\" stroke=\"#ffffff\" stroke-width=\"1\"/>"
      <> "<text x=\"198\" y=\"81\" fill=\"#cbd5e1\" font-size=\"7\" font-family=\"monospace\">50 km</text>"

    "gghighlight" ->
      // Highlighted series in cyan, background series in dimmed slate
      "<path d=\"M 40 85 Q 90 80, 140 82 T 260 80\" fill=\"none\" stroke=\"#334155\" stroke-width=\"1\"/>"
      <> "<path d=\"M 40 72 Q 90 75, 140 70 T 260 74\" fill=\"none\" stroke=\"#334155\" stroke-width=\"1\"/>"
      <> "<path d=\"M 40 65 Q 90 55, 140 40 T 260 32\" fill=\"none\" stroke=\"#38bdf8\" stroke-width=\"2.5\"/>"
      <> "<circle cx=\"260\" cy=\"32\" r=\"3.5\" fill=\"#38bdf8\" stroke=\"#ffffff\" stroke-width=\"1\"/>"
      <> "<text x=\"200\" y=\"25\" fill=\"#38bdf8\" font-size=\"8\" font-family=\"monospace\" font-weight=\"bold\">Peak Signal</text>"

    "ggtern" ->
      // Ternary plot triangular simplex coordinates
      "<polygon points=\"150,32 60,95 240,95\" fill=\"none\" stroke=\"#334155\" stroke-width=\"1.5\"/>"
      <> "<line x1=\"105\" y1=\"63\" x2=\"195\" y2=\"63\" stroke=\"#1e293b\" stroke-width=\"1\" stroke-dasharray=\"2,2\"/>"
      <> "<circle cx=\"145\" cy=\"60\" r=\"3\" fill=\"#38bdf8\"/>"
      <> "<circle cx=\"120\" cy=\"80\" r=\"3\" fill=\"#34d399\"/>"
      <> "<circle cx=\"180\" cy=\"85\" r=\"3\" fill=\"#f59e0b\"/>"
      <> "<text x=\"145\" y=\"28\" fill=\"#cbd5e1\" font-size=\"7\">Top (A)</text>"
      <> "<text x=\"35\" y=\"100\" fill=\"#cbd5e1\" font-size=\"7\">Left (B)</text>"
      <> "<text x=\"245\" y=\"100\" fill=\"#cbd5e1\" font-size=\"7\">Right (C)</text>"

    "gghalves" ->
      // Half-violin on left, jittered dot cloud on right
      "<path d=\"M 140 40 C 105 55, 105 75, 140 95 Z\" fill=\"#818cf8\" fill-opacity=\"0.4\" stroke=\"#818cf8\" stroke-width=\"1.5\"/>"
      <> "<line x1=\"140\" y1=\"35\" x2=\"140\" y2=\"100\" stroke=\"#cbd5e1\" stroke-width=\"1.5\"/>"
      <> "<circle cx=\"152\" cy=\"48\" r=\"2.5\" fill=\"#34d399\"/>"
      <> "<circle cx=\"158\" cy=\"56\" r=\"2.5\" fill=\"#34d399\"/>"
      <> "<circle cx=\"148\" cy=\"65\" r=\"2.5\" fill=\"#34d399\"/>"
      <> "<circle cx=\"162\" cy=\"74\" r=\"2.5\" fill=\"#34d399\"/>"
      <> "<circle cx=\"150\" cy=\"86\" r=\"2.5\" fill=\"#34d399\"/>"
      <> "<rect x=\"136\" y=\"60\" width=\"8\" height=\"16\" fill=\"#0284c7\" stroke=\"#ffffff\" stroke-width=\"1\"/>"

    "ggbeeswarm" ->
      // Columnar beeswarm point packing
      "<line x1=\"90\" y1=\"35\" x2=\"90\" y2=\"100\" stroke=\"#1e293b\" stroke-width=\"1\"/>"
      <> "<line x1=\"210\" y1=\"35\" x2=\"210\" y2=\"100\" stroke=\"#1e293b\" stroke-width=\"1\"/>"
      <> "<circle cx=\"90\" cy=\"45\" r=\"3\" fill=\"#38bdf8\"/><circle cx=\"84\" cy=\"52\" r=\"3\" fill=\"#38bdf8\"/><circle cx=\"96\" cy=\"52\" r=\"3\" fill=\"#38bdf8\"/><circle cx=\"78\" cy=\"60\" r=\"3\" fill=\"#38bdf8\"/><circle cx=\"90\" cy=\"60\" r=\"3\" fill=\"#38bdf8\"/><circle cx=\"102\" cy=\"60\" r=\"3\" fill=\"#38bdf8\"/><circle cx=\"84\" cy=\"68\" r=\"3\" fill=\"#38bdf8\"/><circle cx=\"96\" cy=\"68\" r=\"3\" fill=\"#38bdf8\"/><circle cx=\"90\" cy=\"76\" r=\"3\" fill=\"#38bdf8\"/>"
      <> "<circle cx=\"210\" cy=\"55\" r=\"3\" fill=\"#f43f5e\"/><circle cx=\"204\" cy=\"63\" r=\"3\" fill=\"#f43f5e\"/><circle cx=\"216\" cy=\"63\" r=\"3\" fill=\"#f43f5e\"/><circle cx=\"198\" cy=\"71\" r=\"3\" fill=\"#f43f5e\"/><circle cx=\"210\" cy=\"71\" r=\"3\" fill=\"#f43f5e\"/><circle cx=\"222\" cy=\"71\" r=\"3\" fill=\"#f43f5e\"/><circle cx=\"210\" cy=\"80\" r=\"3\" fill=\"#f43f5e\"/>"

    "ggstream" ->
      // Smooth undulating streamgraph stacked ribbons
      "<path d=\"M 40 68 Q 90 55, 140 62 Q 190 70, 240 65 L 240 75 Q 190 80, 140 72 Q 90 65, 40 78 Z\" fill=\"#0284c7\" fill-opacity=\"0.7\"/>"
      <> "<path d=\"M 40 60 Q 90 48, 140 54 Q 190 60, 240 55 L 240 65 Q 190 70, 140 62 Q 90 55, 40 68 Z\" fill=\"#38bdf8\" fill-opacity=\"0.7\"/>"
      <> "<path d=\"M 40 52 Q 90 38, 140 45 Q 190 48, 240 45 L 240 55 Q 190 60, 140 54 Q 90 48, 40 60 Z\" fill=\"#818cf8\" fill-opacity=\"0.7\"/>"
      <> "<line x1=\"40\" y1=\"65\" x2=\"240\" y2=\"65\" stroke=\"#ffffff\" stroke-width=\"1\" stroke-opacity=\"0.2\" stroke-dasharray=\"2,2\"/>"

    "ggbreak" ->
      // Discontinuous broken axis marks
      "<line x1=\"40\" y1=\"90\" x2=\"130\" y2=\"90\" stroke=\"#94a3b8\" stroke-width=\"1.5\"/>"
      <> "<line x1=\"150\" y1=\"90\" x2=\"270\" y2=\"90\" stroke=\"#94a3b8\" stroke-width=\"1.5\"/>"
      <> "<line x1=\"127\" y1=\"84\" x2=\"133\" y2=\"96\" stroke=\"#f43f5e\" stroke-width=\"2\"/>"
      <> "<line x1=\"147\" y1=\"84\" x2=\"153\" y2=\"96\" stroke=\"#f43f5e\" stroke-width=\"2\"/>"
      <> "<circle cx=\"70\" cy=\"80\" r=\"3\" fill=\"#38bdf8\"/><circle cx=\"100\" cy=\"75\" r=\"3\" fill=\"#38bdf8\"/>"
      <> "<circle cx=\"180\" cy=\"45\" r=\"3\" fill=\"#f59e0b\"/><circle cx=\"240\" cy=\"35\" r=\"3\" fill=\"#f59e0b\"/>"
      <> "<text x=\"132\" y=\"103\" fill=\"#f43f5e\" font-size=\"7\" font-family=\"monospace\">Break</text>"

    "ggupset" ->
      // Combination matrix for UpSet plots
      "<rect x=\"60\" y=\"35\" width=\"14\" height=\"35\" fill=\"#38bdf8\"/>"
      <> "<rect x=\"110\" y=\"45\" width=\"14\" height=\"25\" fill=\"#38bdf8\"/>"
      <> "<rect x=\"160\" y=\"55\" width=\"14\" height=\"15\" fill=\"#38bdf8\"/>"
      <> "<circle cx=\"67\" cy=\"80\" r=\"3\" fill=\"#38bdf8\"/><circle cx=\"67\" cy=\"90\" r=\"3\" fill=\"#38bdf8\"/>"
      <> "<line x1=\"67\" y1=\"80\" x2=\"67\" y2=\"90\" stroke=\"#38bdf8\" stroke-width=\"1.5\"/>"
      <> "<circle cx=\"117\" cy=\"80\" r=\"3\" fill=\"#38bdf8\"/><circle cx=\"117\" cy=\"90\" r=\"3\" fill=\"#334155\"/>"
      <> "<circle cx=\"167\" cy=\"80\" r=\"3\" fill=\"#334155\"/><circle cx=\"167\" cy=\"90\" r=\"3\" fill=\"#38bdf8\"/>"

    "ggtree" ->
      // Phylogenetic circular cladogram
      "<path d=\"M 150 65 A 35 35 0 0 1 185 65\" fill=\"none\" stroke=\"#38bdf8\" stroke-width=\"1.5\"/>"
      <> "<path d=\"M 150 65 A 35 35 0 0 0 115 65\" fill=\"none\" stroke=\"#34d399\" stroke-width=\"1.5\"/>"
      <> "<line x1=\"185\" y1=\"65\" x2=\"205\" y2=\"50\" stroke=\"#38bdf8\" stroke-width=\"1.5\"/>"
      <> "<line x1=\"185\" y1=\"65\" x2=\"205\" y2=\"80\" stroke=\"#38bdf8\" stroke-width=\"1.5\"/>"
      <> "<circle cx=\"205\" cy=\"50\" r=\"2.5\" fill=\"#38bdf8\"/><text x=\"210\" y=\"52\" fill=\"#38bdf8\" font-size=\"7\">Taxon 1</text>"
      <> "<circle cx=\"205\" cy=\"80\" r=\"2.5\" fill=\"#38bdf8\"/><text x=\"210\" y=\"82\" fill=\"#38bdf8\" font-size=\"7\">Taxon 2</text>"
      <> "<line x1=\"115\" y1=\"65\" x2=\"95\" y2=\"65\" stroke=\"#34d399\" stroke-width=\"1.5\"/>"
      <> "<circle cx=\"95\" cy=\"65\" r=\"2.5\" fill=\"#34d399\"/><text x=\"60\" y=\"67\" fill=\"#34d399\" font-size=\"7\">Outgroup</text>"

    "geomtextpath" ->
      // Text curving along a spline wave
      "<path d=\"M 45 75 Q 100 35, 155 75 T 265 75\" fill=\"none\" stroke=\"#334155\" stroke-width=\"1.5\" stroke-dasharray=\"3,3\"/>"
      <> "<text x=\"70\" y=\"55\" fill=\"#38bdf8\" font-size=\"9\" font-family=\"monospace\" font-weight=\"bold\" transform=\"rotate(-15 70 55)\">Curved Text Flow</text>"
      <> "<circle cx=\"155\" cy=\"75\" r=\"3\" fill=\"#34d399\"/>"

    "gghoriplot" ->
      // Horizon chart folded bands
      "<rect x=\"40\" y=\"45\" width=\"230\" height=\"15\" fill=\"#0284c7\" fill-opacity=\"0.3\"/>"
      <> "<path d=\"M 40 60 Q 90 48, 140 55 Q 190 60, 240 52 L 270 55 L 270 60 Z\" fill=\"#0284c7\" fill-opacity=\"0.7\"/>"
      <> "<rect x=\"40\" y=\"65\" width=\"230\" height=\"15\" fill=\"#f43f5e\" fill-opacity=\"0.3\"/>"
      <> "<path d=\"M 40 65 Q 90 78, 140 70 Q 190 65, 240 75 L 270 72 L 270 65 Z\" fill=\"#f43f5e\" fill-opacity=\"0.7\"/>"

    "ggnewscale" ->
      // Dual side-by-side scale colorbars
      "<circle cx=\"75\" cy=\"65\" r=\"12\" fill=\"#0284c7\"/><circle cx=\"115\" cy=\"65\" r=\"12\" fill=\"#38bdf8\"/>"
      <> "<rect x=\"150\" y=\"53\" width=\"24\" height=\"24\" fill=\"#10b981\"/><rect x=\"180\" y=\"53\" width=\"24\" height=\"24\" fill=\"#34d399\"/>"
      <> "<text x=\"80\" y=\"92\" fill=\"#38bdf8\" font-size=\"7\" font-family=\"monospace\">Scale 1 (Fill)</text>"
      <> "<text x=\"155\" y=\"92\" fill=\"#34d399\" font-size=\"7\" font-family=\"monospace\">Scale 2 (Color)</text>"

    "ggfx" ->
      // Outer glow and neon shader effect
      "<circle cx=\"150\" cy=\"65\" r=\"18\" fill=\"#38bdf8\" fill-opacity=\"0.1\" stroke=\"#38bdf8\" stroke-width=\"6\" stroke-opacity=\"0.3\"/>"
      <> "<circle cx=\"150\" cy=\"65\" r=\"18\" fill=\"#38bdf8\" fill-opacity=\"0.3\" stroke=\"#38bdf8\" stroke-width=\"3\" stroke-opacity=\"0.6\"/>"
      <> "<circle cx=\"150\" cy=\"65\" r=\"18\" fill=\"#0284c7\" stroke=\"#ffffff\" stroke-width=\"1.5\"/>"
      <> "<text x=\"125\" y=\"68\" fill=\"#ffffff\" font-size=\"8\" font-weight=\"bold\">Glow</text>"

    "gginnards" ->
      // AST layer tree inspector
      "<rect x=\"45\" y=\"38\" width=\"65\" height=\"18\" rx=\"2\" fill=\"#1e293b\" stroke=\"#38bdf8\" stroke-width=\"1\"/>"
      <> "<text x=\"50\" y=\"50\" fill=\"#38bdf8\" font-size=\"7\" font-family=\"monospace\">Layer 1: Geom</text>"
      <> "<rect x=\"125\" y=\"38\" width=\"65\" height=\"18\" rx=\"2\" fill=\"#1e293b\" stroke=\"#34d399\" stroke-width=\"1\"/>"
      <> "<text x=\"130\" y=\"50\" fill=\"#34d399\" font-size=\"7\" font-family=\"monospace\">Layer 2: Stat</text>"
      <> "<rect x=\"205\" y=\"38\" width=\"65\" height=\"18\" rx=\"2\" fill=\"#1e293b\" stroke=\"#fbbf24\" stroke-width=\"1\"/>"
      <> "<text x=\"210\" y=\"50\" fill=\"#fbbf24\" font-size=\"7\" font-family=\"monospace\">Layer 3: Coord</text>"
      <> "<line x1=\"77\" y1=\"56\" x2=\"157\" y2=\"75\" stroke=\"#64748b\" stroke-width=\"1\"/>"
      <> "<rect x=\"125\" y=\"75\" width=\"65\" height=\"18\" rx=\"2\" fill=\"#0f172a\" stroke=\"#cbd5e1\" stroke-width=\"1\"/>"
      <> "<text x=\"132\" y=\"87\" fill=\"#cbd5e1\" font-size=\"7\" font-family=\"monospace\">Root ggproto</text>"

    "ggQC" | "xmrr" ->
      // Statistical process control chart
      "<line x1=\"40\" y1=\"45\" x2=\"270\" y2=\"45\" stroke=\"#f43f5e\" stroke-width=\"1.5\" stroke-dasharray=\"3,3\"/>"
      <> "<text x=\"272\" y=\"48\" fill=\"#f43f5e\" font-size=\"7\" font-family=\"monospace\">UCL</text>"
      <> "<line x1=\"40\" y1=\"68\" x2=\"270\" y2=\"68\" stroke=\"#34d399\" stroke-width=\"1.5\"/>"
      <> "<text x=\"272\" y=\"71\" fill=\"#34d399\" font-size=\"7\" font-family=\"monospace\">CL</text>"
      <> "<line x1=\"40\" y1=\"90\" x2=\"270\" y2=\"90\" stroke=\"#f43f5e\" stroke-width=\"1.5\" stroke-dasharray=\"3,3\"/>"
      <> "<text x=\"272\" y=\"93\" fill=\"#f43f5e\" font-size=\"7\" font-family=\"monospace\">LCL</text>"
      <> "<polyline points=\"50,68 80,60 110,72 140,55 170,40 200,65 230,70\" fill=\"none\" stroke=\"#38bdf8\" stroke-width=\"1.5\"/>"
      <> "<circle cx=\"170\" cy=\"40\" r=\"4\" fill=\"#f43f5e\" stroke=\"#ffffff\" stroke-width=\"1\"/>"

    "cowplot" ->
      // Figure layout with A and B tags
      "<rect x=\"40\" y=\"35\" width=\"110\" height=\"60\" rx=\"2\" fill=\"#0b132b\" stroke=\"#1e293b\" stroke-width=\"1\"/>"
      <> "<text x=\"45\" y=\"48\" fill=\"#ffffff\" font-size=\"10\" font-weight=\"bold\">A</text>"
      <> "<circle cx=\"95\" cy=\"65\" r=\"14\" fill=\"#38bdf8\" fill-opacity=\"0.4\" stroke=\"#38bdf8\" stroke-width=\"1.5\"/>"
      <> "<rect x=\"160\" y=\"35\" width=\"110\" height=\"60\" rx=\"2\" fill=\"#0b132b\" stroke=\"#1e293b\" stroke-width=\"1\"/>"
      <> "<text x=\"165\" y=\"48\" fill=\"#ffffff\" font-size=\"10\" font-weight=\"bold\">B</text>"
      <> "<path d=\"M 175 80 L 205 50 L 235 65 L 255 45\" fill=\"none\" stroke=\"#34d399\" stroke-width=\"2\"/>"

    "plotROC" ->
      // Empirical ROC curve with 45 degree chance line and AUC shading
      "<line x1=\"50\" y1=\"95\" x2=\"250\" y2=\"95\" stroke=\"#334155\" stroke-width=\"1\"/>"
      <> "<line x1=\"50\" y1=\"35\" x2=\"50\" y2=\"95\" stroke=\"#334155\" stroke-width=\"1\"/>"
      <> "<line x1=\"50\" y1=\"95\" x2=\"250\" y2=\"35\" stroke=\"#64748b\" stroke-width=\"1\" stroke-dasharray=\"3,3\"/>"
      <> "<path d=\"M 50 95 L 65 70 L 90 55 L 130 42 L 180 38 L 250 35 L 250 95 Z\" fill=\"#38bdf8\" fill-opacity=\"0.2\"/>"
      <> "<path d=\"M 50 95 L 65 70 L 90 55 L 130 42 L 180 38 L 250 35\" fill=\"none\" stroke=\"#38bdf8\" stroke-width=\"2\"/>"
      <> "<text x=\"120\" y=\"75\" fill=\"#38bdf8\" font-size=\"8\" font-family=\"monospace\">AUC = 0.89</text>"

    "ggbump" ->
      // Sigmoid ranking lines
      "<path d=\"M 50 40 C 90 40, 110 85, 150 85 C 190 85, 210 55, 250 55\" fill=\"none\" stroke=\"#38bdf8\" stroke-width=\"2.5\"/>"
      <> "<path d=\"M 50 65 C 90 65, 110 40, 150 40 C 190 40, 210 85, 250 85\" fill=\"none\" stroke=\"#f43f5e\" stroke-width=\"2.5\"/>"
      <> "<path d=\"M 50 85 C 90 85, 110 65, 150 65 C 190 65, 210 40, 250 40\" fill=\"none\" stroke=\"#34d399\" stroke-width=\"2.5\"/>"
      <> "<circle cx=\"50\" cy=\"40\" r=\"3\" fill=\"#ffffff\"/><circle cx=\"150\" cy=\"85\" r=\"3\" fill=\"#ffffff\"/><circle cx=\"250\" cy=\"55\" r=\"3\" fill=\"#ffffff\"/>"

    _ ->
      // Distinct Category Geometric Rendering
      case ext.category {
        UncertaintyDistribution ->
          "<path d=\"M 40 90 Q 90 90, 130 55 Q 160 30, 180 30 Q 200 30, 230 55 Q 270 90, 290 90 Z\" fill=\"#38bdf8\" fill-opacity=\"0.35\" stroke=\"#38bdf8\" stroke-width=\"1.5\"/>"
          <> "<line x1=\"60\" y1=\"90\" x2=\"270\" y2=\"90\" stroke=\"#94a3b8\" stroke-width=\"1.5\"/>"
          <> "<line x1=\"100\" y1=\"90\" x2=\"240\" y2=\"90\" stroke=\"#38bdf8\" stroke-width=\"3\" stroke-linecap=\"round\"/>"
          <> "<line x1=\"140\" y1=\"90\" x2=\"210\" y2=\"90\" stroke=\"#0284c7\" stroke-width=\"5\" stroke-linecap=\"round\"/>"
          <> "<circle cx=\"175\" cy=\"90\" r=\"3.5\" fill=\"#ffffff\"/>"

        NetworkGraphTopology ->
          "<path d=\"M 70 50 Q 120 70, 160 65\" stroke=\"#475569\" stroke-width=\"1.5\" fill=\"none\"/>"
          <> "<path d=\"M 70 90 Q 120 75, 160 65\" stroke=\"#475569\" stroke-width=\"1.5\" fill=\"none\"/>"
          <> "<path d=\"M 160 65 Q 210 50, 250 45\" stroke=\"#475569\" stroke-width=\"1.5\" fill=\"none\"/>"
          <> "<path d=\"M 160 65 Q 210 85, 250 95\" stroke=\"#475569\" stroke-width=\"1.5\" fill=\"none\"/>"
          <> "<circle cx=\"70\" cy=\"50\" r=\"8\" fill=\"#818cf8\"/><circle cx=\"70\" cy=\"90\" r=\"8\" fill=\"#818cf8\"/>"
          <> "<circle cx=\"160\" cy=\"65\" r=\"12\" fill=\"#38bdf8\" stroke=\"#ffffff\" stroke-width=\"1.5\"/>"
          <> "<circle cx=\"250\" cy=\"45\" r=\"7\" fill=\"#34d399\"/><circle cx=\"250\" cy=\"95\" r=\"9\" fill=\"#fbbf24\"/>"

        FlowAlluvialSankey ->
          "<rect x=\"40\" y=\"35\" width=\"15\" height=\"65\" rx=\"2\" fill=\"#38bdf8\"/>"
          <> "<rect x=\"150\" y=\"35\" width=\"15\" height=\"45\" rx=\"2\" fill=\"#34d399\"/>"
          <> "<rect x=\"150\" y=\"85\" width=\"15\" height=\"15\" rx=\"2\" fill=\"#f87171\"/>"
          <> "<rect x=\"260\" y=\"35\" width=\"15\" height=\"45\" rx=\"2\" fill=\"#4ade80\"/>"
          <> "<path d=\"M 55 35 C 100 35, 105 35, 150 35 L 150 80 C 105 80, 100 80, 55 80 Z\" fill=\"#38bdf8\" fill-opacity=\"0.35\"/>"
          <> "<path d=\"M 55 80 C 100 80, 105 85, 150 85 L 150 100 C 105 100, 100 100, 55 100 Z\" fill=\"#f87171\" fill-opacity=\"0.35\"/>"
          <> "<path d=\"M 165 35 C 210 35, 215 35, 260 35 L 260 80 C 215 80, 210 80, 165 80 Z\" fill=\"#34d399\" fill-opacity=\"0.35\"/>"

        HierarchicalPartition ->
          "<rect x=\"40\" y=\"35\" width=\"120\" height=\"65\" rx=\"2\" fill=\"#38bdf8\" fill-opacity=\"0.2\" stroke=\"#38bdf8\" stroke-width=\"1\"/>"
          <> "<text x=\"50\" y=\"55\" fill=\"#38bdf8\" font-size=\"10\" font-family=\"monospace\">Apps (48%)</text>"
          <> "<rect x=\"165\" y=\"35\" width=\"75\" height=\"65\" rx=\"2\" fill=\"#818cf8\" fill-opacity=\"0.2\" stroke=\"#818cf8\" stroke-width=\"1\"/>"
          <> "<text x=\"175\" y=\"55\" fill=\"#818cf8\" font-size=\"10\" font-family=\"monospace\">Engines</text>"
          <> "<rect x=\"245\" y=\"35\" width=\"45\" height=\"65\" rx=\"2\" fill=\"#34d399\" fill-opacity=\"0.2\" stroke=\"#34d399\" stroke-width=\"1\"/>"
          <> "<text x=\"250\" y=\"55\" fill=\"#34d399\" font-size=\"9\" font-family=\"monospace\">Svc</text>"

        SpatialVectorField ->
          "<line x1=\"60\" y1=\"50\" x2=\"95\" y2=\"45\" stroke=\"#38bdf8\" stroke-width=\"1.5\" marker-end=\"url(#arr)\"/>"
          <> "<line x1=\"110\" y1=\"50\" x2=\"145\" y2=\"55\" stroke=\"#38bdf8\" stroke-width=\"1.5\"/>"
          <> "<line x1=\"160\" y1=\"50\" x2=\"195\" y2=\"70\" stroke=\"#34d399\" stroke-width=\"2\"/>"
          <> "<line x1=\"60\" y1=\"80\" x2=\"95\" y2=\"80\" stroke=\"#38bdf8\" stroke-width=\"1.5\"/>"
          <> "<line x1=\"110\" y1=\"80\" x2=\"145\" y2=\"75\" stroke=\"#34d399\" stroke-width=\"2\"/>"
          <> "<line x1=\"160\" y1=\"80\" x2=\"200\" y2=\"90\" stroke=\"#f59e0b\" stroke-width=\"2.5\"/>"
          <> "<circle cx=\"230\" cy=\"65\" r=\"12\" fill=\"#f59e0b\" fill-opacity=\"0.3\" stroke=\"#f59e0b\" stroke-width=\"1\"/>"

        QualityControlTimeSeries ->
          "<line x1=\"45\" y1=\"45\" x2=\"265\" y2=\"45\" stroke=\"#f87171\" stroke-width=\"1.5\" stroke-dasharray=\"3,3\"/>"
          <> "<line x1=\"45\" y1=\"68\" x2=\"265\" y2=\"68\" stroke=\"#34d399\" stroke-width=\"1.5\"/>"
          <> "<line x1=\"45\" y1=\"90\" x2=\"265\" y2=\"90\" stroke=\"#f87171\" stroke-width=\"1.5\" stroke-dasharray=\"3,3\"/>"
          <> "<polyline points=\"55,68 85,62 115,75 145,55 175,42 205,65 235,68 255,70\" fill=\"none\" stroke=\"#38bdf8\" stroke-width=\"1.8\"/>"
          <> "<circle cx=\"175\" cy=\"42\" r=\"3.5\" fill=\"#f87171\" stroke=\"#ffffff\" stroke-width=\"1\"/>"

        BioinformaticsGenomics ->
          "<line x1=\"40\" y1=\"95\" x2=\"280\" y2=\"95\" stroke=\"#334155\" stroke-width=\"1\"/>"
          <> "<line x1=\"40\" y1=\"45\" x2=\"280\" y2=\"45\" stroke=\"#ef4444\" stroke-width=\"1\" stroke-dasharray=\"2,2\"/>"
          <> "<circle cx=\"65\" cy=\"82\" r=\"2\" fill=\"#38bdf8\"/><circle cx=\"80\" cy=\"75\" r=\"2\" fill=\"#38bdf8\"/><circle cx=\"95\" cy=\"60\" r=\"2\" fill=\"#38bdf8\"/>"
          <> "<circle cx=\"145\" cy=\"78\" r=\"2\" fill=\"#818cf8\"/><circle cx=\"160\" cy=\"35\" r=\"3.5\" fill=\"#ef4444\" stroke=\"#ffffff\" stroke-width=\"1\"/>"
          <> "<circle cx=\"175\" cy=\"85\" r=\"2\" fill=\"#818cf8\"/>"
          <> "<circle cx=\"220\" cy=\"72\" r=\"2\" fill=\"#34d399\"/><circle cx=\"240\" cy=\"50\" r=\"2.5\" fill=\"#34d399\"/>"

        TypographyTextRepel ->
          "<circle cx=\"75\" cy=\"80\" r=\"3.5\" fill=\"#38bdf8\"/>"
          <> "<circle cx=\"140\" cy=\"55\" r=\"3.5\" fill=\"#34d399\"/>"
          <> "<circle cx=\"220\" cy=\"75\" r=\"3.5\" fill=\"#fbbf24\"/>"
          <> "<line x1=\"75\" y1=\"80\" x2=\"100\" y2=\"50\" stroke=\"#64748b\" stroke-width=\"1\" stroke-dasharray=\"2,2\"/>"
          <> "<text x=\"105\" y=\"52\" fill=\"#f8fafc\" font-size=\"9\" font-family=\"monospace\">Cluster_Alpha</text>"
          <> "<line x1=\"140\" y1=\"55\" x2=\"170\" y2=\"35\" stroke=\"#64748b\" stroke-width=\"1\" stroke-dasharray=\"2,2\"/>"
          <> "<text x=\"175\" y=\"37\" fill=\"#f8fafc\" font-size=\"9\" font-family=\"monospace\">Peak_Beta</text>"

        MultiScaleCoordinate ->
          "<circle cx=\"150\" cy=\"65\" r=\"35\" fill=\"none\" stroke=\"#334155\" stroke-width=\"1\"/>"
          <> "<circle cx=\"150\" cy=\"65\" r=\"20\" fill=\"none\" stroke=\"#334155\" stroke-width=\"1\" stroke-dasharray=\"2,2\"/>"
          <> "<line x1=\"150\" y1=\"25\" x2=\"150\" y2=\"105\" stroke=\"#334155\" stroke-width=\"1\"/>"
          <> "<line x1=\"110\" y1=\"65\" x2=\"190\" y2=\"65\" stroke=\"#334155\" stroke-width=\"1\"/>"
          <> "<polygon points=\"150,40 175,60 160,85 135,75 140,55\" fill=\"#38bdf8\" fill-opacity=\"0.35\" stroke=\"#38bdf8\" stroke-width=\"1.5\"/>"

        CompositeMultiPanel ->
          "<rect x=\"45\" y=\"35\" width=\"100\" height=\"30\" rx=\"2\" fill=\"#0f172a\" stroke=\"#38bdf8\" stroke-width=\"1\"/>"
          <> "<text x=\"52\" y=\"46\" fill=\"#38bdf8\" font-size=\"8\">Panel 1</text>"
          <> "<rect x=\"155\" y=\"35\" width=\"110\" height=\"30\" rx=\"2\" fill=\"#0f172a\" stroke=\"#34d399\" stroke-width=\"1\"/>"
          <> "<text x=\"162\" y=\"46\" fill=\"#34d399\" font-size=\"8\">Panel 2</text>"
          <> "<rect x=\"45\" y=\"70\" width=\"220\" height=\"30\" rx=\"2\" fill=\"#0f172a\" stroke=\"#fbbf24\" stroke-width=\"1\"/>"
          <> "<text x=\"52\" y=\"82\" fill=\"#fbbf24\" font-size=\"8\">Panel 3 (Composite)</text>"

        ThreeDimensionalProjection ->
          "<polygon points=\"80,40 180,30 240,50 140,60\" fill=\"#1e293b\" stroke=\"#38bdf8\" stroke-width=\"1\"/>"
          <> "<polygon points=\"80,40 140,60 140,95 80,75\" fill=\"#0f172a\" stroke=\"#38bdf8\" stroke-width=\"1\"/>"
          <> "<polygon points=\"140,60 240,50 240,85 140,95\" fill=\"#0b132b\" stroke=\"#38bdf8\" stroke-width=\"1\"/>"
          <> "<line x1=\"140\" y1=\"60\" x2=\"170\" y2=\"40\" stroke=\"#34d399\" stroke-width=\"2\"/>"

        StatisticalDiagnosisInference ->
          "<circle cx=\"65\" cy=\"80\" r=\"3\" fill=\"#38bdf8\"/><circle cx=\"95\" cy=\"72\" r=\"3\" fill=\"#38bdf8\"/><circle cx=\"135\" cy=\"60\" r=\"3\" fill=\"#38bdf8\"/><circle cx=\"175\" cy=\"55\" r=\"3\" fill=\"#38bdf8\"/><circle cx=\"215\" cy=\"48\" r=\"3\" fill=\"#38bdf8\"/><circle cx=\"255\" cy=\"42\" r=\"3\" fill=\"#38bdf8\"/>"
          <> "<line x1=\"55\" y1=\"85\" x2=\"265\" y2=\"40\" stroke=\"#38bdf8\" stroke-width=\"1.8\"/>"
          <> "<path d=\"M 140 38 L 140 33 L 220 33 L 220 38\" stroke=\"#34d399\" stroke-width=\"1\" fill=\"none\"/>"
          <> "<text x=\"165\" y=\"30\" fill=\"#34d399\" font-size=\"8\" font-family=\"monospace\">p=0.002</text>"

        PatternFilterShader ->
          "<defs><pattern id=\"patStripe\" width=\"8\" height=\"8\" patternTransform=\"rotate(45 0 0)\" patternUnits=\"userSpaceOnUse\"><line x1=\"0\" y1=\"0\" x2=\"0\" y2=\"8\" stroke=\"#38bdf8\" stroke-width=\"2\"/></pattern></defs>"
          <> "<rect x=\"55\" y=\"45\" width=\"45\" height=\"50\" fill=\"url(#patStripe)\" stroke=\"#38bdf8\" stroke-width=\"1\"/>"
          <> "<rect x=\"115\" y=\"35\" width=\"45\" height=\"60\" fill=\"#818cf8\" fill-opacity=\"0.3\" stroke=\"#818cf8\" stroke-width=\"1.5\"/>"
          <> "<rect x=\"175\" y=\"55\" width=\"45\" height=\"40\" fill=\"url(#patStripe)\" stroke=\"#34d399\" stroke-width=\"1\"/>"
          <> "<rect x=\"235\" y=\"40\" width=\"45\" height=\"55\" fill=\"#f59e0b\" fill-opacity=\"0.3\" stroke=\"#f59e0b\" stroke-width=\"1.5\"/>"

        DimensionalityReduction ->
          "<line x1=\"160\" y1=\"40\" x2=\"160\" y2=\"95\" stroke=\"#1e293b\" stroke-width=\"1\"/>"
          <> "<line x1=\"50\" y1=\"68\" x2=\"270\" y2=\"68\" stroke=\"#1e293b\" stroke-width=\"1\"/>"
          <> "<circle cx=\"110\" cy=\"55\" r=\"3\" fill=\"#38bdf8\"/><circle cx=\"125\" cy=\"62\" r=\"3\" fill=\"#38bdf8\"/><circle cx=\"100\" cy=\"65\" r=\"3\" fill=\"#38bdf8\"/>"
          <> "<circle cx=\"210\" cy=\"75\" r=\"3\" fill=\"#f43f5e\"/><circle cx=\"225\" cy=\"82\" r=\"3\" fill=\"#f43f5e\"/><circle cx=\"235\" cy=\"70\" r=\"3\" fill=\"#f43f5e\"/>"
          <> "<line x1=\"160\" y1=\"68\" x2=\"195\" y2=\"50\" stroke=\"#34d399\" stroke-width=\"1.8\"/>"
          <> "<text x=\"200\" y=\"50\" fill=\"#34d399\" font-size=\"8\" font-family=\"monospace\">PC1 (68%)</text>"

        ThemingPaletteAesthetic ->
          "<rect x=\"45\" y=\"45\" width=\"32\" height=\"40\" rx=\"2\" fill=\"#440154\"/>"
          <> "<rect x=\"82\" y=\"45\" width=\"32\" height=\"40\" rx=\"2\" fill=\"#414487\"/>"
          <> "<rect x=\"119\" y=\"45\" width=\"32\" height=\"40\" rx=\"2\" fill=\"#2a788e\"/>"
          <> "<rect x=\"156\" y=\"45\" width=\"32\" height=\"40\" rx=\"2\" fill=\"#22a884\"/>"
          <> "<rect x=\"193\" y=\"45\" width=\"32\" height=\"40\" rx=\"2\" fill=\"#7ad151\"/>"
          <> "<rect x=\"230\" y=\"45\" width=\"32\" height=\"40\" rx=\"2\" fill=\"#fde725\"/>"
          <> "<text x=\"45\" y=\"98\" fill=\"#94a3b8\" font-size=\"8\" font-family=\"monospace\">Scale: " <> ext.name <> "</text>"

        IntrospectionLayerEditing ->
          "<polyline points=\"45,85 85,82 125,84 165,80 205,82 245,80 275,81\" fill=\"none\" stroke=\"#334155\" stroke-width=\"1\"/>"
          <> "<polyline points=\"45,72 85,74 125,70 165,72 205,71 245,70 275,73\" fill=\"none\" stroke=\"#334155\" stroke-width=\"1\"/>"
          <> "<polyline points=\"45,65 85,58 125,48 165,38 205,42 245,35 275,32\" fill=\"none\" stroke=\"#38bdf8\" stroke-width=\"2.5\"/>"
          <> "<circle cx=\"245\" cy=\"35\" r=\"4\" fill=\"#38bdf8\" stroke=\"#ffffff\" stroke-width=\"1\"/>"
          <> "<text x=\"210\" y=\"26\" fill=\"#38bdf8\" font-size=\"8\" font-family=\"monospace\">Focal Trace</text>"
      }
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
