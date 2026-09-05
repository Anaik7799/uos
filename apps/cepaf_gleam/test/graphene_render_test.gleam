import cepaf_gleam/graphene.{
  Point2, StateEdge, StateMachine, StateNode, SvgCircle, SvgPolygon, SvgRect,
  SvgStar, Transform2D,
}
import cepaf_gleam/testing/nav_graph
import gleam/list
import gleeunit/should

const out = "/home/an/dev/ver/c3i/docs/wireframes/graphene"

pub fn page_state_diagram_test() {
  let #(nodes, edges) = graphene.c3i_page_state_machine()
  graphene.skia_render_state_diagram(
    "PLANNING PAGE — State Machine",
    nodes,
    edges,
    out <> "/page_states.png",
    1200,
    600,
  )
  |> should.be_ok()
}

pub fn c1_state_diagram_test() {
  let #(nodes, edges) = graphene.c3i_c1_state_machine()
  graphene.skia_render_state_diagram(
    "C1 WEATHER BAR — State Machine",
    nodes,
    edges,
    out <> "/c1_states.png",
    1000,
    450,
  )
  |> should.be_ok()
}

pub fn c4_state_diagram_test() {
  let #(nodes, edges) = graphene.c3i_c4_state_machine()
  graphene.skia_render_state_diagram(
    "C4 TASK GRID — State Machine",
    nodes,
    edges,
    out <> "/c4_states.png",
    1100,
    450,
  )
  |> should.be_ok()
}

pub fn c4_triage_state_diagram_test() {
  graphene.skia_render_state_diagram(
    "C4.zones TRIAGE — State Machine",
    [
      StateNode("LOADING", "muted"),
      StateNode("NORMAL", "red"),
      StateNode("NO_CRIT", "amber"),
      StateNode("ALL_NOM", "green"),
      StateNode("ALL_CRIT", "red"),
    ],
    [
      StateEdge(0, 1, "p0>0"),
      StateEdge(0, 2, "p0=0"),
      StateEdge(0, 3, "blk=0"),
      StateEdge(0, 4, "p0=all"),
      StateEdge(1, 2, "LastP0"),
      StateEdge(1, 3, "Unblk"),
      StateEdge(2, 1, "NewP0"),
      StateEdge(3, 1, "NewBlk"),
    ],
    out <> "/c4z_states.png",
    1000,
    450,
  )
  |> should.be_ok()
}

pub fn c5_state_diagram_test() {
  graphene.skia_render_state_diagram(
    "C5 KANBAN — State Machine",
    [
      StateNode("LOADING", "muted"),
      StateNode("NORMAL", "green"),
      StateNode("OVERFLOW", "amber"),
      StateNode("SINGLE_COL", "blue"),
      StateNode("DONE_EXP", "green"),
    ],
    [
      StateEdge(0, 1, "Data"),
      StateEdge(1, 2, ">20 cards"),
      StateEdge(1, 3, "<768px"),
      StateEdge(1, 4, "ClickDone"),
      StateEdge(3, 1, ">=768px"),
      StateEdge(4, 1, "Collapse"),
    ],
    out <> "/c5_states.png",
    1000,
    450,
  )
  |> should.be_ok()
}

pub fn c8_state_diagram_test() {
  graphene.skia_render_state_diagram(
    "C8 AI SEARCH — State Machine",
    [
      StateNode("HIDDEN", "muted"),
      StateNode("ACTIVE", "accent"),
      StateNode("TYPING", "accent"),
      StateNode("SEARCHING", "amber"),
      StateNode("RESULTS", "green"),
      StateNode("NO_RESULTS", "muted"),
    ],
    [
      StateEdge(0, 1, "Ctrl+K"),
      StateEdge(1, 2, "Type"),
      StateEdge(1, 0, "Esc"),
      StateEdge(2, 3, "200ms"),
      StateEdge(2, 0, "Esc"),
      StateEdge(3, 4, "Found"),
      StateEdge(3, 5, "None"),
      StateEdge(4, 0, "Click"),
      StateEdge(5, 2, "Type"),
    ],
    out <> "/c8_states.png",
    1000,
    450,
  )
  |> should.be_ok()
}

