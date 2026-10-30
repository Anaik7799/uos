//// Track A live MCP ingress. The OTP owner serializes every transport's state.
//// Transport identity never supplies task/grant authority. EV ceiling stays 93.

import cepaf_gleam/harness/admission as harness_admission
import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import cepaf_gleam/harness/mcp as launcher
import cepaf_gleam/harness/native_backend
import cepaf_gleam/harness/operations as ops
import cepaf_gleam/harness/successor_mcp
import cepaf_gleam/harness/value
import cepaf_gleam/mcp/adapters/analysis
import cepaf_gleam/mcp/adapters/control
import cepaf_gleam/mcp/adapters/features
import cepaf_gleam/mcp/adapters/knowledge
import cepaf_gleam/mcp/adapters/planning_read
import cepaf_gleam/mcp/adapters/planning_write
import cepaf_gleam/mcp/adapters/system_observation
import cepaf_gleam/mcp/adapters/vault_metadata
import cepaf_gleam/mcp/adapters/verification
import cepaf_gleam/mcp/admission
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/http_auth
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/profiles/modern
import cepaf_gleam/mcp/prompts
import cepaf_gleam/mcp/receipts
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/resources
import cepaf_gleam/mcp/route_convergence
import cepaf_gleam/mcp/server
import cepaf_gleam/mcp/subscriptions
import cepaf_gleam/mcp/supervisor
import cepaf_gleam/mcp/task_extension
import cepaf_gleam/mcp/transports/http
import cepaf_gleam/mcp/transports/stdio
import cepaf_gleam/mcp/transports/zenoh as zenoh_transport
import cepaf_gleam/mcp/types
import cepaf_gleam/mcp/version
import cepaf_gleam/mcp/wire
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/charlist
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor as otp_supervisor
import gleam/otp/supervision
import gleam/result
import gleam/string
import simplifile

const default_root = "/home/an/NAS-setup/uos"

const completion_plan = "20261029-1913-mcp-server-completion"

const default_issuer = "https://nas-1.tail55d152.ts.net:4101"

pub const max_successor_sessions = 1024

pub type SuccessorSessionRecord {
  SuccessorSessionRecord(
    owner_actor: String,
    owner_client: String,
    owner_transport: types.TransportKind,
    owner_session: String,
    state: successor_mcp.State,
  )
}

/// Trusted code seam, never populated from request authority fields. Resolution
/// observes real harness admission; execution is delayed until canonical gates.
pub type PrivateBinding {
  PrivateBinding(
    route_grant: Option(route_convergence.RouteGrant),
    task_fence: Option(admission.TaskFence),
    execute: fn() -> #(Result(String, String), Option(successor_mcp.State)),
  )
}

pub type PrivateResolver =
  fn(
    principal.Principal,
    String,
    String,
    value.Value,
    Option(SuccessorSessionRecord),
  ) -> Result(PrivateBinding, types.ToolError)

pub opaque type PreparedPrivateCall {
  PreparedPrivateCall(
    context: admission.AdmissionContext,
    route_grant: Option(route_convergence.RouteGrant),
    route: String,
    tool: String,
    args: dict.Dict(String, String),
    output: Result(String, String),
    next_successor: Option(successor_mcp.State),
    intent_id: String,
    candidate: String,
    effect_executed: Bool,
  )
}

pub opaque type PrivateSnapshot {
  PrivateSnapshot(
    pool: supervisor.WorkerPool,
    features: features.FeatureEvidenceStore,
    workspace_root: String,
    successor: Option(SuccessorSessionRecord),
    successor_count: Int,
  )
}

pub type GatewayState {
  GatewayState(
    pool: supervisor.WorkerPool,
    backends: server.ServerBackends,
    resources: resources.ResourceRegistry,
    resource_cache: resources.ResourceCache,
    prompts: List(prompts.PromptSpec),
    subscriptions: subscriptions.SubscriptionStore,
    tasks: task_extension.TaskExtensionStore,
    negotiated_task_sessions: dict.Dict(String, Bool),
    successor_sessions: dict.Dict(String, SuccessorSessionRecord),
    supervised_gateway: supervisor.SupervisedGateway,
  )
}

/// Trusted in-VM actor protocol. Neither snapshots nor prepared calls can be
/// constructed from transport payloads; their public types remain opaque.
pub type Message {
  Ping(process.Subject(Bool))
  Snapshot(principal.Principal, process.Subject(PrivateSnapshot))
  ObservationTarget(process.Subject(supervisor.SupervisedGateway))
  CommitPrivate(PreparedPrivateCall, process.Subject(types.Outcome))
  Dispatch(
    principal.Principal,
    types.ProtocolProfile,
    String,
    String,
    wire.NormalizedMessage,
    Int,
    Option(#(String, Option(knowledge.CorpusEntry))),
    Option(planning_read.PlanningReadStore),
    Option(#(verification.CheckId, verification.CheckRunnerResult)),
    Option(Bool),
    process.Subject(types.Outcome),
  )
}

type StdioLine {
  Line(String)
  EndOfFile
  ReadError(String)
}

@external(erlang, "cepaf_gleam_ffi", "get_env")
fn get_env(key: String) -> Result(String, Nil)

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn system_time_nanos() -> Int

@external(erlang, "os", "getpid")
fn os_pid() -> charlist.Charlist

@external(erlang, "erlang", "monotonic_time")
fn monotonic_time(unit: atom.Atom) -> Int

@external(erlang, "persistent_term", "get")
fn stored_subject(
  key: atom.Atom,
  default: Option(process.Subject(Message)),
) -> Option(process.Subject(Message))

@external(erlang, "persistent_term", "put")
fn store_subject(
  key: atom.Atom,
  subject: Option(process.Subject(Message)),
) -> Nil

@external(erlang, "mcp_stdio_ffi", "run_workspace_bounded_cd")
fn run_bounded_cd(
  path: String,
  args: List(String),
  cwd: String,
  timeout_ms: Int,
) -> Result(#(Int, String), String)

@external(erlang, "mcp_stdio_ffi", "read_line")
fn read_line() -> StdioLine

@external(erlang, "mcp_stdio_ffi", "with_gateway_boot_lock")
fn with_gateway_boot_lock(f: fn() -> Bool) -> Bool

@external(erlang, "mcp_stdio_ffi", "with_private_route_lock")
fn with_private_route_lock(f: fn() -> a) -> a

@external(erlang, "mcp_stdio_ffi", "register_or_stop_supervisor")
fn register_or_stop_supervisor(pid: process.Pid) -> Bool

@external(erlang, "mcp_stdio_ffi", "loaded_mcp_beams_digest")
fn loaded_mcp_beams_digest() -> String

@external(erlang, "mcp_stdio_ffi", "start_zenoh_sse_subscriber")
fn start_sse_worker(
  host: String,
  port: Int,
  secret: String,
  register: Bool,
  lock_port: Int,
  idle_timeout_ms: Int,
  handler: fn(String) -> Option(#(String, String)),
) -> Result(process.Pid, String)

@external(erlang, "mcp_stdio_ffi", "stop_zenoh_sse_subscriber")
pub fn stop_zenoh_sse_subscriber(pid: process.Pid) -> Bool

@external(erlang, "mcp_stdio_ffi", "zenoh_subscriber_alive")
pub fn zenoh_subscriber_alive() -> Bool

@external(erlang, "mcp_stdio_ffi", "mark_stdio_gateway")
fn mark_stdio_gateway() -> Nil

@external(erlang, "mcp_stdio_ffi", "stdio_gateway")
fn stdio_gateway() -> Bool

pub fn zenoh_subscriber_enabled() -> Bool {
  env("UOS_MCP_ZENOH_SUBSCRIBER", "0") == "1"
  && env("UOS_MCP_ZENOH_SHARED_SECRET", "") != ""
  && env("UOS_MCP_CLIENT_NAME", "") == ""
  && !stdio_gateway()
}

/// Trusted entrypoint; the FFI independently permits only the pinned router or
/// IPv4 loopback. Production never takes host/port from environment or payload.
pub fn start_zenoh_sse_subscriber_for_test(
  host: String,
  port: Int,
  shared_secret: String,
) -> Result(process.Pid, String) {
  start_zenoh_sse_subscriber_with_options(
    host,
    port,
    shared_secret,
    False,
    0,
    5000,
  )
}

/// Trusted code only: the independent FFI endpoint guard and OS mutex also
/// apply to this seam. Transport payloads never supply these options.
pub fn start_zenoh_sse_subscriber_with_options(
  host: String,
  port: Int,
  shared_secret: String,
  register: Bool,
  lock_port: Int,
  idle_timeout_ms: Int,
) -> Result(process.Pid, String) {
  start_sse_worker(
    host,
    port,
    shared_secret,
    register,
    lock_port,
    idle_timeout_ms,
    fn(block) {
      case decode_zenoh_sse_event(block) {
        None -> None
        Some(#(topic, payload)) ->
          zenoh_raw_with_secret(topic, payload, shared_secret)
      }
    },
  )
}

@external(erlang, "mcp_stdio_ffi", "with_zenoh_boot_lock")
fn with_zenoh_boot_lock(f: fn() -> Bool) -> Bool

@external(erlang, "mcp_stdio_ffi", "register_or_keep_zenoh_supervisor")
fn register_or_keep_zenoh_supervisor(pid: process.Pid) -> Bool

@external(erlang, "mcp_stdio_ffi", "zenoh_supervisor_running")
fn zenoh_supervisor_running() -> Bool

@external(erlang, "mcp_stdio_ffi", "zenoh_subscriber_state")
pub fn zenoh_subscriber_state() -> String

@external(erlang, "mcp_stdio_ffi", "zenoh_subscriber_last_activity_age_ms")
pub fn zenoh_subscriber_last_activity_age_ms() -> Int

@external(erlang, "mcp_stdio_ffi", "isolate_zenoh_supervisor_start")
fn isolate_zenoh_supervisor_start(
  start: fn() -> Result(process.Pid, String),
) -> Result(process.Pid, String)

/// This supervisor has no link to the gateway owner or its supervisor. The
/// same constructor exercises registered/OS-locked workers in loopback tests.
pub fn start_zenoh_supervisor_with_options_for_test(
  host: String,
  port: Int,
  secret: String,
  register: Bool,
  lock_port: Int,
  idle_timeout_ms: Int,
) -> Result(process.Pid, String) {
  isolate_zenoh_supervisor_start(fn() {
    otp_supervisor.new(otp_supervisor.OneForOne)
    |> otp_supervisor.restart_tolerance(intensity: 5, period: 60)
    |> otp_supervisor.add(
      supervision.worker(fn() {
        start_zenoh_sse_subscriber_with_options(
          host,
          port,
          secret,
          register,
          lock_port,
          idle_timeout_ms,
        )
        |> result.map(fn(pid) { actor.Started(pid, Nil) })
        |> result.map_error(actor.InitFailed)
      }),
    )
    |> otp_supervisor.start
    |> result.map(fn(started) {
      process.unlink(started.pid)
      started.pid
    })
    |> result.map_error(fn(_) { "zenoh_supervisor_start_failed" })
  })
}

fn start_production_zenoh_subscriber() -> Bool {
  with_zenoh_boot_lock(fn() {
    case zenoh_supervisor_running() {
      True -> True
      False ->
        case
          start_zenoh_supervisor_with_options_for_test(
            "nas-1.tail55d152.ts.net",
            8080,
            env("UOS_MCP_ZENOH_SHARED_SECRET", ""),
            True,
            41_199,
            30_000,
          )
        {
          Ok(pid) -> register_or_keep_zenoh_supervisor(pid)
          // An in-node or cross-process owner is expected contention, never a
          // gateway boot failure. Later ingress may retry the independent child.
          Error(_) -> False
        }
    }
  })
}

fn gateway_key() -> atom.Atom {
  // Constant atom only; client input can never grow the atom table.
  atom.create("uos_mcp_runtime_gateway_subject")
}

fn env(key: String, fallback: String) -> String {
  case get_env(key) {
    Ok(value) if value != "" -> value
    _ -> fallback
  }
}

fn workspace_root() -> String {
  let fallback = case simplifile.is_directory(default_root) {
    Ok(True) -> default_root
    _ -> "."
  }
  env("UOS_MCP_WORKSPACE_ROOT", env("PROJECT_ROOT", fallback))
}

fn now_ms() -> Int {
  system_time_nanos() / 1_000_000
}

fn subject_alive(subject: process.Subject(a)) -> Bool {
  case process.subject_owner(subject) {
    Ok(pid) -> process.is_alive(pid)
    Error(_) -> False
  }
}

pub fn supervised_gateway_pids_alive(
  gateway: supervisor.SupervisedGateway,
) -> Bool {
  process.is_alive(gateway.supervisor_pid)
  && subject_alive(gateway.gateway_subject)
}

fn gateway_alive(gateway: supervisor.SupervisedGateway) -> Bool {
  case supervised_gateway_pids_alive(gateway) {
    False -> False
    True -> {
      let reply = process.new_subject()
      process.send(gateway.gateway_subject, supervisor.Ping(reply))
      process.receive(reply, 1000) == Ok(True)
    }
  }
}

pub fn is_running() -> Bool {
  case stored_subject(gateway_key(), None) {
    None -> False
    Some(subject) ->
      case subject_alive(subject) {
        False -> False
        True -> {
          let reply = process.new_subject()
          process.send(subject, Ping(reply))
          process.receive(reply, 1500) == Ok(True)
        }
      }
  }
}

pub fn ensure_started() -> Bool {
  ensure_started_with_zenoh(zenoh_subscriber_enabled())
}

/// False is mandatory for ephemeral stdio entrypoints; subscriber failures are
/// never propagated into the independent gateway state-owner supervisor.
fn ensure_started_with_zenoh(enable_zenoh: Bool) -> Bool {
  ensure_started_with_subscriber_for_test(fn() {
    case enable_zenoh {
      True -> start_production_zenoh_subscriber()
      False -> False
    }
  })
}

/// Trusted injection seam for fresh-VM boot under real subscriber contention.
/// Production and tests share the same state-owner boot-before-subscriber order.
pub fn ensure_started_with_subscriber_for_test(
  start_subscriber: fn() -> Bool,
) -> Bool {
  let running =
    with_gateway_boot_lock(fn() {
      case is_running() {
        True -> True
        False -> {
          let root = workspace_root()
          let cand = candidate_id.from_root(root)
          case candidate_id.is_sha256_digest(cand) {
            False -> False
            True -> {
              // The state owner is a real supervisor child, with its subject
              // refreshed in persistent_term on every OTP restart.
              let child =
                supervision.worker(fn() {
                  case
                    supervisor.start_supervised_gateway(),
                    supervisor.start_worker_pool_for_candidate(
                      size: 4,
                      candidate: cand,
                    )
                  {
                    Ok(gateway), Ok(pool) -> {
                      let state = new_state(root, cand, pool, gateway)
                      case start_state_owner(state) {
                        Ok(started) -> {
                          store_subject(gateway_key(), Some(started.data))
                          Ok(started)
                        }
                        Error(error) -> Error(error)
                      }
                    }
                    Error(error), _ -> Error(error)
                    _, Error(reason) -> Error(actor.InitFailed(reason))
                  }
                })
              case
                otp_supervisor.new(otp_supervisor.OneForOne)
                |> otp_supervisor.restart_tolerance(intensity: 5, period: 60)
                |> otp_supervisor.add(child)
                |> otp_supervisor.start
              {
                Ok(started) -> {
                  process.unlink(started.pid)
                  case register_or_stop_supervisor(started.pid) {
                    True -> is_running()
                    False -> is_running()
                  }
                }
                Error(_) -> False
              }
            }
          }
        }
      }
    })
  case running {
    True -> {
      let _ = start_subscriber()
      Nil
    }
    False -> Nil
  }
  running
}

pub fn gateway_health_json() -> String {
  health_json(is_running(), candidate_id.from_root(workspace_root()))
  |> json.to_string
}

fn health_json(running: Bool, candidate: String) -> json.Json {
  json.object([
    #(
      "status",
      json.string(case running {
        True -> "running"
        False -> "stopped"
      }),
    ),
    #("child_id", json.string("mcp_unified_gateway")),
    #("candidate", json.string(candidate)),
    #("loaded_beam_sha256", json.string(loaded_mcp_beams_digest())),
    #("zenoh_subscriber_enabled", json.bool(zenoh_subscriber_enabled())),
    #("zenoh_subscriber_alive", json.bool(zenoh_subscriber_alive())),
    #(
      "zenoh_subscriber_state",
      json.string(case zenoh_subscriber_enabled() {
        False -> "disabled"
        True -> zenoh_subscriber_state()
      }),
    ),
    #(
      "zenoh_subscriber_last_activity_age_ms",
      json.int(zenoh_subscriber_last_activity_age_ms()),
    ),
    #("public_routes", json.int(65)),
    #("development_routes", json.int(21)),
    #("successor_routes", json.int(15)),
    #("total_routes", json.int(101)),
    #("application_admitted", json.bool(False)),
  ])
}

/// Assemble state for supervised ingress or an isolated development fixture.
pub fn new_state(
  root: String,
  cand: String,
  pool: supervisor.WorkerPool,
  gateway: supervisor.SupervisedGateway,
) -> GatewayState {
  let corpus = knowledge.new_corpus(root, ["public"], 1_048_576, 4)
  let corpus =
    list.fold(["AGENTS.md", "CLAUDE.md", "GEMINI.md"], corpus, load_document)
  let evidence =
    features.FeatureEvidenceStore(
      active_candidate: cand,
      admitted_ev_ceiling: 93,
      capabilities: list.map(registry.all_specs(), fn(spec) {
        features.CapabilityRecord(
          spec.name,
          spec.route,
          "declared",
          "implemented",
          "unrun",
          "unrun",
          "not_admitted",
        )
      }),
      completed_task_ids: list.map(
        int.range(0, 25, [], fn(acc, n) { [n, ..acc] }) |> list.reverse,
        fn(n) {
          "T"
          <> case n < 10 {
            True -> "0"
            False -> ""
          }
          <> int.to_string(n)
        },
      ),
      receipts: dict.new(),
      intents: dict.new(),
    )
  let backends =
    server.ServerBackends(
      planning_read: load_planning(root, completion_plan),
      planning_write: planning_write.new_store(),
      observation: observation(
        cand,
        now_ms(),
        supervised_gateway_pids_alive(gateway),
        "gateway_pid_liveness",
      ),
      control: control.ControlBackend(cand, 0, False, dict.new()),
      verification_runner: fn(_) {
        verification.ProverMissing(
          "No live verification runner bound to runtime gateway",
        )
      },
      knowledge: corpus,
      vault: vault_metadata.UnwiredVault("No supervised vault handle bound"),
      analysis: analysis.MaxDaemonOffline("No inference daemon bound"),
      features: evidence,
    )
  let entries = [
    #(
      "uos://system/mcp-gateway-health",
      "MCP Gateway Health",
      health_json(True, cand) |> json.to_string,
    ),
    #(
      "uos://governance/ev-provenance-ceiling",
      "EV provenance ceiling",
      "{\"admitted_ev_ceiling\":93,\"application_admitted\":false}",
    ),
    #(
      "uos://planning/active-cutover-plan",
      "Active MCP cutover plan",
      "{\"plan_id\":\"20261030-1245-mcp-full-service-cutover\",\"authority\":\"sa_plan\"}",
    ),
  ]
  GatewayState(
    pool,
    backends,
    resources.registry(
      list.map(entries, fn(entry) {
        resources.ResourceEntry(
          entry.0,
          entry.1,
          "application/json",
          resources.PublicResource,
          "",
          root,
          entry.2,
        )
      }),
      [
        resources.ResourceTemplate(
          "uos://docs/{slug}",
          "uos_doc",
          "Canonical UOS documentation entry",
        ),
      ],
    ),
    resources.empty_cache(),
    [
      prompts.PromptSpec(
        "uos_poodavr_review",
        "Advisory POODAVR review",
        [],
        "Predict, observe, orient, decide, act, verify, reflect. Advice grants no effect authority.",
      ),
      prompts.PromptSpec(
        "uos_jidoka_rca",
        "Advisory Jidoka root cause analysis",
        [],
        "Contain the failure, disconfirm hypotheses, and verify recovery under Sa-plan authority.",
      ),
    ],
    subscriptions.empty_store(),
    task_extension.empty_store(),
    dict.new(),
    dict.new(),
    gateway,
  )
}

