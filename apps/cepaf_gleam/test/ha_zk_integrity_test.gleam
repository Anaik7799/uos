/// ZK Integrity Tests — Content hash verification before ZK injection (OP-3)
///
/// 11 tests covering: verify_holon, batch_verify, all_valid, invalid_count, summary.
///
/// Layer: L0_CONSTITUTIONAL
/// STAMP: SC-SATYA-009, SC-AVP-001, SC-MUDA-001, SC-SIL4-001
/// Ultrathink: Focus #7 (Cryptographically Verifiable Event Sourcing),
///              Focus #5 (Continuous Formal Verification)
///
/// अनृतं न वदेत् — Speak no untruth (Taittiriya Upanishad 1.11)
import cepaf_gleam/ha/manifest_signer
import cepaf_gleam/ha/zk_integrity.{
  type IntegrityCheck, IntegrityCheck, all_valid, batch_verify, invalid_count,
  summary, verify_holon,
}
import gleam/string
import gleeunit/should

// ===========================================================================
// 1. verify_holon — single check
// ===========================================================================

pub fn verify_matching_hash_returns_valid_test() {
  let content = "holon body text for zk-0042"
  let expected = manifest_signer.compute_hash(content)
  let check = verify_holon("zk-0042", content, expected)
  check.valid |> should.be_true()
}

pub fn verify_wrong_hash_returns_invalid_test() {
  let check = verify_holon("zk-0043", "some content", "00000000")
  check.valid |> should.be_false()
}

pub fn verify_stores_holon_id_test() {
  let content = "body"
  let expected = manifest_signer.compute_hash(content)
  let check = verify_holon("zk-1234", content, expected)
  check.holon_id |> should.equal("zk-1234")
}

pub fn verify_stores_expected_and_actual_test() {
  let content = "test content"
  let expected = manifest_signer.compute_hash(content)
  let check = verify_holon("zk-abc", content, expected)
  check.expected_hash |> should.equal(expected)
  check.actual_hash |> should.equal(expected)
}

// ===========================================================================
// 2. batch_verify
// ===========================================================================

pub fn batch_verify_all_valid_test() {
  let c1 = "content one"
  let c2 = "content two"
  let holons = [
    #("zk-1", c1, manifest_signer.compute_hash(c1)),
    #("zk-2", c2, manifest_signer.compute_hash(c2)),
  ]
  let results = batch_verify(holons)
  all_valid(results) |> should.be_true()
}

pub fn batch_verify_one_bad_hash_test() {
  let holons = [
    #("zk-good", "good content", manifest_signer.compute_hash("good content")),
    #("zk-bad", "bad content", "deadbeef"),
  ]
  let results = batch_verify(holons)
  invalid_count(results) |> should.equal(1)
}

pub fn batch_verify_preserves_order_test() {
  let holons = [
    #("first", "a", manifest_signer.compute_hash("a")),
    #("second", "b", "wrong"),
    #("third", "c", manifest_signer.compute_hash("c")),
  ]
  let results = batch_verify(holons)
  let ids = list_map(results, fn(c: IntegrityCheck) { c.holon_id })
  ids |> should.equal(["first", "second", "third"])
}

pub fn batch_verify_empty_list_returns_empty_test() {
  batch_verify([]) |> should.equal([])
}

// ===========================================================================
// 3. all_valid and invalid_count
// ===========================================================================

pub fn all_valid_empty_list_returns_true_test() {
  all_valid([]) |> should.be_true()
}

pub fn invalid_count_all_valid_returns_zero_test() {
  let content = "good"
  let checks = [
    IntegrityCheck(
      holon_id: "h1",
      expected_hash: "abc",
      actual_hash: "abc",
      valid: True,
    ),
    IntegrityCheck(
      holon_id: "h2",
      expected_hash: "def",
      actual_hash: "def",
      valid: True,
    ),
  ]
  invalid_count(checks) |> should.equal(0)
  let _ = content
}

// ===========================================================================
// 4. summary
// ===========================================================================

pub fn summary_shows_valid_count_test() {
  let c = "body"
  let checks = batch_verify([#("zk-x", c, manifest_signer.compute_hash(c))])
  let s = summary(checks)
  { string.contains(s, "1/1 valid") } |> should.be_true()
}

// ===========================================================================
// Helpers
// ===========================================================================

fn list_map(xs: List(a), f: fn(a) -> b) -> List(b) {
  case xs {
    [] -> []
    [h, ..t] -> [f(h), ..list_map(t, f)]
  }
}
