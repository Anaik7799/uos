---
id: hermes-imported-20260805-111058-lint-algebra-programme-journal
status: published
type: reference
generated: false
allow_example_links: true
migrated_from: zigvm/docs/journal/20260805-111058-lint-algebra-programme-journal.md
ktype: source
maturity: incubating
domain: imported-journals
created: 2026-08-08
---
# The lint algebra programme — when a checker is confidently wrong

**Date:** 20260805-111058 · **Slices:** `gap-doc-lint-observability`,
`gap-doc-lint-table-model`, `gap-doc-lint-markup-algebra` ·
**Divergences:** 758, 759, 760 · **Commits:** `d6daa27` → `4ed140a` → (this)

---

## 1 · The prompts, verbatim

The session was driven by seven successive instructions. They are reproduced
exactly, because the shape of the work followed the shape of the asks — and
because two of them changed the plan mid-flight.

1. `sync state , continue`
2. `dashboard, metrics, kpis, otel, diagrams and analytics for the lint pipeline`
3. `**Residual (honest).** 44 warnings remain, 43 of them
   `MD-TABLE-COLUMN-COUNT` -- fix these. keep error and wanring to zero`
4. `finish the DIVERGENCE_LOG fixes and get warnings to zero. create smart logic
   for handling tables`
5. `… this should be extremely robust, if the browsers can render it then it
   should be ok, but if we are generating the the tables then then should be
   strictly correct. do comprehensive testing tdd, bdd, fuzz, property,
   probabilistic ranges for correctness, ruliological`
6. `… get formal algebric stuctur and algebra of tables and its behavior, get
   and create comprehensive ontology and algebra`
7. `apply the same algebra treatment to the HTML rules` ·
   `update all fractal arififacts , skills, agents and documentation impacted by
   this capability and knowledge` · `create detauled journal entry …`

Instruction 3 is the pivot. It asked for a cleanup. What it actually exposed
was a defect in the tool doing the measuring.

---

## 2 · Problem statement

At the session's start the lint gate reported `errors = 0, warnings = 60` over
1,531 files, held under a monotone ratchet. The standing handover described the
60 as a *document backlog*: 43 `MD-TABLE-COLUMN-COUNT`, 14 `ZIG-MODULE-DOC`, 2
`ZK-EMPTY-WIKILINK`, 1 `HTML-HEADING-LEVELS`. The instruction was to drive it to
zero.

The 17 non-table warnings were a backlog, and were fixed as one. The 43 were
not. They were the output of a rule that could not distinguish a table from a
paragraph containing pipes, and the question the session actually had to answer
was:

> **What is the correct behaviour of a checker whose subject is a structured
> format, and how do you know it has it?**

A secondary question arrived with instruction 5, and turned out to be the more
useful half of the design:

> **Is "a browser renders this correctly" a sufficient standard?** — and if it
> is for authored prose, what is the standard for output we generate ourselves?

---

## 3 · Analysis

### 3.1 What the pipe counter was actually measuring

The original rule treated any run of consecutive lines containing pipes as a
table, took the first as the header, and on a mismatch **reset** so the next row
became a new header. Running it over `DIVERGENCE_LOG.md` — an append-only ledger
of 377 pipe-delimited records — produced 33 findings.

Measuring the ledger directly settled what those findings meant:

| Measurement | Result |
|---|---|
| Pipe-row runs in the file | 42, separated by blank lines and prose |
| Runs carrying a delimiter row | **1** (lines 12–13) |
| Rows by arity | 3 cells: 4 · 4 cells: 3 · **5 cells: 139** · **6 cells: 107** · **7 cells: 119** · 8 cells: 3 · 9 cells: 1 · 14 cells: 1 |
| Gaps between runs that are blank-only | 38 of 40 |

The file is not a table and never was. It is a log of pipe-delimited records
whose arity drifted from 5 to 7 columns as the programme's ledger schema grew,
and every conforming renderer emits those 373 delimiter-less rows as literal
text. The counter was comparing rows of unrelated fragments against each other,
which is why the reported numbers looked arbitrary — *"6 cells; header has 7"*
where the "header" was a row from a different fragment 300 lines away.

