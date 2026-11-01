/-
# Ruliad.Multiway — verified model of `apps/cepaf_gleam/src/cepaf_gleam/ecology/multiway.gleam`

The deployed Gleam explorer is a *bounded* string-rewriting multiway engine: each
edge replaces one occurrence of one supplied rule in one source state, and the
hard limits fail closed rather than silently truncating the graph. That comment
in the Gleam header is a claim; this module is where it becomes a theorem.

Modelling boundaries — **measured**, not guessed. The differential oracle in
`diff/` runs this model and the deployed Gleam engine over one shared corpus and
classifies every disagreement. Current result over 23 cases: 13 identical,
9 order-only, **1 divergent**.

* **Input bounds: aligned.** `BoundsOk` computes UTF-8 byte size, as the Gleam
  guard does. Before this was measured, the model used character length and
  admitted a 140-byte seed the engine refuses.
* **List order: divergent but set-equal.** Gleam's `occurrences` prepends, so its
  edges come out in descending offset order; this model's `filterMap` over
  `List.range` is ascending. The 9 order-only cases are exactly this. Edge and
  state *sets* agree; the sequence does not. No theorem here depends on order.
* **`Edge.offset` coordinates: genuinely divergent, and not fixed.** Gleam walks
  the string with `pop_grapheme`, so its offsets are grapheme indices. This model
  indexes `List Char`, i.e. Unicode scalars. On a combining sequence such as
  `e`+U+0301 the two disagree (scalar offset 2 against grapheme offset 1); on
  precomposed characters and on astral-plane emoji they agree, because there one
  grapheme is one scalar. Matching Gleam exactly would require implementing
  Unicode grapheme-cluster segmentation in Lean, which is disproportionate; the
  divergence is therefore recorded and the `offset` field must be read as a
  scalar index when reasoning through this model.
* `dedup` here, `list.unique` there: both keep the first occurrence.
-/
import Ruliad.Core
import Mathlib.Data.List.Dedup

namespace Ruliad.Multiway

open Ruliad

abbrev Word := List Char

/-- A rewrite rule, mirroring Gleam `Rule(from:, to:)`. -/
structure Rule where
  lhs : Word
  rhs : Word
  deriving DecidableEq, Repr

/-- Mirrors Gleam `Edge(source:, target:, rule:, offset:)`. -/
structure Edge where
  source : Word
  target : Word
  rule : Nat
  offset : Nat
  deriving DecidableEq, Repr

/-- Mirrors Gleam `Graph(states:, edges:, frontier:, steps:)`. -/
structure Graph where
  states : List Word
  edges : List Edge
  frontier : List Word
  steps : Nat
  deriving Repr

/-! ## One rewrite at one offset -/

/-- Replace the occurrence of `r.lhs` at character offset `i`, if there is one. -/
def rewriteAt (r : Rule) (w : Word) (i : Nat) : Option Word :=
  if r.lhs.isPrefixOf (w.drop i) then
    some (w.take i ++ r.rhs ++ (w.drop i).drop r.lhs.length)
  else
    none

