# 20261024-1930 Telegram native cancellation safety delta

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

COMMAND_IMPL7 development scope: bounded native command and historical receipt recovery. This is not authenticated Telegram ingress or production activation.

## Behavior and boundaries

Existing Sa-plan CLI gains job cancel-once and job cancellation-result. Both consume at most8192 UTF-8 bytes from stdin with one exact13-field request object; no caller-provided clock, file path or approval flag. Decode occurs before opening the store, and both require an existing database. The supervising Gleam adapter must supply a protected database and pinned executable, authenticated approval/identity, current host/boot admission and finite process lifetime. The local native API itself does not establish those authorities.

Cancel uses existing exact-attempt CAS and durable receipt within one transaction. The native entry acquires BEGIN IMMEDIATE before observing host time: SQLite can wait5000ms for a lock, and pre-wait expiry checks are stale. Response validation occurs before the outer transaction commits. Exceptions and failed response checks roll back.

Historical lookup requires the full exact original request, validates the stored request hash and fixed result under canonical mapping, and may operate after the original controller lease/approval expiry. It never mutates jobs, renews an approval, retries an effect, or reports current worker liveness. Missing receipt returns found=false; recorded receipts are explicitly historical with process_quiesced=false and task_cancelled=false. Protected caller authorization is still required before exposing lookup externally.

## STPA and FMEA

| UCA | Hazard | Constraint |
|---|---|---|
| Not provided | Timeout hides a completed effect | Read-only exact historical lookup; absence is not success |
| Provided unsafe | Changed request reads another effect or native data is treated as approval | Exact original hash/result binding; private trusted adapter boundary |
| Wrong timing | Lock wait carries stale approval time into write | Acquire transaction before native observation; expiry-during-contention test |
| Duration | Retry repeats action or lookup extends authority | Idempotent cancellation; historical mode never dispatches effect |

Raw FMEA analyst estimates1–5: stale time after lock wait S5/O3/D3=45; substituted historical request S5/O3/D3=45; native endpoint exposed without authenticated ingress S5/O3/D3=45; misleading process-stop result S5/O3/D3=45. Component tests do not establish reduced production risk or admission.

## Evidence and residuals

12/12 native offload suites pass, including real child CLI against isolated SQLite, request rejection before DB creation, replay, lookup, and contention. Three intentional mutations (historical hash bypass, unknown fields, clock before lock) are killed; two initial unused-binding compile-void mutants are preserved and not counted. Actual AGY1ec874c2 protocol source adapted to actual store fields; redundant custom UTF-8 implementation removed. Full trusted Gleam execution, protected signer configuration, receipt ingress/outbox, dual-clock admission, actual quiescence where required and live Telegram remain open.

[Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md) · [Dashboard](http://nas-1.tail55d152.ts.net:4100/static/20261024-0712-recovery-dashboard.html)

## Comprehensive verification checklist

Checks below are obligations, not blanket passing claims.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [ ] **CHK-01-TIME** — Observe synchronized clock evidence and document prefix.
- [ ] **CHK-02-TAIL** — Verify full Tailnet links and actual serving status.
- [ ] **CHK-03-FRACT** — Verify L0–L9 tags and applicable layer mapping.
- [ ] **CHK-04-KM** — Reconcile specification, wiki, ZK and journal links.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [ ] **CHK-05-MUDA** — Verify exclusions against the candidate dependencies.
- [ ] **CHK-06-GRAPH** — Verify the pure BEAM/Hermes graph boundary.
- [ ] **CHK-07-DRIVE** — Preserve the denied OS serial and test real interlocks only in scope.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] **CHK-08-C1C8** — Verify all applicable C1–C8 surfaces.
- [ ] **CHK-09-MATH** — Measure the four declared mathematical gates.
- [ ] **CHK-10-9MOD** — Apply relevant unit, system, TDD, BDD, performance, scalability, property, fuzz and chaos checks.
- [ ] **CHK-11-REGR** — Run applicable regressions and bounded observation.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] **CHK-12-GLEAM** — Observe actual OTP control/supervision behavior.
- [ ] **CHK-13-HERMES** — Observe bounded analysis and authoritative evidence.
- [ ] **CHK-14-ZIGVM** — Verify deterministic execution and descriptor-relative VFS.
- [ ] **CHK-15-MAX** — Observe actual isolated inference when applicable.
- [ ] **CHK-16-OTEL** — Verify clock and nonzero trace/span identity.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — Obtain candidate-bound independent review and authorized admission.
- [ ] **CHK-18-JJ** — Preserve standalone JJ, source ownership and exact candidate identity.

</details>

<details>
<summary>Domain 6 — Provenance extension</summary>

EV ceiling remains 93. EV-94..109 remain NOT_ADMITTED. No new EV number is minted.

</details>

[Previous: formal specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260909-0412-gleam-harness-symbiosis-formal-spec.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/)

UOS footer: document and component evidence do not grant system admission.
