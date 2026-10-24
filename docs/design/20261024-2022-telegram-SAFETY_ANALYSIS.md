# 20261024-2022 Telegram approved cancellation safety analysis
#fractal-l0 #fractal-l1 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Completion plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md) · [Dashboard](http://nas-1.tail55d152.ts.net:4100/static/20261024-0712-recovery-dashboard.html)

Scope: COMMAND_IMPL attempt8, parent384a18f7. Pure approved request preparation and response validation connected to the real native worker in isolated signed fixtures. This increment does not enable a Telegram mutation route or grant deployment/admission.

## Executable constraints

- Intent v2 signs the native mapping ID, bridge lease ID, bridge fencing token and protected execution-profile digest as well as caller/target/candidate/time. Coordinator epoch and bridge fence remain distinct. Stable logical effect identity prevents context changes from creating a fresh logical effect.
- The profile digest identifies protected static configuration, not mutable SQLite file bytes. The caller must observe that profile, worker artifact and current source-of-truth fences; syntax validation is not observation.
- Preparation requires verified Ed25519 evidence and exact intent/binding/target equality. The exact native request and its cross-language hash use the minimum signed receipt and roster expiry. That deadline cannot extend the intent window.
- Typed readiness rechecks roster, intent, binding, target, host, boot and UTC/boot clock observations. It performs no I/O and does not replace effect-time canonical authority or actual protected configuration.
- Strict response decoding rejects duplicate/unknown/missing keys, wrong types, wrong request/mapping/effect/intent/target identities, future or expired receipt timestamps and false task/process claims. Body bound16KiB; native request bound remains8192bytes.
- Domain rejection and absent historical receipt are separate outcomes. LeaseRevoked means job lease cleared only. Historical lookup can occur after approval expiry and never renews execution authority.
- Exact prepared request must be durably stored before effect. This persistence and restart reconstruction are NOT implemented by this module. The existing service/outbox must supply them, and uncertain outcomes prohibit blind retry.
- Existing pinned guardian/worker and atomic native task/bridge/job lease checks remain unchanged. No new daemon, queue, FFI or cryptographic implementation.

## STPA: four unsafe control action classes

| Type | Hazard | Constraint / falsifier |
|---|---|---|
| Not provided | Valid approval cannot reach a useful backend | Real signed fixture traverses Gleam client, pinned guardian/native worker and historical receipt validation |
| Provided unsafe | Execution profile or lease swapped after approval; rejection treated as success | Intent v2 signs context; strict typed outcomes and adversarial response tests |
| Wrong timing | Native effect runs beyond earlier signer or roster expiry | Earliest expiry encoded into native request/hash; existing native transaction checks clock after lock |
| Duration | Uncertain effect repeated or historic receipt becomes a new grant | Stable effect ID, exact original request, read-only historical lookup; durable integration remains mandatory |

## FMEA (analyst estimates, uncalibrated)

| Failure | S | O | D | RPN | Mitigation / residual |
|---|---:|---:|---:|---:|---|
| Swapped execution context | 9 | 3 | 2 | 54 | Signed mapping/lease/fence/profile, mutation falsifier; actual profile loader remains pending |
| Approval/roster expiry extended | 9 | 4 | 2 | 72 | Minimum expiry encoded and tested; real effect-time host/boot observations remain pending |
| False cancellation receipt | 8 | 3 | 2 | 48 | Exact schema/identity/hash/status, negative tests and mutation falsifier |
| Lost request after commit | 9 | 4 | 4 | 144 | Native historical receipt exists; durable pre-effect service record and restart reconstruction still pending |
| Test approval mistaken for operator authority | 10 | 2 | 3 | 60 | Ephemeral keys confined to tests, production signer ingress and configuration not claimed |

## Verification and residual scope

62 focused Gleam tests pass (17intent,18approval,5cancellation,22ingress). Twelve native suites pass through the offload verifier,0failed/0skipped,12reaped/0residual. Eleven suites do not emit optional data-plane telemetry; that absence is retained, not misrepresented as a skipped suite. The signed native fixture additionally asserts real effect, exact Gleam/native hash equality for Unicode/quotes/backslash reason, and historical lookup after expiry. Three focused Gleam mutants are killed: omitted profile binding, ignored roster expiry, accepted false process quiescence. Source restored and compiled after mutation.

No full-system or live Telegram acceptance. Trusted runtime profile/roster and receipt ingress, canonical bridge provisioning, current effect-time host/boot/coordinator fences, durable pre-effect/restart/outbox integration remain required. Remaining entire scope:77commands,14MiniApp pages/13backend gaps,seven media types,ninefamilies,provider access,browser/live acceptance,independent release/global admission and stable JJ main integration. Runtime61/71 and release25/33 unchanged; EV>93 NOT_ADMITTED. Independent review binds the frozen candidate.

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


UOS footer: component evidence grants no global admission.
