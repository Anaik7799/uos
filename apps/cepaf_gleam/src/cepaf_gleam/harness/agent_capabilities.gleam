//// Four-agent source registry and DATA-only intent algebra.
//// Declaration, source presence, fresh observation DATA and effect authority
//// are independent coordinates. No constructor here creates a Grant,
//// Execution, TaskFence, signed approval, process witness or effect adapter.
//// Requirements denote a finite conjunction; their union commutes. Ordered
//// effect dispatch does not commute and is owned by successor_mcp/operations.

import cepaf_gleam/harness/client_profiles
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Agent {
  Pi
  Claude
  Agy
  Codex
}

pub type AgentRuntime {
  PiRuntime
  ClaudeRuntime
  AgyRuntime
  CodexRuntime
}

pub type InferenceProvider {
  OpenRouterProvider
  GoogleProvider
  AnthropicProvider
  OpenAiProvider
  ProviderUnspecified
}

pub type ModelNamespace {
  OpenRouterCatalog
  NativeCatalog(runtime: AgentRuntime)
}

pub opaque type ModelRef {
  ModelRef(provider: InferenceProvider, namespace: ModelNamespace, id: String)
}

pub opaque type RequestedInferenceData {
  RequestedInferenceData(runtime: AgentRuntime, model: ModelRef)
}

pub type SourceInference {
  InferenceUnspecified(runtime: AgentRuntime)
  SourceDeclaredModel(runtime: AgentRuntime, model: ModelRef, source: String)
  LegacyDeclaredModel(runtime: AgentRuntime, model: ModelRef, source: String)
}

pub fn runtime(agent: Agent) -> AgentRuntime {
  case agent {
    Pi -> PiRuntime
    Claude -> ClaudeRuntime
    Agy -> AgyRuntime
    Codex -> CodexRuntime
  }
}

/// Exact requested identity DATA. No aliases, provider discovery or inference
/// from a name such as 'google/' or 'Gemini'. This is not an observed model.
pub fn model_ref(
  provider: InferenceProvider,
  namespace: ModelNamespace,
  id: String,
) -> Result(ModelRef, String) {
  case
    string.byte_size(id) > 0
    && string.byte_size(id) <= 200
    && list.all(string.to_graphemes(id), fn(c) {
      string.byte_size(c) == 1
      && string.contains(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:/",
        c,
      )
    })
    && { namespace != OpenRouterCatalog || provider == OpenRouterProvider }
  {
    True -> Ok(ModelRef(provider, namespace, id))
    False -> Error("invalid_exact_model_reference_data")
  }
}

pub fn model_identity(
  model: ModelRef,
) -> #(InferenceProvider, ModelNamespace, String) {
  #(model.provider, model.namespace, model.id)
}

pub fn requested_inference(
  runtime: AgentRuntime,
  model: ModelRef,
) -> Result(RequestedInferenceData, String) {
  case model.namespace {
    NativeCatalog(expected) if expected != runtime ->
      Error("native_model_runtime_mismatch")
    _ -> Ok(RequestedInferenceData(runtime, model))
  }
}

pub fn requested_identity(
  data: RequestedInferenceData,
) -> #(AgentRuntime, ModelRef) {
  #(data.runtime, data.model)
}

/// Native AGY model declaration and legacy Pi defaults are source facts only.
/// They do not prove custody, current runtime model choice or admitted routing.
pub fn source_inference(agent: Agent) -> SourceInference {
  case agent {
    Agy ->
      SourceDeclaredModel(
        AgyRuntime,
        ModelRef(
          ProviderUnspecified,
          NativeCatalog(AgyRuntime),
          "gemini-4-argon-high",
        ),
        "apps/cepaf_gleam/src/cepaf_gleam/harness/agy_dispatch.gleam",
      )
    Pi ->
      LegacyDeclaredModel(
        PiRuntime,
        ModelRef(GoogleProvider, NativeCatalog(PiRuntime), "gemini-2.5-flash"),
        "apps/cepaf_gleam/src/cepaf_gleam/bridge/pi_runtime.gleam",
      )
    Claude | Codex -> InferenceUnspecified(runtime(agent))
  }
}

pub type Capability {
  ConfigureMcp
  KnowledgeRead
  AdvisoryCompletion
  ToolExecution
  TaskLifecycle
  EvolutionProposal
  ReleaseDeployment
}

