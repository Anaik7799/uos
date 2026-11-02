import cepaf_gleam/harness/agent_capabilities as a
import cepaf_gleam/harness/agent_ecology
import cepaf_gleam/harness/client_profiles
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import gleeunit/should

pub fn existing_ecology_uses_four_agent_registry_test() {
  let rows = agent_ecology.agent_capability_registry()
  list.length(rows) |> should.equal(28)
  list.each(a.agents(), fn(agent) {
    client_profiles.name(a.client(agent)) |> should.equal(a.name(agent))
    list.count(rows, fn(r) { r.agent == agent }) |> should.equal(7)
  })
  let formatted = agent_ecology.format_ecology_summary()
  list.each(a.agents(), fn(agent) {
    string.contains(formatted, "| " <> a.name(agent) <> " |") |> should.be_true
  })
  string.contains(formatted, "28 declared coordinates") |> should.be_true
  string.contains(formatted, "Runtime availability and authority: UNVERIFIED")
  |> should.be_true
}

pub fn declaration_source_and_authority_are_separate_test() {
  list.each([a.Claude, a.Codex], fn(agent) {
    let r = a.registration(agent, a.ToolExecution)
    r.declared |> should.be_true
    r.implementation |> should.equal(a.NoMappedAgentAdapter)
  })
  a.registration(a.Agy, a.ToolExecution).implementation
  |> should.equal(a.AgentJobSource("harness/agy_dispatch.gleam"))
  a.registration(a.Pi, a.ToolExecution).implementation
  |> should.equal(a.LegacyUnintegratedSource("bridge/pi_daemon.gleam"))
  list.each(a.agents(), fn(agent) {
    a.registration(agent, a.ReleaseDeployment).implementation
    |> should.equal(a.NoMappedAgentAdapter)
  })
}

// Independent direct semantic interpretation of requirement membership.
// The production algebra normalizes sets; this oracle answers one predicate
// at a time without using its combinator or requirement table.
fn oracle(cap: a.Capability, r: a.Requirement) -> Bool {
  case r {
    a.AuthenticatedPrincipal | a.CandidateBinding | a.FreshClock -> True
    a.CurrentTaskFence
    | a.ScopedGrant
    | a.DurableIntent
    | a.IndependentVerification -> cap != a.KnowledgeRead
    a.DurableLiability -> cap == a.AdvisoryCompletion || cap == a.ToolExecution
    a.AdmittedToolPolicy -> cap == a.ToolExecution
    a.WorkspaceOwnership ->
      list.contains(
        [
          a.ConfigureMcp,
          a.ToolExecution,
          a.EvolutionProposal,
          a.ReleaseDeployment,
        ],
        cap,
      )
    a.ConfirmedProcessCleanup ->
      list.contains(
        [a.AdvisoryCompletion, a.ToolExecution, a.ReleaseDeployment],
        cap,
      )
    a.ReleaseApproval | a.ReaderBarrier -> cap == a.ReleaseDeployment
  }
}

pub fn finite_requirement_interpretations_agree_test() {
  list.each(a.capabilities(), fn(cap) {
    list.each(a.requirement_order(), fn(r) {
      list.contains(a.requirements(a.Perform(cap)), r)
      |> should.equal(oracle(cap, r))
    })
  })
}

pub fn requirement_union_laws_test() {
  let sets = list.map(a.capabilities(), fn(c) { a.requirements(a.Perform(c)) })
  list.each(sets, fn(x) {
    a.combine(x, []) |> should.equal(x)
    a.combine(x, x) |> should.equal(x)
    list.each(sets, fn(y) {
      a.combine(x, y) |> should.equal(a.combine(y, x))
      list.each(sets, fn(z) {
        a.combine(a.combine(x, y), z)
        |> should.equal(a.combine(x, a.combine(y, z)))
      })
    })
  })
}

pub fn requirement_sequence_homomorphism_test() {
  list.each(a.capabilities(), fn(x) {
    list.each(a.capabilities(), fn(y) {
      let actual = a.requirements(a.Sequence([a.Perform(x), a.Perform(y)]))
      list.each(a.requirement_order(), fn(r) {
        list.contains(actual, r) |> should.equal(oracle(x, r) || oracle(y, r))
      })
    })
  })
}

fn context() -> a.ContextData {
  let assert Ok(model) =
    a.model_ref(
      a.OpenRouterProvider,
      a.OpenRouterCatalog,
      "google/gemini-4-argon",
    )
  let assert Ok(inference) = a.requested_inference(a.PiRuntime, model)
  a.ContextData(
    a.Pi,
    a.AdvisoryCompletion,
    "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
    Some(inference),
    a.ScopeData("uos/private", "review", "worker", 1, "intent"),
    a.ClockData(
      "nas-1.tail55d152.ts.net",
      "fixture-boot",
      "fixture-mono",
      1000,
      -2000,
    ),
  )
}

