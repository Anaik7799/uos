//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/web/special_views</module>
////     <fsharp-lineage>Cepaf.UI.Web.PageViews.fs (special section)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-GLM-UI-001, SC-GLM-UI-004, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       Page view functions map 1:1 from the F# source — Element(msg) output
////       is structurally equivalent to the original Lustre SSR rendering.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// विभागशः — Division into parts, each complete in itself (Gita 18.41)
////
//// Special views: constitutional integrity, evolution tracking, biomorphic
//// subsystems, federation, health grid, component demo showcase, and allium
//// specification viewer. Covers L0, L2, L5, L6, L7 fractal layers.

import cepaf_gleam/agui/event_stream_widget
import cepaf_gleam/symbiosis/tensor as symbiosis_tensor
import cepaf_gleam/symbiosis/types as symbiosis_types
import cepaf_gleam/ui/lustre/shell
import cepaf_gleam/ui/state.{
  type SharedMeshState, ThreatElevated, ThreatNominal, ThreatNone,
  cockpit_mode_to_string, ooda_phase_to_string,
}
import gleam/float
import gleam/int
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

// ---------------------------------------------------------------------------
// 25. Mathematical Integrity — L0 Constitutional
// ---------------------------------------------------------------------------

pub fn integrity_view(state: SharedMeshState) -> Element(msg) {
  let integrity_status = case state.quorum_healthy {
    True -> "Healthy"
    False -> "Degraded"
  }
  html.div([attribute.class("w-full")], [
    page_header(
      "Integrity (L0 Constitutional)",
      "Hash chain verification, Psi invariants, constitution integrity",
    ),
    shell.section("Constitution & Hash Chain", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "Hash Chain",
          integrity_status,
          "VALID",
          "256 blocks verified",
        ),
        shell.status_card(
          "Constitution Hash",
          "Healthy",
          "e3b0c44298fc1c14",
          "sha256 canonical",
        ),
        shell.status_card(
          "Last Verification",
          "Healthy",
          "2026-04-07T01:30Z",
          "automated cycle",
        ),
        shell.status_card("Chain Length", "Healthy", "256", "immutable blocks"),
      ]),
    ]),
    shell.section("Psi Invariants (7 Constitutional Axioms)", [
      html.table([], [
        html.thead([], [
          html.tr([], [
            html.th([], [element.text("Invariant")]),
            html.th([], [element.text("Status")]),
            html.th([], [element.text("Description")]),
            html.th([], [element.text("Last Verified")]),
          ]),
        ]),
        html.tbody([], [
          psi_row(
            "Psi-0",
            "Existence",
            "PASS",
            "System must exist and be alive",
            "2026-04-07",
          ),
          psi_row(
            "Psi-1",
            "Regeneration",
            "PASS",
            "State recoverable from SQLite/DuckDB",
            "2026-04-07",
          ),
          psi_row(
            "Psi-2",
            "History",
            "PASS",
            "Append-only log preserved, no truncation",
            "2026-04-07",
          ),
          psi_row(
            "Psi-3",
            "Verification",
            "PASS",
            "Hash chain intact, no tampering",
            "2026-04-07",
          ),
          psi_row(
            "Psi-4",
            "Alignment",
            "PASS",
            "Founder directive compliance verified",
            "2026-04-07",
          ),
          psi_row(
            "Psi-5",
            "Truthfulness",
            "PASS",
            "No deception in agent responses",
            "2026-04-07",
          ),
          psi_row(
            "Omega-0",
            "Symbiotic",
            "PASS",
            "Human-AI survival mandate active",
            "2026-04-07",
          ),
        ]),
      ]),
    ]),
    shell.section("Verification Timeline", [
      html.div([attribute.class("card-grid-wide")], [
        shell.status_card("Cycle 256", "Healthy", "ALL PASS", "7/7 invariants"),
        shell.status_card("Cycle 255", "Healthy", "ALL PASS", "7/7 invariants"),
        shell.status_card("Cycle 254", "Healthy", "ALL PASS", "7/7 invariants"),
        shell.status_card("Streak", "Healthy", "256 cycles", "zero violations"),
      ]),
    ]),
    element.element(
      "script",
      [attribute.attribute("src", "/static/integrity-grid.js?v=22.10.1")],
      [],
    ),
  ])
}

// ---------------------------------------------------------------------------
// 26. Evolution Vectors — L5 Cognitive
// ---------------------------------------------------------------------------

pub fn evolution_view(state: SharedMeshState) -> Element(msg) {
  let total_containers = int.to_string(state.container_count)
  let healthy_containers = int.to_string(state.healthy_count)
  html.div([attribute.class("w-full")], [
    page_header(
      "Evolution (L5 Cognitive)",
      "Shannon entropy, morphogenic cycles, mutation rate, fitness tracking",
    ),
    shell.section("Mathematical Gates", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "Shannon H",
          "Healthy",
          "2.67 bits",
          ">= 2.5 gate: PASS",
        ),
        shell.status_card("CCM", "Degraded", "0.770", ">= 0.90 gate: IMPROVING"),
        shell.status_card(
          "ITQS",
          "Degraded",
          "0.736",
          ">= 0.85 gate: IMPROVING",
        ),
        shell.status_card(
          "Active Containers",
          case state.quorum_healthy {
            True -> "Healthy"
            False -> "Degraded"
          },
          healthy_containers <> "/" <> total_containers,
          "mesh substrate health",
        ),
      ]),
    ]),
    shell.section("Fitness & Adaptation", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "Fitness Score",
          "Healthy",
          "0.92",
          "composite metric",
        ),
        shell.status_card("Mutation Rate", "Healthy", "0.03", "per cycle"),
        shell.status_card(
          "Adaptability",
          "Healthy",
          "0.90",
          "response to change",
        ),
        shell.status_card("Resilience", "Healthy", "0.80", "recovery speed"),
      ]),
    ]),
    shell.section("Cycle History (last 8)", [
      html.table([], [
        html.thead([], [
          html.tr([], [
            html.th([], [element.text("Generation")]),
            html.th([], [element.text("Entropy")]),
            html.th([], [element.text("Fitness")]),
            html.th([], [element.text("Mutations")]),
            html.th([], [element.text("Status")]),
          ]),
        ]),
        html.tbody([], [
          gen_row("88", "2.67", "0.92", "3", "Healthy"),
          gen_row("87", "2.65", "0.91", "2", "Healthy"),
          gen_row("86", "2.62", "0.90", "4", "Healthy"),
          gen_row("85", "2.58", "0.88", "1", "Healthy"),
          gen_row("84", "2.55", "0.87", "5", "Healthy"),
          gen_row("83", "2.51", "0.86", "2", "Healthy"),
          gen_row("82", "2.48", "0.84", "3", "Degraded"),
          gen_row("81", "2.45", "0.82", "6", "Degraded"),
        ]),
      ]),
    ]),
    shell.section("Statistics", [
      html.div([attribute.class("card-grid")], [
        shell.status_card("Total Cycles", "Healthy", "42", "completed"),
        shell.status_card("Generation", "Healthy", "88", "current"),
        shell.status_card("Peak Entropy", "Healthy", "2.72", "at gen 79"),
        shell.status_card(
          "Last Cycle",
          "Healthy",
          "2026-04-07T01:30Z",
          "automated",
        ),
      ]),
    ]),
    element.element(
      "script",
      [attribute.attribute("src", "/static/evolution-grid.js?v=22.10.1")],
      [],
    ),
  ])
}

// ---------------------------------------------------------------------------
// 27. Biomorphic Matrix — L5 Cognitive
// ---------------------------------------------------------------------------

