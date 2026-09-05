---
id: hermes-project-structure-fractal-ontology
status: published
type: reference
ktype: moc
maturity: incubating
domain: formal_verification
topics: [structure, workspace, ontology, strata]
created: 2026-08-09
last_verified: 2026-08-12
verified_by: agent
next_review: 2026-09-09
---
# Project structure — fractal ontology

The workspace's own entities, levels and modal strengths — the same
treatment the six comparators received, applied reflexively. Companions:
[[Project structure — fractal atlas]] · [[Project structure — fractal algebra]].

## 1. The level lattice

| W | Level | Entity | Defined by |
|---|---|---|---|
| **W0** | Workspace | the repository | `dune-project` (tracked, `hermes_workspace`) |
| **W1** | Stratum | production · incubation · record · runtime · parked · vendored | the root `dune` scan policy |
| **W2** | Component | a production module or incubating project | its directory and Dune declarations; an actor-modeled component additionally owns an FPP base-id window |
| **W3** | Concern | `src/engine`, `src/control`, `test/`, `baseline/`, `pages/`, `import/` | a dune library or a pinned data root |
| **W4** | Module | an `.ml`/`.mli` pair | its interface and laws |
| **W5** | Artifact | a page, a pin line, a gauge, a register row | one ledger row |
| **WX** | Policy plane | the scan policy, `.gitignore` | machinery, never content (the LX mirror) |

## 2. The strata, with what each IS

| Stratum | Path | Promise |
|---|---|---|
| **production** | `modules/` | admitted to the root Dune scan; implementation, tests and formal surfaces live here (three empty reservations are disclosed) |
| **incubation** | `projects/` | builds in isolation, owns its docs, invisible to the root scan until it graduates |
| **record** | `docs/hermes/` | living plans and the append-only journal — never rewritten |
| **runtime** | `state/` | regenerable output (SQLite, OTel, dashboard, site, media and temporary run state) |
| **parked** | `zigvm_legacy/` | preserved history with a per-file map as its undo record |
| **vendored** | `external/ third_party/ vendor/` | inputs we do not own; data to the build |

## 3. Policy and data-only roots

The six strata are the normative path partition. The live root also contains
the policy plane and build-excluded auxiliary roots; exclusion from Dune does
not silently make them a seventh stratum.

| Class | Paths | Current use |
|---|---|---|
| **WX policy** | `.claude/ .agents/ .codex/ .gemini/` plus root Dune/opam files | shared instructions and product-native projections |
| **derived** | `generated/ _build/` | checked-in model/proof projections and untracked build output |
| **auxiliary data-only** | `rust/ scripts/ ui_web/ webedit/ tools/ providers/ _gospel/` | FFI input, historical utilities, reserved and legacy surfaces excluded by the scan policy |
| **local environment** | `.firecrawl/ .superdesign/ .superpowers/ .venv/ venv/ libev-4.33/` | local crawl/design/SDD/tool residue, never production authority by location alone |

The auxiliary roots are the observed SW1/SW4 residual: they are build-excluded
but do not all reside below one of the six promised path boundaries. The
algebra records that distinction rather than promoting exclusion to
classification.

## 4. Modal strength per relation

| Relation | Strength | Held by |
|---|---|---|
| production admission | **enforced** | the scan policy: only `modules/` contributes nested Dune stanzas |
| total stratum membership | **required, currently partial** | SW1; auxiliary root residue above remains explicit |
| corpus membership | **derived** | `git ls-files` — reviewable in a diff |
| wiki self-containment | **enforced** | the law test grepping every wiki dune for harness libs |
| dependency guard (wiki never → harness) | **enforced** | the law rejects `hermes_harness_*` in wiki Dune files; it does not prove standalone liftability |
| FPP window disjointness | **solver-proved** | `test_fprime_smt` |
| scoped classification totality | **enforced inside each carrier; workspace-wide partial** | register · import coverage · root-file map fail on unclassified members; auxiliary roots remain outside those carriers |
| journal history | **declared + checked** | R16 naming and the append-only prefix law (`Journal`) |

Part of [[Knowledge fractal map]].
