//// Vault GCP Secret Manager I/O — Slice D tests (Phase 3, post-FFI-flip).
////
//// LOCK-IN TRAP UPGRADE ([zk-3346fc607a1ef9e6]): the prior tests asserted
//// `Error("http_not_yet_wired")`. After Phase 3 wired real `httpc:request`
//// against `secretmanager.googleapis.com`, that token MUST NOT appear.
//// Validation errors (empty project, invalid secret_id) are still
//// deterministic and unchanged.

import cepaf_gleam/vault_gcp_sm.{SecretManagerRef, SmAdcToken}
import cepaf_gleam/vault_gcp_sm_io
import gleam/string
import gleeunit/should

const ok_token = SmAdcToken("ya29.fake-test-token")

const ok_project = "c3i-eu-north1"

fn assert_not_unwired_token(result: Result(String, String)) -> Nil {
  case result {
    Error(msg) -> {
      string.contains(msg, "http_not_yet_wired")
      |> should.be_false
      Nil
    }
    Ok(_) -> Nil
  }
}

// =====================================================================
// Phase 3 lock-in: real wire — no "http_not_yet_wired" anywhere
// =====================================================================

pub fn list_secrets_does_not_return_unwired_token_test() {
  vault_gcp_sm_io.list_secrets(ok_project, 50, ok_token)
  |> assert_not_unwired_token
}

pub fn access_secret_does_not_return_unwired_token_test() {
  let ref = SecretManagerRef(project: ok_project, secret_id: "openrouter_key")
  vault_gcp_sm_io.access_secret(ref, "latest", ok_token)
  |> assert_not_unwired_token
}

pub fn add_version_does_not_return_unwired_token_test() {
  let ref = SecretManagerRef(project: ok_project, secret_id: "openrouter_key")
  vault_gcp_sm_io.add_version(ref, "cGF5bG9hZA==", ok_token)
  |> assert_not_unwired_token
}

// =====================================================================
// Pre-FFI validation guard (deterministic, no network)
// =====================================================================

pub fn list_secrets_fails_fast_on_empty_project_test() {
  vault_gcp_sm_io.list_secrets("", 50, ok_token)
  |> should.equal(Error("empty_project"))
}

pub fn access_secret_fails_fast_on_uppercase_secret_id_test() {
  let ref = SecretManagerRef(project: ok_project, secret_id: "OpenRouterKey")
  let result = vault_gcp_sm_io.access_secret(ref, "latest", ok_token)
  case result {
    Error(msg) -> {
      let is_validation_error = case msg {
        "invalid_secret_id: " <> _ -> True
        _ -> False
      }
      is_validation_error |> should.be_true
    }
    Ok(_) -> should.fail()
  }
}

pub fn add_version_fails_fast_on_dash_secret_id_test() {
  let ref = SecretManagerRef(project: ok_project, secret_id: "open-router-key")
  let result = vault_gcp_sm_io.add_version(ref, "cGF5", ok_token)
  case result {
    Error(msg) -> {
      let is_validation_error = case msg {
        "invalid_secret_id: " <> _ -> True
        _ -> False
      }
      is_validation_error |> should.be_true
    }
    Ok(_) -> should.fail()
  }
}

pub fn add_version_fails_fast_on_empty_secret_id_test() {
  let ref = SecretManagerRef(project: ok_project, secret_id: "")
  vault_gcp_sm_io.add_version(ref, "cGF5", ok_token)
  |> should.equal(Error("empty_secret_id"))
}
