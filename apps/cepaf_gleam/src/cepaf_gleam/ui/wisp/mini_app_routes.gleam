//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/ui/wisp/mini_app_routes</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-OPENCLAW-001, SC-SEC-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Telegram Mini App HTTP routes — serves mobile-optimized SSR HTML.
//// Route prefix: /mini-app/*
//// All pages wrapped in TeleNative HTML shell with Telegram CSS variables.
//// STAMP: SC-GLM-UI-001, SC-OPENCLAW-001, SC-SEC-001
import cepaf_gleam/telegram/theme
import cepaf_gleam/telegram/types.{
  TabAlerts, TabDashboard, TabSystem, TabTasks,
}
import cepaf_gleam/ui/lustre/mini_app
import gleam/string
/// Route a /mini-app/* path to the appropriate handler.
/// Returns full HTML string ready for HTTP response body.
pub fn route(path: String) -> String {
  let page_content = case path {
    "/mini-app/dashboard" | "/mini-app" | "/mini-app/" ->
      mini_app.dashboard_view()
    "/mini-app/health" -> mini_app.health_grid_view()
    "/mini-app/alerts" -> mini_app.cockpit_view()
    "/mini-app/immune" -> mini_app.immune_view()
    "/mini-app/tasks" -> mini_app.planning_view()
    "/mini-app/inference" -> mini_app.inference_view()
    "/mini-app/chat" -> mini_app.conversation_view()
    "/mini-app/config" -> mini_app.config_view()
    "/mini-app/containers" -> mini_app.podman_view()
    "/mini-app/federation" -> mini_app.federation_view()
    "/mini-app/verify" -> mini_app.verification_view()
    "/mini-app/fmea" -> mini_app.fmea_view()
    "/mini-app/telemetry" -> mini_app.telemetry_view()
    "/mini-app/zenoh" -> mini_app.zenoh_browser_view()
    _ -> mini_app.dashboard_view()
  }
  let active_tab = case path {
    "/mini-app/alerts" | "/mini-app/immune" -> TabAlerts
    "/mini-app/tasks" | "/mini-app/chat" -> TabTasks
    "/mini-app/inference" | "/mini-app/config" | "/mini-app/containers"
    | "/mini-app/federation"
    | "/mini-app/verify"
    | "/mini-app/fmea"
    | "/mini-app/zenoh"
    -> TabSystem
    _ -> TabDashboard
  }
  render_shell(page_content, active_tab)
}
/// Check if a path belongs to the Mini App routes.
pub fn is_mini_app_path(path: String) -> Bool {
  string.starts_with(path, "/mini-app")
}
/// Render the TeleNative HTML shell with content and bottom navigation.
fn render_shell(content: String, active_tab: types.NavTab) -> String {
  let css = theme.mini_app_css()
  let nav = render_nav_bar(active_tab)
  "<!DOCTYPE html>
<html>
<head>
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no\">
<title>C3I</title>
<script src=\"https://telegram.org/js/telegram-web-app.js\"></script>
<style>"
  <> css
  <> "</style>
</head>
<body>
"
  <> content
  <> nav
  <> "
<script>
// Initialize Telegram WebApp
if (window.Telegram && window.Telegram.WebApp) {
  const tg = window.Telegram.WebApp;
  tg.ready();
  tg.expand();
  // Apply haptic feedback to all buttons
  document.querySelectorAll('.tg-btn, .tg-action-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      if (tg.HapticFeedback) tg.HapticFeedback.impactOccurred('light');
    });
  });
}
// Navigation handler
document.querySelectorAll('[data-navigate]').forEach(el => {
  el.addEventListener('click', (e) => {
    e.preventDefault();
    window.location.href = el.getAttribute('data-navigate');
  });
});
</script>
</body>
</html>"
}
/// Render the 4-tab bottom navigation bar.
fn render_nav_bar(active: types.NavTab) -> String {
  let dashboard_class = case active {
    TabDashboard -> "tg-nav-item active"
    _ -> "tg-nav-item"
  }
  let alerts_class = case active {
    TabAlerts -> "tg-nav-item active"
    _ -> "tg-nav-item"
  }
  let tasks_class = case active {
    TabTasks -> "tg-nav-item active"
    _ -> "tg-nav-item"
  }
  let system_class = case active {
    TabSystem -> "tg-nav-item active"
    _ -> "tg-nav-item"
  }
  "<nav class=\"tg-nav-bar\">
  <a href=\"/mini-app/dashboard\" class=\""
  <> dashboard_class
  <> "\"><span class=\"tg-nav-icon\">&#9776;</span>Home</a>
  <a href=\"/mini-app/alerts\" class=\""
  <> alerts_class
  <> "\"><span class=\"tg-nav-icon\">&#9888;</span>Alerts</a>
  <a href=\"/mini-app/tasks\" class=\""
  <> tasks_class
  <> "\"><span class=\"tg-nav-icon\">&#9745;</span>Tasks</a>
  <a href=\"/mini-app/inference\" class=\""
  <> system_class
  <> "\"><span class=\"tg-nav-icon\">&#9881;</span>System</a>
</nav>"
}
