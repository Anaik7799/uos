//// Production-capable typed recovery activation for UOS.
////
//// Governing contracts:
//// - contracts/rules/20260907-0653-tri-agent-coordination.md (SYNC-04)
//// - contracts/rules/20260909-0412-gleam-harness-agent-operation-contract.md (SC-HARNESS-MCP-001)
//// - contracts/rules/20260908-0912-provenance-integrity-contract.md (SC-PROVENANCE-001)
////
//// Architectural Invariants:
//// - Finite typed intent validated by Gleam
//// - Separate private reviewed grant (reviewer != worker, review receipt schema + PASS)
//// - Private file permissions and ancestor security verification (no symlinks, mode <= 0600)
//// - Strict host/boot clock verification (no fallback to unknown host/boot)
//// - Exclusive per-target lock at TARGET.recovery-lock (O_CREAT | O_EXCL)
//// - Persistent generation token at TARGET.recovery-generation, advanced atomically
////   under lock BEFORE preservation/swap; never removed on rollback (retiring stale handles)
//// - Quiescence rechecked under lock AFTER generation advance (inspects main + sidecars)
//// - Full ancestor directory safety inspection
//// - Mandatory effect-time Sa-plan lease re-check under lock
//// - Full cryptographic chain verification (coordinator session_store triggers & digests;
////   cycle triggers, contiguous sequence, previous_digest chain)
//// - Candidate is NOT checkpoint-mutated after digest verification
//// - Target hash is strictly required on existing targets
//// - Crash-safe atomic staged swap (.swap-tmp -> fsync -> rename)
//// - Target sidecars retired with error checking BEFORE DB swap
//// - Full preservation of original DB, WAL, SHM into unique immutable backup dir with manifest
//// - Reopened SQLite integrity check (PRAGMA integrity_check + PRAGMA quick_check)
//// - Deterministic rollback on failure restoring preserved originals
//// - Failed rollback retains lock in HOLD status permanently (no unconditional unlock)
//// - Persisted phase receipts for deterministic crash analysis
//// - Per-operation immutable recovery and rollback receipts

import cepaf_gleam/harness/development as dev
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

// -----------------------------------------------------------------------------
// FFI Declarations
// -----------------------------------------------------------------------------

@external(erlang, "recovery_activation_ffi", "get_pid")
pub fn get_pid() -> Int

