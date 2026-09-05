//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/chrome/browser</module></identity>
////   <fractal-topology><layer>L4_SYSTEM</layer></fractal-topology>
////   <compliance><stamp-controls>SC-OPENCLAW-001, SC-UIGT-008, SC-GLM-UI-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Chrome Browser Integration — Playwright-based browser control for the full
//// concept → spec → dev → test → deploy cycle.
////
//// Architecture:
////   Gleam → Zenoh NIF → publish intent → Rust sa-plan-daemon → Playwright
////   OR
////   Gleam → @playwright/mcp → Chrome DevTools Protocol → Chromium
////
//// Use Cases:
////   1. CONCEPT: Screenshot any URL, extract DOM structure for spec generation
////   2. SPEC: Compare rendered page against Allium behavioral spec
////   3. DEV: Live reload verification — code change → build → screenshot → diff
////   4. TEST: Full E2E via Playwright (already working — 68 tests, 340/340)
////   5. DEPLOY: Post-deploy smoke test — screenshot + DOM verify
////   6. MONITOR: Periodic health screenshots for dark cockpit
////
//// STAMP: SC-OPENCLAW-001 (Motor tools), SC-UIGT-008 (Wisp endpoints E2E)

import cepaf_gleam/c3i/nif as c3i_nif
import gleam/json
import gleam/string

/// Browser action result.
pub type BrowserResult {
  BrowserResult(
    status: String,
    url: String,
    screenshot_path: String,
    dom_summary: String,
    page_title: String,
    error: String,
  )
}

/// Screenshot request configuration.
pub type ScreenshotConfig {
  ScreenshotConfig(
    url: String,
    width: Int,
    height: Int,
    full_page: Bool,
    wait_ms: Int,
    output_path: String,
  )
}

/// Default screenshot config for planning page.
pub fn planning_screenshot() -> ScreenshotConfig {
  ScreenshotConfig(
    url: "https://vm-1.tail55d152.ts.net:4101/planning",
    width: 1400,
    height: 900,
    full_page: True,
    wait_ms: 5000,
    output_path: "/tmp/c3i-planning-screenshot.png",
  )
}

/// Default screenshot config for any C3I page.
pub fn page_screenshot(path: String) -> ScreenshotConfig {
  ScreenshotConfig(
    url: "https://vm-1.tail55d152.ts.net:4101" <> path,
    width: 1400,
    height: 900,
    full_page: False,
    wait_ms: 3000,
    output_path: "/tmp/c3i-page-" <> string.replace(path, "/", "-") <> ".png",
  )
}

/// Request a screenshot via Zenoh MoZ → Rust → Playwright.
pub fn request_screenshot(config: ScreenshotConfig) -> String {
  let payload =
    json.object([
      #("method", json.string("browser_screenshot")),
      #("url", json.string(config.url)),
      #("width", json.int(config.width)),
      #("height", json.int(config.height)),
      #("full_page", json.bool(config.full_page)),
      #("wait_ms", json.int(config.wait_ms)),
      #("output_path", json.string(config.output_path)),
    ])
    |> json.to_string

  // Publish via Zenoh NIF to the browser MCP topic
  let _ =
    c3i_nif.zenoh_put("indrajaal/l4/system/mcp/req/browser/screenshot", payload)
  payload
}

/// Request DOM analysis of a page.
pub fn request_dom_analysis(url: String) -> String {
  let payload =
    json.object([
      #("method", json.string("browser_dom_analysis")),
      #("url", json.string(url)),
    ])
    |> json.to_string

  let _ = c3i_nif.zenoh_put("indrajaal/l4/system/mcp/req/browser/dom", payload)
  payload
}

/// Request visual diff between two screenshots.
pub fn request_visual_diff(before_path: String, after_path: String) -> String {
  let payload =
    json.object([
      #("method", json.string("browser_visual_diff")),
      #("before", json.string(before_path)),
      #("after", json.string(after_path)),
    ])
    |> json.to_string

  let _ = c3i_nif.zenoh_put("indrajaal/l4/system/mcp/req/browser/diff", payload)
  payload
}

/// SDLC cycle phases where Chrome participates.
pub type ChromePhase {
  /// Concept: screenshot existing page, extract structure
  Concept
  /// Spec: compare rendered output against Allium spec
  SpecVerify
  /// Dev: live reload — code → build → screenshot → visual diff
  DevFeedback
  /// Test: full Playwright E2E (68 tests)
  Test
  /// Deploy: post-deploy smoke screenshot
  DeployVerify
  /// Monitor: periodic health screenshots for dark cockpit
  Monitor
}

/// Map a Chrome phase to its Zenoh topic.
pub fn phase_topic(phase: ChromePhase) -> String {
  case phase {
    Concept -> "indrajaal/l5/cog/chrome/concept"
    SpecVerify -> "indrajaal/l5/cog/chrome/spec-verify"
    DevFeedback -> "indrajaal/l4/system/chrome/dev-feedback"
    Test -> "indrajaal/l4/system/chrome/test"
    DeployVerify -> "indrajaal/l4/system/chrome/deploy-verify"
    Monitor -> "indrajaal/l2/health/chrome/monitor"
  }
}

/// All C3I pages that should be monitored.
pub fn monitored_pages() -> List(String) {
  [
    "/planning", "/dashboard", "/cockpit", "/immune", "/verification", "/zenoh",
    "/telemetry", "/federation", "/mini-app/dashboard", "/mini-app/alerts",
    "/health",
  ]
}

/// Generate Playwright test command for a page.
pub fn playwright_test_command(page_path: String) -> String {
  "npx playwright test --grep \"" <> page_path <> "\""
}
