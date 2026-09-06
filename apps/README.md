# Apps Subsystem (`apps/`)

- **Ownership & Language Authority**: Pure Gleam / OTP.
- **Scope**: Live operational applications, agent swarm orchestration, CEPAF coordinator (`apps/cepaf_gleam`), TUI, and operational API endpoints.
- **Invariants**: All supervision, state machines, lease management, and high-level routing live here. Zero native blocking code.

## `apps/uos_tui` (added 20260906-2150-)
- **Role**: Pure-Gleam terminal UI library and reference cockpit (Textual-referenced TEA on OTP). See ADR-061 and `docs/design/20260906-2150-uos-tui-gleam-library-textual-reference-design.md`.
- **Run**: `cd apps/uos_tui && gleam test` (116 tests), `gleam run` (live), `gleam run -- snapshot`, `gleam run -- dictionary`.
- **Boundaries**: 0 NIFs; 6 pure-Erlang externals (`shell`, `io`, `erlang`, `calendar`); emits `Intent` values, executes nothing.
