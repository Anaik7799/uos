---
name: timestamp-sync
description: Synchronize system and OpenCode timestamps. Runs at session start and every 30 minutes. Enforces mandatory YYYYMMDD-HHSS- document prefix.
---
# Timestamp Sync Skill
# Purpose
Ensure system and OpenCode timestamps are synchronized to prevent drift, and enforce the mandatory `YYYYMMDD-HHSS-` document naming convention across all generated artifacts.

# Mandatory Document Prefix Rule
Per explicit operator directive and `contracts/rules/timestamp-mandate.md`:
**All generated documents (journals, plans, specifications, briefs, reports) MUST begin with `YYYYMMDD-HHSS-` prefix.**
Format: `YYYYMMDD-HHSS-<kebab-case-title>.md`
- `YYYY`: 4-digit calendar year (e.g., `2026`)
- `MM`: 2-digit month (`01`–`12`)
- `DD`: 2-digit day (`01`–`31`)
- `HH`: 2-digit hour (`00`–`23`)
- `SS`: 2-digit seconds (`00`–`59`, no minutes field)
Example: `20260905-1725-codex-verification-journal.md`.
Enforced by: `tools/uos timestamp-check` and `engines/hermes/modules/hermes_dependability/dependability_clock.ml`.

# Usage
# Automatic (Recommended)
The Rust daemon runs in background:
```bash
# Start daemon
~/.config/opencode/bin/timestamp-sync-hook.sh start
# Check status
~/.config/opencode/bin/timestamp-sync-hook.sh status
# One-shot sync
~/.config/opencode/bin/timestamp-sync-hook.sh sync
```
# Features
- **Rust Daemon**: Long-running background process
- **TUI**: ANSI color-coded display
- **Fractal Logging**: L0-L7 JSON Lines
- **Zenoh**: Telemetry publisher
- **OTEL**: Traces to JSONL
# Thresholds
| Drift | Level | Color | Action |
|-------|-------|-------|--------|
| 0-2s | NOMINAL | Green | Log |
| 2-5s | MINOR | Yellow | Warning |
| 5-10s | WARNING | Magenta | Alert |
| >10s | CRITICAL | Red | Halt + NTP |
# Files
| File | Purpose |
|------|---------|
| `~/.config/opencode/bin/timestamp-sync-hook.sh` | Hook script |
| `~/.local/share/indrajaal-timestamp-sync/` | Daemon data |
| `logs/fractal.log` | Fractal logs |
| `logs/otel_traces.jsonl` | OTEL traces |
# Integration
Added to `AGENTS.md`:
- Session bootstrap with timestamp sync
- Hook location documented
- Mandatory `YYYYMMDD-HHSS-` filename enforcement
