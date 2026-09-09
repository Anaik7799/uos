# EV RAG cache freshness repair journal

Candidate: `12b978fd0a140b36f9ca22d2489e3069b2b4851f` (`unxwrtloswzzkostwzwqslkvxuzoxnvn`). This journal is evidence-only and does not admit EV103.

## 1. Scope & Trigger

Independent review found that the pure RAG cache lookup ignored TTL, mutations accepted negative or unbounded inputs, and refresh did not renew a freshness observation. Scope was limited to the cache model, its tests, and its focused Gleam runner.

## 2. Pre-State Assessment

`lookup_exact` and `lookup_semantic` had no `now_ts`; TTL was consulted only by explicit eviction. `put` accepted arbitrary vectors, strings, chunks, token counts, and TTLs. `refresh_vector` changed an embedding and access time while TTL still derived from creation time.

## 3. Execution Detail

Added `observed_at_ts`, typed `CacheFresh`, `CacheStale`, `CacheMissing`, and `CacheRefused` outcomes, and explicit input limits. Lookup now receives the observation time. Invalid mutation input leaves state unchanged. Valid refresh replaces the observation time used by TTL. Added a focused runner for the cache tests.

## 4. Root Cause Analysis

Freshness was represented as an eviction concern instead of a lookup contract. The mutable boundary lacked validation, so accounting and retained resources could be invalid before any cache policy executed.

## 5. Fix Taxonomy

Typed freshness outcome; timestamped observation; fail-closed validation; bounded character/vector/chunk/token/TTL policy; refresh-to-observation transition; regression tests.

## 6. Patterns & Anti-Patterns Discovered

TTL is enforceable only where an observation clock is supplied. A refresh flag or access timestamp does not establish a fresh observation. Clamping or rejecting values at mutation boundaries prevents invalid internal accounting; this model rejects by returning the unchanged mesh.

## 7. Verification Matrix

Red observation: `expired_lookup_is_not_returned_as_a_hit_test` failed against the base because an entry at `1000` with TTL `10` was returned as a hit at `1010`.

Green observation: Gleam 1.16 compiled to `/tmp/uos-ev-rag-freshness-final-20260909-0523`; OTP 29 executed `ev_rag_freshness_runner` with `erl -s`, exit 0, covering 11 focused tests. No package download occurred. Native active risk observation passed at `2026-09-09T05:04:33Z`, assessment `4aa709e79ca11e14cf8bbe2a5acc4956380b74b2441ab65da5280df241c89cc7`.

## 8. Files Modified

- `apps/cepaf_gleam/src/cepaf_gleam/knowledge/rag_cache_mesh.gleam`
- `apps/cepaf_gleam/test/rag_cache_mesh_test.gleam`
- `apps/cepaf_gleam/test/ev_rag_freshness_runner.gleam`

## 9. Architectural Observations

The cache is a pure in-memory model. Its `CacheFresh` result is a cache-state fact only; it neither retrieves documents nor invokes embeddings or an LLM.

## 10. Remaining Gaps

Actual retrieval, embedding generation, inference, authentication, disk persistence, restart behavior, integration, formal refinement, and EV admission remain unverified and unclaimed.

## 11. Metrics Summary

Bounds: capacity 1024; embedding dimensions 1024; query 8192 characters; response 65536 characters; chunks 32 at 8192 characters each; token count 1,000,000; TTL 86,400 seconds. Focused tests: 11 pass.

## 12. STAMP & Constitutional Alignment

The model refuses unsafe cache mutation and distinguishes stale data from missing data before a caller could represent it as a fresh answer. Risk portfolio: `docs/reviews/20260909-0450-ev-rag-freshness-risk.json`; active observation grants no runtime admission or effect authority.

## 13. Conclusion

The candidate is ready for independent review. `REPAIR` remains executing and no task completion, integration, deployment, or admission action occurred.

## Comprehensive Verification Checklist & Provenance

| Domain | Checkpoints | Status |
| --- | --- | --- |
| Metadata, timestamp, navigation | 01 timestamped journal; 02 candidate ID; 03 workspace identity; 04 source hashes | PASS |
| Zero-Muda and storage safety | 05 no Bevy; 06 no Graphite; 07 no Graphene dependency; 08 no storage mutation | PASS (scoped source review) |
| Testing and math | 09 red observed; 10 focused green; 11 compiler observed; 12 OTP observed | PASS |
| Control and observability | 13 typed stale/missing; 14 mutation refusal; 15 bounded resources; 16 timestamped refresh | PASS at pure-model scope |
| Governance and Jujutsu | 17 immutable candidate; 18 active Sa-plan/risk observation | PASS; task remains executing |
| Provenance | candidate-bound SHA-256 equality; no admission claim | PASS |

Source equality at review time: `rag_cache_mesh.gleam` `4d64da8f446196ccaa9161d766a6961c13c3cb0b9f19e5aeb1301c2764244ec5`; `rag_cache_mesh_test.gleam` `55f7c2756461c0325af31337d36f2ba4d8f897ae1205917638d7eb26704b6c16`; runner `8f753ec01b438f374ff91691e6cbcc0ca29c523ae3f8840642c48e88aad3c75f`.
