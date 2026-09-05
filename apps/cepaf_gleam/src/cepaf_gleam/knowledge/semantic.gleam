import gleam/list
import gleam/option.{type Option}

pub type RdfTerm {
  Iri(String)
  Blank(String)
  Literal(value: String, lang: String, datatype: String)
}

pub type Triple {
  Triple(subject: RdfTerm, predicate: String, object: RdfTerm)
}

pub type TriplePattern {
  TriplePattern(
    subject: Option(RdfTerm),
    predicate: Option(String),
    object: Option(RdfTerm),
  )
}

pub type Vector =
  List(Float)

@external(erlang, "cepaf_gleam_ffi", "sqrt")
fn erl_sqrt(x: Float) -> Float

pub fn dot_product(v1: Vector, v2: Vector) -> Float {
  list.zip(v1, v2)
  |> list.map(fn(pair) { pair.0 *. pair.1 })
  |> list.fold(0.0, fn(acc, x) { acc +. x })
}

pub fn magnitude(v: Vector) -> Float {
  v
  |> list.map(fn(x) { x *. x })
  |> list.fold(0.0, fn(acc, x) { acc +. x })
  |> erl_sqrt()
}

pub fn cosine_similarity(v1: Vector, v2: Vector) -> Result(Float, String) {
  let mag1 = magnitude(v1)
  let mag2 = magnitude(v2)

  case mag1 == 0.0 || mag2 == 0.0 {
    True -> Error("Cannot calculate similarity with zero-magnitude vector")
    False -> {
      let dot = dot_product(v1, v2)
      Ok(dot /. { mag1 *. mag2 })
    }
  }
}
