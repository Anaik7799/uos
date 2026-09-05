import gleam/float
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub type HsDsData {
  HsDsData(shannon_entropy: Float, ccm_score: Float, itqs_score: Float)
}

pub fn view(data: HsDsData) -> Element(msg) {
  html.div([attribute.class("hs-ds-pane")], [
    html.h3([], [element.text("Mathematical Hs/Ds Pane")]),
    html.div([attribute.class("metric")], [
      html.span([], [element.text("Shannon Entropy: ")]),
      html.span([], [element.text(float_to_string(data.shannon_entropy))]),
    ]),
    html.div([attribute.class("metric")], [
      html.span([], [element.text("CCM Score: ")]),
      html.span([], [element.text(float_to_string(data.ccm_score))]),
    ]),
    html.div([attribute.class("metric")], [
      html.span([], [element.text("ITQS Score: ")]),
      html.span([], [element.text(float_to_string(data.itqs_score))]),
    ]),
  ])
}

fn float_to_string(f: Float) -> String {
  let s = float.to_string(f)
  case string.length(s) > 6 {
    True -> string.slice(s, 0, 6)
    False -> s
  }
}
