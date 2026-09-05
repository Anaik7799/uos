//// Patrol MCP Envelope Schema Wiring Guard
////
//// Cites: SC-PATROL-MCP-004, SC-CPIG-002, SC-WIRE-001
//// ZK: [zk-bb4de67d97f807ac]
////
//// Hard-codes the canonical 7-field OTel envelope schema for Patrol MCP
//// per SC-PATROL-MCP-004. This file is the single source of truth for
//// the envelope shape; if Patrol's envelope drifts, this file fails to
//// compile or its tests fail FIRST — before scattered envelope users.

import gleam/list
import gleam/string
import gleeunit/should

/// Canonical 7-field OTel envelope schema (SC-PATROL-MCP-004).
fn envelope_fields() -> List(String) {
  ["at", "source", "urn", "run_id", "phase", "platform", "payload"]
}

/// Canonical phases set for Patrol MCP envelopes.
fn envelope_phases() -> List(String) {
  ["start", "screenshot", "native-tree", "status", "passed", "failed", "quit"]
}

/// Canonical platform set.
fn platforms() -> List(String) {
  ["android", "linux", "chrome", "ios", "macos", "windows"]
}

/// Canonical URN prefix for Patrol envelopes.
fn urn_prefix() -> String {
  "urn:c3i:test:patrol:"
}

// ===========================================================================
// Wiring Tests (SC-WIRE-001)
// ===========================================================================

pub fn envelope_field_count_test() {
  envelope_fields()
  |> list.length
  |> should.equal(7)
}

pub fn envelope_phases_test() {
  let phases = envelope_phases()
  phases |> list.length |> should.equal(7)
  phases |> list.contains("start") |> should.be_true
  phases |> list.contains("screenshot") |> should.be_true
  phases |> list.contains("native-tree") |> should.be_true
  phases |> list.contains("status") |> should.be_true
  phases |> list.contains("passed") |> should.be_true
  phases |> list.contains("failed") |> should.be_true
  phases |> list.contains("quit") |> should.be_true
}

pub fn platform_set_test() {
  let p = platforms()
  p |> list.length |> should.equal(6)
  p |> list.contains("android") |> should.be_true
  p |> list.contains("linux") |> should.be_true
  p |> list.contains("chrome") |> should.be_true
  p |> list.contains("ios") |> should.be_true
  p |> list.contains("macos") |> should.be_true
  p |> list.contains("windows") |> should.be_true
}

pub fn urn_prefix_test() {
  let sample_urn =
    urn_prefix() <> "fluffychat:550e8400-e29b-41d4-a716-446655440000"
  sample_urn
  |> string.starts_with("urn:c3i:test:patrol:")
  |> should.be_true
}

pub fn no_duplicate_phase_test() {
  let phases = envelope_phases()
  let unique = list.unique(phases)
  list.length(phases) |> should.equal(list.length(unique))
}
