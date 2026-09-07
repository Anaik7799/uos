# Bounded FerrisKey OIDC Ed25519 verifier journal

Tags: `#fractal-l0` `#zero-muda` `#oidc` `#security`

Canonical file: [UOS live viewer](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260907-1533-bounded-oidc-ed25519-verifier-journal.md)

## 1. Scope & Trigger

`AUTH-OIDC` required real Ed25519 JWT signature and audience verification, a bounded fresh JWKS snapshot, and removal of the OIDC-to-static administrator downgrade. Work was isolated in `.uos-workspaces/codex-oidc-verifier` on stable Jujutsu change ID `kozsqvqtssvp`, rebased while empty from `a9d40c6e6369` to candidate base `c08ec3942e12c41d2ac60c3ab4e954969e3983ae`.

## 2. Pre-State Assessment

`auth/oidc.gleam` decoded only the middle JWT segment, parsed `sub`, `exp`, and `iss`, left audience and roles empty, and performed no signature verification. `ui/wisp/auth.gleam` retried every failed OIDC token as `C3I_API_TOKEN`, granting the static principal administrator roles on equality.

## 3. Execution Detail

The Gleam domain now holds an opaque validated snapshot with explicit load time and age, parses both legal audience forms plus FerrisKey realm roles, and enforces issuer, audience, subject, expiry, `nbf`, and `iat`. A bounded Erlang adapter validates compact structure, canonical base64url, duplicate-free JSON, header and key profiles, and calls OTP `crypto:verify/5`. Wisp selects an opaque authentication mode before processing the header and has no fallback edge from OIDC failure.

## 4. Root Cause Analysis

Comments claimed JWKS verification while the implementation had only payload decoding. The Wisp compatibility branch conflated two independent authentication authorities and made signature validation advisory because static-token equality could override any OIDC error.

## 5. Fix Taxonomy

This is an implementation correction, trust-boundary separation, bounded-input hardening, cryptographic verification addition, and fail-closed configuration change. It does not add OIDC discovery or an in-request key fetcher.

## 6. Patterns & Anti-Patterns Discovered

Authority must be selected from trusted configuration before token evaluation. A fallback between two credential systems is a privilege transition, not ordinary error recovery. Token-provided `jku` or `jwk`, permissive algorithm dispatch, last-wins duplicate JSON, stale keys, and noncanonical encodings are rejected.

## 7. Verification Matrix

| Gate | Observed result |
|---|---|
| Host clock | `NTPSynchronized=yes`; chrony offset 0.000725141 seconds slow; leap status normal |
| Gleam format | Changed Gleam files pass `gleam format --check` after formatting |
| Gleam source check | `gleam check` passes on OTP 29 |
| Focused OIDC EUnit | 24/24 pass via direct `eunit:test(auth_oidc_test, [verbose])` |
| Real signature | RFC 8037 public-key fixture accepts valid Ed25519 JWS |
| Negative security cases | Tamper, wrong key, `none`, duplicate header/claim, `jku`, issuer, audience, expiry, future `nbf`, absent/stale snapshot, oversize, bad JWK, and static downgrade reject |
| Broader suite | 10085 passed, 202 pre-existing/environmental failures; failures include absent project NIFs and unrelated hook/web expectations |

## 8. Files Modified

- [OIDC domain](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/auth/oidc.gleam) — SHA-256 `c83d26628e912765751f2ece759c9826d498079ac143e0cd7ef9ef81d6f85dc6`.
- [Wisp auth policy](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/auth.gleam) — SHA-256 `6b42dd7284e3946f6027a2d19c0968249452c81dfee8c77fe886cf0d60045868`.
- [OTP verifier adapter](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/oidc_jwt_ffi.erl) — SHA-256 `efbac5db17aba6c3af824ac5a1e3382b94634a02cd17f2b49a88c7a78dba2cc1`.
- [Wiring guard](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/testing/wiring_guard.gleam) — SHA-256 `ee223bb13d340dcc949cc93b7742ec856e8696c96e566fd4ce962f92361e0b76`.
- [OIDC tests](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/test/auth_oidc_test.gleam) — SHA-256 `5ee9d002dd9f0e4d935032b2ca86af097ab874bfaab4b691f9307158c664df09`.
- [Scope](http://nas-1.tail55d152.ts.net:4100/docs/design/20260907-1533-bounded-oidc-ed25519-verifier-scope.md).
- This journal.

## 9. Architectural Observations

The acceptance decision is a conjunction whose observations are externally testable and whose efficient interpretation is the bounded production verifier. The Wisp mode ADT removes the previously implicit cross-authority transition. JWKS acquisition remains outside the request interpreter, preserving deterministic behavior and a small audit surface.

## 10. Remaining Gaps

An operator must provision a trusted FerrisKey JWKS snapshot and freshness timestamp, then refresh and restart or rebuild the immutable configuration before expiry. No production snapshot was available or asserted. Full-suite environmental failures prevent a repository-wide green claim; they are outside this candidate and reproducibly distinct from the focused OIDC suite.

## 11. Metrics Summary

Inputs are capped at 8192 token bytes, 32768 JWKS bytes, 16 keys, 128-byte key IDs, 16 audiences, 512-character subjects, 64-byte signatures, 32-byte public keys, 60 seconds clock skew, and 3600 seconds maximum snapshot age. Focused verification executed 24 tests in 0.160 seconds on OTP 29.0.6.

## 12. STAMP & Constitutional Alignment

The change enforces SC-AUTH-001 through SC-AUTH-005 by making every failed observation deny, preserves Gleam ownership of policy, confines cryptographic effects to a bounded OTP adapter, introduces no barred runtime, performs no deployment, and leaves admission to the independent integration gate.

## 13. Conclusion

The candidate provides a real FerrisKey-profile EdDSA/Ed25519 verification path and removes static administrator downgrade when OIDC is enabled. Its claim is limited to the tested bounded profile and the provided operator-controlled snapshot interface.

## Comprehensive verification checklist

### Domain 1 — Metadata, timestamp, and Tailscale navigation

- [x] 1. Timestamp prefix is present and host clock synchronization was observed.
- [x] 2. Canonical Tailscale FQDN journal and file links are present.
- [x] 3. Scope and trigger are recorded.
- [x] 4. Revision lineage is explicit.

### Domain 2 — Zero-Muda purity and storage safety

- [x] 5. No barred Bevy, Graphite, Graphene, or new native dependency was introduced.
- [x] 6. No storage or deployment mutation occurred.
- [x] 7. Fixtures contain public test key material only.
- [x] 8. Verification has no network I/O or token-directed key authority.

### Domain 3 — Testing gold standard and math gates

- [x] 9. Positive signed runtime behavior was observed.
- [x] 10. Required adversarial negatives were observed.
- [x] 11. Acceptance semantics and bounds are recorded.
- [x] 12. Focused results are separated from unrelated full-suite failures.

### Domain 4 — Cross-language control and observability

- [x] 13. Gleam retains typed policy and claims ownership.
- [x] 14. Erlang FFI is bounded to parsing and cryptographic verification.
- [x] 15. Errors remain typed and machine-readable.

### Domain 5 — Tri-sovereign governance and Jujutsu monorepo

- [x] 16. Standalone Jujutsu workspace discipline was maintained.
- [x] 17. No integration, admission, or deployment claim is made.
- [x] 18. Candidate change ID and immutable base are recorded for handoff.
