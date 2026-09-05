//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/auth/token_exchange</module>
////     <fsharp-lineage>New — no F# predecessor</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-AUTH-001, SC-IAM-004, SC-OPENCLAW-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Telegram initData ↪ FerrisKey JWT via RFC 8693 token exchange.
////       Existing telegram/auth.gleam validates HMAC;
////       this module exchanges the validated identity for a FerrisKey JWT.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Token exchange for Telegram identity federation with FerrisKey.
//// Validates Telegram Mini App initData, then exchanges the verified
//// identity for a FerrisKey JWT via OAuth2 token exchange (RFC 8693).
////
//// STAMP: SC-AUTH-001, SC-IAM-004, SC-OPENCLAW-001

import gleam/dynamic/decode
import gleam/json
import gleam/option

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Token exchange request from a Telegram Mini App.
pub type TelegramExchangeRequest {
  TelegramExchangeRequest(
    init_data: String,
    telegram_user_id: Int,
    telegram_username: String,
  )
}

/// Token exchange response with FerrisKey JWT.
pub type ExchangeResponse {
  ExchangeResponse(
    access_token: String,
    token_type: String,
    expires_in: Int,
    refresh_token: String,
  )
}

/// Token exchange error.
pub type ExchangeError {
  InvalidTelegramData(reason: String)
  FerrisKeyUnavailable(reason: String)
  ExchangeRejected(reason: String)
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Build the token exchange request body for FerrisKey.
///
/// Uses RFC 8693 (OAuth 2.0 Token Exchange):
///   grant_type = urn:ietf:params:oauth:grant-type:token-exchange
///   subject_token_type = urn:c3i:telegram:init-data
///   subject_token = validated Telegram user JSON
pub fn build_exchange_body(
  telegram_user_id: Int,
  telegram_username: String,
  client_id: String,
  client_secret: String,
) -> String {
  let subject_token =
    json.object([
      #("telegram_user_id", json.int(telegram_user_id)),
      #("telegram_username", json.string(telegram_username)),
      #("provider", json.string("telegram")),
    ])
    |> json.to_string()

  "grant_type=urn:ietf:params:oauth:grant-type:token-exchange"
  <> "&subject_token_type=urn:c3i:telegram:init-data"
  <> "&subject_token="
  <> url_encode(subject_token)
  <> "&client_id="
  <> client_id
  <> "&client_secret="
  <> client_secret
  <> "&requested_token_type=urn:ietf:params:oauth:token-type:access_token"
}

/// Parse the FerrisKey token response into an ExchangeResponse.
pub fn parse_exchange_response(
  body: String,
) -> Result(ExchangeResponse, ExchangeError) {
  let decoder = {
    use access_token <- decode.field("access_token", decode.string)
    use expires_in <- decode.field("expires_in", decode.int)
    use refresh_token <- decode.field(
      "refresh_token",
      decode.optional(decode.string),
    )
    decode.success(ExchangeResponse(
      access_token: access_token,
      token_type: "Bearer",
      expires_in: expires_in,
      refresh_token: option.unwrap(refresh_token, ""),
    ))
  }
  case json.parse(body, decoder) {
    Ok(resp) -> Ok(resp)
    Error(_) -> Error(ExchangeRejected("failed to parse token response"))
  }
}

/// Convert exchange error to JSON for API responses.
pub fn error_to_json(error: ExchangeError) -> String {
  let reason = case error {
    InvalidTelegramData(r) -> r
    FerrisKeyUnavailable(r) -> r
    ExchangeRejected(r) -> r
  }
  json.object([
    #("error", json.string("token_exchange_failed")),
    #("reason", json.string(reason)),
    #("stamp", json.string("SC-AUTH-001")),
  ])
  |> json.to_string()
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Simple URL encoding (percent-encode special characters).
fn url_encode(input: String) -> String {
  input
  |> do_url_encode()
}

@external(erlang, "cepaf_gleam_ffi", "url_encode")
fn do_url_encode(input: String) -> String
