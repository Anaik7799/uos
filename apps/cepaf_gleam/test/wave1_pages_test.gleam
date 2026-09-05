// Wave 1 page tests — Lustre MVU init/update + TUI render for all 6 new pages
// STAMP: SC-GLM-UI-001, SC-UIGT-007, SC-MUDA-001

import cepaf_gleam/planning/nif as planning_nif
import cepaf_gleam/ui/lustre/bicameral
import cepaf_gleam/ui/lustre/biomorphic
import cepaf_gleam/ui/lustre/evolution
import cepaf_gleam/ui/lustre/homeostasis
import cepaf_gleam/ui/lustre/integrity
import cepaf_gleam/ui/lustre/singularity
import cepaf_gleam/ui/tui/bicameral_view
import cepaf_gleam/ui/tui/biomorphic_view
import cepaf_gleam/ui/tui/evolution_view
import cepaf_gleam/ui/tui/homeostasis_view
import cepaf_gleam/ui/tui/integrity_view
import cepaf_gleam/ui/tui/singularity_view
import gleam/option.{Some}
import gleam/string
import gleeunit/should

// =============================================================================
// Integrity (L0 Constitutional)
// =============================================================================

pub fn integrity_init_defaults_test() {
  let m = integrity.init()
  m.loading |> should.equal(True)
  m.chain_valid |> should.equal(False)
  m.constitution_hash |> should.equal("")
}

pub fn integrity_verification_loaded_test() {
  let checks = [
    integrity.PsiCheck(name: "Psi-0", passed: True, detail: "ok"),
    integrity.PsiCheck(name: "Psi-1", passed: True, detail: "ok"),
  ]
  let m =
    integrity.init()
    |> integrity.update(integrity.VerificationLoaded(
      hash: "sha256:abc",
      checks: checks,
      chain_ok: True,
      timestamp: "2026-04-07",
    ))
  m.loading |> should.equal(False)
  m.chain_valid |> should.equal(True)
  m.constitution_hash |> should.equal("sha256:abc")
  integrity.all_psi_passed(m) |> should.equal(True)
}

pub fn integrity_psi_failure_detected_test() {
  let checks = [
    integrity.PsiCheck(name: "Psi-0", passed: True, detail: "ok"),
    integrity.PsiCheck(name: "Psi-3", passed: False, detail: "BROKEN"),
  ]
  let m =
    integrity.init()
    |> integrity.update(integrity.VerificationLoaded(
      hash: "sha256:abc",
      checks: checks,
      chain_ok: False,
      timestamp: "2026-04-07",
    ))
  integrity.all_psi_passed(m) |> should.equal(False)
  m.chain_valid |> should.equal(False)
}

pub fn integrity_error_test() {
  let m =
    integrity.init()
    |> integrity.update(integrity.ErrorReceived("DB timeout"))
  m.error |> should.equal(Some("DB timeout"))
  m.loading |> should.equal(False)
}

pub fn integrity_tui_renders_nonempty_test() {
  let output = integrity_view.render(integrity.init())
  { string.length(output) > 10 } |> should.equal(True)
  string.contains(output, "INTEGRITY") |> should.equal(True)
}

// =============================================================================
// Evolution (L5 Cognitive)
// =============================================================================

pub fn evolution_init_defaults_test() {
  let m = evolution.init()
  m.entropy |> should.equal(0.0)
  m.cycle_count |> should.equal(0)
  m.loading |> should.equal(True)
}

pub fn evolution_metrics_loaded_test() {
  let m =
    evolution.init()
    |> evolution.update(evolution.MetricsLoaded(
      entropy: 2.67,
      cycles: 42,
      mutation: 0.03,
      fitness: 0.92,
      gen: 88,
      timestamp: "2026-04-07",
    ))
  m.entropy |> should.equal(2.67)
  m.cycle_count |> should.equal(42)
  m.fitness_score |> should.equal(0.92)
  evolution.entropy_healthy(m) |> should.equal(True)
}

pub fn evolution_low_entropy_unhealthy_test() {
  let m =
    evolution.init()
    |> evolution.update(evolution.MetricsLoaded(
      entropy: 1.5,
      cycles: 10,
      mutation: 0.1,
      fitness: 0.5,
      gen: 5,
      timestamp: "t",
    ))
  evolution.entropy_healthy(m) |> should.equal(False)
}

