//// High-assurance durable storage consumer for Telegram bot runtime v2.
//// Spec: uos.telegram-durable-store-corrected-development-spec.v1
//// Wire: uos.telegram-store-wire-v4.v1

import cepaf_gleam/harness/telegram_conversation as conv
import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_delivery_ledger as ledger
import cepaf_gleam/harness/telegram_lifecycle_adapter as lifecycle
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_store_codec as codec
import cepaf_gleam/harness/telegram_store_transport as transport
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub opaque type CleanupProof {
  CleanupProof(
    guardian_sha256: String,
    worker_sha256: String,
    database: String,
    canonical_request: String,
    exit_status: Int,
    observed_at_us: Int,
  )
}

pub opaque type PendingOperation {
  PendingOperation(
    bot_id: Int,
    operation_id: String,
    expected_digest: String,
    expected_generation: Int,
    expected_summary_json: String,
    canonical_request: String,
    cleanup_proof: Option(CleanupProof),
    error_detail: String,
  )
}

pub type StoreError {
  StoreTransportError(transport.TransportError)
  StoreBackendError(code: String)
  StoreDecodeError(reason: String)
  StoreInvariantError(reason: String)
  StoreCapacityExceeded(reason: String)
  StoreUncertain(reason: String)
  StoreUncertainApply(pending: PendingOperation)
}

pub type ReconciledPending {
  PendingCommitted(receipt: codec.Receipt)
  PendingAbsent(proof: CleanupProof)
  PendingConflict(expected_digest: String, found_receipt: codec.Receipt)
  PendingUnknown(reason: String)
}

pub type ReconciliationResult {
  ReconciledCommitted(receipt: codec.Receipt)
  ReconciledAbsent
  ReconciledCollision(receipt: codec.Receipt)
  ReconciledUnknown(reason: String)
}

pub fn pending_bot_id(pending: PendingOperation) -> Int {
  pending.bot_id
}

pub fn pending_operation_id(pending: PendingOperation) -> String {
  pending.operation_id
}

pub fn pending_expected_digest(pending: PendingOperation) -> String {
  pending.expected_digest
}

pub fn pending_expected_generation(pending: PendingOperation) -> Int {
  pending.expected_generation
}

pub fn pending_expected_summary_json(pending: PendingOperation) -> String {
  pending.expected_summary_json
}

pub fn pending_canonical_request(pending: PendingOperation) -> String {
  pending.canonical_request
}

pub fn pending_has_cleanup_proof(pending: PendingOperation) -> Bool {
  option.is_some(pending.cleanup_proof)
}

pub fn pending_cleanup_proof(
  pending: PendingOperation,
) -> Option(CleanupProof) {
  pending.cleanup_proof
}

pub fn pending_error_detail(pending: PendingOperation) -> String {
  pending.error_detail
}

pub fn cleanup_proof_exit_status(proof: CleanupProof) -> Int {
  proof.exit_status
}

pub fn cleanup_proof_observed_at_us(proof: CleanupProof) -> Int {
  proof.observed_at_us
}

pub fn cleanup_proof_database(proof: CleanupProof) -> String {
  proof.database
}

pub fn cleanup_proof_canonical_request(proof: CleanupProof) -> String {
  proof.canonical_request
}

@external(erlang, "telegram_store_transport_ffi", "request_config_with_cleanup")
fn ffi_request_with_cleanup(
  config: transport.LocalConfiguration,
  body: String,
) -> #(Result(String, String), Option(#(Int, Int)))

@external(erlang, "telegram_store_transport_ffi", "config_database")
fn ffi_config_database(config: transport.LocalConfiguration) -> String

@external(erlang, "telegram_store_transport_ffi", "config_guardian_hash")
fn ffi_config_guardian_hash(config: transport.LocalConfiguration) -> String

@external(erlang, "telegram_store_transport_ffi", "config_worker_hash")
fn ffi_config_worker_hash(config: transport.LocalConfiguration) -> String

pub fn verify_cleanup_proof(
  proof: CleanupProof,
  config: transport.LocalConfiguration,
  expected_canonical_request: String,
) -> Bool {
  proof.guardian_sha256 == ffi_config_guardian_hash(config)
  && proof.worker_sha256 == ffi_config_worker_hash(config)
  && proof.database == ffi_config_database(config)
  && proof.canonical_request == expected_canonical_request
}

pub type TransportObservation {
  TransportObservation(
    body_result: Result(String, transport.TransportError),
    cleanup_proof: Option(CleanupProof),
  )
}

pub fn exchange_with_cleanup(
  config: transport.LocalConfiguration,
  canonical_request: String,
) -> TransportObservation {
  case string.byte_size(canonical_request) {
    0 ->
      TransportObservation(
        body_result: Error(transport.InputBound),
        cleanup_proof: None,
      )
    n if n > transport.max_body_bytes ->
      TransportObservation(
        body_result: Error(transport.InputBound),
        cleanup_proof: None,
      )
    _ -> {
      let #(raw_res, raw_witness) =
        ffi_request_with_cleanup(config, canonical_request)
      let body_res =
        raw_res
        |> result.map_error(fn(code) {
          case code {
            "transport_input_bound" -> transport.InputBound
            "transport_configuration_or_spawn" -> transport.ConfigurationOrSpawn
            "transport_cleanup_unknown" -> transport.CleanupUnknown
            _ -> transport.Uncertain
          }
        })
      let proof = case raw_witness {
        Some(#(exit_code, observed_at_us)) ->
          case exit_code == 0 || exit_code == 124 || exit_code == 125 {
            True ->
              Some(CleanupProof(
                guardian_sha256: ffi_config_guardian_hash(config),
                worker_sha256: ffi_config_worker_hash(config),
                database: ffi_config_database(config),
                canonical_request: canonical_request,
                exit_status: exit_code,
                observed_at_us: observed_at_us,
              ))
            False -> None
          }
        None -> None
      }
      TransportObservation(body_result: body_res, cleanup_proof: proof)
    }
  }
}

pub type CommitPrefixResult {
  CommitPrefixResult(
    receipt: codec.Receipt,
    watermark: ledger.Watermark,
    admitted_records: List(ledger.InboxRecord),
    remaining_updates: List(guard.IngressVerdict),
  )
}

pub type CommitResultResult {
  CommitResultResult(
    receipt: codec.Receipt,
    inbox_record: ledger.InboxRecord,
    chunks: List(ledger.OutboxChunk),
  )
}

fn wrap_transport(
  res: Result(String, transport.TransportError),
) -> Result(String, StoreError) {
  result.map_error(res, fn(err) {
    case err {
      transport.Uncertain -> StoreUncertain("transport_uncertain")
      _ -> StoreTransportError(err)
    }
  })
}

fn execute_apply(
  config: transport.LocalConfiguration,
  bot_id: Int,
  operation_id: String,
  expected_generation: Int,
  read_set: List(codec.ReadSetAssertion),
  changes: List(codec.Change),
  res_delta: codec.ReservationDelta,
  summary_json: String,
) -> Result(codec.ApplyResult, StoreError) {
  let digest =
    codec.compute_apply_digest(
      bot_id,
      operation_id,
      expected_generation,
      read_set,
      changes,
      res_delta,
      summary_json,
    )

  let apply_req =
    codec.encode_apply_command(
      bot_id,
      operation_id,
      digest,
      expected_generation,
      read_set,
      changes,
      res_delta,
      summary_json,
      None,
    )

  let obs = exchange_with_cleanup(config, apply_req)
  use apply_resp <- result.try(case obs.body_result {
    Ok(resp) -> Ok(resp)
    Error(err) -> {
      let pending =
        PendingOperation(
          bot_id: bot_id,
          operation_id: operation_id,
          expected_digest: digest,
          expected_generation: expected_generation,
          expected_summary_json: summary_json,
          canonical_request: apply_req,
          cleanup_proof: obs.cleanup_proof,
          error_detail: case err {
            transport.Uncertain -> "transport_uncertain"
            transport.CleanupUnknown -> "transport_cleanup_unknown"
            transport.ConfigurationOrSpawn -> "transport_configuration_or_spawn"
            transport.InputBound -> "transport_input_bound"
          },
        )
      case err {
        transport.Uncertain -> Error(StoreUncertainApply(pending))
        transport.CleanupUnknown -> Error(StoreUncertainApply(pending))
        _ -> Error(StoreTransportError(err))
      }
    }
  })
  use apply_res <- result.try(
    case codec.decode_apply_response_discriminated(apply_resp) {
      codec.DecodedApplySuccess(res) -> Ok(res)
      codec.DecodedApplyRefusal("commit_uncertain") -> {
        let pending =
          PendingOperation(
            bot_id: bot_id,
            operation_id: operation_id,
            expected_digest: digest,
            expected_generation: expected_generation,
            expected_summary_json: summary_json,
            canonical_request: apply_req,
            cleanup_proof: obs.cleanup_proof,
            error_detail: "commit_uncertain",
          )
        Error(StoreUncertainApply(pending))
      }
      codec.DecodedApplyRefusal(code) -> Error(StoreBackendError(code))
      codec.DecodedApplyDecodeError(reason) -> {
        let pending =
          PendingOperation(
            bot_id: bot_id,
            operation_id: operation_id,
            expected_digest: digest,
            expected_generation: expected_generation,
            expected_summary_json: summary_json,
            canonical_request: apply_req,
            cleanup_proof: obs.cleanup_proof,
            error_detail: reason,
          )
        Error(StoreUncertainApply(pending))
      }
    },
  )

  let receipt = apply_res.receipt
  let field_mismatch =
    receipt.operation_id != operation_id
    || receipt.request_digest != digest
    || receipt.summary_json != summary_json
    || receipt.generation <= 0

  let generation_mismatch = case apply_res.replay {
    False -> receipt.generation != expected_generation + 1
    True -> receipt.generation > expected_generation + 1
  }

  case field_mismatch, generation_mismatch {
    True, _ -> {
      let pending =
        PendingOperation(
          bot_id: bot_id,
          operation_id: operation_id,
          expected_digest: digest,
          expected_generation: expected_generation,
          expected_summary_json: summary_json,
          canonical_request: apply_req,
          cleanup_proof: obs.cleanup_proof,
          error_detail: "apply_receipt_field_mismatch",
        )
      Error(StoreUncertainApply(pending))
    }
    False, True -> {
      let pending =
        PendingOperation(
          bot_id: bot_id,
          operation_id: operation_id,
          expected_digest: digest,
          expected_generation: expected_generation,
          expected_summary_json: summary_json,
          canonical_request: apply_req,
          cleanup_proof: obs.cleanup_proof,
          error_detail: case apply_res.replay {
            False -> "apply_receipt_generation_mismatch"
            True -> "apply_replay_generation_invalid"
          },
        )
      Error(StoreUncertainApply(pending))
    }
    False, False -> Ok(apply_res)
  }
}

// -----------------------------------------------------------------------------
// Initialization & Resumable Bootstrap
// -----------------------------------------------------------------------------

pub fn initialize_store(
  config: transport.LocalConfiguration,
  bot_id: Int,
) -> Result(Int, StoreError) {
  case guard.valid_positive_id(bot_id) {
    False -> Error(StoreInvariantError("invalid_bot_id"))
    True -> {
      let init_req = codec.encode_initialize_new_command(bot_id, None)
      let init_res = case wrap_transport(transport.exchange(config, init_req)) {
        Ok(resp) ->
          codec.decode_initialize_new_response(resp)
          |> result.map_error(StoreBackendError)
        Error(err) -> Error(err)
      }

      case init_res {
        Ok(gen1) -> bootstrap_metadata(config, bot_id, gen1)
        Error(StoreBackendError("db_already_exists")) ->
          resume_bootstrap(config, bot_id)
        Error(err) -> Error(err)
      }
    }
  }
}


/// Evidence of successful exclusive native creation, bound to its observed inode
/// and incarnation cookie. This is not a live-writer or effect-authority permit.
pub opaque type FreshWriterStore {
  FreshWriterStore(
    config: transport.LocalConfiguration,
    bot_id: Int,
    generation: Int,
    incarnation: String,
  )
}

pub fn fresh_writer_store_incarnation(proof: FreshWriterStore) -> String {
  proof.incarnation
}

/// First stage: create exclusively, then measure the actual file identity.
/// An existing or partially created file never yields this proof.
pub fn begin_new_writer_store(
  config: transport.LocalConfiguration,
  bot_id: Int,
) -> Result(FreshWriterStore, StoreError) {
  use _ <- result.try(case guard.valid_positive_id(bot_id) {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("invalid_bot_id"))
  })
  let request = codec.encode_initialize_new_command(bot_id, None)
  use response <- result.try(wrap_transport(transport.exchange(config, request)))
  use generation <- result.try(
    codec.decode_initialize_new_response(response)
    |> result.map_error(StoreBackendError),
  )
  use _ <- result.try(case generation == 1 {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("fresh_store_generation_invalid"))
  })
  use incarnation <- result.try(
    lifecycle.compute_store_incarnation(ffi_config_database(config))
    |> result.map_error(StoreInvariantError),
  )
  Ok(FreshWriterStore(config, bot_id, generation, incarnation))
}

