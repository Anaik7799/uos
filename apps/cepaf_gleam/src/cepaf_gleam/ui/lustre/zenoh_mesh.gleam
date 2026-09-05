/// Lustre component for Zenoh Mesh plane (SC-GLM-UI-001).
/// Subscribes to Zenoh PubSub for real-time updates (SC-GLM-UI-005).
/// Imports from zenoh/domain.gleam — no type duplication (SC-GLM-UI-009).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-005, SC-GLM-UI-009
import cepaf_gleam/ui/domain as ui_domain
import cepaf_gleam/ui/zenoh_otel
import cepaf_gleam/zenoh/domain.{
  type LifecycleState, type ZenohHealth, Connected, empty_health,
}
import gleam/list

pub type ZenohModel {
  ZenohModel(
    health: ZenohHealth,
    lifecycle: LifecycleState,
    subscriptions: List(String),
    message_log: List(MessageEntry),
  )
}

pub type MessageEntry {
  MessageEntry(key: String, size: Int, timestamp: Int)
}

pub type ZenohMsg {
  HealthUpdated(ZenohHealth)
  LifecycleChanged(LifecycleState)
  MessageReceived(key: String, size: Int, timestamp: Int)
  SubscriptionAdded(topic: String)
  SubscriptionRemoved(topic: String)
  RefreshZenoh
}

pub fn init() -> ZenohModel {
  ZenohModel(
    health: empty_health(),
    lifecycle: domain.Uninitialized,
    subscriptions: [],
    message_log: [],
  )
}

pub fn update(model: ZenohModel, msg: ZenohMsg) -> ZenohModel {
  zenoh_otel.emit(ui_domain.Zenoh, "update", zenoh_otel.Act)
  case msg {
    HealthUpdated(h) -> ZenohModel(..model, health: h)
    LifecycleChanged(s) -> ZenohModel(..model, lifecycle: s)
    MessageReceived(key, size, ts) ->
      ZenohModel(..model, message_log: [
        MessageEntry(key, size, ts),
        ..model.message_log
      ])
    SubscriptionAdded(topic) ->
      ZenohModel(..model, subscriptions: [topic, ..model.subscriptions])
    SubscriptionRemoved(topic) ->
      ZenohModel(
        ..model,
        subscriptions: list.filter(model.subscriptions, fn(s) { s != topic }),
      )
    RefreshZenoh -> model
  }
}

pub fn is_connected(model: ZenohModel) -> Bool {
  model.health.status == Connected
}

pub fn message_rate(model: ZenohModel) -> Int {
  model.health.messages_published + model.health.messages_received
}