Two independent reviews of the counter's output, run as subagents over the
smaller files, reported the same structural finding from the other direction:
several flagged lines were **cascade artifacts**, correct rows reported because
an earlier bad row had silently re-based the check. The rule was pointing at the
wrong line.

**The decisive observation:** the remedy the rule proposed — "make this row's
cell count match its header" — applied to an append-only historical ledger would
have had an agent invent or drop content to satisfy a broken model. A subagent
was already partway into doing exactly that and was stopped before it wrote.

### 3.2 The same defect, one layer up

Instruction 7 asked for the same treatment on the HTML rules, and the same class
of defect was there:

| Rule | What it did | What that costs |
|---|---|---|
| `HTML-TAG-BALANCE` | counted `<html` against `</html>` over raw bytes | counts occurrences inside comments, inside `<script>`, inside attribute values; cannot tell `<main>…</main><main>` from `<main><main>…</main>` |
| `HTML-SELF-CONTAINED` | matched six exact byte spellings | missed extra whitespace, uppercase `SRC`, unquoted values, protocol-relative `//cdn`, CSS `@import`, `@font-face`, and every resource element beyond script/link/img |
| `html_start_tag` | scanned to the next `>` | stops early on a `>` inside a quoted attribute value |
| `HTML-HEADING-LEVELS` | scanned for `<h1..6` in raw bytes | a page documenting heading structure trips on its own examples |

The self-containment case is the serious one. Its needle list was a **lower
bound** on remote assets, and the journal contract's archival property — an
evidence page must render with no network — rested on it. That is a silent
non-detection on an evidence path, the false-green direction the safety analysis
names as the dangerous one.

### 3.3 Why "add another needle" was not the fix

Both rules could have been patched. The reason not to is that neither had a
statable precision: there is no answer to *"what does this rule report, and on
what?"* other than a list of substrings. A rule you cannot characterise cannot
be trusted at a gate, and its false positives are worse than its false
negatives, because agents act on them.

---

## 4 · References used

Internal, and binding:

- `AGENTS.md`, `ALGEBRAIC_FRACTAL_RULES.md` — the mandatory slice loop: semantic
  domain before code, oracle and final encoding, laws named after algebraic
  properties, ≥2 mutants, doc sync, green gate.
- `skills/algebraic-fractal-structures/SKILL.md` — the operational workflow.
- `skills/harness-supervisor/SKILL.md` — the OODA loop and dispatch tiers.
- `skills/approach-b-zero-muda-observability/SKILL.md` — one acquisition, bounded
  parallelism admitted by its sequential oracle, report-only observers.
- `skills/formal-technique-selection/SKILL.md` — matching technique to the
  *shape* of the subject; the source of the ruliology trigger test.
- `docs/design/LINT_FORMAL_SPEC.md`, `LINT_FEATURES.md`, `LINT_BENCHMARK.md` —
  the existing specification, check list and differential against external
  tools.
- `SAFETY_ANALYSIS.md` § CTRL-DOC-LINT — the hazard taxonomy (H-L1 false green,
  H-L2 false red, H-L3 crash-as-verdict, H-L4 ceiling drift) that classified the
  defect.
- `MUTATION_LOG.md` — the standing lesson from the programme's first pass: *a
  rule is admitted after running over the real corpus, not when it looks right.*

External, as specifications rather than dependencies:

- The GitHub Flavored Markdown tables extension — a table is a header row, a
  delimiter row whose cell count **equals** the header's, and a body; any other
  line ends it. This is the definition the table algebra implements.
- The HTML standard's tokenizer stages and element categories — void elements,
  elements whose end tag may be omitted, raw-text elements. These are what make
  the markup algebra's tolerances principled rather than arbitrary.
- W3C `vnu`, markdownlint, remark-lint, html-validate, HTMLHint — the benchmark
  set already recorded in `LINT_BENCHMARK.md`, and the reason the scope limits
  are stated explicitly rather than implied.

---

## 5 · The solution

### 5.1 Two algebras

Each states carrier, denotation, signature, ontology, oracle and final
encodings, laws, verification regime, and scope limits.

**`docs/design/TABLE_ALGEBRA.md`.** A Document denotes its **Block
decomposition** — maximal runs of row-ish lines, each tagged with whether its
preceding gap was blank-only. A **Table** is a Block whose first line is a Row
and whose second is a Delimiter *of equal arity*; a Table denotes the finite map
its Body induces. A **Fragment** — a Block that is not a Table — denotes literal
text, which is not a defect, because that is exactly what every renderer does
with it.

