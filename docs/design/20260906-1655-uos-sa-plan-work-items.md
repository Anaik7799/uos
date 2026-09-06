# UOS sa-plan work-item contracts

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #km-triad #zero-muda #tailscale-web

[Execution plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-1655-uos-sa-plan-execution-plan.md) | [Manifest](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json)

The manifest and native sa-plan IDs bind every task below. Original 60 task contracts are retained; additions and dependencies are explicit. Runtime state is read from sa-plan, not edited in this document.

## E01: Freeze a review candidate and reconcile advertised status

**Workstream:** E. **Priority:** P0. **Dependencies:** PLAN00. **Requirements:** RQ01, RQ31, RQ32, RQ33.

**Files:**

- create: `tools/verification/candidate_snapshot.ml`
- create: `tests/acceptance/candidate_snapshot_test.ml`
- inspect: `HANDOVER_TO_CODEX.md`
- inspect: `apps/cepaf_gleam/src/cepaf_gleam/fpp/evolutionary_cycles.gleam`

**Execution steps:**

- [ ] Step 1: Read jj status/log and collect runtime build/version endpoints; inventory concurrent writers without stopping them implicitly.
- [ ] Step 2: Create a bounded OCaml snapshot tool with allowlisted paths and presence-only records for known quarantined material; distinguish source metadata from admitted sanitized snapshots.
- [ ] Step 3: Bind historical claims to their original candidate and actual receipts. Reconcile new FPP code, agent_factory timestamps, TCM fields, CLI checks and evolutionary-cycle constants before assigning credit.

**Executable acceptance fixture:**

```json
{
  "id": "E01-regression",
  "given": {
    "candidate": "current-jj",
    "evidence_candidate": "older-jj",
    "source_mode": "read_only",
    "clock_source": "chrony",
    "inherited_claim": "all_passed"
  },
  "when": [ { "op": "candidate.snapshot" } ],
  "expect": {
    "inherited_credit": "STALE",
    "source_writes": 0,
    "records": [
      "change_id", "commit_id", "dirty_manifest", "served_build",
      "tool_versions", "clock_receipt"
    ],
    "signature_credit": false
  }
}
```

**Acceptance gate:** Every claim is current-supported, stale, unrun or contradicted with a locator; no automatic green from a file, comment, certificate or test total.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/candidate_snapshot_test.ml
```

E01 supplies this standalone bootstrap probe before the E02 runner exists; E02 subsequently replays the shared acceptance fixture.

## E02: Build a receipt-producing acceptance harness that can fail honestly

**Workstream:** E. **Priority:** P0. **Dependencies:** E01. **Requirements:** RQ19, RQ20, RQ31, RQ33.

**Files:**

- create: `tests/acceptance/contract.ml`
- create: `tests/acceptance/run.ml`
- create: `tests/acceptance/registry.ml`
- create: `tests/acceptance/runner_test.ml`
- create: `tests/acceptance/golden/receipt.schema.json`

**Execution steps:**

- [ ] Step 1: Define the JSON action/fixture/observation contract in this plan; implement strict decoding, namespaced adapter dispatch, command/dependency allowlists and bounded subprocesses using OCaml/Bos.
- [ ] Step 2: Keep expected observations in the assertion interpreter only; adapters collect real outputs, failures, artifacts and timings. Unknown operations, missing fixtures, skipped required tests and timeout are nonpassing.
- [ ] Step 3: Add self-tests for a known passing control, deliberate failing assertion, missing executable, timeout, child-tree cleanup, output quota and source/revision mismatch. Write receipts atomically with separate built/executed/passed fields.

**Executable acceptance fixture:**

```json
{
  "id": "E02-regression",
  "given": {
    "adapter": "missing_adapter",
    "required": true,
    "expected_exit": 0,
    "fixture": "temporary_isolated"
  },
  "when": [ { "op": "runner.verify" } ],
  "expect": {
    "exit_code": 2,
    "status": "ERROR",
    "passing_tests": 0,
    "children_reaped": true
  }
}
```

**Acceptance gate:** Known positive control passes; every negative self-test produces its named nonpassing state and no leaked child process. The runner is not admitted merely because it emits JSON.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task E02
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## E03: Replace constant verification and metrics with evidence-backed results

**Workstream:** E. **Priority:** P0. **Dependencies:** E02. **Requirements:** RQ31, RQ33, RQ34.

**Files:**

- modify: `tools/uos/src/main.gleam`
- modify: `tools/uos/src/uos.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/evolutionary_cycles.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/verification/master_verification_registry.gleam`
- create: `apps/cepaf_gleam/test/verification_truth_test.gleam`
- create: `tools/uos/test/exit_status_test.gleam`

**Execution steps:**

- [ ] Step 1: Write mutants that preserve existing contract files while removing runtime/formal receipts, changing their candidate or changing measured inputs; each must lose admission.
- [ ] Step 2: Replace constant cycle pass flags, synthetic digests and fixed quality values with typed observations and independently checked receipt references. Preserve historical certificates as attributed claims.
- [ ] Step 3: Make CLI process exit status reflect failed gates rather than only returning an ignored Int; feed the same result to UI/checklists and expose missing denominators.

**Executable acceptance fixture:**

```json
{
  "id": "E03-regression",
  "given": {
    "runtime_receipt": "missing",
    "formal_receipt": "missing",
    "existing_document": true,
    "claimed_token_gated": true,
    "claimed_parity": true,
    "metric_inputs": []
  },
  "when": [ { "op": "verification.evaluate" } ],
  "expect": {
    "admitted": false,
    "status": "UNRUN",
    "exit_code": 1,
    "metrics_available": false
  }
}
```

**Acceptance gate:** File-presence-only and constant-True mutants fail; CLI nonzero exit is observed by a subprocess; UI and API report the same evidence state.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task E03
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## E04: Complete the source, document and test census

**Workstream:** E. **Priority:** P1. **Dependencies:** E01, E02. **Requirements:** RQ01, RQ02, RQ03, RQ32.

**Files:**

- modify: `tools/ocaml_test_inventory/src/ocaml_test_inventory/inventory.gleam`
- modify: `tools/ocaml_test_inventory/src/ocaml_test_inventory/files.gleam`
- create: `tools/source_review/census.ml`
- create: `tools/source_review/census_test.ml`

**Execution steps:**

- [ ] Step 1: Resume the 161-file OCaml register, 770-file selected catalogue and 8,047-record corpus without double counting declarations/assertions/Gherkin steps.
- [ ] Step 2: Enumerate Dune/Gleeunit/ExUnit/Gherkin registration plus AST/import/call edges, linked journals/design documents and nested/symlinked Indrajaal/Sutra source roots; record every excluded/unreadable/generated/binary entry.
- [ ] Step 3: Give every case a stable source ID, locator/span, actual oracle, coverage scope, browser classification, transfer decision, dependency/runner and execution state. Close-reading status is distinct from indexed or hashed status.

**Executable acceptance fixture:**

```json
{
  "id": "E04-regression",
  "given": {
    "files": [
      "registered_test.ml", "helper.ml", "journal.md", "unreadable.md"
    ],
    "registered_tests": [ "registered_test.ml" ],
    "ast_sites": 3,
    "unreadable": [ "unreadable.md" ]
  },
  "when": [ { "op": "census.classify" } ],
  "expect": {
    "files_accounted": 4,
    "unreadable": 1,
    "complete_review": false,
    "executed_tests": 0
  }
}
```

**Acceptance gate:** Scoped files and references equal reviewed plus classified exclusions plus explicit remaining frontier; census may finish while full close reading remains open, and that distinction is machine visible.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task E04
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## E05: Pin upstream techniques, fixtures and adoption decisions

**Workstream:** E. **Priority:** P1. **Dependencies:** E04. **Requirements:** RQ01, RQ04, RQ12, RQ32.

**Files:**

- create: `tools/source_review/adoption.ml`
- create: `tests/acceptance/adoption_test.ml`
- create: `governance/sources/20260906-0817-adoption-protocol.md`

**Execution steps:**

- [ ] Step 1: Bind Google web.dev/Lighthouse/HEART, WPT/WCAG/ARIA/axe, CommonMark/MediaWiki/Parsoid/TiddlyWiki/Logseq/Joplin/Docusaurus/Sphinx, SHACL/PROV, graph/category/property/fuzz references and NASA/OMG/Zenoh suites to exact locators and versions.
- [ ] Step 2: Review license/attribution and test dialect compatibility before copying any fixture; use read-only citations where source writers or licensing prevent admission.
- [ ] Step 3: Map each technique to a UOS requirement, mechanism, intended observable improvement, test/oracle, tradeoff and adoption/rejection rationale. Quarantined material remains presence only.

**Executable acceptance fixture:**

```json
{
  "id": "E05-regression",
  "given": {
    "source_revision": "pinned",
    "license": "unreviewed",
    "writers_quiesced": false,
    "contains_secret": false,
    "formal_key": false,
    "runtime_key": false
  },
  "when": [ { "op": "source.admit" } ],
  "expect": {
    "admitted": false,
    "source_writes": 0,
    "reason_codes": [
      "license_not_reviewed", "source_not_quiesced", "two_keys_missing"
    ]
  }
}
```

**Acceptance gate:** Every imported fixture/algorithm has a reviewed license and exact provenance plus both admission keys; every research recommendation has a concrete UOS use or explicit rejection.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task E05
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## E06: Create cross-language fixtures and guarded OCaml differential execution

**Workstream:** E. **Priority:** P1. **Dependencies:** E02, E04, E05, M02. **Requirements:** RQ01, RQ03, RQ19, RQ21.

**Files:**

- modify: `apps/cepaf_gleam/src/cepaf_gleam/verification/ocaml_differential_oracle.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/verification/ocaml_parity_verifier.gleam`
- create: `tests/differential/run_oracle.ml`
- create: `tests/differential/fixture_codec.ml`
- create: `apps/cepaf_gleam/test/ocaml_oracle_contract_test.gleam`

**Execution steps:**

- [ ] Step 1: Define lossless versioned fixtures for ASTs, links, graph states, actions and outcomes; preserve binary bytes and explicit error categories.
- [ ] Step 2: Run eligible original OCaml in an admitted read-only sandbox with isolated output directory and bounded dependencies; unavailable original execution remains UNRUN.
- [ ] Step 3: Compare Gleam observations with independent OCaml outputs modulo only documented normalization. Retain counterexamples and reject artificial compare-to-self or constant-success adapters.

**Executable acceptance fixture:**

```json
{
  "id": "E06-regression",
  "given": {
    "fixture": "unicode-link-and-nul-payload",
    "left_status": "tool_missing",
    "right_output": "valid",
    "normalization": "declared_semantics_only"
  },
  "when": [ { "op": "oracle.compare" } ],
  "expect": {
    "status": "UNRUN",
    "equivalent": false,
    "original_source_changed": false
  }
}
```

**Acceptance gate:** Positive shared fixtures agree; deliberate Gleam mutation disagrees; missing/failed original tool cannot produce parity credit; original source digests remain identical.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task E06
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## E07: Port every selected useful test obligation into Gleam suites

**Workstream:** E. **Priority:** P1. **Dependencies:** E04, E06, P01, P03. **Requirements:** RQ03, RQ19, RQ20, RQ21.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/knowledge/test_contract.gleam`
- create: `apps/cepaf_gleam/test/knowledge_html_port_test.gleam`
- create: `apps/cepaf_gleam/test/knowledge_wiki_port_test.gleam`
- create: `apps/cepaf_gleam/test/knowledge_zk_port_test.gleam`
- create: `apps/cepaf_gleam/test/knowledge_km_port_test.gleam`

**Execution steps:**

- [ ] Step 1: For each accepted source case implement its domain behavior and discriminating Gleam test using the shared fixture contract; prioritize parser/renderer/link/key/graph algebra laws.
- [ ] Step 2: Keep browser cases in the browser adapter, runtime actor cases in real process suites, and OCaml-only formal oracles in Hermes; distinguish a port from a reference fixture.
- [ ] Step 3: Require each accepted original case to resolve to a new test ID and coverage explanation. Reject obsolete/duplicate/tautological cases with evidence instead of reproducing weak assertions.

**Executable acceptance fixture:**

```json
{
  "id": "E07-regression",
  "given": {
    "cases": [
      {
        "id": "html-escape",
        "decision": "gleam_port",
        "gleam_case": "missing"
      },
      {
        "id": "browser-navigation",
        "decision": "browser_adapter",
        "browser_case": "missing"
      },
      {
        "id": "tautology",
        "decision": "reject",
        "reason": "does_not_discriminate"
      }
    ]
  },
  "when": [ { "op": "migration.coverage" } ],
  "expect": {
    "required_missing": 2,
    "coverage_complete": false,
    "rejected_with_reason": 1
  }
}
```

**Acceptance gate:** No selected useful case lacks a runnable destination; a mutation appropriate to each class is detected; all original OCaml remains unchanged.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task E07
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## E08: Connect requirements, sources, plans and observations to one ledger

**Workstream:** E. **Priority:** P1. **Dependencies:** E02, E03, E04. **Requirements:** RQ02, RQ03, RQ11, RQ31, RQ32, RQ35.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/verification/trace_ledger.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/verification/master_verification_registry.gleam`
- modify: `tools/planning_ledger/src/uos_planning_ledger.gleam`
- create: `apps/cepaf_gleam/test/trace_ledger_test.gleam`

**Execution steps:**

- [ ] Step 1: Use stable typed IDs for requirement/source/intent/model/law/code/test/receipt/page/component edges; reject dangling references and conflicting identity.
- [ ] Step 2: Publish backlog/report projections through the admitted planning writer API, with exclusive epoch leases and idempotent IDs; never patch a live SQLite/WAL directly.
- [ ] Step 3: Add change-impact invalidation so code/model/source/dependency/route changes stale the affected descendants and aggregate checklist results.

**Executable acceptance fixture:**

```json
{
  "id": "E08-regression",
  "given": {
    "requirement": "RQ25",
    "source": "S-1",
    "intent": "I-1",
    "model": "M-1",
    "law": "L-1",
    "code": "C-1",
    "test": "T-1",
    "receipt_candidate": "old",
    "current_candidate": "new",
    "page": "/wiki"
  },
  "when": [ { "op": "ledger.validate" } ],
  "expect": {
    "trace_connected": true,
    "admitted": false,
    "receipt_state": "STALE"
  }
}
```

**Acceptance gate:** Trace paths are machine traversable; stale evidence propagates through dependent nodes; rereading/importing the same plan is idempotent.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task E08
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## M01: Reconcile DMC/TCM vocabularies and register actual carriers

**Workstream:** M. **Priority:** P0. **Dependencies:** E02, E03. **Requirements:** RQ07, RQ08, RQ09, RQ10, RQ11.

**Files:**

- modify: `contracts/rules/dmc-tcm-mandate.md`
- create: `apps/cepaf_gleam/src/cepaf_gleam/semantics/vocabulary.gleam`
- create: `apps/cepaf_gleam/test/semantics_vocabulary_test.gleam`
- inspect: `apps/cepaf_gleam/src/cepaf_gleam/fpp/dmc_tcm.gleam`

**Execution steps:**

- [ ] Step 1: Register Denotational Meta-Calculus separately from new FPP Deterministic Memory Coherence; reconcile Type Class Morphisms, Traceability Coordinate Matrix and Temporal Coherence without deleting any obligation.
- [ ] Step 2: Define concrete domain records/enums and measured observations; ten axes, thirteen trace fields and ten fractal layers are distinct types.
- [ ] Step 3: Map each old public API and rule to its canonical domain; add compatibility adapters where needed and tests rejecting cross-domain substitution.

**Executable acceptance fixture:**

```json
{
  "id": "M01-regression",
  "given": {
    "labels": [
      "DMC-Denotation", "DMC-Memory", "TCM-Morphism", "TCM-Trace13",
      "TCM-Temporal", "TensorAxis", "FractalLayer"
    ]
  },
  "when": [ { "op": "semantics.resolve" } ],
  "expect": {
    "distinct_domains": 7,
    "aliased_domains": 0,
    "all_have_carrier_and_observation": true
  }
}
```

**Acceptance gate:** Every use of DMC/TCM in code/contracts/UI maps to one documented domain; no loss of previously requested semantics; registry compiles.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task M01
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## M02: Implement pure denotational intent and independent state transitions

**Workstream:** M. **Priority:** P0. **Dependencies:** E02, M01. **Requirements:** RQ07, RQ19, RQ20, RQ21.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/semantics/intent.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/semantics/reference.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/intent.gleam`
- create: `apps/cepaf_gleam/test/intent_denotation_test.gleam`

