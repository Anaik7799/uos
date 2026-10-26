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
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor as sup
import gleam/otp/supervision
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

@external(erlang, "erlang", "system_time")
fn system_time_in(unit: Atom) -> Int

type LocalTime

@external(erlang, "calendar", "system_time_to_local_time")
fn local_time(seconds: Int, unit: Atom) -> LocalTime

@external(erlang, "file", "change_time")
fn change_time(path: String, time: LocalTime) -> Dynamic

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
    orphan_grace_ms: store.default_orphan_grace_ms,
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

// ------------------------------------------------------------ orphans (M2-02)

fn host_now_ms() -> Int {
  system_time_in(atom.create("millisecond"))
}

fn age(path: String, seconds: Int) -> Nil {
  let then = system_time_in(atom.create("second")) - seconds
  let _ = change_time(path, local_time(then, atom.create("second")))
  Nil
}

pub fn a_tick_reclaims_aged_orphans_and_keeps_young_ones_test() {
  use root, key <- with_env
  let a = put_text(root, "alpha", t0)
  let b = put_text(root, "beta", t0)
  let shard = root <> "/media/" <> string.slice(a.sha256_hex, 0, 2)
  let assert Ok(_) = simplifile.delete(shard_file(root, a.sha256_hex, "json"))
  let assert Ok(_) = simplifile.delete(shard_file(root, b.sha256_hex, "json"))
  let assert Ok(_) = simplifile.write(shard <> "/.tmp-stale", "partial")
  let assert Ok(_) = simplifile.write(shard <> "/.tmp-young", "partial")
  age(shard_file(root, a.sha256_hex, "bin"), 3600)
  age(shard <> "/.tmp-stale", 3600)
  let j = start_manual(root, key, 10, 8)
  // the host clock: the files' mtimes are real, so the janitor's now must be too
  set_clock(key, host_now_ms())
  process.send(j, janitor.Tick)
  let s = snap(j)
  let assert Some(last) = s.last
  let assert Ok(orphans) = last.orphans
  list.map(orphans.removed, fn(r) { r.kind })
  |> list.sort(fn(x, y) {
    string.compare(string.inspect(x), string.inspect(y))
  })
  |> should.equal([store.OrphanBin, store.OrphanTmp])
  simplifile.is_file(shard_file(root, a.sha256_hex, "bin"))
  |> should.equal(Ok(False))
  simplifile.is_file(shard <> "/.tmp-stale") |> should.equal(Ok(False))
  simplifile.is_file(shard_file(root, b.sha256_hex, "bin"))
  |> should.equal(Ok(True))
  simplifile.is_file(shard <> "/.tmp-young") |> should.equal(Ok(True))
  s.consecutive_errors |> should.equal(0)
  janitor.stop(j) |> should.be_true
}

pub fn one_tick_never_deletes_more_than_max_objects_in_total_test() {
  use root, key <- with_env
  let _ = put_text(root, "alpha", t0)
  let b = put_text(root, "beta", t0)
  let c = put_text(root, "gamma", t0)
  // alpha is expired; beta and gamma are old orphans
  let assert Ok(_) = simplifile.delete(shard_file(root, b.sha256_hex, "json"))
  let assert Ok(_) = simplifile.delete(shard_file(root, c.sha256_hex, "json"))
  age(shard_file(root, b.sha256_hex, "bin"), 3600)
  age(shard_file(root, c.sha256_hex, "bin"), 3600)
  let j = start_manual(root, key, 2, 8)
  // the object's retention horizon is t0+retention in its own (fake) clock
  // domain; the janitor clock is the host clock, so alpha is long expired
  set_clock(key, host_now_ms())
  let assert Ok(run) = janitor.run_now(j, wait_ms)
  let expired = receipt_of(run)
  let assert Ok(orphans) = run.orphans
  list.length(expired.removed) |> should.equal(1)
  // 2 - 1 examined = 1 left for orphans: exactly one of the two
  list.length(orphans.removed) |> should.equal(1)
  orphans.truncated |> should.be_true
  janitor.stop(j) |> should.be_true
}

// ---------------------------------------------------- refusals and the pause

/// Replace an object's bin by a symlink: its delete is refused untouched.
fn refuse_object(root: String, sha: String) -> Nil {
  let bin = shard_file(root, sha, "bin")
  let assert Ok(_) = simplifile.write_bits(root <> "/outside.bin", <<"x":utf8>>)
  let assert Ok(_) = simplifile.delete(bin)
  let assert Ok(_) = simplifile.create_symlink("../../outside.bin", bin)
  Nil
}

