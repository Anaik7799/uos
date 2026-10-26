//// Laws for the /verify run orchestration: reserve is idempotent and binds
//// the job, a completed request returns its stored receipt and never reruns,
//// partial, in-progress, non-claimable and mismatched state refuse, the
//// guardian runs only inside a Sa-plan claim that is completed afterwards,
//// and the real executor rechecks artifacts and honours the approval deadline.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_action_intent as action
import cepaf_gleam/harness/telegram_verify_action as verify_action
import cepaf_gleam/harness/telegram_verify_contract as v
import cepaf_gleam/harness/telegram_verify_executor as executor
import cepaf_gleam/harness/telegram_verify_job as job
import cepaf_gleam/harness/telegram_verify_loader as loader
import cepaf_gleam/harness/telegram_verify_run as run
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import simplifile
import telegram_verify_action_test as fx

const guardian_sha256 = "d1dc2995fe52915e9c2a7b39309f23a8197cfb273d025f3453ebd904b24f50f4"

const request_id = "bot7/inbox19"

const far_future_ms = 9_000_000_000_000

fn guardian() -> executor.Guardian {
  let assert Ok(cwd) = simplifile.current_directory()
  executor.Guardian(
    cwd <> "/../../tools/validation/verify_guardian.exe",
    guardian_sha256,
  )
}

fn fresh_root(tag: String) -> String {
  let root =
    "/tmp/uos_tg_verify_run_test_"
    <> tag
    <> "_"
    <> int.to_string(int.random(1_000_000_000))
  let assert Ok(_) = simplifile.create_directory_all(root <> "/gates")
  let assert Ok(_) = simplifile.create_directory_all(root <> "/evidence")
  let assert Ok(_) = simplifile.create_directory_all(root <> "/reservations")
  root
}

fn script(root: String, name: String, body: String) -> String {
  let content = "#!/bin/sh\n" <> body <> "\n"
  let path = root <> "/gates/" <> name
  let assert Ok(_) = simplifile.write(path, content)
  let assert Ok(_) = simplifile.set_permissions_octal(path, 0o755)
  files.digest(content)
}

/// One passing gate under a pinned profile; returns the configured source.
fn source(root: String) -> run.Source {
  let build = script(root, "build.sh", "echo built")
  let assert Ok(_) = simplifile.write(root <> "/gates/build.in", "b")
  let assert Ok(p) =
    v.profile(
      "telegram-core",
      string.repeat("a", 40),
      string.repeat("b", 64),
      [v.Gate("build", build, files.digest("b"), 2000)],
      2000,
    )
  let assert Ok(_) =
    simplifile.write(root <> "/profile.json", v.canonical_json(p))
  run.Source(
    root: root,
    profile_path: "profile.json",
    pin: v.profile_digest(p),
    locators: [loader.Locator("build", "gates/build.sh", "gates/build.in")],
    guardian: guardian(),
    reservation_dir: "reservations",
    evidence_base: "evidence",
    worker: fx.worker,
  )
}

fn job_row(id: String, state: String, worker: String) -> String {
  json.object([
    #("id", json.string(id)),
    #("queue", json.string(job.queue)),
    #("worker", json.string(worker)),
    #("state", json.string(state)),
    #("attempt", json.string("1")),
  ])
  |> json.to_string
}

