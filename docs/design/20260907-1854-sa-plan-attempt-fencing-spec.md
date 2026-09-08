# Sa-plan task-attempt fencing candidate

Observed: 2026-09-07T19:22:45Z. Package prefix is the task-start UTC hour/second stamp.
Status: IMPLEMENTED_AND_LOCALLY_TESTED; NOT_ADMITTED.
Identity: codex-side-hive-fencing. Sa-plan: uos/hive-fencing/20260907-1854 / FENCE-CANDIDATE / attempt 1.
Base: 3c05ee107bdfb2a5f4cab16b1c04377c55e909d7.
JJ change: pnmksopxqrzrroxsqwoqsywsknzolpqk.
Tags: #fractal-l0 #fractal-l3 #fractal-l4 #fractal-l6 #fractal-l9 #zk-adr #zero-muda.

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

Navigation targets are unverified in this side session. This isolated candidate is not published.

## 1. Scope and observations

A worker whose task or job lease has expired or been replaced must not complete
or release that work using its old claim, including when the new worker has the
same name. Bridge leases must retain the task attempt from acquisition.

The observable state is resource identity, phase, worker, attempt, expiry, result
and retry availability. A claim is an attempt receipt; a completion/release is a
command; the SQLite transaction is the aggregate boundary. The CLI and manual
swarm adapter translate commands. These receipts prevent stale cooperative
writers; they are not cryptographic identities or deployment capabilities.

This candidate extends existing Hermes OCaml persistence. Gleam/OTP remains the
supervisory authority. It introduces no service, model dependency or native
kernel. The generic workflow/activity and administrative cancellation APIs are
outside this slice and still need their own effect authorization.

Governing references: contracts/rules/20260907-1559-risk-prioritization-sop.md,
contracts/rules/20260907-1606-risk-checker-contract.md and
contracts/rules/20260907-0653-tri-agent-coordination.md.
Related parent backlog: uos/full-implementation/20260906-1655:P01; referenced,
not claimed or completed by this candidate.

## 2. Required laws and interfaces

Let R be a task/job state, C the caller's original claim, and n an observed local
wall-clock time in nanoseconds. Worker names are opaque authenticated-adapter
inputs; obtaining a name or guessing a public attempt number is not authorization.

Authorized(R,C,n) :=
  R.phase = executing AND R.worker = C.worker AND
  R.attempt = C.attempt AND C.attempt > 0 AND n >= 0 AND R.expiry > n.

| Law | Required behavior | Executable evidence |
|---|---|---|
| F-01 Ownership | Accepted completion/release implies Authorized(R,C,n). | Finite-state oracle, job negatives and CLI tests. |
| F-02 No mutation on refusal | Rejected command preserves state, owner, attempt, expiry and result. | Independent readonly SQLite observations before/after adversarial commands. |
| F-03 No ABA with worker reuse | After another claim, every earlier attempt is rejected even if worker names match. | Same-worker task/job restart and 729 oracle traces. |
| F-04 Exclusive expiry | n = expiry rejects finalization and permits eligible reclaim. | Task, job, bridge and swarm-adapter equality checks. |
| F-05 Bounded acquisition | Worker nonblank; n >= 0; duration > 0; n + duration and next attempt/fence must fit. | Invalid-input, overflow and exhausted-counter fixtures. |
| F-06 Dependency closure | Neither generic nor bridge claim bypasses unfinished task dependencies. | Existing dependency tests and new bridge control. |
| F-07 Durable bridge binding | Bridge owner/id/fence and both expiries must be valid; stored task_attempt must equal the actual task attempt. | Cross-path release/reclaim and restart tests. |
| F-08 Legacy uncertainty | A pre-v7 bridge lease has task_attempt = None and cannot complete. A new eligible claim binds an attempt. | v6-shaped fixture migration, refusal and fresh claim. |
| F-09 Atomic competing claim | Two connections racing to reclaim produce one winner; old receipt cannot complete. | Two-domain, two-connection SQLite test. |
| F-10 Retry boundedness | Error outcomes are fenced too; retry time arithmetic must not wrap. | Error/retry takeover and overflow tests. |

Public Store API changes: release_task, complete_task and complete_job require
expected_attempt:int with no optional fallback. Callers retain the attempt from
claim_task/claim_next/claim_job; they must never query a current row to replace a
missing caller attempt. bridge_lease gains task_attempt:int option.

