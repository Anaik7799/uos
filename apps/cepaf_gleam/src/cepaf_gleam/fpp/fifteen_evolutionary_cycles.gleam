//// =============================================================================
//// [UOS-FPP-15-CYCLES] 15 SYSTEMATIC EVOLUTIONARY CYCLES (EV-111 .. EV-125)
//// =============================================================================
//// <uos-module>
////   <identity>
////     <module>cepaf_gleam/fpp/fifteen_evolutionary_cycles</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL..L9_SOVEREIGNTY</layer>
////     <topology>Universal 15 Evolutionary Cycles Metamodel Covering All 17 Aspects</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-HA-001, SC-SOV-001, SC-POODAVR-001, SC-CHECKLIST-001</stamp-controls>
////   </compliance>
//// </uos-module>
//// =============================================================================

import gleam/int
import gleam/list

pub type SovereignKind {
  CodexAstra
  ClaudeFable
  AgySovereign
  OpenRouterSovereign
  TriSovereignConsensus
}

pub fn sovereign_to_string(sovereign: SovereignKind) -> String {
  case sovereign {
    CodexAstra -> "Codex Astra"
    ClaudeFable -> "Claude Fable"
    AgySovereign -> "AGY Sovereign"
    OpenRouterSovereign -> "OpenRouter"
    TriSovereignConsensus -> "Tri-Sovereign Consensus"
  }
}

pub type SystemEvolutionCycle {
  SystemEvolutionCycle(
    cycle_num: Int,
    ev_tag: String,
    title: String,
    target_aspect_ids: List(Int),
    target_fractal_layer: Int,
    sovereign_sponsor: SovereignKind,
    focus: String,
    expected_gain_pct: Float,
    risk_score: Float,
    receipt_digest_prefix: String,
  )
}