// Refuse every symlink component, including links within the workspace. There
// is no silent follow of an intermediate directory into a foreign tree.
fn regular_components(root: String, parts: List(String)) -> Bool {
  case parts {
    [] -> True
    [part, ..rest] -> {
      let path = root <> "/" <> part
      case simplifile.is_symlink(path) {
        Ok(False) -> regular_components(path, rest)
        _ -> False
      }
    }
  }
}

fn load_document(
  corpus: knowledge.KnowledgeCorpus,
  path: String,
) -> knowledge.KnowledgeCorpus {
  apply_document(corpus, path, read_corpus_entry(corpus.workspace_root, path))
}

fn apply_document(
  corpus: knowledge.KnowledgeCorpus,
  path: String,
  entry: Option(knowledge.CorpusEntry),
) -> knowledge.KnowledgeCorpus {
  let corpus =
    knowledge.KnowledgeCorpus(
      ..corpus,
      entries: dict.delete(corpus.entries, path),
    )
  case entry {
    Some(entry) -> knowledge.with_entry(corpus, entry)
    None -> corpus
  }
}

// Filesystem-only prefetch; this helper never reads or mutates actor state.
fn read_corpus_entry(
  root: String,
  path: String,
) -> Option(knowledge.CorpusEntry) {
  case knowledge.path_security_violation(path, root) {
    Some(_) -> None
    None -> {
      let relative = case string.starts_with(path, root <> "/") {
        True -> string.drop_start(path, string.length(root) + 1)
        False -> path
      }
      let full = root <> "/" <> relative
      case
        !string.starts_with(relative, "/")
        && relative != ""
        && regular_components(root, string.split(relative, "/"))
      {
        False ->
          Some(knowledge.CorpusEntry(
            path,
            knowledge.SymlinkEscape,
            "public",
            "",
          ))
        True ->
          case simplifile.file_info(full) {
            Ok(info) if info.nlinks > 1 ->
              Some(knowledge.CorpusEntry(
                path,
                knowledge.HardlinkEscape,
                "public",
                "",
              ))
            Ok(info) if info.size <= 1_048_576 ->
              case simplifile.read(full) {
                Ok(content) ->
                  case string.byte_size(content) <= 1_048_576 {
                    True ->
                      Some(knowledge.CorpusEntry(
                        path,
                        knowledge.RegularFile,
                        "public",
                        content,
                      ))
                    False -> None
                  }
                _ -> None
              }
            _ -> None
          }
      }
    }
  }
}

fn task_row_decoder() -> decode.Decoder(planning_read.CanonicalTaskRow) {
  use plan <- decode.field("plan_id", decode.string)
  use id <- decode.field("id", decode.string)
  use title <- decode.field("title", decode.string)
  use state <- decode.field("state", decode.string)
  use worker <- decode.field("worker", decode.string)
  use attempt <- decode.field("attempt", decode.int)
  decode.success(planning_read.CanonicalTaskRow(
    plan,
    id,
    title,
    state,
    worker,
    attempt,
  ))
}

fn sqlite_binary(root: String) -> Option(String) {
  list.find(
    ["/usr/bin/sqlite3", root <> "/toolchains/nix-profile/bin/sqlite3"],
    fn(path) { simplifile.is_file(path) == Ok(True) },
  )
  |> option.from_result
}

fn load_planning(
  root: String,
  plan: String,
) -> planning_read.PlanningReadStore {
  let db = root <> "/var/sa-plan/uos.sqlite3"
  case simplifile.is_file(db), sqlite_binary(root) {
    Ok(True), Some(binary) -> {
      // Escape SQL string literals; never interpolate identifiers or commands.
      let selected =
        " WHERE plan_id = '" <> string.replace(plan, "'", "''") <> "'"
      let query =
        "SELECT plan_id, id, title, state, COALESCE(worker, '-') AS worker, COALESCE(attempt, 0) AS attempt FROM sa_plan_task"
        <> selected
        <> " ORDER BY plan_id, id LIMIT 500;"
      let output =
        run_bounded_cd(binary, ["-readonly", "-json", db, query], root, 3000)
      let output = case output {
        Ok(#(code, text)) if code != 0 ->
          case string.contains(text, "no such table: sa_plan_task") {
            True ->
              run_bounded_cd(
                binary,
                [
                  "-readonly",
                  "-json",
                  db,
                  string.replace(query, "FROM sa_plan_task", "FROM tasks"),
                ],
                root,
                3000,
              )
            False -> output
          }
        _ -> output
      }
      case output {
        Ok(#(0, text)) ->
          case string.byte_size(text) <= 524_288 {
            False ->
              planning_read.unavailable_store(
                "Canonical query output too large",
              )
            True ->
              case json.parse(text, decode.list(task_row_decoder())) {
                Ok(rows) -> planning_read.sample_canonical_store(plan, rows)
                Error(_) ->
                  planning_read.unavailable_store(
                    "Canonical task query returned invalid JSON or no rows",
                  )
              }
          }
        _ ->
          planning_read.unavailable_store(
            "Canonical read-only task query failed or exceeded output bound",
          )
      }
    }
    Ok(True), None -> planning_read.sample_canonical_store(completion_plan, [])
    _, _ ->
      planning_read.unavailable_store(
        "Canonical Sa-plan database missing or unreadable",
      )
  }
}

fn observation(
  cand: String,
  now: Int,
  alive: Bool,
  scope: String,
) -> system_observation.ObservationBackend {
  system_observation.ObservedSnapshot(
    cand,
    "beam_otp29_live",
    now,
    30_000,
    Some(["c3i-zenoh-router-1", "c3i-docs-server"]),
    dict.from_list([
      #("system_health.status", case alive {
        True -> "healthy"
        False -> "stopped"
      }),
      #("gateway_alive", case alive {
        True -> "true"
        False -> "false"
      }),
      #(
        "observation_scope",
        scope <> "; container names are configured inventory",
      ),
      #("public_routes", "65"),
      #("total_routes", "101"),
    ]),
  )
}

