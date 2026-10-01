//// =============================================================================
//// [UOS-L5-COG] Pure Telegram Authority Protocol Test Suite
//// =============================================================================

import cepaf_gleam/harness/telegram_authority_protocol as proto
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

pub fn identifier_validation_test() {
  // 1. Generic identifier backwards compat (NO trimming!)
  proto.validate_identifier("valid_id-123", 64)
  |> should.equal(Ok("valid_id-123"))

  proto.validate_identifier("", 64)
  |> should.equal(Error("identifier_must_not_be_empty"))

  proto.validate_identifier("too_long", 4)
  |> should.equal(Error("identifier_exceeds_max_length_4"))

  proto.validate_identifier("bad\u{0000}id", 64)
  |> should.equal(Error("identifier_must_not_contain_nul_byte"))

  // Spaces are not allowed
  proto.validate_identifier("bad id", 64)
  |> should.equal(Error("identifier_contains_invalid_characters"))

  proto.validate_identifier(" bad ", 64)
  |> should.equal(Error("identifier_contains_invalid_characters"))

  // 2. Coordinator exact identifier validation
  proto.validate_coordinator_identifier("sess-1")
  |> should.equal(Ok("sess-1"))

  proto.validate_coordinator_identifier("session.123_abc:node-1")
  |> should.equal(Ok("session.123_abc:node-1"))

  // Spaces, slashes, or foreign characters rejected
  proto.validate_coordinator_identifier("bad id")
  |> should.equal(Error("invalid_coordinator_identifier"))

  proto.validate_coordinator_identifier(" op ")
  |> should.equal(Error("invalid_coordinator_identifier"))

  proto.validate_coordinator_identifier("sess/1")
  |> should.equal(Error("invalid_coordinator_identifier"))

  proto.validate_coordinator_identifier("sess$1")
  |> should.equal(Error("invalid_coordinator_identifier"))

  proto.validate_coordinator_identifier("")
  |> should.equal(Error("invalid_coordinator_identifier"))

  // 3. Workspace validation
  proto.validate_workspace("/home/an/NAS-setup/uos")
  |> should.equal(Ok("/home/an/NAS-setup/uos"))

  proto.validate_workspace("relative/path")
  |> should.equal(Error("invalid_workspace_path"))

  proto.validate_workspace("/path/../escape")
  |> should.equal(Error("invalid_workspace_path"))

  proto.validate_workspace("/path with spaces")
  |> should.equal(Error("invalid_workspace_path"))

  // 4. Revision validation
  proto.validate_revision("rev-123.abc:0")
  |> should.equal(Ok("rev-123.abc:0"))

  proto.validate_revision("rev with space")
  |> should.equal(Error("invalid_revision"))

  // 5. Tags validation
  proto.validate_tags("-")
  |> should.equal(Ok("-"))

  proto.validate_tags("plan:boot,board:sess-1")
  |> should.equal(Ok("plan:boot,board:sess-1"))

  proto.validate_tags("tag with space")
  |> should.equal(Error("invalid_tags"))

  // 6. Coordinator resource validation
  proto.validate_coordinator_resource("runtime:telegram-bridge")
  |> should.equal(Ok("runtime:telegram-bridge"))

  proto.validate_coordinator_resource("integration/main")
  |> should.equal(Ok("integration/main"))

  proto.validate_coordinator_resource("task:abc123hex")
  |> should.equal(Ok("task:abc123hex"))

  proto.validate_coordinator_resource("task:bad id")
  |> should.equal(Error("invalid_coordinator_resource"))

  proto.validate_coordinator_resource("unsupported:namespace")
  |> should.equal(Error("invalid_coordinator_resource"))

  // 7. Sa-Plan name validation
  proto.validate_saplan_name("uos/telegram-service/boot")
  |> should.equal(Ok("uos/telegram-service/boot"))

  proto.validate_saplan_name("uos/telegram/req-1/EXECUTE")
  |> should.equal(Ok("uos/telegram/req-1/EXECUTE"))

  proto.validate_saplan_name("bad name with spaces")
  |> should.equal(Error("invalid_saplan_name"))

  proto.validate_saplan_name("bad/../traversal")
  |> should.equal(Error("invalid_saplan_name"))
}

