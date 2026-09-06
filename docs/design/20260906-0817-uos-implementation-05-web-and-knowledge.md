# 20260906-0817- Web, wiki, Zettelkasten and knowledge experience Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task by task. Checkboxes track execution. Inline work is the default; this plan does not dispatch subagents.

**Goal:** Complete and admit the UOS web/wiki/Zettelkasten/KM system, denotational DMC/TCM and L0-L9 atlas, FPP/SysML Gleam actor ecology, and full versioned C3I-derived Zenoh communication with observable verification.

**Architecture:** This subsystem is implemented through the task interfaces below and integrated through the shared evidence ledger. Existing source behavior is reused only after discriminating tests; every model/native/browser observation retains its exact candidate.

**Tech Stack:** Gleam/OTP and applicable Gleam JavaScript, Lustre/Wisp, Hermes OCaml/Bos/Dune, bounded native Rust/Rustler/Zenoh, Z3/Lean/Gospel/Quint, real browser automation, standalone Jujutsu. Exact installed/resolved pins are recorded by E01/M08/Z01; a source manifest version is not a runtime receipt.

**Spec:** [Unified AGY-to-Codex specification](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0606-uos-agy-codex-unified-master-prompt.md) and [Reviewed handover](http://nas-1.tail55d152.ts.net:4100/files/docs/zk/20260906-0606-agy-handover-understanding-and-actor-ecology-plan.md).

**Status:** PLAN READY; implementation tasks and their acceptance cases are PLANNED/UNRUN. Generated from synchronized host observation 2026-09-06T08:04:17Z. [This document](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20260906-0817-uos-implementation-05-web-and-knowledge.md).

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
| W01 | Close route, page, component and UI-state manifests | E04, E08 |
| W02 | Make Markdown/HTML rendering and source display safe and faithful | W01, E06 |
| W03 | Implement semantic links, anchors, redirects and navigation algebra | W01, M06 |
| W04 | Complete the uniform shell, navigation and truthful checklist | W02, W03, E03 |
| W05 | Complete wiki parsing, transclusion and content lifecycle | W02, W03, M03, E07 |
| W06 | Integrate ZK, MOCs, living ontology and graph integrity | W05, M06, M07, M05 |
| W07 | Implement measurable search, discovery and information architecture | W06, M06 |
| W08 | Connect all dashboards to actual system observations | W04, M07, A06, Z12 |
| W09 | Complete responsive, accessible design and task-focused UX/CX | W04, W05, W07, W08 |

## Execution contract

Read the master plan's harness, build/replay, source admission, conformance closure and browser-cycle sections before execution. The fixtures below are actual acceptance specifications to implement, not recorded execution results. Each adapter must observe the named production path; the expected object stays in the assertion engine. Expand every documented action/error/property/target obligation beyond the minimum example. Conformance parents generate deterministic leaf tasks from their pinned source inventory and remain open until every required leaf passes.

## Task W01: Close route, page, component and UI-state manifests

**Status/priority:** PLANNED / P0. **Depends on:** E04, E08. **Requirements:** RQ23, RQ25, RQ35.

**Files and ownership:**

- **create**: apps/cepaf_gleam/src/cepaf_gleam/knowledge/routes.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/knowledge/components.gleam
- **create**: tools/verification/route_manifest.ml
- **modify**: apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam
- **create**: apps/cepaf_gleam/test/route_manifest_test.gleam

**Interfaces:** Operation `web.manifest`. Consumes: Exact page/content/action fixture below; route/component manifest and pure reference are version-bound inputs. Produces: DOM/AX/network/state observations in expect, not HTTP status or screenshot count alone. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "W01-regression",
  "given": {
    "router_routes": [
      "/wiki",
      "/zk",
      "/ux-audit"
    ],
    "document_links": [
      "/ux-auditor"
    ],
    "crawl_cap": 2,
    "dynamic_document_instances": 20
  },
  "when": [
    {
      "op": "web.manifest"
    }
  ],
  "expect": {
    "mismatch": [
      "/ux-auditor"
    ],
    "frontier_remaining": true,
    "whole_site_complete": false,
    "components_require_per_page_instances": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Extract routes from router AST/definitions and reconcile actual DOM/nav/MOCs, dynamic document IDs, query states, redirects, fragments and authorization variants.
2. Include every known baseline route and ten tensor-era routes plus new FPP/agent/evolution screens; never freeze the denominator at the earlier 46-page baseline.
3. Assign stable page/component/instance/state IDs and purpose/action/oracle/side-effect contracts; define canonical aliases/redirects and preserve unresolved crawl/auth frontiers.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task W01
```

Planned E02 runner; pure/web/browser adapter delivered with the task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Every reachable or specified route is accounted for; crawl caps and unvisited dynamic instances are visible; /ux-audit versus /ux-auditor is resolved deliberately. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task W02: Make Markdown/HTML rendering and source display safe and faithful

**Status/priority:** PLANNED / P0. **Depends on:** W01, E06. **Requirements:** RQ19, RQ21, RQ22, RQ24, RQ27.

**Files and ownership:**

- **modify**: apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam
- **modify**: apps/indrajaal_gleam_web/test/document_render_contract_test.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/markdown.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/knowledge/document_ast.gleam
- **create**: apps/cepaf_gleam/test/document_security_test.gleam

**Interfaces:** Operation `web.render`. Consumes: Exact page/content/action fixture below; route/component manifest and pure reference are version-bound inputs. Produces: DOM/AX/network/state observations in expect, not HTTP status or screenshot count alone. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "W02-regression",
  "given": {
    "markdown": "[run](javascript:alert(1))\\n\\n<script>window.__uos_probe=1</script>",
    "mode": "rendered_then_raw"
  },
  "when": [
    {
      "op": "web.render"
    }
  ],
  "expect": {
    "script_executed": false,
    "unsafe_protocol_active": false,
    "raw_source_preserved": true,
    "newline_semantics_preserved": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Reconcile the earlier newline/fixture repair with the current renderer; preserve its passing regressions while replacing unsafe HTML/protocol handling.
2. Parse the declared dialect into a typed AST, apply reviewed sanitization/CSP rules, escape by context, bound nesting/input and render through safe Gleam HTML primitives.
3. Test CommonMark/approved wiki extensions, nested lists/code/tables, Unicode/quotes/newlines, raw/rendered round trips, XSS payloads, malformed AST and source toggle focus/selection.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task W02
```

Planned E02 runner; pure/web/browser adapter delivered with the task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Admitted dialect fixtures render faithfully; unsafe markup cannot execute; raw source is exact and safely displayed; prior renderer regressions remain covered. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task W03: Implement semantic links, anchors, redirects and navigation algebra

**Status/priority:** PLANNED / P0. **Depends on:** W01, M06. **Requirements:** RQ12, RQ19, RQ21, RQ25.

**Files and ownership:**

- **create**: apps/cepaf_gleam/src/cepaf_gleam/knowledge/links.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/knowledge/navigation.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/verification/graph_verification.gleam
- **create**: apps/cepaf_gleam/test/navigation_laws_test.gleam
- **create**: tests/web_quality/link_probe.ml

**Interfaces:** Operation `web.resolve_link`. Consumes: Exact page/content/action fixture below; route/component manifest and pure reference are version-bound inputs. Produces: DOM/AX/network/state observations in expect, not HTTP status or screenshot count alone. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "W03-regression",
  "given": {
    "link": "/docs/note.md#missing",
    "response_status": 200,
    "rendered_title": "Fallback home",
    "anchors": [
      "intro"
    ]
  },
  "when": [
    {
      "op": "web.resolve_link"
    }
  ],
  "expect": {
    "valid_target": false,
    "reason_codes": [
      "semantic_destination_mismatch",
      "missing_anchor"
    ],
    "http_200_credit": false
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Resolve relative/absolute Tailnet links, fragments, encoding, transclusions, downloads, redirects and query parameters against a typed route registry; detect loops and fallback pages.
2. Implement navigation history/context/focus restoration and graph algorithms for reachability, SCCs, broken backlinks, orphan detection and shortest useful paths with independent oracles.
3. Check external sources with bounded concurrency/rate limits and GET semantics where HEAD is misleading; separate temporary network failure, auth requirements and confirmed broken targets.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task W03
```

Planned E02 runner; pure/web/browser adapter delivered with the task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Every required link reaches its intended semantic destination and anchor; legitimate graph cycles remain supported; Back/Forward laws hold under declared history assumptions. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task W04: Complete the uniform shell, navigation and truthful checklist

**Status/priority:** PLANNED / P1. **Depends on:** W02, W03, E03. **Requirements:** RQ23, RQ25, RQ26, RQ31, RQ35.

**Files and ownership:**

- **modify**: apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/site_shell.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/verification_checklist.gleam
- **create**: apps/cepaf_gleam/test/site_shell_contract_test.gleam

**Interfaces:** Operation `web.shell`. Consumes: Exact page/content/action fixture below; route/component manifest and pure reference are version-bound inputs. Produces: DOM/AX/network/state observations in expect, not HTTP status or screenshot count alone. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "W04-regression",
  "given": {
    "route": "/wiki",
    "viewport": [
      390,
      844
    ],
    "keyboard_only": true,
    "runtime_receipt": "missing",
    "formal_receipt": "passed"
  },
  "when": [
    {
      "op": "web.shell"
    }
  ],
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

- [ ] **Implement the named behavior and its independent oracle.**

1. Implement shared grouped sidebar, top status/FQDN/copy control, breadcrumbs, rendered/raw toggle, Prev/Next and footer with route-appropriate semantics.
2. Render all eighteen checkpoints in five expandable domains using the evidence ledger; derive state and freshness from receipts and show missing/failing checks.
3. Exercise shell integration on every containing page, including small viewports/zoom, long names, keyboard/touch, copy feedback, navigation restoration and error states.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task W04
```

Planned E02 runner; pure/web/browser adapter delivered with the task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Every screen/document view has the complete shell/checklist with actual state; shared component unit tests do not replace each-page integration evidence. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task W05: Complete wiki parsing, transclusion and content lifecycle

**Status/priority:** PLANNED / P1. **Depends on:** W02, W03, M03, E07. **Requirements:** RQ03, RQ19, RQ21, RQ25, RQ27.

**Files and ownership:**

- **modify**: apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/wiki_transclusion_engine.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/knowledge/wiki.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/knowledge/transclusion.gleam
- **create**: apps/cepaf_gleam/test/wiki_semantics_test.gleam

**Interfaces:** Operation `wiki.expand`. Consumes: Exact page/content/action fixture below; route/component manifest and pure reference are version-bound inputs. Produces: DOM/AX/network/state observations in expect, not HTTP status or screenshot count alone. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "W05-regression",
  "given": {
    "documents": {
      "a": "[[wiki:b]]",
      "b": "[[wiki:a]]"
    },
    "start": "a",
    "depth_limit": 8
  },
  "when": [
    {
      "op": "wiki.expand"
    }
  ],
  "expect": {
    "result": "TransclusionCycle",
    "cycle": [
      "a",
      "b",
      "a"
    ],
    "bounded": true,
    "source_documents_unchanged": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Implement versioned document IDs/frontmatter, AST parsing, wiki/ZK links, transclusion expansion, source provenance, invalidation and safe rendering against original Hermes oracle fixtures.
2. Bound cycles/depth/size, define missing/forbidden targets and partial content errors, and preserve origin/source spans through nested expansion.
3. Route content edits through authorized versioned transactions with conflict/rollback behavior; test stale edits, denied transclusions and index invalidation.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task W05
```

Planned E02 runner; pure/web/browser adapter delivered with the task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** All selected wiki cases have semantic Gleam coverage; transclusion cannot loop, leak forbidden content or lose provenance; unauthorized edits produce zero effects. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task W06: Integrate ZK, MOCs, living ontology and graph integrity

**Status/priority:** PLANNED / P1. **Depends on:** W05, M06, M07, M05. **Requirements:** RQ11, RQ12, RQ19, RQ25, RQ32.

**Files and ownership:**

- **create**: apps/cepaf_gleam/src/cepaf_gleam/knowledge/zettelkasten.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/knowledge/ontology.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/knowledge/corpus.gleam
- **create**: apps/cepaf_gleam/test/knowledge_graph_integrity_test.gleam

**Interfaces:** Operation `knowledge.index`. Consumes: Exact page/content/action fixture below; route/component manifest and pure reference are version-bound inputs. Produces: DOM/AX/network/state observations in expect, not HTTP status or screenshot count alone. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "W06-regression",
  "given": {
    "notes": [
      {
        "id": "n1",
        "links": [
          "n2"
        ]
      },
      {
        "id": "n2",
        "links": []
      }
    ],
    "rename": {
      "from": "n2",
      "to": "n3"
    },
    "source_snapshot": "immutable"
  },
  "when": [
    {
      "op": "knowledge.index"
    }
  ],
  "expect": {
    "backlinks_consistent": true,
    "redirect_or_reference_update_recorded": true,
    "provenance_retained": true,
    "original_source_changed": false
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Unify Hermes wiki AST, ZigVM ZK/MOCs and C3I living ontology as typed, bidirectionally linked projections with stable identities and immutable source bindings.
2. Implement backlink/rename/alias/orphan/duplicate checks, schema/shape constraints and explicit timestamp/fractal-tag rules; archive revisions rather than rewriting external originals.
3. Test index rebuild equivalence, incremental invalidation, conflicting edits, missing nodes, schema migration and observer-versus-writer separation.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task W06
```

Planned E02 runner; pure/web/browser adapter delivered with the task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Knowledge graph updates preserve stable identity/provenance and declared invariants; all MOC and ontology references resolve or show named gaps. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task W07: Implement measurable search, discovery and information architecture

**Status/priority:** PLANNED / P1. **Depends on:** W06, M06. **Requirements:** RQ12, RQ19, RQ21, RQ26.

**Files and ownership:**

- **create**: apps/cepaf_gleam/src/cepaf_gleam/knowledge/search.gleam
- **create**: apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/knowledge_search.gleam
- **create**: apps/cepaf_gleam/test/knowledge_search_test.gleam

**Interfaces:** Operation `knowledge.search`. Consumes: Exact page/content/action fixture below; route/component manifest and pure reference are version-bound inputs. Produces: DOM/AX/network/state observations in expect, not HTTP status or screenshot count alone. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "W07-regression",
  "given": {
    "queries": [
      "typed navigation",
      ""
    ],
    "corpus": "judged_small_corpus",
    "filters": {
      "tag": "wiki"
    },
    "forbidden_document": "secret-note"
  },
  "when": [
    {
      "op": "knowledge.search"
    }
  ],
  "expect": {
    "forbidden_results": 0,
    "empty_state_has_next_action": true,
    "filter_state_survives_back": true,
    "ranking_compared_to_judgments": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Create a judged corpus and task-based information architecture; implement deterministic indexing/tokenization/filtering/ranking with explicit tie-breakers and independent small reference results.
2. Provide context/backlinks, facets, empty/loading/error states and keyboard navigation; protect authorization through both search results and snippets.
3. Measure retrieval quality and find/open/return workflows; document algorithm complexity and justify optional vector/similarity methods with actual corpus evidence.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task W07
```

Planned E02 runner; pure/web/browser adapter delivered with the task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Search correctness, access filtering and context preservation pass; relevance/UX claims have task/judgment denominators rather than arbitrary quality scores. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task W08: Connect all dashboards to actual system observations

**Status/priority:** PLANNED / P1. **Depends on:** W04, M07, A06, Z12. **Requirements:** RQ11, RQ23, RQ26, RQ33, RQ34, RQ35.

**Files and ownership:**

- **modify**: apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/fpp_topology_view.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/fpp_atlas_view.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/fpp_agent_view.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/zenoh_mesh.gleam
- **modify**: apps/indrajaal_gleam_web/src/indrajaal_gleam_web.gleam
- **create**: apps/cepaf_gleam/test/dashboard_observation_test.gleam

**Interfaces:** Operation `web.dashboard`. Consumes: Exact page/content/action fixture below; route/component manifest and pure reference are version-bound inputs. Produces: DOM/AX/network/state observations in expect, not HTTP status or screenshot count alone. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "W08-regression",
  "given": {
    "page": "/tensor-atlas",
    "runtime_state": "disconnected",
    "proof_receipt": "stale",
    "metric_samples": []
  },
  "when": [
    {
      "op": "web.dashboard"
    }
  ],
  "expect": {
    "connected_badge": false,
    "admitted_badge": false,
    "metric_value": "unavailable",
    "recovery_action_visible": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Connect existing tensor/SRE/UX/KM/FPP/agent/Zenoh/brain pages to live typed projections and ledger evidence; remove generated scores used as proof of operational health.
2. Render loading, partial, stale, denied, disconnected and recovery states consistently across web/TUI/API surfaces with preserved correlation.
3. Bind every displayed action to an intent/authorization/model/test contract and update page/component manifests whenever a route/control is added.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task W08
```

Planned E02 runner; pure/web/browser adapter delivered with the task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** No dashboard emits green operational credit from a constant/model-only result; every action has real observable behavior and appropriate failure presentation. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.

## Task W09: Complete responsive, accessible design and task-focused UX/CX

**Status/priority:** PLANNED / P1. **Depends on:** W04, W05, W07, W08. **Requirements:** RQ23, RQ24, RQ26.

**Files and ownership:**

- **create**: apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/design_tokens.gleam
- **modify**: apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/site_shell.gleam
- **create**: tests/web_quality/experience_tasks.json
- **create**: apps/cepaf_gleam/test/ui_state_contract_test.gleam

**Interfaces:** Operation `web.experience`. Consumes: Exact page/content/action fixture below; route/component manifest and pure reference are version-bound inputs. Produces: DOM/AX/network/state observations in expect, not HTTP status or screenshot count alone. Registry: tests/acceptance/registry.ml; resource/error/observation schema: tests/acceptance/contract.ml, both created by E02. This is a proposed interface contract, not a claim that the adapter exists today.

- [ ] **Red: register this concrete regression and observe the expected discrepancy.** Decode the following fixture strictly, bind the operation to the real production path, and keep expected results in the assertion interpreter. Include a positive control and the listed negative case. Missing adapter/tool is ERROR/UNRUN, not a semantic pass or proof of a reproduced application defect.

```json
{
  "id": "W09-regression",
  "given": {
    "journey": "find-note-follow-backlink-inspect-source-return",
    "viewport": [
      320,
      640
    ],
    "zoom_percent": 200,
    "keyboard_only": true,
    "reduced_motion": true,
    "theme": "dark"
  },
  "when": [
    {
      "op": "web.experience"
    }
  ],
  "expect": {
    "task_completed": true,
    "focus_restored": true,
    "content_loss": false,
    "clipping": false,
    "error_recovery_discoverable": true
  }
}
```

- [ ] **Implement the named behavior and its independent oracle.**

1. Define shared typography/spacing/color/state/motion tokens with semantic component rules and clear information hierarchy; implement long/localized text and mobile/zoom reflow.
2. Specify UX/CX goals/signals/measures for supported journeys, failure understanding and recovery, with real participant/task denominators where human feedback is required.
3. Run visual/accessibility/task reviews and repair observable issues; automated scores, synthetic users or screenshot equality alone cannot certify subjective experience.

- [ ] **Green and refactor: run the real package tests plus this acceptance case.**

```text
Working directory: /home/an/NAS-setup/uos
ocaml tests/acceptance/run.ml --backlog governance/planning/20260906-0817-uos-full-implementation-backlog.json --task W09
```

Planned E02 runner; pure/web/browser adapter delivered with the task. The command is the planned replay interface. A successful task receipt requires actual execution at the current candidate, all expected observations and no missing required cases. Use the package-specific build/test commands in the master plan; run the smallest affected suite, then integration checks justified by changed call paths. Record input/source/tool/build hashes, exit status and artifacts. Production code must never read fixture expected results.

- [ ] **Review and checkpoint:** Required layouts, input methods and states meet the documented criteria; measured task evidence supports experience claims; unavailable human/assistive feedback remains explicit. Resolve test survivors/gaps, update child clause/API rows, regenerate affected trace/atlas/page evidence and journal entries, and make a serialized Jujutsu checkpoint in the owned workspace. Do not modify other writers' changes or publish an admission certificate here.


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

