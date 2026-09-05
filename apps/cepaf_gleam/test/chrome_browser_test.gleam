import cepaf_gleam/chrome/browser
import gleam/string
import gleeunit/should

pub fn planning_screenshot_config_test() {
  let config = browser.planning_screenshot()
  string.contains(config.url, "planning") |> should.be_true
  config.width |> should.equal(1400)
  config.full_page |> should.equal(True)
}

pub fn page_screenshot_config_test() {
  let config = browser.page_screenshot("/cockpit")
  string.contains(config.url, "cockpit") |> should.be_true
  string.contains(config.output_path, "cockpit") |> should.be_true
}

pub fn phase_topic_concept_test() {
  browser.phase_topic(browser.Concept)
  |> string.contains("concept")
  |> should.be_true
}

pub fn phase_topic_test_test() {
  browser.phase_topic(browser.Test)
  |> string.contains("test")
  |> should.be_true
}

pub fn phase_topic_monitor_test() {
  browser.phase_topic(browser.Monitor)
  |> string.contains("monitor")
  |> should.be_true
}

pub fn monitored_pages_includes_planning_test() {
  let pages = browser.monitored_pages()
  list.contains(pages, "/planning") |> should.be_true
}

pub fn monitored_pages_includes_miniapp_test() {
  let pages = browser.monitored_pages()
  list.contains(pages, "/mini-app/dashboard") |> should.be_true
}

pub fn playwright_command_test() {
  let cmd = browser.playwright_test_command("/planning")
  string.contains(cmd, "playwright") |> should.be_true
  string.contains(cmd, "planning") |> should.be_true
}

pub fn request_screenshot_returns_json_test() {
  let config = browser.planning_screenshot()
  let payload = browser.request_screenshot(config)
  string.contains(payload, "browser_screenshot") |> should.be_true
  string.contains(payload, "planning") |> should.be_true
}

pub fn request_dom_analysis_returns_json_test() {
  let payload = browser.request_dom_analysis("https://localhost:4100/planning")
  string.contains(payload, "browser_dom_analysis") |> should.be_true
}

pub fn request_visual_diff_returns_json_test() {
  let payload = browser.request_visual_diff("/tmp/before.png", "/tmp/after.png")
  string.contains(payload, "browser_visual_diff") |> should.be_true
}

import gleam/list
