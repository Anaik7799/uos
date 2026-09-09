//// Reviewed local-launcher development grant and canonical task admission.
//// This is cooperative filesystem/session trust, not cryptographic workload IAM.
//// Historical HARNESSBOOT is never a successor task; production is refused.

import cepaf_gleam/harness/clock
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import cepaf_gleam/harness/value
import cepaf_gleam/planning/sa_plan_bridge as sa
import gleam/bit_array
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import session_sync_cli
import simplifile

pub type Scope {
  Scope(plan: String, task: String, reads: List(String), writes: List(String),
    sources: List(String), tests: List(String), portfolio: String)
}
pub type Grant {
  Grant(id: String, path: String, digest: String, session: String, worker: String,
    host: String, boot: String, expires_us: Int, scopes: List(Scope),
    review_path: String, review_sha256: String)
}
pub type Execution {
  Execution(grant: Grant, scope: Scope, binding: dev.Binding, risk_path: String)
}

@external(erlang, "cepaf_gleam_ffi", "get_env")
fn get_env(key: String) -> Result(String, Nil)
@external(erlang, "erlang", "apply")
fn metadata(module: atom.Atom, function: atom.Atom, arguments: List(atom.Atom)) -> BitArray

pub const control_modules = [
  "cepaf_gleam@harness@admission", "cepaf_gleam@harness@operations",
  "cepaf_gleam@harness@successor_mcp", "cepaf_gleam@harness@mcp",
  "cepaf_gleam@harness@development", "cepaf_gleam@harness@clock",
  "cepaf_gleam@harness@files", "cepaf_gleam@harness@value",
  "cepaf_gleam@planning@sa_plan_bridge",
]

// C4: the guardian at tools/ecology_process.ml bounds every effect's time,
// output and process group, is invoked from ecology_capability_ffi.erl, and was
// bound by NOTHING -- no path list, no control module. It could change while the
// review, the task row, the candidate manifest and all nine control ids stayed
// perfectly matched. These are control dependencies that are not BEAM modules,
// so `module_info(md5)` cannot reach them; their digests are declared in the
// grant, which the peer signs by hashing the proposal.
pub const control_dependencies = ["tools/ecology_process.ml"]

