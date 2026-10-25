---
name: living-ontology
description: Keep the wiki, zettelkasten, and the SQLite-backed living ontology current, interconnected, and unbroken — the symbiotic memory the agents and the system co-evolve.
---

# Living Ontology — the system's evolving memory

The ontology is **not a static doc**. It is a dynamic, SQLite-backed, OCaml-driven
structure with persistence and behavior — a *projection of the current system*
(codebase + ledger + served docs) that the agents read as knowledge and the harness
writes as it evolves. This skill governs how it — and the wiki/zettelkasten it indexes
— stay current, interconnected, and functional.

Database access must go through the harness or authored OCaml code. Use the
documented harness/MCP ontology operations or an OCaml module; never use a
direct database client or shell SQL.

Human-readable index: [[FRACTAL_ONTOLOGY]] (the fractal layer model) and [[ONTOLOGY]]
(the class model). Live view: the wiki route **`/ontology`**.

## The pieces (all OCaml + SQLite)

- **Store** — `onto_node` / `onto_edge` / `onto_refresh` in
  `harness/state/zigvm_harness.sqlite3`. Biomorphic: `first_seen` = birth,
  `last_seen`/`present` = alive vs dormant (a concept that leaves the system is
  *remembered* with `present=0`, never deleted). `onto_refresh` is the growth/health
  time-series — the ontology's memory of its own evolution.
- **Behavior** — `refresh_ontology` (`harness/zigvm_harness.ml`) derives the graph live:
  L0-L10, nine planes, Strata A/B/C, Axes F/C/O/P/S/R, canonical components,
  S1-S33, and typed interactions, plus path-identified modules, scripts, docs,
  fixtures, generated targets, formal artifacts, ledger tables, capabilities,
  slices, safety objects, rules, agents, faculties, tools, and services.
- **Wiki / zettelkasten** — pure OCaml: `harness/docs_wiki.ml` (the Model→View renderer,
  `[[wikilinks]]` + bidirectional backlinks) served by `harness/agent_workers.ml` (the
  Riot node on :8088). The corpus is every git-tracked `.md` under root, `docs/`,
  `skills/`, `proofs/`, `specs/`.
- **Enforcement** — the `--wiki-audit` (alias `--refresh-ontology`) harness action:
  refreshes the ontology AND audits the wiki/ZK (parity · broken-links · orphans ·
  health), recording an `onto_refresh` point. Run every 10 min by the
  `zigvm-ontology-audit.timer` systemd user unit (the symbiotic currency loop).

## The currency contract (rules)

1. **Every slice updates its model.** If a slice adds or renames a layer, plane,
   component, subsystem, interaction, controller, evidence store, route, agent
   surface, module, script, doc, fixture, generated target, or ledger table,
   update the canonical registry/docs and verify its live node/edge birth with
   `--wiki-audit`.
2. **Health = parity.** The functional guarantee is that every tracked doc becomes a
   served page (`wiki_parity = 0`). A parity break (a doc stopped serving) is a **red**
   — the audit exits non-zero. Broken `[[wikilinks]]` and orphans are **quality signals**
   (surfaced + trended), not functional breakage; fix them to keep the ZK interconnected,
   but an illustrative example-link (e.g. MUTATION_LOG documenting the link grammar) is
   expected.
3. **Interconnect.** Prefer `[[wikilink]]` over bare prose when a doc references another
   governing doc, so the zettelkasten graph stays dense. New hub docs link *out*; new
   leaf docs get linked *in* from a hub (reduce orphans).
4. **Never forge a green-stamp.** The audit run finalizes `status='wiki-audit'` (never
   `'ok'`), so it can never satisfy SC-ZeroTrust. Do not change that guard.
5. **The ledger is the source of truth.** The `/ontology`, `/report`, `/ops`,
   `/strategic` boards are *Views* over SQLite — never hand-edit the DB; let the harness
   write it.
6. **Projection is atomic and typed.** A refresh runs in one OCaml transaction.
   Every live edge has live endpoints and a declared interaction type; every
   canonical component has a layer and plane. Any failed law rolls back.

## OODA for currency

- **Observe** — `--wiki-audit` (or read `/ontology`); note parity, broken, orphans, and
  the `onto_refresh` trend (is the system growing? what went dormant?).
- **Orient** — a parity break is a served-doc regression (fix the corpus filter or the
  doc); a rising orphan count is ZK-decay (add wikilinks); a dormant node is a removed
  concept (expected on a deletion, suspicious otherwise).
- **Decide/Act** — fix the smallest thing that restores health; re-run `--wiki-audit`.
- **Verify** — all 11 ontology laws pass, parity is 0, and the new/changed nodes
  and interactions are present. Wiki quality warnings remain visible.

