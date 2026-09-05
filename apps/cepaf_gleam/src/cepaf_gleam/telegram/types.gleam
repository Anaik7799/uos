//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/telegram/types</module></identity>
////   <fractal-topology><layer>L2_COMPONENT</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-OPENCLAW-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Shared types for Telegram Mini App integration.
//// STAMP: SC-GLM-UI-001, SC-OPENCLAW-001

/// Mini App page — subset of domain.Page optimized for mobile.
pub type MiniAppPage {
  MiniDashboard
  MiniHealthGrid
  MiniCockpit
  MiniImmune
  MiniPlanning
  MiniInference
  MiniConversation
  MiniConfig
  MiniPodman
  MiniFederation
  MiniVerification
  MiniFmea
  MiniTelemetry
  MiniZenohBrowser
}

/// Convert MiniAppPage to URL path fragment.
pub fn page_to_path(page: MiniAppPage) -> String {
  case page {
    MiniDashboard -> "/mini-app/dashboard"
    MiniHealthGrid -> "/mini-app/health"
    MiniCockpit -> "/mini-app/alerts"
    MiniImmune -> "/mini-app/immune"
    MiniPlanning -> "/mini-app/tasks"
    MiniInference -> "/mini-app/inference"
    MiniConversation -> "/mini-app/chat"
    MiniConfig -> "/mini-app/config"
    MiniPodman -> "/mini-app/containers"
    MiniFederation -> "/mini-app/federation"
    MiniVerification -> "/mini-app/verify"
    MiniFmea -> "/mini-app/fmea"
    MiniTelemetry -> "/mini-app/telemetry"
    MiniZenohBrowser -> "/mini-app/zenoh"
  }
}

/// Human-readable label for each Mini App page.
pub fn page_to_label(page: MiniAppPage) -> String {
  case page {
    MiniDashboard -> "Dashboard"
    MiniHealthGrid -> "Health"
    MiniCockpit -> "Alerts"
    MiniImmune -> "Immune"
    MiniPlanning -> "Tasks"
    MiniInference -> "Inference"
    MiniConversation -> "Chat"
    MiniConfig -> "Config"
    MiniPodman -> "Containers"
    MiniFederation -> "Federation"
    MiniVerification -> "Verify"
    MiniFmea -> "FMEA"
    MiniTelemetry -> "Telemetry"
    MiniZenohBrowser -> "Zenoh"
  }
}

/// Bottom navigation tab — the 4 primary tabs for field operator.
pub type NavTab {
  TabDashboard
  TabAlerts
  TabTasks
  TabSystem
}

/// Map a Mini App page to its parent nav tab.
pub fn page_nav_tab(page: MiniAppPage) -> NavTab {
  case page {
    MiniDashboard | MiniHealthGrid | MiniTelemetry -> TabDashboard
    MiniCockpit | MiniImmune -> TabAlerts
    MiniPlanning | MiniConversation -> TabTasks
    MiniInference
    | MiniConfig
    | MiniPodman
    | MiniFederation
    | MiniVerification
    | MiniFmea
    | MiniZenohBrowser -> TabSystem
  }
}
