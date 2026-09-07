# 20260907-1559 — UOS lifecycle, skills and Superpowers bindings

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda

[Source](http://nas-1.tail55d152.ts.net:4100/files/plugins/uos-risk-prioritization/skills/uos-risk-prioritization/references/20260907-1559-superpowers-bindings.md) · [SOP](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1559-risk-prioritization-sop.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260907-1559-risk-prioritization-guide.md) · [ADR](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260907-1559-adr-risk-prioritization.md) · [Journal](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260907-1559-risk-prioritization-journal.md)

Created: 2026-09-07T15:58:59Z. Process guidance; no production admission claim.

This is an active UOS-local extension of the named workflows. It is sufficient to apply the
prioritization method without installing Superpowers or reading private global skill trees.
When those skills are present, apply this binding at their entry and exit. Their other
compatible engineering practices remain useful; their example rankings and execution paths
do not override SC-RISK-PRIORITY-001 or Sa-plan authority.

| Workflow/skill | Mandatory entry | Mandatory exit |
|---|---|---|
| system-engineering-sop | Identify controlled system, losses, safe state and affected control actions | Controls have explicit enforcement and evidence scope |
| stpa-safety-protocol | Four UCA types, cause/context, constraints and FMEA delta | Unresolved constraints and any separate SIF/EJ assessments remain visible |
| fractal-decision-calculus | Fresh primary inputs, alternatives, counterevidence and uncertainty | Use the operator's five-factor ranking; AHP/Pugh may advise alternatives, not replace it |
| superpowers:brainstorming / brainstorming | Confirm scope and facts; rank actual problems before designs | Bounded design with dependencies, risks, acceptance and budget |
| superpowers:writing-plans / writing-plans | Record the five factors, class, source freshness and graph | Plan and exact tasks registered in Sa-plan; no Markdown shadow queue |
| superpowers:executing-plans / executing-plans | Recompute eligibility and claim the exact selected task | Evidence and changed risks recorded before selecting more work |
| superpowers:test-driven-development | Identify observable acceptance and relevant negative cases | Tests establish behavior at their actual scope; no fabricated baseline or test receipt |
| superpowers:systematic-debugging | Observe failure; preserve evidence; contain if authorized | Cause note before speculative retry; targeted regression verifies the fix |
| superpowers:dispatching-parallel-agents / subagent-driven-development | Only if active instructions allow delegation; disjoint scopes and bounded budgets | Child work and evidence tied to parent; no duplicated authority or automatic acceptance |
| superpowers:requesting-code-review / receiving-code-review | Reviewer gets candidate, assessment, constraints, counterevidence and evidence refs | Findings update residual risks and ranking; ACK is not admission |
| superpowers:verification-before-completion | Recheck candidate, freshness, authority, dependencies and relevant tests | Claim only observed evidence state; preserve UNKNOWN, STALE and NOT_ADMITTED |
| superpowers:finishing-a-development-branch | Check integration/release ownership and recovery plan separately | No automatic deployment or integration from a score or task completion |
| production-readiness / SRE | Release constraints, actual runtime, recovery, isolation, budgets and fencing | Authorized bounded cutover/rollback evidence, or an explicit hold |
| journal-protocol | Capture before-state, selected/deferred alternatives and expected outcome | All 13 sections, actual results/cost, residual risks, new priorities and learning refs |
| writing-skills / plugin-creator | Keep guidance and validators local; define pressure cases and limitations | Local links/manifests validate; behavior tests and reload/adoption are separately evidenced |

For STPA-derived SIF/EJ/P-matrix evidence, retain the original named method and inputs.
Do not mix its dimensions or thresholds into C/T/F/Dep/I. If methods disagree, investigate the
underlying constraints/evidence; a blocking safety constraint wins over either arithmetic ranking.

## Roles and workflow handoff

- Planner/implementer: prepare the record and bounded work, with target paths and limits.
- Reviewer: challenge freshness, FMEA/UCAs, dependency edges and claimed completion.
- SRE/release controller: verify actual authority, recovery and control state immediately before effects.
- Plugin/agent/tool adapter: forward the record reference and bounded request; do not invent a parallel queue.
- Journal/knowledge consumer: preserve observed decisions and outcomes; publish projections of Sa-plan state.

OpenRouter and other advisory agents use the same record and explicit budgets.
Route on demonstrated capability and current price evidence, not model brand or an assumed global optimum.
Imported skill instructions that call for sub-agents do not override a session that prohibits them.

## Pressure cases to review

“Cheapest wins despite a P1 hazard”, “the board says done”, “my lease expired but the test passed”,
“we already spent time on it”, “a high score makes the dependency optional”, and
“the plugin loaded so enforcement is active” must all be rejected with the corresponding SOP rule.
Automated arithmetic/package checks do not prove that live agents obey these cases.
Record behavioral evaluation as UNRUN until actually observed in an authorized session.

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

**UOS footer:** scoped workflow bindings; no global plugin installation or runtime mutation.

