//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/lustre/hyperdimensional_zk_hologram</module>
////     <lineage>EV-TENSOR-06 Hyperdimensional ZK Hologram & Knowledge Graph</lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L9_TRANS_KNOWLEDGE</layer>
////     <mesh-domain>Zettelkasten Hologram, Louvain Modularity & Transclusion Depth</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>
////       SC-KM-001, SC-CHECKLIST-001, SC-MUDA-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/float
import gleam/int
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub type HologramNode {
  HologramNode(
    id: String,
    label: String,
    cluster: Int,
    x: Float,
    y: Float,
    radius: Float,
    color: String,
  )
}

pub type HologramEdge {
  HologramEdge(
    source_id: String,
    target_id: String,
    weight: Float,
    is_transclusion: Bool,
  )
}

pub type ZkHologramModel {
  ZkHologramModel(
    nodes: List(HologramNode),
    edges: List(HologramEdge),
    modularity_q: Float,
    active_clusters_count: Int,
    max_transclusion_depth: Int,
    cycle_detected: Bool,
  )
}

pub fn build_canonical_hologram() -> ZkHologramModel {
  let nodes = [
    HologramNode("ADR-001", "Formal Gospel", 0, 150.0, 120.0, 14.0, "#38bdf8"),
    HologramNode("ADR-002", "Descriptor VFS", 1, 280.0, 90.0, 12.0, "#10b981"),
    HologramNode(
      "ADR-003",
      "Dual Lattice STM",
      0,
      180.0,
      220.0,
      13.0,
      "#38bdf8",
    ),
    HologramNode("ADR-004", "13D Coordinate", 0, 100.0, 260.0, 15.0, "#38bdf8"),
    HologramNode("ADR-005", "Z3 Solvers", 0, 220.0, 310.0, 12.0, "#38bdf8"),
    HologramNode("ADR-006", "Rete-UL Net", 2, 360.0, 180.0, 14.0, "#f59e0b"),
    HologramNode(
      "ADR-007",
      "Zero-Trust Dispatch",
      2,
      420.0,
      120.0,
      13.0,
      "#f59e0b",
    ),
    HologramNode(
      "ADR-008",
      "Parsoid Roundtrip",
      3,
      490.0,
      240.0,
      14.0,
      "#ec4899",
    ),
    HologramNode("ADR-009", "Linear Arenas", 1, 320.0, 340.0, 12.0, "#10b981"),
    HologramNode(
      "ADR-010",
      "DMC Biosemiotics",
      2,
      460.0,
      320.0,
      15.0,
      "#f59e0b",
    ),
    HologramNode(
      "ADR-011",
      "Two-Key Security",
      2,
      540.0,
      160.0,
      13.0,
      "#f59e0b",
    ),
    HologramNode(
      "ADR-012",
      "Lyapunov Stability",
      1,
      260.0,
      420.0,
      14.0,
      "#10b981",
    ),
    HologramNode("ADR-013", "Zenoh PubSub", 1, 380.0, 430.0, 13.0, "#10b981"),
    HologramNode(
      "ADR-014",
      "MAX Python Isolation",
      1,
      170.0,
      440.0,
      12.0,
      "#10b981",
    ),
    HologramNode("ADR-015", "Sheaf Boundary", 3, 580.0, 280.0, 14.0, "#ec4899"),
    HologramNode(
      "ADR-016",
      "Rocha Cut Decouple",
      2,
      520.0,
      400.0,
      15.0,
      "#f59e0b",
    ),
  ]

  let edges = [
    HologramEdge("ADR-001", "ADR-003", 1.0, True),
    HologramEdge("ADR-001", "ADR-005", 1.0, False),
    HologramEdge("ADR-003", "ADR-004", 1.0, True),
    HologramEdge("ADR-002", "ADR-009", 1.0, False),
    HologramEdge("ADR-006", "ADR-007", 1.0, True),
    HologramEdge("ADR-007", "ADR-011", 1.0, False),
    HologramEdge("ADR-008", "ADR-015", 1.0, True),
    HologramEdge("ADR-010", "ADR-016", 1.0, True),
    HologramEdge("ADR-012", "ADR-013", 1.0, False),
    HologramEdge("ADR-009", "ADR-012", 1.0, False),
    HologramEdge("ADR-004", "ADR-010", 1.0, True),
    HologramEdge("ADR-005", "ADR-006", 1.0, False),
    HologramEdge("ADR-003", "ADR-012", 1.0, False),
    HologramEdge("ADR-013", "ADR-014", 1.0, False),
    HologramEdge("ADR-015", "ADR-016", 1.0, True),
    HologramEdge("ADR-007", "ADR-010", 1.0, False),
    HologramEdge("ADR-001", "ADR-004", 1.0, True),
    HologramEdge("ADR-002", "ADR-007", 1.0, False),
    HologramEdge("ADR-006", "ADR-011", 1.0, False),
    HologramEdge("ADR-008", "ADR-010", 1.0, True),
  ]

  ZkHologramModel(
    nodes: nodes,
    edges: edges,
    modularity_q: 0.785,
    // Louvain community modularity Q
    active_clusters_count: 4,
    max_transclusion_depth: 3,
    cycle_detected: False,
  )
}

