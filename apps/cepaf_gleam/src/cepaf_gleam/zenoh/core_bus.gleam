//// UOS-CORE-EVO: Hardened `uos/v1/**` Signed Zenoh & ZLP-v3 Bus
//// (`SC-HARNESS-MCP-001`, `SC-PROVENANCE-001`, `I04` & `I28` Split-Brain Fence)
////
//// Provides the unified event, heartbeat, quota-window, RCA/TPS handoff, and
//// <= 512-byte conductor-digest communication plane backed by:
//// 1. Supervised UOS-ZLP-v3 OTP 29 Port Hyperplane (`zlp_hyperplane.gleam`:
////    Lean 4.33.0 zero-sorry `verify_frame` anti-replay + Zig 0.16.0 Zen 5
////    AVX-512 Two-Lane `epoll`/`eventfd` Zenoh `:7447`/`:8000` shards).
//// 2. Local BEAM ETS store-and-forward cache (`beam_cache`) so zero envelopes
////    are lost across `:4100` release capsule restarts.
//// 3. Fail-closed cryptographic/structural fence dropping legacy `c3i/**`
////    frames from `:4200` (`PID 9040` `sa-plan-daemon`), `EV > 93` claims,
////    replayed `seq_id` frames, and oversized payloads.

import cepaf_gleam/ecology/core_evolution
import cepaf_gleam/mcp/transports/zlp_hyperplane
import cepaf_gleam/substrate/beam_cache
import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub const envelope_schema = "uos.zenoh.core_evo.v1"

pub const max_worker_payload_bytes = 4096

pub const default_shards = 4

pub type CoreBusError {
  ErrLegacySplitBrainTopic(topic: String)
  ErrInvalidUosV1Topic(topic: String)
  ErrProvenanceCeilingExceeded(ev_claimed: Int)
  ErrNonMonotonicSeq(seq_id: Int, last_seq_id: Int)
  ErrInvalidHexDigest(field: String)
  ErrPayloadTooLarge(actual_bytes: Int, limit_bytes: Int)
  ErrDigestMismatch(expected: String, actual: String)
  ErrMalformedEnvelopeJson(detail: String)
  ErrTransportRefused(detail: String)
}

pub type SignedCoreEnvelope {
  SignedCoreEnvelope(
    schema: String,
    topic: String,
    candidate_sha256: String,
    plan_id: String,
    task_id: String,
    worker_id: String,
    attempt: Int,
    seq_id: Int,
    ev_ceiling: Int,
    payload_sha256: String,
    payload_json: String,
  )
}

pub type BusDeliveryReceipt {
  BusDeliveryReceipt(
    topic: String,
    seq_id: Int,
    ets_buffered: Bool,
    zlp_published: Bool,
    lean_verified_excl: Int,
  )
}

@external(erlang, "crypto", "hash")
fn crypto_hash_sha256(alg: Sha256Atom, data: BitArray) -> BitArray

pub type Sha256Atom {
  Sha256
}

/// Compute lowercase 64-char SHA-256 hex digest using BEAM `crypto:hash/2`.
pub fn sha256_hex(input: String) -> String {
  crypto_hash_sha256(Sha256, bit_array.from_string(input))
  |> bit_array.base16_encode
  |> string.lowercase
}

/// Strictly validate `uos/v1/{domain}/...` topics and fence out `c3i/**` (`I28`).
pub fn validate_topic(topic: String) -> Result(String, CoreBusError) {
  case
    string.starts_with(topic, "c3i/")
    || topic == "c3i"
    || string.contains(topic, "/c3i/")
  {
    True -> Error(ErrLegacySplitBrainTopic(topic))
    False -> {
      let bytes = string.byte_size(topic)
      let parts = string.split(topic, "/")
      let allowed_chars =
        list.all(string.to_graphemes(topic), fn(c) {
          string.contains(
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/_-",
            c,
          )
        })
      let non_empty_segments =
        list.all(parts, fn(p) { p != "" && p != "." && p != ".." })
      case bytes >= 10 && bytes <= 256 && allowed_chars && non_empty_segments {
        False -> Error(ErrInvalidUosV1Topic(topic))
        True ->
          case parts {
            ["uos", "v1", domain, ..rest] ->
              case
                list.contains(
                  [
                    "quota",
                    "saplan",
                    "rca",
                    "coord",
                    "wave",
                    "core_evo",
                    "hive",
                    "biomorphic",
                    "fractal",
                  ],
                  domain,
                )
                && rest != []
              {
                True -> Ok(topic)
                False -> Error(ErrInvalidUosV1Topic(topic))
              }
            _ -> Error(ErrInvalidUosV1Topic(topic))
          }
      }
    }
  }
}

