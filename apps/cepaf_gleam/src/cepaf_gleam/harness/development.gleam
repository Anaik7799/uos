//// Finite local-stdio development harness. The environment asserts a binding;
//// request payload fields never grant identity, role, task or backend authority.
//// Cooperative local filesystem/launcher trust is not credential authentication
//// or a production isolation boundary. The exact initial tuple stays finite.

import cepaf_gleam/harness/clock
import cepaf_gleam/harness/files
import cepaf_gleam/harness/value
import cepaf_gleam/planning/sa_plan_bridge
import gleam/bit_array
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import session_sync_cli
import simplifile
import uos_swarm/clock_guard
import uos_swarm/session_sync

pub const root = "/home/an/NAS-setup/uos"

pub const portfolio = "var/harness/20260909-0412-bootstrap-risk.json"

pub const effects = "var/harness/effects/"

pub const completion_intent = "var/harness/20260909-0412-bootstrap-completion-intent.json"

pub const completion_result = "var/harness/20260909-0412-bootstrap-completion.json"

// Gleam/JJ match tools/lib/uos-toolchain.sh. Env is a separately observed
// entry in the realized repository profile; the resolver has no env arm yet.
// No fallback to mutable home-profile tools is allowed for these adapters.
const pinned_jj = root <> "/toolchains/nix-profile/bin/jj"

const pinned_gleam = root <> "/toolchains/gleam-1.16.0/bin/gleam"

const pinned_env = root <> "/toolchains/nix-profile/bin/env"

const build_path = root
  <> "/toolchains/nix-profile/bin:"
  <> root
  <> "/toolchains/gleam-1.16.0/bin:"
  <> root
  <> "/toolchains/opam-ocaml/bin"

// Explicit one-time bootstrap gaps: resolver/profile currently lack these
// capabilities. Parent owns pinned provisioning; these are not release pins.
const bootstrap_sqlite3 = "/usr/bin/sqlite3"

const bootstrap_bash = "/usr/bin/bash"

pub fn adapter_scope() -> json.Json {
  json.object([
    #("scope", json.string("development_bootstrap_only")),
    #("gleam", json.string(pinned_gleam)),
    #("jj", json.string(pinned_jj)),
    #("env", json.string(pinned_env)),
    #("build_path", json.string(build_path)),
    #(
      "bootstrap_host_exceptions",
      json.array([bootstrap_sqlite3, bootstrap_bash, "/usr/bin/chronyc"], json.string),
    ),
    #("all_adapters_pinned", json.bool(False)),
    #("production_admission", json.bool(False)),
  ])
}

pub type TaskRecord {
  TaskRecord(
    state: String,
    worker: Option(String),
    attempt: Int,
    lease_until_ns: Option(Int),
    blocked: Int,
    result: Option(String),
    completed_at_ns: Option(Int),
  )
}

pub type SourceDigest {
  SourceDigest(path: String, sha256: String)
}

pub type Binding {
  Binding(
    role: String,
    plan: String,
    task: String,
    worker: String,
    attempt: Int,
    session: String,
    epoch: Int,
  )
}

pub type Fence {
  Fence(
    clock: clock.Observation,
    lease_until_ns: Int,
    coordinator_lease_until_us: Int,
  )
}

/// Cooperative observation tied to one finite launcher binding. Opacity stops
/// accidental construction; it is neither a linear permit nor an atomic fence.
pub opaque type TrackingProof {
  TrackingProof(binding: Binding, started: Fence)
}

@external(erlang, "cepaf_gleam_ffi", "get_env")
fn get_env(name: String) -> Result(String, Nil)

