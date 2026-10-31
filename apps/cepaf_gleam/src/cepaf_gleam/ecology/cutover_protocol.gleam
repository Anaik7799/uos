//// Finite cutover policy, interpreted by a separately admitted OTP adapter.
//// This pure module is not a grant issuer, a reader barrier or host executor.
//// A successful synthetic observation does not establish its real-world truth.
//// Files are individually atomic; group consistency requires every reader to
//// remain fenced until candidate verification or verified full restoration.

import cepaf_gleam/mcp/admission
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/types.{ControlActuation, ReleaseAuthority}
import gleam/dict
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/string

pub type ExecutionBinding {
  ExecutionBinding(
    plan_id: String,
    task_id: String,
    worker: String,
    attempt: Int,
    workspace: String,
    runtime_owner: String,
  )
}

pub type Phase {
  Preparing
  Quiescing
  Replacing(index: Int)
  CheckingCandidate
  ResumingCandidate
  Committed
  Restoring(index: Int)
  CheckingPrevious
  ResumingPrevious
  RolledBack
  RecoveryQuiescing
  RecoveryHeld
}

pub type Command {
  StageFiles
  FenceReaders
  ReplaceFile(index: Int)
  VerifyCandidate
  RestoreFile(index: Int)
  VerifyPrevious
  ResumeReaders
}

pub type Observation {
  Succeeded
  Prepared(manifest: String, physical_count: Int)
  Verified(candidate: String)
  Failed
}

/// The adapter must derive this receipt from the actual bounded operation.
/// Its fields fence stale/cross-transaction ACKs; this type is not a signature.
pub type Acknowledgement {
  Acknowledgement(
    transaction_id: String,
    manifest: String,
    epoch: Int,
    generation: Int,
    command: Command,
    observation: Observation,
  )
}

pub opaque type Transaction {
  Transaction(
    transaction_id: String,
    candidate: String,
    previous_candidate: String,
    manifest: String,
    execution: ExecutionBinding,
    physical_count: Int,
    runtime_epoch: Int,
    generation: Int,
    prepared: Bool,
    phase: Phase,
  )
}

/// Freshness is a bounded observation, not a lease duration. Real ingress must
/// re-read source, risk, runtime ownership and the reader barrier at each effect.
/// candidate is the intended candidate binding, not the currently active release.
pub type RuntimeObservation {
  RuntimeObservation(
    candidate: String,
    manifest: String,
    transaction_id: String,
    epoch: Int,
    owner: String,
    observed_ms: Int,
    lease_until_ms: Int,
    source_and_risk_current: Bool,
    all_readers_fenced: Bool,
    ingress_admitted: Bool,
  )
}

pub fn new(
  transaction_id: String,
  candidate: String,
  previous_candidate: String,
  manifest: String,
  physical_count: Int,
  runtime_epoch: Int,
  execution: ExecutionBinding,
) -> Result(Transaction, String) {
  case
    candidate_id.is_sha256_digest(transaction_id)
    && candidate_id.is_sha256_digest(candidate)
    && candidate_id.is_sha256_digest(previous_candidate)
    && candidate_id.is_sha256_digest(manifest)
    && { physical_count == 14 || physical_count == 15 }
    && runtime_epoch > 0
    && execution.attempt > 0
    && execution.plan_id != ""
    && execution.task_id != ""
    && execution.worker != ""
    && execution.runtime_owner != ""
    && string.starts_with(execution.workspace, "/")
  {
    True ->
      Ok(Transaction(
        transaction_id,
        candidate,
        previous_candidate,
        manifest,
        execution,
        physical_count,
        runtime_epoch,
        0,
        False,
        Preparing,
      ))
    False -> Error("INVALID_CUTOVER_BINDING")
  }
}

pub fn phase(transaction: Transaction) -> Phase {
  transaction.phase
}

pub fn epoch(transaction: Transaction) -> Int {
  transaction.runtime_epoch
}

pub fn generation(transaction: Transaction) -> Int {
  transaction.generation
}

pub fn physical_count(transaction: Transaction) -> Int {
  transaction.physical_count
}

pub fn family(transaction: Transaction) -> String {
  case transaction.phase {
    RecoveryQuiescing | Restoring(_) | CheckingPrevious | ResumingPrevious ->
      "ecology_cutover_recovery"
    _ -> "ecology_cutover"
  }
}

pub fn command_key(command: Command) -> String {
  case command {
    StageFiles -> "stage"
    FenceReaders -> "fence_readers"
    ReplaceFile(index) -> "replace:" <> int.to_string(index)
    VerifyCandidate -> "verify_candidate"
    RestoreFile(index) -> "restore:" <> int.to_string(index)
    VerifyPrevious -> "verify_previous"
    ResumeReaders -> "resume_readers"
  }
}

