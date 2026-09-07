//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/lustre/mesh_topology_view</module>
////     <fsharp-lineage>N/A — Pure Lustre Multi-Host SVG Topology Visualizer</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L6_ECOSYSTEM</layer>
////     <layer>L7_FEDERATION</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-TAILSCALE-WEB-001, SC-CHECKLIST-001, SC-GLM-UI-001, SC-MUDA-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/float
import gleam/int
import gleam/list

const tailscale_base_url = "http://nas-1.tail55d152.ts.net:4100"
const peer_base_url = "http://vm-1.tail55d152.ts.net:8088"

/// Topology node descriptor.
pub type TopologyNode {
  TopologyNode(
    node_id: String,
    tailscale_ip: String,
    port: Int,
    tailscale_fqdn: String,
    health_score: Float,
    active_workers: Int,
    queue_depth: Int,
    lyapunov_exponent: Float,
    is_local: Bool,
  )
}

/// Model for the mesh topology view.
pub type TopologyViewModel {
  TopologyViewModel(
    nodes: List(TopologyNode),
    inter_node_latency_ms: Float,
    total_gossip_rounds: Int,
    total_stolen_tasks: Int,
  )
}

/// Initialize the default multi-host topology model (nas-1 + vm-1).
pub fn init_topology_view() -> TopologyViewModel {
  let nas =
    TopologyNode(
      node_id: "nas-1",
      tailscale_ip: "100.87.7.78",
      port: 4100,
      tailscale_fqdn: "http://nas-1.tail55d152.ts.net:4100",
      health_score: 0.98,
      active_workers: 4,
      queue_depth: 2,
      lyapunov_exponent: -3.4,
      is_local: True,
    )
  let vm =
    TopologyNode(
      node_id: "vm-1",
      tailscale_ip: "100.78.98.18",
      port: 8088,
      tailscale_fqdn: "http://vm-1.tail55d152.ts.net:8088",
      health_score: 0.95,
      active_workers: 2,
      queue_depth: 1,
      lyapunov_exponent: -2.8,
      is_local: False,
    )
  TopologyViewModel(
    nodes: [nas, vm],
    inter_node_latency_ms: 4.2,
    total_gossip_rounds: 128,
    total_stolen_tasks: 14,
  )
}

/// Update or insert a node in the topology model.
pub fn update_topology_node(
  model: TopologyViewModel,
  node: TopologyNode,
) -> TopologyViewModel {
  let filtered = list.filter(model.nodes, fn(n) { n.node_id != node.node_id })
  TopologyViewModel(..model, nodes: [node, ..filtered])
}

/// Render the pure SVG multi-host mesh topology graph string.
pub fn render_topology_svg(model: TopologyViewModel) -> String {
  "<svg width=\"100%\" height=\"260\" viewBox=\"0 0 700 260\" style=\"background:rgba(10, 15, 29, 0.95);border-radius:8px;border:1px solid rgba(0, 240, 255, 0.2)\">"
  <> "<line x1=\"180\" y1=\"130\" x2=\"520\" y2=\"130\" stroke=\"#00F0FF\" stroke-width=\"3\" stroke-dasharray=\"6 4\" />"
  <> "<g>"
  <> "<rect x=\"300\" y=\"110\" width=\"100\" height=\"36\" rx=\"6\" fill=\"#050B14\" stroke=\"#00F0FF\" stroke-width=\"1\" />"
  <> "<text x=\"350\" y=\"132\" text-anchor=\"middle\" fill=\"#00F0FF\" font-size=\"12\" font-family=\"monospace\">RTT "
  <> float.to_string(model.inter_node_latency_ms)
  <> "ms</text>"
  <> "</g>"
  <> "<g>"
  <> "<circle cx=\"180\" cy=\"130\" r=\"50\" fill=\"rgba(0, 240, 255, 0.15)\" stroke=\"#00F0FF\" stroke-width=\"2\" />"
  <> "<text x=\"180\" y=\"125\" text-anchor=\"middle\" fill=\"#FFFFFF\" font-size=\"14\" font-weight=\"bold\" font-family=\"monospace\">nas-1 (Local)</text>"
  <> "<text x=\"180\" y=\"145\" text-anchor=\"middle\" fill=\"#70A0FF\" font-size=\"11\" font-family=\"monospace\">:4100 [SIL-6]</text>"
  <> "</g>"
  <> "<g>"
  <> "<circle cx=\"520\" cy=\"130\" r=\"50\" fill=\"rgba(112, 160, 255, 0.15)\" stroke=\"#70A0FF\" stroke-width=\"2\" />"
  <> "<text x=\"520\" y=\"125\" text-anchor=\"middle\" fill=\"#FFFFFF\" font-size=\"14\" font-weight=\"bold\" font-family=\"monospace\">vm-1 (Peer)</text>"
  <> "<text x=\"520\" y=\"145\" text-anchor=\"middle\" fill=\"#70A0FF\" font-size=\"11\" font-family=\"monospace\">:8088 [Online]</text>"
  <> "</g>"
  <> "</svg>"
}

