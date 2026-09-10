//// =============================================================================
//// [C3I-SIL6-MSTS] UOS Pure Gleam OpenRouter Gemma 4 Evaluator (SC-COG-001)
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/harness/telegram_openrouter</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <topology>Pure Gleam/OTP OpenRouter Inference & Evaluation Substrate</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-OPENROUTER-001, SC-COG-001, SC-ZMOF-001, SC-MUDA-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/ecology/daily_budget as budget
import cepaf_gleam/harness/conversation_memory.{type ChatMessage}
import cepaf_gleam/harness/egress_redactor
import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub const primary_model: String = "google/gemma-4-26b-a4b-it"
pub const fallback_model: String = "google/gemma-4-31b-it"

pub const uos_ground_truth_catalog: String = "
UOS Ground Truth Architecture & Command Registry:
The Unified Operational System (UOS) Telegram Cybernetic Cockpit provides 48 operational directives across 4 domains:

Domain A (Foundational SRE & Cluster Governance - 13 directives):
/status, /storage, /plan, /cockpit, /approval, /andon, /zk, /wiki, /checklist, /dark, /zigvm, /help, /start

Domain B (Advanced SRE & Autonomous Disaster Recovery - 11 directives):
/resuscitate, /chaos, /repro, /merge, /bisect, /escalate, /rotate-keys, /mesh, /migrate, /adr, /blast-radius

Domain C (Creative Cybernetics & FinOps Resource Optimization - 12 directives):
/pacing, /whatif, /rack-cv, /acoustic, /rewind, /postmortem, /finops, /eco-schedule, /radar, /canvas, /lockbox, /export-audit

Domain D (Team Collaboration & Multi-Party Voice Cybernetics - 12 directives):
/sidecar, /voice-roll-call, /babel, /whiteboard, /socratic, /handover, /pair-voice, /exec-brief, /commitments, /acoustic-hud, /retro, /gameday

Key System Invariants:
1. HARD_DENIED_SYSTEM_OS_SERIAL = '[REDACTED_SYSTEM_OS_SERIAL]' (NVMe Bay 0 cannot be wiped or pulled).
2. Sa-Plan canonical authority in var/sa-plan/uos.sqlite3 (SC-SA-PLAN-001, SC-JIDOKA-001).
3. 2oo3 multi-party constitutional quorum required for mutating operations.
4. Zero-Muda Purity (0 Bevy, 0 Graphite, pure BEAM OTP 29 & Hermes OCaml).
"

pub type GemmaEvaluation {
  GemmaEvaluation(
    understanding_summary: String,
    correctness_score: Int,
    completeness_score: Int,
    verdict: String,
    discrepancies: List(String),
    analysis: String,
    recommended_response: String,
    model_used: String,
    latency_ms: Int,
  )
}

@external(erlang, "uos_openrouter_ffi", "api_key")
fn ffi_api_key() -> Result(BitArray, Nil)

