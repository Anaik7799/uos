//// Wisp API for Health Product (SC-GLM-UI-001, SC-GLM-UI-003).
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-BIO-EVO-001, SC-TRUTH-001

import cepaf_gleam/ha/health_product
import gleam/float
import gleam/json

/// Render health product as JSON.
pub fn health_product_json(hp: health_product.HealthProduct) -> String {
  json.object([
    #("plane", json.string("health_product")),
    #("product", json.string(float.to_string(hp.product))),
    #("weather", json.string(health_product.weather_to_string(hp.weather))),
    #("weakest_name", json.string(hp.weakest_name)),
    #(
      "weakest_health",
      json.string(float.to_string(hp.weakest_health)),
    ),
    #("subsystem_count", json.int(hp.subsystem_count)),
    #("is_alive", json.bool(health_product.is_alive(hp))),
    #("is_healthy", json.bool(health_product.is_healthy(hp))),
    #("is_optimal", json.bool(health_product.is_optimal(hp))),
    #("subsystems", json.array(hp.subsystems, encode_vital)),
    #("status", json.string(health_product.status_string(hp))),
  ])
  |> json.to_string()
}

/// Summary JSON for embedding.
pub fn health_product_summary_json(
  hp: health_product.HealthProduct,
) -> json.Json {
  json.object([
    #("product", json.string(float.to_string(hp.product))),
    #("weather", json.string(health_product.weather_to_string(hp.weather))),
    #("weakest", json.string(hp.weakest_name)),
    #("alive", json.bool(health_product.is_alive(hp))),
  ])
}

fn encode_vital(v: health_product.SubsystemVital) -> json.Json {
  json.object([
    #("name", json.string(v.name)),
    #("health", json.string(float.to_string(v.health))),
    #("source", json.string(v.source)),
  ])
}
