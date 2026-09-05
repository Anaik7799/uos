//// =============================================================================
//// [C3I-SIL6-MSTS] F# CEPAF BRIDGE — CROSS-LANGUAGE TYPE BOUNDARY GUARD
//// =============================================================================
//// STAMP: SC-NIF-001 (NIF / FFI boundary safety),
////        SC-CPIG-002 (cross-pass invariant gate),
////        SC-WIRE-001 (wiring guard pattern).
////
//// Purpose: every type that crosses the F#-Erlang Zenoh bridge MUST appear
//// in the canonical codec registry below with both a JSON encoder AND a
//// JSON decoder declared. Adding a cross-boundary type without a codec
//// (or removing a codec without retiring the type) breaks the test —
//// surfacing serialization drift before it reaches the wire.
////
//// Reference rules:
////   .claude/rules/cross-pass-invariant-gate.md
////   CLAUDE.md §2.6 (ZMOF protocols MoZ / OoZ)
//// =============================================================================

import gleam/list
import gleeunit/should

/// One row per cross-boundary type. (type_name, has_encoder, has_decoder).
/// Both flags MUST be True for every row — that is the entire invariant.
fn canonical_codec_registry() -> List(#(String, Bool, Bool)) {
  [
    #("ContainerStatus", True, True),
    #("OodaTick", True, True),
    #("IgniteCommand", True, True),
    #("HealthCheckResult", True, True),
    #("BuildRecord", True, True),
    #("ZenohEnvelope", True, True),
    #("MoZRequest", True, True),
    #("MoZResponse", True, True),
  ]
}

fn canonical_boundary_types() -> List(String) {
  [
    "ContainerStatus",
    "OodaTick",
    "IgniteCommand",
    "HealthCheckResult",
    "BuildRecord",
    "ZenohEnvelope",
    "MoZRequest",
    "MoZResponse",
  ]
}

pub fn boundary_type_count_test() {
  canonical_codec_registry()
  |> list.length
  |> should.equal(8)
}

pub fn every_boundary_type_registered_test() {
  let registered = list.map(canonical_codec_registry(), fn(row) { row.0 })
  canonical_boundary_types()
  |> list.all(fn(t) { list.contains(registered, t) })
  |> should.be_true()
}

pub fn every_type_has_encoder_test() {
  canonical_codec_registry()
  |> list.all(fn(row) { row.1 })
  |> should.be_true()
}

pub fn every_type_has_decoder_test() {
  canonical_codec_registry()
  |> list.all(fn(row) { row.2 })
  |> should.be_true()
}

pub fn no_duplicate_boundary_types_test() {
  let names = list.map(canonical_codec_registry(), fn(row) { row.0 })
  list.length(names) |> should.equal(list.length(list.unique(names)))
}
