//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/manifest_signer</module>
////     <fsharp-lineage>None — novel extension provenance attestation (OP-2)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>
////       Extension provenance attestation for Zenoh-injected manifests.
////       Computes a content hash (FNV-1a 32-bit folded to hex string), signs
////       the manifest with signer identity and timestamp, and verifies the
////       signature on later retrieval.
////
////       FNV-1a hash (Fowler-Noll-Vo 1a, 32-bit):
////         offset_basis = 2166136261
////         prime        = 16777619
////         h₀ = offset_basis
////         hᵢ = (hᵢ₋₁ XOR byte_i) × prime  (mod 2³²)
////
////       Properties:
////         1. DETERMINISTIC — same content always yields same hash string.
////         2. PURE          — no I/O, no mutable state.
////         3. FAST          — O(n) in content length; suitable for manifests.
////         4. COLLISION-RESISTANT enough for integrity gating (not cryptographic).
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>SC-SIL4-001, SC-VER-001, SC-MUDA-001, SC-FUNC-001, SC-SATYA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       FNV-1a hash algorithm ↪ Gleam pure function over String → String.
////       All arithmetic performed on Int (arbitrary precision in Erlang);
////       result folded into 8-char lowercase hex.
////     </morphism>
////     <morphism type="surjective" loss="cryptographic-strength">
////       FNV-1a is NOT a cryptographic hash — use only for integrity gating,
////       not for security. Mitigation: add Zenoh attestation layer for
////       adversarial contexts (SC-VER-079).
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// MANIFEST SIGNER — Extension Provenance Attestation
//// प्रमाणं सत्यस्य मूलम् — Attestation is the root of truth
////
//// FNV-1a 32-bit reference (Marek Majkowski adaptation):
////   https://en.wikipedia.org/wiki/Fowler–Noll–Vo_hash_function
////
//// Use cases:
////   • Verify a Gleam module was not tampered before ZK injection (OP-3 bridge).
////   • Provide a lightweight content fingerprint on Zenoh OTel spans.
////   • Record provenance of generated manifests in the ImmutableRegister.

import gleam/int
import gleam/list
import gleam/string

// =============================================================================
// Public types
// =============================================================================

/// Provenance attestation for a named manifest file.
pub type ManifestSignature {
  ManifestSignature(
    /// Original filename (e.g. "manifest_signer.gleam")
    filename: String,
    /// Hex-encoded FNV-1a 32-bit hash of the content at signing time.
    hash: String,
    /// ISO-8601 wall-clock string supplied by the caller (no stdlib DateTime).
    signed_at: String,
    /// Human-readable signer identity (e.g. "claude-agent/op-2").
    signer: String,
    /// True iff the stored hash still matches the content at verify time.
    valid: Bool,
  )
}

// =============================================================================
// Constants — FNV-1a 32-bit
// =============================================================================

const fnv_offset_basis: Int = 2_166_136_261

const fnv_prime: Int = 16_777_619

const mask_32: Int = 4_294_967_295

// =============================================================================
// Hash computation
// =============================================================================

/// Compute FNV-1a 32-bit hash of a UTF-8 string, returned as 8-char lowercase hex.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">FNV-1a ↪ pure String→String total function</morphism>
///   <formal-proof>
///     <P>content is a valid UTF-8 String</P>
///     <C>compute_hash(content)</C>
///     <Q>8-char lowercase hex String, same content always → same result</Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn compute_hash(content: String) -> String {
  let codepoints = string.to_utf_codepoints(content)
  let hash =
    list.fold(codepoints, fnv_offset_basis, fn(h, cp) {
      let byte = string.utf_codepoint_to_int(cp)
      int.bitwise_and(
        int.bitwise_and(int.bitwise_exclusive_or(h, byte) * fnv_prime, mask_32),
        mask_32,
      )
    })
  to_hex8(hash)
}

// =============================================================================
// Signing and verification
// =============================================================================

/// Produce a ManifestSignature by hashing content at signing time.
pub fn sign_manifest(
  filename: String,
  content: String,
  signer: String,
) -> ManifestSignature {
  let hash = compute_hash(content)
  ManifestSignature(
    filename: filename,
    hash: hash,
    signed_at: "unknown",
    signer: signer,
    valid: True,
  )
}

/// Sign with an explicit timestamp (for deterministic tests and audit logs).
pub fn sign_manifest_at(
  filename: String,
  content: String,
  signer: String,
  signed_at: String,
) -> ManifestSignature {
  let hash = compute_hash(content)
  ManifestSignature(
    filename: filename,
    hash: hash,
    signed_at: signed_at,
    signer: signer,
    valid: True,
  )
}

/// Verify that `sig.hash` still matches the current content.
///
/// Returns the signature with `valid` updated accordingly.
pub fn verify_signature(
  sig: ManifestSignature,
  content: String,
) -> ManifestSignature {
  let actual = compute_hash(content)
  ManifestSignature(..sig, valid: actual == sig.hash)
}

// =============================================================================
// Rendering helpers
// =============================================================================

/// One-line human-readable summary.
pub fn summary(sig: ManifestSignature) -> String {
  let status = case sig.valid {
    True -> "VALID"
    False -> "INVALID"
  }
  sig.filename
  <> " ["
  <> status
  <> "] hash="
  <> sig.hash
  <> " signer="
  <> sig.signer
  <> " at="
  <> sig.signed_at
}

/// Minimal JSON object string.
pub fn to_json(sig: ManifestSignature) -> String {
  let valid_str = case sig.valid {
    True -> "true"
    False -> "false"
  }
  "{"
  <> "\"filename\":\""
  <> sig.filename
  <> "\","
  <> "\"hash\":\""
  <> sig.hash
  <> "\","
  <> "\"signed_at\":\""
  <> sig.signed_at
  <> "\","
  <> "\"signer\":\""
  <> sig.signer
  <> "\","
  <> "\"valid\":"
  <> valid_str
  <> "}"
}

// =============================================================================
// Internal helpers
// =============================================================================

/// Convert an integer to exactly 8 lowercase hex characters.
fn to_hex8(n: Int) -> String {
  int.to_base16(int.bitwise_and(n, mask_32))
  |> string.lowercase
  |> pad_left_zeros(8)
}

fn pad_left_zeros(s: String, width: Int) -> String {
  let len = string.length(s)
  case len >= width {
    True -> s
    False -> string.repeat("0", width - len) <> s
  }
}