@external(erlang, "recovery_activation_ffi", "clock")
pub fn ffi_clock() -> Result(#(String, String, Int, Int), String)

@external(erlang, "recovery_activation_ffi", "utc_now_iso8601")
pub fn utc_now_iso8601() -> String

@external(erlang, "recovery_activation_ffi", "sha256_file")
pub fn sha256_file(path: String) -> Result(String, String)

@external(erlang, "recovery_activation_ffi", "path_safety_check")
pub fn path_safety_check(path: String) -> Result(Nil, String)

@external(erlang, "recovery_activation_ffi", "check_private_file")
pub fn check_private_file(path: String) -> Result(Nil, String)

@external(erlang, "recovery_activation_ffi", "acquire_target_lock")
pub fn acquire_target_lock(
  lock_path: String,
  payload: String,
) -> Result(Nil, String)

@external(erlang, "recovery_activation_ffi", "release_target_lock")
pub fn release_target_lock(
  lock_path: String,
  expected_pid: Int,
) -> Result(Nil, String)

@external(erlang, "recovery_activation_ffi", "hold_target_lock")
pub fn hold_target_lock(
  lock_path: String,
  reason: String,
  utc_string: String,
) -> Result(Nil, String)

@external(erlang, "recovery_activation_ffi", "is_target_locked")
pub fn is_target_locked(lock_path: String) -> Result(Bool, String)

@external(erlang, "recovery_activation_ffi", "read_target_lock")
pub fn read_target_lock(lock_path: String) -> Result(String, String)

@external(erlang, "recovery_activation_ffi", "read_generation")
pub fn read_generation(gen_path: String) -> Result(String, String)

@external(erlang, "recovery_activation_ffi", "advance_generation")
pub fn advance_generation(
  gen_path: String,
  token: String,
) -> Result(Nil, String)

@external(erlang, "recovery_activation_ffi", "check_quiescence")
pub fn check_quiescence(target_path: String) -> Result(Nil, String)

@external(erlang, "recovery_activation_ffi", "preserve_target_state")
pub fn preserve_target_state(
  target_path: String,
  backup_dir: String,
  intent_id: String,
  attempt: Int,
  gen_token: String,
  utc_us: Int,
  utc_string: String,
) -> Result(#(String, String, String, String, String), String)

@external(erlang, "recovery_activation_ffi", "retire_target_sidecars")
pub fn retire_target_sidecars(target_path: String) -> Result(Nil, String)

@external(erlang, "recovery_activation_ffi", "staged_swap_database")
pub fn staged_swap_database(
  candidate_path: String,
  target_path: String,
  expected_candidate_sha256: String,
) -> Result(Nil, String)

@external(erlang, "recovery_activation_ffi", "rollback_from_manifest")
pub fn rollback_from_manifest(
  target_path: String,
  backup_dir: String,
) -> Result(Nil, String)

@external(erlang, "recovery_activation_ffi", "persist_phase_receipt")
pub fn persist_phase_receipt(
  backup_dir: String,
  intent_id: String,
  phase: String,
  utc_us: Int,
  utc_string: String,
  extra_json: String,
) -> Result(Nil, String)

@external(erlang, "recovery_activation_ffi", "sqlite_verify_integrity")
pub fn sqlite_verify_integrity(db_path: String) -> Result(Int, String)

@external(erlang, "recovery_activation_ffi", "sqlite_checkpoint")
pub fn sqlite_checkpoint(db_path: String) -> Result(Nil, String)

@external(erlang, "recovery_activation_ffi", "verify_cycle_chain")
pub fn verify_cycle_chain(db_path: String) -> Result(#(Int, Int), String)

@external(erlang, "recovery_activation_ffi", "file_exists")
pub fn file_exists(path: String) -> Bool

@external(erlang, "recovery_activation_ffi", "read_file_binary")
pub fn read_file_binary(path: String) -> Result(BitArray, String)

@external(erlang, "recovery_activation_ffi", "write_file_binary")
pub fn write_file_binary(path: String, content: BitArray) -> Result(Nil, String)

@external(erlang, "recovery_activation_ffi", "change_file_mode")
pub fn change_file_mode(path: String, mode: Int) -> Result(Nil, String)

@external(erlang, "recovery_activation_ffi", "delete_file")
pub fn delete_file(path: String) -> Result(Nil, String)

@external(erlang, "recovery_activation_ffi", "list_dir")
pub fn list_dir(path: String) -> Result(List(String), String)

@external(erlang, "recovery_activation_ffi", "create_test_db")
pub fn create_test_db(path: String, table_name: String) -> Result(Nil, String)

@external(erlang, "recovery_activation_ffi", "verify_coordinator_chain")
pub fn verify_coordinator_chain(path: String) -> Result(Int, String)

@external(erlang, "recovery_activation_ffi", "create_test_coordinator_db")
pub fn create_test_coordinator_db(path: String) -> Result(Nil, String)

@external(erlang, "recovery_activation_ffi", "create_test_cycle_db")
pub fn create_test_cycle_db(path: String) -> Result(Nil, String)

// -----------------------------------------------------------------------------
// Core Domain Types
// -----------------------------------------------------------------------------

pub type TargetKind {
  CoordinatorStore
  KmCycleStore
  UnsupportedTargetKind(String)
}

pub fn parse_target_kind(raw: String) -> TargetKind {
  case raw {
    "coordinator" -> CoordinatorStore
    "km_cycle" -> KmCycleStore
    "km_cycles" -> KmCycleStore
    other -> UnsupportedTargetKind(other)
  }
}

pub type ActivationIntent {
  ActivationIntent(
    intent_id: String,
    plan: String,
    task: String,
    worker: String,
    attempt: Int,
    host_id: String,
    boot_id: String,
    expiry_utc_us: Int,
    target_path: String,
    target_kind: TargetKind,
    candidate_path: String,
    candidate_sha256: String,
    expected_target_sha256: Option(String),
    review_receipt_sha256: String,
    operator_scope: String,
    backup_dir: String,
  )
}

pub type ReviewedGrant {
  ReviewedGrant(
    grant_id: String,
    reviewer: String,
    review_receipt_path: String,
    review_receipt_sha256: String,
    plan: String,
    task: String,
    target_path: String,
    candidate_sha256: String,
    valid_until_utc_us: Int,
  )
}

pub type ReviewReceipt {
  ReviewReceipt(
    schema: String,
    verdict: String,
    reviewer: String,
    plan: String,
    task: String,
    target_path: String,
    candidate_sha256: String,
  )
}

pub type ActivationStatus {
  ActivationStatus(
    target_path: String,
    is_locked: Bool,
    lock_owner: Option(String),
    generation: String,
    target_exists: Bool,
    target_sha256: Option(String),
    candidate_exists: Bool,
    candidate_sha256: Option(String),
    candidate_matches: Bool,
    sqlite_valid: Bool,
  )
}

pub type RecoveryReceipt {
  RecoveryReceipt(
    receipt_id: String,
    timestamp_utc: String,
    plan: String,
    task: String,
    worker: String,
    intent_id: String,
    target_path: String,
    generation_token: String,
    candidate_path: String,
    candidate_sha256: String,
    prior_target_sha256: Option(String),
    backup_target_path: String,
    backup_wal_path: Option(String),
    backup_shm_path: Option(String),
    swapped: Bool,
    verified: Bool,
    tables_found: Int,
    status: String,
  )
}

pub type RollbackReceipt {
  RollbackReceipt(
    schema: String,
    receipt_id: String,
    timestamp_utc: String,
    plan: String,
    task: String,
    worker: String,
    intent_id: String,
    target_path: String,
    restored_from: String,
    status: String,
  )
}

pub type ActivationError {
  InvalidTarget(reason: String)
  HostBootMismatch(
    expected_host: String,
    actual_host: String,
    expected_boot: String,
    actual_boot: String,
  )
  TaskLeaseExpired(reason: String)
  TaskStateInvalid(reason: String)
  GrantInvalid(reason: String)
  ReviewerMatchesWorker(reason: String)
  ReviewReceiptMismatch(expected: String, actual: String)
  ReviewReceiptInvalid(reason: String)
  CandidateHashMismatch(expected: String, actual: String)
  TargetHashMismatch(expected: String, actual: String)
  TargetHashMissingOnExistingTarget(reason: String)
  TargetLocked(reason: String)
  QuiescenceFailed(reason: String)
  PathSafetyViolation(reason: String)
  PrivateFileSecurityViolation(reason: String)
  StagedSwapFailed(reason: String)
  IntegrityVerificationFailed(reason: String)
  CryptographicChainVerificationFailed(reason: String)
  RollbackTriggered(reason: String)
  RollbackFailedRetainingLock(reason: String)
  NativeIoError(reason: String)
}

// -----------------------------------------------------------------------------
// Lock & Generation Path Invariants
// -----------------------------------------------------------------------------

pub fn lock_path_for(target_path: String) -> String {
  target_path <> ".recovery-lock"
}

pub fn generation_path_for(target_path: String) -> String {
  target_path <> ".recovery-generation"
}

pub fn lock_payload(
  intent: ActivationIntent,
  pid: Int,
  now_utc: String,
) -> String {
  json.object([
    #("schema", json.string("uos.recovery-lock.v1")),
    #("status", json.string("ACTIVE")),
    #("pid", json.int(pid)),
    #("worker", json.string(intent.worker)),
    #("task", json.string(intent.task)),
    #("plan", json.string(intent.plan)),
    #("attempt", json.int(intent.attempt)),
    #("host_id", json.string(intent.host_id)),
    #("boot_id", json.string(intent.boot_id)),
    #("created_at_utc", json.string(now_utc)),
    #("expiry_utc_us", json.int(intent.expiry_utc_us)),
  ])
  |> json.to_string
}

// -----------------------------------------------------------------------------
// JSON Decoders & Encoders
// -----------------------------------------------------------------------------

pub fn intent_decoder() -> decode.Decoder(ActivationIntent) {
  use intent_id <- decode.field("intent_id", decode.string)
  use plan <- decode.field("plan", decode.string)
  use task <- decode.field("task", decode.string)
  use worker <- decode.field("worker", decode.string)
  use attempt <- decode.field("attempt", decode.int)
  use host_id <- decode.field("host_id", decode.string)
  use boot_id <- decode.field("boot_id", decode.string)
  use expiry_utc_us <- decode.field("expiry_utc_us", decode.int)
  use target_path <- decode.field("target_path", decode.string)
  use target_kind_str <- decode.field("target_kind", decode.string)
  use candidate_path <- decode.field("candidate_path", decode.string)
  use candidate_sha256 <- decode.field("candidate_sha256", decode.string)
  use expected_target_sha256 <- decode.field(
    "expected_target_sha256",
    decode.optional(decode.string),
  )
  use review_receipt_sha256 <- decode.field(
    "review_receipt_sha256",
    decode.string,
  )
  use operator_scope <- decode.field("operator_scope", decode.string)
  use backup_dir <- decode.field("backup_dir", decode.string)

  let target_kind = parse_target_kind(target_kind_str)

  decode.success(ActivationIntent(
    intent_id,
    plan,
    task,
    worker,
    attempt,
    host_id,
    boot_id,
    expiry_utc_us,
    target_path,
    target_kind,
    candidate_path,
    candidate_sha256,
    expected_target_sha256,
    review_receipt_sha256,
    operator_scope,
    backup_dir,
  ))
}

pub fn grant_decoder() -> decode.Decoder(ReviewedGrant) {
  use grant_id <- decode.field("grant_id", decode.string)
  use reviewer <- decode.field("reviewer", decode.string)
  use review_receipt_path <- decode.field(
    "review_receipt_path",
    decode.string,
  )
  use review_receipt_sha256 <- decode.field(
    "review_receipt_sha256",
    decode.string,
  )
  use plan <- decode.field("plan", decode.string)
  use task <- decode.field("task", decode.string)
  use target_path <- decode.field("target_path", decode.string)
  use candidate_sha256 <- decode.field("candidate_sha256", decode.string)
  use valid_until_utc_us <- decode.field("valid_until_utc_us", decode.int)
  decode.success(ReviewedGrant(
    grant_id,
    reviewer,
    review_receipt_path,
    review_receipt_sha256,
    plan,
    task,
    target_path,
    candidate_sha256,
    valid_until_utc_us,
  ))
}

pub fn review_receipt_decoder() -> decode.Decoder(ReviewReceipt) {
  use schema <- decode.field("schema", decode.string)
  use verdict <- decode.field("verdict", decode.string)
  use reviewer <- decode.field("reviewer", decode.string)
  use plan <- decode.field("plan", decode.string)
  use task <- decode.field("task", decode.string)
  use target_path <- decode.field("target_path", decode.string)
  use candidate_sha256 <- decode.field("candidate_sha256", decode.string)
  decode.success(ReviewReceipt(
    schema,
    verdict,
    reviewer,
    plan,
    task,
    target_path,
    candidate_sha256,
  ))
}

pub fn receipt_to_json(receipt: RecoveryReceipt) -> String {
  json.object([
    #("schema", json.string("uos.recovery-receipt.v1")),
    #("receipt_id", json.string(receipt.receipt_id)),
    #("timestamp_utc", json.string(receipt.timestamp_utc)),
    #("plan", json.string(receipt.plan)),
    #("task", json.string(receipt.task)),
    #("worker", json.string(receipt.worker)),
    #("intent_id", json.string(receipt.intent_id)),
    #("target_path", json.string(receipt.target_path)),
    #("generation_token", json.string(receipt.generation_token)),
    #("candidate_path", json.string(receipt.candidate_path)),
    #("candidate_sha256", json.string(receipt.candidate_sha256)),
    #(
      "prior_target_sha256",
      case receipt.prior_target_sha256 {
        Some(h) -> json.string(h)
        None -> json.null()
      },
    ),
    #("backup_target_path", json.string(receipt.backup_target_path)),
    #(
      "backup_wal_path",
      case receipt.backup_wal_path {
        Some(w) -> json.string(w)
        None -> json.null()
      },
    ),
    #(
      "backup_shm_path",
      case receipt.backup_shm_path {
        Some(s) -> json.string(s)
        None -> json.null()
      },
    ),
    #("swapped", json.bool(receipt.swapped)),
    #("verified", json.bool(receipt.verified)),
    #("tables_found", json.int(receipt.tables_found)),
    #("status", json.string(receipt.status)),
  ])
  |> json.to_string
}

