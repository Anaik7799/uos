# 20261024-2057 Telegram existing-task bridge safety analysis

#fractal-l0 #fractal-l1 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md)

Scope: COMMAND_IMPL attempt9, trusted native store primitive only. Bind a bridge to an already-executing canonical task; never claim it again, mutate its lease or advance its attempt. Existing claim_bridge_lease unchanged. Native API is not public ingress or an admission grant.

## STPA unsafe control actions

| UCA class | Hazard | Control / evidence |
|---|---|---|
| Not provided | Valid running controller cannot acquire bridge, making approved cancellation unreachable | Bind to exact existing owner/attempt with no task mutation; positive and cancellation fixture evidence |
| Provided incorrectly | Wrong worker, attempt, domain or duplicate live bridge acquires control | Atomic canonical task observation, strict identity/domain checks and exclusive live bridge; refusal and two-connection race tests |
| Wrong timing/order | Rebind stale task or request bridge beyond task expiry | BEGIN IMMEDIATE, task expiry cap and current attempt; exact expiry boundary tests |
| Applied too long/stopped too soon | Bridge outlives controller or recovered history causes repeated effect | Finite expiry<=task expiry; positive monotone fence; historical lookup remains separate; service integration still pending |

## Raw FMEA and priority

Scores are engineering estimates, not calibrated incident frequencies.

| Failure mode | S | O | D | RPN | Mitigation / residual |
|---|---:|---:|---:|---:|---|
| Task lease re-claimed during bridge setup | 9 | 5 | 4 | 180 | New binding writes only bridge row; full before/after task comparison |
| Owner/attempt check missing | 10 | 3 | 5 | 150 | Exact predicates inside transaction; two killed mutations |
| Bridge exceeds task expiry | 9 | 3 | 4 | 108 | Reject overlong duration; no clamp; mutation killed |
| Duplicate live bridge replaced | 9 | 3 | 4 | 108 | Refuse all live rows; two-connection exactly-one winner; mutation killed |
| Caller mistakes helper for admission | 10 | 4 | 6 | 240 | No public wire endpoint; protected runtime signer/profile/time/coordinator checks still required before activation |

Authority and dependency gates precede priority. C=5,T=5,F=5,Dep=5,I=5 =>3125 planning estimate, interval2000..3125. No queue authority inferred. Risk assessment refreshed20:51Z; active-checkCOMMAND_IMPL9 passed.

## Evidence and falsifiers

23 targeted bridge assertions plus existing cancellation and historical/restart tests run inside12 native suites;0failed/0skipped,12reaped/0residual,11 optional telemetry observations missing. Ops_mutate killed5/5,0survived/void, source restored. First compile failure was a test record-label ambiguity, corrected with Store.bridge_mapping annotation. Zero-fence fixture insertion was correctly rejected by existing SQLite CHECK; corrupt-state test now explicitly disables constraints only on its disposable injection connection. Production constraint and API checks unchanged. Exact candidate/source manifest and independent review are required before acceptance.

## Remaining integration

Need protected bridge provision transport and runtime binding, authentic signer/profile ingress, current effect-time coordinator/clock/host checks, live command route and absent/uncertain reconciliation. This slice does not enable cancellation from Telegram, terminate a worker process or admit production. No new package/dependency/scheduler/EV number.

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


[Previous](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261024-2047-telegram-durable-cancellation.md) · [Next](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md)

UOS footer: component evidence is not admission.
