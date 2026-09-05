//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/lustre/app</module>
////     <fsharp-lineage>Cepaf.UI.Bolero.App.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>Lustre MVU Dashboard</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-005, SC-GLM-UI-008</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       F# Elmish/Bolero MVU ≅ Gleam Lustre MVU. Perfect structural mapping.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================

///
/// Lustre Web UI application for c3i cockpit (SC-GLM-UI-001, SC-GLM-UI-002).
/// Server-side rendered on BEAM — no client-side JS required.
/// Subscribes to Zenoh PubSub for real-time telemetry (SC-GLM-UI-005).
/// Implements Dark Cockpit pattern (SC-GLM-UI-008, SC-HMI-010).
import cepaf_gleam/ui/domain.{
  type HealthStatus, type Page, type RenderContext, type TelemetryPoint,
  Critical, Dashboard, Degraded, Healthy, RenderContext, Unknown,
}
import cepaf_gleam/ui/zenoh_otel

/// Lustre Model — application state for the c3i Web dashboard.
pub type Model {
  Model(context: RenderContext, dark_cockpit: Bool, selected_page: Page)
}

/// Lustre Messages — UI events and Zenoh subscriptions.
pub type Msg {
  NavigateTo(page: Page)
  TelemetryReceived(point: TelemetryPoint)
  HealthUpdated(status: HealthStatus)
  ZenohConnectionChanged(connected: Bool)
  ToggleDarkCockpit
  Tick
}

/// Initialize the Lustre application with default state.
pub fn init() -> Model {
  Model(
    context: RenderContext(
      page: Dashboard,
      health: Unknown,
      telemetry: [],
      zenoh_connected: False,
    ),
    dark_cockpit: True,
    selected_page: Dashboard,
  )
}

/// Update function — processes messages and returns new model.
pub fn update(model: Model, msg: Msg) -> Model {
  zenoh_otel.emit(Dashboard, "update", zenoh_otel.Act)
  case msg {
    NavigateTo(page) -> Model(..model, selected_page: page)
    TelemetryReceived(point) ->
      Model(
        ..model,
        context: RenderContext(..model.context, telemetry: [
          point,
          ..model.context.telemetry
        ]),
      )
    HealthUpdated(status) ->
      Model(..model, context: RenderContext(..model.context, health: status))
    ZenohConnectionChanged(connected) ->
      Model(
        ..model,
        context: RenderContext(..model.context, zenoh_connected: connected),
      )
    ToggleDarkCockpit -> Model(..model, dark_cockpit: !model.dark_cockpit)
    Tick -> model
  }
}

/// Render health as HTML class for Dark Cockpit pattern.
/// Normal = minimal display. Anomaly = prominent display (SC-HMI-010).
pub fn health_class(status: HealthStatus) -> String {
  case status {
    Healthy -> "health-ok"
    Degraded(_) -> "health-warn"
    Critical(_) -> "health-critical"
    Unknown -> "health-unknown"
  }
}
