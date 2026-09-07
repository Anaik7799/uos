// =============================================================================
// [C3I-SIL6-MSTS] 13-DIMENSIONAL TRACEABILITY ALGEBRA (SC-TRACE-001)
// =============================================================================
// Direct Gleam implementation of formal/lean/Traceability.lean:
// 1. 13-Dimensional Coordinate Vector:
//    <Layer, Comp, Feat, Surf, Modal, Plane, Carrier, Prof, Sem, Ops, Obs, Inv, Auth>
// 2. 10 Fractal Surfaces (L0 to L9).
// 3. Invariant Conservation Law (Delta T_13 = 0).
// 4. Fail-Closed Zero-Trust Indicator: Unverified claims reject closed.
// 5. Non-Escalation of Authority across architectural planes.
// =============================================================================

import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

// -----------------------------------------------------------------------------
// 1. Types & Enums Matching Lean 4 Traceability.lean
// -----------------------------------------------------------------------------

pub type FractalLayer {
  L0MicroKernelAllocator
  L1TermRepJit
  L2InstructionDispatch
  L3DifferentialByteParity
  L4TransactionalConcurrency
  L5ActorSupervision
  L6ZeroTrustGate
  L7ProbabilisticTelemetry
  L8KnowledgeLivingOntology
  L9AutonomousFederation
}

pub type ArchitecturalPlane {
  GleamControlPlane
  ZigRustRuntimePlane
  HermesEvidencePlane
  SupervisedBoundary
}

pub type OperationalSurface {
  Development
  Operational
  Evolutionary
}

pub type Modality {
  SynchronousNif
  ZenohQueryable
  ActorMessage
  PipeStream
}

pub type FormalProfile {
  Lean4Theorem
  RocqLemma
  GospelContract
  QuintModel
  VerifiedAuditReceipt
}

pub type AuthorityRole {
  RootSupervisor
  SubsystemSupervisor
  SandboxedWorker
  ExternalObserver
}

pub type VerificationStatus {
  Discovered
  Classified
  Mapped
  Implemented
  Built
  Executed
  Passed
  Verified
  Admitted
}

pub type TraceCoordinate {
  TraceCoordinate(
    layer: FractalLayer,
    component: String,
    feature: String,
    surface: OperationalSurface,
    modal: Modality,
    plane: ArchitecturalPlane,
    carrier: String,
    profile: FormalProfile,
    semantics: String,
    operations: List(String),
    telemetry: List(String),
    invariants: List(String),
    authority: AuthorityRole,
    status: VerificationStatus,
  )
}

pub type TransitionError {
  SourceNotWellFormed(reason: String)
  TargetNotWellFormed(reason: String)
  InvariantLost(lost_invariant: String)
  UnauthorizedEscalation(from: AuthorityRole, to: AuthorityRole)
}

// -----------------------------------------------------------------------------
// 2. String Conversions & Parsers
// -----------------------------------------------------------------------------

pub fn layer_to_string(layer: FractalLayer) -> String {
  case layer {
    L0MicroKernelAllocator -> "L0"
    L1TermRepJit -> "L1"
    L2InstructionDispatch -> "L2"
    L3DifferentialByteParity -> "L3"
    L4TransactionalConcurrency -> "L4"
    L5ActorSupervision -> "L5"
    L6ZeroTrustGate -> "L6"
    L7ProbabilisticTelemetry -> "L7"
    L8KnowledgeLivingOntology -> "L8"
    L9AutonomousFederation -> "L9"
  }
}

pub fn layer_from_string(s: String) -> Result(FractalLayer, String) {
  case string.uppercase(s) {
    "L0" | "L0_MICROKERNEL_ALLOCATOR" -> Ok(L0MicroKernelAllocator)
    "L1" | "L1_TERMREP_JIT" -> Ok(L1TermRepJit)
    "L2" | "L2_INSTRUCTION_DISPATCH" -> Ok(L2InstructionDispatch)
    "L3" | "L3_DIFFERENTIAL_BYTE_PARITY" -> Ok(L3DifferentialByteParity)
    "L4" | "L4_TRANSACTIONAL_CONCURRENCY" -> Ok(L4TransactionalConcurrency)
    "L5" | "L5_ACTOR_SUPERVISION" -> Ok(L5ActorSupervision)
    "L6" | "L6_ZERO_TRUST_GATE" -> Ok(L6ZeroTrustGate)
    "L7" | "L7_PROBABILISTIC_TELEMETRY" -> Ok(L7ProbabilisticTelemetry)
    "L8" | "L8_KNOWLEDGE_LIVING_ONTOLOGY" -> Ok(L8KnowledgeLivingOntology)
    "L9" | "L9_AUTONOMOUS_FEDERATION" -> Ok(L9AutonomousFederation)
    _ -> Error("unknown_fractal_layer: " <> s)
  }
}

