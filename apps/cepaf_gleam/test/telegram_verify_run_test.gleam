//// Laws for the /verify run orchestration: reserve is idempotent and binds
//// the job, a completed request returns its stored receipt and never reruns,
//// partial and in-progress state refuse, a mismatched reservation refuses,
//// and the real executor rechecks artifacts and runs the pinned guardian.

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
import gleam/result
import gleam/string
import gleeunit/should
import simplifile
import telegram_verify_action_test as fx

const guardian_sha256 = "d1dc2995fe52915e9c2a7b39309f23a8197cfb273d025f3453ebd904b24f50f4"

const request_id = "bot7/inbox19"

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

/// A stateless fake sa-plan: `job list` answers with the given rows (job id,
/// state) and `job enqueue` succeeds. Every argv is reported on `calls`.
fn runner(
  rows: List(#(String, String)),
  calls: process.Subject(List(String)),
) -> job.Runner {
  fn(args) {
    process.send(calls, args)
    case args {
      ["--format", "json", "job", "list", queue] ->
        rows
        |> list.map(fn(row) {
          json.object([
            #("id", json.string(row.0)),
            #("queue", json.string(queue)),
            #("worker", json.string(fx.worker)),
            #("state", json.string(row.1)),
            #("attempt", json.string("1")),
          ])
          |> json.to_string
        })
        |> string.join("\n")
        |> Ok
      // Sa-plan refuses a duplicate job id; the fake does the same so that a
      // replayed reserve observes AlreadyEnqueued, as the real store would.
      ["job", "enqueue", id, ..] ->
        case list.any(rows, fn(row) { row.0 == id }) {
          True -> Error("UNIQUE constraint failed: sa_plan_job.id")
          False -> Ok("enqueued")
        }
      _ -> Error("unexpected_argv")
    }
  }
}

fn reserved(src: run.Source) -> #(loader.Loaded, v.Binding) {
  // Before enqueue the list is empty; the fake answers the row after enqueue
  // because it is stateless, so derive the binding first to build the row.
  let assert Ok(loaded) =
    loader.load(src.root, src.profile_path, src.pin, src.locators)
  let assert Ok(b) = v.binding(loader.profile(loaded), request_id, 1)
  let assert Ok(#(loaded, b2, ensured)) =
    run.reserve(
      src,
      runner([#(b.job_id, "available")], process.new_subject()),
      request_id,
      1,
    )
  b2 |> should.equal(b)
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
fn counting_executor(
  calls: process.Subject(v.Binding),
) -> run.Executor {
  fn(_loaded, b) {
    process.send(calls, b)
    Ok(fake_outcome())
  }
}

fn evidence_dir(src: run.Source, b: v.Binding) -> String {
  src.root <> "/" <> executor.evidence_dir(src.evidence_base, b)
}

pub fn reserve_is_idempotent_and_conflicts_on_another_binding_test() {
  let src = source(fresh_root("reserve"))
  let #(_, b) = reserved(src)
  // Same request again: Existing reservation, AlreadyEnqueued job.
  let assert Ok(#(_, again, ensured)) =
    run.reserve(
      src,
      runner([#(b.job_id, "available")], process.new_subject()),
      request_id,
      1,
    )
  again |> should.equal(b)
  case ensured {
    job.AlreadyEnqueued(_) -> Nil
    job.Enqueued(_) -> should.fail()
  }
  // A different attempt for the same inbox request is a conflict.
  run.reserve(
    src,
    runner([#(b.job_id, "available")], process.new_subject()),
    request_id,
    2,
  )
  |> should.equal(Error("reservation_conflict"))
}

pub fn not_run_executes_once_through_the_injected_executor_test() {
  let src = source(fresh_root("notrun"))
  let #(loaded, b) = reserved(src)
  let calls = process.new_subject()
  let assert Ok(run.Executed(out)) =
    run.execute(
      src,
      runner([#(b.job_id, "available")], process.new_subject()),
      prepared_for(b),
      loaded,
      counting_executor(calls),
    )
  out.assessment |> should.equal(v.VerifiedEvidence)
  process.receive(calls, 100) |> should.equal(Ok(b))
  process.receive(calls, 0) |> should.be_error
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
    runner([#(b.job_id, "available")], process.new_subject()),
    prepared_for(b),
    loaded,
    counting_executor(calls),
  )
  |> should.equal(Ok(run.AlreadyComplete("{\"stored\":1}")))
  process.receive(calls, 0) |> should.be_error
}

pub fn partial_in_progress_and_missing_job_refuse_test() {
  let src = source(fresh_root("refuse"))
  let #(loaded, b) = reserved(src)
  let calls = process.new_subject()
  // Job row says executing: another run owns it.
  run.execute(
    src,
    runner([#(b.job_id, "executing")], process.new_subject()),
    prepared_for(b),
    loaded,
    counting_executor(calls),
  )
  |> should.equal(Ok(run.Refused("in_progress")))
  // No job row at all although reserved.
  run.execute(
    src,
    runner([], process.new_subject()),
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
    runner([#(b.job_id, "available")], process.new_subject()),
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
    runner([#(b.job_id, "available")], process.new_subject()),
    prepared_for(other),
    loaded,
    counting_executor(calls),
  )
  |> should.equal(Ok(run.Refused("reservation_binding_mismatch")))
  process.receive(calls, 0) |> should.be_error
}

pub fn real_executor_rechecks_and_runs_the_pinned_guardian_test() {
  let src = source(fresh_root("real"))
  let #(loaded, b) = reserved(src)
  let assert Ok(run.Executed(out)) =
    run.execute(
      src,
      runner([#(b.job_id, "available")], process.new_subject()),
      prepared_for(b),
      loaded,
      run.real_executor(src),
    )
  out.assessment |> should.equal(v.VerifiedEvidence)
  list.map(out.runs, fn(r) { r.status }) |> should.equal(["PASS"])
  // The receipt now exists, so a second execute returns it unchanged.
  let assert Ok(run.AlreadyComplete(receipt)) =
    run.execute(
      src,
      runner([#(b.job_id, "available")], process.new_subject()),
      prepared_for(b),
      loaded,
      run.real_executor(src),
    )
  receipt |> should.equal(out.receipt)
}

pub fn real_executor_refuses_a_changed_artifact_before_spawning_test() {
  let src = source(fresh_root("swap"))
  let #(loaded, b) = reserved(src)
  let assert Ok(_) =
    simplifile.write(src.root <> "/gates/build.sh", "#!/bin/sh\necho swapped\n")
  run.execute(
    src,
    runner([#(b.job_id, "available")], process.new_subject()),
    prepared_for(b),
    loaded,
    run.real_executor(src),
  )
  |> result.is_error
  |> should.be_true
  // No evidence directory was created for the refused run.
  simplifile.is_directory(evidence_dir(src, b)) |> should.equal(Ok(False))
}
