//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/lustre/markdown</module>
////     <fsharp-lineage>Cepaf.Cockpit.ZettelView.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-GLM-UI-001, SC-GLM-UI-002, SC-SMRITI-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="surjective" loss="wpf-rendering">
////       F# WPF FlowDocument rendering mapped to Lustre HTML elements.
////       Mitigation: Server-side HTML rendering replaces client-side WPF.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Lustre markdown renderer for zettel content display.
//// Converts a subset of CommonMark to Lustre HTML elements.
//// Server-side only — no client JavaScript.
////
//// STAMP: SC-GLM-UI-001 (Triple-Interface), SC-SMRITI-001

import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

// =============================================================================
// Types
// =============================================================================

pub type MarkdownBlock {
  Heading(level: Int, text: String)
  Paragraph(text: String)
  CodeBlock(language: String, code: String)
  UnorderedList(items: List(String))
  OrderedList(items: List(String))
  Blockquote(text: String)
  HorizontalRule
  EmptyLine
}

pub type InlineStyle {
  Bold(text: String)
  Italic(text: String)
  Code(text: String)
  Link(text: String, url: String)
  Plain(text: String)
}

// =============================================================================
// Public API
// =============================================================================

/// Render markdown text to a Lustre HTML element.
pub fn render(content: String) -> Element(msg) {
  let blocks = parse_blocks(content)
  html.div(
    [attribute.class("markdown-content")],
    list.map(blocks, render_block),
  )
}

/// Render markdown with a wrapper class for styling.
pub fn render_with_class(content: String, class: String) -> Element(msg) {
  let blocks = parse_blocks(content)
  html.div([attribute.class(class)], list.map(blocks, render_block))
}

/// Render a single zettel entry with title and content.
pub fn render_zettel(
  title: String,
  content: String,
  tags: List(String),
) -> Element(msg) {
  html.article([attribute.class("zettel")], [
    html.h2([attribute.class("zettel-title")], [element.text(title)]),
    case tags {
      [] -> element.none()
      _ ->
        html.div(
          [attribute.class("zettel-tags")],
          list.map(tags, fn(tag) {
            html.span([attribute.class("tag")], [element.text(tag)])
          }),
        )
    },
    render(content),
  ])
}

// =============================================================================
// Block Parser
// =============================================================================

fn parse_blocks(content: String) -> List(MarkdownBlock) {
  let lines = string.split(content, "\n")
  parse_lines(lines, [], False, "", "")
}

fn parse_lines(
  lines: List(String),
  acc: List(MarkdownBlock),
  in_code: Bool,
  code_lang: String,
  code_buf: String,
) -> List(MarkdownBlock) {
  case lines {
    [] ->
      case in_code {
        True -> list.reverse([CodeBlock(code_lang, code_buf), ..acc])
        False -> list.reverse(acc)
      }
    [line, ..rest] -> {
      case in_code {
        True ->
          case string.starts_with(line, "```") {
            True ->
              parse_lines(
                rest,
                [CodeBlock(code_lang, code_buf), ..acc],
                False,
                "",
                "",
              )
            False -> {
              let new_buf = case code_buf {
                "" -> line
                _ -> code_buf <> "\n" <> line
              }
              parse_lines(rest, acc, True, code_lang, new_buf)
            }
          }
        False -> {
          case parse_line(line) {
            CodeBlock(lang, _) -> parse_lines(rest, acc, True, lang, "")
            block -> parse_lines(rest, [block, ..acc], False, "", "")
          }
        }
      }
    }
  }
}

fn parse_line(line: String) -> MarkdownBlock {
  let trimmed = string.trim(line)
  case trimmed {
    "" -> EmptyLine
    "---" | "***" | "___" -> HorizontalRule
    _ ->
      case string.starts_with(trimmed, "```") {
        True -> {
          let lang = string.drop_start(trimmed, 3) |> string.trim
          CodeBlock(lang, "")
        }
        False ->
          case string.starts_with(trimmed, "> ") {
            True -> Blockquote(string.drop_start(trimmed, 2))
            False ->
              case parse_heading(trimmed) {
                Ok(heading) -> heading
                Error(_) ->
                  case
                    string.starts_with(trimmed, "- ")
                    || string.starts_with(trimmed, "* ")
                  {
                    True -> UnorderedList([string.drop_start(trimmed, 2)])
                    False -> Paragraph(trimmed)
                  }
              }
          }
      }
  }
}

fn parse_heading(line: String) -> Result(MarkdownBlock, Nil) {
  case line {
    "# " <> rest -> Ok(Heading(1, rest))
    "## " <> rest -> Ok(Heading(2, rest))
    "### " <> rest -> Ok(Heading(3, rest))
    "#### " <> rest -> Ok(Heading(4, rest))
    "##### " <> rest -> Ok(Heading(5, rest))
    "###### " <> rest -> Ok(Heading(6, rest))
    _ -> Error(Nil)
  }
}

