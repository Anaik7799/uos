/// Matrix Gateway Comprehensive Tests — Production-Class C1-C8
/// Tests against full Matrix Client-Server API v1.18 specification.
///
/// C1: Type construction & validation (11 tests)
/// C2: Message content types (9 tests)
/// C3: JSON codec encode/decode (8 tests)
/// C4: HTTP client layer (6 tests)
/// C5: Client state machine (8 tests)
/// C6: Room templates (8 tests)
/// C7: Bridge operations (6 tests)
/// C8: Container config (5 tests)
///
/// STAMP: SC-MATRIX-001..008
import cepaf_gleam/gateway/matrix/bridge
import cepaf_gleam/gateway/matrix/client
import cepaf_gleam/gateway/matrix/codec
import cepaf_gleam/gateway/matrix/config
import cepaf_gleam/gateway/matrix/http
import cepaf_gleam/gateway/matrix/rooms
import cepaf_gleam/gateway/matrix/types
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// ═══════════════════════════════════════════════════════════════════
// C1: Type Construction & Validation
// ═══════════════════════════════════════════════════════════════════

pub fn session_construction_test() {
  let s =
    types.MatrixSession("@user:server", "DEVICE1", "token123", "https://server")
  s.user_id |> should.equal("@user:server")
  s.device_id |> should.equal("DEVICE1")
}

pub fn event_type_roundtrip_all_test() {
  let ets = [
    types.MRoomMessage,
    types.MRoomMember,
    types.MRoomCreate,
    types.MRoomPowerLevels,
    types.MRoomTopic,
    types.MRoomName,
    types.MRoomJoinRules,
    types.MRoomHistoryVisibility,
    types.MRoomCanonicalAlias,
    types.MRoomAvatar,
    types.MRoomEncryption,
    types.MRoomRedaction,
    types.MPresence,
    types.MTyping,
    types.MReceipt,
    types.MReaction,
    types.MRoomPinnedEvents,
    types.CustomEvent("m.custom"),
  ]
  list.each(ets, fn(et) {
    let s = types.event_type_to_string(et)
    let rt = types.string_to_event_type(s)
    types.event_type_to_string(rt) |> should.equal(s)
  })
}

pub fn membership_roundtrip_test() {
  let ms = [types.Join, types.Leave, types.Invite, types.Ban, types.Knock]
  list.each(ms, fn(m) {
    let s = types.membership_to_string(m)
    let rt = types.string_to_membership(s)
    types.membership_to_string(rt) |> should.equal(s)
  })
}

pub fn presence_roundtrip_test() {
  let ps = [types.Online, types.Offline, types.Unavailable]
  list.each(ps, fn(p) {
    let s = types.presence_to_string(p)
    let rt = types.string_to_presence(s)
    types.presence_to_string(rt) |> should.equal(s)
  })
}

pub fn validate_room_id_valid_test() {
  types.validate_room_id("!abc:server.com") |> should.be_ok()
}

pub fn validate_room_id_invalid_test() {
  types.validate_room_id("abc:server.com") |> should.be_error()
}

pub fn validate_user_id_valid_test() {
  types.validate_user_id("@user:server.com") |> should.be_ok()
}

pub fn validate_user_id_invalid_test() {
  types.validate_user_id("user:server.com") |> should.be_error()
}

pub fn validate_event_id_valid_test() {
  types.validate_event_id("$event123") |> should.be_ok()
}

pub fn default_power_levels_test() {
  let pl = types.default_power_levels()
  pl.events_default |> should.equal(0)
  pl.state_default |> should.equal(50)
  pl.ban |> should.equal(50)
}

pub fn is_state_event_test() {
  let evt =
    types.MatrixEvent(
      "$1",
      types.MRoomTopic,
      "!r:s",
      "@u:s",
      100,
      "{}",
      Some(""),
    )
  types.is_state_event(evt) |> should.be_true()
  let evt2 =
    types.MatrixEvent("$2", types.MRoomMessage, "!r:s", "@u:s", 100, "{}", None)
  types.is_state_event(evt2) |> should.be_false()
}

// ═══════════════════════════════════════════════════════════════════
// C2: Message Content Types
// ═══════════════════════════════════════════════════════════════════