fn handle_message(
  state: GatewayState,
  message: Message,
) -> actor.Next(GatewayState, Message) {
  case message {
    Snapshot(p, reply) -> {
      process.send(reply, private_snapshot(state, p))
      actor.continue(state)
    }
    ObservationTarget(reply) -> {
      process.send(reply, state.supervised_gateway)
      actor.continue(state)
    }
    CommitPrivate(prepared, reply) -> {
      let #(outcome, next) = commit_private(state, prepared)
      process.send(reply, outcome)
      actor.continue(next)
    }
    Ping(reply) -> {
      process.send(
        reply,
        supervised_gateway_pids_alive(state.supervised_gateway),
      )
      actor.continue(state)
    }
    Dispatch(
      p,
      profile,
      route,
      raw,
      msg,
      now,
      prefetched_doc,
      prefetched_plan,
      prefetched_check,
      prefetched_gateway_alive,
      reply,
    ) -> {
      let backends =
        server.ServerBackends(
          ..state.backends,
          knowledge: case prefetched_doc {
            Some(#(path, entry)) ->
              apply_document(state.backends.knowledge, path, entry)
            None -> state.backends.knowledge
          },
          planning_read: option.unwrap(
            prefetched_plan,
            state.backends.planning_read,
          ),
          verification_runner: fn(cid) {
            case prefetched_check {
              Some(#(expected, res)) if expected == cid -> res
              _ -> verification.ProverMissing("No prefetched check result")
            }
          },
        )
      let state = GatewayState(..state, backends: backends)
      let #(outcome, next) =
        dispatch_non_private(
          state,
          p,
          profile,
          route,
          raw,
          msg,
          now,
          prefetched_gateway_alive,
        )
      process.send(reply, outcome)
      actor.continue(next)
    }
  }
}

/// Start an isolated owner with the same non-blocking handler as production.
pub fn start_state_owner(
  state: GatewayState,
) -> Result(actor.Started(process.Subject(Message)), actor.StartError) {
  actor.new(state) |> actor.on_message(handle_message) |> actor.start
}

fn dispatch_actor(
  p: principal.Principal,
  profile: types.ProtocolProfile,
  route: String,
  raw: String,
  msg: wire.NormalizedMessage,
  now: Int,
) -> types.Outcome {
  case ensure_started(), stored_subject(gateway_key(), None) {
    True, Some(subject) -> {
      case msg.method == "tools/call" && is_private_route(route) {
        True ->
          with_private_route_lock(fn() {
            dispatch_private_actor(
              subject,
              p,
              route,
              raw,
              msg,
              live_private_binding,
            )
          })
        False ->
          dispatch_public_actor(subject, p, profile, route, raw, msg, now)
      }
    }
    _, _ -> refuse("GATEWAY_UNAVAILABLE", "OTP gateway could not start")
  }
}

fn dispatch_public_actor(
  subject: process.Subject(Message),
  p: principal.Principal,
  profile: types.ProtocolProfile,
  route: String,
  raw: String,
  msg: wire.NormalizedMessage,
  now: Int,
) -> types.Outcome {
  let prefetched_gateway_alive = case msg.method {
    "tools/call" -> {
      let #(tool, _) = tool_arguments(raw, msg)
      case
        route == "public" && system_observation.is_known_observation_tool(tool)
      {
        True -> Some(prefetch_gateway_alive(subject))
        False -> None
      }
    }
    _ -> None
  }
  let #(prefetched_doc, prefetched_plan, prefetched_check) = case msg.method {
    "tools/call" -> {
      let #(tool, args) = tool_arguments(raw, msg)
      let root = workspace_root()
      let prefetched_doc = case tool {
        "read_file" -> {
          let path = argument(args, "path", "")
          Some(#(path, read_corpus_entry(root, path)))
        }
        _ -> None
      }
      let prefetched_plan = case registry.lookup(route, tool) {
        Ok(spec) if spec.family == "planning_read" ->
          Some(load_planning(root, argument(args, "plan_id", completion_plan)))
        _ -> None
      }
      let prefetched_check = case verification.is_verification_tool(tool) {
        True -> {
          let check_raw =
            argument(args, "check_id", case tool {
              "preflight_check" -> "preflight_toolchain"
              _ -> ""
            })
          case verification.parse_check_id(check_raw) {
            Ok(check_id) ->
              Some(#(check_id, run_verification_check(root, check_id)))
            Error(_) -> None
          }
        }
        False -> None
      }
      #(prefetched_doc, prefetched_plan, prefetched_check)
    }
    "tasks/create" -> {
      let args = dict.from_list(msg.args)
      let plan_id =
        raw_string(raw, ["params", "planId"], argument(args, "plan_id", ""))
      let prefetched_plan = case profile {
        types.Modern20260728 -> Some(load_planning(workspace_root(), plan_id))
        types.Legacy20241105 -> None
      }
      #(None, prefetched_plan, None)
    }
    _ -> #(None, None, None)
  }
  let reply = process.new_subject()
  process.send(
    subject,
    Dispatch(
      p,
      profile,
      route,
      raw,
      msg,
      now,
      prefetched_doc,
      prefetched_plan,
      prefetched_check,
      prefetched_gateway_alive,
      reply,
    ),
  )
  case process.receive(reply, 15_000) {
    Ok(outcome) -> outcome
    Error(Nil) ->
      types.Refused(types.ToolError(
        "GATEWAY_TIMEOUT",
        "MCP gateway call timed out",
        types.Retryable,
      ))
  }
}

// Both waits are in the ingress caller. The actor only sends a target handle.
fn prefetch_gateway_alive(subject: process.Subject(Message)) -> Bool {
  let reply = process.new_subject()
  process.send(subject, ObservationTarget(reply))
  case process.receive(reply, 1000) {
    Ok(gateway) -> gateway_alive(gateway)
    Error(_) -> False
  }
}

fn is_private_route(route: String) -> Bool {
  route == "development" || route == "successor"
}

fn private_error(code: String, reason: String) -> types.ToolError {
  types.ToolError(code, reason, types.NonRetryable)
}

fn dispatch_private_actor(
  subject: process.Subject(Message),
  p: principal.Principal,
  route: String,
  raw: String,
  msg: wire.NormalizedMessage,
  resolver: PrivateResolver,
) -> types.Outcome {
  dispatch_private_actor_with_timeouts(
    subject,
    p,
    route,
    raw,
    msg,
    resolver,
    1000,
    15_000,
  )
}

/// Injectable actor transport for deterministic timeout/reconciliation tests.
/// Production uses the same protocol with 1s snapshot / 15s commit budgets.
pub fn dispatch_private_actor_with_timeouts(
  subject: process.Subject(Message),
  p: principal.Principal,
  route: String,
  raw: String,
  msg: wire.NormalizedMessage,
  resolver: PrivateResolver,
  snapshot_timeout_ms: Int,
  commit_timeout_ms: Int,
) -> types.Outcome {
  let reply = process.new_subject()
  process.send(subject, Snapshot(p, reply))
  case process.receive(reply, snapshot_timeout_ms) {
    Error(_) -> refuse("GATEWAY_TIMEOUT", "Private snapshot timed out")
    Ok(snapshot) ->
      // Admission may observe subprocesses. This is the ingress caller, never
      // the state actor. Refresh UTC after waiting for the private lock.
      case prepare_private(snapshot, p, route, raw, msg, now_ms(), resolver) {
        Error(outcome) -> outcome
        Ok(prepared) ->
          commit_prepared_private(subject, prepared, commit_timeout_ms)
      }
  }
}

fn commit_prepared_private(
  subject: process.Subject(Message),
  prepared: PreparedPrivateCall,
  timeout_ms: Int,
) -> types.Outcome {
  let reply = process.new_subject()
  process.send(subject, CommitPrivate(prepared, reply))
  case process.receive(reply, timeout_ms) {
    Ok(outcome) -> outcome
    Error(_) ->
      case prepared.effect_executed {
        False ->
          refuse(
            "GATEWAY_TIMEOUT",
            "Private replay commit timed out before any effect",
          )
        True ->
          types.Uncertain(types.UncertainReceipt(
            intent_id: prepared.intent_id,
            route: prepared.route,
            tool: prepared.tool,
            reason: "Private commit timed out after effect execution; reconcile required",
            candidate: prepared.candidate,
          ))
      }
  }
}

/// Trusted-code integration seam. Uses the production private lock, snapshot
/// and actor commit protocol; the resolver cannot be supplied over a transport.
pub fn dispatch_private_live_with_resolver(
  p: principal.Principal,
  route: String,
  raw: String,
  msg: wire.NormalizedMessage,
  resolver: PrivateResolver,
) -> types.Outcome {
  case ensure_started(), stored_subject(gateway_key(), None) {
    True, Some(subject) ->
      with_private_route_lock(fn() {
        dispatch_private_actor(subject, p, route, raw, msg, resolver)
      })
    _, _ -> refuse("GATEWAY_UNAVAILABLE", "OTP gateway could not start")
  }
}

/// Lossless arguments are separate from the string-only canonical MCP binding
/// fields. An explicitly invalid arguments value never falls back to msg.args.
pub fn private_arguments(
  raw: String,
  msg: wire.NormalizedMessage,
) -> Result(value.Value, types.ToolError) {
  use document <- result.try(
    json.parse(raw, value.decoder())
    |> result.map_error(fn(_) {
      private_error("INVALID_PRIVATE_ARGUMENTS", "Invalid request JSON")
    }),
  )
  let fallback =
    value.Object(list.map(msg.args, fn(pair) { #(pair.0, value.Text(pair.1)) }))
  case value.get(document, "params") {
    Error(_) -> Ok(fallback)
    Ok(params) ->
      case value.get(params, "arguments") {
        Error(_) -> Ok(fallback)
        Ok(value.Object(_) as args) -> Ok(args)
        Ok(_) ->
          Error(private_error(
            "INVALID_PRIVATE_ARGUMENTS",
            "arguments must be an object",
          ))
      }
  }
}

// The frozen wire normalizer accepts only string argument bindings. Project
// those bindings for it, after ingress has validated the ORIGINAL frame. The
// original typed object remains the only source of backend arguments and is
// included in the receipt hash. No identity/meta/version field is rewritten.
fn private_wire_projection(raw: String) -> Option(String) {
  use document <- option.then(
    json.parse(raw, value.decoder()) |> option.from_result,
  )
  use _ <- option.then(case value.get(document, "method") {
    Ok(value.Text("tools/call")) -> Some(Nil)
    _ -> None
  })
  use params <- option.then(value.get(document, "params") |> option.from_result)
  case value.get(params, "arguments") {
    Ok(value.Object(fields)) -> {
      let strings =
        list.filter(fields, fn(pair) {
          case pair.1 {
            value.Text(_) -> True
            _ -> False
          }
        })
      case list.length(strings) == list.length(fields) {
        True -> None
        False ->
          Some(
            document
            |> value.set(
              "params",
              value.set(params, "arguments", value.Object(strings)),
            )
            |> value.encode
            |> json.to_string,
          )
      }
    }
    _ -> None
  }
}

/// Injectable trusted resolver shared by fixtures and production. Both paths
/// run the very same pre-admission, receipt/finish gate, and canonical commit.
pub fn dispatch_private_with_resolver(
  state: GatewayState,
  p: principal.Principal,
  route: String,
  raw: String,
  msg: wire.NormalizedMessage,
  now: Int,
  resolver: PrivateResolver,
) -> #(types.Outcome, GatewayState) {
  case
    prepare_private(
      private_snapshot(state, p),
      p,
      route,
      raw,
      msg,
      now,
      resolver,
    )
  {
    Error(outcome) -> #(outcome, state)
    Ok(prepared) -> commit_private(state, prepared)
  }
}

pub fn private_snapshot(
  state: GatewayState,
  p: principal.Principal,
) -> PrivateSnapshot {
  PrivateSnapshot(
    state.pool,
    state.backends.features,
    state.backends.knowledge.workspace_root,
    dict.get(state.successor_sessions, successor_session_key(p))
      |> option.from_result,
    dict.size(state.successor_sessions),
  )
}

fn prepare_private(
  snapshot: PrivateSnapshot,
  p: principal.Principal,
  route: String,
  raw: String,
  msg: wire.NormalizedMessage,
  now: Int,
  resolver: PrivateResolver,
) -> Result(PreparedPrivateCall, types.Outcome) {
  use _ <- result.try(
    case is_private_route(route) && msg.method == "tools/call" {
      True -> Ok(Nil)
      False -> Error(refuse("UNSUPPORTED_ROUTE", "Private tools/call required"))
    },
  )
  use _ <- result.try(
    case
      candidate_id.is_valid(snapshot.pool.ledger.candidate)
      && snapshot.pool.ledger.candidate == snapshot.features.active_candidate
    {
      True -> Ok(Nil)
      False ->
        Error(refuse(
          "CANDIDATE_EVIDENCE_MISMATCH",
          "Private snapshot candidate mismatch",
        ))
    },
  )
  let #(tool, string_args) = tool_arguments(raw, msg)
  use _ <- result.try(
    private_tool_precheck(route, tool, string_args)
    |> result.map_error(types.Refused),
  )
  use raw_args <- result.try(
    private_arguments(raw, msg) |> result.map_error(types.Refused),
  )
  let current = snapshot.successor
  use binding <- result.try(
    resolver(p, route, tool, raw_args, current)
    |> result.map_error(types.Refused),
  )
  // Preserve every typed/nested argument in the receipt payload hash too. This
  // prevents equal string projections from aliasing different typed requests.
  let args =
    dict.insert(
      string_args,
      "_private_arguments_json",
      json.to_string(value.encode(raw_args)),
    )
  let args = case tool, binding.task_fence, dict.has_key(args, "task_id") {
    "harness_finish", Some(fence), False ->
      dict.insert(args, "task_id", fence.task_id)
    _, _, _ -> args
  }
  let context =
    private_route_context(snapshot.workspace_root, p, route, binding, now)
  // A foreign authenticated principal must not be hidden by the route ticket
  // workspace check, which otherwise precedes principal admission canonically.
  use _ <- result.try(
    case principal.workspace_root(context.principal) == context.workspace_root {
      True -> Ok(Nil)
      False ->
        Error(refuse(
          "PRINCIPAL_WORKSPACE_MISMATCH",
          "Principal workspace root does not match active workspace",
        ))
    },
  )
  use validated_call <- result.try(
    route_convergence.admit_converged(
      context,
      binding.route_grant,
      route,
      tool,
      args,
    )
    |> result.map_error(types.Refused),
  )
  use _ <- result.try(
    case
      route == "successor"
      && current == None
      && snapshot.successor_count >= max_successor_sessions
    {
      True ->
        Error(
          types.Refused(types.ToolError(
            "SUCCESSOR_SESSION_CAPACITY_EXCEEDED",
            "Successor session store capacity exceeded",
            types.Retryable,
          )),
        )
      False -> Ok(Nil)
    },
  )
  // Dry-run the immutable canonical pipeline with a non-effecting sentinel.
  // It checks finish evidence AND receipt replay/conflict/uncertainty before
  // the real backend runs. Discard this probe ledger; only the actor commits.
  let #(probe, _) =
    route_convergence.execute_converged(
      snapshot.pool,
      context,
      binding.route_grant,
      snapshot.features,
      route,
      tool,
      args,
      fn(_, _) { Error("private_execution_pending") },
    )
  let base =
    PreparedPrivateCall(
      context,
      binding.route_grant,
      route,
      tool,
      args,
      Error("private_receipt_replay"),
      None,
      private_ledger_intent_id(validated_call),
      snapshot.pool.ledger.candidate,
      False,
    )
  case probe {
    types.Refused(types.ToolError(
      "WORKER_ISOLATED_FAILURE",
      "private_execution_pending",
      _,
    )) -> {
      let #(output, next) = binding.execute()
      Ok(
        PreparedPrivateCall(
          ..base,
          output: output,
          next_successor: next,
          effect_executed: True,
        ),
      )
    }
    types.Complete(_, _) -> Ok(base)
    outcome -> Error(outcome)
  }
}

/// Mirrors the immutable dispatcher's framed payload/owner identity exactly.
pub fn private_ledger_intent_id(call: admission.ValidatedCall) -> String {
  let payload_hash =
    receipts.hash_payload(call.spec.name, dict.to_list(call.arguments))
  let owner_hash =
    receipts.hash_payload(call.spec.name, [
      #("actor", principal.actor_id(call.principal)),
      #("workspace", principal.workspace_root(call.principal)),
      #("plan_id", option.unwrap(call.plan_id, "")),
      #("task_id", option.unwrap(call.task_id, "")),
      #("attempt", int.to_string(option.unwrap(call.attempt, 0))),
      #("grant_id", option.unwrap(call.grant_id, "")),
    ])
  let logical_id = case dict.get(call.arguments, "intent_id") {
    Ok(id) if id != "" -> id
    _ -> payload_hash
  }
  call.spec.route
  <> ":"
  <> call.spec.name
  <> ":"
  <> owner_hash
  <> ":"
  <> logical_id
}

/// Resolve only reviewed direct sibling roots. Foreign principal roots remain
/// untouched, so the canonical principal/workspace check still refuses them.
pub fn private_route_context(
  gateway_root: String,
  p: principal.Principal,
  route: String,
  binding: PrivateBinding,
  now: Int,
) -> admission.AdmissionContext {
  let ticket_root = case route, binding.route_grant {
    "successor", Some(rg) -> rg.ticket.workspace_root
    _, _ -> gateway_root
  }
  let authorized =
    ticket_root == gateway_root
    || string.starts_with(ticket_root, gateway_root <> "/.uos-workspaces/")
  let principal_root = principal.workspace_root(p)
  case
    authorized
    && { principal_root == gateway_root || principal_root == ticket_root }
  {
    True ->
      admission.AdmissionContext(
        rebind_workspace(p, ticket_root),
        admission.EnforcedMode,
        now,
        ticket_root,
        binding.task_fence,
      )
    False ->
      admission.AdmissionContext(
        p,
        admission.EnforcedMode,
        now,
        gateway_root,
        binding.task_fence,
      )
  }
}

fn rebind_workspace(
  p: principal.Principal,
  root: String,
) -> principal.Principal {
  let rebound = case principal.transport(p) {
    types.Stdio ->
      principal.from_launcher_env(
        principal.actor_id(p),
        principal.client_profile(p),
        root,
        principal.session_id(p),
      )
    types.HttpStreamable ->
      principal.from_http_auth_middleware(
        principal.actor_id(p),
        principal.client_profile(p),
        root,
        principal.session_id(p),
      )
    types.Zenoh ->
      principal.from_signed_zenoh_envelope(
        principal.actor_id(p),
        principal.client_profile(p),
        root,
        principal.session_id(p),
      )
  }
  principal.apply_untrusted_payload_labels(
    rebound,
    principal.untrusted_actor_label(p),
    principal.untrusted_client_label(p),
    principal.untrusted_header_actor(p),
  )
}

/// Cheap in-memory rejection precedes every admission observation/subprocess.
pub fn private_tool_precheck(
  route: String,
  tool: String,
  string_args: dict.Dict(String, String),
) -> Result(types.ToolSpec, types.ToolError) {
  use spec <- result.try(registry.lookup(route, tool))
  use _ <- result.try(registry.verify_schema_digest(spec, spec.input_schema))
  use _ <- result.try(route_convergence.verify_client_schema_pin(
    spec,
    dict.get(string_args, "_client_schema_digest") |> option.from_result,
  ))
  let declared = case route {
    "development" ->
      list.any(launcher.tool_definitions(), fn(t) { t.name == tool })
    "successor" -> list.contains(ops.names, tool)
    _ -> False
  }
  case declared {
    True -> Ok(spec)
    False ->
      Error(private_error(
        "TOOL_NOT_IN_ROUTE_GRANT",
        "Tool is absent from the route's backend list",
      ))
  }
}

fn string_bindings(args: value.Value) -> dict.Dict(String, String) {
  case args {
    value.Object(fields) ->
      fields
      |> list.filter_map(fn(pair) {
        case pair.1 {
          value.Text(text) -> Ok(#(pair.0, text))
          _ -> Error(Nil)
        }
      })
      |> dict.from_list
    _ -> dict.new()
  }
}

fn commit_private(
  state: GatewayState,
  prepared: PreparedPrivateCall,
) -> #(types.Outcome, GatewayState) {
  let #(outcome, pool, backends) =
    server.execute_route_authenticated(
      prepared.context,
      prepared.route_grant,
      state.pool,
      state.backends,
      prepared.route,
      prepared.tool,
      prepared.args,
      fn(_, _) { prepared.output },
    )
  // Successor errors may latch unresolved-operation state. Persist those too;
  // the private lock covers snapshot, execution and this state commit.
  let sessions = case prepared.next_successor {
    Some(next) ->
      dict.insert(
        state.successor_sessions,
        successor_session_key(prepared.context.principal),
        successor_session_record(prepared.context.principal, next),
      )
    None -> state.successor_sessions
  }
  #(
    outcome,
    GatewayState(
      ..state,
      pool: pool,
      backends: backends,
      successor_sessions: sessions,
    ),
  )
}

fn ungranted_private() -> PrivateBinding {
  PrivateBinding(None, None, fn() { #(Error("route_grant_required"), None) })
}

fn live_private_binding(
  p: principal.Principal,
  route: String,
  tool: String,
  args: value.Value,
  current: Option(SuccessorSessionRecord),
) -> Result(PrivateBinding, types.ToolError) {
  use _ <- result.try(private_tool_precheck(route, tool, string_bindings(args)))
  case route {
    "development" ->
      case dev.load_binding() {
        Error(_) -> Ok(ungranted_private())
        Ok(binding) ->
          case binding.worker == principal.actor_id(p) {
            False ->
              Error(private_error(
                "PRINCIPAL_WORKER_MISMATCH",
                "Development binding worker differs from principal",
              ))
            True ->
              case dev.fence(binding) {
                Error(_) -> Ok(ungranted_private())
                Ok(proof) -> {
                  // Coordinator expiry is boot_us, already checked by dev.fence.
                  // Only the UTC Sa-plan deadline can be projected into MCP UTC ms.
                  let until = proof.lease_until_ns / 1_000_000
                  let ticket =
                    admission.GrantTicket(
                      "dev:"
                        <> binding.session
                        <> ":"
                        <> binding.plan
                        <> ":"
                        <> binding.task
                        <> ":"
                        <> int.to_string(binding.epoch),
                      types.TaskScopedMutation,
                      False,
                      until,
                      dev.root,
                    )
                  Ok(
                    PrivateBinding(
                      Some(route_convergence.RouteGrant(
                        "development",
                        list.map(launcher.tool_definitions(), fn(t) { t.name }),
                        ticket,
                      )),
                      Some(admission.TaskFence(
                        binding.plan,
                        binding.task,
                        binding.worker,
                        binding.attempt,
                        admission.TaskExecuting,
                        until,
                        Some(ticket),
                      )),
                      fn() {
                        #(
                          launcher.call_task_bound(tool, args)
                            |> result.map(json.to_string),
                          None,
                        )
                      },
                    ),
                  )
                }
              }
          }
      }
    "successor" ->
      case harness_admission.load() {
        Error(_) -> Ok(ungranted_private())
        Ok(grant) ->
          case grant.worker == principal.actor_id(p) {
            False ->
              Error(private_error(
                "PRINCIPAL_WORKER_MISMATCH",
                "Successor grant worker differs from principal",
              ))
            True -> {
              use successor <- result.try(successor_session_for_principal(
                p,
                current,
                grant,
              ))
              let checked = {
                use _ <- result.try(native_backend.initialize(
                  grant.path,
                  grant.digest,
                ))
                use _ <- result.try(harness_admission.check(grant))
                successor_binding(grant, successor, tool, args)
              }
              checked
              |> result.map_error(fn(reason) {
                private_error("ROUTE_GRANT_REQUIRED", reason)
              })
            }
          }
      }
    _ -> Error(private_error("UNSUPPORTED_ROUTE", route))
  }
}

fn successor_binding(
  grant: harness_admission.Grant,
  state: successor_mcp.State,
  tool: String,
  args: value.Value,
) -> Result(PrivateBinding, String) {
  use root <- result.try(harness_admission.source_root(grant))
  let ticket = successor_ticket(grant, root)
  use fence <- result.try(case state.execution {
    Some(execution) -> {
      use proof <- result.try(harness_admission.fence(execution, 0))
      Ok(
        Some(admission.TaskFence(
          execution.binding.plan,
          execution.binding.task,
          execution.binding.worker,
          execution.binding.attempt,
          admission.TaskExecuting,
          int.min(grant.expires_us / 1000, proof.lease_until_ns / 1_000_000),
          Some(ticket),
        )),
      )
    }
    None ->
      case preattach_tool(tool) {
        False -> Ok(None)
        True -> {
          let observed_now = now_ms()
          use observed <- result.try(
            observe_preattach_scope(grant, tool, args, observed_now, fn(scope) {
              // This binding is only a read selector, never an execution permit.
              dev.read_task(dev.Binding(
                "development",
                scope.plan,
                scope.task,
                grant.worker,
                0,
                grant.session,
                0,
              ))
            }),
          )
          Ok(
            option.map(observed, fn(selected) {
              project_observed_preattach_fence(
                grant,
                selected.0.plan,
                selected.0.task,
                selected.1,
                observed_now,
                root,
              ).1
            }),
          )
        }
      }
  })
  Ok(
    PrivateBinding(
      Some(route_convergence.RouteGrant("successor", ops.names, ticket)),
      fence,
      fn() {
        let #(next, output) = successor_mcp.call(state, tool, args)
        #(result.map(output, json.to_string), Some(next))
      },
    ),
  )
}

fn preattach_tool(tool: String) -> Bool {
  list.contains(
    [
      "harness_status",
      "harness_clock",
      "harness_heartbeat",
      "harness_claim",
      "harness_attach",
      "harness_reconcile",
      "harness_assess",
    ],
    tool,
  )
}

fn successor_ticket(
  grant: harness_admission.Grant,
  root: String,
) -> admission.GrantTicket {
  admission.GrantTicket(
    grant.id,
    types.TaskScopedMutation,
    False,
    grant.expires_us / 1000,
    root,
  )
}

/// A projection of observed facts, not an admission decision. UTC task expiry
/// stays separate from the reviewed grant window; canonical admission compares
/// both to now_ms. The clock argument is retained for the explicit seam.
pub fn project_observed_preattach_fence(
  grant: harness_admission.Grant,
  plan: String,
  task: String,
  row: dev.TaskRecord,
  _now_ms: Int,
  ticket_root: String,
) -> #(admission.GrantTicket, admission.TaskFence) {
  let ticket = successor_ticket(grant, ticket_root)
  let state = case row.state {
    "executing" -> admission.TaskExecuting
    "completed" -> admission.TaskCompleted
    _ -> admission.TaskAvailable
  }
  let lease_until = case row.lease_until_ns {
    Some(deadline) if deadline > 0 ->
      int.min(grant.expires_us / 1000, deadline / 1_000_000)
    _ -> 0
  }
  #(
    ticket,
    admission.TaskFence(
      plan,
      task,
      option.unwrap(row.worker, ""),
      row.attempt,
      state,
      lease_until,
      Some(ticket),
    ),
  )
}

/// Task-acting bootstrap calls must name their exact reviewed scope. General
/// bootstrap observations prefer a real owned live task, then retain the first
/// scope's real non-executing record (or no fence if it cannot be observed).
pub fn observe_preattach_scope(
  grant: harness_admission.Grant,
  tool: String,
  args: value.Value,
  now: Int,
  read_task: fn(harness_admission.Scope) -> Result(dev.TaskRecord, String),
) -> Result(Option(#(harness_admission.Scope, dev.TaskRecord)), String) {
  let owner = grant.worker
  use _ <- result.try(harness_admission.require(
    preattach_tool(tool),
    "not_a_preattach_tool",
  ))
  case value.get(args, "plan"), value.get(args, "task") {
    Ok(value.Text(plan)), Ok(value.Text(task)) -> {
      use scope <- result.try(harness_admission.lookup(grant, plan, task))
      use row <- result.try(read_task(scope))
      Ok(Some(#(scope, row)))
    }
    Error(_), Error(_) ->
      case
        list.contains(
          ["harness_claim", "harness_attach", "harness_assess"],
          tool,
        )
      {
        True -> Error("explicit_plan_and_task_required")
        False ->
          case grant.scopes {
            [] -> Error("grant_scope_missing")
            [first, ..rest] -> {
              let first_row = read_task(first) |> option.from_result
              case first_row {
                Some(row)
                  if row.state == "executing" && row.worker == Some(owner)
                ->
                  case observed_live_lease(row, now) {
                    True -> Ok(Some(#(first, row)))
                    False ->
                      Ok(option.or(
                        scan_preattach_scopes(
                          rest,
                          grant.worker,
                          now,
                          read_task,
                        ),
                        option.map(first_row, fn(row) { #(first, row) }),
                      ))
                  }
                _ ->
                  Ok(option.or(
                    scan_preattach_scopes(rest, grant.worker, now, read_task),
                    option.map(first_row, fn(row) { #(first, row) }),
                  ))
              }
            }
          }
      }
    _, _ -> Error("explicit_plan_and_task_required")
  }
}

fn observed_live_lease(row: dev.TaskRecord, now: Int) -> Bool {
  case row.lease_until_ns {
    Some(deadline) -> deadline > now * 1_000_000
    None -> False
  }
}

fn scan_preattach_scopes(
  scopes: List(harness_admission.Scope),
  worker: String,
  now: Int,
  read_task: fn(harness_admission.Scope) -> Result(dev.TaskRecord, String),
) -> Option(#(harness_admission.Scope, dev.TaskRecord)) {
  case scopes {
    [] -> None
    [scope, ..rest] ->
      case read_task(scope) {
        Ok(row) if row.state == "executing" && row.worker == Some(worker) ->
          case observed_live_lease(row, now) {
            True -> Some(#(scope, row))
            False -> scan_preattach_scopes(rest, worker, now, read_task)
          }
        _ -> scan_preattach_scopes(rest, worker, now, read_task)
      }
  }
}

pub fn successor_session_record(
  p: principal.Principal,
  state: successor_mcp.State,
) -> SuccessorSessionRecord {
  SuccessorSessionRecord(
    principal.actor_id(p),
    principal.client_profile(p).name,
    principal.transport(p),
    principal.session_id(p),
    state,
  )
}

/// UTF-8 byte length framing keeps separators in any identity field harmless.
pub fn successor_session_key(p: principal.Principal) -> String {
  let transport = case principal.transport(p) {
    types.Stdio -> "stdio"
    types.HttpStreamable -> "http"
    types.Zenoh -> "zenoh"
  }
  [
    principal.actor_id(p),
    transport,
    principal.client_profile(p).name,
    principal.session_id(p),
  ]
  |> list.map(fn(field) {
    int.to_string(string.byte_size(field)) <> ":" <> field
  })
  |> string.concat
}

pub fn successor_session_for_principal(
  p: principal.Principal,
  current: Option(SuccessorSessionRecord),
  grant: harness_admission.Grant,
) -> Result(successor_mcp.State, types.ToolError) {
  use state <- result.try(case current {
    None -> Ok(None)
    Some(record) ->
      case
        record.owner_actor == principal.actor_id(p)
        && record.owner_client == principal.client_profile(p).name
        && record.owner_transport == principal.transport(p)
        && record.owner_session == principal.session_id(p)
      {
        False ->
          Error(private_error(
            "CROSS_PRINCIPAL_SUCCESSOR_SESSION_FORBIDDEN",
            "Recorded successor owner differs from the observed principal",
          ))
        True -> Ok(Some(record.state))
      }
  })
  successor_session(state, grant)
  |> result.map_error(fn(reason) {
    private_error("SUCCESSOR_SESSION_GRANT_CHANGED", reason)
  })
}

/// Session continuity is tied to the freshly verified launcher grant, not to
/// transport-supplied session strings alone. Kept pure for adversarial tests.
pub fn successor_session(
  current: Option(successor_mcp.State),
  grant: harness_admission.Grant,
) -> Result(successor_mcp.State, String) {
  case current {
    None -> Ok(successor_mcp.initial(grant))
    Some(state) ->
      case state.grant.id == grant.id && state.grant.digest == grant.digest {
        True -> Ok(state)
        False -> Error("successor_session_grant_changed")
      }
  }
}

// Only the caller process runs bounded commands; the state actor receives a
// check-id-bound result and never invokes a verifier or waits for its process.
fn run_verification_check(
  root: String,
  check_id: verification.CheckId,
) -> verification.CheckRunnerResult {
  let command = case check_id {
    verification.PreflightToolchain ->
      Some(#(["tools/preflight", "--max-age", "900", "--quiet"], 25_000))
    verification.GateChecklist -> Some(#(["tools/km-gate", "--gate"], 15_000))
    verification.BoundedZ3Control ->
      Some(#(
        [
          "-c",
          "printf '(assert (= (+ 1 1) 2))(check-sat)\\n' | ./tools/z3 -in",
        ],
        5000,
      ))
    _ -> None
  }
  case command {
    None -> verification.ProverMissing("Check not bound on live public gateway")
    Some(#(args, budget_ms)) -> {
      let unit = atom.create("millisecond")
      let started = monotonic_time(unit)
      let output = run_bounded_cd("/bin/bash", args, root, budget_ms)
      let duration_ms = monotonic_time(unit) - started
      case output {
        Ok(#(exit_code, stdout)) ->
          verification.CheckExecuted(exit_code, stdout, duration_ms)
        Error("timeout") | Error("guardian_timeout") ->
          verification.CheckTimedOut(budget_ms)
        Error(reason) -> verification.ProverMissing(reason)
      }
    }
  }
}

fn refuse(code: String, reason: String) -> types.Outcome {
  types.Refused(types.ToolError(code, reason, types.NonRetryable))
}

fn complete(
  state: GatewayState,
  route: String,
  tool: String,
  body: json.Json,
) -> types.Outcome {
  let text = json.to_string(body)
  types.Complete(
    text,
    types.EvidenceRecord(
      state.pool.ledger.candidate,
      route,
      tool,
      "declared",
      "implemented",
      "observed",
      "unrun",
      "not_admitted",
      files.digest(text),
    ),
  )
}

fn view_for_route(route: String) -> types.AccessView {
  case route {
    "development" -> types.PrivateDevelopmentView
    "successor" -> types.PrivateSuccessorView
    _ -> types.OperationalView
  }
}

fn profile_for(version: String) -> types.ProtocolProfile {
  case version {
    "2024-11-05" -> types.Legacy20241105
    _ -> types.Modern20260728
  }
}

fn protocol_version(profile: types.ProtocolProfile) -> String {
  case profile {
    types.Legacy20241105 -> "2024-11-05"
    types.Modern20260728 -> "2026-07-28"
  }
}

fn initialize_json(
  profile: types.ProtocolProfile,
  requested_version: String,
) -> json.Json {
  json.object([
    #("protocolVersion", json.string(requested_version)),
    #(
      "capabilities",
      json.object([
        #("tools", json.object([#("listChanged", json.bool(False))])),
        #(
          "resources",
          json.object([
            #("subscribe", json.bool(True)),
            #("listChanged", json.bool(False)),
          ]),
        ),
        #("prompts", json.object([#("listChanged", json.bool(False))])),
        #("logging", json.object([])),
        #("completions", json.object([])),
        ..case profile {
          types.Modern20260728 -> [#("tasks", json.object([]))]
          types.Legacy20241105 -> []
        }
      ]),
    ),
    #(
      "serverInfo",
      json.object([
        #("name", json.string("uos-mcp-unified-gateway")),
        #("version", json.string("1.0.0")),
      ]),
    ),
  ])
}

fn raw_string(raw: String, path: List(String), fallback: String) -> String {
  json.parse(raw, decode.at(path, decode.string))
  |> result.unwrap(fallback)
}

fn raw_declares_tasks_capability(raw: String) -> Bool {
  case json.parse(raw, value.decoder()) {
    Error(_) -> False
    Ok(body) -> {
      let capabilities =
        body
        |> value.get("params")
        |> result.try(fn(params) { value.get(params, "capabilities") })
      let tasks =
        capabilities
        |> result.try(fn(caps) { value.get(caps, "tasks") })
      let experimental_tasks =
        capabilities
        |> result.try(fn(caps) { value.get(caps, "experimental") })
        |> result.try(fn(experimental) { value.get(experimental, "tasks") })
      list.any([tasks, experimental_tasks], fn(found) {
        case found {
          Ok(value.Null) | Ok(value.Boolean(False)) | Error(_) -> False
          Ok(_) -> True
        }
      })
    }
  }
}

fn scoped_subscription_id(
  p: principal.Principal,
  raw_id: String,
  uri: String,
) -> String {
  let prefix = principal.actor_id(p) <> ":"
  case string.trim(raw_id) == "" {
    True -> prefix <> uri
    False ->
      case string.starts_with(raw_id, prefix) {
        True -> raw_id
        False -> prefix <> raw_id
      }
  }
}

fn argument(
  args: dict.Dict(String, String),
  name: String,
  fallback: String,
) -> String {
  dict.get(args, name) |> result.unwrap(fallback)
}

fn tool_arguments(
  raw: String,
  msg: wire.NormalizedMessage,
) -> #(String, dict.Dict(String, String)) {
  let args = dict.from_list(msg.args)
  let tool =
    raw_string(
      raw,
      ["params", "name"],
      argument(args, "tool", argument(args, "name", "")),
    )
  let args = case
    tool == "sa_plan_status_for" && !dict.has_key(args, "plan_id")
  {
    True ->
      dict.insert(args, "plan_id", argument(args, "plan", completion_plan))
    False -> args
  }
  let args = case tool == "preflight_check" && !dict.has_key(args, "check_id") {
    True -> dict.insert(args, "check_id", "preflight_toolchain")
    False -> args
  }
  #(tool, args)
}

/// Shared state transition used by supervised ingress and isolated development fixtures.
pub fn dispatch_normalized(
  state: GatewayState,
  p: principal.Principal,
  profile: types.ProtocolProfile,
  route: String,
  raw: String,
  msg: wire.NormalizedMessage,
  now: Int,
) -> #(types.Outcome, GatewayState) {
  case msg.method == "tools/call" && is_private_route(route) {
    True ->
      dispatch_private_with_resolver(
        state,
        p,
        route,
        raw,
        msg,
        now,
        live_private_binding,
      )
    False -> dispatch_non_private(state, p, profile, route, raw, msg, now, None)
  }
}

fn dispatch_non_private(
  state: GatewayState,
  p: principal.Principal,
  profile: types.ProtocolProfile,
  route: String,
  raw: String,
  msg: wire.NormalizedMessage,
  now: Int,
  prefetched_gateway_alive: Option(Bool),
) -> #(types.Outcome, GatewayState) {
  let args = dict.from_list(msg.args)
  case msg.method {
    "tools/call" if route == "development" || route == "successor" -> #(
      refuse(
        "PRIVATE_PREPARATION_REQUIRED",
        "Private execution belongs to the ingress caller",
      ),
      state,
    )
    "initialize" -> {
      let requested =
        raw_string(
          raw,
          ["params", "protocolVersion"],
          protocol_version(profile),
        )
      case version.negotiate(requested) {
        Error(error) -> #(types.Refused(error), state)
        Ok(negotiated_profile) -> {
          let session = principal.session_id(p)
          case
            negotiated_profile == types.Modern20260728
            && !dict.has_key(state.negotiated_task_sessions, session)
            && dict.size(state.negotiated_task_sessions) >= 1024
          {
            True -> #(
              types.Refused(types.ToolError(
                "TASK_NEGOTIATION_CAPACITY_EXCEEDED",
                "Task negotiation session store capacity exceeded",
                types.Retryable,
              )),
              state,
            )
            False -> {
              let sessions = case negotiated_profile {
                types.Modern20260728 ->
                  dict.insert(
                    state.negotiated_task_sessions,
                    session,
                    raw_declares_tasks_capability(raw),
                  )
                types.Legacy20241105 ->
                  dict.delete(state.negotiated_task_sessions, session)
              }
              #(
                complete(
                  state,
                  route,
                  msg.method,
                  initialize_json(negotiated_profile, requested),
                ),
                GatewayState(..state, negotiated_task_sessions: sessions),
              )
            }
          }
        }
      }
    }
    "ping"
    | "notifications/initialized"
    | "notifications/cancelled"
    | "logging/setLevel" -> #(
      complete(state, route, msg.method, json.object([])),
      state,
    )
    "completion/complete" -> #(
      complete(
        state,
        route,
        msg.method,
        json.object([
          #(
            "completion",
            json.object([
              #("values", json.preprocessed_array([])),
              #("total", json.int(0)),
              #("hasMore", json.bool(False)),
            ]),
          ),
        ]),
      ),
      state,
    )
    "discovery/list" ->
      case profile {
        types.Legacy20241105 -> #(
          refuse(
            "PROFILE_METHOD_MISMATCH",
            "discovery/list requires modern MCP profile",
          ),
          state,
        )
        types.Modern20260728 ->
          case json.parse(modern.discovery_metadata(), value.decoder()) {
            Ok(metadata) -> #(
              complete(state, route, msg.method, value.encode(metadata)),
              state,
            )
            Error(_) -> #(
              refuse(
                "INVALID_DISCOVERY_METADATA",
                "Modern discovery metadata is invalid JSON",
              ),
              state,
            )
          }
      }
    "tools/list" -> {
      case list.contains(["public", "development", "successor"], route) {
        False -> #(refuse("UNSUPPORTED_ROUTE", route), state)
        True -> #(
          complete(
            state,
            route,
            msg.method,
            json.object([
              #(
                "tools",
                json.array(
                  registry.definitions(profile, view_for_route(route)),
                  fn(spec) {
                    json.object([
                      #("name", json.string(spec.name)),
                      #("description", json.string(spec.description)),
                      #("inputSchema", spec.input_schema),
                    ])
                  },
                ),
              ),
            ]),
          ),
          state,
        )
      }
    }
    "tools/call" -> {
      let #(tool, args) = tool_arguments(raw, msg)
      let root = state.backends.knowledge.workspace_root
      let backends =
        server.ServerBackends(
          ..state.backends,
          observation: observation(
            state.pool.ledger.candidate,
            now,
            option.unwrap(
              prefetched_gateway_alive,
              supervised_gateway_pids_alive(state.supervised_gateway),
            ),
            case prefetched_gateway_alive {
              Some(_) -> "gateway_ping"
              None -> "gateway_pid_liveness"
            },
          ),
        )
      // This arm is public-only. Caller fence/grant strings are bindings, not evidence of a live lease
      // or authority. No mutation grant is fabricated by the transport layer.
      let fence = case
        list.any(["plan_id", "task_id", "attempt", "grant_id"], fn(key) {
          dict.has_key(args, key)
        })
        && dict.has_key(args, "task_id")
      {
        True ->
          Some(admission.TaskFence(
            argument(args, "plan_id", ""),
            argument(args, "task_id", ""),
            principal.actor_id(p),
            int.parse(argument(args, "attempt", "0")) |> result.unwrap(0),
            admission.TaskAvailable,
            0,
            None,
          ))
        False -> None
      }
      let context =
        admission.AdmissionContext(p, admission.EnforcedMode, now, root, fence)
      let #(outcome, pool, updated) =
        server.execute_route_authenticated(
          context,
          None,
          state.pool,
          backends,
          route,
          tool,
          args,
          fn(_, _) { Error("Private calls require caller-side admission") },
        )
      #(outcome, GatewayState(..state, pool: pool, backends: updated))
    }
    "resources/list" ->
      case
        resources.list_resources(
          state.resources,
          state.resource_cache,
          p,
          100,
          0,
        )
      {
        Error(error) -> #(types.Refused(error), state)
        Ok(#(entries, cache)) -> #(
          complete(
            state,
            route,
            msg.method,
            json.object([#("resources", json.array(entries, encode_resource))]),
          ),
          GatewayState(..state, resource_cache: cache),
        )
      }
    "resources/templates/list" ->
      case resources.list_templates(state.resources, p) {
        Error(error) -> #(types.Refused(error), state)
        Ok(templates) -> #(
          complete(
            state,
            route,
            msg.method,
            json.object([
              #(
                "resourceTemplates",
                json.array(templates, fn(t) {
                  json.object([
                    #("uriTemplate", json.string(t.uri_template)),
                    #("name", json.string(t.name)),
                    #("description", json.string(t.description)),
                  ])
                }),
              ),
            ]),
          ),
          state,
        )
      }
    "resources/read" -> {
      let uri = raw_string(raw, ["params", "uri"], argument(args, "uri", ""))
      case
        resources.read_resource(state.resources, state.resource_cache, p, uri)
      {
        Error(error) -> #(types.Refused(error), state)
        Ok(#(entry, cache)) -> #(
          complete(
            state,
            route,
            msg.method,
            json.object([
              #(
                "contents",
                json.preprocessed_array([
                  json.object([
                    #("uri", json.string(entry.uri)),
                    #("mimeType", json.string(entry.mime_type)),
                    #("text", json.string(entry.content)),
                  ]),
                ]),
              ),
            ]),
          ),
          GatewayState(..state, resource_cache: cache),
        )
      }
    }
    "resources/subscribe" -> {
      let uri = raw_string(raw, ["params", "uri"], argument(args, "uri", ""))
      case
        resources.read_resource(state.resources, state.resource_cache, p, uri)
      {
        Error(err) -> #(types.Refused(err), state)
        Ok(_) -> {
          let sub_id =
            scoped_subscription_id(
              p,
              raw_string(raw, ["params", "subscriptionId"], ""),
              uri,
            )
          case
            subscriptions.subscribe(
              state.subscriptions,
              profile,
              p,
              sub_id,
              subscriptions.ResourceSubscription(uri),
            )
          {
            Ok(next_subs) -> #(
              complete(
                state,
                route,
                msg.method,
                json.object([
                  #("subscriptionId", json.string(sub_id)),
                  #("uri", json.string(uri)),
                ]),
              ),
              GatewayState(..state, subscriptions: next_subs),
            )
            Error(err) -> #(types.Refused(err), state)
          }
        }
      }
    }
    "resources/unsubscribe" -> {
      let uri = raw_string(raw, ["params", "uri"], argument(args, "uri", ""))
      let sub_id =
        scoped_subscription_id(
          p,
          raw_string(raw, ["params", "subscriptionId"], ""),
          uri,
        )
      case subscriptions.unsubscribe(state.subscriptions, profile, p, sub_id) {
        Ok(next_subs) -> #(
          complete(
            state,
            route,
            msg.method,
            json.object([
              #("unsubscribed", json.bool(True)),
              #("subscriptionId", json.string(sub_id)),
            ]),
          ),
          GatewayState(..state, subscriptions: next_subs),
        )
        Error(err) -> #(types.Refused(err), state)
      }
    }
    "tasks/create" | "tasks/get" | "tasks/result" | "tasks/cancel" ->
      case profile {
        types.Legacy20241105 -> #(
          refuse(
            "PROFILE_METHOD_MISMATCH",
            msg.method <> " requires modern MCP profile",
          ),
          state,
        )
        types.Modern20260728 ->
          case msg.method {
            "tasks/create" -> {
              let plan_id =
                raw_string(
                  raw,
                  ["params", "planId"],
                  argument(args, "plan_id", ""),
                )
              let task_id =
                raw_string(
                  raw,
                  ["params", "taskId"],
                  argument(args, "task_id", ""),
                )
              let record =
                executing_task_record(
                  state.backends.planning_read,
                  plan_id,
                  task_id,
                )
              let negotiated =
                dict.get(
                  state.negotiated_task_sessions,
                  principal.session_id(p),
                )
                |> result.unwrap(False)
              case
                task_extension.issue_durable_handle(
                  profile,
                  negotiated,
                  p,
                  record,
                  now + 3_600_000,
                  now,
                )
              {
                Error(err) -> #(types.Refused(err), state)
                Ok(handle) -> {
                  case
                    !task_extension.has_handle(state.tasks, handle.handle_id)
                    && task_extension.size(state.tasks)
                    >= task_extension.max_task_handles
                  {
                    True -> #(
                      types.Refused(types.ToolError(
                        "TASK_HANDLE_CAPACITY_EXCEEDED",
                        "Task handle store capacity exceeded",
                        types.Retryable,
                      )),
                      state,
                    )
                    False -> {
                      let next_tasks =
                        task_extension.register(
                          state.tasks,
                          handle.handle_id,
                          record,
                        )
                      #(
                        complete(
                          state,
                          route,
                          msg.method,
                          json.object([
                            #("handleId", json.string(handle.handle_id)),
                            #("planId", json.string(handle.plan_id)),
                            #("taskId", json.string(handle.task_id)),
                            #("attempt", json.int(handle.attempt)),
                            #("expiresAtMs", json.int(handle.expires_at_ms)),
                          ]),
                        ),
                        GatewayState(..state, tasks: next_tasks),
                      )
                    }
                  }
                }
              }
            }
            "tasks/get" | "tasks/result" -> {
              let handle_id =
                raw_string(
                  raw,
                  ["params", "handleId"],
                  argument(args, "handle_id", ""),
                )
              case task_extension.lookup(state.tasks, handle_id) {
                Error(err) -> #(types.Refused(err), state)
                Ok(record) ->
                  case record.owner_actor == principal.actor_id(p) {
                    False -> #(
                      refuse(
                        "CROSS_PRINCIPAL_TASK_HANDLE_FORBIDDEN",
                        "Task record is owned by another principal",
                      ),
                      state,
                    )
                    True -> #(
                      complete(
                        state,
                        route,
                        msg.method,
                        json.object([
                          #("handleId", json.string(handle_id)),
                          #("planId", json.string(record.plan_id)),
                          #("taskId", json.string(record.task_id)),
                          #("attempt", json.int(record.attempt)),
                          #(
                            "state",
                            json.string(task_state_name(record.lifecycle)),
                          ),
                        ]),
                      ),
                      state,
                    )
                  }
              }
            }
            _ -> {
              let handle_id =
                raw_string(
                  raw,
                  ["params", "handleId"],
                  argument(args, "handle_id", ""),
                )
              case task_extension.request_cancel(state.tasks, p, handle_id) {
                Error(err) -> #(types.Refused(err), state)
                Ok(#(receipt, next_tasks)) -> #(
                  complete(
                    state,
                    route,
                    msg.method,
                    json.object([
                      #("handleId", json.string(receipt.handle_id)),
                      #(
                        "cancelAcknowledged",
                        json.bool(receipt.cancel_acknowledged),
                      ),
                      #("effectStopped", json.bool(receipt.effect_stopped)),
                    ]),
                  ),
                  GatewayState(..state, tasks: next_tasks),
                )
              }
            }
          }
      }
    "prompts/list" -> #(
      complete(
        state,
        route,
        msg.method,
        json.object([
          #(
            "prompts",
            json.array(prompts.list_prompts(state.prompts), fn(prompt) {
              json.object([
                #("name", json.string(prompt.name)),
                #("description", json.string(prompt.description)),
                #(
                  "arguments",
                  json.array(prompt.required_args, fn(name) {
                    json.object([
                      #("name", json.string(name)),
                      #("required", json.bool(True)),
                    ])
                  }),
                ),
              ])
            }),
          ),
        ]),
      ),
      state,
    )
    "prompts/get" ->
      case
        prompts.get_prompt(
          state.prompts,
          raw_string(raw, ["params", "name"], argument(args, "name", "")),
          args,
        )
      {
        Error(error) -> #(types.Refused(error), state)
        Ok(prompt) -> #(
          complete(
            state,
            route,
            msg.method,
            json.object([
              #("description", json.string(prompt.name)),
              #(
                "messages",
                json.array(prompt.messages, fn(text) {
                  json.object([
                    #("role", json.string("user")),
                    #(
                      "content",
                      json.object([
                        #("type", json.string("text")),
                        #("text", json.string(text)),
                      ]),
                    ),
                  ])
                }),
              ),
              #("advisory_only", json.bool(True)),
              #("effect_authority", json.bool(False)),
            ]),
          ),
          state,
        )
      }
    _ -> #(
      refuse("METHOD_NOT_FOUND", "Unknown MCP method: " <> msg.method),
      state,
    )
  }
}

