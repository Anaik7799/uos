# 20261027-1013 — Typed planning intent implementation (PLANNING_MCP attempt 1)

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda #km-triad #tailscale-web

`uos/hive-development/20261027-0532` / `PLANNING_MCP` attempt 2, epoch 2 · worker `claude-hive-planning-2585` · grant `6f0b476b…` · review `0b9309fa…` · [Design](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261027-1013-typed-planning-intent-design.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/). Observed 2026-10-27T10:20Z–10:36Z. **Task NOT completed; no activation.** Sa-plan is the sole authority. EV ceiling 93; EV-94..109 NOT_ADMITTED.

## 1. Scope & Trigger
First local-development planning MCP slice: one private 14th tool, three closed intents, behind the existing reviewed harness. Five code writes exactly as granted. `sa_bridge_submit`, the standard 4-read-only surface and production are untouched.

## 2. Pre-State Assessment
Pre-edit canary before any write: clock `OBSERVATION_ONLY`, offset −43 µs; readiness manifest readable at 77086 bytes, so `harness_assess` is usable as designed; candidate `8c51eb2b…` over 18 sources; **All 84 tests passed**; 13 tools advertised.

## 3. Execution Detail
Heartbeat before each phase. Scaffold → RED → GREEN, each phase preceded by an assessment refresh. Twelve refreshes were needed because every authorized control-source edit changes a guarded digest.

## 4. Root Cause Analysis
No product defect. Analysis of Competing Hypotheses (ACH) on the first write refusal, `backend_exit:1`:

| Evidence | H1 stale guarded source hashes | H2 malformed write or scope error |
|---|---|---|
| `risk-priority-check --active-check` read `HOLD` with `RP-EVIDENCE` SHA-256 mismatch on `operations.gleam` across 29 rows | Consistent | Inconsistent |
| Portfolio recorded `f64da7e1…`, disk held `985c47be…` after the granted edit | Very consistent | Inconsistent |
| Path was inside `write_paths`; CAS digest matched | Neutral | **Refuted** |
| After the refresh the identical frame executed | Consistent | Refuted |
| Verdict | **CONFIRMED** | REFUTED |

A second, distinct hold followed: *evidence predates the freshness window or postdates the assessment*, because refreshed evidence at 10:25:46Z postdated each row's 10:05:50Z observation. Advancing each row's `observed_at` past the evidence time resolved it, with `valid_until` left unextended.

## 5. Fix Taxonomy
Poka-yoke: closed intent set and closed payload key set, so an identity, role, backend, SQL or shell carrier is refused by name. Jidoka: prevalidation refuses before dispatch; everything else is Uncertain. Standardized work: one shared entry point used by both the dispatch arm and the laws. Muda: no new framework, package, directory or test module.

## 6. Patterns & Anti-Patterns Discovered
Pattern — the wrapper that protects ordinary effects can defeat a replay ledger. The generic effect path keys receipts by grant and folds attempt into the signature, so wrapping the new tool would refuse a replayed logical id *before* the inner ledger could gate it. The dispatch arm therefore bypasses that wrapper and gates internally.

Anti-pattern — concatenating a key. My first key used newline joins; `("a/b","c","d")` and `("a","b/c","d")` could collide under a separator scheme. The key is now a canonical JSON object, and two laws assert non-collision.

**Devil's Advocate / Red Team, Popperian falsification.** This slice could be mistaken for a working planner: it is not. `submit` completes prevalidation and the stable key and reports dispatch as gated pending activation; no canonical row is created. **Explicit falsifier:** any logical key that differs across two grants or two attempts; any nonzero exit classified as a refusal; any readback accepted without exact identity match; any payload over 65536 bytes admitted; any unit test mutating the canonical store; any dispatch reaching `sa_bridge_submit`. Any one reopens this task.

## 7. Verification Matrix
Admiralty per `SC-JOURNAL-003`; only ≥B2 admissible.

