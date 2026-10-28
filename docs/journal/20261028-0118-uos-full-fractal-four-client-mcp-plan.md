# 20261028-0118 — Development harness first: full fractal plan and AGY/Codex/Claude/Pi MCP acceptance journal

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda #checklist-nav #tailscale-web #km-triad

## 1. Scope & Trigger

Operator requests: preserve the complete criticality-based L0–L9 functionality plan in a journal; fully integrate the Gleam harness with AGY, Codex, Claude and Pi; make every required MCP command actually work and retain tests demonstrating that operation.

This is a planning and evidence record, not a task-completion or production-admission certificate. Canonical execution remains Sa-plan. Existing task IDs and histories are reused; new work is registered only where a genuinely missing deliverable needs an independently testable child. No new EV identifier.

Hard acceptance amendment:
- Four real client families, AGY, Codex, Claude and Pi, must each use the actual admitted Gleam/OTP harness.
- Every supported command must demonstrate a successful authorized operation against a real supervised backend in isolated development/staging, with independent response/state/effect evidence.
- Each command also needs invalid-input, missing/expired authority, boundary, timeout/cancellation, replay and recovery tests wherever applicable.
- A declaration, tools/list entry, static acknowledgement, transport-only success, deterministic UNAVAILABLE response, or synthetic adapter reply cannot satisfy positive functional acceptance.
- Legacy mutators require a safe transport-bound typed implementation for authorized use, or an explicit operator-approved retirement. Blanket refusal alone cannot close the all-command requirement.
- Provider/client unavailability and command exclusions remain blocking for FULL_PROFILE_DEV_READY unless scope is explicitly changed by the operator.

Publication scope: additive workspace journal saved under the operator-reaffirmed journal-only local-tool exception. No product source, client configuration, task store, runtime, VCS bookmark or production state is changed by this save. Readback/serving/indexing have separate evidence states.

## 2. Pre-State Assessment

### As-is

| Plan | Total | Completed | Ready | Executing |
|---|---|---|---|---|
| uos/hive-development/20261027-0532 | 31 | 14 | 3 | 1 |
| uos/harness-features/20260909 | 52 | 0 | 1 | 0 |
| uos/telegram-fractal-tests/20261027-0312 | 16 | 1 | 1 | 0 |
| uos/agentic-product/20260907-1837 | 3 | 3 | 0 | 0 |
| uos/ecology/20260909-0146 | 2 | 1 | 1 | 0 |

These are prior fresh read-only MCP observations from this planning session, not current effect-time authority. Each must be reobserved before execution.

Inventory: 52 harness features; product46 contains the same21 infrastructure services and25 additional PM obligations; 17 aspects and18 infrastructure invariants; Telegram136 seed targets with inventory_complete=false; ten dynamic source-census categories. These universes overlap and must not be summed as delivered features.

Current MCP inventory: 65 declared; 12 unavailable; 53 declared-unprobed; effect_authority=false. Only read_file, knowledge_search, sa_plan_status_for and mcp_capability_inventory are exposed to this Codex session.

Source findings:
- .codex/config.toml disables uos_development; its allowlist omits harness_plan_intent.
- planning_intents.gleam already implements CreatePlan/CreateTask/PublishEvidence and typed Applied/Replayed/Refused/Uncertain outcomes; finish acceptance instead of rebuilding it.
- Its three intents do not establish typed dependency/assessment registration support.
- Handover owner of PLANNING_MCP is pi-agent-20261028 attempt4; fresh ownership/lease is not established by the status tool.
- dependability_process.prepare refuses pending registered target authority; bridge catalogs do not establish hostile-code containment.
- Context character estimates and workflow statistics do not establish model-tokenizer limits or protected-context compaction.
- TF-IDF and inspected MAX projection/conflict paths do not establish pinned learned embeddings/model inference; live serving identity remains unknown.
- Telegram tests contain a synthetic success fallback and unmatched-command-to-L9 fallback; correct claim scope and use independent runtime oracles.
- Product task completion does not establish all25 PM capabilities; implementation task links remain absent in the inspected manifest.
- Reported main f8b73da0411b differs from handover receipt808714ecbff9; revision/remote state remains unverified here.
- Session preflight reported untracked tools/validation/verify_guardian.exe. Preserve and inspect provenance; do not delete merely to make the preflight green.

Journal-save host observation:2026-10-28T01:36:18Z; filename prefix20261028-0118 uses UTC hour and seconds. chronyc reports Leap status Normal; system time0.000212723 seconds fast of NTP; reference2026-10-28T01:31:18Z. This is a journal metadata observation, not a task lease, runtime grant or system-admission receipt. Source-to-serving-byte correspondence, complete claim/lease inventory and production state remain UNKNOWN.

## 3. Execution Detail

### Operator priority amendment: DEVELOPMENT HARNESS FIRST

The operator explicitly directs execution until the development-harness goal is complete, with maximum useful parallelization and token-optimized cheaper eligible execution agents. This supersedes any inferred planning-only pause for the requested development scope. It does not mint Sa-plan ownership, a runtime grant, a bootstrap bypass or production authority.

**Primary goal: DEV_HARNESS_FULLY_FUNCTIONAL.** Four actual clients (AGY, Codex, Claude and Pi) use the admitted Gleam/OTP development harness, and every declared development MCP command works with successful authorized behavior and applicable negative/recovery tests. CORE_DEV_READY is an earlier checkpoint; it does not discharge the full four-client development goal.

Broader UOS capability work remains fully recorded below but is deferred from the primary implementation frontier until the development harness is accepted, except a demonstrated dependency needed to make that harness safe and functional. Full replication, standby, advanced cognition and production rollout must not become blanket prerequisites for this bounded development milestone.

#### D0 — Restore and reconcile actual admitted development access
- Reobserve the existing PLANNING_MCP owner/attempt/lease/epoch, pending effects, reviewed grants, source/BEAM identities and synchronized clock.
- Use an already admitted/current authorized launcher to expose the finite successor tools in the actual client. The existing configuration disables this server and omits harness_plan_intent from its allowlist.
- Confirm tools/list matches operations.names, the schema/serving candidate, actual client exposure and declared effect authority.
- No force-claim, expired-owner reuse, direct SQL, broad shell tool or silent host fallback. The journal-only local save exception does not cover product implementation or runtime changes.

#### D1 — Complete typed planning and durable execution acceptance
- Reuse CreatePlan/CreateTask/PublishEvidence and Applied/Replayed/Refused/Uncertain.
- Demonstrate sandbox plan/task/evidence write/readback, stable parent-plan/task/logical-ID replay, changed-payload refusal, bounded outputs and denial-before-effect.
- Renewed grant/attempt and lost-reply scenarios reconcile the original effect; unresolved operation inhibits unsafe sibling work/finish.
- Add missing typed dependency/assessment/task operations only through separately scoped supported Sa-plan APIs.

#### D2 — Make all14 development commands operational
- `harness_plan_intent`
- `harness_status`
- `harness_clock`
- `harness_heartbeat`
- `harness_claim`
- `harness_attach`
- `harness_release`
- `harness_read_file`
- `harness_write_file`
- `harness_build`
- `harness_test`
- `harness_assess`
- `harness_finish`
- `harness_reconcile`

The minimum development positive matrix is14 commands×4 actual clients=56 cells. harness_plan_intent has three operation variants, and every mutator needs state/effect, refusal, replay, failure and recovery variants beyond those56 cells. This is a minimum denominator, not a sufficient test count.

- **harness_plan_intent acceptance:** Each of CreatePlan/CreateTask/PublishEvidence applies and reads back real sandbox state; original logical ID replays without duplicate backend dispatch.
- **harness_status acceptance:** Reports actual canonical task and serving/grant identities; never substitutes static completion or healthy defaults.
- **harness_clock acceptance:** Observes real UTC/monotonic/boot/synchronization domains and declared uncertainty; invalid freshness denies affected effects.
- **harness_heartbeat acceptance:** Renews only the current bound actor/task/attempt/epoch and returns authority evidence; stale/foreign ownership refuses.
- **harness_claim acceptance:** Claims the exact eligible task with trusted scope; concurrent claims admit one current owner; high score cannot bypass dependencies/HOLD.
- **harness_attach acceptance:** Attaches only to a permitted current attempt; wrong identity/epoch/source or another owner's attempt refuses.
- **harness_release acceptance:** Releases the actual owned scope without losing durable uncertain outcomes or granting a stale worker further effects.
- **harness_read_file acceptance:** Reads bounded permitted UTF-8 bytes from the real path with independent readback; missing/escaping/oversized paths are truthful errors.
- **harness_write_file acceptance:** Performs scoped durable sandbox create/edit, verified byte/hash readback and recovery; rejects path/scope drift.
- **harness_build acceptance:** Runs the real pinned candidate build under finite resources, preserving the known-good serving baseline and actual diagnostics.
- **harness_test acceptance:** Executes real assertions on that candidate; a deliberate failing control remains failed and retained rather than manufactured as success.
- **harness_assess acceptance:** Uses the fresh complete portfolio and source/task identity; raw FMEA/four UCAs, dependencies and resource bounds determine truthful eligibility.
- **harness_finish acceptance:** Completes the exact owned task only with required accepted evidence and reconciled effects; missing/stale/HOLD evidence refuses.
- **harness_reconcile acceptance:** Classifies uncertain effects from durable/backend state, preserving logical identity/liability; absence of a reply never proves absence of an effect.

#### D3 — Integrate AGY, Codex, Claude and Pi
- Each actual installed client initializes, discovers all14 tools, uses an enrolled identity and current reviewed finite grant, and reports the loaded UOS policy closure.
- Each executes the positive command matrix on real isolated backends, including build/test/finish and interrupted-worker recovery.
- Exercise all12 directed cross-family handoffs as bounded cases (four families×three other families), recording actual sender/receiver identities, task/effect continuity, non-escalating authority and explicit acknowledgements.
- A Codex sub-agent is not an AGY, Claude or Pi client. A configured but unavailable client remains a blocking integration gap.
- Independent reviewers need their own admitted verification access. Implementers never provide the only oracle or approve their own changes.

#### D4 — Prove supervision, containment and recovery for the development profile
- Observe real OTP/ERTS/process/store identity, restart/queue budgets, worker cancellation/reaping and clean shutdown.
- Inject isolated pre-dispatch, during-effect, post-commit/pre-reply and resumed-attempt faults. Reconcile before retry; preserve finite diagnostics and failed evidence.
- Verify no stale writer, duplicate logical effect, secret disclosure, unbounded worker/queue or false completion.
- Protocol/native failure returns a bounded typed outcome and the next legitimate command still works.

#### D5 — Independently accept the development milestone
- Freeze exact source/build/dependency/client/server/grant identities and required operations.
- Require all four real clients, all14 development tools, all applicable positive/negative/recovery cases, review findings and the declared development SLO/resource bounds.
- No required UNAVAILABLE/UNRUN/UNKNOWN/STALE/HOLD, unresolved effect or conflicting active writer can pass.
- Publish actual evidence and canonical task readback. Record the exact accepted profile; no production admission or full-UOS readiness is inferred.

