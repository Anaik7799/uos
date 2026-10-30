import cepaf_gleam/mcp/admission
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/types.{
  ClientProfile, ControlMutation, NonRetryable, TaskScopedMutation,
}
import gleam/dict
import gleam/option.{type Option, Some}
import gleeunit/should

pub fn payload_actor_cannot_change_principal_test() {
  let transport_principal =
    principal.from_launcher_env(
      actor: "agy-authenticated-worker",
      client: ClientProfile("agy"),
      workspace_root: "/home/an/NAS-setup/uos",
      session_id: "sess-001",
    )

  let attempted_escalation =
    principal.apply_untrusted_payload_labels(
      transport_principal,
      payload_actor: Some("root-sovereign-admin"),
      client_info_name: Some("claude-override"),
      unverified_header_actor: Some("codex-override"),
    )

  principal.actor_id(attempted_escalation)
  |> should.equal("agy-authenticated-worker")
  principal.client_profile(attempted_escalation)
  |> should.equal(ClientProfile("agy"))
  principal.untrusted_actor_label(attempted_escalation)
  |> should.equal(Some("root-sovereign-admin"))
}

pub fn completed_task_is_not_reusable_authority_test() {
  let assert Ok(spec) = registry.lookup("public", "sa_task_complete")
  let p =
    principal.from_launcher_env(
      actor: "agy-worker-20261030",
      client: ClientProfile("agy"),
      workspace_root: "/home/an/NAS-setup/uos",
      session_id: "sess-002",
    )

  let completed_fence =
    admission.TaskFence(
      plan_id: "20261029-1913-mcp-server-completion",
      task_id: "T02",
      worker_id: "agy-worker-20261030",
      attempt: 1,
      task_state: admission.TaskCompleted,
      lease_until_ms: 9_999_999_999_999,
      grant: Some(admission.GrantTicket(
        grant_id: "grant-001",
        scope: TaskScopedMutation,
        revoked: False,
        expires_at_ms: 9_999_999_999_999,
        workspace_root: "/home/an/NAS-setup/uos",
      )),
    )

  let ctx =
    admission.AdmissionContext(
      principal: p,
      mode: admission.EnforcedMode,
      now_ms: 1_000_000,
      workspace_root: "/home/an/NAS-setup/uos",
      task_fence: Some(completed_fence),
    )

  let args =
    dict.from_list([
      #("plan_id", "20261029-1913-mcp-server-completion"),
      #("task_id", "T02"),
    ])

  case admission.admit(ctx, spec, args) {
    Ok(_) -> should.fail()
    Error(err) -> {
      err.retryability |> should.equal(NonRetryable)
      err.code |> should.equal("COMPLETED_TASK_NOT_REUSABLE")
    }
  }

  // Also verify AuditOnly mode can never admit mutations
  let active_fence =
    admission.TaskFence(..completed_fence, task_state: admission.TaskExecuting)
  let audit_ctx =
    admission.AdmissionContext(
      ..ctx,
      mode: admission.AuditOnlyMode,
      task_fence: Some(active_fence),
    )
  case admission.admit(audit_ctx, spec, args) {
    Ok(_) -> should.fail()
    Error(err) -> {
      err.retryability |> should.equal(NonRetryable)
      err.code |> should.equal("AUDIT_ONLY_MUTATION_FORBIDDEN")
    }
  }
}