CLI 0.4.0 requires exact arguments:

    task release PLAN TASK WORKER ATTEMPT
    task complete PLAN TASK WORKER ATTEMPT RESULT
    job complete JOB WORKER ATTEMPT OK|ERROR RESULT

Legacy completion syntax is refused. ATTEMPT must be a positive representable
decimal integer. Claims expose attempt; jobs now expose lease_until_ns too.
Store errors remain explicit results. The manual adapter rechecks the bound
task before stage recording, resumed start and completion, and passes the
validated original job attempt to the finalizer.

The equations above are normative requirements. The pure Oracle interpretation
and SQLite interpretation agree over 729 explicitly enumerated four-action
traces (one initial claim plus three actions from nine choices). This is bounded
execution evidence, not an unbounded theorem, Lean proof or distributed-clock
proof. Eight retained bridge checks plus 2,955 new assertions pass.

## 3. STPA, FMEA and prioritization

The controller is Sa-plan; its control action is accepting work completion,
release or claim. The losses are false completion, duplicate effects and
misleading readiness. The controlled state includes dependencies, worker,
attempt, lease and bridge binding.

| Unsafe control action | Hazard | Constraint |
|---|---|---|
| Required completion/reclaim withheld indefinitely | Starvation after worker loss | Reclaim eligible work at expiry; preserve current attempt receipt. |
| Stale completion/release provided | Replaced worker changes current state | Require original attempt, worker, executing state and expiry together. |
| Completion accepted too late or takeover too early | Split ownership | Use one exclusive expiry boundary and atomic acquisition. |
| Authority persists after release, completion or upgrade | Old bridge receipt governs new work | Check bound task state/attempt; unknown legacy binding refuses. |

FMEA estimate FM-STALE-WRITER: severity 5, occurrence 3, detection difficulty 4,
RPN 60, severity-floor band 5. These are analyst estimates, not measured failure
frequencies. This bounded source candidate is P2 with C3 × STPA4 × FMEA5 ×
dependency5 × impact5 = 1500. Expanded autonomous side effects remain a P1
integration concern; a score or passing checker does not authorize them.

Decision summary: reuse the existing durable store and bridge fence, add explicit
attempts to finalizers, and preserve original claim identity at adapters.
Worker-only checks, automatic latest-attempt lookup and silently backfilling
legacy leases were rejected because they allow stale authority to become current.

Forecast: old receipts fail after takeover without changing durable state.
Falsifier: a stale worker successfully completes/releases after a newer claim,
or a migrated lease infers authority from a current row. These conditions are
covered by tests and targeted semantic mutants. Forecast calibration over
production outcomes is unavailable.

## 4. Migration and rollout contract

Schema v7 adds a nullable task_attempt to sa_plan_bridge_lease. Migration preserves
legacy rows with NULL. No production database was migrated in this side session.

Integration must serialize ownership, preserve a consistent database backup,
drain or stop old writers under the operator's runtime authority, and deploy
compatible callers and store code together. An old binary is not an acceptable
post-migration writer. The v6 binary refuses a future schema on reopen, but an
already open v6 process can still issue legacy writes; draining is mandatory.

Outstanding v6 bridge work waits for expiry before a new claim binds its task
attempt. Generic claims already carry attempts, so callers must retain those
receipts or wait for fresh claims; they must not invent them from a live row.
Release followed by a generic claim can leave a bridge lease present until its
original expiry; the bound-attempt check prevents its use during that interval.

Prefer a compatible forward repair after migration. Restoring a database backup
requires separately controlled handling of effects and observations created
since the backup. This document grants no rollback, migration or deployment authority.

A database commit is not atomic with an external tool, filesystem or network
effect. Recipients still need fencing-token checks and idempotency keys, with an
outbox/reconciliation path for uncertain results. Attempts are scoped to a durable
resource lineage; deleting/recreating resources or restoring old backups must not
reset externally accepted authority.

## 5. Validation and reproduction

Observed toolchain: OCaml 5.5.0, Dune 3.23.1. Tests used isolated temporary stores.
Candidate source and receipt hashes are recorded in docs/reviews/20260907-1854-sa-plan-attempt-fencing-review.json.