pub fn control_ids() -> json.Json {
  json.object(list.map(control_modules, fn(name) {
    let digest = metadata(atom.create(name), atom.create("module_info"), [atom.create("md5")])
      |> bit_array.base16_encode |> string.lowercase
    #(name, json.string(digest))
  }))
}
pub fn require(ok: Bool, reason: String) -> Result(Nil, String) {
  case ok { True -> Ok(Nil) False -> Error(reason) }
}
pub fn component(text: String) -> Bool {
  string.byte_size(text) > 0 && string.byte_size(text) <= 120
  && list.all(string.to_graphemes(text), fn(c) {
    string.contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.", c)
  }) && text != "." && text != ".."
}
pub fn intent_valid(text: String) -> Bool {
  component(text) && string.byte_size(text) <= 48
}
pub fn digest_valid(text: String) -> Bool {
  string.byte_size(text) == 64 && list.all(string.to_graphemes(text), fn(c) {
    string.contains("0123456789abcdef", c)
  })
}
pub fn public_path(path: String) -> Bool {
  result.is_ok(files.relative_path(path)) && !string.contains(path, "/.")
  && !string.contains(string.lowercase(path), "credential")
  && !string.contains(string.lowercase(path), "secret")
  && !string.ends_with(path, ".sqlite3") && !string.ends_with(path, ".db")
  && { path == "AGENTS.md"
    || list.any(["apps/", "docs/", "formal/", "contracts/", "governance/", "tools/"], fn(p) {
      string.starts_with(path, p)
    })
  }
}
pub fn risk_path(path: String) -> Bool {
  result.is_ok(files.relative_path(path)) && string.starts_with(path, "var/harness/")
  && string.ends_with(path, ".json") && !string.contains(path, "/.")
}
pub fn scope_valid(scope: Scope) -> Bool {
  dev.valid_identifier(scope.plan) && string.starts_with(scope.plan, "uos/")
  && dev.valid_identifier(scope.task) && scope.task != "HARNESSBOOT"
  && list.length(scope.reads) <= 256 && list.length(scope.writes) <= 128
  && scope.sources != [] && list.length(scope.sources) <= 128
  && list.all(list.append(scope.reads, list.append(scope.writes, scope.sources)), public_path)
  && list.all(scope.writes, fn(p) {
    // New implementation/control code is Gleam; documentation is data.
    string.ends_with(p, ".gleam") || string.ends_with(p, ".md") || string.ends_with(p, ".json")
  })
  && scope.tests != [] && list.length(scope.tests) <= 32
  && list.all(scope.tests, fn(t) { component(t) && !string.contains(t, ".") && !string.contains(t, "-") })
  && risk_path(scope.portfolio) && string.ends_with(scope.portfolio, "-current-risk.json")
}
fn scope_decoder() -> decode.Decoder(Scope) {
  use plan <- decode.field("plan", decode.string)
  use task <- decode.field("task", decode.string)
  use reads <- decode.field("read_paths", decode.list(decode.string))
  use writes <- decode.field("write_paths", decode.list(decode.string))
  use sources <- decode.field("source_paths", decode.list(decode.string))
  use tests <- decode.field("test_modules", decode.list(decode.string))
  use portfolio <- decode.field("risk_portfolio", decode.string)
  decode.success(Scope(plan, task, reads, writes, sources, tests, portfolio))
}
pub fn decode_grant(path: String, body: String) -> Result(Grant, String) {
  let decoder = {
    use schema <- decode.field("schema", decode.string)
    use role <- decode.field("role", decode.string)
    use id <- decode.field("grant_id", decode.string)
    use session <- decode.field("session", decode.string)
    use worker <- decode.field("worker", decode.string)
    use host <- decode.field("host_id", decode.string)
    use boot <- decode.field("boot_id", decode.string)
    use expiry <- decode.field("expires_utc_us", decode.string)
    use scopes <- decode.field("tasks", decode.list(scope_decoder()))
    use review <- decode.field("review_path", decode.string)
    use review_hash <- decode.field("review_sha256", decode.string)
    decode.success(#(schema, role, id, session, worker, host, boot, expiry, scopes, review, review_hash))
  }
  use fields <- result.try(json.parse(body, decoder) |> result.map_error(fn(_) { "grant_decode" }))
  use expiry <- result.try(int.parse(fields.7) |> result.map_error(fn(_) { "grant_expiry" }))
  use _ <- result.try(require(fields.0 == "uos.harness-development-grant.v1"
    && fields.1 == "development" && intent_valid(fields.2)
    && dev.valid_identifier(fields.3) && dev.valid_identifier(fields.4)
    && digest_valid(fields.5) && dev.valid_identifier(fields.6)
    && fields.8 != [] && list.length(fields.8) <= 64
    && list.all(fields.8, scope_valid)
    && list.length(list.unique(list.map(fields.8, fn(s) { #(s.plan, s.task) }))) == list.length(fields.8)
    && public_path(fields.9) && digest_valid(fields.10) && risk_path(path),
    "grant_scope_or_role_refused"))
  Ok(Grant(fields.2, path, files.digest(body), fields.3, fields.4, fields.5,
    fields.6, expiry, fields.8, fields.9, fields.10))
}
pub fn grant_budget_valid(expires_us: Int, now_us: Int, required_ms: Int) -> Bool {
  now_us >= 0 && required_ms >= 0 && required_ms <= 70_000
    && expires_us > now_us + required_ms * 1000
    && expires_us - now_us <= 86_400_000_000
}
pub fn validate_window_for(grant: Grant, observed: clock.Observation, required_ms: Int) -> Result(Nil, String) {
  let current = observed.sample.observed
  require(grant.host == current.domain.host_id && grant.boot == current.domain.boot_id
    && grant_budget_valid(grant.expires_us, current.utc_us, required_ms),
    "grant_host_boot_expiry_or_operation_window")
}
pub fn validate_window(grant: Grant, observed: clock.Observation) -> Result(Nil, String) {
  validate_window_for(grant, observed, 0)
}
pub fn control_ids_match(recorded: value.Value, actual: json.Json) -> Bool {
  case recorded, json.parse(json.to_string(actual), value.decoder()) {
    value.Object(fields), Ok(expected) ->
      list.length(fields) == list.length(control_modules)
      && list.all(control_modules, fn(name) { value.get(recorded, name) == value.get(expected, name) })
    _, _ -> False
  }
}
// Fails closed on every arm: a missing declaration, a missing file, an
// unreadable file, an invalid digest or a mismatch all refuse admission. An
// unverified dependency is never an admitted one.
pub fn control_dependencies_match(recorded: value.Value) -> Result(Nil, String) {
  case recorded {
    value.Object(entries) -> {
      use _ <- result.try(require(
        list.length(entries) == list.length(control_dependencies)
          && list.all(control_dependencies, fn(p) { result.is_ok(value.get(recorded, p)) }),
        "control_dependency_set_mismatch",
      ))
      list.try_each(control_dependencies, fn(rel) {
        use declared <- result.try(value.get(recorded, rel))
        use expected <- result.try(case declared {
          value.Text(hash) ->
            case digest_valid(hash) {
              True -> Ok(hash)
              False -> Error("control_dependency_digest_invalid:" <> rel)
            }
          _ -> Error("control_dependency_digest_invalid:" <> rel)
        })
        use body <- result.try(
          files.read(dev.root, rel)
          |> result.map_error(fn(_) { "control_dependency_unreadable:" <> rel }),
        )
        require(files.digest(body) == expected, "control_dependency_digest_mismatch:" <> rel)
      })
    }
    _ -> Error("control_dependencies_object_required")
  }
}

fn text_field(document: value.Value, key: String) -> Result(String, String) {
  use found <- result.try(value.get(document, key))
  case found { value.Text(text) -> Ok(text) _ -> Error("review_string_field:" <> key) }
}
fn same_object(left: value.Value, right: value.Value) -> Bool {
  case left, right {
    value.Object(a), value.Object(b) ->
      list.length(a) == list.length(b)
      && list.length(list.unique(list.map(a, fn(p) { p.0 }))) == list.length(a)
      && list.length(list.unique(list.map(b, fn(p) { p.0 }))) == list.length(b)
      && list.all(a, fn(p) {
        case value.get(right, p.0) { Ok(v) -> same_value(p.1, v) Error(_) -> False }
      })
    _, _ -> False
  }
}
pub fn same_value(left: value.Value, right: value.Value) -> Bool {
  case left, right {
    value.Object(_), value.Object(_) -> same_object(left, right)
    value.Array(a), value.Array(b) ->
      list.length(a) == list.length(b)
      && list.all(list.zip(a, b), fn(p) { same_value(p.0, p.1) })
    _, _ -> left == right
  }
}
pub fn outcome_unknown(reason: String) -> Bool {
  list.any(["claim_outcome_unknown:", "attachment_outcome_unknown:",
    "release_outcome_unknown:", "completion_outcome_unknown:",
    "effect_unverified:", "reconciliation_outcome_unknown:"],
    fn(prefix) { string.starts_with(reason, prefix) })
    || string.contains(reason, "unknown_effect_outcome")
}
pub fn review_task_matches(binding: dev.Binding, row: dev.TaskRecord, digest: String) -> Bool {
  digest_valid(digest) && dev.terminal_matches(binding, row, "uos.harness-peer-review.v1:" <> digest)
}
fn check_review_task(document: value.Value, reviewed: value.Value, digest: String) -> Result(Nil, String) {
  use expected <- result.try(value.get(document, "review_task"))
  use plan <- result.try(text_field(expected, "plan"))
  use task <- result.try(text_field(expected, "task"))
  use reviewer <- result.try(value.get(reviewed, "reviewer"))
  use actual_plan <- result.try(text_field(reviewer, "plan_id"))
  use actual_task <- result.try(text_field(reviewer, "task_id"))
  use worker <- result.try(text_field(reviewer, "worker"))
  use session <- result.try(text_field(reviewer, "session_id"))
  use attempt <- result.try(value.get(reviewer, "attempt"))
  use attempt <- result.try(case attempt { value.Integer(n) if n > 0 -> Ok(n) _ -> Error("review_attempt") })
  use grant_worker <- result.try(text_field(document, "worker"))
  use _ <- result.try(require(dev.valid_identifier(plan) && string.starts_with(plan, "uos/")
    && dev.valid_identifier(task) && task != "HARNESSBOOT"
    && actual_plan == plan && actual_task == task && component(worker)
    && worker != grant_worker, "review_task_binding"))
  let binding = dev.Binding("development", plan, task, worker, attempt, session, 1)
  use row <- result.try(dev.read_task(binding))
  require(review_task_matches(binding, row, digest), "canonical_review_completion_digest")
}
pub fn validate_review(
  document: value.Value,
  reviewed: value.Value,
  proposal: value.Value,
) -> Result(Nil, String) {
  use _ <- result.try(require(value.get(reviewed, "schema")
    == Ok(value.Text("uos.harness-successor-grant-review.v1")), "review_schema"))
  use _ <- result.try(require(value.get(reviewed, "verdict")
    == Ok(value.Text("APPROVE_DEV_TEST_SCOPE")), "review_verdict"))
  use proposal_path <- result.try(text_field(document, "proposal_path"))
  use proposal_hash <- result.try(text_field(document, "proposal_sha256"))
  use review_hash <- result.try(value.get(document, "review_sha256"))
  use _ <- result.try(require(risk_path(proposal_path) && digest_valid(proposal_hash),
    "review_proposal_reference"))
  use binding <- result.try(value.get(reviewed, "grant_proposal"))
  use _ <- result.try(list.try_each([
    #("path", value.Text(proposal_path)), #("sha256", value.Text(proposal_hash)),
  ], fn(pair) {
    require(value.get(binding, pair.0) == Ok(pair.1), "review_proposal_binding")
  }))
  use _ <- result.try(list.try_each([
    #("grant_id", "grant_id"), #("target_session", "session"), #("target_worker", "worker"),
  ], fn(pair) {
    use expected <- result.try(text_field(document, pair.1))
    require(value.get(binding, pair.0) == Ok(value.Text(expected)), "review_identity_binding")
  }))
  use reviewer <- result.try(value.get(reviewed, "reviewer"))
  use peer_session <- result.try(text_field(reviewer, "session_id"))
  use session <- result.try(text_field(document, "session"))
  use _ <- result.try(require(component(peer_session) && peer_session != session,
    "independent_review_session_required"))
  // The launcher may bind the review hash and immutable proposal reference.
  // Every other grant field must remain exactly as the peer reviewed it.
  let expected = proposal
    |> value.set("review_sha256", review_hash)
    |> value.set("proposal_path", value.Text(proposal_path))
    |> value.set("proposal_sha256", value.Text(proposal_hash))
  let differing = case document {
    value.Object(fields) -> list.find(fields, fn(p) {
      case value.get(expected, p.0) { Ok(v) -> !same_value(p.1, v) Error(_) -> True }
    }) |> result.map(fn(p) { p.0 }) |> result.unwrap("object_shape_or_duplicate_key")
    _ -> "object_shape"
  }
  require(same_object(document, expected), "grant_differs_from_reviewed_proposal:$." <> differing)
}
pub fn check(grant: Grant) -> Result(clock.Observation, String) {
  use body <- result.try(files.read(dev.root, grant.path))
  use _ <- result.try(require(files.digest(body) == grant.digest, "grant_changed"))
  use reviewed <- result.try(files.read(dev.root, grant.review_path))
  use _ <- result.try(require(files.digest(reviewed) == grant.review_sha256, "review_changed"))
  use document <- result.try(json.parse(body, value.decoder()) |> result.map_error(fn(_) { "grant_json" }))
  use review_document <- result.try(json.parse(reviewed, value.decoder())
    |> result.map_error(fn(_) { "review_json" }))
  use _ <- result.try(require(value.get(review_document, "verdict")
    == Ok(value.Text("APPROVE_DEV_TEST_SCOPE")), "review_verdict"))
  use proposal_path <- result.try(text_field(document, "proposal_path"))
  use proposal_hash <- result.try(text_field(document, "proposal_sha256"))
  use _ <- result.try(require(risk_path(proposal_path) && proposal_path != grant.path
    && digest_valid(proposal_hash), "proposal_reference"))
  use proposal_body <- result.try(files.read(dev.root, proposal_path))
  use _ <- result.try(require(files.digest(proposal_body) == proposal_hash, "proposal_changed"))
  use proposal <- result.try(json.parse(proposal_body, value.decoder())
    |> result.map_error(fn(_) { "proposal_json" }))
  use _ <- result.try(validate_review(document, review_document, proposal))
  use _ <- result.try(check_review_task(document, review_document, grant.review_sha256))
  use recorded <- result.try(value.get(document, "loaded_control_ids"))
  use _ <- result.try(require(control_ids_match(recorded, control_ids()),
    "loaded_control_identity_mismatch"))
  use recorded_dependencies <- result.try(value.get(document, "control_dependencies"))
  use _ <- result.try(control_dependencies_match(recorded_dependencies))
  use now <- result.try(clock.observe())
  use _ <- result.try(validate_window(grant, now))
  Ok(now)
}
pub fn load() -> Result(Grant, String) {
  use path <- result.try(get_env("UOS_HARNESS_GRANT_PATH") |> result.map_error(fn(_) { "grant_path_missing" }))
  use expected <- result.try(get_env("UOS_HARNESS_GRANT_SHA256") |> result.map_error(fn(_) { "grant_digest_missing" }))
  use body <- result.try(files.read(dev.root, path))
  use _ <- result.try(require(digest_valid(expected) && files.digest(body) == expected, "launcher_grant_digest"))
  use grant <- result.try(decode_grant(path, body))
  use _ <- result.try(check(grant))
  Ok(grant)
}
pub fn lookup(grant: Grant, plan: String, task: String) -> Result(Scope, String) {
  list.find(grant.scopes, fn(s) { s.plan == plan && s.task == task })
  |> result.map_error(fn(_) { "task_not_in_reviewed_grant" })
}
pub fn coordinate(args: List(String)) -> Result(String, String) {
  dev.bounded_observation(fn() {
    session_sync_cli.run([dev.root <> "/var/coordination/tri-agent", ..args])
  }, 3000)
}
pub fn heartbeat(grant: Grant) -> Result(json.Json, String) {
  use now <- result.try(check(grant))
  use revision <- result.try(dev.bounded(dev.root <> "/toolchains/nix-profile/bin/jj",
    ["--ignore-working-copy", "--repository", dev.root, "log", "-r", "@", "--no-graph", "-T", "commit_id"], 3000))
  use raw <- result.try(coordinate(["heartbeat", grant.session, string.trim(revision),
    "successor-grant:" <> grant.id, "successor-heartbeat-" <> int.to_string(now.sample.observed.utc_us)]))
  json.parse(raw, value.decoder()) |> result.map(value.encode) |> result.map_error(fn(_) { "heartbeat_json" })
}
pub fn read_optional(path: String) -> Result(Option(String), String) {
  use absolute <- result.try(files.checked_path(dev.root, path))
  case simplifile.link_info(absolute) {
    Error(simplifile.Enoent) -> Ok(None)
    Error(_) -> Error("artifact_stat_failed")
    Ok(_) -> files.read(dev.root, path) |> result.map(Some)
  }
}
pub fn risk_check(path: String, scope: Scope, worker: String, attempt: Int, active: Bool) -> Result(String, String) {
  use _ <- result.try(require(risk_path(path), "risk_path_refused"))
  let mode = case active {
    True -> ["--active-check", dev.root <> "/" <> path, scope.task, worker, int.to_string(attempt)]
    False -> ["--preflight", dev.root <> "/" <> path, scope.task]
  }
  use raw <- result.try(dev.bounded(dev.root <> "/toolchains/nix-profile/bin/env", [
    "PATH=" <> dev.root <> "/toolchains/nix-profile/bin:" <> dev.root <> "/toolchains/opam-ocaml/bin:/usr/bin:/bin",
    "OPAM_SWITCH_PREFIX=" <> dev.root <> "/toolchains/opam-ocaml",
    "/usr/bin/bash", dev.root <> "/tools/risk-priority-check", ..mode], 15_000))
  use parsed <- result.try(json.parse(raw, value.decoder()) |> result.map_error(fn(_) { "risk_json" }))
  use status <- result.try(value.get(parsed, "status"))
  let expected = case active { True -> "ACTIVE_OBSERVATION_PASS" False -> "PREFLIGHT_PASS" }
  use _ <- result.try(require(status == value.Text(expected), "risk_hold"))
  Ok(raw)
}
pub fn state_assessment(execution: Execution, state: String, suffix: String) -> Result(String, String) {
  use body <- result.try(files.read(dev.root, execution.risk_path))
  use parsed <- result.try(json.parse(body, value.decoder()) |> result.map_error(fn(_) { "risk_json" }))
  use records <- result.try(case parsed { value.Array(xs) -> Ok(xs) _ -> Error("risk_array") })
  let changed = list.map(records, fn(record) {
    case value.get(record, "plan_id"), value.get(record, "task_id") {
      Ok(value.Text(p)), Ok(value.Text(t)) if p == execution.scope.plan && t == execution.scope.task ->
        value.set(record, "task_state", value.Text(state))
      _, _ -> record
    }
  })
  let updated = value.encode(value.Array(changed)) |> json.to_string
  let path = "var/harness/" <> execution.grant.id <> "-" <> suffix <> "-risk.json"
  use _ <- result.try(files.create(dev.root, path, updated))
  use original <- result.try(files.read(dev.root, execution.scope.portfolio))
  use _ <- result.try(files.create(dev.root, path <> ".before.json", original))
  use _ <- result.try(files.replace(dev.root, execution.scope.portfolio, files.digest(original), updated))
  Ok(execution.scope.portfolio)
}
pub fn attach(grant: Grant, scope: Scope, intent: String) -> Result(Execution, String) {
  use _ <- result.try(require(intent_valid(intent), "intent_id"))
  use now <- result.try(check(grant))
  use _ <- result.try(validate_window_for(grant, now, 70_000))
  use _ <- result.try(heartbeat(grant))
  let base = dev.Binding("development", scope.plan, scope.task, grant.worker, 1, grant.session, 1)
  use row <- result.try(dev.read_task(base))
  use _ <- result.try(require(row.state == "executing" && row.worker == Some(grant.worker) && row.attempt > 0,
    "attach_requires_current_owned_attempt"))
  let outcome = {
    let preliminary = Execution(grant, scope, dev.Binding(..base, attempt: row.attempt), scope.portfolio)
    use current_risk <- result.try(state_assessment(preliminary, "executing", intent <> "-attach"))
    use _ <- result.try(risk_check(current_risk, scope, grant.worker, row.attempt, True))
    use raw <- result.try(coordinate(["claim", grant.session, dev.task_resource(base), "3600", grant.id <> "-" <> intent <> "-coordinate"]))
    use epoch <- result.try(json.parse(raw, decode.field("epoch", decode.int, decode.success))
      |> result.map_error(fn(_) { "coordinator_claim_outcome_unknown" }))
    let active = Execution(..preliminary, binding: dev.Binding(..base, attempt: row.attempt, epoch: epoch))
    use _ <- result.try(fence(active, 0))
    Ok(active)
  }
  result.map_error(outcome, fn(e) { "attachment_outcome_unknown:" <> e })
}
pub fn claim(grant: Grant, scope: Scope, intent: String) -> Result(Execution, String) {
  use _ <- result.try(require(intent_valid(intent), "intent_id"))
  use now <- result.try(check(grant))
  use _ <- result.try(validate_window_for(grant, now, 70_000))
  use _ <- result.try(heartbeat(grant))
  use _ <- result.try(risk_check(scope.portfolio, scope, grant.worker, 0, False))
  let begin_path = "var/harness/" <> grant.id <> "-" <> intent <> "-claim-intent.json"
  let body = json.object([#("plan", json.string(scope.plan)), #("task", json.string(scope.task)),
    #("worker", json.string(grant.worker)), #("grant_sha256", json.string(grant.digest))]) |> json.to_string
  // Once an intent may exist, only explicit ownership reconciliation can resume.
  use _ <- result.try(files.create(dev.root, begin_path, body)
    |> result.map_error(fn(e) { "claim_outcome_unknown:intent:" <> e }))
  let outcome = {
    use _ <- result.try(sa.run_sa_plan_cli(["task", "claim", grant.worker, scope.plan, "3600000000000", scope.task]))
    let base = dev.Binding("development", scope.plan, scope.task, grant.worker, 1, grant.session, 1)
    use row <- result.try(dev.read_task(base))
    use _ <- result.try(require(row.state == "executing" && row.worker == Some(grant.worker), "claim_outcome_unknown"))
    let interim = Execution(grant, scope, dev.Binding(..base, attempt: row.attempt), scope.portfolio)
    use risk <- result.try(state_assessment(interim, "executing", intent))
    use _ <- result.try(risk_check(risk, scope, grant.worker, row.attempt, True))
    use raw <- result.try(coordinate(["claim", grant.session, dev.task_resource(base), "3600", grant.id <> "-" <> intent <> "-coordinate"]))
    use epoch <- result.try(json.parse(raw, decode.field("epoch", decode.int, decode.success))
      |> result.map_error(fn(_) { "coordinator_claim_outcome_unknown" }))
    let active = Execution(..interim, risk_path: risk, binding: dev.Binding(..interim.binding, epoch: epoch))
    use _ <- result.try(fence(active, 0))
    Ok(active)
  }
  result.map_error(outcome, fn(e) { "claim_outcome_unknown:" <> e })
}
pub fn fence(execution: Execution, duration_ms: Int) -> Result(dev.Fence, String) {
  use _ <- result.try(require(duration_ms >= 0 && duration_ms <= 65_000, "operation_window_bound"))
  use _ <- result.try(check(execution.grant))
  use proof <- result.try(dev.fence_for(execution.binding, duration_ms + 5000))
  use _ <- result.try(validate_window_for(execution.grant, proof.clock, duration_ms + 5000))
  Ok(proof)
}
pub fn observe_execution(execution: Execution) -> json.Json {
  json.object([#("plan", json.string(execution.scope.plan)), #("task", json.string(execution.scope.task)),
    #("worker", json.string(execution.binding.worker)), #("attempt", json.int(execution.binding.attempt)),
    #("coordinator_epoch", json.int(execution.binding.epoch)), #("risk_portfolio", json.string(execution.risk_path)),
    #("grant_sha256", json.string(execution.grant.digest)),
    #("authority", json.string("canonical_sa_plan_with_cooperative_local_launcher_and_session_fences")),
    #("production_admission", json.bool(False))])
}
