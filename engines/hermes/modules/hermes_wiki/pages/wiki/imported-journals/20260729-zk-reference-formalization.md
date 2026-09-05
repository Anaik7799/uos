---
id: hermes-imported-20260729-zk-reference-formalization
status: published
type: reference
generated: false
allow_example_links: true
migrated_from: zigvm/docs/journal/20260729-zk-reference-formalization.md
status: published
last_verified: 2026-07-29
verified_by: agent
ktype: source
maturity: incubating
domain: imported-journals
created: 2026-08-08
---
# ZK reference & formalization arc — feature DB, coverage algebra, the unified spec (2026-07-29)

*Feature journal per the closure rule of
[[journal--20260729-1056-zk-wiki-mcp-ai-architecture-recommendations]] §9.14,
covering three slices and seven recorded cycles: `zk-feature-db`,
`zk-feature-algebra` (cycles 1–4), and `zk-gap-closure-1` (the improve pass). Operating context
[[skills--wiki-design--skill]] · [[skills--zk-knowledge-base--skill]].*
#zettelkasten #journal #formal

## The directive arc

One escalating user directive drove the whole front: take Notion and Obsidian
as references at 100% feature coverage → annotate every feature (use cases,
look & feel, navigation cues) → make it a real feature database → scrape
notion.com, build ontology and design language → formalize algebraically in
OCaml → integrate Rete-UL/STPA/FMEA/ruliology, the Rocq/Aeon ladder, STM —
and finally Smtml + OCANNL as intelligence substrates.

## zk-feature-db (commit `299f34e`, worktree gate 2670 ok, recorded)

- Coverage **matrices** (Notion 100% surface + Obsidian incl. 2025 Bases) in
  the wiki-design skill; rule set: ✗ never silently becomes ◐; `—` rows are
  answered by the substrate, not missing.
- The **feature database**: 108 generated notes + 6 from the live notion.com
  scrape — one atomic note per feature, annotated with use cases, look &
  feel (textual visual descriptions), and navigation cues, tagged
  `#cov-*`/`#src-*`/`#area-*`; a **self-querying README** whose live
  `zkquery` fences enumerate the 19 gaps, the strong points, and the
  by-design rows.
- **The scrape's headline**: Notion's 2026 wave (Agents, Custom Agents over
  MCP, a Notion CLI, agent audit logs) **converged on this ZK's
  architecture** — recorded as `#notion-2026` notes.
- Synthesis notes: [[Notion ontology — the concept model]] (containment vs
  REFERENCE) and [[Notion design language — look, feel, and navigation cues]]
  (every cue adopted/diverged/candidate).