pub fn coordinator_argv_builders_test() {
  // 1. Register with service provider
  proto.build_coordinator_register_argv(
    "sess-1",
    "/home/an/NAS-setup/uos",
    "rev-123",
    "plan:boot,board:sess-1",
    "op-reg",
  )
  |> should.equal(Ok([
    "register",
    "sess-1",
    "service",
    "/home/an/NAS-setup/uos",
    "rev-123",
    "plan:boot,board:sess-1",
    "op-reg",
  ]))

  // 2. Claim runtime with valid TTL (1..3600)
  proto.build_coordinator_claim_runtime_argv("sess-1", 120, "op-claim-rt")
  |> should.equal(Ok([
    "claim",
    "sess-1",
    "runtime:telegram-bridge",
    "120",
    "op-claim-rt",
  ]))

  // TTL boundary tests: min=1, max=3600
  proto.build_coordinator_claim_runtime_argv("sess-1", 1, "op-claim-min")
  |> should.equal(Ok([
    "claim",
    "sess-1",
    "runtime:telegram-bridge",
    "1",
    "op-claim-min",
  ]))

  proto.build_coordinator_claim_runtime_argv("sess-1", 3600, "op-claim-max")
  |> should.equal(Ok([
    "claim",
    "sess-1",
    "runtime:telegram-bridge",
    "3600",
    "op-claim-max",
  ]))

  // Excess TTL rejected
  proto.build_coordinator_claim_runtime_argv("sess-1", 3601, "op-claim-excess")
  |> should.equal(Error("ttl_seconds_out_of_bounds_1_to_3600"))

  // Zero / negative TTL rejected
  proto.build_coordinator_claim_runtime_argv("sess-1", 0, "op-claim-zero")
  |> should.equal(Error("ttl_seconds_out_of_bounds_1_to_3600"))

  proto.build_coordinator_claim_runtime_argv("sess-1", -10, "op-claim-neg")
  |> should.equal(Error("ttl_seconds_out_of_bounds_1_to_3600"))

  // Invalid session identifier rejected without silent normalization
  proto.build_coordinator_claim_runtime_argv("bad id", 120, "op-claim")
  |> should.equal(Error("invalid_coordinator_identifier"))

  proto.build_coordinator_claim_runtime_argv("sess-1", 120, " op ")
  |> should.equal(Error("invalid_coordinator_identifier"))

  // 3. Claim task resource
  proto.build_coordinator_claim_task_argv("sess-1", "task:abc123hex", 120, "op-claim-task")
  |> should.equal(Ok([
    "claim",
    "sess-1",
    "task:abc123hex",
    "120",
    "op-claim-task",
  ]))

  // Invalid task resource rejected
  proto.build_coordinator_claim_task_argv("sess-1", "task:bad id", 120, "op-claim-task")
  |> should.equal(Error("invalid_coordinator_resource"))

  // 4. Renew with epoch
  proto.build_coordinator_renew_argv("sess-1", "runtime:telegram-bridge", 2, 120, "op-renew")
  |> should.equal(Ok([
    "renew",
    "sess-1",
    "runtime:telegram-bridge",
    "2",
    "120",
    "op-renew",
  ]))

  // Non-positive epoch rejected
  proto.build_coordinator_renew_argv("sess-1", "runtime:telegram-bridge", 0, 120, "op-renew")
  |> should.equal(Error("epoch_must_be_positive"))

  proto.build_coordinator_renew_argv("sess-1", "runtime:telegram-bridge", -1, 120, "op-renew")
  |> should.equal(Error("epoch_must_be_positive"))

  // 5. Release with epoch
  proto.build_coordinator_release_argv("sess-1", "runtime:telegram-bridge", 2, "op-rel")
  |> should.equal(Ok([
    "release",
    "sess-1",
    "runtime:telegram-bridge",
    "2",
    "op-rel",
  ]))

  // Non-positive epoch on release rejected
  proto.build_coordinator_release_argv("sess-1", "runtime:telegram-bridge", 0, "op-rel")
  |> should.equal(Error("epoch_must_be_positive"))

  // 6. Heartbeat
  proto.build_coordinator_heartbeat_argv("sess-1", "rev-123", "plan:boot", "op-hb")
  |> should.equal(Ok([
    "heartbeat",
    "sess-1",
    "rev-123",
    "plan:boot",
    "op-hb",
  ]))

  // 7. Retire
  proto.build_coordinator_retire_argv("sess-1", "op-ret")
  |> should.equal(Ok([
    "retire",
    "sess-1",
    "op-ret",
  ]))
}

