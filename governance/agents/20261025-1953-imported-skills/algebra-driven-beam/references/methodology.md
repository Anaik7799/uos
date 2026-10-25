# The Algebra-Driven Design process

How to go from a fuzzy domain to a signature, laws, and derived
implementations. This is the Zig translation of the book's two arcs —
*Designing Algebras* and *Deriving Implementations* — condensed into an
operational procedure for Erlang/Elixir on the BEAM. Vocabulary and doctrine here; BEAM mechanics live in
`beam-idioms.md`.

## Contents
1. Vocabulary
2. Choose observations first (the semantic domain)
3. The operation inventory: constructors, combinators, observations
4. Deriving laws
5. What makes a good algebra (quality gates)
6. Law discovery when you're stuck (QuickSpec by hand)
7. Deriving implementations (initial → tests → efficient)
8. Worked micro-example index

## 1. Vocabulary

- **Algebra**: a set of types, operations over them, and equations (laws) the
  operations satisfy. The *user-facing API is the algebra*; everything else is
  implementation detail.
- **Signature**: just the types of the operations, e.g.
  `beside : (Tile, Tile) -> Tile`. No bodies.
- **Constructor**: introduces a value from outside the type
  (`fill : Pixel -> Canvas`, `empty : () -> Canvas`).
- **Combinator**: consumes and produces values of the type
  (`overlay : (Canvas, Canvas) -> Canvas`, `cw : Tile -> Tile`).
- **Observation** (a.k.a. eliminator): extracts information *out* of the type
  (`rasterize : Canvas -> Raster`, `contains : (Region, Point) -> bool`).
  Observations define what the type *means*; two terms the observations cannot
  distinguish **are equal**, full stop.
