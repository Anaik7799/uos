# Critical Code Registry, Agentic Update Resilience, and Fast-OODA MCP Mandate

Contract: SC-AGENTIC-RESILIENCE-001  
Status: ACTIVE & ENFORCED (Development & Integration Boundary)  
Observed UTC: 2026-10-29T07:45:00Z  
Tags: #fractal-l0 #fractal-l1 #fractal-l2 #fractal-l3 #fractal-l4 #fractal-l5 #fractal-l6 #fractal-l7 #fractal-l8 #fractal-l9 #zk-adr #zero-muda

[Rendered](http://nas-1.tail55d152.ts.net:4100/docs/contracts/rules/20261029-0745-critical-code-agentic-resilience-and-mcp-mandate.md) · [Raw](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20261029-0745-critical-code-agentic-resilience-and-mcp-mandate.md) · [Root Policy](http://nas-1.tail55d152.ts.net:4100/files/AGENTS.md) · [Harness Contract](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20260909-0412-gleam-harness-agent-operation-contract.md)

## 1. Purpose and Scope

Autonomous multi-agent code updates across sibling Jujutsu workspaces introduce specific structural hazards: dropped pattern-match dispatch arms when merging sibling branches, contract-to-test drift across JSON-RPC error envelopes, stale control-module counts, and unverified workspace divergence. This contract defines:
1. The **Canonical Critical Code Registry** (28 compiled BEAM control modules, 44 source files, bounded native dependencies, and immutable Nix store artifacts).
2. The **5-Layer Defense-in-Depth Resilience Controls** that protect critical code from agentic regressions.
3. The **Fast-OODA Tri-Agent Execution & Frequent Main-Merge Protocol** under `gemini-4-argon` (`pi-agy` supervisor), `codex` (`gpt-6-luna` mechanical/implementation worker), and `claude` (`claude-opus-5` independent reviewer).

## 2. Canonical Critical Code Registry

Every modification to the following critical control-plane paths requires a reviewed task-scoped grant, CAS expected-SHA-256 verification, and 100% passing execution of the 12-module (184-test) MCP + Development Harness EUnit gate before advancing `main`:

| Tier | Module / Path | Compiled BEAM / Binary Identity | Critical Invariant Protected |
|---|---|---|---|
| **T0 Admission & Runtime Guard** | `apps/cepaf_gleam/src/cepaf_gleam/harness/admission.gleam`, `src/harness_runtime_guard_ffi.erl` | `cepaf_gleam@harness@admission`, `harness_runtime_guard_ffi` | 28-module BEAM MD5 verification, 44-source SHA-256 manifest, grant signature, role/attempt/epoch/clock bounds |
| **T0 Immutable Host Backend** | `apps/cepaf_gleam/src/cepaf_gleam/harness/native_backend.gleam`, `src/harness_native_backend_ffi.erl`, `/nix/store/mmycwn1v7bvpjgl0hxvbazxrqwjwn335-uos-sa-plan-main-cfe06ec3` | `cepaf_gleam@harness@native_backend`, `harness_native_backend_ffi` | Atomic node-local CAS registry (`Absent -> Pending -> Ready | Failed`), poison-on-failure (no silent fallback), `0555` root-owned 42,344,784 B store verification |
| **T1 Successor Dev MCP** | `apps/cepaf_gleam/src/cepaf_gleam/harness/successor_mcp.gleam`, `operations.gleam`, `development.gleam`, `planning_intents.gleam` | `cepaf_gleam@harness@successor_mcp`, `cepaf_gleam@harness@operations`, `cepaf_gleam@harness@development`, `cepaf_gleam@harness@planning_intents` | Total 15-tool dispatch completeness (`ops.names`), pre-attach assessment guard, single-flight effect ledger, planning Andon latch |
| **T1 Canonical Sa-Plan Bridge** | `apps/cepaf_gleam/src/cepaf_gleam/planning/sa_plan_bridge.gleam`, `engines/hermes/modules/sa_plan/*` | `cepaf_gleam@planning@sa_plan_bridge` | Literal fixed argv, 3-scope lease renewal (`--task-renew`), Jidoka Andon enforcement (`SC-JIDOKA-001`) |
| **T2 Four-Client Config & Transport** | `apps/cepaf_gleam/src/cepaf_gleam/harness/client_profiles.gleam`, `client_mcp.gleam`, `client_config.gleam`, `src/client_config_io.erl` | `cepaf_gleam@harness@client_profiles`, `cepaf_gleam@harness@client_mcp`, `cepaf_gleam@harness@client_config`, `client_config_io` | Exact structural JSON/TOML verification for `AGY/Gemini`, `Codex`, `Claude`, and `Pi`; block project-file read/write of client configs |
| **T2 Public MCP Server & Authz** | `apps/cepaf_gleam/src/cepaf_gleam/mcp/server.gleam`, `tools.gleam`, `protocol.gleam`, `authz.gleam` | `cepaf_gleam@mcp@server`, `cepaf_gleam@mcp@tools`, `cepaf_gleam@mcp@protocol`, `cepaf_gleam@mcp@authz` | 65 declared tools (53 operational, 12 explicit fail-closed `unavailable_tools`), SEU/STPA preflight gate, W3C OTel trace context |
| **T3 Clock, Files & Process FFI** | `apps/cepaf_gleam/src/cepaf_gleam/harness/clock.gleam`, `files.gleam`, `mcp.gleam`, `src/ecology_capability_ffi.erl`, `tools/ecology_process.ml` | `cepaf_gleam@harness@clock`, `cepaf_gleam@harness@files`, `cepaf_gleam@harness@mcp`, `ecology_capability_ffi` | Chrony NTP drift $<2.0\text{s}$, traversal-free atomic CAS writes, noncanonical/noecho PTY framing, bounded process tree reaping |

## 3. Five-Layer Agentic Code Update Resilience Controls (Fractal TPS)

1. **Layer 1 — Poka-Yoke CAS & Scope Allowlist (`files.write_cas`, `dev.decide_write_cas`)**:
   - Every agentic file edit must supply the exact `expected_sha256` of the current file on disk and match `grant.write_scope`. Blind overwrites, path traversal, symlinks, and out-of-scope edits fail closed before touching disk.
2. **Layer 2 — Total Dispatch & Schema Completeness Law (`every_declared_operation_has_schema_and_client_mcp_config_is_routed_test`)**:
   - Every operation declared in `ops.names` (all 15 tools) MUST have a valid JSON Schema and a wired execution branch in `successor_mcp.active_call_dispatch`. Any agentic edit that adds or modifies an operation without wiring its dispatch arm fails the automated law test immediately.
3. **Layer 3 — Runtime Control-Module MD5 & Source Manifest Guard (`admission.verify_runtime_controls`)**:
   - Before any tool call executes, the harness verifies the live in-memory BEAM MD5 of all 28 `control_modules` and the SHA-256 of `control_dependencies` (`tools/ecology_process.ml`) against the reviewed grant. Any hot-code drift or unreviewed recompile halts dispatch with `loaded_control_digest_mismatch`.
4. **Layer 4 — Jidoka Andon & Single-Flight Effect Ledger (`planning.decide_andon`, `dev.record_effect_intent`)**:
   - Every build, test, write, client-config, or planning intent writes a durable intent record BEFORE execution. Any `Uncertain` outcome or corrupt receipt latches the parent task's Andon line (`planning_andon_held`) until reconciled via `harness_reconcile`.
5. **Layer 5 — Fast-OODA Sibling Workspace Gate & Serialized `integration/main` Fence**:
   - All agentic edits and builds run in isolated sibling workspaces (`.uos-workspaces/*`). Advancing `main` requires an active `integration/main` coordinator epoch lease, 0 merge conflicts, 184/184 passing EUnit tests across all 12 MCP + harness test modules, and independent agent review (`claude` or `codex` cross-family verification).

## 4. Comprehensive Verification Checklist

<details>
<summary>Domain 1 — Metadata, timestamp and Tailscale navigation</summary>

- [x] **CHK-01-TIME** — Observed synchronized host UTC and `YYYYMMDD-HHSS-` prefix recorded.
- [x] **CHK-02-TAIL** — Full Tailscale FQDN links supplied.
- [x] **CHK-03-FRACT** — Fractal layers `#fractal-l0`..`#fractal-l9` mapped.
- [x] **CHK-04-KM** — Cross-linked to root policy, harness contract, and learnings rule.

</details>
<details>
<summary>Domain 2 — Zero-Muda purity and storage safety</summary>

- [x] **CHK-05-MUDA** — 0 Bevy, 0 Graphite across all critical modules.
- [x] **CHK-06-GRAPH** — Pure Gleam/Erlang and Hermes OCaml boundaries enforced.
- [x] **CHK-07-DRIVE** — Denied system OS serial interlock preserved.

</details>
<details>
<summary>Domain 3 — Testing Gold Standard and mathematical gates</summary>

- [ ] **CHK-08-C1C8** — Full UI surface C1–C8 verification remains separate.
- [ ] **CHK-09-MATH** — Four composite mathematical gates remain separate from unit laws.
- [ ] **CHK-10-9MOD** — Full 9-modality campaign remains open.
- [x] **CHK-11-REGR** — 184/184 EUnit tests across 12 MCP and harness modules verified.

</details>
<details>
<summary>Domain 4 — Cross-language control and observability</summary>

- [x] **CHK-12-GLEAM** — Gleam owns admission, backend selection, and tool dispatch.
- [x] **CHK-13-HERMES** — Hermes owns `sa-plan` SQLite WAL ledger and bounded CLI.
- [x] **CHK-14-ZIGVM** — ZigVM boundary preserved.
- [ ] **CHK-15-MAX** — Isolated MAX inference remains separate.
- [x] **CHK-16-OTEL** — Synchronized clock and trace/receipt digests enforced.

</details>
<details>
<summary>Domain 5 — Sovereign governance and standalone Jujutsu</summary>

- [x] **CHK-17-SOV** — Tri-sovereign multi-agent review (`gemini-4-argon`, `codex`, `claude`) active.
- [x] **CHK-18-JJ** — Standalone Jujutsu workspace isolation and topological `main` unification enforced.

</details>
<details>
<summary>Domain 6 — Provenance extension</summary>

EV ceiling remains 93 (`SC-PROVENANCE-001`). Cycles EV-94..109 remain `NOT_ADMITTED`. No new EV number is minted.

</details>