// =============================================================================
// Block Renderer
// =============================================================================

fn render_block(block: MarkdownBlock) -> Element(msg) {
  case block {
    Heading(1, text) -> html.h1([attribute.class("md-h1")], render_inline(text))
    Heading(2, text) -> html.h2([attribute.class("md-h2")], render_inline(text))
    Heading(3, text) -> html.h3([attribute.class("md-h3")], render_inline(text))
    Heading(level, text) -> {
      let tag = case level {
        4 -> html.h4
        5 -> html.h5
        _ -> html.h6
      }
      tag(
        [attribute.class("md-h" <> string.inspect(level))],
        render_inline(text),
      )
    }
    Paragraph(text) -> html.p([attribute.class("md-p")], render_inline(text))
    CodeBlock(lang, code) ->
      html.pre([attribute.class("md-code")], [
        html.code([attribute.attribute("data-language", lang)], [
          element.text(code),
        ]),
      ])
    UnorderedList(items) ->
      html.ul(
        [attribute.class("md-ul")],
        list.map(items, fn(item) { html.li([], render_inline(item)) }),
      )
    OrderedList(items) ->
      html.ol(
        [attribute.class("md-ol")],
        list.map(items, fn(item) { html.li([], render_inline(item)) }),
      )
    Blockquote(text) ->
      html.blockquote([attribute.class("md-quote")], render_inline(text))
    HorizontalRule -> html.hr([attribute.class("md-hr")])
    EmptyLine -> element.none()
  }
}

// =============================================================================
// Inline Renderer
// =============================================================================

fn render_inline(text: String) -> List(Element(msg)) {
  parse_inline_segments(text)
  |> list.map(render_inline_segment)
}

fn render_inline_segment(segment: InlineStyle) -> Element(msg) {
  case segment {
    Bold(t) -> html.strong([], [element.text(t)])
    Italic(t) -> html.em([], [element.text(t)])
    Code(t) -> html.code([attribute.class("md-inline-code")], [element.text(t)])
    Link(t, url) -> html.a([attribute.href(url)], [element.text(t)])
    Plain(t) -> element.text(t)
  }
}

fn parse_inline_segments(text: String) -> List(InlineStyle) {
  parse_inline_acc(text, [])
  |> list.reverse
}

fn parse_inline_acc(text: String, acc: List(InlineStyle)) -> List(InlineStyle) {
  case text {
    "" -> acc
    "**" <> rest ->
      case string.split_once(rest, "**") {
        Ok(#(bold_text, after)) ->
          parse_inline_acc(after, [Bold(bold_text), ..acc])
        Error(_) -> [Plain("**" <> rest), ..acc]
      }
    "*" <> rest ->
      case string.split_once(rest, "*") {
        Ok(#(italic_text, after)) ->
          parse_inline_acc(after, [Italic(italic_text), ..acc])
        Error(_) -> [Plain("*" <> rest), ..acc]
      }
    "`" <> rest ->
      case string.split_once(rest, "`") {
        Ok(#(code_text, after)) ->
          parse_inline_acc(after, [Code(code_text), ..acc])
        Error(_) -> [Plain("`" <> rest), ..acc]
      }
    "[" <> rest ->
      case string.split_once(rest, "](") {
        Ok(#(link_text, after_bracket)) ->
          case string.split_once(after_bracket, ")") {
            Ok(#(url, after_paren)) ->
              parse_inline_acc(after_paren, [Link(link_text, url), ..acc])
            Error(_) -> [Plain("[" <> rest), ..acc]
          }
        Error(_) -> {
          let #(before, remaining) = take_until_special(text)
          parse_inline_acc(remaining, [Plain(before), ..acc])
        }
      }
    _ -> {
      let #(before, remaining) = take_until_special(text)
      parse_inline_acc(remaining, [Plain(before), ..acc])
    }
  }
}

fn take_until_special(text: String) -> #(String, String) {
  take_until_special_acc(text, "")
}

fn take_until_special_acc(text: String, acc: String) -> #(String, String) {
  case text {
    "" -> #(acc, "")
    "**" <> _ -> #(acc, text)
    "*" <> _ -> #(acc, text)
    "`" <> _ -> #(acc, text)
    "[" <> _ -> #(acc, text)
    _ -> {
      case string.pop_grapheme(text) {
        Ok(#(char, rest)) -> take_until_special_acc(rest, acc <> char)
        Error(_) -> #(acc, "")
      }
    }
  }
}
