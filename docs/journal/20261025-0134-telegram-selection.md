# 20261025-0134 — Reviewed Telegram task selection

Observed 2026-10-25T01:34:31.742Z. #fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Checkpoint](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20261025-0134-telegram-selection-checkpoint.json) · [Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md)

## 1. Scope & Trigger

Repair the concrete equal-risk selection blocker under SELECTION_REPAIR1 so dependency-ready Telegram Mini App work can proceed. Frozen candidate8cf461c4; no admission.

## 2. Pre-State Assessment

COMMAND_IMPL and MINI_API_IMPL both eligible at768. Ordinary preflight held on RP-COST-TIE/RP-SELECTION. SOP allowed reviewed cost/benefit decisions but checker lacked an explicit input. Kalman state is unmeasured.

## 3. Execution Detail

Add --preflight-reviewed with exact portfolio hash, top eligible tie group, bounded next-packet cost comparisons, expiry and separately reviewed proposal hash. Original audit runs first; only the exact top-group tie finding is removed. All other findings, source rereads and Sa-plan authority remain. Actual reviewed preflight passed; MINI_API_IMPL1 claimed and accepted baseline rebuilt,8tests passed.

## 4. Root Cause Analysis

ACH H1 artificial priorities needed: disconfirmed by successful reviewed equal-score selection. H2 missing policy input: supported by ordinary HOLD versus reviewed PASS on the same portfolio. H3 reviewer proof authenticates identity cryptographically: false; this remains a cooperative account boundary. Initial conversation-ID binding was circular; Codex rejected earlier AGY PASS and corrected to a stable reviewed label with exact proposal hash.

## 5. Fix Taxonomy

Poka-Yoke: strict schema, exact task set and hash, expiry and byte rereads. Jidoka: unrelated findings and wrong requested task still refuse. Muda: reuse the existing checker and Sa-plan; no additional scheduler.

## 6. Patterns & Anti-Patterns Discovered

Devil's Advocate: independent review is evidence, not automatic acceptance: Codex found a circular-identity flaw after AGY PASS. Top-group-only handling prevents this mechanism from selecting lower-priority work or clearing other holds.

## 7. Verification Matrix

Admiralty B2 scoped observations:37targeted checks,375baseline checks,32953adversarial checks including32768DAG scenarios. Warning-free isolated build;14source/config hashes match. Corrected source review f8a94d82 PASS. Actual AGY684b5df3 approved exact selection proposal; live reviewed preflight PASS, ordinary preflight and wrong-task calls HOLD. No production or global-suite claim.

## 8. Files Modified

Frozen poll-workspace candidate: reviewed_selection.ml,reviewed_selection_test.ml,validate.ml,dune and timestamped safety analysis. Reporting checkpoint, journal and critical-path projections updated separately. Main unchanged.

## 9. Architectural Observations

Bounded Hermes checking remains behind Gleam; canonical task claim stays in Sa-plan. Stable reviewer label is not authenticated identity, explicitly reported false. Model review does not grant execution authority. No new formal category/sheaf proof.

## 10. Remaining Gaps

45command routes,13Mini App backends/actions and browser acceptance,7media types plus gateway, working privacy-compliant provider, authorized live recipient, integrated release/admission and applicable main integration. MINI_API_IMPL is the active feature task.

## 11. Metrics Summary

Command coverage remains32/77=41.56%; runtime61/71 and release25/33 unchanged. Selection repair adds no Telegram feature percentage. Earlier p=.55 forecast for a new flow by01:25 failed: outcome0,Brier.3025. Bayesian/Kalman/Lyapunov quantities remain unmeasured.

## 12. STAMP & Constitutional Alignment

Four UCA modes: missing selection starves ready work; unsafe selection bypasses higher priority; wrong timing uses stale review; excessive duration reuses expired authority. Countermeasures exact top group, full audit, start/end byte and expiry checks, separate current task leases. Raw FMEA1–5: wrong selection S4/O2/D3 RPN24; liveness hold S3/O3/D2 RPN18. Residual local-account proof trust retained. EVceiling93; no Git, live send or release.

## 13. Conclusion

The concrete scheduler-input defect is repaired, independently reviewed and demonstrated in development. Mini API is now executing under valid claims. Forecast p=.65 by02:00Z: a real Mini App backend adapter is built and tested, with review/HTTP acceptance reported separately. Brier=(.65-outcome)^2 will be recorded after the horizon. This is a single uncalibrated forecast, not a delivery promise.

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
