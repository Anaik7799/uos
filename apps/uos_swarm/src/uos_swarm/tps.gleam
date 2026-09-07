//// Toyota Production System (TPS) flow control for the swarm and the TUI
//// task board: WIP-limited Kanban columns, Andon signalling, Jidoka
//// stop-the-line, takt time, first-pass yield, throughput and Muda
//// (waste) tracking.
////
//// Reference: Toyota Production System / Lean Kanban board concepts,
//// adapted as a pure Gleam flow-control model for the uos_tui task board.
//// STAMP id: SC-TUI-W09-001

import gleam/int
import gleam/list
import gleam/option

/// A card's position on the Kanban board.
pub type Column {
  Planned
  Running
  Verifying
  Done
  Failed
}

/// The seven classical wastes (Muda) of lean flow.
pub type Muda {
  Overproduction
  Waiting
  Transport
  Overprocessing
  Inventory
  Motion
  Defects
}

/// Andon (line-status) signal.
pub type Andon {
  Green
  Yellow
  Red
}

/// One unit of work flowing through the board.
pub type Card {
  Card(
    id: String,
    slice: String,
    owner: String,
    column: Column,
    muda: List(Muda),
    cycle_minutes: option.Option(Int),
  )
}

/// The board: cards plus WIP/takt/jidoka control state.
pub type Board {
  Board(
    cards: List(Card),
    wip_limit: Int,
    takt_minutes: Int,
    jidoka_stops: Int,
    line_stopped: Bool,
  )
}

/// A fresh, empty board with the given WIP limit and takt time.
pub fn new(wip_limit: Int, takt_minutes: Int) -> Board {
  Board(
    cards: [],
    wip_limit: wip_limit,
    takt_minutes: takt_minutes,
    jidoka_stops: 0,
    line_stopped: False,
  )
}

fn has_id(cards: List(Card), id: String) -> Bool {
  list.any(cards, fn(c) { c.id == id })
}

/// Add a card to the board. A card with a duplicate id is ignored.
pub fn add(board: Board, card: Card) -> Board {
  case has_id(board.cards, card.id) {
    True -> board
    False -> Board(..board, cards: [card, ..board.cards])
  }
}

/// Current work-in-progress count: cards in Running or Verifying.
pub fn wip(board: Board) -> Int {
  list.count(board.cards, fn(c) { c.column == Running || c.column == Verifying })
}

fn find_card(board: Board, id: String) -> Result(Card, Nil) {
  list.find(board.cards, fn(c) { c.id == id })
}

fn replace_card(board: Board, id: String, updated: Card) -> Board {
  let cards =
    list.map(board.cards, fn(c) {
      case c.id == id {
        True -> updated
        False -> c
      }
    })
  Board(..board, cards: cards)
}

/// Pull a Planned card into Running, respecting the WIP limit and the
/// stopped-line interlock.
pub fn pull(board: Board, id: String) -> Result(Board, String) {
  case find_card(board, id) {
    Error(Nil) -> Error("card not found: " <> id)
    Ok(card) ->
      case card.column {
        Planned ->
          case board.line_stopped {
            True -> Error("line stopped")
            False ->
              case wip(board) < board.wip_limit {
                True ->
                  Ok(replace_card(board, id, Card(..card, column: Running)))
                False -> Error("wip limit reached")
              }
          }
        _ -> Error("card not in Planned column")
      }
  }
}

fn legal_transition(from: Column, to: Column) -> Bool {
  case from, to {
    Running, Verifying -> True
    Verifying, Done -> True
    Verifying, Failed -> True
    Failed, Running -> True
    _, _ -> False
  }
}

/// Move a card between columns, only along legal TPS transitions.
pub fn move(board: Board, id: String, column: Column) -> Result(Board, String) {
  case find_card(board, id) {
    Error(Nil) -> Error("card not found: " <> id)
    Ok(card) ->
      case legal_transition(card.column, column) {
        True -> Ok(replace_card(board, id, Card(..card, column: column)))
        False -> Error("illegal transition")
      }
  }
}

