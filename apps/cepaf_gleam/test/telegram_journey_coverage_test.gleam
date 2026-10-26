//// SC-TELEGRAM-JOURNEY-001 coverage: every catalog literal appears in at
//// least one operator journey (security, defence, critical responder) with a
//// behavioural expectation, and every journey literal exists in the catalog.
//// A literal with no journey is a command nobody has described how to use
//// truthfully. Review C-14 and C-15 (wave 6k) tightened both laws: tombstone
//// steps do not count as coverage, and the plain-message law asserts the
//// preview or denial status the adapters really produce.

import cepaf_gleam/harness/telegram_action_adapters as action_adapters
import cepaf_gleam/harness/telegram_commands as commands
import cepaf_gleam/harness/telegram_ingress_guard as guard
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import gleam/string
import gleeunit/should
import telegram_journey_defence_test as defence
import telegram_journey_responder_test as responder
import telegram_journey_security_test as security

fn catalog_literals() -> List(String) {
  commands.catalog() |> list.map(fn(d) { d.literal })
}

fn journey_literals() -> List(String) {
  list.flatten([
    security.covered_literals(),
    defence.covered_literals(),
    responder.covered_literals(),
  ])
  |> list.unique
}

pub fn every_catalog_literal_has_a_journey_step_test() {
  let covered = set.from_list(journey_literals())
  let missing =
    catalog_literals()
    |> list.filter(fn(l) { !set.contains(covered, l) })
    |> list.sort(string.compare)
  missing |> should.equal([])
  list.length(catalog_literals()) |> should.equal(77)
}

pub fn every_journey_literal_exists_in_the_catalog_test() {
  let catalog = set.from_list(catalog_literals())
  journey_literals()
  |> list.filter(fn(l) { !set.contains(catalog, l) })
  |> should.equal([])
}

fn status_of(reply: String) -> String {
  case
    json.parse(reply, {
      use status <- decode.field("status", decode.string)
      decode.success(status)
    })
  {
    Ok(status) -> status
    Error(_) -> "MISSING_STATUS"
  }
}

/// Service-owned ControlledAction names: no adapter claims them, and the
/// service runs them only through their own gates (signed verify packet,
/// approval ledger, tool cancellation, zigvm read).
const service_owned = [
  "/verify", "/verification", "/approval", "/approval_manage", "/tool",
  "/tool_help", "/cancel_job_lease", "/zigvm",
]

/// Every ControlledAction literal, with several argument shapes, either
/// previews through an adapter with a non-executing status, is denied at
/// classify, or is preserved for a service-owned arm. Nothing a journey can
/// type yields `ok`, `executed` or `duplicate` from a plain message.
pub fn journeys_never_expect_execution_from_a_plain_message_test() {
  let shapes = [
    "",
    " x",
    " {}",
    " " <> string.repeat("a", 2000),
    " x\u{0}y\nz",
  ]
  commands.catalog()
  |> list.filter(fn(d) { d.kind == commands.ControlledAction })
  |> list.each(fn(d) {
    list.each(shapes, fn(shape) {
      let text = d.literal <> shape
      case guard.classify_directive(text) {
        guard.DeniedMutation(_, _) -> Nil
        guard.DirectReadTool(_) -> Nil
        guard.UnknownDirective(_) ->
          should.equal(#(text, "classified"), #(text, "UnknownDirective"))
        guard.PreservedDirective(name, args) ->
          case action_adapters.route_preview(name, args) {
            Some(reply) -> {
              let status = status_of(reply)
              should.equal(
                #(
                  d.literal,
                  shape,
                  list.contains(
                    [
                      "preview",
                      "denied",
                      "backend_unavailable",
                      "approval_required",
                    ],
                    status,
                  ),
                ),
                #(d.literal, shape, True),
              )
            }
            None ->
              should.equal(
                #(d.literal, shape, list.contains(service_owned, name)),
                #(d.literal, shape, True),
              )
          }
      }
    })
  })
}