/// Second stage: callers can now construct the external control registration
/// from the real store/unit identity. This function commits storage metadata;
/// live control binding, cleanup, task/runtime fencing and single-start ownership
/// are separate obligations. Replay of identical metadata is not new admission.
/// Losing the proof after creation requires explicit incomplete-store recovery.
pub fn finish_new_writer_store(
  proof: FreshWriterStore,
  registration: codec.WriterRegistration,
) -> Result(Int, StoreError) {
  use raw <- result.try(
    codec.encode_writer_registration(registration)
    |> result.map_error(StoreInvariantError),
  )
  use _ <- result.try(case registration.service_epoch == 1 {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("first_writer_requires_epoch_one"))
  })
  use _ <- result.try(case registration.bot_id == proof.bot_id {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("fresh_writer_bot_mismatch"))
  })
  use current_incarnation <- result.try(
    lifecycle.compute_store_incarnation(ffi_config_database(proof.config))
    |> result.map_error(StoreInvariantError),
  )
  use _ <- result.try(case
    current_incarnation == proof.incarnation
    && registration.store_incarnation_id == proof.incarnation
  {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("fresh_writer_incarnation_mismatch"))
  })
  bootstrap_metadata_with_writer(proof.config, proof.bot_id, proof.generation, [
    codec.Change(
      key: codec.writer_registration_key(),
      expected_version: 0,
      expected_sha256: "",
      new_value_base64: codec.encode_canonical_base64(raw),
    ),
  ])
}

fn resume_bootstrap(
  config: transport.LocalConfiguration,
  bot_id: Int,
) -> Result(Int, StoreError) {
  use #(gen, rows) <- result.try(
    read_keys(config, [
      codec.bot_identity_key(),
      codec.watermark_key(),
    ]),
  )
  let bot_row = list.find(rows, fn(r) { r.key == codec.bot_identity_key() })
  let wm_row = list.find(rows, fn(r) { r.key == codec.watermark_key() })

  case bot_row, wm_row {
    Ok(b), Ok(w) if b.exists && w.exists -> {
      use raw_bot <- result.try(
        codec.decode_canonical_base64(b.canonical_value_base64)
        |> result.map_error(StoreDecodeError),
      )
      use stored_id <- result.try(
        codec.decode_bot_identity_value(raw_bot)
        |> result.map_error(StoreDecodeError),
      )
      case stored_id == bot_id {
        True -> Ok(gen)
        False -> Error(StoreInvariantError("bot_id_mismatch"))
      }
    }
    _, _ -> bootstrap_metadata(config, bot_id, gen)
  }
}

fn bootstrap_metadata(
  config: transport.LocalConfiguration,
  bot_id: Int,
  gen: Int,
) -> Result(Int, StoreError) {
  bootstrap_metadata_with_writer(config, bot_id, gen, [])
}

fn bootstrap_metadata_with_writer(
  config: transport.LocalConfiguration,
  bot_id: Int,
  gen: Int,
  writer_changes: List(codec.Change),
) -> Result(Int, StoreError) {
  let bot_id_val = codec.encode_bot_identity_value(bot_id)
  let wm_val = codec.encode_watermark_value(ledger.Watermark(0))

  let changes = [
    codec.Change(
      key: codec.bot_identity_key(),
      expected_version: 0,
      expected_sha256: "",
      new_value_base64: codec.encode_canonical_base64(bot_id_val),
    ),
    codec.Change(
      key: codec.watermark_key(),
      expected_version: 0,
      expected_sha256: "",
      new_value_base64: codec.encode_canonical_base64(wm_val),
    ),
  ]

  let changes = list.append(changes, writer_changes)
  let res_delta = codec.ReservationDelta(rows: 0, receipts: 0)
  let summary_json =
    json.object([
      #("op", json.string("bootstrap_init")),
      #("bot_id", json.int(bot_id)),
    ])
    |> json.to_string

  let op_id = "op-bootstrap-" <> int.to_string(bot_id)
  use apply_res <- result.try(execute_apply(
    config,
    bot_id,
    op_id,
    gen,
    [],
    changes,
    res_delta,
    summary_json,
  ))
  Ok(apply_res.receipt.generation)
}

// -----------------------------------------------------------------------------
// Read Queries
// -----------------------------------------------------------------------------

pub fn read_keys(
  config: transport.LocalConfiguration,
  keys: List(String),
) -> Result(#(Int, List(codec.RowResult)), StoreError) {
  case keys == [] || list.length(keys) > codec.max_read_keys {
    True -> Error(StoreInvariantError("read_keys_bound_exceeded"))
    False -> {
      let unique_req_keys = list.unique(keys)
      case list.length(unique_req_keys) == list.length(keys) {
        False -> Error(StoreInvariantError("duplicate_requested_keys"))
        True -> {
          let req = codec.encode_read_keys_command(keys, None)
          use resp <- result.try(
            wrap_transport(transport.exchange(config, req)),
          )
          use #(gen, rows) <- result.try(
            codec.decode_read_keys_response(resp)
            |> result.map_error(StoreBackendError),
          )
          use _ <- result.try(case gen > 0 {
            True -> Ok(Nil)
            False -> Error(StoreInvariantError("non_positive_generation"))
          })
          use _ <- result.try(case list.length(rows) == list.length(keys) {
            True -> Ok(Nil)
            False -> Error(StoreInvariantError("read_keys_count_mismatch"))
          })
          let returned_keys = list.map(rows, fn(r) { r.key })
          use _ <- result.try(
            case list.length(list.unique(returned_keys)) == list.length(rows) {
              True -> Ok(Nil)
              False ->
                Error(StoreInvariantError("read_keys_duplicate_returned_rows"))
            },
          )
          use _ <- result.try(
            case list.all(rows, fn(r) { list.contains(keys, r.key) }) {
              True -> Ok(Nil)
              False ->
                Error(StoreInvariantError("read_keys_unrequested_key_returned"))
            },
          )
          use _ <- result.try(
            list.try_map(rows, fn(r) {
              case r.exists {
                False ->
                  case
                    r.version == 0
                    && r.sha256 == ""
                    && r.canonical_value_base64 == ""
                  {
                    True -> Ok(Nil)
                    False ->
                      Error(StoreInvariantError("invalid_absent_row_fields"))
                  }
                True -> {
                  case r.version > 0 && guard.valid_digest(r.sha256) {
                    False ->
                      Error(StoreInvariantError("invalid_present_row_fields"))
                    True -> {
                      use raw <- result.try(
                        codec.decode_canonical_base64(r.canonical_value_base64)
                        |> result.map_error(StoreDecodeError),
                      )
                      case files.digest(raw) == r.sha256 {
                        True -> Ok(Nil)
                        False ->
                          Error(StoreInvariantError(
                            "corrupt_row_canonical_hash",
                          ))
                      }
                    }
                  }
                }
              }
            }),
          )
          Ok(#(gen, rows))
        }
      }
    }
  }
}

