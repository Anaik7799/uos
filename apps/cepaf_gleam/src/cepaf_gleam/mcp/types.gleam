//// Shared typed MCP contracts, protocol profiles, tool specs, and outcomes.

import gleam/json.{type Json}
import gleam/option.{type Option}

pub type ProtocolProfile {
  Legacy20241105
  Modern20260728
}

pub type ClientProfile {
  ClientProfile(name: String)
}

pub type TransportKind {
  Stdio
  HttpStreamable
  Zenoh
}

pub type AuthorityScope {
  PublicReadOnly
  ScopedObservation
  TaskScopedMutation
  ControlMutation
  ReleaseAuthority
  AuditOnly
}

pub type AccessView {
  OperationalView
  DeclaredCatalogView
  PrivateDevelopmentView
  PrivateSuccessorView
}

pub type EffectClass {
  ReadOnly
  Mutating
  VerificationGate
  ControlActuation
}

pub type Retryability {
  Retryable
  NonRetryable
  ReconcileFirst
}

pub type ToolError {
  ToolError(code: String, reason: String, retryability: Retryability)
}

pub type EvidenceRecord {
  EvidenceRecord(
    candidate: String,
    route: String,
    tool: String,
    declaration_state: String,
    implementation_state: String,
    execution_state: String,
    formal_state: String,
    admission_state: String,
    output_sha256: String,
  )
}

pub type UncertainReceipt {
  UncertainReceipt(
    intent_id: String,
    route: String,
    tool: String,
    reason: String,
    candidate: String,
  )
}

pub type Outcome {
  Complete(value: String, evidence: EvidenceRecord)
  Refused(error: ToolError)
  Uncertain(receipt: UncertainReceipt)
}

pub type ToolSpec {
  ToolSpec(
    route: String,
    name: String,
    description: String,
    family: String,
    owner_task: String,
    primary_layer: Int,
    input_schema: Json,
    schema_digest: String,
    effect_class: EffectClass,
    backend: String,
    budget_ms: Int,
  )
}

pub type RequestContext {
  RequestContext(
    principal_id: String,
    role: String,
    route: String,
    source_binding: String,
    task_binding: Option(String),
    trace_id: String,
    deadline_ms: Int,
  )
}
