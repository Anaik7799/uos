# 20260907-1450 — Independent bounded OIDC verifier review

#fractal-l0 #fractal-l3 #fractal-l4 #zk-adr #zero-muda #tailscale-web

**UOS / Authentication / Independent review** · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist)

**Document:** [Rendered](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260907-1450-oidc-independent-review.md) · [Raw](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260907-1450-oidc-independent-review.md). These are canonical navigation locations; this isolated lane did not publish or check serving.

## 1. Scope & Trigger

Task `AUTH-VERIFY` in `uos/mirage-security/20260907-1310` requested independent review of candidate `9193385706282ea61300e77cbcc6f4664273a57d` (`kozsqvqtssvpvupqpnstxuxrkvlwuoyl`). **The bounded Ed25519 JWT verifier and selected OIDC authentication wrapper are approved within this review scope. The web ingress is not approved.**

## 2. Pre-State Assessment

The candidate replaces unconditional verification failure with a bounded public-JWKS verifier and removes OIDC-to-static-admin fallback. Its supplied report claimed 24 passing tests. The review starts from exactly that immutable candidate in `.uos-workspaces/codex-oidc-auth-review`; no production configuration or secrets were read.

## 3. Execution Detail

Applied verification-before-completion and freshly generated Erlang from the candidate Gleam package with Gleam 1.16.0, then compiled the selected verifier, wrapper, RBAC, FFI, router and test modules with OTP 29 / ERTS 17.0.6. Module path inspection confirmed the reviewed modules loaded from this workspace's `var/oidc-review/ebin`; dependencies came from an existing local cache. Low-level compilation avoided package fetching; compiler and test VMs had outer deadlines and `ERL_FLAGS='+S 4:4 +A 4'`.

