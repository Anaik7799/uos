/-
  Abstract safety model for the development harness failure classifier.
  The `canonical` bit abstracts parsing of the recorded backend exit string;
  `sourceDigestConflict` abstracts both accepted write-conflict spellings.
  Actual guardian timeouts arrive as `timeout` or `guardian_timeout`; exit 124
  is additionally excluded if it appears in a recorded string. This file does
  not prove the Gleam parser, filesystem, process containment, or refinement
  from the running implementation to this model.
-/

namespace UOS.HarnessFailedCheck

inductive Status where
  | failed
  | executed
  deriving DecidableEq, Repr

inductive Tool where
  | writeFile
  | build
  | test
  | other
  deriving DecidableEq, Repr

inductive Failure where
  | sourceDigestConflict
  | backendExit (code : Nat) (canonical : Bool)
  | other
  deriving DecidableEq, Repr

inductive Disposition where
  | unappliedWriteConflict
  | nonzeroCheckExit (code : Nat)
  | unknown
  deriving DecidableEq, Repr

def classify : Status → Tool → Failure → Disposition
  | .failed, .writeFile, .sourceDigestConflict => .unappliedWriteConflict
  | .failed, .build, .backendExit n true =>
      if 0 < n ∧ n < 124 then .nonzeroCheckExit n else .unknown
  | .failed, .test, .backendExit n true =>
      if 0 < n ∧ n < 124 then .nonzeroCheckExit n else .unknown
  | _, _, _ => .unknown

-- Only the existing exact write-conflict case may settle, and then only if
-- the separately bound resolution is present. A failed check remains held.
def maySettle : Disposition → Bool → Bool
  | .unappliedWriteConflict, hasResolution => hasResolution
  | _, _ => false

theorem nonzero_check_never_settles (n : Nat) (hasResolution : Bool) :
    maySettle (.nonzeroCheckExit n) hasResolution = false := by
  rfl

theorem failed_build_never_settles (f : Failure) (hasResolution : Bool) :
    maySettle (classify .failed .build f) hasResolution = false := by
  cases f with
  | sourceDigestConflict => rfl
  | other => rfl
  | backendExit n canonical =>
      cases canonical with
      | false => rfl
      | true =>
          simp only [classify]
          split <;> rfl

theorem failed_test_never_settles (f : Failure) (hasResolution : Bool) :
    maySettle (classify .failed .test f) hasResolution = false := by
  cases f with
  | sourceDigestConflict => rfl
  | other => rfl
  | backendExit n canonical =>
      cases canonical with
      | false => rfl
      | true =>
          simp only [classify]
          split <;> rfl

theorem timeout_exit_is_unknown :
    classify .failed .build (.backendExit 124 true) = .unknown := by
  decide

theorem write_conflict_requires_resolution (hasResolution : Bool) :
    maySettle (classify .failed .writeFile .sourceDigestConflict) hasResolution
      = hasResolution := by
  rfl

#print axioms nonzero_check_never_settles
#print axioms failed_build_never_settles
#print axioms failed_test_never_settles
#print axioms timeout_exit_is_unknown
#print axioms write_conflict_requires_resolution

end UOS.HarnessFailedCheck
