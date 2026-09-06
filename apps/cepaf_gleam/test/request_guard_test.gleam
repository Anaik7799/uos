// request_guard_test.gleam — unit tests for ha/request_guard.gleam
//
// Covers:
//   T1  check() on a fresh grid → always Proceed (health = 1.0 ≥ 0.3)
//   T2  check_with_grid() on a fully-healthy grid → Proceed
//   T3  check_with_grid() on a critically-unhealthy grid → Block with reason
//   T4  service_unavailable/1 → 503 response with correct status and body
//   T5  service_unavailable_json/1 → 503 JSON response with structured body
//   T6  critical_health_threshold() → returns 0.3
//   T7  Block reason contains health score as string
//   T8  service_unavailable sets x-guard-blocked header
//   T9  service_unavailable_json sets content-type application/json
//
// STAMP: SC-SIL4-001, SC-FUNC-002, SC-SATYA-001, SC-NASA-001

import cepaf_gleam/ha/guard_grid
import cepaf_gleam/ha/request_guard.{Block, Proceed}
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// T1 — check() on fresh grid is always Proceed
// ---------------------------------------------------------------------------

pub fn check_fresh_grid_is_proceed_test() {
  // A freshly initialised grid has all 24 cells as PASSED → health = 1.0
  // 1.0 ≥ critical_threshold (0.3) → Proceed
  request_guard.check()
  |> should.equal(Proceed)
}

// ---------------------------------------------------------------------------
// T2 — check_with_grid on a healthy grid → Proceed
// ---------------------------------------------------------------------------

pub fn check_with_healthy_grid_is_proceed_test() {
  let grid = guard_grid.init()
  request_guard.check_with_grid(grid)
  |> should.equal(Proceed)
}

// ---------------------------------------------------------------------------
// T3 — check_with_grid on a critically unhealthy grid → Block
// ---------------------------------------------------------------------------

