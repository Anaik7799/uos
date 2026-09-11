//// =============================================================================
//// [C3I-SIL6-MSTS] UOS CORTEX DOMAIN TYPES & ALGEBRAIC ATLAS
//// =============================================================================
//// <uos-module>
////   <identity>
////     <module>cepaf_gleam/cortex/cortex_types</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <topology>Cortex Intent & Decision Algebraic Types</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-COG-001, SC-COG-MAX-001, SC-CIRCUIT-001, SC-WIRE-001</stamp-controls>
////   </compliance>
//// </uos-module>
//// =============================================================================

import gleam/option.{type Option}

pub type IntentSource {
  SourceTelegram
  SourceGChat
  SourceMatrix
  SourceWebCockpit
  SourceInternalAgent
  SourceVoice
  SourceOther(String)
}

pub type TaskIntent {
  TaskIntent(
    id: String,
    raw_text: String,
    source: IntentSource,
    chat_id: Option(String),
    user_id: Option(String),
    timestamp_ms: Int,
    intent_type: String,
    stress_level: Float,
  )
}

pub type OodaPhase {
  PhaseObserve
  PhaseOrient
  PhaseDecide
  PhaseAct
  PhaseCompleted
}

pub type InferenceTierId {
  Tier1GeminiDirect
  Tier2OpenRouter
  Tier3MistralRsGemma4
  Tier4OllamaGemma4
  Tier5OllamaGemma3
  Tier6ReteUlRules
  Tier7StaticAck
}

pub type InferenceResult {
  InferenceResult(
    tier: InferenceTierId,
    model: String,
    response_text: String,
    latency_ms: Int,
    token_count: Int,
    confidence: Float,
  )
}

pub type TraceStage {
  TraceStage(
    name: String,
    detail: String,
    status: String,
    elapsed_ms: Int,
  )
}

pub type PipelineTrace {
  PipelineTrace(
    id: String,
    source: String,
    started_at_ms: Int,
    stages: List(TraceStage),
    classification: String,
    total_ms: Int,
  )
}

pub type CortexDecision {
  CortexDecision(
    intent_id: String,
    phase: OodaPhase,
    reasoning: String,
    reply_markdown: String,
    actions_proposed: List(String),
    inference_result: Option(InferenceResult),
    confidence: Float,
    timestamp_ms: Int,
    trace: Option(PipelineTrace),
    footer: String,
    sa_plan_authorized: Bool,
  )
}

pub fn source_to_string(source: IntentSource) -> String {
  case source {
    SourceTelegram -> "telegram"
    SourceGChat -> "gchat"
    SourceMatrix -> "matrix"
    SourceWebCockpit -> "web_cockpit"
    SourceInternalAgent -> "internal_agent"
    SourceVoice -> "voice"
    SourceOther(s) -> s
  }
}

pub fn string_to_source(s: String) -> IntentSource {
  case s {
    "telegram" -> SourceTelegram
    "gchat" -> SourceGChat
    "matrix" -> SourceMatrix
    "web_cockpit" -> SourceWebCockpit
    "internal_agent" -> SourceInternalAgent
    "voice" -> SourceVoice
    other -> SourceOther(other)
  }
}

pub fn tier_to_int(tier: InferenceTierId) -> Int {
  case tier {
    Tier1GeminiDirect -> 1
    Tier2OpenRouter -> 2
    Tier3MistralRsGemma4 -> 3
    Tier4OllamaGemma4 -> 4
    Tier5OllamaGemma3 -> 5
    Tier6ReteUlRules -> 6
    Tier7StaticAck -> 7
  }
}

pub fn tier_to_name(tier: InferenceTierId) -> String {
  case tier {
    Tier1GeminiDirect -> "gemini_direct"
    Tier2OpenRouter -> "openrouter"
    Tier3MistralRsGemma4 -> "mistral_rs_gemma4"
    Tier4OllamaGemma4 -> "ollama_gemma4"
    Tier5OllamaGemma3 -> "ollama_gemma3"
    Tier6ReteUlRules -> "rete_ul"
    Tier7StaticAck -> "static_ack"
  }
}

pub fn tier_expected_latency(tier: InferenceTierId) -> Int {
  case tier {
    Tier1GeminiDirect -> 900
    Tier2OpenRouter -> 1100
    Tier3MistralRsGemma4 -> 500
    Tier4OllamaGemma4 -> 4000
    Tier5OllamaGemma3 -> 10_000
    Tier6ReteUlRules -> 1
    Tier7StaticAck -> 1
  }
}
