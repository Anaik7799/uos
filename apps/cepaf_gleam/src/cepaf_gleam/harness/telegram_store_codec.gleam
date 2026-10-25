//// Strict domain codec for Telegram durable storage v2.
//// Spec: uos.telegram-durable-store-corrected-development-spec.v1
//// Wire: uos.telegram-store-wire-v4.v1

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_delivery_ledger as ledger
import cepaf_gleam/harness/telegram_ingress_guard as guard
import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const max_request_json_bytes = 1_048_572

pub const max_response_json_bytes = 1_048_572

pub const max_key_bytes = 256

pub const max_operation_id_bytes = 128

pub const max_value_bytes = 98_304

pub const max_aggregate_decoded_values = 524_288

pub const max_changes = 128

pub const max_read_set_assertions = 128

pub const max_read_keys = 64

pub const max_receipt_summary_bytes = 65_536

pub const max_reservation_delta_rows = 20

pub const max_reservation_delta_receipts = 64

pub const max_rows_capacity = 20_000

pub const max_receipts_capacity = 20_000

pub const max_inbox_index_limit = 100

pub const schema_version = "uos.telegram-store.v2"

pub type ReadSetAssertion {
  ReadSetAssertion(key: String, expected_version: Int, expected_sha256: String)
}

pub type Change {
  Change(
    key: String,
    expected_version: Int,
    expected_sha256: String,
    new_value_base64: String,
  )
}

pub type ReservationDelta {
  ReservationDelta(rows: Int, receipts: Int)
}

pub type RowResult {
  RowResult(
    key: String,
    exists: Bool,
    version: Int,
    canonical_value_base64: String,
    sha256: String,
  )
}

pub type Receipt {
  Receipt(
    operation_id: String,
    request_digest: String,
    generation: Int,
    summary_json: String,
    committed_utc_us: Int,
  )
}

pub type ApplyResult {
  ApplyResult(replay: Bool, receipt: Receipt)
}

pub type LookupResult {
  LookupResult(found: Bool, receipt: Option(Receipt))
}

pub type AuthorityRecord {
  AuthorityRecord(
    request_id: String,
    bot_id: Int,
    worker: String,
    epoch: Int,
    granted_at_ms: Int,
  )
}

pub type ResultMeta {
  ResultMeta(
    request_id: String,
    bot_id: Int,
    chat_id: Int,
    update_id: Int,
    message_id: Int,
    user_id: Int,
    text_hash: String,
    created_at_ms: Int,
    digest: String,
    total_chunks: Int,
  )
}

// -----------------------------------------------------------------------------
// Canonical Base64 Utilities
// -----------------------------------------------------------------------------

pub fn encode_canonical_base64(raw: String) -> String {
  bit_array.from_string(raw)
  |> bit_array.base64_encode(True)
}

pub fn decode_canonical_base64(s: String) -> Result(String, String) {
  case string.byte_size(s) % 4 == 0 {
    False -> Error("invalid_base64")
    True ->
      case bit_array.base64_decode(s) {
        Error(_) -> Error("invalid_base64")
        Ok(bits) ->
          case bit_array.base64_encode(bits, True) == s {
            False -> Error("non_canonical_base64")
            True ->
              bit_array.to_string(bits)
              |> result.map_error(fn(_) { "invalid_utf8" })
          }
      }
  }
}

// -----------------------------------------------------------------------------
// Row Result Validation
// -----------------------------------------------------------------------------

pub fn is_valid_hex_64(h: String) -> Bool {
  case string.byte_size(h) == 64 {
    False -> False
    True -> {
      list.all(string.to_graphemes(h), fn(c) {
        string.contains("0123456789abcdef", c)
      })
    }
  }
}

pub fn validate_row_result(row: RowResult) -> Result(RowResult, String) {
  case row.exists {
    False ->
      case
        row.version == 0 && row.canonical_value_base64 == "" && row.sha256 == ""
      {
        True -> Ok(row)
        False -> Error("invalid_absent_row_invariants")
      }
    True ->
      case
        row.version > 0
        && is_valid_hex_64(row.sha256)
        && string.byte_size(row.canonical_value_base64) > 0
      {
        False -> Error("invalid_present_row_invariants")
        True ->
          case decode_canonical_base64(row.canonical_value_base64) {
            Error(err) -> Error("corrupt_row_base64: " <> err)
            Ok(decoded) ->
              case files.digest(decoded) == row.sha256 {
                True -> Ok(row)
                False -> Error("corrupt_row_hash_mismatch")
              }
          }
      }
  }
}

pub fn decode_row_value(row: RowResult) -> Result(String, String) {
  use validated <- result.try(validate_row_result(row))
  case validated.exists {
    False -> Error("row_absent")
    True -> decode_canonical_base64(validated.canonical_value_base64)
  }
}

// -----------------------------------------------------------------------------
// Canonical Versioned Request Digest Derivation
// Header: "uos.telegram-store.apply.v2\n"
// -----------------------------------------------------------------------------

fn add_lp_field(s: String) -> String {
  int.to_string(string.byte_size(s)) <> ":" <> s <> "\n"
}

pub fn compute_apply_digest(
  bot_id: Int,
  operation_id: String,
  expected_generation: Int,
  read_set: List(ReadSetAssertion),
  changes: List(Change),
  res_delta: ReservationDelta,
  summary_json: String,
) -> String {
  let sorted_read_set =
    list.sort(read_set, fn(a, b) { string.compare(a.key, b.key) })
  let sorted_changes =
    list.sort(changes, fn(a, b) { string.compare(a.key, b.key) })

  let buf =
    "uos.telegram-store.apply.v2\n"
    <> add_lp_field(int.to_string(bot_id))
    <> add_lp_field(operation_id)
    <> int.to_string(expected_generation)
    <> "\n"
    <> int.to_string(list.length(sorted_read_set))
    <> "\n"
    <> list.fold(sorted_read_set, "", fn(acc, a) {
      acc
      <> add_lp_field(a.key)
      <> int.to_string(a.expected_version)
      <> "\n"
      <> add_lp_field(a.expected_sha256)
    })
    <> int.to_string(list.length(sorted_changes))
    <> "\n"
    <> list.fold(sorted_changes, "", fn(acc, c) {
      acc
      <> add_lp_field(c.key)
      <> int.to_string(c.expected_version)
      <> "\n"
      <> add_lp_field(c.expected_sha256)
      <> add_lp_field(c.new_value_base64)
    })
    <> int.to_string(res_delta.rows)
    <> ":"
    <> int.to_string(res_delta.receipts)
    <> "\n"
    <> add_lp_field(summary_json)

  files.digest(buf)
}

// -----------------------------------------------------------------------------
// Command Encoders
// -----------------------------------------------------------------------------

