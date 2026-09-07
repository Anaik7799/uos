//// Widget tree (Textual `Widget` DOM and built-in widget gallery reference).
//// Widgets are pure data; the model owns all state (TEA). Interactive widgets carry
//// callbacks that lift user intent into `msg` values, never side effects.
//// Reference mapping (Textual -> uos_tui): Header, Footer, Static/Label, Button, Input,
//// DataTable, Tree, ListView, ProgressBar, Sparkline, Tabs/TabbedContent, RichLog/Log,
//// Rule, Vertical/Horizontal containers, Grid. UOS additions: Checklist, StatusBar.
//// STAMP: SC-TUI-WIDGET-001.

import gleam/list
import gleam/option.{type Option}
import uos_tui/event.{type Key}
import uos_tui/layout.{type Direction, type Scalar}
import uos_tui/style.{type Style}

pub type Binding(msg) {
  Binding(key: Key, action: msg, description: String)
}

pub type Column {
  Column(label: String, width: Scalar)
}

pub type TreeNode {
  TreeNode(label: String, expanded: Bool, children: List(TreeNode))
}

pub type ChecklistItem {
  ChecklistItem(id: String, label: String, passed: Bool)
}

pub type ChecklistDomain {
  ChecklistDomain(title: String, items: List(ChecklistItem))
}

pub type StatusField {
  StatusField(label: String, value: String, style: Style)
}

