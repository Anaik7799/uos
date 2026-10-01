//// Slice 1 Verification Test Suite for Telegram Service, Client & Lifecycle
////
//// Tests:
//// 1. Local HTTP fixture integration:
////    - Normal delivery (200 OK + message_id + chat_id match)
////    - Proven rejections (400 Bad Request, 403 Forbidden)
////    - Ambiguous outcomes (502 Bad Gateway, wrong_chat mismatch, TCP drop)
////    - getUpdates JSON decoding & answerCallbackQuery
//// 2. Lifecycle adapter & cgroup Poka-Yoke:
////    - Refuses non-test units (herdr.service, user@1000.service, app.slice)
////    - Accepts valid test unit pattern (uos-tg-store-test-*)
////    - Enforces in-memory ServiceWriterHold fail-closed gate
//// 3. Authority leasing & fencing:
////    - Rejects missing authority lease
////    - Rejects expired authority lease
////    - Rejects mismatched epoch lease

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_delivery_ledger as ledger
import cepaf_gleam/harness/telegram_http_client as http_client
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_lifecycle_adapter as lifecycle
import cepaf_gleam/harness/telegram_service as service
import cepaf_gleam/harness/telegram_store as store
import cepaf_gleam/harness/telegram_store_codec as codec
import cepaf_gleam/harness/telegram_store_transport as transport
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleeunit/should
import simplifile
import uos_swarm/session_store as coord_store
import uos_swarm/session_sync as sync

const recovery_guardian_path = "/home/an/NAS-setup/uos/tools/validation/telegram_store_transport_guardian.exe"

const recovery_guardian_sha = "06a278afd304bb4752522bd632004eb35ecff8a1b65459a3607a70b24e67f0ab"

const recovery_worker_path = "/home/an/NAS-setup/uos/tools/validation/telegram_store_recovery_worker.exe"

const recovery_worker_sha = "f4f249eaa6ff2c9f4b1bf8c6587426f283ec1754892e847568b5dd1712a55b1e"



// -----------------------------------------------------------------------------
// Fixture FFI
// -----------------------------------------------------------------------------

