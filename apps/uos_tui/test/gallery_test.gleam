import gleam/option.{Some}
import gleam/string
import gleeunit/should
import uos_tui/aspects
import uos_tui/frame
import uos_tui/gallery
import uos_tui/geometry.{Size}
import uos_tui/headless
import uos_tui/widget

fn model() -> gallery.Model {
  gallery.init_model("2026-09-07T00:00:00Z", "test-change")
}

pub fn renders_headlessly_at_120x40_without_panicking_test() {
  let run = headless.run(gallery.app(model()), Size(120, 40), [])
  let text = frame.to_text(headless.last_frame(run))
  should.be_true(string.length(text) > 0)
}

pub fn contains_tailnet_fqdn_test() {
  let run = headless.run(gallery.app(model()), Size(120, 40), [])
  let text = frame.to_text(headless.last_frame(run))
  should.be_true(string.contains(text, aspects.tailnet_fqdn))
}

pub fn checklist_mounted_test() {
  case widget.find(gallery.view(model()), "checklist") {
    Some(widget.Checklist(..)) -> Nil
    _ -> should.fail()
  }
}
