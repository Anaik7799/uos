//// Router from a ControlledAction literal to its adapter's read-only preview.
//// This is the only entry the Telegram service may call for these literals
//// until the signed approval flow is extended to call `execute`: a preview
//// reads real state and says what WOULD change; it mutates nothing and grants
//// nothing. Each adapter follows docs/design/20261026-0115 (parse, effect_id,
//// preview, execute). `execute` is deliberately not reachable from here.

import cepaf_gleam/harness/telegram_action_andon as andon
import cepaf_gleam/harness/telegram_action_chaos as chaos
import cepaf_gleam/harness/telegram_action_dark as dark
import cepaf_gleam/harness/telegram_action_export_audit as export_audit
import cepaf_gleam/harness/telegram_action_gameday as gameday
import cepaf_gleam/harness/telegram_action_handover as handover
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string

pub fn literals() -> List(String) {
  [
    andon.literal(),
    dark.literal(),
    chaos.literal(),
    gameday.literal(),
    export_audit.literal(),
    handover.literal(),
  ]
}

fn denied(command: String, reason: String) -> String {
  json.object([
    #("status", json.string("denied")),
    #("command", json.string(command)),
    #("reason", json.string(reason)),
  ])
  |> json.to_string
}

/// Preview reply for a ControlledAction literal, or None when no adapter owns
/// it. A parse failure is a typed denial carrying the adapter's usage text.
pub fn route_preview(name: String, args: List(String)) -> Option(String) {
  let text = string.join(args, " ")
  case name {
    "/andon" -> Some(preview(name, andon.parse(text), andon.preview))
    "/dark" -> Some(preview(name, dark.parse(text), dark.preview))
    "/chaos" -> Some(preview(name, chaos.parse(text), chaos.preview))
    "/gameday" -> Some(preview(name, gameday.parse(text), gameday.preview))
    "/export-audit" ->
      Some(preview(name, export_audit.parse(text), export_audit.preview))
    "/handover" -> Some(preview(name, handover.parse(text), handover.preview))
    _ -> None
  }
}

fn preview(
  name: String,
  parsed: Result(r, String),
  show: fn(r) -> String,
) -> String {
  case parsed {
    Ok(request) -> show(request)
    Error(usage) -> denied(name, usage)
  }
}
