import cepaf_gleam/telegram/auth
import gleam/string
import gleeunit/should

// Synthetic golden vector from independent review:
// Token: 123456789:synthetic-test-token-not-a-real-credential
// User: {"id":12345,"first_name":"Synthetic"}
// auth_date: 1791720600
// hash: 41b5f6131c21690c9d7e4b89247e02183c3b4c8cda1856fa55b3a0b0f9222caa

const token = "123456789:synthetic-test-token-not-a-real-credential"

const valid_signed = "auth_date=1791720600&user=%7B%22id%22%3A12345%2C%22first_name%22%3A%22Synthetic%22%7D&hash=41b5f6131c21690c9d7e4b89247e02183c3b4c8cda1856fa55b3a0b0f9222caa"

const empty_hash_forged = "auth_date=1791720600&user=%7B%22id%22%3A12345%2C%22first_name%22%3A%22Synthetic%22%7D&hash="

pub fn auth_independent_review_golden_vector_test() {
  let result = auth.validate(valid_signed, token)
  case result {
    auth.Authenticated(user) -> {
      user.id |> should.equal(12_345)
      user.first_name |> should.equal("Synthetic")
      user.username |> should.equal("")
      user.language_code |> should.equal("en")
    }
    _ -> should.be_true(False)
  }
}

