//// Route convergence for the public, development-private, and successor-private
//// MCP harness routes.
////
//// A grant is bound to exactly one route. Overlapping tool names never widen a
//// grant across routes, private/mutating calls require explicit route scoping,
//// completion evidence is enforced on every finish path (including legacy
//// development), and successful evidence is rebound to the active candidate.

import cepaf_gleam/mcp/adapters/features.{
  type ExecutionReceipt, type FeatureEvidenceStore, valid_active_receipt,
  wrapper_raw_conflict,
}
import cepaf_gleam/mcp/admission.{
  type AdmissionContext, type GrantTicket, type TaskFence, type ValidatedCall,
  TaskExecuting, admit, verify_at_effect_time,
}
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/dispatch
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/supervisor
import cepaf_gleam/mcp/types.{
  type Outcome, type ToolError, type ToolSpec, AuditOnly, Complete,
  ControlActuation, ControlMutation, EvidenceRecord, Mutating, NonRetryable,
  PublicReadOnly, ReadOnly, Refused, ReleaseAuthority, ScopedObservation,
  ToolError, VerificationGate,
}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type RouteGrant {
  RouteGrant(
    allowed_route: String,
    allowed_tools: List(String),
    ticket: GrantTicket,
  )
}

pub fn admit_converged(
  context: AdmissionContext,
  route_grant: Option(RouteGrant),
  route: String,
  tool_name: String,
  args: Dict(String, String),
) -> Result(ValidatedCall, ToolError) {
  case registry.lookup(route, tool_name) {
    Error(err) -> Error(err)
    Ok(spec) ->
      case registry.verify_schema_digest(spec, spec.input_schema) {
        Error(err) -> Error(err)
        Ok(_) ->
          case
            verify_client_schema_pin(
              spec,
              dict.get(args, "_client_schema_digest") |> option.from_result,
            )
          {
            Error(err) -> Error(err)
            Ok(_) ->
              case verify_route_grant(context, spec, route_grant) {
                Error(err) -> Error(err)
                Ok(_) ->
                  case admit(context, spec, args) {
                    Error(err) -> Error(err)
                    Ok(call) -> verify_at_effect_time(context, call)
                  }
              }
          }
      }
  }
}

fn verify_route_grant(
  context: AdmissionContext,
  spec: ToolSpec,
  route_grant: Option(RouteGrant),
) -> Result(Nil, ToolError) {
  case requires_route_grant(spec) {
    False -> Ok(Nil)
    True ->
      case route_grant {
        None ->
          Error(ToolError(
            "ROUTE_GRANT_REQUIRED",
            "Tool "
              <> spec.name
              <> " on route "
              <> spec.route
              <> " requires an explicit route grant",
            NonRetryable,
          ))
        Some(rg) ->
          case rg.allowed_route == spec.route {
            False ->
              Error(ToolError(
                "CROSS_ROUTE_GRANT_FORBIDDEN",
                "Grant for route "
                  <> rg.allowed_route
                  <> " cannot authorize route "
                  <> spec.route,
                NonRetryable,
              ))
            True ->
              case list.contains(rg.allowed_tools, spec.name) {
                False ->
                  Error(ToolError(
                    "TOOL_NOT_IN_ROUTE_GRANT",
                    "Tool "
                      <> spec.name
                      <> " is not allowed by the grant for route "
                      <> spec.route,
                    NonRetryable,
                  ))
                True -> verify_route_grant_ticket(context, spec, rg)
              }
          }
      }
  }
}

fn verify_route_grant_ticket(
  context: AdmissionContext,
  spec: ToolSpec,
  rg: RouteGrant,
) -> Result(Nil, ToolError) {
  use _ <- result.try(case string.trim(rg.ticket.grant_id) != "" {
    True -> Ok(Nil)
    False ->
      Error(route_grant_error(
        "ROUTE_GRANT_ID_REQUIRED",
        "Route grant ticket must carry a non-empty grant_id",
      ))
  })
  use _ <- result.try(case rg.ticket.revoked {
    True ->
      Error(route_grant_error(
        "ROUTE_GRANT_REVOKED",
        "Route grant ticket has been revoked",
      ))
    False -> Ok(Nil)
  })
  use _ <- result.try(case rg.ticket.expires_at_ms > context.now_ms {
    True -> Ok(Nil)
    False ->
      Error(route_grant_error(
        "ROUTE_GRANT_EXPIRED",
        "Route grant ticket has expired",
      ))
  })
  use _ <- result.try(case rg.ticket.workspace_root == context.workspace_root {
    True -> Ok(Nil)
    False ->
      Error(route_grant_error(
        "ROUTE_GRANT_WORKSPACE_MISMATCH",
        "Route grant ticket is bound to a foreign workspace root",
      ))
  })
  use _ <- result.try(verify_route_grant_scope(spec, rg))
  verify_route_grant_fence(context, spec, rg)
}

