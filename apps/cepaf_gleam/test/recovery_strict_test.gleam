import cepaf_gleam/harness/files
import cepaf_gleam/harness/recovery_activation as io
import cepaf_gleam/harness/recovery_strict as strict
import gleam/bit_array
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import gleeunit/should
import simplifile

pub fn only_the_matching_canonical_target_is_accepted_test() {
  let coordinator =
    "/home/an/NAS-setup/uos/var/coordination/tri-agent/coordinator.sqlite3"
  let cycles = "/home/an/NAS-setup/uos/var/km/provenance-cycles.sqlite3"
  strict.canonical_target(io.CoordinatorStore, coordinator) |> should.be_true
  strict.canonical_target(io.KmCycleStore, cycles) |> should.be_false
  ["/tmp/arbitrary.sqlite3", "/tmp/target.db", coordinator <> "/..", cycles]
  |> list.each(fn(path) {
    strict.canonical_target(io.CoordinatorStore, path) |> should.be_false
  })
  strict.canonical_target(io.KmCycleStore, coordinator) |> should.be_false
}

pub fn authority_must_cover_the_full_bounded_recovery_window_test() {
  [0, 1, 119_999_999, 120_000_000]
  |> list.each(fn(left) {
    strict.authority_window(1000, 1000 + left) |> should.be_false
  })
  strict.authority_window(1000, 120_001_001) |> should.be_true
}

pub fn no_private_review_means_no_activation_test() {
  strict.prepare("does-not-exist.json", "does-not-exist-review.json")
  |> result.is_error
  |> should.be_true
  strict.activate("does-not-exist.json", "does-not-exist-review.json")
  |> result.is_error
  |> should.be_true
}

@external(erlang, "session_sync_ffi", "unique_id")
fn unique_id() -> String

@external(erlang, "recovery_activation_ffi", "staged_swap_database")
fn swap(
  candidate: String,
  target: String,
  expected: String,
) -> Result(Nil, String)

fn fixture() -> String {
  let root = "/tmp/uos-strict-rehearsal-" <> unique_id()
  let assert Ok(_) = simplifile.create_directory_all(root)
  root
}

fn put(path: String, body: String) -> Result(Nil, String) {
  io.write_file_binary(path, bit_array.from_string(body))
}

pub fn pre_mutation_refusal_never_rolls_back_or_overwrites_test() {
  let root = fixture()
  let target = root <> "/target.sqlite3"
  let assert Ok(_) = put(target, "newly observed foreign bytes")
  strict.transition(
    fn() { Error("target_preimage_changed") },
    fn() {
      let _ = put(target, "incorrect mutation")
      Error("must not execute")
    },
    fn(_) { put(target, "incorrect rollback") },
    fn(_) { put(root <> "/rollback", "incorrect receipt") },
    fn() { put(root <> "/unlocked", "incorrect unlock") },
    fn(reason) { put(root <> "/hold", reason) },
  )
  |> result.is_error
  |> should.be_true
  simplifile.read(target) |> should.equal(Ok("newly observed foreign bytes"))
  simplifile.is_file(root <> "/rollback") |> should.equal(Ok(False))
  simplifile.is_file(root <> "/unlocked") |> should.equal(Ok(False))
  simplifile.is_file(root <> "/hold") |> should.equal(Ok(True))
}

pub fn partial_sidecar_retirement_restores_all_bytes_and_holds_test() {
  let root = fixture()
  let target = root <> "/target.sqlite3"
  let assert Ok(_) = io.create_test_db(target, "original")
  let assert Ok(original) = io.sha256_file(target)
  let assert Ok(_) = put(target <> "-wal", "original WAL")
  let assert Ok(_) = put(target <> "-shm", "original SHM")
  strict.transition(
    fn() {
      use saved <- result.try(io.preserve_target_state(
        target,
        root,
        "partial",
        1,
        "generation",
        100,
        "fixture",
      ))
      Ok(saved.0)
    },
    fn() {
      use _ <- result.try(io.retire_target_sidecars(target))
      Error("injected failure after sidecar retirement")
    },
    fn(backup) { io.rollback_from_manifest(target, backup) },
    fn(detail) { put(root <> "/rollback", detail) },
    fn() { put(root <> "/unlocked", "incorrect unlock") },
    fn(reason) { put(root <> "/hold", reason) },
  )
  |> result.is_error
  |> should.be_true
  io.sha256_file(target) |> should.equal(Ok(original))
  simplifile.read(target <> "-wal") |> should.equal(Ok("original WAL"))
  simplifile.read(target <> "-shm") |> should.equal(Ok("original SHM"))
  simplifile.is_file(root <> "/hold") |> should.equal(Ok(True))
  simplifile.is_file(root <> "/unlocked") |> should.equal(Ok(False))
}

