import Std

/-!
# AgentScaleControl — abstract, serialized safety model for UOS hive scale control

PROVENANCE: native Claude timed out before publishing a model. Its scratch
prototype is retained in private evidence. This completed source and its proofs
were salvaged locally by a CODEX RELAY under explicit parent instruction; they
are not a completed native Claude result.

SCOPE (read first). This file is a REPORT-ONLY, kernel-checked ABSTRACT model of plan section 7
(agent scale-control).  It proves safety properties of a total, SERIALIZED (one transition at a
time) admission state machine `step`.  It does NOT establish: native Gleam refinement/equivalence,
authentication/cryptography, liveness/progress, clock-provider correctness, provider price
correctness, or whole-system admission.  It creates no runtime/backend.

Obligations this model places on EXISTING Gleam infrastructure (NOT proved here):
* `daily_budget`: one durable reservation of exactly 250000 microUSD per provider request, daily
  total <= 10000000 microUSD, no refunds, unique reservation id, per frozen-UTC-day counter.
* Sa-plan task: durable effect-ID ledger (permanent tombstones), immutable logical payload per
  effect ID, durable monotone generation / coordinator epoch.
* coordinator effect fences: effect-time re-check of grant/task/attempt/candidate/risk (abstracted
  by the assumed `Env` predicates) and STRICT `now < deadline`, `now < lease` (NOT `<=`).

Stable logical payload (`Payload`, immutable per effect id) is kept apart from the ephemeral
effect-time fences (`Fence`: generation, epoch, deadline, lease, plus `Env` oracle answers).
Capacity is a finite typed-slot design: two writer slots + one reviewer slot.  A worker in ANY of
reserved/starting/running/uncertain/draining occupies its slot; only an authoritative stopped
readback empties a slot, and the ledger (tombstones, liabilities) is never shrunk.
Day semantics: `day` is a frozen UTC day number supplied by a trusted clock; `rollover` requires a
strictly larger day and resets only the per-day counter (assumed external; lifetime liability kept).

Typed slots prove capacity, NOT injectivity of real worker IDs. `Readback.authoritative`
is assumed truthful, current, and effect-bound; a Boolean is not authentication.
Single-writer serialization, trusted day rollover, and actual durable commit are
external obligations. Concrete guards do not test a proposed post-state invariant.
-/

namespace AgentScaleControl

def hardTotal : Nat := 3
def unitCost : Nat := 250000
def dailyCap : Nat := 10000000

inductive Role | writer | reviewer deriving DecidableEq, Repr
inductive Slot | w0 | w1 | r0 deriving DecidableEq, Repr
def Slot.role : Slot → Role | .w0 => .writer | .w1 => .writer | .r0 => .reviewer
def writerSlots : List Slot := [.w0, .w1]
def reviewerSlots : List Slot := [.r0]

inductive Phase | reserved | starting | running | uncertain | draining deriving DecidableEq, Repr
inductive RbState | running | stopped | unreachable deriving DecidableEq, Repr

/-- Stable logical payload: immutably bound to an effect id. -/
structure Payload where
  role : Role
  worker : Nat
  plan : Nat
  task : Nat
  attempt : Nat
  candidate : Nat
  risk : Nat
  budgetReceipt : Nat
  deriving DecidableEq, Repr

/-- Ephemeral effect-time fence (never part of the stable binding). -/
structure Fence where
  gen : Nat
  epoch : Nat
  deadline : Nat
  lease : Nat
  deriving DecidableEq, Repr

structure Request where
  effect : Nat
  payload : Payload
  fence : Fence
  deriving DecidableEq, Repr

/-- ASSUMED external typed validity predicates (fresh authenticated answers at effect time). -/
structure Env where
  grant : Payload → Bool
  task : Payload → Bool
  attempt : Payload → Bool
  candidate : Payload → Bool
  risk : Payload → Bool
  control : Bool

structure Readback where
  effect : Nat
  authoritative : Bool
  state : RbState
  deriving DecidableEq, Repr

/-- Permanent ledger entry (tombstone + provider-request reservation).  Never deleted. -/
structure Entry where
  effect : Nat
  payload : Payload
  res : Nat
  consumed : Bool
  deriving DecidableEq, Repr

structure Occ where
  effect : Nat
  phase : Phase
  deriving DecidableEq, Repr

/-- Serialized authoritative admission state (telemetry is NOT part of it). -/
structure S where
  gen : Nat
  epoch : Nat
  now : Nat
  day : Nat
  target : Nat
  draining : Bool
  slots : Slot → Option Occ
  ledger : List Entry
  nextRes : Nat
  lifetimePaid : Nat
  dayPaid : Nat

def init : S :=
  { gen := 0, epoch := 1, now := 0, day := 0, target := 0, draining := false,
    slots := fun _ => none, ledger := [], nextRes := 0, lifetimePaid := 0, dayPaid := 0 }

def isOcc (s : S) (sl : Slot) : Bool := (s.slots sl).isSome
def writers (s : S) : Nat := (writerSlots.filter (isOcc s)).length
def reviewers (s : S) : Nat := (reviewerSlots.filter (isOcc s)).length
def occupied (s : S) : Nat := writers s + reviewers s

