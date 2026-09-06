# 20260906-0817- Complete Zenoh native layer and communication migration Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task by task. Checkboxes track execution. Inline work is the default; this plan does not dispatch subagents.

**Goal:** Complete and admit the UOS web/wiki/Zettelkasten/KM system, denotational DMC/TCM and L0-L9 atlas, FPP/SysML Gleam actor ecology, and full versioned C3I-derived Zenoh communication with observable verification.

**Architecture:** This subsystem is implemented through the task interfaces below and integrated through the shared evidence ledger. Existing source behavior is reused only after discriminating tests; every model/native/browser observation retains its exact candidate.

**Tech Stack:** Gleam/OTP and applicable Gleam JavaScript, Lustre/Wisp, Hermes OCaml/Bos/Dune, bounded native Rust/Rustler/Zenoh, Z3/Lean/Gospel/Quint, real browser automation, standalone Jujutsu. Exact installed/resolved pins are recorded by E01/M08/Z01; a source manifest version is not a runtime receipt.

**Spec:** [Unified AGY-to-Codex specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0606-uos-agy-codex-unified-master-prompt.md) and [Reviewed handover](http://nas-1.tail55d152.ts.net:4100/files/docs/zk/20260906-0606-agy-handover-understanding-and-actor-ecology-plan.md).

**Status:** PLAN READY; implementation tasks and their acceptance cases are PLANNED/UNRUN. Generated from synchronized host observation 2026-09-06T08:04:17Z. [This document](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0817-uos-implementation-04-zenoh-native-and-ecosystem.md).

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
| Z01 | Complete candidate census and pin the native feature contract | E04, E05, M01 |
| Z02 | Repair native loading, result shapes and truthful error handling | Z01, E02 |
| Z03 | Implement supervised bounded session resources and ownership | Z02, M05 |
| Z04 | Complete binary data, key expressions, selectors and configuration | Z03, M04 |
| Z05 | Complete publishers, real Delete and owned subscriptions | Z04, M03 |
| Z06 | Complete queries, queryables and all reply semantics | Z05 |
| Z07 | Implement scouting, matching and liveliness | Z05, Z06 |
| Z08 | Complete QoS, locality, congestion and scheduling profiles | Z06, Z07 |
| Z09 | Complete advanced extensions and shared memory | Z08, M05 |
| Z10 | Complete transports, authentication and managed router/storage/plugins | Z09, E05 |
| Z11 | Benchmark corrected candidates and select the measured baseline | Z10, E03 |
| Z12 | Migrate and verify every UOS application communication edge | Z11, A05, M03, M04, E08 |

## Execution contract

Read the master plan's harness, build/replay, source admission, conformance closure and browser-cycle sections before execution. The fixtures below are actual acceptance specifications to implement, not recorded execution results. Each adapter must observe the named production path; the expected object stays in the assertion engine. Expand every documented action/error/property/target obligation beyond the minimum example. Conformance parents generate deterministic leaf tasks from their pinned source inventory and remain open until every required leaf passes.

## Task Z01: Complete candidate census and pin the native feature contract — conformance parent

**Status/priority:** PLANNED / P0. **Depends on:** E04, E05, M01. **Requirements:** RQ04, RQ17, RQ18.

**Files and ownership:**

- **create**: apps/cepaf_gleam/src/cepaf_gleam/zenoh/capabilities.gleam
- **create**: tools/verification/zenoh_api_inventory.ml
- **inspect**: apps/cepaf_gleam/native/c3i_nif/Cargo.toml
- **inspect**: apps/cepaf_gleam/native/c3i_nif/src/zenoh_nif.rs
- **create**: apps/cepaf_gleam/test/zenoh_capability_inventory_test.gleam

**Interfaces:** Operation `zenoh.inventory`. Consumes: Pinned, bounded fixture schema given below; native symbols/arity/result types are generated from the admitted API matrix. Produces: Native observations in expect, captured through the real Gleam facade and an independent receiver where applicable. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "Z01-regression",
  "given": {
    "candidates": [
      "current_c3i_uos",
      "legacy_indrajaal",
      "sutra"
    ],
    "exports": [
      5,
      17,
      6
    ],
    "runtime_benchmarks": [],
    "upstream_pages": [
      "1.8.0",
      "1.9.0",
      "1.10.0"
    ]
  },
  "when": [
    {
      "op": "zenoh.inventory"
    }
  ],
  "expect": {
    "performance_winner": "UNKNOWN",
    "selected_runtime_version": "requires_compatibility_receipt",
    "missing_api_rows_block_completion": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Compare all located Gleam/Elixir bindings, wrappers, native modules, lockfiles, tests and journals; extend the three-candidate comparison before choosing a source baseline.
2. Select exact compatible Zenoh/zenoh-ext/Rust/Rustler/OTP/router versions using release/toolchain/peer compatibility evidence; record as-found and chosen profiles separately.
3. Generate every public API/type/enum/builder/config/feature/platform/extension row from pinned sources and map it to planned native/Gleam APIs and tests. Include all sixteen families and all feature flags; reject census drift in CI.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task Z01
```

Planned E02 runner; real-native adapter, fixtures and isolated router profile supplied by this task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Every pinned upstream public item and flag has a row; no fastest claim without comparable native measurements; missing stable/unstable/target rows remain open. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task Z02: Repair native loading, result shapes and truthful error handling

**Status/priority:** PLANNED / P0. **Depends on:** Z01, E02. **Requirements:** RQ05, RQ17, RQ18, RQ27.

**Files and ownership:**

- **modify**: apps/cepaf_gleam/native/c3i_nif/src/lib.rs
- **modify**: apps/cepaf_gleam/src/c3i_nif.erl
- **modify**: apps/cepaf_gleam/src/indrajaal_native_zenoh.erl
- **modify**: apps/cepaf_gleam/src/cepaf_gleam_ffi.erl
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/zenoh/client.gleam
- **create**: apps/cepaf_gleam/test/zenoh_native_abi_test.gleam

**Interfaces:** Operation `zenoh.native_load`. Consumes: Pinned, bounded fixture schema given below; native symbols/arity/result types are generated from the admitted API matrix. Produces: Native observations in expect, captured through the real Gleam facade and an independent receiver where applicable. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "Z02-regression",
  "given": {
    "library": "missing",
    "operation": "get",
    "payload": "a legitimate string containing error"
  },
  "when": [
    {
      "op": "zenoh.native_load"
    }
  ],
  "expect": {
    "status": "Unavailable",
    "empty_success": false,
    "string_substring_error_classification": false,
    "phantom_session": false
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Generate and cross-check module/function/arity/result mappings for the actual selected native library; test loading through Gleam and any required Elixir facade.
2. Remove dummy open/put, unloaded-get empty success, hardcoded external .so paths and substring-based success/error inference; produce typed failures with bounded diagnostics.
3. Add positive native-load control and missing/wrong ABI/library/symbol/result-shape cases. Stage source adaptation only after E05 provenance and quiescence requirements hold.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task Z02
```

Planned E02 runner; real-native adapter, fixtures and isolated router profile supplied by this task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Native absence is always unavailable; actual symbols load at the locked candidate; no wrapper-shaped test can pass without the native operation. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task Z03: Implement supervised bounded session resources and ownership

**Status/priority:** PLANNED / P0. **Depends on:** Z02, M05. **Requirements:** RQ10, RQ15, RQ18, RQ27.

**Files and ownership:**

- **modify**: apps/cepaf_gleam/native/c3i_nif/src/zenoh_nif.rs
- **create**: apps/cepaf_gleam/native/c3i_nif/src/zenoh_session.rs
- **create**: apps/cepaf_gleam/src/cepaf_gleam/zenoh/session.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/moz/client.gleam
- **create**: apps/cepaf_gleam/test/zenoh_session_lifecycle_test.gleam

**Interfaces:** Operation `zenoh.session_lifecycle`. Consumes: Pinned, bounded fixture schema given below; native symbols/arity/result types are generated from the admitted API matrix. Produces: Native observations in expect, captured through the real Gleam facade and an independent receiver where applicable. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "Z03-regression",
  "given": {
    "sessions": 2,
    "retain_alias": true,
    "actions": [
      "open",
      "close",
      "put_via_old_alias",
      "reopen",
      "owner_die"
    ],
    "unreachable_endpoint": true
  },
  "when": [
    {
      "op": "zenoh.session_lifecycle"
    }
  ],
  "expect": {
    "old_alias_result": "Closed",
    "reopen_generation_changed": true,
    "other_session_unaffected": true,
    "all_resources_released": true,
    "normal_scheduler_blocked": false
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Replace singleton replacement/global-lock behavior with owned resource sessions, explicit generation/closed state and monitored BEAM ownership; close remains effective while aliases exist.
2. Move network waits into cancellable asynchronous native tasks or an isolated supervised transport host using the same NIF; keep scheduler-facing work/allocations bounded and do not hold global locks across awaits.
3. Implement readiness, real state, backoff, endpoint validation, drain/close/reopen, owner death and task cleanup; measure normal/dirty scheduler impact under failure.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task Z03
```

Planned E02 runner; real-native adapter, fixtures and isolated router profile supplied by this task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** No phantom connected status, stale resource use or leaked tasks; finite deadlines and close/reopen work with retained aliases and concurrent sessions. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task Z04: Complete binary data, key expressions, selectors and configuration — conformance parent

**Status/priority:** PLANNED / P1. **Depends on:** Z03, M04. **Requirements:** RQ09, RQ18, RQ21, RQ22.

**Files and ownership:**

- **create**: apps/cepaf_gleam/native/c3i_nif/src/zenoh_codec.rs
- **create**: apps/cepaf_gleam/src/cepaf_gleam/zenoh/types.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/zenoh/config.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/zenoh/key_expr.gleam
- **create**: apps/cepaf_gleam/test/zenoh_codec_key_test.gleam

**Interfaces:** Operation `zenoh.codec_roundtrip`. Consumes: Pinned, bounded fixture schema given below; native symbols/arity/result types are generated from the admitted API matrix. Produces: Native observations in expect, captured through the real Gleam facade and an independent receiver where applicable. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "Z04-regression",
  "given": {
    "payload_bytes": [
      0,
      255,
      34,
      10,
      240,
      159,
      140,
      141
    ],
    "kind": "Delete",
    "attachment": [
      0,
      1
    ],
    "invalid_config": "not-json",
    "key": "site/**",
    "operation": "concrete_publish"
  },
  "when": [
    {
      "op": "zenoh.codec_roundtrip"
    }
  ],
  "expect": {
    "bytes_preserved": true,
    "kind_preserved": true,
    "attachment_preserved": true,
    "invalid_config_rejected": true,
    "wildcard_publication_rejected": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Expose every selected-version sample field and all configuration options through typed validated schemas; preserve error reply, source metadata, timestamps and encoding without inventing identity from congestion status.
2. Support binary payloads and explicit bounds for bytes, attachments, keys, batches and replies; validate concrete versus expression/selector semantics using upstream and independent finite-language vectors.
3. Use structured serialization for spans/envelopes instead of string interpolation; reject invalid config rather than silently selecting defaults and retain exact option diagnostics.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task Z04
```

Planned E02 runner; real-native adapter, fixtures and isolated router profile supplied by this task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** All admitted codec/config/key rows round-trip or reject correctly; binary/NUL/Unicode/error/delete semantics survive real transport. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task Z05: Complete publishers, real Delete and owned subscriptions

**Status/priority:** PLANNED / P1. **Depends on:** Z04, M03. **Requirements:** RQ18, RQ19, RQ20, RQ34.

**Files and ownership:**

- **create**: apps/cepaf_gleam/native/c3i_nif/src/zenoh_pubsub.rs
- **create**: apps/cepaf_gleam/src/cepaf_gleam/zenoh/pubsub.gleam
- **create**: apps/cepaf_gleam/test/zenoh_pubsub_runtime_test.gleam

**Interfaces:** Operation `zenoh.pubsub`. Consumes: Pinned, bounded fixture schema given below; native symbols/arity/result types are generated from the admitted API matrix. Produces: Native observations in expect, captured through the real Gleam facade and an independent receiver where applicable. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

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
  "when": [
    {
      "op": "zenoh.pubsub"
    }
  ],
  "expect": {
    "received_kind": "Delete",
    "empty_put_not_accepted": true,
    "owner_cleanup": true,
    "oversize_poll_rejected": true,
    "authorization_checked": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Implement direct put/delete, declared publishers, every publication builder option, declare/undeclare and per-item batch outcomes; do not claim atomic batches unless separately implemented.
2. Deliver callbacks to monitored subjects/PIDs, signal declaration readiness/errors, bound queue count and bytes, implement pinned FIFO/ring/background/poll semantics and cleanup on owner death.
3. Audit per-item authorization and cancellation races. Independent subscribers must observe exact payload/kind/metadata; empty Put must never stand in for Delete.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task Z05
```

Planned E02 runner; real-native adapter, fixtures and isolated router profile supplied by this task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Every publication/subscription API row executes; ignored callbacks, readiness failures, empty-delete substitution and oversized allocation mutants fail. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task Z06: Complete queries, queryables and all reply semantics

**Status/priority:** PLANNED / P1. **Depends on:** Z05. **Requirements:** RQ18, RQ19, RQ21.

**Files and ownership:**

- **create**: apps/cepaf_gleam/native/c3i_nif/src/zenoh_query.rs
- **create**: apps/cepaf_gleam/src/cepaf_gleam/zenoh/query.gleam
- **create**: apps/cepaf_gleam/test/zenoh_query_runtime_test.gleam

**Interfaces:** Operation `zenoh.query`. Consumes: Pinned, bounded fixture schema given below; native symbols/arity/result types are generated from the admitted API matrix. Produces: Native observations in expect, captured through the real Gleam facade and an independent receiver where applicable. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "Z06-regression",
  "given": {
    "queryables": [
      {
        "reply": "Put",
        "key": "a"
      },
      {
        "reply": "Delete",
        "key": "b"
      },
      {
        "reply": "Error",
        "reason": "denied"
      }
    ],
    "target": "all",
    "consolidation": "none",
    "deadline_ms": 1000,
    "cancel_after_reply": 2
  },
  "when": [
    {
      "op": "zenoh.query"
    }
  ],
  "expect": {
    "error_reply_not_dropped": true,
    "delete_reply_distinct": true,
    "cancellation_observed": true,
    "late_replies_rejected": true,
    "reply_memory_bounded": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Implement get and declared queriers/queryables, completeness, selectors/parameters/payload/encoding/attachments, targets, consolidation, reply-key rules and all reply variants from the pin.
2. Use bounded streaming replies and explicit end/error/timeout/cancel events; validate query ownership and reject replies after cancellation or stale correlation.
3. Test zero/one/many responders, disjoint reply keys, local/remote routing, queryable death, malformed requests, deadline exhaustion and matching listeners.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task Z06
```

Planned E02 runner; real-native adapter, fixtures and isolated router profile supplied by this task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** All query/reply rows execute against real independent queryables; application errors are not swallowed as empty success; cancellation releases native and BEAM resources. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task Z07: Implement scouting, matching and liveliness

**Status/priority:** PLANNED / P1. **Depends on:** Z05, Z06. **Requirements:** RQ15, RQ18, RQ21.

**Files and ownership:**

- **create**: apps/cepaf_gleam/native/c3i_nif/src/zenoh_discovery.rs
- **create**: apps/cepaf_gleam/src/cepaf_gleam/zenoh/discovery.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/zenoh/liveliness.gleam
- **create**: apps/cepaf_gleam/test/zenoh_discovery_liveness_test.gleam

**Interfaces:** Operation `zenoh.liveliness`. Consumes: Pinned, bounded fixture schema given below; native symbols/arity/result types are generated from the admitted API matrix. Produces: Native observations in expect, captured through the real Gleam facade and an independent receiver where applicable. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "Z07-regression",
  "given": {
    "token": "uos/test/actor/a",
    "listener_join": "late",
    "owner_action": "crash",
    "partition_then_rejoin": true
  },
  "when": [
    {
      "op": "zenoh.liveliness"
    }
  ],
  "expect": {
    "history_observed": true,
    "disappearance_observed": true,
    "reappearance_observed": true,
    "token_does_not_grant_write_authority": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Expose scout start/stop and peer/router identities; distinguish physical presence, session status and application readiness.
2. Implement publisher/querier matching status/listeners and liveliness token/drop/get/subscriber/history APIs with bounded ownership.
3. Test late join, no matches, multiple matches, owner/router death, partition/rejoin and cancellation with actual network observations.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task Z07
```

Planned E02 runner; real-native adapter, fixtures and isolated router profile supplied by this task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Every discovery/matching/liveliness row behaves according to the pin; no health/liveliness signal can authorize effects. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task Z08: Complete QoS, locality, congestion and scheduling profiles

**Status/priority:** PLANNED / P1. **Depends on:** Z06, Z07. **Requirements:** RQ15, RQ18, RQ26.

**Files and ownership:**

- **create**: apps/cepaf_gleam/src/cepaf_gleam/zenoh/qos.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/ha/qos_policy.gleam
- **create**: apps/cepaf_gleam/native/c3i_nif/src/zenoh_qos.rs
- **create**: apps/cepaf_gleam/test/zenoh_qos_load_test.gleam

**Interfaces:** Operation `zenoh.qos`. Consumes: Pinned, bounded fixture schema given below; native symbols/arity/result types are generated from the admitted API matrix. Produces: Native observations in expect, captured through the real Gleam facade and an independent receiver where applicable. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "Z08-regression",
  "given": {
    "profile": "telemetry_drop",
    "offered_rate": "above_capacity",
    "command_profile": "authenticated_bounded",
    "mailbox_budget": 100
  },
  "when": [
    {
      "op": "zenoh.qos"
    }
  ],
  "expect": {
    "telemetry_loss_reported": true,
    "command_success_not_fabricated": true,
    "mailbox_within_budget": true,
    "scheduler_responsive": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Map every pinned priority/reliability/congestion/express/batching/locality variant and its stability gate; define profile contracts per message class.
2. Measure overload with open-loop producers, separate declared queue bounds from BEAM mailbox growth, and implement admission credits where required.
3. Test latency/throughput tradeoffs and origin/destination constraints without inventing global FIFO or exactly-once guarantees.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task Z08
```

Planned E02 runner; real-native adapter, fixtures and isolated router profile supplied by this task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Each supported QoS profile has a measured contract; lost telemetry is counted, commands retain explicit failure/acknowledgment semantics. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task Z09: Complete advanced extensions and shared memory — conformance parent

**Status/priority:** PLANNED / P1. **Depends on:** Z08, M05. **Requirements:** RQ18, RQ21, RQ22.

**Files and ownership:**

- **create**: apps/cepaf_gleam/native/c3i_nif/src/zenoh_advanced.rs
- **create**: apps/cepaf_gleam/native/c3i_nif/src/zenoh_shm.rs
- **create**: apps/cepaf_gleam/src/cepaf_gleam/zenoh/advanced.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/zenoh/shared_memory.gleam
- **create**: apps/cepaf_gleam/test/zenoh_advanced_shm_test.gleam

**Interfaces:** Operation `zenoh.recover`. Consumes: Pinned, bounded fixture schema given below; native symbols/arity/result types are generated from the admitted API matrix. Produces: Native observations in expect, captured through the real Gleam facade and an independent receiver where applicable. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "Z09-regression",
  "given": {
    "history_capacity": 3,
    "published_sequences": [
      1,
      2,
      3,
      4
    ],
    "subscriber_last": 1,
    "drop_sequence": 3,
    "buffer_owner": "terminated"
  },
  "when": [
    {
      "op": "zenoh.recover"
    }
  ],
  "expect": {
    "recovery_window_enforced": true,
    "missing_sample_reported": true,
    "duplicates_not_committed_twice": true,
    "buffer_reclaimed": true,
    "no_use_after_free": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Implement every pinned zenoh-ext serialization, advanced publish/subscribe, history/cache/recovery/miss/listener/group operation; map deprecated APIs to documented replacements while preserving compatibility obligations.
2. Complete shared-memory buffer/provider/client/lifetime/reclamation/fallback APIs as explicit supported profiles with byte budgets and platform checks.
3. Run stateful loss/recovery properties, isolated sanitizer/fault tests and actual copy/allocation measurements; missing hardware/profile execution remains UNRUN.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task Z09
```

Planned E02 runner; real-native adapter, fixtures and isolated router profile supplied by this task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** All extension and shared-memory rows have semantic/lifetime evidence; zero-copy is measured rather than asserted; unavailable profiles block full execution credit. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task Z10: Complete transports, authentication and managed router/storage/plugins — conformance parent

**Status/priority:** PLANNED / P1. **Depends on:** Z09, E05. **Requirements:** RQ16, RQ18, RQ27, RQ34.

**Files and ownership:**

- **create**: apps/cepaf_gleam/src/cepaf_gleam/zenoh/ecosystem.gleam
- **create**: tests/zenoh/profiles/transport_matrix.json
- **create**: tests/zenoh/ecosystem_probe.ml
- **create**: apps/cepaf_gleam/test/zenoh_ecosystem_contract_test.gleam

**Interfaces:** Operation `zenoh.ecosystem`. Consumes: Pinned, bounded fixture schema given below; native symbols/arity/result types are generated from the admitted API matrix. Produces: Native observations in expect, captured through the real Gleam facade and an independent receiver where applicable. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "Z10-regression",
  "given": {
    "transport_profiles": "all_pinned_supported_targets",
    "denied_key": "uos/control/forbidden",
    "storage_restart": true,
    "missing_target": "serial_fixture"
  },
  "when": [
    {
      "op": "zenoh.ecosystem"
    }
  ],
  "expect": {
    "denied_effects": 0,
    "persistence_observed": true,
    "missing_target_state": "UNRUN",
    "all_profiles_claimed_pass": false
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Provide versioned profiles for TCP/UDP/multicast/TLS/QUIC/datagrams/WebSocket/Unix socket/pipe/serial/vsock plus compression/multilink where offered by the selected release.
2. Implement typed management/verification for router topology/admin/statistics, storage manager/backends/replication and required bridges/plugins as supervised services; no unrestricted dynamic plugin loading from user input.
3. Exercise public-key/user-password/TLS identity and ACLs with isolated fixture credentials; verify restart durability, peer/version compatibility, invalid identities and missing profile dependencies.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task Z10
```

Planned E02 runner; real-native adapter, fixtures and isolated router profile supplied by this task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Every upstream transport/config/ecosystem row is accounted for and tested on declared targets; absent profiles remain nonpassing; original secrets/binaries are not imported. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task Z11: Benchmark corrected candidates and select the measured baseline

**Status/priority:** PLANNED / P1. **Depends on:** Z10, E03. **Requirements:** RQ17, RQ18, RQ26, RQ33.

**Files and ownership:**

- **create**: tests/zenoh/benchmark.ml
- **create**: apps/cepaf_gleam/native/c3i_nif/benches/transport_boundary.rs
- **create**: tests/zenoh/benchmark_analysis.ml

**Interfaces:** Operation `zenoh.benchmark`. Consumes: Pinned, bounded fixture schema given below; native symbols/arity/result types are generated from the admitted API matrix. Produces: Native observations in expect, captured through the real Gleam facade and an independent receiver where applicable. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "Z11-regression",
  "given": {
    "implementations": [
      "adapted_c3i",
      "adapted_indrajaal",
      "adapted_sutra",
      "pinned_rust_control"
    ],
    "same_qos": true,
    "same_auth": true,
    "native_receiver_missing": true
  },
  "when": [
    {
      "op": "zenoh.benchmark"
    }
  ],
  "expect": {
    "ranking_available": false,
    "status": "ERROR",
    "mock_or_pubsub_results_excluded": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Compare as-found and common-version builds separately under equal hardware/build/OTP/router/topology/payload/QoS/auth settings with raw samples, warm-up and independent repeats.
2. Measure boundary cost, real receive, query round trip and durable command acknowledgment separately; report supported tail quantiles, confidence intervals, throughput/goodput, loss, CPU/RSS/copies, reductions and scheduler/mailbox delay.
3. Exercise size/concurrency/fan-out/key/batch/shared-memory/overload/reconnect matrices. Enforce correctness/safety first, then select the coverage/performance Pareto frontier and document the deployment choice.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task Z11
```

Planned E02 runner; real-native adapter, fixtures and isolated router profile supplied by this task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** No winner without reproducible independent native receipts; mock/PubSub/serialization-only timings are labeled controls, not native throughput. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task Z12: Migrate and verify every UOS application communication edge

**Status/priority:** PLANNED / P1. **Depends on:** Z11, A05, M03, M04, E08. **Requirements:** RQ15, RQ16, RQ18, RQ34.

**Files and ownership:**

- **create**: apps/cepaf_gleam/src/cepaf_gleam/zenoh/domain_router.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/moz/client.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/agui/zenoh_bus.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/bridge/zenoh_mcp.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/planning/zenoh_adapter.gleam
- **create**: apps/cepaf_gleam/test/zenoh_domain_edges_test.gleam

**Interfaces:** Operation `zenoh.edge_audit`. Consumes: Pinned, bounded fixture schema given below; native symbols/arity/result types are generated from the admitted API matrix. Produces: Native observations in expect, captured through the real Gleam facade and an independent receiver where applicable. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "Z12-regression",
  "given": {
    "edges": [
      {
        "id": "wiki-query",
        "transport": "zenoh",
        "observed": true
      },
      {
        "id": "agent-command",
        "transport": "hidden_pubsub",
        "observed": true
      }
    ],
    "browser_gateway": "http"
  },
  "when": [
    {
      "op": "zenoh.edge_audit"
    }
  ],
  "expect": {
    "complete": false,
    "unmigrated_edges": [
      "agent-command"
    ],
    "http_gateway_accounted": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Enumerate every sender/receiver/schema/authority/deadline/QoS/current transport/key expression and migration status across apps, engines, services, intelligence, knowledge, agents and telemetry.
2. Adapt each domain edge through the admitted C3I-derived facade; browser/API/HTTP/SSE/WebSocket remain explicitly modeled gateways. Document OTP bootstrap/supervision and pure in-process mechanics separately.
3. Observe send/receive/apply/commit and full Trace13 where required. Detect hidden alternate domain buses by static call graph plus runtime instrumentation; retain unexplained exceptions as open gaps.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task Z12
```

Planned E02 runner; real-native adapter, fixtures and isolated router profile supplied by this task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** All required domain edges are mapped and observed through Zenoh; no phantom success, unobserved shortcut or unexplained alternative domain bus remains. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.


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

