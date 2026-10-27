# 20261027-1910 — Code review bundle (Pi symbiosis + harness-integration changes)

#fractal-l0 #fractal-l3 #fractal-l9 #zk-adr #zero-muda #tailscale-web

[This bundle](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20261027-1910-code-review-bundle.md) · [Sweep](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20261027-1810-harness-tool-sweep.md)

Requested: independent Codex review of all code and implementation. Scope below is candidate-bound; review does not grant admission.

## Changes under review (uncommitted JJ working tree)

### Source
1. `apps/cepaf_gleam/src/cepaf_gleam/mcp/server.gleam`
   - `tool_preflight_check`: strict `decode.float` → lenient `number_decoder` (`one_of(float, int→float)`) for `benefit`/`cost`. Fixes integer-arg rejection (schema says `"number"`).
   - `verify_mutating_action_preflight`: same fix for `benefit`/`cost`/`risk_score`.
   - `tool_verification_run`: rewired from `c3i_nif.verification_run()` to `run_bounded_cd("/home/an/.nix-profile/bin/gleam", ["check"], "…/apps/cepaf_gleam", 60000)`; result encoded as `{ok, output(≤2000 graphemes), warnings, errors}` via `gleam/json`. Removes the Rust-NIF fork/wait `ECHILD` path.
   - Added `@external(erlang, "ecology_capability_ffi", "run_bounded_cd")`.
2. `apps/cepaf_gleam/src/ecology_capability_ffi.erl`
   - Added `run_bounded_cd/4` (Path, Args, Cwd, TimeoutMs): cwd must be at/under UOS root; spawns the OCaml process-group guardian via `open_port({spawn_executable, …},{cd,Cwd})`, same deadline/output-ceiling/cleanup as `run_bounded/3`.
3. `apps/cepaf_gleam/native/c3i_nif/src/verification.rs`
   - `gleam_dir` resolution now prefers `apps/cepaf_gleam` / `/home/an/NAS-setup/uos/apps/cepaf_gleam` over the stale `/home/an/dev/ver/c3i` fallback. **Not rebuilt** (needs `devenv` cargo + `.so` re-pin; unified NIF `.so` serves 40 working tools).
4. `~/.pi/agent/mcp.json`
   - Added `uos-harness` (read surface, `cepaf_gleam@mcp@server:main()`) and `uos-harness-dev` (grant-gated `successor_mcp:main()`); backup `mcp.json.bak-20261027-1758`.

### Docs / rules (additive)
`SC-MIRROR-PROJ-001` rule; `full-symbiosis` skill learnings; journals/plans/reviews; grant proposal + review request.

## Test evidence (full suite, this session)
- `gleam build`: 0 errors (pre-existing unused-import warnings only).
- `gleam test` (full): **619 passed / 11 failed**.
- The 11 failures are ALL caused by a **pre-existing NIF ABI incompatibility**: `Error loading module c3i_nif: corrupt atom table` (the `c3i_nif.so` dated 2026-09-06 vs current ERTS 17.0.5 / OTP 29.0.5). Cascade: `actors_test.freshness_actor_*` (7) + `actors_test.observer_actor_*` (3) = `Undef`, plus `agui_cockpit_test` `ModuleNotFound`. Not attributable to the changes above.
- End-to-end canary (fresh server instance): `preflight_check` with integer args → `{"status":"approved", …, "gate":"PASS"}` (was `Missing required params.arguments`).

## Review checklist (Codex)
1. Does `run_bounded_cd` preserve the guardian's deadline/output-ceiling/process-group cleanup and cwd containment (no `..` escape, absolute-under-root)?
2. Is the `number_decoder` change type-safe and equivalent to `rete_rule_conflict`'s existing usage?
3. Does `tool_verification_run` JSON shape stay backward-compatible with the prior NIF result shape?
4. Is the `verification.rs` cwd order correct and non-regressive for the old c3i layout?
5. Any issue with `mcp.json` server args/env for a fresh Pi session?

## Residual (NOT part of this review's authority)
- `c3i_nif.so` rebuild + re-pin (fixes the 11 ABI failures) — governed release flow.
- Pi-bound grant admission (effect surface) — needs peer verdict + operator authorization.

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Review is advisory; this bundle grants no admission.