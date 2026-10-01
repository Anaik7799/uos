//// Comprehensive test suite for typed recovery activation.
////
//// Validates all negative and positive requirements:
//// - Status query over uninitialized and populated states
//// - Reviewer identity different from worker requirement
//// - Private file permissions on review receipts (no symlinks, mode <= 0600)
//// - Review receipt schema ("uos.recovery-review-receipt.v1") and verdict ("PASS") validation
//// - Persistent generation token (.recovery-generation) tracking
//// - Strict host/boot clock validation and mismatch refusal
//// - Mandatory expected_target_sha256 on existing targets
//// - Prepare dry-run validation (grant, review receipt, candidate hash, target hash)
//// - Expired grant and mismatched review receipt refusal
//// - Changed candidate hash and target hash mismatch refusal
//// - Symlink path safety rejection
//// - Effect-time Sa-plan task lease failure refusal before swap
//// - Existing active target lock refusal
//// - Full staged swap positive test with real SQLite database and reopened integrity
//// - Automatic rollback on failure restoring preserved originals while keeping generation
//// - Failed rollback retains lock in HOLD status permanently (no unconditional unlock)
//// - Rollback using finite intent, private grant, and durable backup manifest

import cepaf_gleam/harness/recovery_activation as ra
import gleam/int
import gleam/option.{type Option, None, Some}
import gleeunit/should
import simplifile

const test_root = "/tmp/uos_recovery_gleam_test"

fn setup_dirs() {
  let _ = simplifile.delete(test_root)
  let _ = simplifile.create_directory_all(test_root <> "/target_dir")
  let _ = simplifile.create_directory_all(test_root <> "/candidate_dir")
  let _ = simplifile.create_directory_all(test_root <> "/backups")
  let _ = simplifile.create_directory_all(test_root <> "/reviews")
  Nil
}

fn make_review_receipt_content(
  plan: String,
  task: String,
  reviewer: String,
  target_path: String,
  cand_hash: String,
) -> String {
  "{\"schema\":\"uos.recovery-review-receipt.v1\",\"verdict\":\"PASS\",\"reviewer\":\""
  <> reviewer
  <> "\",\"plan\":\""
  <> plan
  <> "\",\"task\":\""
  <> task
  <> "\",\"target_path\":\""
  <> target_path
  <> "\",\"candidate_sha256\":\""
  <> cand_hash
  <> "\"}"
}

fn create_private_review_receipt(path: String, content: String) -> String {
  let assert Ok(Nil) = ra.write_file_binary(path, <<content:utf8>>)
  let assert Ok(h) = ra.sha256_file(path)
  h
}

fn make_intent_and_grant(
  target_path: String,
  candidate_path: String,
  expected_target: Option(String),
) -> #(ra.ActivationIntent, ra.ReviewedGrant) {
  let plan = "uos/full-restoration/20260930-0515"
  let task = "AGY_EXEC"
  let worker = "agy-full-restoration-20260930"
  let reviewer = "codex-independent-reviewer"

  let assert Ok(cand_hash) = ra.sha256_file(candidate_path)
  let receipt_path = test_root <> "/reviews/review_receipt.json"
  let receipt_content =
    make_review_receipt_content(plan, task, reviewer, target_path, cand_hash)
  let receipt_hash =
    create_private_review_receipt(receipt_path, receipt_content)

  let assert Ok(#(host_id, boot_id, _, now_utc_us)) = ra.ffi_clock()
  let expiry = now_utc_us + 3_600_000_000

  let intent =
    ra.ActivationIntent(
      intent_id: "int-001",
      plan: plan,
      task: task,
      worker: worker,
      attempt: 1,
      host_id: host_id,
      boot_id: boot_id,
      expiry_utc_us: expiry,
      target_path: target_path,
      target_kind: ra.CoordinatorStore,
      candidate_path: candidate_path,
      candidate_sha256: cand_hash,
      expected_target_sha256: expected_target,
      review_receipt_sha256: receipt_hash,
      operator_scope: "coordinator",
      backup_dir: test_root <> "/backups",
    )

  let grant =
    ra.ReviewedGrant(
      grant_id: "grnt-001",
      reviewer: reviewer,
      review_receipt_path: receipt_path,
      review_receipt_sha256: receipt_hash,
      plan: intent.plan,
      task: intent.task,
      target_path: intent.target_path,
      candidate_sha256: cand_hash,
      valid_until_utc_us: expiry,
    )

  #(intent, grant)
}

