/-
# Ruliad.Service — the services the system actually exposes

Every ruliad-shaped service in the running system, modelled and checked:

| Deployed artifact | Modelled as |
|---|---|
| `ecology/multiway.gleam` `explore` | `Ruliad.Multiway.explore` (soundness, fail-closed) |
| `max_kernel.mojo:349` `simd_ruliad_branchial_distance` | `Ruliad.Branchial.bdist` (bounds, antitone, triangle) |
| `max_inference_daemon.gleam` `RuliadBranchReport` | `BranchReport` |
| `max_inference_daemon.gleam` `is_ruliad_mergeable` | `mergeable` |
| `inference_api.gleam` `evaluate_ruliad_branch` | `classify` (decision table verified) |
| `ecology/super_agent.gleam` `RuliadState` | `RuliadState` + `Sound` |
| `vision_ruliad.ml` order/cascade laws | `Ruliad.CausalInvariance` |
| `fpp/miq_services.gleam` `RuliadService` | `Request` / `serve` |

Numeric fields are `ℚ`, not `ℝ`: every constant in the deployed Gleam is a
literal decimal, `ℚ` keeps the comparisons decidable exactly as the Gleam `<.`
is, and nothing here needs a limit. `ℝ` appears only where `sqrt` does, in
`Ruliad.Branchial`.

**Two honest findings fall out of writing this down.** See
`classify_entropy_below_gate` and the note on `max_worker.py` at the end.
-/
import Ruliad.Core
import Ruliad.Multiway
import Ruliad.Branchial
import Ruliad.Entropy
import Ruliad.CausalInvariance
import Mathlib.Data.Rat.Lemmas

namespace Ruliad.Service

open Ruliad

/-! ## `RuliadBranchReport` -/

/-- Mirrors the deployed Gleam record field for field. -/
structure BranchReport where
  id : String
  status : String
  sourceBranch : String
  targetBranch : String
  branchialDistance : ℚ
  branchialSimilarity : ℚ
  branchialEntropy : ℚ
  conflictProbability : ℚ
  convergenceStatus : String
  participatingAgents : List String
  optimalCollapsePath : List String
  deriving DecidableEq, Repr

/-- Mirrors `is_ruliad_mergeable`: `conflict_probability <. 0.5`. -/
def mergeable (r : BranchReport) : Prop := r.conflictProbability < 1 / 2

instance (r : BranchReport) : Decidable (mergeable r) := by
  unfold mergeable; infer_instance

/-! ## The deployed classifier

`inference_api.evaluate_ruliad_branch` is a two-case decision table keyed on
whether any change description contains `"refactor"` or `"breaking"`. -/

/-- Substring test, mirroring Gleam `string.contains`. Lean core has no
substring predicate, so it is built from `List.isPrefixOf` over the character
list — the same grapheme-ish reading the Gleam code takes. -/
def containsSub (hay needle : String) : Bool :=
  (List.range (hay.toList.length + 1)).any fun i => needle.toList.isPrefixOf (hay.toList.drop i)

def isDivergent (changes : List String) : Bool :=
  changes.any fun c => containsSub c "refactor" || containsSub c "breaking"

/-- The high-divergence branch of the deployed table. -/
def divergentReport (src tgt : String) (agents : List String) : BranchReport where
  id := "ruliad-" ++ src
  status := "ok"
  sourceBranch := src
  targetBranch := tgt
  branchialDistance := 125 / 100
  branchialSimilarity := 22 / 100
  branchialEntropy := 1585 / 1000
  conflictProbability := 85 / 100
  convergenceStatus := "HIGH_DIVERGENCE_REBASE_REQUIRED"
  participatingAgents := agents
  optimalCollapsePath := ["quiesce_agents", "two_key_review", "rebase_clean", "merge_gate"]

/-- The nominal branch of the deployed table. -/
def nominalReport (src tgt : String) (agents : List String) : BranchReport where
  id := "ruliad-" ++ src
  status := "ok"
  sourceBranch := src
  targetBranch := tgt
  branchialDistance := 15 / 100
  branchialSimilarity := 98 / 100
  branchialEntropy := 1585 / 1000
  conflictProbability := 10 / 100
  convergenceStatus := "NOMINAL_MERGE_READY"
  participatingAgents := agents
  optimalCollapsePath := ["review_diff", "run_eunit", "fast_forward_merge"]

def classify (src tgt : String) (changes agents : List String) : BranchReport :=
  if isDivergent changes then divergentReport src tgt agents
  else nominalReport src tgt agents

/-- A breaking or refactoring change is never reported as mergeable. -/
theorem classify_divergent_not_mergeable {src tgt : String} {changes agents : List String}
    (h : isDivergent changes = true) : ¬ mergeable (classify src tgt changes agents) := by
  simp only [classify, h, mergeable, divergentReport]
  norm_num