pub fn plane_to_string(plane: ArchitecturalPlane) -> String {
  case plane {
    GleamControlPlane -> "control"
    ZigRustRuntimePlane -> "runtime"
    HermesEvidencePlane -> "evidence"
    SupervisedBoundary -> "boundary"
  }
}

pub fn plane_from_string(s: String) -> Result(ArchitecturalPlane, String) {
  case string.lowercase(s) {
    "control" | "gleam_control_plane" | "gleamcontrolplane" ->
      Ok(GleamControlPlane)
    "runtime" | "zig_rust_runtime_plane" | "zigrustruntimeplane" ->
      Ok(ZigRustRuntimePlane)
    "evidence" | "hermes_evidence_plane" | "hermesevidenceplane" ->
      Ok(HermesEvidencePlane)
    "boundary" | "supervised_boundary" | "supervisedboundary" ->
      Ok(SupervisedBoundary)
    _ -> Error("unknown_architectural_plane: " <> s)
  }
}

pub fn surface_to_string(surf: OperationalSurface) -> String {
  case surf {
    Development -> "development"
    Operational -> "operational"
    Evolutionary -> "evolutionary"
  }
}

pub fn surface_from_string(s: String) -> Result(OperationalSurface, String) {
  case string.lowercase(s) {
    "development" | "dev" -> Ok(Development)
    "operational" | "ops" -> Ok(Operational)
    "evolutionary" | "evo" -> Ok(Evolutionary)
    _ -> Error("unknown_operational_surface: " <> s)
  }
}

pub fn modal_to_string(m: Modality) -> String {
  case m {
    SynchronousNif -> "sync_nif"
    ZenohQueryable -> "zenoh_queryable"
    ActorMessage -> "actor_message"
    PipeStream -> "pipe_stream"
  }
}

pub fn modal_from_string(s: String) -> Result(Modality, String) {
  case string.lowercase(s) {
    "sync_nif" | "synchronousnif" | "nif" -> Ok(SynchronousNif)
    "zenoh_queryable" | "zenohqueryable" | "zenoh" -> Ok(ZenohQueryable)
    "actor_message" | "actormessage" | "beam" -> Ok(ActorMessage)
    "pipe_stream" | "pipestream" | "pipe" -> Ok(PipeStream)
    _ -> Error("unknown_modality: " <> s)
  }
}

pub fn profile_to_string(p: FormalProfile) -> String {
  case p {
    Lean4Theorem -> "lean4"
    RocqLemma -> "rocq"
    GospelContract -> "gospel"
    QuintModel -> "quint"
    VerifiedAuditReceipt -> "receipt"
  }
}

pub fn profile_from_string(s: String) -> Result(FormalProfile, String) {
  case string.lowercase(s) {
    "lean4" | "lean4_theorem" | "lean4theorem" -> Ok(Lean4Theorem)
    "rocq" | "rocq_lemma" | "rocqlemma" -> Ok(RocqLemma)
    "gospel" | "gospel_contract" | "gospelcontract" -> Ok(GospelContract)
    "quint" | "quint_model" | "quintmodel" -> Ok(QuintModel)
    "receipt" | "verified_audit_receipt" | "verifiedauditreceipt" ->
      Ok(VerifiedAuditReceipt)
    _ -> Error("unknown_formal_profile: " <> s)
  }
}

pub fn authority_to_string(a: AuthorityRole) -> String {
  case a {
    RootSupervisor -> "root_supervisor"
    SubsystemSupervisor -> "subsystem_supervisor"
    SandboxedWorker -> "sandboxed_worker"
    ExternalObserver -> "external_observer"
  }
}

pub fn authority_from_string(s: String) -> Result(AuthorityRole, String) {
  case string.lowercase(s) {
    "root_supervisor" | "rootsupervisor" | "root" -> Ok(RootSupervisor)
    "subsystem_supervisor" | "subsystemsupervisor" | "subsystem" ->
      Ok(SubsystemSupervisor)
    "sandboxed_worker" | "sandboxedworker" | "worker" -> Ok(SandboxedWorker)
    "external_observer" | "externalobserver" | "observer" ->
      Ok(ExternalObserver)
    _ -> Error("unknown_authority_role: " <> s)
  }
}

pub fn status_to_string(st: VerificationStatus) -> String {
  case st {
    Discovered -> "discovered"
    Classified -> "classified"
    Mapped -> "mapped"
    Implemented -> "implemented"
    Built -> "built"
    Executed -> "executed"
    Passed -> "passed"
    Verified -> "verified"
    Admitted -> "admitted"
  }
}