pub fn rollback_receipt_to_json(receipt: RollbackReceipt) -> String {
  json.object([
    #("schema", json.string(receipt.schema)),
    #("receipt_id", json.string(receipt.receipt_id)),
    #("timestamp_utc", json.string(receipt.timestamp_utc)),
    #("plan", json.string(receipt.plan)),
    #("task", json.string(receipt.task)),
    #("worker", json.string(receipt.worker)),
    #("intent_id", json.string(receipt.intent_id)),
    #("target_path", json.string(receipt.target_path)),
    #("restored_from", json.string(receipt.restored_from)),
    #("status", json.string(receipt.status)),
  ])
  |> json.to_string
}

pub fn status_to_json(status: ActivationStatus) -> String {
  json.object([
    #("schema", json.string("uos.recovery-status.v1")),
    #("target_path", json.string(status.target_path)),
    #("is_locked", json.bool(status.is_locked)),
    #(
      "lock_owner",
      case status.lock_owner {
        Some(o) -> json.string(o)
        None -> json.null()
      },
    ),
    #("generation", json.string(status.generation)),
    #("target_exists", json.bool(status.target_exists)),
    #(
      "target_sha256",
      case status.target_sha256 {
        Some(h) -> json.string(h)
        None -> json.null()
      },
    ),
    #("candidate_exists", json.bool(status.candidate_exists)),
    #(
      "candidate_sha256",
      case status.candidate_sha256 {
        Some(h) -> json.string(h)
        None -> json.null()
      },
    ),
    #("candidate_matches", json.bool(status.candidate_matches)),
    #("sqlite_valid", json.bool(status.sqlite_valid)),
  ])
  |> json.to_string
}

// -----------------------------------------------------------------------------
// Cryptographic Chain Verification Oracles
// -----------------------------------------------------------------------------

