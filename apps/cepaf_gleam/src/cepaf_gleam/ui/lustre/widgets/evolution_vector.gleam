import gleam/float
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub type Vector3 {
  Vector3(x: Float, y: Float, z: Float)
}

pub type EvolutionVectorData {
  EvolutionVectorData(
    v1_physics: Vector3,
    v2_logic: Vector3,
    v3_cognitive: Vector3,
    v4_social: Vector3,
  )
}

pub fn view(data: EvolutionVectorData) -> Element(msg) {
  html.div([attribute.class("evolution-vector")], [
    html.h3([], [element.text("Evolution Vector V1-V4")]),
    render_vector("V1 (Physics)", data.v1_physics),
    render_vector("V2 (Logic)", data.v2_logic),
    render_vector("V3 (Cognitive)", data.v3_cognitive),
    render_vector("V4 (Social)", data.v4_social),
  ])
}

fn render_vector(label: String, v: Vector3) -> Element(msg) {
  html.div([attribute.class("vector-row")], [
    html.span([attribute.class("vector-label")], [element.text(label <> ": ")]),
    html.span([attribute.class("vector-values")], [
      element.text(
        "["
        <> float_to_string(v.x)
        <> ", "
        <> float_to_string(v.y)
        <> ", "
        <> float_to_string(v.z)
        <> "]",
      ),
    ]),
  ])
}

fn float_to_string(f: Float) -> String {
  let s = float.to_string(f)
  case string.length(s) > 4 {
    True -> string.slice(s, 0, 4)
    False -> s
  }
}