**Execution steps:**

- [ ] Step 1: Define intent AST variants for navigation/read/query, guarded content changes, actor commands and verification jobs with source spans and typed errors.
- [ ] Step 2: Implement a pure reference interpretation from context/state/intent to either a value plus proposed effects or a typed rejection; strings describing an action are not the denotation.
- [ ] Step 3: Define sequence identity/associativity under the chosen error semantics, and test denotation against an independent small transition table for both accepted and rejected programs.

**Executable acceptance fixture:**

```json
{
  "id": "M02-regression",
  "given": {
    "state": { "notes": [ "a" ], "selected": "a" },
    "program": [ { "kind": "navigate", "target": "missing" } ]
  },
  "when": [ { "op": "intent.denote" } ],
  "expect": {
    "result": "UnknownTarget",
    "state": { "notes": [ "a" ], "selected": "a" },
    "effects": []
  }
}
```

**Acceptance gate:** State/effect observations match the reference; invalid target and partial-failure semantics are explicit; pure denotation performs no I/O.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task M02
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## M03: Enforce typed authorization and effect isolation at every ingress

**Workstream:** M. **Priority:** P0. **Dependencies:** E03, M02. **Requirements:** RQ07, RQ10, RQ15, RQ27, RQ34.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/semantics/authorization.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/semantics/effects.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/api/denotational_intent_router.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/api/denotational_intent_api.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/intent.gleam`
- create: `apps/cepaf_gleam/test/intent_authorization_test.gleam`

**Execution steps:**

- [ ] Step 1: Create an opaque authorized-intent value only the policy module can construct; use current actor/action/target/capability/epoch/context, not a caller-provided guard or proof-reference string.
- [ ] Step 2: Centralize the effect interpreter and enforce protected serial 25503L801736 independently at relevant storage boundary; observers cannot become writers through telemetry or forged traces.
- [ ] Step 3: Route HTTP/AG-UI/FPP/Zenoh commands through the same policy check. Add compiler-negative unauthorized constructor/use fixtures plus real effect-log tests for denied, expired, replayed and allowed intents.

**Executable acceptance fixture:**

```json
{
  "id": "M03-regression",
  "given": {
    "actor": "observer",
    "action": "write_note",
    "target": "note/a",
    "guard": true,
    "proof_ref": "unverified-text",
    "serial": "other-device",
    "payload": "changed"
  },
  "when": [ { "op": "intent.authorize_and_execute" } ],
  "expect": {
    "decision": "Denied",
    "effect_count": 0,
    "authoritative_state_changed": false
  }
}
```

**Acceptance gate:** Every denied/replayed/untrusted intent has zero effects; independent boundary interlocks hold; authorized intent produces exactly its declared effect proposal and receipt.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task M03
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## M04: Implement complete Trace13 transport and transition checks

**Workstream:** M. **Priority:** P0. **Dependencies:** M01, M03. **Requirements:** RQ09, RQ21, RQ34.

**Files:**

- modify: `apps/cepaf_gleam/src/cepaf_gleam/verification/web_quality_contract.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/verification/dmc_tcm_algebraic_atlas.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/dmc_tcm.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/semantics/trace.gleam`
- create: `apps/cepaf_gleam/test/trace13_mutation_test.gleam`

**Execution steps:**

- [ ] Step 1: Register all thirteen coordinate names/types from the reconciled schema; reject missing/unknown fields unless a versioned migration explicitly handles them.
- [ ] Step 2: Use exact preservation for transport, and a separate transition relation for permitted causal/time/epoch changes; preserve immutable authority and correlation fields.
- [ ] Step 3: Mutate every field and pairs, exercise old/new schema conversion, and connect the same checks to actual network envelopes and evidence-writer boundaries.

**Executable acceptance fixture:**

```json
{
  "id": "M04-regression",
  "given": {
    "mode": "transport",
    "base": "valid_trace13_fixture",
    "mutations": "each_of_13_fields_and_pairs"
  },
  "when": [ { "op": "trace.check" } ],
  "expect": {
    "single_field_mutations_rejected": 13,
    "unapproved_pair_mutations_rejected": true,
    "unchanged_control_passes": true
  }
}
```

**Acceptance gate:** All thirteen independent transport mutants fail, permitted state transitions pass only their explicit relation, and network round trips preserve the fields.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task M04
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## M05: Replace fixed time and value-only leases with real fenced ownership

**Workstream:** M. **Priority:** P0. **Dependencies:** M03, M04. **Requirements:** RQ10, RQ27, RQ34.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/semantics/clock.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/semantics/lease.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/dmc_tcm.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/agent_factory.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/uos_sup.gleam`
- create: `apps/cepaf_gleam/test/lease_clock_test.gleam`

**Execution steps:**

- [ ] Step 1: Inject wall and monotonic clocks through explicit interfaces; replace constant date/time and synthetic vectors, testing epoch/day/month/year rollover and actual timestamp conversion.
- [ ] Step 2: Put lease acquisition/renewal/release and epoch comparison at the serialized authoritative writer, not only in a freely copied record; fence stale writers at commit.
- [ ] Step 3: Test two concurrent requesters, crash/restart, expired leases, negative time, drift bands, telemetry non-interference and interval-ID overlap with unknown components rejected.

**Executable acceptance fixture:**

```json
{
  "id": "M05-regression",
  "given": {
    "lease": { "holder": "writer-b", "epoch": 8 },
    "command": { "holder": "writer-a", "epoch": 7 },
    "wall_clock_jump_ms": -60000,
    "monotonic_sequence": [ 100, 101 ]
  },
  "when": [ { "op": "lease.apply" } ],
  "expect": {
    "command": "RejectedStaleEpoch",
    "writes": 0,
    "monotonic_order_preserved": true,
    "wall_clock_jump_reported": true
  }
}
```

**Acceptance gate:** At most one current writer can commit; stale epochs never commit; time strings match supplied instants; observer-only state cannot mutate the ledger.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task M05
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## M06: Implement executable morphism, graph and category laws

**Workstream:** M. **Priority:** P1. **Dependencies:** M02, M04. **Requirements:** RQ08, RQ11, RQ12, RQ21.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/semantics/morphism.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/knowledge/graph.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/verification/graph_verification.gleam`
- create: `apps/cepaf_gleam/test/morphism_graph_laws_test.gleam`

**Execution steps:**

- [ ] Step 1: Define objects/arrows/composability, identity and composition with typed errors; represent maps as executable functions/dictionaries with a named observation.
- [ ] Step 2: Implement BFS/DFS reachability, SCCs, topological sort where acyclicity is required, shortest paths and overlap/impact graph operations with explicit complexities.
- [ ] Step 3: Compare optimized algorithms to independent finite reference algorithms; test identity/associativity and operation preservation. Do not require legitimate navigation/link graphs to be acyclic or every path to be invertible.

**Executable acceptance fixture:**

```json
{
  "id": "M06-regression",
  "given": {
    "vertices": [ "a", "b", "c" ],
    "edges": [ [ "a", "b" ], [ "b", "c" ] ],
    "mapped_edges": [ [ "a", "b" ] ],
    "law": "reachability_preservation"
  },
  "when": [ { "op": "graph.verify" } ],
  "expect": {
    "valid_functor": false,
    "counterexample": [ "a", "c" ],
    "reference_algorithm": "independent_floyd_warshall"
  }
}
```

**Acceptance gate:** Every claimed morphism law has quantified domains and counterexample-sensitive tests; graph mutants fail against an independent oracle.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task M06
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## M07: Complete L0-L9 atlas and finite sheaf constructions

**Workstream:** M. **Priority:** P1. **Dependencies:** E08, M01, M06. **Requirements:** RQ11, RQ12, RQ21, RQ30, RQ35.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/semantics/atlas.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/semantics/sheaf.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/algebraic_atlas.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/fpp_atlas_view.gleam`
- create: `apps/cepaf_gleam/test/atlas_sheaf_laws_test.gleam`

**Execution steps:**

- [ ] Step 1: Derive overlap from declared domains, reject duplicate/conflicting local assignments, implement restriction composition and gluing uniqueness over finite covers, including three or more sections.
- [ ] Step 2: Generate one atlas registry with carriers, operations, observations, denotation, laws, generators/shrinkers, independent oracles, source/code/test/proof/component locators and evidence state for all ten layers.
- [ ] Step 3: Replace constant associativity/gluing flags in FPP reports with actual law receipts. Generate equivalent ASCII/Mermaid views from the same graph and report uncovered L8/L9 deployment/model obligations.

**Executable acceptance fixture:**

```json
{
  "id": "M07-regression",
  "given": {
    "sections": [
      { "domain": [ "x" ], "values": { "x": "left" } },
      { "domain": [ "x", "y" ], "values": { "x": "right", "y": "ok" } }
    ],
    "caller_claimed_overlap": [],
    "layers": [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ]
  },
  "when": [ { "op": "atlas.glue" } ],
  "expect": {
    "result": "OverlapConflict",
    "conflicting_key": "x",
    "accepts_caller_omitted_overlap": false,
    "layer_count": 10
  }
}
```

**Acceptance gate:** No missing layer, opaque claimed law or omitted-overlap conflict is admitted; every atlas entry resolves to code and tests; rendering diagrams does not create proof credit.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task M07
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## M08: Bind real compiler and bounded formal workers to implementation semantics

**Workstream:** M. **Priority:** P1. **Dependencies:** E02, M04, M05, M06, M07. **Requirements:** RQ05, RQ06, RQ08, RQ11.

**Files:**

- modify: `tools/web_quality_gate.ml`
- create: `tools/verification/formal_worker.ml`
- create: `tests/formal/worker_test.ml`
- modify: `formal/lean/Traceability.lean`
- modify: `formal/lean/TwoLattice_STM.lean`
- modify: `formal/quint/parity_frontier.qnt`
- modify: `formal/registry/formal-manifest.toml`

**Execution steps:**

- [ ] Step 1: Pin toolchains and encode value-level invariants from explicit Gleam transition observations or a checked IR projection; retain model/AST/source/input correspondence.
- [ ] Step 2: Run each solver in a normalized isolated worker with timeout/memory/output bounds and process-tree reaping; require satisfiable controls and expected failures for malformed/unsupported/missing tools.
- [ ] Step 3: Run actual Gleam BEAM and applicable JavaScript checks, compiler-negative fixtures, Lean/Gospel/Quint obligations, and reject missing axioms/proof holes. Enumerate properties not expressible in a given backend.

**Executable acceptance fixture:**

```json
{
  "id": "M08-regression",
  "given": {
    "law": "trace_transport",
    "negated_query": "pinned-generated-smt",
    "worker_result": "unknown",
    "satisfiable_control": "sat",
    "candidate_match": true
  },
  "when": [ { "op": "formal.check" } ],
  "expect": {
    "admitted": false,
    "status": "UNKNOWN",
    "process_tree_reaped": true
  }
}
```

**Acceptance gate:** Formal results are invocation-specific; timeout/UNKNOWN/syntax error/proof hole cannot pass; a model or code mutation invalidates the corresponding proof/receipt.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task M08
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## A01: Pin and implement the full FPP language front end

**Workstream:** A. **Priority:** P1. **Dependencies:** E05, M01. **Requirements:** RQ04, RQ13, RQ19.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/fpp/parser.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/domain.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/fpp/conformance.gleam`
- create: `apps/cepaf_gleam/test/fpp_parser_conformance_test.gleam`

**Execution steps:**

- [ ] Step 1: Freeze the FPP specification/compiler and enumerate every clause, syntax construct, type, builder and positive/negative upstream test with source/license provenance.
- [ ] Step 2: Implement complete typed AST/parser/name resolution and diagnostics, preserving annotations, imports/includes, IDs, expressions, arrays/enums/structs, components, topology and state-machine constructs supported by the pin.
- [ ] Step 3: Compare parse/validation output and normalized round trips with the pinned official compiler. Turn every uncovered clause into a bounded child work item with a runnable fixture.

**Executable acceptance fixture:**

```json
{
  "id": "A01-regression",
  "given": {
    "source": "unknown_construct X",
    "file": "negative.fpp",
    "reference_tool": "pinned_official_fpp"
  },
  "when": [ { "op": "fpp.parse" } ],
  "expect": {
    "accepted": false,
    "diagnostic_has_source_span": true,
    "unsupported_construct_not_dropped": true
  }
}
```

**Acceptance gate:** Every pinned FPP clause has implementation and positive/negative evidence; unsupported syntax blocks full-conformance admission.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task A01
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## A02: Validate topology, ID spaces and typed port composition

**Workstream:** A. **Priority:** P1. **Dependencies:** A01, M06. **Requirements:** RQ12, RQ13, RQ15.

**Files:**

- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/topology.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/domain.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/dmc_tcm.gleam`
- create: `apps/cepaf_gleam/test/fpp_topology_contract_test.gleam`

**Execution steps:**

- [ ] Step 1: Extend existing topology validators for concrete type/arity/direction, serial/typed ports, duplicate IDs, indexing, instance ownership and lifecycle connections.
- [ ] Step 2: Compute ID ranges from the validated model; do not substitute a default span for missing components. Check overflow and overlap against an independent interval/graph oracle.
- [ ] Step 3: Represent allowed command/query/telemetry routes and forbidden observer-to-writer edges explicitly; require actual runtime routing to correspond to this graph.

**Executable acceptance fixture:**

```json
{
  "id": "A02-regression",
  "given": {
    "instances": [
      { "id": "a", "base": 100, "span": 10 },
      { "id": "b", "base": 105, "span": 10 }
    ],
    "edge": { "from_type": "IntPort", "to_type": "StringPort" },
    "unknown_component": "missing"
  },
  "when": [ { "op": "fpp.validate_topology" } ],
  "expect": {
    "valid": false,
    "errors": [ "id_overlap", "port_type_mismatch", "unknown_component" ]
  }
}
```

**Acceptance gate:** Invalid edges/ranges fail with located errors; valid bounded cyclic communication is allowed where specified; actual port bindings resolve to unique authorized targets.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task A02
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## A03: Complete FPP commands, parameters, telemetry, packets and dictionaries

**Workstream:** A. **Priority:** P1. **Dependencies:** A02, M03. **Requirements:** RQ13, RQ19, RQ21.

**Files:**

- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/dictionary.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/prm_db.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/packetizer.gleam`
- create: `apps/cepaf_gleam/test/fpp_wire_vectors_test.gleam`

**Execution steps:**

- [ ] Step 1: Pin actual F Prime command/event/parameter/telemetry/dictionary and selected wire-format contracts; separate CCSDS framing from F Prime protocols and do not infer compatibility from a sync constant.
- [ ] Step 2: Implement complete typed encode/decode, limits, IDs, endianness, checksum/framing, persistence semantics, parameter validation and command completion in the existing modules.
- [ ] Step 3: Use official golden vectors, binary round trips, malformed/truncated/oversized payloads, dictionary drift, unknown IDs and unauthorized parameter changes.

**Executable acceptance fixture:**

```json
{
  "id": "A03-regression",
  "given": {
    "fixture": "official_pinned_packet_vector",
    "mutation": "flip_payload_bit",
    "dictionary_revision": "matched",
    "parameter_write_authorized": false
  },
  "when": [ { "op": "fpp.decode_packet" } ],
  "expect": {
    "packet": "RejectedChecksum",
    "parameter_writes": 0,
    "dictionary_drift": false
  }
}
```

**Acceptance gate:** Wire vectors match their exact protocol/version; mutations fail correctly; no generic packet record or claimed checksum substitutes for observed encoding/decoding.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task A03
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## A04: Complete hierarchical state-machine semantics

**Workstream:** A. **Priority:** P1. **Dependencies:** A01, M02. **Requirements:** RQ13, RQ15, RQ19, RQ21.

**Files:**

- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/interp.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/domain.gleam`
- modify: `apps/cepaf_gleam/test/fpp_hsm_test.gleam`

**Execution steps:**

- [ ] Step 1: Use the pinned FPP/HSM semantics for hierarchical initial states, guard/action ordering, event dispatch, history/internal/self transitions and invalid state references.
- [ ] Step 2: Test least-common-ancestor exit leaf-first and entry root-first against a simple independent transition interpreter, including nested cases and rejected guards.
- [ ] Step 3: Bound run-to-completion work and reject cyclic initialization or unbounded microsteps; retain generated stateful sequences and minimized counterexamples.

**Executable acceptance fixture:**

```json
{
  "id": "A04-regression",
  "given": {
    "active_path": [ "root", "left", "leaf" ],
    "target_path": [ "root", "right", "leaf2" ],
    "event": "switch",
    "guard": true
  },
  "when": [ { "op": "fpp.hsm_step" } ],
  "expect": {
    "exit_order": [ "leaf", "left" ],
    "entry_order": [ "right", "leaf2" ],
    "active_path": [ "root", "right", "leaf2" ],
    "actions_run_once": true
  }
}
```

**Acceptance gate:** All state-machine clauses have trace equivalence evidence; guard false preserves state and has no action effects; bounded runaway cases fail explicitly.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task A04
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## A05: Complete passive, queued and active process interpretations

**Workstream:** A. **Priority:** P1. **Dependencies:** A02, A04, M03, M05. **Requirements:** RQ13, RQ15, RQ19, RQ34.

**Files:**

- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/actor.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/interp.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/uos_sup.gleam`
- create: `apps/cepaf_gleam/test/fpp_actor_runtime_test.gleam`

**Execution steps:**

- [ ] Step 1: Extend the real actor.start path already present; distinguish synchronous passive calls, caller-drained queued behavior and autonomous active processing according to the model.
- [ ] Step 2: Add actual queue drain and execution, explicit ingress credits/backpressure and bounded work. A bounded list inside state does not bound the BEAM mailbox.
- [ ] Step 3: Fail actor initialization for invalid HSMs instead of silently discarding them; test shutdown, owner death, restart budgets, overflow policies and command accept/apply/commit stages.

**Executable acceptance fixture:**

```json
{
  "id": "A05-regression",
  "given": {
    "component_kind": "queued",
    "capacity": 2,
    "arrival_commands": [ 1, 2, 3 ],
    "drain_steps": 2,
    "overflow_policy": "drop_new"
  },
  "when": [ { "op": "actor.run" } ],
  "expect": {
    "applied": [ 1, 2 ],
    "dropped": [ 3 ],
    "queue_depth": 0,
    "reply_stage": "applied",
    "supervisor_observed": true
  }
}
```

**Acceptance gate:** Real process traces match the model under load and failure; bounded mailbox/resource behavior is measured; no enqueue acknowledgment is reported as completed execution.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task A05
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## A06: Map every required agent role and MIQ service to real behavior

**Workstream:** A. **Priority:** P1. **Dependencies:** A05, E04, M07. **Requirements:** RQ11, RQ15, RQ28, RQ34.

**Files:**

- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/agent_taxonomy.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/agent_factory.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/miq_services.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/fpp/ontology.gleam`
- create: `apps/cepaf_gleam/test/agent_role_runtime_test.gleam`

**Execution steps:**

- [ ] Step 1: Map Harness-Bionic and C3I roles to UOS responsibilities and source evidence; validate whether mappings are total, injective or many-to-one instead of assuming a bijection.
- [ ] Step 2: Bind agent instances to actual subjects/processes, real clocks, capability boundaries and supervision; connect MIQ/inference/media operations to supervised bounded services with typed outcomes.
- [ ] Step 3: Exercise intent ingress, registries, corpus writers, renderer/index, auditors, verification workers, recovery, provenance and UI projection roles; every declared role has an observable workflow.

**Executable acceptance fixture:**

```json
{
  "id": "A06-regression",
  "given": {
    "role": "link_auditor",
    "input": { "page": "/wiki", "broken_target": "/missing" },
    "requested_effect": "write_corpus"
  },
  "when": [ { "op": "actor.role_workflow" } ],
  "expect": {
    "finding": "BrokenLink",
    "corpus_writes": 0,
    "proposal_requires_policy": true,
    "timestamp_source": "runtime_clock"
  }
}
```

**Acceptance gate:** No role receives credit from an enum/name alone; every enabled service executes under its real supervisor and authority contract.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task A06
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## A07: Implement the complete SysML/KerML syntax and semantic front end

**Workstream:** A. **Priority:** P1. **Dependencies:** E05, M01. **Requirements:** RQ04, RQ14, RQ19.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/sysml/ast.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/sysml/parser.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/sysml/resolve.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/sysml/typecheck.gleam`
- create: `apps/cepaf_gleam/test/sysml_conformance_test.gleam`
- inspect: `engines/hermes/modules/hermes_sysml/sysml_grammar.ml`

**Execution steps:**

- [ ] Step 1: Pin OMG SysML 2.0/KerML 1.0 and compatible reference tooling/libraries/interchange schemas; enumerate complete normative syntax and semantic clause obligations.
- [ ] Step 2: Build Gleam source-span AST, scopes/imports/resolution, classification/specialization, feature typing, multiplicities, units/quantities and diagnostics; preserve the original unit-valued Hermes grammar.
- [ ] Step 3: Implement and test every normative clause with reviewed reference positives/negatives. Separate imported library conformance from the core parser and keep missing clauses visible.

**Executable acceptance fixture:**

```json
{
  "id": "A07-regression",
  "given": {
    "model": "pinned_negative_reference_model",
    "case": "unresolved_feature_and_bad_units"
  },
  "when": [ { "op": "sysml.validate" } ],
  "expect": {
    "valid": false,
    "errors_have_locations": true,
    "unit_valued_model": false,
    "original_hermes_changed": false
  }
}
```

**Acceptance gate:** Full pinned-standard denominator is explicit; no unsupported construct is silently accepted/discarded; parser success alone is not semantic conformance.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task A07
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## A08: Implement SysML behavior, requirements, verification and interchange

**Workstream:** A. **Priority:** P1. **Dependencies:** A07, M02, M06. **Requirements:** RQ14, RQ19, RQ21, RQ32.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/sysml/semantics.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/sysml/interchange.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/sysml/requirements.gleam`
- create: `apps/cepaf_gleam/test/sysml_behavior_roundtrip_test.gleam`

**Execution steps:**

- [ ] Step 1: Complete parts/ports/connections, actions/states/transitions, calculations/constraints, requirements/satisfy/verify and other normative model features from the clause matrix.
- [ ] Step 2: Define pure execution semantics for executable constructs and explicitly typed non-executable model constructs; retain all supported standard information in interchange.
- [ ] Step 3: Test located semantic errors, units/multiplicity/specialization, stable IDs, round trips modulo stated normalization and comparison with the pinned reference validator.

**Executable acceptance fixture:**

```json
{
  "id": "A08-regression",
  "given": {
    "model": "requirements-actions-states-connections-fixture",
    "mutation": "drop_verification_case_link"
  },
  "when": [ { "op": "sysml.roundtrip" } ],
  "expect": {
    "equivalent": false,
    "diagnostic": "VerificationTraceLost",
    "stable_ids_preserved": true
  }
}
```

**Acceptance gate:** Every standard feature is represented and validated; executable behavior matches its reference; unsupported reference-tool coverage is a named gap rather than a pass.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task A08
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## A09: Prove and test model-to-actor correspondence

**Workstream:** A. **Priority:** P1. **Dependencies:** A03, A05, A08, M08. **Requirements:** RQ06, RQ11, RQ13, RQ14, RQ15.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/sysml/fpp_projection.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/fpp/runtime_projection.gleam`
- create: `apps/cepaf_gleam/test/model_runtime_correspondence_test.gleam`
- create: `formal/quint/actor_correspondence.qnt`

**Execution steps:**

- [ ] Step 1: Create typed projections preserving stable model IDs, ports, ownership, requirements, units and trace coordinates; declare any abstraction relation explicitly.
- [ ] Step 2: Generate bounded traces from SysML/FPP reference transitions and observe actual actor event histories independently; compare under the declared observation relation.
- [ ] Step 3: Bind formal temporal checks to the same projection and input trace corpus; reject altered topology, omitted actions, unauthorized transitions and unmodeled runtime edges.

**Executable acceptance fixture:**

```json
{
  "id": "A09-regression",
  "given": {
    "model_events": [ "accepted", "applied", "committed" ],
    "runtime_events": [ "accepted", "committed" ],
    "mutation": "omit_apply"
  },
  "when": [ { "op": "model.compare_trace" } ],
  "expect": {
    "correspondence": false,
    "counterexample_step": 1,
    "admitted": false
  }
}
```

**Acceptance gate:** Each admitted model feature has reference-tool and actual runtime correspondence evidence; a generated model file is not treated as proof.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task A09
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## A10: Deliver an operational knowledge and verification actor ecology

**Workstream:** A. **Priority:** P1. **Dependencies:** A06, A09, W06, Z12. **Requirements:** RQ15, RQ16, RQ20, RQ34.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/ecology/knowledge_workflow.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/ecology/verification_workflow.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/uos_sup.gleam`
- create: `apps/cepaf_gleam/test/ecology_journeys_test.gleam`

**Execution steps:**

- [ ] Step 1: Deliver one read-only find/open/backlink/verify-note journey and one authorized edit-or-command journey with immutable evidence and consumer acknowledgment.
- [ ] Step 2: Run locally between real supervised processes and across two nodes with an isolated real router; constrain peer shortcuts so transport evidence identifies the exercised path.
- [ ] Step 3: Exercise writer/auditor separation, UI projection, correlation, crash-after-apply recovery and missing peer behavior. Extend to every inventoried role/edge after the vertical slices pass.

**Executable acceptance fixture:**

```json
{
  "id": "A10-regression",
  "given": {
    "entry": "browser",
    "intent": "verify_note_links",
    "note": "note/a",
    "broken_link": "note/missing",
    "transport": "real_zenoh",
    "observer": "separate_process"
  },
  "when": [ { "op": "ecology.journey" } ],
  "expect": {
    "policy_checked": true,
    "send_observed": true,
    "receive_observed": true,
    "finding_visible": true,
    "corpus_writes": 0,
    "trace_chain_complete": true
  }
}
```

**Acceptance gate:** Every required role and domain edge executes with policy/model/trace correspondence; receipts distinguish accepted, received, applied and committed.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task A10
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## Z01: Complete candidate census and pin the native feature contract

**Workstream:** Z. **Priority:** P0. **Dependencies:** E04, E05, M01. **Requirements:** RQ04, RQ17, RQ18.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/zenoh/capabilities.gleam`
- create: `tools/verification/zenoh_api_inventory.ml`
- inspect: `apps/cepaf_gleam/native/c3i_nif/Cargo.toml`
- inspect: `apps/cepaf_gleam/native/c3i_nif/src/zenoh_nif.rs`
- create: `apps/cepaf_gleam/test/zenoh_capability_inventory_test.gleam`

**Execution steps:**

- [ ] Step 1: Compare all located Gleam/Elixir bindings, wrappers, native modules, lockfiles, tests and journals; extend the three-candidate comparison before choosing a source baseline.
- [ ] Step 2: Select exact compatible Zenoh/zenoh-ext/Rust/Rustler/OTP/router versions using release/toolchain/peer compatibility evidence; record as-found and chosen profiles separately.
- [ ] Step 3: Generate every public API/type/enum/builder/config/feature/platform/extension row from pinned sources and map it to planned native/Gleam APIs and tests. Include all sixteen families and all feature flags; reject census drift in CI.

**Executable acceptance fixture:**

```json
{
  "id": "Z01-regression",
  "given": {
    "candidates": [ "current_c3i_uos", "legacy_indrajaal", "sutra" ],
    "exports": [ 5, 17, 6 ],
    "runtime_benchmarks": [],
    "upstream_pages": [ "1.8.0", "1.9.0", "1.10.0" ]
  },
  "when": [ { "op": "zenoh.inventory" } ],
  "expect": {
    "performance_winner": "UNKNOWN",
    "selected_runtime_version": "requires_compatibility_receipt",
    "missing_api_rows_block_completion": true
  }
}
```

**Acceptance gate:** Every pinned upstream public item and flag has a row; no fastest claim without comparable native measurements; missing stable/unstable/target rows remain open.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task Z01
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## Z02: Repair native loading, result shapes and truthful error handling

**Workstream:** Z. **Priority:** P0. **Dependencies:** E02, Z01. **Requirements:** RQ05, RQ17, RQ18, RQ27.

**Files:**

- modify: `apps/cepaf_gleam/native/c3i_nif/src/lib.rs`
- modify: `apps/cepaf_gleam/src/c3i_nif.erl`
- modify: `apps/cepaf_gleam/src/indrajaal_native_zenoh.erl`
- modify: `apps/cepaf_gleam/src/cepaf_gleam_ffi.erl`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/zenoh/client.gleam`
- create: `apps/cepaf_gleam/test/zenoh_native_abi_test.gleam`

**Execution steps:**

- [ ] Step 1: Generate and cross-check module/function/arity/result mappings for the actual selected native library; test loading through Gleam and any required Elixir facade.
- [ ] Step 2: Remove dummy open/put, unloaded-get empty success, hardcoded external .so paths and substring-based success/error inference; produce typed failures with bounded diagnostics.
- [ ] Step 3: Add positive native-load control and missing/wrong ABI/library/symbol/result-shape cases. Stage source adaptation only after E05 provenance and quiescence requirements hold.

**Executable acceptance fixture:**

```json
{
  "id": "Z02-regression",
  "given": {
    "library": "missing",
    "operation": "get",
    "payload": "a legitimate string containing error"
  },
  "when": [ { "op": "zenoh.native_load" } ],
  "expect": {
    "status": "Unavailable",
    "empty_success": false,
    "string_substring_error_classification": false,
    "phantom_session": false
  }
}
```

**Acceptance gate:** Native absence is always unavailable; actual symbols load at the locked candidate; no wrapper-shaped test can pass without the native operation.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task Z02
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## Z03: Implement supervised bounded session resources and ownership

**Workstream:** Z. **Priority:** P0. **Dependencies:** M05, Z02. **Requirements:** RQ10, RQ15, RQ18, RQ27.

**Files:**

- modify: `apps/cepaf_gleam/native/c3i_nif/src/zenoh_nif.rs`
- create: `apps/cepaf_gleam/native/c3i_nif/src/zenoh_session.rs`
- create: `apps/cepaf_gleam/src/cepaf_gleam/zenoh/session.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/moz/client.gleam`
- create: `apps/cepaf_gleam/test/zenoh_session_lifecycle_test.gleam`

