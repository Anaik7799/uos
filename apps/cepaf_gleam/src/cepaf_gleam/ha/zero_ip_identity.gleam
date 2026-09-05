//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/zero_ip_identity</module>
////     <fsharp-lineage>None — novel Zero-IP identity federation (F19)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L7_FEDERATION</layer>
////     <mesh-domain>
////       Zero-IP identity token lifecycle for the OpenClaw mesh.
////       Devices join the mesh via ECDSA-signed Zenoh tokens rather than
////       IP addresses. This module models the token issuance, verification,
////       revocation and registry pruning logic as pure functions.
////       Zero I/O — pure functional state-in / state-out interface.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>SC-OPENCLAW-001, SC-SEC-001, SC-FED-001, SC-MUDA-001, SC-FUNC-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Zero-IP identity concept ↪ Gleam pure state machine over List(IdentityToken).
////       No real cryptography — key_hash is a String standing in for a hash digest.
////     </morphism>
////     <morphism type="surjective" loss="cryptographic-verification">
////       Real ECDSA signature verification ↠ trusted_keys allowlist check.
////       Mitigation: Real signing is performed by the Rust sa-plan-daemon NIF layer;
////       this module models the policy and lifecycle logic only.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// ZERO-IP IDENTITY — F19
//// SC-OPENCLAW-001: OpenClaw motor capabilities — ECDSA-signed Zenoh tokens
//// SC-SEC-001:      Security controls — no IP-based identity
//// SC-FED-001:      Federation governance — nodes join via cryptographic identity
////
//// Token lifecycle:
////   issue_token  → verify_token (Valid | Expired | InvalidSignature | ...)
////   revoke_node  → verify_token returns Revoked
////   prune_expired → removes stale tokens
////
//// STAMP: SC-OPENCLAW-001, SC-SEC-001, SC-FED-001, SC-MUDA-001, SC-FUNC-001

import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public Types
// ---------------------------------------------------------------------------

/// An identity token issued to a node when it joins the mesh
pub type IdentityToken {
  IdentityToken(
    node_id: String,
    public_key_hash: String,
    issued_at: Int,
    expires_at: Int,
    nonce: String,
    capabilities: List(String),
  )
}

/// Result of verifying an identity token
pub type IdentityVerification {
  Valid
  Expired
  InvalidSignature
  UnknownNode
  Revoked
}

/// Registry of all known tokens and trust anchors
pub type IdentityRegistry {
  IdentityRegistry(
    tokens: List(IdentityToken),
    trusted_keys: List(String),
    revoked_nodes: List(String),
  )
}

/// Parameters for issuing a new token
pub type TokenClaim {
  TokenClaim(node_id: String, capabilities: List(String), ttl_seconds: Int)
}

// ---------------------------------------------------------------------------
// Constructors
// ---------------------------------------------------------------------------

/// Create an empty registry with no tokens, no trusted keys, no revocations
pub fn registry_new() -> IdentityRegistry {
  IdentityRegistry(tokens: [], trusted_keys: [], revoked_nodes: [])
}

// ---------------------------------------------------------------------------
// Trust Management
// ---------------------------------------------------------------------------

/// Add a public-key hash to the trusted-keys allowlist
pub fn trust_key(
  registry: IdentityRegistry,
  key_hash: String,
) -> IdentityRegistry {
  IdentityRegistry(
    ..registry,
    trusted_keys: list.flatten([registry.trusted_keys, [key_hash]]),
  )
}

/// Returns True if the given key_hash is in the trusted allowlist
pub fn is_trusted(registry: IdentityRegistry, key_hash: String) -> Bool {
  list.contains(registry.trusted_keys, key_hash)
}

// ---------------------------------------------------------------------------
// Token Issuance
// ---------------------------------------------------------------------------

