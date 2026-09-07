# 20260907-1559 — Risk prioritization standard operating procedure

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda

[UOS](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Source](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1559-risk-prioritization-sop.md)

Created from host observation 2026-09-07T15:58:59Z. Prefix uses UTC hour and **seconds**, not minutes.

**Contract:** SC-RISK-PRIORITY-001 · **Version:** 1.0.0  
**Authority:** operator request in the side conversation to standardize prioritization, processes, skills, agents and plugins.  
**Scope:** all UOS SDLC, SRE, SOP, agentic work, jobs and workflows, at L0–L9.  
**Enforcement:** mandatory process rule; this package supplies policy, records and discovery bindings. It does not claim a mandatory runtime scheduler or admission gate has been implemented.

## 1. Decision rule

Use **Criticality × STPA exposure × FMEA band × Dependency × Impact**:
**score = C × T × F × Dep × I**, with each factor an integer 1–5, yielding 1–3125.
The operator's “FEMA” is interpreted as **FMEA**. The legacy Sa-plan field remains named fema.

Apply the score only after checking safety constraints, authority, freshness and dependency readiness.
A high score never grants permission to execute, deploy, bypass a gate or close a safety constraint.
These are ordinal analyst judgments, not measured probabilities, certified risk levels or an industry-standard STPA formula.
C, T, F and I can be correlated: do not interpret their product as independent likelihoods or expected loss.
Do not replace the factors with AHP weights, agent preference, standards compliance or model enthusiasm.

