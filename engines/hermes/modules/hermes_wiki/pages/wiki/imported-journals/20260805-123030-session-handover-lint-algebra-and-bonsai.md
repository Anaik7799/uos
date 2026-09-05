---
id: hermes-imported-20260805-123030-session-handover-lint-algebra-and-bonsai
status: published
type: reference
generated: false
migrated_from: zigvm/docs/journal/20260805-123030-session-handover-lint-algebra-and-bonsai.md
ktype: source
maturity: incubating
domain: imported-journals
created: 2026-08-08
---
# Session handover — lint algebras, the Bonsai programme, and the framework comparisons

**20260805-123030** · master `6990f61` == origin · gate green:
`All 1090 tests passed`, 1559 files, 0 errors, 0 warnings, 123 doc-lint laws,
29 skills.

Written for a successor with no memory of this session. Everything below is
either a fact verified in-session or a clearly-labelled open question.

---

## 1 · What the session did, in order

| Slice | Commit | What landed |
|---|---|---|
| `gap-doc-lint-observability` | `d6daa27` | report-only lint metrics, OTLP spans, inline-SVG dashboard, trend series |
| `gap-doc-lint-table-model` | `4ed140a` | the GFM table algebra; ratchet driven to zero |
| `gap-doc-lint-markup-algebra` | `e39c5d0` | the HTML tokenizer algebra; fractal propagation |
| `gap-journal-html-publish` | `32803bf` | `--journal-html`, published to the dashboard |
| `gap-bonsai-ontology-algebra` | `ba1d950` | four Bonsai documents, skill, four lint rules |
| (correction) | `b510c46` | algebra and guide corrected against the framework's own docs |
| (evidence) | `ae4fc8b` | executable feature suite + Phoenix comparison |
| (artifacts) | `978fb27` | Phoenix ontology, Dream map, browser test |
| (frontend) | `6990f61` | frontend and LiveView comparison |

---

## 2 · The load-bearing lesson

**A checker over a structured format needs the format's algebra, not a
substring scan.** Twice this session a rule that "worked" was found to be
confidently wrong, and in both cases the remedy it proposed would have
corrupted the artifact it was protecting.

- `MD-TABLE-COLUMN-COUNT` counted pipes. It reported an append-only ledger of
  pipe-delimited *records* as 33 malformed table rows, and told an agent to
  change cell counts in a historical ledger. Of 43 findings, **5 were real**.
- The HTML rules counted `<html` substrings — including inside comments,
  inside `<script>`, and inside attribute values — and `HTML-SELF-CONTAINED`'s
  needle list was a **lower bound** on remote assets that the journal
  contract's archival property was resting on.

The failure mode is not a missed defect. It is a confident wrong answer with an
actionable-looking remedy. **The tell is a rule whose precision you cannot
state.** This is now a non-negotiable in `skills/algebraic-fractal-structures`.

---

## 3 · Reusable technique

### 3.1 The verification regime that found things

Six methods, and the ones that earned their place:

- **Ruliological enumeration.** Exhaustively enumerate the rule space rather
  than sampling it — every line-shape sequence to length 5 (19,607 documents)
  and every markup-fragment sequence to length 4 (16,000+). It caught two
  defects in code written the same hour. Cheap when the alphabet is small.
- **Round-trip conservation as an oracle.** For a tokenizer, assert that the
  token spans reconstruct the document byte-for-byte. Deliberately chosen over
  a twin implementation: a second hand-written tokenizer shares its author's
  misconceptions and the two agree while both are wrong. **The document is the
  reference.**
- **Generated ground truth.** Plant exactly one known defect, assert exactly
  one finding at exactly that line, over hundreds of seeds. Measures precision
  and recall rather than asserting them.
- **Non-vacuity guards.** An enumeration that never builds the interesting case
  passes every invariant while proving nothing. Assert the *count* of
  interesting cases too.

### 3.2 Mutants that survive are findings

`MUT-LINT-13` survived its first kill attempt. The law aimed at exactly its
behaviour fed the linter a bare `---` in prose, which is inert. A mutant
surviving a law aimed at its behaviour means **the law's input was not
discriminating** — not that the mutant is equivalent. Recorded rather than
quietly patched.

### 3.3 Landing a new rule family over existing code

New rules over a large existing component land at **`Info` severity** with the
backlog fully visible and a **named promotion trigger and closing slice**. This
avoids both dishonest options: raising a ceiling that is at zero, or blocking
on an unrelated refactor. Errors and warnings stayed at 0 throughout.

### 3.4 Two-tier standard by provenance

