/- 20260909-0157: Bounded ecology transaction capability, #fractal-l3 #fractal-l8 #zero-muda.
   Companion: apps/cepaf_gleam/src/cepaf_gleam/ecology/capability_twin.gleam.
   Natural-valued fragment; the Gleam boundary rejects invalid negative inputs.
   A pure model theorem grants no live lease, scheduling or deployment authority.
   No claim that the whole UOS implementation refines this model is made. -/
namespace EcologyCapabilityTwin

structure Snapshot where
  version : Nat
  value : String
  owner : Nat
  epoch : Nat
  expires : Nat
  telemetry : Nat
deriving Repr, DecidableEq

structure Transaction where
  actor : Nat
  token : Nat
  snapshot : Nat
  now : Nat
  write : String
deriving Repr, DecidableEq

def Gate (s : Snapshot) (t : Transaction) : Prop :=
  s.version ≥ 1 ∧ s.epoch ≥ 1 ∧ t.snapshot ≥ 1 ∧ t.token ≥ 1 ∧
  t.actor > 0 ∧ s.owner = t.actor ∧ s.epoch = t.token ∧
  t.now < s.expires ∧ t.snapshot = s.version

instance (s : Snapshot) (t : Transaction) : Decidable (Gate s t) :=
  inferInstanceAs (Decidable (_ ∧ _ ∧ _ ∧ _ ∧ _ ∧ _ ∧ _ ∧ _ ∧ _))

def committed (s : Snapshot) (t : Transaction) : Snapshot :=
  { s with version := s.version + 1, value := t.write, owner := 0 }

def commit (s : Snapshot) (t : Transaction) : Option Snapshot :=
  if Gate s t then some (committed s t) else none

def transition (s : Snapshot) (t : Transaction) : Snapshot :=
  (commit s t).getD s

def reference (s : Snapshot) (t : Transaction) : Snapshot :=
  if Gate s t then
    ⟨s.version + 1, t.write, 0, s.epoch, s.expires, s.telemetry⟩
  else s

def observe (s : Snapshot) : Snapshot := { s with telemetry := s.telemetry + 1 }

theorem rejected_unchanged (s : Snapshot) (t : Transaction) (h : ¬ Gate s t) :
    transition s t = s := by simp [transition, commit, h]

theorem acceptance_requires_gate (s : Snapshot) (t : Transaction) (out : Snapshot)
    (h : commit s t = some out) : Gate s t := by
  by_cases present : Gate s t
  · exact present
  · simp [commit, present] at h

theorem commit_result (s : Snapshot) (t : Transaction) (out : Snapshot)
    (h : commit s t = some out) : out = committed s t := by
  have gate := acceptance_requires_gate s t out h
  simpa [commit, gate] using h.symm

theorem exact_commit_effect (s : Snapshot) (t : Transaction) (out : Snapshot)
    (h : commit s t = some out) :
    out.version = s.version + 1 ∧ out.value = t.write ∧ out.owner = 0 ∧
    out.epoch = s.epoch ∧ out.telemetry = s.telemetry := by
  rw [commit_result s t out h]
  simp [committed]

theorem stale_fence_rejected (s : Snapshot) (t : Transaction)
    (h : s.epoch ≠ t.token) : commit s t = none := by
  simp [commit, Gate, h]

theorem stale_snapshot_rejected (s : Snapshot) (t : Transaction)
    (h : t.snapshot ≠ s.version) : commit s t = none := by
  simp [commit, Gate, h]

theorem expiry_boundary_rejected (s : Snapshot) (t : Transaction)
    (h : s.expires ≤ t.now) : commit s t = none := by
  have expired : ¬ t.now < s.expires := by omega
  simp [commit, Gate, expired]

theorem absent_owner_rejected (s : Snapshot) (t : Transaction)
    (h : s.owner = 0) : commit s t = none := by
  have denied : ¬ Gate s t := by
    intro gate
    rcases gate with ⟨_, _, _, _, ha, ho, _, _, _⟩
    omega
  simp [commit, denied]

theorem no_replay (s : Snapshot) (t : Transaction) (out : Snapshot)
    (h : commit s t = some out) : commit out t = none := by
  apply absent_owner_rejected
  exact (exact_commit_effect s t out h).2.2.1

theorem observation_noninterference (s : Snapshot) :
    (observe s).version = s.version ∧ (observe s).value = s.value ∧
    (observe s).owner = s.owner ∧ (observe s).epoch = s.epoch ∧
    (observe s).expires = s.expires := by simp [observe]

theorem runtime_equals_reference (s : Snapshot) (t : Transaction) :
    transition s t = reference s t := by
  unfold transition commit reference
  split <;> rfl

def sample : Snapshot := ⟨1, "before", 1, 1, 10, 0⟩
def request : Transaction := ⟨1, 1, 1, 0, "after"⟩
example : commit sample request = some ⟨2, "after", 0, 1, 10, 0⟩ := by decide
example : commit sample { request with now := 10 } = none := by decide
example : commit sample { request with token := 2 } = none := by decide

#eval commit sample request
#eval commit sample { request with now := 10 }
#print axioms runtime_equals_reference
#print axioms exact_commit_effect
#print axioms observation_noninterference
#print axioms no_replay
end EcologyCapabilityTwin
