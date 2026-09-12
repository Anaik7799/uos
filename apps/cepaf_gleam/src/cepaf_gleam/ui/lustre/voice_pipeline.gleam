//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/ui/lustre/voice_pipeline</module></identity>
////   <fractal-topology><layer>L4_SYSTEM</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-OPENCLAW-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Lustre page: 5-tier voice cascade status.

import gleam/option.{type Option, None, Some}

pub type VoiceTier {
  GeminiLiveWS
  GeminiRest25
  GeminiRest31
  WhisperCpp
  RuleAck
}

pub type VoiceTierStatus {
  VoiceTierStatus(
    tier: VoiceTier,
    name: String,
    latency_ms: Int,
    active: Bool,
    connected: Bool,
  )
}

pub type VoicePipelineModel {
  VoicePipelineModel(
    tiers: List(VoiceTierStatus),
    active_tier: Option(VoiceTier),
    ws_connected: Bool,
    transcription_active: Bool,
    last_transcription: String,
    loading: Bool,
    error: Option(String),
  )
}

pub type VoicePipelineMsg {
  TiersUpdated(List(VoiceTierStatus))
  TranscriptionReceived(String)
  WsStateChanged(Bool)
  RefreshVoice
  ErrorReceived(String)
}

pub fn init() -> VoicePipelineModel {
  VoicePipelineModel(
    tiers: default_voice_tiers(),
    active_tier: None,
    ws_connected: False,
    transcription_active: False,
    last_transcription: "",
    loading: False,
    error: None,
  )
}

pub fn update(model: VoicePipelineModel, msg: VoicePipelineMsg) -> VoicePipelineModel {
  case msg {
    TiersUpdated(tiers) -> VoicePipelineModel(..model, tiers: tiers, loading: False)
    TranscriptionReceived(text) ->
      VoicePipelineModel(..model, last_transcription: text, transcription_active: True)
    WsStateChanged(connected) -> VoicePipelineModel(..model, ws_connected: connected)
    RefreshVoice -> VoicePipelineModel(..model, loading: True)
    ErrorReceived(e) -> VoicePipelineModel(..model, error: Some(e), loading: False)
  }
}

pub fn tier_name(tier: VoiceTier) -> String {
  case tier {
    GeminiLiveWS -> "Gemini Live WS"
    GeminiRest25 -> "Gemini REST 2.5"
    GeminiRest31 -> "Gemini REST 3.1"
    WhisperCpp -> "Whisper.cpp"
    RuleAck -> "Rule Ack"
  }
}

fn default_voice_tiers() -> List(VoiceTierStatus) {
  [
    VoiceTierStatus(GeminiLiveWS, "Gemini Live WS", 250, False, False),
    VoiceTierStatus(GeminiRest25, "Gemini REST 2.5", 900, False, True),
    VoiceTierStatus(GeminiRest31, "Gemini REST 3.1", 1100, False, True),
    VoiceTierStatus(WhisperCpp, "Whisper.cpp (offline)", 2000, False, True),
    VoiceTierStatus(RuleAck, "Rule-based ack", 1, False, True),
  ]
}

// =============================================================================
// NIF-backed data loading (SC-WIRE-001: real ops data)
// =============================================================================

import cepaf_gleam/c3i/nif
import gleam/dynamic/decode
import gleam/json

/// Load real voice pipeline status from NIF → Rust → UserPreferences
pub fn load_from_nif() -> VoicePipelineModel {
  let raw = nif.voice_status()
  let decoder = {
    use ws <- decode.field("ws_connected", decode.bool)
    decode.success(ws)
  }
  let ws = case json.parse(raw, decoder) {
    Ok(w) -> w
    Error(_) -> False
  }
  let model = init()
  VoicePipelineModel(..model, ws_connected: ws, loading: False)
}
