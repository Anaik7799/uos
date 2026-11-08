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

end UosStacksDescent