@external(erlang, "telegram_http_test_fixture", "start")
fn fixture_start() -> Result(#(Pid, Int, String), Dynamic)

@external(erlang, "telegram_http_test_fixture", "stop")
fn fixture_stop(pid: Pid) -> Dynamic

@external(erlang, "telegram_http_test_fixture", "set_mode")
fn fixture_set_mode(pid: Pid, mode: String) -> Dynamic

@external(erlang, "telegram_http_test_fixture", "set_updates")
fn fixture_set_updates(pid: Pid, updates: List(String)) -> Dynamic

@external(erlang, "telegram_test_authority", "seed_test_sa_plan_task")
fn seed_test_sa_plan_task(
  db_path: String,
  plan_id: String,
  task_id: String,
  worker: String,
  attempt: Int,
  lease_until_ns: Int,
) -> Result(Nil, Dynamic)

// -----------------------------------------------------------------------------
// HTTP Client & Fixture Tests
// -----------------------------------------------------------------------------

pub fn http_fixture_normal_delivery_test() {
  let assert Ok(#(pid, _port, base_url)) = fixture_start()
  let config = http_client.default_configuration(base_url, "test-token-123")

  // Test sendMessage
  let outcome = http_client.send_message(config, 100, "Hello World", None)
  outcome
  |> should.equal(http_client.Delivered(message_id: 42, chat_id: 100))

  // Test answerCallbackQuery
  let callback_res =
    http_client.answer_callback_query(config, "cb-query-999", None)
  callback_res
  |> should.equal(Ok(True))

  fixture_stop(pid)
}

pub fn http_fixture_get_updates_test() {
  let assert Ok(#(pid, _port, base_url)) = fixture_start()
  let config = http_client.default_configuration(base_url, "test-token-123")

  let update_json =
    "{\"update_id\": 1001, \"message\": {\"message_id\": 50, \"chat\": {\"id\": 100, \"type\": \"private\"}, \"from\": {\"id\": 200, \"is_bot\": false, \"first_name\": \"Alice\"}, \"text\": \"/status\", \"date\": 1700000000}}"
  fixture_set_updates(pid, [update_json])

  let assert Ok(updates) = http_client.poll_updates(config, 0, 10, 5)
  let assert [u] = updates
  string.contains(u, "\"update_id\":1001")
  |> should.equal(True)
  string.contains(u, "\"/status\"")
  |> should.equal(True)

  fixture_stop(pid)
}

pub fn http_fixture_proven_rejection_forbidden_test() {
  let assert Ok(#(pid, _port, base_url)) = fixture_start()
  let config = http_client.default_configuration(base_url, "test-token-123")
  fixture_set_mode(pid, "forbidden")

  let outcome = http_client.send_message(config, 100, "Hello", None)
  outcome
  |> should.equal(
    http_client.ProvenRejection(
      error_code: 403,
      description: "bot_blocked_by_user",
    ),
  )

  fixture_stop(pid)
}

pub fn http_fixture_proven_rejection_bad_request_test() {
  let assert Ok(#(pid, _port, base_url)) = fixture_start()
  let config = http_client.default_configuration(base_url, "test-token-123")
  fixture_set_mode(pid, "bad_request")

  let outcome = http_client.send_message(config, 100, "Hello", None)
  outcome
  |> should.equal(
    http_client.ProvenRejection(
      error_code: 400,
      description: "chat_not_found",
    ),
  )

  fixture_stop(pid)
}

pub fn http_fixture_ambiguous_bad_gateway_test() {
  let assert Ok(#(pid, _port, base_url)) = fixture_start()
  let config = http_client.default_configuration(base_url, "test-token-123")
  fixture_set_mode(pid, "bad_gateway")

  let outcome = http_client.send_message(config, 100, "Hello", None)
  outcome
  |> should.equal(http_client.AmbiguousOutcome("server_error_502"))

  fixture_stop(pid)
}

pub fn http_fixture_ambiguous_wrong_chat_test() {
  let assert Ok(#(pid, _port, base_url)) = fixture_start()
  let config = http_client.default_configuration(base_url, "test-token-123")
  fixture_set_mode(pid, "wrong_chat")

  let outcome = http_client.send_message(config, 100, "Hello", None)
  outcome
  |> should.equal(
    http_client.AmbiguousOutcome(
      "chat_id_mismatch: expected 100 got 99999999",
    ),
  )

  fixture_stop(pid)
}

pub fn http_fixture_ambiguous_socket_drop_test() {
  let assert Ok(#(pid, _port, base_url)) = fixture_start()
  let config = http_client.default_configuration(base_url, "test-token-123")
  fixture_set_mode(pid, "drop")

  let outcome = http_client.send_message(config, 100, "Hello", None)
  case outcome {
    http_client.AmbiguousOutcome(reason) -> {
      let is_match =
        string.contains(reason, "closed")
        || string.contains(reason, "request_failed")
        || string.contains(reason, "http_network_error")
        || string.contains(reason, "cleanup_unknown")
        || string.contains(reason, "guardian_failed")
      is_match |> should.equal(True)
    }
    _ -> should.fail()
  }

  fixture_stop(pid)
}

// -----------------------------------------------------------------------------
// Lifecycle Adapter Tests
// -----------------------------------------------------------------------------

pub fn lifecycle_poka_yoke_unit_name_test() {
  // Valid test unit names
  lifecycle.validate_test_unit_name("uos-tg-store-test-alpha")
  |> should.equal(Ok("uos-tg-store-test-alpha"))

  lifecycle.validate_test_unit_name("uos-tg-store-test-12345")
  |> should.equal(Ok("uos-tg-store-test-12345"))

  // Strictly refused production / host units
  lifecycle.validate_test_unit_name("herdr.service")
  |> should.be_error

  lifecycle.validate_test_unit_name("user@1000.service")
  |> should.be_error

  lifecycle.validate_test_unit_name("app.slice")
  |> should.be_error

  lifecycle.validate_test_unit_name("default.slice")
  |> should.be_error

  lifecycle.validate_test_unit_name("uos-telegram-production.service")
  |> should.be_error
}

pub fn lifecycle_poka_yoke_slice_name_test() {
  // Valid test slice names
  lifecycle.validate_test_slice_name("app-uos_tg_test_alpha.slice")
  |> should.equal(Ok("app-uos_tg_test_alpha.slice"))

  lifecycle.validate_test_slice_name("app-uos_tg_test_12345")
  |> should.equal(Ok("app-uos_tg_test_12345"))

  // Strictly refused production / host slices
  lifecycle.validate_test_slice_name("app.slice")
  |> should.be_error

  lifecycle.validate_test_slice_name("app-herdr.slice")
  |> should.be_error

  lifecycle.validate_test_slice_name("user.slice")
  |> should.be_error

  lifecycle.validate_test_slice_name("default.slice")
  |> should.be_error

  lifecycle.validate_test_slice_name("uos-telegram-production.service")
  |> should.be_error
}

pub fn lifecycle_writer_gate_test() {
  // Clean state passes
  lifecycle.evaluate_writer_gate(lifecycle.ServiceWriterClean)
  |> should.equal(Ok(Nil))

  // Hold state fails closed
  let hold_res =
    lifecycle.evaluate_writer_gate(
      lifecycle.ServiceWriterHold("unquiesced_crash"),
    )
  hold_res
  |> should.equal(
    Error(
      "service_writer_held: disk mutations barred: unquiesced_crash",
    ),
  )
}

// -----------------------------------------------------------------------------
// Authority Leasing & Fencing Tests
// -----------------------------------------------------------------------------

fn make_dummy_service_state(
  authority: option.Option(service.AuthorityLease),
  writer_state: lifecycle.ServiceWriterState,
) -> service.ServiceState {
  let dummy_storage =
    transport.reviewed_local_configuration(
      "/tmp/fake-guardian",
      "0000000000000000000000000000000000000000000000000000000000000000",
      "/tmp/fake-worker",
      "0000000000000000000000000000000000000000000000000000000000000000",
      "/tmp/fake.db",
    )
  let dummy_http =
    http_client.TelegramHttpConfiguration(
      base_url: "http://127.0.0.1:9999",
      bot_token: "fake-token",
      timeout_ms: 5000,
      max_response_bytes: 65_536,
    )
  let config =
    service.default_service_configuration(
      dummy_storage,
      dummy_http,
      1,
      [#(100, 200)],
      "test-worker",
      5,
    )

  service.ServiceState(
    config: config,
    authority: authority,
    authority_revoked: False,
    writer_state: writer_state,
    pending_operation: None,
    watermark: ledger.Watermark(last_committed_offset: 0),
    watermark_version: 1,
    watermark_sha: "0000000000000000000000000000000000000000000000000000000000000000",
    expected_generation: 1,
    in_flight_poll: False,
    in_flight_workers: [],
    poll_worker: None,
    dispatch_worker: None,
    delivery_queue: [],
    recovered_records: [],
    self_subject: None,
    authority_worker: None,
    store_worker: None,
    poller_worker: None,
  )
}

pub fn service_authority_lease_missing_test() {
  let state =
    make_dummy_service_state(None, lifecycle.ServiceWriterClean)
  let now_us = 1_000_000

  let poll_res = service.poll_cycle(state, now_us)
  let assert Error(service.ServiceError(_err_state, err)) = poll_res
  err
  |> should.equal("authority_lease_missing")
}

pub fn service_authority_lease_expired_test() {
  let expired_lease =
    service.AuthorityLease(
      lease_id: "lease-1",
      expected_task_attempt: 2,
      coordinator_epoch: 1,
      valid_until_us: 500_000,
    )
  let state =
    make_dummy_service_state(Some(expired_lease), lifecycle.ServiceWriterClean)
  let now_us = 1_000_000

  let poll_res = service.poll_cycle(state, now_us)
  case poll_res {
    Error(service.ServiceError(_err_state, err)) -> {
      string.contains(err, "authority_lease_invalid_or_expired")
      |> should.equal(True)
    }
    _ -> should.fail()
  }
}

pub fn service_authority_lease_task_attempt_mismatch_test() {
  let mismatched_lease =
    service.AuthorityLease(
      lease_id: "lease-1",
      expected_task_attempt: 1,
      coordinator_epoch: 1,
      valid_until_us: 3_000_000_000_000_000,
    )
  let state =
    make_dummy_service_state(
      Some(mismatched_lease),
      lifecycle.ServiceWriterClean,
    )
  let now_us = 1_000_000

  let poll_res = service.poll_cycle(state, now_us)
  case poll_res {
    Error(service.ServiceError(_err_state, err)) -> {
      string.contains(err, "authority_lease_task_attempt_mismatch")
      |> should.equal(True)
    }
    _ -> should.fail()
  }
}

pub fn service_authority_lease_coordinator_epoch_mismatch_test() {
  let state0 =
    make_dummy_service_state(
      None,
      lifecycle.ServiceWriterClean,
    )
  let mismatched_lease =
    service.AuthorityLease(
      lease_id: "lease-1",
      expected_task_attempt: state0.config.expected_task_attempt,
      coordinator_epoch: 99,
      valid_until_us: 3_000_000_000_000_000,
    )
  let state =
    service.ServiceState(..state0, authority: Some(mismatched_lease))
  let now_us = 1_000_000

  let poll_res = service.poll_cycle(state, now_us)
  case poll_res {
    Error(service.ServiceError(_err_state, err)) -> {
      string.contains(err, "authority_lease_coordinator_epoch_mismatch")
      |> should.equal(True)
    }
    _ -> should.fail()
  }
}

pub fn service_writer_hold_bars_polling_test() {
  let valid_lease =
    service.AuthorityLease(
      lease_id: "lease-1",
      expected_task_attempt: 2,
      coordinator_epoch: 1,
      valid_until_us: 3_000_000_000_000_000,
    )
  let state =
    make_dummy_service_state(
      Some(valid_lease),
      lifecycle.ServiceWriterHold("unquiesced_crash_detected"),
    )
  let now_us = 1_000_000

  let poll_res = service.poll_cycle(state, now_us)
  let assert Error(service.ServiceError(_err_state, err)) = poll_res
  err
  |> should.equal(
    "service_writer_held: disk mutations barred: unquiesced_crash_detected",
  )
}

fn init_coordinator_epoch7(
  coord_db: String,
  session: String,
  res_name: String,
) -> Result(Nil, String) {
  use store_handle <- result.try(
    coord_store.open(coord_db)
    |> result.map_error(coord_store.error_to_string),
  )
  use _ <- result.try(
    coord_store.append(
      store_handle,
      sync.Register(session, "agy", "/home/an/NAS-setup/uos", "rev", []),
      "reg-dual",
    )
    |> result.map_error(coord_store.error_to_string),
  )
  let ttl_us = 3_600_000_000
  let cycles = [1, 2, 3, 4, 5, 6]
  use _ <- result.try(
    list.try_each(cycles, fn(i) {
      let op_c = "claim-" <> int.to_string(i)
      let op_r = "rel-" <> int.to_string(i)
      use _ <- result.try(
        coord_store.append(
          store_handle,
          sync.Claim(session, res_name, ttl_us),
          op_c,
        )
        |> result.map_error(coord_store.error_to_string),
      )
      use _ <- result.try(
        coord_store.append(
          store_handle,
          sync.Release(session, res_name, i),
          op_r,
        )
        |> result.map_error(coord_store.error_to_string),
      )
      Ok(Nil)
    }),
  )
  use _ <- result.try(
    coord_store.append(
      store_handle,
      sync.Claim(session, res_name, ttl_us),
      "claim-7",
    )
    |> result.map_error(coord_store.error_to_string),
  )
  let _ = coord_store.close(store_handle)
  Ok(Nil)
}

pub fn service_dual_authority_attempt2_epoch7_positive_and_rejection_test() {
  let unique = int.to_string(int.random(1_000_000_000))
  let dir = "/tmp/uos_tg_authority_dual_test_" <> unique
  let assert Ok(_) = simplifile.create_directory_all(dir)
  let sa_plan_db = dir <> "/sa_plan.sqlite3"
  let coord_db = dir <> "/coord.sqlite3"

  let plan_id = "plan-dual"
  let task_id = "dual-task-01"
  let res_name = "task:" <> task_id
  let worker_id = "worker-dual"
  let far_future_ns = 4_000_000_000_000_000_000

  // 1. Seed Sa-Plan task with attempt = 2
  let assert Ok(_) =
    seed_test_sa_plan_task(
      sa_plan_db,
      plan_id,
      task_id,
      worker_id,
      2,
      far_future_ns,
    )

  // 2. Seed Coordinator resource with epoch = 7
  let assert Ok(_) = init_coordinator_epoch7(coord_db, worker_id, res_name)

  let dummy_storage =
    transport.reviewed_local_configuration(
      "/tmp/fake-guardian",
      "0000000000000000000000000000000000000000000000000000000000000000",
      "/tmp/fake-worker",
      "0000000000000000000000000000000000000000000000000000000000000000",
      "/tmp/fake.db",
    )
  let dummy_http =
    http_client.TelegramHttpConfiguration(
      base_url: "http://127.0.0.1:9999",
      bot_token: "fake-token",
      timeout_ms: 5000,
      max_response_bytes: 65_536,
    )

  // Test Case A (POSITIVE): attempt 2 + epoch 7 MUST work!
  let valid_config =
    service.ServiceConfiguration(
      storage_config: dummy_storage,
      http_config: dummy_http,
      bot_id: 1,
      allowed_pairs: [#(100, 200)],
      plan_id: plan_id,
      task_id: task_id,
      session_id: worker_id,
      resource_id: res_name,
      worker_id: worker_id,
      expected_task_attempt: 2,
      coordinator_epoch: 7,
      service_epoch: 1,
      poll_limit: 10,
      poll_timeout_s: 5,
      observer_exe: service.canonical_observer_exe,
      observer_sha256: service.canonical_observer_sha256,
      guardian_exe: service.canonical_guardian_exe,
      guardian_sha256: service.canonical_guardian_sha256,
      authority_paths: service.IsolatedTestPaths(sa_plan_db, coord_db),
      control_registration_path: None,
    )
  let valid_lease =
    service.AuthorityLease(
      lease_id: "lease-dual",
      expected_task_attempt: 2,
      coordinator_epoch: 7,
      valid_until_us: 3_000_000_000_000_000,
    )
  let valid_state =
    service.ServiceState(
      config: valid_config,
      authority: Some(valid_lease),
      authority_revoked: False,
      writer_state: lifecycle.ServiceWriterClean,
      pending_operation: None,
      watermark: ledger.Watermark(last_committed_offset: 0),
      watermark_version: 1,
      watermark_sha: "0000000000000000000000000000000000000000000000000000000000000000",
      expected_generation: 1,
      in_flight_poll: False,
      in_flight_workers: [],
      poll_worker: None,
      dispatch_worker: None,
      delivery_queue: [],
      recovered_records: [],
      self_subject: None,
      authority_worker: None,
      store_worker: None,
      poller_worker: None,
    )
  let res_ok = service.verify_authority(valid_state, 1_700_000_000_000)
  case res_ok {
    Ok(_) -> Nil
    Error(_) -> should.fail()
  }

  // Test Case B (WRONG TASK ATTEMPT): expected_task_attempt = 1 (actual in DB is 2) MUST refuse!
  let wrong_attempt_config =
    service.ServiceConfiguration(..valid_config, expected_task_attempt: 1)
  let wrong_attempt_lease =
    service.AuthorityLease(..valid_lease, expected_task_attempt: 1)
  let wrong_attempt_state =
    service.ServiceState(
      ..valid_state,
      config: wrong_attempt_config,
      authority: Some(wrong_attempt_lease),
    )
  let res_err1 =
    service.verify_authority(wrong_attempt_state, 1_700_000_000_000)
  case res_err1 {
    Error(err) -> {
      string.contains(err, "task_attempt_mismatch") |> should.equal(True)
    }
    _ -> should.fail()
  }

  // Test Case C (WRONG COORDINATOR EPOCH): coordinator_epoch = 6 (actual in DB is 7) MUST refuse!
  let wrong_epoch_config =
    service.ServiceConfiguration(..valid_config, coordinator_epoch: 6)
  let wrong_epoch_lease =
    service.AuthorityLease(..valid_lease, coordinator_epoch: 6)
  let wrong_epoch_state =
    service.ServiceState(
      ..valid_state,
      config: wrong_epoch_config,
      authority: Some(wrong_epoch_lease),
    )
  let res_err2 =
    service.verify_authority(wrong_epoch_state, 1_700_000_000_000)
  case res_err2 {
    Error(err) -> {
      string.contains(err, "coordinator_fence_refused") |> should.equal(True)
    }
    _ -> should.fail()
  }

  let _ = simplifile.delete(dir)
  Nil
}

// -----------------------------------------------------------------------------
// New Feature & Resilience Tests
// -----------------------------------------------------------------------------

pub fn lifecycle_prelaunch_control_registration_positive_and_refusal_test() {
  let unique = int.to_string(int.random(1_000_000_000))
  let dir = "/tmp/uos_tg_ctrl_reg_test_" <> unique
  let assert Ok(_) = simplifile.create_directory_all(dir)
  let ctrl_path = dir <> "/control_reg.json"

  let db_path = dir <> "/test.db"
  let assert Ok(_) = simplifile.write(db_path, "sqlite_fixture_content")
  let assert Ok(inc) = lifecycle.compute_store_incarnation(db_path)
  let now_us = service.ffi_system_now_utc_us()

  let valid_reg =
    lifecycle.ControlRegistration(
      unit_name: "uos-tg-store-test-worker-1",
      slice_name: "app-uos_tg_test_slice-1.slice",
      unit_invocation_id: "inv-unit-1",
      slice_invocation_id: "inv-slice-1",
      store_incarnation_id: inc,
      store_db_path: db_path,
      worker_hash: "0000000000000000000000000000000000000000000000000000000000000000",
      guardian_hash: "0000000000000000000000000000000000000000000000000000000000000000",
      service_epoch: 1,
      registered_at_us: now_us,
    )

  // 1. Positive: write and read_and_verify
  let assert Ok(_) = lifecycle.write_prelaunch_control(ctrl_path, valid_reg)
  let read_res =
    lifecycle.read_and_verify_prelaunch_control(
      ctrl_path,
      "uos-tg-store-test-worker-1",
      db_path,
      "0000000000000000000000000000000000000000000000000000000000000000",
      "0000000000000000000000000000000000000000000000000000000000000000",
      1,
    )
  let assert Ok(reg) = read_res
  reg.unit_name |> should.equal("uos-tg-store-test-worker-1")
  reg.slice_name |> should.equal("app-uos_tg_test_slice-1.slice")
  reg.unit_invocation_id |> should.equal("inv-unit-1")
  reg.slice_invocation_id |> should.equal("inv-slice-1")
  reg.store_incarnation_id |> should.equal(inc)

  // 2. Refusal on mismatched unit
  let mismatch_unit_res =
    lifecycle.read_and_verify_prelaunch_control(
      ctrl_path,
      "uos-tg-store-test-worker-99",
      db_path,
      "0000000000000000000000000000000000000000000000000000000000000000",
      "0000000000000000000000000000000000000000000000000000000000000000",
      1,
    )
  case mismatch_unit_res {
    Error(err) -> string.contains(err, "unit_name_mismatch") |> should.equal(True)
    _ -> should.fail()
  }

  // 3. Refusal on mismatched db path
  let mismatch_db_res =
    lifecycle.read_and_verify_prelaunch_control(
      ctrl_path,
      "uos-tg-store-test-worker-1",
      "/tmp/other.db",
      "0000000000000000000000000000000000000000000000000000000000000000",
      "0000000000000000000000000000000000000000000000000000000000000000",
      1,
    )
  case mismatch_db_res {
    Error(err) -> string.contains(err, "store_db_path_mismatch") |> should.equal(True)
    _ -> should.fail()
  }

  // 4. Refusal on empty store incarnation ID
  let empty_inc_reg =
    lifecycle.ControlRegistration(..valid_reg, store_incarnation_id: "")
  let assert Ok(_) = lifecycle.write_prelaunch_control(ctrl_path, empty_inc_reg)
  lifecycle.read_and_verify_prelaunch_control(
    ctrl_path,
    "uos-tg-store-test-worker-1",
    db_path,
    "0000000000000000000000000000000000000000000000000000000000000000",
    "0000000000000000000000000000000000000000000000000000000000000000",
    1,
  )
  |> should.equal(Error("empty_store_incarnation_id_in_control_registration"))

  // 5. Refusal on empty unit invocation ID
  let empty_unit_reg =
    lifecycle.ControlRegistration(..valid_reg, unit_invocation_id: "")
  let assert Ok(_) = lifecycle.write_prelaunch_control(ctrl_path, empty_unit_reg)
  lifecycle.read_and_verify_prelaunch_control(
    ctrl_path,
    "uos-tg-store-test-worker-1",
    db_path,
    "0000000000000000000000000000000000000000000000000000000000000000",
    "0000000000000000000000000000000000000000000000000000000000000000",
    1,
  )
  |> should.equal(Error("empty_unit_invocation_id_in_control_registration"))

  // 6. Refusal on empty slice invocation ID
  let empty_slice_reg =
    lifecycle.ControlRegistration(..valid_reg, slice_invocation_id: "")
  let assert Ok(_) = lifecycle.write_prelaunch_control(ctrl_path, empty_slice_reg)
  lifecycle.read_and_verify_prelaunch_control(
    ctrl_path,
    "uos-tg-store-test-worker-1",
    db_path,
    "0000000000000000000000000000000000000000000000000000000000000000",
    "0000000000000000000000000000000000000000000000000000000000000000",
    1,
  )
  |> should.equal(Error("empty_slice_invocation_id_in_control_registration"))

  // 7. Refusal to write non-test unit name
  let illegal_reg =
    lifecycle.ControlRegistration(
      ..valid_reg,
      unit_name: "herdr.service",
    )
  let illegal_write_res =
    lifecycle.write_prelaunch_control(ctrl_path, illegal_reg)
  case illegal_write_res {
    Error(err) -> {
      string.contains(err, "refused_non_test_unit_name") |> should.equal(True)
    }
    _ -> should.fail()
  }

  let _ = simplifile.delete(dir)
  Nil
}

pub fn lifecycle_store_incarnation_test() {
  let unique = int.to_string(int.random(1_000_000_000))
  let dir = "/tmp/uos_tg_inc_test_" <> unique
  let assert Ok(_) = simplifile.create_directory_all(dir)
  let assert Ok(_) = simplifile.set_permissions_octal(dir, 0o700)
  let db_path = dir <> "/incarnation.db"

  // 1. Uncreated store returns store_file_not_found error (fail-closed)
  lifecycle.compute_store_incarnation(db_path)
  |> should.equal(Error("store_file_not_found"))

  // 2. Initialized store database produces header-bound incarnation
  let dummy_worker = recovery_worker_path
  let dummy_guardian = recovery_guardian_path
  let storage_cfg =
    transport.reviewed_local_configuration(
      dummy_guardian,
      recovery_guardian_sha,
      dummy_worker,
      recovery_worker_sha,
      db_path,
    )
  let assert Ok(_) = store.initialize_store(storage_cfg, 1)
  let assert Ok(inc1) = lifecycle.compute_store_incarnation(db_path)
  string.length(inc1) |> should.equal(64)

  // 3. Incarnation is stable across repeat reads
  let assert Ok(inc2) = lifecycle.compute_store_incarnation(db_path)
  inc1 |> should.equal(inc2)

  let _ = simplifile.delete(dir)
  Nil
}

pub fn lifecycle_live_ownership_positive_and_refusal_test() {
  let nonce = int.to_string(int.random(1_000_000_000))
  let unit_name = "uos-tg-store-test-act-" <> nonce <> ".service"
  let slice_name = "app-uos_tg_test_act_" <> nonce <> ".slice"

  let assert Ok(True) = lifecycle.start_test_slice(slice_name)
  let assert Ok(True) =
    lifecycle.run_test_unit(
      slice_name,
      unit_name,
      "/usr/bin/tail",
      ["-f", "/dev/null"],
    )

  // Query actual systemd unit and slice statuses
  let assert Ok(unit_status) = lifecycle.get_unit_status(unit_name)
  let assert Ok(slice_status) = lifecycle.get_unit_status(slice_name)

  let fake_db_path =
    "/tmp/uos_tg_fake_reg_" <> int.to_string(int.random(1_000_000_000)) <> ".db"
  let assert Ok(_) = simplifile.write(fake_db_path, "sqlite_fixture")
  let assert Ok(inc) = lifecycle.compute_store_incarnation(fake_db_path)

  let reg =
    lifecycle.ControlRegistration(
      unit_name: unit_name,
      slice_name: slice_name,
      unit_invocation_id: unit_status.invocation_id,
      slice_invocation_id: slice_status.invocation_id,
      store_incarnation_id: inc,
      store_db_path: fake_db_path,
      worker_hash: "0000000000000000000000000000000000000000000000000000000000000000",
      guardian_hash: "0000000000000000000000000000000000000000000000000000000000000000",
      service_epoch: 1,
      registered_at_us: 1_700_000_000_000,
    )

  // 1. Refusal on non-worker executable (tail): COUNTEREVIDENCE OF PRIOR FALSE ACCEPTANCE.
  // The prior candidate falsely accepted /usr/bin/tail. Hardened check strictly refuses it.
  case lifecycle.verify_live_lifecycle_ownership(reg) {
    Error(err) -> {
      string.contains(err, "refused_non_worker_executable_in_unit")
      |> should.equal(True)
    }
    _ -> should.fail()
  }

  // 2. Refusal on slice InvocationID mismatch
  let bad_slice_reg =
    lifecycle.ControlRegistration(..reg, slice_invocation_id: "inv-slice-wrong")
  case lifecycle.verify_live_lifecycle_ownership(bad_slice_reg) {
    Error(err) -> {
      string.contains(err, "slice_invocation_id_mismatch")
      |> should.equal(True)
    }
    _ -> should.fail()
  }

  // 3. Refusal on unit InvocationID mismatch
  let bad_unit_reg =
    lifecycle.ControlRegistration(..reg, unit_invocation_id: "inv-unit-wrong")
  case lifecycle.verify_live_lifecycle_ownership(bad_unit_reg) {
    Error(err) -> {
      string.contains(err, "unit_invocation_id_mismatch")
      |> should.equal(True)
    }
    _ -> should.fail()
  }

  // 4. Refusal on store incarnation mismatch
  let bad_inc_reg =
    lifecycle.ControlRegistration(
      ..reg,
      store_incarnation_id: "0000000000000000000000000000000000000000000000000000000000000000",
    )
  case lifecycle.verify_live_lifecycle_ownership(bad_inc_reg) {
    Error(err) -> {
      string.contains(err, "store_incarnation_mismatch")
      |> should.equal(True)
    }
    _ -> should.fail()
  }

  // 5. Refusal on missing store DB file
  let missing_db_reg =
    lifecycle.ControlRegistration(
      ..reg,
      store_db_path: "/tmp/nonexistent_store_db_path.db",
    )
  case lifecycle.verify_live_lifecycle_ownership(missing_db_reg) {
    Error(err) -> {
      string.contains(err, "store_file_not_found")
      |> should.equal(True)
    }
    _ -> should.fail()
  }

  // 6. Refusal on empty unit invocation ID
  let empty_unit_live =
    lifecycle.ControlRegistration(..reg, unit_invocation_id: "")
  lifecycle.verify_live_lifecycle_ownership(empty_unit_live)
  |> should.equal(Error("empty_unit_invocation_id_in_control_registration"))

  // 7. Refusal on empty slice invocation ID
  let empty_slice_live =
    lifecycle.ControlRegistration(..reg, slice_invocation_id: "")
  lifecycle.verify_live_lifecycle_ownership(empty_slice_live)
  |> should.equal(Error("empty_slice_invocation_id_in_control_registration"))

  // 8. Refusal on empty store incarnation ID
  let empty_inc_live =
    lifecycle.ControlRegistration(..reg, store_incarnation_id: "")
  lifecycle.verify_live_lifecycle_ownership(empty_inc_live)
  |> should.equal(Error("empty_store_incarnation_id_in_control_registration"))

  // Stop initial tail unit cleanly
  let _ =
    lifecycle.stop_and_verify_test_unit(
      slice_name,
      unit_name,
      fake_db_path,
      "0000000000000000000000000000000000000000000000000000000000000000",
      "0000000000000000000000000000000000000000000000000000000000000000",
    )

  // 9. Negative outside-unit probe and Positive inside-unit verification:
  // Launch genuine BEAM unit in systemd running the runner in standby mode.
  let ipc_dir = "/tmp/uos_tg_probe_ipc_" <> nonce
  let assert Ok(_) = simplifile.create_directory_all(ipc_dir)
  let cfg_json =
    "{\"mode\": \"standby\", \"ipc_dir\": \""
    <> ipc_dir
    <> "\"}"
  let cfg_file = ipc_dir <> "/worker_config.json"
  let assert Ok(_) = simplifile.write(cfg_file, cfg_json)

  let beam_unit_name = "uos-tg-store-test-act-b" <> nonce <> ".service"
  let assert Ok(True) = lifecycle.start_test_slice(slice_name)
  let assert Ok(True) =
    lifecycle.run_test_unit(
      slice_name,
      beam_unit_name,
      lifecycle.canonical_beam_exe,
      [
        "+S", "1:1", "+A", "1", "-noshell", "-eval",
        "code:add_paths(filelib:wildcard(\"/home/an/NAS-setup/uos/apps/cepaf_gleam/build/dev/erlang/*/ebin\")), telegram_service_worker_runner:start([\""
        <> cfg_file
        <> "\"]).",
      ],
    )

  // Wait for worker to be ready inside unit
  let ready_path = ipc_dir <> "/worker.ready"
  let _ = wait_for_file(ready_path, 80)

  let assert Ok(beam_unit_status) = lifecycle.get_unit_status(beam_unit_name)
  let assert Ok(fresh_slice_status) = lifecycle.get_unit_status(slice_name)
  let beam_reg =
    lifecycle.ControlRegistration(
      ..reg,
      unit_name: beam_unit_name,
      slice_invocation_id: fresh_slice_status.invocation_id,
      unit_invocation_id: beam_unit_status.invocation_id,
    )

  // Caller is outside the unit -> fails closed with cgroup_membership_mismatch!
  case lifecycle.verify_live_lifecycle_ownership(beam_reg) {
    Error(err) -> {
      string.contains(err, "cgroup_membership_mismatch")
      |> should.equal(True)
    }
    _ -> should.fail()
  }

  // 10. Positive inside-unit verification:
  // Instruct the runner INSIDE beam_unit_name to verify its own live ownership!
  let reg_file = ipc_dir <> "/control_probe.json"
  let assert Ok(_) = lifecycle.write_prelaunch_control(reg_file, beam_reg)
  let cmd_json =
    "{\"action\": \"probe_ownership\", \"control_registration_path\": \""
    <> reg_file
    <> "\"}"
  let cmd_path = ipc_dir <> "/cmd.json"
  let assert Ok(_) = simplifile.write(cmd_path, cmd_json)

  let resp_path = ipc_dir <> "/resp.json"
  let resp_content = wait_for_file(resp_path, 80)
  string.contains(resp_content, "verified") |> should.equal(True)

  // Clean stop of beam unit and slice
  let _ =
    lifecycle.stop_and_verify_test_unit(
      slice_name,
      beam_unit_name,
      fake_db_path,
      "0000000000000000000000000000000000000000000000000000000000000000",
      "0000000000000000000000000000000000000000000000000000000000000000",
    )
  let _ = lifecycle.stop_test_slice(slice_name)
  let _ = simplifile.delete(fake_db_path)
  let _ = simplifile.delete(fake_db_path <> ".incarnation")
  let _ = simplifile.delete(ipc_dir)
  Nil
}

fn wait_for_file(path: String, retries: Int) -> String {
  case simplifile.read(path) {
    Ok(content) -> content
    Error(_) -> {
      case retries > 0 {
        True -> {
          ffi_sleep_ms(50)
          wait_for_file(path, retries - 1)
        }
        False -> ""
      }
    }
  }
}

@external(erlang, "timer", "sleep")
fn ffi_sleep_ms(ms: Int) -> Nil

pub fn lifecycle_store_cookie_rejection_and_durability_test() {
  let fake_db =
    "/tmp/uos_cookie_test_" <> int.to_string(int.random(1_000_000_000)) <> ".db"
  let cookie_path = fake_db <> ".incarnation"

  // 1. Uncreated DB file fails closed
  case lifecycle.compute_store_incarnation(fake_db) {
    Error("store_file_not_found") -> Nil
    _ -> should.fail()
  }

  // 2. Create the DB file
  let assert Ok(_) = simplifile.write(fake_db, "sqlite_test_data")

  // 3. If cookie path is a DIRECTORY, compute_store_incarnation fails closed deterministically
  let assert Ok(_) = simplifile.create_directory(cookie_path)
  case lifecycle.compute_store_incarnation(fake_db) {
    Error(err) -> string.contains(err, "cookie_path_is_directory") |> should.equal(True)
    _ -> should.fail()
  }
  // Call a second time to ensure deterministic failure (no random fallback!)
  case lifecycle.compute_store_incarnation(fake_db) {
    Error(err) -> string.contains(err, "cookie_path_is_directory") |> should.equal(True)
    _ -> should.fail()
  }
  let _ = simplifile.delete(cookie_path)

  // 4. If cookie file exists with corrupt content, reject bad existing cookie
  let assert Ok(_) = simplifile.write(cookie_path, "corrupted_non_hex_cookie_value_12345")
  case lifecycle.compute_store_incarnation(fake_db) {
    Error(err) -> string.contains(err, "corrupt_cookie_file") |> should.equal(True)
    _ -> should.fail()
  }
  let _ = simplifile.delete(cookie_path)

  // 5. Clean computation creates valid cookie and is durable/stable
  let assert Ok(h1) = lifecycle.compute_store_incarnation(fake_db)
  string.length(h1) |> should.equal(64)
  let assert Ok(h2) = lifecycle.compute_store_incarnation(fake_db)
  h1 |> should.equal(h2)

  let _ = simplifile.delete(fake_db)
  let _ = simplifile.delete(cookie_path)
  Nil
}

pub fn service_admission_queue_saturation_test() {
  let valid_lease =
    service.AuthorityLease(
      lease_id: "lease-sat",
      expected_task_attempt: 4,
      coordinator_epoch: 1,
      valid_until_us: 3_000_000_000_000_000,
    )
  let state =
    make_dummy_service_state(Some(valid_lease), lifecycle.ServiceWriterClean)

  // Spawn 1 active worker to occupy the active delivery slot
  let active_worker_pid = process.spawn_unlinked(fn() { process.sleep(5000) })

  let inbox_rec =
    ledger.InboxRecord(
      update_id: 100,
      message_id: 101,
      chat_id: 200,
      user_id: 100,
      text_hash: "0000000000000000000000000000000000000000000000000000000000000000",
      status: ledger.InboxProcessing("worker-1", 1),
      created_at_ms: 1_000_000,
      bot_id: 1,
      request_id: "req-sat-1",
    )
  let chunk =
    ledger.OutboxChunk(
      request_id: "req-sat-1",
      chunk_index: 0,
      total_chunks: 1,
      chat_id: 200,
      payload: "hello",
      status: ledger.OutboxPending,
      attempt_count: 0,
      bot_id: 1,
      result_digest: "0000000000000000000000000000000000000000000000000000000000000000",
    )

  let reply_subj = process.new_subject()
  let dummy_task =
    service.DeliveryTask(
      inbox_record: inbox_rec,
      inbox_version: 1,
      inbox_sha: "0000000000000000000000000000000000000000000000000000000000000000",
      chunk: chunk,
      chunk_version: 1,
      chunk_sha: "0000000000000000000000000000000000000000000000000000000000000000",
      now_us: 1_000_000,
      reply_to: reply_subj,
    )
  let queue_16 = list.repeat(dummy_task, 16)

  let saturated_state =
    service.ServiceState(
      ..state,
      in_flight_workers: [active_worker_pid],
      delivery_queue: queue_16,
    )

  let msg =
    service.DeliverChunk(
      inbox_rec,
      1,
      "0000000000000000000000000000000000000000000000000000000000000000",
      chunk,
      1,
      "0000000000000000000000000000000000000000000000000000000000000000",
      1_000_000,
      reply_subj,
    )

  let _ = service.handle_message(saturated_state, msg)
  let reply = process.receive(reply_subj, 500)
  reply |> should.equal(Ok(Error("admission_queue_saturated")))

  process.kill(active_worker_pid)
  Nil
}

pub fn service_authority_revocation_kills_inflight_worker_test() {
  let valid_lease =
    service.AuthorityLease(
      lease_id: "lease-kill",
      expected_task_attempt: 4,
      coordinator_epoch: 1,
      valid_until_us: 3_000_000_000_000_000,
    )
  let state =
    make_dummy_service_state(Some(valid_lease), lifecycle.ServiceWriterClean)

  // Spawn an active worker process that stays alive
  let worker_pid = process.spawn_unlinked(fn() { process.sleep(10_000) })
  process.is_alive(worker_pid) |> should.equal(True)

  let state_with_worker =
    service.ServiceState(
      ..state,
      in_flight_workers: [worker_pid],
    )

  // Handle RevokeAuthority
  let _ = service.handle_message(state_with_worker, service.RevokeAuthority)

  // Allow OS/BEAM scheduler to process exit signal
  process.sleep(20)
  process.is_alive(worker_pid) |> should.equal(False)
}

pub fn service_startup_outbox_recovery_test() {
  let unique = int.to_string(int.random(1_000_000_000))
  let dir = "/tmp/uos_tg_outbox_rec_test_" <> unique
  let assert Ok(_) = simplifile.create_directory_all(dir)
  let assert Ok(_) = simplifile.set_permissions_octal(dir, 0o700)
  let db_path = dir <> "/telegram.sqlite3"

  let config =
    transport.reviewed_local_configuration(
      recovery_guardian_path,
      recovery_guardian_sha,
      recovery_worker_path,
      recovery_worker_sha,
      db_path,
    )

  let bot_id = 999_777
  let allowed_pairs = [#(100, 200)]
  let assert Ok(2) = store.initialize_store(config, bot_id)

  // 1. Ingress commit
  let assert Ok(#(wm, wm_ver, wm_sha)) = store.read_watermark(config)
  let verdict =
    guard.evaluate_update(
      "{\"update_id\": 9050, \"message\": {\"message_id\": 99, \"chat\": {\"id\": 100, \"type\": \"private\"}, \"from\": {\"id\": 200, \"is_bot\": false, \"first_name\": \"Alice\"}, \"text\": \"/recover\", \"date\": 1700000000}}",
      guard.Allowlist(bot_id: bot_id, allowed_pairs: allowed_pairs),
    )
  let assert Ok(pref) =
    store.commit_prefix(
      config,
      bot_id,
      "op-pref-9050",
      2,
      wm,
      wm_ver,
      wm_sha,
      [verdict],
      1_700_000_000_000,
    )
  let assert [inbox_rec] = pref.admitted_records

  // 2. Claim task
  let assert Ok(#(claim_rcpt, processing_rec)) =
    store.claim_task_processing(
      config,
      bot_id,
      "op-claim-9050",
      pref.receipt.generation,
      inbox_rec,
      1,
      files.digest(codec.encode_inbox_record(inbox_rec)),
      "worker-rec",
      1,
      1_700_000_001_000,
    )

  // 3. Commit result with an outbox chunk
  let processing_sha = files.digest(codec.encode_inbox_record(processing_rec))
  let assert Ok(res_result) =
    store.commit_result(
      config,
      bot_id,
      "op-res-9050",
      claim_rcpt.generation,
      processing_rec,
      2,
      processing_sha,
      ["Crash before deliver"],
      "worker-rec",
      1,
    )
  let assert [chunk0] = res_result.chunks
  let ready_rec = res_result.inbox_record

  // 4. Mark chunk as OutboxSending (simulating worker crash during send)
  let chunk_sha0 = files.digest(codec.encode_chunk_value(chunk0))
  let assert Ok(#(send_rcpt, _sending_chunk)) =
    store.commit_sending(
      config,
      bot_id,
      "op-send-9050",
      res_result.receipt.generation,
      ready_rec,
      3,
      files.digest(codec.encode_inbox_record(ready_rec)),
      chunk0,
      1,
      chunk_sha0,
      "worker-rec",
      1,
    )
  send_rcpt.generation |> should.equal(6)

  // 5. Run recover_inflight_record
  let assert Ok(#(rec_recovered, chunks_recovered)) =
    service.recover_inflight_record(config, ready_rec)

  // Verify: record becomes InboxHold("uncertain_or_failed_delivery")
  rec_recovered.status
  |> should.equal(ledger.InboxHold("uncertain_or_failed_delivery"))

  // Verify: sending chunk becomes OutboxUncertain("crash_during_send")
  let assert [recovered_chunk] = chunks_recovered
  recovered_chunk.status
  |> should.equal(ledger.OutboxUncertain("crash_during_send"))

  let _ = simplifile.delete(dir)
  Nil
}

pub fn authority_worker_independent_test() {
  let unique = int.to_string(int.random(1_000_000_000))
  let dir = "/tmp/uos_tg_authority_indep_" <> unique
  let assert Ok(_) = simplifile.create_directory_all(dir)
  let sa_plan_db = dir <> "/sa_plan.sqlite3"
  let coord_db = dir <> "/coord.sqlite3"

  let plan_id = "plan-auth-indep"
  let task_id = "auth-task-01"
  let res_name = "task:" <> task_id
  let worker_id = "worker-auth-indep"
  let far_future_ns = 4_000_000_000_000_000_000

  let assert Ok(_) =
    seed_test_sa_plan_task(
      sa_plan_db,
      plan_id,
      task_id,
      worker_id,
      2,
      far_future_ns,
    )
  let assert Ok(_) = init_coordinator_epoch7(coord_db, worker_id, res_name)

  let dummy_storage =
    transport.reviewed_local_configuration(
      recovery_guardian_path,
      recovery_guardian_sha,
      recovery_worker_path,
      recovery_worker_sha,
      "/tmp/fake.db",
    )
  let dummy_http =
    http_client.TelegramHttpConfiguration(
      base_url: "http://127.0.0.1:9999",
      bot_token: "fake-token",
      timeout_ms: 5000,
      max_response_bytes: 65_536,
    )
  let config =
    service.ServiceConfiguration(
      storage_config: dummy_storage,
      http_config: dummy_http,
      bot_id: 1,
      allowed_pairs: [#(100, 200)],
      plan_id: plan_id,
      task_id: task_id,
      session_id: worker_id,
      resource_id: res_name,
      worker_id: worker_id,
      expected_task_attempt: 2,
      coordinator_epoch: 7,
      service_epoch: 1,
      poll_limit: 10,
      poll_timeout_s: 5,
      observer_exe: service.canonical_observer_exe,
      observer_sha256: service.canonical_observer_sha256,
      guardian_exe: service.canonical_guardian_exe,
      guardian_sha256: service.canonical_guardian_sha256,
      authority_paths: service.IsolatedTestPaths(sa_plan_db, coord_db),
      control_registration_path: None,
    )
  let assert Ok(started) = service.start_authority_worker(config)
  let worker = started.data

  // 1. Ping
  let pong = process.call(worker, 5000, service.AuthorityPing)
  pong |> should.equal("pong")

  // 2. Missing lease
  let now_us = service.ffi_system_now_utc_us()
  let ver_res = service.authority_worker_verify(worker, now_us, 5000)
  ver_res |> should.equal(Error("authority_lease_missing"))

  // 3. Set valid lease
  let valid_lease =
    service.AuthorityLease(
      lease_id: "lease-auth-test-1",
      expected_task_attempt: 2,
      coordinator_epoch: 7,
      valid_until_us: now_us + 10_000_000,
    )
  service.authority_worker_set_lease(worker, valid_lease)

  // Verify valid lease
  let assert Ok(_witness) = service.authority_worker_verify(worker, now_us, 5000)

  // 4. Expired lease
  let exp_res =
    service.authority_worker_verify(worker, now_us + 20_000_000, 5000)
  exp_res |> should.equal(Error("authority_lease_invalid_or_expired"))

  // 5. Task attempt mismatch
  let mismatch_attempt_lease =
    service.AuthorityLease(
      ..valid_lease,
      expected_task_attempt: 3,
    )
  service.authority_worker_set_lease(worker, mismatch_attempt_lease)
  let att_res = service.authority_worker_verify(worker, now_us, 5000)
  att_res |> should.equal(Error("authority_lease_task_attempt_mismatch"))

  // 6. Coordinator epoch mismatch
  let mismatch_epoch_lease =
    service.AuthorityLease(
      ..valid_lease,
      coordinator_epoch: 8,
    )
  service.authority_worker_set_lease(worker, mismatch_epoch_lease)
  let ep_res = service.authority_worker_verify(worker, now_us, 5000)
  ep_res |> should.equal(Error("authority_lease_coordinator_epoch_mismatch"))

  // 7. Revoke lease
  service.authority_worker_set_lease(worker, valid_lease)
  service.authority_worker_revoke_lease(worker)
  let rev_res = service.authority_worker_verify(worker, now_us, 5000)
  rev_res |> should.equal(Error("authority_lease_revoked"))

  let _ = simplifile.delete(dir)
  Nil
}

pub fn store_worker_independent_test() {
  let dir =
    "/tmp/uos-tg-slice1-store-worker-"
    <> int.to_string(service.ffi_system_now_utc_us())
  let _ = simplifile.create_directory_all(dir)
  let assert Ok(_) = simplifile.set_permissions_octal(dir, 0o700)
  let db_path = dir <> "/store_worker.db"
  let storage_config =
    transport.reviewed_local_configuration(
      recovery_guardian_path,
      recovery_guardian_sha,
      recovery_worker_path,
      recovery_worker_sha,
      db_path,
    )
  let bot_id = 999_666
  let assert Ok(2) = store.initialize_store(storage_config, bot_id)

  let assert Ok(started) = service.start_store_worker(storage_config, bot_id)
  let worker = started.data

  // 1. Ping
  let pong = process.call(worker, 5000, service.StorePing)
  pong |> should.equal("pong")

  // 2. Read watermark
  let assert Ok(#(wm, wm_ver, wm_sha)) =
    service.store_worker_read_watermark(worker, 5000)
  wm.last_committed_offset |> should.equal(0)

  // 3. Commit prefix
  let verdict =
    guard.evaluate_update(
      "{\"update_id\": 9060, \"message\": {\"message_id\": 61, \"chat\": {\"id\": 100, \"type\": \"private\"}, \"from\": {\"id\": 200, \"is_bot\": false, \"first_name\": \"Bob\"}, \"text\": \"/test_store_worker\", \"date\": 1700000000}}",
      guard.Allowlist(bot_id: bot_id, allowed_pairs: [#(100, 200)]),
    )
  let assert Ok(pref) =
    service.store_worker_commit_prefix(
      worker,
      bot_id,
      "op-pref-worker-1",
      2,
      wm,
      wm_ver,
      wm_sha,
      [verdict],
      1_700_000_000_000,
      5000,
    )
  let assert [inbox_rec] = pref.admitted_records
  pref.receipt.generation |> should.equal(3)

  // 4. Read keys
  let assert Ok(#(gen_keys, rows)) =
    service.store_worker_read_keys(
      worker,
      [codec.input_key(inbox_rec.request_id)],
      5000,
    )
  gen_keys |> should.equal(3)
  list.length(rows) |> should.equal(1)

  // 5. Claim task processing
  let assert Ok(#(claim_rcpt, processing_rec)) =
    service.store_worker_claim_task_processing(
      worker,
      bot_id,
      "op-claim-worker-1",
      pref.receipt.generation,
      inbox_rec,
      1,
      files.digest(codec.encode_inbox_record(inbox_rec)),
      "test-worker-1",
      1,
      1_700_000_001_000,
      5000,
    )
  claim_rcpt.generation |> should.equal(4)

  // 6. Commit result
  let proc_sha = files.digest(codec.encode_inbox_record(processing_rec))
  let assert Ok(res_result) =
    service.store_worker_commit_result(
      worker,
      bot_id,
      "op-res-worker-1",
      claim_rcpt.generation,
      processing_rec,
      2,
      proc_sha,
      ["response chunk 1"],
      "test-worker-1",
      1,
      5000,
    )
  res_result.receipt.generation |> should.equal(5)
  let assert [chunk0] = res_result.chunks
  let ready_rec = res_result.inbox_record

  // 7. Commit sending
  let chunk_sha0 = files.digest(codec.encode_chunk_value(chunk0))
  let assert Ok(#(send_rcpt, sending_chunk)) =
    service.store_worker_commit_sending(
      worker,
      bot_id,
      "op-send-worker-1",
      res_result.receipt.generation,
      ready_rec,
      3,
      files.digest(codec.encode_inbox_record(ready_rec)),
      chunk0,
      1,
      chunk_sha0,
      "test-worker-1",
      1,
      5000,
    )
  send_rcpt.generation |> should.equal(6)

  // 8. Commit outcome
  let sending_sha = files.digest(codec.encode_chunk_value(sending_chunk))
  let assert Ok(#(outcome_rcpt, delivered_chunk)) =
    service.store_worker_commit_outcome(
      worker,
      bot_id,
      "op-outcome-worker-1",
      send_rcpt.generation,
      sending_chunk,
      2,
      sending_sha,
      ledger.OutboxDelivered(1234),
      5000,
    )
  outcome_rcpt.generation |> should.equal(7)

  // 9. Commit task completion
  let assert Ok(#(comp_rcpt, completed_rec)) =
    service.store_worker_commit_task_completion(
      worker,
      bot_id,
      "op-comp-worker-1",
      outcome_rcpt.generation,
      ready_rec,
      3,
      files.digest(codec.encode_inbox_record(ready_rec)),
      [delivered_chunk],
      5000,
    )
  comp_rcpt.generation |> should.equal(8)
  case completed_rec.status {
    ledger.InboxCompleted(_) -> Nil
    _ -> panic as "expected_inbox_completed"
  }

  let _ = simplifile.delete(dir)
  Nil
}

pub fn poller_worker_independent_test() {
  let assert Ok(#(fixture_pid, _port, base_url)) = fixture_start()
  let http_config =
    http_client.TelegramHttpConfiguration(
      base_url: base_url,
      bot_token: "test-token-poller",
      timeout_ms: 5000,
      max_response_bytes: 65_536,
    )
  let bot_id = 999_555

  let assert Ok(started) = service.start_poller_worker(http_config, bot_id)
  let worker = started.data

  // 1. Ping
  let pong = process.call(worker, 5000, service.PollerPing)
  pong |> should.equal("pong")

  // 2. Poll empty updates
  let assert Ok(updates) =
    service.poller_worker_get_updates(worker, 0, 100, 0, 5000)
  updates |> should.equal([])

  // 3. Poll seeded update
  let update_str =
    "{\"update_id\": 9070, \"message\": {\"message_id\": 71, \"chat\": {\"id\": 100, \"type\": \"private\"}, \"from\": {\"id\": 200, \"is_bot\": false, \"first_name\": \"Carol\"}, \"text\": \"/poller_test\", \"date\": 1700000000}}"
  fixture_set_updates(fixture_pid, [update_str])
  let assert Ok(updates2) =
    service.poller_worker_get_updates(worker, 0, 100, 0, 5000)
  let assert [u] = updates2
  string.contains(u, "\"update_id\":9070") |> should.equal(True)
  string.contains(u, "\"/poller_test\"") |> should.equal(True)

  // 4. Stop fixture and verify network failure
  fixture_stop(fixture_pid)
  let err_res = service.poller_worker_get_updates(worker, 0, 100, 0, 5000)
  case err_res {
    Error(_) -> Nil
    Ok(_) -> panic as "expected_network_error_when_fixture_stopped"
  }

  Nil
}

pub fn supervised_service_four_roles_and_rest_for_one_test() {
  process.trap_exits(True)
  let assert Ok(#(fixture_pid, _port, base_url)) = fixture_start()
  let dir =
    "/tmp/uos-tg-slice1-supervised-"
    <> int.to_string(service.ffi_system_now_utc_us())
  let _ = simplifile.create_directory_all(dir)
  let assert Ok(_) = simplifile.set_permissions_octal(dir, 0o700)
  let db_path = dir <> "/supervised.db"
  let storage_config =
    transport.reviewed_local_configuration(
      recovery_guardian_path,
      recovery_guardian_sha,
      recovery_worker_path,
      recovery_worker_sha,
      db_path,
    )
  let http_config =
    http_client.TelegramHttpConfiguration(
      base_url: base_url,
      bot_token: "test-token-supervised",
      timeout_ms: 5000,
      max_response_bytes: 65_536,
    )
  let bot_id = 999_444
  let assert Ok(2) = store.initialize_store(storage_config, bot_id)

  let config =
    service.default_service_configuration(
      storage_config,
      http_config,
      bot_id,
      [#(100, 200)],
      "worker-sup-test",
      5,
    )

  // Clear any existing worker subjects for this bot_id
  service.ffi_clear_worker_subjects(bot_id)

  let assert Ok(sup_svc) = service.start_supervised_service(config, None)

  // 1. Verify all 4 roles are active and respond to ping / getState
  let auth_pong =
    process.call(sup_svc.authority_worker, 5000, service.AuthorityPing)
  auth_pong |> should.equal("pong")

  let store_pong =
    process.call(sup_svc.store_worker, 5000, service.StorePing)
  store_pong |> should.equal("pong")

  let poller_pong =
    process.call(sup_svc.poller_worker, 5000, service.PollerPing)
  poller_pong |> should.equal("pong")

  let coord_state =
    process.call(sup_svc.actor_subject, 5000, service.GetState)
  coord_state.config.bot_id |> should.equal(bot_id)

  // 2. Test RestForOne restart:
  // Killing Child 1 (AuthorityWorker) causes RestForOne to restart Children 1, 2, 3, 4!
  let assert Ok(auth_pid) =
    process.subject_owner(sup_svc.authority_worker)
  let assert Ok(coord_pid) =
    process.subject_owner(sup_svc.actor_subject)

  process.kill(auth_pid)

  // Wait for supervisor to restart children
  process.sleep(150)

  // Old coordinator should have been restarted
  process.is_alive(coord_pid) |> should.equal(False)

  // Check new subjects in persistent_term
  let assert Ok(new_auth) =
    service.ffi_get_worker_subject(bot_id, "authority")
  let assert Ok(new_store) =
    service.ffi_get_worker_subject(bot_id, "store")
  let assert Ok(new_poller) =
    service.ffi_get_worker_subject(bot_id, "poller")
  let assert Ok(new_coord) =
    service.ffi_get_worker_subject(bot_id, "coordinator")

  // Verify newly restarted roles respond
  let new_auth_pong = process.call(new_auth, 5000, service.AuthorityPing)
  new_auth_pong |> should.equal("pong")

  let new_store_pong = process.call(new_store, 5000, service.StorePing)
  new_store_pong |> should.equal("pong")

  let new_poller_pong = process.call(new_poller, 5000, service.PollerPing)
  new_poller_pong |> should.equal("pong")

  let new_coord_state = process.call(new_coord, 5000, service.GetState)
  new_coord_state.config.bot_id |> should.equal(bot_id)

  // Clean shutdown
  service.stop_supervised_service(sup_svc)
  fixture_stop(fixture_pid)
  let _ = simplifile.delete(dir)
  Nil
}