pub fn coordinator_response_decoder_test() {
  // 1. Valid claim response with canonical expires_boot_us and positive epoch
  let valid_json =
    "{\"ok\": true, \"operation_id\": \"op-1\", \"operation\": \"claim\", \"epoch\": 2, \"expires_boot_us\": 2000000000, \"sequence\": 5, \"duplicate\": false, \"message_id\": \"\"}"

  let assert Ok(receipt) =
    proto.decode_coordinator_response(valid_json, "op-1", "claim", 1000000000)
  receipt.ok |> should.equal(True)
  receipt.operation_id |> should.equal("op-1")
  receipt.operation |> should.equal("claim")
  receipt.epoch |> should.equal(2)
  receipt.expires_boot_us |> should.equal(2000000000)

  // 2. Invented alias expires_us strictly rejected
  let alias_json =
    "{\"ok\": true, \"operation_id\": \"op-1\", \"operation\": \"claim\", \"epoch\": 2, \"expires_us\": 2000000000}"
  proto.decode_coordinator_response(alias_json, "op-1", "claim", 1000000000)
  |> should.equal(Error("malformed_coordinator_response_json"))

  // 3. Missing expires_boot_us strictly rejected
  let missing_expires =
    "{\"ok\": true, \"operation_id\": \"op-1\", \"operation\": \"claim\", \"epoch\": 2}"
  proto.decode_coordinator_response(missing_expires, "op-1", "claim", 1000000000)
  |> should.equal(Error("malformed_coordinator_response_json"))

  // 4. Null expires_boot_us strictly rejected
  let null_expires =
    "{\"ok\": true, \"operation_id\": \"op-1\", \"operation\": \"claim\", \"epoch\": 2, \"expires_boot_us\": null}"
  proto.decode_coordinator_response(null_expires, "op-1", "claim", 1000000000)
  |> should.equal(Error("malformed_coordinator_response_json"))

  // 5. ok: false refused
  let bad_ok =
    "{\"ok\": false, \"operation_id\": \"op-1\", \"operation\": \"claim\", \"epoch\": 2, \"expires_boot_us\": 2000000000}"
  proto.decode_coordinator_response(bad_ok, "op-1", "claim", 1000000000)
  |> should.equal(Error("coordinator_response_ok_false"))

  // 6. operation_id mismatch returns finite redacted error (no private value leakage)
  proto.decode_coordinator_response(valid_json, "wrong-op", "claim", 1000000000)
  |> should.equal(Error("operation_id_mismatch"))

  // 7. operation mismatch returns finite redacted error (no private value leakage)
  proto.decode_coordinator_response(valid_json, "op-1", "renew", 1000000000)
  |> should.equal(Error("operation_mismatch"))

  // 8. Zero or negative epoch refused
  let zero_epoch =
    "{\"ok\": true, \"operation_id\": \"op-1\", \"operation\": \"claim\", \"epoch\": 0, \"expires_boot_us\": 2000000000}"
  proto.decode_coordinator_response(zero_epoch, "op-1", "claim", 1000000000)
  |> should.equal(Error("coordinator_epoch_must_be_positive"))

  // 9. Expired lease refused
  proto.decode_coordinator_response(valid_json, "op-1", "claim", 3000000000)
  |> should.equal(Error("coordinator_lease_expiration_must_be_in_future"))

  // 10. Release operation accepts expired deadline but requires positive epoch
  let release_json =
    "{\"ok\": true, \"operation_id\": \"op-rel\", \"operation\": \"release\", \"epoch\": 3, \"expires_boot_us\": 0}"
  let assert Ok(rel_receipt) =
    proto.decode_coordinator_response(release_json, "op-rel", "release", 1000000000)
  rel_receipt.epoch |> should.equal(3)

  // 11. Oversized payload (> 64KB) refused
  let huge_json = string.repeat(" ", 65_537)
  proto.decode_coordinator_response(huge_json, "op-1", "claim", 1000000000)
  |> should.equal(Error("response_payload_exceeds_max_bytes"))
}

