# 20260907-1655 — Evidence-truth checks on the candidate (ETC-1..ETC-4)

#fractal-l0 #fractal-l4 #fractal-l5 #km-triad #rocha-semiotics #cybernetics #zero-muda #zk-adr #stamp-stpa

**UOS / Journal / Evidence truth** · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist)
**Live document:** [http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260907-1655-uos-evidence-truth-checks-journal.md](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260907-1655-uos-evidence-truth-checks-journal.md)
**Transclusions:** `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`
**Record:** `generated/20260907-1650-uos-evidence-truth-checks.json` · **Task:** sa-plan `uos/claude-integration/20260907-1355` `EVIDENCE-TRUTH-CHECKS` (completed) · **Actor:** L0-fable (claude-fable-5-1), route R1 · **Candidate:** main `rkwwmqlukkkp/bb8f0f94`

## 1. Scope & Trigger
Operator directive (evidence-truth checks: forecast health hardcoded, MAX worker canned vectors, board receipts without verified labels) ledgered as sa-plan task EVIDENCE-TRUTH-CHECKS; executed as an R1 deterministic inspection of the source on main.

## 2. Pre-State Assessment
`/api/v1/forecast/health` returned six literal constants; `max_worker.py` v2.2.0 described its embedder as "authentic neural embeddings"; 2 of 144 Integrate/Report rows on the signed board carried any verification marker.

## 3. Execution Detail
Read `ha/fractal_forecast.gleam` (forecast_health_json, lines 892–901), `ui/wisp/router.gleam` (forecast and inference arms), `services/inference/max/max_worker.py` (NeuralSemanticEmbedder.embed, import surface), and the board ledger; wrote the four findings with grades into the record; applied the ETC-1 fix (honest UNKNOWN health, cockpit Brier tile UNRUN, test inverted) on the integration work change; adopted `evidence_grade` and `verified_by` in my board posts from 16:50 UTC.

## 4. Root Cause Analysis
Why constants: the health surface was authored as a demonstration before any telemetry existed. Why relabelled embedder: a stub was replaced by transformer-shaped arithmetic and the comments overstated it. Why unlabelled receipts: the board schema carries free-text meta only; no field forces a grade.

## 5. Fix Taxonomy
Honest-UNKNOWN surface (ETC-1, applied); relabel request (ETC-2, ETC-4, owners AGY + Codex); board convention (ETC-3, in force for L0-fable, validator enforcement proposed).

## 6. Patterns & Anti-Patterns Discovered
DO: return `UNKNOWN` with observation counts when nothing is measured. AVOID: literal health numbers, docstrings that promote arithmetic to "neural", GET endpoints that evaluate fixtures without saying so.

## 7. Verification Matrix
| Check | Result |
|---|---|
| ETC-1 source read | six constants, no input (measured) |
| ETC-1 fix | cepaf_gleam 10332 passed / 0 failures after the change; format clean |
| ETC-2 source read | no weights, no MAX/Mojo call, deterministic projection (measured) |
| ETC-3 ledger count | 144 Integrate/Report rows, 2 with a marker (measured) |
| ETC-4 router read | three GET arms with literal inputs (measured) |

## 8. Files Modified
`generated/20260907-1650-uos-evidence-truth-checks.json` (new); `apps/cepaf_gleam/src/cepaf_gleam/ha/fractal_forecast.gleam`; `apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/forecast_cockpit.gleam`; `apps/cepaf_gleam/test/fractal_forecast_test.gleam`; this journal.

## 9. Architectural Observations
Every self-report surface needs an evidence grade next to it (SC-HIVE-KPI-001 decision transparency); the board is the right place to enforce it because every integration passes through it.

## 10. Remaining Gaps
- P1: wire real telemetry into the forecast predictors so the health endpoint can leave UNKNOWN (owner: cepaf web runtime, Codex R5).
- P2: relabel the MAX embedder and the inference GET arms (owner: AGY), or run a pinned MAX model.
- P2: `board validate --strict` to require `evidence_grade` and `verified_by` on Integrate.

## 11. Metrics Summary
| Metric | Value |
|---|---|
| findings | 4 (all Measured) |
| fixes applied | 1 (ETC-1), 3 files |
| receipts with a verification marker | 2 / 144 before; convention adopted after |
| remote tokens | 0 (R1) |

## 12. STAMP & Constitutional Alignment
Addresses H-1 (green without measurement) and H-3 (telemetry diverging from reality) and SYNC-10 (evidence before closure); no runtime action; no control action executed.

## 13. Conclusion
The candidate carried one fabricated health surface, one overstated capability label, one fixture-fed demo route and a receipt culture without grades. The fabricated surface now says UNKNOWN with zero observations, the labels are requested from their authors, and receipts from this session carry grades and a verifier field.

## Comprehensive verification checklist
Document checks and production gates have different evidence scopes; runtime items remain UNRUN for this journal.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] **CHK-01-TIME** — Host-clock timestamp prefix.
- [x] **CHK-02-TAIL** — Full clickable Tailscale FQDN references.
- [x] **CHK-03-FRACT** — Fractal tags assigned.
- [x] **CHK-04-KM** — Record, task and transclusions cross-linked.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [ ] **CHK-05-MUDA** — Dependency scan not part of this journal.
- [ ] **CHK-06-GRAPH** — Not exercised.
- [ ] **CHK-07-DRIVE** — Not exercised.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] **CHK-08-C1C8** — Not exercised.
- [ ] **CHK-09-MATH** — Not exercised.
- [x] **CHK-10-9MOD** — Unit suite executed for the ETC-1 fix (10332/0).
- [ ] **CHK-11-REGR** — Not exercised.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] **CHK-12-GLEAM** — Not exercised.
- [ ] **CHK-13-HERMES** — Not exercised.
- [ ] **CHK-14-ZIGVM** — Not exercised.
- [ ] **CHK-15-MAX** — Finding ETC-2 records that no MAX inference runs.
- [ ] **CHK-16-OTEL** — Not exercised.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — Codex R5 requested for ETC-1 and ETC-2.
- [x] **CHK-18-JJ** — Authored with standalone JJ; no native Git mutations.

</details>

Navigation: [ZK Master MOC](http://nas-1.tail55d152.ts.net:4100/zk) · [Hermes Wiki Corpus Index](http://nas-1.tail55d152.ts.net:4100/wiki) · [Review Tome](http://nas-1.tail55d152.ts.net:4100/docs/docs/handover/20260905-1801-review-tome-consolidation-and-verification.md) · **Previous:** [Holonic naming journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260907-1505-uos-holonic-naming-system-and-fractal-mapping-journal.md)
