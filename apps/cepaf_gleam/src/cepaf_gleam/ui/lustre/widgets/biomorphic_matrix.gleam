import gleam/float
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub type BiomorphicData {
  BiomorphicData(
    visual_balance: Float,
    cognitive_load: Float,
    ergonomic_score: Float,
  )
}

pub fn view(data: BiomorphicData) -> Element(msg) {
  html.div([attribute.class("biomorphic-matrix")], [
    html.h3([], [element.text("NASA-STD-3000 Biomorphic Matrix")]),
    render_metric("Visual Balance", data.visual_balance),
    render_metric("Cognitive Load", data.cognitive_load),
    render_metric("Ergonomic Score", data.ergonomic_score),
  ])
}

fn render_metric(label: String, value: Float) -> Element(msg) {
  html.div([attribute.class("metric-row")], [
    html.span([attribute.class("metric-label")], [element.text(label <> ": ")]),
    html.span([attribute.class("metric-value")], [
      element.text(float_to_string(value)),
    ]),
    render_progress_bar(value),
  ])
}

fn render_progress_bar(value: Float) -> Element(msg) {
  let percentage = float.clamp(value *. 100.0, 0.0, 100.0)
  html.div([attribute.class("progress-container")], [
    html.div(
      [
        attribute.class("progress-bar"),
        attribute.attribute(
          "style",
          "width: " <> float.to_string(percentage) <> "%",
        ),
      ],
      [],
    ),
  ])
}

fn float_to_string(f: Float) -> String {
  let s = float.to_string(f)
  case string.length(s) > 4 {
    True -> string.slice(s, 0, 4)
    False -> s
  }
}
