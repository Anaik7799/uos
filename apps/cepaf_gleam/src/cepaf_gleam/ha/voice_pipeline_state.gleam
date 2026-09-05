//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/voice_pipeline_state</module>
////     <fsharp-lineage>None — novel voice pipeline state machine (F17)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L1_ATOMIC_DEBUG</layer>
////     <mesh-domain>
////       Voice activity detection (VAD) state machine for the 5-tier voice
////       cascade. Tracks energy-threshold-based speech detection, emits typed
////       VoiceEvent variants, and maintains per-session statistics. Zero I/O —
////       pure functional state-in / state-out interface.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-OPENCLAW-001, SC-BIO-EVO-005, SC-MUDA-001, SC-FUNC-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       5-tier voice cascade concept ↪ Gleam pure state machine.
////       Energy threshold comparison replaces continuous audio DSP.
////     </morphism>
////     <morphism type="surjective" loss="audio-fidelity">
////       Real PCM energy ↠ Float scalar.
////       Mitigation: Energy is computed upstream by the NIF layer; this module
////       only receives the normalised scalar and applies threshold logic.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// VOICE PIPELINE STATE — F17
//// SC-OPENCLAW-001: 5-tier voice cascade — Gemini Live → REST → Whisper → rules
//// SC-BIO-EVO-005: System MUST respond to stimuli < 1s (nervous system L1)
////
//// Models the VAD (Voice Activity Detection) stage of the voice pipeline.
//// Supports four operating modes with typed event emission:
////   AlwaysOn     — microphone always open, every sample classified
////   PushToTalk   — only active when external gate is set
////   WakeWord     — listens for wake-word trigger before opening gate
////   Disabled     — pipeline off
////
//// STAMP: SC-OPENCLAW-001, SC-BIO-EVO-005, SC-MUDA-001, SC-FUNC-001

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public Types
// ---------------------------------------------------------------------------

/// Operating mode for the voice input pipeline
pub type VoiceMode {
  AlwaysOn
  PushToTalk
  WakeWord
  Disabled
}

/// Result of a Voice Activity Detection check on a single energy sample
pub type VadResult {
  VadResult(speech_detected: Bool, energy: Float, confidence: Float)
}

/// Typed events emitted by the voice pipeline state machine
pub type VoiceEvent {
  /// Wake-word recognised — transitions to active listening
  WakeWordDetected
  /// First speech frame above threshold
  SpeechStart
  /// Speech segment ended — carries the recognised text (or empty)
  SpeechEnd(text: String)
  /// Silence duration in milliseconds
  Silence(duration_ms: Int)
}

/// Mutable-style state record for the voice pipeline.
/// Updated via pure functional transitions (state-in / state-out).
pub type VoiceState {
  VoiceState(
    active: Bool,
    mode: VoiceMode,
    session_id: String,
    energy_threshold: Float,
    samples_processed: Int,
    events: List(VoiceEvent),
  )
}

// ---------------------------------------------------------------------------
// Constructors
// ---------------------------------------------------------------------------

/// Create a fresh VoiceState for the given mode.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">VoiceMode ADT ↪ zeroed VoiceState</morphism>
///   <formal-proof>
///     <P> mode is a valid VoiceMode variant </P>
///     <C> voice_new(mode) </C>
///     <Q> VoiceState with active=False, samples_processed=0, events=[] </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn voice_new(mode: VoiceMode) -> VoiceState {
  VoiceState(
    active: False,
    mode: mode,
    session_id: "session-" <> mode_to_string(mode),
    energy_threshold: 0.5,
    samples_processed: 0,
    events: [],
  )
}

// ---------------------------------------------------------------------------
// VAD — Voice Activity Detection
// ---------------------------------------------------------------------------

/// Determine whether speech is present based on energy vs threshold.
///
/// confidence = clamp(energy / (threshold * 2.0), 0.0, 1.0)
/// speech_detected = energy > threshold
pub fn vad_detect(energy: Float, threshold: Float) -> VadResult {
  let speech = energy >. threshold
  let raw_conf = case threshold >. 0.0 {
    True -> energy /. { threshold *. 2.0 }
    False -> 1.0
  }
  let confidence = case raw_conf >. 1.0 {
    True -> 1.0
    False ->
      case raw_conf <. 0.0 {
        True -> 0.0
        False -> raw_conf
      }
  }
  VadResult(speech_detected: speech, energy: energy, confidence: confidence)
}

// ---------------------------------------------------------------------------
// Sample Processing
// ---------------------------------------------------------------------------

/// Process a single energy sample, updating state and emitting events.
///
/// Rules:
///   - Disabled mode:  no state change, no events
///   - PushToTalk:     only active when state.active == True
///   - AlwaysOn/WakeWord: process all samples
///
/// Returns updated state and list of newly emitted events.
pub fn process_sample(
  state: VoiceState,
  energy: Float,
) -> #(VoiceState, List(VoiceEvent)) {
  case state.mode {
    Disabled -> #(state, [])
    PushToTalk ->
      case state.active {
        False -> #(state, [])
        True -> do_process(state, energy)
      }
    AlwaysOn -> do_process(state, energy)
    WakeWord -> do_process(state, energy)
  }
}

fn do_process(
  state: VoiceState,
  energy: Float,
) -> #(VoiceState, List(VoiceEvent)) {
  let vad = vad_detect(energy, state.energy_threshold)
  let new_events = case vad.speech_detected {
    True -> [SpeechStart]
    False -> [Silence(0)]
  }
  let updated =
    VoiceState(
      ..state,
      samples_processed: state.samples_processed + 1,
      events: list.flatten([state.events, new_events]),
    )
  #(updated, new_events)
}

// ---------------------------------------------------------------------------
// Lifecycle Controls
// ---------------------------------------------------------------------------

/// Set the pipeline to active (open gate)
pub fn activate(state: VoiceState) -> VoiceState {
  VoiceState(..state, active: True)
}

/// Set the pipeline to inactive (close gate)
pub fn deactivate(state: VoiceState) -> VoiceState {
  VoiceState(..state, active: False)
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

/// Whether the pipeline is currently active
pub fn is_active(state: VoiceState) -> Bool {
  state.active
}

/// Number of events accumulated in the current session
pub fn event_count(state: VoiceState) -> Int {
  list.length(state.events)
}

/// Health score: 1.0 active, 0.5 inactive-but-enabled, 0.0 Disabled
pub fn voice_health(state: VoiceState) -> Float {
  case state.mode {
    Disabled -> 0.0
    _ ->
      case state.active {
        True -> 1.0
        False -> 0.5
      }
  }
}

/// Human-readable label for a VoiceMode
pub fn mode_to_string(mode: VoiceMode) -> String {
  case mode {
    AlwaysOn -> "always_on"
    PushToTalk -> "push_to_talk"
    WakeWord -> "wake_word"
    Disabled -> "disabled"
  }
}

/// One-line summary of the pipeline state
pub fn summary(state: VoiceState) -> String {
  let status = case state.active {
    True -> "active"
    False -> "inactive"
  }
  let health_str =
    state
    |> voice_health
    |> float.to_string
  string.join(
    [
      "VoicePipeline[",
      mode_to_string(state.mode),
      "] status=",
      status,
      " samples=",
      int.to_string(state.samples_processed),
      " events=",
      int.to_string(event_count(state)),
      " health=",
      health_str,
    ],
    "",
  )
}