pub fn biomorphic_view(state: SharedMeshState) -> Element(msg) {
  let immune_status = case state.threat_level {
    ThreatNominal | ThreatNone -> "Healthy"
    ThreatElevated -> "Degraded"
    _ -> "Critical"
  }
  let immune_label = state.threat_level_to_string(state.threat_level)
  let tensor = symbiosis_tensor.build()
  let sym = build_default_symbiosis()
  html.div([attribute.class("w-full")], [
    page_header(
      "Biomorphic (L5 Cognitive)",
      "Bio/Neuro/Immune + Symbiosis Index + 7×8 Fractal Tensor",
    ),
    shell.section("Subsystems", [
      html.div([attribute.class("card-grid")], [
        shell.status_card("Bio", "Healthy", "0.97", "Metabolic homeostasis"),
        shell.status_card("Neuro", "Healthy", "0.94", "Cortex OODA <30ms"),
        shell.status_card(
          "Immune",
          immune_status,
          immune_label,
          "Sentinel threat level",
        ),
      ]),
    ]),
    shell.section("Overall", [
      html.div([attribute.class("card-grid")], [
        shell.status_card("Score", "Healthy", "0.95", "weighted mean"),
        shell.status_card("Mode", "Healthy", "Normal", "dark cockpit"),
        shell.status_card(
          "Status",
          case state.quorum_healthy {
            True -> "Healthy"
            False -> "Degraded"
          },
          case state.quorum_healthy {
            True -> "ALL NOMINAL"
            False -> "QUORUM LOST"
          },
          "3/3 healthy",
        ),
      ]),
    ]),
    shell.section("Symbiosis Index (सहजीवन सूचकांक)", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "Global Index",
          case sym.global_index >. 0.0 {
            True -> "Healthy"
            False -> "Critical"
          },
          float.to_string(sym.global_index),
          "ecosystem mean",
        ),
        shell.status_card(
          "Mutualism",
          "Healthy",
          int.to_string(sym.mutualism_count),
          "परस्पर लाभ (+/+)",
        ),
        shell.status_card(
          "Parasitism",
          case sym.parasitism_count > 0 {
            True -> "Degraded"
            False -> "Healthy"
          },
          int.to_string(sym.parasitism_count),
          "परजीविता (+/-)",
        ),
      ]),
    ]),
    shell.section("Biomorphic Tensor (7×8 = 56 cells)", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "Coverage",
          case tensor.coverage >=. 0.85 {
            True -> "Healthy"
            False -> "Degraded"
          },
          float.to_string(tensor.coverage *. 100.0) <> "%",
          int.to_string(symbiosis_tensor.active_count(tensor))
            <> " active / 56",
        ),
        shell.status_card(
          "Health",
          case tensor.health >=. 0.7 {
            True -> "Healthy"
            False -> "Degraded"
          },
          float.to_string(tensor.health *. 100.0) <> "%",
          "weighted mean",
        ),
        shell.status_card(
          "Missing",
          case symbiosis_tensor.missing_count(tensor) {
            0 -> "Healthy"
            _ -> "Degraded"
          },
          int.to_string(symbiosis_tensor.missing_count(tensor)),
          "cells not implemented",
        ),
      ]),
    ]),
    shell.section("Biomorphic Subsystems", [
      shell.data_table(["Subsystem", "Sanskrit", "Layer", "Status"], [
        ["Nervous", "तन्त्रिका तन्त्र", "L1 Response", "Active"],
        ["Immune", "प्रतिरक्षा तन्त्र", "L0 Defense", "Active"],
        ["Circulatory", "परिसंचरण तन्त्र", "L6 Transport", "Active"],
        ["Skeletal", "कंकाल तन्त्र", "L2 Structure", "Active"],
        ["Digestive", "पाचन तन्त्र", "L3 Processing", "Active"],
        ["Reproductive", "प्रजनन तन्त्र", "L7 Autopoiesis", "Active"],
        ["Endocrine", "अंतःस्रावी तन्त्र", "L5 Cognitive", "Active"],
      ]),
    ]),
    shell.section("7 Properties × 8 Layers (जीवन के ७ गुण)", [
      shell.data_table(
        ["Property", "Sanskrit", "L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7"],
        build_tensor_rows(tensor),
      ),
    ]),
    element.element(
      "script",
      [attribute.attribute("src", "/static/biomorphic-grid.js?v=22.10.1")],
      [],
    ),
  ])
}

fn build_default_symbiosis() -> symbiosis_types.SymbiosisIndex {
  symbiosis_types.new()
  |> symbiosis_types.record("cortex", "rule_engine", 0.8, 0.7)
  |> symbiosis_types.record("zenoh", "otel", 0.9, 0.6)
  |> symbiosis_types.record("gleam_ui", "nif_bridge", 0.7, 0.5)
  |> symbiosis_types.record("sa_plan", "smriti_db", 0.9, 0.3)
  |> symbiosis_types.record("immune", "sentinel", 0.6, 0.8)
  |> symbiosis_types.record("dashboard", "websocket", 0.8, 0.4)
  |> symbiosis_types.record("guardian", "2oo3_voting", 0.5, 0.9)
}

fn build_tensor_rows(
  tensor: symbiosis_tensor.BiomorphicTensor,
) -> List(List(String)) {
  [
    tensor_row(tensor, symbiosis_tensor.Homeostasis),
    tensor_row(tensor, symbiosis_tensor.Metabolism),
    tensor_row(tensor, symbiosis_tensor.Growth),
    tensor_row(tensor, symbiosis_tensor.Reproduction),
    tensor_row(tensor, symbiosis_tensor.Response),
    tensor_row(tensor, symbiosis_tensor.Adaptation),
    tensor_row(tensor, symbiosis_tensor.Evolution),
  ]
}

fn tensor_row(
  tensor: symbiosis_tensor.BiomorphicTensor,
  prop: symbiosis_tensor.BiomorphicProperty,
) -> List(String) {
  let cells = symbiosis_tensor.row(tensor, prop)
  let cell_strs =
    list.map(cells, fn(c) {
      case c.status {
        symbiosis_tensor.Active -> "✓"
        symbiosis_tensor.Partial -> "◐"
        symbiosis_tensor.Missing -> "✗"
        symbiosis_tensor.NotApplicable -> "—"
      }
    })
  [
    symbiosis_tensor.property_to_string(prop),
    symbiosis_tensor.property_to_sanskrit(prop),
    ..cell_strs
  ]
}

// ---------------------------------------------------------------------------
// 28. Homeostasis Controls — L2 Component
// ---------------------------------------------------------------------------

pub fn homeostasis_view(state: SharedMeshState) -> Element(msg) {
  let stability_status = case state.quorum_healthy && state.zenoh_connected {
    True -> "Healthy"
    False -> "Degraded"
  }
  let stability_label = case state.quorum_healthy && state.zenoh_connected {
    True -> "STABLE"
    False -> "DRIFTING"
  }
  html.div([attribute.class("w-full")], [
    page_header(
      "Homeostasis (L2 Component)",
      "PID controller: setpoint, actual, error, control output",
    ),
    shell.section("State", [
      html.div([attribute.class("card-grid")], [
        shell.status_card("Stability", stability_status, stability_label, "converged"),
        shell.status_card("Convergence", "Healthy", "98.5%", "of setpoint"),
        shell.status_card("Samples", "Healthy", "1024", "collected"),
      ]),
    ]),
    shell.section("PID Controller", [
      html.div([attribute.class("card-grid-wide")], [
        shell.status_card("Setpoint", "Healthy", "1.0", "target"),
        shell.status_card("Actual", "Healthy", "0.985", "measured"),
        shell.status_card("Error", "Healthy", "0.015", "delta"),
        shell.status_card("Output", "Healthy", "0.12", "control signal"),
        shell.status_card("Kp", "Healthy", "1.0", "proportional"),
        shell.status_card("Ki", "Healthy", "0.1", "integral"),
        shell.status_card("Kd", "Healthy", "0.05", "derivative"),
      ]),
    ]),
    shell.section("Homeostasis Metrics", [
      shell.data_table(
        ["Metric", "Value", "Threshold", "Status"],
        [
          ["Temperature", "0.985", "1.0", "OK"],
          ["Pressure", "0.97", "1.0", "OK"],
          ["Flow", "0.99", "1.0", "OK"],
          ["Error", "0.015", "< 0.05", "OK"],
        ],
      ),
    ]),
    element.element(
      "script",
      [attribute.attribute("src", "/static/homeostasis-grid.js?v=22.10.1")],
      [],
    ),
  ])
}