**Execution steps:**

- [ ] Step 1: Replace singleton replacement/global-lock behavior with owned resource sessions, explicit generation/closed state and monitored BEAM ownership; close remains effective while aliases exist.
- [ ] Step 2: Move network waits into cancellable asynchronous native tasks or an isolated supervised transport host using the same NIF; keep scheduler-facing work/allocations bounded and do not hold global locks across awaits.
- [ ] Step 3: Implement readiness, real state, backoff, endpoint validation, drain/close/reopen, owner death and task cleanup; measure normal/dirty scheduler impact under failure.

**Executable acceptance fixture:**

```json
{
  "id": "Z03-regression",
  "given": {
    "sessions": 2,
    "retain_alias": true,
    "actions": [
      "open", "close", "put_via_old_alias", "reopen", "owner_die"
    ],
    "unreachable_endpoint": true
  },
  "when": [ { "op": "zenoh.session_lifecycle" } ],
  "expect": {
    "old_alias_result": "Closed",
    "reopen_generation_changed": true,
    "other_session_unaffected": true,
    "all_resources_released": true,
    "normal_scheduler_blocked": false
  }
}
```

**Acceptance gate:** No phantom connected status, stale resource use or leaked tasks; finite deadlines and close/reopen work with retained aliases and concurrent sessions.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task Z03
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## Z04: Complete binary data, key expressions, selectors and configuration

**Workstream:** Z. **Priority:** P1. **Dependencies:** M04, Z03. **Requirements:** RQ09, RQ18, RQ21, RQ22.

**Files:**

- create: `apps/cepaf_gleam/native/c3i_nif/src/zenoh_codec.rs`
- create: `apps/cepaf_gleam/src/cepaf_gleam/zenoh/types.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/zenoh/config.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/zenoh/key_expr.gleam`
- create: `apps/cepaf_gleam/test/zenoh_codec_key_test.gleam`

**Execution steps:**

- [ ] Step 1: Expose every selected-version sample field and all configuration options through typed validated schemas; preserve error reply, source metadata, timestamps and encoding without inventing identity from congestion status.
- [ ] Step 2: Support binary payloads and explicit bounds for bytes, attachments, keys, batches and replies; validate concrete versus expression/selector semantics using upstream and independent finite-language vectors.
- [ ] Step 3: Use structured serialization for spans/envelopes instead of string interpolation; reject invalid config rather than silently selecting defaults and retain exact option diagnostics.

**Executable acceptance fixture:**

```json
{
  "id": "Z04-regression",
  "given": {
    "payload_bytes": [ 0, 255, 34, 10, 240, 159, 140, 141 ],
    "kind": "Delete",
    "attachment": [ 0, 1 ],
    "invalid_config": "not-json",
    "key": "site/**",
    "operation": "concrete_publish"
  },
  "when": [ { "op": "zenoh.codec_roundtrip" } ],
  "expect": {
    "bytes_preserved": true,
    "kind_preserved": true,
    "attachment_preserved": true,
    "invalid_config_rejected": true,
    "wildcard_publication_rejected": true
  }
}
```

**Acceptance gate:** All admitted codec/config/key rows round-trip or reject correctly; binary/NUL/Unicode/error/delete semantics survive real transport.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task Z04
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## Z05: Complete publishers, real Delete and owned subscriptions

**Workstream:** Z. **Priority:** P1. **Dependencies:** M03, Z04. **Requirements:** RQ18, RQ19, RQ20, RQ34.

**Files:**

- create: `apps/cepaf_gleam/native/c3i_nif/src/zenoh_pubsub.rs`
- create: `apps/cepaf_gleam/src/cepaf_gleam/zenoh/pubsub.gleam`
- create: `apps/cepaf_gleam/test/zenoh_pubsub_runtime_test.gleam`

**Execution steps:**

- [ ] Step 1: Implement direct put/delete, declared publishers, every publication builder option, declare/undeclare and per-item batch outcomes; do not claim atomic batches unless separately implemented.
- [ ] Step 2: Deliver callbacks to monitored subjects/PIDs, signal declaration readiness/errors, bound queue count and bytes, implement pinned FIFO/ring/background/poll semantics and cleanup on owner death.
- [ ] Step 3: Audit per-item authorization and cancellation races. Independent subscribers must observe exact payload/kind/metadata; empty Put must never stand in for Delete.

**Executable acceptance fixture:**

```json
{
  "id": "Z05-regression",
  "given": {
    "key": "uos/test/delete",
    "payload_bytes": [],
    "action": "delete",
    "receiver": "separate_process",
    "owner_dies_after_subscribe": true,
    "requested_poll_capacity": 1000000000
  },
  "when": [ { "op": "zenoh.pubsub" } ],
  "expect": {
    "received_kind": "Delete",
    "empty_put_not_accepted": true,
    "owner_cleanup": true,
    "oversize_poll_rejected": true,
    "authorization_checked": true
  }
}
```

**Acceptance gate:** Every publication/subscription API row executes; ignored callbacks, readiness failures, empty-delete substitution and oversized allocation mutants fail.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task Z05
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## Z06: Complete queries, queryables and all reply semantics

**Workstream:** Z. **Priority:** P1. **Dependencies:** Z05. **Requirements:** RQ18, RQ19, RQ21.

**Files:**

- create: `apps/cepaf_gleam/native/c3i_nif/src/zenoh_query.rs`
- create: `apps/cepaf_gleam/src/cepaf_gleam/zenoh/query.gleam`
- create: `apps/cepaf_gleam/test/zenoh_query_runtime_test.gleam`

**Execution steps:**

- [ ] Step 1: Implement get and declared queriers/queryables, completeness, selectors/parameters/payload/encoding/attachments, targets, consolidation, reply-key rules and all reply variants from the pin.
- [ ] Step 2: Use bounded streaming replies and explicit end/error/timeout/cancel events; validate query ownership and reject replies after cancellation or stale correlation.
- [ ] Step 3: Test zero/one/many responders, disjoint reply keys, local/remote routing, queryable death, malformed requests, deadline exhaustion and matching listeners.

**Executable acceptance fixture:**

```json
{
  "id": "Z06-regression",
  "given": {
    "queryables": [
      { "reply": "Put", "key": "a" },
      { "reply": "Delete", "key": "b" },
      { "reply": "Error", "reason": "denied" }
    ],
    "target": "all",
    "consolidation": "none",
    "deadline_ms": 1000,
    "cancel_after_reply": 2
  },
  "when": [ { "op": "zenoh.query" } ],
  "expect": {
    "error_reply_not_dropped": true,
    "delete_reply_distinct": true,
    "cancellation_observed": true,
    "late_replies_rejected": true,
    "reply_memory_bounded": true
  }
}
```

**Acceptance gate:** All query/reply rows execute against real independent queryables; application errors are not swallowed as empty success; cancellation releases native and BEAM resources.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task Z06
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## Z07: Implement scouting, matching and liveliness

**Workstream:** Z. **Priority:** P1. **Dependencies:** Z05, Z06. **Requirements:** RQ15, RQ18, RQ21.

**Files:**

- create: `apps/cepaf_gleam/native/c3i_nif/src/zenoh_discovery.rs`
- create: `apps/cepaf_gleam/src/cepaf_gleam/zenoh/discovery.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/zenoh/liveliness.gleam`
- create: `apps/cepaf_gleam/test/zenoh_discovery_liveness_test.gleam`

**Execution steps:**

- [ ] Step 1: Expose scout start/stop and peer/router identities; distinguish physical presence, session status and application readiness.
- [ ] Step 2: Implement publisher/querier matching status/listeners and liveliness token/drop/get/subscriber/history APIs with bounded ownership.
- [ ] Step 3: Test late join, no matches, multiple matches, owner/router death, partition/rejoin and cancellation with actual network observations.

**Executable acceptance fixture:**

```json
{
  "id": "Z07-regression",
  "given": {
    "token": "uos/test/actor/a",
    "listener_join": "late",
    "owner_action": "crash",
    "partition_then_rejoin": true
  },
  "when": [ { "op": "zenoh.liveliness" } ],
  "expect": {
    "history_observed": true,
    "disappearance_observed": true,
    "reappearance_observed": true,
    "token_does_not_grant_write_authority": true
  }
}
```

**Acceptance gate:** Every discovery/matching/liveliness row behaves according to the pin; no health/liveliness signal can authorize effects.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task Z07
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## Z08: Complete QoS, locality, congestion and scheduling profiles

**Workstream:** Z. **Priority:** P1. **Dependencies:** Z06, Z07. **Requirements:** RQ15, RQ18, RQ26.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/zenoh/qos.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/ha/qos_policy.gleam`
- create: `apps/cepaf_gleam/native/c3i_nif/src/zenoh_qos.rs`
- create: `apps/cepaf_gleam/test/zenoh_qos_load_test.gleam`

**Execution steps:**

- [ ] Step 1: Map every pinned priority/reliability/congestion/express/batching/locality variant and its stability gate; define profile contracts per message class.
- [ ] Step 2: Measure overload with open-loop producers, separate declared queue bounds from BEAM mailbox growth, and implement admission credits where required.
- [ ] Step 3: Test latency/throughput tradeoffs and origin/destination constraints without inventing global FIFO or exactly-once guarantees.

**Executable acceptance fixture:**

```json
{
  "id": "Z08-regression",
  "given": {
    "profile": "telemetry_drop",
    "offered_rate": "above_capacity",
    "command_profile": "authenticated_bounded",
    "mailbox_budget": 100
  },
  "when": [ { "op": "zenoh.qos" } ],
  "expect": {
    "telemetry_loss_reported": true,
    "command_success_not_fabricated": true,
    "mailbox_within_budget": true,
    "scheduler_responsive": true
  }
}
```

**Acceptance gate:** Each supported QoS profile has a measured contract; lost telemetry is counted, commands retain explicit failure/acknowledgment semantics.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task Z08
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## Z09: Complete advanced extensions and shared memory

**Workstream:** Z. **Priority:** P1. **Dependencies:** M05, Z08. **Requirements:** RQ18, RQ21, RQ22.

**Files:**

- create: `apps/cepaf_gleam/native/c3i_nif/src/zenoh_advanced.rs`
- create: `apps/cepaf_gleam/native/c3i_nif/src/zenoh_shm.rs`
- create: `apps/cepaf_gleam/src/cepaf_gleam/zenoh/advanced.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/zenoh/shared_memory.gleam`
- create: `apps/cepaf_gleam/test/zenoh_advanced_shm_test.gleam`

**Execution steps:**

- [ ] Step 1: Implement every pinned zenoh-ext serialization, advanced publish/subscribe, history/cache/recovery/miss/listener/group operation; map deprecated APIs to documented replacements while preserving compatibility obligations.
- [ ] Step 2: Complete shared-memory buffer/provider/client/lifetime/reclamation/fallback APIs as explicit supported profiles with byte budgets and platform checks.
- [ ] Step 3: Run stateful loss/recovery properties, isolated sanitizer/fault tests and actual copy/allocation measurements; missing hardware/profile execution remains UNRUN.

**Executable acceptance fixture:**

```json
{
  "id": "Z09-regression",
  "given": {
    "history_capacity": 3,
    "published_sequences": [ 1, 2, 3, 4 ],
    "subscriber_last": 1,
    "drop_sequence": 3,
    "buffer_owner": "terminated"
  },
  "when": [ { "op": "zenoh.recover" } ],
  "expect": {
    "recovery_window_enforced": true,
    "missing_sample_reported": true,
    "duplicates_not_committed_twice": true,
    "buffer_reclaimed": true,
    "no_use_after_free": true
  }
}
```

**Acceptance gate:** All extension and shared-memory rows have semantic/lifetime evidence; zero-copy is measured rather than asserted; unavailable profiles block full execution credit.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task Z09
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## Z10: Complete transports, authentication and managed router/storage/plugins

**Workstream:** Z. **Priority:** P1. **Dependencies:** E05, Z09. **Requirements:** RQ16, RQ18, RQ27, RQ34.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/zenoh/ecosystem.gleam`
- create: `tests/zenoh/profiles/transport_matrix.json`
- create: `tests/zenoh/ecosystem_probe.ml`
- create: `apps/cepaf_gleam/test/zenoh_ecosystem_contract_test.gleam`

**Execution steps:**

- [ ] Step 1: Provide versioned profiles for TCP/UDP/multicast/TLS/QUIC/datagrams/WebSocket/Unix socket/pipe/serial/vsock plus compression/multilink where offered by the selected release.
- [ ] Step 2: Implement typed management/verification for router topology/admin/statistics, storage manager/backends/replication and required bridges/plugins as supervised services; no unrestricted dynamic plugin loading from user input.
- [ ] Step 3: Exercise public-key/user-password/TLS identity and ACLs with isolated fixture credentials; verify restart durability, peer/version compatibility, invalid identities and missing profile dependencies.

**Executable acceptance fixture:**

```json
{
  "id": "Z10-regression",
  "given": {
    "transport_profiles": "all_pinned_supported_targets",
    "denied_key": "uos/control/forbidden",
    "storage_restart": true,
    "missing_target": "serial_fixture"
  },
  "when": [ { "op": "zenoh.ecosystem" } ],
  "expect": {
    "denied_effects": 0,
    "persistence_observed": true,
    "missing_target_state": "UNRUN",
    "all_profiles_claimed_pass": false
  }
}
```

**Acceptance gate:** Every upstream transport/config/ecosystem row is accounted for and tested on declared targets; absent profiles remain nonpassing; original secrets/binaries are not imported.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task Z10
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## Z11: Benchmark corrected candidates and select the measured baseline

**Workstream:** Z. **Priority:** P1. **Dependencies:** E03, Z10. **Requirements:** RQ17, RQ18, RQ26, RQ33.

**Files:**

- create: `tests/zenoh/benchmark.ml`
- create: `apps/cepaf_gleam/native/c3i_nif/benches/transport_boundary.rs`
- create: `tests/zenoh/benchmark_analysis.ml`

**Execution steps:**

- [ ] Step 1: Compare as-found and common-version builds separately under equal hardware/build/OTP/router/topology/payload/QoS/auth settings with raw samples, warm-up and independent repeats.
- [ ] Step 2: Measure boundary cost, real receive, query round trip and durable command acknowledgment separately; report supported tail quantiles, confidence intervals, throughput/goodput, loss, CPU/RSS/copies, reductions and scheduler/mailbox delay.
- [ ] Step 3: Exercise size/concurrency/fan-out/key/batch/shared-memory/overload/reconnect matrices. Enforce correctness/safety first, then select the coverage/performance Pareto frontier and document the deployment choice.

**Executable acceptance fixture:**

```json
{
  "id": "Z11-regression",
  "given": {
    "implementations": [
      "adapted_c3i", "adapted_indrajaal", "adapted_sutra",
      "pinned_rust_control"
    ],
    "same_qos": true,
    "same_auth": true,
    "native_receiver_missing": true
  },
  "when": [ { "op": "zenoh.benchmark" } ],
  "expect": {
    "ranking_available": false,
    "status": "ERROR",
    "mock_or_pubsub_results_excluded": true
  }
}
```

**Acceptance gate:** No winner without reproducible independent native receipts; mock/PubSub/serialization-only timings are labeled controls, not native throughput.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task Z11
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## Z12: Migrate and verify every UOS application communication edge

