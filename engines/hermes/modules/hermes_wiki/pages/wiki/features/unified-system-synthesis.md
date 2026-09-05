---
id: hermes-unified-system-synthesis
status: draft
type: claim
ktype: moc
maturity: incubating
domain: formal_verification
topics: [structures, reconciliation, synthesis, second-pass]
created: 2026-08-09
generated: false
allow_example_links: true
last_verified: 2026-08-09
verified_by: agent
next_review: 2026-09-09
---
# Unified system synthesis — the harness and the wiki as one structure

#feature #src-unified #area-algebra #cov-design

**Nothing in this document is implemented.** Every structure below is a
*proposal*, in the discipline of `[[Unified deep structures]]`: a mathematical
identity, the harness constructs and the wiki constructs that instantiate it,
an OCaml signature sketch, laws as equations, the discharging tool from the
ladder the harness actually runs, and a five-criteria scorecard using the
proxies of `[[Unified deep structures]]` §1 (consequence ratio ρ, seam width σ,
promotion count Δ, the lostness numbers, floor rank and mutation yield).

The first deep-structures pass (S27–S35) unified the wiki/ZK subsystem, and
S27 has since **landed** as `hermes_harness/dep_sheaf.ml{,i}`. This pass is the
level above: one view across the **parity/evidence harness, the wiki/ZK layer,
and the build** — the places where the evidence machinery and the knowledge
machinery are the same mathematics wearing two uniforms. The index continues
as **S36–S42** and renumbers nothing.

**The R9 rule governs this whole document.** The evidence fractal (L0 product
→ L6 receipt, plus LX control — `docs/hermes/feature-ontology.md`) and any
runtime or corpus fractal are *different fractals*. Everything below unifies by
exhibiting a **common structure with disjoint instances**, never by identifying
levels of one fractal with levels of another. The one proposal that required
the identification is dissected in §10.1 and rejected.

**Bounded-model honesty, stated once.** Every rung-4 claim below is an `unsat`
result over a bounded encoding — a fixed chain height, a fixed key set, a fixed
tree size. `Formal_coverage` records such a claim as `Solver_proved` with the
bound named, never as `Machine_checked`. And one further honesty this pass
adds: **the emptiness of a hom-set is never solver-provable** — see S38, which
takes that limit as its subject rather than hiding from it.

## 1. The thesis

> **The whole system is one structure: a family of fail-closed reconciliation
> gates over world-indexed judgments.** Every judgment the system trusts is a
> section over a *named world* (a snapshot digest, a revision, a verifier, a
> date — S40) and a *named cover* (its dependency set or its child
> decomposition — S39); verdicts merge only through graded join-semilattices
> with per-site empty policies (S37); every registry, gate and baseline is one
> reconciliation pair — a declared claim against a derived observation, with
> the residue computed and surfaced (S36); and the arrows that could forge
> evidence — alert into verdict, telemetry into credit, one fractal into the
> other — are *stated absences* in the system's own category (S38).

Stated falsifiably: **every credit-bearing or drift-bearing path in this
repository factors as *restrict* (to a named world and cover) → *derive* →
*reconcile* → *merge*, and every "may not flow" rule in
`docs/hermes/mandatory-rules.md` is a row of the S38 absence catalogue.**
Exhibit one gate, one merge, or one prohibition that does not fit and the
thesis fails. The nearest candidates for a falsifier are named honestly: the
convergence controllers (`homeostasis.mli`, `turn_budget.mli`) are control
loops, not gates — the thesis covers them only through S37 (their alert
lattice) and S38 (their absent arrow into verdicts), and claims nothing about
their control laws. If a controller is ever found *granting* credit, that is
not a falsifier of the thesis; it is a violation of R10.

## 2. The structure index, continued

| # | Structure | Where it lives | What it buys |
|---|---|---|---|
| S36 | **Reconciliation pair** (declared vs derived, residue computed) | `Feature_register`, `Gap_plan`, `Formal_coverage`, render baseline, `schema_gaps`, `dead_cover_elements`, evidence store, R13 preflight | five registry disciplines and two gate disciplines become one pattern with one law: the residue is computed, surfaced, and demonstrably non-vacuous |
| S37 | **Graded verdict chain** (bounded chain, keep-worst join, per-site empty policy) | `Parity_algebra`, `Homeostasis`, `Fractal_diagnostic` severity, `Formal_coverage.strength`, wiki `Verdict`, defects/notices | one solver encoding instead of two hand-mirrored ones; the vacuous-truth guard becomes a stated per-site policy; two more chains get rung-4 proofs by instantiation |
| S38 | **The co-presentation** (absent arrows as design objects) | R5, R9, R10, the two-lattice law, no-`widen`, no write verb, no `bind`, the refused adjunction | the mandatory rules become morphism constraints in a catalogue with one meta-law (every absence lives at a visible seam); two concrete rung-5 promotions |
| S39 | **Descent on two sites** (evidence tree and dependency site, one coverage theory) | `Parity_algebra.roll_up` + the completion invariant; `Dep_sheaf` (landed) | the completion invariant stops being prose; the space/time duality of S27/S33 gains a third site — proof — without identifying any levels (R9-safe by construction) |
| S40 | **World-indexed judgments** (the pinning discipline as a discrete fibration) | snapshot/revision/verifier keys, fixtures, receipts, baselines, R16 dates, `last_verified`/decay | six scattered keying rules become one law: evidence does not transport between worlds, it is re-derived; the stale-evidence class gets a type-level kill |
| S41 | **Diagnosis = kernel of repair** | capture-failure constructors, gospel-lint triage, Blocked/Unmapped, dead link/anchor/ambiguous, Drifted/Edited_since | "different fixes ⟹ different diagnoses" becomes a two-equation factorisation law with a conflation-mutant discipline that already has a landed precedent |
| S42 | **The law register** (laws as data; criteria as derived gauges) | `Formal_coverage` at law granularity; the algebra scoreboard | the ~78-law scoreboard and the four smells become queries that cannot drift; ρ, Δ and the floor become computed, which is what makes the five criteria measurable |