pub fn next(transaction: Transaction) -> Result(Command, String) {
  case transaction.phase {
    Preparing -> Ok(StageFiles)
    Quiescing | RecoveryQuiescing -> Ok(FenceReaders)
    Replacing(index) -> Ok(ReplaceFile(index))
    CheckingCandidate -> Ok(VerifyCandidate)
    ResumingCandidate | ResumingPrevious -> Ok(ResumeReaders)
    Restoring(index) -> Ok(RestoreFile(index))
    CheckingPrevious -> Ok(VerifyPrevious)
    Committed | RolledBack -> Error("TRANSACTION_TERMINAL")
    RecoveryHeld -> Error("RECOVERY_REQUIRES_RECONCILIATION")
  }
}

/// Interpret an acknowledgement of exactly the outstanding command. A failed
/// rename may already have happened, so restore the full set in reverse order.
/// Failed restoration or an uncertain reader resume retains the stop line.
pub fn observe(
  transaction: Transaction,
  acknowledgement: Acknowledgement,
) -> Result(Transaction, String) {
  let command = acknowledgement.command
  let observation = acknowledgement.observation
  case
    acknowledgement.transaction_id == transaction.transaction_id
    && acknowledgement.manifest == transaction.manifest
    && acknowledgement.epoch == transaction.runtime_epoch
    && acknowledgement.generation == transaction.generation
  {
    False -> Error("STALE_OR_FOREIGN_ACKNOWLEDGEMENT")
    True -> observe_bound(transaction, command, observation)
  }
}

fn observe_bound(
  transaction: Transaction,
  command: Command,
  observation: Observation,
) -> Result(Transaction, String) {
  case next(transaction) {
    Error(reason) -> Error(reason)
    Ok(expected) if expected != command -> Error("OUT_OF_ORDER_ACKNOWLEDGEMENT")
    Ok(_) -> {
      let checked = case transaction.phase, observation {
        Preparing, Prepared(manifest, count)
          if manifest == transaction.manifest
          && count == transaction.physical_count
        -> Ok(Succeeded)
        CheckingCandidate, Verified(candidate)
          if candidate == transaction.candidate
        -> Ok(Succeeded)
        CheckingPrevious, Verified(candidate)
          if candidate == transaction.previous_candidate
        -> Ok(Succeeded)
        Preparing, Succeeded
        | CheckingCandidate, Succeeded
        | CheckingPrevious, Succeeded
        -> Error("OBSERVATION_EVIDENCE_REQUIRED")
        _, Prepared(_, _) | _, Verified(_) ->
          Error("OBSERVATION_BINDING_MISMATCH")
        _, result -> Ok(result)
      }
      case checked {
        Error(reason) -> Error(reason)
        Ok(observation) -> {
          let next_phase = case transaction.phase, observation {
            Preparing, Succeeded -> Quiescing
            Preparing, Failed -> RecoveryHeld
            Quiescing, Succeeded -> Replacing(0)
            Quiescing, Failed -> RecoveryHeld
            RecoveryQuiescing, Succeeded ->
              Restoring(transaction.physical_count - 1)
            RecoveryQuiescing, Failed -> RecoveryHeld
            Replacing(index), Succeeded
              if index + 1 < transaction.physical_count
            -> Replacing(index + 1)
            Replacing(_), Succeeded -> CheckingCandidate
            CheckingCandidate, Succeeded -> ResumingCandidate
            Replacing(_), Failed | CheckingCandidate, Failed ->
              Restoring(transaction.physical_count - 1)
            Restoring(index), Succeeded if index > 0 -> Restoring(index - 1)
            Restoring(_), Succeeded -> CheckingPrevious
            CheckingPrevious, Succeeded -> ResumingPrevious
            ResumingCandidate, Succeeded -> Committed
            ResumingPrevious, Succeeded -> RolledBack
            Restoring(_), Failed
            | CheckingPrevious, Failed
            | ResumingCandidate, Failed
            | ResumingPrevious, Failed
            -> RecoveryHeld
            Committed, _ | RolledBack, _ | RecoveryHeld, _ -> RecoveryHeld
            _, Prepared(_, _) | _, Verified(_) -> RecoveryHeld
          }
          Ok(
            Transaction(
              ..transaction,
              phase: next_phase,
              generation: transaction.generation + 1,
              prepared: transaction.prepared
                || {
                  transaction.phase == Preparing && observation == Succeeded
                },
            ),
          )
        }
      }
    }
  }
}

