//// Safe C04/C05 command-line adapter.
////
//// This entrypoint only performs current-state validation and dry runs. It has
//// no branch mutation, deployment, restart, mitigation or rollback adapter.
//// Policy and authorization fields are caller-supplied declarations and the
//// output explicitly does not claim authenticated authority.

import argv
import gleam/int
import gleam/io
import gleam/json
import gleam/option.{None}
import gleam/result
import gleam/string
import uos_swarm/action_boundary as action

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

fn number(value: String) -> Result(Int, String) {
  int.parse(value) |> result.replace_error("expected an integer")
}

fn refs(value: String) -> List(String) {
  case value {
    "-" -> []
    _ -> string.split(value, ",")
  }
}

fn authorization(
  request: action.Request,
  policy_version: String,
  expires_us: Int,
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
    expires_us,
    authority_ref,
  )
}

fn candidate_receipt(
  candidate: String,
  evidence: List(String),
  expires_boot_us: Int,
) -> Result(action.CandidateReceipt, String) {
  case evidence {
    [runtime_evidence, formal_evidence, ..] ->
      Ok(action.CandidateReceipt(
        candidate,
        action.CandidateVerified,
        0,
        expires_boot_us,
        runtime_evidence,
        formal_evidence,
      ))
    _ ->
      Error("candidate dry run requires runtime and formal evidence references")
  }
}

pub fn run(arguments: List(String)) -> Result(String, String) {
  case arguments {
    [
      root,
      "integration-dry-run",
      session,
      epoch_text,
      candidate,
      "inspect",
      evidence_text,
      policy_version,
      policy_expiry_text,
      authorization_expiry_text,
      authority_ref,
      operation_id,
    ] -> {
      use epoch <- result.try(number(epoch_text))
      use policy_expiry <- result.try(number(policy_expiry_text))
      use authorization_expiry <- result.try(number(authorization_expiry_text))
      let evidence = refs(evidence_text)
      use candidate_receipt <- result.try(candidate_receipt(
        candidate,
        evidence,
        policy_expiry,
      ))
      let operation = action.InspectIntegration
      let command =
        action.Integration(action.IntegrationCommand(
          candidate,
          operation,
          evidence,
        ))
      let request = action.Request(operation_id, session, epoch, command)
      let policy =
        action.PolicySnapshot(
          policy_version,
          candidate_receipt,
          [action.AllowIntegration(session, operation)],
          policy_expiry,
        )
      action.observe_dry_run(
        root,
        request,
        policy,
        authorization(
          request,
          policy_version,
          authorization_expiry,
          authority_ref,
        ),
      )
    }
    [
      root,
      "runtime-dry-run",
      session,
      epoch_text,
      service,
      candidate,
      operation_text,
      "-",
      postcheck_ref,
      runtime_evidence_ref,
      formal_evidence_ref,
      policy_version,
      policy_expiry_text,
      authorization_expiry_text,
      authority_ref,
      operation_id,
    ] -> {
      use epoch <- result.try(number(epoch_text))
      use policy_expiry <- result.try(number(policy_expiry_text))
      use authorization_expiry <- result.try(number(authorization_expiry_text))
      use candidate_receipt <- result.try(candidate_receipt(
        candidate,
        [runtime_evidence_ref, formal_evidence_ref],
        policy_expiry,
      ))
      use operation <- result.try(case operation_text {
        "observe" -> Ok(action.ObserveRuntime)
        "diagnose" -> Ok(action.DiagnoseRuntime)
        _ -> Error("CLI permits only observe or diagnose runtime dry runs")
      })
      let command =
        action.Runtime(action.RuntimeAction(
          service,
          candidate,
          operation,
          None,
          postcheck_ref,
        ))
      let request = action.Request(operation_id, session, epoch, command)
      let policy =
        action.PolicySnapshot(
          policy_version,
          candidate_receipt,
          [action.AllowRuntime(session, service, operation)],
          policy_expiry,
        )
      action.observe_dry_run(
        root,
        request,
        policy,
        authorization(
          request,
          policy_version,
          authorization_expiry,
          authority_ref,
        ),
      )
    }
    [_, "integration-dry-run", ..] ->
      Error("CLI permits only inspect for integration dry runs")
    [_, "runtime-dry-run", ..] ->
      Error(
        "CLI permits only observe or diagnose runtime dry runs; rollback must be '-'",
      )
    _ -> Error(usage())
  }
}

pub fn usage() -> String {
  "gleam run -m action_boundary_cli -- <state_root> integration-dry-run "
  <> "<session> <epoch> <candidate> inspect <evidence_csv> <policy_version> "
  <> "<policy_expires_us> <authorization_expires_us> <authority_ref> <operation_id>\n"
  <> "gleam run -m action_boundary_cli -- <state_root> runtime-dry-run "
  <> "<session> <epoch> <service> <deployed_revision> <observe|diagnose> - "
  <> "<postcheck_ref> <runtime_evidence_ref> <formal_evidence_ref> "
  <> "<policy_version> <policy_expires_us> "
  <> "<authorization_expires_us> <authority_ref> <operation_id>\n"
  <> "Dry-run only. Caller-supplied references are not authenticated authority."
}

pub fn main() -> Nil {
  case run(argv.load().arguments) {
    Ok(output) -> io.println(output)
    Error(reason) -> {
      io.println(
        json.to_string(
          json.object([
            #("ok", json.bool(False)),
            #("error", json.string(reason)),
          ]),
        ),
      )
      halt(1)
    }
  }
}