**Workstream:** Z. **Priority:** P1. **Dependencies:** A05, E08, M03, M04, Z11. **Requirements:** RQ15, RQ16, RQ18, RQ34.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/zenoh/domain_router.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/moz/client.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/agui/zenoh_bus.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/bridge/zenoh_mcp.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/planning/zenoh_adapter.gleam`
- create: `apps/cepaf_gleam/test/zenoh_domain_edges_test.gleam`

**Execution steps:**

- [ ] Step 1: Enumerate every sender/receiver/schema/authority/deadline/QoS/current transport/key expression and migration status across apps, engines, services, intelligence, knowledge, agents and telemetry.
- [ ] Step 2: Adapt each domain edge through the admitted C3I-derived facade; browser/API/HTTP/SSE/WebSocket remain explicitly modeled gateways. Document OTP bootstrap/supervision and pure in-process mechanics separately.
- [ ] Step 3: Observe send/receive/apply/commit and full Trace13 where required. Detect hidden alternate domain buses by static call graph plus runtime instrumentation; retain unexplained exceptions as open gaps.

**Executable acceptance fixture:**

```json
{
  "id": "Z12-regression",
  "given": {
    "edges": [
      { "id": "wiki-query", "transport": "zenoh", "observed": true },
      {
        "id": "agent-command",
        "transport": "hidden_pubsub",
        "observed": true
      }
    ],
    "browser_gateway": "http"
  },
  "when": [ { "op": "zenoh.edge_audit" } ],
  "expect": {
    "complete": false,
    "unmigrated_edges": [ "agent-command" ],
    "http_gateway_accounted": true
  }
}
```

**Acceptance gate:** All required domain edges are mapped and observed through Zenoh; no phantom success, unobserved shortcut or unexplained alternative domain bus remains.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task Z12
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## W01: Close route, page, component and UI-state manifests

**Workstream:** W. **Priority:** P0. **Dependencies:** E04, E08. **Requirements:** RQ23, RQ25, RQ35.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/knowledge/routes.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/knowledge/components.gleam`
- create: `tools/verification/route_manifest.ml`
- modify: `apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam`
- create: `apps/cepaf_gleam/test/route_manifest_test.gleam`

**Execution steps:**

- [ ] Step 1: Extract routes from router AST/definitions and reconcile actual DOM/nav/MOCs, dynamic document IDs, query states, redirects, fragments and authorization variants.
- [ ] Step 2: Include every known baseline route and ten tensor-era routes plus new FPP/agent/evolution screens; never freeze the denominator at the earlier 46-page baseline.
- [ ] Step 3: Assign stable page/component/instance/state IDs and purpose/action/oracle/side-effect contracts; define canonical aliases/redirects and preserve unresolved crawl/auth frontiers.

**Executable acceptance fixture:**

```json
{
  "id": "W01-regression",
  "given": {
    "router_routes": [ "/wiki", "/zk", "/ux-audit" ],
    "document_links": [ "/ux-auditor" ],
    "crawl_cap": 2,
    "dynamic_document_instances": 20
  },
  "when": [ { "op": "web.manifest" } ],
  "expect": {
    "mismatch": [ "/ux-auditor" ],
    "frontier_remaining": true,
    "whole_site_complete": false,
    "components_require_per_page_instances": true
  }
}
```

**Acceptance gate:** Every reachable or specified route is accounted for; crawl caps and unvisited dynamic instances are visible; /ux-audit versus /ux-auditor is resolved deliberately.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task W01
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## W02: Make Markdown/HTML rendering and source display safe and faithful

**Workstream:** W. **Priority:** P0. **Dependencies:** E06, W01. **Requirements:** RQ19, RQ21, RQ22, RQ24, RQ27.

**Files:**

- modify: `apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam`
- modify: `apps/indrajaal_gleam_web/test/document_render_contract_test.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/markdown.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/knowledge/document_ast.gleam`
- create: `apps/cepaf_gleam/test/document_security_test.gleam`

**Execution steps:**

- [ ] Step 1: Reconcile the earlier newline/fixture repair with the current renderer; preserve its passing regressions while replacing unsafe HTML/protocol handling.
- [ ] Step 2: Parse the declared dialect into a typed AST, apply reviewed sanitization/CSP rules, escape by context, bound nesting/input and render through safe Gleam HTML primitives.
- [ ] Step 3: Test CommonMark/approved wiki extensions, nested lists/code/tables, Unicode/quotes/newlines, raw/rendered round trips, XSS payloads, malformed AST and source toggle focus/selection.

**Executable acceptance fixture:**

```json
{
  "id": "W02-regression",
  "given": {
    "markdown": "[run](javascript:alert(1))\\n\\n<script>window.__uos_probe=1</script>",
    "mode": "rendered_then_raw"
  },
  "when": [ { "op": "web.render" } ],
  "expect": {
    "script_executed": false,
    "unsafe_protocol_active": false,
    "raw_source_preserved": true,
    "newline_semantics_preserved": true
  }
}
```

**Acceptance gate:** Admitted dialect fixtures render faithfully; unsafe markup cannot execute; raw source is exact and safely displayed; prior renderer regressions remain covered.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task W02
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## W03: Implement semantic links, anchors, redirects and navigation algebra

**Workstream:** W. **Priority:** P0. **Dependencies:** M06, W01. **Requirements:** RQ12, RQ19, RQ21, RQ25.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/knowledge/links.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/knowledge/navigation.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/verification/graph_verification.gleam`
- create: `apps/cepaf_gleam/test/navigation_laws_test.gleam`
- create: `tests/web_quality/link_probe.ml`

**Execution steps:**

- [ ] Step 1: Resolve relative/absolute Tailnet links, fragments, encoding, transclusions, downloads, redirects and query parameters against a typed route registry; detect loops and fallback pages.
- [ ] Step 2: Implement navigation history/context/focus restoration and graph algorithms for reachability, SCCs, broken backlinks, orphan detection and shortest useful paths with independent oracles.
- [ ] Step 3: Check external sources with bounded concurrency/rate limits and GET semantics where HEAD is misleading; separate temporary network failure, auth requirements and confirmed broken targets.

**Executable acceptance fixture:**

```json
{
  "id": "W03-regression",
  "given": {
    "link": "/docs/note.md#missing",
    "response_status": 200,
    "rendered_title": "Fallback home",
    "anchors": [ "intro" ]
  },
  "when": [ { "op": "web.resolve_link" } ],
  "expect": {
    "valid_target": false,
    "reason_codes": [ "semantic_destination_mismatch", "missing_anchor" ],
    "http_200_credit": false
  }
}
```

**Acceptance gate:** Every required link reaches its intended semantic destination and anchor; legitimate graph cycles remain supported; Back/Forward laws hold under declared history assumptions.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task W03
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## W04: Complete the uniform shell, navigation and truthful checklist

**Workstream:** W. **Priority:** P1. **Dependencies:** E03, W02, W03. **Requirements:** RQ23, RQ25, RQ26, RQ31, RQ35.

**Files:**

- modify: `apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/site_shell.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/verification_checklist.gleam`
- create: `apps/cepaf_gleam/test/site_shell_contract_test.gleam`

**Execution steps:**

- [ ] Step 1: Implement shared grouped sidebar, top status/FQDN/copy control, breadcrumbs, rendered/raw toggle, Prev/Next and footer with route-appropriate semantics.
- [ ] Step 2: Render all eighteen checkpoints in five expandable domains using the evidence ledger; derive state and freshness from receipts and show missing/failing checks.
- [ ] Step 3: Exercise shell integration on every containing page, including small viewports/zoom, long names, keyboard/touch, copy feedback, navigation restoration and error states.

**Executable acceptance fixture:**

```json
{
  "id": "W04-regression",
  "given": {
    "route": "/wiki",
    "viewport": [ 390, 844 ],
    "keyboard_only": true,
    "runtime_receipt": "missing",
    "formal_receipt": "passed"
  },
  "when": [ { "op": "web.shell" } ],
  "expect": {
    "sidebar_groups": 3,
    "checkpoint_count": 18,
    "domain_count": 5,
    "overall_admitted": false,
    "focus_visible": true,
    "horizontal_overflow": false
  }
}
```

**Acceptance gate:** Every screen/document view has the complete shell/checklist with actual state; shared component unit tests do not replace each-page integration evidence.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task W04
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## W05: Complete wiki parsing, transclusion and content lifecycle

**Workstream:** W. **Priority:** P1. **Dependencies:** E07, M03, W02, W03. **Requirements:** RQ03, RQ19, RQ21, RQ25, RQ27.

**Files:**

- modify: `apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/wiki_transclusion_engine.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/knowledge/wiki.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/knowledge/transclusion.gleam`
- create: `apps/cepaf_gleam/test/wiki_semantics_test.gleam`

**Execution steps:**

- [ ] Step 1: Implement versioned document IDs/frontmatter, AST parsing, wiki/ZK links, transclusion expansion, source provenance, invalidation and safe rendering against original Hermes oracle fixtures.
- [ ] Step 2: Bound cycles/depth/size, define missing/forbidden targets and partial content errors, and preserve origin/source spans through nested expansion.
- [ ] Step 3: Route content edits through authorized versioned transactions with conflict/rollback behavior; test stale edits, denied transclusions and index invalidation.

**Executable acceptance fixture:**

```json
{
  "id": "W05-regression",
  "given": {
    "documents": { "a": "[[wiki:b]]", "b": "[[wiki:a]]" },
    "start": "a",
    "depth_limit": 8
  },
  "when": [ { "op": "wiki.expand" } ],
  "expect": {
    "result": "TransclusionCycle",
    "cycle": [ "a", "b", "a" ],
    "bounded": true,
    "source_documents_unchanged": true
  }
}
```

**Acceptance gate:** All selected wiki cases have semantic Gleam coverage; transclusion cannot loop, leak forbidden content or lose provenance; unauthorized edits produce zero effects.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task W05
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## W06: Integrate ZK, MOCs, living ontology and graph integrity

**Workstream:** W. **Priority:** P1. **Dependencies:** M05, M06, M07, W05. **Requirements:** RQ11, RQ12, RQ19, RQ25, RQ32.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/knowledge/zettelkasten.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/knowledge/ontology.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/knowledge/corpus.gleam`
- create: `apps/cepaf_gleam/test/knowledge_graph_integrity_test.gleam`

**Execution steps:**

- [ ] Step 1: Unify Hermes wiki AST, ZigVM ZK/MOCs and C3I living ontology as typed, bidirectionally linked projections with stable identities and immutable source bindings.
- [ ] Step 2: Implement backlink/rename/alias/orphan/duplicate checks, schema/shape constraints and explicit timestamp/fractal-tag rules; archive revisions rather than rewriting external originals.
- [ ] Step 3: Test index rebuild equivalence, incremental invalidation, conflicting edits, missing nodes, schema migration and observer-versus-writer separation.

**Executable acceptance fixture:**

```json
{
  "id": "W06-regression",
  "given": {
    "notes": [
      { "id": "n1", "links": [ "n2" ] }, { "id": "n2", "links": [] }
    ],
    "rename": { "from": "n2", "to": "n3" },
    "source_snapshot": "immutable"
  },
  "when": [ { "op": "knowledge.index" } ],
  "expect": {
    "backlinks_consistent": true,
    "redirect_or_reference_update_recorded": true,
    "provenance_retained": true,
    "original_source_changed": false
  }
}
```

**Acceptance gate:** Knowledge graph updates preserve stable identity/provenance and declared invariants; all MOC and ontology references resolve or show named gaps.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task W06
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## W07: Implement measurable search, discovery and information architecture

**Workstream:** W. **Priority:** P1. **Dependencies:** M06, W06. **Requirements:** RQ12, RQ19, RQ21, RQ26.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/knowledge/search.gleam`
- create: `apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/knowledge_search.gleam`
- create: `apps/cepaf_gleam/test/knowledge_search_test.gleam`

**Execution steps:**

- [ ] Step 1: Create a judged corpus and task-based information architecture; implement deterministic indexing/tokenization/filtering/ranking with explicit tie-breakers and independent small reference results.
- [ ] Step 2: Provide context/backlinks, facets, empty/loading/error states and keyboard navigation; protect authorization through both search results and snippets.
- [ ] Step 3: Measure retrieval quality and find/open/return workflows; document algorithm complexity and justify optional vector/similarity methods with actual corpus evidence.

**Executable acceptance fixture:**

```json
{
  "id": "W07-regression",
  "given": {
    "queries": [ "typed navigation", "" ],
    "corpus": "judged_small_corpus",
    "filters": { "tag": "wiki" },
    "forbidden_document": "secret-note"
  },
  "when": [ { "op": "knowledge.search" } ],
  "expect": {
    "forbidden_results": 0,
    "empty_state_has_next_action": true,
    "filter_state_survives_back": true,
    "ranking_compared_to_judgments": true
  }
}
```

**Acceptance gate:** Search correctness, access filtering and context preservation pass; relevance/UX claims have task/judgment denominators rather than arbitrary quality scores.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task W07
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## W08: Connect all dashboards to actual system observations

**Workstream:** W. **Priority:** P1. **Dependencies:** A06, M07, W04, Z12. **Requirements:** RQ11, RQ23, RQ26, RQ33, RQ34, RQ35.

**Files:**

- modify: `apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/fpp_topology_view.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/fpp_atlas_view.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/fpp_agent_view.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/zenoh_mesh.gleam`
- modify: `apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam`
- create: `apps/cepaf_gleam/test/dashboard_observation_test.gleam`

**Execution steps:**

- [ ] Step 1: Connect existing tensor/SRE/UX/KM/FPP/agent/Zenoh/brain pages to live typed projections and ledger evidence; remove generated scores used as proof of operational health.
- [ ] Step 2: Render loading, partial, stale, denied, disconnected and recovery states consistently across web/TUI/API surfaces with preserved correlation.
- [ ] Step 3: Bind every displayed action to an intent/authorization/model/test contract and update page/component manifests whenever a route/control is added.

**Executable acceptance fixture:**

```json
{
  "id": "W08-regression",
  "given": {
    "page": "/tensor-atlas",
    "runtime_state": "disconnected",
    "proof_receipt": "stale",
    "metric_samples": []
  },
  "when": [ { "op": "web.dashboard" } ],
  "expect": {
    "connected_badge": false,
    "admitted_badge": false,
    "metric_value": "unavailable",
    "recovery_action_visible": true
  }
}
```

**Acceptance gate:** No dashboard emits green operational credit from a constant/model-only result; every action has real observable behavior and appropriate failure presentation.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task W08
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## W09: Complete responsive, accessible design and task-focused UX/CX

**Workstream:** W. **Priority:** P1. **Dependencies:** W04, W05, W07, W08. **Requirements:** RQ23, RQ24, RQ26.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/design_tokens.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/site_shell.gleam`
- create: `tests/web_quality/experience_tasks.json`
- create: `apps/cepaf_gleam/test/ui_state_contract_test.gleam`

**Execution steps:**

- [ ] Step 1: Define shared typography/spacing/color/state/motion tokens with semantic component rules and clear information hierarchy; implement long/localized text and mobile/zoom reflow.
- [ ] Step 2: Specify UX/CX goals/signals/measures for supported journeys, failure understanding and recovery, with real participant/task denominators where human feedback is required.
- [ ] Step 3: Run visual/accessibility/task reviews and repair observable issues; automated scores, synthetic users or screenshot equality alone cannot certify subjective experience.

**Executable acceptance fixture:**

```json
{
  "id": "W09-regression",
  "given": {
    "journey": "find-note-follow-backlink-inspect-source-return",
    "viewport": [ 320, 640 ],
    "zoom_percent": 200,
    "keyboard_only": true,
    "reduced_motion": true,
    "theme": "dark"
  },
  "when": [ { "op": "web.experience" } ],
  "expect": {
    "task_completed": true,
    "focus_restored": true,
    "content_loss": false,
    "clipping": false,
    "error_recovery_discoverable": true
  }
}
```

