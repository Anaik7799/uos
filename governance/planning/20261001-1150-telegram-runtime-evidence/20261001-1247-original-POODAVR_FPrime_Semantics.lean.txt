/- POODAVR_FPrime_Semantics.lean — Lean 4 Formal Model of POODAVR 7-Stage Cybernetic Loop,
   NASA JPL F Prime (F') Statechart Semantics, and Denotational Sheaf Valuation (SC-POODAVR-001, SC-FPRIME-001).

   Formalizes:
   1. POODAVR 7-Stage Lifecycle: Predict -> Observe -> Orient -> Decide -> Act -> Verify -> Reflect.
   2. Fail-Closed Andon Invariant: Any hazard breach or unledgered task transitions to ConstitutionalHalt.
   3. NASA JPL F Prime Guard Safety: Act state is unreachable from Orient when storage serial is locked.
   4. 13D Trace Coordinate Monotonicity: Causal epoch advances monotonically under valid valuation.
-/

namespace UOS.POODAVR

/-- The 7 stages of the POODAVR Cybernetic Loop plus terminal ConstitutionalHalt. -/
inductive PoodavrPhase where
  | Predict
  | Observe
  | Orient
  | Decide
  | Act
  | Verify
  | Reflect
  | ConstitutionalHalt
  deriving Repr, DecidableEq

/-- The canonical host OS NVMe serial permanently locked against mutation. -/
def HARD_DENIED_SYSTEM_OS_SERIAL : String := "25503L801736"

/-- An Intent presented to the POODAVR loop. -/
structure PoodavrIntent where
  id : Nat
  target_disk : String
  is_ledgered_in_sa_plan : Bool
  constitutional_health_ppm : Nat -- parts per million, e.g. 850000 = 0.85
  deriving Repr, DecidableEq

/-- System state during a POODAVR cycle. -/
structure PoodavrState where
  phase : PoodavrPhase
  causal_epoch : Nat
  halt_code : Option Int
  deriving Repr, DecidableEq

/-- Check if an intent violates the hardware storage interlock or Jidoka sa-plan exclusivity. -/
def is_intent_safe (intent : PoodavrIntent) : Bool :=
  (intent.target_disk != HARD_DENIED_SYSTEM_OS_SERIAL) &&
  intent.is_ledgered_in_sa_plan &&
  (intent.constitutional_health_ppm >= 850000)

/-- Transition function for the Orient stage of POODAVR. -/
def orient_transition (intent : PoodavrIntent) (st : PoodavrState) : PoodavrState :=
  if is_intent_safe intent then
    { st with phase := PoodavrPhase.Decide }
  else
    { st with phase := PoodavrPhase.ConstitutionalHalt, halt_code := some (-32002) }

/-- Transition function for Decide to Act. -/
def decide_transition (st : PoodavrState) : PoodavrState :=
  match st.phase with
  | PoodavrPhase.Decide => { st with phase := PoodavrPhase.Act }
  | other => st

/-- THEOREM 1: Hard Denied Storage & Jidoka Safety.
    If an intent targets the locked host OS disk or lacks sa-plan ledgering,
    the Orient stage strictly transitions to ConstitutionalHalt with Andon Halt code -32002. -/
theorem orient_fails_closed_on_hazard (intent : PoodavrIntent) (st : PoodavrState)
    (h_breach : is_intent_safe intent = false) :
    (orient_transition intent st).phase = PoodavrPhase.ConstitutionalHalt ∧
    (orient_transition intent st).halt_code = some (-32002) := by
  dsimp [orient_transition]
  rw [h_breach]
  dsimp
  constructor
  · rfl
  · rfl

/-- THEOREM 2: Act Unreachability under Hazard.
    An unsafe intent can NEVER reach the Act stage through the Orient-Decide path. -/
theorem act_unreachable_on_hazard (intent : PoodavrIntent) (st : PoodavrState)
    (h_breach : is_intent_safe intent = false) :
    (decide_transition (orient_transition intent st)).phase ≠ PoodavrPhase.Act := by
  have h_halt := orient_fails_closed_on_hazard intent st h_breach
  dsimp [decide_transition]
  rw [h_halt.left]
  dsimp
  intro h_contra
  contradiction

/-- Transition function for Verify stage: monotonic epoch progression on verification pass. -/
def verify_transition (st : PoodavrState) (verification_passed : Bool) : PoodavrState :=
  if verification_passed then
    { st with phase := PoodavrPhase.Reflect, causal_epoch := st.causal_epoch + 1 }
  else
    { st with phase := PoodavrPhase.ConstitutionalHalt, halt_code := some (-32003) }

/-- THEOREM 3: Causal Epoch Monotonicity.
    Passing verification strictly increases the 13D trace causal epoch by 1. -/
theorem verify_epoch_monotonic (st : PoodavrState) :
    (verify_transition st true).causal_epoch = st.causal_epoch + 1 := by
  dsimp [verify_transition]
  rfl

/-- F Prime deterministic cycle: Predict -> Observe -> Orient -> Decide -> Act -> Verify -> Reflect -> Predict. -/
def full_cycle_phase_succ (p : PoodavrPhase) : PoodavrPhase :=
  match p with
  | PoodavrPhase.Predict => PoodavrPhase.Observe
  | PoodavrPhase.Observe => PoodavrPhase.Orient
  | PoodavrPhase.Orient => PoodavrPhase.Decide
  | PoodavrPhase.Decide => PoodavrPhase.Act
  | PoodavrPhase.Act => PoodavrPhase.Verify
  | PoodavrPhase.Verify => PoodavrPhase.Reflect
  | PoodavrPhase.Reflect => PoodavrPhase.Predict
  | PoodavrPhase.ConstitutionalHalt => PoodavrPhase.ConstitutionalHalt

/-- THEOREM 4: F Prime 7-Stage Cycle Determinism.
    Iterating full_cycle_phase_succ 7 times from Predict returns to Predict. -/
theorem fprime_7stage_cycle_preservation :
    full_cycle_phase_succ (full_cycle_phase_succ (full_cycle_phase_succ
      (full_cycle_phase_succ (full_cycle_phase_succ (full_cycle_phase_succ
        (full_cycle_phase_succ PoodavrPhase.Predict)))))) = PoodavrPhase.Predict := by
  rfl

end UOS.POODAVR
