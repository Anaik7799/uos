# 20261025-0141 — Mini App recorded evidence adapters

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md) · [Dashboard](http://nas-1.tail55d152.ts.net:4100/static/20261024-0712-recovery-dashboard.html)

Scope: authenticated read-only FMEA and candidate verification display in the existing Mini App. These are two backend slices, not full Mini App completion or admission. Actual build/test/review results are recorded separately.

Configuration is server-owned. FMEA requires UOS_TELEGRAM_MINI_FMEA_SOURCE and UOS_TELEGRAM_MINI_FMEA_PLAN. Verification requires UOS_TELEGRAM_MINI_VERIFICATION_SOURCE, UOS_TELEGRAM_MINI_VERIFICATION_SHA256 and UOS_TELEGRAM_MINI_VERIFICATION_CANDIDATE. Sources must be regular files under canonical governance/planning, without symlink ancestors. No browser-supplied path or candidate controls the read.

The unchanged signed identity, allowlist, body bounds and post-observation expiry checks run before data is returned. Each reader uses the existing hash-bound isolated Erlang worker under the native guardian, with a 3-second limit and 32768-byte output cap. Existing API checks the 5-second wall-clock observation budget afterward. These are development components, not a production rollout.

FMEA displays at most five assessments and the three highest-RPN modes of each, with explicit shown/total counts. It labels S/O/Det/RPN as engineering estimates, not measured failure rates. The candidate checklist shows all18 checkpoints and preserves RECORDED/STALE/UNKNOWN states. It never verifies referenced evidence bytes or executes a gate. Record age remains separate from response fetch time.

| Unsafe control action | Mitigation | Acceptance falsifier |
|---|---|---|
| Required evidence omitted | Explicit counts, omitted modes, UNKNOWN checkpoints | Missing source must yield unavailable, not green defaults |
| Unsafe evidence supplied | Fixed source configuration, candidate/hash binding, observation-only envelope | Wrong candidate/hash/admission flag must refuse |
| Evidence shown at wrong time | Transport age <=30seconds and existing signed identity recheck; record age retained | Stale record must never become RECORDED_PASS |
| Access persists too long | Existing signature maxage300seconds and bounded reader lifetime | Expired signature or backend timeout must not expose fields |

Raw FMEA1–5: misleading stale evidence S4/O3/D3 RPN36; unauthorized read S4/O2/D3 RPN24; backend blockage S3/O2/D2 RPN12. These are analyst estimates. Residuals: local operator controls configured source and assessment content; readers verify file identity and envelope, not truth of all upstream claims. FMEA summary intentionally omits lower-ranked detail with explicit counts; full page interactions and other backends remain open.

Observed RCA during private HTTP: a1ns lease was displayed active because the previous Tasks adapter rounded time to seconds. The adapter now compares nanoseconds, with before/equal/after boundary tests. Large dictionary iteration also scattered FMEA details; the API now explicitly sorts fields with scope/limitations before assessment/checkpoint detail. Unavailable messages describe missing or failed sources without claiming every failure means unimplemented.

Verification plan: retain baseline8 boundary tests; add independent projection tests from actual report generators, authenticated HTTP positive/denial/missing-source and hash-mismatch cases, real desktop/mobile Chromium navigation and screenshot inspection. Synthetic Telegram SDK credentials are private fixture evidence, not live Telegram acceptance. No external send, package provisioning, global admission or main mutation.

Observed 2026-10-25T01:41:19.903Z.

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