**Acceptance gate:** Required layouts, input methods and states meet the documented criteria; measured task evidence supports experience claims; unavailable human/assistive feedback remains explicit.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task W09
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## V01: Create a real browser harness with semantic actions and durable artifacts

**Workstream:** V. **Priority:** P0. **Dependencies:** E02, W01, W02. **Requirements:** RQ23, RQ24, RQ35.

**Files:**

- create: `tests/web_quality/browser_harness.ml`
- create: `tests/web_quality/artifact_store.ml`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/verification/browser_emulation_bridge.gleam`
- create: `tests/web_quality/browser_harness_test.ml`

**Execution steps:**

- [ ] Step 1: Adapt the retained OCaml browser controller into a reproducible bounded harness with semantic locators, actual pointer/keyboard/touch actions, state restoration, console/network logs and build identification.
- [ ] Step 2: Provision pinned Chromium/Firefox/WebKit runners where required; separate browser absence from test failure and remove browser-emulation shortcuts from operational gates.
- [ ] Step 3: Store screenshot/DOM/AX/AST/video/trace artifacts with task/page/component/state/cycle/viewport/browser/candidate/time/digest metadata in a durable verified store; redact secrets and test retention/retrieval.

**Executable acceptance fixture:**

```json
{
  "id": "V01-regression",
  "given": {
    "browser_executable": "missing",
    "page": "/wiki",
    "requested_artifacts": [ "png", "dom", "ax", "ast", "video", "trace" ],
    "emulation_result": true
  },
  "when": [ { "op": "browser.probe" } ],
  "expect": {
    "status": "UNRUN",
    "semantic_cycles_passed": 0,
    "emulation_credit": false,
    "missing_browser_reported": true
  }
}
```

**Acceptance gate:** An actual browser action produces matching semantic/network observations and retrievable media; missing browser or emulation cannot produce a pass.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task V01
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## V02: Run four recursive semantic cycles for every page and component

**Workstream:** V. **Priority:** P1. **Dependencies:** A10, V01, W09. **Requirements:** RQ20, RQ23, RQ24, RQ25, RQ35.

**Files:**

- create: `tests/web_quality/cycle_controller.ml`
- create: `tests/web_quality/cycle_contract.ml`
- create: `apps/cepaf_gleam/src/cepaf_gleam/verification/browser_cycle_ledger.gleam`
- create: `apps/cepaf_gleam/test/browser_cycle_ledger_test.gleam`

**Execution steps:**

- [ ] Step 1: For each page and component instance run C1 semantics/all links, C2 interactions/BDD/focus, C3 responsive/zoom/accessibility/visual/failure, C4 regression/independent oracle/recovery.
- [ ] Step 2: Each cycle observes, derives expected behavior, acts, compares, records defects, applies a TDD repair where needed, rebuilds and reverifies affected descendants/siblings/parents; clean cycles record that no repair was necessary.
- [ ] Step 3: Invalidate dependent receipts after changes and repeat affected final-candidate cycles. Four viewports/screenshots/retries are not four distinct semantic cycles; keep running until the complete manifest is green.

**Executable acceptance fixture:**

```json
{
  "id": "V02-regression",
  "given": {
    "page": "/wiki",
    "component": "source-toggle",
    "cycles": [
      { "id": 1, "semantic": true },
      { "id": 2, "semantic": true },
      { "id": 3, "semantic": true },
      { "id": 4, "semantic": false }
    ],
    "candidate": "current"
  },
  "when": [ { "op": "browser.cycle_admission" } ],
  "expect": {
    "admitted": false,
    "semantic_cycles": 3,
    "required_cycles": 4,
    "reason": "fourth_cycle_has_no_semantic_evidence"
  }
}
```

**Acceptance gate:** Every required final-candidate page and component has at least four complete distinct passing semantic cycles, all actions/states covered and no unexplained route/frontier gap.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task V02
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## V03: Verify accessibility, appearance and interaction across targets

**Workstream:** V. **Priority:** P1. **Dependencies:** V01, W09. **Requirements:** RQ23, RQ24, RQ26.

**Files:**

- create: `tests/web_quality/accessibility.ml`
- create: `tests/web_quality/visual_review.ml`
- create: `tests/web_quality/accessibility_cases.json`

**Execution steps:**

- [ ] Step 1: Run pinned axe/WCAG/ARIA checks through the browser plus keyboard focus/order/restoration, screen-reader workflow, contrast by state, labels/errors and touch targets.
- [ ] Step 2: Use desktop/tablet/mobile, 200/400 percent zoom, reduced motion, themes and long/localized content; inspect screenshots for hierarchy/spacing/alignment/clipping.
- [ ] Step 3: Review visual differences with tolerances tied to stable rendering conditions; retain decisions and human/assistive-technology observations rather than treating pixels as functional proof.

**Executable acceptance fixture:**

```json
{
  "id": "V03-regression",
  "given": {
    "control": "source-toggle",
    "accessible_name": "",
    "keyboard_activation": false,
    "visual_snapshot_equal": true
  },
  "when": [ { "op": "browser.accessibility" } ],
  "expect": {
    "passed": false,
    "violations": [ "missing_accessible_name", "keyboard_inoperable" ],
    "visual_equality_overrides_semantics": false
  }
}
```

**Acceptance gate:** All specified target/state/accessibility checks pass; untested assistive/browser targets remain UNRUN and are not hidden in aggregate success.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task V03
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## V04: Add stateful property, metamorphic, differential and coverage-guided fuzz tests

**Workstream:** V. **Priority:** P1. **Dependencies:** A09, E07, M07, W07, Z10. **Requirements:** RQ21, RQ22, RQ27.

**Files:**

- create: `tests/property/run.ml`
- create: `tests/fuzz/run.ml`
- create: `tests/fuzz/corpus_manifest.json`
- create: `apps/cepaf_gleam/test/stateful_property_test.gleam`

**Execution steps:**

- [ ] Step 1: Build domain-valid generators/shrinkers for ASTs, graphs, routes, intent sequences, actor schedules, configs/keys/binary payloads, SysML/FPP models and knowledge edits.
- [ ] Step 2: Use metamorphic relations, independent OCaml/reference outputs and state-machine oracles. Record generator distributions, seeds, shrink lineage and expected-vs-observed semantic coverage.
- [ ] Step 3: Integrate genuine coverage feedback for suitable compiled parser/native targets with crash isolation and bounded resources; call random seed testing generated testing when coverage feedback is absent. Retain/minimize/replay every failure corpus.

**Executable acceptance fixture:**

```json
{
  "id": "V04-regression",
  "given": {
    "target": "markdown_and_key_codec",
    "seed": 3401,
    "mutation": "embedded_nul_and_invalid_utf8",
    "timeout_ms": 1000,
    "coverage_feedback": false
  },
  "when": [ { "op": "fuzz.campaign" } ],
  "expect": {
    "coverage_guided_claim": false,
    "seed_replayable": true,
    "failures_shrunk": true,
    "resource_bounds_enforced": true
  }
}
```

**Acceptance gate:** Named seeded counterexamples reproduce and shrink; fuzz campaigns have actual feedback/coverage evidence where claimed; failures cannot be converted into skips.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task V04
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## V05: Verify compiler boundaries, formal coverage and mutation sensitivity

**Workstream:** V. **Priority:** P1. **Dependencies:** A09, M08, W06, Z10. **Requirements:** RQ05, RQ06, RQ19, RQ22, RQ33.

**Files:**

- create: `tests/compiler/fixtures.gleam.txt`
- create: `tests/compiler/run.ml`
- create: `tests/mutation/run.ml`
- modify: `tools/web_quality_gate.ml`

**Execution steps:**

- [ ] Step 1: Build positive and negative fixtures for opaque construction, port/message mismatch, unsupported targets, FFI result shapes and generated code; verify nonzero compiler exit and diagnostic class, not a string anywhere in a log.
- [ ] Step 2: Link actual tool/source/query/candidate receipts to every atlas/conformance obligation; run bounded solver controls and reject holes, unsupported syntax and stale or incomplete model mappings.
- [ ] Step 3: Create targeted semantic mutants for original false-success patterns and critical safety laws; measure killed/surviving/equivalent/unrun denominators and investigate survivors.

**Executable acceptance fixture:**

```json
{
  "id": "V05-regression",
  "given": {
    "mutants": [
      "drop_trace_field", "bypass_authorization", "fake_browser_pass",
      "omit_sheaf_overlap", "swallow_query_error"
    ],
    "compiler_negative_exit": 0,
    "solver_control": "unsat"
  },
  "when": [ { "op": "verification.mutation" } ],
  "expect": {
    "admitted": false,
    "negative_compile_case_failed": true,
    "solver_vacuity_rejected": true,
    "all_required_mutants_must_be_killed": true
  }
}
```

**Acceptance gate:** Required bad programs fail for intended reasons, positive controls compile, all critical mutants are detected and every claimed mathematical result has fresh scoped evidence.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task V05
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## V06: Measure web, system, UX, DX and CX performance

**Workstream:** V. **Priority:** P1. **Dependencies:** H03, W09, Z11. **Requirements:** RQ17, RQ26, RQ33.

**Files:**

- create: `tests/performance/web_and_actor.ml`
- create: `tests/performance/experience_analysis.ml`
- create: `tests/performance/workload_contract.json`

**Execution steps:**

- [ ] Step 1: Define workload/goal/signal/metric contracts before measurement; set measured budgets using product requirements and observed baselines, recording review decisions and regressions.
- [ ] Step 2: Measure browser Core Web Vitals/lab responsiveness/resource weight, server/actor throughput and tail latency, retrieval quality, build/test/edit-feedback time and actionable diagnostics.
- [ ] Step 3: Run real representative user tasks and feedback where available; preserve attempt/participant/environment denominators, separate lab from field and avoid invented satisfaction or beauty scores.

**Executable acceptance fixture:**

```json
{
  "id": "V06-regression",
  "given": {
    "task": "find-note-and-return",
    "attempts": 10,
    "completed": 7,
    "lab_lcp_ms": 2400,
    "field_samples": 0,
    "dx_build_logs": "captured"
  },
  "when": [ { "op": "experience.measure" } ],
  "expect": {
    "task_success_rate": 0.7,
    "field_claim_available": false,
    "lab_and_field_separate": true,
    "failures_retained": 3
  }
}
```

**Acceptance gate:** Performance/experience claims reproduce from raw observations; field/human gaps stay explicit; optimizations preserve accessibility and correctness.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task V06
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## V07: Run full system BDD, recovery and ecological feedback verification

**Workstream:** V. **Priority:** P1. **Dependencies:** A10, V02, V03, V04, V05, V06. **Requirements:** RQ15, RQ19, RQ20, RQ23, RQ27, RQ34.

**Files:**

- create: `tests/system/ecology_bdd.ml`
- create: `tests/system/fault_scenarios.json`
- create: `apps/cepaf_gleam/test/system_recovery_contract_test.gleam`

**Execution steps:**

- [ ] Step 1: Run end-to-end read and authorized-write journeys with actual browser, policy, model, native Zenoh, actor, storage/evidence and UI feedback.
- [ ] Step 2: Inject isolated router/peer/worker failures, queue pressure, duplicate/out-of-order messages, schema mismatch, clock changes and crash-after-apply schedules; never perform destructive physical storage experiments.
- [ ] Step 3: Verify bounded recovery, idempotency/fencing, telemetry non-interference, dead-man freshness and OODA/controller decisions from measured windows; do not substitute a chosen negative Lyapunov constant for a stability observation.

**Executable acceptance fixture:**

```json
{
  "id": "V07-regression",
  "given": {
    "scenario": "crash_after_apply_before_ack",
    "message_id": "cmd-17",
    "retry": true,
    "router_partition": true,
    "observer_can_write": false
  },
  "when": [ { "op": "system.recover" } ],
  "expect": {
    "durable_effect_count": 1,
    "retry_receipt_correlated": true,
    "observer_writes": 0,
    "recovery_bounded": true,
    "ui_state_truthful": true
  }
}
```

**Acceptance gate:** All required complete workflows and failure schedules satisfy effect/trace/time/authority contracts and show correct recoverable UI behavior.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task V07
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## H01: Repair and admit relevant skills, rules and diagram generation

**Workstream:** H. **Priority:** P0. **Dependencies:** E02, E04, E05. **Requirements:** RQ28, RQ30, RQ32.

**Files:**

- modify: `governance/capability-inventory/skills.toml`
- create: `tools/verification/skill_contract.ml`
- create: `tests/skills/skill_contract_test.ml`
- modify: `contracts/rules/diagram-ascii-mermaid-mandate.md`

**Execution steps:**

- [ ] Step 1: Audit schema/path/trigger/rule/dependency/mirror integrity for every registered skill; prioritize behavior/example verification for website/page/wiki/ZK/KM/layout/navigation/Gleam/Lustre/formal/browser/research skills, and require current safe examples for every skill admitted to execution.
- [ ] Step 2: Repair UOS-owned defects with backups and runnable examples; imported skills stay inert until adaptation/admission, and protected global agent-home writes follow actual sandbox permission requirements.
- [ ] Step 3: Generate paired ASCII/Mermaid from one graph model and check node/edge/label/group parity; preserve historical diagrams and distinguish test screenshots/videos from explanatory diagrams.

**Executable acceptance fixture:**

```json
{
  "id": "H01-regression",
  "given": {
    "skill": "wiki-design",
    "declared_tool": "missing_tool",
    "mirror_digest": "different",
    "diagram": {
      "ascii_edges": [ [ "a", "b" ] ],
      "mermaid_edges": [ [ "a", "c" ] ]
    }
  },
  "when": [ { "op": "skills.verify" } ],
  "expect": {
    "admitted": false,
    "missing_dependency_reported": true,
    "mirror_drift_reported": true,
    "diagram_parity": false
  }
}
```

**Acceptance gate:** Relevant admitted skills load and execute their safe examples, mirrors agree, contradictions are reconciled, and diagram parity is machine checked.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task H01
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## H02: Verify AGY/Codex core, connectors, browser and native integrations

**Workstream:** H. **Priority:** P1. **Dependencies:** E03, H01. **Requirements:** RQ29, RQ31.

**Files:**

- create: `tools/verification/agent_health.ml`
- create: `tests/agents/health_contract_test.ml`
- inspect: `tests/web_quality/20260906-0631-agy-config-repair.ml`

**Execution steps:**

- [ ] Step 1: Recheck native configuration/skill/hook discovery and core bounded inference smoke using the actual AGY/Codex entry points; retain current versions and sanitized result receipts.
- [ ] Step 2: Resolve AGY's required Stitch OAuth client configuration through the authorized credential mechanism and provision a supported pinned browser driver; do not fabricate missing credentials or silently drop required integrations.
- [ ] Step 3: Test tool calls, errors, restart/recovery and missing dependencies. Separate core usability from connector/native/browser health, with actionable residual reasons.

**Executable acceptance fixture:**

```json
{
  "id": "H02-regression",
  "given": {
    "core_inference": "passed",
    "skill_discovery": "passed",
    "stitch_oauth": "missing_client_id",
    "browser_driver": "download_failed"
  },
  "when": [ { "op": "agents.health" } ],
  "expect": {
    "core_usable": true,
    "all_integrations_healthy": false,
    "remaining": [ "stitch_oauth", "browser_driver" ],
    "secrets_logged": false
  }
}
```

**Acceptance gate:** All required integrations have fresh observed receipts; missing user-owned credentials remain explicit blockers for that integration without blocking independent work.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task H02
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## H03: Make development, documentation and test replay reproducible

**Workstream:** H. **Priority:** P1. **Dependencies:** E02, H01, M08. **Requirements:** RQ05, RQ26, RQ28, RQ32.

**Files:**

- modify: `tests/web_quality/20260906-0606-replay-guide.md`
- create: `tools/verification/environment.ml`
- create: `tests/dx/setup_replay_test.ml`
- modify: `tools/README.md`

**Execution steps:**

- [ ] Step 1: Replace historical scratch-path assumptions with repository-relative inputs or explicit arguments, locked tool versions and small executable examples.
- [ ] Step 2: Document exact cwd/commands/env requirements for Gleam Erlang, supported JavaScript modules, Hermes/formal workers, native builds and browser fixtures; actual package CLI behavior controls command syntax.
- [ ] Step 3: Run clean isolated setup/build/test/replay and record time/error/repair outcomes; expose actionable diagnostics, source links and example-driven API guidance.

**Executable acceptance fixture:**

```json
{
  "id": "H03-regression",
  "given": {
    "checkout": "clean_isolated_jj",
    "scratch_inputs_present": false,
    "dependencies": "locked",
    "requested": "selected_unit_and_browser_case"
  },
  "when": [ { "op": "dx.replay" } ],
  "expect": {
    "uses_hidden_tmp_paths": false,
    "commands_documented": true,
    "missing_dependency_diagnostic": "explicit",
    "execution_receipts_generated": true
  }
}
```

**Acceptance gate:** A clean admitted environment reproduces selected tests without hidden /tmp history; dependency absence fails with an actionable diagnostic rather than a false pass.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task H03
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## R01: Assemble a reproducible release and verify reversible cutover

**Workstream:** R. **Priority:** P1. **Dependencies:** E08, H02, H03, K02, K03, N01, P04, Q01, Q02, V07. **Requirements:** RQ16, RQ27, RQ31, RQ32.

**Files:**

- modify: `apps/cepaf_gleam/src/cepaf_gleam/release.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/ha/otp_release.gleam`
- create: `tools/verification/release_manifest.ml`
- create: `tests/release/cutover_test.ml`

**Execution steps:**

- [ ] Step 1: Create release artifacts with locked sources/dependencies/native libraries/feature flags, schema/model/atlas versions, content snapshots, routes and tool receipts.
- [ ] Step 2: Exercise staged isolated cutover, canary health and rollback with real payload/permission/trace compatibility; rollback covers native library/schema/actor state, not only code.
- [ ] Step 3: Prepare the exact change, health criteria, rollback triggers and evidence for any deployment approval required by the current authorized scope. Do not invent approval or send third-party messages.

**Executable acceptance fixture:**

```json
{
  "id": "R01-regression",
  "given": {
    "candidate": "final-jj",
    "runtime_receipt": "older-jj",
    "rollback_bundle": "verified",
    "deployment_authorized": false
  },
  "when": [ { "op": "release.prepare" } ],
  "expect": {
    "deploy": false,
    "admitted": false,
    "reason": "stale_runtime_receipt",
    "rollback_ready": true
  }
}
```

**Acceptance gate:** Release is reproducible and rollback exercised; stale/missing evidence prevents deployment/admission; any required approval concerns a concrete prepared candidate.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task R01
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## R02: Run final candidate gates and independent review

**Workstream:** R. **Priority:** P1. **Dependencies:** H02, R01, V02, V03, V04, V05, V06, V07. **Requirements:** RQ05, RQ06, RQ18, RQ23, RQ30, RQ31, RQ33, RQ35.

**Files:**

- create: `tools/verification/admission.ml`
- create: `tests/release/admission_test.ml`
- modify: `tools/uos/src/main.gleam`

**Execution steps:**

- [ ] Step 1: Freeze the final candidate/build/content/model/dependency manifest and re-run all affected formal/runtime/browser/profile/role/edge cases with complete denominators.
- [ ] Step 2: Require independent human or separately identified reviewer evidence under the existing governance policy; never generate another reviewer's signature or infer review from a certificate heading.
- [ ] Step 3: Check all layers, API clauses, routes/components/cycles, source-preservation/licensing, metrics, skills and required integrations; serialize Jujutsu integration and reject any drift.

**Executable acceptance fixture:**

```json
{
  "id": "R02-regression",
  "given": {
    "required_cases": 100,
    "passed": 99,
    "unrun": 1,
    "formal_key": true,
    "runtime_key": true,
    "reviewer_signature": "unverified_label"
  },
  "when": [ { "op": "release.admit" } ],
  "expect": {
    "admitted": false,
    "missing_cases": 1,
    "signature_credit": false
  }
}
```

**Acceptance gate:** Zero required missing/failed/skipped/unknown/stale obligations; actual runtime and formal keys match candidate; all reviews are authentic and attributable.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task R02
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## R03: Publish complete journals, handover and admitted status

**Workstream:** R. **Priority:** P1. **Dependencies:** R02. **Requirements:** RQ31, RQ32, RQ34.

**Files:**

- create: `tools/verification/completion_report.ml`
- modify: `HANDOVER_TO_CODEX.md`
- modify: `docs/zk/moc-agent-handover.md`
- modify: `governance/capability-inventory/verification-tracking.toml`

**Execution steps:**

- [ ] Step 1: Generate timestamped source/test/coverage/conformance/atlas/actor/edge/page-cycle reports and the exact 13-section completion journal from the validated ledger.
- [ ] Step 2: Publish full Tailnet links and retrievable artifact manifests, update root handover/MOCs/planning projections and show admitted state only after R02.
- [ ] Step 3: Record final Jujutsu change/commit/operation/bookmark provenance without Git mutations; retain old evidence/certificates as historical and describe any scoped exclusions explicitly.

**Executable acceptance fixture:**

```json
{
  "id": "R03-regression",
  "given": {
    "all_required_gates": "passed_current_candidate",
    "journal_sections": 13,
    "source_links_resolve": true,
    "media_retrievable": true,
    "authentic_review_present": true
  },
  "when": [ { "op": "release.publish_status" } ],
  "expect": {
    "status": "ADMITTED",
    "journal_sections": 13,
    "trace_chain_complete": true,
    "old_claims_preserved_as_history": true
  }
}
```

**Acceptance gate:** All delivered reports and media resolve, the complete evidence chain is inspectable, and completion state exactly matches the admitted candidate.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task R03
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## PLAN00: Register and verify this sa-plan execution programme

**Workstream:** P. **Priority:** P0. **Dependencies:** none. **Requirements:** RQ31, RQ33.

**Files:**

- create: `tools/sa_plan_execution.ml`
- create: `governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json`

**Execution steps:**

- [ ] Step 1: Validate all task IDs, dependencies, requirements and review mappings before a write.
- [ ] Step 2: Register tasks, reserved jobs and workflows through Sa_plan.Store in one transaction; replay without duplicates.
- [ ] Step 3: Read every registered record back, compare the contract, and complete only this planning task after registration checks pass.

**Executable acceptance fixture:**

```json
{
  "id": "PLAN00-registration",
  "given": { "empty_store": true, "second_registration": "identical" },
  "when": [
    { "op": "plan.register" },
    { "op": "plan.register" },
    { "op": "plan.status" }
  ],
  "expect": {
    "tasks": 71,
    "jobs": 71,
    "workflows": 13,
    "duplicates": 0,
    "implementation_cases_executed": 0
  }
}
```

**Acceptance gate:** Identical replay preserves records; unknown dependency, cycle and changed payload fail; no implementation job is dispatched.

**Replay contract:**

```sh
timeout 1200s ocaml tools/sa_plan_execution.ml selftest governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json
```

Actual planning registration selftest; not implementation acceptance.

## P01: Implement dependency-gated sa-plan job dispatch and fenced completion

**Workstream:** P. **Priority:** P0. **Dependencies:** E02, E03, M05. **Requirements:** RQ19, RQ20, RQ31, RQ33.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/planning/execution_dispatcher.gleam`
- create: `apps/cepaf_gleam/test/execution_dispatcher_test.gleam`

