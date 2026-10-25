---
name: journal-artifact-publisher
description: "Gemini mirror for creating, validating, and publishing C3I journal bundles: Markdown journal, HTML analysis, slide-deck HTML, email draft/send payload, operator handoff index, links manifest, sa-plan task/update/sync/status evidence, workflow/job/schedule evidence, ZK ingestion, L0-L7 fractal closure, and optional upload planning. Rust/Gleam-only: use `sa-plan`, Rust/Gleam validators, and static artifacts; no Python/Node ad hoc scripts."
---

# Journal Artifact Publisher

Use this skill for every Gemini-authored artifact bundle that needs journal, HTML, slides, email, links, task-management integration, and full fractal closure evidence.

## Required Bundle

- `*-journal.md` with all 13 journal-protocol sections.
- `*-analysis.html` self-contained operator report.
- `*-deck.html` scrollable HTML slide deck.
- `*-email.md` email draft with attachment list and send command template.
- `*-index.html` operator handoff index.
- `task-<id>-links.json` or task-local `links.json`.
- sa-plan task ID, URN, priority, status, command evidence, and degraded-mode notes.
- L0-L7 fractal closure matrix when claiming full closure, fixed blockers, fixed all issues, or multilayer supervision.

## Workflow

1. Read `.gemini/skills/journal-protocol/SKILL.md` when present.
2. Use `/home/an/dev/ver/c3i/.claude/skills/journal-artifact-publisher/references/artifact-contract.md` for the canonical artifact contract.
3. Use these canonical references for artifact-specific detail:
   - `references/journal-template.md`
   - `references/html-report.md`
   - `references/slide-deck.md`
   - `references/email-payload.md`
   - `references/sa-plan-workflow.md`
   - `references/link-validation.md`
   - `references/task-management-integration.md`
   - `references/fractal-closure-checklist.md`
4. Create or reuse a real sa-plan task using `./sa-plan add`; record exact failure if unavailable.
5. Create artifacts under `docs/journal/`.
6. Validate links with `jq empty`, local file existence checks, and route status fields.
7. Run `./sa-plan status`, `./sa-plan sync`, and `./sa-plan ingest-docs --dry-run` when available.
8. Send email only when a recipient is explicit or a higher-priority local notification rule names the recipient.
9. Stage only files belonging to this bundle; never bulk-stage `.gemini/**` drift.

## Fractal Closure Gate

- Record L0 constitutional, L1 atomic, L2 component, L3 transaction, L4 system, L5 cognitive, L6 ecosystem, and L7 federation evidence.
- Include all artifact channels or explicitly mark a channel `not_applicable`.
- Separate verified current-pass results from historical evidence and expected-but-unverified routes.
- Keep skipped GDrive, blocked email send, warnings, and quality-score gaps visible.

## Guardrails

- Preserve Gemini identity in `.gemini/**`; do not convert Gemini text to Claude text.
- Do not touch `gdrive/` unless explicitly requested.
- Do not use Python/Node scripts for bundle generation.
- Do not claim live Tailscale/customer links unless route checks passed.
- If `sa-plan` fails, record degraded-mode evidence and keep current-pass task claims false.