#### D6 — Pull the broader backlog after the development harness is functional
- Reuse the complete52-feature/21-service/25PM/Telegram crosswalk below.
- The public65-command matrix and other server tools remain explicit broader requirements. Implement safe authorized legacy mutation routes and unavailable backends; do not erase them from discovery to improve counts.
- Any broader command that is an actual prerequisite for D0–D5 is promoted into the development dependency closure with fresh risk evidence.

#### Token-optimized execution policy
- Use cheaper models for bounded execution agents when they have demonstrated capability for the task. For Codex-native bounded readers/executors, gpt-6-luna is the initial low-cost candidate under the user's explicit preference; it still needs runtime availability, applicable eligibility and correctness checks.
- Gleam owns production agent/model routing. Catalog names or native sub-agent selection do not grant harness/provider authority.
- Supply compact task packets: exact task/attempt, paths, interfaces, acceptance/falsifiers, resource/token/retry ceiling and a small relevant evidence set. Prefer isolated minimal context to repeatedly copying the full journal.
- Use deterministic local checks before model calls; reuse valid candidate/scope-bound evidence, compiled artifacts and passing targeted suites.
- Keep max three active workers plus coordinator. Allocate two disjoint implementation lanes and one independent verification/oracle lane; adjust only to measured resource limits.
- Escalate authority, concurrency, evidence-integrity and recovery design/review to a stronger eligible model when a cheaper executor cannot resolve the task within its finite budget. Expensive review must address a concrete uncertainty.
- Preserve exact failures; stop repeated quota/timeout loops; do not add filler agents or duplicate reviews.
- Record actual tokens, latency, retries, useful accepted output and monetary liability. Provider prices/quota and budget eligibility are runtime observations; no claim of zero cost or global optimum.
- Carry token/cost ceilings in canonical task assessments before effects. This journal makes no paid provider call and activates no paid routing.


### To-be

One traceable authorized workflow: requirement → implementation → runtime binding → canonical task → acceptance → runtime/formal evidence → independent verdict. Gleam/OTP owns control and effects; Sa-plan owns task/job/workflow execution; Hermes owns bounded evidence/oracles; ZigVM owns deterministic runtime; isolated MAX/Mojo supplies identified inference. No competing registry/queue, generic shell/eval/SQL escape hatch, unvetted external service, or foreign control plane.

Milestones: CORE_DEV_READY for one frozen development profile; FULL_PROFILE_DEV_READY for every required capability including all four clients and all required MCP commands; production authorization remains separate.

### Approach and criticality

Choose a protected core followed by dependency-ready vertical slices. Immediate whole-backlog implementation expands uncontrolled effects; completing every assurance framework first delays useful feedback. Safety/authority/readiness precede P0/P1/P2/P3 and C×T×F×Dep×I. Raw S/O/Det, all four UCAs, evidence age, uncertainty, rationale, acceptance, rollback and residuals are recorded per task. Unknown factor values stay null with intervals; historical scores are not reused as fresh clearance. No present P0 incident was established by this review.

### Delivery groups

| Group | Deliverable | Exit |
|---|---|---|
| 0 | Reconcile candidate/clock/claims/grants; restore actual client finite successor/planning exposure | Real admitted publication, claim, verification and readback path; no bootstrap bypass |
| 1 | Complete PLANNING_MCP, AGENT_PARITY, SERVICE_VERIFY and HIVE_VERIFY | Independent named CORE_DEV_READY verdict |
| 2 | Freeze/deduplicate complete source-derived inventory and ownership/evidence crosswalk | Every discovered obligation has a disposition and acceptance path; unresolved unknowns explicit |
| 3 | Identity, local fencing, transactional budgets/effects/outbox/audit, containment | Safe local foundations accepted before downstream effects |
| 4 | Infrastructure/PM/operator/Telegram functional slices | Actual interface/backend operations plus independent state/effect oracle |
| 5 | Distributed state/standby/failover/upgrades/advanced cognition/native capabilities | Capability-specific runtime/formal evidence |
| 6 | Cross-system journeys, adverse cases, load/recovery/full command matrix and soak | Independent full-profile acceptance; no required unknown/unresolved outcomes |
| 7 | Serialized standalone JJ integration and reproducible recovery package | Accepted development integration; separately authorized production release |

Groups are reporting envelopes, not global barriers. Source review, pure contract work and independent test design may proceed while unrelated implementation is blocked. Access repair uses an existing authorized finite task and admitted ingress; a historical bootstrap exception cannot create a new direct-tool bypass.

### Execution continuation receipt — current development blocker

Operator goal is active: all MCP commands must work, fully integrated, with token-optimized operations and cheapest eligible execution models. The development harness remains the first functional milestone.

Three bounded native advisory audits used gpt-6-luna (one high-reasoning prerequisite reader, two medium-reasoning client/test readers). These are source investigations, not real AGY/Claude/Pi acceptance or admitted runtime executors. No provider price or claim of global cheapest-model optimality is established.

Independently reconciled source facts:
- operations.names has14 development tools.
- .codex/config.toml has13 development allowlist entries, omits harness_plan_intent and sets uos_development enabled=false.
- Exactly four read-only mcp__uos_gleam tools remain exposed.
- planning_intents.gleam already contains the three-intent implementation. Dated planning projections must not be used to declare it absent.
- Fresh hive summary remains31 total,14 completed,3 ready,1 executing; the summary does not reveal a current transferable task/lease/grant.
- Historical Claude private-stdio receipts and old task-specific grants are not current launch authority for this session.
- Candidate AGY/Pi config path ENOENT/search misses are limited observations, not proof that no integration exists elsewhere.
- Existing successor/authority tests contain useful fixture/negative/replay assertions; no full four-client command matrix or real-backend success is inferred.

Current blocker: no callable mutation/claim/build/test/publication ingress with a current session-bound reviewed grant is available. Journal-only local-tool exception is exhausted by metadata write/readback and does not authorize product/runtime activation. Required unblock is an admitted development launcher/current grant and current canonical task authority, or a separately explicit finite bootstrap-repair authorization followed by independent checks. No direct SQL, unreviewed grant reuse, forced takeover or production action is permitted.

Next finite acceptance packet after unblock: actual-client initialization/tools-list parity; harmless real status/clock/read; current scoped task claim/attach; sandbox typed planning/write/readback; real pinned build/test; denied out-of-scope calls; interrupted transport and durable reconciliation; finish/release with accepted evidence. Expand this through all four actual clients and all14 commands before the development goal is marked complete.

### First vertical slice

1. Reobserve exact task owner/attempt/lease/epoch, host/boot, loaded source/module identity, clock and outstanding effects.
2. Preserve the inherited PLANNING_MCP attempt; transfer/reclaim only through canonical authority.
3. Restore the reviewed finite actual-client tool surface, including the typed planning tool where authorized.
4. Exercise CreatePlan, CreateTask and PublishEvidence in sandbox targets with canonical readback/digests.
5. Verify the65536-byte payload bound, target/path allowlists and rejection of caller-supplied authority/backend/SQL.
6. Reuse the grant-independent parent-plan/task/logical-ID identity; changed payload at the same ID refuses.
7. Interrupt after effect/commit before reply; preserve uncertainty and reconcile before retry.
8. Observe no duplicate logical backend effect across renewed grant/attempt; do not infer universal exactly-once external effects.
9. Add typed graph/assessment operations through supported Sa-plan APIs only where required and separately scoped.
10. Independently review actual client, policy, service and interrupted-worker recovery evidence.

### Fractal allocation

| Layer | Responsibility | Acceptance |
|---|---|---|
| L0 | Constitutional authority, identity, policy, approvals, storage/provenance | Actual boundary refuses unauthorized/expired/revoked/escalating effects |
| L1 | Atomic bytes/paths/clocks/digests/ABI/executable identities | Independent integrity checks and bounded errors |
| L2 | Typed components/discovery/protocol contracts | Real valid operations and truthful invalid/unsupported outcomes |
| L3 | Transactions/tasks/workflows/effects/budgets/inbox-outbox | Durability/fencing/replay/cancellation/uncertainty reconciliation |
| L4 | OTP supervision/isolated workers/queues/shutdown | Observed process identity, containment and bounded recovery |
| L5 | Context/retrieval/inference/rules/forecasts | Identified inputs/models, finite resources and independent quality |
| L6 | Hive collaboration/ownership/handoffs/review | Actual four-client identities, disjoint scope and independent access |
| L7 | Federation/tenant namespaces/transports | Authentication/parity/deduplication/partition and reconnect |
| L8 | Evolution/formal/regression/optimization | Reproducible candidates, falsifiers, useful outcome and rollback |
| L9 | Assurance/composition/readiness/release | Nonvacuous required-child closure and independent candidate verdict |

Children may restrict inherited authority, never enlarge it. A healthy parent does not fill unknown required child evidence.

### Complete52-feature harness crosswalk

#### foundation

- **time.observe — Validated Gleam clock and distinct freshness domains.** Recorded prerequisites: none. Historical stage: EXECUTED. Required acceptance: UTC/boot continuity, offset, uncertainty, reference-age and delivery-age predicates; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **files.read — Bounded UTF-8 file reads through MCP.** Recorded prerequisites: time.observe. Historical stage: EXECUTED. Required acceptance: Bounded reads preserve bytes; invalid encoding/path never yields successful content; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **files.edit — Task-scoped durable development edits.** Recorded prerequisites: files.read, task.lifecycle. Historical stage: IMPLEMENTED. Required acceptance: Expected digest conflict preserves the previous content; exclusive create never overwrites; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **development.build — Pinned Gleam development builds.** Recorded prerequisites: files.edit. Historical stage: IMPLEMENTED. Required acceptance: Actual nonzero/timeout outcomes cannot become passing receipts; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **development.verify — Candidate-bound Gleam acceptance checks.** Recorded prerequisites: development.build. Historical stage: EXECUTED. Required acceptance: Checks preserve actual outcomes and current source identity; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: R2-3: Current effect receipts lack trace_id/span_id; targeted PASS is not universal C3I conformance. R2-7: Canonical completion must be observed after review reconciliation; dispatched prompts are not peer ACKs. Existing acceptance remains incomplete.
- **toolchain.pins — Repository-pinned and usable backend adapters.** Recorded prerequisites: development.build. Historical stage: IMPLEMENTED. Required acceptance: Resolve and functionally probe every invoked adapter against pinned realized repository toolchains; No feature completion from source/catalog presence or historical counts. Historical open finding to revalidate: Known Gleam/JJ/env paths fixed; chronyc/sqlite3/bash remain explicit bootstrap host dependencies

#### authority