pub fn text_message_test() {
  let m = types.TextMessage("hello", None, None)
  m.body |> should.equal("hello")
}

pub fn notice_message_test() {
  let m = types.NoticeMessage("alert!")
  m.body |> should.equal("alert!")
}

pub fn image_message_test() {
  let m = types.ImageMessage("pic", "mxc://server/media", Some("image/png"))
  m.url |> should.equal("mxc://server/media")
}

pub fn file_message_test() {
  let m =
    types.FileMessage("doc", "mxc://s/m", "report.pdf", Some("application/pdf"))
  m.filename |> should.equal("report.pdf")
}

pub fn audio_message_test() {
  let m = types.AudioMessage("voice", "mxc://s/m", Some("audio/ogg"))
  m.body |> should.equal("voice")
}

pub fn video_message_test() {
  let m = types.VideoMessage("clip", "mxc://s/m", Some("video/mp4"))
  m.body |> should.equal("clip")
}

pub fn emote_message_test() {
  let m = types.EmoteMessage("waves")
  m.body |> should.equal("waves")
}

pub fn location_message_test() {
  let m = types.LocationMessage("here", "geo:59.3293,18.0686")
  m.geo_uri |> should.equal("geo:59.3293,18.0686")
}

pub fn custom_message_test() {
  let m = types.CustomMessage("m.c3i.otel", "span data")
  m.msgtype |> should.equal("m.c3i.otel")
}

// ═══════════════════════════════════════════════════════════════════
// C3: JSON Codec Encode/Decode
// ═══════════════════════════════════════════════════════════════════

pub fn encode_login_test() {
  let j = codec.encode_login("alice", "password123")
  { string.contains(j, "m.login.password") } |> should.be_true()
  { string.contains(j, "alice") } |> should.be_true()
}

pub fn encode_text_message_test() {
  let j = codec.encode_message(types.TextMessage("hello world", None, None))
  { string.contains(j, "m.text") } |> should.be_true()
  { string.contains(j, "hello world") } |> should.be_true()
}

pub fn encode_notice_message_test() {
  let j = codec.encode_message(types.NoticeMessage("system alert"))
  { string.contains(j, "m.notice") } |> should.be_true()
}

pub fn encode_create_room_test() {
  let j =
    codec.encode_create_room("Test Room", "A topic", "private_chat", ["@u:s"])
  { string.contains(j, "Test Room") } |> should.be_true()
  { string.contains(j, "private_chat") } |> should.be_true()
}

pub fn decode_login_response_valid_test() {
  let body =
    "{\"user_id\":\"@alice:server\",\"device_id\":\"DEV1\",\"access_token\":\"tok123\"}"
  let result = codec.decode_login_response(body)
  case result {
    Ok(s) -> {
      s.user_id |> should.equal("@alice:server")
      s.access_token |> should.equal("tok123")
    }
    Error(_) -> should.fail()
  }
}

pub fn decode_login_response_invalid_test() {
  codec.decode_login_response("{}") |> should.be_error()
}

pub fn decode_versions_test() {
  let body = "{\"versions\":[\"v1.1\",\"v1.18\"],\"unstable_features\":{}}"
  case codec.decode_versions(body) {
    Ok(vs) -> { vs != [] } |> should.be_true()
    Error(_) -> should.fail()
  }
}

pub fn decode_error_test() {
  let body = "{\"errcode\":\"M_FORBIDDEN\",\"error\":\"Access denied\"}"
  case codec.decode_error(body) {
    Ok(#(code, msg)) -> {
      code |> should.equal("M_FORBIDDEN")
      msg |> should.equal("Access denied")
    }
    Error(_) -> should.fail()
  }
}

// ═══════════════════════════════════════════════════════════════════
// C4: HTTP Client Layer
// ═══════════════════════════════════════════════════════════════════

pub fn http_client_new_test() {
  let c = http.new("https://matrix.example.com")
  c.base_url |> should.equal("https://matrix.example.com")
  c.access_token |> should.equal(None)
}

pub fn http_client_with_token_test() {
  let c = http.new("https://m.com") |> http.with_token("tok123")
  c.access_token |> should.equal(Some("tok123"))
}

