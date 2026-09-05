//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity><module>cepaf_gleam/gateway/matrix/types</module></identity>
////   <fractal-topology><layer>L0_CONSTITUTIONAL</layer></fractal-topology>
////   <compliance><stamp-controls>SC-MATRIX-001, SC-MATRIX-002</stamp-controls></compliance>
////   <transformations>
////     <morphism type="constructive">
////       Complete Matrix v1.18 protocol types as pure Gleam ADTs.
////       Zero I/O, zero side effects. Foundation for all Matrix modules.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================

import gleam/option.{type Option, None, Some}
import gleam/string

// -- Core Identity Types -----------------------------------------------------

pub type MatrixSession {
  MatrixSession(
    user_id: String,
    device_id: String,
    access_token: String,
    homeserver_url: String,
  )
}

// -- Event Types -------------------------------------------------------------

pub type EventType {
  MRoomMessage
  MRoomMember
  MRoomCreate
  MRoomPowerLevels
  MRoomTopic
  MRoomName
  MRoomJoinRules
  MRoomHistoryVisibility
  MRoomCanonicalAlias
  MRoomAvatar
  MRoomEncryption
  MRoomRedaction
  MPresence
  MTyping
  MReceipt
  MReaction
  MRoomPinnedEvents
  CustomEvent(String)
}

pub type MatrixEvent {
  MatrixEvent(
    event_id: String,
    event_type: EventType,
    room_id: String,
    sender: String,
    origin_server_ts: Int,
    content: String,
    state_key: Option(String),
  )
}

// -- Message Content ---------------------------------------------------------

pub type MessageContent {
  TextMessage(
    body: String,
    format: Option(String),
    formatted_body: Option(String),
  )
  NoticeMessage(body: String)
  ImageMessage(body: String, url: String, mimetype: Option(String))
  FileMessage(
    body: String,
    url: String,
    filename: String,
    mimetype: Option(String),
  )
  AudioMessage(body: String, url: String, mimetype: Option(String))
  VideoMessage(body: String, url: String, mimetype: Option(String))
  EmoteMessage(body: String)
  LocationMessage(body: String, geo_uri: String)
  CustomMessage(msgtype: String, body: String)
}

// -- Membership & Power Levels -----------------------------------------------

pub type Membership {
  Join
  Leave
  Invite
  Ban
  Knock
}

