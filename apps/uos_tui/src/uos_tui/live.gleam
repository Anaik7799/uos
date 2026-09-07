//// Live terminal driver (Textual `Driver` + `App.run` reference) on OTP.
//// One actor owns the `app.State`; a reader process turns stdin bytes into `KeyPress`
//// events; a ticker sends `Tick`s; `Task` effects run in spawned processes and
//// deliver their `msg` back to the actor. Raw mode and size come from pure Erlang APIs.
//// STAMP: SC-TUI-LIVE-001 (no side effect outside this module and the FFI shim).

import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import uos_tui/app.{type App, type State}
import uos_tui/event.{type Event}
import uos_tui/frame
import uos_tui/geometry.{type Size, Size}

pub type Message(msg) {
  Incoming(Event)
  Dispatch(msg)
  Stop
}

pub type Options {
  Options(tick_ms: Int, fallback_size: Size, raw_mode: Bool)
}

pub const default_options = Options(
  tick_ms: 250,
  fallback_size: Size(120, 40),
  raw_mode: True,
)

@external(erlang, "uos_tui_ffi", "enter_raw")
fn enter_raw() -> Result(Nil, String)

@external(erlang, "uos_tui_ffi", "size")
fn terminal_size() -> Result(#(Int, Int), Nil)

@external(erlang, "uos_tui_ffi", "read_chars")
fn read_chars(count: Int) -> Result(String, Nil)

@external(erlang, "uos_tui_ffi", "write")
fn write(data: String) -> Nil

@external(erlang, "uos_tui_ffi", "monotonic_micros")
pub fn monotonic_micros() -> Int

@external(erlang, "uos_tui_ffi", "utc_iso8601")
pub fn utc_now() -> String

const alt_screen_on = "\u{001b}[?1049h\u{001b}[?25l\u{001b}[H"

const alt_screen_off = "\u{001b}[?25h\u{001b}[?1049l"

/// Current terminal size, or the fallback when not attached to a tty.
pub fn probe_size(fallback: Size) -> Size {
  case terminal_size() {
    Ok(#(w, h)) if w > 0 && h > 0 -> Size(w, h)
    _ -> fallback
  }
}

type Loop(model, msg) {
  Loop(
    state: State(model, msg),
    self: Subject(Message(msg)),
    exit: Subject(Nil),
    last_size: Size,
  )
}

/// Start the driver as an OTP actor. Returns the actor's subject; `exit` receives `Nil` on quit.
pub fn start(
  app: App(model, msg),
  options: Options,
  exit: Subject(Nil),
) -> Result(Subject(Message(msg)), actor.StartError) {
  actor.new_with_initialiser(1000, fn(self) {
    let size = probe_size(options.fallback_size)
    let #(state, effect) = app.start(app, size)
    let #(state, residual) = app.apply_effect(state, effect)
    run_tasks(residual, self)
    case options.raw_mode {
      True -> {
        let _ = enter_raw()
        write(alt_screen_on)
      }
      False -> Nil
    }
    process.spawn(fn() { reader(self) })
    process.spawn(fn() { ticker(self, options.tick_ms) })
    let state = paint(state)
    Loop(state, self, exit, size)
    |> actor.initialised
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

/// Child specification so the driver can live under `uos_sup` (aspect 4).
pub fn child_spec(
  app: App(model, msg),
  options: Options,
  exit: Subject(Nil),
) -> ChildSpecification(Subject(Message(msg))) {
  supervision.worker(fn() {
    start(app, options, exit)
    |> result.map(fn(subject) {
      actor.Started(pid: process.self(), data: subject)
    })
  })
}

fn handle(
  loop: Loop(model, msg),
  message: Message(msg),
) -> actor.Next(Loop(model, msg), Message(msg)) {
  case message {
    Stop -> finish(loop)
    Incoming(ev) -> {
      let #(state, effect) = app.step(loop.state, ev)
      after_step(loop, state, effect)
    }
    Dispatch(msg) -> {
      let #(state, effect) = app.dispatch(loop.state, msg)
      after_step(loop, state, effect)
    }
  }
}

fn after_step(
  loop: Loop(model, msg),
  state: State(model, msg),
  effect: app.Effect(msg),
) -> actor.Next(Loop(model, msg), Message(msg)) {
  let #(state, residual) = app.apply_effect(state, effect)
  run_tasks(residual, loop.self)
  case state.quit {
    True -> finish(Loop(..loop, state: state))
    False -> {
      // Resize detection on every tick/key: cheap and avoids SIGWINCH plumbing.
      let size = probe_size(loop.last_size)
      let state = case size == loop.last_size {
        True -> state
        False -> app.step(state, event.Resize(size)).0
      }
      actor.continue(Loop(..loop, state: paint(state), last_size: size))
    }
  }
}

fn finish(
  loop: Loop(model, msg),
) -> actor.Next(Loop(model, msg), Message(msg)) {
  write(alt_screen_off)
  process.send(loop.exit, Nil)
  actor.stop()
}

fn paint(state: State(model, msg)) -> State(model, msg) {
  let started = monotonic_micros()
  let f = app.render(state)
  write("\u{001b}[H" <> frame.to_ansi(f))
  let micros = monotonic_micros() - started
  let #(state, _) =
    app.apply_effect(state, app.Telemetry("FrameMicros", int_to_string(micros)))
  app.frame_rendered(state)
}

fn int_to_string(i: Int) -> String {
  case i < 0 {
    True -> "-" <> int_to_string(0 - i)
    False -> digits(i, "")
  }
}

fn digits(i: Int, acc: String) -> String {
  let d = case i % 10 {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    4 -> "4"
    5 -> "5"
    6 -> "6"
    7 -> "7"
    8 -> "8"
    _ -> "9"
  }
  case i < 10 {
    True -> d <> acc
    False -> digits(i / 10, d <> acc)
  }
}

fn run_tasks(effect: app.Effect(msg), self: Subject(Message(msg))) -> Nil {
  app.tasks(effect)
  |> list.each(fn(task) {
    process.spawn(fn() { process.send(self, Dispatch(task())) })
  })
}

fn reader(self: Subject(Message(msg))) -> Nil {
  case read_chars(1024) {
    Ok(data) -> {
      event.parse_keys(data)
      |> list.each(fn(k) { process.send(self, Incoming(event.KeyPress(k))) })
      reader(self)
    }
    Error(_) -> process.send(self, Stop)
  }
}

fn ticker(self: Subject(Message(msg)), interval: Int) -> Nil {
  process.sleep(interval)
  process.send(self, Incoming(event.Tick(interval)))
  ticker(self, interval)
}

/// Convenience: run until the app quits.
pub fn run(
  app: App(model, msg),
  options: Options,
) -> Result(Nil, actor.StartError) {
  let exit = process.new_subject()
  use _ <- result.map(start(app, options, exit))
  process.receive_forever(exit)
}

/// Read-only projection for non-tty callers (Wisp, MCP): one frame as text.
pub fn snapshot_text(app: App(model, msg), size: Size) -> String {
  let #(state, effect) = app.start(app, size)
  let #(state, _) = app.apply_effect(state, effect)
  frame.to_text(app.render(state))
}

pub fn opt_size(size: option.Option(Size), fallback: Size) -> Size {
  case size {
    Some(s) -> s
    None -> fallback
  }
}
