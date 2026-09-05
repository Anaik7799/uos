import cepaf_gleam/ha/health_derivative.{Critical, HealthSample, Stable}
import gleeunit/should

// T01: init creates stable state with zero derivatives
pub fn init_state_test() {
  let d = health_derivative.init(0.9)
  should.equal(d.current, 0.9)
  should.equal(d.velocity, 0.0)
  should.equal(d.acceleration, 0.0)
  should.equal(d.alert, Stable)
}

// T02: init clamps to [0,1]
pub fn init_clamp_test() {
  let d = health_derivative.init(1.5)
  should.equal(d.current, 1.0)
  let d2 = health_derivative.init(-0.5)
  should.equal(d2.current, 0.0)
}

// T03: single sample update — no derivative yet (need 2+ samples)
pub fn single_sample_test() {
  let d =
    health_derivative.init(0.9)
    |> health_derivative.update(HealthSample(timestamp_ms: 1000, value: 0.9))
  should.equal(d.current, 0.9)
  should.equal(d.velocity, 0.0)
  should.equal(d.alert, Stable)
}

// T04: two samples with constant health — velocity ~0
pub fn constant_health_test() {
  let d =
    health_derivative.init(0.9)
    |> health_derivative.update(HealthSample(timestamp_ms: 1000, value: 0.9))
    |> health_derivative.update(HealthSample(timestamp_ms: 2000, value: 0.9))
  should.equal(d.velocity, 0.0)
  should.equal(d.alert, Stable)
}

// T05: two samples with declining health — negative velocity
pub fn declining_health_test() {
  let d =
    health_derivative.init(0.9)
    |> health_derivative.update(HealthSample(timestamp_ms: 1000, value: 0.9))
    |> health_derivative.update(HealthSample(timestamp_ms: 2000, value: 0.8))
  should.be_true(d.velocity <. 0.0)
}

// T06: three samples with linear decline — central difference
pub fn linear_decline_central_test() {
  let d =
    health_derivative.init(0.9)
    |> health_derivative.update(HealthSample(timestamp_ms: 1000, value: 0.9))
    |> health_derivative.update(HealthSample(timestamp_ms: 2000, value: 0.8))
    |> health_derivative.update(HealthSample(timestamp_ms: 3000, value: 0.7))
  should.be_true(d.velocity <. 0.0)
  should.be_true(d.current == 0.7)
}

// T07: predict returns value in [0,1]
pub fn predict_clamped_test() {
  let d = health_derivative.init(0.1)
  let p = health_derivative.predict(d, 1000.0)
  should.be_true(p >=. 0.0)
  should.be_true(p <=. 1.0)
}

// T08: predict with zero derivatives returns current
pub fn predict_stable_test() {
  let d = health_derivative.init(0.8)
  let p = health_derivative.predict(d, 60.0)
  should.equal(p, 0.8)
}

// T09: summary returns non-empty string
pub fn summary_test() {
  let d = health_derivative.init(0.9)
  let s = health_derivative.summary(d)
  should.be_true(s != "")
}

// T10: classify_alert returns correct level
pub fn classify_alert_stable_test() {
  let d = health_derivative.init(0.9)
  let alert = health_derivative.classify_alert(d)
  should.equal(alert, Stable)
}

// T11: ring buffer caps at 10 samples
pub fn ring_buffer_cap_test() {
  let d =
    health_derivative.init(0.9)
    |> health_derivative.update(HealthSample(timestamp_ms: 100, value: 0.9))
    |> health_derivative.update(HealthSample(timestamp_ms: 200, value: 0.9))
    |> health_derivative.update(HealthSample(timestamp_ms: 300, value: 0.9))
    |> health_derivative.update(HealthSample(timestamp_ms: 400, value: 0.9))
    |> health_derivative.update(HealthSample(timestamp_ms: 500, value: 0.9))
    |> health_derivative.update(HealthSample(timestamp_ms: 600, value: 0.9))
    |> health_derivative.update(HealthSample(timestamp_ms: 700, value: 0.9))
    |> health_derivative.update(HealthSample(timestamp_ms: 800, value: 0.9))
    |> health_derivative.update(HealthSample(timestamp_ms: 900, value: 0.9))
    |> health_derivative.update(HealthSample(timestamp_ms: 1000, value: 0.9))
    |> health_derivative.update(HealthSample(timestamp_ms: 1100, value: 0.9))
    |> health_derivative.update(HealthSample(timestamp_ms: 1200, value: 0.9))
  // Should have at most 10 samples despite 12 updates
  should.be_true(list_len(d.samples) <= 10)
}

fn list_len(items: List(a)) -> Int {
  do_len(items, 0)
}

fn do_len(items: List(a), acc: Int) -> Int {
  case items {
    [] -> acc
    [_, ..rest] -> do_len(rest, acc + 1)
  }
}

// T12: critical alert when health below 0.5
pub fn critical_alert_test() {
  let d =
    health_derivative.init(0.4)
    |> health_derivative.update(HealthSample(timestamp_ms: 1000, value: 0.4))
    |> health_derivative.update(HealthSample(timestamp_ms: 2000, value: 0.3))
  should.equal(d.alert, Critical)
}
