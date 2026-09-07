//// Tests for uos_tui/markdown: block parsing, inline parsing, wrapping,
//// styling, and property/fuzz coverage using test/prng.gleam.
//// STAMP: SC-TUI-W04-001.

import gleam/list
import gleam/string
import gleeunit/should
import prng
import uos_tui/markdown.{
  Blank, Bold, Bullet, Code, CodeBlock, Heading, Link, Paragraph, Plain, Rule,
}
import uos_tui/render
import uos_tui/segment
import uos_tui/style

pub fn heading_block_test() {
  markdown.parse("# Title")
  |> should.equal([Heading(1, [Plain("Title")])])
}

pub fn heading_level_six_test() {
  markdown.parse("###### Deep")
  |> should.equal([Heading(6, [Plain("Deep")])])
}

pub fn bullet_block_test() {
  markdown.parse("- item one")
  |> should.equal([Bullet([Plain("item one")])])
}

pub fn bullet_star_block_test() {
  markdown.parse("* item two")
  |> should.equal([Bullet([Plain("item two")])])
}

pub fn fenced_code_block_test() {
  markdown.parse("```gleam\nlet x = 1\n```")
  |> should.equal([CodeBlock("gleam", ["let x = 1"])])
}

pub fn rule_block_test() {
  markdown.parse("---")
  |> should.equal([Rule])
}

pub fn blank_block_test() {
  markdown.parse("")
  |> should.equal([Blank])
}

pub fn paragraph_join_test() {
  markdown.parse("line one\nline two")
  |> should.equal([Paragraph([Plain("line one line two")])])
}

pub fn inline_bold_test() {
  markdown.parse_inlines("**bold**")
  |> should.equal([Bold("bold")])
}

pub fn inline_unterminated_bold_test() {
  markdown.parse_inlines("**oops")
  |> should.equal([Plain("**oops")])
}

pub fn inline_code_test() {
  markdown.parse_inlines("`code`")
  |> should.equal([Code("code")])
}

pub fn inline_link_test() {
  markdown.parse_inlines("[text](http://example.com)")
  |> should.equal([Link("text", "http://example.com")])
}

pub fn inline_nested_in_paragraph_test() {
  markdown.parse("plain `code` end")
  |> should.equal([
    Paragraph([Plain("plain "), Code("code"), Plain(" end")]),
  ])
}

pub fn rule_length_equals_width_test() {
  let strips = markdown.render_lines("---", 20, render.dark)
  case strips {
    [strip] -> should.equal(strip.cell_length, 20)
    _ -> should.fail()
  }
}

pub fn zero_width_returns_empty_test() {
  markdown.render_lines("# Title", 0, render.dark)
  |> should.equal([])
}

pub fn code_block_indentation_test() {
  let strips = markdown.render_lines("```\nfoo\n```", 20, render.dark)
  case strips {
    [strip] -> segment.plain_text(strip) |> should.equal("  foo")
    _ -> should.fail()
  }
}

pub fn heading_style_bold_accent_test() {
  let strips = markdown.render_lines("## Two", 20, render.dark)
  case strips {
    [strip] ->
      case strip.segments {
        [segment.Segment(_, st), ..] -> style.is_none(st) |> should.equal(False)
        [] -> should.fail()
      }
    _ -> should.fail()
  }
}

pub fn wrap_at_width_test() {
  let text =
    "this is a fairly long paragraph that should wrap across several lines when rendered"
  let strips = markdown.render_lines(text, 12, render.dark)
  list.all(strips, fn(s) { s.cell_length <= 12 })
  |> should.equal(True)
}

pub fn plain_text_extracts_test() {
  markdown.parse("# Hi\n\nsome text")
  |> markdown.plain_text
  |> string.contains("Hi")
  |> should.equal(True)
}

pub fn property_wrap_never_exceeds_width_test() {
  let seeds = prng.seeds(20)
  list.each(seeds, fn(seed) {
    let #(width, seed2) = prng.int_between(seed, 1, 80)
    let #(text, _seed3) = prng.text(seed2, 60)
    let strips = markdown.render_lines(text, width, render.dark)
    let ok = list.all(strips, fn(s) { s.cell_length <= width })
    ok |> should.equal(True)
  })
}

pub fn fuzz_parse_and_render_never_crash_test() {
  let seeds = prng.seeds(300)
  list.each(seeds, fn(seed) {
    let #(len, seed2) = prng.int_between(seed, 0, 200)
    let #(text, seed3) = prng.text(seed2, len)
    let #(width, _seed4) = prng.int_between(seed3, 1, 80)
    let blocks = markdown.parse(text)
    let _strips = markdown.render_lines(text, width, render.dark)
    let _pt = markdown.plain_text(blocks)
    Nil
  })
  Nil
  |> should.equal(Nil)
}

const safe_alphabet = [
  "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "0", "1", "2", "3", "4", "5",
]

fn random_word(seed: prng.Seed, len: Int) -> #(String, prng.Seed) {
  let #(idx, seed2) = prng.ints(seed, len, 0, list.length(safe_alphabet) - 1)
  let word =
    idx
    |> list.filter_map(fn(i) { safe_alphabet |> list.drop(i) |> list.first })
    |> string.concat
  #(word, seed2)
}

fn random_words(
  seed: prng.Seed,
  count: Int,
  acc: List(String),
) -> #(List(String), prng.Seed) {
  case count {
    0 -> #(list.reverse(acc), seed)
    _ -> {
      let #(w, seed2) = random_word(seed, 4)
      random_words(seed2, count - 1, [w, ..acc])
    }
  }
}

pub fn plain_text_contains_words_test() {
  let seeds = prng.seeds(15)
  list.each(seeds, fn(seed) {
    let #(words, _seed2) = random_words(seed, 6, [])
    let text = string.join(words, " ")
    let out = markdown.plain_text(markdown.parse(text))
    list.each(words, fn(w) {
      case w {
        "" -> Nil
        _ -> string.contains(out, w) |> should.equal(True)
      }
    })
  })
}

pub fn bullet_wraps_with_prefix_test() {
  let strips =
    markdown.render_lines(
      "- a somewhat long bullet item that must wrap onto more than one line",
      10,
      render.dark,
    )
  list.all(strips, fn(s) { s.cell_length <= 10 })
  |> should.equal(True)
}
