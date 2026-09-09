# 20260909-0308 — Codex OpenRouter profile and dispatch cycle

#fractal-l0 #fractal-l2 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l8 #zk-adr #zero-muda

Observed host UTC: 2026-09-09T03:26:08Z. [UOS](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Source and test receipt](http://nas-1.tail55d152.ts.net:4100/files/governance/sources/20260909-0308-ecology-model-profiles-receipt.json) · [Design review](http://nas-1.tail55d152.ts.net:4100/docs/design/20260909-0314-openrouter-engine-review-and-recommendation.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

## 1. Scope & Trigger

The user authorized paid GLM, Kimi and DeepSeek coding candidates, Gemma4 decision support and a $10/day aggregate budget, then asked for a grounded code/document review. Root delegated profile metadata and shared-worker policy under `uos/ecology-model-profiles/20260909-0358`, task `PROFILES`, worker `codex-ecology-capabilities`, attempt1. Root owns paid reservations, authenticated probes, deployment and the proposed adaptive engine. This cycle made no paid call.

## 2. Pre-State Assessment

The default free Fin route had separate root-owned live evidence. The worker allowed only512 completion tokens regardless of paid intent. Its routed entry point discarded the chosen tier and posted the original request model. The routing policy declared a free-only remote flag without checking it. Legacy catalog, immutable Budget values and heuristic quality scores did not establish measured routing quality or durable spend control.

## 3. Execution Detail

Verified public model metadata and primary cards, compared canonical routing code with read-only VM-1 C3I/Indrajaal selectors, and added six typed profiles. Explicit paid profiles allow4096 tokens,0.25USD and30 seconds; the free default remains512 tokens,0.02USD and30 seconds. Provider requests retain ZDR and zero request-fee caps, with separately recorded input/output price ceilings. GLM5.3 uses mandatory low-effort reasoning; optional reasoning is disabled for the other curated profiles and excluded from returned content.

Bound selection to the actual OpenRouter POST, refused non-OpenRouter selections, and derived this worker's remote candidate list from its shared exact allowlist and current prices. Added the missing free-only policy veto,8192 UTF-8 bytes per message alongside the existing2000-grapheme hygiene check, and strict paid receipt checks. Paid replies require reported cost, the admitted model, bounded completion tokens and cost within the requested/hard budget. Durably embedded the focused test output and isolated negative-control output in the linked JSON receipt.

## 4. Root Cause Analysis

The selection layer and effect boundary were disconnected: a route result was treated as permission for the caller's original model. Parallel policy representations also drifted: a route flag was unused, a static model list differed from the worker allowlist, and a Budget record was described as atomic without performing a reservation. Grapheme count was incorrectly treated as a payload bound. Falling back to a catalog estimate could label unreported paid spend as measured cost.

## 5. Fix Taxonomy

Dispatch binding, policy consistency, bounded input validation and receipt integrity. The UTF-8 regression uses one grapheme containing4096 combining marks and proves rejection before POST. Pure routing and immutable profile metadata remain separate from the caller's durable budget and task authority. No automatic paid fallback, private-source export or artifact execution was added.

## 6. Patterns & Anti-Patterns Discovered

Keep catalog quotes, accepted endpoint caps, estimates, reservations and reported spend as distinct data. The public models response observed03:05:38Z contains431 entries,709193 bytes, SHA256 `aaab06c453b67c00ef806800013b311680971b39ad16b37f298853a372c7e32b`. The ZDR response observed03:08:14Z contains841 records,745720 bytes, SHA256 `1567a7ed4bbdc8319df1229ef90a9c8a1171107c52a5dc37c18959895492062b`. Both URLs and the selected normalized records are durably bound in the receipt. API quotes are not guaranteed current minima across providers; HTML cards and discounts can differ. [Public model catalog](https://openrouter.ai/api/v1/models), [public ZDR endpoints](https://openrouter.ai/api/v1/endpoints/zdr).

| Profile | Exact model | Observed API quote USD/M input/output | Accepted cap USD/M input/output |
|---|---|---:|---:|
| Free advisory | `inclusionai/ling-3.0-flash-fin:free` | 0 / 0 | 0 / 0 |
| Coding GLM | `z-ai/glm-5.3` | 1.40 / 4.40 | 1.40 / 4.40 |
| Coding Kimi | `moonshotai/kimi-k3` | 3.00 / 15.00 | 3.00 / 15.00 |
| Coding DeepSeek | `deepseek/deepseek-v4-pro-0813` | 0.57948 / 1.73844 | 1.32 / 3.96 |
| Efficient coding | `deepseek/deepseek-v4-flash-0731` | 0.065 / 0.18 | 0.065 / 0.18 |
| Decision Gemma | `google/gemma-4-31b-it` | 0.09 / 0.34 | 0.09 / 0.34 |

No public ZDR record met DeepSeek Pro's API quote under the bounded query. The explicitly accepted higher cap admits13 records,12 distinct provider tags. Corresponding paid counts are18 GLM,14 Kimi,4 Flash and1 Gemma record. These are public eligibility observations, not authenticated availability. Provider `max_price` uses USD per million tokens, while local admission prices use USD per token. [Provider-selection semantics](https://openrouter.ai/docs/guides/routing/provider-selection).

Primary cards support evaluating GLM5.3, KimiK3 and DeepSeek Pro for coding work; they do not identify the best model on UOS tests. Dense Gemma31B is the initial decision-support candidate, with26B MoE as an efficiency comparison. Endpoint-specific tools/schema support needs its own filter before any future tool-enabled work. [GLM card](https://huggingface.co/zai-org/GLM-5.3), [Kimi card](https://huggingface.co/moonshotai/Kimi-K3), [DeepSeek card](https://huggingface.co/deepseek-ai/DeepSeek-V4-Pro-0813), [Gemma4 model card](https://ai.google.dev/gemma/docs/core/model_card_4).

## 7. Verification Matrix

| Check | Observed result | Scope |
|---|---|---|
| Pinned Gleam1.16 build | PASS,0.41 seconds final build | Shared source, existing realized dependencies |
| OpenRouter worker tests |35/35 PASS | Mock HTTP, real pure policy and JSON checks |
| Router tests |20/20 PASS | Authority, adequacy, cost and free-only gate |
| Restored old dispatch defect | Expected regression failure | Isolated generated Erlang in `/tmp`; canonical files unchanged |
| Actual runtime toolchain | OTP29,ERTS17.0.5,4 schedulers,4 async threads | Observed local VM settings |
| Paid network/model benchmark | Not run by this worker | Root owns reservation and live probes |
| Full adaptive-engine proof/release | Not claimed | Requires integration and independent evidence |

The first build caught two test syntax/type mistakes; a later formatter caught incorrect Boolean grouping. Both failures were corrected before their passing checks and are retained in the receipt. The negative control failed at the assertion comparing original Gemma versus selected Fin, confirming that the regression detects the reviewed defect.

<details><summary>Domain1 — Metadata and navigation</summary>

- [x] CHK-01-TIME: synchronized host clock used by canonical preflight and active checks.
- [x] CHK-02-TAIL: operational links and VM-1 target use Tailscale FQDNs.
- [x] CHK-03-FRACT: control, implementation, review and evidence layers tagged.
- [ ] CHK-04-KM: root owns grouped wiki/ZK/KM propagation and publication.

</details>
<details><summary>Domain2 — Purity and storage</summary>

- [x] CHK-05-MUDA: no packages, weights or prohibited engines introduced.
- [x] CHK-06-GRAPH: pure Gleam policy; no graph/NIF dependency change.
- [x] CHK-07-DRIVE: no device, external-tree or baseline runtime mutation.

</details>
<details><summary>Domain3 — Tests and mathematics</summary>

- [ ] CHK-08-C1C8: full system test modalities are outside this slice.
- [ ] CHK-09-MATH: no new adaptive-engine theorem claimed.
- [x] CHK-10-9MOD: focused positive, refusal and restored-defect observations retained.
- [x] CHK-11-REGR:55 focused tests passed at the recorded source hashes.

</details>
<details><summary>Domain4 — Control and observability</summary>

- [x] CHK-12-GLEAM: OTP29 policy/JSON execution observed.
- [ ] CHK-13-HERMES: parent-owned durable spend integration is separate.
- [ ] CHK-14-ZIGVM: external current source remains unbound to live executable.
- [ ] CHK-15-MAX: no MAX changes in this cycle; earlier root evidence is separate.
- [ ] CHK-16-OTEL: no whole-engine tracing or learning completeness claim.

</details>
<details><summary>Domain5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV: runtime/system admission NOT_GRANTED; EV ceiling93 unchanged.
- [x] CHK-18-JJ: exact Sa-plan attempt observed; no VCS mutation by this worker.

</details>

## 8. Files Modified

`apps/uos_swarm/src/uos_swarm/openrouter_worker.gleam`, `apps/uos_swarm/src/uos_swarm/route.gleam`, their two focused test modules, this journal and the linked receipt. Exact source SHA256 values are in the receipt. Temporary metadata, risk assessments and isolated negative-control modules remain outside the canonical source tree. No baseline release package, credentials FFI or external ecology adapter was edited.

## 9. Architectural Observations

Reuse canonical `route.gleam` operation classes, authority checks, minimum trials and per-model/class Beta evidence. Its nonempty evidence references still need authenticated, deduplicated receipts before autonomous learning. The separate `cepaf_gleam/ai/intelligence_router.gleam` is a catalog projection; its daily budget fields and fallback choices are not execution enforcement.

Current read-only C3I `cortex/model_selector.ex` separates complexity, latency and quality constraints but uses static tier scores; free/smart candidates share one selected model and premium is empty. `cortex/synapse/model_selector.ex` uses fixed0.40/0.35/0.25 cost/latency/quality weights and old free model IDs. Reuse those boundaries as a design pattern, not the moving roster or heuristic scores as measured intelligence. Exact external locators are in the receipt; no external code was admitted into UOS.

## 10. Remaining Gaps

Paid engine integration must bind current Sa-plan authority, a fresh durable reservation, exact chosen model and independently verified result. The legacy JSONL budget APIs are not adequate aggregate paid authority. This worker neither implemented nor enabled continuous learning, arbitrary coding effects, account policy changes or a whole-system supervisor. Public endpoint compatibility can change. Account guardrails, usable answers and provider-reported spend require live verification within the root-owned budget.

## 11. Metrics Summary

Six profiles, five newly allowlisted paid IDs, four code/test files,55 passing focused tests and one expected failing negative control. Public metadata contains431 models and841 ZDR records. Zero paid calls, credential-bearing requests, external writes, packages, model-weight downloads or VCS mutations by this worker. Per-field UTF-8 limits bound total message text to16384 bytes. Parent's conservative Kimi-priced reservation calculation is0.116736USD before the0.25USD reserved liability; this arithmetic does not itself reserve funds or prove tokenizer behavior.

## 12. STAMP & Constitutional Alignment

Sa-plan preflight passed before claim at03:04:56Z; active observations passed at03:05:25Z,03:16:32Z and03:21:48Z as the authorized scope expanded. Source-bound handoff evidence is in the receipt. FMEA S4/O3/Det3 yields RPN36, band4. STPA distinguishes omitted repairs, unsafe selected-model dispatch, stale source/price evidence and work continuing beyond lease/budget. Parent and hooks supplied bounded reviews; no peer message or passing count grants deployment or admission authority.

## 13. Conclusion

The shared worker now exposes bounded explicit model profiles and checks dispatch, input and paid receipt integrity. Its tests detect the original routing defect. Model evaluation and the durable autonomous engine remain separately owned integration work, supported by current source evidence rather than a claimed universal model ranking.

**Previous:** [VM-1 comparison journal](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260909-0241-ecology-vm1-comparison-codex-journal.md) · **Next:** [OpenRouter engine review](http://nas-1.tail55d152.ts.net:4100/docs/design/20260909-0314-openrouter-engine-review-and-recommendation.md)

**UOS footer:** Canonical execution authority remains Sa-plan. Scoped source/test evidence is not publication, release or system admission.
