/-
# UosStacksDescent — descent, gluing and the 6-plane cover (20261108-1642)

## Why this file exists

`contracts/rules/20260908-1110-denotational-intent-algebraic-atlas-contract.md`
(`SC-INTENT-ATLAS-001`) already states UOS state as a 10-chart atlas with
transition morphisms, a cocycle condition and a **sheaf gluing property**. Until
now those words were proved over hand-rolled `Nat`/`Bool` in
`formal/lean/Algebraic_Atlas_Intent.lean`, on the 4.33.0 toolchain, with no
Mathlib: the gluing claim was arithmetic that resembled descent rather than
descent.

Mathlib `v4.35.0` is on disk in this package and carries the real thing --
`CategoryTheory.Sites.Descent.{DescentData, IsPrestack, IsStack, Precoverage}`
and `CategoryTheory.FiberedCategory.*` -- with declarations carrying `@[stacks
TAG]` attributes that cite Stacks Project tags directly (`IsStack` is tagged
`026F`). So the vocabulary is reachable here, and `stacksApiReachable` below is
the mechanical proof that it is, not a claim that it is used in anger.

## What is actually proved here, and what is not

PROVED. The descent content of the 6-plane Veil predicate, stated as a gluing
problem over the overlap graph of a cover:

* `glue_of_chain` -- a matching family on the 5 declared overlaps glues to a
  global section. This is why `allSixPlanesEpochAligned` may check 5 pairs and
  still conclude about all 15.
* `chain_link_not_redundant` -- drop ANY ONE of the 5 overlaps and a
  counterexample exists. The cover's overlap graph is a spanning tree: it has no
  slack, so no check in that predicate can be deleted as redundant. This is the
  falsifiability control for `glue_of_chain`; without it, "5 checks suffice"
  would be a claim that cannot fail.
* `singletons_do_not_glue` -- a cover by per-plane declarations with NO declared
  overlaps does not glue. Six planes each asserting their own epoch is not a
  descent datum, which is the precise reason the Veil system needs the Andon
  stop line rather than a per-plane conformance report.
* `ST_16_ratification_cover_glues` & `ST_02_quarantined_events_422_432_437_do_not_descend`
  -- 2-of-4 sovereign model-family ratification (`{codex, agy, claude,
  pi+openrouter+gemini+argon}` + Operator) as a covering condition with
  non-vacuous failure on the quarantined `EV-94..EV-109` events (`422..432`,
  `437`), keeping `admitted_ev_ceiling = 93`.
* `ST_06_lease_cocycle_of_epochs` & `ST_06_broken_cocycle_detects_split_brain`
  -- `sa-plan` lease fencing transitions satisfy the 1-cocycle equation
  $\delta_{01} + \delta_{12} = \delta_{02}$ on monotone epochs, while a stale
  split-brain handover violates the cocycle.
* `ST_14_adjacent_links_glue_to_global_chain` & `ST_14_single_tamper_breaks_chain`
  -- local adjacent `(prev_hash, self_hash)` agreement (`km_chain.ml`) glues to
  global transitive chain integrity across `[0..n]`, and any single middle
  tamper falsifies the global section.
* `ST_11_reconcileRoute_idempotent` & `ST_11_hollow_declaration_is_exact_kernel`
  -- sheafification of declared vs. connected 104-route MCP surfaces is an
  idempotent projector whose kernel is exactly the hollow declarations
  (`declared = true ∧ connected = false`).

NOT PROVED, and not claimed anywhere: no `IsStack` instance for any UOS
pseudofunctor. Building one needs `LocallyDiscrete Cᵒᵖ ⥤ᵖ Cat` for the UOS
chart category plus effectivity of descent, and that is a program (see the
criticality ranking in
`governance/agents/policy/20261108-1642-uos-stacks-descent-criticality-ranking.json`),
not a file. Everything below is finite combinatorics in the shape of descent,
with the category-theoretic statement named as future work.

Axioms: `propext`, `Classical.choice`, `Quot.sound` only (Mathlib's standard
three); no `sorryAx`, no `native_decide`.