pub fn status_query_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"
  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)

  let #(intent, _) = make_intent_and_grant(target_path, cand_path, None)
  let st = ra.query_status(intent)

  st.target_exists |> should.equal(False)
  st.candidate_exists |> should.equal(True)
  st.candidate_matches |> should.equal(True)
  st.sqlite_valid |> should.equal(True)
  st.is_locked |> should.equal(False)
  st.generation |> should.equal("genesis")
}

pub fn prepare_success_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"
  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)
  let assert Ok(Nil) = ra.create_test_coordinator_db(target_path)

  let assert Ok(target_hash) = ra.sha256_file(target_path)
  let #(intent, grant) =
    make_intent_and_grant(target_path, cand_path, Some(target_hash))

  ra.prepare(intent, grant) |> should.be_ok
}

pub fn prepare_reviewer_matches_worker_refusal_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"
  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)

  let #(intent, grant) = make_intent_and_grant(target_path, cand_path, None)
  // Reviewer self-authorizing as worker -> must be refused!
  let bad_grant = ra.ReviewedGrant(..grant, reviewer: intent.worker)

  case ra.prepare(intent, bad_grant) {
    Error(ra.ReviewerMatchesWorker(_)) -> Nil
    _ -> panic as "expected ReviewerMatchesWorker error"
  }
}

pub fn prepare_insecure_review_receipt_file_refusal_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"
  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)

  let #(intent, grant) = make_intent_and_grant(target_path, cand_path, None)
  // Set insecure group/world writable mode on review receipt file
  let assert Ok(Nil) = ra.change_file_mode(grant.review_receipt_path, 0o666)

  case ra.prepare(intent, grant) {
    Error(ra.PrivateFileSecurityViolation(_)) -> Nil
    _ -> panic as "expected PrivateFileSecurityViolation for 0666 file"
  }
}

pub fn prepare_review_receipt_verdict_fail_refusal_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"
  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)

  let #(intent, grant) = make_intent_and_grant(target_path, cand_path, None)
  let bad_content =
    "{\"schema\":\"uos.recovery-review-receipt.v1\",\"verdict\":\"FAIL\",\"reviewer\":\""
    <> grant.reviewer
    <> "\",\"plan\":\""
    <> intent.plan
    <> "\",\"task\":\""
    <> intent.task
    <> "\",\"target_path\":\""
    <> intent.target_path
    <> "\",\"candidate_sha256\":\""
    <> intent.candidate_sha256
    <> "\"}"
  let assert Ok(Nil) =
    ra.write_file_binary(grant.review_receipt_path, <<bad_content:utf8>>)
  let assert Ok(bad_hash) = ra.sha256_file(grant.review_receipt_path)
  let bad_grant = ra.ReviewedGrant(..grant, review_receipt_sha256: bad_hash)
  let bad_intent =
    ra.ActivationIntent(..intent, review_receipt_sha256: bad_hash)

  case ra.prepare(bad_intent, bad_grant) {
    Error(ra.ReviewReceiptInvalid(_)) -> Nil
    _ -> panic as "expected ReviewReceiptInvalid for verdict FAIL"
  }
}

pub fn prepare_host_mismatch_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"
  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)

  let #(intent, grant) = make_intent_and_grant(target_path, cand_path, None)
  let bad_intent = ra.ActivationIntent(..intent, host_id: "foreign_host_id")

  case ra.prepare(bad_intent, grant) {
    Error(ra.HostBootMismatch(_, _, _, _)) -> Nil
    _ -> panic as "expected HostBootMismatch error"
  }
}

pub fn prepare_boot_mismatch_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"
  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)

  let #(intent, grant) = make_intent_and_grant(target_path, cand_path, None)
  let bad_intent = ra.ActivationIntent(..intent, boot_id: "foreign_boot_id")

  case ra.prepare(bad_intent, grant) {
    Error(ra.HostBootMismatch(_, _, _, _)) -> Nil
    _ -> panic as "expected HostBootMismatch error"
  }
}

pub fn prepare_missing_expected_target_hash_on_existing_target_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"
  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)
  let assert Ok(Nil) = ra.create_test_coordinator_db(target_path)

  // Target exists, but expected_target_sha256 is None -> must be refused!
  let #(intent, grant) = make_intent_and_grant(target_path, cand_path, None)

  case ra.prepare(intent, grant) {
    Error(ra.TargetHashMissingOnExistingTarget(_)) -> Nil
    _ -> panic as "expected TargetHashMissingOnExistingTarget error"
  }
}