STPA retains its control structure, unsafe control actions, loss scenarios and constraints.
The numerical T band is a UOS triage projection of that analysis. The process follows the analysis structure described by the [MIT STPA/CAST handbooks](https://psas.scripts.mit.edu/home/books-and-handbooks/); the five-factor scoring and thresholds here are local policy.

## 2. Safety classes and eligibility come first

| Class | Meaning | Required response |
|---|---|---|
| P0 | Current unsafe effect, active security/data-loss incident, uncontrolled writer or failing safety control | Contain through an already authorized bounded runbook; stop unsafe effects, preserve evidence, record incident and re-observe. |
| P1 | Unresolved safety, authorization, evidence-integrity, recovery or isolation condition that blocks the proposed release/effect | Hold that release/effect. Work on authorized repairs or bounded evidence collection. |
| P2 | Necessary reliability, capability or efficiency work with its immediate effects controlled | Pull dependency-ready work by score. |
| P3 | Optional optimization, convenience or experimentation | Pull after higher classes, subject to capacity and measured value. |

Classes are contextual, not numeric score thresholds. An open P1 does not prohibit safe work on unrelated scopes.
A score of 3125 in P3 cannot displace a P1 repair. Critical severity, an unresolved unsafe control action,
or missing evidence for a safety constraint cannot be averaged away.

A task is eligible only when scope and owner are explicit, authority is valid, dependencies are satisfied,
evidence is fresh for its effect, resources fit the budget, and the action does not violate a safety constraint.
Repair/probe tasks may be eligible while the unsafe downstream release is blocked.
UNKNOWN/STALE assessment inputs produce **NEEDS_EVIDENCE**, not low-risk clearance.
Sa-plan's existing available/executing/completed states are not renamed by this SOP:
BLOCKED, NEEDS_EVIDENCE and safety classes are assessment fields, not new database states.

An incident uses an abbreviated packet: loss/hazard, authorized runbook, target, owner, rollback,
start time and resource bounds. Stabilization may precede the full scoring worksheet.
Sa-plan unavailability triggers the existing Andon rule; this SOP introduces no bypass or new authority.

## 3. Anchored five-factor rubric

Higher values mean greater urgency, exposure, failure concern, dependency importance or useful impact.
Each value needs a rationale and primary evidence reference. Unknown values are null with a stated interval.

| Factor | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| C — criticality / cost of delay | Discretionary | Routine planned work | Necessary within planned milestone | Imminent release/SLO constraint | Current loss or unsafe effect needs immediate control |
| T — STPA control exposure | No applicable UCA, with all four types considered | Scoped UCA with verified control | Credible UCA with incomplete feedback or coverage | Critical UCA with missing/unverified enforcement | Observed unsafe or missing control in its hazardous context |
| Dep — dependency importance | No blocked consumer | Optional downstream use | Several ready consumers | Required release/critical-path predecessor | Shared authority/control blocks multiple critical paths |
| I — benefit if acceptance criteria succeed | Local convenience | One bounded workflow | One critical service | Several services or tenants | Fleet-wide critical capability or loss prevention |

The Dep score is not permission to violate DAG order. Record actual task IDs and edges, not counts invented to inflate priority.
I describes the benefit of the completed change; it does not represent confidence or speculative consciousness.

### FMEA band F

For every relevant failure mode, record component/function, cause, local effect, system effect,
existing prevention/detection, severity S, occurrence O and detection difficulty Det, each 1–5.

| Subfactor | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| S — severity | Cosmetic | Local recoverable degradation | Service outage/rework | Major service/security/evidence damage | Irreversible loss, major compromise or false safety admission |
| O — occurrence | Rare in a stated observed population | Isolated occurrence | Credible under expected load/fault conditions | Recurrent in observed conditions | Reproduces on ordinary exposure |
| Det — detection difficulty | Deterministic detection before effect | Reliable alarm before loss | Detected after bounded loss | Delayed/manual detection | Silent or no detection mechanism |

Occurrence is not a fabricated probability. State population, exposure window and evidence, or mark O unknown.
For mode m, **RPN_m = S_m × O_m × Det_m** (1–125), and
**F_m = max(S_m, rpn_band(RPN_m))** (1–5), using these local triage bands:
RPN 1–5 → 1; 6–15 → 2; 16–35 → 3; 36–70 → 4; 71–125 → 5.
For the task, **F = max(F_m)**, never an average over modes.
The severity floor prevents a severe, rare or easily detected failure from disappearing.
Report the full S/O/Det triplet and RPN alongside F. Equal products are not equivalent failure modes.
Retain separate pre-control and residual assessments; reduce residual ratings only after fresh control evidence.

## 4. Mandatory reviewable decision record

Attach the record to the Sa-plan task and its jobs/workflows; use the versioned record schema in
[governance/planning](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260907-1559-risk-priority-record.schema.json).
The JSON example is a policy-change example, not fleet health or release evidence.

Every assessment contains:

1. Plan/task/actor identity, scoped resources/paths, phase, L0–L9 layer, parent and dependencies.
2. Host-observed UTC time, expiry, source/candidate or working-tree digest, and evidence locators.
3. Losses, hazards, controller, control action, and explicit consideration of all four UCA types:
   required action not provided; unsafe action provided; wrong timing/order; stopped too soon or applied too long.
   Each applicable UCA binds source, action, context, hazard and constraint. Each inapplicable case explains why.
4. FMEA modes and controls, raw S/O/Det and RPN, normalized F, and all five factor rationales.
5. Safety class, blockers, readiness, own score/interval, inherited urgency and its source task IDs.
6. Alternatives, chosen action, concise reasons, counterevidence, assumptions, confidence,
   predicted outcomes and falsifiers. This is a reviewable decision summary; private internal reasoning is not required.
7. Acceptance tests, intended rollback/containment, reviewer, budget ceilings, actual results and residual risks.
8. Superseded assessment reference and reason for changes. Preserve history; do not overwrite inconvenient evidence.

Use monotonic elapsed time for local durations and the authority's lease/fencing protocol for ownership.
UTC observations, NTP offset and Lamport causal order are different fields and never substitute for one another.
A model's time string or board timestamp cannot establish a live lease.

Default review ceilings: incident 15 minutes, release/effect 60 minutes, planned backlog 24 hours.
These are maximum assessment ages, not lease lengths or guaranteed evidence lifetimes.
Changes to candidate, input digest, hazard context, authority, dependency state or observed outcome invalidate affected assessments immediately.
At a safety-critical effect boundary, recheck the actual required controls even if the ceiling has not elapsed.

## 5. Deterministic selection and dependency handling

1. Re-observe changed evidence and identify hard constraints and P0/P1 holds.
2. Validate the dependency DAG; unresolved references or cycles block affected tasks and create a bounded repair/probe.
3. Propagate urgency to genuine unfinished prerequisites: effective class is the most urgent class among the task and its blocked consumers.
   Effective score is the maximum score among those in the most urgent inherited class,
   with origin IDs retained. Preserve the prerequisite's own score.
   Never propagate through cycles or make the blocked consumer eligible.
4. Among authorized, evidence-sufficient, dependency-ready tasks, choose effective class P0 before P1 before P2 before P3,
   then descending effective score.
5. With overlapping uncertainty intervals or order reversals under a ±1 factor sensitivity check,
   label the ordering provisional and prefer a cheap discriminating probe when it can change the decision safely.
   Do not delay authorized incident containment for statistical analysis.
6. Break remaining ties by evidenced benefit per bounded cost, then oldest ready time, then stable task ID.
   Cost is a tie breaker, not a divisor that suppresses severe hazards. Aging cannot demote a safety constraint.
7. Record selected and deferred candidates and why; claim the exact chosen task through Sa-plan, then recheck ownership before effects.

Unknown factors produce a score interval from the declared factor bounds, not a synthetic point score.
Intervals and sensitivity are scenario analysis, not calibrated confidence intervals.
Recompute parent summaries from current child assessments; do not sum duplicate evidence or inherited scores across L0–L9.

## 6. Integration into daily SDLC, SRE and agentic work

| Entry/transition | Required record and action | Exit evidence |
|---|---|---|
| Intake / “what next?” | Observe live tasks and code; remove already-completed candidates from consideration; rate remaining work | Candidate list with sources, constraints, dependencies and score rationale |
| Design / planning | Define losses, UCAs, FMEA modes, acceptance tests, affected interfaces and rollback | Reviewed bounded plan; capability gaps explicit |
| Claim / dispatch | Select dependency-ready work, record selection, choose cheapest capable resource, claim exact task | Task/attempt/lease, scope, budget and selection reference |
| Implement / build | Work only inside scope; reconsider changed risks before new effects | Artifacts and targeted tests bound to their input snapshot |
| Review / integrate | Recompute residual risks; challenge unsupported “green”; apply two-key evidence rules | Independent review and current candidate evidence; unresolved constraints listed |
| Release / cutover | Recheck authorization, recovery, fencing, isolation and freshness at the effect boundary | Explicit release decision and observed rollback/cutover results |
| Operate / incident | Correlate board events with actual telemetry; P0 containment; CAST for judge/evidence/concurrency failures | Observations, containment results, cause note before speculative reruns |
| Recovery / postmortem | Restore and verify effect outcomes; prevent stale owners resuming; update failure rates and controls | New assessment, residual backlog, journal and learning references |

Every child job/workflow carries its parent plan/task, assessment reference, budget and effect constraints.
Changing those constraints requires a new assessment, not reinterpretation by a worker.
Agents may exchange compact decision summaries and evidence references; board ACKs remain advisory.
Existing roles stay intact: implementer prepares, reviewer challenges, authorized controller admits effects.
No model, plugin, Rete result, forecast or score grants its own execution authority.

Prefer deterministic local checks. Select the least costly model with demonstrated capability for the operation,
using current prices, privacy policy and aggregate budgets. Route uncertain/high-impact judgments to qualified review.
Do not claim a global cost optimum without comparable capability, availability and cost evidence.
Limit duplicate work, token budgets, retries and WIP; collect actual cost and useful outcome.

## 7. Skills, Superpowers, agents and plugins

The repository-owned **uos-risk-prioritization** skill is the common entry point.
It binds system-engineering-sop, stpa-safety-protocol, fractal-decision-calculus,
production-readiness, journal-protocol and Superpowers lifecycle skills.
Read [the Superpowers bindings](http://nas-1.tail55d152.ts.net:4100/files/plugins/uos-risk-prioritization/skills/uos-risk-prioritization/references/20260907-1559-superpowers-bindings.md).

Root and per-runtime agent policies require this SOP at planning, dispatch, review, release and incident transitions.
The local plugin packages the skill for reuse; it adds no hooks, network calls, background workers or deployment permissions.
Imported/global skill files remain read-only. UOS-local ranking and authority rules override conflicting imported examples.
Respect the active session's limits on delegation and mutation; this side conversation does not authorize sub-agents.

## 8. Sa-plan adapter and current enforcement gap

Observed implementation: Sa-plan's task select command records stpa, fema, criticality, dependency,
standards and agent_fit, plus priority and rationale. It has no dedicated impact column.
record_selection appends evidence; it does **not** update sa_plan_task.priority or implement this ordering.
Factor validation currently accepts nonnegative integers, not this policy's exact 1–5 bounds.

Until a native adapter is implemented and independently verified:

- Set UOS_SA_PLAN_DB explicitly to /home/an/NAS-setup/uos/var/sa-plan/uos.sqlite3.
- Store C/T/F/Dep in the corresponding fields; retain impact, raw FMEA, class, blockers, intervals and policy version in JSON rationale.
- Keep standards and agent_fit separate; use 0 for not assessed in this legacy API, never as an impact substitute.
- Pass the calculated score as the selection's priority argument; record effective/inherited values separately.
- Select and claim by exact task ID after the procedural checks. A generic claim-next call does not prove this policy's ordering.
- Use only supported Sa-plan commands/Store APIs for task state; no direct database writes, competing queue or plugin-owned task status.
- Schema/arithmetic validation is report-only. The record schema alone does not recompute scores or enforce lifecycle decisions.

Required follow-up: typed impact/class/freshness schema, arithmetic and DAG validation, atomic eligible selection
with fencing and budgets, and tests for stale/forged evidence, blocked high scores, cycle detection and concurrency.
Documentation or plugin discovery must never label that follow-up “enforced” before candidate-bound verification.

## 9. Acceptance scenarios and recurring audit

| Scenario | Required decision |
|---|---|
| P3 score 3125 versus ready P1 score 100 | P1 first; score cannot waive class |
| High-score release with unfinished prerequisite | Release blocked; eligible prerequisite inherits urgency |
| Severe FMEA S=5, O=1, Det=1 | RPN=5, F=5; severe consequence retained |
| Ordinary FMEA S=2, O=5, Det=5 | RPN=50, F=4; recurrence/detection can raise the band |
| Missing factor / stale evidence / changed candidate | NEEDS_EVIDENCE; interval and bounded probe, no clearance |
| Existing STPA constraint missing, model recommends proceed | Hold affected effect regardless of score |
| Lease expired, worker claims old ownership | No further effect; reacquire through authority and reassess |
| Two workers choose same top task | Only current claimed/fenced owner may act; score is not a lease |
| Cost estimate or model price unknown | Bounded local check or budget clarification; no invented free inference |
| All tests pass but physical application migration unrun | Report tests passed at their scope; migration remains UNRUN |
| Emergency requires containment | Authorized bounded containment first, full packet follows |
| Same score and cost evidence | Oldest ready task, then stable ID; keep decision history |

At each release and after an incident, audit coverage: eligible tasks with fresh records / all eligible tasks,
effects with valid constraint evidence / all sampled effects, overdue P1 age, blocked critical-path age,
unauthorized/expired-owner effects, false-green claims, rank stability, and useful outcome per actual cost.
Missing denominators or runtime feeds are UNKNOWN. No constant “100% compliance” or unmeasured intelligence/consciousness KPI.

## 10. Initial follow-up order

Revalidate these working priorities against live evidence before claims; this table is not a second task queue.

1. Evidence/admission integrity and expired-owner/fencing controls.
2. Authorization at real effect boundaries; recovery and safe cutover.
3. Sandbox isolation and pinned Solo5/Mirage toolchain evidence.
4. Durable workflow effects, aggregate budget/overload controls and tenant-isolated context.
5. Truthful telemetry/forecast calibration, interoperability and demonstrated inference.
6. Optional optimization after measured acceptance.

The policy rollout's own evidence is in its journal. Historical “completed” task labels are not independent production approval.

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

[SOP](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1559-risk-prioritization-sop.md) · [Wiki](http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260907-1559-risk-prioritization-guide.md) · [ADR](http://nas-1.tail55d152.ts.net:4100/docs/zk/20260907-1559-adr-risk-prioritization.md) · [Journal](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260907-1559-risk-prioritization-journal.md)

**UOS footer:** mandatory process policy; automated enforcement and runtime admission require separate evidence.