| Check | Result |
|---|---|
| Candidate Sa-plan targets and integration test build, one Dune job | PASS |
| Existing ops verify --full --no-build --require-complete against candidate | 12 passed, 1 failed, 296 unbuilt/skipped; exit 1 |
| Fencing executable | 2,955 new + 8 retained checks passed; 729 bounded traces |
| Mutations through existing Ops_mutate, narrowed build adapter | 6 killed, 0 survived, 0 void |
| Real CLI, retained attempts 1 then 2 | 5 expected rejections; current task/job completions passed |
| Manual swarm adapter | 45 checks passed |
| Planning adapter scratch selftest | 10 checks passed |
| Existing sa_plan_test executable | Exit 0 |
| Active risk checker | ACTIVE_OBSERVATION_PASS; authority NONE |
| Peer review, full mathematical gates, runtime cutover | UNRUN / NOT_ADMITTED |

The one failing integration assertion is "operator state path passes resource
preflight". Its unchanged Resource_envelope interface intentionally marks
operational observation unavailable pending a receipt-bound owner; every
non-empty preflight refuses. This candidate does not bypass or repair that
separate authority. Unbuilt suites are not passing evidence.

From the isolated workspace's engines/hermes directory:

    dune build -j 1 @modules/sa_plan/test/all modules/system_engg/test_run_swarm_bridge_programme.exe modules/sa_plan/sa_plan.cma
    ocaml -I modules/hermes_ops ../../tools/20260907-1854-sa-plan-fencing-mutations.ml --dune /absolute/path/to/dune
    dune build -j 1 @modules/sa_plan/test/all modules/system_engg/test_run_swarm_bridge_programme.exe
    _build/default/modules/sa_plan/test/test_sa_plan_leases.exe

The rebuild after mutation is mandatory: Ops_mutate restores source bytes;
the last built executable can still contain a mutation. Its adapter limits each
build to one job and 30 seconds and each suite to 15 seconds. The runner refuses
the canonical workspace. It does not change Ops_mutate or installed tools.

From the selected repository root, with that repository's library already built:

    ocaml -I tools tools/test_sa_plan_swarm.ml
    ocaml tools/sa_plan_execution.ml selftest governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json

These scripts now load the selected repository's library, rather than silently
loading the canonical live build. Set an isolated TMPDIR for fixed-name module
fixtures. The manual swarm test uses unique /tmp/uos-sa-plan-* fixtures to satisfy
its path policy; it does not access the operational store.

## 6. Remaining work in dependency order

1. P1 before integration: restore receipt-bound operational resource observation
   and rerun the failing gate; obtain independent candidate review.
2. P1 before runtime migration: plan compatible writer draining, backup,
   migration, restart/reclaim and recovery under serialized runtime ownership.
3. P1 before autonomous external writes: enforce fencing and idempotency at
   recipients; validate policy/delegated identity and clock freshness at actual use.
4. P2 following these prerequisites: apply comparable claims to generic workflow,
   activity, cancellation and other effect paths; test adapter crash/reconciliation.
5. P2: connect outcome measurements to forecasts and risk ranking. Agent counts,
   board acknowledgements and local test totals are not operational success KPIs.

These are proposed follow-up priorities, not new claims or assigned work.

Related journal: docs/journal/20260907-1854-sa-plan-attempt-fencing-journal.md.

## Verification checklist

This is an isolated OCaml candidate. The entries below do not assert fleet or production conformance.
UNRUN and NOT_ADMITTED remain nonpassing; N/A must be justified for each actual change.

<details><summary>Domain 1 — Metadata and navigation</summary>

- [x] CHK-01-TIME — Host timestamp recorded.
- [x] CHK-02-TAIL — Full Tailscale FQDN references provided; live delivery unverified.
- [x] CHK-03-FRACT — L0–L9 applicability tagged.
- [x] CHK-04-KM — Specification, evidence, governing SOP and journal referenced in this package.

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
- [ ] CHK-13-HERMES — Task/job/bridge finalizers locally tested; whole-system enforcement NOT_ADMITTED.
- [ ] CHK-14-ZIGVM — Runtime kernel checks UNRUN.
- [ ] CHK-15-MAX — Actual inference checks UNRUN.
- [ ] CHK-16-OTEL — Runtime telemetry correlation UNRUN.

</details>
<details><summary>Domain 5 — Governance and Jujutsu</summary>

- [ ] CHK-17-SOV — Independent review/admission NOT_ADMITTED.
- [x] CHK-18-JJ — Isolated JJ candidate only; no native Git command, mainline integration or runtime cutover.

</details>
