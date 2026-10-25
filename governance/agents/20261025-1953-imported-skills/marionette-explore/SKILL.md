---
name: marionette-explore
description: "Marionette-driven exploratory authoring for Flutter apps — discovers selectors live, drafts test cases, captures evidence, publishes Zenoh envelopes. Use BEFORE writing any new Flutter UI test."
---

# /marionette-explore

Live exploration of a running Flutter app via Marionette MCP (16-tool surface). Avoids the selector-guessing anti-pattern [zk-bb4de67d97f807ac] by always starting from `get_interactive_elements`.

## Usage

```
/marionette-explore <app> <screen-or-flow>            # default platform = linux
/marionette-explore <app> <flow> --platform=android   # target Android emulator
/marionette-explore <app> <flow> --resume             # reuse running debug session
/marionette-explore <app> <flow> --record-video       # marionette_cli record-video alongside
```

`<app>` resolves under `sub-projects/sutra/<app>/` (or any other `sub-projects/.../<app>/` containing `pubspec.yaml`).

## What it does

1. Verifies/activates `marionette_mcp` and `marionette_cli` (`dart pub global activate ...`) — no-op if already active.
2. Boots `flutter run -d <platform> --debug -t integration_test/marionette/marionette_runner.dart` (unless `--resume`); waits for VM URI.
3. Delegates to the `marionette-explorer` sub-agent to:
   - `connect` → `list_custom_extensions` → `get_interactive_elements`
   - drive the named flow with the appropriate gestures
   - capture per-step screenshots, tree snapshots, logs
   - propose new rows for `<app>/integration_test/marionette/CATALOG.md`
4. Persists evidence under `docs/cache/marionette/<run_id>/` and publishes envelopes on `indrajaal/l5/test/marionette/<run_id>/<phase>` (SC-MARIONETTE-012).
5. Returns:
   - Proposed test rows (markdown).
   - List of stable selectors discovered (key / text / type).
   - Any custom VM extensions enumerated.
   - Path to the run dir.

## Mandatory invariants

- `get_interactive_elements` BEFORE any tap/text in the same session (SC-MARIONETTE-003).
- Failure path captures screenshot + logs + tree before disconnect (SC-MARIONETTE-004).
- No invocation in release builds (SC-MARIONETTE-005).

## Examples

```
/marionette-explore fluffychat onboarding-login
/marionette-explore fluffychat send-image-with-caption --platform=android --record-video
/marionette-explore fluffychat verify-device-cross-signing --resume
```

## Math gates the run reports

- **Shannon H** across 16 Marionette tools used in this run (target ≥ 2.5 bits).
- **CCM** weighted coverage across {tap, gesture, text, capture, custom_ext} (target ≥ 0.90).
- **D** discovery-distance violations (target = 0).
- **S** evidence-sufficiency on every failure (must hold).

These are emitted in the final summary the skill returns to the operator.

## RETE-UL feedback channel

The Rust rule engine (subscribing to `indrajaal/l5/test/marionette/**`) may
post advisories that this skill surfaces in its summary:
`MarionetteSelectorDrift`, `MarionetteFlakeQuarantine`, `MarionetteBackpressure`,
`MarionetteEntropyFloor`. React per the rule definitions in
`.claude/rules/marionette-mcp-flutter-testing.md` §10.

## See also

- Allium spec: `specs/allium/marionette_mcp.allium`
- Rule: `.claude/rules/marionette-mcp-flutter-testing.md`
- Agent: `.claude/agents/marionette-explorer.md`
- Catalog reference: `sub-projects/sutra/fluffychat/integration_test/marionette/CATALOG.md`
- Journal: `docs/journal/20260428-032106-marionette-mcp-integration.md`
