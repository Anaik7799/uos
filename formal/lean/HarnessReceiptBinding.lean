/-
  Abstract model of the failed-effect receipt identity checks. Optional values
  represent decoded fields; natural numbers stand for validated identities.
  This does not prove actual JSON decoding, digest validity, filesystem
  immutability, current lease ownership, or refinement to Gleam.
-/

namespace UOS.HarnessReceiptBinding

structure Identity where
  grant : Option Nat
  worker : Option Nat
  attempt : Option Nat
  epoch : Option Nat

def matched (left right : Option Nat) : Prop :=
  ∃ n, left = some n ∧ right = some n

def matchedPositive (left right : Option Nat) : Prop :=
  ∃ n, 0 < n ∧ left = some n ∧ right = some n

def identityBound (left right : Identity) : Prop :=
  matched left.grant right.grant ∧
  matched left.worker right.worker ∧
  matchedPositive left.attempt right.attempt ∧
  matchedPositive left.epoch right.epoch

-- Current-attempt fencing is modeled as an input; no live lease is observed.
def boundTo (recorded : Identity) (grant worker attempt epoch : Nat) : Prop :=
  recorded.grant = some grant ∧ recorded.worker = some worker ∧
  ∃ a e, recorded.attempt = some a ∧ 0 < a ∧ a ≤ attempt ∧
    recorded.epoch = some e ∧ 0 < e ∧ e ≤ epoch

theorem missing_left_grant_refused (left right : Identity)
    (h : identityBound left right) : left.grant ≠ none := by
  obtain ⟨n, hl, _⟩ := h.1
  intro contradiction
  rw [hl] at contradiction
  cases contradiction

theorem missing_right_worker_refused (left right : Identity)
    (h : identityBound left right) : right.worker ≠ none := by
  obtain ⟨n, _, hr⟩ := h.2.1
  intro contradiction
  rw [hr] at contradiction
  cases contradiction

theorem bound_attempts_agree_and_positive (left right : Identity)
    (h : identityBound left right) :
    ∃ n, 0 < n ∧ left.attempt = some n ∧ right.attempt = some n := by
  exact h.2.2.1

theorem bound_epochs_agree_and_positive (left right : Identity)
    (h : identityBound left right) :
    ∃ n, 0 < n ∧ left.epoch = some n ∧ right.epoch = some n := by
  exact h.2.2.2

theorem current_grant_is_bound (recorded : Identity) (grant worker attempt epoch : Nat)
    (h : boundTo recorded grant worker attempt epoch) : recorded.grant = some grant := by
  exact h.1

theorem recorded_attempt_is_not_future (recorded : Identity) (grant worker attempt epoch : Nat)
    (h : boundTo recorded grant worker attempt epoch) :
    ∃ a, recorded.attempt = some a ∧ 0 < a ∧ a ≤ attempt := by
  obtain ⟨a, _, ha, hp, hb, _, _, _⟩ := h.2.2
  exact ⟨a, ha, hp, hb⟩

theorem recorded_epoch_is_not_future (recorded : Identity) (grant worker attempt epoch : Nat)
    (h : boundTo recorded grant worker attempt epoch) :
    ∃ e, recorded.epoch = some e ∧ 0 < e ∧ e ≤ epoch := by
  obtain ⟨_, e, _, _, _, he, hp, hb⟩ := h.2.2
  exact ⟨e, he, hp, hb⟩

theorem valid_identity_is_inhabited : ∃ left right, identityBound left right := by
  let i : Identity := ⟨some 7, some 9, some 1, some 2⟩
  refine ⟨i, i, ?_, ?_, ?_, ?_⟩
  · exact ⟨7, rfl, rfl⟩
  · exact ⟨9, rfl, rfl⟩
  · exact ⟨1, by decide, rfl, rfl⟩
  · exact ⟨2, by decide, rfl, rfl⟩

namespace Quarantine

/- A successful step represents one completely written record. Crashes within
   a write, filesystem durability, leases and refinement are not modeled. -/
structure State where
  intentBurned : Bool
  signatureBurned : Bool
  published : Bool

inductive Action where
  | burnIntent
  | burnSignature
  | publish

def safe (s : State) : Prop :=
  s.published = true → s.intentBurned = true ∧ s.signatureBurned = true

