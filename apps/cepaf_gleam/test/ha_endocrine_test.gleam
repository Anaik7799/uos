/// Endocrine Tests — EMA hormonal regulation, mood classification, actions
///
/// 22 tests covering: init, sample, regulate, classify_mood, is_elevated,
/// is_critical, elevated_count, health, hormone_to_string, mood_to_string,
/// summary.
///
/// Layer: L5_COGNITIVE
/// STAMP: SC-BIO-EVO-001, SC-FUNC-002
/// समस्थिति — Homeostasis: the system regulates itself (Biomorphic Property 1)
import cepaf_gleam/ha/endocrine.{
  Calm, CpuTrend, ErrorRateEma, GrowthHormone, MemoryPressure, NoRegulation,
  Stressed, classify_mood, elevated_count, health, hormone_to_string, init,
  is_critical, is_elevated, mood_to_string, regulate, sample, summary,
}
import gleam/list
import gleam/string
import gleeunit/should

// ===========================================================================
// 1. init/0
// ===========================================================================

pub fn init_has_seven_hormones_test() {
  init().levels |> list.length() |> should.equal(7)
}

pub fn init_mood_is_calm_test() {
  init().mood |> should.equal(Calm)
}

pub fn init_regulation_events_zero_test() {
  init().regulation_events |> should.equal(0)
}

pub fn init_all_ema_at_half_test() {
  let state = init()
  let all_half =
    state.levels
    |> list.all(fn(lvl) { lvl.ema == 0.5 })
  all_half |> should.be_true()
}

pub fn init_all_sample_counts_zero_test() {
  let state = init()
  let all_zero =
    state.levels
    |> list.all(fn(lvl) { lvl.sample_count == 0 })
  all_zero |> should.be_true()
}

// ===========================================================================
// 2. sample/3 — EMA update
// ===========================================================================

pub fn sample_increases_sample_count_test() {
  let state = init()
  let updated = sample(state, CpuTrend, 0.8)
  let maybe_lvl =
    updated.levels
    |> list.find(fn(l) { l.hormone == CpuTrend })
  case maybe_lvl {
    Ok(lvl) -> lvl.sample_count |> should.equal(1)
    Error(_) -> should.fail()
  }
}

pub fn sample_updates_value_test() {
  let state = init()
  let updated = sample(state, ErrorRateEma, 0.9)
  let maybe_lvl =
    updated.levels
    |> list.find(fn(l) { l.hormone == ErrorRateEma })
  case maybe_lvl {
    Ok(lvl) -> lvl.value |> should.equal(0.9)
    Error(_) -> should.fail()
  }
}

pub fn sample_ema_moves_toward_raw_value_test() {
  // alpha for CpuTrend = 0.1; init ema = 0.5; raw = 1.0
  // new_ema = 0.1 * 1.0 + 0.9 * 0.5 = 0.1 + 0.45 = 0.55
  let state = init()
  let updated = sample(state, CpuTrend, 1.0)
  let maybe_lvl =
    updated.levels
    |> list.find(fn(l) { l.hormone == CpuTrend })
  case maybe_lvl {
    Ok(lvl) -> { lvl.ema >. 0.5 } |> should.be_true()
    Error(_) -> should.fail()
  }
}

pub fn sample_does_not_affect_other_hormones_test() {
  let state = init()
  let updated = sample(state, CpuTrend, 1.0)
  let memory_lvl =
    updated.levels
    |> list.find(fn(l) { l.hormone == MemoryPressure })
  case memory_lvl {
    Ok(lvl) -> lvl.ema |> should.equal(0.5)
    Error(_) -> should.fail()
  }
}

// ===========================================================================
// 3. is_elevated/1 and is_critical/1
// ===========================================================================

pub fn is_elevated_false_at_init_test() {
  let state = init()
  let all_not_elevated =
    state.levels |> list.all(fn(l) { is_elevated(l) == False })
  all_not_elevated |> should.be_true()
}

pub fn is_elevated_true_above_threshold_test() {
  let state = init()
  // Drive CpuTrend EMA above 0.7 with repeated high samples
  let s1 = sample(state, CpuTrend, 1.0)
  let s2 = sample(s1, CpuTrend, 1.0)
  let s3 = sample(s2, CpuTrend, 1.0)
  let s4 = sample(s3, CpuTrend, 1.0)
  let s5 = sample(s4, CpuTrend, 1.0)
  let s6 = sample(s5, CpuTrend, 1.0)
  let s7 = sample(s6, CpuTrend, 1.0)
  let s8 = sample(s7, CpuTrend, 1.0)
  let s9 = sample(s8, CpuTrend, 1.0)
  let s10 = sample(s9, CpuTrend, 1.0)
  let maybe_lvl =
    s10.levels
    |> list.find(fn(l) { l.hormone == CpuTrend })
  case maybe_lvl {
    Ok(lvl) -> is_elevated(lvl) |> should.be_true()
    Error(_) -> should.fail()
  }
}

pub fn is_critical_false_at_init_test() {
  let state = init()
  let all_not_critical =
    state.levels |> list.all(fn(l) { is_critical(l) == False })
  all_not_critical |> should.be_true()
}

// ===========================================================================
// 4. elevated_count/1
// ===========================================================================

pub fn elevated_count_zero_at_init_test() {
  elevated_count(init()) |> should.equal(0)
}

// ===========================================================================
// 5. classify_mood/1
// ===========================================================================

pub fn classify_mood_calm_at_init_test() {
  classify_mood(init()) |> should.equal(Calm)
}

// ===========================================================================
// 6. regulate/1
// ===========================================================================

pub fn regulate_increments_events_test() {
  let state = init()
  let #(new_state, _action) = regulate(state)
  new_state.regulation_events |> should.equal(1)
}

pub fn regulate_no_regulation_when_calm_test() {
  let state = init()
  let #(_new_state, action) = regulate(state)
  action |> should.equal(NoRegulation)
}

// ===========================================================================
// 7. health/1
// ===========================================================================

pub fn health_is_one_when_calm_test() {
  health(init()) |> should.equal(1.0)
}

pub fn health_returns_float_test() {
  let h = health(init())
  { h >=. 0.0 && h <=. 1.0 } |> should.be_true()
}

// ===========================================================================
// 8. hormone_to_string/1
// ===========================================================================

pub fn hormone_to_string_cpu_test() {
  hormone_to_string(CpuTrend) |> should.equal("cpu_trend")
}

pub fn hormone_to_string_error_rate_test() {
  hormone_to_string(ErrorRateEma) |> should.equal("error_rate_ema")
}

pub fn hormone_to_string_growth_test() {
  hormone_to_string(GrowthHormone) |> should.equal("growth_hormone")
}

// ===========================================================================
// 9. mood_to_string/1
// ===========================================================================

pub fn mood_to_string_calm_test() {
  mood_to_string(Calm) |> should.equal("calm")
}

pub fn mood_to_string_stressed_test() {
  mood_to_string(Stressed) |> should.equal("stressed")
}

// ===========================================================================
// 10. summary/1
// ===========================================================================

pub fn summary_contains_endocrine_test() {
  summary(init()) |> string.contains("Endocrine") |> should.be_true()
}

pub fn summary_contains_mood_test() {
  summary(init()) |> string.contains("mood=") |> should.be_true()
}
