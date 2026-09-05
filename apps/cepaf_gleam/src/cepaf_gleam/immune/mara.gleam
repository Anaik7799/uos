import cepaf_gleam/immune/domain.{
  type ChaosAttack, ContainerAssault, HeartbeatSabotage, ResourceDrain,
  ZenohFlood,
}
import cepaf_gleam/telemetry/otel
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/option.{None}
import gleam/otp/actor
import gleam/result

pub type MaraConfig {
  MaraConfig(
    is_enabled: Bool,
    chaos_level: Float,
    protected_containers: List(String),
  )
}

pub type Message {
  Strike
  SetEnabled(Bool)
  Shutdown
}

pub fn start(config: MaraConfig) -> Result(Subject(Message), actor.StartError) {
  actor.new(config)
  |> actor.on_message(handle_message)
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

fn handle_message(
  config: MaraConfig,
  message: Message,
) -> actor.Next(MaraConfig, Message) {
  case message {
    SetEnabled(val) -> actor.continue(MaraConfig(..config, is_enabled: val))
    Strike -> {
      let tags = dict.from_list([#("actor", "mara"), #("action", "strike")])
      otel.start_span(["cepaf", "immune", "mara"], tags, None)

      case config.is_enabled {
        True -> {
          let attack = select_random_attack()
          execute_attack(attack, config)

          otel.stop_span(["cepaf", "immune", "mara"], 1.5, tags, None)
          actor.continue(config)
        }
        False -> {
          io.println_error("[MARA] Strike blocked: Agent disabled for safety.")

          otel.error_span(
            ["cepaf", "immune", "mara"],
            0.1,
            "agent_disabled",
            tags,
            None,
          )
          actor.continue(config)
        }
      }
    }
    Shutdown -> actor.stop()
  }
}

fn select_random_attack() -> ChaosAttack {
  let val = int.random(4)
  case val {
    0 -> ContainerAssault("indrajaal-ex-app-2", "restart")
    1 -> ZenohFlood("indrajaal/safety/alerts", 1000)
    2 -> HeartbeatSabotage("cortex-synapse")
    _ -> ResourceDrain(80, 5000)
  }
}

fn execute_attack(attack: ChaosAttack, config: MaraConfig) {
  case attack {
    ContainerAssault(name, mode) -> {
      case list_contains(config.protected_containers, name) {
        True ->
          io.println_error(
            "[MARA] Assault rejected: " <> name <> " is PROTECTED.",
          )
        False ->
          io.println("[MARA] ASSAULT: Target=" <> name <> " Mode=" <> mode)
      }
    }
    _ -> io.println("[MARA] Executing non-deterministic attack pattern.")
  }
}

fn list_contains(items: List(String), target: String) -> Bool {
  case items {
    [] -> False
    [x, ..rest] -> {
      case x == target {
        True -> True
        False -> list_contains(rest, target)
      }
    }
  }
}
