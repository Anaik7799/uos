# Apps Subsystem (`apps/`)

- **Ownership & Language Authority**: Pure Gleam / OTP.
- **Scope**: Live operational applications, agent swarm orchestration, CEPAF coordinator (`apps/cepaf_gleam`), TUI, and operational API endpoints.
- **Invariants**: All supervision, state machines, lease management, and high-level routing live here. Zero native blocking code.

## `apps/uos_tui` (added 20260906-2150-)
- **Role**: Pure-Gleam terminal UI library and reference cockpit (Textual-referenced TEA on OTP). See ADR-061 and `docs/design/20260906-2150-uos-tui-gleam-library-textual-reference-design.md`.
- **Run**: `cd apps/uos_tui && gleam test` (116 tests), `gleam run` (live), `gleam run -- snapshot`, `gleam run -- dictionary`.
- **Boundaries**: 0 NIFs; 6 pure-Erlang externals (`shell`, `io`, `erlang`, `calendar`); emits `Intent` values, executes nothing.

## `apps/uos_tui` swarm, hive mind and Zenoh infra (added 20260907-0537-)
- **Swarm**: round 1: 15 agents (10 Sonnet + 5 Haiku) in jj sibling workspaces, 11/11 PASS first attempt; round H2 (Codex P1 hardening): 5 Sonnet workers, 400 tests, 0 warnings; see ADR-062 and `docs/plans/20260907-0440-uos-tui-swarm-15-agent-multilayer-plan.md`.
- **Hive mind**: `gleam run -- board ...` (post, post-acl, ack, ingest, validate, reconcile, proof, inbox, retry, replay, share; posts pass `coord.authorize` against the ledger roster), `manager-run`, `audit-system`, `hive`, `holon`, `lexicon`, `acl grammar|parse`, `dashboard`.
- **vm-1 evidence copy**: sanitized read-only snapshot of C3I + Indrajaal at `/home/an/dev/ver/c3i-vm1-20260907-0559` (receipt `governance/sources/20260907-0604-vm1-c3i-indrajaal-sanitized-snapshot-receipt.json`); use it for reference only, nothing enters `apps/` without two-key verification.
- **Zenoh**: `ops/zenoh/` runbook; router `c3i-zenoh-router-1`, REST :8080, storages on `c3i/a2a/**` and `uos/tui/**`.
