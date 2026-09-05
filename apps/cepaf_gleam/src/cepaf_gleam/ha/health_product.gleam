//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/health_product</module>
////     <fsharp-lineage>None — novel Gleam implementation</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>Live biomorphic health product computation</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-BIO-EVO-001, SC-TRUTH-001, SC-SATYA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="constructive">
////       7 subsystem vitals → multiplicative product Π(health_i) → weather label.
////       System is ALIVE iff product > 0, HEALTHY iff > 0.7, OPTIMAL iff > 0.9.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// LIVE BIOMORPHIC HEALTH PRODUCT
//// जीवित जैवरूपी स्वास्थ्य गुणनफल
////
//// Computes the multiplicative health product Π(subsystem_health_i) for all
//// 7 biomorphic subsystems. This is the single number that answers:
//// "Is the system alive, healthy, or optimal?"
////
//// STAMP: SC-BIO-EVO-001, SC-TRUTH-001, SC-SATYA-001

import gleam/float
import gleam/int
import gleam/list
import gleam/string

/// A single subsystem's health vital.
pub type SubsystemVital {
  SubsystemVital(
    /// Subsystem name (nervous, immune, circulatory, etc.)
    name: String,
    /// Health score [0.0, 1.0]
    health: Float,
    /// Data source description
    source: String,
  )
}

/// The computed health product from all 7 subsystems.
pub type HealthProduct {
  HealthProduct(
    /// Individual subsystem vitals
    subsystems: List(SubsystemVital),
    /// Multiplicative product: Π(health_i)
    product: Float,
    /// Name of the weakest subsystem
    weakest_name: String,
    /// Health score of the weakest subsystem
    weakest_health: Float,
    /// Weather label derived from product
    weather: WeatherLabel,
    /// Number of subsystems sampled
    subsystem_count: Int,
  )
}

/// System weather derived from health product.
pub type WeatherLabel {
  /// product >= 0.9 — all nominal, suppress noise
  Clear
  /// product >= 0.7 — minor issues
  PartlyCloudy
  /// product >= 0.5 — attention needed
  Cloudy
  /// product >= 0.3 — significant degradation
  Stormy
  /// product < 0.3 — system-wide failure
  Emergency
}

/// Compute the health product from a list of subsystem vitals.
pub fn compute(subsystems: List(SubsystemVital)) -> HealthProduct {
  let product = list.fold(subsystems, 1.0, fn(acc, v) { acc *. v.health })
  let #(weakest_name, weakest_health) = find_weakest(subsystems)
  let weather = classify_weather(product)
  HealthProduct(
    subsystems: subsystems,
    product: product,
    weakest_name: weakest_name,
    weakest_health: weakest_health,
    weather: weather,
    subsystem_count: list.length(subsystems),
  )
}

/// Build default subsystem vitals when no live data available.
pub fn default_vitals() -> List(SubsystemVital) {
  [
    SubsystemVital(
      name: "nervous",
      health: 0.9,
      source: "hooks + auto-build response time",
    ),
    SubsystemVital(
      name: "immune",
      health: 0.85,
      source: "threat level + antibody count",
    ),
    SubsystemVital(
      name: "circulatory",
      health: 0.95,
      source: "heartbeat monitor (Gleam↔Rust)",
    ),
    SubsystemVital(
      name: "skeletal",
      health: 1.0,
      source: "type system + wiring guard",
    ),
    SubsystemVital(
      name: "digestive",
      health: 0.9,
      source: "freshness monitor pipeline health",
    ),
    SubsystemVital(
      name: "reproductive",
      health: 0.85,
      source: "tensor coverage + rule adaptation",
    ),
    SubsystemVital(
      name: "endocrine",
      health: 0.8,
      source: "OODA cycle latency + EMA trends",
    ),
  ]
}

/// Compute with default vitals.
pub fn compute_default() -> HealthProduct {
  compute(default_vitals())
}

/// Classify weather from health product.
fn classify_weather(product: Float) -> WeatherLabel {
  case product {
    p if p >=. 0.9 -> Clear
    p if p >=. 0.7 -> PartlyCloudy
    p if p >=. 0.5 -> Cloudy
    p if p >=. 0.3 -> Stormy
    _ -> Emergency
  }
}

/// Find the weakest subsystem.
fn find_weakest(subsystems: List(SubsystemVital)) -> #(String, Float) {
  case subsystems {
    [] -> #("none", 1.0)
    [first, ..rest] ->
      list.fold(rest, #(first.name, first.health), fn(acc, v) {
        case v.health <. acc.1 {
          True -> #(v.name, v.health)
          False -> acc
        }
      })
  }
}

/// Weather label to string.
pub fn weather_to_string(w: WeatherLabel) -> String {
  case w {
    Clear -> "Clear"
    PartlyCloudy -> "Partly Cloudy"
    Cloudy -> "Cloudy"
    Stormy -> "Stormy"
    Emergency -> "Emergency"
  }
}

/// Is the system alive? (product > 0)
pub fn is_alive(hp: HealthProduct) -> Bool {
  hp.product >. 0.0
}

/// Is the system healthy? (product >= 0.7)
pub fn is_healthy(hp: HealthProduct) -> Bool {
  hp.product >=. 0.7
}

/// Is the system optimal? (product >= 0.9)
pub fn is_optimal(hp: HealthProduct) -> Bool {
  hp.product >=. 0.9
}

/// Human-readable status string.
pub fn status_string(hp: HealthProduct) -> String {
  let status = case is_optimal(hp) {
    True -> "OPTIMAL"
    False ->
      case is_healthy(hp) {
        True -> "HEALTHY"
        False ->
          case is_alive(hp) {
            True -> "DEGRADED"
            False -> "DEAD"
          }
      }
  }
  status
  <> " Π="
  <> float.to_string(hp.product)
  <> " weather="
  <> weather_to_string(hp.weather)
  <> " weakest="
  <> hp.weakest_name
  <> "("
  <> float.to_string(hp.weakest_health)
  <> ")"
}

/// Render subsystem vitals as a compact table string.
pub fn vitals_table(hp: HealthProduct) -> String {
  hp.subsystems
  |> list.map(fn(v) {
    let bar = health_bar(v.health)
    "  " <> pad_right(v.name, 14) <> bar <> " " <> float_pct(v.health)
  })
  |> string.join("\n")
}

fn health_bar(h: Float) -> String {
  let filled = float.round(h *. 10.0)
  let empty = 10 - filled
  "[" <> string.repeat("█", filled) <> string.repeat("░", empty) <> "]"
}

fn float_pct(f: Float) -> String {
  let pct = float.round(f *. 100.0)
  int.to_string(pct) <> "%"
}

fn pad_right(s: String, width: Int) -> String {
  let len = string.length(s)
  case len >= width {
    True -> s
    False -> s <> string.repeat(" ", width - len)
  }
}
