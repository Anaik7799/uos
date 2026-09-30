//// Reviewed, finite one-time restoration entrypoint. The AGY implementation is
//// preserved as low-level development evidence; this module owns effect policy.
//// Failure after lock acquisition retains HOLD. Originals and terminal receipts
//// are durable before admission of a recovered target. No history is re-signed.
import cepaf_gleam/harness/admission as a
import cepaf_gleam/harness/clock
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import cepaf_gleam/harness/recovery_activation as io
import cepaf_gleam/harness/value as v
import gleam/bit_array
import gleam/erlang/atom
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import restoration_runtime_cli as runtime
import simplifile
import uos_swarm/session_store as store

pub const private_root = "/home/an/uos-recovery-candidates/20260930-0421-fractal-rca"
pub const cycle_oracle = dev.root <> "/var/recovery-runtime/20260930/cycle_verify.exe"

@external(erlang, "erlang", "apply")
fn metadata(module: atom.Atom, function: atom.Atom, args: List(atom.Atom)) -> BitArray

@external(erlang, "ecology_capability_ffi", "uos_root")
fn backend_root() -> String

@external(erlang, "recovery_activation_ffi", "staged_swap_database")
fn swap(candidate: String, target: String, expected: String) -> Result(Nil, String)

pub fn control_ids() -> json.Json {
  json.object([
    #("runtime_closure", runtime.control_ids()),
    #("strict", json.string(metadata(atom.create("cepaf_gleam@harness@recovery_strict"), atom.create("module_info"), [atom.create("md5")]) |> bit_array.base16_encode)),
    #("io_types", json.string(metadata(atom.create("cepaf_gleam@harness@recovery_activation"), atom.create("module_info"), [atom.create("md5")]) |> bit_array.base16_encode)),
    #("cli", json.string(metadata(atom.create("recovery_activation_cli"), atom.create("module_info"), [atom.create("md5")]) |> bit_array.base16_encode)),
  ])
}

fn text(doc: v.Value, key: String) -> Result(String, String) {
  case v.get(doc, key) { Ok(v.Text(s)) -> Ok(s) _ -> Error("text:" <> key) }
}

fn number(doc: v.Value, key: String) -> Result(Int, String) {
  case v.get(doc, key) { Ok(v.Integer(n)) -> Ok(n) _ -> Error("integer:" <> key) }
}

fn private_read(name: String) -> Result(String, String) {
  use _ <- result.try(a.require(a.component(name), "private_filename"))
  use _ <- result.try(io.check_private_file(private_root <> "/" <> name))
  files.read(private_root, name)
}

fn parse(body: String) -> Result(v.Value, String) {
  json.parse(body, v.decoder()) |> result.map_error(fn(_) { "invalid_json" })
}

pub fn canonical_target(kind: io.TargetKind, target: String) -> Bool {
  case kind {
    io.CoordinatorStore -> target == dev.root <> "/var/coordination/tri-agent/coordinator.sqlite3"
    io.KmCycleStore -> target == dev.root <> "/var/km/provenance-cycles.sqlite3"
    _ -> False
  }
}

fn finite(intent: io.ActivationIntent) -> Result(Nil, String) {
  use _ <- result.try(a.require(canonical_target(intent.target_kind, intent.target_path), "only_two_canonical_targets"))
  let candidate = case intent.target_kind {
    io.CoordinatorStore -> private_root <> "/coordinator-fresh-20260930.sqlite3"
    io.KmCycleStore -> private_root <> "/cycles-prefix332.sqlite3"
    _ -> ""
  }
  a.require(intent.candidate_path == candidate
    && intent.backup_dir == private_root
    && a.intent_valid(intent.intent_id)
    && intent.plan == "uos/full-restoration/20260930-0515"
    && intent.task == "RESTORE"
    && intent.worker == "codex-full-restoration-20260930"
    && intent.attempt > 0
    && a.digest_valid(intent.candidate_sha256), "finite_restoration_binding")
}

