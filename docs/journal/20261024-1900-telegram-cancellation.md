# 20261024-1900 Telegram fenced cancellation and SQLite lifetime repair

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Dashboard](http://nas-1.tail55d152.ts.net:4100/static/20261024-0712-recovery-dashboard.html) · [Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md) · [Checkpoint](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20261024-1900-telegram-cancellation-checkpoint.json)

## 1. Scope & Trigger

COMMAND_IMPL attempt6 remains open under the full Telegram goal. This increment adds canonical fenced job-cancellation persistence and repairs an observed SQLite wrapper lifetime crash. No production effect, Telegram route, reviewer authentication or new scheduler is introduced. Formal Lean/Gospel gateways were not invoked.

## 2. Pre-State Assessment

The prior action descriptor binds an exact request but cannot consume a durable cancellation atomically. Existing cancellation revokes a job lease without an atomic effect receipt. Initial isolated regression observed two SIGSEGV failures, while the unchanged baseline suite passed. No Kalman state estimate is claimed.

## 3. Execution Detail

Implemented cancel_job_once using existing Schema7 bridge mapping, current bridge/task attempt fences, exact target job lease, a store-computed request hash, and one BEGIN IMMEDIATE transaction for job compare-and-set plus receipt insertion. Replays require current authority and verified postconditions. Actual AGY design attempt timed out and was discarded; Codex implemented and tested. Actual independent AGY a0ca1544-98da-46c7-afc6-c0d660f93272 reviewed exact candidate in58.67seconds: PASS with four residual risks. No new schema, queue, package or daemon.

OBSERVE15 also completed: unchanged dashboard source/config renewal independently reviewed by actual AGY299eabe7 then corrected exact job18 configuration by AGYfac977a2. Job17 lacked config_sha256 and failed closed; job discarded. Job18 first startup refused stale observer heartbeat; MainPID0 verified before refreshed heartbeat and restart. Active invocationf512578a50f64fcab37c11975b173b67 produced HTTP200 snapshot19:04:17Z, valid through19:53:38Z;300second/task-completion cadence. Old16stopped19:01:35Z;17failed; gap preserved. Plan now explicitly requires final config digest in job args and fresh observer heartbeat before cutover.

## 4. Root Cause Analysis

ACH H1: cancellation transaction logic caused native crashes. Counterevidence: stack points to sqlite3_finalize before cancellation cases; unchanged code also crashes under concurrent-GC lifecycle stress. H2: runtime-releasing sqlite3-ocaml5.4.1 finalization/close wrappers lose their last OCaml root. Upstream source, GDB stack and controlled comparison support H2. Retaining wrappers with Core.Gc.keep_alive prevents the observed failure. A first overly aggressive stress run timed out on the repaired candidate and remains a failure receipt; a paced1000-lifecycle comparison crashes baseline and passes repaired candidate. Separate fixture hierarchical-name error was corrected without weakening production validation. See candidate CAST_LOG for full competing-hypothesis evidence.

## 5. Fix Taxonomy

Poka-Yoke: bounded identifiers, hashes, UTF-8 reasons, exact worker/attempt/lease, finite expiry and typed request. Jidoka: stale authority or conflicting replay refuses; receipt insertion failure rolls back the job update. Muda: existing canonical Sa-plan storage and offload/mutation harness reused. Gc.keep_alive fixes lifetime without dependency upgrade.

## 6. Patterns & Anti-Patterns Discovered

Devil's Advocate falsification: a SQL cancelled state is not evidence that the worker process stopped or its parent task was cancelled. Result fields explicitly preserve process_quiesced=false and task_cancelled=false. Same logical effect with changed request bytes is refused. Test mutants bypassing hashing, task attempt and transaction boundaries were all killed. An intermittent native crash cannot be cleared by a single green rerun.

## 7. Verification Matrix

Final pinned native build passed. Canonical full offload profile:12 suites passed,0 failed,0 skipped;12 processes reaped and0 residual. Three meaningful source mutants killed,0 survived,0 void; source restoration verified. Permanent concurrent-GC regression completes1000 database lifecycles. Manifest594 files,99 symlinks recorded without traversal,3 changed source/interface/test matches. Admiralty B2: scoped directly observed evidence and independent review meet the declared B2 development threshold; no live Telegram, global admission, full system or seven-engine completion inferred.

## 8. Files Modified

Candidate667a8775f6e2a6b28523083742a1404154a5d98b: sa_plan_store.ml, sa_plan_store.mli, test_sa_plan_leases.ml and timestamped cancellation CAST_LOG. Integration bookmark integration/telegram-cancel-store-20261024-1900 preserves it. Canonical checkpoint, journal and execution-plan projections record the result separately. Main is unchanged.

## 9. Architectural Observations

Hermes owns canonical persistence and bounded native verification; Gleam must authenticate incoming approvals, observe clocks and supervise effects before exposing this primitive. Existing schema and controller lease semantics remain intact. Retry after expiry requires a separate authorized receipt read. The lifetime repair covers the observed finalize/db_close paths, not a full dependency FFI audit; no category-theoretic proof claimed.

## 10. Remaining Gaps

Authentic reviewer/operator receipts, trusted Gleam execution adapter, process-quiescence observation where required, and Telegram controlled-action routing remain. Other command backends, actual provider completion,13 remaining MiniApp data backends and browser tests,7 media types, gateway, integrated/live acceptance, release/global admission and stabilized main integration remain. Runtime61/71 and release25/33 do not express feature completeness. COMMAND_IMPL is now attempt7 with fresh preflight/active checks through20:03:29Z; workspace epoch2 renewed.

## 11. Metrics Summary

12 current native suites,3 killed mutants and1000 lifecycle iterations are different metrics and are not summed with earlier command test totals. Exact AGY independent review58.67seconds. The earlier forecast p=.6 for another required executable obligation by19:10 has supporting observation at18:54, but its horizon has not yet elapsed. No calibrated Bayesian posterior, Lyapunov convergence or all-feature ETA is inferred.

## 12. STAMP & Constitutional Alignment

Not-provided cancellation can leave work running; unsafe cancellation can revoke the wrong worker; wrong timing can act on a new attempt; prolonged control can reuse stale authority. Exact mapped scope, active attempts, short expiry, compare-and-set and atomic receipt address those UCA cases at this storage boundary. Caller authentication and actual process supervision remain explicit constraints. Canonical task/job ownership, independent review, standalone JJ and EV93 ceiling preserved.

## 13. Conclusion

The durable cancellation prerequisite and observed native lifetime defect have verified development fixes. This is progress toward reliable Telegram agent management, not completion of /approval or /andon. Next acceptance requires authenticated intent approval plus trusted execution/routing. Forecast p=.65, horizon2026-10-24T19:30:00Z: one next required controlled-action integration obligation obtains executable evidence or a concrete externally observed blocker; Brier pending.

<details><summary>Verification domain 1</summary>

- [ ] CHK-01 Timestamp — scoped evidence above; no blanketPASS
- [ ] CHK-02 Tailnet navigation — scoped evidence above; no blanketPASS
- [ ] CHK-03 Fractal scope — scoped evidence above; no blanketPASS
- [ ] CHK-04 Knowledge links — scoped evidence above; no blanketPASS

</details>

<details><summary>Verification domain 2</summary>

- [ ] CHK-05 Dependency exclusions — scoped evidence above; no blanketPASS
- [ ] CHK-06 Pure graph boundary — scoped evidence above; no blanketPASS
- [ ] CHK-07 Storage safety — scoped evidence above; no blanketPASS

</details>

<details><summary>Verification domain 3</summary>

- [ ] CHK-08 C1-C8 — scoped evidence above; no blanketPASS
- [ ] CHK-09 Math gates — scoped evidence above; no blanketPASS
- [ ] CHK-10 Test modalities — scoped evidence above; no blanketPASS
- [ ] CHK-11 Regression — scoped evidence above; no blanketPASS

</details>

<details><summary>Verification domain 4</summary>

- [ ] CHK-12 GleamOTP — scoped evidence above; no blanketPASS
- [ ] CHK-13 Hermes — scoped evidence above; no blanketPASS
- [ ] CHK-14 ZigVM — scoped evidence above; no blanketPASS
- [ ] CHK-15 MAX — scoped evidence above; no blanketPASS
- [ ] CHK-16 Trace correlation — scoped evidence above; no blanketPASS

</details>

<details><summary>Verification domain 5</summary>

- [ ] CHK-17 Independentreview — scoped evidence above; no blanketPASS
- [ ] CHK-18 Jujutsu — scoped evidence above; no blanketPASS

</details>

Provenance: EV>93 NOT_ADMITTED.


[Previous](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261024-1754-telegram-search.md) · [Next: completion plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md)

UOS footer: scoped evidence grants no global admission.
