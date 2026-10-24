# 20261024-2233 Telegram target observation, proposals and private approval status

Observed 2026-10-24T22:32:29.280Z. #fractal-l0 #fractal-l1 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md) · [Dashboard](http://nas-1.tail55d152.ts.net:4100/static/20261024-0712-recovery-dashboard.html)

Scope: COMMAND_IMPL attempt10, development only. AGY Gemini4ArgonHigh authored the native current-target observer. Gleam owns proposal policy, measured time, current service authority and user status. A proposal is signable data, not authorization or an effect. Durable proposal storage, signed receipt collection and the complete asynchronous workflow remain pending.

## STPA controls

| UCA class | Hazard | Constraint |
|---|---|---|
| Not provided | Pending action remains invisible or cannot obtain exact signing target | User-scoped /approval status; current target tuple returned for proposal creation |
| Incorrectly provided | Foreign user's request leaks, or unrelated job is targeted | Exact bot/chat/user filter, original persisted input digest, original plan scope, closed request/response schemas |
| Wrong timing/order | Lock wait makes authority stale before target is read | Time observed after SQLite write-lock acquisition; controller task, bridge fence and target lease checked in the same transaction |
| Too long/repeated | Proposal reused indefinitely or mistaken for execution | Fresh 256-bit nonce; expiry bounded by target/controller leases and120seconds; proposal API has no effect or store mutation |

## Raw FMEA

Engineering estimates, not measured incident probabilities.

| Failure | S | O | D | RPN | Mitigation and residual |
|---|---:|---:|---:|---:|---|
| Cross-user status leak | 8 | 3 | 5 | 120 | Exact recipient filter; real HTTP fixture foreign-user denial; filter-removal mutation detected |
| Stale or foreign cancellation target | 10 | 4 | 6 | 240 | Indexed exact job lookup; controller/task/bridge/target fences; observed-after-lock clock and scope falsifiers |
| Proposal interpreted as approval | 10 | 3 | 5 | 150 | Data-only return; status says approval/execution unconfirmed; no grant or receipt API introduced |
| Native error discloses authority data | 7 | 3 | 4 | 84 | Static failure reason; target response contains only bounded identity/fence/lease fields, no job args or results |
| Fixture success mistaken for live acceptance | 8 | 4 | 6 | 192 | Candidate-bound evidence, no live recipient or admission claim |

Authority and dependencies precede C5*T5*F5*Dep5*I5=3125 (engineering interval2000..3125). Existing canonical task and coordinator/workspace fences remain mandatory. No score grants execution authority.

## Verification and falsifiers

Evidence root: var/recovery-runtime/20261024-2217-action-proposal. Normal twelve-suite native run passed with0failures/0skips,12reaped/0residual;11optional telemetry observations missing. Eleven actual service/native cases include proposal generation without mutation, requester-only status through local HTTP and foreign-user denial. Native target tests cover wrong plan/fence, expired controller/target, changed worker/attempt/state, exact schemas, a real SQLite lock wait and Gleam/native transport. The final scoped Gleam regression passes116checks. Restored native verification binds the final candidate separately.

Two native Ops_mutate cases removed bridge-fence and target-expiry checks; both were killed and source restored. The fixture Ops_mutate build adapter uses dune build --root . @all instead of the repository-specific --pkg=disabled option; mutation classification/restoration is unchanged. The first status privacy mutation was VOID because an earlier recovery scenario refused an expired clock-delivery sample. It is retained, never counted as killed. A bounded rerun without changing the clock guard reached and killed the intended foreign-user law, then restored and rebuilt the original source. No production threshold was relaxed.

## Preserved verification selection error

An accidental whole-module run included copied fault-injected service fixtures beyond their four intended test entrypoints. Two unrelated recovery assertions failed and the35/45second bounded run expired; this receipt is nonpassing even though its child status field was0. Corrected the evidence wrapper to treat any timeout error as failure, and executed the intended four entrypoints plus the nine normal modules:116passed. The original receipt is retained; no production assertion or clock policy was weakened.

## Remaining obligations

Complete durable proposal and receipt collection, asynchronous approval transitions, full managed restart with expired historical profiles, remaining command backends,13MiniAppbackends,sevenmedia types,gateway,provider access,authorized live Telegram and browser acceptance,independent release/global admission/main. This slice does not claim mathematical proof or all-seven-engine execution. Native cancellation semantics are unchanged; the worker adds a read-only target protocol.


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


[Previous](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261024-2059-telegram-current-task-bridge.md) · [Next](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md)

UOS footer: component evidence is not admission.
