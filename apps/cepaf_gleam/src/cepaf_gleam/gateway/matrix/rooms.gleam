//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/gateway/matrix/rooms</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-MATRIX-007</stamp-controls></compliance>
//// </c3i-module>
////
//// C3I-specific Matrix room management — 7 room types.

import cepaf_gleam/gateway/matrix/types
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

pub type C3iRoomType {
  OperatorRoom
  AlertRoom
  AgentRoom(String)
  FederationRoom
  AuditRoom
  OodaRoom
  GuardianRoom
}

pub type RoomTemplate {
  RoomTemplate(
    room_type: C3iRoomType,
    name: String,
    topic: String,
    alias_localpart: String,
    preset: String,
    power_levels: types.PowerLevels,
    invite_list: List(String),
  )
}

pub type RoomRegistry {
  RoomRegistry(rooms: List(#(String, String)), default_homeserver: String)
}

pub fn operator_template() -> RoomTemplate {
  RoomTemplate(
    room_type: OperatorRoom,
    name: "C3I Operators",
    topic: "System operators channel — Dark Cockpit monitoring",
    alias_localpart: "c3i-operators",
    preset: "private_chat",
    power_levels: types.default_power_levels(),
    invite_list: [],
  )
}

pub fn alert_template() -> RoomTemplate {
  RoomTemplate(
    room_type: AlertRoom,
    name: "C3I Alerts",
    topic: "Automated OTel alerts — read-only for non-admins",
    alias_localpart: "c3i-alerts",
    preset: "private_chat",
    power_levels: types.PowerLevels(
      ..types.default_power_levels(),
      events_default: 50,
    ),
    invite_list: [],
  )
}

pub fn agent_template(agent_id: String) -> RoomTemplate {
  RoomTemplate(
    room_type: AgentRoom(agent_id),
    name: "Agent: " <> agent_id,
    topic: "Agent communication channel — " <> agent_id,
    alias_localpart: "c3i-agent-" <> agent_id,
    preset: "private_chat",
    power_levels: types.default_power_levels(),
    invite_list: [],
  )
}

pub fn federation_template() -> RoomTemplate {
  RoomTemplate(
    room_type: FederationRoom,
    name: "C3I Federation",
    topic: "Multi-node federation coordination",
    alias_localpart: "c3i-federation",
    preset: "private_chat",
    power_levels: types.default_power_levels(),
    invite_list: [],
  )
}

pub fn audit_template() -> RoomTemplate {
  RoomTemplate(
    room_type: AuditRoom,
    name: "C3I Audit Trail",
    topic: "Append-only audit log — immutable record",
    alias_localpart: "c3i-audit",
    preset: "private_chat",
    power_levels: types.PowerLevels(
      ..types.default_power_levels(),
      events_default: 50,
      redact: 100,
    ),
    invite_list: [],
  )
}

pub fn ooda_template() -> RoomTemplate {
  RoomTemplate(
    room_type: OodaRoom,
    name: "C3I OODA Cycle",
    topic: "OODA loop events — observe/orient/decide/act",
    alias_localpart: "c3i-ooda",
    preset: "private_chat",
    power_levels: types.default_power_levels(),
    invite_list: [],
  )
}

pub fn guardian_template() -> RoomTemplate {
  RoomTemplate(
    room_type: GuardianRoom,
    name: "C3I Guardian",
    topic: "L0 Constitutional — HITL approval required",
    alias_localpart: "c3i-guardian",
    preset: "private_chat",
    power_levels: types.PowerLevels(
      ..types.default_power_levels(),
      events_default: 100,
      state_default: 100,
    ),
    invite_list: [],
  )
}

pub fn template_for(room_type: C3iRoomType) -> RoomTemplate {
  case room_type {
    OperatorRoom -> operator_template()
    AlertRoom -> alert_template()
    AgentRoom(id) -> agent_template(id)
    FederationRoom -> federation_template()
    AuditRoom -> audit_template()
    OodaRoom -> ooda_template()
    GuardianRoom -> guardian_template()
  }
}

pub fn all_templates() -> List(RoomTemplate) {
  [
    operator_template(),
    alert_template(),
    federation_template(),
    audit_template(),
    ooda_template(),
    guardian_template(),
  ]
}

pub fn room_alias(template: RoomTemplate, homeserver: String) -> String {
  "#" <> template.alias_localpart <> ":" <> homeserver
}

pub fn registry_new(homeserver: String) -> RoomRegistry {
  RoomRegistry(rooms: [], default_homeserver: homeserver)
}

pub fn register_room(
  registry: RoomRegistry,
  room_type_str: String,
  room_id: String,
) -> RoomRegistry {
  RoomRegistry(..registry, rooms: [#(room_type_str, room_id), ..registry.rooms])
}

pub fn find_room(
  registry: RoomRegistry,
  room_type_str: String,
) -> Option(String) {
  case list.find(registry.rooms, fn(r) { r.0 == room_type_str }) {
    Ok(#(_, id)) -> Some(id)
    Error(_) -> None
  }
}

pub fn room_type_to_string(rt: C3iRoomType) -> String {
  case rt {
    OperatorRoom -> "operator"
    AlertRoom -> "alert"
    AgentRoom(id) -> "agent:" <> id
    FederationRoom -> "federation"
    AuditRoom -> "audit"
    OodaRoom -> "ooda"
    GuardianRoom -> "guardian"
  }
}

pub fn room_count(registry: RoomRegistry) -> Int {
  list.length(registry.rooms)
}

pub fn summary(registry: RoomRegistry) -> String {
  "RoomRegistry("
  <> int.to_string(room_count(registry))
  <> " rooms, server="
  <> registry.default_homeserver
  <> ")"
}
