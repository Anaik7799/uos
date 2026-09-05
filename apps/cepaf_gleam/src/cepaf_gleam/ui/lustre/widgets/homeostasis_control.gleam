import gleam/float
import gleam/result
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type HomeostasisMsg {
  SetThreshold(metric: String, value: Float)
  TriggerEquilibrium
}

pub fn view(msg_mapper: fn(HomeostasisMsg) -> msg) -> Element(msg) {
  html.div([attribute.class("homeostasis-control")], [
    html.h3([], [element.text("Interactive Homeostasis Thresholds")]),
    render_control("CPU Limit", "cpu", 0.85, msg_mapper),
    render_control("Memory Pressure", "mem", 0.75, msg_mapper),
    html.button([event.on_click(msg_mapper(TriggerEquilibrium))], [
      element.text("Trigger Equilibrium"),
    ]),
  ])
}

fn render_control(
  label: String,
  metric: String,
  current: Float,
  msg_mapper: fn(HomeostasisMsg) -> msg,
) -> Element(msg) {
  html.div([attribute.class("control-row")], [
    html.label([], [element.text(label)]),
    html.input([
      attribute.type_("range"),
      attribute.min("0"),
      attribute.max("1"),
      attribute.step("0.01"),
      attribute.value(float.to_string(current)),
      event.on_input(fn(v) {
        let val = result.unwrap(float.parse(v), current)
        msg_mapper(SetThreshold(metric, val))
      }),
    ]),
    html.span([], [element.text(float_to_string(current))]),
  ])
}

fn float_to_string(f: Float) -> String {
  let s = float.to_string(f)
  case string.length(s) > 4 {
    True -> string.slice(s, 0, 4)
    False -> s
  }
}
