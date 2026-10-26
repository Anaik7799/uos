# 20261026-0220 — UOS Telegram journeys: Superpowers bindings

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l9 #zk-adr #zero-muda

[Source](http://nas-1.tail55d152.ts.net:4100/files/plugins/uos-telegram-journeys/skills/uos-telegram-journeys/references/20261026-0220-superpowers-bindings.md) · [Skill](http://nas-1.tail55d152.ts.net:4100/files/plugins/uos-telegram-journeys/skills/uos-telegram-journeys/SKILL.md) · [Rule](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20261026-0220-telegram-journey-acceptance.md) · [Contract](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261026-0210-telegram-operator-journey-contract.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/docs/wiki/20261026-0220-telegram-journeys-guide.md)

Created: 2026-10-26. Process guidance; no production admission claim. This UOS-local binding is sufficient without installing Superpowers. Where those skills are present, apply the binding at their entry and exit. Sa-plan authority and `SC-RISK-PRIORITY-001` are unchanged.

| Workflow/skill | Mandatory entry | Mandatory exit |
|---|---|---|
| superpowers:verification-before-completion | Identify the journeys that cover the changed Telegram behaviour and the candidate they will run against | Journeys are the completion evidence for Telegram surface work: report staged results at their scope, real-traffic as `UNRUN` until an authorized human records it; no claim from a model reply or ACK |
| superpowers:finishing-a-development-branch | Check whether the change touches the command surface; if so, the staged journey tests and coverage test are a landing gate (INV-TGJ-02) | No landing of command-surface work with a red or unrun journey test; integration ownership checked separately |
| superpowers:test-driven-development | A new command literal starts with its journey step and expected reply class in the spec table, then the failing dispatcher-layer assertion | Coverage test green; every literal and family has a step; expected classes are only `ok`/`preview`/`denied`/`backend_unavailable`/`approval_required` (`executed`/`duplicate` only via approval) |
| superpowers:systematic-debugging | Reproduce a failing journey step at the dispatcher layer first (`classify_directive` then the adapter route), preserving the exact input and output | Cause note before any retry against real traffic; targeted regression added to the journey test; real-traffic re-run only by the operator |

## Boundaries

- No hooks, no network calls, no background workers, no credentials in this package.
- Staging bot only; the production bridge is never restarted for a journey (INV-TGJ-05).
- A real-traffic pass is recorded by an authorized human in Sa-plan (INV-TGJ-03); no agent records it.
- Plan, task and job state stays in Sa-plan; no Markdown shadow queue.

## Pressure cases to review

"The dispatcher test is green so Telegram works", "the board ACKed the journey", "the model says the reply looked right", "just restart the production bridge to test" and "expect `executed` so the step looks green" must all be rejected with the corresponding invariant. Record behavioural evaluation of these as `UNRUN` until observed in an authorized session.

## Comprehensive verification checklist

This is a process/document package. The entries below do not assert production conformance.
UNRUN and NOT_ADMITTED remain nonpassing; N/A must be justified for each actual change.

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Timestamp prefix recorded (20261026-0220).
- [x] CHK-02-TAIL — Full Tailscale FQDN references provided; live delivery unverified.
- [x] CHK-03-FRACT — L0–L9 applicability tagged.
- [x] CHK-04-KM — Contract, specs, runbooks and wiki guide linked in this package.

</details>
<details><summary>Domain 2 — Zero-Muda and storage safety</summary>

- [ ] CHK-05-MUDA — Fleet dependency exclusion scan UNRUN.
- [ ] CHK-06-GRAPH — Runtime language/NIF conformance UNRUN.
- [ ] CHK-07-DRIVE — OS storage interlock execution UNRUN.

</details>
<details><summary>Domain 3 — Testing and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Full UI categories UNRUN.
- [ ] CHK-09-MATH — Mathematical quality gates UNRUN.
- [ ] CHK-10-9MOD — Nine runtime test modalities UNRUN.
- [ ] CHK-11-REGR — Live UI regression monitoring UNRUN.

</details>
<details><summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — Staged journey tests not run by this documentation package; UNRUN.
- [ ] CHK-13-HERMES — Mandatory enforcement NOT_IMPLEMENTED by this package.
- [ ] CHK-14-ZIGVM — Runtime kernel checks UNRUN.
- [ ] CHK-15-MAX — Actual inference checks UNRUN.
- [ ] CHK-16-OTEL — Runtime telemetry correlation UNRUN.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Independent review/admission NOT_ADMITTED.
- [x] CHK-18-JJ — No native Git command used; standalone JJ workspace fable-w4 only.

</details>

<details><summary>Domain 6 — Provenance extension</summary>

EV ceiling remains 93. EV-94..109 remain NOT_ADMITTED. No new EV number is minted.
A real-traffic journey pass is recorded by an authorized human in Sa-plan; this package records none.

</details>

**UOS footer:** scoped workflow bindings; no global plugin installation or runtime mutation.
