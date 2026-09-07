# 20260907-0950- ADR-063: UOS TUI and Swarm Work-Stream Split
#fractal-l0 #fractal-l2 #fractal-l4 #fractal-l5 #zero-muda #tailscale-web #km-triad #uos-tui #swarm #jujutsu

- **ADR ID**: ADR-063
- **Title**: UOS TUI and Swarm Work-Stream Split
- **Timestamp**: `20260907-0950-`
- **Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260907-0950-adr-063-uos-tui-and-swarm-work-stream-split.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/zk/20260907-0950-adr-063-uos-tui-and-swarm-work-stream-split.md)
- **Transclusions**: `[[zk:20260906-2150-adr-061-uos-tui-gleam-library-textual-reference]]` `[[zk:20260907-0537-adr-062-uos-tui-swarm-hive-mind-message-board-coordination-acl-and-zenoh-infra]]` `[[zk:20260905-1801-moc-uos-unified-master]]` `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`

## Comprehensive Verification Checklist (SC-CHECKLIST-001)
<details><summary>18 checkpoints (ADR status)</summary>
CHK-01 PASS · CHK-02 PASS · CHK-03 PASS · CHK-04 PASS · CHK-05 PASS · CHK-06 PASS · CHK-07 PASS · CHK-08 DECLARED · CHK-09 DECLARED · CHK-10 DECLARED · CHK-11 DECLARED · CHK-12 PASS · CHK-13 DECLARED · CHK-14 DECLARED · CHK-15 DECLARED · CHK-16 PASS · CHK-17 DECLARED · CHK-18 PASS
</details>

## Status

**ACCEPTED** — Architectural decision executed at change T (`integration/uos-tui`/`tmwpokqm`) and S (`integration/uos-swarm`/`wyowkrpw`). Both packages build (0 warnings), both test suites pass (469 tests), boundary violations fixed, coordination lease transferred, tri-sovereign boundary review pending.

## Context

Prior to this ADR, `apps/uos_tui` contained two distinct concerns with different review cadences and ownership:
1. **Pure TUI library**: 17 core modules (geometry, style, segment, frame, layout, event, widget, render, app, headless, live, aspects, fprime, ontology, palette, markdown, diff, html, telemetry) defining a reusable terminal UI abstraction on OTP.
2. **Hive-mind swarm application**: 16 modules (swarm, board, coord, manager, acl, holon, agent_runtime, system_audit, stpa, fmea, ooda, tps, cockpit, openrouter_worker, session_sync, herdr) implementing agent coordination, message board, ACL, and system audit.

The two concerns were coupled by:
- A single `gleam.toml` and shared CLI entry point.
- A boundary violation: `features.gleam` (TUI-side) imported `cockpit` (swarm-side) to count screens.
- Interleaved test suites and FFI modules.
- Shared generation artefacts (ledger JSON, board JSONL, ACL files, audit, KPIs).

This coupling blocked independent review, testing, and deployment of the TUI library and swarm application, and made it difficult for multiple agents to work on the two streams in parallel.

## Decision

**Split `apps/uos_tui` and `apps/uos_swarm` into two independent packages with unidirectional dependency.**

### Package Structure

| Package | Path | Ownership | Modules | Tests | FFI | Role |
|---|---|---|---|---|---|---|
| **uos_tui** | `apps/uos_tui/` | Fable (L0 authority) | 21 TUI library | 198 (18 test modules) | `uos_tui_ffi.erl` (8 fns: raw, size, read, write, micros, iso8601, file_read, list_dir) | Pure Gleam terminal UI library and reference gallery demo |
| **uos_swarm** | `apps/uos_swarm/` | Fable + Codex (session_sync*, herdr*) | 16 swarm & coord | 271 (14 test modules) | `uos_swarm_ffi.erl`, `uos_openrouter_ffi.erl`, `uos_herdr_ffi.erl`, `session_sync_ffi.erl` | Hive-mind message board, agent coordination, ACL, audit, agent kernel |

### Dependency Direction

```
apps/uos_swarm
    ├── depends on apps/uos_tui by path
    │   uos_tui = { path = "../uos_tui" }
    │
    └── imports: uos_tui/geometry, uos_tui/render, uos_tui/palette, etc.

apps/uos_tui
    └── zero imports from apps/uos_swarm (no reverse dependency)
```

**Invariant**: `apps/uos_tui` is standalone and buildable without `apps/uos_swarm`.

### Boundary Fix

The boundary violation `features.gleam` → `cockpit` was eliminated by parameterizing the feature sheet:
- **Before**: `features.gleam` instantiated the cockpit to count screens; tight coupling.
- **After**: `features.sheet(bindings: List(#(String, String)))` accepts explicit bindings; the swarm CLI supplies the binding list.

Result: `features.gleam` remains in `apps/uos_tui` and imports no swarm module.

### Ownership & Responsibilities

| Domain | Owner | Modules | Authority |
|---|---|---|---|
| **TUI Library Core** | Fable | geometry, style, segment, frame, layout, event, widget, render, app, headless, live, aspects, fprime, ontology, palette, markdown, diff, html, telemetry, features | Design & API contracts |
| **Gallery Demo** | Fable | gallery (reference app for the library; replaces the cockpit as the tui reference) | Lifecycle & versioning |
| **Board & Coordination** | Fable | board, coord, manager, acl, holon, agent_runtime, system_audit, stpa, fmea, ooda, tps, cockpit | Consensus & lease management |
| **AI Integration** | Fable | openrouter_worker, openrouter_ffi | Cost optimization & advisory |
| **Session Sync** | Codex | session_sync, session_sync_ffi | Persistence & state replication |
| **Herald** | Codex | herdr, herdr_ffi | Message relay & federation |

