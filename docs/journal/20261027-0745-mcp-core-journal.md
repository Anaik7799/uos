# 20261027-0745 — MCP activation core verification (MCP_ACTIVATE attempt 2)

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda #tailscale-web

`uos/hive-development/20261027-0532` / `MCP_ACTIVATE` attempt 2 · worker `claude-hive-receipt-fix-2585` · grant `c4c98b8a…` · candidate `4366da874475ca47b747cbc89c1c3382c589c1c11bf14c54905ae98ca7180b92` · prior journal [receipt-core](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261027-0745-receipt-core-journal.md) `e0f35c15…`. Sa-plan is the sole authority; no admission granted. EV ceiling 93; EV-94..109 NOT_ADMITTED.

## 1. Scope & Trigger
Verify the reviewed MCP interface on current controls after `RECEIPT_FIX` attempt 2. Same grant and server, no restart. No source, config or guidance edits; no production, network or provider calls.

## 2. Pre-State Assessment
`PREFLIGHT_PASS`, 0 findings (`var/harness/20261027-0745-mcp-preflight.json`); risk 236876 B under the 262144 B cap; 14 guarded sources at `4366da87…`, 0 drift; 38 prior receipts preserved. Prior that activation holds: 0.90.

## 3. Execution Detail
Heartbeat before each phase. Claim `claude-2585-mcp-claim-1` → attempt 2, epoch 2; then build, test, smoke write, same-intent replay, pure refusals. No diagram; the ordered list carries it.

## 4. Root Cause Analysis
No defect arose. Analysis of Competing Hypotheses (ACH) on one anomaly, a heartbeat reply reading `{"ok":null,"sequence":null}`:

| Evidence | H1 response-shape variance | H2 heartbeat failed |
|---|---|---|
| Claim in same phase succeeded | Consistent | **Refuted** |
| Later heartbeats returned `ok:true` | Consistent | Refuted |
| No stale-heartbeat refusal followed | Consistent | Refuted |
| Verdict | **CONFIRMED** | REFUTED |

## 5. Fix Taxonomy
No code fix. Poka-yoke: scope guards refused every out-of-scope read. Jidoka: an unscoped claim while attached was refused. Standardized work: each phase a typed intent with a durable receipt. Containment: no effectful negative probe repeated.

## 6. Patterns & Anti-Patterns Discovered
Pattern — replay is distinguishable from re-execution only when re-execution would fail. The smoke used `expected_sha256:"ABSENT"`, so re-execution had to fail against the now-existing file; identical signature plus unchanged mtime and size is evidence, not coincidence.

Anti-pattern — assuming a file is readable because it is relevant. The preflight file is not in this task's `read_paths`; my first positive control was refused. Correct guard, wrong assumption by me.

**Devil's Advocate / Red Team, Popperian falsification.** Green here does not show the interface is safe under concurrency, only under one serial attached worker. **Explicit falsifier:** any receipt whose `output_retained_sha256` differs from the digest of its own `output`; any same-intent replay causing a second physical effect or differing signature; any out-of-scope path that reads successfully. Any one reopens this task.

## 7. Verification Matrix
Admiralty per `SC-JOURNAL-003`; only ≥B2 admissible.

| # | Claim | Evidence | Grade |
|---|---|---|---|
| V1 | Canonical attempt matched | attempt 2, epoch 2 | A2 |
| V2 | 14 sources, 0 drift | `sha256sum -c`; root recomputed | A1 |
| V3 | Build EXECUTED | `018b820e…`, full, 8408 B, retained==full `7d0cf03c…` | A1 |
| V4 | 84 passed, 0 failed, 0 skipped, 6 modules | `97c05ac7…` | A2 |
| V5 | Retained digest covers retained bytes | `tail_truncated` 19013/8192 B, `54f3d9bd…`, rehashed outside harness; root matched all 3 | A1 |
| V6 | Replay, no second effect | signature `348e7a43…`, mtime/size unchanged, one receipt pair | A1 |
| V7 | Pure refusals hold | out-of-scope, traversal, absolute, cross-task → `read_scope_refused`; unscoped claim → `release_or_complete_current_task_first` | A2 |
| V8 | Peer review | `a94bff48…` `APPROVE_MCP_ACTIVATION_DEVELOPMENT_ONLY` | B1 |
| V9 | Finite formal checks | `dd82b36c…` `FINITE_SCOPED_CHECKS_PASS` | B2 |