**Execution steps:**

- [ ] Step 1: Dispatch only from a named plan and queue with a current task lease, candidate-bound authorization, and satisfied local and external evidence dependencies.
- [ ] Step 2: Use stable task/job/activity IDs and attempt fencing; reject stale completion and prevent effects before task claim.
- [ ] Step 3: Enforce a 1200-second command budget, cancellation and process-tree cleanup; retry only declared idempotent work and record each result in sa-plan.

**Executable acceptance fixture:**

```json
{
  "id": "P01-dispatch",
  "given": {
    "job": "available",
    "task_dependency": "incomplete",
    "external_receipt": "missing"
  },
  "when": [ { "op": "execution.dispatch" } ],
  "expect": {
    "effect_count": 0,
    "task_completed": false,
    "job_dispatched": false,
    "reason": "DEPENDENCY_UNSATISFIED"
  }
}
```

**Acceptance gate:** Negative controls cover job/task mismatch, missing external receipt, stale lease, replay, worker crash and timeout; a satisfied-dependency positive control produces one observed effect.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task P01
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## P02: Make sa-plan CLI status and workflow views explicitly plan-aware

**Workstream:** P. **Priority:** P0. **Dependencies:** E02, E03. **Requirements:** RQ31, RQ33, RQ34.

**Files:**

- modify: `tools/sa-plan`
- create: `apps/cepaf_gleam/src/cepaf_gleam/planning/cli.gleam`
- create: `apps/cepaf_gleam/test/sa_plan_cli_integration_test.gleam`

**Execution steps:**

- [ ] Step 1: Add a Gleam CLI facade with explicit plan selection for list/tree/status/watch and UI projections; preserve the imported OCaml CLI/test originals and route documented legacy commands explicitly.
- [ ] Step 2: Expose actual task dependencies, job arguments and workflow state through typed read-only Store views and the bounded Store adapter.
- [ ] Step 3: Reject unknown plan IDs and malformed requests with nonzero process exit; bind output to the selected database and plan.

**Executable acceptance fixture:**

```json
{
  "id": "P02-plan-isolation",
  "given": {
    "plans": [ "uos/one", "uos/two" ],
    "selected": "uos/two",
    "different_counts": true
  },
  "when": [ { "op": "planning.status" } ],
  "expect": {
    "reported_plan": "uos/two",
    "cross_plan_records": 0,
    "unknown_plan_exit": 1
  }
}
```

**Acceptance gate:** Two independently populated plans remain isolated in all status projections; no hardcoded-plan fallback.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task P02
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## P03: Federate the existing 75-task OCaml-to-Gleam plan without resetting it

**Workstream:** P. **Priority:** P0. **Dependencies:** E04, P02. **Requirements:** RQ01, RQ02, RQ03, RQ31, RQ33.

**Files:**

- create: `apps/cepaf_gleam/src/cepaf_gleam/planning/linked_plan.gleam`
- create: `apps/cepaf_gleam/test/linked_plan_test.gleam`
- inspect: `governance/testing/ocaml_gleam/20260905-2251-sa-plan-workflow-spec.json`

**Execution steps:**

- [ ] Step 1: Resolve the existing uos/ocaml-gleam-tests/v1 plan, its 75 task IDs, 74 jobs and workflow using its actual store and original ownership.
- [ ] Step 2: Map every legacy task to an E/M/A/W/V/R obligation and provide read-only status plus candidate-bound completion receipt references.
- [ ] Step 3: Keep old IDs, attempts, results and histories intact. Route future mutations through its owning sa-plan writer; any store relocation requires an explicit migration receipt and owner coordination.

**Executable acceptance fixture:**

```json
{
  "id": "P03-legacy-federation",
  "given": {
    "legacy_tasks": 75,
    "legacy_jobs": 74,
    "legacy_workflows": 1,
    "repeat_link": true
  },
  "when": [ { "op": "planning.link_legacy" } ],
  "expect": {
    "new_execution_copies": 0,
    "legacy_history_changes": 0,
    "mapped_tasks": 75,
    "unknown_state_credit": false
  }
}
```

**Acceptance gate:** Every legacy ID is mapped once; E07 cannot close before required legacy completion receipts match the current source-preservation and parity candidate.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task P03
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## P04: Connect the Gleam planning cockpit to actual sa-plan records

**Workstream:** P. **Priority:** P1. **Dependencies:** P01, P02, W04, Z12. **Requirements:** RQ14, RQ18, RQ21, RQ23, RQ31, RQ34.

**Files:**

- modify: `apps/cepaf_gleam/src/cepaf_gleam/planning/sa_plan_bridge.gleam`
- create: `apps/cepaf_gleam/test/planning_cockpit_live_test.gleam`

**Execution steps:**

- [ ] Step 1: Use a supervised bounded Store adapter owned by Gleam and an explicitly modeled Zenoh gateway for domain communication.
- [ ] Step 2: Render selected plan, dependencies, leases, jobs, workflow history, unknown evidence and errors from observations rather than fixtures.
- [ ] Step 3: Verify a real record transition appears in UI/API with matching IDs and trace coordinates, and disconnected storage is reported as unavailable.

**Executable acceptance fixture:**

```json
{
  "id": "P04-live-planning",
  "given": { "observed_task": "E01", "store_available": false },
  "when": [ { "op": "planning.render" } ],
  "expect": {
    "status": "UNAVAILABLE",
    "constant_green": false,
    "task_completed": false
  }
}
```

**Acceptance gate:** Real Store mutation/readback reaches the browser; live and disconnected cases have captured DOM/accessibility/network evidence.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task P04
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## K01: Replace the simulated OCaml receipt with a real bounded worker

**Workstream:** K. **Priority:** P0. **Dependencies:** E06, M05. **Requirements:** RQ05, RQ06, RQ12, RQ13, RQ20, RQ31.

**Files:**

- modify: `apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_knowledge_runtime.gleam`
- create: `engines/hermes/modules/hermes_wiki/uos_knowledge_worker.ml`
- create: `engines/hermes/modules/hermes_wiki/uos_knowledge_worker.mli`
- create: `apps/cepaf_gleam/test/ocaml_knowledge_worker_integration_test.gleam`

**Execution steps:**

- [ ] Step 1: Define a versioned bounded request/result protocol, real cryptographic payload digest and process identity; obtain typed authorization before dispatch.
- [ ] Step 2: Launch and supervise the OCaml worker through a bounded subprocess adapter; collect actual stdout, exit, duration and oracle provenance.
- [ ] Step 3: Return nonpassing results for missing worker, malformed frames, timeout, process death and unsupported queries; remove fixed COMMITTED/GOSPEL_VERIFIED receipts.

**Executable acceptance fixture:**

```json
{
  "id": "K01-worker-absent",
  "given": {
    "worker_executable": "missing",
    "payloads_same_length": [ "abc", "xyz" ]
  },
  "when": [ { "op": "knowledge.worker_call" } ],
  "expect": {
    "status": "UNAVAILABLE",
    "verified": false,
    "digests_distinct": true,
    "leaked_children": 0
  }
}
```

**Acceptance gate:** A positive call proves a real worker PID and independent output; missing/crashed/timed-out workers never return verified receipts.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task K01
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## K02: Implement real journal ingestion and cited corpus retrieval

**Workstream:** K. **Priority:** P0. **Dependencies:** E04, E05, K01, W05. **Requirements:** RQ01, RQ02, RQ03, RQ21, RQ22, RQ25, RQ31.

**Files:**

- modify: `apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_vertical_slice_engine.gleam`
- modify: `apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_knowledge_runtime.gleam`
- create: `apps/cepaf_gleam/test/journal_ingestion_integration_test.gleam`

**Execution steps:**

- [ ] Step 1: Read allowlisted candidate files and parse their real AST/frontmatter/sections; reject absent or malformed journals.
- [ ] Step 2: Compute content digests from actual permitted bytes and build a source-revision/dirty-manifest/per-file provenance bundle before corpus admission.
- [ ] Step 3: Retrieve citations from the actual admitted index; return locations and matching digests, propagate stale/missing source status and expose true API results.