fn executing_task_record(
  store: planning_read.PlanningReadStore,
  plan_id: String,
  task_id: String,
) -> task_extension.SaPlanTaskRecord {
  // Preserve the canonical worker and attempt, including a foreign owner so
  // issue_durable_handle can refuse it. Never invent persistence or ownership.
  let row = case store {
    planning_read.AvailableStore(_, rows) ->
      list.find(rows, fn(row) {
        row.plan_id == plan_id
        && row.task_id == task_id
        && row.state == "executing"
      })
      |> option.from_result
    planning_read.UnavailableStore(_) -> None
  }
  case row {
    Some(row) ->
      task_extension.SaPlanTaskRecord(
        plan_id,
        task_id,
        row.worker,
        row.attempt,
        True,
        task_extension.RunningTask,
      )
    None ->
      task_extension.SaPlanTaskRecord(
        plan_id,
        task_id,
        "",
        0,
        False,
        task_extension.PendingTask,
      )
  }
}

fn task_state_name(state: task_extension.SaTaskState) -> String {
  case state {
    task_extension.PendingTask -> "pending"
    task_extension.RunningTask -> "running"
    task_extension.CancelRequested -> "cancel_requested"
    task_extension.CancelledStopped -> "cancelled_stopped"
    task_extension.CompletedTask -> "completed"
    task_extension.FailedTask -> "failed"
  }
}