**NOT CLAIMED**, recorded as gaps, not evidence: fresh Lean rerun (model reused); per-assertion coverage (84 is a reported total); concurrency safety (one serial worker).

## 8. Files Modified
No source, config or guidance file. Three in-scope evidence writes: `governance/planning/20261027-0745-mcp-core-smoke.json` `137614fd…`, this journal, `governance/planning/20261027-0745-mcp-core-verification.json`. Preserved: 38 prior receipts, the oversize portfolio, the prior task's failed-attach and nested-packet records.

## 9. Architectural Observations
Authority, scope and replay are independent gates: the claim fenced identity, the read guard fenced paths, the operation id fenced repetition. The retained/full digest split from `RECEIPT_FIX` holds across both classifications in one task, `full` on build and smoke, `tail_truncated` on test, so the classifier is exercised, not asserted.

## 10. Remaining Gaps
1 Formal key reused, not rerun; two-key not complete. 2 No coverage claim; manifest is not the full dependency closure. 3 `output_sha256` on a truncated receipt stays metadata; the dropped prefix is unrecoverable. 4 Concurrency untested. 5 `AGENT_PARITY` actual Google and client activation gaps remain **HOLD**; no completion claimed for unfinished scope. 6 `backend_diagnostic`'s 16384 B fallback is outside every write scope used.

## 11. Metrics Summary
Source edits 0 · evidence writes 3 · receipt pairs 5, all terminal, 0 dangling · tests 84/0/0, 6 modules · guarded hashes 14, drift 0, verified twice · pure refusals 6 · replays 1, second effects 0 · retained-digest matches 3 of 3.

Bayesian: prior 0.90; three independently rehashing retained digests plus a replay with no second effect are unlikely under a broken interface. Posterior 0.96, 7-day half-life, **not** extended to production or concurrent operation. Lyapunov: V = unresolved or unverified effects stayed 0 throughout; dV/dt ≤ 0, no excursion, unlike the prior task.

## 12. STAMP & Constitutional Alignment
Scope guards prevented H-1 false green; replay fencing L-6 duplicate effect; the read cap L-3 evidence contamination; lease epochs stale-owner effects; Sa-plan bound every effect to attempt 2. Ψ2 nothing rewritten. Ψ3 runtime key fresh, formal key reused, so two-key is not asserted complete. Ψ5 the NOT CLAIMED items record what was not verified. Zero Bevy, zero Graphite, zero Graphene NIF introduced; no host storage serial appears here.

## 13. Conclusion
The reviewed MCP interface is verified on current controls for one serial attached worker: claim identity, build, 84-test green, scoped reads, refusals, and an idempotent same-intent replay with no second physical effect. Development evidence under a development-only grant; not production admission.

| # | Forecast | p | Falsifier | Horizon |
|---|---|---|---|---|
| F1 | Next reviewed activation replay produces no second physical effect | 0.95 | any replay mutating the target or returning a differing signature | 2026-10-31 |
| F2 | `AGENT_PARITY` closes with Google/client activation still HOLD | 0.80 | a candidate-bound activation observation landing first | 2026-11-07 |
| F3 | Fresh Lean rerun at `4366da87…` reports no new failing theorem | 0.88 | any theorem failing or needing `sorry` | 2026-11-07 |

Brier loss $B=(p-o)^2$, target $B \le 0.10$.

**UOS footer:** Sa-plan is the sole execution authority; this journal grants no admission.
