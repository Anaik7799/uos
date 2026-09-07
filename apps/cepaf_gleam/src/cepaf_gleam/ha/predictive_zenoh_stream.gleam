//// =============================================================================
//// [UOS-HA] Predictive Zenoh Telemetry Stream & Real-Time Kalman Actor
//// =============================================================================
//// STAMP: SC-ZENOH-OTEL-001, SC-HIVE-FORECAST-001, SC-PRED-001, SC-SIL6-001
//// Connects live Zenoh pub/sub mesh topics (indrajaal/**) into the 10-layer
//// predictive Kalman and Bayesian forecasting models in real time.
////
//// Zero-Muda Purity: Pure functional Gleam OTP Actor on BEAM (SC-MUDA-001)
//// =============================================================================

import cepaf_gleam/ha/fractal_forecast.{
  type FractalLayer, type LayerForecast, LayerL0Constitutional, LayerL1Atomic,
  LayerL2Component, LayerL3Transaction, LayerL4System, LayerL5Cognitive,
  LayerL6Ecosystem, LayerL7Federation, LayerL8Mutation, LayerL9Verification,
  predict_l0_constitutional, predict_l1_atomic, predict_l2_component,
  predict_l3_transaction, predict_l4_system, predict_l5_cognitive,
  predict_l6_ecosystem, predict_l7_federation, predict_l8_mutation,
  predict_l9_verification,
}
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/string

pub type StreamMessage {
  IngestTelemetry(topic: String, payload: String)
  QueryForecast(layer: FractalLayer, reply_to: Subject(LayerForecast))
  QueryAllForecasts(reply_to: Subject(List(LayerForecast)))
}

pub type StreamState {
  StreamState(
    l0_buffer: List(Float),
    l1_buffer: List(Float),
    l2_buffer: List(Float),
    l3_buffer: List(Float),
    l4_buffer: List(Float),
    l5_buffer: List(Float),
    l6_buffer: List(Float),
    l7_buffer: List(Float),
    l8_buffer: List(Float),
    l9_buffer: List(Float),
    total_messages: Int,
  )
}