pub fn authority_window(now: Int, expires: Int) -> Bool {
  expires > now + 120_000_000
}

fn fence(intent: io.ActivationIntent, grant: v.Value) -> Result(Nil, String) {
  use observed <- result.try(clock.observe())
  use #(host, boot, _, now) <- result.try(io.ffi_clock())
  use expires <- result.try(number(grant, "expires_us"))
  use _ <- result.try(a.require(
    host == intent.host_id && boot == intent.boot_id
    && observed.sample.observed.domain.boot_id == boot
    && authority_window(now, expires) && authority_window(now, intent.expiry_utc_us),
    "clock_and_grant_window"))
  let binding = dev.Binding("recovery", intent.plan, intent.task, intent.worker, intent.attempt, intent.worker, 1)
  use row <- result.try(dev.read_task(binding))
  a.require(row.state == "executing" && row.worker == Some(intent.worker)
    && row.attempt == intent.attempt && row.blocked == 0
    && case row.lease_until_ns {
      Some(deadline) -> deadline > { now + 120_000_000 } * 1000
      _ -> False
    }, "canonical_task_attempt_dependency_lease")
}

fn bounded_file(path: String) -> Result(Nil, String) {
  use _ <- result.try(io.path_safety_check(path))
  use info <- result.try(simplifile.link_info(path) |> result.map_error(string.inspect))
  a.require(simplifile.file_info_type(info) == simplifile.File
    && info.nlinks == 1 && info.size <= 67_108_864, "bounded_regular_single_link_file")
}

fn hash_or_absent(path: String) -> Result(String, String) {
  case simplifile.link_info(path) {
    Error(simplifile.Enoent) -> Ok("absent")
    Error(e) -> Error(string.inspect(e))
    Ok(_) -> {
      use _ <- result.try(bounded_file(path))
      io.sha256_file(path)
    }
  }
}

fn snapshot_matches(intent: io.ActivationIntent, grant: v.Value) -> Result(Nil, String) {
  use declared <- result.try(v.get(grant, "target_files"))
  list.try_each([#("main", ""), #("wal", "-wal"), #("shm", "-shm")], fn(part) {
    use expected <- result.try(text(declared, part.0))
    use actual <- result.try(hash_or_absent(intent.target_path <> part.1))
    use _ <- result.try(a.require(actual == expected, "target_preimage_changed:" <> part.0))
    case part.0 {
      "main" -> a.require(intent.expected_target_sha256 == Some(actual) && a.digest_valid(actual), "existing_target_hash_required")
      _ -> Ok(Nil)
    }
  })
}

fn candidate_valid(intent: io.ActivationIntent) -> Result(Nil, String) {
  use _ <- result.try(bounded_file(intent.candidate_path))
  use hash <- result.try(io.sha256_file(intent.candidate_path))
  use _ <- result.try(a.require(hash == intent.candidate_sha256, "candidate_changed"))
  use _ <- result.try(case simplifile.link_info(intent.candidate_path <> "-wal") {
    Error(simplifile.Enoent) -> Ok(Nil)
    Ok(info) -> a.require(simplifile.file_info_type(info) == simplifile.File && info.size == 0, "candidate_wal_not_empty")
    _ -> Error("candidate_wal_unknown")
  })
  use _ <- result.try(io.sqlite_verify_integrity(intent.candidate_path))
  use _ <- result.try(case intent.target_kind {
    io.CoordinatorStore -> {
      use report <- result.try(store.verify_file(intent.candidate_path) |> result.map_error(store.error_to_string))
      a.require(report.ok && report.checked == 1, "fresh_coordinator_epoch_required")
    }
    io.KmCycleStore -> {
      use output <- result.try(dev.bounded(cycle_oracle, [intent.candidate_path], 10_000))
      use report <- result.try(parse(output))
      a.require(v.get(report, "ok") == Ok(v.Boolean(True))
        && v.get(report, "rows") == Ok(v.Integer(332))
        && v.get(report, "holds") == Ok(v.Integer(24))
        && v.get(report, "releases") == Ok(v.Integer(0)), "cycle_prefix_and_holds_required")
    }
    _ -> Error("unsupported_target")
  })
  use after <- result.try(io.sha256_file(intent.candidate_path))
  a.require(after == hash, "candidate_changed_during_verification")
}