@external(erlang, "ecology_capability_ffi", "run_bounded")
fn run_bounded(
  path: String,
  args: List(String),
  timeout_ms: Int,
) -> Result(#(Int, BitArray), String)

@external(erlang, "erlang", "apply")
fn module_metadata(
  module: atom.Atom,
  function: atom.Atom,
  arguments: List(atom.Atom),
) -> BitArray

pub fn control_id() -> String {
  module_metadata(
    atom.create("cepaf_gleam@harness@development"),
    atom.create("module_info"),
    [atom.create("md5")],
  )
  |> bit_array.base16_encode
  |> string.lowercase
}

pub fn valid_identifier(text: String) -> Bool {
  string.byte_size(text) > 0
  && string.byte_size(text) <= 160
  && list.all(string.to_graphemes(text), fn(c) {
    string.contains(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_/.:",
      c,
    )
  })
}

pub fn load_binding() -> Result(Binding, String) {
  use role <- result.try(
    get_env("UOS_HARNESS_ROLE")
    |> result.map_error(fn(_) { "role_binding_missing" }),
  )
  use plan <- result.try(
    get_env("UOS_HARNESS_PLAN")
    |> result.map_error(fn(_) { "plan_binding_missing" }),
  )
  use task <- result.try(
    get_env("UOS_HARNESS_TASK")
    |> result.map_error(fn(_) { "task_binding_missing" }),
  )
  use worker <- result.try(
    get_env("UOS_HARNESS_WORKER")
    |> result.map_error(fn(_) { "worker_binding_missing" }),
  )
  use attempt <- result.try(
    get_env("UOS_HARNESS_ATTEMPT")
    |> result.try(int.parse)
    |> result.map_error(fn(_) { "attempt_binding_missing" }),
  )
  use session <- result.try(
    get_env("UOS_HARNESS_SESSION")
    |> result.map_error(fn(_) { "session_binding_missing" }),
  )
  use epoch <- result.try(
    get_env("UOS_HARNESS_EPOCH")
    |> result.try(int.parse)
    |> result.map_error(fn(_) { "epoch_binding_missing" }),
  )
  // Initial grant is deliberately finite and environment-asserted, not a
  // credential authenticator. New scopes require a separately reviewed grant.
  case
    role == "development"
    && plan == "uos/ecology/20260909-0146"
    && task == "HARNESSBOOT"
    && worker == "codex-01a083d2-harness"
    && attempt == 2
    && session == "01a083d2-baa3-7783-8e45-5357cc9e96d8"
    && epoch == 1
  {
    True -> Ok(Binding(role, plan, task, worker, attempt, session, epoch))
    False -> Error("development_bootstrap_grant_mismatch")
  }
}

/// Retain short diagnostics; a negative start beyond the beginning produces an
/// empty string in the stdlib. This is bounded evidence, never executable text.
pub fn backend_diagnostic(output: String) -> String {
  let start = int.max(0, string.length(output) - 8192)
  let tail = string.slice(output, start, 8192)
  case string.byte_size(tail) <= 16_384 {
    True -> tail
    False -> "diagnostic_exceeded_byte_bound"
  }
}

pub fn bounded(
  path: String,
  args: List(String),
  timeout: Int,
) -> Result(String, String) {
  case run_bounded(path, args, timeout) {
    Ok(#(0, bytes)) ->
      bit_array.to_string(bytes)
      |> result.map_error(fn(_) { "backend_output_invalid_utf8" })
    Ok(#(code, bytes)) -> {
      let diagnostic = case bit_array.to_string(bytes) {
        Ok(output) -> {
          backend_diagnostic(output)
        }
        Error(_) -> "diagnostic_invalid_utf8"
      }
      Error("backend_exit:" <> int.to_string(code) <> "\n" <> diagnostic)
    }
    Error(e) -> Error(e)
  }
}

pub fn evaluate_fence(
  binding: Binding,
  state: String,
  worker: String,
  attempt: Int,
  deadline: Int,
  blocked: Int,
  now_ns: Int,
) -> Result(Nil, String) {
  evaluate_task_window(
    binding,
    state,
    worker,
    attempt,
    deadline,
    blocked,
    now_ns,
    70_000,
  )
}

/// A cooperative observation, never an atomic permission to perform an effect.
pub fn evaluate_task_window(
  binding: Binding,
  state: String,
  worker: String,
  attempt: Int,
  deadline: Int,
  blocked: Int,
  now_ns: Int,
  required_ms: Int,
) -> Result(Nil, String) {
  case
    binding.role == "development"
    && state == "executing"
    && binding.worker == worker
    && binding.attempt == attempt
    && now_ns >= 0
    && required_ms >= 0
    && required_ms <= 70_000
    && deadline > now_ns + required_ms * 1_000_000
    && blocked == 0
  {
    True -> Ok(Nil)
    False -> Error("task_role_attempt_lease_or_dependency_fence")
  }
}

/// Reply relay exits at the deadline, so a late worker cannot send into the
/// MCP owner's mailbox. A timed-out native observation never authorizes effects;
/// killing its BEAM worker is not a claim of forcible native-code cancellation.
pub fn bounded_observation(
  operation: fn() -> Result(String, String),
  timeout_ms: Int,
) -> Result(String, String) {
  case timeout_ms > 0 && timeout_ms <= 3000 {
    False -> Error("observation_timeout_bound")
    True -> {
      let replies = process.new_subject()
      let relay =
        process.spawn_unlinked(fn() {
          let result = process.new_subject()
          let worker =
            process.spawn_unlinked(fn() { process.send(result, operation()) })
          let outcome = case process.receive(result, timeout_ms) {
            Ok(value) -> value
            Error(_) -> {
              process.kill(worker)
              Error("coordinator_observation_timeout_no_effect_authority")
            }
          }
          process.send(replies, outcome)
        })
      case process.receive(replies, timeout_ms + 250) {
        Ok(outcome) -> outcome
        Error(_) -> {
          process.kill(relay)
          Error("observation_relay_timeout_no_effect_authority")
        }
      }
    }
  }
}

pub fn read_task(binding: Binding) -> Result(TaskRecord, String) {
  use _ <- result.try(
    case
      list.all([binding.plan, binding.task, binding.worker], valid_identifier)
    {
      True -> Ok(Nil)
      False -> Error("invalid_bound_identity")
    },
  )
  let sql =
    "SELECT state,worker,attempt,lease_until_ns,result,completed_at_ns,(SELECT count(*) FROM sa_plan_dependency d LEFT JOIN sa_plan_task t ON t.plan_id=d.plan_id AND t.id=d.dependency_id WHERE d.plan_id=p.plan_id AND d.task_id=p.id AND (t.state IS NULL OR t.state!='completed')) AS blocked FROM sa_plan_task p WHERE p.plan_id='"
    <> binding.plan
    <> "' AND p.id='"
    <> binding.task
    <> "';"
  use raw <- result.try(bounded(
    bootstrap_sqlite3,
    ["-readonly", "-json", root <> "/var/sa-plan/uos.sqlite3", sql],
    3000,
  ))
  let decoder = {
    use state <- decode.field("state", decode.string)
    use worker <- decode.field("worker", decode.optional(decode.string))
    use attempt <- decode.field("attempt", decode.int)
    use deadline <- decode.field("lease_until_ns", decode.optional(decode.int))
    use result <- decode.field("result", decode.optional(decode.string))
    use completed <- decode.field(
      "completed_at_ns",
      decode.optional(decode.int),
    )
    use blocked <- decode.field("blocked", decode.int)
    decode.success(TaskRecord(
      state,
      worker,
      attempt,
      deadline,
      blocked,
      result,
      completed,
    ))
  }
  use rows <- result.try(
    json.parse(raw, decode.list(decoder))
    |> result.map_error(fn(_) { "task_observation_invalid" }),
  )
  case rows {
    [row] -> Ok(row)
    _ -> Error("exactly_one_task_required")
  }
}

fn validate_task_record(
  binding: Binding,
  row: TaskRecord,
  now_ns: Int,
  required_ms: Int,
) -> Result(Int, String) {
  case row.worker, row.lease_until_ns {
    Some(worker), Some(deadline) -> {
      use _ <- result.try(evaluate_task_window(
        binding,
        row.state,
        worker,
        row.attempt,
        deadline,
        row.blocked,
        now_ns,
        required_ms,
      ))
      Ok(deadline)
    }
    _, _ -> Error("task_not_executing_with_lease")
  }
}

/// Successor coordination keys include the plan to prevent cross-plan aliasing.
pub fn task_resource(binding: Binding) -> String {
  case binding.plan == "uos/ecology/20260909-0146" && binding.task == "HARNESSBOOT" {
    True -> "task:HARNESSBOOT"
    False -> "task:" <> files.digest(json.to_string(json.object([
      #("plan", json.string(binding.plan)), #("task", json.string(binding.task)),
    ])))
  }
}

fn coordinator_observation(binding: Binding) -> Result(#(String, Int), String) {
  let resource = task_resource(binding)
  use raw <- result.try(bounded_observation(
    fn() {
      session_sync.observe(
        root <> "/var/coordination/tri-agent",
        fn(state, boot, now) {
          use _ <- result.try(session_sync.check(
            state,
            binding.session,
            resource,
            binding.epoch,
            boot,
            now,
          ))
          use lease <- result.try(
            dict.get(state.coordinator.leases, resource)
            |> result.map_error(fn(_) { "coordinator_lease_missing" }),
          )
          Ok(
            json.object([
              #("boot_id", json.string(boot)),
              #("lease_until_us", json.int(lease.expires_us)),
              #(
                "scope",
                json.string("cooperative_observation_not_atomic_authority"),
              ),
            ]),
          )
        },
      )
    },
    2000,
  ))
  let decoder = {
    use boot <- decode.field("boot_id", decode.string)
    use deadline <- decode.field("lease_until_us", decode.int)
    decode.success(#(boot, deadline))
  }
  json.parse(raw, decoder)
  |> result.map_error(fn(_) { "coordinator_observation_invalid" })
}

fn task_fence(binding: Binding) -> Result(Fence, String) {
  use before <- result.try(clock.observe())
  use row <- result.try(read_task(binding))
  // Sample only after the possibly blocking database observation.
  use current <- result.try(clock.observe())
  use _ <- result.try(clock.continuity(before, current))
  use deadline <- result.try(validate_task_record(
    binding,
    row,
    current.sample.observed.utc_us * 1000,
    70_000,
  ))
  Ok(Fence(current, deadline, 0))
}

pub fn fence_for(binding: Binding, required_ms: Int) -> Result(Fence, String) {
  use before <- result.try(clock.observe())
  use #(coordinator_boot, coordinator_deadline) <- result.try(
    coordinator_observation(binding),
  )
  use row <- result.try(read_task(binding))
  // Both task and coordinator observations may have waited. This final sample
  // ages both leases in their own clock domains before any operation starts.
  use current <- result.try(clock.observe())
  use _ <- result.try(clock.continuity(before, current))
  use deadline <- result.try(validate_task_record(
    binding,
    row,
    current.sample.observed.utc_us * 1000,
    required_ms,
  ))
  case
    coordinator_boot == current.sample.observed.domain.boot_id
    && coordinator_deadline
    > current.sample.observed.boot_us + required_ms * 1000
  {
    False -> Error("coordinator_lease_expired_after_observation")
    True -> Ok(Fence(current, deadline, coordinator_deadline))
  }
}

pub fn fence(binding: Binding) -> Result(Fence, String) {
  fence_for(binding, 70_000)
}

/// Reserve five seconds for guardian termination and bookkeeping. The bound
/// uses the fresh dispatch sample, not the time at which a slow check began.
pub fn lease_budget_ms(
  task_deadline_ns: Int,
  coordinator_deadline_us: Int,
  now_ns: Int,
  boot_us: Int,
  requested_ms: Int,
) -> Result(Int, String) {
  let task_left = { task_deadline_ns - now_ns } / 1_000_000 - 5000
  let coordinator_left = { coordinator_deadline_us - boot_us } / 1000 - 5000
  let available = case task_left < coordinator_left {
    True -> task_left
    False -> coordinator_left
  }
  case
    now_ns >= 0
    && boot_us >= 0
    && requested_ms > 0
    && requested_ms <= 60_000
    && available > 0
  {
    False -> Error("dispatch_lease_budget_expired")
    True ->
      Ok(case requested_ms < available {
        True -> requested_ms
        False -> available
      })
  }
}

fn dispatch_budget(proof: Fence, requested_ms: Int) -> Result(Int, String) {
  use current <- result.try(clock.observe())
  use _ <- result.try(clock.continuity(proof.clock, current))
  lease_budget_ms(
    proof.lease_until_ns,
    proof.coordinator_lease_until_us,
    current.sample.observed.utc_us * 1000,
    current.sample.observed.boot_us,
    requested_ms,
  )
}

fn check_launcher_binding(binding: Binding) -> Result(Nil, String) {
  use current <- result.try(load_binding())
  require(binding == current, "tracking_launcher_binding_mismatch")
}

/// The tracking adapter still owns its immutable logical intent and outcome
/// reconciliation. These checks do not generalize the bootstrap grant.
pub fn begin_tracking(binding: Binding) -> Result(TrackingProof, String) {
  use _ <- result.try(check_launcher_binding(binding))
  use _ <- result.try(risk_check(binding))
  use proof <- result.try(fence(binding))
  Ok(TrackingProof(binding, proof))
}

/// Call after staging intent bytes and immediately before bounded dispatch.
/// Observation costs and elapsed preparation consume the actual lease budget.
pub fn tracking_budget_ms(proof: TrackingProof) -> Result(Int, String) {
  use _ <- result.try(check_launcher_binding(proof.binding))
  use current <- result.try(fence_for(proof.binding, 0))
  use _ <- result.try(clock.continuity(proof.started.clock, current.clock))
  dispatch_budget(current, 60_000)
}

/// A failed post-check must remain failed or uncertain even if the canonical
/// command changed state. It never permits an automatic effect retry.
pub fn end_tracking(
  binding: Binding,
  proof: TrackingProof,
) -> Result(Nil, String) {
  use _ <- result.try(require(
    binding == proof.binding,
    "tracking_proof_binding_mismatch",
  ))
  use _ <- result.try(check_launcher_binding(binding))
  use current <- result.try(fence_for(binding, 0))
  clock.continuity(proof.started.clock, current.clock)
}

fn heartbeat(binding: Binding) -> Result(json.Json, String) {
  use proof <- result.try(task_fence(binding))
  use revision <- result.try(bounded(
    pinned_jj,
    [
      "--ignore-working-copy",
      "--repository",
      root,
      "log",
      "-r",
      "@",
      "--no-graph",
      "-T",
      "commit_id",
    ],
    3000,
  ))
  let op =
    "harness-heartbeat-" <> int.to_string(proof.clock.sample.observed.utc_us)
  use beat <- result.try(
    bounded_observation(fn() { session_sync_cli.run([
      root <> "/var/coordination/tri-agent",
      "heartbeat",
      binding.session,
      string.trim(revision),
      "task:HARNESSBOOT,gleam-mcp-development-bootstrap",
      op,
    ]) }, 2000),
  )
  use renewed <- result.try(
    bounded_observation(fn() { session_sync_cli.run([
      root <> "/var/coordination/tri-agent",
      "renew",
      binding.session,
      "task:" <> binding.task,
      int.to_string(binding.epoch),
      "3600",
      op <> "-renew",
    ]) }, 2000),
  )
  Ok(
    json.object([
      #("heartbeat", json.string(beat)),
      #("task_lease", json.string(renewed)),
      #("revision", json.string(string.trim(revision))),
    ]),
  )
}

pub fn source_allowed(path: String) -> Bool {
  list.contains(bootstrap_source_paths(), path) && {
  string.starts_with(path, "apps/cepaf_gleam/src/cepaf_gleam/harness/")
  && string.ends_with(path, ".gleam")
  || list.contains(
    [
      "apps/cepaf_gleam/src/cepaf_gleam/mcp/server.gleam",
      "apps/cepaf_gleam/src/cepaf_gleam/mcp/tools.gleam",
      "apps/cepaf_gleam/src/cepaf_gleam/planning/sa_plan_bridge.gleam",
      "apps/cepaf_gleam/test/mcp_runtime_truth_test.gleam",
    ],
    path,
  )
  || string.starts_with(path, "apps/cepaf_gleam/test/harness_")
  && string.ends_with(path, ".gleam")
  }
}

pub fn document_allowed(path: String) -> Bool {
  list.any(
    [
      "docs/design/",
      "docs/journal/",
      "docs/wiki/",
      "docs/zk/",
      "governance/capability-inventory/",
    ],
    fn(prefix) {
      string.starts_with(path, prefix <> "20260909-")
      && string.contains(path, "harness")
      && list.any([".md", ".json", ".mmd", ".txt"], fn(suffix) {
        string.ends_with(path, suffix)
      })
    },
  )
  || string.starts_with(path, "docs/design/diagrams/20260909-0412-harness-")
  && { string.ends_with(path, ".mmd") || string.ends_with(path, ".txt") }
}

pub fn readable(path: String) -> Bool {
  source_allowed(path)
  || document_allowed(path)
  || path == "AGENTS.md"
  || path == "apps/cepaf_gleam/gleam.toml"
  || path == "apps/cepaf_gleam/manifest.toml"
  || path == portfolio
  || path == completion_intent
  || path == completion_result
  || string.starts_with(path, effects)
  && string.ends_with(path, ".json")
  || string.starts_with(path, ".codex/skills/")
  && string.ends_with(path, "SKILL.md")
  || string.starts_with(path, "contracts/rules/")
  && string.ends_with(path, ".md")
}

fn field(arguments: value.Value, key: String) -> Result(String, String) {
  use found <- result.try(value.get(arguments, key))
  case found {
    value.Text(s) -> Ok(s)
    _ -> Error("string_field:" <> key)
  }
}

fn risk_check(binding: Binding) -> Result(String, String) {
  use raw <- result.try(bounded(
    pinned_env,
    [
      // Native checker needs host chronyc until that observation adapter is
      // pinned. Language compilers resolve from the explicit repository paths;
      // no ambient PATH from an agent is inherited.
      "PATH=" <> build_path <> ":/usr/bin:/bin",
      "OPAM_SWITCH_PREFIX=" <> root <> "/toolchains/opam-ocaml",
      bootstrap_bash,
      root <> "/tools/risk-priority-check",
      "--active-check",
      root <> "/" <> portfolio,
      binding.task,
      binding.worker,
      int.to_string(binding.attempt),
    ],
    15_000,
  ))
  use status <- result.try(
    json.parse(raw, decode.field("status", decode.string, decode.success))
    |> result.map_error(fn(_) { "risk_receipt_invalid" }),
  )
  case status == "ACTIVE_OBSERVATION_PASS" {
    True -> Ok(raw)
    False -> Error("risk_hold")
  }
}

/// Rehash only existing assessed entries. This does not grant source-write
/// access to closure inputs or change the portfolio's analysis/expiry.
pub fn risk_input_allowed(path: String) -> Bool {
  source_allowed(path) || list.contains(bootstrap_source_paths(), path)
}

fn refresh_evidence(
  row: value.Value,
  now: String,
) -> Result(value.Value, String) {
  use snapshot <- result.try(value.get(row, "snapshot"))
  use evidence <- result.try(value.get(snapshot, "evidence"))
  use refreshed <- result.try(case evidence {
    value.Array(entries) -> {
      use new_entries <- result.try(
        list.try_map(entries, fn(entry) {
          use path <- result.try(field(entry, "path"))
          use _ <- result.try(case risk_input_allowed(path) {
            True -> Ok(Nil)
            False -> Error("risk_source_outside_grant")
          })
          // Changed bytes invalidate the assessment. Re-observation never
          // launders source drift into a fresh PASS with unchanged analysis.
          use body <- result.try(files.read(root, path))
          use assessed_digest <- result.try(field(entry, "sha256"))
          use _ <- result.try(require(
            files.digest(body) == assessed_digest,
            "risk_source_changed_requires_reassessment:" <> path,
          ))
          Ok(
            entry
            |> value.set("observed_at", value.Text(now)),
          )
        }),
      )
      Ok(value.Array(new_entries))
    }
    _ -> Error("risk_evidence_missing")
  })
  Ok(
    row
    |> value.set("observed_at", value.Text(now))
    |> value.set("snapshot", value.set(snapshot, "evidence", refreshed)),
  )
}

fn refresh_risk(binding: Binding) -> Result(json.Json, String) {
  use proof <- result.try(fence(binding))
  use body <- result.try(files.read(root, portfolio))
  use parsed <- result.try(
    json.parse(body, value.decoder())
    |> result.map_error(fn(_) { "risk_json_invalid" }),
  )
  use updated <- result.try(case parsed {
    value.Array(rows) ->
      list.try_map(rows, fn(row) {
        refresh_evidence(row, clock.canonical_utc(proof.clock))
      })
    _ -> Error("risk_portfolio_required")
  })
  use _ <- result.try(files.replace(
    root,
    portfolio,
    files.digest(body),
    json.to_string(json.array(updated, value.encode)) <> "\n",
  ))
  use receipt <- result.try(risk_check(binding))
  Ok(
    json.object([
      #("status", json.string("risk_observation_refreshed")),
      #("receipt", json.string(receipt)),
    ]),
  )
}

pub fn tool_names() -> List(String) {
  [
    "harness_heartbeat",
    "harness_status",
    "harness_clock",
    "harness_read_file",
    "harness_write_file",
    "harness_build",
    "harness_test",
    "harness_risk_refresh",
    "harness_risk_check",
    "harness_finish",
  ]
}

pub fn call(
  binding: Binding,
  name: String,
  arguments: value.Value,
) -> Result(json.Json, String) {
  use _ <- result.try(validate_arguments(name, arguments))
  case name {
    "harness_heartbeat" -> heartbeat(binding)
    "harness_clock" -> clock.observe() |> result.map(clock.to_json)
    "harness_status" -> status(binding)
    "harness_read_file" -> {
      use path <- result.try(field(arguments, "path"))
      use _ <- result.try(
        case path == completion_intent || path == completion_result {
          True -> completion_read_authority(binding)
          False -> fence_for(binding, 0) |> result.map(fn(_) { Nil })
        },
      )
      case readable(path) {
        False -> Error("read_scope_denied")
        True -> {
          use content <- result.try(files.read(root, path))
          Ok(
            json.object([
              #("path", json.string(path)),
              #("sha256", json.string(files.digest(content))),
              #("content", json.string(content)),
            ]),
          )
        }
      }
    }
    "harness_risk_refresh" -> refresh_risk(binding)
    "harness_risk_check" -> {
      use _ <- result.try(fence(binding))
      risk_check(binding)
      |> result.map(fn(receipt) {
        json.object([#("receipt", json.string(receipt))])
      })
    }
    "harness_finish" -> finish(binding, arguments)
    "harness_write_file" | "harness_build" | "harness_test" ->
      effect(binding, name, arguments)
    _ -> Error("unknown_or_unadmitted_tool")
  }
}

pub fn validate_arguments(
  name: String,
  arguments: value.Value,
) -> Result(Nil, String) {
  let expected = case name {
    "harness_read_file" -> ["path"]
    "harness_write_file" -> ["intent_id", "path", "content", "expected_sha256"]
    "harness_build" | "harness_test" -> ["intent_id"]
    "harness_finish" -> ["journal_path", "build_intent_id", "test_intent_id"]
    _ -> []
  }
  case arguments {
    value.Object(fields) ->
      case
        list.length(fields) == list.length(expected)
        && list.all(expected, fn(key) {
          case field(arguments, key) {
            Ok(_) -> True
            Error(_) -> False
          }
        })
        && list.all(fields, fn(p) { list.contains(expected, p.0) })
      {
        True -> Ok(Nil)
        False -> Error("exact_tool_schema_required")
      }
    _ -> Error("arguments_object_required")
  }
}

/// This is an explicit finite source set, not an attestation of every package,
/// toolchain, test oracle or runtime dependency in the repository.
pub fn bootstrap_source_paths() -> List(String) {
  [
    "apps/cepaf_gleam/src/cepaf_gleam/harness/value.gleam",
    "apps/cepaf_gleam/src/cepaf_gleam/harness/files.gleam",
    "apps/cepaf_gleam/src/cepaf_gleam/harness/clock.gleam",
    "apps/cepaf_gleam/src/cepaf_gleam/harness/development.gleam",
    "apps/cepaf_gleam/src/cepaf_gleam/harness/mcp.gleam",
    "apps/cepaf_gleam/src/cepaf_gleam/harness/peers.gleam",
    "apps/cepaf_gleam/src/cepaf_gleam/harness/tracking.gleam",
    "apps/cepaf_gleam/src/cepaf_gleam/mcp/server.gleam",
    "apps/cepaf_gleam/src/cepaf_gleam/mcp/tools.gleam",
    "apps/cepaf_gleam/src/cepaf_gleam/planning/sa_plan_bridge.gleam",
    "apps/cepaf_gleam/src/ecology_capability_ffi.erl",
    "apps/cepaf_gleam/src/cepaf_gleam_ffi.erl",
    "apps/cepaf_gleam/test/harness_development_test.gleam",
    "apps/cepaf_gleam/test/harness_authority_test.gleam",
    "apps/cepaf_gleam/test/harness_tracking_test.gleam",
    "apps/cepaf_gleam/test/harness_sa_plan_boundary_test.gleam",
    "apps/cepaf_gleam/test/harness_verification.gleam",
    "apps/cepaf_gleam/test/mcp_runtime_truth_test.gleam",
    "apps/cepaf_gleam/gleam.toml",
    "apps/cepaf_gleam/manifest.toml",
    "apps/uos_swarm/src/session_sync_cli.gleam",
    "apps/uos_swarm/src/uos_swarm/session_sync.gleam",
    "apps/uos_swarm/src/uos_swarm/clock_contract.gleam",
    "apps/uos_swarm/src/uos_swarm/clock_guard.gleam",
    "apps/uos_swarm/src/session_store_ffi.erl",
    "tools/ecology_process.ml",
    "tools/lib/uos-toolchain.sh",
    "governance/capability-inventory/20260909-0412-harness-feature-catalog.json",
  ]
}

fn capture_sources() -> Result(List(SourceDigest), String) {
  list.try_map(bootstrap_source_paths(), fn(path) {
    use source <- result.try(files.read(root, path))
    Ok(SourceDigest(path, files.digest(source)))
  })
}

pub fn manifest_json(sources: List(SourceDigest)) -> json.Json {
  json.array(sources, fn(source) {
    json.object([
      #("path", json.string(source.path)),
      #("sha256", json.string(source.sha256)),
    ])
  })
}

pub fn manifest_digest(sources: List(SourceDigest)) -> String {
  files.digest(json.to_string(manifest_json(sources)))
}

fn integer_field(data: value.Value, key: String) -> Result(Int, String) {
  use found <- result.try(value.get(data, key))
  case found {
    value.Integer(n) -> Ok(n)
    _ -> Error("integer_field:" <> key)
  }
}

fn receipt_sources(parsed: value.Value) -> Result(List(SourceDigest), String) {
  use source <- result.try(value.get(parsed, "source_manifest"))
  let item = {
    use path <- decode.field("path", decode.string)
    use sha <- decode.field("sha256", decode.string)
    decode.success(SourceDigest(path, sha))
  }
  json.parse(json.to_string(value.encode(source)), decode.list(item))
  |> result.map_error(fn(_) { "source_manifest_invalid" })
}

pub fn logical_intent(intent: String) -> Bool {
  valid_identifier(intent)
  && !string.contains(intent, "/")
  && !string.contains(intent, ".")
  && string.byte_size(intent) <= 80
}

fn intent_signature(name: String, arguments: value.Value) -> String {
  files.digest(name <> "\n" <> json.to_string(value.encode(arguments)))
}

fn simple_signature(name: String, intent: String) -> String {
  intent_signature(name, value.Object([#("intent_id", value.Text(intent))]))
}

pub fn validate_bootstrap_receipt(
  raw: String,
  binding: Binding,
  intent: String,
  tool: String,
  expected_sources: List(SourceDigest),
  expected_control: String,
) -> Result(value.Value, String) {
  use parsed <- result.try(
    json.parse(raw, value.decoder())
    |> result.map_error(fn(_) { "bootstrap_receipt_invalid" }),
  )
  use schema <- result.try(field(parsed, "schema"))
  use saved_intent <- result.try(field(parsed, "intent_id"))
  use saved_tool <- result.try(field(parsed, "tool"))
  use plan <- result.try(field(parsed, "plan"))
  use task <- result.try(field(parsed, "task"))
  use worker <- result.try(field(parsed, "worker"))
  use attempt <- result.try(integer_field(parsed, "attempt"))
  use epoch <- result.try(integer_field(parsed, "epoch"))
  use signature <- result.try(field(parsed, "signature"))
  use status <- result.try(field(parsed, "status"))
  use verification <- result.try(field(parsed, "verification"))
  use control <- result.try(field(parsed, "loaded_dispatch_module_md5"))
  use scope <- result.try(field(parsed, "source_manifest_scope"))
  use fingerprint <- result.try(field(parsed, "source_manifest_sha256"))
  use sources <- result.try(receipt_sources(parsed))
  use unchanged <- result.try(value.get(parsed, "source_manifest_unchanged"))
  use end <- result.try(value.get(parsed, "observed_end"))
  let end_present = case end {
    value.Object(_) -> True
    _ -> False
  }
  case
    logical_intent(intent)
    && { tool == "harness_build" || tool == "harness_test" }
    && schema == "uos.harness-effect.v1"
    && saved_intent == intent
    && saved_tool == tool
    && plan == binding.plan
    && task == binding.task
    && worker == binding.worker
    && attempt == binding.attempt
    && epoch == binding.epoch
    && signature == simple_signature(tool, intent)
    && status == "EXECUTED"
    && verification == "passed"
    && control == expected_control
    && scope == "finite_harness_reviewed_inputs_v1"
    && !list.is_empty(expected_sources)
    && sources == expected_sources
    && fingerprint == manifest_digest(expected_sources)
    && unchanged == value.Boolean(True)
    && end_present
  {
    True -> Ok(parsed)
    False -> Error("bootstrap_receipt_failed_stale_or_unbound")
  }
}

fn successful_receipt(
  binding: Binding,
  intent: String,
  tool: String,
  sources: List(SourceDigest),
) -> Result(String, String) {
  use _ <- result.try(case logical_intent(intent) {
    True -> Ok(Nil)
    False -> Error("logical_intent_id_invalid")
  })
  use pending <- result.try(files.read(
    root,
    effects <> "20260909-0412-" <> intent <> "-intent.json",
  ))
  use raw <- result.try(files.read(
    root,
    effects <> "20260909-0412-" <> intent <> "-result.json",
  ))
  use _ <- result.try(
    case
      pending == json.to_string(json.string(simple_signature(tool, intent)))
    {
      True -> Ok(Nil)
      False -> Error("bootstrap_pending_signature_mismatch")
    },
  )
  use _ <- result.try(validate_bootstrap_receipt(
    raw,
    binding,
    intent,
    tool,
    sources,
    control_id(),
  ))
  Ok(raw)
}

fn effect(
  binding: Binding,
  name: String,
  arguments: value.Value,
) -> Result(json.Json, String) {
  use intent <- result.try(field(arguments, "intent_id"))
  case logical_intent(intent) {
    False -> Error("logical_intent_id_invalid")
    True -> {
      use before <- result.try(fence(binding))
      use _ <- result.try(risk_check(binding))
      let signature = intent_signature(name, arguments)
      let pending = effects <> "20260909-0412-" <> intent <> "-intent.json"
      let done = effects <> "20260909-0412-" <> intent <> "-result.json"
      case files.read(root, pending) {
        Ok(previous) ->
          case previous == json.to_string(json.string(signature)) {
            False -> Error("intent_payload_conflict")
            True ->
              case files.read(root, done) {
                Ok(receipt) -> replay_receipt(receipt, intent, name, signature)
                Error(_) ->
                  Error("effect_outcome_unknown_reconcile_without_retry")
              }
          }
        Error(_) -> {
          // Exclusive create keeps an existing unreadable/corrupted pending file
          // from being treated as permission to retry.
          use _ <- result.try(files.create(
            root,
            pending,
            json.to_string(json.string(signature)),
          ))
          let source_check = name == "harness_build" || name == "harness_test"
          use sources <- result.try(case source_check {
            True -> capture_sources()
            False -> Ok([])
          })
          use dispatch <- result.try(fence(binding))
          use timeout <- result.try(dispatch_budget(dispatch, 60_000))
          let outcome = perform(name, arguments, timeout)
          let source_after = case source_check {
            True -> capture_sources()
            False -> Ok([])
          }
          let unchanged = source_after == Ok(sources)
          let after = fence_for(binding, 0)
          let verified = case outcome, after, unchanged {
            Ok(_), Ok(after), True ->
              clock.continuity(before.clock, after.clock)
            Error(e), _, _ -> Error(e)
            _, Error(e), _ -> Error("post_effect_authority_unknown:" <> e)
            _, _, False -> Error("source_changed_during_backend_execution")
          }
          let receipt =
            json.object([
              #("schema", json.string("uos.harness-effect.v1")),
              #("intent_id", json.string(intent)),
              #("tool", json.string(name)),
              #("plan", json.string(binding.plan)),
              #("task", json.string(binding.task)),
              #("worker", json.string(binding.worker)),
              #("attempt", json.int(binding.attempt)),
              #("epoch", json.int(binding.epoch)),
              #("signature", json.string(signature)),
              #("loaded_dispatch_module_md5", json.string(control_id())),
              #(
                "source_manifest_scope",
                json.string(case source_check {
                  True -> "finite_harness_reviewed_inputs_v1"
                  False -> "source_write_not_build_evidence"
                }),
              ),
              #("source_manifest", manifest_json(sources)),
              #("source_manifest_sha256", json.string(manifest_digest(sources))),
              #("source_manifest_unchanged", json.bool(unchanged)),
              #("operation_timeout_ms", json.int(timeout)),
              #(
                "fence_scope",
                json.string("cooperative_observation_not_atomic_authority"),
              ),
              #("observed_start", clock.to_json(before.clock)),
              #("observed_end", case after {
                Ok(proof) -> clock.to_json(proof.clock)
                Error(_) -> json.null()
              }),
              #(
                "status",
                json.string(case verified {
                  Ok(_) -> "EXECUTED"
                  Error(_) -> "FAILED_OR_UNVERIFIED"
                }),
              ),
              #(
                "detail",
                json.string(case outcome {
                  Ok(s) -> s
                  Error(e) -> e
                }),
              ),
              #(
                "verification",
                json.string(case verified {
                  Ok(_) -> "passed"
                  Error(e) -> e
                }),
              ),
              #("admission", json.string("NOT_GRANTED")),
            ])
          use _ <- result.try(files.create(
            root,
            done,
            json.to_string(receipt) <> "\n",
          ))
          case verified {
            Ok(_) -> Ok(receipt)
            Error(e) -> Error(e <> "; receipt:" <> done)
          }
        }
      }
    }
  }
}

