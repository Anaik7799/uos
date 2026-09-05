---
name: infranodus-design-superset
description: Design, generate, journal, materialize, and verify the InfraNodus-compatible UI as one OCaml-owned design superalgebra with Figma, Google Stitch, GetDesign, Impeccable, Bonsai, and Zettelkasten profiles. Use for capability/page/component expansion, DESIGN.md generation, Figma or Stitch work, design-quality audits, self-contained evidence journals, and typed OCaml Playwright parity closure.
---

# InfraNodus Design Superset

Pair this skill with `algebra-driven-ocaml`, `ocaml-figma-control`,
`ocaml-playwright-control`, `mobile-first-adaptive-ui`, and
`zk-knowledge-base`. Read
`docs/journal/20260804-infranodus-design-superset-journal.md` for the research
and current status. Read `references/profile-contract.md` before changing a
profile and `references/journal-contract.md` before publishing evidence.
Read `references/execution-character.md` before running or changing the
Approach B bundle pipeline, its budgets, telemetry, hard controls, or assurance
envelope.

## Integrated workflow (read before acting)

The end-to-end operating manual is `docs/design/INTEGRATED_DESIGN_WORKFLOW.md`
— the W0–W8 stage lattice (carriers → planning/P0 → Figma projection → S7
generator → refinement → Bonsai runtime → typed verification → hash-verified
publication → evidence/knowledge), the ten-loop fast-feedback OODA spine, RRDF
grades per stage, the hazard-containment map, and the integrated P0→P9 phase
walk. Its analysis of record is `docs/design/FIGMA_FRACTAL_STPA_ENVELOPE.md`
(constraints SC-F1–SC-F41). Disagreement between the two is a defect, fixed
algebra-first.

**Doing the work:** `INTEGRATED_DESIGN_WORKFLOW.md` §8 is the phase activity
runbook — per phase P0..P9 (plus the optional P3½ generator stage) it states
entry criteria, the numbered activities in their required order, the evidence
produced, exit criteria, and which guards fire. Follow it rather than
improvising a phase; an improvised activity set is invisible to the next
session (SC-F42) and its declaration is gate-enforced.

MECHANIZED arms (not protocol — these RED the gate, envelope §25/§28):

- `--check-design` (also inside `check_docs`, therefore in the canonical gate):
  the SC-F registry must stay TOTAL (contiguous 1..max), every SC-F cited by a
  sibling design doc must resolve, and the runbook must declare an activity
  block for every phase P0..P9. Adding a constraint means adding it to the
  envelope, contiguously; adding a phase means declaring its activities.
- `SC-DESIGN-1` (Zero-Trust `verify_cycle`): a cycle whose commit changed
  `docs/design/tokens.json|tokens.css` without `harness/figma_design.ml` or a
  visible `regen:` acknowledgement is REJECTED.
- `SC-DESIGN-2` (same): a cycle whose commit changed a published journal HTML
  without a real sha256 digest, or an explicit `publication:unverified`
  disclosure, is REJECTED.

Both rules admit an honest DISCLOSURE but never silence. Everything else in the
SC-F register remains protocol-enforced; do not describe it as mechanized.

## Authority

- Keep the semantic source in typed OCaml. Treat Figma and Stitch as external
  interpretations, GetDesign as documentation/catalog projection, Impeccable
  as advisory quality projection, and Bonsai as executable interpretation.
- Never import Stitch React/TypeScript or Figma plugin JavaScript as authored
  implementation.
- Emit `Exact | Equivalent | Advisory | Generated | Unsupported | Unavailable`
  for every projected concept. Never silently drop a residual.
- Keep authentication in the external substrate. Never persist passwords,
  tokens, cookies, recovery codes, or OAuth secrets.

## Fractal Workflow

1. Observe the canonical capability, page, component, token, transition,
   responsive, accessibility, provenance, and evidence registries.
2. Add or change the smallest OCaml carrier and observation.
3. State laws and at least two meaningful mutant targets for the slice.
4. Make the initial operation-list interpretation green.
5. Generate the affected Figma, Stitch DESIGN.md, GetDesign, Impeccable, and
   Bonsai projections.
