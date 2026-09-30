# 20260907-1451 — Independent bounded HTTP framing review

#fractal-l0 #fractal-l3 #fractal-l4 #zk-adr #zero-muda #tailscale-web

**UOS / Authentication / Framing review** · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist)

**Document:** [Rendered](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260907-1451-auth-framing-independent-review.md) · [Raw](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260907-1451-auth-framing-independent-review.md). Canonical links are navigation only; this lane did not publish or test serving.

## 1. Scope & Trigger

Task `AUTH-INGRESS` independently reviewed the framing repair and its Expect follow-up. **Candidate `acfe752cc5f1ff4302d605713ea928e051364c2a` is approved for the bounded fixed-length body profile and AG-UI/API fallback adapter.** This is not approval of deployment or every web endpoint.

## 2. Pre-State Assessment

Candidate `6b033f3781e159495b3cb9812b5480f4802a8855` passed adapter checks but failed an actual Mist chunked-body counterexample. Parent `5b1146ea97cc62c1ed9108bd8d254f4d6e4a8e64` introduced strict framing and one fixed-body deadline; the final child adds immediate 417 for unsupported Expect.

## 3. Execution Detail

Used isolated JJ and verification-before-completion. Freshly generated the final web package with Gleam 1.16.0 and compiled changed application/FFI/test modules on OTP 29 / ERTS 17.0.6. Unchanged auth/router modules came from this reviewer's prior frozen-candidate build; JJ confirmed no changes to those sources. Module path inspection verified precedence.

