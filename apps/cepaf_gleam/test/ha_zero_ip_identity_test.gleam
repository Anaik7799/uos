/// Zero-IP Identity Registry — 15-test suite
/// Layer: L7_FEDERATION
/// STAMP: SC-OPENCLAW-001, SC-SEC-001, SC-FED-001, SC-MUDA-001
///
/// SC-OPENCLAW-001: Devices join mesh via ECDSA-signed Zenoh tokens (no IP)
import cepaf_gleam/ha/zero_ip_identity.{
  Expired, InvalidSignature, Revoked, TokenClaim, Valid, active_token_count,
  expired_tokens, is_trusted, issue_token, prune_expired, registry_new,
  revoke_node, summary, token_to_string, trust_key, verify_token,
}
import gleam/string
import gleeunit/should

// ===========================================================================
// Registry Constructors
// ===========================================================================

pub fn registry_new_is_empty_test() {
  let r = registry_new()
  active_token_count(r) |> should.equal(0)
  r.trusted_keys |> should.equal([])
  r.revoked_nodes |> should.equal([])
}

pub fn trust_key_adds_to_allowlist_test() {
  let r = registry_new() |> trust_key("key-abc")
  is_trusted(r, "key-abc") |> should.equal(True)
}

pub fn trust_key_unknown_key_not_trusted_test() {
  let r = registry_new() |> trust_key("key-abc")
  is_trusted(r, "key-xyz") |> should.equal(False)
}

// ===========================================================================
// Token Issuance
// ===========================================================================

pub fn issue_token_increments_count_test() {
  let r = registry_new() |> trust_key("key1")
  let claim =
    TokenClaim(node_id: "node-1", capabilities: ["read"], ttl_seconds: 3600)
  let #(r2, _tok) = issue_token(r, claim, 1000, "key1")
  active_token_count(r2) |> should.equal(1)
}

pub fn issue_token_sets_correct_expiry_test() {
  let r = registry_new() |> trust_key("key1")
  let claim = TokenClaim(node_id: "node-1", capabilities: [], ttl_seconds: 100)
  let #(_r2, tok) = issue_token(r, claim, 500, "key1")
  tok.expires_at |> should.equal(600)
}

pub fn issue_token_nonce_contains_key_and_time_test() {
  let r = registry_new() |> trust_key("k1")
  let claim = TokenClaim(node_id: "n1", capabilities: [], ttl_seconds: 60)
  let #(_r2, tok) = issue_token(r, claim, 42, "k1")
  tok.nonce |> should.equal("k1-42")
}

// ===========================================================================
// Token Verification — Valid path
// ===========================================================================

pub fn verify_token_valid_test() {
  let r = registry_new() |> trust_key("key1")
  let claim = TokenClaim(node_id: "n1", capabilities: [], ttl_seconds: 3600)
  let #(r2, tok) = issue_token(r, claim, 1000, "key1")
  verify_token(r2, tok, 1001) |> should.equal(Valid)
}

// ===========================================================================
// Token Verification — Expired
// ===========================================================================

pub fn verify_token_expired_test() {
  let r = registry_new() |> trust_key("key1")
  let claim = TokenClaim(node_id: "n1", capabilities: [], ttl_seconds: 10)
  let #(r2, tok) = issue_token(r, claim, 1000, "key1")
  // current_time = 1011 > expires_at = 1010
  verify_token(r2, tok, 1011) |> should.equal(Expired)
}

// ===========================================================================
// Token Verification — InvalidSignature
// ===========================================================================

pub fn verify_token_invalid_signature_test() {
  let r = registry_new()
  // key NOT added to trusted_keys
  let claim = TokenClaim(node_id: "n1", capabilities: [], ttl_seconds: 3600)
  let #(r2, tok) = issue_token(r, claim, 1000, "untrusted-key")
  verify_token(r2, tok, 1001) |> should.equal(InvalidSignature)
}

// ===========================================================================
// Token Verification — Revoked
// ===========================================================================

pub fn verify_token_revoked_test() {
  let r = registry_new() |> trust_key("key1")
  let claim = TokenClaim(node_id: "n1", capabilities: [], ttl_seconds: 3600)
  let #(r2, tok) = issue_token(r, claim, 1000, "key1")
  let r3 = revoke_node(r2, "n1")
  verify_token(r3, tok, 1001) |> should.equal(Revoked)
}

// ===========================================================================
// Revocation
// ===========================================================================

pub fn revoke_node_idempotent_test() {
  let r = registry_new() |> revoke_node("n1") |> revoke_node("n1")
  r.revoked_nodes |> should.equal(["n1"])
}

// ===========================================================================
// Expiry Management
// ===========================================================================

pub fn expired_tokens_returns_old_tokens_test() {
  let r = registry_new() |> trust_key("k")
  let claim = TokenClaim(node_id: "n1", capabilities: [], ttl_seconds: 5)
  let #(r2, _) = issue_token(r, claim, 100, "k")
  let exp = expired_tokens(r2, 200)
  exp |> should.not_equal([])
}

pub fn prune_expired_removes_old_tokens_test() {
  let r = registry_new() |> trust_key("k")
  let claim = TokenClaim(node_id: "n1", capabilities: [], ttl_seconds: 5)
  let #(r2, _) = issue_token(r, claim, 100, "k")
  let r3 = prune_expired(r2, 200)
  active_token_count(r3) |> should.equal(0)
}

pub fn prune_expired_keeps_active_tokens_test() {
  let r = registry_new() |> trust_key("k")
  let claim = TokenClaim(node_id: "n1", capabilities: [], ttl_seconds: 3600)
  let #(r2, _) = issue_token(r, claim, 1000, "k")
  let r3 = prune_expired(r2, 1001)
  active_token_count(r3) |> should.equal(1)
}

// ===========================================================================
// Serialisation & Summary
// ===========================================================================

pub fn token_to_string_non_empty_test() {
  let r = registry_new() |> trust_key("k")
  let claim = TokenClaim(node_id: "n1", capabilities: ["read"], ttl_seconds: 60)
  let #(_r2, tok) = issue_token(r, claim, 1000, "k")
  let txt = token_to_string(tok)
  txt |> string.contains("n1") |> should.equal(True)
}

pub fn summary_shows_counts_test() {
  let r = registry_new() |> trust_key("k1") |> trust_key("k2")
  let txt = summary(r)
  txt |> string.contains("trusted_keys=2") |> should.equal(True)
}
