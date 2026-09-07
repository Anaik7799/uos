# 20260907-0653 — UOS implementation handoff for the cheaper phase

#fractal-l0 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #zk-adr #zero-muda #tailscale-web

**UOS / Implementation plan** · [Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Checklist](http://nas-1.tail55d152.ts.net:4100/checklist)  
**Live:** [http://nas-1.tail55d152.ts.net:4100/docs/plans/20260907-0653-uos-tri-agent-cheaper-mode-implementation-plan.md](http://nas-1.tail55d152.ts.net:4100/docs/plans/20260907-0653-uos-tri-agent-cheaper-mode-implementation-plan.md) · [Raw source](http://nas-1.tail55d152.ts.net:4100/files/docs/plans/20260907-0653-uos-tri-agent-cheaper-mode-implementation-plan.md)

Created: 2026-09-07T06:38:53Z. Stage: **ANALYSIS / PLAN / DESIGN COMPLETE; FURTHER IMPLEMENTATION DEFERRED BY OPERATOR.**
Primary [infrastructure specification](http://nas-1.tail55d152.ts.net:4100/docs/design/20260907-0550-uos-agentic-infrastructure-17-aspect-formal-spec.md), [coordination specification](http://nas-1.tail55d152.ts.net:4100/docs/design/20260907-0653-uos-tri-agent-sdlc-sre-herdr-spec.md), [contract](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260907-0653-tri-agent-coordination.md), and [Astra/max review](http://nas-1.tail55d152.ts.net:4100/docs/reviews/20260907-0653-astra-max-agentic-system-design-review.md).

## 1. Starting checkpoint and scope

The design has21 services,17 canonical aspects,357 service/aspect obligations,18 invariants and63 service acceptance cases. Eight parent work packages define enterprise implementation. The bounded coordination work started before the operator changed stage; those prototype files are preserved and explicitly unadmitted. No prototype status is a substitute for the acceptance obligations below.

Native prototype entrypoints are `session_sync_cli`, `herdr_sync_cli` and `openrouter_worker_cli` under `apps/uos_tui/src`. They reuse `uos_tui/coord`, the signed `board`, Hermes/Sa-plan, Gleam/OTP and a small Erlang I/O boundary. The current package remains one implementation location; any TUI/swarm package split is a behavior-preserving packaging step, not permission to rewrite tested domain logic.

Before resuming, rediscover Herdr sessions, refresh JJ state and source hashes, inspect inbox/Andon records, run the bounded suite and claim ownership. Do not assume the pane IDs, source revision or passing count in this handoff remains current.

## 2. Ordered coordination slices

| Slice | Dependencies | Files / contracts | Implementation and exit criteria |
|---|---|---|---|
| C00 Candidate and ownership baseline | None | JJ, Sa-plan, session/board schema | Pin base/change/commit IDs, private state path and actual peer identities. Inventory dirty work and acquire one integration owner. Save observation receipt; no automatic cleanup of another writer. |
| C01 Durable local coordination | C00 | session_sync.gleam, session_sync_ffi.erl, session_sync_test.gleam | Verify atomic event append, lock recovery, epoch retention and command-body-bound idempotency across independent OS processes. Canonicalize workspace resource paths. Crash at every persistence point; corrupted/torn evidence must remain preserved and fail closed. |
| C02 Sa-plan bridge and board repair | C01 | Proposed typed SessionObservation bridge; existing board/coord | Implement idempotent observation ingestion and board projections. Preserve original sender events and explicit causal gap records. A missing historical message cannot be repaired by forging its ID or ACK. No shared-key DELETE or ledger regeneration. |
| C03 Actual peer binding and Herdr | C01,C02 | herdr.gleam, herdr_sync_cli, Herdr session API | All3actual sessions register and ACK their own inbox messages. Reject stale IDs, replaced processes, blocked approval UIs and unauthorized directories. Record the CLI's non-atomic dispatch race; require a stronger fenced protocol before privileged unattended dispatch. |
| C04 SDLC executor boundary | C02,C03 | Proposed IntegrationCommand and candidate receipt | Enforce current candidate, owner epoch and policy at the action consumer. One writer creates a preserving JJ merge and rechecks conflict/source/evidence state. Tests show stale sessions cannot integrate through this adapter. A raw JJ invocation remains outside the adapter until separately intercepted. |
| C05 SRE action boundary | C02,C03 | Proposed RuntimeAction, service allowlist, rollback receipt | Separate runtime leases; typed observe/diagnose/mitigate/rollback operations; explicit policy and authorization. Incident, SLO and rollback evidence correlate to the exact deployed artifact. No model or terminal ACK authorizes a restart/deletion. |
| C06 OpenRouter workers and economy | C02 | openrouter_worker, request budget broker | Replace heuristic paid token liability with an enforceable provider/request bound and atomic per-task/tenant fleet reservation. Validate all priced dimensions, fallback attempts and ambiguous charges. Free-only default; task-scoped paid opt-in. Retain actual provider/model/usage/cost and outcome references. |
| C07 Formal refinement and swarm acceptance | C01–C06 | Lean/Quint models, implementation differential/crash tests | Bind concrete session generations, canonical resource identity, journal sequence, clock domain, policy/candidate tuple and reservation-attempt linkage to the abstract model. Extend temporal models for crash/replay/recovery and multiple resources. Run a real bounded3 peer swarm with independent ACKs, task exclusion, restart, failed provider and one reviewed integration. |
| C08 Packaging and release readiness | C07 | Existing TUI + proposed swarm package boundary | Split presentation from coordination only with import/build/test/CLI parity; preserve entrypoint adapters during migration. Stage/canary, rollback, backup-restore, operational alerts and two-key admission stay explicit gates. |

A review task may proceed in parallel with source implementation when paths and ownership are disjoint. Integration and runtime-target mutation remain serialized.

## 3. Full enterprise work packages

| Work package | Dependency | Result |
|---|---|---|
| AINF-WP00 | None | Freeze schema, candidate and evidence contracts; include C00–C03 coordination prerequisites. |
| AINF-WP01 | WP00 | Workload identity, delegated user authority, policy, tenant boundary and credentials. |
| AINF-WP02 | WP01 | Hermes transaction authority, durable workflows, budgets, event outbox/inbox and bound approvals. |
| AINF-WP03 | WP02 | Registry/protocol negotiation, dynamic tools and independently isolated execution. |
| AINF-WP04 | WP03 | KM graph/retrieval, context routing/compaction and admitted model routing. |
| AINF-WP05 | WP03,WP04 | Semantic trajectory evaluation, telemetry, regression corpus and cost/quality measurements. |
| AINF-WP06 | WP05 | UI surfaces, operational runbooks and all 17 aspect candidate evidence. |
| AINF-WP07 | WP06 | Canary, load/isolation/recovery rehearsal and explicitly authorized admission. |

The machine companion binds every service to its primary WP and all 17 aspects. All63 enterprise acceptance cases remain UNRUN until executed against implemented services. Coordination prototype tests do not close those cases.

## 4. Concrete authority and transaction decisions

Hermes is the single transactional authority for workflow outcomes, approvals, money and dispatch. The local session journal is only a cooperative registry/reservation/ACK log. Its events reach Hermes as typed `SessionObservation(event_id, payload_hash, local_sequence, session_ref, resource_ref, epoch, candidate_ref)` messages. Hermes stores an idempotent inbox row and returns `ObservationAccepted(event_id, payload_hash, hermes_sequence)`; duplicate matching messages repeat the receipt and conflicting bodies reject. Local receipt ACK records that ingestion only.

A task completion or action request uses a separate authorized Hermes command with task/attempt identity, current Sa-plan lease, expected candidate and evidence references. No pair of local-journal and Hermes writes forms an authoritative distributed transaction. On disconnect, retain local pending observations and replay them idempotently. Sequence gaps, superseded sessions and mismatched hashes produce a visible reconciliation state.

The public dispatch operation is `reserve_and_prepare_dispatch`: one Hermes WAL transaction commits authorization snapshot, all quota reservations, action identity, workflow transition and outbox. Final `authorize_and_claim_dispatch` serialization checks current policy epoch, revocation/cancellation ordering and the expected live fence before recording dispatch start. Revocation committed first prevents start; start committed first does not assert reversibility, and later cancellation requires containment/reconciliation if an effect may have begun. Adapter-level validity checks and destination enforcement remain necessary; the database cannot atomically serialize an unrelated remote system.

## 5. Formal scope and verification completion

The Lean/Quint checkpoint covers admission-gate structure, a single resource per model instance, epoch/authority rules and separate budget arithmetic. It does **not** establish real cryptographic receipt validity, receipt age, sovereign approval, all fields of the candidate tuple, multiple sessions of one client kind, disk durability, process reaping or per-attempt reservation linkage. These are named refinements, not implicit axioms.

Observed checkpoint:26 Lean theorems compile;9 Quint scenarios pass;400 seeded traces of up to60 steps find no violation;2 unsafe mutants are detected. [Formal invocation receipt](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260907-0620-uos-tri-agent-formal-verification.json) binds tool versions, hashes and limits. The model gate is distinct from all 17 operational semantics, which remain NOT_PROVED.

At the implementation checkpoint, root observed448 TUI tests and10,196 cepaf tests passing;3 hardware-identity tests passed. The earlier sandbox cepaf run had179 failures caused by restricted local resources, so the host rerun is the applicable baseline. Hermes wiki/Sa-plan `dune runtest` exited0 without a new verbose count; this does not claim every existing suite freshly re-executed. These are source/test observations, not system admission.

## 6. Cost-conscious execution policy

Start each slice with local compilation, focused tests, source queries and proof tools. Use one implementation worker and one independent reviewer where risk warrants it; default concurrent WIP is 3, with distinct path/resource claims. Dispatch compact packets bounded by task, paths, candidate and acceptance cases. Store durable references instead of repeating full histories.

Use the cheaper model chosen by the operator for routine implementation. Escalate a narrowly scoped issue to Astra/max only for an unresolved architecture contradiction, failed formal refinement or repeated critical defect. OpenRouter remote advisory requests default to free-only and <=512 completion tokens; no repeated model fanout or automatic paid fallback. The observed account denied free routes, so that default can fail closed. One earlier explicit paid smoke test used359 total tokens and reportedUSD 0.0001061; that is a single receipt, not an expected cost guarantee.

Paid swarm rollout waits for aggregate reservation and cost reconciliation in C06. Evaluate useful accepted findings per token, total attempts, elapsed time, failure/rework rate and cost per accepted task. Do not optimize token price while increasing duplicate work or reducing required evidence.

### Global routing decision

The router minimizes estimated cost per accepted outcome across eligible Claude,
Codex, AGY and OpenRouter routes. Eligibility requires current capability,
authorization, data policy, a task-specific quality threshold and available
budget. Quality eligibility uses a conservative confidence bound from held-out
verified outcomes; a Thompson sample or one successful review is not a quality
guarantee. Include retry liability, cache behavior, elapsed time and subscription
quota/opportunity cost. Unknown CLI dollar cost remains unknown, not zero;
deterministic tools consume zero model tokens but still consume compute.

Every fallback is another bounded attempt charged to the same task budget.
Never turn a free-tier refusal into paid permission. Unknown adequacy routes to
a bounded evaluation task or explicit escalation, and no empirical selector is
claimed to prove a global optimum. Model pricing and quality statistics expire
and are rebound to the candidate/model/provider revisions.

The separately authored `20260907-0925-uos-global-intelligence-routing-design.md`
is retained as a peer proposal. Its price/adequacy comparisons, Fable-only global
authority and automatic paid-floor language are not adopted as governing rules
by this handoff; the eligibility and authorization contract above controls.

## 7. Stop and resume contract

Implementation is paused after design completion. Preserve prototypes, private runtime state and external trees. Existing production services are unchanged by this handoff. Resume with C00, then the ordered slices and enterprise WP dependency graph. Progression remains discovered → classified → mapped → implemented → built → executed → passed → verified → admitted; no state skips.


## Comprehensive verification checklist

Document checks and production gates have different evidence scopes. Checked
items below refer only to this document package. All infrastructure runtime,
formal-proof and sovereign-admission obligations remain **UNRUN**.

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] **CHK-01-TIME** — Host-clock timestamp prefix and chrony receipt recorded.
- [x] **CHK-02-TAIL** — Full clickable Tailscale FQDN references provided; serving status is reported in the journal.
- [x] **CHK-03-FRACT** — Canonical L0–L9 fractal tags assigned.
- [x] **CHK-04-KM** — Specification, wiki, ADR, source review and journal cross-linked.

</details>

<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [ ] **CHK-05-MUDA** — Production dependency/exclusion scan required.
- [ ] **CHK-06-GRAPH** — Pure BEAM/Hermes graph boundary must pass runtime checks.
- [ ] **CHK-07-DRIVE** — Denied OS serial `25503L801736` must pass real interlock tests.

</details>

<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] **CHK-08-C1C8** — Structure, health badges, data grids, timeline, interactions, dark cockpit, advisory and action interlock.
- [ ] **CHK-09-MATH** — H ≥ 2.50 bits, CCM ≥ 90.0%, D_EA ≤ 10.0%, ITQS ≥ 0.85 require declared metrics and fresh measurements.
- [ ] **CHK-10-9MOD** — Unit, system, TDD, BDD, performance, scalability, property, fuzz and chaos.
- [ ] **CHK-11-REGR** — Relevant UI regression suite and 30-second monitoring require execution.

</details>

<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [ ] **CHK-12-GLEAM** — Real OTP domain/actor supervision and restart evidence.
- [ ] **CHK-13-HERMES** — Authoritative WAL, bounded formal checks and evidence receipts.
- [ ] **CHK-14-ZIGVM** — Deterministic execution and descriptor-relative VFS evidence.
- [ ] **CHK-15-MAX** — Real inference through the isolated MAX boundary.
- [ ] **CHK-16-OTEL** — UTC microsecond timestamps and nonzero W3C trace/span IDs.

</details>

<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [ ] **CHK-17-SOV** — Tri-sovereign candidate review and authorized admission are outstanding.
- [x] **CHK-18-JJ** — Documentation authored in UOS using its standalone JJ discipline; no native Git mutations in UOS.

</details>


**Previous:** [System design](http://nas-1.tail55d152.ts.net:4100/docs/design/20260907-0653-uos-tri-agent-sdlc-sre-herdr-spec.md) · **Next:** [Operating runbook](http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260907-0653-uos-tri-agent-swarm-operations.md)  
**UOS footer:** Design handoff complete; implementation deferred; no production admission.