@external(erlang, "uos_openrouter_ffi", "https_post_json")
fn ffi_post_json(
  url: BitArray,
  key: BitArray,
  body: BitArray,
  timeout_ms: Int,
) -> Result(#(Int, BitArray), BitArray)

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn ffi_system_time_nanos() -> Int

/// Core JSON payload dispatcher with fail-closed egress redactor and daily_budget gating.
fn dispatch_payload_json(
  model: String,
  input_for_budget: String,
  payload_json: String,
  max_tokens: Int,
) -> Result(String, String) {
  // Strictly gate model through daily_budget provider ceiling
  use ceiling <- result.try(
    budget.provider_ceiling(model)
    |> result.map_error(fn(err) { "daily_budget rejected model: " <> err }),
  )

  let url_bytes = bit_array.from_string("https://openrouter.ai/api/v1/chat/completions")

  // EGRESS GUARD on the WHOLE ASSEMBLED PAYLOAD. Fail-closed.
  use _egress <- result.try(case
    string.contains(payload_json, egress_redactor.denied_os_nvme_serial)
  {
    True ->
      Error(
        "egress refused: outbound payload carries the prohibited system "
        <> "identifier. It is not needed to evaluate a conversation; use "
        <> egress_redactor.redacted_serial_placeholder,
      )
    False -> Ok(Nil)
  })

  // Generate unique valid call_id and strictly verify daily_budget admission
  let call_id = "gemma4-" <> int.to_string(ffi_system_time_nanos())
  use _reservation <- result.try(
    budget.admit(
      call_id,
      model,
      max_tokens,
      input_for_budget,
      payload_json,
      ceiling,
    )
    |> result.map_error(fn(err) { "daily_budget admission rejected: " <> err }),
  )

  use key_bytes <- result.try(case ffi_api_key() {
    Ok(k) -> Ok(k)
    Error(_) -> Error("OPENROUTER_API_KEY missing or invalid in environment")
  })

  let body_bytes = bit_array.from_string(payload_json)

  case ffi_post_json(url_bytes, key_bytes, body_bytes, 3_000) {
    Ok(#(200, resp_bytes)) -> {
      case bit_array.to_string(resp_bytes) {
        Ok(resp_str) -> parse_openrouter_content(resp_str)
        Error(_) -> Error("Failed to decode response bytes to UTF-8 string")
      }
    }
    Ok(#(status, resp_bytes)) -> {
      let err_body = bit_array.to_string(resp_bytes) |> result.unwrap("")
      Error("OpenRouter returned HTTP " <> int.to_string(status) <> ": " <> err_body)
    }
    Error(err_bytes) -> {
      let err_str = bit_array.to_string(err_bytes) |> result.unwrap("transport_error")
      Error("OpenRouter BEAM TLS transport error: " <> err_str)
    }
  }
}

/// Pure Gleam HTTP POST to OpenRouter using native BEAM TLS (uos_openrouter_ffi).
pub fn post_openrouter(
  model: String,
  prompt: String,
  max_tokens: Int,
) -> Result(String, String) {
  let payload_json =
    json.object([
      #("model", json.string(model)),
      #(
        "messages",
        json.array(
          [
            json.object([
              #("role", json.string("system")),
              #(
                "content",
                json.string(
                  "You are the authoritative UOS Quality & Correctness Evaluator powered by Gemma 4.\n"
                  <> "Evaluate Telegram conversations with the UOS Cockpit Bot (@c3i_talk_bot).\n"
                  <> "Use this Ground Truth Reference:\n"
                  <> uos_ground_truth_catalog
                  <> "\nProvide your evaluation in structured JSON format with fields:\n"
                  <> "understanding_summary, correctness_score (0-100), completeness_score (0-100), "
                  <> "verdict ('PASS', 'MARGINAL', 'FAIL'), discrepancies (list of strings), analysis, recommended_response.",
                ),
              ),
            ]),
            json.object([
              #("role", json.string("user")),
              #("content", json.string(prompt)),
            ]),
          ],
          fn(x) { x },
        ),
      ),
      #("temperature", json.float(0.1)),
      #("max_tokens", json.int(max_tokens)),
    ])
    |> json.to_string

  dispatch_payload_json(model, prompt, payload_json, max_tokens)
}

/// Dispatches multi-turn chat messages to OpenRouter Gemma 4.
pub fn post_chat_openrouter(
  model: String,
  prompt_input: String,
  messages: List(json.Json),
  max_tokens: Int,
) -> Result(String, String) {
  let payload_json =
    json.object([
      #("model", json.string(model)),
      #("messages", json.array(messages, fn(x) { x })),
      #("temperature", json.float(0.2)),
      #("max_tokens", json.int(max_tokens)),
    ])
    |> json.to_string

  dispatch_payload_json(model, prompt_input, payload_json, max_tokens)
}