pub fn read_watermark(
  config: transport.LocalConfiguration,
) -> Result(#(ledger.Watermark, Int, String), StoreError) {
  use #(_, rows) <- result.try(read_keys(config, [codec.watermark_key()]))
  case rows {
    [row] -> {
      use validated <- result.try(
        codec.validate_row_result(row)
        |> result.map_error(StoreInvariantError),
      )
      case validated.exists {
        False -> Error(StoreInvariantError("watermark_row_missing"))
        True -> {
          use raw <- result.try(
            codec.decode_row_value(validated)
            |> result.map_error(StoreDecodeError),
          )
          use wm <- result.try(
            codec.decode_watermark_value(raw)
            |> result.map_error(StoreDecodeError),
          )
          Ok(#(wm, validated.version, validated.sha256))
        }
      }
    }
    _ -> Error(StoreInvariantError("watermark_query_failed"))
  }
}

pub fn read_bot_identity(
  config: transport.LocalConfiguration,
) -> Result(#(Int, Int, String), StoreError) {
  use #(_, rows) <- result.try(read_keys(config, [codec.bot_identity_key()]))
  case rows {
    [row] -> {
      use validated <- result.try(
        codec.validate_row_result(row)
        |> result.map_error(StoreInvariantError),
      )
      case validated.exists {
        False -> Error(StoreInvariantError("bot_identity_row_missing"))
        True -> {
          use raw <- result.try(
            codec.decode_row_value(validated)
            |> result.map_error(StoreDecodeError),
          )
          use bot_id <- result.try(
            codec.decode_bot_identity_value(raw)
            |> result.map_error(StoreDecodeError),
          )
          Ok(#(bot_id, validated.version, validated.sha256))
        }
      }
    }
    _ -> Error(StoreInvariantError("bot_identity_query_failed"))
  }
}

pub fn read_inbox_index(
  config: transport.LocalConfiguration,
  limit: Int,
  after_key: Option(String),
) -> Result(#(Int, List(String)), StoreError) {
  case limit <= 0 || limit > codec.max_inbox_index_limit {
    True -> Error(StoreInvariantError("invalid_inbox_index_limit"))
    False -> {
      let req = codec.encode_read_inbox_index_command(limit, after_key, None)
      use resp <- result.try(wrap_transport(transport.exchange(config, req)))
      codec.decode_read_inbox_index_response(resp)
      |> result.map_error(StoreBackendError)
    }
  }
}

pub fn read_inbox_records(
  config: transport.LocalConfiguration,
  limit: Int,
  after_key: Option(String),
) -> Result(#(Int, List(#(ledger.InboxRecord, Int, String))), StoreError) {
  use #(index_gen, keys) <- result.try(read_inbox_index(
    config,
    limit,
    after_key,
  ))
  case keys {
    [] -> Ok(#(index_gen, []))
    _ -> {
      use #(read_gen, rows) <- result.try(read_keys(config, keys))
      use _ <- result.try(case index_gen == read_gen {
        True -> Ok(Nil)
        False ->
          Error(StoreInvariantError("concurrent_mutation_during_index_read"))
      })
      let records =
        list.try_map(rows, fn(r) {
          use raw <- result.try(
            codec.decode_row_value(r)
            |> result.map_error(StoreDecodeError),
          )
          use rec <- result.try(
            codec.decode_inbox_record(raw)
            |> result.map_error(StoreDecodeError),
          )
          Ok(#(rec, r.version, r.sha256))
        })
      case records {
        Ok(rs) -> Ok(#(read_gen, rs))
        Error(err) -> Error(err)
      }
    }
  }
}

pub fn lookup_operation(
  config: transport.LocalConfiguration,
  operation_id: String,
) -> Result(codec.LookupResult, StoreError) {
  case
    string.byte_size(operation_id) == 0
    || string.byte_size(operation_id) > codec.max_operation_id_bytes
  {
    True -> Error(StoreInvariantError("invalid_operation_id"))
    False -> {
      let req = codec.encode_lookup_operation_command(operation_id, None)
      use resp <- result.try(wrap_transport(transport.exchange(config, req)))
      use lookup_res <- result.try(
        codec.decode_lookup_operation_response(resp)
        |> result.map_error(StoreBackendError),
      )
      case lookup_res.found, lookup_res.receipt {
        True, Some(receipt) ->
          case receipt.operation_id == operation_id {
            True -> Ok(lookup_res)
            False -> Error(StoreInvariantError("lookup_operation_id_mismatch"))
          }
        True, None -> Error(StoreInvariantError("corrupt_lookup_result"))
        False, _ -> Ok(lookup_res)
      }
    }
  }
}

pub fn reconcile_uncertain(
  config: transport.LocalConfiguration,
  operation_id: String,
  expected_digest: String,
) -> Result(ReconciliationResult, StoreError) {
  reconcile_uncertain_quiesced(config, operation_id, expected_digest, False)
}

pub fn reconcile_uncertain_quiesced(
  config: transport.LocalConfiguration,
  operation_id: String,
  expected_digest: String,
  _writer_quiesced: Bool,
) -> Result(ReconciliationResult, StoreError) {
  use lookup <- result.try(lookup_operation(config, operation_id))
  case lookup.found {
    False -> Ok(ReconciledUnknown("writer_quiescence_unproven"))
    True ->
      case lookup.receipt {
        None -> Error(StoreInvariantError("corrupt_lookup_result"))
        Some(receipt) ->
          case receipt.request_digest == expected_digest {
            True -> Ok(ReconciledCommitted(receipt))
            False -> Ok(ReconciledCollision(receipt))
          }
      }
  }
}

pub fn reconcile_pending(
  config: transport.LocalConfiguration,
  pending: PendingOperation,
) -> Result(ReconciledPending, StoreError) {
  case pending.cleanup_proof {
    None -> Ok(PendingUnknown("writer_quiescence_unproven"))
    Some(proof) -> {
      case verify_cleanup_proof(proof, config, pending.canonical_request) {
        False ->
          Error(StoreInvariantError("quiescence_witness_binding_mismatch"))
        True -> {
          use lookup <- result.try(lookup_operation(
            config,
            pending.operation_id,
          ))
          case lookup.found {
            False -> Ok(PendingAbsent(proof))
            True ->
              case lookup.receipt {
                None -> Error(StoreInvariantError("corrupt_lookup_result"))
                Some(receipt) -> {
                  let is_exact_match =
                    receipt.operation_id == pending.operation_id
                    && receipt.request_digest == pending.expected_digest
                    && receipt.summary_json == pending.expected_summary_json
                    && receipt.generation == pending.expected_generation + 1
                  case is_exact_match {
                    True -> Ok(PendingCommitted(receipt))
                    False ->
                      Ok(PendingConflict(pending.expected_digest, receipt))
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
// Prefix Ingestion Transaction
// -----------------------------------------------------------------------------

fn get_update_id(v: guard.IngressVerdict) -> Int {
  case v {
    guard.AcceptedEnvelope(update_id: uid, ..) -> uid
    guard.RejectedUpdate(update_id: uid, ..) -> uid
    guard.UnidentifiedRejection(_) -> -1
  }
}

fn get_verdict_bot_id(v: guard.IngressVerdict) -> Int {
  case v {
    guard.AcceptedEnvelope(bot_id: b, ..) -> b
    guard.RejectedUpdate(bot_id: b, ..) -> b
    guard.UnidentifiedRejection(_) -> -1
  }
}

fn verdicts_match(a: guard.IngressVerdict, b: guard.IngressVerdict) -> Bool {
  case a, b {
    guard.AcceptedEnvelope(u1, m1, c1, usr1, h1, t1, d1, b1, cb1),
      guard.AcceptedEnvelope(u2, m2, c2, usr2, h2, t2, d2, b2, cb2)
    ->
      u1 == u2
      && m1 == m2
      && c1 == c2
      && usr1 == usr2
      && h1 == h2
      && t1 == t2
      && d1 == d2
      && b1 == b2
      && cb1 == cb2
    guard.RejectedUpdate(u1, b1, h1, r1), guard.RejectedUpdate(u2, b2, h2, r2)
    -> u1 == u2 && b1 == b2 && h1 == h2 && r1 == r2
    _, _ -> False
  }
}

fn group_equal_id_updates(
  updates: List(guard.IngressVerdict),
) -> List(List(guard.IngressVerdict)) {
  case updates {
    [] -> []
    [first, ..rest] -> {
      let uid = get_update_id(first)
      let same = list.take_while(rest, fn(u) { get_update_id(u) == uid })
      let remaining = list.drop(rest, list.length(same))
      [[first, ..same], ..group_equal_id_updates(remaining)]
    }
  }
}

fn validate_verdict_structure(
  v: guard.IngressVerdict,
) -> Result(Nil, StoreError) {
  case v {
    guard.AcceptedEnvelope(
      update_id: uid,
      message_id: mid,
      chat_id: cid,
      user_id: uid_usr,
      text_hash: hash,
      raw_text: raw_text,
      directive: directive,
      bot_id: bot,
      callback_query_id: cb_id,
    ) -> {
      case
        guard.valid_update_id(uid)
        && guard.valid_positive_id(mid)
        && guard.valid_chat_id(cid)
        && guard.valid_positive_id(uid_usr)
        && guard.valid_digest(hash)
        && guard.valid_text(raw_text)
        && files.digest(raw_text) == hash
        && guard.valid_positive_id(bot)
        && directive == guard.classify_directive(raw_text)
        && case cb_id {
          None -> True
          Some(id) -> id != "" && string.byte_size(id) <= 128
        }
      {
        True -> Ok(Nil)
        False ->
          Error(StoreInvariantError("invalid_accepted_envelope_structure"))
      }
    }
    guard.RejectedUpdate(
      update_id: uid,
      bot_id: bot,
      envelope_hash: hash,
      reason: r,
    ) -> {
      case
        guard.valid_update_id(uid)
        && guard.valid_positive_id(bot)
        && guard.valid_digest(hash)
        && r != ""
        && string.byte_size(r) <= 128
      {
        True -> Ok(Nil)
        False -> Error(StoreInvariantError("invalid_rejected_update_structure"))
      }
    }
    guard.UnidentifiedRejection(_) ->
      Error(StoreInvariantError("unidentified_update_cannot_advance_offset"))
  }
}

fn validate_group_identity(
  group: List(guard.IngressVerdict),
  bot_id: Int,
) -> Result(guard.IngressVerdict, StoreError) {
  case group {
    [] -> Error(StoreInvariantError("empty_update_group"))
    [representative, ..rest] -> {
      let rep_uid = get_update_id(representative)
      use _ <- result.try(
        case
          guard.valid_update_id(rep_uid)
          && get_verdict_bot_id(representative) == bot_id
          && guard.valid_positive_id(bot_id)
        {
          True -> Ok(Nil)
          False ->
            case rep_uid < 0 {
              True ->
                Error(StoreInvariantError(
                  "unidentified_update_cannot_advance_offset",
                ))
              False -> Error(StoreInvariantError("group_bot_id_mismatch"))
            }
        },
      )
      use _ <- result.try(validate_verdict_structure(representative))
      use _ <- result.try(list.try_map(rest, validate_verdict_structure))
      let all_match =
        list.all(rest, fn(u) {
          verdicts_match(representative, u) && get_verdict_bot_id(u) == bot_id
        })
      case all_match {
        True -> Ok(representative)
        False -> Error(StoreInvariantError("batch_identity_collision"))
      }
    }
  }
}

pub fn commit_prefix(
  config: transport.LocalConfiguration,
  bot_id: Int,
  operation_id: String,
  expected_generation: Int,
  current_wm: ledger.Watermark,
  current_wm_version: Int,
  current_wm_sha: String,
  updates: List(guard.IngressVerdict),
  now_ms: Int,
) -> Result(CommitPrefixResult, StoreError) {
  use _ <- result.try(
    case
      updates != []
      && list.length(updates) <= ledger.max_batch_size
      && current_wm.last_committed_offset >= 0
      && current_wm.last_committed_offset <= guard.max_update_id + 1
      && current_wm_version > 0
      && now_ms > 0
      && now_ms <= guard.max_identity
    {
      True -> Ok(Nil)
      False -> Error(StoreInvariantError("batch_or_watermark_bound"))
    },
  )

  let expected_wm_val = codec.encode_watermark_value(current_wm)
  let expected_wm_sha = files.digest(expected_wm_val)
  use _ <- result.try(case expected_wm_sha == current_wm_sha {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("watermark_hash_mismatch"))
  })

  let sorted_updates =
    list.sort(updates, fn(a, b) {
      int.compare(get_update_id(a), get_update_id(b))
    })

  let groups = group_equal_id_updates(sorted_updates)
  case groups {
    [] -> Error(StoreInvariantError("cannot_commit_empty_prefix"))
    [first_group, ..remaining_groups] -> {
      // Prevalidate ALL groups up front
      use _ <- result.try(
        list.try_map(groups, fn(g) { validate_group_identity(g, bot_id) }),
      )
      use rep <- result.try(validate_group_identity(first_group, bot_id))
      let rep_uid = get_update_id(rep)
      let request_id = ledger.make_request_id(bot_id, rep_uid)

      case rep_uid < current_wm.last_committed_offset {
        True -> {
          // Below watermark: lookup inbox and input to see if this is an admitted known replay
          use #(_gen, rows) <- result.try(
            read_keys(config, [
              codec.inbox_key(request_id),
              codec.input_key(request_id),
            ]),
          )
          let inbox_row =
            list.find(rows, fn(r) { r.key == codec.inbox_key(request_id) })
          let input_row =
            list.find(rows, fn(r) { r.key == codec.input_key(request_id) })
          case inbox_row, input_row {
            Ok(in_row), Ok(inp_row) if in_row.exists && inp_row.exists -> {
              use raw_inbox <- result.try(
                codec.decode_canonical_base64(in_row.canonical_value_base64)
                |> result.map_error(StoreDecodeError),
              )
              use stored_inbox <- result.try(
                codec.decode_inbox_record(raw_inbox)
                |> result.map_error(StoreDecodeError),
              )
              use raw_input <- result.try(
                codec.decode_canonical_base64(inp_row.canonical_value_base64)
                |> result.map_error(StoreDecodeError),
              )
              use #(_s_req, _s_bot, _s_upd, stored_verdict) <- result.try(
                codec.decode_input_verdict(raw_input)
                |> result.map_error(StoreDecodeError),
              )
              use proposed <- result.try(
                ledger.ingest_single(rep, now_ms, [])
                |> result.map_error(StoreInvariantError),
              )
              let is_valid_replay =
                verdicts_match(stored_verdict, rep)
                && stored_inbox.request_id == proposed.request_id
                && stored_inbox.bot_id == proposed.bot_id
                && stored_inbox.update_id == proposed.update_id
                && stored_inbox.chat_id == proposed.chat_id
                && stored_inbox.message_id == proposed.message_id
                && stored_inbox.user_id == proposed.user_id
                && stored_inbox.text_hash == proposed.text_hash
                && case stored_inbox.status, proposed.status {
                  ledger.InboxRejected(x), ledger.InboxRejected(y) -> x == y
                  ledger.InboxRejected(_), _ | _, ledger.InboxRejected(_) ->
                    False
                  _, _ -> True
                }
              case is_valid_replay {
                False -> Error(StoreInvariantError("batch_identity_collision"))
                True -> {
                  let read_set = [
                    codec.ReadSetAssertion(
                      key: codec.inbox_key(request_id),
                      expected_version: in_row.version,
                      expected_sha256: in_row.sha256,
                    ),
                    codec.ReadSetAssertion(
                      key: codec.input_key(request_id),
                      expected_version: inp_row.version,
                      expected_sha256: inp_row.sha256,
                    ),
                  ]
                  let res_delta = codec.ReservationDelta(rows: 0, receipts: 0)
                  let summary_json =
                    json.object([
                      #("op", json.string("known_replay")),
                      #("request_id", json.string(request_id)),
                      #("update_id", json.int(rep_uid)),
                    ])
                    |> json.to_string

                  use apply_res <- result.try(execute_apply(
                    config,
                    bot_id,
                    operation_id,
                    expected_generation,
                    read_set,
                    [],
                    res_delta,
                    summary_json,
                  ))

                  let remaining_flat = list.flatten(remaining_groups)
                  Ok(CommitPrefixResult(
                    receipt: apply_res.receipt,
                    watermark: current_wm,
                    admitted_records: [stored_inbox],
                    remaining_updates: remaining_flat,
                  ))
                }
              }
            }
            _, _ ->
              Error(StoreInvariantError("unseen_update_below_committed_offset"))
          }
        }
        False -> {
          let new_offset =
            int.max(current_wm.last_committed_offset, rep_uid + 1)
          let new_wm = ledger.Watermark(new_offset)

          use #(record, is_admitted, rows_reserved, receipts_reserved) <- result.try(
            case rep {
              guard.AcceptedEnvelope(
                update_id: uid,
                message_id: mid,
                chat_id: cid,
                user_id: uid_usr,
                text_hash: hash,
                bot_id: bot,
                ..,
              ) ->
                Ok(#(
                  ledger.InboxRecord(
                    update_id: uid,
                    message_id: mid,
                    chat_id: cid,
                    user_id: uid_usr,
                    text_hash: hash,
                    status: ledger.InboxPending,
                    created_at_ms: now_ms,
                    bot_id: bot,
                    request_id: request_id,
                  ),
                  True,
                  18,
                  63,
                ))
              guard.RejectedUpdate(
                update_id: uid,
                bot_id: bot,
                envelope_hash: hash,
                reason: r,
              ) ->
                Ok(#(
                  ledger.InboxRecord(
                    update_id: uid,
                    message_id: 0,
                    chat_id: 0,
                    user_id: 0,
                    text_hash: hash,
                    status: ledger.InboxRejected(r),
                    created_at_ms: now_ms,
                    bot_id: bot,
                    request_id: request_id,
                  ),
                  False,
                  0,
                  0,
                ))
              guard.UnidentifiedRejection(_) ->
                Error(StoreInvariantError("unidentified_rejection_in_prefix"))
            },
          )

          let input_val =
            codec.encode_input_verdict(request_id, bot_id, rep_uid, rep)
          let inbox_val = codec.encode_inbox_record(record)
          let wm_val = codec.encode_watermark_value(new_wm)

          let changes = [
            codec.Change(
              key: codec.input_key(request_id),
              expected_version: 0,
              expected_sha256: "",
              new_value_base64: codec.encode_canonical_base64(input_val),
            ),
            codec.Change(
              key: codec.inbox_key(request_id),
              expected_version: 0,
              expected_sha256: "",
              new_value_base64: codec.encode_canonical_base64(inbox_val),
            ),
            codec.Change(
              key: codec.watermark_key(),
              expected_version: current_wm_version,
              expected_sha256: current_wm_sha,
              new_value_base64: codec.encode_canonical_base64(wm_val),
            ),
          ]

          let read_set = [
            codec.ReadSetAssertion(
              key: codec.watermark_key(),
              expected_version: current_wm_version,
              expected_sha256: current_wm_sha,
            ),
            codec.ReadSetAssertion(
              key: codec.inbox_key(request_id),
              expected_version: 0,
              expected_sha256: "",
            ),
            codec.ReadSetAssertion(
              key: codec.input_key(request_id),
              expected_version: 0,
              expected_sha256: "",
            ),
          ]

          let res_delta =
            codec.ReservationDelta(
              rows: rows_reserved,
              receipts: receipts_reserved,
            )

          let summary_json =
            json.object([
              #("op", json.string("commit_prefix")),
              #("request_id", json.string(request_id)),
              #("update_id", json.int(rep_uid)),
              #("watermark", json.int(new_offset)),
              #("admitted", json.bool(is_admitted)),
            ])
            |> json.to_string

          use apply_res <- result.try(execute_apply(
            config,
            bot_id,
            operation_id,
            expected_generation,
            read_set,
            changes,
            res_delta,
            summary_json,
          ))

          let remaining_flat = list.flatten(remaining_groups)
          Ok(CommitPrefixResult(
            receipt: apply_res.receipt,
            watermark: new_wm,
            admitted_records: [record],
            remaining_updates: remaining_flat,
          ))
        }
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Task Claiming & Authority
// -----------------------------------------------------------------------------

pub fn claim_task_processing(
  config: transport.LocalConfiguration,
  bot_id: Int,
  operation_id: String,
  expected_generation: Int,
  inbox_record: ledger.InboxRecord,
  inbox_version: Int,
  inbox_sha: String,
  worker: String,
  epoch: Int,
  now_ms: Int,
) -> Result(#(codec.Receipt, ledger.InboxRecord), StoreError) {
  use _ <- result.try(
    case
      inbox_record.bot_id == bot_id
      && inbox_version > 0
      && string.byte_size(inbox_sha) == 64
    {
      True -> Ok(Nil)
      False -> Error(StoreInvariantError("invalid_inbox_binding"))
    },
  )

  let expected_inbox_val = codec.encode_inbox_record(inbox_record)
  use _ <- result.try(case files.digest(expected_inbox_val) == inbox_sha {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("inbox_record_sha_mismatch"))
  })

  use updated_record <- result.try(
    ledger.claim_inbox_task(inbox_record, worker, epoch)
    |> result.map_error(StoreInvariantError),
  )

  let authority =
    codec.AuthorityRecord(
      request_id: inbox_record.request_id,
      bot_id: bot_id,
      worker: worker,
      epoch: epoch,
      granted_at_ms: now_ms,
    )

  let inbox_val = codec.encode_inbox_record(updated_record)
  let auth_val = codec.encode_authority_value(authority)

  let changes = [
    codec.Change(
      key: codec.inbox_key(inbox_record.request_id),
      expected_version: inbox_version,
      expected_sha256: inbox_sha,
      new_value_base64: codec.encode_canonical_base64(inbox_val),
    ),
    codec.Change(
      key: codec.authority_key(inbox_record.request_id),
      expected_version: 0,
      expected_sha256: "",
      new_value_base64: codec.encode_canonical_base64(auth_val),
    ),
  ]

  let read_set = [
    codec.ReadSetAssertion(
      key: codec.inbox_key(inbox_record.request_id),
      expected_version: inbox_version,
      expected_sha256: inbox_sha,
    ),
    codec.ReadSetAssertion(
      key: codec.authority_key(inbox_record.request_id),
      expected_version: 0,
      expected_sha256: "",
    ),
  ]

  let res_delta = codec.ReservationDelta(rows: -1, receipts: -1)
  let summary_json =
    json.object([
      #("op", json.string("claim_task")),
      #("request_id", json.string(inbox_record.request_id)),
      #("worker", json.string(worker)),
      #("epoch", json.int(epoch)),
    ])
    |> json.to_string

  use apply_res <- result.try(execute_apply(
    config,
    bot_id,
    operation_id,
    expected_generation,
    read_set,
    changes,
    res_delta,
    summary_json,
  ))

  Ok(#(apply_res.receipt, updated_record))
}

// -----------------------------------------------------------------------------
// Result & Outbox Chunk Persistence (Atomic Batch)
// -----------------------------------------------------------------------------

pub fn commit_result(
  config: transport.LocalConfiguration,
  bot_id: Int,
  operation_id: String,
  expected_generation: Int,
  inbox_record: ledger.InboxRecord,
  inbox_version: Int,
  inbox_sha: String,
  payloads: List(String),
  worker: String,
  epoch: Int,
) -> Result(CommitResultResult, StoreError) {
  commit_result_extended(config, bot_id, operation_id, expected_generation, inbox_record, inbox_version, inbox_sha, payloads, worker, epoch, [], [], 0)
}

fn commit_result_extended(
  config: transport.LocalConfiguration,
  bot_id: Int,
  operation_id: String,
  expected_generation: Int,
  inbox_record: ledger.InboxRecord,
  inbox_version: Int,
  inbox_sha: String,
  payloads: List(String),
  worker: String,
  epoch: Int,
  extra_read_set: List(codec.ReadSetAssertion),
  extra_changes: List(codec.Change),
  extra_reserved_rows: Int,
) -> Result(CommitResultResult, StoreError) {
  use _ <- result.try(
    case
      inbox_record.bot_id == bot_id
      && inbox_version > 0
      && string.byte_size(inbox_sha) == 64
    {
      True -> Ok(Nil)
      False -> Error(StoreInvariantError("invalid_inbox_binding"))
    },
  )

  let expected_inbox_val = codec.encode_inbox_record(inbox_record)
  use _ <- result.try(case files.digest(expected_inbox_val) == inbox_sha {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("inbox_record_sha_mismatch"))
  })

  let auth_key = codec.authority_key(inbox_record.request_id)
  use #(_gen, auth_rows) <- result.try(read_keys(config, [auth_key]))
  use auth_row <- result.try(case auth_rows {
    [r] -> Ok(r)
    _ -> Error(StoreInvariantError("auth_row_query_failed"))
  })
  use _ <- result.try(case auth_row.exists {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("authority_row_missing"))
  })
  use raw_auth <- result.try(
    codec.decode_canonical_base64(auth_row.canonical_value_base64)
    |> result.map_error(StoreDecodeError),
  )
  use auth <- result.try(
    codec.decode_authority_value(raw_auth)
    |> result.map_error(StoreDecodeError),
  )
  use _ <- result.try(
    case
      auth.bot_id == bot_id
      && auth.worker == worker
      && auth.epoch == epoch
      && auth.request_id == inbox_record.request_id
    {
      True -> Ok(Nil)
      False -> Error(StoreInvariantError("worker_epoch_authority_mismatch"))
    },
  )

  use #(updated_inbox, chunks) <- result.try(
    ledger.record_result(inbox_record, payloads, worker, epoch)
    |> result.map_error(StoreInvariantError),
  )

  use digest <- result.try(case updated_inbox.status {
    ledger.InboxResultReady(d) -> Ok(d)
    _ -> Error(StoreInvariantError("record_result_failed_to_produce_ready"))
  })

  let total_chunks = list.length(chunks)
  let result_meta =
    codec.ResultMeta(
      request_id: inbox_record.request_id,
      bot_id: bot_id,
      chat_id: inbox_record.chat_id,
      update_id: inbox_record.update_id,
      message_id: inbox_record.message_id,
      user_id: inbox_record.user_id,
      text_hash: inbox_record.text_hash,
      created_at_ms: inbox_record.created_at_ms,
      digest: digest,
      total_chunks: total_chunks,
    )

  let inbox_val = codec.encode_inbox_record(updated_inbox)
  let result_val = codec.encode_result_value(result_meta)

  let inbox_change =
    codec.Change(
      key: codec.inbox_key(inbox_record.request_id),
      expected_version: inbox_version,
      expected_sha256: inbox_sha,
      new_value_base64: codec.encode_canonical_base64(inbox_val),
    )

  let result_change =
    codec.Change(
      key: codec.result_key(inbox_record.request_id),
      expected_version: 0,
      expected_sha256: "",
      new_value_base64: codec.encode_canonical_base64(result_val),
    )

  let chunk_changes =
    list.map(chunks, fn(c) {
      let chunk_val = codec.encode_chunk_value(c)
      codec.Change(
        key: codec.chunk_key(c.request_id, c.chunk_index),
        expected_version: 0,
        expected_sha256: "",
        new_value_base64: codec.encode_canonical_base64(chunk_val),
      )
    })

  let changes = list.append([inbox_change, result_change, ..chunk_changes], extra_changes)

  let chunk_read_assertions =
    list.map(chunks, fn(c) {
      codec.ReadSetAssertion(
        key: codec.chunk_key(c.request_id, c.chunk_index),
        expected_version: 0,
        expected_sha256: "",
      )
    })

  let base_read_set = [
    codec.ReadSetAssertion(
      key: codec.inbox_key(inbox_record.request_id),
      expected_version: inbox_version,
      expected_sha256: inbox_sha,
    ),
    codec.ReadSetAssertion(
      key: auth_key,
      expected_version: auth_row.version,
      expected_sha256: auth_row.sha256,
    ),
    codec.ReadSetAssertion(
      key: codec.result_key(inbox_record.request_id),
      expected_version: 0,
      expected_sha256: "",
    ),
    ..chunk_read_assertions
  ]

  let read_set = list.append(base_read_set, extra_read_set)
  let res_delta = codec.ReservationDelta(rows: -17 - extra_reserved_rows, receipts: -1)
  let summary_json =
    json.object([
      #("op", json.string("commit_result")),
      #("request_id", json.string(inbox_record.request_id)),
      #("digest", json.string(digest)),
      #("total_chunks", json.int(total_chunks)),
    ])
    |> json.to_string

  use apply_res <- result.try(execute_apply(
    config,
    bot_id,
    operation_id,
    expected_generation,
    read_set,
    changes,
    res_delta,
    summary_json,
  ))

  Ok(CommitResultResult(
    receipt: apply_res.receipt,
    inbox_record: updated_inbox,
    chunks: chunks,
  ))
}

// -----------------------------------------------------------------------------
// Durable SENDING Persistence (Must Commit Before HTTP Send)
// -----------------------------------------------------------------------------

pub fn commit_sending(
  config: transport.LocalConfiguration,
  bot_id: Int,
  operation_id: String,
  expected_generation: Int,
  inbox_record: ledger.InboxRecord,
  inbox_version: Int,
  inbox_sha: String,
  chunk: ledger.OutboxChunk,
  chunk_version: Int,
  chunk_sha: String,
  worker: String,
  epoch: Int,
) -> Result(#(codec.Receipt, ledger.OutboxChunk), StoreError) {
  use _ <- result.try(
    case
      inbox_record.bot_id == bot_id
      && chunk.bot_id == bot_id
      && chunk.request_id == inbox_record.request_id
      && inbox_version > 0
      && string.byte_size(inbox_sha) == 64
      && chunk_version > 0
      && string.byte_size(chunk_sha) == 64
    {
      True -> Ok(Nil)
      False -> Error(StoreInvariantError("invalid_inbox_or_chunk_binding"))
    },
  )

  let expected_inbox_val = codec.encode_inbox_record(inbox_record)
  use _ <- result.try(case files.digest(expected_inbox_val) == inbox_sha {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("inbox_record_sha_mismatch"))
  })

  let expected_chunk_val = codec.encode_chunk_value(chunk)
  use _ <- result.try(case files.digest(expected_chunk_val) == chunk_sha {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("chunk_sha_mismatch"))
  })

  use _ <- result.try(case chunk.status {
    ledger.OutboxPending -> Ok(Nil)
    _ -> Error(StoreInvariantError("commit_sending_requires_outbox_pending"))
  })

  use _ <- result.try(case inbox_record.status {
    ledger.InboxResultReady(d) if d == chunk.result_digest -> Ok(Nil)
    _ ->
      Error(StoreInvariantError(
        "commit_sending_requires_matching_inbox_result_ready",
      ))
  })

  use _ <- result.try(case ledger.valid_worker(worker, epoch) {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("invalid_worker_or_epoch"))
  })

  let auth_key = codec.authority_key(chunk.request_id)
  use #(_gen, auth_rows) <- result.try(read_keys(config, [auth_key]))
  use auth_row <- result.try(case auth_rows {
    [r] -> Ok(r)
    _ -> Error(StoreInvariantError("auth_row_query_failed"))
  })
  use _ <- result.try(case auth_row.exists {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("authority_row_missing"))
  })
  use raw_auth <- result.try(
    codec.decode_canonical_base64(auth_row.canonical_value_base64)
    |> result.map_error(StoreDecodeError),
  )
  use auth <- result.try(
    codec.decode_authority_value(raw_auth)
    |> result.map_error(StoreDecodeError),
  )
  use _ <- result.try(
    case
      auth.bot_id == bot_id
      && auth.worker == worker
      && auth.epoch == epoch
      && auth.request_id == chunk.request_id
    {
      True -> Ok(Nil)
      False -> Error(StoreInvariantError("worker_epoch_authority_mismatch"))
    },
  )

  let updated_chunk =
    ledger.OutboxChunk(
      ..chunk,
      status: ledger.OutboxSending(worker, epoch),
      attempt_count: 1,
    )

  let chunk_val = codec.encode_chunk_value(updated_chunk)

  let changes = [
    codec.Change(
      key: codec.chunk_key(chunk.request_id, chunk.chunk_index),
      expected_version: chunk_version,
      expected_sha256: chunk_sha,
      new_value_base64: codec.encode_canonical_base64(chunk_val),
    ),
  ]

  let read_set = [
    codec.ReadSetAssertion(
      key: codec.inbox_key(inbox_record.request_id),
      expected_version: inbox_version,
      expected_sha256: inbox_sha,
    ),
    codec.ReadSetAssertion(
      key: codec.chunk_key(chunk.request_id, chunk.chunk_index),
      expected_version: chunk_version,
      expected_sha256: chunk_sha,
    ),
    codec.ReadSetAssertion(
      key: auth_key,
      expected_version: auth_row.version,
      expected_sha256: auth_row.sha256,
    ),
  ]

  let res_delta = codec.ReservationDelta(rows: 0, receipts: -1)
  let summary_json =
    json.object([
      #("op", json.string("commit_sending")),
      #("request_id", json.string(chunk.request_id)),
      #("chunk_index", json.int(chunk.chunk_index)),
      #("worker", json.string(worker)),
      #("epoch", json.int(epoch)),
    ])
    |> json.to_string

  use apply_res <- result.try(execute_apply(
    config,
    bot_id,
    operation_id,
    expected_generation,
    read_set,
    changes,
    res_delta,
    summary_json,
  ))

  Ok(#(apply_res.receipt, updated_chunk))
}

// -----------------------------------------------------------------------------
// Durable Send Outcome Persistence (Committed After Send Outcome Known)
// -----------------------------------------------------------------------------

pub fn commit_outcome(
  config: transport.LocalConfiguration,
  bot_id: Int,
  operation_id: String,
  expected_generation: Int,
  chunk: ledger.OutboxChunk,
  chunk_version: Int,
  chunk_sha: String,
  outcome: ledger.OutboxStatus,
) -> Result(#(codec.Receipt, ledger.OutboxChunk), StoreError) {
  use #(worker, epoch) <- result.try(case chunk.status {
    ledger.OutboxSending(w, e) -> Ok(#(w, e))
    _ -> Error(StoreInvariantError("commit_outcome_requires_outbox_sending"))
  })

  use _ <- result.try(case outcome {
    ledger.OutboxDelivered(mid) if mid > 0 -> Ok(Nil)
    ledger.OutboxFailed(err) if err != "" -> Ok(Nil)
    ledger.OutboxUncertain(err) if err != "" -> Ok(Nil)
    _ ->
      Error(StoreInvariantError("commit_outcome_requires_valid_outcome_status"))
  })

  use _ <- result.try(
    case
      chunk.bot_id == bot_id
      && chunk_version > 0
      && string.byte_size(chunk_sha) == 64
    {
      True -> Ok(Nil)
      False -> Error(StoreInvariantError("invalid_chunk_binding"))
    },
  )

  let auth_key = codec.authority_key(chunk.request_id)
  use #(_gen, auth_rows) <- result.try(read_keys(config, [auth_key]))
  use auth_row <- result.try(case auth_rows {
    [r] -> Ok(r)
    _ -> Error(StoreInvariantError("auth_row_query_failed"))
  })
  use _ <- result.try(case auth_row.exists {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("authority_row_missing"))
  })
  use raw_auth <- result.try(
    codec.decode_canonical_base64(auth_row.canonical_value_base64)
    |> result.map_error(StoreDecodeError),
  )
  use auth <- result.try(
    codec.decode_authority_value(raw_auth)
    |> result.map_error(StoreDecodeError),
  )
  use _ <- result.try(
    case
      auth.bot_id == bot_id
      && auth.worker == worker
      && auth.epoch == epoch
      && auth.request_id == chunk.request_id
    {
      True -> Ok(Nil)
      False -> Error(StoreInvariantError("worker_epoch_authority_mismatch"))
    },
  )

  let expected_chunk_val = codec.encode_chunk_value(chunk)
  use _ <- result.try(case files.digest(expected_chunk_val) == chunk_sha {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("chunk_sha_mismatch"))
  })

  let updated_chunk = ledger.OutboxChunk(..chunk, status: outcome)
  let chunk_val = codec.encode_chunk_value(updated_chunk)

  let changes = [
    codec.Change(
      key: codec.chunk_key(chunk.request_id, chunk.chunk_index),
      expected_version: chunk_version,
      expected_sha256: chunk_sha,
      new_value_base64: codec.encode_canonical_base64(chunk_val),
    ),
  ]

  let read_set = [
    codec.ReadSetAssertion(
      key: codec.chunk_key(chunk.request_id, chunk.chunk_index),
      expected_version: chunk_version,
      expected_sha256: chunk_sha,
    ),
    codec.ReadSetAssertion(
      key: auth_key,
      expected_version: auth_row.version,
      expected_sha256: auth_row.sha256,
    ),
  ]

  let res_delta = codec.ReservationDelta(rows: 0, receipts: -1)
  let summary_json =
    json.object([
      #("op", json.string("commit_outcome")),
      #("request_id", json.string(chunk.request_id)),
      #("chunk_index", json.int(chunk.chunk_index)),
    ])
    |> json.to_string

  use apply_res <- result.try(execute_apply(
    config,
    bot_id,
    operation_id,
    expected_generation,
    read_set,
    changes,
    res_delta,
    summary_json,
  ))

  Ok(#(apply_res.receipt, updated_chunk))
}

// -----------------------------------------------------------------------------
// Task Completion Ingestion
// -----------------------------------------------------------------------------

pub fn commit_task_completion(
  config: transport.LocalConfiguration,
  bot_id: Int,
  operation_id: String,
  expected_generation: Int,
  inbox_record: ledger.InboxRecord,
  inbox_version: Int,
  inbox_sha: String,
  chunks: List(ledger.OutboxChunk),
) -> Result(#(codec.Receipt, ledger.InboxRecord), StoreError) {
  use _ <- result.try(
    case
      inbox_record.bot_id == bot_id
      && inbox_version > 0
      && string.byte_size(inbox_sha) == 64
    {
      True -> Ok(Nil)
      False -> Error(StoreInvariantError("invalid_inbox_binding"))
    },
  )

  let expected_inbox_val = codec.encode_inbox_record(inbox_record)
  use _ <- result.try(case files.digest(expected_inbox_val) == inbox_sha {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("inbox_record_sha_mismatch"))
  })

  use _ <- result.try(
    case
      list.all(chunks, fn(c) {
        c.bot_id == bot_id && c.request_id == inbox_record.request_id
      })
    {
      True -> Ok(Nil)
      False -> Error(StoreInvariantError("chunk_bot_or_request_mismatch"))
    },
  )

  use completed_inbox <- result.try(
    ledger.complete_inbox_task(inbox_record, chunks)
    |> result.map_error(StoreInvariantError),
  )

  let auth_key = codec.authority_key(inbox_record.request_id)
  use #(_gen, auth_rows) <- result.try(read_keys(config, [auth_key]))
  use auth_row <- result.try(case auth_rows {
    [r] -> Ok(r)
    _ -> Error(StoreInvariantError("auth_row_query_failed"))
  })
  use _ <- result.try(case auth_row.exists {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("authority_row_missing"))
  })
  use raw_auth <- result.try(
    codec.decode_canonical_base64(auth_row.canonical_value_base64)
    |> result.map_error(StoreDecodeError),
  )
  use auth <- result.try(
    codec.decode_authority_value(raw_auth)
    |> result.map_error(StoreDecodeError),
  )
  use _ <- result.try(
    case auth.bot_id == bot_id && auth.request_id == inbox_record.request_id {
      True -> Ok(Nil)
      False -> Error(StoreInvariantError("authority_bot_id_mismatch"))
    },
  )

  let inbox_val = codec.encode_inbox_record(completed_inbox)

  let changes = [
    codec.Change(
      key: codec.inbox_key(inbox_record.request_id),
      expected_version: inbox_version,
      expected_sha256: inbox_sha,
      new_value_base64: codec.encode_canonical_base64(inbox_val),
    ),
  ]

  let chunk_keys =
    list.map(chunks, fn(c) { codec.chunk_key(c.request_id, c.chunk_index) })
  use #(_gen, chunk_rows) <- result.try(read_keys(config, chunk_keys))

  use chunk_read_assertions <- result.try(
    list.try_map(chunks, fn(c) {
      let key = codec.chunk_key(c.request_id, c.chunk_index)
      case list.find(chunk_rows, fn(r: codec.RowResult) { r.key == key }) {
        Error(_) ->
          Error(StoreInvariantError("chunk_missing_from_read: " <> key))
        Ok(row) if row.version == 0 ->
          Error(StoreInvariantError("chunk_absent: " <> key))
        Ok(row) -> {
          let expected_val = codec.encode_chunk_value(c)
          let expected_sha = files.digest(expected_val)
          case row.sha256 == expected_sha {
            True ->
              Ok(codec.ReadSetAssertion(
                key: key,
                expected_version: row.version,
                expected_sha256: row.sha256,
              ))
            False -> Error(StoreInvariantError("chunk_sha_mismatch: " <> key))
          }
        }
      }
    }),
  )

  let read_set = [
    codec.ReadSetAssertion(
      key: codec.inbox_key(inbox_record.request_id),
      expected_version: inbox_version,
      expected_sha256: inbox_sha,
    ),
    codec.ReadSetAssertion(
      key: auth_key,
      expected_version: auth_row.version,
      expected_sha256: auth_row.sha256,
    ),
    ..chunk_read_assertions
  ]

  let n_chunks = list.length(chunks)
  let remaining_receipts = 61 - 2 * n_chunks
  let receipts_delta = -remaining_receipts
  let res_delta = codec.ReservationDelta(rows: 0, receipts: receipts_delta)
  let summary_json =
    json.object([
      #("op", json.string("commit_completion")),
      #("request_id", json.string(inbox_record.request_id)),
    ])
    |> json.to_string

  use apply_res <- result.try(execute_apply(
    config,
    bot_id,
    operation_id,
    expected_generation,
    read_set,
    changes,
    res_delta,
    summary_json,
  ))

  Ok(#(apply_res.receipt, completed_inbox))
}

/// Durable single-start marker. This is storage exclusion, not authorization.
/// The service must check live unit/control digest and current task/runtime leases
/// before calling, keep the success private to its one supervisor factory, and
/// never mint a fresh live permit from an operation replay or uncertain result.
pub fn consume_writer_start(
  config: transport.LocalConfiguration,
  expected: codec.WriterRegistration,
) -> Result(Int, StoreError) {
  use raw <- result.try(codec.encode_writer_registration(expected)
    |> result.map_error(StoreInvariantError))
  use current_incarnation <- result.try(
    lifecycle.compute_store_incarnation(ffi_config_database(config))
    |> result.map_error(StoreInvariantError),
  )
  use _ <- result.try(case current_incarnation == expected.store_incarnation_id {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("writer_start_incarnation_mismatch"))
  })
  use #(generation, rows) <- result.try(read_keys(config, [
    codec.bot_identity_key(), codec.writer_registration_key(), "meta/writer_start",
  ]))
  use bot <- result.try(list.find(rows, fn(row) { row.key == codec.bot_identity_key() })
    |> result.map_error(fn(_) { StoreInvariantError("writer_start_missing_bot_row") }))
  use writer <- result.try(list.find(rows, fn(row) { row.key == codec.writer_registration_key() })
    |> result.map_error(fn(_) { StoreInvariantError("writer_start_missing_writer_row") }))
  use start <- result.try(list.find(rows, fn(row) { row.key == "meta/writer_start" })
    |> result.map_error(fn(_) { StoreInvariantError("writer_start_missing_start_row") }))
  use _ <- result.try(case bot.exists {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("writer_start_missing_bot_row"))
  })
  use _ <- result.try(case writer.exists {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("writer_start_missing_writer_row"))
  })
  use bot_raw <- result.try(codec.decode_row_value(bot) |> result.map_error(StoreDecodeError))
  use actual_bot <- result.try(codec.decode_bot_identity_value(bot_raw) |> result.map_error(StoreDecodeError))
  use writer_raw <- result.try(codec.decode_row_value(writer) |> result.map_error(StoreDecodeError))
  use actual_writer <- result.try(codec.decode_writer_registration(writer_raw) |> result.map_error(StoreDecodeError))
  use _ <- result.try(case actual_bot == expected.bot_id && actual_writer == expected {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("writer_start_registration_mismatch"))
  })
  use _ <- result.try(case start.exists {
    False -> case expected.service_epoch == 1 {
      True -> Ok(Nil)
      False -> Error(StoreInvariantError("writer_start_predecessor_missing"))
    }
    True -> {
      use marker_raw <- result.try(codec.decode_row_value(start) |> result.map_error(StoreDecodeError))
      case codec.decode_writer_registration(marker_raw) {
        Ok(previous) -> case previous == expected {
          True -> Error(StoreInvariantError("writer_start_already_consumed"))
          False -> Error(StoreInvariantError("writer_start_invalid_successor"))
        }
        Error(_) -> {
          use prepared <- result.try(codec.decode_prepared_writer_start(marker_raw) |> result.map_error(StoreDecodeError))
          case prepared.next == expected {
            True -> Ok(Nil)
            False -> Error(StoreInvariantError("writer_start_prepared_mismatch"))
          }
        }
      }
    }
  })
  let read_set = list.map(rows, fn(row) {
    codec.ReadSetAssertion(row.key, row.version, row.sha256)
  })
  let summary = json.object([
    #("op", json.string("writer_start")),
    #("instance_token", json.string(expected.instance_token)),
    #("service_epoch", json.int(expected.service_epoch)),
  ]) |> json.to_string
  use applied <- result.try(execute_apply(
    config, expected.bot_id, "op-writer-start-" <> expected.instance_token,
    generation, read_set,
    [codec.Change("meta/writer_start", start.version, start.sha256,
      codec.encode_canonical_base64(raw))],
    codec.ReservationDelta(0, 0), summary,
  ))
  case applied.replay {
    True -> Error(StoreInvariantError("writer_start_replay_not_admission"))
    False -> Ok(applied.receipt.generation)
  }
}


