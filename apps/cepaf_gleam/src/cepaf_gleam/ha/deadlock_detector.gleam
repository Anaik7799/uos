// =============================================================================
// deadlock_detector.gleam — 2PL Distributed Deadlock Detection via Wait-For Graph
// STAMP: SC-SIL6-001, SC-2PL-001, SC-DEADLOCK-001
// Codex Astra Mode: Directed Cycle Detection & Optimal Victim Selection
// =============================================================================

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string

pub type WaitEdge {
  WaitEdge(waiter: String, holder: String)
}

pub type WaitForGraph {
  WaitForGraph(edges: List(WaitEdge))
}

pub fn new_wfg() -> WaitForGraph {
  WaitForGraph(edges: [])
}

pub fn add_wait_edge(wfg: WaitForGraph, waiter: String, holder: String) -> WaitForGraph {
  case waiter == holder {
    True -> wfg // Self-wait is ignored or immediate cycle
    False -> {
      let exists = list.any(wfg.edges, fn(e) { e.waiter == waiter && e.holder == holder })
      case exists {
        True -> wfg
        False -> WaitForGraph(edges: [WaitEdge(waiter, holder), ..wfg.edges])
      }
    }
  }
}

pub fn remove_wait_edge(wfg: WaitForGraph, waiter: String, holder: String) -> WaitForGraph {
  WaitForGraph(edges: list.filter(wfg.edges, fn(e) { e.waiter != waiter || e.holder != holder }))
}

pub fn remove_all_for_tx(wfg: WaitForGraph, tx_id: String) -> WaitForGraph {
  WaitForGraph(edges: list.filter(wfg.edges, fn(e) { e.waiter != tx_id && e.holder != tx_id }))
}

// DFS cycle detection
fn dfs_find_cycle(
  current: String,
  edges: List(WaitEdge),
  visited: List(String),
  path: List(String),
) -> Option(List(String)) {
  case list.contains(path, current) {
    True -> Some(list.reverse([current, ..path]))
    False -> {
      case list.contains(visited, current) {
        True -> None
        False -> {
          let outgoing =
            list.filter(edges, fn(e) { e.waiter == current })
            |> list.map(fn(e) { e.holder })

          let next_path = [current, ..path]
          list.fold_until(outgoing, None, fn(_acc, next_node) {
            case dfs_find_cycle(next_node, edges, [current, ..visited], next_path) {
              Some(cycle) -> list.Stop(Some(cycle))
              None -> list.Continue(None)
            }
          })
        }
      }
    }
  }
}

pub fn detect_deadlock(wfg: WaitForGraph) -> Option(List(String)) {
  let all_waiters = list.map(wfg.edges, fn(e) { e.waiter }) |> list.unique
  list.fold_until(all_waiters, None, fn(_acc, start_node) {
    case dfs_find_cycle(start_node, wfg.edges, [], []) {
      Some(cycle) -> list.Stop(Some(cycle))
      None -> list.Continue(None)
    }
  })
}

pub fn select_deadlock_victim(cycle: List(String)) -> Option(String) {
  // Select youngest / lexicographically highest ID as deterministic victim
  case cycle {
    [] -> None
    [head, ..tail] -> {
      let victim = list.fold(tail, head, fn(acc, node) {
        case string.compare(node, acc) {
          order.Gt -> node
          _ -> acc
        }
      })
      Some(victim)
    }
  }
}
