---
id: hermes-imported-20260804-wiki-zk-pipeline-benchmark
status: published
type: reference
generated: false
allow_example_links: true
migrated_from: zigvm/docs/journal/20260804-wiki-zk-pipeline-benchmark.md
id: 6bc2f2ec-7b27-4c23-b693-2a92c9f5abf5
title: Wiki and Zettelkasten Pipeline Benchmark Dashboard
status: published
verified_by: codex
type: evidence
tags: [benchmark, wiki, zettelkasten, eio, quint, smtml, rete-ul, stan]
ktype: source
maturity: incubating
domain: imported-journals
created: 2026-08-08
---

# Wiki and Zettelkasten Pipeline Benchmark Dashboard

Generated `20260804-131242`. Authority: report-only telemetry plus executable differential laws. Gate authority remains the existing hard verification pipeline.

Relations: [[20260804-infranodus-design-superset-journal]] · [[20260804-wiki-zk-parallel-pipeline]] · [[20260804-131604-sa-plan-c3i-admission-journal]] · [[20260725-zk-wiki-system-architecture]]

## Progress

- [x] Stage-level wall, CPU, allocation, byte, work, and budget telemetry
- [x] Immutable render context and byte-identical sequential oracle
- [x] Eio guided self-scheduling with exactly-once accounting
- [x] Quint bounded scheduling model
- [x] SMTML concrete-trace refutation of duplicate/missing work
- [x] Live Rete-UL wiki/gate isolation
- [x] Stan latency posterior, advisory only
- [x] Indexed backlink reduction and Aho-Corasick unlinked mentions
- [x] Worker-count, corpus-size, and cold/warm sensitivity
- [x] Canonical gate and Zero-Trust `--verify-cycle`
- [x] Sa-plan Store closure: 18/18 completed
- [ ] NUMA topology discovery, pinning, and hierarchical stealing — `unavailable_observed`

## Outcome KPIs

| KPI | Baseline | Final | Impact |
|---|---:|---:|---:|
| Internal end-to-end | 125.15 s | 9.42 s | 13.281×; 92.5% reduction |
| Corpus build | 35.97 s | 1.47 s | 24.396× |
| Parallel render | 183.56 ms | 121.50 ms | 2.950× at 4 workers |
| Semantic checks | 6,473 | 6,479 | all green |
| Rendered bytes | 66210052 | 66210052 | conserved |
| Peak RSS from `/usr/bin/time` | 750,284 KiB | 588,984 KiB | 21.5% reduction |

The render-kernel Amdahl estimate at 4 workers is parallel fraction `p≈0.881` and serial fraction `1-p≈0.119`. This applies only to the render kernel; rendering is now too small a share of the full pipeline for more render workers to materially improve end-to-end latency.

## Final stage profile

| Stage | Actual | Budget ms | Budget state |
|---|---:|---:|---|
| total | 9.42 s | 90000 | within |
| dynamic-projections | 2.60 s | 30000 | within |
| render-context | 1.58 s | 30000 | within |
| corpus-build | 1.47 s | 10000 | within |
| structural-contract | 1.39 s | 5000 | within |
| metadata-api-json | 1.05 s | 5000 | within |
| zk-fractal-alignment | 714.18 ms | 15000 | within |
| render-sequential-oracle | 358.39 ms | 30000 | within |

## Worker sensitivity

| Workers | Sequential ms | Parallel ms | Speedup | Efficiency |
|---:|---:|---:|---:|---:|
| 1 | 360.34 | 333.99 | 1.079× | 1.079 |
| 2 | 356.53 | 210.38 | 1.695× | 0.847 |
| 4 | 334.84 | 127.20 | 2.633× | 0.658 |
| 8 | 395.87 | 185.82 | 2.130× | 0.266 |
| 9 | 332.39 | 170.61 | 1.948× | 0.216 |

Measured choice: four workers. Eight and nine workers regress because shared-memory/GC/domain overhead exceeds useful parallel work.

## Corpus and cache sensitivity

| Pages | Build ms | Context ms | Parallel render ms | Speedup | Cold page ms | Warm page ms | Naive ref ms |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 64 | 440.00 | 62.20 | 13.95 | 1.596× | 46.329 | 0.327 | 1985.98 |
| 128 | 670.96 | 211.61 | 18.92 | 2.148× | 187.663 | 0.341 | 6129.55 |
| 256 | 868.53 | 419.31 | 40.22 | 2.136× | 368.856 | 0.190 | 14464.25 |
| 512 | 1186.87 | 1027.10 | 90.42 | 2.551× | 1027.913 | 0.347 | — |
| 643 | 1361.45 | 1473.76 | 125.64 | 3.097× | 1382.307 | 0.453 | — |

The retained naive reference is bounded to 256 pages in scale sweeps; the full 643-page admission differential took 34.43 seconds and matched exactly. At 643 pages, compatibility page rendering improves from about 1.38 seconds cold to about 0.45 ms warm because the immutable corpus context is reused.

## Formal and control checks

| Technique | Question | Result | Authority |
|---|---|---|---|
| Sequential OCaml oracle | Are ordered HTML values identical? | byte-equal over every page | admission |
| Eio + GSS | Is every coordinate produced once with bounded workers? | green | execution |
| Quint | Can the bounded CAS-linearized claim model skip or duplicate work? | no violation in seeded bounded run | evidence |
| SMTML/Z3 | Is a bad visit compatible with the observed concrete trace? | UNSAT | evidence with independent OCaml oracle |
| Rete-UL | Can wiki/ZK report facts affect gate admission? | decoupled; 5 laws | gate-isolation guard |
| Stan | What is P(page render ≤100 ms) in this run? | 0.9984, correlated-page disclosure | report-only |

## Optimization decision algorithm

1. Rank stages by wall time, CPU, allocation, bytes, and duplicated acquisition.
2. Optimize the largest measured stage only.
3. Preserve the sequential interpretation and compare values, not formatting claims.
4. Sweep workers and corpus sizes; compute speedup, efficiency, saturation, and cache effects.
5. Reject changes that trade latency for semantic drift, unbounded RSS, or hidden authority coupling.
6. Repeat until stages meet budgets or carry an explicit measured residual.

## Ranked residuals

1. Render-context preparation (~1.58 s): similarity and transitive inference remain superlinear. Consider sharded immutable indexes or incremental invalidation before more domains.
2. Corpus build (~1.47 s): parsing still uses sequential mutable capture state. Make extraction state local before any parallel parse.
3. Structural/dynamic validation (~4.0 s combined): scan once into a compact observation record instead of repeatedly searching full HTML.
4. Code inventory/search (~0.71 s): add content-addressed inventory caching shared by requests.
5. NUMA: topology, first-touch placement, affinity, and hierarchical stealing are not implemented or claimed. Introduce only with hwloc/OS evidence through permitted OCaml FFI and cross-socket benchmarks.
