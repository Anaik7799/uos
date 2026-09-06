# UOS sa-plan execution planning journal

- Timestamp: `20260906-1655-`, bound to planning-start observation `2026-09-06T16:55:55Z` (UTC hour and seconds).
- Host synchronization: chrony Normal; system 0.000773245 seconds fast of NTP at the recorded observation.
- Plan: [Execution plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-1655-uos-sa-plan-execution-plan.md).
- Work contracts: [All work items](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-1655-uos-sa-plan-work-items.md).
- Native state and verification: [Registration receipt](http://nas-1.tail55d152.ts.net:4100/files/governance/sources/20260906-1655-uos-sa-plan-registration-receipt.json).
- Source specification: [Execution manifest](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json).
- This journal: [Tailscale link](http://nas-1.tail55d152.ts.net:4100/docs/journal/20260906-1655-uos-sa-plan-execution-planning-journal.md).
- Native plan ID: `uos/full-implementation/20260906-1655`.
- Status authority: sa-plan; this journal records the planning task, not system admission.

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #km-triad #zero-muda #tailscale-web

## 1. Scope & Trigger

The operator requested a plan to execute all original work items and remaining review findings, using sa-plan for every task, job and workflow. The work creates executable task contracts, dependency order, native registration and a bounded readback/registration adapter.

The 60-item backlog and nine Codex findings remain the baseline. Full implementation, browser execution, native feature admission and independent reviewer approval are not claimed by this planning task.

## 2. Pre-State Assessment

Canonical main was `53308442c6ef81c509abbf402e9b44f58801f6d1`; the working change `56c2bec3` also held the preceding Codex review artifacts. Created isolated Jujutsu workspace `.uos-workspaces/sa-plan-execution` from that change, preserving all existing work.

The existing OCaml-to-Gleam sa-plan database was present. Read-only observation confirmed 75 available tasks, 74 available jobs with zero attempts and one open workflow. Those records remain in their original store.

## 3. Execution Detail

Read the original backlog, workstream specifications, sa-plan Store/CLI source and previous registration receipts. The general CLI status/tree views select a hardcoded legacy plan; job claims do not enforce task dependencies. Added explicit tasks P01-P04 for those integration gaps and K/Q/N tasks for the remaining worker, ingestion, conformance, test and peer-service issues.

Generated a 71-task programme, 71 job contracts, 13 workflow definitions, 26 eligibility waves, all 35 original requirement mappings, nine finding mappings and 75 links to existing legacy tasks. The native registration uses Sa_plan.Store APIs in one transaction; it does not issue raw SQL writes or dispatch implementation workers.

Executed scratch-store controls for registration/readback, replay, unknown dependency, cycle, conflicting metadata, failed-update preservation, atomic rollback, dependency claim rejection, planning-only completion and completion replay. Separately read the new task and job records through the existing sa-plan CLI.

## 4. Root Cause Analysis

The previous backlog was an implementation specification, not a registered unified execution programme. The older 75-task registration existed in another store and would be lost or duplicated if reconstructed from its summary.

The current sa-plan CLI also has legacy defaults that can show the wrong plan. Explicit plan IDs and a Store-backed adapter give this programme accurate state now; P01-P04 carry the remaining production dispatch and UI work. A native workflow in the running state means an open local history, not a launched agent or a connected Temporal server.

## 5. Fix Taxonomy

| Change | Purpose | Scope |
|---|---|---|
| Immutable execution manifest | Preserve requirements, fixtures, dependencies and provenance | Planning specification |
| Existing-plan links | Keep all 75 legacy tasks visible without copying histories | Federated planning |
| Store adapter | Atomic registration, explicit selected-plan readback and replay checks | Bounded administration |
| New P/K/Q/N tasks | Assign uncovered implementation gaps | Future execution |
| PLAN00 | Track this planning work in sa-plan itself | Planning-only completion |

E01 uses its own standalone candidate-snapshot probe before the E02 acceptance runner exists. P02 uses an additive Gleam facade so imported OCaml CLI and test originals remain preserved.

## 6. Patterns & Anti-Patterns Discovered

Use immutable task contracts plus mutable sa-plan state. Match task, job, workflow, source revision and receipt identifiers at every execution stage. Register new standards clauses, source cases, routes, components and retries before executing them.

Do not infer execution from an available job, an open workflow, a generated Markdown checkbox or a test total. Do not copy live DB/WAL/SHM files to move a plan or make an evidence artifact. A linked legacy plan remains subject to its original ownership until an explicit migration is verified.

## 7. Verification Matrix

| Verification | Observation | Meaning |
|---|---|---|
| Contract validation | 71 tasks, 71 jobs, 13 workflows, 35 requirements, 75 legacy links | IDs, dependency closure and source hashes checked |
| Scratch-store controls | Ten checks passed | Registration and planning bookkeeping tested |
| Native Store readback | 71 tasks, 71 jobs, 13 open workflows registered | Real durable records created |
| Independent CLI task list | 71 available records at initial readback | Correct explicit plan selected |
| Independent CLI implementation-job list | 70 available jobs, zero attempts | Implementation not dispatched |
| Original legacy store | 75 available tasks, 74 unattempted jobs, one open workflow | Existing work preserved |
| Canonical database permissions | 0600 under ignored `var/sa-plan/` | Live state kept outside versioned evidence |
| Original application/OCaml source | No implementation edits by this task | Original code retained |
| Application/browser/formal acceptance | UNRUN by this planning task | No system admission credit |

The final registration receipt records PLAN00 completion separately from the 70 implementation tasks and identifies the next ready task. Its selftest results concern registration only.

<details>
<summary>Comprehensive planning checklist: five domains and 18 checkpoints</summary>

| Domain | Checkpoint | State | Evidence or owning work |
|---|---|---|---|
| D1 | CHK-01-TIME | PLANNING_METADATA | Observed clock, explicit hour/seconds timestamp |
| D1 | CHK-02-TAIL | PLANNING_METADATA | Full Tailnet links supplied; browser behavior remains unrun |
| D1 | CHK-03-FRACT | PLANNING_METADATA | L0-L9 tags supplied |
| D1 | CHK-04-KM | IMPLEMENTATION_UNRUN | W05/W06 own corpus links and transclusions |
| D2 | CHK-05-MUDA | IMPLEMENTATION_UNRUN | No new dependency; E04 closes global census |
| D2 | CHK-06-GRAPH | IMPLEMENTATION_UNRUN | No foreign vector library introduced |
| D2 | CHK-07-DRIVE | IMPLEMENTATION_UNRUN | No physical operations; Q02 covers production tests |
| D3 | CHK-08-C1C8 | IMPLEMENTATION_UNRUN | W/V workstreams own real browser acceptance |
| D3 | CHK-09-MATH | IMPLEMENTATION_UNRUN | M/E/V require actual model, proof and metric evidence |
| D3 | CHK-10-9MOD | IMPLEMENTATION_UNRUN | Each modality has separate evidence obligations |
| D3 | CHK-11-REGR | REGISTRATION_CHECKED | Ten registration controls; no application regression inference |
| D4 | CHK-12-GLEAM | IMPLEMENTATION_UNRUN | P01/P04 own production supervised integration |
| D4 | CHK-13-HERMES | IMPLEMENTATION_UNRUN | K01/K03 own real knowledge-worker calls |
| D4 | CHK-14-ZIGVM | IMPLEMENTATION_UNRUN | Original kernel verification requirements retained |
| D4 | CHK-15-MAX | IMPLEMENTATION_UNRUN | MAX isolation retained |
| D4 | CHK-16-OTEL | IMPLEMENTATION_UNRUN | E08/M04/P04 bind observed traces |
| D5 | CHK-17-SOV | UNKNOWN | No independent reviewer approval invented |
| D5 | CHK-18-JJ | PLANNING_METADATA | Isolated standalone Jujutsu workspace |

</details>

## 8. Files Modified

Added the execution plan, detailed work-item contracts, this journal, the additions catalog, complete execution manifest, registration receipt, and two OCaml administration/generation tools. Final Jujutsu diff is the authoritative file list.

Native sa-plan records were written through Store APIs to `/home/an/NAS-setup/uos/var/sa-plan/uos.sqlite3`. The database and scratch SQLite stores are runtime state, not versioned artifacts; they are neither copied nor hashed. Existing legacy planning records and original OCaml code are unchanged.

## 9. Architectural Observations

The programme separates the immutable acceptance contract from durable execution state. Workstream and programme workflows collect evidence; task dependencies and linked-plan completion receipts govern eligibility.

The execution plan contains paired ASCII/Mermaid diagrams with matching nodes and edges. No diagram claims implemented control behavior. Full FPP/SysML/Zenoh and page/component coverage expands into explicit child records after its versioned census.

## 10. Remaining Gaps

The first implementation sequence is E01 -> E02 -> E03. The full dependency graph then covers original test migration, denotation/DMC/TCM/atlas, actor/FPP/SysML semantics, complete Zenoh, knowledge and navigation, real browser cycles, properties/fuzz/formal checks, skills/agent health, and release admission.

P01 must prove dependency-aware dispatch and completion fencing; P02 fixes general CLI selection; P03 federates the legacy plan; P04 connects actual Store observations to the UI. All 70 implementation items remain open after PLAN00 completes.

## 11. Metrics Summary

| Metric | Count |
|---|---:|
| Original implementation tasks retained | 60 |
| Additional implementation tasks | 10 |
| Planning-only task | 1 |
| New native tasks/jobs/workflows | 71 / 71 / 13 |
| Linked legacy tasks/jobs/workflows | 75 / 74 / 1 |
| Total tracked task/job/workflow records across both stores | 146 / 145 / 14 |
| Requirements / review findings covered | 35 / 9 |
| Dependency eligibility waves | 26 |
| Registration verification controls | 10 |
| Implementation jobs attempted by this task | 0 |
| New command ceiling | 1,200 seconds |

These counts describe management records and planning checks, not implemented features, browser coverage or system-wide passing tests.

## 12. STAMP & Constitutional Alignment

The primary hazard is false execution credit. Registration keeps dispatch disabled, reserves implementation jobs, distinguishes PLAN00 from implementation, and records missing checks as nonpassing.

The work preserves original source and external ownership, uses standalone Jujutsu, avoids destructive storage operations, never copies live stores, retains bounded solver rules, and grants no system or reviewer admission. All future task/job/workflow activity remains under sa-plan.

## 13. Conclusion

The execution programme is concrete, dependency-ordered and registered through the real sa-plan Store. Existing legacy work remains linked with its IDs and history preserved. The resulting documents provide exact task files, fixtures, commands, acceptance gates and source mappings.

Completing PLAN00 confirms planning and registration only. E01 is the next implementation task; the remaining 70 implementation items require their own observed execution and acceptance evidence.

