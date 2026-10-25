---
name: codex-symbiosis
description: Run Codex as a first-class zigvm agent with the same MCP control plane, SQLite data plane, rules, skills, and verification semantics as Claude.
---

# Codex Symbiosis

Use this skill when taking over from Claude, configuring Codex for zigvm,
checking cross-agent parity, or operating the harness through MCP.

## Required Reads

1. `AGENTS.md`
2. `CODEX.md`
3. `docs/CODEX_SYMBIOSIS.md`
4. `docs/AGENT_HANDOVER.md`
5. `docs/AUTONOMOUS_RUNBOOK.md`
6. `skills/harness-supervisor/SKILL.md`

## Workflow

1. Confirm the Codex MCP server registration exists in `~/.codex/config.toml`
   or use the stdio MCP fallback from `CODEX.md`.
2. Call `observe` and `next_slice` through MCP. If native tools are absent,
   start `opam exec -- dune exec ./harness/zigvm_harness.exe -- --root "$PWD" --mcp`
   and use newline-delimited JSON-RPC.
3. Treat `AGENTS.md` as the rulebook and the repo `skills/` files as the skill
   source. Do not treat `.superpowers/` as state.
4. Map Claude superpowers to Codex actions through `docs/CODEX_SYMBIOSIS.md`
   and `skills/harness-supervisor/SKILL.md`.
5. Verify every accepted slice with the harness, then record through MCP:
   `record_cycle`, `log_ooda`, and `snapshot`.
6. For Rete-UL/ruliology requests, distinguish planned R-track work from live
   engines. R1 is OCaml under `harness/`; R2 is Zig under `src/`.

## Hard Rules

- MCP first; stdio MCP fallback second; raw CLI only when debugging the MCP
  server itself.
- **MCP staleness (h-mcp-staleness):** after ANY `harness/*.ml` edit + rebuild,
  a long-running `--mcp` server keeps its OLD in-process code and fails closed
  with `STALE-HARNESS` on every `tools/call`. Use the CLI for evidence, or
  reconnect the MCP server after the final harness build.
- **Verify by exit code + `harness_runs.status`, never printed text** (CAST-12).
- SQLite is the only durable position/memory store.
- Database access must go through the harness or authored OCaml code; direct
  clients, Python bindings, and shell SQL are forbidden.
- No false-EQ, no file-based task state, no non-OCaml harness logic, no
  non-Zig VM implementation, no non-OCaml automation scripts
  (`docs/OCAML_SCRIPTING_SOP.md`).
- A Codex run is equivalent to a Claude run only when the same MCP facts,
  same gate, and same SQLite effects are observed.
