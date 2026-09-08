# Sa-plan attempt fencing — implementation journal

Observed host clock: 2026-09-07T19:22:45Z; chrony stratum 3, normal leap status,
system offset 0.000083021 seconds fast. Prefix 20260907-1854 is the initial
task-start UTC hour/second stamp.
Tags: #fractal-l0 #fractal-l3 #fractal-l4 #fractal-l6 #fractal-l9 #zk-adr #zero-muda.

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk)

Navigation targets are unverified in this side session. This isolated candidate is not published.

## 1. Scope & Trigger

The side-conversation operator said "continue" after the recommendation to close
stale-worker authority gaps at Sa-plan boundaries. Implement a reviewable isolated
candidate; preserve the main thread, production services and other work claims.

Specification: docs/design/20260907-1854-sa-plan-attempt-fencing-spec.md. Evidence: docs/reviews/20260907-1854-sa-plan-attempt-fencing-review.json.

## 2. Pre-State Assessment

Base revision 3c05ee107bdfb2a5f4cab16b1c04377c55e909d7 had worker-only generic
task/release/job finalizers. Bridge completion had a durable fence but no binding
to the task attempt, and accepted expiry equality. Related unclaimed parent P01
was referenced without claiming it. No parent task was continued here.

The own plan is uos/hive-fencing/20260907-1854, task FENCE-CANDIDATE, worker
codex-side-hive-fencing, attempt 1. C3 × STPA4 × FMEA5 × dependency5 × impact5
gave P2/1500 for the bounded source candidate. Initial risk preflight passed
before claiming. Expanded autonomous effects remain separately gated.

## 3. Execution Detail

Created .uos-workspaces/codex-side-hive-fencing and pinned its source base.
The initial workspace-add command used --ignore-working-copy, which created
metadata but could not materialize files. Recovery stayed inside that new
workspace: a restore produced a tree on a root-parent commit, followed by
jj new at the intended pinned base. The final candidate is a child of that
base; no root source tree or integration bookmark was rewritten.

Authored public interface laws, added mandatory original attempts, exclusive
expiry, overflow checks and v7 bridge attempt binding. Updated actual callers,
CLI help/validation and the manual adapter. Repository-relative OCaml loading
ensures tests use the candidate library. Added a bounded independent state
oracle, SQLite race/restart/migration tests, CLI negatives and six semantic
mutants using the existing Ops_mutate with a scoped build adapter.

A fresh active risk check confirmed owner, attempt, unexpired own lease and
four candidate source hashes at 2026-09-07T19:09:16Z. It explicitly granted
no execution or runtime admission authority.

## 4. Root Cause Analysis

Worker names persisted across attempts, so worker equality could not distinguish
an earlier execution from a current one. Generic completion omitted both attempt
and expiry. Bridge identity was durable but separate from mutable task identity.
Duplicate definitions of the expiry boundary created another inconsistency.

These were implementation observations. The broad verifier's separate resource
preflight failure was not evidence that the fencing change failed.

## 5. Fix Taxonomy

Concurrency: caller-retained attempt and transactional compare-and-set.
Durability: nullable legacy bridge binding, established only by new acquisition.
Temporal semantics: one exclusive expiry boundary and checked arithmetic.
Integration: typed callers, strict CLI grammar and repository-bound library load.
Verification: state oracle, actual stores, two connections, hostile inputs and
semantic mutation. No new service or external code ingestion.

## 6. Patterns & Anti-Patterns Discovered

Retain claim receipts; do not synthesize a current receipt for a stale worker.
A bridge mapping is not enough unless it stays bound to the actual task attempt.
Migration uncertainty must remain explicit. Byte restoration after mutation
does not rebuild the executable; a post-mutation rebuild is necessary.

The normal verifier makes unbuilt suites explicit. Its whole-system report must
not be reduced to the passing Sa-plan subset. Test wrapper mistakes were visible:
an OCaml option comparison required Option.equal, toplevel include/dependency
paths needed correction, and CLI usage errors returned 2 rather than 1.
A risk record with the unsupported phase value "verification" was refused and
corrected to the canonical "implementation" enum before active checking.

## 7. Verification Matrix

