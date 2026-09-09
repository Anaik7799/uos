# 20260909-0209 — Codex OpenRouter routing and reasoning diagnostic

#fractal-l2 #fractal-l4 #fractal-l5 #fractal-l8 #zk-adr #zero-muda

Created: 2026-09-09T02:39:09Z. [Receipt](http://nas-1.tail55d152.ts.net:4100/files/governance/sources/20260909-0209-ecology-openrouter-diagnostic-receipt.json) · [UOS](http://nas-1.tail55d152.ts.net:4100/) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

## 1. Scope & Trigger

User steering required OpenRouter to work under fractal TPS and Jidoka. Root delegated read-only official documentation, public endpoint metadata and local routing review under Sa-plan uos/ecology-openrouter-diagnostic/20260909-0247, task DIAGNOSTIC, worker codex-ecology-capabilities, attempt 1.

## 2. Pre-State Assessment

Earlier endpoint errors suggested privacy or price filtering. The local free request already carried zero prompt, completion and request price caps, a 512-token ceiling and strict final-content/cost validation. No reasoning control was included in the observed source.

## 3. Execution Detail

Read official routing, privacy and reasoning documentation; fetched public models and ZDR endpoints without credentials; joined eligible text-model records; sent exact candidate settings to root. No source, account, privacy, guardrail or VCS change was performed by this worker.

## 4. Root Cause Analysis

Root reported a later HTTP 200 through the same zero caps, selecting Ling Flash Fin free via Novita with cost zero. That falsifies a blanket max_price.request=0 routing block. The returned final content was null with a length finish, so the current failure is separately classified as answer-budget exhaustion. This peer observation is not an independent authenticated test by this worker.

## 5. Fix Taxonomy

Diagnostic correction and proposed request configuration. Preserve all zero-price controls. For optional-reasoning models, try reasoning.enabled=false with reasoning.exclude=true, then require a nonempty final answer and explicit cost zero through the strict adapter before release. No implementation completion is claimed here.

## 6. Patterns & Anti-Patterns Discovered

Hiding reasoning does not stop its token consumption. Dynamic router metadata cannot determine a selected model's default reasoning mode. A public catalog can establish candidates but cannot establish effective API-key policy or capacity. Official sources: [reasoning controls](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens), [provider price caps](https://openrouter.ai/docs/guides/routing/provider-selection), [ZDR enforcement](https://openrouter.ai/docs/guides/features/zdr).

## 7. Verification Matrix

| Check | Observed result | Limit |
|---|---|---|
| Public default model catalog | 431 records | Observation window bound in receipt |
| Public ZDR endpoint catalog | 841 records | Does not expose effective key policy |
| Free text-model/ZDR intersection | 2 Novita endpoints | Ling Flash Fin and Flash Sante free |
| Reasoning metadata | Optional, enabled by default for both | Disabled-reasoning completion untested by this worker |
| Risk active check | PASS at 02:39:09Z | Two exact source hashes; no effect authority |
| Root HTTP 200 counterexample | Peer reported cost 0, null content | Not usable advisory success |

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME: synchronized host UTC recorded.
- [x] CHK-02-TAIL: full Tailscale artifact links provided.
- [x] CHK-03-FRACT: L2/L4/L5/L8 scope tagged.
- [ ] CHK-04-KM: grouped wiki/ZK integration remains root-owned.

</details>
<details><summary>Domain 2 — Purity and storage</summary>

- [x] CHK-05-MUDA: no package or runtime dependency added.
- [x] CHK-06-GRAPH: no graph dependency or NIF introduced.
- [x] CHK-07-DRIVE: no physical storage mutation; N/A.

</details>
<details><summary>Domain 3 — Tests and mathematics</summary>

- [ ] CHK-08-C1C8: implementation and UI checks outside this read-only task.
- [ ] CHK-09-MATH: no new formal proof claimed.
- [x] CHK-10-9MOD: relevant public observations and peer counterexample preserved; full modalities not claimed.
- [ ] CHK-11-REGR: source unchanged; authenticated regression remains root-owned.

</details>
<details><summary>Domain 4 — Control and observability</summary>

- [x] CHK-12-GLEAM: existing strict policy boundary inspected; changes not made.
- [ ] CHK-13-HERMES: unchanged; N/A.
- [ ] CHK-14-ZIGVM: unchanged; N/A.
- [ ] CHK-15-MAX: unchanged; N/A.
- [ ] CHK-16-OTEL: no deployment observation by this worker.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV: system admission NOT_GRANTED.
- [x] CHK-18-JJ: exact Sa-plan task/attempt; no VCS mutation.

</details>

## 8. Files Modified

Only this journal and its linked diagnostic receipt were created. Runtime source remains unchanged by this task. Public temporary snapshots are identified by URL, local path and SHA-256 in the receipt.

## 9. Architectural Observations

Jidoka distinguishes routing-policy unavailability, incomplete final output, and a validated advisory. None grants effect authority. Price caps and account/guardrail restrictions remain enforced while root tests a request-level change that disables optional reasoning.

## 10. Remaining Gaps

Root owns authenticated verification and any reviewed allowlist/request change. The two direct Ling variants were absent from the observed local allowlist; openrouter/free was present. Public endpoint eligibility can change. Current catalog-listed free Gemma, Nemotron Lightning and Inkling endpoints were absent from the observed ZDR list, so they are not proposed as alternatives under required ZDR.

## 11. Metrics Summary

Two public API reads; zero credential requests; two exact source hashes; two eligible text-advisory endpoints; zero source changes, paid calls, account-setting changes or new EV identifiers. The wider ZDR catalog includes audio/image/reranking entries with zero token prices; those do not expand the text-advisory candidate count.

## 12. STAMP & Constitutional Alignment

The source-bound P1 assessment used score 768 and FMEA S4/O3/Det3/RPN36. Missing diagnostics, unsafe relaxation of zero-price/privacy controls, stale endpoint selection and excessive retries are the four relevant UCA contexts. Root retains release authority; this worker keeps failed or empty replies outside usable advisory success.

## 13. Conclusion

Public evidence identifies a zero-cost, privacy-preserving candidate configuration: disable optional reasoning on a currently eligible Ling free route, preserve zero price caps, and verify final output within 512 tokens. The diagnostic is complete; runtime recovery must be established by root's strict authenticated test.

**UOS footer:** http://nas-1.tail55d152.ts.net:4100/ · canonical execution authority remains Sa-plan.