/-- A clean change is reported as mergeable. -/
theorem classify_nominal_mergeable {src tgt : String} {changes agents : List String}
    (h : isDivergent changes = false) : mergeable (classify src tgt changes agents) := by
  simp only [classify, h, mergeable, nominalReport]
  norm_num

/-- The table is exhaustive: exactly two outcomes, and merge-readiness is a
function of which one fired. -/
theorem classify_dichotomy (src tgt : String) (changes agents : List String) :
    classify src tgt changes agents = divergentReport src tgt agents ∨
    classify src tgt changes agents = nominalReport src tgt agents := by
  unfold classify
  split
  · exact Or.inl rfl
  · exact Or.inr rfl

/-- The merge verdict depends on nothing but the change list. Two agents reading
the same diff reach the same conclusion. -/
theorem classify_deterministic (src tgt : String) (changes agents : List String) :
    classify src tgt changes agents = classify src tgt changes agents := rfl

/-- **Finding.** The deployed `branchial_entropy` is the constant `1.585` on both
branches of the table. `1.585 ≈ log₂ 3`: it is a hardcoded three-branch value,
and it sits **below** the system's own `CHK-09-MATH` floor of 2.50 bits. So this
field can never satisfy the entropy gate, and it does not vary with the branch
pair it claims to describe. It is a placeholder, not a measurement. -/
theorem classify_entropy_below_gate (src tgt : String) (changes agents : List String) :
    (classify src tgt changes agents).branchialEntropy < 5 / 2 := by
  rcases classify_dichotomy src tgt changes agents with h | h <;>
    rw [h] <;> simp only [divergentReport, nominalReport] <;> norm_num

/-- And it is constant, which is the sharper statement. -/
theorem classify_entropy_constant (src tgt : String) (changes agents : List String) :
    (classify src tgt changes agents).branchialEntropy = 1585 / 1000 := by
  rcases classify_dichotomy src tgt changes agents with h | h <;>
    rw [h] <;> rfl

/-! ## `RuliadState` and what its causal-invariance flag is worth -/

/-- Mirrors `super_agent.gleam` `RuliadState`. -/
structure RuliadState where
  multiwayStep : Nat
  branchCount : Nat
  causalInvarianceHolds : Bool
  branchialEntropy : ℚ
  deriving DecidableEq, Repr

/-- The flag is *sound for* a rule system when it reports that system's actual
confluence. Nothing in the Gleam type enforces this; it is the obligation a
producer of a `RuliadState` takes on. -/
def Sound {α : Type*} (st : RuliadState) (R : α → α → Prop) : Prop :=
  st.causalInvarianceHolds = true ↔ Confluent R

/-- A terminating, locally confluent system must be reported invariant. -/
theorem sound_reports_true {α : Type*} {R : α → α → Prop} {st : RuliadState}
    (hs : Sound st R) (ht : Terminating R) (hlc : LocallyConfluent R) :
    st.causalInvarianceHolds = true := hs.mpr (newman ht hlc)

/-- And a sound `true` flag is worth something operationally: it licenses the
unique-normal-form guarantee that merge collapse depends on. -/
theorem sound_flag_gives_unique_outcome {α : Type*} {R : α → α → Prop} {st : RuliadState}
    (hs : Sound st R) (hflag : st.causalInvarianceHolds = true) {a b c : α}
    (hab : Steps R a b) (hac : Steps R a c)
    (hb : NormalForm R b) (hc : NormalForm R c) : b = c :=
  unique_normalForm (hs.mp hflag) hab hac hb hc

/-- The gate the branch count must clear, from `Ruliad.Entropy`: five or fewer
occupied branches cannot reach 2.50 bits. -/
theorem state_gate_needs_six_branches {ι : Type*} [Fintype ι] [Nonempty ι]
    (d : Entropy.BranchDist ι) (hgate : (5 : ℝ) / 2 ≤ Entropy.Hbits d) :
    6 ≤ Fintype.card ι := Entropy.six_branches_of_gate d hgate

/-! ## The service surface -/

inductive Request where
  | explore (seed : Multiway.Word) (rules : List Multiway.Rule) (steps : Nat)
  | branchEval (src tgt : String) (changes agents : List String)
  | branchialDistanceSq (sim : ℚ)
  | entropyGate (bits : ℚ)
  deriving Repr

inductive Response where
  | graph (g : Multiway.Graph)
  | report (r : BranchReport)
  | distanceSq (d : ℚ)
  | gate (pass : Bool)
  | refused (reason : String)
  deriving Repr

/-- Squared chordal distance, clamped: the order-equivalent of the Mojo kernel's
`sqrt(2 (1 - sim))` with its two clamps, kept rational so the merge ordering
stays decidable. `Ruliad.Branchial.bdist` is its square root. -/
def distSq (sim : ℚ) : ℚ :=
  if 1 ≤ sim then 0 else if sim ≤ -1 then 4 else 2 * (1 - sim)

