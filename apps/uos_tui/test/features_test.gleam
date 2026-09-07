import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import prng
import uos_tui/features
import uos_tui/fprime
import uos_tui/widget

fn section_named(sections: List(features.Section), title: String) {
  list.find(sections, fn(s) { s.title == title })
}

pub fn sections_count_and_titles_test() {
  let sheet = features.sheet([])
  list.length(sheet.sections) |> should.equal(11)
  let titles = list.map(sheet.sections, fn(s) { s.title })
  titles
  |> should.equal([
    "Widgets", "Keys", "Effects", "Aspects", "F\u{00b4} commands",
    "F\u{00b4} channels", "F\u{00b4} events", "F\u{00b4} parameters",
    "Ontology fidelity", "Drivers", "Test modalities",
  ])
}

pub fn bindings_section_present_when_nonempty_test() {
  let sheet = features.sheet([#("q", "quit"), #("m", "mode")])
  list.length(sheet.sections) |> should.equal(12)
  case section_named(sheet.sections, "Cockpit bindings") {
    Ok(section) -> section.rows |> should.equal([["q", "quit"], ["m", "mode"]])
    Error(_) -> should.fail()
  }
}

pub fn widget_rows_match_catalog_test() {
  let sheet = features.sheet([])
  case section_named(sheet.sections, "Widgets") {
    Ok(section) ->
      list.length(section.rows) |> should.equal(list.length(widget.catalog))
    Error(_) -> should.fail()
  }
}

pub fn aspects_rows_test() {
  let sheet = features.sheet([])
  case section_named(sheet.sections, "Aspects") {
    Ok(section) -> list.length(section.rows) |> should.equal(17)
    Error(_) -> should.fail()
  }
}

pub fn fprime_command_rows_test() {
  let sheet = features.sheet([])
  let commands = fprime.component().commands
  case section_named(sheet.sections, "F\u{00b4} commands") {
    Ok(section) ->
      list.length(section.rows) |> should.equal(list.length(commands))
    Error(_) -> should.fail()
  }
}

pub fn markdown_contains_widgets_and_header_test() {
  let md = features.to_markdown(features.sheet([]))
  should.be_true(string.contains(md, "# uos_tui Feature Sheet"))
  list.each(widget.catalog, fn(name) {
    should.be_true(string.contains(md, name))
  })
}

pub fn json_contains_widgets_test() {
  let text = json.to_string(features.to_json(features.sheet([])))
  should.be_true(string.contains(text, "Widgets"))
}

pub fn total_rows_equals_sum_test() {
  let sheet = features.sheet([])
  let expected =
    list.fold(sheet.sections, 0, fn(acc, s) { acc + list.length(s.rows) })
  features.total_rows(sheet) |> should.equal(expected)
}

pub fn subset_total_rows_property_test() {
  let sheet = features.sheet([])
  let seeds = prng.seeds(6)
  list.each(seeds, fn(seed) {
    let #(n, _) = prng.int_between(seed, 0, list.length(sheet.sections))
    let subset = list.take(sheet.sections, n)
    let subset_sheet = features.FeatureSheet(sheet.generated_by, subset)
    let expected =
      list.fold(subset, 0, fn(acc, s) { acc + list.length(s.rows) })
    features.total_rows(subset_sheet) |> should.equal(expected)
    list.length(subset) |> should.equal(list.length(subset_sheet.sections))
  })
}

pub fn fuzz_markdown_random_rows_never_crashes_test() {
  let seeds = prng.seeds(6)
  list.each(seeds, fn(seed) {
    let #(text1, seed2) = prng.text(seed, 12)
    let #(text2, _) = prng.text(seed2, 5)
    let section = features.Section("Fuzz", [[text1, text2]], ["A", "B"])
    let sheet = features.FeatureSheet("fuzz", [section])
    let md = features.to_markdown(sheet)
    should.be_true(string.contains(md, "Fuzz"))
  })
}
