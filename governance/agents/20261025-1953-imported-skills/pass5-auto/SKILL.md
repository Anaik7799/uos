---
name: pass5-auto
description: "Execute the Ultra-Pass-5 deliverable pipeline (journal + analysis HTML + slide deck + 5 diagrams + screenshots + email + ZK ingest + links.json + child tasks)."
---
# Ultra-Pass-5 Auto Pipeline Command

Runs the full SC-PASS5-AUTO-001 pipeline for a newly-implemented feature or closed task.

## Usage

```
/pass5-auto <feature-slug>
/pass5-auto --task-id <id>
```

## What it does

1. **RECALL** — search both ZKs for `<feature-slug>`, emit ≥ 5 holon citations.
2. **PLAN** — `./sa-plan add "<title>" P0` for parent, then fan out child tasks for each FMEA row.
3. **BUILD** — `cd lib/cepaf_gleam && gleam build && gleam test` (must stay green).
4. **RENDER** — 5 Graphviz diagrams (control, data, fractal, MSC, SM) via `dot -Tpng`.
5. **SHOOT** — 3+ headless-chromium screenshots (HTTP dashboard, HTTPS dashboard, task-page).
6. **WRITE** — journal MD (10+ sections), analysis HTML, slide deck HTML.
7. **MIRROR** — copy everything into `sub-projects/c3i/docs/journal/` (daemon CWD).
8. **INDEX** — `docs/journal/task-<id>-links.json` with every URL.
9. **INGEST** — `./sa-plan ingest-docs` (new holons + STAMP refs).
10. **EMAIL** — `./sa-plan send-email --to Abhijit.Naik@bountytek.com --attach ...`.
11. **SYNC** — `./sa-plan sync` (PROJECT_TODOLIST.md).
12. **VERIFY** — `curl -sk` every URL returns HTTP 200.

Reference: `.gemini/rules/sc-pass5-auto-001.md`
Reference implementation: task `116450171390820012` (slug `20260422-212140-...-ultrapass5`).

## Acceptance

- ZK citation rate ≥ 90 %
- All URLs return HTTP 200
- ≥ 15 KB journal, ≥ 12 KB analysis, ≥ 10 KB deck
- Email delivered, sa-plan `✅ sent`
- ZK `Total holons in KMS` increased by ≥ 3
- PROJECT_TODOLIST.md synchronized
- At least 1 child task transitioned to `completed`
