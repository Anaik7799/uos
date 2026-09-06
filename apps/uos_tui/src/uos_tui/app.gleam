//// Application core (Textual `App`, `Screen` stack, `Binding`/actions, reactive re-render reference)
//// expressed as The Elm Architecture. `step` is a pure state transition; all side effects are
//// returned as `Effect` values for a driver (headless or live) to execute.
//// STAMP: SC-TUI-APP-001 (determinism: same events, same frames).

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import uos_tui/event.{type Event, type Key}
import uos_tui/frame.{type Frame}
import uos_tui/geometry.{type Size, Size}
import uos_tui/render.{type Theme}
import uos_tui/widget.{type Binding, type Widget, Binding}

/// Side effects requested by `update`. Drivers execute them; `step` never does.
pub type Effect(msg) {
  NoEffect
  Batch(List(Effect(msg)))
  Task(fn() -> msg)
  PushScreen(String)
  PopScreen
  FocusWidget(String)
  Telemetry(channel: String, value: String)
  Quit
}

pub type Screen(model, msg) {
  Screen(name: String, view: fn(model) -> Widget(msg))
}

pub type App(model, msg) {
  App(
    name: String,
    init: fn(Size) -> #(model, Effect(msg)),
    update: fn(model, msg) -> #(model, Effect(msg)),
    screens: List(Screen(model, msg)),
    initial_screen: String,
    bindings: List(Binding(msg)),
    theme: Theme,
  )
}

/// Runtime state owned by the driver.
pub type State(model, msg) {
  State(
    app: App(model, msg),
    model: model,
    size: Size,
    screen_stack: List(String),
    focus: Option(String),
    frame_count: Int,
    telemetry: Dict(String, String),
    quit: Bool,
  )
}

/// Build the initial state and the effects `init` requested.
pub fn start(
  app: App(model, msg),
  size: Size,
) -> #(State(model, msg), Effect(msg)) {
  let #(model, effect) = app.init(size)
  let state =
    State(
      app: app,
      model: model,
      size: size,
      screen_stack: [app.initial_screen],
      focus: None,
      frame_count: 0,
      telemetry: dict.new(),
      quit: False,
    )
  let state = ensure_focus(state)
  #(state, effect)
}

fn current_screen(state: State(model, msg)) -> Option(Screen(model, msg)) {
  case state.screen_stack {
    [name, ..] ->
      list.find(state.app.screens, fn(s) { s.name == name })
      |> option.from_result
    [] -> None
  }
}

/// The widget tree for the current screen.
pub fn view(state: State(model, msg)) -> Widget(msg) {
  case current_screen(state) {
    Some(screen) -> screen.view(state.model)
    None ->
      widget.Static(
        "missing-screen",
        "no screen: " <> string.join(state.screen_stack, "/"),
        state.app.theme.danger,
      )
  }
}

/// Render the current screen.
pub fn render(state: State(model, msg)) -> Frame {
  render.compose(view(state), state.size, state.focus, state.app.theme)
}

fn ensure_focus(state: State(model, msg)) -> State(model, msg) {
  let chain = widget.focus_chain(view(state))
  case state.focus {
    Some(id) ->
      case list.contains(chain, id) {
        True -> state
        False -> State(..state, focus: list.first(chain) |> option.from_result)
      }
    None -> State(..state, focus: list.first(chain) |> option.from_result)
  }
}

fn move_focus(state: State(model, msg), delta: Int) -> State(model, msg) {
  let chain = widget.focus_chain(view(state))
  let n = list.length(chain)
  case n {
    0 -> State(..state, focus: None)
    _ -> {
      let current = case state.focus {
        Some(id) -> index_of(chain, id) |> option.unwrap(-1)
        None -> -1
      }
      let next = { { current + delta } % n + n } % n
      State(
        ..state,
        focus: chain |> list.drop(next) |> list.first |> option.from_result,
      )
    }
  }
}

fn index_of(items: List(String), item: String) -> Option(Int) {
  list.index_fold(items, None, fn(acc, x, i) {
    case acc, x == item {
      None, True -> Some(i)
      _, _ -> acc
    }
  })
}