fn verify_route_grant_scope(
  spec: ToolSpec,
  rg: RouteGrant,
) -> Result(Nil, ToolError) {
  verify_ticket_scope(spec, rg.ticket.scope)
}

fn verify_ticket_scope(
  spec: ToolSpec,
  scope: types.AuthorityScope,
) -> Result(Nil, ToolError) {
  case scope {
    AuditOnly ->
      Error(route_grant_error(
        "ROUTE_GRANT_SCOPE_INSUFFICIENT",
        "AuditOnly grant scope cannot authorize a route grant",
      ))
    _ ->
      case spec.effect_class {
        ControlActuation ->
          case scope {
            ControlMutation | ReleaseAuthority -> Ok(Nil)
            _ ->
              Error(route_grant_error(
                "ROUTE_GRANT_SCOPE_INSUFFICIENT",
                "ControlActuation route call requires ControlMutation or ReleaseAuthority grant scope",
              ))
          }
        Mutating ->
          case scope {
            PublicReadOnly | ScopedObservation ->
              Error(route_grant_error(
                "ROUTE_GRANT_SCOPE_INSUFFICIENT",
                "Mutating route call requires a mutation grant scope",
              ))
            _ -> Ok(Nil)
          }
        ReadOnly | VerificationGate -> Ok(Nil)
      }
  }
}

fn verify_route_grant_fence(
  context: AdmissionContext,
  spec: ToolSpec,
  rg: RouteGrant,
) -> Result(Nil, ToolError) {
  case context.task_fence {
    None ->
      case is_private_route(spec.route) {
        True ->
          Error(route_grant_error(
            "MISSING_TASK_FENCE",
            "Private route call requires an active TaskFence",
          ))
        False -> Ok(Nil)
      }
    Some(fence) -> verify_route_grant_fence_binding(context, spec, rg, fence)
  }
}

fn verify_route_grant_fence_binding(
  context: AdmissionContext,
  spec: ToolSpec,
  rg: RouteGrant,
  fence: TaskFence,
) -> Result(Nil, ToolError) {
  case is_private_route(spec.route) {
    False ->
      case fence.grant {
        Some(fg) -> {
          use _ <- result.try(verify_ticket_scope(spec, fg.scope))
          case route_grant_ticket_equal(fg, rg.ticket) {
            True -> Ok(Nil)
            False -> route_grant_ticket_mismatch()
          }
        }
        None -> Ok(Nil)
      }
    True -> {
      use _ <- result.try(case fence.task_state {
        TaskExecuting -> Ok(Nil)
        _ ->
          Error(route_grant_error(
            "TASK_FENCE_NOT_EXECUTING",
            "Private route call requires an executing task fence",
          ))
      })
      use _ <- result.try(
        case fence.worker_id == principal.actor_id(context.principal) {
          True -> Ok(Nil)
          False ->
            Error(route_grant_error(
              "PRINCIPAL_WORKER_MISMATCH",
              "Transport principal does not match task lease owner",
            ))
        },
      )
      use _ <- result.try(case fence.lease_until_ms > context.now_ms {
        True -> Ok(Nil)
        False ->
          Error(route_grant_error(
            "TASK_LEASE_EXPIRED",
            "Sa-plan task lease has expired",
          ))
      })
      case fence.grant {
        None ->
          Error(route_grant_error(
            "MISSING_AUTHORITY_GRANT",
            "Private route call requires an explicit authority grant ticket",
          ))
        Some(fg) -> {
          use _ <- result.try(verify_ticket_scope(spec, fg.scope))
          use _ <- result.try(case route_grant_ticket_equal(fg, rg.ticket) {
            True -> Ok(Nil)
            False -> route_grant_ticket_mismatch()
          })
          use _ <- result.try(case fg.revoked {
            True ->
              Error(route_grant_error(
                "ROUTE_GRANT_REVOKED",
                "Fence authority grant ticket has been revoked",
              ))
            False -> Ok(Nil)
          })
          use _ <- result.try(case fg.expires_at_ms > context.now_ms {
            True -> Ok(Nil)
            False ->
              Error(route_grant_error(
                "ROUTE_GRANT_EXPIRED",
                "Fence authority grant ticket has expired",
              ))
          })
          case fg.workspace_root == context.workspace_root {
            True -> Ok(Nil)
            False ->
              Error(route_grant_error(
                "ROUTE_GRANT_WORKSPACE_MISMATCH",
                "Fence authority grant ticket is bound to a foreign workspace root",
              ))
          }
        }
      }
    }
  }
}

fn route_grant_ticket_mismatch() -> Result(Nil, ToolError) {
  Error(route_grant_error(
    "ROUTE_GRANT_TICKET_MISMATCH",
    "Route grant ticket does not match the active task fence authority grant",
  ))
}

fn route_grant_ticket_equal(fg: GrantTicket, rt: GrantTicket) -> Bool {
  fg.grant_id == rt.grant_id
  && fg.scope == rt.scope
  && fg.revoked == rt.revoked
  && fg.expires_at_ms == rt.expires_at_ms
  && fg.workspace_root == rt.workspace_root
}