pub fn replay_receipt(
  raw: String,
  intent: String,
  name: String,
  signature: String,
) -> Result(json.Json, String) {
  use parsed <- result.try(
    json.parse(raw, value.decoder())
    |> result.map_error(fn(_) { "saved_receipt_invalid" }),
  )
  use schema <- result.try(field(parsed, "schema"))
  use saved_intent <- result.try(field(parsed, "intent_id"))
  use saved_tool <- result.try(field(parsed, "tool"))
  use saved_signature <- result.try(field(parsed, "signature"))
  use status <- result.try(field(parsed, "status"))
  use verification <- result.try(field(parsed, "verification"))
  case
    schema == "uos.harness-effect.v1"
    && saved_intent == intent
    && saved_tool == name
    && saved_signature == signature
  {
    False -> Error("saved_receipt_binding_mismatch")
    True ->
      case status == "EXECUTED" && verification == "passed" {
        False -> Error("saved_effect_failed_or_unverified_no_retry")
        True ->
          Ok(
            json.object([
              #("replayed", json.bool(True)),
              #("receipt", value.encode(parsed)),
            ]),
          )
      }
  }
}

pub fn journal_sections_valid(journal: String) -> Bool {
  let titles = [
    "Scope & Trigger", "Pre-State Assessment", "Execution Detail",
    "Root Cause Analysis", "Fix Taxonomy", "Patterns & Anti-Patterns Discovered",
    "Verification Matrix", "Files Modified", "Architectural Observations",
    "Remaining Gaps", "Metrics Summary", "STAMP & Constitutional Alignment",
    "Conclusion",
  ]
  let expected =
    list.index_map(titles, fn(title, index) {
      "## " <> int.to_string(index + 1) <> ". " <> title
    })
  let actual =
    journal
    |> string.split("\n")
    |> list.map(string.trim)
    |> list.filter(fn(line) { string.starts_with(line, "## ") })
  actual == expected
  || actual == list.append(expected, ["## Comprehensive verification checklist"])
}

