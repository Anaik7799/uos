# Additive OCaml/Gleam tests — first implementation batch

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deliver a real, fully traced Gleam counterpart of the parity-algebra suite and a reusable preservation/inventory gate; retain all OCaml originals.
**Architecture:** Gleam assertions call original OCaml libraries through a bounded local operation adapter. A separate Gleam inventory tool detects source drift and classifies migration progress without inventing case coverage.
**Tech Stack:** Observed Gleam 1.16.0, OCaml 5.5.0, Dune 3.23.1, JJ 0.44.0; selected OTP runtime verified at execution. Pinned Hex dependencies, no new authored shell/Python/JavaScript/Erlang scripts.
**Spec:** [Approved additive design](../design/20260905-2149-ocaml-gleam-additive-test-design.md).
**Approval:** User said "approved." after reviewing the written design. Identity timestamp: 2026-09-05T22:05:09Z (UTC; 2026-09-06 locally).

## Global Constraints

- Existing OCaml test sources, fixtures, helpers, Dune declarations, and runners remain unchanged permanently.
- No external/vendor source tree is modified.
- Gleam owns fixture selection, assertions, expected results, property generators, coverage accounting, and final test verdicts.
- New OCaml operation adapters link the same production libraries as the source suites.
- A deadline expiry, missing tool, nonzero exit, or truncated frame is a non-passing result.
- Initial adapter frame limit: 8 MiB; one in-flight request per process; 30-second response deadline.
- No live ledgers, credentials, production services, or remote agent invocations are test inputs.
- No count predicates, mock algorithms, or wrappers of old test executables receive counterpart credit.
- All authored automation is Gleam or OCaml; dependencies and formal-language files keep their original language.
- JJ only. Controller serializes commits. Work in the existing isolated workspace.
- Each batch must state its unported remainder; this first batch does not complete all 318 candidate files.

