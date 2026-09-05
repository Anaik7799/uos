//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/zk_integrity</module>
////     <fsharp-lineage>None — novel ZK content-hash verification gate (OP-3)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>
////       Content-hash verification gate before Zettelkasten injection.
////       Ensures holons arrive unmodified by computing FNV-1a over the raw
////       content string and comparing against a caller-supplied expected hash.
////
////       Batch verification is the primary use-case: the ZK pipeline calls
////       batch_verify(holons) where each tuple is (holon_id, content, expected_hash).
////       The result list is 1:1 with input — order is preserved.
////
////       Gate: all_valid(checks) MUST return True before any holon is written
////       to the SQLite FTS5 Smriti.db store (SC-SATYA-009).
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>SC-SATYA-009, SC-AVP-001, SC-MUDA-001, SC-SIL4-001, SC-FUNC-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       FNV-1a hash algorithm (from manifest_signer) ↪ integrity check ADT.
////       Pure functional: no I/O, no side-effects.
////     </morphism>
////     <morphism type="surjective" loss="cryptographic-strength">
////       FNV-1a is not collision-resistant against adversaries.
////       Mitigation: used only for accidental corruption detection;
////       adversarial verification delegates to Zenoh Ed25519 layer.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// ZK INTEGRITY — Content Hash Verification Before ZK Injection
//// अनृतं न वदेत् — Speak no untruth (Taittiriya Upanishad 1.11)
////
//// SC-SATYA-009: ALL Zettelkasten holons MUST be verified — unverified data
//// is pollution that degrades institutional memory.

import cepaf_gleam/ha/manifest_signer
import gleam/int
import gleam/list
import gleam/string

// =============================================================================
// Public types
// =============================================================================

/// Result of verifying a single holon's content against its expected hash.
pub type IntegrityCheck {
  IntegrityCheck(
    /// Unique identifier of the holon (e.g. "zk-1234").
    holon_id: String,
    /// The hash the caller claims the content should produce.
    expected_hash: String,
    /// The hash actually computed from the supplied content.
    actual_hash: String,
    /// True iff expected_hash == actual_hash.
    valid: Bool,
  )
}

// =============================================================================
// Core verification functions
// =============================================================================

/// Verify a single holon: compute FNV-1a hash of content and compare with expected.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">hash comparison ↪ pure IntegrityCheck ADT</morphism>
///   <formal-proof>
///     <P>holon_id is non-empty, content is UTF-8, expected_hash is 8-char hex</P>
///     <C>verify_holon(holon_id, content, expected_hash)</C>
///     <Q>IntegrityCheck with valid=True iff actual matches expected; no panics</Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn verify_holon(
  holon_id: String,
  content: String,
  expected_hash: String,
) -> IntegrityCheck {
  let actual = manifest_signer.compute_hash(content)
  IntegrityCheck(
    holon_id: holon_id,
    expected_hash: expected_hash,
    actual_hash: actual,
    valid: actual == expected_hash,
  )
}

/// Batch-verify a list of (holon_id, content, expected_hash) triples.
/// Output list is 1:1 with input list (order preserved).
pub fn batch_verify(
  holons: List(#(String, String, String)),
) -> List(IntegrityCheck) {
  list.map(holons, fn(h) {
    let #(id, content, expected) = h
    verify_holon(id, content, expected)
  })
}

// =============================================================================
// Aggregate helpers
// =============================================================================

/// True iff every check in the list is valid.
/// Returns True for an empty list (vacuous truth — nothing to reject).
pub fn all_valid(checks: List(IntegrityCheck)) -> Bool {
  list.all(checks, fn(c) { c.valid })
}

/// Count of checks that failed (actual_hash != expected_hash).
pub fn invalid_count(checks: List(IntegrityCheck)) -> Int {
  list.count(checks, fn(c) { !c.valid })
}

// =============================================================================
// Rendering helpers
// =============================================================================

/// Multi-line summary of batch results, one line per check.
pub fn summary(checks: List(IntegrityCheck)) -> String {
  let total = list.length(checks)
  let invalid = invalid_count(checks)
  let valid = total - invalid
  let header =
    "ZK Integrity: "
    <> int.to_string(valid)
    <> "/"
    <> int.to_string(total)
    <> " valid"
  let lines =
    list.map(checks, fn(c) {
      let status = case c.valid {
        True -> "OK"
        False -> "FAIL"
      }
      "  ["
      <> status
      <> "] "
      <> c.holon_id
      <> " expected="
      <> c.expected_hash
      <> " actual="
      <> c.actual_hash
    })
  string.join([header, ..lines], "\n")
}