pub fn verify_target_cryptographic_chain(
  kind: TargetKind,
  path: String,
) -> Result(Int, ActivationError) {
  case kind {
    CoordinatorStore -> {
      case verify_coordinator_chain(path) {
        Ok(count) -> Ok(count)
        Error(err) ->
          Error(CryptographicChainVerificationFailed(
            "coordinator cryptographic chain verification failed: " <> err,
          ))
      }
    }
    KmCycleStore -> {
      case verify_cycle_chain(path) {
        Ok(#(row_count, _hold_count)) -> Ok(row_count)
        Error(err) ->
          Error(CryptographicChainVerificationFailed(
            "cycle cryptographic chain verification failed: " <> err,
          ))
      }
    }
    UnsupportedTargetKind(other) -> {
      Error(InvalidTarget("unsupported target_kind: " <> other))
    }
  }
}

// -----------------------------------------------------------------------------
// Operational API: Status Query
// -----------------------------------------------------------------------------

pub fn query_status(intent: ActivationIntent) -> ActivationStatus {
  let lock_path = lock_path_for(intent.target_path)
  let gen_path = generation_path_for(intent.target_path)
  let is_locked = case is_target_locked(lock_path) {
    Ok(b) -> b
    _ -> False
  }
  let lock_owner = case is_locked {
    True ->
      case read_target_lock(lock_path) {
        Ok(c) -> Some(c)
        _ -> None
      }
    False -> None
  }
  let gen_token = case read_generation(gen_path) {
    Ok(g) -> g
    _ -> "genesis"
  }
  let target_exists = file_exists(intent.target_path)
  let target_sha256 = case target_exists {
    True ->
      case sha256_file(intent.target_path) {
        Ok(h) -> Some(h)
        _ -> None
      }
    False -> None
  }
  let candidate_exists = file_exists(intent.candidate_path)
  let candidate_sha256 = case candidate_exists {
    True ->
      case sha256_file(intent.candidate_path) {
        Ok(h) -> Some(h)
        _ -> None
      }
    False -> None
  }
  let candidate_matches = case candidate_sha256 {
    Some(actual) -> actual == intent.candidate_sha256
    None -> False
  }
  let sqlite_valid = case candidate_exists {
    True ->
      case
        sqlite_verify_integrity(intent.candidate_path),
        verify_target_cryptographic_chain(
          intent.target_kind,
          intent.candidate_path,
        )
      {
        Ok(cnt), Ok(_) if cnt >= 0 -> True
        _, _ -> False
      }
    False -> False
  }
  ActivationStatus(
    target_path: intent.target_path,
    is_locked: is_locked,
    lock_owner: lock_owner,
    generation: gen_token,
    target_exists: target_exists,
    target_sha256: target_sha256,
    candidate_exists: candidate_exists,
    candidate_sha256: candidate_sha256,
    candidate_matches: candidate_matches,
    sqlite_valid: sqlite_valid,
  )
}

pub fn validate_canonical_target(
  intent: ActivationIntent,
) -> Result(Nil, ActivationError) {
  let target_is_sqlite =
    string.ends_with(intent.target_path, ".sqlite3")
    || string.ends_with(intent.target_path, ".db")
  use _ <- result.try(case target_is_sqlite {
    True -> Ok(Nil)
    False ->
      Error(InvalidTarget(
        "target_path must be an SQLite database ending in .sqlite3 or .db: "
        <> intent.target_path,
      ))
  })

  let candidate_is_sqlite =
    string.ends_with(intent.candidate_path, ".sqlite3")
    || string.ends_with(intent.candidate_path, ".db")
  use _ <- result.try(case candidate_is_sqlite {
    True -> Ok(Nil)
    False ->
      Error(InvalidTarget(
        "candidate_path must be an SQLite database ending in .sqlite3 or .db: "
        <> intent.candidate_path,
      ))
  })

  use _ <- result.try(case intent.target_path != intent.candidate_path {
    True -> Ok(Nil)
    False ->
      Error(InvalidTarget("candidate_path cannot be identical to target_path"))
  })

  case intent.target_kind {
    CoordinatorStore -> {
      case intent.operator_scope == "coordinator" {
        True -> Ok(Nil)
        False ->
          Error(InvalidTarget(
            "operator_scope for CoordinatorStore must be 'coordinator', found: "
            <> intent.operator_scope,
          ))
      }
    }
    KmCycleStore -> {
      case
        intent.operator_scope == "km_cycle"
        || intent.operator_scope == "km_cycles"
      {
        True -> Ok(Nil)
        False ->
          Error(InvalidTarget(
            "operator_scope for KmCycleStore must be 'km_cycle' or 'km_cycles', found: "
            <> intent.operator_scope,
          ))
      }
    }
    UnsupportedTargetKind(other) ->
      Error(InvalidTarget("unsupported target_kind: " <> other))
  }
}

pub fn validate_intent_and_grant(
  intent: ActivationIntent,
  grant: ReviewedGrant,
) -> Result(Nil, ActivationError) {
  // 0. Enforce finite canonical targets directly
  use _ <- result.try(validate_canonical_target(intent))

  // 1. Reviewer identity must be strictly different from worker identity!
  use _ <- result.try(case grant.reviewer != intent.worker {
    True -> Ok(Nil)
    False ->
      Error(ReviewerMatchesWorker(
        "reviewer "
        <> grant.reviewer
        <> " cannot match worker "
        <> intent.worker,
      ))
  })

  // 2. Private file security check on grant's review receipt file
  use _ <- result.try(
    check_private_file(grant.review_receipt_path)
    |> result.map_error(PrivateFileSecurityViolation),
  )

  // 3. Path safety checks on target and backup dirs
  use _ <- result.try(
    path_safety_check(intent.target_path)
    |> result.map_error(PathSafetyViolation),
  )
  use _ <- result.try(
    path_safety_check(intent.backup_dir)
    |> result.map_error(PathSafetyViolation),
  )

  // 4. Strict Host & Boot clock identity verification
  use #(obs_host, obs_boot, _, now_utc_us) <- result.try(
    ffi_clock()
    |> result.map_error(fn(e) {
      GrantInvalid("strict clock observation failed: " <> e)
    }),
  )
  use _ <- result.try(case
    obs_host == intent.host_id && obs_boot == intent.boot_id
  {
    True -> Ok(Nil)
    False ->
      Error(HostBootMismatch(
        expected_host: intent.host_id,
        actual_host: obs_host,
        expected_boot: intent.boot_id,
        actual_boot: obs_boot,
      ))
  })

  // 5. Grant authorization parameters verification
  use _ <- result.try(case
    grant.plan == intent.plan
    && grant.task == intent.task
    && grant.target_path == intent.target_path
    && grant.candidate_sha256 == intent.candidate_sha256
    && grant.review_receipt_sha256 == intent.review_receipt_sha256
  {
    True -> Ok(Nil)
    False ->
      Error(GrantInvalid(
        "grant parameters do not match intent or review receipt digest",
      ))
  })

  // 6. Expiry checks
  use _ <- result.try(case
    now_utc_us < grant.valid_until_utc_us
    && now_utc_us < intent.expiry_utc_us
  {
    True -> Ok(Nil)
    False -> Error(GrantInvalid("grant or intent expired before operation"))
  })

  // 7. Review receipt presence and digest check
  use actual_receipt_sha256 <- result.try(
    sha256_file(grant.review_receipt_path)
    |> result.map_error(fn(e) {
      ReviewReceiptMismatch(
        expected: grant.review_receipt_sha256,
        actual: "file_unreadable:" <> e,
      )
    }),
  )
  use _ <- result.try(case
    actual_receipt_sha256 == grant.review_receipt_sha256
  {
    True -> Ok(Nil)
    False ->
      Error(ReviewReceiptMismatch(
        expected: grant.review_receipt_sha256,
        actual: actual_receipt_sha256,
      ))
  })

  // 8. Review receipt content validation
  use receipt_raw <- result.try(
    simplifile.read(grant.review_receipt_path)
    |> result.map_error(fn(e) {
      ReviewReceiptInvalid(
        "could not read review receipt file: " <> simplifile.describe_error(e),
      )
    }),
  )
  use receipt <- result.try(
    json.parse(receipt_raw, review_receipt_decoder())
    |> result.map_error(fn(_) {
      ReviewReceiptInvalid("review receipt JSON failed schema validation")
    }),
  )
  use _ <- result.try(case receipt.schema == "uos.recovery-review-receipt.v1" {
    True -> Ok(Nil)
    False ->
      Error(ReviewReceiptInvalid(
        "review receipt schema mismatch; expected uos.recovery-review-receipt.v1, found "
        <> receipt.schema,
      ))
  })
  use _ <- result.try(case receipt.verdict == "PASS" {
    True -> Ok(Nil)
    False ->
      Error(ReviewReceiptInvalid(
        "review receipt verdict is not PASS; found " <> receipt.verdict,
      ))
  })
  use _ <- result.try(case receipt.reviewer == grant.reviewer {
    True -> Ok(Nil)
    False ->
      Error(ReviewReceiptInvalid(
        "review receipt reviewer mismatch; expected "
        <> grant.reviewer
        <> ", found "
        <> receipt.reviewer,
      ))
  })
  use _ <- result.try(case receipt.reviewer != intent.worker {
    True -> Ok(Nil)
    False ->
      Error(ReviewerMatchesWorker(
        "review receipt reviewer cannot match worker: " <> receipt.reviewer,
      ))
  })
  use _ <- result.try(case receipt.plan == intent.plan {
    True -> Ok(Nil)
    False ->
      Error(ReviewReceiptInvalid(
        "review receipt plan mismatch; expected "
        <> intent.plan
        <> ", found "
        <> receipt.plan,
      ))
  })
  use _ <- result.try(case receipt.task == intent.task {
    True -> Ok(Nil)
    False ->
      Error(ReviewReceiptInvalid(
        "review receipt task mismatch; expected "
        <> intent.task
        <> ", found "
        <> receipt.task,
      ))
  })
  use _ <- result.try(case receipt.target_path == intent.target_path {
    True -> Ok(Nil)
    False ->
      Error(ReviewReceiptInvalid(
        "review receipt target_path mismatch; expected "
        <> intent.target_path
        <> ", found "
        <> receipt.target_path,
      ))
  })
  use _ <- result.try(case receipt.candidate_sha256 == intent.candidate_sha256 {
    True -> Ok(Nil)
    False ->
      Error(ReviewReceiptInvalid(
        "review receipt candidate_sha256 mismatch; expected "
        <> intent.candidate_sha256
        <> ", found "
        <> receipt.candidate_sha256,
      ))
  })

  Ok(Nil)
}

