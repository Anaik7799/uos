//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/lustre/tensor_fractal_atlas</module>
////     <lineage>EV-TENSOR-01 Multi-Dimensional Fractal Tensor Atlas</lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_TO_L9_FULL_SPECTRUM</layer>
////     <mesh-domain>13D TCM Vector Tensor Space & Fractal Navigation</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>
////       SC-GLM-UI-001, SC-FRACTAL-001, SC-CHECKLIST-001, SC-MUDA-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/float
import gleam/int
import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub type TensorLayerSpec {
  TensorLayerSpec(
    layer_id: String,
    name: String,
    authority: String,
    criticality: String,
    primary_route: String,
  )
}

pub type TensorAtlasModel {
  TensorAtlasModel(
    layers: List(TensorLayerSpec),
    delta_t13: Float,
    surfaces_count: Int,
    trust_score: Float,
  )
}

pub fn string_contains(source: String, sub: String) -> Bool {
  string.contains(source, sub)
}

pub fn layer_count(model: TensorAtlasModel) -> Int {
  list.length(model.layers)
}

pub fn build_canonical_atlas() -> TensorAtlasModel {
  let layers = [
    TensorLayerSpec(
      "L0",
      "L0_CONSTITUTIONAL",
      "Guardian & 2oo3",
      "DAL-A / SIL-6",
      "/checklist",
    ),
    TensorLayerSpec(
      "L1",
      "L1_ATOMIC_NIF",
      "Pure BEAM & Kernels",
      "DAL-A / SIL-5",
      "/api/health",
    ),
    TensorLayerSpec(
      "L2",
      "L2_COMPONENT_HEALTH",
      "Quorum & Badges",
      "DAL-B / SIL-4",
      "/features",
    ),
    TensorLayerSpec(
      "L3",
      "L3_TRANSACTION_DIFF",
      "RFC 6902 & Myers",
      "DAL-B / SIL-4",
      "/wiki-preview",
    ),
    TensorLayerSpec(
      "L4",
      "L4_SYSTEM_SUPERVISOR",
      "OTP 29 Root Supervisor",
      "DAL-A / SIL-5",
      "/verify-patrol",
    ),
    TensorLayerSpec(
      "L5",
      "L5_COGNITIVE_OODA",
      "Rocha Cut & Lyapunov",
      "DAL-B / SIL-4",
      "/biosemiotics",
    ),
    TensorLayerSpec(
      "L6",
      "L6_ECOSYSTEM_MESH",
      "A2A Mesh & Subagents",
      "DAL-C / SIL-3",
      "/ag-ui/events",
    ),
    TensorLayerSpec(
      "L7",
      "L7_FEDERATION_CRDT",
      "Version Vectors & Sync",
      "DAL-B / SIL-4",
      "/planning",
    ),
    TensorLayerSpec(
      "L8",
      "L8_PLANETARY_INFRA",
      "Kubernetes & Storage NVMe",
      "DAL-A / SIL-6",
      "/files/",
    ),
    TensorLayerSpec(
      "L9",
      "L9_TRANS_KNOWLEDGE",
      "ZK ADRs & Hermes Wiki",
      "DAL-A / SIL-6",
      "/zk-graph",
    ),
  ]

  TensorAtlasModel(
    layers: layers,
    delta_t13: 0.0,
    surfaces_count: 5,
    trust_score: 0.998,
  )
}

pub fn render_svg_tensor_matrix(model: TensorAtlasModel) -> String {
  let header =
    "<svg viewBox='0 0 800 400' class='tensor-matrix-svg' style='width:100%;max-width:800px;background:#0d1117;border:1px solid #30363d;border-radius:8px'>"
  let layer_boxes =
    list.index_map(model.layers, fn(layer, idx) {
      let y = int.to_string(30 + idx * 35)
      "<rect x='30' y='"
      <> y
      <> "' width='740' height='28' rx='4' fill='#161b22' stroke='#30363d' stroke-width='1'/>"
      <> "<text x='45' y='"
      <> int.to_string(30 + idx * 35 + 18)
      <> "' fill='#58a6ff' font-size='12' font-family='monospace' font-weight='bold'>"
      <> layer.name
      <> "</text>"
      <> "<text x='300' y='"
      <> int.to_string(30 + idx * 35 + 18)
      <> "' fill='#8b949e' font-size='11' font-family='monospace'>"
      <> layer.authority
      <> "</text>"
      <> "<text x='520' y='"
      <> int.to_string(30 + idx * 35 + 18)
      <> "' fill='#3fb950' font-size='11' font-family='monospace'>"
      <> layer.criticality
      <> "</text>"
      <> "<text x='670' y='"
      <> int.to_string(30 + idx * 35 + 18)
      <> "' fill='#ffc107' font-size='11' font-family='monospace'>"
      <> layer.primary_route
      <> "</text>"
    })
    |> string.join("\n")
  let footer = "</svg>"
  header <> "\n" <> layer_boxes <> "\n" <> footer
}

pub fn render_tensor_atlas_view(model: TensorAtlasModel) -> Element(msg) {
  html.div([attribute.class("tensor-atlas-container")], [
    html.h3([], [
      element.text("Multidimensional Fractal Tensor Atlas (L0 - L9)"),
    ]),
    html.div([attribute.class("badges-row")], [
      html.span([attribute.class("badge badge-fractal")], [
        element.text(
          "Layers: " <> int.to_string(layer_count(model)) <> " (L0 - L9)",
        ),
      ]),
      html.span([attribute.class("badge badge-tailscale")], [
        element.text(
          "Surfaces: "
          <> int.to_string(model.surfaces_count)
          <> " (Web, API, TUI, SSE, ZMOF)",
        ),
      ]),
      html.span([attribute.class("badge badge-muda")], [
        element.text(
          "Delta T_13 = " <> float.to_string(model.delta_t13) <> " (CONSERVED)",
        ),
      ]),
    ]),
  ])
}