fn encode_resource(entry: resources.ResourceEntry) -> json.Json {
  json.object([
    #("uri", json.string(entry.uri)),
    #("name", json.string(entry.title)),
    #("mimeType", json.string(entry.mime_type)),
  ])
}

/// Shared HTTP authentication and origin configuration for ingress and its web wrapper.
pub fn http_auth_config() -> http_auth.AuthConfig {
  http_auth.AuthConfig(
    approved_origins: string.split(
      env(
        "UOS_MCP_HTTP_APPROVED_ORIGINS",
        "https://nas-1.tail55d152.ts.net:4101,https://vm-1.tail55d152.ts.net:8443,https://nas-1.tail55d152.ts.net",
      ),
      ",",
    )
      |> list.map(string.trim),
    expected_issuer: env("UOS_MCP_HTTP_ISSUER", default_issuer),
    expected_audience: env("UOS_MCP_HTTP_AUDIENCE", default_issuer <> "/mcp"),
    required_scope: env("UOS_MCP_HTTP_SCOPE", "mcp:operational"),
    signing_secret: env("UOS_MCP_HTTP_SIGNING_SECRET", ""),
  )
}

pub fn handle_http_request(
  method: String,
  path: String,
  headers: List(#(String, String)),
  body: String,
) -> #(Int, List(#(String, String)), String) {
  handle_http_with_config(
    method,
    path,
    headers,
    body,
    http_auth_config(),
    now_ms(),
  )
}

