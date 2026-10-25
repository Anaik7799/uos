# 20261024-2210 Telegram command dispatch and historical recovery

Observed 2026-10-24T22:09:03.218Z. #fractal-l0 #fractal-l1 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md) · [Dashboard](http://nas-1.tail55d152.ts.net:4100/static/20261024-0712-recovery-dashboard.html)

Scope: COMMAND_IMPL attempt10 in development. The bounded cancellation command reaches the signed service stage and existing HTTP outbox. Trusted historical configuration is a separate recovery-only mode; it cannot execute new cancellations. Recovery looks up immutable native history and atomically commits the reply plus successor delivery authority. The existing admitted writer gate, canonical task/coordinator checks and measured machine identity remain prerequisites. No live recipient or production release is claimed.

## STPA controls

| UCA class | Hazard | Constraint |
|---|---|---|
| Not provided | Approved command or previously confirmed result never reaches recipient | Configured dispatcher and historical processing route reach the existing durable HTTP outbox |
| Incorrectly provided | New service adopts unrelated cancellation or changed historical profile | Exact immutable profile digest, original input/binding, machine, plan/task/database and current recipient checks |
| Wrong timing/order | Reply ownership changes without result, or authority expires before commit | Single generation/row CAS transaction; current authority checked before history and before commit |
| Too long/repeated | Restart repeats cancellation or duplicate reply | Historical lookup only; new effect requires active signed mode; processing/result/delivery states persist |

## Raw FMEA

Engineering estimates, not calibrated incident rates.

| Failure | S | O | D | RPN | Mitigation and residual |
|---|---:|---:|---:|---:|---|
| Historical effect replay | 10 | 4 | 6 | 240 | Recovery has no Cancel operation or Prepared reconstruction; absent outcome holds |
| Partial authority/outbox handoff | 9 | 3 | 5 | 135 | One native store apply with old-authority assertion and new-authority change; successor epoch strictly increases |
| Historical profile substituted | 10 | 3 | 5 | 150 | Exact pinned file reloaded at both service boundaries; mutable signatures never become recovery authority |
| Missing approval silently stalls a command | 5 | 4 | 3 | 60 | Pending row remains unclaimed; asynchronous challenge/status UX is still required and is not reported complete |
| Development fixture mistaken for live acceptance | 8 | 4 | 6 | 192 | Explicit fixture scope; live recipient, complete feature matrix, release/admission remain open |

Authority and readiness precede C5*T5*F5*Dep5*I5=3125 (engineering interval2000..3125). Current canonical attempt10 and workspace2 remain required; a score grants no authority. Historical expiry is not renewed, old boot is evidence only, and current measured machine must match the trusted profile. Current writer/quiescence authority remains established by existing startup lifecycle; a data-only store handoff function grants none.

## Evidence and falsifiers

111 distinct focused Gleam checks pass (107 action/profile/approval/record/ingress/conversation-store/tool cases and4 current expiry/uncertainty service regressions). Twelve native suites pass,0failed/0skipped,12reaped/0residual;11 optional telemetry observations absent. Eight native service scenarios include signed action, existing absence, wrong bridge fence, revoked coordinator, normal command HTTP delivery, successor-epoch sendability, recovery absence without re-execution and automatic recovery HTTP delivery once. Actual isolated native databases, OTP store actor, measured clock and real local HTTP transport are used. There is no real Telegram recipient. Fault injection results are recorded separately in the candidate checkpoint.

## Preserved failures and corrections

New configuration field initially exposed missing test constructors; updated explicit None defaults. Test tuple and OutboxSending patterns initially used wrong arity; compiler rejected them. A cancellation response test used the pre-effect clock and correctly refused a later result; changed to an observed post-effect clock. An initial fixture copy targeted the wrong directory; corrected after inspecting actual paths. None of these failures are suppressed.

## Remaining work

Asynchronous intent creation and signed receipt collection, user-visible pending approval state, explicit unresolved outcome handling, full managed-restart acceptance with expired historical profiles, remaining command backends,13MiniAppbackends,sevenmedia types,gateway,realprovideraccess,authorizedliveTelegramflow,browseracceptance,reviewedrelease/globaladmission/main. Native effect code and transport binaries remain unchanged.

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
