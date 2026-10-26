import cepaf_gleam/harness/telegram_verify_contract as v
import cepaf_gleam/harness/telegram_verify_executor as executor
import cepaf_gleam/harness/telegram_verify_job as job
import cepaf_gleam/harness/telegram_verify_reconcile as reconcile
import cepaf_gleam/harness/telegram_verify_reservation as reservation
import gleam/int
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import simplifile

fn binding(request: String) -> v.Binding {
  let assert Ok(p) =
    v.profile(
      "telegram-core",
      string.repeat("a", 40),
      string.repeat("b", 64),
      [
        v.Gate("build", string.repeat("c", 64), string.repeat("e", 64), 1000),
      ],
      3000,
    )
  let assert Ok(b) = v.binding(p, request, 1)
  b
}

fn row(b: v.Binding, state: String) -> job.Job {
  job.Job(b.job_id, "w", state, "0")
}

const none = reconcile.Evidence(False, 0, False)

pub fn classify_covers_every_durable_state_test() {
  let b = binding("bot999/inbox8201")
  reconcile.classify(None, None, none) |> should.equal(reconcile.NoReservation)
  reconcile.classify(Some(b), None, none) |> should.equal(reconcile.JobMissing)
  reconcile.classify(Some(b), Some(row(b, "available")), none)
  |> should.equal(reconcile.NotRun("available"))
  reconcile.classify(Some(b), Some(row(b, "executing")), none)
  |> should.equal(reconcile.InProgress)
  reconcile.classify(
    Some(b),
    Some(row(b, "executing")),
    reconcile.Evidence(True, 1, False),
  )
  |> should.equal(reconcile.Partial(1))
  reconcile.classify(
    Some(b),
    Some(row(b, "completed")),
    reconcile.Evidence(True, 2, True),
  )
  |> should.equal(reconcile.Complete)
}

pub fn classify_names_inconsistent_states_test() {
  let b = binding("bot999/inbox8202")
  reconcile.classify(None, Some(row(b, "available")), none)
  |> should.equal(reconcile.Inconsistent("job_without_reservation"))
  reconcile.classify(Some(b), None, reconcile.Evidence(True, 0, False))
  |> should.equal(reconcile.Inconsistent("evidence_without_job"))
  reconcile.classify(None, None, reconcile.Evidence(True, 0, True))
  |> should.equal(reconcile.Inconsistent("evidence_without_reservation"))
  let other =
    job.Job("telegram/verify/" <> string.repeat("0", 64), "w", "available", "0")
  reconcile.classify(Some(b), Some(other), none)
  |> should.equal(reconcile.Inconsistent("job_id_mismatch"))
}

pub fn a_receipt_always_wins_over_a_running_row_test() {
  // Restart after completion but before the job row was completed: never rerun.
  let b = binding("bot999/inbox8203")
  reconcile.classify(
    Some(b),
    Some(row(b, "executing")),
    reconcile.Evidence(True, 1, True),
  )
  |> should.equal(reconcile.Complete)
}

fn fresh_root() -> String {
  let root =
    "/tmp/uos_tg_verify_reconcile_test_"
    <> int.to_string(int.random(1_000_000_000))
  let assert Ok(_) = simplifile.create_directory_all(root <> "/reservations")
  let assert Ok(_) = simplifile.create_directory_all(root <> "/evidence")
  root
}

/// In-memory Sa-plan stand-in: one listed job row, or none.
fn runner(rows: List(job.Job)) -> job.Runner {
  fn(args) {
    case args {
      ["--format", "json", "job", "list", _] ->
        Ok(
          rows
          |> list_map_join(fn(r) {
            "{\"id\":\""
            <> r.id
            <> "\",\"name\":\""
            <> r.id
            <> "\",\"queue\":\"telegram-verify\",\"worker\":\""
            <> r.worker
            <> "\",\"state\":\""
            <> r.state
            <> "\",\"attempt\":\""
            <> r.attempt
            <> "\"}"
          }),
        )
      _ -> Error("unexpected")
    }
  }
}

fn list_map_join(rows: List(job.Job), f: fn(job.Job) -> String) -> String {
  case rows {
    [] -> ""
    [r] -> f(r)
    [r, ..rest] -> f(r) <> "\n" <> list_map_join(rest, f)
  }
}

pub fn observe_walks_reservation_job_and_evidence_test() {
  let root = fresh_root()
  let b = binding("bot999/inbox8204")
  let empty = runner([])
  let assert Ok(r0) =
    reconcile.observe(root, "reservations", "evidence", empty, b.request_id)
  r0.verdict |> should.equal(reconcile.NoReservation)
  let assert Ok(_) = reservation.reserve(root, "reservations", b)
  let assert Ok(r1) =
    reconcile.observe(root, "reservations", "evidence", empty, b.request_id)
  r1.verdict |> should.equal(reconcile.JobMissing)
  let with_job = runner([row(b, "available")])
  let assert Ok(r2) =
    reconcile.observe(root, "reservations", "evidence", with_job, b.request_id)
  r2.verdict |> should.equal(reconcile.NotRun("available"))
  let dir = root <> "/" <> executor.evidence_dir("evidence", b)
  let assert Ok(_) = simplifile.create_directory_all(dir)
  let assert Ok(_) = simplifile.write(dir <> "/build.out", "partial")
  let assert Ok(r3) =
    reconcile.observe(root, "reservations", "evidence", with_job, b.request_id)
  r3.verdict |> should.equal(reconcile.Partial(1))
  let assert Ok(_) = simplifile.write(dir <> "/receipt.json", "{}")
  let assert Ok(r4) =
    reconcile.observe(root, "reservations", "evidence", with_job, b.request_id)
  r4.verdict |> should.equal(reconcile.Complete)
}

pub fn observe_reports_store_failure_not_a_verdict_test() {
  let root = fresh_root()
  let b = binding("bot999/inbox8205")
  let assert Ok(_) = reservation.reserve(root, "reservations", b)
  let broken = fn(_args) { Error("sa_plan_unreachable") }
  reconcile.observe(root, "reservations", "evidence", broken, b.request_id)
  |> should.equal(Error("job_list_failed:sa_plan_unreachable"))
}