pub fn c9_state_diagram_test() {
  graphene.skia_render_state_diagram(
    "C9 DETAIL PANEL — State Machine",
    [
      StateNode("CLOSED", "muted"),
      StateNode("OPENING", "accent"),
      StateNode("OPEN", "accent"),
      StateNode("LOAD_AI", "amber"),
      StateNode("AI_DONE", "green"),
      StateNode("RELATED", "blue"),
    ],
    [
      StateEdge(0, 1, "ClickTask"),
      StateEdge(1, 2, "200ms"),
      StateEdge(2, 0, "Close"),
      StateEdge(2, 3, "AI"),
      StateEdge(2, 5, "Related"),
      StateEdge(3, 4, "Response"),
      StateEdge(4, 0, "Close"),
      StateEdge(5, 2, "Click"),
    ],
    out <> "/c9_states.png",
    1000,
    450,
  )
  |> should.be_ok()
}

pub fn c10_state_diagram_test() {
  graphene.skia_render_state_diagram(
    "C10 GEMMA CHAT — State Machine",
    [
      StateNode("HIDDEN", "muted"),
      StateNode("MINIMIZED", "muted"),
      StateNode("OPEN", "accent"),
      StateNode("TYPING", "accent"),
      StateNode("WAITING", "amber"),
      StateNode("RESPONSE", "green"),
      StateNode("ERROR", "red"),
    ],
    [
      StateEdge(0, 2, "ClickAI"),
      StateEdge(1, 2, "Click"),
      StateEdge(2, 0, "Close"),
      StateEdge(2, 3, "Type"),
      StateEdge(3, 4, "Send"),
      StateEdge(4, 5, "Response"),
      StateEdge(4, 6, "Timeout"),
      StateEdge(5, 2, "Done"),
      StateEdge(6, 4, "Retry"),
    ],
    out <> "/c10_states.png",
    1000,
    500,
  )
  |> should.be_ok()
}

pub fn c11_state_diagram_test() {
  graphene.skia_render_state_diagram(
    "C11 CHANGE LOG — State Machine",
    [
      StateNode("EMPTY", "muted"),
      StateNode("TICKER", "accent"),
      StateNode("EXPANDED", "accent"),
      StateNode("TOAST", "amber"),
    ],
    [
      StateEdge(0, 1, "Desktop"),
      StateEdge(0, 3, "Mobile"),
      StateEdge(1, 2, "Click"),
      StateEdge(2, 1, "Collapse"),
      StateEdge(3, 0, "3s timeout"),
    ],
    out <> "/c11_states.png",
    800,
    400,
  )
  |> should.be_ok()
}

pub fn c12_state_diagram_test() {
  graphene.skia_render_state_diagram(
    "C12 FRACTAL FILTER — State Machine",
    [StateNode("ALL_SHOWN", "accent"), StateNode("SELECTED", "blue")],
    [
      StateEdge(0, 1, "ClickLayer"),
      StateEdge(1, 0, "Toggle"),
      StateEdge(1, 1, "Switch"),
    ],
    out <> "/c12_states.png",
    600,
    350,
  )
  |> should.be_ok()
}

pub fn c2_state_diagram_test() {
  graphene.skia_render_state_diagram(
    "C2 PROGRESS RINGS — State Machine",
    [
      StateNode("LOADING", "muted"),
      StateNode("NORMAL", "green"),
      StateNode("ALL_BLOCKED", "red"),
      StateNode("ALL_COMPLETE", "green"),
      StateNode("EMPTY", "muted"),
    ],
    [
      StateEdge(0, 1, "Data"),
      StateEdge(0, 2, "AllBlk"),
      StateEdge(0, 3, "AllDone"),
      StateEdge(0, 4, "NoData"),
      StateEdge(1, 2, "AllBlk"),
      StateEdge(1, 3, "AllDone"),
      StateEdge(2, 1, "Unblock"),
      StateEdge(3, 1, "NewTask"),
    ],
    out <> "/c2_states.png",
    1000,
    450,
  )
  |> should.be_ok()
}

