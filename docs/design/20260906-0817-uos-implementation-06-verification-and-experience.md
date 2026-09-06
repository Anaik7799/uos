# 20260906-0817- Browser, formal, property, fuzz and system verification Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task by task. Checkboxes track execution. Inline work is the default; this plan does not dispatch subagents.

**Goal:** Complete and admit the UOS web/wiki/Zettelkasten/KM system, denotational DMC/TCM and L0-L9 atlas, FPP/SysML Gleam actor ecology, and full versioned C3I-derived Zenoh communication with observable verification.

**Architecture:** This subsystem is implemented through the task interfaces below and integrated through the shared evidence ledger. Existing source behavior is reused only after discriminating tests; every model/native/browser observation retains its exact candidate.

**Tech Stack:** Gleam/OTP and applicable Gleam JavaScript, Lustre/Wisp, Hermes OCaml/Bos/Dune, bounded native Rust/Rustler/Zenoh, Z3/Lean/Gospel/Quint, real browser automation, standalone Jujutsu. Exact installed/resolved pins are recorded by E01/M08/Z01; a source manifest version is not a runtime receipt.

**Spec:** [Unified AGY-to-Codex specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0606-uos-agy-codex-unified-master-prompt.md) and [Reviewed handover](http://nas-1.tail55d152.ts.net:4100/files/docs/zk/20260906-0606-agy-handover-understanding-and-actor-ecology-plan.md).

**Status:** PLAN READY; implementation tasks and their acceptance cases are PLANNED/UNRUN. Generated from synchronized host observation 2026-09-06T08:04:17Z. [This document](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0817-uos-implementation-06-verification-and-experience.md).

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
| V01 | Create a real browser harness with semantic actions and durable artifacts | E02, W01, W02 |
| V02 | Run four recursive semantic cycles for every page and component | V01, W09, A10 |
| V03 | Verify accessibility, appearance and interaction across targets | V01, W09 |
| V04 | Add stateful property, metamorphic, differential and coverage-guided fuzz tests | E07, M07, A09, Z10, W07 |
| V05 | Verify compiler boundaries, formal coverage and mutation sensitivity | M08, A09, Z10, W06 |
| V06 | Measure web, system, UX, DX and CX performance | Z11, W09, H03 |
| V07 | Run full system BDD, recovery and ecological feedback verification | A10, V02, V03, V04, V05, V06 |

## Execution contract

Read the master plan's harness, build/replay, source admission, conformance closure and browser-cycle sections before execution. The fixtures below are actual acceptance specifications to implement, not recorded execution results. Each adapter must observe the named production path; the expected object stays in the assertion engine. Expand every documented action/error/property/target obligation beyond the minimum example. Conformance parents generate deterministic leaf tasks from their pinned source inventory and remain open until every required leaf passes.

## Task V01: Create a real browser harness with semantic actions and durable artifacts

**Status/priority:** PLANNED / P0. **Depends on:** E02, W01, W02. **Requirements:** RQ23, RQ24, RQ35.

**Files and ownership:**

- **create**: tests/web_quality/browser_harness.ml
- **create**: tests/web_quality/artifact_store.ml
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/verification/browser_emulation_bridge.gleam
- **create**: tests/web_quality/browser_harness_test.ml

**Interfaces:** Operation `browser.probe`. Consumes: Explicit acceptance fixture below and the referenced candidate/manifest inputs. Produces: Observed receipt/effect/artifact fields in expect; unavailable required tools/targets are nonpassing. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "V01-regression",
  "given": {
    "browser_executable": "missing",
    "page": "/wiki",
    "requested_artifacts": [
      "png",
      "dom",
      "ax",
      "ast",
      "video",
      "trace"
    ],
    "emulation_result": true
  },
  "when": [
    {
      "op": "browser.probe"
    }
  ],
  "expect": {
    "status": "UNRUN",
    "semantic_cycles_passed": 0,
    "emulation_credit": false,
    "missing_browser_reported": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Adapt the retained OCaml browser controller into a reproducible bounded harness with semantic locators, actual pointer/keyboard/touch actions, state restoration, console/network logs and build identification.
2. Provision pinned Chromium/Firefox/WebKit runners where required; separate browser absence from test failure and remove browser-emulation shortcuts from operational gates.
3. Store screenshot/DOM/AX/AST/video/trace artifacts with task/page/component/state/cycle/viewport/browser/candidate/time/digest metadata in a durable verified store; redact secrets and test retention/retrieval.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task V01
```

Planned E02 runner plus the task-specific verification adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** An actual browser action produces matching semantic/network observations and retrievable media; missing browser or emulation cannot produce a pass. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task V02: Run four recursive semantic cycles for every page and component

**Status/priority:** PLANNED / P1. **Depends on:** V01, W09, A10. **Requirements:** RQ20, RQ23, RQ24, RQ25, RQ35.

**Files and ownership:**

- **create**: tests/web_quality/cycle_controller.ml
- **create**: tests/web_quality/cycle_contract.ml
- **create**: apps/cepaf_gleam/src/cepaf_gleam/verification/browser_cycle_ledger.gleam
- **create**: apps/cepaf_gleam/test/browser_cycle_ledger_test.gleam

**Interfaces:** Operation `browser.cycle_admission`. Consumes: Explicit acceptance fixture below and the referenced candidate/manifest inputs. Produces: Observed receipt/effect/artifact fields in expect; unavailable required tools/targets are nonpassing. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "V02-regression",
  "given": {
    "page": "/wiki",
    "component": "source-toggle",
    "cycles": [
      {
        "id": 1,
        "semantic": true
      },
      {
        "id": 2,
        "semantic": true
      },
      {
        "id": 3,
        "semantic": true
      },
      {
        "id": 4,
        "semantic": false
      }
    ],
    "candidate": "current"
  },
  "when": [
    {
      "op": "browser.cycle_admission"
    }
  ],
  "expect": {
    "admitted": false,
    "semantic_cycles": 3,
    "required_cycles": 4,
    "reason": "fourth_cycle_has_no_semantic_evidence"
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. For each page and component instance run C1 semantics/all links, C2 interactions/BDD/focus, C3 responsive/zoom/accessibility/visual/failure, C4 regression/independent oracle/recovery.
2. Each cycle observes, derives expected behavior, acts, compares, records defects, applies a TDD repair where needed, rebuilds and reverifies affected descendants/siblings/parents; clean cycles record that no repair was necessary.
3. Invalidate dependent receipts after changes and repeat affected final-candidate cycles. Four viewports/screenshots/retries are not four distinct semantic cycles; keep running until the complete manifest is green.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task V02
```

Planned E02 runner plus the task-specific verification adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Every required final-candidate page and component has at least four complete distinct passing semantic cycles, all actions/states covered and no unexplained route/frontier gap. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task V03: Verify accessibility, appearance and interaction across targets

**Status/priority:** PLANNED / P1. **Depends on:** V01, W09. **Requirements:** RQ23, RQ24, RQ26.

**Files and ownership:**

- **create**: tests/web_quality/accessibility.ml
- **create**: tests/web_quality/visual_review.ml
- **create**: tests/web_quality/accessibility_cases.json

**Interfaces:** Operation `browser.accessibility`. Consumes: Explicit acceptance fixture below and the referenced candidate/manifest inputs. Produces: Observed receipt/effect/artifact fields in expect; unavailable required tools/targets are nonpassing. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "V03-regression",
  "given": {
    "control": "source-toggle",
    "accessible_name": "",
    "keyboard_activation": false,
    "visual_snapshot_equal": true
  },
  "when": [
    {
      "op": "browser.accessibility"
    }
  ],
  "expect": {
    "passed": false,
    "violations": [
      "missing_accessible_name",
      "keyboard_inoperable"
    ],
    "visual_equality_overrides_semantics": false
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Run pinned axe/WCAG/ARIA checks through the browser plus keyboard focus/order/restoration, screen-reader workflow, contrast by state, labels/errors and touch targets.
2. Use desktop/tablet/mobile, 200/400 percent zoom, reduced motion, themes and long/localized content; inspect screenshots for hierarchy/spacing/alignment/clipping.
3. Review visual differences with tolerances tied to stable rendering conditions; retain decisions and human/assistive-technology observations rather than treating pixels as functional proof.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task V03
```

Planned E02 runner plus the task-specific verification adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** All specified target/state/accessibility checks pass; untested assistive/browser targets remain UNRUN and are not hidden in aggregate success. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task V04: Add stateful property, metamorphic, differential and coverage-guided fuzz tests

**Status/priority:** PLANNED / P1. **Depends on:** E07, M07, A09, Z10, W07. **Requirements:** RQ21, RQ22, RQ27.

**Files and ownership:**

- **create**: tests/property/run.ml
- **create**: tests/fuzz/run.ml
- **create**: tests/fuzz/corpus_manifest.json
- **create**: apps/cepaf_gleam/test/stateful_property_test.gleam

**Interfaces:** Operation `fuzz.campaign`. Consumes: Explicit acceptance fixture below and the referenced candidate/manifest inputs. Produces: Observed receipt/effect/artifact fields in expect; unavailable required tools/targets are nonpassing. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

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
  "when": [
    {
      "op": "fuzz.campaign"
    }
  ],
  "expect": {
    "coverage_guided_claim": false,
    "seed_replayable": true,
    "failures_shrunk": true,
    "resource_bounds_enforced": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Build domain-valid generators/shrinkers for ASTs, graphs, routes, intent sequences, actor schedules, configs/keys/binary payloads, SysML/FPP models and knowledge edits.
2. Use metamorphic relations, independent OCaml/reference outputs and state-machine oracles. Record generator distributions, seeds, shrink lineage and expected-vs-observed semantic coverage.
3. Integrate genuine coverage feedback for suitable compiled parser/native targets with crash isolation and bounded resources; call random seed testing generated testing when coverage feedback is absent. Retain/minimize/replay every failure corpus.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task V04
```

Planned E02 runner plus the task-specific verification adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Named seeded counterexamples reproduce and shrink; fuzz campaigns have actual feedback/coverage evidence where claimed; failures cannot be converted into skips. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task V05: Verify compiler boundaries, formal coverage and mutation sensitivity

**Status/priority:** PLANNED / P1. **Depends on:** M08, A09, Z10, W06. **Requirements:** RQ05, RQ06, RQ19, RQ22, RQ33.

**Files and ownership:**

- **create**: tests/compiler/fixtures.gleam.txt
- **create**: tests/compiler/run.ml
- **create**: tests/mutation/run.ml
- **modify**: tools/web_quality_gate.ml

**Interfaces:** Operation `verification.mutation`. Consumes: Explicit acceptance fixture below and the referenced candidate/manifest inputs. Produces: Observed receipt/effect/artifact fields in expect; unavailable required tools/targets are nonpassing. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "V05-regression",
  "given": {
    "mutants": [
      "drop_trace_field",
      "bypass_authorization",
      "fake_browser_pass",
      "omit_sheaf_overlap",
      "swallow_query_error"
    ],
    "compiler_negative_exit": 0,
    "solver_control": "unsat"
  },
  "when": [
    {
      "op": "verification.mutation"
    }
  ],
  "expect": {
    "admitted": false,
    "negative_compile_case_failed": true,
    "solver_vacuity_rejected": true,
    "all_required_mutants_must_be_killed": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Build positive and negative fixtures for opaque construction, port/message mismatch, unsupported targets, FFI result shapes and generated code; verify nonzero compiler exit and diagnostic class, not a string anywhere in a log.
2. Link actual tool/source/query/candidate receipts to every atlas/conformance obligation; run bounded solver controls and reject holes, unsupported syntax and stale or incomplete model mappings.
3. Create targeted semantic mutants for original false-success patterns and critical safety laws; measure killed/surviving/equivalent/unrun denominators and investigate survivors.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task V05
```

Planned E02 runner plus the task-specific verification adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Required bad programs fail for intended reasons, positive controls compile, all critical mutants are detected and every claimed mathematical result has fresh scoped evidence. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task V06: Measure web, system, UX, DX and CX performance

**Status/priority:** PLANNED / P1. **Depends on:** Z11, W09, H03. **Requirements:** RQ17, RQ26, RQ33.

**Files and ownership:**

- **create**: tests/performance/web_and_actor.ml
- **create**: tests/performance/experience_analysis.ml
- **create**: tests/performance/workload_contract.json

**Interfaces:** Operation `experience.measure`. Consumes: Explicit acceptance fixture below and the referenced candidate/manifest inputs. Produces: Observed receipt/effect/artifact fields in expect; unavailable required tools/targets are nonpassing. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

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
  "when": [
    {
      "op": "experience.measure"
    }
  ],
  "expect": {
    "task_success_rate": 0.7,
    "field_claim_available": false,
    "lab_and_field_separate": true,
    "failures_retained": 3
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Define workload/goal/signal/metric contracts before measurement; set measured budgets using product requirements and observed baselines, recording review decisions and regressions.
2. Measure browser Core Web Vitals/lab responsiveness/resource weight, server/actor throughput and tail latency, retrieval quality, build/test/edit-feedback time and actionable diagnostics.
3. Run real representative user tasks and feedback where available; preserve attempt/participant/environment denominators, separate lab from field and avoid invented satisfaction or beauty scores.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task V06
```

Planned E02 runner plus the task-specific verification adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Performance/experience claims reproduce from raw observations; field/human gaps stay explicit; optimizations preserve accessibility and correctness. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task V07: Run full system BDD, recovery and ecological feedback verification

**Status/priority:** PLANNED / P1. **Depends on:** A10, V02, V03, V04, V05, V06. **Requirements:** RQ15, RQ19, RQ20, RQ23, RQ27, RQ34.

**Files and ownership:**

- **create**: tests/system/ecology_bdd.ml
- **create**: tests/system/fault_scenarios.json
- **create**: apps/cepaf_gleam/test/system_recovery_contract_test.gleam

**Interfaces:** Operation `system.recover`. Consumes: Explicit acceptance fixture below and the referenced candidate/manifest inputs. Produces: Observed receipt/effect/artifact fields in expect; unavailable required tools/targets are nonpassing. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

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
  "when": [
    {
      "op": "system.recover"
    }
  ],
  "expect": {
    "durable_effect_count": 1,
    "retry_receipt_correlated": true,
    "observer_writes": 0,
    "recovery_bounded": true,
    "ui_state_truthful": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Run end-to-end read and authorized-write journeys with actual browser, policy, model, native Zenoh, actor, storage/evidence and UI feedback.
2. Inject isolated router/peer/worker failures, queue pressure, duplicate/out-of-order messages, schema mismatch, clock changes and crash-after-apply schedules; never perform destructive physical storage experiments.
3. Verify bounded recovery, idempotency/fencing, telemetry non-interference, dead-man freshness and OODA/controller decisions from measured windows; do not substitute a chosen negative Lyapunov constant for a stability observation.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task V07
```

Planned E02 runner plus the task-specific verification adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** All required complete workflows and failure schedules satisfy effect/trace/time/authority contracts and show correct recoverable UI behavior. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.


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

