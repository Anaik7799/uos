# EV98 review repair: health replay ordering and retained observation clock

#fractal-l0 #fractal-l2 #fractal-l6 #fractal-l7 #zk-adr #zero-muda

[UOS](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Earlier journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0423-ev98-delta-freshness-repair-journal.md) · [Health source](http://nas-1.tail55d152.ts.net:4100/files/apps/cepaf_gleam/src/cepaf_gleam/crdt/health_bridge.gleam)

## 1. Scope & Trigger

Independent review of source `df0978287c4ffa9dcad14a10298081297327d3f5` reproduced loss of a newer same-tick health sample after delayed delivery and regressing consecutive gossip timestamps. This follow-up remains under child Sa-plan `uos/ev-delta-freshness/20260909`, task `REPAIR`, worker `codex-ev-delta-freshness`, attempt 1. Its scope is pure state behavior and evidence; no live mesh or admission effect.

## 2. Pre-State Assessment

Earlier source and handoff `ea42b6457a235b5302dccfcdf76b7fa5cd0c703b` remain immutable. Parent renewed workspace epoch 1 with authentic holder `01a08017-fd72-7b20-9d32-4df53154bcc8`, coordinator sequence 1219, expiry `16770440000` boot microseconds. Native active observation passed at host `2026-09-09T05:14:47Z`, with six scoped file hashes and chrony observation, before code effects.

## 3. Execution Detail

Added executable reverse-delivery, concurrent-observer, causal-update and clock regressions. A setup compile failure from a missing Gleam type annotation is preserved separately. The first genuine run produced 33 passes and four failures. Initial repair passed 37 cases; an additional sample-time precedence test then exposed a logical-clock ordering mistake (37 passes, one failure), which was repaired before final execution. Final native compilation is warning-free, all 42 discovered tests pass, the direct 42-call runner exits 0, and scoped formatting passes. Invocation receipts preserve actual argv, output digests, status and times.

## 4. Root Cause Analysis

Two changes to the same health target at the same sample time produced identical LWW timestamp/writer pairs. A delayed older value could therefore replace the newer value while the vector clock retained its later version, suppressing further anti-entropy repair. Concurrent observers also used the target as writer identity. Separately, gossip clamped its emitted timestamp but did not retain that accepted observation in engine state; incoming acknowledgement and digest paths had the same watermark gap.

## 5. Fix Taxonomy

`record_health_from` accepts an explicit serialized writer identity. The engine supplies its local node ID. Older sample times are ignored; identical telemetry is idempotent. Other accepted observations allocate `max(sample_time, previous_register_version + 1)`. The existing register `timestamp_us` field is thus a logical merge version for health entries, not a newly observed physical timestamp. Actual observation time remains `sample_epoch_us`.

Health-map merge compares actual sample time first, then logical register version and writer ID. This gives deterministic concurrent resolution for distinct writers and prevents many older same-tick writes from outranking a physically newer sample. The existing generic LWW type and other CRDTs are unchanged. The compatibility `record_health` helper uses the target as its single-writer identity; multi-observer engines use the new explicit helper.

Accepted gossip retains its clamped epoch. Incoming messages similarly retain their accepted observation watermark. Pure queue rejection returns no updated state, so rejected operations cannot advance the caller's retained watermark. Existing bounded FIFO/drain behavior and transition-only dead-man actions remain covered.

## 6. Patterns & Anti-Patterns Discovered

Version metadata must distinguish every accepted value whose replay order matters. Causal counters and physical sample times have different meanings and require an explicit comparison rule. Updating only the emitted timestamp leaves the next state transition without the observation needed to enforce monotonicity.

## 7. Verification Matrix

| Check | Observed result |
|---|---|
| Review regressions before repair | 33 passed / 4 failed |
| Physical sample precedence negative control | 37 passed / 1 failed |
| Final discovered tests | 42 passed / 0 failed |
| Direct public-test runner | Exit 0, same 42 cases |
| Focused compile and format | Exit 0, no compile warnings |
| Runtime transport, formal proof, EV admission | UNRUN, UNRUN, NOT_GRANTED |

The 42 cases comprise the previous 32, six new engine regressions, and four existing health-bridge/mesh-sync compatibility cases. Private staging uses five production modules, four test modules and one runner. The copied manifest removes only its development-dependency header to compile test modules as application modules. Already-realized canonical dependency artifacts are reused, with stale `cepaf_gleam` and `uos_swarm` outputs excluded by the native adapter. No release-closure reproducibility claim is made.

## 8. Files Modified

This follow-up modifies `crdt/health_bridge.gleam`, `crdt/delta_mesh_engine.gleam`, `test/delta_mesh_engine_test.gleam` and `test/ev_delta_freshness_runner.gleam`, plus new timestamped risk, invocation, verification and journal artifacts. The unchanged `crdt_health_bridge_test.gleam` and `crdt_mesh_sync_test.gleam` were executed. The original journal and failed receipts remain preserved.

## 9. Architectural Observations

The repair stays in pure Gleam control state. `peer_simulator.gleam` is an existing compatibility-helper caller; it remains source-unchanged and was not executed in this focused suite. Writer identity is caller-provided, not cryptographically authenticated. Existing pure JSON summary formatting is not evidence of a live mesh wire protocol.

## 10. Remaining Gaps

Convergence requires distinct writer identities and serialized retained state; conflicting values forged with an identical full version are outside this valid-state scope. Legacy conflicting registers cannot recover missing causal history retrospectively, and no live migration was performed. The list representation may retain different key ordering while pointwise values agree. Queue capacity still bounds messages, not payload bytes, and draining remains an in-memory handoff. Independent rereview is pending; no task completion or admission is asserted.

## 11. Metrics Summary

42 passing final cases; five genuine follow-up regression failures preserved across two red runs. Zero packages provisioned, zero live DB changes, zero new EV identifiers. Final source and staging digests are recorded in the separate machine-readable verification receipt.

## 12. STAMP & Constitutional Alignment

Missing health feedback, unsafe stale clearance, incorrectly ordered observation and unbounded output duration remain the assessed hazards. Sa-plan attempt 1 and parent workspace epoch 1 remain execution authority; risk observations and test results grant no deployment authority. All follow-up automation uses native OCaml and Gleam/direct native executables, with no Bash or handwritten Erlang evaluator.

## 13. Conclusion

The observed replay and watermark defects now have targeted repairs and executable regression evidence. This is a bounded development candidate for independent rereview. The EV-93 admitted ceiling is unchanged.

## Comprehensive verification checklist

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Native host/chrony observation retained.
- [x] CHK-02-TAIL — Full Tailnet links supplied; live rendering unverified.
- [x] CHK-03-FRACT — Scoped fractal tags supplied.
- [x] CHK-04-KM — Prior journal linked, no EV/ADR minted.

</details>
<details><summary>Domain 2 — Zero-Muda and storage</summary>

- [x] CHK-05-MUDA — No new dependency or foreign runtime role.
- [x] CHK-06-GRAPH — No NIF or graphics change.
- [ ] CHK-07-DRIVE — Storage tests UNRUN; no storage change.

</details>
<details><summary>Domain 3 — Verification</summary>

- [x] CHK-08-C1C8 — Applicable state/replay/order controls executed.
- [ ] CHK-09-MATH — Formal proof UNRUN.
- [ ] CHK-10-9MOD — Fleet modalities UNRUN.
- [ ] CHK-11-REGR — Live UI regression N/A to pure-state scope.

</details>
<details><summary>Domain 4 — Control and observability</summary>

- [x] CHK-12-GLEAM — Native Gleam cases executed.
- [x] CHK-13-HERMES — Native OCaml orchestration used.
- [ ] CHK-14-ZIGVM — Kernel execution UNRUN.
- [ ] CHK-15-MAX — Inference execution UNRUN.
- [ ] CHK-16-OTEL — Live telemetry UNRUN; invocation provenance retained.

</details>
<details><summary>Domain 5 — Governance</summary>

- [ ] CHK-17-SOV — Independent rereview pending.
- [x] CHK-18-JJ — Isolated Jujutsu workspace and Sa-plan task retained.

</details>
<details><summary>Domain 6 — Provenance</summary>

- [x] Earlier failed candidate and red receipts preserved.
- [x] EV admission remains NOT_GRANTED.

</details>

UOS footer: bounded source repair only; canonical execution authority remains Sa-plan.
