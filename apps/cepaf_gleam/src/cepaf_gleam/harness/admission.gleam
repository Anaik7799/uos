//// Reviewed local-launcher development grant and canonical task admission.
//// This is cooperative filesystem/session trust, not cryptographic workload IAM.
//// Historical HARNESSBOOT is never a successor task; production is refused.

import cepaf_gleam/harness/clock
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import cepaf_gleam/harness/value
import cepaf_gleam/mcp/json_guard
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
import simplifile
import uos_swarm/session_authority
import uos_swarm/session_store

pub type Scope {
  Scope(
    plan: String,
    task: String,
    reads: List(String),
    writes: List(String),
    sources: List(String),
    tests: List(String),
    portfolio: String,
    allowed_clients: List(String),
    allowed_client_actions: List(String),
  )
}

pub type Grant {
  Grant(
    id: String,
    path: String,
    digest: String,
    session: String,
    worker: String,
    host: String,
    boot: String,
    expires_us: Int,
    scopes: List(Scope),
    workspace_root: String,
    review_path: String,
    review_sha256: String,
  )
}

pub type Execution {
  Execution(grant: Grant, scope: Scope, binding: dev.Binding, risk_path: String)
}

/// Factual fixed-plan recovery context. This is neither a TaskFence nor a
/// permission. Only the explicit preparation branch consumes it.
pub opaque type RecoveryProposalData {
  RecoveryProposalData(
    plan: String,
    selected_task: String,
    worker: String,
    snapshot_sha256: String,
    assessment_sha256: String,
    source_manifest_sha256: String,
    bindings: List(RecoveryOldClaim),
    selection_review: value.Value,
  )
}

pub type RecoveryOldClaim {
  RecoveryOldClaim(task: String, worker: String, attempt: Int, lease_ns: Int)
}

pub opaque type RecoveryObservationData {
  RecoveryObservationData(proposal: RecoveryProposalData, report_sha256: String)
}

pub opaque type PreparedRecovery {
  PreparedRecovery(
    observation: RecoveryObservationData,
    grant_sha256: String,
    review_sha256: String,
    observed_utc_us: Int,
  )
}

@external(erlang, "cepaf_gleam_ffi", "get_env")
fn get_env(key: String) -> Result(String, Nil)

@external(erlang, "erlang", "apply")
fn metadata(
  module: atom.Atom,
  function: atom.Atom,
  arguments: List(atom.Atom),
) -> BitArray

pub const control_modules = [
  "cepaf_gleam@harness@admission", "cepaf_gleam@harness@operations",
  "cepaf_gleam@harness@successor_mcp", "cepaf_gleam@harness@mcp",
  "cepaf_gleam@harness@development", "cepaf_gleam@harness@clock",
  "cepaf_gleam@harness@files", "cepaf_gleam@harness@value",
  "cepaf_gleam@planning@sa_plan_bridge", "uos_swarm@session_authority",
  "uos_swarm@session_store", "uos_swarm@session_sync", "session_store_cli",
  "session_store_ffi", "uos_swarm@coord", "uos_swarm@board", "uos_swarm_ffi",
  "session_sync_ffi", "esqlite3", "esqlite3_nif", "ecology_capability_ffi",
  "cepaf_gleam@harness@planning_intents", "cepaf_gleam@harness@client_mcp",
  "cepaf_gleam@harness@client_profiles", "cepaf_gleam@harness@client_config",
  "client_config_io", "cepaf_gleam@harness@native_backend",
  "harness_native_backend_ffi",
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
  json.object(
    list.map(control_modules, fn(name) {
      let digest =
        metadata(atom.create(name), atom.create("module_info"), [
          atom.create("md5"),
        ])
        |> bit_array.base16_encode
        |> string.lowercase
      #(name, json.string(digest))
    }),
  )
}

pub fn require(ok: Bool, reason: String) -> Result(Nil, String) {
  case ok {
    True -> Ok(Nil)
    False -> Error(reason)
  }
}

pub fn component(text: String) -> Bool {
  string.byte_size(text) > 0
  && string.byte_size(text) <= 120
  && list.all(string.to_graphemes(text), fn(c) {
    string.contains(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.",
      c,
    )
  })
  && text != "."
  && text != ".."
}

pub fn intent_valid(text: String) -> Bool {
  component(text) && string.byte_size(text) <= 48
}

pub fn digest_valid(text: String) -> Bool {
  string.byte_size(text) == 64
  && list.all(string.to_graphemes(text), fn(c) {
    string.contains("0123456789abcdef", c)
  })
}

pub fn public_path(path: String) -> Bool {
  result.is_ok(files.relative_path(path))
  && !string.contains(path, "/.")
  && !string.contains(string.lowercase(path), "credential")
  && !string.contains(string.lowercase(path), "secret")
  && !string.ends_with(path, ".sqlite3")
  && !string.ends_with(path, ".db")
  && {
    path == "AGENTS.md"
    || list.any(
      [
        "apps/",
        "docs/",
        "formal/",
        "contracts/",
        "governance/",
        "tools/",
        "engines/",
      ],
      fn(p) { string.starts_with(path, p) },
    )
  }
}

fn source_code_path(path: String) -> Bool {
  string.ends_with(path, ".gleam")
  || string.ends_with(path, ".erl")
  || {
    case string.starts_with(path, "engines/") {
      True -> string.ends_with(path, ".ml") || string.ends_with(path, ".mli")
      False -> False
    }
  }
}

pub fn risk_path(path: String) -> Bool {
  result.is_ok(files.relative_path(path))
  && string.starts_with(path, "var/harness/")
  && string.ends_with(path, ".json")
  && !string.contains(path, "/.")
}

pub fn scope_valid(scope: Scope) -> Bool {
  dev.valid_identifier(scope.plan)
  && string.starts_with(scope.plan, "uos/")
  && dev.valid_identifier(scope.task)
  && scope.task != "HARNESSBOOT"
  && list.length(scope.reads) <= 256
  && list.length(scope.writes) <= 128
  && scope.sources != []
  && list.length(scope.sources) <= 128
  && list.all(
    list.append(scope.reads, list.append(scope.writes, scope.sources)),
    public_path,
  )
  && list.all(scope.writes, fn(p) {
    // Source-code writes must be in candidate identity. Data and docs stay
    // on the canonical evidence root.
    case source_code_path(p) {
      True -> list.contains(scope.sources, p)
      False -> string.ends_with(p, ".md") || string.ends_with(p, ".json")
    }
  })
  && scope.tests != []
  && list.length(scope.tests) <= 32
  && list.all(scope.tests, fn(t) {
    component(t) && !string.contains(t, ".") && !string.contains(t, "-")
  })
  && list.length(list.unique(scope.allowed_clients))
  == list.length(scope.allowed_clients)
  && list.all(scope.allowed_clients, fn(client) {
    list.contains(["agy", "gemini", "codex", "claude", "pi"], client)
  })
  && list.length(list.unique(scope.allowed_client_actions))
  == list.length(scope.allowed_client_actions)
  && list.all(scope.allowed_client_actions, fn(action) {
    list.contains(["prepare", "status", "rollback"], action)
  })
  && client_permissions_complete(scope)
  && risk_path(scope.portfolio)
  && string.ends_with(scope.portfolio, "-current-risk.json")
}

fn client_permissions_complete(scope: Scope) -> Bool {
  case scope.allowed_clients, scope.allowed_client_actions {
    [], [] -> True
    [], _ -> False
    _, [] -> False
    _, _ -> True
  }
}