pub fn handle_http_with_config(
  method: String,
  path: String,
  headers: List(#(String, String)),
  body: String,
  config: http_auth.AuthConfig,
  now_ms: Int,
) -> #(Int, List(#(String, String)), String) {
  let _ = ensure_started()
  let profile =
    profile_for(
      http_auth.header(headers, "mcp-protocol-version") |> result.unwrap(""),
    )
  let route =
    http_auth.header(headers, "uos-mcp-route")
    |> result.unwrap(
      http_auth.header(headers, "x-uos-mcp-route") |> result.unwrap("public"),
    )
  let handler = fn(p, _clean, msg) {
    case route {
      "public" -> dispatch_actor(p, profile, route, body, msg, now_ms)
      "development" ->
        case
          http_auth.token_has_scope(config, headers, "mcp:development", now_ms)
        {
          True -> dispatch_actor(p, profile, route, body, msg, now_ms)
          False ->
            refuse(
              "HTTP_ROUTE_SCOPE_FORBIDDEN",
              "Token lacks mcp:development scope",
            )
        }
      "successor" ->
        case
          http_auth.token_has_scope(config, headers, "mcp:successor", now_ms)
        {
          True -> dispatch_actor(p, profile, route, body, msg, now_ms)
          False ->
            refuse(
              "HTTP_ROUTE_SCOPE_FORBIDDEN",
              "Token lacks mcp:successor scope",
            )
        }
      _ -> refuse("UNSUPPORTED_ROUTE", route)
    }
  }
  let response =
    http.handle(
      http.HttpRequest(method, path, headers, body),
      config,
      profile,
      now_ms,
      config.expected_audience,
      [config.expected_issuer],
      handler,
    )
  // Only retry the string-only normalization failure, after the original
  // request passed HTTP auth, credentials, identity, byte and depth checks.
  let response = case
    method == "POST"
    && path == "/mcp"
    && is_private_route(route)
    && response.status == 400
    && response.body == "{\"error\":\"MALFORMED_JSONRPC\"}"
  {
    False -> response
    True ->
      case private_wire_projection(body) {
        None -> response
        Some(projected) ->
          http.handle(
            http.HttpRequest(method, path, headers, projected),
            config,
            profile,
            now_ms,
            config.expected_audience,
            [config.expected_issuer],
            handler,
          )
      }
  }
  #(response.status, response.headers, response.body)
}

