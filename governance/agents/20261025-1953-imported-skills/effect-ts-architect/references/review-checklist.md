# Effect TS Review Checklist

## Required

- Changed TS imports from `effect` or a scoped `@effect/*` package.
- Internal async/IO functions return `Effect.Effect<A, E, R>`.
- Promise wrappers are at API edges only.
- Throwable sync work uses `Effect.try`.
- Promise work uses `Effect.tryPromise`.
- Nullable/missing data uses `Option`.
- External data uses `Schema`.
- Retry/repeat/backoff uses `Schedule`.
- Cross-module dependencies use `Context.Tag` + `Layer`.
- Error diagnostics preserve `Exit`/`Cause` or typed failures.
- Browser behavior follows Effect TS + IIFE rule.

## Reject

- New `fp-ts` imports.
- New raw browser `.js` behavior.
- Untyped `response.json()` consumed without `Schema` near boundary.
- New `.then().catch()` chains in internal logic.
- New `setTimeout`/`setInterval` retry loops.
- Swallowed exceptions or empty `catch {}` without typed fallback.
- Mutable global service clients when `Layer` is feasible.

## Commands

```bash
rg -n "from ['\"]fp-ts|fp-ts/" .
rg -n "from ['\"]effect['\"]|from ['\"]@effect/" <changed-ts-paths>
rg -n "new Promise|\\.then\\(|\\.catch\\(|setInterval\\(|setTimeout\\(" <changed-ts-paths>
```

Run the local package check from the nearest `AGENTS.md`.
