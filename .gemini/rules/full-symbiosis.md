---
trigger: always_on
---

# Full Symbiosis Rule

## Purpose

Keep Codex/GPT, Claude, Gemini, `.agents`, repo-local `.codex`, Pi-mono, and C3I runtime surfaces aligned whenever rules, skills, agents, hooks, webhooks, task plans, or journals change.

## Mandatory State

- **Rule parity**: mirror enforceable policy across `.claude/rules`, `.gemini/rules`, `.agents/rules`, and durable `.codex/rules` summaries where those surfaces exist.
- **Skill parity**: mirror executable workflows across `.claude/skills`, `.gemini/skills`, `.agents/skills`, durable `.codex/skills` summaries, and user-local Codex skills when available.
- **Agent parity**: mirror supervisory role definitions across `.claude/agents`, `.gemini/agents`, `.agents/agents`, and durable `.codex/agents` summaries.
- **Hook parity**: update `settings.json` / `settings.local.json` hook guards so future edits to governance, webhook, and `.codex` surfaces receive the same constraints.
- **Task parity**: represent non-trivial symbiosis work in `sa-plan` / work-plan where available.
- **Evidence parity**: update journal, ZK, HTML, slide, and email artifacts when the work changes operator-visible state.

## Surface Coverage Matrix

| Surface | Required State |
|---|---|
| Work surface | Local adapters, Codex-compatible rules, and `.claude/settings.local.json` carry the same constraints as C3I without staging `gdrive/`. |
| C3I root | Canonical `.claude`, `.gemini`, `.agents`, repo-local `.codex`, docs, and task ledgers remain the source of durable operator evidence. |
| Nested C3I | Nested `.claude`, `.gemini`, `.agents`, docs, and Rust/Gleam runtime services remain aligned with `sa-plan`, scheduler, journal, vault, and ZK workflows. |
| Pi-mono | `.claude`, `.gemini`, `.agents`, and pi-specific hooks preserve Effect TS, IIFE, and provider compatibility. |
| Codex/GPT | Repo-local `.agents`, durable `.codex` summaries, and user-local Codex skills expose the same operational workflow to GPT agents without copying user-local runtime state. |
| Journals/tasks | Every non-trivial cross-surface change has task state, completion evidence, and drift notes. |

## L0-L7 Gate

| Layer | Gate |
|---|---|
| L0 Constitutional | No rule bypass, no silent downgrade, no contradictory active guidance. |
| L1 Atomic | Data, absence, error, panic, and secret semantics must be typed and explicit. |
| L2 Component | Skills and agents must point to real files and current runtime boundaries. |
| L3 Transaction | Hooks/webhooks must be idempotent, timeout-bounded, and non-secret-bearing. |
| L4 System | C3I, work, pi-mono, Claude, Gemini, `.agents`, repo-local `.codex`, and Codex mirrors must agree. |
| L5 Cognitive | Journals and ZK notes must capture decisions, evidence, and residual risk. |
| L6 Ecosystem | External docs/webhooks require source attribution and operator-approved credentials. |
| L7 Federation | Cross-tree changes must avoid `gdrive/`, preserve dirty work, and document drift. |

## Runtime Language Rules

- Generated or modified TypeScript must use Effect (`effect`), not `fp-ts`.
- Browser/runtime JavaScript must be generated IIFE output from Effect TypeScript unless explicitly waived.
- Generated or modified Rust must use `fp-core = "0.1.9"` where applicable and target >=95% functional style.
- Runtime Rust must not add new `unwrap`, `expect`, `panic!`, or undocumented unsafe paths.
- New automation should be Gleam or Rust, not shell/Python/Node scripts.

## Change Protocol

1. Classify the change as rule, skill, agent, hook, webhook, code, task, or artifact.
2. Identify every mirror that already contains that class; include root C3I, nested C3I, pi-mono, work, repo-local `.codex`, and user-local Codex surfaces before declaring parity.
3. Update the canonical work-surface file first, then copy or patch C3I and pi-mono mirrors.
4. Keep webhook commands as warnings or deterministic local guards; do not add network callbacks unless credentials and consent are explicit.
5. Preserve existing dirty work by changing only the files needed for the symbiosis task.
6. Validate JSON, Markdown links, mirror presence, and language-specific constraints before closure.

## Drift Classes

- **P0 contradiction**: two active rules disagree about TypeScript, Rust, secrets, task state, or tool safety.
- **P1 missing guard**: a runtime can edit governed files without receiving the full symbiosis reminder.
- **P1 stale skill**: a skill exists on one surface but not on another active agent surface.
- **P2 stale agent**: supervisor role text exists but does not describe current hook/task/codegen constraints.
- **P2 evidence gap**: implementation changed operator-visible behavior without journal/task/validation evidence.

## Validation

- Run `jq empty` on changed hook JSON.
- Run a link check for changed journal/webhook Markdown when available.
- Search touched TypeScript for `fp-ts` / `TaskEither` regressions.
- Search touched Rust for new `unwrap(`, `expect(`, and `panic!`.
- Record any skipped validation with a concrete reason.

## Continuous Report Quality Parity

When report-quality guidance changes, synchronize the five-level standard across rules, skills, agents, hooks, webhooks, journal, HTML, and email artifacts:

1. Every generated artifact must be current, source-backed, useful, visually informative, cross-artifact consistent, and gate-verified.
2. Agents must reject low-information output and require Claim/Evidence/Source/Risk/Quality.
3. Report bundles must cover web/runtime, data path, control plane, rules, STAMP, AOR, skills, agents, hooks, FMEA/FEMA, RETE-UL, ruliology, coverage math, L0-L7, all clients, and delivery readiness.
4. File existence, image size, word count, and attachment count are not quality proof.
5. Email or closure cannot proceed when the relevant Gleam quality gate fails.
