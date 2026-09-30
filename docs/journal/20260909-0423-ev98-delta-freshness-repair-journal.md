# EV98 delta mesh and dead-man freshness repair

Created 2026-09-09T04:45:23Z from the observed host clock.
#fractal-l0 #fractal-l2 #fractal-l6 #fractal-l7 #zk-adr #zero-muda

[UOS](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Delta source](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/crdt/delta_mesh_engine.gleam) · [Freshness source](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/ha/deadman_freshness.gleam)

## 1. Scope & Trigger

Parent programme `uos/ev-admission/20260909-0210`, task `PROGRAM`, requested the existing EV98 delta/freshness state repair. Child plan `uos/ev-delta-freshness/20260909`, task `REPAIR`, worker `codex-ev-delta-freshness`, attempt 1 owns this isolated work. Scope is two pure Gleam modules and focused tests, with no networking, deployment or admission effect.

## 2. Pre-State Assessment

The workspace began at immutable `337f99137673d7866b958a38bd490fb876b2880f`. Health-map writes left the digest's causal clock unchanged. Worker epochs could regress. Outbound operations always prepended messages without a limit. Every stale tick could emit another trip/failover, reset its first-trip timestamp and increment its cumulative count; backward ticks or stale heartbeats could recover an actor. Parent recorded workspace epoch 1 under authentic session `01a08017-fd72-7b20-9d32-4df53154bcc8`, coordinator sequence 1202. No coordinator event was written under another agent's identity.

## 3. Execution Detail

Canonical native Sa-plan registration, preflight, claim and active observation preceded code effects. The initial focused native build/test attempt exposed two test-harness mistakes, preserved in receipts: development dependency classification and incorrect standard-library range calls. After repairing that setup, genuine baseline execution produced 11 passes and seven failures. Repairs then produced 26 passes and one remaining stale re-registration failure. The final code has 32 passing tests, a passing direct Gleam runner and a warning-free focused compile. All automation for this task used OCaml and direct native tools; no handwritten Erlang evaluator or Bash was used.

## 4. Root Cause Analysis

Health state and its advertised version evolved independently, so a changed observation could be hidden behind an unchanged digest. The outbound list lacked an acceptance boundary. Freshness evaluation derived actions only from elapsed time, ignoring retained status and observation order. These caused missing feedback, resource growth and repeated transition requests. Stale re-registration was a separate path that could clear the same trip and required its own regression.

## 5. Fix Taxonomy

Accepted health-map changes now increment the local vector clock and keep the mesh epoch at the maximum observed value. Replayed or older LWW samples that do not change the map do not advance the clock. Worker and gossip epochs and existing-peer observation updates do not regress.

Both `generate_gossip_digest` and `handle_incoming_message` now return `Result(..., OutboundError)`. At 256 queued messages, response-generating operations return `Error(OutboundQueueFull(256))`; the caller retains its original state and can retry after draining. Queued messages use FIFO order. `drain_pending_outbound` transfers all currently accepted messages to the caller and empties the queue; repeated draining returns an empty list. Incoming acknowledgement-only messages need no queue slot. Returned response values describe the same queued messages; callers must avoid dispatching both that preview and the drained copy.

Freshness ticks must advance `last_eval_ms`. Tripped actors retain the original trip timestamp and emit no further trip/failover actions until rearmed by a heartbeat strictly newer than both the actor heartbeat and the last evaluation. Repeated warning levels are quiet. Fresh recovery permits one later trip; counts track those transitions. Invalid interval/threshold registrations become quarantined and cannot recover by heartbeat; explicit valid fresh registration can repair their configuration. Stale re-registration cannot reset an existing actor. Actor order remains stable across evaluations.

## 6. Patterns & Anti-Patterns Discovered

A state change used by reconciliation must advance the version used to detect that change. An immutable state machine can reject a full queue atomically without rollback machinery, because no returned new state exists on rejection. Exactly-once transition requests require remembering the previous status and observation watermark. Every alternate recovery path, including registration, needs the same freshness discipline.

## 7. Verification Matrix

| Observation | Result | Scope |
|---|---|---|
| Baseline regressions | 11 passed / 7 failed | Real compiled Gleam behavior, before production repair |
| Expanded stale-registration regression | 26 passed / 1 failed | Preserved before its fix |
| Final focused compile | Exit 0, no warnings | Five production modules, two test modules and one runner |
| Final Gleeunit run | 32 passed / 0 failed | Both scoped test modules discovered from an isolated directory |
| Direct Gleam runner | Exit 0 | Same 32 public tests called explicitly |
| Scoped format check | Exit 0 | Two modified production and three test files |
| Live transport / formal proof / EV admission | UNRUN / UNRUN / NOT_GRANTED | Not established by pure state tests |

Focused staging copied three unchanged supporting modules (`delta_state`, `health_bridge`, `mesh_sync`) alongside the two changed modules. The temporary package copied the canonical manifest and removed its development-dependency section header so copied test modules could compile as application modules. This transformation affected only the private staging tree. The canonical realized dependency artifacts under `apps/cepaf_gleam/build/dev/erlang` were reused; the native BEAM adapter excludes stale local `cepaf_gleam` and `uos_swarm` output directories. The build is not claimed to establish a reproducible release closure.