pub fn build_get_request_test() {
  let c = http.new("https://m.com")
  let req = http.build_request(c, http.Get, "/path", None)
  req.method |> should.equal(http.Get)
  { string.contains(req.url, "/path") } |> should.be_true()
}

pub fn build_post_request_test() {
  let c = http.new("https://m.com")
  let req = http.build_request(c, http.Post, "/login", Some("{}"))
  req.method |> should.equal(http.Post)
  req.body |> should.equal(Some("{}"))
}

pub fn is_success_test() {
  http.is_success(200) |> should.be_true()
  http.is_success(201) |> should.be_true()
  http.is_success(404) |> should.be_false()
  http.is_success(500) |> should.be_false()
}

pub fn method_to_string_test() {
  http.method_to_string(http.Get) |> should.equal("GET")
  http.method_to_string(http.Post) |> should.equal("POST")
  http.method_to_string(http.Put) |> should.equal("PUT")
  http.method_to_string(http.Delete) |> should.equal("DELETE")
}

// ═══════════════════════════════════════════════════════════════════
// C5: Client State Machine
// ═══════════════════════════════════════════════════════════════════

pub fn client_new_test() {
  let c = client.new("https://m.com")
  c.session |> should.equal(None)
  c.consecutive_failures |> should.equal(0)
  c.transaction_id |> should.equal(0)
}

pub fn client_with_session_test() {
  let session = types.MatrixSession("@u:s", "D1", "tok", "https://m.com")
  let c = client.new("https://m.com") |> client.with_session(session)
  c.session |> should.equal(Some(session))
}

pub fn login_request_test() {
  let c = client.new("https://m.com")
  let #(_, req) = client.login_request(c, "alice", "pass")
  req.method |> should.equal(http.Post)
  { string.contains(req.url, "/login") } |> should.be_true()
}

pub fn sync_request_no_since_test() {
  let c = client.new("https://m.com")
  let #(_, req) = client.sync_request(c, 5000)
  { string.contains(req.url, "timeout=5000") } |> should.be_true()
}

pub fn send_message_request_test() {
  let session = types.MatrixSession("@u:s", "D1", "tok", "https://m.com")
  let c = client.new("https://m.com") |> client.with_session(session)
  let msg = types.TextMessage("hello", None, None)
  let #(new_c, req) = client.send_message_request(c, "!room:s", msg)
  req.method |> should.equal(http.Put)
  { string.contains(req.url, "m.room.message") } |> should.be_true()
  new_c.transaction_id |> should.equal(1)
}

pub fn record_failure_test() {
  let c = client.new("https://m.com")
  let c2 = client.record_failure(c)
  c2.consecutive_failures |> should.equal(1)
}

pub fn is_healthy_test() {
  let c = client.new("https://m.com")
  client.is_healthy(c) |> should.be_true()
  // After max_failures (5), not healthy
  let c2 = client.MatrixClientState(..c, consecutive_failures: 5)
  client.is_healthy(c2) |> should.be_false()
}

pub fn next_txn_id_test() {
  let c = client.new("https://m.com")
  let #(c2, txn) = client.next_txn_id(c)
  txn |> should.equal("m.1")
  c2.transaction_id |> should.equal(1)
}

// ═══════════════════════════════════════════════════════════════════
// C6: Room Templates
// ═══════════════════════════════════════════════════════════════════

pub fn operator_template_test() {
  let t = rooms.operator_template()
  t.name |> should.equal("C3I Operators")
  t.alias_localpart |> should.equal("c3i-operators")
  t.preset |> should.equal("private_chat")
}

pub fn alert_template_power_levels_test() {
  let t = rooms.alert_template()
  t.power_levels.events_default |> should.equal(50)
}

pub fn agent_template_test() {
  let t = rooms.agent_template("cortex-001")
  { string.contains(t.name, "cortex-001") } |> should.be_true()
  t.alias_localpart |> should.equal("c3i-agent-cortex-001")
}

pub fn guardian_template_restricted_test() {
  let t = rooms.guardian_template()
  t.power_levels.events_default |> should.equal(100)
  t.power_levels.state_default |> should.equal(100)
}