pub fn c6_state_diagram_test() {
  graphene.skia_render_state_diagram(
    "C6 TIMELINE — State Machine",
    [
      StateNode("LOADING", "muted"),
      StateNode("NORMAL", "green"),
      StateNode("ZOOMED", "accent"),
      StateNode("FILTERED", "blue"),
      StateNode("EMPTY", "muted"),
    ],
    [
      StateEdge(0, 1, "Data"),
      StateEdge(0, 4, "NoData"),
      StateEdge(1, 2, "Zoom"),
      StateEdge(1, 3, "Filter"),
      StateEdge(2, 1, "Reset"),
      StateEdge(3, 1, "Clear"),
      StateEdge(4, 1, "Data"),
    ],
    out <> "/c6_states.png",
    1000,
    450,
  )
  |> should.be_ok()
}

pub fn c7_state_diagram_test() {
  graphene.skia_render_state_diagram(
    "C7 ANALYTICS — State Machine",
    [
      StateNode("LOADING", "muted"),
      StateNode("POPULATED", "green"),
      StateNode("REFRESHING", "amber"),
      StateNode("ERROR", "red"),
    ],
    [
      StateEdge(0, 1, "Compute"),
      StateEdge(1, 2, "5s timer"),
      StateEdge(2, 1, "Data"),
      StateEdge(2, 3, "Error"),
      StateEdge(3, 0, "Retry"),
    ],
    out <> "/c7_states.png",
    800,
    400,
  )
  |> should.be_ok()
}

pub fn component_c1_wireframe_test() {
  graphene.skia_render_component("c1_weather", out <> "/comp_c1.png")
  |> should.be_ok()
}

pub fn component_c2_wireframe_test() {
  graphene.skia_render_component("c2_rings", out <> "/comp_c2.png")
  |> should.be_ok()
}

pub fn component_c4_wireframe_test() {
  graphene.skia_render_component("c4_grid", out <> "/comp_c4.png")
  |> should.be_ok()
}

pub fn component_c9_wireframe_test() {
  graphene.skia_render_component("c9_detail", out <> "/comp_c9.png")
  |> should.be_ok()
}

pub fn component_c11_wireframe_test() {
  graphene.skia_render_component("c11_changelog", out <> "/comp_c11.png")
  |> should.be_ok()
}

pub fn component_c12_wireframe_test() {
  graphene.skia_render_component("c12_fractal", out <> "/comp_c12.png")
  |> should.be_ok()
}

pub fn viewport_state_diagram_test() {
  graphene.skia_render_state_diagram(
    "VIEWPORT ADAPTATION — State Machine",
    [
      StateNode("MOBILE <768", "red"),
      StateNode("TABLET 768-1023", "amber"),
      StateNode("DESKTOP 1024-1399", "blue"),
      StateNode("WIDE 1400+", "green"),
    ],
    [
      StateEdge(0, 1, "resize>=768"),
      StateEdge(1, 0, "resize<768"),
      StateEdge(1, 2, "resize>=1024"),
      StateEdge(2, 1, "resize<1024"),
      StateEdge(2, 3, "resize>=1400"),
      StateEdge(3, 2, "resize<1400"),
    ],
    out <> "/viewport_states.png",
    1000,
    400,
  )
  |> should.be_ok()
}

pub fn view_substate_diagram_test() {
  graphene.skia_render_state_diagram(
    "VIEW SUB-STATES — Tab Navigation",
    [
      StateNode("GRID", "green"),
      StateNode("KANBAN", "blue"),
      StateNode("TIMELINE", "amber"),
      StateNode("ANALYTICS", "accent"),
      StateNode("FRACTAL", "l4"),
    ],
    [
      StateEdge(0, 1, "key 2"),
      StateEdge(0, 2, "key 3"),
      StateEdge(0, 3, "key 4"),
      StateEdge(0, 4, "key 5"),
      StateEdge(1, 0, "key 1"),
      StateEdge(1, 2, "key 3"),
      StateEdge(1, 3, "key 4"),
      StateEdge(2, 0, "key 1"),
      StateEdge(2, 1, "key 2"),
      StateEdge(3, 0, "key 1"),
      StateEdge(3, 4, "key 5"),
      StateEdge(4, 0, "key 1"),
      StateEdge(4, 3, "key 4"),
    ],
    out <> "/view_states.png",
    1000,
    450,
  )
  |> should.be_ok()
}