pub type PowerLevels {
  PowerLevels(
    events_default: Int,
    state_default: Int,
    users_default: Int,
    ban: Int,
    kick: Int,
    invite_level: Int,
    redact: Int,
    users: List(#(String, Int)),
    events: List(#(String, Int)),
  )
}

// -- Room State --------------------------------------------------------------

pub type RoomState {
  RoomState(
    room_id: String,
    name: Option(String),
    topic: Option(String),
    canonical_alias: Option(String),
    creator: String,
    members: List(#(String, Membership)),
    power_levels: PowerLevels,
    join_rule: String,
    history_visibility: String,
    encrypted: Bool,
    version: String,
  )
}

// -- Sync Response -----------------------------------------------------------

pub type SyncResponse {
  SyncResponse(
    next_batch: String,
    rooms: SyncRooms,
    presence: List(MatrixEvent),
  )
}

pub type SyncRooms {
  SyncRooms(
    join: List(JoinedRoom),
    invite: List(InvitedRoom),
    leave: List(LeftRoom),
  )
}

pub type JoinedRoom {
  JoinedRoom(
    room_id: String,
    timeline: List(MatrixEvent),
    state: List(MatrixEvent),
    ephemeral: List(MatrixEvent),
    prev_batch: Option(String),
    limited: Bool,
  )
}

pub type InvitedRoom {
  InvitedRoom(room_id: String, invite_state: List(MatrixEvent))
}

pub type LeftRoom {
  LeftRoom(room_id: String, timeline: List(MatrixEvent))
}

// -- Presence & Ephemeral ----------------------------------------------------

pub type PresenceState {
  Online
  Offline
  Unavailable
}

pub type TypingNotification {
  TypingNotification(room_id: String, user_ids: List(String))
}

pub type ReadReceipt {
  ReadReceipt(room_id: String, event_id: String, user_id: String, ts: Int)
}

// -- E2EE Types --------------------------------------------------------------

pub type DeviceInfo {
  DeviceInfo(
    device_id: String,
    display_name: Option(String),
    last_seen_ip: Option(String),
    last_seen_ts: Option(Int),
  )
}

pub type EncryptionConfig {
  EncryptionConfig(
    algorithm: String,
    rotation_period_ms: Int,
    rotation_period_msgs: Int,
  )
}

// -- Federation --------------------------------------------------------------

pub type FederationPeer {
  FederationPeer(server_name: String, last_seen_ts: Int, verified: Bool)
}

// -- Conversion Functions ----------------------------------------------------

pub fn event_type_to_string(et: EventType) -> String {
  case et {
    MRoomMessage -> "m.room.message"
    MRoomMember -> "m.room.member"
    MRoomCreate -> "m.room.create"
    MRoomPowerLevels -> "m.room.power_levels"
    MRoomTopic -> "m.room.topic"
    MRoomName -> "m.room.name"
    MRoomJoinRules -> "m.room.join_rules"
    MRoomHistoryVisibility -> "m.room.history_visibility"
    MRoomCanonicalAlias -> "m.room.canonical_alias"
    MRoomAvatar -> "m.room.avatar"
    MRoomEncryption -> "m.room.encryption"
    MRoomRedaction -> "m.room.redaction"
    MPresence -> "m.presence"
    MTyping -> "m.typing"
    MReceipt -> "m.receipt"
    MReaction -> "m.reaction"
    MRoomPinnedEvents -> "m.room.pinned_events"
    CustomEvent(t) -> t
  }
}

pub fn string_to_event_type(s: String) -> EventType {
  case s {
    "m.room.message" -> MRoomMessage
    "m.room.member" -> MRoomMember
    "m.room.create" -> MRoomCreate
    "m.room.power_levels" -> MRoomPowerLevels
    "m.room.topic" -> MRoomTopic
    "m.room.name" -> MRoomName
    "m.room.join_rules" -> MRoomJoinRules
    "m.room.history_visibility" -> MRoomHistoryVisibility
    "m.room.canonical_alias" -> MRoomCanonicalAlias
    "m.room.avatar" -> MRoomAvatar
    "m.room.encryption" -> MRoomEncryption
    "m.room.redaction" -> MRoomRedaction
    "m.presence" -> MPresence
    "m.typing" -> MTyping
    "m.receipt" -> MReceipt
    "m.reaction" -> MReaction
    "m.room.pinned_events" -> MRoomPinnedEvents
    other -> CustomEvent(other)
  }
}

pub fn membership_to_string(m: Membership) -> String {
  case m {
    Join -> "join"
    Leave -> "leave"
    Invite -> "invite"
    Ban -> "ban"
    Knock -> "knock"
  }
}

pub fn string_to_membership(s: String) -> Membership {
  case s {
    "join" -> Join
    "invite" -> Invite
    "ban" -> Ban
    "knock" -> Knock
    _ -> Leave
  }
}

pub fn presence_to_string(p: PresenceState) -> String {
  case p {
    Online -> "online"
    Offline -> "offline"
    Unavailable -> "unavailable"
  }
}

pub fn string_to_presence(s: String) -> PresenceState {
  case s {
    "online" -> Online
    "unavailable" -> Unavailable
    _ -> Offline
  }
}

pub fn is_state_event(event: MatrixEvent) -> Bool {
  case event.state_key {
    Some(_) -> True
    None -> False
  }
}

pub fn default_power_levels() -> PowerLevels {
  PowerLevels(
    events_default: 0,
    state_default: 50,
    users_default: 0,
    ban: 50,
    kick: 50,
    invite_level: 0,
    redact: 50,
    users: [],
    events: [],
  )
}

pub fn validate_room_id(s: String) -> Result(String, String) {
  case string.starts_with(s, "!") {
    True -> Ok(s)
    False -> Error("Room ID must start with '!'")
  }
}

pub fn validate_user_id(s: String) -> Result(String, String) {
  case string.starts_with(s, "@") {
    True -> Ok(s)
    False -> Error("User ID must start with '@'")
  }
}

pub fn validate_event_id(s: String) -> Result(String, String) {
  case string.starts_with(s, "$") {
    True -> Ok(s)
    False -> Error("Event ID must start with '$'")
  }
}

pub fn empty_sync() -> SyncResponse {
  SyncResponse(
    next_batch: "",
    rooms: SyncRooms(join: [], invite: [], leave: []),
    presence: [],
  )
}

pub fn summary_event(event: MatrixEvent) -> String {
  event.sender
  <> ": "
  <> event_type_to_string(event.event_type)
  <> " in "
  <> event.room_id
}
