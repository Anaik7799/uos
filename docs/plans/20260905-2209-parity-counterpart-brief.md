# Task 1 — complete parity-algebra Gleam counterpart

Read this first; these are the task's exact requirements. Approved design: [Additive test design](../design/20260905-2149-ocaml-gleam-additive-test-design.md). Parent plan: [Implementation batch](20260905-2209-additive-ocaml-gleam-tests-plan.md).
Identity timestamp: 2026-09-05T22:05:09Z.

## Scope and ownership

Work at `/home/an/NAS-setup/.uos-workspaces/ocaml-gleam-tests`. Read its AGENTS.md and scoped policies before inspecting source modules. You own NEW files under `tests/ocaml_counterparts/**` and `engines/hermes/test_ports/**` only. Existing OCaml tests, libraries, fixtures, helpers, Dune files, and runners stay byte-identical. No Git, no JJ mutation (controller handles commits), no source-repo changes, no new subagents.

Add a separate Gleam/BEAM package and a new bounded OCaml adapter linking the real `hermes_harness_parity_algebra` and `hermes_wiki_diag` libraries. Do not independently reimplement the algebra or wrap the old test executable as the counterpart.

## Behavior and transport

The source `engines/hermes/modules/hermes_harness/test_parity_algebra.ml` is the complete requirement for all original test assertions. Read the whole file, including the final chaos and structure sections. Gleam must perform the assertions against actual OCaml results.

Expose JSON requests with `version: 1`, string `id`, string `operation`, and typed `arguments`; replies echo these identity fields and contain result or structured error. Design the smallest operation set that allows observations of name, rank, grants_credit, asserts_defect, identity, combine, roll_up, diagnostic-impact mapping, and complete reports including credit_percent/render_report. Native code serializes values; it contains no test assertions or suite verdicts.

Use explicit executable plus argv, not shell strings. Frame size <= 8 MiB, one in-flight request per subprocess, response deadline 30 seconds, bounded parsing, cleanup on timeout/error. Blocked or crashed tools must fail tests, never pass or silently skip. OCaml/solver workloads must not run in a BEAM NIF. Stateful/process/solver suites are not part of this pure-algebra pilot; do not claim process-tree admission without its tests.

Keep all authored executable files Gleam or OCaml. Existing Hex dependency Erlang internals are fine; no authored Erlang helper. Prefer existing `gleam_erlang`, `exception`, `gleam_json`, `gleeunit`, and `simplifile` dependencies with exact versions and lockfile.

## Required cases

Port the seven source layers: unit, property, BDD, feature, fuzz, chaos, structure. Preserve all verdict combinations (4/16/64), diagnostic-impact mapping, full report fields/percent/rendering, empty optional/required distinction, 2,000 OCaml-generated input vectors with seed 20260808 and the exact original operation order, 100,000 children with one blocked, and 10,000 divergent children. Export inputs using the original OCaml random generator in a new helper/operation if needed; identical seed numbers across runtimes are not equivalent streams.

Write real Gleam tests before adapter implementation (TDD), record a behavioral assertion failure first, and then implement the minimal native/client path. Add tests that detect malformed/truncated/oversized frames, malformed JSON, correlation/version/operation mismatch, missing executable, native errors/nonzero exit, and timeouts. Fault producers can be new OCaml fixture executables. Demonstrate an isolated implementation mutation being caught without modifying original sources or adding a mutation flag to the normal adapter.

## Evidence and report contract

Run focused tests while iterating; serialize builds in your package. Baseline tools observed: Gleam 1.16.0, OCaml 5.5.0, Dune 3.23.1. Check the actual OTP version you use. Existing isolated OTP29 executable directory is available if needed: `/nix/store/k7w9agazdjmsm55p0kasv1f2a3ilpvnk-uos-planning-ledger-otp-29.0.6/bin`; inspect before use, do not assert availability from this note.

Report to `governance/testing/ocaml_gleam/20260905-2209-parity-implementation-report.json` with: status, files changed, complete case-to-function mapping or its path, RED command/output, GREEN commands/outputs, versions, source/dependency hashes, random-vector identity, mutants killed, unverified limits. Use apply_patch for authored files. Controller will review/commit; do not mutate JJ or spawn reviewers.

Return only status, report path, one-line test result, and concrete concerns. If dependencies or interfaces are blocked, report promptly rather than inventing successful output.


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

- [ ] CHK-12-GLEAM: New Gleam execution evidence pending.
- [ ] CHK-13-HERMES: Native boundary evidence pending.
- [ ] CHK-14-ZIGVM: Kernel outside this slice.
- [ ] CHK-15-MAX: Inference outside this slice.
- [ ] CHK-16-OTEL: Full operational telemetry not admitted by this slice.

</details>
<details>
<summary>5. Governance and Jujutsu</summary>

- [ ] CHK-17-SOV: User design approval received; not tri-sovereign signoff.
- [ ] CHK-18-JJ: Isolated JJ workspace; full-system admission not evaluated.

</details>

Previous: [Plan](20260905-2209-additive-ocaml-gleam-tests-plan.md). Next: [Execution journal](../journal/20260905-2209-additive-test-execution-journal.md).