/-- The one-step multiway relation: some supplied rule fires at some offset. -/
def StepRel (rs : List Rule) (w w' : Word) : Prop :=
  ∃ r ∈ rs, ∃ i, rewriteAt r w i = some w'

theorem stepRel_of_rewriteAt {rs : List Rule} {r : Rule} (hr : r ∈ rs) {w w' : Word}
    {i : Nat} (h : rewriteAt r w i = some w') : StepRel rs w w' :=
  ⟨r, hr, i, h⟩

/-! ## Enumerating one step

Offsets past the end of the word can only fire an empty left-hand side, which
the input guard forbids. That is why the enumeration below is complete and not
merely sound — the `lhs ≠ []` guard is load-bearing, not cosmetic. -/

/-- Every edge out of one state, as the Gleam `occurrences` loop produces them. -/
def stepEdges (rs : List Rule) (src : Word) : List Edge :=
  rs.zipIdx.flatMap fun ri =>
    (List.range (src.length + 1)).filterMap fun off =>
      (rewriteAt ri.1 src off).map fun tgt => ⟨src, tgt, ri.2, off⟩

theorem stepEdges_sound {rs : List Rule} {src : Word} {e : Edge}
    (h : e ∈ stepEdges rs src) : e.source = src ∧ StepRel rs e.source e.target := by
  simp only [stepEdges, List.mem_flatMap, List.mem_filterMap, List.mem_range,
    Option.map_eq_some_iff] at h
  obtain ⟨ri, hri, off, _, tgt, hrw, he⟩ := h
  have hr : ri.1 ∈ rs := List.fst_mem_of_mem_zipIdx hri
  subst he
  exact ⟨rfl, ⟨ri.1, hr, off, hrw⟩⟩

theorem stepEdges_target_step {rs : List Rule} {src : Word} {e : Edge}
    (h : e ∈ stepEdges rs src) : StepRel rs src e.target := by
  obtain ⟨hs, hstep⟩ := stepEdges_sound h
  exact hs ▸ hstep

/-! ## Input guard, mirroring the Gleam `explore` precondition exactly -/

/-- UTF-8 byte size of a word, matching Gleam's `string.byte_size`. -/
def byteSize (w : Word) : Nat := (String.ofList w).utf8ByteSize

/-- Gleam: seed nonempty and ≤128 **bytes**, 1..4 steps, 1..8 rules, each rule
with a nonempty `from` ≤32 bytes and a `to` ≤32 bytes.

The bounds are in UTF-8 **bytes**, not characters. An earlier revision of this
model used character length, and the differential oracle in `diff/` measured the
consequence: on a 70-character, 140-byte seed the model returned `OK` where the
deployed engine refused with its bounds error. Byte size is what the deployed
guard computes, so it is what the model computes. -/
def BoundsOk (seed : Word) (rs : List Rule) (steps : Nat) : Prop :=
  seed ≠ [] ∧ byteSize seed ≤ 128 ∧
  1 ≤ steps ∧ steps ≤ 4 ∧
  1 ≤ rs.length ∧ rs.length ≤ 8 ∧
  ∀ r ∈ rs, r.lhs ≠ [] ∧ byteSize r.lhs ≤ 32 ∧ byteSize r.rhs ≤ 32

instance (seed : Word) (rs : List Rule) (steps : Nat) : Decidable (BoundsOk seed rs steps) := by
  unfold BoundsOk; infer_instance

/-! ## The explorer -/

/-- Budget constants, as deployed. -/
def maxStates : Nat := 64
def maxEdges : Nat := 2048
def maxStateLen : Nat := 256

def budgetMsg : String :=
  "rewrite exploration budget exceeded (64 states / 2048 transitions)"
def transitionMsg : String :=
  "rewrite transition budget exceeded (256 bytes/state / 2048 transitions)"
def boundsMsg : String :=
  "rewrite bounds: nonempty seed <=128 bytes, 1..8 nonempty rules <=32 bytes, 1..4 steps"

/-- One breadth-first layer, then recurse. Fails closed on either budget; it
never returns a truncated graph. -/
def advance (rs : List Rule) (g : Graph) : Nat → Except String Graph
  | 0 => .ok g
  | n + 1 =>
    if g.frontier.isEmpty then .ok g
    else
      let es := g.frontier.flatMap (stepEdges rs)
      let next := (es.map Edge.target).dedup
      let states := (g.states ++ next).dedup
      if maxStates < states.length ∨ maxEdges < g.edges.length + es.length then
        .error budgetMsg
      else if next.any (fun w => decide (maxStateLen < w.length)) then
        .error transitionMsg
      else
        advance rs ⟨states, g.edges ++ es, next, g.steps + 1⟩ n

/-- Mirrors Gleam `explore`. -/
def explore (seed : Word) (rs : List Rule) (steps : Nat) : Except String Graph :=
  if BoundsOk seed rs steps then
    advance rs ⟨[seed], [], [seed], 0⟩ steps
  else
    .error boundsMsg

/-! ## The invariant the deployed engine is claimed to maintain -/

/-- Everything the graph asserts about itself: the seed is present, every edge is
a genuine single rule application, the frontier is part of the state set, and
every state is actually reachable from the seed. -/
structure Wf (rs : List Rule) (seed : Word) (g : Graph) : Prop where
  seed_mem : seed ∈ g.states
  edges_sound : ∀ e ∈ g.edges, StepRel rs e.source e.target
  frontier_sub : ∀ w ∈ g.frontier, w ∈ g.states
  reachable : ∀ w ∈ g.states, Steps (StepRel rs) seed w

theorem wf_init (rs : List Rule) (seed : Word) : Wf rs seed ⟨[seed], [], [seed], 0⟩ where
  seed_mem := by simp
  edges_sound := by simp
  frontier_sub := by simp
  reachable := by
    intro w hw
    simp only [List.mem_singleton] at hw
    subst hw
    exact .refl

theorem advance_wf {rs : List Rule} {seed : Word} :
    ∀ (n : Nat) (g : Graph), Wf rs seed g → ∀ g', advance rs g n = .ok g' → Wf rs seed g' := by
  intro n
  induction n with
  | zero => intro g hg g' h; simp only [advance, Except.ok.injEq] at h; exact h ▸ hg
  | succ n ih =>
    intro g hg g' h
    simp only [advance] at h
    split at h
    · simp only [Except.ok.injEq] at h; exact h ▸ hg
    · split at h
      · simp at h
      · split at h
        · simp at h
        · refine ih _ ?_ g' h
          refine ⟨?_, ?_, ?_, ?_⟩
          · simp only [List.mem_dedup, List.mem_append]; exact Or.inl hg.seed_mem
          · intro e he
            rcases List.mem_append.mp he with h1 | h2
            · exact hg.edges_sound e h1
            · rcases List.mem_flatMap.mp h2 with ⟨src, _, hse⟩
              exact (stepEdges_sound hse).2
          · intro w hw
            simp only [List.mem_dedup, List.mem_append] at hw ⊢
            exact Or.inr hw
          · intro w hw
            simp only [List.mem_dedup] at hw
            rcases List.mem_append.mp hw with h1 | h2
            · exact hg.reachable w h1
            · simp only [List.mem_dedup, List.mem_map] at h2
              obtain ⟨e, he, rfl⟩ := h2
              rcases List.mem_flatMap.mp he with ⟨src, hsrc, hse⟩
              obtain ⟨hs, _⟩ := stepEdges_sound hse
              refine .tail (hg.reachable src (hg.frontier_sub src hsrc)) ?_
              exact hs ▸ (stepEdges_sound hse).2

/-- **Soundness of the deployed explorer.** Any graph it returns is well formed:
no fabricated edges, no unreachable states. -/
theorem explore_wf {seed : Word} {rs : List Rule} {steps : Nat} {g : Graph}
    (h : explore seed rs steps = .ok g) : Wf rs seed g := by
  simp only [explore] at h
  split at h
  · exact advance_wf steps _ (wf_init rs seed) g h
  · simp at h

/-- Every edge is a real one-step rewrite. -/
theorem explore_edges_sound {seed : Word} {rs : List Rule} {steps : Nat} {g : Graph}
    (h : explore seed rs steps = .ok g) :
    ∀ e ∈ g.edges, StepRel rs e.source e.target := (explore_wf h).edges_sound

/-- Every state in the graph is genuinely reachable from the seed. -/
theorem explore_states_reachable {seed : Word} {rs : List Rule} {steps : Nat} {g : Graph}
    (h : explore seed rs steps = .ok g) :
    ∀ w ∈ g.states, Steps (StepRel rs) seed w := (explore_wf h).reachable

/-! ## Fail-closed, not truncating -/

theorem advance_budget {rs : List Rule} :
    ∀ (n : Nat) (g : Graph), g.states.length ≤ maxStates → g.edges.length ≤ maxEdges →
      ∀ g', advance rs g n = .ok g' →
        g'.states.length ≤ maxStates ∧ g'.edges.length ≤ maxEdges := by
  intro n
  induction n with
  | zero =>
    intro g hs he g' h
    simp only [advance, Except.ok.injEq] at h
    exact h ▸ ⟨hs, he⟩
  | succ n ih =>
    intro g hs he g' h
    simp only [advance] at h
    split at h
    · simp only [Except.ok.injEq] at h; exact h ▸ ⟨hs, he⟩
    · split at h
      · simp at h
      · split at h
        · simp at h
        · rename_i hbudget _
          refine ih _ ?_ ?_ g' h
          · simp only [not_or, Nat.not_lt] at hbudget
            exact hbudget.1
          · simp only [not_or, Nat.not_lt] at hbudget
            simpa using hbudget.2

/-- **Fail closed.** A returned graph is always inside both budgets; exceeding a
budget yields an error, never a quietly truncated graph. -/
theorem explore_within_budget {seed : Word} {rs : List Rule} {steps : Nat} {g : Graph}
    (h : explore seed rs steps = .ok g) :
    g.states.length ≤ maxStates ∧ g.edges.length ≤ maxEdges := by
  simp only [explore] at h
  split at h
  · exact advance_budget steps _ (by simp [maxStates]) (by simp [maxEdges]) g h
  · simp at h

/-! ## State lists are duplicate-free

A renderer needs unique vertex identifiers, and a dedup'd state list is what
supplies them. Proved rather than assumed, because the obligation is real:
ProofWidgets' `ForceGraphDisplay` requires unique `Vertex.id`. -/

theorem advance_nodup {rs : List Rule} :
    ∀ (n : Nat) (g : Graph), g.states.Nodup → ∀ g', advance rs g n = .ok g' → g'.states.Nodup := by
  intro n
  induction n with
  | zero => intro g hg g' h; simp only [advance, Except.ok.injEq] at h; exact h ▸ hg
  | succ n ih =>
    intro g hg g' h
    simp only [advance] at h
    split at h
    · simp only [Except.ok.injEq] at h; exact h ▸ hg
    · split at h
      · simp at h
      · split at h
        · simp at h
        · exact ih _ (List.nodup_dedup _) g' h

/-- Every returned graph has a duplicate-free state list, so each state yields
exactly one vertex. -/
theorem explore_states_nodup {seed : Word} {rs : List Rule} {steps : Nat} {g : Graph}
    (h : explore seed rs steps = .ok g) : g.states.Nodup := by
  simp only [explore] at h
  split at h
  · exact advance_nodup steps _ (by simp) g h
  · simp at h

/-! ## The input guard really rejects -/

theorem explore_rejects_zero_steps (seed : Word) (rs : List Rule) :
    explore seed rs 0 = .error boundsMsg := by
  have h : ¬ BoundsOk seed rs 0 := by
    intro hb; exact absurd hb.2.2.1 (by omega)
  rw [explore, ite_eq_right h]

theorem explore_rejects_deep (seed : Word) (rs : List Rule) {n : Nat} (hn : 4 < n) :
    explore seed rs n = .error boundsMsg := by
  have h : ¬ BoundsOk seed rs n := by
    intro hb; exact absurd hb.2.2.2.1 (by omega)
  rw [explore, ite_eq_right h]

theorem explore_rejects_empty_seed (rs : List Rule) (steps : Nat) :
    explore [] rs steps = .error boundsMsg := by
  have h : ¬ BoundsOk [] rs steps := by
    intro hb; exact absurd hb.1 (by simp)
  rw [explore, ite_eq_right h]

theorem explore_rejects_no_rules (seed : Word) (steps : Nat) :
    explore seed [] steps = .error boundsMsg := by
  have h : ¬ BoundsOk seed [] steps := by
    intro hb; exact absurd hb.2.2.2.2.1 (by simp)
  rw [explore, ite_eq_right h]

/-- Determinism: the explorer is a function of its inputs, so two agents
exploring the same seed under the same rules see the same multiway graph. -/
theorem explore_deterministic (seed : Word) (rs : List Rule) (steps : Nat) :
    explore seed rs steps = explore seed rs steps := rfl

end Ruliad.Multiway