pub type Implementation {
  NoMappedAgentAdapter
  ClientConfigurationSource(path: String)
  SharedHarnessSource(path: String)
  AgentJobSource(path: String)
  LegacyUnintegratedSource(path: String)
}

pub type Registration {
  Registration(
    agent: Agent,
    capability: Capability,
    declared: Bool,
    implementation: Implementation,
  )
}

pub fn agents() -> List(Agent) {
  [Pi, Claude, Agy, Codex]
}

pub fn capabilities() -> List(Capability) {
  [
    ConfigureMcp,
    KnowledgeRead,
    AdvisoryCompletion,
    ToolExecution,
    TaskLifecycle,
    EvolutionProposal,
    ReleaseDeployment,
  ]
}

pub fn name(agent: Agent) -> String {
  case agent {
    Pi -> "pi"
    Claude -> "claude"
    Agy -> "agy"
    Codex -> "codex"
  }
}

pub fn client(agent: Agent) -> client_profiles.Client {
  case agent {
    Pi -> client_profiles.Pi
    Claude -> client_profiles.Claude
    Agy -> client_profiles.Agy
    Codex -> client_profiles.Codex
  }
}

/// Source facts for this baseline, NOT availability or currently loaded code.
/// Shared harness code is not evidence that a native agent is connected to it.
/// KnowledgeRead here maps scoped read_file only, not the complete KM triad
/// search/transclusion/writeback/preflight/performance service contract.
pub fn registration(agent: Agent, capability: Capability) -> Registration {
  let implementation = case capability {
    ConfigureMcp -> ClientConfigurationSource("harness/client_mcp.gleam")
    KnowledgeRead | TaskLifecycle | EvolutionProposal ->
      SharedHarnessSource("harness/operations.gleam")
    AdvisoryCompletion | ToolExecution ->
      case agent {
        Agy -> AgentJobSource("harness/agy_dispatch.gleam")
        Pi -> LegacyUnintegratedSource("bridge/pi_daemon.gleam")
        Claude | Codex -> NoMappedAgentAdapter
      }
    ReleaseDeployment -> NoMappedAgentAdapter
  }
  Registration(agent, capability, True, implementation)
}

pub fn registry() -> List(Registration) {
  list.flat_map(agents(), fn(a) {
    list.map(capabilities(), fn(c) { registration(a, c) })
  })
}

pub type SourceOwner {
  Controller
  Admission
  Effects
  ClientConfiguration
  AgentJobs
  ModelPolicy
  UsageEvidence
  BudgetLedger
  ProcessGuardian
  EcologyCatalog
  LegacyPiBridge
  ProtocolMapping
}

pub type OwnedSource {
  OwnedSource(owner: SourceOwner, path: String)
}

/// Bounded traceability map of the existing integration surfaces, not an
/// assertion that every agent-related file or backend is implemented.
pub fn owned_sources() -> List(OwnedSource) {
  [
    OwnedSource(
      Controller,
      "apps/cepaf_gleam/src/cepaf_gleam/harness/successor_mcp.gleam",
    ),
    OwnedSource(
      Admission,
      "apps/cepaf_gleam/src/cepaf_gleam/harness/admission.gleam",
    ),
    OwnedSource(
      Effects,
      "apps/cepaf_gleam/src/cepaf_gleam/harness/operations.gleam",
    ),
    OwnedSource(
      ClientConfiguration,
      "apps/cepaf_gleam/src/cepaf_gleam/harness/client_mcp.gleam",
    ),
    OwnedSource(
      ClientConfiguration,
      "apps/cepaf_gleam/src/cepaf_gleam/harness/client_profiles.gleam",
    ),
    OwnedSource(
      AgentJobs,
      "apps/cepaf_gleam/src/cepaf_gleam/harness/agy_dispatch.gleam",
    ),
    OwnedSource(
      ModelPolicy,
      "apps/uos_swarm/src/uos_swarm/openrouter_worker.gleam",
    ),
    OwnedSource(
      UsageEvidence,
      "apps/uos_swarm/src/uos_swarm/token_monitor_native.gleam",
    ),
    OwnedSource(
      UsageEvidence,
      "apps/uos_swarm/src/uos_swarm/token_monitor_billing.gleam",
    ),
    OwnedSource(BudgetLedger, "tools/ecology_budget.ml"),
    OwnedSource(ProcessGuardian, "tools/ecology_process.ml"),
    OwnedSource(
      EcologyCatalog,
      "apps/cepaf_gleam/src/cepaf_gleam/harness/agent_ecology.gleam",
    ),
    OwnedSource(
      LegacyPiBridge,
      "apps/cepaf_gleam/src/cepaf_gleam/bridge/pi_daemon.gleam",
    ),
    OwnedSource(
      LegacyPiBridge,
      "apps/cepaf_gleam/src/cepaf_gleam/bridge/pi_runtime.gleam",
    ),
    OwnedSource(
      LegacyPiBridge,
      "apps/cepaf_gleam/src/cepaf_gleam/bridge/pi_rpc.gleam",
    ),
    OwnedSource(
      LegacyPiBridge,
      "apps/cepaf_gleam/src/cepaf_gleam/bridge/pi_tools.gleam",
    ),
    OwnedSource(
      LegacyPiBridge,
      "apps/cepaf_gleam/src/cepaf_gleam/bridge/pi_supervisor.gleam",
    ),
    OwnedSource(
      ProtocolMapping,
      "apps/cepaf_gleam/src/cepaf_gleam/bridge/pi_claude_code.gleam",
    ),
  ]
}

