//// Supervised bounded media janitor. Real store roots under TMPDIR (or /tmp),
//// a fake clock the test advances, and the real actor. Injected `Tick`
//// messages stand in for the cadence so the laws do not wait on wall time;
//// two tests do wait for real `send_after` ticks.

import cepaf_gleam/harness/telegram_media_ref as ref
import cepaf_gleam/harness/telegram_media_store as store
import cepaf_gleam/telegram/telegram_media_janitor as janitor
import envoy
import gleam/bit_array
import gleam/crypto
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/static_supervisor as sup
import gleam/result
import gleam/string
import gleeunit/should
import simplifile

@external(erlang, "erlang", "unique_integer")
fn unique_integer() -> Int

@external(erlang, "erlang", "system_time")
fn system_time() -> Int

@external(erlang, "persistent_term", "put")
fn clock_put(key: String, value: Int) -> Dynamic

@external(erlang, "persistent_term", "get")
fn clock_get(key: String) -> Int

@external(erlang, "persistent_term", "erase")
fn clock_erase(key: String) -> Dynamic

const t0 = 1_000_000

const retention = 60_000

const wait_ms = 1000

fn tmp_base() -> String {
  case envoy.get("TMPDIR") {
    Ok(dir) if dir != "" -> dir
    _ -> "/tmp"
  }
}

fn unique() -> String {
  int.to_string(int.absolute_value(unique_integer()))
  <> "-"
  <> int.to_string(system_time())
}

fn policy(root: String) -> store.Policy {
  store.Policy(
    root: root,
    base: "media",
    retention_ms: retention,
    total_ceiling_bytes: 1_000_000,
  )
}

/// Fresh root plus a fake clock, both removed afterwards.
fn with_env(body: fn(String, String) -> Nil) -> Nil {
  let id = unique()
  let root = tmp_base() <> "/uos-media-janitor-test-" <> id
  let _ = simplifile.delete(root)
  let assert Ok(_) = simplifile.create_directory_all(root)
  let key = "uos_media_janitor_clock_" <> id
  clock_put(key, t0)
  body(root, key)
  let _ = clock_erase(key)
  let _ = simplifile.delete(root)
  Nil
}

fn set_clock(key: String, now: Int) -> Nil {
  clock_put(key, now)
  Nil
}

fn config(
  root: String,
  key: String,
  cadence: Int,
  max_objects: Int,
  history_limit: Int,
) -> janitor.Config {
  janitor.Config(
    policy: policy(root),
    cadence_ms: cadence,
    max_objects: max_objects,
    history_limit: history_limit,
    now_ms: fn() { clock_get(key) },
  )
}

/// Start with a cadence long enough that only injected ticks ever run.
fn start_manual(
  root: String,
  key: String,
  max_objects: Int,
  history_limit: Int,
) -> Subject(janitor.Message) {
  let assert Ok(j) =
    janitor.start(config(root, key, 600_000, max_objects, history_limit))
  j
}

fn text_sha(text: String) -> String {
  crypto.hash(crypto.Sha256, bit_array.from_string(text))
  |> bit_array.base16_encode
  |> string.lowercase
}

fn put_text(root: String, text: String, now: Int) -> store.Stored {
  let assert store.Written(s) =
    store.put(
      policy(root),
      ref.Document,
      "id-" <> text,
      bit_array.from_string(text),
      text_sha(text),
      now,
      0,
    )
  s
}

fn snap(j: Subject(janitor.Message)) -> janitor.Snapshot {
  let assert Ok(s) = janitor.snapshot(j, wait_ms)
  s
}

fn receipt_of(run: janitor.Run) -> store.ReclaimReceipt {
  let assert Ok(r) = run.outcome
  r
}

fn shard_file(root: String, sha: String, ext: String) -> String {
  root <> "/media/" <> string.slice(sha, 0, 2) <> "/" <> sha <> "." <> ext
}

