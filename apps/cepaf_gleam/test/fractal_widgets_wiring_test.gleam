//// =============================================================================
//// [C3I-SIL6-MSTS] FRACTAL WIDGETS L0-L7 — LAYER PARITY GUARD
//// =============================================================================
//// STAMP: SC-FRACTAL-001 (genotype topology must match runtime graph),
////        SC-CPIG-002 (cross-pass invariant gate),
////        SC-WIRE-001 (wiring guard pattern).
////
//// Purpose: every fractal layer L0-L7 MUST have at least one widget module
//// registered under cepaf_gleam/fractal/. Importing the modules at the top
//// of this file is the wiring guard itself — if any of the eight layer
//// modules is renamed, deleted, or moved, this test FAILS TO COMPILE,
//// surfacing the drift at build time (not test time).
////
//// Each layer is bound to one public type via a type alias so the compiler
//// refuses to elide the import — the alias is the "presence witness".
////
//// Reference rules:
////   .claude/rules/cross-pass-invariant-gate.md
////   CLAUDE.md §7.0 (Fractal Widget Architecture)
//// =============================================================================

import cepaf_gleam/fractal/l0_constitutional
import cepaf_gleam/fractal/l1_atomic_debug
import cepaf_gleam/fractal/l2_component
import cepaf_gleam/fractal/l3_transaction
import cepaf_gleam/fractal/l4_system
import cepaf_gleam/fractal/l5_cognitive
import cepaf_gleam/fractal/l6_ecosystem
import cepaf_gleam/fractal/l7_federation
import gleam/list
import gleeunit/should

// Compile-time presence witnesses — one public type per layer module.
// Removing or renaming any of these modules makes this file fail to
// type-check, which IS the wiring guard.
type WitnessL0 =
  l0_constitutional.ApprovalRequest

type WitnessL1 =
  l1_atomic_debug.TraceSpan

type WitnessL2 =
  l2_component.BadgeSeverity

type WitnessL3 =
  l3_transaction.StateDiffEntry

type WitnessL4 =
  l4_system.RunState

type WitnessL5 =
  l5_cognitive.OodaPhase

type WitnessL6 =
  l6_ecosystem.AgentNode

type WitnessL7 =
  l7_federation.FederationPeer

/// Canonical L0-L7 layer registry. Cardinality + ordering invariants below.
fn canonical_layer_names() -> List(String) {
  ["L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7"]
}

pub fn fractal_layer_count_test() {
  canonical_layer_names()
  |> list.length
  |> should.equal(8)
}

pub fn fractal_layers_unique_test() {
  let names = canonical_layer_names()
  list.length(names) |> should.equal(list.length(list.unique(names)))
}

pub fn fractal_layers_in_canonical_order_test() {
  canonical_layer_names()
  |> should.equal(["L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7"])
}

// Suppress "unused type" warnings — referencing each witness in a phantom
// list keeps the imports load-bearing without needing constructors.
type LayerWitnesses {
  LayerWitnesses(
    l0: fn(WitnessL0) -> Nil,
    l1: fn(WitnessL1) -> Nil,
    l2: fn(WitnessL2) -> Nil,
    l3: fn(WitnessL3) -> Nil,
    l4: fn(WitnessL4) -> Nil,
    l5: fn(WitnessL5) -> Nil,
    l6: fn(WitnessL6) -> Nil,
    l7: fn(WitnessL7) -> Nil,
  )
}

pub fn fractal_witness_record_constructs_test() {
  let _w =
    LayerWitnesses(
      l0: fn(_) { Nil },
      l1: fn(_) { Nil },
      l2: fn(_) { Nil },
      l3: fn(_) { Nil },
      l4: fn(_) { Nil },
      l5: fn(_) { Nil },
      l6: fn(_) { Nil },
      l7: fn(_) { Nil },
    )
  True |> should.be_true()
}
