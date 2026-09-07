import Std

/-
UOS C07 bounded durable-journal refinement, authored 2026-09-07.

Structural source correspondence (not a differential interpreter proof):
  candidate 1c69804b45f13af549f0070a711ed089cee8a418
  apps/uos_swarm/src/uos_swarm/session_sync.gleam
  apps/uos_swarm/src/session_sync_ffi.erl

The model makes committed sequence/epoch state, exact operation-body replay,
pending/torn fail-closed evidence, per-resource leases, and ACK non-authority
explicit. It does not prove filesystem or power-loss durability, digest or IAM
security, wall/boot-clock validity, production effect isolation, or refinement
of the concrete Gleam/Erlang interpreter.
-/
namespace UOS.AgenticJournal

inductive Session where
  | claude | codex | agy
deriving DecidableEq, Repr

inductive Resource where
  | integration | runtimeA | runtimeB
deriving DecidableEq, Repr

inductive Evidence where
  | clean | pending | torn
deriving DecidableEq, Repr

structure Lease where
  owner : Session
  epoch : Nat
deriving DecidableEq, Repr

structure Command where
  operationId : Nat
  bodyHash : Nat
  actor : Session
  resource : Resource
deriving DecidableEq, Repr

structure Ticket where
  actor : Session
  resource : Resource
  epoch : Nat
  policyRevision : Nat
  candidateRevision : Nat
  attempt : Nat
  task : Nat
  action : Nat
deriving DecidableEq, Repr

structure DecisionKey where
  actor : Session
  resource : Resource
  epoch : Nat
  candidateRevision : Nat
  attempt : Nat
  task : Nat
  action : Nat
deriving DecidableEq, Repr

inductive Outcome where
  | accepted | replayed | rejectedConflict | rejectedEvidence | rejectedBusy
deriving DecidableEq, Repr

structure Durable where
  sequence : Nat
  epochs : Resource → Nat
  leases : Resource → Option Lease
  seenBodies : Nat → Option Nat
  acknowledgements : Nat
  effects : Nat
  evidence : Evidence
  policyRevision : Nat
  candidateRevision : Nat
  authorized : Session → Resource → Bool
  reservedAttempt : Session → Resource → Nat
  validatedDecision : DecisionKey → Bool

structure Transition where
  store : Durable
  outcome : Outcome

def updateAt [DecidableEq α] (f : α → β) (key : α) (value : β) : α → β :=
  fun candidate => if candidate = key then value else f candidate

def ValidHolder (d : Durable) (resource : Resource) (owner : Session) (epoch : Nat) : Prop :=
  d.evidence = .clean ∧ d.leases resource = some { owner := owner, epoch := epoch }

def CanEffect (d : Durable) (ticket : Ticket) : Prop :=
  ValidHolder d ticket.resource ticket.actor ticket.epoch ∧
  d.policyRevision = ticket.policyRevision ∧
  d.candidateRevision = ticket.candidateRevision ∧
  d.authorized ticket.actor ticket.resource = true ∧
  d.reservedAttempt ticket.actor ticket.resource = ticket.attempt ∧
  ticket.attempt > 0 ∧
  d.validatedDecision {
    actor := ticket.actor
    resource := ticket.resource
    epoch := ticket.epoch
    candidateRevision := ticket.candidateRevision
    attempt := ticket.attempt
    task := ticket.task
    action := ticket.action
  } = true

instance (d : Durable) (r : Resource) (a : Session) (e : Nat) :
    Decidable (ValidHolder d r a e) := by
  unfold ValidHolder
  infer_instance

instance (d : Durable) (t : Ticket) : Decidable (CanEffect d t) := by
  unfold CanEffect
  infer_instance

def reject (d : Durable) (why : Outcome) : Transition :=
  { store := d, outcome := why }

