# EV103 RAG numeric repair — 20260909-0736

## 1. Scope & Trigger

Independent re-review of `7d577676120e61c32c3901e56e82a36984f3a763` found that its scale-normalized cosine still treated every scale at or below `1e-6` as zero. The bounded follow-up under `uos/ev-rag-freshness/20260909` task `REPAIR`, attempt 1, preserves all prior candidates and corrects only pure Gleam cache arithmetic and focused tests.

## 2. Pre-State Assessment

The preceding numeric candidate fixed overflow for accepted `1.0e100` values and passed 16 local checks plus 9 earlier independent checks. Independent numeric review added six cases: maximum dimension, mixed scale, antipodal, and zero controls passed; tiny nonzero analytic similarity and tiny semantic matching failed.

## 3. Execution Detail

The cosine zero guard now tests exact zero only. Every nonzero vector is scale-normalized before norm and dot-product work. Regressions cover `[3e-100,4e-100]` versus `[4e-100,3e-100]`, a tiny semantic cache match, subnormal identity `[1e-320]`, and the exact-zero control.

## 4. Root Cause Analysis

The earlier repair retained an epsilon intended for raw floating-point norms. After normalization, scale magnitude no longer predicts arithmetic safety, so that threshold conflated valid tiny data with an actual zero vector.

## 5. Fix Taxonomy

This is a numerical-state predicate repair: exact-zero identity, scale-independent normalization, and focused boundary controls. It retains the existing maximum dimension and finite magnitude policy without reducing accepted tiny values.

## 6. Patterns & Anti-Patterns Discovered

An epsilon can be correct before rescaling and incorrect after rescaling. Numeric safety must distinguish representation safety from semantic identity. A magnitude cutoff is not a substitute for a zero predicate when normalization preserves ratios.

## 7. Verification Matrix

The local focused runner first reproduced the failure in `/tmp/uos-rag-tiny-red-20260909-0736`. It then compiled with realized Gleam 1.16.0 and executed with OTP 29 from `/tmp/uos-rag-tiny-green-20260909-0739`: 19 direct checks passed. Normal analytic, `1e100`, tiny, subnormal, and zero controls passed. Native active-risk validation passed at `2026-09-09T05:34:58Z`, assessment SHA-256 `06edc6c3633adf1c7f67bfc16904399a8e98ee97ec1a0fbbe09eb2019909b352`.

## 8. Files Modified

- `apps/cepaf_gleam/src/cepaf_gleam/knowledge/rag_cache_mesh.gleam`
- `apps/cepaf_gleam/test/rag_cache_mesh_test.gleam`
- `apps/cepaf_gleam/test/ev_rag_freshness_runner.gleam`
- `docs/reviews/20260909-0735-ev-rag-tiny-numeric-risk.json`
- `docs/reviews/20260909-0736-ev-rag-numeric-source-summary.json`

## 9. Architectural Observations

Scale normalization constrains cosine intermediates for the cache model, while content freshness and embedding observation remain separate state facts. Caller-provided timestamps and embeddings remain model inputs; this work does not provide clock, provenance, retrieval, inference, disk, or network evidence.

## 10. Remaining Gaps

Independent re-review is mandatory. No full package suite, actual retrieval, embedding generation, persistence, distributed transport, formal proof, task completion, or EV admission is established.

## 11. Metrics Summary

Focused runner count: 19 passed. Prior numeric re-review: four controls passed and two tiny-vector probes failed. The current active checker inspected three candidate-bound source/test files and reported authority `NONE` with runtime admission `NOT_GRANTED`.

## 12. STAMP & Constitutional Alignment

The controlled action is semantic cache lookup. The exact-zero constraint prevents false misses while normalized arithmetic prevents the prior overflow. Sa-plan remains the sole authority and `REPAIR` remains executing; no report-only observation grants an effect or admission transition.

## 13. Conclusion

Candidate `11fa5b0e561580081479420df54dd9a66d13153a` is ready for independent review of all freshness and numeric repairs. It is not complete or admitted.

## Verification checklist — 18 checkpoints

### Domain 1: Metadata and time

1. Timestamped journal path: pass.
2. Candidate lineage: pass.
3. Sa-plan task identity: pass.
4. Fresh risk observation: pass.

### Domain 2: Purity and storage

5. Pure Gleam scope: pass.
6. No Bevy: pass.
7. No Graphite: pass.
8. No persistence mutation or download: pass.

### Domain 3: Verification

9. Red tiny analytic failure: preserved.
10. Tiny analytic repair: pass.
11. Tiny semantic repair: pass.
12. Subnormal and zero controls: pass.

### Domain 4: Runtime and observability

13. Realized Gleam compile: pass.
14. OTP 29 focused runner: pass.
15. Maximum accepted numeric boundary: pass.
16. Candidate hashes recorded: pass.

### Domain 5: Governance and Jujutsu

17. Immutable JJ descendants: pass.
18. Independent review, task completion, and admission: pending.
