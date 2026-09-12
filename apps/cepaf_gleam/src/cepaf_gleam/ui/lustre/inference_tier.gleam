//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/ui/lustre/inference_tier</module></identity>
////   <fractal-topology><layer>L4_SYSTEM</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-COG-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Lustre page: 6-tier inference cascade dashboard with circuit breaker status.
//// STAMP: SC-GLM-UI-001 (Triple-Interface), SC-COG-001 (6-tier inference)

import gleam/list
import gleam/option.{type Option, None, Some}

pub type CircuitState {
  CircuitClosed
  CircuitOpen(cooldown_remaining_s: Int)
  CircuitHalfOpen
}

pub type TierStatus {
  TierStatus(
    tier: Int,
    name: String,
    model: String,
    latency_ms: Int,
    active: Bool,
    circuit: CircuitState,
    requests_total: Int,
    failures_total: Int,
  )
}

pub type InferenceTierModel {
  InferenceTierModel(
    tiers: List(TierStatus),
    active_tier: Int,
    hedged_mode: Bool,
    total_requests: Int,
    avg_latency_ms: Int,
    cache_hit_rate: Float,
    loading: Bool,
    error: Option(String),
  )
}

pub type InferenceTierMsg {
  TiersLoaded(List(TierStatus))
  ActiveTierChanged(Int)
  CacheStatsUpdated(Float)
  RefreshInference
  ErrorReceived(String)
}

pub fn init() -> InferenceTierModel {
  InferenceTierModel(
    tiers: default_tiers(),
    active_tier: 1,
    hedged_mode: True,
    total_requests: 0,
    avg_latency_ms: 0,
    cache_hit_rate: 0.0,
    loading: False,
    error: None,
  )
}

pub fn update(
  model: InferenceTierModel,
  msg: InferenceTierMsg,
) -> InferenceTierModel {
  case msg {
    TiersLoaded(tiers) -> InferenceTierModel(..model, tiers: tiers, loading: False)
    ActiveTierChanged(tier) -> InferenceTierModel(..model, active_tier: tier)
    CacheStatsUpdated(rate) -> InferenceTierModel(..model, cache_hit_rate: rate)
    RefreshInference -> InferenceTierModel(..model, loading: True)
    ErrorReceived(e) -> InferenceTierModel(..model, error: Some(e), loading: False)
  }
}

pub fn active_tier_name(model: InferenceTierModel) -> String {
  case list.find(model.tiers, fn(t) { t.tier == model.active_tier }) {
    Ok(t) -> t.name
    Error(_) -> "unknown"
  }
}

pub fn circuit_state_label(state: CircuitState) -> String {
  case state {
    CircuitClosed -> "CLOSED"
    CircuitOpen(s) -> "OPEN (" <> int_to_str(s) <> "s)"
    CircuitHalfOpen -> "HALF-OPEN"
  }
}

pub fn all_circuits_healthy(model: InferenceTierModel) -> Bool {
  list.all(model.tiers, fn(t) {
    case t.circuit {
      CircuitClosed -> True
      _ -> False
    }
  })
}

fn default_tiers() -> List(TierStatus) {
  [
    TierStatus(1, "Gemini Direct", "gemini-3.1-flash-lite-preview", 900, True, CircuitClosed, 0, 0),
    TierStatus(2, "OpenRouter", "gemini-3-flash-preview", 1100, True, CircuitClosed, 0, 0),
    TierStatus(3, "Ollama gemma4", "gemma4", 4000, False, CircuitClosed, 0, 0),
    TierStatus(4, "Ollama gemma3", "gemma3", 10000, False, CircuitClosed, 0, 0),
    TierStatus(5, "RETE-UL Rules", "rule-engine", 1, False, CircuitClosed, 0, 0),
    TierStatus(6, "Static Ack", "static", 0, False, CircuitClosed, 0, 0),
  ]
}

@external(erlang, "erlang", "integer_to_binary")
fn int_to_str(i: Int) -> String

// =============================================================================
// NIF-backed data loading (SC-WIRE-001: real ops data)
// =============================================================================

import cepaf_gleam/c3i/nif
import gleam/dynamic/decode
import gleam/json

/// Load real inference status from NIF → Rust → TransactionSummary
pub fn load_from_nif() -> InferenceTierModel {
  let raw = nif.inference_status()
  let decoder = {
    use total <- decode.field("total_recent", decode.int)
    decode.success(total)
  }
  let total = case json.parse(raw, decoder) {
    Ok(t) -> t
    Error(_) -> 0
  }
  let model = init()
  InferenceTierModel(..model, total_requests: total, loading: False)
}
