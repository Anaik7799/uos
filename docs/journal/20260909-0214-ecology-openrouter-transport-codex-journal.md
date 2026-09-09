# 20260909-0214 — Codex bounded OpenRouter transport journal

#fractal-l2 #fractal-l4 #fractal-l5 #fractal-l8 #zk-adr #zero-muda

Created: 2026-09-09T02:29:14Z. [Source-bound receipt](http://nas-1.tail55d152.ts.net:4100/files/governance/sources/20260909-0214-ecology-openrouter-transport-receipt.json) · [UOS](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

## 1. Scope & Trigger

Root delegated TRANSPORT in Sa-plan uos/ecology-transport/20260909-0211 after review found unbounded fully buffered HTTP responses. Worker codex-ecology-capabilities, attempt1, owned the Erlang transport and isolated EUnit tests.

## 2. Pre-State Assessment

The httpc path had per-call timeouts but buffered complete responses for all statuses. It accepted arbitrary URL arguments and did not impose response-byte limits. Model reply validation remained a distinct root-owned concern.

## 3. Execution Detail

Replaced buffered calls with passive verified TLS, an exact two-endpoint allowlist, bounded incremental HTTP parsing and one absolute request deadline. Added a watchdog monitoring both caller and socket owner so cancellation closes outstanding transport. Content-Length, chunked and connection-close responses are supported without redirects.

## 4. Root Cause Analysis

A request timeout was treated as complete resource bounding even though received bytes were unbounded. Monitoring a child also did not propagate caller cancellation. The new counter checks each received fragment before concatenation; the watchdog survives a blocked read and reacts to caller death.

## 5. Fix Taxonomy

Transport replacement, resource-bound enforcement, credential-boundary validation, cancellation supervision and malformed/fractured wire regressions. No packages or credentials were provisioned.

## 6. Patterns & Anti-Patterns Discovered

HTTP status errors need the same byte limits as successful responses. Duplicate framing headers and mixed length/transfer encoding fail closed. A TLS-peer identity check is preserved independently of endpoint allowlisting. Error strings exclude keys and request terms.

## 7. Verification Matrix

| Check | Result | Scope |
|---|---|---|
| Production erlc +warnings_as_errors | PASS | OTP29 compiler |
| Dedicated EUnit |16 PASS /0 FAIL|85 fixed-status/fragment cases and31 chunk-fragment cases included|
| Timeout and caller cancellation |PASS|Continuous output, ignored recv timeout and killed caller|
| Live final-source TLS GET |HTTP200,709193 bytes|Public models endpoint, no credential;0.227 seconds|
| Risk active check |PASS at02:27:35Z|Two source hashes, worker/attempt1; no admission|

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME: host UTC recorded.
- [x] CHK-02-TAIL: full Tailscale artifact links supplied; rendering not rechecked.
- [x] CHK-03-FRACT: L2/L4/L5/L8 scope tagged.
- [ ] CHK-04-KM: grouped wiki/ZK/KM integration remains root-owned.

</details>
<details><summary>Domain 2 — Purity and storage</summary>

- [x] CHK-05-MUDA: existing OTP/SSL only, no new packages.
- [x] CHK-06-GRAPH: no graph/NIF/runtime dependency introduced.
- [x] CHK-07-DRIVE: no physical storage mutation; N/A.

</details>
<details><summary>Domain 3 — Tests and mathematics</summary>

- [ ] CHK-08-C1C8: UI categories outside scope.
- [ ] CHK-09-MATH: no new formal completeness proof claimed.
- [x] CHK-10-9MOD: relevant boundary, failure and real-network modes executed; full nine modalities not claimed.
- [x] CHK-11-REGR:16 dedicated regressions passed.

</details>
<details><summary>Domain 4 — Control and observability</summary>

- [x] CHK-12-GLEAM: narrow existing Erlang FFI; supervision deadline/cancellation tested.
- [ ] CHK-13-HERMES: unchanged, N/A.
- [ ] CHK-14-ZIGVM: unchanged, N/A.
- [ ] CHK-15-MAX: unchanged by transport task.
- [ ] CHK-16-OTEL: deployment tracing remains root-owned.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV: system admission NOT_GRANTED.
- [x] CHK-18-JJ: no VCS mutation; canonical task/attempt used.

</details>

## 8. Files Modified

- [apps/uos_swarm/src/uos_openrouter_ffi.erl](http://nas-1.tail55d152.ts.net:4100/files/apps/uos_swarm/src/uos_openrouter_ffi.erl)
- [tools/validation/ecology_openrouter_transport_test.erl](http://nas-1.tail55d152.ts.net:4100/files/tools/validation/ecology_openrouter_transport_test.erl)

The receipt and this journal record the scoped handoff. Test exports are compiled only with -DTEST; production keeps the existing four API functions.

## 9. Architectural Observations

The socket owner and its watchdog form a bounded transport lifetime under the calling supervised actor. Scope is HTTP plaintext received, including headers and framing; this is not an encrypted-wire-byte or total OTP-heap bound. TLS verification uses the system CA bundle and HTTPS hostname matching for openrouter.ai.

## 10. Remaining Gaps

Root owns actual credential-bearing completion verification, free-model reply semantics, release rebuilding and deployment. Compression, interim responses, chunk extensions and trailers deliberately return errors. General process containment and full-system formal refinement remain separate.

## 11. Metrics Summary

Two implementation/test paths;16 tests passed;116 fragmentation/status combinations;16KiB header and4MiB total HTTP plaintext ceilings;30-second maximum configured request duration;64KiB request-body ceiling;zero credential requests, downloaded packages or VCS mutations.

## 12. STAMP & Constitutional Alignment

P1 score768 (C4×T4×F4×Dep4×I3), FMEA S4/O3/Det3/RPN36. Required bound omission, unsafe response acceptance, deadline ordering and worker duration/cancellation were considered. Root retains effect authority. The first network attempt failed within the sandbox; the approved rerun succeeded. No EV number or admission was minted.

## 13. Conclusion

The bounded transport is compiled, tested and observed against the public TLS endpoint at the recorded source bytes. It is ready for root integration; this task does not assert whole-system runtime or admission.

**UOS footer:** http://nas-1.tail55d152.ts.net:4100/ · canonical execution authority remains Sa-plan.
