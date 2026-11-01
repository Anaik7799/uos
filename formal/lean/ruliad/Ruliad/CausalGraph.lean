/-
# Ruliad.CausalGraph — the event-level causal graph

`Ruliad.Causal` proves things about *state-level* causal structure, and records
why it stops there: `Ruliad.Hypergraph.fire` removes a matched sub-multiset with
`List.diff`, which does not say *which* occurrence it removed, so the
produce/consume edge between events cannot be reconstructed. That gap closes
here, by the device a real Wolfram-model engine uses: **tokens**.

Every hyperedge carries a token. Firing consumes named tokens and mints fresh
ones, so an event records exactly what it destroyed and what it created. The
causal relation is then literally "A produced a token that B consumed", and the
structural fact becomes provable:

  `causal_forward` — **no event consumes a token produced by a later event.**

That is the causal graph being a DAG whose edges agree with the update order,
and it is the precondition for any event-level talk of causal invariance.
-/
import Ruliad.Core
import Ruliad.Hypergraph
import Mathlib.Data.List.Nodup

namespace Ruliad.CausalGraph

open Ruliad Ruliad.Hypergraph

/-- A token: the identity of one hyperedge occurrence. -/
abbrev Token := Nat

/-- A hyperedge together with its occurrence identity. -/
structure TEdge where
  token : Token
  edge : Hyperedge
  deriving DecidableEq, Repr

/-- A tokenized state: the edges present, and the next unused token. -/
structure TState where
  edges : List TEdge
  next : Token
  deriving Repr

def TState.tokens (s : TState) : List Token := s.edges.map TEdge.token

/-- The counter bounds every token in play. This single invariant is what makes
"produced later" and "already present" distinguishable, and it is all the DAG
theorem needs. -/
def Wf (s : TState) : Prop := ∀ e ∈ s.edges, e.token < s.next

theorem lt_next_of_mem_tokens {s : TState} (hwf : Wf s) {t : Token}
    (h : t ∈ s.tokens) : t < s.next := by
  simp only [TState.tokens, List.mem_map] at h
  obtain ⟨e, he, rfl⟩ := h
  exact hwf e he

/-- An event: one rule application, recording what it consumed and produced.
This is a vertex of the causal graph. -/
structure Event where
  rule : Nat
  consumed : List Token
  produced : List Token
  deriving DecidableEq, Repr

/-- `n` fresh tokens starting at `start`. -/
def mkTokens (start : Token) (n : Nat) : List Token :=
  (List.range n).map (fun i => start + i)

theorem mkTokens_spec {start n t : Nat} (h : t ∈ mkTokens start n) :
    start ≤ t ∧ t < start + n := by
  simp only [mkTokens, List.mem_map, List.mem_range] at h
  obtain ⟨i, hi, rfl⟩ := h
  exact ⟨Nat.le_add_right _ _, Nat.add_lt_add_left hi _⟩

/-- An event's produced tokens are pairwise distinct: each new edge gets its own
identity. -/
theorem mkTokens_nodup (start n : Nat) : (mkTokens start n).Nodup := by
  refine List.Nodup.map ?_ List.nodup_range
  intro a b h
  exact Nat.add_left_cancel h

/-- Fire a rule: drop the consumed tokens, mint one fresh token per new edge. -/
def applyEvent (s : TState) (ruleIdx : Nat) (consumed : List Token)
    (newEdges : List Hyperedge) : TState × Event :=
  let prodTokens := mkTokens s.next newEdges.length
  ({ edges := (s.edges.filter fun e => !consumed.contains e.token) ++
        (prodTokens.zip newEdges).map (fun p => ⟨p.1, p.2⟩),
     next := s.next + newEdges.length },
   { rule := ruleIdx, consumed := consumed, produced := prodTokens })

theorem applyEvent_next (s : TState) (i : Nat) (c : List Token) (n : List Hyperedge) :
    (applyEvent s i c n).1.next = s.next + n.length := rfl

theorem applyEvent_produced (s : TState) (i : Nat) (c : List Token) (n : List Hyperedge) :
    (applyEvent s i c n).2.produced = mkTokens s.next n.length := rfl

theorem applyEvent_consumed (s : TState) (i : Nat) (c : List Token) (n : List Hyperedge) :
    (applyEvent s i c n).2.consumed = c := rfl