- **Semantic domain / denotation**: the mathematical object a value stands
  for. Written `Canvas ≙ (x, y) -> ?Pixel` ("a canvas *is* a function from
  coordinates to optional pixel"). Also called denotational design.
- **Law / axiom**: an equation between terms, universally quantified over
  variables, judged under the observations:
  `∀x. overlay(empty, x) == x`.
- **Initial encoding**: represent terms as data (a tagged-union AST); meaning
  comes from an interpreter run later. Deep embedding.
- **Final encoding**: represent terms directly as their meaning; operations
  compute immediately. Shallow embedding.
- **Homomorphism**: a structure-preserving map between two implementations of
  the same signature: `denote(overlay_A(x, y)) == overlay_B(denote(x), denote(y))`.
  The correctness statement connecting encodings.

## 2. Choose observations FIRST

Most APIs are designed constructor-first ("what can users build?"). ADD
inverts this: decide **what questions can be asked** of a value, because the
answers are the only thing that exists. Everything unobservable is
implementation freedom.

Procedure:
1. List every question a user could ask of a value of the type.
2. Collapse them into the *fewest, most general* observations. Prefer one
   total function over many partial predicates. (Book example: a scavenger
   hunt's many status checks collapse into one unified
   `Challenge -> (rewards, remaining-challenge)` observation.)
3. The semantic domain is the joint codomain of the observations. State it as
   a `≙` equation in a comment at the top of the module. On the BEAM it
   usually becomes a plain term — most often a **map tabulating** a
   finite-domain function (an 8×8 grid map standing in for
   `{X, Y} -> pixel() | transparent`), because map `=:=` is canonical and
   order-independent, making total observational equality free.
4. If two candidate terms would be indistinguishable but *shouldn't* be, you
   are missing an observation. If the domain distinguishes things users can
   never see, shrink it.

Keep the test-time domain small enough that comparing denotations quantifies
over the whole domain (an 8×8 grid), not a sample of it.

## 3. The operation inventory

For each operation, record: name, type, class (constructor/combinator/
observation), informal meaning **stated in the semantic domain**:

```
overlay : (Canvas, Canvas) -> Canvas        -- combinator
  ⟦overlay(t, b)⟧(x, y) = ⟦t⟧(x, y) orelse ⟦b⟧(x, y)
```

That `⟦·⟧` line is the specification. Writing it forces precision *and* is
80% of the final-encoding implementation. Every operation must have one. If
you cannot write it, the operation is under-specified — stop and design.

Rules of thumb:
- Combinators must be **closed** (return the algebra's type) and **total**
  (no panics, no partiality; make illegal states unrepresentable instead).
- Prefer few polymorphic/general operations over many specific ones; specific
  ones should be derivable (`fill(px) = ...` in terms of primitives, if
  possible) and shipped as derived helpers, not primitives.

## 4. Deriving laws

Work through the pairwise grid: for every (operation, operation) pair, ask
"what happens when one is applied to the result of the other?" and write the
equation, or explicitly note "no relation". Sources of laws, in order of
yield:

1. **Identity elements**: does some constructor act as a unit for a
   combinator? `overlay(empty, x) == x`.
2. **Associativity / commutativity** of binary combinators.
3. **Idempotence**: `f(x, x) == x` (common in "last/first-wins" semantics).
4. **Annihilators**: `combine(zero, x) == zero` (deny-overrides policies,
   multiplication by 0).
5. **Distributivity / absorption** between two combinators.
6. **Self-inverse / involution**: `cw(cw(cw(cw(t)))) == t`.
7. **Observation equations**: how each observation acts on each
   constructor/combinator — these are exactly the `⟦·⟧` lines from §3 and
   become the interpreter's function clauses.

Validate each candidate law *in the semantic domain by hand* on one example
before adopting it. A wrong law is worse than a missing one: the property
tests will faithfully enforce it against every future implementation.

Every law goes in the design note in this exact shape (name, equation,
quantified variables) — the property-test suite is a 1:1 transcription:

```
Law "overlay left identity":  ∀x: Canvas.  overlay(empty(), x) == x
```

## 5. What makes a good algebra — quality gates

Gate before writing Zig. Fail any gate → redesign.

- **Closure**: every combinator maps the type into itself with no
  side-conditions.
- **Compositionality**: the meaning of a term is a function of the meanings
  of its parts (guaranteed if every `⟦·⟧` line only mentions sub-term
  denotations).
- **No privileged constructors**: laws should not need to inspect "how a
  value was built". If a law only holds for `fill`-built canvases, the design
  leaks.
- **Parsimony**: remove any operation expressible via others; re-add as a
  derived helper.
- **Orthogonality**: operations shouldn't overlap in capability.
- **Generalization pressure**: when a law looks like a known structure's law
  but doesn't quite fit, try generalizing the *type* (the book repeatedly
  turns concrete types into type parameters this way). On the BEAM: parametrize the
  algebra module over the payload (pass payload callbacks in a map of funs,
  or a `Payload` module implementing its own tiny behaviour).
- **Law coverage**: every combinator appears in ≥1 law. Unconstrained
  operations are unspecified operations.

## 6. Law discovery when stuck (QuickSpec by hand)

QuickSpec doesn't exist for Zig; emulate it:

1. Enumerate all well-typed terms of depth ≤ 2–3 over a couple of variables
   (`x`, `y`) and the signature. Small — do it in comments or a scratch
   program.
2. Evaluate each term's denotation for several random assignments of the
   variables (a scratch eunit test with the initial encoding does this in ~20 lines).
3. Bucket terms whose denotations always coincide. Each bucket ⇒ candidate
   equation between its simplest members.
4. Adopt the ones that survive scrutiny (§4's hand-validation), discard
   coincidences by raising the number of random assignments.

This is mechanical and cheap with the initial encoding already in hand —
another reason the initial encoding comes first.

## 7. Deriving implementations

1. **Initial encoding is free.** One union variant per constructor/
   combinator; the interpreter's arms are the `⟦·⟧` lines verbatim. It is
   correct by construction and exists to be the *oracle*.
2. **Generate the test suite from the laws** (Phase 4 of SKILL.md). Run it
   against the initial encoding. Failures indict the laws/domain, not the
   code — iterate the design here, where change is cheap.
3. **Derive the efficient representation from the denotation**, not from
   intuition:
   - Denotation is a function with small finite domain → **tabulate** it
     (array/grid). Operations become element-wise loops; `empty` becomes a
     constant.
   - Laws form a rewrite system with normal forms → store the **normal form**
     (e.g. associativity+identity ⇒ flat list; +commutativity+idempotence ⇒
     sorted set; annihilator ⇒ short-circuit).
   - Denotation is a fold over inputs → store the fold's accumulated state
     (classic monoid trick).
4. **Prove equivalence by homomorphism property test**: twin identically-
   seeded generators build the same term shape in both encodings; assert
   denotations agree. This test is the license to delete the AST from
   production paths while keeping it in tests forever.
5. **Optimize by algebraic rewriting only**: each optimization must cite the
   law that justifies it, and the suite must stay green. This is how ADD
   finds performance "not via intuition but through algebraic manipulation".

## 8. Worked micro-example index

- `references/canvas_algebra.erl` + `canvas_initial.erl` + `canvas_final.erl`
  — spatial canvas: **non-commutative idempotent monoid** (top-wins overlay);
  the denotation is literally a map and `overlay` is literally `maps:merge`;
  homomorphism + doctrine-guard + negative-contract tests included.
- `assets/severity_algebra.erl` + `severity_initial.erl` +
  `severity_final.erl` — severity: **bounded semilattice** (worst-wins), the
  smallest complete skeleton; adapt it for new domains.

When modeling a new domain, first ask which catalog structure (see
`algebra-catalog.md`) the pairwise-grid laws resemble — recognizing the
structure imports its whole law set and known implementation tricks for free.
