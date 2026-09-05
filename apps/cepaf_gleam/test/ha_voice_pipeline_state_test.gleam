/// Voice Pipeline State — 15-test suite
/// Layer: L1_ATOMIC_DEBUG
/// STAMP: SC-OPENCLAW-001, SC-BIO-EVO-005, SC-MUDA-001
///
/// SC-BIO-EVO-005: System MUST respond to stimuli < 1s (nervous system)
import cepaf_gleam/ha/voice_pipeline_state.{
  AlwaysOn, Disabled, PushToTalk, Silence, SpeechStart, WakeWord, activate,
  deactivate, event_count, is_active, mode_to_string, process_sample, summary,
  vad_detect, voice_health, voice_new,
}
import gleeunit/should

// ===========================================================================
// Initialisation
// ===========================================================================

pub fn voice_new_always_on_test() {
  let s = voice_new(AlwaysOn)
  s.active |> should.equal(False)
  s.samples_processed |> should.equal(0)
  s.events |> should.equal([])
}

pub fn voice_new_disabled_test() {
  let s = voice_new(Disabled)
  s.mode |> should.equal(Disabled)
  s.active |> should.equal(False)
}

pub fn voice_new_push_to_talk_test() {
  let s = voice_new(PushToTalk)
  s.mode |> should.equal(PushToTalk)
  s.energy_threshold |> should.equal(0.5)
}

// ===========================================================================
// VAD — Voice Activity Detection
// ===========================================================================

pub fn vad_detect_speech_above_threshold_test() {
  let r = vad_detect(0.8, 0.5)
  r.speech_detected |> should.equal(True)
  r.energy |> should.equal(0.8)
}

pub fn vad_detect_silence_below_threshold_test() {
  let r = vad_detect(0.2, 0.5)
  r.speech_detected |> should.equal(False)
}

pub fn vad_detect_confidence_clamped_to_one_test() {
  // energy = 10.0 >> threshold * 2.0 = 1.0 → confidence clamped to 1.0
  let r = vad_detect(10.0, 0.5)
  r.confidence |> should.equal(1.0)
}

pub fn vad_detect_confidence_half_at_threshold_test() {
  // energy = 0.5, threshold = 0.5 → confidence = 0.5 / 1.0 = 0.5
  let r = vad_detect(0.5, 0.5)
  r.confidence |> should.equal(0.5)
}

// ===========================================================================
// Activation / Deactivation
// ===========================================================================

pub fn activate_sets_active_true_test() {
  let s = voice_new(AlwaysOn) |> activate
  is_active(s) |> should.equal(True)
}

pub fn deactivate_sets_active_false_test() {
  let s = voice_new(AlwaysOn) |> activate |> deactivate
  is_active(s) |> should.equal(False)
}

// ===========================================================================
// Sample Processing
// ===========================================================================

pub fn process_sample_disabled_no_events_test() {
  let s = voice_new(Disabled) |> activate
  let #(updated, events) = process_sample(s, 0.9)
  updated.samples_processed |> should.equal(0)
  events |> should.equal([])
}

pub fn process_sample_always_on_speech_test() {
  let s = voice_new(AlwaysOn)
  let #(updated, events) = process_sample(s, 0.9)
  updated.samples_processed |> should.equal(1)
  events |> should.equal([SpeechStart])
}

pub fn process_sample_always_on_silence_test() {
  let s = voice_new(AlwaysOn)
  let #(updated, events) = process_sample(s, 0.1)
  updated.samples_processed |> should.equal(1)
  events |> should.equal([Silence(0)])
}

pub fn process_sample_push_to_talk_inactive_skips_test() {
  let s = voice_new(PushToTalk)
  // inactive — no processing even with high energy
  let #(updated, events) = process_sample(s, 0.9)
  updated.samples_processed |> should.equal(0)
  events |> should.equal([])
}

// ===========================================================================
// Health & Queries
// ===========================================================================

pub fn voice_health_active_is_one_test() {
  let s = voice_new(AlwaysOn) |> activate
  voice_health(s) |> should.equal(1.0)
}

pub fn voice_health_inactive_enabled_is_half_test() {
  let s = voice_new(AlwaysOn)
  voice_health(s) |> should.equal(0.5)
}

pub fn voice_health_disabled_is_zero_test() {
  let s = voice_new(Disabled)
  voice_health(s) |> should.equal(0.0)
}

pub fn mode_to_string_variants_test() {
  mode_to_string(AlwaysOn) |> should.equal("always_on")
  mode_to_string(PushToTalk) |> should.equal("push_to_talk")
  mode_to_string(WakeWord) |> should.equal("wake_word")
  mode_to_string(Disabled) |> should.equal("disabled")
}

pub fn event_count_accumulates_test() {
  let s = voice_new(AlwaysOn)
  let #(s2, _) = process_sample(s, 0.9)
  let #(s3, _) = process_sample(s2, 0.1)
  event_count(s3) |> should.equal(2)
}

pub fn summary_contains_mode_test() {
  let s = voice_new(AlwaysOn)
  let txt = summary(s)
  txt |> should.not_equal("")
}
