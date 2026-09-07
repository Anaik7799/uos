//// Purpose: pure-string HTML dashboard builder for the UOS TUI web mirror.
//// Reference: conceptually mirrors a Textual/Rich static HTML export — no
//// external resources, theme-aware CSS via prefers-color-scheme + data-theme.
//// STAMP: SC-TUI-W10-001

import gleam/float
import gleam/list
import gleam/option
import gleam/string

/// Semantic tone used to color KPI cards and progress bars.
pub type Tone {
  Good
  Warn
  Bad
  Neutral
}

/// A single key performance indicator card.
pub type Kpi {
  Kpi(label: String, value: String, ratio: option.Option(Float), tone: Tone)
}

/// A simple table with a header row of columns and data rows.
pub type Table {
  Table(columns: List(String), rows: List(List(String)))
}

/// A node in the dashboard document tree.
pub type Node {
  KpiRow(List(Kpi))
  TableNode(Table)
  Progress(label: String, ratio: Float)
  Text(String)
  Pre(String)
  Link(text: String, href: String)
  Section(title: String, children: List(Node))
}

/// Escape the five HTML-significant characters for safe text/attribute use.
pub fn escape(text: String) -> String {
  text
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
  |> string.replace("\"", "&quot;")
  |> string.replace("'", "&#39;")
}

fn clamp_ratio(ratio: Float) -> Float {
  case ratio <. 0.0 {
    True -> 0.0
    False ->
      case ratio >. 1.0 {
        True -> 1.0
        False -> ratio
      }
  }
}

fn tone_class(tone: Tone) -> String {
  case tone {
    Good -> "tone-good"
    Warn -> "tone-warn"
    Bad -> "tone-bad"
    Neutral -> "tone-neutral"
  }
}

fn percent_string(ratio: Float) -> String {
  let clamped = clamp_ratio(ratio)
  let pct = clamped *. 100.0
  float.to_string(pct)
}

fn render_kpi(kpi: Kpi) -> String {
  let ratio_html = case kpi.ratio {
    option.Some(r) -> {
      let width = percent_string(r)
      "<div class=\"kpi-bar\"><div class=\"kpi-bar-fill "
      <> tone_class(kpi.tone)
      <> "\" style=\"width:"
      <> width
      <> "%\"></div></div>"
    }
    option.None -> ""
  }
  "<div class=\"kpi-card "
  <> tone_class(kpi.tone)
  <> "\"><div class=\"kpi-label\">"
  <> escape(kpi.label)
  <> "</div><div class=\"kpi-value\">"
  <> escape(kpi.value)
  <> "</div>"
  <> ratio_html
  <> "</div>"
}

fn render_kpi_row(kpis: List(Kpi)) -> String {
  "<div class=\"kpi-row\">"
  <> string.join(list.map(kpis, render_kpi), "")
  <> "</div>"
}

fn render_table_header(columns: List(String)) -> String {
  "<tr>"
  <> string.join(
    list.map(columns, fn(c) { "<th>" <> escape(c) <> "</th>" }),
    "",
  )
  <> "</tr>"
}

fn render_table_row(row: List(String)) -> String {
  "<tr>"
  <> string.join(
    list.map(row, fn(cell) { "<td>" <> escape(cell) <> "</td>" }),
    "",
  )
  <> "</tr>"
}

fn render_table(table: Table) -> String {
  "<div class=\"table-wrap\"><table><thead>"
  <> render_table_header(table.columns)
  <> "</thead><tbody>"
  <> string.join(list.map(table.rows, render_table_row), "")
  <> "</tbody></table></div>"
}

fn render_progress(label: String, ratio: Float) -> String {
  let width = percent_string(ratio)
  "<div class=\"progress\"><div class=\"progress-label\">"
  <> escape(label)
  <> "</div><div class=\"progress-track\"><div class=\"progress-fill\" style=\"width:"
  <> width
  <> "%\"></div></div></div>"
}

fn render_link(text: String, href: String) -> String {
  "<a class=\"tui-link\" href=\""
  <> escape(href)
  <> "\">"
  <> escape(text)
  <> "</a>"
}

fn render_section(title: String, children: List(Node)) -> String {
  "<section class=\"tui-section\"><h2>"
  <> escape(title)
  <> "</h2>"
  <> string.join(list.map(children, render), "")
  <> "</section>"
}

