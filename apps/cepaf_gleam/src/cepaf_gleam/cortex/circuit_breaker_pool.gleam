//// =============================================================================
//// [C3I-SIL6-MSTS] UOS CORTEX CIRCUIT BREAKER POOL
//// =============================================================================
//// <uos-module>
////   <identity>
////     <module>cepaf_gleam/cortex/circuit_breaker_pool</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////     <topology>5-Breaker Hedged Inference Protection Pool</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-CIRCUIT-001, SC-COG-001, SC-CPIG-002, SC-WIRE-001</stamp-controls>
////   </compliance>
//// </uos-module>
//// =============================================================================

import cepaf_gleam/cortex/cortex_types.{
  type InferenceTierId, Tier1GeminiDirect, Tier2OpenRouter, Tier3MistralRsGemma4,
  Tier4OllamaGemma4, Tier5OllamaGemma3, Tier6ReteUlRules, Tier7StaticAck,
}
import cepaf_gleam/prajna/circuit_breaker.{
  type Breaker, attempt_half_open, create, is_allowed, record_failure,
  record_success,
}


pub const failure_threshold: Int = 3
pub const cooldown_seconds: Int = 60
pub const cooldown_ms: Int = 60_000

pub type BreakerPool {
  BreakerPool(
    breaker1_gemini: Breaker,
    breaker2_openrouter: Breaker,
    breaker3_mistral: Breaker,
    breaker4_ollama: Breaker,
    breaker5_rules: Breaker,
  )
}

/// Initialize the 5-breaker pool with strict failure thresholds and cooldowns.
pub fn init_pool() -> BreakerPool {
  BreakerPool(
    breaker1_gemini: create("gemini_direct", failure_threshold, 1, cooldown_ms),
    breaker2_openrouter: create("openrouter", failure_threshold, 1, cooldown_ms),
    breaker3_mistral: create("mistral_gemma4", failure_threshold, 1, cooldown_ms),
    breaker4_ollama: create("ollama_shared", failure_threshold, 1, cooldown_ms),
    breaker5_rules: create("rules_static_shared", failure_threshold, 1, cooldown_ms),
  )
}

/// Map each inference tier to its assigned circuit breaker (1..5).
pub fn tier_to_breaker_id(tier: InferenceTierId) -> Int {
  case tier {
    Tier1GeminiDirect -> 1
    Tier2OpenRouter -> 2
    Tier3MistralRsGemma4 -> 3
    Tier4OllamaGemma4 -> 4
    Tier5OllamaGemma3 -> 4
    Tier6ReteUlRules -> 5
    Tier7StaticAck -> 5
  }
}

/// Query whether a specific inference tier is permitted to execute.
pub fn is_tier_allowed(pool: BreakerPool, tier: InferenceTierId, now_ms: Int) -> Bool {
  case tier {
    Tier7StaticAck -> True // Static ACK is always available (no-blackhole anchor)
    Tier1GeminiDirect -> is_allowed(attempt_half_open(pool.breaker1_gemini, now_ms))
    Tier2OpenRouter -> is_allowed(attempt_half_open(pool.breaker2_openrouter, now_ms))
    Tier3MistralRsGemma4 -> is_allowed(attempt_half_open(pool.breaker3_mistral, now_ms))
    Tier4OllamaGemma4 | Tier5OllamaGemma3 ->
      is_allowed(attempt_half_open(pool.breaker4_ollama, now_ms))
    Tier6ReteUlRules -> is_allowed(attempt_half_open(pool.breaker5_rules, now_ms))
  }
}

/// Record a failure for a specific inference tier.
pub fn record_tier_failure(pool: BreakerPool, tier: InferenceTierId, now_ms: Int) -> BreakerPool {
  case tier {
    Tier1GeminiDirect ->
      BreakerPool(..pool, breaker1_gemini: record_failure(pool.breaker1_gemini, now_ms))
    Tier2OpenRouter ->
      BreakerPool(..pool, breaker2_openrouter: record_failure(pool.breaker2_openrouter, now_ms))
    Tier3MistralRsGemma4 ->
      BreakerPool(..pool, breaker3_mistral: record_failure(pool.breaker3_mistral, now_ms))
    Tier4OllamaGemma4 | Tier5OllamaGemma3 ->
      BreakerPool(..pool, breaker4_ollama: record_failure(pool.breaker4_ollama, now_ms))
    Tier6ReteUlRules | Tier7StaticAck ->
      BreakerPool(..pool, breaker5_rules: record_failure(pool.breaker5_rules, now_ms))
  }
}

/// Record a success for a specific inference tier.
pub fn record_tier_success(pool: BreakerPool, tier: InferenceTierId) -> BreakerPool {
  case tier {
    Tier1GeminiDirect ->
      BreakerPool(..pool, breaker1_gemini: record_success(pool.breaker1_gemini))
    Tier2OpenRouter ->
      BreakerPool(..pool, breaker2_openrouter: record_success(pool.breaker2_openrouter))
    Tier3MistralRsGemma4 ->
      BreakerPool(..pool, breaker3_mistral: record_success(pool.breaker3_mistral))
    Tier4OllamaGemma4 | Tier5OllamaGemma3 ->
      BreakerPool(..pool, breaker4_ollama: record_success(pool.breaker4_ollama))
    Tier6ReteUlRules | Tier7StaticAck ->
      BreakerPool(..pool, breaker5_rules: record_success(pool.breaker5_rules))
  }
}

/// Get a list of all 5 breaker statuses.
pub fn pool_status(pool: BreakerPool) -> List(#(String, String, Int)) {
  [
    #(pool.breaker1_gemini.name, breaker_state_str(pool.breaker1_gemini), pool.breaker1_gemini.failure_count),
    #(pool.breaker2_openrouter.name, breaker_state_str(pool.breaker2_openrouter), pool.breaker2_openrouter.failure_count),
    #(pool.breaker3_mistral.name, breaker_state_str(pool.breaker3_mistral), pool.breaker3_mistral.failure_count),
    #(pool.breaker4_ollama.name, breaker_state_str(pool.breaker4_ollama), pool.breaker4_ollama.failure_count),
    #(pool.breaker5_rules.name, breaker_state_str(pool.breaker5_rules), pool.breaker5_rules.failure_count),
  ]
}

fn breaker_state_str(b: Breaker) -> String {
  case b.state {
    circuit_breaker.BreakerClosed -> "closed"
    circuit_breaker.BreakerOpen(_) -> "open"
    circuit_breaker.BreakerHalfOpen -> "half_open"
  }
}

/// Returns True if all primary dynamic inference breakers are tripped/open.
pub fn is_pool_tripped(pool: BreakerPool) -> Bool {
  pool.breaker1_gemini.failure_count >= failure_threshold
  && pool.breaker2_openrouter.failure_count >= failure_threshold
  && pool.breaker3_mistral.failure_count >= failure_threshold
  && pool.breaker4_ollama.failure_count >= failure_threshold
}
