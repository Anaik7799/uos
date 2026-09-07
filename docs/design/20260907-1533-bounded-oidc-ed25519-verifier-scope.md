# Bounded FerrisKey OIDC Ed25519 verifier scope

Tags: `#fractal-l0` `#zero-muda` `#oidc` `#security`

Canonical file: [UOS live viewer](http://nas-1.tail55d152.ts.net:4100/docs/design/20260907-1533-bounded-oidc-ed25519-verifier-scope.md)

## Purpose and boundary

This change implements the FerrisKey deployment profile used by the UOS Wisp API: compact JWS tokens signed with EdDSA over Ed25519 and verified against a trusted, issuer-bound, preloaded JWKS snapshot. It does not claim general JOSE, OIDC discovery, IAM, key fetching, token encryption, or token exchange support.

The verification request path has no network I/O. The `jwks_url` configuration field remains provenance for the external operator-controlled refresher; token headers cannot provide `jku`, `jwk`, `x5u`, or other key authority. Static bearer mode remains available only when `FERRISKEY_ENABLED` is false. Once OIDC mode is selected, every OIDC error is final and cannot become static administrator authentication.

## Acceptance algebra

The observable decision is:

`accept ≙ bounded-compact-structure ∧ canonical-base64url ∧ duplicate-free-JSON ∧ allowed-header ∧ exact-kid ∧ valid-key-profile ∧ valid-Ed25519-signature ∧ fresh-snapshot ∧ exact-issuer ∧ audience-membership ∧ valid-time-window ∧ nonempty-subject`

Each conjunct is deny-producing. The pure Wisp policy has two initial authorities, `StaticMode(expected_token)` and `OidcMode(config)`, selected from trusted process configuration before attacker input is evaluated. There is no combinator or transition from failed `OidcMode` to `StaticMode`.

## Bounded profile

- Compact JWT size is 1–8192 bytes with exactly three nonempty canonical unpadded base64url segments.
- The protected header permits only `alg`, `kid`, and optional `typ`; `alg` must be `EdDSA`, `typ` must be `JWT` when present, and `kid` is an exact nonempty match of at most 128 bytes.
- Signature length is exactly 64 bytes. OTP verifies `crypto:verify(eddsa, none, SigningInput, Signature, [PublicKey, ed25519])`.
- JWKS JSON is at most 32768 bytes and contains 1–16 unique keys. Every key must be `kty=OKP`, `crv=Ed25519`, `alg=EdDSA`, a canonical 32-byte `x`, and an exact `kid`. Optional `use` and `key_ops` are restricted to `sig` and `["verify"]`.
- OTP JSON decoding rejects duplicate members at every object depth and trailing non-whitespace data.
- `iss` is exact, required `aud` membership accepts the JWT string or array form, `exp` must be in the future, optional `nbf` and `iat` are bounded by 60 seconds of clock skew and precede `exp`, and `sub` must be nonempty and at most 512 characters.
- Snapshot age is positive and capped at 3600 seconds. Validation rejects an absent, future-dated, or expired snapshot.

## Operator provisioning and refresh

OIDC mode requires these values before starting or restarting the Wisp service:

- `FERRISKEY_ENABLED=true`
- `FERRISKEY_ISSUER_URL=<exact trusted issuer>`
- `FERRISKEY_AUDIENCE=<this API's audience>`
- `FERRISKEY_CLIENT_ID=<registered client identifier>`
- `FERRISKEY_JWKS_SNAPSHOT=<pre-fetched public JWKS JSON>`
- `FERRISKEY_JWKS_LOADED_AT=<trusted Unix timestamp for fetch completion>`
- `FERRISKEY_JWKS_MAX_AGE_SECONDS=<positive age, default 300, maximum 3600>`

The external issuer-controlled refresher must fetch and validate the configured issuer's JWKS, then replace the preloaded values and restart or otherwise rebuild the immutable `OidcConfig` through `load_jwks_snapshot`. No production snapshot or secret is included in this candidate. Snapshot values are public verification keys, but their provenance and freshness remain security-critical.

## Standards basis

- [RFC 8725 JWT Best Current Practices](https://www.rfc-editor.org/rfc/rfc8725.html): explicit algorithm verification, issuer/key binding, and audience validation.
- [RFC 8037 CFRG curves in JOSE](https://www.rfc-editor.org/rfc/rfc8037.html): OKP, Ed25519, EdDSA, and JWK `x` representation.
- [RFC 7517 JSON Web Key](https://www.rfc-editor.org/rfc/rfc7517.html): JWK Set structure and duplicate-member handling.
- [Erlang/OTP `json` module](https://www.erlang.org/doc/apps/stdlib/json.html): callback decoding used to reject duplicate keys.

## Comprehensive verification checklist

### Domain 1 — Metadata, timestamp, and Tailscale navigation

- [x] 1. Timestamp prefix is `20260907-1533-`, derived from NTP-synchronized host time.
- [x] 2. Canonical full Tailscale FQDN file link is present.
- [x] 3. Scope, profile boundary, and operator inputs are explicit.
- [x] 4. Evidence references use stable standards URLs.

### Domain 2 — Zero-Muda purity and storage safety

- [x] 5. No Bevy, Graphite, Graphene, storage mutation, or native dependency is introduced.
- [x] 6. Verification uses bounded OTP standard-library operations only.
- [x] 7. Test fixtures contain public RFC key material only; no live token, private key, or secret is present.
- [x] 8. Request verification performs zero network I/O and rejects token-directed key authority.

### Domain 3 — Testing gold standard and math gates

- [x] 9. A real signed Ed25519 fixture proves the positive path.
- [x] 10. Tamper, wrong-key, `none`, duplicate JSON, header, issuer, audience, expiry, time, snapshot, size, and fallback negatives are executable.
- [x] 11. The acceptance conjunction is stated as the independent semantic oracle.
- [x] 12. OTP 29 compile, format, source check, and focused EUnit commands are recorded in the paired journal.

### Domain 4 — Cross-language control and observability

- [x] 13. Gleam owns typed configuration, claims, time, issuer, audience, subject, role, and mode policy.
- [x] 14. Erlang FFI is limited to strict JSON/base64 parsing and OTP crypto verification.
- [x] 15. Existing structured authentication error output remains available without key material disclosure.

### Domain 5 — Tri-sovereign governance and Jujutsu monorepo

- [x] 16. Work is isolated in the assigned standalone Jujutsu sibling workspace.
- [x] 17. Candidate is based on `c08ec3942e12c41d2ac60c3ab4e954969e3983ae`; integration and deployment remain external gates.
- [x] 18. The candidate is identified by stable change ID `kozsqvqtssvp` and will be frozen before handoff.