Severity is a function of provenance: **every finding on a GENERATED artifact
is an `Error`**, no ratchet, no exception; authored documents keep the declared
severity. Detection is from the generation marker generators write, plus
generated trees, so a new generator inherits strictness without enumeration.
**Leniency stops at content loss** — arity and balance rules fire regardless.

---

## 4 · Sharp edges (will bite again)

| Edge | Detail |
|---|---|
| **Self-reference hazard** | Hit **seven** times now. A control tripping over the pattern it describes: a registry naming an undefined index, a review note quoting live section numbers, a rule catalogue containing the forbidden pattern, a journal embedding rule literals, a linter page tripping its own checks, an OCaml comment broken by an unmatched quote inside it, and lint rules matching their own detection needles. **Fix: concatenation-split every literal** a scanner also hunts (`"Bon" ^ "sai."`). Established convention; see `CAST-20260805-lint-obs-scanner-literal`. |
| **Core shadows `=`** | With `open! Core`, `=` is integer equality. Boolean comparisons need `Bool.equal` or direct use. Cost a build cycle. |
| **`Effect` is not top-level in core bonsai** | It is `Bonsai.Effect` (aliasing `Ui_effect`). `Bonsai_web` re-exports it at top level; the core library does not. |
| **Bonsai state primitives return a PAIR** | `state`/`state'`/`toggle`/`state_machine` return two values, not one of a tuple. The driver wants one — join with `both` at the edge. |
| **`ppx_jane` needed for deriving** | An executable using `[@@deriving …]` needs `(preprocess (pps ppx_jane))` in its dune stanza. |
| **Incremental state is shared across drivers** | One raised stabilisation poisons every later one in the same process. Test isolation needs a **process** boundary, not a fresh driver. |
| **`on_change` defaults to before-display** | The headless frame protocol (`flush` → `result` → `trigger_lifecycles`) does not pump that phase, so an edge test written against the default **observes nothing and passes vacuously**. Use `~trigger:`After_display` in driver tests. |
| **Never `perl s\|…\|…\|` on prose with table pipes** | Corrupted two documents in an earlier session. Exact-match editing only. |
| **MCP goes stale** | After any `harness/*.ml` rebuild the long-running server fails closed. Use the CLI for evidence; `/mcp reconnect` for tools. |
| **`.agents/` is gitignored** | Skill mirroring to `.claude`, `.codex`, `.gemini` is tracked; `.agents` is not. |

---

## 5 · Bonsai — verified facts

Pin `v0.18~preview.130.106+341`. **Signatures read from the installed
interfaces, not from memory.** Where public material disagrees, the interface
wins.

- **Applicative, not monadic.** No `bind`, deliberately — it would let runtime
  values change graph *shape*. Shape change goes through `match%sub`, `enum`,
  `assoc`, `scope_model`, `Memo`.
- **A computation is a function** `'input t -> graph -> 'result t`. There is no
  `Computation.t` type in the current API.
- **`bonsai.red` teaches the PREVIOUS API generation** — two types where our pin
  has one. Good for design rationale, **do not copy its code shapes**. Its
  "`let%map` is always harmful" advice is superseded; at our pin the two forms
  differ only on patterns that ignore fields.
- **The `assoc` optimisation that matters:** an assoc body that never touches
  `graph` compiles to a plain incremental map with a **constant** node count
  regardless of key count.
- **Incrementality is two-sided.** Depending on everything is the obvious
  failure; over-splitting is the non-obvious one, since nodes cost to create
  and fire. Split where it separates expensive work from fast-changing input.
- **The runtime loop is seven steps**, and nothing stabilises after the DOM
  patch or after lifecycles — which is why a state update scheduled from a
  lifecycle event lands next frame.

### 5.1 The repo's own frontend — the census that grounded the lint rules

`harness/ui_web/main.ml` binds **25 separate states**, bundles them into a
**positional list** of same-typed pairs, and consumes the bundle in one
**321-line map**. The positional bundle forces a catch-all arm rendering
"Invalid UI state", so reordering two entries is a type-correct silent
behavioural change and adding one degrades the UI at runtime rather than
failing to compile.

**Sharpest detail:** `ui_state.ml` already defines
`camera = { zoom : float; x : float; y : float }` and typed variants
throughout, while `main.ml` stores zoom as the string `"1.0"` and re-parses it.
**The correct types already existed and the UI layer routed around them.**

Closing slice, when someone takes it: introduce a `Legacy_ui_model.t` record,
move the 25 fields into it, replace the bundle with that record, split the
321-line map along the panels it already renders. Then promote the four
`BONSAI-*` rules from `Info` to `Warning`.

---

## 6 · Framework comparison — conclusions reached

- **Bonsai and Phoenix are not competitors.** Bonsai is a UI library; Phoenix
  is an application framework containing one. LiveView is perhaps a fifth of
  Phoenix.
- **On the UI axis Bonsai is at parity and stronger** on typing, latency, and
  the impossibility of silently defeating incrementality.
- **Change tracking fails in opposite directions.** LiveView derives
  dependencies from the assign-write API — free granularity, silently defeated
  by a local variable in a template. Bonsai derives them from the typed graph —
  cannot be bypassed, easy to over-depend. **A visible failure is the better
  one**, which is why a lint rule catches ours.
- **Three real frontend gaps**, all libraries: forms with per-field errors and
  reconnect recovery, async-as-a-typed-primitive, uploads.
- **One architectural gap:** server push. The UI polls; a completed gate run
  should update every open dashboard.
- **One thing not portable at any price:** per-viewer crash isolation is a
  property of Phoenix's *runtime*, not its framework.
- **Dream covers more than expected** — routing ~90%, sessions/CSRF/flash/
  forms/uploads ~95%, websocket transport ~100%; the channel/topic model above
  the socket ~10%. Read from the installed `dream.mli`.
- **Recommendation: do not pursue framework equivalence.** Most of Phoenix's
  surface targets multi-tenant public web apps. Telemetry and production
  introspection — two of its strongest batteries — are already solved here.

### 6.1 Ocsigen — the correction

Earlier flagged as unverified because Eliom is not installed. **Local finding
that reframes it:** `lwt` 5.10.1, `tyxml` 4.6.0, `js_of_ocaml` 6.4.1 and
`react` 1.2.2 **are** installed. The ecosystem's foundational libraries are
already in use — `js_of_ocaml` compiles our frontend. **Only the Eliom
framework layer is absent.** The open question is narrow: does Eliom's
client/server-in-one-program model earn a rewrite of the Dream + Bonsai split,
given both sides are already OCaml with a typed RPC surface? Research was
in flight at session end.

---

## 7 · What exists now

**Documents** — `docs/bonsai/`: `BONSAI_ONTOLOGY.md`, `BONSAI_ALGEBRA.md`,
`BONSAI_GUIDE.md`, `BONSAI_SOP.md`, `PHOENIX_COMPARISON.md`,
`PHOENIX_ONTOLOGY.md`, `PHOENIX_DREAM_MAP.md`,
`FRONTEND_LIVEVIEW_COMPARISON.md`. Plus `docs/design/TABLE_ALGEBRA.md` and
`docs/design/HTML_ALGEBRA.md`.

**Code** — `harness/doc_lint.ml` (24 rules, two algebras, provenance),
`harness/lint_report.ml` (report-only projection),
`harness/bonsai_features.exe` (38 cases, headless),
`harness/bonsai_ui_playwright.exe` (browser evidence),
`--journal-html`, `--lint-report`.

**Skill** — `skills/bonsai-ui-development`, mirrored to three vendor trees.

**Evidence** — browser run on the published journal: 22 headings, 21,603
characters, **zero remote requests**, no console or page errors.

---

## 8 · Open threads, ranked

1. **Three Bonsai findings** (`BONSAI_GUIDE.md` §10.1). The `on_change`
   de-duplication one could invalidate a documented claim — do it first.
   `scope_model` raised inside stabilisation; not yet diagnosed as usage error
   versus real constraint. Feature-suite sections need process isolation.
2. **Server-push slice.** Typed event from the harness, websocket over Dream,
   round-trip law on the payload, report-only, degrading to polling.
3. **Drive the live UI in a browser.** Needs the backend running; pairs with 2.
4. **Ocsigen artifacts + three-way map.** Research was in flight.
5. **Frontend refactor** to clear the eight `BONSAI-*` findings, then promote
   the rules to `Warning`.
6. **Formal specs.** The algebra records an honest verdict: **Quint fits** the
   frame-ordering and last-scheduled-wins properties; **property tests on the
   transition function are the highest value per effort**; **ruliology does not
   fire** for the combinator set. Build on that assessment rather than adding a
   technique because it is available.

---

## 9 · Standing discipline that held

- Gate on the **exact commit**, then `--record-cycle`, chained in one command.
- Stage **exact files**; never `git add -A`.
- A red gate gets a `CAST_LOG.md` entry **before** any re-run.
- Every claim of behaviour gets an executable, or it is labelled unverified.
- What a check **cannot** cover is printed on every run.