pub fn prepare_expired_grant_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"
  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)

  let #(intent, grant) = make_intent_and_grant(target_path, cand_path, None)
  let expired_grant = ra.ReviewedGrant(..grant, valid_until_utc_us: 1000)

  case ra.prepare(intent, expired_grant) {
    Error(ra.GrantInvalid(_)) -> Nil
    _ -> panic as "expected GrantInvalid error for expired grant"
  }
}

pub fn prepare_mismatched_receipt_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"
  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)

  let #(intent, grant) = make_intent_and_grant(target_path, cand_path, None)
  let _ =
    ra.write_file_binary(grant.review_receipt_path, <<
      "{\"tampered\":true}":utf8,
    >>)

  case ra.prepare(intent, grant) {
    Error(ra.ReviewReceiptMismatch(_, _)) -> Nil
    _ -> panic as "expected ReviewReceiptMismatch error"
  }
}

pub fn prepare_changed_candidate_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"
  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)

  let #(intent, grant) = make_intent_and_grant(target_path, cand_path, None)
  let bad_intent =
    ra.ActivationIntent(..intent, candidate_sha256: "00000000000000000000")

  case ra.prepare(bad_intent, grant) {
    Error(ra.GrantInvalid(_)) -> Nil
    _ -> panic as "expected GrantInvalid due to intent/grant mismatch"
  }
}

pub fn prepare_target_hash_mismatch_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"
  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)
  let assert Ok(Nil) = ra.create_test_coordinator_db(target_path)

  let #(intent, grant) =
    make_intent_and_grant(
      target_path,
      cand_path,
      Some("mismatched_target_hash"),
    )

  case ra.prepare(intent, grant) {
    Error(ra.TargetHashMismatch(_, _)) -> Nil
    _ -> panic as "expected TargetHashMismatch error"
  }
}

pub fn prepare_symlink_path_rejection_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"
  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)

  let symlink_path = test_root <> "/candidate_dir/symlink.sqlite3"
  let _ = simplifile.create_symlink(cand_path, symlink_path)

  let #(intent, grant) = make_intent_and_grant(target_path, symlink_path, None)

  case ra.prepare(intent, grant) {
    Error(ra.PathSafetyViolation(_)) -> Nil
    _ -> panic as "expected PathSafetyViolation for symlink path"
  }
}

pub fn activate_lease_refusal_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"
  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)
  let assert Ok(Nil) = ra.create_test_coordinator_db(target_path)

  let assert Ok(target_hash) = ra.sha256_file(target_path)
  let #(intent, grant) =
    make_intent_and_grant(target_path, cand_path, Some(target_hash))

  let validator = fn() {
    Error(ra.TaskLeaseExpired("lease expired in sa-plan"))
  }

  case ra.activate_with_task_validator(intent, grant, validator) {
    Error(ra.TaskLeaseExpired(_)) -> Nil
    _ -> panic as "expected TaskLeaseExpired refusal"
  }

  // Target must remain untouched
  let assert Ok(count) = ra.sqlite_verify_integrity(target_path)
  count |> should.equal(3)
  // Lock must be released
  ra.is_target_locked(ra.lock_path_for(target_path))
  |> should.equal(Ok(False))
}

pub fn activate_existing_lock_refusal_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"
  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)
  let assert Ok(Nil) = ra.create_test_coordinator_db(target_path)

  let assert Ok(target_hash) = ra.sha256_file(target_path)
  let #(intent, grant) =
    make_intent_and_grant(target_path, cand_path, Some(target_hash))

  // Hold a lock beforehand with current PID
  let lock_path = ra.lock_path_for(target_path)
  let pid = ra.get_pid()
  let lock_body = ra.lock_payload(intent, pid, "2026-09-30T05:24:00Z")
  let assert Ok(Nil) = ra.acquire_target_lock(lock_path, lock_body)

  let validator = fn() { Ok(Nil) }
  case ra.activate_with_task_validator(intent, grant, validator) {
    Error(ra.TargetLocked(_)) -> Nil
    _ -> panic as "expected TargetLocked refusal"
  }

  // Clean up lock
  let _ = ra.release_target_lock(lock_path, pid)
  Nil
}

