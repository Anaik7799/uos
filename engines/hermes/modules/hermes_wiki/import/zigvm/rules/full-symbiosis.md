# Full Symbiosis Rule

This rule keeps Claude, Codex, Gemini, and future agent clients observationally
equivalent inside the zigvm project.

## Canonical Sources

- `AGENTS.md` is the binding repository rulebook.
- `CLAUDE.md`, `CODEX.md`, and `GEMINI.md` are vendor entrypoints, not forks.
- `skills/README.md` is the canonical skill inventory.
- `skills/*/SKILL.md` are the canonical skill bodies.
- `docs/AGENT_HANDOVER.md` and `docs/AUTONOMOUS_RUNBOOK.md` define bootstrap,
  OODA, dispatch, verification, and recording.

## Mirror Law

The repo-local `.claude/skills`, `.codex/skills`, `.gemini/skills`, and
`.agents/skills` mirrors must expose the same linked skill set declared in
`skills/README.md`, and every mirror entry must be a symlink to the matching
repo `skills/` directory. User-
local mirrors such as `~/.codex/skills` may exist, but they are not the project
source of truth.

## Entry Point Law

Shared project facts must stay synchronized across `CLAUDE.md`, `CODEX.md`, and
`GEMINI.md`: command surface, gate semantics, hard language boundaries, MCP
staleness rule, Zig toolchain discovery, default OTP-parity loop, and linked
skill inventory. Vendor-specific sections may differ only where the client
mechanics differ.

## OCaml Toolchain Law

Every vendor uses the exact local OCaml 5.5.0 switch and the same
`scripts/setup_ocaml_550.ml` install/check controller. The opam manifest,
tree-hash-verified local pins, `vendor/ocaml-5.5-patches/`, complete PPX closure,
and js_of_ocaml generated-target boundary are shared facts. Agents must not add
an ad hoc pin, alternate package repository, or untracked bootstrap path to one
vendor surface. The shared admitted web closure is Bonsai/Bonsai_web/Virtual_dom
`v0.18~preview.130.106+341` plus Dream `dev`; the browser bundle is generated
from OCaml and Dream reaches SQLite only through the harness `Db` actor.

## Agent Law

Supervisor profiles under `docs/agents/` must bind every agent to the same MCP
control plane, SQLite position truth, L3 verification recipe, and
record-cycle discipline. A worker report is never evidence until the harness
gate, ledgers, and SQLite rows corroborate it.

## Database Access Law

Database access must go through the harness or authored OCaml code. Every
vendor and supervisor surface must reject direct SQLite CLI, Python binding,
shell SQL, and non-OCaml client access. Missing operations are added as typed
harness/MCP modes or OCaml modules; they are never worked around out of band.

## Decision-Support Law

Every vendor and supervisor surface treats a Stan/Bayesian posterior as
ADVISORY, never authority. The Stan surfaces (`--stan`, `--stan-scenarios`, and
the per-cycle report in `--decision-frame`; `harness/stan_bridge.ml`/
`stan_mcmc.ml`/`stan_report.ml`/`prob_classify.ml`; `skills/stan-probabilistic-
substrate` + `skills/fractal-decision-calculus`) compute posteriors, credible
intervals, a PHIA/NATO estimative-probability classification, a subjective-
expected-utility framing, and a behavioural bias-taxonomy overlay — all report-
only. Posterior-gating of any decision is a permanent reject shared across
Claude, Codex, and Gemini; the hard gates (Admiralty ≥A2, AHP CR<0.10, the Coq
proofs, the armed Rete rule) decide. stanc3 is a vendored OCaml library and the
cmdstan C++ runtime a disclosed external dependency invoked via Unix exec; all
posterior data comes through the harness `Db` actor, never a raw client.

## Document-Lint Law

Every vendor and supervisor surface inherits the same document lint.
`--check-lint` runs inside `check_docs`, hence inside the canonical gate, and
its ratchet `docs/design/lint-baseline.txt` stands at `errors = 0,
warnings = 0`: there is no backlog for a new finding to hide in.
`SC-LINT-RATCHET` (`Rete_rules.lint_rules`, routed through `all_rules`) refuses
a cycle that edits the ceiling without a visible `ratchet:` statement.

Two algebras decide, not heuristics: `docs/design/TABLE_ALGEBRA.md` and
`docs/design/HTML_ALGEBRA.md`, each with an ontology, signature, semantic
domain, oracle and final encodings, and laws executable in `--verify-formal`.
Severity is a function of PROVENANCE — an authored document is held to what a
renderer does with it, while **every finding on a generated artifact is an
`Error`**, with no ratchet and no exception. No vendor may weaken this split,
re-implement the rules locally, or raise the ceiling to unblock work.

`--lint-report` is report-only: it publishes metrics, an OTLP span stream in
Unix nanoseconds and a self-contained dashboard, and a source-scan law denies
the projection module any effectful token. A dashboard is never cited as gate
evidence; `--check-lint` and the SQLite run status are.

## Design-Governance Law

Every vendor and supervisor surface inherits the same mechanized design arms.
`--check-design` (SC-F registry totality + reference-cleanliness + phase-runbook
totality P0..P9) runs inside `check_docs`, hence inside the canonical gate; `SC-DESIGN-1`/`SC-DESIGN-2`
(`Rete_rules.design_rules`, routed through `all_rules`) fire in the Zero-Trust
`verify_cycle` path shared by MCP `record_cycle` and CLI
`--verify-cycle SLICE NOTES`; the CLI replays the exact record context. A
generated design artifact changed without its generator, or a published journal
HTML changed without its sha256 digest, is rejected unless the cycle carries a
visible `regen:` / `publication:unverified` disclosure. Silence is never
admissible; an honest disclosure always is. No vendor may weaken, bypass, or
locally re-implement these rules. The operating manual is
`docs/design/INTEGRATED_DESIGN_WORKFLOW.md` (W0–W9 lattice, OODA spine, RRDF
grades, P0→P9 walk, and §8 the per-phase ACTIVITY RUNBOOK every vendor follows
instead of improvising a phase); the analysis of record is
`docs/design/FIGMA_FRACTAL_STPA_ENVELOPE.md` (SC-F1–SC-F41). Constraints beyond
the arms named in envelope §25 remain protocol-enforced and must not be
described as mechanized.

## Validation Law

After a symbiosis edit, validate changed JSON/settings, validate skill
frontmatter through the harness doc gate or standalone skill validator, check
that skill mirrors are isomorphic, and run the relevant harness gate before
declaring the sync complete.