pub fn graph_bfs_test() {
  let n = "[\"Dashboard\",\"Planning\",\"Immune\",\"Zenoh\"]"
  let e =
    "[[\"Dashboard\",\"Planning\",1],[\"Dashboard\",\"Immune\",1],[\"Planning\",\"Zenoh\",1]]"
  graphene.graphene_bfs(n, e, "Dashboard") |> should.be_ok()
}

pub fn graph_scc_test() {
  let n = "[\"A\",\"B\",\"C\"]"
  let e = "[[\"A\",\"B\",1],[\"B\",\"C\",1],[\"C\",\"A\",1]]"
  graphene.graphene_scc(n, e) |> should.be_ok()
}

pub fn graph_pagerank_test() {
  let n = "[\"Dashboard\",\"Planning\",\"Immune\"]"
  let e =
    "[[\"Dashboard\",\"Planning\",1],[\"Planning\",\"Immune\",1],[\"Immune\",\"Dashboard\",1]]"
  graphene.graphene_pagerank(n, e, 0.85, 30) |> should.be_ok()
}

pub fn graph_topological_sort_test() {
  let n = "[\"Zenoh\",\"DB\",\"Obs\",\"App\"]"
  let e = "[[\"Zenoh\",\"DB\",1],[\"DB\",\"Obs\",1],[\"Obs\",\"App\",1]]"
  graphene.graphene_topological_sort(n, e) |> should.be_ok()
}

// Graphite vector graphics tests

pub fn svg_path_from_points_test() {
  graphene.kurbo_path_from_points("[[0,0],[100,0],[100,100],[0,100]]")
  |> should.be_ok()
}

pub fn svg_path_analyze_test() {
  graphene.kurbo_path_analyze("M 0 0 L 100 0 L 100 100 L 0 100 Z")
  |> should.be_ok()
}

pub fn svg_shape_rect_test() {
  graphene.kurbo_shape("{\"type\":\"rect\",\"x\":0,\"y\":0,\"w\":100,\"h\":50}")
  |> should.be_ok()
}

pub fn svg_shape_circle_test() {
  graphene.kurbo_shape("{\"type\":\"circle\",\"cx\":50,\"cy\":50,\"r\":30}")
  |> should.be_ok()
}

pub fn svg_shape_star_test() {
  graphene.kurbo_shape(
    "{\"type\":\"star\",\"cx\":50,\"cy\":50,\"r_outer\":40,\"r_inner\":20,\"points\":5}",
  )
  |> should.be_ok()
}

pub fn svg_shape_polygon_test() {
  graphene.kurbo_shape(
    "{\"type\":\"polygon\",\"cx\":50,\"cy\":50,\"r\":30,\"sides\":6}",
  )
  |> should.be_ok()
}

pub fn svg_path_transform_test() {
  graphene.kurbo_path_transform(
    "M 0 0 L 100 0 L 100 100 Z",
    "{\"translate\":[50,50],\"rotate\":45}",
  )
  |> should.be_ok()
}

pub fn vec2_distance_test() {
  graphene.kurbo_vec2_math("distance", "{\"a\":[0,0],\"b\":[3,4]}")
  |> should.be_ok()
}

pub fn vec2_lerp_test() {
  graphene.kurbo_vec2_math("lerp", "{\"a\":[0,0],\"b\":[100,100],\"t\":0.5}")
  |> should.be_ok()
}

pub fn vec2_normalize_test() {
  graphene.kurbo_vec2_math("normalize", "{\"v\":[3,4]}")
  |> should.be_ok()
}

pub fn vec2_dot_test() {
  graphene.kurbo_vec2_math("dot", "{\"a\":[1,0],\"b\":[0,1]}")
  |> should.be_ok()
}