/// A durable unfinished journal is replayed under a new verified reader fence.
/// Restoring every entry also covers crash-after-rename-before-journal-write.
/// The native interpreter must validate the complete journal and its binding;
/// it cannot turn a malformed/incomplete backup set into a recovery receipt.
pub fn recover(
  transaction: Transaction,
  new_epoch: Int,
) -> Result(Transaction, String) {
  case transaction.phase {
    Committed | RolledBack -> Error("TRANSACTION_TERMINAL")
    _ if new_epoch <= transaction.runtime_epoch ->
      Error("RECOVERY_REQUIRES_NEW_EPOCH")
    _ if !transaction.prepared -> Error("BACKUP_SET_NOT_VERIFIED")
    _ ->
      Ok(
        Transaction(
          ..transaction,
          runtime_epoch: new_epoch,
          phase: RecoveryQuiescing,
          generation: transaction.generation + 1,
        ),
      )
  }
}

/// Reuse existing effect-time admission, then add transaction-specific guards.
/// No public route currently issues this ReleaseAuthority. Callbacks below are
/// injected observations; tests with fabricated grants remain model tests.
pub fn authorize_next(
  transaction: Transaction,
  context: admission.AdmissionContext,
  call: admission.ValidatedCall,
  read_task: fn() -> Option(admission.TaskFence),
  read_clock_ms: fn() -> Int,
  read_runtime: fn() -> RuntimeObservation,
) -> Result(Command, String) {
  let task = read_task()
  let runtime = read_runtime()
  let now = read_clock_ms()
  let fresh_context =
    admission.AdmissionContext(..context, task_fence: task, now_ms: now)
  case admission.verify_at_effect_time(fresh_context, call) {
    Error(error) -> Error(error.code)
    Ok(checked) -> {
      case task {
        None -> Error("MISSING_TASK_FENCE")
        Some(task) ->
          case task.grant {
            None -> Error("MISSING_RELEASE_AUTHORITY")
            Some(grant) -> {
              case
                grant.scope == ReleaseAuthority
                && call.spec.effect_class == ControlActuation
                && call.spec.family == family(transaction)
                && context.workspace_root == transaction.execution.workspace
                && task.plan_id == transaction.execution.plan_id
                && task.task_id == transaction.execution.task_id
                && task.worker_id == transaction.execution.worker
                && task.attempt == transaction.execution.attempt
                && call.spec.owner_task == transaction.execution.task_id
                && call.principal == checked.principal
                && call.plan_id == checked.plan_id
                && call.task_id == checked.task_id
                && call.attempt == checked.attempt
                && call.grant_id == checked.grant_id
                && dict.get(call.arguments, "transaction_id")
                == Ok(transaction.transaction_id)
                && dict.get(call.arguments, "candidate")
                == Ok(transaction.candidate)
                && dict.get(call.arguments, "manifest")
                == Ok(transaction.manifest)
                && dict.get(call.arguments, "runtime_epoch")
                == Ok(int.to_string(transaction.runtime_epoch))
                && dict.get(call.arguments, "generation")
                == Ok(int.to_string(transaction.generation))
                && case next(transaction) {
                  Ok(command) ->
                    dict.get(call.arguments, "command")
                    == Ok(command_key(command))
                  Error(_) -> False
                }
              {
                False -> Error("RELEASE_CALL_BINDING_MISMATCH")
                True -> authorize_runtime(transaction, runtime, now)
              }
            }
          }
      }
    }
  }
}

fn authorize_runtime(
  transaction: Transaction,
  runtime: RuntimeObservation,
  now: Int,
) -> Result(Command, String) {
  case
    runtime.ingress_admitted
    && runtime.source_and_risk_current
    && runtime.transaction_id == transaction.transaction_id
    && runtime.candidate == transaction.candidate
    && runtime.manifest == transaction.manifest
    && runtime.epoch == transaction.runtime_epoch
    && runtime.owner == transaction.execution.runtime_owner
    && runtime.observed_ms >= 0
    && runtime.observed_ms <= now
    && now - runtime.observed_ms <= 1000
    && runtime.lease_until_ms > now
  {
    False -> Error("RUNTIME_OBSERVATION_NOT_AUTHORITATIVE")
    True ->
      case next(transaction) {
        Error(reason) -> Error(reason)
        Ok(command) ->
          case command {
            StageFiles | FenceReaders -> Ok(command)
            ReplaceFile(_)
            | VerifyCandidate
            | RestoreFile(_)
            | VerifyPrevious
            | ResumeReaders ->
              case runtime.all_readers_fenced {
                True -> Ok(command)
                False -> Error("READERS_NOT_FENCED")
              }
          }
      }
  }
}