pub fn evolution_cycle_increments_test() {
  let m =
    evolution.init()
    |> evolution.update(evolution.MetricsLoaded(
      entropy: 2.5,
      cycles: 10,
      mutation: 0.02,
      fitness: 0.8,
      gen: 10,
      timestamp: "t",
    ))
    |> evolution.update(evolution.CycleCompleted(
      new_entropy: 2.7,
      new_fitness: 0.85,
    ))
  m.cycle_count |> should.equal(11)
  m.generation |> should.equal(11)
  m.entropy |> should.equal(2.7)
}

pub fn evolution_tui_renders_nonempty_test() {
  let output = evolution_view.render(evolution.init())
  { string.length(output) > 10 } |> should.equal(True)
  string.contains(output, "EVOLUTION") |> should.equal(True)
}

// =============================================================================
// Biomorphic (L5 Cognitive)
// =============================================================================

pub fn biomorphic_init_all_healthy_test() {
  let m = biomorphic.init()
  biomorphic.all_healthy(m) |> should.equal(True)
  m.overall_score |> should.equal(1.0)
}

pub fn biomorphic_subsystem_update_test() {
  let m =
    biomorphic.init()
    |> biomorphic.update(biomorphic.SubsystemUpdated(
      name: "neuro",
      status: "degraded",
      score: 0.6,
    ))
  biomorphic.all_healthy(m) |> should.equal(False)
  m.neuro.status |> should.equal("degraded")
}

pub fn biomorphic_tui_renders_nonempty_test() {
  let output = biomorphic_view.render(biomorphic.init())
  { string.length(output) > 10 } |> should.equal(True)
  string.contains(output, "BIOMORPHIC") |> should.equal(True)
}

// =============================================================================
// Homeostasis (L2 Component)
// =============================================================================

pub fn homeostasis_init_defaults_test() {
  let m = homeostasis.init()
  m.stable |> should.equal(False)
  m.pid.setpoint |> should.equal(1.0)
  m.loading |> should.equal(True)
}

pub fn homeostasis_pid_loaded_test() {
  let pid =
    homeostasis.PidState(
      setpoint: 1.0,
      actual: 0.99,
      error: 0.01,
      output: 0.05,
      kp: 1.0,
      ki: 0.1,
      kd: 0.05,
      integral: 0.5,
    )
  let m =
    homeostasis.init()
    |> homeostasis.update(homeostasis.PidLoaded(
      pid: pid,
      stable: True,
      convergence: 99.0,
      samples: 500,
    ))
  m.stable |> should.equal(True)
  m.convergence_pct |> should.equal(99.0)
  m.pid.actual |> should.equal(0.99)
}

pub fn homeostasis_pid_updated_test() {
  let m =
    homeostasis.init()
    |> homeostasis.update(homeostasis.PidUpdated(
      actual: 0.95,
      error: 0.05,
      output: 0.2,
    ))
  m.pid.actual |> should.equal(0.95)
  m.sample_count |> should.equal(1)
}

pub fn homeostasis_tui_renders_nonempty_test() {
  let output = homeostasis_view.render(homeostasis.init())
  { string.length(output) > 10 } |> should.equal(True)
  string.contains(output, "HOMEOSTASIS") |> should.equal(True)
}

// =============================================================================
// Bicameral (L0 Constitutional)
// =============================================================================

pub fn bicameral_init_no_consensus_test() {
  let m = bicameral.init()
  m.consensus_reached |> should.equal(False)
  m.guardian.vote |> should.equal("pending")
}

pub fn bicameral_2oo3_consensus_test() {
  let g =
    bicameral.Chamber(
      name: "Guardian",
      vote: "approve",
      timestamp: "t1",
      veto_count: 0,
    )
  let s =
    bicameral.Chamber(
      name: "Sentinel",
      vote: "approve",
      timestamp: "t2",
      veto_count: 0,
    )
  let c =
    bicameral.Chamber(
      name: "Cortex",
      vote: "reject",
      timestamp: "t3",
      veto_count: 1,
    )
  let m =
    bicameral.init()
    |> bicameral.update(bicameral.StateLoaded(
      guardian: g,
      sentinel: s,
      cortex: c,
      decisions: 10,
      vetoes: 1,
    ))
  m.consensus_reached |> should.equal(True)
  m.total_decisions |> should.equal(10)
}

