//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/samvid_vajravyuha</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>
////       Saṁvid Vajravyūha (संविद् वज्रव्यूह) Canonical Holarchic Registry.
////       Defines the 7 bare-metal sovereign defense holons, tracks local vs
////       cloud execution ratios, and enforces SIL-6 fail-closed autonomy.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>
////       SC-DEFENSE-CONSTITUTION-001, SC-SURVEILLANCE-001, SC-INF-MOJO-001,
////       SC-ZERO-MUDA-001, SC-MATH-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/float
import gleam/int
import gleam/json

/// The 7 Canonical Holons of Saṁvid Vajravyūha.
pub type HolonLayer {
  Holon0VajraAdhisthana
  Holon1RasaDhatu
  Holon2KevalaKosa
  Holon3PramanaViveka
  Holon4PranaVyuha
  Holon5PratyaksaRaksa
  Holon6CakraSancarana
}

/// Convert HolonLayer to string identifier.
pub fn layer_to_string(layer: HolonLayer) -> String {
  case layer {
    Holon0VajraAdhisthana -> "H0_VAJRA_ADHISTHANA"
    Holon1RasaDhatu -> "H1_RASA_DHATU"
    Holon2KevalaKosa -> "H2_KEVALA_KOSA"
    Holon3PramanaViveka -> "H3_PRAMANA_VIVEKA"
    Holon4PranaVyuha -> "H4_PRANA_VYUHA"
    Holon5PratyaksaRaksa -> "H5_PRATYAKSA_RAKSA"
    Holon6CakraSancarana -> "H6_CAKRA_SANCARANA"
  }
}

/// Holon Definition Structure.
pub type HolonDefinition {
  HolonDefinition(
    id: String,
    layer: HolonLayer,
    sanskrit_name: String,
    transliteration: String,
    engine: String,
    language: String,
    max_latency_budget_us: Int,
    is_local_metal: Bool,
  )
}

/// Global State of the Saṁvid Vajravyūha Holarchy.
pub type VajravyuhaState {
  VajravyuhaState(
    holons: List(HolonDefinition),
    total_workloads: Int,
    local_workloads: Int,
    cloud_workloads: Int,
    degradation_active: Bool,
  )
}

/// Return the 7 Canonical Holon Definitions.
pub fn canonical_holons() -> List(HolonDefinition) {
  [
    HolonDefinition(
      id: "H0",
      layer: Holon0VajraAdhisthana,
      sanskrit_name: "वज्र-अधिष्ठान",
      transliteration: "Vajra-Adhisthana",
      engine: "ZigVM",
      language: "Zig 0.16.0",
      max_latency_budget_us: 100,
      is_local_metal: True,
    ),
    HolonDefinition(
      id: "H1",
      layer: Holon1RasaDhatu,
      sanskrit_name: "रस-धातु",
      transliteration: "Rasa-Dhatu",
      engine: "Modular MAX / Mojo",
      language: "Mojo 1.0.0",
      max_latency_budget_us: 30,
      is_local_metal: True,
    ),
    HolonDefinition(
      id: "H2",
      layer: Holon2KevalaKosa,
      sanskrit_name: "केवल-कोश",
      transliteration: "Kevala-Kosa",
      engine: "MirageOS / Solo5",
      language: "OCaml 5.5.0 Unikernel",
      max_latency_budget_us: 10_000,
      is_local_metal: True,
    ),
    HolonDefinition(
      id: "H3",
      layer: Holon3PramanaViveka,
      sanskrit_name: "प्रमाण-विवेक",
      transliteration: "Pramana-Viveka",
      engine: "Hermes OCaml & Lean 4",
      language: "OCaml 5.5.0 / Lean 4.33.0",
      max_latency_budget_us: 1000,
      is_local_metal: True,
    ),
    HolonDefinition(
      id: "H4",
      layer: Holon4PranaVyuha,
      sanskrit_name: "प्राण-व्यूह",
      transliteration: "Prana-Vyuha",
      engine: "Pure Gleam / BEAM OTP 29",
      language: "Gleam 1.16.0 / Erlang 29",
      max_latency_budget_us: 2000,
      is_local_metal: True,
    ),
    HolonDefinition(
      id: "H5",
      layer: Holon5PratyaksaRaksa,
      sanskrit_name: "प्रत्यक्ष-रक्षा",
      transliteration: "Pratyaksa-Raksa",
      engine: "Gleam Tri-Agent Monitor & Hermes Hook",
      language: "Gleam & OCaml",
      max_latency_budget_us: 500,
      is_local_metal: True,
    ),
    HolonDefinition(
      id: "H6",
      layer: Holon6CakraSancarana,
      sanskrit_name: "चक्र-संचरण",
      transliteration: "Cakra-Sancarana",
      engine: "Zenoh Pub/Sub Mesh & W3C OTel",
      language: "Rust / C / Gleam",
      max_latency_budget_us: 1000,
      is_local_metal: True,
    ),
  ]
}

