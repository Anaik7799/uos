//// Supervised Telegram Service: Polling, Durable Storage, & Bounded Delivery
////
//// Implements the coordinated runtime loop:
//// 1. Authority fencing: lease & epoch verification before side effects.
////    Requires verified canonical coordinator or Sa-plan claim; caller-invented
////    leases and unvetted workers are strictly refused.
//// 2. Single flight polling: getUpdates -> ingress evaluation -> commit_prefix.
//// 3. Startup recovery: watermark discovery -> generation-coherent full inbox
////    enumeration (cursor-paginated) -> ledger recovery with receipt association.
//// 4. Quiescence gate: fail-closed in-memory ServiceWriterHold if unquiesced crash detected.
//// 5. Delivery pipeline: commit_sending -> bounded http POST -> verify 200 OK -> commit_outcome.

import cepaf_gleam/harness/clock as checked_clock
import cepaf_gleam/harness/telegram_conversation as conversation
import cepaf_gleam/harness/telegram_conversation_model as conversation_model
import uos_swarm/openrouter_worker as model
import cepaf_gleam/harness/doctor_projection
import cepaf_gleam/harness/telegram_commands as commands
import cepaf_gleam/harness/telegram_task_command as task_command
import cepaf_gleam/harness/telegram_tool_command as tool_command
import cepaf_gleam/harness/telegram_operational_status as operational_status
import cepaf_gleam/harness/files
import cepaf_gleam/harness/observer_policy as obs_policy
import cepaf_gleam/harness/telegram_delivery_ledger as ledger
import cepaf_gleam/harness/telegram_http_client as http_client
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_lifecycle_adapter as lifecycle
import cepaf_gleam/harness/telegram_poll_rpc as poll_rpc
import cepaf_gleam/harness/telegram_store as store
import cepaf_gleam/harness/telegram_store_codec as codec
import cepaf_gleam/harness/telegram_store_transport as transport
import gleam/bit_array
import gleam/dynamic/decode
import gleam/dict
import gleam/erlang/process.{type Pid, type Subject}
import gleam/erlang/reference
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/result
import gleam/string
import uos_swarm/session_store as coord_store
import uos_swarm/session_sync as sync

pub const canonical_observer_exe = "/home/an/NAS-setup/uos/tools/validation/sa_plan_observer.exe"

pub const canonical_observer_sha256 = "5b9dab694c7486f39decb0f3db4238b74753941a659106d5e12fee3c0fe656e2"

pub const canonical_guardian_exe = "/home/an/NAS-setup/uos/tools/validation/obs_guardian.exe"

pub const canonical_guardian_sha256 = "b7bab1a85ffa3689a2548ff28a391e659c0537104dec7be0f774bae1820ec4be"

pub const max_chunk_bytes = 4096

pub const max_chunks_per_request = 16

pub type AuthorityPaths {
  CanonicalProductionPaths
  IsolatedTestPaths(sa_plan_db: String, coord_db: String)
}

pub fn resolve_sa_plan_db(paths: AuthorityPaths) -> String {
  case paths {
    CanonicalProductionPaths -> "/home/an/NAS-setup/uos/var/sa-plan/uos.sqlite3"
    IsolatedTestPaths(sa_db, _) -> sa_db
  }
}

pub fn chunk_payload_utf8(payload: String) -> List(String) {
  chunk_payload_utf8_bounded(payload, max_chunk_bytes, max_chunks_per_request)
}

pub fn chunk_payload_utf8_bounded(
  payload: String,
  max_bytes: Int,
  max_chunks: Int,
) -> List(String) {
  let cleaned = string.replace(payload, "\u{0}", "[NUL]")
  let trimmed = string.trim(cleaned)
  case trimmed == "" {
    True -> ["(empty)"]
    False -> {
      let graphemes = string.to_graphemes(cleaned)
      let chunks =
        do_chunk_graphemes(graphemes, max_bytes, max_chunks, "", 0, [])
      case list.filter(chunks, fn(c) { string.trim(c) != "" }) {
        [] -> ["(empty)"]
        valid_chunks -> valid_chunks
      }
    }
  }
}

fn do_chunk_graphemes(
  graphemes: List(String),
  max_bytes: Int,
  max_chunks: Int,
  current_chunk: String,
  current_bytes: Int,
  completed_chunks: List(String),
) -> List(String) {
  let is_final_chunk_slot = list.length(completed_chunks) >= max_chunks - 1

  case graphemes {
    [] -> {
      case current_chunk {
        "" -> list.reverse(completed_chunks)
        _ -> list.reverse([current_chunk, ..completed_chunks])
      }
    }
    [g, ..rest] -> {
      let g_bytes = string.byte_size(g)
      case is_final_chunk_slot {
        True -> {
          let trunc_marker = "\n... [truncated]"
          let trunc_marker_bytes = string.byte_size(trunc_marker)
          let limit = max_bytes - trunc_marker_bytes

          case current_bytes + g_bytes <= limit {
            True ->
              do_chunk_graphemes(
                rest,
                max_bytes,
                max_chunks,
                current_chunk <> g,
                current_bytes + g_bytes,
                completed_chunks,
              )
            False -> {
              let final_chunk = case current_chunk {
                "" -> g <> trunc_marker
                _ -> current_chunk <> trunc_marker
              }
              list.reverse([final_chunk, ..completed_chunks])
            }
          }
        }
        False -> {
          case current_bytes + g_bytes <= max_bytes {
            True ->
              do_chunk_graphemes(
                rest,
                max_bytes,
                max_chunks,
                current_chunk <> g,
                current_bytes + g_bytes,
                completed_chunks,
              )
            False -> {
              let next_completed = case current_chunk {
                "" -> completed_chunks
                _ -> [current_chunk, ..completed_chunks]
              }
              do_chunk_graphemes(
                rest,
                max_bytes,
                max_chunks,
                g,
                g_bytes,
                next_completed,
              )
            }
          }
        }
      }
    }
  }
}

pub type ConversationConfiguration {
  ConversationDisabled
  FreeConversation(daily_requests: Int, timeout_ms: Int)
  IsolatedConversation(daily_requests: Int, timeout_ms: Int, io: model.Io)
}

