//// Headless driver (Textual `App.run_test` / `Pilot` reference).
//// Feeds a scripted event list through the app, running `Task` effects synchronously,
//// and returns every frame. Deterministic: used by unit, BDD, property, fuzz, chaos and perf tests.
//// STAMP: SC-TUI-HEADLESS-001.

import gleam/list
import uos_tui/app.{type App, type Effect, type State}
import uos_tui/event.{type Event}
import uos_tui/frame.{type Frame}
import uos_tui/geometry.{type Size}

pub type Run(model, msg) {
  Run(state: State(model, msg), frames: List(Frame))
}

/// Run `events` against `app` at `size`. Returns the final state and all frames (one per event + initial).
pub fn run(
  app: App(model, msg),
  size: Size,
  events: List(Event),
) -> Run(model, msg) {
  let #(state, effect) = app.start(app, size)
  let state = settle(state, effect)
  let first = app.render(state)
  let state = app.frame_rendered(state)
  let #(state, frames) =
    list.fold(events, #(state, [first]), fn(acc, ev) {
      let #(state, frames) = acc
      case state.quit {
        True -> acc
        False -> {
          let #(state, effect) = app.step(state, ev)
          let state = settle(state, effect)
          let frame = app.render(state)
          #(app.frame_rendered(state), [frame, ..frames])
        }
      }
    })
  Run(state, list.reverse(frames))
}

/// Execute residual tasks synchronously until no tasks remain (bounded to avoid runaway loops).
fn settle(state: State(model, msg), effect: Effect(msg)) -> State(model, msg) {
  settle_loop(state, effect, 64)
}

fn settle_loop(
  state: State(model, msg),
  effect: Effect(msg),
  budget: Int,
) -> State(model, msg) {
  let #(state, residual) = app.apply_effect(state, effect)
  case app.tasks(residual), budget > 0 {
    [], _ -> state
    _, False -> state
    tasks, True ->
      list.fold(tasks, state, fn(s, task) {
        let #(s, e) = app.dispatch(s, task())
        settle_loop(s, e, budget - 1)
      })
  }
}

/// Last frame of a run.
pub fn last_frame(run: Run(model, msg)) -> Frame {
  case list.last(run.frames) {
    Ok(f) -> f
    Error(_) -> frame.blank(run.state.size, run.state.app.theme.base)
  }
}
