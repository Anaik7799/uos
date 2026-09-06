//// =============================================================================
//// [UOS-FPP-PACKETIZER] NASA JPL F Prime Telemetry Packetizer in Gleam
//// =============================================================================
//// Packs individual telemetry channels into downlink packet sets:
//// - Validates that all required channel_ids are present
//// - Encodes packed telemetry buffers to structured JSON for ground processing
//// =============================================================================

import cepaf_gleam/fpp/domain.{type TlmPacket}
import gleam/int
import gleam/json
import gleam/list

pub type PackedTelemetryPacket {
  PackedTelemetryPacket(
    packet_id: Int,
    packet_name: String,
    channels: List(#(Int, String)),
  )
}

pub fn pack_telemetry(
  packet: TlmPacket,
  available_channels: List(#(Int, String)),
) -> Result(PackedTelemetryPacket, String) {
  let packed_channels =
    list.filter_map(packet.channel_ids, fn(cid) {
      case list.key_find(available_channels, cid) {
        Ok(v) -> Ok(#(cid, v))
        Error(_) -> Error(Nil)
      }
    })

  let missing =
    list.filter(packet.channel_ids, fn(cid) {
      case list.key_find(available_channels, cid) {
        Ok(_) -> False
        Error(_) -> True
      }
    })

  case missing {
    [] ->
      Ok(PackedTelemetryPacket(
        packet_id: packet.packet_id,
        packet_name: packet.packet_name,
        channels: packed_channels,
      ))
    [first, ..] ->
      Error(
        "Packet "
        <> packet.packet_name
        <> " missing required channel ID "
        <> int.to_string(first),
      )
  }
}

pub fn serialize_packet_json(packed: PackedTelemetryPacket) -> String {
  json.object([
    #("packet_id", json.int(packed.packet_id)),
    #("packet_name", json.string(packed.packet_name)),
    #(
      "channels",
      json.array(packed.channels, fn(pair) {
        json.object([
          #("channel_id", json.int(pair.0)),
          #("value", json.string(pair.1)),
        ])
      }),
    ),
  ])
  |> json.to_string
}
