---
name: algebra-driven-zig
description: >-
  Design and implement Zig libraries, APIs, and domain models using
  Algebra-Driven Design (Sandy Maguire's methodology): algebraic signatures,
  equational laws, property-based tests, and initial/final encodings mapped to
  Zig's comptime contracts, tagged unions, and arena allocation. Use this skill
  whenever the user mentions algebra-driven design, ADD, algebraic
  specification, denotational or equational design, "leak-free abstractions",
  designing a DSL or combinator library in Zig, monoids/semigroups/semilattices
  or algebraic laws in Zig, property-based testing or QuickCheck/QuickSpec-style
  testing in Zig, initial vs final encodings, tagged-union ASTs with
  interpreters, or comptime interface contracts — and also when the user asks to
  "design a clean abstraction", "model a domain", or "architect a library" in
  Zig, even if they never say the word "algebra".
---

# Algebra-Driven Design in Zig

Treat software as an **algebraic specification**, not a pile of mutating state:
a domain is a set of types and operations (the *signature*), governed by
equational *laws*, given meaning by one or more *interpretations*. The design
is correct when every law passes as a property-based test over both a naive
interpretation and the efficient one.

The methodology comes from *Algebra-Driven Design* (Sandy Maguire). The book is
Haskell-centric; this skill translates it into idiomatic Zig: comptime duck
typing instead of typeclasses, tagged unions instead of GADTs, arenas instead
of garbage collection, `std.Random` + `test` blocks instead of QuickCheck.

## Reference files — read before designing

| File | Read when |
|---|---|
| `references/methodology.md` | Always, before Phase 1. The design process: constructors/combinators/observations, deriving laws, what makes a good algebra, law discovery. |
| `references/zig-idioms.md` | Always, before writing any Zig. Comptime contracts, arena ownership, PRNG generators, shrinking, **version-drift pitfalls**. |
| `references/algebra-catalog.md` | During Phase 1/3 to identify which structure the domain forms and which law set to test. |
| `references/canvas_algebra.zig` | As the gold-standard worked example (compile-verified, all laws pass). Mirror its file layout. |
| `assets/algebra_template.zig` | As the starting skeleton for a new domain (compile-verified; adapt, don't rewrite from scratch). |

## Non-negotiable doctrine

These rules exist because violating any of them produces code that *looks*
algebraic but fails its own verification suite:

1. **Laws are observational, never structural.** `overlay(empty(), x) == x`
   holds in the *denotation*, not in AST shape — an `.overlay` node is never
   structurally equal to a `.fill` node. The signature must include an
   observation into a semantic domain (`rasterize`, `denote`, `run`), and
   `eql` must compare denotations. Structural equality on the initial encoding
   is only ever an *optimization*, and only after proving it equivalent.
2. **Every algebra ships with at least two interpretations** — an obviously
   correct initial encoding (tagged-union AST + interpreter) and the efficient
   final encoding — plus a **homomorphism test** proving they denote the same
   algebra on random terms.
3. **Constructors that allocate take an arena and document build-observe-drop
   ownership.** No per-node `deinit`; the caller owns the arena. Tests wrap
   each iteration in `std.heap.ArenaAllocator` so `std.testing.allocator`
   proves leak-freedom.
4. **Exhaustive switches.** No `_` or `else` arm over a domain's tagged union.
   Adding a variant must break every interpreter at compile time.
5. **Comptime contracts diagnose, not gatekeep.** The signature check emits a
   named `@compileError` per missing/misshapen decl (see idioms file), never a
   bare `bool` the caller might ignore.
6. **No hidden state.** Combinators are pure value → value functions; effects
   live only in interpretations, at the edge.
7. **Verify with the actual toolchain before delivering.** Zig's std churns
   between versions. Run `zig version`, then `zig test` (or
   `scripts/run_zig_tests.sh`, which falls back to `pip install ziglang`).
   Never deliver Zig code you haven't compiled.

## Workflow

### Phase 0 — Scope the domain

Ask (or infer from context): what are the atomic things, what combines them,
and what do users ultimately *extract* from them? Write these three lists in
plain language before any code. If the user has existing code, identify its
implicit algebra first: which functions construct, which combine, which
observe.

### Phase 1 — Design the algebra on paper (no Zig yet)

Follow `references/methodology.md`. Deliverables, as comments or a short
design note:

1. **Signature** — types + operations in type-equation form, e.g.
   `empty : () -> Canvas`, `overlay : (Canvas, Canvas) -> Canvas`,
   `rasterize : Canvas -> Raster`.
   Classify each as constructor / combinator / observation.
2. **Semantic domain** — what a value *means*, stated as a (possibly
   tabulated) function, e.g. `Canvas ≙ (x, y) -> ?Pixel`. Choose observations
   first; the domain is whatever the observations jointly see. This is the
   single most important design decision.
3. **Laws** — for every pair of operations, ask "what equation relates them
   under the observation?" Use the catalog to spot the structure (monoid,
   semilattice, semiring, ...). Every combinator must appear in at least one
   law; a law-free operation is a design smell (it's unconstrained, hence
   probably wrong or leaky).
4. **Quality check** — closure (combinators total over the type), no
   privileged constructors, orthogonality, and the generalization test from
   the methodology file.

Present the signature + laws to the user for confirmation when the domain came
from them; laws are requirements in disguise and cheap to change now.

### Phase 2 — Encode signature + semantic domain in Zig

Start from `assets/algebra_template.zig`. Produce, in this order, in one file
(split into files only past ~500 lines):

1. Value types (`Pixel`-like payloads) and the **semantic domain type**
   (`Raster`-like), with its own `eql`.
2. `requireXAlgebra(comptime T: type)` comptime contract (idioms file has the
   pattern) checking decl presence *and* function shapes.

### Phase 3 — Initial encoding + interpreter

Tagged union mirroring the constructors/combinators one-to-one; recursive
positions are `*const Self` allocated from a caller-supplied arena. The
interpreter (`rasterize`/`denote`) is an exhaustive `switch` folding into the
semantic domain. `eql` = interpret both sides, compare denotations. This
encoding is *free* — it cannot be wrong, which is exactly why it exists: it is
the oracle the efficient implementation is tested against.

### Phase 4 — Laws as property-based tests

Follow the generator patterns in `references/zig-idioms.md`:

- One generator per algebra, built from the algebra's **own constructors**,
  depth-bounded, driven by `std.Random.DefaultPrng` with a **fixed seed**
  (reproducibility) — and echo seed + depth on failure.
- One `verifyXLaws(comptime Impl, gpa, cfg)` function generic over the
  implementation, asserting every law from Phase 1 on ~200 random terms,
  arena-per-iteration.
- A named `test` block per implementation, plus a **doctrine-guard test**
  demonstrating a structurally-distinct-but-observationally-equal pair (locks
  in rule 1 against future regressions).

Run the suite now, against the initial encoding only. Failures at this stage
mean the *laws* are wrong (or the semantic domain is), not the code — go back
to Phase 1. This loop is the whole point of ADD: debugging the design while
it's still cheap.

### Phase 5 — Derive the efficient final encoding

Derive the representation from the semantic domain itself (methodology file,
"Deriving Implementations"): if the denotation is a function, tabulate it; if
laws let terms normalize, store the normal form. Implement the same signature
computing results directly, then add:

- the same `verifyXLaws` test against the final encoding;
- the **homomorphism test**: identically-seeded twin generators build the same
  term in both encodings; their denotations must agree (pattern in
  `canvas_algebra.zig`).

Optimizations from here on are algebraic rewrites (justified by laws), each
guarded by the existing suite.

### Phase 6 — Verify and deliver

`scripts/run_zig_tests.sh <files...>` — every test green, zero leaks, and the
negative case checked (a deliberately broken impl must fail the comptime
contract with a readable error). Deliver: the module file(s), a short design
note stating signature + laws + identified structure, and how to run tests.

## Output structure

Every generated module follows this layout (see `canvas_algebra.zig`):

```
//! <Domain> algebra — Algebra-Driven Design
// PART 1: SIGNATURE        — value types, semantic-domain type, comptime contract
// PART 2: SEMANTIC DOMAIN  — denotation + its eql
// PART 3a: INITIAL ENCODING — tagged-union AST + interpreter (the oracle)
// PART 3b: FINAL ENCODING   — direct efficient implementation
// PART 4: LAWS             — generator, verifyLaws(Impl), homomorphism, tests
```

## Anti-patterns to reject on sight

- Structural `eql` used to judge laws (rule 1) — the original sin of naive ADD
  ports; it makes correct implementations fail their own suite.
- `@hasDecl`-only "interfaces" returning `bool` — silent, shape-blind.
- `else`/`_` arms over domain unions; `catch unreachable` on arena allocation
  in library code (propagate `error.OutOfMemory`).
- Laws tested on one hand-picked example instead of generated terms.
- A single interpretation with no oracle to test against.
- Combinators that mutate an operand or share mutable state between terms.
- Unverified code: if `zig test` wasn't run, the task is not done.