pub fn strict_positive_decimal_parser_test() {
  // Valid canonical positive decimals
  proto.parse_strict_positive_decimal("1") |> should.equal(Ok(1))
  proto.parse_strict_positive_decimal("2") |> should.equal(Ok(2))
  proto.parse_strict_positive_decimal("10") |> should.equal(Ok(10))
  proto.parse_strict_positive_decimal("2000000000") |> should.equal(Ok(2000000000))
  proto.parse_strict_positive_decimal("1800000000000000000")
  |> should.equal(Ok(1800000000000000000))

  // Non-canonical signed numbers rejected
  proto.parse_strict_positive_decimal("+1") |> should.equal(Error(Nil))
  proto.parse_strict_positive_decimal("+2000000000") |> should.equal(Error(Nil))
  proto.parse_strict_positive_decimal("-1") |> should.equal(Error(Nil))
  proto.parse_strict_positive_decimal("-5") |> should.equal(Error(Nil))

  // Leading zeros rejected
  proto.parse_strict_positive_decimal("01") |> should.equal(Error(Nil))
  proto.parse_strict_positive_decimal("007") |> should.equal(Error(Nil))
  proto.parse_strict_positive_decimal("0") |> should.equal(Error(Nil))

  // Whitespace rejected
  proto.parse_strict_positive_decimal(" 1") |> should.equal(Error(Nil))
  proto.parse_strict_positive_decimal("1 ") |> should.equal(Error(Nil))
  proto.parse_strict_positive_decimal(" 100 ") |> should.equal(Error(Nil))

  // Non-digits rejected
  proto.parse_strict_positive_decimal("1.0") |> should.equal(Error(Nil))
  proto.parse_strict_positive_decimal("1e5") |> should.equal(Error(Nil))
  proto.parse_strict_positive_decimal("abc") |> should.equal(Error(Nil))
  proto.parse_strict_positive_decimal("") |> should.equal(Error(Nil))
}

pub fn saplan_argv_builders_test() {
  proto.build_saplan_create_plan_argv("uos/telegram/req-1")
  |> should.equal(Ok([
    "--format",
    "json",
    "plan",
    "create",
    "uos/telegram/req-1",
    "uos/telegram/req-1",
    "Bounded Telegram request",
  ]))

  proto.build_saplan_create_task_argv("uos/telegram/req-1", "req-1-task")
  |> should.equal(Ok([
    "--format",
    "json",
    "task",
    "create",
    "uos/telegram/req-1",
    "EXECUTE",
    "req-1-task",
    "Bounded Telegram read and delivery",
    "-",
    "-",
    "10",
  ]))

  proto.build_saplan_claim_argv("service-worker-1", "uos/telegram/req-1")
  |> should.equal(Ok([
    "--format",
    "json",
    "task",
    "claim",
    "service-worker-1",
    "uos/telegram/req-1",
    "120000000000",
    "EXECUTE",
  ]))

  proto.build_saplan_release_argv("service-worker-1", "uos/telegram/req-1", 1)
  |> should.equal(Ok([
    "task",
    "release",
    "uos/telegram/req-1",
    "EXECUTE",
    "service-worker-1",
    "1",
  ]))
}