pub fn successful_copy_has_durable_verification_before_unlock_test() {
  let root = fixture()
  let target = root <> "/target.sqlite3"
  let candidate = root <> "/candidate.sqlite3"
  let assert Ok(_) = io.create_test_db(target, "original")
  let assert Ok(_) = io.create_test_db(candidate, "replacement")
  let assert Ok(hash) = io.sha256_file(candidate)
  let lock = target <> ".recovery-lock"
  let assert Ok(_) =
    io.acquire_target_lock(
      lock,
      "{\"pid\":" <> int.to_string(io.get_pid()) <> "}",
    )
  strict.transition(
    fn() {
      use _ <- result.try(io.advance_generation(
        target <> ".recovery-generation",
        "new",
      ))
      use saved <- result.try(io.preserve_target_state(
        target,
        root,
        "success",
        1,
        "new",
        100,
        "fixture",
      ))
      Ok(saved.0)
    },
    fn() {
      use _ <- result.try(io.retire_target_sidecars(target))
      use _ <- result.try(swap(candidate, target, hash))
      use _ <- result.try(strict.post_swap_valid(target, hash))
      use _ <- result.try(files.create(root, "VERIFIED", hash))
      Ok(hash)
    },
    fn(backup) { io.rollback_from_manifest(target, backup) },
    fn(detail) { put(root <> "/rollback", detail) },
    fn() {
      use verified <- result.try(files.read(root, "VERIFIED"))
      case verified == hash {
        True -> io.release_target_lock(lock, io.get_pid())
        False -> Error("verification must be durable before unlock")
      }
    },
    fn(reason) { put(root <> "/hold", reason) },
  )
  |> should.equal(Ok(hash))
  io.sha256_file(target) |> should.equal(Ok(hash))
  simplifile.is_file(lock) |> should.equal(Ok(False))
  simplifile.is_file(root <> "/VERIFIED") |> should.equal(Ok(True))
  simplifile.is_file(root <> "/hold") |> should.equal(Ok(False))
}

fn finite_intent() -> io.ActivationIntent {
  io.ActivationIntent(
    intent_id: "restore-coordinator-test",
    plan: "uos/coordinator-incident/20261024-0544",
    task: "RESTORE",
    worker: "codex-analysis-20261024",
    attempt: 1,
    host_id: "test",
    boot_id: "test",
    expiry_utc_us: 1,
    target_path: "/home/an/NAS-setup/uos/var/coordination/tri-agent/coordinator.sqlite3",
    target_kind: io.CoordinatorStore,
    candidate_path: strict.private_root <> "/coordinator-fresh-20261024.sqlite3",
    candidate_sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    expected_target_sha256: None,
    review_receipt_sha256: "bound-by-independent-full-grant-review",
    operator_scope: "coordinator",
    backup_dir: strict.private_root,
  )
}

pub fn finite_binding_rejects_wrong_and_historical_grants_test() {
  let good = finite_intent()
  strict.finite(good) |> should.equal(Ok(Nil))
  [
    io.ActivationIntent(..good, plan: "uos/full-restoration/20260930-0515"),
    io.ActivationIntent(..good, task: "FIX"),
    io.ActivationIntent(..good, worker: "different-worker"),
    io.ActivationIntent(..good, attempt: 0),
    io.ActivationIntent(..good, operator_scope: "km_cycle"),
    io.ActivationIntent(..good, review_receipt_sha256: "unreviewed"),
    io.ActivationIntent(..good, candidate_path: "/tmp/other.sqlite3"),
    io.ActivationIntent(..good, backup_dir: "/tmp"),
    io.ActivationIntent(..good, target_kind: io.KmCycleStore),
  ]
  |> list.each(fn(intent) {
    strict.finite(intent) |> result.is_error |> should.be_true
  })
}

pub fn even_empty_candidate_sidecars_are_refused_without_removal_test() {
  ["-wal", "-shm"]
  |> list.each(fn(suffix) {
    let root = fixture()
    let path = root <> "/candidate.sqlite3"
    strict.sidecars_absent(path, "sidecar") |> should.equal(Ok(Nil))
    let assert Ok(_) = put(path <> suffix, "")
    strict.sidecars_absent(path, "sidecar") |> result.is_error |> should.be_true
    simplifile.is_file(path <> suffix) |> should.equal(Ok(True))
  })
}

pub fn post_swap_verification_checks_hash_and_sidecars_under_lock_test() {
  let root = fixture()
  let path = root <> "/target.sqlite3"
  let assert Ok(_) = io.create_test_db(path, "sealed")
  let assert Ok(hash) = io.sha256_file(path)
  let lock = io.lock_path_for(path)
  let assert Ok(_) =
    io.acquire_target_lock(
      lock,
      json.to_string(json.object([#("pid", json.int(io.get_pid()))])),
    )
  strict.post_swap_valid(path, hash) |> should.equal(Ok(hash))
  strict.post_swap_valid(path, "wrong") |> result.is_error |> should.be_true
  let assert Ok(_) = put(path <> "-shm", "")
  strict.post_swap_valid(path, hash) |> result.is_error |> should.be_true
  simplifile.is_file(path <> "-shm") |> should.equal(Ok(True))
  let assert Ok(_) = io.release_target_lock(lock, io.get_pid())
}
