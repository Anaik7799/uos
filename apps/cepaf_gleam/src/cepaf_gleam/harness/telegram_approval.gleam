//// Pure cryptographic evidence verifier for Telegram multi-party approval receipts.
////
//// Security boundaries:
//// - Performs pure verification only; executes no I/O and grants no production authority.
//// - The signer roster must come from a trusted, integrity-protected configuration source;
////   caller-supplied roster data is not self-authenticating.
//// - Canonical effect fences and persistent idempotency checks remain mandatory before
////   any privileged effect is executed.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_action_intent as intent
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

const max_timestamp_ms = 9_007_199_254_740_991

const max_roster_window_ms = 3_600_000

const max_identifier_bytes = 128

const ed25519_b64u_key_bytes = 43

const max_token_bytes = 8192

const expected_version = "uos.telegram.approval.v1"

const expected_purpose = "cancel_job_lease"

const expected_decision = "approve"

const expected_claim_keys = [
  "decision",
  "effect_id",
  "exp_ms",
  "iat_ms",
  "intent_digest",
  "nbf_ms",
  "purpose",
  "role",
  "roster_digest",
  "subject",
  "version",
]

pub type Role {
  Codex
  Agy
  Claude
  Operator
}

pub type Signer {
  Signer(role: Role, subject: String, kid: String, public_key: String)
}

pub type Receipt {
  Receipt(role: Role, token: String)
}

pub opaque type Roster {
  Roster(
    signers: List(Signer),
    loaded_at_ms: Int,
    expires_at_ms: Int,
    digest: String,
  )
}

pub opaque type Verified {
  Verified(
    intent_digest: String,
    effect_id: String,
    roster_digest: String,
    receipt_digests: List(String),
    min_exp_ms: Int,
    verified_utc_ms: Int,
    verified_boot_ms: Int,
  )
}

type Claims {
  Claims(
    version: String,
    purpose: String,
    role: String,
    subject: String,
    decision: String,
    intent_digest: String,
    effect_id: String,
    iat_ms: Int,
    nbf_ms: Int,
    exp_ms: Int,
    roster_digest: String,
  )
}

@external(erlang, "oidc_jwt_ffi", "validate_jwks_snapshot")
fn validate_jwks_snapshot(jwks: String) -> Result(Nil, String)

@external(erlang, "oidc_jwt_ffi", "verify_ed25519_jwt")
fn verify_ed25519_jwt(token: String, jwks: String) -> Result(String, String)

pub fn role_name(role: Role) -> String {
  case role {
    Codex -> "codex"
    Agy -> "agy"
    Claude -> "claude"
    Operator -> "operator"
  }
}

pub fn roster_digest(roster: Roster) -> String {
  roster.digest
}

pub fn receipt_digests(e: Verified) -> List(String) {
  e.receipt_digests
}

pub fn new_roster(
  signers: List(Signer),
  loaded_at_ms: Int,
  expires_at_ms: Int,
) -> Result(Roster, String) {
  use bounded_signers <- result.try(bound_three_to_four(
    signers,
    "roster_signer_count_invalid",
  ))
  use _ <- result.try(validate_roster_window(loaded_at_ms, expires_at_ms))
  use _ <- result.try(validate_signers(bounded_signers, []))
  use _ <- result.try(validate_role_quorum(
    list.map(bounded_signers, fn(s) { s.role }),
    "roster_quorum_invalid",
  ))
  let digest =
    compute_roster_digest(bounded_signers, loaded_at_ms, expires_at_ms)
  Ok(Roster(
    signers: bounded_signers,
    loaded_at_ms: loaded_at_ms,
    expires_at_ms: expires_at_ms,
    digest: digest,
  ))
}

pub fn verify(
  roster: Roster,
  request: intent.Intent,
  host: String,
  boot: String,
  now_utc_ms: Int,
  now_boot_ms: Int,
  receipts: List(Receipt),
) -> Result(Verified, String) {
  use _ <- result.try(check_roster_active(roster, now_utc_ms))
  use _ <- result.try(
    case intent.valid_at(request, host, boot, now_utc_ms, now_boot_ms) {
      True -> Ok(Nil)
      False -> Error("intent_not_valid_at_now")
    },
  )
  let req_digest = intent.digest(request)
  let req_effect_id = intent.effect_id(request)
  use _ <- result.try(case req_digest != "" && req_effect_id != "" {
    True -> Ok(Nil)
    False -> Error("intent_identity_invalid")
  })
  use bounded_receipts <- result.try(bound_three_to_four(
    receipts,
    "receipt_count_invalid",
  ))
  use _ <- result.try(precheck_receipts(bounded_receipts, []))
  use _ <- result.try(validate_role_quorum(
    list.map(bounded_receipts, fn(r) { r.role }),
    "receipt_quorum_invalid",
  ))
  use verified_items <- result.try(
    list.try_map(bounded_receipts, fn(receipt) {
      verify_single_receipt(
        roster,
        request,
        req_digest,
        req_effect_id,
        now_utc_ms,
        receipt,
      )
    }),
  )
  let digests = list.map(verified_items, fn(item) { item.0 })
  let exp_times = list.map(verified_items, fn(item) { item.1 })
  use min_exp_ms <- result.try(min_int(exp_times, "receipt_count_invalid"))
  Ok(Verified(
    intent_digest: req_digest,
    effect_id: req_effect_id,
    roster_digest: roster.digest,
    receipt_digests: digests,
    min_exp_ms: min_exp_ms,
    verified_utc_ms: now_utc_ms,
    verified_boot_ms: now_boot_ms,
  ))
}

