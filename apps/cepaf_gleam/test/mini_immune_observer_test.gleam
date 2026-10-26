import cepaf_gleam/immune/patterns
import cepaf_gleam/immune/system
import cepaf_gleam/telegram/mini_api as api
import cepaf_gleam/telegram/mini_immune_observer as obs
import gleam/dict
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

@external(erlang, "erlang", "monotonic_time")
fn monotonic_time(unit: Atom) -> Int

fn now_ms() -> Int {
  monotonic_time(atom.create("millisecond"))
}

fn snap(targets: List(String)) -> system.SystemSnapshot {
  system.SystemSnapshot(
    active_antibodies: 3,
    violation_count: 7,
    known_patterns: 4,
    antibody_targets: targets,
  )
}

fn fields(o: api.Observation) {
  let assert api.Observed(_, _, f) = o
  f
}

fn field(o: api.Observation, key: String) -> String {
  let assert Ok(v) = dict.get(fields(o), key)
  v
}

pub fn observe_ok_is_observed_with_four_fields_test() {
  let o = obs.observe(1234, Ok(snap(["a", "b"])))
  let assert api.Observed(at, source, _) = o
  at |> should.equal(1234)
  source |> should.equal(obs.source)
  field(o, "Source") |> should.equal("cepaf_gleam/immune/system")
  field(o, "Confidence") |> should.equal("observed")
  field(o, "Active antibodies") |> should.equal("3")
  field(o, "Violations") |> should.equal("7")
  field(o, "Known patterns") |> should.equal("4")
  field(o, "Antibody targets") |> should.equal("a, b")
  { dict.size(fields(o)) <= 24 } |> should.be_true
}

pub fn observe_clips_long_targets_test() {
  let targets = list.repeat(string.repeat("x", 100), 24)
  let o = obs.observe(1, Ok(snap(targets)))
  let v = field(o, "Antibody targets")
  { string.byte_size(v) <= 512 } |> should.be_true
  string.ends_with(v, "...") |> should.be_true
  { dict.size(fields(o)) <= 24 } |> should.be_true
}

pub fn observe_error_is_unavailable_verbatim_test() {
  obs.observe(1, Error("some_reason"))
  |> should.equal(api.Unavailable("some_reason"))
}

pub fn observe_live_none_is_not_running_test() {
  obs.observe_live(1, None, 100)
  |> should.equal(api.Unavailable(obs.not_running_reason))
}

pub fn live_actor_snapshot_is_consistent_test() {
  let assert Ok(actor) = system.start()
  let assert Ok(s) = obs.query(actor, 1000)
  s.violation_count |> should.equal(0)
  s.active_antibodies |> should.equal(0)
  s.known_patterns
  |> should.equal(list.length(patterns.default_patterns()))
  s.antibody_targets |> should.equal([])

  // Benign messages leave the counters unchanged.
  process.send(actor, system.PruneAntibodies)
  process.send(actor, system.ProcessLogLine("nothing to see here"))
  let assert Ok(s2) = obs.query(actor, 1000)
  s2 |> should.equal(s)

  let o = obs.observe_live(55, Some(actor), 1000)
  field(o, "Confidence") |> should.equal("observed")
  field(o, "Violations") |> should.equal("0")
  field(o, "Known patterns")
  |> should.equal(int.to_string(list.length(patterns.default_patterns())))
}

fn dead_subject() -> process.Subject(system.Message) {
  let me = process.new_subject()
  let _ =
    process.spawn_unlinked(fn() {
      let s = process.new_subject()
      process.send(me, s)
    })
  let assert Ok(s) = process.receive(me, 1000)
  // Wait for the owner to exit.
  let assert Ok(pid) = process.subject_owner(s)
  wait_dead(pid, 50)
  s
}

fn wait_dead(pid: process.Pid, tries: Int) -> Nil {
  case process.is_alive(pid), tries {
    False, _ -> Nil
    True, 0 -> Nil
    True, _ -> {
      process.sleep(10)
      wait_dead(pid, tries - 1)
    }
  }
}

pub fn dead_actor_times_out_without_crash_test() {
  let dead = dead_subject()
  obs.query(dead, 500) |> should.equal(Error(obs.timeout_reason))
  obs.observe_live(9, Some(dead), 500)
  |> should.equal(api.Unavailable(obs.timeout_reason))
}

pub fn silent_actor_times_out_within_clamp_test() {
  // A fresh subject owned by this process that nobody serves.
  let silent = process.new_subject()
  let start = now_ms()
  obs.query(silent, 50) |> should.equal(Error(obs.timeout_reason))
  let elapsed = now_ms() - start
  { elapsed >= 40 && elapsed < 1000 } |> should.be_true
}

pub fn timeout_zero_is_clamped_to_one_test() {
  let silent = process.new_subject()
  let start = now_ms()
  obs.query(silent, 0) |> should.equal(Error(obs.timeout_reason))
  obs.query(silent, -5) |> should.equal(Error(obs.timeout_reason))
  { now_ms() - start < 500 } |> should.be_true
}

pub fn timeout_ten_thousand_is_clamped_to_three_thousand_test() {
  let silent = process.new_subject()
  let start = now_ms()
  obs.query(silent, 10_000) |> should.equal(Error(obs.timeout_reason))
  let elapsed = now_ms() - start
  { elapsed >= 2900 && elapsed < 5000 } |> should.be_true
}

pub fn live_actor_reports_violations_and_caps_targets_test() {
  let assert Ok(actor) = system.start()
  process.send(actor, system.ReportViolation("first-reason", "target-a"))
  let assert Ok(one) = obs.query(actor, 1000)
  one.violation_count |> should.equal(1)
  one.active_antibodies |> should.equal(1)
  one.antibody_targets |> should.equal(["first-reason"])
  one.known_patterns
  |> should.equal(list.length(patterns.default_patterns()))

  send_violations(actor, 2, 30)
  let assert Ok(many) = obs.query(actor, 1000)
  many.violation_count |> should.equal(30)
  many.active_antibodies |> should.equal(30)
  list.length(many.antibody_targets) |> should.equal(24)
  // Newest first.
  list.first(many.antibody_targets) |> should.equal(Ok("r30"))

  let o = obs.observe_live(5, Some(actor), 1000)
  field(o, "Violations") |> should.equal("30")
  field(o, "Active antibodies") |> should.equal("30")
  { dict.size(fields(o)) <= 24 } |> should.be_true
}

fn send_violations(
  actor: process.Subject(system.Message),
  from: Int,
  to: Int,
) -> Nil {
  case from > to {
    True -> Nil
    False -> {
      process.send(
        actor,
        system.ReportViolation("r" <> int.to_string(from), "t"),
      )
      send_violations(actor, from + 1, to)
    }
  }
}
