//// Router from a ControlledAction literal to its adapter's read-only preview.
//// This is the only entry the Telegram service may call for these literals
//// until the signed approval flow is extended to call `execute`: a preview
//// reads real state and says what WOULD change; it mutates nothing and grants
//// nothing. Each adapter follows docs/design/20261026-0115 (parse, effect_id,
//// preview, execute). `execute` is deliberately not reachable from here.
//// Waves 2 and 3 (21 literals); /verify stays with the executor path.

import cepaf_gleam/harness/telegram_action_andon as andon
import cepaf_gleam/harness/telegram_action_bisect as bisect
import cepaf_gleam/harness/telegram_action_chaos as chaos
import cepaf_gleam/harness/telegram_action_commitments as commitments
import cepaf_gleam/harness/telegram_action_dark as dark
import cepaf_gleam/harness/telegram_action_eco_schedule as eco_schedule
import cepaf_gleam/harness/telegram_action_escalate as escalate
import cepaf_gleam/harness/telegram_action_export_audit as export_audit
import cepaf_gleam/harness/telegram_action_gameday as gameday
import cepaf_gleam/harness/telegram_action_handover as handover
import cepaf_gleam/harness/telegram_action_lockbox as lockbox
import cepaf_gleam/harness/telegram_action_merge as merge
import cepaf_gleam/harness/telegram_action_migrate as migrate
import cepaf_gleam/harness/telegram_action_pair_voice as pair_voice
import cepaf_gleam/harness/telegram_action_repro as repro
import cepaf_gleam/harness/telegram_action_resuscitate as resuscitate
import cepaf_gleam/harness/telegram_action_rewind as rewind
import cepaf_gleam/harness/telegram_action_rotate_keys as rotate_keys
import cepaf_gleam/harness/telegram_action_sidecar as sidecar
import cepaf_gleam/harness/telegram_action_voice_roll_call as voice_roll_call
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
    rotate_keys.literal(),
    lockbox.literal(),
    migrate.literal(),
    escalate.literal(),
    resuscitate.literal(),
    repro.literal(),
    merge.literal(),
    bisect.literal(),
    rewind.literal(),
    commitments.literal(),
    eco_schedule.literal(),
    sidecar.literal(),
    voice_roll_call.literal(),
    pair_voice.literal(),
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
    "/rotate-keys" ->
      Some(preview(name, rotate_keys.parse(text), rotate_keys.preview))
    "/lockbox" -> Some(preview(name, lockbox.parse(text), lockbox.preview))
    "/migrate" -> Some(preview(name, migrate.parse(text), migrate.preview))
    "/escalate" -> Some(preview(name, escalate.parse(text), escalate.preview))
    "/resuscitate" ->
      Some(preview(name, resuscitate.parse(text), resuscitate.preview))
    "/repro" -> Some(preview(name, repro.parse(text), repro.preview))
    "/merge" -> Some(preview(name, merge.parse(text), merge.preview))
    "/bisect" -> Some(preview(name, bisect.parse(text), bisect.preview))
    "/rewind" -> Some(preview(name, rewind.parse(text), rewind.preview))
    "/commitments" ->
      Some(preview(name, commitments.parse(text), commitments.preview))
    "/eco-schedule" ->
      Some(preview(name, eco_schedule.parse(text), eco_schedule.preview))
    "/sidecar" -> Some(preview(name, sidecar.parse(text), sidecar.preview))
    "/voice-roll-call" ->
      Some(preview(name, voice_roll_call.parse(text), voice_roll_call.preview))
    "/pair-voice" ->
      Some(preview(name, pair_voice.parse(text), pair_voice.preview))
    // "/verification" is a catalog alias of "/verify" and stays on the
    // executor path; telegram_action_verification is kept for a later
    // "/verify status" surface and is not routed here.
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
