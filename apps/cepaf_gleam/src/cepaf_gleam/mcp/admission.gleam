// UOS MCP Effect-Time Admission & Authority Fencing
// Centralizes admit(context, spec, args) -> Result(ValidatedCall, ToolError)
// and verify_at_effect_time(context, validated_call).

import cepaf_gleam/mcp/principal.{type Principal}
import cepaf_gleam/mcp/types.{
  type AuthorityScope, type EffectClass, type ToolError, type ToolSpec,
  AuditOnly, ControlActuation, ControlMutation, Mutating, NonRetryable,
  PublicReadOnly, ReadOnly, ReleaseAuthority, ScopedObservation,
  TaskScopedMutation, ToolError, VerificationGate,
}
import gleam/dict.{type Dict}
import gleam/option.{type Option, None, Some}

pub type EnforcementMode {
  EnforcedMode
  AuditOnlyMode
}

pub type TaskLifecycleState {
  TaskAvailable
  TaskExecuting
  TaskCompleted
}

pub type GrantTicket {
  GrantTicket(
    grant_id: String,
    scope: AuthorityScope,
    revoked: Bool,
    expires_at_ms: Int,
    workspace_root: String,
  )
}

pub type TaskFence {
  TaskFence(
    plan_id: String,
    task_id: String,
    worker_id: String,
    attempt: Int,
    task_state: TaskLifecycleState,
    lease_until_ms: Int,
    grant: Option(GrantTicket),
  )
}

pub type AdmissionContext {
  AdmissionContext(
    principal: Principal,
    mode: EnforcementMode,
    now_ms: Int,
    workspace_root: String,
    task_fence: Option(TaskFence),
  )
}

pub type ValidatedCall {
  ValidatedCall(
    spec: ToolSpec,
    principal: Principal,
    arguments: Dict(String, String),
    plan_id: Option(String),
    task_id: Option(String),
    attempt: Option(Int),
    grant_id: Option(String),
  )
}

pub fn admit(
  context: AdmissionContext,
  spec: ToolSpec,
  args: Dict(String, String),
) -> Result(ValidatedCall, ToolError) {
  case principal.workspace_root(context.principal) == context.workspace_root {
    False ->
      Error(authority_error(
        "PRINCIPAL_WORKSPACE_MISMATCH",
        "Principal workspace root does not match active workspace",
      ))
    True -> admit_workspace_checked(context, spec, args)
  }
}

fn admit_workspace_checked(
  context: AdmissionContext,
  spec: ToolSpec,
  args: Dict(String, String),
) -> Result(ValidatedCall, ToolError) {
  case context.mode, is_mutation_effect(spec.effect_class) {
    AuditOnlyMode, True ->
      Error(authority_error(
        "AUDIT_ONLY_MUTATION_FORBIDDEN",
        "AuditOnly mode cannot admit Mutating or ControlActuation tools",
      ))
    _, _ -> verify_effect_class(context, spec, args, False)
  }
}

pub fn verify_at_effect_time(
  context: AdmissionContext,
  call: ValidatedCall,
) -> Result(ValidatedCall, ToolError) {
  case principal.workspace_root(context.principal) == context.workspace_root {
    False ->
      Error(authority_error(
        "PRINCIPAL_WORKSPACE_MISMATCH",
        "Principal workspace root does not match active workspace",
      ))
    True -> verify_at_effect_time_workspace_checked(context, call)
  }
}

pub fn verify_at_effect_time_live(
  base_context: AdmissionContext,
  call: ValidatedCall,
  read_fence: fn() -> Option(TaskFence),
  read_clock_ms: fn() -> Int,
) -> Result(ValidatedCall, ToolError) {
  let context =
    AdmissionContext(
      ..base_context,
      now_ms: read_clock_ms(),
      task_fence: read_fence(),
    )
  verify_at_effect_time(context, call)
}

fn verify_at_effect_time_workspace_checked(
  context: AdmissionContext,
  call: ValidatedCall,
) -> Result(ValidatedCall, ToolError) {
  case context.mode, is_mutation_effect(call.spec.effect_class) {
    AuditOnlyMode, True ->
      Error(authority_error(
        "AUDIT_ONLY_MUTATION_FORBIDDEN",
        "AuditOnly mode cannot execute mutations at effect time",
      ))
    _, _ -> verify_effect_class(context, call.spec, call.arguments, True)
  }
}

fn verify_effect_class(
  context: AdmissionContext,
  spec: ToolSpec,
  args: Dict(String, String),
  at_effect_time: Bool,
) -> Result(ValidatedCall, ToolError) {
  case spec.effect_class {
    ReadOnly | VerificationGate ->
      case context.task_fence {
        None ->
          Ok(ValidatedCall(
            spec: spec,
            principal: context.principal,
            arguments: args,
            plan_id: None,
            task_id: None,
            attempt: None,
            grant_id: None,
          ))
        Some(fence) ->
          Ok(ValidatedCall(
            spec: spec,
            principal: context.principal,
            arguments: args,
            plan_id: Some(fence.plan_id),
            task_id: Some(fence.task_id),
            attempt: Some(fence.attempt),
            grant_id: option.map(fence.grant, fn(g) { g.grant_id }),
          ))
      }
    Mutating | ControlActuation ->
      verify_fenced_mutation(context, spec, args, at_effect_time)
  }
}

