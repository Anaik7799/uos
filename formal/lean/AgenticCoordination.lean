import Std

/-
UOS tri-agent coordination reference kernel, authored 2026-09-07.
Scope: one protected resource (instantiate for integration/main or runtime:*).
Revision values and evidence keys are opaque natural-number identifiers, not
cryptographic validation. Receipt authentication and concrete event-store/OS
refinement are outside this model. No operational feature is admitted by this file.
-/
namespace UOS.AgenticCoordination

abbrev Aspect := Fin 17
inductive Agent where | claude | codex | agy deriving DecidableEq, Repr
inductive Resource where | integration | runtime deriving DecidableEq, Repr

structure Packet where
  aspect : Aspect
  sourceRevision : Nat
  runtimeRevision : Nat
  formalRevision : Nat
  runtimeKey : Nat
  formalKey : Nat
  runtimePassed : Bool
  formalPassed : Bool
deriving DecidableEq, Repr

def Packet.bound (p : Packet) (a : Aspect) (candidate : Nat) : Prop :=
  p.aspect = a ∧ p.sourceRevision = candidate ∧
  p.runtimeRevision = candidate ∧ p.formalRevision = candidate ∧
  p.runtimeKey > 0 ∧ p.formalKey > 0 ∧
  p.runtimePassed = true ∧ p.formalPassed = true

instance (p : Packet) (a : Aspect) (candidate : Nat) :
    Decidable (p.bound a candidate) := inferInstanceAs (Decidable (_ ∧ _))

def Ready (candidate : Nat) (packets : Aspect → Packet) : Prop :=
  (∀ a, (packets a).bound a candidate) ∧
  (∀ a b, (packets a).runtimeKey = (packets b).runtimeKey → a = b) ∧
  (∀ a b, (packets a).formalKey = (packets b).formalKey → a = b) ∧
  (∀ a b, (packets a).runtimeKey ≠ (packets b).formalKey)

instance (c : Nat) (p : Aspect → Packet) : Decidable (Ready c p) :=
  inferInstanceAs (Decidable (_ ∧ _))

structure Lease where
  owner : Agent
  epoch : Nat
  expires : Nat
deriving DecidableEq, Repr

structure State where
  resource : Resource
  candidate : Nat
  packets : Aspect → Packet
  admitted : Bool
  clock : Nat
  epoch : Nat
  lease : Option Lease
  authority : Agent → Bool
  reserved : Nat
  settled : Nat
  cap : Nat
  effects : Nat
  observations : Nat

def Inv (s : State) : Prop :=
  s.reserved + s.settled ≤ s.cap ∧
  (s.admitted = true → Ready s.candidate s.packets) ∧
  (∀ l, s.lease = some l → l.epoch = s.epoch)

def admitCandidate (s : State) : State :=
  if Ready s.candidate s.packets then { s with admitted := true } else s

def recordPacket (s : State) (a : Aspect) (p : Packet) : State :=
  { s with packets := fun b => if b = a then p else s.packets b, admitted := false }

def nominate (s : State) (candidate : Nat) : State :=
  { s with candidate := candidate, admitted := false }

def reserve (s : State) (amount : Nat) : State :=
  if s.reserved + amount + s.settled ≤ s.cap then
    { s with reserved := s.reserved + amount }
  else s

def settle (s : State) (amount : Nat) : State :=
  if amount ≤ s.reserved then
    { s with reserved := s.reserved - amount, settled := s.settled + amount }
  else s

def acquire (s : State) (owner : Agent) (duration : Nat) : State :=
  if duration > 0 ∧ (s.lease = none ∨ ∀ l, s.lease = some l → l.expires ≤ s.clock) then
    { s with
      epoch := s.epoch + 1
      lease := some { owner := owner, epoch := s.epoch + 1, expires := s.clock + duration } }
  else s

def release (s : State) (owner : Agent) (epoch : Nat) : State :=
  match s.lease with
  | some l => if l.owner = owner ∧ l.epoch = epoch then { s with lease := none } else s
  | none => s

def CanApply (s : State) (resource : Resource) (owner : Agent)
    (epoch candidate : Nat) : Prop :=
  resource = s.resource ∧ s.authority owner = true ∧ s.admitted = true ∧
  candidate = s.candidate ∧ epoch = s.epoch ∧
  ∃ l, s.lease = some l ∧ l.owner = owner ∧ l.epoch = epoch ∧ s.clock < l.expires

instance (s : State) (r : Resource) (a : Agent) (e c : Nat) :
    Decidable (CanApply s r a e c) := by
  unfold CanApply
  cases h : s.lease with
  | none => simp; infer_instance
  | some l => simp; infer_instance

def applyAction (s : State) (r : Resource) (a : Agent) (epoch candidate : Nat) : State :=
  if CanApply s r a epoch candidate then { s with effects := s.effects + 1 } else s

