//// Pure reference contracts for web verification. No network or authority effects.
//// A model law does not establish browser behavior or arbitrary-program correctness.

pub opaque type Layer {
  Layer(Int)
}

pub fn layer(value: Int) -> Result(Layer, Nil) {
  case value >= 0 && value <= 9 {
    True -> Ok(Layer(value))
    False -> Error(Nil)
  }
}

pub fn layer_number(value: Layer) -> Int {
  let Layer(n) = value
  n
}

pub type Evidence {
  Passed
  Unrun
  Failed
}

pub fn admit(runtime: Evidence, formal: Evidence) -> Bool {
  runtime == Passed && formal == Passed
}

pub fn join(a: Evidence, b: Evidence) -> Evidence {
  case a, b {
    Failed, _ | _, Failed -> Failed
    Unrun, _ | _, Unrun -> Unrun
    Passed, Passed -> Passed
  }
}

pub fn rollup(items: List(Evidence)) -> Evidence {
  case items {
    [] -> Unrun
    [first, ..rest] -> rollup_from(first, rest)
  }
}

fn rollup_from(acc: Evidence, items: List(Evidence)) -> Evidence {
  case items {
    [] -> acc
    [first, ..rest] -> rollup_from(join(acc, first), rest)
  }
}

pub opaque type Route {
  Route(String)
}

// Conservative normalized path subset; URI decoding is a separate HTTP boundary.
pub fn route(value: String) -> Result(Route, Nil) {
  case value {
    "/" -> Ok(Route(value))
    "/" <> rest ->
      case safe_path(rest, True) {
        True -> Ok(Route(value))
        False -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn safe_path(value: String, previous_slash: Bool) -> Bool {
  case value {
    "" -> !previous_slash
    "/" <> rest -> !previous_slash && safe_path(rest, True)
    "-" <> rest | "_" <> rest -> safe_path(rest, False)
    ".." <> _ -> False
    "." <> rest -> safe_path(rest, False)
    "a" <> rest
    | "b" <> rest
    | "c" <> rest
    | "d" <> rest
    | "e" <> rest
    | "f" <> rest
    | "g" <> rest
    | "h" <> rest
    | "i" <> rest
    | "j" <> rest
    | "k" <> rest
    | "l" <> rest
    | "m" <> rest
    | "n" <> rest
    | "o" <> rest
    | "p" <> rest
    | "q" <> rest
    | "r" <> rest
    | "s" <> rest
    | "t" <> rest
    | "u" <> rest
    | "v" <> rest
    | "w" <> rest
    | "x" <> rest
    | "y" <> rest
    | "z" <> rest
    | "A" <> rest
    | "B" <> rest
    | "C" <> rest
    | "D" <> rest
    | "E" <> rest
    | "F" <> rest
    | "G" <> rest
    | "H" <> rest
    | "I" <> rest
    | "J" <> rest
    | "K" <> rest
    | "L" <> rest
    | "M" <> rest
    | "N" <> rest
    | "O" <> rest
    | "P" <> rest
    | "Q" <> rest
    | "R" <> rest
    | "S" <> rest
    | "T" <> rest
    | "U" <> rest
    | "V" <> rest
    | "W" <> rest
    | "X" <> rest
    | "Y" <> rest
    | "Z" <> rest
    | "0" <> rest
    | "1" <> rest
    | "2" <> rest
    | "3" <> rest
    | "4" <> rest
    | "5" <> rest
    | "6" <> rest
    | "7" <> rest
    | "8" <> rest
    | "9" <> rest -> safe_path(rest, False)
    _ -> False
  }
}

pub fn route_path(value: Route) -> String {
  let Route(path) = value
  path
}

pub fn complete_cycles(cycles: List(Int)) -> Bool {
  contains(cycles, 1)
  && contains(cycles, 2)
  && contains(cycles, 3)
  && contains(cycles, 4)
}

fn contains(values: List(a), value: a) -> Bool {
  case values {
    [] -> False
    [head, ..tail] -> head == value || contains(tail, value)
  }
}

fn append(a: List(x), b: List(x)) -> List(x) {
  case a {
    [] -> b
    [head, ..tail] -> [head, ..append(tail, b)]
  }
}

fn range(n: Int) -> List(Int) {
  case n <= 0 {
    True -> []
    False -> append(range(n - 1), [n - 1])
  }
}

fn every(values: List(a), predicate: fn(a) -> Bool) -> Bool {
  case values {
    [] -> True
    [head, ..tail] -> predicate(head) && every(tail, predicate)
  }
}

fn neighbours(edges: List(#(Int, Int)), node: Int) -> List(Int) {
  case edges {
    [] -> []
    [#(from, to), ..rest] ->
      case from == node {
        True -> [to, ..neighbours(rest, node)]
        False -> neighbours(rest, node)
      }
  }
}

fn reach(
  edges: List(#(Int, Int)),
  pending: List(Int),
  seen: List(Int),
  goal: Int,
) -> Bool {
  case pending {
    [] -> False
    [node, ..rest] ->
      case node == goal, contains(seen, node) {
        True, _ -> True
        False, True -> reach(edges, rest, seen, goal)
        False, False ->
          reach(
            edges,
            append(rest, neighbours(edges, node)),
            [node, ..seen],
            goal,
          )
      }
  }
}

pub fn strongly_connected(size: Int, edges: List(#(Int, Int))) -> Bool {
  size > 0
  && size <= 64
  && every(edges, fn(e) { e.0 >= 0 && e.0 < size && e.1 >= 0 && e.1 < size })
  && every(range(size), fn(a) {
    every(range(size), fn(b) { reach(edges, [a], [], b) })
  })
}

pub type Intent {
  Open(Int)
  Back
}

pub type Navigation {
  Navigation(current: Int, history: List(Int))
}

pub fn denote(intents: List(Intent), state: Navigation) -> Navigation {
  case intents {
    [] -> state
    [first, ..rest] -> {
      let next = case first {
        Open(node) -> Navigation(node, [state.current, ..state.history])
        Back ->
          case state.history {
            [] -> state
            [previous, ..history] -> Navigation(previous, history)
          }
      }
      denote(rest, next)
    }
  }
}

pub type Trace {
  Trace(
    layer: Layer,
    fractal: String,
    domain: String,
    origin: String,
    target: String,
    epoch: Int,
    authority: String,
    status: String,
    digest: String,
    trust: Int,
    drift_us: Int,
    entropy_millibits: Int,
    parity: String,
  )
}

// Exact transport conservation. Semantic state transitions need an explicit delta contract.
pub fn conserves(before: Trace, after: Trace) -> Bool {
  before == after
}
