//// Tests for uos_tui/ooda: property, fuzz and branch coverage over the
//// fast OODA loop controller.
//// STAMP id: SC-TUI-W08-001

import gleam/int
import gleam/list
import gleeunit/should
import prng
import uos_swarm/ooda.{
  type Observation, AuditAspects, Bright, Dark, Dim, Emergency, Falling,
  HaltAdmission, Loop, Normal, Observation, RaiseAndon, Repaint, Rising, Stable,
}

fn obs(
  ts: Int,
  frame: Int,
  events: Int,
  failed: Int,
  health: Float,
) -> Observation {
  Observation(
    ts_ms: ts,
    frame_us: frame,
    events: events,
    aspects_failed: failed,
    health: health,
  )
}

pub fn new_defaults_test() {
  let l = ooda.new(0, 0)
  l.window_size |> should.equal(16)
  l.budget_us |> should.equal(100_000)
  l.cycles |> should.equal(0)
  l.overruns |> should.equal(0)
}

pub fn new_custom_test() {
  let l = ooda.new(4, 50_000)
  l.window_size |> should.equal(4)
  l.budget_us |> should.equal(50_000)
}

pub fn window_bounded_property_test() {
  let seeds = prng.seeds(20)
  list.each(seeds, fn(seed) {
    let #(count, seed) = prng.int_between(seed, 1, 500)
    let #(vals, _) = prng.ints(seed, count, -100, 100)
    let loop =
      list.fold(vals, ooda.new(16, 100_000), fn(acc, v) {
        let #(next, _, _, _) = ooda.step(acc, obs(v, v, v, 0, 0.5))
        next
      })
    { list.length(loop.window) <= 16 } |> should.be_true
  })
}

pub fn lyapunov_empty_and_single_test() {
  ooda.lyapunov([]) |> should.equal(0.0)
  ooda.lyapunov([3.0]) |> should.equal(0.0)
}

pub fn lyapunov_converging_test() {
  let l = ooda.lyapunov([1.0, 0.5, 0.0])
  { l <. 0.0 } |> should.be_true
}

pub fn lyapunov_diverging_test() {
  let l = ooda.lyapunov([0.0, 0.5, 1.0])
  { l >. 0.0 } |> should.be_true
}

pub fn lyapunov_constant_test() {
  ooda.lyapunov([0.5, 0.5, 0.5]) |> should.equal(0.0)
}

pub fn orient_dead_band_test() {
  let l =
    Loop(
      window: [obs(0, 0, 0, 0, 0.5), obs(1, 0, 0, 0, 0.505)],
      window_size: 16,
      budget_us: 100_000,
      mode: Dark,
      cycles: 0,
      overruns: 0,
    )
  let #(trend, _) = ooda.orient(l)
  trend |> should.equal(Stable)
}

pub fn orient_rising_test() {
  let l =
    Loop(
      window: [obs(0, 0, 0, 0, 0.1), obs(1, 0, 0, 0, 0.9)],
      window_size: 16,
      budget_us: 100_000,
      mode: Dark,
      cycles: 0,
      overruns: 0,
    )
  let #(trend, _) = ooda.orient(l)
  trend |> should.equal(Rising)
}

pub fn decide_emergency_test() {
  let l = ooda.new(16, 100_000)
  let latest = obs(0, 1000, 0, 4, 0.9)
  let #(mode, actions) = ooda.decide(l, Stable, latest)
  mode |> should.equal(Emergency)
  list.contains(actions, HaltAdmission) |> should.be_true
  list.contains(actions, RaiseAndon) |> should.be_true
  list.contains(actions, Repaint) |> should.be_true
}

pub fn decide_bright_test() {
  let l = ooda.new(16, 100_000)
  let latest = obs(0, 1000, 0, 1, 0.9)
  let #(mode, actions) = ooda.decide(l, Stable, latest)
  mode |> should.equal(Bright)
  list.contains(actions, AuditAspects) |> should.be_true
}

