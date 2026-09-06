# 20260906-0817- FPP, SysML and actor ecology Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task by task. Checkboxes track execution. Inline work is the default; this plan does not dispatch subagents.

**Goal:** Complete and admit the UOS web/wiki/Zettelkasten/KM system, denotational DMC/TCM and L0-L9 atlas, FPP/SysML Gleam actor ecology, and full versioned C3I-derived Zenoh communication with observable verification.

**Architecture:** This subsystem is implemented through the task interfaces below and integrated through the shared evidence ledger. Existing source behavior is reused only after discriminating tests; every model/native/browser observation retains its exact candidate.

**Tech Stack:** Gleam/OTP and applicable Gleam JavaScript, Lustre/Wisp, Hermes OCaml/Bos/Dune, bounded native Rust/Rustler/Zenoh, Z3/Lean/Gospel/Quint, real browser automation, standalone Jujutsu. Exact installed/resolved pins are recorded by E01/M08/Z01; a source manifest version is not a runtime receipt.

**Spec:** [Unified AGY-to-Codex specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0606-uos-agy-codex-unified-master-prompt.md) and [Reviewed handover](http://nas-1.tail55d152.ts.net:4100/files/docs/zk/20260906-0606-agy-handover-understanding-and-actor-ecology-plan.md).

**Status:** PLAN READY; implementation tasks and their acceptance cases are PLANNED/UNRUN. Generated from synchronized host observation 2026-09-06T08:04:17Z. [This document](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0817-uos-implementation-03-models-and-actors.md).

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
| A01 | Pin and implement the full FPP language front end | E05, M01 |
| A02 | Validate topology, ID spaces and typed port composition | A01, M06 |
| A03 | Complete FPP commands, parameters, telemetry, packets and dictionaries | A02, M03 |
| A04 | Complete hierarchical state-machine semantics | A01, M02 |
| A05 | Complete passive, queued and active process interpretations | A02, A04, M03, M05 |
| A06 | Map every required agent role and MIQ service to real behavior | A05, M07, E04 |
| A07 | Implement the complete SysML/KerML syntax and semantic front end | E05, M01 |
| A08 | Implement SysML behavior, requirements, verification and interchange | A07, M02, M06 |
| A09 | Prove and test model-to-actor correspondence | A03, A05, A08, M08 |
| A10 | Deliver an operational knowledge and verification actor ecology | A06, A09, Z12, W06 |

## Execution contract

Read the master plan's harness, build/replay, source admission, conformance closure and browser-cycle sections before execution. The fixtures below are actual acceptance specifications to implement, not recorded execution results. Each adapter must observe the named production path; the expected object stays in the assertion engine. Expand every documented action/error/property/target obligation beyond the minimum example. Conformance parents generate deterministic leaf tasks from their pinned source inventory and remain open until every required leaf passes.

## Task A01: Pin and implement the full FPP language front end — conformance parent

**Status/priority:** PLANNED / P1. **Depends on:** E05, M01. **Requirements:** RQ04, RQ13, RQ19.

**Files and ownership:**

- **create**: apps/cepaf_gleam/src/cepaf_gleam/fpp/parser.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/domain.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/fpp/conformance.gleam
- **create**: apps/cepaf_gleam/test/fpp_parser_conformance_test.gleam

**Interfaces:** Operation `fpp.parse`. Consumes: Versioned fixture in acceptance_case.given; adapter binds to these planned/current production files. Produces: Required observations in acceptance_case.expect; model observations and runtime observations are independent. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "A01-regression",
  "given": {
    "source": "unknown_construct X",
    "file": "negative.fpp",
    "reference_tool": "pinned_official_fpp"
  },
  "when": [
    {
      "op": "fpp.parse"
    }
  ],
  "expect": {
    "accepted": false,
    "diagnostic_has_source_span": true,
    "unsupported_construct_not_dropped": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Freeze the FPP specification/compiler and enumerate every clause, syntax construct, type, builder and positive/negative upstream test with source/license provenance.
2. Implement complete typed AST/parser/name resolution and diagnostics, preserving annotations, imports/includes, IDs, expressions, arrays/enums/structs, components, topology and state-machine constructs supported by the pin.
3. Compare parse/validation output and normalized round trips with the pinned official compiler. Turn every uncovered clause into a bounded child work item with a runnable fixture.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task A01
```

Planned E02 runner plus the task-specific model/runtime adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Every pinned FPP clause has implementation and positive/negative evidence; unsupported syntax blocks full-conformance admission. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task A02: Validate topology, ID spaces and typed port composition

**Status/priority:** PLANNED / P1. **Depends on:** A01, M06. **Requirements:** RQ12, RQ13, RQ15.

**Files and ownership:**

- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/topology.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/domain.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/dmc_tcm.gleam
- **create**: apps/cepaf_gleam/test/fpp_topology_contract_test.gleam

**Interfaces:** Operation `fpp.validate_topology`. Consumes: Versioned fixture in acceptance_case.given; adapter binds to these planned/current production files. Produces: Required observations in acceptance_case.expect; model observations and runtime observations are independent. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "A02-regression",
  "given": {
    "instances": [
      {
        "id": "a",
        "base": 100,
        "span": 10
      },
      {
        "id": "b",
        "base": 105,
        "span": 10
      }
    ],
    "edge": {
      "from_type": "IntPort",
      "to_type": "StringPort"
    },
    "unknown_component": "missing"
  },
  "when": [
    {
      "op": "fpp.validate_topology"
    }
  ],
  "expect": {
    "valid": false,
    "errors": [
      "id_overlap",
      "port_type_mismatch",
      "unknown_component"
    ]
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Extend existing topology validators for concrete type/arity/direction, serial/typed ports, duplicate IDs, indexing, instance ownership and lifecycle connections.
2. Compute ID ranges from the validated model; do not substitute a default span for missing components. Check overflow and overlap against an independent interval/graph oracle.
3. Represent allowed command/query/telemetry routes and forbidden observer-to-writer edges explicitly; require actual runtime routing to correspond to this graph.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task A02
```

Planned E02 runner plus the task-specific model/runtime adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Invalid edges/ranges fail with located errors; valid bounded cyclic communication is allowed where specified; actual port bindings resolve to unique authorized targets. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task A03: Complete FPP commands, parameters, telemetry, packets and dictionaries

**Status/priority:** PLANNED / P1. **Depends on:** A02, M03. **Requirements:** RQ13, RQ19, RQ21.

**Files and ownership:**

- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/dictionary.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/prm_db.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/packetizer.gleam
- **create**: apps/cepaf_gleam/test/fpp_wire_vectors_test.gleam

**Interfaces:** Operation `fpp.decode_packet`. Consumes: Versioned fixture in acceptance_case.given; adapter binds to these planned/current production files. Produces: Required observations in acceptance_case.expect; model observations and runtime observations are independent. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "A03-regression",
  "given": {
    "fixture": "official_pinned_packet_vector",
    "mutation": "flip_payload_bit",
    "dictionary_revision": "matched",
    "parameter_write_authorized": false
  },
  "when": [
    {
      "op": "fpp.decode_packet"
    }
  ],
  "expect": {
    "packet": "RejectedChecksum",
    "parameter_writes": 0,
    "dictionary_drift": false
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Pin actual F Prime command/event/parameter/telemetry/dictionary and selected wire-format contracts; separate CCSDS framing from F Prime protocols and do not infer compatibility from a sync constant.
2. Implement complete typed encode/decode, limits, IDs, endianness, checksum/framing, persistence semantics, parameter validation and command completion in the existing modules.
3. Use official golden vectors, binary round trips, malformed/truncated/oversized payloads, dictionary drift, unknown IDs and unauthorized parameter changes.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task A03
```

Planned E02 runner plus the task-specific model/runtime adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Wire vectors match their exact protocol/version; mutations fail correctly; no generic packet record or claimed checksum substitutes for observed encoding/decoding. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task A04: Complete hierarchical state-machine semantics

**Status/priority:** PLANNED / P1. **Depends on:** A01, M02. **Requirements:** RQ13, RQ15, RQ19, RQ21.

**Files and ownership:**

- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/interp.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/domain.gleam
- **modify**: apps/cepaf_gleam/test/fpp_hsm_test.gleam

**Interfaces:** Operation `fpp.hsm_step`. Consumes: Versioned fixture in acceptance_case.given; adapter binds to these planned/current production files. Produces: Required observations in acceptance_case.expect; model observations and runtime observations are independent. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "A04-regression",
  "given": {
    "active_path": [
      "root",
      "left",
      "leaf"
    ],
    "target_path": [
      "root",
      "right",
      "leaf2"
    ],
    "event": "switch",
    "guard": true
  },
  "when": [
    {
      "op": "fpp.hsm_step"
    }
  ],
  "expect": {
    "exit_order": [
      "leaf",
      "left"
    ],
    "entry_order": [
      "right",
      "leaf2"
    ],
    "active_path": [
      "root",
      "right",
      "leaf2"
    ],
    "actions_run_once": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Use the pinned FPP/HSM semantics for hierarchical initial states, guard/action ordering, event dispatch, history/internal/self transitions and invalid state references.
2. Test least-common-ancestor exit leaf-first and entry root-first against a simple independent transition interpreter, including nested cases and rejected guards.
3. Bound run-to-completion work and reject cyclic initialization or unbounded microsteps; retain generated stateful sequences and minimized counterexamples.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task A04
```

Planned E02 runner plus the task-specific model/runtime adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** All state-machine clauses have trace equivalence evidence; guard false preserves state and has no action effects; bounded runaway cases fail explicitly. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task A05: Complete passive, queued and active process interpretations

**Status/priority:** PLANNED / P1. **Depends on:** A02, A04, M03, M05. **Requirements:** RQ13, RQ15, RQ19, RQ34.

**Files and ownership:**

- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/actor.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/interp.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/uos_sup.gleam
- **create**: apps/cepaf_gleam/test/fpp_actor_runtime_test.gleam

**Interfaces:** Operation `actor.run`. Consumes: Versioned fixture in acceptance_case.given; adapter binds to these planned/current production files. Produces: Required observations in acceptance_case.expect; model observations and runtime observations are independent. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "A05-regression",
  "given": {
    "component_kind": "queued",
    "capacity": 2,
    "arrival_commands": [
      1,
      2,
      3
    ],
    "drain_steps": 2,
    "overflow_policy": "drop_new"
  },
  "when": [
    {
      "op": "actor.run"
    }
  ],
  "expect": {
    "applied": [
      1,
      2
    ],
    "dropped": [
      3
    ],
    "queue_depth": 0,
    "reply_stage": "applied",
    "supervisor_observed": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Extend the real actor.start path already present; distinguish synchronous passive calls, caller-drained queued behavior and autonomous active processing according to the model.
2. Add actual queue drain and execution, explicit ingress credits/backpressure and bounded work. A bounded list inside state does not bound the BEAM mailbox.
3. Fail actor initialization for invalid HSMs instead of silently discarding them; test shutdown, owner death, restart budgets, overflow policies and command accept/apply/commit stages.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task A05
```

Planned E02 runner plus the task-specific model/runtime adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Real process traces match the model under load and failure; bounded mailbox/resource behavior is measured; no enqueue acknowledgment is reported as completed execution. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task A06: Map every required agent role and MIQ service to real behavior

**Status/priority:** PLANNED / P1. **Depends on:** A05, M07, E04. **Requirements:** RQ11, RQ15, RQ28, RQ34.

**Files and ownership:**

- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/agent_taxonomy.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/agent_factory.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/miq_services.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/ontology.gleam
- **create**: apps/cepaf_gleam/test/agent_role_runtime_test.gleam

**Interfaces:** Operation `actor.role_workflow`. Consumes: Versioned fixture in acceptance_case.given; adapter binds to these planned/current production files. Produces: Required observations in acceptance_case.expect; model observations and runtime observations are independent. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "A06-regression",
  "given": {
    "role": "link_auditor",
    "input": {
      "page": "/wiki",
      "broken_target": "/missing"
    },
    "requested_effect": "write_corpus"
  },
  "when": [
    {
      "op": "actor.role_workflow"
    }
  ],
  "expect": {
    "finding": "BrokenLink",
    "corpus_writes": 0,
    "proposal_requires_policy": true,
    "timestamp_source": "runtime_clock"
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Map Harness-Bionic and C3I roles to UOS responsibilities and source evidence; validate whether mappings are total, injective or many-to-one instead of assuming a bijection.
2. Bind agent instances to actual subjects/processes, real clocks, capability boundaries and supervision; connect MIQ/inference/media operations to supervised bounded services with typed outcomes.
3. Exercise intent ingress, registries, corpus writers, renderer/index, auditors, verification workers, recovery, provenance and UI projection roles; every declared role has an observable workflow.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task A06
```

Planned E02 runner plus the task-specific model/runtime adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** No role receives credit from an enum/name alone; every enabled service executes under its real supervisor and authority contract. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task A07: Implement the complete SysML/KerML syntax and semantic front end — conformance parent

**Status/priority:** PLANNED / P1. **Depends on:** E05, M01. **Requirements:** RQ04, RQ14, RQ19.

**Files and ownership:**

- **create**: apps/cepaf_gleam/src/cepaf_gleam/sysml/ast.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/sysml/parser.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/sysml/resolve.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/sysml/typecheck.gleam
- **create**: apps/cepaf_gleam/test/sysml_conformance_test.gleam
- **inspect**: engines/hermes/modules/hermes_sysml/sysml_grammar.ml

**Interfaces:** Operation `sysml.validate`. Consumes: Versioned fixture in acceptance_case.given; adapter binds to these planned/current production files. Produces: Required observations in acceptance_case.expect; model observations and runtime observations are independent. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "A07-regression",
  "given": {
    "model": "pinned_negative_reference_model",
    "case": "unresolved_feature_and_bad_units"
  },
  "when": [
    {
      "op": "sysml.validate"
    }
  ],
  "expect": {
    "valid": false,
    "errors_have_locations": true,
    "unit_valued_model": false,
    "original_hermes_changed": false
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Pin OMG SysML 2.0/KerML 1.0 and compatible reference tooling/libraries/interchange schemas; enumerate complete normative syntax and semantic clause obligations.
2. Build Gleam source-span AST, scopes/imports/resolution, classification/specialization, feature typing, multiplicities, units/quantities and diagnostics; preserve the original unit-valued Hermes grammar.
3. Implement and test every normative clause with reviewed reference positives/negatives. Separate imported library conformance from the core parser and keep missing clauses visible.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task A07
```

Planned E02 runner plus the task-specific model/runtime adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Full pinned-standard denominator is explicit; no unsupported construct is silently accepted/discarded; parser success alone is not semantic conformance. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task A08: Implement SysML behavior, requirements, verification and interchange — conformance parent

**Status/priority:** PLANNED / P1. **Depends on:** A07, M02, M06. **Requirements:** RQ14, RQ19, RQ21, RQ32.

**Files and ownership:**

- **create**: apps/cepaf_gleam/src/cepaf_gleam/sysml/semantics.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/sysml/interchange.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/sysml/requirements.gleam
- **create**: apps/cepaf_gleam/test/sysml_behavior_roundtrip_test.gleam

**Interfaces:** Operation `sysml.roundtrip`. Consumes: Versioned fixture in acceptance_case.given; adapter binds to these planned/current production files. Produces: Required observations in acceptance_case.expect; model observations and runtime observations are independent. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "A08-regression",
  "given": {
    "model": "requirements-actions-states-connections-fixture",
    "mutation": "drop_verification_case_link"
  },
  "when": [
    {
      "op": "sysml.roundtrip"
    }
  ],
  "expect": {
    "equivalent": false,
    "diagnostic": "VerificationTraceLost",
    "stable_ids_preserved": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Complete parts/ports/connections, actions/states/transitions, calculations/constraints, requirements/satisfy/verify and other normative model features from the clause matrix.
2. Define pure execution semantics for executable constructs and explicitly typed non-executable model constructs; retain all supported standard information in interchange.
3. Test located semantic errors, units/multiplicity/specialization, stable IDs, round trips modulo stated normalization and comparison with the pinned reference validator.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task A08
```

Planned E02 runner plus the task-specific model/runtime adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Every standard feature is represented and validated; executable behavior matches its reference; unsupported reference-tool coverage is a named gap rather than a pass. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task A09: Prove and test model-to-actor correspondence

**Status/priority:** PLANNED / P1. **Depends on:** A03, A05, A08, M08. **Requirements:** RQ06, RQ11, RQ13, RQ14, RQ15.

**Files and ownership:**

- **create**: apps/cepaf_gleam/src/cepaf_gleam/sysml/fpp_projection.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/fpp/runtime_projection.gleam
- **create**: apps/cepaf_gleam/test/model_runtime_correspondence_test.gleam
- **create**: formal/quint/actor_correspondence.qnt

**Interfaces:** Operation `model.compare_trace`. Consumes: Versioned fixture in acceptance_case.given; adapter binds to these planned/current production files. Produces: Required observations in acceptance_case.expect; model observations and runtime observations are independent. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "A09-regression",
  "given": {
    "model_events": [
      "accepted",
      "applied",
      "committed"
    ],
    "runtime_events": [
      "accepted",
      "committed"
    ],
    "mutation": "omit_apply"
  },
  "when": [
    {
      "op": "model.compare_trace"
    }
  ],
  "expect": {
    "correspondence": false,
    "counterexample_step": 1,
    "admitted": false
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Create typed projections preserving stable model IDs, ports, ownership, requirements, units and trace coordinates; declare any abstraction relation explicitly.
2. Generate bounded traces from SysML/FPP reference transitions and observe actual actor event histories independently; compare under the declared observation relation.
3. Bind formal temporal checks to the same projection and input trace corpus; reject altered topology, omitted actions, unauthorized transitions and unmodeled runtime edges.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task A09
```

Planned E02 runner plus the task-specific model/runtime adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Each admitted model feature has reference-tool and actual runtime correspondence evidence; a generated model file is not treated as proof. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task A10: Deliver an operational knowledge and verification actor ecology

**Status/priority:** PLANNED / P1. **Depends on:** A06, A09, Z12, W06. **Requirements:** RQ15, RQ16, RQ20, RQ34.

**Files and ownership:**

- **create**: apps/cepaf_gleam/src/cepaf_gleam/ecology/knowledge_workflow.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/ecology/verification_workflow.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/uos_sup.gleam
- **create**: apps/cepaf_gleam/test/ecology_journeys_test.gleam

**Interfaces:** Operation `ecology.journey`. Consumes: Versioned fixture in acceptance_case.given; adapter binds to these planned/current production files. Produces: Required observations in acceptance_case.expect; model observations and runtime observations are independent. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

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
  "when": [
    {
      "op": "ecology.journey"
    }
  ],
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

- [ ] **Implement the named behavior and its independent oracle.**

1. Deliver one read-only find/open/backlink/verify-note journey and one authorized edit-or-command journey with immutable evidence and consumer acknowledgment.
2. Run locally between real supervised processes and across two nodes with an isolated real router; constrain peer shortcuts so transport evidence identifies the exercised path.
3. Exercise writer/auditor separation, UI projection, correlation, crash-after-apply recovery and missing peer behavior. Extend to every inventoried role/edge after the vertical slices pass.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task A10
```

Planned E02 runner plus the task-specific model/runtime adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Every required role and domain edge executes with policy/model/trace correspondence; receipts distinguish accepted, received, applied and committed. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.


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

