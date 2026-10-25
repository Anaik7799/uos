---
name: gleam-expert
description: Expert guidance for Gleam development on the BEAM VM. Use when Gemini CLI needs to write type-safe Gleam code, port F# logic to Gleam, integrate with Erlang via FFI, or build actor-based orchestration layers.
---
# Gleam Expert Skill
This skill provides expert patterns and guidance for developing high-assurance systems in Gleam, specifically targeting the BEAM VM.
# Core Mandates
1.  **Gleam 1.0+ Compliance**: ALWAYS use the latest Gleam patterns, including labeled arguments and the `gleam/dynamic/decode` API.
2.  **Type Safety First**: Use opaque types and controlled constructors to maintain domain invariants (e.g., NonEmptyString).
3.  **BEAM Synergy**: Leverage Erlang FFI for low-level system access (UDS, Zenoh) while wrapping them in type-safe Gleam interfaces.
4.  **Actor-Based Concurrency**: Replace F# `MailboxProcessor` with Gleam `otp` actors for state management.
# Quick Reference
# JSON Decoding (Modern Pattern)
Use `gleam/json` and `gleam/dynamic/decode`:
```gleam
import gleam/json
import gleam/dynamic/decode
pub fn decode_user(json_string: String) {
let decoder = {
use id <- decode.field("id", decode.int)
use name <- decode.field("name", decode.string)
decode.success(User(id, name))
}
json.parse(from: json_string, using: decoder)
}
```
# Erlang FFI
- **Naming**: Gleam module `my_module` maps to Erlang module `my_module`.
- **Types**: Gleam `String` is Erlang `binary`. Gleam `Int` is Erlang `integer`.
- **FFI Attribute**: `@external(erlang, "module_name", "function_name")`.
# STAMP Constraints (Gleam-Specific)
| ID | Constraint |
|----|-----------|
| SC-GLM-CMP-001 | `gleam build` MUST produce zero warnings/errors |
| SC-GLM-CMP-002 | `gleam format` MUST pass before commit |
| SC-GLM-CMP-003 | `gleam check` fast type-check gate |
| SC-GLM-CMP-004 | BEAM target only (`target = "erlang"` in gleam.toml) |
| SC-GLM-CMP-005 | Gleam-Elixir FFI via typed OTP message passing |
| SC-GLM-CORE-001 | ALL new c3i logic in Gleam |
| SC-GLM-CORE-002 | Result type for all fallible operations |
| SC-GLM-CORE-003 | Exhaustive pattern matching on custom types |
| SC-GLM-NIF-001 | Rust NIFs for Zenoh FFI and perf-critical paths only |
| SC-GLM-NIF-002 | NIF calls through `cepaf_gleam_ffi.erl` wrapper |
| SC-GLM-UI-001 | Every c3i function MUST expose Lustre + Wisp + TUI |
| SC-GLM-UI-002 | Lustre: server-side rendering on BEAM |
| SC-GLM-UI-003 | Wisp: typed JSON via `gleam/json` |
| SC-GLM-UI-004 | TUI: ANSI via `cockpit/visuals.gleam` |
| SC-GLM-UI-009 | All 3 interfaces share same domain types |
# AOR Rules (Gleam-Specific)
| ID | Rule |
|----|------|
| AOR-GLM-001 | ALL new c3i modules in Gleam |
| AOR-GLM-002 | `gleam build` before `mix compile` |
| AOR-GLM-003 | `gleam format` before commit |
| AOR-GLM-005 | Result type for errors — never raise |
| AOR-GLM-010 | No imports from F# namespace |
| AOR-BUILD-001 | Build order: Rust → Gleam → Elixir → F# |
| AOR-GLM-UI-001 | New c3i function → create Lustre + Wisp + TUI |
| AOR-GLM-UI-005 | All 3 interfaces import from SAME domain module |
| AOR-GLM-UI-009 | NEVER add Wisp endpoint without Lustre + TUI |
# UI Architecture (Lustre + Wisp + TUI)
Every Gleam c3i function exposes 3 interfaces per SC-GLM-UI-001:
| Interface | Tech | Directory | Purpose |
|-----------|------|-----------|---------|
| **Lustre** | `lustre >= 4.0` | `ui/lustre/` | Real-time Web dashboard, SSR on BEAM, Dark Cockpit |
| **Wisp** | `wisp >= 1.0` + `mist >= 3.0` | `ui/wisp/` | JSON API (port 4100), health probes, agent access |
| **TUI** | ANSI + `cockpit/visuals.gleam` | `ui/tui/` | Terminal sparklines, health bars, command REPL |
Shared types: `ui/domain.gleam` — Page, HealthStatus, TelemetryPoint, Action, RenderContext.
# Migration Status (2026-04-01)
Phases 1-5 COMPLETED (~90% non-container parity). Phase 6 (Podman substrate) DEFERRED.
~39 Gleam modules across 9 operational planes in `lib/cepaf_gleam/src/` (including `ui/`).
# Advanced Guides
- **BEAM Integration**: See [BEAM_INTEGRATION.md](references/BEAM_INTEGRATION.md) for FFI and OTP patterns.
- **Dynamic Decoding**: See [DYNAMIC_DECODER.md](references/DYNAMIC_DECODER.md) for complex record decoding.
- **Migration from F#**: See [FSHARP_MIGRATION.md](references/FSHARP_MIGRATION.md) for mapping F# types and async workflows.