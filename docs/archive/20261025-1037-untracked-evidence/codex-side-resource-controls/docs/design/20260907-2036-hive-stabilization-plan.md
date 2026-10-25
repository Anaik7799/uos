# Hive Stabilization Implementation Plan

> For agentic workers: use the repository executing-plans and risk-prioritization
> skills task by task. The main session owns peer discovery, dispatch and board
> posting. This side conversation prepares the plan and cannot launch or direct agents.

**Goal:** Establish truthful evidence and fenced coordination, then demonstrate
a bounded swarm before increasing autonomous work.

**Architecture:** Gleam/OTP supervises coordination and telemetry; Hermes owns
existing typed analysis and Sa-plan durability. Preserve isolated JJ candidates
and serialize integration separately from runtime ownership.

**Tech stack:** Existing UOS Gleam/OTP, Hermes OCaml, Sa-plan and approved runtime
ecosystem. No additional model or infrastructure dependency is required for intake.

**Spec:** [Coordination contract](../../contracts/rules/20260907-0653-tri-agent-coordination.md),
[risk SOP](../../contracts/rules/20260907-1559-risk-prioritization-sop.md),
[resource contract](20260907-1906-resource-controls-spec.md) and
[observed hive evidence](../journal/20260907-1906-resource-controls-journal.md).

