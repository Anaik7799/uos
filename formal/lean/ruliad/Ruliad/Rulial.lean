/-
# Ruliad.Rulial — the ruliad as an object, and why it must be stratified

Everything so far fixes one rule set and studies its multiway graph. The ruliad
is the entangled limit of *all* rule systems applied to *all* initial
conditions. This module is where that object is actually constructed, and where
the construction's unavoidable compromise is proved rather than excused.

`no_universal_encoding` is the load-bearing negative result: **no single type
can injectively encode all rule systems over itself.** Cantor's argument
applies directly. So "the ruliad" is not a `Type`; it is a universe-indexed
family, and every statement about it is relative to an observer's universe.
That is not a modelling shortcut — it is forced.

What *is* constructible: `Slice.{u}`, the ruliad as seen from universe `u`,
being every system with carrier in `Type u` together with every initial
condition; and the category of emulations between systems, which is how rulial
space is navigated. The transfer theorem `Confluent.of_faithful` is the
practical payoff: causal invariance of a complicated rule set can be obtained
by faithfully embedding it in a simple one.
-/
import Ruliad.Core
import Mathlib.Logic.Function.Basic
import Mathlib.Data.List.Dedup
import Mathlib.Order.SymmDiff
import Mathlib.Data.Finset.SymmDiff
import Mathlib.Data.Finset.Card

namespace Ruliad.Rulial

open Ruliad

universe u v

/-! ## Systems and the ruliad slice -/

/-- A rule system: a carrier and a one-step relation. Nothing more is needed —
every theorem in `Ruliad.Core` applies to `step`. -/
structure System where
  Carrier : Type u
  step : Carrier → Carrier → Prop

/-- One point of the ruliad as seen from universe `u`: a system together with an
initial condition. The multiway graph is `Steps sys.step init`. -/
structure Slice where
  sys : System.{u}
  init : sys.Carrier

/-- The reachable set of a slice — its observed universe. -/
def Slice.reachable (s : Slice.{u}) : Set s.sys.Carrier :=
  {x | Steps s.sys.step s.init x}

theorem Slice.init_reachable (s : Slice.{u}) : s.init ∈ s.reachable := Relation.ReflTransGen.refl

theorem Slice.reachable_closed (s : Slice.{u}) {x y : s.sys.Carrier}
    (hx : x ∈ s.reachable) (hxy : s.sys.step x y) : y ∈ s.reachable :=
  Relation.ReflTransGen.tail hx hxy

/-! ## The ruliad is not a type

This is the theorem that forces stratification. It is Cantor's diagonal, applied
to the relations over a carrier. -/

/-- **No universal encoding.** For any type `U`, the rule systems whose carrier
is `U` cannot be injectively encoded *into* `U`. A fortiori there is no type
containing all rule systems over all carriers, so the ruliad cannot be a single
`Type` and must be indexed by an observer's universe. -/
theorem no_universal_encoding (U : Type u) :
    ¬ ∃ enc : (U → U → Prop) → U, Function.Injective enc := by
  intro ⟨enc, henc⟩
  refine Function.cantor_injective (fun s : Set U => enc (fun a _ => a ∈ s)) ?_
  intro s₁ s₂ h
  have hrel := henc h
  ext a
  have := congrFun (congrFun hrel a) a
  exact Iff.of_eq this

/-- Consequence, in the form that matters for an implementation: any concrete
ruliad representation is a *slice*, parameterised by its rule set, and a claim
about "the ruliad" is a claim about one slice unless the universe is stated. -/
theorem ruliad_is_slicewise (U : Type u) :
    ¬ ∃ enc : (U → U → Prop) → U, Function.Injective enc := no_universal_encoding U

/-! ## Emulation: navigating rulial space -/

