//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/lustre/health_product_page</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-BIO-EVO-001, SC-TRUTH-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Lustre MVU model for the Health Product page.
//// Displays the multiplicative biomorphic health product Π(health_i).

import cepaf_gleam/ha/health_product
import gleam/option.{type Option, None, Some}

pub type HealthProductModel {
  HealthProductModel(
    product: Float,
    weather: String,
    weakest_name: String,
    weakest_health: Float,
    subsystem_count: Int,
    is_alive: Bool,
    is_healthy: Bool,
    is_optimal: Bool,
    vitals_table: String,
    loading: Bool,
    error: Option(String),
  )
}

pub type HealthProductMsg {
  ProductComputed(hp: health_product.HealthProduct)
  RefreshProduct
  ErrorReceived(String)
}

pub fn init() -> HealthProductModel {
  let hp = health_product.compute_default()
  HealthProductModel(
    product: hp.product,
    weather: health_product.weather_to_string(hp.weather),
    weakest_name: hp.weakest_name,
    weakest_health: hp.weakest_health,
    subsystem_count: hp.subsystem_count,
    is_alive: health_product.is_alive(hp),
    is_healthy: health_product.is_healthy(hp),
    is_optimal: health_product.is_optimal(hp),
    vitals_table: health_product.vitals_table(hp),
    loading: False,
    error: None,
  )
}

pub fn update(
  model: HealthProductModel,
  msg: HealthProductMsg,
) -> HealthProductModel {
  case msg {
    ProductComputed(hp) ->
      HealthProductModel(
        product: hp.product,
        weather: health_product.weather_to_string(hp.weather),
        weakest_name: hp.weakest_name,
        weakest_health: hp.weakest_health,
        subsystem_count: hp.subsystem_count,
        is_alive: health_product.is_alive(hp),
        is_healthy: health_product.is_healthy(hp),
        is_optimal: health_product.is_optimal(hp),
        vitals_table: health_product.vitals_table(hp),
        loading: False,
        error: None,
      )
    RefreshProduct -> HealthProductModel(..model, loading: True)
    ErrorReceived(e) ->
      HealthProductModel(..model, error: Some(e), loading: False)
  }
}
