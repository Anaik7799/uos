//// Router from a preserved read directive to its adapter module. Adapters
//// either observe a real backend or answer a typed backend_unavailable that
//// names the missing backend; the router adds nothing and never synthesises a
//// reply. A literal outside every adapter's set returns None so the service
//// keeps its existing fallthrough. Wave-1 adapters were built in parallel
//// workspaces and are wired here serially (journal 20261026-0049).

import cepaf_gleam/harness/telegram_knowledge_read_command as knowledge
import cepaf_gleam/harness/telegram_simulation_read_command as simulation
import cepaf_gleam/harness/telegram_system_read_command as system
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// Every literal some adapter answers for.
pub fn literals() -> List(String) {
  list.flatten([system.literals(), knowledge.literals(), simulation.literals()])
}

pub fn route(name: String, args: List(String)) -> Option(String) {
  let text = string.join(args, " ")
  case list.contains(system.literals(), name) {
    True -> Some(system.handle(name, text))
    False ->
      case list.contains(knowledge.literals(), name) {
        True -> Some(knowledge.handle(name, text))
        False ->
          case list.contains(simulation.literals(), name) {
            True -> Some(simulation.handle(name, text))
            False -> None
          }
      }
  }
}