/// Atomically prepare the next registration and its unconsumed start marker.
/// This is a storage transition only. The service must prove predecessor
/// quiescence and current authority before invoking it; no live permit is returned.
pub fn transition_writer_registration(
  config: transport.LocalConfiguration,
  previous: codec.WriterRegistration,
  next: codec.WriterRegistration,
) -> Result(Int, StoreError) {
  let prepared = codec.PreparedWriterStart(previous, next)
  use prepared_raw <- result.try(codec.encode_prepared_writer_start(prepared)
    |> result.map_error(StoreInvariantError))
  use next_raw <- result.try(codec.encode_writer_registration(next)
    |> result.map_error(StoreInvariantError))
  use incarnation <- result.try(lifecycle.compute_store_incarnation(ffi_config_database(config))
    |> result.map_error(StoreInvariantError))
  use _ <- result.try(case incarnation == previous.store_incarnation_id {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("writer_transition_incarnation_mismatch"))
  })
  use #(generation, rows) <- result.try(read_keys(config, [
    codec.bot_identity_key(), codec.writer_registration_key(), "meta/writer_start",
  ]))
  use bot <- result.try(list.find(rows, fn(row) { row.key == codec.bot_identity_key() })
    |> result.map_error(fn(_) { StoreInvariantError("writer_transition_missing_bot") }))
  use writer <- result.try(list.find(rows, fn(row) { row.key == codec.writer_registration_key() })
    |> result.map_error(fn(_) { StoreInvariantError("writer_transition_missing_writer") }))
  use start <- result.try(list.find(rows, fn(row) { row.key == "meta/writer_start" })
    |> result.map_error(fn(_) { StoreInvariantError("writer_transition_missing_start_row") }))
  use _ <- result.try(case bot.exists && writer.exists {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("writer_transition_uninitialized"))
  })
  use bot_raw <- result.try(codec.decode_row_value(bot) |> result.map_error(StoreDecodeError))
  use actual_bot <- result.try(codec.decode_bot_identity_value(bot_raw) |> result.map_error(StoreDecodeError))
  use writer_raw <- result.try(codec.decode_row_value(writer) |> result.map_error(StoreDecodeError))
  use actual_writer <- result.try(codec.decode_writer_registration(writer_raw) |> result.map_error(StoreDecodeError))
  use _ <- result.try(case actual_bot == previous.bot_id {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("writer_transition_bot_mismatch"))
  })
  case actual_writer == next {
    True -> {
      use marker <- result.try(codec.decode_row_value(start) |> result.map_error(StoreDecodeError))
      case start.exists && marker == prepared_raw {
        True -> Ok(generation)
        False -> Error(StoreInvariantError("writer_transition_repeat_not_prepared"))
      }
    }
    False -> {
      use _ <- result.try(case actual_writer == previous {
        True -> Ok(Nil)
        False -> Error(StoreInvariantError("writer_transition_previous_mismatch"))
      })
      use _ <- result.try(case start.exists {
        False -> case previous.service_epoch == 1 {
          True -> Ok(Nil)
          False -> Error(StoreInvariantError("writer_transition_missing_history"))
        }
        True -> {
          use marker <- result.try(codec.decode_row_value(start) |> result.map_error(StoreDecodeError))
          case codec.decode_writer_registration(marker) {
            Ok(started) -> case started == previous {
              True -> Ok(Nil)
              False -> Error(StoreInvariantError("writer_transition_started_mismatch"))
            }
            Error(_) -> {
              use earlier <- result.try(codec.decode_prepared_writer_start(marker) |> result.map_error(StoreDecodeError))
              case earlier.next == previous {
                True -> Ok(Nil)
                False -> Error(StoreInvariantError("writer_transition_prepared_mismatch"))
              }
            }
          }
        }
      })
      let reads = list.map(rows, fn(row) { codec.ReadSetAssertion(row.key, row.version, row.sha256) })
      let summary = json.object([
        #("op", json.string("writer_prepare")),
        #("instance_token", json.string(next.instance_token)),
        #("service_epoch", json.int(next.service_epoch)),
      ]) |> json.to_string
      use applied <- result.try(execute_apply(config, next.bot_id,
        "op-writer-prepare-" <> next.instance_token, generation, reads,
        [
          codec.Change(writer.key, writer.version, writer.sha256, codec.encode_canonical_base64(next_raw)),
          codec.Change(start.key, start.version, start.sha256, codec.encode_canonical_base64(prepared_raw)),
        ], codec.ReservationDelta(0, 0), summary))
      Ok(applied.receipt.generation)
    }
  }
}