pub type Widget(msg) {
  Static(id: String, text: String, style: Style)
  Header(id: String, title: String, subtitle: String, style: Style)
  Footer(id: String, bindings: List(Binding(msg)))
  Button(id: String, label: String, on_press: msg)
  Input(
    id: String,
    value: String,
    cursor: Int,
    placeholder: String,
    on_change: fn(String) -> msg,
    on_submit: Option(msg),
  )
  DataTable(
    id: String,
    columns: List(Column),
    rows: List(List(String)),
    cursor: Int,
    on_move: Option(fn(Int) -> msg),
    on_select: Option(fn(Int) -> msg),
  )
  Tree(id: String, root: TreeNode, cursor: Int, on_move: Option(fn(Int) -> msg))
  ListView(
    id: String,
    items: List(String),
    cursor: Int,
    on_move: Option(fn(Int) -> msg),
    on_select: Option(fn(Int) -> msg),
  )
  ProgressBar(id: String, ratio: Float, label: String)
  Sparkline(id: String, data: List(Float), style: Style)
  Tabs(
    id: String,
    labels: List(String),
    active: Int,
    on_change: Option(fn(Int) -> msg),
  )
  Log(id: String, lines: List(String), scroll: Int)
  Rule(id: String, title: String)
  Container(
    id: String,
    direction: Direction,
    children: List(#(Scalar, Widget(msg))),
    border: Bool,
    title: String,
  )
  Grid(
    id: String,
    columns: List(Scalar),
    rows: List(Scalar),
    cells: List(Widget(msg)),
  )
  Checklist(
    id: String,
    domains: List(ChecklistDomain),
    expanded: List(Int),
    on_toggle: Option(fn(Int) -> msg),
  )
  StatusBar(id: String, fields: List(StatusField))
}

pub fn id_of(widget: Widget(msg)) -> String {
  case widget {
    Static(id, ..) -> id
    Header(id, ..) -> id
    Footer(id, ..) -> id
    Button(id, ..) -> id
    Input(id, ..) -> id
    DataTable(id, ..) -> id
    Tree(id, ..) -> id
    ListView(id, ..) -> id
    ProgressBar(id, ..) -> id
    Sparkline(id, ..) -> id
    Tabs(id, ..) -> id
    Log(id, ..) -> id
    Rule(id, ..) -> id
    Container(id, ..) -> id
    Grid(id, ..) -> id
    Checklist(id, ..) -> id
    StatusBar(id, ..) -> id
  }
}

/// Widget family name (for catalog coverage audits).
pub fn kind_of(widget: Widget(msg)) -> String {
  case widget {
    Static(..) -> "Static"
    Header(..) -> "Header"
    Footer(..) -> "Footer"
    Button(..) -> "Button"
    Input(..) -> "Input"
    DataTable(..) -> "DataTable"
    Tree(..) -> "Tree"
    ListView(..) -> "ListView"
    ProgressBar(..) -> "ProgressBar"
    Sparkline(..) -> "Sparkline"
    Tabs(..) -> "Tabs"
    Log(..) -> "Log"
    Rule(..) -> "Rule"
    Container(..) -> "Container"
    Grid(..) -> "Grid"
    Checklist(..) -> "Checklist"
    StatusBar(..) -> "StatusBar"
  }
}

pub const catalog = [
  "Static", "Header", "Footer", "Button", "Input", "DataTable", "Tree",
  "ListView", "ProgressBar", "Sparkline", "Tabs", "Log", "Rule", "Container",
  "Grid", "Checklist", "StatusBar",
]

pub fn children(widget: Widget(msg)) -> List(Widget(msg)) {
  case widget {
    Container(children: kids, ..) -> list.map(kids, fn(k) { k.1 })
    Grid(cells: cells, ..) -> cells
    _ -> []
  }
}

/// Pre-order traversal of the whole tree.
pub fn flatten(widget: Widget(msg)) -> List(Widget(msg)) {
  [widget, ..list.flat_map(children(widget), flatten)]
}

pub fn find(widget: Widget(msg), id: String) -> Option(Widget(msg)) {
  widget |> flatten |> list.find(fn(w) { id_of(w) == id }) |> option.from_result
}

pub fn is_focusable(widget: Widget(msg)) -> Bool {
  case widget {
    Button(..)
    | Input(..)
    | DataTable(..)
    | Tree(..)
    | ListView(..)
    | Tabs(..)
    | Checklist(..) -> True
    _ -> False
  }
}

/// Focus chain in document order (Textual focus chain reference).
pub fn focus_chain(widget: Widget(msg)) -> List(String) {
  widget |> flatten |> list.filter(is_focusable) |> list.map(id_of)
}

/// All plain text a widget displays (used by audits and tests).
pub fn texts(widget: Widget(msg)) -> List(String) {
  case widget {
    Static(_, text, _) -> [text]
    Header(_, title, subtitle, _) -> [title, subtitle]
    Footer(_, bindings) -> list.map(bindings, fn(b) { b.description })
    Button(_, label, _) -> [label]
    Input(_, value, _, placeholder, _, _) -> [value, placeholder]
    DataTable(_, columns, rows, _, _, _) ->
      list.append(list.map(columns, fn(c) { c.label }), list.flatten(rows))
    Tree(_, root, _, _) -> tree_labels(root)
    ListView(_, items, _, _, _) -> items
    ProgressBar(_, _, label) -> [label]
    Sparkline(..) -> []
    Tabs(_, labels, _, _) -> labels
    Log(_, lines, _) -> lines
    Rule(_, title) -> [title]
    Container(_, _, kids, _, title) -> [
      title,
      ..list.flat_map(kids, fn(k) { texts(k.1) })
    ]
    Grid(_, _, _, cells) -> list.flat_map(cells, texts)
    Checklist(_, domains, _, _) ->
      list.flat_map(domains, fn(d) {
        [d.title, ..list.map(d.items, fn(i) { i.id <> " " <> i.label })]
      })
    StatusBar(_, fields) ->
      list.map(fields, fn(f) { f.label <> " " <> f.value })
  }
}

fn tree_labels(node: TreeNode) -> List(String) {
  [node.label, ..list.flat_map(node.children, tree_labels)]
}

/// Visible rows of a tree (respecting `expanded`), with depth.
pub fn tree_rows(node: TreeNode) -> List(#(Int, TreeNode)) {
  tree_rows_at(node, 0)
}

fn tree_rows_at(node: TreeNode, depth: Int) -> List(#(Int, TreeNode)) {
  let rest = case node.expanded {
    True -> list.flat_map(node.children, tree_rows_at(_, depth + 1))
    False -> []
  }
  [#(depth, node), ..rest]
}

/// Minimum content height a widget needs (used for `Auto` scalars).
pub fn min_height(widget: Widget(msg)) -> Int {
  case widget {
    Static(..) -> 1
    Header(..) -> 1
    Footer(..) -> 1
    Button(..) -> 1
    Input(..) -> 1
    DataTable(_, _, rows, _, _, _) -> list.length(rows) + 2
    Tree(_, root, _, _) -> list.length(tree_rows(root))
    ListView(_, items, _, _, _) -> list.length(items)
    ProgressBar(..) -> 1
    Sparkline(..) -> 1
    Tabs(..) -> 1
    Log(_, lines, _) -> list.length(lines)
    Rule(..) -> 1
    Container(_, layout.Vertical, kids, border, _) -> {
      let inner = list.fold(kids, 0, fn(acc, k) { acc + min_height(k.1) })
      case border {
        True -> inner + 2
        False -> inner
      }
    }
    Container(_, layout.Horizontal, kids, border, _) -> {
      let inner =
        list.fold(kids, 0, fn(acc, k) { int_max(acc, min_height(k.1)) })
      case border {
        True -> inner + 2
        False -> inner
      }
    }
    Grid(_, _, rows, _) -> list.length(rows)
    Checklist(_, domains, expanded, _) ->
      list.index_fold(domains, 0, fn(acc, d, i) {
        case list.contains(expanded, i) {
          True -> acc + 1 + list.length(d.items)
          False -> acc + 1
        }
      })
    StatusBar(..) -> 1
  }
}

fn int_max(a: Int, b: Int) -> Int {
  case a > b {
    True -> a
    False -> b
  }
}

/// Neutral style for callers that do not import `uos_tui/style`.
pub fn no_style() -> Style {
  style.none
}
