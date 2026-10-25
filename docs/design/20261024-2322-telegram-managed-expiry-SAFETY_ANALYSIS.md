# 20261024-2322 Managed Telegram restart with expired approvals

Observed 2026-10-24T23:21:59.482Z. #fractal-l0 #fractal-l1 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md) · [Dashboard](http://nas-1.tail55d152.ts.net:4100/static/20261024-0712-recovery-dashboard.html)

## Acceptance scope

The existing managed successor fixture now additionally carries an original pending cancellation request and three authentic independent approval receipts across termination of a real transient systemd service and startup of its fenced successor. Signature verification succeeds at the historical signing time and fails at the current time. The roster, bridge lease and intent are expired before the restart; their bytes are retained.

The successor runs with the explicitly historical recovery profile under current canonical task/runtime authority. Wrong predecessor control and duplicate startup refuse. A new proposal request receives the recovery-only refusal; the requester can then withdraw the old request. Two actual local HTTP replies are delivered; the original is terminal, its proposal and profile bytes unchanged, and no original authority/cancellation row exists. The successor releases runtime authority and whole-unit cleanup is verified.

This proves the expired pending-approval path through real managed service replacement. It does not prove recovery of a committed native cancellation under a rotated production profile, machine reboot, or live Telegram delivery. Existing native history tests remain separate. No fresh intent, roster or lease is minted for the historical request.

## Changes and risk

Only test fixture code changes: reuse the existing signed profile/receipt builders; add a test-only historical-profile option to the worker runner; extend managed successor parameters; add one scenario. The default runner path and production service code are unchanged. The helper uses fixture keys and pinned development native transport. It creates no production recipient or execution authority.

| UCA | Risk | S/O/D; RPN | Check |
|---|---|---|---|
| Not provided | Restart leaves pending requests unusable | 6/4/4;96 | Actual requester withdrawal and HTTP delivery after successor startup |
| Incorrectly provided | Expired signatures cause a new effect | 10/3/6;180 | Historical/current cryptographic verification contrast; no authority/cancellation row after dispatch |
| Wrong timing/order | Successor starts before predecessor is stopped | 10/3/6;180 | Whole-unit cleanup receipt and wrong-predecessor refusal in existing fixture |
| Too long/repeated | Restart renews approval or repeats start | 10/3/6;180 | Exact proposal/profile preservation and duplicate-start refusal |

FMEA values are engineering estimates. Criticality Critical. Current COMMAND_IMPL attempt11 and source/workspace fences apply. Initial focused scenario passed in5.682seconds; final frozen-candidate regression and independent review receipts govern acceptance. No new EV number or system admission.

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
