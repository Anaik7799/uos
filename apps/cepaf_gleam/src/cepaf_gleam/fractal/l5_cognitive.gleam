//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/fractal/l5_cognitive</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-AGUI-006, SC-OODA-001</stamp-controls></compliance></c3i-module>
////
//// L5 Cognitive: reasoning stream, OODA ring, AI copilot panel.

import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}

/// OODA phase for ring diagram.
pub type OodaPhase {
  Observe
  Orient
  Decide
  Act
  OodaIdle
}

/// OODA cycle state.
pub type OodaCycleState {
  OodaCycleState(
    current_phase: OodaPhase,
    cycle_count: Int,
    last_cycle_ms: Int,
    target_ms: Int,
    pattern: Option(String),
    decision: Option(String),
    history: List(Int),
  )
}

/// Reasoning stream state — visible chain-of-thought.
pub type ReasoningState {
  ReasoningState(
    active: Bool,
    message_id: Option(String),
    content_buffer: String,
    encrypted: Bool,
    chunks_received: Int,
  )
}

/// AI Copilot suggestion.
pub type CopilotSuggestion {
  CopilotSuggestion(
    id: String,
    text: String,
    confidence: Float,
    source: String,
    accepted: Option(Bool),
  )
}

pub fn initial_ooda() -> OodaCycleState {
  OodaCycleState(
    current_phase: OodaIdle,
    cycle_count: 0,
    last_cycle_ms: 0,
    target_ms: 100,
    pattern: None,
    decision: None,
    history: [],
  )
}

pub fn set_ooda_phase(state: OodaCycleState, phase: OodaPhase) -> OodaCycleState {
  OodaCycleState(..state, current_phase: phase)
}

pub fn complete_ooda_cycle(
  state: OodaCycleState,
  duration_ms: Int,
  pattern: String,
  decision: String,
) -> OodaCycleState {
  let new_history = [duration_ms, ..state.history] |> list.take(60)
  OodaCycleState(
    ..state,
    current_phase: OodaIdle,
    cycle_count: state.cycle_count + 1,
    last_cycle_ms: duration_ms,
    pattern: Some(pattern),
    decision: Some(decision),
    history: new_history,
  )
}

pub fn ooda_within_target(state: OodaCycleState) -> Bool {
  state.last_cycle_ms <= state.target_ms
}

pub fn initial_reasoning() -> ReasoningState {
  ReasoningState(
    active: False,
    message_id: None,
    content_buffer: "",
    encrypted: False,
    chunks_received: 0,
  )
}

pub fn start_reasoning(
  _state: ReasoningState,
  message_id: String,
) -> ReasoningState {
  ReasoningState(
    active: True,
    message_id: Some(message_id),
    content_buffer: "",
    encrypted: False,
    chunks_received: 0,
  )
}

pub fn append_reasoning(state: ReasoningState, delta: String) -> ReasoningState {
  ReasoningState(
    ..state,
    content_buffer: state.content_buffer <> delta,
    chunks_received: state.chunks_received + 1,
  )
}

pub fn end_reasoning(state: ReasoningState) -> ReasoningState {
  ReasoningState(..state, active: False)
}

pub fn ooda_phase_to_string(phase: OodaPhase) -> String {
  case phase {
    Observe -> "observe"
    Orient -> "orient"
    Decide -> "decide"
    Act -> "act"
    OodaIdle -> "idle"
  }
}

pub fn ooda_to_json(state: OodaCycleState) -> json.Json {
  json.object([
    #("phase", json.string(ooda_phase_to_string(state.current_phase))),
    #("cycle_count", json.int(state.cycle_count)),
    #("last_cycle_ms", json.int(state.last_cycle_ms)),
    #("target_ms", json.int(state.target_ms)),
    #("within_target", json.bool(ooda_within_target(state))),
  ])
}