pub opaque type ConversationReservation {
  ConversationReservation(
    config: transport.LocalConfiguration,
    generation: Int,
    inbox_record: ledger.InboxRecord,
    inbox_version: Int,
    inbox_sha: String,
    worker: String,
    epoch: Int,
    context: conv.Context,
    prompt: String,
    context_row: codec.RowResult,
    budget_key: String,
    budget_version: Int,
    budget_sha: String,
    reserved_context_rows: Int,
  )
}

pub fn conversation_context(res: ConversationReservation) -> conv.Context {
  res.context
}

pub fn conversation_prompt(res: ConversationReservation) -> String {
  res.prompt
}

pub fn conversation_generation(res: ConversationReservation) -> Int {
  res.generation
}

fn find_read_row(
  rows: List(codec.RowResult),
  key: String,
) -> Result(codec.RowResult, StoreError) {
  case list.find(rows, fn(r) { r.key == key }) {
    Ok(row) ->
      case row.exists {
        True ->
          case row.version > 0 && string.byte_size(row.sha256) == 64 {
            True -> Ok(row)
            False -> Error(StoreDecodeError("invalid_existing_row_metadata"))
          }
        False ->
          case row.version == 0 && row.sha256 == "" {
            True -> Ok(row)
            False -> Error(StoreDecodeError("invalid_missing_row_metadata"))
          }
      }
    Error(_) -> Error(StoreInvariantError("read_row_missing"))
  }
}

