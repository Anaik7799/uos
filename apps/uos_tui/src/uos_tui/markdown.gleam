//// Minimal markdown renderer to terminal strips (Textual `Markdown` widget reference).
//// Parses a restricted markdown subset into typed blocks and renders them to
//// word-wrapped, styled `Strip` lines bounded to a fixed cell width.
//// STAMP: SC-TUI-W04-001.

import gleam/list
import gleam/string
import uos_tui/render.{type Theme}
import uos_tui/segment.{type Strip}
import uos_tui/style

pub type Inline {
  Plain(String)
  Bold(String)
  Code(String)
  Link(text: String, href: String)
}

pub type Block {
  Heading(level: Int, inlines: List(Inline))
  Paragraph(List(Inline))
  Bullet(List(Inline))
  CodeBlock(lang: String, lines: List(String))
  Rule
  Blank
}

/// Parse markdown text into a list of blocks. Total: never crashes.
pub fn parse(text: String) -> List(Block) {
  let lines = string.split(text, "\n")
  parse_lines(lines, [])
}

fn parse_lines(lines: List(String), acc: List(Block)) -> List(Block) {
  case lines {
    [] -> list.reverse(acc)
    [line, ..rest] -> {
      case classify_fence(line) {
        Ok(lang) -> {
          let #(body, remaining) = take_until_fence(rest, [])
          parse_lines(remaining, [CodeBlock(lang, body), ..acc])
        }
        Error(Nil) ->
          case classify_line(line) {
            LHeading(level, content) ->
              parse_lines(rest, [Heading(level, parse_inlines(content)), ..acc])
            LBullet(content) ->
              parse_lines(rest, [Bullet(parse_inlines(content)), ..acc])
            LRule -> parse_lines(rest, [Rule, ..acc])
            LBlank -> parse_lines(rest, [Blank, ..acc])
            LText(content) -> {
              let #(joined, remaining) = collect_paragraph(rest, [content])
              parse_lines(remaining, [Paragraph(parse_inlines(joined)), ..acc])
            }
          }
      }
    }
  }
}

fn collect_paragraph(
  lines: List(String),
  acc: List(String),
) -> #(String, List(String)) {
  case lines {
    [] -> #(string.join(list.reverse(acc), " "), [])
    [line, ..rest] ->
      case classify_fence(line) {
        Ok(_) -> #(string.join(list.reverse(acc), " "), lines)
        Error(Nil) ->
          case classify_line(line) {
            LText(content) -> collect_paragraph(rest, [content, ..acc])
            _ -> #(string.join(list.reverse(acc), " "), lines)
          }
      }
  }
}

fn take_until_fence(
  lines: List(String),
  acc: List(String),
) -> #(List(String), List(String)) {
  case lines {
    [] -> #(list.reverse(acc), [])
    [line, ..rest] ->
      case classify_fence(line) {
        Ok(_) -> #(list.reverse(acc), rest)
        Error(Nil) -> take_until_fence(rest, [line, ..acc])
      }
  }
}

fn classify_fence(line: String) -> Result(String, Nil) {
  case string.starts_with(line, "```") {
    True -> Ok(string.trim(string.drop_start(line, 3)))
    False -> Error(Nil)
  }
}

type Line {
  LHeading(level: Int, content: String)
  LBullet(content: String)
  LRule
  LBlank
  LText(content: String)
}

