//// Compositor: widget tree -> Frame (Textual `Compositor` + `render_line` reference).
//// `compose` is deterministic and total: any widget at any size yields a well-formed frame.
//// STAMP: SC-TUI-RENDER-001.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import gleam/string
import uos_tui/event
import uos_tui/frame.{type Frame}
import uos_tui/geometry.{type Region, type Size, Region}
import uos_tui/layout
import uos_tui/segment.{type Strip}
import uos_tui/style.{type Style, Style}
import uos_tui/widget.{type Widget}

pub type Theme {
  Theme(
    base: Style,
    accent: Style,
    muted: Style,
    focus: Style,
    ok: Style,
    warn: Style,
    danger: Style,
    border: Style,
  )
}

pub const dark = Theme(
  base: Style(style.Default, style.Default, False, False, False, False, False),
  accent: Style(style.Cyan, style.Default, True, False, False, False, False),
  muted: Style(
    style.BrightBlack,
    style.Default,
    False,
    False,
    False,
    False,
    False,
  ),
  focus: Style(style.Black, style.Cyan, True, False, False, False, False),
  ok: Style(style.Green, style.Default, False, False, False, False, False),
  warn: Style(style.Yellow, style.Default, False, False, False, False, False),
  danger: Style(style.Red, style.Default, True, False, False, False, False),
  border: Style(
    style.BrightBlack,
    style.Default,
    False,
    False,
    False,
    False,
    False,
  ),
)

/// Compose a widget tree into a frame of the given size.
pub fn compose(
  widget: Widget(msg),
  size: Size,
  focus: Option(String),
  theme: Theme,
) -> Frame {
  let base = frame.blank(size, theme.base)
  let placements = arrange(widget, geometry.size_to_region(size), focus, theme)
  list.fold(placements, base, fn(f, p) { frame.blit(f, p.0, p.1, theme.base) })
  |> frame.normalise(theme.base)
}