def commitClaim (d : Durable) (command : Command) : Transition :=
  match d.evidence with
  | .pending | .torn => reject d .rejectedEvidence
  | .clean =>
      match d.seenBodies command.operationId with
      | some prior =>
          if prior = command.bodyHash then reject d .replayed
          else reject d .rejectedConflict
      | none =>
          match d.leases command.resource with
          | some _ => reject d .rejectedBusy
          | none =>
              let nextEpoch := d.epochs command.resource + 1
              { store :=
                  { d with
                    sequence := d.sequence + 1
                    epochs := updateAt d.epochs command.resource nextEpoch
                    leases := updateAt d.leases command.resource
                      (some { owner := command.actor, epoch := nextEpoch })
                    seenBodies := updateAt d.seenBodies command.operationId
                      (some command.bodyHash) }
                outcome := .accepted }

/- ACK is a committed observation. It records exact operation-body identity but
   does not alter leases, epochs, policy, authorization, reservations, or effects. -/
def commitAck (d : Durable) (command : Command) : Transition :=
  match d.evidence with
  | .pending | .torn => reject d .rejectedEvidence
  | .clean =>
      match d.seenBodies command.operationId with
      | some prior =>
          if prior = command.bodyHash then reject d .replayed
          else reject d .rejectedConflict
      | none =>
          { store :=
              { d with
                sequence := d.sequence + 1
                seenBodies := updateAt d.seenBodies command.operationId
                  (some command.bodyHash)
                acknowledgements := d.acknowledgements + 1 }
            outcome := .accepted }

/- A pre-rename crash leaves the last committed head intact and exposes pending
   evidence. A post-commit crash leaves the atomically committed store intact. -/
def crashBeforeCommit (d : Durable) : Durable := { d with evidence := .pending }
def crashAfterCommit (d : Durable) : Durable := d
def markTorn (d : Durable) : Durable := { d with evidence := .torn }

def recover (d : Durable) : Option Durable :=
  if d.evidence = .clean then some d else none

def CommittedHeadEq (left right : Durable) : Prop :=
  left.sequence = right.sequence ∧ left.epochs = right.epochs ∧ left.leases = right.leases

theorem no_two_valid_lease_holders (d : Durable) (resource : Resource)
    (first second : Session) (firstEpoch secondEpoch : Nat)
    (hFirst : ValidHolder d resource first firstEpoch)
    (hSecond : ValidHolder d resource second secondEpoch) :
    first = second ∧ firstEpoch = secondEpoch := by
  have equalLease := hFirst.2.symm.trans hSecond.2
  have exactLease :
      ({ owner := first, epoch := firstEpoch } : Lease) =
      { owner := second, epoch := secondEpoch } := Option.some.inj equalLease
  exact ⟨congrArg Lease.owner exactLease, congrArg Lease.epoch exactLease⟩

theorem pending_cannot_grant (d : Durable) (resource : Resource)
    (owner : Session) (epoch : Nat) (h : d.evidence = .pending) :
    ¬ ValidHolder d resource owner epoch := by
  intro valid
  exact Evidence.noConfusion (h.symm.trans valid.1)

theorem torn_cannot_grant (d : Durable) (resource : Resource)
    (owner : Session) (epoch : Nat) (h : d.evidence = .torn) :
    ¬ ValidHolder d resource owner epoch := by
  intro valid
  exact Evidence.noConfusion (h.symm.trans valid.1)

theorem pending_recovery_fails_closed (d : Durable) :
    recover (crashBeforeCommit d) = none := by
  simp [recover, crashBeforeCommit]

theorem torn_recovery_fails_closed (d : Durable) : recover (markTorn d) = none := by
  simp [recover, markTorn]

theorem clean_recovery_replays_committed (d : Durable) (h : d.evidence = .clean) :
    recover d = some d := by
  simp [recover, h]

theorem crash_before_preserves_committed_head (d : Durable) :
    CommittedHeadEq (crashBeforeCommit d) d := by
  exact ⟨rfl, rfl, rfl⟩

theorem crash_after_preserves_committed_head (d : Durable) :
    CommittedHeadEq (crashAfterCommit d) d := by
  exact ⟨rfl, rfl, rfl⟩

