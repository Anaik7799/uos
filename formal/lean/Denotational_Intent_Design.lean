/- Denotational_Intent_Design.lean — Lean 4 Formal Model of
   Denotational Semantics, State Lattice (Sigma_bot, sqsubseteq),
   and Fail-Closed Interlocks for UOS Intent-Based Operations.

   Companion to:
   - apps/cepaf_gleam/src/cepaf_gleam/semantics/algebraic_atlas.gleam
   - apps/cepaf_gleam/src/cepaf_gleam/intent/config.gleam
   - formal/lean/Algebraic_Atlas_Intent.lean
   - formal/lean/Traceability.lean
   - contracts/rules/comprehensive-checklist-contract.md

   STAMP Compliance:
   - SC-INTENT-ATLAS-001
   - SC-JIDOKA-001 (Fractal Jidoka Andon Stop Line)
   - HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"
-/

namespace UOS.Denotational

/-- The Ten Fractal Chart Indices corresponding to L0 through L9 -/
inductive ChartIndex where
  | L0Constitutional
  | L1AtomicKernel
  | L2Homeostasis
  | L3Transactions
  | L4SystemDaemons
  | L5CognitiveOODA
  | L6SwarmMesh
  | L7Federation
  | L8Verification
  | L9Sovereignty
deriving Repr, DecidableEq

/-- 13D Trace Coordinates associated with any point in the Atlas -/
structure TraceCoordinates where
  dim01_timestampUs : Nat
  dim02_layerId : Nat
  dim03_holonId : String
  dim04_causalEpoch : Nat
  dim05_shannonEntropyBits : Nat
  dim06_lyapunovEnergy : Nat
  dim07_cyclomaticComplexity : Nat
  dim08_divergencePPM : Nat
  dim09_itqsQuality : Nat
  dim10_quarantineFlags : Nat
  dim11_workerHash : String
  dim12_planDigest : String
  dim13_parentDigest : String
deriving Repr, DecidableEq

/-- System State Sigma at a given chart -/
structure State where
  chart : ChartIndex
  coordinates : TraceCoordinates
  payload : String
  constitutionalHealth : Nat  -- in [0, 100], representing percentage
deriving Repr, DecidableEq

/-- Declarative Intent Specification -/
structure Intent where
  intentId : String
  proposerHolon : String
  authority : String
  targetDriveSerial : String
  criticality : String
  guardianApproved : Bool
  sourceChart : ChartIndex
  targetChart : ChartIndex
  action : String
  preservesInvariants : Bool
deriving Repr, DecidableEq

/-- State Lattice with Bottom element representing fail-closed abortion -/
inductive StateBot where
  | bottom : StateBot
  | state : State → StateBot
deriving Repr, DecidableEq

/-- Lattice Partial Ordering: bot is less than or equal to everything, and states are ordered by equality -/
def leq (s1 s2 : StateBot) : Prop :=
  match s1, s2 with
  | StateBot.bottom, _ => True
  | StateBot.state a, StateBot.state b => a = b
  | StateBot.state _, StateBot.bottom => False

instance : LE StateBot where
  le := leq

/-- Reflexivity of StateBot lattice order -/
theorem leq_refl (s : StateBot) : s ≤ s := by
  cases s <;> simp [LE.le, leq]

/-- Transitivity of StateBot lattice order -/
theorem leq_trans (a b c : StateBot) (h1 : a ≤ b) (h2 : b ≤ c) : a ≤ c := by
  cases a <;> cases b <;> cases c
  · simp [LE.le, leq]
  · simp [LE.le, leq]
  · contradiction
  · contradiction
  · simp [LE.le, leq]
  · simp [LE.le, leq]
  · contradiction
  · cases h1
    cases h2
    simp [LE.le, leq]

/-- Denotational Semantic Valuation Function: D[[ Intent ]] (State) -> StateBot -/
def evaluate (i : Intent) (s : State) : StateBot :=
  -- Guard 1: Non-sa-plan authority fails closed to bottom (SC-JIDOKA-001)
  if i.authority ≠ "sa-plan" then
    StateBot.bottom
  -- Guard 2: Root OS NVMe mutation fails closed to bottom
  else if i.targetDriveSerial = "25503L801736" then
    StateBot.bottom
  -- Guard 3: DAL-A intent without Guardian approval fails closed to bottom
  else if i.criticality = "DAL-A" ∧ ¬i.guardianApproved then
    StateBot.bottom
  -- Guard 4: Chart continuity guard
  else if s.chart ≠ i.sourceChart then
    StateBot.bottom
  -- Guard 5: Constitutional health guard (H_C >= 85%)
  else if s.constitutionalHealth < 85 then
    StateBot.bottom
  -- Guard 6: Invariant preservation guard
  else if ¬i.preservesInvariants then
    StateBot.bottom
  -- Valid transition: advance causal epoch and transition to target chart
  else
    let nextCoords : TraceCoordinates :=
      { s.coordinates with
        dim02_layerId := 0,
        dim04_causalEpoch := s.coordinates.dim04_causalEpoch + 1 }
    let nextState : State :=
      { chart := i.targetChart,
        coordinates := nextCoords,
        payload := "denotational-eval-" ++ i.action,
        constitutionalHealth := s.constitutionalHealth }
    StateBot.state nextState

/-- Theorem: Unauthorized Non-Sa-Plan Intent Fails Closed to Bottom -/
theorem safety_fail_closed_non_sa_plan (i : Intent) (s : State) (h : i.authority ≠ "sa-plan") :
    evaluate i s = StateBot.bottom := by
  simp [evaluate, h]

/-- Theorem: Root OS NVMe Mutation Fails Closed to Bottom -/
theorem safety_fail_closed_drive_lock (i : Intent) (s : State) (h : i.targetDriveSerial = "25503L801736") :
    evaluate i s = StateBot.bottom := by
  simp [evaluate]
  intro h_auth
  simp [h]

/-- Theorem: Unapproved DAL-A Criticality Fails Closed to Bottom -/
theorem safety_fail_closed_guardian_veto (i : Intent) (s : State) (h_dal : i.criticality = "DAL-A") (h_veto : ¬i.guardianApproved) :
    evaluate i s = StateBot.bottom := by
  simp [evaluate]
  intro h_auth h_drive
  simp [h_dal, h_veto]

/-- Intent Composition: Sequential execution of intent1 followed by intent2 -/
def composeIntents (i1 i2 : Intent) (s : State) : StateBot :=
  match evaluate i1 s with
  | StateBot.bottom => StateBot.bottom
  | StateBot.state s' => evaluate i2 s'

/-- Theorem: Bottom Propagation under Intent Composition -/
theorem bottom_propagation (i1 i2 : Intent) (s : State) (h : evaluate i1 s = StateBot.bottom) :
    composeIntents i1 i2 s = StateBot.bottom := by
  simp [composeIntents, h]

end UOS.Denotational
