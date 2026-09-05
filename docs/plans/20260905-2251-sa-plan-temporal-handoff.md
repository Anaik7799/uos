# SA-Plan migration workflow and execution handoff

Observed: 2026-09-05T22:40:42Z. Document prefix: `20260905-2251`.
Tags: `#fractal-l0` `#fractal-l2` `#fractal-l7` `#zk-adr` `#zero-muda`.

[Home](http://nas-1.tail55d152.ts.net:4100/) / [Planning](http://nas-1.tail55d152.ts.net:4100/planning) / SA-Plan migration.
These are navigation references; publication of this isolated workspace is not verified.

## Created state

| Item | Observed value |
|---|---|
| Plan | `uos/ocaml-gleam-tests/v1` |
| Workflow | `uos/ocaml-gleam-tests/v1/workflow` |
| Reserved queue | `uos-ocaml-gleam-v1-reserved` |
| Tasks / jobs / workflows | 75 / 74 / 1 |
| Completed / executing tasks | 0 / 0 |
| Ready tasks / total job attempts | 1 / 0 |
| Dispatch | Disabled; no worker started |
| Store workflow state | `running`: history record, NOT an executing Temporal worker |

The exact task roster and dependencies are in the
[generated specification](../../governance/testing/ocaml_gleam/20260905-2251-sa-plan-workflow-spec.json).
The [registration receipt](../../governance/testing/ocaml_gleam/20260905-2251-sa-plan-registration-receipt.json)
contains real commands and readback; the
[execution journal](../journal/20260905-2209-additive-test-execution-journal.md)
tracks implementation progress separately.

Persistent state is at
`/home/an/NAS-setup/.uos-workspaces/ocaml-gleam-tests/state/ocaml_gleam_tests/sa_plan.sqlite3`,
mode 0600, ignored by JJ. Canonical UOS remains
`/home/an/NAS-setup/uos`. The feature workspace has not been merged.
Do not copy the live SQLite/WAL into source control: replay the typed registrar
in the intended store after integration approval.

## Dependencies and parallel work

```text
OGL.00  source freeze / preservation
  +--> OGL.01 toolchain --> OGL.03 parity native + Gleam tests --+
  +--> OGL.02 inventory + Dune classification ------------------+--> OGL.04 review
  |                                                                  |
  |                                                               OGL.05 pilot gate
  +--> 16 x Mnn.D classify -------------------------------------------+
                  |                                                  |
                  +-- [D + pilot gate] --> Mnn.P port --> Mnn.V verify
                                                          | (+ OGL.02)
                                                        Mnn.R review
                                                          |
                          all 16 reviewed families --> OGL.91 integrate
                                                       +--> OGL.92 preservation --+
                                                       +--> OGL.93 final gates ---+--> OGL.94 handoff
                                                                                         |
                                                                                       OGL complete
```

The 16 source families are agent_loop, dependability, dune_graph, fpp_authority,
harness, nix, ops, ops_dashboard, sysml, toolchain, vcs, vision, wiki, zellij,
swarm and system_engg. Their candidate counts are retained in the specification
and baseline; 318 candidate files are not a testcase denominator.

Classification can run in parallel after the source gate. Porting waits for the
pilot gate; verification precedes independent review. Integration and shared JJ
mutations are serialized. Each job has a stable activity/idempotency key, its
task ID and dependencies, a three-attempt limit, and no executable effect list.
P0/P1 are planning priorities, not measured FMEA scores; FMEA remains explicitly
assessment-required.

## Actual Temporal boundary

This implementation uses the existing `Sa_plan.Store` SQLite workflow history,
not Temporal Cloud, a Temporal server, or an SDK worker. Signals, durable timers,
workflow cancellation and production replay compatibility are unavailable here.
No exactly-once external-effect guarantee is claimed.

The Store's job claim does not enforce the task DAG. The dedicated reserved
queue has no worker. Do not dispatch it with a generic queue consumer. A future
worker must obtain scoped effect authorization and a dependency-gated task
claim, validate fresh revision-bound evidence, implement idempotent effects and
fenced/unexpired completion, and pass failure/recovery tests. The current facade
can only register or observe; it cannot claim, complete, or execute work.
Formal evidence and review records cannot authorize effects on their own.

## Files and commands

```text
uos/                                      canonical target; currently isolated JJ feature
+-- engines/hermes/orchestration/ocaml_gleam_plan/
|   +-- migration_plan.ml/.mli             typed Store registrar and immutable DAG
|   +-- plan_port.ml                       bounded local facade
|   +-- testing/plan_fixture.ml            test-only Store observations, no assertions
+-- tests/ocaml_gleam_orchestration/        Gleam API/CLI and 9 behavior tests
+-- tests/ocaml_counterparts/              one source-suite pilot and native client
+-- engines/hermes/test_ports/parity/      original-library observation adapter
+-- tools/ocaml_test_inventory/            Gleam SHA256 preservation gate
+-- state/ocaml_gleam_tests/                ignored task-local SQLite state
+-- governance/testing/ocaml_gleam/        spec, source map, reviews and run receipts
+-- docs/plans/                            this handoff and approved batch plan
```

Build the registrar from the feature workspace's `engines/hermes`:

```sh
dune build --build-dir /tmp/uos-sa-plan-build orchestration/ocaml_gleam_plan/plan_port.exe
```

Observe the created records from `tests/ocaml_gleam_orchestration`:

```sh
PATH=/nix/store/k7w9agazdjmsm55p0kasv1f2a3ilpvnk-uos-planning-ledger-otp-29.0.6/bin:$PATH \
UOS_PLAN_PORT=/tmp/uos-sa-plan-build/default/orchestration/ocaml_gleam_plan/plan_port.exe \
UOS_PLAN_DB=/home/an/NAS-setup/.uos-workspaces/ocaml-gleam-tests/state/ocaml_gleam_tests/sa_plan.sqlite3 \
UOS_PLAN_OPERATION=status gleam run
```

Changing only `UOS_PLAN_OPERATION` to `register` replays registration: exact input
is idempotent; graph/workflow/job input drift fails without overwrite.
The public Gleam `request("status", database)` API returns full tasks, jobs and
history; the CLI prints a compact status summary. No SQL CLI or authored
shell/Python/Erlang script was introduced.

## Evidence and remaining work

Fresh observed checks: 9 orchestration tests, 7 inventory tests, 14 counterpart
test functions, and the unchanged OCaml source suite's 146 checks all passed.
These are different counting units, not 176 independent source capabilities.
All 318 baseline candidate hashes match in both source roots.

The parity review found and corrected two omitted report-verdict checks; the
reviewer accepted the fix and both report-only mutants were detected. Original
OCaml sources, fixtures and Dune declarations remain untouched. No full source
migration, full mathematical admission, live UI publication, tri-sovereign
approval, or warning-free cold OTP29 dependency build is claimed.

SA-Plan completion remains zero deliberately: registration is not evidence
import or execution. Before admitting any task, attach the candidate revision,
source hashes, actual run output, independent review, and required formal
evidence using a separately verified completion path. The registrar cannot
mark a task complete.

The next work is OGL.02's expanded Dune/nonstandard testcase census, remaining
suite counterparts, and a verified execution dispatcher. Existing OCaml tests
must remain unchanged permanently.


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


Previous: [Approved batch plan](20260905-2209-additive-ocaml-gleam-tests-plan.md).
Next: [Registration receipt](../../governance/testing/ocaml_gleam/20260905-2251-sa-plan-registration-receipt.json).
