//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/telegram/auth</module></identity>
////   <fractal-topology><layer>L0_CONSTITUTIONAL</layer></fractal-topology>
////   <compliance><stamp-controls>SC-SEC-001, SC-OPENCLAW-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Telegram Mini App initData HMAC-SHA256 validation.
//// Verifies that WebApp data was signed by Telegram using the bot token.
//// STAMP: SC-SEC-001, SC-OPENCLAW-001

import gleam/crypto
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleam/uri

/// Maximum allowed byte size for init_data query string.
pub const max_init_data_bytes = 4096

/// Maximum allowed byte size for bot token.
pub const max_token_bytes = 256

/// Maximum allowed byte size for user JSON payload.
pub const max_user_json_bytes = 4096

/// Maximum safe integer (2^53 - 1) representing JSON safe number limit.
pub const max_safe_integer = 9_007_199_254_740_991

/// Maximum allowed freshness window: 24 hours (86,400 seconds).
pub const max_allowed_max_age = 86_400

/// Maximum allowed clock skew tolerance: 60 seconds.
pub const max_allowed_skew = 60

/// Authenticated Telegram user extracted from validated initData.
pub type TelegramUser {
  TelegramUser(
    id: Int,
    first_name: String,
    username: String,
    language_code: String,
  )
}

/// Validation result.
pub type AuthResult {
  Authenticated(TelegramUser)
  InvalidHash
  ExpiredData
  MalformedData(String)
}