/-- Firing preserves the invariant. -/
theorem applyEvent_wf {s : TState} (hwf : Wf s) (i : Nat) (c : List Token)
    (n : List Hyperedge) : Wf (applyEvent s i c n).1 := by
  intro e he
  simp only [applyEvent, List.mem_append, List.mem_filter, List.mem_map] at he
  rcases he with ⟨hmem, _⟩ | ⟨p, hp, rfl⟩
  · exact Nat.lt_of_lt_of_le (hwf e hmem) (Nat.le_add_right _ _)
  · have h1 : p.1 ∈ mkTokens s.next n.length := (List.of_mem_zip hp).1
    exact (mkTokens_spec h1).2

/-- **Minted tokens are genuinely new.** Nothing produced collides with
anything already present, so token identity is never ambiguous. -/
theorem produced_not_mem {s : TState} (hwf : Wf s) (i : Nat) (c : List Token)
    (n : List Hyperedge) :
    ∀ t ∈ (applyEvent s i c n).2.produced, t ∉ s.tokens := by
  intro t ht hmem
  have hge := (mkTokens_spec (by rwa [applyEvent_produced] at ht)).1
  exact absurd (lt_next_of_mem_tokens hwf hmem) (Nat.not_lt.mpr hge)

/-! ## Runs of events -/