fn load(grant_name: String, review_name: String) -> Result(#(io.ActivationIntent, v.Value), String) {
  use _ <- result.try(a.require(backend_root() == dev.root, "canonical_backend_required"))
  use raw <- result.try(private_read(grant_name))
  use grant <- result.try(parse(raw))
  use review_raw <- result.try(private_read(review_name))
  use review <- result.try(parse(review_raw))
  use intent_value <- result.try(v.get(grant, "intent"))
  use intent <- result.try(json.parse(json.to_string(v.encode(intent_value)), io.intent_decoder()) |> result.map_error(fn(_) { "intent_schema" }))
  use reviewer <- result.try(text(review, "reviewer"))
  use _ <- result.try(a.require(
    v.get(grant, "schema") == Ok(v.Text("uos.recovery-strict-grant.v1"))
    && v.get(grant, "operation") == Ok(v.Text("activate"))
    && v.get(review, "schema") == Ok(v.Text("uos.recovery-strict-review.v1"))
    && v.get(review, "verdict") == Ok(v.Text("PASS"))
    && v.get(review, "grant_sha256") == Ok(v.Text(files.digest(raw)))
    && reviewer != intent.worker && string.length(reviewer) > 0, "independent_complete_intent_review"))
  use recorded <- result.try(v.get(grant, "control_ids"))
  use _ <- result.try(a.require(runtime.controls_match(recorded, control_ids()), "loaded_control_closure"))
  use deps <- result.try(v.get(grant, "dependencies"))
  use _ <- result.try(list.try_each([
    cycle_oracle, dev.root <> "/tools/ecology_process.ml",
    dev.root <> "/toolchains/opam-ocaml/bin/ocaml", "/usr/bin/fuser",
  ], fn(path) {
    use actual <- result.try(io.sha256_file(path))
    a.require(v.get(deps, path) == Ok(v.Text(actual)), "native_dependency_changed:" <> path)
  }))
  use _ <- result.try(finite(intent))
  use _ <- result.try(fence(intent, grant))
  Ok(#(intent, grant))
}

pub fn prepare(grant_name: String, review_name: String) -> Result(String, String) {
  use #(intent, grant) <- result.try(load(grant_name, review_name))
  use _ <- result.try(candidate_valid(intent))
  use _ <- result.try(snapshot_matches(intent, grant))
  use _ <- result.try(io.check_quiescence(intent.target_path))
  Ok("PREPARED")
}

fn phase(intent: io.ActivationIntent, name: String, detail: String) -> Result(Nil, String) {
  files.create(private_root, intent.intent_id <> "." <> name <> ".json",
    json.to_string(json.object([
      #("schema", json.string("uos.recovery-strict-phase.v1")),
      #("intent", json.string(intent.intent_id)), #("phase", json.string(name)),
      #("plan", json.string(intent.plan)), #("task", json.string(intent.task)),
      #("worker", json.string(intent.worker)), #("target", json.string(intent.target_path)),
      #("candidate_sha256", json.string(intent.candidate_sha256)),
      #("observed_utc", json.string(io.utc_now_iso8601())),
      #("detail", json.string(detail)),
    ])))
}

/// The operational transition kernel. Injected functions are in-process test/IO
/// interpreters, never request parameters. Production admission remains in load.
/// Refusal before destructive intent cannot invoke compensating writes.
pub fn transition(
  prepare_mutation: fn() -> Result(String, String),
  mutate_and_verify: fn() -> Result(String, String),
  rollback: fn(String) -> Result(Nil, String),
  record_rollback: fn(String) -> Result(Nil, String),
  unlock: fn() -> Result(Nil, String),
  hold: fn(String) -> Result(Nil, String),
) -> Result(String, String) {
  let outcome = {
    use backup <- result.try(prepare_mutation())
    case mutate_and_verify() {
      Ok(hash) -> {
        use _ <- result.try(unlock())
        Ok(hash)
      }
      Error(reason) -> {
        let restored = rollback(backup)
        let detail = reason <> "; preserved rollback=" <> string.inspect(restored)
        let recorded = record_rollback(detail)
        Error(detail <> "; receipt=" <> string.inspect(recorded))
      }
    }
  }
  case outcome {
    Ok(hash) -> Ok(hash)
    Error(reason) -> {
      let held = hold(reason)
      Error("HOLD:" <> reason <> "; lock=" <> string.inspect(held))
    }
  }
}

pub fn activate(grant_name: String, review_name: String) -> Result(String, String) {
  use _ <- result.try(prepare(grant_name, review_name))
  use #(intent, grant) <- result.try(load(grant_name, review_name))
  let lock = io.lock_path_for(intent.target_path)
  let pid = io.get_pid()
  use _ <- result.try(io.acquire_target_lock(lock, io.lock_payload(intent, pid, io.utc_now_iso8601())))
  use hash <- result.try(transition(
    fn() {
      use _ <- result.try(phase(intent, "LOCKED", "exclusive target lock"))
      use _ <- result.try(fence(intent, grant))
      use _ <- result.try(io.advance_generation(io.generation_path_for(intent.target_path), intent.intent_id))
      use _ <- result.try(phase(intent, "GENERATION", intent.intent_id))
      use _ <- result.try(io.check_quiescence(intent.target_path))
      use _ <- result.try(snapshot_matches(intent, grant))
      use _ <- result.try(candidate_valid(intent))
      use #(_, _, _, now) <- result.try(io.ffi_clock())
      use backup <- result.try(io.preserve_target_state(intent.target_path, private_root,
        intent.intent_id, intent.attempt, intent.intent_id, now, io.utc_now_iso8601()))
      use _ <- result.try(phase(intent, "PRESERVED", backup.0))
      use fresh <- result.try(load(grant_name, review_name))
      use _ <- result.try(a.require(a.same_value(grant, fresh.1), "grant_changed"))
      use _ <- result.try(snapshot_matches(intent, grant))
      use _ <- result.try(io.check_quiescence(intent.target_path))
      use _ <- result.try(phase(intent, "SWAP_INTENT", intent.candidate_sha256))
      Ok(backup.0)
    },
    fn() {
      use _ <- result.try(io.retire_target_sidecars(intent.target_path))
      use _ <- result.try(swap(intent.candidate_path, intent.target_path, intent.candidate_sha256))
      use actual <- result.try(io.sha256_file(intent.target_path))
      use _ <- result.try(a.require(actual == intent.candidate_sha256, "post_swap_digest"))
      use _ <- result.try(io.sqlite_verify_integrity(intent.target_path))
      use _ <- result.try(phase(intent, "VERIFIED", actual))
      Ok(actual)
    },
    fn(backup) { io.rollback_from_manifest(intent.target_path, backup) },
    fn(detail) { phase(intent, "ROLLBACK_HOLD", detail) },
    fn() { io.release_target_lock(lock, pid) },
    fn(reason) { io.hold_target_lock(lock, reason, io.utc_now_iso8601()) },
  ))
  Ok(json.to_string(json.object([
    #("schema", json.string("uos.recovery-strict-result.v1")),
    #("status", json.string("ACTIVATED")), #("target", json.string(intent.target_path)),
    #("sha256", json.string(hash)), #("intent", json.string(intent.intent_id)),
  ])))
}
