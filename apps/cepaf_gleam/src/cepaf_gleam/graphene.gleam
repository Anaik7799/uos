//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/graphene</module>
////     <fsharp-lineage>None — new Gleam-native module</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L2_COMPONENT</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-AGUI-UI-001, SC-UIGT-001, SC-NIF-001, SC-ULTRA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       6 Rust crates -> 1 NIF -> 22 NIF functions -> 55+ typed Gleam functions.
////       Packages: graphene (graph), tiny-skia (render), kurbo (paths),
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================

import gleam/json
import gleam/list
import gleam/result

// ═══════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════

pub type StateNode {
  StateNode(label: String, color: String)
}

pub type StateEdge {
  StateEdge(from: Int, to: Int, label: String)
}

pub type StateMachine {
  StateMachine(nodes: List(StateNode), edges: List(StateEdge))
}

pub type Point2 {
  Point2(x: Float, y: Float)
}

pub type Point3 {
  Point3(x: Float, y: Float, z: Float)
}

pub type Rgba {
  Rgba(r: Float, g: Float, b: Float, a: Float)
}

pub type SvgShape {
  SvgRect(x: Float, y: Float, w: Float, h: Float)
  SvgCircle(cx: Float, cy: Float, r: Float)
  SvgStar(cx: Float, cy: Float, r_outer: Float, r_inner: Float, points: Int)
  SvgPolygon(cx: Float, cy: Float, r: Float, sides: Int)
}

pub type Transform2D {
  Transform2D(translate: Point2, rotate_deg: Float, scale: Point2)
}

// ═══════════════════════════════════════════════════════════════
// GRAPHENE — Graph Algorithms (graphene_*)
// 7 NIF + 8 typed wrappers = 15 functions
// ═══════════════════════════════════════════════════════════════

/// BFS traversal. JSON in, JSON out.
pub fn graphene_bfs(
  nodes_json: String,
  edges_json: String,
  start: String,
) -> Result(String, String) {
  nif_graph_bfs(nodes_json, edges_json, start)
}

/// DFS traversal. JSON in, JSON out.
pub fn graphene_dfs(
  nodes_json: String,
  edges_json: String,
  start: String,
) -> Result(String, String) {
  nif_graph_dfs(nodes_json, edges_json, start)
}

/// Topological sort (Kahn's). Errors on cycles.
pub fn graphene_topological_sort(
  nodes_json: String,
  edges_json: String,
) -> Result(String, String) {
  nif_graph_topological_sort(nodes_json, edges_json)
}

/// Strongly Connected Components (Tarjan's).
pub fn graphene_scc(
  nodes_json: String,
  edges_json: String,
) -> Result(String, String) {
  nif_graph_scc(nodes_json, edges_json)
}

/// Shortest path (Dijkstra).
pub fn graphene_shortest_path(
  nodes_json: String,
  edges_json: String,
  from: String,
  to: String,
) -> Result(String, String) {
  nif_graph_shortest_path(nodes_json, edges_json, from, to)
}

/// PageRank with damping and iterations.
pub fn graphene_pagerank(
  nodes_json: String,
  edges_json: String,
  damping: Float,
  iterations: Int,
) -> Result(String, String) {
  nif_graph_pagerank(nodes_json, edges_json, damping, iterations)
}

/// Graph analysis: vertex/edge count, density, is_dag, degree stats.
pub fn graphene_analyze(
  nodes_json: String,
  edges_json: String,
) -> Result(String, String) {
  nif_graph_analyze(nodes_json, edges_json)
}

/// Build graph JSON from typed lists. Returns (nodes_json, edges_json).
pub fn graphene_build_graph(
  nodes: List(String),
  edges: List(#(String, String, Int)),
) -> #(String, String) {
  let nj =
    nodes
    |> list.map(json.string)
    |> json.preprocessed_array()
    |> json.to_string()
  let ej =
    edges
    |> list.map(fn(e) {
      json.preprocessed_array([
        json.string(e.0),
        json.string(e.1),
        json.int(e.2),
      ])
    })
    |> json.preprocessed_array()
    |> json.to_string()
  #(nj, ej)
}

