# Effect TS Artifact Map

## Official Sources Checked

- `https://effect.website/` — product site and current positioning: robust, typed, scalable TypeScript.
- `https://effect.website/docs/` — canonical documentation.
- `https://github.com/Effect-TS/effect` — monorepo with core and ecosystem packages.
- `https://effect-ts.github.io/effect/` — API reference.
- `https://raw.githubusercontent.com/Effect-TS/effect/main/AGENTS.md` — upstream agent instructions.
- Firecrawl research output: `/home/an/dev/ver/work/.firecrawl/effect-ts-artifacts.json` captured GitHub, API reference, platform README, and RPC README search results on 2026-05-09.

## Current GitHub Snapshot

- Monorepo: `Effect-TS/effect`
- Primary branch: `main`
- Latest observed GitHub commit during research: `3585f25` / "Version Packages (#6218)" on 2026-05-08.
- Repository shape: `packages/` contains the core package and ecosystem packages; README lists `effect`, `@effect/platform`, `@effect/rpc`, `@effect/sql`, `@effect/opentelemetry`, `@effect/ai`, provider packages, runtime platform packages, `@effect/vitest`, and `@effect/workflow`.
- Upstream repo requires TypeScript strict mode for `effect` and emphasizes zero check failures, clarity, and concise code.

## Package Matrix

| Package | Use For | C3I/Pi Guidance |
|---------|---------|-----------------|
| `effect` | Core `Effect`, `Option`, `Either`, `Exit`, `Cause`, `Schema`, `Context`, `Layer`, `Schedule`, `Stream`, `Queue`, `PubSub`, `Fiber`, `Config`, `Ref` | Default dependency for all generated/modified TS |
| `@effect/platform` | Platform-neutral HTTP APIs, clients, server abstractions, file/key-value/socket/worker utilities | Use for HTTP boundary definitions and typed clients |
| `@effect/platform-node` | Node runtime, Node context, HTTP server/client integration | Use for Node CLI/daemon bridges |
| `@effect/platform-browser` | Browser platform services | Use for browser runtime TS when a platform service is required |
| `@effect/rpc` | Schema-backed RPC groups, clients, servers, middleware | Use for MCP-like or Pi↔C3I request groups when TypeScript owns both ends |
| `@effect/sql` | SQL client abstraction, resolvers, schema-aware SQL utilities | Use for TS-owned SQL access only; prefer existing Rust/Gleam C3I persistence if present |
| `@effect/sql-pg`, `@effect/sql-sqlite-node`, etc. | Concrete SQL drivers | Add only with a clear DB boundary |
| `@effect/opentelemetry` | OTel tracing, logging, metrics integration | Use when TS code emits OTel directly |
| `@effect/ai`, provider packages | Effect-native AI abstractions and providers | Use for new Effect-native AI client paths; do not replace existing provider code without scope |
| `@effect/cli` | CLI arg parsing and command composition | Use for new TS CLI tools |
| `@effect/vitest` | Effect-aware tests (`it.effect`, `it.scoped`, test clock) | Use when adding new Effect tests |
| `@effect/workflow`, `@effect/cluster` | Durable workflows and distributed compute | Use only with explicit architecture need |

## Component Selection Playbook

### Core App Logic

Use only `effect`:

- `Effect` for IO, concurrency, typed errors, timeouts, acquire/release.
- `Schema` for payloads and generated contracts.
- `Option` / `Either` / `Exit` / `Cause` for explicit data and failure boundaries.
- `Context` / `Layer` for services.
- `Ref`, `Queue`, `PubSub`, `Stream`, `Schedule`, `Duration`, `Config` for runtime control.

### HTTP and Browser/Node Platform

Use `@effect/platform` when TypeScript owns HTTP clients, HTTP APIs, sockets, workers, file systems, key-value stores, or platform-independent runtime code. Add `@effect/platform-node`, `@effect/platform-browser`, or other runtime packages only for the concrete runtime.

### RPC / MCP-Like Requests

Use `@effect/rpc` when a TypeScript subsystem owns request/response contracts and both client/server should derive from a `Schema`-backed RPC group. This fits future TypeScript-owned MCP-like bridges; do not force it into existing Rust/Gleam-owned C3I tool paths unless that boundary is explicitly moved.

### SQL

Use `@effect/sql` only when TypeScript owns database access. Prefer existing Rust/Gleam C3I persistence if the boundary already exists. If TS owns the boundary, choose one concrete driver package and keep all SQL calls inside a service `Layer`.

### OTel

Use `@effect/opentelemetry` when TypeScript directly emits or exports tracing/metrics/logging. For existing C3I Zenoh OTel bridges, keep the compatibility API but implement internals as `Effect`.

### AI

Use `@effect/ai` and provider packages for new Effect-native AI integrations. Do not replace pi-mono’s established provider API unless the task explicitly scopes that migration.

### Tests

Use `@effect/vitest` (`it.effect`, `it.scoped`, `TestClock`) when adding tests for Effect code and the repo already uses Vitest or explicitly adds the package.

## Upstream Agent Practices

Adopt these upstream Effect repo practices where compatible with C3I/Pi:

- Zero tolerance for type/check failures.
- Prefer clarity over cleverness.
- Keep prose and code concise.
- Use existing local patterns before writing new abstractions.
- Effect tests should prefer `it.effect` / `@effect/vitest` where available.

## Deprecated / Avoid

- Do not add `@effect/schema` for new work; `Schema` is in `effect`.
- Do not add `fp-ts` for new or modified generated TypeScript.
- Do not mix `fp-ts` and Effect in the same new module.
- Do not use `Effect-TS` package names from older tutorials unless they resolve to the current `effect` / `@effect/*` ecosystem.
