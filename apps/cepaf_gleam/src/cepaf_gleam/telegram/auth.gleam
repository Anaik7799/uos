//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/telegram/auth</module></identity>
////   <fractal-topology><layer>L0_CONSTITUTIONAL</layer></fractal-topology>
////   <compliance><stamp-controls>SC-SEC-001, SC-OPENCLAW-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Telegram Mini App initData HMAC-SHA256 validation.
//// Verifies that WebApp data was signed by Telegram using the bot token.
//// STAMP: SC-SEC-001, SC-OPENCLAW-001

import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleam/uri

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

/// Validate Telegram Mini App initData using HMAC-SHA256.
///
/// Algorithm (from Telegram docs):
/// 1. Parse initData as URL query string
/// 2. Extract `hash` parameter, remove it from params
/// 3. Sort remaining params alphabetically
/// 4. Join as `key=value\n` (data_check_string)
/// 5. secret_key = HMAC-SHA256("WebAppData", bot_token)
/// 6. computed_hash = HMAC-SHA256(secret_key, data_check_string)
/// 7. Compare computed_hash == hash
pub fn validate(init_data: String, bot_token: String) -> AuthResult {
  let params = parse_query_string(init_data)

  // Extract hash
  let hash_result =
    list.find(params, fn(kv) { kv.0 == "hash" })
    |> result.map(fn(kv) { kv.1 })

  case hash_result {
    Error(_) -> MalformedData("missing hash parameter")
    Ok(expected_hash) -> {
      // Remove hash from params and sort
      let check_params =
        params
        |> list.filter(fn(kv) { kv.0 != "hash" })
        |> list.sort(fn(a, b) { string.compare(a.0, b.0) })

      // Build data_check_string
      let data_check_string =
        check_params
        |> list.map(fn(kv) { kv.0 <> "=" <> kv.1 })
        |> string.join("\n")

      // Compute HMAC
      let secret_key =
        crypto.hmac(<<bot_token:utf8>>, crypto.Sha256, <<"WebAppData":utf8>>)
      let computed =
        crypto.hmac(<<data_check_string:utf8>>, crypto.Sha256, secret_key)
      let computed_hex = bit_array_to_hex(computed)

      case string.lowercase(computed_hex) == string.lowercase(expected_hash) {
        True -> {
          // Extract user JSON
          let user_result =
            list.find(params, fn(kv) { kv.0 == "user" })
            |> result.map(fn(kv) { kv.1 })
          case user_result {
            Ok(user_json) -> parse_user(user_json)
            Error(_) -> MalformedData("missing user parameter")
          }
        }
        False -> InvalidHash
      }
    }
  }
}

/// Parse user JSON string into TelegramUser.
fn parse_user(user_json: String) -> AuthResult {
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

  let decoded_json = json.parse(user_json, decoder)
  case decoded_json {
    Ok(user) -> Authenticated(user)
    Error(_) -> MalformedData("invalid user JSON")
  }
}

/// Parse URL query string into key-value pairs.
fn parse_query_string(qs: String) -> List(#(String, String)) {
  qs
  |> string.split("&")
  |> list.filter_map(fn(pair) {
    case string.split_once(pair, "=") {
      Ok(#(key, value)) ->
        Ok(#(
          uri.percent_decode(key) |> result.unwrap(key),
          uri.percent_decode(value) |> result.unwrap(value),
        ))
      Error(_) -> Error(Nil)
    }
  })
}

/// Convert a bit array to lowercase hex string.
fn bit_array_to_hex(bits: BitArray) -> String {
  bits
  |> bit_array.to_string
  |> result.unwrap("")
  |> string.to_graphemes
  |> list.map(fn(ch) {
    let codepoint = string.to_utf_codepoints(ch)
    case codepoint {
      [cp] -> {
        let val = string.utf_codepoint_to_int(cp)
        int_to_hex_byte(val)
      }
      _ -> "00"
    }
  })
  |> string.join("")
}

/// Convert a single byte (0-255) to 2-char hex string.
fn int_to_hex_byte(val: Int) -> String {
  let high = val / 16
  let low = val % 16
  hex_digit(high) <> hex_digit(low)
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

/// Check if init_data is not older than max_age_seconds.
pub fn check_freshness(
  init_data: String,
  now_unix: Int,
  max_age_seconds: Int,
) -> Bool {
  let params = parse_query_string(init_data)
  let auth_date_result =
    list.find(params, fn(kv) { kv.0 == "auth_date" })
    |> result.map(fn(kv) { kv.1 })
    |> result.try(int.parse)

  case auth_date_result {
    Ok(auth_date) -> now_unix - auth_date <= max_age_seconds
    Error(_) -> False
  }
}