- **task.lifecycle — Canonical Sa-plan authority and recoverable completion.** Recorded prerequisites: time.observe. Historical stage: IMPLEMENTED. Required acceptance: One current attempt; completion receipt is recoverable; no independent task store; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **identity.grants — General authenticated agent grants and effect-time fencing.** Recorded prerequisites: task.lifecycle. Historical stage: PLANNED. Required acceptance: Different principals, roles, attempts and expired leases are enforced by authenticated transport; No feature completion from source/catalog presence or historical counts. Historical open finding to revalidate: N10/R2-6: Non-root reviewers are refused by the finite bootstrap grant; no admitted reviewer access path exists. Existing acceptance remains incomplete.
- **tracking.sa_plan — All-feature canonical SQLite task tracking.** Recorded prerequisites: task.lifecycle. Historical stage: IMPLEMENTED. Required acceptance: Every catalog feature has stable canonical task identity and dependencies, with no shadow task store; No feature completion from source/catalog presence or historical counts. Historical open finding to revalidate: R2-4: Legacy in-memory task models and a second MCP server coexist; their non-authoritative scope and migration must be explicit. Existing acceptance remains incomplete.
- **safety.fractal_tps — Fractal TPS, Jidoka and Andon enforcement.** Recorded prerequisites: safety.stpa_fmea, identity.grants. Historical stage: MAPPED. Required acceptance: All four UCA classes, raw FMEA and unauthorized effects are exercised across L0-L9; No feature completion from source/catalog presence or historical counts. Historical open finding to revalidate: Process guidance and source predicates do not prove runtime enforcement

#### supervision

- **otp.supervision — OTP supervision as agent holon runtime.** Recorded prerequisites: task.lifecycle. Historical stage: PLANNED. Required acceptance: Restart intensity and dependency isolation hold under actual faults; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: R2-2: Development MCP is a bare loop with unlinked workers and no uos_sup child; supervised fault recovery is not implemented. Existing acceptance remains incomplete.
- **otp.catalog — Complete installed OTP capability catalog.** Recorded prerequisites: otp.supervision. Historical stage: MAPPED. Required acceptance: Discover every installed OTP service with ownership, roles, resource bounds and actual availability; No feature completion from source/catalog presence or historical counts. Historical open finding to revalidate: R2-1: Atlas lacks an observed OTP/ERTS inventory and capability-specific coverage. Existing acceptance remains incomplete.
- **state.ets — ETS-backed capability state.** Recorded prerequisites: otp.supervision. Historical stage: MAPPED. Required acceptance: Atomic bounded operations preserve declared ownership; ETS is not automatic durable replication; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **supervision.fractal — Multilayer homeostatic supervisors and leveled queues.** Recorded prerequisites: otp.supervision, safety.stpa_fmea. Historical stage: MAPPED. Required acceptance: Observe fault propagation and bounded recovery at each L0-L9 control boundary; No feature completion from source/catalog presence or historical counts. Historical open finding to revalidate: Earlier local loop is not universal ecology autonomy

#### workflow

- **tracking.jobs — Canonical per-feature durable job records.** Recorded prerequisites: tracking.sa_plan. Historical stage: IMPLEMENTED. Required acceptance: Each feature has a content-bound canonical metadata job; actual worker status is separately observed; No feature completion from source/catalog presence or historical counts. Historical open finding to revalidate: Native job rows lack direct plan_id/task_id foreign-key columns; current identity is a checked JSON convention. Existing acceptance remains incomplete.
- **tracking.temporal — Sa-plan Temporal workflow lifecycle and history.** Recorded prerequisites: tracking.sa_plan. Historical stage: IMPLEMENTED. Required acceptance: Start each feature workflow, append digest-bound observations, check replay/conflicts and close only after acceptance; No feature completion from source/catalog presence or historical counts. Historical open finding to revalidate: Local durable workflow history is operational for feature metadata; external Temporal workers and distributed recovery remain unverified. Native workflow rows lack direct plan_id/task_id foreign-key columns; preserve linkage limitations. Existing acceptance remains incomplete.

#### agents

- **peers.review — Actual peer discovery, identity and review receipts.** Recorded prerequisites: task.lifecycle. Historical stage: EXECUTED. Required acceptance: Delivery does not imply peer ACK; uncertain delivery is never automatically retried; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **review.independent — Claude, Fable and AGY comprehensive decision review.** Recorded prerequisites: peers.review. Historical stage: EXECUTED. Required acceptance: Reconcile all D01-D28 and 17 aspects with actual reviewer identity, evidence and corrected inconsistencies; No feature completion from source/catalog presence or historical counts. Historical open finding to revalidate: Full Claude, delegated Fable and AGY reviews are received; reviewer grants, final immutable candidate review and closure of REVISE/UNKNOWN findings remain incomplete.
- **clients.hooks — Cross-agent hooks and policy parity.** Recorded prerequisites: identity.grants. Historical stage: MAPPED. Required acceptance: Every admitted operational surface uses the harness; reminders are not enforcement; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Actual Claude Code2.1.266 SessionStart wiring was validated for UOS and NAS-parent configurations. Agents/Gemini client launch checks remain UNRUN; hooks are advisory and universal no-host-fallback enforcement is absent.
- **agents.superagents — Composable superagents and selective capability activation.** Recorded prerequisites: identity.grants, otp.catalog. Historical stage: PLANNED. Required acceptance: Each authenticated holon discovers full catalog and activates only authorized subsets; No feature completion from source/catalog presence or historical counts. Historical open finding to revalidate: General external holon capability activation unverified

#### telemetry

- **dashboard.ecology — Live ecology dashboard and autonomous-loop observations.** Recorded prerequisites: files.read. Historical stage: EXECUTED. Required acceptance: Observe real cycle progression, errors, actual bindings and capability state without invented completion; No feature completion from source/catalog presence or historical counts. Historical open finding to revalidate: H1: Canonical4100 Live panel renders static demo_events and fixed health/container counters; peer observed2 running containers against16/16 rendered. The4110 ecology surface remains a local loop with no external system bindings. Existing acceptance remains incomplete.
- **dashboard.completion — Truthful feature and completion dashboard.** Recorded prerequisites: tracking.sa_plan, tracking.temporal. Historical stage: PLANNED. Required acceptance: Display canonical per-feature task/job/workflow state, evidence age, gaps and review outcomes; No feature completion from source/catalog presence or historical counts. Historical open finding to revalidate: H2: No deployed live harness feature-completion panel; SQLite projection and report are not a deployed dashboard. Existing acceptance remains incomplete.
- **observability.tracing — C3I trace and span identity in harness intents and receipts.** Recorded prerequisites: task.lifecycle, development.verify. Historical stage: PLANNED. Required acceptance: Generate or validate nonzero128-bit trace_id and64-bit span_id through Gleam-owned ingress; Propagate parent/child identity through intent, native adapter, workflow and result receipts; Test malformed/zero/missing trace identities and replay consistency; Keep trace correlation separate from effect authorization. Historical open finding to revalidate: R2-3: Harness effect receipts have intent_id/signature but lack trace_id/span_id required by the C3I envelope.

#### federation

- **transport.zenoh — Addressed Zenoh transport and MCP semantic parity.** Recorded prerequisites: task.lifecycle. Historical stage: PLANNED. Required acceptance: Two bridges, duplicate delivery, target isolation and correlation-deadline falsifiers pass; No feature completion from source/catalog presence or historical counts. Historical open finding to revalidate: Prefix/correlation mismatch remains
- **ucon.binding — Actual UCon and external ecology bindings.** Recorded prerequisites: identity.grants, models.routing. Historical stage: PLANNED. Required acceptance: Local participant counters cannot stand in for external UCon behavior; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **provenance.vm1 — VM-1 C3I/Indrajaal/ZigVM provenance comparison.** Recorded prerequisites: files.read. Historical stage: MAPPED. Required acceptance: Bind exact read-only source locators, revisions and sanitized evidence without unvetted ingestion; No feature completion from source/catalog presence or historical counts. Historical open finding to revalidate: Earlier comparison receipt does not prove all existing VM-1 services configured in UOS

#### state

- **state.stm — Two-lattice STM and concurrency semantics.** Recorded prerequisites: state.ets. Historical stage: PLANNED. Required acceptance: Committed histories refine the declared serial reference model; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **state.replication — Complete declared state replication.** Recorded prerequisites: state.stm, deployment.roles. Historical stage: PLANNED. Required acceptance: Single writer epoch and committed-prefix replay preserve all declared state; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **replication.failover — Fenced failover and partition recovery.** Recorded prerequisites: deployment.standby. Historical stage: PLANNED. Required acceptance: Primary loss and partition drills preserve one writer and unresolved liabilities; No feature completion from source/catalog presence or historical counts. Historical open finding to revalidate: Recovery and split-brain controls UNRUN

#### inference

- **ml.max — Isolated MAX/Mojo inference service.** Recorded prerequisites: otp.supervision. Historical stage: MAPPED. Required acceptance: Shape, numeric tolerance, resources and failure isolation match contract; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **models.daily_budget — Aggregate OpenRouter ten-dollar daily liability ledger.** Recorded prerequisites: task.lifecycle, time.observe. Historical stage: MAPPED. Required acceptance: Admitted liabilities do not exceed USD10/day; uncertain spend remains reserved; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **models.coding — Paid GLM, Kimi and DeepSeek coding models.** Recorded prerequisites: models.daily_budget, verification.environment. Historical stage: IMPLEMENTED. Required acceptance: Route only by verified eligibility, budget and measured task quality; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **models.decision — Gemma 4 decision model eligibility.** Recorded prerequisites: models.daily_budget, verification.environment. Historical stage: IMPLEMENTED. Required acceptance: Advice cannot grant effect authority; quality remains evaluation-bound; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **models.routing — Need-based adaptive OpenRouter engine.** Recorded prerequisites: models.coding, models.decision. Historical stage: IMPLEMENTED. Required acceptance: Feasible routes satisfy capability/privacy/budget constraints before utility ranking; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established

#### knowledge

- **knowledge.triad — Linked journal, wiki, ZK and KM artifacts.** Recorded prerequisites: files.edit. Historical stage: MAPPED. Required acceptance: Projections preserve provenance, scope, source identity and unknowns; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Full Fable rows and grouped journal/wiki/ZK artifacts now exist; global KM ingestion, index reconciliation and serving-byte verification remain unverified.

#### formal

- **formal.lean — Lean formal evidence service.** Recorded prerequisites: development.verify. Historical stage: MAPPED. Required acceptance: No missing tool, timeout, sorry or undeclared axiom counts as proof; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **formal.quint — Quint temporal modelling service.** Recorded prerequisites: development.verify. Historical stage: MAPPED. Required acceptance: Bounds and actual invariant/counterexample outcomes remain explicit; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **formal.specification — Denotational specification and implementation conformance.** Recorded prerequisites: files.edit, review.independent. Historical stage: PLANNED. Required acceptance: Map every normative SHALL and scenario to an implemented operation or explicit gap; Reconcile duplicate task models/MCP servers and the scoped bootstrap exception; Verify each claimed state transition and formal invocation at an exact candidate. Historical open finding to revalidate: R2-4/R2-6: Normative universal control and no-host-fallback requirements exceed implemented scope; legacy authority surfaces need explicit reconciliation.
- **formal.algebraic_atlas — Machine-checkable algebraic atlas and installed OTP inventory.** Recorded prerequisites: formal.specification, development.verify. Historical stage: PLANNED. Required acceptance: Encode the specification's nine algebraic structures with capability-specific domains, composition, laws and falsifiers; Replace repeated generic law/oracle strings with typed machine-checkable contracts and independent oracles; Observe the installed OTP/ERTS capabilities and map each to status/authorization/evidence; No source-only registry entry grants formal verification or admission. Historical open finding to revalidate: R2-1: Current atlas is a partial capability registry; repeated law/oracle strings and absent installed OTP inventory do not encode the claimed algebra.

