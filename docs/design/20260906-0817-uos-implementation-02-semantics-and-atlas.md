# 20260906-0817- Denotation, DMC/TCM and algebraic atlas Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task by task. Checkboxes track execution. Inline work is the default; this plan does not dispatch subagents.

**Goal:** Complete and admit the UOS web/wiki/Zettelkasten/KM system, denotational DMC/TCM and L0-L9 atlas, FPP/SysML Gleam actor ecology, and full versioned C3I-derived Zenoh communication with observable verification.

**Architecture:** This subsystem is implemented through the task interfaces below and integrated through the shared evidence ledger. Existing source behavior is reused only after discriminating tests; every model/native/browser observation retains its exact candidate.

**Tech Stack:** Gleam/OTP and applicable Gleam JavaScript, Lustre/Wisp, Hermes OCaml/Bos/Dune, bounded native Rust/Rustler/Zenoh, Z3/Lean/Gospel/Quint, real browser automation, standalone Jujutsu. Exact installed/resolved pins are recorded by E01/M08/Z01; a source manifest version is not a runtime receipt.

**Spec:** [Unified AGY-to-Codex specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0606-uos-agy-codex-unified-master-prompt.md) and [Reviewed handover](http://nas-1.tail55d152.ts.net:4100/files/docs/zk/20260906-0606-agy-handover-understanding-and-actor-ecology-plan.md).

**Status:** PLAN READY; implementation tasks and their acceptance cases are PLANNED/UNRUN. Generated from synchronized host observation 2026-09-06T08:04:17Z. [This document](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0817-uos-implementation-02-semantics-and-atlas.md).

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
| M01 | Reconcile DMC/TCM vocabularies and register actual carriers | E02, E03 |
| M02 | Implement pure denotational intent and independent state transitions | M01, E02 |
| M03 | Enforce typed authorization and effect isolation at every ingress | M02, E03 |
| M04 | Implement complete Trace13 transport and transition checks | M01, M03 |
| M05 | Replace fixed time and value-only leases with real fenced ownership | M03, M04 |
| M06 | Implement executable morphism, graph and category laws | M02, M04 |
| M07 | Complete L0-L9 atlas and finite sheaf constructions | M01, M06, E08 |
| M08 | Bind real compiler and bounded formal workers to implementation semantics | M04, M05, M06, M07, E02 |

## Execution contract

Read the master plan's harness, build/replay, source admission, conformance closure and browser-cycle sections before execution. The fixtures below are actual acceptance specifications to implement, not recorded execution results. Each adapter must observe the named production path; the expected object stays in the assertion engine. Expand every documented action/error/property/target obligation beyond the minimum example. Conformance parents generate deterministic leaf tasks from their pinned source inventory and remain open until every required leaf passes.

## Task M01: Reconcile DMC/TCM vocabularies and register actual carriers

**Status/priority:** PLANNED / P0. **Depends on:** E02, E03. **Requirements:** RQ07, RQ08, RQ09, RQ10, RQ11.

**Files and ownership:**

- **modify**: contracts/rules/dmc-tcm-mandate.md
- **create**: apps/cepaf_gleam/src/cepaf_gleam/semantics/vocabulary.gleam
- **create**: apps/cepaf_gleam/test/semantics_vocabulary_test.gleam
- **inspect**: apps/cepaf_gleam/src/cepaf_gleam/fpp/dmc_tcm.gleam

**Interfaces:** Operation `semantics.resolve`. Consumes: Versioned fixture object given below; register production adapter in tests/acceptance/registry.ml. Produces: Required observations in expect; implementation results are collected independently of the expected values. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "M01-regression",
  "given": {
    "labels": [
      "DMC-Denotation",
      "DMC-Memory",
      "TCM-Morphism",
      "TCM-Trace13",
      "TCM-Temporal",
      "TensorAxis",
      "FractalLayer"
    ]
  },
  "when": [
    {
      "op": "semantics.resolve"
    }
  ],
  "expect": {
    "distinct_domains": 7,
    "aliased_domains": 0,
    "all_have_carrier_and_observation": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Register Denotational Meta-Calculus separately from new FPP Deterministic Memory Coherence; reconcile Type Class Morphisms, Traceability Coordinate Matrix and Temporal Coherence without deleting any obligation.
2. Define concrete domain records/enums and measured observations; ten axes, thirteen trace fields and ten fractal layers are distinct types.
3. Map each old public API and rule to its canonical domain; add compatibility adapters where needed and tests rejecting cross-domain substitution.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task M01
```

Planned runner supplied by E02 and task-specific adapter supplied here. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Every use of DMC/TCM in code/contracts/UI maps to one documented domain; no loss of previously requested semantics; registry compiles. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task M02: Implement pure denotational intent and independent state transitions

**Status/priority:** PLANNED / P0. **Depends on:** M01, E02. **Requirements:** RQ07, RQ19, RQ20, RQ21.

**Files and ownership:**

- **create**: apps/cepaf_gleam/src/cepaf_gleam/semantics/intent.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/semantics/reference.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/intent.gleam
- **create**: apps/cepaf_gleam/test/intent_denotation_test.gleam

**Interfaces:** Operation `intent.denote`. Consumes: Versioned fixture object given below; register production adapter in tests/acceptance/registry.ml. Produces: Required observations in expect; implementation results are collected independently of the expected values. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "M02-regression",
  "given": {
    "state": {
      "notes": [
        "a"
      ],
      "selected": "a"
    },
    "program": [
      {
        "kind": "navigate",
        "target": "missing"
      }
    ]
  },
  "when": [
    {
      "op": "intent.denote"
    }
  ],
  "expect": {
    "result": "UnknownTarget",
    "state": {
      "notes": [
        "a"
      ],
      "selected": "a"
    },
    "effects": []
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Define intent AST variants for navigation/read/query, guarded content changes, actor commands and verification jobs with source spans and typed errors.
2. Implement a pure reference interpretation from context/state/intent to either a value plus proposed effects or a typed rejection; strings describing an action are not the denotation.
3. Define sequence identity/associativity under the chosen error semantics, and test denotation against an independent small transition table for both accepted and rejected programs.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task M02
```

Planned runner supplied by E02 and task-specific adapter supplied here. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** State/effect observations match the reference; invalid target and partial-failure semantics are explicit; pure denotation performs no I/O. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task M03: Enforce typed authorization and effect isolation at every ingress

**Status/priority:** PLANNED / P0. **Depends on:** M02, E03. **Requirements:** RQ07, RQ10, RQ15, RQ27, RQ34.

**Files and ownership:**

- **create**: apps/cepaf_gleam/src/cepaf_gleam/semantics/authorization.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/semantics/effects.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/api/denotational_intent_router.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/api/denotational_intent_api.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/intent.gleam
- **create**: apps/cepaf_gleam/test/intent_authorization_test.gleam

**Interfaces:** Operation `intent.authorize_and_execute`. Consumes: Versioned fixture object given below; register production adapter in tests/acceptance/registry.ml. Produces: Required observations in expect; implementation results are collected independently of the expected values. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

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
  "when": [
    {
      "op": "intent.authorize_and_execute"
    }
  ],
  "expect": {
    "decision": "Denied",
    "effect_count": 0,
    "authoritative_state_changed": false
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Create an opaque authorized-intent value only the policy module can construct; use current actor/action/target/capability/epoch/context, not a caller-provided guard or proof-reference string.
2. Centralize the effect interpreter and enforce protected serial 25503L801736 independently at relevant storage boundary; observers cannot become writers through telemetry or forged traces.
3. Route HTTP/AG-UI/FPP/Zenoh commands through the same policy check. Add compiler-negative unauthorized constructor/use fixtures plus real effect-log tests for denied, expired, replayed and allowed intents.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task M03
```

Planned runner supplied by E02 and task-specific adapter supplied here. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Every denied/replayed/untrusted intent has zero effects; independent boundary interlocks hold; authorized intent produces exactly its declared effect proposal and receipt. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task M04: Implement complete Trace13 transport and transition checks

**Status/priority:** PLANNED / P0. **Depends on:** M01, M03. **Requirements:** RQ09, RQ21, RQ34.

**Files and ownership:**

- **modify**: apps/cepaf_gleam/src/cepaf_gleam/verification/web_quality_contract.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/verification/dmc_tcm_algebraic_atlas.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/dmc_tcm.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/semantics/trace.gleam
- **create**: apps/cepaf_gleam/test/trace13_mutation_test.gleam

**Interfaces:** Operation `trace.check`. Consumes: Versioned fixture object given below; register production adapter in tests/acceptance/registry.ml. Produces: Required observations in expect; implementation results are collected independently of the expected values. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "M04-regression",
  "given": {
    "mode": "transport",
    "base": "valid_trace13_fixture",
    "mutations": "each_of_13_fields_and_pairs"
  },
  "when": [
    {
      "op": "trace.check"
    }
  ],
  "expect": {
    "single_field_mutations_rejected": 13,
    "unapproved_pair_mutations_rejected": true,
    "unchanged_control_passes": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Register all thirteen coordinate names/types from the reconciled schema; reject missing/unknown fields unless a versioned migration explicitly handles them.
2. Use exact preservation for transport, and a separate transition relation for permitted causal/time/epoch changes; preserve immutable authority and correlation fields.
3. Mutate every field and pairs, exercise old/new schema conversion, and connect the same checks to actual network envelopes and evidence-writer boundaries.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task M04
```

Planned runner supplied by E02 and task-specific adapter supplied here. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** All thirteen independent transport mutants fail, permitted state transitions pass only their explicit relation, and network round trips preserve the fields. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task M05: Replace fixed time and value-only leases with real fenced ownership

**Status/priority:** PLANNED / P0. **Depends on:** M03, M04. **Requirements:** RQ10, RQ27, RQ34.

**Files and ownership:**

- **create**: apps/cepaf_gleam/src/cepaf_gleam/semantics/clock.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/semantics/lease.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/dmc_tcm.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/agent_factory.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/uos_sup.gleam
- **create**: apps/cepaf_gleam/test/lease_clock_test.gleam

**Interfaces:** Operation `lease.apply`. Consumes: Versioned fixture object given below; register production adapter in tests/acceptance/registry.ml. Produces: Required observations in expect; implementation results are collected independently of the expected values. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "M05-regression",
  "given": {
    "lease": {
      "holder": "writer-b",
      "epoch": 8
    },
    "command": {
      "holder": "writer-a",
      "epoch": 7
    },
    "wall_clock_jump_ms": -60000,
    "monotonic_sequence": [
      100,
      101
    ]
  },
  "when": [
    {
      "op": "lease.apply"
    }
  ],
  "expect": {
    "command": "RejectedStaleEpoch",
    "writes": 0,
    "monotonic_order_preserved": true,
    "wall_clock_jump_reported": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Inject wall and monotonic clocks through explicit interfaces; replace constant date/time and synthetic vectors, testing epoch/day/month/year rollover and actual timestamp conversion.
2. Put lease acquisition/renewal/release and epoch comparison at the serialized authoritative writer, not only in a freely copied record; fence stale writers at commit.
3. Test two concurrent requesters, crash/restart, expired leases, negative time, drift bands, telemetry non-interference and interval-ID overlap with unknown components rejected.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task M05
```

Planned runner supplied by E02 and task-specific adapter supplied here. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** At most one current writer can commit; stale epochs never commit; time strings match supplied instants; observer-only state cannot mutate the ledger. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task M06: Implement executable morphism, graph and category laws

**Status/priority:** PLANNED / P1. **Depends on:** M02, M04. **Requirements:** RQ08, RQ11, RQ12, RQ21.

**Files and ownership:**

- **create**: apps/cepaf_gleam/src/cepaf_gleam/semantics/morphism.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/knowledge/graph.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/verification/graph_verification.gleam
- **create**: apps/cepaf_gleam/test/morphism_graph_laws_test.gleam

**Interfaces:** Operation `graph.verify`. Consumes: Versioned fixture object given below; register production adapter in tests/acceptance/registry.ml. Produces: Required observations in expect; implementation results are collected independently of the expected values. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "M06-regression",
  "given": {
    "vertices": [
      "a",
      "b",
      "c"
    ],
    "edges": [
      [
        "a",
        "b"
      ],
      [
        "b",
        "c"
      ]
    ],
    "mapped_edges": [
      [
        "a",
        "b"
      ]
    ],
    "law": "reachability_preservation"
  },
  "when": [
    {
      "op": "graph.verify"
    }
  ],
  "expect": {
    "valid_functor": false,
    "counterexample": [
      "a",
      "c"
    ],
    "reference_algorithm": "independent_floyd_warshall"
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Define objects/arrows/composability, identity and composition with typed errors; represent maps as executable functions/dictionaries with a named observation.
2. Implement BFS/DFS reachability, SCCs, topological sort where acyclicity is required, shortest paths and overlap/impact graph operations with explicit complexities.
3. Compare optimized algorithms to independent finite reference algorithms; test identity/associativity and operation preservation. Do not require legitimate navigation/link graphs to be acyclic or every path to be invertible.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task M06
```

Planned runner supplied by E02 and task-specific adapter supplied here. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Every claimed morphism law has quantified domains and counterexample-sensitive tests; graph mutants fail against an independent oracle. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task M07: Complete L0-L9 atlas and finite sheaf constructions

**Status/priority:** PLANNED / P1. **Depends on:** M01, M06, E08. **Requirements:** RQ11, RQ12, RQ21, RQ30, RQ35.

**Files and ownership:**

- **create**: apps/cepaf_gleam/src/cepaf_gleam/semantics/atlas.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/semantics/sheaf.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/fpp/algebraic_atlas.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/fpp_atlas_view.gleam
- **create**: apps/cepaf_gleam/test/atlas_sheaf_laws_test.gleam

**Interfaces:** Operation `atlas.glue`. Consumes: Versioned fixture object given below; register production adapter in tests/acceptance/registry.ml. Produces: Required observations in expect; implementation results are collected independently of the expected values. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "M07-regression",
  "given": {
    "sections": [
      {
        "domain": [
          "x"
        ],
        "values": {
          "x": "left"
        }
      },
      {
        "domain": [
          "x",
          "y"
        ],
        "values": {
          "x": "right",
          "y": "ok"
        }
      }
    ],
    "caller_claimed_overlap": [],
    "layers": [
      0,
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9
    ]
  },
  "when": [
    {
      "op": "atlas.glue"
    }
  ],
  "expect": {
    "result": "OverlapConflict",
    "conflicting_key": "x",
    "accepts_caller_omitted_overlap": false,
    "layer_count": 10
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Derive overlap from declared domains, reject duplicate/conflicting local assignments, implement restriction composition and gluing uniqueness over finite covers, including three or more sections.
2. Generate one atlas registry with carriers, operations, observations, denotation, laws, generators/shrinkers, independent oracles, source/code/test/proof/component locators and evidence state for all ten layers.
3. Replace constant associativity/gluing flags in FPP reports with actual law receipts. Generate equivalent ASCII/Mermaid views from the same graph and report uncovered L8/L9 deployment/model obligations.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task M07
```

Planned runner supplied by E02 and task-specific adapter supplied here. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** No missing layer, opaque claimed law or omitted-overlap conflict is admitted; every atlas entry resolves to code and tests; rendering diagrams does not create proof credit. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task M08: Bind real compiler and bounded formal workers to implementation semantics

**Status/priority:** PLANNED / P1. **Depends on:** M04, M05, M06, M07, E02. **Requirements:** RQ05, RQ06, RQ08, RQ11.

**Files and ownership:**

- **modify**: tools/web_quality_gate.ml
- **create**: tools/verification/formal_worker.ml
- **create**: tests/formal/worker_test.ml
- **modify**: formal/lean/Traceability.lean
- **modify**: formal/lean/TwoLattice_STM.lean
- **modify**: formal/quint/parity_frontier.qnt
- **modify**: formal/registry/formal-manifest.toml

**Interfaces:** Operation `formal.check`. Consumes: Versioned fixture object given below; register production adapter in tests/acceptance/registry.ml. Produces: Required observations in expect; implementation results are collected independently of the expected values. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

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
  "when": [
    {
      "op": "formal.check"
    }
  ],
  "expect": {
    "admitted": false,
    "status": "UNKNOWN",
    "process_tree_reaped": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Pin toolchains and encode value-level invariants from explicit Gleam transition observations or a checked IR projection; retain model/AST/source/input correspondence.
2. Run each solver in a normalized isolated worker with timeout/memory/output bounds and process-tree reaping; require satisfiable controls and expected failures for malformed/unsupported/missing tools.
3. Run actual Gleam BEAM and applicable JavaScript checks, compiler-negative fixtures, Lean/Gospel/Quint obligations, and reject missing axioms/proof holes. Enumerate properties not expressible in a given backend.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task M08
```

Planned runner supplied by E02 and task-specific adapter supplied here. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Formal results are invocation-specific; timeout/UNKNOWN/syntax error/proof hole cannot pass; a model or code mutation invalidates the corresponding proof/receipt. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.


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