pub fn bicameral_no_consensus_test() {
  let g =
    bicameral.Chamber(
      name: "Guardian",
      vote: "approve",
      timestamp: "t1",
      veto_count: 0,
    )
  let s =
    bicameral.Chamber(
      name: "Sentinel",
      vote: "reject",
      timestamp: "t2",
      veto_count: 1,
    )
  let c =
    bicameral.Chamber(
      name: "Cortex",
      vote: "reject",
      timestamp: "t3",
      veto_count: 1,
    )
  let m =
    bicameral.init()
    |> bicameral.update(bicameral.StateLoaded(
      guardian: g,
      sentinel: s,
      cortex: c,
      decisions: 5,
      vetoes: 2,
    ))
  m.consensus_reached |> should.equal(False)
}

pub fn bicameral_vote_received_test() {
  let m =
    bicameral.init()
    |> bicameral.update(bicameral.VoteReceived(
      chamber: "guardian",
      vote: "approve",
      timestamp: "2026-04-07",
    ))
  m.guardian.vote |> should.equal("approve")
}

pub fn bicameral_tui_renders_nonempty_test() {
  let output = bicameral_view.render(bicameral.init())
  { string.length(output) > 10 } |> should.equal(True)
  string.contains(output, "BICAMERAL") |> should.equal(True)
}

// =============================================================================
// Singularity (L7 Federation)
// =============================================================================

pub fn singularity_init_defaults_test() {
  let m = singularity.init()
  m.convergence_pct |> should.equal(0.0)
  m.safety_margin |> should.equal(1.0)
  singularity.within_safety_boundary(m) |> should.equal(True)
}

pub fn singularity_estimation_loaded_test() {
  let caps = [
    singularity.CapabilityMetric(name: "Reasoning", score: 0.72, trend: "up"),
    singularity.CapabilityMetric(name: "Autonomy", score: 0.31, trend: "stable"),
  ]
  let m =
    singularity.init()
    |> singularity.update(singularity.EstimationLoaded(
      convergence: 12.5,
      safety: 0.87,
      capability: 0.45,
      caps: caps,
      horizon: "indeterminate",
    ))
  m.convergence_pct |> should.equal(12.5)
  m.safety_margin |> should.equal(0.87)
  singularity.within_safety_boundary(m) |> should.equal(True)
}

pub fn singularity_unsafe_boundary_test() {
  let m =
    singularity.init()
    |> singularity.update(singularity.EstimationLoaded(
      convergence: 99.0,
      safety: 0.05,
      capability: 0.99,
      caps: [],
      horizon: "imminent",
    ))
  singularity.within_safety_boundary(m) |> should.equal(False)
}

pub fn singularity_capability_updated_test() {
  let m =
    singularity.init()
    |> singularity.update(singularity.CapabilityUpdated(
      name: "NewCap",
      score: 0.5,
      trend: "up",
    ))
  { list_len(m.capabilities) > 0 } |> should.equal(True)
}

pub fn singularity_tui_renders_nonempty_test() {
  let output = singularity_view.render(singularity.init())
  { string.length(output) > 10 } |> should.equal(True)
  string.contains(output, "SINGULARITY") |> should.equal(True)
}

// =============================================================================
// MCP Planning NIF integration
// =============================================================================

pub fn mcp_planning_nif_status_returns_json_test() {
  let result = planning_nif.status()
  { string.length(result) > 2 } |> should.be_true()
}

pub fn mcp_planning_nif_list_pending_returns_json_test() {
  let result = planning_nif.list_pending()
  { string.length(result) > 1 } |> should.be_true()
}

pub fn mcp_planning_nif_search_returns_json_test() {
  let result = planning_nif.search("test")
  { string.length(result) > 1 } |> should.be_true()
}

// Helper
fn list_len(lst: List(a)) -> Int {
  case lst {
    [] -> 0
    [_, ..rest] -> 1 + list_len(rest)
  }
}
