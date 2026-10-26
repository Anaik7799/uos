//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/harness/telegram_verify_run</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-JIDOKA-001, SC-SA-PLAN-001, SC-TELEGRAM-JOURNEY-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Orchestrates one approved /verify request over the durable chain:
//// profile -> reservation -> Sa-plan job -> crash reconciliation -> Sa-plan
//// claim -> artifact recheck -> guardian execution -> receipt -> Sa-plan
//// completion. Every effect is behind an injected runner or executor so the
//// decision logic is testable without a guardian; the real executor is
//// `real_executor`. The guardian runs only inside a Sa-plan job claim held by
//// the service worker (SC-SA-PLAN-001); the job is completed or failed with
//// the receipt digest afterwards. Nothing here grants admission: a receipt
//// says what the pinned gates observed for the pinned artifacts.

import cepaf_gleam/harness/development
import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_verify_action as verify_action
import cepaf_gleam/harness/telegram_verify_contract as v
import cepaf_gleam/harness/telegram_verify_executor as executor
import cepaf_gleam/harness/telegram_verify_job as job
import cepaf_gleam/harness/telegram_verify_loader as loader
import cepaf_gleam/harness/telegram_verify_reconcile as reconcile
import cepaf_gleam/harness/telegram_verify_reservation as reservation
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

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

/// Lease the service holds on the verify job while the guardian runs.
pub const job_lease_ns = 600_000_000_000

pub type Outcome {
  /// A receipt already existed for this request; it is returned, not rerun.
  AlreadyComplete(receipt: String)
  /// The guardian ran now under a Sa-plan job claim.
  Executed(executor.Outcome)
  /// Durable state forbids a run; the reason names the reconcile verdict.
  Refused(reason: String)
}

/// Injected execution: given the rechecked loaded profile and the binding,
/// run every gate and return the executor outcome.
pub type Executor =
  fn(loader.Loaded, v.Binding) -> Result(executor.Outcome, String)

/// A sa-plan runner bound to one database: every call sets `UOS_SA_PLAN_DB`
/// for the bounded child, so a service on isolated authority paths can never
/// reach the canonical store by inheritance. The tool is the repository's
/// `tools/sa-plan` wrapper or the pinned `sa_plan_main.exe`.
pub fn sa_plan_runner(tool: String, database: String) -> job.Runner {
  fn(args) {
    development.bounded_env(
      tool,
      args,
      [#("UOS_SA_PLAN_DB", database)],
      15_000,
    )
    |> result.map(string.trim)
  }
}

/// Load the pinned profile and derive the binding for the inbox request.
/// No side effect: nothing is reserved or enqueued.
pub fn derive_binding(
  source: Source,
  request_id: String,
  attempt: Int,
) -> Result(#(loader.Loaded, v.Binding), String) {
  use loaded <- result.try(loader.load(
    source.root,
    source.profile_path,
    source.pin,
    source.locators,
  ))
  use b <- result.try(v.binding(loader.profile(loaded), request_id, attempt))
  Ok(#(loaded, b))
}

/// Reserve the derived binding exclusively and ensure its Sa-plan job.
/// Idempotent for an identical request; any other binding for the same
/// request is a conflict.
pub fn reserve_loaded(
  source: Source,
  run: job.Runner,
  b: v.Binding,
) -> Result(job.Ensured, String) {
  use reserved <- result.try(reservation.reserve(
    source.root,
    source.reservation_dir,
    b,
  ))
  let b = case reserved {
    reservation.Created(x) | reservation.Existing(x) -> x
  }
  job.ensure(run, b, source.worker)
}

/// `derive_binding` then `reserve_loaded`, for callers that want both.
pub fn reserve(
  source: Source,
  run: job.Runner,
  request_id: String,
  attempt: Int,
) -> Result(#(loader.Loaded, v.Binding, job.Ensured), String) {
  use #(loaded, b) <- result.try(derive_binding(source, request_id, attempt))
  use ensured <- result.try(reserve_loaded(source, run, b))
  Ok(#(loaded, b, ensured))
}

fn receipt_path(source: Source, b: v.Binding) -> String {
  executor.evidence_dir(source.evidence_base, b) <> "/receipt.json"
}

/// Read-only: the stored receipt when the request is already Complete. This
/// needs no approval, so a replay after the receipts expired still answers.
pub fn complete_receipt(
  source: Source,
  run: job.Runner,
  b: v.Binding,
) -> Result(Option(String), String) {
  use report <- result.try(reconcile.observe(
    source.root,
    source.reservation_dir,
    source.evidence_base,
    run,
    b.request_id,
  ))
  case report.verdict, report.binding {
    reconcile.Complete, Some(stored) if stored == b ->
      files.read(source.root, receipt_path(source, b)) |> result.map(Some)
    reconcile.Complete, _ -> Error("reservation_binding_mismatch")
    _, _ -> Ok(None)
  }
}

/// The executor that checks the approval deadline, re-hashes every artifact
/// and then spawns the pinned guardian. A passed deadline, a changed artifact
/// or a changed guardian refuses before any child exists.
pub fn real_executor(
  source: Source,
  deadline_ms: Int,
  now_ms: fn() -> Int,
) -> Executor {
  fn(loaded, b) {
    use _ <- result.try(case now_ms() < deadline_ms {
      True -> Ok(Nil)
      False -> Error("approval_deadline_passed")
    })
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

fn completion_result(out: executor.Outcome) -> #(Bool, String) {
  let #(ok, assessment) = case out.assessment {
    v.VerifiedEvidence -> #(True, "verified_evidence")
    v.Failed(reason) -> #(False, "failed:" <> reason)
    v.Indeterminate(reason) -> #(False, "indeterminate:" <> reason)
  }
  #(
    ok,
    json.object([
      #("receipt_sha256", json.string(files.digest(out.receipt))),
      #("assessment", json.string(assessment)),
      #("gates", json.int(list.length(out.runs))),
    ])
      |> json.to_string,
  )
}

/// Decide and act for a prepared, approved request. The reconcile verdict is
/// read first: a completed request returns its stored receipt and never runs
/// twice; partial, in-progress, inconsistent and non-claimable state refuse.
/// Only an available job executes, and only after the service worker claims
/// it through Sa-plan and the durable reservation equals the approved one;
/// the job is then completed or failed with the receipt digest.
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
    reconcile.NotRun(state) ->
      case report.binding == Some(b), state {
        False, _ -> Ok(Refused("reservation_binding_mismatch"))
        True, "available" ->
          case loader.profile(loaded) |> v.binding(b.request_id, b.attempt) {
            Ok(derived) if derived == b -> {
              use claimed <- result.try(job.claim(
                run,
                b,
                source.worker,
                job_lease_ns,
              ))
              use out <- result.try(exec(loaded, b))
              let #(ok, result_json) = completion_result(out)
              use _ <- result.try(job.complete(
                run,
                b,
                source.worker,
                claimed.attempt,
                ok,
                result_json,
              ))
              Ok(Executed(out))
            }
            _ -> Ok(Refused("profile_binding_mismatch"))
          }
        True, other -> Ok(Refused("job_not_claimable:" <> other))
      }
    reconcile.NoReservation -> Ok(Refused("no_reservation"))
    reconcile.JobMissing -> Ok(Refused("job_missing"))
    reconcile.InProgress -> Ok(Refused("in_progress"))
    reconcile.Partial(n) ->
      Ok(Refused("partial_evidence:" <> int.to_string(n)))
    reconcile.Inconsistent(reason) -> Ok(Refused("inconsistent:" <> reason))
  }
}