/-- `A` emulates into `B`: a translation of states under which every `A` step
becomes a `B` computation. This is the morphism of rulial space. -/
structure Emulation (A B : System.{u}) where
  encode : A.Carrier → B.Carrier
  preserve : ∀ a a', A.step a a' → Steps B.step (encode a) (encode a')

/-- Emulation lifts whole computations, not just single steps. -/
theorem Emulation.steps {A B : System.{u}} (e : Emulation A B) {a a' : A.Carrier}
    (h : Steps A.step a a') : Steps B.step (e.encode a) (e.encode a') := by
  induction h with
  | refl => exact .refl
  | tail _ hr ih => exact ih.trans (e.preserve _ _ hr)

/-- Identity emulation. -/
def Emulation.id (A : System.{u}) : Emulation A A where
  encode := fun a => a
  preserve := fun _ _ h => Relation.ReflTransGen.single h

/-- Emulations compose, so systems and emulations form a category: rulial space
has a structure, not just a population. -/
def Emulation.comp {A B C : System.{u}} (f : Emulation A B) (g : Emulation B C) :
    Emulation A C where
  encode := g.encode ∘ f.encode
  preserve := fun a a' h => g.steps (f.preserve a a' h)

theorem Emulation.comp_encode {A B C : System.{u}} (f : Emulation A B) (g : Emulation B C)
    (a : A.Carrier) : (f.comp g).encode a = g.encode (f.encode a) := rfl

theorem Emulation.id_comp {A B : System.{u}} (f : Emulation A B) (a : A.Carrier) :
    ((Emulation.id A).comp f).encode a = f.encode a := rfl

/-- A divergence in the guest is always reconcilable in a confluent host. -/
theorem Emulation.joinable_image {A B : System.{u}} (e : Emulation A B)
    (hB : Confluent B.step) {a b c : A.Carrier}
    (hab : Steps A.step a b) (hac : Steps A.step a c) :
    Joinable B.step (e.encode b) (e.encode c) :=
  hB _ _ _ (e.steps hab) (e.steps hac)

/-! ## Faithful emulation and confluence transfer -/

/-- A faithful emulation reflects computations as well as preserving them: the
host sees no reductions between encoded states that the guest cannot perform. -/
structure Faithful (A B : System.{u}) extends Emulation A B where
  inj : Function.Injective encode
  reflect : ∀ a (y : B.Carrier), Steps B.step (encode a) y →
    ∃ a', y = encode a' ∧ Steps A.step a a'

/-- **Confluence transfer.** A faithful emulation into a confluent host makes the
guest confluent. This is the practical route to causal invariance for a rule set
too complicated to analyse directly: embed it in one that is already known
invariant. -/
theorem Confluent.of_faithful {A B : System.{u}} (f : Faithful A B)
    (hB : Confluent B.step) : Confluent A.step := by
  intro a b c hab hac
  obtain ⟨d, hbd, hcd⟩ := hB _ _ _ (f.toEmulation.steps hab) (f.toEmulation.steps hac)
  obtain ⟨b', hdb', hbb'⟩ := f.reflect b d hbd
  obtain ⟨c', hdc', hcc'⟩ := f.reflect c d hcd
  have hbc : b' = c' := f.inj (hdb'.symm.trans hdc')
  exact ⟨b', hbb', hbc ▸ hcc'⟩

/-! ## Rulial distance

How far apart two rule sets are, counted in rules. The deployed system reports a
`branchial_distance` between branches of one rule set; this is the orthogonal
axis — distance between rule sets themselves. -/

variable {α : Type} [DecidableEq α]

/-- Symmetric difference of two rule lists, counted with multiplicity. -/
def rulialDist (rs₁ rs₂ : List α) : Nat :=
  (rs₁.diff rs₂).length + (rs₂.diff rs₁).length

/-- `l.diff l = []`, which Mathlib does not state at this revision. -/
theorem diff_self_nil : ∀ (l : List α), l.diff l = []
  | [] => by simp
  | a :: t => by
    rw [List.diff_cons, List.erase_cons_head]
    exact diff_self_nil t

theorem rulialDist_self (rs : List α) : rulialDist rs rs = 0 := by
  simp [rulialDist, diff_self_nil]

theorem rulialDist_comm (rs₁ rs₂ : List α) : rulialDist rs₁ rs₂ = rulialDist rs₂ rs₁ := by
  simp [rulialDist, Nat.add_comm]

/-- Zero distance means neither set contributes a rule the other lacks. -/
theorem rulialDist_eq_zero_iff (rs₁ rs₂ : List α) :
    rulialDist rs₁ rs₂ = 0 ↔ rs₁.diff rs₂ = [] ∧ rs₂.diff rs₁ = [] := by
  simp only [rulialDist, Nat.add_eq_zero_iff, List.length_eq_zero_iff]

/-! ### Rulial distance is a genuine metric on rule sets

The previous revision recorded the triangle inequality as unproved. It is proved
here for rule **sets** — which is the real case, since a rule set does not
contain the same rule twice — by way of `symmDiff_triangle` and
`Finset.card_union_le`. The multiset version remains open, and is still recorded
as open below. -/

/-- Rulial distance between rule sets: the size of the symmetric difference. -/
def rulialDistFinset (A B : Finset α) : Nat := (symmDiff A B).card

theorem rulialDistFinset_self (A : Finset α) : rulialDistFinset A A = 0 := by
  simp [rulialDistFinset]

theorem rulialDistFinset_comm (A B : Finset α) :
    rulialDistFinset A B = rulialDistFinset B A := by
  rw [rulialDistFinset, rulialDistFinset, symmDiff_comm]

theorem rulialDistFinset_eq_zero_iff (A B : Finset α) :
    rulialDistFinset A B = 0 ↔ A = B := by
  rw [rulialDistFinset, Finset.card_eq_zero, ← Finset.bot_eq_empty, symmDiff_eq_bot]

/-- **The triangle inequality.** Navigating rulial space by way of a third rule
set is never shorter than going directly, so rulial distances compose. -/
theorem rulialDistFinset_triangle (A B C : Finset α) :
    rulialDistFinset A C ≤ rulialDistFinset A B + rulialDistFinset B C := by
  calc rulialDistFinset A C
      ≤ (symmDiff A B ∪ symmDiff B C).card :=
        Finset.card_le_card (by simpa [rulialDistFinset] using symmDiff_triangle A B C)
    _ ≤ (symmDiff A B).card + (symmDiff B C).card := Finset.card_union_le _ _
    _ = rulialDistFinset A B + rulialDistFinset B C := rfl

/-- So rule sets under rulial distance form a metric space, in the integer-valued
sense: symmetric, zero exactly on equality, and subadditive along any detour. -/
theorem rulialDistFinset_isMetric :
    (∀ A : Finset α, rulialDistFinset A A = 0) ∧
    (∀ A B : Finset α, rulialDistFinset A B = rulialDistFinset B A) ∧
    (∀ A B : Finset α, rulialDistFinset A B = 0 → A = B) ∧
    (∀ A B C : Finset α,
      rulialDistFinset A C ≤ rulialDistFinset A B + rulialDistFinset B C) :=
  ⟨rulialDistFinset_self, rulialDistFinset_comm,
   fun A B h => (rulialDistFinset_eq_zero_iff A B).mp h, rulialDistFinset_triangle⟩

/-!
### Still open

The **multiset** triangle inequality for `rulialDist` on `List`s. It is true —
multiset symmetric difference is a metric — but the proof needs per-element
count arithmetic (`|count A e - count C e| ≤ |count A e - count B e| +
|count B e - count C e|` summed over the joint support), which is a development
of its own. Until then: use `rulialDistFinset` when distances are composed, and
`rulialDist` only as a computable comparator on lists.
-/

end Ruliad.Rulial