fn require(condition: Bool, reason: String) -> Result(Nil, String) {
  case condition {
    True -> Ok(Nil)
    False -> Error(reason)
  }
}

fn completion_arguments(
  arguments: value.Value,
) -> Result(#(String, String, String), String) {
  use path <- result.try(field(arguments, "journal_path"))
  use build <- result.try(field(arguments, "build_intent_id"))
  use test_intent <- result.try(field(arguments, "test_intent_id"))
  use _ <- result.try(require(
    document_allowed(path)
      && string.starts_with(path, "docs/journal/")
      && string.ends_with(path, ".md"),
    "completion_journal_scope",
  ))
  use _ <- result.try(require(
    logical_intent(build) && logical_intent(test_intent) && build != test_intent,
    "completion_build_and_test_ids_required",
  ))
  Ok(#(path, build, test_intent))
}

fn prepare_completion(
  binding: Binding,
  arguments: value.Value,
) -> Result(String, String) {
  use #(path, build, test_intent) <- result.try(completion_arguments(arguments))
  use journal <- result.try(files.read(root, path))
  use _ <- result.try(require(
    journal_sections_valid(journal),
    "completion_journal_sections_missing",
  ))
  use sources <- result.try(capture_sources())
  use build_receipt <- result.try(successful_receipt(
    binding,
    build,
    "harness_build",
    sources,
  ))
  use test_receipt <- result.try(successful_receipt(
    binding,
    test_intent,
    "harness_test",
    sources,
  ))
  Ok(
    json.to_string(
      json.object([
        #("schema", json.string("uos.harness-completion-intent.v1")),
        #("plan", json.string(binding.plan)),
        #("task", json.string(binding.task)),
        #("worker", json.string(binding.worker)),
        #("attempt", json.int(binding.attempt)),
        #("session", json.string(binding.session)),
        #("epoch", json.int(binding.epoch)),
        #("journal_path", json.string(path)),
        #("journal_sha256", json.string(files.digest(journal))),
        #("build_intent_id", json.string(build)),
        #("test_intent_id", json.string(test_intent)),
        #("build_receipt_sha256", json.string(files.digest(build_receipt))),
        #("test_receipt_sha256", json.string(files.digest(test_receipt))),
        #("source_manifest", manifest_json(sources)),
        #("source_manifest_sha256", json.string(manifest_digest(sources))),
        #("admission", json.string("NOT_GRANTED")),
      ]),
    ),
  )
}

fn validate_prepared(
  binding: Binding,
  raw: String,
) -> Result(value.Value, String) {
  use parsed <- result.try(
    json.parse(raw, value.decoder())
    |> result.map_error(fn(_) { "completion_intent_invalid" }),
  )
  use schema <- result.try(field(parsed, "schema"))
  use plan <- result.try(field(parsed, "plan"))
  use task <- result.try(field(parsed, "task"))
  use worker <- result.try(field(parsed, "worker"))
  use attempt <- result.try(integer_field(parsed, "attempt"))
  use session <- result.try(field(parsed, "session"))
  use epoch <- result.try(integer_field(parsed, "epoch"))
  use fingerprint <- result.try(field(parsed, "source_manifest_sha256"))
  use sources <- result.try(receipt_sources(parsed))
  use admission <- result.try(field(parsed, "admission"))
  use _ <- result.try(completion_arguments(parsed))
  use _ <- result.try(require(
    schema == "uos.harness-completion-intent.v1"
      && binding.role == "development"
      && plan == binding.plan
      && task == binding.task
      && worker == binding.worker
      && attempt == binding.attempt
      && session == binding.session
      && epoch == binding.epoch
      && list.map(sources, fn(source) { source.path })
      == bootstrap_source_paths()
      && fingerprint == manifest_digest(sources)
      && admission == "NOT_GRANTED",
    "completion_intent_binding_mismatch",
  ))
  Ok(parsed)
}

pub fn completion_task_result(prepared: String) -> String {
  "uos.harness-completion.v1:" <> files.digest(prepared)
}

/// Terminal reconciliation does not re-authorize source writes, builds or tests.
pub fn terminal_matches(
  binding: Binding,
  row: TaskRecord,
  expected: String,
) -> Bool {
  let completed_time = case row.completed_at_ns {
    Some(n) -> n > 0
    None -> False
  }
  binding.role == "development"
  && row.state == "completed"
  && row.worker == Some(binding.worker)
  && row.attempt == binding.attempt
  && row.lease_until_ns == None
  && row.result == Some(expected)
  && completed_time
}

type DurableMode {
  Read
  Raw
}

@external(erlang, "file", "open")
fn durable_open(
  path: String,
  modes: List(DurableMode),
) -> Result(files.Device, atom.Atom)

@external(erlang, "file", "sync")
fn durable_sync(device: files.Device) -> dynamic.Dynamic

@external(erlang, "file", "close")
fn durable_close(device: files.Device) -> dynamic.Dynamic

@external(erlang, "simplifile_erl", "file_info")
fn durable_info(
  device: files.Device,
) -> Result(simplifile.FileInfo, simplifile.FileError)

/// Visible matching bytes alone cannot upgrade an earlier sync failure.
pub fn accept_existing_artifact(
  wanted: String,
  observed: String,
  durability: Result(Nil, String),
) -> Result(Nil, String) {
  use _ <- result.try(require(wanted == observed, "artifact_bytes_changed"))
  durability
}

/// Re-establish durability without replacing matching immutable bytes. Like
/// files.read, this verifies the open descriptor; parent rename exclusion still
/// depends on cooperative ownership, not a descriptor-relative VFS.
pub fn verify_artifact_durability(
  base: String,
  relative: String,
  wanted: String,
) -> Result(Nil, String) {
  use observed <- result.try(files.read(base, relative))
  use _ <- result.try(require(wanted == observed, "artifact_bytes_changed"))
  use path <- result.try(files.checked_path(base, relative))
  use before <- result.try(
    simplifile.link_info(path)
    |> result.map_error(fn(_) { "artifact_stat_failed" }),
  )
  use fd <- result.try(
    durable_open(path, [Read, Raw])
    |> result.map_error(fn(_) { "artifact_sync_open_failed" }),
  )
  let synced = case durable_info(fd) {
    Ok(actual)
      if actual.inode == before.inode
      && actual.dev == before.dev
      && actual.nlinks == 1
      && actual.size <= files.max_bytes
    -> {
      case durable_sync(fd) == atom.to_dynamic(atom.create("ok")) {
        True -> Ok(Nil)
        False -> Error("artifact_file_sync_failed")
      }
    }
    _ -> Error("artifact_sync_descriptor_changed")
  }
  let closed = durable_close(fd)
  let durability = {
    use _ <- result.try(synced)
    use _ <- result.try(require(
      closed == atom.to_dynamic(atom.create("ok")),
      "artifact_sync_close_failed",
    ))
    let parent =
      path
      |> string.split("/")
      |> list.reverse
      |> list.drop(1)
      |> list.reverse
      |> string.join("/")
    clock_guard.verify_durable_directory(parent)
  }
  use _ <- result.try(accept_existing_artifact(wanted, observed, durability))
  use after <- result.try(files.read(base, relative))
  require(after == wanted, "artifact_changed_after_sync")
}

fn ensure_same_file(path: String, content: String) -> Result(Nil, String) {
  case files.read(root, path) {
    Ok(saved) -> {
      use _ <- result.try(require(
        saved == content,
        "immutable_artifact_conflict:" <> path,
      ))
      verify_artifact_durability(root, path, content)
    }
    Error(_) -> files.create(root, path, content)
  }
}

fn terminal_core(
  binding: Binding,
  row: TaskRecord,
  prepared: String,
) -> Result(json.Json, String) {
  use parsed <- result.try(validate_prepared(binding, prepared))
  use _ <- result.try(require(
    terminal_matches(binding, row, completion_task_result(prepared)),
    "terminal_task_result_mismatch",
  ))
  let completed = case row.completed_at_ns {
    Some(n) -> n
    None -> 0
  }
  Ok(
    json.object([
      #("schema", json.string("uos.harness-completion-result.v1")),
      #("completed", json.bool(True)),
      #("canonical_task_result", json.string(completion_task_result(prepared))),
      #("completed_at_ns", json.string(int.to_string(completed))),
      #("prepared_sha256", json.string(files.digest(prepared))),
      #("prepared", value.encode(parsed)),
      #("authority_scope", json.string("terminal_receipt_reconciliation_only")),
      #("system_admission", json.bool(False)),
    ]),
  )
}

fn reconcile_terminal(
  binding: Binding,
  row: TaskRecord,
  prepared: String,
) -> Result(json.Json, String) {
  use core <- result.try(terminal_core(binding, row, prepared))
  // If the original reply/receipt write was lost, the canonical terminal row
  // and immutable prepared digest suffice to reconstruct these exact bytes.
  use _ <- result.try(
    ensure_same_file(completion_result, json.to_string(core) <> "\n")
    |> result.map_error(fn(reason) {
      "task_completed_receipt_reconciliation_required:" <> reason
    }),
  )
  let released =
    bounded_observation(
      fn() {
        session_sync_cli.run([
          root <> "/var/coordination/tri-agent",
          "release",
          binding.session,
          "task:" <> binding.task,
          int.to_string(binding.epoch),
          "harness-bootstrap-finish-20260909-0412",
        ])
      },
      2000,
    )
  Ok(
    json.object([
      #("completion", core),
      #(
        "coordinator_release",
        json.object([
          #("verified", json.bool(result.is_ok(released))),
          #(
            "detail",
            json.string(case released {
              Ok(r) -> r
              Error(e) -> e
            }),
          ),
          #(
            "scope",
            json.string("idempotent_cleanup_separate_from_task_completion"),
          ),
        ]),
      ),
      #("system_admission", json.bool(False)),
    ]),
  )
}

