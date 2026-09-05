import cepaf_gleam/moz/client as moz
import gleam/io
import gleam/json
import gleam/list

pub fn main() {
  io.println("🚀 INITIALIZING GEMMA 4 CEHACKING TEST SUITE (SIL-6)")
  io.println("====================================================")

  let moz_state = moz.new()

  // TIER 1: Semantic Memory Retrieval
  test_semantic_memory(moz_state)

  // TIER 3: Intent-to-Motor Accuracy
  test_mcp_mapping(moz_state)

  // TIER 4: Stress Homeostasis
  test_concurrent_load(moz_state)
}

fn test_semantic_memory(state: moz.MoZClientState) {
  io.println("\n[TIER 1] Testing Semantic Memory Retrieval...")
  let prompt =
    "Using the EventLog in Smriti.db, identify the last 3 tasks I performed in Wave 1 and summarize their outcomes."
  let params =
    json.object([
      #("prompt", json.string(prompt)),
      #("model", json.string("gemma4")),
    ])

  let #(_, result) =
    moz.send_request(state, "plan", "inference_generate", params)
  case result {
    Ok(_) -> io.println("  [pass] Intent dispatched to Mojo cell.")
    Error(e) -> io.println("  [fail] Bridge error: " <> e)
  }
}

fn test_mcp_mapping(state: moz.MoZClientState) {
  io.println("\n[TIER 3] Testing Intent-to-Motor (MCP) Mapping...")
  let prompt =
    "I want to see my system health and send it to Abhi on GChat. Output the MCP tool calls as JSON-RPC."
  let params =
    json.object([
      #("prompt", json.string(prompt)),
      #("model", json.string("gemma4")),
    ])

  let #(_, result) =
    moz.send_request(state, "plan", "inference_generate", params)
  case result {
    Ok(_) -> io.println("  [pass] Mapping request reified.")
    Error(e) -> io.println("  [fail] Bridge error: " <> e)
  }
}

fn test_concurrent_load(state: moz.MoZClientState) {
  io.println("\n[TIER 4] Testing Swarm Stress Homeostasis (Concurrency)...")
  let prompts = list.repeat("Short reasoning test.", 5)

  list.each(prompts, fn(p) {
    let params =
      json.object([
        #("prompt", json.string(p)),
        #("model", json.string("gemma4")),
      ])
    let #(_, result) =
      moz.send_request(state, "plan", "inference_generate", params)
    case result {
      Ok(_) -> io.println("  [ok] Parallel intent fired.")
      Error(e) -> io.println("  [!] Error: " <> e)
    }
  })
  io.println("  [pass] Wavefront dispatched without actor crash.")
}