[Home](http://nas-1.tail55d152.ts.net:4100/) / [Planning](http://nas-1.tail55d152.ts.net:4100/planning) / Implementation batch

## Task 1: Complete parity-algebra counterpart and actual native boundary

Files: create only `tests/ocaml_counterparts/**` and `engines/hermes/test_ports/**`.
Detailed implementer requirements: [Task 1 brief](20260905-2209-parity-counterpart-brief.md).
Source: `engines/hermes/modules/hermes_harness/test_parity_algebra.ml`, `parity_algebra.ml`, and the linked `hermes_wiki_diag` library.

Interface: a JSON request carries version 1, string ID, operation, and arguments. A reply echoes version/ID/operation and carries exactly result or structured error. Operations expose observations of literal verdicts, identity, combine, roll_up, diagnostic-impact mapping, and full report/credit_percent/render_report; a bounded input-export operation reproduces the original OCaml random stream. Native code has no assertions and never returns source-suite pass counts.

- [x] Write a focused Gleam test that the real adapter returns `"unmapped"` for a required empty roll-up. Build a typed unavailable implementation first; observe an assertion failure caused by the missing real operation, not a compiler typo.
- [x] Implement the framed local subprocess adapter and client. Use argv execution, bounded reads, timeout, explicit cleanup, correlation checks, and strict decoders. Link existing production libraries without changing any original file.
- [x] Implement all seven source layers: unit, property, BDD, feature, fuzz, chaos, structure. Port every source assertion, including diagnostic impacts and report counts; retain the full source-label/case mapping.
- [x] Preserve the original 2,000 generated vectors (seed 20260808, original OCaml RNG operation order), plus 100,000-child and 10,000-divergence cases. Compare values against literal/independent expectations in Gleam.
- [x] Add transport-negative tests: absent executable, malformed/oversized/truncated replies, wrong version/ID/operation, native error/nonzero exit, and deadline expiry. Helpers producing faults may be new OCaml executables, not rewritten algorithms.
- [x] Demonstrate failure sensitivity using a temporary isolated implementation mutation; do not alter the original source path or add a production mutation switch.
- [x] Run the untouched source suite, full focused Gleam suite, format/check/build, and verify original hashes. Report compiler versions, actual commands, outputs, source-case counts, generated-input bounds, and limitations.
- [x] Controller obtains independent spec/quality review and records accepted fixes before marking this task complete.

Example discriminating assertion (not a substitute for the rest of the source suite):

```gleam
pub fn empty_required_withholds_credit_test() {
  let assert Ok(observed) = client.roll_up(True, [])
  observed.name |> should.equal("unmapped")
  observed.grants_credit |> should.be_false
}
```

## Task 2: Gleam preservation and inventory gate

Files: create `tools/ocaml_test_inventory/gleam.toml`, `src/ocaml_test_inventory.gleam`, `src/ocaml_test_inventory/inventory.gleam`, and `test/inventory_test.gleam`. Keep the original candidate inventory unchanged as a baseline.
Inputs: `governance/testing/ocaml_gleam/20260905-2149-source-candidates.json` and explicit source root. Outputs: typed per-path findings, observed counts, changed/missing paths; nonzero CLI exit on invalid inventory or drift. Source files are read-only.

Public core:
```gleam
pub type Entry { Entry(path: String, sha256: String) }
pub type ReadError { NotFound CannotRead }
pub type Finding {
  Changed(path: String)
  Missing(path: String)
  Unreadable(path: String)
  InvalidInventory(reason: String)
}
pub fn verify_entries(
  entries: List(Entry),
  read: fn(String) -> Result(BitArray, ReadError),
) -> List(Finding)
```

- [x] First write a hand-checked SHA-256 fixture: `"abc"` hashes to `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`. Assert altered bytes yield `Changed("fixture.ml")`; observe RED before implementation.
- [x] Reject empty lists, duplicate paths, absolute/traversal/noncanonical paths, non-hex/wrong-length digests, and missing files. Success is an empty findings list only for a nonempty valid inventory whose real file bytes match.
- [x] Implement SHA-256 using the pinned Gleam crypto dependency and read files through simplifile. Do not parse source text to manufacture test passes.
- [x] Add temporary-file integration tests: matching bytes, changed bytes, missing file. Verify the CLI exits nonzero on an altered input and never writes source files.
- [x] Run the tool against both the isolated workspace and canonical UOS source candidates, storing separate observations.
- [ ] Extend the discovered inventory with read-only Dune declaration classification and nonstandard test candidates. Unknowns remain unknown; never reduce the denominator by silently dropping a candidate.
- [ ] Obtain independent task review and record results.

## Task 3: Review, evidence, and safe handoff

Files: append to the task journal; create timestamped run receipt, case map, and review artifacts under `governance/testing/ocaml_gleam/`; no existing source edits.

- [ ] Match source labels and generated domains to concrete Gleam functions and native operations. Record source/dependency/toolchain identities.
- [ ] Independently review the full new-code diff for preservation, actual implementation exercise, malformed-input failure, cleanup, and source-case omissions.
- [ ] Run both packages' complete test suites once on final code; recheck all baseline source hashes.
- [ ] Record JJ commit/change IDs and test receipts. Keep all unported candidates explicit. Do not call this full migration completion.
- [ ] Keep the feature workspace/bookmark available for the remaining modules; do not merge, delete, or publish automatically.

## Preflight decisions and dependency alignment

## Added Task 4: SA-Plan tasks, jobs, and Temporal-style workflow

Operator request (verbatim): "create sa-plan taks, hjobs and workflow with temporal".
Create an idempotent registration facade over the existing typed `Sa_plan.Store`;
Gleam calls the facade and owns its assertions. Persist a dependency DAG covering
the pilot and all 16 discovered source families. The 318-file inventory is a
candidate baseline, not a case denominator or a completeness certificate.

- [x] Register tasks, namespaced jobs, and one workflow record atomically.
- [x] Verify replay, immutable-input conflict rejection, rollback, restart readback,
  and actual task dependency enforcement with Gleam tests.
- [x] Keep the SQLite file in ignored task-local `state/ocaml_gleam_tests/`.
- [x] Keep dispatch disabled and do not launch worker or production processes.
- [x] Explain that this source provides a local Temporal-style Store history,
  not a connected Temporal service or full SDK compatibility.
- [x] Preserve all original OCaml files and update the execution journal and receipt.

Observed implementation status: Task 1 pilot and Task 2a preservation gate have
passed scoped independent reviews and fresh tests; Task 2 Dune/nonstandard-case
classification is still open. [Created state and handoff](20260905-2251-sa-plan-temporal-handoff.md).

The C3I orchestration skill's typed durable Store is authoritative for these
records; the CEPAF skill's legacy Markdown-authority rule is not used. Markdown
is a derived human-readable view. Existing job claims do not enforce task DAG
dependencies, so the dedicated reserved queue has no worker and is not dispatch
authority. A future worker must claim the associated dependency-gated task and
obtain scoped authorization before any effect. Status and workflow creation do
not imply tests have executed or passed.

## Implementation dependency alignment

Task 1 and Task 2 share no implementation files and can progress independently. Task 3 consumes both result sets. Gleam native tests require Task 1's actual adapter; inventory success cannot substitute for it. Preservation hashes cover the baseline candidates; Dune/source classification extends the map rather than rewriting the baseline.

The controller owns the inventory task and coordinates one implementation subagent for the native parity pilot. Independent reviews are read-only. No subagent may start additional agents or commit shared working-copy state.


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

Previous: [Approved design](../design/20260905-2149-ocaml-gleam-additive-test-design.md). Next: [Execution journal](../journal/20260905-2209-additive-test-execution-journal.md).
