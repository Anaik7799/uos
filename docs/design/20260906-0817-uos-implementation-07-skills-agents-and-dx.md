# 20260906-0817- Skills, AGY/Codex health and developer experience Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task by task. Checkboxes track execution. Inline work is the default; this plan does not dispatch subagents.

**Goal:** Complete and admit the UOS web/wiki/Zettelkasten/KM system, denotational DMC/TCM and L0-L9 atlas, FPP/SysML Gleam actor ecology, and full versioned C3I-derived Zenoh communication with observable verification.

**Architecture:** This subsystem is implemented through the task interfaces below and integrated through the shared evidence ledger. Existing source behavior is reused only after discriminating tests; every model/native/browser observation retains its exact candidate.

**Tech Stack:** Gleam/OTP and applicable Gleam JavaScript, Lustre/Wisp, Hermes OCaml/Bos/Dune, bounded native Rust/Rustler/Zenoh, Z3/Lean/Gospel/Quint, real browser automation, standalone Jujutsu. Exact installed/resolved pins are recorded by E01/M08/Z01; a source manifest version is not a runtime receipt.

**Spec:** [Unified AGY-to-Codex specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0606-uos-agy-codex-unified-master-prompt.md) and [Reviewed handover](http://nas-1.tail55d152.ts.net:4100/files/docs/zk/20260906-0606-agy-handover-understanding-and-actor-ecology-plan.md).

**Status:** PLAN READY; implementation tasks and their acceptance cases are PLANNED/UNRUN. Generated from synchronized host observation 2026-09-06T08:04:17Z. [This document](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0817-uos-implementation-07-skills-agents-and-dx.md).

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
| H01 | Repair and admit relevant skills, rules and diagram generation | E04, E05, E02 |
| H02 | Verify AGY/Codex core, connectors, browser and native integrations | H01, E03 |
| H03 | Make development, documentation and test replay reproducible | E02, H01, M08 |

## Execution contract

Read the master plan's harness, build/replay, source admission, conformance closure and browser-cycle sections before execution. The fixtures below are actual acceptance specifications to implement, not recorded execution results. Each adapter must observe the named production path; the expected object stays in the assertion engine. Expand every documented action/error/property/target obligation beyond the minimum example. Conformance parents generate deterministic leaf tasks from their pinned source inventory and remain open until every required leaf passes.

## Task H01: Repair and admit relevant skills, rules and diagram generation

**Status/priority:** PLANNED / P0. **Depends on:** E04, E05, E02. **Requirements:** RQ28, RQ30, RQ32.

**Files and ownership:**

- **modify**: governance/capability-inventory/skills.toml
- **create**: tools/verification/skill_contract.ml
- **create**: tests/skills/skill_contract_test.ml
- **modify**: contracts/rules/diagram-ascii-mermaid-mandate.md

**Interfaces:** Operation `skills.verify`. Consumes: Explicit acceptance fixture below and the referenced candidate/manifest inputs. Produces: Observed receipt/effect/artifact fields in expect; unavailable required tools/targets are nonpassing. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "H01-regression",
  "given": {
    "skill": "wiki-design",
    "declared_tool": "missing_tool",
    "mirror_digest": "different",
    "diagram": {
      "ascii_edges": [
        [
          "a",
          "b"
        ]
      ],
      "mermaid_edges": [
        [
          "a",
          "c"
        ]
      ]
    }
  },
  "when": [
    {
      "op": "skills.verify"
    }
  ],
  "expect": {
    "admitted": false,
    "missing_dependency_reported": true,
    "mirror_drift_reported": true,
    "diagram_parity": false
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Audit schema/path/trigger/rule/dependency/mirror integrity for every registered skill; prioritize behavior/example verification for website/page/wiki/ZK/KM/layout/navigation/Gleam/Lustre/formal/browser/research skills, and require current safe examples for every skill admitted to execution.
2. Repair UOS-owned defects with backups and runnable examples; imported skills stay inert until adaptation/admission, and protected global agent-home writes follow actual sandbox permission requirements.
3. Generate paired ASCII/Mermaid from one graph model and check node/edge/label/group parity; preserve historical diagrams and distinguish test screenshots/videos from explanatory diagrams.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task H01
```

Planned E02 runner plus the task-specific verification adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Relevant admitted skills load and execute their safe examples, mirrors agree, contradictions are reconciled, and diagram parity is machine checked. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task H02: Verify AGY/Codex core, connectors, browser and native integrations

**Status/priority:** PLANNED / P1. **Depends on:** H01, E03. **Requirements:** RQ29, RQ31.

**Files and ownership:**

- **create**: tools/verification/agent_health.ml
- **create**: tests/agents/health_contract_test.ml
- **inspect**: tests/web_quality/20260906-0631-agy-config-repair.ml

**Interfaces:** Operation `agents.health`. Consumes: Explicit acceptance fixture below and the referenced candidate/manifest inputs. Produces: Observed receipt/effect/artifact fields in expect; unavailable required tools/targets are nonpassing. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "H02-regression",
  "given": {
    "core_inference": "passed",
    "skill_discovery": "passed",
    "stitch_oauth": "missing_client_id",
    "browser_driver": "download_failed"
  },
  "when": [
    {
      "op": "agents.health"
    }
  ],
  "expect": {
    "core_usable": true,
    "all_integrations_healthy": false,
    "remaining": [
      "stitch_oauth",
      "browser_driver"
    ],
    "secrets_logged": false
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Recheck native configuration/skill/hook discovery and core bounded inference smoke using the actual AGY/Codex entry points; retain current versions and sanitized result receipts.
2. Resolve AGY's required Stitch OAuth client configuration through the authorized credential mechanism and provision a supported pinned browser driver; do not fabricate missing credentials or silently drop required integrations.
3. Test tool calls, errors, restart/recovery and missing dependencies. Separate core usability from connector/native/browser health, with actionable residual reasons.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task H02
```

Planned E02 runner plus the task-specific verification adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** All required integrations have fresh observed receipts; missing user-owned credentials remain explicit blockers for that integration without blocking independent work. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task H03: Make development, documentation and test replay reproducible

**Status/priority:** PLANNED / P1. **Depends on:** E02, H01, M08. **Requirements:** RQ05, RQ26, RQ28, RQ32.

**Files and ownership:**

- **modify**: tests/web_quality/20260906-0606-replay-guide.md
- **create**: tools/verification/environment.ml
- **create**: tests/dx/setup_replay_test.ml
- **modify**: tools/README.md

**Interfaces:** Operation `dx.replay`. Consumes: Explicit acceptance fixture below and the referenced candidate/manifest inputs. Produces: Observed receipt/effect/artifact fields in expect; unavailable required tools/targets are nonpassing. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "H03-regression",
  "given": {
    "checkout": "clean_isolated_jj",
    "scratch_inputs_present": false,
    "dependencies": "locked",
    "requested": "selected_unit_and_browser_case"
  },
  "when": [
    {
      "op": "dx.replay"
    }
  ],
  "expect": {
    "uses_hidden_tmp_paths": false,
    "commands_documented": true,
    "missing_dependency_diagnostic": "explicit",
    "execution_receipts_generated": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Replace historical scratch-path assumptions with repository-relative inputs or explicit arguments, locked tool versions and small executable examples.
2. Document exact cwd/commands/env requirements for Gleam Erlang, supported JavaScript modules, Hermes/formal workers, native builds and browser fixtures; actual package CLI behavior controls command syntax.
3. Run clean isolated setup/build/test/replay and record time/error/repair outcomes; expose actionable diagnostics, source links and example-driven API guidance.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task H03
```

Planned E02 runner plus the task-specific verification adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** A clean admitted environment reproduces selected tests without hidden /tmp history; dependency absence fails with an actionable diagnostic rather than a false pass. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.


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