#### cognition

- **probability.bayesian — Bayesian inference capabilities.** Recorded prerequisites: development.verify. Historical stage: PLANNED. Required acceptance: Normalized posterior and declared approximation/calibration bounds; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **rules.rete_ul — Rete-UL rule evaluation with independent oracle.** Recorded prerequisites: development.verify. Historical stage: PLANNED. Required acceptance: Incremental result equals independent full recomputation including retraction; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: R2-5: Reviewer found no complete Rete-UL implementation; semantic fixtures must not be credited as the full algorithm. Existing acceptance remains incomplete.
- **safety.stpa_fmea — STPA and FMEA risk controls.** Recorded prerequisites: task.lifecycle, formal.quint. Historical stage: MAPPED. Required acceptance: All four UCA classes and raw FMEA remain distinct; score never grants authority; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **twins.model — Formal modelling and calibrated digital twins.** Recorded prerequisites: formal.lean, formal.quint. Historical stage: PLANNED. Required acceptance: Twin validity is scoped by calibration, observation age and declared assumptions; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **ruliad.explore — Bounded ruliad exploration.** Recorded prerequisites: models.routing. Historical stage: PLANNED. Required acceptance: Explicit finite step/node/memory bounds; no claim to realize the entire mathematical ruliad; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **flight.f_prime — F Prime modelling and runtime integration.** Recorded prerequisites: development.verify. Historical stage: PLANNED. Required acceptance: Projection is not authoritative until official toolchain validation; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established

#### acceleration

- **native.mojo_generated — Gleam-authored Mojo/MAX acceleration.** Recorded prerequisites: development.verify, ml.max. Historical stage: PLANNED. Required acceptance: Generated implementation refines independent Gleam interpretation; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **native.ocaml — Gleam-authored native OCaml acceleration.** Recorded prerequisites: development.verify, formal.lean. Historical stage: MAPPED. Required acceptance: FFI ownership, runtime locks and lifetime preserve Gleam semantics; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established

#### release

- **deployment.roles — Isolated development, production and standby roles.** Recorded prerequisites: otp.supervision. Historical stage: PLANNED. Required acceptance: Code/tests run only in dev and production accepts only verified release artifacts; No feature completion from source/catalog presence or historical counts. Historical open finding to revalidate: Three-role deployment not observed
- **release.recovery — Release migration, rollback and forward recovery.** Recorded prerequisites: deployment.roles, development.verify. Historical stage: PLANNED. Required acceptance: Rehearse incompatible state, failed upgrade, rollback and non-reversible effect reconciliation; No feature completion from source/catalog presence or historical counts. Historical open finding to revalidate: Release recovery UNRUN
- **release.dynamic — Tested dynamic OTP upgrades.** Recorded prerequisites: state.replication, release.recovery. Historical stage: PLANNED. Required acceptance: Upgrade preserves migration relation or fails into tested recovery; Exercise authorized MCP path and failure/replay behavior at the same source identity; Bind fresh actual runtime and formal evidence; reconcile reviewer findings before feature completion. Historical open finding to revalidate: Complete MCP binding and candidate-bound end-to-end acceptance are not established
- **deployment.standby — Production standby instance and release parity.** Recorded prerequisites: deployment.roles, state.replication. Historical stage: PLANNED. Required acceptance: Observe both production instances with matching admitted release and replicated committed prefix; No feature completion from source/catalog presence or historical counts. Historical open finding to revalidate: No verified standby observation

#### environment

- **verification.environment — Environment and tool evaluation suite.** Recorded prerequisites: development.verify. Historical stage: EXECUTED. Required acceptance: Re-run Gleam, OCaml, Mojo, Lean, Quint, STM, Bayesian, Rete and STPA/FMEA controls through harness; No feature completion from source/catalog presence or historical counts. Historical open finding to revalidate: R2-5: Rete semantic cases do not establish Rete-UL algorithm coverage. Existing acceptance remains incomplete.

Recorded52-feature graph: all dependency references resolve; no cycles; nine structural waves. This is not verification of the combined live cross-plan graph or effect authority. Add source-backed safety dependencies before claims.

### Complete21-service infrastructure crosswalk

#### security

- **AINF-S01/AINF-R01: Cryptographic workload IAM.** Validate workload certificate/JWT signature, issuer, audience, tenant binding, not-before, expiry, revocation epoch and proof of possession at every ingress. Rotate short-lived identities; fail closed on unknown trust roots. A SPIFFE-shaped identifier alone SHALL NOT authenticate a caller.
  Sources: `apps/cepaf_gleam/src/cepaf_gleam/iam/supervisor.gleam`, `apps/cepaf_gleam/src/cepaf_gleam/iam/jwks_cache_actor.gleam`.
  Acceptance: AINF-T01-1: Accept an enrolled workload using the admitted trust bundle.; AINF-T01-2: Reject forged, expired, wrong-audience and cross-tenant identities.; AINF-T01-3: Rotate roots with a bounded overlap; reject a revoked identity before its former expiry..
- **AINF-S02/AINF-R02: RBAC / ABAC / PBAC.** Compute effective permission as the intersection of initiating principal, workload, delegation chain, tenant policy, resource ACL and environmental restrictions. Explicit deny dominates; missing attributes, stale policies, evaluator errors and timeouts deny. Rete recommendations cannot grant authority.
  Sources: `apps/cepaf_gleam/src/cepaf_gleam/auth/rbac.gleam`, `apps/cepaf_gleam/src/cepaf_gleam/rules/engine.gleam`.
  Acceptance: AINF-T02-1: Permit a registered read tool for an authorized tenant principal.; AINF-T02-2: Deny when any grant is absent even if the workload has administrative privileges.; AINF-T02-3: Revoke a policy while a request is queued; reject its stale authorization at dispatch..
- **AINF-S03/AINF-R03: Principal propagation and delegated authorization.** Carry the initiating principal and ordered actor chain through every handoff. Issue audience-specific, short-lived down-scoped credentials through the existing IAM boundary; enforce maximum depth, expiry and revocation. Exchange source and upstream tokens remain opaque to models and ordinary logs.
  Sources: `apps/cepaf_gleam/src/cepaf_gleam/auth/token_exchange.gleam`, `apps/cepaf_gleam/src/cepaf_gleam/iam/sts_token_cache_actor.gleam`.
  Acceptance: AINF-T03-1: Exchange to a narrower audience and scope for the same principal and tenant.; AINF-T03-2: Reject cyclic chains, depth overflow, scope escalation and confused-deputy token reuse.; AINF-T03-3: Revoke the root delegation and demonstrate invalidation of cached descendants..
- **AINF-S04/AINF-R04: Ephemeral secret and credential broker.** Issue opaque credential lease references bound to tenant, subject, tool, endpoint, request digest, epoch and expiry. Inject secret bytes only at the isolated adapter boundary, scrub inheritance and perform verified cleanup. No secret bytes, secret hashes, refresh tokens or private keys enter prompts, retained audit payloads or specification artifacts.
  Sources: `apps/cepaf_gleam/src/cepaf_gleam/vault.gleam`, `apps/cepaf_gleam/src/cepaf_gleam/vault_supervisor.gleam`, `engines/hermes/modules/hermes_dependability/dependability_credential.mli`.
  Acceptance: AINF-T04-1: Obtain a lease and use it only for the bound tool and endpoint.; AINF-T04-2: Reject lease replay after expiry, tenant mismatch, cancellation or revocation.; AINF-T04-3: Scan model inputs, telemetry and replay records to prove fixture secrets are absent..
- **AINF-S05/AINF-R05: Input, output and tool guardrails.** Separate trusted policy from untrusted retrieved/tool content, enforce typed schemas and size limits, and redact classified fields before export. Combine deterministic controls with separately evaluated advisory classifiers. Prompt text, classifier approval or SQL substring filtering alone SHALL NOT authorize effects or replace parameterized SQL.
  Sources: `apps/cepaf_gleam/src/cepaf_gleam/vault_pii_scrub.gleam`, `engines/hermes/modules/system_engg/agent_dispatch_hook.ml`.
  Acceptance: AINF-T05-1: Retain an adversarial retrieved document as untrusted data while rejecting its requested privileged action.; AINF-T05-2: Reject NUL, malformed JSON and oversized arguments before adapter invocation.; AINF-T05-3: Redact seeded PII/credentials and quarantine a schema-invalid model result even after HTTP 200..

#### durability

- **AINF-S08/AINF-R08: Asynchronous agent messaging and event bus.** Use Zenoh as the UOS backplane with explicit per-tenant namespace ACLs, persistent transactional outbox/inbox, deduplication keys, bounded mailbox depth, acknowledgements, retry policy and dead letters. Define ordering per workflow, not globally. Internal messages are not claims of external A2A protocol conformance.
  Sources: `apps/cepaf_gleam/src/cepaf_gleam/bridge/zenoh_mcp.gleam`, `apps/uos_tui/src/uos_tui/board.gleam`.
  Acceptance: AINF-T08-1: Deliver a durable message after a broker disconnect and restart.; AINF-T08-2: Redeliver duplicates without duplicating an admitted effect; reject cross-tenant subscription.; AINF-T08-3: Saturate one mailbox and observe backpressure/dead letters without starving a second tenant..
- **AINF-S09/AINF-R09: Session state and scratchpads.** Keep volatile working state in protected OTP/ETS partitions keyed by tenant, principal, session and authorization epoch, with item and byte quotas and TTLs. Durable checkpoints are referenced through Hermes. Cache contents cannot be authoritative for quota, approval, lease or completed-effect recovery.
  Sources: `apps/cepaf_gleam/src/cepaf_gleam/substrate/beam_cache.gleam`, `apps/cepaf_gleam/src/cepaf_gleam/ha/context_cache.gleam`.
  Acceptance: AINF-T09-1: Read and update an owned session within byte and item bounds.; AINF-T09-2: Reject guessed identifiers, expired sessions and a cache entry after policy-epoch change.; AINF-T09-3: Restart a session actor and recover only authorized checkpoint data; never reset durable spend..
- **AINF-S14/AINF-R14: Durable workflow and transaction orchestration.** Use Sa-Plan leases and Hermes WAL transactions to persist workflow events, step intent, budget reservation and outbox atomically. Keep nondeterministic model/tool outcomes in versioned history and replay the pure transition function. Use idempotency keys for retryable effects and an explicit reconciliation state for ambiguous non-idempotent outcomes; compensation is an authorized action, not automatic reversal.
  Sources: `apps/cepaf_gleam/src/cepaf_gleam/planning/sa_plan_bridge.gleam`, `apps/cepaf_gleam/src/cepaf_gleam/sdlc/sa_plan_engine.gleam`, `engines/hermes/modules/sa_plan/sa_plan_store.ml`, `engines/hermes/modules/sa_plan/sa_plan_temporal.ml`.
  Acceptance: AINF-T14-1: Kill the worker at every intent/effect/receipt boundary and recover committed workflow state.; AINF-T14-2: Replay completed model/tool steps from recorded outcomes without calling providers again.; AINF-T14-3: Fence a stale writer and reconcile an effect whose remote success was not durably acknowledged..

