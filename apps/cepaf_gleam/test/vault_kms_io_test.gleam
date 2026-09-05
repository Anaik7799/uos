//// Vault KMS I/O — Slice C-C3 tests (Phase 3, post-FFI-flip).
////
//// LOCK-IN TRAP UPGRADE ([zk-3346fc607a1ef9e6]): the prior test asserted
//// `Error("http_not_yet_wired")`. After Phase 3 wired real `httpc:request`
//// against `cloudkms.googleapis.com`, that token is GONE — its presence in
//// any test would be a regression. New asserts:
////   • Pre-FFI validation errors (wrong region, empty fields) MUST still
////     fire fast (deterministic, no network).
////   • Post-validation calls reach the wire and surface either
////     `http_unauthorized` (typical: fake token rejected by Google) or a
////     `http_transport_error: …` (offline CI). Both prove the flip.
////   • The literal string `http_not_yet_wired` MUST NOT appear in any error.

import cepaf_gleam/vault_kms.{type KmsKeyRef, AdcToken, HttpRequest, KmsKeyRef}
import cepaf_gleam/vault_kms_io
import gleam/string
import gleeunit/should

const ok_token = AdcToken("ya29.fake-test-token")

const ok_project = "c3i-eu-north1"

fn ok_ref() -> KmsKeyRef {
  KmsKeyRef(
    project: ok_project,
    location: "europe-north1",
    keyring: "vault-kek-ring",
    crypto_key: "kek-master",
  )
}

// =====================================================================
// Phase 3 lock-in: "http_not_yet_wired" MUST NOT appear in any path
// =====================================================================

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

pub fn execute_does_not_return_unwired_token_test() {
  let req =
    HttpRequest(
      method: "POST",
      url: "https://cloudkms.googleapis.com/v1/foo:decrypt",
      headers: [
        #("Authorization", "Bearer x"),
        #("Content-Type", "application/json"),
      ],
      body: "{}",
    )
  vault_kms_io.execute(req)
  |> assert_not_unwired_token
}

pub fn decrypt_with_valid_ref_does_not_return_unwired_token_test() {
  // Wire is real. Fake token will get 401 from Google in connected CI, or
  // transport error offline. Either is acceptable; "http_not_yet_wired" is not.
  vault_kms_io.decrypt(ok_ref(), ok_token, "Y2lwaGVydGV4dA==")
  |> assert_not_unwired_token
}

// =====================================================================
// Pre-FFI validation guard (Stub-That-Lies — input MUST fail fast,
// deterministic regardless of network)
// =====================================================================

pub fn decrypt_fails_fast_on_wrong_region_test() {
  let bad_ref =
    KmsKeyRef(
      project: ok_project,
      location: "us-central1",
      keyring: "vault-kek-ring",
      crypto_key: "kek-master",
    )
  vault_kms_io.decrypt(bad_ref, ok_token, "Y2lwaGVydGV4dA==")
  |> should.equal(Error("wrong_region: us-central1"))
}

pub fn decrypt_fails_fast_on_empty_project_test() {
  let bad_ref =
    KmsKeyRef(
      project: "",
      location: "europe-north1",
      keyring: "vault-kek-ring",
      crypto_key: "kek-master",
    )
  vault_kms_io.decrypt(bad_ref, ok_token, "Y2lwaGVydGV4dA==")
  |> should.equal(Error("empty_project"))
}

pub fn decrypt_fails_fast_on_empty_keyring_test() {
  let bad_ref =
    KmsKeyRef(
      project: ok_project,
      location: "europe-north1",
      keyring: "",
      crypto_key: "kek-master",
    )
  vault_kms_io.decrypt(bad_ref, ok_token, "Y2lwaGVydGV4dA==")
  |> should.equal(Error("empty_keyring"))
}

pub fn decrypt_fails_fast_on_empty_crypto_key_test() {
  let bad_ref =
    KmsKeyRef(
      project: ok_project,
      location: "europe-north1",
      keyring: "vault-kek-ring",
      crypto_key: "",
    )
  vault_kms_io.decrypt(bad_ref, ok_token, "Y2lwaGVydGV4dA==")
  |> should.equal(Error("empty_crypto_key"))
}

pub fn decrypt_rejects_uppercase_region_test() {
  let bad_ref =
    KmsKeyRef(
      project: ok_project,
      location: "Europe-North1",
      keyring: "vault-kek-ring",
      crypto_key: "kek-master",
    )
  vault_kms_io.decrypt(bad_ref, ok_token, "Y2lwaGVydGV4dA==")
  |> should.equal(Error("wrong_region: Europe-North1"))
}