pub fn encode_initialize_new_command(
  bot_id: Int,
  db_path: Option(String),
) -> String {
  json.object([
    #("command", json.string("initialize_new")),
    #("bot_id", json.string(int.to_string(bot_id))),
    ..case db_path {
      Some(p) -> [#("db_path", json.string(p))]
      None -> []
    }
  ])
  |> json.to_string
}

pub fn encode_read_keys_command(
  keys: List(String),
  db_path: Option(String),
) -> String {
  json.object([
    #("command", json.string("read_keys")),
    #("keys", json.array(keys, json.string)),
    ..case db_path {
      Some(p) -> [#("db_path", json.string(p))]
      None -> []
    }
  ])
  |> json.to_string
}

pub fn encode_read_inbox_index_command(
  limit: Int,
  after_key: Option(String),
  db_path: Option(String),
) -> String {
  json.object([
    #("command", json.string("read_inbox_index")),
    #("limit", json.int(limit)),
    ..case after_key {
      Some(ak) -> [#("after_key", json.string(ak))]
      None -> []
    }
    |> list.append(case db_path {
      Some(p) -> [#("db_path", json.string(p))]
      None -> []
    })
  ])
  |> json.to_string
}

pub fn encode_lookup_operation_command(
  operation_id: String,
  db_path: Option(String),
) -> String {
  json.object([
    #("command", json.string("lookup_operation")),
    #("operation_id", json.string(operation_id)),
    ..case db_path {
      Some(p) -> [#("db_path", json.string(p))]
      None -> []
    }
  ])
  |> json.to_string
}

pub fn encode_apply_command(
  bot_id: Int,
  operation_id: String,
  request_digest: String,
  expected_generation: Int,
  read_set: List(ReadSetAssertion),
  changes: List(Change),
  res_delta: ReservationDelta,
  summary_json: String,
  db_path: Option(String),
) -> String {
  json.object([
    #("command", json.string("apply")),
    #("bot_id", json.string(int.to_string(bot_id))),
    #("operation_id", json.string(operation_id)),
    #("request_digest", json.string(request_digest)),
    #("expected_generation", json.int(expected_generation)),
    #(
      "read_set_assertions",
      json.array(read_set, fn(a) {
        json.object([
          #("key", json.string(a.key)),
          #("expected_version", json.int(a.expected_version)),
          #("expected_sha256", json.string(a.expected_sha256)),
        ])
      }),
    ),
    #(
      "changes",
      json.array(changes, fn(c) {
        json.object([
          #("key", json.string(c.key)),
          #("expected_version", json.int(c.expected_version)),
          #("expected_sha256", json.string(c.expected_sha256)),
          #("new_value_base64", json.string(c.new_value_base64)),
        ])
      }),
    ),
    #(
      "reservation_delta",
      json.object([
        #("rows", json.int(res_delta.rows)),
        #("receipts", json.int(res_delta.receipts)),
      ]),
    ),
    #("summary_json", json.string(summary_json)),
    ..case db_path {
      Some(p) -> [#("db_path", json.string(p))]
      None -> []
    }
  ])
  |> json.to_string
}

// -----------------------------------------------------------------------------
// Response Decoders
// -----------------------------------------------------------------------------

pub fn is_whitelisted_backend_error(code: String) -> Bool {
  case code {
    "aggregate_values_too_large"
    | "bot_id_mismatch"
    | "capacity_exhausted"
    | "cas_conflict"
    | "changes_too_many"
    | "commit_uncertain"
    | "corrupt_row_hash"
    | "db_already_exists"
    | "db_directory_insecure"
    | "db_file_insecure"
    | "db_file_replaced"
    | "db_locked"
    | "db_not_found"
    | "db_path_invalid"
    | "db_path_mismatch"
    | "db_path_symlink"
    | "duplicate_change_key"
    | "duplicate_json_keys"
    | "duplicate_read_set_key"
    | "expected_colon"
    | "expected_comma_or_brace"
    | "expected_comma_or_bracket"
    | "expected_string_key"
    | "fsync_failed"
    | "invalid_after_key"
    | "invalid_base64"
    | "invalid_bot_id"
    | "invalid_change"
    | "invalid_escape"
    | "invalid_exponent"
    | "invalid_journal_mode"
    | "invalid_json"
    | "invalid_limit"
    | "invalid_literal"
    | "invalid_number"
    | "invalid_operation_id"
    | "invalid_read_set_assertion"
    | "invalid_reservation_delta"
    | "invalid_token"
    | "invalid_unicode_escape"
    | "invalid_utf8"
    | "invalid_value"
    | "json_array_too_long"
    | "json_nesting_depth_exceeded"
    | "json_node_budget_exceeded"
    | "json_object_too_wide"
    | "key_too_long"
    | "leading_zero_number"
    | "lone_surrogate"
    | "operation_collision_digest_mismatch"
    | "pragma_verification_failed"
    | "read_keys_too_many"
    | "read_set_conflict"
    | "read_set_too_many"
    | "receipt_too_large"
    | "request_digest_invalid"
    | "request_digest_mismatch"
    | "schema_mismatch"
    | "simulated_before_commit_failure"
    | "sqlite_busy"
    | "sqlite_error"
    | "stale_generation"
    | "trailing_comma"
    | "trailing_decimal_point"
    | "trailing_garbage"
    | "unescaped_control_char"
    | "unexpected_eof"
    | "unknown_json_field"
    | "unterminated_escape"
    | "unterminated_string"
    | "value_too_large" -> True
    _ -> False
  }
}

pub type StrictJsonValue {
  JsonObject(List(#(String, StrictJsonValue)))
  JsonArray(List(StrictJsonValue))
  JsonString(String)
  JsonInt(Int)
  JsonFloat(Float)
  JsonBool(Bool)
  JsonNull
}

@external(erlang, "telegram_store_codec_ffi", "parse_strict")
pub fn parse_strict_json(json_str: String) -> Result(StrictJsonValue, String)

fn get_field(
  obj: List(#(String, StrictJsonValue)),
  key: String,
) -> Result(StrictJsonValue, String) {
  case list.key_find(obj, key) {
    Ok(val) -> Ok(val)
    Error(_) -> Error("missing_field: " <> key)
  }
}

fn check_exact_fields(
  obj: List(#(String, StrictJsonValue)),
  allowed: List(String),
) -> Result(Nil, String) {
  let all_allowed = list.all(obj, fn(pair) { list.contains(allowed, pair.0) })
  case all_allowed {
    True -> Ok(Nil)
    False -> Error("unknown_json_field")
  }
}

fn as_bool(val: StrictJsonValue) -> Result(Bool, String) {
  case val {
    JsonBool(b) -> Ok(b)
    _ -> Error("expected_bool")
  }
}

fn as_int(val: StrictJsonValue) -> Result(Int, String) {
  case val {
    JsonInt(i) -> Ok(i)
    _ -> Error("expected_int")
  }
}

fn as_string(val: StrictJsonValue) -> Result(String, String) {
  case val {
    JsonString(s) -> Ok(s)
    _ -> Error("expected_string")
  }
}

fn as_object(
  val: StrictJsonValue,
) -> Result(List(#(String, StrictJsonValue)), String) {
  case val {
    JsonObject(fields) -> Ok(fields)
    _ -> Error("expected_object")
  }
}

fn as_array(val: StrictJsonValue) -> Result(List(StrictJsonValue), String) {
  case val {
    JsonArray(elems) -> Ok(elems)
    _ -> Error("expected_array")
  }
}

fn parse_response_root(
  json_str: String,
  allowed_success_fields: List(String),
) -> Result(#(Bool, List(#(String, StrictJsonValue))), String) {
  use root <- result.try(parse_strict_json(json_str))
  use fields <- result.try(as_object(root))
  use ok_val <- result.try(get_field(fields, "ok"))
  use ok_bool <- result.try(as_bool(ok_val))
  case ok_bool {
    True -> {
      use _ <- result.try(check_exact_fields(fields, allowed_success_fields))
      Ok(#(True, fields))
    }
    False -> {
      use _ <- result.try(check_exact_fields(fields, ["ok", "error"]))
      use err_val <- result.try(get_field(fields, "error"))
      use err_str <- result.try(as_string(err_val))
      case is_whitelisted_backend_error(err_str) {
        True -> Error(err_str)
        False -> Error("unwhitelisted_backend_error")
      }
    }
  }
}

pub fn decode_initialize_new_response(json_str: String) -> Result(Int, String) {
  use #(_, fields) <- result.try(
    parse_response_root(json_str, ["ok", "generation"])
    |> result.map_error(fn(err) {
      case is_whitelisted_backend_error(err) {
        True -> err
        False -> "invalid_initialize_response"
      }
    }),
  )
  use gen_val <- result.try(
    get_field(fields, "generation")
    |> result.map_error(fn(_) { "invalid_initialize_response" }),
  )
  use gen <- result.try(
    as_int(gen_val)
    |> result.map_error(fn(_) { "invalid_initialize_response" }),
  )
  case gen > 0 {
    True -> Ok(gen)
    False -> Error("invalid_initialize_response")
  }
}

pub fn decode_read_keys_response(
  json_str: String,
) -> Result(#(Int, List(RowResult)), String) {
  use #(_, fields) <- result.try(
    parse_response_root(json_str, ["ok", "generation", "rows"])
    |> result.map_error(fn(err) {
      case is_whitelisted_backend_error(err) {
        True -> err
        False -> "invalid_read_keys_response"
      }
    }),
  )
  use gen_val <- result.try(
    get_field(fields, "generation")
    |> result.map_error(fn(_) { "invalid_read_keys_response" }),
  )
  use gen <- result.try(
    as_int(gen_val)
    |> result.map_error(fn(_) { "invalid_read_keys_response" }),
  )
  use _ <- result.try(case gen > 0 {
    True -> Ok(Nil)
    False -> Error("invalid_read_keys_response")
  })
  use rows_val <- result.try(
    get_field(fields, "rows")
    |> result.map_error(fn(_) { "invalid_read_keys_response" }),
  )
  use rows_list <- result.try(
    as_array(rows_val)
    |> result.map_error(fn(_) { "invalid_read_keys_response" }),
  )
  let decoded_rows =
    list.try_map(rows_list, fn(row_item) {
      use r_fields <- result.try(
        as_object(row_item)
        |> result.map_error(fn(_) { "invalid_read_keys_response" }),
      )
      use _ <- result.try(
        check_exact_fields(r_fields, [
          "key",
          "exists",
          "version",
          "canonical_value_base64",
          "sha256",
        ])
        |> result.map_error(fn(_) { "invalid_read_keys_response" }),
      )
      use k_val <- result.try(
        get_field(r_fields, "key")
        |> result.map_error(fn(_) { "invalid_read_keys_response" }),
      )
      use k <- result.try(
        as_string(k_val)
        |> result.map_error(fn(_) { "invalid_read_keys_response" }),
      )
      use ex_val <- result.try(
        get_field(r_fields, "exists")
        |> result.map_error(fn(_) { "invalid_read_keys_response" }),
      )
      use ex <- result.try(
        as_bool(ex_val)
        |> result.map_error(fn(_) { "invalid_read_keys_response" }),
      )
      use v_val <- result.try(
        get_field(r_fields, "version")
        |> result.map_error(fn(_) { "invalid_read_keys_response" }),
      )
      use v <- result.try(
        as_int(v_val)
        |> result.map_error(fn(_) { "invalid_read_keys_response" }),
      )
      use b64_val <- result.try(
        get_field(r_fields, "canonical_value_base64")
        |> result.map_error(fn(_) { "invalid_read_keys_response" }),
      )
      use b64 <- result.try(
        as_string(b64_val)
        |> result.map_error(fn(_) { "invalid_read_keys_response" }),
      )
      use sha_val <- result.try(
        get_field(r_fields, "sha256")
        |> result.map_error(fn(_) { "invalid_read_keys_response" }),
      )
      use sha <- result.try(
        as_string(sha_val)
        |> result.map_error(fn(_) { "invalid_read_keys_response" }),
      )
      let r =
        RowResult(
          key: k,
          exists: ex,
          version: v,
          canonical_value_base64: b64,
          sha256: sha,
        )
      validate_row_result(r)
      |> result.map_error(fn(_) { "invalid_read_keys_response" })
    })
  use rows <- result.try(decoded_rows)
  Ok(#(gen, rows))
}

pub fn decode_read_inbox_index_response(
  json_str: String,
) -> Result(#(Int, List(String)), String) {
  use #(_, fields) <- result.try(
    parse_response_root(json_str, ["ok", "generation", "keys"])
    |> result.map_error(fn(err) {
      case is_whitelisted_backend_error(err) {
        True -> err
        False -> "invalid_read_inbox_index_response"
      }
    }),
  )
  use gen_val <- result.try(
    get_field(fields, "generation")
    |> result.map_error(fn(_) { "invalid_read_inbox_index_response" }),
  )
  use gen <- result.try(
    as_int(gen_val)
    |> result.map_error(fn(_) { "invalid_read_inbox_index_response" }),
  )
  use _ <- result.try(case gen > 0 {
    True -> Ok(Nil)
    False -> Error("invalid_read_inbox_index_response")
  })
  use keys_val <- result.try(
    get_field(fields, "keys")
    |> result.map_error(fn(_) { "invalid_read_inbox_index_response" }),
  )
  use keys_list <- result.try(
    as_array(keys_val)
    |> result.map_error(fn(_) { "invalid_read_inbox_index_response" }),
  )
  use keys <- result.try(
    list.try_map(keys_list, fn(k) {
      as_string(k)
      |> result.map_error(fn(_) { "invalid_read_inbox_index_response" })
    }),
  )
  Ok(#(gen, keys))
}

fn decode_receipt_object(val: StrictJsonValue) -> Result(Receipt, String) {
  use r_fields <- result.try(as_object(val))
  use _ <- result.try(
    check_exact_fields(r_fields, [
      "operation_id",
      "request_digest",
      "generation",
      "summary_json",
      "committed_utc_us",
    ]),
  )
  use op_val <- result.try(get_field(r_fields, "operation_id"))
  use op_id <- result.try(as_string(op_val))
  use dig_val <- result.try(get_field(r_fields, "request_digest"))
  use req_digest <- result.try(as_string(dig_val))
  use gen_val <- result.try(get_field(r_fields, "generation"))
  use gen <- result.try(as_int(gen_val))
  use sum_val <- result.try(get_field(r_fields, "summary_json"))
  use summary <- result.try(as_string(sum_val))
  use ts_val <- result.try(get_field(r_fields, "committed_utc_us"))
  use committed_ts <- result.try(as_int(ts_val))
  case
    string.byte_size(op_id) > 0
    && string.byte_size(op_id) <= max_operation_id_bytes
    && guard.valid_digest(req_digest)
    && gen > 0
    && committed_ts > 0
  {
    True -> {
      use _ <- result.try(
        parse_strict_json(summary)
        |> result.map_error(fn(_) { "invalid_summary_json" }),
      )
      Ok(Receipt(
        operation_id: op_id,
        request_digest: req_digest,
        generation: gen,
        summary_json: summary,
        committed_utc_us: committed_ts,
      ))
    }
    False -> Error("invalid_receipt_fields")
  }
}

pub fn decode_lookup_operation_response(
  json_str: String,
) -> Result(LookupResult, String) {
  use #(_, fields) <- result.try(
    parse_response_root(json_str, ["ok", "found", "receipt"])
    |> result.map_error(fn(err) {
      case
        is_whitelisted_backend_error(err)
        || err == "unwhitelisted_backend_error"
      {
        True -> err
        False -> "invalid_lookup_operation_response"
      }
    }),
  )
  use found_val <- result.try(
    get_field(fields, "found")
    |> result.map_error(fn(_) { "invalid_lookup_operation_response" }),
  )
  use found <- result.try(
    as_bool(found_val)
    |> result.map_error(fn(_) { "invalid_lookup_operation_response" }),
  )
  case found {
    False -> {
      use _ <- result.try(
        check_exact_fields(fields, ["ok", "found"])
        |> result.map_error(fn(_) { "invalid_lookup_operation_response" }),
      )
      Ok(LookupResult(found: False, receipt: None))
    }
    True -> {
      use _ <- result.try(
        check_exact_fields(fields, ["ok", "found", "receipt"])
        |> result.map_error(fn(_) { "invalid_lookup_operation_response" }),
      )
      use r_val <- result.try(
        get_field(fields, "receipt")
        |> result.map_error(fn(_) { "invalid_lookup_operation_response" }),
      )
      use receipt <- result.try(
        decode_receipt_object(r_val)
        |> result.map_error(fn(_) { "invalid_lookup_operation_response" }),
      )
      Ok(LookupResult(found: True, receipt: Some(receipt)))
    }
  }
}

pub type DecodedApplyResponse {
  DecodedApplySuccess(ApplyResult)
  DecodedApplyRefusal(code: String)
  DecodedApplyDecodeError(reason: String)
}

pub fn decode_apply_response_discriminated(
  json_str: String,
) -> DecodedApplyResponse {
  case parse_strict_json(json_str) {
    Error(err) -> DecodedApplyDecodeError("invalid_json: " <> err)
    Ok(root) ->
      case as_object(root) {
        Error(err) -> DecodedApplyDecodeError(err)
        Ok(fields) ->
          case get_field(fields, "ok") {
            Error(err) -> DecodedApplyDecodeError(err)
            Ok(ok_val) ->
              case as_bool(ok_val) {
                Error(err) -> DecodedApplyDecodeError(err)
                Ok(True) ->
                  case check_exact_fields(fields, ["ok", "replay", "receipt"]) {
                    Error(err) -> DecodedApplyDecodeError(err)
                    Ok(_) ->
                      case
                        get_field(fields, "replay"),
                        get_field(fields, "receipt")
                      {
                        Ok(rep_val), Ok(rec_val) ->
                          case
                            as_bool(rep_val),
                            decode_receipt_object(rec_val)
                          {
                            Ok(rep), Ok(rec) ->
                              DecodedApplySuccess(ApplyResult(
                                replay: rep,
                                receipt: rec,
                              ))
                            _, _ ->
                              DecodedApplyDecodeError(
                                "invalid_apply_success_fields",
                              )
                          }
                        _, _ ->
                          DecodedApplyDecodeError(
                            "missing_apply_success_fields",
                          )
                      }
                  }
                Ok(False) ->
                  case check_exact_fields(fields, ["ok", "error"]) {
                    Error(err) -> DecodedApplyDecodeError(err)
                    Ok(_) ->
                      case get_field(fields, "error") {
                        Error(err) -> DecodedApplyDecodeError(err)
                        Ok(err_val) ->
                          case as_string(err_val) {
                            Error(err) -> DecodedApplyDecodeError(err)
                            Ok(code) ->
                              case is_whitelisted_backend_error(code) {
                                True -> DecodedApplyRefusal(code)
                                False ->
                                  DecodedApplyDecodeError(
                                    "unwhitelisted_backend_error: " <> code,
                                  )
                              }
                          }
                      }
                  }
              }
          }
      }
  }
}

pub fn decode_apply_response(json_str: String) -> Result(ApplyResult, String) {
  case decode_apply_response_discriminated(json_str) {
    DecodedApplySuccess(res) -> Ok(res)
    DecodedApplyRefusal(code) -> Error(code)
    DecodedApplyDecodeError(reason) -> {
      case string.starts_with(reason, "unwhitelisted_backend_error") {
        True -> Error("unwhitelisted_backend_error")
        False -> Error("invalid_apply_response")
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Domain Value Serialization (Strict JSON + RFC 8259 Standard Objects)
// -----------------------------------------------------------------------------

// 1. Watermark ("meta/next_offset")
pub fn watermark_key() -> String {
  "meta/next_offset"
}

pub fn encode_watermark_value(wm: ledger.Watermark) -> String {
  json.object([
    #("schema", json.string("uos.telegram-watermark.v1")),
    #("last_committed_offset", json.int(wm.last_committed_offset)),
  ])
  |> json.to_string
}

pub fn valid_request_id(
  request_id: String,
  bot_id: Int,
  update_id: Int,
) -> Bool {
  guard.valid_positive_id(bot_id)
  && guard.valid_update_id(update_id)
  && request_id == ledger.make_request_id(bot_id, update_id)
}

pub fn valid_authority_request_id(request_id: String, bot_id: Int) -> Bool {
  case string.split(request_id, "-") {
    ["tg", b_str, u_str] -> {
      case int.parse(b_str), int.parse(u_str) {
        Ok(b), Ok(u) ->
          b == bot_id
          && guard.valid_positive_id(b)
          && guard.valid_update_id(u)
          && request_id == ledger.make_request_id(b, u)
        _, _ -> False
      }
    }
    _ -> False
  }
}

pub fn decode_watermark_value(
  json_str: String,
) -> Result(ledger.Watermark, String) {
  let decoder = {
    use schema <- decode.field("schema", decode.string)
    use offset <- decode.field("last_committed_offset", decode.int)
    case
      schema == "uos.telegram-watermark.v1"
      && offset >= 0
      && offset <= guard.max_update_id + 1
    {
      True -> decode.success(ledger.Watermark(offset))
      False -> decode.failure(ledger.Watermark(0), "invalid_watermark_schema")
    }
  }
  json.parse(json_str, decoder)
  |> result.map_error(fn(_) { "invalid_watermark_payload" })
}

// 2. Bot Identity ("meta/bot_identity")
pub fn bot_identity_key() -> String {
  "meta/bot_identity"
}

pub fn encode_bot_identity_value(bot_id: Int) -> String {
  json.object([
    #("schema", json.string("uos.telegram-bot-identity.v1")),
    #("bot_id", json.int(bot_id)),
  ])
  |> json.to_string
}

pub fn decode_bot_identity_value(json_str: String) -> Result(Int, String) {
  let decoder = {
    use schema <- decode.field("schema", decode.string)
    use bot_id <- decode.field("bot_id", decode.int)
    case
      schema == "uos.telegram-bot-identity.v1"
      && guard.valid_positive_id(bot_id)
    {
      True -> decode.success(bot_id)
      False -> decode.failure(0, "invalid_bot_identity_schema")
    }
  }
  json.parse(json_str, decoder)
  |> result.map_error(fn(_) { "invalid_bot_identity_payload" })
}

// 3. Inbox Record ("inbox/<request_id>")
pub fn inbox_key(request_id: String) -> String {
  "inbox/" <> request_id
}

fn encode_inbox_status(st: ledger.InboxStatus) -> json.Json {
  case st {
    ledger.InboxPending -> json.object([#("tag", json.string("pending"))])
    ledger.InboxProcessing(w, e) ->
      json.object([
        #("tag", json.string("processing")),
        #("worker", json.string(w)),
        #("epoch", json.int(e)),
      ])
    ledger.InboxResultReady(d) ->
      json.object([
        #("tag", json.string("result_ready")),
        #("digest", json.string(d)),
      ])
    ledger.InboxCompleted(d) ->
      json.object([
        #("tag", json.string("completed")),
        #("digest", json.string(d)),
      ])
    ledger.InboxRejected(r) ->
      json.object([
        #("tag", json.string("rejected")),
        #("reason", json.string(r)),
      ])
    ledger.InboxHold(r) ->
      json.object([
        #("tag", json.string("hold")),
        #("reason", json.string(r)),
      ])
  }
}

fn inbox_status_decoder() -> decode.Decoder(ledger.InboxStatus) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "pending" -> decode.success(ledger.InboxPending)
    "processing" -> {
      use w <- decode.field("worker", decode.string)
      use e <- decode.field("epoch", decode.int)
      case ledger.valid_worker(w, e) {
        True -> decode.success(ledger.InboxProcessing(w, e))
        False -> decode.failure(ledger.InboxPending, "invalid_worker_epoch")
      }
    }
    "result_ready" -> {
      use d <- decode.field("digest", decode.string)
      case guard.valid_digest(d) {
        True -> decode.success(ledger.InboxResultReady(d))
        False ->
          decode.failure(ledger.InboxPending, "invalid_result_ready_digest")
      }
    }
    "completed" -> {
      use d <- decode.field("digest", decode.string)
      case guard.valid_digest(d) {
        True -> decode.success(ledger.InboxCompleted(d))
        False -> decode.failure(ledger.InboxPending, "invalid_completed_digest")
      }
    }
    "rejected" -> {
      use r <- decode.field("reason", decode.string)
      case r != "" && string.byte_size(r) <= 128 {
        True -> decode.success(ledger.InboxRejected(r))
        False -> decode.failure(ledger.InboxPending, "invalid_rejected_reason")
      }
    }
    "hold" -> {
      use r <- decode.field("reason", decode.string)
      case r != "" && string.byte_size(r) <= 128 {
        True -> decode.success(ledger.InboxHold(r))
        False -> decode.failure(ledger.InboxPending, "invalid_hold_reason")
      }
    }
    _ -> decode.failure(ledger.InboxPending, "unknown_inbox_status_tag")
  }
}

pub fn encode_inbox_record(r: ledger.InboxRecord) -> String {
  json.object([
    #("schema", json.string("uos.telegram-inbox-record.v2")),
    #("request_id", json.string(r.request_id)),
    #("bot_id", json.int(r.bot_id)),
    #("update_id", json.int(r.update_id)),
    #("message_id", json.int(r.message_id)),
    #("chat_id", json.int(r.chat_id)),
    #("user_id", json.int(r.user_id)),
    #("text_hash", json.string(r.text_hash)),
    #("status", encode_inbox_status(r.status)),
    #("created_at_ms", json.int(r.created_at_ms)),
  ])
  |> json.to_string
}

pub fn decode_inbox_record(
  json_str: String,
) -> Result(ledger.InboxRecord, String) {
  let decoder = {
    use schema <- decode.field("schema", decode.string)
    use req_id <- decode.field("request_id", decode.string)
    use bot <- decode.field("bot_id", decode.int)
    use upd <- decode.field("update_id", decode.int)
    use msg <- decode.field("message_id", decode.int)
    use chat <- decode.field("chat_id", decode.int)
    use usr <- decode.field("user_id", decode.int)
    use hash <- decode.field("text_hash", decode.string)
    use st <- decode.field("status", inbox_status_decoder())
    use ts <- decode.field("created_at_ms", decode.int)

    let record =
      ledger.InboxRecord(
        update_id: upd,
        message_id: msg,
        chat_id: chat,
        user_id: usr,
        text_hash: hash,
        status: st,
        created_at_ms: ts,
        bot_id: bot,
        request_id: req_id,
      )
    case
      schema == "uos.telegram-inbox-record.v2"
      && ledger.valid_record(record)
      && case st {
        ledger.InboxRejected("withdrawn_by_requester") ->
          guard.valid_positive_id(msg) && guard.valid_chat_id(chat) && guard.valid_positive_id(usr)
        ledger.InboxRejected(_) -> msg == 0 && chat == 0 && usr == 0
        _ -> True
      }
    {
      True -> decode.success(record)
      False ->
        decode.failure(
          ledger.InboxRecord(0, 0, 0, 0, "", ledger.InboxPending, 0, 0, ""),
          "invalid_inbox_record_domain",
        )
    }
  }
  json.parse(json_str, decoder)
  |> result.map_error(fn(_) { "invalid_inbox_record_payload" })
}

// 4. Raw Ingress Input ("request/<request_id>/input")
pub fn input_key(request_id: String) -> String {
  "request/" <> request_id <> "/input"
}

fn encode_directive(d: guard.ParsedDirective) -> json.Json {
  case d {
    guard.DirectReadTool(t) ->
      json.object([
        #("tag", json.string("direct_read")),
        #("tool", json.string(t)),
      ])
    guard.PreservedDirective(n, args) ->
      json.object([
        #("tag", json.string("preserved")),
        #("name", json.string(n)),
        #("args", json.array(args, json.string)),
      ])
    guard.DeniedMutation(t, r) ->
      json.object([
        #("tag", json.string("denied")),
        #("tool", json.string(t)),
        #("reason", json.string(r)),
      ])
    guard.UnknownDirective(n) ->
      json.object([
        #("tag", json.string("unknown")),
        #("name", json.string(n)),
      ])
  }
}

fn directive_decoder() -> decode.Decoder(guard.ParsedDirective) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "direct_read" -> {
      use t <- decode.field("tool", decode.string)
      decode.success(guard.DirectReadTool(t))
    }
    "preserved" -> {
      use n <- decode.field("name", decode.string)
      use args <- decode.field("args", decode.list(decode.string))
      decode.success(guard.PreservedDirective(n, args))
    }
    "denied" -> {
      use t <- decode.field("tool", decode.string)
      use r <- decode.field("reason", decode.string)
      decode.success(guard.DeniedMutation(t, r))
    }
    "unknown" -> {
      use n <- decode.field("name", decode.string)
      decode.success(guard.UnknownDirective(n))
    }
    _ -> decode.failure(guard.UnknownDirective(""), "unknown_directive_tag")
  }
}

pub fn encode_input_verdict(
  request_id: String,
  bot_id: Int,
  update_id: Int,
  v: guard.IngressVerdict,
) -> String {
  json.object([
    #("schema", json.string("uos.telegram-input.v2")),
    #("request_id", json.string(request_id)),
    #("bot_id", json.int(bot_id)),
    #("update_id", json.int(update_id)),
    #("verdict", case v {
      guard.AcceptedEnvelope(
        update_id: _,
        message_id: mid,
        chat_id: cid,
        user_id: uid_usr,
        text_hash: hash,
        raw_text: txt,
        directive: dir,
        bot_id: _,
        callback_query_id: cb_id_opt,
      ) -> {
        let base_fields = [
          #("tag", json.string("accepted")),
          #("message_id", json.int(mid)),
          #("chat_id", json.int(cid)),
          #("user_id", json.int(uid_usr)),
          #("text_hash", json.string(hash)),
          #("raw_text", json.string(txt)),
          #("directive", encode_directive(dir)),
        ]
        let fields = case cb_id_opt {
          Some(cb_id) -> [
            #("callback_query_id", json.string(cb_id)),
            ..base_fields
          ]
          None -> base_fields
        }
        json.object(fields)
      }
      guard.RejectedUpdate(
        update_id: _,
        bot_id: _,
        envelope_hash: hash,
        reason: r,
      ) ->
        json.object([
          #("tag", json.string("rejected")),
          #("envelope_hash", json.string(hash)),
          #("reason", json.string(r)),
        ])
      guard.UnidentifiedRejection(reason: r) ->
        json.object([
          #("tag", json.string("unidentified")),
          #("reason", json.string(r)),
        ])
    }),
  ])
  |> json.to_string
}

pub fn decode_input_verdict(
  json_str: String,
) -> Result(#(String, Int, Int, guard.IngressVerdict), String) {
  let verdict_decoder = fn(upd: Int, bot: Int) {
    use tag <- decode.field("tag", decode.string)
    case tag {
      "accepted" -> {
        use mid <- decode.field("message_id", decode.int)
        use cid <- decode.field("chat_id", decode.int)
        use uid_usr <- decode.field("user_id", decode.int)
        use hash <- decode.field("text_hash", decode.string)
        use txt <- decode.field("raw_text", decode.string)
        use dir <- decode.field("directive", directive_decoder())
        use cb_id_opt <- decode.optional_field(
          "callback_query_id",
          None,
          decode.optional(decode.string),
        )
        case
          guard.valid_positive_id(mid)
          && guard.valid_chat_id(cid)
          && guard.valid_positive_id(uid_usr)
          && guard.valid_digest(hash)
          && guard.valid_text(txt)
          && files.digest(txt) == hash
          && dir == guard.classify_directive(txt)
          && case cb_id_opt {
            None -> True
            Some(id) -> id != "" && string.byte_size(id) <= 128
          }
        {
          True ->
            decode.success(guard.AcceptedEnvelope(
              update_id: upd,
              message_id: mid,
              chat_id: cid,
              user_id: uid_usr,
              text_hash: hash,
              raw_text: txt,
              directive: dir,
              bot_id: bot,
              callback_query_id: cb_id_opt,
            ))
          False ->
            decode.failure(
              guard.UnidentifiedRejection(""),
              "invalid_accepted_envelope_domain",
            )
        }
      }
      "rejected" -> {
        use hash <- decode.field("envelope_hash", decode.string)
        use r <- decode.field("reason", decode.string)
        case guard.valid_digest(hash) && r != "" && string.byte_size(r) <= 128 {
          True ->
            decode.success(guard.RejectedUpdate(
              update_id: upd,
              bot_id: bot,
              envelope_hash: hash,
              reason: r,
            ))
          False ->
            decode.failure(
              guard.UnidentifiedRejection(""),
              "invalid_rejected_update_domain",
            )
        }
      }
      "unidentified" -> {
        use r <- decode.field("reason", decode.string)
        case r != "" && string.byte_size(r) <= 128 {
          True -> decode.success(guard.UnidentifiedRejection(r))
          False ->
            decode.failure(
              guard.UnidentifiedRejection(""),
              "invalid_unidentified_domain",
            )
        }
      }
      _ ->
        decode.failure(
          guard.UnidentifiedRejection(""),
          "unknown_input_verdict_tag",
        )
    }
  }

  let decoder = {
    use schema <- decode.field("schema", decode.string)
    use req_id <- decode.field("request_id", decode.string)
    use bot <- decode.field("bot_id", decode.int)
    use upd <- decode.field("update_id", decode.int)
    use v <- decode.field("verdict", verdict_decoder(upd, bot))
    case
      schema == "uos.telegram-input.v2" && valid_request_id(req_id, bot, upd)
    {
      True -> decode.success(#(req_id, bot, upd, v))
      False ->
        decode.failure(
          #("", 0, 0, guard.UnidentifiedRejection("")),
          "invalid_input_verdict_schema",
        )
    }
  }
  json.parse(json_str, decoder)
  |> result.map_error(fn(_) { "invalid_input_verdict_payload" })
}

// 5. Task Authority ("request/<request_id>/authority")
pub fn authority_key(request_id: String) -> String {
  "request/" <> request_id <> "/authority"
}

pub fn encode_authority_value(a: AuthorityRecord) -> String {
  json.object([
    #("schema", json.string("uos.telegram-authority.v2")),
    #("request_id", json.string(a.request_id)),
    #("bot_id", json.int(a.bot_id)),
    #("worker", json.string(a.worker)),
    #("epoch", json.int(a.epoch)),
    #("granted_at_ms", json.int(a.granted_at_ms)),
  ])
  |> json.to_string
}

pub fn decode_authority_value(
  json_str: String,
) -> Result(AuthorityRecord, String) {
  let decoder = {
    use schema <- decode.field("schema", decode.string)
    use req_id <- decode.field("request_id", decode.string)
    use bot <- decode.field("bot_id", decode.int)
    use worker <- decode.field("worker", decode.string)
    use epoch <- decode.field("epoch", decode.int)
    use ts <- decode.field("granted_at_ms", decode.int)
    case
      schema == "uos.telegram-authority.v2"
      && guard.valid_positive_id(bot)
      && valid_authority_request_id(req_id, bot)
      && ledger.valid_worker(worker, epoch)
      && ts > 0
      && ts <= guard.max_identity
    {
      True ->
        decode.success(AuthorityRecord(
          request_id: req_id,
          bot_id: bot,
          worker: worker,
          epoch: epoch,
          granted_at_ms: ts,
        ))
      False ->
        decode.failure(
          AuthorityRecord("", 0, "", 0, 0),
          "invalid_authority_record_schema",
        )
    }
  }
  json.parse(json_str, decoder)
  |> result.map_error(fn(_) { "invalid_authority_record_payload" })
}

// 6. Result Metadata ("request/<request_id>/result")
pub fn result_key(request_id: String) -> String {
  "request/" <> request_id <> "/result"
}

pub fn encode_result_value(rm: ResultMeta) -> String {
  json.object([
    #("schema", json.string("uos.telegram-result-meta.v2")),
    #("request_id", json.string(rm.request_id)),
    #("bot_id", json.int(rm.bot_id)),
    #("chat_id", json.int(rm.chat_id)),
    #("update_id", json.int(rm.update_id)),
    #("message_id", json.int(rm.message_id)),
    #("user_id", json.int(rm.user_id)),
    #("text_hash", json.string(rm.text_hash)),
    #("created_at_ms", json.int(rm.created_at_ms)),
    #("digest", json.string(rm.digest)),
    #("total_chunks", json.int(rm.total_chunks)),
  ])
  |> json.to_string
}

pub fn decode_result_value(json_str: String) -> Result(ResultMeta, String) {
  let decoder = {
    use schema <- decode.field("schema", decode.string)
    use req_id <- decode.field("request_id", decode.string)
    use bot <- decode.field("bot_id", decode.int)
    use chat <- decode.field("chat_id", decode.int)
    use upd <- decode.field("update_id", decode.int)
    use msg <- decode.field("message_id", decode.int)
    use usr <- decode.field("user_id", decode.int)
    use hash <- decode.field("text_hash", decode.string)
    use ts <- decode.field("created_at_ms", decode.int)
    use dig <- decode.field("digest", decode.string)
    use total <- decode.field("total_chunks", decode.int)
    case
      schema == "uos.telegram-result-meta.v2"
      && valid_request_id(req_id, bot, upd)
      && guard.valid_chat_id(chat)
      && guard.valid_positive_id(msg)
      && guard.valid_positive_id(usr)
      && guard.valid_digest(hash)
      && ts > 0
      && ts <= guard.max_identity
      && total > 0
      && total <= ledger.max_chunks
      && guard.valid_digest(dig)
    {
      True ->
        decode.success(ResultMeta(
          request_id: req_id,
          bot_id: bot,
          chat_id: chat,
          update_id: upd,
          message_id: msg,
          user_id: usr,
          text_hash: hash,
          created_at_ms: ts,
          digest: dig,
          total_chunks: total,
        ))
      False ->
        decode.failure(
          ResultMeta("", 0, 0, 0, 0, 0, "", 0, "", 0),
          "invalid_result_meta_schema",
        )
    }
  }
  json.parse(json_str, decoder)
  |> result.map_error(fn(_) { "invalid_result_meta_payload" })
}

// 7. Outbox Chunk ("request/<request_id>/chunk/<index>")
pub fn chunk_key(request_id: String, index: Int) -> String {
  "request/" <> request_id <> "/chunk/" <> int.to_string(index)
}

fn encode_outbox_status(st: ledger.OutboxStatus) -> json.Json {
  case st {
    ledger.OutboxPending -> json.object([#("tag", json.string("pending"))])
    ledger.OutboxSending(w, e) ->
      json.object([
        #("tag", json.string("sending")),
        #("worker", json.string(w)),
        #("epoch", json.int(e)),
      ])
    ledger.OutboxDelivered(id) ->
      json.object([
        #("tag", json.string("delivered")),
        #("telegram_msg_id", json.int(id)),
      ])
    ledger.OutboxFailed(err) ->
      json.object([
        #("tag", json.string("failed")),
        #("err", json.string(err)),
      ])
    ledger.OutboxUncertain(err) ->
      json.object([
        #("tag", json.string("uncertain")),
        #("err", json.string(err)),
      ])
  }
}

fn outbox_status_decoder() -> decode.Decoder(ledger.OutboxStatus) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "pending" -> decode.success(ledger.OutboxPending)
    "sending" -> {
      use w <- decode.field("worker", decode.string)
      use e <- decode.field("epoch", decode.int)
      case ledger.valid_worker(w, e) {
        True -> decode.success(ledger.OutboxSending(w, e))
        False ->
          decode.failure(ledger.OutboxPending, "invalid_outbox_sending_status")
      }
    }
    "delivered" -> {
      use id <- decode.field("telegram_msg_id", decode.int)
      case guard.valid_positive_id(id) {
        True -> decode.success(ledger.OutboxDelivered(id))
        False ->
          decode.failure(
            ledger.OutboxPending,
            "invalid_outbox_delivered_status",
          )
      }
    }
    "failed" -> {
      use err <- decode.field("err", decode.string)
      case err != "" && string.byte_size(err) <= 128 {
        True -> decode.success(ledger.OutboxFailed(err))
        False ->
          decode.failure(ledger.OutboxPending, "invalid_outbox_failed_status")
      }
    }
    "uncertain" -> {
      use err <- decode.field("err", decode.string)
      case err != "" && string.byte_size(err) <= 128 {
        True -> decode.success(ledger.OutboxUncertain(err))
        False ->
          decode.failure(
            ledger.OutboxPending,
            "invalid_outbox_uncertain_status",
          )
      }
    }
    _ -> decode.failure(ledger.OutboxPending, "unknown_outbox_status_tag")
  }
}

pub fn encode_chunk_value(c: ledger.OutboxChunk) -> String {
  json.object([
    #("schema", json.string("uos.telegram-chunk.v2")),
    #("request_id", json.string(c.request_id)),
    #("bot_id", json.int(c.bot_id)),
    #("chat_id", json.int(c.chat_id)),
    #("chunk_index", json.int(c.chunk_index)),
    #("total_chunks", json.int(c.total_chunks)),
    #("payload", json.string(c.payload)),
    #("result_digest", json.string(c.result_digest)),
    #("attempt_count", json.int(c.attempt_count)),
    #("status", encode_outbox_status(c.status)),
  ])
  |> json.to_string
}

pub fn decode_chunk_value(
  json_str: String,
) -> Result(ledger.OutboxChunk, String) {
  let decoder = {
    use schema <- decode.field("schema", decode.string)
    use req_id <- decode.field("request_id", decode.string)
    use bot <- decode.field("bot_id", decode.int)
    use chat <- decode.field("chat_id", decode.int)
    use idx <- decode.field("chunk_index", decode.int)
    use total <- decode.field("total_chunks", decode.int)
    use payload <- decode.field("payload", decode.string)
    use dig <- decode.field("result_digest", decode.string)
    use attempts <- decode.field("attempt_count", decode.int)
    use st <- decode.field("status", outbox_status_decoder())
    let chunk =
      ledger.OutboxChunk(
        request_id: req_id,
        chunk_index: idx,
        total_chunks: total,
        chat_id: chat,
        payload: payload,
        status: st,
        attempt_count: attempts,
        bot_id: bot,
        result_digest: dig,
      )
    case
      schema == "uos.telegram-chunk.v2"
      && valid_authority_request_id(req_id, bot)
      && ledger.valid_chunk(chunk)
    {
      True -> decode.success(chunk)
      False ->
        decode.failure(
          ledger.OutboxChunk("", 0, 0, 0, "", ledger.OutboxPending, 0, 0, ""),
          "invalid_chunk_schema",
        )
    }
  }
  json.parse(json_str, decoder)
  |> result.map_error(fn(_) { "invalid_chunk_payload" })
}

const writer_registration_schema = "uos.telegram-writer-registration.v1"

const max_service_epoch = 2_147_483_647

const max_registered_at_us = 9_007_199_254_740_991

/// Storage identity codec record for Telegram writer registration.
/// `control_digest` is the SHA-256 of the exact canonical external ControlRegistration
/// binding unit/slice names and IDs, store path, and worker/guardian pins.
/// `instance_token` is a unique identity token (not a secret or authority bearer).
/// Full writer admission still requires live unit and current canonical task/runtime
/// lease checks, exclusive fresh-store proof for first boot, and verified prior cleanup
/// for recovery.
pub type WriterRegistration {
  WriterRegistration(
    bot_id: Int,
    service_epoch: Int,
    instance_token: String,
    control_digest: String,
    store_incarnation_id: String,
    unit_invocation_id: String,
    registered_at_us: Int,
  )
}

pub fn writer_registration_key() -> String {
  "meta/writer_registration"
}

fn is_valid_lowercase_hex_64(value: String) -> Bool {
  is_valid_hex_64(value) && string.lowercase(value) == value
}

fn is_valid_lowercase_hex_32(value: String) -> Bool {
  string.byte_size(value) == 32
  && is_valid_hex_64(value <> value)
  && string.lowercase(value) == value
}

pub fn validate_writer_registration(
  r: WriterRegistration,
) -> Result(Nil, String) {
  case guard.valid_positive_id(r.bot_id) {
    False -> Error("invalid_writer_registration_bot_id")
    True ->
      case r.service_epoch >= 1 && r.service_epoch <= max_service_epoch {
        False -> Error("invalid_writer_registration_service_epoch")
        True ->
          case is_valid_lowercase_hex_64(r.instance_token) {
            False -> Error("invalid_writer_registration_instance_token")
            True ->
              case is_valid_lowercase_hex_64(r.control_digest) {
                False -> Error("invalid_writer_registration_control_digest")
                True ->
                  case is_valid_lowercase_hex_64(r.store_incarnation_id) {
                    False ->
                      Error("invalid_writer_registration_store_incarnation_id")
                    True ->
                      case is_valid_lowercase_hex_32(r.unit_invocation_id) {
                        False ->
                          Error("invalid_writer_registration_unit_invocation_id")
                        True ->
                          case
                            r.registered_at_us >= 1
                            && r.registered_at_us <= max_registered_at_us
                          {
                            False ->
                              Error("invalid_writer_registration_registered_at_us")
                            True -> Ok(Nil)
                          }
                      }
                  }
              }
          }
      }
  }
}

pub fn encode_writer_registration(
  r: WriterRegistration,
) -> Result(String, String) {
  use _ <- result.try(validate_writer_registration(r))
  let encoded =
    json.object([
      #("schema", json.string(writer_registration_schema)),
      #("bot_id", json.int(r.bot_id)),
      #("service_epoch", json.int(r.service_epoch)),
      #("instance_token", json.string(r.instance_token)),
      #("control_digest", json.string(r.control_digest)),
      #("store_incarnation_id", json.string(r.store_incarnation_id)),
      #("unit_invocation_id", json.string(r.unit_invocation_id)),
      #("registered_at_us", json.int(r.registered_at_us)),
    ])
    |> json.to_string
  case string.byte_size(encoded) <= max_value_bytes {
    True -> Ok(encoded)
    False -> Error("writer_registration_value_too_large")
  }
}

fn writer_registration_decoder() -> decode.Decoder(#(String, WriterRegistration)) {
  use schema <- decode.field("schema", decode.string)
  use bot_id <- decode.field("bot_id", decode.int)
  use service_epoch <- decode.field("service_epoch", decode.int)
  use instance_token <- decode.field("instance_token", decode.string)
  use control_digest <- decode.field("control_digest", decode.string)
  use store_incarnation_id <- decode.field("store_incarnation_id", decode.string)
  use unit_invocation_id <- decode.field("unit_invocation_id", decode.string)
  use registered_at_us <- decode.field("registered_at_us", decode.int)
  decode.success(#(
    schema,
    WriterRegistration(
      bot_id: bot_id,
      service_epoch: service_epoch,
      instance_token: instance_token,
      control_digest: control_digest,
      store_incarnation_id: store_incarnation_id,
      unit_invocation_id: unit_invocation_id,
      registered_at_us: registered_at_us,
    ),
  ))
}

pub fn decode_writer_registration(
  raw: String,
) -> Result(WriterRegistration, String) {
  let size = string.byte_size(raw)
  case size > 0 && size <= max_value_bytes {
    False -> Error("invalid_writer_registration_payload_size")
    True ->
      case json.parse(raw, writer_registration_decoder()) {
        Error(_) -> Error("malformed_writer_registration_json")
        Ok(#(schema, registration)) ->
          case schema == writer_registration_schema {
            False -> Error("invalid_writer_registration_schema")
            True -> {
              use _ <- result.try(validate_writer_registration(registration))
              use canonical <- result.try(encode_writer_registration(registration))
              case raw == canonical {
                True -> Ok(registration)
                False -> Error("non_canonical_writer_registration_json")
              }
            }
          }
      }
  }
}

const prepared_writer_start_schema = "uos.telegram-writer-prepared.v1"

pub type PreparedWriterStart {
  PreparedWriterStart(
    previous: WriterRegistration,
    next: WriterRegistration,
  )
}

pub fn validate_writer_successor(
  previous: WriterRegistration,
  next: WriterRegistration,
) -> Result(Nil, String) {
  use _ <- result.try(validate_writer_registration(previous))
  use _ <- result.try(validate_writer_registration(next))
  case next.bot_id == previous.bot_id {
    False -> Error("writer_successor_bot_id_mismatch")
    True ->
      case next.store_incarnation_id == previous.store_incarnation_id {
        False -> Error("writer_successor_store_incarnation_mismatch")
        True ->
          case next.service_epoch == previous.service_epoch + 1 {
            False -> Error("invalid_writer_successor_service_epoch")
            True ->
              case next.instance_token != previous.instance_token {
                False -> Error("duplicate_writer_successor_instance_token")
                True ->
                  case next.unit_invocation_id != previous.unit_invocation_id {
                    False ->
                      Error("duplicate_writer_successor_unit_invocation_id")
                    True ->
                      case next.control_digest != previous.control_digest {
                        False ->
                          Error("duplicate_writer_successor_control_digest")
                        True ->
                          case
                            next.registered_at_us >= previous.registered_at_us
                          {
                            False ->
                              Error("writer_successor_registered_at_regression")
                            True -> Ok(Nil)
                          }
                      }
                  }
              }
          }
      }
  }
}

pub fn encode_prepared_writer_start(
  p: PreparedWriterStart,
) -> Result(String, String) {
  use _ <- result.try(validate_writer_successor(p.previous, p.next))
  use previous_json <- result.try(encode_writer_registration(p.previous))
  use next_json <- result.try(encode_writer_registration(p.next))
  let encoded =
    json.object([
      #("schema", json.string(prepared_writer_start_schema)),
      #("previous", json.string(previous_json)),
      #("next", json.string(next_json)),
    ])
    |> json.to_string
  case string.byte_size(encoded) <= max_value_bytes {
    True -> Ok(encoded)
    False -> Error("prepared_writer_start_value_too_large")
  }
}

fn prepared_writer_start_decoder() -> decode.Decoder(#(String, String, String)) {
  use schema <- decode.field("schema", decode.string)
  use previous_raw <- decode.field("previous", decode.string)
  use next_raw <- decode.field("next", decode.string)
  decode.success(#(schema, previous_raw, next_raw))
}

pub fn decode_prepared_writer_start(
  raw: String,
) -> Result(PreparedWriterStart, String) {
  let size = string.byte_size(raw)
  case size > 0 && size <= max_value_bytes {
    False -> Error("invalid_prepared_writer_start_payload_size")
    True ->
      case json.parse(raw, prepared_writer_start_decoder()) {
        Error(_) -> Error("malformed_prepared_writer_start_json")
        Ok(#(schema, previous_raw, next_raw)) ->
          case schema == prepared_writer_start_schema {
            False -> Error("invalid_prepared_writer_start_schema")
            True -> {
              use previous <- result.try(decode_writer_registration(previous_raw))
              use next <- result.try(decode_writer_registration(next_raw))
              let prepared = PreparedWriterStart(previous: previous, next: next)
              use _ <- result.try(validate_writer_successor(previous, next))
              use canonical <- result.try(encode_prepared_writer_start(prepared))
              case raw == canonical {
                True -> Ok(prepared)
                False -> Error("non_canonical_prepared_writer_start_json")
              }
            }
          }
      }
  }
}