pub fn prepare(
  intent: ActivationIntent,
  grant: ReviewedGrant,
) -> Result(Nil, ActivationError) {
  use _ <- result.try(validate_intent_and_grant(intent, grant))
  use _ <- result.try(
    path_safety_check(intent.candidate_path)
    |> result.map_error(PathSafetyViolation),
  )

  // 9. Candidate digest and cryptographic chain verification
  // Candidate is strictly immutable; NOT checkpoint-mutated after digest verification.
  use actual_candidate_sha256 <- result.try(
    sha256_file(intent.candidate_path)
    |> result.map_error(fn(e) {
      CandidateHashMismatch(
        expected: intent.candidate_sha256,
        actual: "file_unreadable:" <> e,
      )
    }),
  )
  use _ <- result.try(case actual_candidate_sha256 == intent.candidate_sha256 {
    True -> Ok(Nil)
    False ->
      Error(CandidateHashMismatch(
        expected: intent.candidate_sha256,
        actual: actual_candidate_sha256,
      ))
  })
  use _ <- result.try(
    sqlite_verify_integrity(intent.candidate_path)
    |> result.map_error(IntegrityVerificationFailed),
  )
  use _ <- result.try(
    verify_target_cryptographic_chain(intent.target_kind, intent.candidate_path),
  )

  // 10. Target presence and expected hash verification
  // Existing targets REQUIRE an expected_target_sha256; None is refused on existing targets.
  case file_exists(intent.target_path) {
    True -> {
      case intent.expected_target_sha256 {
        None ->
          Error(TargetHashMissingOnExistingTarget(
            "expected_target_sha256 is mandatory when target already exists",
          ))
        Some(expected) -> {
          use actual_target <- result.try(
            sha256_file(intent.target_path)
            |> result.map_error(fn(e) {
              TargetHashMismatch(expected: expected, actual: "unreadable:" <> e)
            }),
          )
          case actual_target == expected {
            True -> Ok(Nil)
            False ->
              Error(TargetHashMismatch(
                expected: expected,
                actual: actual_target,
              ))
          }
        }
      }
    }
    False -> Ok(Nil)
  }
}

// -----------------------------------------------------------------------------
// Canonical Sa-Plan Effect-Time Task Verification
// -----------------------------------------------------------------------------