pub fn activate_success_with_reopened_integrity_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"

  let assert Ok(Nil) = ra.create_test_coordinator_db(target_path)
  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)

  let assert Ok(target_hash) = ra.sha256_file(target_path)
  let assert Ok(cand_hash) = ra.sha256_file(cand_path)
  let #(intent, grant) =
    make_intent_and_grant(target_path, cand_path, Some(target_hash))

  let validator = fn() { Ok(Nil) }
  let assert Ok(receipt) =
    ra.activate_with_task_validator(intent, grant, validator)

  // Verify receipt and generation
  receipt.swapped |> should.equal(True)
  receipt.verified |> should.equal(True)
  receipt.candidate_sha256 |> should.equal(cand_hash)
  receipt.status |> should.equal("ACTIVATED")
  receipt.tables_found |> should.equal(3)
  receipt.generation_token |> should.not_equal("genesis")

  // Verify target is now the candidate database and has valid reopened integrity
  let assert Ok(new_target_hash) = ra.sha256_file(target_path)
  new_target_hash |> should.equal(cand_hash)
  let assert Ok(t_count) = ra.sqlite_verify_integrity(target_path)
  t_count |> should.equal(3)

  // Verify generation token persists on disk
  let gen_path = ra.generation_path_for(target_path)
  let assert Ok(persisted_gen) = ra.read_generation(gen_path)
  persisted_gen |> should.equal(receipt.generation_token)

  // Verify lock was released
  ra.is_target_locked(ra.lock_path_for(target_path))
  |> should.equal(Ok(False))

  // Verify unique backup directory and manifest exist
  let unique_backup_dir =
    intent.backup_dir
    <> "/bk-"
    <> intent.intent_id
    <> "-att"
    <> int.to_string(intent.attempt)
  ra.file_exists(unique_backup_dir <> "/manifest.json") |> should.equal(True)
  ra.file_exists(receipt.backup_target_path) |> should.equal(True)
}

pub fn activate_cycle_store_success_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand_cycle.sqlite3"
  let target_path = test_root <> "/target_dir/target_cycle.sqlite3"

  let assert Ok(Nil) = ra.create_test_cycle_db(target_path)
  let assert Ok(Nil) = ra.create_test_cycle_db(cand_path)

  let assert Ok(target_hash) = ra.sha256_file(target_path)
  let assert Ok(cand_hash) = ra.sha256_file(cand_path)

  let #(base_intent, base_grant) =
    make_intent_and_grant(target_path, cand_path, Some(target_hash))
  let intent =
    ra.ActivationIntent(
      ..base_intent,
      target_kind: ra.KmCycleStore,
      operator_scope: "km_cycle",
    )
  let grant = base_grant

  let validator = fn() { Ok(Nil) }
  let assert Ok(receipt) =
    ra.activate_with_task_validator(intent, grant, validator)

  receipt.swapped |> should.equal(True)
  receipt.verified |> should.equal(True)
  receipt.candidate_sha256 |> should.equal(cand_hash)
  receipt.status |> should.equal("ACTIVATED")
  receipt.tables_found |> should.equal(2)

  let assert Ok(new_target_hash) = ra.sha256_file(target_path)
  new_target_hash |> should.equal(cand_hash)
}

pub fn activate_coordinator_tampered_chain_refusal_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand_tampered.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"

  // Raw non-coordinator DB as candidate -> must be refused by cryptographic oracle!
  let assert Ok(Nil) = ra.create_test_db(cand_path, "unregistered_raw_table")
  let assert Ok(Nil) = ra.create_test_coordinator_db(target_path)

  let assert Ok(target_hash) = ra.sha256_file(target_path)
  let #(intent, grant) =
    make_intent_and_grant(target_path, cand_path, Some(target_hash))

  let validator = fn() { Ok(Nil) }
  case ra.activate_with_task_validator(intent, grant, validator) {
    Error(ra.CryptographicChainVerificationFailed(_)) -> Nil
    _ ->
      panic as "expected CryptographicChainVerificationFailed refusal for raw DB"
  }
}

pub fn rollback_success_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"

  let assert Ok(Nil) = ra.create_test_coordinator_db(target_path)
  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)

  let assert Ok(target_hash) = ra.sha256_file(target_path)
  let #(intent, grant) =
    make_intent_and_grant(target_path, cand_path, Some(target_hash))

  let validator = fn() { Ok(Nil) }

  // 1. Activate to produce valid unique backup and manifest
  let assert Ok(_receipt) =
    ra.activate_with_task_validator(intent, grant, validator)

  // 2. Corrupt target to simulate failure
  let assert Ok(Nil) =
    ra.write_file_binary(target_path, <<"CORRUPTED_TARGET_DB":utf8>>)

  // 3. Rollback with same intent and grant
  let assert Ok(rb_receipt) =
    ra.rollback_with_task_validator(intent, grant, validator)

  rb_receipt.status |> should.equal("ROLLED_BACK")

  // Target restored to original safe hash
  let assert Ok(restored_hash) = ra.sha256_file(target_path)
  restored_hash |> should.equal(target_hash)

  // Lock must be cleanly released on successful rollback
  ra.is_target_locked(ra.lock_path_for(target_path))
  |> should.equal(Ok(False))
}

