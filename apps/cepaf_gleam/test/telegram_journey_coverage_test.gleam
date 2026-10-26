//// SC-TELEGRAM-JOURNEY-001 coverage: every catalog literal appears in at
//// least one operator journey (security, defence, critical responder), and
//// every journey literal exists in the catalog. A literal with no journey is a
//// command nobody has described how to use truthfully.

import cepaf_gleam/harness/telegram_commands as commands
import cepaf_gleam/harness/telegram_ingress_guard as guard
import gleam/list
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

pub fn journeys_never_expect_execution_from_a_plain_message_test() {
  // Every ControlledAction literal classifies to a preview (preserved) or a
  // denial; nothing a journey can type executes an effect directly.
  commands.catalog()
  |> list.filter(fn(d) { d.kind == commands.ControlledAction })
  |> list.each(fn(d) {
    case guard.classify_directive(d.literal <> " x") {
      guard.PreservedDirective(_, _) -> Nil
      guard.DeniedMutation(_, _) -> Nil
      guard.DirectReadTool(_) -> Nil
      guard.UnknownDirective(_) -> should.fail()
    }
  })
}
