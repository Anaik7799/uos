/-!
Abstract development model for the UOS agent meta-harness active-slot lifecycle.

This is a specification-level transition system, not a refinement proof for
agent_meta_policy.gleam, a process supervisor, an authenticated cleanup witness,
or a distributed atomic reservation service.  The rules below deliberately
assume a single sequential state transition and a fixed configured capacity.
The liability/cost ledger is omitted: active slots are resource-accounting
units, not monetary amounts or provider-cost bounds.
-/

namespace UOS.AgentMetaRuntimeInvariant

structure State where
  capacity : Nat
  active : Nat
  cleanupUnknown : Nat
deriving DecidableEq, Repr

def initial (capacity : Nat) : State :=
  ⟨capacity, 0, 0⟩

def Safe (s : State) : Prop :=
  s.cleanupUnknown ≤ s.active ∧ s.active ≤ s.capacity

inductive Action where
  | reserve
  | observeCleanupUnknown
  | confirmKnownCleanup
  | confirmUnknownCleanup
deriving DecidableEq, Repr

/-!
Specification assumptions encoded by these constructors:
* reservation is one atomic abstract operation and checks current headroom;
* unknown cleanup remains in the active count;
* an active slot can be removed only by one of the two explicitly confirmed
  cleanup transitions;
* an unknown-cleanup slot can be confirmed cleaned only when one is retained.

The model does not assert that Gleam currently implements these rules
atomically, or that a cleanup observation authenticates OS/process termination.
-/
inductive Step : State → Action → State → Prop where
  | reserve (s : State) (headroom : s.active < s.capacity) :
      Step s .reserve ⟨s.capacity, s.active + 1, s.cleanupUnknown⟩
  | observeCleanupUnknown (s : State) (knownActive : s.cleanupUnknown < s.active) :
      Step s .observeCleanupUnknown
        ⟨s.capacity, s.active, s.cleanupUnknown + 1⟩
  | confirmKnownCleanup (s : State) (knownActive : s.cleanupUnknown < s.active) :
      Step s .confirmKnownCleanup
        ⟨s.capacity, s.active - 1, s.cleanupUnknown⟩
  | confirmUnknownCleanup (s : State) (unknownPresent : 0 < s.cleanupUnknown) :
      Step s .confirmUnknownCleanup
        ⟨s.capacity, s.active - 1, s.cleanupUnknown - 1⟩

inductive Reach : State → State → Prop where
  | refl (s : State) : Reach s s
  | next {start current next : State} {action : Action} :
      Reach start current →
      Step current action next →
      Reach start next

theorem step_preserves_safe {s t : State} {action : Action}
    (safe : Safe s) (step : Step s action t) : Safe t := by
  cases step with
  | reserve headroom =>
      simp only [Safe] at safe ⊢
      rcases safe with ⟨unknownBound, activeBound⟩
      constructor
      · omega
      · omega
  | observeCleanupUnknown knownActive =>
      simp only [Safe] at safe ⊢
      rcases safe with ⟨unknownBound, activeBound⟩
      constructor <;> omega
  | confirmKnownCleanup knownActive =>
      simp only [Safe] at safe ⊢
      rcases safe with ⟨unknownBound, activeBound⟩
      constructor <;> omega
  | confirmUnknownCleanup unknownPresent =>
      simp only [Safe] at safe ⊢
      rcases safe with ⟨unknownBound, activeBound⟩
      constructor <;> omega

theorem reachable_preserves_safe (capacity : Nat) {s : State}
    (reachable : Reach (initial capacity) s) : Safe s := by
  induction reachable with
  | refl =>
      simp [Safe, initial]
  | next prior step ih => exact step_preserves_safe ih step

theorem unknown_cleanup_retains_slot {s t : State}
    (step : Step s .observeCleanupUnknown t) : t.active = s.active := by
  cases step
  rfl

theorem active_decrease_only_after_confirmed_cleanup
    {s t : State} {action : Action}
    (step : Step s action t) (decreased : t.active < s.active) :
    action = .confirmKnownCleanup ∨ action = .confirmUnknownCleanup := by
  cases step <;> simp_all <;> omega

def oneUnknown : State := ⟨2, 1, 1⟩

theorem concrete_unknown_state_is_reachable :
    Reach (initial 2) oneUnknown := by
  have reserveOne : Step (initial 2) .reserve ⟨2, 1, 0⟩ := by
    apply Step.reserve
    decide
  have observeUnknown :
      Step ⟨2, 1, 0⟩ .observeCleanupUnknown oneUnknown := by
    apply Step.observeCleanupUnknown
    decide
  exact Reach.next (Reach.next (Reach.refl _) reserveOne) observeUnknown

theorem concrete_unknown_is_active_and_safe :
    oneUnknown.cleanupUnknown = 1 ∧ oneUnknown.active = 1 ∧ Safe oneUnknown := by
  exact ⟨rfl, rfl, reachable_preserves_safe 2 concrete_unknown_state_is_reachable⟩

#print axioms step_preserves_safe
#print axioms reachable_preserves_safe
#print axioms unknown_cleanup_retains_slot
#print axioms active_decrease_only_after_confirmed_cleanup
#print axioms concrete_unknown_is_active_and_safe

end UOS.AgentMetaRuntimeInvariant