pub fn handle_zenoh_with_secret(
  shared_secret: String,
  expected_client_id: String,
  profile: types.ProtocolProfile,
  envelope: zenoh_transport.SignedZenohEnvelope,
  now_ms: Int,
) -> Result(Option(#(String, String)), types.ToolError) {
  zenoh_transport.handle_envelope(
    shared_secret: shared_secret,
    supports_subscriptions: True,
    profile: profile,
    expected_client_id: expected_client_id,
    envelope: envelope,
    handler: fn(p, msg) {
      dispatch_actor(p, profile, "public", envelope.payload, msg, now_ms)
    },
  )
}

fn envelope_decoder(
  topic: String,
) -> decode.Decoder(zenoh_transport.SignedZenohEnvelope) {
  use topic <- decode.optional_field("topic", topic, decode.string)
  use reply <- decode.field("reply_topic", decode.string)
  use actor <- decode.field("sender_actor", decode.string)
  use client <- decode.field("client_name", decode.string)
  use root <- decode.field("workspace_root", decode.string)
  use session <- decode.field("session_id", decode.string)
  use payload <- decode.field("payload", decode.string)
  use signature <- decode.field("signature", decode.string)
  decode.success(zenoh_transport.SignedZenohEnvelope(
    topic,
    reply,
    actor,
    client,
    root,
    session,
    payload,
    signature,
  ))
}

pub fn handle_zenoh_raw(
  topic: String,
  payload: String,
) -> Option(#(String, String)) {
  zenoh_raw_with_secret(topic, payload, env("UOS_MCP_ZENOH_SHARED_SECRET", ""))
}

fn zenoh_raw_with_secret(
  topic: String,
  payload: String,
  secret: String,
) -> Option(#(String, String)) {
  case
    string.byte_size(payload) <= 1_048_576 && safe_zenoh_request_topic(topic)
  {
    False -> None
    True ->
      case string.split(topic, "/") {
        ["indrajaal", "mcp", "request", client_id, _] ->
          case json.parse(payload, envelope_decoder(topic)) {
            Ok(envelope) if envelope.topic == topic ->
              handle_zenoh_with_secret(
                secret,
                client_id,
                profile_for(raw_string(
                  envelope.payload,
                  ["params", "protocolVersion"],
                  "2026-07-28",
                )),
                envelope,
                now_ms(),
              )
              |> result.unwrap(None)
            _ -> None
          }
        _ -> None
      }
  }
}

pub fn process_stdio_input(
  actor_id: String,
  client_name: String,
  workspace_root: String,
  session_id: String,
  route: String,
  profile: types.ProtocolProfile,
  chunks: List(String),
  now_ms: Int,
) -> Result(List(String), types.ToolError) {
  use session <- result.try(stdio.new_session(
    actor_id: actor_id,
    client_name: client_name,
    workspace_root: workspace_root,
    session_id: session_id,
    profile: profile,
    deadline_ms: stdio.default_frame_deadline_ms,
  ))
  use session <- result.try(
    list.try_fold(chunks, session, fn(session, chunk) {
      ingest_canonical(session, chunk, route, now_ms)
    }),
  )
  use closed <- result.try(stdio.handle_eof(session: session))
  Ok(closed.stdout_frames)
}

fn ingest_canonical(
  session: stdio.StdioSession,
  chunk: String,
  route: String,
  now: Int,
) -> Result(stdio.StdioSession, types.ToolError) {
  // Validate the whole chunk before dispatching any of its frames. Preserve
  // raw params (notably tools/call.name) across partial and batched frames.
  use _ <- result.try(
    stdio.ingest_chunk(
      session: session,
      chunk: chunk,
      now_ms: now,
      handler: fn(_, _) { refuse("VALIDATION_ONLY", "Framing only") },
    ),
  )
  ingest_parts(session, string.split(chunk, "\n"), route, now)
}

fn ingest_parts(
  session: stdio.StdioSession,
  parts: List(String),
  route: String,
  now: Int,
) -> Result(stdio.StdioSession, types.ToolError) {
  case parts {
    [] -> Ok(session)
    [part, ..rest] -> {
      let chunk =
        part
        <> case rest {
          [] -> ""
          _ -> "\n"
        }
      let raw = session.buffer <> part
      let projection = case is_private_route(route), rest {
        True, [_, ..] -> private_wire_projection(raw)
        _, _ -> None
      }
      // Framing and security always inspect the original bytes first. A
      // complete typed private frame is then decoded through a string-only
      // projection; partial frames retain their original buffer/deadline.
      let validated = case projection {
        None -> Ok(session)
        Some(_) ->
          stdio.ingest_chunk(
            session: session,
            chunk: chunk,
            now_ms: now,
            handler: fn(_, _) {
              refuse("VALIDATION_ONLY", "Original frame checks")
            },
          )
          |> result.map(fn(pair) { pair.0 })
      }
      use session <- result.try(validated)
      let chunk = case projection {
        None -> chunk
        Some(projected) -> projected <> "\n"
      }
      use #(next, _) <- result.try(
        stdio.ingest_chunk(
          session: session,
          chunk: chunk,
          now_ms: now,
          handler: fn(p, msg) {
            dispatch_actor(p, session.profile, route, raw, msg, now)
          },
        ),
      )
      ingest_parts(next, rest, route, now)
    }
  }
}