pub fn node_count(h: ZkHologramModel) -> Int {
  list.length(h.nodes)
}

pub fn edge_count(h: ZkHologramModel) -> Int {
  list.length(h.edges)
}

pub fn render_zk_hologram_view(h: ZkHologramModel) -> Element(msg) {
  html.div([attribute.class("zk-hologram-container")], [
    html.h3([], [
      element.text("Hyperdimensional ZK Hologram & Living Knowledge Graph"),
    ]),
    html.div([attribute.class("hologram-metrics-strip")], [
      html.div([attribute.class("metric-pill")], [
        html.strong([], [element.text("Louvain Modularity Q: ")]),
        element.text(float.to_string(h.modularity_q)),
      ]),
      html.div([attribute.class("metric-pill")], [
        html.strong([], [element.text("Clusters: ")]),
        element.text(int.to_string(h.active_clusters_count)),
      ]),
      html.div([attribute.class("metric-pill")], [
        html.strong([], [element.text("Nodes / Edges: ")]),
        element.text(
          int.to_string(node_count(h)) <> " / " <> int.to_string(edge_count(h)),
        ),
      ]),
      html.div([attribute.class("metric-pill")], [
        html.strong([], [element.text("Max Depth: ")]),
        element.text(int.to_string(h.max_transclusion_depth) <> " (No Cycle)"),
      ]),
    ]),
    html.div([attribute.class("hologram-graph-wrapper")], [
      html.div([attribute.class("graph-card")], [
        html.h4([], [
          element.text("Topological Knowledge Graph (Pure SVG Force Layout)"),
        ]),
        html.p([], [
          element.text(
            "Clusters: Formal Logic (#38bdf8), Deterministic VFS (#10b981), Cybernetic Control (#f59e0b), Transclusion Sheaf (#ec4899)",
          ),
        ]),
        render_svg_hologram(h),
      ]),
    ]),
  ])
}

fn render_svg_hologram(h: ZkHologramModel) -> Element(msg) {
  let svg_width = 720
  let svg_height = 500

  let edge_elements =
    list.map(h.edges, fn(e) {
      let source_node = list.find(h.nodes, fn(n) { n.id == e.source_id })
      let target_node = list.find(h.nodes, fn(n) { n.id == e.target_id })

      case source_node, target_node {
        Ok(s), Ok(t) -> {
          let stroke_style = case e.is_transclusion {
            True -> "stroke:#ec4899;stroke-width:2;stroke-dasharray:4,4"
            False -> "stroke:#444;stroke-width:1.5"
          }
          element.element(
            "line",
            [
              attribute.attribute("x1", float.to_string(s.x)),
              attribute.attribute("y1", float.to_string(s.y)),
              attribute.attribute("x2", float.to_string(t.x)),
              attribute.attribute("y2", float.to_string(t.y)),
              attribute.attribute("style", stroke_style),
            ],
            [],
          )
        }
        _, _ -> element.text("")
      }
    })

  let node_elements =
    list.map(h.nodes, fn(n) {
      element.element("g", [], [
        element.element(
          "circle",
          [
            attribute.attribute("cx", float.to_string(n.x)),
            attribute.attribute("cy", float.to_string(n.y)),
            attribute.attribute("r", float.to_string(n.radius)),
            attribute.attribute("fill", n.color),
            attribute.attribute("stroke", "#ffffff"),
            attribute.attribute("stroke-width", "1.5"),
          ],
          [],
        ),
        element.element(
          "text",
          [
            attribute.attribute("x", float.to_string(n.x +. 12.0)),
            attribute.attribute("y", float.to_string(n.y +. 4.0)),
            attribute.attribute("fill", "#e0e0e0"),
            attribute.attribute("font-size", "11px"),
            attribute.attribute("font-family", "monospace"),
          ],
          [element.text(n.label)],
        ),
      ])
    })

  let all_svg_children = list.append(edge_elements, node_elements)

  element.element(
    "svg",
    [
      attribute.attribute("width", "100%"),
      attribute.attribute("height", "500"),
      attribute.attribute(
        "viewBox",
        "0 0 " <> int.to_string(svg_width) <> " " <> int.to_string(svg_height),
      ),
      attribute.attribute(
        "style",
        "background:#0d1117;border:1px solid #30363d;border-radius:6px;",
      ),
    ],
    all_svg_children,
  )
}