/// Apply one event: returns the new state plus effects to execute.
pub fn step(
  state: State(model, msg),
  event: Event,
) -> #(State(model, msg), Effect(msg)) {
  case event {
    event.Mount -> #(state, NoEffect)
    event.Resize(size) -> #(State(..state, size: clamp_size(size)), NoEffect)
    event.Tick(_) -> #(state, NoEffect)
    event.Paste(text) -> paste(state, text)
    event.KeyPress(key) -> key_press(state, key)
  }
}

fn clamp_size(size: Size) -> Size {
  Size(int.max(size.width, 0), int.max(size.height, 0))
}

fn paste(
  state: State(model, msg),
  text: String,
) -> #(State(model, msg), Effect(msg)) {
  case focused_widget(state) {
    Some(widget.Input(_, value, cursor, _, on_change, _)) -> {
      let cursor = int.clamp(cursor, 0, string.length(value))
      let new =
        string.slice(value, 0, cursor)
        <> text
        <> string.drop_start(value, cursor)
      dispatch(state, on_change(new))
    }
    _ -> #(state, NoEffect)
  }
}

fn focused_widget(state: State(model, msg)) -> Option(Widget(msg)) {
  case state.focus {
    Some(id) -> widget.find(view(state), id)
    None -> None
  }
}

fn key_press(
  state: State(model, msg),
  key: Key,
) -> #(State(model, msg), Effect(msg)) {
  // 1. Focused widget consumes navigation/editing keys first (Textual: widget bindings before app bindings).
  case widget_key(state, key) {
    Some(result) -> result
    None ->
      case key {
        event.Tab -> #(move_focus(state, 1), NoEffect)
        event.BackTab -> #(move_focus(state, -1), NoEffect)
        _ ->
          // 2. App-level bindings.
          case list.find(state.app.bindings, fn(b) { b.key == key }) {
            Ok(Binding(_, action, _)) -> dispatch(state, action)
            Error(_) -> #(state, NoEffect)
          }
      }
  }
}

