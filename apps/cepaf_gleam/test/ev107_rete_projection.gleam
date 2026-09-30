import cepaf_gleam/knowledge/rete_ul_verifier as rete
import gleam/int
import gleam/io
import gleam/list

// This emits observations from the compiled engine. The independent OCaml
// reference computes reachability from the mask, without calling this engine.
fn selected(mask: Int, bit: Int) -> Bool {
  int.bitwise_and(mask, bit) != 0
}

fn initial(mask: Int) -> List(rete.ReteFact) {
  list.filter_map([#(1, "f0"), #(2, "f1"), #(4, "f2"), #(8, "f3")], fn(entry) {
    case selected(mask, entry.0) {
      True -> Ok(rete.ReteFact(entry.1, [#("value", "yes")]))
      False -> Error(Nil)
    }
  })
}

fn rules(mask: Int, ordering: Int) -> List(rete.ReteRule) {
  let edges = [
    #(1, 0, 1),
    #(2, 0, 2),
    #(4, 0, 3),
    #(8, 1, 2),
    #(16, 1, 3),
    #(32, 2, 3),
  ]
  let selected_rules =
    list.filter_map(edges, fn(edge) {
      case selected(mask, edge.0) {
        False -> Error(Nil)
        True ->
          Ok(rete.ReteRule(
            "edge" <> int.to_string(edge.0),
            [
              rete.ReteCondition(
                "f" <> int.to_string(edge.1),
                "value",
                rete.OpEq,
                "yes",
              ),
            ],
            rete.ConsequenceAssert("f" <> int.to_string(edge.2), "value", "yes"),
          ))
      }
    })
  case ordering {
    0 -> selected_rules
    _ -> list.reverse(selected_rules)
  }
}

fn observed_mask(facts: List(rete.ReteFact)) -> Int {
  list.fold(facts, 0, fn(mask, fact) {
    let assert [#("value", "yes")] = fact.attributes
    let bit = case fact.kind {
      "f0" -> 1
      "f1" -> 2
      "f2" -> 4
      "f3" -> 8
      _ -> panic as "unexpected derived fact kind"
    }
    let assert False = selected(mask, bit)
    mask + bit
  })
}

fn observe(edge_mask: Int, seed_mask: Int, ordering: Int) {
  let memory =
    rete.WorkingMemory(
      initial(seed_mask),
      rules(edge_mask, ordering),
      [],
      True,
      0,
    )
  let assert Ok(run) = rete.try_fire_forward_chaining(memory)
  let assert [] = run.verdicts
  io.println(
    "RETE_CASE|"
    <> int.to_string(edge_mask)
    <> "|"
    <> int.to_string(seed_mask)
    <> "|"
    <> int.to_string(ordering)
    <> "|"
    <> int.to_string(observed_mask(run.memory.facts))
    <> "|"
    <> int.to_string(run.memory.fired_count),
  )
}

pub fn main() {
  int.range(0, 64, Nil, fn(_, edge_mask) {
    int.range(0, 16, Nil, fn(_, seed_mask) {
      observe(edge_mask, seed_mask, 0)
      observe(edge_mask, seed_mask, 1)
    })
  })
  io.println("PASS EV107 finite projection emitted 2048 observed cases")
}