/// The Canonical 15 Evolutionary Cycles (EV-111 through EV-125).
/// Systematically covers all 17 system aspects across layers L0..L9.
pub fn get_15_system_evolutionary_cycles() -> List(SystemEvolutionCycle) {
  [
    SystemEvolutionCycle(
      1,
      "EV-111",
      "Substrate & Hardware Armor",
      [1, 3],
      0,
      AgySovereign,
      "Host NVMe 25503L801736 interlock enforcement and Zero-Muda verification",
      18.0,
      0.04,
      "sha256-ev111-hw-armor",
    ),
    SystemEvolutionCycle(
      2,
      "EV-112",
      "Standalone Jujutsu Monorepo Purity",
      [2],
      9,
      TriSovereignConsensus,
      "Pure .jj/ standalone repo operations with zero native Git mutations",
      15.0,
      0.03,
      "sha256-ev112-jj-monorepo",
    ),
    SystemEvolutionCycle(
      3,
      "EV-113",
      "Deterministic ZigVM Runtime & VFS",
      [5],
      1,
      CodexAstra,
      "Descriptor-relative, race-free, symlink-aware VFS (8/8 laws) and CAS arena",
      22.0,
      0.02,
      "sha256-ev113-zigvm-vfs",
    ),
    SystemEvolutionCycle(
      4,
      "EV-114",
      "OTP 29 Root Supervision & Homeostasis",
      [4, 8],
      2,
      ClaudeFable,
      "Root 4-domain supervisor (uos_sup.gleam), Prajna breakers, Lyapunov damping",
      20.0,
      0.03,
      "sha256-ev114-otp-supervision",
    ),
    SystemEvolutionCycle(
      5,
      "EV-115",
      "Sa-Plan Durable Workflow Engine",
      [17],
      3,
      CodexAstra,
      "Hermes OCaml Sa-plan bridge, Oban jobs, Temporal recovery, Jidoka Andon Stop Line",
      24.0,
      0.02,
      "sha256-ev115-saplan-engine",
    ),
    SystemEvolutionCycle(
      6,
      "EV-116",
      "Quarantined MAX/Mojo SIMD Inference",
      [9],
      4,
      OpenRouterSovereign,
      "Modular MAX/Mojo SIMD vector ranker, Python stdio quarantine, sub-ms embeddings",
      26.0,
      0.03,
      "sha256-ev116-max-simd",
    ),
    SystemEvolutionCycle(
      7,
      "EV-117",
      "Zenoh Fractal Mesh Backplane",
      [10],
      4,
      ClaudeFable,
      "OoZ (OTel-over-Zenoh) & MoZ (MCP-over-Zenoh) backplane, zero-copy pub/sub",
      28.0,
      0.02,
      "sha256-ev117-zenoh-mesh",
    ),
    SystemEvolutionCycle(
      8,
      "EV-118",
      "POODAVR 7-Stage Cybernetic Loop",
      [4, 8],
      5,
      TriSovereignConsensus,
      "Predict-Observe-Orient-Decide-Act-Verify-Reflect loop, Lyapunov decay, Kalman prior",
      25.0,
      0.03,
      "sha256-ev118-poodavr-loop",
    ),
    SystemEvolutionCycle(
      9,
      "EV-119",
      "NASA JPL F Prime (F') Statecharts",
      [1, 4],
      5,
      CodexAstra,
      "Pure Gleam F Prime component state machine, signal dispatch, fail-closed halt",
      17.0,
      0.01,
      "sha256-ev119-fprime-fsm",
    ),
    SystemEvolutionCycle(
      10,
      "EV-120",
      "AG-UI 32-Event Stream Protocol",
      [11],
      6,
      ClaudeFable,
      "32 structured event types across 7 categories (Lifecycle, Tool, State, etc.)",
      19.0,
      0.02,
      "sha256-ev120-agui-protocol",
    ),
    SystemEvolutionCycle(
      11,
      "EV-121",
      "A2UI Declarative Component Catalog",
      [12],
      6,
      AgySovereign,
      "233 verified declarative JSON component specifications across 22 domains",
      21.0,
      0.02,
      "sha256-ev121-a2ui-catalog",
    ),
    SystemEvolutionCycle(
      12,
      "EV-122",
      "Penta-Stack Multi-Interface Parity",
      [13],
      6,
      TriSovereignConsensus,
      "Triple-interface parity: Lustre Web (4100/8100), Wisp REST, Split-Screen ANSI TUI",
      23.0,
      0.02,
      "sha256-ev122-pentastack-ui",
    ),
    SystemEvolutionCycle(
      13,
      "EV-123",
      "Universal Tailscale FQDN Routing",
      [14],
      7,
      OpenRouterSovereign,
      "Clickable Tailscale FQDN links on all views and docs (nas-1.tail55d152.ts.net:8100)",
      16.0,
      0.01,
      "sha256-ev123-tailscale-routing",
    ),
    SystemEvolutionCycle(
      14,
      "EV-124",
      "Knowledge Management Triad (KM)",
      [16],
      7,
      ClaudeFable,
      "Hermes Wiki AST, ZigVM ZK permanent ADRs (001..047), C3I Living Ontology",
      22.0,
      0.02,
      "sha256-ev124-km-triad",
    ),
    SystemEvolutionCycle(
      15,
      "EV-125",
      "Formal Verification & Sovereign Seal",
      [6, 7, 15],
      8,
      TriSovereignConsensus,
      "Lean 4 theorems (Trace13 conservation), Gospel contracts, 18/18 Checklist PASS",
      30.0,
      0.01,
      "sha256-ev125-formal-seal",
    ),
  ]
}

/// Computes the deduplicated list of all aspect IDs covered across the cycles.
pub fn covered_aspect_ids(cycles: List(SystemEvolutionCycle)) -> List(Int) {
  list.flat_map(cycles, fn(c) { c.target_aspect_ids })
  |> list.unique
  |> list.sort(int.compare)
}

/// Mathematically verifies that all 17 canonical aspects are covered.
pub fn verify_aspect_coverage_across_15_cycles(
  cycles: List(SystemEvolutionCycle),
) -> Bool {
  let covered = covered_aspect_ids(cycles)
  let required_aspects = [
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
  ]
  list.length(covered) == 17
  && list.all(required_aspects, fn(id) { list.contains(covered, id) })
}