pub type Relation {
  Relation(
    caller: SourceOwner,
    callee: SourceOwner,
    functions: String,
    meaning: String,
  )
}

/// Existing source calls only. No invented Pi/Claude/Codex execution edge.
pub fn source_relations() -> List(Relation) {
  [
    Relation(
      Controller,
      Admission,
      "load/check/fence",
      "existing admission calls",
    ),
    Relation(
      Controller,
      Effects,
      "effect/reconcile",
      "durable intent interpreter calls",
    ),
    Relation(
      Effects,
      ClientConfiguration,
      "perform",
      "native MCP configuration calls",
    ),
    Relation(
      AgentJobs,
      Admission,
      "require/component",
      "validation helpers only; no admission proof",
    ),
  ]
}

fn implementation_label(source: Implementation) -> String {
  case source {
    NoMappedAgentAdapter -> "unmapped"
    ClientConfigurationSource(_) -> "config"
    SharedHarnessSource(_) -> "shared"
    AgentJobSource(_) -> "job"
    LegacyUnintegratedSource(_) -> "legacy"
  }
}

/// Compact source map for the existing ecology formatter. These labels are
/// implementation categories, never operational or permission badges.
pub fn format_registry() -> String {
  "Four-agent capability map — source coordinates only\n"
  <> "| Agent | MCP config | Scoped read | Advice | Tools | Tasks | Evolution | Release |\n"
  <> "|---|---|---|---|---|---|---|---|\n"
  <> string.join(
    list.map(agents(), fn(agent) {
      "| "
      <> name(agent)
      <> " | "
      <> string.join(
        list.map(capabilities(), fn(capability) {
          registration(agent, capability).implementation |> implementation_label
        }),
        " | ",
      )
      <> " |"
    }),
    "\n",
  )
  <> "\n"
  <> int.to_string(list.length(registry()))
  <> " declared coordinates. "
  <> "config = MCP configuration source; shared = shared harness source; "
  <> "job = agent job source; legacy = source not mapped to admitted harness; "
  <> "unmapped = no mapped execution adapter in this registry.\n"
  <> "Runtime availability and authority: UNVERIFIED. "
  <> "This bounded map does not cover all agent-related code."
  <> " Scoped read means read_file, not full KM triad operations; "
  <> "service coverage, preflight and performance evidence are omitted."
  <> "\nRuntime, inference provider and exact model are independent axes. "
  <> "Pi legacy config declares Google/gemini-2.5-flash; admitted inference is unverified. "
  <> "Claude/Codex inference is unspecified in this map. "
  <> "AGY source declares native gemini-4-argon-high; upstream provider is unspecified. "
  <> "Requested model data does not establish an observed or available model."
}

pub type Requirement {
  AuthenticatedPrincipal
  CandidateBinding
  FreshClock
  CurrentTaskFence
  ScopedGrant
  DurableIntent
  DurableLiability
  AdmittedToolPolicy
  WorkspaceOwnership
  ConfirmedProcessCleanup
  IndependentVerification
  ReleaseApproval
  ReaderBarrier
}

pub fn requirement_order() -> List(Requirement) {
  [
    AuthenticatedPrincipal,
    CandidateBinding,
    FreshClock,
    CurrentTaskFence,
    ScopedGrant,
    DurableIntent,
    DurableLiability,
    AdmittedToolPolicy,
    WorkspaceOwnership,
    ConfirmedProcessCleanup,
    IndependentVerification,
    ReleaseApproval,
    ReaderBarrier,
  ]
}