**`docs/design/HTML_ALGEBRA.md`.** A Document denotes its **token sequence**.
Every rule is a predicate over that sequence, so comments, raw-text elements and
attribute values are opaque *by construction* rather than by special-casing —
which retired the `markup_only` hack that existed only so pages documenting the
rules would not trip on their own quoted examples.

### 5.2 The consequences that fall out

Modelling the format rather than the bytes decided several things that had
previously been guesses:

- The column check is **header-anchored** and never re-bases. One bad row is one
  finding, at that row. The cascade class disappears.
- A delimiter-less pipe run is **not a table**, so the ledger's 33 findings
  disappear — not by exclusion, but because the format says so and every
  renderer agrees.
- Balance is a **stack** that reports *where*, so `<main><main>…</main>` is
  caught where counting could not see it.
- Self-containment reads **resource attributes**, so it catches every spelling
  and still knows an `<a href>` to a website is navigation, not an asset.

### 5.3 Rules the heuristics could not express

| Rule | Defect | Why nothing else reports it |
|---|---|---|
| `MD-TABLE-DELIMITER` | a uniform grid with no delimiter row | renders as text — valid, just not a table |
| `MD-TABLE-SPLIT` | a blank line detaching rows from the table above | the source still looks like one table |
| `MD-TABLE-ROW-WRAPPED` | a row hard-wrapped across physical lines | Markdown has no row continuation |
| `HTML-COMMENT-UNCLOSED` | an unterminated `<!--` | swallows the rest of the document; the page still looks plausible |
| `HTML-ATTR-DUPLICATE` | a repeated attribute | the parser keeps the first and drops the rest, silently |

### 5.4 The two-tier standard

Instruction 5's framing became a mechanism. Severity is a **function of
provenance**: an authored document is held to what a renderer does with it, and
**every finding on a generated artifact is an `Error`** — no ratchet, no
exception. Provenance is detected from the generation marker generators already
write, plus the generated trees, so a new generator inherits the strict standard
without being enumerated.

The justification is that the two have different failure modes. An authored
fragment is a human writing pipes and getting pipes: visible to them, costing
nothing. A generated one is a bug in a generator — invisible until a reader hits
the page, and reproducible across every artifact that generator emits.

**The leniency has a hard floor: content loss.** `MD-TABLE-COLUMN-COUNT` fires
regardless of provenance, because a row of the wrong arity makes the renderer
*drop cells*. So do `HTML-TAG-BALANCE`, `HTML-COMMENT-UNCLOSED` and
`HTML-DATA-URI-INTACT`. "The browser renders it" is a defence for a construct
that renders *differently*, never for one that renders *less*.

### 5.5 Verification — six independent methods

| Method | What it does | Scale |
|---|---|---|
| TDD | every rule written against a failing law first | — |
| BDD | given/when/then per rule, positive and negative | 60+ scenarios |
| Property | the structural algebra: conservation, maximality, the concatenation homomorphism, arity invariance, header anchoring, permutation, idempotence | 20 laws |
| **Ruliological** | exhaustive enumeration of the rule space — every line-shape sequence to length 5 (19,607 documents) and every markup-fragment sequence to length 4 (16,000+) | 35,000+ documents |
| **Probabilistic** | generated ground truth: clean inputs must yield nothing (precision), one injected defect must yield exactly that finding at exactly that line (recall, location, no spurious) | 1,000 trials |
| Fuzz | adversarial bytes over format-shaped alphabets | 1,200 documents |

The table oracle is an obviously-correct decomposition (materialise, collect
runs, decide gaps by inspection) that the streaming encoding must equal. The
markup oracle is **round-trip conservation** — the token spans partition the
document, so reconstruction is byte-identical — chosen *deliberately* over a
twin tokenizer: a second hand-written implementation would share its author's
misconceptions about HTML and the two would agree while both were wrong.
Byte-exact reconstruction cannot fail that way, because the reference is the
document itself.

The ruliological pass carries a non-vacuity guard: an enumeration that never
built a real table would satisfy every invariant while proving nothing, so the
count of enumerated documents *containing* a table is itself asserted.