| # | Claim | Evidence | Grade |
|---|---|---|---|
| V1 | Grant and review are the reviewed artifacts | `sha256sum` equals `6f0b476b…` and `0b9309fa…` | A1 |
| V2 | Pre-edit baseline | candidate `8c51eb2b…`, All 84 passed, receipts `88ee1f7a…`, `7baf49b9…` | A1 |
| V3 | RED is behavioural | build succeeded first, then `Failed: 6. Skipped: 0. Passed: 90.`; receipt `245bb61f…` preserved | A1 |
| V4 | GREEN | All 104 tests passed, candidate `844f2cce…`, receipts `1464e67d…`, `a24b235…` | A1 |
| V5 | Five writes, exactly as granted | five EXECUTED write receipts, CAS on prior digests | A1 |
| V6 | Assessment refreshed truthfully | actual digests rebound, canonical whole-second UTC, `ACTIVE_OBSERVATION_PASS` with 0 findings, 251600 bytes under the 262144 cap | A1 |
| V7 | No activation, no hotload | serving harness still advertises 13 tools while the 14th exists in compiled source | A2 |
| V8 | Original six test modules kept | no new test file; planning laws added to `harness_successor_test` | A1 |

**NOT CLAIMED**, recorded as gaps: cross-command atomicity; hostile-writer or production safety; any canonical sandbox create, read or publish; live lost-reply behaviour; independent review of this slice.

## 8. Files Modified
`planning_intents.gleam` `d3b52b7f…` (new) · `operations.gleam` `df2dc3f8…` · `successor_mcp.gleam` `98e096c6…` · `admission.gleam` `4e6b88e9…` · `harness_successor_test.gleam` `b56920d0…`. Evidence: this journal, `…-planning-mcp-smoke.json`, `…-planning-mcp-verification.json`, `…-planning-mcp-validation.json`. All prior receipts preserved.

## 9. Architectural Observations
Three gates are now independent: the closed intent and key set at the type boundary, the stable logical key over an unambiguous tuple, and identity taken from the trusted `Execution` rather than the payload. The ledger key excludes grant and attempt, which is what makes a replay recognisable at all; the transport receipt id carries the trusted attempt, which is what stops a caller minting a second identity. `Store.with_transaction` gives atomicity only inside one OCaml invocation, so two CLI calls are not one transaction and no such guarantee is offered.

## 10. Remaining Gaps
1 Canonical sandbox create/read/publish UNRUN. 2 Live lost-reply and reconcile UNRUN. 3 `submit` stops at prevalidation plus key; ledger write and CLI dispatch belong to the activation slice. 4 No activation of the compiled controller. 5 Native transactional fencing absent. 6 Independent review outstanding.

**Explicit falsifier for the residual set.** Each gap is refutable by the obvious observation: a sandbox row created and read back by exact identity refutes gap 1; a simulated dropped reply that does not duplicate a logical operation refutes gap 2; a ledger pair on disk refutes gap 3; a reviewed activation refutes gap 4.

## 11. Metrics Summary
Code writes 5 · evidence artifacts 4 · new test files 0 · test modules still 6 · tests 84 baseline → 96 GREEN, 0 failed, 0 skipped · RED 6 failed / 90 passed · assessment refreshes 12 · portfolio 251600 B of 262144 · tools advertised 13, compiled 14 · canonical store mutations from tests 0 · EV minted 0.

No Bayesian or Beta-Binomial update is offered and none is justified: these are correlated observations from one session with no likelihood function or data model. No Lyapunov or stability claim is made; the plain observation is that unresolved effects were 0 at every point and the one `backend_exit:1` class was a recorded `effect_failed`, reconciled by refreshing evidence rather than by retry.

## 12. STAMP & Constitutional Alignment
Write-scope guards held every change inside the granted five; CAS prevented lost updates; `RP-EVIDENCE` prevented mutation on stale evidence, twice; lease epochs and per-phase heartbeats prevented stale-owner effects; Sa-plan bound every effect to attempt 1. Ψ2: additive, nothing rewritten, RED receipt preserved. Ψ3: runtime key fresh for the no-regression and law claims; no formal key sought, so no two-key claim. Ψ5: the gaps above are stated rather than estimated. Zero Bevy, zero Graphite, zero Graphene NIF introduced; no host storage serial appears here.

