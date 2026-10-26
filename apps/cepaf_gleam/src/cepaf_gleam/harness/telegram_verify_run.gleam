//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/harness/telegram_verify_run</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-JIDOKA-001, SC-TELEGRAM-JOURNEY-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Orchestrates one approved /verify request over the durable chain:
//// reservation -> Sa-plan job -> crash reconciliation -> artifact recheck ->
//// guardian execution -> receipt. Every effect is behind an injected runner or
//// executor so the decision logic is testable without a guardian; the real
//// executor is `real_executor`. Nothing here grants admission: a receipt says
//// what the pinned gates observed for the pinned artifacts, nothing more.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_verify_action as verify_action
import cepaf_gleam/harness/telegram_verify_contract as v
import cepaf_gleam/harness/telegram_verify_executor as executor
import cepaf_gleam/harness/telegram_verify_job as job
import cepaf_gleam/harness/telegram_verify_loader as loader
import cepaf_gleam/harness/telegram_verify_reconcile as reconcile
import cepaf_gleam/harness/telegram_verify_reservation as reservation
import gleam/int
import gleam/option.{Some}
import gleam/result

/// Operator-held verify configuration. `root` bounds every path; the
/// reservation directory and evidence base are relative to it.
pub type Source {
  Source(
    root: String,
    profile_path: String,
    pin: String,
    locators: List(loader.Locator),
    guardian: executor.Guardian,
    reservation_dir: String,
    evidence_base: String,
    worker: String,
  )
}

pub type Outcome {
  /// A receipt already existed for this request; it is returned, not rerun.
  AlreadyComplete(receipt: String)
  /// The guardian ran now.
  Executed(executor.Outcome)
  /// Durable state forbids a run; the reason names the reconcile verdict.
  Refused(reason: String)
}

/// Injected execution: given the rechecked loaded profile and the binding,
/// run every gate and return the executor outcome.
pub type Executor =
  fn(loader.Loaded, v.Binding) -> Result(executor.Outcome, String)

/// Load the pinned profile, derive the binding for the inbox request, reserve
/// it exclusively and ensure its Sa-plan job. Idempotent for an identical
/// request; any other binding for the same request is a conflict.
pub fn reserve(
  source: Source,
  run: job.Runner,
  request_id: String,
  attempt: Int,
) -> Result(#(loader.Loaded, v.Binding, job.Ensured), String) {
  use loaded <- result.try(loader.load(
    source.root,
    source.profile_path,
    source.pin,
    source.locators,
  ))
  use b <- result.try(v.binding(loader.profile(loaded), request_id, attempt))
  use reserved <- result.try(reservation.reserve(
    source.root,
    source.reservation_dir,
    b,
  ))
  let b = case reserved {
    reservation.Created(x) | reservation.Existing(x) -> x
  }
  use ensured <- result.try(job.ensure(run, b, source.worker))
  Ok(#(loaded, b, ensured))
}

/// The executor that re-hashes every artifact immediately before spawning the
/// pinned guardian. A changed artifact or guardian refuses before any child.
pub fn real_executor(source: Source) -> Executor {
  fn(loaded, b) {
    use _ <- result.try(loader.recheck(loaded))
    executor.execute(
      loaded,
      source.root,
      b,
      source.guardian,
      source.root,
      source.evidence_base,
    )
  }
}

fn receipt_path(source: Source, b: v.Binding) -> String {
  executor.evidence_dir(source.evidence_base, b) <> "/receipt.json"
}

/// Decide and act for a prepared, approved request. The reconcile verdict is
/// read first: a completed request returns its stored receipt and never runs
/// twice; partial, in-progress and inconsistent state refuse; only NotRun
/// executes, and only when the durable reservation equals the approved one.
pub fn execute(
  source: Source,
  run: job.Runner,
  prepared: verify_action.Prepared,
  loaded: loader.Loaded,
  exec: Executor,
) -> Result(Outcome, String) {
  let b = verify_action.verify_binding(prepared)
  use report <- result.try(reconcile.observe(
    source.root,
    source.reservation_dir,
    source.evidence_base,
    run,
    b.request_id,
  ))
  case report.verdict {
    reconcile.Complete ->
      files.read(source.root, receipt_path(source, b))
      |> result.map(AlreadyComplete)
    reconcile.NotRun(_) ->
      case report.binding == Some(b) {
        False -> Ok(Refused("reservation_binding_mismatch"))
        True ->
          case loader.profile(loaded) |> v.binding(b.request_id, b.attempt) {
            Ok(derived) if derived == b -> exec(loaded, b) |> result.map(Executed)
            _ -> Ok(Refused("profile_binding_mismatch"))
          }
      }
    reconcile.NoReservation -> Ok(Refused("no_reservation"))
    reconcile.JobMissing -> Ok(Refused("job_missing"))
    reconcile.InProgress -> Ok(Refused("in_progress"))
    reconcile.Partial(n) ->
      Ok(Refused("partial_evidence:" <> int.to_string(n)))
    reconcile.Inconsistent(reason) -> Ok(Refused("inconsistent:" <> reason))
  }
}
