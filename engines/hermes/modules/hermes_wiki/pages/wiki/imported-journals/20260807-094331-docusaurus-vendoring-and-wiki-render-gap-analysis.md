---
id: hermes-imported-20260807-094331-docusaurus-vendoring-and-wiki-render-gap-analysis
status: published
type: reference
generated: false
allow_example_links: true
migrated_from: zigvm/docs/journal/20260807-094331-docusaurus-vendoring-and-wiki-render-gap-analysis.md
id: f3ded0d8-2293-c99f-aa86-01adfc81f556
title: "Docusaurus vendoring and the wiki/ZK render gap analysis"
type: journal
slug: 20260807-094331-docusaurus-vendoring-and-wiki-render-gap-analysis
status: published
last_verified: 2026-08-07
verified_by: agent
next_review: 2026-09-07
has_frontmatter: true
---

# Session Archive: Docusaurus Vendoring and the Wiki/ZK Render Gap Analysis

A complete, non-lossy record of the session of **2026-08-07** (started 09:43:31 CEST) in
which `facebook/docusaurus` was acquired into `third_party/`, made gate-safe, and analysed
against the zigvm wiki/ZK render stack under a caller-supplied stratified framework.

No code behaviour changed. The session produced an **analysis** plus two **repo-hygiene**
edits. All findings carry measured corpus incidence.

---

## 1. Verbatim Prompts Ledger

### Prompt 1