fn widget_key(
  state: State(model, msg),
  key: Key,
) -> Option(#(State(model, msg), Effect(msg))) {
  case focused_widget(state) {
    Some(widget.Button(_, _, on_press)) ->
      case key {
        event.Enter | event.Char(" ") -> Some(dispatch(state, on_press))
        _ -> None
      }
    Some(widget.Input(_, value, cursor, _, on_change, on_submit)) -> {
      let cursor = int.clamp(cursor, 0, string.length(value))
      case key {
        event.Char(c) ->
          Some(dispatch(
            state,
            on_change(
              string.slice(value, 0, cursor)
              <> c
              <> string.drop_start(value, cursor),
            ),
          ))
        event.Backspace ->
          case cursor > 0 {
            True ->
              Some(dispatch(
                state,
                on_change(
                  string.slice(value, 0, cursor - 1)
                  <> string.drop_start(value, cursor),
                ),
              ))
            False -> Some(#(state, NoEffect))
          }
        event.Delete ->
          Some(dispatch(
            state,
            on_change(
              string.slice(value, 0, cursor)
              <> string.drop_start(value, cursor + 1),
            ),
          ))
        event.Enter ->
          case on_submit {
            Some(m) -> Some(dispatch(state, m))
            None -> Some(#(state, NoEffect))
          }
        _ -> None
      }
    }
    Some(widget.ListView(_, items, cursor, on_move, on_select)) ->
      cursor_keys(state, key, cursor, list.length(items), on_move, on_select)
    Some(widget.DataTable(_, _, rows, cursor, on_move, on_select)) ->
      cursor_keys(state, key, cursor, list.length(rows), on_move, on_select)
    Some(widget.Tree(_, root, cursor, on_move)) ->
      cursor_keys(
        state,
        key,
        cursor,
        list.length(widget.tree_rows(root)),
        on_move,
        None,
      )
    Some(widget.Tabs(_, labels, active, on_change)) ->
      case key, on_change {
        event.Left, Some(f) ->
          Some(dispatch(state, f(wrap(active - 1, list.length(labels)))))
        event.Right, Some(f) ->
          Some(dispatch(state, f(wrap(active + 1, list.length(labels)))))
        _, _ -> None
      }
    Some(widget.Checklist(_, domains, _, on_toggle)) ->
      case key, on_toggle {
        event.Char(c), Some(f) -> {
          let count = list.length(domains)
          case int.parse(c) {
            Ok(n) if n >= 1 && n <= count -> Some(dispatch(state, f(n - 1)))
            _ -> None
          }
        }
        _, _ -> None
      }
    _ -> None
  }
}

fn wrap(i: Int, n: Int) -> Int {
  case n {
    0 -> 0
    _ -> { i % n + n } % n
  }
}

fn cursor_keys(
  state: State(model, msg),
  key: Key,
  cursor: Int,
  count: Int,
  on_move: Option(fn(Int) -> msg),
  on_select: Option(fn(Int) -> msg),
) -> Option(#(State(model, msg), Effect(msg))) {
  let bounded = fn(i) { int.clamp(i, 0, int.max(count - 1, 0)) }
  case key, on_move, on_select {
    event.Up, Some(f), _ -> Some(dispatch(state, f(bounded(cursor - 1))))
    event.Down, Some(f), _ -> Some(dispatch(state, f(bounded(cursor + 1))))
    event.PageUp, Some(f), _ -> Some(dispatch(state, f(bounded(cursor - 10))))
    event.PageDown, Some(f), _ -> Some(dispatch(state, f(bounded(cursor + 10))))
    event.Home, Some(f), _ -> Some(dispatch(state, f(0)))
    event.End, Some(f), _ -> Some(dispatch(state, f(bounded(count - 1))))
    event.Enter, _, Some(f) -> Some(dispatch(state, f(bounded(cursor))))
    _, _, _ -> None
  }
}

/// Route a message through `update`, then apply the driver-independent effects
/// (screen stack, focus, telemetry, quit). Remaining effects are returned for the driver.
pub fn dispatch(
  state: State(model, msg),
  msg: msg,
) -> #(State(model, msg), Effect(msg)) {
  let #(model, effect) = state.app.update(state.model, msg)
  let state = State(..state, model: model)
  let #(state, residual) = apply_effect(state, effect)
  #(ensure_focus(state), residual)
}

/// Apply pure effects; return the residual (Task) effects.
pub fn apply_effect(
  state: State(model, msg),
  effect: Effect(msg),
) -> #(State(model, msg), Effect(msg)) {
  case effect {
    NoEffect -> #(state, NoEffect)
    Batch(effects) -> {
      let #(state, residuals) =
        list.fold(effects, #(state, []), fn(acc, e) {
          let #(s, rs) = acc
          let #(s, r) = apply_effect(s, e)
          #(s, [r, ..rs])
        })
      #(state, Batch(list.reverse(residuals)))
    }
    Task(_) -> #(state, effect)
    PushScreen(name) ->
      case list.any(state.app.screens, fn(s) { s.name == name }) {
        True -> #(
          State(
            ..state,
            screen_stack: [name, ..state.screen_stack],
            focus: None,
          ),
          NoEffect,
        )
        False -> #(state, NoEffect)
      }
    PopScreen ->
      case state.screen_stack {
        [_, ..rest] if rest != [] -> #(
          State(..state, screen_stack: rest, focus: None),
          NoEffect,
        )
        _ -> #(state, NoEffect)
      }
    FocusWidget(id) -> #(State(..state, focus: Some(id)), NoEffect)
    Telemetry(channel, value) -> #(
      State(..state, telemetry: dict.insert(state.telemetry, channel, value)),
      NoEffect,
    )
    Quit -> #(State(..state, quit: True), NoEffect)
  }
}

/// Collect the tasks a driver must run from a residual effect.
pub fn tasks(effect: Effect(msg)) -> List(fn() -> msg) {
  case effect {
    Task(f) -> [f]
    Batch(effects) -> list.flat_map(effects, tasks)
    _ -> []
  }
}

/// Count a rendered frame.
pub fn frame_rendered(state: State(model, msg)) -> State(model, msg) {
  State(..state, frame_count: state.frame_count + 1)
}