/- Advice, prompts, model output, and ACKs are observations. There is no
   executable privilege-granting transition in this kernel. Policy is an input
   from the external trusted authority, fixed for an execution trace. -/
def observe (s : State) : State := { s with observations := s.observations + 1 }
def tick (s : State) : State := { s with clock := s.clock + 1 }

theorem admit_preserves (s : State) (h : Inv s) : Inv (admitCandidate s) := by
  unfold admitCandidate
  split
  · exact ⟨h.1, fun _ => by assumption, h.2.2⟩
  · exact h

theorem record_preserves (s : State) (h : Inv s) (a : Aspect) (p : Packet) :
    Inv (recordPacket s a p) := by
  exact ⟨h.1, by simp [recordPacket], h.2.2⟩

theorem nominate_preserves (s : State) (h : Inv s) (c : Nat) : Inv (nominate s c) := by
  exact ⟨h.1, by simp [nominate], h.2.2⟩

theorem reserve_preserves (s : State) (h : Inv s) (n : Nat) : Inv (reserve s n) := by
  unfold reserve
  split
  · exact ⟨by assumption, h.2.1, h.2.2⟩
  · exact h

theorem settle_preserves (s : State) (h : Inv s) (n : Nat) : Inv (settle s n) := by
  unfold settle
  split
  · refine ⟨?_, h.2.1, h.2.2⟩
    have hb := h.1
    dsimp
    omega
  · exact h

theorem acquire_preserves (s : State) (h : Inv s) (a : Agent) (d : Nat) :
    Inv (acquire s a d) := by
  unfold acquire
  split
  · refine ⟨h.1, h.2.1, ?_⟩
    intro l hl
    simp only [Option.some.injEq] at hl
    cases hl
    rfl
  · exact h

theorem release_preserves (s : State) (h : Inv s) (a : Agent) (e : Nat) :
    Inv (release s a e) := by
  unfold release
  split
  · split
    · exact ⟨h.1, h.2.1, by simp⟩
    · exact h
  · exact h

theorem apply_preserves (s : State) (h : Inv s) (r : Resource) (a : Agent) (e c : Nat) :
    Inv (applyAction s r a e c) := by
  unfold applyAction
  split <;> exact h

theorem lease_epoch_monotone (s : State) (a : Agent) (d : Nat) :
    s.epoch ≤ (acquire s a d).epoch := by
  unfold acquire
  split <;> simp

theorem release_retains_epoch (s : State) (a : Agent) (e : Nat) :
    (release s a e).epoch = s.epoch := by
  unfold release
  split
  · split <;> rfl
  · rfl

theorem live_owner_blocks_acquire (s : State) (a : Agent) (d : Nat)
    (l : Lease) (held : s.lease = some l) (live : s.clock < l.expires) :
    acquire s a d = s := by
  unfold acquire
  apply if_neg
  rintro ⟨_, empty | expired⟩
  · simp [held] at empty
  · have he := expired l held
    omega

theorem single_owner (s : State) (l₁ l₂ : Lease)
    (h₁ : s.lease = some l₁) (h₂ : s.lease = some l₂) : l₁.owner = l₂.owner := by
  have h := h₁.symm.trans h₂
  cases Option.some.inj h
  rfl

theorem stale_epoch_cannot_apply (s : State) (r : Resource) (a : Agent) (e c : Nat)
    (stale : e ≠ s.epoch) : applyAction s r a e c = s := by
  apply if_neg
  intro h
  exact stale h.2.2.2.2.1

theorem wrong_revision_cannot_apply (s : State) (r : Resource) (a : Agent) (e c : Nat)
    (stale : c ≠ s.candidate) : applyAction s r a e c = s := by
  apply if_neg
  intro h
  exact stale h.2.2.2.1

theorem expired_lease_cannot_apply (s : State) (r : Resource) (a : Agent) (e c : Nat)
    (l : Lease) (hl : s.lease = some l) (expired : l.expires ≤ s.clock) :
    applyAction s r a e c = s := by
  apply if_neg
  rintro ⟨_, _, _, _, _, witness, hw, _, _, htime⟩
  have eq : l = witness := Option.some.inj (hl.symm.trans hw)
  subst witness
  omega

theorem apply_requires_all_17 (s : State) (h : Inv s) (r : Resource)
    (a : Agent) (e c : Nat) (enabled : CanApply s r a e c) :
    ∀ aspect : Aspect, (s.packets aspect).bound aspect c := by
  have ready := h.2.1 enabled.2.2.1
  rw [enabled.2.2.2.1]
  exact ready.1

theorem duplicate_key_cannot_admit (s : State) (a b : Aspect)
    (collision : (s.packets a).runtimeKey = (s.packets b).formalKey) :
    admitCandidate s = s := by
  apply if_neg
  intro ready
  exact ready.2.2.2 a b collision

