/// Manifest Signer Tests — FNV-1a provenance attestation (OP-2)
///
/// 12 tests covering: compute_hash, sign_manifest, sign_manifest_at,
/// verify_signature, summary, to_json.
///
/// Layer: L0_CONSTITUTIONAL
/// STAMP: SC-SIL4-001, SC-VER-001, SC-MUDA-001, SC-SATYA-001
/// Ultrathink: Focus #7 (Cryptographically Verifiable Event Sourcing)
///
/// प्रमाणं सत्यस्य मूलम् — Attestation is the root of truth
import cepaf_gleam/ha/manifest_signer.{
  compute_hash, sign_manifest, sign_manifest_at, summary, to_json,
  verify_signature,
}
import gleam/string
import gleeunit/should

// ===========================================================================
// 1. compute_hash — FNV-1a determinism
// ===========================================================================

pub fn hash_empty_string_is_eight_hex_chars_test() {
  let h = compute_hash("")
  string.length(h) |> should.equal(8)
}

pub fn hash_deterministic_same_content_test() {
  let h1 = compute_hash("hello world")
  let h2 = compute_hash("hello world")
  h1 |> should.equal(h2)
}

pub fn hash_different_content_produces_different_hash_test() {
  let h1 = compute_hash("foo")
  let h2 = compute_hash("bar")
  { h1 != h2 } |> should.be_true()
}

pub fn hash_result_is_lowercase_hex_test() {
  let h = compute_hash("C3I system")
  let valid_chars =
    string.to_graphemes(h)
    |> list_all_fn(fn(c) {
      c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
      || c == "a"
      || c == "b"
      || c == "c"
      || c == "d"
      || c == "e"
      || c == "f"
    })
  valid_chars |> should.be_true()
}

// ===========================================================================
// 2. sign_manifest — basic attestation
// ===========================================================================

pub fn sign_manifest_stores_filename_and_signer_test() {
  let sig = sign_manifest("my_module.gleam", "content here", "claude-agent")
  sig.filename |> should.equal("my_module.gleam")
  sig.signer |> should.equal("claude-agent")
}

pub fn sign_manifest_valid_flag_is_true_test() {
  let sig = sign_manifest("test.gleam", "some content", "op-2")
  sig.valid |> should.be_true()
}

pub fn sign_manifest_hash_matches_compute_hash_test() {
  let content = "pub fn hello() { \"world\" }"
  let sig = sign_manifest("hello.gleam", content, "agent")
  let expected_hash = compute_hash(content)
  sig.hash |> should.equal(expected_hash)
}

// ===========================================================================
// 3. sign_manifest_at — explicit timestamp
// ===========================================================================

pub fn sign_manifest_at_stores_timestamp_test() {
  let sig =
    sign_manifest_at("f.gleam", "content", "agent", "2026-04-17T12:00:00Z")
  sig.signed_at |> should.equal("2026-04-17T12:00:00Z")
}

// ===========================================================================
// 4. verify_signature — tamper detection
// ===========================================================================

pub fn verify_unchanged_content_returns_valid_test() {
  let content = "module content unchanged"
  let sig = sign_manifest("m.gleam", content, "agent")
  let result = verify_signature(sig, content)
  result.valid |> should.be_true()
}

pub fn verify_tampered_content_returns_invalid_test() {
  let original = "original content"
  let tampered = "tampered content"
  let sig = sign_manifest("m.gleam", original, "agent")
  let result = verify_signature(sig, tampered)
  result.valid |> should.be_false()
}

// ===========================================================================
// 5. summary and to_json
// ===========================================================================

pub fn summary_contains_filename_test() {
  let sig = sign_manifest("my_file.gleam", "content", "agent")
  { string.contains(summary(sig), "my_file.gleam") } |> should.be_true()
}

pub fn summary_contains_valid_status_test() {
  let sig = sign_manifest("f.gleam", "c", "agent")
  { string.contains(summary(sig), "VALID") } |> should.be_true()
}

pub fn to_json_contains_hash_key_test() {
  let sig = sign_manifest("f.gleam", "c", "agent")
  let j = to_json(sig)
  { string.contains(j, "\"hash\"") } |> should.be_true()
}

pub fn to_json_valid_true_for_fresh_signature_test() {
  let sig = sign_manifest("f.gleam", "c", "agent")
  let j = to_json(sig)
  { string.contains(j, "\"valid\":true") } |> should.be_true()
}

// ===========================================================================
// Helpers
// ===========================================================================

fn list_all_fn(xs: List(a), pred: fn(a) -> Bool) -> Bool {
  case xs {
    [] -> True
    [h, ..t] ->
      case pred(h) {
        False -> False
        True -> list_all_fn(t, pred)
      }
  }
}
