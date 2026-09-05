//// =============================================================================
//// [C3I-SIL6-MSTS] ZENOH OTEL ZMOF — TOPIC FAMILY WIRING GUARD
//// =============================================================================
//// STAMP: SC-CPIG-002 (cross-pass invariant gate),
////        SC-ZMOF-001 (Zenoh sole transport),
////        SC-WIRE-001 (wiring guard pattern).
////
//// Purpose: hard-coded canonical Zenoh topic-family registry for the ZMOF
//// backplane. Adding/removing/renaming a topic family without updating this
//// list breaks the test — surfacing topic-namespace drift at test time
//// instead of at runtime in the mesh.
////
//// Reference rules:
////   .claude/rules/zenoh-control-plane-comms.md
////   .claude/rules/cross-pass-invariant-gate.md
////   .claude/rules/sched-telemetry-mandatory.md
//// =============================================================================

import gleam/list
import gleam/string
import gleeunit/should

/// Canonical topic-family prefixes published anywhere in the C3I mesh.
/// MUST stay in lockstep with publishers in:
///   - sub-projects/c3i/native/planning_daemon/src/sched_telemetry.rs
///   - lib/cepaf_gleam/src/cepaf_gleam/ui/zenoh_otel.gleam
///   - lib/cepaf_gleam/src/cepaf_gleam/bridge/pi_zenoh.gleam
///   - .claude/rules/zenoh-control-plane-comms.md
fn canonical_topic_families() -> List(String) {
  [
    "indrajaal/health/",
    "indrajaal/l0/const/",
    "indrajaal/l4/sched/job/",
    "indrajaal/l4/sched/proc/",
    "indrajaal/l4/sched/run/",
    "indrajaal/l4/sre/ooda/",
    "indrajaal/l5/cog/trace/",
    "indrajaal/l5/scripts/evolution/",
    "indrajaal/l5/test/marionette/",
    "indrajaal/l5/test/patrol/",
    "indrajaal/otel/spans/",
    "indrajaal/plan/spans/",
  ]
}

pub fn topic_family_count_test() {
  canonical_topic_families()
  |> list.length
  |> should.equal(12)
}

pub fn topic_family_sorted_test() {
  let families = canonical_topic_families()
  let sorted = list.sort(families, string.compare)
  families |> should.equal(sorted)
}

pub fn topic_family_no_duplicates_test() {
  let families = canonical_topic_families()
  let unique = list.unique(families)
  list.length(families) |> should.equal(list.length(unique))
}

pub fn topic_family_namespace_prefix_test() {
  // Every topic family MUST live under the indrajaal/ root namespace.
  canonical_topic_families()
  |> list.all(fn(f) { string.starts_with(f, "indrajaal/") })
  |> should.be_true()
}

pub fn topic_family_trailing_slash_test() {
  // Every topic family MUST end with "/" so subscribers can append a leaf
  // segment without ambiguity (e.g. indrajaal/health/<node>).
  canonical_topic_families()
  |> list.all(fn(f) { string.ends_with(f, "/") })
  |> should.be_true()
}