def step (s : State) : Action → State
  | .burnIntent => { s with intentBurned := true }
  | .burnSignature =>
      if s.intentBurned then { s with signatureBurned := true } else s
  | .publish =>
      if s.intentBurned && s.signatureBurned then { s with published := true } else s

theorem step_preserves_safe (s : State) (action : Action) :
    safe s → safe (step s action) := by
  cases s with
  | mk intent signature published =>
      cases intent <;> cases signature <;> cases published <;> cases action <;> simp [safe, step]

def initial : State := ⟨false, false, false⟩

inductive Reachable : State → Prop where
  | initial : Reachable Quarantine.initial
  | next (s : State) (action : Action) : Reachable s → Reachable (step s action)

theorem reachable_never_publishes_without_burns (s : State) (h : Reachable s) : safe s := by
  induction h with
  | initial => simp [safe, initial]
  | next state action _ ih => exact step_preserves_safe state action ih

#print axioms step_preserves_safe
#print axioms reachable_never_publishes_without_burns

end Quarantine

namespace ReconcileStop

/- Abstract state transition after an operation-level reconciliation. The scan
   is an input; its completeness and the Gleam implementation are not proved. -/
structure State where
  unresolved : Bool
  hasExecution : Bool

inductive Scan where
  | pending
  | clear
  | unknown

def after (state : State) (scan : Scan) (planning : Bool) : Option State :=
  if state.unresolved then
    if state.hasExecution then
      match scan with
      | .pending => some state
      | .unknown => none
      | .clear => some ⟨false, planning⟩
    else none
  else some state

theorem other_pending_preserves_stop (planning : Bool) :
    after ⟨true, true⟩ .pending planning = some ⟨true, true⟩ := by
  rfl

theorem unknown_scan_never_clears_stop (planning : Bool) :
    after ⟨true, true⟩ .unknown planning = none := by
  rfl

theorem clear_scan_allows_effect_release :
    after ⟨true, true⟩ .clear false = some ⟨false, false⟩ := by
  rfl

theorem clear_scan_keeps_planning_execution :
    after ⟨true, true⟩ .clear true = some ⟨false, true⟩ := by
  rfl

#print axioms other_pending_preserves_stop
#print axioms unknown_scan_never_clears_stop
#print axioms clear_scan_allows_effect_release
#print axioms clear_scan_keeps_planning_execution

end ReconcileStop

namespace EffectTimeBinding

/- Abstract identities supplied by an already trusted transport. This model
   does not authenticate the transport or establish Gleam refinement. -/
structure Principal where
  actor : Nat
  client : Nat
  transport : Nat
  workspace : Nat
  session : Nat

structure Task where
  plan : Option Nat
  task : Option Nat
  attempt : Option Nat
  grant : Option Nat

structure BoundCall where
  principal : Principal
  task : Task

def stable (original refreshed : BoundCall) : Prop :=
  original.principal = refreshed.principal ∧ original.task = refreshed.task

theorem unchanged_binding_is_stable (call : BoundCall) : stable call call := by
  exact ⟨rfl, rfl⟩

theorem changed_session_is_refused (original refreshed : BoundCall)
    (changed : original.principal.session ≠ refreshed.principal.session) :
    ¬ stable original refreshed := by
  intro accepted
  exact changed (congrArg Principal.session accepted.1)

theorem changed_attempt_is_refused (original refreshed : BoundCall)
    (changed : original.task.attempt ≠ refreshed.task.attempt) :
    ¬ stable original refreshed := by
  intro accepted
  exact changed (congrArg Task.attempt accepted.2)

theorem changed_grant_is_refused (original refreshed : BoundCall)
    (changed : original.task.grant ≠ refreshed.task.grant) :
    ¬ stable original refreshed := by
  intro accepted
  exact changed (congrArg Task.grant accepted.2)

#print axioms unchanged_binding_is_stable
#print axioms changed_session_is_refused
#print axioms changed_attempt_is_refused
#print axioms changed_grant_is_refused

end EffectTimeBinding

#print axioms missing_left_grant_refused
#print axioms missing_right_worker_refused
#print axioms bound_attempts_agree_and_positive
#print axioms bound_epochs_agree_and_positive
#print axioms current_grant_is_bound
#print axioms recorded_attempt_is_not_future
#print axioms recorded_epoch_is_not_future
#print axioms valid_identity_is_inhabited

end UOS.HarnessReceiptBinding
