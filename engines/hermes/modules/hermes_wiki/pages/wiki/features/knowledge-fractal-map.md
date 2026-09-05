---
id: hermes-knowledge-fractal-map
status: published
type: reference
ktype: moc
maturity: incubating
domain: formal_verification
topics: [map, fractal, wiki, zk, knowledge-management]
created: 2026-08-09
generated: false
last_verified: 2026-08-12
verified_by: agent
next_review: 2026-09-09
---
# Knowledge fractal map — every wiki, ZK and knowledge-management item, one hub

#feature #src-unified #area-map #cov-navigation

The map of content over the whole fractal knowledge space: five per-tool
surveys, the unified analytical layer, the normative decision layer, the two
deep-structure passes, and the operational stratum that builds it. Every item
below is reachable from here in one hop; backlinks are derived, so membership
in this map cannot go stale silently. Counts are deliberately absent — the
derived group MoCs and the register own every number this page would
otherwise restate.

## 0. How to read the space

Five strata, each verifying the one above it:

1. **Survey** — what each tool *is*, fractally: ontology (entities), atlas
   (maps), algebra (laws), per tool.
2. **Unified analytical** — the six systems as one theory: colimit, not
   intersection; nothing dropped.
3. **Normative** — the decisions: the feature set we build, the ontology,
   atlas and algebra we hold ourselves to, and the implementation approach.
4. **Passes** — deep structures found and verified after the fact (S27–S35,
   then S36–S42), never trusted merely because they are beautiful.
5. **Operational** — the register that tracks it, the plans that sequence it,
   the imports that accelerate it, the engine that runs it.

## 1. The per-tool fractal surveys

| Tool | Ontology | Atlas | Algebra | Detail fleet |
|---|---|---|---|---|
| Notion | [[Notion — fractal ontology]] | [[Notion — fractal atlas]] | [[Notion — fractal algebra]] | group `notion` (derived MoC enumerates it) |
| Obsidian | [[Obsidian — fractal ontology]] | [[Obsidian — fractal atlas]] | [[Obsidian — fractal algebra]] | group `obsidian` |
| Docusaurus | [[Docusaurus — fractal ontology]] | [[Docusaurus — fractal atlas]] | [[Docusaurus — fractal algebra]] | — (rows live in the register) |
| Sphinx | [[Sphinx — fractal ontology]] | [[Sphinx — fractal atlas]] | [[Sphinx — fractal algebra]] | — (rows live in the register) |
| Yuque | [[Yuque — fractal ontology]] | [[Yuque — fractal atlas]] | [[Yuque — fractal algebra]] | group `yuque` |

## 2. The unified analytical layer

- [[Unified fractal ontology]] — one ontology, six presentations; the
  U-level lattice and modal strength.
- [[Unified fractal atlas]] — the six systems on one map; where a gate can
  stand.
- [[Unified fractal algebra]] — six law families F1–F6; the id-cited
  scoreboard.
- [[Unified mathematical structures]] — the eighteen structures and the two
  theorems everything rests on.
- [[Meta-unification]] — why the five surveys and the harness are one
  subject.

## 3. The normative layer

- [[Unified feature set]] — the maximal admissible set, with use cases and
  the deliberate non-set.
- [[Unified domain ontology]] — entities, relations, invariants, modal
  strength as a required field.
- [[Unified functional atlas]] — every capability as a typed function;
  structure index S1–S26.
- [[Unified functional algebra]] — the laws and the tool that discharges
  each one.
- [[Unified implementation approach]] — typing discipline, module plan,
  sequencing, honest bounds.
- [[Glossary]] — the controlled vocabulary as a checked artifact; every
  `[[term:x]]` reference in the corpus resolves here and only here.

## 4. The deep-structure passes

- [[Unified deep structures]] — pass one: S27–S35; S27 landed as
  `Dep_sheaf`.
- [[Unified system synthesis]] — pass two: S36–S42, the update map (§11)
  applied across this space, and the S36 `Reconcile` exemplar (§13).

## 5. The operational stratum (by path — these live outside the pinned corpus)

- **Register**: `modules/hermes_wiki/src/register/feature_register.ml` — every
  feature a row, status derived by live probe; lives below the parity harness
  inside the wiki subsystem; its document form is
  `docs/hermes/features-audit-implementation-plan.md`.
- **PKM architecture**: `docs/hermes/specs/2026-08-09-pkm-longterm-architecture.md`
  — the nine-field schema every document here carries.
- **Plans**: `docs/hermes/unified-wiki-zk-buildout-plan.md` (monitors,
  controls, Playwright) · `docs/hermes/open-items-implementation-plan.md`
  (the phase sequence this map landed in).
- **Journal**: `docs/hermes/journal/` — R16-named, append-only, prompts
  verbatim.
- **Imports**: `modules/hermes_wiki/import/zigvm/MANIFEST.md` (the wiki/zk/graph/
  journal/km-profile/InfraNodus/playwright reference fleet, two tranches) ·
  `modules/hermes_wiki/import/c3i/MANIFEST.md` (ZK rules SC-ZETTEL-001..008, holon
  ladder, skills) — mirror sources, outside the build by design (R14/R9) ·
  `docs/hermes/root-ocaml-file-map.md` — every root legacy OCaml file
  classified to its appropriate folder.
- **Engine**: `modules/hermes_wiki/src/engine` (corpus, AST, query, sheaf) ·
  `modules/hermes_wiki/src/fpp/wiki_topology.ml` (the system as FPP actors) ·
  `modules/hermes_wiki/test/` (the laws that hold all of the above).
- **The workspace itself**, fractally:
  [[Project structure — fractal ontology]] ·
  [[Project structure — fractal atlas]] ·
  [[Project structure — fractal algebra]] — strata, gates, laws and the
  muda clearance, reflexively under the house method.

## 5b. The declared reading order (HW.6.8.1)

The links above are a *graph*: they say what relates to what. The block
below is a **tree**: it says what to read, in what order, and it is
authored rather than derived from the filing. Placement here is what the
`toc_unplaced` gauge counts down — a page not in any declared tree is
reachable only by search, and that is now a measured choice rather than
an accident.

```toctree caption=Start-here
unified-feature-set
unified-fractal-ontology
unified-fractal-atlas
unified-fractal-algebra
unified-mathematical-structures
unified-deep-structures
unified-system-synthesis
project-structure-fractal-ontology
project-structure-fractal-atlas
project-structure-fractal-algebra
glossary
```

## 6. The laws this map itself obeys

Membership is checkable: every stratum-1..4 item above is a corpus page, so a
dead link here fails the build; every stratum-5 path is repo-relative. This
page is `ktype: moc` and claims nothing the linked pages do not prove — it
navigates, it does not assert.

Cross-references: [[Unified system synthesis]] · [[Meta-unification]] ·
`docs/hermes/open-items-implementation-plan.md`.
