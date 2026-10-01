//// =============================================================================
//// [UOS-L5-COG] Pure Telegram Authority Protocol Test Suite
//// =============================================================================

import cepaf_gleam/harness/telegram_authority_protocol as proto
import gleeunit/should
import gleam/option.{None, Some}

pub fn identifier_validation_test() {
  proto.validate_identifier("valid_id-123", 64)
  |> should.equal(Ok("valid_id-123"))

  // Empty identifier rejected
  proto.validate_identifier("", 64)
  |> should.equal(Error("identifier_must_not_be_empty"))

  // Oversized identifier rejected
  proto.validate_identifier("too_long", 4)
  |> should.equal(Error("identifier_exceeds_max_length_4"))

  // NUL byte injection rejected
  proto.validate_identifier("bad\u{0000}id", 64)
  |> should.equal(Error("identifier_must_not_contain_nul_byte"))
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

  // 2. Claim runtime (NO epoch in argv!)
  proto.build_coordinator_claim_runtime_argv("sess-1", 120, "op-claim-rt")
  |> should.equal(Ok([
    "claim",
    "sess-1",
    "runtime:telegram-bridge",
    "120",
    "op-claim-rt",
  ]))

  // 3. Claim task resource (NO epoch in argv!)
  proto.build_coordinator_claim_task_argv("sess-1", "task:abc123hex", 120, "op-claim-task")
  |> should.equal(Ok([
    "claim",
    "sess-1",
    "task:abc123hex",
    "120",
    "op-claim-task",
  ]))

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

  // 5. Release with epoch
  proto.build_coordinator_release_argv("sess-1", "runtime:telegram-bridge", 2, "op-rel")
  |> should.equal(Ok([
    "release",
    "sess-1",
    "runtime:telegram-bridge",
    "2",
    "op-rel",
  ]))

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
  let valid_json = "{\"ok\": true, \"operation_id\": \"op-1\", \"operation\": \"claim\", \"epoch\": 2, \"expires_us\": 2000000000}"

  // 1. Valid claim response with future expires
  let assert Ok(receipt) =
    proto.decode_coordinator_response(valid_json, "op-1", "claim", 1000000000)
  receipt.ok |> should.equal(True)
  receipt.operation_id |> should.equal("op-1")
  receipt.operation |> should.equal("claim")
  receipt.epoch |> should.equal(2)
  receipt.expires_us |> should.equal(2000000000)

  // 2. ok: false refused
  let bad_ok = "{\"ok\": false, \"operation_id\": \"op-1\", \"operation\": \"claim\", \"epoch\": 2, \"expires_us\": 2000000000}"
  proto.decode_coordinator_response(bad_ok, "op-1", "claim", 1000000000)
  |> should.equal(Error("coordinator_response_ok_false"))

  // 3. operation_id mismatch refused
  proto.decode_coordinator_response(valid_json, "wrong-op", "claim", 1000000000)
  |> should.equal(Error("operation_id_mismatch: expected wrong-op but got op-1"))

  // 4. operation mismatch refused
  proto.decode_coordinator_response(valid_json, "op-1", "renew", 1000000000)
  |> should.equal(Error("operation_mismatch: expected renew but got claim"))

  // 5. Zero or negative epoch refused
  let zero_epoch = "{\"ok\": true, \"operation_id\": \"op-1\", \"operation\": \"claim\", \"epoch\": 0, \"expires_us\": 2000000000}"
  proto.decode_coordinator_response(zero_epoch, "op-1", "claim", 1000000000)
  |> should.equal(Error("coordinator_epoch_must_be_positive"))

  // 6. Expired lease refused
  proto.decode_coordinator_response(valid_json, "op-1", "claim", 3000000000)
  |> should.equal(Error("coordinator_lease_expiration_must_be_in_future"))
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
  let valid_emit = "{\"attempt\":\"1\",\"claimed\":\"true\",\"lease_until_ns\":\"1800000000000000000\",\"task\":\"EXECUTE\"}"

  // 1. Valid strict string-encoded response
  let assert Ok(receipt) =
    proto.decode_saplan_claim_response(valid_emit, "EXECUTE", 1000000000)
  receipt.claimed |> should.equal(True)
  receipt.task |> should.equal("EXECUTE")
  receipt.attempt |> should.equal(1)
  receipt.lease_until_ns |> should.equal(1800000000000000000)

  // 2. claimed: "false" refused
  let unobtained = "{\"attempt\":\"1\",\"claimed\":\"false\",\"lease_until_ns\":\"1800000000000000000\",\"task\":\"EXECUTE\"}"
  proto.decode_saplan_claim_response(unobtained, "EXECUTE", 1000000000)
  |> should.equal(Error("task_claim_refused_claimed_false"))

  // 3. Task mismatch refused
  proto.decode_saplan_claim_response(valid_emit, "OTHER_TASK", 1000000000)
  |> should.equal(Error("task_mismatch: expected OTHER_TASK but got EXECUTE"))

  // 4. Non-decimal attempt string refused
  let non_decimal_attempt = "{\"attempt\":\"attempt_1\",\"claimed\":\"true\",\"lease_until_ns\":\"1800000000000000000\",\"task\":\"EXECUTE\"}"
  proto.decode_saplan_claim_response(non_decimal_attempt, "EXECUTE", 1000000000)
  |> should.equal(Error("attempt_is_not_a_valid_decimal_integer"))

  // 5. Zero attempt refused
  let zero_attempt = "{\"attempt\":\"0\",\"claimed\":\"true\",\"lease_until_ns\":\"1800000000000000000\",\"task\":\"EXECUTE\"}"
  proto.decode_saplan_claim_response(zero_attempt, "EXECUTE", 1000000000)
  |> should.equal(Error("attempt_must_be_positive"))

  // 6. Expired lease refused
  proto.decode_saplan_claim_response(valid_emit, "EXECUTE", 2000000000000000000)
  |> should.equal(Error("lease_until_ns_must_be_in_future"))
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
  saplan_argv_builders_test()
  saplan_claim_response_decoder_test()
  risk_adapter_protocol_fail_closed_test()
}