theorem advice_ack_prompt_non_authority (s : State) :
    (observe s).authority = s.authority ∧
    (observe s).lease = s.lease ∧
    (observe s).epoch = s.epoch ∧
    (observe s).packets = s.packets ∧
    (observe s).admitted = s.admitted ∧
    (observe s).effects = s.effects := by
  exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem unprivileged_cannot_apply (s : State) (r : Resource) (a : Agent) (e c : Nat)
    (denied : s.authority a = false) : applyAction s r a e c = s := by
  apply if_neg
  intro h
  have hyes := h.2.1
  rw [denied] at hyes
  contradiction

theorem apply_requires_distinct_keys (s : State) (h : Inv s) (r : Resource)
    (a : Agent) (e c : Nat) (enabled : CanApply s r a e c) :
    ∀ i j : Aspect, (s.packets i).runtimeKey ≠ (s.packets j).formalKey := by
  exact (h.2.1 enabled.2.2.1).2.2.2

inductive Event where
  | packet (a : Aspect) (p : Packet)
  | candidate (revision : Nat)
  | admit
  | acquire (a : Agent) (duration : Nat)
  | release (a : Agent) (epoch : Nat)
  | reserve (amount : Nat)
  | settle (amount : Nat)
  | apply (r : Resource) (a : Agent) (epoch revision : Nat)
  | advice | ack | prompt | modelOutput | tick

def step (s : State) : Event → State
  | .packet a p => recordPacket s a p
  | .candidate c => nominate s c
  | .admit => admitCandidate s
  | .acquire a d => acquire s a d
  | .release a e => release s a e
  | .reserve n => reserve s n
  | .settle n => settle s n
  | .apply r a e c => applyAction s r a e c
  | .advice | .ack | .prompt | .modelOutput => observe s
  | .tick => tick s

theorem step_preserves (s : State) (h : Inv s) (event : Event) : Inv (step s event) := by
  cases event with
  | packet a p => exact record_preserves s h a p
  | candidate c => exact nominate_preserves s h c
  | admit => exact admit_preserves s h
  | acquire a d => exact acquire_preserves s h a d
  | release a e => exact release_preserves s h a e
  | reserve n => exact reserve_preserves s h n
  | settle n => exact settle_preserves s h n
  | apply r a e c => exact apply_preserves s h r a e c
  | advice | ack | prompt | modelOutput | tick => exact h

theorem step_epoch_monotone (s : State) (event : Event) : s.epoch ≤ (step s event).epoch := by
  cases event <;>
    simp [step, recordPacket, nominate, admitCandidate, acquire, release,
      reserve, settle, applyAction, observe, tick]
  all_goals split <;> (try split) <;> simp_all

theorem step_authority_unchanged (s : State) (event : Event) :
    (step s event).authority = s.authority := by
  cases event <;>
    simp [step, recordPacket, nominate, admitCandidate, acquire, release,
      reserve, settle, applyAction, observe, tick]
  all_goals split <;> (try split) <;> simp_all

def run (s : State) (events : List Event) : State := events.foldl step s

theorem run_preserves (events : List Event) (s : State) (h : Inv s) : Inv (run s events) := by
  induction events generalizing s with
  | nil => exact h
  | cons event rest ih => exact ih (step s event) (step_preserves s h event)

/- Nonvacuity: fully distinct 34 evidence keys really allow admission; a
   registered policy-authorized owner can reserve, apply, and settle a cost. -/
def validPacket (c : Nat) (a : Aspect) : Packet :=
  { aspect := a, sourceRevision := c, runtimeRevision := c, formalRevision := c,
    runtimeKey := 2 * a.val + 1, formalKey := 2 * a.val + 2,
    runtimePassed := true, formalPassed := true }

theorem valid_packets_ready (c : Nat) : Ready c (validPacket c) := by
  refine ⟨?_, ?_, ?_, ?_⟩
  · intro a
    simp [Packet.bound, validPacket]
  · intro a b h
    apply Fin.ext
    dsimp [validPacket] at h
    omega
  · intro a b h
    apply Fin.ext
    dsimp [validPacket] at h
    omega
  · intro a b h
    dsimp [validPacket] at h
    omega

def fixture : State :=
  { resource := .integration, candidate := 7, packets := validPacket 7,
    admitted := false, clock := 0, epoch := 0, lease := none,
    authority := fun a => a == Agent.codex,
    reserved := 0, settled := 0, cap := 10, effects := 0, observations := 0 }

theorem fixture_safe : Inv fixture := by
  simp [Inv, fixture]

#eval (run fixture [.admit, .acquire .codex 5, .reserve 3,
  .apply .integration .codex 1 7, .settle 3]).effects
#eval (run fixture [.admit, .acquire .codex 5,
  .apply .integration .codex 0 7]).effects
#eval (run fixture [.advice, .ack, .prompt, .modelOutput]).effects

#print axioms run_preserves
#print axioms apply_requires_all_17
#print axioms valid_packets_ready
#print axioms step_epoch_monotone
#print axioms step_authority_unchanged

end UOS.AgenticCoordination
