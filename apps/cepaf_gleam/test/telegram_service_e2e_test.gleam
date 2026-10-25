import telegram_conversation_test_io as conversation_fixture
@external(erlang,"telegram_budget_test_io","fixture")
fn budget_fixture(db:String,variant:String)->String
import telegram_verification_report_test as evidence_fixture
import telegram_managed_action_test as managed_action
import cepaf_gleam/harness/telegram_conversation as conv
import telegram_test_runner_binding as test_binding
//// End-to-End Integration & Supervised OTP Test Suite for Telegram Service
////
//// Tests complete conversation and recovery workflows:
//// 1. Full conversation lifecycle: Ingress poll -> Task claim -> Result ready ->
////    Outbox sending pre-commit -> HTTP 200 OK delivery -> Outbox delivered post-commit -> Task completion.
//// 2. Ingress rejection: Unauthorized sender rejected at store admission with zero tasks claimed.
//// 3. Bounded delivery failure: HTTP 400 Bad Request maps to OutboxFailed in store.
//// 4. Ambiguous network drop: TCP socket drop maps to OutboxUncertain (no blind retry).
//// 5. Crash recovery & cgroup quiescence: Unquiesced in-flight processing task triggers
////    fail-closed in-memory ServiceWriterHold; cleared by valid UnitCleanupReceipt.

import cepaf_gleam/harness/telegram_task_command as task_command
import cepaf_gleam/harness/observer_policy as task_observer
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
import gleam/dynamic/decode
import gleam/erlang/process.{type Pid}
import gleam/json
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleeunit/should
import simplifile
import uos_swarm/session_store as coord_store
import uos_swarm/session_sync as sync

// -----------------------------------------------------------------------------
// Pinned Fixture & Binary Paths
// -----------------------------------------------------------------------------

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

@external(erlang, "telegram_http_test_fixture", "get_requests")
fn fixture_get_requests(pid: Pid) -> List(Dynamic)

@external(erlang, "telegram_test_authority", "seed_test_sa_plan_task")
fn seed_test_sa_plan_task(
  db_path: String,
  plan_id: String,
  task_id: String,
  worker: String,
  attempt: Int,
  lease_until_ns: Int,
) -> Result(Nil, Dynamic)

fn init_test_coordinator(coord_db: String) -> Result(Nil, String) {
  use store_handle <- result.try(
    coord_store.open(coord_db)
    |> result.map_error(coord_store.error_to_string),
  )
  let sessions = [
    #("worker-e2e-01", "task:lease-e2e-01", "op1"),
    #("worker-unauth", "task:lease-e2e-02", "op2"),
    #("worker-fail", "task:lease-e2e-03", "op3"),
    #("worker-drop", "task:lease-e2e-04", "op4"),
    #("worker-recovery", "task:lease-e2e-05", "op5"),
  ]
  let ttl_us = 3_600_000_000
  let res =
    list.try_each(sessions, fn(item) {
      let #(s, res_name, op) = item
      use _ <- result.try(
        coord_store.append(
          store_handle,
          sync.Register(s, "agy", "/home/an/NAS-setup/uos", "rev", []),
          op <> "-reg",
        )
        |> result.map_error(coord_store.error_to_string),
      )
      use _ <- result.try(
        coord_store.append(
          store_handle,
          sync.Claim(s, res_name, ttl_us),
          op <> "-claim",
        )
        |> result.map_error(coord_store.error_to_string),
      )
      Ok(Nil)
    })
  let _ = coord_store.close(store_handle)
  res
}

// -----------------------------------------------------------------------------
// Helper: Ephemeral SQLite Store
// -----------------------------------------------------------------------------

fn with_recovery_store(
  test_fn: fn(transport.LocalConfiguration, String, String, String, String) -> a,
) -> a {
  let unique = int.to_string(int.random(1_000_000_000))
  let dir = "/tmp/uos_tg_service_e2e_test_" <> unique
  let assert Ok(_) = simplifile.create_directory_all(dir)
  let assert Ok(_) = simplifile.set_permissions_octal(dir, 0o700)
  let db_path = dir <> "/telegram.sqlite3"
  let sa_plan_db = dir <> "/sa_plan.sqlite3"
  let coord_db = dir <> "/coord.sqlite3"

  // Seed test authority leases for E2E tests (lease_until: 100 years in future)
  let far_future_ns = 4_000_000_000_000_000_000
  let assert Ok(_) =
    seed_test_sa_plan_task(
      sa_plan_db,
      "plan-e2e",
      "lease-e2e-01",
      "worker-e2e-01",
      1,
      far_future_ns,
    )
  let assert Ok(_) =
    seed_test_sa_plan_task(
      sa_plan_db,
      "plan-e2e",
      "lease-e2e-02",
      "worker-unauth",
      1,
      far_future_ns,
    )
  let assert Ok(_) =
    seed_test_sa_plan_task(
      sa_plan_db,
      "plan-e2e",
      "lease-e2e-03",
      "worker-fail",
      1,
      far_future_ns,
    )
  let assert Ok(_) =
    seed_test_sa_plan_task(
      sa_plan_db,
      "plan-e2e",
      "lease-e2e-04",
      "worker-drop",
      1,
      far_future_ns,
    )
  let assert Ok(_) =
    seed_test_sa_plan_task(
      sa_plan_db,
      "plan-e2e",
      "lease-e2e-05",
      "worker-recovery",
      1,
      far_future_ns,
    )

  let assert Ok(_) = init_test_coordinator(coord_db)

  let config =
    transport.reviewed_local_configuration(
      recovery_guardian_path,
      recovery_guardian_sha,
      recovery_worker_path,
      recovery_worker_sha,
      db_path,
    )
  let res = test_fn(config, db_path, sa_plan_db, coord_db, dir)
  let _ = simplifile.delete(dir)
  res
}

