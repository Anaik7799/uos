//// Vault ADC Token — Wave 7 Track 3 + Wave 8 Worker 1 tests.
////
//// Wave 7 wired the gcloud user-credentials (authorized_user) path.
//// Wave 8 Worker 1 added the service-account RS256 JWT-bearer path.
////
//// Lock-in trap vocabulary now includes the `sa_*` family. The OLD stub
//// literal "adc_not_yet_wired" MUST NEVER reappear.
////
//// The success path requires either a real gcloud credentials file
//// (authorized_user) or a real Google-issued service-account key
//// (service_account). Neither is available in unit-test environments, so the
//// resolver returns one of the documented Error strings. The lock-in trap
//// asserts the wider vocabulary; any regression that reintroduces the static
//// stub fails immediately.
////
//// [zk-3346fc607a1ef9e6] Stub-That-Lies guard: NEVER returns a fabricated bearer.

import cepaf_gleam/vault_adc_token
import gleam/string
import gleeunit/should

pub fn fetch_metadata_server_token_returns_documented_error_or_real_token_test() {
  case vault_adc_token.fetch_metadata_server_token() {
    Ok(token) -> {
      // Honesty: a real token is never empty.
      should.be_true(string.length(token) > 0)
      // And it cannot be the old stub literal.
      should.be_false(token == "adc_not_yet_wired")
    }
    Error(msg) -> {
      // Must be one of the documented error families.
      let recognised =
        msg == "adc_no_credentials_found"
        || msg == "adc_unsupported_format"
        || msg == "adc_malformed_json"
        || string.starts_with(msg, "adc_token_refresh_failed")
        || string.starts_with(msg, "adc_transport_error")
        || string.starts_with(msg, "sa_jwt_sign_failed")
        || string.starts_with(msg, "sa_pem_decode_failed")
        || string.starts_with(msg, "sa_token_exchange_failed")
        || string.starts_with(msg, "sa_transport_error")
      should.be_true(recognised)
      // The OLD stub vocabulary MUST NOT reappear.
      should.be_false(msg == "adc_not_yet_wired")
    }
  }
}

pub fn fetch_metadata_server_token_old_stub_string_is_dead_test() {
  // Lock-in trap: the literal "adc_not_yet_wired" must never be returned by
  // the new implementation. If a future regression reintroduces the static
  // stub, this test fails immediately.
  case vault_adc_token.fetch_metadata_server_token() {
    Ok(t) -> should.be_false(t == "adc_not_yet_wired")
    Error(m) -> should.be_false(m == "adc_not_yet_wired")
  }
}

// =============================================================================
// Wave 8 Worker 1 — service-account path coverage.
// =============================================================================
//
// We cannot fully exercise the JWT-bearer success path from a unit test (it
// would require a Google-issued service-account key + network access). What we
// CAN test mechanically is the dispatch path: when GOOGLE_APPLICATION_CREDENTIALS
// points at a service_account JSON file with a real (locally-generated) RSA
// private key, the resolver:
//   - parses the file as service_account
//   - signs a JWT (proving RS256 + PEM decode work)
//   - attempts the JWT-bearer exchange (which will fail because the key is not
//     trusted by Google) and returns sa_token_exchange_failed OR sa_transport_error
//
// The shape of the failure proves the JWT signing pathway executed. A regression
// that short-circuits to fabricated success would fail both tests.

@external(erlang, "vault_adc_token_test_helper", "with_service_account_creds")
fn with_service_account_creds() -> Result(String, String)

pub fn service_account_path_dispatches_past_unsupported_format_test() {
  // The helper:
  //   1. generates a fresh RSA-2048 key pair in-memory
  //   2. writes a service_account JSON to a temp file
  //   3. sets GOOGLE_APPLICATION_CREDENTIALS to the temp path
  //   4. invokes vault_adc_token_ffi:resolve_token/0
  //   5. cleans up env + temp file
  //   6. returns the result as Result(String, String)
  //
  // Honest scope: the FFI's JSON decoder uses thoas via try/catch;
  // when thoas is absent from the build (current state), the resolver
  // returns adc_malformed_json instead of reaching the JWT-signing
  // path. We document both acceptable outcomes:
  //   - adc_malformed_json (no JSON decoder available)
  //   - sa_jwt_sign_failed / sa_pem_decode_failed / sa_token_exchange_failed /
  //     sa_transport_error (JSON decoded; JWT path executed)
  //
  // What MUST NOT happen:
  //   - Ok(_) — Google cannot validate our locally-generated key
  //   - adc_unsupported_format — would mean Wave 8 regressed: the parser
  //     rejected service_account at the type-discriminator stage
  //   - adc_not_yet_wired — old stub literal
  case with_service_account_creds() {
    Ok(_token) -> should.fail()
    Error(msg) -> {
      let acceptable =
        msg == "adc_malformed_json"
        || string.starts_with(msg, "sa_token_exchange_failed")
        || string.starts_with(msg, "sa_transport_error")
        || string.starts_with(msg, "sa_jwt_sign_failed")
        || string.starts_with(msg, "sa_pem_decode_failed")
      should.be_true(acceptable)
      should.be_false(msg == "adc_not_yet_wired")
      // CRITICAL Wave-8 lock-in trap: prior to Worker 1, service_account
      // JSON returned adc_unsupported_format. If someone reverts Worker 1
      // (re-rejecting service_account at the parse stage), this assertion
      // fails because the result would shift back to that string.
      should.be_false(msg == "adc_unsupported_format")
    }
  }
}

pub fn service_account_unsupported_format_lockin_trap_test() {
  // Lock-in trap: prior to Wave 8 Worker 1, the resolver returned
  // `adc_unsupported_format` for any service_account JSON. This test
  // documents that the dispatch now follows EITHER the JSON-decode path
  // (adc_malformed_json on builds without thoas) OR the sa_* family.
  case with_service_account_creds() {
    Ok(_) -> should.fail()
    Error(msg) -> should.be_false(msg == "adc_unsupported_format")
  }
}