Authority NONE. EV ceiling 93; `EV-94..109` `NOT_ADMITTED`; no new EV minted.
-/
import Mathlib.Tactic
import Mathlib.CategoryTheory.Sites.Grothendieck
import Mathlib.CategoryTheory.Sites.Descent.IsStack
import Mathlib.CategoryTheory.FiberedCategory.Fibered

namespace UosStacksDescent

/-! ## 1. The Stacks-tagged Mathlib API is reachable from this package -/

/-- Mechanical reachability of Mathlib's stack API: `IsStack` carries the Stacks
Project tag `026F`. Binding it here is what proves the import resolves; nothing
is instantiated. -/
def stacksApiReachable := @CategoryTheory.Pseudofunctor.IsStack

/-- Likewise for descent data and for fibered categories. -/
def descentDataReachable := @CategoryTheory.Pseudofunctor.DescentData
def fiberedReachable := @CategoryTheory.Functor.IsFibered
def grothendieckTopologyReachable := @CategoryTheory.GrothendieckTopology

/-! ## 2. The 6-plane cover and its overlap graph

A plane is an index; an *epoch assignment* is a local section over each plane of
the cover. A *declared overlap* `(i, j)` is a place where two planes are
required to agree -- in UOS terms, a cross-reference that is actually checked. -/

/-- The six synchronized planes: spec, twin, code, comments, docs/wiki/ZK, memory. -/
abbrev Plane := Fin 6

/-- A local section of the epoch presheaf on each plane of the cover. -/
abbrev EpochFamily := Plane → Nat

/-- The 5 overlaps the Veil predicate actually declares: a chain
`spec–twin–code–comment–wikiZk–memory`. -/
def chainOverlaps : List (Plane × Plane) :=
  [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5)]

/-- A family is *matching* on a set of declared overlaps when the two restrictions
agree on each one. -/
abbrev Matching (E : EpochFamily) (overlaps : List (Plane × Plane)) : Prop :=
  ∀ p ∈ overlaps, E p.1 = E p.2

/-- A family *glues* when it is the restriction of a single global epoch, i.e. all
planes carry the same value. -/
abbrev Glues (E : EpochFamily) : Prop := ∀ i j : Plane, E i = E j

/-! ## 3. Descent over the declared overlaps -/

/-- **Gluing.** A matching family on the 5 declared overlaps descends to a global
section. The chain is connected, so transitivity closes the remaining 10 pairs. -/
theorem glue_of_chain {E : EpochFamily} (h : Matching E chainOverlaps) : Glues E := by
  have h01 : E 0 = E 1 := h (0, 1) (by simp [chainOverlaps])
  have h12 : E 1 = E 2 := h (1, 2) (by simp [chainOverlaps])
  have h23 : E 2 = E 3 := h (2, 3) (by simp [chainOverlaps])
  have h34 : E 3 = E 4 := h (3, 4) (by simp [chainOverlaps])
  have h45 : E 4 = E 5 := h (4, 5) (by simp [chainOverlaps])
  intro i j
  fin_cases i <;> fin_cases j <;>
    simp_all

/-! ## 4. Falsifiability: the cover has no redundant overlap

`glue_of_chain` on its own is the kind of statement that cannot fail -- adding
MORE overlaps keeps it true. The control is the other direction: delete one. -/

/-- The step family that is constant `0` up to plane `k` and `1` after it. It is
matching on every overlap except the one straddling `k`. -/
def stepFamily (k : Nat) : EpochFamily := fun i => if i.val ≤ k then 0 else 1

/-- **No overlap in the chain is redundant.** For each of the 5 declared overlaps
there is a family matching all the OTHER four that does not glue. So the 5 checks
are a spanning tree of the 6-plane cover: minimal and sufficient, not merely
sufficient. -/
theorem chain_link_not_redundant (k : Fin 5) :
    Matching (stepFamily k.val) (chainOverlaps.filter (fun p => p.1.val ≠ k.val)) ∧
    ¬ Glues (stepFamily k.val) := by
  fin_cases k <;> constructor <;> decide

/-- **A cover with no declared overlaps does not glue.** Six planes each
reporting their own epoch is vacuously matching, and says nothing. This is the
formal reason a per-plane conformance report is not a sync proof. -/
theorem singletons_do_not_glue :
    Matching (stepFamily 2) [] ∧ ¬ Glues (stepFamily 2) := by
  refine ⟨by intro p hp; simp at hp, ?_⟩
  intro hg
  have := hg 0 5
  simp [stepFamily] at this