/// Issue a new token for a node.
///
/// nonce = signing_key_hash <> "-" <> int.to_string(current_time)
/// expires_at = current_time + claim.ttl_seconds
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">TokenClaim ↪ IdentityToken in registry</morphism>
///   <formal-proof>
///     <P> signing_key_hash in registry.trusted_keys </P>
///     <C> issue_token(registry, claim, current_time, signing_key_hash) </C>
///     <Q> new token appended; token.expires_at = current_time + ttl </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn issue_token(
  registry: IdentityRegistry,
  claim: TokenClaim,
  current_time: Int,
  signing_key_hash: String,
) -> #(IdentityRegistry, IdentityToken) {
  let nonce = signing_key_hash <> "-" <> int.to_string(current_time)
  let token =
    IdentityToken(
      node_id: claim.node_id,
      public_key_hash: signing_key_hash,
      issued_at: current_time,
      expires_at: current_time + claim.ttl_seconds,
      nonce: nonce,
      capabilities: claim.capabilities,
    )
  let updated =
    IdentityRegistry(
      ..registry,
      tokens: list.flatten([registry.tokens, [token]]),
    )
  #(updated, token)
}

// ---------------------------------------------------------------------------
// Token Verification
// ---------------------------------------------------------------------------

/// Verify a token against the registry at current_time.
///
/// Order of checks:
///   1. node_id in revoked_nodes  → Revoked
///   2. current_time > expires_at → Expired
///   3. public_key_hash not in trusted_keys → InvalidSignature
///   4. token not in registry.tokens → UnknownNode
///   5. all checks pass → Valid
pub fn verify_token(
  registry: IdentityRegistry,
  token: IdentityToken,
  current_time: Int,
) -> IdentityVerification {
  case list.contains(registry.revoked_nodes, token.node_id) {
    True -> Revoked
    False ->
      case current_time > token.expires_at {
        True -> Expired
        False ->
          case list.contains(registry.trusted_keys, token.public_key_hash) {
            False -> InvalidSignature
            True ->
              case token_in_registry(registry, token) {
                False -> UnknownNode
                True -> Valid
              }
          }
      }
  }
}

// ---------------------------------------------------------------------------
// Revocation
// ---------------------------------------------------------------------------

/// Add a node_id to the revoked list (token stays in registry for audit)
pub fn revoke_node(
  registry: IdentityRegistry,
  node_id: String,
) -> IdentityRegistry {
  case list.contains(registry.revoked_nodes, node_id) {
    True -> registry
    False ->
      IdentityRegistry(
        ..registry,
        revoked_nodes: list.flatten([registry.revoked_nodes, [node_id]]),
      )
  }
}

// ---------------------------------------------------------------------------
// Expiry Management
// ---------------------------------------------------------------------------

/// Return all tokens whose expires_at < current_time
pub fn expired_tokens(
  registry: IdentityRegistry,
  current_time: Int,
) -> List(IdentityToken) {
  list.filter(registry.tokens, fn(t) { t.expires_at < current_time })
}

/// Remove expired tokens from the registry
pub fn prune_expired(
  registry: IdentityRegistry,
  current_time: Int,
) -> IdentityRegistry {
  let active =
    list.filter(registry.tokens, fn(t) { t.expires_at >= current_time })
  IdentityRegistry(..registry, tokens: active)
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

/// Number of tokens currently in the registry
pub fn active_token_count(registry: IdentityRegistry) -> Int {
  list.length(registry.tokens)
}

/// Human-readable representation of a single token
pub fn token_to_string(token: IdentityToken) -> String {
  string.join(
    [
      "Token[",
      token.node_id,
      "] key=",
      token.public_key_hash,
      " issued=",
      int.to_string(token.issued_at),
      " expires=",
      int.to_string(token.expires_at),
      " caps=",
      int.to_string(list.length(token.capabilities)),
    ],
    "",
  )
}

/// One-line summary of the registry
pub fn summary(registry: IdentityRegistry) -> String {
  string.join(
    [
      "IdentityRegistry tokens=",
      int.to_string(active_token_count(registry)),
      " trusted_keys=",
      int.to_string(list.length(registry.trusted_keys)),
      " revoked=",
      int.to_string(list.length(registry.revoked_nodes)),
    ],
    "",
  )
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

fn token_in_registry(registry: IdentityRegistry, token: IdentityToken) -> Bool {
  list.any(registry.tokens, fn(t) {
    t.node_id == token.node_id && t.nonce == token.nonce
  })
}
