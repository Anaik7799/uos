# 20261025-0241 — Reviewed expired-claim recovery

Observed 2026-10-25T02:40:15.953Z. #fractal-l0 #fractal-l3 #fractal-l9 #zk-adr #zero-muda

[Telegram completion plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md)

Scope: explicit --reclaim-preflight-reviewed composes the existing exact expired-owner projection and independently reviewed top equal-risk choice. This is read-only evidence; Sa-plan claim and active/effect-time checks remain necessary. Ordinary modes retain their prior behavior. Active and reclaim-set review combinations remain unavailable.

RC-01: task, worker, attempt and previous deadline exactly match an expired executing live task and its original assessment owner before review. RC-02: review digest binds original portfolio bytes, while the tie group is computed from the validated projection. RC-03: only exact top-group tie findings may be discharged; every source, clock, ownership, dependency and unrelated finding remains. RC-04: live snapshot, source and review bytes and expiry are rechecked at completion. RC-05: no state, score or lease is changed by this checker.

RCA: accepted selection mode explicitly rejected reclaim mode, while expired reclaim projection reproduced the unresolved tie. Both mechanisms existed but were not composable; fresh heartbeat alone could not repair the expired Sa-plan attempt. Alternatives rejected: inflate scores, edit database state, reuse expired review.

STPA: omitted recovery starves Telegram work; unsafe recovery permits duplicate owners; late review uses stale portfolio; overly long review survives evidence validity. Controls: exact existing claim matching, original-byte proof, top-group-only selection, final freshness and separate current effect fences. FMEA estimates on 1–5 scales: stale-owner effects S4 O3 D3 RPN36; evidence substitution S4 O3 D2 RPN24; starvation S3 O4 D1 RPN12. Residual risks: privileged local actors can rewrite unsigned evidence, and observation-to-claim races require authoritative Sa-plan compare-and-set. No cryptographic reviewer identity or global admission is claimed.

Validation: 12 added composition checks, 49 total selection checks, 375 baseline checks, 32953 adversarial checks (including 32768 DAG scenarios). Actual reviewed reclaim CLI and fresh claim/active observations must pass before recovery is accepted. These are bounded executable contracts, not unbounded proof.

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
