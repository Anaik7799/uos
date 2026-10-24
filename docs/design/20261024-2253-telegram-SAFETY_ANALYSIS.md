# 20261024-2253 Telegram durable approval workflow

Observed 2026-10-24T22:52:22.959Z. #fractal-l0 #fractal-l1 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md) · [Dashboard](http://nas-1.tail55d152.ts.net:4100/static/20261024-0712-recovery-dashboard.html)

## User flow and scope

This development flow uses an already configured trusted action profile and signer roster. Test keys are isolated fixtures; production signer enrollment and live recipient acceptance are separate release obligations.

1. Send /tool cancel_job_lease <job_id> -- <reason>. Only the configured plan can be targeted.
2. Use /approval list to find the request identifier.
3. Send /approval propose <request_id>. The reply contains the exact canonical intent, its digest and the trusted roster digest. Repeating this command returns the original proposal bytes and nonce.
4. Independent roster signers review that exact intent and supply their signed receipts. Submit each with /approval submit <request_id> <role> <signed_receipt>.
5. Operator plus two sovereign approvals are required. Partial receipts are data only. The next dispatch verifies full quorum, current task/coordinator/profile/bridge/target fences, persists cancellation history, invokes the native guarded operation and delivers the precise result.
6. Expired proposals are never renewed. Send a new /tool request if still needed. Invalid, foreign-user and unconfigured submissions receive truthful refusal; those input errors do not halt the service.

The command revokes the exact native job lease; it does not claim worker-process termination. The current staged test delivers eight real local HTTP replies: recovery-only refusal, foreign-user refusal, challenge, invalid-receipt refusal, three receipt acknowledgements and one action result. Repeated dispatch sends no extra result. This is not a live Telegram account test.

## STPA and raw FMEA

| UCA type | Hazard | Constraint |
|---|---|---|
| Not provided | Pending request cannot collect approvals or user cannot discover challenge | Existing /approval status plus bounded propose/submit routes and durable reply path |
| Incorrectly provided | Foreign request read, forged signature or replaced intent | Exact stored input/recipient binding; trusted roster; immutable intent and monotonic receipt sequence |
| Wrong timing/order | Approval expires or target changes between collection and effect | Collection validates current intent/roster; execution rechecks full quorum, measured time and canonical effect fences |
| Too long/repeated | Restart renews approvals or repeats uncertain effect | Original nonce/intent persisted, no expiry extension, existing cancellation history and lookup-only recovery |

Engineering FMEA estimates, not incident frequencies:

| Failure | S | O | D | RPN | Mitigation / residual |
|---|---:|---:|---:|---:|---|
| Proposal substitution | 10 | 3 | 6 | 180 | Original canonical intent and roster digest immutable; replacement mutation killed |
| Duplicate role counted twice | 10 | 3 | 5 | 150 | Unique-role partial validation and unchanged full quorum verifier; duplicate-check mutation killed |
| Uncertain proposal commit | 8 | 3 | 5 | 120 | Existing generation/read-set CAS and PendingOperation containment; no new retry mechanism |
| Unauthorized challenge disclosure | 8 | 3 | 5 | 120 | Original bot/chat/user comparison before proposal lookup or mutation |
| Malformed/unconfigured command disrupts service | 6 | 4 | 4 | 96 | Bounded refusal reply; actual staged flow continues afterwards |
| Development evidence mistaken for live completion | 8 | 4 | 6 | 192 | Explicit fixture scope; remaining acceptance and release gates stay open |

Authority and dependency readiness precede C5*T5*F5*Dep5*I5=3125 (engineering interval2000..3125). COMMAND_IMPL attempt11 and current coordinator/workspace fences remain mandatory. No score or review grants production effect authority.

## Implementation and evidence

Gleam owns proposal codec, partial cryptographic verification, current service policy, actor-dispatched persistence and command routes. Existing native storage remains a bounded transactional data adapter. Proposal data occupies its own key namespace and cannot reconstruct executable approval authority. The full verifier still creates the opaque Verified value only for complete valid quorum.

126focused Gleam checks pass. Native full suite passes12groups with13actual service scenarios, including the multi-message flow; final restored run receipt is bound in the checkpoint. Two fault injections are killed, source restored and rebuilt. Native worker bytes are reused from the accepted exact-target candidate. Read-after-reopen tests invoke fresh native processes on the same SQLite store; full managed service replacement across expired profiles remains pending.

Preserved failures: an early whitespace test used an invalid delimiter and was corrected to the existing accepted grammar; the actual storage/execution whitespace mismatch was fixed by shared typed cancellation parsing with an added positive test. The longer multi-message fixture exceeded its original6.5second child bound; only that test child now has20seconds, with the same termination/reaping path. All other children remain6.5seconds and production deadlines are unchanged. An optional-argument OCaml compile error and an ingress type-name compile error were corrected; no failing evidence was discarded. A test temporarily removed all action configuration, allowing the pre-existing ordinary unconfigured-tool reply to consume the original request before the approval query; corrected the fixture to trusted recovery-only mode so the original remains pending while new approvals are refused.

## Remaining obligations

Explicit proposal rejection/abandonment lifecycle and managed restart acceptance across expired profiles; other command adapters;13MiniAppbackends and browser acceptance;sevenmedia types;gateway;provider availability;authorized live Telegram flow;independent release/global admission and applicable main integration. No new EV identifier. No new scheduler or daemon.

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
