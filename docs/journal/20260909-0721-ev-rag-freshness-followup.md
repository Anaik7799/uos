# EV103 RAG freshness follow-up — 20260909-0721

## 1. Scope & Trigger

Independent review placed candidate `12b978fd0a140b36f9ca22d2489e3069b2b4851f` on HOLD after five adverse probes. This follow-up is a bounded pure-Gleam cache-model repair under Sa-plan `uos/ev-rag-freshness/20260909`, task `REPAIR`, attempt 1. It preserves the reviewed candidate and adds descendants only.

## 2. Pre-State Assessment

The prior model passed 11 focused tests but accepted a future observation as fresh, let embedding refresh extend content freshness, compared unequal vector dimensions, and permitted an extreme float to reach BEAM arithmetic. Negative time and ordinary invalid mutation refusal were already observed controls.

## 3. Execution Detail

`CacheEntry` now carries a separate `embedding_observed_at_ts`. Content freshness requires `observed_at_ts <= now_ts` and an unexpired content TTL. Refresh is monotonic for embeddings and leaves content observation unchanged. Semantic lookup requires matching dimensions; validation refuses empty, oversized, and out-of-range vectors before arithmetic.

## 4. Root Cause Analysis

One timestamp was used for two different identities: cached response content and its embedding metadata. The semantic path also assumed zipped operands represented a complete vector comparison, while numeric validation did not keep dangerous magnitudes from the dot-product path.

## 5. Fix Taxonomy

The repair is typed state-boundary hardening: separate observations, monotonic update ordering, dimension equality, and bounded numeric input refusal. It changes no retrieval provider, model, network, disk, or persistence interface.

## 6. Patterns & Anti-Patterns Discovered

An embedding update is not evidence that response content was re-observed. Zipping inputs without a length predicate silently changes the semantic relation. Input validation must happen before similarity arithmetic, where an exception would otherwise bypass typed cache outcomes.

## 7. Verification Matrix

The native focused runner compiled with realized Gleam 1.16.0 and executed on OTP 29 at `/tmp/uos-rag-followup5-20260909-0535`: 15 direct checks passed. New checks cover pre-observation stale lookup, out-of-order refresh preservation, unequal-dimension semantic miss, and extreme-vector refusal; the revised existing check covers content expiry after embedding-only refresh. The canonical active risk check passed at `2026-09-09T05:20:20Z`, assessment SHA-256 `8a4da56cca4a3d1c33c96491b9f1ef8d6583055ba432f9f6a077e6d81fb71705`.

## 8. Files Modified

- `apps/cepaf_gleam/src/cepaf_gleam/knowledge/rag_cache_mesh.gleam`
- `apps/cepaf_gleam/test/rag_cache_mesh_test.gleam`
- `apps/cepaf_gleam/test/ev_rag_freshness_runner.gleam`
- `docs/reviews/20260909-0718-ev-rag-freshness-followup-risk.json`
- `docs/reviews/20260909-0721-ev-rag-freshness-followup-source-summary.json`

## 9. Architectural Observations

The cache model can now distinguish content age from embedding age, but caller-supplied timestamps remain model inputs. This evidence does not establish clock trust, vector provenance, retrieval freshness, model inference, disk durability, or a network protocol.

## 10. Remaining Gaps

Independent re-review remains required. The focused runner is not a full package suite. Formal refinement, actual retrieval, embedding generation, durable persistence, and admission are outside this repair.

## 11. Metrics Summary

Prior independent review: 11 original checks passed; 7 adverse probes produced 2 passes and 5 failures. This descendant: 15 focused checks pass. The new active observation records 3 source/test evidence files and no runtime-admission authority.

## 12. STAMP & Constitutional Alignment

The control action is cache insertion, refresh, and lookup. Constraints prevent unsafe early or expired content, incomplete semantic comparison, and arithmetic-failure paths. The Sa-plan task remains executing; the native checker reported `authority: NONE` and `runtime_admission: NOT_GRANTED`.

## 13. Conclusion

Candidate `cfd3afbae74f996d42321843cc48248cd3aaf956` is ready for independent re-review, not completion or admission. Its source hashes and invocation receipt are recorded in the accompanying source summary.

## Verification checklist — 18 checkpoints

### Domain 1: Metadata, time, and navigation

1. Timestamped filename: pass.
2. Scope and task identity: pass.
3. Candidate identity: pass.
4. Time observation recorded: pass.

### Domain 2: Zero-Muda and storage safety

5. No Bevy source: pass.
6. No Graphite source: pass.
7. No persistence mutation: pass.
8. No downloaded dependency: pass.

### Domain 3: Testing and math

9. Prior counterexamples preserved: pass.
10. Future-observation case: pass.
11. Embedding/content split case: pass.
12. Dimension agreement case: pass.

### Domain 4: Control and observability

13. Extreme numeric refusal: pass.
14. Native Gleam compilation: pass.
15. Native OTP focused execution: pass.
16. Candidate hashes: pass.

### Domain 5: Governance and Jujutsu

17. Sa-plan task remains executing: pass.
18. Independent re-review and admission remain pending: pass.
