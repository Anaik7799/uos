//// Finite string-rewriting exploration, not the mathematical total Ruliad.
//// Each edge replaces one occurrence of one supplied rule in one source state.
//// Hard limits fail closed rather than silently truncating the graph.
//// SC-HOLON-001; #fractal-l5 #fractal-l8 #zero-muda

import gleam/list
import gleam/result
import gleam/string

pub type Rule {
  Rule(from: String, to: String)
}

pub type Edge {
  Edge(source: String, target: String, rule: Int, offset: Int)
}

pub type Graph {
  Graph(
    states: List(String),
    edges: List(Edge),
    frontier: List(String),
    steps: Int,
  )
}

pub fn explore(
  seed: String,
  rules: List(Rule),
  steps: Int,
) -> Result(Graph, String) {
  case
    string.byte_size(seed) <= 128
    && seed != ""
    && steps >= 1
    && steps <= 4
    && list.length(rules) >= 1
    && list.length(rules) <= 8
    && list.all(rules, fn(r) {
      r.from != ""
      && string.byte_size(r.from) <= 32
      && string.byte_size(r.to) <= 32
    })
  {
    False ->
      Error(
        "rewrite bounds: nonempty seed <=128 bytes, 1..8 nonempty rules <=32 bytes, 1..4 steps",
      )
    True -> advance(Graph([seed], [], [seed], 0), rules, steps)
  }
}

fn advance(
  g: Graph,
  rules: List(Rule),
  remaining: Int,
) -> Result(Graph, String) {
  case remaining == 0 || list.is_empty(g.frontier) {
    True -> Ok(g)
    False -> {
      use edges <- result.try(
        list.try_fold(g.frontier, [], fn(edges, source) {
          list.try_fold(
            list.index_map(rules, fn(r, i) { #(r, i) }),
            edges,
            fn(edges, pair) {
              let #(rule, index) = pair
              occurrences(source, "", source, rule, index, 0, edges)
            },
          )
        }),
      )
      let next = edges |> list.map(fn(e) { e.target }) |> list.unique
      let states = list.unique(list.append(g.states, next))
      case
        list.length(states) > 64
        || list.length(g.edges) + list.length(edges) > 2048
      {
        True ->
          Error(
            "rewrite exploration budget exceeded (64 states / 2048 transitions)",
          )
        False ->
          advance(
            Graph(states, list.append(g.edges, edges), next, g.steps + 1),
            rules,
            remaining - 1,
          )
      }
    }
  }
}

fn occurrences(
  source: String,
  prefix: String,
  suffix: String,
  rule: Rule,
  rule_index: Int,
  offset: Int,
  edges: List(Edge),
) -> Result(List(Edge), String) {
  case suffix {
    "" -> Ok(edges)
    _ -> {
      use edges <- result.try(
        case string.slice(suffix, 0, string.length(rule.from)) == rule.from {
          False -> Ok(edges)
          True -> {
            let target =
              prefix
              <> rule.to
              <> string.drop_start(suffix, string.length(rule.from))
            case string.byte_size(target) > 256 || list.length(edges) >= 2048 {
              True ->
                Error(
                  "rewrite transition budget exceeded (256 bytes/state / 2048 transitions)",
                )
              False -> Ok([Edge(source, target, rule_index, offset), ..edges])
            }
          }
        },
      )
      case string.pop_grapheme(suffix) {
        Error(_) -> Ok(edges)
        Ok(#(head, tail)) ->
          occurrences(
            source,
            prefix <> head,
            tail,
            rule,
            rule_index,
            offset + 1,
            edges,
          )
      }
    }
  }
}