// Standard JSON-RPC shares the stdio framing/security gates. Validation uses a
// non-effecting closure, then exactly one dispatch enters the state actor.
fn validate_standard_line(
  raw: String,
  profile: types.ProtocolProfile,
  p: principal.Principal,
  now: Int,
  route: String,
) -> Result(wire.NormalizedMessage, types.ToolError) {
  use session <- result.try(stdio.new_session(
    actor_id: principal.actor_id(p),
    client_name: principal.client_profile(p).name,
    workspace_root: principal.workspace_root(p),
    session_id: principal.session_id(p),
    profile: profile,
    deadline_ms: stdio.default_frame_deadline_ms,
  ))
  use #(session, _) <- result.try(
    stdio.ingest_chunk(
      session: session,
      chunk: raw,
      now_ms: now,
      handler: fn(_, _) {
        refuse("VALIDATION_ONLY", "No effect during framing")
      },
    ),
  )
  use _ <- result.try(
    stdio.ingest_chunk(
      session: session,
      chunk: "\n",
      now_ms: now,
      handler: fn(_, _) {
        refuse("VALIDATION_ONLY", "No effect during framing")
      },
    ),
  )
  use document <- result.try(
    json.parse(raw, value.decoder())
    |> result.map_error(fn(_) {
      types.ToolError("MALFORMED_JSONRPC", "Invalid JSON", types.NonRetryable)
    }),
  )
  use _ <- result.try(case value.get(document, "jsonrpc") {
    Ok(value.Text("2.0")) | Error(_) -> Ok(Nil)
    _ ->
      Error(types.ToolError(
        "MALFORMED_JSONRPC",
        "jsonrpc must be 2.0",
        types.NonRetryable,
      ))
  })
  let projected = case is_private_route(route) {
    True -> option.unwrap(private_wire_projection(raw), raw)
    False -> raw
  }
  wire.decode_request(profile, projected)
  |> result.map_error(fn(error) {
    types.ToolError(error.code, error.reason, types.NonRetryable)
  })
}

fn request_id_json(id: wire.WireId) -> json.Json {
  case id {
    wire.IntId(n) -> json.int(n)
    wire.StringId(s) -> json.string(s)
    wire.NoIdNotification -> json.null()
  }
}

pub fn standard_response(
  id: wire.WireId,
  method: String,
  outcome: types.Outcome,
) -> String {
  let response = case outcome {
    types.Complete(text, ev) -> {
      let payload = case method {
        "tools/call" ->
          json.object([
            #("isError", json.bool(False)),
            #(
              "content",
              json.preprocessed_array([
                json.object([
                  #("type", json.string("text")),
                  #("text", json.string(text)),
                ]),
              ]),
            ),
            #(
              "_meta",
              json.object([
                #("candidate", json.string(ev.candidate)),
                #("route", json.string(ev.route)),
                #("output_sha256", json.string(ev.output_sha256)),
              ]),
            ),
          ])
        _ ->
          case json.parse(text, value.decoder()) {
            Ok(v) -> value.encode(v)
            _ -> json.string(text)
          }
      }
      #("result", payload)
    }
    types.Refused(error) ->
      case method {
        "tools/call" -> #(
          "result",
          json.object([
            #("isError", json.bool(True)),
            #(
              "content",
              json.preprocessed_array([
                json.object([
                  #("type", json.string("text")),
                  #("text", json.string(error.code <> ": " <> error.reason)),
                ]),
              ]),
            ),
          ]),
        )
        _ -> #(
          "error",
          json.object([
            #(
              "code",
              json.int(case error.code {
                "METHOD_NOT_FOUND" -> -32_601
                _ -> -32_600
              }),
            ),
            #("message", json.string(error.code <> ": " <> error.reason)),
          ]),
        )
      }
    types.Uncertain(receipt) -> #(
      "error",
      json.object([
        #("code", json.int(-32_603)),
        #("message", json.string("UNCERTAIN: " <> receipt.reason)),
        #(
          "data",
          json.object([
            #("intent_id", json.string(receipt.intent_id)),
            #("route", json.string(receipt.route)),
            #("tool", json.string(receipt.tool)),
            #("candidate", json.string(receipt.candidate)),
            #("retryability", json.string("reconcile_first")),
          ]),
        ),
      ]),
    )
  }
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", request_id_json(id)),
    response,
  ])
  |> json.to_string
}

pub fn handle_standard_mcp_line(
  actor_id: String,
  client_name: String,
  workspace_root: String,
  session_id: String,
  route: String,
  raw_line: String,
  now_ms: Int,
) -> Option(String) {
  let profile =
    profile_for(raw_string(
      raw_line,
      ["params", "protocolVersion"],
      "2026-07-28",
    ))
  handle_standard_with_profile(
    actor_id,
    client_name,
    workspace_root,
    session_id,
    route,
    raw_line,
    now_ms,
    profile,
  )
}

fn handle_standard_with_profile(
  actor_id: String,
  client_name: String,
  workspace_root: String,
  session_id: String,
  route: String,
  raw_line: String,
  now_ms: Int,
  profile: types.ProtocolProfile,
) -> Option(String) {
  let p =
    principal.from_launcher_env(
      actor: actor_id,
      client: types.ClientProfile(client_name),
      workspace_root: workspace_root,
      session_id: session_id,
    )
  case validate_standard_line(raw_line, profile, p, now_ms, route) {
    Error(error) ->
      Some(standard_response(wire.NoIdNotification, "", types.Refused(error)))
    Ok(msg) -> {
      let outcome = dispatch_actor(p, profile, route, raw_line, msg, now_ms)
      case msg.id {
        wire.NoIdNotification -> None
        _ -> Some(standard_response(msg.id, msg.method, outcome))
      }
    }
  }
}

pub fn stdio_main() -> Nil {
  case launcher.configure_stdout_utf8() {
    Ok(Nil) -> stdio_run()
    Error(reason) -> io.println_error("MCP stdout encoding: " <> reason)
  }
}

fn stdio_run() -> Nil {
  mark_stdio_gateway()
  let actor_id = env("UOS_MCP_ACTOR_ID", env("USER", "local-stdio-operator"))
  let client = env("UOS_MCP_CLIENT_NAME", "uos-stdio-client")
  let root = workspace_root()
  let session_id = env("UOS_MCP_SESSION_ID", default_stdio_session_id())
  let route = env("UOS_MCP_ROUTE", "public")
  let profile = profile_for(env("UOS_MCP_PROTOCOL_VERSION", "2026-07-28"))
  let _ = ensure_started_with_zenoh(False)
  case env("UOS_MCP_WIRE_MODE", "standard_mcp") {
    "canonical" ->
      case
        stdio.new_session(
          actor_id: actor_id,
          client_name: client,
          workspace_root: root,
          session_id: session_id,
          profile: profile,
          deadline_ms: stdio.default_frame_deadline_ms,
        )
      {
        Ok(session) -> canonical_loop(session, route)
        Error(error) -> io.println_error(error.code)
      }
    _ -> standard_loop(actor_id, client, root, session_id, route, profile)
  }
}

pub fn default_stdio_session_id() -> String {
  "stdio:"
  <> charlist.to_string(os_pid())
  <> ":"
  <> int.to_string(system_time_nanos())
}

fn standard_loop(
  actor_id: String,
  client: String,
  root: String,
  session_id: String,
  route: String,
  profile: types.ProtocolProfile,
) -> Nil {
  case read_line() {
    Line(raw) -> {
      let profile = case raw_string(raw, ["method"], "") {
        "initialize" ->
          case raw_string(raw, ["params", "protocolVersion"], "") {
            "2024-11-05" -> types.Legacy20241105
            "2025-03-26" | "2025-06-18" | "2025-11-25" | "2026-07-28" ->
              types.Modern20260728
            _ -> profile
          }
        _ -> profile
      }
      case
        handle_standard_with_profile(
          actor_id,
          client,
          root,
          session_id,
          route,
          string.trim_end(raw),
          now_ms(),
          profile,
        )
      {
        Some(response) -> io.println(response)
        None -> Nil
      }
      standard_loop(actor_id, client, root, session_id, route, profile)
    }
    EndOfFile -> Nil
    ReadError(reason) -> io.println_error("MCP stdin: " <> reason)
  }
}

fn canonical_loop(session: stdio.StdioSession, route: String) -> Nil {
  case read_line() {
    Line(raw) -> {
      let now = now_ms()
      case ingest_canonical(session, raw, route, now) {
        Ok(next) -> {
          list.each(next.stdout_frames, io.println)
          canonical_loop(
            stdio.StdioSession(..next, stdout_frames: [], stderr_logs: []),
            route,
          )
        }
        Error(error) -> io.println_error(error.code)
      }
    }
    EndOfFile ->
      case stdio.handle_eof(session: session) {
        Ok(_) -> Nil
        Error(error) -> io.println_error(error.code)
      }
    ReadError(reason) -> io.println_error(reason)
  }
}

/// Decode only complete, bounded SSE events. Transport framing and HMAC
/// verification remain independent gates; no sample can select a network host.
pub fn decode_zenoh_sse_event(block: String) -> Option(#(String, String)) {
  case string.byte_size(block) <= 1_048_576 {
    False -> None
    True -> {
      let lines =
        block
        |> string.replace("\r\n", "\n")
        |> string.replace("\r", "\n")
        |> string.split("\n")
      let data =
        list.filter_map(lines, fn(line) {
          case string.starts_with(line, "data:") {
            False -> Error(Nil)
            True -> {
              let text = string.drop_start(line, 5)
              Ok(case string.starts_with(text, " ") {
                True -> string.drop_start(text, 1)
                False -> text
              })
            }
          }
        })
        |> string.join("\n")
      // Bound recursive JSON decoding before entering the lossless decoder.
      case sse_json_depth_ok(bit_array.from_string(data), False, False, 0) {
        False -> None
        True ->
          case json.parse(data, value.decoder()) {
            Error(_) -> None
            Ok(sample) -> {
              let key = case value.get(sample, "key") {
                Ok(v) -> Ok(v)
                Error(_) -> value.get(sample, "key_expr")
              }
              let payload = case value.get(sample, "value") {
                Ok(v) -> Ok(v)
                Error(_) -> value.get(sample, "payload")
              }
              case key, payload {
                Ok(value.Text(topic)), Ok(v) ->
                  case safe_zenoh_request_topic(topic) {
                    False -> None
                    True ->
                      case v {
                        value.Text(text) -> Some(#(topic, text))
                        value.Object(_) ->
                          Some(#(topic, json.to_string(value.encode(v))))
                        _ -> None
                      }
                  }
                _, _ -> None
              }
            }
          }
      }
    }
  }
}

fn safe_zenoh_request_topic(topic: String) -> Bool {
  string.byte_size(topic) <= 512
  && case string.split(topic, "/") {
    ["indrajaal", "mcp", "request", client, request] ->
      safe_zenoh_segment(client) && safe_zenoh_segment(request)
    _ -> False
  }
}

fn safe_zenoh_segment(segment: String) -> Bool {
  segment != ""
  && segment != "."
  && segment != ".."
  && list.all(string.to_graphemes(segment), fn(c) {
    string.contains(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-",
      c,
    )
  })
}

fn sse_json_depth_ok(
  bytes: BitArray,
  quoted: Bool,
  escaped: Bool,
  depth: Int,
) -> Bool {
  case depth > 36 {
    True -> False
    False ->
      case bytes, quoted, escaped {
        <<>>, _, _ -> True
        <<_, rest:bytes>>, True, True ->
          sse_json_depth_ok(rest, True, False, depth)
        <<0x5c, rest:bytes>>, True, False ->
          sse_json_depth_ok(rest, True, True, depth)
        <<0x22, rest:bytes>>, _, _ ->
          sse_json_depth_ok(rest, !quoted, False, depth)
        <<0x7b, rest:bytes>>, False, _ | <<0x5b, rest:bytes>>, False, _ ->
          sse_json_depth_ok(rest, False, False, depth + 1)
        <<0x7d, rest:bytes>>, False, _ | <<0x5d, rest:bytes>>, False, _ ->
          sse_json_depth_ok(rest, False, False, depth - 1)
        <<_, rest:bytes>>, _, _ -> sse_json_depth_ok(rest, quoted, False, depth)
        _, _, _ -> False
      }
  }
}