fn completion_read_authority(binding: Binding) -> Result(Nil, String) {
  use row <- result.try(read_task(binding))
  case row.state {
    "completed" -> {
      use prepared <- result.try(files.read(root, completion_intent))
      terminal_core(binding, row, prepared) |> result.map(fn(_) { Nil })
    }
    _ -> fence_for(binding, 0) |> result.map(fn(_) { Nil })
  }
}

fn status(binding: Binding) -> Result(json.Json, String) {
  use row <- result.try(read_task(binding))
  case row.state {
    "completed" -> {
      use prepared <- result.try(files.read(root, completion_intent))
      use core <- result.try(terminal_core(binding, row, prepared))
      let expected = json.to_string(core) <> "\n"
      let artifact = case files.read(root, completion_result) {
        Ok(saved) if saved == expected -> "PRESENT_AND_MATCHED"
        Ok(_) -> "CONFLICT_RECONCILIATION_REQUIRED"
        Error(_) -> "MISSING_OR_UNREADABLE_RECONCILIATION_REQUIRED"
      }
      Ok(
        json.object([
          #("mode", json.string("development_bootstrap_terminal")),
          #("completion", core),
          #("completion_artifact", json.string(artifact)),
          #("ordinary_effects", json.string("REFUSED")),
          #("successor_grant", json.string("NOT_GRANTED")),
          #("system_admission", json.bool(False)),
        ]),
      )
    }
    _ -> {
      use proof <- result.try(fence_for(binding, 0))
      Ok(
        json.object([
          #("mode", json.string("development_bootstrap")),
          #("loaded_dispatch_module_md5", json.string(control_id())),
          #(
            "principal_binding",
            json.string(
              "environment_asserted_cooperative_local_filesystem_trust",
            ),
          ),
          #("credential_authentication", json.bool(False)),
          #("adapters", adapter_scope()),
          #("worker", json.string(binding.worker)),
          #("plan", json.string(binding.plan)),
          #("task", json.string(binding.task)),
          #("attempt", json.int(binding.attempt)),
          #("epoch", json.int(binding.epoch)),
          #("backend_selection", json.string("gleam_policy_fixed_adapters")),
          #(
            "fence_scope",
            json.string("cooperative_observation_not_atomic_authority"),
          ),
          #("zenoh", json.string("UNAVAILABLE_NOT_VERIFIED")),
          #("production_admission", json.bool(False)),
          #("core_tools", json.array(tool_names(), json.string)),
          #("clock", clock.to_json(proof.clock)),
        ]),
      )
    }
  }
}

