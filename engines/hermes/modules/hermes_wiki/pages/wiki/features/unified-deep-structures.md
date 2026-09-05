---
id: hermes-unified-deep-structures
status: draft
type: claim
ktype: moc
maturity: incubating
domain: formal_verification
topics: [structures, sheaf, quasi-metric, bisimulation, verification]
created: 2026-08-09
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Unified deep structures — nine structures the design has not yet named

#feature #src-unified #area-algebra #cov-design

**Nothing in this document is implemented.** Every structure below is a
*proposal*: a mathematical object, the place in the existing design it would
occupy, an OCaml signature sketch, laws stated as equations, and the rung of the
verification ladder that would discharge each one. Where a solver is named, the
evidence is **bounded-model** and says so.

`[[Unified functional atlas]]` §0 indexes S1–S26. This document extends that
index as **S27–S35** and renumbers nothing. It is typed `claim` because each
structure is falsifiable in the same way: if its laws cannot be discharged by a
tool the harness actually runs, it does not belong here.

The prize the pass was searching for is stated up front, because one structure
won it: **S27 makes seven laws that are currently stated and tested separately
into corollaries of two equations.** That is the whole argument for doing it
first.

## 1. The five criteria, and how to measure each one

A structure earns its place by laws a tool can discharge. These are the
questions asked of every candidate, each with a proxy that produces a number
rather than an opinion.

| Criterion | What it means | Measurable proxy | Pass mark |
|---|---|---|---|
| **Beauty** | economy and inevitability — few primitives, many consequences; dualities made explicit; laws that read as identities | **consequence ratio** ρ = (existing laws made corollaries + new laws stated) ÷ (new primitives introduced); plus "is a duality named?" | ρ ≥ 4 |
| **Flexibility** | extension without modification — a new capability is a new algebra or instance along a stated seam | **seam width** σ = number of *existing* modules that must be edited to add the next instance, measured against a named extension exercise | σ = 0 |
| **Utility** | kills a defect class or yields a user-visible capability | names the `HW.*` row it serves or adds; **promotion count** Δ = number of currently-`Declared` (rung 0) laws it raises | Δ ≥ 1 |
| **Navigability** | the corpus as a *space* — distances, neighbourhoods, charts, reading paths; laws that bound how lost a reader can be | **lostness bound**: ecc(index) = worst-case click depth; orphans = count of pages at infinite distance from the index; efficiency = expected click depth ÷ source-coding optimum | at least one becomes computable, and none gets worse |
| **Verifiability** | 2–5 laws as equations, each with a discharging tool from the ladder we have | **floor rank** = the minimum `Formal_coverage.rank` over the structure's laws; **mutation yield** = mutants killed ÷ mutants written | floor ≥ 2, yield = 1.0, ≥ 3 mutants |

The ladder is the one in `[[Unified functional algebra]]` §0 and nothing else:
rung 5 OCaml types (machine-checked), rung 4 smtml + Z3 in process
(bounded-model solver proofs), rung 3 the render-baseline differential, rung 2
property tests with mutation legs, rung 1 Gospel contracts on the `.mli`, rung 0
declared. Quint is available for temporal properties and is currently unused —
S32 uses it.

**Scoring convention.** Each structure carries a 1–5 score per criterion. A 5 on
Verifiability requires the *headline* law to sit at rung 5, i.e. to be true by
construction rather than by test. A 5 on Navigability requires the structure to
produce one of the three lostness numbers directly. A 1 is honest: several
structures below score 1 on Navigability because they have nothing to do with
reading, and pretending otherwise would make the criterion useless.

**Bounded-model honesty, stated once.** Every rung-4 claim below is an `unsat`
result over a *bounded encoding* — a fixed graph size, a fixed lattice height, a
fixed alphabet. That is real evidence, it is stronger than a property test
because it quantifies over all values in the encoding, and it is **not** a proof
for all inputs. `Formal_coverage` records such a claim as `Solver_proved` with
the bound named, never as `Machine_checked`.

## 2. The structure index, continued

| # | Structure | Where it lives | What it buys |
|---|---|---|---|
| S27 | **Sheaf / descent on the dependency site** | `render`, `Transclude`, the build | seven existing laws become corollaries of two equations; the read-set enters the type |
| S28 | **Lawvere quasi-metric space** (category enriched over `[0,∞]`) | `Graph`, `Nav`, `Metrics` | navigability becomes a number with a bound; orphan = infinite distance |
| S29 | **Subdominant ultrametric / dendrogram** | `Metrics.communities`, MoCs | community determinism becomes a *theorem*, not a constraint bolted onto label propagation |
| S30 | **Dissection ⃗∂F and the patch groupoid** | `Ast`, `Differential`, history | a drift verdict carries its own explanation; the zipper S16 falls out as a special case |
| S31 | **Coalgebraic bisimulation** | `Wiki_ast` vs the line-machine oracle | the oracle equivalence stops being corpus-bounded and starts quantifying over all inputs |
| S32 | **Trace monoid (Mazurkiewicz)** | the build scheduler | `build_par = build` becomes a theorem about an independence relation; Quint finally has a target |
| S33 | **Functor from the commit poset to the patch groupoid** | as-of query, timeline | history gets the same treatment as space: composition of deltas is functoriality |
| S34 | **Information source + prefix code** | `Nav`, `Tags`, `Metrics` | a *lower bound* on how good any index can be; a tag that carries no information is diagnosable |
| S35 | **Closure operator / formal concept lattice** | `Query`, `Tags` | query equality becomes decidable by comparing bytes; S21 is the tag-only special case |
| S36–S42 | **continued** — the second pass's seven structures | `[[Unified system synthesis]]` | the index continues there, renumbering nothing here |

Nine structures, three seams (space, time, meaning), and two of them — S29 and
S33 — are dependents that exist only because S28 and S30 do.

## 3. S27 · The sheaf of renders on the dependency site

### Identity

A **local morphism of presheaves on a site with descent**. The site is the
poset of sub-corpora ordered by inclusion, with the coverage whose covering
families of a document `d` are the finite sets `deps d` of documents that
`render d` may observe. The observable presheaf assigns to a sub-corpus the
partial map from slug to observable; `render` is a morphism into the section
presheaf, and it is a **local** morphism: it factors through restriction to the
cover.

**Precision, and where the abuse would be.** The observable presheaf is a sheaf
trivially, because the environment is a function of the corpus and compatibility
on overlaps is therefore automatic. So calling the *structure* a sheaf is only
interesting once the site is named: the mathematical content is not the sheaf
axiom on observables but the two facts about `render` — **separatedness** (it
sees only its cover) and **gluing** (a compatible family of local sections
determines the global one, uniquely and order-independently). Descent is the
right word; "sheaf" is shorthand and this paragraph is the receipt.

### Where it lives