**Executable acceptance fixture:**

```json
{
  "id": "K02-real-input",
  "given": {
    "journal_path": "nonexistent.md",
    "declared_sections": 13,
    "census_kind": "dry_run"
  },
  "when": [ { "op": "knowledge.ingest" } ],
  "expect": {
    "status": "NOT_FOUND",
    "sections_count": 0,
    "admitted_files": 0,
    "verified_green": false
  }
}
```

**Acceptance gate:** Different real inputs produce correct distinct metadata and digests; no dry-run count becomes ingestion credit; citations resolve to admitted original content.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task K02
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## K03: Run independent Rust and OCaml knowledge conformance oracles

**Workstream:** K. **Priority:** P1. **Dependencies:** E06, K01, Z02. **Requirements:** RQ03, RQ05, RQ06, RQ20, RQ31.

**Files:**

- modify: `apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_vertical_slice_engine.gleam`
- create: `apps/cepaf_gleam/test/knowledge_differential_integration_test.gleam`

**Execution steps:**

- [ ] Step 1: Invoke independently pinned native and OCaml implementations with the same versioned fixture, collecting actual outputs and hashes.
- [ ] Step 2: Compare normalized semantic outputs without sharing expected values or copying one implementation's digest into the other.
- [ ] Step 3: Inject a deliberate one-side mismatch and missing-oracle control; report mismatch/unavailable with no parity credit.

**Executable acceptance fixture:**

```json
{
  "id": "K03-differential-mutant",
  "given": { "rust_output": "mutated", "ocaml_output": "reference" },
  "when": [ { "op": "knowledge.compare_oracles" } ],
  "expect": {
    "parity_matched": false,
    "verified_green": false,
    "independent_invocations": 2
  }
}
```

**Acceptance gate:** Positive independent execution matches and one-side mutants fail; fixed shared-digest implementations cannot satisfy the gate.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task K03
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## Q01: Remove the two observed compiler warnings and record the actual result

**Workstream:** Q. **Priority:** P2. **Dependencies:** E02. **Requirements:** RQ05, RQ31, RQ33.

**Files:**

- modify: `apps/cepaf_gleam/test/c3i_knowledge_actor_test.gleam`
- modify: `apps/cepaf_gleam/test/c3i_knowledge_runtime_test.gleam`

**Execution steps:**

- [ ] Step 1: Remove the unused type import and use or remove the redundant inventory binding while preserving assertions.
- [ ] Step 2: Run the affected tests and required compiler checks with captured diagnostics; record the exact current warning count.
- [ ] Step 3: Correct downstream handover warning claims only using the resulting candidate-bound receipt.

**Executable acceptance fixture:**

```json
{
  "id": "Q01-compiler-diagnostics",
  "given": { "prior_warning_count": 2 },
  "when": [ { "op": "compiler.check_affected_tests" } ],
  "expect": { "targeted_unused_warnings": 0, "assertions_removed": 0 }
}
```

**Acceptance gate:** Actual compiler output contains neither targeted warning; no implementation-mirroring test is added for this low-impact cleanup.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task Q01
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## Q02: Make all storage-safety assertions exercise the production admission path

**Workstream:** Q. **Priority:** P0. **Dependencies:** E02, E03. **Requirements:** RQ20, RQ31, RQ32.

**Files:**

- modify: `ops/kubernetes/nas-k8s-lab/tests/hardware_identity_test.rs`
- modify: `ops/kubernetes/nas-k8s-lab/src/spec.rs`

**Execution steps:**

- [ ] Step 1: Route protected-serial, missing-serial and valid-secondary-device fixtures through the production validator, moving the tested module boundary only if necessary.
- [ ] Step 2: Remove the duplicate test-local validator as an oracle; preserve the immutable protected serial in production.
- [ ] Step 3: Prove a production-check mutant is detected in an isolated non-destructive fixture; never exercise a real disk wipe.

**Executable acceptance fixture:**

```json
{
  "id": "Q02-production-serial",
  "given": { "serial": "25503L801736", "production_check_mutated": true },
  "when": [ { "op": "storage.run_production_validation_tests" } ],
  "expect": { "mutant_detected": true, "physical_disk_operations": 0 }
}
```

**Acceptance gate:** Safety fixtures call production code; deleting the production rejection causes the suite to fail.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task Q02
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## N01: Diagnose and restore the advertised VM-1 HTTP endpoint

**Workstream:** N. **Priority:** P1. **Dependencies:** E01, E02. **Requirements:** RQ18, RQ23, RQ31, RQ34.

**Files:**

- create: `tests/acceptance/peer_http_service_test.ml`
- inspect: `docs/design/20260906-1649-codex-master-session-handover.md`

**Execution steps:**

- [ ] Step 1: Distinguish name resolution, Tailnet reachability, listener state, service ownership and application health using bounded read-only probes.
- [ ] Step 2: Fix the identified service configuration through its owner and authorized service controls, or correct an obsolete advertised endpoint with provenance.
- [ ] Step 3: Capture a response carrying actual service/build identity, check linked navigation, and test unavailable-state reporting; do not equate TCP reachability with system health.

**Executable acceptance fixture:**

```json
{
  "id": "N01-peer-unavailable",
  "given": {
    "endpoint": "http://vm-1.tail55d152.ts.net:8088",
    "connection": "refused"
  },
  "when": [ { "op": "peer.health" } ],
  "expect": {
    "status": "UNAVAILABLE",
    "system_green": false,
    "timeout_seconds": 1200
  }
}
```

**Acceptance gate:** The advertised endpoint responds correctly with service identity or an evidence-backed corrected URL; failure remains visible in UI and sa-plan.

**Replay contract:**

```sh
timeout 1200s ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json --task N01
```

Acceptance runner and task adapter are delivered by E02 and the owning task; missing adapters are nonpassing.

## Linked existing OCaml-to-Gleam tasks

These native records remain in `uos/ocaml-gleam-tests/v1`. They are not copied into the new plan. P03/P01 provide federation and completion gates.

| Existing task | Title | Master obligations |
|---|---|---|
| OGL | Additive Gleam counterparts; retain every OCaml original | E07 |
| OGL.00 | Freeze and validate source inventory; preserve originals and Dune files | E04 |
| OGL.01 | Verify pinned OTP29, Gleam, OCaml and native build readiness | M08, H03 |
| OGL.02 | Implement Gleam preservation gate and expanded Dune classification | E04, E06 |
| OGL.03 | Implement all seven parity-algebra layers and bounded native adapter | E06, M06 |
| OGL.04 | Independently review pilot, case map, transport and mutation evidence | E07 |
| OGL.05 | Admit pilot pattern only after fresh source-preservation and parity evidence | E07 |
| OGL.M01.D | hermes_agent_loop: classify 17 candidates; enumerate cases and fixtures | E04 |
| OGL.M01.P | hermes_agent_loop: implement traced Gleam assertions over original libraries | E07 |
| OGL.M01.V | hermes_agent_loop: execute both suites, boundaries, properties and mutants | E07, V04 |
| OGL.M01.R | hermes_agent_loop: independent source-case and safety review | E07, R02 |
| OGL.M02.D | hermes_dependability: classify 23 candidates; enumerate cases and fixtures | E04 |
| OGL.M02.P | hermes_dependability: implement traced Gleam assertions over original libraries | E07 |
| OGL.M02.V | hermes_dependability: execute both suites, boundaries, properties and mutants | E07, V04 |
| OGL.M02.R | hermes_dependability: independent source-case and safety review | E07, R02 |
| OGL.M03.D | hermes_dune_graph: classify 1 candidates; enumerate cases and fixtures | E04 |
| OGL.M03.P | hermes_dune_graph: implement traced Gleam assertions over original libraries | E07 |
| OGL.M03.V | hermes_dune_graph: execute both suites, boundaries, properties and mutants | E07, V04 |
| OGL.M03.R | hermes_dune_graph: independent source-case and safety review | E07, R02 |
| OGL.M04.D | hermes_fpp_authority: classify 1 candidates; enumerate cases and fixtures | E04 |
| OGL.M04.P | hermes_fpp_authority: implement traced Gleam assertions over original libraries | E07 |
| OGL.M04.V | hermes_fpp_authority: execute both suites, boundaries, properties and mutants | E07, V04 |
| OGL.M04.R | hermes_fpp_authority: independent source-case and safety review | E07, R02 |
| OGL.M05.D | hermes_harness: classify 82 candidates; enumerate cases and fixtures | E04 |
| OGL.M05.P | hermes_harness: implement traced Gleam assertions over original libraries | E07 |
| OGL.M05.V | hermes_harness: execute both suites, boundaries, properties and mutants | E07, V04 |
| OGL.M05.R | hermes_harness: independent source-case and safety review | E07, R02 |
| OGL.M06.D | hermes_nix: classify 8 candidates; enumerate cases and fixtures | E04 |
| OGL.M06.P | hermes_nix: implement traced Gleam assertions over original libraries | E07 |
| OGL.M06.V | hermes_nix: execute both suites, boundaries, properties and mutants | E07, V04 |
| OGL.M06.R | hermes_nix: independent source-case and safety review | E07, R02 |
| OGL.M07.D | hermes_ops: classify 35 candidates; enumerate cases and fixtures | E04 |
| OGL.M07.P | hermes_ops: implement traced Gleam assertions over original libraries | E07 |
| OGL.M07.V | hermes_ops: execute both suites, boundaries, properties and mutants | E07, V04 |
| OGL.M07.R | hermes_ops: independent source-case and safety review | E07, R02 |
| OGL.M08.D | hermes_ops_dashboard: classify 23 candidates; enumerate cases and fixtures | E04 |
| OGL.M08.P | hermes_ops_dashboard: implement traced Gleam assertions over original libraries | E07 |
| OGL.M08.V | hermes_ops_dashboard: execute both suites, boundaries, properties and mutants | E07, V04 |
| OGL.M08.R | hermes_ops_dashboard: independent source-case and safety review | E07, R02 |
| OGL.M09.D | hermes_sysml: classify 6 candidates; enumerate cases and fixtures | E04 |
| OGL.M09.P | hermes_sysml: implement traced Gleam assertions over original libraries | E07 |
| OGL.M09.V | hermes_sysml: execute both suites, boundaries, properties and mutants | E07, V04 |
| OGL.M09.R | hermes_sysml: independent source-case and safety review | E07, R02 |
| OGL.M10.D | hermes_toolchain: classify 2 candidates; enumerate cases and fixtures | E04 |
| OGL.M10.P | hermes_toolchain: implement traced Gleam assertions over original libraries | E07 |
| OGL.M10.V | hermes_toolchain: execute both suites, boundaries, properties and mutants | E07, V04 |
| OGL.M10.R | hermes_toolchain: independent source-case and safety review | E07, R02 |
| OGL.M11.D | hermes_vcs: classify 19 candidates; enumerate cases and fixtures | E04 |
| OGL.M11.P | hermes_vcs: implement traced Gleam assertions over original libraries | E07 |
| OGL.M11.V | hermes_vcs: execute both suites, boundaries, properties and mutants | E07, V04 |
| OGL.M11.R | hermes_vcs: independent source-case and safety review | E07, R02 |
| OGL.M12.D | hermes_vision: classify 2 candidates; enumerate cases and fixtures | E04 |
| OGL.M12.P | hermes_vision: implement traced Gleam assertions over original libraries | E07 |
| OGL.M12.V | hermes_vision: execute both suites, boundaries, properties and mutants | E07, V04 |
| OGL.M12.R | hermes_vision: independent source-case and safety review | E07, R02 |
| OGL.M13.D | hermes_wiki: classify 69 candidates; enumerate cases and fixtures | E04 |
| OGL.M13.P | hermes_wiki: implement traced Gleam assertions over original libraries | E07 |
| OGL.M13.V | hermes_wiki: execute both suites, boundaries, properties and mutants | E07, V04 |
| OGL.M13.R | hermes_wiki: independent source-case and safety review | E07, R02 |
| OGL.M14.D | hermes_zellij: classify 3 candidates; enumerate cases and fixtures | E04 |
| OGL.M14.P | hermes_zellij: implement traced Gleam assertions over original libraries | E07 |
| OGL.M14.V | hermes_zellij: execute both suites, boundaries, properties and mutants | E07, V04 |
| OGL.M14.R | hermes_zellij: independent source-case and safety review | E07, R02 |
| OGL.M15.D | swarm: classify 18 candidates; enumerate cases and fixtures | E04 |
| OGL.M15.P | swarm: implement traced Gleam assertions over original libraries | E07 |
| OGL.M15.V | swarm: execute both suites, boundaries, properties and mutants | E07, V04 |
| OGL.M15.R | swarm: independent source-case and safety review | E07, R02 |
| OGL.M16.D | system_engg: classify 9 candidates; enumerate cases and fixtures | E04 |
| OGL.M16.P | system_engg: implement traced Gleam assertions over original libraries | E07 |
| OGL.M16.V | system_engg: execute both suites, boundaries, properties and mutants | E07, V04 |
| OGL.M16.R | system_engg: independent source-case and safety review | E07, R02 |
| OGL.91 | Integrate all family evidence; report unknowns and nonstandard tests | E07, E08 |
| OGL.92 | Recheck every original test, fixture, helper and Dune declaration unchanged | E04, R01 |
| OGL.93 | Run final differential, fault, formal and mutation gates; reject vacuity | V04, V05, V07 |
| OGL.94 | Independent final review and explicit operator integration handoff | E07, R02 |

<details>
<summary>5-domain, 18-checkpoint planning checklist</summary>

| Domain | Checkpoint | State | Evidence / obligation |
|---|---|---|---|
| D1 | CHK-01-TIME | PLANNING_METADATA | Observed clock and hour/seconds filename |
| D1 | CHK-02-TAIL | PLANNING_METADATA | Tailnet links supplied; browser acceptance remains open |
| D1 | CHK-03-FRACT | PLANNING_METADATA | L0-L9 tags provided |
| D1 | CHK-04-KM | IMPLEMENTATION_UNRUN | Source and plan links; bidirectional KM verification is W06 |
| D2 | CHK-05-MUDA | IMPLEMENTATION_UNRUN | No new runtime dependencies; full census is E04 |
| D2 | CHK-06-GRAPH | IMPLEMENTATION_UNRUN | No foreign vector library added |
| D2 | CHK-07-DRIVE | IMPLEMENTATION_UNRUN | Physical storage untouched; Q02 verifies production path |
| D3 | CHK-08-C1C8 | IMPLEMENTATION_UNRUN | W/V tasks define browser obligations |
| D3 | CHK-09-MATH | IMPLEMENTATION_UNRUN | M/E/V tasks require actual metrics and proofs |
| D3 | CHK-10-9MOD | IMPLEMENTATION_UNRUN | Modality-specific receipts required |
| D3 | CHK-11-REGR | IMPLEMENTATION_UNRUN | Registration verification is not application regression credit |
| D4 | CHK-12-GLEAM | IMPLEMENTATION_UNRUN | P01/P04 own real supervision integration |
| D4 | CHK-13-HERMES | IMPLEMENTATION_UNRUN | K01/K03 own actual subprocess and oracle calls |
| D4 | CHK-14-ZIGVM | IMPLEMENTATION_UNRUN | Kernel/VFS verification stays explicit |
| D4 | CHK-15-MAX | IMPLEMENTATION_UNRUN | MAX remains isolated |
| D4 | CHK-16-OTEL | IMPLEMENTATION_UNRUN | E08/M04/P04 bind real traces |
| D5 | CHK-17-SOV | IMPLEMENTATION_UNRUN | No reviewer signature fabricated |
| D5 | CHK-18-JJ | PLANNING_METADATA | Standalone JJ; original OCaml unchanged |

</details>