- Fix en route: 8 pages broke by quoting live link syntax — solved by
  backtick-quoting (code spans don't linkify), a rendering improvement over a
  marker exemption.

## zk-feature-algebra cycle 1 — the mathematics (commit `c62fde2`, gate 2688)

- **Coverage as a typed join-semilattice** (`Gap<Partial<Native<Strong`
  chain, `Na` identity) with **EXHAUSTIVE** law verification — the finite
  carrier lets the selftest check all 125 associativity triples, 25
  commutativity pairs, 5 idempotents: total verification, not sampling.
- `feature_of_page`/`feature_db`: the notes are the INITIAL encoding, typed
  records the FINAL, under exactly-one tag discipline (malformed = reported,
  never guessed); `coverage_rollup` derives per-source·area JOIN (capability)
  and FLOOR (debt). Surfaces: `--zk-coverage` + the Reference-coverage panel
  on the currency page. Real-corpus guards in `--selfcheck-wiki`
  (0 malformed over 114 features; the **cross-encoding AGREEMENT law**:
  kernel census ≡ the independent zkquery tag path).
- **The unified formal spec** [[The Knowledge-Systems Algebra — a formal
  specification of Wiki, ZK, Notion, and Obsidian entities]]: signature K
  (adjoint-inverse/purity/identity laws), the containment-embeds-into-
  reference theorem, per-system ADTs (ours mechanized; Notion/Obsidian
  spec-only), static invariants, dynamic behavior as labelled transition
  systems (incl. the MoC fixpoint-immunity stability theorem), the fractal
  extension structure, and the honest **mechanization ledger**.
- [[Notion site fractal — notion.com's own IA mapped to our surfaces]]: the
  120-URL site map organ-mapped (help pages = feature notes, releases =
  journals, guides = skills) — the reference vendor's site validates the
  shape of this knowledge base.
- Mutants MUT-FE-1/2/3 killed (join inverted; tag discipline loosened; floor
  computes max).
- **The law's first live catch, minutes after landing**: the currency timer
  drew a MoC around feature notes and its tags-rollup **laundered** member
  tags (`#feature` + `#cov-*`) into live tags — wellformedness AND agreement
  went red simultaneously (two encodings, one answer, exactly as designed).
  Root-cause fix: MoC tag rollups render as INERT code spans, closing the
  laundering channel for all tag families.

## Cycle 2 — the governance ring (commit `6a34435`, gate 2697)

Spec §7: **FM-ZK-TAG-LAUNDER** recorded in SAFETY_ANALYSIS.md with its class
rule (generated aggregators must emit inert forms of live syntax — detection
is a LAW, mitigation is structural); the **Rete-UL stance made precise**
(knowledge rules and admission rules in disjoint rule spaces; report-only
extension recipe); the **Rocq/Aeon mechanization ladder** (six candidates
with cost + trigger; each rung arms the fail-closed formal gate; Aeon
transcriptions of the LTSs as executable conformance oracles); the
**ruliological frame kept defensible** (confluence-by-design at observation
via derivation-purity; evolution-as-rule-application via the Zero-Trust
gate); the **organism loop** (self = the corpus including the spec; four
memory systems — episodic/semantic/procedural/historical — on one substrate;
auditable algebraic intelligence; fast OODA from the 30-minute heartbeat to
per-slice cycles) with the **evolution invariant**: note → kernel+laws+
mutants → controller+packet → rule+proof; and the **STM roadmap** (kcas over
OCaml 5 domains; three scoped hot spots — cache snapshot, gate-cache claims,
front memoization — triggers only, decided jointly with SAC).

**The discipline bit its author again**: the FMEA prose quoting live
`#feature`/`[[links]]` syntax turned safety-analysis itself into a malformed
feature + broken-link page — caught by `fractal:feature-db-wellformed` and
the audit within one run, fixed by the very class rule the entry defines.

## Cycle 3 — the intelligence substrates (commit `7948415`, gate 2705)

Spec §7.7 **Smtml** as the SMT rung below Rocq, aligned with the repo's
existing [[SMTML and SMT Algorithms in ZigVM]] operating rule (*SMT
proposes/refutes/ratchets/witnesses; Rocq proves; Rete gates*): triple-
agreement with counterexample generation, bounded model checking of the §4
LTSs, zkquery equivalence/emptiness lint, grounded-labelling cross-check —
entry via the existing aeon_lang Z3 path, each its own slice, never gate
authority. Spec §7.8 **OCANNL** with the honesty ledger: it dissolves the
external-tool objection to the parked neural-embeddings seam (the
`note_vectors` kind column was built for `kind='neural'`) while the DEMAND
trigger stands; the P(fail)/TIA track stays label-starved (engine-swap =
make-work, explicitly not a slice); any future ML output is a report-only
SUGGESTION class under the lockout + disjoint-rule-spaces policies. Ladder:
QCheck/exhaustive → Smtml → Rocq, with OCANNL beside it, never on it.

## Cycle 4 — the Smtml×OCANNL system sweep (commit `7a2dffb`, gate 2712)

The final directive ("where all can SMTML and OCANNL improve the existing
system — full fractal analysis and implication check") landed as
[[OCANNL and ML Algorithms in ZigVM — the full fractal sweep]], the
equal-depth companion to the repo's existing
[[SMTML and SMT Algorithms in ZigVM]]:

- **Executive verdict**: Smtml is a NOW-substrate (its P0 — consolidating
  the aeon_lang Z3 path, the agent firewall, Rete rule analysis — is
  justified by existing needs); OCANNL is a **WHEN-substrate with no current
  P0** — every candidate fails the demand test (embeddings), the label test
  (P(fail): ~1/702, the standing E30 finding), or the deterministic-first
  test (bench changepoints → CUSUM before ML).
- **The 11-layer placement table** with per-row implication checks: two
  genuinely-labeled NEXT rows (mutant-target ranking over the MUTATION_LOG
  corpus — the best-labeled dataset in the repo; TIA cost prediction over
  `tia_cost`, the flagship composition with smtml-tia-optimizer); PARKED
  rows with named triggers; permanent REJECTs (learned slice routing =
  governance — OODA's Decide stays rule-based; safety/verdicts/renders/
  gates = policy).
- **The SANDWICH doctrine, adopted into spec §7.8**: *ML suggests → Smtml
  checks → laws admit* — nothing learned ever renders, decides, or gates;
  a suggestion becomes a fact only through existing guarded paths.
- **Pre-scoped failure modes** for the day the first slice opens:
  FM-ML-SUGGEST-FLOOD (cap + threshold), FM-ML-AUTHORITY-CREEP (disjoint
  spaces extended to suggestion classes), FM-ML-DRIFT (models as versioned
  git artifacts, suggestions carrying the model hash) — packets open WITH
  the first slice, not before.
- ACH: H3 "ML when, through the sandwich" accepted over "ML now" (no
  candidate passes both tests) and "ML never" (two real datasets exist);
  devil's advocate conceded-and-countered ("a roadmap about not doing
  things" — that is the point: the E25–E30 wave proved-then-parked the
  pipeline; this analysis prevents a shiny library from un-parking it
  without data; ignored suggestions surface as standing toil by
  construction).

## zk-gap-closure-1 — the improve pass (commit `03d6845`, gate 2723)

The directive's closing clause — *"fable must think comprehensively and
improve this"* — got the honest ultrathink answer: not a sixth analysis
document, but the FIRST end-to-end execution of the evolution loop the spec
promises. The coverage algebra said what improvement means (19 gaps, zero
closed); three renderer gaps became laws, notes flipped, and **the census
moved live exactly as the semilattice predicts** — gap 19→14, native 30→34,
partial 31→32, on `--zk-coverage`, the currency panel, and the README's
self-querying fences.

- **Callouts**: `> [!type] Title` typed admonitions in exactly Obsidian's
  syntax — closing BOTH vendors' gap rows at once (any lowercase type, icon +
  color family, plain quotes untouched). MUT-GC-1 (type defaulted: "every
  warning renders as a calm note") killed.
- **To-do checkboxes**: `- [ ]`/`- [x]` as READ-ONLY inputs — state
  deliberately left to the kanban ledger, exactly as the feature note
  promised when it was written. MUT-GC-2 (checked state ignored) killed.
- **`[TOC]`**: a full-line marker renders the note's own heading tree linking
  the SAME anchors `heading_html` emits (znorm or explicit `^id` — the
  agreement IS the law). MUT-GC-3 (unnormalized anchors: "a TOC of dead
  links") killed.
- Five feature notes flipped with CLOSED-by annotations
  (`obsidian-outline` honestly to ◐ — the in-note block landed, the
  persistent pane did not); the flipped notes verified serving on :8088.
- All three mutants died first try — the markup-form assertion rule (the
  standing CSS-in-page lesson) applied from the start.

**The THIRD live self-catch**: minutes after closure, the agreement law went
red (15 vs 14) — the gap-closure MUTATION_LOG prose had itself laundered
`#cov-gap` as a live tag. Caught by the kernel≡zkquery law on the next
selfcheck, fixed by the FM-ZK-TAG-LAUNDER class rule, committed as its own
catch (`7293d95`). Three same-day violations, three same-day catches, all by
laws written the same day.

## Evidence & tallies for the arc

Seven recorded cycles across three slices; worktree gates 2670, 2688, 2697,
2705, 2712, and 2723 all green; every closure Zero-Trust-admitted and
episodic-note-documented; all pushed (`7293d95` at arc close). Front total
**48 mutants killed / 0 surviving**. Corpus at 332 pages, selfcheck-wiki at
3,363 checks, audit HEALTHY. THREE live self-catches (the MoC tag
laundering; the FMEA prose; the gap-closure prose) — every one found by a
law written the same day and fixed structurally under the same class rule:
the discipline is demonstrably self-applying. The arc closes having both
DESCRIBED the evolution invariant and EXECUTED it — gap → trigger →
law-carrying slice → census change → self-documentation — with the
intelligence roadmap in the same shape as everything else here: every yes
has a trigger, every no has a reason, and both are queryable notes in the
graph they describe.