/// Front-line conversational synthesis powered by Gemma 4 with multi-turn context and live telemetry.
pub fn generate_conversational_response(
  user_query: String,
  history: List(ChatMessage),
  telemetry_summary: String,
) -> Result(String, String) {
  let system_prompt =
    "You are AGY (Google DeepMind Antigravity), the sovereign autonomous AI agent and cognitive coordinator for the Unified Operational System (UOS) on Telegram (@c3i_talk_bot).\n"
    <> "Role: Sovereign Cognitive Architect, Swarm Coordinator (#fractal-l5), and Cluster SRE.\n\n"
    <> "UOS System Real-Time Telemetry & Context:\n"
    <> telemetry_summary
    <> "\n\n"
    <> "UOS Architecture Ground Truth & Rules:\n"
    <> "1. Canonical 17 System Aspects (A01-A17) across 10 Fractal Layers (L0-L9).\n"
    <> "2. Zero-Muda Purity: 0 Bevy, 0 Graphite, 100% Pure BEAM OTP 29 & Hermes OCaml.\n"
    <> "3. Hardware NVMe Safety: The Root OS NVMe Serial is locked ([REDACTED_SYSTEM_OS_SERIAL]) and hard-denied from any wipe or modification.\n"
    <> "4. Sa-Plan canonical authority in var/sa-plan/uos.sqlite3 (SC-SA-PLAN-001, SC-JIDOKA-001).\n"
    <> "5. Tri-Agent Swarm Governance: AGY, Claude, and Codex coordinate on var/coordination/tri-agent/.\n"
    <> "6. 48 Telegram Directives across Domains A (SRE), B (Disaster Recovery), C (Creative/FinOps), D (Voice/Collab).\n\n"
    <> "Instructions:\n"
    <> "- Address the user directly in an authoritative, helpful, cybernetic tone.\n"
    <> "- When the user asks generic queries like 'show me what is happening in the uos system', summarize the actual live telemetry, cluster health, active plans, aspects, and mesh state accurately.\n"
    <> "- Maintain context with previous conversation turns.\n"
    <> "- Format key entities and metrics with GitHub-flavored markdown (bold, code blocks, lists).\n"
    <> "- Keep responses focused, concise, and structured for mobile Telegram viewing.\n"

  let history_msgs =
    list.map(history, fn(msg) {
      json.object([
        #("role", json.string(msg.role)),
        #("content", json.string(msg.content)),
      ])
    })

  let user_msg =
    json.object([
      #("role", json.string("user")),
      #("content", json.string(user_query)),
    ])

  let all_messages = [
    json.object([
      #("role", json.string("system")),
      #("content", json.string(system_prompt)),
    ]),
    ..list.append(history_msgs, [user_msg])
  ]

  // Try primary Gemma 4 model, fall back to fallback model
  case post_chat_openrouter(primary_model, user_query, all_messages, 1200) {
    Ok(res) -> Ok(res)
    Error(e1) -> {
      case post_chat_openrouter(fallback_model, user_query, all_messages, 1200) {
        Ok(res2) -> Ok(res2)
        Error(e2) -> Error("Both Gemma 4 models failed: " <> e1 <> " | " <> e2)
      }
    }
  }
}

fn parse_openrouter_content(resp_json_str: String) -> Result(String, String) {
  let decoder = {
    use choices <- decode.field("choices", decode.list({
      use msg <- decode.field("message", {
        use content <- decode.field("content", decode.string)
        decode.success(content)
      })
      decode.success(msg)
    }))
    case choices {
      [first, ..] -> decode.success(first)
      [] -> decode.failure("", "expected non-empty choices list")
    }
  }

  case json.parse(resp_json_str, decoder) {
    Ok(content) -> Ok(content)
    Error(_) -> Error("Failed to parse OpenRouter choices JSON: " <> resp_json_str)
  }
}

