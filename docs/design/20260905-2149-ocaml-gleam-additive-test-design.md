# Additive Gleam counterparts for all UOS-owned OCaml tests

Status: DESIGN FOR REVIEW; implementation not started. Document identity timestamp: 2026-09-05T21:42:49Z (UTC). Source digests observed at 2026-09-05T21:43:48Z.

Tags: `#fractal-l0` `#fractal-l2` `#fractal-l7` `#zk-adr` `#zero-muda`.

[UOS home](http://nas-1.tail55d152.ts.net:4100/) / [Planning](http://nas-1.tail55d152.ts.net:4100/planning) / [Design](#scope-and-preservation)

On this page: [Scope](#scope-and-preservation), [Inventory](#observed-baseline), [Design](#execution-design), [Cases](#case-level-traceability), [Delivery](#delivery-order), [Acceptance](#acceptance-gates), [Checklist](#verification-checklist).

## Scope and preservation

The latest operator instruction is authoritative:

> , make all of theocaml tests gleam tests, keep the ocaml tests as-is , do not remove them

Add genuine Gleam counterparts for every UOS-owned OCaml test suite. Existing OCaml test sources, fixtures, helpers, Dune declarations, and runners remain unchanged permanently. They are not deprecated, renamed, replaced, or scheduled for later removal. OCaml production libraries and formal proofs retain their current language and authority. No external/vendor source tree is modified.

The operator has confirmed the side-by-side scope in chat. This written design remains pending review under the architectural brainstorming workflow. It supersedes the earlier suggestion of retiring originals after parity; it does not claim that any new test has already been implemented.

## Observed baseline

Read-only scan of `/home/an/NAS-setup/uos` found 933 OCaml implementation files and 318 test/support candidate files across 16 modules. These numbers are file counts, not test-case counts. [The machine-readable inventory](../../governance/testing/ocaml_gleam/20260905-2149-source-candidates.json) records every candidate path, its SHA-256, preservation rule, and reserved counterpart path.

| Module | Candidate files |
|---|---:|
| hermes_agent_loop | 17 |
| hermes_dependability | 23 |
| hermes_dune_graph | 1 |
| hermes_fpp_authority | 1 |
| hermes_harness | 82 |
| hermes_nix | 8 |
| hermes_ops | 35 |
| hermes_ops_dashboard | 23 |
| hermes_sysml | 6 |
| hermes_toolchain | 2 |
| hermes_vcs | 19 |
| hermes_vision | 2 |
| hermes_wiki | 69 |
| hermes_zellij | 3 |
| swarm | 18 |
| system_engg | 9 |
| Total | 318 |

Scan exclusions: build caches, JJ metadata, node_modules, vendor, third_party, and migration copies. The next inventory pass must reconcile Dune test/executable declarations, inline laws, selftests, nonstandard names, and support modules. A filename scan is not an exhaustive semantic inventory. An active UOS-owned test found outside the initial scan must be added, not silently excluded.

The stored JJ observation is commit `22008c49704ab12e809537d0d7a7c43810158fba`, change `xxwnznxwmxkmlkwpnkzyoprxplxpxvso`. Individual working-tree source digests are authoritative for this scan; writers were not quiesced, so this is not an atomic source snapshot or an admission receipt.

### Existing Gleam parity code is not a completeness certificate

- [ocaml_differential_oracle.gleam](../../apps/cepaf_gleam/src/cepaf_gleam/verification/ocaml_differential_oracle.gleam) sets `parity_pass` from `file_count == 432`; it does not enumerate or execute OCaml test cases.
- [ocaml_parity_verifier.gleam](../../apps/cepaf_gleam/src/cepaf_gleam/verification/ocaml_parity_verifier.gleam) uses `mock_ast_render_block` for rendering checks. Those checks cannot certify the actual Hermes renderer.
- [test_parity_algebra.ml](../../engines/hermes/modules/hermes_harness/test_parity_algebra.ml) includes diagnostic-impact mapping, report fields, credit percentages, 2,000 generated roll-ups, and 100,000-child scale checks. The existing Gleam algebra section alone does not cover the whole source suite.
- [test_wiki_routes.ml](../../engines/hermes/modules/hermes_wiki/test/test_wiki_routes.ml) exercises the actual Dream handler as well as pure route resolution. A new Gleam counterpart must retain both boundaries.

These existing files and their historical [integration specification](20260905-2204-uos-ocaml-parity-and-testing-integration-spec.md) remain unchanged. Their completion claims are not accepted as fresh evidence for this task.

## Execution design

The selected approach is additive Gleam assertions against the actual implementation, through an existing callable interface where available and an isolated operation adapter where missing. The adapter returns values and errors; it does not execute the original test executable and return a pass flag.

```text
Existing OCaml tests (unchanged) --------> OCaml production libraries
                                                    ^
                                                    |
New Gleam assertions --> typed request/response --> bounded OCaml adapter
         |
         +--> explicit case/fixture/result mapping and preservation checks
```

The alternatives are a runner-only wrapper (useful orchestration, but not a Gleam test port) and independent pure-Gleam model tests (useful additional checks, but not evidence that the OCaml implementation behaves correctly). Neither receives counterpart credit without the actual source behavior being exercised.

### Expected additive directory structure

```text
uos/
  engines/hermes/modules/             existing OCaml suites: unchanged
  engines/hermes/test_ports/          new operation adapters, no assertions
  tests/ocaml_counterparts/
    gleam.toml                       separate Gleam/BEAM test package
    src/ocaml_counterparts/          typed clients, decoding, bounded transport
    test/<source-module>/            real Gleam assertions and case generators
    fixtures/                       new, source-bound input vectors only
  governance/testing/ocaml_gleam/    candidate inventory, case map, run evidence
  docs/design/                      this design
  docs/journal/                     task records
```

Paths other than this design, its journal, and the candidate inventory are proposed; they have not been scaffolded. Preserve source-relative hierarchy under `test/` to prevent name collisions. Support-only files receive support counterparts, not fake passing test functions.

### Interface and isolation contract

- Gleam owns fixture selection, assertions, expected results, property generators, coverage accounting, and final test verdicts.
- New OCaml operation adapters link the same production libraries as the source suites. They serialize input/output only; no reimplementation of tested algorithms and no hard-coded success results.
- Requests and responses carry protocol version, request ID, operation tag, and structured payload. Typed decoders reject malformed data, missing fields, unknown operations, wrong versions, and mismatched IDs.
- Use an explicitly selected local executable and argv, not shell interpolation. For the initial algebra adapter, limit each frame to 8 MiB, permit one in-flight request per process, and enforce a 30-second response deadline. A deadline expiry, missing tool, nonzero exit, or truncated frame is a non-passing result. Scale/solver suites require separately recorded bounds and cannot inherit an unbounded default.
- Stateful filesystem, SQLite, networking, and process suites use private disposable test resources. No live ledgers, credentials, production services, or remote agent invocations are inputs. A missing isolated fixture is reported unavailable, not substituted with production data.
- Blocking, crash-prone, and solver operations remain outside the BEAM VM. Reuse an existing bounded NIF only after its ABI and actual production behavior are checked. This task does not authorize loading arbitrary OCaml libraries as NIFs.
- Process-group termination and reaping must be tested before process/solver suites are admitted. Killing only a shell wrapper does not satisfy cancellation.
- Existing OCaml Dune/test commands remain available and unchanged. New Dune declarations live in new adapter directories; do not rewrite original declarations to disable or redirect tests.

## Case-level traceability

Every source case needs: stable ID, source path/hash/locator, source label, fixture identity, generated-input domain and seed/vector digest, dependency identity, original execution boundary, expected outcome, new Gleam module/function, counterpart kind, and revision-bound run evidence. A filename-to-filename association alone is only discovery.

Preservation and semantic coverage are separate gates:

```text
OriginalPreserved(p) := current_sha256(p) = baseline_sha256(p)
CounterpartVerified(c) := source_case_mapped(c)
  AND actual_implementation_exercised(c)
  AND equivalent_assertions_and_inputs(c)
  AND successful_revision_bound_run(c)
  AND failure_sensitivity_demonstrated(c)

Complete := all_originals_preserved
  AND no_unclassified_in_scope_sources
  AND all_in_scope_cases_have_verified_counterparts
  AND no_unavailable_or_unrun_required_cases
```

These are acceptance predicates, not a claim of a machine-checked proof. An implementation plan must encode the inventory/preservation predicates in executable Gleam checks. Mapping coverage, executed coverage, and verified coverage use the classified case set as denominator. Until that set is complete, semantic percentages are unknown; the 318 candidate files are not that denominator.

Cross-language random seeds do not imply identical input streams. The first parity-algebra port must reproduce the original OCaml generator's actual 2,000 vectors using a new, pinned input exporter or implement and verify the same generator. It must also preserve its seven layers: unit, property, BDD, feature, fuzz, chaos, and structure. Additional Gleam-generated cases are recorded separately.

## Delivery order

1. Classify declared suites and support files; capture baseline bytes and fixture/runner ownership. Implement an additive integrity gate without modifying originals.
2. Deliver the parity-algebra suite completely, including its 4/16/64 exhaustive combinations, diagnostic impacts, reporting, 2,000 generated inputs, and large-list cases. Validate the transport's failure behavior before crediting native results.
3. Add pure protocol/algebra suites in dependency order; retain exact source error semantics and invalid-input tests.
4. Add wiki parsing/rendering and real router tests, preserving the distinction between pure resolution and the Dream handler.
5. Add stateful, process, SQLite, filesystem, and solver suites after their isolation and cleanup gates pass.
6. Reconcile every remaining module and nonstandard test declaration; run both unchanged OCaml suites and additive Gleam suites at the same source baseline. Report unavailable dependencies explicitly.

Each module is an independently reviewed implementation slice. Do not claim the entire migration is complete after the pilot. Formal proof files remain in their original languages; Gleam may orchestrate checks and assert outcomes, but a stub or a missing prover cannot pass.

## Acceptance gates

- Original test, helper, fixture, and runner bytes remain unchanged, with before/after evidence.
- Every classified source case has a counterpart; unclassified records prevent a full-coverage claim.
- All new tests exercise actual implementation behavior; renamed files, count predicates, mock renderers, and old-test-executable wrappers do not qualify.
- New counterpart package compiles and runs under the selected pinned Gleam/OTP toolchain. Any dependency resolution failure is a blocker, not a passing skip.
- Fault injection demonstrates that malformed replies, native failures, timeouts, and at least one relevant implementation mutation are detected. Mutation work occurs only in an isolated temporary candidate; originals remain untouched.
- Source tests and new tests are reported separately. A skipped, unavailable, stale, unrun, or mocked case grants no verified counterpart credit.
- Both inventory diffs and run receipts are attached to the JJ change. Human review is not reported as AGY/Claude approval unless those reviewers actually respond.

## Verification checklist

The canonical checklist is displayed with task-local evidence only. Unchecked means unverified, out of scope, or pending; it is never an implicit pass.

<details>
<summary>Domain 1: Metadata, timestamp, and navigation</summary>

- [x] CHK-01-TIME: Timestamped filename; observed clock with chrony Normal status and 0.000151538-second offset.
- [x] CHK-02-TAIL: Full Tailnet navigation links included; live serving of this new document is not verified.
- [x] CHK-03-FRACT: Scope-appropriate fractal tags included.
- [ ] CHK-04-KM: Wiki/ZK bidirectional publication not verified.

</details>
<details>
<summary>Domain 2: Purity and hardware safety</summary>

- [ ] CHK-05-MUDA: No dependency changes proposed for excluded frameworks; global history not audited.
- [ ] CHK-06-GRAPH: Vector-math implementation not changed or verified here.
- [ ] CHK-07-DRIVE: Hardware interlock not exercised; no storage mutation authorized.

</details>
<details>
<summary>Domain 3: Test quality and mathematical gates</summary>

- [ ] CHK-08-C1C8: UI quality gates not executed.
- [ ] CHK-09-MATH: Mathematical metrics not measured.
- [ ] CHK-10-9MOD: New counterparts not implemented or run.
- [ ] CHK-11-REGR: Existing UI regression suite not run.

</details>
<details>
<summary>Domain 4: Language boundaries and observability</summary>

- [ ] CHK-12-GLEAM: Gleam counterpart execution pending.
- [ ] CHK-13-HERMES: Existing test sources inventoried; native adapter execution pending.
- [ ] CHK-14-ZIGVM: Runtime kernel not modified or verified.
- [ ] CHK-15-MAX: Inference service not modified or verified.
- [ ] CHK-16-OTEL: Transport/run receipt observability pending.

</details>
<details>
<summary>Domain 5: Review and Jujutsu</summary>

- [ ] CHK-17-SOV: Written design and reviewer approvals pending; no tri-sovereign signoff claimed.
- [ ] CHK-18-JJ: Isolated JJ workspace created; full-system cycle admission is not evaluated by this task.

</details>

Previous: [Historical integration specification](20260905-2204-uos-ocaml-parity-and-testing-integration-spec.md). Next: [Design journal](../journal/20260905-2149-ocaml-gleam-test-design-journal.md).

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) | [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki) | [ZK](http://nas-1.tail55d152.ts.net:4100/zk)
