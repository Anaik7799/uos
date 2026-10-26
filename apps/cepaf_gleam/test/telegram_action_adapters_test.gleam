import cepaf_gleam/harness/telegram_action_adapters as actions
import cepaf_gleam/harness/telegram_ingress_guard as guard
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

const wave_two = [
  "/andon", "/dark", "/chaos", "/gameday", "/export-audit", "/handover",
  "/rotate-keys", "/lockbox", "/migrate", "/escalate", "/resuscitate", "/repro",
  "/merge", "/bisect", "/rewind", "/commitments", "/eco-schedule", "/sidecar",
  "/pair-voice",
]

fn status_of(reply: String) -> String {
  let assert Ok(s) =
    json.parse(reply, {
      use s <- decode.field("status", decode.string)
      decode.success(s)
    })
  s
}

pub fn every_wave_two_literal_previews_or_denies_test() {
  list.sort(actions.literals(), string.compare)
  |> should.equal(list.sort(wave_two, string.compare))
  list.each(wave_two, fn(name) {
    let assert Some(reply) = actions.route_preview(name, [])
    // Read-only outcomes only: a preview cannot report an execution.
    list.contains(
      ["preview", "denied", "backend_unavailable"],
      status_of(reply),
    )
    |> should.be_true
    { string.byte_size(reply) <= 3500 } |> should.be_true
  })
}

pub fn router_never_reports_executed_test() {
  list.each(wave_two, fn(name) {
    list.each([[], ["dark"], ["x", "y"], ["modular_max", "serious"]], fn(args) {
      case actions.route_preview(name, args) {
        Some(reply) ->
          { status_of(reply) != "executed" && status_of(reply) != "duplicate" }
          |> should.be_true
        None -> should.fail()
      }
    })
  })
}

pub fn foreign_literals_fall_through_test() {
  actions.route_preview("/verify", []) |> should.equal(None)
  // Catalog alias of /verify: never previewed here.
  actions.route_preview("/verification", []) |> should.equal(None)
  actions.route_preview("/task", ["X"]) |> should.equal(None)
}

pub fn classify_preserves_wave_two_actions_and_still_denies_others_test() {
  list.each(wave_two, fn(name) {
    case guard.classify_directive(name <> " dark") {
      guard.PreservedDirective(n, _) -> n |> should.equal(name)
      _ -> should.fail()
    }
  })
  // /verify and its alias are preserved for the service's VerifyDispatch
  // (signed packet executes; otherwise a truthful not-configured reply). No
  // adapter owns them, so nothing previews or executes from this text.
  case guard.classify_directive("/verify telegram-core") {
    guard.PreservedDirective("/verify", ["telegram-core"]) -> Nil
    _ -> should.fail()
  }
  case guard.classify_directive("/verification now") {
    guard.PreservedDirective("/verify", ["now"]) -> Nil
    _ -> should.fail()
  }
  actions.route_preview("/verify", ["telegram-core"]) |> should.equal(None)
  // Adopted media design T0: the biometric arm is denied at classify.
  case guard.classify_directive("/voice-roll-call all") {
    guard.DeniedMutation("/voice-roll-call", _) -> Nil
    _ -> should.fail()
  }
  actions.route_preview("/voice-roll-call", []) |> should.equal(None)
}
