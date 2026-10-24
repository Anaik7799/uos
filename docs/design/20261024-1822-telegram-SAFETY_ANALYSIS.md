# Telegram controlled-action request safety delta

Observed: 2026-10-24. Scope: COMMAND_IMPL attempt 6, development only.
Tags: #fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

This delta specifies immutable request data. It grants no authority and performs no cancellation, approval, queue mutation, or process control. The existing Telegram service continues to refuse unsupported controlled actions.

## Contract and control structure

The Gleam request constructor binds the Telegram bot/chat/user/update identity, canonical plan/task/worker/attempt/epoch, candidate artifact SHA-256, host/boot domain, exact target job/worker/attempt/lease, operation, reason, nonce, and equal UTC/boot expiry intervals. Syntax validation does not authenticate any supplied value. Only the future canonical store/executor may compare this descriptor against fresh real authority.

The canonical JSON array has a fixed version and field order, with typed integers and strings. Its SHA-256 identifies the exact request. A separate stable effect identifier binds the bot/chat/user/update and operation/target across attempt changes. The future store must enforce one effect identity and refuse a different request digest for an already-recorded effect; hashing alone does not provide replay protection.

Request lifetime is at most 300 seconds. Both clock domains must be before expiry, the boot identity must match, and elapsed UTC/boot divergence cannot exceed 2000 ms. A synchronized clock observation and actual effect-time fences remain required outside this pure descriptor.

## STPA delta

Controller: future Gleam Telegram controlled-action controller. Control action: submit a cancellation request for a canonical job. Loss: unauthorized effects or misleading emergency-stop feedback. Hazard: an unverified request is interpreted as an execution grant.

| UCA type | Unsafe context | Constraint and enforcement |
|---|---|---|
| Not provided | A necessary stop remains unavailable | Report unavailable honestly; genuine supervisor quiescence remains a required executor feature. This descriptor does not close the gap. |
| Provided unsafe | A request for one identity or job is reused for another | Bind all context and exact target fields into a fixed digest; opaque constructor and mutation tests enforce descriptor integrity. Authenticated independent review and canonical execution remain pending. |
| Wrong timing | Request survives expiry, reboot, clock jump, or changed attempt | Bound both clocks and domain; exact binding/target comparison functions. Actual fresh observations must be supplied by a trusted adapter. |
| Duration | Retry consumes an approval twice or extends a stop claim | Stable logical effect identity; no state transition in this module. Atomic receipt consumption and persistent idempotency remain pending. |

## FMEA delta

Raw scores are analyst estimates on a 1–5 scale, not calibrated probabilities.

| Mode | S | O | D | RPN | Mitigation and residual |
|---|---:|---:|---:|---:|---|
| Descriptor mistaken for authority | 5 | 3 | 3 | 45 | No executor/grant API and explicit data-only contract. Application integration must still enforce authentic 2oo3/operator requirements. |
| Request substitution or ambiguous serialization | 5 | 3 | 3 | 45 | Fixed typed JSON array, exact context/target binding, independent digest vectors. SHA-256 is not a signature. |
| Late or cross-boot use | 4 | 3 | 3 | 36 | Dual-clock lifetime and exact host/boot binding. Real clock evidence and effect-time fence are outside this module. |
| Duplicate execution after retry | 5 | 3 | 3 | 45 | Stable effect identity across attempts; actual durable uniqueness and atomic consumption are unfinished. |
| Cancelled row misreported as stopped worker | 5 | 3 | 3 | 45 | No cancellation performed here. Future result must distinguish lease revocation, task cancellation, and confirmed process quiescence. |

All modes remain high priority until the actual executor is verified. No numerical reduction is claimed from descriptor tests alone.

## Reviewed plan and corrections

Actual AGY design review: b6ee7573-f853-4bd3-9bfe-f6eb4c9dc4a2. Adopt the narrow initial operation, exact binding, independent authentication, and reuse of Sa-plan. Corrections retained:
- Sa-plan currently has no awaiting_approval job state; adding one is a reviewed schema/state-machine change, not an existing capability.
- Telegram state and Sa-plan use separate stores; their outbox and job transactions cannot be assumed atomic. A durable canonical result and idempotent delivery reconciliation must bridge them.
- One independent signature does not replace the required 2oo3/operator policy.
- No blanket post-cancellation quiescence or effect-fencing guarantee exists for all workers.
- Candidate artifact SHA-256 differs from a Jujutsu revision identifier.
- Recovery-strict credentials must not be repurposed as general Telegram grants.

## Next acceptance boundary

Implement and independently verify authentic review receipts and canonical persistence/execution; then connect Telegram ingress/outbox. Required falsifiers include replay, altered context, expiry, changed canonical target, simultaneous consumers, crash after execution before delivery, and still-running workers after metadata cancellation.

This file is a source-level safety delta. The canonical COMMAND_IMPL risk packet retains the four UCA types and raw FMEA. No legacy external safety database or global admission state is rewritten.

[Execution plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md) · [Dashboard](http://nas-1.tail55d152.ts.net:4100/static/20261024-0712-recovery-dashboard.html)

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
