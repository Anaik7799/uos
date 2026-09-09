---
title: Read-only Gleam clock reuse review
observed_at: 2026-09-09T05:00:39Z
plan_id: uos/ecology-clock-review/20260909-0439
task_id: CLOCK-REVIEW
worker: codex-ecology-supervision
attempt: 1
status: READ_ONLY_REVIEW_COMPLETE
runtime_admission: NOT_GRANTED
tags: [fractal-l2, fractal-l4, zk-adr, zero-muda]
---

# Read-only Gleam clock reuse review

#fractal-l2 #fractal-l4 #zk-adr #zero-muda

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Receipt](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0539-ecology-clock-reuse-review.json) · [Raw source](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0539-ecology-clock-reuse-review.md)

## 1. Scope & Trigger

The operator required agent operations and time/check policy through a Gleam MCP harness, then explicitly authorized development bootstrap. Root assigned read-only inspection of existing Gleam time modules and a reuse proposal. This task does not implement a second clock specification, edit application source, build, call models or change services.

## 2. Pre-State Assessment

`uos_swarm/clock_contract.gleam` already defines host/boot domains, UTC and boot-relative readings, synchronization evidence, bounded policy and typed failures. `clock_guard.gleam` adds observation reports and an actor. Other modules called freshness monitors have different semantics and are not suitable clock-admission authorities.

## 3. Execution Detail

Read the clock contract, guard, fetch adapter, Erlang sampling implementation, associated test declarations, session-store clock primitive and older HA/IAM freshness modules. Compared the existing engine source hashes with its earlier frozen test receipt. No tests or live clock sampling service were executed; Sa-plan risk checks observed the host synchronization daemon only for the bootstrap task protocol.

## 4. Root Cause Analysis

The reusable pure clock contract is present. The gap is receipt admission: current guard evidence anchors its reading to the NTP reference time and raises its age allowance to one hour, so one field cannot independently express both old NTP reference age and newly delivered MCP receipt age. A source reference string alone also does not authenticate a service receipt.

## 5. Fix Taxonomy

Recommended reuse is a thin typed receipt-admission layer around existing `clock_contract.validate`, `continuity` and `failure_label`. Add service/source binding, separate NTP-reference age, delivery/capture age and sampler-duration bounds. Leave actual OS synchronization in its observed service/substrate role; a Gleam verdict does not establish that Gleam implements NTP synchronization.

## 6. Patterns & Anti-Patterns Discovered

- `clock_contract.Reading` separates UTC and nonnegative OS boot-relative microseconds. Raw Erlang monotonic instants can be negative and belong in a separate duration type.
- `clock_guard_ffi.sample` projects an old NTP reference into boot time using a clamped subtraction and samples UTC before querying Chrony. Prefer an actual capture reading and a separate reference timestamp in the new receipt.
- The old Chrony receive loop renews its timeout on each output chunk. Preserve an absolute deadline in the harness-owned observation service.
- The guard actor performs sampling/fetch/persistence inline, and plain repeated `Tick` messages schedule additional timer chains. Reuse the pure contract instead of adopting this loop unchanged.
- HA freshness stores cycle counts in timestamp-named fields. IAM freshness classifies negative age as fresh. Dead-man freshness also treats negative elapsed time as healthy. These are not clock validation functions.

## 7. Verification Matrix

| Scope | Observation |
| --- | --- |
| Existing pure clock API | Read at `clock_contract.gleam`: Domain line 10, Reading 14, Evidence 18, Policy 29, continuity 107, validate 141 |
| Existing strict limits | Offset 2 s; uncertainty 0.5 s; evidence age 120 s; clock-step 2 s; future allowance 0 |
| Guard reference-age variant | `clock_guard.strict_config` line 93 uses a 1-hour evidence-age allowance |
| OS observation boundary | `clock_guard_ffi.erl` sample line 118, Chrony spawn 140, receive loop 148, parse 157 |
| Existing tests | Six clock-contract, twelve guard and two fetch test functions found; all UNRUN by this review |
| Final source observation | ACTIVE_OBSERVATION_PASS at 2026-09-09T05:00:39Z, ten exact source hashes |
| Builds/runtime effects | UNRUN; none performed |

Final assessment digest: `d57be01d3fcab2e889f570db375eb976359e8beaae848b691c845344b2e47ac2`. A passing source observation grants no effect authority. The adjacent receipt preserves the exact assessed sources and check result.