pub type ServiceConfiguration {
  ServiceConfiguration(
    storage_config: transport.LocalConfiguration,
    http_config: http_client.TelegramHttpConfiguration,
    bot_id: Int,
    allowed_pairs: List(#(Int, Int)),
    plan_id: String,
    task_id: String,
    session_id: String,
    resource_id: String,
    worker_id: String,
    expected_task_attempt: Int,
    coordinator_epoch: Int,
    service_epoch: Int,
    poll_limit: Int,
    poll_timeout_s: Int,
    observer_exe: String,
    observer_sha256: String,
    guardian_exe: String,
    guardian_sha256: String,
    authority_paths: AuthorityPaths,
    control_registration_path: Option(String),
    conversation: ConversationConfiguration,
  )
}

pub fn operational_service_configuration(
  storage_config: transport.LocalConfiguration,
  http_config: http_client.TelegramHttpConfiguration,
  bot_id: Int,
  allowed_pairs: List(#(Int, Int)),
  plan_id: String,
  task_id: String,
  worker_id: String,
  session_id: String,
  expected_task_attempt: Int,
  coordinator_epoch: Int,
  service_epoch: Int,
) -> ServiceConfiguration {
  ServiceConfiguration(
    storage_config: storage_config,
    http_config: http_config,
    bot_id: bot_id,
    allowed_pairs: allowed_pairs,
    plan_id: plan_id,
    task_id: task_id,
    session_id: session_id,
    resource_id: "runtime:telegram-bridge",
    worker_id: worker_id,
    expected_task_attempt: expected_task_attempt,
    coordinator_epoch: coordinator_epoch,
    service_epoch: service_epoch,
    poll_limit: 10,
    poll_timeout_s: 5,
    observer_exe: canonical_observer_exe,
    observer_sha256: canonical_observer_sha256,
    guardian_exe: canonical_guardian_exe,
    guardian_sha256: canonical_guardian_sha256,
    authority_paths: CanonicalProductionPaths,
    control_registration_path: None,
    conversation: ConversationDisabled,
  )
}

pub fn development_service_configuration(
  storage_config: transport.LocalConfiguration,
  http_config: http_client.TelegramHttpConfiguration,
  bot_id: Int,
  allowed_pairs: List(#(Int, Int)),
  worker_id: String,
  service_epoch: Int,
) -> ServiceConfiguration {
  ServiceConfiguration(
    storage_config: storage_config,
    http_config: http_config,
    bot_id: bot_id,
    allowed_pairs: allowed_pairs,
    plan_id: "uos/telegram-runtime/20261001-1150",
    task_id: "SERVICE_IMPL",
    session_id: worker_id,
    resource_id: "task:SERVICE_IMPL",
    worker_id: worker_id,
    expected_task_attempt: 8,
    coordinator_epoch: 1,
    service_epoch: service_epoch,
    poll_limit: 10,
    poll_timeout_s: 5,
    observer_exe: canonical_observer_exe,
    observer_sha256: canonical_observer_sha256,
    guardian_exe: canonical_guardian_exe,
    guardian_sha256: canonical_guardian_sha256,
    authority_paths: CanonicalProductionPaths,
    control_registration_path: None,
    conversation: ConversationDisabled,
  )
}

pub fn default_service_configuration(
  storage_config: transport.LocalConfiguration,
  http_config: http_client.TelegramHttpConfiguration,
  bot_id: Int,
  allowed_pairs: List(#(Int, Int)),
  worker_id: String,
  service_epoch: Int,
) -> ServiceConfiguration {
  development_service_configuration(
    storage_config,
    http_config,
    bot_id,
    allowed_pairs,
    worker_id,
    service_epoch,
  )
}

pub type AuthorityLease {
  AuthorityLease(
    lease_id: String,
    expected_task_attempt: Int,
    coordinator_epoch: Int,
    valid_until_us: Int,
  )
}

pub opaque type AuthorityWitness {
  AuthorityWitness(
    plan_id: String,
    task_id: String,
    worker_id: String,
    expected_task_attempt: Int,
    coordinator_epoch: Int,
    lease_until_ns: Int,
    verified_at_ns: Int,
  )
}

pub const max_admission_queue = 16

pub type DeliveryTask {
  DeliveryTask(
    inbox_record: ledger.InboxRecord,
    inbox_version: Int,
    inbox_sha: String,
    chunk: ledger.OutboxChunk,
    chunk_version: Int,
    chunk_sha: String,
    now_us: Int,
    reply_to: Subject(Result(ServiceStepResult, String)),
  )
}

pub type ServiceState {
  ServiceState(
    config: ServiceConfiguration,
    authority: Option(AuthorityLease),
    authority_revoked: Bool,
    writer_state: lifecycle.ServiceWriterState,
    pending_operation: Option(store.PendingOperation),
    watermark: ledger.Watermark,
    watermark_version: Int,
    watermark_sha: String,
    expected_generation: Int,
    in_flight_poll: Bool,
    in_flight_workers: List(Pid),
    poll_worker: Option(Pid),
    dispatch_worker: Option(Pid),
    delivery_queue: List(DeliveryTask),
    recovered_records: List(#(ledger.InboxRecord, List(ledger.OutboxChunk))),
    self_subject: Option(Subject(ServiceMessage)),
    authority_worker: Option(Subject(AuthorityWorkerMessage)),
    store_worker: Option(Subject(StoreWorkerMessage)),
    poller_worker: Option(Subject(PollerWorkerMessage)),
    authority_managed: Bool,
  )
}

pub type ServiceStepResult {
  PollCommitted(count: Int, new_watermark: Int)
  PollEmpty
  PollSkipped(reason: String)
  DeliveryStepSuccess(request_id: String, message_id: Int)
  DeliveryStepFailed(request_id: String, reason: String)
  DeliveryStepUncertain(request_id: String, reason: String)
  RecoveryResult(active_count: Int, held_count: Int, total_records: Int)
  RecoveryHold(reason: String)
  DispatchCycleResult(processed_count: Int, delivered_count: Int)
}

pub type ServiceError {
  ServiceError(state: ServiceState, reason: String)
}

// -----------------------------------------------------------------------------
// Initialization & Startup Recovery
// -----------------------------------------------------------------------------

@external(erlang, "telegram_lifecycle_ffi", "storage_config_db_path")
fn ffi_storage_config_db_path(config: transport.LocalConfiguration) -> String

@external(erlang, "telegram_lifecycle_ffi", "storage_config_worker_sha")
fn ffi_storage_config_worker_sha(config: transport.LocalConfiguration) -> String

@external(erlang, "telegram_lifecycle_ffi", "storage_config_guardian_sha")
fn ffi_storage_config_guardian_sha(
  config: transport.LocalConfiguration,
) -> String

@external(erlang, "telegram_service_ffi", "system_now_utc_us")
pub fn ffi_system_now_utc_us() -> Int

@external(erlang, "telegram_service_ffi", "system_now_ns")
pub fn ffi_system_now_ns() -> Int

fn int_range(from: Int, to: Int, acc: List(Int)) -> List(Int) {
  case from > to {
    True -> list.reverse(acc)
    False -> int_range(from + 1, to, [from, ..acc])
  }
}

pub fn recover_inflight_record(
  storage_config: transport.LocalConfiguration,
  record: ledger.InboxRecord,
) -> Result(#(ledger.InboxRecord, List(ledger.OutboxChunk)), String) {
  let res_key = codec.result_key(record.request_id)
  case store.read_keys(storage_config, [res_key]) {
    Error(err) -> Error("read_result_meta_failed: " <> string.inspect(err))
    Ok(#(meta_gen, [row])) -> {
      case codec.decode_row_value(row) {
        Error("row_absent") -> {
          // Result meta does not exist; processing lacking result stays held
          Ok(ledger.recover_request(record, []))
        }
        Error(err) -> Error("decode_result_row_failed: " <> err)
        Ok(raw_json) -> {
          case codec.decode_result_value(raw_json) {
            Error(err) -> Error("decode_result_meta_failed: " <> err)
            Ok(rm) -> {
              case rm.total_chunks <= 0 {
                True -> Error("invalid_total_chunks_in_result_meta")
                False -> {
                  let chunk_keys =
                    list.map(int_range(0, rm.total_chunks - 1, []), fn(i) {
                      codec.chunk_key(record.request_id, i)
                    })
                  case store.read_keys(storage_config, chunk_keys) {
                    Error(err) ->
                      Error("read_chunk_keys_failed: " <> string.inspect(err))
                    Ok(#(chunk_gen, chunk_rows)) -> {
                      case chunk_gen == meta_gen {
                        False ->
                          Error(
                            "generation_divergence_between_result_and_chunks: meta="
                            <> int.to_string(meta_gen)
                            <> " chunk="
                            <> int.to_string(chunk_gen),
                          )
                        True -> {
                          use chunks <- result.try(
                            list.try_map(chunk_rows, fn(crow) {
                              case codec.decode_row_value(crow) {
                                Error(err) ->
                                  Error("chunk_row_decode_error: " <> err)
                                Ok(cval) ->
                                  codec.decode_chunk_value(cval)
                                  |> result.map_error(fn(err) {
                                    "chunk_value_decode_error: " <> err
                                  })
                              }
                            }),
                          )
                          case list.length(chunks) == rm.total_chunks {
                            False ->
                              Error(
                                "chunk_count_mismatch_with_result_meta: expected "
                                <> int.to_string(rm.total_chunks)
                                <> " got "
                                <> int.to_string(list.length(chunks)),
                              )
                            True -> Ok(ledger.recover_request(record, chunks))
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
    Ok(#(_, _)) -> {
      // Result meta does not exist; processing lacking result stays held
      Ok(ledger.recover_request(record, []))
    }
  }
}

pub fn init_service(
  config: ServiceConfiguration,
  cleanup_receipt: Option(lifecycle.UnitCleanupReceipt),
) -> Result(#(ServiceState, ServiceStepResult), String) {
  case cleanup_receipt {
    None -> {
      // FirstBootstrap conditions B1..B4:
      // Admissible ONLY when demonstrably never been a prior writer (service_epoch == 1)
      case config.service_epoch == 1 {
        True -> {
          // B2: Store must contain ZERO in-flight rows
          case scan_all_inbox_records(config.storage_config, None, None, 0, []) {
            Ok(#(cur_gen, records)) -> {
              let in_flight =
                list.any(records, fn(row) {
                  let #(rec, _, _) = row
                  case rec.status {
                    ledger.InboxProcessing(..) -> True
                    _ -> False
                  }
                })
              case in_flight {
                True -> {
                  // B4: in-flight rows without registration is an unexplained prior writer -> HOLD
                  let reason =
                    "first_bootstrap_rejected: in-flight operations detected without prior registration"
                  let state =
                    ServiceState(
                      config: config,
                      authority: None,
                      authority_revoked: False,
                      writer_state: lifecycle.ServiceWriterHold(reason),
                      pending_operation: None,
                      watermark: ledger.Watermark(last_committed_offset: 0),
                      watermark_version: 0,
                      watermark_sha: "",
                      expected_generation: cur_gen,
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
      authority_managed: False,
                    )
                  Ok(#(state, RecoveryHold(reason)))
                }
                False -> {
                  // B3: Clean initial bootstrap at epoch 1
                  use #(wm, wm_ver, wm_sha) <- result.try(
                    store.read_watermark(config.storage_config)
                    |> result.map_error(fn(err) {
                      "first_bootstrap_watermark_read_failed: " <> string.inspect(err)
                    }),
                  )
                  let state =
                    ServiceState(
                      config: config,
                      authority: None,
                      authority_revoked: False,
                      writer_state: lifecycle.ServiceWriterClean,
                      pending_operation: None,
                      watermark: wm,
                      watermark_version: wm_ver,
                      watermark_sha: wm_sha,
                      expected_generation: cur_gen,
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
      authority_managed: False,
                    )
                  Ok(#(
                    state,
                    RecoveryResult(
                      active_count: 0,
                      held_count: 0,
                      total_records: list.length(records),
                    ),
                  ))
                }
              }
            }
            Error(err) -> {
              let reason =
                "first_bootstrap_store_read_failed: " <> string.inspect(err)
              let state =
                ServiceState(
                  config: config,
                  authority: None,
                  authority_revoked: False,
                  writer_state: lifecycle.ServiceWriterHold(reason),
                  pending_operation: None,
                  watermark: ledger.Watermark(last_committed_offset: 0),
                  watermark_version: 0,
                  watermark_sha: "",
                  expected_generation: 0,
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
      authority_managed: False,
                )
              Ok(#(state, RecoveryHold(reason)))
            }
          }
        }
        False -> {
          // Unknown prior writer at epoch > 1 without cleanup receipt
          let reason =
            "unquiesced_in_flight_operation_detected_without_cleanup_receipt: writer unknown at epoch "
            <> int.to_string(config.service_epoch)
          let state =
            ServiceState(
              config: config,
              authority: None,
              authority_revoked: False,
              writer_state: lifecycle.ServiceWriterHold(reason),
              pending_operation: None,
              watermark: ledger.Watermark(last_committed_offset: 0),
              watermark_version: 0,
              watermark_sha: "",
              expected_generation: 0,
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
      authority_managed: False,
            )
          Ok(#(state, RecoveryHold(reason)))
        }
      }
    }
    Some(receipt) -> {
      case config.control_registration_path {
        None -> {
          let state =
            ServiceState(
              config: config,
              authority: None,
              authority_revoked: False,
              writer_state: lifecycle.ServiceWriterHold(
                "missing_control_registration: registration path required for store writer",
              ),
              pending_operation: None,
              watermark: ledger.Watermark(last_committed_offset: 0),
              watermark_version: 0,
              watermark_sha: "",
              expected_generation: 0,
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
      authority_managed: False,
            )
          Ok(#(
            state,
            RecoveryHold(
              "missing_control_registration: registration path required for store writer",
            ),
          ))
        }
        Some(ctrl_path) -> {
          case init_service_admitted(config, receipt, ctrl_path) {
            Error(hold_reason) -> {
              let state =
                ServiceState(
                  config: config,
                  authority: None,
                  authority_revoked: False,
                  writer_state: lifecycle.ServiceWriterHold(hold_reason),
                  pending_operation: None,
                  watermark: ledger.Watermark(last_committed_offset: 0),
                  watermark_version: 0,
                  watermark_sha: "",
                  expected_generation: 0,
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
      authority_managed: False,
                )
              Ok(#(state, RecoveryHold(hold_reason)))
            }
            Ok(#(admitted_state, step_res)) -> {
              // A7: Consume receipt atomically with admission
              case lifecycle.mark_receipt_consumed(receipt) {
                Error(err) -> {
                  let state =
                    ServiceState(
                      ..admitted_state,
                      writer_state: lifecycle.ServiceWriterHold(
                        "cleanup_receipt_already_consumed_or_reused: " <> err,
                      ),
                    )
                  Ok(#(
                    state,
                    RecoveryHold(
                      "cleanup_receipt_already_consumed_or_reused: " <> err,
                    ),
                  ))
                }
                Ok(Nil) -> Ok(#(admitted_state, step_res))
              }
            }
          }
        }
      }
    }
  }
}

fn init_service_admitted(
  config: ServiceConfiguration,
  receipt: lifecycle.UnitCleanupReceipt,
  ctrl_path: String,
) -> Result(#(ServiceState, ServiceStepResult), String) {
  let expected_db = ffi_storage_config_db_path(config.storage_config)
  let expected_w = ffi_storage_config_worker_sha(config.storage_config)
  let expected_g = ffi_storage_config_guardian_sha(config.storage_config)

  // A8: Worker and guardian expected hashes must be exactly 64-char hex
  use _ <- result.try(
    case string.length(expected_w) == 64 && string.length(expected_g) == 64 {
      True -> Ok(Nil)
      False ->
        Error(
          "invalid_storage_config_hashes: worker and guardian hashes must be 64-char hex",
        )
    },
  )

  // The predecessor is historical but its file and content remain bounded and canonical.
  use reg <- result.try(lifecycle.read_and_verify_prelaunch_control_bounded(
    ctrl_path, "", expected_db, expected_w, expected_g, config.service_epoch - 1, None))

  // A6: Monotone successor check: config.service_epoch == reg.service_epoch + 1
  use _ <- result.try(case config.service_epoch == reg.service_epoch + 1 {
    True -> Ok(Nil)
    False ->
      Error(
        "service_epoch_not_monotone_successor: config epoch="
        <> int.to_string(config.service_epoch)
        <> " reg epoch="
        <> int.to_string(reg.service_epoch),
      )
  })

  // A5: Strict epoch equality between receipt and registration
  let rcpt_epoch = lifecycle.receipt_service_epoch(receipt)
  use _ <- result.try(case rcpt_epoch == reg.service_epoch {
    True -> Ok(Nil)
    False ->
      Error(
        "cleanup_receipt_service_epoch_mismatch: receipt epoch="
        <> int.to_string(rcpt_epoch)
        <> " reg epoch="
        <> int.to_string(reg.service_epoch),
      )
  })

  // A4b: Predecessor unit and slice Invocation ID association
  let rcpt_inv = lifecycle.receipt_invocation_id(receipt)
  let rcpt_slice_inv = lifecycle.receipt_slice_invocation_id(receipt)
  use _ <- result.try(case rcpt_inv == reg.unit_invocation_id {
    True -> Ok(Nil)
    False ->
      Error(
        "predecessor_unit_invocation_id_mismatch: receipt="
        <> rcpt_inv
        <> " registration="
        <> reg.unit_invocation_id,
      )
  })
  use _ <- result.try(case rcpt_slice_inv == reg.slice_invocation_id {
    True -> Ok(Nil)
    False ->
      Error(
        "predecessor_slice_invocation_id_mismatch: receipt="
        <> rcpt_slice_inv
        <> " registration="
        <> reg.slice_invocation_id,
      )
  })

  // A4c: Predecessor unit must be confirmed stopped in systemd
  use predecessor_status <- result.try(
    lifecycle.get_unit_status(reg.unit_name)
    |> result.map_error(fn(err) {
      "predecessor_unit_status_check_failed: " <> err
    }),
  )
  use _ <- result.try(
    case
      predecessor_status.active_state == "inactive"
      || predecessor_status.active_state == "failed"
      || predecessor_status.invocation_id != reg.unit_invocation_id
    {
      True -> Ok(Nil)
      False ->
        Error(
          "predecessor_unit_still_active_or_running: active_state="
          <> predecessor_status.active_state,
        )
    },
  )

  // A2 & A4d: Database path equality
  use _ <- result.try(
    case
      lifecycle.receipt_store_db_path(receipt) == expected_db
      && reg.store_db_path == expected_db
    {
      True -> Ok(Nil)
      False ->
        Error(
          "store_db_path_mismatch: receipt="
          <> lifecycle.receipt_store_db_path(receipt)
          <> " reg="
          <> reg.store_db_path
          <> " config="
          <> expected_db,
        )
    },
  )

  // A3 & A4d: Store incarnation equality evaluated NOW on disk
  use actual_inc <- result.try(
    lifecycle.compute_store_incarnation(expected_db)
    |> result.map_error(fn(err) { "compute_store_incarnation_failed: " <> err }),
  )
  use _ <- result.try(
    case
      lifecycle.receipt_store_incarnation_id(receipt) == actual_inc
      && reg.store_incarnation_id == actual_inc
    {
      True -> Ok(Nil)
      False ->
        Error(
          "store_incarnation_mismatch: observed="
          <> actual_inc
          <> " receipt="
          <> lifecycle.receipt_store_incarnation_id(receipt)
          <> " reg="
          <> reg.store_incarnation_id,
        )
    },
  )

  // A8: Binary hash matching for both receipt and registration
  let rcpt_w = lifecycle.receipt_worker_hash(receipt)
  let rcpt_g = lifecycle.receipt_guardian_hash(receipt)
  use _ <- result.try(case rcpt_w == expected_w && rcpt_g == expected_g {
    True -> Ok(Nil)
    False -> Error("cleanup_receipt_binary_hash_mismatch_with_storage_config")
  })
  use _ <- result.try(
    case reg.worker_hash == expected_w && reg.guardian_hash == expected_g {
      True -> Ok(Nil)
      False -> Error("registration_binary_hash_mismatch_with_storage_config")
    },
  )

  // Causality: predecessor stopped after registering
  use _ <- result.try(
    case lifecycle.receipt_stopped_at_us(receipt) >= reg.registered_at_us {
      True -> Ok(Nil)
      False ->
        Error(
          "cleanup_receipt_stopped_before_registration: causality violation",
        )
    },
  )

  // 3. Read watermark with proven quiescence
  use #(wm, wm_ver, wm_sha) <- result.try(
    store.read_watermark(config.storage_config)
    |> result.map_error(fn(err) {
      "store_read_watermark_failed: " <> string.inspect(err)
    }),
  )

  // 4. Generation-coherent inbox scan across all pages (cursor pagination)
  use #(gen, records) <- result.try(
    scan_all_inbox_records(config.storage_config, None, None, 0, []),
  )

  // 5. Recover in-flight operations (D6) & retain recovered records
  let #(held_count, active_count, recovered_acc) =
    list.fold(records, #(0, 0, []), fn(acc, row) {
      let #(rec, _, _) = row
      case rec.status {
        ledger.InboxProcessing(_, _) -> {
          let #(rec_rec, chunks_rec) = case
            recover_inflight_record(config.storage_config, rec)
          {
            Ok(pair) -> pair
            Error(_) -> #(
              ledger.InboxRecord(
                ..rec,
                status: ledger.InboxHold("unrecoverable_inflight_state"),
              ),
              [],
            )
          }
          #(acc.0 + 1, acc.1, [#(rec_rec, chunks_rec), ..acc.2])
        }
        ledger.InboxHold(_) -> #(acc.0 + 1, acc.1, [#(rec, []), ..acc.2])
        _ -> #(acc.0, acc.1 + 1, acc.2)
      }
    })

  let recovered_records = list.reverse(recovered_acc)

  let state =
    ServiceState(
      config: config,
      authority: None,
      authority_revoked: False,
      writer_state: lifecycle.ServiceWriterClean,
      pending_operation: None,
      watermark: wm,
      watermark_version: wm_ver,
      watermark_sha: wm_sha,
      expected_generation: gen,
      in_flight_poll: False,
      in_flight_workers: [],
      poll_worker: None,
      dispatch_worker: None,
      delivery_queue: [],
      recovered_records: recovered_records,
      self_subject: None,
      authority_worker: None,
      store_worker: None,
      poller_worker: None,
      authority_managed: False,
    )

  let summary =
    RecoveryResult(
      active_count: active_count,
      held_count: held_count,
      total_records: list.length(records),
    )

  Ok(#(state, summary))
}

fn scan_all_inbox_records(
  storage_config: transport.LocalConfiguration,
  cursor: Option(String),
  expected_gen: Option(Int),
  page_count: Int,
  acc: List(#(ledger.InboxRecord, Int, String)),
) -> Result(#(Int, List(#(ledger.InboxRecord, Int, String))), String) {
  case page_count > 100 {
    True -> Error("inbox_scan_exceeded_max_pages_bound_100")
    False -> {
      case store.read_inbox_records(storage_config, 64, cursor) {
        Error(err) ->
          Error("store_read_inbox_records_failed: " <> string.inspect(err))
        Ok(#(gen, records)) -> {
          use initial_gen <- result.try(case expected_gen {
            None -> Ok(gen)
            Some(exp) ->
              case exp == gen {
                True -> Ok(gen)
                False ->
                  Error(
                    "generation_changed_during_scan: expected "
                    <> int.to_string(exp)
                    <> " got "
                    <> int.to_string(gen),
                  )
              }
          })
          let new_acc = list.fold(records, acc, fn(a, r) { [r, ..a] })
          case list.length(records) < 64 {
            True -> Ok(#(initial_gen, list.reverse(new_acc)))
            False -> {
              case list.last(records) {
                Error(_) -> Ok(#(initial_gen, list.reverse(new_acc)))
                Ok(#(last_rec, _, _)) ->
                  scan_all_inbox_records(
                    storage_config,
                    Some(codec.inbox_key(last_rec.request_id)),
                    Some(initial_gen),
                    page_count + 1,
                    new_acc,
                  )
              }
            }
          }
        }
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Authority Management
// -----------------------------------------------------------------------------

pub fn set_authority(
  state: ServiceState,
  lease: AuthorityLease,
) -> ServiceState {
  case state.authority_worker {
    Some(aw) -> authority_worker_set_lease(aw, lease)
    None -> Nil
  }
  ServiceState(..state, authority: Some(lease), authority_revoked: False)
}

pub fn revoke_authority(state: ServiceState) -> ServiceState {
  case state.authority_worker {
    Some(aw) -> authority_worker_revoke_lease(aw)
    None -> Nil
  }
  ServiceState(..state, authority: None, authority_revoked: True)
}

pub type ObservedTask {
  ObservedTask(
    task_id: String,
    state: String,
    worker: Option(String),
    lease_until_ns: Option(String),
    attempt: Int,
  )
}

fn observed_task_decoder() -> decode.Decoder(ObservedTask) {
  use task_id <- decode.field("task_id", decode.string)
  use state <- decode.field("state", decode.string)
  use worker <- decode.field("worker", decode.optional(decode.string))
  use lease_until_ns <- decode.field(
    "lease_until_ns",
    decode.optional(decode.string),
  )
  use attempt <- decode.field("attempt", decode.int)
  decode.success(ObservedTask(task_id, state, worker, lease_until_ns, attempt))
}

fn observed_plan_decoder() -> decode.Decoder(List(ObservedTask)) {
  use tasks <- decode.field("tasks", decode.list(observed_task_decoder()))
  decode.success(tasks)
}

pub fn check_sa_plan_fence(
  observer_exe: String,
  observer_sha256: String,
  guardian_exe: String,
  guardian_sha256: String,
  sa_plan_db: String,
  plan_id: String,
  task_id: String,
  worker_id: String,
  expected_attempt: Int,
  now_ns: Int,
) -> Result(Int, String) {
  case plan_id == "" || task_id == "" || worker_id == "" {
    True -> Error("sa_plan_authority_parameters_empty")
    False -> {
      let req =
        obs_policy.ObserveRequest(
          guardian_exe: guardian_exe,
          guardian_sha256: guardian_sha256,
          observer_exe: observer_exe,
          observer_sha256: observer_sha256,
          db_path: sa_plan_db,
          plan_id: plan_id,
          task_id: obs_policy.Task(task_id),
          deadline_ms: 5000,
          max_bytes: 262_144,
        )
      use observation <- result.try(
        obs_policy.observe(req)
        |> result.map_error(fn(err) {
          "sa_plan_observer_invocation_failed: " <> err
        }),
      )
      use json_str <- result.try(
        bit_array.to_string(observation.payload)
        |> result.replace_error("sa_plan_observer_payload_invalid_utf8"),
      )
      use tasks <- result.try(
        json.parse(json_str, observed_plan_decoder())
        |> result.map_error(fn(err) {
          "sa_plan_observer_json_parse_failed: " <> string.inspect(err)
        }),
      )
      case list.find(tasks, fn(t) { t.task_id == task_id }) {
        Error(_) -> Error("task_not_found_in_plan: " <> task_id)
        Ok(t) -> {
          case t.state {
            "executing" -> {
              case t.worker == Some(worker_id) {
                True -> {
                  case t.attempt == expected_attempt {
                    True -> {
                      case t.lease_until_ns {
                        None -> Error("task_lease_missing_in_store")
                        Some(lease_str) -> {
                          use lease_ns <- result.try(
                            int.parse(lease_str)
                            |> result.replace_error(
                              "task_lease_integer_overflow_or_invalid",
                            ),
                          )
                          case lease_ns > now_ns {
                            True -> Ok(lease_ns)
                            False -> Error("task_lease_expired_in_store")
                          }
                        }
                      }
                    }
                    False -> Error("task_attempt_mismatch")
                  }
                }
                False -> Error("task_worker_mismatch")
              }
            }
            _ -> Error("task_not_executing")
          }
        }
      }
    }
  }
}

pub fn check_coordinator_fence(
  coord_db: String,
  is_canonical: Bool,
  session_id: String,
  resource: String,
  expected_epoch: Int,
) -> Result(Nil, String) {
  case coord_db == "" || session_id == "" || resource == "" {
    True -> Error("coordinator_authority_parameters_empty")
    False -> {
      use store_handle <- result.try(
        case is_canonical {
          True -> coord_store.open_existing(coord_db)
          False -> coord_store.open(coord_db)
        }
        |> result.map_error(fn(err) {
          "coordinator_store_open_failed: " <> coord_store.error_to_string(err)
        }),
      )
      let outcome =
        coord_store.observe(store_handle, fn(state, boot, now) {
          sync.check(state, session_id, resource, expected_epoch, boot, now)
          |> result.map_error(coord_store.RefusedError)
        })
      let _ = coord_store.close(store_handle)
      case outcome {
        Ok(Nil) -> Ok(Nil)
        Error(err) ->
          Error(
            "coordinator_fence_refused: " <> coord_store.error_to_string(err),
          )
      }
    }
  }
}

pub fn verify_authority_config(
  config: ServiceConfiguration,
  now_ns: Int,
) -> Result(AuthorityWitness, String) {
  let #(sa_plan_db, coord_db, is_canonical) = case config.authority_paths {
    CanonicalProductionPaths -> #(
      "/home/an/NAS-setup/uos/var/sa-plan/uos.sqlite3",
      "/home/an/NAS-setup/uos/var/coordination/tri-agent/coordinator.sqlite3",
      True,
    )
    IsolatedTestPaths(sa_db, co_db) -> #(sa_db, co_db, False)
  }
  let trusted_now_ns = ffi_system_now_ns()
  let effective_now_ns = int.max(now_ns, trusted_now_ns)

  use lease_until_ns <- result.try(check_sa_plan_fence(
    config.observer_exe,
    config.observer_sha256,
    config.guardian_exe,
    config.guardian_sha256,
    sa_plan_db,
    config.plan_id,
    config.task_id,
    config.worker_id,
    config.expected_task_attempt,
    effective_now_ns,
  ))
  use _ <- result.try(check_coordinator_fence(
    coord_db,
    is_canonical,
    config.session_id,
    config.resource_id,
    config.coordinator_epoch,
  ))
  let completion_now_ns = ffi_system_now_ns()
  case lease_until_ns > completion_now_ns {
    False -> Error("task_lease_expired_during_authority_verification")
    True ->
      Ok(AuthorityWitness(
        plan_id: config.plan_id,
        task_id: config.task_id,
        worker_id: config.worker_id,
        expected_task_attempt: config.expected_task_attempt,
        coordinator_epoch: config.coordinator_epoch,
        lease_until_ns: lease_until_ns,
        verified_at_ns: completion_now_ns,
      ))
  }
}

pub fn verify_authority(
  state: ServiceState,
  now_us: Int,
) -> Result(AuthorityWitness, String) {
  case state.authority_worker {
    Some(aw) -> authority_worker_verify(aw, now_us, 5000)
    None -> {
      case state.authority_revoked {
        True -> Error("authority_lease_revoked")
        False -> {
          case state.authority {
            None -> Error("authority_lease_missing")
            Some(lease) -> {
              let trusted_now_us = ffi_system_now_utc_us()
              let effective_now_us = int.max(now_us, trusted_now_us)
              case lease.valid_until_us <= effective_now_us {
                True -> Error("authority_lease_invalid_or_expired")
                False -> {
                  case
                    lease.expected_task_attempt
                    == state.config.expected_task_attempt
                  {
                    False -> Error("authority_lease_task_attempt_mismatch")
                    True -> {
                      case
                        lease.coordinator_epoch
                        == state.config.coordinator_epoch
                      {
                        False ->
                          Error("authority_lease_coordinator_epoch_mismatch")
                        True -> {
                          let now_ns = effective_now_us * 1000
                          verify_authority_config(state.config, now_ns)
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

fn svc_poll_updates(
  state: ServiceState,
  offset: Int,
  limit: Int,
  timeout_s: Int,
) -> Result(List(String), String) {
  case state.poller_worker {
    Some(pw) -> {
      use deadline_ms <- result.try(poll_rpc.deadline(
        state.config.http_config.timeout_ms,
      ))
      poller_worker_get_updates(pw, offset, limit, timeout_s, deadline_ms)
    }
    None ->
      http_client.poll_updates(
        state.config.http_config,
        offset,
        limit,
        timeout_s,
      )
  }
}

fn svc_read_watermark(
  state: ServiceState,
) -> Result(#(ledger.Watermark, Int, String), store.StoreError) {
  case state.store_worker {
    Some(sw) -> store_worker_read_watermark(sw, 5000)
    None -> store.read_watermark(state.config.storage_config)
  }
}

fn svc_read_keys(
  state: ServiceState,
  keys: List(String),
) -> Result(#(Int, List(codec.RowResult)), store.StoreError) {
  case state.store_worker {
    Some(sw) -> store_worker_read_keys(sw, keys, 5000)
    None -> store.read_keys(state.config.storage_config, keys)
  }
}

fn svc_commit_prefix(
  state: ServiceState,
  bot_id: Int,
  operation_id: String,
  expected_gen: Int,
  watermark: ledger.Watermark,
  watermark_version: Int,
  watermark_sha: String,
  verdicts: List(guard.IngressVerdict),
  now_ms: Int,
) -> Result(store.CommitPrefixResult, store.StoreError) {
  case state.store_worker {
    Some(sw) ->
      store_worker_commit_prefix(
        sw,
        bot_id,
        operation_id,
        expected_gen,
        watermark,
        watermark_version,
        watermark_sha,
        verdicts,
        now_ms,
        5000,
      )
    None ->
      store.commit_prefix(
        state.config.storage_config,
        bot_id,
        operation_id,
        expected_gen,
        watermark,
        watermark_version,
        watermark_sha,
        verdicts,
        now_ms,
      )
  }
}

fn svc_claim_task_processing(
  state: ServiceState,
  bot_id: Int,
  operation_id: String,
  expected_gen: Int,
  inbox_record: ledger.InboxRecord,
  record_version: Int,
  record_sha: String,
  worker_id: String,
  service_epoch: Int,
  now_ms: Int,
) -> Result(#(codec.Receipt, ledger.InboxRecord), store.StoreError) {
  case state.store_worker {
    Some(sw) ->
      store_worker_claim_task_processing(
        sw,
        bot_id,
        operation_id,
        expected_gen,
        inbox_record,
        record_version,
        record_sha,
        worker_id,
        service_epoch,
        now_ms,
        5000,
      )
    None ->
      store.claim_task_processing(
        state.config.storage_config,
        bot_id,
        operation_id,
        expected_gen,
        inbox_record,
        record_version,
        record_sha,
        worker_id,
        service_epoch,
        now_ms,
      )
  }
}

fn svc_commit_result(
  state: ServiceState,
  bot_id: Int,
  operation_id: String,
  expected_gen: Int,
  inbox_record: ledger.InboxRecord,
  record_version: Int,
  record_sha: String,
  response_chunks: List(String),
  worker_id: String,
  service_epoch: Int,
) -> Result(store.CommitResultResult, store.StoreError) {
  case state.store_worker {
    Some(sw) ->
      store_worker_commit_result(
        sw,
        bot_id,
        operation_id,
        expected_gen,
        inbox_record,
        record_version,
        record_sha,
        response_chunks,
        worker_id,
        service_epoch,
        5000,
      )
    None ->
      store.commit_result(
        state.config.storage_config,
        bot_id,
        operation_id,
        expected_gen,
        inbox_record,
        record_version,
        record_sha,
        response_chunks,
        worker_id,
        service_epoch,
      )
  }
}

fn svc_commit_sending(
  state: ServiceState,
  bot_id: Int,
  operation_id: String,
  expected_gen: Int,
  inbox_record: ledger.InboxRecord,
  record_version: Int,
  record_sha: String,
  chunk: ledger.OutboxChunk,
  chunk_version: Int,
  chunk_sha: String,
  worker_id: String,
  service_epoch: Int,
) -> Result(#(codec.Receipt, ledger.OutboxChunk), store.StoreError) {
  case state.store_worker {
    Some(sw) ->
      store_worker_commit_sending(
        sw,
        bot_id,
        operation_id,
        expected_gen,
        inbox_record,
        record_version,
        record_sha,
        chunk,
        chunk_version,
        chunk_sha,
        worker_id,
        service_epoch,
        5000,
      )
    None ->
      store.commit_sending(
        state.config.storage_config,
        bot_id,
        operation_id,
        expected_gen,
        inbox_record,
        record_version,
        record_sha,
        chunk,
        chunk_version,
        chunk_sha,
        worker_id,
        service_epoch,
      )
  }
}

fn svc_commit_outcome(
  state: ServiceState,
  bot_id: Int,
  operation_id: String,
  expected_gen: Int,
  chunk: ledger.OutboxChunk,
  chunk_version: Int,
  chunk_sha: String,
  outcome: ledger.OutboxStatus,
) -> Result(#(codec.Receipt, ledger.OutboxChunk), store.StoreError) {
  case state.store_worker {
    Some(sw) ->
      store_worker_commit_outcome(
        sw,
        bot_id,
        operation_id,
        expected_gen,
        chunk,
        chunk_version,
        chunk_sha,
        outcome,
        5000,
      )
    None ->
      store.commit_outcome(
        state.config.storage_config,
        bot_id,
        operation_id,
        expected_gen,
        chunk,
        chunk_version,
        chunk_sha,
        outcome,
      )
  }
}

fn svc_commit_task_completion(
  state: ServiceState,
  bot_id: Int,
  operation_id: String,
  expected_gen: Int,
  inbox_record: ledger.InboxRecord,
  record_version: Int,
  record_sha: String,
  delivered_chunks: List(ledger.OutboxChunk),
) -> Result(#(codec.Receipt, ledger.InboxRecord), store.StoreError) {
  case state.store_worker {
    Some(sw) ->
      store_worker_commit_task_completion(
        sw,
        bot_id,
        operation_id,
        expected_gen,
        inbox_record,
        record_version,
        record_sha,
        delivered_chunks,
        5000,
      )
    None ->
      store.commit_task_completion(
        state.config.storage_config,
        bot_id,
        operation_id,
        expected_gen,
        inbox_record,
        record_version,
        record_sha,
        delivered_chunks,
      )
  }
}

// -----------------------------------------------------------------------------
// Polling Loop Step
// -----------------------------------------------------------------------------

pub fn poll_cycle(
  state: ServiceState,
  now_us: Int,
) -> Result(#(ServiceState, ServiceStepResult), ServiceError) {
  // Gate 1: In-Memory Writer Gate & Pending Operation Check
  case state.pending_operation {
    Some(_) ->
      Error(ServiceError(
        state,
        "service_writer_held: pending_unreconciled_operation_in_state",
      ))
    None ->
      case lifecycle.evaluate_writer_gate(state.writer_state) {
        Error(err) -> Error(ServiceError(state, err))
        Ok(Nil) -> {
          // Gate 2: Authority Lease (Verified canonical claim)
          case verify_authority(state, now_us) {
            Error(err) -> Error(ServiceError(state, err))
            Ok(_lease) -> {
              // Gate 3: Single Poll Flight
              case state.in_flight_poll {
                True -> Ok(#(state, PollSkipped("poll_already_in_flight")))
                False -> {
                  let state_in_flight =
                    ServiceState(..state, in_flight_poll: True)

                  // HTTP getUpdates
                  let poll_res =
                    svc_poll_updates(
                      state,
                      state.watermark.last_committed_offset,
                      state.config.poll_limit,
                      state.config.poll_timeout_s,
                    )

                  case poll_res {
                    Error(err) -> {
                      let next_writer_state = case err {
                        "http_poll_network_error: cleanup_unknown"
                        | "poller_worker_timeout"
                        | "poller_worker_down" ->
                          lifecycle.ServiceWriterHold(
                            "poll_cleanup_unconfirmed: " <> err,
                          )
                        _ -> state_in_flight.writer_state
                      }
                      let state_idle =
                        ServiceState(
                          ..state_in_flight,
                          in_flight_poll: False,
                          writer_state: next_writer_state,
                        )
                      Error(ServiceError(
                        state_idle,
                        "http_poll_updates_failed: " <> err,
                      ))
                    }
                    Ok([]) -> {
                      let state_idle =
                        ServiceState(..state_in_flight, in_flight_poll: False)
                      Ok(#(state_idle, PollEmpty))
                    }
                    Ok(raw_updates) -> {
                      // Recheck Authority after HTTP getUpdates wait, before any DB effect
                      let fresh_now_us = ffi_system_now_utc_us()
                      let effective_now_us = int.max(now_us, fresh_now_us)
                      case verify_authority(state, effective_now_us) {
                        Error(auth_err) -> {
                          let state_idle =
                            ServiceState(
                              ..state_in_flight,
                              in_flight_poll: False,
                            )
                          Error(ServiceError(
                            state_idle,
                            "authority_expired_after_http_poll: " <> auth_err,
                          ))
                        }
                        Ok(_witness2) -> {
                          // Gate 4: Evaluate Ingress & Allowlist
                          let allowlist =
                            guard.Allowlist(
                              bot_id: state.config.bot_id,
                              allowed_pairs: state.config.allowed_pairs,
                            )
                          let verdicts =
                            list.map(raw_updates, fn(u) {
                              guard.evaluate_update(u, allowlist)
                            })

                          let op_id = "poll-" <> int.to_string(effective_now_us)
                          let now_ms = effective_now_us / 1000

                          case
                            svc_read_keys(state, [
                              codec.watermark_key(),
                            ])
                          {
                            Error(err) -> {
                              let state_idle =
                                ServiceState(
                                  ..state_in_flight,
                                  in_flight_poll: False,
                                )
                              Error(ServiceError(
                                state_idle,
                                "store_read_current_generation_failed: "
                                  <> string.inspect(err),
                              ))
                            }
                            Ok(#(current_gen, _)) -> {
                              let fresh_now_us_pre_prefix =
                                ffi_system_now_utc_us()
                              let effective_pre_prefix_us =
                                int.max(now_us, fresh_now_us_pre_prefix)
                              case
                                verify_authority(state, effective_pre_prefix_us)
                              {
                                Error(auth_err) -> {
                                  let state_idle =
                                    ServiceState(
                                      ..state_in_flight,
                                      in_flight_poll: False,
                                    )
                                  Error(ServiceError(
                                    state_idle,
                                    "authority_expired_before_commit_prefix: "
                                      <> auth_err,
                                  ))
                                }
                                Ok(_) -> {
                                  // Storage Commit Prefix
                                  let commit_res =
                                    svc_commit_prefix(
                                      state,
                                      state.config.bot_id,
                                      op_id,
                                      current_gen,
                                      state.watermark,
                                      state.watermark_version,
                                      state.watermark_sha,
                                      verdicts,
                                      now_ms,
                                    )

                                  case commit_res {
                                    Error(store.StoreUncertainApply(pending)) -> {
                                      let state_held =
                                        ServiceState(
                                          ..state_in_flight,
                                          in_flight_poll: False,
                                          pending_operation: Some(pending),
                                          writer_state: lifecycle.ServiceWriterHold(
                                            "store_uncertain_apply_pending",
                                          ),
                                        )
                                      Error(ServiceError(
                                        state_held,
                                        "store_uncertain_apply_pending",
                                      ))
                                    }
                                    Error(err) -> {
                                      let state_idle =
                                        ServiceState(
                                          ..state_in_flight,
                                          in_flight_poll: False,
                                        )
                                      Error(ServiceError(
                                        state_idle,
                                        "store_commit_prefix_failed: "
                                          <> string.inspect(err),
                                      ))
                                    }
                                    Ok(prefix_outcome) -> {
                                      // Refresh watermark for exact CAS version and SHA
                                      case svc_read_watermark(state) {
                                        Error(err) -> {
                                          let state_idle =
                                            ServiceState(
                                              ..state_in_flight,
                                              in_flight_poll: False,
                                            )
                                          Error(ServiceError(
                                            state_idle,
                                            "store_read_watermark_failed: "
                                              <> string.inspect(err),
                                          ))
                                        }
                                        Ok(#(
                                          fresh_wm,
                                          fresh_wm_ver,
                                          fresh_wm_sha,
                                        )) -> {
                                          let next_state =
                                            ServiceState(
                                              ..state_in_flight,
                                              watermark: fresh_wm,
                                              watermark_version: fresh_wm_ver,
                                              watermark_sha: fresh_wm_sha,
                                              expected_generation: prefix_outcome.receipt.generation,
                                              in_flight_poll: False,
                                            )
                                          Ok(#(
                                            next_state,
                                            PollCommitted(
                                              count: list.length(
                                                prefix_outcome.admitted_records,
                                              ),
                                              new_watermark: fresh_wm.last_committed_offset,
                                            ),
                                          ))
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
      }
  }
}

// -----------------------------------------------------------------------------
// Delivery Pipeline Step
// -----------------------------------------------------------------------------

pub fn deliver_chunk(
  state: ServiceState,
  inbox_record: ledger.InboxRecord,
  inbox_version: Int,
  inbox_sha: String,
  chunk: ledger.OutboxChunk,
  chunk_version: Int,
  chunk_sha: String,
  now_us: Int,
) -> Result(#(ServiceState, ServiceStepResult), ServiceError) {
  // Gate 1: In-Memory Writer Gate & Pending Operation Check
  case state.pending_operation {
    Some(_) ->
      Error(ServiceError(
        state,
        "service_writer_held: pending_unreconciled_operation_in_state",
      ))
    None ->
      case lifecycle.evaluate_writer_gate(state.writer_state) {
        Error(err) -> Error(ServiceError(state, err))
        Ok(Nil) -> {
          // Gate 2: Authority Lease
          case verify_authority(state, now_us) {
            Error(err) -> Error(ServiceError(state, err))
            Ok(_lease) -> {
              // Step 1: Pre-commit OutboxSending
              let op_send =
                "send-"
                <> chunk.request_id
                <> "-"
                <> int.to_string(chunk.chunk_index)
                <> "-"
                <> int.to_string(now_us)

              case
                svc_read_keys(state, [
                  codec.watermark_key(),
                ])
              {
                Error(err) ->
                  Error(ServiceError(
                    state,
                    "store_read_current_generation_failed: "
                      <> string.inspect(err),
                  ))
                Ok(#(current_gen, _)) -> {
                  let pre_commit_now = ffi_system_now_utc_us()
                  case verify_authority(state, pre_commit_now) {
                    Error(err) ->
                      Error(ServiceError(
                        state,
                        "authority_expired_before_commit_sending: " <> err,
                      ))
                    Ok(_) -> {
                      let send_res =
                        svc_commit_sending(
                          state,
                          state.config.bot_id,
                          op_send,
                          current_gen,
                          inbox_record,
                          inbox_version,
                          inbox_sha,
                          chunk,
                          chunk_version,
                          chunk_sha,
                          state.config.worker_id,
                          state.config.service_epoch,
                        )

                      case send_res {
                        Error(store.StoreUncertainApply(pending)) -> {
                          let state_held =
                            ServiceState(
                              ..state,
                              writer_state: lifecycle.ServiceWriterHold(
                                "store_uncertain_apply_pending",
                              ),
                              pending_operation: Some(pending),
                            )
                          Error(ServiceError(
                            state_held,
                            "store_uncertain_apply_pending",
                          ))
                        }
                        Error(err) ->
                          Error(ServiceError(
                            state,
                            "store_commit_sending_failed: "
                              <> string.inspect(err),
                          ))
                        Ok(#(send_receipt, sending_chunk)) -> {
                          let state_sending =
                            ServiceState(
                              ..state,
                              expected_generation: send_receipt.generation,
                            )

                          let sending_chunk_version = chunk_version + 1
                          let sending_chunk_sha =
                            files.digest(codec.encode_chunk_value(sending_chunk))

                          // Step 2: Bounded HTTP POST with fresh authority fence
                          let pre_send_now = ffi_system_now_utc_us()
                          case verify_authority(state_sending, pre_send_now) {
                            Error(auth_err) ->
                              Error(ServiceError(
                                state_sending,
                                "authority_expired_before_http_send: "
                                  <> auth_err,
                              ))
                            Ok(_) -> {
                              let delivery_outcome =
                                http_client.send_message(
                                  state.config.http_config,
                                  chunk.chat_id,
                                  chunk.payload,
                                  None,
                                )

                              // Recheck Authority after HTTP send wait, before outcome commit
                              let fresh_now_us = ffi_system_now_utc_us()
                              let post_now_us = int.max(now_us, fresh_now_us)
                              case
                                verify_authority(state_sending, post_now_us)
                              {
                                Error(auth_err) ->
                                  Error(ServiceError(
                                    state_sending,
                                    "authority_expired_after_http_send: "
                                      <> auth_err,
                                  ))
                                Ok(_witness2) -> {
                                  // Step 3: Map Outcome & Commit to SQLite
                                  let op_outcome =
                                    "outcome-"
                                    <> chunk.request_id
                                    <> "-"
                                    <> int.to_string(chunk.chunk_index)
                                    <> "-"
                                    <> int.to_string(post_now_us)

                                  case delivery_outcome {
                                    http_client.Delivered(msg_id, _) -> {
                                      let outcome_res =
                                        svc_commit_outcome(
                                          state_sending,
                                          state.config.bot_id,
                                          op_outcome,
                                          state_sending.expected_generation,
                                          sending_chunk,
                                          sending_chunk_version,
                                          sending_chunk_sha,
                                          ledger.OutboxDelivered(msg_id),
                                        )
                                      case outcome_res {
                                        Error(store.StoreUncertainApply(pending)) -> {
                                          let state_held =
                                            ServiceState(
                                              ..state_sending,
                                              writer_state: lifecycle.ServiceWriterHold(
                                                "store_uncertain_apply_pending",
                                              ),
                                              pending_operation: Some(pending),
                                            )
                                          Error(ServiceError(
                                            state_held,
                                            "store_uncertain_apply_pending",
                                          ))
                                        }
                                        Error(err) ->
                                          Error(ServiceError(
                                            state_sending,
                                            "store_commit_outcome_delivered_failed: "
                                              <> string.inspect(err),
                                          ))
                                        Ok(#(outcome_receipt, _delivered_chunk)) -> {
                                          let next_state =
                                            ServiceState(
                                              ..state_sending,
                                              expected_generation: outcome_receipt.generation,
                                            )
                                          Ok(#(
                                            next_state,
                                            DeliveryStepSuccess(
                                              chunk.request_id,
                                              msg_id,
                                            ),
                                          ))
                                        }
                                      }
                                    }

                                    http_client.ProvenRejection(code, desc) -> {
                                      let err_str =
                                        "http_rejected_"
                                        <> int.to_string(code)
                                        <> ": "
                                        <> desc
                                      let outcome_res =
                                        svc_commit_outcome(
                                          state_sending,
                                          state.config.bot_id,
                                          op_outcome,
                                          state_sending.expected_generation,
                                          sending_chunk,
                                          sending_chunk_version,
                                          sending_chunk_sha,
                                          ledger.OutboxFailed(err_str),
                                        )
                                      case outcome_res {
                                        Error(store.StoreUncertainApply(pending)) -> {
                                          let state_held =
                                            ServiceState(
                                              ..state_sending,
                                              writer_state: lifecycle.ServiceWriterHold(
                                                "store_uncertain_apply_pending",
                                              ),
                                              pending_operation: Some(pending),
                                            )
                                          Error(ServiceError(
                                            state_held,
                                            "store_uncertain_apply_pending",
                                          ))
                                        }
                                        Error(err) ->
                                          Error(ServiceError(
                                            state_sending,
                                            "store_commit_outcome_failed_failed: "
                                              <> string.inspect(err),
                                          ))
                                        Ok(#(outcome_receipt, _failed_chunk)) -> {
                                          let next_state =
                                            ServiceState(
                                              ..state_sending,
                                              expected_generation: outcome_receipt.generation,
                                            )
                                          Ok(#(
                                            next_state,
                                            DeliveryStepFailed(
                                              chunk.request_id,
                                              err_str,
                                            ),
                                          ))
                                        }
                                      }
                                    }

                                    http_client.AmbiguousOutcome(reason) -> {
                                      let outcome_res =
                                        svc_commit_outcome(
                                          state_sending,
                                          state.config.bot_id,
                                          op_outcome,
                                          state_sending.expected_generation,
                                          sending_chunk,
                                          sending_chunk_version,
                                          sending_chunk_sha,
                                          ledger.OutboxUncertain(reason),
                                        )
                                      case outcome_res {
                                        Error(store.StoreUncertainApply(pending)) -> {
                                          let state_held =
                                            ServiceState(
                                              ..state_sending,
                                              writer_state: lifecycle.ServiceWriterHold(
                                                "store_uncertain_apply_pending",
                                              ),
                                              pending_operation: Some(pending),
                                            )
                                          Error(ServiceError(
                                            state_held,
                                            "store_uncertain_apply_pending",
                                          ))
                                        }
                                        Error(err) ->
                                          Error(ServiceError(
                                            state_sending,
                                            "store_commit_outcome_uncertain_failed: "
                                              <> string.inspect(err),
                                          ))
                                        Ok(#(outcome_receipt, _uncertain_chunk)) -> {
                                          let next_state =
                                            ServiceState(
                                              ..state_sending,
                                              expected_generation: outcome_receipt.generation,
                                            )
                                          Ok(#(
                                            next_state,
                                            DeliveryStepUncertain(
                                              chunk.request_id,
                                              reason,
                                            ),
                                          ))
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
      }
  }
}

pub fn dispatch_cycle(
  state: ServiceState,
  now_us: Int,
) -> Result(#(ServiceState, ServiceStepResult), ServiceError) {
  case state.authority_revoked {
    True -> Error(ServiceError(state, "authority_lease_revoked"))
    False -> {
      case state.pending_operation {
        Some(_) ->
          Error(ServiceError(
            state,
            "service_writer_held: pending_unreconciled_operation_in_state",
          ))
        None -> {
          case lifecycle.evaluate_writer_gate(state.writer_state) {
            Error(err) -> Error(ServiceError(state, err))
            Ok(Nil) -> {
              case verify_authority(state, now_us) {
                Error(err) -> Error(ServiceError(state, err))
                Ok(_) -> {
                  case
                    scan_all_inbox_records(
                      state.config.storage_config,
                      None,
                      None,
                      0,
                      [],
                    )
                  {
                    Error(err) ->
                      Error(ServiceError(state, "read_inbox_failed: " <> err))
                    Ok(#(cur_gen, inbox_rows)) -> {
                      let pending_rows =
                        list.filter(inbox_rows, fn(row) {
                          let #(rec, _, _) = row
                          case rec.status {
                            ledger.InboxPending -> True
                            _ -> False
                          }
                        })
                      case pending_rows {
                        [] ->
                          Ok(#(
                            state,
                            DispatchCycleResult(
                              processed_count: 0,
                              delivered_count: 0,
                            ),
                          ))
                        [#(inbox_rec, inbox_ver, inbox_sha), ..] -> {
                          execute_guarded_dispatch(
                            state,
                            cur_gen,
                            inbox_rec,
                            inbox_ver,
                            inbox_sha,
                            now_us,
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
      }
    }
  }
}

fn execute_guarded_dispatch(
  state: ServiceState,
  gen0: Int,
  inbox_rec: ledger.InboxRecord,
  inbox_ver: Int,
  inbox_sha: String,
  now_us: Int,
) -> Result(#(ServiceState, ServiceStepResult), ServiceError) {
  let pre_claim_now = ffi_system_now_utc_us()
  let effective_now = int.max(now_us, pre_claim_now)
  case verify_authority(state, effective_now) {
    Error(err) ->
      Error(ServiceError(
        state,
        "authority_expired_before_claim_task_processing: " <> err,
      ))
    Ok(_) -> {
      let op_claim_id = "op-claim-" <> inbox_rec.request_id
      case
        svc_claim_task_processing(
          state,
          state.config.bot_id,
          op_claim_id,
          gen0,
          inbox_rec,
          inbox_ver,
          inbox_sha,
          state.config.worker_id,
          state.config.service_epoch,
          effective_now,
        )
      {
        Error(store.StoreUncertainApply(pending)) -> {
          let state_held =
            ServiceState(
              ..state,
              pending_operation: Some(pending),
              writer_state: lifecycle.ServiceWriterHold(
                "store_uncertain_apply_pending",
              ),
            )
          Error(ServiceError(state_held, "store_uncertain_apply_pending"))
        }
        Error(err) ->
          Error(ServiceError(
            state,
            "claim_task_processing_failed: " <> string.inspect(err),
          ))
        Ok(#(claim_rcpt, processing_rec)) -> {
          let gen1 = claim_rcpt.generation
          let proc_ver = inbox_ver + 1
          let proc_sha = files.digest(codec.encode_inbox_record(processing_rec))

          case specialized_dispatch(state, inbox_rec.request_id) {
            MemoryDispatch -> execute_memory_dispatch(
              ServiceState(..state, expected_generation: gen1),
              processing_rec, proc_ver, proc_sha,
            )
            ConversationDispatch -> execute_conversation_dispatch(
              ServiceState(..state, expected_generation: gen1),
              processing_rec, proc_ver, proc_sha,
            )
            RegularDispatch -> {
          let #(response_payload, callback_query_id) = case
            svc_read_keys(state, [
              codec.input_key(inbox_rec.request_id),
            ])
          {
            Ok(#(_, [row])) -> {
              case codec.decode_row_value(row) {
                Ok(raw_json) -> {
                  case codec.decode_input_verdict(raw_json) {
                    Ok(#(
                      _,
                      _,
                      _,
                      guard.AcceptedEnvelope(
                        raw_text: txt,
                        directive: dir,
                        callback_query_id: cb_id,
                        ..,
                      ),
                    )) -> {
                      let payload = case dir {
                        guard.DirectReadTool("query_system_health") -> {
                          let local = operational_status.LocalState(
                            observed_at_us: ffi_system_now_utc_us(),
                            service_epoch: state.config.service_epoch,
                            store_generation: gen1,
                            next_update_offset: state.watermark.last_committed_offset,
                            pending_recovery: option.is_some(state.pending_operation),
                            conversation_configured: state.config.conversation != ConversationDisabled,
                          )
                          case operational_status.observe(local, operational_status.live_io(),
                            fn() { conversation_authorize(state) }, 6000) {
                            Ok(reply) -> reply
                            Error(_) -> json.object([
                              #("status", json.string("observation_failed")),
                              #("error", json.string("Operational status could not be observed within current authority and budget.")),
                            ]) |> json.to_string
                          }
                        }
                        guard.DirectReadTool("query_doctor") ->
                          doctor_projection.project()
                          |> doctor_projection.to_json()
                        guard.DirectReadTool("query_saplan") -> {
                          let req = command_observer_request(state.config)
                          case obs_policy.observe(req) {
                            Ok(obs) ->
                              case bit_array.to_string(obs.payload) {
                                Ok(payload_str) -> payload_str
                                Error(_) ->
                                  json.object([
                                    #(
                                      "error",
                                      json.string("observer_payload_not_utf8"),
                                    ),
                                  ])
                                  |> json.to_string
                              }
                            Error(err) ->
                              json.object([
                                #(
                                  "error",
                                  json.string("observer_failed: " <> err),
                                ),
                              ])
                              |> json.to_string
                          }
                        }
                        guard.PreservedDirective("/task", [task_id]) -> {
                          case task_command.observe_task(command_observer_request(state.config), task_id) {
                            Ok(reply) -> reply
                            Error(reason) -> json.object([
                              #("status", json.string("observation_failed")),
                              #("error", json.string(reason)),
                            ]) |> json.to_string
                          }
                        }
                        guard.PreservedDirective("/tool_help", []) -> tool_command.help()
                        guard.PreservedDirective(name, _) -> {
                          let reference = case commands.parse(txt) {
                            Ok(invocation) -> commands.reference_reply(invocation)
                            Error(_) -> Error(Nil)
                          }
                          case reference {
                            Ok(reply) -> reply
                            Error(_) -> json.object([
                              #("status", json.string("backend_unavailable")),
                              #("directive", json.string(name)),
                              #("request_id", json.string(inbox_rec.request_id)),
                              #("error", json.string("Command adapter is not integrated; no action executed.")),
                            ]) |> json.to_string
                          }
                        }
                        guard.DeniedMutation(tool, reason) ->
                          json.object([
                            #(
                              "error",
                              json.string(
                                "denied_mutation: "
                                <> tool
                                <> " ("
                                <> reason
                                <> ")",
                              ),
                            ),
                          ])
                          |> json.to_string
                        guard.UnknownDirective(name) ->
                          json.object([
                            #(
                              "error",
                              json.string("unknown_directive_refused: " <> name),
                            ),
                          ])
                          |> json.to_string
                        _ ->
                          json.object([
                            #("observation", json.string(txt)),
                            #("request_id", json.string(inbox_rec.request_id)),
                          ])
                          |> json.to_string
                      }
                      #(payload, cb_id)
                    }
                    _ -> #(
                      "Observation: request_id="
                        <> inbox_rec.request_id
                        <> ", message_id="
                        <> int.to_string(inbox_rec.message_id),
                      None,
                    )
                  }
                }
                _ -> #(
                  "Observation: request_id="
                    <> inbox_rec.request_id
                    <> ", message_id="
                    <> int.to_string(inbox_rec.message_id),
                  None,
                )
              }
            }
            _ -> #(
              "Observation: request_id="
                <> inbox_rec.request_id
                <> ", message_id="
                <> int.to_string(inbox_rec.message_id),
              None,
            )
          }

          // AUTO-01: Re-verify authority before effect commits (after tool observation)
          let pre_res_now = ffi_system_now_utc_us()
          case verify_authority(state, pre_res_now) {
            Error(err) ->
              Error(ServiceError(
                state,
                "authority_expired_before_commit_result: " <> err,
              ))
            Ok(_) -> {
              let op_result_id = "op-result-" <> inbox_rec.request_id
              let chunk_payloads = chunk_payload_utf8(response_payload)
              case
                svc_commit_result(
                  state,
                  state.config.bot_id,
                  op_result_id,
                  gen1,
                  processing_rec,
                  proc_ver,
                  proc_sha,
                  chunk_payloads,
                  state.config.worker_id,
                  state.config.service_epoch,
                )
              {
                Error(store.StoreUncertainApply(pending)) -> {
                  let state_held =
                    ServiceState(
                      ..state,
                      pending_operation: Some(pending),
                      writer_state: lifecycle.ServiceWriterHold(
                        "store_uncertain_apply_pending",
                      ),
                    )
                  Error(ServiceError(
                    state_held,
                    "store_uncertain_apply_pending",
                  ))
                }
                Error(err) ->
                  Error(ServiceError(
                    state,
                    "commit_result_failed: " <> string.inspect(err),
                  ))
                Ok(res_result) -> {
                  let gen2 = res_result.receipt.generation
                  let ready_rec = res_result.inbox_record
                  let ready_ver = proc_ver + 1
                  let ready_sha =
                    files.digest(codec.encode_inbox_record(ready_rec))

                  case res_result.chunks {
                    [] ->
                      Error(ServiceError(
                        state,
                        "commit_result_produced_zero_chunks",
                      ))
                    chunks -> {
                      drain_chunks(
                        state,
                        inbox_rec,
                        ready_rec,
                        ready_ver,
                        ready_sha,
                        gen2,
                        chunks,
                        [],
                        callback_query_id,
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
      }
    }
  }
}

fn drain_chunks(
  state: ServiceState,
  inbox_rec: ledger.InboxRecord,
  ready_rec: ledger.InboxRecord,
  ready_ver: Int,
  ready_sha: String,
  cur_gen: Int,
  remaining_chunks: List(ledger.OutboxChunk),
  delivered_acc: List(ledger.OutboxChunk),
  callback_query_id: Option(String),
) -> Result(#(ServiceState, ServiceStepResult), ServiceError) {
  case remaining_chunks {
    [] -> {
      // AUTO-01: Re-verify authority before task completion commit
      let pre_comp_now = ffi_system_now_utc_us()
      case verify_authority(state, pre_comp_now) {
        Error(err) ->
          Error(ServiceError(
            state,
            "authority_expired_before_commit_task_completion: " <> err,
          ))
        Ok(_) -> {
          // AUTO-05: Preserve and answer provider callback query if present.
          let cb_res = case callback_query_id {
            Some(cb_id) ->
              http_client.answer_callback_query(
                state.config.http_config,
                cb_id,
                None,
              )
            None -> Ok(True)
          }
          case cb_res {
            Error(err) ->
              Error(ServiceError(state, "answer_callback_query_failed: " <> err))
            Ok(_) -> {
              let post_cb_now = ffi_system_now_utc_us()
              case verify_authority(state, post_cb_now) {
                Error(err) ->
                  Error(ServiceError(
                    state,
                    "authority_expired_after_callback_answer: " <> err,
                  ))
                Ok(_) -> {
                  let op_complete_id = "op-complete-" <> inbox_rec.request_id
                  case
                    svc_commit_task_completion(
                      state,
                      state.config.bot_id,
                      op_complete_id,
                      cur_gen,
                      ready_rec,
                      ready_ver,
                      ready_sha,
                      list.reverse(delivered_acc),
                    )
                  {
                    Error(store.StoreUncertainApply(pending)) -> {
                      let state_held =
                        ServiceState(
                          ..state,
                          pending_operation: Some(pending),
                          writer_state: lifecycle.ServiceWriterHold(
                            "store_uncertain_apply_pending",
                          ),
                        )
                      Error(ServiceError(
                        state_held,
                        "store_uncertain_apply_pending",
                      ))
                    }
                    Error(err) ->
                      Error(ServiceError(
                        state,
                        "commit_task_completion_failed: " <> string.inspect(err),
                      ))
                    Ok(#(comp_rcpt, _completed_rec)) -> {
                      let final_gen = comp_rcpt.generation
                      let next_state =
                        ServiceState(..state, expected_generation: final_gen)
                      Ok(#(
                        next_state,
                        DispatchCycleResult(
                          processed_count: 1,
                          delivered_count: list.length(delivered_acc),
                        ),
                      ))
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    [chunk, ..rest] -> {
      let chunk_ver = 1
      let chunk_sha = files.digest(codec.encode_chunk_value(chunk))
      let op_sending_id =
        "op-sending-"
        <> inbox_rec.request_id
        <> "-"
        <> int.to_string(chunk.chunk_index)

      // AUTO-01: Re-verify authority before commit_sending
      let pre_send_now = ffi_system_now_utc_us()
      case verify_authority(state, pre_send_now) {
        Error(err) ->
          Error(ServiceError(
            state,
            "authority_expired_before_commit_sending: " <> err,
          ))
        Ok(_) -> {
          case
            svc_commit_sending(
              state,
              state.config.bot_id,
              op_sending_id,
              cur_gen,
              ready_rec,
              ready_ver,
              ready_sha,
              chunk,
              chunk_ver,
              chunk_sha,
              state.config.worker_id,
              state.config.service_epoch,
            )
          {
            Error(store.StoreUncertainApply(pending)) -> {
              let state_held =
                ServiceState(
                  ..state,
                  pending_operation: Some(pending),
                  writer_state: lifecycle.ServiceWriterHold(
                    "store_uncertain_apply_pending",
                  ),
                )
              Error(ServiceError(state_held, "store_uncertain_apply_pending"))
            }
            Error(err) ->
              Error(ServiceError(
                state,
                "commit_sending_failed: " <> string.inspect(err),
              ))
            Ok(#(sending_rcpt, sending_chunk)) -> {
              let gen3 = sending_rcpt.generation
              let chunk_ver2 = chunk_ver + 1
              let chunk_sha2 =
                files.digest(codec.encode_chunk_value(sending_chunk))

              // AUTO-01: Re-verify authority before HTTP send
              let pre_http_now = ffi_system_now_utc_us()
              case verify_authority(state, pre_http_now) {
                Error(err) ->
                  Error(ServiceError(
                    state,
                    "authority_expired_before_http_send: " <> err,
                  ))
                Ok(_) -> {
                  let send_outcome =
                    http_client.send_message(
                      state.config.http_config,
                      inbox_rec.chat_id,
                      chunk.payload,
                      None,
                    )

                  case send_outcome {
                    http_client.Delivered(msg_id, _) -> {
                      let post_send_now = ffi_system_now_utc_us()
                      case verify_authority(state, post_send_now) {
                        Error(err) ->
                          Error(ServiceError(
                            state,
                            "authority_expired_after_http_send: " <> err,
                          ))
                        Ok(_) -> {
                          let op_outcome_id =
                            "op-outcome-"
                            <> inbox_rec.request_id
                            <> "-"
                            <> int.to_string(chunk.chunk_index)
                          case
                            svc_commit_outcome(
                              state,
                              state.config.bot_id,
                              op_outcome_id,
                              gen3,
                              sending_chunk,
                              chunk_ver2,
                              chunk_sha2,
                              ledger.OutboxDelivered(msg_id),
                            )
                          {
                            Error(store.StoreUncertainApply(pending)) -> {
                              let state_held =
                                ServiceState(
                                  ..state,
                                  pending_operation: Some(pending),
                                  writer_state: lifecycle.ServiceWriterHold(
                                    "store_uncertain_apply_pending",
                                  ),
                                )
                              Error(ServiceError(
                                state_held,
                                "store_uncertain_apply_pending",
                              ))
                            }
                            Error(err) ->
                              Error(ServiceError(
                                state,
                                "commit_outcome_failed: " <> string.inspect(err),
                              ))
                            Ok(#(outcome_rcpt, delivered_chunk)) -> {
                              let gen4 = outcome_rcpt.generation
                              let state_updated =
                                ServiceState(..state, expected_generation: gen4)
                              drain_chunks(
                                state_updated,
                                inbox_rec,
                                ready_rec,
                                ready_ver,
                                ready_sha,
                                gen4,
                                rest,
                                [delivered_chunk, ..delivered_acc],
                                callback_query_id,
                              )
                            }
                          }
                        }
                      }
                    }
                    http_client.ProvenRejection(code, desc) -> {
                      let post_send_now = ffi_system_now_utc_us()
                      case verify_authority(state, post_send_now) {
                        Error(err) ->
                          Error(ServiceError(
                            state,
                            "authority_expired_before_outcome_commit: " <> err,
                          ))
                        Ok(_) -> {
                          let err = int.to_string(code) <> ": " <> desc
                          let op_outcome_id =
                            "op-outcome-fail-"
                            <> inbox_rec.request_id
                            <> "-"
                            <> int.to_string(chunk.chunk_index)
                          case
                            svc_commit_outcome(
                              state,
                              state.config.bot_id,
                              op_outcome_id,
                              gen3,
                              sending_chunk,
                              chunk_ver2,
                              chunk_sha2,
                              ledger.OutboxFailed(err),
                            )
                          {
                            Error(store.StoreUncertainApply(pending)) -> {
                              let state_held =
                                ServiceState(
                                  ..state,
                                  pending_operation: Some(pending),
                                  writer_state: lifecycle.ServiceWriterHold(
                                    "store_uncertain_apply_pending",
                                  ),
                                )
                              Error(ServiceError(
                                state_held,
                                "store_uncertain_apply_pending",
                              ))
                            }
                            Error(commit_err) ->
                              Error(ServiceError(
                                state,
                                "commit_outcome_failed: "
                                  <> string.inspect(commit_err),
                              ))
                            Ok(#(outcome_rcpt, _failed_chunk)) -> {
                              let gen4 = outcome_rcpt.generation
                              let state_updated =
                                ServiceState(..state, expected_generation: gen4)
                              Error(ServiceError(
                                state_updated,
                                "http_delivery_rejected: " <> err,
                              ))
                            }
                          }
                        }
                      }
                    }
                    http_client.AmbiguousOutcome(err) -> {
                      let post_send_now = ffi_system_now_utc_us()
                      case verify_authority(state, post_send_now) {
                        Error(auth_err) ->
                          Error(ServiceError(
                            state,
                            "authority_expired_before_outcome_commit: "
                              <> auth_err,
                          ))
                        Ok(_) -> {
                          let op_outcome_id =
                            "op-outcome-unc-"
                            <> inbox_rec.request_id
                            <> "-"
                            <> int.to_string(chunk.chunk_index)
                          case
                            svc_commit_outcome(
                              state,
                              state.config.bot_id,
                              op_outcome_id,
                              gen3,
                              sending_chunk,
                              chunk_ver2,
                              chunk_sha2,
                              ledger.OutboxUncertain(err),
                            )
                          {
                            Error(store.StoreUncertainApply(pending)) -> {
                              let state_held =
                                ServiceState(
                                  ..state,
                                  pending_operation: Some(pending),
                                  writer_state: lifecycle.ServiceWriterHold(
                                    "store_uncertain_apply_pending",
                                  ),
                                )
                              Error(ServiceError(
                                state_held,
                                "store_uncertain_apply_pending",
                              ))
                            }
                            Error(commit_err) ->
                              Error(ServiceError(
                                state,
                                "commit_outcome_failed: "
                                  <> string.inspect(commit_err),
                              ))
                            Ok(#(outcome_rcpt, _unc_chunk)) -> {
                              let gen4 = outcome_rcpt.generation
                              let state_updated =
                                ServiceState(..state, expected_generation: gen4)
                              Error(ServiceError(
                                state_updated,
                                "http_delivery_uncertain: " <> err,
                              ))
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

// -----------------------------------------------------------------------------
// Supervised OTP Actor API
// -----------------------------------------------------------------------------

pub type ServiceMessage {
  SetAuthority(AuthorityLease)
  ManagedAuthorityRenewed(AuthorityLease)
  ManagedAuthorityLost
  RevokeAuthority
  PollCycle(now_us: Int, reply_to: Subject(Result(ServiceStepResult, String)))
  AutomaticDispatchTick(
    now_us: Int,
    reply_to: Subject(Result(ServiceStepResult, String)),
  )
  PollWorkerFinished(
    pid: Pid,
    outcome: Result(#(ServiceState, ServiceStepResult), ServiceError),
    reply_to: Subject(Result(ServiceStepResult, String)),
  )
  DispatchWorkerFinished(
    pid: Pid,
    outcome: Result(#(ServiceState, ServiceStepResult), ServiceError),
    reply_to: Subject(Result(ServiceStepResult, String)),
  )
  DeliverChunk(
    inbox_record: ledger.InboxRecord,
    inbox_version: Int,
    inbox_sha: String,
    chunk: ledger.OutboxChunk,
    chunk_version: Int,
    chunk_sha: String,
    now_us: Int,
    reply_to: Subject(Result(ServiceStepResult, String)),
  )
  DeliveryWorkerFinished(
    pid: Pid,
    new_generation: Option(Int),
    new_writer_state: Option(lifecycle.ServiceWriterState),
    pending_operation: Option(store.PendingOperation),
  )
  WorkerDown(process.Down)
  GetState(reply_to: Subject(ServiceState))
  GetManagedStartupState(reply_to: Subject(Result(ServiceState, String)))
  GetPendingOperation(reply_to: Subject(Option(store.PendingOperation)))
  Stop
}

fn spawn_delivery_worker(
  state: ServiceState,
  task: DeliveryTask,
) -> ServiceState {
  let self_sub = state.self_subject
  let worker_pid =
    process.spawn_unlinked(fn() {
      let outcome =
        deliver_chunk(
          state,
          task.inbox_record,
          task.inbox_version,
          task.inbox_sha,
          task.chunk,
          task.chunk_version,
          task.chunk_sha,
          task.now_us,
        )
      case outcome {
        Ok(#(next_state, res)) -> {
          process.send(task.reply_to, Ok(res))
          case self_sub {
            Some(sub) ->
              process.send(
                sub,
                DeliveryWorkerFinished(
                  process.self(),
                  Some(next_state.expected_generation),
                  Some(next_state.writer_state),
                  next_state.pending_operation,
                ),
              )
            None -> Nil
          }
        }
        Error(ServiceError(failed_state, err)) -> {
          process.send(task.reply_to, Error(err))
          case self_sub {
            Some(sub) ->
              process.send(
                sub,
                DeliveryWorkerFinished(
                  process.self(),
                  None,
                  Some(failed_state.writer_state),
                  failed_state.pending_operation,
                ),
              )
            None -> Nil
          }
        }
      }
    })
  let _mon = process.monitor(worker_pid)
  ServiceState(..state, in_flight_workers: [worker_pid])
}

@external(erlang, "telegram_service_ffi", "ensure_worker_scope")
fn ensure_worker_scope() -> reference.Reference

@external(erlang, "telegram_service_ffi", "set_worker_subject")
pub fn ffi_set_worker_subject(scope: a, role: String, subject: b) -> Nil

@external(erlang, "telegram_service_ffi", "get_worker_subject")
pub fn ffi_get_worker_subject(scope: a, role: String) -> Result(b, Nil)

@external(erlang, "telegram_service_ffi", "clear_worker_subjects")
pub fn ffi_clear_worker_subjects(scope: a) -> Nil

/// Compatibility view of the fully supervised service. The returned PID owns
/// the four-role tree; data is the coordinator subject. No fallback children.
pub fn start_actor(
  config: ServiceConfiguration,
  cleanup_receipt: Option(lifecycle.UnitCleanupReceipt),
) -> Result(actor.Started(Subject(ServiceMessage)), String) {
  use svc <- result.try(start_supervised_service(config, cleanup_receipt))
  Ok(actor.Started(pid: svc.supervisor_pid, data: svc.actor_subject))
}

fn start_actor_scoped(
  config: ServiceConfiguration,
  cleanup_receipt: Option(lifecycle.UnitCleanupReceipt),
  scope: reference.Reference,
) -> Result(actor.Started(Subject(ServiceMessage)), String) {
  case init_service(config, cleanup_receipt) {
    Error(err) -> Error("service_init_failed: " <> err)
    Ok(#(initial_state, _recovery_summary)) -> {
      use auth_subj <- result.try(
        ffi_get_worker_subject(scope, "authority")
        |> result.map_error(fn(_) { "supervised_authority_subject_missing" }),
      )
      use store_subj <- result.try(
        ffi_get_worker_subject(scope, "store")
        |> result.map_error(fn(_) { "supervised_store_subject_missing" }),
      )
      use poller_subj <- result.try(
        ffi_get_worker_subject(scope, "poller")
        |> result.map_error(fn(_) { "supervised_poller_subject_missing" }),
      )

      actor.new_with_initialiser(5000, fn(subject) {
        ffi_set_worker_subject(scope, "coordinator", subject)
        let state =
          ServiceState(
            ..initial_state,
            self_subject: Some(subject),
            authority_worker: Some(auth_subj),
            store_worker: Some(store_subj),
            poller_worker: Some(poller_subj),
          )
        let selector =
          process.new_selector()
          |> process.select(for: subject)
          |> process.select_monitors(WorkerDown)
        actor.initialised(state)
        |> actor.selecting(selector)
        |> actor.returning(subject)
        |> Ok
      })
      |> actor.on_message(handle_message)
      |> actor.start()
      |> result.map_error(fn(err) {
        "service_actor_start_failed: " <> string.inspect(err)
      })
    }
  }
}

pub type SupervisedService {
  SupervisedService(
    supervisor: static_supervisor.Supervisor,
    actor_subject: Subject(ServiceMessage),
    authority_worker: Subject(AuthorityWorkerMessage),
    store_worker: Subject(StoreWorkerMessage),
    poller_worker: Subject(PollerWorkerMessage),
    subject_scope: reference.Reference,
    supervisor_pid: Pid,
    configuration: ServiceConfiguration,
  )
}

pub type AuthorityWorkerMessage {
  AuthorityPing(reply_to: Subject(String))
  EnableManagedAuthority(coordinator: Subject(ServiceMessage), ttl_us: Int, interval_ms: Int, reply_to: Subject(Result(Nil, String)))
  MaintenanceTick(sequence: Int)
  VerifyAuthority(
    now_us: Int,
    reply_to: Subject(Result(AuthorityWitness, String)),
  )
  SetAuthorityLease(AuthorityLease)
  RevokeAuthorityLease
  GetAuthorityStatus(reply_to: Subject(#(Option(AuthorityLease), Bool)))
}

pub type ManagedAuthorityMaintenance {
  ManagedAuthorityMaintenance(coordinator: Subject(ServiceMessage), ttl_us: Int, interval_ms: Int, lease_id: String, sequence: Int)
}

pub type AuthorityWorkerState {
  AuthorityWorkerState(
    config: ServiceConfiguration,
    lease: Option(AuthorityLease),
    revoked: Bool,
    self: Subject(AuthorityWorkerMessage),
    managed: Option(ManagedAuthorityMaintenance),
  )
}

fn handle_authority_worker_message(
  state: AuthorityWorkerState,
  msg: AuthorityWorkerMessage,
) -> actor.Next(AuthorityWorkerState, AuthorityWorkerMessage) {
  case msg {
    AuthorityPing(reply_to) -> {
      process.send(reply_to, "pong")
      actor.continue(state)
    }
    SetAuthorityLease(lease) -> {
      case state.managed {
        Some(_) -> actor.continue(state)
        None -> actor.continue(AuthorityWorkerState(..state, lease: Some(lease), revoked: False))
      }
    }
    RevokeAuthorityLease -> actor.continue(suspend_managed_authority(state))
    EnableManagedAuthority(coordinator, ttl_us, interval_ms, reply_to) -> {
      let valid = case state.config.authority_paths {
        CanonicalProductionPaths -> ttl_us == 30_000_000 && interval_ms == 10_000
        IsolatedTestPaths(_, _) -> ttl_us >= 1_000_000 && ttl_us <= 30_000_000 && interval_ms >= 20 && interval_ms * 3_000 <= ttl_us
      }
      case state.managed, state.revoked, valid {
        None, False, True -> {
          let managed = ManagedAuthorityMaintenance(coordinator, ttl_us, interval_ms,
            files.digest("managed-authority:" <> state.config.session_id <> ":" <> int.to_string(ffi_system_now_ns())), 0)
          let candidate = AuthorityWorkerState(..state, managed: Some(managed))
          case maintain_authority(candidate, managed) {
            Ok(next) -> { process.send(reply_to, Ok(Nil)) actor.continue(next) }
            Error(err) -> { process.send(reply_to, Error(err)) actor.continue(suspend_managed_authority(candidate)) }
          }
        }
        _, _, _ -> { process.send(reply_to, Error("managed_authority_enable_refused")) actor.continue(state) }
      }
    }
    MaintenanceTick(sequence) -> {
      case state.managed, state.revoked {
        Some(managed), False if managed.sequence == sequence -> {
          case maintain_authority(state, managed) {
            Ok(next) -> actor.continue(next)
            Error(_) -> actor.continue(suspend_managed_authority(state))
          }
        }
        _, _ -> actor.continue(state)
      }
    }
    GetAuthorityStatus(reply_to) -> {
      process.send(reply_to, #(state.lease, state.revoked))
      actor.continue(state)
    }
    VerifyAuthority(now_us, reply_to) -> {
      let res = case state.revoked {
        True -> Error("authority_lease_revoked")
        False -> {
          case state.lease {
            None -> Error("authority_lease_missing")
            Some(lease) -> {
              let trusted_now_us = ffi_system_now_utc_us()
              let effective_now_us = int.max(now_us, trusted_now_us)
              case lease.valid_until_us <= effective_now_us {
                True -> Error("authority_lease_invalid_or_expired")
                False -> {
                  case
                    lease.expected_task_attempt
                    == state.config.expected_task_attempt
                  {
                    False -> Error("authority_lease_task_attempt_mismatch")
                    True -> {
                      case
                        lease.coordinator_epoch
                        == state.config.coordinator_epoch
                      {
                        False ->
                          Error("authority_lease_coordinator_epoch_mismatch")
                        True -> {
                          let now_ns = effective_now_us * 1000
                          verify_authority_config(state.config, now_ns)
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
      process.send(reply_to, res)
      actor.continue(state)
    }
  }
}

pub fn start_authority_worker(
  config: ServiceConfiguration,
) -> Result(actor.Started(Subject(AuthorityWorkerMessage)), String) {
  start_authority_worker_scoped(config, config.bot_id)
}

fn start_authority_worker_scoped(
  config: ServiceConfiguration,
  scope: a,
) -> Result(actor.Started(Subject(AuthorityWorkerMessage)), String) {
  actor.new_with_initialiser(5000, fn(subject) {
    ffi_set_worker_subject(scope, "authority", subject)
    actor.initialised(AuthorityWorkerState(
      config: config,
      lease: None,
      revoked: False,
      self: subject,
      managed: None,
    ))
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.on_message(handle_authority_worker_message)
  |> actor.start()
  |> result.map_error(fn(err) {
    "authority_worker_start_failed: " <> string.inspect(err)
  })
}

pub fn authority_worker(
  config: ServiceConfiguration,
) -> supervision.ChildSpecification(Subject(AuthorityWorkerMessage)) {
  supervision.worker(fn() {
    case start_authority_worker(config) {
      Ok(started) -> Ok(started)
      Error(err) -> Error(actor.InitFailed(err))
    }
  })
}

pub fn authority_worker_verify(
  worker: Subject(AuthorityWorkerMessage),
  now_us: Int,
  timeout_ms: Int,
) -> Result(AuthorityWitness, String) {
  poll_rpc.call(worker, timeout_ms, fn(reply_to) {
    VerifyAuthority(now_us, reply_to)
  })
}

pub fn authority_worker_set_lease(
  worker: Subject(AuthorityWorkerMessage),
  lease: AuthorityLease,
) -> Nil {
  process.send(worker, SetAuthorityLease(lease))
}

pub fn authority_worker_revoke_lease(
  worker: Subject(AuthorityWorkerMessage),
) -> Nil {
  process.send(worker, RevokeAuthorityLease)
}

pub type StoreWorkerMessage {
  StorePrepareMemory(
    gen: Int, record: ledger.InboxRecord, version: Int, sha: String,
    worker: String, epoch: Int, reply_to: Subject(Result(store.MemoryObservation,store.StoreError)),
  )
  StoreCommitMemory(observation: store.MemoryObservation, payloads: List(String),
    reply_to: Subject(Result(store.CommitResultResult,store.StoreError)))
  StoreReserveConversation(
    expected_gen: Int, record: ledger.InboxRecord, version: Int, sha: String,
    worker: String, epoch: Int, day: Int, daily_limit: Int,
    reply_to: Subject(Result(store.ConversationReservation, store.StoreError)),
  )
  StoreCommitConversation(
    reservation: store.ConversationReservation, payloads: List(String), reply: Option(String),
    reply_to: Subject(Result(store.CommitResultResult, store.StoreError)),
  )
  StorePing(reply_to: Subject(String))
  StoreReadWatermark(
    reply_to: Subject(
      Result(#(ledger.Watermark, Int, String), store.StoreError),
    ),
  )
  StoreCommitPrefix(
    bot_id: Int,
    operation_id: String,
    expected_gen: Int,
    watermark: ledger.Watermark,
    watermark_version: Int,
    watermark_sha: String,
    verdicts: List(guard.IngressVerdict),
    now_ms: Int,
    reply_to: Subject(Result(store.CommitPrefixResult, store.StoreError)),
  )
  StoreClaimTaskProcessing(
    bot_id: Int,
    operation_id: String,
    expected_gen: Int,
    inbox_record: ledger.InboxRecord,
    record_version: Int,
    record_sha: String,
    worker_id: String,
    service_epoch: Int,
    now_ms: Int,
    reply_to: Subject(
      Result(#(codec.Receipt, ledger.InboxRecord), store.StoreError),
    ),
  )
  StoreCommitResult(
    bot_id: Int,
    operation_id: String,
    expected_gen: Int,
    inbox_record: ledger.InboxRecord,
    record_version: Int,
    record_sha: String,
    response_chunks: List(String),
    worker_id: String,
    service_epoch: Int,
    reply_to: Subject(Result(store.CommitResultResult, store.StoreError)),
  )
  StoreCommitSending(
    bot_id: Int,
    operation_id: String,
    expected_gen: Int,
    inbox_record: ledger.InboxRecord,
    record_version: Int,
    record_sha: String,
    chunk: ledger.OutboxChunk,
    chunk_version: Int,
    chunk_sha: String,
    worker_id: String,
    service_epoch: Int,
    reply_to: Subject(
      Result(#(codec.Receipt, ledger.OutboxChunk), store.StoreError),
    ),
  )
  StoreCommitOutcome(
    bot_id: Int,
    operation_id: String,
    expected_gen: Int,
    chunk: ledger.OutboxChunk,
    chunk_version: Int,
    chunk_sha: String,
    outcome: ledger.OutboxStatus,
    reply_to: Subject(
      Result(#(codec.Receipt, ledger.OutboxChunk), store.StoreError),
    ),
  )
  StoreCommitTaskCompletion(
    bot_id: Int,
    operation_id: String,
    expected_gen: Int,
    inbox_record: ledger.InboxRecord,
    record_version: Int,
    record_sha: String,
    delivered_chunks: List(ledger.OutboxChunk),
    reply_to: Subject(
      Result(#(codec.Receipt, ledger.InboxRecord), store.StoreError),
    ),
  )
  StoreReadKeys(
    keys: List(String),
    reply_to: Subject(Result(#(Int, List(codec.RowResult)), store.StoreError)),
  )
  StoreRecoverInflightRecord(
    record: ledger.InboxRecord,
    reply_to: Subject(
      Result(#(ledger.InboxRecord, List(ledger.OutboxChunk)), String),
    ),
  )
}

pub type StoreWorkerState {
  StoreWorkerState(config: transport.LocalConfiguration, bot_id: Int)
}

fn handle_store_worker_message(
  state: StoreWorkerState,
  msg: StoreWorkerMessage,
) -> actor.Next(StoreWorkerState, StoreWorkerMessage) {
  case msg {
    StorePrepareMemory(gen,record,version,sha,worker,epoch,reply_to) -> {
      process.send(reply_to,store.prepare_memory_command(state.config,gen,record,version,sha,worker,epoch))
      actor.continue(state)
    }
    StoreCommitMemory(observation,payloads,reply_to) -> {
      process.send(reply_to,store.commit_memory_result(observation,payloads))
      actor.continue(state)
    }
    StoreReserveConversation(gen, record, version, sha, worker, epoch, day, limit, reply_to) -> {
      let res = store.reserve_conversation(state.config, gen, record, version, sha, worker, epoch, day, limit)
      process.send(reply_to, res)
      actor.continue(state)
    }
    StoreCommitConversation(reservation, payloads, reply, reply_to) -> {
      let res = store.commit_conversation_result(reservation, payloads, reply)
      process.send(reply_to, res)
      actor.continue(state)
    }
    StorePing(reply_to) -> {
      process.send(reply_to, "pong")
      actor.continue(state)
    }
    StoreReadWatermark(reply_to) -> {
      let res = store.read_watermark(state.config)
      process.send(reply_to, res)
      actor.continue(state)
    }
    StoreCommitPrefix(
      bot_id,
      operation_id,
      expected_gen,
      watermark,
      watermark_version,
      watermark_sha,
      verdicts,
      now_ms,
      reply_to,
    ) -> {
      let res =
        store.commit_prefix(
          state.config,
          bot_id,
          operation_id,
          expected_gen,
          watermark,
          watermark_version,
          watermark_sha,
          verdicts,
          now_ms,
        )
      process.send(reply_to, res)
      actor.continue(state)
    }
    StoreClaimTaskProcessing(
      bot_id,
      operation_id,
      expected_gen,
      inbox_record,
      record_version,
      record_sha,
      worker_id,
      service_epoch,
      now_ms,
      reply_to,
    ) -> {
      let res =
        store.claim_task_processing(
          state.config,
          bot_id,
          operation_id,
          expected_gen,
          inbox_record,
          record_version,
          record_sha,
          worker_id,
          service_epoch,
          now_ms,
        )
      process.send(reply_to, res)
      actor.continue(state)
    }
    StoreCommitResult(
      bot_id,
      operation_id,
      expected_gen,
      inbox_record,
      record_version,
      record_sha,
      response_chunks,
      worker_id,
      service_epoch,
      reply_to,
    ) -> {
      let res =
        store.commit_result(
          state.config,
          bot_id,
          operation_id,
          expected_gen,
          inbox_record,
          record_version,
          record_sha,
          response_chunks,
          worker_id,
          service_epoch,
        )
      process.send(reply_to, res)
      actor.continue(state)
    }
    StoreCommitSending(
      bot_id,
      operation_id,
      expected_gen,
      inbox_record,
      record_version,
      record_sha,
      chunk,
      chunk_version,
      chunk_sha,
      worker_id,
      service_epoch,
      reply_to,
    ) -> {
      let res =
        store.commit_sending(
          state.config,
          bot_id,
          operation_id,
          expected_gen,
          inbox_record,
          record_version,
          record_sha,
          chunk,
          chunk_version,
          chunk_sha,
          worker_id,
          service_epoch,
        )
      process.send(reply_to, res)
      actor.continue(state)
    }
    StoreCommitOutcome(
      bot_id,
      operation_id,
      expected_gen,
      chunk,
      chunk_version,
      chunk_sha,
      outcome,
      reply_to,
    ) -> {
      let res =
        store.commit_outcome(
          state.config,
          bot_id,
          operation_id,
          expected_gen,
          chunk,
          chunk_version,
          chunk_sha,
          outcome,
        )
      process.send(reply_to, res)
      actor.continue(state)
    }
    StoreCommitTaskCompletion(
      bot_id,
      operation_id,
      expected_gen,
      inbox_record,
      record_version,
      record_sha,
      delivered_chunks,
      reply_to,
    ) -> {
      let res =
        store.commit_task_completion(
          state.config,
          bot_id,
          operation_id,
          expected_gen,
          inbox_record,
          record_version,
          record_sha,
          delivered_chunks,
        )
      process.send(reply_to, res)
      actor.continue(state)
    }
    StoreReadKeys(keys, reply_to) -> {
      let res = store.read_keys(state.config, keys)
      process.send(reply_to, res)
      actor.continue(state)
    }
    StoreRecoverInflightRecord(record, reply_to) -> {
      let res = recover_inflight_record(state.config, record)
      process.send(reply_to, res)
      actor.continue(state)
    }
  }
}

pub fn start_store_worker(
  config: transport.LocalConfiguration,
  bot_id: Int,
) -> Result(actor.Started(Subject(StoreWorkerMessage)), String) {
  start_store_worker_scoped(config, bot_id, bot_id)
}

fn start_store_worker_scoped(
  config: transport.LocalConfiguration,
  bot_id: Int,
  scope: a,
) -> Result(actor.Started(Subject(StoreWorkerMessage)), String) {
  actor.new_with_initialiser(5000, fn(subject) {
    ffi_set_worker_subject(scope, "store", subject)
    actor.initialised(StoreWorkerState(config: config, bot_id: bot_id))
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.on_message(handle_store_worker_message)
  |> actor.start()
  |> result.map_error(fn(err) {
    "store_worker_start_failed: " <> string.inspect(err)
  })
}

pub fn store_worker(
  config: transport.LocalConfiguration,
  bot_id: Int,
) -> supervision.ChildSpecification(Subject(StoreWorkerMessage)) {
  supervision.worker(fn() {
    case start_store_worker(config, bot_id) {
      Ok(started) -> Ok(started)
      Error(err) -> Error(actor.InitFailed(err))
    }
  })
}

pub fn store_worker_read_watermark(
  worker: Subject(StoreWorkerMessage),
  timeout_ms: Int,
) -> Result(#(ledger.Watermark, Int, String), store.StoreError) {
  process.call(worker, timeout_ms, StoreReadWatermark)
}

pub fn store_worker_read_keys(
  worker: Subject(StoreWorkerMessage),
  keys: List(String),
  timeout_ms: Int,
) -> Result(#(Int, List(codec.RowResult)), store.StoreError) {
  process.call(worker, timeout_ms, fn(reply_to) {
    StoreReadKeys(keys, reply_to)
  })
}

pub fn store_worker_commit_prefix(
  worker: Subject(StoreWorkerMessage),
  bot_id: Int,
  operation_id: String,
  expected_gen: Int,
  watermark: ledger.Watermark,
  watermark_version: Int,
  watermark_sha: String,
  verdicts: List(guard.IngressVerdict),
  now_ms: Int,
  timeout_ms: Int,
) -> Result(store.CommitPrefixResult, store.StoreError) {
  process.call(worker, timeout_ms, fn(reply_to) {
    StoreCommitPrefix(
      bot_id,
      operation_id,
      expected_gen,
      watermark,
      watermark_version,
      watermark_sha,
      verdicts,
      now_ms,
      reply_to,
    )
  })
}

pub fn store_worker_claim_task_processing(
  worker: Subject(StoreWorkerMessage),
  bot_id: Int,
  operation_id: String,
  expected_gen: Int,
  inbox_record: ledger.InboxRecord,
  record_version: Int,
  record_sha: String,
  worker_id: String,
  service_epoch: Int,
  now_ms: Int,
  timeout_ms: Int,
) -> Result(#(codec.Receipt, ledger.InboxRecord), store.StoreError) {
  process.call(worker, timeout_ms, fn(reply_to) {
    StoreClaimTaskProcessing(
      bot_id,
      operation_id,
      expected_gen,
      inbox_record,
      record_version,
      record_sha,
      worker_id,
      service_epoch,
      now_ms,
      reply_to,
    )
  })
}

pub fn store_worker_commit_result(
  worker: Subject(StoreWorkerMessage),
  bot_id: Int,
  operation_id: String,
  expected_gen: Int,
  inbox_record: ledger.InboxRecord,
  record_version: Int,
  record_sha: String,
  response_chunks: List(String),
  worker_id: String,
  service_epoch: Int,
  timeout_ms: Int,
) -> Result(store.CommitResultResult, store.StoreError) {
  process.call(worker, timeout_ms, fn(reply_to) {
    StoreCommitResult(
      bot_id,
      operation_id,
      expected_gen,
      inbox_record,
      record_version,
      record_sha,
      response_chunks,
      worker_id,
      service_epoch,
      reply_to,
    )
  })
}

pub fn store_worker_commit_sending(
  worker: Subject(StoreWorkerMessage),
  bot_id: Int,
  operation_id: String,
  expected_gen: Int,
  inbox_record: ledger.InboxRecord,
  record_version: Int,
  record_sha: String,
  chunk: ledger.OutboxChunk,
  chunk_version: Int,
  chunk_sha: String,
  worker_id: String,
  service_epoch: Int,
  timeout_ms: Int,
) -> Result(#(codec.Receipt, ledger.OutboxChunk), store.StoreError) {
  process.call(worker, timeout_ms, fn(reply_to) {
    StoreCommitSending(
      bot_id,
      operation_id,
      expected_gen,
      inbox_record,
      record_version,
      record_sha,
      chunk,
      chunk_version,
      chunk_sha,
      worker_id,
      service_epoch,
      reply_to,
    )
  })
}

pub fn store_worker_commit_outcome(
  worker: Subject(StoreWorkerMessage),
  bot_id: Int,
  operation_id: String,
  expected_gen: Int,
  chunk: ledger.OutboxChunk,
  chunk_version: Int,
  chunk_sha: String,
  outcome: ledger.OutboxStatus,
  timeout_ms: Int,
) -> Result(#(codec.Receipt, ledger.OutboxChunk), store.StoreError) {
  process.call(worker, timeout_ms, fn(reply_to) {
    StoreCommitOutcome(
      bot_id,
      operation_id,
      expected_gen,
      chunk,
      chunk_version,
      chunk_sha,
      outcome,
      reply_to,
    )
  })
}

pub fn store_worker_commit_task_completion(
  worker: Subject(StoreWorkerMessage),
  bot_id: Int,
  operation_id: String,
  expected_gen: Int,
  inbox_record: ledger.InboxRecord,
  record_version: Int,
  record_sha: String,
  delivered_chunks: List(ledger.OutboxChunk),
  timeout_ms: Int,
) -> Result(#(codec.Receipt, ledger.InboxRecord), store.StoreError) {
  process.call(worker, timeout_ms, fn(reply_to) {
    StoreCommitTaskCompletion(
      bot_id,
      operation_id,
      expected_gen,
      inbox_record,
      record_version,
      record_sha,
      delivered_chunks,
      reply_to,
    )
  })
}

pub fn store_worker_recover_inflight_record(
  worker: Subject(StoreWorkerMessage),
  record: ledger.InboxRecord,
  timeout_ms: Int,
) -> Result(#(ledger.InboxRecord, List(ledger.OutboxChunk)), String) {
  process.call(worker, timeout_ms, fn(reply_to) {
    StoreRecoverInflightRecord(record, reply_to)
  })
}

pub type PollerWorkerMessage {
  PollerPing(reply_to: Subject(String))
  PollerGetUpdates(
    offset: Int,
    limit: Int,
    timeout_s: Int,
    reply_to: Subject(Result(List(String), String)),
  )
}

pub type PollerWorkerState {
  PollerWorkerState(config: http_client.TelegramHttpConfiguration, bot_id: Int)
}

pub fn start_poller_worker(
  config: http_client.TelegramHttpConfiguration,
  bot_id: Int,
) -> Result(actor.Started(Subject(PollerWorkerMessage)), String) {
  start_poller_worker_scoped(config, bot_id, bot_id)
}

fn start_poller_worker_scoped(
  config: http_client.TelegramHttpConfiguration,
  bot_id: Int,
  scope: a,
) -> Result(actor.Started(Subject(PollerWorkerMessage)), String) {
  actor.new_with_initialiser(5000, fn(subject) {
    ffi_set_worker_subject(scope, "poller", subject)
    actor.initialised(PollerWorkerState(config: config, bot_id: bot_id))
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.on_message(fn(state, msg) {
    case msg {
      PollerPing(reply_to) -> {
        process.send(reply_to, "pong")
        actor.continue(state)
      }
      PollerGetUpdates(offset, limit, timeout_s, reply_to) -> {
        let res =
          http_client.poll_updates(state.config, offset, limit, timeout_s)
        process.send(reply_to, res)
        actor.continue(state)
      }
    }
  })
  |> actor.start()
  |> result.map_error(fn(err) {
    "poller_worker_start_failed: " <> string.inspect(err)
  })
}

pub fn poller_worker(
  config: http_client.TelegramHttpConfiguration,
  bot_id: Int,
) -> supervision.ChildSpecification(Subject(PollerWorkerMessage)) {
  supervision.worker(fn() {
    case start_poller_worker(config, bot_id) {
      Ok(started) -> Ok(started)
      Error(err) -> Error(actor.InitFailed(err))
    }
  })
}

pub fn poller_worker_get_updates(
  worker: Subject(PollerWorkerMessage),
  offset: Int,
  limit: Int,
  timeout_s: Int,
  timeout_ms: Int,
) -> Result(List(String), String) {
  poll_rpc.call(worker, timeout_ms, fn(reply_to) {
    PollerGetUpdates(offset, limit, timeout_s, reply_to)
  })
}

fn supervised_worker_scoped(
  config: ServiceConfiguration,
  cleanup_receipt: Option(lifecycle.UnitCleanupReceipt),
  bridge_subject: Option(Subject(#(reference.Reference, Subject(ServiceMessage)))),
) -> supervision.ChildSpecification(Subject(ServiceMessage)) {
  supervision.worker(fn() {
    let scope = ensure_worker_scope()
    case start_actor_scoped(config, cleanup_receipt, scope) {
      Ok(started) -> {
        case bridge_subject {
          Some(subj) -> process.send(subj, #(scope, started.data))
          None -> Nil
        }
        Ok(started)
      }
      Error(err) -> Error(actor.InitFailed(err))
    }
  })
}

pub fn start_supervised_service(
  config: ServiceConfiguration,
  cleanup_receipt: Option(lifecycle.UnitCleanupReceipt),
) -> Result(SupervisedService, String) {
  let bridge_subject = process.new_subject()
  let c1 = supervision.worker(fn() {
    let scope = ensure_worker_scope()
    start_authority_worker_scoped(config, scope)
    |> result.map_error(actor.InitFailed)
  })
  let c2 = supervision.worker(fn() {
    let scope = ensure_worker_scope()
    start_store_worker_scoped(config.storage_config, config.bot_id, scope)
    |> result.map_error(actor.InitFailed)
  })
  let c3 = supervision.worker(fn() {
    let scope = ensure_worker_scope()
    start_poller_worker_scoped(config.http_config, config.bot_id, scope)
    |> result.map_error(actor.InitFailed)
  })
  let c4 = supervised_worker_scoped(config, cleanup_receipt, Some(bridge_subject))
  use sup_started <- result.try(
    static_supervisor.new(static_supervisor.RestForOne)
    |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
    |> static_supervisor.add(c1)
    |> static_supervisor.add(c2)
    |> static_supervisor.add(c3)
    |> static_supervisor.add(c4)
    |> static_supervisor.start()
    |> result.map_error(fn(err) {
      "start_service_supervisor_failed: " <> string.inspect(err)
    }),
  )
  // Child start closures execute inside the owning supervisor. Its ETS scope
  // is created there and dies there, without a handoff or bootstrap registry.
  case process.receive(bridge_subject, 3000) {
    Ok(#(scope, actor_subj)) -> {
      case #(
        ffi_get_worker_subject(scope, "authority"),
        ffi_get_worker_subject(scope, "store"),
        ffi_get_worker_subject(scope, "poller")
      ) {
        #(Ok(auth_subj), Ok(store_subj), Ok(poller_subj)) ->
          Ok(SupervisedService(
            supervisor: sup_started.data,
            actor_subject: actor_subj,
            authority_worker: auth_subj,
            store_worker: store_subj,
            poller_worker: poller_subj,
            subject_scope: scope,
            supervisor_pid: sup_started.pid,
            configuration: config,
          ))
        _ -> {
          let cleanup = stop_instance(sup_started.pid)
          Error("supervised_worker_subject_missing: " <> string.inspect(cleanup))
        }
      }
    }
    Error(_) -> {
      let cleanup = stop_instance(sup_started.pid)
      Error("timed_out_waiting_for_supervised_actor_subject: " <> string.inspect(cleanup))
    }
  }
}

@external(erlang, "telegram_service_ffi", "stop_supervisor")
pub fn stop_supervisor(pid: Pid) -> Result(Nil, String)

fn stop_instance(pid: Pid) -> Result(Nil, String) {
  let monitor = process.monitor(pid)
  let selector = process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) { down })
  use _ <- result.try(stop_supervisor(pid) |> result.map_error(fn(err) {
    process.demonitor_process(monitor)
    err
  }))
  case process.selector_receive(selector, 5000) {
    Ok(_) -> {
      Ok(Nil)
    }
    Error(_) -> {
      process.demonitor_process(monitor)
      Error("supervisor_cleanup_unconfirmed")
    }
  }
}

pub fn stop_supervised_service(svc: SupervisedService) -> Result(Nil, String) {
  stop_instance(svc.supervisor_pid)
}

pub fn handle_message(
  state: ServiceState,
  msg: ServiceMessage,
) -> actor.Next(ServiceState, ServiceMessage) {
  let poll_active = state.in_flight_poll || state.poll_worker != None
  let dispatch_active = state.dispatch_worker != None
  let delivery_active =
    state.in_flight_workers != [] || state.delivery_queue != []

  case msg {
    PollCycle(_, reply) ->
      case dispatch_active || delivery_active {
        True -> {
          process.send(reply, Error("service_effect_in_flight"))
          actor.continue(state)
        }
        False -> handle_message_inner(state, msg)
      }

    AutomaticDispatchTick(_, reply) ->
      case poll_active || delivery_active {
        True -> {
          process.send(reply, Error("service_effect_in_flight"))
          actor.continue(state)
        }
        False -> handle_message_inner(state, msg)
      }

    DeliverChunk(_, _, _, _, _, _, _, reply) ->
      case poll_active || dispatch_active {
        True -> {
          process.send(reply, Error("service_effect_in_flight"))
          actor.continue(state)
        }
        False -> handle_message_inner(state, msg)
      }

    RevokeAuthority -> {
      let next_state = case poll_active || dispatch_active || delivery_active {
        True ->
          case state.writer_state {
            lifecycle.ServiceWriterHold(_) -> state
            _ ->
              ServiceState(
                ..state,
                writer_state: lifecycle.ServiceWriterHold(
                  "authority_revoked_with_inflight_effect",
                ),
              )
          }
        False -> state
      }
      handle_message_inner(next_state, msg)
    }

    DeliveryWorkerFinished(pid, _, _, _) ->
      case list.contains(state.in_flight_workers, pid) {
        True -> handle_message_inner(state, msg)
        False -> actor.continue(state)
      }

    _ -> handle_message_inner(state, msg)
  }
}

fn handle_message_inner(
  state: ServiceState,
  msg: ServiceMessage,
) -> actor.Next(ServiceState, ServiceMessage) {
  case msg {
    SetAuthority(lease) -> {
      case state.authority_managed {
        True -> actor.continue(state)
        False -> actor.continue(set_authority(state, lease))
      }
    }
    ManagedAuthorityRenewed(lease) -> {
      case state.authority_revoked {
        True -> actor.continue(state)
        False -> actor.continue(ServiceState(..state, authority: Some(lease), authority_managed: True))
      }
    }
    ManagedAuthorityLost -> handle_message_inner(ServiceState(..state, authority_managed: True), RevokeAuthority)

    RevokeAuthority -> {
      case state.authority_worker {
        Some(aw) -> authority_worker_revoke_lease(aw)
        None -> Nil
      }
      case state.poll_worker {
        Some(pid) -> process.kill(pid)
        None -> Nil
      }
      case state.dispatch_worker {
        Some(pid) -> process.kill(pid)
        None -> Nil
      }
      list.each(state.in_flight_workers, fn(pid) { process.kill(pid) })
      list.each(state.delivery_queue, fn(qtask) {
        process.send(qtask.reply_to, Error("authority_lease_revoked"))
      })
      actor.continue(
        ServiceState(
          ..state,
          authority: None,
          authority_revoked: True,
          in_flight_poll: False,
          poll_worker: None,
          dispatch_worker: None,
          in_flight_workers: [],
          delivery_queue: [],
        ),
      )
    }

    PollCycle(now_us, reply_to) -> {
      case state.authority_revoked {
        True -> {
          process.send(reply_to, Error("authority_lease_revoked"))
          actor.continue(state)
        }
        False -> {
          case state.in_flight_poll {
            True -> {
              process.send(reply_to, Error("poll_already_in_flight"))
              actor.continue(state)
            }
            False -> {
              case state.pending_operation {
                Some(_) -> {
                  process.send(
                    reply_to,
                    Error(
                      "service_writer_held: pending_unreconciled_operation_in_state",
                    ),
                  )
                  actor.continue(state)
                }
                None -> {
                  case lifecycle.evaluate_writer_gate(state.writer_state) {
                    Error(err) -> {
                      process.send(reply_to, Error(err))
                      actor.continue(state)
                    }
                    Ok(Nil) -> {
                      case verify_authority(state, now_us) {
                        Error(err) -> {
                          process.send(reply_to, Error(err))
                          actor.continue(state)
                        }
                        Ok(_) -> {
                          let self_sub = state.self_subject
                          let poll_worker_pid =
                            process.spawn_unlinked(fn() {
                              let outcome = poll_cycle(state, now_us)
                              case self_sub {
                                Some(sub) ->
                                  process.send(
                                    sub,
                                    PollWorkerFinished(
                                      process.self(),
                                      outcome,
                                      reply_to,
                                    ),
                                  )
                                None -> Nil
                              }
                            })
                          let _mon = process.monitor(poll_worker_pid)
                          actor.continue(
                            ServiceState(
                              ..state,
                              in_flight_poll: True,
                              poll_worker: Some(poll_worker_pid),
                            ),
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
      }
    }

    PollWorkerFinished(pid, outcome, reply_to) -> {
      let is_current = state.poll_worker == Some(pid)
      case is_current {
        False -> actor.continue(state)
        True -> {
          case state.authority_revoked {
            True -> {
              process.send(reply_to, Error("authority_lease_revoked"))
              actor.continue(
                ServiceState(..state, in_flight_poll: False, poll_worker: None),
              )
            }
            False -> {
              case outcome {
                Ok(#(next_state, step_result)) -> {
                  process.send(reply_to, Ok(step_result))
                  actor.continue(
                    ServiceState(
                      ..state,
                      in_flight_poll: False,
                      poll_worker: None,
                      watermark: next_state.watermark,
                      watermark_version: next_state.watermark_version,
                      watermark_sha: next_state.watermark_sha,
                      expected_generation: next_state.expected_generation,
                      writer_state: next_state.writer_state,
                      pending_operation: next_state.pending_operation,
                    ),
                  )
                }
                Error(ServiceError(failed_state, err)) -> {
                  process.send(reply_to, Error(err))
                  actor.continue(
                    ServiceState(
                      ..state,
                      in_flight_poll: False,
                      poll_worker: None,
                      writer_state: failed_state.writer_state,
                      pending_operation: failed_state.pending_operation,
                    ),
                  )
                }
              }
            }
          }
        }
      }
    }

    AutomaticDispatchTick(now_us, reply_to) -> {
      case state.authority_revoked {
        True -> {
          process.send(reply_to, Error("authority_lease_revoked"))
          actor.continue(state)
        }
        False -> {
          case state.dispatch_worker {
            Some(_) -> {
              process.send(reply_to, Error("dispatch_already_in_flight"))
              actor.continue(state)
            }
            None -> {
              case state.pending_operation {
                Some(_) -> {
                  process.send(
                    reply_to,
                    Error(
                      "service_writer_held: pending_unreconciled_operation_in_state",
                    ),
                  )
                  actor.continue(state)
                }
                None -> {
                  case lifecycle.evaluate_writer_gate(state.writer_state) {
                    Error(err) -> {
                      process.send(reply_to, Error(err))
                      actor.continue(state)
                    }
                    Ok(Nil) -> {
                      case verify_authority(state, now_us) {
                        Error(err) -> {
                          process.send(reply_to, Error(err))
                          actor.continue(state)
                        }
                        Ok(_) -> {
                          let self_sub = state.self_subject
                          let dispatch_worker_pid =
                            process.spawn_unlinked(fn() {
                              let outcome = dispatch_cycle(state, now_us)
                              case self_sub {
                                Some(sub) ->
                                  process.send(
                                    sub,
                                    DispatchWorkerFinished(
                                      process.self(),
                                      outcome,
                                      reply_to,
                                    ),
                                  )
                                None -> Nil
                              }
                            })
                          let _mon = process.monitor(dispatch_worker_pid)
                          actor.continue(
                            ServiceState(
                              ..state,
                              dispatch_worker: Some(dispatch_worker_pid),
                            ),
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
      }
    }

    DispatchWorkerFinished(pid, outcome, reply_to) -> {
      let is_current = state.dispatch_worker == Some(pid)
      case is_current {
        False -> actor.continue(state)
        True -> {
          case state.authority_revoked {
            True -> {
              process.send(reply_to, Error("authority_lease_revoked"))
              actor.continue(ServiceState(..state, dispatch_worker: None))
            }
            False -> {
              case outcome {
                Ok(#(next_state, step_result)) -> {
                  process.send(reply_to, Ok(step_result))
                  actor.continue(
                    ServiceState(
                      ..state,
                      dispatch_worker: None,
                      expected_generation: next_state.expected_generation,
                      writer_state: next_state.writer_state,
                      pending_operation: next_state.pending_operation,
                    ),
                  )
                }
                Error(ServiceError(failed_state, err)) -> {
                  process.send(reply_to, Error(err))
                  actor.continue(
                    ServiceState(
                      ..state,
                      dispatch_worker: None,
                      expected_generation: failed_state.expected_generation,
                      writer_state: failed_state.writer_state,
                      pending_operation: failed_state.pending_operation,
                    ),
                  )
                }
              }
            }
          }
        }
      }
    }

    DeliverChunk(
      inbox_record,
      inbox_version,
      inbox_sha,
      chunk,
      chunk_version,
      chunk_sha,
      now_us,
      reply_to,
    ) -> {
      case state.authority_revoked {
        True -> {
          process.send(reply_to, Error("authority_lease_revoked"))
          actor.continue(state)
        }
        False -> {
          case list.length(state.delivery_queue) >= max_admission_queue {
            True -> {
              process.send(reply_to, Error("admission_queue_saturated"))
              actor.continue(state)
            }
            False -> {
              case state.pending_operation {
                Some(_) -> {
                  process.send(
                    reply_to,
                    Error(
                      "service_writer_held: pending_unreconciled_operation_in_state",
                    ),
                  )
                  actor.continue(state)
                }
                None -> {
                  case lifecycle.evaluate_writer_gate(state.writer_state) {
                    Error(err) -> {
                      process.send(reply_to, Error(err))
                      actor.continue(state)
                    }
                    Ok(Nil) -> {
                      case verify_authority(state, now_us) {
                        Error(err) -> {
                          process.send(reply_to, Error(err))
                          actor.continue(state)
                        }
                        Ok(_) -> {
                          let task =
                            DeliveryTask(
                              inbox_record: inbox_record,
                              inbox_version: inbox_version,
                              inbox_sha: inbox_sha,
                              chunk: chunk,
                              chunk_version: chunk_version,
                              chunk_sha: chunk_sha,
                              now_us: now_us,
                              reply_to: reply_to,
                            )
                          case list.is_empty(state.in_flight_workers) {
                            True -> {
                              let next_state =
                                spawn_delivery_worker(state, task)
                              actor.continue(next_state)
                            }
                            False -> {
                              let next_queue =
                                list.append(state.delivery_queue, [task])
                              actor.continue(
                                ServiceState(
                                  ..state,
                                  delivery_queue: next_queue,
                                ),
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
          }
        }
      }
    }

    DeliveryWorkerFinished(pid, maybe_gen, maybe_writer_state, maybe_pending) -> {
      let remaining = list.filter(state.in_flight_workers, fn(p) { p != pid })
      let next_gen = case maybe_gen {
        Some(g) -> g
        None -> state.expected_generation
      }
      let next_writer_state = case maybe_writer_state {
        Some(ws) -> ws
        None -> state.writer_state
      }
      let next_pending = case maybe_pending {
        Some(p) -> Some(p)
        None -> state.pending_operation
      }

      case lifecycle.evaluate_writer_gate(next_writer_state) {
        Error(err) -> {
          list.each(state.delivery_queue, fn(qtask) {
            process.send(qtask.reply_to, Error("service_writer_held: " <> err))
          })
          actor.continue(
            ServiceState(
              ..state,
              in_flight_workers: remaining,
              delivery_queue: [],
              expected_generation: next_gen,
              writer_state: next_writer_state,
              pending_operation: next_pending,
            ),
          )
        }
        Ok(Nil) -> {
          case state.delivery_queue {
            [] ->
              actor.continue(
                ServiceState(
                  ..state,
                  in_flight_workers: remaining,
                  expected_generation: next_gen,
                  writer_state: next_writer_state,
                  pending_operation: next_pending,
                ),
              )
            [next_task, ..rest_queue] -> {
              let interim_state =
                ServiceState(
                  ..state,
                  in_flight_workers: remaining,
                  delivery_queue: rest_queue,
                  expected_generation: next_gen,
                  writer_state: next_writer_state,
                  pending_operation: next_pending,
                )
              let spawned_state =
                spawn_delivery_worker(interim_state, next_task)
              actor.continue(spawned_state)
            }
          }
        }
      }
    }

    WorkerDown(down) -> {
      case down {
        process.ProcessDown(_mon, pid, reason) -> {
          let state1 = case state.poll_worker == Some(pid) {
            True -> {
              case reason == process.Normal {
                True ->
                  ServiceState(
                    ..state,
                    poll_worker: None,
                    in_flight_poll: False,
                  )
                False -> {
                  ServiceState(
                    ..state,
                    poll_worker: None,
                    in_flight_poll: False,
                    writer_state: lifecycle.ServiceWriterHold(
                      "poll_worker_died_unexpectedly",
                    ),
                  )
                }
              }
            }
            False -> state
          }
          let state2 = case state1.dispatch_worker == Some(pid) {
            True -> {
              case reason == process.Normal {
                True -> ServiceState(..state1, dispatch_worker: None)
                False -> {
                  ServiceState(
                    ..state1,
                    dispatch_worker: None,
                    writer_state: lifecycle.ServiceWriterHold(
                      "dispatch_worker_died_unexpectedly",
                    ),
                  )
                }
              }
            }
            False -> state1
          }
          case list.contains(state2.in_flight_workers, pid) {
            False -> actor.continue(state2)
            True -> {
              let remaining =
                list.filter(state2.in_flight_workers, fn(p) { p != pid })
              case reason == process.Normal {
                True ->
                  actor.continue(
                    ServiceState(..state2, in_flight_workers: remaining),
                  )
                False -> {
                  list.each(state2.delivery_queue, fn(qtask) {
                    process.send(
                      qtask.reply_to,
                      Error("delivery_worker_died_unexpectedly"),
                    )
                  })
                  actor.continue(
                    ServiceState(
                      ..state2,
                      in_flight_workers: remaining,
                      delivery_queue: [],
                      writer_state: lifecycle.ServiceWriterHold(
                        "delivery_worker_died_unexpectedly",
                      ),
                    ),
                  )
                }
              }
            }
          }
        }
        process.PortDown(..) -> actor.continue(state)
      }
    }

    GetManagedStartupState(reply_to) -> {
      process.send(reply_to, Ok(state))
      actor.continue(state)
    }
    GetState(reply_to) -> {
      process.send(reply_to, state)
      actor.continue(state)
    }

    GetPendingOperation(reply_to) -> {
      process.send(reply_to, state.pending_operation)
      actor.continue(state)
    }

    Stop -> {
      case state.poll_worker {
        Some(pid) -> process.kill(pid)
        None -> Nil
      }
      case state.dispatch_worker {
        Some(pid) -> process.kill(pid)
        None -> Nil
      }
      list.each(state.in_flight_workers, fn(pid) { process.kill(pid) })
      list.each(state.delivery_queue, fn(qtask) {
        process.send(qtask.reply_to, Error("service_stopped"))
      })
      actor.stop()
    }
  }
}

/// Managed development entry: bind live unit, persisted writer, task and runtime
/// authority before consuming the single start. Lease automation and operational
/// entrypoint migration are separate remaining integration obligations.
pub fn start_managed_service(
  config: ServiceConfiguration,
  current_control_path: String,
  expected: codec.WriterRegistration,
  cleanup_receipt: Option(lifecycle.UnitCleanupReceipt),
) -> Result(SupervisedService, String) {
  start_managed_service_with_transition(config, current_control_path, expected, cleanup_receipt, None)
}

/// Recover a stopped predecessor into one live successor. Preparation in storage
/// is not startup: only the subsequent single-use CAS grants this instance a start.
pub fn recover_active_managed_service(
  config: ServiceConfiguration,
  current_control_path: String,
  previous: codec.WriterRegistration,
  expected: codec.WriterRegistration,
  cleanup_receipt: lifecycle.UnitCleanupReceipt,
) -> Result(SupervisedService, String) {
  use svc <- result.try(start_managed_service_with_transition(
    config, current_control_path, expected, Some(cleanup_receipt), Some(previous)))
  activate_managed_service(svc)
}

fn start_managed_service_with_transition(
  config: ServiceConfiguration,
  current_control_path: String,
  expected: codec.WriterRegistration,
  cleanup_receipt: Option(lifecycle.UnitCleanupReceipt),
  previous_writer: Option(codec.WriterRegistration),
) -> Result(SupervisedService, String) {
  use _ <- result.try(case config.resource_id == "runtime:telegram-bridge" {
    True -> Ok(Nil)
    False ->
      Error(
        "invalid_managed_service_resource_id: "
        <> config.resource_id,
      )
  })
  use _ <- result.try(case config.bot_id > 0 {
    True -> Ok(Nil)
    False -> Error("invalid_service_bot_id")
  })
  use _ <- result.try(case config.service_epoch > 0 {
    True -> Ok(Nil)
    False -> Error("invalid_service_epoch")
  })
  use _ <- result.try(case expected.bot_id == config.bot_id {
    True -> Ok(Nil)
    False -> Error("expected_writer_bot_id_mismatch")
  })
  use _ <- result.try(case expected.service_epoch == config.service_epoch {
    True -> Ok(Nil)
    False -> Error("expected_writer_service_epoch_mismatch")
  })
  use _ <- result.try(case config.service_epoch {
    1 ->
      case cleanup_receipt, config.control_registration_path {
        None, None -> Ok(Nil)
        _, _ ->
          Error("epoch_1_forbids_predecessor_cleanup_or_control_path")
      }
    _ ->
      case cleanup_receipt, config.control_registration_path {
        Some(_), Some(predecessor_path) ->
          case string.trim(predecessor_path) != "" && predecessor_path != current_control_path {
            True -> Ok(Nil)
            False -> Error("epoch_gt_1_empty_predecessor_control_path")
          }
        _, _ ->
          Error("epoch_gt_1_requires_predecessor_cleanup_and_control_path")
      }
  })
  use _ <- result.try(case string.trim(current_control_path) != "" {
    True -> Ok(Nil)
    False -> Error("empty_current_control_path")
  })

  use _ <- result.try(codec.encode_writer_registration(expected)
    |> result.map_error(fn(err) { "invalid_expected_writer_registration: " <> err }))

  let expected_db = ffi_storage_config_db_path(config.storage_config)
  let expected_worker = ffi_storage_config_worker_sha(config.storage_config)
  let expected_guardian =
    ffi_storage_config_guardian_sha(config.storage_config)

  use current_control <- result.try(
    lifecycle.read_and_verify_prelaunch_control_bounded(
      current_control_path,
      "",
      expected_db,
      expected_worker,
      expected_guardian,
      config.service_epoch,
      Some(60_000_000),
    ),
  )
  use _ <- result.try(lifecycle.verify_live_lifecycle_ownership(current_control))

  let actual_control_digest =
    files.digest(lifecycle.encode_control_registration(current_control))
  use _ <- result.try(case expected.control_digest == actual_control_digest {
    True -> Ok(Nil)
    False ->
      Error(
        "writer_registration_control_digest_mismatch: exp="
        <> expected.control_digest
        <> " actual="
        <> actual_control_digest,
      )
  })
  use _ <- result.try(
    case expected.unit_invocation_id == current_control.unit_invocation_id {
      True -> Ok(Nil)
      False -> Error("writer_registration_unit_invocation_id_mismatch")
    },
  )
  use _ <- result.try(
    case expected.store_incarnation_id == current_control.store_incarnation_id {
      True -> Ok(Nil)
      False -> Error("writer_registration_store_incarnation_id_mismatch")
    },
  )
  use _ <- result.try(
    case expected.registered_at_us == current_control.registered_at_us {
      True -> Ok(Nil)
      False -> Error("writer_registration_registered_at_us_mismatch")
    },
  )

  // Read-only preflight does not consume the predecessor cleanup receipt.
  // Failures after CAS deliberately require recovery under a new epoch.
  use #(preflight_state, _) <- result.try(case cleanup_receipt, config.control_registration_path {
    None, None -> init_service(config, None)
    Some(receipt), Some(path) -> init_service_admitted(config, receipt, path)
    _, _ -> Error("managed_preflight_invalid_cleanup_pair")
  })
  use _ <- result.try(case preflight_state.writer_state {
    lifecycle.ServiceWriterClean -> Ok(Nil)
    lifecycle.ServiceWriterHold(reason) -> Error("managed_preflight_writer_hold: " <> reason)
  })

  use _pre_cas_authority <- result.try(verify_authority_config(
    config,
    ffi_system_now_ns(),
  ))


  use _ <- result.try(case previous_writer {
    None -> case config.service_epoch == 1 {
      True -> Ok(Nil)
      False -> Error("managed_successor_requires_recovery_entry")
    }
    Some(previous) -> {
      use _ <- result.try(codec.validate_writer_successor(previous, expected))
      use path <- result.try(case config.control_registration_path {
        Some(path) -> Ok(path)
        None -> Error("recovery_missing_predecessor_control")
      })
      use predecessor <- result.try(lifecycle.read_and_verify_prelaunch_control_bounded(
        path, "", expected_db, expected_worker, expected_guardian,
        previous.service_epoch, None))
      use _ <- result.try(case
        previous.control_digest == files.digest(lifecycle.encode_control_registration(predecessor))
        && previous.unit_invocation_id == predecessor.unit_invocation_id
        && previous.store_incarnation_id == predecessor.store_incarnation_id
        && previous.registered_at_us == predecessor.registered_at_us
      {
        True -> Ok(Nil)
        False -> Error("recovery_predecessor_writer_control_mismatch")
      })
      // Recheck ownership immediately before the storage mutation.
      use _ <- result.try(verify_authority_config(config, ffi_system_now_ns()))
      use _ <- result.try(lifecycle.verify_live_lifecycle_ownership(current_control))
      store.transition_writer_registration(config.storage_config, previous, expected)
      |> result.map(fn(_) { Nil })
      |> result.map_error(fn(err) { "prepare_writer_successor_failed: " <> string.inspect(err) })
    }
  })

  use _consumed_generation <- result.try(
    store.consume_writer_start(config.storage_config, expected)
    |> result.map_error(fn(err) {
      "consume_writer_start_failed: " <> string.inspect(err)
    }),
  )

  use _post_cas_authority <- result.try(verify_authority_config(
    config,
    ffi_system_now_ns(),
  ))
  use _ <- result.try(lifecycle.verify_live_lifecycle_ownership(current_control))

  use svc <- result.try(start_supervised_service(config, cleanup_receipt))
  case poll_rpc.call(svc.actor_subject, 5000, GetManagedStartupState) {
    Error(err) -> abort_managed_start(svc, "managed_service_state_unavailable: " <> err)
    Ok(state) -> case state.writer_state {
      lifecycle.ServiceWriterClean -> {
        case verify_managed_post_start(config, current_control_path, current_control) {
          Ok(Nil) -> Ok(svc)
          Error(err) -> abort_managed_start(svc, err)
        }
      }
      lifecycle.ServiceWriterHold(reason) ->
        abort_managed_start(svc, "managed_service_started_in_writer_hold: " <> reason)
    }
  }
}

fn abort_managed_start(
  svc: SupervisedService, reason: String,
) -> Result(SupervisedService, String) {
  case stop_supervised_service(svc) {
    Ok(Nil) -> Error(reason)
    Error(err) -> Error(reason <> " (cleanup_unconfirmed: " <> err <> ")")
  }
}

fn verify_managed_post_start(
  config: ServiceConfiguration,
  current_control_path: String,
  expected_control: lifecycle.ControlRegistration,
) -> Result(Nil, String) {
  use current <- result.try(lifecycle.read_and_verify_prelaunch_control_bounded(
    current_control_path, expected_control.unit_name,
    ffi_storage_config_db_path(config.storage_config),
    ffi_storage_config_worker_sha(config.storage_config),
    ffi_storage_config_guardian_sha(config.storage_config),
    config.service_epoch, Some(60_000_000),
  ))
  use _ <- result.try(case current == expected_control {
    True -> Ok(Nil)
    False -> Error("managed_control_changed_during_startup")
  })
  use _ <- result.try(lifecycle.verify_live_lifecycle_ownership(current))
  use _ <- result.try(verify_authority_config(config, ffi_system_now_ns()))
  Ok(Nil)
}

fn suspend_managed_authority(state: AuthorityWorkerState) -> AuthorityWorkerState {
  case state.managed {
    Some(managed) -> {
      case state.revoked { False -> process.send(managed.coordinator, ManagedAuthorityLost) True -> Nil }
      AuthorityWorkerState(..state, lease: None, revoked: True,
        managed: Some(ManagedAuthorityMaintenance(..managed, sequence: managed.sequence + 1)))
    }
    None -> AuthorityWorkerState(..state, lease: None, revoked: True)
  }
}

fn maintain_authority(state: AuthorityWorkerState, managed: ManagedAuthorityMaintenance) -> Result(AuthorityWorkerState, String) {
  use lease <- result.try(renew_managed_authority(state.config, managed.lease_id, managed.ttl_us, managed.sequence))
  let next = ManagedAuthorityMaintenance(..managed, sequence: managed.sequence + 1)
  process.send(managed.coordinator, ManagedAuthorityRenewed(lease))
  let _ = process.send_after(state.self, managed.interval_ms, MaintenanceTick(next.sequence))
  Ok(AuthorityWorkerState(..state, lease: Some(lease), managed: Some(next)))
}

pub fn enable_managed_authority(svc: SupervisedService, ttl_us: Int, interval_ms: Int) -> Result(Nil, String) {
  poll_rpc.call(svc.authority_worker, 5000, fn(reply) {
    EnableManagedAuthority(svc.actor_subject, ttl_us, interval_ms, reply)
  })
}

fn renew_managed_authority(
  config: ServiceConfiguration,
  lease_id: String,
  ttl_us: Int,
  sequence: Int,
) -> Result(AuthorityLease, String) {
  use _ <- result.try(case config.resource_id == "runtime:telegram-bridge" {
    True -> Ok(Nil)
    False -> Error("invalid authority resource_id: " <> config.resource_id)
  })
  use _ <- result.try(case string.trim(lease_id) != "" && sequence >= 0 {
    True -> Ok(Nil)
    False -> Error("invalid lease_id or negative sequence for renewal")
  })
  use _ <- result.try(case ttl_us >= 1_000_000 {
    True -> Ok(Nil)
    False -> Error("requested renewal ttl_us below minimum 1000000")
  })
  use initial_witness <- result.try(
    verify_authority_config(config, ffi_system_now_ns()),
  )
  use initial_ttl_us <- result.try(
    cap_ttl_to_task_deadline(ttl_us, initial_witness),
  )
  let coord_db_path = case config.authority_paths {
    CanonicalProductionPaths ->
      "/home/an/NAS-setup/uos/var/coordination/tri-agent/coordinator.sqlite3"
    IsolatedTestPaths(_, coord_db) -> coord_db
  }
  case coord_store.open_existing(coord_db_path) {
    Error(err) -> Error(coord_store.error_to_string(err))
    Ok(store) -> {
      let outcome =
        renew_with_open_store(
          store,
          config,
          lease_id,
          initial_ttl_us,
          sequence,
        )
      case coord_store.close(store) {
        Ok(Nil) -> outcome
        Error(err) -> Error("renewal_store_close_failed: " <> coord_store.error_to_string(err))
      }
    }
  }
}

fn cap_ttl_to_task_deadline(
  requested_ttl_us: Int,
  witness: AuthorityWitness,
) -> Result(Int, String) {
  let remaining_task_us =
    { witness.lease_until_ns - ffi_system_now_ns() } / 1000
  let effective_ttl_us = int.min(requested_ttl_us, remaining_task_us)
  case effective_ttl_us >= 1_000_000 {
    True -> Ok(effective_ttl_us)
    False -> Error("capped renewal ttl_us below minimum 1000000")
  }
}

fn renew_with_open_store(
  store: coord_store.Store,
  config: ServiceConfiguration,
  lease_id: String,
  initial_ttl_us: Int,
  sequence: Int,
) -> Result(AuthorityLease, String) {
  use #(revision, refs) <- result.try(
    coord_store.observe(store, fn(state, boot, now) {
      case
        sync.check(
          state,
          config.session_id,
          config.resource_id,
          config.coordinator_epoch,
          boot,
          now,
        )
      {
        Error(reason) -> Error(coord_store.RefusedError(reason))
        Ok(Nil) ->
          case dict.get(state.sessions, config.session_id) {
            Ok(session) -> Ok(#(session.revision, session.refs))
            Error(_) ->
              Error(coord_store.RefusedError(
                "missing coordinator session: " <> config.session_id,
              ))
          }
      }
    })
    |> result.map_error(coord_store.error_to_string),
  )
  let op_digest =
    files.digest(
      lease_id
      <> int.to_string(sequence)
      <> int.to_string(ffi_system_now_ns()),
    )
  use #(_hb_receipt, hb_duplicate) <- result.try(
    coord_store.append(
      store,
      sync.Heartbeat(config.session_id, revision, refs),
      "heartbeat:" <> op_digest,
    )
    |> result.map_error(coord_store.error_to_string),
  )
  use _ <- result.try(case hb_duplicate {
    False -> Ok(Nil)
    True -> Error("refused duplicate heartbeat operation")
  })
  use _ <- result.try(
    coord_store.observe(store, fn(state, boot, now) {
      case
        sync.check(
          state,
          config.session_id,
          config.resource_id,
          config.coordinator_epoch,
          boot,
          now,
        )
      {
        Ok(Nil) -> Ok(Nil)
        Error(reason) -> Error(coord_store.RefusedError(reason))
      }
    })
    |> result.map_error(coord_store.error_to_string),
  )
  use pre_renew_witness <- result.try(
    verify_authority_config(config, ffi_system_now_ns()),
  )
  use renew_ttl_us <- result.try(
    cap_ttl_to_task_deadline(initial_ttl_us, pre_renew_witness),
  )
  use #(renew_receipt, renew_duplicate) <- result.try(
    coord_store.append(
      store,
      sync.Renew(
        config.session_id,
        config.resource_id,
        config.coordinator_epoch,
        renew_ttl_us,
      ),
      "renew:" <> op_digest,
    )
    |> result.map_error(coord_store.error_to_string),
  )
  use _ <- result.try(case renew_duplicate {
    False -> Ok(Nil)
    True -> Error("refused duplicate renew operation")
  })
  let sampled_utc_us = ffi_system_now_ns() / 1000
  use remaining_boot_us <- result.try(
    coord_store.observe(store, fn(state, boot, now) {
      case
        sync.check(
          state,
          config.session_id,
          config.resource_id,
          config.coordinator_epoch,
          boot,
          now,
        )
      {
        Error(reason) -> Error(coord_store.RefusedError(reason))
        Ok(Nil) -> {
          let remaining = renew_receipt.expires_us - now
          case remaining > 0 {
            True -> Ok(remaining)
            False ->
              Error(coord_store.RefusedError(
                "renewed lease already expired on boot clock",
              ))
          }
        }
      }
    })
    |> result.map_error(coord_store.error_to_string),
  )
  use final_witness <- result.try(
    verify_authority_config(config, ffi_system_now_ns()),
  )
  let valid_until_us =
    int.min(
      final_witness.lease_until_ns / 1000,
      sampled_utc_us + remaining_boot_us - 100_000,
    )
  let current_utc_us = ffi_system_now_ns() / 1000
  case valid_until_us > current_utc_us {
    True ->
      Ok(AuthorityLease(
        lease_id,
        config.expected_task_attempt,
        config.coordinator_epoch,
        valid_until_us,
      ))
    False -> Error("renewed authority lease expired after safety margin")
  }
}

/// Active entry: current unit/writer admission plus automatic owned lease maintenance.
/// The caller owns the bounded poll driver; startup itself never performs Telegram HTTP.
pub fn start_active_managed_service(
  config: ServiceConfiguration,
  current_control_path: String,
  expected: codec.WriterRegistration,
  cleanup_receipt: Option(lifecycle.UnitCleanupReceipt),
) -> Result(SupervisedService, String) {
  use svc <- result.try(start_managed_service(config, current_control_path, expected, cleanup_receipt))
  activate_managed_service(svc)
}

fn activate_managed_service(svc: SupervisedService) -> Result(SupervisedService, String) {
  case enable_managed_authority(svc, 30_000_000, 10_000) {
    Error(err) -> abort_managed_start(svc, "managed_authority_activation_failed: " <> err)
    Ok(Nil) -> case poll_rpc.call(svc.actor_subject, 5000, GetManagedStartupState) {
      Error(err) -> abort_managed_start(svc, "managed_activation_state_unavailable: " <> err)
      Ok(state) -> case state.authority, state.authority_revoked {
        Some(_), False -> Ok(svc)
        _, _ -> abort_managed_start(svc, "managed_activation_not_observed")
      }
    }
  }
}

/// Confirm the OTP tree stopped before releasing this exact runtime lease.
/// Unit/cgroup quiescence remains a separate required predecessor recovery proof.
pub fn stop_managed_service(svc: SupervisedService) -> Result(Nil, String) {
  let config = svc.configuration
  use _ <- result.try(case config.resource_id == "runtime:telegram-bridge" {
    True -> Ok(Nil)
    False -> Error("managed_stop_resource_mismatch")
  })
  use _ <- result.try(stop_supervised_service(svc))
  let db = case config.authority_paths {
    CanonicalProductionPaths -> "/home/an/NAS-setup/uos/var/coordination/tri-agent/coordinator.sqlite3"
    IsolatedTestPaths(_, path) -> path
  }
  use handle <- result.try(coord_store.open_existing(db) |> result.map_error(coord_store.error_to_string))
  let released = coord_store.append(handle,
    sync.Release(config.session_id, config.resource_id, config.coordinator_epoch),
    "telegram-stop:" <> files.digest(config.session_id <> ":" <> int.to_string(config.coordinator_epoch) <> ":" <> int.to_string(ffi_system_now_ns())))
    |> result.map_error(coord_store.error_to_string)
  let closed = coord_store.close(handle) |> result.map_error(coord_store.error_to_string)
  use _ <- result.try(closed)
  use #(_, replay) <- result.try(released)
  case replay { False -> Ok(Nil) True -> Error("managed_stop_release_replayed") }
}

fn command_observer_request(config: ServiceConfiguration) -> obs_policy.ObserveRequest {
  obs_policy.ObserveRequest(
    guardian_exe: config.guardian_exe,
    guardian_sha256: config.guardian_sha256,
    observer_exe: config.observer_exe,
    observer_sha256: config.observer_sha256,
    db_path: resolve_sa_plan_db(config.authority_paths),
    plan_id: config.plan_id,
    task_id: obs_policy.NoTask,
    deadline_ms: 5000,
    max_bytes: 262_144,
  )
}

type SpecializedDispatch { RegularDispatch ConversationDispatch MemoryDispatch }

fn specialized_dispatch(state: ServiceState, request_id: String) -> SpecializedDispatch {
  case svc_read_keys(state, [codec.input_key(request_id)]) {
    Ok(#(_, [row])) -> case codec.decode_row_value(row) |> result.try(codec.decode_input_verdict) {
      Ok(#(_, _, _, guard.AcceptedEnvelope(
        directive: guard.PreservedDirective(name, _), callback_query_id: None, ..
      ))) -> case name {
        "/memory" | "/history" | "/messages" -> MemoryDispatch
        "conversational" | "/agy" -> case state.config.conversation {
          ConversationDisabled -> RegularDispatch
          _ -> ConversationDispatch
        }
        _ -> RegularDispatch
      }
      _ -> RegularDispatch
    }
    _ -> RegularDispatch
  }
}

fn conversation_settings(config: ServiceConfiguration) -> Result(#(Int, Int, model.Io), String) {
  use #(limit, timeout, io) <- result.try(case config.conversation {
    ConversationDisabled -> Error("conversation_disabled")
    FreeConversation(limit, timeout) -> Ok(#(limit, timeout, conversation_model.live_io()))
    IsolatedConversation(limit, timeout, io) -> case config.authority_paths {
      IsolatedTestPaths(_, _) -> Ok(#(limit, timeout, io))
      CanonicalProductionPaths -> Error("test_model_io_refused_in_production")
    }
  })
  case limit >= 1 && limit <= 1000 && timeout >= 100 && timeout <= 15_000 {
    True -> Ok(#(limit, timeout, io))
    False -> Error("invalid_conversation_limits")
  }
}

fn conversation_authorize(state: ServiceState) -> Result(Int, String) {
  use witness <- result.try(verify_authority(state, ffi_system_now_utc_us()))
  let task_remaining = { witness.lease_until_ns - ffi_system_now_ns() } / 1_000_000
  let remaining = case state.authority {
    Some(lease) -> int.min(task_remaining, { lease.valid_until_us - ffi_system_now_utc_us() } / 1000)
    None -> 0
  }
  case remaining > 0 {
    True -> Ok(remaining)
    False -> Error("conversation_authority_expired")
  }
}

fn svc_reserve_conversation(
  state: ServiceState, record: ledger.InboxRecord, version: Int,
  sha: String, day: Int, limit: Int,
) -> Result(store.ConversationReservation, store.StoreError) {
  case state.store_worker {
    Some(worker) -> process.call(worker, 5000, fn(reply_to) {
      StoreReserveConversation(state.expected_generation, record, version, sha,
        state.config.worker_id, state.config.service_epoch, day, limit, reply_to)
    })
    None -> store.reserve_conversation(state.config.storage_config,
      state.expected_generation, record, version, sha,
      state.config.worker_id, state.config.service_epoch, day, limit)
  }
}

fn svc_commit_conversation(
  state: ServiceState, reservation: store.ConversationReservation,
  payloads: List(String), reply: Option(String),
) -> Result(store.CommitResultResult, store.StoreError) {
  case state.store_worker {
    Some(worker) -> process.call(worker, 5000, fn(reply_to) {
      StoreCommitConversation(reservation, payloads, reply, reply_to)
    })
    None -> store.commit_conversation_result(reservation, payloads, reply)
  }
}

fn conversation_store_failure(state: ServiceState, err: store.StoreError) -> ServiceError {
  case err {
    store.StoreUncertainApply(pending) -> ServiceError(
      ServiceState(..state, pending_operation: Some(pending),
        writer_state: lifecycle.ServiceWriterHold("store_uncertain_apply_pending")),
      "store_uncertain_apply_pending")
    _ -> ServiceError(
      ServiceState(..state, writer_state: lifecycle.ServiceWriterHold("conversation_store_failed")),
      "conversation_store_failed")
  }
}

fn finish_conversation(
  state: ServiceState, original: ledger.InboxRecord, processing_version: Int,
  committed: store.CommitResultResult,
) -> Result(#(ServiceState, ServiceStepResult), ServiceError) {
  let ready = committed.inbox_record
  case committed.chunks {
    [] -> Error(ServiceError(state, "conversation_result_has_no_chunks"))
    chunks -> drain_chunks(state, original, ready, processing_version + 1,
      files.digest(codec.encode_inbox_record(ready)), committed.receipt.generation,
      chunks, [], None)
  }
}

fn execute_conversation_dispatch(
  state: ServiceState, record: ledger.InboxRecord, version: Int, sha: String,
) -> Result(#(ServiceState, ServiceStepResult), ServiceError) {
  use #(limit, timeout, io) <- result.try(conversation_settings(state.config)
    |> result.map_error(fn(reason) { ServiceError(state, reason) }))
  use observed <- result.try(checked_clock.observe()
    |> result.map_error(fn(_) { ServiceError(state, "conversation_clock_refused") }))
  use day <- result.try(conversation.utc_day(observed.sample.observed.utc_us / 1000)
    |> result.map_error(fn(reason) { ServiceError(state, reason) }))
  use _ <- result.try(conversation_authorize(state)
    |> result.map_error(fn(reason) { ServiceError(state, reason) }))
  case svc_reserve_conversation(state, record, version, sha, day, limit) {

    Error(store.StoreCapacityExceeded("daily_request_budget_exhausted")) ->
      reply_without_reservation(state, record, version, sha,
        "Daily conversation request limit reached. Please try again tomorrow.")
    Error(store.StoreInvariantError("not_a_conversation_prompt"))
    | Error(store.StoreInvariantError("invalid_conversation_prompt")) ->
      reply_without_reservation(state, record, version, sha,
        "Use /agy <message> or send a short text message.")
    Error(err) -> Error(conversation_store_failure(state, err))
    Ok(reservation) -> {
      let reserved_state = ServiceState(..state,
        expected_generation: store.conversation_generation(reservation))
      let outcome = conversation_model.run(reservation, io,
        fn() { conversation_authorize(reserved_state) }, timeout)
      use _ <- result.try(conversation_authorize(reserved_state)
        |> result.map_error(fn(reason) { ServiceError(reserved_state, reason) }))
      let #(payloads, successful) = case outcome {
        Ok(execution) -> {
          let parts = chunk_payload_utf8(execution.reply)
          case string.join(parts, "") == execution.reply
            && list.all(parts, fn(p) { string.byte_size(p) <= max_chunk_bytes }) {
            True -> #(parts, Some(execution.reply))
            False -> #(["Assistant reply could not be delivered safely. Please try a shorter request."], None)
          }
        }
        Error(_) -> #(["Assistant unavailable for this request. Please try again later."], None)
      }
      use committed <- result.try(svc_commit_conversation(reserved_state, reservation, payloads, successful)
        |> result.map_error(fn(err) { conversation_store_failure(reserved_state, err) }))
      finish_conversation(reserved_state, record, version, committed)
    }
  }
}

fn reply_without_reservation(
  state: ServiceState, record: ledger.InboxRecord, version: Int,
  sha: String, message: String,
) -> Result(#(ServiceState, ServiceStepResult), ServiceError) {
  use _ <- result.try(conversation_authorize(state)
    |> result.map_error(fn(reason) { ServiceError(state, reason) }))
  use committed <- result.try(svc_commit_result(state, state.config.bot_id,
    "op-result-" <> record.request_id, state.expected_generation,
    record, version, sha, [message],
    state.config.worker_id, state.config.service_epoch)
    |> result.map_error(fn(err) { conversation_store_failure(state, err) }))
  finish_conversation(state, record, version, committed)
}

fn execute_memory_dispatch(
  state: ServiceState, record: ledger.InboxRecord, version: Int, sha: String,
) -> Result(#(ServiceState, ServiceStepResult), ServiceError) {
  use _ <- result.try(conversation_authorize(state)
    |> result.map_error(fn(reason) { ServiceError(state,reason) }))
  use observation <- result.try(case state.store_worker {
    Some(worker) -> process.call(worker,5000,fn(reply_to) {
      StorePrepareMemory(state.expected_generation,record,version,sha,
        state.config.worker_id,state.config.service_epoch,reply_to)
    })
    None -> store.prepare_memory_command(state.config.storage_config,
      state.expected_generation,record,version,sha,
      state.config.worker_id,state.config.service_epoch)
  } |> result.map_error(fn(err) { conversation_store_failure(state,err) }))
  let text = store.memory_reply(observation)
  let payloads = chunk_payload_utf8(text)
  use _ <- result.try(case string.join(payloads,"") == text
    && list.all(payloads,fn(p) { string.byte_size(p) <= max_chunk_bytes }) {
    True -> Ok(Nil)
    False -> Error(ServiceError(state,"memory_reply_chunking_failed"))
  })
  use _ <- result.try(conversation_authorize(state)
    |> result.map_error(fn(reason) { ServiceError(state,reason) }))
  use committed <- result.try(case state.store_worker {
    Some(worker) -> process.call(worker,5000,fn(reply_to) {
      StoreCommitMemory(observation,payloads,reply_to)
    })
    None -> store.commit_memory_result(observation,payloads)
  } |> result.map_error(fn(err) { conversation_store_failure(state,err) }))
  finish_conversation(state,record,version,committed)
}
