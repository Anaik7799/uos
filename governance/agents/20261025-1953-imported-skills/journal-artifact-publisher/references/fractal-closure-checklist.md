# Fractal Closure Checklist

Use this reference when a journal bundle claims full closure, all blocked items fixed, all issues addressed, multilayer supervision, or L0-L7/fractal component coverage.

## Required Closure Claims

Do not claim full closure unless every claim is tied to evidence. Use these statuses:

- `verified`: command or artifact check passed in the current pass.
- `historical_evidence`: observed in a prior pass and clearly labeled.
- `expected_not_verified_current_pass`: structurally available but not checked now.
- `blocked_current_pass`: attempted and failed, with exact error.
- `not_applicable`: not part of the operator directive.

## L0-L7 Layer Matrix

| Layer | Required journal evidence | Minimum artifact evidence |
|---|---|---|
| L0 Constitutional | Active hard rules, forbidden paths, language/runtime constraints, no false claims. | Journal guardrails, manifest validation, stage boundary, no `gdrive/` unless requested. |
| L1 Atomic | Function/field-level fixes, local validators, parse checks, DB checks. | File-level deltas, `jq empty`, `test -f`, `rg`/link checks, Rust/Gleam command output. |
| L2 Component | CLI/component/channel behavior and independent component pass/fail status. | Work-plan commands, HTML report, deck, email draft, index, links manifest. |
| L3 Transaction | Ordered multi-step operations and side-effect safety. | Dry-run gates, task lifecycle, send/upload gates, rollback/degraded notes. |
| L4 System | Cross-folder/cross-repo ownership and system boundaries. | Work surface vs git repo distinction, `PROJECT_TODOLIST.md`, status/sync evidence. |
| L5 Cognitive | Journal/rules/skills/agents and knowledge ingestion. | 13-section journal, skill references, `ingest-docs --dry-run`, ZK/RAG notes. |
| L6 Ecosystem | Provider/tool/runtime parity across surfaces. | `.claude`, `.gemini`, `.agents`, Codex/GPT compatibility notes, route classes. |
| L7 Federation | Handoff across local, served, operator, and external channels. | Relative links, route status, email attachments, optional upload plan, no unverified live route claims. |

## Component Checklist

Every comprehensive bundle should cover these components or explicitly mark them `not_applicable`:

- Markdown journal with all 13 required sections.
- Self-contained HTML analysis report.
- Scrollable, JavaScript-free slide deck.
- Email draft with recipient gate, attachment list, and send command template.
- Operator handoff index with local verification commands.
- Links manifest with local paths, relative hrefs, expected routes, and validation results.
- sa-plan task lifecycle: add/reuse, in-progress, sync, status, ingest dry-run, completion gate.
- Git staging boundary: exact pathspec and no `gdrive/` staged.
- Runtime validation evidence: Rust, Gleam, DB, CLI smoke, daemon/status gates when relevant.
- Remaining gap table for warnings, quality scores, route checks, email, upload, or unrelated dirty state.

## Fractal Supervisors

For multilayer supervision claims, identify the reviewer role by layer instead of inventing invisible agents:

- L0 policy supervisor: validates hard rules and prohibited paths.
- L1 validator: validates atomic commands and file-level checks.
- L2 component reviewer: validates each artifact/channel independently.
- L3 transaction reviewer: validates ordered task and dry-run sequences.
- L4 system reviewer: validates folder/repo and task-management integration.
- L5 cognitive reviewer: validates journal/skill/knowledge ingestion completeness.
- L6 ecosystem reviewer: validates provider parity and runtime compatibility.
- L7 federation reviewer: validates handoff routes, email/upload gates, and local fallback.

## Failure Semantics

- If an initial command fails and a corrected command later passes, record both.
- If a score reports poor quality but exits successfully, mark it as a quality gap, not a command failure.
- If routes are not checked, mark them `expected_not_verified_current_pass`.
- If email has no concrete recipient, keep the draft and mark send blocked.
- If GDrive is skipped, do not create, stage, or mutate any `gdrive/` path.
