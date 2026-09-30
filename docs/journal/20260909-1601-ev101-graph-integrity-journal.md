# 20260909-1601 EV101 bounded graph integrity

#fractal-l0 #fractal-l5 #fractal-l6 #zk-adr #zero-muda

[UOS cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Verification](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/ev98-peer-loop-20260909/docs/reviews/20260909-1600-ev101-graph-verification.json) · [Risk](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/ev98-peer-loop-20260909/docs/reviews/20260909-1545-ev101-graph-risk-1788969563.json)

## 1. Scope & Trigger

Parent PROGRAM authorized a separate pure Gleam repair of the EV101 graph component after audit found inflated edge counts and false consistency. Canonical Sa-plan `uos/ev101-graph-integrity/20260909`, task `REPAIR`, worker `codex-ev101-graph`, attempt 1 remains executing pending independent review. This is not full EV101 completion or admission. Source candidate: `ea6cd8e8dcc0775239d49697390d54728e9eded0`, based on `52e013cfe8c32d6c8d4353c27cfdf0a23f225124` in the parent's epoch-2 peer workspace.

## 2. Pre-State Assessment

The only production importer found is `ui/lustre/sheaf_navigator_view.gleam`; it initializes the graph and reads existing public fields. Five existing engine tests passed despite duplicate/missing-endpoint count inflation, one-sided self-links, lost replacement adjacency, and a score of 1.0 for a one-sided edge. The initializer's stored 0.985 score disagreed with its actual adjacency. The UI's static checklist and consistency declarations are separate uncorrected presentation gaps.

## 3. Execution Detail

Created a separate Sa-plan plan/task, ran source-bound preflight, claimed attempt 1, and observed ACTIVE at 15:47:04 UTC. Initial invalid hierarchical names and an invalid `pending` risk enum were refused and preserved; the real available task state was observed before the successful claim. Native OCaml staging extracts immutable JJ regular-file bytes and copies three realized Gleam dependency packages into private directories. Gleam compiles and direct ELF ERTS executes; no authored shell, downloads, live network, shared runtime, or production source outside this component was used.

Executable RED `eb1f1b835b515aad4bad0b4225a806efcecc297f` produced nine new failures and five legacy passes. A prior test-fixture compilation error and consequent unavailable runner were preserved without credit. The first repaired run passed 20 tests; a later run passed 21. A final raw-graph control reproduced 0.99609375 consistency for 257 outgoing and 255 incoming entries at `635d7c1971b1360e472bd4580fb8697151dd45d5`. The shared shape check now enforces the outgoing-edge bound before scoring. Final immutable build is warning-free and all 22 tests pass.

## 4. Root Cause Analysis

`add_transclusion` incremented the cached count unconditionally even when no endpoint or new edge existed. A mutually exclusive branch prevented self-edges from updating both adjacency lists. `add_node` replaced one record without reconciling incoming indexes or cached metrics. The purported cohomology calculation counted existing target IDs and averaged per-node scores, so isolated nodes and one-sided links could create false confidence. The extra raw-input boundary exposed a distinction between total stored adjacency entries and directed-edge count.

## 5. Fix Taxonomy

The component now represents a directed simple graph with self-links counted once. `validate_graph`, `try_add_node`, and `try_add_transclusion` return typed refusals. Legacy signatures remain and return the complete original graph on refusal. Replacement treats the supplied outgoing list as authoritative, preserves other nodes' outgoing edges, and derives all incoming indexes. The bounded supplied incoming cache is explicitly ignored and rebuilt. Counts and the stored score are derived from actual adjacency; invalid graph values are refused by reads and mutations.

## 6. Patterns & Anti-Patterns Discovered

Independent edge sets make useful oracles because they do not reuse the production index rebuilding code. Name-compatible wrappers can retain callers while exposing refusal through checked APIs. Cached counters and historical mathematical names are not evidence. The final boundary control prevents a high fractional score from obscuring an unsupported raw edge count. Public record constructors remain possible and therefore require explicit validation.

## 7. Verification Matrix

| Observation | Result | Scope |
| --- | --- | --- |
| Original five tests | PASS | Existing engine expectations retained |
| Nine original adverse cases on baseline | Expected failures | Actual RED, not compilation-only evidence |
| Final EUnit run | 22 PASS, 0 failed, 0 skipped | Five original and seventeen new tests |
| Directed edge-set oracle | 512 graph states | All directed three-node graphs, including self-links; repeated insertion and node replacement |
| Raw adjacency metric oracle | 256 states | Every two-node outgoing/incoming matrix combination |
| Boundaries and refusals | PASS | 64 nodes, 256 edges, duplicate-at-cap, replacement recovery, metadata, invalid IDs/caches and malformed graphs |
| Asymmetric raw edge overflow | RED then PASS | 257 outgoing/255 incoming entries cannot emit score credit |
| Immutable source/dependencies | Rehashed | Four compiler inputs, 160 realized dependency artifacts |
| Final active risk | PASS 15:59:42 UTC | Current task attempt and source hashes; no effect or admission authority by itself |

Final runtime: `/tmp/ev101-sealed-runtime.json`. Full commands, argv, timeouts, outputs, source hashes, compiled-artifact hashes and durable copies of failures are in the linked verification manifest. Direct native evidence remains cooperative local observation; no reproducible release or cryptographic producer-authentication claim is made.