pub fn three_all_refused_runs_pause_the_janitor_test() {
  use root, key <- with_env
  let a = put_text(root, "alpha", t0)
  refuse_object(root, a.sha256_hex)
  let j = start_manual(root, key, 5, 8)
  set_clock(key, t0 + retention)
  process.send(j, janitor.Tick)
  process.send(j, janitor.Tick)
  let two = snap(j)
  // the call itself succeeded, but every attempted deletion was refused
  two.consecutive_errors |> should.equal(2)
  two.paused |> should.be_false
  process.send(j, janitor.Tick)
  let s = snap(j)
  s.consecutive_errors |> should.equal(3)
  s.paused |> should.be_true
  s.next_tick_ms |> should.equal(None)
  s.last_refused |> should.equal(1)
  s.refused_total |> should.equal(3)
  let assert Some(last) = s.last
  last.outcome |> result.is_ok |> should.be_true
  last.refused |> should.equal(1)
  janitor.stop(j) |> should.be_true
}

pub fn a_run_that_removes_something_is_not_failed_by_a_refusal_test() {
  use root, key <- with_env
  let a = put_text(root, "alpha", t0)
  let _ = put_text(root, "beta", t0)
  refuse_object(root, a.sha256_hex)
  let j = start_manual(root, key, 5, 8)
  set_clock(key, t0 + retention)
  list.each([1, 2, 3, 4], fn(_) { process.send(j, janitor.Tick) })
  let s = snap(j)
  // run 1 removed beta and refused alpha: not a failure. Runs 2-4 only
  // refuse alpha, so the streak starts there
  s.runs |> should.equal(4)
  s.consecutive_errors |> should.equal(3)
  s.paused |> should.be_true
  let assert [first, ..] = s.history
  first.refused |> should.equal(1)
  list.length(receipt_of(first).removed) |> should.equal(1)
  janitor.stop(j) |> should.be_true
}

pub fn a_malformed_index_alone_is_not_a_failed_run_test() {
  use root, key <- with_env
  let a = put_text(root, "alpha", t0)
  let assert Ok(_) =
    simplifile.write(shard_file(root, a.sha256_hex, "json"), "{broken")
  let j = start_manual(root, key, 5, 8)
  set_clock(key, t0 + retention)
  list.each([1, 2, 3, 4], fn(_) { process.send(j, janitor.Tick) })
  let s = snap(j)
  s.runs |> should.equal(4)
  s.consecutive_errors |> should.equal(0)
  s.paused |> should.be_false
  janitor.stop(j) |> should.be_true
}

pub fn refusals_in_history_are_bounded_and_counted_test() {
  use root, key <- with_env
  list.repeat(Nil, 40)
  |> list.index_map(fn(_, i) {
    let s = put_text(root, "obj-" <> int.to_string(i), t0)
    refuse_object(root, s.sha256_hex)
  })
  let j = start_manual(root, key, 100, 8)
  set_clock(key, t0 + retention)
  let assert Ok(run) = janitor.run_now(j, wait_ms)
  run.refused |> should.equal(40)
  run.refused_dropped |> should.equal(8)
  list.length(receipt_of(run).refused)
  |> should.equal(janitor.refused_detail_limit)
  // the recorded history carries the same bounded run
  let assert Some(last) = snap(j).last
  last.refused_dropped |> should.equal(8)
  list.length(receipt_of(last).refused) |> should.equal(32)
  janitor.stop(j) |> should.be_true
}

pub fn validate_refuses_an_unusable_orphan_grace_test() {
  use root, key <- with_env
  let ok = config(root, key, 1000, 1, 1)
  janitor.validate(janitor.Config(..ok, orphan_grace_ms: 999))
  |> result_reason
  |> should.equal("orphan_grace_invalid")
  janitor.validate(janitor.Config(..ok, orphan_grace_ms: 1000))
  |> result.is_ok
  |> should.be_true
}

// --------------------------------------------------- supervision isolation

