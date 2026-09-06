# 20260906-0817- Evidence, provenance and test migration Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task by task. Checkboxes track execution. Inline work is the default; this plan does not dispatch subagents.

**Goal:** Complete and admit the UOS web/wiki/Zettelkasten/KM system, denotational DMC/TCM and L0-L9 atlas, FPP/SysML Gleam actor ecology, and full versioned C3I-derived Zenoh communication with observable verification.

**Architecture:** This subsystem is implemented through the task interfaces below and integrated through the shared evidence ledger. Existing source behavior is reused only after discriminating tests; every model/native/browser observation retains its exact candidate.

**Tech Stack:** Gleam/OTP and applicable Gleam JavaScript, Lustre/Wisp, Hermes OCaml/Bos/Dune, bounded native Rust/Rustler/Zenoh, Z3/Lean/Gospel/Quint, real browser automation, standalone Jujutsu. Exact installed/resolved pins are recorded by E01/M08/Z01; a source manifest version is not a runtime receipt.

**Spec:** [Unified AGY-to-Codex specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0606-uos-agy-codex-unified-master-prompt.md) and [Reviewed handover](http://nas-1.tail55d152.ts.net:4100/files/docs/zk/20260906-0606-agy-handover-understanding-and-actor-ecology-plan.md).

**Status:** PLAN READY; implementation tasks and their acceptance cases are PLANNED/UNRUN. Generated from synchronized host observation 2026-09-06T08:04:17Z. [This document](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0817-uos-implementation-01-evidence-and-migration.md).

[Master plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0817-uos-full-implementation-plan.md) · [Backlog](http://nas-1.tail55d152.ts.net:4100/files/governance/planning/20260906-0817-uos-full-implementation-backlog.json) · [Unified specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0606-uos-agy-codex-unified-master-prompt.md) · [Plan verification receipt](http://nas-1.tail55d152.ts.net:4100/files/governance/sources/20260906-0817-uos-full-implementation-plan-receipt.json) · [Planning cockpit](http://nas-1.tail55d152.ts.net:4100/planning) · [Home](http://nas-1.tail55d152.ts.net:4100/)

#fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #km-triad #zero-muda #tailscale-web

## Global constraints

- Canonical workspace: /home/an/NAS-setup/uos. Standalone, non-colocated Jujutsu only; no native Git mutation commands.
- External source trees are read-only. Before code/logic ingestion: source-writer quiescence, exact revision/dirty manifest/sanitized snapshot, license review and two-key verification. Original OCaml remains unchanged.
- Secret bytes, private keys, tokens, live DB/WAL/SHM, compiler caches and model weights are excluded from ingestion; known quarantined incidents are presence only.
- Gleam/OTP owns control/policy/actors; Hermes OCaml owns formal/oracle analysis; ZigVM owns deterministic runtime; Python is confined to services/inference/max.
- Operator-selected C3I-derived Zenoh NIF is the common UOS application/domain transport. Bounded scheduler-facing native calls; long work in supervised asynchronous tasks or isolated transport hosts.
- HTTP/SSE/WebSocket/AG-UI are modeled gateways; OTP bootstrap/supervision and pure local calls are explicitly classified runtime mechanics. Unexplained alternate domain communication is an open migration gap.
- Zero Bevy and Graphite. HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736" remains enforced. No destructive physical fault injection.
- All new generated documents/reports carry YYYYMMDD-HHSS-; HH is hour and SS seconds. Use synchronized host time, full Tailnet links and fractal tags.
- Every explanatory diagram has both ASCII and Mermaid with identical nodes/edges/labels/grouping. Screenshots/videos are observed evidence with provenance.
- Every page/document has the uniform shell and 5-domain, 18-checkpoint component. Checkpoints reflect fresh evidence rather than constant green labels.
- At least four distinct complete semantic cycles per page AND component at the final candidate; every discovered route/state/profile remains in the denominator.
- State sequence: discovered -> classified -> mapped -> implemented -> built -> executed -> passed -> verified -> admitted. PLANNED/MOCK/UNRUN/STALE/QUARANTINED/EXCLUDED/UNKNOWN are not passing.
- Two keys: fresh observed runtime behavior AND machine-verifiable formal specification at the same candidate. Solver timeout/UNKNOWN, unsupported syntax, missing tools, sorry, Admitted and undeclared axioms fail closed.
- Do not write raw live planning/evidence databases; use the admitted writer API and fenced leases. No third-party messaging or deployment is performed by this planning task.

## File and task map

| Task | Deliverable | Dependencies |
|---|---|---|
| E01 | Freeze a review candidate and reconcile advertised status | none |
| E02 | Build a receipt-producing acceptance harness that can fail honestly | E01 |
| E03 | Replace constant verification and metrics with evidence-backed results | E02 |
| E04 | Complete the source, document and test census | E01, E02 |
| E05 | Pin upstream techniques, fixtures and adoption decisions | E04 |
| E06 | Create cross-language fixtures and guarded OCaml differential execution | E02, E04, E05, M02 |
| E07 | Port every selected useful test obligation into Gleam suites | E04, E06 |
| E08 | Connect requirements, sources, plans and observations to one ledger | E02, E03, E04 |

## Execution contract

Read the master plan's harness, build/replay, source admission, conformance closure and browser-cycle sections before execution. The fixtures below are actual acceptance specifications to implement, not recorded execution results. Each adapter must observe the named production path; the expected object stays in the assertion engine. Expand every documented action/error/property/target obligation beyond the minimum example. Conformance parents generate deterministic leaf tasks from their pinned source inventory and remain open until every required leaf passes.

## Task E01: Freeze a review candidate and reconcile advertised status

**Status/priority:** PLANNED / P0. **Depends on:** none. **Requirements:** RQ01, RQ31, RQ32, RQ33.

**Files and ownership:**

- **create**: tools/verification/candidate_snapshot.ml
- **create**: tests/acceptance/candidate_snapshot_test.ml
- **inspect**: HANDOVER_TO_CODEX.md
- **inspect**: apps/cepaf_gleam/src/cepaf_gleam/fpp/evolutionary_cycles.gleam

**Interfaces:** Operation `candidate.snapshot`. Consumes: The acceptance_case.given object below is the exact fixture contract; the task registers a versioned adapter from this schema to the named production modules. Produces: The acceptance_case.expect object below defines required observable result fields. Production code cannot read expected values. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

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
  "when": [
    {
      "op": "candidate.snapshot"
    }
  ],
  "expect": {
    "inherited_credit": "STALE",
    "source_writes": 0,
    "records": [
      "change_id",
      "commit_id",
      "dirty_manifest",
      "served_build",
      "tool_versions",
      "clock_receipt"
    ],
    "signature_credit": false
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Read jj status/log and collect runtime build/version endpoints; inventory concurrent writers without stopping them implicitly.
2. Create a bounded OCaml snapshot tool with allowlisted paths and presence-only records for known quarantined material; distinguish source metadata from admitted sanitized snapshots.
3. Bind historical claims to their original candidate and actual receipts. Reconcile new FPP code, agent_factory timestamps, TCM fields, CLI checks and evolutionary-cycle constants before assigning credit.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task E01
```

Bootstrap uses its OCaml metadata probe; replay command becomes available in E02. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Every claim is current-supported, stale, unrun or contradicted with a locator; no automatic green from a file, comment, certificate or test total. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task E02: Build a receipt-producing acceptance harness that can fail honestly

**Status/priority:** PLANNED / P0. **Depends on:** E01. **Requirements:** RQ19, RQ20, RQ31, RQ33.

**Files and ownership:**

- **create**: tests/acceptance/contract.ml
- **create**: tests/acceptance/run.ml
- **create**: tests/acceptance/registry.ml
- **create**: tests/acceptance/runner_test.ml
- **create**: tests/acceptance/golden/receipt.schema.json

**Interfaces:** Operation `runner.verify`. Consumes: The acceptance_case.given object below is the exact fixture contract; the task registers a versioned adapter from this schema to the named production modules. Produces: The acceptance_case.expect object below defines required observable result fields. Production code cannot read expected values. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "E02-regression",
  "given": {
    "adapter": "missing_adapter",
    "required": true,
    "expected_exit": 0,
    "fixture": "temporary_isolated"
  },
  "when": [
    {
      "op": "runner.verify"
    }
  ],
  "expect": {
    "exit_code": 2,
    "status": "ERROR",
    "passing_tests": 0,
    "children_reaped": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Define the JSON action/fixture/observation contract in this plan; implement strict decoding, namespaced adapter dispatch, command/dependency allowlists and bounded subprocesses using OCaml/Bos.
2. Keep expected observations in the assertion interpreter only; adapters collect real outputs, failures, artifacts and timings. Unknown operations, missing fixtures, skipped required tests and timeout are nonpassing.
3. Add self-tests for a known passing control, deliberate failing assertion, missing executable, timeout, child-tree cleanup, output quota and source/revision mismatch. Write receipts atomically with separate built/executed/passed fields.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task E02
```

Runner is implemented in E02; task-specific adapter and fixtures are delivered by this task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Known positive control passes; every negative self-test produces its named nonpassing state and no leaked child process. The runner is not admitted merely because it emits JSON. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task E03: Replace constant verification and metrics with evidence-backed results

**Status/priority:** PLANNED / P0. **Depends on:** E02. **Requirements:** RQ31, RQ33, RQ34.

**Files and ownership:**

- **modify**: tools/uos/src/main.gleam
- **modify**: tools/uos/src/uos.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/evolutionary_cycles.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/verification/master_verification_registry.gleam
- **create**: apps/cepaf_gleam/test/verification_truth_test.gleam
- **create**: tools/uos/test/exit_status_test.gleam

**Interfaces:** Operation `verification.evaluate`. Consumes: The acceptance_case.given object below is the exact fixture contract; the task registers a versioned adapter from this schema to the named production modules. Produces: The acceptance_case.expect object below defines required observable result fields. Production code cannot read expected values. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

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
  "when": [
    {
      "op": "verification.evaluate"
    }
  ],
  "expect": {
    "admitted": false,
    "status": "UNRUN",
    "exit_code": 1,
    "metrics_available": false
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Write mutants that preserve existing contract files while removing runtime/formal receipts, changing their candidate or changing measured inputs; each must lose admission.
2. Replace constant cycle pass flags, synthetic digests and fixed quality values with typed observations and independently checked receipt references. Preserve historical certificates as attributed claims.
3. Make CLI process exit status reflect failed gates rather than only returning an ignored Int; feed the same result to UI/checklists and expose missing denominators.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task E03
```

Runner is implemented in E02; task-specific adapter and fixtures are delivered by this task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** File-presence-only and constant-True mutants fail; CLI nonzero exit is observed by a subprocess; UI and API report the same evidence state. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task E04: Complete the source, document and test census

**Status/priority:** PLANNED / P1. **Depends on:** E01, E02. **Requirements:** RQ01, RQ02, RQ03, RQ32.

**Files and ownership:**

- **modify**: tools/ocaml_test_inventory/src/ocaml_test_inventory/inventory.gleam
- **modify**: tools/ocaml_test_inventory/src/ocaml_test_inventory/files.gleam
- **create**: tools/source_review/census.ml
- **create**: tools/source_review/census_test.ml

**Interfaces:** Operation `census.classify`. Consumes: The acceptance_case.given object below is the exact fixture contract; the task registers a versioned adapter from this schema to the named production modules. Produces: The acceptance_case.expect object below defines required observable result fields. Production code cannot read expected values. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "E04-regression",
  "given": {
    "files": [
      "registered_test.ml",
      "helper.ml",
      "journal.md",
      "unreadable.md"
    ],
    "registered_tests": [
      "registered_test.ml"
    ],
    "ast_sites": 3,
    "unreadable": [
      "unreadable.md"
    ]
  },
  "when": [
    {
      "op": "census.classify"
    }
  ],
  "expect": {
    "files_accounted": 4,
    "unreadable": 1,
    "complete_review": false,
    "executed_tests": 0
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Resume the 161-file OCaml register, 770-file selected catalogue and 8,047-record corpus without double counting declarations/assertions/Gherkin steps.
2. Enumerate Dune/Gleeunit/ExUnit/Gherkin registration plus AST/import/call edges, linked journals/design documents and nested/symlinked Indrajaal/Sutra source roots; record every excluded/unreadable/generated/binary entry.
3. Give every case a stable source ID, locator/span, actual oracle, coverage scope, browser classification, transfer decision, dependency/runner and execution state. Close-reading status is distinct from indexed or hashed status.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task E04
```

Runner is implemented in E02; task-specific adapter and fixtures are delivered by this task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Scoped files and references equal reviewed plus classified exclusions plus explicit remaining frontier; census may finish while full close reading remains open, and that distinction is machine visible. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task E05: Pin upstream techniques, fixtures and adoption decisions

**Status/priority:** PLANNED / P1. **Depends on:** E04. **Requirements:** RQ01, RQ04, RQ12, RQ32.

**Files and ownership:**

- **create**: tools/source_review/adoption.ml
- **create**: tests/acceptance/adoption_test.ml
- **create**: governance/sources/20260906-0817-adoption-protocol.md

**Interfaces:** Operation `source.admit`. Consumes: The acceptance_case.given object below is the exact fixture contract; the task registers a versioned adapter from this schema to the named production modules. Produces: The acceptance_case.expect object below defines required observable result fields. Production code cannot read expected values. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

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
  "when": [
    {
      "op": "source.admit"
    }
  ],
  "expect": {
    "admitted": false,
    "source_writes": 0,
    "reason_codes": [
      "license_not_reviewed",
      "source_not_quiesced",
      "two_keys_missing"
    ]
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Bind Google web.dev/Lighthouse/HEART, WPT/WCAG/ARIA/axe, CommonMark/MediaWiki/Parsoid/TiddlyWiki/Logseq/Joplin/Docusaurus/Sphinx, SHACL/PROV, graph/category/property/fuzz references and NASA/OMG/Zenoh suites to exact locators and versions.
2. Review license/attribution and test dialect compatibility before copying any fixture; use read-only citations where source writers or licensing prevent admission.
3. Map each technique to a UOS requirement, mechanism, intended observable improvement, test/oracle, tradeoff and adoption/rejection rationale. Quarantined material remains presence only.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task E05
```

Runner is implemented in E02; task-specific adapter and fixtures are delivered by this task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Every imported fixture/algorithm has a reviewed license and exact provenance plus both admission keys; every research recommendation has a concrete UOS use or explicit rejection. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task E06: Create cross-language fixtures and guarded OCaml differential execution

**Status/priority:** PLANNED / P1. **Depends on:** E02, E04, E05, M02. **Requirements:** RQ01, RQ03, RQ19, RQ21.

**Files and ownership:**

- **modify**: apps/cepaf_gleam/src/cepaf_gleam/verification/ocaml_differential_oracle.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/verification/ocaml_parity_verifier.gleam
- **create**: tests/differential/run_oracle.ml
- **create**: tests/differential/fixture_codec.ml
- **create**: apps/cepaf_gleam/test/ocaml_oracle_contract_test.gleam

**Interfaces:** Operation `oracle.compare`. Consumes: The acceptance_case.given object below is the exact fixture contract; the task registers a versioned adapter from this schema to the named production modules. Produces: The acceptance_case.expect object below defines required observable result fields. Production code cannot read expected values. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "E06-regression",
  "given": {
    "fixture": "unicode-link-and-nul-payload",
    "left_status": "tool_missing",
    "right_output": "valid",
    "normalization": "declared_semantics_only"
  },
  "when": [
    {
      "op": "oracle.compare"
    }
  ],
  "expect": {
    "status": "UNRUN",
    "equivalent": false,
    "original_source_changed": false
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Define lossless versioned fixtures for ASTs, links, graph states, actions and outcomes; preserve binary bytes and explicit error categories.
2. Run eligible original OCaml in an admitted read-only sandbox with isolated output directory and bounded dependencies; unavailable original execution remains UNRUN.
3. Compare Gleam observations with independent OCaml outputs modulo only documented normalization. Retain counterexamples and reject artificial compare-to-self or constant-success adapters.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task E06
```

Runner is implemented in E02; task-specific adapter and fixtures are delivered by this task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Positive shared fixtures agree; deliberate Gleam mutation disagrees; missing/failed original tool cannot produce parity credit; original source digests remain identical. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task E07: Port every selected useful test obligation into Gleam suites

**Status/priority:** PLANNED / P1. **Depends on:** E04, E06. **Requirements:** RQ03, RQ19, RQ20, RQ21.

**Files and ownership:**

- **create**: apps/cepaf_gleam/src/cepaf_gleam/knowledge/test_contract.gleam
- **create**: apps/cepaf_gleam/test/knowledge_html_port_test.gleam
- **create**: apps/cepaf_gleam/test/knowledge_wiki_port_test.gleam
- **create**: apps/cepaf_gleam/test/knowledge_zk_port_test.gleam
- **create**: apps/cepaf_gleam/test/knowledge_km_port_test.gleam

**Interfaces:** Operation `migration.coverage`. Consumes: The acceptance_case.given object below is the exact fixture contract; the task registers a versioned adapter from this schema to the named production modules. Produces: The acceptance_case.expect object below defines required observable result fields. Production code cannot read expected values. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

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
  "when": [
    {
      "op": "migration.coverage"
    }
  ],
  "expect": {
    "required_missing": 2,
    "coverage_complete": false,
    "rejected_with_reason": 1
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. For each accepted source case implement its domain behavior and discriminating Gleam test using the shared fixture contract; prioritize parser/renderer/link/key/graph algebra laws.
2. Keep browser cases in the browser adapter, runtime actor cases in real process suites, and OCaml-only formal oracles in Hermes; distinguish a port from a reference fixture.
3. Require each accepted original case to resolve to a new test ID and coverage explanation. Reject obsolete/duplicate/tautological cases with evidence instead of reproducing weak assertions.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task E07
```

Runner is implemented in E02; task-specific adapter and fixtures are delivered by this task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** No selected useful case lacks a runnable destination; a mutation appropriate to each class is detected; all original OCaml remains unchanged. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task E08: Connect requirements, sources, plans and observations to one ledger

**Status/priority:** PLANNED / P1. **Depends on:** E02, E03, E04. **Requirements:** RQ02, RQ03, RQ11, RQ31, RQ32, RQ35.

**Files and ownership:**

- **create**: apps/cepaf_gleam/src/cepaf_gleam/verification/trace_ledger.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/verification/master_verification_registry.gleam
- **modify**: tools/planning_ledger/src/uos_planning_ledger.gleam
- **create**: apps/cepaf_gleam/test/trace_ledger_test.gleam

**Interfaces:** Operation `ledger.validate`. Consumes: The acceptance_case.given object below is the exact fixture contract; the task registers a versioned adapter from this schema to the named production modules. Produces: The acceptance_case.expect object below defines required observable result fields. Production code cannot read expected values. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

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
  "when": [
    {
      "op": "ledger.validate"
    }
  ],
  "expect": {
    "trace_connected": true,
    "admitted": false,
    "receipt_state": "STALE"
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Use stable typed IDs for requirement/source/intent/model/law/code/test/receipt/page/component edges; reject dangling references and conflicting identity.
2. Publish backlog/report projections through the admitted planning writer API, with exclusive epoch leases and idempotent IDs; never patch a live SQLite/WAL directly.
3. Add change-impact invalidation so code/model/source/dependency/route changes stale the affected descendants and aggregate checklist results.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task E08
```

Runner is implemented in E02; task-specific adapter and fixtures are delivered by this task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Trace paths are machine traversable; stale evidence propagates through dependent nodes; rereading/importing the same plan is idempotent. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.


## Subsystem exit gate

All listed tasks and their required conformance leaves have actual built/executed/passed/verified receipts; all mapped requirements have valid trace edges; changes have invalidated and refreshed dependent evidence. This subsystem's completion alone does not admit UOS. Follow R01-R03 for final release and full-system claims.

<details>
<summary>Five domains and eighteen verification checkpoints — plan status</summary>

| Domain | Checkpoint | Evidence or required gate |
|---|---|---|
| Metadata/navigation | CHK-01-TIME | Synchronized birth timestamp 2026-09-06T08:04:17Z; document prefix uses UTC hour and seconds. |
| Metadata/navigation | CHK-02-NAV | Full Tailnet document links; link validation is recorded separately from browser behavior. |
| Metadata/navigation | CHK-03-FRACT | All L0-L9 obligations mapped; implementation remains PLANNED. |
| Metadata/navigation | CHK-04-WIKI | Wiki/ZK/KM source and handover links retained. |
| Purity/storage | CHK-05-PURE | Gleam/OTP control, Hermes formal workers, Zig runtime; authorized C3I-derived bounded native transport. |
| Purity/storage | CHK-06-BANNED | No Bevy/Graphite ingestion authorized; provenance exclusions retained. |
| Purity/storage | CHK-07-STORAGE | Protected serial 25503L801736 remains denied; no physical destructive tests planned. |
| Testing/math | CHK-08-TEST | Concrete acceptance cases and TDD/BDD loop; none executed by writing this plan. |
| Testing/math | CHK-09-MATH | Compiler/formal/property/mutation tasks required; constants and labels do not prove laws. |
| Testing/math | CHK-10-BROWSER | Four final-candidate semantic cycles per page and component required; planning is not browser admission. |
| Testing/math | CHK-11-PARITY | External OCaml preserved; differential execution guarded and separately recorded. |
| Control/observability | CHK-12-GLEAM | Real actors already located; lifecycle and effect correspondence require verification. |
| Control/observability | CHK-13-HERMES | Bounded isolated solver/oracle workers; no direct observer writes. |
| Control/observability | CHK-14-ZIGVM | Read-only source evidence; deterministic Zig boundary preserved. |
| Control/observability | CHK-15-OTEL | Typed trace and receive/apply/commit evidence required across all domain edges. |
| Governance/Jujutsu | CHK-16-SOV | No independent signature or system admission invented. |
| Governance/Jujutsu | CHK-17-JJ | Standalone Jujutsu; concurrent work preserved; serialized integration. |
| Governance/Jujutsu | CHK-18-DOCS | Timestamped plans, machine backlog, thirteen-section journal and handover continuity. |

</details>