## Supporting skills

- [[skills--wiki-design--skill|wiki-design]] / [[skills--docs-design--skill|docs-design]]
  — the visual + authoring conventions for the pages this skill keeps current.
- [[skills--harness-supervisor--skill|harness-supervisor]] — the Tier-2 OODA loop over the
  same SQLite memory; the living ontology is that memory's semantic index.

## The full pass — one lean flow (zero muda)

Ṛtambharā runs a complete **OODA cognitive loop** on itself every 10 min
(`zigvm-ontology-audit.service`), all OCaml, none of it able to red the gate:

```
OBSERVE (audit: parity/broken/orphans) → ORIENT (vitality + foresight) →
DECIDE (next-best-action, consistency-lawed) → ACT (onto_task open/close, self-healing) →
LEARN (Raven Rune autodiff over its own memory, differential-admitted) → OBSERVE …
```

**Verify everything in one lean battery** (no waste — this IS the full fractal / SDLC / SRE /
formal / OODA evidence):

```sh
G="opam exec -- dune exec ./harness/zigvm_harness.exe -- --root $PWD"
$G                       # L9 gate — the fractal law suite (All N passed. + status=ok)
$G --verify-formal       # Rocq/Quint/Aeon/Lean + agent-codegen + sdlc-sre-rete rules
$G --selfcheck-slo       # SRE SLOs
$G --selfcheck-ooda      # the OODA loop laws
$G --wiki-audit          # living-ontology refresh + wiki/ZK audit + autonomic + foresight + decide
opam exec -- dune exec ./harness/organ_learn.exe -- $PWD/harness/state/zigvm_harness.sqlite3   # LEARN (isolated)
dune exec ./harness/test_viz.exe       # 38 viz/library-integration regression tests
dune exec ./harness/test_docs_wiki.exe # 89 wiki + zettelkasten renderer tests
```

**Data plane** (SQLite, the biomorphic memory): `onto_node`/`onto_edge` (layers,
planes, components, artifacts, interactions),
`onto_refresh` (evolution + vitality + foresight + decision series), `onto_task` (self-repair
backlog, self-healing), `onto_ml` (the Rune learning record). The `/self` dashboard is a View over
these — never hand-edit; the harness writes them.

**Rules (the lean discipline):** health = parity (functional); a decision never names a defect that
does not exist (consistency law); the learning organ is admitted only when it agrees with an
independent oracle (differential); `nx`/`rune` stay OUT of the gate exe (isolation); the audit run
never mints a green-stamp (`status='wiki-audit'`); and no organ is added without real data or
justification — completeness comes from **closing the loop**, not adding organs.

## Seeing itself — the visualization layer (all OCaml-fed, offline)

The organism renders its own structure. OCaml generators emit the specs/data; vendored
runtimes render them in the wiki (no CDN). To *see* the ontology:

| Route | View | OCaml generator | Runtime |
| --- | --- | --- | --- |
| `/self` · `/ontology` | the living dashboard (KPIs, faculties, backlog, vitality) | in `agent_workers.ml` | pure OCaml |
| `/atlas` | fractal spine + cognitive-loop ring (SVG) | in `agent_workers.ml` | pure OCaml SVG |
| `/vega` | fractal bubble-ladder | `atlas_vega6.ml` (pure Vega 6) | vendored `vega@6.1.2` |
| `/vegalite` | evolution area chart | inline VL spec | vendored `vega-lite@6` |
| `/grid` | every node, sortable/filterable | inline row data | vendored `ag-grid` community |
| `/docs/graph` | zettelkasten link-graph | `docs_wiki.ml` | pure OCaml SVG |

`atlas_graphml.ml` emits `web/ontology.graphml` as a standards-based interchange
artifact. OCaml owns the complete export; no Python or non-OCaml repository
script is part of the ontology path.

**Rule:** OCaml owns the data + the specs; the renderer is a swap behind the typed model
(`OntoNode`/`OntoEdge`/`LayerKind`/`EvoPoint`). Vendored runtimes stay OUT of the gate exe.
Regenerate after structural change: `dune exec ./harness/atlas_vega6.exe -- <db> > web/vega6-spec.json`.

## Fractal FP atlas synchronization

Changes to ontology nodes, edges, layers, controllers, evidence, routes, or
agent surfaces are atlas-governed. Update both living-ontology registries and
the Fractal FP registry, regenerate all eleven projections, run
`--selfcheck-fractal-fp-atlas` plus `--wiki-audit`, and record
`phase:atlas_sync`. The generated views are projections; exact-head OCaml laws
and gate evidence remain authority.