#### approval_budget_audit

- **AINF-S15/AINF-R15: Human approval and escalation gateway.** Persist approvals bound to tenant, initiating principal, approver authority, exact canonical action digest, policy version, cost ceiling, expiry, lease epoch and a single-use nonce. Resume with current authorization and budget checks. Approval cannot override constitutional storage or scope denials; stale, altered or replayed approvals fail closed.
  Sources: `apps/cepaf_gleam/src/cepaf_gleam/fractal/l0_constitutional.gleam`, `engines/hermes/modules/sa_plan/guardian.ml`, `engines/hermes/modules/hermes_dependability/dependability_approval_crypto.ml`.
  Acceptance: AINF-T15-1: Pause a policy-designated high-impact action and resume exactly the approved request.; AINF-T15-2: Reject altered payloads, cross-tenant approvers, expired approval and nonce replay.; AINF-T15-3: Cancel a waiting workflow, then prove a delayed approval cannot dispatch it..
- **AINF-S19/AINF-R19: Cost, quota and budget enforcement.** Maintain integer micro-unit monetary and token/resource budgets with durable compare-and-swap reservation, settlement and refund records. Scope global, tenant, principal and workflow limits and enforce all simultaneously. Concurrent attempts reserve before dispatch; cancellation retains uncertain liability until reconciliation. Unknown pricing or usage fails closed for additional spend.
  Sources: `apps/cepaf_gleam/src/cepaf_gleam/ha/token_budget.gleam`, `apps/uos_tui/src/uos_tui/coord.gleam`, `engines/hermes/modules/sa_plan/sa_plan_store.ml`.
  Acceptance: AINF-T19-1: Race concurrent requests at an exact tenant/global budget boundary and prevent oversubscription.; AINF-T19-2: Charge hedges/retries and settle duplicate usage receipts once.; AINF-T19-3: Restart/fail over the quota owner without resetting balances or releasing an ambiguous in-flight reservation..
- **AINF-S20/AINF-R20: Immutable audit and compliance evidence.** Use the existing authoritative Hermes SQLite WAL evidence plane with a fenced single writer, append-only API and cryptographic chaining of canonical redacted records. Anchor chain heads outside the writer's trust domain; verify backup restoration and retention. Describe guarantees as tamper evidence with a stated threat model, not absolute tamper proofing. Persistence failure blocks new effects.
  Sources: `engines/hermes/modules/hermes_harness/evidence_store.ml`, `engines/hermes/modules/hermes_dependability/dependability_writer_lease.ml`.
  Acceptance: AINF-T20-1: Detect modification, omission, reordering and a truncated tail against an independently stored checkpoint.; AINF-T20-2: Refuse a dispatch when the ledger is unwritable, full or its writer lease is stale.; AINF-T20-3: Restore an encrypted backup, verify chain/sequence/tenant isolation and execute a documented retention procedure..

#### execution

- **AINF-S06/AINF-R06: Agent naming, registry and discovery.** Register versioned capability descriptors with tenant visibility, schema and implementation digests, endpoint identity, supported protocols, lease expiry, health evidence and capacity. Discovery returns authorized, compatible and freshly leased candidates; discovery never grants execution authority.
  Sources: `apps/cepaf_gleam/src/cepaf_gleam/ontology/adk_c3i_master_ontology.gleam`, `apps/uos_tui/src/uos_tui/swarm.gleam`.
  Acceptance: AINF-T06-1: Discover two compatible authorized workers and select one with available capacity.; AINF-T06-2: Exclude expired, incompatible, unhealthy and other-tenant descriptors.; AINF-T06-3: Change a tool/schema digest after planning and require re-resolution and authorization..
- **AINF-S07/AINF-R07: MCP and dynamic tool gateway.** Normalize admitted MCP, OpenAPI and internal MoZ calls into one typed invocation envelope. Negotiate pinned protocol versions; validate argument/result schemas, identity, deadline, payload bound, egress target and idempotency at the same boundary. HTTP auth, stdio framing and Zenoh ACLs remain distinct transport contracts; unknown protocol versions fail closed.
  Sources: `apps/cepaf_gleam/src/cepaf_gleam/mcp/protocol.gleam`, `apps/cepaf_gleam/src/cepaf_gleam/mcp/server.gleam`, `apps/cepaf_gleam/src/cepaf_gleam/bridge/zenoh_mcp.gleam`.
  Acceptance: AINF-T07-1: Invoke an admitted read tool through two transports and compare normalized outcomes and trace bindings.; AINF-T07-2: Reject unsupported versions, schema drift, unauthorized redirects and wrong token audiences.; AINF-T07-3: Cancel or time out a real worker and reap its process tree; never retry a non-idempotent ambiguous call..
- **AINF-S13/AINF-R13: Isolated sandbox and bounded execution.** Route admitted deterministic programs to ZigVM and hostile host-tool execution to an independently isolated Hermes-Bionic process/container profile. Verify filesystem, privilege, network, CPU, memory, PID, output and wall-time limits before dispatch; cancel and reap descendants. Neither an OTP actor nor descriptor-relative VFS alone is a host-code security sandbox. Preserve the host OS storage interlock.
  Sources: `apps/cepaf_gleam/src/cepaf_gleam/harness/hermes_bionic_bridge.gleam`, `engines/hermes/modules/hermes_dependability/dependability_process.mli`, `engines/zigvm/build.zig`.
  Acceptance: AINF-T13-1: Run a bounded admitted task and retain a sanitized result with the sandbox profile digest.; AINF-T13-2: Attempt path escape, symlink race, credential mount access, forbidden egress and resource exhaustion; require containment.; AINF-T13-3: Deny execution when isolation attestation is absent and verify descendant cleanup after timeout..
- **AINF-S16/AINF-R16: Circuit breakers, anti-loop controls and dead letters.** Enforce maximum steps, delegation depth, repeated semantic tool signatures, no-progress window, absolute deadline and aggregate retry allowance. Apply tenant/provider circuit breakers with bounded half-open probes. On exhaustion, revoke pending dispatch permits and store a redacted, quota-bounded dead letter; stochastic hallucination detection remains an evaluated signal.
  Sources: `apps/cepaf_gleam/src/cepaf_gleam/prajna/circuit_breaker.gleam`, `apps/cepaf_gleam/src/cepaf_gleam/ha/freshness_monitor.gleam`.
  Acceptance: AINF-T16-1: Terminate a repeated tool loop within the configured count without another effect.; AINF-T16-2: Open a failing provider breaker, permit one half-open probe and avoid a retry storm.; AINF-T16-3: Show malformed or negative limits are rejected and one tenant's failures do not open another tenant's local breaker..

#### cognition

- **AINF-S10/AINF-R10: Vector retrieval and long-term memory.** Extend the Hermes retrieval substrate with versioned embeddings produced only by admitted MAX inference. Authorize tenant, principal ACL, time bounds, retention and residency before scoring and again before release. Bind model, dimension, tokenizer, corpus and index revisions to every result; treat indexes as rebuildable projections.
  Sources: `engines/hermes/modules/hermes_wiki/src/graph/wiki_similarity.ml`, `apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_knowledge_runtime.gleam`.
  Acceptance: AINF-T10-1: Retrieve authorized evidence with source citations and model/index revision bindings.; AINF-T10-2: Exclude other-tenant and revoked documents before top-k selection and on final return.; AINF-T10-3: Rebuild an index and verify recall against a pinned labeled corpus; do not label TF-IDF as neural embeddings..
- **AINF-S11/AINF-R11: Knowledge graph and ontology.** Use the existing KM triad and typed Hermes/BEAM graph operations. Enforce authorization on every vertex, edge and derived fact, track provenance and cap traversal depth/result size. Inference may propose relationships; only validated evidence can become authoritative facts or permission inputs.
  Sources: `engines/hermes/modules/hermes_wiki/src/graph/wiki_graph.ml`, `apps/cepaf_gleam/src/cepaf_gleam/ontology/adk_c3i_master_ontology.gleam`.
  Acceptance: AINF-T11-1: Resolve an authorized multi-hop relation with complete provenance.; AINF-T11-2: Reject a traversal through a hidden intermediary and prevent inferred permission escalation.; AINF-T11-3: Withdraw source evidence and invalidate dependent graph facts and caches..
- **AINF-S12/AINF-R12: Context routing, compaction and memory budget.** Assemble context using the selected model's admitted tokenizer and explicit input/output reservations. Preserve immutable policy, task constraints, delegation/approval references, unresolved tool pairs and evidence identifiers. Summaries remain versioned, untrusted derivatives with source references; fail if protected context cannot fit instead of dropping constraints.
  Sources: `apps/cepaf_gleam/src/cepaf_gleam/ha/context_manager.gleam`, `apps/cepaf_gleam/src/cepaf_gleam/ha/token_budget.gleam`, `apps/cepaf_gleam/src/cepaf_gleam/ha/workflow_compactor.gleam`.
  Acceptance: AINF-T12-1: Compact an over-budget session while preserving protected entries and tool-call/result pairing.; AINF-T12-2: Reject negative token counts, model/tokenizer mismatch and protected content exceeding capacity.; AINF-T12-3: Compare pre/post-compaction task answers on a pinned corpus and reject lost safety constraints..
- **AINF-S17/AINF-R17: Model gateway, routing, failover and cache.** Route through UOS Gleam policy to admitted MAX or already admitted provider adapters whose manifest satisfies tenant policy, model capabilities, residency, context and cost limits. Reserve worst-case spend per attempt including hedges before dispatch. Cache only eligible sanitized results with complete tenant/principal/policy/model/context bindings; default semantic cache off. Static acknowledgements cannot count as successful inference.
  Sources: `apps/cepaf_gleam/src/cepaf_gleam/bridge/pi_provider.gleam`, `apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/inference_api.gleam`, `services/inference/max/max_worker.py`.
  Acceptance: AINF-T17-1: Invoke a real pinned inference backend and verify tokenizer usage and structured result against evidence.; AINF-T17-2: Fail over only to an authorized compatible provider with a fresh reservation; reject forbidden residency.; AINF-T17-3: Demonstrate no cache reuse across tenants, ACL epochs, tool schemas, corpus versions or model changes..

#### evaluation

- **AINF-S18/AINF-R18: Step-level tracing and semantic telemetry.** Emit correlated W3C spans and C3I coordinates for authorized decisions, routing, retrieval, compaction, approvals, attempts, results, usage and eval verdicts. Record observable actions and concise redacted rationale/evidence references; exclude hidden chain-of-thought, secrets and unrestricted raw context. Distinguish transport success, task success and admission. Telemetry loss cannot rewrite authoritative evidence.
  Sources: `apps/cepaf_gleam/src/cepaf_gleam/ha/trace_context.gleam`, `apps/cepaf_gleam/src/cepaf_gleam/agui/sse.gleam`, `contracts/evidence/c3i_fractal_observability_spec.json`.
  Acceptance: AINF-T18-1: Reconstruct a multi-step trajectory across transports using valid nonzero trace/span IDs.; AINF-T18-2: Return HTTP 200 with a semantically wrong answer and record task failure independently.; AINF-T18-3: Drop telemetry under load while preserving the durable audit chain and admitting no unaudited effect..
