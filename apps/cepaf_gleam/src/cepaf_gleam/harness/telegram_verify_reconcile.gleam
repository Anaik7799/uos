//// Crash reconciliation for one /verify inbox request. After a restart the
//// three durable facts, the inbox reservation, the Sa-plan job row and the
//// evidence directory, are read and classified. The classification decides
//// what a supervisor may do next; it never executes anything itself.
////
////   NoReservation  nothing was ever reserved: a new request may reserve.
////   JobMissing     reserved, no job row: ensure the job, never re-reserve.
////   NotRun         job exists, no evidence dir: a worker may claim and run.
////   InProgress     job row says executing: do not start a second run.
////   Partial        gate outputs exist but no receipt: the run died mid-way.
////                  The executor refuses an existing evidence directory, so a
////                  rerun needs a new attempt and a Sa-plan job failure record.
////   Complete       receipt.json exists: never run again; load the receipt.
////   Inconsistent   facts that cannot coexist (job without reservation,
////                  receipt without job): stop and report.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_verify_contract as v
import cepaf_gleam/harness/telegram_verify_executor as executor
import cepaf_gleam/harness/telegram_verify_job as job
import cepaf_gleam/harness/telegram_verify_reservation as reservation
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

pub type Evidence {
  Evidence(dir_exists: Bool, gate_outputs: Int, receipt: Bool)
}

pub type Verdict {
  NoReservation
  JobMissing
  NotRun(job_state: String)
  InProgress
  Partial(gate_outputs: Int)
  Complete
  Inconsistent(String)
}

pub type Report {
  Report(
    binding: Option(v.Binding),
    job: Option(job.Job),
    evidence: Evidence,
    verdict: Verdict,
  )
}

/// Pure classification of the three durable facts.
pub fn classify(
  binding: Option(v.Binding),
  j: Option(job.Job),
  e: Evidence,
) -> Verdict {
  case binding, j {
    None, None ->
      case e.dir_exists {
        True -> Inconsistent("evidence_without_reservation")
        False -> NoReservation
      }
    None, Some(_) -> Inconsistent("job_without_reservation")
    Some(b), Some(row) if row.id != b.job_id -> Inconsistent("job_id_mismatch")
    Some(_), None ->
      case e.dir_exists {
        True -> Inconsistent("evidence_without_job")
        False -> JobMissing
      }
    Some(_), Some(row) ->
      case e.receipt, e.dir_exists, row.state {
        True, _, _ -> Complete
        False, True, _ -> Partial(e.gate_outputs)
        False, False, "executing" -> InProgress
        False, False, state -> NotRun(state)
      }
  }
}

fn evidence(root: String, base: String, b: v.Binding) -> Evidence {
  let dir = executor.evidence_dir(base, b)
  case files.checked_path(root, dir) {
    Error(_) -> Evidence(False, 0, False)
    Ok(path) ->
      case simplifile.read_directory(path) {
        Error(_) -> Evidence(False, 0, False)
        Ok(names) ->
          Evidence(
            True,
            list.count(names, fn(n) { string.ends_with(n, ".out") }),
            list.contains(names, "receipt.json"),
          )
      }
  }
}

/// Reads reservation, job and evidence for `request_id` and classifies them.
/// A missing reservation is a fact, not an error; store failures are errors.
pub fn observe(
  root: String,
  reservation_dir: String,
  evidence_base: String,
  run: job.Runner,
  request_id: String,
) -> Result(Report, String) {
  case reservation.load(root, reservation_dir, request_id) {
    Error("reservation_unavailable:file_unavailable") ->
      Ok(Report(
        None,
        None,
        Evidence(False, 0, False),
        classify(None, None, Evidence(False, 0, False)),
      ))
    Error(e) -> Error(e)
    Ok(b) -> {
      use j <- result.try(case job.lookup(run, b.job_id) {
        Ok(row) -> Ok(Some(row))
        Error("job_absent") -> Ok(None)
        Error(e) -> Error(e)
      })
      let e = evidence(root, evidence_base, b)
      Ok(Report(Some(b), j, e, classify(Some(b), j, e)))
    }
  }
}