### 5.6 Observability

Landed first, as `harness/lint_report.ml` — a pure projection of one lint
observation into `lint_metrics.json`, `lint_otel.jsonl` (OTLP spans, Unix
nanoseconds), a self-contained inline-SVG `lint_dashboard.html`, and a durable
trend series. It shares **one acquisition** with the gate rather than walking the
corpus twice, and it is report-only in a way that is mechanised: a source-scan
law rejects every effectful token in the module, so the observation plane has no
path to a verdict. The dashboard must pass the very registry it displays, in the
law suite and in production — the generated artifacts land inside the linted
corpus.

---

## 6 · What the methods actually caught

Recorded because a verification regime that never catches its author is
decoration.

| # | Defect | Found by |
|---|---|---|
| 1 | Gap tracking: the blank line that *ended* a block was also the gap, so `MD-TABLE-SPLIT` never fired | its own BDD law, on first run |
| 2 | `MD-TABLE-SPLIT` carried a header arity across unrelated blocks, naming a table hundreds of lines away with a remedy that would not work | corpus run after fixing #1 |
| 3 | A bullet list of wikilinks — `- [[a\|b]] · degree 67` — read as a uniform two-cell grid, reporting 8 generated MoC notes as malformed tables | full-corpus run |
| 4 | A thematic break `---` parsed as a one-column delimiter row, opening a phantom table | mutant MUT-LINT-13 |
| 5 | An OCaml comment introducing the tokenizer quoted a script-src prefix; its unmatched double quote opened a string literal and broke the build | the compiler |

Defects 1–3 were in code written *this session*, found before admission,
by running it. Defect 5 is the sixth instance of the programme's recurring
self-reference hazard — a constraint registry naming an index it did not define,
a review note quoting live section numbers, a rule catalogue containing the
pattern it forbids, a journal embedding rule literals, a linter page tripping
its own checks, and now a comment about quoting broken by a quote.

**MUT-LINT-13 survived its first kill attempt**, and that is recorded rather
than quietly patched. The law aimed at exactly its behaviour fed the linter a
bare `---` in prose — which is inert, because nothing pairs with it. Only a
one-cell row *above* the break makes the phantom table observable. A mutant
surviving a law aimed at its behaviour means the law's input was not
discriminating; it does not mean the mutant is equivalent.

---

## 7 · Results

```text
before   errors 0, warnings 60   1,531 files   98.4% clean   15 rules
after    errors 0, warnings  0   1,543 files  100.0% clean   20 rules
```

Of the 60: 17 were a real backlog and were fixed (14 `ZIG-MODULE-DOC` — the two
generated tables fixed at their **generators** and regenerated, never by hand),
and 43 were table findings that the algebra reduced to **5 real defects**, each
repaired at its cause:

| Defect | Repair |
|---|---|
| two ledger rows missing a cell boundary | inserted the separator at the real semantic seam; no content invented |
| an unbalanced code span in `MUTATION_LOG.md` | escaped backticks inside a code span, which GFM does not support |
| a `CODEBASE_MAP.md` row hard-wrapped over 53 physical lines | joined onto one line — the fix the wrapped-row rule prescribes |
| a blank line splitting a table | deleted |

The 67 HTML files produced **0 findings** under the stricter markup model. The
pages were already sound; the rules can now say so for a reason.

Ratchet: `errors = 0, warnings = 0`. There is no backlog left for a new finding
to hide in. Laws: 49 → **120**. Mutants: `MUT-LINT-8..16`, all killed.

---

## 8 · Why the algebraic approach was worth it

Stated concretely, in terms of what it produced here rather than in principle.

**It changes what a wrong answer costs.** A heuristic that is wrong is
*confidently* wrong: it names a line, states a count, and proposes a remedy. An
agent that follows that remedy modifies the artifact to satisfy the model. In
this session that path led to editing an append-only historical ledger to match
a definition of "table" the file never claimed. Modelling the format made the
correct answer *"this is not a table"* — which no amount of needle-tuning would
have reached.

**Precision becomes statable, so it becomes reviewable.** "A table is a header,
a delimiter row of equal arity, and a body" is a sentence a reviewer can
disagree with. "The rule matches these six substrings" is not a specification of
anything; it cannot be argued with, only extended.