/// Canonical finite set union: this describes requirements, not effect order.
pub fn combine(
  a: List(Requirement),
  b: List(Requirement),
) -> List(Requirement) {
  list.filter(requirement_order(), fn(r) {
    list.contains(a, r) || list.contains(b, r)
  })
}

pub type Intent {
  Inspect(capability: Capability)
  Perform(capability: Capability)
  Sequence(intents: List(Intent))
}

pub fn requirements(intent: Intent) -> List(Requirement) {
  let observation = [AuthenticatedPrincipal, CandidateBinding, FreshClock]
  case intent {
    Inspect(_) -> observation
    Sequence(intents) ->
      list.fold(intents, [], fn(acc, i) { combine(acc, requirements(i)) })
    Perform(capability) -> {
      let mutation =
        combine(observation, [
          CurrentTaskFence,
          ScopedGrant,
          DurableIntent,
          IndependentVerification,
        ])
      case capability {
        KnowledgeRead -> observation
        ConfigureMcp | EvolutionProposal ->
          combine(mutation, [WorkspaceOwnership])
        TaskLifecycle -> mutation
        AdvisoryCompletion ->
          combine(mutation, [DurableLiability, ConfirmedProcessCleanup])
        ToolExecution ->
          combine(mutation, [
            DurableLiability,
            AdmittedToolPolicy,
            WorkspaceOwnership,
            ConfirmedProcessCleanup,
          ])
        ReleaseDeployment ->
          combine(mutation, [
            WorkspaceOwnership,
            ConfirmedProcessCleanup,
            ReleaseApproval,
            ReaderBarrier,
          ])
      }
    }
  }
}

pub type ScopeData {
  ScopeData(
    plan: String,
    task: String,
    worker: String,
    attempt: Int,
    intent: String,
  )
}

pub type ClockData {
  ClockData(
    host: String,
    boot: String,
    domain: String,
    utc_ms: Int,
    mono_ms: Int,
  )
}

pub type ContextData {
  ContextData(
    agent: Agent,
    capability: Capability,
    candidate_sha256: String,
    source_sha256: String,
    inference: Option(RequestedInferenceData),
    scope: ScopeData,
    now: ClockData,
  )
}

pub type ObservationData {
  ObservationData(
    context: ContextData,
    expires_utc_ms: Int,
    expires_mono_ms: Int,
  )
}

pub opaque type CheckedObservationData {
  CheckedObservationData(data: ObservationData, checked_at: ClockData)
}

pub type ObservationError {
  InvalidBinding
  BindingChanged
  ClockDomainChanged
  ClockRegressed
  Expired
}

fn digest(s: String) -> Bool {
  string.byte_size(s) == 71
  && string.starts_with(s, "sha256:")
  && list.all(string.to_graphemes(string.drop_start(s, 7)), fn(c) {
    string.byte_size(c) == 1 && string.contains("0123456789abcdef", c)
  })
}

fn identifier(s: String) -> Bool {
  string.byte_size(s) > 0
  && string.byte_size(s) <= 256
  && !string.contains(s, "\u{0}")
}

fn valid_context(c: ContextData) -> Bool {
  digest(c.candidate_sha256)
  && digest(c.source_sha256)
  && list.all(
    [
      c.scope.plan,
      c.scope.task,
      c.scope.worker,
      c.scope.intent,
      c.now.host,
      c.now.boot,
      c.now.domain,
    ],
    identifier,
  )
  && c.scope.attempt > 0
  && c.scope.attempt <= 9_000_000_000_000
  && c.now.utc_ms > 0
  && c.now.utc_ms <= 9_000_000_000_000_000
  && c.now.mono_ms >= -9_000_000_000_000_000
  && c.now.mono_ms <= 9_000_000_000_000_000
  && case c.inference {
    Some(data) -> data.runtime == runtime(c.agent)
    None -> c.capability != AdvisoryCompletion
  }
}