theorem fresh_claim_advances_sequence_and_epoch (d : Durable) (command : Command)
    (clean : d.evidence = .clean)
    (fresh : d.seenBodies command.operationId = none)
    (free : d.leases command.resource = none) :
    (commitClaim d command).outcome = .accepted ∧
    (commitClaim d command).store.sequence = d.sequence + 1 ∧
    (commitClaim d command).store.epochs command.resource =
      d.epochs command.resource + 1 := by
  simp [commitClaim, clean, fresh, free, updateAt]

theorem same_body_duplicate_replays (d : Durable) (command : Command)
    (clean : d.evidence = .clean)
    (seen : d.seenBodies command.operationId = some command.bodyHash) :
    commitClaim d command = { store := d, outcome := .replayed } := by
  simp [commitClaim, clean, seen, reject]

theorem conflicting_duplicate_rejected (d : Durable) (command : Command) (prior : Nat)
    (clean : d.evidence = .clean)
    (seen : d.seenBodies command.operationId = some prior)
    (conflict : prior ≠ command.bodyHash) :
    commitClaim d command = { store := d, outcome := .rejectedConflict } := by
  simp [commitClaim, clean, seen, conflict, reject]

theorem claim_does_not_change_other_resource (d : Durable) (command : Command)
    (clean : d.evidence = .clean)
    (fresh : d.seenBodies command.operationId = none)
    (free : d.leases command.resource = none)
    (other : Resource) (different : other ≠ command.resource) :
    (commitClaim d command).store.leases other = d.leases other ∧
    (commitClaim d command).store.epochs other = d.epochs other := by
  simp [commitClaim, clean, fresh, free, updateAt, different]

theorem accepted_claim_survives_post_commit_crash (d : Durable) (command : Command)
    (clean : d.evidence = .clean)
    (fresh : d.seenBodies command.operationId = none)
    (free : d.leases command.resource = none) :
    let committed := (commitClaim d command).store
    (crashAfterCommit committed).sequence = d.sequence + 1 ∧
    (crashAfterCommit committed).epochs command.resource =
      d.epochs command.resource + 1 := by
  simp [crashAfterCommit, commitClaim, clean, fresh, free, updateAt]

theorem ack_preserves_action_boundary (d : Durable) (command : Command) :
    let after := (commitAck d command).store
    after.leases = d.leases ∧ after.epochs = d.epochs ∧
    after.effects = d.effects ∧ after.authorized = d.authorized ∧
    after.policyRevision = d.policyRevision ∧
    after.candidateRevision = d.candidateRevision ∧
    after.reservedAttempt = d.reservedAttempt ∧
    after.validatedDecision = d.validatedDecision := by
  cases evidence : d.evidence with
  | clean =>
      cases seen : d.seenBodies command.operationId with
      | none => simp [commitAck, evidence, seen]
      | some prior =>
          by_cases same : prior = command.bodyHash <;>
            simp [commitAck, evidence, seen, same, reject]
  | pending => simp [commitAck, evidence, reject]
  | torn => simp [commitAck, evidence, reject]

theorem ack_does_not_grant_action (d : Durable) (command : Command) (ticket : Ticket) :
    CanEffect (commitAck d command).store ticket ↔ CanEffect d ticket := by
  unfold CanEffect ValidHolder
  cases evidence : d.evidence with
  | clean =>
      cases seen : d.seenBodies command.operationId with
      | none => simp [commitAck, evidence, seen]
      | some prior =>
          by_cases same : prior = command.bodyHash <;>
            simp [commitAck, evidence, seen, same, reject]
  | pending => simp [commitAck, evidence, reject]
  | torn => simp [commitAck, evidence, reject]

theorem missing_decision_record_cannot_effect (d : Durable) (ticket : Ticket)
    (missing : d.validatedDecision {
      actor := ticket.actor
      resource := ticket.resource
      epoch := ticket.epoch
      candidateRevision := ticket.candidateRevision
      attempt := ticket.attempt
      task := ticket.task
      action := ticket.action
    } = false) :
    ¬ CanEffect d ticket := by
  intro permitted
  rcases permitted with ⟨_, _, _, _, _, _, present⟩
  rw [missing] at present
  contradiction

end UOS.AgenticJournal
