# 20260906-0817- Release, rollback, evidence and admission Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task by task. Checkboxes track execution. Inline work is the default; this plan does not dispatch subagents.

**Goal:** Complete and admit the UOS web/wiki/Zettelkasten/KM system, denotational DMC/TCM and L0-L9 atlas, FPP/SysML Gleam actor ecology, and full versioned C3I-derived Zenoh communication with observable verification.

**Architecture:** This subsystem is implemented through the task interfaces below and integrated through the shared evidence ledger. Existing source behavior is reused only after discriminating tests; every model/native/browser observation retains its exact candidate.

**Tech Stack:** Gleam/OTP and applicable Gleam JavaScript, Lustre/Wisp, Hermes OCaml/Bos/Dune, bounded native Rust/Rustler/Zenoh, Z3/Lean/Gospel/Quint, real browser automation, standalone Jujutsu. Exact installed/resolved pins are recorded by E01/M08/Z01; a source manifest version is not a runtime receipt.

**Spec:** [Unified AGY-to-Codex specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0606-uos-agy-codex-unified-master-prompt.md) and [Reviewed handover](http://nas-1.tail55d152.ts.net:4100/files/docs/zk/20260906-0606-agy-handover-understanding-and-actor-ecology-plan.md).

**Status:** PLAN READY; implementation tasks and their acceptance cases are PLANNED/UNRUN. Generated from synchronized host observation 2026-09-06T08:04:17Z. [This document](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0817-uos-implementation-08-release-and-admission.md).

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
| R01 | Assemble a reproducible release and verify reversible cutover | E08, V07, H02, H03 |
| R02 | Run final candidate gates and independent review | R01, V02, V03, V04, V05, V06, V07, H02 |
| R03 | Publish complete journals, handover and admitted status | R02 |

## Execution contract

Read the master plan's harness, build/replay, source admission, conformance closure and browser-cycle sections before execution. The fixtures below are actual acceptance specifications to implement, not recorded execution results. Each adapter must observe the named production path; the expected object stays in the assertion engine. Expand every documented action/error/property/target obligation beyond the minimum example. Conformance parents generate deterministic leaf tasks from their pinned source inventory and remain open until every required leaf passes.

## Task R01: Assemble a reproducible release and verify reversible cutover

**Status/priority:** PLANNED / P1. **Depends on:** E08, V07, H02, H03. **Requirements:** RQ16, RQ27, RQ31, RQ32.

**Files and ownership:**

- **modify**: apps/cepaf_gleam/src/cepaf_gleam/release.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/ha/otp_release.gleam
- **create**: tools/verification/release_manifest.ml
- **create**: tests/release/cutover_test.ml

**Interfaces:** Operation `release.prepare`. Consumes: Explicit acceptance fixture below and the referenced candidate/manifest inputs. Produces: Observed receipt/effect/artifact fields in expect; unavailable required tools/targets are nonpassing. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "R01-regression",
  "given": {
    "candidate": "final-jj",
    "runtime_receipt": "older-jj",
    "rollback_bundle": "verified",
    "deployment_authorized": false
  },
  "when": [
    {
      "op": "release.prepare"
    }
  ],
  "expect": {
    "deploy": false,
    "admitted": false,
    "reason": "stale_runtime_receipt",
    "rollback_ready": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Create release artifacts with locked sources/dependencies/native libraries/feature flags, schema/model/atlas versions, content snapshots, routes and tool receipts.
2. Exercise staged isolated cutover, canary health and rollback with real payload/permission/trace compatibility; rollback covers native library/schema/actor state, not only code.
3. Prepare the exact change, health criteria, rollback triggers and evidence for any deployment approval required by the current authorized scope. Do not invent approval or send third-party messages.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task R01
```

Planned E02 runner plus the task-specific verification adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Release is reproducible and rollback exercised; stale/missing evidence prevents deployment/admission; any required approval concerns a concrete prepared candidate. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task R02: Run final candidate gates and independent review

**Status/priority:** PLANNED / P1. **Depends on:** R01, V02, V03, V04, V05, V06, V07, H02. **Requirements:** RQ05, RQ06, RQ18, RQ23, RQ30, RQ31, RQ33, RQ35.

**Files and ownership:**

- **create**: tools/verification/admission.ml
- **create**: tests/release/admission_test.ml
- **modify**: tools/uos/src/main.gleam

**Interfaces:** Operation `release.admit`. Consumes: Explicit acceptance fixture below and the referenced candidate/manifest inputs. Produces: Observed receipt/effect/artifact fields in expect; unavailable required tools/targets are nonpassing. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

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
  "when": [
    {
      "op": "release.admit"
    }
  ],
  "expect": {
    "admitted": false,
    "missing_cases": 1,
    "signature_credit": false
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Freeze the final candidate/build/content/model/dependency manifest and re-run all affected formal/runtime/browser/profile/role/edge cases with complete denominators.
2. Require independent human or separately identified reviewer evidence under the existing governance policy; never generate another reviewer's signature or infer review from a certificate heading.
3. Check all layers, API clauses, routes/components/cycles, source-preservation/licensing, metrics, skills and required integrations; serialize Jujutsu integration and reject any drift.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task R02
```

Planned E02 runner plus the task-specific verification adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Zero required missing/failed/skipped/unknown/stale obligations; actual runtime and formal keys match candidate; all reviews are authentic and attributable. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task R03: Publish complete journals, handover and admitted status

**Status/priority:** PLANNED / P1. **Depends on:** R02. **Requirements:** RQ31, RQ32, RQ34.

**Files and ownership:**

- **create**: tools/verification/completion_report.ml
- **modify**: HANDOVER_TO_CODEX.md
- **modify**: docs/zk/moc-agent-handover.md
- **modify**: governance/capability-inventory/verification-tracking.toml

**Interfaces:** Operation `release.publish_status`. Consumes: Explicit acceptance fixture below and the referenced candidate/manifest inputs. Produces: Observed receipt/effect/artifact fields in expect; unavailable required tools/targets are nonpassing. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

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
  "when": [
    {
      "op": "release.publish_status"
    }
  ],
  "expect": {
    "status": "ADMITTED",
    "journal_sections": 13,
    "trace_chain_complete": true,
    "old_claims_preserved_as_history": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Generate timestamped source/test/coverage/conformance/atlas/actor/edge/page-cycle reports and the exact 13-section completion journal from the validated ledger.
2. Publish full Tailnet links and retrievable artifact manifests, update root handover/MOCs/planning projections and show admitted state only after R02.
3. Record final Jujutsu change/commit/operation/bookmark provenance without Git mutations; retain old evidence/certificates as historical and describe any scoped exclusions explicitly.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task R03
```

Planned E02 runner plus the task-specific verification adapter. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** All delivered reports and media resolve, the complete evidence chain is inspectable, and completion state exactly matches the admitted candidate. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.


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

