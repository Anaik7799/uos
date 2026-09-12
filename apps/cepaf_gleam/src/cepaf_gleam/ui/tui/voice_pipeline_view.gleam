// STAMP: SC-GLM-UI-001, SC-OPENCLAW-001
import cepaf_gleam/ui/lustre/voice_pipeline.{type VoicePipelineModel, type VoiceTierStatus}
import gleam/list
import gleam/string

pub fn render(model: VoicePipelineModel) -> String {
  let ws = case model.ws_connected {
    True -> "\u{001b}[32mCONNECTED\u{001b}[0m"
    False -> "\u{001b}[31mDISCONNECTED\u{001b}[0m"
  }
  let header = "\u{001b}[1;36m▌ Voice Pipeline\u{001b}[0m  WebSocket: " <> ws
  let tiers = list.map(model.tiers, render_tier) |> string.join("\n")
  let transcript = case model.last_transcription {
    "" -> "  (no transcription)"
    t -> "  Last: " <> t
  }
  string.join([header, "", tiers, "", transcript], "\n")
}

fn render_tier(t: VoiceTierStatus) -> String {
  let status = case t.active {
    True -> "\u{001b}[1;32m→\u{001b}[0m"
    False -> " "
  }
  let conn = case t.connected {
    True -> "\u{001b}[32mOK\u{001b}[0m"
    False -> "\u{001b}[31m--\u{001b}[0m"
  }
  status <> " " <> pad(t.name, 24) <> pad(int_str(t.latency_ms) <> "ms", 8) <> conn
}

fn pad(s: String, w: Int) -> String {
  let l = string.length(s)
  case l >= w {
    True -> s
    False -> s <> string.repeat(" ", w - l)
  }
}

@external(erlang, "erlang", "integer_to_binary")
fn int_str(i: Int) -> String