## 8. Files Modified

Only this completion journal and its machine receipt were generated as review artifacts. Sa-plan recorded the separate CLOCK-REVIEW task and temporary risk observations were produced. No application, backend, test or specification source was edited.

## 9. Architectural Observations

Root can expose a typed `ClockReceipt` carrying an actual capture `clock.Reading`, source/receipt identity, synchronization flag, signed offset, uncertainty and NTP reference UTC. Its admission function should take the prior accepted reading, current same-domain reading and a policy. Construct existing `clock.Evidence` with the capture reading; `validate` then checks receipt age. Separately check nonnegative bounded NTP reference age, sampler duration and trusted service binding. Call `continuity(previous,current)` before replacing the accepted anchor.

UTC budget day is an integer day derived only from admitted UTC, never boot time or Lamport order. An optional stricter day verdict can hold when the UTC interval expanded by offset magnitude and uncertainty crosses midnight. Remote receipts require their own verified host/boot domain; do not subtract a remote monotonic coordinate from a local one. `session_store_ffi.clock` uses a machine-ID hash while `clock_guard_ffi.sample` uses hostname, so the harness must select one canonical host identity scheme.

## 10. Remaining Gaps

Root owns the new MCP transport, authenticated receipt binding, source observation worker, tests and final operational mapping. Clock evidence remains observation authority only. Production failover requires replicated durable reservation/counter state and an exclusive fenced epoch plus fresh clock evidence for the promoted host. OTP supervision alone does not replicate that state, and a development candidate must not automatically become production backup.

The earlier ENGINE task remains a separate unfinished record, last observed executing under attempt 1 with its lease subsequently expiring. Its final active-check receipt is absent after interruption and cannot be credited. No engine completion journal was created. This review did not reclaim, release or complete ENGINE.

## 11. Metrics Summary

Ten source files were hash-bound in the final review observation. Existing clock tests were counted by declarations, not executed. Prior engine source SHA remains `ca926e374cbe89cacd3a929e10fa242a0814529055c71a954044d8d8ed47060a`; its test SHA remains `f21c12921b5a957871e234554d58b86ef512102bebb9135fbf76c38a224503bd`. Earlier logs `/tmp/uos-ecology-engine-build-final.log` and `/tmp/uos-ecology-engine-test-final.log` recorded 11 engine plus six budget tests; they are historical evidence, not a new run.

## 12. STAMP & Constitutional Alignment

Absent synchronization evidence must hold. Unsafe or forged receipt data must not earn a trusted verdict. Wrong timing includes stale delivery, old source reference, cross-domain subtraction and UTC rollback. Excess duration belongs under an absolute monotonic worker deadline. The review followed its own Sa-plan plan/worker/attempt, performed no runtime effects and minted no EV identifier.

<details>
<summary>Comprehensive verification checklist: scoped review and explicit unknowns</summary>

| Domain | Scope |
| --- | --- |
| Metadata/navigation | CHK-01-TIME observed host/risk receipt; CHK-02-TAIL FQDN links; CHK-03-FRACT tags; CHK-04-KM review journal/receipt. |
| Purity/storage | CHK-05-MUDA no dependency change; CHK-06-GRAPH no renderer; CHK-07-DRIVE no device action, test UNRUN. |
| Tests/mathematics | CHK-08-C1C8 tests UNRUN; CHK-09-MATH existing contract reviewed, no proof claim; CHK-10-9MOD source hashes; CHK-11-REGR review findings only. |
| Runtime/observability | CHK-12-GLEAM existing pure API reviewed; CHK-13-HERMES risk observation; CHK-14-ZIGVM UNRUN; CHK-15-MAX UNRUN; CHK-16-OTEL integration UNRUN. |
| Governance/VCS | CHK-17-SOV NOT_ADMITTED; CHK-18-JJ no VCS mutation. |
| Provenance | CHK-PROV EV-93 ceiling retained. |

</details>

## 13. Conclusion

Reuse the existing pure clock contract and add only the missing receipt/source/age boundary in root's development harness. The review delivered exact APIs and implementation limitations without creating a competing specification or altering running control systems.

[Previous: budget journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0356-ecology-daily-budget-completion.md) · [Next: receipt](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20260909-0539-ecology-clock-reuse-review.json)

UOS · CLOCK-REVIEW · Read-only findings · NOT_ADMITTED
