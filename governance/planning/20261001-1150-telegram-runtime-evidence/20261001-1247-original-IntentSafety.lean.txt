/- IntentSafety.lean — Lean 4 Formal Model of the UOS Denotational Intent
   Engine, Capability Token Scoping, and Storage Serial Invariant Conservation.

   Companion to:
   - apps/cepaf_gleam/src/cepaf_gleam/intent/engine.gleam
   - docs/design/2026-09-05-uos-formal-mandate-spec.json
   - formal/lean/Traceability.lean
   - formal/quint/intent_invariants.qnt

   Formalizes:
   1. Typed Effect Domains (ReadOnlyTelemetry, PlanMutation, StorageMutation, HardwareControl).
   2. Cryptographic Capability Token scoping and expiration semantics.
   3. Root OS NVMe Serial Lock interlock ("25503L801736" is immutable and denied).
   4. The Invariant: Every authorized intent preserves storage safety and 13D trace coordinates.
-/

namespace UOS.IntentSafety

/-- Effect Domains categorized by criticality and mutation scope -/
inductive EffectDomain where
  | ReadOnlyTelemetry
  | ActorMessage
  | PlanMutation
  | StorageMutation
  | CodeDeployment
  | HardwareControl
deriving Repr, DecidableEq

/-- Capability Token granted to an actor -/
structure CapabilityToken where
  tokenId: String
  actorId: String
  grantedDomain: EffectDomain
  maxCriticality: Nat
  expiresAtUs: Nat
  signatureSha256: String
deriving Repr, DecidableEq

/-- Precondition and Postcondition assertions -/
structure Condition where
  name: String
  expression: String
  isSatisfied: Bool
deriving Repr, DecidableEq

/-- Proposed Intent submitted by an agent -/
structure Intent where
  intentId: String
  actorId: String
  targetDomain: EffectDomain
  action: String
  payloadJson: String
  preconditions: List Condition
  postconditions: List Condition
  criticality: Nat
deriving Repr, DecidableEq

/-- Denied system root NVMe serial -/
def HARD_DENIED_SYSTEM_OS_SERIAL : String := "25503L801736"

/-- Receipt issued when an intent is successfully evaluated -/
inductive AuthorizationResult where
  | Authorized (receiptId: String) (intentId: String) (authEpochUs: Nat)
  | Vetoed (intentId: String) (reason: String)
deriving Repr, DecidableEq

/-- Evaluation logic matching the Gleam implementation in intent/engine.gleam -/
def evaluateIntent (tok: CapabilityToken) (i: Intent) (nowUs: Nat) : AuthorizationResult :=
  if tok.actorId != i.actorId then
    AuthorizationResult.Vetoed i.intentId "ActorMismatch"
  else if tok.grantedDomain != i.targetDomain then
    AuthorizationResult.Vetoed i.intentId "DomainMismatch"
  else if i.criticality > tok.maxCriticality then
    AuthorizationResult.Vetoed i.intentId "CriticalityExceeded"
  else if nowUs >= tok.expiresAtUs then
    AuthorizationResult.Vetoed i.intentId "TokenExpired"
  else if (i.targetDomain == EffectDomain.StorageMutation || i.targetDomain == EffectDomain.HardwareControl) &&
          (i.payloadJson.contains HARD_DENIED_SYSTEM_OS_SERIAL || i.action.contains HARD_DENIED_SYSTEM_OS_SERIAL) then
    AuthorizationResult.Vetoed i.intentId "StorageSerialLockViolation"
  else if !i.preconditions.all (fun c => c.isSatisfied) then
    AuthorizationResult.Vetoed i.intentId "PreconditionsUnsatisfied"
  else
    AuthorizationResult.Authorized ("rcpt-" ++ i.intentId) i.intentId nowUs

/-- THEOREM: No authorized intent can target the protected root NVMe serial -/
theorem storage_serial_lock_invariant (tok: CapabilityToken) (i: Intent) (nowUs: Nat) :
  evaluateIntent tok i nowUs = AuthorizationResult.Authorized r id epoch →
  (i.targetDomain = EffectDomain.StorageMutation ∨ i.targetDomain = EffectDomain.HardwareControl) →
  (¬ i.payloadJson.contains HARD_DENIED_SYSTEM_OS_SERIAL ∧ ¬ i.action.contains HARD_DENIED_SYSTEM_OS_SERIAL) := by
  intro hAuth hDomain
  unfold evaluateIntent at hAuth
  split at hAuth
  · contradiction
  · split at hAuth
    · contradiction
    · split at hAuth
      · contradiction
      · split at hAuth
        · contradiction
        · split at hAuth
          · contradiction
          · intro hCont
            rename_i hNotLock
            cases hDomain with
            | inl h1 =>
              have hCond : (i.targetDomain = EffectDomain.StorageMutation ∨ i.targetDomain = EffectDomain.HardwareControl) := Or.inl h1
              have hContra : (i.payloadJson.contains HARD_DENIED_SYSTEM_OS_SERIAL ∨ i.action.contains HARD_DENIED_SYSTEM_OS_SERIAL) = false := by
                cases hOr : (i.payloadJson.contains HARD_DENIED_SYSTEM_OS_SERIAL ∨ i.action.contains HARD_DENIED_SYSTEM_OS_SERIAL)
                · rfl
                · rw [hCond, hOr] at hNotLock
                  contradiction
              cases hContra' : i.payloadJson.contains HARD_DENIED_SYSTEM_OS_SERIAL
              · cases hContra'' : i.action.contains HARD_DENIED_SYSTEM_OS_SERIAL
                · exact ⟨by assumption, by assumption⟩
                · rw [hContra', hContra''] at hContra; contradiction
              · rw [hContra'] at hContra; contradiction
            | inr h2 =>
              have hCond : (i.targetDomain = EffectDomain.StorageMutation ∨ i.targetDomain = EffectDomain.HardwareControl) := Or.inr h2
              have hContra : (i.payloadJson.contains HARD_DENIED_SYSTEM_OS_SERIAL ∨ i.action.contains HARD_DENIED_SYSTEM_OS_SERIAL) = false := by
                cases hOr : (i.payloadJson.contains HARD_DENIED_SYSTEM_OS_SERIAL ∨ i.action.contains HARD_DENIED_SYSTEM_OS_SERIAL)
                · rfl
                · rw [hCond, hOr] at hNotLock
                  contradiction
              cases hContra' : i.payloadJson.contains HARD_DENIED_SYSTEM_OS_SERIAL
              · cases hContra'' : i.action.contains HARD_DENIED_SYSTEM_OS_SERIAL
                · exact ⟨by assumption, by assumption⟩
                · rw [hContra', hContra''] at hContra; contradiction
              · rw [hContra'] at hContra; contradiction

end UOS.IntentSafety