## 13. Conclusion

**Correction to this journal's earlier revision, root review 10:39Z.** The 96 helper tests did NOT establish an implemented interpreter: `submit` returned `gated_pending_activation` unconditionally and never reached the target, evidence or size guards. Those green helper counts stand as valid but narrow evidence about pure functions. The interpreter is now implemented and the suite is **All 104 tests passed** at candidate `a77a075c…`; thirteen further review findings (R1-R13 in the smoke artifact) were applied in this attempt, including a stub replay that would have read an uncertainty as success, a latching Andon release file, a fence that reserved no dispatch window, and native name rules that would have rejected a bare `T01`.

**Second correction, root reachability review.** `prepare` and `decide_ledger` were present as definitions and **never called**, so the comments claiming a shared real path were false. They are now invoked from `submit_with` (`planning_intents.gleam:324` and `:331`, with `decide_andon` at `:587`), the duplicated inline ledger logic is deleted, a replay reports typed `Replayed` while preserving the immutable original record, and the 25 s fence was moved AFTER the bounded 15 s risk phase with `clock.continuity` checked against the final fence. Helper green was not enough; independent source reachability review caught what my own green suite did not.

**Third correction, root replay-authority review.** `submit_with` fenced only the `Dispatch` branch, so a `ReplaySaved` return bypassed expiry, current-owner and control checks. A replay is read-only but still needs current reviewed authority, exactly as `harness_read_file` does. Repaired under the bounded new-control grant `20261027-1130-planning-replay-repair` (21 current control IDs pinned): `a.fence(execution, 0)` now runs immediately after the pure `precheck` and **before** the grant and ledger reads, so every path including replay is fenced; the re-observed 25 s window after the bounded 15 s risk phase remains for `Dispatch` only and its clock is still carried into `clock.continuity`.

**Restart no longer depends on memory-only code.** Before rebuilding, all **21 pinned serving BEAM binaries were located, md5-verified against the grant's `loaded_control_ids` (21/21 match, 0 mismatch, 0 missing) and retained privately** outside the build tree, with a hash manifest. The earlier `loaded_control_identity_mismatch` blocker, where a stopped process left no startable control set, cannot recur for this grant. No compiled artifact was overwritten.

**Evidence correction, cross-process Andon.** An earlier revision of these artifacts recorded cross-process Andon for the other mutation tools as `NOT_IMPLEMENTED`, needing an admission-layer change. That was wrong, and it conflated *untested at runtime* with *missing in source*. `planning.andon_guard` is wired at both generic mutation entry points, `operations.gleam:489` inside `effect` (defined `:480`) and `:825` inside `finish` (defined `:819`), and it derives the hold from the durable CURRENT pointer plus the pointed-at result record rather than from in-memory state, so it survives a fresh process, grant and attempt. Correct status is **IMPLEMENTED_IN_SOURCE, RUNTIME_UNRUN**. A separate, pre-existing limitation remains: legacy generic uncertainties unrelated to planning still rely on in-memory `state.unresolved` within one process.

**Scope honesty.** `planning_targets` is **empty** in this grant, so the backend cannot dispatch at all. This is control repair, not planning acceptance: no canonical row can be created and none was. The normal connected 4-read surface is unchanged.

**As-is, observed now.** Readiness 29 tasks, 12 completed. Catalog 65 declared, 53 unprobed, 12 unavailable. Environment **NOT_FULLY_READY**. The five guidance artifacts and eight aliases from the earlier slice stand, with client adoption and actual Google execution **UNRUN**. **To-be** preserves the full user goal: all required services and capabilities for data and control through MCP, declarative typed intent, Sa-plan execution, verified feature-database coverage, and actual client, agent, service and Telegram operation observed. Retirement is not offered as a way to drop a requirement.

