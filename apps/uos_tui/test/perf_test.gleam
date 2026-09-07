import gleam/int
import gleam/list
import gleeunit/should
import prng
import uos_tui/cockpit.{Container}
import uos_tui/event.{KeyPress}
import uos_tui/geometry.{Size}
import uos_tui/headless
import uos_tui/live

// Performance gate: 200 cockpit frames at 120x40 must average under 16ms each (AOR-GLM-UI-008 budget).
pub fn frame_budget_test() {
  let m =
    cockpit.Model(
      ..cockpit.init_model("2026-09-06T21:23:36Z", "kxqzrlmp"),
      containers: prng.range(1, 40)
        |> list.map(fn(i) {
          Container("c" <> int.to_string(i), "T1", "running", 0.5)
        }),
    )
  let events =
    prng.range(1, 200)
    |> list.map(fn(i) { KeyPress(event.Char(int.to_string(i % 8 + 1))) })
  let started = live.monotonic_micros()
  let run = headless.run(cockpit.app(m), Size(120, 40), events)
  let elapsed = live.monotonic_micros() - started
  list.length(run.frames) |> should.equal(201)
  let per_frame_us = elapsed / 201
  { per_frame_us < 16_000 } |> should.be_true
}
