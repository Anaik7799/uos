# EV98 synchronization frontier evidence

Observed at: 2026-09-09T15:23:42Z

## 1. Scope & Trigger

Root review reproduced stale ACK and Delta messages restoring `Synchronized` after a newer peer frontier. This evidence child binds the repair at `0d9bd0a8a8ecf26014904975a5e8e9a6c97d8d8d`; source remains immutable.

## 2. Pre-State Assessment

The preserved parent `9a75d96856da2f8e6120291747e168b790394891` passes earlier cases but has no retained causal frontier. Root's independent reordered ACK/Delta probes are preserved as pending external review evidence.

## 3. Execution Detail

A `VectorClock` field was retained for each registered `PeerSyncEndpoint`. Incoming Digest, Delta, and ACK observations merge their reported clock monotonically after any required outbound enqueue succeeds. Status becomes synchronized only for equal-local evidence that dominates the prior retained frontier.

## 4. Root Cause Analysis

Observation time was treated as causal coverage. A newer digest established divergence, but a later stale equal-local ACK or Delta replaced status without comparing the prior observation.

## 5. Fix Taxonomy

Use bounded, per-registered-peer monotone evidence; derive status from current local clock and retained evidence; retain queue-refusal atomicity.

## 6. Patterns & Anti-Patterns Discovered

Do retain causal frontier separately from a wall-clock watermark. Do not treat a queued reply, a message timestamp, or an equal-local replay as proof that previously advertised remote updates disappeared.

## 7. Verification Matrix

| Check | Result | Receipt |
|---|---|---|
| Three-peer merge RED | observed failure | `/tmp/ev98-sync-status-three-peer-red-run-20260909-1422.json` |
| Reordered stale-ACK RED | observed failure | `/tmp/ev98-sync-status-frontier-ack-red-run-20260909-1501.json` |
| Focused causal suite | 11 PASS | `/tmp/ev98-sync-status-frontier-green-run-20260909-1510.json` |
| Retained codec/engine/deadman suite | 72 PASS | `/tmp/ev98-sync-status-retained-frontier-run-20260909-1518.json` |
| Risk active check | PASS, attempt 2 | `/tmp/ev98-sync-frontier-active-attempt2-20260909-1528.json` |
| Root independent reorder replay | pending | `/tmp/ev-sync-root-reorder-green-1508` |

## 8. Files Modified

| File | Change |
|---|---|
| `delta_mesh_engine.gleam` | Monotone peer evidence and causal status predicate |
| `mesh_sync.gleam` | `observed_clock` endpoint state |
| `delta_mesh_engine_test.gleam` | Three-peer, stale ACK, and stale Delta regressions |
| `ev98_sync_status_runner.gleam` | Focused runner entries |

## 9. Architectural Observations

```text
peer report -> retained frontier -> current-clock comparison -> status
                          |                         |
                     monotone merge             equal + covers
```

The endpoint state is bounded by registered peers. It is a pure in-memory model, not a durable protocol claim.

## 10. Remaining Gaps

P1: root independent reorder replay is pending. P2: frontiers do not survive process incarnation. P2: sender/clock authenticity, transport delivery, supervised peer-loop integration, and full EV98 admission remain outside this slice.

## 11. Metrics Summary

Source candidate: 4 implementation/test files plus risk record. Regression evidence: two preserved RED observations, 11 focused PASS, and 72 retained PASS. Task is attempt 2 and remains executing.

## 12. STAMP & Constitutional Alignment

The repair constrains unsafe false synchronization and preserves fail-closed bounded queue behavior. It uses native OCaml orchestration and direct ERTS receipts only. It does not grant runtime authority, task completion, or EV admission.

## 13. Conclusion

`0d9bd0a8` makes synchronization a claim about retained causal coverage rather than a reply or timestamp. The evidence is candidate-bound and records both red histories and green runtime observations.

Independent root replay remains a required review input. The model's current-incarnation and honest-message limits are explicit; this journal makes no broader mesh or admission claim.


### Independent review addendum

Root independently rebuilt candidate `0d9bd0a8a8ecf26014904975a5e8e9a6c97d8d8d` and passed unchanged stale-ACK and stale-Delta probes. Approval: `/tmp/ev-sync-root-reorder-green-1508/20260909-1536-sync_status-independent-approval.json` (SHA-256 `87b419f76f5a1b1fbc2468d3b41b9d8acd319a5d8cbf35d1825276d7d87bc92`). Its verdict is bounded component approval only; task completion and EV admission remain separate authorities.

Final active check: `/tmp/ev98-sync-completion-active-attempt2-20260909-1540.json` recorded `ACTIVE_OBSERVATION_PASS` for attempt 2 immediately before evidence freeze.
