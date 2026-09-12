// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-OPENCLAW-001
import cepaf_gleam/ui/lustre/voice_pipeline.{type VoicePipelineModel, type VoiceTierStatus}
import gleam/json

pub fn status_json(model: VoicePipelineModel) -> json.Json {
  json.object([
    #("ws_connected", json.bool(model.ws_connected)),
    #("transcription_active", json.bool(model.transcription_active)),
    #("last_transcription", json.string(model.last_transcription)),
    #("tiers", json.array(model.tiers, tier_json)),
  ])
}

fn tier_json(t: VoiceTierStatus) -> json.Json {
  json.object([
    #("name", json.string(t.name)),
    #("latency_ms", json.int(t.latency_ms)),
    #("active", json.bool(t.active)),
    #("connected", json.bool(t.connected)),
  ])
}
