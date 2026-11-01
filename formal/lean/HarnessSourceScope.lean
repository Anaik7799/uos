/-
  Abstract model of the development-harness source/evidence write boundary.
  The caller supplies the already-classified path kind, public-path decision,
  exact manifest membership, exact write authorization, and workspace choice.
  This deliberately does not prove the actual Gleam string classifier,
  workspace registration, filesystem race resistance, or runtime refinement.
-/

namespace UOS.HarnessSourceScope

inductive Kind where
  | policy
  | source
  | evidence
  | other
  deriving DecidableEq, Repr

inductive Root where
  | candidate
  | canonical
  deriving DecidableEq, Repr

def isSource : Kind → Bool
  | .policy | .source => true
  | _ => false

def isEvidence : Kind → Bool
  | .evidence => true
  | _ => false

def writeAllowed (kind : Kind) (pathPublic listed workspace authorized : Bool) : Bool :=
  pathPublic && authorized &&
    (if isSource kind then listed else isEvidence kind) &&
    (if kind == .policy then workspace else true)

def rootFor (listed workspace : Bool) : Root :=
  if listed && workspace then .candidate else .canonical

theorem nonpublic_write_rejected (kind : Kind) (listed workspace authorized : Bool) :
    writeAllowed kind false listed workspace authorized = false := by
  rfl

theorem unauthorized_write_rejected (kind : Kind) (pathPublic listed workspace : Bool) :
    writeAllowed kind pathPublic listed workspace false = false := by
  cases pathPublic <;> rfl

theorem source_write_requires_manifest (kind : Kind) :
    ∀ pathPublic listed workspace authorized : Bool,
      isSource kind = true →
      writeAllowed kind pathPublic listed workspace authorized = true → listed = true := by
  cases kind <;> decide

theorem policy_write_requires_candidate :
    ∀ pathPublic listed workspace authorized : Bool,
      writeAllowed .policy pathPublic listed workspace authorized = true →
      rootFor listed workspace = .candidate := by
  decide

theorem unlisted_evidence_uses_canonical_root :
    ∀ pathPublic workspace authorized : Bool,
      writeAllowed .evidence pathPublic false workspace authorized = true →
      rootFor false workspace = .canonical := by
  decide

#print axioms nonpublic_write_rejected
#print axioms unauthorized_write_rejected
#print axioms source_write_requires_manifest
#print axioms policy_write_requires_candidate
#print axioms unlisted_evidence_uses_canonical_root

end UOS.HarnessSourceScope
