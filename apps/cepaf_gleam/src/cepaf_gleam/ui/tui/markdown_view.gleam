// STAMP: SC-GLM-UI-001, SC-GLM-UI-009, SC-SMRITI-001
// TUI ANSI renderer for markdown/zettel content.
// Triple-Interface: Lustre (markdown.gleam) + Wisp (markdown_api.gleam) + TUI (this).

import gleam/list
import gleam/string

/// Render markdown content as ANSI-formatted terminal output.
pub fn render(content: String) -> String {
  let lines = string.split(content, "\n")
  list.map(lines, render_line)
  |> string.join("\n")
}

/// Render a zettel entry with title, tags, and content for the terminal.
pub fn render_zettel(
  title: String,
  content: String,
  tags: List(String),
) -> String {
  let header = "\u{001b}[1;36m" <> title <> "\u{001b}[0m"
  let tag_line = case tags {
    [] -> ""
    _ -> "\u{001b}[33m[" <> string.join(tags, ", ") <> "]\u{001b}[0m\n"
  }
  header <> "\n" <> tag_line <> render(content)
}

fn render_line(line: String) -> String {
  let trimmed = string.trim(line)
  case trimmed {
    "" -> ""
    "---" | "***" | "___" ->
      "\u{001b}[90m" <> string.repeat("─", 60) <> "\u{001b}[0m"
    "# " <> rest -> "\u{001b}[1;37m█ " <> rest <> "\u{001b}[0m"
    "## " <> rest -> "\u{001b}[1;36m▌ " <> rest <> "\u{001b}[0m"
    "### " <> rest -> "\u{001b}[1;33m▎ " <> rest <> "\u{001b}[0m"
    "> " <> rest -> "\u{001b}[90m│ \u{001b}[3m" <> rest <> "\u{001b}[0m"
    "- " <> rest -> "  \u{001b}[36m•\u{001b}[0m " <> render_inline_ansi(rest)
    "* " <> rest -> "  \u{001b}[36m•\u{001b}[0m " <> render_inline_ansi(rest)
    _ -> "  " <> render_inline_ansi(trimmed)
  }
}

fn render_inline_ansi(text: String) -> String {
  text
  |> apply_bold
  |> apply_italic
  |> apply_code
}

fn apply_bold(text: String) -> String {
  case string.split_once(text, "**") {
    Ok(#(before, rest)) ->
      case string.split_once(rest, "**") {
        Ok(#(bold, after)) ->
          before <> "\u{001b}[1m" <> bold <> "\u{001b}[22m" <> apply_bold(after)
        Error(_) -> text
      }
    Error(_) -> text
  }
}

fn apply_italic(text: String) -> String {
  case string.split_once(text, "*") {
    Ok(#(before, rest)) ->
      case string.split_once(rest, "*") {
        Ok(#(italic, after)) ->
          before
          <> "\u{001b}[3m"
          <> italic
          <> "\u{001b}[23m"
          <> apply_italic(after)
        Error(_) -> text
      }
    Error(_) -> text
  }
}

fn apply_code(text: String) -> String {
  case string.split_once(text, "`") {
    Ok(#(before, rest)) ->
      case string.split_once(rest, "`") {
        Ok(#(code, after)) ->
          before <> "\u{001b}[32m" <> code <> "\u{001b}[0m" <> apply_code(after)
        Error(_) -> text
      }
    Error(_) -> text
  }
}
