---
name: uos-risk-prioritization
description: Use when choosing UOS work, writing or executing plans, reviewing changes, releasing, handling incidents, or changing agent, skill, Superpowers or plugin processes.
---

# 20260907-1559 — UOS risk prioritization

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda

[Source](http://nas-1.tail55d152.ts.net:4100/files/plugins/uos-risk-prioritization/skills/uos-risk-prioritization/SKILL.md) · [SOP](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1559-risk-prioritization-sop.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260907-1559-risk-prioritization-guide.md) · [ADR](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260907-1559-adr-risk-prioritization.md) · [Journal](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260907-1559-risk-prioritization-journal.md)

Created: 2026-09-07T15:58:59Z. Process guidance; no production admission claim.

Read the repository-owned [SOP](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1559-risk-prioritization-sop.md) at
contracts/rules/20260907-1559-risk-prioritization-sop.md. Use the filesystem copy when the dashboard is unavailable.
Everything required for this method is in UOS; imported/global skills are optional context.

1. Observe current Sa-plan tasks, candidate/evidence digests, authority and constraints.
   Stay within the active request; do not resume inherited work or spawn agents when prohibited.
2. Consider all four STPA unsafe-control-action types, attach constraints, and record FMEA modes.
   Keep severity, occurrence and detection difficulty explicit.
3. Apply safety class and dependency eligibility first. Calculate
   **C × T × F × Dep × I** using the SOP's 1–5 anchors and FMEA severity floor.
   Unknown is not zero or permission. Show interval, rationale and evidence.
4. Propagate urgency to real prerequisites without making blocked consumers eligible.
   Challenge close/uncertain rankings; prefer a cheap discriminating check.
5. Record the selection through Sa-plan. Its legacy select command is append-only evidence:
   impact belongs in JSON rationale; the recorded score does not update queue order.
   Claim the exact eligible task; recheck ownership and scope before effects.
6. Choose the cheapest capable tool/model under explicit resource bounds. Never trade a
   safety constraint for lower token cost.
7. Reassess at lifecycle transitions and on changed evidence. Review the decision,
   alternatives, assumptions, forecast and falsifiers. Private internal reasoning is not required.
8. Close with acceptance evidence, residual risk, a 13-section journal and learning references.
   A passing validator, board ACK or model result never grants admission.

For SDLC/SRE stages and Superpowers integration read the repository-local
[bindings](http://nas-1.tail55d152.ts.net:4100/files/plugins/uos-risk-prioritization/skills/uos-risk-prioritization/references/20260907-1559-superpowers-bindings.md) at plugins/uos-risk-prioritization/skills/uos-risk-prioritization/references/20260907-1559-superpowers-bindings.md.
The binding is sufficient when Superpowers is not installed.

Run the local report-only validation wrapper:
**bash tools/risk-priority-check --selftest**, then **bash tools/risk-priority-check --package**.
Its dependencies and reproducible commands are in the package wiki.
Do not claim runtime enforcement from these checks.

## 20260907-1606 — Strong checker integration (SC-RISK-CHECK-001)

Follow the repository-owned
[checker contract](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1606-risk-checker-contract.md)
and [operating guide](http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260907-1606-risk-checkers-guide.md).
Run **bash tools/risk-priority-check --all** for checker/policy changes and relevant CI.
Before a claim use **--preflight PORTFOLIO TASK**; during owned work use
**--active-check PORTFOLIO TASK WORKER ATTEMPT** with current Sa-plan identity.
Both require a complete, fresh, source-bound plan assessment. Reused receipts require
**--receipt RECEIPT**. HOLD, missing tools/evidence, clock failures and provisional
ordering fail closed; investigate the reported next check before retry.
These are local preflight observations. Atomic admission, semantic review and actual
effect-time fencing remain separate requirements. No global hooks or agent reload are implied.


## Comprehensive verification checklist

This is a process/document package. The entries below do not assert production conformance.
UNRUN and NOT_ADMITTED remain nonpassing; N/A must be justified for each actual change.

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Host timestamp recorded.
- [x] CHK-02-TAIL — Full Tailscale FQDN references provided; live delivery unverified.
- [x] CHK-03-FRACT — L0–L9 applicability tagged.
- [x] CHK-04-KM — SOP, wiki, ADR and journal linked in this package.

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

- [ ] CHK-12-GLEAM — Production supervision/fencing checks UNRUN.
- [ ] CHK-13-HERMES — Mandatory scheduler enforcement NOT_IMPLEMENTED by this package.
- [ ] CHK-14-ZIGVM — Runtime kernel checks UNRUN.
- [ ] CHK-15-MAX — Actual inference checks UNRUN.
- [ ] CHK-16-OTEL — Runtime telemetry correlation UNRUN.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Independent review/admission NOT_ADMITTED.
- [x] CHK-18-JJ — No native Git command or integration/VCS mutation used for this package.

</details>

**UOS footer:** local skill adapter; canonical selection state remains in Sa-plan.

