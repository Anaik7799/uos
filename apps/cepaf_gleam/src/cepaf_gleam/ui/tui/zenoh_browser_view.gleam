// STAMP: SC-GLM-UI-001, SC-ZENOH-001
import cepaf_gleam/ui/lustre/zenoh_browser.{type ZenohBrowserModel, type TopicNode}
import gleam/list
import gleam/string

pub fn render(model: ZenohBrowserModel) -> String {
  let header = "\u{001b}[1;36m▌ Zenoh Topic Browser\u{001b}[0m  Topics: " <> int_str(zenoh_browser.total_topics(model))
  let tree = list.map(model.root, fn(n) { render_node(n, 0) }) |> string.join("\n")
  header <> "\n" <> tree
}
fn render_node(node: TopicNode, depth: Int) -> String {
  let indent = string.repeat("  ", depth)
  let line = indent <> "\u{001b}[36m" <> node.path <> "\u{001b}[0m (" <> int_str(node.message_count) <> ")"
  let children = list.map(node.children, fn(c) { render_node(c, depth + 1) }) |> string.join("\n")
  case children {
    "" -> line
    c -> line <> "\n" <> c
  }
}
@external(erlang, "erlang", "integer_to_binary")
fn int_str(i: Int) -> String