Observed intake: 2026-09-07T20:21:36Z; chrony stratum3,
0.000568691 seconds fast. Final planning preflight observation: 20:26:57Z,
absolute offset0.000420285 seconds, uncertainty0.0172847305 seconds.
Prefix 20260907-2036 uses UTC hour and seconds at intake.
Tags: #fractal-l0 #fractal-l3 #fractal-l4 #fractal-l6 #fractal-l9 #zk-adr #zero-muda.

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Board REST](http://nas-1.tail55d152.ts.net:8080/c3i/a2a/**) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

[Task manifest](../reviews/20260907-2036-hive-stabilization-tasks.json) · [Journal](../journal/20260907-2036-hive-stabilization-journal.md) · [Planning risk packet](../reviews/20260907-2036-stabilization-design-risk.json)

## Global constraints

- Sa-plan plan: uos/hive-stabilization/20260907-2036. Claims must use exact eligible task IDs.
- Standalone Jujutsu only. Resource repair c502fbd27c68439dd72686f2affe586c4198851b
  and fencing parent311d2b12368d65c9b0f27f3d6adca315b94bbc62 are preserved for review.
- No shared journal rewrite, namespace deletion or hidden recovery bypass.
- Scope/attempt/epoch, source commit, resource budget and expiry accompany each action.
- Missing observations and incomplete tests remain UNKNOWN/UNRUN, not green.
- Source integration and runtime cutover require separate current ownership and evidence.
- Side-session restriction: no peer-agent launch, contact or board dispatch.
- Published explanatory diagrams require matching ASCII and Mermaid; this plan uses tables.
- Proposed operational targets below are acceptance goals, not measured fleet SLOs.

## Observed baseline and ordering

The live board returned334 messages, newest17:50:02UTC. Sa-plan at approximately
20:14UTC had15 executing labels,13 expired leases and2 live leases. Coordinator
repair was marked completed with resultOK; its independent outcome was not proven.
Forecast histories and health are fixtures/constants. MAX labels do not prove
trained model execution. Resource sensing remains blocked on root/current owners.

At20:23:44UTC the checker rejected a changed session_sync.gleam hash. Inspection
found active SQLite helpers and journal compaction code. Its reference was refreshed
only after inspecting the delta. Verify the current coordinator owner's candidate;
do not duplicate its implementation or run compaction against live evidence.

Safety class and dependency eligibility precede C × T × F × Dep × I.
These are provisional ordinal work-order estimates. Full source-bound STPA/FMEA
execution packets must be refreshed before claims; scores do not grant authority.
For false admission/authority hazards, S5 imposes F5 even with unknown occurrence
and detection (RPN5–125). HISTORY has S4 and unknown O/Det, hence F4–5.
MODELS has S3 and unknown O/Det, hence F3–5. Unknowns are not invented probabilities.

| Task | Class | C/T/F/Dep/I | Score | Dependencies |
|---|---|---|---|---|
| HANDOFF | P1 | 4/4/5/5/5 | 2000 | DESIGN |
| COORD | P1 | 4/4/5/5/5 | 2000 | HANDOFF |
| TRUTH | P1 | 4/4/5/4/4 | 1280 | HANDOFF |
| FENCE | P1 | 4/4/5/5/5 | 2000 | COORD |
| OBSERVE | P1 | 4/4/5/5/5 | 2000 | COORD, FENCE |
| HISTORY | P2 | 3/3/4–5/4/4 | 576–720 | COORD, TRUTH, OBSERVE |
| CANARY | P2 | 3/3/5/4/4 | 720 | COORD, TRUTH, FENCE, OBSERVE, HISTORY |
| EXPAND | P2 | 3/3/5/3/4 | 540 | CANARY |
| MODELS | P3 | 2/2/3–5/2/3 | 72–120 | HISTORY, CANARY |

HANDOFF inherits urgency from the downstream control tasks. Among ready P1 tasks,
reverification of existing work precedes duplicate implementation. Blocked tasks
remain ineligible regardless of score. HISTORY and MODELS require discriminating
measurement before a point ranking. This plan is not an atomic scheduler.

## Fast OODA operating loop

1. **Observe, up to60seconds:** Capture hostUTC, chrony offset/uncertainty,
   monotonic elapsed time, board receive time, logical sequence, exact source
   revision and Sa-plan worker/attempt/lease. Reject invalid/stale inputs.
2. **Orient:** Read the previous outcome, changed dependency/hazard and current
   portfolio. Retain one falsifiable goal per work packet.
3. **Decide:** Select one exact eligible task using safety class, dependencies,
   score interval and cheapest demonstrated capable tool. Claim it through Sa-plan.
4. **Act in2–5minute steps:** Use deterministic reads/tests first, make one scoped
   change, then verify that change. Larger work spans multiple such cycles.
5. **Feedback:** Publish compact state/evidence on transitions or every5minutes
   while active. After two cycles without new evidence or progress, stop retries,
   identify the blocked prerequisite and revise the task.

One integration writer; at most two implementation workspaces at once, with
disjoint paths. Reviewer does not approve its own candidate. Each remote advisory
request is free-only, at most one retry and an explicit token ceiling; proposed
initial aggregate cap is20000 advisory tokens per cycle and USD0. If no capable
free route exists, retain the task as blocked and use an approved budget path.
Subscription usage is not automatically zero cost. Track tokens, time and verified
outcome; no global optimum claim without comparable measurements.

## Task HANDOFF — current discovery and execution authority

Files: coordination contract, session_store_cli.gleam and session_sync_cli.gleam.
Consumes this plan and its source references. Produces a current plan assessment,
real provider/session IDs, explicit ACKs and task/workspace claims.

- [ ] Read current Sa-plan task results and actual live Herdr/session identities.
  Check whether COORD-JOURNAL-DB, KM, HOLON-COVERAGE or PRODUCT-WORKFLOW already
  owns overlapping work. Do not duplicate or take over their tasks.
- [ ] Reverify the canonical coordinator read-only status before registration.
  A current source hash or reachable process is not a peer ACK.
- [ ] Refresh one complete execution portfolio with four STPA UCA cases per
  task: missing control, unsafe provision, wrong order/time and excessive duration.
  Bind FMEA modes, source hashes, budgets, dependencies and falsifiers.
- [ ] Select capable real agents by role and actual availability, then obtain
  ACKs for distinct workspace/path scopes. Assign one integration controller.
- [ ] Post the unsigned intent below through the admitted signed board adapter.
  Bind actual sender/session/clock and delivery receipt there; do not copy a
  historical Codex identity or invent a signature.
- [ ] Complete HANDOFF only with evidence references to these observations and
  ACKs. No board ACK independently admits source or runtime effects.

Main-session roles: controller owns selection/integration; workerA owns coordinator
verification; workerB owns truth-label repair; independent reviewer challenges
candidate evidence. Provider choices are deferred to discovered capability/cost,
not hardcoded to Claude/Codex/AGY.

## Task COORD — verify existing repair before changing it

Files: session_store.gleam, session_store_ffi.erl, session_sync.gleam and their
existing tests. These are moving canonical files; obtain their owner's pinned
candidate and isolated workspace first. Produces verified replay, append-only
behavior and current ownership evidence.

- [ ] Reproduce on a private copy: body-byte alteration, sequence gap, changed
  predecessor digest and unknown command must each refuse replay.
- [ ] Attempt UPDATE/DELETE through the supported ordinary writer; require refusal.
  Preserve original event bytes and digests. Any repair projection must have
  separate lineage and cannot replace the source journal or conceal orphaned events.
- [ ] Race two independent claims for one resource: exactly one current owner.
  Reuse an operationID with conflicting content: refusal. Crash/reopen around
  append: one recoverable outcome, no silently dropped accepted event.
- [ ] Test expired/same-name sessions and boot changes. Observe first, then
  reconcile expired task labels through supported APIs after checking unfinished
  effects. Do not mark all expired work successful or remove another live lock.
- [ ] Run the existing session_store/session_sync suites in the owner's isolated
  apps/uos_swarm build and record actual toolchain, test count, source hash and exit.
- [ ] Have a separate reviewer reproduce the negative cases. A task resultOK
  alone cannot complete this verification work order.

## Task TRUTH — remove misleading health and model labels

Files: fractal_forecast.gleam, ui/wisp/router.gleam,
fractal_forecast_test.gleam and max_worker.py within its existing isolated boundary.
Produces truthful API evidence states; does not imply trained inference.

- [ ] Add failures for six constant health fields: no measured input must yield
  statusunknown and no numeric calibration claim. Fixed histories must be labelled
  fixture/demo and must not emit authorized operational commands.
- [ ] Assert missing telemetry time, expired observation or absent outcome history
  yields unknown/stale, never nominal. Retain a distinct fixture endpoint if useful.
- [ ] Replace literal health with an input-derived evidence state and add
  source_kind, observed_at, source_revision, sample_count and validity information.
  Current constructors forecast_health_json/predict_all_layers are the patch points;
  propagate the typed source state to their router consumers.
- [ ] Check live endpoint response schema, HTTP status and served revision after
  separately authorized rollout. HTTP200 with error:not_found is not a healthy model.
- [ ] Label the deterministic semantic projection as untrained. Require actual
  model/kernel/version/weights-or-artifact digest, invocation and timing receipt
  before reporting MAX/Mojo execution. Preserve useful deterministic features.
- [ ] Run targeted forecast/inference protocol tests and negative consumer tests
  that attempt to act on fixture or stale evidence.

Example acceptance for the existing literal health surface, before the patch:

~~~sh
curl --fail --silent --max-time 5 \
  http://nas-1.tail55d152.ts.net:4100/api/v1/forecast/health |
  jq -e '.status == "unknown" and (.brier_calibration == null)'
~~~

Expected before repair: nonzero. Expected after no-data repair: zero.
Do not execute live mutation or rollout merely because this assertion is specified.

## Task FENCE — use the prepared original-attempt repair

Files: sa_plan_store.ml/.mli, test_sa_plan_leases.ml and tools/sa_plan_execution.ml.
Consumes preserved parent311d2b12 and produces independently reviewed source/caller
compatibility evidence plus separately authorized integration.

- [ ] Inspect its revision-bound journal/review artifact. Re-run its2963assertions
  and stale-attempt/expiry/restart/duplicate-completion cases on the pinned candidate.
- [ ] Verify CLI and every completion/release caller retains the original attempt;
  it must not query the current attempt and use it to authorize old work.
- [ ] Exercise schema/caller compatibility on a private database. No old unfenced
  writer may remain after a later coordinated cutover.
- [ ] Independent reviewer signs evidence for the exact source manifest; controller
  serializes JJ integration and holds runtime deployment until its own gate.

## Task OBSERVE — genuine controlled sensing, no forged receipt

Files: root/current owner interfaces, ops_external_resource_target.ml,
Resource_envelope and bridge programme paths named in the task manifest.
Consumes admitted fencing and resource candidatec502fbd2. Produces fresh
resource-bound observation receipts and their effect-time validation.

- [ ] Re-run resource4343, bridge23 and eight mutation checks from the resource
  specification. Confirm private-record forgery still fails compilation.
- [ ] Implement the root/current prerequisites in the resource specification's
  dependency table. Every new constructor must be owner-only and bound to current
  target/event/effect state; callers cannot supply public Boolean authority.
- [ ] Add bounded real sensing through the actual owner and bind resource identity,
  request, epoch, trusted observed time and expiry. Preserve unavailable status
  until all required owners are constructible and current.
- [ ] Test wrong resource, expired receipt, stale epoch, owner restart, scarce
  resource, changed target and cancellation. All must refuse before effects.
- [ ] Obtain separate review and cutover evidence. This is a larger critical-path
  item; use repeated bounded implementation steps, not a promised one-cycle fix.

## Task HISTORY — measured feedback and forecast outcomes

Files: predictive_zenoh_stream.gleam, fractal_forecast.gleam,
sdlc/forecasting_engine.gleam and tests. Produces retained timestamped observation/
forecast/outcome pairs, with source and model provenance.

- [ ] Introduce an event contract with eventID, sourceID/revision, host/boot,
  UTC, monotonic tick, Lamport, observed value/unit, confidence kind and validity.
  Store through the existing controlled evidence owner; don't add a competing queue.
- [ ] Replay duplicate, late, out-of-order and future-dated input. Deduplicate by
  identity, preserve original timestamps, distinguish receipt time from event time,
  and refuse unsafe causal/validity assumptions.
- [ ] Use explicit sample intervals in trend projection. For bounded metrics,
  reject/report invalid predictions; clamping alone must not fabricate calibration.
- [ ] Retain forecast ID, as-of cutoff, horizon and subsequent outcome. Compute
  Brier only for resolved probability forecasts; regression uses error/coverage.
  No resolved samples means unknown calibration.
- [ ] Verify on a deterministic recorded fixture and an independently observed
  controlled live sequence. Historical fixtures remain labelled as such.

## Task CANARY — initiate a small measurable swarm in the main session

Files: existing board/session/Sa-plan adapters. Depends on all five verification
predecessors. Produces one controller plus at most two discovered workers running
read-only, task-scoped analysis; zero production mutations.

- [ ] Controller creates the canary work through Sa-plan, binds each agent's real
  session, model route, workspace, lease, original attempt and aggregate budget,
  and obtains explicit ACKs via the admitted board route.
- [ ] Run ten short OODA cycles, not a fixed promise of total elapsed time. Each
  cycle carries fresh observations and one verified read-only task outcome.
- [ ] Inject duplicate delivery, expired lease and one worker interruption within
  the private canary scope. Verify no duplicate authoritative completion and no
  stale worker can complete or apply an effect.
- [ ] Require all claimed workers present in readback, zero unauthorized effects,
  task/evidence source agreement, bounded retries and actual cost within the cap.
  Proposed freshness target: telemetry<=30seconds; ACK<=120seconds; host time in
  SC-TIME nominal band. If a target cannot be observed, report unknown and hold expansion.
- [ ] Publish source-bound results and independent review. Missing budget meter,
  stalled cycles, failed fences or inconsistent evidence stop expansion.

## Task EXPAND — add one capability at a time

Consumes the accepted canary receipt. Produces a separately authorized bounded
SDLC or SRE capability with target-side fences and rollback evidence.

- [ ] Choose one acceptance-tested capability: isolated source repair OR read-only
  SRE incident triage. Keep one integration writer and existing worker caps.
- [ ] For any requested runtime effect, acquire separate runtime:service ownership,
  bind candidate, target, rollback and post-check; observation advice alone cannot act.
- [ ] Compare accepted outcomes, duplicate work, elapsed time, budget and incidents
  against the canary. Increase one limit only after evidence supports it.
- [ ] Stop at the first unresolved control failure; preserve receipts and reclaim
  only through the current authority after checking effect outcomes.

## Task MODELS — measured utility after stabilization

Consumes trustworthy HISTORY/CANARY evidence. Produces an evaluation report before
any trained runtime admission.

- [ ] Benchmark deterministic incident deduplication, task-duration baseline and
  evidence retrieval on chronological held-out data.
- [ ] Evaluate one small model only where the baseline has a measured gap. Record
  training/input provenance, exact model artifact, leakage checks, accuracy,
  calibration, latency, memory and total cost per accepted outcome.
- [ ] Admit to the existing Gleam-supervised MAX/Mojo boundary only if actual
  execution is observed and the measured utility exceeds the stated baseline goal.
- [ ] Keep Rete/STPA/FMEA checks authoritative only through their typed policy
  roles; model/Ruliad advice cannot self-authorize production changes.

## Board handoff draft — UNPOSTED

The task manifest carries the same draft as data. A main-session sender must
supply its real authenticated identity and observed time through the board API.

~~~text
Plan: uos/hive-stabilization/20260907-2036
Goal: truthful evidence + fenced ownership, then bounded read-only canary.
First: HANDOFF; verify current COORD-JOURNAL-DB candidate, don't duplicate it.
Ready after HANDOFF: COORD verification and TRUTH repair in disjoint scopes.
Reuse: fencing311d2b12; resourcec502fbd2, locally tested and not admitted.
Required ACK: real session, task, workspace/paths, base revision, budget, blockers.
Safety: no journal rewrite; no runtime cutover from board ACK or model advice.
Report: source/evidence refs, observation UTC+monotonic+Lamport, outcome, next.
~~~

## Completion and acceptance

DESIGN completion means this plan, task DAG, risk packet and journal exist and
were structurally checked. It does not complete HANDOFF, contact peers or initiate
the canary. Future execution requires a fresh whole-plan risk portfolio and exact
eligible claims; this planning packet alone must not be reused as execution clearance.

## Verification checklist

This planning package does not certify runtime health or authorize dispatch.

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Host time, chrony receipt and timestamp prefix recorded.
- [x] CHK-02-TAIL — Full Tailscale FQDN links supplied; plan unpublished.
- [x] CHK-03-FRACT — Applicable fractal and ZK tags supplied.
- [x] CHK-04-KM — Plan, journal, task manifest and risk packet linked.

</details>
<details><summary>Domain 2 — Zero-Muda and storage safety</summary>

- [ ] CHK-05-MUDA — Whole-repository exclusion scan UNRUN.
- [ ] CHK-06-GRAPH — Runtime dependency/NIF conformance UNRUN.
- [ ] CHK-07-DRIVE — Storage safety execution UNRUN; planning performs no storage changes.

</details>
<details><summary>Domain 3 — Testing and mathematical gates</summary>

- [ ] CHK-08-C1C8 — Full UI/test categories UNRUN.
- [ ] CHK-09-MATH — Formal system admission gates UNRUN.
- [ ] CHK-10-9MOD — Nine runtime modalities UNRUN.
- [ ] CHK-11-REGR — Live UI regression monitoring UNRUN.

</details>
<details><summary>Domain 4 — Cross-language control and observability</summary>

- [ ] CHK-12-GLEAM — Swarm/OTP initialization UNRUN in this side conversation.
- [ ] CHK-13-HERMES — Existing candidate has local tests; operational owner blocked.
- [ ] CHK-14-ZIGVM — Runtime kernel verification UNRUN.
- [ ] CHK-15-MAX — Trained MAX/Mojo runtime use UNVERIFIED.
- [ ] CHK-16-OTEL — Measured end-to-end telemetry correlation UNRUN.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Independent execution-plan review and runtime admission UNRUN.
- [x] CHK-18-JJ — Isolated JJ plan child; task operations through Sa-plan.

</details>