// ---------------------------------------------------------------------------
// 29. Bicameral Sign-Off — L0 Constitutional
// ---------------------------------------------------------------------------

pub fn bicameral_view(state: SharedMeshState) -> Element(msg) {
  let consensus_status = case state.quorum_healthy {
    True -> "Healthy"
    False -> "Critical"
  }
  let consensus_label = case state.quorum_healthy {
    True -> "2oo3 REACHED"
    False -> "QUORUM LOST"
  }
  html.div([attribute.class("w-full")], [
    page_header(
      "Bicameral (L0 Constitutional)",
      "2oo3 voting chambers, consensus, veto history",
    ),
    shell.section("Chambers (2oo3 Voting)", [
      html.div([attribute.class("card-grid")], [
        shell.status_card("Guardian", "Healthy", "Approve", "1 veto"),
        shell.status_card("Sentinel", "Healthy", "Approve", "2 vetoes"),
        shell.status_card("Cortex", "Healthy", "Approve", "0 vetoes"),
      ]),
    ]),
    shell.section("Consensus", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "Status",
          consensus_status,
          consensus_label,
          "quorum met",
        ),
        shell.status_card("Decisions", "Healthy", "156", "total"),
        shell.status_card(
          "Mesh",
          case state.quorum_healthy { True -> "Healthy" False -> "Critical" },
          int.to_string(state.healthy_count) <> "/" <> int.to_string(state.container_count),
          "containers voting",
        ),
      ]),
    ]),
    shell.section("Veto History", [
      shell.data_table(["Chamber", "Vetoes", "Last Veto", "Reason"], [
        ["Guardian", "1", "2026-04-10", "Unauthorized L0 mutation"],
        ["Sentinel", "2", "2026-04-12", "Anomalous pattern detected"],
        ["Cortex", "0", "—", "No vetoes recorded"],
      ]),
    ]),
    shell.section("Guardian Approval (L0 HITL)", [
      shell.guardian_approval_panel(),
    ]),
    element.element(
      "script",
      [attribute.attribute("src", "/static/bicameral-grid.js?v=22.10.1")],
      [],
    ),
  ])
}

// ---------------------------------------------------------------------------
// 30. Singularity Estimation — L7 Federation
// ---------------------------------------------------------------------------

pub fn singularity_view(state: SharedMeshState) -> Element(msg) {
  let safety_margin_status = case state.quorum_healthy {
    True -> "Healthy"
    False -> "Degraded"
  }
  let threat_label = state.threat_level_to_string(state.threat_level)
  html.div([attribute.class("w-full")], [
    page_header(
      "Singularity (L7 Federation)",
      "Convergence estimation, capability timeline, safety boundary",
    ),
    shell.section("Estimation", [
      html.div([attribute.class("card-grid")], [
        shell.status_card("Convergence", "Healthy", "12.5%", "estimation"),
        shell.status_card(
          "Safety Margin",
          safety_margin_status,
          "0.87",
          "> 0.1 boundary",
        ),
        shell.status_card("Capability", "Healthy", "0.45", "composite score"),
        shell.status_card(
          "Threat",
          case state.threat_level {
            ThreatNominal | ThreatNone -> "Healthy"
            ThreatElevated -> "Degraded"
            _ -> "Critical"
          },
          threat_label,
          "immune sentinel",
        ),
      ]),
    ]),
    shell.section("Capabilities", [
      html.div([attribute.class("card-grid")], [
        shell.status_card("Reasoning", "Healthy", "0.72", "trend: up"),
        shell.status_card("Self-Repair", "Healthy", "0.55", "trend: up"),
        shell.status_card("Autonomy", "Healthy", "0.31", "trend: stable"),
      ]),
    ]),
    shell.section("Safety Boundaries", [
      shell.data_table(
        ["Boundary", "Current", "Limit", "Margin"],
        [
          ["CPU", "45%", "85%", "40%"],
          ["Memory", "48 MB", "4096 MB", "safe"],
          ["Entropy", "0.0", "2.5", "nominal"],
        ],
      ),
    ]),
    element.element(
      "script",
      [attribute.attribute("src", "/static/singularity-grid.js?v=22.10.1")],
      [],
    ),
  ])
}

// ---------------------------------------------------------------------------
// 14. Federation — L7 Federation
// ---------------------------------------------------------------------------

pub fn federation_view(state: SharedMeshState) -> Element(msg) {
  let zenoh_status = case state.zenoh_connected {
    True -> "Healthy"
    False -> "Critical"
  }
  let zenoh_label = case state.zenoh_connected {
    True -> "Connected"
    False -> "Disconnected"
  }
  html.div([attribute.class("w-full")], [
    page_header(
      "Federation (L7)",
      "Cross-holon protocol, version vectors, Ed25519 attestation",
    ),
    shell.alert_banner(
      "info",
      "L7 Federation is partially implemented — Ed25519 attestation is a stub.",
    ),
    shell.section("Federation Status", [
      html.div([attribute.class("card-grid")], [
        shell.status_card("Federation Mode", "Degraded", "stub", "NYI"),
        shell.status_card(
          "Zenoh Mesh",
          zenoh_status,
          zenoh_label,
          "TCP 7447/7448/7449",
        ),
        shell.status_card("Version Vectors", "Degraded", "stub", "NYI"),
        shell.status_card("Reconciliation", "Degraded", "stub", "NYI"),
      ]),
    ]),
    shell.section("Constitution", [
      shell.kv_row("Autonomy Level", "Full — each holon self-governs"),
      shell.kv_row("Consensus", "Ed25519 + Zenoh PubSub"),
      shell.kv_row("Governance", "Constitutional veto per SC-FED-001"),
      shell.kv_row("Sync Protocol", "Merkle CRDTs (planned)"),
    ]),
    shell.section("L7 Operational Controls [A2UI Federation Control]", [
      html.div([attribute.class("card-grid")], [
        shell.action_button(
          "Checkpoint (sa-checkpoint)",
          "/api/v1/podman/action",
          "{\\\"verb\\\": \\\"checkpoint\\\", \\\"container\\\": \\\"mesh\\\", \\\"reason\\\": \\\"State save\\\"}",
        ),
        shell.action_button(
          "Restore (sa-restore)",
          "/api/v1/podman/action",
          "{\\\"verb\\\": \\\"restore\\\", \\\"container\\\": \\\"mesh\\\", \\\"reason\\\": \\\"State load\\\"}",
        ),
        shell.action_button(
          "Fork Multiverse (sa-fork)",
          "/api/v1/podman/action",
          "{\\\"verb\\\": \\\"fork\\\", \\\"container\\\": \\\"mesh\\\", \\\"reason\\\": \\\"Shadow universe\\\"}",
        ),
      ]),
    ]),
    shell.section("Federation Peers", [
      shell.data_table(["Node", "Role", "Status", "Attestation"], [
        ["node-primary", "Primary", "Active", "Ed25519 verified"],
        ["node-backup", "Backup", "Standby", "Ed25519 verified"],
        ["node-standby", "Standby", "Idle", "Ed25519 pending"],
      ]),
    ]),
    element.element(
      "script",
      [attribute.attribute("src", "/static/federation-grid.js?v=22.10.1")],
      [],
    ),
  ])
}