pub fn vec2_angle_test() {
  graphene.kurbo_vec2_math("angle", "{\"a\":[1,0],\"b\":[0,1]}")
  |> should.be_ok()
}
// [ZERO-MUDA] Bevy tests purged.

// Mermaid tests

pub fn mermaid_flowchart_test() {
  graphene.mermaid_render(
    "flowchart LR\n  A[Start]-->B[Build]\n  B-->C[Test]\n  C-->D[Deploy]",
    "svg",
  )
  |> should.be_ok()
}

pub fn mermaid_state_diagram_test() {
  graphene.mermaid_render(
    "stateDiagram-v2\n  [*]-->Loading\n  Loading-->Connected\n  Connected-->Disconnected\n  Disconnected-->Loading",
    "svg",
  )
  |> should.be_ok()
}

pub fn mermaid_render_to_file_test() {
  graphene.mermaid_render_to_file(
    "flowchart TD\n  A-->B\n  B-->C",
    out <> "/mermaid_test.svg",
  )
  |> should.be_ok()
}

// ═══════════════════════════════════════════════════════════════
// 100% API coverage tests — every typed wrapper
// ═══════════════════════════════════════════════════════════════

// §2b Typed graph builders
pub fn build_graph_test() {
  let #(n, e) =
    graphene.graphene_build_graph(["A", "B", "C"], [
      #("A", "B", 1),
      #("B", "C", 2),
    ])
  graphene.graphene_bfs(n, e, "A") |> should.be_ok()
}