/// Make the store unlistable: `base` becomes a plain file.
fn break_store(root: String) -> Nil {
  let _ = simplifile.delete(root <> "/media")
  let assert Ok(_) = simplifile.write(root <> "/media", "not a directory")
  Nil
}

fn repair_store(root: String) -> Nil {
  let assert Ok(_) = simplifile.delete(root <> "/media")
  let assert Ok(_) = simplifile.create_directory_all(root <> "/media")
  Nil
}

// ------------------------------------------------------------------- reclaim

pub fn one_tick_removes_expired_and_keeps_live_test() {
  use root, key <- with_env
  let _ = put_text(root, "alpha", t0)
  let _ = put_text(root, "beta", t0)
  let live = put_text(root, "gamma", t0 + 50_000)
  let j = start_manual(root, key, 10, 8)
  let now = t0 + retention + 10_000
  set_clock(key, now)
  process.send(j, janitor.Tick)
  let s = snap(j)
  s.runs |> should.equal(1)
  s.consecutive_errors |> should.equal(0)
  s.paused |> should.be_false
  s.next_tick_ms |> should.equal(Some(now + 600_000))
  let assert Some(last) = s.last
  last.started_ms |> should.equal(now)
  let receipt = receipt_of(last)
  list.length(receipt.removed) |> should.equal(2)
  receipt.truncated |> should.be_false
  receipt.refused |> should.equal([])
  s.history |> should.equal([last])
  // the live object is untouched and still served
  store.get(policy(root), live.sha256_hex, now)
  |> result.is_ok
  |> should.be_true
  store.usage(policy(root)) |> should.equal(Ok(5))
  janitor.stop(j) |> should.be_true
}

pub fn max_objects_bounds_each_tick_test() {
  use root, key <- with_env
  let _ = put_text(root, "alpha", t0)
  let _ = put_text(root, "beta", t0)
  let j = start_manual(root, key, 1, 8)
  set_clock(key, t0 + retention)
  process.send(j, janitor.Tick)
  process.send(j, janitor.Tick)
  let s = snap(j)
  s.runs |> should.equal(2)
  let assert [first, second] = s.history
  let r1 = receipt_of(first)
  let r2 = receipt_of(second)
  r1.truncated |> should.be_true
  list.length(r1.removed) |> should.equal(1)
  r2.truncated |> should.be_false
  list.length(r2.removed) |> should.equal(1)
  store.usage(policy(root)) |> should.equal(Ok(0))
  janitor.stop(j) |> should.be_true
}

pub fn history_is_bounded_and_keeps_the_latest_test() {
  use root, key <- with_env
  let j = start_manual(root, key, 5, 2)
  list.each([100, 200, 300], fn(now) {
    set_clock(key, now)
    process.send(j, janitor.Tick)
    // wait for the tick: the actor samples the clock when it handles it
    let _ = snap(j)
    Nil
  })
  let s = snap(j)
  s.runs |> should.equal(3)
  list.map(s.history, fn(r) { r.started_ms }) |> should.equal([200, 300])
  option.map(s.last, fn(r) { r.started_ms }) |> should.equal(Some(300))
  janitor.stop(j) |> should.be_true
}

pub fn tmp_and_foreign_files_survive_a_tick_test() {
  use root, key <- with_env
  let a = put_text(root, "alpha", t0)
  let shard = root <> "/media/" <> string.slice(a.sha256_hex, 0, 2)
  let assert Ok(_) = simplifile.write(shard <> "/.tmp-inflight", "partial")
  let assert Ok(_) = simplifile.write(root <> "/neighbour.txt", "not ours")
  let j = start_manual(root, key, 10, 8)
  set_clock(key, t0 + retention)
  process.send(j, janitor.Tick)
  let s = snap(j)
  let assert Some(last) = s.last
  list.length(receipt_of(last).removed) |> should.equal(1)
  simplifile.is_file(shard_file(root, a.sha256_hex, "bin"))
  |> should.equal(Ok(False))
  simplifile.read(shard <> "/.tmp-inflight") |> should.equal(Ok("partial"))
  simplifile.read(root <> "/neighbour.txt") |> should.equal(Ok("not ours"))
  janitor.stop(j) |> should.be_true
}