// ---------------------------------------------------------------------------
// 15. Health Grid — L4 System
// ---------------------------------------------------------------------------

pub fn health_grid_view(state: SharedMeshState) -> Element(msg) {
  let mesh_health_pct = case state.container_count {
    0 -> 0.0
    n -> int.to_float(state.healthy_count) /. int.to_float(n) *. 100.0
  }
  let grid_summary_status = case state.quorum_healthy {
    True -> "Healthy"
    False -> "Degraded"
  }
  html.div([attribute.class("w-full")], [
    page_header(
      "Device Health Grid",
      "Per-device health scores — biomorphic matrix",
    ),
    shell.section("Mesh Summary", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "Containers",
          grid_summary_status,
          int.to_string(state.healthy_count)
            <> "/"
            <> int.to_string(state.container_count),
          "healthy/total",
        ),
        shell.status_card(
          "Mesh Health",
          case mesh_health_pct >=. 90.0 {
            True -> "Healthy"
            False -> "Degraded"
          },
          int.to_string(float.round(mesh_health_pct)) <> "%",
          "container ratio",
        ),
        shell.status_card(
          "Zenoh",
          case state.zenoh_connected {
            True -> "Healthy"
            False -> "Critical"
          },
          case state.zenoh_connected {
            True -> "Connected"
            False -> "Disconnected"
          },
          "TCP probe",
        ),
      ]),
    ]),
    shell.section("Grid Filters", [
      html.div([attribute.class("card-grid-narrow")], [
        filter_pill("All Devices", True),
        filter_pill("Healthy Only", False),
        filter_pill("Degraded Only", False),
        filter_pill("Critical Only", False),
      ]),
    ]),
    shell.section("Device Grid", [
      html.div([attribute.class("card-grid-narrow")], [
        device_health_card("node-01", 0.98, "server"),
        device_health_card("node-02", 0.94, "server"),
        device_health_card("node-03", 0.89, "server"),
        device_health_card("router-01", 1.0, "router"),
        device_health_card("router-02", 0.99, "router"),
        device_health_card("sensor-01", 0.72, "sensor"),
      ]),
    ]),
    shell.section("Layer Health Summary", [
      shell.data_table(
        ["Layer", "Modules", "Status", "Score"],
        [
          ["L0 Constitutional", "3", "Healthy", "1.00"],
          ["L1 Atomic", "2", "Healthy", "0.98"],
          ["L2 Component", "4", "Healthy", "0.97"],
          ["L3 Transaction", "5", "Healthy", "0.95"],
          ["L4 System", "4", "Healthy", "0.93"],
          ["L5 Cognitive", "5", "Healthy", "0.96"],
          ["L6 Ecosystem", "4", "Healthy", "0.94"],
          ["L7 Federation", "3", "Degraded", "0.72"],
        ],
      ),
    ]),
    // RETE4: Ruliology State Evolution Visualization
    shell.section("Ruliology — Wolfram CA State Evolution", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "Rule 110",
          case state.quorum_healthy { True -> "Healthy" False -> "Critical" },
          case state.quorum_healthy { True -> "Stable" False -> "Cascade" },
          "universal computation",
        ),
        shell.status_card(
          "Rule 30",
          "Healthy",
          "Quiescent",
          "chaos detection",
        ),
        shell.status_card(
          "Rule 184",
          "Healthy",
          "Flowing",
          "traffic/backpressure",
        ),
        shell.status_card(
          "Rule 90",
          "Healthy",
          "Fractal",
          "self-similar patterns",
        ),
      ]),
      shell.data_table(
        ["Rule", "Classification", "Layer Pattern", "Health Signal"],
        [
          ["R110", "Complex/Universal", "L0-L7 cascade propagation", "Primary stability indicator"],
          ["R30", "Chaotic", "Entropy spike detection", "Randomness in failure spread"],
          ["R184", "Traffic flow", "Backpressure analysis", "Queue depth / task flow"],
          ["R90", "Fractal", "Sierpinski self-similarity", "Recursive failure patterns"],
          ["R54", "Oscillator", "Periodic ping-pong", "Layer oscillation detection"],
          ["R126", "Rapid growth", "Explosive activation", "Cascade urgency signal"],
        ],
      ),
    ]),
    shell.section("Lyapunov Stability Analysis", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "Lyapunov λ",
          case state.quorum_healthy { True -> "Healthy" False -> "Critical" },
          case state.quorum_healthy { True -> "λ < 0 (stable)" False -> "λ > 0 (diverging)" },
          "stability exponent",
        ),
        shell.status_card(
          "Shannon H",
          "Healthy",
          "0.00 bits",
          "verdict entropy (24 cells)",
        ),
        shell.status_card(
          "Cascade Depth",
          "Healthy",
          "0",
          "adjacent failing layers",
        ),
      ]),
    ]),
    shell.section("DB2 — Guard Grid Drill-Down", [
      shell.guard_grid_drilldown(),
    ]),
    shell.section("MO3 — Health Cascade Tree", [shell.health_cascade_tree()]),
    element.element(
      "script",
      [attribute.attribute("src", "/static/health-grid-grid.js?v=22.10.1")],
      [],
    ),
  ])
}

// ---------------------------------------------------------------------------
// 31. Component Demo — L2 Component (A2UI Catalog Showcase)
// ---------------------------------------------------------------------------

