# Apps Subsystem (`apps/`)

- **Ownership & Language Authority**: Pure Gleam / OTP.
- **Scope**: Live operational applications, agent swarm orchestration, CEPAF coordinator (`apps/cepaf_gleam`), TUI, and operational API endpoints.
- **Invariants**: All supervision, state machines, lease management, and high-level routing live here. Zero native blocking code.

## `apps/uos_tui` (added 20260906-2150-)
- **Role**: Pure-Gleam terminal UI library and reference cockpit (Textual-referenced TEA on OTP). See ADR-061 and `docs/design/20260906-2150-uos-tui-gleam-library-textual-reference-design.md`.
- **Run**: `cd apps/uos_tui && gleam test` (116 tests), `gleam run` (live), `gleam run -- snapshot`, `gleam run -- dictionary`.
- **Boundaries**: 0 NIFs; 6 pure-Erlang externals (`shell`, `io`, `erlang`, `calendar`); emits `Intent` values, executes nothing.

## Work streams (split 20260907-0950-)

Per the operator directive to "split and tui and swarm work into separate work streams", the monolithic `apps/uos_tui` has been split into two independent packages:

### `apps/uos_tui` (TUI Library)
- **Role**: Pure-Gleam terminal UI library with reusable widgets and layout engine (Textual-referenced TEA on OTP).
- **Modules**: 21 (geometry, style, segment, frame, layout, event, widget, render, app, headless, live, aspects, fprime, ontology, palette, markdown, diff, html, telemetry, features, gallery).
- **Tests**: 198 (18 test modules), 0 warnings.
- **Reference App**: `gallery` demo (replaces the cockpit as the library's reference application).
- **FFI**: `uos_tui_ffi.erl` — 8 functions (raw mode, size, read_chars, write, monotonic_micros, utc_iso8601, file_read, list_dir).
- **Run**: `cd apps/uos_tui && gleam test` (tests), `gleam run` (gallery demo), `gleam run -- snapshot` (snapshot), `gleam run -- dictionary` (feature dictionary).
- **See also**: ADR-061, `docs/design/20260906-2150-uos-tui-gleam-library-textual-reference-design.md`.

### `apps/uos_swarm` (Hive-Mind Application)
- **Role**: Hive-mind message board, agent coordination, ACL, system audit, and agent runtime using the uos_tui library.
- **Modules**: 16 (swarm, board, coord, manager, acl, holon, agent_runtime, system_audit, stpa, fmea, ooda, tps, cockpit, openrouter_worker, session_sync, herdr).
- **Tests**: 271 (14 test modules), 0 warnings.
- **Dependency**: Path dependency on `uos_tui` (`uos_tui = { path = "../uos_tui" }`).
- **FFI**: `uos_swarm_ffi.erl`, `uos_openrouter_ffi.erl`, `session_sync_ffi.erl`, `uos_herdr_ffi.erl`.
- **Artefacts**: Swarm ledger JSON, board JSONL, ACL files, audit, KPIs, hive, controls, lexicon under `apps/uos_swarm/swarm/` and `apps/uos_swarm/generated/`.
- **Run**: 
  - `cd apps/uos_swarm && gleam test` (tests)
  - `gleam run -- board validate swarm/20260907-0440-swarm-board.jsonl` (board validation)
  - `gleam run -- audit-system` (system audit)
  - `gleam run -- manager-run`, `gleam run -- hive`, `gleam run -- holon`, etc. (CLIs)
  - `gleam run -m openrouter_worker_cli -- probe` (OpenRouter advisory)
  - `gleam run -m session_sync_cli -- status` (session sync status)
  - `gleam run -m herdr_sync_cli -- status` (herald sync status)
- **See also**: ADR-062, `docs/design/20260907-0537-adr-062-uos-tui-swarm-hive-mind-message-board-coordination-acl-and-zenoh-infra-design.md`, ADR-063, `docs/journal/20260907-0950-uos-tui-swarm-work-stream-split-journal.md`.

### Ownership & Booking
- **Fable (L0 authority)**: Design, board, coord, manager, agent_runtime, system_audit, acl, holon, openrouter_worker, cockpit, aspects; both package CLIs and integration gate.
- **Codex**: session_sync, herdr modules (immutable; imported verbatim in swarm).
- **Bookmarks**: `integration/uos-tui` (T, `tmwpokqm`), `integration/uos-swarm` (S, `wyowkrpw`, child of T).
- **Workspaces**: `.uos-workspaces/split-tui` and `.uos-workspaces/split-swarm` (worker sandboxes; deleted after merge).

### Metrics
- **Total tests**: 469 (198 + 271), 0 compiler warnings across both packages.
- **Board**: 187 messages valid; 1 causal gap documented.
- **Boundary violations**: 0 (features.gleam fixed: now parameterized, no swarm imports).

---

## Historical: Swarm & Hive Mind (Execution Record)

**15-agent swarm** (20260907-0537-): Round 1: 15 agents (10 Sonnet + 5 Haiku) in jj sibling workspaces, 11/11 PASS first attempt; round H2 (Codex P1 hardening): 5 Sonnet workers, 400 tests, 0 warnings; see ADR-062 and `docs/plans/20260907-0440-uos-tui-swarm-15-agent-multilayer-plan.md`.

**OpenRouter advisory worker** (added 20260907-0900-): `gleam run -m openrouter_worker_cli -- probe | models | estimate <model> <max_tokens> | review-lease-invariant [model] [--paid] [out.json]`; allowlisted exact models with live price ceilings, ≤ 512 tokens, ≤ USD 0.02, 30 s, no tools, free-only default, fail closed without `OPENROUTER_API_KEY`.

**Zenoh infra**: `ops/zenoh/` runbook; router `c3i-zenoh-router-1`, REST :8080, storages on `c3i/a2a/**` and `uos/tui/**`.

**vm-1 evidence copy**: sanitized read-only snapshot of C3I + Indrajaal at `/home/an/dev/ver/c3i-vm1-20260907-0559` (receipt `governance/sources/20260907-0604-vm1-c3i-indrajaal-sanitized-snapshot-receipt.json`); use it for reference only, nothing enters `apps/` without two-key verification.
