//// PRIVATE actual actor/guardian/Ed25519/SQLite tests, not production approval.

import cepaf_gleam/harness/recovery_owner as c
import cepaf_gleam/harness/recovery_owner_store as s
import cepaf_gleam/harness/recovery_wire as w
import cepaf_gleam/harness/telegram_store_transport as t
import cepaf_gleam/harness/value as v
import cepaf_gleam/mcp/json_guard
import envoy
import gleam/erlang/process
import gleam/json
import gleam/option.{None, Some}
import gleam/result
import gleeunit/should
import simplifile

@external(erlang, "erlang", "suspend_process")
fn suspend(pid: process.Pid) -> Bool

@external(erlang, "erlang", "resume_process")
fn resume(pid: process.Pid) -> Bool

fn dead_bool(pid, n) {
  case process.is_alive(pid), n > 0 {
    False, _ -> True
    True, True -> {
      process.sleep(1)
      dead_bool(pid, n - 1)
    }
    _, _ -> False
  }
}

fn until_mono(target, n) {
  case c.monotonic_ms() >= target, n > 0 {
    True, _ -> Nil
    False, True -> {
      process.sleep(1)
      until_mono(target, n - 1)
    }
    _, _ -> panic as "monotonic wait bound"
  }
}

pub fn actual_delayed_callback_cannot_dispatch_after_immutable_deadline_test() {
  let f = fixture(20_000, 200)
  let reached = process.new_subject()
  let calls = process.new_subject()
  let assert Ok(owner) =
    c.fixture_start(
      f.config,
      fn() { Ok(Nil) },
      fn() { Ok(Nil) },
      fn(stage) {
        case stage == "pending_created_by_this_owner" {
          True -> {
            let release = process.new_subject()
            process.send(reached, #(release, process.self()))
            let _ = process.receive(release, 3000)
            quiet(f, stage)
          }
          False -> quiet(f, stage)
        }
      },
      fn(body) {
        process.send(calls, Nil)
        real(f, body)
      },
    )
    |> result.map(fn(x) { x.data })
  await(owner, 2000).phase |> should.equal(c.DataOnly)
  let replies = process.new_subject()
  let started = c.monotonic_ms()
  let _ = process.spawn(fn() { process.send(replies, commit(owner)) })
  let assert Ok(#(release, worker_pid)) = process.receive(reached, 3000)
  let assert Ok(owner_pid) = process.subject_owner(owner)
  suspend(owner_pid) |> should.be_true()
  until_mono(started + 350, 2000)
  process.send(release, Nil)
  let worker_ended = dead_bool(worker_pid, 3000)
  resume(owner_pid) |> should.be_true()
  worker_ended |> should.be_true()
  process.receive(calls, 20) |> should.be_error()
  observe(f)
  |> should.equal(v.Array([v.Integer(1), v.Integer(1), v.Integer(1)]))
  let _ = process.receive(replies, 2000)
  let _ = c.stop(owner, 1000)
  Nil
}

fn env(k) {
  let assert Ok(v) = envoy.get(k)
  v
}

fn helper(locator) {
  t.reviewed_local_configuration(
    env("UOS_OWNER_GUARDIAN"),
    env("UOS_OWNER_GUARDIAN_SHA"),
    env("UOS_OWNER_FIXTURE"),
    env("UOS_OWNER_FIXTURE_SHA"),
    locator,
  )
}

fn call_helper(directory, op, ttl) {
  let body =
    json.to_string(
      json.object([#("operation", json.string(op)), #("ttl_ms", json.int(ttl))]),
    )
  let raw = s.raw_exchange(helper(directory), body)
  s.successful(raw.cleanup) |> should.be_true()
  let assert Ok(body) = raw.body
  let assert Ok(value) = json_guard.native_inspect(body, 12)
  value
}

fn field(v, k) {
  let assert Ok(s) = s.text(v, k)
  s
}

type Fixture {
  Fixture(
    data: v.Value,
    config: c.ConfigurationData,
    effect: t.LocalConfiguration,
  )
}

fn fixture(ttl, timeout) {
  let data = call_helper("/unused-private-fixture", "prepare", ttl)
  let journal =
    t.reviewed_local_configuration(
      field(data, "guardian"),
      field(data, "guardian_sha256"),
      field(data, "journal_worker"),
      field(data, "journal_worker_sha256"),
      field(data, "journal_database"),
    )
  let effect =
    t.reviewed_local_configuration(
      field(data, "guardian"),
      field(data, "guardian_sha256"),
      field(data, "worker"),
      field(data, "worker_sha256"),
      field(data, "native_locator"),
    )
  let assert Ok(request) = w.decode(field(data, "factual_request"))
  let assert Ok(config) =
    c.configuration_data(
      "fixture-owner",
      request,
      field(data, "context_sha256"),
      field(data, "commit_body"),
      field(data, "inspect_body"),
      journal,
      timeout,
    )
  Fixture(data, config, effect)
}

fn quiet(f: Fixture, stage: String) {
  case
    call_helper(
      field(f.data, "directory"),
      case stage == "pending_created_by_this_owner" {
        True -> "probe_pending_created"
        False -> "probe"
      },
      0,
    )
  {
    v.Boolean(True) -> Ok(Nil)
    _ -> Error("ACTUAL_NATIVE_NOT_QUIESCENT")
  }
}

fn await(owner, n) {
  let assert Ok(s) = c.get(owner, 1000)
  case s.in_flight && n > 0 {
    True -> {
      process.sleep(1)
      await(owner, n - 1)
    }
    False -> s
  }
}

fn until_file(path, n) {
  case simplifile.is_file(path), n > 0 {
    Ok(True), _ -> Nil
    _, True -> {
      process.sleep(1)
      until_file(path, n - 1)
    }
    _, False -> panic as "fixture file deadline"
  }
}

fn until_quiet(f, n) {
  case quiet(f, "reconciliation"), n > 0 {
    Ok(_), _ -> Nil
    _, True -> {
      process.sleep(1)
      until_quiet(f, n - 1)
    }
    _, False -> panic as "actual native reap deadline"
  }
}

fn start(f: Fixture, effect) {
  let assert Ok(owner) =
    c.fixture_start(
      f.config,
      fn() { Ok(Nil) },
      fn() { Ok(Nil) },
      fn(stage) { quiet(f, stage) },
      effect,
    )
    |> result.map(fn(x) { x.data })
  let s = await(owner, 2000)
  s.phase |> should.equal(c.DataOnly)
  owner
}

fn real(f: Fixture, body) {
  s.raw_exchange(f.effect, body)
}

fn observe(f: Fixture) {
  call_helper(field(f.data, "directory"), "observe", 0)
}

fn commit(owner) {
  let assert Ok(before) = c.get(owner, 1000)
  c.commit(owner, c.Step(before.operation_id, before.revision), 10_000)
}

pub fn actual_journal_append_and_reply_digest_parity_test() {
  let f = fixture(20_000, 15_000)
  let journal =
    t.reviewed_local_configuration(
      field(f.data, "guardian"),
      field(f.data, "guardian_sha256"),
      field(f.data, "journal_worker"),
      field(f.data, "journal_worker_sha256"),
      field(f.data, "journal_database"),
    )
  let b = c.binding(f.config)
  let initial = s.exchange(journal, b, None, None)
  let assert Ok(s.Reply("LATEST", None)) = initial.reply
  let appended = s.exchange(journal, b, Some(#(1, s.Pending, None)), None)
  let assert Ok(s.Reply("APPENDED", Some(r))) = appended.reply
  r.sequence |> should.equal(1)
  let repeated = s.exchange(journal, b, Some(#(1, s.Pending, None)), None)
  let assert Ok(s.Reply("REPLAY", Some(same))) = repeated.reply
  same |> should.equal(r)
}

pub fn actual_task_fixture_protocol_positive_control_test() {
  let f = fixture(20_000, 15_000)
  let response = real(f, field(f.data, "commit_body"))
  s.successful(response.cleanup) |> should.be_true()
  let assert Ok(raw) = response.body
  let assert Ok(value) = json_guard.native_inspect(raw, 12)
  field(value, "code") |> should.equal("FIXTURE_COMMIT")
  field(value, "status") |> should.equal("COMMITTED")
  observe(f)
  |> should.equal(v.Array([v.Integer(2), v.Integer(2), v.Integer(2)]))
}

pub fn actual_guarded_commit_restart_and_no_redispatch_test() {
  let f = fixture(20_000, 15_000)
  let owner = start(f, fn(body) { real(f, body) })
  let assert Ok(done) = commit(owner)
  done.phase |> should.equal(c.HistoricalFact)
  done.observed_effect_exchanges |> should.equal(1)
  observe(f)
  |> should.equal(v.Array([v.Integer(2), v.Integer(2), v.Integer(2)]))
  commit(owner) |> should.be_error()
  c.stop(owner, 1000) |> should.be_ok()
  let assert Ok(restarted) =
    c.fixture_start(
      f.config,
      fn() { Ok(Nil) },
      fn() { Ok(Nil) },
      fn(stage) { quiet(f, stage) },
      fn(body) { real(f, body) },
    )
    |> result.map(fn(x) { x.data })
  await(restarted, 2000).phase |> should.equal(c.ReconcileOnly)
  commit(restarted) |> should.be_error()
  let assert Ok(history) = c.reconcile(restarted, 10_000)
  history.phase |> should.equal(c.HistoricalFact)
  observe(f)
  |> should.equal(v.Array([v.Integer(2), v.Integer(2), v.Integer(2)]))
  c.stop(restarted, 1000) |> should.be_ok()
}

pub fn lost_ack_keeps_pending_and_post_expiry_restart_uses_history_only_test() {
  let f = fixture(1200, 15_000)
  let owner =
    start(f, fn(body) {
      let actual = real(f, body)
      s.RawExchange(Error("ACTUAL_BODY_DROPPED_AFTER_REAP"), actual.cleanup)
    })
  let assert Ok(unknown) = commit(owner)
  unknown.phase |> should.equal(c.ReconcileOnly)
  observe(f)
  |> should.equal(v.Array([v.Integer(2), v.Integer(2), v.Integer(2)]))
  c.stop(owner, 1000) |> should.be_ok()
  process.sleep(1300)
  let assert Ok(restarted) =
    c.fixture_start(
      f.config,
      fn() { Ok(Nil) },
      fn() { Ok(Nil) },
      fn(stage) { quiet(f, stage) },
      fn(body) { real(f, body) },
    )
    |> result.map(fn(x) { x.data })
  await(restarted, 2000).phase |> should.equal(c.ReconcileOnly)
  commit(restarted) |> should.be_error()
  let assert Ok(history) = c.reconcile(restarted, 10_000)
  history.phase |> should.equal(c.HistoricalFact)
  observe(f)
  |> should.equal(v.Array([v.Integer(2), v.Integer(2), v.Integer(2)]))
  c.stop(restarted, 1000) |> should.be_ok()
}

pub fn missing_cleanup_witness_fences_all_followup_native_dispatch_test() {
  let f = fixture(20_000, 15_000)
  let calls = process.new_subject()
  let owner =
    start(f, fn(body) {
      process.send(calls, Nil)
      let actual = real(f, body)
      s.RawExchange(actual.body, s.Unconfirmed)
    })
  let assert Ok(unknown) = commit(owner)
  unknown.phase |> should.equal(c.CleanupUnconfirmed)
  let assert Ok(_) = process.receive(calls, 1000)
  c.reconcile(owner, 1000) |> should.be_error()
  commit(owner) |> should.be_error()
  process.receive(calls, 20) |> should.be_error()
  observe(f)
  |> should.equal(v.Array([v.Integer(2), v.Integer(2), v.Integer(2)]))
  c.stop(owner, 1000) |> should.be_ok()
}

pub fn two_real_owners_same_pending_cas_commit_at_most_once_test() {
  let f = fixture(20_000, 15_000)
  let a = start(f, fn(body) { real(f, body) })
  let b = start(f, fn(body) { real(f, body) })
  let replies = process.new_subject()
  let _ = process.spawn(fn() { process.send(replies, commit(a)) })
  let _ = process.spawn(fn() { process.send(replies, commit(b)) })
  let assert Ok(Ok(sa)) = process.receive(replies, 20_000)
  let assert Ok(Ok(sb)) = process.receive(replies, 20_000)
  { sa.observed_effect_exchanges + sb.observed_effect_exchanges }
  |> should.equal(1)
  observe(f)
  |> should.equal(v.Array([v.Integer(2), v.Integer(2), v.Integer(2)]))
  c.stop(a, 1000) |> should.be_ok()
  c.stop(b, 1000) |> should.be_ok()
}

pub fn actual_blocked_native_timeout_reaps_and_restart_needs_quiescence_test() {
  let f = fixture(20_000, 250)
  let lock_done = process.new_subject()
  let _ =
    process.spawn(fn() {
      let raw =
        s.raw_exchange(
          helper(field(f.data, "directory")),
          json.to_string(
            json.object([#("operation", json.string("hold_lock"))]),
          ),
        )
      process.send(lock_done, raw)
    })
  until_file(field(f.data, "directory") <> "/lock-ready", 2000)
  let owner = start(f, fn(body) { real(f, body) })
  let replies = process.new_subject()
  let _ = process.spawn(fn() { process.send(replies, commit(owner)) })
  until_file(field(f.data, "marker"), 2000)
  let assert Ok(restarted) =
    c.fixture_start(
      f.config,
      fn() { Ok(Nil) },
      fn() { Ok(Nil) },
      fn(stage) { quiet(f, stage) },
      fn(_) { panic as "no native replacement while actual old PID lives" },
    )
    |> result.map(fn(x) { x.data })
  await(restarted, 2000).phase |> should.equal(c.Unavailable)
  c.stop(restarted, 1000) |> should.be_ok()
  let assert Ok(Ok(timed)) = process.receive(replies, 5000)
  timed.phase |> should.equal(c.CleanupUnconfirmed)
  until_quiet(f, 2000)
  c.reconcile(owner, 1000) |> should.be_error()
  c.stop(owner, 1000) |> should.be_ok()
  // Lock helper intentionally times out under its own guardian; no claim of
  // normal fixture reply. This diagnostic process is not the task worker.
  let assert Ok(lock_result) = process.receive(lock_done, 6000)
  s.cleanup_known(lock_result.cleanup) |> should.be_true()
  observe(f)
  |> should.equal(v.Array([v.Integer(1), v.Integer(1), v.Integer(1)]))
}

fn held_lock(f: Fixture) {
  let done = process.new_subject()
  let _ =
    process.spawn(fn() {
      process.send(
        done,
        s.raw_exchange(
          helper(field(f.data, "directory")),
          json.to_string(
            json.object([#("operation", json.string("hold_lock"))]),
          ),
        ),
      )
    })
  until_file(field(f.data, "directory") <> "/lock-ready", 2000)
  done
}

fn release_lock(done: process.Subject(s.RawExchange)) {
  let assert Ok(result) = process.receive(done, 6000)
  s.cleanup_known(result.cleanup) |> should.be_true()
}

fn until_dead(pid, n) {
  case process.is_alive(pid), n > 0 {
    False, _ -> Nil
    True, True -> {
      process.sleep(1)
      until_dead(pid, n - 1)
    }
    True, False -> panic as "BEAM owner reap deadline"
  }
}

pub fn actual_normal_creator_death_retains_pending_and_reaps_native_test() {
  let f = fixture(20_000, 15_000)
  let lock = held_lock(f)
  let created = process.new_subject()
  let _ =
    process.spawn_unlinked(fn() {
      let done = process.new_subject()
      let owner = start(f, fn(body) { real(f, body) })
      process.send(created, #(owner, done))
      let _ = process.receive(done, 20_000)
      Nil
    })
  let assert Ok(#(owner, creator_done)) = process.receive(created, 3000)
  let assert Ok(owner_pid) = process.subject_owner(owner)
  let replies = process.new_subject()
  let _ = process.spawn(fn() { process.send(replies, commit(owner)) })
  until_file(field(f.data, "marker"), 2000)
  process.send(creator_done, Nil)
  until_dead(owner_pid, 2000)
  until_quiet(f, 2000)
  let assert Ok(Error(_)) = process.receive(replies, 2000)
  release_lock(lock)
  let assert Ok(restarted) =
    c.fixture_start(
      f.config,
      fn() { Ok(Nil) },
      fn() { Ok(Nil) },
      fn(stage) { quiet(f, stage) },
      fn(body) { real(f, body) },
    )
    |> result.map(fn(x) { x.data })
  await(restarted, 2000).phase |> should.equal(c.ReconcileOnly)
  commit(restarted) |> should.be_error()
  let assert Ok(absent) = c.reconcile(restarted, 10_000)
  absent.phase |> should.equal(c.ReconcileOnly)
  observe(f)
  |> should.equal(v.Array([v.Integer(1), v.Integer(1), v.Integer(1)]))
  c.stop(restarted, 1000) |> should.be_ok()
}

pub fn actual_abrupt_owner_kill_leaves_durable_pending_and_no_native_orphan_test() {
  let f = fixture(20_000, 15_000)
  let lock = held_lock(f)
  let created = process.new_subject()
  let _ =
    process.spawn_unlinked(fn() {
      let owner = start(f, fn(body) { real(f, body) })
      process.send(created, owner)
      process.sleep(20_000)
    })
  let assert Ok(owner) = process.receive(created, 3000)
  let assert Ok(pid) = process.subject_owner(owner)
  let replies = process.new_subject()
  let _ =
    process.spawn(fn() {
      let assert Ok(snap) = c.get(owner, 1000)
      process.send(
        replies,
        c.commit(owner, c.Step(snap.operation_id, snap.revision), 1000),
      )
    })
  until_file(field(f.data, "marker"), 2000)
  process.kill(pid)
  until_dead(pid, 2000)
  until_quiet(f, 2000)
  let assert Ok(Error(_)) = process.receive(replies, 2000)
  release_lock(lock)
  let assert Ok(restarted) =
    c.fixture_start(
      f.config,
      fn() { Ok(Nil) },
      fn() { Ok(Nil) },
      fn(stage) { quiet(f, stage) },
      fn(body) { real(f, body) },
    )
    |> result.map(fn(x) { x.data })
  await(restarted, 2000).phase |> should.equal(c.ReconcileOnly)
  commit(restarted) |> should.be_error()
  observe(f)
  |> should.equal(v.Array([v.Integer(1), v.Integer(1), v.Integer(1)]))
  c.stop(restarted, 1000) |> should.be_ok()
}

pub fn actual_stop_inflight_kills_worker_and_keeps_unknown_not_retry_test() {
  let f = fixture(20_000, 15_000)
  let lock = held_lock(f)
  let owner = start(f, fn(body) { real(f, body) })
  let replies = process.new_subject()
  let _ = process.spawn(fn() { process.send(replies, commit(owner)) })
  until_file(field(f.data, "marker"), 2000)
  c.stop(owner, 2000) |> should.be_error()
  let assert Ok(Error(_)) = process.receive(replies, 2000)
  until_quiet(f, 2000)
  release_lock(lock)
  let assert Ok(restarted) =
    c.fixture_start(
      f.config,
      fn() { Ok(Nil) },
      fn() { Ok(Nil) },
      fn(stage) { quiet(f, stage) },
      fn(body) { real(f, body) },
    )
    |> result.map(fn(x) { x.data })
  await(restarted, 2000).phase |> should.equal(c.ReconcileOnly)
  commit(restarted) |> should.be_error()
  observe(f)
  |> should.equal(v.Array([v.Integer(1), v.Integer(1), v.Integer(1)]))
  c.stop(restarted, 1000) |> should.be_ok()
}

pub fn pending_created_witness_cannot_be_reconstructed_after_owner_loss_test() {
  let f = fixture(20_000, 15_000)
  let reached = process.new_subject()
  let never = process.new_subject()
  let assert Ok(owner) =
    c.fixture_start(
      f.config,
      fn() { Ok(Nil) },
      fn() { Ok(Nil) },
      fn(stage) {
        case stage == "pending_created_by_this_owner" {
          True -> {
            process.send(reached, Nil)
            let _ = process.receive(never, 20_000)
            Error("INJECTED_PRE_DISPATCH_PAUSE")
          }
          False -> quiet(f, stage)
        }
      },
      fn(_) { panic as "never dispatched before pending ownership witness" },
    )
    |> result.map(fn(x) { x.data })
  await(owner, 2000).phase |> should.equal(c.DataOnly)
  let result = process.new_subject()
  let _ = process.spawn(fn() { process.send(result, commit(owner)) })
  let assert Ok(_) = process.receive(reached, 3000)
  c.stop(owner, 2000) |> should.be_error()
  let assert Ok(Error(_)) = process.receive(result, 2000)
  let stages = process.new_subject()
  let assert Ok(restarted) =
    c.fixture_start(
      f.config,
      fn() { Ok(Nil) },
      fn() { Ok(Nil) },
      fn(stage) {
        process.send(stages, stage)
        quiet(f, stage)
      },
      fn(_) { panic as "restart cannot reuse pending-created witness" },
    )
    |> result.map(fn(x) { x.data })
  await(restarted, 2000).phase |> should.equal(c.Unavailable)
  let assert Ok("startup") = process.receive(stages, 1000)
  process.receive(stages, 20) |> should.be_error()
  commit(restarted) |> should.be_error()
  observe(f)
  |> should.equal(v.Array([v.Integer(1), v.Integer(1), v.Integer(1)]))
  c.stop(restarted, 1000) |> should.be_ok()
}

pub fn journal_claim_without_native_receipt_never_becomes_historical_fact_test() {
  let f = fixture(20_000, 15_000)
  let read = real(f, field(f.data, "inspect_body"))
  s.successful(read.cleanup) |> should.be_true()
  let journal =
    t.reviewed_local_configuration(
      field(f.data, "guardian"),
      field(f.data, "guardian_sha256"),
      field(f.data, "journal_worker"),
      field(f.data, "journal_worker_sha256"),
      field(f.data, "journal_database"),
    )
  let b = c.binding(f.config)
  let assert Ok(s.Reply(_, Some(pending))) =
    s.exchange(journal, b, Some(#(1, s.Pending, None)), None).reply
  let assert Ok(_) =
    s.exchange(
      journal,
      b,
      Some(#(2, s.CommittedFact, Some(b.operation_id))),
      Some(pending.sha256),
    ).reply
  let assert Ok(owner) =
    c.fixture_start(
      f.config,
      fn() { Ok(Nil) },
      fn() { Ok(Nil) },
      fn(stage) { quiet(f, stage) },
      fn(body) { real(f, body) },
    )
    |> result.map(fn(x) { x.data })
  await(owner, 2000).phase |> should.equal(c.ReconcileOnly)
  commit(owner) |> should.be_error()
  let assert Ok(unproven) = c.reconcile(owner, 10_000)
  unproven.phase |> should.equal(c.ReconcileOnly)
  observe(f)
  |> should.equal(v.Array([v.Integer(1), v.Integer(1), v.Integer(1)]))
  c.stop(owner, 1000) |> should.be_ok()
}

pub fn malformed_existing_journal_never_loads_ready_or_dispatches_test() {
  let f = fixture(20_000, 15_000)
  call_helper(field(f.data, "directory"), "corrupt_journal", 0)
  |> should.equal(v.Boolean(True))
  let assert Ok(owner) =
    c.fixture_start(
      f.config,
      fn() { Ok(Nil) },
      fn() { Ok(Nil) },
      fn(stage) { quiet(f, stage) },
      fn(_) { panic as "malformed journal cannot dispatch" },
    )
    |> result.map(fn(x) { x.data })
  await(owner, 2000).phase |> should.equal(c.ReconcileOnly)
  commit(owner) |> should.be_error()
  observe(f)
  |> should.equal(v.Array([v.Integer(1), v.Integer(1), v.Integer(1)]))
  c.stop(owner, 1000) |> should.be_ok()
}