pub fn auth_empty_hash_forgery_rejected_test() {
  let result = auth.validate(empty_hash_forged, token)
  case result {
    auth.InvalidHash -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

pub fn auth_short_hash_rejected_test() {
  let qs =
    "auth_date=1791720600&user=%7B%22id%22%3A12345%2C%22first_name%22%3A%22Synthetic%22%7D&hash=41b5"
  case auth.validate(qs, token) {
    auth.InvalidHash -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

pub fn auth_long_hash_rejected_test() {
  let qs =
    "auth_date=1791720600&user=%7B%22id%22%3A12345%2C%22first_name%22%3A%22Synthetic%22%7D&hash=41b5f6131c21690c9d7e4b89247e02183c3b4c8cda1856fa55b3a0b0f9222caa00"
  case auth.validate(qs, token) {
    auth.InvalidHash -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

pub fn auth_non_hex_hash_rejected_test() {
  let qs =
    "auth_date=1791720600&user=%7B%22id%22%3A12345%2C%22first_name%22%3A%22Synthetic%22%7D&hash=41b5f6131c21690c9d7e4b89247e02183c3b4c8cda1856fa55b3a0b0f9222caz"
  case auth.validate(qs, token) {
    auth.InvalidHash -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

pub fn auth_wrong_signature_rejected_test() {
  let qs =
    "auth_date=1791720600&user=%7B%22id%22%3A12345%2C%22first_name%22%3A%22Synthetic%22%7D&hash=0000000000000000000000000000000000000000000000000000000000000000"
  case auth.validate(qs, token) {
    auth.InvalidHash -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

pub fn auth_uppercase_hash_accepted_test() {
  let qs =
    "auth_date=1791720600&user=%7B%22id%22%3A12345%2C%22first_name%22%3A%22Synthetic%22%7D&hash=41B5F6131C21690C9D7E4B89247E02183C3B4C8CDA1856FA55B3A0B0F9222CAA"
  case auth.validate(qs, token) {
    auth.Authenticated(user) -> user.id |> should.equal(12_345)
    _ -> should.be_true(False)
  }
}

pub fn auth_duplicate_keys_rejected_test() {
  let qs =
    "auth_date=1791720600&auth_date=1791720601&hash=41b5f6131c21690c9d7e4b89247e02183c3b4c8cda1856fa55b3a0b0f9222caa"
  case auth.validate(qs, token) {
    auth.MalformedData(msg) -> {
      msg |> should.equal("duplicate parameter key")
    }
    _ -> should.be_true(False)
  }
}

pub fn auth_encoded_duplicate_key_rejected_test() {
  // auth_date vs %61uth_date (%61 is ASCII 'a')
  let qs =
    "auth_date=1791720600&%61uth_date=1791720601&hash=41b5f6131c21690c9d7e4b89247e02183c3b4c8cda1856fa55b3a0b0f9222caa"
  case auth.validate(qs, token) {
    auth.MalformedData(msg) -> {
      msg |> should.equal("duplicate parameter key")
    }
    _ -> should.be_true(False)
  }
}

pub fn auth_malformed_percent_rejected_test() {
  let qs =
    "auth_date=1791720600&user=%ZZ&hash=41b5f6131c21690c9d7e4b89247e02183c3b4c8cda1856fa55b3a0b0f9222caa"
  case auth.validate(qs, token) {
    auth.MalformedData(msg) -> {
      msg |> should.equal("malformed percent encoding")
    }
    _ -> should.be_true(False)
  }
}

pub fn auth_nul_byte_rejected_test() {
  let qs =
    "auth_date=1791720600\u{0000}&hash=41b5f6131c21690c9d7e4b89247e02183c3b4c8cda1856fa55b3a0b0f9222caa"
  case auth.validate(qs, token) {
    auth.MalformedData(msg) -> {
      msg |> should.equal("payload contains invalid characters")
    }
    _ -> should.be_true(False)
  }
}

pub fn auth_crlf_injection_rejected_test() {
  // Value containing newline to forge parameter injection in data check string
  let qs =
    "auth_date=1791720600\nadmin=true&hash=41b5f6131c21690c9d7e4b89247e02183c3b4c8cda1856fa55b3a0b0f9222caa"
  case auth.validate(qs, token) {
    auth.MalformedData(msg) -> {
      msg |> should.equal("payload contains invalid characters")
    }
    _ -> should.be_true(False)
  }
}

pub fn auth_error_nonreflection_test() {
  let secret_payload = "SECRET_CREDENTIAL_PAYLOAD"
  let qs =
    "secret="
    <> secret_payload
    <> "&malformed=%ZZ&hash=41b5f6131c21690c9d7e4b89247e02183c3b4c8cda1856fa55b3a0b0f9222caa"
  case auth.validate(qs, token) {
    auth.MalformedData(msg) -> {
      // Must not reflect secret payload in error message!
      string.contains(msg, secret_payload) |> should.be_false()
      msg |> should.equal("malformed percent encoding")
    }
    _ -> should.be_true(False)
  }
}

pub fn auth_combining_mark_oversized_test() {
  // One base letter 'a' with 3000 combining marks (\u{0300} is 2 bytes in UTF-8).
  // Total byte size > 6000 bytes > max_init_data_bytes (4096), while grapheme count is small.
  let combining = string.repeat("\u{0300}", 2500)
  let qs =
    "auth_date=1791720600&user=a"
    <> combining
    <> "&hash=41b5f6131c21690c9d7e4b89247e02183c3b4c8cda1856fa55b3a0b0f9222caa"
  case auth.validate(qs, token) {
    auth.MalformedData(msg) ->
      msg |> should.equal("init_data exceeds maximum size")
    _ -> should.be_true(False)
  }
}

pub fn auth_huge_user_id_rejected_test() {
  // ID exceeds max_safe_integer (9007199254740991): 9999999999999999999
  // Data: auth_date=1791720600\nuser={"first_name":"Huge","id":9999999999999999999}
  // HMAC: d71a19780b87c1570ae6b51a731ecffe11bec5c1dbaaf309cb8afa8eee31ca0e
  let qs =
    "auth_date=1791720600&user=%7B%22first_name%22%3A%22Huge%22%2C%22id%22%3A9999999999999999999%7D&hash=d71a19780b87c1570ae6b51a731ecffe11bec5c1dbaaf309cb8afa8eee31ca0e"
  case auth.validate(qs, token) {
    auth.MalformedData(msg) -> msg |> should.equal("invalid user id")
    _ -> should.be_true(False)
  }
}

pub fn auth_plus_as_space_test() {
  let qs =
    "auth_date=1791720600&user=%7B%22first_name%22%3A%22First+Last%22%2C%22id%22%3A9999%7D&hash=bbaaac8297deb38f5e21b9f5c56eef2c4057b0c7b4ed5752aa00f4ca9d3855a6"
  case auth.validate(qs, token) {
    auth.Authenticated(user) -> {
      user.first_name |> should.equal("First Last")
      user.id |> should.equal(9999)
    }
    _ -> should.be_true(False)
  }
}

pub fn auth_unicode_name_test() {
  let qs =
    "auth_date=1791720600&user=%7B%22first_name%22%3A%22%C3%89milie%22%2C%22id%22%3A9999%7D&hash=cf1ff645d4ecc3a3f8f2b7bfb14ff2043ea76e9c94cb7da018486321f7d4d696"
  case auth.validate(qs, token) {
    auth.Authenticated(user) -> {
      user.first_name |> should.equal("Émilie")
      user.id |> should.equal(9999)
    }
    _ -> should.be_true(False)
  }
}

pub fn auth_invalid_user_id_zero_test() {
  let qs =
    "auth_date=1791720600&user=%7B%22first_name%22%3A%22Zero%22%2C%22id%22%3A0%7D&hash=c234afdfa1f6c7931c890b92e78707e4a3c13b58d9b15fc867bba84a91082b84"
  case auth.validate(qs, token) {
    auth.MalformedData(msg) -> msg |> should.equal("invalid user id")
    _ -> should.be_true(False)
  }
}

pub fn auth_invalid_language_code_test() {
  // language_code contains uppercase or special chars e.g. "EN_US"
  // HMAC: e0233c91f69f143041bf13434bb4618c6f5737dbe82ab744c303a1508e3c0ee9
  let qs =
    "auth_date=1791720600&user=%7B%22first_name%22%3A%22Test%22%2C%22id%22%3A1%2C%22language_code%22%3A%22EN_US%22%7D&hash=e0233c91f69f143041bf13434bb4618c6f5737dbe82ab744c303a1508e3c0ee9"
  case auth.validate(qs, token) {
    auth.MalformedData(msg) -> msg |> should.equal("invalid user fields")
    _ -> should.be_true(False)
  }
}

pub fn auth_freshness_valid_test() {
  auth.check_freshness(valid_signed, 1_791_720_610, 300)
  |> should.be_true()
}

pub fn auth_freshness_exact_boundary_test() {
  auth.check_freshness(valid_signed, 1_791_720_900, 300)
  |> should.be_true()
}

pub fn auth_freshness_future_rejected_test() {
  auth.check_freshness(valid_signed, 1_791_720_500, 300)
  |> should.be_false()
}

pub fn auth_freshness_negative_now_rejected_test() {
  auth.check_freshness(valid_signed, -100, 300)
  |> should.be_false()
}

pub fn auth_freshness_negative_max_age_rejected_test() {
  auth.check_freshness(valid_signed, 1_791_720_610, -10)
  |> should.be_false()
}

pub fn auth_freshness_negative_skew_rejected_test() {
  auth.check_freshness_with_skew(valid_signed, 1_791_720_610, 300, -5)
  |> should.be_false()
}

pub fn auth_freshness_skew_exceeds_max_rejected_test() {
  // skew exceeds 60s policy ceiling
  auth.check_freshness_with_skew(valid_signed, 1_791_720_610, 300, 61)
  |> should.be_false()
}

pub fn auth_freshness_max_age_exceeds_policy_rejected_test() {
  // max_age exceeds 86400s (24h) policy ceiling
  auth.check_freshness(valid_signed, 1_791_720_610, 86_401)
  |> should.be_false()
}

pub fn auth_freshness_time_overflow_rejected_test() {
  // now exceeds max_safe_integer
  auth.check_freshness(valid_signed, 9_007_199_254_740_992, 300)
  |> should.be_false()
}

pub fn auth_freshness_expired_rejected_test() {
  auth.check_freshness(valid_signed, 1_791_721_000, 300)
  |> should.be_false()
}

pub fn auth_validate_fresh_valid_test() {
  case auth.validate_fresh(valid_signed, token, 1_791_720_610, 300) {
    auth.Authenticated(user) -> user.id |> should.equal(12_345)
    _ -> should.be_true(False)
  }
}

pub fn auth_validate_fresh_future_rejected_test() {
  case auth.validate_fresh(valid_signed, token, 1_791_720_500, 300) {
    auth.ExpiredData -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

pub fn auth_validate_fresh_expired_rejected_test() {
  case auth.validate_fresh(valid_signed, token, 1_791_721_000, 300) {
    auth.ExpiredData -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

pub fn auth_clock_skew_tolerance_test() {
  case
    auth.validate_fresh_with_skew(valid_signed, token, 1_791_720_590, 300, 15)
  {
    auth.Authenticated(user) -> user.id |> should.equal(12_345)
    _ -> should.be_true(False)
  }
}

pub fn auth_pt_br_language_code_accepted_test() {
  let qs =
    "auth_date=1791720600&user=%7B%22first_name%22%3A%22Alice%22%2C%22id%22%3A1%2C%22language_code%22%3A%22pt-BR%22%7D&hash=32a8172e67753393717e9f5947fbe53ac406c1063889344be7ac760dae9ff85b"
  case auth.validate(qs, token) {
    auth.Authenticated(user) -> {
      user.id |> should.equal(1)
      user.first_name |> should.equal("Alice")
      user.language_code |> should.equal("pt-BR")
    }
    _ -> should.be_true(False)
  }
}

pub fn auth_es_419_language_code_accepted_test() {
  let qs =
    "auth_date=1791720600&user=%7B%22first_name%22%3A%22Bob%22%2C%22id%22%3A2%2C%22language_code%22%3A%22es-419%22%7D&hash=cb22e2c8430fa5f2b7ab241aa08e3cd777d057a6ed89fee2a856ec939f877565"
  case auth.validate(qs, token) {
    auth.Authenticated(user) -> {
      user.id |> should.equal(2)
      user.first_name |> should.equal("Bob")
      user.language_code |> should.equal("es-419")
    }
    _ -> should.be_true(False)
  }
}

pub fn auth_c0_control_char_in_param_rejected_test() {
  // ESC (0x1B) percent-encoded as %1B in parameter value
  let qs =
    "auth_date=1791720600&custom=%1B&hash=41b5f6131c21690c9d7e4b89247e02183c3b4c8cda1856fa55b3a0b0f9222caa"
  case auth.validate(qs, token) {
    auth.MalformedData(msg) ->
      msg |> should.equal("parameter value contains invalid characters")
    _ -> should.be_true(False)
  }
}

pub fn auth_del_control_char_in_param_rejected_test() {
  // DEL (0x7F) percent-encoded as %7F in parameter value
  let qs =
    "auth_date=1791720600&custom=%7F&hash=41b5f6131c21690c9d7e4b89247e02183c3b4c8cda1856fa55b3a0b0f9222caa"
  case auth.validate(qs, token) {
    auth.MalformedData(msg) ->
      msg |> should.equal("parameter value contains invalid characters")
    _ -> should.be_true(False)
  }
}
