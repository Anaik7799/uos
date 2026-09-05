//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/zettelkasten/trust</module></identity>
////   <fractal-topology><layer>L0_CONSTITUTIONAL</layer></fractal-topology>
////   <compliance><stamp-controls>SC-SMRITI-130, SC-SAFETY-014</stamp-controls></compliance>
//// </c3i-module>
////
//// Trust scoring for Zettelkasten knowledge.
//// Not all knowledge is equal — axioms outweigh anecdotes.
//// STAMP: SC-SMRITI-130 (query results include integrity proofs), SC-SAFETY-014 (truthfulness)

import cepaf_gleam/zettelkasten/types.{
  type Holon, type RhetoricalFunction, Anecdote, Axiom, Evidence, Hypothesis,
}

/// Compute effective trust considering entropy decay.
/// Trust degrades as entropy increases: effective = base * (1 - entropy).
pub fn effective_trust(holon: Holon) -> Float {
  let base = types.trust_for(holon.rhetorical)
  base.value *. { 1.0 -. holon.entropy }
}

/// Rank holons by effective trust (highest first).
pub fn rank_by_trust(holons: List(Holon)) -> List(Holon) {
  list_sort_desc(holons, effective_trust)
}

/// Filter holons above a minimum trust threshold.
pub fn filter_trusted(holons: List(Holon), min_trust: Float) -> List(Holon) {
  list_filter(holons, fn(h) { effective_trust(h) >=. min_trust })
}

/// Compute aggregate trust score for a set of holons (weighted average).
pub fn aggregate_trust(holons: List(Holon)) -> Float {
  case holons {
    [] -> 0.0
    _ -> {
      let #(sum, count) =
        list_fold(holons, #(0.0, 0.0), fn(acc, h) {
          #(acc.0 +. effective_trust(h), acc.1 +. 1.0)
        })
      case count >. 0.0 {
        True -> sum /. count
        False -> 0.0
      }
    }
  }
}

/// Should this holon be included in RAG context?
/// Excluded if: entropy > 0.9 OR effective trust < 0.1
pub fn is_rag_eligible(holon: Holon) -> Bool {
  holon.entropy <. 0.9 && effective_trust(holon) >=. 0.1
}

/// Trust label for display.
pub fn trust_label(trust: Float) -> String {
  case trust >=. 0.8 {
    True -> "high"
    False ->
      case trust >=. 0.5 {
        True -> "medium"
        False ->
          case trust >=. 0.2 {
            True -> "low"
            False -> "untrusted"
          }
      }
  }
}

/// Compare two rhetorical functions by authority.
/// Axiom > Evidence > Hypothesis > Anecdote.
pub fn authority_rank(function: RhetoricalFunction) -> Int {
  case function {
    Axiom -> 4
    Evidence -> 3
    Hypothesis -> 2
    Anecdote -> 1
  }
}

// Helpers (avoiding gleam/list import for minimal coupling)
fn list_filter(items: List(a), predicate: fn(a) -> Bool) -> List(a) {
  case items {
    [] -> []
    [first, ..rest] ->
      case predicate(first) {
        True -> [first, ..list_filter(rest, predicate)]
        False -> list_filter(rest, predicate)
      }
  }
}

fn list_fold(items: List(a), acc: b, f: fn(b, a) -> b) -> b {
  case items {
    [] -> acc
    [first, ..rest] -> list_fold(rest, f(acc, first), f)
  }
}

fn list_sort_desc(items: List(a), key: fn(a) -> Float) -> List(a) {
  case items {
    [] -> []
    [pivot, ..rest] -> {
      let pivot_key = key(pivot)
      let higher = list_filter(rest, fn(x) { key(x) >=. pivot_key })
      let lower = list_filter(rest, fn(x) { key(x) <. pivot_key })
      list_append(list_sort_desc(higher, key), [
        pivot,
        ..list_sort_desc(lower, key)
      ])
    }
  }
}

fn list_append(a: List(x), b: List(x)) -> List(x) {
  case a {
    [] -> b
    [first, ..rest] -> [first, ..list_append(rest, b)]
  }
}