/// BFS with typed node/edge lists.
pub fn graphene_bfs_typed(
  nodes: List(String),
  edges: List(#(String, String, Int)),
  start: String,
) -> Result(String, String) {
  let #(n, e) = graphene_build_graph(nodes, edges)
  nif_graph_bfs(n, e, start)
}

/// DFS with typed node/edge lists.
pub fn graphene_dfs_typed(
  nodes: List(String),
  edges: List(#(String, String, Int)),
  start: String,
) -> Result(String, String) {
  let #(n, e) = graphene_build_graph(nodes, edges)
  nif_graph_dfs(n, e, start)
}

/// Topological sort with typed lists.
pub fn graphene_topological_sort_typed(
  nodes: List(String),
  edges: List(#(String, String, Int)),
) -> Result(String, String) {
  let #(n, e) = graphene_build_graph(nodes, edges)
  nif_graph_topological_sort(n, e)
}

/// SCC with typed lists.
pub fn graphene_scc_typed(
  nodes: List(String),
  edges: List(#(String, String, Int)),
) -> Result(String, String) {
  let #(n, e) = graphene_build_graph(nodes, edges)
  nif_graph_scc(n, e)
}

/// Shortest path with typed lists.
pub fn graphene_shortest_path_typed(
  nodes: List(String),
  edges: List(#(String, String, Int)),
  from: String,
  to: String,
) -> Result(String, String) {
  let #(n, e) = graphene_build_graph(nodes, edges)
  nif_graph_shortest_path(n, e, from, to)
}

/// PageRank with typed lists.
pub fn graphene_pagerank_typed(
  nodes: List(String),
  edges: List(#(String, String, Int)),
  damping: Float,
  iterations: Int,
) -> Result(String, String) {
  let #(n, e) = graphene_build_graph(nodes, edges)
  nif_graph_pagerank(n, e, damping, iterations)
}

/// Analyze with typed lists.
pub fn graphene_analyze_typed(
  nodes: List(String),
  edges: List(#(String, String, Int)),
) -> Result(String, String) {
  let #(n, e) = graphene_build_graph(nodes, edges)
  nif_graph_analyze(n, e)
}

@external(erlang, "graphene_nif", "graph_bfs")
fn nif_graph_bfs(n: String, e: String, s: String) -> Result(String, String)

@external(erlang, "graphene_nif", "graph_dfs")
fn nif_graph_dfs(n: String, e: String, s: String) -> Result(String, String)

@external(erlang, "graphene_nif", "graph_topological_sort")
fn nif_graph_topological_sort(n: String, e: String) -> Result(String, String)

@external(erlang, "graphene_nif", "graph_scc")
fn nif_graph_scc(n: String, e: String) -> Result(String, String)

@external(erlang, "graphene_nif", "graph_shortest_path")
fn nif_graph_shortest_path(
  n: String,
  e: String,
  f: String,
  t: String,
) -> Result(String, String)

@external(erlang, "graphene_nif", "graph_pagerank")
fn nif_graph_pagerank(
  n: String,
  e: String,
  d: Float,
  i: Int,
) -> Result(String, String)

@external(erlang, "graphene_nif", "graph_analyze")
fn nif_graph_analyze(n: String, e: String) -> Result(String, String)

// ═══════════════════════════════════════════════════════════════
// SKIA — PNG Rendering (skia_*)
// 3 NIF + 1 typed wrapper = 4 functions
// ═══════════════════════════════════════════════════════════════

/// Render state diagram to PNG with BFS-layered layout.
pub fn skia_render_state_diagram(
  title: String,
  nodes: List(StateNode),
  edges: List(StateEdge),
  output_path: String,
  width: Int,
  height: Int,
) -> Result(Nil, String) {
  let nj =
    nodes
    |> list.map(fn(n) {
      json.object([
        #("label", json.string(n.label)),
        #("color", json.string(n.color)),
      ])
    })
    |> json.preprocessed_array()
    |> json.to_string()
  let ej =
    edges
    |> list.map(fn(e) {
      json.object([
        #("from", json.int(e.from)),
        #("to", json.int(e.to)),
        #("label", json.string(e.label)),
      ])
    })
    |> json.preprocessed_array()
    |> json.to_string()
  nif_render_state_diagram(title, nj, ej, output_path, width, height)
  |> result.map(fn(_) { Nil })
}

/// Render a StateMachine to PNG.
pub fn skia_render_machine(
  title: String,
  machine: StateMachine,
  output_path: String,
  width: Int,
  height: Int,
) -> Result(Nil, String) {
  skia_render_state_diagram(
    title,
    machine.nodes,
    machine.edges,
    output_path,
    width,
    height,
  )
}

/// Render named component wireframe (multi-state dummy data PNG).
/// Names: "c1_weather", "c2_rings", "c4_grid", "c4_triage", "c5_kanban", "c9_detail", "c11_changelog", "c12_fractal"
pub fn skia_render_component(
  component: String,
  output_path: String,
) -> Result(Nil, String) {
  nif_render_component(component, output_path) |> result.map(fn(_) { Nil })
}

/// Render ALL state diagrams + component wireframes. Returns JSON filename list.
pub fn skia_render_all(output_dir: String) -> Result(String, String) {
  nif_render_all_diagrams(output_dir)
}

@external(erlang, "graphene_nif", "render_state_diagram")
fn nif_render_state_diagram(
  t: String,
  n: String,
  e: String,
  p: String,
  w: Int,
  h: Int,
) -> Result(Nil, String)

@external(erlang, "graphene_nif", "render_component")
fn nif_render_component(c: String, p: String) -> Result(Nil, String)

@external(erlang, "graphene_nif", "render_all_diagrams")
fn nif_render_all_diagrams(d: String) -> Result(String, String)

// ═══════════════════════════════════════════════════════════════
// KURBO — Vector Paths (kurbo_*)
// 5 NIF + 5 typed wrappers = 10 functions
// ═══════════════════════════════════════════════════════════════

/// Generate SVG path from JSON points [[x,y],...].
pub fn kurbo_path_from_points(points_json: String) -> Result(String, String) {
  nif_svg_path_from_points(points_json)
}

/// Analyze SVG path data: bounding_box, area, perimeter, segment_count.
pub fn kurbo_path_analyze(svg_d: String) -> Result(String, String) {
  nif_svg_path_analyze(svg_d)
}

/// Apply affine transform JSON to SVG path.
pub fn kurbo_path_transform(
  svg_d: String,
  transform_json: String,
) -> Result(String, String) {
  nif_svg_path_transform(svg_d, transform_json)
}

/// Apply typed Transform2D to SVG path.
pub fn kurbo_path_apply_transform(
  svg_d: String,
  t: Transform2D,
) -> Result(String, String) {
  let tj =
    json.object([
      #(
        "translate",
        json.preprocessed_array([
          json.float(t.translate.x),
          json.float(t.translate.y),
        ]),
      ),
      #("rotate", json.float(t.rotate_deg)),
      #(
        "scale",
        json.preprocessed_array([json.float(t.scale.x), json.float(t.scale.y)]),
      ),
    ])
    |> json.to_string()
  nif_svg_path_transform(svg_d, tj)
}

/// Generate SVG shape from JSON spec.
pub fn kurbo_shape(shape_json: String) -> Result(String, String) {
  nif_svg_shape(shape_json)
}

/// Generate SVG shape from typed SvgShape.
pub fn kurbo_shape_typed(shape: SvgShape) -> Result(String, String) {
  let sj = case shape {
    SvgRect(x, y, w, h) ->
      json.object([
        #("type", json.string("rect")),
        #("x", json.float(x)),
        #("y", json.float(y)),
        #("w", json.float(w)),
        #("h", json.float(h)),
      ])
    SvgCircle(cx, cy, r) ->
      json.object([
        #("type", json.string("circle")),
        #("cx", json.float(cx)),
        #("cy", json.float(cy)),
        #("r", json.float(r)),
      ])
    SvgStar(cx, cy, ro, ri, pts) ->
      json.object([
        #("type", json.string("star")),
        #("cx", json.float(cx)),
        #("cy", json.float(cy)),
        #("r_outer", json.float(ro)),
        #("r_inner", json.float(ri)),
        #("points", json.int(pts)),
      ])
    SvgPolygon(cx, cy, r, sides) ->
      json.object([
        #("type", json.string("polygon")),
        #("cx", json.float(cx)),
        #("cy", json.float(cy)),
        #("r", json.float(r)),
        #("sides", json.int(sides)),
      ])
  }
  nif_svg_shape(json.to_string(sj))
}

/// 2D vector math: raw operation + JSON params.
pub fn kurbo_vec2_math(
  operation: String,
  params_json: String,
) -> Result(String, String) {
  nif_vec2_math(operation, params_json)
}

/// Distance between two 2D points.
pub fn kurbo_vec2_distance(a: Point2, b: Point2) -> Result(String, String) {
  nif_vec2_math("distance", p2_pair(a, b))
}

/// Linear interpolation between two 2D points.
pub fn kurbo_vec2_lerp(
  a: Point2,
  b: Point2,
  t: Float,
) -> Result(String, String) {
  let p =
    json.object([#("a", p2j(a)), #("b", p2j(b)), #("t", json.float(t))])
    |> json.to_string()
  nif_vec2_math("lerp", p)
}

/// Normalize 2D vector to unit length.
pub fn kurbo_vec2_normalize(v: Point2) -> Result(String, String) {
  let p = json.object([#("v", p2j(v))]) |> json.to_string()
  nif_vec2_math("normalize", p)
}

/// Dot product of two 2D vectors.
pub fn kurbo_vec2_dot(a: Point2, b: Point2) -> Result(String, String) {
  nif_vec2_math("dot", p2_pair(a, b))
}

/// Angle between two 2D vectors (radians + degrees).
pub fn kurbo_vec2_angle(a: Point2, b: Point2) -> Result(String, String) {
  nif_vec2_math("angle", p2_pair(a, b))
}

fn p2j(p: Point2) -> json.Json {
  json.preprocessed_array([json.float(p.x), json.float(p.y)])
}

fn p2_pair(a: Point2, b: Point2) -> String {
  json.object([#("a", p2j(a)), #("b", p2j(b))]) |> json.to_string()
}

@external(erlang, "graphene_nif", "svg_path_from_points")
fn nif_svg_path_from_points(p: String) -> Result(String, String)

@external(erlang, "graphene_nif", "svg_path_analyze")
fn nif_svg_path_analyze(d: String) -> Result(String, String)

@external(erlang, "graphene_nif", "svg_path_transform")
fn nif_svg_path_transform(d: String, t: String) -> Result(String, String)

@external(erlang, "graphene_nif", "svg_shape")
fn nif_svg_shape(s: String) -> Result(String, String)

@external(erlang, "graphene_nif", "vec2_math")
fn nif_vec2_math(op: String, p: String) -> Result(String, String)

// [ZERO-MUDA] Bevy ECS, Bevy Math, and Bevy Color have been permanently purged
// from UOS architecture per Rule 1 and Gate G-MUDA.

// ═══════════════════════════════════════════════════════════════
// MERMAID — Diagram Renderer (mermaid_*)
// 2 NIF + 4 typed builders = 6 functions
// ═══════════════════════════════════════════════════════════════

/// Render Mermaid text to SVG string. 23 diagram types supported.
pub fn mermaid_render(
  mermaid_text: String,
  output_format: String,
) -> Result(String, String) {
  nif_mermaid_render(mermaid_text, output_format)
}

/// Render Mermaid text and save as SVG file.
pub fn mermaid_render_to_file(
  mermaid_text: String,
  output_path: String,
) -> Result(String, String) {
  nif_mermaid_render_to_file(mermaid_text, output_path)
}

/// Render a StateMachine as Mermaid stateDiagram SVG file.
pub fn mermaid_render_machine(
  machine: StateMachine,
  output_path: String,
) -> Result(String, String) {
  nif_mermaid_render_to_file(mermaid_build_state_diagram(machine), output_path)
}

/// Build Mermaid stateDiagram-v2 text from StateMachine.
pub fn mermaid_build_state_diagram(machine: StateMachine) -> String {
  let transitions =
    machine.edges
    |> list.map(fn(e) {
      let fl = get_label(machine.nodes, e.from)
      let tl = get_label(machine.nodes, e.to)
      "  " <> fl <> " --> " <> tl <> " : " <> e.label
    })
  ["stateDiagram-v2", ..transitions]
  |> list.fold("", fn(acc, l) { acc <> l <> "\n" })
}

/// Build Mermaid flowchart text from typed node/edge lists.
pub fn mermaid_build_flowchart(
  direction: String,
  nodes: List(#(String, String)),
  edges: List(#(String, String, String)),
) -> String {
  let nl = nodes |> list.map(fn(n) { "  " <> n.0 <> "[" <> n.1 <> "]" })
  let el =
    edges
    |> list.map(fn(e) {
      case e.2 {
        "" -> "  " <> e.0 <> " --> " <> e.1
        lbl -> "  " <> e.0 <> " -->|" <> lbl <> "| " <> e.1
      }
    })
  ["flowchart " <> direction, ..list.append(nl, el)]
  |> list.fold("", fn(acc, l) { acc <> l <> "\n" })
}

/// Build Mermaid sequence diagram text.
pub fn mermaid_build_sequence(
  participants: List(String),
  messages: List(#(String, String, String)),
) -> String {
  let pl = participants |> list.map(fn(p) { "  participant " <> p })
  let ml =
    messages |> list.map(fn(m) { "  " <> m.0 <> "->>" <> m.1 <> ": " <> m.2 })
  ["sequenceDiagram", ..list.append(pl, ml)]
  |> list.fold("", fn(acc, l) { acc <> l <> "\n" })
}

fn get_label(nodes: List(StateNode), index: Int) -> String {
  case nodes |> list.drop(index) |> list.first() {
    Ok(StateNode(label, _)) -> label
    Error(_) -> "?"
  }
}

@external(erlang, "graphene_nif", "mermaid_render")
fn nif_mermaid_render(t: String, f: String) -> Result(String, String)

@external(erlang, "graphene_nif", "mermaid_render_to_file")
fn nif_mermaid_render_to_file(t: String, p: String) -> Result(String, String)

// ═══════════════════════════════════════════════════════════════
// KURBO EXTENDED — Affine transforms (kurbo_affine_*)
// 1 NIF (multiplexed) + 9 typed wrappers = 10 functions
// ═══════════════════════════════════════════════════════════════

pub fn kurbo_affine_op(
  operation: String,
  params_json: String,
) -> Result(String, String) {
  nif_kurbo_affine_op(operation, params_json)
}

pub fn kurbo_affine_identity() -> Result(String, String) {
  nif_kurbo_affine_op("identity", "{}")
}

pub fn kurbo_affine_rotate(angle_deg: Float) -> Result(String, String) {
  nif_kurbo_affine_op(
    "rotate",
    json.object([#("angle", json.float(angle_deg))]) |> json.to_string(),
  )
}

pub fn kurbo_affine_translate(dx: Float, dy: Float) -> Result(String, String) {
  nif_kurbo_affine_op(
    "translate",
    json.object([#("dx", json.float(dx)), #("dy", json.float(dy))])
      |> json.to_string(),
  )
}

pub fn kurbo_affine_scale(sx: Float, sy: Float) -> Result(String, String) {
  nif_kurbo_affine_op(
    "scale",
    json.object([#("sx", json.float(sx)), #("sy", json.float(sy))])
      |> json.to_string(),
  )
}

pub fn kurbo_affine_skew(kx: Float, ky: Float) -> Result(String, String) {
  nif_kurbo_affine_op(
    "skew",
    json.object([#("kx", json.float(kx)), #("ky", json.float(ky))])
      |> json.to_string(),
  )
}

pub fn kurbo_affine_inverse(coeffs: List(Float)) -> Result(String, String) {
  nif_kurbo_affine_op(
    "inverse",
    json.object([
      #("coeffs", json.preprocessed_array(list.map(coeffs, json.float))),
    ])
      |> json.to_string(),
  )
}

pub fn kurbo_affine_compose(
  a: List(Float),
  b: List(Float),
) -> Result(String, String) {
  nif_kurbo_affine_op(
    "compose",
    json.object([
      #("a", json.preprocessed_array(list.map(a, json.float))),
      #("b", json.preprocessed_array(list.map(b, json.float))),
    ])
      |> json.to_string(),
  )
}

pub fn kurbo_affine_transform_point(
  coeffs: List(Float),
  point: Point2,
) -> Result(String, String) {
  nif_kurbo_affine_op(
    "transform_point",
    json.object([
      #("affine", json.preprocessed_array(list.map(coeffs, json.float))),
      #("point", p2j(point)),
    ])
      |> json.to_string(),
  )
}

@external(erlang, "graphene_nif", "kurbo_affine_op")
fn nif_kurbo_affine_op(op: String, p: String) -> Result(String, String)

// ═══════════════════════════════════════════════════════════════
// KURBO EXTENDED — Geometry operations (kurbo_geometry_*)
// 1 NIF (multiplexed) + 14 typed wrappers = 15 functions
// ═══════════════════════════════════════════════════════════════

pub fn kurbo_geometry_op(
  operation: String,
  params_json: String,
) -> Result(String, String) {
  nif_kurbo_geometry_op(operation, params_json)
}

pub fn kurbo_rect_area(
  x: Float,
  y: Float,
  w: Float,
  h: Float,
) -> Result(String, String) {
  nif_kurbo_geometry_op(
    "rect_area",
    json.object([
      #("x", json.float(x)),
      #("y", json.float(y)),
      #("w", json.float(w)),
      #("h", json.float(h)),
    ])
      |> json.to_string(),
  )
}

pub fn kurbo_rect_union(
  a: #(Float, Float, Float, Float),
  b: #(Float, Float, Float, Float),
) -> Result(String, String) {
  nif_kurbo_geometry_op(
    "rect_union",
    json.object([
      #(
        "a",
        json.preprocessed_array([
          json.float(a.0),
          json.float(a.1),
          json.float(a.2),
          json.float(a.3),
        ]),
      ),
      #(
        "b",
        json.preprocessed_array([
          json.float(b.0),
          json.float(b.1),
          json.float(b.2),
          json.float(b.3),
        ]),
      ),
    ])
      |> json.to_string(),
  )
}

pub fn kurbo_rect_intersect(
  a: #(Float, Float, Float, Float),
  b: #(Float, Float, Float, Float),
) -> Result(String, String) {
  nif_kurbo_geometry_op(
    "rect_intersect",
    json.object([
      #(
        "a",
        json.preprocessed_array([
          json.float(a.0),
          json.float(a.1),
          json.float(a.2),
          json.float(a.3),
        ]),
      ),
      #(
        "b",
        json.preprocessed_array([
          json.float(b.0),
          json.float(b.1),
          json.float(b.2),
          json.float(b.3),
        ]),
      ),
    ])
      |> json.to_string(),
  )
}

pub fn kurbo_rect_contains(
  x: Float,
  y: Float,
  w: Float,
  h: Float,
  point: Point2,
) -> Result(String, String) {
  nif_kurbo_geometry_op(
    "rect_contains_point",
    json.object([
      #("x", json.float(x)),
      #("y", json.float(y)),
      #("w", json.float(w)),
      #("h", json.float(h)),
      #("point", p2j(point)),
    ])
      |> json.to_string(),
  )
}

pub fn kurbo_rect_inflate(
  x: Float,
  y: Float,
  w: Float,
  h: Float,
  d: Float,
) -> Result(String, String) {
  nif_kurbo_geometry_op(
    "rect_inflate",
    json.object([
      #("x", json.float(x)),
      #("y", json.float(y)),
      #("w", json.float(w)),
      #("h", json.float(h)),
      #("d", json.float(d)),
    ])
      |> json.to_string(),
  )
}

pub fn kurbo_circle_area(
  cx: Float,
  cy: Float,
  r: Float,
) -> Result(String, String) {
  nif_kurbo_geometry_op(
    "circle_area",
    json.object([
      #("cx", json.float(cx)),
      #("cy", json.float(cy)),
      #("r", json.float(r)),
    ])
      |> json.to_string(),
  )
}

pub fn kurbo_ellipse_area(
  cx: Float,
  cy: Float,
  rx: Float,
  ry: Float,
  rotation: Float,
) -> Result(String, String) {
  nif_kurbo_geometry_op(
    "ellipse_area",
    json.object([
      #("cx", json.float(cx)),
      #("cy", json.float(cy)),
      #("rx", json.float(rx)),
      #("ry", json.float(ry)),
      #("rotation", json.float(rotation)),
    ])
      |> json.to_string(),
  )
}

pub fn kurbo_line_length(a: Point2, b: Point2) -> Result(String, String) {
  nif_kurbo_geometry_op(
    "line_length",
    json.object([#("a", p2j(a)), #("b", p2j(b))]) |> json.to_string(),
  )
}

pub fn kurbo_line_crossing(
  a: #(Float, Float, Float, Float),
  b: #(Float, Float, Float, Float),
) -> Result(String, String) {
  nif_kurbo_geometry_op(
    "line_crossing",
    json.object([
      #(
        "a",
        json.preprocessed_array([
          json.float(a.0),
          json.float(a.1),
          json.float(a.2),
          json.float(a.3),
        ]),
      ),
      #(
        "b",
        json.preprocessed_array([
          json.float(b.0),
          json.float(b.1),
          json.float(b.2),
          json.float(b.3),
        ]),
      ),
    ])
      |> json.to_string(),
  )
}

pub fn kurbo_triangle_area(
  a: Point2,
  b: Point2,
  c: Point2,
) -> Result(String, String) {
  nif_kurbo_geometry_op(
    "triangle_area",
    json.object([#("a", p2j(a)), #("b", p2j(b)), #("c", p2j(c))])
      |> json.to_string(),
  )
}

pub fn kurbo_point_distance(a: Point2, b: Point2) -> Result(String, String) {
  nif_kurbo_geometry_op(
    "point_distance",
    json.object([#("a", p2j(a)), #("b", p2j(b))]) |> json.to_string(),
  )
}

pub fn kurbo_point_lerp(
  a: Point2,
  b: Point2,
  t: Float,
) -> Result(String, String) {
  nif_kurbo_geometry_op(
    "point_lerp",
    json.object([#("a", p2j(a)), #("b", p2j(b)), #("t", json.float(t))])
      |> json.to_string(),
  )
}

pub fn kurbo_vec2_cross(a: Point2, b: Point2) -> Result(String, String) {
  nif_kurbo_geometry_op(
    "vec2_cross",
    json.object([#("a", p2j(a)), #("b", p2j(b))]) |> json.to_string(),
  )
}

pub fn kurbo_vec2_from_angle(angle_deg: Float) -> Result(String, String) {
  nif_kurbo_geometry_op(
    "vec2_from_angle",
    json.object([#("angle", json.float(angle_deg))]) |> json.to_string(),
  )
}

pub fn kurbo_size_area(w: Float, h: Float) -> Result(String, String) {
  nif_kurbo_geometry_op(
    "size_area",
    json.object([#("w", json.float(w)), #("h", json.float(h))])
      |> json.to_string(),
  )
}

@external(erlang, "graphene_nif", "kurbo_geometry_op")
fn nif_kurbo_geometry_op(op: String, p: String) -> Result(String, String)

// ═══════════════════════════════════════════════════════════════
// KURBO EXTENDED — Bezier operations (kurbo_bezier_*)
// 1 NIF (multiplexed) + 4 typed wrappers = 5 functions
// ═══════════════════════════════════════════════════════════════

pub fn kurbo_bezier_op(
  operation: String,
  params_json: String,
) -> Result(String, String) {
  nif_kurbo_bezier_op(operation, params_json)
}

pub fn kurbo_bezier_cubic_eval(
  p0: Point2,
  p1: Point2,
  p2: Point2,
  p3: Point2,
  t: Float,
) -> Result(String, String) {
  nif_kurbo_bezier_op(
    "cubic_eval",
    json.object([
      #("p0", p2j(p0)),
      #("p1", p2j(p1)),
      #("p2", p2j(p2)),
      #("p3", p2j(p3)),
      #("t", json.float(t)),
    ])
      |> json.to_string(),
  )
}

pub fn kurbo_bezier_quad_eval(
  p0: Point2,
  p1: Point2,
  p2: Point2,
  t: Float,
) -> Result(String, String) {
  nif_kurbo_bezier_op(
    "quad_eval",
    json.object([
      #("p0", p2j(p0)),
      #("p1", p2j(p1)),
      #("p2", p2j(p2)),
      #("t", json.float(t)),
    ])
      |> json.to_string(),
  )
}

pub fn kurbo_bezier_path_reverse(svg_d: String) -> Result(String, String) {
  nif_kurbo_bezier_op(
    "path_reverse",
    json.object([#("path", json.string(svg_d))]) |> json.to_string(),
  )
}

pub fn kurbo_bezier_path_flatten(
  svg_d: String,
  tolerance: Float,
) -> Result(String, String) {
  nif_kurbo_bezier_op(
    "path_flatten",
    json.object([
      #("path", json.string(svg_d)),
      #("tolerance", json.float(tolerance)),
    ])
      |> json.to_string(),
  )
}

@external(erlang, "graphene_nif", "kurbo_bezier_op")
fn nif_kurbo_bezier_op(op: String, p: String) -> Result(String, String)

// ═══════════════════════════════════════════════════════════════
// MERMAID EXTENDED — Render with options (mermaid_*)
// 1 NIF = 1 function
// ═══════════════════════════════════════════════════════════════

pub fn mermaid_render_with_options(
  mermaid_text: String,
  options_json: String,
) -> Result(String, String) {
  nif_mermaid_render_with_options(mermaid_text, options_json)
}

@external(erlang, "graphene_nif", "mermaid_render_with_options")
fn nif_mermaid_render_with_options(
  t: String,
  o: String,
) -> Result(String, String)

// ═══════════════════════════════════════════════════════════════
// SKIA EXTENDED — Programmatic drawing (skia_draw_*)
// 1 NIF = 1 function
// ═══════════════════════════════════════════════════════════════

/// Draw shapes to PNG using a JSON operations array.
/// ops: [{"type":"rect","x":0,"y":0,"w":100,"h":50,"color":"#ff4757"},
///       {"type":"circle","cx":50,"cy":50,"radius":25,"color":"#00d4aa"},
///       {"type":"line","x1":0,"y1":0,"x2":100,"y2":100","color":"#4d96ff"},
///       {"type":"text","x":10,"y":10,"text":"Hello","scale":1.5,"color":"#e0e6ed"},
///       {"type":"bar","x":10,"y":80,"w":200,"h":16,"ratio":0.75,"color":"#3dd68c"}]
pub fn skia_draw_to_png(
  operations_json: String,
  output_path: String,
  width: Int,
  height: Int,
) -> Result(String, String) {
  nif_skia_draw_to_png(operations_json, output_path, width, height)
}

@external(erlang, "graphene_nif", "skia_draw_to_png")
fn nif_skia_draw_to_png(
  ops: String,
  path: String,
  w: Int,
  h: Int,
) -> Result(String, String)

// ═══════════════════════════════════════════════════════════════
// VEGA-LITE — Declarative Visualization Grammar (vega_lite_*)
// 3 NIF + 9 typed presets = 12 functions
// ═══════════════════════════════════════════════════════════════

/// Build a Vega-Lite JSON spec. chart_type: "bar","line","point","area","arc","boxplot","heatmap"
pub fn vega_lite_spec(
  chart_type: String,
  params_json: String,
) -> Result(String, String) {
  nif_vega_lite_spec(chart_type, params_json)
}

/// Build a layered/multi-view Vega-Lite spec from JSON array of layer specs.
pub fn vega_lite_layered(layers_json: String) -> Result(String, String) {
  nif_vega_lite_layered(layers_json)
}

/// Build a C3I dashboard chart preset. Presets: "health_sparkline","priority_bar","fractal_heatmap","status_pie","ooda_ring","age_histogram","timeline_gantt"
pub fn vega_lite_preset(
  preset: String,
  data_json: String,
) -> Result(String, String) {
  nif_vega_lite_preset(preset, data_json)
}

/// Build a bar chart spec.
pub fn vega_lite_bar(
  title: String,
  data_json: String,
  x: String,
  y: String,
) -> Result(String, String) {
  let p =
    json.object([
      #("title", json.string(title)),
      #("data", json.string(data_json)),
      #("x", json.string(x)),
      #("y", json.string(y)),
      #("x_type", json.string("nominal")),
      #("y_type", json.string("quantitative")),
    ])
    |> json.to_string()
  nif_vega_lite_spec("bar", p)
}

/// Build a line chart spec.
pub fn vega_lite_line(
  title: String,
  data_json: String,
  x: String,
  y: String,
) -> Result(String, String) {
  let p =
    json.object([
      #("title", json.string(title)),
      #("data", json.string(data_json)),
      #("x", json.string(x)),
      #("y", json.string(y)),
      #("x_type", json.string("temporal")),
      #("y_type", json.string("quantitative")),
    ])
    |> json.to_string()
  nif_vega_lite_spec("line", p)
}

/// Build a scatter plot spec.
pub fn vega_lite_scatter(
  title: String,
  data_json: String,
  x: String,
  y: String,
) -> Result(String, String) {
  let p =
    json.object([
      #("title", json.string(title)),
      #("data", json.string(data_json)),
      #("x", json.string(x)),
      #("y", json.string(y)),
      #("x_type", json.string("quantitative")),
      #("y_type", json.string("quantitative")),
    ])
    |> json.to_string()
  nif_vega_lite_spec("point", p)
}

/// Build a pie/arc chart spec.
pub fn vega_lite_pie(
  title: String,
  data_json: String,
  theta: String,
  color: String,
) -> Result(String, String) {
  let p =
    json.object([
      #("title", json.string(title)),
      #("data", json.string(data_json)),
      #("theta", json.string(theta)),
      #("color", json.string(color)),
    ])
    |> json.to_string()
  nif_vega_lite_spec("arc", p)
}

/// Build an area chart spec.
pub fn vega_lite_area(
  title: String,
  data_json: String,
  x: String,
  y: String,
) -> Result(String, String) {
  let p =
    json.object([
      #("title", json.string(title)),
      #("data", json.string(data_json)),
      #("x", json.string(x)),
      #("y", json.string(y)),
      #("x_type", json.string("temporal")),
      #("y_type", json.string("quantitative")),
    ])
    |> json.to_string()
  nif_vega_lite_spec("area", p)
}

/// Build a heatmap spec.
pub fn vega_lite_heatmap(
  title: String,
  data_json: String,
  x: String,
  y: String,
  color: String,
) -> Result(String, String) {
  let p =
    json.object([
      #("title", json.string(title)),
      #("data", json.string(data_json)),
      #("x", json.string(x)),
      #("y", json.string(y)),
      #("color", json.string(color)),
      #("x_type", json.string("nominal")),
      #("y_type", json.string("nominal")),
    ])
    |> json.to_string()
  nif_vega_lite_spec("rect", p)
}

/// C3I preset: health sparkline (time vs health score)
pub fn vega_lite_health_sparkline(data_json: String) -> Result(String, String) {
  nif_vega_lite_preset("health_sparkline", data_json)
}

/// C3I preset: priority distribution bar chart
pub fn vega_lite_priority_bar(data_json: String) -> Result(String, String) {
  nif_vega_lite_preset("priority_bar", data_json)
}

/// C3I preset: fractal layer heatmap
pub fn vega_lite_fractal_heatmap(data_json: String) -> Result(String, String) {
  nif_vega_lite_preset("fractal_heatmap", data_json)
}

/// C3I preset: task status pie chart
pub fn vega_lite_status_pie(data_json: String) -> Result(String, String) {
  nif_vega_lite_preset("status_pie", data_json)
}

/// C3I preset: OODA cycle donut ring
pub fn vega_lite_ooda_ring(data_json: String) -> Result(String, String) {
  nif_vega_lite_preset("ooda_ring", data_json)
}

/// C3I preset: task age histogram
pub fn vega_lite_age_histogram(data_json: String) -> Result(String, String) {
  nif_vega_lite_preset("age_histogram", data_json)
}

/// C3I preset: task timeline Gantt chart
pub fn vega_lite_timeline_gantt(data_json: String) -> Result(String, String) {
  nif_vega_lite_preset("timeline_gantt", data_json)
}

@external(erlang, "graphene_nif", "vega_lite_spec")
fn nif_vega_lite_spec(t: String, p: String) -> Result(String, String)

@external(erlang, "graphene_nif", "vega_lite_layered")
fn nif_vega_lite_layered(l: String) -> Result(String, String)

@external(erlang, "graphene_nif", "vega_lite_preset")
fn nif_vega_lite_preset(p: String, d: String) -> Result(String, String)

// ═══════════════════════════════════════════════════════════════
// PETGRAPH — Production Graph Library (petgraph_*)
// 1 NIF (multiplexed) + 12 typed wrappers = 13 functions
// ═══════════════════════════════════════════════════════════════

/// Raw petgraph operation dispatch. 11 operations available.
pub fn petgraph_op(
  operation: String,
  nodes_json: String,
  edges_json: String,
  params_json: String,
) -> Result(String, String) {
  nif_petgraph_op(operation, nodes_json, edges_json, params_json)
}

/// Dijkstra shortest paths from start node to all reachable nodes.
pub fn petgraph_dijkstra(
  nodes_json: String,
  edges_json: String,
  start: Int,
) -> Result(String, String) {
  nif_petgraph_op(
    "dijkstra",
    nodes_json,
    edges_json,
    json.object([#("start", json.int(start))]) |> json.to_string(),
  )
}

/// Bellman-Ford shortest paths (handles negative weights). Detects negative cycles.
pub fn petgraph_bellman_ford(
  nodes_json: String,
  edges_json: String,
  start: Int,
) -> Result(String, String) {
  nif_petgraph_op(
    "bellman_ford",
    nodes_json,
    edges_json,
    json.object([#("start", json.int(start))]) |> json.to_string(),
  )
}

/// Check if directed graph contains cycles.
pub fn petgraph_is_cyclic(
  nodes_json: String,
  edges_json: String,
) -> Result(String, String) {
  nif_petgraph_op("is_cyclic", nodes_json, edges_json, "{}")
}

/// Topological sort with cycle node identification on failure.
pub fn petgraph_toposort(
  nodes_json: String,
  edges_json: String,
) -> Result(String, String) {
  nif_petgraph_op("toposort", nodes_json, edges_json, "{}")
}

/// Count connected components (undirected interpretation).
pub fn petgraph_connected_components(
  nodes_json: String,
  edges_json: String,
) -> Result(String, String) {
  nif_petgraph_op("connected_components", nodes_json, edges_json, "{}")
}

/// Minimum spanning tree (Kruskal's algorithm).
pub fn petgraph_min_spanning_tree(
  nodes_json: String,
  edges_json: String,
) -> Result(String, String) {
  nif_petgraph_op("min_spanning_tree", nodes_json, edges_json, "{}")
}

/// Export graph as Graphviz DOT format string.
pub fn petgraph_dot_export(
  nodes_json: String,
  edges_json: String,
) -> Result(String, String) {
  nif_petgraph_op("dot_export", nodes_json, edges_json, "{}")
}

/// Export graph as DOT with edge labels.
pub fn petgraph_dot_export_full(
  nodes_json: String,
  edges_json: String,
) -> Result(String, String) {
  nif_petgraph_op("dot_export_full", nodes_json, edges_json, "{}")
}

/// Get node and edge counts.
pub fn petgraph_node_count(
  nodes_json: String,
  edges_json: String,
) -> Result(String, String) {
  nif_petgraph_op("node_count", nodes_json, edges_json, "{}")
}

/// Get neighbors of a specific node.
pub fn petgraph_neighbors(
  nodes_json: String,
  edges_json: String,
  node: Int,
) -> Result(String, String) {
  nif_petgraph_op(
    "neighbors",
    nodes_json,
    edges_json,
    json.object([#("node", json.int(node))]) |> json.to_string(),
  )
}

/// List all edges with weights.
pub fn petgraph_all_edges(
  nodes_json: String,
  edges_json: String,
) -> Result(String, String) {
  nif_petgraph_op("all_edges", nodes_json, edges_json, "{}")
}

@external(erlang, "graphene_nif", "petgraph_op")
fn nif_petgraph_op(
  op: String,
  n: String,
  e: String,
  p: String,
) -> Result(String, String)

// ═══════════════════════════════════════════════════════════════
// GRAFANA — Dashboard JSON Builder (grafana_*)
// 2 NIF + 9 typed presets = 11 functions
// ═══════════════════════════════════════════════════════════════

/// Build a complete Grafana dashboard JSON model.
pub fn grafana_dashboard(
  title: String,
  panels_json: String,
) -> Result(String, String) {
  nif_grafana_dashboard_json(title, panels_json)
}

/// Build a Grafana panel from C3I presets.
/// Presets: health_gauge, container_table, ooda_timeseries, fractal_heatmap, task_bar, zenoh_graph, alert_list
pub fn grafana_panel_preset(
  preset: String,
  params_json: String,
) -> Result(String, String) {
  nif_grafana_panel_preset(preset, params_json)
}

/// Health gauge panel (0-100, red/yellow/green thresholds).
pub fn grafana_health_gauge(title: String) -> Result(String, String) {
  nif_grafana_panel_preset(
    "health_gauge",
    json.object([#("title", json.string(title))]) |> json.to_string(),
  )
}

/// Container health table panel.
pub fn grafana_container_table(title: String) -> Result(String, String) {
  nif_grafana_panel_preset(
    "container_table",
    json.object([#("title", json.string(title))]) |> json.to_string(),
  )
}

/// OODA cycle timeseries panel (4 phases).
pub fn grafana_ooda_timeseries(title: String) -> Result(String, String) {
  nif_grafana_panel_preset(
    "ooda_timeseries",
    json.object([#("title", json.string(title))]) |> json.to_string(),
  )
}

/// Fractal layer health heatmap panel.
pub fn grafana_fractal_heatmap(title: String) -> Result(String, String) {
  nif_grafana_panel_preset(
    "fractal_heatmap",
    json.object([#("title", json.string(title))]) |> json.to_string(),
  )
}

/// Task status bar chart panel.
pub fn grafana_task_bar(title: String) -> Result(String, String) {
  nif_grafana_panel_preset(
    "task_bar",
    json.object([#("title", json.string(title))]) |> json.to_string(),
  )
}

/// Zenoh mesh node graph panel.
pub fn grafana_zenoh_graph(title: String) -> Result(String, String) {
  nif_grafana_panel_preset(
    "zenoh_graph",
    json.object([#("title", json.string(title))]) |> json.to_string(),
  )
}

/// Alert list panel (C3I alerts).
pub fn grafana_alert_list(title: String) -> Result(String, String) {
  nif_grafana_panel_preset(
    "alert_list",
    json.object([#("title", json.string(title))]) |> json.to_string(),
  )
}

@external(erlang, "graphene_nif", "grafana_dashboard_json")
fn nif_grafana_dashboard_json(t: String, p: String) -> Result(String, String)

@external(erlang, "graphene_nif", "grafana_panel_preset")
fn nif_grafana_panel_preset(p: String, d: String) -> Result(String, String)

// ═══════════════════════════════════════════════════════════════
// PRE-DEFINED STATE MACHINES (c3i_*)
// ═══════════════════════════════════════════════════════════════

/// Planning page: 9 states, 15 transitions
pub fn c3i_page_state_machine() -> #(List(StateNode), List(StateEdge)) {
  #(
    [
      StateNode("LOADING", "amber"),
      StateNode("CONNECTED", "green"),
      StateNode("STALE", "amber"),
      StateNode("DISCONNECTED", "red"),
      StateNode("ERROR", "red"),
      StateNode("FILTERED", "blue"),
      StateNode("SEARCHING", "accent"),
      StateNode("DETAIL_OPEN", "accent"),
      StateNode("CHAT_OPEN", "accent"),
    ],
    [
      StateEdge(0, 1, "WsConnect"),
      StateEdge(0, 4, "Error"),
      StateEdge(1, 3, "WsDisconnect"),
      StateEdge(1, 5, "FilterLayer"),
      StateEdge(1, 6, "Search"),
      StateEdge(1, 7, "ClickTask"),
      StateEdge(1, 8, "OpenChat"),
      StateEdge(1, 2, "3s timeout"),
      StateEdge(2, 1, "WsUpdate"),
      StateEdge(3, 0, "WsReconnect"),
      StateEdge(4, 0, "Recover"),
      StateEdge(5, 1, "ClearFilter"),
      StateEdge(6, 1, "ClearSearch"),
      StateEdge(7, 1, "CloseDetail"),
      StateEdge(8, 1, "CloseChat"),
    ],
  )
}

/// C1 Weather Bar: 5 states, 12 transitions
pub fn c3i_c1_state_machine() -> #(List(StateNode), List(StateEdge)) {
  #(
    [
      StateNode("LOADING", "muted"),
      StateNode("HEALTHY", "green"),
      StateNode("DEGRADED", "amber"),
      StateNode("CRITICAL", "red"),
      StateNode("DISCONNECTED", "red"),
    ],
    [
      StateEdge(0, 1, "h>=85"),
      StateEdge(0, 2, "70<=h<85"),
      StateEdge(0, 3, "h<70"),
      StateEdge(0, 4, "Timeout"),
      StateEdge(1, 2, "h<85"),
      StateEdge(1, 4, "WsDisc"),
      StateEdge(2, 1, "h>=85"),
      StateEdge(2, 3, "h<70"),
      StateEdge(2, 4, "WsDisc"),
      StateEdge(3, 1, "h>=85"),
      StateEdge(3, 4, "WsDisc"),
      StateEdge(4, 0, "Reconnect"),
    ],
  )
}

/// C4 Task Grid: 7 states, 11 transitions
pub fn c3i_c4_state_machine() -> #(List(StateNode), List(StateEdge)) {
  #(
    [
      StateNode("LOADING", "muted"),
      StateNode("POPULATED", "green"),
      StateNode("FILTERED", "blue"),
      StateNode("SORTED", "accent"),
      StateNode("HIGHLIGHT", "amber"),
      StateNode("EMPTY", "muted"),
      StateNode("ERROR", "red"),
    ],
    [
      StateEdge(0, 1, "DataLoad"),
      StateEdge(0, 5, "NoData"),
      StateEdge(0, 6, "Error"),
      StateEdge(1, 2, "Filter"),
      StateEdge(1, 3, "Sort"),
      StateEdge(1, 4, "WsUpdate"),
      StateEdge(2, 1, "Clear"),
      StateEdge(3, 3, "Toggle"),
      StateEdge(4, 1, "1.8s"),
      StateEdge(5, 1, "DataLoad"),
      StateEdge(6, 0, "Retry"),
    ],
  )
}

/// Navigation digraph: 22 Lustre pages (SC-UIGT-001)
pub fn c3i_nav_graph_pages() -> #(String, String) {
  #(
    "[\"Dashboard\",\"Planning\",\"Immune\",\"Knowledge\",\"Zenoh\",\"Cockpit\",\"Verification\",\"Substrate\",\"Metabolic\",\"Podman\",\"Mcp\",\"Kms\",\"Telemetry\",\"Agents\",\"Bridge\",\"Config\",\"Database\",\"Git\",\"Holon\",\"Prajna\",\"Smriti\",\"PlanDash\"]",
    "[]",
  )
}
