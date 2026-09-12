//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/ui/lustre/ruliology</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-FRACTAL-001</stamp-controls></compliance></c3i-module>
//// Lustre page: Ruliology explorer — cellular automata, multiway systems, causal graphs.

import gleam/option.{type Option, None, Some}

// All 5 ruliology structures matching Rust ruliology.rs
pub type AutomatonState {
  AutomatonState(name: String, states: List(String), current: String, step_count: Int)
}

pub type MultiwayNode {
  MultiwayNode(id: String, branches: List(String))
}

pub type CausalEdge {
  CausalEdge(from: String, to: String, label: String, weight: Float)
}

pub type CausalGraph {
  CausalGraph(nodes: List(String), edges: List(CausalEdge))
}

pub type ProductionRule {
  ProductionRule(name: String, salience: Int, preconditions: List(String), decision: String, reason: String)
}

pub type ProductionSystem {
  ProductionSystem(rules: List(ProductionRule), fired_count: Int, last_decision: String)
}

pub type HypergraphEdge {
  HypergraphEdge(id: String, source_nodes: List(String), target_nodes: List(String), label: String)
}

pub type Hypergraph {
  Hypergraph(nodes: List(String), edges: List(HypergraphEdge))
}

pub type RuliologyModel {
  RuliologyModel(
    automata: List(AutomatonState),
    multiway_nodes: List(MultiwayNode),
    causal_graph: CausalGraph,
    production_system: ProductionSystem,
    hypergraph: Hypergraph,
    selected_automaton: Option(String),
    rule_number: Int,
    steps: Int,
    loading: Bool,
    error: Option(String),
  )
}

pub type RuliologyMsg {
  AutomataLoaded(List(AutomatonState))
  MultiwayLoaded(List(MultiwayNode))
  CausalGraphLoaded(CausalGraph)
  ProductionSystemLoaded(ProductionSystem)
  HypergraphLoaded(Hypergraph)
  SetRuleNumber(Int)
  StepAutomaton
  FireRule(String)
  SelectAutomaton(String)
  RefreshRuliology
  ErrorReceived(String)
}

pub fn init() -> RuliologyModel {
  RuliologyModel(
    automata: [],
    multiway_nodes: [],
    causal_graph: CausalGraph([], []),
    production_system: ProductionSystem([], 0, ""),
    hypergraph: Hypergraph([], []),
    selected_automaton: None,
    rule_number: 110,
    steps: 0,
    loading: False,
    error: None,
  )
}

pub fn update(model: RuliologyModel, msg: RuliologyMsg) -> RuliologyModel {
  case msg {
    AutomataLoaded(a) -> RuliologyModel(..model, automata: a, loading: False)
    MultiwayLoaded(n) -> RuliologyModel(..model, multiway_nodes: n)
    CausalGraphLoaded(g) -> RuliologyModel(..model, causal_graph: g)
    ProductionSystemLoaded(ps) -> RuliologyModel(..model, production_system: ps)
    HypergraphLoaded(h) -> RuliologyModel(..model, hypergraph: h)
    SetRuleNumber(n) -> RuliologyModel(..model, rule_number: n)
    StepAutomaton -> RuliologyModel(..model, steps: model.steps + 1)
    FireRule(name) -> {
      let ps = model.production_system
      RuliologyModel(..model, production_system: ProductionSystem(
        ..ps, fired_count: ps.fired_count + 1, last_decision: name))
    }
    SelectAutomaton(name) -> RuliologyModel(..model, selected_automaton: Some(name))
    RefreshRuliology -> RuliologyModel(..model, loading: True)
    ErrorReceived(e) -> RuliologyModel(..model, error: Some(e), loading: False)
  }
}

// =============================================================================
// NIF-backed data loading (SC-WIRE-001: real ops data)
// =============================================================================

import cepaf_gleam/c3i/nif
import gleam/dynamic/decode
import gleam/json

/// Load ruliology automaton from NIF → Rust → ruliology.rs
pub fn load_automaton_from_nif(name: String) -> AutomatonState {
  let raw = nif.ruliology_automaton(name)
  let decoder = {
    use n <- decode.field("name", decode.string)
    use current <- decode.field("current", decode.string)
    use step_count <- decode.field("step_count", decode.int)
    decode.success(#(n, current, step_count))
  }
  case json.parse(raw, decoder) {
    Ok(#(n, current, steps)) -> AutomatonState(n, [], current, steps)
    Error(_) -> AutomatonState(name, [], "unknown", 0)
  }
}

/// Load multiway system from NIF → Rust → ruliology.rs
pub fn load_multiway_from_nif() -> String {
  nif.ruliology_multiway()
}

/// Load causal graph from NIF → Rust → ruliology.rs
pub fn load_causal_from_nif() -> String {
  nif.ruliology_causal()
}