pub fn still_valid(
  e: Verified,
  roster: Roster,
  request: intent.Intent,
  host: String,
  boot: String,
  now_utc_ms: Int,
  now_boot_ms: Int,
) -> Bool {
  let req_digest = intent.digest(request)
  let req_effect_id = intent.effect_id(request)
  e.roster_digest == roster.digest
  && e.intent_digest == req_digest
  && e.effect_id == req_effect_id
  && req_digest != ""
  && req_effect_id != ""
  && now_utc_ms >= roster.loaded_at_ms
  && now_utc_ms < roster.expires_at_ms
  && intent.valid_at(request, host, boot, now_utc_ms, now_boot_ms)
  && now_utc_ms >= e.verified_utc_ms
  && now_boot_ms >= e.verified_boot_ms
  && now_utc_ms < e.min_exp_ms
}

fn bound_three_to_four(items: List(a), err: String) -> Result(List(a), String) {
  case items {
    [_, _, _] | [_, _, _, _] -> Ok(items)
    _ -> Error(err)
  }
}

fn validate_roster_window(
  loaded_at_ms: Int,
  expires_at_ms: Int,
) -> Result(Nil, String) {
  case
    loaded_at_ms >= 0
    && expires_at_ms > loaded_at_ms
    && expires_at_ms <= max_timestamp_ms
    && expires_at_ms - loaded_at_ms <= max_roster_window_ms
  {
    True -> Ok(Nil)
    False -> Error("roster_window_invalid")
  }
}

fn check_roster_active(roster: Roster, now_utc_ms: Int) -> Result(Nil, String) {
  case now_utc_ms >= roster.loaded_at_ms && now_utc_ms < roster.expires_at_ms {
    True -> Ok(Nil)
    False -> Error("roster_not_active")
  }
}

fn validate_signers(
  remaining: List(Signer),
  seen: List(Signer),
) -> Result(Nil, String) {
  case remaining {
    [] -> Ok(Nil)
    [signer, ..rest] -> {
      use _ <- result.try(
        case valid_identifier(signer.subject) && valid_identifier(signer.kid) {
          True -> Ok(Nil)
          False -> Error("roster_identifier_invalid")
        },
      )
      use _ <- result.try(case valid_base64url_key(signer.public_key) {
        True -> Ok(Nil)
        False -> Error("roster_public_key_invalid")
      })
      let duplicate =
        list.any(seen, fn(prev) {
          prev.role == signer.role
          || prev.subject == signer.subject
          || prev.kid == signer.kid
          || prev.public_key == signer.public_key
        })
      use _ <- result.try(case duplicate {
        True -> Error("roster_duplicate_signer_field")
        False -> Ok(Nil)
      })
      let jwks = single_key_jwks(signer.kid, signer.public_key)
      use _ <- result.try(
        validate_jwks_snapshot(jwks)
        |> result.map_error(fn(_) { "roster_public_key_invalid" }),
      )
      validate_signers(rest, [signer, ..seen])
    }
  }
}

fn validate_role_quorum(roles: List(Role), err: String) -> Result(Nil, String) {
  let has_operator = list.any(roles, fn(r) { r == Operator })
  let sovereign_count =
    list.count(roles, fn(r) { r == Codex || r == Agy || r == Claude })
  case has_operator && sovereign_count >= 2 {
    True -> Ok(Nil)
    False -> Error(err)
  }
}

fn precheck_receipts(
  remaining: List(Receipt),
  seen_roles: List(Role),
) -> Result(Nil, String) {
  case remaining {
    [] -> Ok(Nil)
    [receipt, ..rest] -> {
      let size = string.byte_size(receipt.token)
      use _ <- result.try(case size >= 1 && size <= max_token_bytes {
        True -> Ok(Nil)
        False -> Error("receipt_token_size_invalid")
      })
      use _ <- result.try(case list.contains(seen_roles, receipt.role) {
        True -> Error("receipt_duplicate_role")
        False -> Ok(Nil)
      })
      precheck_receipts(rest, [receipt.role, ..seen_roles])
    }
  }
}