### CLI Entry Points

| Package | Entry | Commands |
|---|---|---|
| **uos_tui** | `apps/uos_tui/src/uos_tui.gleam` | snapshot, dictionary, features, features-json, <lifecycle-demos> |
| **uos_swarm** | `apps/uos_swarm/src/uos_swarm.gleam` | board (post, post-acl, ack, ingest, timeline, validate, reconcile, share, proof, retry, replay, inbox, forgery-probe), swarm, swarm-tui, tps-demo, dashboard, audit-system, manager-*, holon*, lexicon, hive, controls, lifecycle-machine, acl (grammar, parse), stpa, fmea, openrouter_worker_cli, session_sync_cli, herdr_sync_cli |

### Jujutsu Bookmarks & Workspaces

| Bookmark | Change ID | Base | Workspace | Content |
|---|---|---|---|---|
| `integration/uos-tui` (T) | `tmwpokqm` | post-sync main | `.uos-workspaces/split-tui` (worker; deleted) | TUI library + design docs |
| `integration/uos-swarm` (S) | `wyowkrpw` | child of T | `.uos-workspaces/split-swarm` (worker; deleted) | Swarm modules + artefacts + tests |
| `integration/main` | (session_sync lease) | S after split | `.uos-workspaces/split-int` (current) | Master integration branch |

### Tests & Build Quality

- **uos_tui**: 198 tests (18 test modules), 0 warnings, ~7s full run.
- **uos_swarm**: 271 tests (14 test modules), 0 warnings, ~12s full run.
- **Total**: 469 tests, 0 compiler warnings across both packages.
- **Board**: 187 messages valid; 1 causal gap documented (Codex message wiped by prior regeneration).

## Consequences

### Positive

1. **Independent review & deployment**: TUI library and swarm application can now be reviewed, tested, and deployed independently by different agents.
2. **Reduced coupling**: No transitive dependency from TUI library to swarm; pure library is now truly self-contained.
3. **Clearer ownership**: Fable owns both packages; Codex owns two swarm-specific modules (session_sync, herdr); boundaries are explicit.
4. **Faster iteration**: TUI library changes do not require re-testing the entire swarm; swarm changes do not block TUI releases.
5. **Parallel work**: Two agents can work on different streams without VCS contention; sibling workspaces + explicit bookmarks enable this.

### Negative

1. **Two CLIs to maintain**: Instead of one `uos_tui` CLI, there are now two (`uos_tui` and `uos_swarm`); documentation and user expectations must be updated.
2. **Artefact relocation**: Swarm artefacts moved from `apps/uos_tui/swarm/` to `apps/uos_swarm/swarm/`; scripts and references must be updated.
3. **Peer rebasing burden**: Existing feature branches (C01–C07) created before the split must rebase onto `integration/uos-swarm`; this is a one-time cost.
4. **Documentation debt**: Wiki paths, pipeline scripts, and reference apps (cockpit moved to swarm) require updates.

### Mitigation

- **Default workspace update** (deferred): When peers rebase, the default workspace will be updated to the new structure.
- **Comprehensive README**: A new "Work streams (split 20260907-0950-)" section explains the two packages, CLIs, and how to run them.
- **Coordination**: Session_sync lease and coordination board ensure no silent data loss during the transition.
- **Feature sheet as bridge**: The parameterized `features.sheet(bindings)` in the TUI library allows swarm to provide the binding list; this decouples the code without breaking the feature sheet's functionality.

## Related

- **ADR-061**: `[[zk:20260906-2150-adr-061-uos-tui-gleam-library-textual-reference]]` — Defines the uos_tui library architecture, Textual reference model, TEA on OTP, and F´ ontology.
- **ADR-062**: `[[zk:20260907-0537-adr-062-uos-tui-swarm-hive-mind-message-board-coordination-acl-and-zenoh-infra]]` — Defines the swarm hive-mind application, message board, coordination layer, and ACL.
- **Plan**: `[[wiki:20260907-0910-uos-tui-and-swarm-work-stream-split-plan]]` — Operator directive, module allocation, execution steps, and gates.
- **Routing Design**: `[[wiki:20260907-0925-uos-global-intelligence-routing-design]]` — Routing strategy used for parallel Sonnet workers (W-A, W-B) and Fable design authority.
- **Journal**: `[[wiki:20260907-0950-uos-tui-swarm-work-stream-split-journal]]` — Execution trace, metrics, gaps, and post-split status.
- **Master MOC**: `[[zk:20260905-1801-moc-uos-unified-master]]` — Master knowledge base integrating all architectural decisions.
- **Tri-Sovereign Coordination**: `[[wiki:20260907-0653-tri-agent-coordination]]` — Coordination policy for Fable, Codex, and AGY on shared work.

---

**Document Status**: Accepted, executed, awaiting tri-sovereign boundary review (AGY, Codex, Claude) and CHK-09 math gate validation.