**The remedy becomes derivable from the model.** `MD-TABLE-SPLIT` says *delete
the blank line*, and that works, because the chain is only carried across gaps
where deleting really does reattach. The first version pointed hundreds of lines
away — and the reason that was a bug is that the *remedy* was wrong, which is a
check only a model makes available.

**Laws outlive their implementation.** `BLOCK-PARTITION`, `CONCAT-HOMOMORPHISM`
and `HTML-CONSERVATION` constrain any future encoding. The streaming table
decomposition exists only because the corpus is 42 MB; the oracle is the
definition. When the fast path is replaced, the laws still hold it to the same
meaning — which is exactly the oracle/final discipline this repository applies to
the VM itself, applied to its own tooling.

**It makes new rules cheap and safe.** Five rules were added in two slices. Each
is a few lines over an existing model, and each covers a defect that renders
without error and that no external tool reports. Under the byte-scanning design
each would have been another needle with its own false-positive surface.

**It made the honest scope limit possible.** Both algebras state what they do
*not* attempt — no inline parsing, no content model, no entity resolution, no
CSS parsing, tolerances named element by element. A heuristic cannot state its
limits, because it does not have a boundary, only a list.

**And it caught its author, five times.** That is the strongest argument
available: three of the five defects in §6 were in code written this session and
were found by the regime before it shipped.

---

## 9 · Residuals, disclosed

- Delimiter-less pipe runs of drifting arity are not reported. They render as
  text, no content is lost, and calling them malformed tables would be a style
  opinion. `DIVERGENCE_LOG.md` is deliberately this shape.
- Wrapped-row detection is syntactic — a row that opens but does not close. A
  wrapped row whose first physical line happens to end in a pipe is not
  detectable without understanding the prose, and is not claimed.
- The markup layer is a tokenizer, not a parser: no tree, no insertion modes, no
  adoption agency. Misnesting is reported as an unclosed element, which is what
  it costs in practice.
- `css_remote_urls` scans for `url(` and `@import`; a remote URL assembled at
  runtime by script is not detectable and is not claimed.
- The lint dashboard is a repository artifact; it is not wired to the Tailscale
  endpoint.
- Ruliology now fires for the *table and markup models* and was applied there.
  The rule **registry**'s `ISOLATION` is unchanged, so its original deferral
  stands: if a rule is ever allowed to read another rule's findings, the rule
  space must be explored before that relaxation is admitted.

---

## 10 · Fractal propagation

The capability was pushed to every surface that binds an agent to it:

| Artifact | Change |
|---|---|
| `docs/ONTOLOGY.md` §14 | the document-lint projection: controllers, observers, provenance, evidence stores, agent surfaces, laws |
| `docs/rules/full-symbiosis.md` | a **Document-Lint Law**, mirrored to all four vendor rule trees by symlink |
| `docs/agents/full-symbiosis-supervisor.md` | dispatch and acceptance facts, including that a lint report must name the law it satisfies, not the symptom it silenced |
| `CLAUDE.md` · `CODEX.md` · `GEMINI.md` | the mode description, identically, under the Entry Point Law |
| `skills/algebraic-fractal-structures` | a non-negotiable: a checker over a structured format needs the format's algebra, and generated artifacts are held to a stricter standard |
| `skills/docs-design` · `skills/wiki-design` | what a generator must emit, now that its output is held to the strict standard |
| `SAFETY_ANALYSIS.md` | CTRL-DOC-LINT-OBS packet, SC-L7–SC-L10, and the markup-layer analysis |
| `DIVERGENCE_LOG.md` | 758, 759, 760 |
| `MUTATION_LOG.md` | MUT-LINT-8..16 |

---

## 11 · Evidence

```text
gate     All 1090 tests passed (exit 0)
laws     doc-lint 120 passed · lint-report 13 passed
lint     1,543 files, 430 kloc, 100.0% clean, errors 0, warnings 0, 20 rules
design   SC-F registry total 1..42; reference-clean; phase runbook total P0..P9
```

Specifications: `docs/design/TABLE_ALGEBRA.md`, `docs/design/HTML_ALGEBRA.md`.
Implementation: `harness/doc_lint.ml`, `harness/lint_report.ml`.
Laws: `doc_lint_laws` and `lint_report_laws` in `harness/zigvm_harness.ml`.