> https://docusaurus.io/docs , https://github.com/facebook/docusaurus -- get code and put in third_party folder , analyse for features to improve the wiki, zk and display and rendering of the html and wiki pages. use this framework - A map of the territory, organized as strata — each layer is a different *stance* on the same objects (a value, a type, a program, a theory). I've kept glosses to a line so the taxonomy stays scannable.
>
> ## 1. Static layer — types as propositions, statics as logic
>
> **Core calculi**
> - λ→ (simply typed), System F (parametric), Fω (constructors), λΠ (dependent), Calculus of (Inductive) Constructions — the λ-cube as the coordinate system
> - Curry-style vs Church-style; intrinsic vs extrinsic typing
> - Curry–Howard–Lambek: proofs ≅ programs ≅ arrows in a CCC
>
> **Inference & discipline**
> - Hindley–Milner, Algorithm W / M, principal types, let-generalization, the value restriction
> - Bidirectional typing (check/synth), elaboration, unification & higher-order pattern unification (Miller)
> - Kinds, higher-kinded types, arity/variance, row polymorphism, structural vs nominal
> - Rank-N types, existentials, GADTs, indexed families, singletons
>
> **Substructural & graded statics**
> - Linear (⊗, ⊸), affine, relevant, ordered — controlling contraction/weakening/exchange
> - Graded/quantitative type theory (QTT), modal types (□/◇), comonadic grading
> - Ownership/region/lifetime systems as substructural statics (Rust's borrow checker is an affine + region discipline)
>
> **Predicate-carrying statics**
> - Refinement & liquid types, SMT-decidable subtyping, predicate abstraction — this is exactly the Aeon/LiquidHaskell/F* axis
> - Dependent pattern matching, proof irrelevance, universes and universe polymorphism
> - Effect systems: effect rows, algebraic effects & handlers, coeffects, gradual & migratory typing
>
> **Semantic statics**
> - Parametricity, relational logical relations, free theorems, abstraction theorem
> - Realizability models, normalization by evaluation, canonicity
>
> ## 2. ADT layer — the algebra of data itself
>
> - Initial/terminal objects, sums (+), products (×), unit (1), void (0); the type semiring
> - Exponentials Bᴬ, currying, cartesian closure — `|A → B| = |B|^|A|`
> - Recursive types: μ (inductive) vs ν (coinductive); iso- vs equi-recursive; Lambek's lemma (initial algebra is an iso)
> - Polynomial functors, containers (shapes ⊳ positions), W-types and M-types as universal (co)inductive presentations
> - Generic programming: pattern functors, sum-of-products, `Regular`/`Generic`/`Multirec`, datatype-generic traversal
> - **Derivatives**: ∂ of a datatype = one-hole context ⇒ zippers (Huet, McBride); dissection for tail-recursive traversal
> - Combinatorial species & generating functions — data types as analytic functors, `T ≅ 1 + T²` and the "seven trees in one" isomorphism
> - Nested/non-regular types, higher-order & indexed functors, ornaments (relating data types by added index structure)
> - Quotient types, HITs, setoids; views and abstract types
> - Existential packaging = data abstraction (Mitchell–Plotkin: abstract types have existential type)
>
> ## 3. Functional algebra — the categorical machinery
>
> **Order & algebraic hierarchy**
> - magma → semigroup → monoid → group; commutative/idempotent variants
> - semiring, ring, module, lattice, Heyting/Boolean algebra, Kleene algebra, quantale
> - preorder → poset → semilattice → complete lattice → CPO/dcpo → Scott domain
> - Join-semilattices as the algebraic substrate of CRDTs — monotone merge, convergence
>
> **Functorial structure**
> - Functor, applicative (lax monoidal), monad, comonad, arrow, profunctor, bifunctor, contravariant, representable, distributive
> - Natural transformations, adjunctions (F ⊣ U), units/counits, monads-from-adjunctions
> - Yoneda / coYoneda, Kan extensions (Lan/Ran) — "all concepts are Kan extensions", including the CPS and free-monad encodings
> - Kleisli and Eilenberg–Moore categories; distributive laws λ: ST → TS; monad transformers vs effect handlers
> - Monoidal / symmetric monoidal / closed / traced / compact closed categories; PROPs and string diagrams
> - Free constructions: free monoid, free monad, freer/operational, cofree comonad, free applicative — syntax as initial algebra, interpretation as the unique algebra morphism
>
> **Recursion schemes** (the calculus of folds)
> - cata / ana / hylo; para / apo; histo / futu; zygo, mutu, dyna, chrono; Elgot algebras
> - Fusion laws, banana-split, fold–build/shortcut deforestation, the "Bananas, Lenses, Envelopes and Barbed Wire" corpus
> - Fixed-point theory: Knaster–Tarski, Kleene ascending chain, Bekić, guarded/productive corecursion, sized types
>
> **Optics** — bidirectional algebra
> - Iso, lens, prism, traversal, affine, setter, getter, fold; van Laarhoven vs profunctor (Tambara module) encodings
> - Lens laws (get-put, put-get, put-put) as *information-preservation* laws — see §6
> - Delta lenses, symmetric lenses, edit lenses; Traversable ≅ finitary container
>
> ## 4. Structural layer — composition, presentation, rewriting
>
> - Structural recursion/induction, well-founded recursion, accessibility, termination measures
> - Structural sharing & persistence: HAMT/CHAMP, finger trees, RRB-vectors, path copying, fat-node/persistent arrays
> - Presentations: generators + relations; algebraic theories, Lawvere theories, clones, operads; theory ≅ finitary monad
> - Term rewriting: confluence, Church–Rosser, critical pairs, Knuth–Bendix completion, strong/weak normalization
> - Equational reasoning, congruence closure, e-graphs & equality saturation (the modern rewrite engine)
> - Institutions and theory morphisms; colimits of theories = modular specification (ties directly into §7)
> - Module systems as structural algebra: ML functors, applicative vs generative functors, signatures as interfaces of theories
>
> ## 5. Dynamic layer — operational and behavioural structure
>
> **Reduction & strategy**
> - α/β/η, confluence, standardization; head/weak-head normal form
> - CBV, CBN, call-by-need, call-by-push-value (the unifying calculus), optimal reduction & Lévy labels, interaction nets
> - Graph reduction, thunks, blackholing, strictness analysis, space leaks, deforestation
>
> **Abstract machines**
> - SECD, Krivine, CEK/CESK, ZINC (OCaml), STG (GHC), G-machine, TIM
> - BEAM: reduction counting, per-process heaps, copying message passing, preemptive scheduling — a machine whose *dynamic* semantics is the safety story
>
> **Control**
> - Continuations, CPS, defunctionalization (Reynolds), ANF; delimited control (shift/reset, prompt/control, `Effect` in OCaml 5)
> - Algebraic effects & handlers as the modern unifier of exceptions/state/nondeterminism/async
>
> **Semantics**
> - Small-step vs big-step vs denotational vs axiomatic; abstract machines as derived semantics
> - Domain theory: Scott continuity, ⊥, approximation order, information ordering; full abstraction; game semantics
> - Contextual equivalence, applicative bisimulation, coinduction & up-to techniques, step-indexed logical relations
> - Separation logic / Iris for stateful FP; Hoare type theory
>
> **Concurrent & distributed dynamics**
> - Process algebras: CCS, CSP, π-calculus, join calculus, ambient calculus
> - Actor model & supervision trees; let-it-crash as a *dynamic* algebra of failure and restart (OTP restart strategies form a compositional recovery structure)
> - Session types & behavioural types (binary and multiparty); linear logic ↔ session types (propositions-as-sessions)
> - CRDTs: state-based (join-semilattice, monotone) vs op-based (commutative); lattice-based programming (LVars/Bloom, CALM theorem)
> - Incremental & self-adjusting computation, differential dataflow, change structures (a change action is a monoid action on values)
>
> ## 6. Information-theoretic layer
>
> **Quantitative content of types**
> - Cardinality semantics: information content of a value of type T ≈ log₂|T| bits; 0/1/+/×/^ mirror the arithmetic exactly
> - Analytic combinatorics / species: EGF & OGF of a datatype give exact counts and asymptotics; entropy of a data type under a distribution
> - Kolmogorov complexity, algorithmic information, MDL — programs as compressed descriptions; occam-style inductive inference
> - Huffman/arithmetic coding expressed as (un)folds; compression ≅ ana/cata pair over a code tree
>
> **Information flow as a type discipline**
> - Parametricity = enforced ignorance: a polymorphic type *bounds* the information a function can extract
> - Non-interference, security lattices (Denning), the Dependency Core Calculus, labelled/graded monads for IFC
> - Declassification, robust declassification, quantitative information flow (min-entropy leakage, channel capacity of a program)
> - Differential privacy via sensitivity typing: Fuzz / DFuzz / Duet — metric-preserving maps as linear (⊸) functions; graded comonads track ε budget
>
> **Conservation and reversibility**
> - Landauer's principle, reversible computation, Toffoli/Fredkin, bijective/invertible languages
> - Linear & quantitative types as resource/usage accounting = information not silently duplicated or discarded
> - Lens laws as information laws: put-get (no loss), get-put (no fabrication), put-put (idempotent overwrite); well-behavedness = the source decomposes as (view × complement)
> - Bidirectional transformations & delta lenses: what's the *minimum* information needed to propagate a change
>
> **Order-theoretic information**
> - Scott's information ordering (⊑ = "is less defined than") vs computational order; approximation as partial information
> - Information systems (Scott), stable domain theory, coherence spaces → linear logic (Girard's route from stability to ⊗/⅋)
> - Entropy/monotonicity in distributed systems: CALM, monotone = coordination-free; lattice join as information accumulation
>
> ## 7. Ontology layer — theories, meaning, and the world
>
> **Logic-based ontology**
> - Description logics: 𝒜ℒ𝒞 → 𝒮ℋ𝒪ℐ𝒩 → 𝒮ℛ𝒪ℐ𝒬; OWL 2 profiles (EL, QL, RL) and their complexity/tractability trade-offs
> - RDF triples, RDFS entailment, SPARQL, SHACL/ShEx constraints, open- vs closed-world, unique-name assumption
> - Upper ontologies: BFO, DOLCE, SUMO, UFO; continuants vs occurrents, endurantism vs perdurantism (3D/4D)
> - Mereology & mereotopology (RCC-8), Allen's interval algebra, qualia/quality spaces, roles vs types vs rigidity (OntoClean)
>
> **Ontology as algebra / category**
> - Formal Concept Analysis: concept lattices from a Galois connection between objects and attributes — ontology *derived* rather than declared
> - Institutions (Goguen–Burstall): a specification-language-independent notion of "theory"; ontology alignment as colimits/pushouts of theories
> - Ologs (Spivak): categorical ontology logs — boxes as types, arrows as functional relations, paths as facts
> - Functorial data migration: schema = category, instance = Set-valued functor, migration = Δ/Σ/Π adjoint triple; databases and ontologies as the same object
> - Sheaves & presheaves over a site: local-to-global consistency of assertions; topoi as universes of variable sets; Lawvere–Tierney topologies as modalities
>
> **Type theory as ontology**
> - Propositions-as-types gives an ontology with *proof-relevant* membership; identity types as "what it means to be the same thing"
> - HoTT: univalence (isomorphic ⇒ equal), h-levels (prop/set/groupoid) as an ontology of sameness, HITs for quotients and higher structure
> - Structural (what a thing *is made of*) vs nominal (what a thing *is declared to be*) — the ADT/ontology fault line: sums and products give a compositional ontology, DLs give a subsumption-based one
> - Setoid hell, quotient types, and the ontology of identity criteria (Frege/Quine's "no entity without identity")
>
> ## Cross-cutting bridges worth internalizing
>
> | Bridge | Static | Structural | Dynamic | Informational |
> |---|---|---|---|---|
> | **Fixed points** | recursive types μ/ν | initial algebra / final coalgebra | recursion & corecursion, productivity | Kleene ascent as accumulating information |
> | **Linearity** | ⊸, QTT, ownership | substructural presentation | session types, protocols | no-cloning, Landauer, sensitivity/DP |
> | **Modality** | graded/comonadic types | coeffect algebra | staging, effects & handlers | security labels, privacy budgets |
> | **Duality** | ∀/∃, products/sums | algebra/coalgebra | data/codata, cata/ana | construction vs observation (info in vs info out) |
> | **Adjunction** | quantifiers ⊣ substitution | free ⊣ forgetful | CPS ⊣ direct style | lens = information-preserving adjunction-ish decomposition |
>
> If you want, I can collapse any one stratum into a working reference — e.g. the recursion-scheme/optics algebra as an OCaml or Elixir-flavoured cheat sheet, or the refinement-type + SMT slice as a design note for an Aeon-style implementation. --Good question to ask *before* the atlas ships, because each stratum wants a different specification style. Think of it as four tiers of rigor, then a per-stratum mapping.
>
> ## The four tiers
>
> **1. Executable oracles (cheapest).** A second implementation or reference model you test against. Tools: plain `dune runtest`, Alcotest/OUnit2 for units, `ppx_expect` for golden/expectation tests, cram tests for CLI-level behavior. Differential testing is the workhorse here — e.g. the Direct/CPS/CEK evaluators must agree on every generated program; my ALC tableau should agree with HermiT/ELK on sampled ontologies.
>
> **2. Property and law specifications.** Most of the atlas's content *is* equational law (monoid associativity, functor/monad laws, lens laws, iso roundtrips, CRDT join semilattice axioms, Huffman `decode ∘ encode = id`). This is property-based testing territory:
>
> - **QCheck/QCheck2** — generators + shrinking; `ppx_deriving_qcheck` derives generators from type definitions
> - **qcheck-stm / qcheck-lin** (from `multicoretests`) — model-based state-machine testing: run HAMT or finger tree against a `Map`/`Deque` model; `lin` checks linearizability of concurrent code
> - **Crowbar** — coverage-guided PBT via AFL (`ocamlopt -afl-instrument`); **Monolith** (Pottier) — model-based fuzzing of an implementation against a reference
> - **Gospel** — the OCaml interface specification language (pre/posts, invariants, models in `.mli` comments); **Ortac** compiles Gospel specs into runtime assertions or auto-generated qcheck-stm suites. This is the closest thing OCaml has to "specs as artifacts"
> - Quality of the test suite itself: **bisect_ppx** (coverage), **mutaml** (mutation testing)
>
> **3. Deductive verification / proof.** For metatheory (progress/preservation, confluence, normalization) and anything the GADTs can't carry:
>
> - **Rocq** (formerly Coq) — with Autosubst for binders, Iris if you want separation logic; **CFML** proves actual OCaml code via characteristic formulae; **coq-of-ocaml** translates
> - **Agda** — best ergonomics for intrinsically-typed syntax (the GADT STLC is essentially an Agda-style development)
> - **Lean 4** — strongest library momentum (Mathlib)
> - **Why3** — the pragmatic hub: write WhyML, discharge to Z3/CVC5/Alt-Ergo; **Cameleer** verifies Gospel-annotated OCaml through Why3
> - **SMT layer** — Z3 and CVC5; the official **Z3 opam bindings** matter for the refinement-types stratum (a real Aeon-style checker calls Z3 natively rather than printing SMT-LIB, though SMT-LIB2 text + `z3 -in` is the right first cut, which is exactly what the `Vcgen` module does). `smtml` gives a solver-agnostic OCaml frontend
> - **F\*** / **Liquid Haskell** / **Dafny** — reference designs to crib from for refinement inference (liquid-style predicate abstraction)
>
> **4. Model checking for the dynamic stratum.** Protocols and concurrency are temporal, not equational:
>
> - **TLA+** (TLC, Apalache) or **Quint** — CRDT convergence, replication, supervision protocols
> - **mCRL2** / SPIN — process algebra, bisimulation checking, modal μ-calculus
> - **nuscr** — multiparty session types in OCaml (Scribble lineage); pairs directly with the FuSe-style channel code
> - **DSCheck** — systematic model checker for OCaml 5 atomics; OCaml 5.2+ has a **ThreadSanitizer** build for data races
> - Rewriting specifically: **Maude** (rewriting-logic specs), **TTT2** (termination), **CSI** (confluence), CeTA for certified proofs; **egg** as the reference e-graph
>
> ## Per-stratum mapping
>
> | Stratum | Specify with | Test with |
> |---|---|---|
> | 1 Static | Ott/Rocq/Agda metatheory; Gospel on checker API; SMT-LIB for VCs | Well-typed-term generators (QCheck), differential vs reference checker, Z3 on VCs |
> | 2 ADT | Iso laws as Gospel/QCheck properties; Agda for proofs | Roundtrip properties, derived generators |
> | 3 Algebra | Law suites (typeclass laws); Rocq for fusion theorems | QCheck law harness per instance; metamorphic tests for optics |
> | 4 Structural | Gospel model specs (Map/sequence models) | qcheck-stm vs model; core_bench/bechamel for complexity claims |
> | 5 Dynamic | TLA+/Quint, mCRL2, nuscr; small-step semantics in Redex/K | Differential evaluators, lin/DSCheck, CRDT convergence properties |
> | 6 Information | Hyperproperties: noninterference as 2-run property; DP as statistical bound | Vary-secret/observe-public QCheck tests; sampling tests for Laplace; roundtrip coding laws |
> | 7 Ontology | OWL profiles, SHACL/ShEx shapes, CQL for migrations | HermiT/ELK/Konclude as oracles, W3C test suites, conexp for FCA cross-check |
>
> Two subtleties worth flagging: noninterference and differential privacy are *hyperproperties* (relations between runs), so single-execution assertions can't express them — you test pairs of runs or statistics over samples. And generating well-typed λ-terms for stratum 1 is a known-hard generator problem (Pałka et al.); the practical trick is generating typing *derivations*, not terms.
>
> **Minimum viable stack**, if you want one `opam switch` that covers 90%: `dune, alcotest, qcheck2, ppx_deriving_qcheck, ppx_expect, gospel, ortac, multicoretests, bisect_ppx, core_bench, z3` — plus Rocq or Lean on the side for the handful of theorems you actually want machine-checked, and TLA+/Quint for the protocol pieces.
>
> Happy to wire this in concretely — I can scaffold the atlas as a dune project with QCheck law suites and a Gospel-specified interface for one exemplar per stratum, so every claim in the document is executable.

### Prompt 2

> show all the gaps and differences between the 2 solutions

### Prompt 3

> add detaiked journal entry with prompt.

---

## 2. Acquisition

`facebook/docusaurus` cloned (`--depth 1`) to `third_party/docusaurus`.

| Property | Value |
|---|---|
| Commit | `16f537309e357226dafd3b0137cdd711b68bece8` |
| Commit date | 2026-07-23 |
| Head subject | `docs: add @deskcrew/docusaurus-plugin to community resources (#12303)` |
| Size | 115 MB |
| Packages | 40 |

### 2.1 Boundary disposition

Docusaurus is JavaScript/TypeScript. Under the three-language rule (`src/` Zig, `harness/` +
`scripts/` OCaml, `fixtures/` Erlang) JS/TS may exist only as a **generated codegen target**
or a **vendored third-party dependency**. This tree is neither built, executed, nor imported —
it is a **source-only reference dependency**, the same disposition as
`third_party/microsoft_playwright_159`.

Confirmed the gate does not scan it: `check_boundaries` excludes `third_party/` at
`harness/zigvm_harness.ml:838`, `:1522`, `:2155`.

### 2.2 Hygiene edits applied

The clone was **not** matched by any `.gitignore` rule, so 115 MB of JS/TS would have been
committed. Two edits, following the Playwright precedent:

1. `.gitignore` — added `/third_party/docusaurus/` with a comment recording the
   source-only/never-built disposition.
2. `third_party/DOCUSAURUS_PIN` (new, tracked) — commit hash + provenance line, matching the
   `third_party/OTP30_PIN` two-line format.

Verified with `git status --short`: `third_party/docusaurus` no longer appears;
`?? third_party/DOCUSAURUS_PIN` does.

---

## 3. Method

Comparison subject on the zigvm side: `harness/markdown_ast.ml` (741 L),
`harness/docs_wiki.ml` (5387 L), `harness/typed_html.ml` (114 L),
`harness/wiki_sidebar_tree_generator.ml` (123 L), and ~40 `zk_*.ml` modules.

**Every incidence claim in this session was measured against the real corpus before being
stated.** This was decisive three times — see §5. The critical scoping fact:
`docs_wiki.ml:1327` sets `zk_dir = "docs/zk"`, so the rendered wiki is *only* that directory.
All counts are therefore reported twice: inside `docs/zk` (live) and across all of `docs/`
(latent).

---

## 4. Principal finding — a Stratum-2 structural ceiling

`markdown_ast.ml` declares:

```
type t = block list
Ul of item list          and item = { i_body : inline list; i_todo : bool option }
Blockquote of { callout : (string * string) option; body : inline list }
cell = { c_body : inline list }
```

**No block constructor contains a `block`.** The carrier is `List (Block (List Inline))` —
a polynomial functor applied once, depth exactly 2 — where Docusaurus's mdast is a genuine
recursive `Parent`, i.e. `μX. Node + List X`.

In the framework's vocabulary: zigvm's document type is **not the initial algebra of a
recursive functor**, so `render` is a two-level walk rather than a catamorphism. Confirmed at
`markdown_ast.ml:648-700`, where `render_block` maps each `item` to a single `li` of inline
content.

This single fact explains four apparently separate gaps: nested-list flattening, admonitions
that cannot contain code or lists, `<details>`, and tabs.

A second, independent and much cheaper AST omission: `Code_block of string` **discards the
fence info string**, so language, title, and line-highlight meta are unrepresentable. That one
type change gates five downstream features.

---

## 5. Measurements, including three that overturned a hypothesis

Recording these in full because in each case the measurement contradicted the expectation, and
the repo heuristic — *a new checker reporting mass violations is itself the suspect* — held.

| Probe | Expectation | Measured | Outcome |
|---|---|---|---|
| Duplicate heading anchors | widespread | **3 docs / 10 collisions of 695 files** | real but latent |
| Fragment wikilinks `[[x#y]]` | some dangling | **0 in `docs/zk`** | gap is latent capability, not a defect |
| Raw inline HTML | 398 hits looked like mass breakage | **0 in `docs/zk`**; all in `docs/bonsai`, `docs/journal`, … | not a live defect |
| Strikethrough `~~x~~` | live rendering defect | 11 hits, **0 in `docs/zk`** (2 files) | latent |
| Images `![](…)` | some | **0 in `docs/zk`, 0 anywhere in `docs/`** | the wiki has no images at all |
| Nested list items | unknown | **4 notes** in `docs/zk` | live, small |
| Heading anchors total | — | **676** in `docs/zk` | all title-derived |

Anchor-collision detail: 7 in `journal/20260726-otp30-three-axis-flip-fractal-plan.md`,
2 in `journal/20260731-full-system-audit-and-fractal-execution-plan.md`,
1 in `zk/episodic/gap-float-to-list-opts.md`.

The reframing this forces: zigvm's markdown is **not "missing CommonMark"** in a defect sense.
It is a **closed dialect matched to a curated, machine-authored corpus**, admitted by an oracle
over exactly that corpus. Most gaps are about what one might want to *write next*.

### 5.1 Two corrections made during the session

- `<html lang="en">` **is** present (`docs_wiki.ml:963`, `Th.a_lang "en"`); an initial grep for
  `lang=` missed the TyXML spelling. Colour-mode support is likewise genuine parity
  (`docs_wiki.ml:709-710`), not a gap.
- A `--check-only` run printed every stage `ok` but the exit line rendered empty, because
  `${PIPESTATUS[0]}` is a bash-ism and this shell is zsh (`$pipestatus[1]`). Re-run capturing
  the true status. This is exactly the CAST-12 lesson recorded in
  the `zigvm-verify-exit-codes` memory: verify by exit code, never by the printed line.

---

## 6. Gap summary by layer

Full matrices are in the two delivered analysis documents (§8). Condensed:

| Layer | Gap count | Character |
|---|---|---|
| A. Markdown dialect | ~14 latent, 2 live | closed dialect; images/strikethrough/footnotes/HTML all 0 in `docs/zk` |
| B. Frontmatter | ~7 | Docusaurus defines 21 doc fields; zigvm uses 2 (`agent`, `draft`) |
| C. Navigation | ~8 | sidebar ordering absent (self-documented `[N/A]`); versioning/i18n/blog not wanted |
| D. Display | ~8 | no scrollspy, copy-code, syntax highlighting, back-to-top, skip-to-content |
| E. Link integrity | ~4 | no fragment validation; pure not stateful slugger; no `{#id}` |
| F. Structural ceiling | 1 root cause | blocks 4 features (§4) |
| G. zigvm ahead | 7 areas | typing, verification, lint, graph, security, print, wiki-native constructs |
| H. Not recommended | 13 | MDX, plugins, versioning, i18n, blog, sitemap, JSON-LD, RSS, PWA, Algolia, … |

### 6.1 Where zigvm is decisively ahead

- **Typed rendering** — TyXML enforces the HTML content model at compile time; the source
  records TyXML *refusing* anchor-in-anchor (`markdown_ast.ml:593`). Docusaurus casts untyped
  `unist` nodes throughout.
- **Verification** — oracle + final encoding admitted by whole-corpus differential + seeded
  fuzz, with 5 quirks deliberately pinned by named BDD scenarios. Docusaurus has snapshot tests.
- **Document lint** — 24 rules over 1694 files, ratchet at errors 0 / warnings 0, backed by
  `TABLE_ALGEBRA.md` and `HTML_ALGEBRA.md`. No analogue.
- **Knowledge graph** — backlinks, contextual backlinks, PageRank/PPR, similarity, MoC
  freshness, orphan index, typed edges, depth-limited cycle-safe transclusion, anomalies,
  currency. Docusaurus has **none** of this.
- **Security** — path-traversal-safe note paths, CSP generator, cache-poisoning detector,
  transclusion depth limiter, agent write quotas, note signing.
- **Print stylesheet**, block anchors `^id`, wikilinks, inline tags.

---

## 7. Ranked proposal (advisory — no slice opened)

| # | Item | Stratum | Tier | Cost | Blocked on |
|---|---|---|---|---|---|
| 1 | `Code_block` carries lang + meta | 2 | 2 | S | — |
| 2 | Mermaid fenced blocks | 5 | 1 | S | #1 |
| 3 | Copy-code button + lang label | 5 | 1 | S | #1 |
| 4 | Stateful slugger (collision suffixes) | 3 | 2 | S | quirk-list amendment |
| 5 | Anchor collection + fragment validation | 6 | 2 | M | — |
| 6 | `{#custom-id}` stable heading ids | 2 | 2 | S | — |
| 7 | Right-rail TOC + scrollspy | 5 | 1 | M | — |
| 8 | `numberPrefix` / `sidebar_position` | 4 | 2 | S | — |
| 9 | git `lastUpdatedAt` / `lastUpdatedBy` | 7 | 1 | S | — |
| 10 | μ-recursive block carrier | 2 | 2 | L | — |
| 11 | `<details>`, tabs, admonition titles | 5 | 2 | M | #10 |
| 12 | `unlisted` visibility | 6 | 1 | S | — |

Tier column uses the caller's four-tier scheme (1 oracle, 2 property/law, 3 proof,
4 model-check). Items 1–3 form one coherent slice. Item 10 should be planned, not squeezed in.

**Discipline note.** Items 4 and 10 change output on published pages. Under the oracle/final
rule the streaming renderer *is* the specification, and the flattening and pure-slug behaviours
are currently pinned quirks. Either change therefore requires a deliberate quirk-list amendment
with a failing law first — never a silent fix.

---

## 8. Artifacts produced

| Artifact | Kind | Location |
|---|---|---|
| Stratified analysis | delivered document | scratchpad, sent to user |
| Complete gap matrix (8 sections) | delivered document | scratchpad, sent to user |
| `third_party/docusaurus` | source-only reference dep | gitignored, pinned |
| `third_party/DOCUSAURUS_PIN` | tracked pin | new file |
| `.gitignore` | edited | +1 rule, +3 comment lines |
| This journal | tracked | `docs/journal/` |

---

## 9. Gate evidence

`opam exec -- dune exec ./harness/zigvm_harness.exe -- --root "$PWD" --check-only`

```
boundary check: ok
skill check: ok (30 skills)
design check: ok (SC-F registry total 1..42; 5 doc(s) reference-clean; phase runbook total P0..P9)
lint check: ok (1694 docs linted, 24 rules, 0 error(s), 0 warning(s) — at or under the ratchet)
doc check: ok
bif-table freshness: ok
unicode-table freshness: ok
fixture check: ok
EXIT=0
```

Exit code read unpiped, per the `zigvm-verify-exit-codes` memory. This run **predates** the addition of
this journal file; the doc lint must be re-run after it lands, since the ratchet is at 0/0 and
any new finding fails the gate.

---

## 10. Residuals and honest bounds

- **No slice was opened and no `record_cycle` was recorded.** This session produced analysis
  plus hygiene edits, not a law-carrying behaviour change. Nothing here is completion evidence
  for any `gap-*` slice.
- **The ranked proposal is advisory.** It has not been through `fractal-decision-calculus`;
  no Admiralty grading, AHP, or pre-mortem was performed. It is one agent's ranking.
- **Coverage bound.** 40 Docusaurus packages were inventoried by file listing and targeted
  reads, not read exhaustively. Areas examined closely: `mdx-loader` (all 13 remark plugins),
  `utils` (slugger, heading ids, links, visibility, VCS), `plugin-content-docs` (frontmatter,
  sidebars, versions), `theme-common`, `theme-classic` component inventory, `brokenLinks.ts`.
  Areas inventoried only: blog, PWA, ideal-image, search-algolia, bundler, faster, babel.
- **The "not recommended" column is a judgement**, not a measurement — it assumes the wiki
  stays internal and Tailscale-served with no search-engine surface. If that assumption
  changes, sitemap/JSON-LD/RSS move back onto the table.
- **Latent-gap incidence is a snapshot** of 2026-08-07. A future note using images, tabs, or
  fragment links would convert the corresponding row from latent to live.

---

## 11. Related

Agent auto-memories — these are memory-file slugs, **not** ZK notes, so they are deliberately
not wikilinked (a `[[…]]` here would assert a graph edge that does not exist):
`zigvm-verify-exit-codes` (the exit-code discipline applied twice this session),
`zigvm-web-algebra-programme` (the typed-html/TyXML conversion programme this analysis
touches), `zigvm-lint-algebras-and-bonsai` (the table/markup algebras behind the 0/0
ratchet), `zigvm-zk-wiki-program` (the ZK/wiki programme whose render stack is the subject).

Repo artifacts:

- `skills/tyxml-conversion` — the conversion recipe for items 1–3 and 10
- `skills/zk-knowledge-base` — governs any change to the ZK surface
- `harness/markdown_ast.ml` — the AST and renderer analysed in §4
- `harness/docs_wiki.ml` — the wiki page shell and ZK graph layer
- `third_party/DOCUSAURUS_PIN` — the pin this session recorded
