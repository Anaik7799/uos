# 20261024-2131 Telegram durable public action profile

Observed 2026-10-24T21:31:16.814Z. #fractal-l0 #fractal-l1 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md)

Scope: COMMAND_IMPL9. Persist an immutable public signer/transport profile containing the original provisioning request. Exact digest and ten-field context must originate from the trusted launcher. No private keys, automatic renewal, new scheduler or additional FFI. Loading expired state enables historical lookup only. Profile objects are created only by durable readback.

## STPA control constraints

| UCA | Hazard | Constraint |
|---|---|---|
| Not provided | Restart loses exact provision identity | File and directory sync followed by readback; two separate BEAM processes recover exact binding |
| Incorrectly provided | Forged context, signer roster, native path or substituted request | Closed typed schema; launcher-pinned digest; context equality; original canonical request; pinned existing transport |
| Wrong time/order | File overwritten or expired profile used for action | Exclusive create; recheck reloads same digest; strict time bounds; live effect-time authority remains required |
| Too long/repeated | Restart renews lease or repeats provisioning | Stored original bytes and deadline; historical load grants no authority; no automatic bind in load |

## Raw FMEA

Engineering estimates, not calibrated probabilities.

| Failure | S | O | D | RPN | Mitigation / residual |
|---|---:|---:|---:|---:|---|
| Context/profile substitution | 10 | 3 | 5 | 150 | Exact digest and all context fields; targeted mutants killed; launcher trust remains |
| Reconstructed request changes expiry | 9 | 4 | 5 | 180 | Canonical exact restoration and two-process unchanged-state check |
| Expired profile mistaken for grant | 10 | 4 | 6 | 240 | Active predicate plus fresh file recheck; service integration still pending |
| Uncertain write retried destructively | 8 | 3 | 5 | 120 | Exclusive creation; reconcile by load; no overwrite |
| Parent renamed by same-UID writer | 9 | 3 | 6 | 162 | Existing cooperative files boundary explicitly retained; no descriptor-relative claim |

Authority and dependencies precede priority. C5*T5*F5*Dep5*I5=3125 estimate, uncertainty interval2000..3125. Risk active check passed21:29Z for attempt9; coordinator9/workspace2. Scores grant no effect authority.

## Verification and evidence age

100 focused Gleam tests and12 native suites pass. The native fixture starts one BEAM that persists/fsyncs the public profile, binds the bridge, emits its digest, then exits77. A separate BEAM loads the pinned profile and reads the exact existing binding. Controller task, original expiry, bridge fence1 and profile bytes are unchanged. This is process-restart evidence, not power-loss evidence. Twelve suites reaped, zero residual processes;11 optional telemetry observations missing and disclosed. Four Gleam fault mutations (digest/context/expiry/request binding) killed, zero survived/void; sources restored. Final formatted source regression passes100. No native production changes this increment; native test extension uses the existing independently reviewed worker.

## Corrections and remaining obligations

Initial Codex test expression used wrong pipeline precedence and failed compilation; fixed and retained receipt. AGY source propagated filesystem errors; Codex redacted them to profile_invalid before testing. Current public profile is not self-authenticating: digest/context must be supplied by the trusted launcher. Actual signer receipt ingress, live host/boot/coordinator/clock checks, service route and uncertain absent-outcome handling remain open. Finite original bridge expiry is not a continuously renewed lease. Full MiniApp/media/gateway/live/release/admission/main scope is unchanged.

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