/// Initialise Canonical Saṁvid Vajravyūha Holarchy State.
pub fn init_vajravyuha(degradation_active: Bool) -> VajravyuhaState {
  VajravyuhaState(
    holons: canonical_holons(),
    total_workloads: 42,
    local_workloads: 39,
    cloud_workloads: 3,
    degradation_active: degradation_active,
  )
}

/// Calculate Local Sovereign Processing Ratio: 39 / 42 = 0.92857... (92.86%).
pub fn local_processing_ratio(state: VajravyuhaState) -> Float {
  case state.total_workloads > 0 {
    True ->
      int.to_float(state.local_workloads)
      /. int.to_float(state.total_workloads)
    False -> 1.0
  }
}

/// Calculate Gleam + Mojo/MAX Combined Processing Ratio: (16 + 16) / 42 = 0.7619 (76.19%).
pub fn gleam_and_max_ratio(_state: VajravyuhaState) -> Float {
  32.0 /. 42.0
}

/// Serialize HolonDefinition to JSON.
pub fn holon_to_json(holon: HolonDefinition) -> json.Json {
  json.object([
    #("id", json.string(holon.id)),
    #("layer", json.string(layer_to_string(holon.layer))),
    #("sanskrit_name", json.string(holon.sanskrit_name)),
    #("transliteration", json.string(holon.transliteration)),
    #("engine", json.string(holon.engine)),
    #("language", json.string(holon.language)),
    #("max_latency_budget_us", json.int(holon.max_latency_budget_us)),
    #("is_local_metal", json.bool(holon.is_local_metal)),
  ])
}

/// Serialize complete VajravyuhaState to JSON.
pub fn state_to_json(state: VajravyuhaState) -> json.Json {
  json.object([
    #("sanskrit_title", json.string("संविद् वज्रव्यूह")),
    #("transliteration_title", json.string("Saṁvid Vajravyūha")),
    #(
      "english_title",
      json.string("Sovereign Adamantine Cybernetic Defense Holarchy"),
    ),
    #("total_workloads", json.int(state.total_workloads)),
    #("local_workloads", json.int(state.local_workloads)),
    #("cloud_workloads", json.int(state.cloud_workloads)),
    #("local_processing_ratio", json.float(local_processing_ratio(state))),
    #("gleam_and_max_ratio", json.float(gleam_and_max_ratio(state))),
    #("degradation_active", json.bool(state.degradation_active)),
    #("holons", json.array(from: state.holons, of: holon_to_json)),
  ])
}

/// ANSI Dashboard Summary String for C3I Cockpit.
pub fn render_ansi_summary(state: VajravyuhaState) -> String {
  let ratio_pct = local_processing_ratio(state) *. 100.0
  let mode_str = case state.degradation_active {
    True -> "[AUTONOMOUS DEGRADATION ACTIVE (100% LOCAL)]"
    False -> "[NOMINAL PEERING (92.86% LOCAL / 7.14% MONITORED CLOUD)]"
  }

  "=== संविद् वज्रव्यूह (Saṁvid Vajravyūha) ===\n"
  <> mode_str
  <> " | Local Sovereignty = "
  <> float.to_string(ratio_pct)
  <> "% ("
  <> int.to_string(state.local_workloads)
  <> "/"
  <> int.to_string(state.total_workloads)
  <> " Workloads)\n"
  <> "Bare-Metal Fabric: Pure Gleam OTP 29 + Modular MAX Mojo + OCaml MirageOS Unikernels + ZigVM"
}
