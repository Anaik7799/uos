//// [C3I-SIL6-MSTS] Zenoh topic namespace browser. STAMP: SC-GLM-UI-001, SC-ZENOH-001

import gleam/list
import gleam/option.{type Option, None, Some}

pub type TopicNode { TopicNode(path: String, message_count: Int, children: List(TopicNode)) }

pub type ZenohBrowserModel {
  ZenohBrowserModel(root: List(TopicNode), selected_topic: Option(String),
    last_message: String, subscribed: List(String), loading: Bool, error: Option(String))
}

pub type ZenohBrowserMsg {
  TopicsLoaded(List(TopicNode))
  SelectTopic(String)
  MessageReceived(String, String)
  SubscribeTopic(String)
  UnsubscribeTopic(String)
  RefreshTopics
  ErrorReceived(String)
}

pub fn init() -> ZenohBrowserModel {
  ZenohBrowserModel(root: [], selected_topic: None, last_message: "",
    subscribed: [], loading: False, error: None)
}

pub fn update(model: ZenohBrowserModel, msg: ZenohBrowserMsg) -> ZenohBrowserModel {
  case msg {
    TopicsLoaded(nodes) -> ZenohBrowserModel(..model, root: nodes, loading: False)
    SelectTopic(t) -> ZenohBrowserModel(..model, selected_topic: Some(t))
    MessageReceived(_topic, msg_text) -> ZenohBrowserModel(..model, last_message: msg_text)
    SubscribeTopic(t) -> ZenohBrowserModel(..model, subscribed: [t, ..model.subscribed])
    UnsubscribeTopic(t) -> ZenohBrowserModel(..model, subscribed: list.filter(model.subscribed, fn(s) { s != t }))
    RefreshTopics -> ZenohBrowserModel(..model, loading: True)
    ErrorReceived(e) -> ZenohBrowserModel(..model, error: Some(e), loading: False)
  }
}

pub fn total_topics(model: ZenohBrowserModel) -> Int { count_nodes(model.root) }
fn count_nodes(nodes: List(TopicNode)) -> Int {
  list.fold(nodes, 0, fn(acc, n) { acc + 1 + count_nodes(n.children) })
}