// --------------------------------------------------------------- jidoka stop

pub fn three_errors_pause_and_resume_restores_test() {
  use root, key <- with_env
  let _ = put_text(root, "alpha", t0)
  // a real cadence, so a missing pause would produce a visible fourth run
  let assert Ok(j) = janitor.start(config(root, key, 1000, 5, 8))
  break_store(root)
  set_clock(key, t0 + retention)
  process.send(j, janitor.Tick)
  process.send(j, janitor.Tick)
  let two = snap(j)
  two.consecutive_errors |> should.equal(2)
  two.paused |> should.be_false
  process.send(j, janitor.Tick)
  let s = snap(j)
  s.runs |> should.equal(3)
  s.consecutive_errors |> should.equal(3)
  s.paused |> should.be_true
  s.next_tick_ms |> should.equal(None)
  let assert Some(last) = s.last
  last.outcome |> should.equal(Error("store_unavailable"))
  // a whole cadence period (and more) passes: no further run
  process.sleep(1400)
  let still = snap(j)
  still.runs |> should.equal(3)
  still.paused |> should.be_true
  // an injected tick is ignored while paused
  process.send(j, janitor.Tick)
  { snap(j).runs } |> should.equal(3)
  // restore the store and resume: counters reset and the cadence returns
  repair_store(root)
  janitor.resume(j) |> should.be_true
  let resumed = snap(j)
  resumed.paused |> should.be_false
  resumed.consecutive_errors |> should.equal(0)
  { resumed.next_tick_ms != None } |> should.be_true
  let assert Ok(run) = janitor.run_now(j, wait_ms)
  run.outcome |> result.is_ok |> should.be_true
  snap(j).runs |> should.equal(4)
  janitor.stop(j) |> should.be_true
}

pub fn success_resets_the_error_streak_test() {
  use root, key <- with_env
  let j = start_manual(root, key, 5, 8)
  break_store(root)
  process.send(j, janitor.Tick)
  process.send(j, janitor.Tick)
  snap(j).consecutive_errors |> should.equal(2)
  repair_store(root)
  process.send(j, janitor.Tick)
  let s = snap(j)
  s.consecutive_errors |> should.equal(0)
  s.paused |> should.be_false
  janitor.stop(j) |> should.be_true
}

// ------------------------------------------------------------------- run now

pub fn run_now_replies_and_leaves_the_cadence_alone_test() {
  use root, key <- with_env
  let _ = put_text(root, "alpha", t0)
  let j = start_manual(root, key, 5, 8)
  let before = snap(j)
  set_clock(key, t0 + retention + 5000)
  let assert Ok(run) = janitor.run_now(j, wait_ms)
  run.started_ms |> should.equal(t0 + retention + 5000)
  list.length(receipt_of(run).removed) |> should.equal(1)
  let after = snap(j)
  after.runs |> should.equal(1)
  // the scheduled tick is the one planned at start, not a new one
  after.next_tick_ms |> should.equal(before.next_tick_ms)
  janitor.stop(j) |> should.be_true
}

pub fn scheduled_tick_fires_on_the_cadence_test() {
  use root, key <- with_env
  let a = put_text(root, "alpha", t0)
  set_clock(key, t0 + retention)
  let assert Ok(j) = janitor.start(config(root, key, 1000, 5, 8))
  snap(j).runs |> should.equal(0)
  process.sleep(1400)
  let s = snap(j)
  { s.runs >= 1 } |> should.be_true
  simplifile.is_file(shard_file(root, a.sha256_hex, "bin"))
  |> should.equal(Ok(False))
  janitor.stop(j) |> should.be_true
}