- **AINF-S21/AINF-R21: Continuous evaluation, regression and red teaming.** Extend Hermes differential evaluation with pinned datasets, prompts, model/tokenizer versions, policy snapshots and deterministic control oracles. Score task success, groundedness, tool/approval correctness, injection resistance, isolation, context preservation, latency and spend. Separate deterministic contract checks from stochastic model measurements; require regression thresholds and confidence intervals before a controlled rollout.
  Sources: `engines/hermes/modules/hermes_harness/test_parity_algebra.ml`, `engines/hermes/modules/hermes_harness/test_parity_compare.ml`, `apps/cepaf_gleam/src/cepaf_gleam/testing/coverage_math.gleam`.
  Acceptance: AINF-T21-1: Run held-out normal and adversarial trajectories and reject a deliberately wrong but syntactically valid response.; AINF-T21-2: Introduce policy, cache-isolation, compaction and quota mutants and observe failing gates.; AINF-T21-3: Mark missing judge/backend, empty datasets, stale receipts and unavailable formal tools UNRUN or UNKNOWN, never PASS..

Local single-writer fencing, durable budget/audit conservation, transactional intent/reservation/outbox and ambiguous-result reconciliation precede effects; full replication/standby follow later. Full failover additionally requires partition fencing, revocation propagation and preservation of uncertain effects/spend.

### Complete25-PM crosswalk

#### identity

- **PM-01: Product definition and outcomes.** Product specifications SHALL preserve a stable identity, purpose, stakeholder/source, outcome hypothesis, metric definition, scope and explicit unknowns. Historical gap to revalidate: Business outcome and customer-feedback lifecycle is not fully represented by the engineering catalogs. Sources: `engines/hermes/modules/hermes_harness/feature_catalog.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.
- **PM-02: Feature hierarchy and ownership.** Every required feature SHALL have one containment parent and stable semantic identity; cross-relations SHALL NOT create extra parents or cycles. Historical gap to revalidate: The inspected external product hierarchy tables are empty; candidate-bound graph completion needs a collector. Sources: `engines/hermes/modules/hermes_harness/fractal_catalog.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.
- **PM-03: Typed feature definition and use cases.** A feature SHALL preserve ID, category, behavior, use case, control references, scenario references, declared state and observed evidence separately. Historical gap to revalidate: InfraNodus metadata tests do not execute every referenced scenario. Sources: `engines/hermes/modules/hermes_wiki/import/zigvm/code/infranodus/infranodus_feature.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.
- **PM-04: Requirements and contract ownership.** Each requirement SHALL have a stable ID, shall statement, owner, contract/formal method, runtime acceptance and source reference. Historical gap to revalidate: Formal ownership/registration must be distinguished from checked proof. Sources: `engines/hermes/modules/hermes_harness/contract_catalog.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.

#### execution

- **PM-07: Sa-plan execution linkage.** Plans, tasks, jobs and workflows SHALL remain in canonical Sa-plan; catalog rows SHALL carry references only. Historical gap to revalidate: Two-database observation is not atomic effect-time fencing. Sources: `engines/hermes/modules/sa_plan/sa_plan_store.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.
- **PM-21: Risk and dependency prioritization.** Selection SHALL apply safety class and readiness before C×T×F×Dep×I and record all four UCAs, raw FMEA and current evidence. Historical gap to revalidate: Legacy wiki numeric priorities and onto_task repair records remain advisory. Sources: `engines/hermes/modules/sa_plan/sa_plan_management.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.
- **PM-22: Desired-state reconciliation.** Reconciliation SHALL preserve explicit desired/actual states, unknown targets, dependency cycles and non-vacuous convergence. Historical gap to revalidate: Never route a converged advisory model directly to deployment. Sources: `engines/hermes/modules/hermes_harness/blueprint.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.

#### evidence

- **PM-06: Traceability across engineering artifacts.** Typed artifact links SHALL preserve role, origin, digest and revision and resolve to an artifact version. Historical gap to revalidate: Graph completeness and semantic validity require more than foreign keys. Sources: `engines/hermes/modules/hermes_harness/reference_artifacts.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.
- **PM-08: Truthful feature state.** Declared, mapped, implemented, tested, verified and admitted observations SHALL remain distinguishable; missing evidence SHALL NOT imply completion. Historical gap to revalidate: Legacy register can return Built when no probe exists. Sources: `engines/hermes/modules/hermes_wiki/src/register/feature_register.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.
- **PM-09: Versioned change history.** An identical object/version replay SHALL be idempotent and a changed payload at that identity SHALL be rejected; new versions retain prior history. Historical gap to revalidate: Administrative replacement of a SQLite file remains outside ordinary API protection. Sources: `engines/hermes/modules/hermes_harness/evidence_store.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.
- **PM-10: SQLite artifact body storage.** Generated/user artifact bodies SHALL be stored with media kind, SHA-256, source locator and immutable revision; source-code oracles remain reference-only. Historical gap to revalidate: External sources must not be copied before quiescence, sanitization and two-key admission. Sources: `engines/hermes/modules/hermes_harness/evidence_store.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.
- **PM-12: Evidence retention at claim granularity.** Per-case assertions SHALL retain per-case evidence; aggregate logs SHALL remain labeled aggregate; absence SHALL remain unknown. Historical gap to revalidate: The new manifest defines acceptance cases; it does not synthesize their execution receipts. Sources: `engines/hermes/modules/hermes_harness/parity_ledger.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.
- **PM-13: Strict product completion.** Completion SHALL require every required child and matching candidate, reference, scenario, normalizer, runtime and formal receipt; empty sets SHALL NOT pass. Historical gap to revalidate: Existing low-level Boolean readers are insufficient alone. Sources: `engines/hermes/modules/hermes_harness/evidence_rollup.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.

#### oracle

- **PM-14: Oracle inventory and provenance.** Oracles SHALL distinguish specification, source, executable, recorded fixture and advisory model roles and preserve origin, owner and revision. Historical gap to revalidate: Generic recursive inventory is not a sanitized UOS ingestion policy. Sources: `engines/hermes/modules/hermes_harness/inventory.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.
- **PM-15: Oracle pin, license and executable identity.** An oracle execution SHALL bind full source revision, dirty-state receipt, license, build/toolchain, executable identity and observation time. Historical gap to revalidate: OTP-major equality plus Git HEAD is not exact executable provenance. Sources: `engines/hermes/modules/hermes_harness/reference_capture.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.
- **PM-17: Bounded oracle execution.** Execution SHALL enforce deadline, memory/output/process limits, sanitized environment and egress policy and reap the full process tree. Historical gap to revalidate: Legacy Reference_capture only kills the direct child and does not establish these limits. Sources: `engines/hermes/modules/hermes_dependability/dependability_process.mli`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.
- **PM-18: Normalization and fixture identity.** Normalizer identity and rules SHALL be versioned with the fixture; load SHALL verify full scenario, snapshot and content identity. Historical gap to revalidate: Reference_capture.load presently does not compare all requested identity fields. Sources: `engines/hermes/modules/hermes_harness/parity_normalizer.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.
- **PM-19: Differential verdict and divergence handling.** Comparison SHALL retain both normalized observations, comparator version and locality; unavailable or vacuous results SHALL never become equivalent. Historical gap to revalidate: Service-level differential runs remain UNRUN in this review. Sources: `engines/hermes/modules/hermes_harness/parity_compare.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.

#### regression

- **PM-16: Oracle recipe discovery and coverage.** Each discovered vector SHALL have a typed bounded execution recipe or explicit nonpassing reason; no fixture may disappear from the denominator. Historical gap to revalidate: Current service oracle registrations need executable differential adapters. Sources: `engines/hermes/modules/hermes_harness/capability_catalog.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.
- **PM-20: Regression, mutation and adversarial evidence.** Regression and mutation records SHALL retain candidate, inputs, expected law, observed result and killed/surviving/unrun status. Historical gap to revalidate: Full imported suites and production chaos were not executed. Sources: `engines/hermes/modules/hermes_harness/test_parity_compare.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.

#### projections

- **PM-05: Specification and model projections.** All derived model surfaces SHALL retain the same IDs, requirements and dependency edges and identify their source version. Historical gap to revalidate: Projection generation alone does not validate an official SysML/OML toolchain. Sources: `engines/hermes/modules/hermes_wiki/src/mbse/feature_model.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.
- **PM-11: Knowledge and document linkage.** Knowledge pointers SHALL preserve locator, source revision, digest and relationship; rendered views SHALL remain projections. Historical gap to revalidate: All rendered graph links require separate navigation validation. Sources: `engines/hermes/modules/hermes_wiki/src/engine/wiki_datastore.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.

#### release

- **PM-24: Release baseline and change control.** A release baseline SHALL bind requirements, dependency snapshot, JJ candidate, approvals, runtime/formal receipts and rollback; no status label alone admits release. Historical gap to revalidate: An integrated product release-baseline collector remains a gap. Sources: `engines/hermes/modules/hermes_ops_dashboard/run_assurance.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.

#### outcomes