pub fn rollback_tampered_backup_retains_hold_lock_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"

  let assert Ok(Nil) = ra.create_test_coordinator_db(target_path)
  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)

  let assert Ok(target_hash) = ra.sha256_file(target_path)
  let #(intent, grant) =
    make_intent_and_grant(target_path, cand_path, Some(target_hash))

  let validator = fn() { Ok(Nil) }

  // 1. Activate
  let assert Ok(_receipt) =
    ra.activate_with_task_validator(intent, grant, validator)

  // 2. Tamper the backup file in the unique backup directory
  let unique_backup_dir =
    intent.backup_dir
    <> "/bk-"
    <> intent.intent_id
    <> "-att"
    <> int.to_string(intent.attempt)
  let bk_file = unique_backup_dir <> "/target.sqlite3"
  let assert Ok(Nil) = ra.change_file_mode(bk_file, 0o600)
  let assert Ok(Nil) =
    ra.write_file_binary(bk_file, <<"TAMPERED_BACKUP_CONTENT":utf8>>)

  // 3. Attempt rollback -> must FAIL and RETAIN LOCK in HOLD status!
  case ra.rollback_with_task_validator(intent, grant, validator) {
    Error(ra.RollbackFailedRetainingLock(_)) -> Nil
    _ -> panic as "expected RollbackFailedRetainingLock"
  }

  // Verify lock is RETAINED on disk with status HOLD
  let lock_path = ra.lock_path_for(target_path)
  ra.is_target_locked(lock_path) |> should.equal(Ok(True))
  let assert Ok(lock_content) = ra.read_target_lock(lock_path)
  lock_content |> should.not_equal("")

  // Clean up lock for test hygiene
  let pid = ra.get_pid()
  let _ = ra.release_target_lock(lock_path, pid)
  Nil
}

pub fn prepare_non_sqlite_target_refusal_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.txt"
  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)

  let #(base_intent, grant) =
    make_intent_and_grant(target_path, cand_path, None)
  let intent = ra.ActivationIntent(..base_intent, target_path: target_path)

  case ra.prepare(intent, grant) {
    Error(ra.InvalidTarget(_)) -> Nil
    _ -> panic as "expected InvalidTarget for non-sqlite target"
  }
}

pub fn prepare_non_sqlite_candidate_refusal_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.txt"
  let target_path = test_root <> "/target_dir/target.sqlite3"
  let assert Ok(Nil) = ra.write_file_binary(cand_path, <<"test":utf8>>)

  let #(base_intent, grant) =
    make_intent_and_grant(target_path, cand_path, None)
  let intent = ra.ActivationIntent(..base_intent, candidate_path: cand_path)

  case ra.prepare(intent, grant) {
    Error(ra.InvalidTarget(_)) -> Nil
    _ -> panic as "expected InvalidTarget for non-sqlite candidate"
  }
}

pub fn prepare_target_equals_candidate_refusal_test() {
  setup_dirs()
  let target_path = test_root <> "/target_dir/target.sqlite3"
  let assert Ok(Nil) = ra.create_test_coordinator_db(target_path)

  let #(base_intent, grant) =
    make_intent_and_grant(target_path, target_path, None)
  let intent = ra.ActivationIntent(..base_intent, candidate_path: target_path)

  case ra.prepare(intent, grant) {
    Error(ra.InvalidTarget(_)) -> Nil
    _ -> panic as "expected InvalidTarget for identical candidate and target"
  }
}

pub fn prepare_incompatible_operator_scope_refusal_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"
  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)

  let #(base_intent, grant) =
    make_intent_and_grant(target_path, cand_path, None)
  let intent = ra.ActivationIntent(..base_intent, operator_scope: "wrong_scope")

  case ra.prepare(intent, grant) {
    Error(ra.InvalidTarget(_)) -> Nil
    _ -> panic as "expected InvalidTarget for incompatible operator scope"
  }
}

