//// Command-line operational surface for typed recovery activation.
////
//// Usage:
////   gleam run -m recovery_activation_cli -- status <intent.json>
////   gleam run -m recovery_activation_cli -- prepare <intent.json> <grant.json>
////   gleam run -m recovery_activation_cli -- activate <intent.json> <grant.json>
////   gleam run -m recovery_activation_cli -- rollback <intent.json> <grant.json>

import cepaf_gleam/harness/recovery_activation as ra
import gleam/io
import gleam/json
import gleam/result
import gleam/string
import simplifile

@external(erlang, "recovery_activation_ffi", "get_argv")
fn get_argv() -> List(String)

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

pub fn main() {
  let args = get_argv()
  case args {
    ["status", intent_path] -> handle_status(intent_path)
    ["prepare", intent_path, grant_path] ->
      handle_prepare(intent_path, grant_path)
    ["activate", intent_path, grant_path] ->
      handle_activate(intent_path, grant_path)
    ["rollback", intent_path, grant_path] ->
      handle_rollback(intent_path, grant_path)
    _ -> print_usage()
  }
}

fn print_usage() {
  io.println(
    "UOS Typed Recovery Activation CLI
Commands:
  status <intent.json>
  prepare <intent.json> <grant.json>
  activate <intent.json> <grant.json>
  rollback <intent.json> <grant.json>
",
  )
  halt(1)
}

fn print_error(stage: String, detail: String) {
  let err_json =
    json.object([
      #("schema", json.string("uos.recovery-cli-error.v1")),
      #("status", json.string("ERROR")),
      #("stage", json.string(stage)),
      #("detail", json.string(detail)),
    ])
    |> json.to_string
  io.println(err_json)
  halt(1)
}

fn load_intent(path: String) -> Result(ra.ActivationIntent, String) {
  use _ <- result.try(
    ra.path_safety_check(path)
    |> result.map_error(fn(e) { "intent path failed safety check: " <> e }),
  )
  use raw <- result.try(
    simplifile.read(path)
    |> result.map_error(fn(e) {
      "could not read intent file: " <> simplifile.describe_error(e)
    }),
  )
  json.parse(raw, ra.intent_decoder())
  |> result.map_error(fn(_) { "invalid intent JSON structure" })
}

fn load_grant(path: String) -> Result(ra.ReviewedGrant, String) {
  use _ <- result.try(
    ra.check_private_file(path)
    |> result.map_error(fn(e) { "grant file failed security check: " <> e }),
  )
  use raw <- result.try(
    simplifile.read(path)
    |> result.map_error(fn(e) {
      "could not read grant file: " <> simplifile.describe_error(e)
    }),
  )
  json.parse(raw, ra.grant_decoder())
  |> result.map_error(fn(_) { "invalid grant JSON structure" })
}

fn handle_status(intent_path: String) {
  case load_intent(intent_path) {
    Error(err) -> print_error("load_intent", err)
    Ok(intent) -> {
      let st = ra.query_status(intent)
      io.println(ra.status_to_json(st))
    }
  }
}

fn handle_prepare(intent_path: String, grant_path: String) {
  case load_intent(intent_path), load_grant(grant_path) {
    Error(err), _ -> print_error("load_intent", err)
    _, Error(err) -> print_error("load_grant", err)
    Ok(intent), Ok(grant) -> {
      case ra.prepare(intent, grant) {
        Ok(Nil) -> {
          let out =
            json.object([
              #("schema", json.string("uos.recovery-prepare.v1")),
              #("status", json.string("PREPARE_OK")),
              #("intent_id", json.string(intent.intent_id)),
              #("target_path", json.string(intent.target_path)),
              #("candidate_sha256", json.string(intent.candidate_sha256)),
            ])
            |> json.to_string
          io.println(out)
        }
        Error(act_err) ->
          print_error("prepare_validation", string.inspect(act_err))
      }
    }
  }
}

fn handle_activate(intent_path: String, grant_path: String) {
  case load_intent(intent_path), load_grant(grant_path) {
    Error(err), _ -> print_error("load_intent", err)
    _, Error(err) -> print_error("load_grant", err)
    Ok(intent), Ok(grant) -> {
      case ra.activate(intent, grant) {
        Ok(receipt) -> io.println(ra.receipt_to_json(receipt))
        Error(act_err) ->
          print_error("activation", string.inspect(act_err))
      }
    }
  }
}

fn handle_rollback(intent_path: String, grant_path: String) {
  case load_intent(intent_path), load_grant(grant_path) {
    Error(err), _ -> print_error("load_intent", err)
    _, Error(err) -> print_error("load_grant", err)
    Ok(intent), Ok(grant) -> {
      case ra.rollback(intent, grant) {
        Ok(receipt) -> io.println(ra.rollback_receipt_to_json(receipt))
        Error(err) -> print_error("rollback", string.inspect(err))
      }
    }
  }
}