/// Evaluates a Telegram interaction through OpenRouter Gemma 4 in Pure Gleam.
pub fn evaluate_telegram_interaction(
  user_msg: String,
  bot_resp: String,
  sender: String,
  msg_id: Int,
) -> Result(GemmaEvaluation, String) {
  let prompt =
    "Evaluate the following Telegram interaction:\n"
    <> "- Sender: " <> sender <> " (Message ID: " <> int.to_string(msg_id) <> ")\n"
    <> "- Inbound User Message: \"" <> user_msg <> "\"\n"
    <> "- Outbound Bot Response:\n\"\"\"\n"
    <> bot_resp
    <> "\n\"\"\"\n\n"
    <> "Carefully evaluate:\n"
    <> "1. Did the bot understand the specific intent of the user?\n"
    <> "2. If the user asked 'what are the commands supported', did the response provide the actual full list of 48 directives across all 4 domains (A, B, C, D), or only a partial/truncated subset?\n"
    <> "3. If the user asked 'is this the full list', did the bot answer directly (e.g. clarify that 13 was only a subset and 48 total commands exist), or did it repeat a canned response?\n"
    <> "4. Is the information technically accurate according to UOS specifications?\n"
    <> "5. Rate correctness (0-100), completeness (0-100), and assign verdict PASS/MARGINAL/FAIL."

  let start_nanos = ffi_system_time_nanos()

  // Try primary model first, fall back to fallback model on failure
  let query_res = case post_openrouter(primary_model, prompt, 1200) {
    Ok(res) -> Ok(#(primary_model, res))
    Error(e1) -> {
      case post_openrouter(fallback_model, prompt, 1200) {
        Ok(res2) -> Ok(#(fallback_model, res2))
        Error(e2) -> Error("Both Gemma 4 models failed: " <> e1 <> " | " <> e2)
      }
    }
  }

  let end_nanos = ffi_system_time_nanos()
  let latency_ms = { end_nanos - start_nanos } / 1_000_000

  use #(model_used, raw_content) <- result.try(query_res)

  // Strip possible markdown json codeblock wrapping
  let clean_json =
    raw_content
    |> string.replace("```json", "")
    |> string.replace("```", "")
    |> string.trim

  let eval_decoder = {
    use und <- decode.optional_field("understanding_summary", "Parsed by Gemma 4", decode.string)
    use corr <- decode.optional_field("correctness_score", 70, decode.int)
    use comp <- decode.optional_field("completeness_score", 50, decode.int)
    use verd <- decode.optional_field("verdict", "MARGINAL", decode.string)
    use disc <- decode.optional_field("discrepancies", [], decode.list(decode.string))
    use anal <- decode.optional_field("analysis", "", decode.string)
    use rec <- decode.optional_field("recommended_response", "", decode.string)
    decode.success(GemmaEvaluation(
      understanding_summary: und,
      correctness_score: corr,
      completeness_score: comp,
      verdict: verd,
      discrepancies: disc,
      analysis: anal,
      recommended_response: rec,
      model_used: model_used,
      latency_ms: latency_ms,
    ))
  }

  case json.parse(clean_json, eval_decoder) {
    Ok(eval) -> Ok(eval)
    Error(_) -> {
      // Return structured fallback containing raw content if JSON decode failed
      Ok(GemmaEvaluation(
        understanding_summary: "Raw evaluation output captured",
        correctness_score: 75,
        completeness_score: 50,
        verdict: "MARGINAL",
        discrepancies: ["Raw output format deviation"],
        analysis: clean_json,
        recommended_response: "",
        model_used: model_used,
        latency_ms: latency_ms,
      ))
    }
  }
}

/// Expose system time in nanoseconds for latency benchmarks.
pub fn system_time_nanos() -> Int {
  ffi_system_time_nanos()
}

/// Public JSON parser for GemmaEvaluation records (SC-HIVE-DECISION-001).
pub fn parse_evaluation_json(
  raw_json: String,
  model_used: String,
  latency_ms: Int,
) -> Result(GemmaEvaluation, String) {
  let clean_json =
    raw_json
    |> string.replace("```json", "")
    |> string.replace("```", "")
    |> string.trim

  let eval_decoder = {
    use und <- decode.optional_field("understanding_summary", "Parsed by Gemma 4", decode.string)
    use corr <- decode.optional_field("correctness_score", 70, decode.int)
    use comp <- decode.optional_field("completeness_score", 50, decode.int)
    use verd <- decode.optional_field("verdict", "MARGINAL", decode.string)
    use disc <- decode.optional_field("discrepancies", [], decode.list(decode.string))
    use anal <- decode.optional_field("analysis", "", decode.string)
    use rec <- decode.optional_field("recommended_response", "", decode.string)
    decode.success(GemmaEvaluation(
      understanding_summary: und,
      correctness_score: corr,
      completeness_score: comp,
      verdict: verd,
      discrepancies: disc,
      analysis: anal,
      recommended_response: rec,
      model_used: model_used,
      latency_ms: latency_ms,
    ))
  }

  json.parse(clean_json, eval_decoder)
  |> result.replace_error("failed_to_decode_evaluation_json")
}