theorem writers_le (s : S) : writers s ≤ 2 := by
  have := List.length_filter_le (isOcc s) writerSlots
  simpa [writers, writerSlots] using this
theorem reviewers_le (s : S) : reviewers s ≤ 1 := by
  have := List.length_filter_le (isOcc s) reviewerSlots
  simpa [reviewers, reviewerSlots] using this
theorem occupied_le (s : S) : occupied s ≤ hardTotal := by
  have := writers_le s; have := reviewers_le s; unfold occupied hardTotal; omega

inductive Refusal
  | conflictingPayload | staleGeneration | staleEpoch | deadlineExpired | leaseExpired
  | grantInvalid | taskInvalid | attemptInvalid | candidateInvalid | riskInvalid
  | draining | targetExhausted | slotOccupied | roleMismatch | budgetExhausted
  | unknownEffect | providerConsumed | notAuthoritative | wrongPhase | slotEmpty
  | targetOverLimit | clockRegression | epochRegression | dayRegression | controlGrantInvalid
  | reservationReuse
  deriving DecidableEq, Repr

def setSlot (f : Slot → Option Occ) (sl : Slot) (v : Option Occ) : Slot → Option Occ :=
  fun x => if x = sl then v else f x

/-- FRESHNESS guard: fence match, STRICT clock, assumed-oracle validity. -/
def Fresh (s : S) (env : Env) (f : Fence) (p : Payload) : Prop :=
  f.gen = s.gen ∧ f.epoch = s.epoch ∧ s.now < f.deadline ∧ s.now < f.lease ∧
  env.grant p = true ∧ env.task p = true ∧ env.attempt p = true ∧
  env.candidate p = true ∧ env.risk p = true
instance (s : S) (env : Env) (f : Fence) (p : Payload) : Decidable (Fresh s env f p) := by
  unfold Fresh; infer_instance

def freshReason (s : S) (env : Env) (f : Fence) (p : Payload) : Refusal :=
  if f.gen ≠ s.gen then .staleGeneration
  else if f.epoch ≠ s.epoch then .staleEpoch
  else if ¬ (s.now < f.deadline) then .deadlineExpired
  else if ¬ (s.now < f.lease) then .leaseExpired
  else if env.grant p = false then .grantInvalid
  else if env.task p = false then .taskInvalid
  else if env.attempt p = false then .attemptInvalid
  else if env.candidate p = false then .candidateInvalid
  else .riskInvalid

def CtlFresh (s : S) (env : Env) (f : Fence) : Prop :=
  f.gen = s.gen ∧ f.epoch = s.epoch ∧ s.now < f.deadline ∧ s.now < f.lease ∧ env.control = true
instance (s : S) (env : Env) (f : Fence) : Decidable (CtlFresh s env f) := by
  unfold CtlFresh; infer_instance
def ctlReason (s : S) (env : Env) (f : Fence) : Refusal :=
  if f.gen ≠ s.gen then .staleGeneration
  else if f.epoch ≠ s.epoch then .staleEpoch
  else if ¬ (s.now < f.deadline) then .deadlineExpired
  else if ¬ (s.now < f.lease) then .leaseExpired
  else .controlGrantInvalid

/-- Admission guards: FRESHNESS, no drain, TARGET, EMPTY typed slot (CAPACITY), role, BUDGET. -/
def AdmitGuards (s : S) (env : Env) (sl : Slot) (r : Request) : Prop :=
  Fresh s env r.fence r.payload ∧ s.draining = false ∧ occupied s < s.target ∧
  s.slots sl = none ∧ r.payload.role = sl.role ∧
  s.ledger.any (fun e => e.payload.budgetReceipt == r.payload.budgetReceipt) = false ∧
  s.dayPaid + unitCost ≤ dailyCap
instance (s : S) (env : Env) (sl : Slot) (r : Request) : Decidable (AdmitGuards s env sl r) := by
  unfold AdmitGuards; infer_instance
def admitReason (s : S) (env : Env) (sl : Slot) (r : Request) : Refusal :=
  if ¬ Fresh s env r.fence r.payload then freshReason s env r.fence r.payload
  else if s.draining = true then .draining
  else if ¬ occupied s < s.target then .targetExhausted
  else if s.slots sl ≠ none then .slotOccupied
  else if r.payload.role ≠ sl.role then .roleMismatch
  else if s.ledger.any (fun e => e.payload.budgetReceipt == r.payload.budgetReceipt)
       then .reservationReuse
  else .budgetExhausted

def admitApply (s : S) (sl : Slot) (r : Request) : S :=
  { s with
    slots := setSlot s.slots sl (some ⟨r.effect, .reserved⟩)
    ledger := ⟨r.effect, r.payload, s.nextRes, false⟩ :: s.ledger
    nextRes := s.nextRes + 1
    lifetimePaid := s.lifetimePaid + unitCost
    dayPaid := s.dayPaid + unitCost }

