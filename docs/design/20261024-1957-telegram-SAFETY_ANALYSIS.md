# 20261024-1957 Telegram framed cancellation safety analysis
#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Completion plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md) · [Dashboard](http://nas-1.tail55d152.ts.net:4100/static/20261024-0712-recovery-dashboard.html)

Scope: development transport increment under COMMAND_IMPL attempt7. Parent2779b7f2. This connects the existing typed Gleam transport to the actual native cancellation transaction in isolated fixtures. Authentication, protected signer ingress, effect-time coordinator/host-boot admission and durable Telegram reply integration remain required. No release or live bot action is authorized by these tests.

## Control constraints and executable contracts

- One frame, 1..16384 bytes, exact EOF before DB access; strict schema/operation/request envelope. Nested cancellation codec retains its13 closed fields. Never accept caller time, DB path, signing bypass or arbitrary command.
- A fixed absolute DB path comes from local protected configuration. Worker rejects lexical dot segments, terminal symlink and nonregular or multiply-linked file. Parent directories and same-UID replacement remain a cooperative protected-launcher boundary.
- Store.open_existing uses SQLite NO_CREATE, exact schema7 and shape audit, with no schema DDL/migration. Existing raw CLI cancellation entry uses it too. Missing, empty, old/future stores refuse. No alternative environment path in framed worker.
- Existing Cancel_protocol acquires BEGIN IMMEDIATE before native clock observation; existing request/task/bridge/target-job fences and atomic durable receipt are unchanged. Worker does not implement duplicate SQL.
- Domain refusals are redacted framed status=rejected with exit0; framing/IO faults use nonzero transport uncertainty. Exit0 alone never proves a successful cancellation.
- Existing transport now bounds executable hashing at64MiB and checks the original5second deadline before each64KiB chunk. Actual native executable39073592bytes exceeded the old16MiB bound; stripping remained26908280bytes and was not adopted. Guardian binary and wire protocol are unchanged.
- The final transport artifact uses the unstripped compiled worker. Exact hash pinning, output/input bounds, caller-death cleanup and uncertainty semantics remain active. A reply denotes job lease revocation only; process/task termination is not asserted.
- Do not blindly retry an uncertain effect. Recover by exact original-request historical lookup; absence of a receipt is not authority to replay. Integration must persist the original request before execution.

## STPA: all four unsafe control action classes

| Type | Hazard | Constraint / falsifier |
|---|---|---|
| Not provided | Unsupported binary bound silently prevents all controlled actions | Real typed Gleam-to-native fixture must execute; static codec success is insufficient |
| Provided unsafe | Trailing frames, changed request or wrong worker bypass intent | Strict envelope/EOF, exact request hash and executable pin; corresponding negative tests |
| Wrong timing | Schema upgrade or clock sampled before lock changes effect context | NO_CREATE/exact-v7/no-DDL opener; existing lock-before-clock oracle retained |
| Duration | Hashing/child outlives request; uncertain result triggers another effect | Shared monotonic deadline, finite guardian, no blind retry, exact read-only reconciliation |

## FMEA (analyst estimates, not calibrated probabilities)

| Failure | S | O | D | RPN | Mitigation / residual |
|---|---:|---:|---:|---:|---|
| Wrong database or unauthenticated effect | 9 | 3 | 3 | 81 | Protected caller configuration and genuine trust/fences remain mandatory before live; tests use isolated DBs |
| Multiple/truncated requests | 8 | 3 | 2 | 48 | Exact frame/EOF, closed envelope and native mutation falsifiers |
| Implicit database creation/migration | 8 | 3 | 2 | 48 | NO_CREATE/exact-v7 opener and empty/missing/old/future tests |
| Binary size refusal | 5 | 8 | 2 | 80 | Measured39MB binary, finite64MiB ceiling and per-chunk deadline; upper-bound regression |
| Ambiguous outcome after effect | 9 | 4 | 3 | 108 | Historical exact lookup exists; durable client request/reply integration still pending |
| Misleading lease-cancel success | 8 | 3 | 2 | 48 | Fixed receipt says task_cancelled=false/process_quiesced=false |

## Verification and remaining obligations

12 native suites pass with6 existing raw CLI invocations,6 framed-worker invocations and4 actual typed Gleam transport calls. Three native mutants killed (trailing frame, file creation, duplicate operation), none surviving/void. Transport regression19/19 passes: finite deadline, process group/caller death, bad frames/output/pins and64MiB upper bound. New-candidate full Telegram acceptance and signed-fixture-to-outbox delivery are not established by this increment. Native test harness requires explicit isolated transport and Gleam fixture directories; missing fixtures fail closed. Independent review must bind the frozen candidate and current evidence.

Remaining entire goal: all77command routes,14MiniApp pages including13backend gaps,seven media types,nine families,browser/live acceptance, permitted provider access, independent release/global admission and stabilized JJ integration. Runtime61/71 andrelease25/33 unchanged. EV>93 NOT_ADMITTED.

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