6. Materialize external profiles only after the OCaml projection exists.
7. Read back external IDs, metadata, screens, variants, exports, and residuals.
8. Verify runtime behavior through direct typed OCaml Playwright at the
   canonical viewport matrix.
9. Publish Markdown, self-contained HTML, prompt provenance, screenshots,
   video, traces, and the residual ledger as one Zettelkasten-connected bundle.
10. Repeat OODA until every registered observation is accepted or honestly
    bounded.

## Mandatory Approach B Execution Rule

- Use the versioned OCaml bundle manifest for recurrent publication. The
  validated bundle is the sole input to acquisition, rendering, fanout, and
  evidence generation.
- Preserve the sequential interpretation as oracle and admit bounded
  parallelism only by observational equivalence.
- Render the archival HTML once, publish identical bytes through the
  serialized per-target atomic crash-recoverable transaction, and reuse
  the content-addressed wiki projection on unchanged inputs.
- Print actual time and budget for every stage in the TUI and dashboard. Reject
  stage-budget overruns and cache-hit warm paths at or above 1500 ms.
- Emit metrics, the self-contained live dashboard, and OpenTelemetry-compatible
  file logs as report-only observers. They never decide gate state.
- Apply TDD, BDD, property laws, mutant kills, typed OCaml Playwright, STPA/FMEA,
  ACH, Admiralty grading, devil's advocacy, and an explicit reality-check
  summary at the operation, stage, bundle, UI, knowledge, and system scales.
- Every new human-facing timestamp is `YYYYMMDD-HHMMSS`; protocol-native OTEL
  timestamps remain Unix nanoseconds. Require `--check-time` before handoff.
- Treat recurrent publication as an OAIS-inspired package pipeline. Preserve
  the SIP sources and provenance, compute/verify SHA-256 for every AIP/DIP copy,
  inventory open formats, and record versioned migration/residual plans.
- Maintain the tripartite PKM loop: append-only journal capture, atomic stable-ID
  zettels with typed reciprocal links, and wiki/MoC synthesis. Plain Markdown,
  JSON, and JSONL remain authoritative; Obsidian and Logseq are replaceable
  views, never the only copy of meaning.
- New PKM frontmatter follows `docs/PKM_ARCHIVAL_ARCHITECTURE.md`; local IDs use
  the `YYYYMMDD-HHMMSS` prefix plus a non-temporal collision suffix. Never invent
  DOI/ORCID assignments or claim ISO/OAIS certification without external proof.
- Logseq interoperability is governed by
  `docs/LOGSEQ_OCAML_SUPERSET_ARCHITECTURE.md` and the generated
  `docs/ontology/LOGSEQ_OCAML_PROFILE.json`. Every upstream feature must have
  an OCaml-owned `Exact | Equivalent | Advisory | Unsupported | Unavailable`
  row, source, wiki mapping, and ZK mapping. Plain-file parsing must round-trip
  bytes; page/block/tag observations must agree with wiki/ZK edges. DB/RTC,
  mobile, sync, plugins, themes, and community extensions remain external and
  cannot be described as implemented without live independent evidence.
- Close every audited item in the exact lattice `Verified |
  Rejected_by_policy | Unavailable_observed`. Reject pending/unknown states,
  missing owners, blank observations, and blank reopen evidence. Generate and
  validate `docs/ontology/INFRANODUS_FRACTAL_CLOSURE.json` together with its
  human Markdown projection.

## Acceptance

- Figma variable/component/screen/transition closure is green.
- Stitch DESIGN.md has zero errors and every remote object reads back.
- GetDesign catalog coverage equals the registered design surface.
- Impeccable findings are evidence-linked and never semantic authority.
- Bonsai page/component/action registries are total.
- Figma, Stitch, and Bonsai agree on shared observations.
- Responsive non-amputation, accessibility, and content non-invention hold.
- Journal HTML has no remote runtime assets and embeds every prompt ledger and
  selected evidence artifact.
- Wiki audit reports the new journal/skill/spec graph honestly.
- External absence is `UNAVAILABLE` or `UNTESTED`, never fabricated PASS.

## Handoff

Record exact toolchain versions, Figma file/node IDs, Stitch project/screen
resources, seeds, viewports, law results, mutants, screenshots, videos, prompt
ledger paths, residuals, and the next smallest OODA slice.