/-- A run: a sequence of events, each consuming only tokens actually present. -/
inductive Run : TState → List Event → TState → Prop where
  | nil (s : TState) : Run s [] s
  | step {s s' s'' : TState} {ev : Event} {evs : List Event}
      {i : Nat} {c : List Token} {n : List Hyperedge}
      (hvalid : ∀ t ∈ c, t ∈ s.tokens)
      (hstep : applyEvent s i c n = (s', ev))
      (hrest : Run s' evs s'') : Run s (ev :: evs) s''

theorem Run.next_mono {s s' : TState} {evs : List Event} (h : Run s evs s') :
    s.next ≤ s'.next := by
  induction h with
  | nil => exact le_refl _
  | @step s s₁ s₂ ev evs i c n _ hstep _ ih =>
    have hs1 : (applyEvent s i c n).1 = s₁ := congrArg Prod.fst hstep
    have hnext : s₁.next = s.next + n.length := by rw [← hs1]; exact applyEvent_next s i c n
    calc s.next ≤ s.next + n.length := Nat.le_add_right _ _
      _ = s₁.next := hnext.symm
      _ ≤ s₂.next := ih

theorem Run.wf {s s' : TState} {evs : List Event} (hwf : Wf s) (h : Run s evs s') :
    Wf s' := by
  induction h with
  | nil => exact hwf
  | @step s s₁ s₂ ev evs i c n _ hstep _ ih =>
    have hs1 : (applyEvent s i c n).1 = s₁ := congrArg Prod.fst hstep
    exact ih (hs1 ▸ applyEvent_wf hwf i c n)

/-- Everything produced anywhere in a run carries a token at or above the run's
starting counter. -/
theorem Run.produced_ge {s s' : TState} {evs : List Event} (hwf : Wf s) (h : Run s evs s') :
    ∀ ev ∈ evs, ∀ t ∈ ev.produced, s.next ≤ t := by
  induction h with
  | nil => intro ev hev; simp at hev
  | @step s s₁ s₂ ev evs i c n _ hstep hrest ih =>
    intro e he t ht
    have hs1 : (applyEvent s i c n).1 = s₁ := congrArg Prod.fst hstep
    have hev : (applyEvent s i c n).2 = ev := congrArg Prod.snd hstep
    have hnext : s₁.next = s.next + n.length := by rw [← hs1]; exact applyEvent_next s i c n
    have hwf1 : Wf s₁ := hs1 ▸ applyEvent_wf hwf i c n
    rcases List.mem_cons.mp he with rfl | hlater
    · have hp : e.produced = mkTokens s.next n.length := by rw [← hev]; exact applyEvent_produced s i c n
      rw [hp] at ht
      exact (mkTokens_spec ht).1
    · have hlo := ih hwf1 e hlater t ht
      calc s.next ≤ s.next + n.length := Nat.le_add_right _ _
        _ = s₁.next := hnext.symm
        _ ≤ t := hlo

/-- A run splits at any point in its event list. -/
theorem Run.split {s s' : TState} : ∀ (l₁ l₂ : List Event), Run s (l₁ ++ l₂) s' →
    ∃ m, Run s l₁ m ∧ Run m l₂ s' := by
  intro l₁
  induction l₁ generalizing s with
  | nil => intro l₂ h; exact ⟨s, Run.nil s, h⟩
  | cons e t ih =>
    intro l₂ h
    cases h with
    | @step _ s₁ _ ev evs i c n hvalid hstep hrest =>
      obtain ⟨m, h1, h2⟩ := ih (s := s₁) l₂ hrest
      exact ⟨m, Run.step hvalid hstep h1, h2⟩

/-! ## The causal graph -/

/-- `e₁` causally precedes `e₂`: `e₁` produced a token `e₂` consumed. This is an
edge of the causal graph, in the exact Wolfram-model sense. -/
def CausallyBefore (e₁ e₂ : Event) : Prop := ∃ t ∈ e₁.produced, t ∈ e₂.consumed

/-- **The causal graph is a DAG, oriented with the update order.** No event
consumes a token produced by a later event, so there are no backward causal
edges and hence no causal cycles. -/
theorem causal_forward {s s' : TState} {evs : List Event} (hwf : Wf s) (h : Run s evs s')
    (pre : List Event) (ev : Event) (post : List Event) (hsplit : evs = pre ++ ev :: post) :
    ∀ ev₂ ∈ post, ¬ CausallyBefore ev₂ ev := by
  subst hsplit
  obtain ⟨m, hpre, hrest⟩ := Run.split pre (ev :: post) h
  have hwfm : Wf m := hpre.wf hwf
  cases hrest with
  | @step _ s₁ _ _ _ i c n hvalid hstep hpost =>
    intro ev₂ hev₂ ⟨t, htprod, htcons⟩
    have hs1 : (applyEvent m i c n).1 = s₁ := congrArg Prod.fst hstep
    have hev : (applyEvent m i c n).2 = ev := congrArg Prod.snd hstep
    have hnext : s₁.next = m.next + n.length := by rw [← hs1]; exact applyEvent_next m i c n
    have hwf1 : Wf s₁ := hs1 ▸ applyEvent_wf hwfm i c n
    have hge : s₁.next ≤ t := Run.produced_ge hwf1 hpost ev₂ hev₂ t htprod
    have hc : ev.consumed = c := by rw [← hev]; exact applyEvent_consumed m i c n
    rw [hc] at htcons
    have hmle : m.next ≤ t :=
      calc m.next ≤ m.next + n.length := Nat.le_add_right _ _
        _ = s₁.next := hnext.symm
        _ ≤ t := hge
    exact absurd (lt_next_of_mem_tokens hwfm (hvalid t htcons)) (Nat.not_lt.mpr hmle)

/-- Consequently the causal relation is irreflexive on a run: no event causes
itself. -/
theorem causal_irrefl {s s' : TState} {evs : List Event} (hwf : Wf s) (h : Run s evs s')
    (pre : List Event) (ev : Event) (post : List Event) (hsplit : evs = pre ++ ev :: post) :
    ¬ CausallyBefore ev ev := by
  subst hsplit
  obtain ⟨m, hpre, hrest⟩ := Run.split pre (ev :: post) h
  have hwfm : Wf m := hpre.wf hwf
  cases hrest with
  | @step _ s₁ _ _ _ i c n hvalid hstep _ =>
    intro ⟨t, htprod, htcons⟩
    have hev : (applyEvent m i c n).2 = ev := congrArg Prod.snd hstep
    have hp : ev.produced = mkTokens m.next n.length := by rw [← hev]; exact applyEvent_produced m i c n
    have hc : ev.consumed = c := by rw [← hev]; exact applyEvent_consumed m i c n
    rw [hp] at htprod
    rw [hc] at htcons
    have hge := (mkTokens_spec htprod).1
    exact absurd (lt_next_of_mem_tokens hwfm (hvalid t htcons)) (Nat.not_lt.mpr hge)

/-!
### What remains

`causal_forward` gives the DAG. The deeper Wolfram claim — that under causal
invariance the causal graph is *the same* whichever update order is taken —
needs a transposition theorem: reordering two events with disjoint
consumed/produced sets yields the same final state and the same causal edges.
That is the next theorem to prove here, and it is **not** proved: token numbering
is order-sensitive by construction, so the statement has to be up to token
renaming, and that renaming has to be constructed.
-/

end Ruliad.CausalGraph
