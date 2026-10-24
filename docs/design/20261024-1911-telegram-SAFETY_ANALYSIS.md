# 20261024-1911 Telegram authenticated approval safety delta

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

Scope: COMMAND_IMPL7; cryptographic evidence only. Runtime dispatch and production activation remain separate.

## Required behavior

Reuse the unchanged bounded Ed25519 JWS verifier. An opaque configured roster pins independent public keys and identities to Codex, AGY, Claude and operator roles. At least two sovereign keys plus the operator key must exist; an unconfigured third sovereign cannot vote. Any present invalid, duplicate, conflicting or rejecting receipt rejects the entire bundle. Two distinct configured sovereign approvals and separate operator assent are required. Claims bind the exact intent, logical effect and roster digest; receipt windows are explicit milliseconds within the intent lifetime. No secrets or raw tokens enter evidence summaries.

AGY design28c18660 independently advised the bounded design. Its four-key constructor is adapted to permit an unavailable third sovereign while preserving two-of-three plus operator; no unknown role or key may vote. Trusted roster construction is data validation, not proof of protected provisioning. Future runtime must obtain it from an operator-protected source, never Telegram payloads or worker-writable files. No live keys or authentic operational signatures are fabricated.

## STPA and FMEA

| UCA | Hazard | Constraint |
|---|---|---|
| Not provided | Required stop unavailable | Truthful unavailable state; retain completion obligation |
| Provided unsafe | Forged approval or one key counts twice | Real signatures, role/key/subject uniqueness, exact request and roster binding |
| Wrong timing | Late approval survives changed attempt or boot | Receipt window, dual-clock intent checks, canonical executor fence remains required |
| Duration | Bundle reused after expiry or rotation | Opaque evidence recheck against current roster/request; persistent one-effect store still required |

Raw analyst FMEA scores on1–5 scale: forged identity S5/O3/D3=45; stale or substituted request S5/O3/D3=45; tokens retained in logs S4/O2/D3=24; false process-stop claim S5/O3/D3=45. Cryptographic tests reduce uncertainty about verification only; no production risk score reduction or admission inferred.

## Acceptance and residuals

Real ephemeral signed fixtures must accept every valid sovereign pair plus operator and reject each binding/time/key/schema change. Production keys must never be used in test fixtures. The existing cancellation primitive revokes a job lease only. Trusted configuration, real signer ingress, current canonical fences, persistence and Telegram routing remain required before end-to-end completion.

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