fn classify_line(line: String) -> Line {
  let trimmed = string.trim(line)
  case trimmed {
    "" -> LBlank
    "---" -> LRule
    _ ->
      case heading_level(trimmed) {
        Ok(#(level, content)) -> LHeading(level, content)
        Error(Nil) ->
          case
            string.starts_with(trimmed, "- ")
            || string.starts_with(trimmed, "* ")
          {
            True -> LBullet(string.drop_start(trimmed, 2))
            False -> LText(trimmed)
          }
      }
  }
}

fn heading_level(trimmed: String) -> Result(#(Int, String), Nil) {
  count_hashes(trimmed, 0)
}

fn count_hashes(text: String, n: Int) -> Result(#(Int, String), Nil) {
  case n > 6 {
    True -> Error(Nil)
    False ->
      case string.pop_grapheme(text) {
        Ok(#("#", rest)) -> count_hashes(rest, n + 1)
        Ok(#(" ", rest)) if n > 0 -> Ok(#(n, string.trim(rest)))
        _ ->
          case n {
            0 -> Error(Nil)
            _ -> Error(Nil)
          }
      }
  }
}

/// Parse inline markdown (bold, code, link) within one line of text.
/// Unterminated markers degrade to Plain text. Total.
pub fn parse_inlines(text: String) -> List(Inline) {
  parse_inlines_loop(text, "", []) |> list.reverse
}

fn parse_inlines_loop(
  text: String,
  plain_acc: String,
  acc: List(Inline),
) -> List(Inline) {
  case text {
    "" -> finish_plain(plain_acc, acc)
    _ ->
      case string.starts_with(text, "**") {
        True ->
          case find_closing(string.drop_start(text, 2), "**") {
            Ok(#(inner, rest)) ->
              parse_inlines_loop(rest, "", [
                Bold(inner),
                ..finish_plain(plain_acc, acc)
              ])
            Error(Nil) -> consume_one(text, plain_acc, acc)
          }
        False ->
          case string.starts_with(text, "`") {
            True ->
              case find_closing(string.drop_start(text, 1), "`") {
                Ok(#(inner, rest)) ->
                  parse_inlines_loop(rest, "", [
                    Code(inner),
                    ..finish_plain(plain_acc, acc)
                  ])
                Error(Nil) -> consume_one(text, plain_acc, acc)
              }
            False ->
              case string.starts_with(text, "[") {
                True ->
                  case parse_link(text) {
                    Ok(#(link, rest)) ->
                      parse_inlines_loop(rest, "", [
                        link,
                        ..finish_plain(plain_acc, acc)
                      ])
                    Error(Nil) -> consume_one(text, plain_acc, acc)
                  }
                False -> consume_one(text, plain_acc, acc)
              }
          }
      }
  }
}

fn consume_one(
  text: String,
  plain_acc: String,
  acc: List(Inline),
) -> List(Inline) {
  case string.pop_grapheme(text) {
    Ok(#(g, rest)) -> parse_inlines_loop(rest, plain_acc <> g, acc)
    Error(Nil) -> finish_plain(plain_acc, acc)
  }
}

fn finish_plain(plain_acc: String, acc: List(Inline)) -> List(Inline) {
  case plain_acc {
    "" -> acc
    _ -> [Plain(plain_acc), ..acc]
  }
}

fn find_closing(
  text: String,
  marker: String,
) -> Result(#(String, String), Nil) {
  find_closing_loop(text, marker, "")
}

fn find_closing_loop(
  text: String,
  marker: String,
  inner_acc: String,
) -> Result(#(String, String), Nil) {
  case string.starts_with(text, marker) {
    True -> Ok(#(inner_acc, string.drop_start(text, string.length(marker))))
    False ->
      case string.pop_grapheme(text) {
        Ok(#(g, rest)) -> find_closing_loop(rest, marker, inner_acc <> g)
        Error(Nil) -> Error(Nil)
      }
  }
}

fn parse_link(text: String) -> Result(#(Inline, String), Nil) {
  case find_closing(string.drop_start(text, 1), "]") {
    Ok(#(label, rest)) ->
      case string.starts_with(rest, "(") {
        True ->
          case find_closing(string.drop_start(rest, 1), ")") {
            Ok(#(href, after)) -> Ok(#(Link(label, href), after))
            Error(Nil) -> Error(Nil)
          }
        False -> Error(Nil)
      }
    Error(Nil) -> Error(Nil)
  }
}

/// Render blocks to terminal strips, word-wrapped to `width`. Total.
pub fn render_lines(text: String, width: Int, theme: Theme) -> List(Strip) {
  case width <= 0 {
    True -> []
    False ->
      parse(text)
      |> list.flat_map(render_block(_, width, theme))
  }
}

fn render_block(block: Block, width: Int, theme: Theme) -> List(Strip) {
  case block {
    Blank -> [segment.empty]
    Rule -> [segment.text(string.repeat("─", width), theme.border)]
    Heading(level, inlines) -> {
      let base_style = case level {
        1 -> style.underline(theme.accent)
        _ -> theme.accent
      }
      let strip = inline_strip(inlines, base_style, theme)
      wrap_strip(strip, width)
    }
    Paragraph(inlines) -> {
      let strip = inline_strip(inlines, style.none, theme)
      wrap_strip(strip, width)
    }
    Bullet(inlines) -> {
      let prefix = segment.text("• ", style.none)
      let body = inline_strip(inlines, style.none, theme)
      wrap_prefixed(prefix, body, width)
    }
    CodeBlock(_lang, lines) ->
      list.map(lines, fn(l) {
        segment.text("  " <> l, theme.muted) |> segment.crop(width)
      })
  }
}

fn inline_strip(
  inlines: List(Inline),
  base: style.Style,
  theme: Theme,
) -> Strip {
  inlines
  |> list.map(fn(inline) { inline_to_strip(inline, base, theme) })
  |> segment.concat
}

fn inline_to_strip(inline: Inline, base: style.Style, theme: Theme) -> Strip {
  case inline {
    Plain(t) -> segment.text(t, base)
    Bold(t) -> segment.text(t, style.combine(base, style.bold(style.none)))
    Code(t) -> segment.text(t, style.combine(base, theme.muted))
    Link(t, href) ->
      segment.text(t <> " (" <> href <> ")", style.combine(base, theme.muted))
  }
}

/// Word-wrap a strip to width, breaking on spaces and hard-splitting words
/// longer than width. Every returned strip has cell_length <= width.
fn wrap_strip(strip: Strip, width: Int) -> List(Strip) {
  let plain = segment.plain_text(strip)
  let words = string.split(plain, " ") |> list.filter(fn(w) { w != "" })
  case words {
    [] -> [segment.empty]
    _ -> {
      let strip_style = style_of(strip)
      wrap_words(words, width, strip_style, "", [])
    }
  }
}

fn wrap_prefixed(prefix: Strip, body: Strip, width: Int) -> List(Strip) {
  let prefix_width = prefix.cell_length
  let inner_width = case width - prefix_width {
    w if w > 0 -> w
    _ -> width
  }
  case wrap_strip(body, inner_width) {
    [] -> [prefix]
    [first, ..rest] -> {
      let first_line = segment.append(prefix, first) |> segment.crop(width)
      let indent = segment.text(string.repeat(" ", prefix_width), style.none)
      let rest_lines =
        list.map(rest, fn(l) {
          segment.append(indent, l) |> segment.crop(width)
        })
      [first_line, ..rest_lines]
    }
  }
}

fn style_of(strip: Strip) -> style.Style {
  case strip.segments {
    [segment.Segment(_, s), ..] -> s
    [] -> style.none
  }
}

fn wrap_words(
  words: List(String),
  width: Int,
  st: style.Style,
  current: String,
  lines: List(Strip),
) -> List(Strip) {
  case words {
    [] ->
      case current {
        "" -> list.reverse(lines)
        _ -> list.reverse([segment.text(current, st), ..lines])
      }
    [word, ..rest] -> {
      let candidate = case current {
        "" -> word
        _ -> current <> " " <> word
      }
      case segment.cell_width(candidate) <= width {
        True -> wrap_words(rest, width, st, candidate, lines)
        False ->
          case current {
            "" -> {
              let #(head_lines, remainder) = hard_split(word, width, st)
              wrap_words(
                rest,
                width,
                st,
                remainder,
                list.append(list.reverse(head_lines), lines),
              )
            }
            _ ->
              wrap_words([word, ..rest], width, st, "", [
                segment.text(current, st),
                ..lines
              ])
          }
      }
    }
  }
}

fn hard_split(
  word: String,
  width: Int,
  st: style.Style,
) -> #(List(Strip), String) {
  case segment.cell_width(word) <= width {
    True -> #([], word)
    False -> {
      let cropped = segment.text(word, st) |> segment.crop(width)
      let taken = segment.plain_text(cropped)
      let remaining = string.drop_start(word, string.length(taken))
      case remaining == word {
        True -> #([cropped], "")
        False -> {
          let #(more_lines, tail) = hard_split(remaining, width, st)
          #([cropped, ..more_lines], tail)
        }
      }
    }
  }
}

/// Extract plain text content of all blocks, joined by spaces.
pub fn plain_text(blocks: List(Block)) -> String {
  blocks
  |> list.map(block_plain_text)
  |> string.join(" ")
}

fn block_plain_text(block: Block) -> String {
  case block {
    Heading(_, inlines) -> inlines_plain_text(inlines)
    Paragraph(inlines) -> inlines_plain_text(inlines)
    Bullet(inlines) -> inlines_plain_text(inlines)
    CodeBlock(_, lines) -> string.join(lines, " ")
    Rule -> ""
    Blank -> ""
  }
}

fn inlines_plain_text(inlines: List(Inline)) -> String {
  inlines
  |> list.map(fn(inline) {
    case inline {
      Plain(t) -> t
      Bold(t) -> t
      Code(t) -> t
      Link(t, href) -> t <> " (" <> href <> ")"
    }
  })
  |> string.join("")
}