/-- Conversely, the glued families are exactly the constant ones. -/
theorem glues_iff_const {E : EpochFamily} : Glues E ↔ ∃ n, ∀ i, E i = n :=
  ⟨fun h => ⟨E 0, fun i => h i 0⟩, fun ⟨_, hn⟩ i j => by rw [hn i, hn j]⟩

/-! ## 5. ST-02 & ST-16: Provenance Sheaf & 2-of-4 Sovereign Ratification Cover

Per `SC-PROVENANCE-001` (`INV-PROV-05`), a candidate EV claim descends to the
canonical global section only when covered by at least 2 distinct sovereign
model families out of the 4 `{codex, agy, claude, pi+openrouter+gemini+argon}`
plus Operator ratification (`opOk = true`), with matching EV ceiling across the
ratifying cover. -/

/-- The 4 sovereign model families:
0 = codex, 1 = agy, 2 = claude, 3 = pi+openrouter+gemini+argon. -/
abbrev SovereignFamily := Fin 4

/-- Local EV ceiling observed/claimed by each sovereign family. -/
abbrev FamilyCeiling := SovereignFamily → Nat

/-- Which sovereign families have ratified a candidate EV transition. -/
abbrev RatificationMask := SovereignFamily → Bool

/-- Number of distinct model families in `Fin 4` that ratified the claim. -/
def ratifyingFamilyCount (mask : RatificationMask) : Nat :=
  ((List.finRange 4).filter (fun f => mask f)).length

/-- A ratification sieve covers the provenance site iff Operator ratified
(`opOk = true`) and at least 2 distinct sovereign model families ratified. -/
def IsRatificationCover (mask : RatificationMask) (opOk : Bool) : Bool :=
  opOk && decide (ratifyingFamilyCount mask ≥ 2)

/-- Matching condition on the ratifying cover: every pair of ratifying families
agrees on the EV ceiling. -/
def MatchingOnCover (C : FamilyCeiling) (mask : RatificationMask) : Prop :=
  ∀ i j : SovereignFamily, mask i = true → mask j = true → C i = C j

/-- **ST-16 (2-of-4 Sovereign Ratification Gluing).** Whenever `(mask, opOk)` is
a valid ratification cover (`IsRatificationCover mask opOk = true`) and `C`
satisfies `MatchingOnCover C mask`, there exists a common EV ceiling `n` agreed
upon by every ratifying family in the cover. -/
theorem ST_16_ratification_cover_glues
    {C : FamilyCeiling} {mask : RatificationMask} {opOk : Bool}
    (hcov : IsRatificationCover mask opOk = true)
    (hmatch : MatchingOnCover C mask) :
    opOk = true ∧ ∃ n : Nat, ∀ i : SovereignFamily, mask i = true → C i = n := by
  unfold IsRatificationCover ratifyingFamilyCount at hcov
  rw [Bool.and_eq_true, decide_eq_true_eq] at hcov
  refine ⟨hcov.1, ?_⟩
  by_cases h0 : mask 0 = true
  · exact ⟨C 0, fun i hi => hmatch i 0 hi h0⟩
  · by_cases h1 : mask 1 = true
    · exact ⟨C 1, fun i hi => hmatch i 1 hi h1⟩
    · by_cases h2 : mask 2 = true
      · exact ⟨C 2, fun i hi => hmatch i 2 hi h2⟩
      · by_cases h3 : mask 3 = true
        · exact ⟨C 3, fun i hi => hmatch i 3 hi h3⟩
        · exfalso
          have hlen : ((List.finRange 4).filter (fun f => mask f)).length = 0 := by
            simp [List.finRange, h0, h1, h2, h3]
          omega

/-- The quarantined `EV-94..EV-109` events (`422..432` and `437`): injected by a
single foreign writer (`f = 0` spoofed) without 2-of-4 ratification (`count = 1`)
and without Operator ratification (`opOk = false`), claiming `109` while honest
families observe the admitted ceiling `93`. -/
def quarantinedEventMask : RatificationMask := fun f => f.val == 0

