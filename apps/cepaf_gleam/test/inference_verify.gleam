import cepaf_gleam/moz/client as moz
import gleam/io
import gleam/json

pub fn main() {
  let moz_state = moz.new()

  io.println("--- PHASE 1: COGNITIVE REASONING (GLEAM) ---")
  io.println("  [intent] Requesting Gemma Analysis for Workspace conflicts...")

  let prompt =
    "Analyze my last 3 unread emails and 2 calendar events for P0 priority conflicts."
  let params =
    json.object([
      #("prompt", json.string(prompt)),
      #("model", json.string("gemma2")),
    ])

  io.println("\n--- PHASE 2: INDRAJAAL TRANSPORT (ZENOH) ---")
  let #(_new_state, result) =
    moz.send_request(moz_state, "plan", "inference_generate", params)

  case result {
    Ok(req_id) -> {
      io.println("  [ok] Inference intent dispatched: " <> req_id)
      io.println("\n--- PHASE 3: MOJO-BRIDGE HANDSHAKE (RUST) ---")
      io.println("  [target] http://intelitor-mojo:11434/api/generate")
    }
    Error(e) -> io.println("  [!] Dispatch failed: " <> e)
  }
}