/// Flatten a widget tree into (region, strips) placements.
pub fn arrange(
  widget: Widget(msg),
  region: Region,
  focus: Option(String),
  theme: Theme,
) -> List(#(Region, List(Strip))) {
  case geometry.is_empty(region) {
    True -> []
    False ->
      case widget {
        widget.Container(_, direction, kids, border, title) -> {
          let inner = case border {
            True -> geometry.shrink(region, 1)
            False -> region
          }
          let scalars = list.map(kids, fn(k) { k.0 })
          let autos = list.map(kids, fn(k) { widget.min_height(k.1) })
          let regions = layout.arrange(direction, inner, scalars, autos)
          let child_placements =
            list.zip(kids, regions)
            |> list.flat_map(fn(pair) {
              arrange(pair.0.1, pair.1, focus, theme)
            })
          case border {
            True -> [
              #(region, draw_border(region, title, theme.border, theme.accent)),
              ..child_placements
            ]
            False -> child_placements
          }
        }
        widget.Grid(_, columns, rows, cells) -> {
          let regions = layout.grid(region, columns, rows) |> list.flatten
          list.zip(cells, regions)
          |> list.flat_map(fn(pair) { arrange(pair.0, pair.1, focus, theme) })
        }
        leaf -> [#(region, render_leaf(leaf, region, focus, theme))]
      }
  }
}

fn focused(widget: Widget(msg), focus: Option(String)) -> Bool {
  focus == Some(widget.id_of(widget))
}

fn draw_border(
  region: Region,
  title: String,
  border: Style,
  accent: Style,
) -> List(Strip) {
  let w = region.width
  let h = region.height
  case w < 2 || h < 2 {
    True -> []
    False -> {
      let inner_w = w - 2
      let title_strip = case title {
        "" -> segment.text(string.repeat("─", inner_w), border)
        t -> {
          let label =
            segment.text(" " <> t <> " ", accent) |> segment.crop(inner_w)
          let rest = int.max(inner_w - label.cell_length, 0)
          segment.append(label, segment.text(string.repeat("─", rest), border))
        }
      }
      let top =
        segment.concat([
          segment.text("┌", border),
          title_strip,
          segment.text("┐", border),
        ])
      let bottom =
        segment.text("└" <> string.repeat("─", inner_w) <> "┘", border)
      let side =
        segment.concat([
          segment.text("│", border),
          segment.extend(segment.empty, inner_w, style.none),
          segment.text("│", border),
        ])
      list.flatten([[top], list.repeat(side, h - 2), [bottom]])
    }
  }
}

fn render_leaf(
  widget: Widget(msg),
  region: Region,
  focus: Option(String),
  theme: Theme,
) -> List(Strip) {
  let w = region.width
  let h = region.height
  let is_focus = focused(widget, focus)
  case widget {
    widget.Static(_, text, st) ->
      wrap_lines(text, w, style.combine(theme.base, st))
    widget.Header(_, title, subtitle, st) -> {
      let left = segment.text(" " <> title, style.combine(theme.accent, st))
      let right = segment.text(subtitle <> " ", theme.muted)
      let gap = int.max(w - left.cell_length - right.cell_length, 1)
      [
        segment.concat([
          left,
          segment.extend(segment.empty, gap, style.none),
          right,
        ]),
      ]
    }
    widget.Footer(_, bindings) -> {
      let parts =
        list.map(bindings, fn(b) {
          segment.concat([
            segment.text(" " <> event.key_label(b.key) <> " ", theme.focus),
            segment.text(" " <> b.description <> " ", theme.muted),
          ])
        })
      [segment.concat(parts)]
    }
    widget.Button(_, label, _) -> {
      let st = case is_focus {
        True -> theme.focus
        False -> theme.accent
      }
      [segment.text("[ " <> label <> " ]", st)]
    }
    widget.Input(_, value, cursor, placeholder, _, _) -> {
      let shown = case value {
        "" -> segment.text(placeholder, theme.muted)
        v -> {
          let cursor = int.clamp(cursor, 0, string.length(v))
          let before = string.slice(v, 0, cursor)
          let at = string.slice(v, cursor, 1)
          let after = string.drop_start(v, cursor + 1)
          case is_focus {
            True ->
              segment.concat([
                segment.text(before, theme.base),
                segment.text(
                  case at {
                    "" -> " "
                    c -> c
                  },
                  style.reverse(theme.base),
                ),
                segment.text(after, theme.base),
              ])
            False -> segment.text(v, theme.base)
          }
        }
      }
      let marker = case is_focus {
        True -> segment.text("> ", theme.accent)
        False -> segment.text("  ", theme.muted)
      }
      [segment.append(marker, shown)]
    }
    widget.DataTable(_, columns, rows, cursor, _, _) -> {
      let widths = layout.resolve(list.map(columns, fn(c) { c.width }), w, [])
      let header =
        cells_row(list.map(columns, fn(c) { c.label }), widths, theme.accent)
      let rule = segment.text(string.repeat("─", w), theme.border)
      let body =
        list.index_map(rows, fn(row, i) {
          let st = case i == cursor && is_focus {
            True -> theme.focus
            False -> theme.base
          }
          cells_row(row, widths, st)
        })
      scroll_to(list.flatten([[header, rule], body]), cursor + 2, h)
    }
    widget.Tree(_, root, cursor, _) -> {
      let rows = widget.tree_rows(root)
      list.index_map(rows, fn(pair, i) {
        let #(depth, node) = pair
        let glyph = case node.children {
          [] -> "· "
          _ ->
            case node.expanded {
              True -> "▾ "
              False -> "▸ "
            }
        }
        let st = case i == cursor && is_focus {
          True -> theme.focus
          False -> theme.base
        }
        segment.text(string.repeat("  ", depth) <> glyph <> node.label, st)
      })
      |> scroll_to(cursor, h)
    }
    widget.ListView(_, items, cursor, _, _) -> {
      list.index_map(items, fn(item, i) {
        case i == cursor && is_focus {
          True -> segment.text("› " <> item, theme.focus)
          False -> segment.text("  " <> item, theme.base)
        }
      })
      |> scroll_to(cursor, h)
    }
    widget.ProgressBar(_, ratio, label) -> {
      let ratio = float.clamp(ratio, 0.0, 1.0)
      let label_w = segment.cell_width(label)
      let bar_w = int.max(w - label_w - 6, 1)
      let filled = float.round(ratio *. int.to_float(bar_w))
      let pct = float.round(ratio *. 100.0)
      [
        segment.concat([
          segment.text(label, theme.base),
          segment.text(string.repeat("█", filled), theme.ok),
          segment.text(string.repeat("░", bar_w - filled), theme.muted),
          segment.text(
            " " <> string.pad_start(int.to_string(pct), 3, " ") <> "%",
            theme.muted,
          ),
        ]),
      ]
    }
    widget.Sparkline(_, data, st) -> [
      segment.text(sparkline(data, w), style.combine(theme.ok, st)),
    ]
    widget.Tabs(_, labels, active, _) -> {
      let parts =
        list.index_map(labels, fn(label, i) {
          case i == active {
            True ->
              segment.text(" " <> label <> " ", case is_focus {
                True -> theme.focus
                False -> theme.accent
              })
            False -> segment.text(" " <> label <> " ", theme.muted)
          }
        })
      [
        list.fold(parts, segment.empty, fn(acc, p) {
          case acc.cell_length {
            0 -> p
            _ -> segment.concat([acc, segment.text("│", theme.border), p])
          }
        }),
      ]
    }
    widget.Log(_, lines, scroll) -> {
      let total = list.length(lines)
      let start = int.clamp(total - h - scroll, 0, int.max(total - 1, 0))
      lines
      |> list.drop(start)
      |> list.take(h)
      |> list.map(segment.text(_, theme.base))
    }
    widget.Rule(_, title) -> {
      case title {
        "" -> [segment.text(string.repeat("─", w), theme.border)]
        t -> {
          let label = segment.text(" " <> t <> " ", theme.muted)
          let rest = int.max(w - 2 - label.cell_length, 0)
          [
            segment.concat([
              segment.text("──", theme.border),
              label,
              segment.text(string.repeat("─", rest), theme.border),
            ]),
          ]
        }
      }
    }
    widget.Checklist(_, domains, expanded, _) -> {
      list.index_map(domains, fn(domain, i) {
        let open = list.contains(expanded, i)
        let passed = list.count(domain.items, fn(it) { it.passed })
        let total = list.length(domain.items)
        let glyph = case open {
          True -> "▾ "
          False -> "▸ "
        }
        let head_style = case passed == total {
          True -> theme.ok
          False -> theme.warn
        }
        let head =
          segment.concat([
            segment.text(glyph <> domain.title, case is_focus {
              True -> theme.accent
              False -> theme.base
            }),
            segment.text(
              " " <> int.to_string(passed) <> "/" <> int.to_string(total),
              head_style,
            ),
          ])
        let items = case open {
          True ->
            list.map(domain.items, fn(it) {
              let mark = case it.passed {
                True -> segment.text("  [x] ", theme.ok)
                False -> segment.text("  [ ] ", theme.danger)
              }
              segment.concat([
                mark,
                segment.text(it.id <> " ", theme.muted),
                segment.text(it.label, theme.base),
              ])
            })
          False -> []
        }
        [head, ..items]
      })
      |> list.flatten
      |> list.take(h)
    }
    widget.StatusBar(_, fields) -> {
      let parts =
        list.map(fields, fn(f) {
          let label = case f.label {
            "" -> segment.text(" ", theme.muted)
            l -> segment.text(" " <> l <> " ", theme.muted)
          }
          segment.append(
            label,
            segment.text(f.value <> " ", style.combine(theme.base, f.style)),
          )
        })
      [
        list.fold(parts, segment.empty, fn(acc, p) {
          case acc.cell_length {
            0 -> p
            _ -> segment.concat([acc, segment.text("│", theme.border), p])
          }
        }),
      ]
    }
    widget.Container(..) | widget.Grid(..) -> []
  }
}

fn cells_row(cells: List(String), widths: List(Int), st: Style) -> Strip {
  let padded =
    list.append(
      cells,
      list.repeat("", int.max(list.length(widths) - list.length(cells), 0)),
    )
  list.zip(padded, widths)
  |> list.map(fn(pair) { segment.fit(segment.text(pair.0, st), pair.1, st) })
  |> segment.concat
}

/// Keep `cursor` visible within `height` rows.
fn scroll_to(lines: List(Strip), cursor: Int, height: Int) -> List(Strip) {
  let total = list.length(lines)
  case total <= height {
    True -> lines
    False -> {
      let start = int.clamp(cursor - height + 1, 0, total - height)
      lines |> list.drop(start) |> list.take(height)
    }
  }
}

/// Word-agnostic hard wrap of text to `width`, split on newlines first.
fn wrap_lines(text: String, width: Int, st: Style) -> List(Strip) {
  case width <= 0 {
    True -> []
    False ->
      text
      |> string.split("\n")
      |> list.flat_map(fn(line) {
        case line {
          "" -> [segment.text("", st)]
          _ ->
            chunk(string.to_graphemes(line), width, [], [], 0)
            |> list.map(segment.text(_, st))
        }
      })
  }
}

fn chunk(
  graphemes: List(String),
  width: Int,
  out: List(String),
  cur: List(String),
  used: Int,
) -> List(String) {
  case graphemes {
    [] ->
      case cur {
        [] -> list.reverse(out)
        _ -> list.reverse([cur |> list.reverse |> string.concat, ..out])
      }
    [g, ..rest] -> {
      let gw = segment.grapheme_width(g)
      case used + gw > width && cur != [] {
        True ->
          chunk(
            graphemes,
            width,
            [cur |> list.reverse |> string.concat, ..out],
            [],
            0,
          )
        False -> chunk(rest, width, out, [g, ..cur], used + gw)
      }
    }
  }
}

const bars = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

/// Sparkline over the last `width` samples (Textual `Sparkline` reference).
pub fn sparkline(data: List(Float), width: Int) -> String {
  let data = list.drop(data, int.max(list.length(data) - width, 0))
  case data {
    [] -> ""
    _ -> {
      let lo = list.fold(data, 1.0e308, float.min)
      let hi = list.fold(data, -1.0e308, float.max)
      let span = case hi -. lo {
        0.0 -> 1.0
        s -> s
      }
      data
      |> list.map(fn(v) {
        let idx = float.round({ v -. lo } /. span *. 7.0)
        bars |> list.drop(int.clamp(idx, 0, 7)) |> list.first |> unwrap("▁")
      })
      |> string.concat
    }
  }
}

fn unwrap(r: Result(a, b), default: a) -> a {
  case r {
    Ok(v) -> v
    Error(_) -> default
  }
}

pub fn region_of(size: Size) -> Region {
  Region(0, 0, size.width, size.height)
}