/// Render a single node to an HTML string fragment.
pub fn render(node: Node) -> String {
  case node {
    KpiRow(kpis) -> render_kpi_row(kpis)
    TableNode(table) -> render_table(table)
    Progress(label, ratio) -> render_progress(label, ratio)
    Text(text) -> "<p>" <> escape(text) <> "</p>"
    Pre(text) -> "<pre>" <> escape(text) <> "</pre>"
    Link(text, href) -> render_link(text, href)
    Section(title, children) -> render_section(title, children)
  }
}

const style = "
:root {
  --bg: #f6f7f9;
  --fg: #1b1f24;
  --card-bg: #ffffff;
  --border: #d7dbe0;
  --muted: #5b6472;
  --good: #1a7f37;
  --warn: #9a6700;
  --bad: #cf222e;
  --neutral: #57606a;
  --link: #0969da;
  --track: #e6e9ec;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme=\"light\"]) {
    --bg: #0d1117;
    --fg: #e6edf3;
    --card-bg: #161b22;
    --border: #30363d;
    --muted: #8b949e;
    --good: #3fb950;
    --warn: #d29922;
    --bad: #f85149;
    --neutral: #8b949e;
    --link: #58a6ff;
    --track: #21262d;
  }
}
:root[data-theme=\"dark\"] {
  --bg: #0d1117;
  --fg: #e6edf3;
  --card-bg: #161b22;
  --border: #30363d;
  --muted: #8b949e;
  --good: #3fb950;
  --warn: #d29922;
  --bad: #f85149;
  --neutral: #8b949e;
  --link: #58a6ff;
  --track: #21262d;
}
body { background: var(--bg); color: var(--fg); font-family: system-ui, sans-serif; margin: 0; padding: 1.5rem; }
.tui-header { border-bottom: 1px solid var(--border); padding-bottom: 1rem; margin-bottom: 1rem; }
.tui-header h1 { margin: 0 0 0.25rem 0; }
.tui-subtitle { color: var(--muted); margin: 0 0 0.5rem 0; }
.kpi-row { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 0.75rem; margin: 0.75rem 0; }
.kpi-card { background: var(--card-bg); border: 1px solid var(--border); border-radius: 8px; padding: 0.75rem; }
.kpi-label { color: var(--muted); font-size: 0.85rem; }
.kpi-value { font-size: 1.4rem; font-weight: 600; }
.kpi-bar { background: var(--track); border-radius: 4px; height: 6px; margin-top: 0.5rem; overflow: hidden; }
.kpi-bar-fill { height: 100%; }
.tone-good { color: var(--good); } .tone-good.kpi-bar-fill, .kpi-bar-fill.tone-good { background: var(--good); }
.tone-warn { color: var(--warn); } .kpi-bar-fill.tone-warn { background: var(--warn); }
.tone-bad { color: var(--bad); } .kpi-bar-fill.tone-bad { background: var(--bad); }
.tone-neutral { color: var(--neutral); } .kpi-bar-fill.tone-neutral { background: var(--neutral); }
.table-wrap { overflow-x: auto; margin: 0.75rem 0; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid var(--border); padding: 0.4rem 0.6rem; text-align: left; }
th { background: var(--card-bg); }
.progress { margin: 0.5rem 0; }
.progress-label { color: var(--muted); font-size: 0.85rem; margin-bottom: 0.25rem; }
.progress-track { background: var(--track); border-radius: 4px; height: 10px; overflow: hidden; }
.progress-fill { background: var(--link); height: 100%; }
.tui-link { color: var(--link); }
.tui-section { margin: 1rem 0; }
.tui-footer { border-top: 1px solid var(--border); color: var(--muted); font-size: 0.8rem; margin-top: 1.5rem; padding-top: 0.75rem; }
"

/// Render a complete dashboard page body fragment (no doctype/html/head/body
/// wrapper tags — the host page supplies those).
pub fn page(
  title: String,
  subtitle: String,
  fqdn_href: String,
  nodes: List(Node),
) -> String {
  "<title>"
  <> escape(title)
  <> "</title><style>"
  <> style
  <> "</style><header class=\"tui-header\"><h1>"
  <> escape(title)
  <> "</h1><p class=\"tui-subtitle\">"
  <> escape(subtitle)
  <> "</p>"
  <> render_link(fqdn_href, fqdn_href)
  <> "</header><main>"
  <> string.join(list.map(nodes, render), "")
  <> "</main><footer class=\"tui-footer\">nas-1.tail55d152.ts.net:4100 \u{00b7} vm-1.tail55d152.ts.net:8088</footer>"
}
