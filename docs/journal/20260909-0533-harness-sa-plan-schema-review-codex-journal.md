# 20260909-0533 — Harness feature registry and durable execution review

#fractal-l0 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l6 #fractal-l8 #zk-adr #zero-muda

Observed authority clock: 2026-09-09T05:46:33Z. [UOS](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Receipt](http://nas-1.tail55d152.ts.net:4100/files/governance/sources/20260909-0533-harness-sa-plan-schema-review-receipt.json) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

## 1. Scope & Trigger

The user requires all harness features and progress to be represented in canonical Sa-plan SQLite, with tasks, jobs and Temporal exposed through the Gleam MCP harness. Root assigned a bounded read-only schema/runtime review under the explicitly approved local development bootstrap. Task: `uos/harness-schema-review/bootstrap`, `SCHEMA-REVIEW`, worker `codex-ecology-capabilities`, attempt 1.

## 2. Pre-State Assessment

The existing executable stores plans, tasks, jobs, workflow history, bridge commands and leases in `var/sa-plan/uos.sqlite3`. `tools/sa-plan` delegates to the realized Hermes `sa_plan_main.exe`. The staged Gleam MCP harness has a finite development grant for its bootstrap task; no callable harness connector was present in this agent's tool inventory. This review does not establish universal MCP enforcement.

## 3. Execution Detail

Read the canonical store interfaces and implementations, normalized CLI dispatch, Gleam bridge and pure planning model. Observed canonical preflight before the exact claim, followed by an active check. Inspected local listener/process names and user service names without reading process arguments, credentials or external trees. No implementation tests, shared source edits, runtime transitions, external requests or new automation were performed.

## 4. Root Cause Analysis

`oban` and `temporal` are aliases for local SQLite commands. Their names and the pure Gleam types do not prove a live Oban/Temporal integration. Separately, `plan list`, the UI observer and default progress commands use the historical `infranodus-fractal-closure-20260804-0936` program. Treating them as a universal registry would omit current harness features.

## 5. Fix Taxonomy

The recommended slice is a Gleam projection over canonical records, followed by narrowly authorized mutation handlers. Keep feature presence, implementation stage, task execution state, backend connectivity and system admission separate. A completed planning task or a cached workflow activity is not fresh runtime evidence.

## 6. Patterns & Anti-Patterns Discovered

Plain plan/task/job/workflow creation uses `INSERT`: duplicate IDs conflict, including identical retries. Task and job completion/release require the original worker, attempt and unexpired lease; SQL compares those fields again. Job claim selects the next queue entry, not an exact job ID, and does not consult task dependencies or enforce the configured job worker field. Expired job claims can be reclaimed; `max_attempts` is checked when an error is completed, not as a universal claim ceiling.

Workflow activity replay returns the old result for an existing `(workflow, key)` without comparing incoming activity ID, name or result. The current durable test explicitly expects changed `digest-2` to replay `digest-1`. Workflow completion/failure has a running-state compare-and-set but no worker/attempt lease fence. These operations need a typed harness authority layer and content-bound command receipt before exposure to agents.

The stronger existing pattern is `ensure_bridge_mapping`: same identity with different source/dependency/prompt/safety/formal hashes is refused. `record_bridge_command` replays a matching command/request hash and refuses a changed request hash. Reuse this behavior after reviewing its typed domain model; do not silently overload a bridge domain with a new feature namespace.

## 7. Verification Matrix

| Observation | Result | Practical limit |
|---|---|---|
| Canonical preflight | PASS at 05:46:06Z | No effect authority |
| Exact claim and active check | Attempt 1, PASS at 05:46:33Z | Scoped read-only review |
| CLI and SQLite source | Candidate hashes retained | Compiled binary parity was not rerun |
| Local TCP 7233/8233 | No listeners observed | Other ports and remote servers remain unknown |
| Process/user-service names | No Temporal/Oban names observed | Does not exclude an embedded or remote worker |
| Targeted SDK/config search | No integration calls in inspected paths | Not a whole-filesystem absence proof |
| Durable unit tests | Read as evidence, not executed | No fresh passing test count claimed |

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME: canonical active observation supplies synchronized host time.
- [x] CHK-02-TAIL: operational links use Tailscale FQDNs.
- [x] CHK-03-FRACT: control, durable execution, review and evidence layers tagged.
- [ ] CHK-04-KM: parent owns grouped wiki/ZK publication.

</details>
<details><summary>Domain 2 — Purity and storage</summary>

- [x] CHK-05-MUDA: no packages or prohibited dependencies introduced.
- [x] CHK-06-GRAPH: no foreign graph or NIF change.
- [x] CHK-07-DRIVE: no direct database writes or runtime mutations.

</details>
<details><summary>Domain 3 — Testing and mathematics</summary>

- [ ] CHK-08-C1C8: implementation testing is a future slice.
- [ ] CHK-09-MATH: no formal runtime proof claimed.
- [x] CHK-10-9MOD: source, command and runtime observations distinguished.
- [ ] CHK-11-REGR: proposed regressions are not yet executed.

</details>
<details><summary>Domain 4 — Control and observability</summary>

- [x] CHK-12-GLEAM: staged bridge and harness boundaries inspected.
- [x] CHK-13-HERMES: canonical SQLite store contracts inspected.
- [ ] CHK-14-ZIGVM: no new external runtime evidence.
- [ ] CHK-15-MAX: outside this read-only slice.
- [ ] CHK-16-OTEL: no end-to-end telemetry admission claim.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV: system admission not granted; EV ceiling 93 unchanged.
- [x] CHK-18-JJ: exact canonical task claim, no VCS mutations.

</details>

## 8. Files Modified

Only this journal and its linked source receipt were authored. Canonical task records were created/claimed through Sa-plan. The existing native risk helper was reused with parent-confirmed bootstrap authorization; no new OCaml, Python or shell automation was authored. Exact inspected source SHA256 values are in the receipt.

## 9. Architectural Observations

Implement the next slice in this order:

1. Define a Gleam `FeatureSpec` catalog with stable feature ID, declarative intent/spec hash, algebra/atlas references, role/backend requirements, acceptance evidence and task/dependency links. Register every planned feature as a canonical task before work begins. Store a versioned catalog projection in canonical workflow input or a reviewed Sa-plan schema API; a loose JSON file is not execution authority.
2. Add a finite read-only MCP snapshot for an explicit allowed plan. Read tasks plus result/lease/dependency fields, relevant jobs and workflow events in one bounded read transaction. Current `task_view`/CLI omit result and lease detail; the existing task observation interface exposes lease/dependencies but still needs typed result evidence. Do not use the hardcoded `plan list`/UI observer as a global listing.
3. Derive declared/implemented/built/executed/verified from candidate-bound receipts, while retaining Sa-plan's available/executing/completed state. Missing or stale source/formal/runtime receipts remain unknown. Compare the entire declared feature set against registered tasks and exposed MCP tools; missing tasks must reduce coverage rather than disappear from the denominator.
4. Add finite create/claim/finish MCP commands bound to launcher principal, role, plan/task, original attempt, clock and source digest. Bind command IDs to complete canonical request hashes. Identical retries replay a stored receipt; changed bodies conflict. Multi-command CLI registration is not atomic: record an intent and reconcile partial creation, or add one reviewed transactional Sa-plan operation. Never publish a half-created feature as ready.
5. Keep jobs locally labeled `sa_plan_sqlite` until a real worker is observed. A job must link to a current authorized task and dependency snapshot; queue position cannot substitute for exact-job/task binding. Keep workflows labeled `sa_plan_local_history` until a verified external backend is connected. Native backend selection remains a Gleam harness decision.
6. For real Temporal, require configured server/namespace/task queue, observed server identity, worker build/source ID, returned workflow/run IDs, a completed activity, and crash/replay evidence. For real Oban, require the actual Oban engine/persistence configuration and worker observations; a similarly named SQLite queue is insufficient. External effect retries require their own deduplication/fencing contracts.

Exact existing argv, passed as separate arguments to `tools/sa-plan`:

| Purpose | Arguments |
|---|---|
| Plan create/show | `plan create ID NAME TITLE`; `plan show ID --format json` |
| Task register | `task create PLAN ID NAME TITLE PARENT_OR_DASH DEPS_CSV_OR_DASH PRIORITY` |
| Task read/claim | `task list PLAN --format json`; `task claim WORKER PLAN LEASE_NS TASK` |
| Task finish/release | `task complete PLAN TASK WORKER ATTEMPT RESULT`; `task release PLAN TASK WORKER ATTEMPT` |
| Job enqueue/claim | `job enqueue ID NAME QUEUE WORKER ARGS MAX_ATTEMPTS`; `job claim QUEUE WORKER LEASE_NS` |
| Job finish/read | `job complete ID WORKER ATTEMPT OK_OR_ERROR RESULT`; `job list QUEUE --format json` |
| Workflow register/activity | `workflow start ID NAME KIND INPUT`; `workflow activity WORKFLOW ACTIVITY NAME KEY RESULT` |
| Workflow finish/read | `workflow complete WORKFLOW RESULT`; `workflow fail WORKFLOW ERROR`; `workflow history WORKFLOW --format json` |

Names must satisfy the hierarchical name parser. CLI JSON output consists of separate objects per row with string-valued fields; a zero exit is not a decoded positive claim. There is no external Temporal server dispatch in these argv.

## 10. Remaining Gaps

No generic feature registry or all-plan MCP projection is implemented by this review. Real Temporal/Oban connection status remains unverified; local evidence supports only SQLite semantics. Agent identity enforcement remains a cooperative finite development grant. Atomic task/job/workflow registration, exact content-bound activity replay, backend effect fencing and candidate-bound progress are implementation work, not completed by this report.

## 11. Metrics Summary

Ten principal source files bound by SHA256, one canonical review task, two authority observations, zero builds/tests/model calls/runtime effects/shared code edits. A broad preliminary search was truncated and was not used as absence evidence; the final search was restricted to named source/config paths and file types. The prior evaluator task remains separately pending with its frozen native evidence preserved.

## 12. STAMP & Constitutional Alignment

Raw review FMEA retains S4/O3/Det3, RPN36. Unsafe-control cases include omitting a feature from the registry, treating modeled history as a live service, accepting stale source/lease evidence, and continuing job retries beyond intended limits. Source hashes, dependency readiness, exact attempt fencing and unknown status take precedence over progress percentages. Root explicitly confirmed the one-time local development bootstrap exception; it is not universal permission to bypass the future MCP boundary.

## 13. Conclusion

Build the Gleam feature registry as a projection of canonical Sa-plan records with separately verified evidence stages. Reuse the existing task/job fences and content-bound bridge receipt patterns. Label current workflows as local durable history until a real server and worker have invocation-specific evidence.

**Previous:** [OpenRouter profile review](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260909-0308-ecology-model-profiles-codex-journal.md) · **Next:** [Planning cockpit](http://nas-1.tail55d152.ts.net:4100/planning)

**UOS footer:** Source review and task completion do not grant deployment, external execution or system admission.
