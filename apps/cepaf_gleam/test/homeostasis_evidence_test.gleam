import cepaf_gleam/ha/homeostasis_evolution_engine as engine
import cepaf_gleam/ui/homeostasis_status as status
import cepaf_gleam/ui/tui/homeostasis_evolution_view as tui
import cepaf_gleam/ui/lustre/homeostasis_evolution_hud as hud
import cepaf_gleam/ui/lustre/homeostasis as legacy
import gleam/list
import gleam/string
import gleeunit/should
import lustre/element

fn sample() { engine.init_homeostasis_system(1_000_000) }

pub fn freshness_boundary_and_clock_rollback_test() {
  let assert Ok(snapshot) = status.observation(sample(), "fixture:a", 1_000_000, 1_000_010, 200_000)
  status.status(snapshot, 999_999) |> should.equal(status.Unavailable)
  status.status(snapshot, 1_199_999) |> should.equal(status.Observed)
  status.status(snapshot, 1_200_000) |> should.equal(status.Stale)
  status.to_json(snapshot, 1_200_000) |> string.contains("\"metrics\":null") |> should.be_true()
}

pub fn invalid_provenance_is_rejected_test() {
  status.observation(sample(), "", 1_000_000, 1_000_010, 100) |> should.be_error()
  status.observation(sample(), "a", 1_000_000, 999_999, 100) |> should.be_error()
  status.observation(sample(), "a", 1_000_001, 1_000_010, 100) |> should.be_error()
  status.observation(sample(), "a", 1_000_000, 1_000_010, 0) |> should.be_error()
  status.observation(sample(), "a", 1_000_000, 1_000_010, 60_000_001) |> should.be_error()
}

pub fn fixtures_never_become_observed_with_time_test() {
  let snapshot = status.simulated(sample())
  status.status(snapshot, 1_000_000) |> should.equal(status.Simulated)
  status.status(snapshot, 9_000_000) |> should.equal(status.Simulated)
  status.to_json(snapshot, 9_000_000) |> string.contains("\"observed_at_us\":null") |> should.be_true()
}

pub fn gui_tui_api_agree_on_evidence_state_test() {
  let assert Ok(observation) = status.observation(sample(), "fixture", 1_000_000, 1_000_000, 10)
  [status.unavailable(), status.simulated(sample()), observation]
  |> list.each(fn(snapshot) {
    [1_000_000, 1_000_010] |> list.each(fn(now) {
      let label = status.status(snapshot, now) |> status.label()
      hud.render_snapshot(snapshot, now) |> element.to_string |> string.contains(label) |> should.be_true()
      tui.render_snapshot(snapshot, now, 80, 24) |> string.contains(label) |> should.be_true()
      status.to_json(snapshot, now) |> string.contains(string.lowercase(label)) |> should.be_true()
    })
  })
}

pub fn untrusted_source_is_text_in_gui_and_terminal_test() {
  let assert Ok(snapshot) = status.observation(sample(), "<img src=x onerror=alert(1)>\u{1b}]52;c;payload\u{7}", 1_000_000, 1_000_000, 10)
  hud.render_snapshot(snapshot, 1_000_000) |> element.to_string |> string.contains("<img src=x") |> should.be_false()
  let rendered = tui.render_snapshot(snapshot, 1_000_000, 80, 24)
  string.contains(rendered, "\u{1b}") |> should.be_false()
  string.contains(rendered, "\u{7}") |> should.be_false()
  tui.safe_text("界\u{202e}x\u{9b}2J") |> should.equal("??x?2J")
}

pub fn terminal_dimensions_and_plain_fallback_are_bounded_test() {
  [#(0, 0), #(1, 1), #(40, 12), #(80, 24), #(120, 40)] |> list.each(fn(size) {
    let #(width, height) = size
    let rendered = tui.render_snapshot(status.unavailable(), 0, width, height)
    case width == 0 || height == 0 {
      True -> rendered |> should.equal("")
      False -> {
        let lines = string.split(rendered, "\n")
        { list.length(lines) <= height } |> should.be_true()
        lines |> list.each(fn(line) { { string.length(line) <= width } |> should.be_true() })
        string.contains(rendered, "\u{1b}") |> should.be_false()
      }
    }
  })
}

pub fn partial_pid_update_invalidates_previous_stability_test() {
  let original = legacy.init()
  let loaded = legacy.update(original, legacy.PidLoaded(original.pid, True, 100.0, 100))
  legacy.update(loaded, legacy.PidUpdated(0.1, 0.9, 0.7)).stable |> should.be_false()
}