pub fn revoked_grant_refused_at_effect_time_test() {
  let assert Ok(spec) = registry.lookup("public", "control_loop")
  let p =
    principal.from_launcher_env(
      actor: "agy-worker-20261030",
      client: ClientProfile("agy"),
      workspace_root: "/home/an/NAS-setup/uos",
      session_id: "sess-003",
    )

  let initial_grant =
    admission.GrantTicket(
      grant_id: "grant-ctrl-01",
      scope: ControlMutation,
      revoked: False,
      expires_at_ms: 5_000_000,
      workspace_root: "/home/an/NAS-setup/uos",
    )
  let active_fence =
    admission.TaskFence(
      plan_id: "20261029-1913-mcp-server-completion",
      task_id: "T03",
      worker_id: "agy-worker-20261030",
      attempt: 1,
      task_state: admission.TaskExecuting,
      lease_until_ms: 5_000_000,
      grant: Some(initial_grant),
    )
  let ctx =
    admission.AdmissionContext(
      principal: p,
      mode: admission.EnforcedMode,
      now_ms: 1_000_000,
      workspace_root: "/home/an/NAS-setup/uos",
      task_fence: Some(active_fence),
    )

  let assert Ok(validated_call) =
    admission.admit(ctx, spec, dict.from_list([#("mode", "step")]))

  // Before effect execution, the grant is revoked or expired
  let revoked_fence =
    admission.TaskFence(
      ..active_fence,
      grant: Some(admission.GrantTicket(..initial_grant, revoked: True)),
    )
  let revoked_ctx =
    admission.AdmissionContext(
      ..ctx,
      now_ms: 1_000_100,
      task_fence: Some(revoked_fence),
    )

  case admission.verify_at_effect_time(revoked_ctx, validated_call) {
    Ok(_) -> should.fail()
    Error(err) -> {
      err.retryability |> should.equal(NonRetryable)
      err.code |> should.equal("GRANT_REVOKED_AT_EFFECT_TIME")
    }
  }
}

pub fn cross_workspace_principal_refused_for_readonly_and_mutation_test() {
  // Principal is bound to a different workspace root than the active one.
  let foreign_principal =
    principal.from_launcher_env(
      actor: "agy-worker-20261030",
      client: ClientProfile("agy"),
      workspace_root: "/home/an/other-workspace",
      session_id: "sess-xws",
    )

  let active_fence =
    admission.TaskFence(
      plan_id: "20261029-1913-mcp-server-completion",
      task_id: "T05",
      worker_id: "agy-worker-20261030",
      attempt: 1,
      task_state: admission.TaskExecuting,
      lease_until_ms: 5_000_000,
      grant: Some(admission.GrantTicket(
        grant_id: "grant-xws-01",
        scope: TaskScopedMutation,
        revoked: False,
        expires_at_ms: 5_000_000,
        workspace_root: "/home/an/NAS-setup/uos",
      )),
    )

  let ctx =
    admission.AdmissionContext(
      principal: foreign_principal,
      mode: admission.EnforcedMode,
      now_ms: 1_000_000,
      workspace_root: "/home/an/NAS-setup/uos",
      task_fence: Some(active_fence),
    )

  // ReadOnly effect class must also be refused on workspace mismatch.
  let assert Ok(read_spec) = registry.lookup("public", "plan_status")
  case admission.admit(ctx, read_spec, dict.new()) {
    Ok(_) -> should.fail()
    Error(err) -> {
      err.code |> should.equal("PRINCIPAL_WORKSPACE_MISMATCH")
      err.retryability |> should.equal(NonRetryable)
    }
  }

  // Mutation effect class must also be refused on workspace mismatch.
  let assert Ok(mut_spec) = registry.lookup("public", "sa_task_complete")
  let args =
    dict.from_list([
      #("plan_id", "20261029-1913-mcp-server-completion"),
      #("task_id", "T05"),
    ])
  case admission.admit(ctx, mut_spec, args) {
    Ok(_) -> should.fail()
    Error(err) -> {
      err.code |> should.equal("PRINCIPAL_WORKSPACE_MISMATCH")
      err.retryability |> should.equal(NonRetryable)
    }
  }
}

pub fn live_fence_reader_observes_midflight_revocation_test() {
  let assert Ok(spec) = registry.lookup("public", "control_loop")
  let p =
    principal.from_launcher_env(
      actor: "agy-worker-20261030",
      client: ClientProfile("agy"),
      workspace_root: "/home/an/NAS-setup/uos",
      session_id: "sess-live",
    )

  let initial_grant =
    admission.GrantTicket(
      grant_id: "grant-live-01",
      scope: ControlMutation,
      revoked: False,
      expires_at_ms: 5_000_000,
      workspace_root: "/home/an/NAS-setup/uos",
    )
  let active_fence =
    admission.TaskFence(
      plan_id: "20261029-1913-mcp-server-completion",
      task_id: "T06",
      worker_id: "agy-worker-20261030",
      attempt: 1,
      task_state: admission.TaskExecuting,
      lease_until_ms: 5_000_000,
      grant: Some(initial_grant),
    )
  let base_ctx =
    admission.AdmissionContext(
      principal: p,
      mode: admission.EnforcedMode,
      now_ms: 1_000_000,
      workspace_root: "/home/an/NAS-setup/uos",
      task_fence: Some(active_fence),
    )

  let assert Ok(validated_call) =
    admission.admit(base_ctx, spec, dict.from_list([#("mode", "step")]))

  // The live reader observes a mid-flight revocation committed after admission.
  let revoked_fence =
    admission.TaskFence(
      ..active_fence,
      grant: Some(admission.GrantTicket(..initial_grant, revoked: True)),
    )
  let read_fence = fn() -> Option(admission.TaskFence) { Some(revoked_fence) }
  let read_clock_ms = fn() -> Int { 1_000_100 }

  case
    admission.verify_at_effect_time_live(
      base_ctx,
      validated_call,
      read_fence,
      read_clock_ms,
    )
  {
    Ok(_) -> should.fail()
    Error(err) -> {
      err.retryability |> should.equal(NonRetryable)
      err.code |> should.equal("GRANT_REVOKED_AT_EFFECT_TIME")
    }
  }
}