Ran six focused supplied EUnit functions and [42 independent checks](http://nas-1.tail55d152.ts.net:4100/files/tools/verification/oidc/auth_framing_independent_review.erl) in `env -i` VMs. Tests use complete in-memory frames, committed public OIDC fixtures and owned ephemeral loopback sockets. Each test VM has a 30-second outer deadline; no production service was contacted.

## 4. Root Cause Analysis

The prior limit inspected Content-Length while Mist could accumulate unbounded chunked input. The repair rejects transfer encodings and ambiguous framing before reading, checks initial bytes against the declared length, and reads only the remaining bytes under one monotonic deadline. It preserves response headers by changing only the routed response body.

## 5. Fix Taxonomy

This lane adds review tests and evidence only. The product repair provides typed framing/error outcomes, a fixed-length reader, explicit unsupported-protocol responses, and response-record preservation. No product file, live configuration or runtime identity was changed by the reviewer.

## 6. Patterns & Anti-Patterns Discovered

Run negative controls through the connection boundary, not only the materialized-body helper. A handler-call counter proves rejection occurs before dispatch. A successful partial-buffer read with trailing `TAIL` bytes verifies the reader consumes exactly the declared remainder.

## 7. Verification Matrix

| Check at final candidate | Observed result | Scope |
|---|---|---|
| Fresh changed-module generation and compilation | Pass | Web application/FFI; reviewed unchanged auth modules and cached dependencies |
| Supplied focused EUnit | 6/6 pass | Adapter, framing, Expect and five-second timeout |
| Independent controls | 42/42 pass | Actual public connection adapter, actual fixed reader, real HTTP/OIDC chain |
| Exact prior 65,537-byte chunked counterexample | 400, handler not called | Rejection before reader |
| Transfer-Encoding and malformed/ambiguous lengths | 400/413, handler not called | Case, duplicate, comma, sign, empty, nondecimal and oversized inputs |
| Five Expect variants | 417, handler not called | Complete frame not required; dummy socket never read |
| Initial buffer versus declared length | Correct accept/reject | Exact 65,536 accepted; overrun and explicit-zero mismatch rejected |
| No framing | Empty body passed | Initial bytes deliberately discarded |
| Real loopback exact-remainder read | `hello` returned; `TAIL` remains | No read beyond declared length; metadata and repeated response headers retained |
| Real loopback stalled request | 408 after 5,001 ms | Five-second application deadline |
| Partial-progress deadline control | Timeout after 453 ms | Configured 450 ms; partial input does not extend deadline |
| Connection → HTTP → OIDC | Expected 401/404/400 | Static downgrade rejected; public signature accepted; invalid status rejected before persistence; invalid UTF-8 rejected |

The [evidence JSON](http://nas-1.tail55d152.ts.net:4100/files/generated/20260907-1451-auth-framing-independent-review-evidence.json) binds exact source hashes, tools, module paths, named results and invariant-to-code correspondence. Earlier observations of `5b1146ea` remain separately labeled: five supplied tests and 33 independent checks passed, with its Expect compatibility limit subsequently corrected.

The request classifier in [the actual entrypoint](http://nas-1.tail55d152.ts.net:4100/files/apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam) rejects unsupported framing before the reader. [The actual FFI](http://nas-1.tail55d152.ts.net:4100/files/apps/indrajaal_gleam_web/src/indrajaal_web_ffi.erl) checks initial bytes, passes only the remaining count to `recv`, and reuses the same monotonic deadline. These are source/test correspondences, not a formal proof of the complete listener.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] CHK-01-TIME — Host UTC 2026-09-07T14:51:51Z; synchronization reported yes.
- [x] CHK-02-TAIL — Canonical navigation supplied; new-file serving untested.
- [x] CHK-03-FRACT — Fractal and governance tags assigned.
- [ ] CHK-04-KM — Evidence/source cross-links supplied; live transclusion unverified.

</details>
<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [x] CHK-05-MUDA — No excluded source or dependency added.
- [x] CHK-06-GRAPH — Pure Erlang test; no native kernel added.
- [ ] CHK-07-DRIVE — Hardware storage interlock outside scope.

</details>
<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Full UI protocol unrun.
- [ ] CHK-09-MATH — Global metrics and formal implementation proof outside scope.
- [ ] CHK-10-9MOD — Focused 48 checks do not imply nine-modality coverage.
- [ ] CHK-11-REGR — Full UI regression and live monitoring unrun.

</details>
<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — Focused OTP 29 checks pass; live supervision outside scope.
- [ ] CHK-13-HERMES — Evidence-store runtime outside scope.
- [ ] CHK-14-ZIGVM — Kernel outside scope.
- [ ] CHK-15-MAX — Inference outside scope.
- [ ] CHK-16-OTEL — End-to-end collector and tracing unrun.

</details>
<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] CHK-17-SOV — Scoped independent approval; no system admission or deployment authority.
- [x] CHK-18-JJ — Owned isolated artifacts only; no root/main or native Git mutation.

</details>

## 8. Files Modified

Added `tools/verification/oidc/auth_framing_independent_review.erl`, this journal and its evidence JSON. Compiler products remain ignored under `var/auth-framing-review/`.

## 9. Architectural Observations

The profile permits an absent body or exactly one decimal Content-Length up to 65,536. Transfer-Encoding and Expect are deliberately unsupported; fixed-length Mist Stream bodies are rejected. Response adaptation retains the original record. Public signed tests exercise the actual connection-to-authentication chain without granting mutation authority.

## 10. Remaining Gaps

SSL and HTTP/2 were not executed. Specialized direct API-handler authorization, preceding Mist header parsing/prebuffering, total listener memory, concurrent connection limits, per-route RBAC/MFA, live OIDC provisioning and runtime identity remain outside approval. The five-second deadline includes ordinary scheduler tolerance and is not a hard real-time claim. Clients requiring chunked uploads or 100 Continue need a compatible request profile.

## 11. Metrics Summary

Final candidate: six supplied and 42 independent checks passed, zero failures. Main stalled deadline observed 5,001 ms; shortened partial-progress deadline 453 ms. Every owned socket closes in `try/after`; the sender process is monitored and awaited. Live production calls, configuration changes, reloads, integrations and deployments: zero.

## 12. STAMP & Constitutional Alignment

The unsafe action is dispatching a request after losing authentication context or resource bounds. The tested connection boundary preserves context and rejects malformed framing before dispatch. This independent evidence informs the parent; it does not move main or authorize side effects.

## 13. Conclusion

Candidate `acfe752cc5f1ff4302d605713ea928e051364c2a` closes the reviewed body-limit and header-preservation findings within the declared profile. **Scoped approval issued; deployment and broader ingress policy remain separate.**

**Previous:** [Rejected ingress review](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260907-1418-auth-ingress-independent-review.md) · **Next:** [Final framing evidence](http://nas-1.tail55d152.ts.net:4100/files/generated/20260907-1451-auth-framing-independent-review-evidence.json)

**UOS footer:** Independent revision-bound evidence; no deployment authority.