**Critical path:** readiness census and sizing alongside the MCP planner, then service and agent verification with recovery, then integrated tests, with independent acceptance and JJ integration conditional. **Qualified ETA:** this slice's activation review is hours, not days; the remaining core is 1-3 focused working days; broader hive and Telegram is a 1-2 week **verification allowance, not a completion promise**, covering implementations that already exist. The whole to-be ETA is **unknown** until the census and `T01` sizing, because the dominant uncertainty is scope, not schedule.

The slice remains deliberately inert at runtime: 13 tools still serve, no canonical row was created, no CLI ran from any test, and `PLANNING_MCP` is **not** completed. Acceptance is root's to decide, not mine.

| # | Forecast | p | Falsifier | Horizon |
|---|---|---|---|---|
| F1 | A reviewed activation will create and read back a sandbox plan by exact identity on first attempt | 0.70 | any readback identity mismatch or uncertain outcome on that first attempt | 2026-11-03 |
| F2 | Independent review returns at least one factual correction to this slice | 0.75 | a review with no factual correction | 2026-10-31 |
| F3 | The next authorized control-source edit again requires an assessment refresh before its mutation | 0.95 | a mutation accepted with stale guarded digests | 2026-11-03 |

Scored by Brier loss $B=(p-o)^2$. F2 is set high deliberately: the previous guidance slice forecast no corrections at p = 0.80 and resolved FALSE at Brier 0.64.

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Sa-plan is the sole execution authority; this journal grants no admission and claims no task completion.

## Comprehensive verification checklist

Obligations for the work this journal reports. Items this attempt did not execute are left **unchecked**.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] **CHK-01-TIME** — `YYYYMMDD-HHSS-` prefix present; host clock observed, offset −43 µs.
- [x] **CHK-02-TAIL** — Full Tailnet links provided; live serving status not asserted.
- [x] **CHK-03-FRACT** — L0, L3, L4, L9 tags assigned.
- [x] **CHK-04-KM** — Design, grant, review and receipt references verified present on disk.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [ ] **CHK-05-MUDA** — Dependency exclusion scan UNRUN; no dependency, package or framework introduced.
- [ ] **CHK-06-GRAPH** — Pure BEAM/Hermes graph boundary UNRUN here.
- [ ] **CHK-07-DRIVE** — Storage interlock execution UNRUN; no host serial appears here.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] **CHK-08-C1C8** — UI categories not applicable; UNRUN.
- [ ] **CHK-09-MATH** — Four mathematical gates UNRUN.
- [ ] **CHK-10-9MOD** — Of the nine modalities only unit and property-style laws ran; the rest UNRUN.
- [ ] **CHK-11-REGR** — UI regression monitoring UNRUN.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [x] **CHK-12-GLEAM** — Gleam/OTP harness exercised: claim, heartbeat, clock, read, write, assess, build, test. Not all advertised tools verified.
- [ ] **CHK-13-HERMES** — Sa-plan OCaml store inspected read-only; its transaction boundary is reported, not exercised here.
- [ ] **CHK-14-ZIGVM** — Deterministic kernel and VFS UNRUN.
- [ ] **CHK-15-MAX** — Isolated inference UNRUN.
- [ ] **CHK-16-OTEL** — Runtime telemetry correlation UNRUN.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — Independent review of this slice is OUTSTANDING; NOT_ADMITTED.
- [x] **CHK-18-JJ** — Authored under standalone JJ discipline; no native Git mutation used.

</details>

<details>
<summary>Domain 6 — Provenance and admission integrity</summary>

- [x] **CHK-19-CEIL** — EV ceiling 93 stated; EV-94..109 NOT_ADMITTED; no EV claim made.
- [ ] **CHK-20-INDEX** — KM index enumeration of this record UNRUN.
- [x] **CHK-21-PRESERVE** — Additive only; the RED receipt and all prior receipts preserved byte-for-byte.
- [ ] **CHK-22-CHAIN** — Cycle-chain verification UNRUN.
- [x] **CHK-23-NOMINT** — No new EV number minted.
- [ ] **CHK-24-FAILCLOSED** — Metric-path fail-closed runtime behavior UNRUN in this documentation scope; no passing claim.

</details>

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Sa-plan is the sole execution authority; this journal grants no admission.