Seven structures. Two — S39 and S42 — are dependents (S39 needs S37's fold;
S42 needs S36's machinery), exactly as S29 and S33 were dependents in the
first pass. Two — S40 and S41 — are on no candidate list this pass was handed.

## 3. S36 · The reconciliation pair — declared vs derived, with a computed residue

### Identity

A **pair of partial sections of one bundle, with a difference kernel and a
fail-closed totalisation**. Over a key set `K` and claim space `V`: a declared
partial map `decl : K ⇀ V` (authored, believed) and a derived partial map
`obs : K ⇀ V` (computed from the running system). Three derived objects:

- `status = obs ⊕ decl` — the **left-biased override** (S17's monoid, with the
  probe on the left): the probe answers wherever it can, the declaration only
  where it cannot;
- `residue = { k ∣ decl k ↓ ∧ obs k ↓ ∧ decl k ≠ obs k }` — the difference
  kernel's complement, computed and surfaced, never suppressed;
- the **fail-closed totalisation**: a key neither map defines is *no claim*
  (never a pass), and a declared claim about a key outside `K` is itself
  residue ("unknown subjects are drift too" — `formal_coverage.mli`).

The residue has two dispositions, and the split is the structure's duality:
**report** (read side: `stale_declarations`, `schema_gaps`, `reconcile` — a
worklist) and **refuse** (write side: the evidence store rejecting a
same-key/different-payload replay, R3; the `feature_catalog` write that is
idempotent only when identical). One equalizer, two totalisations.

### Where it lives

Harness: `hermes_harness/feature_register.mli` (`status` prefers the probe;
`stale_declarations`); `hermes_harness/gap_plan.mli` (same discipline, older
registry); `hermes_harness/formal_coverage.mli` (`intent`/`reconcile`,
`gaps_against` exposed "so tests can prove each law CAN fail",
`missing_files`); the render-baseline differential (F3: pinned digest vs
recomputed render, residue split into `Drifted` and `Edited_since` — the two
directions); `evidence_store` replay rejection (R3);
`docs/hermes/feature-ontology.md` (catalog writes "idempotent only when those
values are identical"); R13's resource preflight (declared needs vs observed
environment, unknowable = unmet). Wiki: `Hermes_wiki.schema_gaps`
(`hermes_wiki.mli` — PKM conformance, notices first, ratchet later);
`Dep_sheaf.dead_cover_elements ?widen_with` (declared cover vs observed
sensitivity, with the meta-falsification hook, landed);
`[[Unified domain ontology]]` §0's preference order — "derived outranks
declared because a derived value needs no gate at all" — which this structure
turns from a table into an algebra.

### Signature sketch

```ocaml
module type SUBJECT = sig
  type key
  type claim
  val equal_key : key -> key -> bool
  val equal_claim : claim -> claim -> bool
  val show_key : key -> string
  val show_claim : claim -> string
end

module Make (S : SUBJECT) : sig
  type t          (* ABSTRACT: rows enter only through [register] *)

  val register :
    (S.key * S.claim option * (unit -> S.claim option) option) list ->
    (t, string) result                  (* duplicate key = refusal, R3 *)

  (* The ONLY reader. The declared claim has no other accessor: a consumer
     that wants to trust a declaration over a live probe cannot be written
     against this interface. *)
  val status : t -> S.key -> S.claim option

  val residue : t -> (S.key * S.claim * S.claim) list   (* (key, declared, observed) *)
  val unknown : t -> claimed:S.key list -> S.key list   (* fail-closed *)

  (* Meta-falsification: force a disagreement, prove the residue can fire. *)
  val inject : t -> S.key -> S.claim -> t
end
```

The load-bearing move mirrors S27's: as `Env.view` has no `widen`, this
register exports **no accessor for the declared claim**. Reading a declaration
past a live probe is not a bug to test for; it is a function that does not
exist.

### Laws

- **L36.1 preference** `obs k ↓ ⟹ status t k = obs k`
- **L36.2 residue soundness and completeness**
  `k ∈ residue t ⟺ decl k ↓ ∧ obs k ↓ ∧ decl k ≠ obs k` — both directions:
  a declared-ahead row and a declared-behind row both appear
- **L36.3 fail-closed** `decl k ↑ ∧ obs k ↑ ⟹ status t k = None`, and
  `unknown t ~claimed` names every claimed key the register does not know —
  absence is never a pass
- **L36.4 write functionality** `register` refuses a duplicate key; recording
  `(k, v)` then `(k, v′)` with `v ≠ v′` is a refusal, not an update — R3 as
  the write-side of the same equation
- **L36.5 non-vacuity** `residue (inject t k v) ≠ []` whenever
  `status t k ↓ ∧ status t k ≠ Some v` — the residue computation is
  demonstrably able to fire (the `gaps_against` / `widen_with` discipline,
  made a law)

### Discharge

| Law | Rung | Tool |
|---|---|---|
| L36.1, L36.3 | **5 / 2** | the abstract `t` with `status` as the only reader — trusting a stale declaration does not compile; the override equation itself by property test |
| L36.2 | **4 + 2** | smtml over a bounded key/claim encoding (finite maps, ≤ 6 keys): negation of the biconditional is `unsat`, with a sanity-`sat` leg — *bounded*; property test with both-direction mutants |
| L36.4 | 2 | the landed `test_evidence_store` pattern, instantiated on the functor |
| L36.5 | 2 | property leg that injects and asserts the residue fires |
| instance agreement | **3** | a differential inside the suite: `Feature_register.stale_declarations` and `Gap_plan.stale_declarations` re-expressed through `Reconcile.Make` must agree with the landed outputs row for row |

### Scorecard

| Criterion | Score | Justification |
|---|---|---|
| Beauty | 5 | ρ ≥ 9: eight live disciplines (two registers, coverage intent, two baseline directions, schema gaps, dead covers, store replay, preflight) become instances of five equations and one new primitive (the abstract register); the report/refuse duality is named |
| Flexibility | 5 | σ = 0: the next registry — the law register S42, a doc-coverage census, a fixture inventory — is a `SUBJECT` instance; no existing module is edited |
| Utility | 4 | Δ ≥ 2: the per-module "cannot drift" comments in `feature_register.mli` and `gap_plan.mli` are today rung-0 prose about the discipline itself and become tested laws; kills the silent-registry-drift class; adds HW.8.2.7 (§13.4) |
| Navigability | 2 | indirect: every residue list is a worklist with a stable order, but no reader distance is bounded |
| Verifiability | 5 | headline law partially rung 5 by abstraction; five mutants named in §13.3, each with its killer predicted |

### Subsumes or strengthens

Strengthens **S17** (the override monoid gains the residue operator, which the
monoid alone cannot state); makes `[[Unified domain ontology]]` §0's modal
preference executable; exhibits **F3**'s two-verdict split and
**S27**'s `dead_cover_elements` as instances; unifies R3's write refusal and
the registers' read reporting as two totalisations of one equalizer. It is the
machinery S42 runs on.

## 4. S37 · The graded verdict chain — one join, many uniforms

### Identity

A **finite bounded chain with keep-worst join, a grading, and a per-site empty
policy**. The schema: a carrier `C` (possibly payload-bearing), a finite chain
`R` with `⊥` and `⊤`, a grading `rank : C → R`; the join keeps the element of
larger rank, so it is a semilattice **on the rank image** and a
grading-monotone choice function on the carrier (payload survival at ties must
be a stated tiebreak — `Homeostasis.worst` carries `P0 of string`, and the law
holds *up to rank*, which the schema states rather than hides). The fold over
a finite family is the semilattice fold **on non-empty families only**; the
empty family maps to a **declared point** `e₀`, chosen per site:

- an *advisory* site declares `e₀ = ⊥` — the empty window is Green, "absence
  of telemetry is never a violation" (`homeostasis.mli`);
- a *required-evidence* site declares `e₀ = ` the no-evidence element, **not**
  `⊥` — `roll_up ~required:true [] = Unmapped`, the vacuous-truth guard that
  `parity_algebra.ml` states as its reason to exist.

That the two policies differ, and that each is correct for its site, is the
information content: the empty case is not a algebraic accident to be
inherited from the unit, it is a **coverage decision** (S39 gives it its
second reading).

### Where it lives

Harness: `Parity_algebra.verdict` — Verified 0 < Unmapped 1 < Blocked 2 <
Divergent 3, `combine = max`, the non-vacuous `roll_up`, `grants_credit` only
at rank 0; `Homeostasis.alert` — Green < P2 < P1 < P0, `worst`, `worst [] =
Green`; `Fractal_diagnostic` severity — No_effect 9 < Blocks_credit 13 <
Denies_credit 17 (the OTel grading, R4); `Formal_coverage.strength` — ranks
0–5, with `grade = ` best (join) over an entry's artifacts and `system_grade =
` **min over entries** — the *meet* in the same chain, the c3i worst-of rule:
the dual fold, in the schema for free. Wiki: `Verdict.combine = max`
(`[[Unified functional atlas]]` §7, S18); diagnostic severity (algebra A5,
already `Solver_proved` over the 4-element domain); the defect/notice
two-chain, whose bottom cannot reach the refusal exit ("a notice never
refuses").

The two existing solver legs — `test_smtml_lattice` and `test_smtml_alerts` —
are **the same encoding written twice by R14 mirror**, as the second one says
in its own header. The schema is the factoring that makes the third and fourth
instantiations (severity, strength) cost one functor application each.

### Signature sketch

```ocaml
module type GRADED_CHAIN = sig
  type t
  val rank : t -> int                   (* into 0 .. height-1, total *)
  val height : int
  val bottom : t                        (* rank 0 *)
  val empty_policy : [ `Bottom | `Point of t ]   (* the site's e0 *)
  val tie : t -> t -> t                 (* payload survival at equal rank *)
end

module Fold (C : GRADED_CHAIN) : sig
  val join : C.t -> C.t -> C.t          (* keep-worst by rank; C.tie at ties *)
  val fold : C.t list -> C.t            (* [] -> e0 per empty_policy *)
  val meet_rank : C.t list -> int       (* the dual: the floor, worst-of *)
end

(* One solver leg, generated per instance: the six join laws, the LUB law,
   the sanity-SAT leg and the broken-join mutant, over ranks 0..height-1 —
   exactly the encoding test_smtml_lattice and test_smtml_alerts each
   hand-roll today. *)
module Solver_leg (C : GRADED_CHAIN) : sig
  val run : unit -> (string * bool) list
end
```

### Laws

- **L37.1 join laws on the rank image** commutative, associative, idempotent;
  `⊥` is the identity of `join`; `⊤` absorbs — the six laws both landed suites
  prove today, once each
- **L37.2 grading** `rank (join a b) = max (rank a) (rank b)`, and `rank` is
  monotone: more severe input can never lower a fold
- **L37.3 fold-glue** `fold (xs @ ys) = join (fold xs) (fold ys)` for
  non-empty `xs`, `ys` — partition and order independence, which is what makes
  concurrent evidence collection legal (and is S39's gluing law in miniature)
- **L37.4 empty policy** `fold [] = e₀`, with `e₀` **declared per site** and,
  for a required-evidence site, `e₀ ≠ ⊥` — the vacuous-truth guard as an
  equation (pinned today at `test_parity_algebra.ml`: "an empty required node
  is unmapped, not verified")
- **L37.5 the dual floor** `meet_rank es ≤ rank e` for every `e ∈ es` — the
  system grade is a lower bound of every entry grade (`Formal_coverage`'s
  worst-of cell rule, now the meet half of the same chain)

### Discharge

| Law | Rung | Tool |
|---|---|---|
| L37.1, L37.2 | **4** | the generated solver leg per instance — the landed encoding, now written once; sanity-`sat` plus the broken-join mutant per instance — *bounded chains, stated heights* |
| L37.3 | 2 | property over random partitions, plus a mutant fold that depends on order |
| L37.4 | 2 | the landed vacuous-truth BDD leg, generalised to assert each site's declared `e₀` |
| L37.5 | 2 | property against brute-force minimum |

### Scorecard

| Criterion | Score | Justification |
|---|---|---|
| Beauty | 4 | one schema, six live instances; the join/meet duality (entry grade vs system floor) and the two empty policies are named; loses a point because the mathematics is elementary and the theorem count is low |
| Flexibility | 5 | σ = 0: a new chain — a lint-severity scale, a review-maturity scale (`seed < incubating < evergreen`, PKM §3) — is one `GRADED_CHAIN` instance and its solver leg is generated |
| Utility | 4 | Δ = 2: the severity chain (A5) keeps rung 4 but gains the mutant leg it lacks; the strength chain's worst-of rule is rung-0 prose in `formal_coverage.mli` today and becomes L37.5 at rung 2; kills the hand-mirrored-suite-drift class the R14 mirror created |
| Navigability | 1 | none, honestly |
| Verifiability | 5 | headline at rung 4 with a landed pattern, mutation legs pre-existing in both suites; floor 2 |

### Subsumes or strengthens

Subsumes **S18** (join-semilattice) as the graded, empty-policy-aware form;
strengthens **A5**, **F2**; supplies the fold S39 glues with. It deliberately
does **not** merge the chains' carriers — see §10.2 for why that tempting
"simplification" is rejected.

## 5. S38 · The co-presentation — absent arrows as first-class design objects

### Identity

The system's modules and exported functions form a small **syntactic
category**; the ambient mathematical category (sets and functions) is bigger.
The design's deepest commitments are places where the syntactic category is a
**deliberately non-full subcategory**: the arrow exists mathematically and is
*absent syntactically*. The candidate framing "the forbidden morphism
alert→verdict as a naturality failure" is rejected as imprecise: nothing
fails — no functor pair and no square are involved. The correct statement is
**stated non-fullness**: `Hom_sys(Alert, Verdict) = ∅` while
`Hom_Set(Alert, Verdict) ≠ ∅`, and `test_smtml_alerts` says exactly this in
prose ("a rank isomorphism exists mathematically, so its nonexistence cannot
be proved — the forbidden morphism is ARCHITECTURAL"). The structure is the
**catalogue of required-empty hom-sets — a co-presentation — plus one
meta-law**: every absence must live at a *seam* where introducing the arrow is
a visible interface diff, never only a code-body discipline.

### Where it lives

Harness: the two-lattice law (no `alert → verdict` path; pinned structurally
via `harness_topology`'s FPP model and the BDD suite); **R5** (only
Implementation origin denies — today the P1 property in
`test_fractal_diagnostic`, an arrow-absence enforced by test, not type);
**R10** (discovery and obligation facts have no arrow into parity credit:
`grants_credit` holds only at `Verified`, and `Verified` is written only by
the differential chain — `docs/hermes/feature-ontology.md`: "only the final
scenario/trace/verification chain is allowed to promote strict parity");
**R9** (no functor between the runtime fractal and the evidence fractal); the
`LX_control` comment in `fractal_diagnostic.ml` ("LX is NOT a level of the
evidence chain") — which the *type does not yet enforce*, since `LX_control`
is a constructor of the same variant as `L0_product … L6_receipt`. Wiki: no
`widen : view -> Env.t` (`dep_sheaf.mli`, landed — S27's load-bearing
absence); `Route` has no write constructor and no traversal alphabet (F1);
`Validation` exports no `bind` (A2); the argumentation frame takes only the
attack relation (D4); re-baselining is a separate executable, outside the
battery (F3); the refused free⊣forgetful adjunction
(`[[Unified domain ontology]]` §2b — an absence already recorded as
load-bearing); no LLM arrow into `render` or any verdict (P2,
`[[Unified mathematical structures]]` §5).

### Signature sketch

```ocaml
module Absent_arrow : sig
  type seam =
    | Type_boundary of string   (* the .mli whose edit would introduce it *)
    | Topology of string        (* the harness_topology / import-graph row *)
    | Battery of string         (* the property/BDD leg that hunts it *)
    | Process of string         (* a separate executable, outside the battery *)

  type t = {
    id : string;                (* "AA-R5", "AA-two-lattice", "AA-widen", ... *)
    src : string;               (* the domain that must not flow *)
    dst : string;               (* the codomain it must not reach *)
    rule : string;              (* R5 | R9 | R10 | P2 | ... *)
    seam : seam;
    discharged_by : string;     (* the test or type that holds it today *)
  }

  val absences : t list
  (* S36 applied to non-arrows: every listed seam anchor must exist, and a
     listed Battery leg must be present in the suite inventory. *)
  val missing_anchors : unit -> string list
end

(* The two promotions this structure proposes, sketched: *)

(* 1. R5 by construction: impact indexed by origin. Denying parity credit
      is only constructible from Implementation. *)
type implementation and environment and evidence_ and control and specification
type _ impact =
  | Denies  : implementation impact
  | Blocks  : _ impact
  | Nothing : _ impact

(* 2. The LX split: the evidence chain is exactly the chain. A control-plane
      coordinate is a DIFFERENT type, so filing a control event at an
      evidence level does not compile — R9's LX half by construction. *)
type chain_level = L0 | L1 | L2 | L3 | L4 | L5 | L6
type coordinate = Chain of chain_level | Control_plane
```

### Laws

- **L38.1 seam visibility** every absence in the catalogue names a seam whose
  edit is interface-visible (a `.mli`, a topology row, a named leg) — a
  prohibition that lives only in a code body is a catalogue gap, reported by
  the same differential discipline as S36
- **L38.2 R5 as an equation** `impact = Denies_credit ⟹ origin =
  Implementation` — today rung 2 (the P1 property); after the GADT promotion,
  the violating diagnostic does not compile
- **L38.3 R10 as an equation** `grants_credit v ⟹ v = Verified`, and the only
  producer of `Verified` is the L4–L6 differential chain — half type
  (`grants_credit` pattern-matches), half topology (who may write `Verified`)
- **L38.4 the two-lattice law** no exported value has type
  `Homeostasis.alert -> Parity_algebra.verdict`, and no import path carries
  one through an intermediary — a structure-suite law, **honestly rung 2
  forever**: emptiness has no solver proof and no type proof, only a seam and
  a hunt
- **L38.5 the LX split** the roll-up consumes `chain_level` only; after the
  split, `Control_plane` at an evidence level is unrepresentable — today the
  conflation is representable and guarded by comment alone, which is the
  weakest guard this repository knows

### Discharge

| Law | Rung | Tool |
|---|---|---|
| L38.2 promotion | **5** | the origin-indexed GADT: the violation does not compile; the existing P1 property is kept as the sanity leg |
| L38.5 promotion | **5** | the variant split; `Fractal_diagnostic` constructors migrate mechanically |
| L38.3 | 2 + 2 | property on `grants_credit`; the landed "parity reports 0% until receipts exist" leg (R10's enforcement today) |
| L38.4, L38.1 | 2 | the structure layer (R7): a suite that walks the export/import surface against the catalogue; plus the S36 anchor check on the catalogue itself |

### Scorecard

| Criterion | Score | Justification |
|---|---|---|
| Beauty | 5 | ρ ≥ 10: three mandatory rules and seven scattered type refusals become rows of one catalogue with one meta-law; the duality is named — a presentation says what exists, a co-presentation says what must not, and the design is only whole with both |
| Flexibility | 4 | σ = 0 to add an absence row; the two promotions edit existing types (priced, mechanical) |
| Utility | 5 | the class killed is the worst in the system — an arrow that forges evidence; Δ = 2 concrete rung-5 promotions (R5 GADT, LX split), both of which retire comment-guarded hazards |
| Navigability | 1 | none |
| Verifiability | 4 | two laws reach rung 5 by promotion; the catalogue check is rung 2; and the structure is honest that L38.4 can never rise — that honesty is itself the receipt |

### Subsumes or strengthens

Strengthens **T1** ("make the illegal unrepresentable" gains a register of the
illegals and a meta-law about where they live), **F1**, **F2**, **A2**,
**D4**; gives **R9** its formal home (the absent identification functor —
§10.1 is this row's dissection); turns every "structures deliberately
rejected" table into enforceable rows rather than prose. S27's no-`widen` is
the landed exemplar the whole catalogue generalises.

## 6. S39 · Descent on two sites — proof joins space and time

### Identity

A **coverage structure** (site: a poset with declared covering families) with
a separated-presheaf-and-descent reading, instantiated on **two different
sites** — and only instantiated, never identified:

- **Site A (space, landed):** sub-corpora ordered by inclusion; the cover of a
  document is `deps d` (`dep_sheaf.mli`). Sections are rendered bytes; gluing
  is `glue`; separatedness is "render sees only its cover" (L27.1).
- **Site B (proof):** the evidence tree; the cover of a node is its child
  decomposition (`docs/hermes/feature-ontology.md`: "for any node `n`,
  `verified(n)` holds only when every direct child is verified"; "a missing
  trace or evidence keeps every ancestor unmapped"). Sections are verdicts;
  gluing is `Parity_algebra.roll_up`; separatedness is "a parent verdict is a
  function of its child family and nothing else".

The precision paragraph, as S27 required one: the verdict presheaf is trivially
a sheaf; the content is (i) separatedness of the *roll-up* (no side channel),
(ii) gluing determinism (any order, any partition — L37.3), and (iii) **the
coverage policy itself**: which families count as covering. And there the two
sites *differ by design*: on Site A the empty family covers (a document with no
dependencies renders against the empty view); on Site B the empty family does
**not** cover a required node (`roll_up ~required:true [] = Unmapped`). One
theory, two coverages, opposite empty policies — S37's `e₀` is the algebraic
shadow of a coverage decision. This is the R9-safe form of the candidate
"restriction/separatedness principle across two sites": the *theory* is
shared; the sites, levels and policies are not. (The other half of that
candidate — "record only what was verified", R3/R10 — is not a restriction
map at all; it lands in S36's write functionality and S38's absent credit
arrow, which is a sharpening of the candidate as posed.)

### Where it lives

Harness: `Parity_algebra.roll_up`/`report`; the completion invariant and the
"missing L5/L6 keeps ancestors unmapped" rule (`feature-ontology.md`); the
level projection of the dashboard (L0–L4) as the chart of Site B. Wiki:
`Dep_sheaf` (landed S27); the single-file export as the global section; L27.3
and L27.4. Register: HW.8.2.3's family on one side, HW.10.1.\* on the other.

### Signature sketch

```ocaml
module type SITE = sig
  type node
  type section
  val covers : node -> node list option
      (* None = leaf; Some [] = the EMPTY family, whose meaning is the
         site's coverage policy, stated in [empty_covers]. *)
  val empty_covers : bool               (* Site A: true. Site B: false. *)
  val glue : section list -> section    (* total on non-empty families *)
  val empty_section : section           (* used only when empty_covers *)
end

module Descent (X : SITE) : sig
  val section_at : X.node -> (X.node -> X.section) -> X.section
  (* separatedness + gluing: the parent section is [glue] of the child
     family, or the policy's answer on the empty family; no other input. *)
  val order_invariant : X.node -> bool  (* the L37.3 check, per node *)
end
```

The R9 guard is in the shape: `Descent` is a functor over a module **type**,
and no function anywhere takes a Site-A node to a Site-B node. Two instances,
zero arrows between them — the absence is itself an S38 row.

### Laws

- **L39.1 separatedness of the roll-up**
  `verdict n = roll_up (map verdict (children n))` — an equation with no other
  free variables: no cousin, no global counter, no cached ancestor
- **L39.2 gluing determinism** for any partition `P` of the child family,
  `roll_up (map roll_up P) = roll_up children` (non-empty parts) — the
  evidence twin of L27.3, from L37.3
- **L39.3 coverage policy** Site B, required node: `children = ∅ ⟹ verdict =
  Unmapped`; Site A: `deps d = ∅ ⟹ section` is defined and equals the render
  against the empty view — both directions pinned, because each is the other's
  counterexample
- **L39.4 monotone refinement** `rank (roll_up (v :: vs)) ≥ rank (roll_up
  vs)` for non-empty `vs` — adding a child can never lift a proved divergence
  out of the parent (the upper-bound half of the landed LUB proof)

### Discharge

| Law | Rung | Tool |
|---|---|---|
| L39.1 | 2 | property + the *escaping roll-up* mutant (reads a global tally — the evidence twin of S27's M4 escaping slugger) |
| L39.2 | 2 + **4** | property over random partitions; the associativity/LUB encodings already `unsat` in `test_smtml_lattice` — *bounded* |
| L39.3 | 2 | the landed vacuous-truth leg (Site B) plus a `Dep_sheaf` empty-cover leg (Site A), cross-referenced so neither can be weakened alone |
| L39.4 | **4** | the monotonicity encoding already in both solver suites — *bounded chains* |

### Scorecard

| Criterion | Score | Justification |
|---|---|---|
| Beauty | 5 | the completion invariant — prose in `feature-ontology.md` today — becomes the same two equations S27 landed for renders; the first pass's duality "space and time are one sheaf condition on two sites" gains its third site, proof, and the triad is the whole system |
| Flexibility | 4 | σ = 0: a new evidence level or a new corpus root is a new node kind under the same `SITE` instance; the `Descent` functor never changes; new code exists (the Site-B wrapper), which costs the point |
| Utility | 4 | Δ = 2: L39.1 and L39.3's Site-B half are rung-0 prose today; kills the "parent verdict computed from a stale child cache" class, which no current check names |
| Navigability | 2 | the evidence tree becomes chartable with the same vocabulary as the corpus (the dashboard's level projection is a chart), but no reader metric improves |
| Verifiability | 4 | floor 2; two laws ride landed rung-4 encodings; the mutant is named in advance |

### Subsumes or strengthens

Strengthens **S27** (exhibits its theory as shared and its site as one of
three); strengthens **S37** (the fold gains its coverage reading);
complements **S33** (space, time, proof — three sites, one condition). It is
the structure that makes §10.1's rejection precise instead of pious.

## 7. S40 · World-indexed judgments — pinning as a discrete fibration

### Identity

A **family of judgment fibers indexed by worlds, over a deliberately discrete
base**. A world is the tuple a judgment is true *at*: snapshot digest ×
harness revision × verifier × date (per judgment kind). Every stored judgment
carries its world **in its key**; within a fiber the evidence assignment is a
partial *function* (R3); and between fibers the system category has **no
transport arrows** — evidence at `w` says nothing at `w′`, and the only
world-crossing operations are *named re-derivations* (re-capture, re-baseline,
`verify` at `HEAD`), each producing a fresh section, never mutating one. The
categorical content is small and that is the point: the base is discrete
**because the design refuses its arrows** — a pinning discipline, stated once
instead of six times.

The complement to S33 is exact and worth stating: S33 made the *corpus* a
functor over the commit poset — objects transport, deltas compose. S40 is the
negative half: **judgments do not follow**. At `c′` you do not transport
`verified-at-c`; you rebuild and re-verify. History composes; evidence
re-derives. The two statements together resolve what looks like a tension and
is actually the design.

### Where it lives

Harness: L6 receipts "must name the same frozen snapshot digest as the source
inventory" (`feature-ontology.md`, completion invariant); fixtures keyed
scenario × snapshot — a wrong-snapshot fixture reads as *absence*, never as a
substitute (HZ-FIX-02, `fractal_diagnostic.ml`); gospel receipts keyed by
verifier so "an 'unavailable' observation cannot overwrite a real check"
(HZ-L3-01); `feature_history` append-only, keyed (snapshot, feature, revision,
phase) — "later development is a new event, never an update"; the logger takes
`time_unix_nano`, `trace_id`, `span_id` as parameters, never generating them
(R4: "a logger that invents its own time cannot be tested");
`Determinism_verifier` — two runs at one world must be byte-equal (HZ-DET-01).
Wiki: `last_verified` / `verified_by` / `next_review` — a fact is verified *at*
a date and decays (E9 currency: "decay computed, never stored"); `created`
backfilled from git's first-commit date, "absence is reported, not faked" (PKM
spec §3, R16); the render baseline's pinned digests, with re-baselining as the
named re-derivation living outside the battery (F3); `as_of(c) =
build(checkout c)` (HW.6.6.1) — the object half that S33 keeps.

### Signature sketch

```ocaml
module World : sig
  type t = {
    snapshot : Digest.t;        (* the frozen reference *)
    revision : string;          (* the candidate's git revision *)
    verifier : string;          (* tool name + version, "" when n/a *)
    date : string;              (* R16: from the environment, never invented *)
  }
  val equal : t -> t -> bool
end

(* The promotion sketch: the world as a phantom parameter. A cross-world
   comparison does not compile — the S27 no-widen move, and S33's
   ordering-witness move, applied to evidence. *)
module Judgment : sig
  type 'w t
  val derive : world:World.t -> subject:string -> payload:string -> 'w t
  val compare : 'w t -> 'w t -> [ `Equal | `Divergent of string ]
  (* deliberately NO  val transport : 'w t -> 'v t  *)
end

module Store : sig
  val record : World.t -> key:string -> payload:string ->
    (unit, [ `Replay_divergent ]) result          (* R3: fiber functionality *)
  val lookup : World.t -> key:string -> string option
  (* lookup at w' of a judgment recorded at w <> w' is None BY KEYING,
     not by filtering: the world is part of the key, so the wrong world
     is a different key — absence, never substitution (HZ-FIX-02). *)
end
```

### Laws

- **L40.1 world-complete keys** every stored judgment's key includes its
  world — checkable as a census over the store schema (the S36 pattern
  applied to key shapes)
- **L40.2 fiber functionality** `record w k p` then `record w k p′` with
  `p′ ≠ p` is `` `Replay_divergent `` — R3, read fiber-wise; one world, one
  key, at most one payload
- **L40.3 intra-world determinism** deriving twice at `w` is byte-equal —
  `Determinism_verifier`'s law, named as the fiber's own coherence
- **L40.4 no transport** `lookup w′ k` for a judgment recorded at `w ≠ w′` is
  `None` — and after the phantom promotion, a cross-world `compare` does not
  compile
- **L40.5 monotone decay** staleness of a judgment is monotone in the distance
  from its world's date: `next_review` can only arrive; a verified fact never
  re-freshens without a new act of verification (the overdue ordering of
  HW.8.2.2, now a law rather than a sort key)

### Discharge

| Law | Rung | Tool |
|---|---|---|
| L40.2 | 2 | landed: `test_evidence_store`'s replay-rejection legs, cited as the instance |
| L40.4 | **5** / 2 | the phantom-world promotion (cross-world comparison unrepresentable); until then, the fixture-corruption fuzz (120 fixtures) and the wrong-snapshot absence leg |
| L40.3 | 2 + chaos | the determinism verifier's double-replay, with the chaos layer driving variance — honestly a self-differential, not an oracle differential, and recorded as such |
| L40.1 | 2 | census differential against the schema (S36 machinery) |
| L40.5 | 2 | property over synthetic date sequences plus a mutant that lets a stale fact re-freshen on read |

### Scorecard

| Criterion | Score | Justification |
|---|---|---|
| Beauty | 4 | one index law explains six keying disciplines, R16, and the wiki's decay model; the S33 complement (objects transport, judgments re-derive) is a named duality; thin category theory costs a point |
| Flexibility | 5 | σ = 0: a new judgment kind (a lint receipt, a doc-coverage snapshot) is a new fiber family under the same key law; nothing existing is edited |
| Utility | 5 | kills the worst surviving class: stale evidence worn as fresh — the PYTHONPATH hole R11 records ("unpinned traces under the frozen digest") was exactly a world-transport violation; Δ ≥ 1 with L40.4's rung-5 promotion |
| Navigability | 3 | the world axis is the temporal chart: as-of, timeline, and the overdue queue are its neighbourhoods; it bounds no click depth |
| Verifiability | 4 | floor 2; one headline promotable to 5; the self-differential honesty is stated rather than dressed up |

### Subsumes or strengthens

Strengthens **S33** (adds the negative half its functoriality needs to be
safe), **E9**, **E23**; unifies **R3 + R16 + HZ-FIX-02 + HZ-L3-01 +
HZ-DET-01** as one law family; gives the zigvm lineage's "pinned oracle"
discipline (R14) its mathematical name. Not on any candidate list this pass
was handed.

## 8. S41 · Diagnosis is the kernel of the repair map

### Identity

Failure states `F`, repair procedures `X`, and the repair assignment
`fix : F → X`. A diagnostic vocabulary `D` with `classify : F → D` is
**adequate** when `fix` factors through it (`∃ f̂ : D → X, fix = f̂ ∘
classify` — same diagnosis, same repair) and **efficient** when `f̂` is
injective (different repairs, different diagnoses — no conflation). Adequate
and efficient together say `D` *is* the kernel partition of `fix`: the
diagnostic type is not a taxonomy of what went wrong but the **quotient of
failures by what fixes them**. Every "distinct diagnosis" decision in both
halves of the system is an instance of keeping this factorisation exact.

### Where it lives

Harness: `of_capture_failure` pairs each of seven failure constructors with
its own `~fix` string (`fractal_diagnostic.ml` — the factorisation written out
by hand); gospel-lint's verdict separation — rejected ≠ not-checkable ≠
unavailable, three exits, three repairs (fix the contract / fix the spec /
provision the tool — R3, HZ-L3-01); `Blocked` vs `Unmapped` — "we tried and
could not" vs "we never looked", provision vs schedule
(`parity_algebra.ml`); the origin axis itself — "only the second one tells you
where to go looking" (`fractal_diagnostic.ml`); `UNANALYSED` as the honest
default whose repair is "add the hazard" (R6). Wiki: dead link ≠ dead anchor ≠
ambiguous reference — "three distinct diagnoses, because three distinct
fixes" (`[[Unified domain ontology]]` I4; `hermes_wiki.mli`: "a dead link
wants a target, a dead fragment wants a heading"); `Drifted` ≠ `Edited_since`
(investigate the render vs re-pin the source); defect ≠ notice (refuse vs
report — two response classes, R7's split).

### Signature sketch

```ocaml
module Triage (F : sig type failure end) : sig
  type diagnosis
  type repair = { action : string; owner : [ `Author | `Operator | `Harness ] }

  val classify : F.failure -> diagnosis
  val repair : diagnosis -> repair          (* f-hat: TOTAL on diagnoses *)

  (* The two factorisation checks, executable: *)
  val adequate : (F.failure * F.failure) list -> (F.failure * F.failure) list
      (* pairs with equal diagnosis but unequal repair: always [] *)
  val conflated : (F.failure * F.failure) list -> (F.failure * F.failure) list
      (* pairs with unequal repair but equal diagnosis: always [] *)
end
```

### Laws

- **L41.1 adequacy** `classify a = classify b ⟹ fix a = fix b` — the repair
  is a function of the diagnosis
- **L41.2 no conflation** `fix a ≠ fix b ⟹ classify a ≠ classify b` — stated
  separately from L41.1 although it is the contrapositive shape, because its
  *mutant* differs: conflation mutants are the ones with a landed precedent
  (the dead-anchor/dead-link mutant that "passed everything" and exposed a
  one-directional pin — `[[Unified implementation approach]]` §4)
- **L41.3 total repair** every diagnosis renders a non-empty `fix` — the
  `~fix` field discipline of `Fractal_diagnostic.make`, promoted from
  convention to smart constructor
- **L41.4 severity independence** `classify` is invariant under the S37
  grading: diagnosis is about origin and repair, severity about consequence;
  the two project from one record and neither determines the other ("where a
  defect enters. Deliberately not severity" — `fractal_diagnostic.ml`)

### Discharge

| Law | Rung | Tool |
|---|---|---|
| L41.1 | 2 + 1 | property over generated failure pairs; Gospel states the factorisation on the `.mli` |
| L41.2 | 2 | the conflation-mutant battery: one mutant per adjacent diagnosis pair (link/anchor, Blocked/Unmapped, Drifted/Edited_since), each predicted to die in the named leg |
| L41.3 | 2 → 5 | today a field convention; a non-empty-string smart constructor makes the empty fix unrepresentable |
| L41.4 | 2 | property: permuting severities leaves every classification fixed |

### Scorecard

| Criterion | Score | Justification |
|---|---|---|
| Beauty | 4 | a two-equation factorisation explains a dozen separately-argued "distinct diagnosis" decisions across both halves; elementary mathematics, honestly priced |
| Flexibility | 4 | σ = 0 for a new failure mode with an existing repair; a genuinely new repair forces the diagnosis type to grow — and L41.2's mutant is what makes *forgetting* to grow it loud |
| Utility | 4 | kills the conflation class, which has a documented live catch in this repository's own history; Δ = 1 (L41.3's promotion) plus I4 moving from per-feature prose to one law family |
| Navigability | 2 | the diagnosis lattice is a chart of the failure space and the `owner` field routes worklists; no reader metric moves |
| Verifiability | 4 | floor 2 with the strongest mutation story in this document — the killer legs are named per pair in advance |

### Subsumes or strengthens

Strengthens **I4**, **A5**, **F3**'s verdict split, gospel-lint's triage, and
**R6** (a diagnostic naming no hazard is precisely a failure whose repair is
unassigned — `UNANALYSED` is L41.3's honest boundary). Not on any candidate
list this pass was handed.

## 9. S42 · The law register — laws as data, criteria as derived gauges

### Identity

**S36 instantiated at the meta-level: the corpus of laws itself becomes a
reconciled register.** One row per law: id, statement, structure (S-number),
family, claimed rung, discharging artifact (test executable, `.mli`, solver
leg, baseline leg), bound (for rung 4). Derived checks close the loop: every
cited artifact exists (the `missing_files` pattern); every claimed rung is
consistent with its artifact kind (a Gospel citation cannot claim 5; a solver
leg claims 4 and names its bound); the published scoreboard equals the
computed one. Then — and only then — the five criteria of
`[[Unified deep structures]]` §1 become **derived gauges** over the unified
structure rather than judgments applied to proposals: the verifiability floor
is a query (min rank, law-granular `system_grade`); Δ is the histogram
difference between commits; ρ is countable per structure once corollary edges
are rows; σ is measured from git against named extension exercises. This is
the sharpened acceptance of the candidate "the five criteria as measurable
functionals": measurable **as gauges over a law register**, with §10.4
guarding what gauges may never do.

### Where it lives

Harness: `Formal_coverage` is this structure at *component* granularity — the
strength type, anchored citations ("the test suite stats them"),
`intent`/`reconcile` (the RFC 9315 pattern its header names); the law register
is the same discipline pushed down to law granularity. Wiki: the ~78-law
tables and §9 scoreboard of `[[Unified functional algebra]]` — hand-counted
today, with the four smells maintained by re-reading; the criteria table of
`[[Unified deep structures]]` §1 — proxies defined, computed nowhere.

### Signature sketch

```ocaml
module Law_register : sig
  type rung = int  (* 0..5, Formal_coverage.rank's scale *)

  type row = {
    id : string;                (* "L27.1", "A5.2", "L36.2", ... *)
    statement : string;
    structure : string;         (* "S27" ... "S42", or "-" *)
    family : string;            (* the algebra's A..G, or the register area *)
    claimed : rung;
    artifact : string;          (* path or executable name; must exist *)
    bound : string;             (* "" unless claimed = 4; then mandatory *)
  }

  val rows : row list
  val missing_artifacts : unit -> string list        (* S36: anchored *)
  val rung_violations : unit -> string list          (* claim vs artifact kind *)
  val histogram : unit -> (rung * int) list          (* the scoreboard, computed *)
  val smells : unit -> row list      (* could-be-stronger, by artifact kind *)
  val delta : previous:(rung * int) list -> (rung * int) list
end
```

### Laws

- **L42.1 anchored citation** `missing_artifacts () = []` — every law's
  discharging artifact exists on disk or in the suite inventory
- **L42.2 rung honesty** `claimed ≤ ceiling (kind artifact)`, and `claimed = 4
  ⟹ bound ≠ ""` — a bounded-model claim without its bound is a violation, not
  a style issue
- **L42.3 scoreboard = query** the histogram published in
  `[[Unified functional algebra]]` §9 equals `histogram ()` — an S36 residue
  between a document and a computation, the same shape as the render baseline
- **L42.4 ratchet on the floor** the count at rung 0 is non-increasing across
  commits except by explicit new-law addition — the Declared gap count becomes
  ratchetable (HW.10.2.1's mechanism, applied to laws)

### Discharge

| Law | Rung | Tool |
|---|---|---|
| L42.1 | 2 | the `missing_files` pattern, landed in `Formal_coverage`, instantiated per row |
| L42.2 | 2 | property over the row list; mutant: a row claiming 5 with a test-only artifact must be flagged |
| L42.3 | **3** | a generated block in the algebra page (`generated: true` discipline) or a differential leg that fails on drift — the render-baseline pattern applied to a table |
| L42.4 | 2 | the ratchet check against the recorded previous histogram |

### Scorecard

| Criterion | Score | Justification |
|---|---|---|
| Beauty | 3 | no new mathematics — deliberately: it is S36 at the meta-level, and it scores for economy of reuse, not novelty |
| Flexibility | 4 | σ = 0: a new law is a row; a new gauge is a query |
| Utility | 5 | the scoreboard, the four smells, Δ and the floor stop being hand-maintained — which is what makes every *future* deep-structures pass cheap to judge; the criteria's pass-marks become computable |
| Navigability | 3 | laws become a queryable chart ("every rung-0 law in Build" is one query away once rows surface as data) |
| Verifiability | 4 | floor 2; L42.3 rides the strongest landed pattern in the repository |

### Subsumes or strengthens

Extends **`Formal_coverage`** from component to law granularity; makes
`[[Unified functional algebra]]` §9 and the four smells computed; depends on
**S36** (it is its instance) and feeds every scorecard in this document.
Accepted from the candidate list *in this form only* — see §10.4 for the form
that is rejected.

## 10. Rejected for cause

A rejected structure is information. Each of these is tempting from inside
this very document, and each fails a specific admissibility property, a
mandatory rule, or the criteria themselves.

### 10.1 The level identification — the R9 near-miss, dissected

**The temptation.** Both the evidence fractal (L0–L6) and the corpus/runtime
hierarchies are graded trees with roll-up. S39 exhibits them as instances of
one coverage theory. Surely the last step is a level-preserving functor —
L0↔U0(realm), L1↔U1, L3 contract ↔ U3 document / the wiki `claim` type, so
that one dashboard, one roll-up and one vocabulary serve both? The unified
level lattice of `[[Unified fractal ontology]]` §1 even supplies the U-column
to line up against.

**Why it must be rejected, three independent ways.**

1. **It transports a law that is false.** The two sites have *opposite* empty-
   cover policies (S39, L39.3). On the corpus site, a childless node is a
   healthy leaf; on the evidence site, a required node with no children is
   `Unmapped` — and returning the join's identity there is the exact
   vacuous-truth bug `parity_algebra.ml` names as its reason to exist and
   `test_parity_algebra` pins ("an empty required node is unmapped, not
   verified"). Any level identification silently ports one policy onto the
   other site. The system already contains the counterexample to its own
   tempting generalisation.
2. **LX has no image.** `LX_control` is documented in `fractal_diagnostic.ml`
   as *not* a level of the evidence chain — it is the machinery that builds
   the chain. A level-preserving identification must either drop it (lossy) or
   assign it a corpus level, which files control-plane events as evidence
   findings — the precise confusion R9 forbids, and the reason S38 proposes
   splitting `LX_control` out of the variant rather than papering over it.
3. **It discharges nothing.** Every equation the identification suggests is
   already stated, stronger, inside one side ("verified(n) iff children",
   L27.1), and every *new* sentence it produces is false on its face ("a wiki
   page with no children is Unmapped"). A structure that adds no law a tool
   can kill a mutant with is a re-description — the same criterion that
   rejected the topos re-description in the first pass, §12 there.

**Verdict.** Unify as S39 does: one module type, two instances, zero arrows
between them — and the zero is an S38 catalogue row, not an oversight.

### 10.2 One global severity carrier

**The temptation.** After S37, all four chains are "the same" bounded chain
with keep-worst join. Merge the carriers: one `type level = int`, one `worst`,
one solver suite; alerts, verdicts, severities and strengths become views of
one scale.

**The failure.** The rank isomorphisms would become *coercions*: `alert →
verdict` would be the identity function, and R5 violations would typecheck.
The entire content of the two-lattice law is that the isomorphism **exists
mathematically and must not exist syntactically** (`test_smtml_alerts`, in its
own words). A shared *schema* (S37's functor) is admissible — instances share
proofs, not values. A shared *carrier* is the vulnerability itself. The
nuance that proves the rule: OTel severity numbers *are* a shared numeric
scale, and the design permits exactly one direction — outward into log
records (R4) — while the arrow back from telemetry into any verdict is an S38
absence. P4 failure; rejected.

### 10.3 The evidence store as a CRDT over the mesh

**The temptation.** Verdicts form a join-semilattice (S37), evidence is
collected concurrently, and zenoh seams exist (`formal_coverage.mli`). So let
replicas merge receipt sets by semilattice join and converge — the
first pass already rejected CRDTs *for documents*; surely receipts, being
lattice-valued, are the safe case?

**The failure.** The store's defining law is the opposite of conflict
resolution: a same-key/different-payload replay is **refused** (R3), because
two payloads under one key means the apparatus is broken, not that a merge
policy is wanted. A CRDT converges *up to the merge function*; the store's
value is that it never needs one — byte-functionality per key is what makes a
receipt quotable as evidence (P1 at the evidence layer). And the seam boundary
is already law: "the mesh carries observation/advice, never authority"
(`formal_coverage.mli`). The rejection replicates across sites exactly as the
document-CRDT rejection did — which is itself weak evidence *for* S36/S40:
the write-side residue must refuse, everywhere. Rejected on R3 and P1.

### 10.4 Gauge-driven promotion — the trap inside S42

**The temptation.** Once S42 computes priority-like gauges (Δ, the floor, the
histogram), close the loop: let a gauge flip a register row's readiness, gate
a merge on a beauty score, or auto-schedule the next structure by ρ.

**The failure.** A gauge is telemetry about the system (LX-plane); readiness
and credit are evidence-plane judgments. Flowing a score into a status is the
alert→verdict arrow one level up — an S38 absence, and the derived-status
discipline (S36) already says what may flip a row: a **probe of presence**,
never a scalar of merit. `Feature_register.priority` today orders work and
grants nothing; that is the correct and only role for every S42 gauge. This
rejection is recorded to guard this document's own proposal, exactly as the
first pass recorded the free-monad trap its criteria kept rediscovering.

## 11. Update map

The synthesis implies edits to the ten unified documents and the plan. **None
are made here**; this map guides the later documentation pass. One row per
document; section named; one line per edit.

| Document | Section | Edit |
|---|---|---|
| `unified-deep-structures.md` | §2 index | add a pointer row: "continued as S36–S42 in `[[Unified system synthesis]]`", renumbering nothing |
| `unified-deep-structures.md` | §15 misses | annotate the first miss: S36 exhibits the differential *gate* as a reconciliation instance, while the canonical-serialisation theorem stays primitive — the miss narrows, it does not close |
| `unified-functional-atlas.md` | §7 `Verdict` | note that S18's `combine` is an S37 instance whose empty policy is site-declared, citing the vacuous-truth leg |
| `unified-functional-atlas.md` | §10 rejections | add the global-severity-carrier rejection (§10.2 here) so the atlas's rejection table stays the single place readers check |
| `unified-domain-ontology.md` | §0 modal strength | add one line: the preference order has an executable form — S36's `status`/`residue`, probe over declaration |
| `unified-domain-ontology.md` | §2b categorical reading | beside "the adjunction we deliberately do not have", add the co-presentation paragraph: the absent arrows are S38 catalogue rows |
| `unified-functional-algebra.md` | §0 ladder | note that chain-lattice solver legs are generated from one S37 schema rather than hand-mirrored per lattice |
| `unified-functional-algebra.md` | §9 scoreboard | mark the histogram and the four smells as future S42 queries (`generated: true` block), with L42.3 as the drift gate |
| `unified-feature-set.md` | §7 verification family | add the S36 row (unified reconciliation core, HW.8.2.7) beside the ratchet and defects-vs-notices rows |
| `unified-feature-set.md` | §8 non-set | cross-reference §10 here: two exclusions (severity carrier, evidence CRDT) now carry structure-level causes |
| `unified-implementation-approach.md` | §1 T1 | extend T1 with L38.1: every refusal lives at a visible seam, and the seams are catalogued (`Absent_arrow.absences`) |
| `unified-implementation-approach.md` | §2 module plan | add rows: `Reconcile` (S36), `Graded_chain`+`Solver_leg` (S37), `Absent_arrow` (S38), `Law_register` (S42) |
| `unified-implementation-approach.md` | §7 honest bounds | add the emptiness bound: absent arrows are never solver-provable; the seam plus the structure suite is the whole guarantee |
| `unified-mathematical-structures.md` | §1 row 8 | annotate the join-semilattice row with the grading and the per-site empty policy (S37), and the min-meet dual (system floor) |
| `unified-mathematical-structures.md` | §4 central theorem | add the demarcation: S36 generalises the *gate* (pinned vs recomputed with residue); the serialisation requirement remains the primitive it rests on |
| `unified-fractal-ontology.md` | §4 modal strength | add the executable-form pointer (S36) mirroring the domain-ontology edit, so the analytical and normative tables stay aligned |
| `unified-fractal-ontology.md` | §1 level lattice | add a caution note: the U-levels and the evidence L-levels admit no identification (§10.1 here; R9) — the lattice compares tools, it does not map fractals |
| `unified-fractal-atlas.md` | §2 control-flow spectrum | one line: every viable gate position in the spectrum is an S36 equalizer (declared vs derived at that seam), which is *why* Notion's no-build-step topology has nowhere to stand one |
| `unified-fractal-algebra.md` | F6 verification family | annotate the family laws with their synthesis instances: the gate law → S36, the verdict merge → S37, determinism (L3.5) → S40's L40.3 |
| `unified-fractal-algebra.md` | §7 family-law tally | recount after the S36/S37 annotations so "Hermes holds 24" cites law ids rather than a hand count (feeds S42) |
| `features-audit-implementation-plan.md` | §7.8 HW.8 register | add the HW.8.2.7 row (unified reconciliation core — §13.4 here) to the LIFECYCLE table |
| `features-audit-implementation-plan.md` | §8.0.8 | add HW.8.2.7's law text in the catalogue's short form |
| `features-audit-implementation-plan.md` | §10 verification regime | note the generated S37 solver-leg schema as the standard shape for any future lattice |
| `features-audit-implementation-plan.md` | §12 honest bounds | add the two honesty items this pass introduces: emptiness is unprovable (S38), and the determinism leg is a self-differential (S40) |

## 12. Implement first — the top two

Ranked by score sum, then independence, then cost — the first pass's rule.

**1 · S36, the reconciliation pair — total 21.** Independent, and the
cheapest structure in this document relative to what it retires: eight live
disciplines become instances of one functor, the two landed registers become
its differential fixtures (their outputs are the oracle for the instance leg),
and the headline law reaches rung 5 by the same abstraction move S27 proved
out (`status` as the only reader, mirroring no-`widen`). It is also the
machinery S42 needs, so building it first makes the criteria measurable —
which every later pass, including the documentation pass this file's §11
directs, benefits from. Worked in full in §13.

**2 · S40, world-indexed judgments — total 21, second on cost.** Independent
and highest-utility (the stale-evidence class is the one H-1 realisation
class with a documented near-miss in R11's history), but its rung-5 promotion
(phantom worlds) touches store and comparator signatures, which is a wider
refactor than S36's functor. Its cheap first tranche is honest and useful on
its own: the world-completeness census (L40.1) and the wrong-world absence
leg (L40.4's rung-2 form) land on the S36 machinery — a second reason S36
goes first.

**Ranked below, with reasons.** S38 and S37 (19 each): S38's two promotions
are surgical and high-value but its catalogue wants S36's anchor checking;
S37 is nearly free (two landed suites become one schema) and should ride
along with whichever structure first adds a chain. S39 (19) depends on S37's
fold and adds the Site-B wrapper. S42 (19) depends on S36 outright. S41 (18)
is worth doing opportunistically, one conflation mutant at a time.

## 13. Worked exemplar — S36 as `Reconcile`

### 13.1 The complete `.mli`

The block below is the module's real interface, INCLUDED rather than
copied (HW.9.2.1): its denotation is the file, so the exemplar cannot
drift from the code it exemplifies. It was a hand-copy until 2026-08-09,
and it had already rotted — the copy still said "PROPOSAL. Nothing in
this interface is implemented" about a module that is shipped and
probe-verified.

```literalinclude modules/hermes_wiki/src/reconcile/reconcile.mli lang=ocaml
```

### 13.2 The complete law list

| Law | Statement | Rung | Discharging tool |
|---|---|---|---|
| L36.1 preference | `obs k ↓ ⟹ status t k = obs k` | **5 / 2** | the abstract `t`: no declared-claim accessor exists, so preferring a declaration is unwritable; the equation itself by property leg |
| L36.2 residue iff | `k ∈ residue t ⟺ decl k ↓ ∧ obs k ↓ ∧ decl k ≠ obs k` | **4 + 2** | smtml over finite maps (≤ 6 keys, ≤ 4 claims): negation `unsat`, sanity `sat` — **bounded encoding, evidence not proof**; property leg both directions |
| L36.3 fail-closed | `decl k ↑ ∧ obs k ↑ ⟹` row refused at `register`; `unknown` names every foreign key | 2 | property leg + the ghost-subject leg (mirrors `Formal_coverage.reconcile`) |
| L36.4 write functionality | duplicate key at `register` is a refusal, never a silent override | 2 | property leg; the landed `test_evidence_store` replay pattern as the model |
| L36.5 non-vacuity | `status t k ↓ ∧ status t k ≠ Some v ⟹ residue (inject t k v) ≠ []` | 2 | the inject leg — the register's own residue is proven able to fire |
| L36.6 snapshot coherence | after `snapshot`, `status`/`residue`/`report` are pure reads: two reads agree byte-for-byte | 2 | double-read leg (the S40 fiber-determinism law, locally) |
| L36.7 residue determinism | `residue` and `unknown` are sorted by `compare_key`: one serialisation, pinnable | **5** | the sorted return type discipline (L27.6's move); P1 holds |

### 13.3 Test plan

**Suite** `test_reconcile.ml`, four legs plus the mutation battery.

1. **Law leg (property).** Generate registers of 1–30 rows over a small claim
   alphabet with random declaration/probe presence and random agreement.
   Check L36.1–L36.7 per generated register, both residue directions
   represented by construction (declared-ahead and declared-behind rows are
   both generated).
2. **Solver leg (smtml, bounded).** Encode `decl`, `obs` as partial maps over
   ≤ 6 keys and ≤ 4 claims; assert the negation of L36.2's biconditional and
   require `unsat`; include the sanity-`sat` leg so the encoding can never
   pass vacuously — the `test_smtml_lattice` pattern.
3. **Instance leg (differential, the oracle move).** Re-express two landed
   registries as `Reconcile.Make` instances over fixtures:
   `Feature_register` rows (key = feature id, claim = readiness, probe =
   `derived`) and `Gap_plan` items (key = item id, claim = state). The
   instance's `residue` must agree **row for row** with the landed
   `stale_declarations` outputs on the same fixtures. The landed code is the
   frozen oracle; the functor is the candidate — the harness's own
   discipline, applied to its own refactor.
4. **Register leg.** `Feature_register.status` for HW.8.2.7 must agree with
   the live probe, and `test_feature_register` fails on disagreement.

**Mutation legs.** Five mutants, each with its killer named in advance.

| # | Mutant | The check that kills it |
|---|---|---|
| **M1** | *The trusting register.* `status` returns the declaration even when the probe answered. | **L36.1 property leg**: any generated row with probe ≠ declaration fails immediately; the instance leg additionally diverges from `Feature_register.status` on every stale fixture row. |
| **M2** | *The one-eyed residue.* `residue` reports declared-ahead rows (declared Built, probe says absent) but drops declared-behind rows (declared Open, probe says present). | **L36.2 both-direction leg** — the generator plants both kinds; the landed precedent is the dead-anchor mutant that survived a one-directional pin, so this leg exists precisely because that class is real. |
| **M3** | *The vacuous reconcile.* `unknown` returns `[]` when the claimed list names a key the register lacks. | **L36.3 ghost-subject leg**: a claim about a ghost key must be named; mirrors `Formal_coverage.reconcile`'s fail-closed rule ("unknown subjects are drift too"). |
| **M4** | *The optimistic default.* `status` of a key with neither declaration nor probe returns a "fine" default instead of the row being refused at `register`. | **L36.3 + L36.4**: registration of the neither-row must be an `Error`; if the mutant instead sneaks the default in at read time, the law leg's `status = None` check on absent keys fails. |
| **M5** | *The silent second write.* `register` accepts a duplicate key, last row wins. | **L36.4 leg**: duplicate registration must be a refusal; the model is the evidence store's replay rejection, and the leg quotes it. |

Mutation yield target: 5 written, 5 killed, killers predicted — the same
convention as the S27 exemplar, because a law without a predicted killer is a
law nobody has confirmed works.

### 13.4 The feature-register row it would add

| Field | Value |
|---|---|
| `id` | `HW.8.2.7` |
| `area` | `Lifecycle` |
| `name` | `Unified reconciliation core (declared vs derived residue)` |
| `law` | `status prefers the probe BY CONSTRUCTION (no declared-claim accessor exists); residue iff both defined and differing, both directions; unknown claims are drift, fail-closed; duplicate registration refused; residue demonstrably non-vacuous (inject)` |
| `utility` | 3 |
| `criticality` | 4 |
| `sources` | `[ Own ]` — the RFC 9315 declare/validate/observe/report pattern, already cited by `formal_coverage.mli`, generalised |
| `gates` | `[ "HW.10.2.1" ]` — the ratchet consumes residue counts; a monotone gauge needs a deterministic residue first |
| `declared` | `Ready` — no blocker: every instance's inputs (`features`, `items`, `schema_gaps`, the baseline lists) exist today |
| `priority` | `3 × 4 + 2 × 3 + 1 = 19` |

In the register's own syntax:

```ocaml
f ~src:[ Own ] ~gates:[ "HW.10.2.1" ]
  "HW.8.2.7" Lifecycle "Unified reconciliation core (declared vs derived residue)"
  "status prefers the probe BY CONSTRUCTION; residue iff both defined and\n\
   differing, both directions; unknown claims are drift, fail-closed;\n\
   duplicate registration refused; residue demonstrably non-vacuous"
  3 4
  ~derived:(fun () ->
    (* live probe: a fixture register with an injected disagreement fires
       its residue, and status prefers the probe over the declaration *)
    try
      let open Reconcile_fixture in
      residue (inject fixture key_a claim_divergent) <> []
      && status fixture key_b = probe_answer_b
    with _ -> false)
  Ready
```

Criticality 4, not 5: a drifted registry misleads the *planner*, where a
stale incremental build (S27's row, criticality 5) silently corrupts the
*product*. The register weights silent wrongness highest, and this row's
wrongness is loud one hop later — at the first probe disagreement — which is
exactly one hop too late, and the honest score for that is 4.

## 14. What this pass did not find

**No structure subsumes the canonical-serialisation theorem.** S36 exhibits
the differential *gate* as a reconciliation instance, but the theorem it
rests on — a digest is a statement about content only when the serialisation
is canonical (`[[Unified mathematical structures]]` §4) — remains the
primitive under everything here, exactly as the first pass found. Two passes
converging on the same bedrock is evidence it is bedrock.

**No structure unifies the control laws.** Homeostasis's Lyapunov descent,
flap detection and circuit breaking are genuinely control theory, not
evidence theory; this pass touches them only where they meet the evidence
plane (S37's chain, S38's absent arrow). A future pass that finds the control
plane's own deep structure — perhaps the convergence loop as a contraction
with a certified measure — would complete a triptych this one deliberately
leaves open.

Cross-references: `[[Unified deep structures]]` · `[[Unified functional atlas]]` ·
`[[Unified domain ontology]]` · `[[Unified functional algebra]]` ·
`[[Unified feature set]]` · `[[Unified mathematical structures]]` ·
`[[Unified implementation approach]]` · `[[Meta-unification]]` ·
`docs/hermes/mandatory-rules.md` · `docs/hermes/feature-ontology.md` ·
`docs/hermes/specs/2026-08-09-pkm-longterm-architecture.md`.

Part of [[Knowledge fractal map]].