- **PM-23: Operational analytics and cost evidence.** Reliability, cost and coverage summaries SHALL state population, retention, candidate and uncertainty; repeated samples SHALL NOT fabricate independent evidence. Historical gap to revalidate: Analytics are advisory and do not establish budget enforcement. Sources: `engines/hermes/modules/hermes_harness/receipt_reliability.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.
- **PM-25: Feedback and outcome learning.** Feedback SHALL retain its source, consent/scope, linked feature, hypothesis and measured outcome separately from proposed changes. Historical gap to revalidate: A complete customer research and business-outcome workflow was not found in the inspected management models. Sources: `engines/hermes/modules/hermes_harness/orientation_history.ml`. Preserve candidate/version/owner/acceptance evidence; no metadata-only completion.

Oracle execution waits for containment; completion waits for identity and claim-granular evidence; release collection waits for the accepted required closure. External empty-store observations do not prove current UOS stores empty.

### Four-client full harness integration (mandatory)

| Client | Required real integration | Acceptance |
|---|---|---|
| AGY | Actual installed client, current enrolled identity, loaded policy/rule/skill closure, finite reviewed grant, real tool discovery and serving identities | Initialize; discover; claim an eligible sandbox task; scoped read/edit; build/test; typed plan/evidence write/readback; heartbeat/release/completion; denial/replay/interruption/recovery. Independent reviewer observes real receipts. |
| Codex | Actual installed client, current enrolled identity, loaded policy/rule/skill closure, finite reviewed grant, real tool discovery and serving identities | Initialize; discover; claim an eligible sandbox task; scoped read/edit; build/test; typed plan/evidence write/readback; heartbeat/release/completion; denial/replay/interruption/recovery. Independent reviewer observes real receipts. |
| Claude | Actual installed client, current enrolled identity, loaded policy/rule/skill closure, finite reviewed grant, real tool discovery and serving identities | Initialize; discover; claim an eligible sandbox task; scoped read/edit; build/test; typed plan/evidence write/readback; heartbeat/release/completion; denial/replay/interruption/recovery. Independent reviewer observes real receipts. |
| Pi | Actual installed client, current enrolled identity, loaded policy/rule/skill closure, finite reviewed grant, real tool discovery and serving identities | Initialize; discover; claim an eligible sandbox task; scoped read/edit; build/test; typed plan/evidence write/readback; heartbeat/release/completion; denial/replay/interruption/recovery. Independent reviewer observes real receipts. |

- Discover actual receiving sessions rather than inherited names; unavailable provider/client is a full-profile gap.
- All four share the same semantic command contracts and Sa-plan truth. Client-specific configuration is an adapter, not a new authority.
- Verify task exchange and handoff between client families, with current identity, explicit acknowledgements, non-escalating scope and stable logical effects.
- Exercise pause, missing tool, stale owner/attempt/epoch/clock, changed candidate, imported Git instructions, forbidden direct fallback, payload identity, grant expiry and lost replies.
- Bound all contexts/tokens/latency/retries/charges; preserve existing explicit aggregate budget without silently enabling paid providers.
- Client adoption, policy copy/parity, hook loading, transport initialization, command success and runtime enforcement are separate evidence columns.

### Every MCP command must work (mandatory)

Freeze the union of actually declared tools/methods/resources/prompts across every required public/development/successor server and all four clients. Key entries by server identity/version, command name, schema digest and candidate. Follow discovery pagination and record additions/removals; the current public65 are the initial denominator, not the whole union.

At minimum the current public65 require260 client-command positive functional cells, plus private-server commands and relevant negative/recovery cases. A successful Codex read is not evidence for the same command in the other three clients.

For each required command:
1. Identify its real supervised backend, authorization, effects, schemas, resource limits and independent oracle.
2. Execute a valid authorized positive case in isolated development/staging through each actual client; assert actual returned meaning and state/effect.
3. Validate malformed/missing/oversized/NUL/Unicode inputs, wrong identity/tenant/scope, absent/expired/revoked authority and source/schema drift.
4. Exercise bounded timeout/cancel/backend failure and next-call survival; ensure descendants/worker quotas are restored.
5. For effects test durable intent, same-ID replay, changed-payload refusal, crash windows, lost replies and explicit uncertainty reconciliation.
6. Compare normalized semantics across supported transports/clients while preserving dynamic IDs/times by contract.
7. Retain request/response/state/effect/trace, source/build/dependency/client/server identities, elapsed bounds, oracle version and review.
8. Require positive functionality plus applicable negative/recovery coverage. Transport determinism/refusal is a separate contract result.
9. Never mask failure with fixed health, synthetic ok, empty output equivalence, unavailable status relabeling, removed denominator entries or caller-supplied authority.
10. Safely implement all12 currently unavailable entries and scoped authorized legacy mutations, or obtain an explicit operator scope change; no silent exclusion.

Initial frozen public inventory (all four-client functional cells UNRUN; previously observed read invocations are limited evidence only):

| Command | Inventory declaration | AGY | Codex | Claude | Pi |
|---|---|---|---|---|---|
| plan_status | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| plan_list_pending | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| plan_list | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| plan_get | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| plan_add | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| plan_update | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| plan_search | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| system_health | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| system_dashboard | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| system_immune | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| system_zenoh | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| system_verification | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| knowledge_search | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| verification_run | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| read_file | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| podman_containers | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| metabolic_state | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| ooda_phase | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| fractal_status | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| prajna_health | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| dark_cockpit_mode | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| integrity_check | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| evolution_metrics | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| mesh_topology | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| ooda_decide | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| kms_catalog | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| vault_status | unavailable | UNRUN | UNRUN | UNRUN | UNRUN |
| vault_list_secrets | unavailable | UNRUN | UNRUN | UNRUN | UNRUN |
| vault_policy_get | unavailable | UNRUN | UNRUN | UNRUN | UNRUN |
| vault_audit_tail | unavailable | UNRUN | UNRUN | UNRUN | UNRUN |
| vault_health | unavailable | UNRUN | UNRUN | UNRUN | UNRUN |
| control_loop | unavailable | UNRUN | UNRUN | UNRUN | UNRUN |
| safety_status | unavailable | UNRUN | UNRUN | UNRUN | UNRUN |
| registry_status | unavailable | UNRUN | UNRUN | UNRUN | UNRUN |
| run_selfcheck | unavailable | UNRUN | UNRUN | UNRUN | UNRUN |
| run_gate | unavailable | UNRUN | UNRUN | UNRUN | UNRUN |
| zk_search | unavailable | UNRUN | UNRUN | UNRUN | UNRUN |
| sa_bridge_submit | unavailable | UNRUN | UNRUN | UNRUN | UNRUN |
| forecast_predict | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| preflight_check | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| sa_plan_status | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| sa_plan_status_for | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| sa_plan_list | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| sa_task_claim | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| sa_task_complete | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| sa_job_enqueue | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| sa_workflow_start | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| stpa_fmea_hazard | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| rete_rule_conflict | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| ruliad_branch_eval | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| shruti_harmonics | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| ast_anomaly_detect | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| zk_transclude | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| lyapunov_trend_predict | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| sciviz_extension_deep_dive | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| ggram_synthesize | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| feature_tracker_status | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| mcp_capability_inventory | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| holon_status | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| swarm_status | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| agent_hierarchy | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| harness_system_feature_catalog | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| harness_system_feature_observations | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| harness_system_feature_intent | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |
| harness_execution_progress | declared_unprobed | UNRUN | UNRUN | UNRUN | UNRUN |

Actual Codex read_file, knowledge_search, sa_plan_status_for and mcp_capability_inventory returned in this planning session. These observations do not pass the complete functional/negative/recovery acceptance matrix.

### Telegram and operator surfaces

Reuse uos/telegram-fractal-tests/20261027-0312. Census136 seed targets plus subcommands/callbacks/subscriptions/service branches/states/journey branches; inventory remains incomplete until source reconciliation.

Implement/reconcile16 named delivery gaps: /cost, /swarm, /ADR, /ask, /chat, /brief, /profile, /intent, /redteam, /warroom, /standup, /pair, /kudos, /oncall, /voice-brief, /voice-cmd. Correct UnknownCommand is safe refusal, not delivered functionality. Each command needs actual backend, identity, scoped effect, independent response/state/effect oracle, replay/uncertainty and client acceptance.

Campaign prerequisites:
- AUTHOR → T00 inventory.
- T01 enumeration and T02 independent oracles follow T00.
- T03 environment/authority/budgets/thresholds follows T01+T02.
- T04 security, T05 storage/media, T06 commands/Mini-App, T08 live data follow T03.
- T07 interactions follows T04+T05+T06.
- T09 journeys follows T07+T08.
- T10 load/recovery/continuous24h soak and T11 human client follow T09.
- T12 deployment scenarios follows T10+T11.
- T13 independent audit follows T10+T11+T12; T14 publication follows T13.

The raw seed product exceeds5.78trillion tuples. T01 freezes applicability, exact finite cardinality, storage/throughput/worker-hours and feasible budgets. Pairwise screening does not close exhaustive obligations. Infeasible required scope remains incomplete pending explicit operator decision.

Verify web/API/TUI/AG-UI/admitted mesh meaning, real routes, authenticated subscriptions, cursor/reconnect/backpressure, freshness and keyboard/mobile rendered/raw behavior. T12 production effects require independent release and separate production authority. No outbound messaging follows from a journal save.

### Maximum useful parallelization

Three workers plus coordinator at current capacity:
- A: highest-criticality implementation.
- B: independent disjoint implementation.
- C: independent oracle/adversarial/formal/review lane.
- Coordinator: graph/risk/authority/interface reconciliation and serialized integration; not an unrecorded fourth executor.

Pull the dependency-ready frontier. Disjoint JJ workspaces, path ownership, stores/ports/topics/identities/fault targets and measured CPU/RAM/I/O ceilings are mandatory. Serialize shared schemas, authority partitions, overlapping edits, shared runtime mutation, integration and release. Reviewer independence survives candidate amendments. Five-executor Telegram cohorts use honest staggered waves; actual required provider execution cannot be replaced by review sessions.

### Full-profile gates

Each capability needs the same candidate-bound test/review/evidence cycle. All17 aspects,18 invariants, applicable L0–L9 cells,25PM obligations, four-client/all-command matrix, Telegram delivery/coverage, actual load/recovery/soak and independent release baseline are explicit. Cross-plan consumers check actual external task state AND current accepted evidence, since native cross-plan DAG enforcement is not established.

## 4. Root Cause Analysis

Competing hypotheses concern why apparent progress does not establish full functionality. Scores below are diagnostic inconsistency indicators (0 consistent,1 unresolved,2 contradicted), not calibrated probabilities or proof.

| Evidence | H1: complete backend absent everywhere | H2: partial code exists; integration/acceptance missing | H3: declarations/synthetic checks inflate completion |
|---|---|---|---|
| Closed planning interpreter exists | 2 | 0 | 1 |
| Actual client exposes only4 reads; development disabled | 1 | 0 | 0 |
| Process preparation refuses; context/inference contract mismatch | 1 | 0 | 0 |
| Synthetic Telegram ok and default layer mapping | 1 | 0 | 0 |
| Three product tasks complete while PM acceptance unrun | 1 | 0 | 0 |

H2 and H3 explain the inspected evidence better than blanket H1. Required disconfirmation: inspect each actual serving route and test it through real clients with independent state/effect oracles. No physical duplicate, global runtime outage, or universal absence was demonstrated.

## 5. Fix Taxonomy

Poka-Yoke: closed typed intents, schema/path/payload bounds, source identities, explicit availability, strict completion collector and immutable logical IDs.
Jidoka: stop affected effects on stale authority, unknown outcome, broken oracle, missing evidence, budget/storage failure or unsafe boundary.
Muda: reuse existing Sa-plan tasks/catalogs/receipts; no duplicate queue, framework, blanket NIF redesign or repeated passing suites without changed inputs.
Standardized work: four-client command matrix and explicit positive/negative/recovery contracts.
Heijunka: dependency-ready bounded WIP with separate runtime and integration ownership.

No implementation repair was performed by saving this plan. The operator has requested continued execution; D0 access/authority gates govern subsequent product effects.

## 6. Patterns & Anti-Patterns Discovered

Use fresh serving behavior and independent evidence. Preserve partial implementations, historic failures, unavailable providers and unresolved scope. Separate declared/implemented/executed/verified/admitted states.

Avoid counting deterministic refusal as delivered functionality, synthetic success as integration, copied policy as enforcement, task counts as readiness, empty required sets as passing, source pin as executable identity, OTP supervision as replication, TF-IDF as learned embeddings, or a static acknowledgement as model inference.

Falsifiers include: an authorized required command still unavailable; one of four clients cannot enroll/use it; a source change retains verification credit; stale owners effect; same logical action dispatches twice after lost reply; protected context disappears; two empty outputs compare equivalent; a wrong200 returns task success; secret fixture appears in prompt/log; an unreadable child becomes green through parent rollup.

## 7. Verification Matrix

Passing admission evidence requires source reliability/information credibility A1/A2/B1/B2 and actual candidate-bound receipts. This journal does not invent those grades.

| Check | Observed scope | Status | Grade | Next verification |
|---|---|---|---|---|
| Canonical plan status | Read-only MCP reports five named plan summaries | OBSERVED; no effect authority | F6 for admission | Reobserve exact tasks/owners/candidate through admitted ingress |
| Exposed MCP surface | Four read operations; inventory65/12unavailable/53unprobed | OBSERVED discovery only | F6 for admission | Full union discovery and actual four-client functional matrix |
| Harness52 accounting | 52 assigned once; source dependency references resolve; no recorded cycle; nine structural waves | ANALYSIS ONLY | F6 | Candidate-bound native master graph validator |
| Infrastructure21 accounting | 21 assigned once | ANALYSIS ONLY | F6 | Runtime/formal evidence for357baseline cells and added discoveries |
| PM25 accounting | 25 assigned once | ANALYSIS ONLY | F6 | Implement/test required catalog and oracle behavior |
| Four-client harness integration | AGY/Codex/Claude/Pi real full workflow | UNRUN | F6 | Actual admitted clients and independent review |
| Every MCP command functional | Positive plus negative/recovery matrix | UNRUN | F6 | Real supervised backends and independent state/effect checks |
| Build/runtime/formal gates | No new build/service/prover run | UNRUN | F6 | Scoped admitted execution |
| Journal linter/topology gates | Not invoked by this journal save | UNRUN | F6 | Run through admitted interface or explicitly bounded exception |
| Journal save/readback | Workspace journal save under finite operator-reaffirmed metadata exception | PENDING | F6 | Actual write, readback and source identity receipt |

The seven journal engines remain separately scoped: ACH documented; Admiralty admission not established; Bayesian posterior unavailable; red-team cases predeclared; formal engine UNRUN; Rete-UL engine UNRUN; forecast resolution pending. No prose satisfies an unrun engine.

## 8. Files Modified

| Path | Change | State |
|---|---|---|
| docs/journal/20261028-0118-uos-full-fractal-four-client-mcp-plan.md | New additive full planning journal; prefix bound to observed synchronized host UTC | NEW workspace planning journal; readback verified separately |
| Source/configuration/runtime/task stores | No changes authorized by this journal-only publication action | UNCHANGED by this action |

Do not rewrite the previous handover or existing journals. Do not mutate Sa-plan with direct SQL, move bookmarks, delete the untracked guardian executable, change client grants, or deploy as part of this journal save.

## 9. Architectural Observations

Control authority remains Gleam/OTP; planning state remains Sa-plan. Source catalogs and UI are read-only projections. Hermes native functions remain bounded analysis/adapters, while blocking work belongs behind supervised isolated processes. Existing ZigVM and MAX boundaries are preserved.

The ten dynamic census categories and named catalog roots define the initial closure. Census terminates only at a frozen candidate, enumerated roots, reconciled entries and explicit unresolved findings. No seed catalog proves all project functionality enumerated. Evidence hierarchies and L0–L9 responsibilities are distinct structures.

Explanatory graph sources, if added, must use equivalent ASCII and Mermaid. This record uses tables and contains no explanatory diagram.

Canonical references:
- [Policy](http://nas-1.tail55d152.ts.net:4100/files/AGENTS.md)
- [Harness boundary](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260909-0412-gleam-harness-agent-operation-contract.md)
- [Risk SOP](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-1559-risk-prioritization-sop.md)
- [Core plan](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20261027-0634-hive-development-readiness-plan.md)
- [Harness52](http://nas-1.tail55d152.ts.net:4100/files/governance/capability-inventory/20260909-0412-harness-feature-catalog.json)
- [Product46](http://nas-1.tail55d152.ts.net:4100/files/governance/capability-inventory/20260907-1837-agentic-product-manifest.json)
- [Infrastructure21](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260907-0550-uos-agentic-infrastructure-17-aspect-formal-spec.json)
- [Telegram campaign](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20261027-0312-telegram-fractal-test-plan.md)

## 10. Remaining Gaps

P1 proposed: actual publication/development ingress; exact ownership/grant/source/clock reconciliation; initial core acceptance; safe local fencing/durability/accounting; process containment; false-green/strict evidence collectors; missing command/backend functionality where release-critical. No current P0 incident demonstrated.

P2 proposed: dependency-ready required services, full four-client integrations, operator surfaces, command delivery, PM/oracle implementation, replication/failover where required by the profile. Escalate any demonstrated safety/release dependency to P1 after fresh assessment.

P3 proposed: optional optimization/experimentation whose effects are controlled. Advanced named catalog requirements remain on the full roadmap; a lower class never silently excludes them.

Outstanding: fresh raw risk factors and combined graph; all new canonical child registrations; all four-client positive/negative/recovery cells; explicit backend for12 unavailable tools; safe authorized legacy mutations; live route and serving-byte identity; candidate-bound formal receipts; Telegram feasibility/actual clients/soak; independent full-profile and separate production decisions.

All unresolved requirements retain UNKNOWN/UNRUN/BLOCKED assessments; these are not new Sa-plan database states.

## 11. Metrics Summary

Counts above measure plan/catalog populations, not functionality percentages. Draft accounting covers harness52/52, infrastructure21/21 andPM25/25 once within each universe; overlap is preserved. MCP public initial functional matrix65×4=260cells, all full-acceptance UNRUN; private union still requires discovery.

Record per task actual tokens/cost/latency/retries/rework/blocked time, mailbox/queue/RSS/CPU/I/O and verified useful outcome. Unknown usage or price remains a liability; no inferred free model usage.

Bayesian prior/posterior and calibrated confidence: NOT_ESTABLISHED. No independent trial population or success/failure series exists for full-profile readiness. Do not update a posterior from correlated catalog checks.

Lyapunov V definition, measured trajectory and dV/dt<0: UNRUN; no stability claim. Kalman prior/innovation: UNRUN. Trust half-life and evidence freshness must follow observed times and source invalidation, not model timestamps.

## 12. STAMP & Constitutional Alignment

Losses: unauthorized effects, evidence corruption/false admission, duplicate external action, secret exposure, storage damage, unbounded spend and service starvation.

Four UCA categories applied to harness dispatch:
1. Required control absent: no current permission/fence/evidence at dispatch. Constraint: deny affected effect; bounded repair/probe only.
2. Unsafe control provided: forged identity, overly broad grant, untrusted model/text instruction or fixed health permits effect. Constraint: trusted scope intersection, schemas, real state and effect-time checks.
3. Wrong timing/order: expired approval/lease, stale candidate, unsatisfied prerequisite, replay after unresolved outcome. Constraint: revalidate at effect; stable logical ID and reconciliation before retry.
4. Duration wrong: runaway task/retry/worker, stopped audit/telemetry mistaken as safe or lease continuing after cancellation. Constraint: bounded deadlines/queues/budgets, tree reaping, permit revocation and retained uncertain liability.

Raw FMEA fields before dispatch: S/O/Det, RPN=S×O×Det, F=max(severity,rpn_band), C/T/Dep/I and rationale. Unknown occurrence/detection remain null; no fabricated numeric ranking.

Zero-Muda; no Bevy/Graphite ingestion; no external source writes; standalone JJ; denied system-OS storage identifier remains [REDACTED_SYSTEM_OS_SERIAL] in journal narrative. New packages only pinned Nix/devenv. All new docs use observed YYYYMMDD-HHSS (hour and seconds). All runtime and release authority separate from model advice, board ACK, task completion and this journal.

<details><summary>Domain1 — Metadata/navigation</summary>

- [x] CHK-01-TIME — Observed synchronized host UTC2026-10-28T01:36:18Z and prefix20261028-0118 (hour and seconds); lease/serving freshness separate.
- [ ] CHK-02-TAIL — Verify actual FQDN serving/readback.
- [x] CHK-03-FRACT — L0–L9 applicability recorded as a plan, not runtime pass.
- [ ] CHK-04-KM — Publish/index exact journal and evidence references.
</details>
<details><summary>Domain2 — Purity/storage</summary>

- [ ] CHK-05-MUDA — Candidate dependency/exclusion scan.
- [ ] CHK-06-GRAPH — Pure graph/native boundary conformance.
- [ ] CHK-07-DRIVE — Safe fixture/interlock checks; no physical drive effects.
</details>
<details><summary>Domain3 — Verification</summary>

- [ ] CHK-08-C1C8 — Applicable actual-surface coverage.
- [ ] CHK-09-MATH — Four repository-defined mathematical gates.
- [ ] CHK-10-9MOD — Applicable modalities and Telegram extensions reconciled.
- [ ] CHK-11-REGR — Actual regression/load/recovery/soak evidence.
</details>
<details><summary>Domain4 — Control/observability</summary>

- [ ] CHK-12-GLEAM — Actual four-client admitted OTP harness.
- [ ] CHK-13-HERMES — Bounded independent analysis/evidence/oracle operations.
- [ ] CHK-14-ZIGVM — Required deterministic/VFS behavior.
- [ ] CHK-15-MAX — Required actual identified inference.
- [ ] CHK-16-OTEL — End-to-end trace/span/13D evidence and loss behavior.
</details>
<details><summary>Domain5 — Governance/JJ</summary>

- [ ] CHK-17-SOV — Independent candidate-bound full-profile review; production separate.
- [ ] CHK-18-JJ — Exact candidate/working-state accounting and serialized integration.
</details>
<details><summary>Domain6 — Provenance</summary>

EV-93 ceiling preserved; EV-94..109 NOT_ADMITTED; no new EV. No journal, score, client registration or catalog count grants admission.
</details>

## 13. Conclusion

This complete planning projection preserves existing implementations and history while assigning every known requirement family an execution and acceptance path. Immediate priority is safe admitted planning access and exact ownership reconciliation, then the named development core. Full delivery explicitly includes real AGY, Codex, Claude and Pi integration and actual successful tested operation of every required MCP command. Deterministic unavailability cannot close a functionality obligation.

This journal does not assert that implementation, registration, runtime verification, independent acceptance or production release has occurred. The host-observed filename timestamp is recorded in Section2. Verify the saved journal by actual byte readback before claiming persistence; serving, indexing, JJ integration and Sa-plan publication remain separate. A saved file is not proof it is served, indexed or committed.

Precommitted forecast (subjective, uncalibrated; no authority): p=0.95 that a fresh command-union acceptance sweep will contain at least one nonpassing required four-client command cell unless development binding/client exposure/backends are repaired. Horizon T_horizon=2026-10-29T23:59:59Z. Outcome o=1 iff a complete candidate-bound sweep conducted by that horizon records at least one required functional/negative/recovery gap; o=0 iff the complete sweep passes every required cell. If no complete sweep is performed, resolution is UNRESOLVED and no Brier result is fabricated. Falsification: a complete four-client sweep passes all required cells without the stated repair. Brier rule B=(p-o)^2 after valid resolution.

[Previous handover](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261028-0114-codex-handover-main-push-comprehensive.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

UOS footer: development harness first; operator requests token-optimized execution to completion. This journal is a planning projection; Sa-plan and admitted Gleam authority govern product execution. Runtime and production admission remain ungranted.
