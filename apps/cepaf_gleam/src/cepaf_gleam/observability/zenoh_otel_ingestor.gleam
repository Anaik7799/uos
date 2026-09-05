// STAMP: SC-ZENOH-OTEL-001, SC-OBS-001, SC-SIL6-001, SC-CIRCUIT-001
// AOR: AOR-GLM-001
// Criticality: Level 2 (HIGH) - Zenoh OTel Ingestor & L2_Immune Circuit Breaker

import cepaf_gleam/prajna/circuit_breaker.{BreakerOpen}
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/otp/actor
import gleam/string

pub const span_topic_prefix = "indrajaal/otel/spans/"

pub type Message {
  ZenohMessage(topic: String, payload: String)
}

pub type State {
  State(breaker: circuit_breaker.Breaker, span_count: Int)
}

pub fn start() -> Result(actor.Started(Subject(Message)), actor.StartError) {
  let initial_breaker = circuit_breaker.create("L2_Immune_OTel", 5, 3, 10_000)

  actor.new(State(breaker: initial_breaker, span_count: 0))
  |> actor.on_message(handle_message)
  |> actor.start()
}

fn handle_message(state: State, msg: Message) -> actor.Next(State, Message) {
  let current_time = now_ms()
  let breaker_checked =
    circuit_breaker.attempt_half_open(state.breaker, current_time)

  case circuit_breaker.is_allowed(breaker_checked) {
    False -> {
      io.println(
        "L2_Immune: Circuit Open! Dropping telemetry. Escalating to L5_Operator.",
      )
      actor.continue(State(..state, breaker: breaker_checked))
    }
    True -> {
      case msg {
        ZenohMessage(_topic, payload) -> {
          let is_fema_critical = string.contains(payload, "CRITICAL")

          case is_fema_critical {
            True -> {
              io.println(
                "L2_Immune: FEMA Tensor > 100 detected. Recording failure.",
              )
              let tripped_breaker =
                circuit_breaker.record_failure(breaker_checked, current_time)

              case tripped_breaker.state {
                BreakerOpen(_) ->
                  io.println(
                    "L2_Immune: CIRCUIT TRIPPED! V_dot(x) < 0 constraint activated.",
                  )
                _ -> Nil
              }
              actor.continue(State(..state, breaker: tripped_breaker))
            }
            False -> {
              let success_breaker =
                circuit_breaker.record_success(breaker_checked)
              actor.continue(State(
                breaker: success_breaker,
                span_count: state.span_count + 1,
              ))
            }
          }
        }
      }
    }
  }
}

pub fn receive_zenoh_message(
  subject: Subject(Message),
  topic: String,
  payload: String,
) {
  process.send(subject, ZenohMessage(topic, payload))
}

@external(erlang, "os", "system_time")
fn system_time_millis() -> Int

fn now_ms() -> Int {
  system_time_millis()
}