pub fn saplan_claim_response_decoder_test() {
  let valid_emit =
    "{\"attempt\":\"1\",\"claimed\":\"true\",\"lease_until_ns\":\"1800000000000000000\",\"task\":\"EXECUTE\"}"

  // 1. Valid strict string-encoded response
  let assert Ok(receipt) =
    proto.decode_saplan_claim_response(valid_emit, "EXECUTE", 1000000000)
  receipt.claimed |> should.equal(True)
  receipt.task |> should.equal("EXECUTE")
  receipt.attempt |> should.equal(1)
  receipt.lease_until_ns |> should.equal(1800000000000000000)

  // 2. claimed: "false" refused
  let unobtained =
    "{\"attempt\":\"1\",\"claimed\":\"false\",\"lease_until_ns\":\"1800000000000000000\",\"task\":\"EXECUTE\"}"
  proto.decode_saplan_claim_response(unobtained, "EXECUTE", 1000000000)
  |> should.equal(Error("task_claim_refused_claimed_false"))

  // 3. Task mismatch refused with redacted error
  proto.decode_saplan_claim_response(valid_emit, "OTHER_TASK", 1000000000)
  |> should.equal(Error("task_mismatch"))

  // 4. Non-canonical decimal attempt strings rejected
  let signed_attempt =
    "{\"attempt\":\"+1\",\"claimed\":\"true\",\"lease_until_ns\":\"1800000000000000000\",\"task\":\"EXECUTE\"}"
  proto.decode_saplan_claim_response(signed_attempt, "EXECUTE", 1000000000)
  |> should.equal(Error("attempt_is_not_a_valid_decimal_integer"))

  let leading_zero_attempt =
    "{\"attempt\":\"01\",\"claimed\":\"true\",\"lease_until_ns\":\"1800000000000000000\",\"task\":\"EXECUTE\"}"
  proto.decode_saplan_claim_response(leading_zero_attempt, "EXECUTE", 1000000000)
  |> should.equal(Error("attempt_is_not_a_valid_decimal_integer"))

  let zero_attempt =
    "{\"attempt\":\"0\",\"claimed\":\"true\",\"lease_until_ns\":\"1800000000000000000\",\"task\":\"EXECUTE\"}"
  proto.decode_saplan_claim_response(zero_attempt, "EXECUTE", 1000000000)
  |> should.equal(Error("attempt_is_not_a_valid_decimal_integer"))

  let alpha_attempt =
    "{\"attempt\":\"attempt_1\",\"claimed\":\"true\",\"lease_until_ns\":\"1800000000000000000\",\"task\":\"EXECUTE\"}"
  proto.decode_saplan_claim_response(alpha_attempt, "EXECUTE", 1000000000)
  |> should.equal(Error("attempt_is_not_a_valid_decimal_integer"))

  // 5. Non-canonical lease_until_ns strings rejected
  let signed_lease =
    "{\"attempt\":\"1\",\"claimed\":\"true\",\"lease_until_ns\":\"+2000000000\",\"task\":\"EXECUTE\"}"
  proto.decode_saplan_claim_response(signed_lease, "EXECUTE", 1000000000)
  |> should.equal(Error("lease_until_ns_is_not_a_valid_decimal_integer"))

  let leading_zero_lease =
    "{\"attempt\":\"1\",\"claimed\":\"true\",\"lease_until_ns\":\"0200000000\",\"task\":\"EXECUTE\"}"
  proto.decode_saplan_claim_response(leading_zero_lease, "EXECUTE", 1000000000)
  |> should.equal(Error("lease_until_ns_is_not_a_valid_decimal_integer"))

  // 6. Expired lease refused
  proto.decode_saplan_claim_response(valid_emit, "EXECUTE", 2000000000000000000)
  |> should.equal(Error("lease_until_ns_must_be_in_future"))

  // 7. Unrecognized claimed string returns redacted error
  let bad_claimed =
    "{\"attempt\":\"1\",\"claimed\":\"maybe\",\"lease_until_ns\":\"1800000000000000000\",\"task\":\"EXECUTE\"}"
  proto.decode_saplan_claim_response(bad_claimed, "EXECUTE", 1000000000)
  |> should.equal(Error("unrecognized_claimed_value"))
}