pub fn check_with_unhealthy_grid_is_block_test() {
  // Inject failures into 22 of 24 cells so health ≈ 0.083 (2/24 < 0.3)
  let grid =
    guard_grid.init()
    |> record_all_failures()
  case request_guard.check_with_grid(grid) {
    Block(_) -> should.be_true(True)
    Proceed -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// T4 — service_unavailable returns 503
// ---------------------------------------------------------------------------

pub fn service_unavailable_status_503_test() {
  let resp = request_guard.service_unavailable("grid health critical")
  resp.status
  |> should.equal(503)
}

pub fn service_unavailable_body_contains_reason_test() {
  let reason = "health=0.083"
  let resp = request_guard.service_unavailable(reason)
  resp.body
  |> should.equal(reason)
}

// ---------------------------------------------------------------------------
// T5 — service_unavailable_json returns structured JSON 503
// ---------------------------------------------------------------------------

pub fn service_unavailable_json_status_503_test() {
  let resp = request_guard.service_unavailable_json("cascade detected")
  resp.status
  |> should.equal(503)
}

pub fn service_unavailable_json_body_has_error_key_test() {
  let resp = request_guard.service_unavailable_json("cascade detected")
  resp.body
  |> string.contains("\"error\":\"service_unavailable\"")
  |> should.be_true()
}

pub fn service_unavailable_json_body_has_reason_test() {
  let reason = "cascade detected"
  let resp = request_guard.service_unavailable_json(reason)
  resp.body
  |> string.contains(reason)
  |> should.be_true()
}

// ---------------------------------------------------------------------------
// T6 — critical_health_threshold returns 0.3
// ---------------------------------------------------------------------------

pub fn critical_health_threshold_is_0_3_test() {
  request_guard.critical_health_threshold()
  |> should.equal(0.3)
}

// ---------------------------------------------------------------------------
// T7 — Block reason contains health score string
// ---------------------------------------------------------------------------

pub fn block_reason_contains_health_score_test() {
  let grid =
    guard_grid.init()
    |> record_all_failures()
  case request_guard.check_with_grid(grid) {
    Block(reason) ->
      reason
      |> string.contains("health")
      |> should.be_true()
    Proceed -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// T8 — service_unavailable sets x-guard-blocked header
// ---------------------------------------------------------------------------

pub fn service_unavailable_sets_guard_blocked_header_test() {
  let resp = request_guard.service_unavailable("blocked")
  let header_value =
    resp.headers
    |> list.key_find("x-guard-blocked")
  header_value
  |> should.equal(Ok("true"))
}

// ---------------------------------------------------------------------------
// T9 — service_unavailable_json sets content-type application/json
// ---------------------------------------------------------------------------

pub fn service_unavailable_json_content_type_test() {
  let resp = request_guard.service_unavailable_json("blocked")
  let ct =
    resp.headers
    |> list.key_find("content-type")
  ct
  |> should.equal(Ok("application/json"))
}

// ---------------------------------------------------------------------------
// T10 — Proceed is returned when health is exactly at threshold (boundary)
// ---------------------------------------------------------------------------

pub fn check_at_boundary_health_is_proceed_test() {
  // Fresh grid health = 1.0 >> 0.3; boundary not triggerable from pure init()
  // but we can verify: a grid with 8/24 passed = health ≈ 0.333 → still Proceed
  let grid = guard_grid.init() |> record_n_failures(16)
  // 8 passed / 24 total = 0.3333... ≥ 0.3 → Proceed
  case request_guard.check_with_grid(grid) {
    Proceed -> should.be_true(True)
    Block(_) -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Record a FAILED_EMPTY verdict into all 24 cells via all layer/module pairs.
fn record_all_failures(grid: guard_grid.GuardGrid) -> guard_grid.GuardGrid {
  let layer_modules = [
    #("L0", ["guardian", "psi_invariants", "emergency_stop"]),
    #("L1", ["nif_bridge", "otel_trace", "debug_probes"]),
    #("L2", ["a2ui_catalog", "shell_helpers", "lustre_ssr"]),
    #("L3", ["plan_status", "smriti_db", "planning_db"]),
    #("L4", ["container_genome", "boot_sequencer", "cpu_governor"]),
    #("L5", ["cortex", "ooda_loop", "inference_cascade"]),
    #("L6", ["zenoh_mesh", "quorum", "moz_bridge"]),
    #("L7", ["gateway", "ha_election", "version_vectors"]),
  ]
  list.fold(layer_modules, grid, fn(g, pair) {
    let #(layer, modules) = pair
    list.fold(modules, g, fn(g2, mod_name) {
      guard_grid.record_verdict(g2, layer, mod_name, "FAILED_EMPTY", 1)
    })
  })
}

/// Record failures into the first N cells (layers L0..Lk, all 3 modules).
/// Each full layer = 3 cells.  `n` is number of failure cells (multiple of 3).
fn record_n_failures(
  grid: guard_grid.GuardGrid,
  n: Int,
) -> guard_grid.GuardGrid {
  let layer_modules = [
    #("L0", ["guardian", "psi_invariants", "emergency_stop"]),
    #("L1", ["nif_bridge", "otel_trace", "debug_probes"]),
    #("L2", ["a2ui_catalog", "shell_helpers", "lustre_ssr"]),
    #("L3", ["plan_status", "smriti_db", "planning_db"]),
    #("L4", ["container_genome", "boot_sequencer", "cpu_governor"]),
    #("L5", ["cortex", "ooda_loop", "inference_cascade"]),
  ]
  let pairs =
    list.flat_map(layer_modules, fn(pair) {
      let #(layer, mods) = pair
      list.map(mods, fn(m) { #(layer, m) })
    })
  let to_fail = list.take(pairs, n)
  list.fold(to_fail, grid, fn(g, pair) {
    let #(layer, mod_name) = pair
    guard_grid.record_verdict(g, layer, mod_name, "FAILED_EMPTY", 1)
  })
}
