// STAMP: SC-GLM-UI-001, SC-ZENOH-001
import cepaf_gleam/ui/lustre/zenoh_browser.{type ZenohBrowserModel}
import gleam/json
import gleam/list
import gleam/option.{None, Some}

pub fn status_json(model: ZenohBrowserModel) -> json.Json {
  json.object([
    #("total_topics", json.int(zenoh_browser.total_topics(model))),
    #("selected", case model.selected_topic {
      Some(t) -> json.string(t)
      None -> json.null()
    }),
    #("last_message", json.string(model.last_message)),
    #("subscribed_count", json.int(list.length(model.subscribed))),
  ])
}