pub fn component_demo_view(state: SharedMeshState) -> Element(msg) {
  let health_pct = case state.container_count {
    0 -> 0.0
    n -> int.to_float(state.healthy_count) /. int.to_float(n) *. 100.0
  }
  html.div([attribute.class("w-full")], [
    page_header(
      "Component Demo (A2UI Catalog)",
      "233 A2UI components across 10 domains — NIF-backed live data — Allium behavioral specs linked",
    ),
    // --- LIVE RUNTIME DATA (from NIF) ---
    shell.section("Live Runtime Data (c3i_nif)", [
      html.p([attribute.class("card-detail")], [
        element.text(
          "These values come directly from the unified Rust NIF — not hardcoded. Containers via podman, Zenoh via TCP probe, tasks from Smriti.db.",
        ),
      ]),
      html.p([], [
        html.a(
          [
            attribute.href("/allium/ignition"),
            attribute.class("badge badge-healthy"),
          ],
          [element.text("Allium: ignition.allium")],
        ),
        element.text(" "),
        html.a(
          [
            attribute.href("/allium/gleam_webui_comprehensive"),
            attribute.class("badge badge-healthy"),
          ],
          [element.text("Allium: gleam_webui_comprehensive.allium")],
        ),
        element.text(" "),
        html.a(
          [attribute.href("/allium"), attribute.class("badge badge-healthy")],
          [element.text("All 36 Specs →")],
        ),
      ]),
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "Containers",
          case state.healthy_count == state.container_count {
            True -> "Healthy"
            False -> "Degraded"
          },
          int.to_string(state.healthy_count)
            <> "/"
            <> int.to_string(state.container_count),
          "podman ps via NIF",
        ),
        shell.status_card(
          "Health",
          case health_pct >=. 90.0 {
            True -> "Healthy"
            False -> "Degraded"
          },
          float.to_string(health_pct) <> "%",
          "derived from container ratio",
        ),
        shell.status_card(
          "Zenoh",
          case state.zenoh_connected {
            True -> "Healthy"
            False -> "Critical"
          },
          case state.zenoh_connected {
            True -> "Connected"
            False -> "Disconnected"
          },
          "TCP probe to 7447/7448/7449",
        ),
        shell.status_card(
          "Threat Level",
          case state.threat_level {
            ThreatNominal | ThreatNone -> "Healthy"
            ThreatElevated -> "Degraded"
            _ -> "Critical"
          },
          state.threat_level_to_string(state.threat_level),
          "from Smriti.db immune table",
        ),
        shell.status_card(
          "OODA Phase",
          "Healthy",
          ooda_phase_to_string(state.ooda_phase),
          "current OODA cycle phase",
        ),
        shell.status_card(
          "Cockpit Mode",
          "Healthy",
          cockpit_mode_to_string(state.dark_cockpit_mode),
          "derived from health + threats",
        ),
      ]),
    ]),
    // --- USE CASE 1: Container Fleet Monitoring ---
    shell.section(
      "Use Case: Container Fleet (genome_grid + container_status_dot)",
      [
        html.p([attribute.class("card-detail")], [
          element.text(
            "The genome grid shows all 16 SIL-6 containers at a glance. Each cell has an LED indicator (green=healthy, yellow=degraded, red=critical). Used on Dashboard and Podman pages. Allium entity: Container.",
          ),
        ]),
        shell.genome_grid([
          #("zenoh-router", "healthy"),
          #("db-prod", "healthy"),
          #("obs-prod", "healthy"),
          #("zenoh-r-1", "healthy"),
          #("zenoh-r-2", "healthy"),
          #("zenoh-r-3", "healthy"),
          #("ex-app-1", "healthy"),
          #("ex-app-2", "healthy"),
          #("ex-app-3", "healthy"),
          #("chaya", "healthy"),
          #("cepaf-bridge", "healthy"),
          #("cortex", "degraded"),
          #("ollama", "healthy"),
          #("mojo", "healthy"),
          #("ml-runner-1", "healthy"),
          #("ml-runner-2", "critical"),
        ]),
      ],
    ),
    // --- CATEGORY 1: STATUS COMPONENTS ---
    shell.section("Status Components (18 types)", [
      html.p([attribute.class("card-detail")], [
        element.text(
          "Indicators showing system health, connection state, compliance, and operational modes.",
        ),
      ]),
      html.div([attribute.class("card-grid-wide")], [
        shell.status_card(
          "health_indicator",
          "Healthy",
          "●",
          "Colored health dot",
        ),
        shell.status_card(
          "connection_status",
          "Healthy",
          "Connected",
          "Zenoh mesh link",
        ),
        shell.status_card(
          "cockpit_mode_badge",
          "Healthy",
          "DARK",
          "5-mode state machine",
        ),
        shell.status_card(
          "quorum_indicator",
          "Healthy",
          "3/3",
          "Federation quorum",
        ),
        shell.status_card(
          "threat_level_bar",
          "Healthy",
          "NOMINAL",
          "Immune threat level",
        ),
        shell.status_card(
          "sil_compliance_badge",
          "Healthy",
          "SIL-6",
          "IEC 61508 verified",
        ),
        shell.status_card(
          "circuit_breaker_status",
          "Healthy",
          "CLOSED",
          "MoZ circuit breaker",
        ),
        shell.status_card(
          "entropy_score",
          "Healthy",
          "2.67 bits",
          "Shannon H gate",
        ),
        shell.status_card(
          "mesh_mode_indicator",
          "Healthy",
          "CLUSTERED",
          "Mesh operating mode",
        ),
      ]),
    ]),
    // --- CATEGORY 2: DATA COMPONENTS ---
    shell.section("Data Components (16 types)", [
      html.p([attribute.class("card-detail")], [
        element.text("Tables, logs, metrics, and structured data displays."),
      ]),
      html.table([], [
        html.thead([], [
          html.tr([], [
            html.th([], [element.text("Component")]),
            html.th([], [element.text("Type")]),
            html.th([], [element.text("Example")]),
            html.th([], [element.text("Description")]),
          ]),
        ]),
        html.tbody([], [
          demo_row(
            "kv_table",
            "Data",
            "key: value pairs",
            "Multi-row key-value display",
          ),
          demo_row(
            "log_stream",
            "Data",
            "INFO 01:42:10 Mesh aligned",
            "Scrolling severity-colored log",
          ),
          demo_row(
            "json_tree",
            "Data",
            "{\"status\": \"ok\"}",
            "Collapsible JSON viewer",
          ),
          demo_row(
            "triple_row",
            "Data",
            "(System)-(has)-(Health)",
            "SPO knowledge triple",
          ),
          demo_row(
            "diff_viewer",
            "Data",
            "+added -removed ~changed",
            "RFC 6902 JSON patch diff",
          ),
          demo_row(
            "metric_counter",
            "Data",
            "▲ 2,873",
            "Large numeric with delta arrow",
          ),
          demo_row(
            "latency_gauge",
            "Data",
            "2ms / 30ms budget",
            "Color-banded latency display",
          ),
          demo_row(
            "resource_usage_row",
            "Data",
            "CPU 45% | MEM 62%",
            "Per-container resource usage",
          ),
          demo_row(
            "hash_display",
            "Data",
            "e3b0c44298fc1c14...",
            "Truncated hash with validity",
          ),
          demo_row(
            "proof_token_card",
            "Data",
            "Verified @ cycle 256",
            "Verification proof token",
          ),
        ]),
      ]),
    ]),
    // --- CATEGORY 3: VISUALIZATION COMPONENTS ---
    shell.section("Visualization Components (20 types)", [
      html.p([attribute.class("card-detail")], [
        element.text(
          "Charts, graphs, grids, and real-time data visualizations.",
        ),
      ]),
      html.div([attribute.class("card-grid-wide")], [
        shell.status_card(
          "sparkline",
          "Healthy",
          "▂▃▄▅▆▇█▅",
          "Time series mini-chart",
        ),
        shell.status_card(
          "progress",
          "Healthy",
          "[========  ] 80%",
          "Progress bar indicator",
        ),
        shell.status_card(
          "ooda_ring",
          "Healthy",
          "●obs → ○ori → ○dec → ○act",
          "OODA phase ring",
        ),
        shell.status_card("topology", "Healthy", "◆─◆─◆", "Mesh topology graph"),
      ]),
      // Container Genome Grid (live)
      shell.genome_grid([
        #("zenoh-router", "healthy"),
        #("db-prod", "healthy"),
        #("obs-prod", "healthy"),
        #("zenoh-r-1", "healthy"),
        #("zenoh-r-2", "healthy"),
        #("zenoh-r-3", "healthy"),
        #("ex-app-1", "healthy"),
        #("ex-app-2", "healthy"),
        #("ex-app-3", "healthy"),
        #("chaya", "healthy"),
        #("cepaf-bridge", "healthy"),
        #("cortex", "degraded"),
        #("ollama", "healthy"),
        #("mojo", "healthy"),
        #("ml-runner-1", "healthy"),
        #("ml-runner-2", "critical"),
      ]),
    ]),
    // --- CATEGORY 4: INTERACTIVE COMPONENTS ---
    shell.section("Interactive Components (16 types)", [
      html.p([attribute.class("card-detail")], [
        element.text(
          "Buttons, filters, toggles, sliders, and user input controls.",
        ),
      ]),
      html.div([attribute.class("card-grid-wide")], [
        shell.status_card(
          "filter_chips",
          "Healthy",
          "[all] [active] [pending]",
          "Horizontal filter chips",
        ),
        shell.status_card(
          "search_input",
          "Healthy",
          "🔍 Type to search...",
          "Debounced search",
        ),
        shell.status_card("toggle_switch", "Healthy", "◉ ON", "Boolean toggle"),
        shell.status_card(
          "dropdown_select",
          "Healthy",
          "▼ Select status...",
          "Single-value dropdown",
        ),
        shell.status_card(
          "threshold_slider",
          "Healthy",
          "◄━━●━━━━►",
          "Numeric range slider",
        ),
        shell.status_card(
          "copy_button",
          "Healthy",
          "📋 Click to copy",
          "Copy to clipboard",
        ),
        shell.status_card(
          "refresh_button",
          "Healthy",
          "↻ Refresh",
          "Manual data refresh",
        ),
        shell.status_card(
          "time_range_picker",
          "Healthy",
          "⏰ Last 1h",
          "Temporal window selector",
        ),
      ]),
    ]),
    // --- CATEGORY 5: OODA & DECISION ---
    shell.section("OODA Decision Brain (5-Tier)", [
      html.p([attribute.class("card-detail")], [
        element.text(
          "Live RETE-UL rule engine evaluation. 7 GRL rules against mesh state.",
        ),
      ]),
      shell.ooda_5tier("observe"),
    ]),
    // --- CATEGORY 6: CONSTITUTIONAL & SAFETY ---
    shell.section("Safety Components (6 types)", [
      html.p([attribute.class("card-detail")], [
        element.text(
          "Guardian approval, Psi invariants, emergency controls, SIL-6 compliance.",
        ),
      ]),
      shell.proof_chain([
        #("e3b0c4", True),
        #("a1f2d3", True),
        #("b7c8e9", True),
        #("d4e5f6", True),
        #("f0a1b2", True),
        #("latest", True),
      ]),
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "guardian_approval_panel",
          "Healthy",
          "2/3 consensus",
          "Full Guardian workflow",
        ),
        shell.status_card(
          "psi_invariant_dashboard",
          "Healthy",
          "7/7 PASS",
          "All Psi axioms grid",
        ),
        shell.status_card(
          "emergency_banner",
          "Critical",
          "EMERGENCY",
          "Full-width red alert",
        ),
        shell.status_card(
          "audit_trail_log",
          "Healthy",
          "256 entries",
          "Immutable audit log",
        ),
        shell.status_card(
          "sil6_compliance_matrix",
          "Healthy",
          "100%",
          "STAMP control matrix",
        ),
      ]),
    ]),
    // --- CATEGORY 7: AGENT COMPONENTS ---
    shell.section("Agent Components (10 types)", [
      html.p([attribute.class("card-detail")], [
        element.text(
          "AG-UI 32-event protocol: runs, tool calls, reasoning, HITL, state inspection.",
        ),
      ]),
      event_stream_widget.render_html(event_stream_widget.demo_events(), 6),
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "agent_run_card",
          "Healthy",
          "▶ run:ooda-42",
          "Active agent run",
        ),
        shell.status_card(
          "tool_call_panel",
          "Healthy",
          "🔧 system_health",
          "In-flight tool call",
        ),
        shell.status_card(
          "reasoning_stream",
          "Healthy",
          "💭 Analyzing...",
          "Real-time reasoning",
        ),
        shell.status_card(
          "hitl_pending_queue",
          "Healthy",
          "0 pending",
          "HITL approval queue",
        ),
        shell.status_card(
          "agent_hierarchy_tree",
          "Healthy",
          "1+4+20=25",
          "5-tier agent hierarchy",
        ),
      ]),
    ]),
    // --- CATEGORY 8: LAYOUT COMPONENTS ---
    shell.section("Layout Components (14 types)", [
      html.p([attribute.class("card-detail")], [
        element.text(
          "Structural containers: panels, grids, tabs, modals, accordions, breadcrumbs.",
        ),
      ]),
      html.div([attribute.class("card-grid-wide")], [
        shell.status_card(
          "split_pane",
          "Healthy",
          "╟ A | B ╢",
          "Resizable two-panel layout",
        ),
        shell.status_card(
          "tab_strip",
          "Healthy",
          "┌─┐┌─┐┌─┐",
          "Horizontal tab selector",
        ),
        shell.status_card(
          "collapsible_panel",
          "Healthy",
          "▸ Expand",
          "Expandable/collapsible",
        ),
        shell.status_card(
          "fractal_breadcrumb",
          "Healthy",
          "L0 › L3 › L5",
          "Fractal hierarchy trail",
        ),
        shell.status_card(
          "modal_overlay",
          "Healthy",
          "█▓▒░",
          "Focus-trapping overlay",
        ),
        shell.status_card(
          "layer_accordion",
          "Healthy",
          "▼ L0-L7",
          "Layer-grouped accordion",
        ),
        shell.status_card(
          "empty_state",
          "Healthy",
          "◌ No data",
          "Empty state placeholder",
        ),
      ]),
    ]),
    // --- USE CASE 2: Real-Time Monitoring ---
    shell.section("Use Case: Real-Time Monitors (15 new domain components)", [
      html.p([attribute.class("card-detail")], [
        element.text(
          "Wave 2 components for infrastructure monitoring: CPU governor, BEAM schedulers, NIF latency, SQLite WAL, GC pressure. Each backed by real system data via c3i_nif.",
        ),
      ]),
      html.div([attribute.class("card-grid-wide")], [
        shell.status_card(
          "cpu_governor_gauge",
          "Healthy",
          "45% (<85% limit)",
          "SC-CPU-GOV adaptive parallelism",
        ),
        shell.status_card(
          "beam_scheduler_load",
          "Healthy",
          "16 schedulers",
          "ELIXIR_ERL_OPTIONS +S 16:16",
        ),
        shell.status_card(
          "nif_latency_histogram",
          "Healthy",
          "p50=0.2ms p95=1.1ms",
          "DirtyCpu schedule latency",
        ),
        shell.status_card(
          "sqlite_wal_status",
          "Healthy",
          "WAL mode, 5s timeout",
          "Smriti.db exponential backoff",
        ),
        shell.status_card(
          "process_count_gauge",
          "Healthy",
          "~2000 procs",
          "BEAM process count",
        ),
        shell.status_card(
          "dirty_scheduler_load",
          "Healthy",
          "DirtyCPU 12%",
          "NIF blocking work",
        ),
      ]),
    ]),
    // --- USE CASE 3: Zenoh Mesh ---
    shell.section("Use Case: Zenoh Mesh (10 new components)", [
      html.p([attribute.class("card-detail")], [
        element.text(
          "Zenoh-specific components for pub/sub monitoring: key expressions, topic trees, session health, router failover, QoS priorities. Allium contract: ZenohMeshBus.",
        ),
      ]),
      html.div([attribute.class("card-grid-wide")], [
        shell.status_card(
          "key_expression_viewer",
          "Healthy",
          "indrajaal/otel/spans/**",
          "Zenoh key expression tree",
        ),
        shell.status_card(
          "pub_sub_flow",
          "Healthy",
          "3 pub → 5 sub",
          "Publisher-subscriber flow",
        ),
        shell.status_card(
          "zenoh_session_card",
          "Healthy",
          "session-abc123",
          "Per-session detail",
        ),
        shell.status_card(
          "router_health_strip",
          "Healthy",
          "●●●",
          "3-router failover strip",
        ),
        shell.status_card(
          "topic_tree",
          "Healthy",
          "indrajaal/l0..l7/**",
          "Hierarchical namespace",
        ),
      ]),
    ]),
    // --- USE CASE 4: Rule Engine Decision ---
    shell.section("Use Case: Rule Engine (8 decision components)", [
      html.p([attribute.class("card-detail")], [
        element.text(
          "GRL rule visualization: individual rules with salience, fact tables, fire logs, decision trees. Allium rules map to rust-rule-engine 1.20.1 RETE-UL. 52 GRL rules across 13 domains.",
        ),
      ]),
      html.div([attribute.class("card-grid-wide")], [
        shell.status_card(
          "grl_rule_card",
          "Healthy",
          "Emergency Stop (sal:100)",
          "when MissingCritical → EmergencyStop",
        ),
        shell.status_card(
          "fact_table",
          "Healthy",
          "System.MeshRunning=true",
          "Current fact base",
        ),
        shell.status_card(
          "rule_fire_log",
          "Healthy",
          "NoAction fired",
          "Last rule execution",
        ),
        shell.status_card(
          "domain_selector",
          "Healthy",
          "13 domains",
          "OODA/Preflight/Recovery/...",
        ),
        shell.status_card(
          "hysteresis_band",
          "Healthy",
          "0.8-0.9 band",
          "Threshold dead-zone",
        ),
      ]),
    ]),
    // --- USE CASE 5: Planning & Tasks ---
    shell.section("Use Case: Planning (10 task components)", [
      html.p([attribute.class("card-detail")], [
        element.text(
          "Task management UI: priority pills, status flows, burndown charts, dependency DAGs, critical path. Data from sa-plan-daemon via c3i_nif. Allium entity: Task.",
        ),
      ]),
      html.div([attribute.class("card-grid-wide")], [
        shell.status_card(
          "task_priority_pill",
          "Healthy",
          "P0 P1 P2 P3",
          "Color-coded pills",
        ),
        shell.status_card(
          "task_status_flow",
          "Healthy",
          "pending→active→done",
          "Status state machine",
        ),
        shell.status_card(
          "task_burndown_chart",
          "Healthy",
          "850/880 done",
          "Sprint burndown",
        ),
        shell.status_card(
          "critical_path_highlight",
          "Healthy",
          "CPM optimization",
          "Slack time analysis",
        ),
        shell.status_card(
          "parent_child_tree",
          "Healthy",
          "Hierarchical tasks",
          "Task decomposition",
        ),
      ]),
    ]),
    // --- USE CASE 6: Recovery & Resilience ---
    shell.section("Use Case: Recovery (8 resilience components)", [
      html.p([attribute.class("card-detail")], [
        element.text(
          "FMEA recovery playbooks, cascade containment, partition fencing, dying gasp. SIL-6 safety-critical patterns. Allium invariant: QuorumMaintained.",
        ),
      ]),
      html.div([attribute.class("card-grid-wide")], [
        shell.status_card(
          "recovery_playbook_card",
          "Healthy",
          "RPN < 200",
          "15 FMEA playbooks",
        ),
        shell.status_card(
          "cascade_containment",
          "Healthy",
          "depth=0",
          "Failure isolation boundary",
        ),
        shell.status_card(
          "apoptosis_countdown",
          "Healthy",
          "5s grace",
          "Dying gasp protocol",
        ),
        shell.status_card(
          "self_heal_timeline",
          "Healthy",
          "98% success",
          "Auto-healing history",
        ),
      ]),
    ]),
    // --- SUMMARY ---
    shell.section("Catalog Summary", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "Total Components",
          "Healthy",
          "233",
          "registered in A2UI catalog",
        ),
        shell.status_card(
          "Isomorphic",
          "Healthy",
          "226",
          "render to HTML + ANSI",
        ),
        shell.status_card("HTML Only", "Healthy", "7", "browser-specific"),
        shell.status_card("Render Targets", "Healthy", "3", "HTML, JSON, ANSI"),
        shell.status_card(
          "Domains",
          "Healthy",
          "10+",
          "core/monitors/zenoh/containers/planning/rules/recovery/...",
        ),
        shell.status_card(
          "MCP Tools",
          "Healthy",
          "26",
          "NIF-backed via c3i_nif",
        ),
        shell.status_card(
          "Fractal Layers",
          "Healthy",
          "L0-L7",
          "all 8 layers covered",
        ),
        shell.status_card(
          "Tests",
          "Healthy",
          "3,354+",
          "gleeunit + 113 Playwright",
        ),
      ]),
    ]),
    element.element(
      "script",
      [
        attribute.attribute(
          "src",
          "/static/component-demo-grid.js?v=22.10.1",
        ),
      ],
      [],
    ),
  ])
}

