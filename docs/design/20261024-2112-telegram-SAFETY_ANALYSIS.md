# 20261024-2112 Telegram existing-task provisioning transport

Observed 2026-10-24T21:12:37.300Z. #fractal-l0 #fractal-l1 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md)

Scope: COMMAND_IMPL9. Existing pinned worker/frame now accepts two explicit closed operations: bind-controller-bridge and controller-bridge-result. Gleam constructs exact bounded requests and strictly interprets responses. No new scheduler, process, dependency or public service endpoint. Native provisioning does not authenticate signers or grant production admission.

## STPA control constraints

| UCA class | Hazard | Constraint and evidence |
|---|---|---|
| Not provided | Running Telegram controller cannot provision its bridge | Actual Gleam/guardian/native bind and read-only lookup pass; task unchanged |
| Incorrectly provided | Arbitrary plan/task, altered lookup or confused domain accepted | Exact8-key request, matched canonical mapping, existing-task owner/attempt, exact response; denial and mutation checks |
| Wrong time/order | Clock sampled before SQLite lock lets expired request execute | Observe native time inside transaction; expiry during contention refuses; clock-before-lock mutant killed |
| Too long/repeated | Overlong lease or retry creates another fence | Absolute expiry<=300seconds and task lease; repeated bind refuses; exact lookup resolves uncertainty without renewal |

## Raw FMEA

Scores are bounded engineering estimates, not calibrated incident rates.

| Failure | S | O | D | RPN | Mitigation / residual |
|---|---:|---:|---:|---:|---|
| Wrong mapping plan/task | 10 | 3 | 5 | 150 | Native canonical mapping check; wrong-plan mutant killed |
| Stale time after database wait | 9 | 4 | 6 | 216 | Transaction-before-clock and contention test |
| Response substitutes expiry/history | 9 | 3 | 5 | 135 | Gleam exact binding/mode/future-time validation; three mutants killed |
| Lost reply causes blind retry | 9 | 4 | 5 | 180 | Exact lookup plus explicit absent/rejected outcomes; service caller persistence still pending |
| Trusted codec mistaken for live authority | 10 | 4 | 6 | 240 | No Telegram route enabled; protected signer/profile/current coordinator/host/clock integration remains open |

Authority/dependency gates precede priority. C5*T5*F5*Dep5*I5=3125 estimate, interval2000..3125; current Sa-plan/coordinator/workspace claims remain9/9/2. Risk active check passed21:05Z. No score grants execution authority.

## Verification

90focused Gleam tests pass, including7 new protocol-client groups and83 previous cancellation/approval/ingress/store checks. Twelve native suites pass with0failed/0skipped,12reaped/0residual;11 optional telemetry observations missing and disclosed. Real Gleam transport exercises absent lookup, bind, refused repeated bind and exact reconciliation, preserving all controller fields. Native request malformed/duplicate/missing/noncanonical-number inputs refuse; actual clock-lock race refuses expiry. Ops_mutate4killed0survived0void plus3Gleam mutants killed; both restored. Existing cancellation/restart/outbox tests pass against the new worker. No live Telegram acceptance or full system suite claimed.

## Preserved failures and corrections

Codex test callback parentheses caused initial build refusal; corrected. A regression invocation named nonexistent telegram_memory_test and was canceled after87 passing checks; preserved as nonpassing. Correct actual baseline plus newclient rerun passes90. AGY proposal lacked explicit raw UTF8 precheck and relied on unqualified bind operator; Codex added the guard and qualified Result.bind before build. First actual native integration passed.

## Remaining obligations

Persist original provision request in protected startup state; inspect exact binding after uncertain outcomes without reissue. Current profile/signer ingress, coordinator/host/clock effect-time enforcement and live service route are not yet connected. Existing mapping must be independently configured; this protocol never creates provenance or tasks. Lookup history is not current authority. Existing flat nested transaction behavior is retained: inner errors abort outer transaction, with no subsequent work performed. Full Telegram/MiniApp/media/gateway/browser/live/release/admission/main scope remains.

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