/// Jidoka: mark a card Failed, record a stop, and halt the line.
/// A missing card id leaves the board unchanged.
pub fn jidoka(board: Board, id: String) -> Board {
  case find_card(board, id) {
    Error(Nil) -> board
    Ok(card) ->
      Board(
        ..replace_card(board, id, Card(..card, column: Failed)),
        jidoka_stops: board.jidoka_stops + 1,
        line_stopped: True,
      )
  }
}

/// Resume the line after a Jidoka stop.
pub fn resume(board: Board) -> Board {
  Board(..board, line_stopped: False)
}

/// Andon signal derived from line status, failed-card count and WIP.
pub fn andon(board: Board) -> Andon {
  let failed = list.count(board.cards, fn(c) { c.column == Failed })
  case board.line_stopped || failed >= 2 {
    True -> Red
    False ->
      case failed == 1 || wip(board) == board.wip_limit {
        True -> Yellow
        False -> Green
      }
  }
}

/// Takt time: available production minutes divided by customer demand.
/// Zero when demand is non-positive.
pub fn takt(available_minutes: Int, demand: Int) -> Float {
  case demand <= 0 {
    True -> 0.0
    False -> int.to_float(available_minutes) /. int.to_float(demand)
  }
}

/// First-pass yield as an integer percent: Done / (Done + Failed).
/// 100 when there are no finished-or-failed cards.
pub fn first_pass_yield(board: Board) -> Int {
  let done = list.count(board.cards, fn(c) { c.column == Done })
  let failed = list.count(board.cards, fn(c) { c.column == Failed })
  case done + failed {
    0 -> 100
    total -> done * 100 / total
  }
}

/// Throughput in Done cards per hour, given elapsed minutes.
/// Zero when elapsed_minutes is non-positive.
pub fn throughput(board: Board, elapsed_minutes: Int) -> Float {
  case elapsed_minutes <= 0 {
    True -> 0.0
    False -> {
      let done = list.count(board.cards, fn(c) { c.column == Done })
      int.to_float(done) *. 60.0 /. int.to_float(elapsed_minutes)
    }
  }
}

const all_muda = [
  Overproduction,
  Waiting,
  Transport,
  Overprocessing,
  Inventory,
  Motion,
  Defects,
]

/// Count of each Muda kind across every card on the board.
pub fn muda_report(board: Board) -> List(#(Muda, Int)) {
  list.map(all_muda, fn(m) {
    let count =
      list.fold(board.cards, 0, fn(acc, c) {
        acc + list.count(c.muda, fn(x) { x == m })
      })
    #(m, count)
  })
}

/// Human-readable label for a Muda kind.
pub fn muda_label(m: Muda) -> String {
  case m {
    Overproduction -> "Overproduction"
    Waiting -> "Waiting"
    Transport -> "Transport"
    Overprocessing -> "Overprocessing"
    Inventory -> "Inventory"
    Motion -> "Motion"
    Defects -> "Defects"
  }
}

/// Human-readable label for a Column.
pub fn column_label(c: Column) -> String {
  case c {
    Planned -> "Planned"
    Running -> "Running"
    Verifying -> "Verifying"
    Done -> "Done"
    Failed -> "Failed"
  }
}

fn card_line(card: Card) -> String {
  "| "
  <> card.id
  <> " | "
  <> card.slice
  <> " | "
  <> card.owner
  <> " | "
  <> column_label(card.column)
  <> " |"
}

/// Render the board as a Markdown table, one row per card.
pub fn to_markdown(board: Board) -> String {
  let header = "| id | slice | owner | column |\n| --- | --- | --- | --- |"
  let rows = list.map(board.cards, card_line)
  header <> "\n" <> string_join(rows, "\n")
}

fn string_join(parts: List(String), sep: String) -> String {
  case parts {
    [] -> ""
    [first, ..rest] ->
      list.fold(rest, first, fn(acc, part) { acc <> sep <> part })
  }
}