| Verification | Observation |
|---|---|
| OCaml 5.5.0 / Dune 3.23.1, one-job targeted build | PASS |
| Sa-plan suites via existing ops verify | 12 passed |
| New fencing assertions | 2,955 passed, including 729 oracle traces |
| Retained bridge assertions | 8 passed; total fencing executable lines 2,963 |
| Six guard-removal mutants | 6 killed, 0 survived, 0 void; source restored |
| CLI current attempts and stale commands | PASS; 5 expected rejections, task/job current completion |
| Manual adapter | 45 passed |
| Planning adapter scratch selftest | 10 passed |
| Existing sa_plan_test executable | Exit 0 |
| Whole repository verifier | Exit 1: 1 resource-preflight assertion failed, 296 unbuilt/skipped |
| Active risk checker | ACTIVE_OBSERVATION_PASS, authority NONE |
| Independent sovereign review, Lean/Quint proof, deployment | UNRUN / NOT_ADMITTED |

The unchanged resource interface explicitly makes operational observation
unavailable pending the controlled owner. Do not replace that absence with a
fabricated pass. Formal evidence here is bounded executable-model comparison;
it does not prove arbitrary executions, clock trust or remote-effect atomicity.

## 8. Files Modified

- engines/hermes/modules/sa_plan/sa_plan_c3i_reference.ml
- engines/hermes/modules/sa_plan/sa_plan_store.ml
- engines/hermes/modules/sa_plan/sa_plan_store.mli
- engines/hermes/modules/sa_plan/test/dune
- engines/hermes/modules/sa_plan/test/sa_plan_cli.ml
- engines/hermes/modules/sa_plan/test/sa_plan_main.ml
- engines/hermes/modules/sa_plan/test/test_sa_plan_cli.ml
- engines/hermes/modules/sa_plan/test/test_sa_plan_durable.ml
- engines/hermes/modules/sa_plan/test/test_sa_plan_leases.ml
- engines/hermes/modules/sa_plan/test/test_sa_plan_observability.ml
- engines/hermes/modules/sa_plan/test/test_sa_plan_observability_kpi.ml
- engines/hermes/modules/sa_plan/test/test_sa_plan_observation.ml
- engines/hermes/modules/system_engg/test_run_swarm_bridge_programme.ml
- tools/20260907-1854-sa-plan-fencing-mutations.ml
- tools/sa_plan_execution.ml
- tools/sa_plan_swarm.ml
- tools/test_sa_plan_swarm.ml

New specification, this journal and review evidence are timestamped artifacts.
No source ingestion, global skill installation, shared board write, runtime
restart or mainline integration was performed.

## 9. Architectural Observations

The candidate remains in Hermes OCaml because Sa-plan already owns durable
SQLite state there. Gleam/OTP supervision and target-side policy remain distinct
authorities. A board acknowledgement, priority score or lease does not substitute
for authorization of a filesystem, network or production effect.

The source interface was specified before implementation. The finite oracle was
added while extending the existing store; this was not an oracle-first rewrite
or a completed full mathematical admission pipeline.

## 10. Remaining Gaps

Independent review and the failing resource gate block admission. Before any
cutover, coordinate writer draining and schema/caller compatibility; existing
open v6 processes must not remain writers. Add receipt-bound fencing/idempotency
at effect recipients and equivalent authority for workflow/activity/cancellation
paths. Recheck trusted host time at use; Store now_ns is an adapter input and
cannot authenticate itself. Durable epochs must survive backup/restore and
resource recreation. Whole-fleet checks and telemetry correlation remain unrun.

## 11. Metrics Summary

One isolated candidate and one own Sa-plan claim; no additional model calls,
remote swarm sessions or paid provider requests. Primary conversation cost was
not measured. New oracle domain: 9 choices at each of 3 suffix positions,
729 traces and 2,916 transition comparisons, within the 2,955 new assertion total.
Six targeted mutants were detected. These are verification measures, not
claims about hive intelligence or consciousness.

## 12. STAMP & Constitutional Alignment

STPA covers withheld control, unsafe control, timing and duration.
FMEA S5/O3/Det4/RPN60 is an analyst prioritization estimate. Fenced ownership,
fail-closed legacy migration and truthful nonpassing evidence implement the
relevant constraints. Jujutsu isolation, Sa-plan task bookkeeping, 18-check
disclosure and existing architecture boundaries were retained. No new permission
or autonomous-effect authority is conferred.

## 13. Conclusion

A locally tested attempt-fencing candidate is ready for review. It prevents the
tested stale-owner/attempt/expiry transitions and retains original claim identity
through the updated adapters. Production behavior has not been changed or admitted.
The exact source manifest and reproduction commands accompany the candidate.

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