fn finish(
  binding: Binding,
  arguments: value.Value,
) -> Result(json.Json, String) {
  use wanted <- result.try(completion_arguments(arguments))
  use row <- result.try(read_task(binding))
  case row.state {
    "completed" -> {
      use prepared <- result.try(files.read(root, completion_intent))
      use parsed <- result.try(validate_prepared(binding, prepared))
      use saved <- result.try(completion_arguments(parsed))
      use _ <- result.try(require(
        saved == wanted,
        "completion_request_conflict",
      ))
      reconcile_terminal(binding, row, prepared)
    }
    "executing" -> {
      use _ <- result.try(fence(binding))
      use _ <- result.try(risk_check(binding))
      use prepared <- result.try(prepare_completion(binding, arguments))
      use _ <- result.try(ensure_same_file(completion_intent, prepared))
      // Recheck evidence after durable preparation, then observe authority/time
      // after all those potentially blocking file reads.
      use current <- result.try(prepare_completion(binding, arguments))
      use _ <- result.try(require(
        current == prepared,
        "completion_inputs_changed",
      ))
      use proof <- result.try(fence_for(binding, 20_000))
      use budget <- result.try(dispatch_budget(proof, 10_000))
      use _ <- result.try(require(
        budget == 10_000,
        "completion_lease_budget_short",
      ))
      let command =
        sa_plan_bridge.complete_sa_task(
          binding.plan,
          binding.task,
          binding.worker,
          binding.attempt,
          completion_task_result(prepared),
        )
      // Never trust CLI output alone. A lost reply is resolved by the exact
      // canonical task result; this call never submits completion a second time.
      use terminal <- result.try(
        read_task(binding)
        |> result.map_error(fn(e) {
          "completion_outcome_unknown_reconcile:" <> e
        }),
      )
      case
        terminal_matches(binding, terminal, completion_task_result(prepared))
      {
        True -> reconcile_terminal(binding, terminal, prepared)
        False ->
          Error(
            "completion_not_observed_no_automatic_retry:"
            <> case command {
              Ok(_) -> "canonical_result_mismatch"
              Error(e) -> e
            },
          )
      }
    }
    _ -> Error("completion_task_not_executing_or_matching_terminal")
  }
}

