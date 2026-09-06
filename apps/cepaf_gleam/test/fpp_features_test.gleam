//// =============================================================================
//// [UOS-FPP-FEATURES-TEST] NASA JPL F Prime Full Features Test Suite in Gleam
//// =============================================================================
//// Tests the complete F Prime feature set implemented in BEAM/Gleam:
//// 1. Parameter Database Actor (Svc::PrmDb) lifecycle & persistence
//// 2. Telemetry Packetizer packing & JSON downlink serialization
//// 3. Subtopology composition and exported boundary port interfaces
//// 4. NASA JPL Ground Dictionary JSON specification emission
//// =============================================================================

import cepaf_gleam/fpp/dictionary.{generate_ground_dictionary_json}
import cepaf_gleam/fpp/domain.{TlmPacket}
import cepaf_gleam/fpp/packetizer.{pack_telemetry, serialize_packet_json}
import cepaf_gleam/fpp/prm_db.{
  DumpAll, GetParam, SaveParams, SetParam, Shutdown, start as start_prm_db,
}
import cepaf_gleam/fpp/topology.{canonical_harness_model}
import gleam/erlang/process
import gleam/list
import gleam/string
import gleeunit/should

// --------------------------------------------- 1. Parameter Database Actor

pub fn prm_db_actor_lifecycle_test() {
  let initial = [#(101, "42"), #(102, "nominal")]
  let start_res = start_prm_db(initial)
  start_res |> should.be_ok

  let assert Ok(started) = start_res
  let client = started.data

  // Query existing parameter
  let val101 = process.call(client, 1000, fn(reply) { GetParam(101, reply) })
  val101 |> should.equal(Ok("42"))

  // Query missing parameter
  let val999 = process.call(client, 1000, fn(reply) { GetParam(999, reply) })
  val999 |> should.be_error

  // Update parameter
  let set_res =
    process.call(client, 1000, fn(reply) { SetParam(101, "99", reply) })
  set_res |> should.equal(Ok(Nil))

  // Verify updated value
  let val101_updated =
    process.call(client, 1000, fn(reply) { GetParam(101, reply) })
  val101_updated |> should.equal(Ok("99"))

  // Dump all parameters
  let all_params = process.call(client, 1000, fn(reply) { DumpAll(reply) })
  let dumped_101 = list.key_find(all_params, 101)
  dumped_101 |> should.equal(Ok("99"))

  let dumped_102 = list.key_find(all_params, 102)
  dumped_102 |> should.equal(Ok("nominal"))

  // Save parameters
  let save_res = process.call(client, 1000, fn(reply) { SaveParams(reply) })
  save_res |> should.equal(Ok(2))

  // Shutdown cleanly
  process.send(client, Shutdown)
}

// ---------------------------------------------------- 2. Telemetry Packetizer

pub fn packetizer_pack_and_serialize_test() {
  let packet =
    TlmPacket(
      packet_id: 1,
      packet_name: "HealthPkt",
      channel_ids: [10, 20],
      level: 1,
    )

  let available_ok = [#(10, "3.14"), #(20, "100.0"), #(30, "ignored")]
  let pack_res = pack_telemetry(packet, available_ok)
  pack_res |> should.be_ok

  let assert Ok(packed) = pack_res
  packed.packet_id |> should.equal(1)
  packed.packet_name |> should.equal("HealthPkt")
  packed.channels |> should.equal([#(10, "3.14"), #(20, "100.0")])

  // Serialize to JSON and verify contents
  let json_str = serialize_packet_json(packed)
  json_str |> string.contains("\"packet_id\":1") |> should.be_true
  json_str |> string.contains("\"packet_name\":\"HealthPkt\"") |> should.be_true
  json_str |> string.contains("\"channel_id\":10") |> should.be_true
  json_str |> string.contains("\"channel_id\":20") |> should.be_true

  // Test missing channel error
  let available_missing = [#(10, "3.14")]
  let err_res = pack_telemetry(packet, available_missing)
  err_res |> should.be_error
}

// -------------------------------- 3. Subtopology & Exported Ports

pub fn subtopology_and_exported_ports_test() {
  let model = canonical_harness_model()
  list.length(model.subtopologies) |> should.equal(1)

  let assert [subtopo] = model.subtopologies
  subtopo.name |> should.equal("EvidencePipelineSubtopo")
  list.length(subtopo.instances) |> should.equal(2)
  list.length(subtopo.exported_ports) |> should.equal(2)

  let p1 = list.first(subtopo.exported_ports)
  p1 |> should.be_ok
  let assert Ok(port1) = p1
  port1.name |> should.equal("receiptIn")
  port1.instance_name |> should.equal("evidence_store")
  port1.port_name |> should.equal("record")
}

// -------------------------------------- 4. Ground Dictionary Emission

pub fn ground_dictionary_json_test() {
  let model = canonical_harness_model()
  let dict_json = generate_ground_dictionary_json(model, "HermesHarness")

  // Check required NASA JPL Ground Dictionary top-level sections
  dict_json
  |> string.contains("\"framework_version\":\"3.4.0-UOS\"")
  |> should.be_true
  dict_json
  |> string.contains("\"project_version\":\"2026.09-SIL6\"")
  |> should.be_true
  dict_json
  |> string.contains("\"topology\":\"HermesHarness\"")
  |> should.be_true
  dict_json |> string.contains("\"commands\":[") |> should.be_true
  dict_json |> string.contains("\"events\":[") |> should.be_true
  dict_json |> string.contains("\"telemetryChannels\":[") |> should.be_true
  dict_json |> string.contains("\"parameters\":[") |> should.be_true
  dict_json |> string.contains("\"telemetryPacketSets\":[") |> should.be_true

  // Check instance-qualified command opcode calculation
  dict_json |> string.contains("harness_config.CONVERGE") |> should.be_true
  dict_json |> string.contains("\"opcode\":1793") |> should.be_true
}