## 8. Files Modified

Production: `apps/cepaf_gleam/src/cepaf_gleam/crdt/delta_mesh_engine.gleam` and `apps/cepaf_gleam/src/cepaf_gleam/ha/deadman_freshness.gleam`. Tests: the existing `delta_mesh_engine_test.gleam`, `deadman_freshness_test.gleam`, and new `ev_delta_freshness_runner.gleam`. Other new files are this timestamped journal and source/risk/invocation receipts. No runtime, ledger, shared configuration or dependency source was modified.

## 9. Architectural Observations

This is pure Gleam control-state logic. Typed queue rejection is an intentional API change; observed typed call sites in this base were confined to the scoped tests. The fixed bound counts retained messages, not payload bytes, peers, workers or health-map entries. Queue draining is an in-memory ownership handoff, not an acknowledgement of physical delivery.

## 10. Remaining Gaps

A caller that discards its original state, retries from an old snapshot, dispatches duplicate previews, or loses drained messages can still lose or duplicate external effects. The tests establish no live network delivery, persistence, acknowledgement protocol, distributed exactly-once guarantee or ownership fence. Trip actions occur once per retained state transition under a serialized owner; replaying a prior state can reproduce its actions. Peer registration still initializes a new reconciliation lifecycle. Input constructors and caller clock provenance remain separate obligations. Independent review is pending; this task is not yet completed.

## 11. Metrics Summary

32 final tests passed; eight observed regression failures were preserved across the two genuine red runs. The accepted outbound count is bounded at 256, and full-queue delta retry, both digest response branches, acknowledgement handling, FIFO draining, clock advancement, stale recovery and repeat transitions are exercised. No packages or paid inference were provisioned. Final source hashes and immutable tested candidate are bound in a separate machine-readable receipt.

## 12. STAMP & Constitutional Alignment

The assessment covers omitted health feedback, unsafe repeated trip/recovery, wrong observation ordering and unbounded queue duration. Raw pre-control FMEA uses severity/occurrence/detection 5/5/4 for stale-health clearance and 4/5/4 for repeated trips and queue growth; respective RPNs are 100, 80 and 80, all yielding band 5. These are scoped analyst judgments supported by ordinary-input reproductions, not measured incident probabilities. Final C3 × T5 × F5 × Dep4 × I3 gives 900 after scope refinement. Sa-plan and the parent workspace fence remain execution authority; tests and risk observations do not grant deployment or admission authority.

## 13. Conclusion

The requested pure-state defects have targeted repairs and executable regression evidence. The candidate is ready for independent review at this bounded development scope. No new EV number or admission record was created, and the admitted ceiling remains unchanged.

## Comprehensive verification checklist

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Observed host timestamp and risk-clock receipts retained.
- [x] CHK-02-TAIL — Full Tailnet navigation supplied; live rendering is unverified.
- [x] CHK-03-FRACT — L0/L2/L6/L7 scope tagged.
- [x] CHK-04-KM — Source and planning references supplied; no new ADR or EV minted.

</details>
<details><summary>Domain 2 — Zero-Muda and storage safety</summary>

- [x] CHK-05-MUDA — No new packages; scoped source remains pure Gleam.
- [x] CHK-06-GRAPH — No new NIF or foreign runtime role.
- [ ] CHK-07-DRIVE — Storage interlock execution UNRUN; no storage changes.

</details>
<details><summary>Domain 3 — Testing and mathematical gates</summary>

- [x] CHK-08-C1C8 — Applicable state, replay, ordering and capacity regressions executed; UI categories N/A.
- [ ] CHK-09-MATH — Formal refinement proof UNRUN.
- [ ] CHK-10-9MOD — Full fleet modalities UNRUN.
- [ ] CHK-11-REGR — Live UI regression N/A to these pure-state functions.

</details>
<details><summary>Domain 4 — Cross-language control and observability</summary>

- [x] CHK-12-GLEAM — Native compiled Gleam state tests executed; live supervision unchanged.
- [x] CHK-13-HERMES — Native OCaml orchestration and canonical risk/plan tools used.
- [ ] CHK-14-ZIGVM — Kernel execution UNRUN; unchanged.
- [ ] CHK-15-MAX — Inference execution UNRUN; unchanged.
- [ ] CHK-16-OTEL — Production telemetry UNRUN; invocation receipts retain execution metadata.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Independent review pending; admission NOT_GRANTED.
- [x] CHK-18-JJ — Isolated Jujutsu workspace and canonical Sa-plan claim used.

</details>
<details><summary>Domain 6 — Provenance</summary>

- [x] Failed observations and immutable candidates preserved.
- [x] EV-93 ceiling retained; this EV98 repair does not establish admission.

</details>

UOS footer: bounded state-model repair only; canonical execution authority remains Sa-plan.