E1 Corpus, E2 Document, E10 Block, E13 Link; R5, R13 (transclusion), R21 (the
Store comonad's `extend` is the *unrestricted* version of the same idea); S5
paramorphism, S10 State (the slugger), S12 Store comonad, S16 zipper. In the
register: HW.10.1.1 incremental, HW.10.1.2 dependency tracking, HW.10.1.3
parallel — all three currently rung 0 `Declared`.

### Signature sketch

```ocaml
module Cover : sig
  type t
  val empty : t
  val of_list : Id.page Id.t list -> t
  val union : t -> t -> t
  val inter : t -> t -> t
  val mem : t -> Id.page Id.t -> bool
  val elements : t -> Id.page Id.t list        (* sorted: determinism *)
end

module Observable : sig
  type t = {
    exists  : bool;
    title   : string;
    anchors : Id.anchor Id.t list;
    blocks  : (Id.block Id.t * Ast.t) list;    (* transclusion targets only *)
  }
end

module Env : sig
  type t
  type view                                     (* ABSTRACT *)
  val of_corpus : Corpus.t -> t
  val restrict  : t -> Cover.t -> view          (* the ONLY producer of a view *)
  val narrow    : view -> Cover.t -> view
  val observe   : view -> Id.page Id.t -> Observable.t option
  val cover_of  : view -> Cover.t
  (* and deliberately NO  val widen : view -> t  *)
end

val deps    : Document.t -> Cover.t
val section : Env.view -> Document.t -> Section.t
val glue    : (Id.page Id.t * Section.t) list -> Section.t
```

The load-bearing move is that `Env.view` is abstract with `restrict` as its only
producer and no widening operation. A render that reads outside its cover cannot
be written; it can only be *enabled* by adding `widen` to the `.mli`, which is a
visible interface change rather than a silent one.

### Laws

- **L27.1 restriction (the headline)**
  `section (Env.restrict e (deps d)) d = section (Env.restrict e all) d`
- **L27.2 functoriality**
  `narrow (narrow v u) w = narrow v (Cover.inter u w)` and `narrow v all = v`
- **L27.3 gluing is a monoid**
  `glue [glue xs; glue ys] = glue (xs @ ys)` and `glue [] = Section.empty`
- **L27.4 descent (incremental equals cold)**
  for `e'` differing from `e` only at `x`:
  `rebuild ~previous:(build e C) e' ~changed:{x} C = build e' C`, byte for byte
- **L27.5 tightness**
  for every `y` in `deps d` there exist `e`, `e'` differing only at `y` with
  `section (restrict e (deps d)) d ≠ section (restrict e' (deps d)) d`

L27.5 is the anti-cheat law: without it, `deps d = all` satisfies everything
else and buys nothing.

### The seven corollaries

| Existing law | Where stated | Why it follows |
|---|---|---|
| slugger locality: `anchors(render_single d) = anchors(render_corpus d)` | algebra A4 | L27.1 with `e` the whole corpus and `deps d` the singleton |
| patch locality: patching one block leaves every other byte-identical | algebra B4 | other documents do not have `d`'s blocks in their cover unless they transclude them |
| transclusion denotation: `⟦![[x]]⟧ = ⟦body(x)⟧` | algebra C3 | the embed *is* the restriction map into `x`'s section |
| `reads(render d) ⊆ deps(d)` | algebra G | this is separatedness, verbatim |
| `incremental = cold` | algebra G | L27.4 |
| `build_par = build` at every worker count | algebra G | L27.3: gluing is associative, so any partition glues alike |
| single-file export equals the served pages | feature set §6 | the global section is the export |

Seven laws, two equations, one new primitive (the abstract `view`). Consequence
ratio ρ = 7 ÷ 1 for the corollaries alone; counting the five new laws, ρ = 12.
The duality made explicit: **space (S27) and time (S33) are the same sheaf
condition on two different sites.**

### Discharge

| Law | Rung | Tool |
|---|---|---|
| L27.1 | **5 Machine_checked** | the abstract `Env.view` with no widening: violation does not compile |
| L27.2 | 5 / 2 | type for `narrow`'s signature; property test for the intersection identity |
| L27.3 | 3 + 2 | render baseline (single-file export vs concatenated page bytes) + associativity property over random partitions |
| L27.4 | 3 + 2 | differential over the 227-document corpus + property test with mutants |
| L27.5 | 2 | property test that searches for a witness per cover element; a dead element fails |
| cocycle on bounded covers | **4 Solver_proved** | smtml over covers of size ≤ 6 — *bounded, evidence not proof* |

### Scorecard

| Criterion | Score | Justification |
|---|---|---|
| Beauty | 5 | ρ = 12; two equations absorb seven separately-tested laws; the space/time duality is named |
| Flexibility | 5 | σ = 0: a new dependency kind is a new cover element and a new render target is a new section algebra; neither touches the parser or the carrier |
| Utility | 5 | Δ = 4 rung-0 laws promoted; kills the stale-incremental-build class, whose signature is silent wrongness (criticality 5); adds HW.10.1.4 |
| Navigability | 3 | indirect — covers are charts and the export is the global chart, but it bounds no reader distance |
| Verifiability | 5 | headline law is rung 5 by construction; five mutants, all with distinct killers (§7) |

### Subsumes or strengthens

Strengthens **S5** (the paramorphism's cycle detection becomes a statement about
covers), **S10** (locality is now derived), **S12** (`extend` is the unrestricted
special case), **S16** (patch locality is a corollary). It also promotes the
typing rule **T4** — "purity except at three leaves" — from prose to a type, by
putting the read-set in the signature.

## 4. S28 · The corpus as a Lawvere quasi-metric space

### Identity

A **category enriched over the monoidal poset `([0,∞], ≥, +, 0)`** — a *Lawvere
metric space*. `d a b` is the least cost of a reading path from `a` to `b`.
Two axioms only: `d a a = 0` (identity) and `d a c ≤ d a b + d b c`
(composition). Symmetry is **not** an axiom, and its absence is the point: links
are directed, so "how far is the reader from x" is genuinely not "how far is x
from the reader". Nor does `d a b = 0` force `a = b`; the failure of separation
is exactly the structural-duplicate notice in L28.5.

### Where it lives

E13 Link, E15 Typed edge, E17 Nav node; R7, R8, R15; S20 Kleene ascent (the
distance is the least fixed point of a min-plus relaxation), S22 transpose, S23
partition, S24 total order. Register: HW.4.2.1 PageRank, HW.4.2.4 structural
holes, HW.6.3.4 PPR ranking, HW.6.4.2 sidebar, plus the unreachable-node
diagnostic.

### Signature sketch

```ocaml
module Dist : sig
  type t = Fin of int | Inf                     (* EXACT: no floats, ever *)
  val zero : t
  val add : t -> t -> t                         (* the tensor of the enrichment *)
  val min : t -> t -> t                         (* the enrichment's join *)
  val compare : t -> t -> int
end

module Space : sig
  type t
  val of_graph : Graph.t -> weight:(Rel.t -> Dist.t) -> t
  val op : t -> t                               (* the OPPOSITE space: d_op a b = d b a *)
  val d : t -> Id.page Id.t -> Id.page Id.t -> Dist.t
  val ball : t -> Id.page Id.t -> radius:Dist.t -> Id.page Id.t list
  val ecc : t -> Id.page Id.t -> Dist.t
  val profile : t -> Id.page Id.t -> (Id.page Id.t * Dist.t) list   (* Yoneda *)
  val sym : t -> t                              (* max of the two directions *)
end
```

### Laws

- **L28.1 identity** `d s a a = 0`
- **L28.2 composition** `d s a c ≤ Dist.add (d s a b) (d s b c)`
- **L28.3 reachability** `d s root p = Inf` if and only if `p` is unreachable —
  the orphan diagnostic *is* an infinite distance
- **L28.4 monotone under link addition** `d (add_edge s e) a b ≤ d s a b` —
  adding a link never makes anything further away, so `ecc index` may not
  increase across a commit that only adds links (a ratchet)
- **L28.5 Yoneda** `profile s a = profile s b` implies `a` and `b` are
  isometric; report as a structural-duplicate notice, never a defect
- **L28.6 symmetrisation** `sym s` is a genuine metric: with
  `s(a,b) = max (d a b) (d b a)`, the triangle inequality follows from L28.2 in
  both directions — the lemma S29 needs

### Discharge

| Law | Rung | Tool |
|---|---|---|
| determinism of the carrier | **5 Machine_checked** | `Dist.t` is `Fin of int` or `Inf`; no float can enter the pinned path |
| L28.1, L28.2, L28.6 | **4 Solver_proved** | smtml over graphs of ≤ 8 nodes; min-plus is linear-arithmetic friendly — *bounded* |
| L28.3 | 2 + 3 | property test, cross-checked against the existing unreachable diagnostic on the real corpus; if they ever disagree, both are wrong |
| L28.4 | 2 | property test plus a mutant that stops relaxing after one pass |
| L28.5 | 2 | property test |

### Scorecard

| Criterion | Score | Justification |
|---|---|---|
| Beauty | 5 | one primitive `d`; orphan, neighbourhood, reading path, eccentricity and similarity all become derived; the duality is explicit — `Space.op` is the transpose S22, so backlinks are the opposite enriched category |
| Flexibility | 4 | σ = 0 for a new edge weight or a new space (tag distance, co-citation distance) — but `Graph` gains one exported constructor |
| Utility | 4 | Δ = 1; adds a navigability-budget row; kills "a reorganisation silently lengthened every reading path", which today is undetectable |
| Navigability | 5 | this *is* the criterion: `ecc index` and the orphan count are the lostness bound, both integers, both ratchetable |
| Verifiability | 4 | floor rung 2; headline laws at rung 4 bounded; the carrier's exactness is rung 5 |

### On the atlas's rejection of tropical algebra

`[[Unified functional atlas]]` §10 rejects "semiring / tropical algebra" on the
grounds that betweenness needs counts and BFS, not a generalisation instantiated
once. **That rejection stands and this is not it.** S28 does not reimplement
Brandes over a semiring; it uses min-plus as the *enrichment base* that makes
navigability laws statable at all, and it instantiates twice — min-plus for
distance and its Boolean sub-semiring for reachability. The triangle inequality,
monotonicity under edge addition and the eccentricity budget are laws that
BFS-as-code cannot state, which is the difference between a generalisation and a
structure.

### Subsumes or strengthens

Strengthens **S22** (transpose is `Space.op`, and `d_op` makes the duality an
equation rather than a naming convention), **S23**, **S24**. It is the
precondition for S29.

## 5. S29 · The subdominant ultrametric, and determinism as a theorem

### Identity

An **ultrametric**: `u a c ≤ max (u a b) (u b c)`. The classical correspondence
is a bijection between ultrametrics on a finite set and **dendrograms**
(hierarchical clusterings), and single linkage computes the *maximal subdominant
ultrametric* below a given metric — which is **unique**. So the community
structure is not an algorithm's output that we must force to be deterministic;
it is a unique object determined by the distance.

### Where it lives

E6 Group, R3 kernel, S23 partition, S24 total order. Register: HW.4.2.2
communities, HW.4.5.2 local graph, HW.4.6.2 community-grounded MoCs, HW.4.6.3
rollup. It directly replaces the "constrained label propagation" choice in
`[[Unified feature set]]` §4, which exists only because LPA is non-deterministic
by construction.

### Signature sketch

```ocaml
module Ultra : sig
  type t
  val subdominant : Space.t -> t                (* single linkage over Space.sym *)
  val u : t -> Id.page Id.t -> Id.page Id.t -> Dist.t
  val cut : t -> at:Dist.t -> (Id.page Id.t * Community.t) list
  val dendrogram : t -> Community.tree
  val merges : t -> (Dist.t * Community.t * Community.t) list   (* sorted, total *)
end
```

### Laws

- **L29.1 ultrametric** `u t a c ≤ max (u t a b) (u t b c)`
- **L29.2 subdominance** `u t ≤ Space.sym s` pointwise, and `u t` is the
  greatest such ultrametric — hence unique, hence deterministic with no tiebreak
- **L29.3 partition at every cut** `cut t r` is disjoint and covering for every
  `r` — S23, at every radius at once, for free
- **L29.4 refinement is monotone** `r ≤ r'` implies `cut t r` refines
  `cut t r'` — zooming out only merges, never re-partitions
- **L29.5 permutation invariance** `cut (subdominant (shuffle g)) r
  = cut (subdominant g) r` — the register's determinism requirement, now a
  *corollary of L29.2* rather than a property bolted onto a labelling loop

### Discharge

| Law | Rung | Tool |
|---|---|---|
| L29.1 | **4 Solver_proved** | smtml over distance matrices of ≤ 6 points — *bounded* |
| L29.2 | 1 + 2 | Gospel on the `.mli` states maximality; property test compares against brute-force enumeration of all ultrametrics below `sym` on ≤ 5 points |
| L29.3 | 2 | property test: disjoint and covering at every merge height |
| L29.4 | 2 | property test plus a mutant using complete linkage, which breaks refinement |
| L29.5 | 2 | property test with shuffled adjacency — the test the register already planned for LPA, now expected to pass by theorem |

### Scorecard

| Criterion | Score | Justification |
|---|---|---|
| Beauty | 5 | determinism stops being a patch and becomes a theorem; the whole dendrogram replaces the arbitrary choice of one threshold |
| Flexibility | 4 | σ = 0 for a new linkage or a new cut radius; the radius is a parameter, not a rebuild |
| Utility | 4 | Δ = 1; kills "the community view reshuffled and the baseline drifted for no reason", which is a false-drift class that erodes trust in the gate |
| Navigability | 5 | nested neighbourhoods are zoomable charts: one structure serves the local graph, the MoC and the sidebar grouping |
| Verifiability | 4 | floor rung 2; L29.1 at rung 4 bounded; L29.2 is where Gospel earns its keep |

### Subsumes or strengthens

Subsumes **S23** in the graph setting (a partition per radius rather than one),
strengthens **S24**, and depends on **S28**.

## 6. S30 · Dissection ⃗∂F and the patch groupoid

### Identity

McBride's **dissection**: for a polynomial functor `F`, `⃗∂F` is `F` with a hole,
values already processed ("clowns") to the left and values not yet processed
("jokers") to the right. The zipper S16 is `∂F`, the special case where clowns
and jokers have the same type. Alongside it, documents and edits form a
**groupoid**: objects are ASTs, arrows are invertible patches, composition is
patch composition, and `diff a b` is the arrow from `a` to `b`.

### Where it lives

E10 Block, E12 Block anchor, E23 Digest; R18; S1 initial algebra, S6 traverse,
S16 zipper. Register: HW.8.2.3 render baseline differential, HW.8.1.1 page
history, and the `Differential.verdict` type.

### Signature sketch

```ocaml
module Dissect : sig
  type ('c, 'j) t                               (* clowns to the left, jokers right *)
  val start : 'j Ast.layer -> (('c,'j) t * 'j, 'c Ast.layer) Either.t
  val step  : ('c,'j) t -> 'c -> (('c,'j) t * 'j, 'c Ast.layer) Either.t
end

module Patch : sig
  type t
  val id      : t
  val compose : t -> t -> t                     (* g after f *)
  val invert  : t -> t
  val diff    : Ast.t -> Ast.t -> t
  val apply   : t -> Ast.t -> (Ast.t, Conflict.t) result
  val touched : t -> Id.block Id.t list
  val bytes   : t -> string                     (* serialisable: P1 holds *)
end
```

`Dissect.step` is total by type — a traversal in progress is either still going
or finished, and "stuck" is unrepresentable. That is the rung-5 half.

### Laws

- **L30.1 fundamental theorem of patches** `apply (diff a b) a = Ok b`
- **L30.2 identity** `diff a a = id` and `apply id a = Ok a`
- **L30.3 groupoid** `apply (compose q p) = apply q ∘ apply p` where the right
  side is defined, and `compose (invert p) p = id`
- **L30.4 locality** every block whose id is not in `touched p` is byte-identical
  after `apply p` — S16's baseline law, now for arbitrary edits rather than one
- **L30.5 drift is typed** `Differential.Drifted` refines from a digest pair to
  a `Patch.t`, with `digest (render (apply p a)) = h_new` — a drift verdict that
  cannot produce such a patch is a **second, newly detectable defect class**

### Discharge

| Law | Rung | Tool |
|---|---|---|
| `Dissect.step` totality | **5 Machine_checked** | the `Either` return type; no stuck state exists |
| L30.1, L30.2, L30.3 | 2 | property tests over generated AST pairs, with mutants that drop an operation and that reverse composition order |
| L30.4 | **3 Differentially_tested** | render baseline before and after a synthetic patch, over the real corpus |
| L30.5 | 3 | the baseline recomputes the digest *from the patch*; an unexplainable drift now fails loudly instead of being reported as an opaque pair |

### Scorecard

| Criterion | Score | Justification |
|---|---|---|
| Beauty | 5 | the derivative you already have, one level up; S16 falls out by setting clowns = jokers, which is the cleanest subsumption in this document |
| Flexibility | 4 | σ = 0: a new block constructor gets its dissection from the same generic derivation the zipper uses |
| Utility | 5 | kills "the baseline says something changed and nobody can say what" — the harness's signature instrument becomes an explanation rather than a boolean |
| Navigability | 3 | history becomes navigable, but only along one axis |
| Verifiability | 4 | floor rung 2; L30.4 at rung 3 on the real corpus; the totality half at rung 5 |

### Subsumes or strengthens

**Subsumes S16** (`∂F` = `⃗∂F` with clowns = jokers). Strengthens the
differential family F3 and is the precondition for S33.

## 7. S31 · Coalgebraic bisimulation for the oracle equivalence

### Identity

Two **coalgebras** for one behaviour functor `B(X) = Out* × (In → X)`: the
line-machine oracle and the AST path. Observational equivalence is
**bisimilarity**, and exhibiting a bisimulation relation `R` closed under the
transition discharges it **by coinduction for every input**, not merely for the
pinned corpus.

**Why this is stateable at all:** `parse` is a hylomorphism (S4), so the
cata-after-ana can be presented as a single-pass machine. Without S4 there is no
streaming presentation of the AST path and no bisimulation to exhibit. One
existing structure is the precondition for a new one — which is the kind of
interlock this pass was looking for.

### Where it lives

E10 Block; R5; S1–S4. Register: HW.2.0.1, whose acceptance criterion is today
"admitted by observational equivalence to the streaming oracle over the whole
corpus" — rung 3, and corpus-bounded.

### Signature sketch

```ocaml
module Bisim : sig
  type oracle_state
  type ast_state
  type obs = Emit of string | Consume | Halt

  val init_oracle : oracle_state
  val init_ast    : ast_state
  val step_oracle : oracle_state -> char -> oracle_state * obs
  val step_ast    : ast_state    -> char -> ast_state    * obs

  val related : oracle_state -> ast_state -> bool          (* the candidate R *)
  val frontier : unit -> (oracle_state * ast_state) list   (* closure worklist *)
  val counterexample : unit -> string option               (* SHORTEST divergence *)
end
```

### Laws

- **L31.1 initial** `related init_oracle init_ast`
- **L31.2 output agreement** `related s t` implies
  `snd (step_oracle s c) = snd (step_ast t c)` for every `c`
- **L31.3 step closure** `related s t` implies
  `related (fst (step_oracle s c)) (fst (step_ast t c))` for every `c`
- **L31.4 coinduction** L31.1–L31.3 imply
  `render_line_machine = render_markdown` on **every** input
- **L31.5 minimal counterexample** if the closure fails, `counterexample ()`
  returns a shortest input on which the two disagree

### Discharge

| Law | Rung | Tool |
|---|---|---|
| L31.2, L31.3 | **4 Solver_proved** | smtml over the encoded state (mode plus bounded counters) and one symbolic character — *bounded encoding*, but quantifying over all characters at each step rather than over the pinned corpus |
| L31.4 | 1 Contracted | Gospel states the coinduction principle on the `.mli`; OCaml can check the premises, not the principle — said plainly |
| L31.1, L31.5 | 2 | property tests with mutants |
| non-vacuity | 3 | the existing corpus differential stays as the sanity leg, exactly as `test_smtml_lattice` keeps its sanity-SAT check |

### Scorecard

| Criterion | Score | Justification |
|---|---|---|
| Beauty | 5 | equivalence becomes a relation you exhibit rather than a corpus you hope is representative; the hylomorphism S4 is revealed as its precondition |
| Flexibility | 3 | σ = 0 for a new dialect rule, but the relation must be re-closed; that is real work, not a new instance |
| Utility | 5 | kills "oracle drift discovered at document 143 with a 4 KB diff"; a failure now names the *shortest* input that separates the two paths |
| Navigability | 1 | none, and pretending otherwise would devalue the criterion |
| Verifiability | 5 | headline laws at rung 4 bounded, with an honest rung-1 statement of the principle they feed and a rung-3 non-vacuity leg |

### Subsumes or strengthens

Strengthens **B1**, the algebra's most load-bearing law, and retires the phrase
"admitted by observational equivalence over the corpus" in favour of a proof
obligation with a shape. Note that `[[Unified functional atlas]]` §10 rejects
coinductive `ν` and streams *for the corpus*, on determinism grounds — that
rejection is untouched, because this is coinduction over a parser's state
machine, not over the set of documents.

## 8. S32 · The trace monoid for the build

### Identity

A **trace monoid** `M(Σ, I)`: the free monoid on build tasks, quotiented by
`ab = ba` for every independent pair. Mazurkiewicz's theorem says all
linearisations of a trace are the same element — so a parallel schedule and a
sequential one are equal *as elements*, and `build_par = build` stops being a
test at three worker counts and becomes a theorem about the independence
relation.

### Where it lives

Follows S27: two tasks are independent exactly when their covers and their
output paths are disjoint. Register: HW.10.1.1, HW.10.1.2, HW.10.1.3 — three
rung-0 `Declared` laws. Tool: **Quint**, which
`[[Unified implementation approach]]` §7 records as available and unused, with
the build state machine named as its natural target.

### Signature sketch

```ocaml
module Task : sig
  type t
  val cover  : t -> Cover.t                     (* what it reads: from S27 *)
  val writes : t -> Out_path.t                  (* what it produces *)
end

module Trace : sig
  type t
  val indep : Task.t -> Task.t -> bool
  val of_schedule : Task.t list -> t            (* the quotient *)
  val equal : t -> t -> bool
  val linearise : t -> workers:int -> Task.t list list
end
```

### Laws

- **L32.1 independence** `indep` is symmetric and irreflexive
- **L32.2 commutation** `indep a b` implies
  `of_schedule (xs @ [a; b] @ ys) = of_schedule (xs @ [b; a] @ ys)`
- **L32.3 Mazurkiewicz** `Trace.equal (of_schedule s) (of_schedule s')` implies
  `run s = run s'` byte for byte — hence `build_par = build` at every worker
  count
- **L32.4 soundness of independence** `indep a b` implies
  `Cover.inter (cover a) (cover b) = Cover.empty` and `writes a ≠ writes b`
- **L32.5 no lost update** every serialisation writes each output exactly once

### Discharge

| Law | Rung | Tool |
|---|---|---|
| L32.1, L32.4 | **5 Machine_checked** | `indep` is *defined* as disjointness, so it cannot disagree with itself; symmetry and irreflexivity are properties of the definition |
| L32.3 | **Quint**, recorded as 4-equivalent | a temporal model of the scheduler, model-checked over bounded task sets and worker counts: all interleavings of an independent pair reach the same state — *bounded* |
| L32.2 | 2 | property test over random schedules |
| L32.5 | 2 | property test plus a mutant that declares two writers of one path independent |

### Scorecard

| Criterion | Score | Justification |
|---|---|---|
| Beauty | 4 | one relation explains three build laws; loses a point because the theorem is imported rather than derived here |
| Flexibility | 5 | σ = 0: a new task kind supplies `cover` and `writes` and the scheduler never changes |
| Utility | 5 | Δ = 3; kills the flaky-parallel-build class, whose defect signature is a byte diff that reproduces one run in ten |
| Navigability | 1 | none |
| Verifiability | 4 | floor rung 2; the headline at Quint over a bounded model; and it finally uses the tool the design admits it is not using |

### Subsumes or strengthens

Depends on **S27** (independence is cover disjointness). Strengthens the whole
Build family, which is currently the largest block of rung-0 laws in
`[[Unified functional algebra]]` §G.

## 9. S33 · History as a functor from the commit poset

### Identity

A **functor** `H` from the commit poset `(Commits, ≤)` into the patch groupoid
of S30: `H c` is the corpus at `c`, and `H (c ≤ c')` is the patch between them.
Functoriality is composition of deltas. Equivalently, the corpus is a presheaf
on the commit poset — a **sheaf in time**, where S27 is a sheaf in space. That
duality is the reason both are in this document.

### Where it lives

E23 Digest; R18; S30. Register: HW.6.6.1 as-of query (`as_of(c) =
build(checkout c)`), HW.6.6.2 timeline, HW.8.1.1 page history.

### Signature sketch

```ocaml
module History : sig
  type commit
  type ('a, 'b) le                              (* a proof that a <= b *)
  val le : commit -> commit -> (commit, commit) le option
  val at : commit -> Corpus.t
  val delta : ('a, 'b) le -> Patch.t            (* only comparable pairs *)
  val edges : ('a, 'b) le -> Edge_delta.t
end
```

`delta` takes the ordering witness, not two commits — so a diff across a fork
does not compile.

### Laws

- **L33.1 identity** `delta (refl c) = Patch.id`
- **L33.2 functoriality** `delta (trans p q) = Patch.compose (delta q) (delta p)`
- **L33.3 as-of soundness** `at c = build (checkout c)` — the existing HW.6.6.1
  law, now the object part of the functor
- **L33.4 timeline additivity** `edges` is additive along the poset:
  `edges (trans p q) = Edge_delta.add (edges p) (edges q)` in the free abelian
  group on edges
- **L33.5 no time travel** `le` is a partial order; an incomparable pair yields
  `None` and the diff is a named refusal, never a silent merge

### Discharge

| Law | Rung | Tool |
|---|---|---|
| L33.5 | **5 Machine_checked** | `delta` consumes the `le` witness; an incomparable diff is unrepresentable |
| L33.1, L33.2, L33.4 | 2 | property tests over real git history plus mutants that reverse composition order |
| L33.3 | **3 Differentially_tested** | check out a pinned commit, rebuild, compare bytes with the recorded corpus |

### Scorecard

| Criterion | Score | Justification |
|---|---|---|
| Beauty | 4 | space and time get one treatment; the duality with S27 is explicit; it borrows its groupoid rather than building one |
| Flexibility | 4 | σ = 0 for a new delta kind (edges, tags, anchors) — each is a functor into a different abelian group |
| Utility | 4 | serves HW.6.6.1 and HW.6.6.2 together; kills "the timeline and the as-of view disagree", which no current check would catch |
| Navigability | 4 | history becomes an axis with a distance — commit count is a metric, so S28's machinery applies unchanged |
| Verifiability | 3 | floor rung 2; one rung-5 law; the rest rest on git, which is evidence about a real history rather than about all histories |

### Subsumes or strengthens

Depends on **S30**. Strengthens HW.6.6.1, and generalises the existing
"edge-set delta, monotone in commit order" acceptance criterion into
functoriality, which is checkable in a way monotonicity alone is not.

## 10. S34 · The corpus as an information source, and navigation as a prefix code

### Identity

A **discrete probability space** over pages with weights `w` (PageRank, or
uniform), its **Shannon entropy** `H w`, and the observation that a navigation
tree is a **prefix code**: expected click depth `L = Σ w p · depth p` obeys the
source-coding bound `H w ≤ L` for every prefix tree, with an optimal tree within
one bit. Alongside it, **mutual information** `I(T; C)` between declared tags
`T` and derived communities `C` measures whether the authored ontology agrees
with the link structure.

This is the structure that gives the Navigability criterion an *optimum* rather
than only a bound: "our sidebar costs 1.4 times the theoretical minimum" is a
sentence no other structure here can produce.

### Where it lives

E16 Tag, E17 Nav node; R14; S21 Galois, S23 partition. Register: HW.6.4.2
sidebar, HW.4.1.7 nested tags, HW.4.2.2 communities. It also gives the ontology
§0 preference order ("derived outranks declared") a measurement: `I(declared;
derived)` is exactly how much the declared axis knows about the derived one.

### Signature sketch

```ocaml
module Info : sig
  type dist                                     (* exact rationals; no floats *)
  val weights : Corpus.t -> dist
  val entropy : dist -> Q.t                     (* bits, to a stated precision *)
  val expected_depth : Nav.t -> dist -> Q.t
  val mutual :
    (Id.page Id.t -> string) -> (Id.page Id.t -> string) -> dist -> Q.t
  val redundant_tags : Corpus.t -> (Tag.t * Q.t) list
end
```

### Laws

- **L34.1 non-negativity** `entropy w ≥ 0` and `mutual f g w ≥ 0`
- **L34.2 symmetry** `mutual f g w = mutual g f w`
- **L34.3 source-coding bound** `expected_depth nav w ≥ entropy w` for every
  prefix navigation tree — a *lower bound on how good any index can be*
- **L34.4 refinement** if `C'` refines `C` then
  `mutual t c' w ≥ mutual t c w` — which is exactly S29's L29.4 seen through
  information rather than through geometry
- **L34.5 redundancy diagnostic** `mutual (tag_of t) community w = 0` if and
  only if the tag is independent of the link structure; report as a notice

### Discharge

| Law | Rung | Tool |
|---|---|---|
| determinism | **5 Machine_checked** | exact rationals with a fixed summation order; no float enters the digest path |
| L34.1, L34.2 | **4 Solver_proved** | smtml over bounded distributions with denominators fixed — *bounded* |
| L34.3 | 2 + 1 | property test over generated trees and weightings; Gospel cites the source-coding theorem, which we instantiate rather than prove |
| L34.4 | 2 | property test plus a mutant that swaps a marginal |
| L34.5 | 2 | property test on synthetic corpora with a deliberately meaningless tag |

**Honest bound.** Entropy needs logarithms, and a logarithm is not exact. The
discipline: comparisons are performed on exact quantities wherever the law is an
ordering, precision is fixed and stated wherever it is not, and no
logarithm-derived value is ever admitted into a pinned digest. A structure whose
numbers cannot be pinned belongs in §11, and this one only escapes by keeping
its floats out of the gate.

### Scorecard

| Criterion | Score | Justification |
|---|---|---|
| Beauty | 4 | two classical theorems, one corpus; but it imports more than it derives |
| Flexibility | 4 | σ = 0: a new declared axis and a new derived axis are two functions passed to `mutual` |
| Utility | 4 | adds a navigation-efficiency row; kills "we introduced a tag vocabulary that carries no information", which is invisible today |
| Navigability | 5 | supplies the optimum against which the S28 lostness numbers are scored |
| Verifiability | 3 | the weakest of the nine: the classical theorems are cited, not proved here, and the numeric laws need a stated tolerance |

### Subsumes or strengthens

Strengthens **S21** and **S29** by giving their outputs a common currency, and
gives the ontology's declared-versus-derived preference order a measurement
instead of an argument.

## 11. S35 · The closure operator on queries, and query normal form

### Identity

The antitone pair `(eval, describe)` between condition sets and page sets is a
**Galois connection**; its composite `close = describe ∘ eval` is a **closure
operator** (extensive, monotone, idempotent), and its fixed points are the
**formal concepts**. The concept lattice is the query language's own lattice,
and `close q` is the canonical normal form of `q`.

`[[Unified functional atlas]]` S21 is the special case where the conditions are
tag memberships. This is the general form, and it is computable precisely
because `Query` is a GADT over closed field and operator sets (S25), so the
condition alphabet is finite — another place where an existing structure is the
precondition for a new one.

### Where it lives

E16 Tag, E18 Query; R14, R16; S21 Galois, S23 partition, S25 closed sums.
Register: the HW.5.* query family.

### Signature sketch

```ocaml
module Concept : sig
  type conds = Query.cond list
  val eval     : Corpus.t -> conds -> Id.page Id.t list
  val describe : Corpus.t -> Id.page Id.t list -> conds
  val close    : Corpus.t -> conds -> conds
  val lattice  : Corpus.t -> (conds * Id.page Id.t list) list
  val normal_form_digest : Corpus.t -> Query.t -> Digest.t
end
```

### Laws

- **L35.1 Galois** `eval c q ⊇ s` if and only if `q ⊆ describe c s`
- **L35.2 closure** `close c (close c q) = close c q`; `q ⊆ close c q`;
  `q ⊆ q'` implies `close c q ⊆ close c q'`
- **L35.3 denotation preserved** `eval c (close c q) = eval c q` — normalising a
  query never changes its rows, so rewriting a fence to normal form is safe
- **L35.4 canonicity** `eval c q = eval c q'` if and only if
  `close c q = close c q'` — two queries mean the same thing **iff** they
  normalise to the same bytes, so query equality is decidable by comparison
- **L35.5 the lattice is the fixed points** `lattice c` enumerates exactly the
  `q` with `close c q = q`, and it is a complete lattice under inclusion

### Discharge

| Law | Rung | Tool |
|---|---|---|
| L35.1, L35.2 | **4 Solver_proved** | smtml over bounded condition and page encodings — *bounded* |
| L35.3 | 2 | property test plus a mutant whose `close` adds a condition not satisfied by every row, which changes the result set and dies |
| L35.4 | 2 | property test over generated query pairs |
| L35.5 | 2 + 1 | property test for completeness of the enumeration; Gospel for the lattice claim |

### Scorecard

| Criterion | Score | Justification |
|---|---|---|
| Beauty | 5 | S21 turns out to be one instance of this; query equality becomes byte equality, which is exactly what the digest gate already knows how to check |
| Flexibility | 4 | σ = 0: a new query field is a new GADT constructor and the closure needs no change |
| Utility | 4 | user-visible capability — "the smallest query that yields exactly this set of pages" is a describe-button for any selection; plus deduplication of query fences and a principled cache key |
| Navigability | 4 | the concept lattice is a chart atlas: every closed set is a named region and the lattice edges are the moves between regions |
| Verifiability | 4 | floor rung 2, headline at rung 4 bounded, one mutant per law |

### Subsumes or strengthens

**Subsumes S21** (tags are the tag-only instance). Strengthens the query family
E1, whose `commute`, `partition` and `limit`-prefix laws all become statements
about the same closure.

## 12. Rejected for cause

A rejected structure is information. Each of these looks deep, and each fails a
specific criterion or a specific admissibility property from
`[[Unified feature set]]` §0.

| Structure | Why it looks deep | The specific failure |
|---|---|---|
| **Spectral reading of the link graph** — graph Laplacian, Fiedler value, Cheeger bound on conductance | eigenvalue zero-multiplicity counts components exactly, and the Cheeger inequality would bound the fragmentation the structural-holes feature is groping at | **Verifiability and P1.** Eigen-decomposition is iterative and floating-point; its output is not byte-pinnable, so it cannot enter a digest and it breaks S24's total-order determinism. The combinatorial shadow survives — component count by union-find is exact — so we keep the shadow and reject the spectrum. |
| **Bidirectional lens between rendered HTML and source** — edit the view, get the source | the well-behaved-lens laws (GetPut, PutGet, PutPut) would make an editable rendered view *provably* faithful | **Two independent failures.** Mathematically, `PutGet` cannot hold because `render` is not injective — many sources render to identical bytes, so `put` has no well-defined choice. Structurally, it needs a write route, which the Route ADT makes unrepresentable (`[[Unified functional algebra]]` F1). Either failure alone is fatal. |
| **Persistent homology of the corpus filtration** — barcodes over a distance threshold | S28 supplies the filtration for free, and an `H1` generator is literally a citation cycle | **Utility and Verifiability.** No named defect class: nobody can say what a corpus should do when a bar is long. The bottleneck distance between barcodes is a float with no exact test, so no rung of the ladder discharges anything. It would be decoration with a bibliography. |
| **Free monad over an open block or effect algebra** — a render plugin seam | it scores **5 on Flexibility**, the highest possible, and it is the obvious answer to "extension without modification" | **P2 and P4, and a trap in my own criteria.** Unbounded constructors make `render` non-total, and the atlas §10 already rejects it. Worth restating here because a criteria-driven pass will keep rediscovering it: the Flexibility criterion must be read as *extension along a stated seam*, and an open constructor set is not a seam, it is the absence of one. |
| **CRDT / join-semilattice merge over documents** — the corpus as a lattice | S18 already makes verdicts a join-semilattice; extending the join to documents looks like the same move one level up | **P1 and the review unit.** A CRDT merge is convergence *up to the merge function*: two replicas agree on a state, not on bytes, so the canonical serialisation dies and with it the differential (`[[Unified mathematical structures]]` §4). It also removes the commit, which is the review unit. |
| **Topos-theoretic re-description** — the internal logic of the S27 site, subobject classifier, sheaf semantics for diagnostics | it would make S27, S33 and S35 instances of one framework, which is exactly the "one structure, many corollaries" prize | **No discharging tool at any rung.** It restates what S27 already proves and adds no equation smtml, the type checker, the baseline, Gospel or Quint can touch. A re-description is not a structure; the test is whether it produces a law a tool can kill a mutant with, and it does not. |

## 13. Implement first — the top three

Ranked by the sum of the five scores, then by independence (a structure that
depends on an unbuilt one cannot be first), then by cost.

**1 · S27, the dependency sheaf — total 23.** The highest score, no
dependencies, and the only structure that turns seven separately-maintained laws
into corollaries of two equations. It promotes four rung-0 `Declared` laws, and
its headline law is rung 5 *by construction* rather than by test, which is the
strongest thing any proposal here claims. It is also the precondition for S32,
so building it makes the whole Build family tractable. Worked out in full in
§14.

**2 · S28, the Lawvere quasi-metric — total 22.** No dependencies, and the only
structure that makes the Navigability criterion measurable at all: `ecc index`
and the orphan count are integers a ratchet can hold. It unlocks S29 (which
scores 22 itself and is excluded from this ranking *only* because it is a
dependent), it supplies the kernel that PPR ranking and local-graph views both
want, and its carrier is exact by type so nothing it computes can poison the
digest. Cheap: the relaxation is a Kleene ascent the design already knows how to
write (S20).

**3 · S30, the dissection and patch groupoid — total 21.** No dependencies,
Utility 5, and it subsumes S16 outright rather than sitting beside it. It
changes the character of the harness's signature instrument: a drift verdict
stops being "these bytes differ" and becomes a patch that can be inspected,
composed and inverted — and a drift that *cannot* produce a patch becomes a new,
newly detectable defect. It is the precondition for S33.

**Ranked below, with reasons rather than silence.** S29 (22) is second on score
but is a dependent of S28. S35 (21) ties S30 but touches a family — query —
where the existing laws already hold, so its Δ is smaller. S34 (20) has the best
Navigability story after S28 but the weakest Verifiability, because it cites
theorems it cannot discharge. S31 (19) and S32 (19) are both excellent and both
narrow: S31 has Navigability 1 by nature, and S32 depends on S27. S33 (19)
depends on S30.

## 14. Worked exemplar — S27 as `Dep_sheaf`

### 14.1 The complete `.mli`

Included, not copied (HW.9.2.1) — the denotation is the file. The
hand-copy this replaces had drifted in nearly every signature: it still
declared the interface unimplemented, still typed the cover over
`Id.page Id.t` rather than `string`, and still carried a `blocks` field
and two Gospel clauses the module no longer has.

```literalinclude modules/hermes_wiki/src/engine/dep_sheaf.mli lang=ocaml
```

### 14.2 The complete law list

| Law | Statement | Rung | Discharging tool |
|---|---|---|---|
| L27.1 restriction | `section (restrict e (deps d)) d = section (restrict e all) d` | **5** | abstract `Env.view`, no widening operation: the violation does not compile |
| L27.2 functoriality | `narrow (narrow v u) w = narrow v (inter u w)`; `narrow v all = v` | 5 / 2 | the `cover_of` Gospel post-condition; property test for the identity |
| L27.3 gluing monoid | `glue [glue xs; glue ys] = glue (xs @ ys)`; `glue [] = Section.empty` | 3 + 2 | render baseline: single-file export vs concatenated page bytes; associativity property over random partitions |
| L27.4 descent | `rebuild ~previous:(build e C) e' ~changed:{x} C = build e' C`, byte for byte | 3 + 2 | differential over the 227-document corpus; property test with mutants |
| L27.5 tightness | for every `y` in `deps d` a perturbation of `y` changes `section … d`; equivalently `dead_cover_elements e d = []` | 2 | property test that searches for the witness per element |
| L27.6 cover determinism | `Cover.elements` is sorted, so `deps d` has one serialisation | 5 | the sorted-list return of `elements`; the cover is pinnable |
| L27.7 cocycle | on a cover of size ≤ 6, any two orders of gluing agree | **4** | smtml — **bounded encoding: evidence over covers of size ≤ 6, not a general proof** |
| L27.8 no IO | `section` performs no IO and imports nothing | 5 | the module type exposes none; P3 by construction |

### 14.3 Test plan

**Suite** `test_dep_sheaf.ml`, four legs plus the mutation battery.

1. **Law leg (property).** Generate corpora of 3–20 documents with random
   wikilinks, transclusions and fragment references. For each document, check
   L27.2, L27.3, L27.5, L27.6 and the equality in L27.4 against a cold build.
2. **Solver leg (smtml, bounded).** Encode covers of size ≤ 6 and section
   concatenation over an abstract byte-monoid; assert the negation of the
   cocycle condition and require `unsat`. Include a sanity-`sat` check so the
   leg can never pass vacuously — the pattern `test_smtml_lattice` already uses.
3. **Differential leg (baseline).** Over the real 227-document corpus: (a)
   `glue (build env docs)` equals the concatenation of the per-page rendered
   bodies; (b) for each of 20 sampled documents, perturb it, `rebuild` with
   `changed` set to that slug, and compare byte-for-byte against a cold build.
4. **Register leg.** `Feature_register.status` for HW.10.1.4 must agree with the
   live probe, and `test_feature_register` fails on disagreement.

**Mutation legs.** Five mutants, each with the check that kills it. A law
without a mutant is a law nobody has confirmed works.

| # | Mutant | The check that kills it |
|---|---|---|
| **M1** | *The leaky renderer.* `section` grows a "related pages" footer that reads every sibling's title from a captured `Env.t` instead of from its view. | **It does not compile.** `Env.view` has no widening operation, so the mutant must first add `widen : view -> t` to the `.mli` — a visible interface change. If the mutant instead widens the cover with `deps d = Cover.of_list all_slugs`, `dead_cover_elements` returns a non-empty list and the L27.5 property leg fails, naming the dead slugs. |
| **M2** | *The under-declared dependency.* `deps` returns wikilink targets only, dropping transclusion sources. | **L27.4, differential leg 3(b).** Perturb a transcluded page `x`, `rebuild ~changed:{x}`, compare with a cold build: the transcluding document's section differs, and the failure names the document. This is the classic stale-incremental-build defect caught by its own law. |
| **M3** | *The order-sensitive glue.* `Section.append` renumbers footnotes globally by first appearance across the whole export. | **L27.3.** Associativity fails over random partitions in leg 1, and the worker-count check in leg 3(a) — `glue` at partition sizes 1, 2 and 8 — produces three different byte strings. |
| **M4** | *The escaping slugger.* The heading slugger keeps one duplicate counter across documents instead of one per document. | **L27.1, via leg 3.** Rendering `d` against `restrict e (deps d)` and against `restrict e all` yields different anchor suffixes, and the render baseline flags it across the corpus. This is the existing A4 locality law, now failing as a corollary rather than as a separate test. |
| **M5** | *The identity restriction.* `narrow v c = v`. | **L27.2.** `cover_of (narrow (narrow v u) w)` no longer equals `inter u w` whenever the intersection is proper — caught by the Gospel post-condition and by the leg-1 property. `dead_cover_elements` additionally reports every slug in the corpus as dead cover. |

Mutation yield target: 5 written, 5 killed, and the killing check named in
advance for each — because the point of a mutation leg is that the test was
predicted to catch it, not that it happened to.

### 14.4 The feature-register row it would add

| Field | Value |
|---|---|
| `id` | `HW.10.1.4` |
| `area` | `Build` |
| `name` | `Restricted render view (dependency sheaf)` |
| `law` | `section (restrict e (deps d)) d = section (restrict e all) d BY CONSTRUCTION (the view is abstract and has no widening); glue is a monoid; rebuild(changed) = cold build, byte for byte; deps has no dead elements` |
| `utility` | 4 |
| `criticality` | 5 |
| `sources` | `[ Sphinx ]` — dependency tracking is the one place the survey's ladder is ahead of ours |
| `gates` | `[ "HW.10.1.1"; "HW.10.1.2"; "HW.10.1.3" ]` |
| `declared` | `Ready` — no blocker; `Corpus` and `Wiki_ast` already supply everything it consumes |
| `priority` | `3 × 5 + 2 × 4 + 3 = 26` |

In the register's own syntax:

```ocaml
f ~src:[ Sphinx ] ~gates:[ "HW.10.1.1"; "HW.10.1.2"; "HW.10.1.3" ]
  "HW.10.1.4" Build "Restricted render view (dependency sheaf)"
  "render sees only its cover, BY CONSTRUCTION; glue is a monoid;\n\
   rebuild(changed) = cold build byte-for-byte; deps has no dead elements"
  4 5
  ~derived:(fun () ->
    (* live probe: a document that links nothing renders identically
       against its own cover and against the whole corpus *)
    try
      let env = Env.of_corpus fixture_corpus in
      let d = fixture_document in
      render (Env.restrict env (deps d)) d
      = render (Env.restrict env fixture_all) d
    with _ -> false)
  Ready
```

Criticality 5 is the honest score: a stale incremental build is *silently*
wrong, and the register weights criticality highest precisely because silent
wrongness costs more than absence.

## 15. What this pass did not find

Two negatives worth recording, since an honest pass reports its misses.

**No structure was found that subsumes the differential itself.** S30 makes a
drift verdict explain itself and S27 makes the build that produces it sound, but
the central theorem of `[[Unified mathematical structures]]` §4 — a differential
gate requires a canonical serialisation — remains a theorem about the primitive
rather than a consequence of a deeper structure. It probably should be: it is
the primitive, and a primitive is what everything else is a consequence *of*.
*Second-pass annotation:* S36 now exhibits the differential **gate** as a
reconciliation instance (`[[Unified system synthesis]]` §13–§14) while the
canonical-serialisation theorem stays primitive underneath it — the miss
narrowed; it did not close.

**No structure improved the Q&A path.** HW.6.3.5 wants a deterministic answer
with non-empty citations. S28 gives it a ranking and S35 gives it a query normal
form, but neither turns "answer a question" into an object with laws. That
remains the hardest open item in the design, and nothing in this pass moved it.

Cross-references: `[[Unified functional atlas]]` · `[[Unified domain ontology]]` ·
`[[Unified functional algebra]]` · `[[Unified feature set]]` ·
`[[Unified mathematical structures]]` · `[[Unified implementation approach]]` ·
`[[Meta-unification]]`.

Part of [[Knowledge fractal map]].

