---
id: hermes-imported-table-algebra
status: published
type: reference
generated: false
migrated_from: zigvm/docs/design/TABLE_ALGEBRA.md
---
# The algebra of Markdown tables

The specification of record for the table layer of `harness/doc_lint.ml`:
signature, semantic domain, ontology, oracle and final encodings, laws, and
scope limits, in this repository's standard shape. Every law named here is
executable in `doc_lint_laws` (`--verify-formal`, hence the canonical gate).

It exists because the previous encoding was not an algebra. It counted pipes,
and a pipe counter cannot tell a table from a paragraph that contains pipes —
so it reported 43 findings of which 5 were real, and its proposed remedy for an
append-only ledger would have had an agent invent content to satisfy the model.
The fix was not a better heuristic. It was writing the algebra down.

## 1 · Ontology

The vocabulary, smallest to largest. Each term is a carrier or an operation of
the algebra; nothing in the implementation names a concept absent here.

| Term | Definition | In code |
|---|---|---|
| **Line** | one physical line of a document | `string` |
| **Cell** | the text between two adjacent separators of a Row | (implicit) |
| **Separator** | a `\|` that is neither escaped (`\\\|`) nor inside a code span | `md_row_cells` |
| **Arity** | the number of Cells a Row carries | `md_row_cells : string -> int` |
| **Row** | a Line whose Arity is at least one and which opens no other block construct | `ML_row of int` |
| **Delimiter** | a Row whose every Cell matches `:?-+:?` and which carries a Separator | `ML_delim of int` |
| **Blank** | a Line that is empty after trimming | `ML_blank` |
| **Other** | any Line that is none of the above, including everything inside a fence | `ML_other` |
| **Block** | a maximal run of consecutive Rows and Delimiters | `md_block` |
| **Gap** | the Lines strictly between two adjacent Blocks | `bl_gap_blank_only` |
| **Table** | a Block whose first Line is a Row and whose second is a Delimiter **of equal Arity** | `md_table_of_block` |
| **Header** | the first Line of a Table; it fixes the Arity every Body Row is judged against | — |
| **Body** | the Lines of a Table after the Delimiter | — |
| **Fragment** | a Block that is not a Table | — |
| **Provenance** | Authored or Generated — which standard the document is held to | `doc.generated` |
| **Finding** | a defect at a Line, with a rule identity and a severity | `finding` |

Two derived notions carry the diagnoses:

- A Fragment is **detached** when a blank-only Gap separates it from a Table (or
  from a chain of detached Fragments) of the same Arity. Deleting that blank
  line reattaches it — which is why the chain must not be carried across prose
  or an Arity change, or the remedy would not work.
- A Row is **wrapped** when it opens with a Separator and does not close with
  one: Markdown has no row continuation, so the Table ends there.

## 2 · Signature

```text
  md_row_cells        : Line -> Arity                    (0 when not a Row)
  md_delimiter_cells  : Line -> Arity option
  md_classify         : Line -> {Blank, Row n, Delim n, Other}
  md_blocks           : Document -> Block list           (final encoding)
  md_blocks_oracle    : Document -> Block list           (oracle)
  md_table_of_block   : Block -> (Arity * Line list) option
```

## 3 · Semantic domain

A **Document denotes its Block decomposition**: an ordered list of maximal Row
runs, each tagged with whether its preceding Gap was blank-only.

A **Table denotes the finite map its Body induces** — position to Cell vector of
the Header's Arity. A Body Row of the wrong Arity has no image in that map: the
renderer drops the excess Cells or pads the missing ones, so content is silently
lost. That is the semantic content of `MD-TABLE-COLUMN-COUNT`, and it is why
that rule fires regardless of Provenance.

A **Fragment denotes literal text**. This is not a defect in itself — it is what
every conforming renderer does with pipes that no Delimiter governs — which is
why the Fragment rules are advisory for Authored documents and hard for
Generated ones.

## 4 · The two-tier standard

> If a browser renders it, it is acceptable; if we generate it, it must be
> strictly correct.

Mechanised as severity being a function of Provenance: on a Generated artifact
**every** Finding is an `Error`, with no ratchet and no exception. An Authored
document keeps the rule's declared severity.

The justification is that the two have different failure modes. An Authored
Fragment is a human writing pipes and getting pipes: a rendering that differs
from the author's intent, visible to them, and costing nothing. A Generated
Fragment is a bug in a generator, invisible until a reader hits the page, and
reproducible across every artifact that generator emits. Provenance is detected
from the generation marker the generators themselves write, plus the generated
trees, so a new generator inherits the strict standard without being enumerated.

The marker is only honoured in the first 2000 bytes: a document that *discusses*
generation is not a generated document (`LAW PROVENANCE-MARKER-HEAD`).

## 5 · Oracle and final encodings

`md_blocks_oracle` materialises the classified Line list, collects maximal Row
runs as index ranges, then decides each Gap by inspecting the Lines between two
runs — the definition, transcribed. `md_blocks` does it in one streaming pass
carrying fence state and the Gap flag in refs; it exists only because the corpus
is 42 MB.

They are admitted equal by **LAW RULIOLOGY-ORACLE** over all 19,607 enumerated
documents and **LAW TABLE-FUZZ-ORACLE** over 600 adversarial ones. The oracle is
never the shipping path and the final encoding is never trusted on its own.