fn mint_test_cleanup_receipt(
  slice_name: String,
  unit_name: String,
  db_path: String,
) -> lifecycle.UnitCleanupReceipt {
  let assert Ok(True) = lifecycle.start_test_slice(slice_name)
  let assert Ok(True) =
    lifecycle.run_test_unit(
      slice_name,
      unit_name,
      lifecycle.canonical_beam_exe,
      [
        "+S", "1:1", "+A", "1", "-noshell", "-eval",
        "timer:sleep(5000), init:stop().",
      ],
    )
  let assert Ok(receipt) =
    lifecycle.stop_and_verify_test_unit(
      slice_name,
      unit_name,
      db_path,
      recovery_worker_sha,
      recovery_guardian_sha,
    )
  receipt
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

fn send_runner_cmd(ipc_dir: String, cmd_json: String) -> String {
  let cmd_tmp = ipc_dir <> "/cmd.json.tmp"
  let cmd_path = ipc_dir <> "/cmd.json"
  let resp_path = ipc_dir <> "/resp.json"
  let _ = simplifile.delete(resp_path)
  let assert Ok(_) = simplifile.write(cmd_tmp, cmd_json)
  let assert Ok(_) = simplifile.rename(cmd_tmp, cmd_path)
  // Includes bounded model execution plus native store and delivery.
  wait_for_file(resp_path, 520)
}

fn start_runner_actor(
  ipc_dir: String,
  db_path: String,
  base_url: String,
  token: String,
  bot_id: Int,
  worker_id: String,
  task_id: String,
  epoch: Int,
  sa_plan_db: String,
  coord_db: String,
  reg_path: Option(String),
  receipt: Option(lifecycle.UnitCleanupReceipt),
  supervised: Bool,
) -> Nil {
  start_runner_actor_with_conversation(ipc_dir,db_path,base_url,token,bot_id,worker_id,task_id,epoch,sa_plan_db,coord_db,reg_path,receipt,supervised,"disabled",10)
}

fn start_runner_actor_with_conversation(
  ipc_dir: String,
  db_path: String,
  base_url: String,
  token: String,
  bot_id: Int,
  worker_id: String,
  task_id: String,
  epoch: Int,
  sa_plan_db: String,
  coord_db: String,
  reg_path: Option(String),
  receipt: Option(lifecycle.UnitCleanupReceipt),
  supervised: Bool,
  conversation_mode: String,
  daily_limit: Int,
) -> Nil {
  let receipt_field = case receipt {
    None -> "\"cleanup_receipt_path\": null"
    Some(rcpt) -> {
      let receipt_file = ipc_dir <> "/cleanup_receipt.json"
      let assert Ok(_) =
        simplifile.write(
          receipt_file,
          lifecycle.encode_unit_cleanup_receipt(rcpt),
        )
      "\"cleanup_receipt_path\": \"" <> receipt_file <> "\""
    }
  }
  let reg_field = case reg_path {
    None -> "\"control_registration_path\": null"
    Some(rp) -> "\"control_registration_path\": \"" <> rp <> "\""
  }
  let sup_str = case supervised {
    True -> "true"
    False -> "false"
  }
  let cmd =
    "{\"action\": \"start_actor\", \"db_path\": \""
    <> db_path
    <> "\", \"guardian_path\": \""
    <> recovery_guardian_path
    <> "\", \"guardian_sha\": \""
    <> recovery_guardian_sha
    <> "\", \"worker_path\": \""
    <> recovery_worker_path
    <> "\", \"worker_sha\": \""
    <> recovery_worker_sha
    <> "\", \"base_url\": \""
    <> base_url
    <> "\", \"token\": \""
    <> token
    <> "\", \"bot_id\": "
    <> int.to_string(bot_id)
    <> ", \"allowed_pairs\": [[100, 200]], \"worker_id\": \""
    <> worker_id
    <> "\", \"task_id\": \""
    <> task_id
    <> "\", \"plan_id\": \"plan-e2e\", \"service_epoch\": "
    <> int.to_string(epoch)
    <> ", \"sa_plan_db\": \""
    <> sa_plan_db
    <> "\", \"coord_db\": \""
    <> coord_db
    <> "\", "
    <> reg_field
    <> ", "
    <> receipt_field
    <> ", \"supervised\": "
    <> sup_str
    <> "}"
  let cmd = "{\"conversation_mode\":\"" <> conversation_mode <> "\",\"conversation_daily_limit\":" <> int.to_string(daily_limit) <> "," <> string.drop_start(cmd,1)
  let cmd = case simplifile.is_file(db_path<>".risk.json") {
    Ok(True) -> "{\"test_risk_source\":"<>json.to_string(json.string(db_path<>".risk.json"))<>","<>string.drop_start(cmd,1)
    _ -> cmd
  }
  let cmd = case simplifile.read(db_path<>".verification.json") {
    Ok(raw) -> "{\"test_verification_source\":"<>json.to_string(json.array([db_path<>".verification.json",files.digest(raw),evidence_fixture.candidate],json.string))<>","<>string.drop_start(cmd,1)
    _ -> cmd
  }
  let cmd = case simplifile.read(db_path<>".budget-source.json") {
    Ok(raw)->"{\"test_budget_source\":"<>raw<>","<>string.drop_start(cmd,1)
    _->cmd
  }
  let resp = send_runner_cmd(ipc_dir, cmd)
  case string.contains(resp, "\"status\":\"ok\"") {
    True -> Nil
    False -> {
      echo resp
      panic as { "start_runner_actor failed: " <> resp }
    }
  }
  Nil
}

fn runner_set_authority(
  ipc_dir: String,
  lease_id: String,
  attempt: Int,
  epoch: Int,
  valid_until_us: Int,
) -> Nil {
  let cmd =
    "{\"action\": \"set_authority\", \"lease_id\": \""
    <> lease_id
    <> "\", \"attempt\": "
    <> int.to_string(attempt)
    <> ", \"epoch\": "
    <> int.to_string(epoch)
    <> ", \"valid_until_us\": "
    <> int.to_string(valid_until_us)
    <> "}"
  let resp = send_runner_cmd(ipc_dir, cmd)
  case string.contains(resp, "\"status\":\"ok\"") {
    True -> Nil
    False -> {
      echo resp
      panic as { "runner_set_authority failed: " <> resp }
    }
  }
}

fn runner_poll_cycle(ipc_dir: String, now_us: Int) -> String {
  let cmd =
    "{\"action\": \"poll_cycle\", \"now_us\": "
    <> int.to_string(now_us)
    <> "}"
  send_runner_cmd(ipc_dir, cmd)
}

fn runner_get_state(ipc_dir: String) -> String {
  send_runner_cmd(ipc_dir, "{\"action\": \"get_state\"}")
}

fn runner_deliver_chunk_from_store(
  ipc_dir: String,
  request_id: String,
  now_us: Int,
) -> String {
  let cmd =
    "{\"action\": \"deliver_chunk_from_store\", \"request_id\": \""
    <> request_id
    <> "\", \"now_us\": "
    <> int.to_string(now_us)
    <> "}"
  send_runner_cmd(ipc_dir, cmd)
}

fn runner_automatic_dispatch_tick(ipc_dir: String, now_us: Int) -> String {
  let cmd =
    "{\"action\": \"automatic_dispatch_tick\", \"now_us\": "
    <> int.to_string(now_us)
    <> "}"
  send_runner_cmd(ipc_dir, cmd)
}

fn runner_stop(ipc_dir: String) -> Nil {
  let _ = send_runner_cmd(ipc_dir, "{\"action\": \"stop\"}")
  Nil
}

fn start_test_runner(
  dir: String,
  slice_name: String,
  unit_name: String,
) -> String {
  let ipc_dir = dir <> "/ipc_" <> unit_name
  let assert Ok(_) = simplifile.create_directory_all(ipc_dir)
  let cfg_json =
    "{\"mode\": \"standby\", \"ipc_dir\": \"" <> ipc_dir <> "\"}"
  let cfg_file = ipc_dir <> "/worker_config.json"
  let assert Ok(_) = simplifile.write(cfg_file, cfg_json)

  let assert Ok(True) = lifecycle.start_test_slice(slice_name)
  let assert Ok(True) =
    lifecycle.run_test_unit_bounded(
      slice_name,
      unit_name,
      45, // Covers bounded multi-request fixture work; production is unchanged.
      lifecycle.canonical_beam_exe,
      [
        "+S", "1:1", "+A", "1", "-noshell", "-eval",
        test_binding.launch_eval(cfg_file),
      ],
    )

  // Wait for worker to be ready inside unit
  let ready_path = ipc_dir <> "/worker.ready"
  let _ = wait_for_file(ready_path, 80)
  ipc_dir
}

fn mint_unit_registration(
  dir: String,
  slice_name: String,
  unit_name: String,
  db_path: String,
  epoch: Int,
) -> String {
  let assert Ok(unit_status) = lifecycle.get_unit_status(unit_name)
  let assert Ok(slice_status) = lifecycle.get_unit_status(slice_name)

  let reg_path = dir <> "/control_" <> unit_name <> ".json"
  let assert Ok(inc) = lifecycle.compute_store_incarnation(db_path)
  let now_us = service.ffi_system_now_utc_us()
  let reg =
    lifecycle.ControlRegistration(
      unit_name: unit_name,
      slice_name: slice_name,
      unit_invocation_id: unit_status.invocation_id,
      slice_invocation_id: slice_status.invocation_id,
      store_incarnation_id: inc,
      store_db_path: db_path,
      worker_hash: recovery_worker_sha,
      guardian_hash: recovery_guardian_sha,
      service_epoch: epoch,
      registered_at_us: now_us,
    )
  let assert Ok(_) = lifecycle.write_prelaunch_control(reg_path, reg)
  reg_path
}

// -----------------------------------------------------------------------------
// E2E Tests
// -----------------------------------------------------------------------------

pub fn e2e_full_conversation_lifecycle_test() {
  use storage_config, db_path, sa_plan_db, coord_db, dir <- with_recovery_store()
  let assert Ok(#(fixture_pid, _port, base_url)) = fixture_start()

  let bot_id = 888_111
  let worker_id = "worker-e2e-01"
  let task_id = "lease-e2e-01"
  let epoch = 1

  // Initialize store schema & watermark
  let assert Ok(init_gen) = store.initialize_store(storage_config, bot_id)
  init_gen |> should.equal(2)

  let nonce = int.to_string(service.ffi_system_now_utc_us())
  let slice_name = "app-uos_tg_test_poll1024_conv_" <> nonce <> ".slice"
  let unit_name = "uos-tg-store-test-poll1024-conv-" <> nonce <> ".service"
  let ipc_dir = start_test_runner(dir, slice_name, unit_name)

  // Start actor in runner inside transient unit
  start_runner_actor(
    ipc_dir,
    db_path,
    base_url,
    "test-bot-token-e2e",
    bot_id,
    worker_id,
    task_id,
    epoch,
    sa_plan_db,
    coord_db,
    None,
    None,
    False,
  )

  // 1. Without authority lease: poll fails closed
  let err_res = runner_poll_cycle(ipc_dir, 1_700_000_000_000)
  case string.contains(err_res, "authority_lease_missing") {
    True -> Nil
    False -> panic as { "err_res unexpected: " <> err_res }
  }

  // 2. Set valid authority lease
  runner_set_authority(
    ipc_dir,
    "lease-e2e-01",
    1,
    1,
    3_000_000_000_000_000,
  )

  // 3. Ingress: queue update from authorized user (chat 100, user 200)
  let update_json =
    "{\"update_id\": 7001, \"message\": {\"message_id\": 88, \"chat\": {\"id\": 100, \"type\": \"private\"}, \"from\": {\"id\": 200, \"is_bot\": false, \"first_name\": \"Alice\"}, \"text\": \"/status\", \"date\": 1700000000}}"
  fixture_set_updates(fixture_pid, [update_json])

  // 4. Poll cycle via actor inside runner
  let poll_res = runner_poll_cycle(ipc_dir, 1_700_000_001_000)
  case string.contains(poll_res, "\"type\":\"poll_committed\"") {
    True -> Nil
    False -> panic as { "poll_res unexpected: " <> poll_res }
  }
  string.contains(poll_res, "\"count\":1") |> should.equal(True)
  string.contains(poll_res, "\"new_watermark\":7002") |> should.equal(True)

  // Verify actor state inside runner
  let state_json = runner_get_state(ipc_dir)
  string.contains(state_json, "\"last_committed_offset\":7002") |> should.equal(True)
  string.contains(state_json, "\"expected_generation\":3") |> should.equal(True)
  string.contains(state_json, "\"writer_state\":\"clean\"") |> should.equal(True)

  // 5. Read inbox record from store
  let assert Ok(#(gen1, [inbox_row])) =
    store.read_inbox_records(storage_config, 10, None)
  gen1 |> should.equal(3)
  let #(inbox_rec, inbox_ver1, inbox_sha1) = inbox_row
  inbox_rec.update_id |> should.equal(7001)
  inbox_ver1 |> should.equal(1)
  let assert ledger.InboxPending = inbox_rec.status

  // 6. Claim task for processing
  let assert Ok(#(claim_rcpt, processing_rec)) =
    store.claim_task_processing(
      storage_config,
      bot_id,
      "op-claim-7001",
      gen1,
      inbox_rec,
      inbox_ver1,
      inbox_sha1,
      worker_id,
      epoch,
      1_700_000_002_000,
    )
  claim_rcpt.generation |> should.equal(4)
  let assert ledger.InboxProcessing(w, ep) = processing_rec.status
  w |> should.equal(worker_id)
  ep |> should.equal(epoch)

  // 7. Commit result ready with response payload
  let response_payload = "System operational. All 7 engines nominal."
  let processing_ver = 2
  let processing_sha = files.digest(codec.encode_inbox_record(processing_rec))
  let assert Ok(res_result) =
    store.commit_result(
      storage_config,
      bot_id,
      "op-result-7001",
      claim_rcpt.generation,
      processing_rec,
      processing_ver,
      processing_sha,
      [response_payload],
      worker_id,
      epoch,
    )
  res_result.receipt.generation |> should.equal(5)
  let assert [_chunk0] = res_result.chunks
  let ready_rec = res_result.inbox_record
  let ready_ver = 3
  let ready_sha = files.digest(codec.encode_inbox_record(ready_rec))

  // 8. Deliver chunk via service actor inside runner
  let deliver_res = runner_deliver_chunk_from_store(ipc_dir, inbox_rec.request_id, 1_700_000_003_000)
  string.contains(deliver_res, "\"type\":\"delivery_step_success\"") |> should.equal(True)
  string.contains(deliver_res, "\"message_id\":42") |> should.equal(True)

  // 9. Verify delivered chunk in SQLite store
  let assert Ok(#(_, [chunk_row])) =
    store.read_keys(storage_config, [codec.chunk_key(inbox_rec.request_id, 0)])
  chunk_row.exists |> should.equal(True)
  chunk_row.version |> should.equal(3)
  let assert Ok(chunk_raw) = codec.decode_row_value(chunk_row)
  let assert Ok(delivered_chunk) = codec.decode_chunk_value(chunk_raw)
  delivered_chunk.status |> should.equal(ledger.OutboxDelivered(42))

  // 10. Commit task completion
  let after_deliver_gen = 7
  let assert Ok(#(comp_rcpt, completed_rec)) =
    store.commit_task_completion(
      storage_config,
      bot_id,
      "op-comp-7001",
      after_deliver_gen,
      ready_rec,
      ready_ver,
      ready_sha,
      [delivered_chunk],
    )
  comp_rcpt.generation |> should.equal(8)
  let assert ledger.InboxCompleted(_digest) = completed_rec.status

  // 11. Empty poll returns PollEmpty
  fixture_set_updates(fixture_pid, [])
  let empty_res = runner_poll_cycle(ipc_dir, 1_700_000_004_000)
  string.contains(empty_res, "\"type\":\"poll_empty\"") |> should.equal(True)

  // Clean shutdown
  runner_stop(ipc_dir)
  fixture_stop(fixture_pid)
  let _ =
    lifecycle.stop_and_verify_test_unit(
      slice_name,
      unit_name,
      db_path,
      recovery_worker_sha,
      recovery_guardian_sha,
    )
  let _ = lifecycle.stop_test_slice(slice_name)
}

pub fn e2e_unauthorized_user_rejection_test() {
  use storage_config, db_path, sa_plan_db, coord_db, dir <- with_recovery_store()
  let assert Ok(#(fixture_pid, _port, base_url)) = fixture_start()

  let bot_id = 888_222
  let worker_id = "worker-unauth"
  let task_id = "lease-e2e-02"
  let epoch = 1

  let assert Ok(2) = store.initialize_store(storage_config, bot_id)

  let nonce = int.to_string(service.ffi_system_now_utc_us()) <> int.to_string(int.random(10_000))
  let slice_name = "app-uos_tg_test_poll1024_u" <> nonce <> ".slice"
  let unit_name = "uos-tg-store-test-poll1024-u" <> nonce <> ".service"
  let ipc_dir = start_test_runner(dir, slice_name, unit_name)

  start_runner_actor(
    ipc_dir,
    db_path,
    base_url,
    "test-bot-token-e2e",
    bot_id,
    worker_id,
    task_id,
    epoch,
    sa_plan_db,
    coord_db,
    None,
    None,
    False,
  )

  runner_set_authority(
    ipc_dir,
    "lease-e2e-02",
    1,
    1,
    3_000_000_000_000_000,
  )

  // Ingress: user 999 is NOT in allowlist
  let update_json =
    "{\"update_id\": 7002, \"message\": {\"message_id\": 89, \"chat\": {\"id\": 100, \"type\": \"private\"}, \"from\": {\"id\": 999, \"is_bot\": false, \"first_name\": \"Eve\"}, \"text\": \"/admin\", \"date\": 1700000000}}"
  fixture_set_updates(fixture_pid, [update_json])

  let poll_res = runner_poll_cycle(ipc_dir, 1_700_000_005_000)
  string.contains(poll_res, "\"type\":\"poll_committed\"") |> should.equal(True)
  string.contains(poll_res, "\"new_watermark\":7003") |> should.equal(True)

  // Verify record in store is InboxRejected
  let assert Ok(#(_, [inbox_row])) =
    store.read_inbox_records(storage_config, 10, None)
  let #(inbox_rec, _, _) = inbox_row
  inbox_rec.update_id |> should.equal(7002)
  let assert ledger.InboxRejected(rej) = inbox_rec.status
  string.contains(rej, "unauthorized") |> should.equal(True)

  runner_stop(ipc_dir)
  fixture_stop(fixture_pid)
  let _ =
    lifecycle.stop_and_verify_test_unit(
      slice_name,
      unit_name,
      db_path,
      recovery_worker_sha,
      recovery_guardian_sha,
    )
  let _ = lifecycle.stop_test_slice(slice_name)
}

pub fn e2e_delivery_failure_bad_request_test() {
  use storage_config, db_path, sa_plan_db, coord_db, dir <- with_recovery_store()
  let assert Ok(#(fixture_pid, _port, base_url)) = fixture_start()

  let bot_id = 888_333
  let worker_id = "worker-fail"
  let task_id = "lease-e2e-03"
  let epoch = 1

  let assert Ok(2) = store.initialize_store(storage_config, bot_id)

  let nonce = int.to_string(service.ffi_system_now_utc_us()) <> int.to_string(int.random(10_000))
  let slice_name = "app-uos_tg_test_poll1024_b" <> nonce <> ".slice"
  let unit_name = "uos-tg-store-test-poll1024-b" <> nonce <> ".service"
  let ipc_dir = start_test_runner(dir, slice_name, unit_name)

  start_runner_actor(
    ipc_dir,
    db_path,
    base_url,
    "test-bot-token-e2e",
    bot_id,
    worker_id,
    task_id,
    epoch,
    sa_plan_db,
    coord_db,
    None,
    None,
    False,
  )

  runner_set_authority(
    ipc_dir,
    "lease-e2e-03",
    1,
    1,
    3_000_000_000_000_000,
  )

  // Ingress & Claim
  let update_json =
    "{\"update_id\": 7003, \"message\": {\"message_id\": 90, \"chat\": {\"id\": 100, \"type\": \"private\"}, \"from\": {\"id\": 200, \"is_bot\": false, \"first_name\": \"Alice\"}, \"text\": \"/large\", \"date\": 1700000000}}"
  fixture_set_updates(fixture_pid, [update_json])

  let poll_res = runner_poll_cycle(ipc_dir, 1_700_000_006_000)
  string.contains(poll_res, "\"type\":\"poll_committed\"") |> should.equal(True)
  string.contains(poll_res, "\"new_watermark\":7004") |> should.equal(True)

  let assert Ok(#(gen1, [inbox_row])) =
    store.read_inbox_records(storage_config, 10, None)
  let #(inbox_rec, inbox_ver1, inbox_sha1) = inbox_row
  let assert Ok(#(claim_rcpt, proc_rec)) =
    store.claim_task_processing(
      storage_config,
      bot_id,
      "op-claim-7003",
      gen1,
      inbox_rec,
      inbox_ver1,
      inbox_sha1,
      worker_id,
      epoch,
      1_700_000_007_000,
    )

  let proc_sha = files.digest(codec.encode_inbox_record(proc_rec))
  let assert Ok(res_result) =
    store.commit_result(
      storage_config,
      bot_id,
      "op-result-7003",
      claim_rcpt.generation,
      proc_rec,
      2,
      proc_sha,
      ["Oversized Payload"],
      worker_id,
      epoch,
    )
  let assert [_chunk0] = res_result.chunks

  // Set HTTP fixture to Bad Request (400)
  fixture_set_mode(fixture_pid, "bad_request")

  // Deliver chunk via runner
  let deliver_res = runner_deliver_chunk_from_store(ipc_dir, inbox_rec.request_id, 1_700_000_008_000)
  string.contains(deliver_res, "\"type\":\"delivery_step_failed\"") |> should.equal(True)
  string.contains(deliver_res, "http_rejected_400") |> should.equal(True)

  // Verify chunk in store has OutboxFailed
  let assert Ok(#(_, [chunk_row])) =
    store.read_keys(storage_config, [codec.chunk_key(inbox_rec.request_id, 0)])
  let assert Ok(chunk_raw) = codec.decode_row_value(chunk_row)
  let assert Ok(failed_chunk) = codec.decode_chunk_value(chunk_raw)
  let assert ledger.OutboxFailed(reason) = failed_chunk.status
  string.contains(reason, "400") |> should.equal(True)

  runner_stop(ipc_dir)
  fixture_stop(fixture_pid)
  let _ =
    lifecycle.stop_and_verify_test_unit(
      slice_name,
      unit_name,
      db_path,
      recovery_worker_sha,
      recovery_guardian_sha,
    )
  let _ = lifecycle.stop_test_slice(slice_name)
}

pub fn e2e_delivery_ambiguous_socket_drop_test() {
  use storage_config, db_path, sa_plan_db, coord_db, dir <- with_recovery_store()
  let assert Ok(#(fixture_pid, _port, base_url)) = fixture_start()

  let bot_id = 888_444
  let _allowed_pairs = [#(100, 200)]
  let worker_id = "worker-drop"
  let task_id = "lease-e2e-04"
  let epoch = 1

  let assert Ok(2) = store.initialize_store(storage_config, bot_id)

  let nonce = int.to_string(service.ffi_system_now_utc_us()) <> int.to_string(int.random(10_000))
  let slice_name = "app-uos_tg_test_poll1024_d" <> nonce <> ".slice"
  let unit_name = "uos-tg-store-test-poll1024-d" <> nonce <> ".service"
  let ipc_dir = start_test_runner(dir, slice_name, unit_name)

  start_runner_actor(
    ipc_dir,
    db_path,
    base_url,
    "test-bot-token-e2e",
    bot_id,
    worker_id,
    task_id,
    epoch,
    sa_plan_db,
    coord_db,
    None,
    None,
    False,
  )

  runner_set_authority(
    ipc_dir,
    "lease-e2e-04",
    1,
    1,
    3_000_000_000_000_000,
  )

  // Ingress & Claim
  let update_json =
    "{\"update_id\": 7004, \"message\": {\"message_id\": 91, \"chat\": {\"id\": 100, \"type\": \"private\"}, \"from\": {\"id\": 200, \"is_bot\": false, \"first_name\": \"Alice\"}, \"text\": \"/drop\", \"date\": 1700000000}}"
  fixture_set_updates(fixture_pid, [update_json])

  let poll_res = runner_poll_cycle(ipc_dir, 1_700_000_009_000)
  string.contains(poll_res, "\"type\":\"poll_committed\"") |> should.equal(True)
  string.contains(poll_res, "\"new_watermark\":7005") |> should.equal(True)

  let assert Ok(#(gen1, [inbox_row])) =
    store.read_inbox_records(storage_config, 10, None)
  let #(inbox_rec, inbox_ver1, inbox_sha1) = inbox_row
  let assert Ok(#(claim_rcpt, proc_rec)) =
    store.claim_task_processing(
      storage_config,
      bot_id,
      "op-claim-7004",
      gen1,
      inbox_rec,
      inbox_ver1,
      inbox_sha1,
      worker_id,
      epoch,
      1_700_000_010_000,
    )

  let proc_sha = files.digest(codec.encode_inbox_record(proc_rec))
  let assert Ok(res_result) =
    store.commit_result(
      storage_config,
      bot_id,
      "op-result-7004",
      claim_rcpt.generation,
      proc_rec,
      2,
      proc_sha,
      ["Drop Payload"],
      worker_id,
      epoch,
    )
  let assert [_chunk0] = res_result.chunks

  // Set HTTP fixture to Socket Drop
  fixture_set_mode(fixture_pid, "drop")

  // Deliver chunk via runner
  let deliver_res = runner_deliver_chunk_from_store(ipc_dir, inbox_rec.request_id, 1_700_000_011_000)
  string.contains(deliver_res, "\"type\":\"delivery_step_uncertain\"") |> should.equal(True)
  let is_match =
    string.contains(deliver_res, "closed")
    || string.contains(deliver_res, "request_failed")
    || string.contains(deliver_res, "cleanup_unknown")
    || string.contains(deliver_res, "guardian_failed")
  is_match |> should.equal(True)

  // Verify chunk in store has OutboxUncertain
  let assert Ok(#(_, [chunk_row])) =
    store.read_keys(storage_config, [codec.chunk_key(inbox_rec.request_id, 0)])
  let assert Ok(chunk_raw) = codec.decode_row_value(chunk_row)
  let assert Ok(uncertain_chunk) = codec.decode_chunk_value(chunk_raw)
  let assert ledger.OutboxUncertain(unc_reason) = uncertain_chunk.status
  let is_unc_match =
    string.contains(unc_reason, "closed")
    || string.contains(unc_reason, "request_failed")
    || string.contains(unc_reason, "cleanup_unknown")
    || string.contains(unc_reason, "guardian_failed")
  is_unc_match |> should.equal(True)

  runner_stop(ipc_dir)
  fixture_stop(fixture_pid)
  let _ =
    lifecycle.stop_and_verify_test_unit(
      slice_name,
      unit_name,
      db_path,
      recovery_worker_sha,
      recovery_guardian_sha,
    )
  let _ = lifecycle.stop_test_slice(slice_name)
}

pub fn e2e_recovery_cgroup_and_writer_hold_test() {
  use storage_config, db_path, sa_plan_db, coord_db, dir <- with_recovery_store()

  let bot_id = 888_555
  let allowed_pairs = [#(100, 200)]
  let worker_id = "worker-recovery"
  let task_id = "lease-e2e-05"
  let epoch = 1

  let assert Ok(2) = store.initialize_store(storage_config, bot_id)

  let http_cfg =
    http_client.default_configuration("http://127.0.0.1:9", "test-token")
  let svc_cfg =
    service.ServiceConfiguration(
      storage_config: storage_config,
      http_config: http_cfg,
      bot_id: bot_id,
      allowed_pairs: allowed_pairs,
      plan_id: "plan-e2e",
      task_id: task_id,
      session_id: worker_id,
      resource_id: "task:" <> task_id,
      worker_id: worker_id,
      expected_task_attempt: 1,
      coordinator_epoch: 1,
      service_epoch: epoch,
      poll_limit: 10,
      poll_timeout_s: 1,
      observer_exe: service.canonical_observer_exe,
      observer_sha256: service.canonical_observer_sha256,
      guardian_exe: service.canonical_guardian_exe,
      guardian_sha256: service.canonical_guardian_sha256,
      authority_paths: service.IsolatedTestPaths(sa_plan_db, coord_db),
      control_registration_path: None,
      conversation: service.ConversationDisabled,
      actions: None,
      risk_source: None,
      verification_source: None,
      budget_source: None,
    )

  // 1. Commit an initial record to store
  let assert Ok(#(wm, wm_ver, wm_sha)) = store.read_watermark(storage_config)
  let verdict =
    guard.evaluate_update(
      "{\"update_id\": 7005, \"message\": {\"message_id\": 92, \"chat\": {\"id\": 100, \"type\": \"private\"}, \"from\": {\"id\": 200, \"is_bot\": false, \"first_name\": \"Alice\"}, \"text\": \"/crash\", \"date\": 1700000000}}",
      guard.Allowlist(bot_id: bot_id, allowed_pairs: allowed_pairs),
    )
  let assert Ok(pref) =
    store.commit_prefix(
      storage_config,
      bot_id,
      "op-pref-7005",
      2,
      wm,
      wm_ver,
      wm_sha,
      [verdict],
      1_700_000_012_000,
    )
  let assert [_inbox_rec] = pref.admitted_records

  // 2. Start transient unit 1 running telegram_service_worker_runner
  let nonce = int.to_string(service.ffi_system_now_utc_us()) <> int.to_string(int.random(10_000))
  let slice_name = "app-uos_tg_test_poll1024_r" <> nonce <> ".slice"
  let unit_name1 = "uos-tg-store-test-poll1024-r1" <> nonce <> ".service"
  let ipc_dir1 = dir <> "/ipc_" <> unit_name1
  let assert Ok(_) = simplifile.create_directory_all(ipc_dir1)
  let cfg_json1 = "{\"mode\": \"standby\", \"ipc_dir\": \"" <> ipc_dir1 <> "\"}"
  let cfg_file1 = ipc_dir1 <> "/worker_config.json"
  let assert Ok(_) = simplifile.write(cfg_file1, cfg_json1)

  let assert Ok(True) = lifecycle.start_test_slice(slice_name)
  let assert Ok(True) =
    lifecycle.run_test_unit(
      slice_name,
      unit_name1,
      lifecycle.canonical_beam_exe,
      [
        "+S", "1:1", "+A", "1", "-noshell", "-eval",
        test_binding.launch_eval(cfg_file1),
      ],
    )
  let _ = wait_for_file(ipc_dir1 <> "/worker.ready", 80)

  let assert Ok(unit_status1) = lifecycle.get_unit_status(unit_name1)
  let assert Ok(slice_status1) = lifecycle.get_unit_status(slice_name)
  let reg_path1 = dir <> "/control_r1_" <> nonce <> ".json"
  let assert Ok(inc) = lifecycle.compute_store_incarnation(db_path)
  let now_us = service.ffi_system_now_utc_us()
  let reg1 =
    lifecycle.ControlRegistration(
      unit_name: unit_name1,
      slice_name: slice_name,
      unit_invocation_id: unit_status1.invocation_id,
      slice_invocation_id: slice_status1.invocation_id,
      store_incarnation_id: inc,
      store_db_path: db_path,
      worker_hash: recovery_worker_sha,
      guardian_hash: recovery_guardian_sha,
      service_epoch: epoch,
      registered_at_us: now_us,
    )
  let assert Ok(_) = lifecycle.write_prelaunch_control(reg_path1, reg1)

  // 3. Instruct unit 1 to claim the task in store and hang (simulating crash)
  let claim_hang_cmd =
    "{\"action\": \"claim_processing_and_hang\", \"db_path\": \""
    <> db_path
    <> "\", \"bot_id\": "
    <> int.to_string(bot_id)
    <> ", \"worker_id\": \""
    <> worker_id
    <> "\", \"service_epoch\": "
    <> int.to_string(epoch)
    <> ", \"now_us\": 1700000013000}"
  let claim_resp = send_runner_cmd(ipc_dir1, claim_hang_cmd)
  string.contains(claim_resp, "\"status\":\"claimed\"") |> should.equal(True)

  // Verify task in store is in InboxProcessing state
  let assert Ok(#(_, [inbox_row_crashed])) =
    store.read_inbox_records(storage_config, 10, None)
  let #(rec_crashed, _, _) = inbox_row_crashed
  let assert ledger.InboxProcessing(_, _) = rec_crashed.status

  // 4. Restart service WITHOUT cleanup receipt -> must hold truthfully without inventing counts
  let assert Ok(#(state_held, service.RecoveryHold(reason))) =
    service.init_service(svc_cfg, None)
  let assert lifecycle.ServiceWriterHold(state_reason) = state_held.writer_state
  string.contains(state_reason, "first_bootstrap_rejected: in-flight operations detected")
  |> should.equal(True)
  string.contains(reason, "first_bootstrap_rejected: in-flight operations detected")
  |> should.equal(True)

  // Writer hold bars mutations
  let lease =
    service.AuthorityLease(
      lease_id: "lease-e2e-05",
      expected_task_attempt: 1,
      coordinator_epoch: 1,
      valid_until_us: 3_000_000_000_000_000,
    )
  let state_with_auth = service.set_authority(state_held, lease)
  let poll_fail = service.poll_cycle(state_with_auth, 1_700_000_014_000)
  let assert Error(service.ServiceError(_err_state, poll_err)) = poll_fail
  string.contains(poll_err, "service_writer_held") |> should.equal(True)

  // 5. Kill unit 1 -> physically terminates the real writer VM, verifies empty cgroup, mints receipt1
  let assert Ok(receipt1) =
    lifecycle.stop_and_verify_test_unit_epoch(
      slice_name,
      unit_name1,
      db_path,
      recovery_worker_sha,
      recovery_guardian_sha,
      epoch,
    )

  // 6. Start transient unit 2 running telegram_service_worker_runner
  let unit_name2 = "uos-tg-store-test-poll1024-r2" <> nonce <> ".service"
  let ipc_dir2 = dir <> "/ipc_" <> unit_name2
  let assert Ok(_) = simplifile.create_directory_all(ipc_dir2)
  let cfg_json2 = "{\"mode\": \"standby\", \"ipc_dir\": \"" <> ipc_dir2 <> "\"}"
  let cfg_file2 = ipc_dir2 <> "/worker_config.json"
  let assert Ok(_) = simplifile.write(cfg_file2, cfg_json2)

  let assert Ok(True) = lifecycle.start_test_slice(slice_name)
  let assert Ok(True) =
    lifecycle.run_test_unit(
      slice_name,
      unit_name2,
      lifecycle.canonical_beam_exe,
      [
        "+S", "1:1", "+A", "1", "-noshell", "-eval",
        test_binding.launch_eval(cfg_file2),
      ],
    )
  let _ = wait_for_file(ipc_dir2 <> "/worker.ready", 80)

  // Write receipt1 to file for unit 2 to read
  let receipt1_file = ipc_dir2 <> "/receipt1.json"
  let assert Ok(_) =
    simplifile.write(
      receipt1_file,
      lifecycle.encode_unit_cleanup_receipt(receipt1),
    )

  // 7. Restart service WITH verified cleanup receipt and live control registration inside unit 2
  // Successor epoch must be epoch + 1 = 2, pointing to predecessor registration reg_path1
  let init_cmd2 =
    "{\"action\": \"init_only\", \"db_path\": \""
    <> db_path
    <> "\", \"bot_id\": "
    <> int.to_string(bot_id)
    <> ", \"worker_id\": \""
    <> worker_id
    <> "\", \"task_id\": \""
    <> task_id
    <> "\", \"service_epoch\": "
    <> int.to_string(epoch + 1)
    <> ", \"sa_plan_db\": \""
    <> sa_plan_db
    <> "\", \"coord_db\": \""
    <> coord_db
    <> "\", \"control_registration_path\": \""
    <> reg_path1
    <> "\", \"cleanup_receipt_path\": \""
    <> receipt1_file
    <> "\"}"
  let init_resp2 = send_runner_cmd(ipc_dir2, init_cmd2)
  string.contains(init_resp2, "\"status\":\"ok\"") |> should.equal(True)
  string.contains(init_resp2, "\"writer_state\":\"clean\"") |> should.equal(True)
  string.contains(init_resp2, "\"held_count\":1") |> should.equal(True)

  // 8. Refusal on consumed receipt reuse (prevents restart reuse of old cleanup receipt)
  let replay_resp = send_runner_cmd(ipc_dir2, init_cmd2)
  string.contains(replay_resp, "cleanup_receipt_already_consumed") |> should.equal(True)

  // Cleanup active test unit and slice
  runner_stop(ipc_dir2)
  let _ =
    lifecycle.stop_and_verify_test_unit(
      slice_name,
      unit_name2,
      db_path,
      recovery_worker_sha,
      recovery_guardian_sha,
    )
  let _ = lifecycle.stop_test_slice(slice_name)
}

fn exercise_automatic_command_dispatch(first_command: String, first_expected: String, second_command: String, second_expected: String) {
  exercise_conversation_dispatch(first_command,first_expected,second_command,second_expected,"disabled",10)
}

fn exercise_conversation_dispatch(first_command: String, first_expected: String, second_command: String, second_expected: String, mode: String, daily_limit: Int) {
  exercise_configured_dispatch(first_command,first_expected,second_command,second_expected,mode,daily_limit,"")
}

@external(erlang,"telegram_fmea_test_io","fixture")
fn risk_fixture(plan:String,variant:String)->String

fn exercise_configured_dispatch(first_command: String, first_expected: String, second_command: String, second_expected: String, mode: String, daily_limit: Int,risk_case:String) {
  use storage_config, db_path, sa_plan_db, coord_db, dir <- with_recovery_store()
  case risk_case {
    "budget" | "budget_missing" | "budget_badsha" -> {
      let assert Ok(_) = simplifile.write(db_path<>".budget-source.json",budget_fixture(db_path,risk_case))
      Nil
    }
    "" -> Nil
    "verification" | "verification_changed" | "verification_stale" | "verification_foreign" | "verification_missing" | "verification_all" -> {
      let variant=case risk_case {"verification_stale"->"stale" "verification_foreign"->"foreign" "verification_all"->"all" _->"empty"}
      let assert Ok(_) = simplifile.write(db_path<>".verification.json",evidence_fixture.fixture(service.ffi_system_now_utc_us()/1000,variant))
      Nil
    }
    _ -> { let assert Ok(_) = simplifile.write(db_path<>".risk.json",risk_fixture("plan-e2e",risk_case)) Nil }
  }
  let assert Ok(#(fixture_pid, _port, base_url)) = fixture_start()

  let bot_id = 999_888
  let worker_id = "worker-e2e-01"
  let task_id = "lease-e2e-01"
  let epoch = 1

  let assert Ok(2) = store.initialize_store(storage_config, bot_id)

  let nonce = int.to_string(service.ffi_system_now_utc_us()) <> int.to_string(int.random(10_000))
  let slice_name = "app-uos_tg_test_poll1024_a" <> nonce <> ".slice"
  let unit_name = "uos-tg-store-test-poll1024-a" <> nonce <> ".service"
  let ipc_dir = start_test_runner(dir, slice_name, unit_name)

  // Start supervised actor in runner inside transient unit
  start_runner_actor_with_conversation(
    ipc_dir,
    db_path,
    base_url,
    "test-bot-token-auto",
    bot_id,
    worker_id,
    task_id,
    epoch,
    sa_plan_db,
    coord_db,
    None,
    None,
    True,
    mode,
    daily_limit,
  )

  runner_set_authority(
    ipc_dir,
    "lease-e2e-auto-01",
    1,
    1,
    3_000_000_000_000_000,
  )

  case risk_case {
    "missing" -> { let assert Ok(_) = simplifile.delete(db_path<>".risk.json") Nil }
    "verification_missing" -> { let assert Ok(_) = simplifile.delete(db_path<>".verification.json") Nil }
    _ -> Nil
  }
  // Queue a /doctor command update into the mock fixture
  let update_json =
    "{\"update_id\": 8001, \"message\": {\"message_id\": 501, \"chat\": {\"id\": 100, \"type\": \"private\"}, \"from\": {\"id\": 200, \"is_bot\": false, \"first_name\": \"Alice\"}, \"text\": \"/doctor\", \"date\": 1700000000}}"
  fixture_set_updates(fixture_pid, [string.replace(update_json, json.to_string(json.string("/doctor")), json.to_string(json.string(first_command)))])

  // 1. PollCycle polls update and stores input_key + inbox row
  let poll_res = runner_poll_cycle(ipc_dir, 1_700_000_020_000)
  echo #(mode, poll_res)
  string.contains(poll_res, "\"type\":\"poll_committed\"") |> should.equal(True)
  string.contains(poll_res, "\"new_watermark\":8002") |> should.equal(True)

  // 2. AutomaticDispatchTick autonomously claims, generates observation, commits result & sending, and delivers via HTTP
  let dispatch_res = runner_automatic_dispatch_tick(ipc_dir, 1_700_000_021_000)
  echo #(mode, dispatch_res)

  case mode == "expire" {
    True -> {
      string.contains(dispatch_res,"\"status\":\"error\"") |> should.be_true
      let assert Ok(day) = conv.utc_day(service.ffi_system_now_utc_us() / 1000)
      let assert Ok(budget_key) = conv.budget_key(bot_id,day)
      let assert Ok(context_key) = conv.context_key(conv.Scope(bot_id,100,200))
      let request = ledger.make_request_id(bot_id,8001)
      let assert Ok(#(_, [b,c,r])) = store.read_keys(storage_config,[budget_key,context_key,codec.result_key(request)])
      let assert Ok(raw) = codec.decode_row_value(b)
      let assert Ok(budget) = conv.decode_budget(raw,bot_id,day)
      budget.reserved_requests |> should.equal(1)
      c.exists |> should.be_false
      r.exists |> should.be_false
      simplifile.is_file(db_path <> ".model-post") |> should.equal(Ok(False))
      runner_stop(ipc_dir)
      fixture_stop(fixture_pid)
      let _ = lifecycle.stop_and_verify_test_unit(slice_name,unit_name,db_path,recovery_worker_sha,recovery_guardian_sha)
      let _ = lifecycle.stop_test_slice(slice_name)
    }
    False -> {
  string.contains(dispatch_res, "\"type\":\"dispatch_cycle_result\"") |> should.equal(True)
  string.contains(dispatch_res, "\"processed_count\":1") |> should.equal(True)
  let delivered_count=delivery_count(dispatch_res)

  // Wait briefly for delivery worker to finish
  ffi_sleep_ms(100)

  // 3. Verify chunk delivered in SQLite store
  let req_id = ledger.make_request_id(bot_id, 8001)
  let first_payload=delivered_payload(storage_config,req_id,delivered_count)
  string.contains(first_payload,first_expected) |> should.be_true
  case mode { "unicode" -> { assert delivered_count==2 assert first_payload==conversation_fixture.response(mode) } _ -> Nil }
  case first_command=="/checklist" && list.contains(["verification","verification_all"],risk_case) {
    True -> {
      string.contains(first_payload,"CHK-18-JJ") |> should.be_true
      let assert Ok(18)=json.parse(first_payload,decode.field("selected_count",decode.int,decode.success))
      {delivered_count>1} |> should.be_true
    }
    False->Nil
  }

  case risk_case {
    "refresh" -> { let assert Ok(_) = simplifile.write(db_path<>".risk.json",risk_fixture("plan-e2e","changed")) Nil }
    "verification_changed" -> { let assert Ok(_) = simplifile.write(db_path<>".verification.json","{}") Nil }
    _ -> Nil
  }
  // 4. Test /saplan automatic dispatch
  let saplan_update =
    "{\"update_id\": 8002, \"message\": {\"message_id\": 778, \"chat\": {\"id\": 100, \"type\": \"private\"}, \"from\": {\"id\": 200, \"is_bot\": false, \"first_name\": \"Alice\"}, \"text\": \"/saplan\", \"date\": 1700000002}}"
  fixture_set_updates(fixture_pid, [string.replace(saplan_update, json.to_string(json.string("/saplan")), json.to_string(json.string(second_command)))])

  let poll_res2 = runner_poll_cycle(ipc_dir, 1_700_000_022_000)
  echo #(mode, poll_res2)
  string.contains(poll_res2, "\"type\":\"poll_committed\"") |> should.equal(True)
  string.contains(poll_res2, "\"new_watermark\":8003") |> should.equal(True)

  let dispatch_res2 = runner_automatic_dispatch_tick(ipc_dir, 1_700_000_023_000)
  echo #(mode, dispatch_res2)
  string.contains(dispatch_res2, "\"type\":\"dispatch_cycle_result\"") |> should.equal(True)
  string.contains(dispatch_res2, "\"processed_count\":1") |> should.equal(True)
  let delivered_count2=delivery_count(dispatch_res2)

  ffi_sleep_ms(100)

  let req_id2 = ledger.make_request_id(bot_id, 8002)
  let second_payload=delivered_payload(storage_config,req_id2,delivered_count2)
  string.contains(second_payload,second_expected) |> should.be_true
  case mode { "unicode" -> { assert delivered_count2==2 assert second_payload==conversation_fixture.response(mode) } _ -> Nil }


  case mode {
    "disabled" -> Nil
    _ -> {
      let assert Ok(day) = conv.utc_day(service.ffi_system_now_utc_us() / 1000)
      let assert Ok(context_key) = conv.context_key(conv.Scope(bot_id,100,200))
      let assert Ok(budget_key) = conv.budget_key(bot_id,day)
      let assert Ok(#(_, [context_row,budget_row])) = store.read_keys(storage_config,[context_key,budget_key])
      let assert Ok(budget_raw) = codec.decode_row_value(budget_row)
      let assert Ok(budget) = conv.decode_budget(budget_raw,bot_id,day)
      budget.reserved_requests |> should.equal(case mode { "empty" | "memory_read" | "memory_clear" -> 1 _ -> int.min(2,daily_limit) })
      case mode {
        "fail" -> context_row.exists |> should.be_false
        _ -> {
          let assert Ok(context_raw) = codec.decode_row_value(context_row)
          let assert Ok(context) = conv.decode_context(context_raw,conv.Scope(bot_id,100,200))
          list.length(context.turns) |> should.equal(case mode { "memory_clear" -> 0 "empty" | "memory_read" -> 1 _ -> int.min(2,daily_limit) })
          case mode {
            "memory_clear" -> context.turns |> should.equal([])
            _ -> {
              let assert Ok(first) = list.first(context.turns)
              first.prompt |> should.equal("Hello")
              first.reply |> should.equal(conversation_fixture.response(mode))
            }
          }
        }
      }
    }
  }
  // Clean shutdown
  runner_stop(ipc_dir)
  fixture_stop(fixture_pid)
  let _ =
    lifecycle.stop_and_verify_test_unit(
      slice_name,
      unit_name,
      db_path,
      recovery_worker_sha,
      recovery_guardian_sha,
    )
  let _ = lifecycle.stop_test_slice(slice_name)
    }
  }
}

pub fn e2e_automatic_dispatch_cycle_actor_test() {
  exercise_automatic_command_dispatch("/doctor", "UNOBSERVED_RUNTIME", "/saplan", "uos.sa_plan.observer.v1")
}

pub fn e2e_catalog_help_and_tasks_dispatch_test() {
  exercise_automatic_command_dispatch("/help", "/cockpit", "/tasks", "uos.sa_plan.observer.v1")
}

pub fn e2e_catalog_start_and_plan_dispatch_test() {
  exercise_automatic_command_dispatch("/start", "/help", "/plan", "uos.sa_plan.observer.v1")
}

pub fn e2e_catalog_cockpit_and_tasks_dispatch_test() {
  exercise_automatic_command_dispatch("/cockpit", "http://nas-1.tail55d152.ts.net:4100/", "/tasks", "uos.sa_plan.observer.v1")
}

pub fn unrelated_cleanup_receipt_should_not_admit_writer_test() {
  use storage_config, db_path, sa_plan_db, coord_db, dir <- with_recovery_store()
  let assert Ok(#(fixture_pid, _port, base_url)) = fixture_start()

  let bot_id = 888_111
  let worker_id = "worker-e2e-01"
  let task_id = "lease-e2e-01"
  let epoch = 7

  // Initialize store schema & watermark
  let assert Ok(init_gen) = store.initialize_store(storage_config, bot_id)
  init_gen |> should.equal(2)

  let nonce = int.to_string(service.ffi_system_now_utc_us())
  let slice_name = "app-uos_tg_test_poll1024_unrel_" <> nonce <> ".slice"
  let unit_name = "uos-tg-store-test-poll1024-unrel-" <> nonce <> ".service"
  let ipc_dir = start_test_runner(dir, slice_name, unit_name)
  let reg_path = mint_unit_registration(dir, slice_name, unit_name, db_path, epoch)
  let unrelated_slice = "app-uos_tg_test_poll1024_unrel_slp_" <> nonce <> ".slice"
  let unrelated_unit = "uos-tg-store-test-poll1024-unrel-sleep-" <> nonce <> ".service"
  let receipt = mint_test_cleanup_receipt(unrelated_slice, unrelated_unit, db_path)

  // Start actor in runner inside transient unit with unrelated receipt (epoch 1) offered for epoch 7
  start_runner_actor(
    ipc_dir,
    db_path,
    base_url,
    "test-bot-token-e2e",
    bot_id,
    worker_id,
    task_id,
    epoch,
    sa_plan_db,
    coord_db,
    Some(reg_path),
    Some(receipt),
    False,
  )

  let observed_state = runner_get_state(ipc_dir)
  runner_stop(ipc_dir)
  fixture_stop(fixture_pid)
  lifecycle.cleanup_test_unit_and_slice(slice_name, unit_name)
  lifecycle.cleanup_test_unit_and_slice(unrelated_slice, unrelated_unit)
  // Receipt came from unrelated sleeper at epoch1, not prior registered writer.
  string.contains(observed_state, "\"writer_state\":\"clean\"") |> should.equal(False)
}

pub fn large_saplan_result_is_chunked_and_delivered_test() {
  use storage_config, db_path, sa_plan_db, coord_db, dir <- with_recovery_store()
  let assert Ok(#(fixture_pid, _port, base_url)) = fixture_start()

  let bot_id = 999_888
  let worker_id = "worker-e2e-01"
  let task_id = "lease-e2e-01"
  let epoch = 1

  let assert Ok(2) = store.initialize_store(storage_config, bot_id)

  let nonce = int.to_string(service.ffi_system_now_utc_us()) <> int.to_string(int.random(10_000))
  let slice_name = "app-uos_tg_test_poll1024_large_" <> nonce <> ".slice"
  let unit_name = "uos-tg-store-test-poll1024-large-" <> nonce <> ".service"
  let ipc_dir = start_test_runner(dir, slice_name, unit_name)

  list.each([1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30], fn(i) {
    let assert Ok(_) = seed_test_sa_plan_task(sa_plan_db, "plan-e2e", "bulk-task-" <> int.to_string(i), "worker-e2e-01", 1, 4_000_000_000_000_000_000)
  })

  // Start supervised actor in runner inside transient unit
  start_runner_actor(
    ipc_dir,
    db_path,
    base_url,
    "test-bot-token-auto",
    bot_id,
    worker_id,
    task_id,
    epoch,
    sa_plan_db,
    coord_db,
    None,
    None,
    True,
  )

  runner_set_authority(
    ipc_dir,
    "lease-e2e-auto-01",
    1,
    1,
    3_000_000_000_000_000,
  )

  // Queue a /saplan command update into the mock fixture
  let update_json =
    "{\"update_id\": 8001, \"message\": {\"message_id\": 501, \"chat\": {\"id\": 100, \"type\": \"private\"}, \"from\": {\"id\": 200, \"is_bot\": false, \"first_name\": \"Alice\"}, \"text\": \"/saplan\", \"date\": 1700000000}}"
  fixture_set_updates(fixture_pid, [update_json])

  // 1. PollCycle polls update and stores input_key + inbox row
  let poll_res = runner_poll_cycle(ipc_dir, 1_700_000_020_000)
  string.contains(poll_res, "\"type\":\"poll_committed\"") |> should.equal(True)

  let observed_dispatch = runner_automatic_dispatch_tick(ipc_dir, 1_700_000_021_000)
  string.contains(observed_dispatch, "\"type\":\"dispatch_cycle_result\"") |> should.equal(True)

  ffi_sleep_ms(300)

  // Delivered chunks verify in mock fixture
  let reqs = fixture_get_requests(fixture_pid)
  { list.length(reqs) > 1 } |> should.equal(True)

  runner_stop(ipc_dir)
  fixture_stop(fixture_pid)
  lifecycle.cleanup_test_unit_and_slice(slice_name, unit_name)
}

pub fn e2e_supervised_six_second_poll_test() {
  use storage_config, db_path, sa_plan_db, coord_db, dir <- with_recovery_store()
  let assert Ok(#(fixture_pid, _port, base_url)) = fixture_start()

  let bot_id = 888_111
  let worker_id = "worker-e2e-01"
  let task_id = "lease-e2e-01"
  let epoch = 1

  // Initialize store schema & watermark
  let assert Ok(init_gen) = store.initialize_store(storage_config, bot_id)
  init_gen |> should.equal(2)

  let nonce = int.to_string(service.ffi_system_now_utc_us())
  let slice_name = "app-uos_tg_test_poll1024_slow_" <> nonce <> ".slice"
  let unit_name = "uos-tg-store-test-poll1024-slow-" <> nonce <> ".service"
  let ipc_dir = start_test_runner(dir, slice_name, unit_name)

  // Start actor in runner inside transient unit
  start_runner_actor(
    ipc_dir,
    db_path,
    base_url,
    "test-bot-token-e2e",
    bot_id,
    worker_id,
    task_id,
    epoch,
    sa_plan_db,
    coord_db,
    None,
    None,
    True,
  )

  // 1. Without authority lease: poll fails closed
  let err_res = runner_poll_cycle(ipc_dir, 1_700_000_000_000)
  case string.contains(err_res, "authority_lease_missing") {
    True -> Nil
    False -> panic as { "err_res unexpected: " <> err_res }
  }

  // 2. Set valid authority lease
  runner_set_authority(
    ipc_dir,
    "lease-e2e-01",
    1,
    1,
    3_000_000_000_000_000,
  )

  // 3. Ingress: queue update from authorized user (chat 100, user 200)
  let update_json =
    "{\"update_id\": 7001, \"message\": {\"message_id\": 88, \"chat\": {\"id\": 100, \"type\": \"private\"}, \"from\": {\"id\": 200, \"is_bot\": false, \"first_name\": \"Alice\"}, \"text\": \"/status\", \"date\": 1700000000}}"
  fixture_set_updates(fixture_pid, [update_json])

  fixture_set_mode(fixture_pid, "slow_valid")
  // 4. Poll cycle via actor inside runner
  let poll_res = runner_poll_cycle(ipc_dir, 1_700_000_001_000)
  fixture_set_mode(fixture_pid, "normal")
  case string.contains(poll_res, "\"type\":\"poll_committed\"") {
    True -> Nil
    False -> panic as { "poll_res unexpected: " <> poll_res }
  }
  string.contains(poll_res, "\"count\":1") |> should.equal(True)
  string.contains(poll_res, "\"new_watermark\":7002") |> should.equal(True)

  // Verify actor state inside runner
  let state_json = runner_get_state(ipc_dir)
  string.contains(state_json, "\"last_committed_offset\":7002") |> should.equal(True)
  string.contains(state_json, "\"expected_generation\":3") |> should.equal(True)
  string.contains(state_json, "\"writer_state\":\"clean\"") |> should.equal(True)

  // 5. Read inbox record from store
  let assert Ok(#(gen1, [inbox_row])) =
    store.read_inbox_records(storage_config, 10, None)
  gen1 |> should.equal(3)
  let #(inbox_rec, inbox_ver1, inbox_sha1) = inbox_row
  inbox_rec.update_id |> should.equal(7001)
  inbox_ver1 |> should.equal(1)
  let assert ledger.InboxPending = inbox_rec.status

  // 6. Claim task for processing
  let assert Ok(#(claim_rcpt, processing_rec)) =
    store.claim_task_processing(
      storage_config,
      bot_id,
      "op-claim-7001",
      gen1,
      inbox_rec,
      inbox_ver1,
      inbox_sha1,
      worker_id,
      epoch,
      1_700_000_002_000,
    )
  claim_rcpt.generation |> should.equal(4)
  let assert ledger.InboxProcessing(w, ep) = processing_rec.status
  w |> should.equal(worker_id)
  ep |> should.equal(epoch)

  // 7. Commit result ready with response payload
  let response_payload = "System operational. All 7 engines nominal."
  let processing_ver = 2
  let processing_sha = files.digest(codec.encode_inbox_record(processing_rec))
  let assert Ok(res_result) =
    store.commit_result(
      storage_config,
      bot_id,
      "op-result-7001",
      claim_rcpt.generation,
      processing_rec,
      processing_ver,
      processing_sha,
      [response_payload],
      worker_id,
      epoch,
    )
  res_result.receipt.generation |> should.equal(5)
  let assert [_chunk0] = res_result.chunks
  let ready_rec = res_result.inbox_record
  let ready_ver = 3
  let ready_sha = files.digest(codec.encode_inbox_record(ready_rec))

  // 8. Deliver chunk via service actor inside runner
  let deliver_res = runner_deliver_chunk_from_store(ipc_dir, inbox_rec.request_id, 1_700_000_003_000)
  string.contains(deliver_res, "\"type\":\"delivery_step_success\"") |> should.equal(True)
  string.contains(deliver_res, "\"message_id\":42") |> should.equal(True)

  // 9. Verify delivered chunk in SQLite store
  let assert Ok(#(_, [chunk_row])) =
    store.read_keys(storage_config, [codec.chunk_key(inbox_rec.request_id, 0)])
  chunk_row.exists |> should.equal(True)
  chunk_row.version |> should.equal(3)
  let assert Ok(chunk_raw) = codec.decode_row_value(chunk_row)
  let assert Ok(delivered_chunk) = codec.decode_chunk_value(chunk_raw)
  delivered_chunk.status |> should.equal(ledger.OutboxDelivered(42))

  // 10. Commit task completion
  let after_deliver_gen = 7
  let assert Ok(#(comp_rcpt, completed_rec)) =
    store.commit_task_completion(
      storage_config,
      bot_id,
      "op-comp-7001",
      after_deliver_gen,
      ready_rec,
      ready_ver,
      ready_sha,
      [delivered_chunk],
    )
  comp_rcpt.generation |> should.equal(8)
  let assert ledger.InboxCompleted(_digest) = completed_rec.status

  // 11. Empty poll returns PollEmpty
  fixture_set_updates(fixture_pid, [])
  let empty_res = runner_poll_cycle(ipc_dir, 1_700_000_004_000)
  string.contains(empty_res, "\"type\":\"poll_empty\"") |> should.equal(True)

  // Clean shutdown
  runner_stop(ipc_dir)
  fixture_stop(fixture_pid)
  let _ =
    lifecycle.stop_and_verify_test_unit(
      slice_name,
      unit_name,
      db_path,
      recovery_worker_sha,
      recovery_guardian_sha,
    )
  let _ = lifecycle.stop_test_slice(slice_name)
}


pub fn e2e_callback_ack_replay_and_denial_test() {
  use storage_config, db_path, sa_plan_db, coord_db, dir <- with_recovery_store()
  let assert Ok(#(fixture_pid, _port, base_url)) = fixture_start()

  let bot_id = 444_333
  let worker_id = "worker-e2e-01"
  let task_id = "lease-e2e-01"
  let epoch = 1

  let assert Ok(2) = store.initialize_store(storage_config, bot_id)

  let nonce = int.to_string(service.ffi_system_now_utc_us()) <> int.to_string(int.random(10_000))
  let slice_name = "app-uos_tg_test_poll1024_a" <> nonce <> ".slice"
  let unit_name = "uos-tg-store-test-poll1024-a" <> nonce <> ".service"
  let ipc_dir = start_test_runner(dir, slice_name, unit_name)

  // Start supervised actor in runner inside transient unit
  start_runner_actor(
    ipc_dir,
    db_path,
    base_url,
    "test-bot-token-auto",
    bot_id,
    worker_id,
    task_id,
    epoch,
    sa_plan_db,
    coord_db,
    None,
    None,
    True,
  )

  runner_set_authority(
    ipc_dir,
    "lease-e2e-auto-01",
    1,
    1,
    3_000_000_000_000_000,
  )


  let update_json =
    "{\"update_id\":9001,\"callback_query\":{\"id\":\"callback-9001\",\"from\":{\"id\":200,\"is_bot\":false,\"first_name\":\"Fixture\"},\"message\":{\"message_id\":501,\"chat\":{\"id\":100,\"type\":\"private\"}},\"data\":\"/saplan\"}}"
  fixture_set_updates(fixture_pid, [update_json])
  let poll = runner_poll_cycle(ipc_dir, service.ffi_system_now_utc_us())
  string.contains(poll, "\"type\":\"poll_committed\"") |> should.equal(True)
  let dispatch = runner_automatic_dispatch_tick(ipc_dir, service.ffi_system_now_utc_us())
  string.contains(dispatch, "\"processed_count\":1") |> should.equal(True)
  let requests = fixture_requests_typed(fixture_pid)
  let callbacks = list.filter(requests, fn(r) {
    let #(_, path, _, _) = r
    string.ends_with(path, "/answerCallbackQuery")
  })
  let assert [#(_, _, _, callback_body)] = callbacks
  string.contains(callback_body, "\"callback_query_id\":\"callback-9001\"")
    |> should.equal(True)
  let sends = list.filter(requests, fn(r) {
    let #(_, path, _, _) = r
    string.ends_with(path, "/sendMessage")
  }) |> list.length
  { sends > 0 } |> should.equal(True)
  let assert Ok(#(_, [inbox_row])) = store.read_inbox_records(storage_config, 10, None)
  let #(inbox, _, _) = inbox_row
  let assert ledger.InboxCompleted(_) = inbox.status
  let replay = runner_automatic_dispatch_tick(ipc_dir, service.ffi_system_now_utc_us())
  string.contains(replay, "\"processed_count\":0") |> should.equal(True)

  let denied =
    "{\"update_id\":9002,\"callback_query\":{\"id\":\"callback-denied\",\"from\":{\"id\":999,\"is_bot\":false},\"message\":{\"message_id\":502,\"chat\":{\"id\":100,\"type\":\"private\"}},\"data\":\"/saplan\"}}"
  fixture_set_updates(fixture_pid, [denied])
  let _ = runner_poll_cycle(ipc_dir, service.ffi_system_now_utc_us())
  let denied_dispatch = runner_automatic_dispatch_tick(ipc_dir, service.ffi_system_now_utc_us())
  string.contains(denied_dispatch, "\"processed_count\":0") |> should.equal(True)
  let after = fixture_requests_typed(fixture_pid)
  let callbacks_after = list.filter(after, fn(r) {
    let #(_, path, _, _) = r
    string.ends_with(path, "/answerCallbackQuery")
  }) |> list.length
  let sends_after = list.filter(after, fn(r) {
    let #(_, path, _, _) = r
    string.ends_with(path, "/sendMessage")
  }) |> list.length
  callbacks_after |> should.equal(1)
  sends_after |> should.equal(sends)
  runner_stop(ipc_dir)
  fixture_stop(fixture_pid)
  lifecycle.cleanup_test_unit_and_slice(slice_name, unit_name)
}

@external(erlang, "telegram_http_test_fixture", "get_requests")
fn fixture_requests_typed(pid: Pid) -> List(#(String, String, Dynamic, String))

pub fn e2e_finite_automatic_loop_dispatches_without_manual_ticks_test() {
  use storage_config, db_path, sa_plan_db, coord_db, dir <- with_recovery_store()
  let assert Ok(#(fixture_pid, _, base_url)) = fixture_start()
  fixture_set_mode(fixture_pid, "offset_aware")
  let bot_id = 222_555
  let assert Ok(2) = store.initialize_store(storage_config, bot_id)
  let nonce = int.to_string(service.ffi_system_now_utc_us()) <> int.to_string(int.random(10_000))
  let slice_name = "app-uos_tg_test_poll1024_l" <> nonce <> ".slice"
  let unit_name = "uos-tg-store-test-poll1024-l" <> nonce <> ".service"
  let ipc_dir = start_test_runner(dir, slice_name, unit_name)
  start_runner_actor(ipc_dir, db_path, base_url, "test-token-loop", bot_id,
    "worker-e2e-01", "lease-e2e-01", 1, sa_plan_db, coord_db, None, None, True)
  runner_set_authority(ipc_dir, "lease-loop", 1, 1, 3_000_000_000_000_000)
  fixture_set_updates(fixture_pid, [
    "{\"update_id\":9101,\"message\":{\"message_id\":501,\"chat\":{\"id\":100,\"type\":\"private\"},\"from\":{\"id\":200,\"is_bot\":false,\"first_name\":\"Test\"},\"text\":\"/doctor\",\"date\":1700000000}}",
    "{\"update_id\":9102,\"message\":{\"message_id\":502,\"chat\":{\"id\":100,\"type\":\"private\"},\"from\":{\"id\":200,\"is_bot\":false,\"first_name\":\"Test\"},\"text\":\"/saplan\",\"date\":1700000000}}",
  ])
  // One start command: the Gleam driver owns all subsequent poll/dispatch scheduling.
  let terminal = send_runner_cmd(ipc_dir, "{\"action\":\"finite_automatic_loop\"}")
  string.contains(terminal, "\"reason\":\"max_cycles\"") |> should.equal(True)
  string.contains(terminal, "\"completed_cycles\":2") |> should.equal(True)
  let request1 = ledger.make_request_id(bot_id, 9101)
  let request2 = ledger.make_request_id(bot_id, 9102)
  let assert Ok(#(_, [row1, row2])) = store.read_keys(storage_config, [
    codec.chunk_key(request1, 0), codec.chunk_key(request2, 0),
  ])
  let assert Ok(raw1) = codec.decode_row_value(row1)
  let assert Ok(raw2) = codec.decode_row_value(row2)
  let assert Ok(chunk1) = codec.decode_chunk_value(raw1)
  let assert Ok(chunk2) = codec.decode_chunk_value(raw2)
  chunk1.status |> should.equal(ledger.OutboxDelivered(42))
  chunk2.status |> should.equal(ledger.OutboxDelivered(42))
  string.contains(chunk1.payload, "UNOBSERVED_RUNTIME") |> should.equal(True)
  string.contains(chunk2.payload, "uos.sa_plan.observer.v1") |> should.equal(True)
  let requests = fixture_requests_typed(fixture_pid)
  list.filter(requests, fn(r) { let #(_, path, _, _) = r string.contains(path, "/getUpdates") })
    |> list.length |> should.equal(2)
  list.filter(requests, fn(r) { let #(_, path, _, _) = r string.contains(path, "/sendMessage") })
    |> list.length |> should.equal(2)
  let stopped = runner_get_state(ipc_dir)
  string.contains(stopped, "\"writer_state\":\"clean\"") |> should.equal(True)
  string.contains(stopped, "\"pending_operation_present\":false") |> should.equal(True)
  string.contains(stopped, "\"last_committed_offset\":9103") |> should.equal(True)
  // Retain unit invocation identity until lifecycle stop captures and verifies it.
  fixture_stop(fixture_pid)
  let assert Ok(_) = lifecycle.stop_and_verify_test_unit(slice_name, unit_name, db_path, recovery_worker_sha, recovery_guardian_sha)
  let assert Ok(True) = lifecycle.stop_test_slice(slice_name)
}

fn managed_start_command(
  db_path: String, base_url: String, bot_id: Int, sa_plan_db: String,
  coord_db: String, current_path: String, writer: codec.WriterRegistration,
  resource: String,
) -> String {
  let assert Ok(writer_json) = codec.encode_writer_registration(writer)
  json.object([
    #("action", json.string("start_actor")),
    #("managed_start", json.bool(True)),
    #("db_path", json.string(db_path)),
    #("guardian_path", json.string(recovery_guardian_path)),
    #("guardian_sha", json.string(recovery_guardian_sha)),
    #("worker_path", json.string(recovery_worker_path)),
    #("worker_sha", json.string(recovery_worker_sha)),
    #("base_url", json.string(base_url)),
    #("token", json.string("test-token-managed")),
    #("bot_id", json.int(bot_id)),
    #("worker_id", json.string("worker-e2e-01")),
    #("task_id", json.string("lease-e2e-01")),
    #("plan_id", json.string("plan-e2e")),
    #("service_epoch", json.int(1)),
    #("resource_id", json.string(resource)),
    #("sa_plan_db", json.string(sa_plan_db)),
    #("coord_db", json.string(coord_db)),
    #("current_control_registration_path", json.string(current_path)),
    #("writer_registration", json.string(writer_json)),
  ]) |> json.to_string
}

pub fn e2e_managed_start_identity_authority_single_use_and_dispatch_test() {
  use storage_config, db_path, sa_plan_db, coord_db, dir <- with_recovery_store()
  let assert Ok(#(fixture_pid, _, base_url)) = fixture_start()
  fixture_set_mode(fixture_pid, "offset_aware")
  let bot_id = 222_556
  let assert Ok(fresh) = store.begin_new_writer_store(storage_config, bot_id)
  let nonce = int.to_string(service.ffi_system_now_utc_us()) <> int.to_string(int.random(10_000))
  let slice_name = "app-uos_tg_test_poll1024_m" <> nonce <> ".slice"
  let unit_name = "uos-tg-store-test-poll1024-m" <> nonce <> ".service"
  let ipc_dir = start_test_runner(dir, slice_name, unit_name)
  let control_path = mint_unit_registration(dir, slice_name, unit_name, db_path, 1)
  let assert Ok(control_json) = simplifile.read(control_path)
  let assert Ok(control) = lifecycle.decode_control_registration(control_json)
  let writer = codec.WriterRegistration(
    bot_id: bot_id, service_epoch: 1,
    instance_token: files.digest("managed-start-" <> nonce),
    control_digest: files.digest(lifecycle.encode_control_registration(control)),
    store_incarnation_id: control.store_incarnation_id,
    unit_invocation_id: control.unit_invocation_id,
    registered_at_us: control.registered_at_us,
  )
  let assert Ok(2) = store.finish_new_writer_store(fresh, writer)
  let cmd = managed_start_command(db_path, base_url, bot_id, sa_plan_db, coord_db,
    control_path, writer, "runtime:telegram-bridge")
  // Current unit and registration are valid, but no runtime lease exists yet.
  let missing_runtime = send_runner_cmd(ipc_dir, cmd)
  string.contains(missing_runtime, "coordinator_fence_refused") |> should.equal(True)
  let assert Ok(#(2, [unconsumed])) = store.read_keys(storage_config, ["meta/writer_start"])
  unconsumed.exists |> should.equal(False)
  let assert Ok(coordinator) = coord_store.open(coord_db)
  let assert Ok(#(runtime_claim, False)) = coord_store.append(coordinator,
    sync.Claim("worker-e2e-01", "runtime:telegram-bridge", 3_600_000_000),
    "managed-runtime-" <> nonce)
  runtime_claim.epoch |> should.equal(1)
  let _ = coord_store.close(coordinator)
  // A caller-changed control digest must not consume the durable start.
  let wrong = codec.WriterRegistration(..writer, control_digest: files.digest("wrong-control"))
  let bad_identity = send_runner_cmd(ipc_dir, managed_start_command(db_path, base_url,
    bot_id, sa_plan_db, coord_db, control_path, wrong, "runtime:telegram-bridge"))
  string.contains(bad_identity, "\"status\":\"error\"") |> should.equal(True)
  let assert Ok(#(2, [still_unconsumed])) = store.read_keys(storage_config, ["meta/writer_start"])
  still_unconsumed.exists |> should.equal(False)
  let first = send_runner_cmd(ipc_dir, cmd)
  string.contains(first, "\"action\":\"started\"") |> should.equal(True)
  let assert Ok(#(3, [start_row])) = store.read_keys(storage_config, ["meta/writer_start"])
  let assert Ok(start_value) = codec.decode_row_value(start_row)
  codec.decode_writer_registration(start_value) |> should.equal(Ok(writer))
  let duplicate = send_runner_cmd(ipc_dir, "{\"action\":\"repeat_managed_start\"}")
  string.contains(duplicate, "\"status\":\"refused\"") |> should.equal(True)
  string.contains(duplicate, "writer_start_already_consumed") |> should.equal(True)
  let assert Ok(#(3, [unchanged_start])) = store.read_keys(storage_config, ["meta/writer_start"])
  unchanged_start |> should.equal(start_row)
  // Startup itself does not manufacture an authority lease or send HTTP.
  fixture_requests_typed(fixture_pid) |> should.equal([])
  let before = runner_poll_cycle(ipc_dir, service.ffi_system_now_utc_us())
  string.contains(before, "authority_lease_missing") |> should.equal(True)
  runner_set_authority(ipc_dir, "managed-runtime", 1, 1, 3_000_000_000_000_000)
  fixture_set_updates(fixture_pid, [
    "{\"update_id\":9201,\"message\":{\"message_id\":501,\"chat\":{\"id\":100,\"type\":\"private\"},\"from\":{\"id\":200,\"is_bot\":false},\"text\":\"/doctor\",\"date\":1700000000}}",
    "{\"update_id\":9202,\"message\":{\"message_id\":502,\"chat\":{\"id\":100,\"type\":\"private\"},\"from\":{\"id\":200,\"is_bot\":false},\"text\":\"/saplan\",\"date\":1700000000}}",
  ])
  let terminal = send_runner_cmd(ipc_dir, "{\"action\":\"finite_automatic_loop\"}")
  string.contains(terminal, "\"reason\":\"max_cycles\"") |> should.equal(True)
  string.contains(terminal, "\"completed_cycles\":2") |> should.equal(True)
  let request1 = ledger.make_request_id(bot_id, 9201)
  let request2 = ledger.make_request_id(bot_id, 9202)
  let assert Ok(#(_, [row1, row2])) = store.read_keys(storage_config, [
    codec.chunk_key(request1, 0), codec.chunk_key(request2, 0),
  ])
  let assert Ok(raw1) = codec.decode_row_value(row1)
  let assert Ok(raw2) = codec.decode_row_value(row2)
  let assert Ok(chunk1) = codec.decode_chunk_value(raw1)
  let assert Ok(chunk2) = codec.decode_chunk_value(raw2)
  chunk1.status |> should.equal(ledger.OutboxDelivered(42))
  chunk2.status |> should.equal(ledger.OutboxDelivered(42))
  string.contains(chunk1.payload, "UNOBSERVED_RUNTIME") |> should.equal(True)
  string.contains(chunk2.payload, "uos.sa_plan.observer.v1") |> should.equal(True)
  let requests = fixture_requests_typed(fixture_pid)
  list.filter(requests, fn(r) { let #(_, path, _, _) = r string.contains(path, "/getUpdates") })
    |> list.length |> should.equal(2)
  list.filter(requests, fn(r) { let #(_, path, _, _) = r string.contains(path, "/sendMessage") })
    |> list.length |> should.equal(2)
  fixture_stop(fixture_pid)
  let assert Ok(_) = lifecycle.stop_and_verify_test_unit(slice_name, unit_name, db_path,
    recovery_worker_sha, recovery_guardian_sha)
  let assert Ok(True) = lifecycle.stop_test_slice(slice_name)
}

pub fn e2e_managed_preflight_hold_preserves_start_permit_test() {
  use storage_config, db_path, sa_plan_db, coord_db, dir <- with_recovery_store()
  let assert Ok(#(fixture_pid, _, base_url)) = fixture_start()
  fixture_set_mode(fixture_pid, "offset_aware")
  let bot_id = 222_556
  let assert Ok(fresh) = store.begin_new_writer_store(storage_config, bot_id)
  let nonce = int.to_string(service.ffi_system_now_utc_us()) <> int.to_string(int.random(10_000))
  let slice_name = "app-uos_tg_test_poll1024_m" <> nonce <> ".slice"
  let unit_name = "uos-tg-store-test-poll1024-m" <> nonce <> ".service"
  let ipc_dir = start_test_runner(dir, slice_name, unit_name)
  let control_path = mint_unit_registration(dir, slice_name, unit_name, db_path, 1)
  let assert Ok(control_json) = simplifile.read(control_path)
  let assert Ok(control) = lifecycle.decode_control_registration(control_json)
  let writer = codec.WriterRegistration(
    bot_id: bot_id, service_epoch: 1,
    instance_token: files.digest("managed-start-" <> nonce),
    control_digest: files.digest(lifecycle.encode_control_registration(control)),
    store_incarnation_id: control.store_incarnation_id,
    unit_invocation_id: control.unit_invocation_id,
    registered_at_us: control.registered_at_us,
  )
  let assert Ok(2) = store.finish_new_writer_store(fresh, writer)
  let assert Ok(#(wm, version, sha)) = store.read_watermark(storage_config)
  let verdict = guard.evaluate_update(
    "{\"update_id\":9301,\"message\":{\"message_id\":501,\"chat\":{\"id\":100,\"type\":\"private\"},\"from\":{\"id\":200,\"is_bot\":false},\"text\":\"/doctor\",\"date\":1700000000}}",
    guard.Allowlist(bot_id, [#(100, 200)]))
  let assert Ok(pref) = store.commit_prefix(storage_config, bot_id, "preflight-orphan-prefix", 2, wm, version, sha, [verdict], 1_700_000_000_000)
  let assert [rec] = pref.admitted_records
  let assert Ok(_) = store.claim_task_processing(storage_config, bot_id, "preflight-orphan-claim", pref.receipt.generation, rec, 1, files.digest(codec.encode_inbox_record(rec)), "dead-worker", 1, 1_700_000_001_000)
  let assert Ok(coordinator) = coord_store.open(coord_db)
  let assert Ok(#(_, False)) = coord_store.append(coordinator, sync.Claim("worker-e2e-01", "runtime:telegram-bridge", 3_600_000_000), "preflight-runtime-" <> nonce)
  let _ = coord_store.close(coordinator)
  let reply = send_runner_cmd(ipc_dir, managed_start_command(db_path, base_url, bot_id, sa_plan_db, coord_db, control_path, writer, "runtime:telegram-bridge"))
  let observed = store.read_keys(storage_config, ["meta/writer_start"])
  let requests = fixture_requests_typed(fixture_pid)
  fixture_stop(fixture_pid)
  let assert Ok(_) = lifecycle.stop_and_verify_test_unit(slice_name, unit_name, db_path, recovery_worker_sha, recovery_guardian_sha)
  let assert Ok(True) = lifecycle.stop_test_slice(slice_name)
  // Cleanup precedes assertions so the negative baseline cannot leak its unit.
  let assert Ok(#(generation, [marker])) = observed
  generation |> should.equal(4)
  marker.exists |> should.equal(False)
  string.contains(reply, "managed_preflight_writer_hold") |> should.equal(True)
  requests |> should.equal([])
}

fn exercise_managed_authority_maintenance(failure_mode: String) {
  use storage_config, db_path, sa_plan_db, coord_db, dir <- with_recovery_store()
  let assert Ok(#(fixture_pid, _, base_url)) = fixture_start()
  fixture_set_mode(fixture_pid, "offset_aware")
  let bot_id = 222_556
  let assert Ok(fresh) = store.begin_new_writer_store(storage_config, bot_id)
  let nonce = int.to_string(service.ffi_system_now_utc_us()) <> int.to_string(int.random(10_000))
  let slice_name = "app-uos_tg_test_poll1024_m" <> nonce <> ".slice"
  let unit_name = "uos-tg-store-test-poll1024-m" <> nonce <> ".service"
  let ipc_dir = start_test_runner(dir, slice_name, unit_name)
  let control_path = mint_unit_registration(dir, slice_name, unit_name, db_path, 1)
  let assert Ok(control_json) = simplifile.read(control_path)
  let assert Ok(control) = lifecycle.decode_control_registration(control_json)
  let writer = codec.WriterRegistration(
    bot_id: bot_id, service_epoch: 1,
    instance_token: files.digest("managed-start-" <> nonce),
    control_digest: files.digest(lifecycle.encode_control_registration(control)),
    store_incarnation_id: control.store_incarnation_id,
    unit_invocation_id: control.unit_invocation_id,
    registered_at_us: control.registered_at_us,
  )
  let assert Ok(2) = store.finish_new_writer_store(fresh, writer)
  let assert Ok(coordinator) = coord_store.open(coord_db)
  let assert Ok(#(_, False)) = coord_store.append(coordinator, sync.Claim("worker-e2e-01", "runtime:telegram-bridge", 3_600_000_000), "maintenance-claim-" <> nonce)
  let task_deadline = service.ffi_system_now_ns() + 5_000_000_000
  case failure_mode {
    "task_expiry" -> {
      let assert Ok(_) = seed_test_sa_plan_task(sa_plan_db, "plan-e2e", "lease-e2e-01", "worker-e2e-01", 1, task_deadline)
      Nil
    }
    _ -> Nil
  }
  let first = send_runner_cmd(ipc_dir, managed_start_command(db_path, base_url, bot_id, sa_plan_db, coord_db, control_path, writer, "runtime:telegram-bridge"))
  string.contains(first, "\"action\":\"started\"") |> should.equal(True)
  let enabled = send_runner_cmd(ipc_dir, "{\"action\":\"enable_managed_authority\",\"ttl_us\":1500000,\"interval_ms\":100}")
  string.contains(enabled, "\"status\":\"enabled\"") |> should.equal(True)
  let before = send_runner_cmd(ipc_dir, "{\"action\":\"get_authority_status\"}")
  let assert Ok(first_until) = json.parse(before, decode.field("valid_until_us", decode.int, decode.success))
  let assert Ok(first_id) = json.parse(before, decode.field("lease_id", decode.string, decode.success))
  process.sleep(1800)
  let after = send_runner_cmd(ipc_dir, "{\"action\":\"get_authority_status\"}")
  let assert Ok(next_until) = json.parse(after, decode.field("valid_until_us", decode.int, decode.success))
  let assert Ok(next_id) = json.parse(after, decode.field("lease_id", decode.string, decode.success))
  { service.ffi_system_now_utc_us() > first_until } |> should.equal(True)
  { next_until > first_until } |> should.equal(True)
  next_id |> should.equal(first_id)
  case failure_mode { "task_expiry" -> { next_until <= task_deadline / 1000 } |> should.equal(True) _ -> Nil }
  runner_set_authority(ipc_dir, "manual-override", 1, 1, 3_000_000_000_000_000)
  let protected = send_runner_cmd(ipc_dir, "{\"action\":\"get_authority_status\"}")
  let assert Ok(protected_id) = json.parse(protected, decode.field("lease_id", decode.string, decode.success))
  protected_id |> should.equal(first_id)
  string.contains(after, "\"revoked\":false") |> should.equal(True)
  fixture_requests_typed(fixture_pid) |> should.equal([])
  case failure_mode {
    "runtime_release" -> {
      let assert Ok(_) = coord_store.append(coordinator, sync.Release("worker-e2e-01", "runtime:telegram-bridge", 1), "maintenance-release-" <> nonce)
      Nil
    }
    "task_expiry" -> Nil
    _ -> {
      let assert Ok(_) = seed_test_sa_plan_task(sa_plan_db, "plan-e2e", "lease-e2e-01", "worker-e2e-01", 2, 4_000_000_000_000_000_000)
      Nil
    }
  }
  let revoked = await_managed_revoked(ipc_dir, 100)
  runner_set_authority(ipc_dir, "manual-resurrection", 1, 1, 3_000_000_000_000_000)
  let still_revoked = send_runner_cmd(ipc_dir, "{\"action\":\"get_authority_status\"}")
  let retry = send_runner_cmd(ipc_dir, "{\"action\":\"enable_managed_authority\",\"ttl_us\":1500000,\"interval_ms\":100}")
  let refused = runner_poll_cycle(ipc_dir, service.ffi_system_now_utc_us())
  let requests = fixture_requests_typed(fixture_pid)
  fixture_stop(fixture_pid)
  let _ = coord_store.close(coordinator)
  let assert Ok(_) = lifecycle.stop_and_verify_test_unit(slice_name, unit_name, db_path, recovery_worker_sha, recovery_guardian_sha)
  let assert Ok(True) = lifecycle.stop_test_slice(slice_name)
  revoked |> should.equal(True)
  string.contains(still_revoked, "\"authority_revoked\":true") |> should.equal(True)
  string.contains(still_revoked, "\"revoked\":true") |> should.equal(True)
  string.contains(retry, "\"status\":\"refused\"") |> should.equal(True)
  string.contains(refused, "authority_lease_revoked") |> should.equal(True)
  requests |> should.equal([])
}

fn await_managed_revoked(ipc_dir: String, remaining: Int) -> Bool {
  let raw = send_runner_cmd(ipc_dir, "{\"action\":\"get_authority_status\"}")
  case string.contains(raw, "\"authority_revoked\":true") && string.contains(raw, "\"revoked\":true") {
    True -> True
    False -> case remaining <= 0 {
      True -> False
      False -> { process.sleep(50) await_managed_revoked(ipc_dir, remaining - 1) }
    }
  }
}

pub fn e2e_managed_renewal_and_runtime_release_suspension_test() {
  exercise_managed_authority_maintenance("runtime_release")
}
pub fn e2e_managed_renewal_and_changed_task_suspension_test() {
  exercise_managed_authority_maintenance("changed_task")
}

pub fn e2e_managed_renewal_never_extends_parent_task_test() {
  exercise_managed_authority_maintenance("task_expiry")
}

fn exercise_active_managed_flow(new_epoch_before_stop: Bool) {
  use storage_config, db_path, sa_plan_db, coord_db, dir <- with_recovery_store()
  let assert Ok(#(fixture_pid, _, base_url)) = fixture_start()
  fixture_set_mode(fixture_pid, "offset_aware")
  let bot_id = 222_556
  let assert Ok(fresh) = store.begin_new_writer_store(storage_config, bot_id)
  let nonce = int.to_string(service.ffi_system_now_utc_us()) <> int.to_string(int.random(10_000))
  let slice_name = "app-uos_tg_test_poll1024_m" <> nonce <> ".slice"
  let unit_name = "uos-tg-store-test-poll1024-m" <> nonce <> ".service"
  let ipc_dir = start_test_runner(dir, slice_name, unit_name)
  let control_path = mint_unit_registration(dir, slice_name, unit_name, db_path, 1)
  let assert Ok(control_json) = simplifile.read(control_path)
  let assert Ok(control) = lifecycle.decode_control_registration(control_json)
  let writer = codec.WriterRegistration(
    bot_id: bot_id, service_epoch: 1,
    instance_token: files.digest("managed-start-" <> nonce),
    control_digest: files.digest(lifecycle.encode_control_registration(control)),
    store_incarnation_id: control.store_incarnation_id,
    unit_invocation_id: control.unit_invocation_id,
    registered_at_us: control.registered_at_us,
  )
  let assert Ok(2) = store.finish_new_writer_store(fresh, writer)
  let assert Ok(coordinator) = coord_store.open(coord_db)
  let assert Ok(#(_, False)) = coord_store.append(coordinator, sync.Claim("worker-e2e-01", "runtime:telegram-bridge", 3_600_000_000), "active-runtime-" <> nonce)
  let cmd = managed_start_command(db_path, base_url, bot_id, sa_plan_db, coord_db, control_path, writer, "runtime:telegram-bridge")
    |> string.replace("\"managed_start\":true", "\"managed_start\":true,\"managed_auto\":true")
  let started = send_runner_cmd(ipc_dir, cmd)
  string.contains(started, "\"action\":\"started\"") |> should.equal(True)
  let authority = send_runner_cmd(ipc_dir, "{\"action\":\"get_authority_status\"}")
  let assert Ok(expiry) = json.parse(authority, decode.field("valid_until_us", decode.int, decode.success))
  { expiry > service.ffi_system_now_utc_us() } |> should.equal(True)
  string.contains(authority, "\"revoked\":false") |> should.equal(True)
  // No manual set_authority/enable call: active startup supplies the observed lease.
  fixture_set_updates(fixture_pid, [
    "{\"update_id\":9401,\"message\":{\"message_id\":501,\"chat\":{\"id\":100,\"type\":\"private\"},\"from\":{\"id\":200,\"is_bot\":false},\"text\":\"/doctor\",\"date\":1700000000}}",
    "{\"update_id\":9402,\"message\":{\"message_id\":502,\"chat\":{\"id\":100,\"type\":\"private\"},\"from\":{\"id\":200,\"is_bot\":false},\"text\":\"/saplan\",\"date\":1700000000}}",
  ])
  let terminal = send_runner_cmd(ipc_dir, "{\"action\":\"finite_automatic_loop\"}")
  string.contains(terminal, "\"reason\":\"max_cycles\"") |> should.equal(True)
  string.contains(terminal, "\"completed_cycles\":2") |> should.equal(True)
  let request1 = ledger.make_request_id(bot_id, 9401)
  let request2 = ledger.make_request_id(bot_id, 9402)
  let assert Ok(#(_, [row1, row2])) = store.read_keys(storage_config, [
    codec.chunk_key(request1, 0), codec.chunk_key(request2, 0),
  ])
  let assert Ok(raw1) = codec.decode_row_value(row1)
  let assert Ok(raw2) = codec.decode_row_value(row2)
  let assert Ok(chunk1) = codec.decode_chunk_value(raw1)
  let assert Ok(chunk2) = codec.decode_chunk_value(raw2)
  chunk1.status |> should.equal(ledger.OutboxDelivered(42))
  chunk2.status |> should.equal(ledger.OutboxDelivered(42))
  string.contains(chunk1.payload, "UNOBSERVED_RUNTIME") |> should.equal(True)
  string.contains(chunk2.payload, "uos.sa_plan.observer.v1") |> should.equal(True)
  let requests = fixture_requests_typed(fixture_pid)
  list.filter(requests, fn(r) { let #(_, path, _, _) = r string.contains(path, "/getUpdates") })
    |> list.length |> should.equal(2)
  list.filter(requests, fn(r) { let #(_, path, _, _) = r string.contains(path, "/sendMessage") })
    |> list.length |> should.equal(2)
  case new_epoch_before_stop {
    True -> {
      let assert Ok(_) = coord_store.append(coordinator, sync.Release("worker-e2e-01", "runtime:telegram-bridge", 1), "replace-release-" <> nonce)
      let assert Ok(#(claimed, False)) = coord_store.append(coordinator, sync.Claim("worker-e2e-01", "runtime:telegram-bridge", 3_600_000_000), "replace-claim-" <> nonce)
      claimed.epoch |> should.equal(2)
    }
    False -> Nil
  }
  let stopped = send_runner_cmd(ipc_dir, "{\"action\":\"stop_managed_service\"}")
  let observed_fence = coord_store.observe(coordinator, fn(state, boot, now) {
    sync.check(state, "worker-e2e-01", "runtime:telegram-bridge", case new_epoch_before_stop { True -> 2 False -> 1 }, boot, now)
    |> result.map_error(coord_store.RefusedError)
  })
  let _ = coord_store.close(coordinator)
  fixture_stop(fixture_pid)
  let assert Ok(_) = lifecycle.stop_and_verify_test_unit(slice_name, unit_name, db_path,
    recovery_worker_sha, recovery_guardian_sha)
  let assert Ok(True) = lifecycle.stop_test_slice(slice_name)
  case new_epoch_before_stop {
    False -> {
      string.contains(stopped, "\"status\":\"stopped_and_released\"") |> should.equal(True)
      result.is_error(observed_fence) |> should.equal(True)
    }
    True -> {
      string.contains(stopped, "\"status\":\"cleanup_unconfirmed\"") |> should.equal(True)
      observed_fence |> should.equal(Ok(Nil))
    }
  }
}

pub fn e2e_active_managed_start_dispatch_and_clean_release_test() {
  exercise_active_managed_flow(False)
}

pub fn e2e_stale_shutdown_cannot_release_successor_runtime_test() {
  exercise_active_managed_flow(True)
}

fn writer_from_control(path: String, bot_id: Int, nonce: String) -> codec.WriterRegistration {
  let assert Ok(raw) = simplifile.read(path)
  let assert Ok(control) = lifecycle.decode_control_registration(raw)
  codec.WriterRegistration(bot_id, control.service_epoch, files.digest(nonce),
    files.digest(lifecycle.encode_control_registration(control)), control.store_incarnation_id,
    control.unit_invocation_id, control.registered_at_us)
}

fn exercise_managed_successor(start_predecessor: Bool, run_entry: Bool, expired_action: Bool) {
  use storage_config, db_path, sa_plan_db, coord_db, dir <- with_recovery_store()
  let assert Ok(#(fixture_pid, _, base_url)) = fixture_start()
  fixture_set_mode(fixture_pid, "offset_aware")
  let bot_id = 222_558
  let assert Ok(fresh) = store.begin_new_writer_store(storage_config, bot_id)
  let nonce = int.to_string(service.ffi_system_now_utc_us()) <> int.to_string(int.random(10_000))
  let old_slice = "app-uos_tg_test_poll1024_r1" <> nonce <> ".slice"
  let old_unit = "uos-tg-store-test-poll1024-r1" <> nonce <> ".service"
  let old_ipc = start_test_runner(dir, old_slice, old_unit)
  let old_control = mint_unit_registration(dir, old_slice, old_unit, db_path, 1)
  let previous = writer_from_control(old_control, bot_id, "old-" <> nonce)
  let assert Ok(2) = store.finish_new_writer_store(fresh, previous)
  let historical=case expired_action {
    True -> Some(managed_action.seed_pending(storage_config,sa_plan_db,dir,bot_id))
    False -> None
  }
  let assert Ok(coordinator) = coord_store.open(coord_db)
  let assert Ok(_) = coord_store.append(coordinator,
    sync.Claim("worker-e2e-01", "runtime:telegram-bridge", 3_600_000_000), "recover-claim1-" <> nonce)
  case start_predecessor {
    False -> Nil
    True -> {
      let old_cmd = managed_start_command(db_path, base_url, bot_id, sa_plan_db, coord_db,
        old_control, previous, "runtime:telegram-bridge")
        |> string.replace("\"managed_start\":true", "\"managed_start\":true,\"managed_auto\":true")
        |> with_historical_action(historical,dir)
      let started = send_runner_cmd(old_ipc, old_cmd)
      string.contains(started, "\"action\":\"started\"") |> should.equal(True)
    }
  }
  // Whole-unit termination proves quiescence, including all descendants.
  let assert Ok(receipt) = lifecycle.stop_and_verify_test_unit_epoch(old_slice, old_unit,
    db_path, recovery_worker_sha, recovery_guardian_sha, 1)
  let assert Ok(_) = coord_store.append(coordinator,
    sync.Release("worker-e2e-01", "runtime:telegram-bridge", 1), "recover-release1-" <> nonce)
  let assert Ok(#(grant, False)) = coord_store.append(coordinator,
    sync.Claim("worker-e2e-01", "runtime:telegram-bridge", 3_600_000_000), "recover-claim2-" <> nonce)
  grant.epoch |> should.equal(2)
  let new_slice = "app-uos_tg_test_poll1024_r2" <> nonce <> ".slice"
  let new_unit = "uos-tg-store-test-poll1024-r2" <> nonce <> ".service"
  let new_ipc = start_test_runner(dir, new_slice, new_unit)
  let new_control = mint_unit_registration(dir, new_slice, new_unit, db_path, 2)
  let next = writer_from_control(new_control, bot_id, "next-" <> nonce)
  let assert Ok(previous_json) = codec.encode_writer_registration(previous)
  let receipt_path = dir <> "/recovery-cleanup.json"
  let assert Ok(_) = simplifile.write(receipt_path, lifecycle.encode_unit_cleanup_receipt(receipt))
  let extra = [
    #("previous_writer_registration", json.string(previous_json)),
    #("control_registration_path", json.string(old_control)),
    #("cleanup_receipt_path", json.string(receipt_path)),
    #("coordinator_epoch", json.int(2)),
  ] |> json.object |> json.to_string
  let command = managed_start_command(db_path, base_url, bot_id, sa_plan_db, coord_db,
    new_control, next, "runtime:telegram-bridge")
    |> string.replace("\"service_epoch\":1", "\"service_epoch\":2")
    |> string.drop_end(1)
    |> fn(prefix) { prefix <> "," <> string.drop_start(extra, 1) }
    |> with_historical_action(historical,dir)
  let before = store.read_keys(storage_config, [codec.writer_registration_key(), "meta/writer_start"])
  // Incorrect predecessor identity must not mutate the store or burn the receipt.
  let assert Ok(wrong_previous) = codec.encode_writer_registration(
    codec.WriterRegistration(..previous, control_digest: files.digest("wrong-control")))
  let rejected = send_runner_cmd(new_ipc,
    string.replace(command, json.to_string(json.string(previous_json)),
      json.to_string(json.string(wrong_previous))))
  string.contains(rejected, "recovery_predecessor_writer_control_mismatch") |> should.equal(True)
  store.read_keys(storage_config, [codec.writer_registration_key(), "meta/writer_start"])
    |> should.equal(before)
  case historical {
    None -> {
  fixture_set_updates(fixture_pid, [
    "{\"update_id\":9601,\"message\":{\"message_id\":601,\"chat\":{\"id\":100,\"type\":\"private\"},\"from\":{\"id\":200,\"is_bot\":false},\"text\":\"/doctor\",\"date\":1700000000}}",
    "{\"update_id\":9602,\"message\":{\"message_id\":602,\"chat\":{\"id\":100,\"type\":\"private\"},\"from\":{\"id\":200,\"is_bot\":false},\"text\":\"/saplan\",\"date\":1700000000}}",
  ])
    }
    Some(#(_,id,_,_)) -> fixture_set_updates(fixture_pid,[
      json.object([#("update_id",json.int(9601)),#("message",json.object([
        #("message_id",json.int(601)),#("chat",json.object([#("id",json.int(100)),#("type",json.string("private"))])),
        #("from",json.object([#("id",json.int(200)),#("is_bot",json.bool(False))])),
        #("text",json.string("/approval propose "<>id)),#("date",json.int(1700000000))]))]) |> json.to_string,
      json.object([#("update_id",json.int(9602)),#("message",json.object([
        #("message_id",json.int(602)),#("chat",json.object([#("id",json.int(100)),#("type",json.string("private"))])),
        #("from",json.object([#("id",json.int(200)),#("is_bot",json.bool(False))])),
        #("text",json.string("/approval withdraw "<>id)),#("date",json.int(1700000000))]))]) |> json.to_string,
    ])
  }
  let recovered = send_runner_cmd(new_ipc, case run_entry {
    False -> command
    True -> string.replace(command, "\"action\":\"start_actor\"", "\"action\":\"run_managed\"")
  })
  case run_entry {
    True -> string.contains(recovered, "\"status\":\"stopped_and_released\"") |> should.equal(True)
    False -> {
      string.contains(recovered, "\"action\":\"started\"") |> should.equal(True)
      let duplicate = send_runner_cmd(new_ipc, "{\"action\":\"repeat_managed_start\"}")
      string.contains(duplicate, "\"status\":\"refused\"") |> should.equal(True)
    }
  }
  let assert Ok(#(_, [marker])) = store.read_keys(storage_config, ["meta/writer_start"])
  let assert Ok(marker_raw) = codec.decode_row_value(marker)
  codec.decode_writer_registration(marker_raw) |> should.equal(Ok(next))
  let terminal = case run_entry {
    True -> recovered
    False -> send_runner_cmd(new_ipc, "{\"action\":\"finite_automatic_loop\"}")
  }
  string.contains(terminal, "\"completed_cycles\":2") |> should.equal(True)
  let assert Ok(#(_, [one, two])) = store.read_keys(storage_config, [
    codec.chunk_key(ledger.make_request_id(bot_id, 9601), 0),
    codec.chunk_key(ledger.make_request_id(bot_id, 9602), 0),
  ])
  list.each([one, two], fn(row) {
    let assert Ok(raw) = codec.decode_row_value(row)
    let assert Ok(chunk) = codec.decode_chunk_value(raw)
    chunk.status |> should.equal(ledger.OutboxDelivered(42))
  })
  case historical {
    None -> Nil
    Some(#(_,id,original_proposal,original_profile)) -> {
      let assert Ok(#(_, [inbox_row,proposal_row,cancel_row,authority_row]))=store.read_keys(storage_config,[
        codec.inbox_key(id),store.proposal_key(id),store.cancellation_key(id),codec.authority_key(id)])
      let assert Ok(inbox_raw)=codec.decode_row_value(inbox_row)
      let assert Ok(inbox)=codec.decode_inbox_record(inbox_raw)
      inbox.status |> should.equal(ledger.InboxRejected("withdrawn_by_requester"))
      codec.decode_row_value(proposal_row) |> should.equal(Ok(original_proposal))
      simplifile.read(dir<>"/historical-profile.json") |> should.equal(Ok(original_profile))
      cancel_row.exists |> should.be_false
      authority_row.exists |> should.be_false
      let assert Ok(first_raw)=codec.decode_row_value(one)
      let assert Ok(first)=codec.decode_chunk_value(first_raw)
      string.contains(first.payload,"not configured") |> should.be_true
      let assert Ok(second_raw)=codec.decode_row_value(two)
      let assert Ok(second)=codec.decode_chunk_value(second_raw)
      string.contains(second.payload,"withdrawn. No action was executed") |> should.be_true
    }
  }
  let requests = fixture_requests_typed(fixture_pid)
  list.filter(requests, fn(r) { let #(_, path, _, _) = r string.contains(path, "/sendMessage") })
    |> list.length |> should.equal(2)
  let stopped = case run_entry {
    True -> recovered
    False -> send_runner_cmd(new_ipc, "{\"action\":\"stop_managed_service\"}")
  }
  string.contains(stopped, "\"status\":\"stopped_and_released\"") |> should.equal(True)
  let assert Ok(_) = coord_store.close(coordinator)
  fixture_stop(fixture_pid)
  let assert Ok(_) = lifecycle.stop_and_verify_test_unit_epoch(new_slice, new_unit, db_path,
    recovery_worker_sha, recovery_guardian_sha, 2)
}

pub fn e2e_managed_successor_recovers_predecessor_that_never_started_test() {
  exercise_managed_successor(False, False, False)
}

pub fn e2e_managed_successor_recovers_terminated_active_predecessor_test() {
  exercise_managed_successor(True, False, False)
}

pub fn e2e_runtime_entry_validates_before_start_runs_and_releases_test() {
  use storage_config, db_path, sa_plan_db, coord_db, dir <- with_recovery_store()
  let assert Ok(#(fixture_pid, _, base_url)) = fixture_start()
  fixture_set_mode(fixture_pid, "offset_aware")
  let bot_id = 222_556
  let assert Ok(fresh) = store.begin_new_writer_store(storage_config, bot_id)
  let nonce = int.to_string(service.ffi_system_now_utc_us()) <> int.to_string(int.random(10_000))
  let slice_name = "app-uos_tg_test_poll1024_m" <> nonce <> ".slice"
  let unit_name = "uos-tg-store-test-poll1024-m" <> nonce <> ".service"
  let ipc_dir = start_test_runner(dir, slice_name, unit_name)
  let control_path = mint_unit_registration(dir, slice_name, unit_name, db_path, 1)
  let assert Ok(control_json) = simplifile.read(control_path)
  let assert Ok(control) = lifecycle.decode_control_registration(control_json)
  let writer = codec.WriterRegistration(
    bot_id: bot_id, service_epoch: 1,
    instance_token: files.digest("managed-start-" <> nonce),
    control_digest: files.digest(lifecycle.encode_control_registration(control)),
    store_incarnation_id: control.store_incarnation_id,
    unit_invocation_id: control.unit_invocation_id,
    registered_at_us: control.registered_at_us,
  )
  let assert Ok(2) = store.finish_new_writer_store(fresh, writer)
  let assert Ok(coordinator) = coord_store.open(coord_db)
  let assert Ok(#(_, False)) = coord_store.append(coordinator, sync.Claim("worker-e2e-01", "runtime:telegram-bridge", 3_600_000_000), "active-runtime-" <> nonce)
  fixture_set_updates(fixture_pid, [
    "{\"update_id\":9401,\"message\":{\"message_id\":501,\"chat\":{\"id\":100,\"type\":\"private\"},\"from\":{\"id\":200,\"is_bot\":false},\"text\":\"/doctor\",\"date\":1700000000}}",
    "{\"update_id\":9402,\"message\":{\"message_id\":502,\"chat\":{\"id\":100,\"type\":\"private\"},\"from\":{\"id\":200,\"is_bot\":false},\"text\":\"/saplan\",\"date\":1700000000}}",
  ])
  let cmd = managed_start_command(db_path, base_url, bot_id, sa_plan_db, coord_db, control_path, writer, "runtime:telegram-bridge")
    |> string.replace("\"action\":\"start_actor\"", "\"action\":\"run_managed\"")
  let invalid = "{\"loop_lifetime_ms\":0," <> string.drop_start(cmd, 1)
  let refused = send_runner_cmd(ipc_dir, invalid)
  string.contains(refused, "invalid_loop_configuration") |> should.equal(True)
  let assert Ok(#(2, [unconsumed])) = store.read_keys(storage_config, ["meta/writer_start"])
  unconsumed.exists |> should.be_false
  let terminal = send_runner_cmd(ipc_dir, cmd)
  string.contains(terminal, "\"status\":\"stopped_and_released\"") |> should.equal(True)
  string.contains(terminal, "\"completed_cycles\":2") |> should.equal(True)
  let request1 = ledger.make_request_id(bot_id, 9401)
  let request2 = ledger.make_request_id(bot_id, 9402)
  let assert Ok(#(_, [row1, row2])) = store.read_keys(storage_config, [
    codec.chunk_key(request1, 0), codec.chunk_key(request2, 0),
  ])
  let assert Ok(raw1) = codec.decode_row_value(row1)
  let assert Ok(raw2) = codec.decode_row_value(row2)
  let assert Ok(chunk1) = codec.decode_chunk_value(raw1)
  let assert Ok(chunk2) = codec.decode_chunk_value(raw2)
  chunk1.status |> should.equal(ledger.OutboxDelivered(42))
  chunk2.status |> should.equal(ledger.OutboxDelivered(42))
  string.contains(chunk1.payload, "UNOBSERVED_RUNTIME") |> should.equal(True)
  string.contains(chunk2.payload, "uos.sa_plan.observer.v1") |> should.equal(True)
  let requests = fixture_requests_typed(fixture_pid)
  list.filter(requests, fn(r) { let #(_, path, _, _) = r string.contains(path, "/getUpdates") })
    |> list.length |> should.equal(2)
  list.filter(requests, fn(r) { let #(_, path, _, _) = r string.contains(path, "/sendMessage") })
    |> list.length |> should.equal(2)
  let observed = coord_store.observe(coordinator, fn(state, boot, now) {
    sync.check(state, "worker-e2e-01", "runtime:telegram-bridge", 1, boot, now)
    |> result.map_error(coord_store.RefusedError)
  })
  result.is_error(observed) |> should.equal(True)
  let assert Ok(_) = coord_store.close(coordinator)
  fixture_stop(fixture_pid)
  let assert Ok(_) = lifecycle.stop_and_verify_test_unit(slice_name, unit_name, db_path,
    recovery_worker_sha, recovery_guardian_sha)
}

pub fn e2e_runtime_entry_recovers_runs_and_releases_test() {
  exercise_managed_successor(True, True, False)
}

pub fn e2e_task_detail_and_missing_dispatch_test() {
  exercise_automatic_command_dispatch("/task lease-e2e-01", "\"task_id\":\"lease-e2e-01\"", "/task missing-task", "task_not_found")
}

pub fn e2e_task_invalid_and_real_plan_dispatch_test() {
  exercise_automatic_command_dispatch("/task x;DROP", "denied_mutation", "/tasks", "uos.sa_plan.observer.v1")
}

pub fn e2e_task_observation_changes_and_recovers_test() {
  use _storage_config, _db_path, sa_plan_db, _coord_db, _dir <- with_recovery_store()
  let req = task_observer.ObserveRequest(
    guardian_exe: service.canonical_guardian_exe,
    guardian_sha256: service.canonical_guardian_sha256,
    observer_exe: service.canonical_observer_exe,
    observer_sha256: service.canonical_observer_sha256,
    db_path: sa_plan_db, plan_id: "plan-e2e", task_id: task_observer.NoTask,
    deadline_ms: 2500, max_bytes: 262_144,
  )
  let assert Ok(_) = seed_test_sa_plan_task(sa_plan_db, "plan-e2e", "DETAIL_TASK", "fixture-worker", 1, 4_000_000_000_000_000_000)
  let assert Ok(first) = task_command.observe_task(req, "DETAIL_TASK")
  string.contains(first, "\"attempt\":1") |> should.equal(True)
  let assert Ok(_) = seed_test_sa_plan_task(sa_plan_db, "plan-e2e", "DETAIL_TASK", "fixture-worker", 2, 4_000_000_000_000_000_000)
  let assert Ok(second) = task_command.observe_task(req, "DETAIL_TASK")
  string.contains(second, "\"attempt\":2") |> should.equal(True)
  assert first != second
  task_command.observe_task(task_observer.ObserveRequest(..req, db_path: sa_plan_db <> ".missing"), "DETAIL_TASK")
    |> should.equal(Error("task_observer_failed"))
  let assert Ok(recovered) = task_command.observe_task(req, "DETAIL_TASK")
  recovered |> should.equal(second)
  task_command.observe_task(req, "ABSENT") |> should.equal(Error("task_not_found"))
}

pub fn e2e_conversation_history_and_agy_dispatch_test() {
  exercise_conversation_dispatch("Hello","Model reply","/agy follow up","Model reply","success",10)
}

pub fn e2e_conversation_daily_limit_test() {
  exercise_conversation_dispatch("Hello","Model reply","/agy follow up","Daily conversation request limit reached","success",1)
}

pub fn e2e_conversation_failure_has_no_memory_test() {
  exercise_conversation_dispatch("Hello","Assistant unavailable","/agy follow up","Assistant unavailable","fail",10)
}

pub fn e2e_conversation_authority_loss_blocks_model_post_test() {
  exercise_conversation_dispatch("Hello","","","","expire",10)
}

pub fn e2e_conversation_empty_agy_does_not_poison_writer_test() {
  exercise_conversation_dispatch("/agy","Use /agy","Hello","Model reply","empty",10)
}

pub fn e2e_memory_history_reads_persisted_exchange_test() {
  exercise_conversation_dispatch("Hello","Model reply","/history 1","You: Hello","memory_read",10)
}

pub fn e2e_memory_status_does_not_charge_model_budget_test() {
  exercise_conversation_dispatch("Hello","Model reply","/memory","1 of 8","memory_read",10)
}

pub fn e2e_memory_clear_commits_before_confirmation_test() {
  exercise_conversation_dispatch("Hello","Model reply","/memory clear","has been cleared","memory_clear",10)
}

pub fn e2e_memory_invalid_clear_preserves_exchange_test() {
  exercise_conversation_dispatch("Hello","Model reply","/memory clear all","Usage:","memory_read",10)
}

pub fn e2e_memory_commands_work_with_model_disabled_test() {
  exercise_automatic_command_dispatch("/memory","0 of 8","/messages","No stored conversation history")
}

pub fn e2e_tool_alias_and_task_dispatch_test() {
  exercise_automatic_command_dispatch("/tool query_task {\"task_id\":\"lease-e2e-01\"}", "\"task_id\":\"lease-e2e-01\"", "/action\tquery_saplan\t{}", "uos.sa_plan.observer.v1")
}
pub fn e2e_tool_help_and_missing_task_test() {
  exercise_automatic_command_dispatch("/tool", "query_task", "/action query_task {\"task_id\":\"missing-task\"}", "task_not_found")
}
pub fn e2e_tool_scope_override_and_mutation_refused_test() {
  exercise_automatic_command_dispatch("/tool query_task {\"task_id\":\"lease-e2e-01\",\"plan\":\"foreign\"}", "denied_mutation", "/action rotate_keys {}", "denied_mutation")
}

pub fn e2e_status_and_system_health_tool_dispatch_test() {
  exercise_automatic_command_dispatch("/status", "development_reference_1h_observation_only",
    "/tool query_system_health {}", "\"version\":\"0.1.0\"")
}
pub fn e2e_status_parameters_refused_test() {
  exercise_automatic_command_dispatch("/status {\"url\":\"http://evil/\"}", "denied_mutation",
    "/action query_system_health {\"host\":\"evil\"}", "denied_mutation")
}
pub fn e2e_health_and_status_operational_status_dispatch_test() {
  exercise_automatic_command_dispatch("/health", "\"global_healthy\":null",
    "/status", "uos.telegram.operational-status.v1")
}
pub fn e2e_health_parameters_refused_test() {
  exercise_automatic_command_dispatch("/health {\"url\":\"http://evil/\"}", "denied_mutation",
    "/health {\"host\":\"evil\"}", "denied_mutation")
}

pub fn e2e_kernel_version_alias_and_tool_test() {
  exercise_automatic_command_dispatch("/zigvm version", "\"version\":\"0.1.0\"",
    "/tool query_zigvm_version {}", "installed_executable_version_only")
}
pub fn e2e_kernel_eval_and_override_refused_test() {
  exercise_automatic_command_dispatch("/zigvm eval dangerous", "denied_mutation",
    "/action query_zigvm_version {\"path\":\"evil\"}", "denied_mutation")
}


pub fn e2e_coordination_peers_and_board_test() {
  exercise_automatic_command_dispatch("/peers", "fresh-self-reported",
    "/board", "\"scope\":\"metadata_counts_only\"")
}
pub fn e2e_coordination_tool_and_scope_refusal_test() {
  exercise_automatic_command_dispatch("/tool query_peers {}", "\"session\":\"worker-e2e-01\"",
    "/action query_board {\"path\":\"evil\"}", "denied_mutation")
}

pub fn e2e_knowledge_wiki_and_zk_test() {
  exercise_automatic_command_dispatch("/wiki uos-master-knowledge-graph-and-living-ontology",
    "docs/wiki/20260905-1721-uos-master-knowledge-graph-and-living-ontology.md",
    "/zk 20260729-fractal-atlas", "docs/zk/20260729-fractal-atlas.md")
}
pub fn e2e_knowledge_tool_and_scope_refusal_test() {
  exercise_automatic_command_dispatch("/tool query_knowledge {\"view\":\"all\",\"query\":\"20260729-fractal-atlas\"}",
    "observed_document_corpus",
    "/action query_knowledge {\"root\":\"/etc\"}", "denied_mutation")
}

pub fn e2e_unified_search_task_and_document_test() {
  exercise_automatic_command_dispatch("/search lease-e2e-01","\"task_id\":\"lease-e2e-01\"",
    "/search 20260729-fractal-atlas","docs/zk/20260729-fractal-atlas.md")
}
pub fn e2e_search_tool_and_scope_refusal_test() {
  exercise_automatic_command_dispatch("/tool query_search {\"query\":\"definitely-no-match-1749\"}","\"matched_total\":0",
    "/action query_search {\"query\":\"uos\",\"plan\":\"foreign\"}","denied_mutation")
}

pub fn e2e_matrix_versions_and_tool_test() {
  exercise_automatic_command_dispatch("/sutra","matrix_client_versions_endpoint",
    "/tool query_matrix_versions {}","supported_versions")
}
pub fn e2e_matrix_scope_refused_test() {
  exercise_automatic_command_dispatch("/sutra foreign","denied_mutation",
    "/action query_matrix_versions {\"host\":\"evil\"}","denied_mutation")
}

fn with_historical_action(command:String,historical:Option(#(String,String,String,String)),root:String) -> String {
 case historical {
   None -> command
   Some(#(sha,_,_,_)) -> string.drop_end(command,1)
     <> ",\"test_historical_action_profile\":" <> json.to_string(json.array([root,sha],json.string)) <> "}"
 }
}
pub fn e2e_managed_successor_preserves_expired_signed_action_and_allows_withdrawal_test() {
 exercise_managed_successor(True,False,True)
}

pub fn e2e_fmea_current_source_and_tool_refresh_test() {
  exercise_configured_dispatch("/fmea","\"rpn\":36",
    "/tool query_fmea {\"task_id\":\"lease-e2e-01\"}","\"rpn\":60","disabled",10,"refresh")
}
pub fn e2e_fmea_stale_and_scope_refusal_test() {
  exercise_configured_dispatch("/fmea lease-e2e-01","\"freshness\":\"stale\"",
    "/tool query_fmea {\"path\":\"/private\"}","denied_mutation","disabled",10,"stale")
}
pub fn e2e_fmea_invalid_source_and_absent_task_test() {
  exercise_configured_dispatch("/fmea","\"status\":\"unavailable\"",
    "/fmea missing-task","\"status\":\"unavailable\"","disabled",10,"malformed")
}
pub fn e2e_fmea_missing_source_is_not_zero_risk_test() {
  exercise_configured_dispatch("/fmea","no zero-risk conclusion",
    "/tool query_fmea {}","no zero-risk conclusion","disabled",10,"missing")
}

pub fn e2e_fmea_unconfigured_source_is_explicit_test() {
  exercise_automatic_command_dispatch("/fmea","\"status\":\"unavailable\"",
    "/tool query_fmea {}","no zero-risk conclusion")
}
pub fn e2e_fmea_absent_task_does_not_cross_scope_test() {
  exercise_configured_dispatch("/fmea absent-task","\"status\":\"unavailable\"",
    "/fmea lease-e2e-01","\"rpn\":36","disabled",10,"fresh")
}

pub fn e2e_ecology_and_tool_dispatch_test() {
  exercise_automatic_command_dispatch("/ecology","local_participant_plane_not_service_admission",
    "/tool query_ecology {}","\"service_health\":\"UNVERIFIED\"")
}
pub fn e2e_ecology_scope_refusal_test() {
  exercise_automatic_command_dispatch("/ecology foreign","denied_mutation",
    "/action query_ecology {\"url\":\"http://evil/\"}","denied_mutation")
}

pub fn e2e_rete_command_and_tool_test() {
 exercise_automatic_command_dispatch("/rete watchdog=true,mesh_running=true","\"verdict\":\"pass\"",
   "/tool evaluate_rete {\"facts\":\"e_stop=true\"}","\"verdict\":\"rejected\"")
}
pub fn e2e_rete_scope_and_missing_facts_test() {
 exercise_automatic_command_dispatch("/rete","denied_mutation",
   "/tool evaluate_rete {\"facts\":\"watchdog=true\",\"worker\":\"/private\"}","denied_mutation")
}

pub fn e2e_storage_and_nvme_alias_test() {
 exercise_automatic_command_dispatch("/storage","host_block_devices_root_capacity_and_policy_probe",
 "/nvme","\"production_interlock_enforcement\":\"NOT_ESTABLISHED\"")
}
pub fn e2e_storage_tool_and_scope_refusal_test() {
 exercise_automatic_command_dispatch("/tool query_storage {}","\"osd_allocation_authority\":\"NOT_GRANTED\"",
 "/action query_storage {\"path\":\"/dev/nvme0n1\"}","denied_mutation")
}

pub fn e2e_checklist_and_aspect_records_test() {
 exercise_configured_dispatch("/checklist","uos.telegram.verification.v1","/aspects A01","RECORDED_PARTIAL","disabled",10,"verification")
}
pub fn e2e_verification_changed_source_refuses_test() {
 exercise_configured_dispatch("/tool query_aspects {\"aspect\":\"A01\"}","RECORDED_PARTIAL","/tool query_checklist {}","unavailable","disabled",10,"verification_changed")
}
pub fn e2e_verification_stale_and_scope_refusal_test() {
 exercise_configured_dispatch("/aspects A01","STALE","/tool query_aspects {\"candidate\":\"foreign\"}","Expected only an aspect code","disabled",10,"verification_stale")
}
pub fn e2e_verification_foreign_candidate_refuses_test() {
 exercise_configured_dispatch("/checklist","unavailable","/aspects","unavailable","disabled",10,"verification_foreign")
}
pub fn e2e_verification_missing_source_refuses_test() {
 exercise_configured_dispatch("/checklist","unavailable","/aspects","unavailable","disabled",10,"verification_missing")
}

fn delivery_count(raw:String)->Int {
 let assert Ok(count)=json.parse(raw,decode.subfield(["result","delivered_count"],decode.int,decode.success))
 {count>=1 && count<=16} |> should.be_true
 count
}
fn delivered_payload(config:transport.LocalConfiguration,request:String,count:Int)->String {
 let keys=chunk_keys(request,0,count)
 let assert Ok(#(_,rows))=store.read_keys(config,keys)
 list.length(rows) |> should.equal(count)
 list.map(rows,fn(row){
  row.exists |> should.be_true
  let assert Ok(raw)=codec.decode_row_value(row)
  let assert Ok(chunk)=codec.decode_chunk_value(raw)
  chunk.status |> should.equal(ledger.OutboxDelivered(42))
  chunk.payload
 }) |> string.concat
}

fn chunk_keys(request:String,index:Int,count:Int)->List(String) {
 case index>=count {True->[] False->[codec.chunk_key(request,index),..chunk_keys(request,index+1,count)]}
}

pub fn e2e_checklist_full_record_chunks_test() {
 exercise_configured_dispatch("/checklist","RECORDED_PASS","/aspects A17","UNKNOWN","disabled",10,"verification_all")
}


pub fn e2e_ha_observation_dispatch_test() {
  exercise_automatic_command_dispatch("/ha", "uos.telegram.ha.v1",
    "/tool query_ha {}", "current_telegram_beam_vm")
}

pub fn e2e_ha_scope_override_refusal_test() {
  exercise_automatic_command_dispatch("/ha reset", "denied_mutation",
    "/action query_ha {\"host\":\"other\"}", "denied_mutation")
}

pub fn e2e_finops_budget_aliases_test() {
 exercise_configured_dispatch("/finops","uos.telegram.finops.v1","/budget","ecology_daily_reservation_ledger_only","disabled",10,"budget")
}
pub fn e2e_finops_tool_and_scope_refusal_test() {
 exercise_configured_dispatch("/tool query_finops {}","uos.telegram.finops.v1","/budget tomorrow","without arguments","disabled",10,"budget")
}
pub fn e2e_finops_missing_ledger_test() {
 exercise_configured_dispatch("/finops","unavailable","/budget","unavailable","disabled",10,"budget_missing")
}
pub fn e2e_finops_changed_executable_refuses_test() {
 exercise_configured_dispatch("/finops","unavailable","/tool query_finops {}","unavailable","disabled",10,"budget_badsha")
}

pub fn e2e_oversized_unicode_grapheme_delivery_test() {
 let response=conversation_fixture.response("unicode")
 exercise_conversation_dispatch("Hello",response,"Hello",response,"unicode",10)
}
