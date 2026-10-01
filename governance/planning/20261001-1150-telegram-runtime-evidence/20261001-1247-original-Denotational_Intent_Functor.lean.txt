/- Denotational_Intent_Functor.lean — Lean 4 Monadic State Transformer
   and Fail-Closed Functorial Valuation for UOS Intent-Based Operations.

   Companion to:
   - formal/lean/Denotational_Intent_Design.lean
   - apps/cepaf_gleam/src/cepaf_gleam/semantics/algebraic_atlas.gleam
   - apps/cepaf_gleam/src/cepaf_gleam/intent/config.gleam
   - contracts/rules/comprehensive-checklist-contract.md

   STAMP Compliance:
   - SC-INTENT-ATLAS-001
   - SC-DENOTATIONAL-INTENT-001
   - SC-JIDOKA-001 (Fractal Jidoka Andon Stop Line)
   - HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"
-/

import Lean

namespace UOS.Denotational.Monad

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

structure TraceCoords where
  timestampUs : Nat
  layerId : Nat
  lyapunovTrend : Nat
  shannonEntropy : Nat
deriving Repr, DecidableEq

structure State where
  version : Nat
  chart : ChartIndex
  coords : TraceCoords
  payload : String
deriving Repr, DecidableEq

structure Intent where
  intentId : String
  authority : String
  targetDriveSerial : String
  criticality : String
  guardianApproved : Bool
  deltaVersion : Nat
deriving Repr, DecidableEq

/-- The Complete Partially Ordered Monad: T(Sigma) = Option State, where none = bot -/
def MState := Option State

def bot : MState := none

def pureState (s : State) : MState := some s

def bindState (ma : MState) (f : State → MState) : MState :=
  match ma with
  | none => none
  | some s => f s

/-- Interlock 1: Authority Interlock (SC-JIDOKA-001) -/
def validateAuthority (i : Intent) (s : State) : MState :=
  if i.authority == "sa-plan" then some s else none

/-- Interlock 2: Hardware NVMe Drive Interlock -/
def validateStorageLock (i : Intent) (s : State) : MState :=
  if i.targetDriveSerial == "25503L801736" then none else some s

/-- Interlock 3: Guardian Approval Interlock (Omega_0) -/
def validateGuardian (i : Intent) (s : State) : MState :=
  if i.criticality == "DAL-A" && !i.guardianApproved then none else some s

/-- State Transformation Step -/
def applyStateDelta (i : Intent) (s : State) : MState :=
  some { s with version := s.version + i.deltaVersion }

/-- Denotational Valuation Functor [[ I ]] -/
def evaluateMonadic (i : Intent) (ma : MState) : MState :=
  bindState ma (fun s =>
    bindState (validateAuthority i s) (fun s1 =>
      bindState (validateStorageLock i s1) (fun s2 =>
        bindState (validateGuardian i s2) (fun s3 =>
          applyStateDelta i s3
        )
      )
    )
  )

/-- Theorem: Bottom Absorption: [[ I ]](bot) = bot -/
theorem bottom_absorption (i : Intent) :
    evaluateMonadic i bot = bot := by
  rfl

/-- Theorem: Unauthorized Execution Fails Closed to Bottom -/
theorem unauthorized_fails_closed (i : Intent) (s : State) (hAuth : i.authority ≠ "sa-plan") :
    evaluateMonadic i (some s) = none := by
  unfold evaluateMonadic bindState validateAuthority
  have hCond : (i.authority == "sa-plan") = false := by
    apply beq_eq_false_iff_ne.mpr hAuth
  simp [hCond]

/-- Theorem: Root NVMe Drive Mutation Fails Closed to Bottom -/
theorem root_drive_lock_fails_closed (i : Intent) (s : State) (hDrive : i.targetDriveSerial = "25503L801736") :
    evaluateMonadic i (some s) = none := by
  unfold evaluateMonadic bindState validateStorageLock
  by_cases hAuth : i.authority == "sa-plan"
  · simp [hAuth]
    have hCond : (i.targetDriveSerial == "25503L801736") = true := by
      apply beq_eq_true_iff_eq.mpr hDrive
    simp [hCond]
  · simp [hAuth]

/-- Theorem: Unapproved DAL-A Criticality Fails Closed to Bottom -/
theorem unapproved_dal_a_fails_closed (i : Intent) (s : State) (hCrit : i.criticality = "DAL-A") (hGuard : i.guardianApproved = false) :
    evaluateMonadic i (some s) = none := by
  unfold evaluateMonadic bindState validateGuardian
  by_cases hAuth : i.authority == "sa-plan"
  · simp [hAuth]
    by_cases hDrive : i.targetDriveSerial == "25503L801736"
    · simp [hDrive]
    · simp [hDrive]
      have hCritCond : (i.criticality == "DAL-A") = true := by
        apply beq_eq_true_iff_eq.mpr hCrit
      simp [hCritCond, hGuard]
  · simp [hAuth]

end UOS.Denotational.Monad