fn scope_decoder() -> decode.Decoder(Scope) {
  use plan <- decode.field("plan", decode.string)
  use task <- decode.field("task", decode.string)
  use reads <- decode.field("read_paths", decode.list(decode.string))
  use writes <- decode.field("write_paths", decode.list(decode.string))
  use sources <- decode.field("source_paths", decode.list(decode.string))
  use tests <- decode.field("test_modules", decode.list(decode.string))
  use portfolio <- decode.field("risk_portfolio", decode.string)
  use clients <- decode.optional_field(
    "allowed_clients",
    [],
    decode.list(decode.string),
  )
  use actions <- decode.optional_field(
    "allowed_client_actions",
    [],
    decode.list(decode.string),
  )
  decode.success(Scope(
    plan,
    task,
    reads,
    writes,
    sources,
    tests,
    portfolio,
    clients,
    actions,
  ))
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
    use workspace <- decode.optional_field("workspace_root", "", decode.string)
    use review <- decode.field("review_path", decode.string)
    use review_hash <- decode.field("review_sha256", decode.string)
    decode.success(#(
      schema,
      role,
      id,
      session,
      worker,
      host,
      boot,
      expiry,
      scopes,
      workspace,
      review,
      review_hash,
    ))
  }
  use fields <- result.try(
    json.parse(body, decoder) |> result.map_error(fn(_) { "grant_decode" }),
  )
  use expiry <- result.try(
    int.parse(fields.7) |> result.map_error(fn(_) { "grant_expiry" }),
  )
  use _ <- result.try(require(
    fields.0 == "uos.harness-development-grant.v1"
      && fields.1 == "development"
      && intent_valid(fields.2)
      && dev.valid_identifier(fields.3)
      && dev.valid_identifier(fields.4)
      && digest_valid(fields.5)
      && dev.valid_identifier(fields.6)
      && fields.8 != []
      && list.length(fields.8) <= 64
      && list.all(fields.8, scope_valid)
      && list.length(
      list.unique(list.map(fields.8, fn(s) { #(s.plan, s.task) })),
    )
      == list.length(fields.8)
      && workspace_locator_valid(fields.9)
      && public_path(fields.10)
      && digest_valid(fields.11)
      && risk_path(path),
    "grant_scope_or_role_refused",
  ))
  Ok(Grant(
    fields.2,
    path,
    files.digest(body),
    fields.3,
    fields.4,
    fields.5,
    fields.6,
    expiry,
    fields.8,
    fields.9,
    fields.10,
    fields.11,
  ))
}

fn workspace_locator_valid(relative: String) -> Bool {
  case relative {
    "" -> True
    _ -> result.is_ok(files.workspace_root(dev.root, relative))
  }
}

/// Legacy grants use the canonical source root. A reviewed candidate grant
/// selects one direct real JJ workspace, resolved again at each use.
pub fn source_root(grant: Grant) -> Result(String, String) {
  case grant.workspace_root {
    "" -> Ok(dev.root)
    relative -> files.workspace_root(dev.root, relative)
  }
}

pub fn workspace_list_args(repository: String) -> List(String) {
  ["--ignore-working-copy", "--repository", repository, "workspace", "list"]
}

pub fn workspace_root_args(repository: String) -> List(String) {
  ["--ignore-working-copy", "--repository", repository, "workspace", "root"]
}

fn registered_workspace(
  relative: String,
  expected_root: String,
) -> Result(Nil, String) {
  case string.split(relative, "/") {
    [".uos-workspaces", _name] -> {
      use listing <- result.try(dev.bounded(
        dev.root <> "/toolchains/nix-profile/bin/jj",
        workspace_list_args(dev.root),
        3000,
      ))
      use actual_root <- result.try(dev.bounded(
        dev.root <> "/toolchains/nix-profile/bin/jj",
        workspace_root_args(expected_root),
        3000,
      ))
      require(
        workspace_identity_matches(
          relative,
          expected_root,
          listing,
          actual_root,
        ),
        "workspace_jj_registration_or_root_identity_mismatch",
      )
    }
    _ -> Error("workspace_path_not_direct_candidate")
  }
}

pub fn workspace_identity_matches(
  relative: String,
  expected_root: String,
  listing: String,
  actual_root: String,
) -> Bool {
  case string.split(relative, "/") {
    [".uos-workspaces", name] -> {
      let line_prefix = name <> ": " <> relative <> " "
      list.any(string.split(listing, "\n"), fn(line) {
        string.starts_with(line, line_prefix)
      })
      && string.trim(actual_root) == expected_root
    }
    _ -> False
  }
}

pub fn grant_budget_valid(
  expires_us: Int,
  now_us: Int,
  required_ms: Int,
) -> Bool {
  now_us >= 0
  && required_ms >= 0
  && required_ms <= 70_000
  && expires_us > now_us + required_ms * 1000
  && expires_us - now_us <= 86_400_000_000
}

pub fn validate_window_for(
  grant: Grant,
  observed: clock.Observation,
  required_ms: Int,
) -> Result(Nil, String) {
  let current = observed.sample.observed
  require(
    grant.host == current.domain.host_id
      && grant.boot == current.domain.boot_id
      && grant_budget_valid(grant.expires_us, current.utc_us, required_ms),
    "grant_host_boot_expiry_or_operation_window",
  )
}

pub fn validate_window(
  grant: Grant,
  observed: clock.Observation,
) -> Result(Nil, String) {
  validate_window_for(grant, observed, 0)
}

pub fn control_ids_match(recorded: value.Value, actual: json.Json) -> Bool {
  case recorded, json.parse(json.to_string(actual), value.decoder()) {
    value.Object(fields), Ok(expected) ->
      list.length(fields) == list.length(control_modules)
      && list.all(control_modules, fn(name) {
        value.get(recorded, name) == value.get(expected, name)
      })
    _, _ -> False
  }
}

// Fails closed on every arm: a missing declaration, a missing file, an
// unreadable file, an invalid digest or a mismatch all refuse admission. An
// unverified dependency is never an admitted one.
pub fn control_dependencies_match(
  recorded: value.Value,
) -> Result(Nil, String) {
  case recorded {
    value.Object(entries) -> {
      use _ <- result.try(require(
        list.length(entries) == list.length(control_dependencies)
          && list.all(control_dependencies, fn(p) {
          result.is_ok(value.get(recorded, p))
        }),
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
        require(
          files.digest(body) == expected,
          "control_dependency_digest_mismatch:" <> rel,
        )
      })
    }
    _ -> Error("control_dependencies_object_required")
  }
}

fn text_field(document: value.Value, key: String) -> Result(String, String) {
  use found <- result.try(value.get(document, key))
  case found {
    value.Text(text) -> Ok(text)
    _ -> Error("review_string_field:" <> key)
  }
}

fn same_object(left: value.Value, right: value.Value) -> Bool {
  case left, right {
    value.Object(a), value.Object(b) ->
      list.length(a) == list.length(b)
      && list.length(list.unique(list.map(a, fn(p) { p.0 }))) == list.length(a)
      && list.length(list.unique(list.map(b, fn(p) { p.0 }))) == list.length(b)
      && list.all(a, fn(p) {
        case value.get(right, p.0) {
          Ok(v) -> same_value(p.1, v)
          Error(_) -> False
        }
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
  list.any(
    [
      "claim_outcome_unknown:",
      "attachment_outcome_unknown:",
      "release_outcome_unknown:",
      "completion_outcome_unknown:",
      "effect_unverified:",
      "reconciliation_outcome_unknown:",
    ],
    fn(prefix) { string.starts_with(reason, prefix) },
  )
  || string.contains(reason, "unknown_effect_outcome")
}

pub fn review_task_matches(
  binding: dev.Binding,
  row: dev.TaskRecord,
  digest: String,
) -> Bool {
  digest_valid(digest)
  && dev.terminal_matches(binding, row, "uos.harness-peer-review.v1:" <> digest)
}

fn check_review_task(
  document: value.Value,
  reviewed: value.Value,
  digest: String,
) -> Result(Nil, String) {
  use expected <- result.try(value.get(document, "review_task"))
  use plan <- result.try(text_field(expected, "plan"))
  use task <- result.try(text_field(expected, "task"))
  use reviewer <- result.try(value.get(reviewed, "reviewer"))
  use actual_plan <- result.try(text_field(reviewer, "plan_id"))
  use actual_task <- result.try(text_field(reviewer, "task_id"))
  use worker <- result.try(text_field(reviewer, "worker"))
  use session <- result.try(text_field(reviewer, "session_id"))
  use attempt <- result.try(value.get(reviewer, "attempt"))
  use attempt <- result.try(case attempt {
    value.Integer(n) if n > 0 -> Ok(n)
    _ -> Error("review_attempt")
  })
  use grant_worker <- result.try(text_field(document, "worker"))
  use _ <- result.try(require(
    dev.valid_identifier(plan)
      && string.starts_with(plan, "uos/")
      && dev.valid_identifier(task)
      && task != "HARNESSBOOT"
      && actual_plan == plan
      && actual_task == task
      && component(worker)
      && worker != grant_worker,
    "review_task_binding",
  ))
  let binding =
    dev.Binding("development", plan, task, worker, attempt, session, 1)
  use row <- result.try(dev.read_task(binding))
  require(
    review_task_matches(binding, row, digest),
    "canonical_review_completion_digest",
  )
}

pub fn validate_review(
  document: value.Value,
  reviewed: value.Value,
  proposal: value.Value,
) -> Result(Nil, String) {
  use _ <- result.try(require(
    value.get(reviewed, "schema")
      == Ok(value.Text("uos.harness-successor-grant-review.v1")),
    "review_schema",
  ))
  use _ <- result.try(require(
    value.get(reviewed, "verdict") == Ok(value.Text("APPROVE_DEV_TEST_SCOPE")),
    "review_verdict",
  ))
  use proposal_path <- result.try(text_field(document, "proposal_path"))
  use proposal_hash <- result.try(text_field(document, "proposal_sha256"))
  use review_hash <- result.try(value.get(document, "review_sha256"))
  use _ <- result.try(require(
    risk_path(proposal_path) && digest_valid(proposal_hash),
    "review_proposal_reference",
  ))
  use binding <- result.try(value.get(reviewed, "grant_proposal"))
  use _ <- result.try(
    list.try_each(
      [
        #("path", value.Text(proposal_path)),
        #("sha256", value.Text(proposal_hash)),
      ],
      fn(pair) {
        require(
          value.get(binding, pair.0) == Ok(pair.1),
          "review_proposal_binding",
        )
      },
    ),
  )
  use _ <- result.try(
    list.try_each(
      [
        #("grant_id", "grant_id"),
        #("target_session", "session"),
        #("target_worker", "worker"),
      ],
      fn(pair) {
        use expected <- result.try(text_field(document, pair.1))
        require(
          value.get(binding, pair.0) == Ok(value.Text(expected)),
          "review_identity_binding",
        )
      },
    ),
  )
  use reviewer <- result.try(value.get(reviewed, "reviewer"))
  use peer_session <- result.try(text_field(reviewer, "session_id"))
  use session <- result.try(text_field(document, "session"))
  use _ <- result.try(require(
    component(peer_session) && peer_session != session,
    "independent_review_session_required",
  ))
  // The launcher may bind the review hash and immutable proposal reference.
  // Every other grant field must remain exactly as the peer reviewed it.
  let expected =
    proposal
    |> value.set("review_sha256", review_hash)
    |> value.set("proposal_path", value.Text(proposal_path))
    |> value.set("proposal_sha256", value.Text(proposal_hash))
  let differing = case document {
    value.Object(fields) ->
      list.find(fields, fn(p) {
        case value.get(expected, p.0) {
          Ok(v) -> !same_value(p.1, v)
          Error(_) -> True
        }
      })
      |> result.map(fn(p) { p.0 })
      |> result.unwrap("object_shape_or_duplicate_key")
    _ -> "object_shape"
  }
  require(
    same_object(document, expected),
    "grant_differs_from_reviewed_proposal:$." <> differing,
  )
}

pub fn check(grant: Grant) -> Result(clock.Observation, String) {
  use body <- result.try(files.read(dev.root, grant.path))
  use _ <- result.try(require(
    files.digest(body) == grant.digest,
    "grant_changed",
  ))
  use reviewed <- result.try(files.read(dev.root, grant.review_path))
  use _ <- result.try(require(
    files.digest(reviewed) == grant.review_sha256,
    "review_changed",
  ))
  use document <- result.try(
    json.parse(body, value.decoder())
    |> result.map_error(fn(_) { "grant_json" }),
  )
  use review_document <- result.try(
    json.parse(reviewed, value.decoder())
    |> result.map_error(fn(_) { "review_json" }),
  )
  use _ <- result.try(require(
    value.get(review_document, "verdict")
      == Ok(value.Text("APPROVE_DEV_TEST_SCOPE")),
    "review_verdict",
  ))
  use proposal_path <- result.try(text_field(document, "proposal_path"))
  use proposal_hash <- result.try(text_field(document, "proposal_sha256"))
  use _ <- result.try(require(
    risk_path(proposal_path)
      && proposal_path != grant.path
      && digest_valid(proposal_hash),
    "proposal_reference",
  ))
  use proposal_body <- result.try(files.read(dev.root, proposal_path))
  use _ <- result.try(require(
    files.digest(proposal_body) == proposal_hash,
    "proposal_changed",
  ))
  use proposal <- result.try(
    json.parse(proposal_body, value.decoder())
    |> result.map_error(fn(_) { "proposal_json" }),
  )
  use _ <- result.try(validate_review(document, review_document, proposal))
  use _ <- result.try(check_review_task(
    document,
    review_document,
    grant.review_sha256,
  ))
  use recorded <- result.try(value.get(document, "loaded_control_ids"))
  use _ <- result.try(require(
    control_ids_match(recorded, control_ids()),
    "loaded_control_identity_mismatch",
  ))
  use recorded_dependencies <- result.try(value.get(
    document,
    "control_dependencies",
  ))
  use _ <- result.try(control_dependencies_match(recorded_dependencies))
  use _ <- result.try(case grant.workspace_root {
    "" -> Ok(Nil)
    relative -> {
      use root <- result.try(source_root(grant))
      registered_workspace(relative, root)
    }
  })
  use now <- result.try(clock.observe())
  use _ <- result.try(validate_window(grant, now))
  Ok(now)
}

pub fn load_with(path: String, expected: String) -> Result(Grant, String) {
  use body <- result.try(files.read(dev.root, path))
  use _ <- result.try(require(
    digest_valid(expected) && files.digest(body) == expected,
    "launcher_grant_digest",
  ))
  use grant <- result.try(decode_grant(path, body))
  use _ <- result.try(check(grant))
  Ok(grant)
}

fn load_active_pointer(primary_error: String) -> Result(Grant, String) {
  let pointer_decoder = {
    use path <- decode.field("path", decode.string)
    use expected <- decode.field("sha256", decode.string)
    decode.success(#(path, expected))
  }
  case files.read(dev.root, "var/harness/active-live-grant.json") {
    Error(_) -> Error(primary_error)
    Ok(raw) ->
      case json.parse(raw, pointer_decoder) {
        Error(_) -> Error(primary_error)
        Ok(#(path, expected)) ->
          case load_with(path, expected) {
            Ok(grant) -> Ok(grant)
            Error(_) -> Error(primary_error)
          }
      }
  }
}

pub fn load() -> Result(Grant, String) {
  use path <- result.try(
    get_env("UOS_HARNESS_GRANT_PATH")
    |> result.map_error(fn(_) { "grant_path_missing" }),
  )
  use expected <- result.try(
    get_env("UOS_HARNESS_GRANT_SHA256")
    |> result.map_error(fn(_) { "grant_digest_missing" }),
  )
  case load_with(path, expected) {
    Ok(grant) -> Ok(grant)
    Error(primary_error) -> load_active_pointer(primary_error)
  }
}

pub fn lookup(
  grant: Grant,
  plan: String,
  task: String,
) -> Result(Scope, String) {
  list.find(grant.scopes, fn(s) { s.plan == plan && s.task == task })
  |> result.map_error(fn(_) { "task_not_in_reviewed_grant" })
}

pub fn coordinate(args: List(String)) -> Result(String, String) {
  dev.bounded_observation(fn() { session_authority.run(args) }, 3000)
}

pub fn heartbeat(grant: Grant) -> Result(json.Json, String) {
  use now <- result.try(check(grant))
  use revision <- result.try(dev.bounded(
    dev.root <> "/toolchains/nix-profile/bin/jj",
    [
      "--ignore-working-copy",
      "--repository",
      dev.root,
      "log",
      "-r",
      "@",
      "--no-graph",
      "-T",
      "commit_id",
    ],
    3000,
  ))
  use raw <- result.try(
    coordinate([
      "heartbeat",
      grant.session,
      string.trim(revision),
      "successor-grant:" <> grant.id,
      "successor-heartbeat-" <> int.to_string(now.sample.observed.utc_us),
    ]),
  )
  json.parse(raw, value.decoder())
  |> result.map(value.encode)
  |> result.map_error(fn(_) { "heartbeat_json" })
}

pub fn read_optional(path: String) -> Result(Option(String), String) {
  use absolute <- result.try(files.checked_path(dev.root, path))
  case simplifile.link_info(absolute) {
    Error(simplifile.Enoent) -> Ok(None)
    Error(_) -> Error("artifact_stat_failed")
    Ok(_) -> files.read(dev.root, path) |> result.map(Some)
  }
}

pub fn risk_check(
  path: String,
  scope: Scope,
  worker: String,
  attempt: Int,
  active: Bool,
) -> Result(String, String) {
  use _ <- result.try(require(risk_path(path), "risk_path_refused"))
  let mode = case active {
    True -> [
      "--active-check",
      dev.root <> "/" <> path,
      scope.task,
      worker,
      int.to_string(attempt),
    ]
    False -> ["--preflight", dev.root <> "/" <> path, scope.task]
  }
  use raw <- result.try(dev.bounded(
    dev.root <> "/toolchains/nix-profile/bin/env",
    [
      "PATH="
        <> dev.root
        <> "/toolchains/nix-profile/bin:"
        <> dev.root
        <> "/toolchains/opam-ocaml/bin:/usr/bin:/bin",
      "OPAM_SWITCH_PREFIX=" <> dev.root <> "/toolchains/opam-ocaml",
      "/usr/bin/bash",
      dev.root <> "/tools/risk-priority-check",
      ..mode
    ],
    15_000,
  ))
  use parsed <- result.try(
    json.parse(raw, value.decoder()) |> result.map_error(fn(_) { "risk_json" }),
  )
  use status <- result.try(value.get(parsed, "status"))
  let expected = case active {
    True -> "ACTIVE_OBSERVATION_PASS"
    False -> "PREFLIGHT_PASS"
  }
  use _ <- result.try(require(status == value.Text(expected), "risk_hold"))
  Ok(raw)
}

pub fn assessment_lock_path_for(root: String, portfolio: String) -> String {
  "var/harness/assessment-path-lock-"
  <> files.digest(root <> "\u{0}" <> portfolio)
  <> ".json"
}

pub fn assessment_path_lock_path(portfolio: String) -> String {
  assessment_lock_path_for(dev.root, portfolio)
}

/// Serialize every writer of one assessment portfolio with the same durable
/// SQLite coordinator critical section. The callback must only perform the
/// bounded target lock/read/write work; it must not call coordinator APIs.
pub fn with_assessment_portfolio_lock(
  portfolio: String,
  operation_id: String,
  body: fn() -> Result(a, String),
) -> Result(a, String) {
  with_assessment_portfolio_lock_at(
    dev.root,
    session_authority.database,
    portfolio,
    operation_id,
    body,
  )
}

/// Testable production serialization seam. Production delegates with the
/// verified canonical coordinator path and source root; tests use a private
/// verified coordinator fixture and disposable root.
pub fn with_assessment_portfolio_lock_at(
  root: String,
  database: String,
  portfolio: String,
  operation_id: String,
  body: fn() -> Result(a, String),
) -> Result(a, String) {
  let path_key =
    "harness-assessment/" <> files.digest(root <> "\u{0}" <> portfolio)
  use section <- result.try(session_store.critical_section(
    path_key,
    operation_id,
  ))
  use opened <- result.try(
    session_store.open_existing(database)
    |> result.map_error(session_store.error_to_string),
  )
  let outcome =
    session_store.with_critical_section(
      opened,
      section,
      fn(_state, _boot, _now) { body() },
    )
  let closed = session_store.close(opened)
  use value <- result.try(
    outcome |> result.map_error(session_store.error_to_string),
  )
  use _ <- result.try(closed |> result.map_error(session_store.error_to_string))
  Ok(value)
}

pub fn state_assessment(
  execution: Execution,
  state: String,
  suffix: String,
) -> Result(String, String) {
  state_assessment_with_owner(execution, state, suffix, None)
}

fn state_assessment_with_owner(
  execution: Execution,
  state: String,
  suffix: String,
  owner_lock: Option(String),
) -> Result(String, String) {
  with_assessment_portfolio_lock(
    execution.scope.portfolio,
    "state-assessment-" <> suffix,
    fn() {
      use lock <- result.try(files.read_optional(
        dev.root,
        assessment_path_lock_path(execution.scope.portfolio),
      ))
      let lock_allowed = case lock, owner_lock {
        None, None -> True
        Some(raw), Some(expected) -> raw == expected
        _, _ -> False
      }
      use _ <- result.try(require(lock_allowed, "assessment_prepared_stop_line"))
      use body <- result.try(files.read(dev.root, execution.risk_path))
      use parsed <- result.try(
        json.parse(body, value.decoder())
        |> result.map_error(fn(_) { "risk_json" }),
      )
      use records <- result.try(case parsed {
        value.Array(xs) -> Ok(xs)
        _ -> Error("risk_array")
      })
      let changed =
        list.map(records, fn(record) {
          assessment_record_state(
            record,
            execution.scope.plan,
            execution.scope.task,
            state,
            execution.binding.worker,
          )
        })
      let updated = value.encode(value.Array(changed)) |> json.to_string
      let path =
        "var/harness/" <> execution.grant.id <> "-" <> suffix <> "-risk.json"
      use _ <- result.try(files.create(dev.root, path, updated))
      use original <- result.try(files.read(dev.root, execution.scope.portfolio))
      use _ <- result.try(files.create(
        dev.root,
        path <> ".before.json",
        original,
      ))
      use _ <- result.try(files.replace(
        dev.root,
        execution.scope.portfolio,
        files.digest(original),
        updated,
      ))
      Ok(execution.scope.portfolio)
    },
  )
}

/// Bind an active assessment to the worker Sa-plan actually assigned after a
/// successful claim. Planning-time actor estimates are not post-claim identity.
pub fn assessment_record_state(
  record: value.Value,
  plan: String,
  task: String,
  state: String,
  worker: String,
) -> value.Value {
  case value.get(record, "plan_id"), value.get(record, "task_id") {
    Ok(value.Text(actual_plan)), Ok(value.Text(actual_task))
      if actual_plan == plan && actual_task == task
    -> {
      let updated = value.set(record, "task_state", value.Text(state))
      case state {
        "executing" -> value.set(updated, "actor", value.Text(worker))
        _ -> updated
      }
    }
    _, _ -> record
  }
}

fn task_transition_lock_record(
  grant: Grant,
  scope: Scope,
  intent: String,
  signature: String,
) -> String {
  json.object([
    #("schema", json.string("uos.harness-assessment-path-lock.v1")),
    #("state", json.string("HELD")),
    #("canonical_root", json.string(dev.root)),
    #("portfolio_path", json.string(scope.portfolio)),
    #("plan", json.string(scope.plan)),
    #("task", json.string(scope.task)),
    #("grant_sha256", json.string(grant.digest)),
    #("worker", json.string(grant.worker)),
    #("intent_id", json.string(intent)),
    #("request_signature", json.string(signature)),
  ])
  |> json.to_string
}

fn acquire_task_transition_lock(
  grant: Grant,
  scope: Scope,
  intent: String,
) -> Result(String, String) {
  let signature =
    files.digest(
      grant.digest
      <> "\u{0}"
      <> scope.plan
      <> "\u{0}"
      <> scope.task
      <> "\u{0}"
      <> intent
      <> "\u{0}task_transition",
    )
  let record = task_transition_lock_record(grant, scope, intent, signature)
  with_assessment_portfolio_lock(
    scope.portfolio,
    "transition-acquire-" <> intent,
    fn() {
      use existing <- result.try(files.read_optional(
        dev.root,
        assessment_path_lock_path(scope.portfolio),
      ))
      use _ <- result.try(require(
        existing == None,
        "assessment_prepared_stop_line",
      ))
      use _ <- result.try(
        files.create(
          dev.root,
          assessment_path_lock_path(scope.portfolio),
          record,
        )
        |> result.map_error(fn(_) { "assessment_path_lock_held_or_unavailable" }),
      )
      Ok(record)
    },
  )
}

fn release_task_transition_lock(
  scope: Scope,
  intent: String,
  record: String,
) -> Result(Nil, String) {
  with_assessment_portfolio_lock(
    scope.portfolio,
    "transition-release-" <> intent,
    fn() {
      let path = assessment_path_lock_path(scope.portfolio)
      use current <- result.try(files.read_optional(dev.root, path))
      use _ <- result.try(require(
        current == Some(record),
        "assessment_path_lock_owner_mismatch",
      ))
      simplifile.delete_file(dev.root <> "/" <> path)
      |> result.map_error(fn(_) { "assessment_path_lock_release_failed" })
    },
  )
}

pub fn attach(
  grant: Grant,
  scope: Scope,
  intent: String,
) -> Result(Execution, String) {
  use _ <- result.try(require(intent_valid(intent), "intent_id"))
  use now <- result.try(check(grant))
  use _ <- result.try(validate_window_for(grant, now, 70_000))
  use _ <- result.try(heartbeat(grant))
  let base =
    dev.Binding(
      "development",
      scope.plan,
      scope.task,
      grant.worker,
      1,
      grant.session,
      1,
    )
  use row <- result.try(dev.read_task(base))
  use _ <- result.try(require(
    row.state == "executing"
      && row.worker == Some(grant.worker)
      && row.attempt > 0,
    "attach_requires_current_owned_attempt",
  ))
  use transition_lock <- result.try(acquire_task_transition_lock(
    grant,
    scope,
    intent,
  ))
  let outcome = {
    let preliminary =
      Execution(
        grant,
        scope,
        dev.Binding(..base, attempt: row.attempt),
        scope.portfolio,
      )
    use current_risk <- result.try(state_assessment_with_owner(
      preliminary,
      "executing",
      intent <> "-attach",
      Some(transition_lock),
    ))
    use _ <- result.try(risk_check(
      current_risk,
      scope,
      grant.worker,
      row.attempt,
      True,
    ))
    use raw <- result.try(
      coordinate([
        "claim",
        grant.session,
        dev.task_resource(base),
        "3600",
        grant.id <> "-" <> intent <> "-coordinate",
      ]),
    )
    use epoch <- result.try(
      json.parse(raw, decode.field("epoch", decode.int, decode.success))
      |> result.map_error(fn(_) { "coordinator_claim_outcome_unknown" }),
    )
    let active =
      Execution(
        ..preliminary,
        binding: dev.Binding(..base, attempt: row.attempt, epoch: epoch),
      )
    use _ <- result.try(fence(active, 0))
    use _ <- result.try(release_task_transition_lock(
      scope,
      intent,
      transition_lock,
    ))
    Ok(active)
  }
  result.map_error(outcome, fn(e) { "attachment_outcome_unknown:" <> e })
}

pub fn claim(
  grant: Grant,
  scope: Scope,
  intent: String,
) -> Result(Execution, String) {
  use _ <- result.try(require(intent_valid(intent), "intent_id"))
  use now <- result.try(check(grant))
  use _ <- result.try(validate_window_for(grant, now, 70_000))
  use _ <- result.try(heartbeat(grant))
  use _ <- result.try(risk_check(scope.portfolio, scope, grant.worker, 0, False))
  let begin_path =
    "var/harness/" <> grant.id <> "-" <> intent <> "-claim-intent.json"
  let body =
    json.object([
      #("plan", json.string(scope.plan)),
      #("task", json.string(scope.task)),
      #("worker", json.string(grant.worker)),
      #("grant_sha256", json.string(grant.digest)),
    ])
    |> json.to_string
  // Once an intent may exist, only explicit ownership reconciliation can resume.
  use _ <- result.try(
    files.create(dev.root, begin_path, body)
    |> result.map_error(fn(e) { "claim_outcome_unknown:intent:" <> e }),
  )
  use transition_lock <- result.try(acquire_task_transition_lock(
    grant,
    scope,
    intent,
  ))
  let outcome = {
    use _ <- result.try(
      sa.run_sa_plan_cli([
        "task",
        "claim",
        grant.worker,
        scope.plan,
        "3600000000000",
        scope.task,
      ]),
    )
    let base =
      dev.Binding(
        "development",
        scope.plan,
        scope.task,
        grant.worker,
        1,
        grant.session,
        1,
      )
    use row <- result.try(dev.read_task(base))
    use _ <- result.try(require(
      row.state == "executing" && row.worker == Some(grant.worker),
      "claim_outcome_unknown",
    ))
    let interim =
      Execution(
        grant,
        scope,
        dev.Binding(..base, attempt: row.attempt),
        scope.portfolio,
      )
    use risk <- result.try(state_assessment_with_owner(
      interim,
      "executing",
      intent,
      Some(transition_lock),
    ))
    use _ <- result.try(risk_check(risk, scope, grant.worker, row.attempt, True))
    use raw <- result.try(
      coordinate([
        "claim",
        grant.session,
        dev.task_resource(base),
        "3600",
        grant.id <> "-" <> intent <> "-coordinate",
      ]),
    )
    use epoch <- result.try(
      json.parse(raw, decode.field("epoch", decode.int, decode.success))
      |> result.map_error(fn(_) { "coordinator_claim_outcome_unknown" }),
    )
    let active =
      Execution(
        ..interim,
        risk_path: risk,
        binding: dev.Binding(..interim.binding, epoch: epoch),
      )
    use _ <- result.try(fence(active, 0))
    use _ <- result.try(release_task_transition_lock(
      scope,
      intent,
      transition_lock,
    ))
    Ok(active)
  }
  result.map_error(outcome, fn(e) { "claim_outcome_unknown:" <> e })
}

pub fn fence(
  execution: Execution,
  duration_ms: Int,
) -> Result(dev.Fence, String) {
  use _ <- result.try(require(
    duration_ms >= 0 && duration_ms <= 65_000,
    "operation_window_bound",
  ))
  use _ <- result.try(check(execution.grant))
  use proof <- result.try(dev.fence_for(execution.binding, duration_ms + 5000))
  use _ <- result.try(validate_window_for(
    execution.grant,
    proof.clock,
    duration_ms + 5000,
  ))
  Ok(proof)
}

fn recovery_closed(v: value.Value, names: List(String)) -> Result(Nil, String) {
  case v {
    value.Object(fs) ->
      require(
        list.length(fs) == list.length(names)
          && list.length(list.unique(list.map(fs, fn(f) { f.0 })))
          == list.length(fs)
          && list.all(fs, fn(f) { list.contains(names, f.0) }),
        "recovery_closed_fields",
      )
    _ -> Error("recovery_object_required")
  }
}

fn recovery_parse(raw: String) -> Result(value.Value, String) {
  use _ <- result.try(require(
    string.byte_size(raw) > 0 && string.byte_size(raw) <= files.max_bytes,
    "recovery_json_bound",
  ))
  json_guard.native_inspect(raw, 32)
  |> result.map_error(fn(_) { "recovery_strict_json" })
}

fn recovery_integer(v: value.Value, key: String) -> Result(Int, String) {
  use found <- result.try(value.get(v, key))
  case found {
    value.Integer(n) -> Ok(n)
    _ -> Error("recovery_integer:" <> key)
  }
}

fn recovery_array(
  v: value.Value,
  key: String,
  maximum: Int,
) -> Result(List(value.Value), String) {
  use found <- result.try(value.get(v, key))
  case found {
    value.Array(xs) -> {
      use _ <- result.try(require(
        list.length(xs) <= maximum,
        "recovery_array_bound",
      ))
      Ok(xs)
    }
    _ -> Error("recovery_array:" <> key)
  }
}

fn recovery_decimal(v: value.Value, key: String) -> Result(Int, String) {
  use raw <- result.try(text_field(v, key))
  use n <- result.try(
    int.parse(raw) |> result.map_error(fn(_) { "recovery_decimal" }),
  )
  use _ <- result.try(require(
    n > 0 && n <= 9_000_000_000_000_000_000 && int.to_string(n) == raw,
    "recovery_decimal_bound",
  ))
  Ok(n)
}

fn recovery_binding(v: value.Value) -> Result(RecoveryOldClaim, String) {
  use _ <- result.try(
    recovery_closed(v, ["task_id", "worker", "attempt", "lease_until_ns"]),
  )
  use task <- result.try(text_field(v, "task_id"))
  use worker <- result.try(text_field(v, "worker"))
  use attempt <- result.try(recovery_integer(v, "attempt"))
  use lease <- result.try(recovery_decimal(v, "lease_until_ns"))
  use _ <- result.try(require(
    dev.valid_identifier(task)
      && component(worker)
      && attempt > 0
      && attempt < 1_000_000,
    "recovery_old_binding",
  ))
  Ok(RecoveryOldClaim(task, worker, attempt, lease))
}

fn recovery_binding_json(b: RecoveryOldClaim) -> json.Json {
  json.object([
    #("task_id", json.string(b.task)),
    #("worker", json.string(b.worker)),
    #("attempt", json.int(b.attempt)),
    #("lease_until_ns", json.string(int.to_string(b.lease_ns))),
  ])
}

/// DATA parser only. Calling this does not authenticate a review or authorize a
/// claim. The effectful preparation branch independently loads/checks a grant,
/// observes its canonical review task and reruns the existing checker.
pub fn recovery_proposal_data(
  raw: String,
) -> Result(RecoveryProposalData, String) {
  use p <- result.try(recovery_parse(raw))
  use _ <- result.try(
    recovery_closed(p, [
      "schema", "plan_id", "selected_task", "target_worker", "snapshot_sha256",
      "assessment_sha256", "source_manifest_sha256", "bindings",
      "selection_review",
    ]),
  )
  use plan <- result.try(text_field(p, "plan_id"))
  use task <- result.try(text_field(p, "selected_task"))
  use worker <- result.try(text_field(p, "target_worker"))
  use snapshot <- result.try(text_field(p, "snapshot_sha256"))
  use assessment <- result.try(text_field(p, "assessment_sha256"))
  use source <- result.try(text_field(p, "source_manifest_sha256"))
  use rows <- result.try(recovery_array(p, "bindings", 1000))
  use bindings <- result.try(list.try_map(rows, recovery_binding))
  use selection <- result.try(value.get(p, "selection_review"))
  use _ <- result.try(case selection {
    value.Null -> Ok(Nil)
    _ -> {
      use _ <- result.try(
        recovery_closed(selection, [
          "path",
          "sha256",
          "proof_path",
          "proof_sha256",
        ]),
      )
      use path <- result.try(text_field(selection, "path"))
      use proof <- result.try(text_field(selection, "proof_path"))
      use digest <- result.try(text_field(selection, "sha256"))
      use proof_digest <- result.try(text_field(selection, "proof_sha256"))
      require(
        public_path(path)
          && public_path(proof)
          && digest_valid(digest)
          && digest_valid(proof_digest),
        "recovery_selection_reference",
      )
    }
  })
  use _ <- result.try(require(
    value.get(p, "schema")
      == Ok(value.Text("uos.harness-reviewed-recovery-proposal.v1"))
      && dev.valid_identifier(plan)
      && string.starts_with(plan, "uos/")
      && dev.valid_identifier(task)
      && task != "HARNESSBOOT"
      && component(worker)
      && digest_valid(snapshot)
      && digest_valid(assessment)
      && digest_valid(source)
      && bindings != []
      && list.length(list.unique(list.map(bindings, fn(b) { b.task })))
      == list.length(bindings)
      && bindings
      == list.sort(bindings, fn(a, b) { string.compare(a.task, b.task) })
      && list.any(bindings, fn(b) { b.task == task && b.worker == worker }),
    "recovery_proposal_scope",
  ))
  Ok(RecoveryProposalData(
    plan,
    task,
    worker,
    snapshot,
    assessment,
    source,
    bindings,
    selection,
  ))
}

fn recovery_snapshot_row(v: value.Value) -> Result(value.Value, String) {
  let keys = [
    "task_id",
    "state",
    "worker",
    "lease_until_ns",
    "attempt",
    "completed_at_ns",
    "result_present",
    "dependencies",
  ]
  use _ <- result.try(recovery_closed(v, keys))
  use id <- result.try(text_field(v, "task_id"))
  use state <- result.try(text_field(v, "state"))
  use attempt <- result.try(recovery_integer(v, "attempt"))
  use deps <- result.try(recovery_array(v, "dependencies", 10_000))
  use _ <- result.try(require(
    dev.valid_identifier(id)
      && list.contains(
      ["available", "executing", "completed", "failed", "cancelled", "blocked"],
      state,
    )
      && attempt >= 0
      && attempt <= 1_000_000,
    "recovery_snapshot_scalar",
  ))
  use worker <- result.try(value.get(v, "worker"))
  use _ <- result.try(case worker {
    value.Null -> Ok(Nil)
    value.Text(w) -> require(component(w), "recovery_snapshot_worker")
    _ -> Error("recovery_snapshot_worker")
  })
  use _ <- result.try(
    list.try_each(["lease_until_ns", "completed_at_ns"], fn(key) {
      use x <- result.try(value.get(v, key))
      case x {
        value.Null -> Ok(Nil)
        _ -> recovery_decimal(v, key) |> result.map(fn(_) { Nil })
      }
    }),
  )
  use _ <- result.try(case value.get(v, "result_present") {
    Ok(value.Boolean(_)) -> Ok(Nil)
    _ -> Error("recovery_snapshot_result")
  })
  use _ <- result.try(
    list.try_each(deps, fn(d) {
      case d {
        value.Text(x) -> require(dev.valid_identifier(x), "recovery_dependency")
        _ -> Error("recovery_dependency")
      }
    }),
  )
  use ordered <- result.try(
    list.try_map(keys, fn(k) {
      use x <- result.try(value.get(v, k))
      Ok(#(k, x))
    }),
  )
  Ok(value.Object(ordered))
}

/// Strict binding of an observation, NOT authentication. Only actual checker
/// output obtained by prepare_reviewed_recovery has process provenance.
pub fn recovery_bind_observation_data(
  p: RecoveryProposalData,
  raw: String,
  observed_now_ns: Int,
) -> Result(RecoveryObservationData, String) {
  use report <- result.try(recovery_parse(raw))
  use _ <- result.try(
    recovery_closed(report, [
      "status", "authority", "runtime_admission", "reclaim", "observed_at",
      "completed_at", "elapsed_monotonic_seconds", "clock_start", "clock_end",
      "assessment_sha256", "selection_review", "evidence_files_checked",
      "sa_plan", "order", "findings", "limits",
    ]),
  )
  use _ <- result.try(require(
    observed_now_ns > 0
      && observed_now_ns <= 9_000_000_000_000_000_000
      && value.get(report, "status") == Ok(value.Text("RECLAIM_PREFLIGHT_PASS"))
      && value.get(report, "authority") == Ok(value.Text("NONE"))
      && value.get(report, "runtime_admission") == Ok(value.Text("NOT_GRANTED"))
      && value.get(report, "findings") == Ok(value.Array([]))
      && value.get(report, "assessment_sha256")
      == Ok(value.Text(p.assessment_sha256)),
    "recovery_checker_hold",
  ))
  use live <- result.try(value.get(report, "sa_plan"))
  use _ <- result.try(
    recovery_closed(live, [
      "plan_id",
      "snapshot_sha256",
      "tasks",
      "mode",
      "lease_fencing_authority",
    ]),
  )
  use _ <- result.try(require(
    value.get(live, "plan_id") == Ok(value.Text(p.plan))
      && value.get(live, "snapshot_sha256") == Ok(value.Text(p.snapshot_sha256))
      && value.get(live, "mode") == Ok(value.Text("READONLY"))
      && value.get(live, "lease_fencing_authority")
      == Ok(value.Text("NOT_GRANTED")),
    "recovery_snapshot_binding",
  ))
  use raw_rows <- result.try(recovery_array(live, "tasks", 1000))
  use rows <- result.try(list.try_map(raw_rows, recovery_snapshot_row))
  use ids <- result.try(
    list.try_map(rows, fn(row) { text_field(row, "task_id") }),
  )
  use _ <- result.try(require(
    rows != []
      && ids == list.sort(ids, string.compare)
      && list.unique(ids) == ids
      && files.digest(json.to_string(value.encode(value.Array(rows))))
      == p.snapshot_sha256,
    "recovery_snapshot_bytes",
  ))
  use expired <- result.try(
    list.try_map(rows, fn(row) {
      use id <- result.try(text_field(row, "task_id"))
      case value.get(row, "state") {
        Ok(value.Text("executing")) -> {
          use lease <- result.try(recovery_decimal(row, "lease_until_ns"))
          case lease <= observed_now_ns {
            False -> Ok(None)
            True -> {
              use worker <- result.try(text_field(row, "worker"))
              use attempt <- result.try(recovery_integer(row, "attempt"))
              use _ <- result.try(require(
                component(worker)
                  && attempt > 0
                  && attempt < 1_000_000
                  && value.get(row, "completed_at_ns") == Ok(value.Null)
                  && value.get(row, "result_present")
                  == Ok(value.Boolean(False)),
                "recovery_expired_tuple",
              ))
              Ok(Some(RecoveryOldClaim(id, worker, attempt, lease)))
            }
          }
        }
        _ -> Ok(None)
      }
    }),
  )
  let expired =
    list.filter_map(expired, fn(x) {
      case x {
        Some(b) -> Ok(b)
        None -> Error(Nil)
      }
    })
    |> list.sort(fn(a, b) { string.compare(a.task, b.task) })
  use _ <- result.try(require(
    expired == p.bindings,
    "recovery_complete_expired_set",
  ))
  use reclaim <- result.try(value.get(report, "reclaim"))
  use _ <- result.try(
    recovery_closed(reclaim, ["plan_id", "bindings", "scope"]),
  )
  use actual <- result.try(value.get(reclaim, "bindings"))
  let expected =
    json.array(p.bindings, fn(b) {
      json.object([
        #("task_id", json.string(b.task)),
        #("worker", json.string(b.worker)),
        #("previous_attempt", json.int(b.attempt)),
        #("previous_lease_until_ns", json.string(int.to_string(b.lease_ns))),
        #("expected_new_attempt", json.int(b.attempt + 1)),
      ])
    })
    |> json.to_string
  use expected <- result.try(recovery_parse(expected))
  use _ <- result.try(require(
    value.get(reclaim, "plan_id") == Ok(value.Text(p.plan))
      && same_value(actual, expected),
    "recovery_report_old_set",
  ))
  use order <- result.try(recovery_array(report, "order", 1000))
  use _ <- result.try(case order {
    [first, ..] ->
      require(
        value.get(first, "task_id") == Ok(value.Text(p.selected_task)),
        "recovery_selection_changed",
      )
    _ -> Error("recovery_selection_missing")
  })
  use selection <- result.try(value.get(report, "selection_review"))
  use _ <- result.try(case p.selection_review {
    value.Null ->
      require(selection == value.Null, "recovery_selection_unexpected")
    value.Object(fields) -> {
      use _ <- result.try(require(
        value.get(selection, "reviewer_authenticated")
          == Ok(value.Boolean(False)),
        "recovery_selection_identity_not_authenticated",
      ))
      list.try_each(fields, fn(pair) {
        require(
          value.get(selection, pair.0) == Ok(pair.1),
          "recovery_selection_changed",
        )
      })
    }
    _ -> Error("recovery_selection_invalid")
  })
  Ok(RecoveryObservationData(p, files.digest(raw)))
}

pub fn recovery_observation_json(data: RecoveryObservationData) -> json.Json {
  json.object([
    #("status", json.string("BOUND_OBSERVATION_DATA_ONLY")),
    #("authority", json.string("NONE")),
    #("plan", json.string(data.proposal.plan)),
    #("task", json.string(data.proposal.selected_task)),
    #("snapshot_sha256", json.string(data.proposal.snapshot_sha256)),
    #("assessment_sha256", json.string(data.proposal.assessment_sha256)),
    #("report_sha256", json.string(data.report_sha256)),
    #("effect_authority", json.bool(False)),
    #("production_admission", json.bool(False)),
  ])
}

fn recovery_source_manifest(
  grant: Grant,
  scope: Scope,
) -> Result(String, String) {
  use root <- result.try(source_root(grant))
  use sources <- result.try(
    list.try_map(list.sort(scope.sources, string.compare), fn(path) {
      use bytes <- result.try(files.read(root, path))
      Ok(dev.SourceDigest(path, files.digest(bytes)))
    }),
  )
  Ok(dev.manifest_digest(sources))
}

/// DATA-only delegation check. The caller must first authenticate the complete
/// grant document through check/load_with. Session IDs remain labels: canonical
/// task completion authenticates the recorded worker/attempt, not session IAM.
pub fn recovery_review_read_delegated(
  document: value.Value,
  reviewer: value.Value,
  target_plan: String,
  target_task: String,
) -> Result(Nil, String) {
  use allowed <- result.try(recovery_array(
    document,
    "recovery_review_tasks",
    16,
  ))
  use _ <- result.try(
    list.try_each(allowed, fn(entry) {
      use _ <- result.try(
        recovery_closed(entry, ["target_plan", "target_task", "reviewer"]),
      )
      use plan <- result.try(text_field(entry, "target_plan"))
      use task <- result.try(text_field(entry, "target_task"))
      use r <- result.try(value.get(entry, "reviewer"))
      use _ <- result.try(
        recovery_closed(r, [
          "plan_id", "task_id", "worker", "session_id", "attempt",
        ]),
      )
      use rp <- result.try(text_field(r, "plan_id"))
      use rt <- result.try(text_field(r, "task_id"))
      use rw <- result.try(text_field(r, "worker"))
      use rs <- result.try(text_field(r, "session_id"))
      use ra <- result.try(recovery_integer(r, "attempt"))
      require(
        dev.valid_identifier(plan)
          && string.starts_with(plan, "uos/")
          && dev.valid_identifier(task)
          && task != "HARNESSBOOT"
          && dev.valid_identifier(rp)
          && string.starts_with(rp, "uos/")
          && dev.valid_identifier(rt)
          && rt != "HARNESSBOOT"
          && component(rw)
          && component(rs)
          && ra > 0
          && ra < 1_000_000,
        "recovery_review_read_delegation_shape",
      )
    }),
  )
  require(
    list.any(allowed, fn(entry) {
      value.get(entry, "target_plan") == Ok(value.Text(target_plan))
      && value.get(entry, "target_task") == Ok(value.Text(target_task))
      && case value.get(entry, "reviewer") {
        Ok(r) -> same_value(r, reviewer)
        Error(_) -> False
      }
    }),
    "recovery_review_task_read_not_delegated",
  )
}

fn recovery_review_task(
  grant: Grant,
  scope: Scope,
  review: value.Value,
  digest: String,
) -> Result(Nil, String) {
  use reviewer <- result.try(value.get(review, "reviewer"))
  // The optional delegation is covered by exact whole-grant proposal/review
  // equality. Reading a review file alone never delegates task metadata reads.
  use body <- result.try(files.read(dev.root, grant.path))
  use _ <- result.try(require(
    files.digest(body) == grant.digest,
    "grant_changed",
  ))
  use document <- result.try(recovery_parse(body))
  use _ <- result.try(recovery_review_read_delegated(
    document,
    reviewer,
    scope.plan,
    scope.task,
  ))
  use _ <- result.try(
    recovery_closed(reviewer, [
      "plan_id",
      "task_id",
      "worker",
      "session_id",
      "attempt",
    ]),
  )
  use plan <- result.try(text_field(reviewer, "plan_id"))
  use task <- result.try(text_field(reviewer, "task_id"))
  use worker <- result.try(text_field(reviewer, "worker"))
  use session <- result.try(text_field(reviewer, "session_id"))
  use attempt <- result.try(recovery_integer(reviewer, "attempt"))
  use _ <- result.try(require(
    dev.valid_identifier(plan)
      && string.starts_with(plan, "uos/")
      && dev.valid_identifier(task)
      && task != "HARNESSBOOT"
      && component(worker)
      && component(session)
      && worker != grant.worker
      && session != grant.session
      && attempt > 0
      && attempt < 1_000_000,
    "recovery_independent_review_binding",
  ))
  let binding =
    dev.Binding("development", plan, task, worker, attempt, session, 1)
  use row <- result.try(dev.read_task(binding))
  require(
    dev.terminal_matches(
      binding,
      row,
      "uos.harness-recovery-review.v1:" <> digest,
    ),
    "recovery_canonical_review_completion",
  )
}

/// Existing reviewed-launcher admission is mandatory. There is deliberately no
/// relaxed TaskFence, no claim/SQL/DDL dispatch, no issuer/provider constructor
/// and no interpretation of a report-only selection as effect authority.
pub fn prepare_reviewed_recovery(
  supplied_grant: Grant,
  plan: String,
  task: String,
  intent: String,
  review_path: String,
  review_sha256: String,
) -> Result(PreparedRecovery, String) {
  use grant <- result.try(load_with(supplied_grant.path, supplied_grant.digest))
  use scope <- result.try(lookup(grant, plan, task))
  use _ <- result.try(require(
    intent_valid(intent)
      && digest_valid(review_sha256)
      && public_path(review_path)
      && string.starts_with(review_path, "governance/planning/")
      && list.contains(scope.reads, review_path),
    "recovery_reference_scope",
  ))
  use now <- result.try(check(grant))
  use _ <- result.try(validate_window_for(grant, now, 20_000))
  use review_bytes <- result.try(files.read(dev.root, review_path))
  use _ <- result.try(require(
    files.digest(review_bytes) == review_sha256,
    "recovery_review_changed",
  ))
  use review <- result.try(recovery_parse(review_bytes))
  use _ <- result.try(
    recovery_closed(review, [
      "schema",
      "verdict",
      "grant_id",
      "grant_sha256",
      "target_session",
      "target_worker",
      "observed_utc_us",
      "expires_utc_us",
      "proposal",
      "proposal_sha256",
      "reviewer",
    ]),
  )
  use observed <- result.try(recovery_decimal(review, "observed_utc_us"))
  use expires <- result.try(recovery_decimal(review, "expires_utc_us"))
  use _ <- result.try(require(
    value.get(review, "schema")
      == Ok(value.Text("uos.harness-reviewed-recovery.v1"))
      && value.get(review, "verdict")
      == Ok(value.Text("APPROVE_DEV_RECOVERY_PREPARATION_ONLY"))
      && value.get(review, "grant_id") == Ok(value.Text(grant.id))
      && value.get(review, "grant_sha256") == Ok(value.Text(grant.digest))
      && value.get(review, "target_worker") == Ok(value.Text(grant.worker))
      && value.get(review, "target_session") == Ok(value.Text(grant.session))
      && observed <= now.sample.observed.utc_us
      && now.sample.observed.utc_us < expires
      && expires - observed <= 3_600_000_000,
    "recovery_review_scope_or_window",
  ))
  use proposal <- result.try(value.get(review, "proposal"))
  let proposal_bytes = json.to_string(value.encode(proposal))
  use proposal_digest <- result.try(text_field(review, "proposal_sha256"))
  use _ <- result.try(require(
    digest_valid(proposal_digest)
      && files.digest(proposal_bytes) == proposal_digest,
    "recovery_review_proposal_digest",
  ))
  use p <- result.try(recovery_proposal_data(proposal_bytes))
  use _ <- result.try(require(
    p.plan == scope.plan
      && p.selected_task == scope.task
      && p.worker == grant.worker,
    "recovery_scope_mismatch",
  ))
  use _ <- result.try(recovery_review_task(grant, scope, review, review_sha256))
  use manifest <- result.try(recovery_source_manifest(grant, scope))
  use _ <- result.try(require(
    manifest == p.source_manifest_sha256,
    "recovery_source_manifest_changed",
  ))
  let bindings =
    json.object([
      #("plan_id", json.string(plan)),
      #("bindings", json.array(p.bindings, recovery_binding_json)),
    ])
    |> json.to_string
  use mode <- result.try(case p.selection_review {
    value.Null ->
      Ok([
        "--reclaim-set-preflight",
        dev.root <> "/" <> scope.portfolio,
        task,
        bindings,
      ])
    selection -> {
      use path <- result.try(text_field(selection, "path"))
      use proof <- result.try(text_field(selection, "proof_path"))
      use _ <- result.try(require(
        list.contains(scope.reads, path) && list.contains(scope.reads, proof),
        "recovery_selection_read_scope",
      ))
      Ok([
        "--reclaim-set-preflight-reviewed",
        dev.root <> "/" <> scope.portfolio,
        task,
        bindings,
        path,
      ])
    }
  })
  use raw <- result.try(dev.bounded(
    dev.root <> "/toolchains/nix-profile/bin/env",
    [
      "PATH="
        <> dev.root
        <> "/toolchains/nix-profile/bin:"
        <> dev.root
        <> "/toolchains/opam-ocaml/bin:/usr/bin:/bin",
      "OPAM_SWITCH_PREFIX=" <> dev.root <> "/toolchains/opam-ocaml",
      "/usr/bin/bash",
      dev.root <> "/tools/risk-priority-check",
      ..mode
    ],
    15_000,
  ))
  use after <- result.try(check(grant))
  use _ <- result.try(require(
    after.sample.observed.utc_us >= now.sample.observed.utc_us
      && after.sample.observed.utc_us < expires,
    "recovery_review_expired",
  ))
  use same_review <- result.try(files.read(dev.root, review_path))
  use _ <- result.try(require(
    same_review == review_bytes,
    "recovery_review_changed",
  ))
  use after_manifest <- result.try(recovery_source_manifest(grant, scope))
  use _ <- result.try(require(
    after_manifest == manifest,
    "recovery_source_manifest_changed",
  ))
  use observation <- result.try(recovery_bind_observation_data(
    p,
    raw,
    after.sample.observed.utc_us * 1000,
  ))
  Ok(PreparedRecovery(
    observation,
    grant.digest,
    review_sha256,
    after.sample.observed.utc_us,
  ))
}

pub fn prepared_recovery_json(prepared: PreparedRecovery) -> json.Json {
  json.object([
    #("status", json.string("PREPARED_OBSERVATION_ONLY")),
    #("observation", recovery_observation_json(prepared.observation)),
    #("grant_sha256", json.string(prepared.grant_sha256)),
    #("review_sha256", json.string(prepared.review_sha256)),
    #("observed_utc_us", json.string(int.to_string(prepared.observed_utc_us))),
    #("native_executor", json.string("UNAVAILABLE")),
    #(
      "reviewer_identity",
      json.string("CANONICAL_TASK_WORKER_ATTEMPT_SESSION_LABEL_UNAUTHENTICATED"),
    ),
    #("authority", json.string("NONE")),
    #("task_mutation_enabled", json.bool(False)),
    #("production_admission", json.bool(False)),
  ])
}

pub fn observe_execution(execution: Execution) -> json.Json {
  json.object([
    #("plan", json.string(execution.scope.plan)),
    #("task", json.string(execution.scope.task)),
    #("worker", json.string(execution.binding.worker)),
    #("attempt", json.int(execution.binding.attempt)),
    #("coordinator_epoch", json.int(execution.binding.epoch)),
    #("risk_portfolio", json.string(execution.risk_path)),
    #("grant_sha256", json.string(execution.grant.digest)),
    #(
      "authority",
      json.string(
        "canonical_sa_plan_with_cooperative_local_launcher_and_session_fences",
      ),
    ),
    #("production_admission", json.bool(False)),
  ])
}
