# 20261025-0203 — Mini App local Podman observations

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md)

Scope: actual local container and image inventory. Container start/stop, remote fleet control and other Mini App actions remain separate incomplete obligations. No production activation is authorized by this document.

The original adapter interpolates shell strings and silently filters malformed container rows. This Mini adapter instead has a typed three-value Query and fixed argv templates. Every command uses --remote=false and the fixed /usr/bin/podman executable pinned by the server-owned UOS_TELEGRAM_MINI_PODMAN_SHA256 value. Telegram supplies neither argv, template, path nor digest. No command, labels, environment variables, mounts or credentials are requested from Podman output.

The existing guardian checks executable bytes and owns cleanup. Each query is limited to1500ms and32768bytes; all three share a4000ms monotonic deadline with continuity checked between queries. Nonzero exit, unknown cleanup, malformed JSON, duplicate IDs, invalid states and exhausted bounds refuse. An empty list is reported only after successful container, image and info reads. The existing Mini auth and5second post-read boundary remain intact.

Up to128containers/image references parse per bounded response;40of each are shown with explicit counts under100fields. Rootless/rootful scope and local service-account inventory are explicit. A running container is not declared application-healthy. Arbitrary container fields remain plain text through the existing browser renderer.

| UCA | Constraint and falsifier |
|---|---|
| Missing inventory | Actual empty response must differ from unavailable reader |
| Unsafe inventory/control | Fixed read-only verbs and pinned executable; wrong user/hash must expose no fields |
| Wrong timing | Monotonic continuity and overall deadline; stale identity rechecked |
| Excessive duration | Native guardian per-call limits and shared4second budget |

Raw analyst FMEA1–5: false empty inventory S3/O3/D3 RPN27; unauthorized exposure S4/O2/D3 RPN24; unbounded process S3/O2/D2 RPN12. Cooperative host configuration and executable provisioning remain release obligations.

Acceptance includes independent pure projection/deadline tests, authenticated HTTP and mobile Chromium, wrong hash/identity refusal, and one disposable local container. The state-change driver uses only cached image sha256:925ff61909aebae4bcc9bc04bb96a8bd15cd2271f13159fe95ce4338824531dd with --pull=never, network none, read-only filesystem, dropped capabilities, no-new-privileges,16PIDs and32MiB memory. It targets only its random-label/exact-ID container, executes /bin/true, removes that container without force, and verifies existing inventory is unchanged. No existing container is stopped or removed. These are private development tests, not admitted production controls.

Observed 2026-10-25T02:02:44.165Z.

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