fn wait_for_new_pid(name: Name(a), old: Pid, attempts: Int) -> Result(Pid, Nil) {
  case process.named(name) {
    Ok(pid) if pid != old -> Ok(pid)
    _ ->
      case attempts <= 0 {
        True -> Error(Nil)
        False -> {
          process.sleep(10)
          wait_for_new_pid(name, old, attempts - 1)
        }
      }
  }
}

/// Kill the named process and wait for its replacement.
fn kill_and_wait(name: Name(a)) -> Nil {
  let assert Ok(old) = process.named(name)
  process.kill(old)
  let assert Ok(_) = wait_for_new_pid(name, old, 200)
  Nil
}

/// A stand-in for the other service children.
fn sibling_spec(name: Name(String)) -> supervision.ChildSpecification(_) {
  supervision.worker(fn() {
    actor.new(Nil)
    |> actor.on_message(fn(state, _message: String) { actor.continue(state) })
    |> actor.named(name)
    |> actor.start
  })
}

/// The service supervisor's own shape: RestForOne, three restarts in five
/// seconds, the other children before the janitor.
fn service_like(
  sibling: Name(String),
  janitor_spec: supervision.ChildSpecification(_),
) -> sup.Builder {
  sup.new(sup.RestForOne)
  |> sup.restart_tolerance(intensity: 3, period: 5)
  |> sup.add(sibling_spec(sibling))
  |> sup.add(janitor_spec)
}

pub fn janitor_crash_loop_leaves_the_service_supervisor_and_siblings_alive_test() {
  use root, key <- with_env
  let name = process.new_name("telegram_media_janitor_iso_" <> unique())
  let sibling = process.new_name("telegram_media_sibling_iso_" <> unique())
  let cfg = config(root, key, 600_000, 5, 8)
  let assert Ok(service) =
    service_like(sibling, janitor.isolated_child_spec_named(name, cfg))
    |> sup.start
  let assert Ok(sibling_pid) = process.named(sibling)
  // four kills inside five seconds: more than the service tolerance of three
  list.each([1, 2, 3, 4], fn(_) { kill_and_wait(name) })
  process.is_alive(service.pid) |> should.be_true
  process.named(sibling) |> should.equal(Ok(sibling_pid))
  // and the janitor is serving again under the same name
  let j = process.named_subject(name)
  let assert Ok(run) = janitor.run_now(j, wait_ms)
  run.outcome |> result.is_ok |> should.be_true
}

pub fn the_same_crash_loop_without_isolation_exhausts_the_service_test() {
  use root, key <- with_env
  process.trap_exits(True)
  let name = process.new_name("telegram_media_janitor_direct_" <> unique())
  let sibling = process.new_name("telegram_media_sibling_direct_" <> unique())
  let cfg = config(root, key, 600_000, 5, 8)
  let assert Ok(service) =
    service_like(sibling, janitor.child_spec_named(name, cfg)) |> sup.start
  // the control: this is the defect M2-03 fixes
  list.each([1, 2, 3], fn(_) { kill_and_wait(name) })
  let assert Ok(old) = process.named(name)
  process.kill(old)
  process.sleep(300)
  process.is_alive(service.pid) |> should.be_false
}

pub fn stop_is_a_normal_exit_that_nothing_restarts_test() {
  use root, key <- with_env
  let name = process.new_name("telegram_media_janitor_stop_" <> unique())
  let sibling = process.new_name("telegram_media_sibling_stop_" <> unique())
  let cfg = config(root, key, 600_000, 5, 8)
  let assert Ok(service) =
    service_like(sibling, janitor.isolated_child_spec_named(name, cfg))
    |> sup.start
  let assert Ok(sibling_pid) = process.named(sibling)
  let j = process.named_subject(name)
  janitor.stop(j) |> should.be_true
  process.sleep(300)
  process.named(name) |> should.equal(Error(Nil))
  process.is_alive(service.pid) |> should.be_true
  process.named(sibling) |> should.equal(Ok(sibling_pid))
}

pub fn a_direct_child_spec_does_not_restart_after_stop_test() {
  use root, key <- with_env
  let name = process.new_name("telegram_media_janitor_tstop_" <> unique())
  let cfg = config(root, key, 600_000, 5, 8)
  let assert Ok(_) =
    sup.new(sup.OneForOne)
    |> sup.add(janitor.child_spec_named(name, cfg))
    |> sup.start
  janitor.stop(process.named_subject(name)) |> should.be_true
  process.sleep(300)
  process.named(name) |> should.equal(Error(Nil))
}