pub fn decide_normal_test() {
  let l = ooda.new(16, 100_000)
  let latest = obs(0, 1000, 0, 0, 0.2)
  let #(mode, _) = ooda.decide(l, Stable, latest)
  mode |> should.equal(Normal)
}

pub fn decide_dim_test() {
  let l = ooda.new(16, 100_000)
  let latest = obs(0, 1000, 0, 0, 0.9)
  let #(mode, _) = ooda.decide(l, Falling, latest)
  mode |> should.equal(Dim)
}

pub fn decide_dark_test() {
  let l = ooda.new(16, 100_000)
  let latest = obs(0, 1000, 0, 0, 0.9)
  let #(mode, actions) = ooda.decide(l, Stable, latest)
  mode |> should.equal(Dark)
  list.contains(actions, Repaint) |> should.be_true
}

pub fn decide_raises_andon_on_overrun_test() {
  let l = ooda.new(16, 100)
  let latest = obs(0, 1000, 0, 0, 0.9)
  let #(mode, actions) = ooda.decide(l, Stable, latest)
  mode |> should.equal(Dark)
  list.contains(actions, RaiseAndon) |> should.be_true
}

pub fn step_within_budget_test() {
  let l = ooda.new(16, 100_000)
  let #(next, _mode, _actions, within) = ooda.step(l, obs(0, 500, 1, 0, 0.9))
  within |> should.be_true
  next.cycles |> should.equal(1)
  next.overruns |> should.equal(0)
}

pub fn step_over_budget_test() {
  let l = ooda.new(16, 100)
  let #(next, _mode, actions, within) = ooda.step(l, obs(0, 5000, 1, 0, 0.9))
  within |> should.be_false
  next.overruns |> should.equal(1)
  list.contains(actions, RaiseAndon) |> should.be_true
}

pub fn stats_ratio_test() {
  let l = ooda.new(16, 10)
  let #(l, _, _, _) = ooda.step(l, obs(0, 5, 0, 0, 0.9))
  let #(l, _, _, _) = ooda.step(l, obs(1, 50, 0, 0, 0.9))
  let #(cycles, overruns, ratio) = ooda.stats(l)
  cycles |> should.equal(2)
  overruns |> should.equal(1)
  ratio |> should.equal(0.5)
}

pub fn stats_no_cycles_test() {
  let l = ooda.new(16, 100_000)
  ooda.stats(l) |> should.equal(#(0, 0, 0.0))
}

pub fn mode_label_test() {
  ooda.mode_label(Dark) |> should.equal("DARK")
  ooda.mode_label(Dim) |> should.equal("DIM")
  ooda.mode_label(Normal) |> should.equal("NORMAL")
  ooda.mode_label(Bright) |> should.equal("BRIGHT")
  ooda.mode_label(Emergency) |> should.equal("EMERGENCY")
}

pub fn fuzz_step_never_crashes_test() {
  let seeds = prng.seeds(50)
  list.each(seeds, fn(seed) {
    let #(ts, seed) = prng.int_between(seed, -1_000_000, 1_000_000)
    let #(frame, seed) = prng.int_between(seed, -1_000_000, 1_000_000)
    let #(events, seed) = prng.int_between(seed, -1000, 1000)
    let #(failed, seed) = prng.int_between(seed, -10, 10)
    let #(health_i, _) = prng.int_between(seed, -200, 200)
    let health = int.to_float(health_i) /. 100.0
    let l = ooda.new(8, 50_000)
    let #(next, mode, _actions, _within) =
      ooda.step(l, obs(ts, frame, events, failed, health))
    { next.cycles == 1 } |> should.be_true
    { list.length(next.window) <= 8 } |> should.be_true
    case list.first(next.window) {
      Ok(o) -> {
        { o.health >=. 0.0 } |> should.be_true
        { o.health <=. 1.0 } |> should.be_true
      }
      Error(_) -> should.fail()
    }
    let _ = mode
    Nil
  })
}
