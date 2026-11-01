/-
# Ruliad.Hypergraph — Wolfram-model hypergraph rewriting

`Ruliad.Multiway` models what the system actually deploys: *string* rewriting.
Wolfram models are **hypergraph** rewriting, and the difference is not cosmetic —
it is where vertex creation, arity, and state identity up to isomorphism live.
This module supplies that substrate.

A state is a list of hyperedges over `Nat` vertices. A rule is a pair of
patterns over pattern variables. Firing a rule removes the matched sub-multiset
and appends the instantiated right-hand side, minting fresh vertices for
variables that occur only on the right.

Multiset semantics matter: two copies of the same hyperedge are two edges, so
matching is `List.Subperm` (sub-multiset) and removal is `List.diff`, not set
difference.

**Finding recorded here:** the deployed `multiway.gleam` dedups states by
syntactic string equality. A hypergraph engine cannot do that — hypergraph
states are only meaningful up to vertex renaming, so two states differing by a
relabelling are the same state and a syntactic dedup would double-count them.
`stepRel_equivariant` below is the property such an engine must have, and the
reason the deployed string model sidesteps a problem it never has to face.
-/
import Ruliad.Core
import Ruliad.ListDiff
import Mathlib.Data.List.Perm.Subperm
import Mathlib.Data.List.Dedup

namespace Ruliad.Hypergraph

open Ruliad

abbrev Vertex := Nat
abbrev Hyperedge := List Vertex
/-- A hypergraph state: a multiset of hyperedges, carried as a list. -/
abbrev State := List Hyperedge

abbrev PatVar := Nat
abbrev Pattern := List (List PatVar)

/-- A Wolfram-model rule: a left pattern rewritten to a right pattern. -/
structure Rule where
  lhs : Pattern
  rhs : Pattern
  deriving DecidableEq, Repr

/-- An assignment of concrete vertices to pattern variables. -/
abbrev Assign := PatVar → Vertex

/-- Instantiate a pattern. -/
def applyPat (σ : Assign) (p : Pattern) : State := p.map (fun e => e.map σ)

/-- Variables occurring in a pattern. -/
def patVars (p : Pattern) : List PatVar := (p.flatMap id).dedup

/-- Vertices occurring in a state. -/
def vertices (g : State) : List Vertex := (g.flatMap id).dedup

/-! ## Matching and firing -/

/-- The instantiated left-hand side occurs in the state as a sub-multiset. -/
def Matches (r : Rule) (σ : Assign) (g : State) : Prop :=
  (applyPat σ r.lhs).Subperm g

/-- Remove the matched edges, append the instantiated right-hand side. -/
def fire (r : Rule) (σ : Assign) (g : State) : State :=
  (g.diff (applyPat σ r.lhs)) ++ applyPat σ r.rhs

/-- Variables appearing only on the right must be mapped to vertices the state
does not already contain: this is hypergraph **vertex creation**. -/
def FreshFor (r : Rule) (σ : Assign) (g : State) : Prop :=
  ∀ v ∈ patVars r.rhs, v ∉ patVars r.lhs → σ v ∉ vertices g