pub fn runtime_provider_and_exact_model_are_independent_data_test() {
  let assert Ok(model) =
    a.model_ref(
      a.OpenRouterProvider,
      a.OpenRouterCatalog,
      "google/gemini-4-argon",
    )
  let assert Ok(requested) = a.requested_inference(a.PiRuntime, model)
  let #(requested_runtime, requested_model) = a.requested_identity(requested)
  requested_runtime |> should.equal(a.PiRuntime)
  a.model_identity(requested_model)
  |> should.equal(#(
    a.OpenRouterProvider,
    a.OpenRouterCatalog,
    "google/gemini-4-argon",
  ))
  let assert a.LegacyDeclaredModel(pi_runtime, pi_model, _) =
    a.source_inference(a.Pi)
  pi_runtime |> should.equal(a.PiRuntime)
  a.model_identity(pi_model)
  |> should.equal(#(
    a.GoogleProvider,
    a.NativeCatalog(a.PiRuntime),
    "gemini-2.5-flash",
  ))
  let assert a.SourceDeclaredModel(runtime, native, _) =
    a.source_inference(a.Agy)
  runtime |> should.equal(a.AgyRuntime)
  a.model_identity(native)
  |> should.equal(#(
    a.ProviderUnspecified,
    a.NativeCatalog(a.AgyRuntime),
    "gemini-4-argon-high",
  ))
  let c = context()
  let observation = a.ObservationData(c, 1100, -1900)
  let assert Ok(other_model) =
    a.model_ref(
      a.OpenRouterProvider,
      a.OpenRouterCatalog,
      "deepseek/deepseek-v4-pro-0813",
    )
  let assert Ok(other_inference) =
    a.requested_inference(a.PiRuntime, other_model)
  a.check_observation(
    observation,
    a.ContextData(..c, inference: Some(other_inference)),
  )
  |> should.equal(Error(a.BindingChanged))
}

pub fn fresh_observation_is_data_and_never_authority_test() {
  let c = context()
  let data = a.ObservationData(c, 1100, -1900)
  let assert Ok(checked) = a.check_observation(data, c)
  a.authority(checked) |> should.equal(a.AdmissionRequired)
  a.observation(checked) |> should.equal(data)
}

pub fn observation_advances_without_extending_deadline_test() {
  let c = context()
  let assert Ok(first) =
    a.check_observation(a.ObservationData(c, 1100, -1900), c)
  let next =
    a.ContextData(..c, now: a.ClockData(..c.now, utc_ms: 1010, mono_ms: -1990))
  let assert Ok(second) = a.advance(first, next)
  let observed = a.observation(second)
  observed.context.now |> should.equal(c.now)
  a.checked_at(second) |> should.equal(next.now)
  observed.expires_utc_ms |> should.equal(1100)
  observed.expires_mono_ms |> should.equal(-1900)
  let backwards =
    a.ContextData(..c, now: a.ClockData(..c.now, utc_ms: 1005, mono_ms: -1995))
  a.advance(second, backwards) |> should.equal(Error(a.ClockRegressed))
}

pub fn exact_scope_clock_and_expiry_bind_data_test() {
  let c = context()
  let data = a.ObservationData(c, 1100, -1900)
  a.check_observation(data, a.ContextData(..c, agent: a.Codex))
  |> result.is_error
  |> should.be_true
  a.check_observation(
    data,
    a.ContextData(..c, now: a.ClockData(..c.now, boot: "other")),
  )
  |> should.equal(Error(a.ClockDomainChanged))
  a.check_observation(
    data,
    a.ContextData(..c, now: a.ClockData(..c.now, utc_ms: 1100)),
  )
  |> should.equal(Error(a.Expired))
}

pub fn paid_completion_trace_preserves_liability_test() {
  let assert Ok(s) = a.interpret([a.Prepare, a.Reserve, a.Dispatch, a.Verify])
  a.phase(s) |> should.equal(a.Verified)
  a.liability(s) |> should.equal(250_000_000)
  a.effect_authority(s) |> should.equal(a.AdmissionRequired)
  let assert Ok(q) =
    a.interpret([a.Prepare, a.Reserve, a.Dispatch, a.LoseOutcome, a.Quarantine])
  a.phase(q) |> should.equal(a.Quarantined)
  a.liability(q) |> should.equal(a.liability(s))
  a.step(q, a.Dispatch) |> result.is_error |> should.be_true
}

pub fn observation_requirements_compose_without_mutation_test() {
  let actual =
    a.requirements(
      a.Sequence([a.Inspect(a.ToolExecution), a.Inspect(a.ReleaseDeployment)]),
    )
  actual
  |> should.equal([a.AuthenticatedPrincipal, a.CandidateBinding, a.FreshClock])
  list.length(a.owned_sources()) |> should.equal(18)
  list.length(a.source_relations()) |> should.equal(4)
}