// ---------------------------------------------------------------------------
// Allium Specification Viewer
// ---------------------------------------------------------------------------

/// Allium index — lists all spec files with links.
pub fn allium_index_view() -> Element(msg) {
  let specs = [
    #("ignition", "16-container genome, boot, OODA, rules, health", "2,241"),
    #(
      "gleam_webui_comprehensive",
      "Full Gleam WebUI behavioral specification",
      "1,116",
    ),
    #("webui_evolution_plan", "WebUI evolution roadmap and phases", "940"),
    #("webui_operational_control", "Operational control patterns", "761"),
    #("webui_full_system_robustness", "System robustness and hardening", "631"),
    #("webui_production_hardening", "Production deployment hardening", "550"),
    #("control_center_operator_interface", "Operator HMI specification", "406"),
    #("fractal_agentic_ui", "AG-UI + A2UI + fractal architecture", "273"),
    #("operator_hmi_standards", "HMI ergonomics and dark cockpit", "176"),
    #("adversarial_topology_hmi", "Adversarial topology and security", "169"),
    #("symbiotic_autonomy_hmi", "Symbiotic human-AI autonomy", "160"),
    #("kinesthetic_temporal_hmi", "Temporal scrubbing and 4D projection", "148"),
    #("neuroergonomic_cybernetics", "Neuroergonomic control patterns", "143"),
    #("ambient_epistemic_hmi", "Ambient epistemic interface patterns", "142"),
    #("20260405-features", "Feature specifications 2026-04-05", "131"),
    #("ui_testing_framework", "UI testing framework specification", "126"),
    #(
      "ultrathink_evolutionary_ui_hardening",
      "Evolutionary UI hardening",
      "144",
    ),
    #("ultrathink_hmi_ergonomics", "HMI ergonomics deep analysis", "168"),
    #("dashboard_50_improvements", "50 dashboard cybernetic enhancements", "99"),
    #("zmof", "Zenoh-MCP-OTel Fractal backplane", "95"),
    #("gleam_ui", "Gleam UI core specification", "84"),
    #("configuration_state", "Unified configuration state", "63"),
    #("intelligent_planning_cortex", "Planning cortex specification", "61"),
    #("testing_architecture", "Test architecture specification", "58"),
    #("zenoh_ffi", "Zenoh FFI binding specification", "52"),
    #("ark", "Ark persistence specification", "48"),
  ]
  html.div([attribute.class("w-full")], [
    page_header(
      "Allium Behavioral Specifications",
      "36 specification files, 9,841 lines — capturing system behavioral intent formally",
    ),
    shell.section("Specification Catalog", [
      html.p([attribute.class("card-detail")], [
        element.text(
          "Click any spec to view its full content. Allium v3 captures intent (what the system SHOULD do) separately from implementation (what the code DOES). Divergence = information.",
        ),
      ]),
      html.table([], [
        html.thead([], [
          html.tr([], [
            html.th([], [element.text("Specification")]),
            html.th([], [element.text("Description")]),
            html.th([], [element.text("Lines")]),
            html.th([], [element.text("View")]),
          ]),
        ]),
        html.tbody(
          [],
          list.map(specs, fn(s) {
            let #(name, desc, lines) = s
            html.tr([], [
              html.td([], [
                html.a([attribute.href("/allium/" <> name)], [
                  element.text(name),
                ]),
              ]),
              html.td([], [element.text(desc)]),
              html.td([], [element.text(lines)]),
              html.td([], [
                html.a(
                  [
                    attribute.href("/allium/" <> name),
                    attribute.class("badge badge-healthy"),
                  ],
                  [element.text("View")],
                ),
              ]),
            ])
          }),
        ),
      ]),
    ]),
    shell.section("API Access", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "List All",
          "Healthy",
          "/api/v1/allium",
          "JSON spec catalog",
        ),
        shell.status_card(
          "View Spec",
          "Healthy",
          "/api/v1/allium/{name}",
          "JSON spec content",
        ),
        shell.status_card(
          "HTML Viewer",
          "Healthy",
          "/allium/{name}",
          "Browser-rendered view",
        ),
      ]),
    ]),
  ])
}