/-- The one-step hypergraph rewriting relation. Being a plain relation, every
theorem in `Ruliad.Core` — Newman included — applies to it unchanged. -/
def StepRel (rs : List Rule) (g g' : State) : Prop :=
  ∃ r ∈ rs, ∃ σ, Matches r σ g ∧ FreshFor r σ g ∧ g' = fire r σ g

/-! ## Arity -/

/-- Instantiation never changes an edge's arity: a binary rule produces binary
edges. This is the invariant a typed hypergraph store depends on. -/
theorem length_mem_applyPat {σ : Assign} {p : Pattern} {e : Hyperedge}
    (h : e ∈ applyPat σ p) : ∃ pe ∈ p, e.length = pe.length := by
  simp only [applyPat, List.mem_map] at h
  obtain ⟨pe, hpe, rfl⟩ := h
  exact ⟨pe, hpe, by simp⟩

/-- A rule whose right-hand side is uniformly `k`-ary produces only `k`-ary
edges. -/
theorem applyPat_uniform_arity {σ : Assign} {p : Pattern} {k : Nat}
    (hp : ∀ pe ∈ p, pe.length = k) : ∀ e ∈ applyPat σ p, e.length = k := by
  intro e he
  obtain ⟨pe, hpe, hlen⟩ := length_mem_applyPat he
  rw [hlen, hp pe hpe]

/-! ## Nothing appears from nowhere -/

theorem vertices_append (g h : State) :
    ∀ v, v ∈ vertices (g ++ h) ↔ v ∈ vertices g ∨ v ∈ vertices h := by
  intro v
  simp [vertices, List.mem_dedup, List.flatMap_append]

theorem vertices_diff_subset (g l : State) :
    ∀ v ∈ vertices (g.diff l), v ∈ vertices g := by
  intro v hv
  simp only [vertices, List.mem_dedup, List.mem_flatMap, id] at hv ⊢
  obtain ⟨e, he, hve⟩ := hv
  exact ⟨e, List.diff_subset g _ he, hve⟩

/-- **Vertex provenance.** Every vertex of the successor state is either a
vertex of the predecessor or the image of a right-hand pattern variable. A
hypergraph step invents nothing it cannot account for. -/
theorem vertices_fire_subset (r : Rule) (σ : Assign) (g : State) :
    ∀ v ∈ vertices (fire r σ g),
      v ∈ vertices g ∨ ∃ w ∈ patVars r.rhs, v = σ w := by
  intro v hv
  rcases (vertices_append _ _ v).mp hv with hleft | hright
  · exact Or.inl (vertices_diff_subset g _ v hleft)
  · right
    simp only [vertices, applyPat, List.mem_dedup, List.mem_flatMap, List.mem_map, id] at hright
    obtain ⟨e, he, hve⟩ := hright
    obtain ⟨pe, hpe, rfl⟩ := he
    simp only [List.mem_map] at hve
    obtain ⟨w, hw, rfl⟩ := hve
    refine ⟨w, ?_, rfl⟩
    simp only [patVars, List.mem_dedup, List.mem_flatMap, id]
    exact ⟨pe, hpe, hw⟩

/-- And a fresh assignment really does produce vertices the state did not have. -/
theorem fresh_vertex_new {r : Rule} {σ : Assign} {g : State}
    (hf : FreshFor r σ g) {w : PatVar} (hw : w ∈ patVars r.rhs)
    (hnew : w ∉ patVars r.lhs) : σ w ∉ vertices g := hf w hw hnew

/-! ## Edge-count arithmetic -/

/-- The surviving edges are a sublist of the predecessor's: firing deletes and
appends, it never rewrites an edge in place. -/
theorem fire_survivors_sublist (r : Rule) (σ : Assign) (g : State) :
    List.Sublist (g.diff (applyPat σ r.lhs)) g := List.diff_sublist g (applyPat σ r.lhs)

/-- Edge-count bound, holding whether or not the rule matched. -/
theorem length_fire_le (r : Rule) (σ : Assign) (g : State) :
    (fire r σ g).length ≤ g.length + r.rhs.length := by
  have hrhs : (applyPat σ r.rhs).length = r.rhs.length := by simp [applyPat]
  simp only [fire, List.length_append, hrhs]
  exact Nat.add_le_add_right (fire_survivors_sublist r σ g).length_le _

/-- **Exact edge accounting.** On a genuine match, the successor has precisely
the predecessor's edges, minus the matched left-hand side, plus the right-hand
side. Every edge is accounted for — nothing is silently created or lost.

This was recorded as a gap in the previous revision for want of a `length_diff`
lemma for `Subperm`; `Ruliad.ListDiff.length_diff_of_subperm` supplies it. -/
theorem length_fire {r : Rule} {σ : Assign} {g : State} (hm : Matches r σ g) :
    (fire r σ g).length = g.length - r.lhs.length + r.rhs.length := by
  have hlhs : (applyPat σ r.lhs).length = r.lhs.length := by simp [applyPat]
  have hrhs : (applyPat σ r.rhs).length = r.rhs.length := by simp [applyPat]
  simp only [fire, List.length_append, hrhs]
  congr 1
  rw [Ruliad.ListDiff.length_diff_of_subperm _ _ hm, hlhs]

/-- A rule with equal-sized sides preserves the edge count exactly: a
length-preserving rewrite, as a theorem rather than an observation. -/
theorem length_fire_eq_of_balanced {r : Rule} {σ : Assign} {g : State}
    (hm : Matches r σ g) (hbal : r.lhs.length = r.rhs.length) :
    (fire r σ g).length = g.length := by
  have hle : r.lhs.length ≤ g.length := by
    have := hm.length_le
    simpa [applyPat] using this
  rw [length_fire hm, ← hbal]
  omega

/-! ## Isomorphism invariance

State states are meaningful only up to vertex renaming. An engine that
canonicalises states needs the step relation to respect renaming; one that
compares states syntactically does not get to assume it. -/

/-- Rename every vertex of a state. -/
def rename (π : Vertex → Vertex) (g : State) : State :=
  g.map (fun e => e.map π)

theorem rename_applyPat (π : Vertex → Vertex) (σ : Assign) (p : Pattern) :
    rename π (applyPat σ p) = applyPat (π ∘ σ) p := by
  simp [rename, applyPat, List.map_map, Function.comp_def]

/-- Matching is renaming-equivariant. -/
theorem matches_rename {r : Rule} {σ : Assign} {g : State} {π : Vertex → Vertex}
    (hπ : Function.Injective π) (h : Matches r σ g) :
    Matches r (π ∘ σ) (rename π g) := by
  unfold Matches at h ⊢
  rw [← rename_applyPat]
  exact h.map (List.map_injective_iff.mpr hπ)

/-- **The equivariance an isomorphism-aware engine must have.** Firing commutes
with renaming on the part that does not involve multiset removal; the `diff`
half needs `π` injective, which is exactly the hypothesis a canonicaliser
supplies and a syntactic dedup cannot. -/
theorem fire_rename_rhs (r : Rule) (σ : Assign) (π : Vertex → Vertex) :
    rename π (applyPat σ r.rhs) = applyPat (π ∘ σ) r.rhs := rename_applyPat π σ r.rhs

/-- Step relation equivariance, as the obligation it is: stated over an
injective renaming, with the `diff` commutation supplied by the caller. -/
theorem stepRel_equivariant {rs : List Rule} {g g' : State} {π : Vertex → Vertex}
    (hπ : Function.Injective π)
    (hdiff : ∀ (r : Rule) (σ : Assign),
      rename π (g.diff (applyPat σ r.lhs)) = (rename π g).diff (applyPat (π ∘ σ) r.lhs))
    (hfresh : ∀ (r : Rule) (σ : Assign), FreshFor r σ g → FreshFor r (π ∘ σ) (rename π g))
    (h : StepRel rs g g') : StepRel rs (rename π g) (rename π g') := by
  obtain ⟨r, hr, σ, hm, hf, rfl⟩ := h
  refine ⟨r, hr, π ∘ σ, matches_rename hπ hm, hfresh r σ hf, ?_⟩
  simp only [fire, rename, List.map_append]
  rw [show (g.diff (applyPat σ r.lhs)).map (fun e => e.map π)
        = rename π (g.diff (applyPat σ r.lhs)) from rfl, hdiff r σ,
      show (applyPat σ r.rhs).map (fun e => e.map π)
        = rename π (applyPat σ r.rhs) from rfl, rename_applyPat]
  rfl

/-! ## Causal invariance for hypergraph rules

Nothing above is special-cased: `StepRel` is a relation, so the whole of
`Ruliad.Core` applies. This is the Wolfram-model causal-invariance criterion. -/

/-- A terminating, locally confluent hypergraph rule set is causally invariant,
and its normal forms are unique. -/
theorem hypergraph_causal_invariance {rs : List Rule}
    (ht : Terminating (StepRel rs)) (hlc : LocallyConfluent (StepRel rs)) :
    Confluent (StepRel rs) := newman ht hlc

theorem hypergraph_unique_normal {rs : List Rule}
    (ht : Terminating (StepRel rs)) (hlc : LocallyConfluent (StepRel rs))
    {a b c : State}
    (hab : Steps (StepRel rs) a b) (hac : Steps (StepRel rs) a c)
    (hb : NormalForm (StepRel rs) b) (hc : NormalForm (StepRel rs) c) : b = c :=
  unique_normalForm_of_newman ht hlc hab hac hb hc

end Ruliad.Hypergraph