pub fn status_from_string(s: String) -> Result(VerificationStatus, String) {
  case string.lowercase(s) {
    "discovered" -> Ok(Discovered)
    "classified" -> Ok(Classified)
    "mapped" -> Ok(Mapped)
    "implemented" -> Ok(Implemented)
    "built" -> Ok(Built)
    "executed" -> Ok(Executed)
    "passed" -> Ok(Passed)
    "verified" -> Ok(Verified)
    "admitted" -> Ok(Admitted)
    _ -> Error("unknown_verification_status: " <> s)
  }
}

// -----------------------------------------------------------------------------
// 3. Mathematical Verification & Invariant Proofs (Traceability.lean)
// -----------------------------------------------------------------------------

/// Fail-Closed Zero-Trust Indicator: Returns 1 for Verified or Admitted, 0 otherwise.
/// Never grants operational trust to planned, mock, or unrun execution states.
pub fn trust_indicator(status: VerificationStatus) -> Int {
  case status {
    Verified -> 1
    Admitted -> 1
    _ -> 0
  }
}

pub fn is_trusted(coord: TraceCoordinate) -> Bool {
  trust_indicator(coord.status) == 1
}

/// Well-formedness invariant:
/// 1. invariants list must be non-empty.
/// 2. operations list must be non-empty.
/// 3. If Admitted and on GleamControlPlane, authority must be RootSupervisor or SubsystemSupervisor.
pub fn is_well_formed(coord: TraceCoordinate) -> Bool {
  let has_invariants = !list.is_empty(coord.invariants)
  let has_operations = !list.is_empty(coord.operations)

  let authority_ok = case coord.status, coord.plane {
    Admitted, GleamControlPlane ->
      case coord.authority {
        RootSupervisor | SubsystemSupervisor -> True
        _ -> False
      }
    _, _ -> True
  }

  has_invariants && has_operations && authority_ok
}

pub fn validate_wf(coord: TraceCoordinate) -> Result(Nil, String) {
  case list.is_empty(coord.invariants) {
    True -> Error("well_formedness_error: invariants list cannot be empty")
    False ->
      case list.is_empty(coord.operations) {
        True -> Error("well_formedness_error: operations list cannot be empty")
        False ->
          case coord.status, coord.plane, coord.authority {
            Admitted, GleamControlPlane, SandboxedWorker
            | Admitted, GleamControlPlane, ExternalObserver
            ->
              Error(
                "well_formedness_error: Admitted GleamControlPlane requires RootSupervisor or SubsystemSupervisor",
              )
            _, _, _ -> Ok(Nil)
          }
      }
  }
}

/// Invariant Conservation Law: Delta T_13 = 0.
/// Target state must preserve ALL invariants present in source state.
pub fn conserves_invariants(
  src: TraceCoordinate,
  tgt: TraceCoordinate,
) -> Result(Nil, String) {
  let missing =
    list.filter(src.invariants, fn(inv) { !list.contains(tgt.invariants, inv) })

  case missing {
    [] -> Ok(Nil)
    [first_lost, ..] ->
      Error("invariant_conservation_violation: lost invariant " <> first_lost)
  }
}

/// Non-Escalation Proof: Sandboxed workers cannot silently escalate to RootSupervisor.
pub fn prevents_escalation(
  src: TraceCoordinate,
  tgt: TraceCoordinate,
) -> Result(Nil, String) {
  case src.authority, tgt.authority {
    SandboxedWorker, RootSupervisor ->
      Error(
        "unauthorized_authority_escalation: SandboxedWorker cannot transition to RootSupervisor",
      )
    _, _ -> Ok(Nil)
  }
}

/// State transition validation (Traceability.lean theorem transition_preserves_wf):
/// Checks source wf -> target wf && invariant conservation && authority non-escalation.
pub fn validate_transition(
  src: TraceCoordinate,
  tgt: TraceCoordinate,
) -> Result(TraceCoordinate, TransitionError) {
  case validate_wf(src) {
    Error(err) -> Error(SourceNotWellFormed(err))
    Ok(Nil) ->
      case validate_wf(tgt) {
        Error(err) -> Error(TargetNotWellFormed(err))
        Ok(Nil) ->
          case conserves_invariants(src, tgt) {
            Error(err) -> Error(InvariantLost(err))
            Ok(Nil) ->
              case prevents_escalation(src, tgt) {
                Error(_) ->
                  Error(UnauthorizedEscalation(src.authority, tgt.authority))
                Ok(Nil) -> Ok(tgt)
              }
          }
      }
  }
}

pub fn is_valid_transition(src: TraceCoordinate, tgt: TraceCoordinate) -> Bool {
  result.is_ok(validate_transition(src, tgt))
}

