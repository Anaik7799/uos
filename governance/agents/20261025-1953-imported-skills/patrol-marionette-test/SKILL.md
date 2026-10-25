---
name: patrol-marionette-test
description: "Drive Patrol MCP + Marionette MCP for triple-platform Flutter testing with Zenoh telemetry"
argument-hint: "[target-file] [platforms]"
---

# /patrol-marionette-test — Dual-MCP Flutter Test Driver

Runs the [Patrol 4.x](https://patrol.leancode.co) + [Marionette](https://marionette.leancode.co) closed-loop testing flow with Zenoh feedback. SC-PATROL-MCP-001..012.

## Inputs
- `$1` — target test file (default `integration_test/patrol_test.dart`)
- `$2` — comma-separated platforms (default `android,linux,chrome`)

## Phase 1 — Discover (Marionette MCP)
1. Ensure the Flutter app is running in debug mode with `MarionetteBinding.ensureInitialized()`. Pull the VM Service URI from `flutter run` stdout (`ws://127.0.0.1:<port>/<key>/ws`).
2. `mcp__marionette__connect uri=<vm-service-uri>`
3. `mcp__marionette__get_interactive_elements` → list of keys/text → use these as Patrol finders.
4. `mcp__marionette__take_screenshots` → archive under `docs/cache/marionette/<session_id>/before.png`.
5. Iterate `tap` / `enter_text` / `scroll_to` to validate the proposed flow before codifying.

## Phase 2 — Codify
- Write/extend `integration_test/patrol_test.dart` using Patrol 4.x `patrolTest($)` with the platform API (`$.native.android.*`, `$.native.ios.*`, `$.platform.web.*`).
- Reuse selectors discovered in Phase 1.

## Phase 3 — Execute (Patrol MCP, per platform)
For each platform in `$2`:
1. `mcp__patrol__run target=$1 device=<platform>` — emits `indrajaal/l5/test/patrol/<run_id>/start`.
2. Poll `mcp__patrol__status` every 5 s; mirror onto Zenoh.
3. On every checkpoint: `mcp__patrol__screenshot` → archive under `docs/cache/patrol/<run_id>/`.
4. On failure: `mcp__patrol__native-tree` → archive → publish `/failed` envelope → escalate to Marionette MCP for live diagnosis.
5. `mcp__patrol__quit` after pass or fail.

## Phase 4 — Persist
- Append run summary to `session_metrics` (test name, platform, duration_ms, result).
- Ingest journal + screenshots to ZK via `sa-plan-daemon ingest-docs`.
- Email summary if any platform failed: `sa-plan-daemon send-email -a <journal>.md`.

## Quick reference

```bash
# CLI fallback (auto-publishes Zenoh envelopes)
./tool/patrol-zenoh-bridge.sh run \
  --target integration_test/patrol_test.dart \
  --device chrome --web-headless --web-video --web-reporter html

# Discovery REPL
dart pub global activate marionette_mcp
marionette --uri ws://127.0.0.1:8181/ws get-interactive-elements
```

## STAMP gate
Mark this skill **complete** only when:
- All requested platforms passed.
- Screenshots + native trees archived.
- Zenoh envelopes visible on `indrajaal/l5/test/**` (verify via `zenoh sub`).
- `session_metrics` row written.
- Tailscale URL of the run journal emitted.