fn verify_single_receipt(
  roster: Roster,
  request: intent.Intent,
  req_digest: String,
  req_effect_id: String,
  now_utc_ms: Int,
  receipt: Receipt,
) -> Result(#(String, Int), String) {
  use signer <- result.try(
    list.find(roster.signers, fn(s) { s.role == receipt.role })
    |> result.map_error(fn(_) { "receipt_role_not_in_roster" }),
  )
  let jwks = single_key_jwks(signer.kid, signer.public_key)
  use payload_json <- result.try(
    verify_ed25519_jwt(receipt.token, jwks)
    |> result.map_error(fn(_) { "receipt_jwt_verification_failed" }),
  )
  use claims <- result.try(decode_claims(payload_json))
  use _ <- result.try(
    case
      claims.version == expected_version
      && claims.purpose == expected_purpose
      && claims.role == role_name(signer.role)
      && claims.subject == signer.subject
      && claims.decision == expected_decision
      && claims.intent_digest == req_digest
      && claims.effect_id == req_effect_id
      && claims.roster_digest == roster.digest
    {
      True -> Ok(Nil)
      False -> Error("receipt_claims_mismatch")
    },
  )
  use _ <- result.try(
    case
      claims.iat_ms >= 0
      && claims.nbf_ms >= 0
      && claims.exp_ms > now_utc_ms
      && claims.exp_ms <= max_timestamp_ms
      && intent.valid_receipt_window(
        request,
        now_utc_ms,
        claims.iat_ms,
        claims.nbf_ms,
        claims.exp_ms,
      )
    {
      True -> Ok(Nil)
      False -> Error("receipt_window_invalid")
    },
  )
  Ok(#(files.digest(receipt.token), claims.exp_ms))
}

fn decode_claims(payload_json: String) -> Result(Claims, String) {
  let decoder = {
    use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
    use version <- decode.field("version", decode.string)
    use purpose <- decode.field("purpose", decode.string)
    use role <- decode.field("role", decode.string)
    use subject <- decode.field("subject", decode.string)
    use decision <- decode.field("decision", decode.string)
    use intent_digest <- decode.field("intent_digest", decode.string)
    use effect_id <- decode.field("effect_id", decode.string)
    use iat_ms <- decode.field("iat_ms", decode.int)
    use nbf_ms <- decode.field("nbf_ms", decode.int)
    use exp_ms <- decode.field("exp_ms", decode.int)
    use roster_digest <- decode.field("roster_digest", decode.string)
    decode.success(#(
      fields,
      Claims(
        version: version,
        purpose: purpose,
        role: role,
        subject: subject,
        decision: decision,
        intent_digest: intent_digest,
        effect_id: effect_id,
        iat_ms: iat_ms,
        nbf_ms: nbf_ms,
        exp_ms: exp_ms,
        roster_digest: roster_digest,
      ),
    ))
  }
  case json.parse(payload_json, decoder) {
    Error(_) -> Error("receipt_claims_decode_failed")
    Ok(#(fields, claims)) ->
      case
        dict.size(fields) == 11
        && list.all(expected_claim_keys, fn(k) { dict.has_key(fields, k) })
      {
        True -> Ok(claims)
        False -> Error("receipt_claims_key_set_invalid")
      }
  }
}

fn single_key_jwks(kid: String, public_key: String) -> String {
  json.object([
    #(
      "keys",
      json.preprocessed_array([
        json.object([
          #("kty", json.string("OKP")),
          #("crv", json.string("Ed25519")),
          #("kid", json.string(kid)),
          #("alg", json.string("EdDSA")),
          #("x", json.string(public_key)),
        ]),
      ]),
    ),
  ])
  |> json.to_string
}

fn compute_roster_digest(
  signers: List(Signer),
  loaded_at_ms: Int,
  expires_at_ms: Int,
) -> String {
  json.preprocessed_array([
    json.string("uos.telegram.approval-roster.v1"),
    json.int(loaded_at_ms),
    json.int(expires_at_ms),
    json.array(signers, fn(s) {
      json.preprocessed_array([
        json.string(role_name(s.role)),
        json.string(s.subject),
        json.string(s.kid),
        json.string(s.public_key),
      ])
    }),
  ])
  |> json.to_string
  |> files.digest
}

fn valid_identifier(s: String) -> Bool {
  let size = string.byte_size(s)
  size >= 1
  && size <= max_identifier_bytes
  && list.all(string.to_utf_codepoints(s), fn(cp) {
    let code = string.utf_codepoint_to_int(cp)
    is_alnum_or_url_safe(code) || code == 46 || code == 58 || code == 47
  })
}

fn valid_base64url_key(s: String) -> Bool {
  string.byte_size(s) == ed25519_b64u_key_bytes
  && list.all(string.to_utf_codepoints(s), fn(cp) {
    is_alnum_or_url_safe(string.utf_codepoint_to_int(cp))
  })
}

fn is_alnum_or_url_safe(code: Int) -> Bool {
  code >= 97
  && code <= 122
  || code >= 65
  && code <= 90
  || code >= 48
  && code <= 57
  || code == 45
  || code == 95
}

fn min_int(values: List(Int), err: String) -> Result(Int, String) {
  case values {
    [first, ..rest] ->
      Ok(list.fold(rest, first, fn(acc, x) { int.min(acc, x) }))
    [] -> Error(err)
  }
}