/// A stateless fake sa-plan: `job list` answers with the given rows (job id,
/// state); `job enqueue` refuses a duplicate id; `job claim` answers with the
/// job named by `claimed` in state executing; `job complete` succeeds.
/// Every argv is reported on `calls`.
fn runner_with(
  rows: List(#(String, String)),
  claimed: String,
  calls: process.Subject(List(String)),
) -> job.Runner {
  fn(args) {
    process.send(calls, args)
    case args {
      ["--format", "json", "job", "list", _] ->
        rows
        |> list.map(fn(row) { job_row(row.0, row.1, fx.worker) })
        |> string.join("\n")
        |> Ok
      ["--format", "json", "job", "claim", _, worker, _] ->
        Ok(job_row(claimed, "executing", worker))
      ["job", "enqueue", id, ..] ->
        case list.any(rows, fn(row) { row.0 == id }) {
          True -> Error("UNIQUE constraint failed: sa_plan_job.id")
          False -> Ok("enqueued")
        }
      ["job", "complete", ..] -> Ok("completed")
      _ -> Error("unexpected_argv")
    }
  }
}

fn runner(
  rows: List(#(String, String)),
  calls: process.Subject(List(String)),
) -> job.Runner {
  let claimed = case rows {
    [first, ..] -> first.0
    [] -> "none"
  }
  runner_with(rows, claimed, calls)
}

fn quiet() -> process.Subject(List(String)) {
  process.new_subject()
}

fn reserved(src: run.Source) -> #(loader.Loaded, v.Binding) {
  // Derive the binding first so the stateless fake can answer the row.
  let assert Ok(#(loaded, b)) = run.derive_binding(src, request_id, 1)
  let assert Ok(#(loaded2, b2, ensured)) =
    run.reserve(src, runner([#(b.job_id, "available")], quiet()), request_id, 1)
  b2 |> should.equal(b)
  loader.profile(loaded2) |> should.equal(loader.profile(loaded))
  case ensured {
    job.Enqueued(j) | job.AlreadyEnqueued(j) -> j.id |> should.equal(b.job_id)
  }
  #(loaded, b)
}

/// A Prepared whose reservation binding is the live one for this profile.
fn prepared_for(b: v.Binding) -> verify_action.Prepared {
  let assert Ok(intent) =
    action.new_kind(
      action.VerifyProfile,
      fx.binding(),
      verify_action.target_for("uos/example", b, fx.worker, fx.lease_until_ns),
      fx.window(),
      "Operator requested verification of telegram-core",
      string.repeat("b", 64),
    )
  let assert Ok(p) =
    verify_action.prepare(
      intent,
      fx.evidence(intent, "verify_profile"),
      fx.roster(),
      fx.binding(),
      b,
      fx.observed(),
    )
  p
}

fn fake_outcome() -> executor.Outcome {
  executor.Outcome(v.VerifiedEvidence, "fake-receipt", [])
}

/// An executor that reports each call and returns a fixed outcome.
fn counting_executor(calls: process.Subject(v.Binding)) -> run.Executor {
  fn(_loaded, b) {
    process.send(calls, b)
    Ok(fake_outcome())
  }
}

fn evidence_dir(src: run.Source, b: v.Binding) -> String {
  src.root <> "/" <> executor.evidence_dir(src.evidence_base, b)
}

fn far_executor(src: run.Source) -> run.Executor {
  run.real_executor(src, far_future_ms, fn() { 1 })
}

fn drain(calls: process.Subject(List(String))) -> List(List(String)) {
  case process.receive(calls, 0) {
    Ok(args) -> [args, ..drain(calls)]
    Error(_) -> []
  }
}

pub fn reserve_is_idempotent_and_conflicts_on_another_binding_test() {
  let src = source(fresh_root("reserve"))
  let #(_, b) = reserved(src)
  // Same request again: Existing reservation, AlreadyEnqueued job.
  let assert Ok(#(_, again, ensured)) =
    run.reserve(src, runner([#(b.job_id, "available")], quiet()), request_id, 1)
  again |> should.equal(b)
  case ensured {
    job.AlreadyEnqueued(_) -> Nil
    job.Enqueued(_) -> should.fail()
  }
  // A different attempt for the same inbox request is a conflict: recovery
  // from partial evidence needs a new inbox request, not an attempt bump.
  run.reserve(src, runner([#(b.job_id, "available")], quiet()), request_id, 2)
  |> should.equal(Error("reservation_conflict"))
}

pub fn derive_has_no_side_effect_test() {
  let src = source(fresh_root("derive"))
  let assert Ok(#(_, b)) = run.derive_binding(src, request_id, 1)
  simplifile.read_directory(src.root <> "/reservations")
  |> should.equal(Ok([]))
  // Nothing reserved means a complete_receipt lookup reports no receipt
  // without touching the executor or enqueuing anything.
  let calls = quiet()
  run.complete_receipt(src, runner([], calls), b) |> should.equal(Ok(None))
  list.any(drain(calls), fn(args) {
    case args {
      ["job", "enqueue", ..] | ["--format", "json", "job", "claim", ..] -> True
      _ -> False
    }
  })
  |> should.be_false
}

pub fn not_run_claims_executes_once_and_completes_in_order_test() {
  let src = source(fresh_root("notrun"))
  let #(loaded, b) = reserved(src)
  let exec_calls = process.new_subject()
  let sa_calls = quiet()
  let assert Ok(run.Executed(out)) =
    run.execute(
      src,
      runner([#(b.job_id, "available")], sa_calls),
      prepared_for(b),
      loaded,
      counting_executor(exec_calls),
    )
  out.assessment |> should.equal(v.VerifiedEvidence)
  process.receive(exec_calls, 100) |> should.equal(Ok(b))
  process.receive(exec_calls, 0) |> should.be_error
  // Sa-plan saw: list (reconcile), claim, complete, in that order.
  let verbs =
    drain(sa_calls)
    |> list.filter_map(fn(args) {
      case args {
        ["--format", "json", "job", "list", ..] -> Ok("list")
        ["--format", "json", "job", "claim", _, worker, lease] ->
          Ok("claim:" <> worker <> ":" <> lease)
        ["job", "complete", id, worker, attempt, status, _] ->
          Ok(
            "complete:"
            <> id
            <> ":"
            <> worker
            <> ":"
            <> attempt
            <> ":"
            <> status,
          )
        _ -> Error(Nil)
      }
    })
  verbs
  |> should.equal([
    "list",
    "claim:" <> fx.worker <> ":" <> int.to_string(run.job_lease_ns),
    "complete:" <> b.job_id <> ":" <> fx.worker <> ":1:OK",
  ])
}

pub fn a_failed_assessment_fails_the_job_test() {
  let src = source(fresh_root("failed"))
  let #(loaded, b) = reserved(src)
  let sa_calls = quiet()
  let failing = fn(_loaded, _b) {
    Ok(executor.Outcome(v.Failed("gate_unit"), "fake-receipt", []))
  }
  let assert Ok(run.Executed(_)) =
    run.execute(
      src,
      runner([#(b.job_id, "available")], sa_calls),
      prepared_for(b),
      loaded,
      failing,
    )
  list.any(drain(sa_calls), fn(args) {
    case args {
      ["job", "complete", _, _, _, "ERROR", _] -> True
      _ -> False
    }
  })
  |> should.be_true
}

pub fn a_claim_that_returns_another_job_is_an_error_not_a_run_test() {
  let src = source(fresh_root("claimmismatch"))
  let #(loaded, b) = reserved(src)
  let exec_calls = process.new_subject()
  run.execute(
    src,
    runner_with([#(b.job_id, "available")], "telegram/verify/other", quiet()),
    prepared_for(b),
    loaded,
    counting_executor(exec_calls),
  )
  |> should.equal(Error("job_claim_mismatch:telegram/verify/other"))
  process.receive(exec_calls, 0) |> should.be_error
}

pub fn complete_returns_the_stored_receipt_and_never_reruns_test() {
  let src = source(fresh_root("complete"))
  let #(loaded, b) = reserved(src)
  let dir = evidence_dir(src, b)
  let assert Ok(_) = simplifile.create_directory_all(dir)
  let assert Ok(_) = simplifile.write(dir <> "/receipt.json", "{\"stored\":1}")
  let calls = process.new_subject()
  run.execute(
    src,
    runner([#(b.job_id, "available")], quiet()),
    prepared_for(b),
    loaded,
    counting_executor(calls),
  )
  |> should.equal(Ok(run.AlreadyComplete("{\"stored\":1}")))
  process.receive(calls, 0) |> should.be_error
  // The read-only lookup sees the same receipt without any approval.
  run.complete_receipt(src, runner([#(b.job_id, "available")], quiet()), b)
  |> should.equal(Ok(Some("{\"stored\":1}")))
}

pub fn partial_in_progress_missing_and_non_claimable_jobs_refuse_test() {
  let src = source(fresh_root("refuse"))
  let #(loaded, b) = reserved(src)
  let calls = process.new_subject()
  // Job row says executing: another run owns it.
  run.execute(
    src,
    runner([#(b.job_id, "executing")], quiet()),
    prepared_for(b),
    loaded,
    counting_executor(calls),
  )
  |> should.equal(Ok(run.Refused("in_progress")))
  // A job already completed or failed without evidence is not claimable.
  run.execute(
    src,
    runner([#(b.job_id, "completed")], quiet()),
    prepared_for(b),
    loaded,
    counting_executor(calls),
  )
  |> should.equal(Ok(run.Refused("job_not_claimable:completed")))
  run.execute(
    src,
    runner([#(b.job_id, "failed")], quiet()),
    prepared_for(b),
    loaded,
    counting_executor(calls),
  )
  |> should.equal(Ok(run.Refused("job_not_claimable:failed")))
  // No job row at all although reserved.
  run.execute(
    src,
    runner([], quiet()),
    prepared_for(b),
    loaded,
    counting_executor(calls),
  )
  |> should.equal(Ok(run.Refused("job_missing")))
  // Gate output without a receipt: the previous run died mid-way.
  let dir = evidence_dir(src, b)
  let assert Ok(_) = simplifile.create_directory_all(dir)
  let assert Ok(_) = simplifile.write(dir <> "/build.out", "partial")
  run.execute(
    src,
    runner([#(b.job_id, "available")], quiet()),
    prepared_for(b),
    loaded,
    counting_executor(calls),
  )
  |> should.equal(Ok(run.Refused("partial_evidence:1")))
  process.receive(calls, 0) |> should.be_error
}

pub fn approved_binding_must_equal_the_durable_reservation_test() {
  let src = source(fresh_root("mismatch"))
  let #(loaded, b) = reserved(src)
  // An approval for attempt 2 of the same request: the stored reservation is
  // attempt 1, so the run refuses before touching the executor.
  let other = v.Binding(..b, attempt: 2)
  let calls = process.new_subject()
  run.execute(
    src,
    runner([#(b.job_id, "available")], quiet()),
    prepared_for(other),
    loaded,
    counting_executor(calls),
  )
  |> should.equal(Ok(run.Refused("reservation_binding_mismatch")))
  process.receive(calls, 0) |> should.be_error
  run.complete_receipt(src, runner([#(b.job_id, "available")], quiet()), other)
  |> should.equal(Ok(None))
}

pub fn real_executor_rechecks_and_runs_the_pinned_guardian_test() {
  let src = source(fresh_root("real"))
  let #(loaded, b) = reserved(src)
  let assert Ok(run.Executed(out)) =
    run.execute(
      src,
      runner([#(b.job_id, "available")], quiet()),
      prepared_for(b),
      loaded,
      far_executor(src),
    )
  out.assessment |> should.equal(v.VerifiedEvidence)
  list.map(out.runs, fn(r) { r.status }) |> should.equal(["PASS"])
  // The receipt is a complete file (written via temp and rename), no .tmp left.
  let assert Ok(names) = simplifile.read_directory(evidence_dir(src, b))
  list.contains(names, "receipt.json") |> should.be_true
  list.any(names, fn(n) { string.ends_with(n, ".tmp") }) |> should.be_false
  // The receipt now exists, so a second execute returns it unchanged.
  let assert Ok(run.AlreadyComplete(receipt)) =
    run.execute(
      src,
      runner([#(b.job_id, "available")], quiet()),
      prepared_for(b),
      loaded,
      far_executor(src),
    )
  receipt |> should.equal(out.receipt)
}

pub fn real_executor_refuses_a_changed_artifact_before_spawning_test() {
  let src = source(fresh_root("swap"))
  let #(loaded, b) = reserved(src)
  let assert Ok(_) =
    simplifile.write(src.root <> "/gates/build.sh", "#!/bin/sh\necho swapped\n")
  let assert Error(reason) =
    run.execute(
      src,
      runner([#(b.job_id, "available")], quiet()),
      prepared_for(b),
      loaded,
      far_executor(src),
    )
  // The refusal names the artifact recheck, not a guardian or spawn failure.
  string.contains(reason, "guardian") |> should.be_false
  string.contains(reason, "build") |> should.be_true
  // No evidence directory was created for the refused run.
  simplifile.is_directory(evidence_dir(src, b)) |> should.equal(Ok(False))
}

pub fn real_executor_refuses_once_the_approval_deadline_passed_test() {
  let src = source(fresh_root("deadline"))
  let #(loaded, b) = reserved(src)
  let late = run.real_executor(src, 1000, fn() { 1000 })
  run.execute(
    src,
    runner([#(b.job_id, "available")], quiet()),
    prepared_for(b),
    loaded,
    late,
  )
  |> should.equal(Error("approval_deadline_passed"))
  simplifile.is_directory(evidence_dir(src, b)) |> should.equal(Ok(False))
}