## 8. Files Modified

Production: `apps/cepaf_gleam/src/cepaf_gleam/knowledge/sheaf_engine.gleam`. New tests: `test/ev101_graph_integrity_test.gleam` and `test/ev101_graph_runner.gleam`. Native immutable staging: `tools/ev101_graph_stage.ml`. Timestamped assessments and this evidence-only child preserve authority, RED/GREEN receipts and the review handoff. The original five-test module and sole UI caller remain unchanged.

## 9. Architectural Observations

Bounds are 64 nodes, 256 directed edges, 256-byte nonempty IDs, 1024-byte title/layer/tag strings, 16 tags and 64 entries per adjacency list. Bounded list traversal precedes whole-list operations. An accepted graph has reciprocal indexes and exact derived count/score. The historic `cohomology_score` name now explicitly denotes reciprocal adjacency: matched pairs contribute two entries divided by all adjacency entries. Empty valid adjacency scores 1; dangling/duplicate/one-sided entries reduce it; invalid IDs and excessive graphs score 0. It is not mathematical cohomology or evidence that document claims are true.

## 10. Remaining Gaps

Independent review is pending; task completion belongs after that review. Full sheaf/formal refinement, live corpus loading, corpus semantics, production navigation claims, multi-host behavior and EV101 admission remain unestablished. Legacy wrappers deliberately preserve state on refusal; callers requiring diagnostics should use the typed checked APIs. The stager uses an already-reviewed local native library and realized dependencies, not a complete reproducible release closure. Input IDs remain ordinary strings, not authenticated document identities.

## 11. Metrics Summary

One production module repaired; two new Gleam test modules; one OCaml staging helper. Twenty-two EUnit tests include 768 enumerated graph/adjacency states; these are not 768 independent top-level tests or proofs. First RED: nine failures. Additional overflow RED: one failure. Final compile and runtime both exited 0, with no compile warnings. No package installs, network writes, live supervisor changes, new EV identifiers or admission events.

## 12. STAMP & Constitutional Alignment

P2 risk score 216 derives from C3 × T3 × F4 × Dep2 × I3, with FMEA S3/O4/Det3, RPN36. Four UCA classes cover omitted reciprocal maintenance, unsafe duplicate/dangling updates, replacement ordering, and excessive caller inputs. Sa-plan is the execution authority; the parent owns the workspace fence. All failures and prior immutable revisions remain evidence. Native OCaml/Gleam/direct ERTS honor the active language mandate. No historical data, external source tree, shared runtime or storage device was modified.

## 13. Conclusion

Source `ea6cd8e8dcc0775239d49697390d54728e9eded0` is built and executed for this bounded graph component. It is ready for independent review, with `REPAIR` still executing. No sovereign, full formal, corpus or EV101 admission result is inferred.

<details><summary>Domain 1 — Metadata, timestamp and navigation</summary>

- CHK-01-TIME: PASS for fresh chrony-observed active receipt and recorded invocation times.
- CHK-02-TAIL: Full Tailnet links included; this journal's live rendering not tested.
- CHK-03-FRACT: Applicable L0/L5/L6 tags recorded.
- CHK-04-KM: Journal, risk and evidence linked; full corpus linkage UNRUN.

</details>
<details><summary>Domain 2 — Purity and storage safety</summary>

- CHK-05-MUDA: Only existing Gleam/OCaml dependency subset reused; fleet exclusion scan UNRUN.
- CHK-06-GRAPH: Pure Gleam component with standard ERTS test bridge; no new NIF.
- CHK-07-DRIVE: N/A to this pure in-memory change; no storage-device operations.

</details>
<details><summary>Domain 3 — Testing and mathematical gates</summary>

- CHK-08-C1C8: Component oracle/regression controls PASS; full C1–C8/UI campaign UNRUN.
- CHK-09-MATH: Finite executable oracles PASS; formal sheaf/cohomology proof unavailable.
- CHK-10-9MOD: Native compilation and actual ERTS observed; full nine modalities UNRUN.
- CHK-11-REGR: Five existing engine tests PASS; full repository and UI regression UNRUN.

</details>
<details><summary>Domain 4 — Control and observability</summary>

- CHK-12-GLEAM: Pure module and direct native ERTS tests PASS; no production startup.
- CHK-13-HERMES: Native OCaml evidence orchestration used; no new solver/formal credit.
- CHK-14-ZIGVM: N/A to this isolated Gleam change; no ZigVM claim.
- CHK-15-MAX: N/A; no inference changes or observations.
- CHK-16-OTEL: Source/argv/hash receipts observed; production telemetry UNRUN.

</details>
<details><summary>Domain 5 — Governance and standalone Jujutsu</summary>

- CHK-17-SOV: Independent bounded review pending; sovereign admission NOT_GRANTED.
- CHK-18-JJ: Standalone sibling child, immutable source and evidence descendants preserved.

</details>

[Previous: Planning](http://nas-1.tail55d152.ts.net:4100/planning) · [Next: Evidence](http://nas-1.tail55d152.ts.net:4100/files/.uos-workspaces/ev98-peer-loop-20260909/docs/reviews/20260909-1600-ev101-graph-verification.json)

UOS footer: bounded graph component execution only. Admitted EV ceiling remains 93.
