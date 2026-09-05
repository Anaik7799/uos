/// Lustre component for Knowledge (Smriti) plane (SC-GLM-UI-001).
/// Imports from knowledge/domain.gleam — no type duplication (SC-GLM-UI-009).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009
import cepaf_gleam/knowledge/domain.{
  type HolonLevel, type KnowledgeLink, type KnowledgeNode,
}
import cepaf_gleam/ui/domain as ui_domain
import cepaf_gleam/ui/zenoh_otel
import gleam/list
import gleam/option.{type Option, None, Some}

pub type KnowledgeModel {
  KnowledgeModel(
    nodes: List(KnowledgeNode),
    links: List(KnowledgeLink),
    selected_node: Option(String),
    filter_level: Option(HolonLevel),
    search_query: String,
  )
}

pub type KnowledgeMsg {
  SelectNode(String)
  SetLevelFilter(Option(HolonLevel))
  SetSearch(String)
  NodesLoaded(List(KnowledgeNode), List(KnowledgeLink))
  RefreshKnowledge
}

pub fn init() -> KnowledgeModel {
  KnowledgeModel(
    nodes: [],
    links: [],
    selected_node: None,
    filter_level: None,
    search_query: "",
  )
}

pub fn update(model: KnowledgeModel, msg: KnowledgeMsg) -> KnowledgeModel {
  zenoh_otel.emit(ui_domain.Knowledge, "update", zenoh_otel.Act)
  case msg {
    SelectNode(id) -> KnowledgeModel(..model, selected_node: Some(id))
    SetLevelFilter(level) -> KnowledgeModel(..model, filter_level: level)
    SetSearch(q) -> KnowledgeModel(..model, search_query: q)
    NodesLoaded(nodes, links) ->
      KnowledgeModel(..model, nodes: nodes, links: links)
    RefreshKnowledge -> model
  }
}

pub fn filtered_nodes(model: KnowledgeModel) -> List(KnowledgeNode) {
  model.nodes
  |> list.filter(fn(n) {
    case model.filter_level {
      None -> True
      Some(level) -> n.level == level
    }
  })
}

pub fn node_count_by_level(nodes: List(KnowledgeNode), level: HolonLevel) -> Int {
  list.filter(nodes, fn(n) { n.level == level }) |> list.length
}