## 6 · Laws

**Structural** — what makes the decomposition a decomposition:

| Law | Statement |
|---|---|
| `BLOCK-PARTITION` | The Blocks partition the Row-ish Lines: each appears exactly once, in document order, and nothing else appears. |
| `BLOCK-MAXIMAL` | Consecutive Blocks are separated by at least one non-Row Line, so the decomposition is canonical. |
| `CONCAT-HOMOMORPHISM` | Documents form a monoid under blank-line-separated concatenation, and the decomposition carries it to list append: `blocks(d1 <> d2) = blocks(d1) @ blocks(d2)`. |
| `CONCAT-IDENTITY` | The empty document is the unit of that monoid. |

**Arity** — what makes the column check about shape, not content:

| Law | Statement |
|---|---|
| `ARITY-CONTENT-INVARIANT` | Cell count is a function of Separator structure alone; rewriting Cell content leaves it fixed. |
| `CELL-COUNT-ESCAPE` | An escaped pipe is not a Separator. |
| `CELL-COUNT-CODESPAN` | A pipe inside a backtick run is not a Separator, for runs of any length. |
| `HEADER-ANCHORED` | Every Body Row is judged against the Header. The check never re-bases, so the Row reported is the Row that is wrong. |
| `BODY-PERMUTATION` | Permuting the Body permutes the Findings and nothing else. |

**Pipeline** — inherited from the enclosing lint algebra:

`LINT-IDEMPOTENT`, `DETERMINISM`, `ORDER-INDEPENDENCE`, `MONOID-*`,
`RULE-FAILURE-CONTAINED`, `PARALLEL-EQUALS-SEQUENTIAL`.

## 7 · Verification regime

Six independent methods, because each catches what the others cannot:

| Method | What it does | Scale |
|---|---|---|
| **TDD** | Every rule was written against a failing law first. | — |
| **BDD** | Given/when/then per rule, positive and negative. | 30+ scenarios |
| **Property** | The structural and arity laws above, over hand-built and generated documents. | 12 laws |
| **Ruliological** | Exhaustive enumeration of the rule space: every sequence over a 7-symbol Line alphabet up to length 5 — both Arities, a Delimiter that pairs and one that does not, the Blank that splits, prose, and a fence — checked for totality, oracle agreement and the structural invariants. | 19,607 documents |
| **Probabilistic** | Generated ground truth: clean Tables of random Arity and length must yield nothing (precision), and a Table with exactly one injected short Row must yield exactly that Finding at exactly that Line (recall, location, no spurious). Rates are measured and asserted, not assumed. | 600 trials |
| **Fuzz** | Adversarial byte sequences over a table-shaped alphabet, checked for totality and oracle agreement. | 600 documents |

The ruliological pass carries its own non-vacuity check
(`LAW RULIOLOGY-NON-VACUOUS`): an enumeration that never builds a real Table
would pass every invariant while proving nothing, so the count of enumerated
documents containing a Table is itself asserted.

**Mutants**: `MUT-LINT-11` (block-marker exclusion disabled), `MUT-LINT-12`
(first Body Row skipped), `MUT-LINT-13` (delimiter pipe clause dropped) — all
killed; see `MUTATION_LOG.md`, including why MUT-LINT-13 survived its first
attempt and what that proved about the law rather than the mutant.

## 8 · Scope limits

Stated so this is never mistaken for a CommonMark implementation:

- **Not a parser.** Inline emphasis, links, HTML blocks, list nesting and lazy
  continuation are not modelled. The algebra covers table structure only.
- **Leading-pipe convention.** A Row must open with a pipe, or contain a
  Separator and open no other block construct. GFM permits Rows with neither
  leading nor trailing pipe; such a table is recognised only when its Delimiter
  is present, which is the case that matters.
- **Fragments of drifting Arity are prose.** A run of pipe-delimited records
  whose Arity varies is not reported: it renders as text, no content is lost,
  and calling it a malformed table would be a style opinion. `DIVERGENCE_LOG.md`
  is exactly this shape, deliberately.
- **Wrapped-Row detection is syntactic.** It sees a Row that opens but does not
  close. A wrapped Row whose first physical line happens to end in a pipe is not
  detectable without understanding the prose, and is not claimed.
- **Alignment markers are parsed, not checked.** `:---:` is accepted as a
  Delimiter; whether the alignment is the one intended is not a well-formedness
  question.

## 9 · Trigger test: ruliology

`LINT_FEATURES.md` recorded that ruliology **partially fires** for the rule
registry and named the condition that would make it fire fully: *rules
interacting*. That condition has now been met in one specific place, and the
method was applied there rather than in general.

Individual rules remain isolated — `check` still receives only a `doc` and
cannot observe another rule's findings. But the Block model beneath them is a
stateful automaton over Line classifications, with transitions (fence open and
close, Gap accumulation, chain continuation) that interact. That is a rule
space, it is small, and its emergent behaviour is exactly what a heuristic gets
wrong. So it was enumerated exhaustively rather than sampled — and the
enumeration immediately paid for itself twice, once through the Gap-tracking
defect the split law exposed and once through the chain-carrying defect that
made a remedy unusable.

The general registry trigger remains as stated: **if rule ISOLATION is ever
relaxed, the rule space must be explored before the relaxation is admitted.**
