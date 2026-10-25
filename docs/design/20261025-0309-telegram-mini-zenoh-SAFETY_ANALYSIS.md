# 20261025-0309 — Telegram Zenoh topic browser contract

Observed 2026-10-25T03:08:46.791Z

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/)

Candidate 103ebc28b3ec04655440618926a9f97739ad9940, parent feature73c17a91. This is a bounded development read capability; publishing, native subscriptions and release admission remain pending.

## Configuration and behavior

UOS_TELEGRAM_MINI_ZENOH_GRANTS is a server-owned JSON array of {user_id, topic} records. The existing bot token and Mini identities remain mandatory. Grant data is limited to65536bytes,1..256unique pairs,positive safe-integer users,20topics peruser. Keys are exact ASCII<=512bytes without wildcards, traversal, query strings or emptysegments. Missing or malformed configuration yields unavailable. An authenticated user without a matching grant receives403 before any Zenoh query. Listing uses only server grants and makes no network call.

Selected topics are read through the existing fixed Tailnet REST endpoint http://nas-1.tail55d152.ts.net:8080 with3second transport budget. A successful response must contain exactly one sample for the exact key; ambiguous, wrong-key, malformed or unsupported encodings fail. An empty envelope means No retained reply, distinct from transportfailure. Text payloads<=32768bytes are preserved in ordered<=2048byte Unicodecodepoint chunks and rendered as literal DOMtext; controlcharacters exceptTAB/LF/CR fail. The existing API rechecks identityfreshness and bounded read duration after observation.

Start live refresh polls only the selected granted key, one request at a time, after a2second completion delay, for at most5minutes. Manual refresh replaces any pending timer. Manualstop, topicchange, authenticationfailure, unavailable/networkresponse, hiddenpage or pagehide stop futurepolls. Returning to a page does not resume polling automatically. An in-flight read may finish after manualstop; it cannot schedule another poll. Polling can miss transient publications and is not native pubsub.

## Acceptance and residual risks

The executable specification is mini_zenoh_test and zenoh_rest_test plus actualHTTP/Chromium acceptance in the candidate builder.63unit,55HTTP,9Chromium scenarios and1retainedstate change are source-bound;128distinct checks, not a fullsystemproof. HTTPfixtures use synthetic Telegram initData. Actual7047byte Unicode/message change was confined to a newly created fixture namespace under existing uos/tui storage; no sharedkey deleted and no routerconfiguration changed.

Raw FMEA1–5: unauthorizedtopic S4/O2/D3 RPN24; deceptiveempty-success S3/O3/D3 RPN27; duplicatepolltimer S2/O3/D2 RPN12; payloadloss S2/O3/D2 RPN12. Controls are exactservergrants, strictdecoder, failurestates, timerreplacement, bytebounds and literalrendering. SameUIDlauncher integrity and trusted fixedrouter remain boundaries; no cryptographic grantrevocation or persistentnative subscription is claimed.

STPA UCA providedunsafe: refuse unauthorizedtopics beforequery. Notprovided: failure remainsvisible and recoveryis tested. Wrongtiming/order: generationtokens suppress old responses afterselectionchange and auth is rechecked. Too long/short: finitepoll budget, boundedtransport, no silent payloadtruncation. Formal Lean/Gospel execution and calibrated probabilities remain UNRUN; test contracts do not establish globaladmission.

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



[Previous](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261025-0230-telegram-mini-history.md) · [Next](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md)

UOS footer: component evidence is not admission.
