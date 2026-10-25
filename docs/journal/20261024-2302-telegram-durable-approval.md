# 20261024-2302 Telegram durable approval commands

Observed 2026-10-24T23:01:56.205Z. #fractal-l0 #fractal-l1 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md) · [Checkpoint](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20261024-2302-telegram-durable-approval-checkpoint.json) · [Dashboard](http://nas-1.tail55d152.ts.net:4100/static/20261024-0712-recovery-dashboard.html)

## 1. Scope & Trigger

Complete the Telegram approval workflow under COMMAND_IMPL attempt11. Parent76fadebe supplied current target/proposal data and scoped status. Candidate ef2db89df99ee67632d531f2bff4d4cf88273ebd connects durable proposals, partial signature collection and real propose/submit commands to the existing guarded native execution path. The overall Telegram, browser, release and main goal remains active.

## 2. Pre-State Assessment

Proposals were ephemeral and /approval only read status. Missing collection meant a user could not complete the signature workflow through Telegram commands. Runtime61/71 and release25/33 tasks complete; no feature percentage inferred. Prior forecast p=.55 by23:10 for durable proposal acceptance plus an identity/restart falsifier remains subject to the candidate review result. No Kalman filter state was computed.

## 3. Execution Detail

AGY Gemini4ArgonHigh3ddf99d4 authored the partial validation API and cryptographic tests. Codex implemented the bounded proposal codec, exact pending-input CAS store, actor messages, proposal/submission service routes and shared prepared execution path. Reused existing full quorum verifier and native cancellation history. Actual staged HTTP test exercises recovery-only refusal, foreign-user refusal, signing challenge, invalid receipt, three valid receipt acknowledgements and one final cancellation reply. Dedicated review result is bound in the checkpoint. Initial AGY cbf521f0 review HOLD identified submit-before-propose and bad-target input errors that incorrectly held the service. Corrected candidate separates missing data from changed generation and converts only explicit input refusals into replies. The final staged flow includes both regressions and then succeeds. Independent closure AGY c3a790af PASS, no findings,29.44seconds.

## 4. Root Cause Analysis

ACH H1: absent durable proposal/receipt plumbing prevented the already verified cancellation core from being usable through chat; the complete staged flow now reaches native cancellation and one final reply. H2: valid command whitespace should be rejected at persistence; disconfirmed by canonical typed parsing, leading to one shared command matcher and a positive execution-persistence test. H3: the first multi-message failure was an effect defect; bounded child expiry at6.5seconds identified a fixture-budget mismatch, and the20second bounded flow passes without changing production limits. Exact scheduling variation is not inferred. H4: missing proposal and generation mismatch are interchangeable; disconfirmed by the reviewer and new tests. Missing data is a normal input-order error, while a changed canonical generation remains a hold.

## 5. Fix Taxonomy

Poka-Yoke: opaque data codec, exact request and roster binding, immutable intent/nonce, monotonic receipt prefix, unique roles and bounded input. Jidoka: partial/invalid/stale approval cannot create executable Verified evidence; uncertain commits preserve existing PendingOperation containment. Muda: no scheduler, daemon, dependency or duplicate effect engine. Existing native transaction, signature helpers, actor and outbox reused.

## 6. Patterns & Anti-Patterns Discovered

Devil's Advocate: replacing the proposal-monotonicity predicate must let an existing receipt be overwritten, and removing the partial unique-role precheck must admit duplicates. Both faults are killed by named tests and original bytes restored. A bad test removed all action configuration and thereby let the ordinary unconfigured-tool route consume the pending original; use recovery-only mode when testing rejection of new approvals while retaining the original request. Missing production configuration and invalid signatures get truthful replies rather than unnecessary whole-service holds.

## 7. Verification Matrix

Scoped Admiralty B2 evidence:126focused Gleam checks on frozen candidate;12native suites0failed/0skipped,12reaped/0residual,11optional telemetry observations absent;13service/native scenarios included in those suites. Full restored native run40.2seconds. Multi-message flow delivers10actual local HTTP replies, including missing-proposal and invalid-target refusals and one final action result; repeated dispatch returns0processed/0delivered. Two mutation cases killed,0survived/void, sources restored. Exact bytes and157canonical source pairs are recorded in manifest. This is neither live Telegram acceptance nor all mathematical/seven-engine verification.

## 8. Files Modified

Thirteen files in the frozen candidate: new proposal module; approval, cancellation-record, ingress, service, store and tool-help modules; four Gleam test modules; native lease test; timestamped safety/operational document. Manifest1279files,123untraversed symlinks,157sourcepairs. Existing native worker SHA b800eff783cf78a643f39f3445f73a8068cae5ed4bd7047c272070cfabc1fdc0 reused. Empty child7063c8e0 for subsequent work; no main mutation.

## 9. Architectural Observations

Proposal persistence and partial validation are data operations; only the unchanged full quorum verifier produces opaque execution evidence. Query-user identity is checked against the original request before challenge or receipt handling. Full execution shares the established current-authority/clock/native-fence and cancellation-history code. Fresh native-worker reopen tests demonstrate stored-byte durability, not full managed service replacement. Category/sheaf consistency is an architectural observation, not a new formal proof.

## 10. Remaining Gaps

Explicit proposal rejection/abandonment and stale-request lifecycle; full managed restart across expired historical profiles; remaining command backends;13MiniAppbackends and browser acceptance;sevenmedia types;gateway;provider access;authorized live Telegram;independent release/global admission and stable applicable main integration. Production signer configuration and enrollment are not established by ephemeral test keys.

## 11. Metrics Summary

126scoped checks,12native suites,13included service scenarios,10HTTP replies in the complete command-flow case,2killed mutations. Runtime61/71 and release25/33 remain unchanged because COMMAND_IMPL is open. Dashboard producer23 independently reviewed under OBSERVE20 and observed fresh, expires23:34:57.119UTC. No calibrated Bayesian reliability, Kalman improvement or Lyapunov dV/dt result is claimed. Prior durable-proposal forecast p=.55 for23:10 achieved before horizon; Brier=.2025, one event only.

## 12. STAMP & Constitutional Alignment

All four UCA classes and raw FMEA are in20261024-2253 safety analysis. User scope, immutable intent, roster and quorum constraints prevent wrong effect provision; current clock and canonical fence checks constrain timing; original expiry and history protect against repetition. Gleam/Sa-plan/coordinator authority and independent release requirements remain intact. EV94–EV109 remain NOT_ADMITTED; no new EV number.

## 13. Conclusion

This increment makes the development approval-command path usable with a trusted configured roster and independent signed receipts. Full Telegram readiness remains unproven. Forecast p=.55,Horizon2026-10-24T23:25:00Z: explicit proposal abandonment or managed restart acceptance obtains positive and refusal evidence. Brier score will be (0.55-outcome)^2 at that horizon; this uncalibrated forecast is not a delivery guarantee.

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


[Previous](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261024-2059-telegram-current-task-bridge.md) · [Next: completion plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md)

UOS footer: scoped component evidence is not admission.
