//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/symbiosis/types</module>
////     <fsharp-lineage>Indrajaal.Substrate.L7.SymbiosisIndex (Elixir port)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L6_ECOSYSTEM</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-ECO-001, SC-ECO-004, SC-FED-005</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       Elixir SymbiosisIndex ecological relationship model → Gleam ADT.
////       Pure functional scoring, no side effects. Shannon H diversity tracking.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// सहजीवन प्रकार — Symbiosis Types
//// Ecological relationship model from mutualism theory.
//// Every pair of holons has a symbiotic relationship classified by net benefit.
////
//// STAMP: SC-ECO-001, SC-ECO-004, SC-FED-005, SC-MUDA-001

import gleam/float
import gleam/int
import gleam/list

/// Ecological relationship type — exhaustive ADT (SC-SATYA-006).
/// From ecology: classifies the net benefit exchange between two entities.
pub type RelationType {
  /// Both parties benefit (+/+)
  Mutualism
  /// One benefits, other neutral (+/0)
  Commensalism
  /// One benefits, other harmed (+/-)
  Parasitism
  /// One neutral, other harmed (0/-)
  Amensalism
  /// Both parties harmed (-/-)
  Competition
  /// Neither affected (0/0)
  Neutralism
}

/// A single symbiotic relationship between two holons.
pub type Relation {
  Relation(
    holon_a: String,
    holon_b: String,
    a_benefit: Float,
    b_benefit: Float,
    pair_index: Float,
    relation_type: RelationType,
  )
}

/// Aggregate symbiosis index across all tracked relationships.
pub type SymbiosisIndex {
  SymbiosisIndex(
    relations: List(Relation),
    global_index: Float,
    mutualism_count: Int,
    parasitism_count: Int,
    neutralism_count: Int,
    total_count: Int,
  )
}

/// Create a new empty symbiosis index.
pub fn new() -> SymbiosisIndex {
  SymbiosisIndex(
    relations: [],
    global_index: 0.0,
    mutualism_count: 0,
    parasitism_count: 0,
    neutralism_count: 0,
    total_count: 0,
  )
}

/// Classify a relationship based on benefit signs.
/// Threshold: |benefit| < 0.05 is considered neutral (0).
pub fn classify(a_benefit: Float, b_benefit: Float) -> RelationType {
  let a_pos = a_benefit >. 0.05
  let a_neg = a_benefit <. -0.05
  let b_pos = b_benefit >. 0.05
  let b_neg = b_benefit <. -0.05
  case a_pos, a_neg, b_pos, b_neg {
    True, _, True, _ -> Mutualism
    True, _, _, True -> Parasitism
    _, True, True, _ -> Parasitism
    True, _, False, False -> Commensalism
    False, False, True, _ -> Commensalism
    _, True, False, False -> Amensalism
    False, False, _, True -> Amensalism
    _, True, _, True -> Competition
    _, _, _, _ -> Neutralism
  }
}

/// Compute pair index = mean of both benefits.
pub fn pair_index(a_benefit: Float, b_benefit: Float) -> Float {
  float_round({ a_benefit +. b_benefit } /. 2.0, 4)
}

/// Record a new relationship in the index.
pub fn record(
  index: SymbiosisIndex,
  holon_a: String,
  holon_b: String,
  a_benefit: Float,
  b_benefit: Float,
) -> SymbiosisIndex {
  let rel_type = classify(a_benefit, b_benefit)
  let idx = pair_index(a_benefit, b_benefit)
  let relation =
    Relation(
      holon_a: holon_a,
      holon_b: holon_b,
      a_benefit: a_benefit,
      b_benefit: b_benefit,
      pair_index: idx,
      relation_type: rel_type,
    )
  let new_relations = [relation, ..index.relations]
  recompute(SymbiosisIndex(..index, relations: new_relations))
}

/// Get all relations of a specific type.
pub fn by_type(
  index: SymbiosisIndex,
  rel_type: RelationType,
) -> List(Relation) {
  list.filter(index.relations, fn(r) { r.relation_type == rel_type })
}

/// Relationship type to string.
pub fn relation_type_to_string(rt: RelationType) -> String {
  case rt {
    Mutualism -> "mutualism"
    Commensalism -> "commensalism"
    Parasitism -> "parasitism"
    Amensalism -> "amensalism"
    Competition -> "competition"
    Neutralism -> "neutralism"
  }
}

/// Relationship type to Sanskrit.
pub fn relation_type_to_sanskrit(rt: RelationType) -> String {
  case rt {
    Mutualism -> "परस्पर लाभ"
    Commensalism -> "एकपक्ष लाभ"
    Parasitism -> "परजीविता"
    Amensalism -> "एकपक्ष हानि"
    Competition -> "प्रतिस्पर्धा"
    Neutralism -> "तटस्थता"
  }
}

/// Check if the ecosystem is predominantly mutualistic (healthy).
pub fn is_healthy(index: SymbiosisIndex) -> Bool {
  index.global_index >. 0.0 && index.mutualism_count > index.parasitism_count
}

/// Ecosystem health score: fraction of mutualistic relationships.
pub fn mutualism_ratio(index: SymbiosisIndex) -> Float {
  case index.total_count {
    0 -> 1.0
    n -> int_to_float(index.mutualism_count) /. int_to_float(n)
  }
}

// -- Internal ----------------------------------------------------------------

fn recompute(index: SymbiosisIndex) -> SymbiosisIndex {
  let total = list.length(index.relations)
  let mut_count =
    list.length(
      list.filter(index.relations, fn(r) { r.relation_type == Mutualism }),
    )
  let par_count =
    list.length(
      list.filter(index.relations, fn(r) { r.relation_type == Parasitism }),
    )
  let neu_count =
    list.length(
      list.filter(index.relations, fn(r) { r.relation_type == Neutralism }),
    )
  let global = case total {
    0 -> 0.0
    _ -> {
      let sum =
        list.fold(index.relations, 0.0, fn(acc, r) { acc +. r.pair_index })
      float_round(sum /. int_to_float(total), 4)
    }
  }
  SymbiosisIndex(
    ..index,
    global_index: global,
    mutualism_count: mut_count,
    parasitism_count: par_count,
    neutralism_count: neu_count,
    total_count: total,
  )
}

fn int_to_float(n: Int) -> Float {
  let assert Ok(f) = float.parse(int.to_string(n) <> ".0")
  f
}

fn float_round(f: Float, _decimals: Int) -> Float {
  let factor = 10_000.0
  let rounded = float.round(f *. factor)
  int_to_float(rounded) /. factor
}