fn row_version_and_sha(row: codec.RowResult) -> #(Int, String) {
  case row.exists {
    True -> #(row.version, row.sha256)
    False -> #(0, "")
  }
}

fn row_read_assertion(key: String, row: codec.RowResult) -> codec.ReadSetAssertion {
  let #(ver, sha) = row_version_and_sha(row)
  codec.ReadSetAssertion(
    key: key,
    expected_version: ver,
    expected_sha256: sha,
  )
}

pub fn reserve_conversation(
  config: transport.LocalConfiguration,
  expected_generation: Int,
  record: ledger.InboxRecord,
  inbox_version: Int,
  inbox_sha: String,
  worker: String,
  epoch: Int,
  day: Int,
  daily_limit: Int,
) -> Result(ConversationReservation, StoreError) {
  use _ <- result.try(
    case
      expected_generation >= 0
      && ledger.valid_record(record)
      && record.status == ledger.InboxProcessing(worker, epoch)
      && inbox_version > 0
      && string.byte_size(inbox_sha) == 64
    {
      True -> Ok(Nil)
      False -> Error(StoreInvariantError("invalid_inbox_binding"))
    },
  )

  let expected_inbox_val = codec.encode_inbox_record(record)
  use _ <- result.try(case files.digest(expected_inbox_val) == inbox_sha {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("inbox_record_sha_mismatch"))
  })

  let scope =
    conv.Scope(
      bot_id: record.bot_id,
      chat_id: record.chat_id,
      user_id: record.user_id,
    )
  use ctx_key <- result.try(
    conv.context_key(scope)
    |> result.map_error(StoreInvariantError),
  )
  use b_key <- result.try(
    conv.budget_key(record.bot_id, day)
    |> result.map_error(StoreInvariantError),
  )
  let auth_key = codec.authority_key(record.request_id)
  let in_key = codec.input_key(record.request_id)

  use #(gen, rows) <- result.try(
    read_keys(config, [ctx_key, b_key, auth_key, in_key]),
  )
  use _ <- result.try(case gen == expected_generation {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("read_generation_mismatch"))
  })
  use _ <- result.try(case list.length(rows) == 4 {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("read_row_count_mismatch"))
  })

  use ctx_row <- result.try(find_read_row(rows, ctx_key))
  use budget_row <- result.try(find_read_row(rows, b_key))
  use auth_row <- result.try(find_read_row(rows, auth_key))
  use input_row <- result.try(find_read_row(rows, in_key))

  use _ <- result.try(case auth_row.exists {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("authority_row_missing"))
  })
  use raw_auth <- result.try(
    codec.decode_canonical_base64(auth_row.canonical_value_base64)
    |> result.map_error(StoreDecodeError),
  )
  use auth <- result.try(
    codec.decode_authority_value(raw_auth)
    |> result.map_error(StoreDecodeError),
  )
  use _ <- result.try(
    case
      auth.bot_id == record.bot_id
      && auth.request_id == record.request_id
      && auth.worker == worker
      && auth.epoch == epoch
    {
      True -> Ok(Nil)
      False -> Error(StoreInvariantError("worker_epoch_authority_mismatch"))
    },
  )

  use _ <- result.try(case input_row.exists {
    True -> Ok(Nil)
    False -> Error(StoreInvariantError("input_row_missing"))
  })
  use raw_input <- result.try(
    codec.decode_canonical_base64(input_row.canonical_value_base64)
    |> result.map_error(StoreDecodeError),
  )
  use #(in_req_id, in_bot, in_upd, verdict) <- result.try(
    codec.decode_input_verdict(raw_input)
    |> result.map_error(StoreDecodeError),
  )
  use raw_text <- result.try(case verdict {
    guard.AcceptedEnvelope(
      update_id: v_upd,
      message_id: mid,
      chat_id: cid,
      user_id: uid_usr,
      text_hash: hash,
      raw_text: raw,
      directive: _,
      bot_id: v_bot,
      callback_query_id: _,
    ) ->
      case
        in_req_id == record.request_id
        && in_bot == record.bot_id
        && in_upd == record.update_id
        && v_bot == record.bot_id
        && v_upd == record.update_id
        && mid == record.message_id
        && cid == record.chat_id
        && uid_usr == record.user_id
        && hash == record.text_hash
        && files.digest(raw) == record.text_hash
      {
        True -> Ok(raw)
        False -> Error(StoreInvariantError("input_verdict_record_mismatch"))
      }
    _ -> Error(StoreInvariantError("input_verdict_not_accepted"))
  })
  use prompt <- result.try(
    conv.prompt_for_text(raw_text)
    |> result.map_error(StoreInvariantError),
  )

  use #(context, reserved_context_rows) <- result.try(case ctx_row.exists {
    False -> Ok(#(conv.Context(scope: scope, turns: []), 1))
    True -> {
      use raw_ctx <- result.try(
        codec.decode_canonical_base64(ctx_row.canonical_value_base64)
        |> result.map_error(StoreDecodeError),
      )
      use decoded_ctx <- result.try(
        conv.decode_context(raw_ctx, scope)
        |> result.map_error(StoreDecodeError),
      )
      Ok(#(decoded_ctx, 0))
    }
  })

  use current_budget <- result.try(case budget_row.exists {
    False ->
      Ok(conv.DailyBudget(
        bot_id: record.bot_id,
        utc_day: day,
        reserved_requests: 0,
      ))
    True -> {
      use raw_budget <- result.try(
        codec.decode_canonical_base64(budget_row.canonical_value_base64)
        |> result.map_error(StoreDecodeError),
      )
      conv.decode_budget(raw_budget, record.bot_id, day)
      |> result.map_error(StoreDecodeError)
    }
  })

  use next_budget <- result.try(
    conv.reserve(current_budget, record.bot_id, day, daily_limit)
    |> result.map_error(fn(reason) {
      case reason {
        "daily_request_budget_exhausted" -> StoreCapacityExceeded(reason)
        _ -> StoreInvariantError(reason)
      }
    }),
  )
  use encoded_budget <- result.try(
    conv.encode_budget(next_budget)
    |> result.map_error(StoreInvariantError),
  )

  let #(budget_ver, budget_sha) = row_version_and_sha(budget_row)
  let budget_change =
    codec.Change(
      key: b_key,
      expected_version: budget_ver,
      expected_sha256: budget_sha,
      new_value_base64: codec.encode_canonical_base64(encoded_budget),
    )

  let read_set = [
    codec.ReadSetAssertion(
      key: codec.inbox_key(record.request_id),
      expected_version: inbox_version,
      expected_sha256: inbox_sha,
    ),
    row_read_assertion(auth_key, auth_row),
    row_read_assertion(in_key, input_row),
    row_read_assertion(ctx_key, ctx_row),
    row_read_assertion(b_key, budget_row),
  ]
  let changes = [budget_change]
  let res_delta =
    codec.ReservationDelta(rows: reserved_context_rows, receipts: 0)
  let operation_id = "op-conversation-reserve-" <> record.request_id
  let summary_json =
    json.object([
      #("op", json.string("reserve_conversation")),
      #("request_id", json.string(record.request_id)),
      #("day", json.int(day)),
      #("reserved_context_rows", json.int(reserved_context_rows)),
    ])
    |> json.to_string

  use apply_res <- result.try(execute_apply(
    config,
    record.bot_id,
    operation_id,
    expected_generation,
    read_set,
    changes,
    res_delta,
    summary_json,
  ))

  Ok(ConversationReservation(
    config: config,
    generation: apply_res.receipt.generation,
    inbox_record: record,
    inbox_version: inbox_version,
    inbox_sha: inbox_sha,
    worker: worker,
    epoch: epoch,
    context: context,
    prompt: prompt,
    context_row: ctx_row,
    budget_key: b_key,
    budget_version: budget_ver + 1,
    budget_sha: files.digest(encoded_budget),
    reserved_context_rows: reserved_context_rows,
  ))
}