pub fn initial_state() -> StreamState {
  StreamState(
    l0_buffer: [0.98, 0.99, 0.97, 0.98, 0.99, 0.98, 0.99, 0.98],
    l1_buffer: [0.12, 0.14, 0.11, 0.13, 0.12, 0.15, 0.13, 0.12],
    l2_buffer: [0.55, 0.58, 0.56, 0.60, 0.62, 0.61, 0.63, 0.62],
    l3_buffer: [0.05, 0.04, 0.06, 0.05, 0.04, 0.05, 0.05, 0.04],
    l4_buffer: [0.02, 0.01, 0.03, 0.02, 0.01, 0.02, 0.02, 0.01],
    l5_buffer: [0.45, 0.48, 0.50, 0.47, 0.52, 0.49, 0.51, 0.50],
    l6_buffer: [0.15, 0.18, 0.16, 0.17, 0.19, 0.16, 0.18, 0.17],
    l7_buffer: [0.08, 0.09, 0.07, 0.08, 0.10, 0.09, 0.08, 0.09],
    l8_buffer: [0.94, 0.95, 0.93, 0.96, 0.94, 0.95, 0.96, 0.95],
    l9_buffer: [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
    total_messages: 0,
  )
}

pub fn start() -> Result(actor.Started(Subject(StreamMessage)), actor.StartError) {
  actor.new(initial_state())
  |> actor.on_message(handle_message)
  |> actor.start()
}

pub fn supervised() -> supervision.ChildSpecification(Subject(StreamMessage)) {
  supervision.worker(start)
  |> supervision.restart(supervision.Permanent)
}

pub fn update_state(state: StreamState, msg: StreamMessage) -> StreamState {
  case msg {
    IngestTelemetry(topic, payload) -> {
      let val = extract_numeric_signal(payload)
      let new_state = case map_topic_to_layer(topic) {
        Some(LayerL0Constitutional) ->
          StreamState(..state, l0_buffer: append_bounded(state.l0_buffer, val))
        Some(LayerL1Atomic) ->
          StreamState(..state, l1_buffer: append_bounded(state.l1_buffer, val))
        Some(LayerL2Component) ->
          StreamState(..state, l2_buffer: append_bounded(state.l2_buffer, val))
        Some(LayerL3Transaction) ->
          StreamState(..state, l3_buffer: append_bounded(state.l3_buffer, val))
        Some(LayerL4System) ->
          StreamState(..state, l4_buffer: append_bounded(state.l4_buffer, val))
        Some(LayerL5Cognitive) ->
          StreamState(..state, l5_buffer: append_bounded(state.l5_buffer, val))
        Some(LayerL6Ecosystem) ->
          StreamState(..state, l6_buffer: append_bounded(state.l6_buffer, val))
        Some(LayerL7Federation) ->
          StreamState(..state, l7_buffer: append_bounded(state.l7_buffer, val))
        Some(LayerL8Mutation) ->
          StreamState(..state, l8_buffer: append_bounded(state.l8_buffer, val))
        Some(LayerL9Verification) ->
          StreamState(..state, l9_buffer: append_bounded(state.l9_buffer, val))
        None -> state
      }
      StreamState(..new_state, total_messages: state.total_messages + 1)
    }
    _ -> state
  }
}

pub fn handle_message(
  state: StreamState,
  msg: StreamMessage,
) -> actor.Next(StreamState, StreamMessage) {
  case msg {
    IngestTelemetry(_, _) -> {
      let next_state = update_state(state, msg)
      actor.continue(next_state)
    }

    QueryForecast(layer, reply_to) -> {
      let forecast = compute_forecast_for_layer(state, layer, 60)
      process.send(reply_to, forecast)
      actor.continue(state)
    }

    QueryAllForecasts(reply_to) -> {
      let forecasts = [
        predict_l0_constitutional(state.l0_buffer, 60),
        predict_l1_atomic(state.l1_buffer, 60),
        predict_l2_component(state.l2_buffer, 60),
        predict_l3_transaction(state.l3_buffer, 60),
        predict_l4_system(state.l4_buffer, 60),
        predict_l5_cognitive(state.l5_buffer, 60),
        predict_l6_ecosystem(state.l6_buffer, 60),
        predict_l7_federation(state.l7_buffer, 60),
        predict_l8_mutation(state.l8_buffer, 60),
        predict_l9_verification(state.l9_buffer, 60),
      ]
      process.send(reply_to, forecasts)
      actor.continue(state)
    }
  }
}

pub fn map_topic_to_layer(topic: String) -> Option(FractalLayer) {
  case string.contains(topic, "/l0/") || string.contains(topic, "/const/") {
    True -> Some(LayerL0Constitutional)
    False ->
      case string.contains(topic, "/l1/") || string.contains(topic, "/atomic/") {
        True -> Some(LayerL1Atomic)
        False ->
          case
            string.contains(topic, "/l2/")
            || string.contains(topic, "/health/")
            || string.contains(topic, "/otel/")
          {
            True -> Some(LayerL2Component)
            False ->
              case
                string.contains(topic, "/l3/") || string.contains(topic, "/vfs/")
              {
                True -> Some(LayerL3Transaction)
                False ->
                  case
                    string.contains(topic, "/l4/")
                    || string.contains(topic, "/system/")
                  {
                    True -> Some(LayerL4System)
                    False ->
                      case
                        string.contains(topic, "/l5/")
                        || string.contains(topic, "/cog/")
                      {
                        True -> Some(LayerL5Cognitive)
                        False ->
                          case
                            string.contains(topic, "/l6/")
                            || string.contains(topic, "/zenoh/")
                          {
                            True -> Some(LayerL6Ecosystem)
                            False ->
                              case
                                string.contains(topic, "/l7/")
                                || string.contains(topic, "/federation/")
                              {
                                True -> Some(LayerL7Federation)
                                False ->
                                  case
                                    string.contains(topic, "/l8/")
                                    || string.contains(topic, "/mutation/")
                                  {
                                    True -> Some(LayerL8Mutation)
                                    False ->
                                      case
                                        string.contains(topic, "/l9/")
                                        || string.contains(topic, "/verify/")
                                      {
                                        True -> Some(LayerL9Verification)
                                        False -> None
                                      }
                                  }
                              }
                          }
                      }
                  }
              }
          }
      }
  }
}

pub fn extract_numeric_signal(payload: String) -> Float {
  case float.parse(payload) {
    Ok(val) -> clamp_signal(val)
    Error(_) ->
      case int.parse(payload) {
        Ok(i) -> clamp_signal(int.to_float(i))
        Error(_) ->
          case string.contains(payload, "CRITICAL") {
            True -> 0.10
            False ->
              case string.contains(payload, "DEGRADED") {
                True -> 0.50
                False -> 0.95
              }
          }
      }
  }
}

pub fn compute_forecast_for_layer(
  state: StreamState,
  layer: FractalLayer,
  horizon_s: Int,
) -> LayerForecast {
  case layer {
    LayerL0Constitutional ->
      predict_l0_constitutional(state.l0_buffer, horizon_s)
    LayerL1Atomic -> predict_l1_atomic(state.l1_buffer, horizon_s)
    LayerL2Component -> predict_l2_component(state.l2_buffer, horizon_s)
    LayerL3Transaction -> predict_l3_transaction(state.l3_buffer, horizon_s)
    LayerL4System -> predict_l4_system(state.l4_buffer, horizon_s)
    LayerL5Cognitive -> predict_l5_cognitive(state.l5_buffer, horizon_s)
    LayerL6Ecosystem -> predict_l6_ecosystem(state.l6_buffer, horizon_s)
    LayerL7Federation -> predict_l7_federation(state.l7_buffer, horizon_s)
    LayerL8Mutation -> predict_l8_mutation(state.l8_buffer, horizon_s)
    LayerL9Verification -> predict_l9_verification(state.l9_buffer, horizon_s)
  }
}

fn append_bounded(buffer: List(Float), value: Float) -> List(Float) {
  let updated = list.append(buffer, [value])
  case list.length(updated) > 16 {
    True -> list.drop(updated, 1)
    False -> updated
  }
}

fn clamp_signal(v: Float) -> Float {
  case v <. 0.0 {
    True -> 0.0
    False ->
      case v >. 1.0 && v <=. 100.0 {
        True -> v /. 100.0
        False ->
          case v >. 100.0 {
            True -> 1.0
            False -> v
          }
      }
  }
}
