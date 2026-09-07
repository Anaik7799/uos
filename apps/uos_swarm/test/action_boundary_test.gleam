import action_boundary_cli
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import uos_swarm/action_boundary.{Refused} as action
import uos_swarm/session_sync as sync

const host = "host-a"

const boot = "boot-a"

const now = 1_000_000

const candidate = "candidate-a"

fn invoke(
  state: sync.State,
  command: sync.Command,
  id: String,
  tick: Int,
) -> sync.State {
  let assert Ok(#(next, _, _)) =
    sync.apply(state, command, id, host, boot, tick, tick + 1_000_000_000)
  next
}

fn claimed(resource: String) -> sync.State {
  sync.empty()
  |> invoke(
    sync.Register("codex", "codex", "/uos", candidate, ["herdr:session=live"]),
    "register-codex",
    now,
  )
  |> invoke(sync.Claim("codex", resource, 30_000_000), "claim-resource", now)
}

fn integration_command(
  operation: action.IntegrationOperation,
) -> action.ActionCommand {
  action.Integration(
    action.IntegrationCommand(candidate, operation, [
      "evidence:runtime",
      "evidence:formal",
    ]),
  )
}

fn integration_request(
  operation_id: String,
  operation: action.IntegrationOperation,
) -> action.Request {
  action.Request(operation_id, "codex", 1, integration_command(operation))
}

fn integration_policy(
  operation: action.IntegrationOperation,
) -> action.PolicySnapshot {
  action.PolicySnapshot(
    "policy-7",
    verified_candidate(),
    [action.AllowIntegration("codex", operation)],
    9_000_000_000_000_000_000,
  )
}

fn verified_candidate() -> action.CandidateReceipt {
  action.CandidateReceipt(
    candidate,
    action.CandidateVerified,
    0,
    9_000_000_000_000_000_000,
    "evidence:runtime",
    "evidence:formal",
  )
}

fn authorization(request: action.Request) -> action.Authorization {
  action.Authorization(
    request.operation_id,
    request.session,
    action.scope(request.command),
    request.epoch,
    action.candidate_revision(request.command),
    "policy-7",
    request.command,
    9_000_000_000_000_000_000,
    "authority:operator-approval-42",
  )
}

fn authorization_with(
  request: action.Request,
  policy_version: String,
  authority_ref: String,
) -> action.Authorization {
  action.Authorization(
    request.operation_id,
    request.session,
    action.scope(request.command),
    request.epoch,
    action.candidate_revision(request.command),
    policy_version,
    request.command,
    9_000_000_000_000_000_000,
    authority_ref,
  )
}

pub fn authorized_integration_invokes_effect_once_and_caches_receipt_test() {
  let state = claimed("integration/main")
  let request = integration_request("integrate-1", action.InspectIntegration)
  let calls = process.new_subject()
  let effect = fn(permit) {
    process.send(calls, action.permitted_operation_id(permit))
    action.EffectApplied("jj:change=accepted")
  }

  let #(executor, first) =
    action.attempt(
      action.new_executor(),
      state,
      boot,
      now,
      request,
      integration_policy(action.InspectIntegration),
      authorization(request),
      effect,
    )
  first
  |> should.equal(action.Executed(
    action.EffectApplied("jj:change=accepted"),
    False,
  ))
  process.receive(calls, 10) |> should.equal(Ok("integrate-1"))

  let #(_, replay) =
    action.attempt(
      executor,
      state,
      boot,
      now + 1,
      request,
      integration_policy(action.InspectIntegration),
      authorization(request),
      effect,
    )
  replay
  |> should.equal(action.Executed(
    action.EffectApplied("jj:change=accepted"),
    True,
  ))
  process.receive(calls, 10) |> should.be_error
}

pub fn changed_command_cannot_reuse_an_operation_id_test() {
  let state = claimed("integration/main")
  let original = integration_request("integrate-1", action.InspectIntegration)
  let changed = integration_request("integrate-1", action.ApplyPreservingMerge)
  let calls = process.new_subject()
  let effect = fn(_permit) {
    process.send(calls, Nil)
    action.EffectApplied("observed")
  }
  let #(executor, _) =
    action.attempt(
      action.new_executor(),
      state,
      boot,
      now,
      original,
      integration_policy(action.InspectIntegration),
      authorization(original),
      effect,
    )
  let #(_, outcome) =
    action.attempt(
      executor,
      state,
      boot,
      now,
      changed,
      integration_policy(action.ApplyPreservingMerge),
      authorization(changed),
      effect,
    )
  outcome
  |> should.equal(action.Refused(
    "operation ID already belongs to a different action",
  ))
  process.receive(calls, 10) |> should.equal(Ok(Nil))
  process.receive(calls, 10) |> should.be_error
}

pub fn unknown_effect_outcome_is_cached_without_automatic_retry_test() {
  let state = claimed("integration/main")
  let request =
    integration_request("integrate-unknown", action.InspectIntegration)
  let calls = process.new_subject()
  let effect = fn(_permit) {
    process.send(calls, Nil)
    action.EffectUnknown(
      "destination reply lost; inspect candidate before retry",
    )
  }
  let #(executor, first) =
    action.attempt(
      action.new_executor(),
      state,
      boot,
      now,
      request,
      integration_policy(action.InspectIntegration),
      authorization(request),
      effect,
    )
  first
  |> should.equal(action.Executed(
    action.EffectUnknown(
      "destination reply lost; inspect candidate before retry",
    ),
    False,
  ))
  let #(_, replay) =
    action.attempt(
      executor,
      state,
      boot,
      now,
      request,
      integration_policy(action.InspectIntegration),
      authorization(request),
      effect,
    )
  replay
  |> should.equal(action.Executed(
    action.EffectUnknown(
      "destination reply lost; inspect candidate before retry",
    ),
    True,
  ))
  process.receive(calls, 10) |> should.equal(Ok(Nil))
  process.receive(calls, 10) |> should.be_error
}

pub fn successor_epoch_and_changed_candidate_fail_before_effect_test() {
  let original = claimed("integration/main")
  let released =
    invoke(
      original,
      sync.Release("codex", "integration/main", 1),
      "release-resource",
      now + 1,
    )
  let with_claude =
    invoke(
      released,
      sync.Register("claude", "claude", "/uos", "candidate-b", []),
      "register-claude",
      now + 1,
    )
  let successor =
    invoke(
      with_claude,
      sync.Claim("claude", "integration/main", 30_000_000),
      "claim-successor",
      now + 1,
    )
  let request = integration_request("stale-attempt", action.InspectIntegration)
  let calls = process.new_subject()
  let #(_, stale) =
    action.attempt(
      action.new_executor(),
      successor,
      boot,
      now + 1,
      request,
      integration_policy(action.InspectIntegration),
      authorization(request),
      fn(_permit) {
        process.send(calls, Nil)
        action.EffectApplied("must-not-run")
      },
    )
  let assert Refused(_) = stale
  process.receive(calls, 10) |> should.be_error

  let changed_candidate_state =
    invoke(
      original,
      sync.Heartbeat("codex", "candidate-b", []),
      "changed-candidate",
      now + 2,
    )
  let #(_, changed) =
    action.attempt(
      action.new_executor(),
      changed_candidate_state,
      boot,
      now + 2,
      request,
      integration_policy(action.InspectIntegration),
      authorization(request),
      fn(_permit) {
        process.send(calls, Nil)
        action.EffectApplied("must-not-run")
      },
    )
  let assert Refused(_) = changed
  process.receive(calls, 10) |> should.be_error
}

pub fn policy_and_authorization_must_match_the_exact_operation_test() {
  let state = claimed("integration/main")
  let request = integration_request("integrate-1", action.InspectIntegration)
  let calls = process.new_subject()
  let run = fn(policy, auth) {
    action.attempt(
      action.new_executor(),
      state,
      boot,
      now,
      request,
      policy,
      auth,
      fn(_permit) {
        process.send(calls, Nil)
        action.EffectApplied("must-not-run")
      },
    ).1
  }

  let assert Refused(_) =
    run(integration_policy(action.ApplyPreservingMerge), authorization(request))
  let assert Refused(_) =
    run(
      integration_policy(action.InspectIntegration),
      authorization_with(request, "policy-6", "authority:operator-approval-42"),
    )
  let assert Refused(_) =
    run(
      action.PolicySnapshot(
        "policy-7",
        verified_candidate(),
        [action.AllowIntegration("codex", action.InspectIntegration)],
        now,
      ),
      authorization(request),
    )
  let assert Refused(_) =
    run(
      integration_policy(action.InspectIntegration),
      authorization_with(request, "policy-7", ""),
    )
  process.receive(calls, 10) |> should.be_error
}

pub fn runtime_and_integration_claims_are_separate_scopes_test() {
  let state = claimed("runtime:wiki")
  let runtime =
    action.Runtime(action.RuntimeAction(
      "wiki",
      candidate,
      action.ObserveRuntime,
      None,
      "check:slo-wiki",
    ))
  let runtime_request = action.Request("observe-wiki", "codex", 1, runtime)
  let runtime_policy =
    action.PolicySnapshot(
      "policy-7",
      verified_candidate(),
      [action.AllowRuntime("codex", "wiki", action.ObserveRuntime)],
      9_000_000_000_000_000_000,
    )
  let calls = process.new_subject()
  let #(_, allowed) =
    action.attempt(
      action.new_executor(),
      state,
      boot,
      now,
      runtime_request,
      runtime_policy,
      authorization(runtime_request),
      fn(_permit) {
        process.send(calls, Nil)
        action.EffectApplied("observation:wiki-healthy")
      },
    )
  allowed
  |> should.equal(action.Executed(
    action.EffectApplied("observation:wiki-healthy"),
    False,
  ))

  let integration =
    integration_request("integrate-on-runtime", action.InspectIntegration)
  let #(_, denied) =
    action.attempt(
      action.new_executor(),
      state,
      boot,
      now,
      integration,
      integration_policy(action.InspectIntegration),
      authorization(integration),
      fn(_permit) {
        process.send(calls, Nil)
        action.EffectApplied("must-not-run")
      },
    )
  let assert Refused(_) = denied
  process.receive(calls, 10) |> should.equal(Ok(Nil))
  process.receive(calls, 10) |> should.be_error
}

pub fn effectful_runtime_actions_require_rollback_and_postcheck_refs_test() {
  let state = claimed("runtime:wiki")
  let malformed =
    action.Runtime(action.RuntimeAction(
      "wiki",
      candidate,
      action.MitigateRuntime,
      None,
      "",
    ))
  let request = action.Request("mitigate-wiki", "codex", 1, malformed)
  let policy =
    action.PolicySnapshot(
      "policy-7",
      verified_candidate(),
      [action.AllowRuntime("codex", "wiki", action.MitigateRuntime)],
      9_000_000_000_000_000_000,
    )
  let #(_, outcome) =
    action.attempt(
      action.new_executor(),
      state,
      boot,
      now,
      request,
      policy,
      authorization(request),
      fn(_permit) { action.EffectApplied("must-not-run") },
    )
  let assert Refused(_) = outcome

  let valid =
    action.Runtime(action.RuntimeAction(
      "wiki",
      candidate,
      action.RollbackRuntime,
      Some("rollback:wiki-candidate-a"),
      "check:wiki-after-rollback",
    ))
  action.scope(valid) |> should.equal("runtime:wiki")
}

pub fn caller_declared_authority_cannot_enable_privileged_effects_test() {
  let integration_state = claimed("integration/main")
  let integration =
    integration_request("blocked-main-write", action.ApplyPreservingMerge)
  let calls = process.new_subject()
  let #(_, integration_outcome) =
    action.attempt(
      action.new_executor(),
      integration_state,
      boot,
      now,
      integration,
      integration_policy(action.ApplyPreservingMerge),
      authorization(integration),
      fn(_permit) {
        process.send(calls, Nil)
        action.EffectApplied("must-not-run")
      },
    )
  let assert Refused(_) = integration_outcome

  let runtime_state = claimed("runtime:wiki")
  let runtime_command =
    action.Runtime(action.RuntimeAction(
      "wiki",
      candidate,
      action.RollbackRuntime,
      Some("rollback:wiki-candidate-a"),
      "check:wiki-after-rollback",
    ))
  let runtime =
    action.Request("blocked-runtime-write", "codex", 1, runtime_command)
  let runtime_policy =
    action.PolicySnapshot(
      "policy-7",
      verified_candidate(),
      [action.AllowRuntime("codex", "wiki", action.RollbackRuntime)],
      9_000_000_000_000_000_000,
    )
  let #(_, runtime_outcome) =
    action.attempt(
      action.new_executor(),
      runtime_state,
      boot,
      now,
      runtime,
      runtime_policy,
      authorization(runtime),
      fn(_permit) {
        process.send(calls, Nil)
        action.EffectApplied("must-not-run")
      },
    )
  let assert Refused(_) = runtime_outcome
  process.receive(calls, 10) |> should.be_error
}

pub fn rejected_stale_expired_and_unknown_candidates_never_reach_effect_test() {
  let state = claimed("integration/main")
  let request =
    integration_request("candidate-state", action.InspectIntegration)
  let calls = process.new_subject()
  list.each(
    [
      action.CandidateRejected,
      action.CandidateStale,
      action.CandidateUnknown,
    ],
    fn(disposition) {
      let policy =
        action.PolicySnapshot(
          "policy-7",
          action.CandidateReceipt(
            candidate,
            disposition,
            0,
            9_000_000_000_000_000_000,
            "evidence:runtime",
            "evidence:formal",
          ),
          [action.AllowIntegration("codex", action.InspectIntegration)],
          9_000_000_000_000_000_000,
        )
      let #(_, outcome) =
        action.attempt(
          action.new_executor(),
          state,
          boot,
          now,
          request,
          policy,
          authorization(request),
          fn(_permit) {
            process.send(calls, Nil)
            action.EffectApplied("must-not-run")
          },
        )
      let assert Refused(_) = outcome
    },
  )
  let expired =
    action.PolicySnapshot(
      "policy-7",
      action.CandidateReceipt(
        candidate,
        action.CandidateVerified,
        0,
        now,
        "evidence:runtime",
        "evidence:formal",
      ),
      [action.AllowIntegration("codex", action.InspectIntegration)],
      9_000_000_000_000_000_000,
    )
  let #(_, expired_outcome) =
    action.attempt(
      action.new_executor(),
      state,
      boot,
      now,
      request,
      expired,
      authorization(request),
      fn(_permit) {
        process.send(calls, Nil)
        action.EffectApplied("must-not-run")
      },
    )
  let assert Refused(_) = expired_outcome
  process.receive(calls, 10) |> should.be_error
}

pub fn current_state_dry_run_observes_durable_fence_without_effect_test() {
  let root = "/tmp/uos-action-boundary-test-" <> unique_id()
  sync.execute(
    root,
    sync.Register("codex", "codex", "/uos", candidate, []),
    "register-codex",
  )
  |> should.be_ok
  sync.execute(
    root,
    sync.Claim("codex", "integration/main", 30_000_000),
    "claim-main",
  )
  |> should.be_ok
  let request =
    integration_request("inspect-current", action.InspectIntegration)
  action.observe_dry_run(
    root,
    request,
    integration_policy(action.InspectIntegration),
    authorization(request),
  )
  |> should.be_ok
  sync.execute(
    root,
    sync.Release("codex", "integration/main", 1),
    "release-main",
  )
  |> should.be_ok
  action.observe_dry_run(
    root,
    request,
    integration_policy(action.InspectIntegration),
    authorization(request),
  )
  |> should.be_error
}

pub fn current_consumer_rechecks_durable_state_and_never_retries_effect_test() {
  let root = "/tmp/uos-action-consumer-test-" <> unique_id()
  sync.execute(
    root,
    sync.Register("codex", "codex", "/uos", candidate, []),
    "register-codex",
  )
  |> should.be_ok
  sync.execute(
    root,
    sync.Claim("codex", "integration/main", 30_000_000),
    "claim-main",
  )
  |> should.be_ok
  let request =
    integration_request("consume-current", action.InspectIntegration)
  let calls = process.new_subject()
  let effect = fn(_permit) {
    process.send(calls, Nil)
    action.EffectApplied("inspection:clean")
  }
  let assert Ok(#(executor, first)) =
    action.consume_current(
      root,
      action.new_executor(),
      request,
      integration_policy(action.InspectIntegration),
      authorization(request),
      effect,
    )
  first
  |> should.equal(action.Executed(
    action.EffectApplied("inspection:clean"),
    False,
  ))
  let assert Ok(#(_, replay)) =
    action.consume_current(
      root,
      executor,
      request,
      integration_policy(action.InspectIntegration),
      authorization(request),
      effect,
    )
  replay
  |> should.equal(action.Executed(
    action.EffectApplied("inspection:clean"),
    True,
  ))
  process.receive(calls, 10) |> should.equal(Ok(Nil))
  process.receive(calls, 10) |> should.be_error

  sync.execute(
    root,
    sync.Release("codex", "integration/main", 1),
    "release-main",
  )
  |> should.be_ok
  let stale =
    integration_request("consume-after-release", action.InspectIntegration)
  let assert Ok(#(_, Refused(_))) =
    action.consume_current(
      root,
      action.new_executor(),
      stale,
      integration_policy(action.InspectIntegration),
      authorization(stale),
      effect,
    )
  process.receive(calls, 10) |> should.be_error
}

pub fn cli_exposes_only_non_mutating_current_state_dry_runs_test() {
  let root = "/tmp/uos-action-cli-test-" <> unique_id()
  sync.execute(
    root,
    sync.Register("codex", "codex", "/uos", candidate, []),
    "register-codex",
  )
  |> should.be_ok
  sync.execute(
    root,
    sync.Claim("codex", "integration/main", 30_000_000),
    "claim-main",
  )
  |> should.be_ok
  let future = "9000000000000000000"
  action_boundary_cli.run([
    root,
    "integration-dry-run",
    "codex",
    "1",
    candidate,
    "inspect",
    "evidence:runtime,evidence:formal",
    "policy-7",
    future,
    future,
    "authority:operator-approval-42",
    "cli-inspect",
  ])
  |> should.be_ok
  action_boundary_cli.run([
    root,
    "integration-dry-run",
    "codex",
    "1",
    candidate,
    "apply",
    "evidence:runtime,evidence:formal",
    "policy-7",
    future,
    future,
    "authority:operator-approval-42",
    "cli-apply",
  ])
  |> should.be_error
  action_boundary_cli.run([
    root,
    "runtime-dry-run",
    "codex",
    "1",
    "wiki",
    candidate,
    "mitigate",
    "rollback:wiki",
    "check:wiki",
    "policy-7",
    future,
    future,
    "authority:operator-approval-42",
    "cli-mitigate",
  ])
  |> should.be_error
}

@external(erlang, "session_sync_ffi", "unique_id")
fn unique_id() -> String