pub fn validate_canonical_sa_plan_task(
  intent: ActivationIntent,
) -> Result(Nil, ActivationError) {
  let binding =
    dev.Binding(
      role: "recovery_activator",
      plan: intent.plan,
      task: intent.task,
      worker: intent.worker,
      attempt: intent.attempt,
      session: "recovery_session",
      epoch: 1,
    )
  use row <- result.try(
    dev.read_task(binding)
    |> result.map_error(fn(err) {
      TaskStateInvalid("sa-plan read_task query failed: " <> err)
    }),
  )
  case row.state == "executing" {
    False ->
      Error(TaskStateInvalid(
        "task is not executing; state=" <> row.state,
      ))
    True -> {
      case row.worker == Some(intent.worker) {
        False ->
          Error(TaskStateInvalid(
            "worker mismatch; expected="
            <> intent.worker
            <> " found="
            <> string.inspect(row.worker),
          ))
        True -> {
          case row.attempt == intent.attempt {
            False ->
              Error(TaskStateInvalid(
                "attempt mismatch; expected="
                <> int.to_string(intent.attempt)
                <> " found="
                <> int.to_string(row.attempt),
              ))
            True -> {
              use #(_, _, _, now_utc_us) <- result.try(
                ffi_clock()
                |> result.map_error(fn(e) {
                  TaskLeaseExpired("clock failed during task check: " <> e)
                }),
              )
              let now_ns = now_utc_us * 1000
              case row.lease_until_ns {
                Some(deadline) if deadline > now_ns + 5_000_000_000 -> Ok(Nil)
                _ ->
                  Error(TaskLeaseExpired(
                    "lease expired or insufficient remaining window (<5s)",
                  ))
              }
            }
          }
        }
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Operational API: Activate (Full Staged Swap Under Lock)
// -----------------------------------------------------------------------------

fn rollback_or_hold(
  target_path: String,
  bk_unique_dir: String,
  lock_path: String,
  backup_dir: String,
  intent_id: String,
  utc_us: Int,
  now_utc: String,
  cause: String,
) -> Result(a, ActivationError) {
  let _ =
    persist_phase_receipt(
      backup_dir,
      intent_id,
      "ROLLBACK_TRIGGERED",
      utc_us,
      now_utc,
      "{\"cause\":\"" <> cause <> "\"}",
    )
  case rollback_from_manifest(target_path, bk_unique_dir) {
    Error(rb_err) -> {
      let _ =
        hold_target_lock(
          lock_path,
          cause <> " and rollback failed: " <> rb_err,
          now_utc,
        )
      let _ =
        persist_phase_receipt(
          backup_dir,
          intent_id,
          "HOLD",
          utc_us,
          now_utc,
          "{\"cause\":\"" <> cause <> "\",\"error\":\"" <> rb_err <> "\"}",
        )
      Error(RollbackFailedRetainingLock(
        cause <> " and rollback failed: " <> rb_err,
      ))
    }
    Ok(Nil) -> {
      let _ =
        persist_phase_receipt(
          backup_dir,
          intent_id,
          "ROLLED_BACK",
          utc_us,
          now_utc,
          "{\"reason\":\"" <> cause <> "\"}",
        )
      Error(RollbackTriggered(cause))
    }
  }
}

pub fn activate(
  intent: ActivationIntent,
  grant: ReviewedGrant,
) -> Result(RecoveryReceipt, ActivationError) {
  activate_with_task_validator(intent, grant, fn() {
    validate_canonical_sa_plan_task(intent)
  })
}

pub fn activate_with_task_validator(
  intent: ActivationIntent,
  grant: ReviewedGrant,
  task_validator: fn() -> Result(Nil, ActivationError),
) -> Result(RecoveryReceipt, ActivationError) {
  // 1. Run full prepare checks first
  use _ <- result.try(prepare(intent, grant))

  // 2. Quiescence check before lock acquisition (inspects main target, -wal, -shm)
  use _ <- result.try(
    check_quiescence(intent.target_path)
    |> result.map_error(QuiescenceFailed),
  )

  // 3. Exclusive target lock acquisition at TARGET <> ".recovery-lock"
  let lock_path = lock_path_for(intent.target_path)
  let gen_path = generation_path_for(intent.target_path)
  let pid = get_pid()
  let now_utc = utc_now_iso8601()
  let lock_body = lock_payload(intent, pid, now_utc)
  use _ <- result.try(
    acquire_target_lock(lock_path, lock_body)
    |> result.map_error(TargetLocked),
  )

  // 4. Critical Section Under Lock
  let execution_result = {
    use #(_host, _boot, _tick, utc_us) <- result.try(
      ffi_clock()
      |> result.map_error(NativeIoError),
    )
    use _ <- result.try(
      persist_phase_receipt(
        intent.backup_dir,
        intent.intent_id,
        "LOCKED",
        utc_us,
        now_utc,
        "{}",
      )
      |> result.map_error(fn(err) {
        NativeIoError("failed to persist LOCKED phase receipt: " <> err)
      }),
    )

    // a. Effect-time task lease check under lock
    use _ <- result.try(task_validator())

    // b. Under lock, recheck target hash if target exists
    use prior_hash <- result.try(case
      file_exists(intent.target_path),
      intent.expected_target_sha256
    {
      True, Some(expected) -> {
        use current_target_sha256 <- result.try(
          sha256_file(intent.target_path)
          |> result.map_error(fn(e) {
            TargetHashMismatch(expected: expected, actual: "unreadable:" <> e)
          }),
        )
        use _ <- result.try(case current_target_sha256 == expected {
          True -> Ok(Nil)
          False ->
            Error(TargetHashMismatch(
              expected: expected,
              actual: current_target_sha256,
            ))
        })
        Ok(Some(current_target_sha256))
      }
      True, None ->
        Error(TargetHashMissingOnExistingTarget(
          "expected_target_sha256 missing on existing target",
        ))
      False, _ -> Ok(None)
    })

    // c. Atomically advance persistent generation BEFORE preservation/swap
    let gen_token = intent.intent_id <> "-" <> int.to_string(pid) <> "-gen"
    use _ <- result.try(
      advance_generation(gen_path, gen_token)
      |> result.map_error(NativeIoError),
    )
    use _ <- result.try(
      persist_phase_receipt(
        intent.backup_dir,
        intent.intent_id,
        "GENERATION_ADVANCED",
        utc_us,
        now_utc,
        "{\"generation\":\"" <> gen_token <> "\"}",
      )
      |> result.map_error(fn(err) {
        NativeIoError(
          "failed to persist GENERATION_ADVANCED phase receipt: " <> err,
        )
      }),
    )

    // d. Re-check quiescence under lock AFTER generation advance!
    use _ <- result.try(
      check_quiescence(intent.target_path)
      |> result.map_error(fn(err) {
        QuiescenceFailed("open handles remain after generation advance: " <> err)
      }),
    )
    use _ <- result.try(
      persist_phase_receipt(
        intent.backup_dir,
        intent.intent_id,
        "QUIESCENCE_RECHECKED",
        utc_us,
        now_utc,
        "{}",
      )
      |> result.map_error(fn(err) {
        NativeIoError(
          "failed to persist QUIESCENCE_RECHECKED phase receipt: " <> err,
        )
      }),
    )

    // e. Preserve target files (DB, WAL, SHM) into unique exclusive backup dir with manifest
    use #(bk_unique_dir, bk_target, bk_wal, bk_shm, _bk_hash) <- result.try(
      preserve_target_state(
        intent.target_path,
        intent.backup_dir,
        intent.intent_id,
        intent.attempt,
        gen_token,
        utc_us,
        now_utc,
      )
      |> result.map_error(NativeIoError),
    )
    use _ <- result.try(
      persist_phase_receipt(
        intent.backup_dir,
        intent.intent_id,
        "TARGET_PRESERVED",
        utc_us,
        now_utc,
        "{\"backup_dir\":\"" <> bk_unique_dir <> "\"}",
      )
      |> result.map_error(fn(err) {
        NativeIoError(
          "failed to persist TARGET_PRESERVED phase receipt: " <> err,
        )
      }),
    )

    // Recheck fresh task lease and clock against grant/intent expiry immediately
    // before destructive sidecar retirement!
    use _ <- result.try(task_validator())
    use #(
      _obs_host_retire,
      _obs_boot_retire,
      _obs_tick_retire,
      now_before_retire_us,
    ) <- result.try(
      ffi_clock()
      |> result.map_error(NativeIoError),
    )
    use _ <- result.try(case
      now_before_retire_us < grant.valid_until_utc_us
      && now_before_retire_us < intent.expiry_utc_us
    {
      True -> Ok(Nil)
      False ->
        Error(GrantInvalid(
          "grant or intent expired before destructive sidecar retirement",
        ))
    })

    // f. Retire target sidecars BEFORE replacing main DB
    case retire_target_sidecars(intent.target_path) {
      Error(ret_err) ->
        rollback_or_hold(
          intent.target_path,
          bk_unique_dir,
          lock_path,
          intent.backup_dir,
          intent.intent_id,
          utc_us,
          now_utc,
          "sidecar retirement failed: " <> ret_err,
        )
      Ok(Nil) -> {
        case
          persist_phase_receipt(
            intent.backup_dir,
            intent.intent_id,
            "SIDECARS_RETIRED",
            utc_us,
            now_utc,
            "{}",
          )
        {
          Error(p_err) ->
            rollback_or_hold(
              intent.target_path,
              bk_unique_dir,
              lock_path,
              intent.backup_dir,
              intent.intent_id,
              utc_us,
              now_utc,
              "failed to persist SIDECARS_RETIRED phase receipt: " <> p_err,
            )
          Ok(Nil) -> {
            // g. Recheck candidate hash under lock immediately before staged swap!
            case sha256_file(intent.candidate_path) {
              Error(cand_err) ->
                rollback_or_hold(
                  intent.target_path,
                  bk_unique_dir,
                  lock_path,
                  intent.backup_dir,
                  intent.intent_id,
                  utc_us,
                  now_utc,
                  "candidate unreadable before staged swap: " <> cand_err,
                )
              Ok(pre_swap_hash) if pre_swap_hash != intent.candidate_sha256 ->
                rollback_or_hold(
                  intent.target_path,
                  bk_unique_dir,
                  lock_path,
                  intent.backup_dir,
                  intent.intent_id,
                  utc_us,
                  now_utc,
                  "candidate hash mutated before swap: expected "
                    <> intent.candidate_sha256
                    <> " found "
                    <> pre_swap_hash,
                )
              Ok(_) -> {
                // h. Perform atomic staged swap (staged_swap_database verifies temp file hash matches expected before rename)
                case
                  staged_swap_database(
                    intent.candidate_path,
                    intent.target_path,
                    intent.candidate_sha256,
                  )
                {
                  Error(swap_err) ->
                    rollback_or_hold(
                      intent.target_path,
                      bk_unique_dir,
                      lock_path,
                      intent.backup_dir,
                      intent.intent_id,
                      utc_us,
                      now_utc,
                      "staged swap failed: " <> swap_err,
                    )
                  Ok(Nil) -> {
                    case
                      persist_phase_receipt(
                        intent.backup_dir,
                        intent.intent_id,
                        "SWAPPED",
                        utc_us,
                        now_utc,
                        "{}",
                      )
                    {
                      Error(p_err) ->
                        rollback_or_hold(
                          intent.target_path,
                          bk_unique_dir,
                          lock_path,
                          intent.backup_dir,
                          intent.intent_id,
                          utc_us,
                          now_utc,
                          "failed to persist SWAPPED phase receipt: " <> p_err,
                        )
                      Ok(Nil) -> {
                        // i. Reopened SQLite integrity check
                        case sqlite_verify_integrity(intent.target_path) {
                          Error(int_err) ->
                            rollback_or_hold(
                              intent.target_path,
                              bk_unique_dir,
                              lock_path,
                              intent.backup_dir,
                              intent.intent_id,
                              utc_us,
                              now_utc,
                              "reopened integrity check failed: " <> int_err,
                            )
                          Ok(table_count) -> {
                            // j. Full cryptographic chain verification beyond SQLite PRAGMA
                            case
                              verify_target_cryptographic_chain(
                                intent.target_kind,
                                intent.target_path,
                              )
                            {
                              Error(chain_err) ->
                                rollback_or_hold(
                                  intent.target_path,
                                  bk_unique_dir,
                                  lock_path,
                                  intent.backup_dir,
                                  intent.intent_id,
                                  utc_us,
                                  now_utc,
                                  "cryptographic chain verification failed: "
                                    <> string.inspect(chain_err),
                                )
                              Ok(_) -> {
                                // k. Verify swapped database hash matches candidate exactly
                                case sha256_file(intent.target_path) {
                                  Error(h_err) ->
                                    rollback_or_hold(
                                      intent.target_path,
                                      bk_unique_dir,
                                      lock_path,
                                      intent.backup_dir,
                                      intent.intent_id,
                                      utc_us,
                                      now_utc,
                                      "could not hash swapped target: " <> h_err,
                                    )
                                  Ok(new_hash)
                                    if new_hash != intent.candidate_sha256
                                  ->
                                    rollback_or_hold(
                                      intent.target_path,
                                      bk_unique_dir,
                                      lock_path,
                                      intent.backup_dir,
                                      intent.intent_id,
                                      utc_us,
                                      now_utc,
                                      "swapped target hash mismatch: expected "
                                        <> intent.candidate_sha256
                                        <> " got "
                                        <> new_hash,
                                    )
                                  Ok(_) -> {
                                    // l. Persist COMPLETED phase receipt. If persistence fails: retain HOLD!
                                    case
                                      persist_phase_receipt(
                                        intent.backup_dir,
                                        intent.intent_id,
                                        "COMPLETED",
                                        utc_us,
                                        now_utc,
                                        "{}",
                                      )
                                    {
                                      Error(comp_err) -> {
                                        let _ =
                                          hold_target_lock(
                                            lock_path,
                                            "completed_phase_receipt_failed: "
                                              <> comp_err,
                                            now_utc,
                                          )
                                        let _ =
                                          persist_phase_receipt(
                                            intent.backup_dir,
                                            intent.intent_id,
                                            "HOLD",
                                            utc_us,
                                            now_utc,
                                            "{\"error\":\"" <> comp_err <> "\"}",
                                          )
                                        Error(RollbackFailedRetainingLock(
                                          "failed to persist COMPLETED phase receipt: "
                                          <> comp_err,
                                        ))
                                      }
                                      Ok(Nil) -> {
                                        let receipt =
                                          RecoveryReceipt(
                                            receipt_id: "rcv-"
                                              <> intent.intent_id,
                                            timestamp_utc: now_utc,
                                            plan: intent.plan,
                                            task: intent.task,
                                            worker: intent.worker,
                                            intent_id: intent.intent_id,
                                            target_path: intent.target_path,
                                            generation_token: gen_token,
                                            candidate_path: intent.candidate_path,
                                            candidate_sha256: intent.candidate_sha256,
                                            prior_target_sha256: prior_hash,
                                            backup_target_path: bk_target,
                                            backup_wal_path: case bk_wal {
                                              "" -> None
                                              w -> Some(w)
                                            },
                                            backup_shm_path: case bk_shm {
                                              "" -> None
                                              s -> Some(s)
                                            },
                                            swapped: True,
                                            verified: True,
                                            tables_found: table_count,
                                            status: "ACTIVATED",
                                          )
                                        Ok(receipt)
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

  // 5. Lock release decision: NEVER release lock if status is HOLD!
  case execution_result {
    Error(RollbackFailedRetainingLock(_)) -> Nil
    _ -> {
      let _ = release_target_lock(lock_path, pid)
      Nil
    }
  }

  execution_result
}

// -----------------------------------------------------------------------------
// Operational API: Rollback (Full Policy Verification)
// -----------------------------------------------------------------------------

pub fn rollback(
  intent: ActivationIntent,
  grant: ReviewedGrant,
) -> Result(RollbackReceipt, ActivationError) {
  rollback_with_task_validator(intent, grant, fn() {
    validate_canonical_sa_plan_task(intent)
  })
}

pub fn rollback_with_task_validator(
  intent: ActivationIntent,
  grant: ReviewedGrant,
  task_validator: fn() -> Result(Nil, ActivationError),
) -> Result(RollbackReceipt, ActivationError) {
  // 1. Run policy verification on intent & grant
  use _ <- result.try(validate_intent_and_grant(intent, grant))

  // 2. Quiescence check
  use _ <- result.try(
    check_quiescence(intent.target_path)
    |> result.map_error(QuiescenceFailed),
  )

  // 3. Acquire target lock
  let lock_path = lock_path_for(intent.target_path)
  let pid = get_pid()
  let now_utc = utc_now_iso8601()
  let lock_body = lock_payload(intent, pid, now_utc)
  use _ <- result.try(
    acquire_target_lock(lock_path, lock_body)
    |> result.map_error(TargetLocked),
  )

  // 4. Critical Section Under Lock
  let unique_backup_dir =
    intent.backup_dir
    <> "/bk-"
    <> intent.intent_id
    <> "-att"
    <> int.to_string(intent.attempt)

  let execution_result = {
    use #(_host, _boot, _tick, utc_us) <- result.try(
      ffi_clock()
      |> result.map_error(NativeIoError),
    )
    use _ <- result.try(
      persist_phase_receipt(
        intent.backup_dir,
        intent.intent_id,
        "ROLLBACK_LOCKED",
        utc_us,
        now_utc,
        "{}",
      )
      |> result.map_error(fn(err) {
        NativeIoError("failed to persist ROLLBACK_LOCKED phase receipt: " <> err)
      }),
    )

    // a. Validate fresh task attempt/lease under lock
    use _ <- result.try(task_validator())

    // b. Execute deterministic rollback from manifest
    let rb_res = rollback_from_manifest(intent.target_path, unique_backup_dir)
    case rb_res {
      Error(rb_err) -> {
        let _ =
          hold_target_lock(
            lock_path,
            "manual_rollback_failed: " <> rb_err,
            now_utc,
          )
        let _ =
          persist_phase_receipt(
            intent.backup_dir,
            intent.intent_id,
            "HOLD",
            utc_us,
            now_utc,
            "{\"error\":\"" <> rb_err <> "\"}",
          )
        Error(RollbackFailedRetainingLock(
          "manual rollback from manifest failed: " <> rb_err,
        ))
      }
      Ok(Nil) -> {
        // c. Verify SQLite integrity if target exists
        case file_exists(intent.target_path) {
          True -> {
            case sqlite_verify_integrity(intent.target_path) {
              Error(int_err) -> {
                let _ =
                  hold_target_lock(
                    lock_path,
                    "restored_target_integrity_failed: " <> int_err,
                    now_utc,
                  )
                let _ =
                  persist_phase_receipt(
                    intent.backup_dir,
                    intent.intent_id,
                    "HOLD",
                    utc_us,
                    now_utc,
                    "{\"error\":\"" <> int_err <> "\"}",
                  )
                Error(RollbackFailedRetainingLock(
                  "restored target failed integrity: " <> int_err,
                ))
              }
              Ok(_) -> {
                case
                  persist_phase_receipt(
                    intent.backup_dir,
                    intent.intent_id,
                    "ROLLED_BACK",
                    utc_us,
                    now_utc,
                    "{\"restored_from\":\"" <> unique_backup_dir <> "\"}",
                  )
                {
                  Error(p_err) -> {
                    let _ =
                      hold_target_lock(
                        lock_path,
                        "rollback_phase_receipt_failed: " <> p_err,
                        now_utc,
                      )
                    let _ =
                      persist_phase_receipt(
                        intent.backup_dir,
                        intent.intent_id,
                        "HOLD",
                        utc_us,
                        now_utc,
                        "{\"error\":\"" <> p_err <> "\"}",
                      )
                    Error(RollbackFailedRetainingLock(
                      "failed to persist ROLLED_BACK phase receipt: " <> p_err,
                    ))
                  }
                  Ok(Nil) -> {
                    let receipt =
                      RollbackReceipt(
                        schema: "uos.recovery-rollback-receipt.v1",
                        receipt_id: "rb-" <> intent.intent_id,
                        timestamp_utc: now_utc,
                        plan: intent.plan,
                        task: intent.task,
                        worker: intent.worker,
                        intent_id: intent.intent_id,
                        target_path: intent.target_path,
                        restored_from: unique_backup_dir,
                        status: "ROLLED_BACK",
                      )
                    Ok(receipt)
                  }
                }
              }
            }
          }
          False -> {
            case
              persist_phase_receipt(
                intent.backup_dir,
                intent.intent_id,
                "ROLLED_BACK",
                utc_us,
                now_utc,
                "{\"restored_from\":\"" <> unique_backup_dir <> "\"}",
              )
            {
              Error(p_err) -> {
                let _ =
                  hold_target_lock(
                    lock_path,
                    "rollback_phase_receipt_failed: " <> p_err,
                    now_utc,
                  )
                let _ =
                  persist_phase_receipt(
                    intent.backup_dir,
                    intent.intent_id,
                    "HOLD",
                    utc_us,
                    now_utc,
                    "{\"error\":\"" <> p_err <> "\"}",
                  )
                Error(RollbackFailedRetainingLock(
                  "failed to persist ROLLED_BACK phase receipt: " <> p_err,
                ))
              }
              Ok(Nil) -> {
                let receipt =
                  RollbackReceipt(
                    schema: "uos.recovery-rollback-receipt.v1",
                    receipt_id: "rb-" <> intent.intent_id,
                    timestamp_utc: now_utc,
                    plan: intent.plan,
                    task: intent.task,
                    worker: intent.worker,
                    intent_id: intent.intent_id,
                    target_path: intent.target_path,
                    restored_from: unique_backup_dir,
                    status: "ROLLED_BACK",
                  )
                Ok(receipt)
              }
            }
          }
        }
      }
    }
  }

  // 5. Lock release decision: NEVER release lock if status is HOLD!
  case execution_result {
    Error(RollbackFailedRetainingLock(_)) -> Nil
    _ -> {
      let _ = release_target_lock(lock_path, pid)
      Nil
    }
  }

  execution_result
}