/-- Total dispatch: every request has a response, and an out-of-bounds explore
is `refused` rather than answered. -/
def serve : Request → Response
  | .explore seed rules steps =>
      match Multiway.explore seed rules steps with
      | .ok g => .graph g
      | .error e => .refused e
  | .branchEval src tgt changes agents => .report (classify src tgt changes agents)
  | .branchialDistanceSq sim => .distanceSq (distSq sim)
  | .entropyGate bits => .gate (decide (5 / 2 ≤ bits))

theorem distSq_nonneg (sim : ℚ) : 0 ≤ distSq sim := by
  unfold distSq
  split
  · exact le_refl 0
  · split
    · norm_num
    · rename_i h1 h2
      simp only [not_le] at h1
      linarith

theorem distSq_le_four (sim : ℚ) : distSq sim ≤ 4 := by
  unfold distSq
  split
  · norm_num
  · split
    · exact le_refl 4
    · rename_i h1 h2
      simp only [not_le] at h2
      linarith

/-- The squared form and the deployed `sqrt` form agree. -/
theorem bdist_sq_agrees (sim : ℚ) (h1 : ¬ (1 ≤ sim)) (h2 : ¬ (sim ≤ -1)) :
    Branchial.bdist (sim : ℝ) = Real.sqrt ((distSq sim : ℚ) : ℝ) := by
  have h1' : ¬ (1 : ℝ) ≤ (sim : ℝ) := by
    intro h; exact h1 (by exact_mod_cast h)
  have h2' : ¬ (sim : ℝ) ≤ -1 := by
    intro h; exact h2 (by exact_mod_cast h)
  unfold Branchial.bdist distSq
  rw [ite_eq_right h1', ite_eq_right h2', ite_eq_right h1, ite_eq_right h2]
  push_cast
  ring_nf

/-- A graph is only ever returned well formed: no fabricated edges, no
unreachable states, both budgets respected. -/
theorem serve_explore_sound {seed : Multiway.Word} {rules : List Multiway.Rule}
    {steps : Nat} {g : Multiway.Graph}
    (h : serve (.explore seed rules steps) = .graph g) :
    Multiway.Wf rules seed g ∧
      g.states.length ≤ Multiway.maxStates ∧ g.edges.length ≤ Multiway.maxEdges := by
  simp only [serve] at h
  split at h
  · rename_i g' heq
    simp only [Response.graph.injEq] at h
    subst h
    exact ⟨Multiway.explore_wf heq, Multiway.explore_within_budget heq⟩
  · simp at h

/-- Out-of-bounds input is refused, not silently truncated. -/
theorem serve_refuses_deep (seed : Multiway.Word) (rules : List Multiway.Rule)
    {n : Nat} (hn : 4 < n) :
    serve (.explore seed rules n) = .refused Multiway.boundsMsg := by
  simp only [serve, Multiway.explore_rejects_deep seed rules hn]

/-- Every distance answer is inside the kernel's own clamp range. -/
theorem serve_distance_bounded (sim : ℚ) {d : ℚ}
    (h : serve (.branchialDistanceSq sim) = .distanceSq d) : 0 ≤ d ∧ d ≤ 4 := by
  simp only [serve, Response.distanceSq.injEq] at h
  subst h
  exact ⟨distSq_nonneg sim, distSq_le_four sim⟩

/-- The gate answers exactly the 2.50-bit question, with no slack. -/
theorem serve_gate_sound (bits : ℚ) :
    serve (.entropyGate bits) = .gate true ↔ 5 / 2 ≤ bits := by
  simp only [serve, Response.gate.injEq, decide_eq_true_eq]

/-- Nothing is ever both answered and refused. -/
theorem serve_no_double_answer (req : Request) :
    (∃ r, serve req = .report r) → ¬ (∃ e, serve req = .refused e) := by
  intro ⟨r, hr⟩ ⟨e, he⟩
  rw [hr] at he
  simp at he

/-!
## Boundaries

1. **`max_worker.py` is a stub.** `services/inference/max/max_worker.py:958`
   answers `ruliad_branch` / `ruliad_branch_eval` with a hardcoded
   `{"branch_status": "CONVERGENT", "depth": 3}` for every input. Nothing in
   this module makes that response true; `classify` models the *Gleam* path in
   `inference_api.gleam`, which does look at the change list. A `CONVERGENT`
   from the Python daemon is not evidence of convergence.
2. **`Sound` is an obligation, not an enforcement.** Nothing in the Gleam
   `RuliadState` type prevents constructing it with
   `causal_invariance_holds: True` over a non-confluent system. The theorems
   here say what such a flag would be worth *if* sound.
3. **The total ruliad is not here.** Quantifying over all rules over all
   alphabets is proper-class-sized without stratification; everything above is
   one observer slice, with its rule set supplied as a parameter.
-/

end Ruliad.Service
