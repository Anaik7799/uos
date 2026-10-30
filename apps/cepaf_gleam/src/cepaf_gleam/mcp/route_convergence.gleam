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
  type AdmissionContext, type GrantTicket, type ValidatedCall, admit,
  verify_at_effect_time,
}
import cepaf_gleam/mcp/dispatch
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/supervisor
import cepaf_gleam/mcp/types.{
  type Outcome, type ToolError, type ToolSpec, Complete, ControlActuation,
  EvidenceRecord, Mutating, NonRetryable, Refused, ToolError,
}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}

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
          case verify_route_grant(spec, route_grant) {
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

fn verify_route_grant(
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
                True -> Ok(Nil)
              }
          }
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
    None -> True
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
  let rewritten = case outcome {
    Complete(payload, evidence) ->
      case candidate_evidence_mismatch(pool, store, evidence.candidate) {
        True ->
          Refused(ToolError(
            "CANDIDATE_EVIDENCE_MISMATCH",
            "Completion evidence names a candidate that is neither the active candidate nor the worker ledger candidate",
            NonRetryable,
          ))
        False ->
          Complete(
            payload,
            EvidenceRecord(
              ..evidence,
              candidate: store.active_candidate,
              route: route,
              tool: tool_name,
            ),
          )
      }
    _ -> outcome
  }
  #(rewritten, updated_pool)
}

fn candidate_evidence_mismatch(
  pool: supervisor.WorkerPool,
  store: FeatureEvidenceStore,
  evidence_candidate: String,
) -> Bool {
  evidence_candidate != ""
  && evidence_candidate != "uos-mcp"
  && evidence_candidate != pool.ledger.candidate
  && evidence_candidate != store.active_candidate
}
