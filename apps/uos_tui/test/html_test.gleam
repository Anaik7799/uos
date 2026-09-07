//// Purpose: tests for uos_tui/html — the pure-string HTML dashboard builder.
//// Reference: property + fuzz coverage via test/prng.gleam.
//// STAMP: SC-TUI-W10-001

import gleam/list
import gleam/option
import gleam/string
import gleeunit/should
import prng
import uos_tui/html.{
  type Node, Bad, Good, Kpi, KpiRow, Link, Neutral, Pre, Progress, Section,
  Table, TableNode, Text, Warn,
}

pub fn escape_all_chars_test() {
  html.escape("&<>\"'")
  |> should.equal("&amp;&lt;&gt;&quot;&#39;")
}

pub fn escape_plain_text_unchanged_test() {
  html.escape("hello world")
  |> should.equal("hello world")
}

pub fn page_contains_title_and_link_test() {
  let out =
    html.page("Cockpit", "sub", "http://nas-1.tail55d152.ts.net:4100/", [
      Text("hi"),
    ])
  should.be_true(string.contains(out, "<title>Cockpit</title>"))
  should.be_true(string.contains(
    out,
    "href=\"http://nas-1.tail55d152.ts.net:4100/\"",
  ))
}

pub fn kpi_label_value_escaped_test() {
  let out =
    html.render(
      KpiRow([
        Kpi("A & B", "<val>", option.None, Good),
      ]),
    )
  should.be_true(string.contains(out, "A &amp; B"))
  should.be_true(string.contains(out, "&lt;val&gt;"))
}

pub fn progress_width_clamped_high_test() {
  let out = html.render(Progress("over", 2.5))
  should.be_true(string.contains(out, "width:100"))
}

pub fn progress_width_clamped_low_test() {
  let out = html.render(Progress("under", -1.0))
  should.be_true(string.contains(out, "width:0"))
}

pub fn table_renders_header_and_rows_test() {
  let out =
    html.render(TableNode(Table(["Col1", "Col2"], [["a", "b"], ["c", "d"]])))
  should.be_true(string.contains(out, "<th>Col1</th>"))
  should.be_true(string.contains(out, "<td>a</td>"))
  should.be_true(string.contains(out, "<td>d</td>"))
}

pub fn section_nests_children_test() {
  let out = html.render(Section("Top", [Text("inner")]))
  should.be_true(string.contains(out, "<h2>Top</h2>"))
  should.be_true(string.contains(out, "<p>inner</p>"))
}

pub fn pre_preserves_text_escaped_test() {
  let out = html.render(Pre("<script>alert(1)</script>"))
  should.be_true(string.contains(out, "&lt;script&gt;alert(1)&lt;/script&gt;"))
  should.be_false(string.contains(out, "<script"))
}

fn tone_from_int(n: Int) -> html.Tone {
  case n % 4 {
    0 -> Good
    1 -> Warn
    2 -> Bad
    _ -> Neutral
  }
}

fn random_node(seed: prng.Seed, depth: Int) -> #(Node, prng.Seed) {
  let #(kind, seed1) = prng.int_between(seed, 0, 5)
  let #(text_a, seed2) = prng.text(seed1, 6)
  case kind, depth {
    0, _ -> #(Text(text_a), seed2)
    1, _ -> #(Pre(text_a), seed2)
    2, _ -> {
      let #(text_b, seed3) = prng.text(seed2, 6)
      #(Link(text_a, text_b), seed3)
    }
    3, _ -> {
      let #(tone_n, seed3) = prng.int_between(seed2, 0, 3)
      #(
        KpiRow([Kpi(text_a, text_a, option.Some(0.5), tone_from_int(tone_n))]),
        seed3,
      )
    }
    4, _ -> #(TableNode(Table([text_a], [[text_a]])), seed2)
    _, n if n > 0 -> {
      let #(child, seed3) = random_node(seed2, n - 1)
      #(Section(text_a, [child]), seed3)
    }
    _, _ -> #(Text(text_a), seed2)
  }
}

pub fn property_no_script_tag_ever_test() {
  let seeds = prng.seeds(200)
  list.each(seeds, fn(seed) {
    let #(node, _) = random_node(seed, 2)
    let out = html.render(node)
    should.be_false(string.contains(out, "<script"))
  })
}

pub fn fuzz_render_never_crashes_test() {
  let seeds = prng.seeds(50)
  list.each(seeds, fn(seed) {
    let #(text, seed1) = prng.text(seed, 20)
    let _ = html.render(Text(text))
    let _ = html.render(Pre(text))
    let #(href, _) = prng.text(seed1, 10)
    let out = html.render(Link(text, href))
    should.be_true(string.length(out) >= 0)
  })
}