fn perform(
  name: String,
  arguments: value.Value,
  timeout_ms: Int,
) -> Result(String, String) {
  case name {
    "harness_write_file" -> {
      use path <- result.try(field(arguments, "path"))
      use content <- result.try(field(arguments, "content"))
      use expected <- result.try(field(arguments, "expected_sha256"))
      case source_allowed(path) || document_allowed(path) {
        False -> Error("write_scope_denied")
        True -> {
          use _ <- result.try(case expected {
            "ABSENT" -> files.create(root, path, content)
            _ -> files.replace(root, path, expected, content)
          })
          use observed <- result.try(files.read(root, path))
          case observed == content {
            True -> Ok(files.digest(observed))
            False -> Error("write_readback_mismatch")
          }
        }
      }
    }
    "harness_build" ->
      bounded(
        pinned_env,
        [
          "--chdir=" <> root <> "/apps/cepaf_gleam",
          "PATH=" <> build_path,
          "ERL_FLAGS=+S 2:2 +A 2",
          "ERL_CRASH_DUMP_SECONDS=0",
          pinned_gleam,
          "build",
        ],
        timeout_ms,
      )
    "harness_test" ->
      bounded(
        pinned_env,
        [
          "--chdir=" <> root <> "/apps/cepaf_gleam",
          "PATH=" <> build_path,
          "ERL_FLAGS=+S 2:2 +A 2",
          "ERL_CRASH_DUMP_SECONDS=0",
          pinned_gleam,
          "run",
          "-m",
          "harness_verification",
        ],
        timeout_ms,
      )
    _ -> Error("effect_not_in_finite_grant")
  }
}