pub fn commit_conversation_result(
  res: ConversationReservation,
  payloads: List(String),
  successful_reply: Option(String),
) -> Result(CommitResultResult, StoreError) {
  let #(ctx_ver, ctx_sha) = row_version_and_sha(res.context_row)
  let ctx_assert =
    codec.ReadSetAssertion(
      key: res.context_row.key,
      expected_version: ctx_ver,
      expected_sha256: ctx_sha,
    )
  let budget_assert =
    codec.ReadSetAssertion(
      key: res.budget_key,
      expected_version: res.budget_version,
      expected_sha256: res.budget_sha,
    )

  use extra_changes <- result.try(case successful_reply {
    None -> Ok([])
    Some(reply) -> {
      use _ <- result.try(case reply == string.join(payloads, "") {
        True -> Ok(Nil)
        False ->
          Error(StoreInvariantError("conversation_reply_payload_mismatch"))
      })
      let turn =
        conv.Turn(
          update_id: res.inbox_record.update_id,
          prompt: res.prompt,
          reply: reply,
        )
      use updated_ctx <- result.try(
        conv.append(res.context, turn)
        |> result.map_error(StoreInvariantError),
      )
      use encoded_ctx <- result.try(
        conv.encode_context(updated_ctx)
        |> result.map_error(StoreInvariantError),
      )
      Ok([
        codec.Change(
          key: res.context_row.key,
          expected_version: ctx_ver,
          expected_sha256: ctx_sha,
          new_value_base64: codec.encode_canonical_base64(encoded_ctx),
        ),
      ])
    }
  })

  commit_result_extended(
    res.config,
    res.inbox_record.bot_id,
    "op-result-" <> res.inbox_record.request_id,
    res.generation,
    res.inbox_record,
    res.inbox_version,
    res.inbox_sha,
    payloads,
    res.worker,
    res.epoch,
    [ctx_assert, budget_assert],
    extra_changes,
    res.reserved_context_rows,
  )
}
