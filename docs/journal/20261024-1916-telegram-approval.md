# 20261024-1916 Telegram authenticated approval evidence

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md) · [Checkpoint](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20261024-1916-telegram-approval-checkpoint.json) · [Dashboard](http://nas-1.tail55d152.ts.net:4100/static/20261024-0712-recovery-dashboard.html)

## 1. Scope & Trigger

COMMAND_IMPL7 under the full Telegram completion goal. Implement authenticated approval evidence as a required controlled-action prerequisite, reusing existing crypto and canonical task machinery. No production activation, live signer provisioning, effect grant or new queue. Lean/Gospel gateways not invoked.

## 2. Pre-State Assessment

Parent667a8775 has tested atomic fenced job-lease cancellation; its caller authentication remains external. The existing manifest_signer computes FNV checksums, and the quorum enum/boolean dispatcher cannot authenticate a reviewer. Existing oidc_jwt_ffi already performs bounded strict Ed25519 JWS verification. Reuse that verifier instead of another cryptographic implementation. Kalman prior not measured.

## 3. Execution Detail

Actual AGY28c18660 design review completed87.48seconds and required exact millisecond windows, closed claims, independent pinned identities and no token retention. Actual AGYcd47da4b generated the verifier in134.50seconds. Codex supplied independent ephemeral signed fixtures, fixed the module import, domain-separated the roster digest, and prevented evidence recheck before its original UTC/boot observation. Independent AGY0f348899 reviewed exact candidate4b6ed682 in31.25seconds and returned PASS with residual integration risks.

## 4. Root Cause Analysis

ACH H1: existing checksum or quorum values authenticate independent approval. Counterevidence: no cryptographic signature verification or protected signer origin in those values. H2: a pinned-key signed receipt verifier and trusted ingress are missing. Existing crypto allows bounded reuse; this change closes only verifier logic. A compile failure was an unannotated test tuple helper; explicit types repaired it without changing runtime checks. Review of AGY output also found that still_valid originally permitted backward time within the broader intent window; retained verification times and falsifiers close that gap.

## 5. Fix Taxonomy

Poka-Yoke: opaque roster/evidence, unique role/key/subject/kid, exact signed11-field schema and request/effect/roster digests. Jidoka: any present malformed, rejecting, duplicate, stale or substituted receipt rejects the whole bundle. Muda: reuse unchanged Ed25519 JWS FFI, existing bounded AGY dispatcher and exact test fixtures; no new crypto package, scheduler, daemon or live keys.

## 6. Patterns & Anti-Patterns Discovered

Devil's Advocate falsification verifies all three sovereign pairs plus operator, while a third supplied rejection vetoes an otherwise adequate pair. Correct-kid wrong-private-key signatures fail. An unavailable third key cannot vote; configuration still needs two distinct sovereigns and operator. Pure caller-supplied roster validation is not evidence of protected provisioning. A verified bundle is not a canonical execution grant.

## 7. Verification Matrix

Admiralty B2 scoped evidence:58 distinct focused checks pass, including17 new signed-approval groups,13 intent cases and28 ingress/tool regressions. Tests use ephemeral per-process Ed25519 keys, never production credentials. Exact claim substitutions, duplicate JSON, hostile key headers, wrong signatures, timing, host/boot, changed attempts and roster substitution are rejected. Final compile passes. Manifest10571 files,49 canonical source matches,3 unhashed directory links. Independent review passes; full-system, live Telegram and seven-engine execution remain unrun.

## 8. Files Modified

Candidate4b6ed682aa3ba2812a717afcd3eeea6e55dcd075: new telegram_approval.gleam, receipt-window helper in telegram_action_intent.gleam, telegram_approval_test.gleam, test-only telegram_approval_test_crypto.erl, and timestamped1911 SAFETY_ANALYSIS. Existing oidc_jwt_ffi is unchanged and hash-bound in the isolated fixture. Bookmark integration/telegram-approval-20261024-1916 preserves source. Separate canonical checkpoint/journal/plan projections record progress.

## 9. Architectural Observations

Gleam owns signed-claim policy and typed evidence. Existing OTP crypto performs bounded signature verification through an unchanged adapter. No network or key lookup occurs on the verification path. Roster lifetime is bounded to one hour; receipts remain inside the intent's at-most300-second dual-clock window. Roster hash includes ordered signer configuration and its validity interval, so equivalent reordered configuration safely invalidates old receipts. No category-theoretic consistency proof is claimed.

## 10. Remaining Gaps

Protected runtime roster provisioning and actual signer ingress are not established. Trusted executor still must observe current canonical fences, map the verified intent to native atomic cancellation, reconcile durable receipts and Telegram delivery, and distinguish lease revocation from process quiescence. Other commands,13 MiniApp backends/browser tests,7 media types, gateway, actual provider completion, integrated/live acceptance, reviewed release, global admission and main integration remain. COMMAND_IMPL7 stays open.

## 11. Metrics Summary

58 distinct focused checks are not added to historical suite totals. Three actual AGY jobs completed with bounded output and candidate evidence; implementation and independent review used separate conversations. Prior forecast p=.6 for another executable required obligation by19:10 resolves true from18:54 cancellation evidence: Brier0.16 for this single observation, not calibrated Bayesian trust or a Lyapunov stability proof. The19:30 forecast remains pending.

## 12. STAMP & Constitutional Alignment

The safety delta records all four UCA types and raw FMEA scores. Missing approvals remain visibly unavailable; forged or mistimed approvals fail closed. Bound key provenance and effect-time authority remain separate obligations. No operational signer keys or peer endorsements are fabricated. Standalone JJ, canonical Sa-plan task/job ownership and EV93 ceiling are retained. No production release or main mutation.

## 13. Conclusion

Cryptographic approval evidence now has actual signed-fixture verification and independent source review. Full Telegram approval/cancellation remains incomplete until protected ingress and trusted execution are connected. Forecast p=.65, horizon2026-10-24T19:40:00Z: another required integration obligation yields executable evidence or a concrete external prerequisite; Brier pending.

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


[Previous](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261024-1754-telegram-search.md) · [Next: completion plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md)

UOS footer: scoped evidence grants no global admission.
