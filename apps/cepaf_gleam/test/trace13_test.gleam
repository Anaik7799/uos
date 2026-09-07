// =============================================================================
// [C3I-SIL6-MSTS] 13-DIMENSIONAL TRACEABILITY TEST SUITE (SC-TRACE-001)
// =============================================================================
// Verifies Lean 4 Traceability.lean theorems, mathematical invariant conservation,
// fail-closed trust indicators, and non-escalation proofs.
// =============================================================================

import cepaf_gleam/c3i/trace13.{
  type TraceCoordinate, Admitted, Discovered, GleamControlPlane, Implemented,
  InvariantLost, L0MicroKernelAllocator, Lean4Theorem, Operational, Passed,
  RootSupervisor, SandboxedWorker, SubsystemSupervisor, SupervisedBoundary,
  SynchronousNif, TraceCoordinate, UnauthorizedEscalation, Verified,
  ZigRustRuntimePlane,
}
import gleam/result
import gleeunit/should

fn create_sample_coord() -> TraceCoordinate {
  TraceCoordinate(
    layer: L0MicroKernelAllocator,
    component: "allocator",
    feature: "vfs_ring_buffer",
    surface: Operational,
    modal: SynchronousNif,
    plane: ZigRustRuntimePlane,
    carrier: "c3i_nif:allocator_init",
    profile: Lean4Theorem,
    semantics: "Deterministic lockless arena allocation with zero GC overhead",
    operations: ["allocate", "free", "reset"],
    telemetry: ["alloc_bytes_total", "free_bytes_total"],
    invariants: ["INV_NO_LEAK", "INV_BOUNDED_US"],
    authority: SubsystemSupervisor,
    status: Admitted,
  )
}

pub fn trust_indicator_test() {
  // Discovered, Classified, Mapped, Implemented, Built, Executed, Passed -> 0
  trace13.trust_indicator(Discovered) |> should.equal(0)
  trace13.trust_indicator(Implemented) |> should.equal(0)
  trace13.trust_indicator(Passed) |> should.equal(0)

  // Verified, Admitted -> 1 (Fail-Closed indicatorTrust theorem)
  trace13.trust_indicator(Verified) |> should.equal(1)
  trace13.trust_indicator(Admitted) |> should.equal(1)
}

pub fn well_formedness_test() {
  let valid = create_sample_coord()
  trace13.is_well_formed(valid) |> should.be_true
  trace13.validate_wf(valid) |> should.be_ok

  // Empty invariants must fail well-formedness
  let invalid_invariants = TraceCoordinate(..valid, invariants: [])
  trace13.is_well_formed(invalid_invariants) |> should.be_false
  trace13.validate_wf(invalid_invariants) |> should.be_error

  // Empty operations must fail well-formedness
  let invalid_ops = TraceCoordinate(..valid, operations: [])
  trace13.is_well_formed(invalid_ops) |> should.be_false
  trace13.validate_wf(invalid_ops) |> should.be_error

  // Admitted on GleamControlPlane with SandboxedWorker must fail
  let invalid_auth =
    TraceCoordinate(
      ..valid,
      plane: GleamControlPlane,
      status: Admitted,
      authority: SandboxedWorker,
    )
  trace13.is_well_formed(invalid_auth) |> should.be_false
  trace13.validate_wf(invalid_auth) |> should.be_error

  // Admitted on GleamControlPlane with RootSupervisor must pass
  let valid_root =
    TraceCoordinate(
      ..valid,
      plane: GleamControlPlane,
      status: Admitted,
      authority: RootSupervisor,
    )
  trace13.is_well_formed(valid_root) |> should.be_true
}

pub fn invariant_conservation_law_test() {
  let src = create_sample_coord()

  // Target preserves all invariants (plus adds a new one) -> Valid
  let tgt_valid =
    TraceCoordinate(
      ..src,
      invariants: ["INV_NO_LEAK", "INV_BOUNDED_US", "INV_PARITY_CHECKED"],
      status: Admitted,
    )
  trace13.conserves_invariants(src, tgt_valid) |> should.be_ok
  trace13.is_valid_transition(src, tgt_valid) |> should.be_true

  // Target loses an invariant -> InvariantLost error (Delta T_13 != 0 violation)
  let tgt_invalid =
    TraceCoordinate(..src, invariants: ["INV_NO_LEAK"], status: Admitted)
  trace13.conserves_invariants(src, tgt_invalid) |> should.be_error
  trace13.validate_transition(src, tgt_invalid)
  |> should.equal(
    Error(InvariantLost(
      "invariant_conservation_violation: lost invariant INV_BOUNDED_US",
    )),
  )
}

pub fn authority_non_escalation_test() {
  let sandboxed_src =
    TraceCoordinate(
      ..create_sample_coord(),
      authority: SandboxedWorker,
      plane: SupervisedBoundary,
      status: Implemented,
    )

  // Transition to SandboxedWorker -> OK
  let tgt_worker = TraceCoordinate(..sandboxed_src, status: Verified)
  trace13.prevents_escalation(sandboxed_src, tgt_worker) |> should.be_ok

  // Silent escalation from SandboxedWorker to RootSupervisor -> Blocked by Lean non-escalation theorem
  let tgt_escalated =
    TraceCoordinate(
      ..sandboxed_src,
      authority: RootSupervisor,
      plane: GleamControlPlane,
      status: Admitted,
    )
  trace13.prevents_escalation(sandboxed_src, tgt_escalated) |> should.be_error
  trace13.validate_transition(sandboxed_src, tgt_escalated)
  |> should.equal(Error(UnauthorizedEscalation(SandboxedWorker, RootSupervisor)))
}

pub fn uri_and_zenoh_topic_test() {
  let coord = create_sample_coord()
  let uri = trace13.to_uri(coord)
  uri
  |> should.equal(
    "uos://L0/runtime/allocator/vfs_ring_buffer?surface=operational&modal=sync_nif&profile=lean4&auth=subsystem_supervisor&status=admitted",
  )

  let topic = trace13.to_zenoh_topic(coord)
  topic |> should.equal("indrajaal/l0/runtime/allocator/vfs_ring_buffer")
}

pub fn json_roundtrip_test() {
  let coord = create_sample_coord()
  let json_str = trace13.to_json_string(coord)

  let decoded = trace13.from_json_string(json_str)
  decoded |> should.be_ok
  let unwrapped = result.unwrap(decoded, coord)
  unwrapped.component |> should.equal("allocator")
  unwrapped.feature |> should.equal("vfs_ring_buffer")
  unwrapped.invariants |> should.equal(["INV_NO_LEAK", "INV_BOUNDED_US"])
}