Ran the actual supplied EUnit module and [59 independent acceptance controls](http://nas-1.tail55d152.ts.net:4100/files/tools/verification/oidc/oidc_independent_review.erl). The independent fixture uses an in-memory ephemeral Ed25519 key pair and synthetic claims. An `env -i` VM contains all test configuration. Known POST paths were called with rejected credentials only after the wrapper and a harmless unknown-route check confirmed rejection. No GET reload, live request, listener, service restart or deployment was executed.

## 4. Root Cause Analysis

The bounded verifier now checks signature, exact issuer, audience membership and shape, nonempty subject, expiry, optional issue/not-before times and fresh snapshot as a conjunction. OIDC mode selects this boundary before token evaluation, so signature or configuration failure cannot become static admin. The remaining ingress gaps arise because the web adapter invokes a path-only router and that path router still contains a reload effect.

## 5. Fix Taxonomy

This lane adds only an independent test, evidence JSON and journal. No product code was edited. Recommended ingress follow-up: preserve method, headers, body and response status through the authenticated request router; restrict reload effects to authenticated POST and return metadata or 405 for GET/HEAD.

## 6. Patterns & Anti-Patterns Discovered

Positive real-signature controls and a deliberately equal static token distinguish correct rejection from a verifier that always rejects or silently falls back. Testing `handle_request` proves that boundary only; it does not prove that a live adapter calls it.

## 7. Verification Matrix

| Check | Observed result | Boundary |
|---|---|---|
| Supplied `auth_oidc_test` EUnit | 24/24 pass, exit 0 | Fresh candidate modules on OTP 29 |
| Independent synthetic controls | 59/59 pass, exit 0 | Actual verifier, wrapper and request router |
| Signature/profile/parser controls | Pass | Wrong key/tamper, canonical base64url, duplicate and trailing JSON, header/key allowlists, bounded JWT/JWKS |
| Issuer/audience/subject/time controls | Pass | Exact issuer; valid audience shape/membership; subject limit; expiry and 60-second skew boundaries |
| Snapshot controls | Pass | Missing, future, stale, age boundaries and malformed snapshots |
| Static-admin downgrade controls | Pass | Tampered token equal to static credential rejected in OIDC mode; absent/stale snapshot also rejected |
| Intended POST rejection boundary | 16/16 return 401 | Invalid credential returns before mutation handler |
| Unknown route and method controls | Expected 404/401/405 | Harmless request-router calls |
| Actual web adapter | Source gap | No live traffic executed |
| Full suite, live IdP, RBAC policy, deployment | Unrun / outside scope | No system-wide admission claim |

[Evidence JSON](http://nas-1.tail55d152.ts.net:4100/files/generated/20260907-1450-oidc-independent-review-evidence.json) includes exact source digests, named controls, supplied EUnit output, tools and reproduction instructions. Network and secret-access flags describe the harness design, not a packet-capture measurement. The attempted network namespace was unavailable; the tests themselves contain no external requests.

| Source finding | Evidence at frozen candidate | Consequence and required follow-up |
|---|---|---|
| AUTH-INGRESS-001, high, pre-existing | `indrajaal_gleam_web.gleam:79` and `:493` call `c3i_router.route(path)` for AG-UI and API fallback. Adapter builds status 200. | Method, authorization headers and body never reach `handle_request` / `handle_post`. Adapt the actual request and preserve the response. Do not infer all POST handlers are reachable: the path router has a different dispatch table. |
| AUTH-INGRESS-002, high, pre-existing | `router.gleam:141` routes reload to `hot_reload_json`; `:1642` calls `hot_reload.reload_changed()`; `:3716` POST-only registry omits reload. | GET/HEAD through the request router, or any method through the path-only adapter, can reach reload when the health guard permits. Remove that effect from the read path and enforce authenticated POST. No runtime reload reproduction was performed. |

Both source files have identical SHA-256 at the candidate and its immediate parent. These findings block an ingress approval, not the narrow cryptographic-verifier result. Source links: [request router](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/router.gleam), [web entrypoint](http://nas-1.tail55d152.ts.net:4100/files/apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam).

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] CHK-01-TIME — Host UTC `2026-09-07T14:08:50Z`; synchronization observation at 14:05:39 reported `NTPSynchronized=yes`.
- [x] CHK-02-TAIL — Canonical FQDN navigation provided; new-file serving untested.
- [x] CHK-03-FRACT — Fractal and governance tags assigned.
- [ ] CHK-04-KM — Journal/evidence/source links provided; live bidirectional transclusions unverified.

</details>
<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [x] CHK-05-MUDA — This lane introduces no excluded dependency or runtime role.
- [x] CHK-06-GRAPH — Pure Erlang test; no graph or other native kernel added.
- [ ] CHK-07-DRIVE — Hardware storage interlock outside scope.

</details>
<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Full UI protocol unrun.
- [ ] CHK-09-MATH — Global four-metric gates unmeasured; no formal proof of JWT implementation claimed.
- [ ] CHK-10-9MOD — Focused 83 checks do not establish nine-modality coverage.
- [ ] CHK-11-REGR — Full UI regression and live monitoring unrun.

</details>
<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — OTP 29 focused execution passed; live supervision and ingress security remain separate.
- [ ] CHK-13-HERMES — Hermes evidence-store execution outside scope.
- [ ] CHK-14-ZIGVM — Deterministic kernel outside scope.
- [ ] CHK-15-MAX — Inference outside scope.
- [ ] CHK-16-OTEL — End-to-end collector and trace propagation unrun.

</details>
<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] CHK-17-SOV — Independent bounded approval only; no tri-agent admission or deployment authority.
- [x] CHK-18-JJ — Isolated JJ workspace, only owned artifacts; no native Git or main mutation. Global doctor unrun.

</details>

## 8. Files Modified

Added `tools/verification/oidc/oidc_independent_review.erl`, `generated/20260907-1450-oidc-independent-review-evidence.json` and this journal. Compiler products and raw local result remain ignored under `var/oidc-review/`; durable results are embedded in the evidence JSON.

## 9. Architectural Observations

The candidate retains a narrow local EdDSA/Ed25519 profile with no request-time discovery or network refresh. OIDC authentication and role projection are separate from endpoint authorization; the candidate does not add a complete RBAC/MFA route policy. The actual web adapter must preserve the authenticated boundary for that policy to matter.

## 10. Remaining Gaps

Operators must explicitly select OIDC with `FERRISKEY_ENABLED=true` or `1`, provide intended issuer/audience/client values and a trustworthy public JWKS snapshot, and refresh its timestamp externally. Other enable values select legacy static mode, whose existing missing-token fallback remains `c3i-dev-token`. Snapshot age defaults to 300 seconds and is capped at 3600. No live configuration was checked. The two ingress defects require separate repair and verification.

## 11. Metrics Summary

24 supplied and 59 independent checks passed; zero failed. Sixteen known POST mutation paths rejected before their handlers. Production edits, imports, live calls, restarts, integrations and deployments by this lane: zero. Existing compiler deprecation warning did not prevent compilation.

## 12. STAMP & Constitutional Alignment

The unsafe control action is granting mutation authority without carrying authenticated request context. The verifier constrains token admission; the web adapter and route dispatch must preserve that constraint. The parent owns task status, peer coordination, integration and operational cutover.

## 13. Conclusion

Candidate `9193385706282ea61300e77cbcc6f4664273a57d` passes this bounded JWT-verifier and OIDC-wrapper review. **This is not approval of live ingress or system admission:** the pre-existing adapter bypass and GET/HEAD reload effect remain open.

**Previous:** [Candidate scope](http://nas-1.tail55d152.ts.net:4100/docs/design/20260907-1533-bounded-oidc-ed25519-verifier-scope.md) · **Next:** [Review evidence](http://nas-1.tail55d152.ts.net:4100/files/generated/20260907-1450-oidc-independent-review-evidence.json)

**UOS footer:** Independent revision-bound review; no deployment authority.
