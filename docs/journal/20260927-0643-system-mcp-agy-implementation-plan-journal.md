# System MCP implementation plan and AGY execution handoff

Created: 2026-09-27T06:33:43Z. Filename prefix uses UTC hour and seconds.
Clock: chrony stratum 3, leap Normal, system offset 0.000007243 seconds slow; reference 2026-09-27T06:24:28Z.
Canonical Sa-plan: `uos/system-mcp-features/20260919-1642`.
Status: planning journal; proposal registration refused in the recorded attempt; no implementation completion or admission claimed.
Tags: #fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda

[Planning cockpit](http://nas-1.tail55d152.ts.net:4100/planning) · [Implementation plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260927-0526-system-mcp-agy-implementation-plan.md) · [Proposal and dependencies](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260927-0526-system-mcp-agy-implementation-proposal.json) · [AGY handoff and MCP receipt](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260927-0526-agy-plan-handoff-receipt.json)

## 1. Scope & Trigger

The operator requested that the implementation plan be written in the journal. This entry records all workstreams, AGY execution ownership, Codex coordination, dependencies, acceptance criteria and the observed registration blocker.
Engine 5 formal gateway: this documentation records intended contracts; no new Lean/Gospel/Z3 proof or runtime admission is established.

## 2. Pre-State Assessment

The last recorded Gleam MCP observation, at 2026-09-27T05:30:29Z, reports 21 canonical tasks, 4 completed, 3 dependency-ready and 0 executing. These counts are historical observations, not a new live census.
The proposal contains 25 nodes: the existing 21 plus four unregistered follow-ups. Coordinator digest/replay, incompatible MCP bindings, real agent enrollment, stale dashboard risk data and file-presence-based verification remain unresolved. Engine 7 Kalman state estimation is UNRUN; no inferred health estimate is substituted for these observations.

## 3. Execution Detail

Google AGY produced the planning handoff using `gemini-3.8-flash-medium`, medium effort and plan mode. Codex reviewed it, removed invented tools/grants/timeouts, corrected dependency ordering and saved the plan, proposal and receipt. This turn records that plan in the journal only.

| Stage | Task references | Intended implementation and acceptance |
|---|---|---|
| Preserve history | `t1-tracker`, `r01-store-gates`, `r13-task-dashboard`, `t1a-source-reconcile` | Preserve the four completed task records; extend behavior through scoped follow-ups. |
| 0: Execution access | NEW `r14-agy-ingress` | Register canonical UOS MCP for AGY, materialize a reviewed identity/scope grant, and support admitted plan registration and readback. Demonstrate exact task claim, bounded operations, release, and wrong-identity/expired-authority refusal. |
| 1: Recovery | `t0-coordination`, `r02-recovery-candidate`, `t0a-reconcile` | Diagnose writers and divergence, preserve both coordinator histories, evaluate isolated candidates, independently select lineage, and test fenced cutover/rollback before replacement. |
| 2: Authority and agents | `r03-harness-coordinator`, `r04-identity-enrollment`, `t0b-bindings`, `t0c-conformance` | Bind the harness to selected authority and enroll real AGY/Claude/Codex sessions plus OTP incarnations. Verify heartbeat/ACK, scope, lease, restart and stale-incarnation behavior. |
| 2: Intent contracts | `t2-contracts` | Define algebraic intents, pure decisions and explicit effects; verify identity, deny dominance, replay idempotency, conflict refusal and no authority amplification. |
| 3: MCP data and control | `r05-mcp-data`, `r06-mcp-control` | Replace incompatible bootstrap/store bindings with scoped successor access. Provide bounded catalog/evidence reads and effect-time actor/task/attempt/epoch fencing; reconcile unknown outcomes before retries. |
| 3: Swarm and services | `r07-hive-swarm`, `r08-service-adapters` | Execute a real coordinated task through MCP and Sa-plan; reconcile every in-scope service against data/control endpoints and observed availability. Keep local simulations distinguishable from external bindings. |
| 3: Dashboard | NEW `r15-dashboard-freshness` | Replace the hardcoded risk file with canonical approved assessment lookup. Missing, stale, future or mismatched evidence must yield UNKNOWN and no executable recommendation. |
| 3: Verification | NEW `r16-evidence-verdicts` | Distinguish inventory, execution, verification and admission with typed verdicts. Existing files and unrun artifacts cannot imply passing runtime/formal gates. |
| 4: Acceptance evidence | `r09-end-to-end`, `t3-evidence` | Test actual clients, agents, effects, failures, recovery and dashboard updates against one candidate. Assemble current source-bound logs and formal evidence; supersede incorrect timestamps without rewriting history. |
| 5: Integration | NEW `r17-candidate-integration` | Inventory ownership of the previously observed 711 changed files, preserve concurrent work, isolate JJ changes, review conflicts, and retest the combined candidate. |
| 5: Artifacts | `r10-artifact-sync` | Generate documentation, agent guidance, dashboard, wiki/ZK and completion projections from verified inventory and canonical state. Preserve provenance and refresh changed evidence bindings. |
| 6: Release | `r11-release-review`, `r12-operational-acceptance` | Independently review the final candidate and rollback, perform separately fenced operational acceptance, reconcile every task, and integrate through authorized JJ bookmarks only when gates pass. |

The machine-readable proposal is the detailed amendment specification; Sa-plan alone owns execution state. Its graph preserves original dependencies and adds these constraints: recovery diagnosis plus candidate evaluation before lineage selection; selected lineage before harness routing; actual enrollment before participant bindings; authorized data access before control; dashboard/checklist repairs before end-to-end acceptance; evidence before candidate integration; artifact synchronization before release review.

AGY owns implementation; Codex owns coordination, review and serialized integration. Start with one implementer; allow at most two after disjoint scope/workspace ownership is verified. Recovery, grant publication and integration stay serial. Default to Flash medium, use Flash low for mechanical work, and escalate to Flash high/Pro high only for demonstrated correctness needs. Runs are bounded to 15 minutes and one repair retry before reassessment; actual cost/tokens remain UNKNOWN unless reported by the provider.

Engine 6 Rete-UL rule execution is UNRUN for this journal. The consistency constraints above are documented obligations, not claims of automated enforcement.

## 4. Root Cause Analysis

ACH disconfirmation matrix for the observed planning-registration failure; 0 means consistent, 1 neutral, 2 contradicted. Scores are diagnostic judgments, not probabilities.

| Evidence | H1: Missing task-bound transport authority | H2: Sa-plan unavailable |
|---|---|---|
| Same MCP session returned canonical plan counts | 0 | 2 |
| Mutation returned explicit -32003 authority refusal | 0 | 2 |
| Total disconfirmation score | 0 | 4 |

H1 best explains this recorded refusal. This does not prove that issuing a grant alone repairs coordinator integrity or every execution path.

## 5. Fix Taxonomy

The plan calls for Poka-Yoke typed arguments/evidence, Jidoka refusal on missing fences, and Muda reduction through focused task contexts and bounded model escalation.
Only documentation is changed here; none of the planned repairs is marked implemented by this entry.

## 6. Patterns & Anti-Patterns Discovered

Preserve completed history, bind observations to candidates, and separate model recommendations from actual actor authority.
Devil's Advocate falsification: an empty but existing file must not pass a runtime check; an expired assessment must not recommend execution; an acknowledged model response must not count as a registered worker. These implementation probes remain planned.

## 7. Verification Matrix

Admiralty grades below are scoped reviewer assessments; they do not constitute independent system admission.

| Evidence | Result and scope | Grade |
|---|---|---|
| Existing MCP transcript in handoff receipt | Observed plan counts and registration refusal at 05:30:29Z; not a new probe | B2 |
| Previously executed proposal graph check | 25 unique nodes, no cycles, original 21 tasks/dependencies preserved | B2 |
| AGY handoff | Advisory planning response; barred from certifying implementation or admission | E3 |
| Journal mechanical validation | PASS, exit 0, 10/10 structural checks; command: `bash tools/journal-check docs/journal/20260927-0643-system-mcp-agy-implementation-plan-journal.md`. This does not verify runtime or formal-engine claims. | B2 |
| System tests and formal engines this turn | UNRUN; documentation-only scope | Not graded |

The seven engines are represented as scope/constraints (5/6), ACH (1), source grading (2), falsifiers (4), metrics limits (3), and a future forecast (7). Their runtime execution and full conformance are not implied by section presence.

## 8. Files Modified

| File | Change |
|---|---|
| `docs/journal/20260927-0643-system-mcp-agy-implementation-plan-journal.md` | New 13-section planning journal with stage/task mapping, evidence boundaries and acceptance obligations. |

The referenced design plan, proposal, handoff receipt and implementation sources are unchanged by this journal entry.

## 9. Architectural Observations

Gleam/OTP owns intent admission and supervision; Sa-plan owns tasks/jobs/workflows; Hermes provides bounded evidence/formal services; ZigVM and isolated MAX retain their domain boundaries.
The journal is a projection of the proposal and recorded evidence, not an alternate execution store. No explanatory diagram is introduced.

## 10. Remaining Gaps

P1: usable task-bound UOS ingress, independently reconciled coordinator lineage, actor enrollment and truthful verification remain prerequisites for effects/release.
P2: complete service coverage, dynamic dashboard assessments, candidate integration and artifact synchronization remain planned. The four proposed follow-ups are unregistered. Full-system usability is unverified.

## 11. Metrics Summary

Canonical registration and task completion receive zero credit from this entry. Last-observed counts stay 21 total/4 complete; proposed counts remain 25 total/4 historical completions, pending registration.
Engine 3 Bayesian updating and half-life decay are not computed: there is no new system trial in this documentation action. Old receipts retain their observation dates. Lyapunov dV/dt and orbital stability are UNMEASURED; runtime stability conformance remains unverified rather than being invented to satisfy the journal format.

## 12. STAMP & Constitutional Alignment

All four UCA classes inform acceptance: missing required enrollment, unauthorized effect provision, stale/wrong-order dispatch, and effects continuing beyond lease/revocation. Task packets must bind prevention, detection, rollback, raw FMEA factors and current risk evidence before claiming.
Sa-plan exclusivity, MCP admission, standalone JJ, 0 Bevy, 0 Graphite and storage interlock preservation remain mandatory. No source repair, DB mutation, integration or production action is performed here. EV ceiling stays 93; no new EV is minted.

## 13. Conclusion

The implementation plan is now recorded as a journaled proposal with AGY as executor and Codex as coordinator/reviewer. The existing permission to proceed is preserved; actual implementation still requires functional task-bound MCP ingress, canonical registration/readback and passing task-specific gates. This entry does not close any implementation task.

Forecast precommitment: p = 0.95 that, at Horizon 2026-09-28T06:33:43Z, this journal and its three linked local planning artifacts remain readable and the proposal remains a 25-node acyclic graph. This is an analyst judgment, not a calibrated model estimate. Falsification: any file is absent/unreadable, the proposal no longer has 25 unique nodes, or a cycle exists. Resolve o = 1 only if all conditions hold; otherwise o = 0. Brier score B = (p - o)^2; outcome and score are UNRESOLVED until observation at the horizon. This forecast concerns artifact durability only.

### Comprehensive verification checklist

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — UTC and chrony observation recorded.
- [x] CHK-02-TAIL — Full Tailnet links included; serving not retested.
- [x] CHK-03-FRACT — L0–L9 scope tags present.
- [ ] CHK-04-KM — Wiki/ZK publication remains r10 work.

</details>
<details><summary>Domain 2 — Purity and storage</summary>

- [ ] CHK-05-MUDA — Candidate-wide exclusions not rerun.
- [ ] CHK-06-GRAPH — Runtime/NIF checks not rerun.
- [ ] CHK-07-DRIVE — Hardware interlock execution not performed.

</details>
<details><summary>Domain 3 — Testing and mathematics</summary>

- [ ] CHK-08-C1C8 — Interface acceptance pending.
- [ ] CHK-09-MATH — Formal and measured mathematical gates pending.
- [ ] CHK-10-9MOD — Relevant implementation test modalities pending.
- [ ] CHK-11-REGR — Candidate runtime regressions not rerun.

</details>
<details><summary>Domain 4 — Runtime and observability</summary>

- [ ] CHK-12-GLEAM — Live supervision/identity acceptance pending.
- [ ] CHK-13-HERMES — Runtime formal/evidence acceptance pending.
- [ ] CHK-14-ZIGVM — Runtime acceptance pending where applicable.
- [ ] CHK-15-MAX — Inference acceptance pending where applicable.
- [ ] CHK-16-OTEL — Correlated runtime traces not tested here.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Final-candidate independent admission pending.
- [x] CHK-18-JJ — Standalone JJ preserved; no integration action.

</details>
<details><summary>Domain 6 — Provenance</summary>

EV-94..109 remain NOT_ADMITTED. Historical observations are identified by time; no current runtime or completion credit is inferred.

</details>

[Previous: implementation plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260927-0526-system-mcp-agy-implementation-plan.md) · [Next: proposal](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260927-0526-system-mcp-agy-implementation-proposal.json) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki)

UOS footer: journaled implementation proposal; Sa-plan and admission state unchanged.