// -----------------------------------------------------------------------------
// 4. URI Serialization & Zenoh Topic Mapping
// -----------------------------------------------------------------------------

/// Format as canonical URI:
/// uos://{layer}/{plane}/{component}/{feature}?surface={surf}&modal={modal}&profile={prof}&auth={auth}&status={status}
pub fn to_uri(c: TraceCoordinate) -> String {
  "uos://"
  <> layer_to_string(c.layer)
  <> "/"
  <> plane_to_string(c.plane)
  <> "/"
  <> c.component
  <> "/"
  <> c.feature
  <> "?surface="
  <> surface_to_string(c.surface)
  <> "&modal="
  <> modal_to_string(c.modal)
  <> "&profile="
  <> profile_to_string(c.profile)
  <> "&auth="
  <> authority_to_string(c.authority)
  <> "&status="
  <> status_to_string(c.status)
}

/// Format as canonical Zenoh telemetry topic:
/// indrajaal/{layer}/{plane}/{component}/{feature}
pub fn to_zenoh_topic(c: TraceCoordinate) -> String {
  "indrajaal/"
  <> string.lowercase(layer_to_string(c.layer))
  <> "/"
  <> plane_to_string(c.plane)
  <> "/"
  <> c.component
  <> "/"
  <> c.feature
}

// -----------------------------------------------------------------------------
// 5. JSON Serialization (Contracts: contracts/spatiotemporal/cordis_spatiotemporal_spec.json)
// -----------------------------------------------------------------------------

pub fn to_json(c: TraceCoordinate) -> json.Json {
  json.object([
    #("layer", json.string(layer_to_string(c.layer))),
    #("component", json.string(c.component)),
    #("feature", json.string(c.feature)),
    #("surface", json.string(surface_to_string(c.surface))),
    #("modal", json.string(modal_to_string(c.modal))),
    #("plane", json.string(plane_to_string(c.plane))),
    #("carrier", json.string(c.carrier)),
    #("profile", json.string(profile_to_string(c.profile))),
    #("semantics", json.string(c.semantics)),
    #("operations", json.array(c.operations, json.string)),
    #("telemetry", json.array(c.telemetry, json.string)),
    #("invariants", json.array(c.invariants, json.string)),
    #("authority", json.string(authority_to_string(c.authority))),
    #("status", json.string(status_to_string(c.status))),
    #("trust_indicator", json.int(trust_indicator(c.status))),
    #("well_formed", json.bool(is_well_formed(c))),
    #("uri", json.string(to_uri(c))),
    #("zenoh_topic", json.string(to_zenoh_topic(c))),
  ])
}

pub fn to_json_string(c: TraceCoordinate) -> String {
  to_json(c) |> json.to_string
}

pub fn decoder() -> decode.Decoder(TraceCoordinate) {
  use layer_str <- decode.field("layer", decode.string)
  use component <- decode.field("component", decode.string)
  use feature <- decode.field("feature", decode.string)
  use surface_str <- decode.field("surface", decode.string)
  use modal_str <- decode.field("modal", decode.string)
  use plane_str <- decode.field("plane", decode.string)
  use carrier <- decode.field("carrier", decode.string)
  use profile_str <- decode.field("profile", decode.string)
  use semantics <- decode.field("semantics", decode.string)
  use operations <- decode.field("operations", decode.list(decode.string))
  use telemetry <- decode.field("telemetry", decode.list(decode.string))
  use invariants <- decode.field("invariants", decode.list(decode.string))
  use authority_str <- decode.field("authority", decode.string)
  use status_str <- decode.field("status", decode.string)

  let layer = layer_from_string(layer_str) |> result.unwrap(L0MicroKernelAllocator)
  let surface = surface_from_string(surface_str) |> result.unwrap(Development)
  let modal = modal_from_string(modal_str) |> result.unwrap(ActorMessage)
  let plane = plane_from_string(plane_str) |> result.unwrap(GleamControlPlane)
  let profile = profile_from_string(profile_str) |> result.unwrap(Lean4Theorem)
  let authority = authority_from_string(authority_str) |> result.unwrap(SandboxedWorker)
  let status = status_from_string(status_str) |> result.unwrap(Discovered)

  decode.success(TraceCoordinate(
    layer: layer,
    component: component,
    feature: feature,
    surface: surface,
    modal: modal,
    plane: plane,
    carrier: carrier,
    profile: profile,
    semantics: semantics,
    operations: operations,
    telemetry: telemetry,
    invariants: invariants,
    authority: authority,
    status: status,
  ))
}

pub fn from_json_string(raw: String) -> Result(TraceCoordinate, String) {
  json.parse(raw, decoder())
  |> result.map_error(fn(_) { "failed_to_decode_13d_trace_coordinate" })
}
