---
name: effect-ts-architect
description: Use when creating, reviewing, or migrating TypeScript that must use Effect. Covers core `effect`, Schema, Layer/Context, Schedule, Stream, @effect/platform, @effect/rpc, @effect/sql, @effect/opentelemetry, @effect/ai, browser IIFE constraints, and migration away from fp-ts/Promise/null patterns.
---

# Effect TS Architect

## Trigger

Use this skill for any TypeScript generation, TypeScript refactor, runtime JavaScript replacement, API/RPC/SQL/OTel/AI integration in TypeScript, or review of agent-authored TypeScript.

## Required Reading

1. `.gemini/rules/effect-ts-universal.md`
2. `.gemini/rules/effect-ts-only-js.md` when browser/runtime JS or IIFE bundles are touched
3. Canonical references in `.claude/skills/effect-ts-architect/references/`

## Artifact Baseline

- Official Effect site/docs: `https://effect.website/`, `https://effect.website/docs/`
- GitHub monorepo: `https://github.com/Effect-TS/effect`
- Core package: `effect`
- Related packages: `@effect/platform`, `@effect/rpc`, `@effect/sql`, `@effect/opentelemetry`, `@effect/ai`, `@effect/cli`, `@effect/vitest`, runtime packages such as `@effect/platform-node`, `@effect/platform-browser`, and SQL drivers such as `@effect/sql-pg`.
- `@effect/schema` is legacy/deprecated for new work; use `Schema` from `effect`.

## Workflow

1. Classify the boundary: core pure logic, async IO, browser IIFE, HTTP, RPC, SQL, OTel, AI, CLI, or tests.
2. Keep internal APIs in `Effect.Effect<A, E, R>`; add `Promise` wrappers only at compatibility edges.
3. Use `Option` for absence, `Schema` for external data, `Layer`/`Context` for services, and `Schedule` for retry/repeat.
4. Preserve C3I browser rule: authored TS + Effect + esbuild IIFE bundle; no new raw JS logic.
5. Verify no `fp-ts` import remains in changed TypeScript.
6. Run the local check command from the nearest `AGENTS.md`.

## Review Gate

Reject changes that add new `fp-ts`, raw Promise control flow in internal APIs, untyped JSON, hand-rolled retry loops, new browser `.js` behavior, or service singletons where `Layer`/`Context` is required.
