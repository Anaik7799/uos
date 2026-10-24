# 20261024-2150 Telegram service-controlled signed cancellation

Observed 2026-10-24T21:50:10.179Z. #fractal-l0 #fractal-l1 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md)

Scope: COMMAND_IMPL10, development. The service now executes a signed cancellation stage through current canonical authority, measured clock/machine/boot, public profile, OTP store actor and pinned native transport. It returns an atomic outbox result to the existing delivery pipeline; no Telegram route or approval user workflow is enabled yet. Profile schema v2 adds an explicit machine fingerprint beside the logical Tailnet hostname. Previous v1 development artifacts remain preserved; v1 is refused by the new parser, and no admitted v1 runtime migration is claimed.

## STPA controls

| UCA class | Hazard | Constraint and evidence |
|---|---|---|
| Not provided | Signed cancellation cannot reach the native effect from service state | Actual service function plus OTP store actor and canonical native DB positive test produces truthful outbox |
| Incorrectly provided | Wrong recipient, copied host profile, invalid signature, changed context or bridge | Measured machine/boot, exact profile/request/roster, current canonical fences and native target CAS; negative cases pass |
| Wrong time/order | Effect before persistence or after expired authority | Durable reservation before native call; fresh authority/clock/profile checks before effect and current authority before reply commit |
| Too long/repeated | Previously persisted absent outcome blindly retried | Existing request performs lookup only and holds on absence; deliberate mutant re-executes and is caught |

## Raw FMEA

Engineering estimates, not calibrated incident rates.

| Failure | S | O | D | RPN | Mitigation / residual |
|---|---:|---:|---:|---:|---|
| Hostname substituted for measured identity | 10 | 3 | 6 | 180 | Separate fingerprint and FQDN fields; freshly re-signed wrong-machine packet refuses; mutant killed |
| Existing uncertain operation re-executed | 10 | 4 | 6 | 240 | Persisted existence prevents repeat; native idempotency retained; mutant killed |
| Profile changed after initial load | 10 | 3 | 5 | 150 | Fresh exact-digest disk recheck; replacement test and mutant killed |
| Wrong service or expired canonical claim | 10 | 3 | 5 | 150 | Task/coordinator checks and native transaction fences; revoked coordinator and task mismatch refuse |
| Unconfirmed process cleanup followed by new I/O | 9 | 3 | 6 | 162 | CleanupUnknown immediately holds; existing transport tests are prior evidence, no new injected service cleanup fault claimed |
| Component stage advertised as completed Telegram flow | 8 | 4 | 6 | 192 | Route, asynchronous approval workflow, expired historical service recovery and live delivery remain explicitly open |

Authority/readiness precede priority. C5*T5*F5*Dep5*I5=3125, engineering uncertainty interval2000..3125. Sa-plan/coordinator10 and workspace2 refreshed21:45Z. Canonical cross-store checks precede the native effect; native task/bridge/target checks are atomic in its own store, not an atomic transaction with the coordinator database. No score grants authority.

## Evidence and falsifiers

104 Gleam checks pass (100 approval/profile/record/ingress/store checks plus4 existing authority/uncertain-delivery regressions). Twelve native suites pass,0failed/0skipped,12reaped/0residual;11 optional telemetry observations absent. Four service-native scenarios cover a permitted effect/outbox, existing persisted absence with no repeat, changed bridge fence with no effect and revoked coordinator with no effect. Signed packet malformed/extra/duplicate/role/tampered-token/size/expiry inputs refuse; missing file, removed allowlist, wrong measured machine, stale task attempt, expired or changed profile refuse. No real Telegram recipient or HTTP delivery is exercised here. Test fixtures remain under owned temporary paths; no global file cleanup claim. Three Gleam service mutations killed,0survived/void, restored native suite passes12.

## Preserved failures and corrections

AGY initially represented receipts as tuples; Codex adapted to the actual approval.Receipt API before compilation and corrected the bounded-reader description (files reader262144bytes, accepted packet65536). The v2 schema migration left one old literal in a refusal test, making the transformation a no-op; corrected. A prior terminal OCaml semicolon made the appended let block fail parsing; removed the sequence separator. Explicit revocation initially returned the generic writer-held label; classified as authority refusal. Mutation reporting spread the numeric process status over the verdict field; original output preserved, separate classification receipt derives each verdict from exit1 and its exact precommitted failed law.

## Remaining work

Wire the service stage into the command dispatcher and trusted startup configuration. Build the actual approval request/response workflow, ordinary processing recovery after receipt expiry, and deliberate handling of confirmed absence. Provisioning/renewal remains explicit and separately fenced. Current API receives trusted local profile and packet paths, never Telegram-supplied paths. Final delivery uses existing pipeline but is not exercised in the new stage test. Full command/MiniApp/media/gateway/browser/live/release/admission/main scope remains.

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
