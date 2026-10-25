# Catalog: algebraic properties & structures

The book's "Common Algebraic Components" chapter as a working checklist.
Use it in two directions: (a) given laws discovered from the domain, name the
structure and import its remaining laws; (b) given a structure hunch, test all
its laws. Property names below are the exact strings to use in `expectLaw`
calls so failures read cleanly.

## Part A — Properties (single equations)

For a binary combinator `op`, elements `e`/`z`, unary `f`. All equalities are
observational (`Impl.eql`).

| Property | Equation | Typical Zig test line |
|---|---|---|
| associativity | `op(op(x,y),z) == op(x,op(y,z))` | generate x,y,z; compare both groupings |
| commutativity | `op(x,y) == op(y,x)` | |
| left identity | `op(e,x) == x` | `e = Impl.empty()` |
| right identity | `op(x,e) == x` | |
| idempotence | `op(x,x) == x` | |
| left annihilation | `op(z,x) == z` | z = "zero"/absorbing element |
| right annihilation | `op(x,z) == z` | |
| involution | `f(f(x)) == x` | negation, reversal |
| periodicity (order n) | `fⁿ(x) == x` | e.g. `cw⁴ == id` for quarter-turns |
| distributivity (left) | `f(op(x,y)) == op(f(x),f(y))` — or `mul(a,add(x,y)) == add(mul(a,x),mul(a,y))` | unary-over-binary and binary-over-binary forms |
| absorption | `meet(x, join(x,y)) == x` | lattice pairs |
| invertibility | `op(x, inv(x)) == e` | rare in domain algebras; needs true inverses |
| congruence / structure preservation | `denote(op_A(x,y)) == op_B(denote(x),denote(y))` | the homomorphism test |
| monotonicity (ordered domains) | `x ≤ y ⇒ f(x) ≤ f(y)` | needs an observable order |

Payload caveat: properties must hold **in the semantic domain**, not the
payload — e.g. float payloads break associativity of `+` at the bit level;
either quantify the law over the domain's actual equality or choose integral
payloads for the denotation.

## Part B — Structures (bundles of properties)

Test the whole bundle when the domain matches; each row lists the *complete*
law set for its `verify<Structure>Laws` function.

| Structure | Operations | Laws | Domain smells that indicate it |
|---|---|---|---|
| Semigroup | `op` | assoc | "combining two of these gives another one" |
| Monoid | `op`, `e` | assoc + left/right identity | there's a natural "nothing" value (empty canvas, no-op patch, empty log) |
| Commutative monoid | + comm | order of combination can't matter (sets of tags, counters) |
| Idempotent monoid | + idem | re-applying is harmless (top-wins overlay, CSS-like override) |
| Bounded semilattice | `op`, `e` | assoc + comm + idem + identity | max/min/union-like merging: severities, permissions-union, CRDT joins |
| Group | monoid + `inv` | + invertibility | undo exists exactly (rare; reversible transforms) |
| Semiring | `add`,`zero`,`mul`,`one` | (add: comm monoid) + (mul: monoid) + mul distributes over add + zero annihilates mul | two interacting combinators: choice+sequence (paths, parsers, tropical costs), any/all policy composition |
| Lattice | `meet`,`join` | both bounded semilattices + absorption | dual merge modes over the same values (most-permissive vs least-permissive) |
| Module/scaling action | monoid + `scale` | scale distributes over op; `scale(1,x)==x`; `scale(a,scale(b,x))==scale(a*b,x)` | "apply k times", weighting, opacity |
| Monoid action | monoid M, set S, `act` | `act(e,s)==s`; `act(op(a,b),s)==act(a,act(b,s))` | commands applied to state; event sourcing |
| Functor-like (Zig) | `map` on a generic module | `map(id)==id`; `map(f∘g)==map(f)∘map(g)` | payload-polymorphic containers/regions; use `fn (comptime T: type) type` modules |

Recognition workflow: after the pairwise law grid (methodology §4), match the
discovered laws against the table top-down; the first full match names your
structure. A *near*-match is a design prompt: either a law is genuinely absent
(document why) or the generalization gate should fire.

## Part C — Structure ⇒ implementation tricks

Knowing the structure buys derived implementations (methodology §7):

- **Monoid** ⇒ fold-based final encoding; parallel/incremental aggregation is
  sound by associativity (chunk, combine, cache partial results).
- **Commutative + idempotent (semilattice)** ⇒ canonical form = sorted
  deduplicated set; structural equality on the canonical form becomes a valid
  *optimization* of observational equality (prove with a property test:
  `canonEql(x,y) == Impl.eql(x,y)` on random pairs).
- **Annihilator** ⇒ short-circuit evaluation in the interpreter (deny-wins
  policies stop at first deny).
- **Semiring** ⇒ matrix/graph algorithms (shortest path = tropical semiring
  fold) and distributive-law-driven normal forms (sum-of-products).
- **Action** ⇒ store the monoid element, apply lazily in one pass at
  observation time (defers work, enables batching).
- **Periodic combinator (order n)** ⇒ store exponent mod n instead of nesting
  (quarter-turn rotations become a 2-bit counter).

Each trick is an algebraic rewrite: implement it, cite the licensing law in a
comment, and keep the oracle homomorphism test — that's the entire safety
argument.
