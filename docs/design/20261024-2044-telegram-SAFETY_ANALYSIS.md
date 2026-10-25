# 20261024-2044 Telegram durable cancellation safety analysis
#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Completion plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md) · [Dashboard](http://nas-1.tail55d152.ts.net:4100/static/20261024-0712-recovery-dashboard.html)

Scope: COMMAND_IMPL8, parenta2912902. Development request persistence, restart lookup and atomic outbox integration. Protected signer/profile ingress, runtime bridge provisioning, effect-time clock/authority observation and service command routing remain pending. No live Telegram action, global admission or main merge is claimed.

## Constraints and executable contracts

- RecoveryRecord contains exact canonical intent v2, deadline, native request and request hash; no JWT or private key. Strict5-key JSON and exact28-element intent array are bounded, reconstructed through existing validation and checked against original canonical bytes and derived native request/hash.
- A restored record can build only the read-only historical lookup envelope. It cannot reconstruct an executable Prepared or approval. Existing Prepared still requires verified signatures and current supplied observations.
- Store persistence binds exact bot/chat/user/update, original inbox version/hash, processing worker/epoch, authority row, accepted input identity/hash and parsed command arguments. Coordinator epoch in the signed intent is distinct from the Telegram store processing epoch.
- Approved syntax for this operation is /tool cancel_job_lease JOB -- REASON, with /action accepted through the existing catalog alias parser. The current service still denies unimplemented mutations; this increment does not enable it.
- One immutable cancellation record per canonical bot/update request. Identical preparation returns the original record; changed deadline/context/hash refuses as collision. The atomic read set covers inbox, authority, input and cancellation row; native capacity/generation checks remain active.
- New cancellation row and receipt are allocated only by a successful bounded existing store transaction before any effect. Existing reserved result/outbox capacity is preserved. An uncertain persistence result returns the existing PendingOperation path; it does not yield a reservation or permission to execute.
- Restoring a record does not retry an effect. Historical native lookup must validate exact identities/hash/deadline/result semantics before a fixed truthful reply is atomically committed to result/outbox. Missing/rejected/malformed results remain unresolved.
- Lookup reply is scoped to job-lease revocation; worker termination is not confirmed. No caller-supplied success text or process/task cancellation claim is accepted.
- Existing store transport, native worker, signature verification and durable outbox are reused; no new queue, daemon, schema migration or production FFI.

## STPA four unsafe control action classes

| Type | Hazard | Constraint / falsifier |
|---|---|---|
| Not provided | A committed native effect loses its reply after BEAM exit | Persist exact request, restart in a fresh BEAM process, readonly lookup and atomic outbox test |
| Provided unsafe | Changed user, input, context or record authorizes a different result | Full inbox/authority/input CAS binding, strict reconstruction and collision refusal |
| Wrong timing | Stale generation/authority or expired approval is reused | Store CAS; restored records cannot create approval; live effect-time authority remains required |
| Duration | Uncertain effect repeated or false absence becomes success | No execution from RecoveryRecord; Absent/Rejected do not create a reply; fixed validated historical result |

## FMEA (uncalibrated analyst estimates)

| Failure | S | O | D | RPN | Control / residual |
|---|---:|---:|---:|---:|---|
| Lost request after committed effect | 9 | 3 | 2 | 54 | Actual isolated two-process recovery/outbox test; service wiring still pending |
| Record tamper/context collision | 9 | 3 | 2 | 54 | Strict canonical reconstruction, original request hash and atomic immutable record |
| Reply fabricated from absence | 8 | 3 | 2 | 48 | Typed historical decoder and unresolved-outcome refusal; mutation killed |
| Stale input/authority or generation | 9 | 3 | 2 | 54 | Read-set CAS and adversarial store tests |
| Test fixture mistaken for live admission | 10 | 2 | 3 | 60 | Ephemeral signers, isolated databases, no live recipient or enabled command route |

## Evidence and boundaries

83 focused Gleam checks pass:7new record/store tests,5client,17intent,18approval,22ingress and14conversation/memory-store regression. Twelve native suites pass,0failed/0skipped,12reaped/0residual; optional data-plane telemetry missing in11suites is disclosed. The native test executes a signed request, deliberately halts the first BEAM process with code77 before any reply, changes the fixture bridge fence/expiry, then launches a fresh BEAM process without signer reconstruction; exact historical lookup commits the pending outbox. This is controlled abnormal process exit, not a power-loss or live Telegram delivery test.

Four focused mutants are killed: stored hash ignored, input command binding skipped, unresolved lookup reported as success, request collision accepted. The first native test correctly refused an insecure /tmp DB parent; the fixture now uses a dedicated0700 directory. The next run exercised both restart assertions but failed cleanup due to a retained process_lock; the exact owned lock-file cleanup is repaired. Failures remain in evidence. Independent review must bind the frozen candidate and these scoped claims.

Remaining full goal: protected live signer/profile ingress, canonical bridge/runtime fencing and service routing; all77command backends,ninefamilies,14MiniApp pages/13remaining backends,sevenmedia types,gateway,browser/live acceptance,permittedprovideraccess,independent release/globaladmission and stable JJ main integration. Runtime61/71 and release25/33 unchanged. EV>93 NOT_ADMITTED.

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
