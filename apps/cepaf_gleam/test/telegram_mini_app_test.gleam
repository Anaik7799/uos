import cepaf_gleam/telegram/auth
import cepaf_gleam/telegram/theme
import cepaf_gleam/telegram/types
import cepaf_gleam/ui/lustre/mini_app
import cepaf_gleam/ui/wisp/mini_app_routes
import gleam/string
import gleeunit/should

// =============================================================================
// Theme tests
// =============================================================================

pub fn theme_bg_color_uses_css_var_test() {
  theme.bg_color()
  |> should.equal("var(--tg-theme-bg-color)")
}

pub fn theme_button_color_uses_css_var_test() {
  theme.button_color()
  |> should.equal("var(--tg-theme-button-color)")
}

pub fn theme_css_contains_tg_card_class_test() {
  theme.mini_app_css()
  |> string.contains(".tg-card")
  |> should.be_true()
}

pub fn theme_css_contains_nav_bar_test() {
  theme.mini_app_css()
  |> string.contains(".tg-nav-bar")
  |> should.be_true()
}

pub fn theme_font_family_has_system_ui_test() {
  theme.font_family()
  |> string.contains("-apple-system")
  |> should.be_true()
}

// =============================================================================
// Auth tests
// =============================================================================

pub fn auth_malformed_data_missing_hash_test() {
  let result = auth.validate("user=test&auth_date=123", "bot_token")
  case result {
    auth.MalformedData(_) -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

pub fn auth_invalid_hash_test() {
  let result =
    auth.validate(
      "user=%7B%22id%22%3A123%7D&auth_date=1234567890&hash=badhash",
      "test_token",
    )
  case result {
    auth.InvalidHash -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

pub fn auth_check_freshness_valid_test() {
  let init_data = "auth_date=1000&hash=abc"
  auth.check_freshness(init_data, 1200, 300)
  |> should.be_true()
}

pub fn auth_check_freshness_expired_test() {
  let init_data = "auth_date=1000&hash=abc"
  auth.check_freshness(init_data, 2000, 300)
  |> should.be_false()
}

// =============================================================================
// Types tests
// =============================================================================

pub fn types_page_to_path_dashboard_test() {
  types.page_to_path(types.MiniDashboard)
  |> should.equal("/mini-app/dashboard")
}

pub fn types_page_to_path_alerts_test() {
  types.page_to_path(types.MiniCockpit)
  |> should.equal("/mini-app/alerts")
}

pub fn types_page_to_label_test() {
  types.page_to_label(types.MiniPlanning)
  |> should.equal("Tasks")
}

pub fn types_nav_tab_dashboard_test() {
  types.page_nav_tab(types.MiniDashboard)
  |> should.equal(types.TabDashboard)
}

pub fn types_nav_tab_alerts_test() {
  types.page_nav_tab(types.MiniCockpit)
  |> should.equal(types.TabAlerts)
}

pub fn types_nav_tab_tasks_test() {
  types.page_nav_tab(types.MiniPlanning)
  |> should.equal(types.TabTasks)
}

pub fn types_nav_tab_system_test() {
  types.page_nav_tab(types.MiniInference)
  |> should.equal(types.TabSystem)
}

// =============================================================================
// Mini App view tests — verify each renders non-empty HTML
// =============================================================================

pub fn mini_dashboard_renders_test() {
  mini_app.dashboard_view()
  |> string.contains("C3I Mesh")
  |> should.be_true()
}

pub fn mini_health_grid_renders_test() {
  mini_app.health_grid_view()
  |> string.contains("Health Grid")
  |> should.be_true()
}

pub fn mini_cockpit_renders_test() {
  mini_app.cockpit_view()
  |> string.contains("Cockpit")
  |> should.be_true()
}

pub fn mini_immune_renders_test() {
  mini_app.immune_view()
  |> string.contains("Immune System")
  |> should.be_true()
}

pub fn mini_planning_renders_test() {
  mini_app.planning_view()
  |> string.contains("Tasks")
  |> should.be_true()
}

pub fn mini_inference_renders_test() {
  mini_app.inference_view()
  |> string.contains("Inference")
  |> should.be_true()
}

pub fn mini_conversation_renders_test() {
  mini_app.conversation_view()
  |> string.contains("Chat History")
  |> should.be_true()
}

pub fn mini_config_renders_test() {
  mini_app.config_view()
  |> string.contains("Configuration")
  |> should.be_true()
}

pub fn mini_podman_renders_test() {
  mini_app.podman_view()
  |> string.contains("Containers")
  |> should.be_true()
}

pub fn mini_federation_renders_test() {
  mini_app.federation_view()
  |> string.contains("Federation")
  |> should.be_true()
}

pub fn mini_verification_renders_test() {
  mini_app.verification_view()
  |> string.contains("Verification")
  |> should.be_true()
}

pub fn mini_fmea_renders_test() {
  mini_app.fmea_view()
  |> string.contains("FMEA")
  |> should.be_true()
}

pub fn mini_telemetry_renders_test() {
  mini_app.telemetry_view()
  |> string.contains("Telemetry")
  |> should.be_true()
}

pub fn mini_zenoh_browser_renders_test() {
  mini_app.zenoh_browser_view()
  |> string.contains("Zenoh Browser")
  |> should.be_true()
}

// =============================================================================
// Route tests
// =============================================================================

pub fn route_is_mini_app_path_test() {
  mini_app_routes.is_mini_app_path("/mini-app/dashboard")
  |> should.be_true()
}

pub fn route_is_not_mini_app_path_test() {
  mini_app_routes.is_mini_app_path("/api/v1/dashboard")
  |> should.be_false()
}

pub fn route_dashboard_returns_html_test() {
  let html = mini_app_routes.route("/mini-app/dashboard")
  html |> string.contains("<!DOCTYPE html>") |> should.be_true()
  html |> string.contains("telegram-web-app.js") |> should.be_true()
  html |> string.contains("tg-nav-bar") |> should.be_true()
}

pub fn route_alerts_returns_html_test() {
  let html = mini_app_routes.route("/mini-app/alerts")
  html |> string.contains("Cockpit") |> should.be_true()
}

pub fn route_unknown_falls_back_to_dashboard_test() {
  let html = mini_app_routes.route("/mini-app/nonexistent")
  html |> string.contains("C3I Mesh") |> should.be_true()
}