pub fn private_sentinel_non_disclosure_test() {
  let canary = "PRIVATE_SENTINEL_CANARY_SECRET_TOKEN_XYZ_12345"

  // 1. Canary in malformed coordinator JSON is not leaked in error
  let malformed_with_canary = "{\"canary\": \"" <> canary <> "\", invalid json syntax"
  case proto.decode_coordinator_response(malformed_with_canary, "op-1", "claim", 100) {
    Error(err) -> {
      string.contains(err, canary) |> should.equal(False)
      err |> should.equal("malformed_coordinator_response_json")
    }
    Ok(_) -> panic as "Malformed JSON must be rejected"
  }

  // 2. Canary in operation mismatch is not leaked in error
  let op_mismatch_with_canary =
    "{\"ok\": true, \"operation_id\": \"op-1\", \"operation\": \"" <> canary <> "\", \"epoch\": 1, \"expires_boot_us\": 2000}"
  case proto.decode_coordinator_response(op_mismatch_with_canary, "op-1", "claim", 100) {
    Error(err) -> {
      string.contains(err, canary) |> should.equal(False)
      err |> should.equal("operation_mismatch")
    }
    Ok(_) -> panic as "Operation mismatch must be rejected"
  }

  // 3. Canary in operation_id mismatch is not leaked in error
  let op_id_mismatch_with_canary =
    "{\"ok\": true, \"operation_id\": \"" <> canary <> "\", \"operation\": \"claim\", \"epoch\": 1, \"expires_boot_us\": 2000}"
  case proto.decode_coordinator_response(op_id_mismatch_with_canary, "op-1", "claim", 100) {
    Error(err) -> {
      string.contains(err, canary) |> should.equal(False)
      err |> should.equal("operation_id_mismatch")
    }
    Ok(_) -> panic as "Operation ID mismatch must be rejected"
  }

  // 4. Canary in malformed Sa-Plan claim JSON is not leaked in error
  let saplan_malformed_canary = "{\"token\": \"" <> canary <> "\", not_json"
  case proto.decode_saplan_claim_response(saplan_malformed_canary, "EXECUTE", 100) {
    Error(err) -> {
      string.contains(err, canary) |> should.equal(False)
      err |> should.equal("malformed_saplan_claim_json")
    }
    Ok(_) -> panic as "Malformed JSON must be rejected"
  }

  // 5. Canary in Sa-Plan task mismatch is not leaked in error
  let saplan_task_canary =
    "{\"attempt\":\"1\",\"claimed\":\"true\",\"lease_until_ns\":\"1800000000000000000\",\"task\":\"" <> canary <> "\"}"
  case proto.decode_saplan_claim_response(saplan_task_canary, "EXECUTE", 100) {
    Error(err) -> {
      string.contains(err, canary) |> should.equal(False)
      err |> should.equal("task_mismatch")
    }
    Ok(_) -> panic as "Task mismatch must be rejected"
  }

  // 6. Canary in unrecognized claimed value is not leaked in error
  let saplan_claimed_canary =
    "{\"attempt\":\"1\",\"claimed\":\"" <> canary <> "\",\"lease_until_ns\":\"1800000000000000000\",\"task\":\"EXECUTE\"}"
  case proto.decode_saplan_claim_response(saplan_claimed_canary, "EXECUTE", 100) {
    Error(err) -> {
      string.contains(err, canary) |> should.equal(False)
      err |> should.equal("unrecognized_claimed_value")
    }
    Ok(_) -> panic as "Unrecognized claimed value must be rejected"
  }
}

pub fn risk_adapter_protocol_fail_closed_test() {
  // 1. Missing risk adapter strictly returns Error - NO FORGED PASS
  proto.evaluate_request_risk(None, "uos/telegram/req-1", "EXECUTE")
  |> should.equal(Error("missing_risk_adapter_refused_no_forged_pass"))

  // 2. Injected adapter evaluates properly
  let mock_adapter = fn(_p, _t) { Ok("ACTIVE_OBSERVATION_PASS") }
  proto.evaluate_request_risk(Some(mock_adapter), "uos/telegram/req-1", "EXECUTE")
  |> should.equal(Ok("ACTIVE_OBSERVATION_PASS"))
}

pub fn main() {
  identifier_validation_test()
  coordinator_argv_builders_test()
  coordinator_response_decoder_test()
  strict_positive_decimal_parser_test()
  saplan_argv_builders_test()
  saplan_claim_response_decoder_test()
  private_sentinel_non_disclosure_test()
  risk_adapter_protocol_fail_closed_test()
}
