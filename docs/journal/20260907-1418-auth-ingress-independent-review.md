# 20260907-1418 — Independent HTTP ingress review

#fractal-l0 #fractal-l3 #fractal-l4 #zk-adr #zero-muda #tailscale-web

**UOS / Authentication / Ingress review** · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist)

**Document:** [Rendered](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260907-1418-auth-ingress-independent-review.md) · [Raw](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260907-1418-auth-ingress-independent-review.md). These canonical locations were not published or checked by this isolated lane.

## 1. Scope & Trigger

Independently review `AUTH-INGRESS` candidate `6b033f3781e159495b3cb9812b5480f4802a8855`, parent `9193385706282ea61300e77cbcc6f4664273a57d`. **The candidate is not approved: authentication/method adaptation passes, but the claimed body-ingestion bound fails.**

## 2. Pre-State Assessment

The prior candidate exposed a path-only ingress bypass and GET/HEAD reload effect. This candidate sends AG-UI/API fallback requests through `handle_request`, adds reload to the POST-only registry and introduces `mist.read_body(..., 65536)`.

## 3. Execution Detail

Using isolated JJ and verification-before-completion, freshly generated both application packages with Gleam 1.16.0 and compiled selected actual modules on OTP 29 / ERTS 17.0.6. Supplied tests and [independent controls](http://nas-1.tail55d152.ts.net:4100/files/tools/verification/oidc/auth_ingress_independent_review.erl) ran in separate `env -i` VMs with public test tokens, 30-second deadlines and two-second termination grace. Dependencies came from a local cache; module paths confirmed owned fresh application BEAMs.

## 4. Root Cause Analysis

Pinned Mist 6.0.2 checks advertised Content-Length before reading. Missing or invalid length becomes zero. Its chunked reader then accumulates all chunks without the limit; the application helper checks byte size only afterward. Direct specialized API branches bypass that final helper entirely.

## 5. Fix Taxonomy

Review artifacts only. The repair agent accepted the finding and is preparing pre-read framing validation and bounded reading. A second source limit is duplicate response headers being collapsed by `list.fold(response.set_header)`; replacing only the routed response body preserves the header list.

## 6. Patterns & Anti-Patterns Discovered

A post-materialization body-size check cannot establish bounded ingestion. Tests of `Request(BitArray)` do not exercise `Request(Connection)` reading. The independent probe invokes the actual pinned reader with a complete tiny over-limit frame and a dummy non-socket, avoiding network or resource exhaustion.

## 7. Verification Matrix

| Check | Result | Scope |
|---|---|---|
| Fresh application generation and selected Erlang compilation | Pass | Candidate application code; local cached dependencies |
| Supplied EUnit | 2/2 pass | Materialized-body helper |
| Independent adapter controls | 46/46 pass | Authentication, methods, query/body preservation, response status/headers/body, UTF-8 and materialized-body limits |
| Known mutation routes with rejected credentials | 16/16 return 401 | Actual adapter; stopped before handlers |
| GET/HEAD reload, including query and signed GET | 405; HEAD empty | Prior HTTP reload gap closed |
| Actual Mist chunked reader at limit 65,536 | **Returned Ok with 65,537 bytes** | Concrete ingestion-bound counterexample |
| Content-Length 65,537 control | ExcessBody | Confirms advertised-length check exists |
| Live service / production configuration | Unrun | No deployment or operational approval |

[Evidence JSON](http://nas-1.tail55d152.ts.net:4100/files/generated/20260907-1418-auth-ingress-independent-review-evidence.json) includes named checks, tools, source/dependency hashes and outputs. The independent process exit covers adapter assertions; its separate reader report explicitly records the defect.

`INGRESS-BODY-001` (high): [main wrapper](http://nas-1.tail55d152.ts.net:4100/files/apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam) line 950 delegates to Mist without a cumulative bound. Mist source lines 220–235 check Content-Length; `mist/internal/http.gleam` lines 186–240 and 403–413 accumulate chunked input. Reject unsupported/ambiguous framing before reading or use a genuinely bounded reader with total deadline; validate the materialized bound before every branch.

`INGRESS-HEADERS-002` (low, source limit): the same application file line 1002 reconstructs headers with `set_header`, collapsing repeated names. Tested routes emitted unique headers, so no current credential consequence is claimed. Use `response.set_body` or `response.map` on the routed response.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] CHK-01-TIME — Host UTC 2026-09-07T14:36:18Z; NTP synchronization observed yes at 14:29:47.
- [x] CHK-02-TAIL — Canonical navigation supplied; serving untested.
- [x] CHK-03-FRACT — Fractal and governance tags assigned.
- [ ] CHK-04-KM — Evidence/source links supplied; transclusion runtime unverified.

</details>
<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [x] CHK-05-MUDA — No excluded source or dependency added.
- [x] CHK-06-GRAPH — Pure Erlang review fixture; no native kernel added.
- [ ] CHK-07-DRIVE — Hardware storage interlock outside scope.

</details>
<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Full UI protocol unrun.
- [ ] CHK-09-MATH — Global metrics unmeasured; no formal implementation proof claimed.
- [ ] CHK-10-9MOD — Focused tests are not nine-modality coverage.
- [ ] CHK-11-REGR — Live monitoring and full UI regression unrun.

</details>
<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — Focused OTP 29 tests passed; live supervision outside scope.
- [ ] CHK-13-HERMES — Evidence-store execution outside scope.
- [ ] CHK-14-ZIGVM — Kernel outside scope.
- [ ] CHK-15-MAX — Inference outside scope.
- [ ] CHK-16-OTEL — End-to-end tracing unrun.

</details>
<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] CHK-17-SOV — Candidate rejected pending repair; no system admission.
- [x] CHK-18-JJ — Isolated JJ workspace and owned artifacts only; no main or native Git mutation.

</details>

## 8. Files Modified

Added the independent Erlang fixture, this journal and its evidence JSON. Compiler products stay ignored under `var/auth-ingress-review/`; no product files changed.

## 9. Architectural Observations

The adapter now preserves request method, path, query, headers and body through `request.set_body`. Its authorization result covers AG-UI and API fallback. Specialized API branches remain direct handlers and require their own policy review; this is not approval of every web endpoint.

## 10. Remaining Gaps

Body framing, cumulative bytes and total read deadline require a replacement candidate. Duplicate response-header preservation should be corrected. OIDC operator enablement/JWKS refresh, endpoint authorization, actual listener identity and deployment remain outside this lane.

## 11. Metrics Summary

Two supplied tests and 46 independent adapter assertions passed; one concrete reader counterexample remains. One initial fixture incorrectly expected unknown-route JSON to echo its query; it was corrected using the actual router contract, then replaced by query-dependent dispatch and redirect-location controls. Production edits, live requests and integrations: zero.

## 12. STAMP & Constitutional Alignment

The unsafe action is accepting a request whose authenticated context or resource bound was lost at adaptation. Authentication context is now carried; the resource bound still depends on an unchecked reader assumption. Independent results advise the parent and do not authorize deployment.

## 13. Conclusion

Candidate `6b033f3781e159495b3cb9812b5480f4802a8855` closes the tested authentication and reload-method gaps but fails the ingestion-bound review. A repaired candidate requires fresh independent verification.

**Previous:** [OIDC verifier review](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260907-1450-oidc-independent-review.md) · **Next:** [Ingress evidence](http://nas-1.tail55d152.ts.net:4100/files/generated/20260907-1418-auth-ingress-independent-review-evidence.json)

**UOS footer:** Independent revision-bound evidence; no deployment authority.
