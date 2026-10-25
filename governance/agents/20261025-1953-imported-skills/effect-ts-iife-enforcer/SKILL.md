---
name: effect-ts-iife-enforcer
description: Enforce Effect TypeScript-only implementation and full IIFE collapse for browser/runtime JS paths.
---

# Effect-TS IIFE Enforcer

## Mandate
When a task touches JavaScript/TypeScript for browser/runtime behavior:
- use Effect TypeScript only
- compile via esbuild to IIFE bundle
- prohibit new raw `.js` logic
- also enforce `.gemini/rules/effect-ts-universal.md` for all TypeScript, including non-browser modules

## Checklist
1. Confirm rule `.claude/rules/effect-ts-only-js.md` is cited in task notes.
2. Confirm rule `.gemini/rules/effect-ts-universal.md` is cited for any generated/modified TS.
3. Verify changed files are `.ts` for logic paths.
4. Verify TS imports from `effect` or an appropriate `@effect/*` package.
5. Verify build output is bundled IIFE (`--format=iife`).
6. Reject/flag any new raw `.js` logic, `fp-ts` imports, or bare Promise/null control flow.
7. Document H-risk waiver if operator explicitly approves exception.

## Evidence Commands
```bash
rg -n "--format=iife|format:\s*'iife'|format:\s*\"iife\"" lib/cepaf_gleam/priv/web-build
rg -n "from 'effect'|from \"effect\"" lib/cepaf_gleam/priv/web-build/src
rg -n "from ['\"]fp-ts|fp-ts/" lib/cepaf_gleam/priv/web-build src sub-projects/pi-mono 2>/dev/null
```