pub fn stop_ends_the_actor_test() {
  use root, key <- with_env
  let j = start_manual(root, key, 5, 8)
  janitor.stop(j) |> should.be_true
  process.sleep(50)
  janitor.snapshot(j, 50) |> should.equal(Error(janitor.CallTimeout))
}

// ------------------------------------------------------------------ validate

pub fn validate_refuses_unusable_configs_test() {
  use root, key <- with_env
  let ok = config(root, key, 1000, 1, 1)
  janitor.validate(ok) |> result.is_ok |> should.be_true
  janitor.validate(janitor.Config(..ok, cadence_ms: 999))
  |> result_reason
  |> should.equal("cadence_invalid")
  janitor.validate(janitor.Config(..ok, max_objects: 0))
  |> result_reason
  |> should.equal("max_objects_invalid")
  janitor.validate(janitor.Config(..ok, max_objects: 10_001))
  |> result_reason
  |> should.equal("max_objects_invalid")
  janitor.validate(janitor.Config(..ok, history_limit: 0))
  |> result_reason
  |> should.equal("history_limit_invalid")
  janitor.validate(janitor.Config(..ok, history_limit: 65))
  |> result_reason
  |> should.equal("history_limit_invalid")
  let bad_policy =
    janitor.Config(..ok, policy: store.Policy(..policy(root), base: "../x"))
  janitor.validate(bad_policy)
  |> result_reason
  |> should.equal("policy_invalid")
  // boundaries are accepted
  janitor.validate(janitor.Config(..ok, max_objects: 10_000, history_limit: 64))
  |> result.is_ok
  |> should.be_true
  // and an invalid config never starts an actor
  janitor.start(janitor.Config(..ok, cadence_ms: 10))
  |> result.is_error
  |> should.be_true
}

fn result_reason(r: Result(janitor.Config, String)) -> String {
  case r {
    Ok(_) -> "OK"
    Error(reason) -> reason
  }
}

// --------------------------------------------------------------- supervision

fn wait_for_snapshot(
  j: Subject(janitor.Message),
  attempts: Int,
) -> Result(janitor.Snapshot, Nil) {
  case attempts <= 0 {
    True -> Error(Nil)
    False ->
      case janitor.snapshot(j, 100) {
        Ok(s) -> Ok(s)
        Error(_) -> {
          process.sleep(50)
          wait_for_snapshot(j, attempts - 1)
        }
      }
  }
}

pub fn actor_restarts_under_one_for_one_after_a_kill_test() {
  use root, key <- with_env
  let name = process.new_name("telegram_media_janitor_test_" <> unique())
  let j = process.named_subject(name)
  let assert Ok(_supervisor) =
    sup.new(sup.OneForOne)
    |> sup.add(janitor.child_spec_named(name, config(root, key, 600_000, 5, 8)))
    |> sup.start
  let assert Ok(run) = janitor.run_now(j, wait_ms)
  run.outcome |> result.is_ok |> should.be_true
  snap(j).runs |> should.equal(1)
  let assert Ok(pid) = process.named(name)
  process.kill(pid)
  // the supervisor restarts it under the same name with fresh counters
  let assert Ok(s) = wait_for_snapshot(j, 40)
  s.runs |> should.equal(0)
  s.history |> should.equal([])
  s.paused |> should.be_false
  s.consecutive_errors |> should.equal(0)
  let assert Ok(again) = janitor.run_now(j, wait_ms)
  again.outcome |> result.is_ok |> should.be_true
}

pub fn invalid_config_is_refused_by_the_child_spec_start_test() {
  use root, key <- with_env
  let name = process.new_name("telegram_media_janitor_bad_" <> unique())
  janitor.start_named(name, config(root, key, 5, 5, 8))
  |> result.is_error
  |> should.be_true
}
