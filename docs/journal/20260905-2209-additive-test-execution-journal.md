# SDD ledger — plan: docs/plans/20260905-2209-additive-ocaml-gleam-tests-plan.md

Identity timestamp: 2026-09-05T22:05:09Z. [Home](http://nas-1.tail55d152.ts.net:4100/) / [Plan](../plans/20260905-2209-additive-ocaml-gleam-tests-plan.md).
Tags: `#fractal-l0` `#fractal-l2` `#fractal-l7` `#zk-adr` `#zero-muda`.

## 1. Scope & Trigger

User instruction: ", make all of theocaml tests gleam tests, keep the ocaml tests as-is , do not remove them". Written-design approval: "approved." Side-by-side implementation now authorized; original suites remain permanently intact.

## 2. Pre-State Assessment

Baseline source commit 22008c49704ab12e809537d0d7a7c43810158fba; design commit 50f8739213461a080b35f2a35cb7810d8c97d1a1. 318 source candidates previously hashed; no Gleam counterparts from this task existed at approval.

Observed toolchain: Gleam 1.16.0, OCaml 5.5.0, Dune 3.23.1, JJ 0.44.0. Chrony: Normal, system 0.000280852 seconds fast of NTP. Local date is September 6 while UTC document identity is September 5; this is a timezone difference, not clock drift.

## 3. Execution Detail

Task 1: implemented and independently reviewed — 14 Gleam tests pass over real native observations. Reviewer found two omitted large-case report.verdict assertions; both added, both isolated report-only mutants killed, re-review accepted. Untouched source suite: 146 passed, 0 failed.
Task 2a: implemented and reviewed — 7 Gleam preservation tests pass; real altered-file CLI exits 1. Both canonical and isolated roots match all 318 baseline candidate hashes. Task 2's expanded Dune/nonstandard testcase classification remains OPEN (OGL.02).
Task 3: scoped evidence/handoff prepared; final JJ binding pending below. No full-migration or full-system completion claim.
Task 4: MATERIALIZED and independently reviewed, dispatch disabled — operator request "create sa-plan taks, hjobs and workflow with temporal". Typed Store contains 75 tasks, 74 reserved jobs, 1 local Temporal-style workflow. Separate-process replay/readback agrees, job attempts 0, completed/executing tasks 0. No Temporal server or worker execution claimed. Re-review approved all blocking fixes; a minor scoped-checklist wording inconsistency was clarified.

Preflight conflict scan:

| Tasks | Producer / consumer or self-check | Finding |
|---|---|---|
| 1 / 1 | Source assertions -> native observations -> Gleam assertions | Preserve all seven layers; no model-only substitute |
| 2 / 2 | Candidate digest inventory -> actual bytes -> drift findings | File count is not semantic coverage |
| 3 / 3 | Actual commands and reviews -> reported status | No unrun or inferred success |
| 1 / 2 | Disjoint packages; common original source baseline | Read-only source access; controller owns JJ state |
| 1 / 3 | Implementation and case map -> independent review | Review follows actual diff and run evidence |
| 2 / 3 | Preservation findings -> handoff | Report source drift rather than rewriting baseline |

Ruling: Execute the approved first batch without another planning approval pause — the user explicitly approved beginning implementation — cost if wrong: reversible new-file work.
Ruling: Use Jujutsu and apply_patch equivalents for skill bookkeeping, not its Git/Bash helper scripts — UOS/user language and VCS boundaries take precedence — cost if wrong: manual bookkeeping requires review.
Ruling: One implementation subagent owns the parity package/adapter; the controller owns a disjoint inventory package — useful parallel progress with no shared implementation files — cost if wrong: interface or build coordination rework.
Ruling: Preserve the isolated workspace and evidence rather than deleting it after a partial migration — remaining source suites depend on this continuation state — cost if wrong: modest retained disk use.
Ruling: UOS permits Gleam or OCaml automation and a separate test package — source-specific OCaml-only/Git helper instructions do not override the approved UOS design — cost if wrong: future tooling adaptation.
Ruling: The typed Sa_plan.Store owns task truth; legacy Markdown-authority guidance is only a projection for this task — current orchestration skill and UOS evidence policy require durable typed records — cost if wrong: an additional UI projection adapter.
Ruling: Reserve a task-local job queue with no worker; never infer task-DAG enforcement from job claims — source inspection shows `claim_job` does not join task dependencies — cost if wrong: explicit future dispatcher implementation before execution.

## 4. Root Cause Analysis

Existing model/count checks do not establish actual OCaml-suite coverage. Cross-language counterparts require source-case mapping, real implementation access, and matching input domains.

## 5. Fix Taxonomy

Additive test counterparts; bounded native adapter; strict typed decoding; source-preservation gate; separate discovered/executed/verified accounting.

## 6. Patterns & Anti-Patterns Discovered

No original tests removed or disabled. No unclassified source silently dropped. No duplicate algorithm used as a stand-in for native behavior. PRNG seeds require matched streams.

## 7. Verification Matrix

Fresh final checks: 14 counterpart test functions passed; 9 orchestration tests passed; 7 inventory tests passed; unchanged original OCaml suite 146/146. Baseline candidate SHA256 verification: isolated 318/318 and canonical 318/318. Source-module JJ diff is empty. These are distinct counting units, not additive source-capability coverage.

TDD evidence: inventory initially returned [] for changed bytes (0 pass/1 failure); orchestration initially returned native_error for missing registration (0 pass/1 failure). Final runs are in [registration receipt](../../governance/testing/ocaml_gleam/20260905-2251-sa-plan-registration-receipt.json). Task 1 has its own [case map](../../tests/ocaml_counterparts/fixtures/20260905-2209-parity-case-map.json) and [implementation/mutation report](../../governance/testing/ocaml_gleam/20260905-2209-parity-implementation-report.json).

SA-Plan review fixes: asserted unchanged workflow kind/input/history and job name/worker/args/attempt limit after conflicts, narrowed temporary path scope to the explicit test root, and asserted queue/backend/DAG dependencies in Gleam. Nine tests pass after fixes. Store workflow 'running' means a durable history record, never worker execution. Cold OTP29 dependency-generated Erlang catch warnings remain third-party noise; no dependency source edits or warning-free cold-build claim.


## Task-local verification checklist

Unchecked items are not passing evidence.

<details>
<summary>1. Metadata and navigation</summary>

- [x] CHK-01-TIME: Timestamp prefix uses observed UTC document identity.
- [x] CHK-02-TAIL: Full [Tailnet home](http://nas-1.tail55d152.ts.net:4100/) link provided; serving unverified.
- [x] CHK-03-FRACT: `#fractal-l0` `#fractal-l2` `#fractal-l7` `#zk-adr` `#zero-muda`.
- [ ] CHK-04-KM: Bidirectional Wiki/ZK publication unverified.

</details>
<details>
<summary>2. Purity and storage safety</summary>

- [ ] CHK-05-MUDA: Global history not audited; no excluded framework introduced.
- [ ] CHK-06-GRAPH: Vector math not in this task.
- [ ] CHK-07-DRIVE: No drive operations; interlock not tested.

</details>
<details>
<summary>3. Test and mathematical gates</summary>

- [ ] CHK-08-C1C8: Web quality gates not run.
- [ ] CHK-09-MATH: Mathematical metrics not measured.
- [ ] CHK-10-9MOD: Full migration pending; focused results recorded separately.
- [ ] CHK-11-REGR: UI regression tests outside this slice.

</details>
<details>
<summary>4. Language boundaries and observability</summary>

- [x] CHK-12-GLEAM: Scoped Gleam pilot, inventory and orchestration execution observed; full migration not admitted.
- [x] CHK-13-HERMES: Scoped native boundary and unchanged source suite execution observed; broader engine admission not evaluated.
- [ ] CHK-14-ZIGVM: Kernel outside this slice.
- [ ] CHK-15-MAX: Inference outside this slice.
- [ ] CHK-16-OTEL: Full operational telemetry not admitted by this slice.

</details>
<details>
<summary>5. Governance and Jujutsu</summary>

- [ ] CHK-17-SOV: User design approval received; not tri-sovereign signoff.
- [ ] CHK-18-JJ: Isolated JJ workspace; full-system admission not evaluated.

</details>


## 8. Files Modified

Additions: tests/ocaml_counterparts, engines/hermes/test_ports/parity, tools/ocaml_test_inventory, tests/ocaml_gleam_orchestration, engines/hermes/orchestration/ocaml_gleam_plan; timestamped evidence/spec/review files under governance/testing/ocaml_gleam and the [SA-Plan handoff](../plans/20260905-2251-sa-plan-temporal-handoff.md). Existing changes are limited to this task's approved-design status, plan and journal. No original OCaml file edited. Root ignore policy materialized unchanged; generated build files were untracked with JJ, not deleted. Live task-local SQLite is ignored by JJ.

## 9. Architectural Observations

Gleam assertions -> typed bounded process boundary -> original OCaml library. Inventory/preservation is an independent evidence check, not an execution surrogate.

## 10. Remaining Gaps

Expanded Dune/nonstandard testcase classification remains open; 318 candidates are not all test cases. Remaining suites across all 16 modules, full formal admission and a dependency-gated effect dispatcher are pending. A real Temporal service/SDK, signals, timers and workflow cancellation are not connected. Direct-child cleanup and lstat/read guards do not establish process-tree or hostile-filesystem isolation.

## 11. Metrics Summary

One source suite has a complete reviewed Gleam counterpart (42 source labels, 146 original check multiplicity, 2000 exact ordered random vectors, 100000/10000-child scale cases). Baseline source candidates: 318, unchanged. Case denominator and whole-system semantic coverage unknown. SA-Plan tasks/jobs/workflows: 75/74/1; completed 0, executing 0, ready 1, job attempts 0. Registrar and preservation evidence do not award migration credit by count.

## 12. STAMP & Constitutional Alignment

Control hazards: original test destruction, false coverage, unavailable native tools presented as passing, process leaks, and edits to live resources. Preserve source bytes, fail closed, bound processes, and separate advisory inventory from runtime evidence.

## 13. Conclusion

Approved pilot, preservation gate, and durable scheduling records are available in the isolated JJ workspace. SA-Plan registration does not start jobs or complete tasks. Continue from [the handoff](../plans/20260905-2251-sa-plan-temporal-handoff.md), preserving originals. The full migration remains unfinished; do not repeat verified pilot work after compaction.

Previous: [Plan](../plans/20260905-2209-additive-ocaml-gleam-tests-plan.md). Next: [Source candidate baseline](../../governance/testing/ocaml_gleam/20260905-2149-source-candidates.json).