def quarantinedEventCeilings : FamilyCeiling := fun f =>
  if f.val == 0 then 109 else 93

/-- Effective global admitted EV ceiling under fail-closed sheaf descent: if the
cover and matching conditions hold on `mask`, adopt `C 0`, otherwise preserve the
canonical baseline ceiling `93`. -/
def admittedCeilingUnderDescent (C : FamilyCeiling) (mask : RatificationMask) (opOk : Bool) : Nat :=
  if IsRatificationCover mask opOk &&
     decide (∀ i j : SovereignFamily, mask i = true → mask j = true → C i = C j) then
    C 0
  else
    93

/-- **ST-02 (Quarantined Events 422-432 and 437 Fail Sheaf Descent).** The
quarantined `EV-94..EV-109` claims neither form a 2-of-4 ratification cover nor
agree across the 4 sovereign families, forcing the descended global ceiling to
remain at `93`. -/
theorem ST_02_quarantined_events_422_432_437_do_not_descend :
    IsRatificationCover quarantinedEventMask false = false ∧
    IsRatificationCover quarantinedEventMask true = false ∧
    (∃ i j : SovereignFamily, quarantinedEventCeilings i ≠ quarantinedEventCeilings j) ∧
    admittedCeilingUnderDescent quarantinedEventCeilings quarantinedEventMask false = 93 := by
  refine ⟨by decide, by decide, ⟨0, 1, by decide⟩, by decide⟩

/-! ## 6. ST-06: `sa-plan` Leases & Effect-Time Fencing as a 1-Cocycle

A lease handover from worker chart `i` (at fencing epoch `e_i`) to worker chart
`j` (at fencing epoch `e_j`) induces a transition increment
`δ_{ij} = (e_j : Int) - (e_i : Int)`. Across any triple `(i, j, k)`, valid
fenced handovers satisfy the 1-cocycle identity `δ_{ij} + δ_{jk} = δ_{ik}` with
strictly positive forward increments. -/

/-- A triple of lease handover increments `(d01, d12, d02)` satisfies the strict
fencing 1-cocycle condition when increments compose additively and each step
strictly advances the fencing token. -/
def LeaseCocycle (d01 d12 d02 : Int) : Prop :=
  d01 + d12 = d02 ∧ d01 > 0 ∧ d12 > 0

/-- Fencing transition between two monotone epochs. -/
def epochTransition (eFrom eTo : Nat) : Int := (eTo : Int) - (eFrom : Int)

/-- **ST-06 (Monotone Fencing Epochs Form a 1-Cocycle).** Any strictly increasing
sequence of `sa-plan` lease epochs `e0 < e1 < e2` satisfies `LeaseCocycle`,
guaranteeing linearizable handover with positive composite progress `d02 ≥ 2`. -/
theorem ST_06_lease_cocycle_of_epochs {e0 e1 e2 : Nat}
    (h01 : e0 < e1) (h12 : e1 < e2) :
    LeaseCocycle (epochTransition e0 e1) (epochTransition e1 e2) (epochTransition e0 e2) ∧
    epochTransition e0 e2 ≥ 2 := by
  unfold LeaseCocycle epochTransition
  omega

/-- **ST-06 Falsifier (Split-Brain Lease Violates the 1-Cocycle).** When a stale
worker attempts to act at epoch `e1` without advancing or when two concurrent
workers claim conflicting target epochs (`d01 = 1, d12 = 0, d02 = 2`), the
1-cocycle condition fails. -/
theorem ST_06_broken_cocycle_detects_split_brain :
    ¬ LeaseCocycle 1 0 2 ∧ ¬ LeaseCocycle 2 (-1) 2 := by
  unfold LeaseCocycle
  omega

/-! ## 7. ST-14: Append-Only SHA-256 Digest Chain (`km_chain.ml`) as a Linear-Site Sheaf

On the linear time site `0 → 1 → … → n`, each ledger entry `k` carries a pair
`(prevHash k, selfHash k)`. Local matching on adjacent overlaps `(k, k+1)` is
equivalent to unbroken integrity across every interval `[i, j]` in `[0, n]`. -/

