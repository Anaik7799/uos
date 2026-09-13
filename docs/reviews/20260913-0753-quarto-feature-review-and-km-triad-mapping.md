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

---

# Second pass — remaining site areas

Observed `2026-09-13T07:51:52Z`, same session and authority. Pages fetched: `authoring/includes`, `authoring/conditional`, `authoring/diagrams`, `dashboards/`, `manuscripts/`, `extensions/`.

## 7. Q7 — Diagrams: the finding this pass exists for

Quarto renders Mermaid and Graphviz natively, treats a diagram **as a figure** (so `label`, `fig-cap`, and `@fig-` cross-referencing apply), accepts an external `.mmd`/`.dot` via a `file` option, and renders format-adaptively (JS for HTML, PNG for PDF via headless Chrome). One source, many renderings.

Checking our side against `SC-DIAGRAM-001`, which requires that ASCII and Mermaid "describe the exact same nodes, edges, labels, and hierarchical groupings," produced three facts.

**7.1 `G-DIAGRAM` is not implemented.** The string appears in exactly four places in the repository — `.claude/`, `.gemini/`, `.agents/`, `.codex/` mirrors of the same rule, each line 8, each naming it as enforcement. There is no gate, no `tools/` entry, no implementation anywhere. The mandate advertises machine enforcement that does not exist. In full-symbiosis drift terms this is a **P1 missing guard**; note that rule-mirror parity is perfect, which is precisely why the absence is invisible — four surfaces agree about a gate none of them can run.

**7.2 The corpus-wide checker tests co-presence and calls it parity.** `tools/journal_linter.ml:255-271`:

```ocaml
let has_mermaid = contains_substring full_text "```mermaid" in
let has_ascii =
  contains_substring full_text "+---" ||
  contains_substring full_text "|   " ||      (* pipe + three spaces *)
  ...
if has_mermaid then
  if has_ascii then
    printf "  [PASS] CHK-DIAG: SC-DIAGRAM-001 dual diagram source parity verified (ASCII + Mermaid)\n"
```

`"|   "` — a pipe followed by three spaces — matches **any padded Markdown table**. So a journal containing one Mermaid diagram and one ordinary table prints *"dual diagram source parity verified."* The check cannot fail for any document that has a table, and it proves nothing about nodes, edges, or labels even when it does fire. It is weaker than co-presence of two diagrams: it is co-presence of a fence and a punctuation pattern. **And it prints the word "parity."**

This is the session's recurring defect class, now with the strongest wording yet attached to the weakest observable: *an observable coarser than the property being enforced*, announcing the property by name.

**7.3 The correct algebra already exists in the tree.** `tools/validate_implementation_plan.ml:115-120` does real semantic parity — it extracts ` --> ` edges from both the ASCII block and the Mermaid block, builds the expected edge set, and compares sorted lists:

```ocaml
check (sorted ascii = sorted expected_ascii && sorted mermaid = sorted expected_mermaid)
      "master diagram parity";
