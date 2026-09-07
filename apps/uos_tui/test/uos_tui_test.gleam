import gleam/json
import gleam/string
import gleeunit
import gleeunit/should
import uos_tui/aspects
import uos_tui/features
import uos_tui/fprime
import uos_tui/gallery
import uos_tui/geometry.{Size}
import uos_tui/live

pub fn main() -> Nil {
  gleeunit.main()
}

// Regression: the `dictionary` CLI command must always produce non-empty F´ ground
// dictionary JSON carrying a "commands" section.
pub fn dictionary_command_produces_json_test() {
  let text = fprime.dictionary_string()
  should.be_true(string.length(text) > 0)
  should.be_true(string.contains(text, "\"commands\""))
}

// Regression: the `features` CLI command renders a non-empty Markdown feature sheet using
// the TUI CLI's own bindings argument (`[]`, per uos_tui.gleam main/0).
pub fn features_command_renders_markdown_test() {
  let md = features.to_markdown(features.sheet([]))
  should.be_true(string.contains(md, "# uos_tui Feature Sheet"))
}

// Regression: the `features-json` CLI command renders valid JSON.
pub fn features_json_command_renders_json_test() {
  let text = json.to_string(features.to_json(features.sheet([])))
  should.be_true(string.starts_with(text, "{"))
}

// Regression: the `snapshot` command (and the default live driver) render the gallery app
// at 120x40 without panicking, and the frame carries the mandatory Tailscale FQDN.
pub fn snapshot_command_renders_gallery_test() {
  let model = gallery.init_model("2026-09-07T00:00:00Z", "test-change")
  let text = live.snapshot_text(gallery.app(model), Size(120, 40))
  should.be_true(string.contains(text, aspects.tailnet_fqdn))
}
