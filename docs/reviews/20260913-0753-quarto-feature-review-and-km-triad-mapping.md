# 20260913-0753 — Quarto feature review and KM-triad mapping

#fractal-l2 #fractal-l5 #fractal-l9 #km-triad #zk-adr #zero-muda #tailscale-web

**Live:** [http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260913-0753-quarto-feature-review-and-km-triad-mapping.md](http://nas-1.tail55d152.ts.net:4100/files/docs/reviews/20260913-0753-quarto-feature-review-and-km-triad-mapping.md)

**Clock:** host observed `2026-09-13T07:00:53Z`; chrony stratum 3, system time 0.000129849 s slow of NTP — nominal band (<2 s).
**Reviewer:** Claude Opus 5, session `a65088e0-…`. **Authority:** advisory only. No implementation, no task claim, no admission.
**Sources:** quarto.org pages fetched 2026-09-13 (`/`, `authoring/cross-references`, `authoring/citations`, `computations/execution-options`, `projects/quarto-projects`, `projects/code-execution`, `websites/website-listings`). UOS side read from source at working revision.

---

## 0. The one-line recommendation

**Adopt six Quarto *design patterns*; do not adopt the Quarto *toolchain*.**

Quarto is Pandoc + Deno + Lua filters + language kernels. Importing that binary stack conflicts with Zero-Muda (§5.6) and with the full-symbiosis rule that new automation be Gleam or Rust, not shell/Python/Node. Everything of value here is a *contract idea* that Hermes OCaml and Gleam already have the machinery to express. The patterns are the asset; the runtime is the liability.

---

## 1. What Quarto actually offers

| Area | Feature |
|---|---|
| Authoring | Pandoc markdown, LaTeX math, callouts, figure panels, page layout, visual editor |
| Cross-refs | Typed prefix labels: `fig- tbl- eq- lst- sec-`, theorem family `thm- lem- cor- prp- cnj- def- exm- exr- sol- rem- alg-` |
| Citations | BibLaTeX/BibTeX/CSL, 8,500+ CSL styles, citeproc, locators, `cite-method` |
| Computation | Python, R, Julia, Observable JS; `eval/echo/output/warning/error/include` |
| Reproducibility | `freeze` (`true` / `auto`), `_freeze` dir committed to VCS; `cache` per-kernel |
| Projects | `_quarto.yml` → `_metadata.yml` → frontmatter; merge-not-overwrite; `metadata-files`; profiles |
| Listings | Auto-generated indexes from metadata; sort, filter, categories, pagination, RSS |
| Formats | HTML, PDF, Word, ePub, revealjs; website, blog, book, manuscript, Confluence |

---

## 2. Mapping to the KM triad — six adoptable patterns

Ranked by defect-reduction value, each against a **measured** UOS gap.

### Q1 — Typed, *resolvable* cross-references → ZK / wiki (highest value)

**Quarto.** A label must start with a reserved type prefix. `@fig-elephant` resolves against a declared `#fig-elephant`. The type is part of the identity, so a reference to the wrong kind of thing is a different name, not a subtle error.

**UOS today.** `tools/km_provenance/km_corpus.ml` checks index completeness with `coverage body needles` — **byte presence of a filename in a body**. `SC-PROVENANCE-001` §7.3 states the limit in its own words:

> "Byte presence of a filename in an index does not prove the surrounding index text is correct."

That is precisely the defect class this repository has been paying down all week: *an observable coarser than the property being enforced*. A filename appearing anywhere in an index — in a footnote, a code fence, a "removed" list — satisfies `KMP-INCOMPLETE`.

**Note a real distinction, so this is not overclaimed.** `Wiki_source_ext.xref` (`source/wiki_source_ext.mli:233`) *does* exist, but it is a **source-code** cross-reference — interface `val` → implementation, rendered by `xref_html`. It is not a document cross-reference system. The two are different features that share a word.

**Adopt.** Typed prefixes for the ZK corpus (`adr-`, `moc-`, `ev-`, `sc-` for contracts, `thm-` for Lean obligations) with a **resolver that fails on a dangling target**. This upgrades `CHK-04-KM` and `KMP-INCOMPLETE` from byte-presence to resolution. The precedent already exists in-tree: `Wiki_transclude.expand` returns `missing`, `cycles`, and `truncated` as first-class outcome fields, and `wiki_audit.ml:160-163` counts them. That algebra is the right one; it simply is not applied to ZK references.

### Q2 — Listings: generate the index, don't check it → KM (poka-yoke)

**Quarto.** `listing:` builds a page's contents from the metadata of the documents it globs. The index cannot omit a document that exists, because the index *is* a function of the corpus.

**UOS today.** The Master MOC and Wiki Corpus Index are hand-maintained; `km-gate` then checks `completeness_ratio == 1.0` after the fact. Status line records 91 ADRs "both 91/91 enumerated."

**Adopt.** Derive both indexes from `docs/zk/*` and check the *derivation*, not the artifact. This converts a detected failure mode into an impossible one — Poka-Yoke over Jidoka, which §3.1/§3.2 of the TPS mandate ranks in that order. `km_corpus.adrs()` already enumerates the directory and sorts by number; it produces the list the index needs and currently only *compares* against it.

**Second-order benefit.** Listing metadata fields (`categories`, `date`, `author`, `description`) map onto fractal tags and would let the MOC render by layer, by contract, or by admission state without a second hand-maintained file.

### Q3 — `freeze` + committed `_freeze` → KM / evidence (two-key verification)

**Quarto.** Computational output is committed to VCS so a collaborator renders the project **without reproducing the computational environment**. `freeze: auto` re-executes only when source changes. Caveat, stated in Quarto's own docs: freeze applies to *project* renders; rendering an individual document always executes.

**UOS today.** This is the closest external analogue to two-key verification that exists in a mainstream tool. Our evidence problem is identical in shape: a claim must be checkable at a revision without re-running the world. We already have the pieces separately — `tools/preflight --receipt` writes `var/preflight/latest.json` with the sha256 of the checker *and* its resolver table, and honours a receipt only if the checker is byte-identical. That is `freeze: auto` reasoning, implemented once, for one tool.

**Adopt.** Generalise the preflight receipt discipline into a corpus-wide *evidence freeze*: an evidence artifact is valid iff (producer digest, input digest, revision) all match; any drift invalidates. This directly attacks the `STALE`/`UNRUN` distinction that `SYNC-10` requires stay nonpassing.

**Caveat worth carrying over verbatim.** Quarto's own warning — freeze silently does not apply on single-document renders — is exactly the kind of scope hole that produces a false green. Any UOS version must make the scope of a freeze explicit in the receipt.

### Q4 — Metadata hierarchy with merge semantics → wiki / KM (fractal tags)

**Quarto.** `_quarto.yml` (project) → `_metadata.yml` (directory) → frontmatter (document), lowest to highest priority, and objects/arrays **merge rather than replace**.

**UOS today.** `SC-FRACTAL-TAXONOMY-001` records the measured pathology: **59% of ADRs claim all ten layers**, and `KMP-ENTROPY` reads that ritual as health (1.306 bits against a 2.50 floor). The contract states the honest limit — "a floor cannot detect ritual tagging."

**Adopt.** Directory-level `_metadata.yml` carrying default layer tags per corpus area, with document frontmatter overriding. This makes **inherited** tags distinguishable from **declared** ones. An author who tags all ten deliberately is then visible as having overridden a default, which is the signal `KMP-ENTROPY` cannot currently see. It does not fully solve earned-vs-ritual — the contract is right that only a per-claim evidence audit does — but it separates the two populations, which is the prerequisite.

### Q5 — Theorem environments bound to Lean → ZK / formal (two-key link)

**Quarto.** Eleven theorem-family prefixes, each cross-referenceable.

**UOS today.** `formal/lean/*.lean` holds machine-checked proofs (`Traceability.lean`, `TwoLattice_STM.lean`, and others). Documents *assert* those proofs in prose. The binding between a document claim and the proof that discharges it is currently a sentence.

**Adopt.** `#thm-` labels in ZK/wiki records that resolve to a **Lean theorem name at a revision**. A dangling `#thm-` is then a broken build, not a stale paragraph. This is the highest-leverage KM change for §6 two-key verification: it makes the *link* between the two keys a checked object. Formal authority stays invocation-specific per §7 — a resolved label proves the theorem is *named*, not that it *checks*; the checker still must run.

### Q6 — Citation/bibliography discipline → KM / evidence provenance

**Quarto.** Typed bibliography entries, resolved keys, a rendered reference section, and CSL for presentation.

**UOS today.** Evidence locators appear as prose paths and URLs across contracts and reviews. `governance/sources/*.json` holds ingestion manifests — the right data, without a citation grammar over it.

**Adopt.** A `.bib`-shaped **evidence bibliography** keyed by typed evidence id (source manifest, cycle row, preflight receipt, board message), cited from documents by key, with unresolved keys failing. This gives `SC-RISK-PRIORITY-001` §4's "evidence locators" a machine-checkable form. Presentation styling (CSL) is not needed and should be skipped.

---

## 3. Mapping table

| Quarto feature | Wiki | ZK | KM | UOS gap it closes | Value |
|---|---|---|---|---|---|
| Typed resolvable xrefs | ●●● | ●●● | ●●● | byte-presence ≠ resolution (`km_corpus.coverage`) | **High** |
| Listings | ●● | ●●● | ●●● | hand-maintained MOC/index; `KMP-INCOMPLETE` checked not generated | **High** |
| `freeze` / `_freeze` in VCS | ○ | ● | ●●● | STALE vs UNRUN; evidence re-checkable at a revision | **High** |
| Metadata hierarchy + merge | ●● | ●●● | ●● | ritual tagging (59% claim all 10 layers) | Medium-High |
| Theorem envs → Lean | ● | ●●● | ●● | doc claim ↔ proof binding is prose | Medium-High |
| Citations / bibliography | ●● | ●● | ●●● | evidence locators unresolvable | Medium |
| Profiles (dev/prod) | ● | ○ | ● | dev/prod boundary in `SC-HARNESS-MCP-001` | Medium |
| Multi-format render | ●● | ● | ● | docs are `.md` at :4100 only | Low-Medium |
| Callouts / layout | ●● | ● | ○ | cosmetic | Low |
| Computation engines | ○ | ○ | ○ | **conflicts** — Python confined to `services/inference/max` | **Do not adopt** |

● = applies, ○ = does not.

---

## 4. What NOT to take

1. **The toolchain.** Pandoc + Deno + Lua + language kernels. Zero-Muda, and full-symbiosis §Runtime Language Rules ("new automation should be Gleam or Rust").
2. **Execution engines.** Quarto executes Python/R/Julia inline. §5.4 confines Python to `services/inference/max`. An inline-execution document format would breach a language boundary at the authoring layer, which is the worst place to breach it.
3. **CSL presentation styling.** 8,500 styles solve a journal-submission problem UOS does not have.
4. **`error: true` as a default.** Quarto's option continues rendering past a failed cell. Useful for teaching notebooks; it is the precise opposite of the fail-closed Andon line (`SC-JIDOKA-001`). If any execution-control vocabulary is borrowed, fail-closed must be the default and `error: true` an explicit, recorded opt-in.

---

## 5. Suggested sequence

| Order | Work | Why first | Gate |
|---|---|---|---|
| 1 | Typed xref resolver over ZK corpus | Reuses `Wiki_transclude`'s outcome algebra; closes the stated byte-presence limit | dangling ref fails `km-gate` |
| 2 | Generate MOC + corpus index from corpus | Makes `KMP-INCOMPLETE` true by construction | derivation checked, not artifact |
| 3 | Evidence freeze receipts (generalise `tools/preflight --receipt`) | Pattern already proven on one tool | drift invalidates |
| 4 | Directory `_metadata.yml` for layer defaults | Separates inherited from declared tags | inherited ≠ declared visible |
| 5 | `#thm-` → Lean binding | Depends on (1) | dangling `#thm-` fails |
| 6 | Evidence bibliography | Depends on (1) | unresolved key fails |

Items 1 and 2 are the ones that would have caught real defects already recorded in this repository.

---

## 6. Limits of this review

- **Source and web reading only.** Nothing built, executed, or claimed. No sa-plan task claimed; this grants no admission.
- **Quarto pages were fetched and summarised by a fetch tool**, not read in full by me. Feature *names and semantics* are quoted from those summaries; I did not run Quarto, so no behavioural claim here is observed.
- **The UOS side is source-read at the current working revision.** I did not execute `km-gate`, `wiki_audit`, or any suite for this review, so statements about current behaviour are properties of the source, not fresh runtime observations. The two measured figures cited (1.306 bits entropy; 59% ten-layer tagging) are quoted from `SC-FRACTAL-TAXONOMY-001` and `SC-CHECKLIST-001`, not re-measured today.
- **I did not enumerate the wiki engine exhaustively** — it has 20 source subdirectories. A feature I describe as absent may exist on a path I did not read; `xref` is the near-miss I caught (present, but a different feature than the name suggests). Treat absence claims as "not found in a targeted search."

---

**UOS footer:** [nas-1.tail55d152.ts.net:4100](http://nas-1.tail55d152.ts.net:4100/) · Sa-plan is the sole execution authority; this review grants no admission and completes no task.