fn verify_fenced_mutation(
  context: AdmissionContext,
  spec: ToolSpec,
  args: Dict(String, String),
  at_effect_time: Bool,
) -> Result(ValidatedCall, ToolError) {
  case context.task_fence {
    None ->
      Error(authority_error(
        "MISSING_TASK_FENCE",
        "Mutating tool requires an active Sa-plan task fence",
      ))
    Some(fence) -> {
      case fence.task_state {
        TaskCompleted ->
          Error(authority_error(
            "COMPLETED_TASK_NOT_REUSABLE",
            "Completed Sa-plan task cannot be reused as mutation authority",
          ))
        TaskAvailable ->
          Error(authority_error(
            "UNCLAIMED_TASK_NOT_AUTHORITATIVE",
            "Task must be in executing state with active lease",
          ))
        TaskExecuting ->
          case fence.worker_id == principal.actor_id(context.principal) {
            False ->
              Error(authority_error(
                "PRINCIPAL_WORKER_MISMATCH",
                "Transport principal does not match task lease owner",
              ))
            True ->
              case fence.lease_until_ms <= context.now_ms {
                True ->
                  Error(authority_error(
                    "TASK_LEASE_EXPIRED",
                    "Sa-plan task lease has expired",
                  ))
                False ->
                  verify_grant_ticket(
                    context,
                    spec,
                    args,
                    fence,
                    at_effect_time,
                  )
              }
          }
      }
    }
  }
}

fn verify_grant_ticket(
  context: AdmissionContext,
  spec: ToolSpec,
  args: Dict(String, String),
  fence: TaskFence,
  at_effect_time: Bool,
) -> Result(ValidatedCall, ToolError) {
  case fence.grant {
    None ->
      Error(authority_error(
        "MISSING_AUTHORITY_GRANT",
        "Mutating tool requires an explicit authority grant ticket",
      ))
    Some(grant) -> {
      case grant.revoked {
        True ->
          Error(authority_error(
            case at_effect_time {
              True -> "GRANT_REVOKED_AT_EFFECT_TIME"
              False -> "GRANT_REVOKED"
            },
            "Authority grant ticket has been revoked",
          ))
        False ->
          case grant.expires_at_ms <= context.now_ms {
            True ->
              Error(authority_error(
                "GRANT_EXPIRED",
                "Authority grant ticket has expired",
              ))
            False ->
              case grant.workspace_root == context.workspace_root {
                False ->
                  Error(authority_error(
                    "GRANT_WORKSPACE_MISMATCH",
                    "Grant workspace root does not match active workspace",
                  ))
                True -> grant_scope_check(context, spec, args, fence, grant)
              }
          }
      }
    }
  }
}

fn grant_scope_check(
  context: AdmissionContext,
  spec: ToolSpec,
  args: Dict(String, String),
  fence: TaskFence,
  grant: GrantTicket,
) -> Result(ValidatedCall, ToolError) {
  case grant.scope {
    PublicReadOnly | ScopedObservation | AuditOnly ->
      Error(authority_error(
        "GRANT_SCOPE_INSUFFICIENT",
        "Read-only or audit grant scope cannot authorize mutations",
      ))
    TaskScopedMutation ->
      case spec.effect_class {
        ControlActuation ->
          Error(authority_error(
            "CONTROL_MUTATION_SCOPE_REQUIRED",
            "ControlActuation tool requires ControlMutation or ReleaseAuthority grant scope",
          ))
        Mutating | ReadOnly | VerificationGate ->
          Ok(validated_mutation(context, spec, args, fence, grant))
      }
    ControlMutation | ReleaseAuthority ->
      Ok(validated_mutation(context, spec, args, fence, grant))
  }
}

fn validated_mutation(
  context: AdmissionContext,
  spec: ToolSpec,
  args: Dict(String, String),
  fence: TaskFence,
  grant: GrantTicket,
) -> ValidatedCall {
  ValidatedCall(
    spec: spec,
    principal: context.principal,
    arguments: args,
    plan_id: Some(fence.plan_id),
    task_id: Some(fence.task_id),
    attempt: Some(fence.attempt),
    grant_id: Some(grant.grant_id),
  )
}

fn is_mutation_effect(effect: EffectClass) -> Bool {
  case effect {
    Mutating | ControlActuation -> True
    ReadOnly | VerificationGate -> False
  }
}

fn authority_error(code: String, reason: String) -> ToolError {
  ToolError(code: code, reason: reason, retryability: NonRetryable)
}
