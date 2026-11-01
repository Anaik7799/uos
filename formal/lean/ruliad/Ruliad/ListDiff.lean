/-
# Ruliad.ListDiff — the `length_diff` lemma Mathlib does not have

Two gaps in this library were blocked on one missing lemma: that removing a
sub-multiset takes exactly its length off the total,

  `l.Subperm g → (g.diff l).length = g.length - l.length`.

Neither Mathlib nor Batteries states it at `v4.35.0` — `List.diff_sublist` gives
only an inequality. Proved here, which closes the exact edge-count identity in
`Ruliad.Hypergraph` and unblocks the rulial-distance metric in `Ruliad.Rulial`.

`List.Subperm l₁ l₂` unfolds to `∃ l, l ~ l₁ ∧ l <+ l₂`, and the two
destructuring lemmas below are the ones that make the induction go through.

Stated over `[BEq α] [LawfulBEq α]`, not `[DecidableEq α]`: that is what
`List.diff` actually takes, and a `DecidableEq`-stated version produces a
different `BEq` instance, so `rw` silently fails to match a `g.diff l` built
from a derived `BEq`. The typeclass has to be the one the function uses.
-/
import Mathlib.Data.List.Perm.Subperm
import Mathlib.Data.List.Dedup

namespace Ruliad.ListDiff

variable {α : Type*}

/-- A sub-multiset's head occurs in the container. -/
theorem subperm_cons_mem {a : α} {t g : List α} (h : (a :: t).Subperm g) : a ∈ g := by
  obtain ⟨l, hp, hs⟩ := h
  exact hs.subset (hp.mem_iff.mpr (List.mem_cons_self ..))

/-- Peeling the head off a sub-multiset relation also erases it on the right. -/
theorem subperm_cons_erase [BEq α] [LawfulBEq α] {a : α} {t g : List α} (h : (a :: t).Subperm g) :
    t.Subperm (g.erase a) := by
  obtain ⟨l, hp, hs⟩ := h
  refine ⟨l.erase a, ?_, hs.erase a⟩
  have := hp.erase a
  rwa [List.erase_cons_head] at this

/-- **Removing a sub-multiset removes exactly its length.** -/
theorem length_diff_of_subperm [BEq α] [LawfulBEq α] : ∀ (l g : List α), l.Subperm g →
    (g.diff l).length = g.length - l.length := by
  intro l
  induction l with
  | nil => intro g _; simp
  | cons a t ih =>
    intro g h
    have ha : a ∈ g := subperm_cons_mem h
    have ht : t.Subperm (g.erase a) := subperm_cons_erase h
    have hlen : (g.erase a).length = g.length - 1 := List.length_erase_of_mem ha
    have hpos : 0 < g.length := List.length_pos_of_mem ha
    rw [List.diff_cons, ih (g.erase a) ht, hlen]
    simp only [List.length_cons]
    omega

end Ruliad.ListDiff