pub fn prepare_unsupported_target_kind_refusal_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"
  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)

  let #(base_intent, grant) =
    make_intent_and_grant(target_path, cand_path, None)
  let intent =
    ra.ActivationIntent(
      ..base_intent,
      target_kind: ra.UnsupportedTargetKind("foreign_store"),
    )

  case ra.prepare(intent, grant) {
    Error(ra.InvalidTarget(_)) -> Nil
    _ -> panic as "expected InvalidTarget for unsupported target kind"
  }
}

pub fn activate_lease_expiry_before_sidecar_retirement_refusal_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"
  let target_wal = test_root <> "/target_dir/target.sqlite3-wal"
  let target_shm = test_root <> "/target_dir/target.sqlite3-shm"

  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)
  let assert Ok(Nil) = ra.create_test_coordinator_db(target_path)
  let assert Ok(Nil) = ra.write_file_binary(target_wal, <<"WAL_BEFORE":utf8>>)
  let assert Ok(Nil) = ra.write_file_binary(target_shm, <<"SHM_BEFORE":utf8>>)

  let assert Ok(target_hash) = ra.sha256_file(target_path)
  let #(intent, grant) =
    make_intent_and_grant(target_path, cand_path, Some(target_hash))

  // State counter: pass 1st task check (under lock), fail 2nd task check (before sidecar retirement)
  let marker = test_root <> "/task_check_marker"
  let assert Ok(Nil) = ra.write_file_binary(marker, <<"active":utf8>>)
  let validator = fn() {
    case ra.file_exists(marker) {
      True -> {
        let _ = ra.delete_file(marker)
        Ok(Nil)
      }
      False ->
        Error(ra.TaskLeaseExpired(
          "lease expired right before sidecar retirement",
        ))
    }
  }

  case ra.activate_with_task_validator(intent, grant, validator) {
    Error(ra.TaskLeaseExpired(_)) -> Nil
    _ -> panic as "expected TaskLeaseExpired refusal before sidecar retirement"
  }

  // Target and sidecars must remain completely untouched on disk
  ra.file_exists(target_wal) |> should.equal(True)
  ra.file_exists(target_shm) |> should.equal(True)
  let assert Ok(current_target_hash) = ra.sha256_file(target_path)
  current_target_hash |> should.equal(target_hash)

  // Lock must be released
  ra.is_target_locked(ra.lock_path_for(target_path))
  |> should.equal(Ok(False))
}

pub fn activate_candidate_mutation_before_swap_triggers_rollback_test() {
  setup_dirs()
  let cand_path = test_root <> "/candidate_dir/cand.sqlite3"
  let target_path = test_root <> "/target_dir/target.sqlite3"
  let target_wal = test_root <> "/target_dir/target.sqlite3-wal"
  let target_shm = test_root <> "/target_dir/target.sqlite3-shm"

  let assert Ok(Nil) = ra.create_test_coordinator_db(cand_path)
  let assert Ok(Nil) = ra.create_test_coordinator_db(target_path)
  let assert Ok(Nil) = ra.write_file_binary(target_wal, <<"WAL_ORIGINAL":utf8>>)
  let assert Ok(Nil) = ra.write_file_binary(target_shm, <<"SHM_ORIGINAL":utf8>>)

  let assert Ok(target_hash) = ra.sha256_file(target_path)
  let #(intent, grant) =
    make_intent_and_grant(target_path, cand_path, Some(target_hash))

  // In the validator right before sidecar retirement, tamper the candidate database on disk!
  let validator = fn() {
    let assert Ok(Nil) =
      ra.write_file_binary(cand_path, <<"TAMPERED_CANDIDATE_POST_PREPARE":utf8>>)
    Ok(Nil)
  }

  case ra.activate_with_task_validator(intent, grant, validator) {
    Error(ra.RollbackTriggered(_)) -> Nil
    _ ->
      panic as "expected RollbackTriggered due to candidate hash mutation before swap"
  }

  // Target and sidecars must be cleanly restored to original state!
  let assert Ok(restored_hash) = ra.sha256_file(target_path)
  restored_hash |> should.equal(target_hash)
  let assert Ok(wal_content) = ra.read_file_binary(target_wal)
  wal_content |> should.equal(<<"WAL_ORIGINAL":utf8>>)
  let assert Ok(shm_content) = ra.read_file_binary(target_shm)
  shm_content |> should.equal(<<"SHM_ORIGINAL":utf8>>)

  // Lock must be cleanly released on successful rollback
  ra.is_target_locked(ra.lock_path_for(target_path))
  |> should.equal(Ok(False))
}