/// Validate Telegram Mini App initData using HMAC-SHA256 signature verification.
///
/// NOTE: This function performs signature-only validation. It does NOT evaluate
/// timestamp freshness or expiration. Call `validate_fresh` or `check_freshness`
/// to enforce temporal replay protection.
///
/// Fixed error messages are returned with zero input/token reflection to prevent
/// information disclosure and error-injection attacks.
pub fn validate(init_data: String, bot_token: String) -> AuthResult {
  case string.byte_size(init_data) > max_init_data_bytes {
    True -> MalformedData("init_data exceeds maximum size")
    False -> {
      let token_size = string.byte_size(bot_token)
      case token_size == 0 || token_size > max_token_bytes {
        True -> MalformedData("invalid bot token")
        False -> {
          case
            contains_disallowed_bytes(init_data)
            || contains_disallowed_bytes(bot_token)
          {
            True -> MalformedData("payload contains invalid characters")
            False -> {
              case parse_query_string(init_data) {
                Error(msg) -> MalformedData(msg)
                Ok(params) -> {
                  case list.find(params, fn(kv) { kv.0 == "hash" }) {
                    Error(_) -> MalformedData("missing hash parameter")
                    Ok(#(_, raw_hash)) -> {
                      case is_valid_hex_64(raw_hash) {
                        False -> InvalidHash
                        True -> {
                          let expected_hash_lower = string.lowercase(raw_hash)
                          let check_params =
                            params
                            |> list.filter(fn(kv) { kv.0 != "hash" })
                            |> list.sort(fn(a, b) { string.compare(a.0, b.0) })

                          let data_check_string =
                            check_params
                            |> list.map(fn(kv) { kv.0 <> "=" <> kv.1 })
                            |> string.join("\n")

                          let secret_key =
                            crypto.hmac(<<bot_token:utf8>>, crypto.Sha256, <<
                              "WebAppData":utf8,
                            >>)
                          let computed =
                            crypto.hmac(
                              <<data_check_string:utf8>>,
                              crypto.Sha256,
                              secret_key,
                            )
                          let computed_hex = bit_array_to_hex(computed)

                          case
                            crypto.secure_compare(<<computed_hex:utf8>>, <<
                              expected_hash_lower:utf8,
                            >>)
                          {
                            True -> {
                              case
                                list.find(params, fn(kv) { kv.0 == "user" })
                              {
                                Ok(#(_, user_json)) -> parse_user(user_json)
                                Error(_) ->
                                  MalformedData("missing user parameter")
                              }
                            }
                            False -> InvalidHash
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
    }
  }
}

/// Validate Telegram Mini App initData signature and freshness.
/// Combines HMAC signature verification with bounded freshness checking.
/// Rejects expired data, future timestamps, and out-of-range policies with ExpiredData.
pub fn validate_fresh(
  init_data: String,
  bot_token: String,
  now_unix: Int,
  max_age_seconds: Int,
) -> AuthResult {
  validate_fresh_with_skew(init_data, bot_token, now_unix, max_age_seconds, 0)
}

/// Validate Telegram Mini App initData signature and freshness with explicit clock skew tolerance.
pub fn validate_fresh_with_skew(
  init_data: String,
  bot_token: String,
  now_unix: Int,
  max_age_seconds: Int,
  skew_tolerance_seconds: Int,
) -> AuthResult {
  case validate(init_data, bot_token) {
    Authenticated(user) -> {
      case
        check_freshness_with_skew(
          init_data,
          now_unix,
          max_age_seconds,
          skew_tolerance_seconds,
        )
      {
        True -> Authenticated(user)
        False -> ExpiredData
      }
    }
    other -> other
  }
}

/// Parse user JSON string into TelegramUser with strict field bounds and character validation.
fn parse_user(user_json: String) -> AuthResult {
  case string.byte_size(user_json) > max_user_json_bytes {
    True -> MalformedData("user payload exceeds maximum size")
    False -> {
      case contains_disallowed_bytes(user_json) {
        True -> MalformedData("user JSON contains invalid characters")
        False -> {
          let decoder = {
            use id <- decode.field("id", decode.int)
            use first_name <- decode.field("first_name", decode.string)
            use username <- decode.optional_field("username", "", decode.string)
            use language_code <- decode.optional_field(
              "language_code",
              "en",
              decode.string,
            )
            decode.success(TelegramUser(id, first_name, username, language_code))
          }

          case json.parse(user_json, decoder) {
            Ok(user) -> {
              case user.id > 0 && user.id <= max_safe_integer {
                True -> {
                  case validate_user_fields(user) {
                    True -> Authenticated(user)
                    False -> MalformedData("invalid user fields")
                  }
                }
                False -> MalformedData("invalid user id")
              }
            }
            Error(_) -> MalformedData("invalid user JSON")
          }
        }
      }
    }
  }
}

/// Validate user text fields: no NUL or control characters, bounded lengths.
fn validate_user_fields(user: TelegramUser) -> Bool {
  let fn_bytes = string.byte_size(user.first_name)
  let un_bytes = string.byte_size(user.username)
  let lc_bytes = string.byte_size(user.language_code)

  fn_bytes >= 1
  && fn_bytes <= 256
  && !contains_disallowed_bytes(user.first_name)
  && un_bytes <= 256
  && !contains_disallowed_bytes(user.username)
  && lc_bytes >= 1
  && lc_bytes <= 64
  && is_valid_language_code(user.language_code)
}

/// Check if language_code consists of bounded ASCII alphanumeric nonempty
/// hyphen-separated subtags (max 64 bytes total, each 1..8 chars, first subtag letters only).
fn is_valid_language_code(lc: String) -> Bool {
  let size = string.byte_size(lc)
  case size >= 1 && size <= 64 {
    False -> False
    True -> {
      let subtags = string.split(lc, "-")
      case subtags {
        [] -> False
        [primary, ..rest] -> {
          is_valid_primary_subtag(primary)
          && list.all(rest, is_valid_subsequent_subtag)
        }
      }
    }
  }
}

fn is_valid_primary_subtag(subtag: String) -> Bool {
  let len = string.length(subtag)
  case len >= 1 && len <= 8 {
    False -> False
    True -> {
      string.to_graphemes(subtag)
      |> list.all(is_ascii_letter)
    }
  }
}

fn is_valid_subsequent_subtag(subtag: String) -> Bool {
  let len = string.length(subtag)
  case len >= 1 && len <= 8 {
    False -> False
    True -> {
      string.to_graphemes(subtag)
      |> list.all(is_ascii_alphanumeric)
    }
  }
}

fn is_ascii_letter(ch: String) -> Bool {
  case ch {
    "a"
    | "b"
    | "c"
    | "d"
    | "e"
    | "f"
    | "g"
    | "h"
    | "i"
    | "j"
    | "k"
    | "l"
    | "m"
    | "n"
    | "o"
    | "p"
    | "q"
    | "r"
    | "s"
    | "t"
    | "u"
    | "v"
    | "w"
    | "x"
    | "y"
    | "z"
    | "A"
    | "B"
    | "C"
    | "D"
    | "E"
    | "F"
    | "G"
    | "H"
    | "I"
    | "J"
    | "K"
    | "L"
    | "M"
    | "N"
    | "O"
    | "P"
    | "Q"
    | "R"
    | "S"
    | "T"
    | "U"
    | "V"
    | "W"
    | "X"
    | "Y"
    | "Z" -> True
    _ -> False
  }
}

fn is_ascii_alphanumeric(ch: String) -> Bool {
  case is_ascii_letter(ch) {
    True -> True
    False ->
      case ch {
        "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
        _ -> False
      }
  }
}

/// Parse URL query string into key-value pairs with strict validation and no error reflection.
fn parse_query_string(qs: String) -> Result(List(#(String, String)), String) {
  case qs {
    "" -> Error("empty query string")
    _ -> {
      let pairs = string.split(qs, "&")
      do_parse_pairs(pairs, [], [])
    }
  }
}

fn do_parse_pairs(
  pairs: List(String),
  seen_keys: List(String),
  acc: List(#(String, String)),
) -> Result(List(#(String, String)), String) {
  case pairs {
    [] -> Ok(list.reverse(acc))
    [pair, ..rest] -> {
      case string.split_once(pair, "=") {
        Error(_) -> Error("malformed parameter format")
        Ok(#(raw_key, raw_val)) -> {
          case
            contains_disallowed_bytes(raw_key)
            || contains_disallowed_bytes(raw_val)
          {
            True -> Error("payload contains invalid characters")
            False -> {
              let key_plussed = string.replace(raw_key, "+", " ")
              let val_plussed = string.replace(raw_val, "+", " ")
              case uri.percent_decode(key_plussed) {
                Error(_) -> Error("malformed percent encoding")
                Ok(key) -> {
                  case is_valid_parameter_key(key) {
                    False -> Error("invalid parameter key")
                    True -> {
                      case list.contains(seen_keys, key) {
                        True -> Error("duplicate parameter key")
                        False -> {
                          case uri.percent_decode(val_plussed) {
                            Error(_) -> Error("malformed percent encoding")
                            Ok(val) -> {
                              case is_valid_parameter_value(val) {
                                False ->
                                  Error(
                                    "parameter value contains invalid characters",
                                  )
                                True -> {
                                  do_parse_pairs(rest, [key, ..seen_keys], [
                                    #(key, val),
                                    ..acc
                                  ])
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
          }
        }
      }
    }
  }
}

/// Telegram parameter keys must be short ASCII identifiers: [a-zA-Z0-9_], 1 to 64 bytes.
fn is_valid_parameter_key(key: String) -> Bool {
  let size = string.byte_size(key)
  case size >= 1 && size <= 64 {
    False -> False
    True -> {
      string.to_graphemes(key)
      |> list.all(fn(ch) {
        case is_ascii_alphanumeric(ch) {
          True -> True
          False -> ch == "_"
        }
      })
    }
  }
}

/// Parameter values must not contain C0 control characters or DEL.
fn is_valid_parameter_value(val: String) -> Bool {
  !contains_disallowed_bytes(val)
}

/// Convert a bit array to lowercase hex string using direct 8-bit binary pattern matching.
/// Does NOT perform intermediate UTF-8 conversions on raw cryptographic digest bytes.
pub fn bit_array_to_hex(bits: BitArray) -> String {
  do_bit_array_to_hex(bits, "")
}

fn do_bit_array_to_hex(bits: BitArray, acc: String) -> String {
  case bits {
    <<byte:8, rest:bits>> -> {
      let high = byte / 16
      let low = byte % 16
      do_bit_array_to_hex(rest, acc <> hex_digit(high) <> hex_digit(low))
    }
    _ -> acc
  }
}

fn hex_digit(n: Int) -> String {
  case n {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    4 -> "4"
    5 -> "5"
    6 -> "6"
    7 -> "7"
    8 -> "8"
    9 -> "9"
    10 -> "a"
    11 -> "b"
    12 -> "c"
    13 -> "d"
    14 -> "e"
    15 -> "f"
    _ -> "0"
  }
}

fn is_hex_char(ch: String) -> Bool {
  case ch {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    "a" | "b" | "c" | "d" | "e" | "f" -> True
    "A" | "B" | "C" | "D" | "E" | "F" -> True
    _ -> False
  }
}

fn is_valid_hex_64(s: String) -> Bool {
  case string.length(s) == 64 {
    True -> {
      string.to_graphemes(s)
      |> list.all(is_hex_char)
    }
    False -> False
  }
}

/// Check if string contains any C0 control characters (codepoints 0 to 31) or DEL (codepoint 127).
fn contains_disallowed_bytes(s: String) -> Bool {
  string.to_utf_codepoints(s)
  |> list.any(fn(cp) {
    let val = string.utf_codepoint_to_int(cp)
    val < 32 || val == 127
  })
}

/// Extract auth_date integer from init_data query string.
fn extract_auth_date(init_data: String) -> Result(Int, Nil) {
  case string.byte_size(init_data) > max_init_data_bytes {
    True -> Error(Nil)
    False -> {
      case parse_query_string(init_data) {
        Ok(params) -> {
          list.find(params, fn(kv) { kv.0 == "auth_date" })
          |> result.map(fn(kv) { kv.1 })
          |> result.try(int.parse)
        }
        Error(_) -> Error(Nil)
      }
    }
  }
}

/// Check if init_data is not older than max_age_seconds and not from the future.
/// Requires nonnegative now_unix and max_age_seconds bounded to policy limits.
pub fn check_freshness(
  init_data: String,
  now_unix: Int,
  max_age_seconds: Int,
) -> Bool {
  check_freshness_with_skew(init_data, now_unix, max_age_seconds, 0)
}

/// Check freshness with explicit clock skew tolerance.
/// Fails closed (False) if any argument is negative or exceeds safe integer / policy bounds.
pub fn check_freshness_with_skew(
  init_data: String,
  now_unix: Int,
  max_age_seconds: Int,
  skew_tolerance_seconds: Int,
) -> Bool {
  let valid_inputs =
    now_unix >= 0
    && now_unix <= max_safe_integer
    && max_age_seconds >= 0
    && max_age_seconds <= max_allowed_max_age
    && skew_tolerance_seconds >= 0
    && skew_tolerance_seconds <= max_allowed_skew

  case valid_inputs {
    False -> False
    True -> {
      case extract_auth_date(init_data) {
        Ok(auth_date) -> {
          auth_date >= 0
          && auth_date <= max_safe_integer
          && auth_date <= now_unix + skew_tolerance_seconds
          && now_unix - auth_date <= max_age_seconds
        }
        Error(_) -> False
      }
    }
  }
}