/// Render the complete Mesh Topology View page.
pub fn render_topology_page(model: TopologyViewModel) -> String {
  "<div class=\"topology-container\" style=\"padding:20px;color:#E0E5F0;font-family:system-ui,sans-serif;background:#0A0E17\">"
  <> "<header style=\"border-bottom:1px solid #1E2A3A;padding-bottom:1rem;margin-bottom:1.5rem\">"
  <> "<div style=\"display:flex;justify-content:space-between;align-items:center\">"
  <> "<h1 style=\"color:#00F0FF;margin:0;font-size:1.8rem\">UOS Federated Mesh Topology Visualizer (EV-99)</h1>"
  <> "<div style=\"display:flex;gap:0.5rem\">"
  <> "<span style=\"background:#00F0FF22;color:#00F0FF;border:1px solid #00F0FF;padding:0.25rem 0.5rem;border-radius:4px;font-size:0.8rem;font-weight:bold\">SIL-6 MESH</span>"
  <> "<span style=\"background:#4A90E222;color:#4A90E2;border:1px solid #4A90E2;padding:0.25rem 0.5rem;border-radius:4px;font-size:0.8rem;font-weight:bold\">WORK-STEALING</span>"
  <> "<span style=\"background:#50E3C222;color:#50E3C2;border:1px solid #50E3C2;padding:0.25rem 0.5rem;border-radius:4px;font-size:0.8rem;font-weight:bold\">LOCK: 25503L801736</span>"
  <> "</div></div>"
  <> "<p style=\"color:#8B9BB4;margin-top:0.5rem\">Real-time Tailscale cluster interconnect, CRDT delta synchronization, and decentralized work-stealing swarm telemetry.</p>"
  <> "<p style=\"font-size:0.85rem\"><strong>Local Node:</strong> <a href=\""
  <> tailscale_base_url
  <> "\" style=\"color:#00F0FF\">"
  <> tailscale_base_url
  <> "</a> &middot; <strong>Peer Host:</strong> <a href=\""
  <> peer_base_url
  <> "\" style=\"color:#4A90E2\">"
  <> peer_base_url
  <> "</a></p>"
  <> "</header>"
  <> render_topology_svg(model)
  <> "<h3 style=\"margin-top:24px;color:#70A0FF\">Cluster Nodes Status & Work-Stealing Metrics</h3>"
  <> "<table style=\"width:100%;border-collapse:collapse;margin-top:12px\">"
  <> "<thead><tr style=\"border-bottom:1px solid rgba(255,255,255,0.1)\">"
  <> "<th style=\"text-align:left;padding:8px\">Node ID</th>"
  <> "<th style=\"text-align:left;padding:8px\">Tailscale FQDN</th>"
  <> "<th style=\"text-align:right;padding:8px\">Health</th>"
  <> "<th style=\"text-align:right;padding:8px\">Workers</th>"
  <> "<th style=\"text-align:right;padding:8px\">Queue</th>"
  <> "<th style=\"text-align:right;padding:8px\">Lyapunov &lambda;(t)</th>"
  <> "</tr></thead><tbody>"
  <> render_node_rows(model.nodes)
  <> "</tbody></table>"
  <> "</div>"
}

fn render_node_rows(nodes: List(TopologyNode)) -> String {
  list.fold(nodes, "", fn(acc, n) {
    acc
    <> "<tr style=\"border-bottom:1px solid rgba(255,255,255,0.05)\">"
    <> "<td style=\"padding:8px;font-weight:bold\">"
    <> n.node_id
    <> "</td>"
    <> "<td style=\"padding:8px\"><a href=\""
    <> n.tailscale_fqdn
    <> "\" style=\"color:#00F0FF;text-decoration:none\">"
    <> n.tailscale_fqdn
    <> "</a></td>"
    <> "<td style=\"padding:8px;text-align:right\"><span style=\"padding:2px 6px;border-radius:4px;background:rgba(0,255,128,0.15);color:#00FF80\">"
    <> float.to_string(n.health_score)
    <> "</span></td>"
    <> "<td style=\"padding:8px;text-align:right\">"
    <> int.to_string(n.active_workers)
    <> "</td>"
    <> "<td style=\"padding:8px;text-align:right\">"
    <> int.to_string(n.queue_depth)
    <> "</td>"
    <> "<td style=\"padding:8px;text-align:right\">"
    <> float.to_string(n.lyapunov_exponent)
    <> "</td>"
    <> "</tr>"
  })
}
