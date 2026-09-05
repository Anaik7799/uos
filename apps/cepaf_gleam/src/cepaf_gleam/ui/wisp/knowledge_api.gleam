/// Wisp API for Knowledge (Smriti) plane (SC-GLM-UI-001, SC-GLM-UI-003).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-007
import cepaf_gleam/knowledge/domain.{
  type KnowledgeLink, type KnowledgeNode, level_to_string, rhetorical_to_string,
}
import gleam/json
import gleam/list

pub fn knowledge_graph_json(
  nodes: List(KnowledgeNode),
  links: List(KnowledgeLink),
) -> String {
  json.object([
    #("plane", json.string("knowledge")),
    #("node_count", json.int(list.length(nodes))),
    #("link_count", json.int(list.length(links))),
    #("nodes", json.array(nodes, encode_node)),
    #("links", json.array(links, encode_link)),
  ])
  |> json.to_string()
}

pub fn node_detail_json(node: KnowledgeNode) -> String {
  json.object([
    #("plane", json.string("knowledge")),
    #("node", encode_node(node)),
  ])
  |> json.to_string()
}

fn encode_node(node: KnowledgeNode) -> json.Json {
  json.object([
    #("id", json.string(node.id)),
    #("title", json.string(node.title)),
    #("level", json.string(level_to_string(node.level))),
    #("rhetorical", json.string(rhetorical_to_string(node.rhetorical))),
    #("entropy", json.float(node.entropy)),
    #("drift", json.float(node.drift)),
    #("tags", json.array(node.tags, json.string)),
  ])
}

fn encode_link(link: KnowledgeLink) -> json.Json {
  json.object([
    #("source_id", json.string(link.source_id)),
    #("target_id", json.string(link.target_id)),
    #("relation_type", json.string(link.relation_type)),
  ])
}