pub fn bfs_typed_test() {
  graphene.graphene_bfs_typed(
    ["X", "Y", "Z"],
    [#("X", "Y", 1), #("Y", "Z", 1)],
    "X",
  )
  |> should.be_ok()
}

pub fn dfs_typed_test() {
  graphene.graphene_dfs_typed(
    ["X", "Y", "Z"],
    [#("X", "Y", 1), #("Y", "Z", 1)],
    "X",
  )
  |> should.be_ok()
}

pub fn topological_sort_typed_test() {
  graphene.graphene_topological_sort_typed(["A", "B", "C"], [
    #("A", "B", 1),
    #("B", "C", 1),
  ])
  |> should.be_ok()
}

pub fn scc_typed_test() {
  graphene.graphene_scc_typed(["A", "B", "C"], [
    #("A", "B", 1),
    #("B", "C", 1),
    #("C", "A", 1),
  ])
  |> should.be_ok()
}

pub fn shortest_path_typed_test() {
  graphene.graphene_shortest_path_typed(
    ["A", "B", "C"],
    [#("A", "B", 4), #("A", "C", 2), #("C", "B", 1)],
    "A",
    "B",
  )
  |> should.be_ok()
}

pub fn pagerank_typed_test() {
  graphene.graphene_pagerank_typed(
    ["A", "B", "C"],
    [#("A", "B", 1), #("B", "C", 1), #("C", "A", 1)],
    0.85,
    30,
  )
  |> should.be_ok()
}

pub fn analyze_typed_test() {
  graphene.graphene_analyze_typed(["A", "B", "C"], [
    #("A", "B", 1),
    #("B", "C", 1),
  ])
  |> should.be_ok()
}

// §4 Typed SVG shape wrappers
pub fn svg_shape_typed_rect_test() {
  graphene.kurbo_shape_typed(SvgRect(0.0, 0.0, 100.0, 50.0))
  |> should.be_ok()
}

pub fn svg_shape_typed_circle_test() {
  graphene.kurbo_shape_typed(SvgCircle(50.0, 50.0, 30.0))
  |> should.be_ok()
}

pub fn svg_shape_typed_star_test() {
  graphene.kurbo_shape_typed(SvgStar(50.0, 50.0, 40.0, 20.0, 5))
  |> should.be_ok()
}

pub fn svg_shape_typed_polygon_test() {
  graphene.kurbo_shape_typed(SvgPolygon(50.0, 50.0, 30.0, 6))
  |> should.be_ok()
}

pub fn svg_path_apply_transform_test() {
  graphene.kurbo_path_apply_transform(
    "M 0 0 L 100 0 L 100 100 Z",
    Transform2D(Point2(50.0, 50.0), 45.0, Point2(2.0, 2.0)),
  )
  |> should.be_ok()
}

// §5b Typed vec2 wrappers
pub fn vec2_normalize_typed_test() {
  graphene.kurbo_vec2_normalize(Point2(3.0, 4.0)) |> should.be_ok()
}

pub fn vec2_dot_typed_test() {
  graphene.kurbo_vec2_dot(Point2(1.0, 0.0), Point2(0.0, 1.0)) |> should.be_ok()
}

pub fn vec2_angle_typed_test() {
  graphene.kurbo_vec2_angle(Point2(1.0, 0.0), Point2(0.0, 1.0))
  |> should.be_ok()
}

pub fn vec2_distance_typed_test() {
  graphene.kurbo_vec2_distance(Point2(0.0, 0.0), Point2(3.0, 4.0))
  |> should.be_ok()
}

pub fn vec2_lerp_typed_test() {
  graphene.kurbo_vec2_lerp(Point2(0.0, 0.0), Point2(100.0, 100.0), 0.5)
  |> should.be_ok()
}

// [ZERO-MUDA] Purged remaining bevy math calls.

// [ZERO-MUDA] Bevy math/color tests purged.

// §6b Typed mermaid builders
pub fn build_mermaid_flowchart_test() {
  let mermaid =
    graphene.mermaid_build_flowchart(
      "LR",
      [#("A", "Start"), #("B", "Build"), #("C", "Test"), #("D", "Deploy")],
      [#("A", "B", ""), #("B", "C", "compile"), #("C", "D", "pass")],
    )
  graphene.mermaid_render(mermaid, "svg") |> should.be_ok()
}

pub fn build_mermaid_sequence_test() {
  let mermaid =
    graphene.mermaid_build_sequence(["Client", "Server", "DB"], [
      #("Client", "Server", "GET /api"),
      #("Server", "DB", "SELECT"),
      #("DB", "Server", "rows"),
    ])
  graphene.mermaid_render(mermaid, "svg") |> should.be_ok()
}

pub fn render_machine_test() {
  let machine =
    StateMachine(
      [
        StateNode("IDLE", "green"),
        StateNode("ACTIVE", "blue"),
        StateNode("ERROR", "red"),
      ],
      [
        StateEdge(0, 1, "Start"),
        StateEdge(1, 0, "Stop"),
        StateEdge(1, 2, "Fail"),
      ],
    )
  graphene.skia_render_machine(
    "Test Machine",
    machine,
    out <> "/machine_test.png",
    800,
    400,
  )
  |> should.be_ok()
}

pub fn render_machine_mermaid_test() {
  let machine =
    StateMachine([StateNode("IDLE", "green"), StateNode("ACTIVE", "blue")], [
      StateEdge(0, 1, "Start"),
      StateEdge(1, 0, "Stop"),
    ])
  graphene.mermaid_render_machine(machine, out <> "/machine_mermaid_test.svg")
  |> should.be_ok()
}

pub fn build_mermaid_state_diagram_test() {
  let #(nodes, edges) = graphene.c3i_c1_state_machine()
  let machine = StateMachine(nodes, edges)
  let mermaid = graphene.mermaid_build_state_diagram(machine)
  graphene.mermaid_render(mermaid, "svg") |> should.be_ok()
}

// ═══════════════════════════════════════════════════════════════
// CI Quality Gates — Navigation Graph Structural Invariants
// SC-UIGT-012: SCC=1 (all pages reachable)
// SC-MOKSHA-002: page count MUST NOT decrease
// ═══════════════════════════════════════════════════════════════

/// Navigation graph MUST be strongly connected (SCC=1).
/// If this test fails, a page is unreachable — deployment BLOCKED (SC-UIGT-012).
pub fn nav_graph_scc_gate_test() {
  let scc = nav_graph.scc_count()
  scc |> should.equal(1)
}

/// Page count must be >= 31 (never decrease per SC-MOKSHA-002).
pub fn nav_graph_page_count_gate_test() {
  let pages = nav_graph.all_pages() |> list.length()
  let assert True = pages >= 31
}
