import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import uos_tui/app.{App, Screen}
import uos_tui/event.{KeyPress}
import uos_tui/frame
import uos_tui/geometry.{Size}
import uos_tui/headless
import uos_tui/layout.{Cells, Vertical}
import uos_tui/render
import uos_tui/widget.{Binding}

type Model {
  Model(count: Int, text: String, cursor: Int, log: List(String))
}

type Msg {
  Inc
  Typed(String)
  Submitted
  Moved(Int)
  Picked(Int)
  Open
  Close
  Async
  Done(String)
  Bye
}

fn view(m: Model) -> widget.Widget(Msg) {
  widget.Container(
    "root",
    Vertical,
    [
      #(
        Cells(1),
        widget.Static(
          "count",
          "count=" <> string.inspect(m.count),
          render.dark.base,
        ),
      ),
      #(Cells(1), widget.Button("inc", "Inc", Inc)),
      #(
        Cells(1),
        widget.Input(
          "in",
          m.text,
          string.length(m.text),
          "type",
          Typed,
          Some(Submitted),
        ),
      ),
      #(
        Cells(3),
        widget.ListView(
          "list",
          ["a", "b", "c"],
          m.cursor,
          Some(Moved),
          Some(Picked),
        ),
      ),
      #(Cells(2), widget.Log("log", m.log, 0)),
    ],
    False,
    "",
  )
}

fn modal(_m: Model) -> widget.Widget(Msg) {
  widget.Container(
    "modal",
    Vertical,
    [#(Cells(1), widget.Button("close", "Close", Close))],
    True,
    "Modal",
  )
}

fn test_app() -> app.App(Model, Msg) {
  App(
    name: "t",
    init: fn(_) { #(Model(0, "", 0, []), app.NoEffect) },
    update: fn(m, msg) {
      case msg {
        Inc -> #(Model(..m, count: m.count + 1), app.NoEffect)
        Typed(t) -> #(Model(..m, text: t), app.NoEffect)
        Submitted -> #(
          Model(..m, log: list.append(m.log, ["submit:" <> m.text]), text: ""),
          app.NoEffect,
        )
        Moved(i) -> #(Model(..m, cursor: i), app.NoEffect)
        Picked(i) -> #(
          Model(..m, log: list.append(m.log, ["picked:" <> string.inspect(i)])),
          app.NoEffect,
        )
        Open -> #(m, app.PushScreen("modal"))
        Close -> #(m, app.PopScreen)
        Async -> #(m, app.Task(fn() { Done("task-result") }))
        Done(s) -> #(
          Model(..m, log: list.append(m.log, [s])),
          app.Telemetry("done", s),
        )
        Bye -> #(m, app.Quit)
      }
    },
    screens: [Screen("main", view), Screen("modal", modal)],
    initial_screen: "main",
    bindings: [
      Binding(event.Char("o"), Open, "open"),
      Binding(event.Char("a"), Async, "async"),
      Binding(event.Char("q"), Bye, "quit"),
    ],
    theme: render.dark,
  )
}

fn keys(s: String) -> List(event.Event) {
  event.parse_keys(s) |> list.map(KeyPress)
}

pub fn initial_focus_is_first_focusable_test() {
  let run = headless.run(test_app(), Size(30, 10), [])
  run.state.focus |> should.equal(Some("inc"))
  list.length(run.frames) |> should.equal(1)
}

pub fn enter_on_button_dispatches_test() {
  let run = headless.run(test_app(), Size(30, 10), keys("\r\r"))
  run.state.model.count |> should.equal(2)
  headless.last_frame(run)
  |> frame.to_text
  |> string.contains("count=2")
  |> should.be_true
}

pub fn tab_cycles_focus_and_wraps_test() {
  let run = headless.run(test_app(), Size(30, 10), keys("\t"))
  run.state.focus |> should.equal(Some("in"))
  let run = headless.run(test_app(), Size(30, 10), keys("\t\t\t"))
  run.state.focus |> should.equal(Some("inc"))
  let run = headless.run(test_app(), Size(30, 10), keys("\u{001b}[Z"))
  run.state.focus |> should.equal(Some("list"))
}

pub fn typing_into_input_then_submit_test() {
  let run = headless.run(test_app(), Size(30, 10), keys("\thi!\u{007f}\r"))
  run.state.model.log |> should.equal(["submit:hi"])
  run.state.model.text |> should.equal("")
}

pub fn list_navigation_bounded_and_select_test() {
  let run =
    headless.run(
      test_app(),
      Size(30, 10),
      keys("\t\t\u{001b}[B\u{001b}[B\u{001b}[B\u{001b}[B\r"),
    )
  run.state.model.cursor |> should.equal(2)
  run.state.model.log |> should.equal(["picked:2"])
}

pub fn app_binding_pushes_and_pops_screen_test() {
  let run = headless.run(test_app(), Size(30, 10), keys("o"))
  run.state.screen_stack |> should.equal(["modal", "main"])
  run.state.focus |> should.equal(Some("close"))
  headless.last_frame(run)
  |> frame.to_text
  |> string.contains("Modal")
  |> should.be_true
  let run = headless.run(test_app(), Size(30, 10), keys("o\r"))
  run.state.screen_stack |> should.equal(["main"])
}

pub fn pop_never_empties_stack_test() {
  let run = headless.run(test_app(), Size(30, 10), [])
  let #(s, _) = app.apply_effect(run.state, app.PopScreen)
  s.screen_stack |> should.equal(["main"])
}

pub fn push_unknown_screen_ignored_test() {
  let run = headless.run(test_app(), Size(30, 10), [])
  let #(s, _) = app.apply_effect(run.state, app.PushScreen("nope"))
  s.screen_stack |> should.equal(["main"])
}

pub fn task_effect_runs_headless_and_records_telemetry_test() {
  let run = headless.run(test_app(), Size(30, 10), keys("a"))
  run.state.model.log |> should.equal(["task-result"])
  dict.get(run.state.telemetry, "done") |> should.equal(Ok("task-result"))
}

pub fn quit_stops_processing_test() {
  let run = headless.run(test_app(), Size(30, 10), keys("q\r\r"))
  run.state.quit |> should.be_true
  run.state.model.count |> should.equal(0)
}

pub fn resize_changes_frame_size_test() {
  let run = headless.run(test_app(), Size(30, 10), [event.Resize(Size(12, 4))])
  headless.last_frame(run).size |> should.equal(Size(12, 4))
  headless.last_frame(run) |> frame.is_well_formed |> should.be_true
}

pub fn paste_inserts_into_focused_input_test() {
  let run =
    headless.run(test_app(), Size(30, 10), [
      KeyPress(event.Tab),
      event.Paste("xy"),
    ])
  run.state.model.text |> should.equal("xy")
}

pub fn frames_are_deterministic_test() {
  let a = headless.run(test_app(), Size(30, 10), keys("\thello\r\u{001b}[B"))
  let b = headless.run(test_app(), Size(30, 10), keys("\thello\r\u{001b}[B"))
  list.map(a.frames, frame.to_text)
  |> should.equal(list.map(b.frames, frame.to_text))
}

pub fn missing_screen_renders_error_not_crash_test() {
  let bad = App(..test_app(), initial_screen: "ghost")
  let run = headless.run(bad, Size(30, 3), [])
  headless.last_frame(run)
  |> frame.to_text
  |> string.contains("no screen")
  |> should.be_true
  run.state.focus |> should.equal(None)
}
