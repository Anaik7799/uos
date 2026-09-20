# UOS implementation plan: AGY execution, Codex coordination

Created from synchronized host observation: 2026-09-27T05:26:26Z.
Batch prefix: 20260927-0526 (UTC hour and seconds).
Tags: #fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda

[Planning cockpit](http://nas-1.tail55d152.ts.net:4100/planning) · [This plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260927-0526-system-mcp-agy-implementation-plan.md) · [Machine-readable proposal](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260927-0526-system-mcp-agy-implementation-proposal.json)

## Authority and actual status

Canonical plan: `uos/system-mcp-features/20260919-1642`.
This document specifies implementation and acceptance. Sa-plan remains the only execution/status authority.
The linked proposal is not a shadow task queue: its additional task IDs and dependency amendments require canonical registration and readback before use.

At 2026-09-27T05:30:29Z, the Gleam MCP status response reports 21 tasks, 4 completed, 3 dependency-ready and 0 executing.
The attempt to register this packet as a Sa-plan workflow through the same MCP server returned JSON-RPC -32003:
`Transport-bound task authority unavailable; legacy mutation refused`.
No workflow, additional task, claim or completion resulted from that request.
The four proposed follow-up tasks would bring the total to 25 only after successful registration.

The user has already authorized planning, AGY implementation and eventual integration after completion.
A further generic permission question is unnecessary. The technical prerequisite is a working, independently reviewed task-bound ingress and a valid current grant.
Do not fabricate that grant, lower refusal checks, reuse a completed task's lease or mutate SQL directly.
An MCP bootstrap repair must have a finite recorded scope and an admitted route; absent that route, implementation remains blocked while the reviewable proposal is available.

## Roles and routing

- **AGY:** implement scoped code, meaningful regression tests, formal contracts and evidence through the admitted UOS harness.
- **Codex:** maintain the canonical dependency plan, review AGY diffs, independently verify acceptance and serialize integration.
- **Independent peer:** verify coordinator lineage and operational release evidence; a model response alone does not grant admission.
- **Sa-plan:** own task, worker, attempt, lease, dependency, job and workflow state.
- **Gleam/OTP harness:** validate identity and policy, admit intents and select bounded backend services.

Actual AGY was invoked with `gemini-3.8-flash-medium --effort medium --mode plan`.
It returned a concrete execution handoff. That was planning execution; source implementation has not started.
AGY's configured MCP inventory currently contains external ZigVM/Hermes registrations but no canonical UOS registration. External source trees must remain read-only.

## Implementation stages

Dependencies below are proposed amendments to the existing canonical graph, not claims that those amendments are already registered.
Preserve the completed history of `t1-tracker`, `r01-store-gates`, `r13-task-dashboard` and `t1a-source-reconcile`.

| Stage | Existing or proposed task | Implementation and acceptance |
|---|---|---|
| 0 | NEW `r14-agy-ingress` | Register canonical Gleam MCP for AGY with an actual launcher identity and bounded grant; expose admitted planning registration/readback and scoped development operations. Demonstrate plan/task inspection, exact eligible task claim, bounded read/write/test, release and recorded refusal cases. Keep generic legacy mutations denied. |
| 1 | `t0-coordination` | Capture source revisions, actual sessions, coordinator failure details and writer ownership. Separate live external sessions from local model representations. Bind evidence to sources and synchronized time. |
| 1 | `r02-recovery-candidate` | Preserve both histories and build isolated candidates without replacing canonical state. Reproduce digest and typed replay outcomes; record event-1 divergence and unavailable evidence honestly. |
| 1 | `t0a-reconcile` | After diagnosis and candidate evaluation, independently select the authoritative lineage. Obtain writer quiescence/ownership and test reversible cutover/rollback. A valid 421-event candidate is not automatically the canonical continuation. |
| 2 | `r03-harness-coordinator` | Route the reviewed harness to the selected authority. Reject invalid history, wrong epoch, expired leases, wrong worker/attempt and unavailable stores before effects. |
| 2 | `r04-identity-enrollment`, `t0b-bindings`, `t0c-conformance` | Enroll actual AGY/Claude/Codex sessions and internal OTP actor incarnations; bind holon membership, scoped permissions, heartbeats, message ACKs and Sa-plan ownership. Verify disconnect/restart, duplicate identity, out-of-order ACK, conflicting claims and stale incarnation refusal. Derive timeouts/quorum from admitted policy rather than inventing constants. |
| 2 | `t2-contracts` | Define typed read/control intents, pure decision functions, explicit effect plans and interpreters. Prove/test identity, deny dominance, idempotency, conflict refusal and no authority amplification. Preserve read-only operations and deny undeclared effects. |
| 3 | `r05-mcp-data` | Replace the incompatible bootstrap/store binding path with reviewed successor authorization. Query catalog, observations and coverage from canonical persistence with bounded pagination. A completed `t1-tracker` task must not be required as reusable read authority. |
| 3 | `r06-mcp-control` | Execute the reviewed intent algebra through current actor/task/attempt/epoch fences. Recheck authority at effect time, use stable logical operation IDs and reconcile unknown outcomes before retry. |
| 3 | `r07-hive-swarm` | Run a real multi-agent work cycle via MCP: enqueue/claim, dispatch, acknowledgement, result, independent verification and completion. Distinguish local ecology simulations from real external service bindings in UI and receipts. |
| 3 | `r08-service-adapters` | Reconcile the complete service/capability census with MCP tools/resources/prompts and implemented adapters. Cover data and control separately; undeclared, unsupported, disabled and failing operations remain visible. No coverage credit from registration alone. |
| 3 | NEW `r15-dashboard-freshness` | Replace the hardcoded September 21 risk path with a canonical, approved assessment reference bound to plan and candidate. Show missing/stale/invalid evidence as UNKNOWN and no executable recommendation. Preserve the historical completion of `r13-task-dashboard`. |
| 3 | NEW `r16-evidence-verdicts` | Make checklist verdicts typed and evidence-based. Distinguish inventory presence, observed behavior, formal verification and admission. Remove fixed pass language and unsupported AGY/model-health claims from touched projections. Check expiry, revision and receipt identity before reporting success. |
| 4 | `r09-end-to-end` | Exercise actual registered clients against the same candidate through MCP, including failure/recovery scenarios and dashboard updates. Require identity conformance, swarm/adapters, dynamic assessments and honest checklist results. |
| 4 | `t3-evidence` | Assemble candidate/source hashes, actual logs, formal invocations, receipts and residual gaps for the full acceptance run. Correct timestamp/time-zone errors with superseding records; never relabel an old receipt as fresh. |
| 5 | NEW `r17-candidate-integration` | Inventory ownership of the 711 changed files, preserve concurrent work, isolate logical JJ changes, review conflicts and assemble an explicit integration candidate. Rerun affected tests and end-to-end acceptance against the combined candidate, not just individual slices. |
| 5 | `r10-artifact-sync` | Generate current documentation, dashboard projections, agent guidance, wiki/ZK links and completion views from verified inventory and Sa-plan state. Preserve historical/quarantined records and EV-93 ceiling. Update evidence bindings after generated changes. |
| 6 | `r11-release-review` | Independently review the exact final candidate, applicable formal/runtime evidence, recovery rehearsal and operational ownership. Reconcile all intended changes and reject missing or stale evidence. |
| 6 | `r12-operational-acceptance` | Perform separately fenced release and bounded operational acceptance, including real MCP data/control and agent coordination. Reconcile unknown outcomes and all task results. Move the authorized JJ integration/mainline bookmark only after its gates pass; no Git mutation or automatic admission. |

## Dependency amendments

The machine-readable packet contains the full proposed 25-node acyclic graph.
All original dependencies are retained; the following additional ordering is intentional:

- The execution ingress precedes new AGY implementation; `r02` retains completed `r01` as prerequisite.
- `t0a-reconcile` waits for both `t0-coordination` and `r02-recovery-candidate`.
- `r03-harness-coordinator` waits for the independently reconciled authority.
- `t0b-bindings` waits for `r04-identity-enrollment` as well as `t0a-reconcile`.
- Control acceptance waits for authorized data-plane access and the contract/identity prerequisites.
- `r09-end-to-end` also waits for `r15-dashboard-freshness` and `r16-evidence-verdicts`.
- `t3-evidence` waits for end-to-end observations; `r17-candidate-integration` waits for that packet and reruns acceptance after integration.
- Artifact synchronization and release review follow the reviewed integration candidate.

Canonical registration must use an admitted amendment/import operation and verify the persisted edges.
The currently observed task CLI has no advertised dependency-update verb. Do not silently assume `task create` updates existing dependencies or patch tables directly.
If an amendment API is missing, include a typed, audited implementation in `r14-agy-ingress`, with explicit finite bootstrap scope.

## Task packets and execution policy

Before any claim, each task needs scope/paths, real worker identity, source/candidate binding, fresh assessment, budget, acceptance tests, rollback and reviewer.
Apply class/authority/dependency eligibility before C × T × F × Dep × I ranking.
Coordinator integrity, authorization and false-verification repairs are P1 unless fresh evidence establishes an ongoing unsafe effect requiring P0 containment.
Do not infer an ongoing P0 solely from historical corruption.

Record FMEA severity, occurrence and detection difficulty separately. Unknown occurrence remains unknown pending evidence; no invented risk score unlocks a task.
Evaluate all four UCAs for each packet: absent required action, unsafe provided action, wrong timing/order, and action stopped too early or continued too long.
Specific constraints are immutable history, identity-bound admission, evidence freshness, and effect-time lease/epoch fencing.

Use risk `--preflight PORTFOLIO TASK` before the exact Sa-plan claim and `--active-check PORTFOLIO TASK WORKER ATTEMPT` during work.
HOLD invalidates execution eligibility but does not erase a repair requirement.
Expired lease, changed sources, unknown effect outcome or failed verification stops that affected slice.

Start with one AGY implementation session. After ingress is verified, independent dashboard and checklist slices may run concurrently with at most two implementers and disjoint JJ workspaces/path ownership.
Coordinator recovery, grant publication, integration and runtime cutover are serialized.
Do not parallelize overlapping `harness/mcp.gleam`, admission, store or task-state edits.

## Model and cost policy

Local `agy models` exposed Gemini 3.8/3.7/3.6 Flash low/medium/high and Gemini 3.1 Pro low/high.
The CLI supports `plan` and `accept-edits` modes, and low/medium/high/max effort.
The actual planning call used Gemini 3.8 Flash medium; its successful result is recorded separately.

- Default implementation: Flash medium, accept-edits, one scoped task after successful claim.
- Mechanical artifact/schema changes after contracts settle: Flash low.
- Difficult state machines or failing correctness cases: Flash high; escalate to Pro high only after a concrete unresolved failure or for targeted lineage/formal review.
- Bound each run to 15 minutes and one repair retry before reassessment; reconcile tool outcomes before any retry.
- Send focused task context and relevant diffs instead of the whole monorepo. Test narrow behavior first, then affected suites and final combined acceptance.
- Record actual provider tokens/cost when available; otherwise UNKNOWN. No measured dollar optimum or free execution is claimed.

## Required falsifiers and definition of done

1. **Authority:** wrong agent/task/worker/attempt/epoch, revoked grant and expired lease cannot perform effects. Registration is idempotent and inconsistent re-registration is refused.
2. **Recovery:** altered event payload/digest, missing registration, interrupted cutover and rollback are detected on disposable candidates; originals remain preserved.
3. **Intent algebra:** duplicate success does not repeat the effect; same ID with a different payload conflicts; partial/unknown outcome requires reconciliation; policy denial dominates composition.
4. **Coverage:** every in-scope service/capability is enumerated with owner, source, endpoint/schema, effects, laws, dependencies, aspects/layers and test evidence. UNKNOWN/ABSENT/DISABLED/FAILING are visible and not counted usable.
5. **Dashboard:** fresh-to-stale, future timestamps, wrong plan/candidate/hash, missing assessment and stale worker cases change status correctly without synthetic recommendations.
6. **Checklist:** an existing empty document, unexecuted binary, failing test, unsupported proof or expired receipt cannot satisfy runtime/formal/admission gates. Output and process exit verdict agree.
7. **Swarm:** live session/actor registration, ACK and lifecycle observations support each coordination claim. Crash/restart and lease-loss scenarios preserve single-owner effects.
8. **Release:** applicable component, end-to-end and formal checks pass at the final candidate; all canonical tasks have matching results; provenance/recovery and independent release gates pass. Any unresolved item keeps the corresponding feature and release incomplete.

## Codex review of AGY's handoff

Accepted: preserve completed tasks, repair ingress first, isolate coordinator recovery, implement a pure intent/effect boundary, add dashboard/checklist successor work, and use bounded model escalation.
Corrected: no invented tool names or bootstrap grant grants authority; no fixed 15-second heartbeat or blanket 24-hour freshness rule; no arbitrary error codes; no copying divergent histories into new live tables.
The candidate diagnosis and lineage selection are distinct; the graph must not both require lineage before candidate and candidate before lineage.
The local ecology is implemented software, not evidence of live external participation; it should not be described simply as a dummy actor.
User authorization is already present. What remains missing is verified technical execution access and the independently reviewed recovery state.

## Comprehensive verification checklist

These are acceptance obligations, not a blanket passing report.

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Host UTC and chrony observed for this planning batch.
- [x] CHK-02-TAIL — Full Tailnet links included; live delivery not retested.
- [x] CHK-03-FRACT — L0–L9 scope tags present.
- [ ] CHK-04-KM — Publish verified wiki/ZK cross-links under r10.

</details>
<details><summary>Domain 2 — Zero-Muda and storage safety</summary>

- [ ] CHK-05-MUDA — Candidate dependency exclusion checks.
- [ ] CHK-06-GRAPH — Runtime language/NIF boundary checks.
- [ ] CHK-07-DRIVE — Preserve and test denied OS serial interlock in scope.

</details>
<details><summary>Domain 3 — Tests and formal gates</summary>

- [ ] CHK-08-C1C8 — Applicable interface behavior acceptance.
- [ ] CHK-09-MATH — Measured/formal mathematical gates.
- [ ] CHK-10-9MOD — Applicable property/fuzz/fault/performance and other modalities.
- [ ] CHK-11-REGR — Relevant regressions at final candidate.

</details>
<details><summary>Domain 4 — Runtime and observability</summary>

- [ ] CHK-12-GLEAM — Actual supervisor, actor and fence observations.
- [ ] CHK-13-HERMES — Bounded formal and authoritative evidence observations.
- [ ] CHK-14-ZIGVM — Deterministic runtime evidence for applicable services.
- [ ] CHK-15-MAX — Real isolated inference evidence when in scope.
- [ ] CHK-16-OTEL — Actual correlated traces and clock freshness.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Candidate-bound independent review and admission.
- [x] CHK-18-JJ — Standalone JJ preserved; no integration mutation in this planning batch.

</details>
<details><summary>Domain 6 — Provenance</summary>

EV ceiling remains 93. EV-94..109 remain NOT_ADMITTED. New EV numbers are not issued.
Existing receipts and failed registration outcomes remain visible; plan authoring is not task completion.

</details>

[Previous: reviewed recovery evidence](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260921-1810-coordinator-source-reconciliation-receipt.json) · [Next: proposal](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260927-0526-system-mcp-agy-implementation-proposal.json) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki)

UOS footer: proposal and planning handoff only; canonical registration and source execution remain unperformed.