```

That is genuine node/edge comparison. It is scoped to one master document inside one tool.

**The structural parallel is exact.** This is the same shape as Q1: the right algebra is implemented once and narrowly, while the corpus-wide checker uses a coarse proxy. Two independent instances in two independent subsystems — which suggests the pattern is not accidental but a consequence of corpus-wide checks being written under pressure to pass.

**Adopt — and prefer generation over checking.** Quarto's actual lesson is not "check two forms agree," it is **one source, generated renderings**. If the ASCII form were *generated from* the Mermaid (or both from a common edge list), parity would be free rather than tested. The repository already argues exactly this, in `engine/wiki_transclude.mli`:

> "Expanding text-to-text before either renderer sees it makes byte-equality FREE rather than something to test for."

Same argument, made for prose, available for diagrams. Recommended order: (a) implement `G-DIAGRAM` using the `validate_implementation_plan` edge algebra corpus-wide; (b) replace `journal_linter`'s `has_ascii` proxy, which should fail loudly rather than pass vacuously; (c) longer term, generate one form from the other and retire the check.

## 8. Q8 — Conditional content: an instance of our defect class *in the wild*

Quarto's `.content-visible` / `.content-hidden` with `when-format`, `unless-format`, `when-profile`, `when-meta` produce different output per target from one source. Format aliasing is neat (`latex` covers latex/pdf/beamer; `html:js` covers JS-capable formats).

Quarto's own documented limitation is the interesting part:

> "They do **not** prevent the code in cells they wrap from executing."

A **visibility** control mistaken for an **execution** control. Content can be hidden from every output while its code still runs — hiding the evidence of an effect, not the effect. That is our defect class, in a mature external tool, documented by its own authors.

**Relevance.** `SC-CHECKLIST-001` §3.4 mandates a Dual View Mode (Rendered Markdown vs Raw Source) on every document view. If conditional visibility is ever adopted for that, the hazard must be explicit: **visibility is not authorization and not execution control.** Anything with an effect is gated by typed policy per §6, never by a rendering class. Worth recording as a hazard we now have a citation for.

## 9. Q9 — Includes: adopt nothing; we already have the better design

Quarto's `{{< include >}}` is, in its own words, "equivalent to copying and pasting the text from the included file into the main file." Consequences it documents: relative paths in the *included* file resolve from the **main** document's directory (fix: absolute paths from project root); YAML frontmatter in an included file affects every document that includes it; includes must sit on their own line and cannot appear inside a list; computational includes require a single shared engine.

**Our `Wiki_transclude` is stronger on every axis that matters here** — and this is worth stating plainly so it is not "modernised" into a regression:

| Property | Quarto include | `Wiki_transclude` |
|---|---|---|
| Cycle handling | not documented | broken where it closes, **reported** (`cycles`) |
| Depth bound | not documented | bounded and **reported** (`truncated`) |
| Missing target | not documented | visible marker + **reported** (`missing`) |
| Sub-document addressing | whole file only | block-level `![[Note#^id]]`, `None` when absent |
| Expansion time | render-path paste | build-time, so byte-equality is free by construction |

**Adopt: nothing.** The one idea worth borrowing is the underscore filename convention (`_partial.qmd`) so partials are structurally excluded from standalone rendering — a cheap poka-yoke against a fragment being published as a document.

## 10. Q10–Q12 — Manuscripts, extensions, dashboards

**Q10 Manuscript project type → KM / journal protocol (Medium-High).** Notebooks are simultaneously the computation and the evidence layer: selected cells embed into the article while the *complete* notebook stays reachable from the site. That is the shape `SC-JOURNAL-v3` needs — a journal section citing a specific evidence cell, with the whole artifact one click away, rather than prose asserting a result. The **MECA archive** (one zip capturing article plus supporting documents for a publisher) maps cleanly onto a *sealed evidence bundle for sovereign review*: exactly what `CHK-17-SOV` review by Codex and AGY currently lacks as a single addressable object.

**Q11 Extensions → plugin surface (Medium).** Eight extension classes (shortcodes, filters, formats, project types, metadata, brand, engines, revealjs plugins), living inside the project directory rather than an external package manager, with registry metadata linking to source. The in-project placement matches `SC-TOOLCHAIN-INPROJECT-001` exactly, and we already have `plugins/uos-risk-prioritization`. The transferable requirement is **pinning**: an extension that floats reproduces the `nixpkgs-weekly/*` wildcard hazard `SC-NIX-DEVENV-001` §5 records.

**Q12 Dashboards → cockpit (Low-Medium).** A declarative layout grammar — pages/rows/columns/tabsets with proportional sizing, cards, value boxes, sidebars — versus our hand-built Lustre pages. Genuinely elegant, but we already serve 31 pages with an 18-checkpoint accordion, and the C1–C8 gold standard encodes requirements this grammar does not express. Borrow the *proportional row/column sizing* idea if page layout is ever revisited; do not restructure the cockpit for it.

## 11. Revised mapping table (both passes)

| Quarto feature | Wiki | ZK | KM | UOS gap | Value |
|---|---|---|---|---|---|
| Typed resolvable xrefs | ●●● | ●●● | ●●● | byte-presence ≠ resolution | **High** |
| **Diagrams as single-source figures** | ●● | ●●● | ●●● | **`G-DIAGRAM` unimplemented; linter tests a pipe-and-spaces proxy** | **High** |
| Listings | ●● | ●●● | ●●● | MOC/index checked, not generated | **High** |
| `freeze` / `_freeze` in VCS | ○ | ● | ●●● | STALE vs UNRUN | **High** |
| Metadata hierarchy + merge | ●● | ●●● | ●● | ritual tagging | Med-High |
| Theorem envs → Lean | ● | ●●● | ●● | claim ↔ proof binding is prose | Med-High |
| Manuscript / MECA bundle | ● | ●● | ●●● | no sealed evidence object for sovereign review | Med-High |
| Citations / bibliography | ●● | ●● | ●●● | evidence locators unresolvable | Medium |
| Extensions (in-project, pinned) | ● | ○ | ●● | plugin pinning | Medium |
| Profiles (dev/prod) | ● | ○ | ● | dev/prod boundary | Medium |
| Multi-format render | ●● | ● | ● | `.md` at :4100 only | Low-Med |
| Dashboard layout grammar | ●● | ○ | ○ | cockpit already meets C1–C8 | Low-Med |
| Conditional content | ●● | ● | ● | **adopt with hazard noted** — visibility ≠ execution | Low (hazard) |
| Include shortcode | ● | ● | ○ | **do not adopt** — ours is stronger | None |
| Computation engines | ○ | ○ | ○ | **conflicts** — Python confined to MAX | **Do not adopt** |

## 12. Revised sequence

Unchanged at the top; the diagram work enters at position 2 because it is the only item where a checker currently prints a passing verdict for a property it does not test.

| Order | Work | Gate |
|---|---|---|
| 1 | Typed xref resolver over ZK corpus | dangling ref fails |
| 2 | **Implement `G-DIAGRAM` with the `validate_implementation_plan` edge algebra; replace `journal_linter`'s `has_ascii` proxy** | **edge sets must match; a table must not satisfy the check** |
| 3 | Generate MOC + corpus index from corpus | derivation checked, not artifact |
| 4 | Evidence freeze receipts | drift invalidates |
| 5 | Directory `_metadata.yml` layer defaults | inherited ≠ declared |
| 6 | `#thm-` → Lean binding | dangling `#thm-` fails |
| 7 | Evidence bibliography; MECA-style review bundle | unresolved key fails |

## 13. Added limits for this pass

- §7.1's absence claim is scoped to a repository-wide search for `G-DIAGRAM` excluding `.jj`, `_build`, `docs/`, and `contracts/`; four rule-mirror hits were the only results. If an equivalent gate exists under a different name I did not find it.
- §7.2's reading of `has_ascii` is from source. **I did not execute `journal_linter`**, so "a table satisfies the check" is a property of the code as written, not an observed run. It is worth confirming by execution before the fix is scoped.
- Quarto behaviour in this pass, as in the first, comes from fetched-page summaries. No Quarto binary was installed or run.

---

**UOS footer:** [nas-1.tail55d152.ts.net:4100](http://nas-1.tail55d152.ts.net:4100/) · advisory review; no admission, no task completion.

---

# Third pass — the diagram weakening is specified, not merely implemented

Added on reading `SC-JOURNAL-v3` (`contracts/rules/20260912-0745-sc-journal-v3-anticipatory-contract.md`, ratified by all three sovereigns). It supersedes §8.2 of `CLAUDE.md` and restates the diagram rule twice, at different strengths.

## 14. A three-step degradation from mandate to implementation

| Tier | Artifact | What it requires |
|---|---|---|
| 1. Mandate | `INV-JRN-06` / `SC-DIAGRAM-001` | ASCII and Mermaid "describing **identical topology**" — same nodes, edges, labels, groupings |
| 2. Enforcement spec | `SC-JOURNAL-v3` §5.4 | "Confirms that any ` ```mermaid ` block **has a corresponding ASCII diagram block**" |
| 3. Implementation | `tools/journal_linter.ml:255-271` | `has_mermaid && contains "\|   "` — a pipe and three spaces, i.e. **any padded Markdown table** |

Tier 2 is strictly weaker than tier 1: co-presence of two blocks cannot establish identical topology. Tier 3 is strictly weaker than tier 2: a Markdown table is not an ASCII diagram.

**This matters more than the implementation gap alone.** §7.2 read as a coding shortcut. It is not — the weakening is *written into the contract's own enforcement section*, and that section was ratified by Codex, Claude Fable, and AGY (§6, three ratification certificates). The checker faithfully implements a specification that was already too weak, and then weakened it once more. No reviewer in the triad caught either step.

So the defect is not "someone wrote a lazy check." It is: **the invariant and the procedure said to enforce it were authored at different strengths, and the review process compared neither against the other.** `INV-JRN-08` then requires exit code 0 from that linter for journal completion, which converts the gap into a positive admission signal.

**Revised recommendation for sequence item 2.** Fix all three tiers, in this order, or the gap reopens:
1. Amend `SC-JOURNAL-v3` §5.4 to state the topology comparison, not co-presence — the contract must ask for what `INV-JRN-06` means.
2. Implement `G-DIAGRAM` with the `validate_implementation_plan.ml:115-120` edge algebra.
3. Replace `journal_linter`'s `has_ascii` proxy so a table cannot satisfy it.

Fixing only (3) leaves a contract that still specifies the weaker check, and the next implementer is entitled to write the weaker check again.

**Cross-check that passed.** `INV-JRN-07` requires the host NVMe serial appear in journals only as `[REDACTED_SYSTEM_OS_SERIAL]`. That is byte-identical to `egress_redactor.redacted_serial_placeholder` in `apps/cepaf_gleam/src/cepaf_gleam/harness/egress_redactor.gleam`, wired at the Telegram and OpenRouter transport boundaries under commit `61ba9a60`. Contract and implementation agree here, and the placeholder is shared rather than duplicated — the counter-example showing the failure above is not systemic to the contract.

## 15. Limits for this pass

- The three tiers are quoted from the contract text supplied in-session and from source read directly. **The linter was still not executed**, so tier 3's behaviour remains a property of the code as written.
- Whether the three ratification certificates in §6 examined §5.4 specifically is **UNKNOWN** — I did not read them. The claim above is only that the published contract carries the weaker wording, not that any particular reviewer overlooked it deliberately.

---

**UOS footer:** [nas-1.tail55d152.ts.net:4100](http://nas-1.tail55d152.ts.net:4100/) · advisory review; no admission, no task completion.
