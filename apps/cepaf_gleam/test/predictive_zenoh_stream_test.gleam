// =============================================================================
// [UOS-HA] Predictive Zenoh Telemetry Stream Actor Tests
// =============================================================================
// STAMP: SC-ZENOH-OTEL-001, SC-HIVE-FORECAST-001, SC-PRED-001, SC-SIL6-001
// Zero-Muda Purity: Pure functional Gleam OTP Actor on BEAM (SC-MUDA-001)
// =============================================================================

import cepaf_gleam/ha/fractal_forecast.{
  LayerL0Constitutional, LayerL1Atomic, LayerL2Component, LayerL3Transaction,
  LayerL4System, LayerL5Cognitive, LayerL6Ecosystem, LayerL7Federation,
  LayerL8Mutation, LayerL9Verification,
}
import cepaf_gleam/ha/predictive_zenoh_stream as pzs
import gleam/erlang/process
import gleam/list
import gleam/option.{Some}
import gleeunit/should

pub fn stream_initial_state_test() {
  let state = pzs.initial_state()
  state.total_messages |> should.equal(0)
  list.length(state.l0_buffer) |> should.equal(8)
  list.length(state.l1_buffer) |> should.equal(8)
  list.length(state.l2_buffer) |> should.equal(8)
  list.length(state.l3_buffer) |> should.equal(8)
  list.length(state.l4_buffer) |> should.equal(8)
  list.length(state.l5_buffer) |> should.equal(8)
  list.length(state.l6_buffer) |> should.equal(8)
  list.length(state.l7_buffer) |> should.equal(8)
  list.length(state.l8_buffer) |> should.equal(8)
  list.length(state.l9_buffer) |> should.equal(8)
}

pub fn stream_topic_mapping_test() {
  pzs.map_topic_to_layer("indrajaal/l0/const/health")
  |> should.equal(Some(LayerL0Constitutional))

  pzs.map_topic_to_layer("indrajaal/l1/atomic/sensor")
  |> should.equal(Some(LayerL1Atomic))

  pzs.map_topic_to_layer("indrajaal/l2/component/util")
  |> should.equal(Some(LayerL2Component))

  pzs.map_topic_to_layer("indrajaal/l3/transaction/lock")
  |> should.equal(Some(LayerL3Transaction))

  pzs.map_topic_to_layer("indrajaal/l4/system/mtbf")
  |> should.equal(Some(LayerL4System))

  pzs.map_topic_to_layer("indrajaal/l5/cog/fuel")
  |> should.equal(Some(LayerL5Cognitive))

  pzs.map_topic_to_layer("indrajaal/l6/ecosystem/peers")
  |> should.equal(Some(LayerL6Ecosystem))

  pzs.map_topic_to_layer("indrajaal/l7/federation/lag")
  |> should.equal(Some(LayerL7Federation))

  pzs.map_topic_to_layer("indrajaal/l8/mutation/kill")
  |> should.equal(Some(LayerL8Mutation))

  pzs.map_topic_to_layer("indrajaal/l9/verification/solver")
  |> should.equal(Some(LayerL9Verification))
}

pub fn stream_state_update_test() {
  let state = pzs.initial_state()
  let msg =
    pzs.IngestTelemetry("indrajaal/l0/const/health", "{\"health\": 0.995}")
  let updated = pzs.update_state(state, msg)

  updated.total_messages |> should.equal(1)
  list.length(updated.l0_buffer) |> should.equal(9)
}

pub fn stream_actor_start_and_query_test() {
  case pzs.start() {
    Ok(started) -> {
      let client = started.data

      // Ingest live telemetry
      process.send(
        client,
        pzs.IngestTelemetry("indrajaal/l0/const/health", "{\"health\": 0.985}"),
      )

      // Query single layer
      let reply_single = process.new_subject()
      process.send(client, pzs.QueryForecast(LayerL0Constitutional, reply_single))
      let forecast = process.receive_forever(reply_single)
      forecast.layer |> should.equal(LayerL0Constitutional)

      // Query all layers
      let reply_all = process.new_subject()
      process.send(client, pzs.QueryAllForecasts(reply_all))
      let all_forecasts = process.receive_forever(reply_all)
      list.length(all_forecasts) |> should.equal(10)
    }
    Error(_) -> panic as "failed to start predictive zenoh stream actor"
  }
}