/-- Admission: replay of identical payload is a no-op; conflicting reuse refuses (tombstones). -/
def admit (s : S) (env : Env) (sl : Slot) (r : Request) : Except Refusal S :=
  match s.ledger.find? (fun e => e.effect == r.effect) with
  | some e => if e.payload = r.payload then .ok s else .error .conflictingPayload
  | none => if AdmitGuards s env sl r then .ok (admitApply s sl r)
            else .error (admitReason s env sl r)

def markConsumed (eff : Nat) (e : Entry) : Entry :=
  if e.effect = eff then { e with consumed := true } else e

def DispatchGuards (s : S) (env : Env) (sl : Slot) (r : Request) (e : Entry) : Prop :=
  Fresh s env r.fence r.payload ∧ s.draining = false ∧ e.consumed = false ∧
  s.slots sl = some ⟨r.effect, .reserved⟩
instance (s : S) (env : Env) (sl : Slot) (r : Request) (e : Entry) :
    Decidable (DispatchGuards s env sl r e) := by
  unfold DispatchGuards; infer_instance
def dispatchReason (s : S) (env : Env) (r : Request) (e : Entry) : Refusal :=
  if ¬ Fresh s env r.fence r.payload then freshReason s env r.fence r.payload
  else if s.draining = true then .draining
  else if e.consumed = true then .providerConsumed
  else .wrongPhase

def dispatchApply (s : S) (sl : Slot) (r : Request) : S :=
  { s with slots := setSlot s.slots sl (some ⟨r.effect, .starting⟩),
           ledger := s.ledger.map (markConsumed r.effect) }

/-- Consume the (single) provider request of an admitted effect.  Permanent. -/
def dispatch (s : S) (env : Env) (sl : Slot) (r : Request) : Except Refusal S :=
  match s.ledger.find? (fun e => e.effect == r.effect) with
  | none => .error .unknownEffect
  | some e =>
    if e.payload ≠ r.payload then .error .conflictingPayload
    else if DispatchGuards s env sl r e then .ok (dispatchApply s sl r)
    else .error (dispatchReason s env r e)

def setTarget (s : S) (env : Env) (f : Fence) (n : Nat) : Except Refusal S :=
  if CtlFresh s env f then
    (if n ≤ hardTotal then .ok { s with target := n, draining := (n == 0), gen := s.gen + 1 }
     else .error .targetOverLimit)
  else .error (ctlReason s env f)

def drainAll (s : S) (env : Env) (f : Fence) : Except Refusal S :=
  if CtlFresh s env f then .ok { s with draining := true, target := 0, gen := s.gen + 1 }
  else .error (ctlReason s env f)

def beginDrain (s : S) (env : Env) (f : Fence) (sl : Slot) : Except Refusal S :=
  if CtlFresh s env f then
    (match s.slots sl with
     | none => .error .slotEmpty
     | some o => if o.phase = .starting ∨ o.phase = .running
                 then .ok { s with slots := setSlot s.slots sl (some ⟨o.effect, .draining⟩) }
                 else .error .wrongPhase)
  else .error (ctlReason s env f)

def markUncertain (s : S) (sl : Slot) : Except Refusal S :=
  match s.slots sl with
  | none => .error .slotEmpty
  | some o => if o.phase = .starting ∨ o.phase = .running ∨ o.phase = .draining
              then .ok { s with slots := setSlot s.slots sl (some ⟨o.effect, .uncertain⟩) }
              else .error .wrongPhase

def confirmRunning (s : S) (sl : Slot) (rb : Readback) : Except Refusal S :=
  match s.slots sl with
  | none => .error .slotEmpty
  | some o => if rb.authoritative = true ∧ rb.state = .running ∧ rb.effect = o.effect then
                (if o.phase = .starting ∨ o.phase = .uncertain
                 then .ok { s with slots := setSlot s.slots sl (some ⟨o.effect, .running⟩) }
                 else .error .wrongPhase)
              else .error .notAuthoritative

/-- The ONLY transition that empties a slot: authoritative stopped readback for that very effect. -/
def releaseStopped (s : S) (sl : Slot) (rb : Readback) : Except Refusal S :=
  match s.slots sl with
  | none => .error .slotEmpty
  | some o => if rb.authoritative = true ∧ rb.state = .stopped ∧ rb.effect = o.effect
              then .ok { s with slots := setSlot s.slots sl none }
              else .error .notAuthoritative

def tick (s : S) (t : Nat) : Except Refusal S :=
  if s.now ≤ t then .ok { s with now := t } else .error .clockRegression
def newEpoch (s : S) (e : Nat) : Except Refusal S :=
  if s.epoch < e then .ok { s with epoch := e } else .error .epochRegression
def rollover (s : S) (d : Nat) : Except Refusal S :=
  if s.day < d then .ok { s with day := d, dayPaid := 0 } else .error .dayRegression