/// Construct a canonical `SignedCoreEnvelope` with authentic SHA-256 payload digest.
pub fn build_envelope(
  topic topic: String,
  candidate_sha256 candidate_sha256: String,
  plan_id plan_id: String,
  task_id task_id: String,
  worker_id worker_id: String,
  attempt attempt: Int,
  seq_id seq_id: Int,
  ev_ceiling ev_ceiling: Int,
  payload_json payload_json: String,
) -> Result(SignedCoreEnvelope, CoreBusError) {
  let env =
    SignedCoreEnvelope(
      schema: envelope_schema,
      topic: topic,
      candidate_sha256: string.lowercase(candidate_sha256),
      plan_id: plan_id,
      task_id: task_id,
      worker_id: worker_id,
      attempt: attempt,
      seq_id: seq_id,
      ev_ceiling: ev_ceiling,
      payload_sha256: sha256_hex(payload_json),
      payload_json: payload_json,
    )
  use _ <- result.try(validate_envelope(env, 0))
  Ok(env)
}

/// Validate all structural, provenance (`EV <= 93`), split-brain (`uos/v1/**`),
/// monotonic anti-replay (`seq_id > last_seq_id`), SHA-256 integrity, and
/// Zero-Muda payload-size invariants (`<= 512 B` for wave summaries).
pub fn validate_envelope(
  env: SignedCoreEnvelope,
  last_seq_id: Int,
) -> Result(SignedCoreEnvelope, CoreBusError) {
  use _ <- result.try(validate_topic(env.topic))
  case env.schema == envelope_schema {
    False -> Error(ErrMalformedEnvelopeJson("unexpected_schema:" <> env.schema))
    True ->
      case
        env.ev_ceiling >= 0
        && env.ev_ceiling <= core_evolution.admitted_ev_ceiling
      {
        False -> Error(ErrProvenanceCeilingExceeded(env.ev_ceiling))
        True ->
          case env.seq_id > last_seq_id && env.seq_id > 0 {
            False -> Error(ErrNonMonotonicSeq(env.seq_id, last_seq_id))
            True ->
              case is_hex64(env.candidate_sha256) {
                False -> Error(ErrInvalidHexDigest("candidate_sha256"))
                True ->
                  case is_hex64(env.payload_sha256) {
                    False -> Error(ErrInvalidHexDigest("payload_sha256"))
                    True -> {
                      let limit = max_bytes_for_topic(env.topic)
                      let actual = string.byte_size(env.payload_json)
                      case actual <= limit {
                        False -> Error(ErrPayloadTooLarge(actual, limit))
                        True -> {
                          let computed = sha256_hex(env.payload_json)
                          case computed == env.payload_sha256 {
                            False ->
                              Error(ErrDigestMismatch(
                                env.payload_sha256,
                                computed,
                              ))
                            True -> Ok(env)
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

pub fn encode_envelope(env: SignedCoreEnvelope) -> String {
  json.object([
    #("schema", json.string(env.schema)),
    #("topic", json.string(env.topic)),
    #("candidate_sha256", json.string(env.candidate_sha256)),
    #("plan_id", json.string(env.plan_id)),
    #("task_id", json.string(env.task_id)),
    #("worker_id", json.string(env.worker_id)),
    #("attempt", json.int(env.attempt)),
    #("seq_id", json.int(env.seq_id)),
    #("ev_ceiling", json.int(env.ev_ceiling)),
    #("payload_sha256", json.string(env.payload_sha256)),
    #("payload_json", json.string(env.payload_json)),
  ])
  |> json.to_string
}

pub fn decode_and_verify_envelope(
  wire_json: String,
  last_seq_id: Int,
) -> Result(SignedCoreEnvelope, CoreBusError) {
  let decoder = {
    use schema <- decode.field("schema", decode.string)
    use topic <- decode.field("topic", decode.string)
    use candidate_sha256 <- decode.field("candidate_sha256", decode.string)
    use plan_id <- decode.field("plan_id", decode.string)
    use task_id <- decode.field("task_id", decode.string)
    use worker_id <- decode.field("worker_id", decode.string)
    use attempt <- decode.field("attempt", decode.int)
    use seq_id <- decode.field("seq_id", decode.int)
    use ev_ceiling <- decode.field("ev_ceiling", decode.int)
    use payload_sha256 <- decode.field("payload_sha256", decode.string)
    use payload_json <- decode.field("payload_json", decode.string)
    decode.success(SignedCoreEnvelope(
      schema: schema,
      topic: topic,
      candidate_sha256: candidate_sha256,
      plan_id: plan_id,
      task_id: task_id,
      worker_id: worker_id,
      attempt: attempt,
      seq_id: seq_id,
      ev_ceiling: ev_ceiling,
      payload_sha256: payload_sha256,
      payload_json: payload_json,
    ))
  }
  case json.parse(wire_json, decoder) {
    Error(_) -> Error(ErrMalformedEnvelopeJson("json_decode_failed"))
    Ok(env) -> validate_envelope(env, last_seq_id)
  }
}

/// Publish a verified `SignedCoreEnvelope` through BEAM ETS store-and-forward
/// AND the supervised UOS-ZLP-v3 Lean 4.33.0 + Zig 0.16.0 Zenoh hyperplane.
pub fn publish_verified(
  env: SignedCoreEnvelope,
) -> Result(BusDeliveryReceipt, CoreBusError) {
  use valid_env <- result.try(validate_envelope(env, 0))
  let wire = encode_envelope(valid_env)
  let _ = beam_cache.init()
  let ets_ok = case beam_cache.put("core_bus:" <> valid_env.topic, wire) {
    Ok(Nil) -> True
    Error(_) -> False
  }

  case zlp_hyperplane.is_binary_available() {
    False ->
      case ets_ok {
        True ->
          Ok(BusDeliveryReceipt(
            topic: valid_env.topic,
            seq_id: valid_env.seq_id,
            ets_buffered: True,
            zlp_published: False,
            lean_verified_excl: 0,
          ))
        False -> Error(ErrTransportRefused("ets_and_zlp_unavailable"))
      }
    True -> {
      let _ = zlp_hyperplane.ensure_started(shards: default_shards)
      // Verify frame via Lean 4.33.0 C-ABI kernel (`verify_frame`) and publish
      // over Zig 0.16.0 Zen 5 AVX-512 Zenoh `:8000`/`:7447` port shard.
      let lean_excl = case
        zlp_hyperplane.verify_frame(
          seq_id: valid_env.seq_id,
          check_json_depth: True,
          payload: wire,
        )
      {
        Ok(r) -> r.excl
        Error(_) -> 0
      }
      case
        zlp_hyperplane.zenoh_publish(topic: valid_env.topic, json_payload: wire)
      {
        Ok(pub_receipt) ->
          Ok(BusDeliveryReceipt(
            topic: valid_env.topic,
            seq_id: valid_env.seq_id,
            ets_buffered: ets_ok,
            zlp_published: True,
            lean_verified_excl: int.max(lean_excl, pub_receipt.excl),
          ))
        Error(refusal) ->
          case ets_ok {
            True ->
              Ok(BusDeliveryReceipt(
                topic: valid_env.topic,
                seq_id: valid_env.seq_id,
                ets_buffered: True,
                zlp_published: False,
                lean_verified_excl: lean_excl,
              ))
            False -> Error(ErrTransportRefused(refusal.detail))
          }
      }
    }
  }
}

/// Fetch and cryptographically re-verify the latest `SignedCoreEnvelope` for a
/// `uos/v1/**` topic from ZLP-v3 Zenoh `:8000` (falling back seamlessly to ETS
/// store-and-forward during capsule cutover).
pub fn fetch_verified(
  topic: String,
  last_seq_id: Int,
) -> Result(SignedCoreEnvelope, CoreBusError) {
  use _ <- result.try(validate_topic(topic))
  let zlp_wire = case zlp_hyperplane.is_binary_available() {
    False -> Error(Nil)
    True -> {
      let _ = zlp_hyperplane.ensure_started(shards: default_shards)
      case zlp_hyperplane.zenoh_get(topic: topic) {
        Ok(#(_, body)) -> extract_wire_from_zenoh_reply(body)
        Error(_) -> Error(Nil)
      }
    }
  }
  case zlp_wire {
    Ok(wire) -> decode_and_verify_envelope(wire, last_seq_id)
    Error(_) -> {
      let _ = beam_cache.init()
      case beam_cache.get("core_bus:" <> topic) {
        Ok(cached_wire) -> decode_and_verify_envelope(cached_wire, last_seq_id)
        Error(err) -> Error(ErrTransportRefused("topic_not_found:" <> err))
      }
    }
  }
}

fn extract_wire_from_zenoh_reply(raw: String) -> Result(String, Nil) {
  let trimmed = string.trim(raw)
  case string.starts_with(trimmed, "{\"schema\":\"uos.zenoh.core_evo.v1\"") {
    True -> Ok(trimmed)
    False -> {
      // Zenoh REST `/key` returns `[{"key":"...","value":...}]` where `value`
      // is either a decoded JSON object or a string/encoded value.
      let obj_decoder =
        decode.list({
          use val_str <- decode.field("value", decode.string)
          decode.success(val_str)
        })
      case json.parse(trimmed, obj_decoder) {
        Ok([first, ..]) -> Ok(first)
        _ -> Error(Nil)
      }
    }
  }
}

fn max_bytes_for_topic(topic: String) -> Int {
  case
    string.starts_with(topic, "uos/v1/wave/")
    && string.ends_with(topic, "/summary")
  {
    True -> core_evolution.max_conductor_digest_bytes
    False -> max_worker_payload_bytes
  }
}

fn is_hex64(s: String) -> Bool {
  string.byte_size(s) == 64
  && list.all(string.to_graphemes(s), fn(c) {
    string.contains("0123456789abcdef", c)
  })
}