/// Validates caller-supplied factual DATA only. It does not authenticate a
/// collector/clock/roster or establish actual runtime functionality.
pub fn check_observation(
  data: ObservationData,
  expected: ContextData,
) -> Result(CheckedObservationData, ObservationError) {
  let a = data.context
  use _ <- result.try(
    case
      valid_context(a)
      && valid_context(expected)
      && data.expires_utc_ms > a.now.utc_ms
      && data.expires_utc_ms - a.now.utc_ms <= 30_000
      && data.expires_mono_ms > a.now.mono_ms
      && data.expires_mono_ms - a.now.mono_ms <= 30_000
    {
      True -> Ok(Nil)
      False -> Error(InvalidBinding)
    },
  )
  use _ <- result.try(
    case
      a.agent == expected.agent
      && a.capability == expected.capability
      && a.candidate_sha256 == expected.candidate_sha256
      && a.source_sha256 == expected.source_sha256
      && a.inference == expected.inference
      && a.scope == expected.scope
    {
      True -> Ok(Nil)
      False -> Error(BindingChanged)
    },
  )
  use _ <- result.try(
    case
      a.now.host == expected.now.host
      && a.now.boot == expected.now.boot
      && a.now.domain == expected.now.domain
    {
      True -> Ok(Nil)
      False -> Error(ClockDomainChanged)
    },
  )
  use _ <- result.try(
    case
      expected.now.utc_ms >= a.now.utc_ms
      && expected.now.mono_ms >= a.now.mono_ms
    {
      True -> Ok(Nil)
      False -> Error(ClockRegressed)
    },
  )
  use _ <- result.try(
    case
      expected.now.utc_ms < data.expires_utc_ms
      && expected.now.mono_ms < data.expires_mono_ms
    {
      True -> Ok(Nil)
      False -> Error(Expired)
    },
  )
  Ok(CheckedObservationData(data, expected.now))
}

/// High-water advances along this immutable value chain; deadlines stay
/// immutable. The owning caller must retain the returned value. This pure
/// function cannot prevent branching from an older value or enforce a global
/// collector/session high-water. Checking cannot refresh an old window.
pub fn advance(
  data: CheckedObservationData,
  expected: ContextData,
) -> Result(CheckedObservationData, ObservationError) {
  let previous = data.data
  use _ <- result.try(
    case
      expected.now.utc_ms >= data.checked_at.utc_ms
      && expected.now.mono_ms >= data.checked_at.mono_ms
    {
      True -> Ok(Nil)
      False -> Error(ClockRegressed)
    },
  )
  use _ <- result.try(check_observation(previous, expected))
  Ok(CheckedObservationData(previous, expected.now))
}

pub fn checked_at(data: CheckedObservationData) -> ClockData {
  data.checked_at
}

pub fn observation(data: CheckedObservationData) -> ObservationData {
  data.data
}

pub type AuthorityState {
  AdmissionRequired
}

pub fn authority(_data: CheckedObservationData) -> AuthorityState {
  AdmissionRequired
}

pub type Phase {
  Idle
  Prepared
  Reserved
  Dispatched
  Verified
  Unknown
  Quarantined
}

pub type Event {
  Prepare
  Reserve
  Dispatch
  Verify
  LoseOutcome
  Quarantine
}

pub opaque type IntentState {
  IntentState(phase: Phase, liability: Int)
}

pub fn initial() -> IntentState {
  IntentState(Idle, 0)
}

pub fn phase(state: IntentState) -> Phase {
  state.phase
}

pub fn liability(state: IntentState) -> Int {
  state.liability
}

/// Paid single-completion lifecycle projection, not the full tool/release/job
/// protocol. These events are not authenticated receipts; even Verified never
/// enables an effect. Other capabilities have requirements above.
pub fn step(state: IntentState, event: Event) -> Result(IntentState, String) {
  case state.phase, event {
    Idle, Prepare -> Ok(IntentState(Prepared, 0))
    Prepared, Reserve -> Ok(IntentState(Reserved, 250_000_000))
    Reserved, Dispatch -> Ok(IntentState(Dispatched, state.liability))
    Dispatched, Verify -> Ok(IntentState(Verified, state.liability))
    Reserved, LoseOutcome | Dispatched, LoseOutcome ->
      Ok(IntentState(Unknown, state.liability))
    Unknown, Quarantine -> Ok(IntentState(Quarantined, state.liability))
    _, _ -> Error("intent_transition_refused_data_only")
  }
}

pub fn interpret(events: List(Event)) -> Result(IntentState, String) {
  list.try_fold(events, initial(), step)
}

pub fn effect_authority(_state: IntentState) -> AuthorityState {
  AdmissionRequired
}