pub fn all_templates_count_test() {
  let ts = rooms.all_templates()
  // 6 base templates (agent requires agent_id so not included)
  list.length(ts) |> should.equal(6)
}

pub fn room_alias_format_test() {
  let t = rooms.operator_template()
  let alias = rooms.room_alias(t, "matrix.c3i.local")
  alias |> should.equal("#c3i-operators:matrix.c3i.local")
}

pub fn registry_new_test() {
  let r = rooms.registry_new("c3i.local")
  rooms.room_count(r) |> should.equal(0)
}

pub fn register_and_find_test() {
  let r =
    rooms.registry_new("c3i.local")
    |> rooms.register_room("operator", "!abc:c3i.local")
  case rooms.find_room(r, "operator") {
    Some(id) -> id |> should.equal("!abc:c3i.local")
    None -> should.fail()
  }
}

// ═══════════════════════════════════════════════════════════════════
// C7: Bridge Operations
// ═══════════════════════════════════════════════════════════════════

pub fn bridge_new_test() {
  let c = client.new("https://m.com")
  let r = rooms.registry_new("c3i.local")
  let b = bridge.bridge_new(c, r)
  bridge.bridge_health(b) |> should.equal(1.0)
}

pub fn zenoh_topic_for_room_test() {
  let topic = bridge.zenoh_topic_for_room("!abc:server")
  { string.contains(topic, "indrajaal/l7/matrix/events/") } |> should.be_true()
}

pub fn process_matrix_event_test() {
  let c = client.new("https://m.com")
  let r = rooms.registry_new("c3i.local")
  let b = bridge.bridge_new(c, r)
  let evt =
    types.MatrixEvent("$1", types.MRoomMessage, "!r:s", "@u:s", 100, "{}", None)
  let #(new_b, action) = bridge.process_matrix_event(b, "!r:s", evt)
  new_b.sync_count |> should.equal(1)
  case action {
    bridge.ForwardToZenoh(_, _) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn bridge_health_degrades_test() {
  let c = client.new("https://m.com")
  let c_degraded = client.MatrixClientState(..c, consecutive_failures: 5)
  let r = rooms.registry_new("c3i.local")
  let b = bridge.bridge_new(c_degraded, r)
  let h = bridge.bridge_health(b)
  { h <. 1.0 } |> should.be_true()
}

pub fn forward_intent_test() {
  let c = client.new("https://m.com")
  let r = rooms.registry_new("c3i.local")
  let b = bridge.bridge_new(c, r)
  let #(_, action) = bridge.forward_intent(b, "restart container X")
  case action {
    bridge.ForwardToZenoh(topic, _) ->
      { string.contains(topic, "intent") } |> should.be_true()
    _ -> should.fail()
  }
}

pub fn bridge_summary_test() {
  let c = client.new("https://m.com")
  let r = rooms.registry_new("c3i.local")
  let b = bridge.bridge_new(c, r)
  let s = bridge.summary(b)
  { s != "" } |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════════
// C8: Container Config
// ═══════════════════════════════════════════════════════════════════

pub fn default_tuwunel_config_test() {
  let c = config.default_config("c3i.local")
  c.server_name |> should.equal("c3i.local")
  c.port |> should.equal(6167)
}

pub fn config_to_toml_test() {
  let c = config.default_config("c3i.local")
  let toml = config.config_to_toml(c)
  { string.contains(toml, "c3i.local") } |> should.be_true()
  { string.contains(toml, "[global]") } |> should.be_true()
}

pub fn container_spec_test() {
  let spec = config.container_spec()
  spec.name |> should.equal("matrix-homeserver")
  spec.federation_port |> should.equal(8448)
  spec.client_port |> should.equal(6167)
  spec.boot_tier |> should.equal(5)
}

pub fn port_safety_test() {
  config.is_port_safe(8448) |> should.be_true()
  config.is_port_safe(6167) |> should.be_true()
  config.is_port_safe(4005) |> should.be_false()
}

pub fn health_check_url_test() {
  let spec = config.container_spec()
  let url = config.health_check_url(spec)
  { string.contains(url, "/_matrix/client/versions") } |> should.be_true()
  { string.contains(url, "6167") } |> should.be_true()
}