fn route_grant_error(code: String, reason: String) -> ToolError {
  ToolError(code, reason, NonRetryable)
}

fn is_private_route(route: String) -> Bool {
  route == "development" || route == "successor"
}

pub fn verify_client_schema_pin(
  spec: ToolSpec,
  expected_digest: Option(String),
) -> Result(Nil, ToolError) {
  case expected_digest {
    None -> Ok(Nil)
    Some(digest) ->
      case digest == spec.schema_digest {
        True -> Ok(Nil)
        False ->
          Error(ToolError(
            "SCHEMA_MIGRATION_REQUIRED",
            "Client schema digest mismatch for "
              <> spec.route
              <> ":"
              <> spec.name,
            NonRetryable,
          ))
      }
  }
}

fn requires_route_grant(spec: ToolSpec) -> Bool {
  spec.route == "development"
  || spec.route == "successor"
  || spec.effect_class == Mutating
  || spec.effect_class == ControlActuation
}

pub fn execute_converged(
  pool: supervisor.WorkerPool,
  context: AdmissionContext,
  route_grant: Option(RouteGrant),
  store: FeatureEvidenceStore,
  route: String,
  tool_name: String,
  args: Dict(String, String),
  edge_handler: fn(ToolSpec, Dict(String, String)) -> Result(String, String),
) -> #(Outcome, supervisor.WorkerPool) {
  case admit_converged(context, route_grant, route, tool_name, args) {
    Error(err) -> #(Refused(err), pool)
    Ok(call) ->
      case tool_name == "harness_finish" {
        True ->
          case completion_evidence_ok(context, store, args) {
            False -> #(
              Refused(ToolError(
                "COMPLETION_EVIDENCE_REQUIRED",
                "Legacy or successor finish requires candidate-bound passing execution receipt",
                NonRetryable,
              )),
              pool,
            )
            True ->
              run_converged(
                pool,
                context,
                store,
                route,
                tool_name,
                call,
                edge_handler,
              )
          }
        False ->
          run_converged(
            pool,
            context,
            store,
            route,
            tool_name,
            call,
            edge_handler,
          )
      }
  }
}

fn completion_evidence_ok(
  context: AdmissionContext,
  store: FeatureEvidenceStore,
  args: Dict(String, String),
) -> Bool {
  case dict.get(args, "task_id") {
    Error(_) -> False
    Ok(task_id) ->
      case dict.get(store.receipts, task_id) {
        Error(_) -> False
        Ok(receipt) ->
          valid_completion_receipt(context, store, receipt, task_id)
      }
  }
}

fn valid_completion_receipt(
  context: AdmissionContext,
  store: FeatureEvidenceStore,
  receipt: ExecutionReceipt,
  task_id: String,
) -> Bool {
  valid_active_receipt(store, receipt)
  && !wrapper_raw_conflict(receipt)
  && receipt.feature_or_task_id == task_id
  && fence_task_matches(context, task_id)
}

fn fence_task_matches(context: AdmissionContext, task_id: String) -> Bool {
  case context.task_fence {
    None -> False
    Some(fence) -> fence.task_id == task_id
  }
}

fn run_converged(
  pool: supervisor.WorkerPool,
  context: AdmissionContext,
  store: FeatureEvidenceStore,
  route: String,
  tool_name: String,
  call: ValidatedCall,
  edge_handler: fn(ToolSpec, Dict(String, String)) -> Result(String, String),
) -> #(Outcome, supervisor.WorkerPool) {
  let #(outcome, updated_pool) =
    dispatch.dispatch_validated(pool, context, call, fn(arguments) {
      edge_handler(call.spec, arguments)
    })
  let rewritten =
    verify_outcome_candidate(updated_pool, store, route, tool_name, outcome)
  #(rewritten, updated_pool)
}

pub fn verify_outcome_candidate(
  pool: supervisor.WorkerPool,
  store: FeatureEvidenceStore,
  route: String,
  tool_name: String,
  outcome: Outcome,
) -> Outcome {
  case outcome {
    Complete(payload, evidence) ->
      case candidate_evidence_mismatch(pool, store, evidence.candidate) {
        True ->
          Refused(ToolError(
            "CANDIDATE_EVIDENCE_MISMATCH",
            "Completion evidence candidate is missing, generic, or mismatches active store/ledger candidate",
            NonRetryable,
          ))
        False ->
          Complete(
            payload,
            EvidenceRecord(..evidence, route: route, tool: tool_name),
          )
      }
    _ -> outcome
  }
}

fn candidate_evidence_mismatch(
  pool: supervisor.WorkerPool,
  store: FeatureEvidenceStore,
  evidence_candidate: String,
) -> Bool {
  !candidate_id.is_valid(evidence_candidate)
  || !candidate_id.is_valid(store.active_candidate)
  || !candidate_id.is_valid(pool.ledger.candidate)
  || evidence_candidate != store.active_candidate
  || evidence_candidate != pool.ledger.candidate
}
