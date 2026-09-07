//// Command palette with fuzzy search over registered commands.
//// Reference: Textual `CommandPalette` (case-insensitive subsequence fuzzy
//// matching with position/word-boundary/consecutive bonuses, ranked results).
//// STAMP: SC-TUI-W03-001.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import uos_tui/layout
import uos_tui/widget.{type Widget, Container, Input, ListView}

/// A single registrable command bound to a `msg` action.
pub type Command(msg) {
  Command(id: String, title: String, keywords: List(String), action: msg)
}

/// A flat list of commands available to the palette.
pub type Registry(msg) =
  List(Command(msg))

const boundary_graphemes = [" ", "-", "_", "/"]

/// Case-insensitive subsequence fuzzy score. `None` if `query` is not a
/// subsequence of `candidate`. Empty query always scores `Some(0)`.
pub fn score(query: String, candidate: String) -> Option(Int) {
  let q = string.lowercase(query)
  let c = string.lowercase(candidate)
  case q {
    "" -> Some(0)
    _ -> {
      let q_graphemes = string.to_graphemes(q)
      let c_graphemes = string.to_graphemes(c)
      case match_subsequence(q_graphemes, c_graphemes, 0, True, 0) {
        None -> None
        Some(#(matched, bonus)) -> {
          let prefix_bonus = case string.starts_with(c, q) {
            True -> 30
            False -> 0
          }
          Some(100 * matched + bonus + prefix_bonus)
        }
      }
    }
  }
}

/// Walk the candidate graphemes trying to consume the query graphemes in
/// order. Tracks: previous grapheme (for boundary detection), whether the
/// previous position was a match (for consecutive bonus), and running gap
/// penalty. Returns `Some(#(matched_count, bonus))` on full match.
fn match_subsequence(
  query: List(String),
  candidate: List(String),
  index: Int,
  prev_was_boundary: Bool,
  bonus: Int,
) -> Option(#(Int, Int)) {
  case query {
    [] -> Some(#(0, bonus))
    [q_head, ..q_rest] ->
      case candidate {
        [] -> None
        [c_head, ..c_rest] ->
          case string.lowercase(c_head) == string.lowercase(q_head) {
            True -> {
              let boundary_hit = case prev_was_boundary {
                True -> 10
                False -> 0
              }
              case
                match_subsequence(
                  q_rest,
                  c_rest,
                  index + 1,
                  list.contains(boundary_graphemes, c_head),
                  bonus + boundary_hit,
                )
              {
                None -> None
                Some(#(matched, total_bonus)) ->
                  Some(#(matched + 1, total_bonus))
              }
            }
            False ->
              match_subsequence(
                query,
                c_rest,
                index + 1,
                list.contains(boundary_graphemes, c_head),
                bonus - 1,
              )
          }
      }
  }
}

/// Rank candidates by descending score, dropping non-matches. Stable for
/// ties: candidates keep their relative input order.
pub fn rank(query: String, candidates: List(String)) -> List(#(String, Int)) {
  candidates
  |> list.index_map(fn(candidate, i) { #(candidate, i) })
  |> list.filter_map(fn(pair) {
    let #(candidate, i) = pair
    case score(query, candidate) {
      None -> Error(Nil)
      Some(s) -> Ok(#(candidate, s, i))
    }
  })
  |> list.sort(fn(a, b) {
    let #(_, score_a, idx_a) = a
    let #(_, score_b, idx_b) = b
    case int.compare(score_b, score_a) {
      order.Eq -> int.compare(idx_a, idx_b)
      other -> other
    }
  })
  |> list.map(fn(triple) {
    let #(candidate, s, _) = triple
    #(candidate, s)
  })
}

/// Search a registry's commands, matching against title and keywords,
/// keeping the best score per command. `limit` caps the number of results
/// (any `limit <= 0` yields no results).
pub fn search(
  registry: Registry(msg),
  query: String,
  limit: Int,
) -> List(Command(msg)) {
  registry
  |> list.filter_map(fn(cmd) {
    let title_score = score(query, cmd.title)
    let keyword_scores =
      list.filter_map(cmd.keywords, fn(k) {
        case score(query, k) {
          None -> Error(Nil)
          Some(s) -> Ok(s)
        }
      })
    let best = case title_score, keyword_scores {
      None, [] -> None
      Some(s), [] -> Some(s)
      None, scores -> Some(max_int(scores))
      Some(s), scores -> Some(int.max(s, max_int(scores)))
    }
    case best {
      None -> Error(Nil)
      Some(s) -> Ok(#(cmd, s))
    }
  })
  |> list.index_map(fn(pair, i) {
    let #(cmd, s) = pair
    #(cmd, s, i)
  })
  |> list.sort(fn(a, b) {
    let #(_, score_a, idx_a) = a
    let #(_, score_b, idx_b) = b
    case int.compare(score_b, score_a) {
      order.Eq -> int.compare(idx_a, idx_b)
      other -> other
    }
  })
  |> list.map(fn(triple) {
    let #(cmd, _, _) = triple
    cmd
  })
  |> take(limit)
}

fn max_int(xs: List(Int)) -> Int {
  case xs {
    [] -> 0
    [head, ..rest] -> list.fold(rest, head, int.max)
  }
}

fn take(xs: List(a), n: Int) -> List(a) {
  case n <= 0 {
    True -> []
    False ->
      case xs {
        [] -> []
        [head, ..rest] -> [head, ..take(rest, n - 1)]
      }
  }
}

/// Render the palette: bordered container titled "Command palette" holding
/// the search input and a results list view.
pub fn view(
  query: String,
  results: List(Command(msg)),
  cursor: Int,
  on_change: fn(String) -> msg,
  on_move: fn(Int) -> msg,
  on_select: fn(Int) -> msg,
) -> Widget(msg) {
  let input =
    Input(
      id: "palette-input",
      value: query,
      cursor: string.length(query),
      placeholder: "type to search",
      on_change: on_change,
      on_submit: None,
    )
  let items = list.map(results, fn(cmd) { cmd.title <> "  (" <> cmd.id <> ")" })
  let list_view =
    ListView(
      id: "palette-results",
      items: items,
      cursor: cursor,
      on_move: Some(on_move),
      on_select: Some(on_select),
    )
  Container(
    id: "palette",
    direction: layout.Vertical,
    children: [#(layout.Cells(3), input), #(layout.Fraction(1), list_view)],
    border: True,
    title: "Command palette",
  )
}