inductive Act
  | admit (sl : Slot) (r : Request)
  | dispatch (sl : Slot) (r : Request)
  | setTarget (f : Fence) (n : Nat)
  | drainAll (f : Fence)
  | beginDrain (f : Fence) (sl : Slot)
  | markUncertain (sl : Slot)
  | confirmRunning (sl : Slot) (rb : Readback)
  | releaseStopped (sl : Slot) (rb : Readback)
  | tick (t : Nat)
  | newEpoch (e : Nat)
  | rollover (d : Nat)

/-- Total serialized transition function. -/
def step (env : Env) (s : S) : Act → Except Refusal S
  | .admit sl r => admit s env sl r
  | .dispatch sl r => dispatch s env sl r
  | .setTarget f n => setTarget s env f n
  | .drainAll f => drainAll s env f
  | .beginDrain f sl => beginDrain s env f sl
  | .markUncertain sl => markUncertain s sl
  | .confirmRunning sl rb => confirmRunning s sl rb
  | .releaseStopped sl rb => releaseStopped s sl rb
  | .tick t => tick s t
  | .newEpoch e => newEpoch s e
  | .rollover d => rollover s d

inductive Steps : S → S → Prop
  | refl (s : S) : Steps s s
  | tail {s s' s'' : S} (env : Env) (a : Act) : Steps s s' → step env s' a = .ok s'' → Steps s s''

def Reach (s : S) : Prop := Steps init s

/-- Financial/capacity-target invariant; reservation bounds establish freshness of
the internally allocated reservation serial. External budget receipts are assumed
validated by the trusted grant oracle, not proved cryptographically here. -/
def Inv (s : S) : Prop :=
  s.dayPaid ≤ dailyCap ∧ s.lifetimePaid = s.nextRes * unitCost ∧
  s.ledger.length = s.nextRes ∧ s.target ≤ hardTotal ∧
  ∀ e ∈ s.ledger, e.res < s.nextRes

theorem initial_inv : Inv init := by simp [Inv, init, dailyCap, hardTotal]

@[simp] theorem markConsumed_res (eff : Nat) (e : Entry) :
    (markConsumed eff e).res = e.res := by unfold markConsumed; split <;> rfl
@[simp] theorem markConsumed_effect (eff : Nat) (e : Entry) :
    (markConsumed eff e).effect = e.effect := by unfold markConsumed; split <;> rfl
@[simp] theorem markConsumed_payload (eff : Nat) (e : Entry) :
    (markConsumed eff e).payload = e.payload := by unfold markConsumed; split <;> rfl

theorem admitApply_inv (s : S) (env : Env) (sl : Slot) (r : Request)
    (hi : Inv s) (hg : AdmitGuards s env sl r) : Inv (admitApply s sl r) := by
  rcases hi with ⟨hd, hp, hl, ht, hr⟩
  rcases hg with ⟨_, _, _, _, _, _, hb⟩
  refine ⟨hb, ?_, ?_, ht, ?_⟩
  · simpa [admitApply, Nat.add_mul] using congrArg (· + unitCost) hp
  · simp [admitApply, hl]
  · intro e he
    simp only [admitApply, List.mem_cons] at he
    rcases he with he | he
    · subst e; simp [admitApply]
    · change e.res < s.nextRes + 1
      exact Nat.lt_succ_of_lt (hr e he)

theorem dispatchApply_inv (s : S) (sl : Slot) (r : Request)
    (hi : Inv s) : Inv (dispatchApply s sl r) := by
  rcases hi with ⟨hd, hp, hl, ht, hr⟩
  refine ⟨hd, hp, ?_, ht, ?_⟩
  · simp [dispatchApply, hl]
  · intro e he
    change e ∈ s.ledger.map (markConsumed r.effect) at he
    obtain ⟨old, ho, rfl⟩ := List.mem_map.mp he
    simpa [dispatchApply] using hr old ho

theorem admit_preserves (hi : Inv s) (h : admit s env sl r = .ok t) : Inv t := by
  unfold admit at h
  split at h
  · split at h
    · cases h; exact hi
    · cases h
  · split at h
    · cases h; exact admitApply_inv s env sl r hi (by assumption)
    · cases h

theorem dispatch_preserves (hi : Inv s) (h : dispatch s env sl r = .ok t) : Inv t := by
  unfold dispatch at h
  split at h
  · cases h
  · split at h
    · cases h
    · split at h
      · cases h; exact dispatchApply_inv s sl r hi
      · cases h

theorem setTarget_preserves (hi : Inv s) (h : setTarget s env f n = .ok t) : Inv t := by
  unfold setTarget at h
  split at h
  · split at h
    · cases h
      exact ⟨hi.1, hi.2.1, hi.2.2.1, by assumption, hi.2.2.2.2⟩
    · cases h
  · cases h

theorem drainAll_preserves (hi : Inv s) (h : drainAll s env f = .ok t) : Inv t := by
  unfold drainAll at h
  split at h
  · cases h
    exact ⟨hi.1, hi.2.1, hi.2.2.1, Nat.zero_le _, hi.2.2.2.2⟩
  · cases h

theorem beginDrain_preserves (hi : Inv s) (h : beginDrain s env f sl = .ok t) : Inv t := by
  unfold beginDrain at h
  split at h
  · split at h
    · cases h
    · split at h
      · cases h; exact hi
      · cases h
  · cases h

theorem markUncertain_preserves (hi : Inv s) (h : markUncertain s sl = .ok t) : Inv t := by
  unfold markUncertain at h
  split at h
  · cases h
  · split at h
    · cases h; exact hi
    · cases h

theorem confirmRunning_preserves (hi : Inv s) (h : confirmRunning s sl rb = .ok t) : Inv t := by
  unfold confirmRunning at h
  split at h
  · cases h
  · split at h
    · split at h
      · cases h; exact hi
      · cases h
    · cases h

theorem releaseStopped_preserves (hi : Inv s) (h : releaseStopped s sl rb = .ok t) : Inv t := by
  unfold releaseStopped at h
  split at h
  · cases h
  · split at h
    · cases h; exact hi
    · cases h

theorem tick_preserves (hi : Inv s) (h : tick s n = .ok t) : Inv t := by
  unfold tick at h; split at h
  · cases h; exact hi
  · cases h
theorem newEpoch_preserves (hi : Inv s) (h : newEpoch s n = .ok t) : Inv t := by
  unfold newEpoch at h; split at h
  · cases h; exact hi
  · cases h
theorem rollover_preserves (hi : Inv s) (h : rollover s n = .ok t) : Inv t := by
  unfold rollover at h; split at h
  · cases h
    exact ⟨Nat.zero_le _, hi.2.1, hi.2.2.1, hi.2.2.2.1, hi.2.2.2.2⟩
  · cases h

theorem step_preserves (hi : Inv s) (h : step env s a = .ok t) : Inv t := by
  cases a with
  | admit sl r => exact admit_preserves hi h
  | dispatch sl r => exact dispatch_preserves hi h
  | setTarget f n => exact setTarget_preserves hi h
  | drainAll f => exact drainAll_preserves hi h
  | beginDrain f sl => exact beginDrain_preserves hi h
  | markUncertain sl => exact markUncertain_preserves hi h
  | confirmRunning sl rb => exact confirmRunning_preserves hi h
  | releaseStopped sl rb => exact releaseStopped_preserves hi h
  | tick n => exact tick_preserves hi h
  | newEpoch n => exact newEpoch_preserves hi h
  | rollover n => exact rollover_preserves hi h

theorem steps_preserve (hi : Inv s) (h : Steps s t) : Inv t := by
  induction h with
  | refl => exact hi
  | tail env a _ heq ih => exact step_preserves ih heq

theorem reachable_inv (h : Reach s) : Inv s := steps_preserve initial_inv h
theorem reachable_safety (h : Reach s) :
    writers s ≤ 2 ∧ reviewers s ≤ 1 ∧ occupied s ≤ 3 ∧ s.dayPaid ≤ dailyCap :=
  ⟨writers_le s, reviewers_le s, occupied_le s, (reachable_inv h).1⟩

/-- New reservations cannot reuse any serial in a reachable ledger. -/
theorem fresh_reservation (h : Reach s) (he : e ∈ s.ledger) : e.res ≠ s.nextRes := by
  have := (reachable_inv h).2.2.2.2 e he
  omega

/-- Historical replay is an observation, not dispatch or a renewed authority. -/
theorem identical_replay
    (hf : s.ledger.find? (fun e => e.effect == r.effect) = some e)
    (hb : e.payload = r.payload) : admit s env sl r = .ok s := by
  simp [admit, hf, hb]
theorem conflicting_replay
    (hf : s.ledger.find? (fun e => e.effect == r.effect) = some e)
    (hb : e.payload ≠ r.payload) : admit s env sl r = .error .conflictingPayload := by
  simp [admit, hf, hb]

theorem stale_generation_not_fresh (h : f.gen ≠ s.gen) : ¬Fresh s env f p := by
  intro hf; exact h hf.1
theorem stale_epoch_not_fresh (h : f.epoch ≠ s.epoch) : ¬Fresh s env f p := by
  intro hf; exact h hf.2.1
theorem deadline_boundary_not_fresh (h : f.deadline ≤ s.now) : ¬Fresh s env f p := by
  intro hf; exact Nat.not_lt_of_ge h hf.2.2.1
theorem lease_boundary_not_fresh (h : f.lease ≤ s.now) : ¬Fresh s env f p := by
  intro hf; exact Nat.not_lt_of_ge h hf.2.2.2.1

theorem fresh_failure_refuses_new_admission
    (hn : s.ledger.find? (fun e => e.effect == r.effect) = none)
    (hx : ¬Fresh s env r.fence r.payload) :
    admit s env sl r = .error (admitReason s env sl r) := by
  have hg : ¬AdmitGuards s env sl r := fun h => hx h.1
  simp [admit, hn, hg]

theorem consumed_request_refuses_dispatch
    (hf : s.ledger.find? (fun e => e.effect == r.effect) = some e)
    (hc : e.consumed = true) : ∃ reason, dispatch s env sl r = .error reason := by
  by_cases hb : e.payload ≠ r.payload
  · exact ⟨.conflictingPayload, by simp [dispatch, hf, hb]⟩
  · have hg : ¬DispatchGuards s env sl r e := by
      intro h; have := h.2.2.1; simp [hc] at this
    exact ⟨dispatchReason s env r e, by simp [dispatch, hf, hb, hg]⟩

@[simp] theorem markConsumed_true (eff : Nat) (e : Entry) (hc : e.consumed = true) :
    (markConsumed eff e).consumed = true := by
  unfold markConsumed; split <;> simp_all

theorem find_markConsumed (xs : List Entry) (eff wanted : Nat) :
    (xs.map (markConsumed eff)).find? (fun e => e.effect == wanted) =
    (xs.find? (fun e => e.effect == wanted)).map (markConsumed eff) := by
  induction xs with
  | nil => rfl
  | cons e xs ih =>
    simp only [List.map_cons, List.find?_cons, markConsumed_effect]
    split <;> simp_all

theorem dispatch_records_consumption
    (hf : s.ledger.find? (fun e => e.effect == r.effect) = some e)
    (h : dispatch s env sl r = .ok t) :
    ∃ e', t.ledger.find? (fun e => e.effect == r.effect) = some e' ∧
      e'.consumed = true ∧ e'.payload = e.payload ∧ e'.res = e.res := by
  have he : e.effect = r.effect := by
    simpa using List.find?_some hf
  by_cases hb : e.payload ≠ r.payload
  · simp [dispatch, hf, hb] at h
  · by_cases hg : DispatchGuards s env sl r e
    · have ht : dispatchApply s sl r = t := by simpa [dispatch, hf, hb, hg] using h
      subst t
      refine ⟨markConsumed r.effect e, ?_, ?_, by simp, by simp⟩
      · change (s.ledger.map (markConsumed r.effect)).find?
          (fun x => x.effect == r.effect) = some (markConsumed r.effect e)
        rw [find_markConsumed, hf]
        rfl
      · simp [markConsumed, he]
    · simp [dispatch, hf, hb, hg] at h

theorem released_capacity_keeps_history
    (h : releaseStopped s sl rb = .ok t) :
    t.ledger = s.ledger ∧ t.lifetimePaid = s.lifetimePaid ∧ t.nextRes = s.nextRes := by
  unfold releaseStopped at h
  split at h
  · cases h
  · split at h
    · cases h; exact ⟨rfl, rfl, rfl⟩
    · cases h

theorem unauthoritative_stop_refuses (hx : rb.authoritative = false) :
    ∃ reason, releaseStopped s sl rb = .error reason := by
  cases hs : s.slots sl with
  | none => exact ⟨.slotEmpty, by simp [releaseStopped, hs]⟩
  | some o => exact ⟨.notAuthoritative, by simp [releaseStopped, hs, hx]⟩

theorem occupancy_replace_some (s : S) (sl : Slot) (o o' : Occ)
    (hs : s.slots sl = some o) :
    occupied {s with slots := setSlot s.slots sl (some o')} = occupied s := by
  have hf : isOcc {s with slots := setSlot s.slots sl (some o')} = isOcc s := by
    funext x
    by_cases hx : x = sl
    · subst x; simp [isOcc, setSlot, hs]
    · simp [isOcc, setSlot, hx]
  simp [occupied, writers, reviewers, hf]

theorem uncertainty_holds_capacity (h : markUncertain s sl = .ok t) :
    occupied t = occupied s := by
  unfold markUncertain at h
  split at h
  · cases h
  · rename_i o hs
    split at h
    · cases h; exact occupancy_replace_some s sl o ⟨o.effect, .uncertain⟩ hs
    · cases h

/-- Lifetime liability, reservation serial, generation, epoch and time never decrease.
Day liability alone may reset under the explicit trusted-day rollover operation. -/
def Mono (s t : S) : Prop :=
  s.lifetimePaid ≤ t.lifetimePaid ∧ s.nextRes ≤ t.nextRes ∧ s.gen ≤ t.gen ∧
  s.epoch ≤ t.epoch ∧ s.now ≤ t.now ∧ s.day ≤ t.day

theorem transition_monotone (h : step env s a = .ok t) : Mono s t := by
  cases a <;>
    simp only [step, admit, dispatch, setTarget, drainAll, beginDrain,
      markUncertain, confirmRunning, releaseStopped, tick, newEpoch, rollover] at h
  all_goals try split at h
  all_goals try split at h
  all_goals try split at h
  all_goals try split at h
  all_goals cases h
  all_goals simp_all [Mono, admitApply, dispatchApply]
  all_goals omega

theorem history_monotone (h : Steps s t) : Mono s t := by
  induction h with
  | refl => exact ⟨Nat.le_refl _, Nat.le_refl _, Nat.le_refl _,
      Nat.le_refl _, Nat.le_refl _, Nat.le_refl _⟩
  | tail env a _ heq ih =>
    have hm := transition_monotone heq
    exact ⟨Nat.le_trans ih.1 hm.1, Nat.le_trans ih.2.1 hm.2.1,
      Nat.le_trans ih.2.2.1 hm.2.2.1, Nat.le_trans ih.2.2.2.1 hm.2.2.2.1,
      Nat.le_trans ih.2.2.2.2.1 hm.2.2.2.2.1,
      Nat.le_trans ih.2.2.2.2.2 hm.2.2.2.2.2⟩

/-- Read-only telemetry may be extended without changing authoritative state. -/
structure Observation where
  authoritative : S
  samples : List Nat
def observe (o : Observation) (sample : Nat) : Observation :=
  {o with samples := sample :: o.samples}
theorem telemetry_noninterference (o : Observation) (sample : Nat) :
    (observe o sample).authoritative = o.authoritative := rfl

def KnownConsumed (s : S) (eff : Nat) : Prop :=
  ∃ e, s.ledger.find? (fun x => x.effect == eff) = some e ∧ e.consumed = true

theorem successful_dispatch_ledger (h : dispatch s env sl r = .ok t) :
    t.ledger = s.ledger.map (markConsumed r.effect) := by
  unfold dispatch at h
  split at h
  · cases h
  · split at h
    · cases h
    · split at h
      · cases h; rfl
      · cases h

theorem admit_keeps_consumed (hk : KnownConsumed s eff)
    (h : admit s env sl r = .ok t) : KnownConsumed t eff := by
  rcases hk with ⟨old, hfo, hco⟩
  cases hf : s.ledger.find? (fun e => e.effect == r.effect) with
  | some e =>
    by_cases hb : e.payload = r.payload
    · have ht : s = t := by simpa [admit, hf, hb] using h
      subst t; exact ⟨old, hfo, hco⟩
    · simp [admit, hf, hb] at h
  | none =>
    by_cases hg : AdmitGuards s env sl r
    · have ht : admitApply s sl r = t := by simpa [admit, hf, hg] using h
      subst t
      have hn : r.effect ≠ eff := by
        intro heq; rw [heq, hfo] at hf; cases hf
      refine ⟨old, ?_, hco⟩
      simp [admitApply, List.find?_cons, hn, hfo]
    · simp [admit, hf, hg] at h

theorem dispatch_keeps_consumed (hk : KnownConsumed s eff)
    (h : dispatch s env sl r = .ok t) : KnownConsumed t eff := by
  rcases hk with ⟨old, hf, hc⟩
  refine ⟨markConsumed r.effect old, ?_, markConsumed_true _ _ hc⟩
  rw [successful_dispatch_ledger h, find_markConsumed, hf]
  rfl

theorem step_keeps_consumed (hk : KnownConsumed s eff)
    (h : step env s a = .ok t) : KnownConsumed t eff := by
  cases a <;> first
    | exact admit_keeps_consumed hk h
    | exact dispatch_keeps_consumed hk h
    | skip
  all_goals simp only [step, setTarget, drainAll, beginDrain, markUncertain,
    confirmRunning, releaseStopped, tick, newEpoch, rollover] at h
  all_goals try split at h
  all_goals try split at h
  all_goals try split at h
  all_goals try split at h
  all_goals cases h
  all_goals exact hk

theorem history_keeps_consumed (hk : KnownConsumed s eff) (h : Steps s t) :
    KnownConsumed t eff := by
  induction h with
  | refl => exact hk
  | tail env a _ heq ih => exact step_keeps_consumed ih heq

/-- Once consumed, no future serialized transition history can make this
provider request executable again, including release, uncertainty and rollover. -/
theorem provider_request_never_runs_again (hk : KnownConsumed s r.effect)
    (h : Steps s t) : ∃ reason, dispatch t env sl r = .error reason := by
  rcases history_keeps_consumed hk h with ⟨e, hf, hc⟩
  exact consumed_request_refuses_dispatch hf hc

/-- Concrete witnesses below use explicitly trusted oracle answers; their
truth in a real backend is an external obligation, not established by examples. -/
def demoEnv : Env := ⟨fun _ => true, fun _ => true, fun _ => true,
  fun _ => true, fun _ => true, true⟩
def demoFence (s : S) : Fence := ⟨s.gen, s.epoch, s.now + 10, s.now + 10⟩
def demoPayload (role : Role) (worker receipt : Nat) : Payload :=
  ⟨role, worker, 1, 2, 1, 3, 4, receipt⟩
def demoRequest (s : S) (effect : Nat) (role : Role) (worker receipt : Nat) : Request :=
  ⟨effect, demoPayload role worker receipt, demoFence s⟩
def accepted : Except Refusal S → Bool | .ok _ => true | .error _ => false
def refusal : Except Refusal S → Option Refusal | .ok _ => none | .error e => some e
/-- Witness-only unwrapping. Acceptance is separately checked below. -/
def witnessState : Except Refusal S → S | .ok s => s | .error _ => init

def exTarget := witnessState (setTarget init demoEnv (demoFence init) 3)
def exReq0 := demoRequest exTarget 10 .writer 1 100
def exW0 := witnessState (admit exTarget demoEnv .w0 exReq0)
def exReq1 := demoRequest exW0 11 .writer 2 101
def exW1 := witnessState (admit exW0 demoEnv .w1 exReq1)
def exReqR := demoRequest exW1 12 .reviewer 3 102
def exThree := witnessState (admit exW1 demoEnv .r0 exReqR)

example : accepted (setTarget init demoEnv (demoFence init) 3) = true ∧
    accepted (admit exTarget demoEnv .w0 exReq0) = true ∧
    accepted (admit exW0 demoEnv .w1 exReq1) = true ∧
    accepted (admit exW1 demoEnv .r0 exReqR) = true := by decide
theorem three_worker_witness : writers exThree = 2 ∧ reviewers exThree = 1 ∧
    occupied exThree = 3 ∧ exThree.dayPaid = 750000 ∧ exThree.ledger.length = 3 := by decide

def exStarting := witnessState (dispatch exThree demoEnv .w0 exReq0)
def exUncertain := witnessState (markUncertain exStarting .w0)
def exStopped : Readback := ⟨10, true, .stopped⟩
def exReleased := witnessState (releaseStopped exUncertain .w0 exStopped)
example : accepted (dispatch exThree demoEnv .w0 exReq0) = true ∧
    accepted (markUncertain exStarting .w0) = true ∧ occupied exUncertain = 3 := by decide
example : refusal (releaseStopped exUncertain .w0 ⟨10, false, .stopped⟩) =
    some .notAuthoritative := by decide
example : accepted (releaseStopped exUncertain .w0 exStopped) = true ∧
    occupied exReleased = 2 ∧ exReleased.dayPaid = 750000 ∧
    exReleased.lifetimePaid = 750000 ∧ exReleased.ledger.length = 3 := by decide
example : refusal (dispatch exReleased demoEnv .w0 exReq0) =
    some .providerConsumed := by decide

example : accepted (admit exReleased demoEnv .w0 exReq0) = true ∧
    occupied (witnessState (admit exReleased demoEnv .w0 exReq0)) = 2 ∧
    (witnessState (admit exReleased demoEnv .w0 exReq0)).dayPaid = 750000 := by decide
example : refusal (admit exReleased demoEnv .w0
    {exReq0 with payload := demoPayload .writer 99 100}) =
    some .conflictingPayload := by decide
/-- External receipt reuse is refused for a new effect and an otherwise free slot. -/
example : refusal (admit exW0 demoEnv .w1 (demoRequest exW0 99 .writer 99 100)) =
    some .reservationReuse := by decide

def exZero := witnessState (setTarget exThree demoEnv (demoFence exThree) 0)
def exDrop := witnessState (setTarget exThree demoEnv (demoFence exThree) 1)
example : exDrop.target = 1 ∧ occupied exDrop = 3 ∧ occupied exDrop ≤ hardTotal := by decide
example : exZero.draining = true ∧ occupied exZero = 3 ∧
    refusal (dispatch exZero demoEnv .w0 {exReq0 with fence := demoFence exZero}) =
      some .draining := by decide

example : refusal (admit exTarget demoEnv .w0
    {exReq0 with fence := {exReq0.fence with gen := 0}}) = some .staleGeneration := by decide
example : refusal (admit exTarget demoEnv .w0
    {exReq0 with fence := {exReq0.fence with epoch := 0}}) = some .staleEpoch := by decide
example : refusal (admit exTarget demoEnv .w0
    {exReq0 with fence := {exReq0.fence with deadline := exTarget.now}}) =
      some .deadlineExpired := by decide
example : refusal (admit exTarget demoEnv .w0
    {exReq0 with fence := {exReq0.fence with lease := exTarget.now}}) =
      some .leaseExpired := by decide
/-- A guard-boundary fixture, not a claimed reachable state. -/
example : refusal (admit {exTarget with dayPaid := dailyCap} demoEnv .w0 exReq0) =
    some .budgetExhausted := by decide

/-- Non-admitted mutant 1: counting only running slots loses reserved/uncertain occupancy. -/
def mutantRunningOnly (s : S) : Nat := ([Slot.w0, .w1, .r0].filter fun sl =>
  match s.slots sl with | some o => o.phase == .running | none => false).length
example : mutantRunningOnly exUncertain = 0 ∧ occupied exUncertain = 3 := by decide
/-- Non-admitted mutant 2: a closed deadline admits the exact boundary wrongly. -/
example : exTarget.now ≤ exTarget.now ∧
    ¬Fresh exTarget demoEnv {exReq0.fence with deadline := exTarget.now} exReq0.payload := by decide

#eval (writers exThree, reviewers exThree, occupied exThree, exThree.dayPaid)
#eval (occupied exUncertain, occupied exReleased, exReleased.lifetimePaid)
#eval refusal (admit exW0 demoEnv .w1 (demoRequest exW0 99 .writer 99 100))
#eval refusal (dispatch exReleased demoEnv .w0 exReq0)

end AgentScaleControl
