//// Wave 11 — secret_api handler tests.
////
//// Verifies the auth gate + vault subprocess dispatch via
//// `vault_secret_api.handle_get_secret/2`. The vault subprocess paths are
//// validated via Bash side (see journal §48 verification matrix) — these
//// tests focus on the Gleam-side bearer/path/error contracts.
////
//// Honest deferred (see journal §48):
////   - End-to-end live HTTPS round-trip is verified manually with curl;
////     test harness here doesn't boot mist.

import cepaf_gleam/ui/wisp/secret_api
import gleeunit/should

pub fn no_auth_header_returns_401_test() {
  let #(status, body) = secret_api.handle_get_secret("", "anthropic_api_key")
  status |> should.equal(401)
  // body must be JSON with error="unauthorized"
  body |> should.not_equal("")
}

pub fn malformed_authz_returns_401_test() {
  // Not "Bearer " prefix
  let #(status, _) =
    secret_api.handle_get_secret("Basic abc123", "anthropic_api_key")
  status |> should.equal(401)
}

pub fn wrong_bearer_returns_401_test() {
  // Even if vault exists, wrong token must NEVER reach the vault subprocess
  let #(status, _) =
    secret_api.handle_get_secret(
      "Bearer obviously-wrong-token-deadbeef",
      "anthropic_api_key",
    )
  status |> should.equal(401)
}

pub fn extract_bearer_strips_prefix_test() {
  let result = secret_api.extract_bearer("Bearer abc123xyz")
  result |> should.equal(Ok("abc123xyz"))
}

pub fn extract_bearer_rejects_basic_test() {
  let result = secret_api.extract_bearer("Basic ZGVjb2Rl")
  case result {
    Error(_) -> should.equal(True, True)
    Ok(_) -> should.fail()
  }
}