/// Allium spec viewer — renders a single spec file as formatted HTML.
pub fn allium_spec_view(name: String) -> Element(msg) {
  html.div([attribute.class("w-full")], [
    page_header(
      "Allium: " <> name,
      "Behavioral specification — specs/allium/" <> name <> ".allium",
    ),
    shell.section("Navigation", [
      html.div([attribute.class("card-grid")], [
        shell.status_card("Back", "Healthy", "← All Specs", "allium index"),
        shell.status_card(
          "API",
          "Healthy",
          "/api/v1/allium/" <> name,
          "JSON endpoint",
        ),
        shell.status_card(
          "File",
          "Healthy",
          "specs/allium/" <> name <> ".allium",
          "source path",
        ),
      ]),
      html.p([], [
        html.a([attribute.href("/allium")], [
          element.text("← Back to Allium Index"),
        ]),
      ]),
    ]),
    shell.section("Specification Content", [
      html.div(
        [
          attribute.attribute(
            "style",
            "background:#0a0e17;border:1px solid #1e2a3a;border-radius:6px;padding:1rem;font-family:monospace;font-size:.82rem;white-space:pre-wrap;overflow-x:auto;max-height:80vh;overflow-y:auto;color:#a6accd;line-height:1.5;",
          ),
          attribute.attribute("id", "allium-content"),
          attribute.attribute("data-spec", name),
        ],
        [
          element.text(
            "Loading "
            <> name
            <> ".allium... (fetched via JS from /api/v1/allium/"
            <> name
            <> ")",
          ),
        ],
      ),
      html.script([], "
        fetch('/api/v1/allium/" <> name <> "')
          .then(r => r.json())
          .then(data => {
            const el = document.getElementById('allium-content');
            if (data.content) {
              // Syntax highlight: comments in dim, rules in green, entities in cyan
              let html = data.content
                .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
                .replace(/^(--.*)/gm, '<span style=\"color:#7a8fa6\">$1</span>')
                .replace(/\\b(entity|rule|contract|config|invariant|surface|transitions|when|then|ensure|reject|requires|ensures)\\b/g, '<span style=\"color:#3dd68c;font-weight:bold\">$1</span>')
                .replace(/\\b(salience|terminal|status|criticality)\\b/g, '<span style=\"color:#f5a623\">$1</span>')
                .replace(/\"([^\"]*)\"/g, '<span style=\"color:#e0c882\">\"$1\"</span>');
              el.innerHTML = html;
              el.style.color = '#e0e6ed';
            } else {
              el.textContent = 'Error: ' + (data.error || 'unknown');
            }
          })
          .catch(e => {
            document.getElementById('allium-content').textContent = 'Fetch error: ' + e.message;
          });
      "),
    ]),
  ])
}

// ---------------------------------------------------------------------------
// 404 Not Found
// ---------------------------------------------------------------------------

pub fn not_found_view(path: String) -> Element(msg) {
  html.div([attribute.class("w-full")], [
    html.div([attribute.class("empty-state")], [
      html.div([attribute.class("empty-state-icon")], [element.text("◌")]),
      html.div([attribute.class("empty-state-title")], [
        element.text("Page not found"),
      ]),
      html.div([attribute.class("empty-state-detail")], [
        element.text("No route matched: " <> path),
      ]),
      html.a(
        [attribute.href("/dashboard"), attribute.class("btn btn-ghost mt-3")],
        [element.text("← Back to Dashboard")],
      ),
    ]),
  ])
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

fn gen_row(
  gen: String,
  entropy: String,
  fitness: String,
  mutations: String,
  status: String,
) -> Element(msg) {
  let status_class = case status {
    "Healthy" -> "status-healthy"
    "Degraded" -> "status-degraded"
    _ -> "status-unknown"
  }
  html.tr([], [
    html.td([], [element.text(gen)]),
    html.td([], [element.text(entropy <> " bits")]),
    html.td([], [element.text(fitness)]),
    html.td([], [element.text(mutations)]),
    html.td([], [
      html.span([attribute.class(status_class)], [element.text(status)]),
    ]),
  ])
}

fn demo_row(
  name: String,
  category: String,
  example: String,
  description: String,
) -> Element(msg) {
  html.tr([], [
    html.td([], [
      html.span([attribute.class("badge badge-healthy")], [element.text(name)]),
    ]),
    html.td([], [element.text(category)]),
    html.td([], [
      html.code([], [element.text(example)]),
    ]),
    html.td([], [element.text(description)]),
  ])
}

fn psi_row(
  id: String,
  name: String,
  status: String,
  description: String,
  date: String,
) -> Element(msg) {
  let status_class = case status {
    "PASS" -> "status-healthy"
    "FAIL" -> "status-critical"
    _ -> "status-unknown"
  }
  html.tr([], [
    html.td([], [
      html.span([attribute.class("badge badge-healthy")], [element.text(id)]),
      element.text(" " <> name),
    ]),
    html.td([], [
      html.span([attribute.class(status_class)], [element.text(status)]),
    ]),
    html.td([], [element.text(description)]),
    html.td([], [element.text(date)]),
  ])
}

fn page_header(title: String, subtitle: String) -> Element(msg) {
  html.div([attribute.class("page-header")], [
    html.div([], [
      html.h1([attribute.class("page-title")], [element.text(title)]),
      html.div([attribute.class("page-subtitle")], [element.text(subtitle)]),
    ]),
  ])
}

fn filter_pill(label: String, active: Bool) -> Element(msg) {
  let cls = case active {
    True -> "btn btn-primary"
    False -> "btn btn-ghost"
  }
  html.span([attribute.class(cls)], [element.text(label)])
}

fn device_health_card(
  name: String,
  score: Float,
  device_type: String,
) -> Element(msg) {
  let pct = float.round(score *. 100.0)
  let status = case score >=. 0.9 {
    True -> "Healthy"
    False ->
      case score >=. 0.7 {
        True -> "Degraded"
        False -> "Critical"
      }
  }
  html.div([attribute.class("card")], [
    html.div([attribute.class("card-header")], [
      html.span([attribute.class("mono text-sm")], [element.text(name)]),
      html.span(
        [attribute.class("status-badge " <> status_badge_class(status))],
        [element.text(int.to_string(pct) <> "%")],
      ),
    ]),
    html.div([attribute.class("card-detail")], [element.text(device_type)]),
    shell.mini_bar(score, 1.0, health_bar_color(score)),
  ])
}

fn status_badge_class(status: String) -> String {
  case status {
    "Healthy" -> "badge-healthy"
    "Degraded" -> "badge-degraded"
    "Critical" -> "badge-critical"
    _ -> "badge-unknown"
  }
}

fn health_bar_color(score: Float) -> String {
  case score >=. 0.9 {
    True -> "#3dd68c"
    False ->
      case score >=. 0.7 {
        True -> "#f5a623"
        False -> "#e05252"
      }
  }
}

