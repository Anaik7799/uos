//// vault_pii_scrub_test — Pass-29 exhaustive coverage of the 7-shape
//// API-key scrubber for vault audit log + Wisp REST defense-in-depth.

import cepaf_gleam/vault_pii_scrub.{
  AnthropicKey, GithubOauth, GithubPat, GoogleApiKey, OpenAiProjectKey,
  OpenRouterKey, SlackBotToken, contains_secret_shape, scrub, shape_token,
}
import gleam/string
import gleeunit/should

// =====================================================================
// Per-shape detection
// =====================================================================

pub fn detects_anthropic_key_test() {
  let r = scrub("token=sk-ant-api03-AbCdEf123_-")
  string.contains(r.cleaned, "[REDACTED:anthropic]") |> should.equal(True)
  string.contains(r.cleaned, "sk-ant-api03-") |> should.equal(False)
  r.redactions |> should.equal(1)
}

pub fn detects_openrouter_key_test() {
  let r = scrub("Bearer sk-or-v1-DEADBEEF1234_")
  string.contains(r.cleaned, "[REDACTED:openrouter]") |> should.equal(True)
  r.redactions |> should.equal(1)
}

pub fn detects_openai_project_key_test() {
  let r = scrub("api: sk-proj-XYZ_abc-123")
  string.contains(r.cleaned, "[REDACTED:openai_project]") |> should.equal(True)
}

pub fn detects_google_api_key_test() {
  let r = scrub("?key=" <> "AIzaSy" <> "A_VeryLong_GoogleApiKey1234")
  string.contains(r.cleaned, "[REDACTED:google_api]") |> should.equal(True)
}

pub fn detects_github_pat_test() {
  let r = scrub("token=ghp_ABCDEFG1234567")
  string.contains(r.cleaned, "[REDACTED:github_pat]") |> should.equal(True)
}

pub fn detects_github_oauth_test() {
  let r = scrub("auth=gho_xyz1234")
  string.contains(r.cleaned, "[REDACTED:github_oauth]") |> should.equal(True)
}

pub fn detects_slack_bot_token_test() {
  let r = scrub("Authorization: xoxb-12345-67890-abcdefg")
  string.contains(r.cleaned, "[REDACTED:slack_bot]") |> should.equal(True)
}

// =====================================================================
// Multiple-shape scenarios
// =====================================================================

pub fn detects_multiple_shapes_in_one_string_test() {
  let r = scrub("anthropic=sk-ant-api03-X github=ghp_Y google=AIzaZ123")
  r.redactions |> should.equal(3)
  // All three redaction tokens present
  string.contains(r.cleaned, "anthropic") |> should.equal(True)
  string.contains(r.cleaned, "github_pat") |> should.equal(True)
  string.contains(r.cleaned, "google_api") |> should.equal(True)
}

pub fn detects_multiple_occurrences_of_same_shape_test() {
  let r = scrub("k1=sk-ant-api03-AAA k2=sk-ant-api03-BBB")
  r.redactions |> should.equal(2)
}

// =====================================================================
// Negative — clean input must remain clean
// =====================================================================

pub fn empty_string_yields_empty_clean_result_test() {
  let r = scrub("")
  r.cleaned |> should.equal("")
  r.redactions |> should.equal(0)
  r.shapes_found |> should.equal([])
}

pub fn plain_text_unchanged_test() {
  let r = scrub("hello world this has no secrets")
  r.cleaned |> should.equal("hello world this has no secrets")
  r.redactions |> should.equal(0)
}

pub fn similar_but_not_matching_prefixes_unchanged_test() {
  // sk-ant- (without api03) is NOT the canonical Anthropic shape
  let r = scrub("not a key: sk-ant-foo bar")
  r.cleaned |> should.equal("not a key: sk-ant-foo bar")
  r.redactions |> should.equal(0)
}

pub fn vault_state_string_remains_clean_test() {
  // Common audit log entries MUST NOT trigger false positives
  let r = scrub("vault_state=Active sealed=false uptime=300s")
  r.cleaned |> should.equal("vault_state=Active sealed=false uptime=300s")
  r.redactions |> should.equal(0)
}

// =====================================================================
// contains_secret_shape — quick guard for pre-write checks
// =====================================================================

pub fn contains_secret_shape_true_for_anthropic_test() {
  contains_secret_shape("debug: sk-ant-api03-XYZ leak") |> should.equal(True)
}

pub fn contains_secret_shape_false_for_clean_test() {
  contains_secret_shape("clean log entry") |> should.equal(False)
}

pub fn contains_secret_shape_true_for_google_test() {
  contains_secret_shape("?key=AIzaSyABCDEF12345") |> should.equal(True)
}

// =====================================================================
// shape_token — stable token names for telemetry
// =====================================================================

pub fn shape_token_anthropic_test() {
  shape_token(AnthropicKey) |> should.equal("anthropic")
}

pub fn shape_token_openrouter_test() {
  shape_token(OpenRouterKey) |> should.equal("openrouter")
}

pub fn shape_token_openai_project_test() {
  shape_token(OpenAiProjectKey) |> should.equal("openai_project")
}

pub fn shape_token_google_api_test() {
  shape_token(GoogleApiKey) |> should.equal("google_api")
}

pub fn shape_token_github_pat_test() {
  shape_token(GithubPat) |> should.equal("github_pat")
}

pub fn shape_token_github_oauth_test() {
  shape_token(GithubOauth) |> should.equal("github_oauth")
}

pub fn shape_token_slack_bot_test() {
  shape_token(SlackBotToken) |> should.equal("slack_bot")
}

// =====================================================================
// Tail boundary — token consumption stops at non-token char
// =====================================================================

pub fn redaction_preserves_trailing_quote_test() {
  let r = scrub("\"sk-ant-api03-XYZ\" | rest")
  // The closing quote is NOT consumed as part of the token
  string.contains(r.cleaned, "\" | rest") |> should.equal(True)
}

pub fn redaction_preserves_trailing_space_test() {
  let r = scrub("key: sk-ant-api03-AAA next_field")
  string.contains(r.cleaned, " next_field") |> should.equal(True)
}

pub fn redaction_preserves_trailing_comma_test() {
  let r = scrub("[\"sk-ant-api03-AAA\",\"k2\"]")
  string.contains(r.cleaned, ",\"k2\"]") |> should.equal(True)
}

// =====================================================================
// Realistic operational scenarios
// =====================================================================

pub fn scrubs_audit_log_entry_with_anthropic_leak_test() {
  let entry =
    "{\"event\":\"put\",\"name\":\"anthropic_api_key\",\"value_LEAK\":\"sk-ant-api03-deadbeef123\"}"
  let r = scrub(entry)
  r.redactions |> should.equal(1)
  string.contains(r.cleaned, "[REDACTED:anthropic]") |> should.equal(True)
  // The structural JSON is preserved
  string.contains(r.cleaned, "\"event\":\"put\"") |> should.equal(True)
}

pub fn scrubs_curl_command_log_test() {
  let entry =
    "curl -H 'x-api-key: sk-ant-api03-X' -H 'X-Goog: AIzaY12345' https://api.example.com"
  let r = scrub(entry)
  r.redactions |> should.equal(2)
}

pub fn scrubs_zenoh_envelope_payload_test() {
  let envelope =
    "{\"caller\":\"nif\",\"masked_value\":\"redacted\",\"raw\":\"sk-or-v1-leakage\"}"
  let r = scrub(envelope)
  r.redactions |> should.equal(1)
  string.contains(r.cleaned, "openrouter") |> should.equal(True)
}