/-- Local adjacent hash-link condition on `[0..n]`: every entry `k + 1` records
`prevHash (k + 1) = selfHash k`. -/
def AdjacentLinksValid (prevHash selfHash : Nat → Nat) (n : Nat) : Prop :=
  ∀ k < n, prevHash (k + 1) = selfHash k

/-- Global interval integrity: across every sub-interval `[i, j]` (`i ≤ j ≤ n`),
every intermediate step `k ∈ [i, j)` preserves the cryptographic link. -/
def GlobalChainValid (prevHash selfHash : Nat → Nat) (n : Nat) : Prop :=
  ∀ i j, i ≤ j → j ≤ n → ∀ k, i ≤ k → k < j → prevHash (k + 1) = selfHash k

/-- **ST-14 (Adjacent Hash Links Glue to Global Ledger Integrity).** Local
verification of the `n` adjacent overlaps `(k, k + 1)` is necessary and
sufficient for global chain validity across all sub-intervals `[i, j] ⊆ [0, n]`. -/
theorem ST_14_adjacent_links_glue_to_global_chain
    (prevHash selfHash : Nat → Nat) (n : Nat) :
    AdjacentLinksValid prevHash selfHash n ↔ GlobalChainValid prevHash selfHash n := by
  constructor
  · intro hadj i j _ hj k _ hkj
    exact hadj k (Nat.lt_of_lt_of_le hkj hj)
  · intro hglob k hkn
    exact hglob 0 n (Nat.zero_le n) (Nat.le_refl n) k (Nat.zero_le k) hkn

/-- **ST-14 Falsifier (Single Tampered Entry Breaks Global Gluing).** If entry
`2` in a 5-entry ledger has its `selfHash` mutated from `102` to `999` without
updating `prevHash 3 = 102`, the global chain predicate fails. -/
theorem ST_14_single_tamper_breaks_chain :
    let prevHash := fun k => 100 + k - 1
    let tamperedSelf := fun k => if k == 2 then 999 else 100 + k
    ¬ GlobalChainValid prevHash tamperedSelf 4 := by
  intro prevHash tamperedSelf hglob
  have hlink := hglob 0 4 (by omega) (by omega) 2 (by omega) (by omega)
  revert hlink
  decide

/-! ## 8. ST-11: Declared vs. Connected 104-Route MCP Surface Sheafification

A route on the 104-surface `uos-harness` boundary carries a declaration bit
`declared : Bool` and a live dispatch bit `connected : Bool`. A presheaf section
is a *sheaf section* iff `declared = connected` (no hollow declarations and no
undeclared shadow routes). Sheafification projects `(declared, connected)` onto
`(declared && connected, declared && connected)`. -/

/-- Sheafification of a route's `(declared, connected)` status onto the subsheaf
of live-backed declared routes. -/
def reconcileRoute (declared connected : Bool) : Bool × Bool :=
  (declared && connected, declared && connected)

/-- A route pair is a sheaf section when declaration and live dispatch coincide. -/
def IsLiveBackedRoute (p : Bool × Bool) : Bool :=
  p.1 == p.2

/-- **ST-11 (Route Reconciliation is an Idempotent Sheafification Projector).**
`reconcileRoute` always lands in the sheaf of live-backed routes, is idempotent,
and fixes every route that is already live-backed (`declared = connected`). -/
theorem ST_11_reconcileRoute_idempotent (declared connected : Bool) :
    IsLiveBackedRoute (reconcileRoute declared connected) = true ∧
    reconcileRoute (reconcileRoute declared connected).1 (reconcileRoute declared connected).2 =
      reconcileRoute declared connected ∧
    (declared = connected → reconcileRoute declared connected = (declared, connected)) := by
  cases declared <;> cases connected <;> decide

/-- **ST-11 Exact Kernel (Hollow Declarations Are the Exact Kernel Among Declared Routes).**
A declared route (`declared = true`) is annihilated by sheafification
(`reconcileRoute declared connected = (false, false)`) if and only if it is a
hollow declaration (`connected = false`). -/
theorem ST_11_hollow_declaration_is_exact_kernel (connected : Bool) :
    reconcileRoute true connected = (false, false) ↔ connected = false := by
  cases connected <;> decide

end UosStacksDescent
