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
import cepaf_gleam/mcp/adapters/canonical_planning_store
import cepaf_gleam/mcp/adapters/control
import cepaf_gleam/mcp/adapters/feature_receipt_ledger
import cepaf_gleam/mcp/adapters/features
import cepaf_gleam/mcp/adapters/knowledge
import cepaf_gleam/mcp/adapters/planning_read
import cepaf_gleam/mcp/adapters/planning_write
import cepaf_gleam/mcp/adapters/system_observation
import cepaf_gleam/mcp/adapters/vault_backend
import cepaf_gleam/mcp/adapters/vault_metadata
import cepaf_gleam/mcp/adapters/verification
import cepaf_gleam/mcp/admission
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/http_auth
import cepaf_gleam/mcp/json_guard
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
import cepaf_gleam/mcp/workspace_knowledge
import cepaf_gleam/ui/lustre/live_corpus
import gleam/bit_array
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/charlist
import gleam/erlang/process
import gleam/float
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
    durable: Bool,
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
    durable_key: Option(String),
    commit_seq: Int,
    commit_order: dict.Dict(String, Int),
  )
}

/// Trusted in-VM actor protocol. Neither snapshots nor prepared calls can be
/// constructed from transport payloads; their public types remain opaque.
pub type Message {
  Ping(process.Subject(Bool))
  Snapshot(principal.Principal, process.Subject(PrivateSnapshot))
  ObservationTarget(process.Subject(supervisor.SupervisedGateway))
  DispatchKnowledge(List(knowledge.CorpusEntry), Message)
  DispatchObserved(system_observation.ObservationBackend, Message)
  DispatchPublicPrefetched(PublicPrefetch, Message)
  ReservePrivate(
    admission.ValidatedCall,
    process.Subject(Result(Nil, types.ToolError)),
  )
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

/// Trusted ingress observations, never decoded from a transport payload.
pub opaque type PublicPrefetch {
  PublicPrefetch(
    vault: Option(vault_metadata.VaultHandle),
    features: Option(features.FeatureEvidenceStore),
    authority: #(
      Option(admission.TaskFence),
      Option(route_convergence.RouteGrant),
    ),
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

@external(erlang, "mcp_stdio_ffi", "gateway_handle_new")
fn owner_box_new() -> dynamic.Dynamic

@external(erlang, "mcp_stdio_ffi", "gateway_owner_set")
fn owner_box_set(
  box: dynamic.Dynamic,
  subject: Option(process.Subject(Message)),
) -> Nil

@external(erlang, "mcp_stdio_ffi", "gateway_owner_register")
fn owner_box_register(pid: process.Pid, box: dynamic.Dynamic) -> Nil

@external(erlang, "mcp_stdio_ffi", "new_reply_subject")
fn new_reply_subject() -> process.Subject(a)

@external(erlang, "mcp_stdio_ffi", "close_reply_subject")
fn close_reply_subject(reply: process.Subject(a)) -> Nil

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
  && subject_alive(supervisor.current_gateway_subject(gateway))
}

fn gateway_alive(gateway: supervisor.SupervisedGateway) -> Bool {
  case supervised_gateway_pids_alive(gateway) {
    False -> False
    True -> {
      let reply = process.new_subject()
      process.send(
        supervisor.current_gateway_subject(gateway),
        supervisor.Ping(reply),
      )
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
      case
        gateway_supervisor_running()
        && {
          case stored_subject(gateway_key(), None) {
            Some(subject) -> subject_alive(subject)
            None -> False
          }
        }
      {
        True -> True
        False ->
          case gateway_supervisor_running() {
            // A live owner supervisor is already responsible for restart. Never
            // create a losing tree whose child could publish a dead subject.
            True -> wait_replacement_subject(100) != None
            False -> start_gateway_owner_supervisor()
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
    #(
      "public_routes",
      json.int(
        list.length(
          list.filter(registry.all_specs(), fn(spec) { spec.route == "public" }),
        ),
      ),
    ),
    #(
      "development_routes",
      json.int(
        list.length(
          list.filter(registry.all_specs(), fn(spec) {
            spec.route == "development"
          }),
        ),
      ),
    ),
    #(
      "successor_routes",
      json.int(
        list.length(
          list.filter(registry.all_specs(), fn(spec) {
            spec.route == "successor"
          }),
        ),
      ),
    ),
    #("total_routes", json.int(list.length(registry.all_specs()))),
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
  // Preserve the eager constructor used by isolated canonical-store fixtures.
  new_state_with_planning(
    root,
    cand,
    pool,
    gateway,
    load_planning(root, default_live_plan(root)),
  )
}

fn new_state_with_planning(
  root: String,
  cand: String,
  pool: supervisor.WorkerPool,
  gateway: supervisor.SupervisedGateway,
  initial_planning: planning_read.PlanningReadStore,
) -> GatewayState {
  let corpus = knowledge.new_corpus(root, ["public"], 1_048_576, 4)
  let corpus =
    list.fold(["AGENTS.md", "CLAUDE.md", "GEMINI.md"], corpus, load_document)
  let evidence = feature_receipt_ledger.load_verified_projection(root, cand)
  let backends =
    server.ServerBackends(
      planning_read: initial_planning,
      planning_write: planning_write.new_canonical_store(root),
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
      vault: vault_backend.load_vault_handle(root),
      analysis: analysis.MaxDaemonOffline("No inference daemon bound"),
      features: evidence,
    )
  let entries = [
    #("uos://km/triad", "Live KM Triad", ""),
    #("uos://wiki/index", "Live Wiki Index", ""),
    #("uos://zk/master-moc", "Live Master MOC", ""),
    #("uos://sop/fractal-system-prompt", "Live Fractal System Prompt", ""),
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
          "uos://wiki/{slug}",
          "uos_wiki",
          "Live wiki document",
        ),
        resources.ResourceTemplate(
          "uos://zk/{slug}",
          "uos_zk",
          "Live ZK document",
        ),
        resources.ResourceTemplate(
          "uos://km/{path}",
          "uos_km",
          "Allowlisted live Brain Memory",
        ),
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
        "uos_km_brain_memory_orient",
        "Advisory live KM Brain Memory orientation",
        [],
        "advisory_only: true. Orient using live #km-triad Brain Memory at http://nas-1.tail55d152.ts.net:4100/km, /wiki and /zk. Query fresh resources before each POODAVR stage; degraded roots grant no authority.",
      ),
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
    durable_key: None,
    commit_seq: 0,
    commit_order: dict.new(),
  )
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
      case !string.starts_with(relative, "/") && relative != "" {
        False -> None
        True ->
          case detect_link_escape(root, string.split(relative, "/")) {
            Some(escape) ->
              Some(knowledge.CorpusEntry(path, escape, "public", ""))
            None ->
              case live_corpus.brain_file(relative) {
                False -> None
                True ->
                  case live_corpus.read(root, relative, 1_048_576) {
                    Ok(content) ->
                      case string.contains(content, "\u{0000}") {
                        True -> None
                        False ->
                          Some(knowledge.CorpusEntry(
                            path,
                            knowledge.RegularFile,
                            "public",
                            content,
                          ))
                      }
                    Error(_) -> None
                  }
              }
          }
      }
    }
  }
}

fn detect_link_escape(
  base: String,
  segments: List(String),
) -> Option(knowledge.LinkKind) {
  case segments {
    [] -> None
    [seg, ..rest] -> {
      let next = base <> "/" <> seg
      case simplifile.link_info(next) {
        Ok(info) ->
          case simplifile.file_info_type(info) {
            simplifile.Symlink -> Some(knowledge.SymlinkEscape)
            simplifile.File ->
              case rest == [] && info.nlinks > 1 {
                True -> Some(knowledge.HardlinkEscape)
                False -> None
              }
            simplifile.Directory -> detect_link_escape(next, rest)
            _ -> None
          }
        Error(_) -> None
      }
    }
  }
}

fn sqlite_binary(root: String) -> Option(String) {
  canonical_planning_store.resolve_sqlite_binary(root)
}

fn default_live_plan(_root: String) -> String {
  ""
}

fn load_planning(
  root: String,
  plan: String,
) -> planning_read.PlanningReadStore {
  canonical_planning_store.load_read_store(root, plan)
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
    None,
    dict.from_list([
      #("probe_kind", "gateway_pid_liveness"),
      #("observed_source", scope),
      #("system_health.status", case alive {
        True -> "healthy"
        False -> "stopped"
      }),
    ]),
  )
}

@external(erlang, "mcp_stdio_ffi", "beam_metrics")
fn live_beam_metrics() -> List(#(String, String))

@external(erlang, "mcp_stdio_ffi", "loopback_probe")
fn loopback_probe(port: Int) -> Bool

@external(erlang, "mcp_stdio_ffi", "coordination_metrics")
fn coordination_metrics(root: String) -> Result(List(#(String, String)), String)

fn sqlite_observe(
  root: String,
  relative: String,
  query: String,
) -> Result(String, Nil) {
  use binary <- result.try(sqlite_binary(root) |> option.to_result(Nil))
  case
    run_bounded_cd(
      binary,
      ["-readonly", "-cmd", ".timeout 1000", root <> "/" <> relative, query],
      root,
      2000,
    )
  {
    Ok(#(0, text)) -> Ok(string.trim(text))
    _ -> Error(Nil)
  }
}

fn task_count_metrics(root: String) -> Result(List(#(String, String)), Nil) {
  use text <- result.try(sqlite_observe(
    root,
    "var/sa-plan/uos.sqlite3",
    "SELECT json_object('executing_tasks',sum(state='executing'),'completed_tasks',sum(state='completed'),'ready_tasks',sum(state in ('available','ready','pending')),'total_tasks',count(*),'active_workers',count(distinct case when state='executing' then worker end)) FROM sa_plan_task;",
  ))
  json.parse(text, decode.dict(decode.string, decode.int))
  |> result.map(fn(rows) {
    list.map(dict.to_list(rows), fn(row) { #(row.0, int.to_string(row.1)) })
  })
  |> result.map_error(fn(_) { Nil })
}

fn observation_probe(
  tool: String,
  root: String,
  cand: String,
  now: Int,
  alive: Bool,
) -> system_observation.ObservationBackend {
  let base =
    dict.from_list(list.append(
      live_beam_metrics(),
      workspace_knowledge.brain_memory_health_metrics(root),
    ))
  let base = dict.insert(base, "probe_kind", "local_bounded_observation")
  let base =
    dict.insert(
      base,
      "observed_source",
      "BEAM runtime; canonical SQLite read-only; loopback socket; local filesystem",
    )
  let base = dict.insert(base, "loaded_beam_sha256", loaded_mcp_beams_digest())
  let base = dict.insert(base, "admitted_ev_ceiling", "93")
  let base =
    dict.insert(base, "gateway_alive", case alive {
      True -> "true"
      False -> "false"
    })
  let queue = int.parse(argument(base, "run_queue", "0")) |> result.unwrap(0)
  let schedulers =
    int.parse(argument(base, "schedulers_online", "1")) |> result.unwrap(1)
  let memory_mb =
    float.parse(argument(base, "memory_total_mb", "0.0")) |> result.unwrap(0.0)
  let healthy =
    alive
    && argument(base, "durable_ets_present", "false") == "true"
    && argument(base, "handles_ets_present", "false") == "true"
    && queue <= schedulers * 4
    && memory_mb <. 16_384.0
  let needs_tasks =
    list.contains(
      [
        "system_verification",
        "fractal_status",
        "evolution_metrics",
        "holon_status",
        "swarm_status",
        "agent_hierarchy",
        "ooda_phase",
        "ooda_decide",
        "system_dashboard",
      ],
      tool,
    )
  let counts = case needs_tasks {
    True -> task_count_metrics(root)
    False -> Ok([])
  }
  let metrics = case counts {
    Ok(rows) -> list.fold(rows, base, fn(d, p) { dict.insert(d, p.0, p.1) })
    Error(_) -> base
  }
  let metrics = case
    list.contains(
      [
        "holon_status",
        "swarm_status",
        "agent_hierarchy",
        "ooda_phase",
        "ooda_decide",
        "system_dashboard",
        "integrity_check",
      ],
      tool,
    )
  {
    True ->
      case coordination_metrics(root) {
        Ok(rows) ->
          list.fold(rows, metrics, fn(d, p) { dict.insert(d, p.0, p.1) })
        Error(_) -> dict.insert(metrics, "coordination_probe", "failed")
      }
    False -> metrics
  }
  let needs_integrity =
    list.contains(
      ["integrity_check", "prajna_health", "dark_cockpit_mode", "system_immune"],
      tool,
    )
  let db_ok = case needs_integrity {
    True ->
      sqlite_observe(root, "var/sa-plan/uos.sqlite3", "PRAGMA quick_check;")
      == Ok("ok")
      && sqlite_observe(
        root,
        "var/coordination/tri-agent/coordinator.sqlite3",
        "PRAGMA quick_check;",
      )
      == Ok("ok")
    False -> True
  }
  let metrics = case needs_integrity {
    True ->
      dict.insert(metrics, "sqlite_quick_check", case db_ok {
        True -> "ok"
        False -> "failed"
      })
    False -> metrics
  }
  let metrics = case
    list.contains(["prajna_health", "dark_cockpit_mode", "system_immune"], tool)
  {
    True -> {
      let quarantined = case
        simplifile.read_directory(
          root <> "/var/coordination/tri-agent/events-quarantine",
        )
      {
        Ok(files) -> list.length(files)
        Error(_) -> -1
      }
      dict.insert(metrics, "quarantine_files", int.to_string(quarantined))
    }
    False -> metrics
  }
  let net_tool = list.contains(["system_zenoh", "mesh_topology"], tool)
  let rest = case net_tool {
    True -> loopback_probe(8080)
    False -> False
  }
  let tcp = case net_tool {
    True -> loopback_probe(7447)
    False -> False
  }
  let metrics = case net_tool {
    True ->
      metrics
      |> dict.insert("zenoh_subscriber_status", zenoh_subscriber_state())
      |> dict.insert("zenoh_rest_reachable", case rest {
        True -> "true"
        False -> "false"
      })
      |> dict.insert("zenoh_tcp_reachable", case tcp {
        True -> "true"
        False -> "false"
      })
    False -> metrics
  }
  let age = case simplifile.read(root <> "/var/preflight/latest.json") {
    Ok(text) ->
      case json.parse(text, decode.at(["epoch_s"], decode.int)) {
        Ok(epoch) -> now / 1000 - epoch
        Error(_) -> 1_000_000_000
      }
    Error(_) -> 1_000_000_000
  }
  let metrics = case needs_tasks {
    True -> dict.insert(metrics, "preflight_age_s", int.to_string(age))
    False -> metrics
  }
  let metrics = case tool {
    "integrity_check" ->
      metrics
      |> dict.insert(
        "candidate_sha256_valid",
        case
          cand == candidate_id.from_root(root) && candidate_id.is_valid(cand)
        {
          True -> "true"
          False -> "false"
        },
      )
    "ooda_phase" | "ooda_decide" -> {
      let phase = case
        int.parse(argument(metrics, "executing_tasks", "0")) |> result.unwrap(0)
        > 0
      {
        True -> "act"
        False -> "reflect"
      }
      metrics
      |> dict.insert("phase", phase)
      |> dict.insert("phase_derivation", "canonical_task_projection")
      |> dict.insert("decision", "preview_only_canonical_task_snapshot")
    }
    _ -> metrics
  }
  let containers = case
    list.contains(["podman_containers", "system_dashboard"], tool)
  {
    True ->
      case
        run_bounded_cd(
          "/usr/bin/podman",
          ["ps", "--format", "{{.Names}}"],
          root,
          1500,
        )
      {
        Ok(#(0, text)) ->
          Some(
            string.split(text, "\n")
            |> list.map(string.trim)
            |> list.filter(fn(s) { s != "" }),
          )
        _ -> None
      }
    False -> None
  }
  let status = case tool {
    "kms_catalog" -> None
    "system_zenoh" | "mesh_topology" ->
      Some(case rest && tcp && zenoh_subscriber_alive() {
        True -> "connected"
        False -> "degraded"
      })
    "system_verification" | "fractal_status" | "evolution_metrics" ->
      Some(case healthy && counts != Error(Nil) && age >= 0 && age <= 900 {
        True -> "healthy"
        False -> "degraded"
      })
    "system_immune" | "prajna_health" | "dark_cockpit_mode" ->
      Some(
        case
          healthy && db_ok && argument(metrics, "quarantine_files", "-1") == "0"
        {
          True -> "healthy"
          False -> "degraded"
        },
      )
    "system_dashboard" ->
      Some(case healthy && counts != Error(Nil) && containers != None {
        True -> "healthy"
        False -> "degraded"
      })
    _ ->
      Some(case healthy && db_ok && counts != Error(Nil) {
        True -> "healthy"
        False -> "degraded"
      })
  }
  let metrics = case status {
    Some(status) -> dict.insert(metrics, tool <> ".status", status)
    None -> metrics
  }
  system_observation.ObservedSnapshot(
    cand,
    "beam_otp29_live",
    now,
    30_000,
    containers,
    metrics,
  )
}

pub const max_committed_receipts = 4096

pub const max_unresolved_receipts = 4096

@external(erlang, "mcp_stdio_ffi", "cached_supervised_gateway")
fn cached_supervised_gateway(
  key: String,
  factory: fn() -> Result(supervisor.SupervisedGateway, actor.StartError),
) -> Result(supervisor.SupervisedGateway, actor.StartError)

@external(erlang, "mcp_stdio_ffi", "durable_initial")
fn durable_initial(key: String, factory: fn() -> GatewayState) -> GatewayState

@external(erlang, "mcp_stdio_ffi", "durable_state")
fn durable_state(key: String, fallback: GatewayState) -> GatewayState

@external(erlang, "mcp_stdio_ffi", "durable_ledger")
fn durable_ledger(
  key: String,
  fallback: receipts.ReceiptLedger,
) -> receipts.ReceiptLedger

@external(erlang, "mcp_stdio_ffi", "durable_checkpoint")
fn durable_checkpoint(
  key: String,
  ledger: receipts.ReceiptLedger,
  state: GatewayState,
) -> Nil

/// Deterministic bounded terminal retention. Pending/uncertain entries are never evicted.
@external(erlang, "erlang", "external_size")
fn stored_bytes(value: a) -> Int

@external(erlang, "mcp_stdio_ffi", "cached_readonly_receipt_keys")
fn cached_readonly_keys(
  factory: fn() -> dict.Dict(#(String, String), Nil),
) -> dict.Dict(#(String, String), Nil)

fn readonly_receipt_keys() -> dict.Dict(#(String, String), Nil) {
  cached_readonly_keys(fn() {
    list.fold(registry.all_specs(), dict.new(), fn(keys, spec) {
      case spec.effect_class == types.ReadOnly {
        True -> dict.insert(keys, #(spec.route, spec.name), Nil)
        False -> keys
      }
    })
  })
}

fn readonly_receipt(
  entry: receipts.ReceiptEntry,
  keys: dict.Dict(#(String, String), Nil),
) -> Bool {
  dict.has_key(keys, #(entry.route, entry.tool))
  || { entry.route == "public" && entry.tool == "ping" }
}

pub fn bound_receipt_ledger(
  ledger: receipts.ReceiptLedger,
) -> receipts.ReceiptLedger {
  let #(_, order) = assign_commit_order(ledger, 0, dict.new())
  bound_receipt_ledger_ordered(ledger, order)
}

// Old node-local snapshots have no historical chronology. Migrate their
// unsequenced entries in lexical order once; every subsequent commit receives
// the next owner-serialized sequence, persisted in the same ETS checkpoint.
fn assign_commit_order(
  ledger: receipts.ReceiptLedger,
  seq: Int,
  order: dict.Dict(String, Int),
) -> #(Int, dict.Dict(String, Int)) {
  ledger.entries
  |> dict.to_list
  |> list.filter(fn(pair) {
    case pair.1.state {
      receipts.OutcomeCommitted(_) -> !dict.has_key(order, pair.0)
      _ -> False
    }
  })
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.fold(#(seq, order), fn(acc, pair) {
    #(acc.0 + 1, dict.insert(acc.1, pair.0, acc.0 + 1))
  })
}

fn bound_receipt_ledger_ordered(
  ledger: receipts.ReceiptLedger,
  order: dict.Dict(String, Int),
) -> receipts.ReceiptLedger {
  let pairs =
    dict.to_list(ledger.entries)
    |> list.sort(fn(a, b) {
      int.compare(
        dict.get(order, b.0) |> result.unwrap(0),
        dict.get(order, a.0) |> result.unwrap(0),
      )
    })
  let readonly_keys = readonly_receipt_keys()
  // Preserve effect fences and unresolved entries before expendable read-only
  // replay payloads. Admission refuses further effects before the byte/count cap.
  let protected =
    list.filter(pairs, fn(pair) {
      case pair.1.state {
        receipts.OutcomeCommitted(_) -> !readonly_receipt(pair.1, readonly_keys)
        _ -> True
      }
    })
  let readonly =
    list.filter(pairs, fn(pair) {
      case pair.1.state {
        receipts.OutcomeCommitted(_) -> readonly_receipt(pair.1, readonly_keys)
        _ -> False
      }
    })
  let #(entries, _, _) =
    list.fold(
      list.append(protected, readonly),
      #(dict.new(), 0, 0),
      fn(acc, pair) {
        let #(entries, count, bytes) = acc
        let entry = pair.1
        case entry.state {
          receipts.OutcomeCommitted(outcome) -> {
            let size = stored_bytes(pair)
            let large =
              stored_bytes(outcome) > 16_384 || bytes + size > 16_777_216
            case readonly_receipt(entry, readonly_keys) {
              True ->
                case count >= max_committed_receipts || large {
                  True -> acc
                  False -> #(
                    dict.insert(entries, pair.0, entry),
                    count + 1,
                    bytes + size,
                  )
                }
              False -> {
                let entry = case large {
                  True ->
                    receipts.ReceiptEntry(
                      ..entry,
                      state: receipts.OutcomeCommitted(
                        types.Refused(types.ToolError(
                          "REPLAY_PAYLOAD_NOT_RETAINED",
                          "Terminal outcome recorded; large replay payload compacted. Reconcile the durable receipt before retry; do not execute again",
                          types.ReconcileFirst,
                        )),
                      ),
                    )
                  False -> entry
                }
                #(
                  dict.insert(entries, pair.0, entry),
                  count + 1,
                  bytes + stored_bytes(#(pair.0, entry)),
                )
              }
            }
          }
          _ -> #(
            dict.insert(entries, pair.0, entry),
            count,
            bytes + stored_bytes(pair),
          )
        }
      },
    )
  receipts.ReceiptLedger(..ledger, entries: entries)
}

fn checkpoint_state(state: GatewayState) -> GatewayState {
  let #(seq, order) =
    assign_commit_order(state.pool.ledger, state.commit_seq, state.commit_order)
  let pool =
    supervisor.WorkerPool(
      ..state.pool,
      ledger: bound_receipt_ledger_ordered(state.pool.ledger, order),
    )
  let order =
    dict.filter(order, fn(id, _) { dict.has_key(pool.ledger.entries, id) })
  let state =
    GatewayState(..state, pool: pool, commit_seq: seq, commit_order: order)
  case state.durable_key {
    Some(key) -> {
      let durable_corpus =
        knowledge.KnowledgeCorpus(
          ..state.backends.knowledge,
          entries: dict.filter(state.backends.knowledge.entries, fn(path, _) {
            list.contains(["AGENTS.md", "CLAUDE.md", "GEMINI.md"], path)
          }),
        )
      let durable =
        GatewayState(
          ..state,
          backends: server.ServerBackends(
            ..state.backends,
            knowledge: durable_corpus,
            verification_runner: fn(_) {
              verification.ProverMissing("Prefetch is per-call only")
            },
          ),
        )
      durable_checkpoint(key, pool.ledger, durable)
      state
    }
    None -> state
  }
}

fn rehydrate_state(key: String, initial: GatewayState) -> GatewayState {
  let state = durable_state(key, initial)
  let ledger = durable_ledger(key, state.pool.ledger)
  let entries =
    dict.map_values(ledger.entries, fn(_, entry) {
      case entry.state {
        receipts.IntentRecorded ->
          receipts.ReceiptEntry(
            ..entry,
            state: receipts.EffectUncertain(types.UncertainReceipt(
              entry.intent_id,
              entry.route,
              entry.tool,
              "State owner interrupted before commit; reconcile required",
              entry.candidate,
            )),
          )
        _ -> entry
      }
    })
  checkpoint_state(
    GatewayState(
      ..state,
      durable_key: Some(key),
      pool: supervisor.WorkerPool(
        ..state.pool,
        ledger: receipts.ReceiptLedger(..ledger, entries: entries),
      ),
    ),
  )
}

fn handle_message(
  state: GatewayState,
  message: Message,
) -> actor.Next(GatewayState, Message) {
  case message {
    DispatchKnowledge(entries, inner) ->
      handle_dispatch(state, inner, entries, None)
    DispatchObserved(snapshot, inner) ->
      handle_message(
        GatewayState(
          ..state,
          backends: server.ServerBackends(
            ..state.backends,
            observation: snapshot,
          ),
        ),
        inner,
      )
    DispatchPublicPrefetched(prefetched, inner) ->
      handle_dispatch(state, inner, [], Some(prefetched))
    Snapshot(p, reply) -> {
      process.send(reply, private_snapshot(state, p))
      actor.continue(state)
    }
    ObservationTarget(reply) -> {
      process.send(reply, state.supervised_gateway)
      actor.continue(state)
    }
    ReservePrivate(call, reply) -> {
      case reserve_call(state, call) {
        Error(error) -> {
          process.send(reply, Error(error))
          actor.continue(state)
        }
        Ok(next) -> {
          process.send(reply, Ok(Nil))
          actor.continue(next)
        }
      }
    }
    CommitPrivate(prepared, reply) -> {
      let #(outcome, next) = commit_private(state, prepared)
      let next = checkpoint_state(next)
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
    Dispatch(..) as dispatch -> handle_dispatch(state, dispatch, [], None)
  }
}

fn handle_dispatch(
  state: GatewayState,
  message: Message,
  extra_entries: List(knowledge.CorpusEntry),
  prefetched: Option(PublicPrefetch),
) -> actor.Next(GatewayState, Message) {
  case message {
    DispatchKnowledge(entries, inner) ->
      handle_dispatch(
        state,
        inner,
        list.append(extra_entries, entries),
        prefetched,
      )
    DispatchObserved(snapshot, inner) ->
      handle_dispatch(
        GatewayState(
          ..state,
          backends: server.ServerBackends(
            ..state.backends,
            observation: snapshot,
          ),
        ),
        inner,
        extra_entries,
        prefetched,
      )
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
      let call_knowledge =
        knowledge.KnowledgeCorpus(
          ..state.backends.knowledge,
          entries: dict.new(),
        )
      let call_knowledge =
        list.fold(
          extra_entries,
          case prefetched_doc {
            Some(#(path, entry)) ->
              apply_document(call_knowledge, path, entry)
            None -> call_knowledge
          },
          fn(corpus, entry) { knowledge.with_entry(corpus, entry) },
        )
      let retained_seeds =
        knowledge.KnowledgeCorpus(
          ..state.backends.knowledge,
          entries: dict.filter(state.backends.knowledge.entries, fn(path, _) {
            list.contains(["AGENTS.md", "CLAUDE.md", "GEMINI.md"], path)
          }),
        )
      let retained_knowledge = case prefetched_doc {
        Some(#(path, entry)) ->
          case list.contains(["AGENTS.md", "CLAUDE.md", "GEMINI.md"], path) {
            True -> apply_document(retained_seeds, path, entry)
            False -> retained_seeds
          }
        None -> retained_seeds
      }
      let backends =
        server.ServerBackends(
          ..state.backends,
          knowledge: call_knowledge,
          planning_read: option.unwrap(
            prefetched_plan,
            state.backends.planning_read,
          ),
          vault: case prefetched {
            Some(PublicPrefetch(vault: Some(handle), ..)) -> handle
            _ -> state.backends.vault
          },
          features: case prefetched {
            Some(PublicPrefetch(features: Some(projection), ..)) ->
              merge_live_features(projection, state.backends.features)
            _ -> state.backends.features
          },
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
          Some(case prefetched {
            Some(item) -> item.authority
            None -> #(None, None)
          }),
        )
      let next =
        GatewayState(
          ..next,
          backends: server.ServerBackends(
            ..next.backends,
            knowledge: retained_knowledge,
            verification_runner: fn(_) {
              verification.ProverMissing("Prefetch is per-call only")
            },
          ),
        )
      let next = checkpoint_state(next)
      process.send(reply, outcome)
      actor.continue(next)
    }
    _ -> actor.continue(state)
  }
}

/// Start an isolated owner with the same non-blocking handler as production.
pub fn start_state_owner(
  state: GatewayState,
) -> Result(actor.Started(process.Subject(Message)), actor.StartError) {
  actor.new(state) |> actor.on_message(handle_message) |> actor.start
}

pub const max_inflight_dispatches = 256

@external(erlang, "mcp_stdio_ffi", "with_inflight_slot")
pub fn with_inflight_slot(
  limit: Int,
  work: fn() -> types.Outcome,
) -> types.Outcome

fn dispatch_actor(
  p: principal.Principal,
  profile: types.ProtocolProfile,
  route: String,
  raw: String,
  msg: wire.NormalizedMessage,
  now: Int,
) -> types.Outcome {
  with_inflight_slot(max_inflight_dispatches, fn() {
    dispatch_actor_admitted(p, profile, route, raw, msg, now)
  })
}

fn dispatch_actor_admitted(
  p: principal.Principal,
  profile: types.ProtocolProfile,
  route: String,
  raw: String,
  msg: wire.NormalizedMessage,
  now: Int,
) -> types.Outcome {
  let ready = case stored_subject(gateway_key(), None) {
    Some(subject) -> subject_alive(subject)
    None -> False
  }
  let ready = case ready {
    True -> True
    False -> ensure_started()
  }
  case ready, stored_subject(gateway_key(), None) {
    True, Some(subject) -> {
      case msg.method == "tools/call" && is_private_route(route) {
        True ->
          case private_ingress_binding_present(route, raw, msg) {
            Error(error) -> types.Refused(error)
            Ok(Nil) ->
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
          }
        False ->
          dispatch_public_actor(subject, p, profile, route, raw, msg, now)
      }
    }
    _, _ -> refuse("GATEWAY_UNAVAILABLE", "OTP gateway could not start")
  }
}

// Refusal-only live ingress check: absence of a binding cannot depend on the
// owner's mailbox. A present binding grants nothing here and is loaded and
// fenced again by the unchanged canonical snapshot/admission/effect path.
fn private_ingress_binding_present(
  route: String,
  raw: String,
  msg: wire.NormalizedMessage,
) -> Result(Nil, types.ToolError) {
  let #(tool, args) = tool_arguments(raw, msg)
  use _ <- result.try(private_tool_precheck(route, tool, args))
  use _ <- result.try(private_arguments(raw, msg))
  let present = case route {
    "development" -> result.is_ok(dev.load_binding())
    "successor" -> result.is_ok(harness_admission.load())
    _ -> False
  }
  case present {
    True -> Ok(Nil)
    False ->
      Error(private_error(
        "ROUTE_GRANT_REQUIRED",
        "A live private route binding is required",
      ))
  }
}

pub fn dispatch_public_actor(
  subject: process.Subject(Message),
  p: principal.Principal,
  profile: types.ProtocolProfile,
  route: String,
  raw: String,
  msg: wire.NormalizedMessage,
  now: Int,
) -> types.Outcome {
  let root = principal.workspace_root(p)
  let prefetched = case msg.method {
    "tools/call" -> {
      let #(tool, args) = tool_arguments(raw, msg)
      case resolve_public_mutation_authority(root, p, route, tool, args) {
        Error(error) -> Error(error)
        Ok(authority) -> {
          let spec = registry.lookup(route, tool)
          let vault = case spec {
            Ok(spec) if spec.family == "vault_metadata" ->
              Some(vault_backend.load_vault_handle(root))
            _ -> None
          }
          let projection = case spec {
            Ok(spec) if spec.family == "feature_evidence" ->
              Some(feature_receipt_ledger.load_verified_projection(
                root,
                candidate_id.from_root(root),
              ))
            _ -> None
          }
          Ok(Some(PublicPrefetch(vault, projection, authority)))
        }
      }
    }
    _ -> Ok(None)
  }
  case prefetched {
    Error(error) -> types.Refused(error)
    Ok(prefetched) ->
      dispatch_public_actor_prefetched(
        subject,
        p,
        profile,
        route,
        raw,
        msg,
        now,
        root,
        prefetched,
      )
  }
}

fn dispatch_public_actor_prefetched(
  subject: process.Subject(Message),
  p: principal.Principal,
  profile: types.ProtocolProfile,
  route: String,
  raw: String,
  msg: wire.NormalizedMessage,
  now: Int,
  root: String,
  prefetched: Option(PublicPrefetch),
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
      let prefetched_doc = case tool {
        "read_file" -> {
          let path = argument(args, "path", "")
          Some(#(path, read_corpus_entry(root, path)))
        }
        _ -> None
      }
      let prefetched_plan = case registry.lookup(route, tool) {
        Ok(spec) if spec.family == "planning_read" ->
          Some(load_planning(
            root,
            argument(args, "plan_id", argument(args, "plan", "")),
          ))
        _ -> None
      }
      let prefetched_check = case verification.is_verification_tool(tool) {
        True -> {
          let check_raw =
            argument(args, "check_id", case tool {
              "preflight_check" | "verification_run" -> "preflight_toolchain"
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
    "resources/read" -> {
      let uri = raw_string(raw, ["params", "uri"], "")
      let entry =
        live_resource(root, uri)
        |> option.map(fn(text) {
          knowledge.CorpusEntry(uri, knowledge.RegularFile, "public", text)
        })
      #(Some(#(uri, entry)), None, None)
    }
    "tasks/create" -> {
      let args = dict.from_list(msg.args)
      let plan_id =
        raw_string(raw, ["params", "planId"], argument(args, "plan_id", ""))
      let prefetched_plan = case profile {
        types.Modern20260728 -> Some(load_planning(root, plan_id))
        types.Legacy20241105 -> None
      }
      #(None, prefetched_plan, None)
    }
    _ -> #(None, None, None)
  }
  let prefetched_observation = case msg.method {
    "tools/call" -> {
      let #(tool, _) = tool_arguments(raw, msg)
      case system_observation.is_known_observation_tool(tool) {
        True ->
          Some(observation_probe(
            tool,
            root,
            candidate_id.from_root(root),
            now,
            option.unwrap(prefetched_gateway_alive, False),
          ))
        False -> None
      }
    }
    _ -> None
  }
  let reply = new_reply_subject()
  let request =
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
    )
  let request = case msg.method {
    "tools/call" -> {
      let #(tool, args) = tool_arguments(raw, msg)
      case list.contains(["knowledge_search", "zk_transclude"], tool) {
        True ->
          DispatchKnowledge(
            workspace_knowledge.prefetch_brain_memory(
              root,
              argument(args, "query", argument(args, "key", "")),
            ),
            request,
          )
        False -> request
      }
    }
    _ -> request
  }
  let request = case prefetched_observation {
    Some(snapshot) -> DispatchObserved(snapshot, request)
    None -> request
  }
  let request = case prefetched {
    Some(data) -> DispatchPublicPrefetched(data, request)
    None -> request
  }
  let outcome = await_public_dispatch(subject, request, reply, 3)
  close_reply_subject(reply)
  outcome
}

// Disk owns all evidence, including revocation and absence. Only actor intents
// survive a clean reload; quarantine replaces even those pending intents.
fn merge_live_features(
  projection: features.FeatureEvidenceStore,
  memory: features.FeatureEvidenceStore,
) -> features.FeatureEvidenceStore {
  case projection.admitted_ev_ceiling < 0 {
    True -> projection
    False -> features.merge_actor_intents(projection, memory.intents)
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
  case private_snapshot_with_recovery(subject, p, snapshot_timeout_ms, 3) {
    Error(_) -> refuse("GATEWAY_TIMEOUT", "Private snapshot timed out")
    Ok(#(subject, snapshot)) ->
      // Admission may observe subprocesses. This is the ingress caller, never
      // the state actor. Refresh UTC after waiting for the private lock.
      case
        prepare_private(
          snapshot,
          p,
          route,
          raw,
          msg,
          now_ms(),
          resolver,
          fn(call) {
            case snapshot.durable {
              False -> Ok(Nil)
              True -> {
                case
                  await_owner_reply(
                    subject,
                    fn(reply) { ReservePrivate(call, reply) },
                    snapshot_timeout_ms,
                  )
                {
                  Ok(result) -> result
                  Error(owner_down) ->
                    Error(private_error(
                      case owner_down {
                        True -> "GATEWAY_RESTARTING"
                        False -> "GATEWAY_TIMEOUT"
                      },
                      "Private reservation interrupted before effect",
                    ))
                }
              }
            }
          },
        )
      {
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
  case
    await_owner_reply(
      subject,
      fn(reply) { CommitPrivate(prepared, reply) },
      timeout_ms,
    )
  {
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

type OwnerReply(a) {
  OwnerReplied(a)
  ReplyOwnerDown
}

// Reply aliases are revoked before returning, dropping replies which arrive
// after a timeout as well as draining replies already in the caller mailbox.
fn await_owner_reply(
  subject: process.Subject(Message),
  request: fn(process.Subject(a)) -> Message,
  timeout: Int,
) -> Result(a, Bool) {
  case process.subject_owner(subject) {
    Error(_) -> Error(True)
    Ok(pid) -> {
      let monitor = process.monitor(pid)
      let reply = new_reply_subject()
      process.send(subject, request(reply))
      let selected =
        process.new_selector()
        |> process.select_map(reply, OwnerReplied)
        |> process.select_specific_monitor(monitor, fn(_) { ReplyOwnerDown })
        |> process.selector_receive(timeout)
      close_reply_subject(reply)
      process.demonitor_process(monitor)
      case selected {
        Ok(OwnerReplied(result)) -> Ok(result)
        Ok(ReplyOwnerDown) -> Error(True)
        Error(_) -> Error(False)
      }
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
        Ok(value.Null) -> Ok(value.Object([]))
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
fn private_wire_projection_fields(raw: String) -> Option(String) {
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

/// Pure projection only: callers must first gate the original frame/authentication.
fn public_wire_projection_fields(raw: String) -> Option(String) {
  use doc <- option.then(json.parse(raw, value.decoder()) |> option.from_result)
  use _ <- option.then(case value.get(doc, "method") {
    Ok(value.Text("tools/call")) -> Some(Nil)
    _ -> None
  })
  use params <- option.then(value.get(doc, "params") |> option.from_result)
  case value.get(params, "arguments") {
    Ok(value.Object(fields)) -> {
      let projected =
        list.map(fields, fn(pair) {
          #(pair.0, value.Text(public_argument_text(pair.1)))
        })
      case projected == fields {
        True -> None
        False ->
          Some(
            value.set(
              doc,
              "params",
              value.set(params, "arguments", value.Object(projected)),
            )
            |> value.encode
            |> json.to_string,
          )
      }
    }
    _ -> None
  }
}

fn public_argument_text(v: value.Value) -> String {
  case v {
    value.Text(s) -> s
    value.Integer(n) -> int.to_string(n)
    value.Number(n) -> float.to_string(n)
    value.Boolean(True) -> "true"
    value.Boolean(False) -> "false"
    value.Null -> "null"
    value.Array(_) | value.Object(_) -> json.to_string(value.encode(v))
  }
}

fn wire_projection(route: String, raw: String) -> Option(String) {
  case is_private_route(route) {
    True -> private_wire_projection(raw)
    False -> public_wire_projection(raw)
  }
}

fn without_field(document: value.Value, key: String) -> value.Value {
  case document {
    value.Object(fields) ->
      value.Object(list.filter(fields, fn(pair) { pair.0 != key }))
    _ -> document
  }
}

fn null_wire_projection(raw: String) -> String {
  case json.parse(raw, value.decoder()) {
    Error(_) -> raw
    Ok(doc) -> {
      let normalized = case value.get(doc, "method"), value.get(doc, "params") {
        Ok(value.Text(method)), Ok(value.Null) ->
          case
            list.contains(
              ["tools/list", "resources/list", "prompts/list", "ping"],
              method,
            )
          {
            True -> without_field(doc, "params")
            False -> doc
          }
        Ok(value.Text("tools/call")), Ok(params) ->
          case value.get(params, "arguments") {
            Ok(value.Null) ->
              value.set(doc, "params", without_field(params, "arguments"))
            _ -> doc
          }
        _, _ -> doc
      }
      case normalized == doc {
        True -> raw
        False -> normalized |> value.encode |> json.to_string
      }
    }
  }
}

fn private_wire_projection(raw: String) -> Option(String) {
  let normalized = null_wire_projection(raw)
  case private_wire_projection_fields(normalized) {
    Some(projected) -> Some(projected)
    None ->
      case normalized == raw {
        True -> None
        False -> Some(normalized)
      }
  }
}

pub fn public_wire_projection(raw: String) -> Option(String) {
  let normalized = null_wire_projection(raw)
  case public_wire_projection_fields(normalized) {
    Some(projected) -> Some(projected)
    None ->
      case normalized == raw {
        True -> None
        False -> Some(normalized)
      }
  }
}

fn original_request_id(raw: String) -> wire.WireId {
  case
    json.parse(raw, value.decoder())
    |> result.map_error(fn(_) { "invalid_json" })
    |> result.try(fn(v) { value.get(v, "id") })
  {
    Ok(value.Integer(n)) -> wire.IntId(n)
    Ok(value.Text(s)) -> wire.StringId(s)
    _ -> wire.NoIdNotification
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
      fn(call) { reserve_call(state, call) |> result.map(fn(_) { Nil }) },
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
    state.durable_key != None,
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
  reserve: fn(admission.ValidatedCall) -> Result(Nil, types.ToolError),
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
      use _ <- result.try(
        reserve(validated_call) |> result.map_error(types.Refused),
      )
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
  let pool = case outcome {
    types.Refused(_) ->
      supervisor.WorkerPool(
        ..pool,
        ledger: receipts.mark_complete(pool.ledger, prepared.intent_id, outcome),
      )
    _ -> pool
  }
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
  let args = case
    list.contains(["preflight_check", "verification_run"], tool)
    && argument(args, "check_id", "") == ""
  {
    True -> dict.insert(args, "check_id", "preflight_toolchain")
    False -> args
  }
  #(tool, args)
}

const public_grant_fields = [
  "grant_id", "worker_id", "workspace_root", "allowed_route", "allowed_tools",
  "scope", "revoked", "expires_at_ms", "plan_id", "task_id",
]

type PublicGrant {
  PublicGrant(
    grant_id: String,
    worker_id: String,
    workspace_root: String,
    allowed_route: String,
    allowed_tools: List(String),
    scope: types.AuthorityScope,
    revoked: Bool,
    expires_at_ms: Int,
    plan_id: String,
    task_id: String,
  )
}

fn invalid_public_grant() -> types.ToolError {
  private_error(
    "PUBLIC_GRANT_INVALID",
    "Public mutation grant is invalid or unreadable",
  )
}

// Walk every ancestor, including ancestors outside the workspace when an
// operator supplies an absolute grant-path override.
fn public_grant_path_safe(path: String) -> Bool {
  !feature_receipt_ledger.has_unsafe_ancestor(path)
}

fn public_grant_text(
  fields: value.Value,
  key: String,
) -> Result(String, types.ToolError) {
  case value.get(fields, key) {
    Ok(value.Text(text)) if text != "" -> Ok(text)
    _ -> Error(invalid_public_grant())
  }
}

fn parse_public_grant(raw: String) -> Result(PublicGrant, types.ToolError) {
  use parsed <- result.try(
    json_guard.native_inspect(raw, 16)
    |> result.map_error(fn(_) { invalid_public_grant() }),
  )
  use _ <- result.try(case parsed {
    value.Object(fields) ->
      case
        list.length(fields) == list.length(public_grant_fields)
        && list.all(fields, fn(pair) {
          list.contains(public_grant_fields, pair.0)
        })
      {
        True -> Ok(Nil)
        False -> Error(invalid_public_grant())
      }
    _ -> Error(invalid_public_grant())
  })
  use grant_id <- result.try(public_grant_text(parsed, "grant_id"))
  use worker_id <- result.try(public_grant_text(parsed, "worker_id"))
  use workspace <- result.try(public_grant_text(parsed, "workspace_root"))
  use route <- result.try(public_grant_text(parsed, "allowed_route"))
  use plan <- result.try(public_grant_text(parsed, "plan_id"))
  use task <- result.try(public_grant_text(parsed, "task_id"))
  use scope_name <- result.try(public_grant_text(parsed, "scope"))
  use scope <- result.try(case scope_name {
    "task_scoped_mutation" -> Ok(types.TaskScopedMutation)
    "control_mutation" -> Ok(types.ControlMutation)
    _ -> Error(invalid_public_grant())
  })
  use tools <- result.try(case value.get(parsed, "allowed_tools") {
    Ok(value.Array(items)) ->
      list.try_map(items, fn(item) {
        case item {
          value.Text(name) if name != "" -> Ok(name)
          _ -> Error(invalid_public_grant())
        }
      })
    _ -> Error(invalid_public_grant())
  })
  use revoked <- result.try(case value.get(parsed, "revoked") {
    Ok(value.Boolean(flag)) -> Ok(flag)
    _ -> Error(invalid_public_grant())
  })
  use expires <- result.try(case value.get(parsed, "expires_at_ms") {
    Ok(value.Integer(deadline)) -> Ok(deadline)
    _ -> Error(invalid_public_grant())
  })
  Ok(PublicGrant(
    grant_id,
    worker_id,
    workspace,
    route,
    tools,
    scope,
    revoked,
    expires,
    plan,
    task,
  ))
}

fn read_public_grant(
  root: String,
) -> Result(Option(PublicGrant), types.ToolError) {
  let path =
    env(
      "UOS_MCP_PUBLIC_GRANT_PATH",
      root <> "/var/harness/mcp_public_mutation_grant.json",
    )
  use _ <- result.try(case public_grant_path_safe(path) {
    True -> Ok(Nil)
    False -> Error(invalid_public_grant())
  })
  case simplifile.is_symlink(path), simplifile.is_file(path) {
    Ok(False), Ok(False) -> Ok(None)
    Ok(False), Ok(True) -> {
      use _ <- result.try(case simplifile.file_info(path) {
        Ok(info) if info.size > 0 && info.size <= 65_536 -> Ok(Nil)
        _ -> Error(invalid_public_grant())
      })
      use raw <- result.try(
        feature_receipt_ledger.read_bounded(path, 65_536)
        |> result.map_error(fn(_) { invalid_public_grant() }),
      )
      use _ <- result.try(
        case string.byte_size(raw) > 0 && string.byte_size(raw) <= 65_536 {
          True -> Ok(Nil)
          False -> Error(invalid_public_grant())
        },
      )
      let expected = env("UOS_MCP_PUBLIC_GRANT_SHA256", "")
      use _ <- result.try(case expected == "" {
        True ->
          Error(private_error(
            "PUBLIC_GRANT_UNPINNED",
            "Public mutation grant requires a SHA-256 pin",
          ))
        False -> Ok(Nil)
      })
      use _ <- result.try(
        case
          feature_receipt_ledger.valid_sha256(expected)
          && expected == files.digest(raw)
        {
          True -> Ok(Nil)
          False ->
            Error(private_error(
              "PUBLIC_GRANT_DIGEST_MISMATCH",
              "Public mutation grant SHA-256 mismatch",
            ))
        },
      )
      parse_public_grant(raw) |> result.map(Some)
    }
    _, _ -> Error(invalid_public_grant())
  }
}

fn ungranted_public_fence(
  p: principal.Principal,
  args: dict.Dict(String, String),
) -> Option(admission.TaskFence) {
  case
    dict.has_key(args, "task_id")
    && list.any(["plan_id", "task_id", "attempt", "grant_id"], fn(key) {
      dict.has_key(args, key)
    })
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
}

// ReadOnly and VerificationGate calls return before env, filesystem or SQLite
// access. Caller JSON is never used to create a grant or an executing fence.
fn resolve_public_mutation_authority(
  root: String,
  p: principal.Principal,
  route: String,
  tool: String,
  args: dict.Dict(String, String),
) -> Result(
  #(Option(admission.TaskFence), Option(route_convergence.RouteGrant)),
  types.ToolError,
) {
  case registry.lookup(route, tool) {
    Ok(spec)
      if route == "public"
      && {
        spec.effect_class == types.Mutating
        || spec.effect_class == types.ControlActuation
      }
    -> {
      use grant <- result.try(read_public_grant(root))
      case grant {
        None -> Ok(#(ungranted_public_fence(p, args), None))
        Some(grant) -> {
          use _ <- result.try(case grant.worker_id == principal.actor_id(p) {
            True -> Ok(Nil)
            False ->
              Error(private_error(
                "PRINCIPAL_WORKER_MISMATCH",
                "Public grant belongs to a different worker",
              ))
          })
          use _ <- result.try(case grant.workspace_root == root {
            True -> Ok(Nil)
            False ->
              Error(private_error(
                "ROUTE_GRANT_WORKSPACE_MISMATCH",
                "Public grant belongs to a different workspace",
              ))
          })
          use _ <- result.try(case grant.allowed_route == "public" {
            True -> Ok(Nil)
            False ->
              Error(private_error(
                "CROSS_ROUTE_GRANT_FORBIDDEN",
                "Public grant cannot authorize a different route",
              ))
          })
          use row <- result.try(
            canonical_planning_store.load_task_fence_row(
              root,
              grant.plan_id,
              grant.task_id,
            )
            |> result.map_error(fn(_) {
              private_error(
                "SA_PLAN_FENCE_UNAVAILABLE",
                "Live canonical Sa-plan task fence unavailable",
              )
            }),
          )
          let lifecycle = case row.0 {
            "executing" -> admission.TaskExecuting
            "completed" -> admission.TaskCompleted
            _ -> admission.TaskAvailable
          }
          let lease_until = case row.3 > 0 {
            True -> int.min(grant.expires_at_ms, row.3 / 1_000_000)
            False -> 0
          }
          let ticket =
            admission.GrantTicket(
              grant.grant_id,
              grant.scope,
              grant.revoked,
              grant.expires_at_ms,
              grant.workspace_root,
            )
          let fence =
            admission.TaskFence(
              grant.plan_id,
              grant.task_id,
              row.1,
              row.2,
              lifecycle,
              lease_until,
              Some(ticket),
            )
          Ok(#(
            Some(fence),
            Some(route_convergence.RouteGrant(
              "public",
              grant.allowed_tools,
              ticket,
            )),
          ))
        }
      }
    }
    _ -> Ok(#(None, None))
  }
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
    False ->
      dispatch_non_private(state, p, profile, route, raw, msg, now, None, None)
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
  _prefetched_gateway_alive: Option(Bool),
  prefetched_authority: Option(
    #(Option(admission.TaskFence), Option(route_convergence.RouteGrant)),
  ),
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
      let backends = state.backends
      let authority = {
        // Fresh quarantine is checked before reservation or replay; a cached
        // successful intent must never hide a now-corrupt disk projection.
        use _ <- result.try(case registry.lookup(route, tool) {
          Ok(spec) if spec.family == "feature_evidence" ->
            features.check_ceiling(backends.features)
          _ -> Ok(Nil)
        })
        case prefetched_authority {
          Some(binding) -> Ok(binding)
          None -> resolve_public_mutation_authority(root, p, route, tool, args)
        }
      }
      case authority {
        Error(error) -> #(types.Refused(error), state)
        Ok(#(fence, route_grant)) -> {
          let context =
            admission.AdmissionContext(
              p,
              admission.EnforcedMode,
              now,
              root,
              fence,
            )
          case
            route_convergence.admit_converged(
              context,
              route_grant,
              route,
              tool,
              args,
            )
          {
            Error(error) -> #(types.Refused(error), state)
            Ok(call) -> {
              let retain = case call.spec.effect_class {
                types.Mutating | types.ControlActuation -> True
                _ -> dict.has_key(args, "intent_id")
              }
              let reservation = case retain {
                True -> reserve_call(state, call)
                False -> Ok(state)
              }
              case reservation {
                Error(error) -> #(types.Refused(error), state)
                Ok(reserved) -> {
                  let cached = case retain {
                    True ->
                      receipts.lookup(
                        reserved.pool.ledger,
                        private_ledger_intent_id(call),
                      )
                    False -> None
                  }
                  let cached = refresh_live_read_receipt(reserved, call, cached)
                  case cached {
                    Some(receipts.ReceiptEntry(
                      state: receipts.OutcomeCommitted(outcome),
                      ..,
                    )) -> #(
                      route_convergence.verify_outcome_candidate(
                        reserved.pool,
                        backends.features,
                        route,
                        tool,
                        outcome,
                      ),
                      reserved,
                    )
                    Some(receipts.ReceiptEntry(
                      state: receipts.EffectUncertain(_),
                      ..,
                    )) -> #(
                      types.Refused(types.ToolError(
                        "UNCERTAIN_RECEIPT_RECONCILE_REQUIRED",
                        "Uncertain effect requires explicit reconciliation",
                        types.ReconcileFirst,
                      )),
                      reserved,
                    )
                    _ -> {
                      let #(outcome, pool, updated) =
                        server.execute_route_authenticated(
                          context,
                          route_grant,
                          reserved.pool,
                          backends,
                          route,
                          tool,
                          args,
                          fn(_, _) {
                            Error("Private calls require caller-side admission")
                          },
                        )
                      let outcome = case tool {
                        "preflight_check" ->
                          verification.with_preflight_utility(outcome, args)
                        _ -> outcome
                      }
                      let ledger = case outcome {
                        types.Complete(_, _) ->
                          receipts.mark_complete(
                            pool.ledger,
                            private_ledger_intent_id(call),
                            outcome,
                          )
                        types.Uncertain(receipt) ->
                          receipts.mark_uncertain(
                            pool.ledger,
                            private_ledger_intent_id(call),
                            receipt.reason,
                          ).1
                        types.Refused(_) ->
                          receipts.mark_complete(
                            pool.ledger,
                            private_ledger_intent_id(call),
                            outcome,
                          )
                      }
                      #(
                        outcome,
                        checkpoint_state(
                          GatewayState(
                            ..reserved,
                            pool: supervisor.WorkerPool(..pool, ledger: ledger),
                            backends: updated,
                          ),
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
      let state = case uri == "uos://system/mcp-gateway-health" {
        False -> state
        True -> {
          let content =
            health_json(
              supervised_gateway_pids_alive(state.supervised_gateway),
              state.pool.ledger.candidate,
            )
            |> json.to_string
          let registry =
            resources.ResourceRegistry(
              ..state.resources,
              resources: list.map(state.resources.resources, fn(entry) {
                case entry.uri == uri {
                  True -> resources.ResourceEntry(..entry, content: content)
                  False -> entry
                }
              }),
            )
          GatewayState(
            ..state,
            resources: registry,
            resource_cache: resources.ResourceCache(
              dict.delete(state.resource_cache.entries, #(
                principal.actor_id(p),
                principal.workspace_root(p),
                uri,
              )),
            ),
          )
        }
      }
      let live = case dict.get(state.backends.knowledge.entries, uri) {
        Ok(e) -> Some(e.content)
        Error(_) -> None
      }
      let registry = case live {
        Some(content) ->
          resources.ResourceRegistry(..state.resources, resources: [
            resources.ResourceEntry(
              uri,
              "Live Brain Memory",
              "text/plain",
              resources.PublicResource,
              "",
              principal.workspace_root(p),
              content,
            ),
            ..list.filter(state.resources.resources, fn(e) { e.uri != uri })
          ])
        None ->
          resources.ResourceRegistry(
            ..state.resources,
            resources: list.filter(state.resources.resources, fn(e) {
              !live_resource_uri(uri) || e.uri != uri
            }),
          )
      }
      let cache = case live_resource_uri(uri) {
        True -> resources.empty_cache()
        False -> state.resource_cache
      }
      case resources.read_resource(registry, cache, p, uri) {
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
          GatewayState(..state, resource_cache: case live_resource_uri(uri) {
            True -> state.resource_cache
            False -> cache
          }),
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

// Live reads retain capacity, idempotency and candidate evidence fences while
// recomputing the payload from the freshly prefetched backend. A forged cached
// candidate is still a hard refusal, and uncertain effects remain latched.
fn refresh_live_read_receipt(
  state: GatewayState,
  call: admission.ValidatedCall,
  cached: Option(receipts.ReceiptEntry),
) -> Option(receipts.ReceiptEntry) {
  let live_read =
    call.spec.effect_class == types.ReadOnly
    && list.contains(
      ["vault_metadata", "feature_evidence", "planning_read"],
      call.spec.family,
    )
  case cached {
    Some(
      receipts.ReceiptEntry(state: receipts.OutcomeCommitted(outcome), ..) as entry,
    )
      if live_read
    ->
      case
        !candidate_id.is_valid(entry.candidate)
        || entry.candidate != state.pool.ledger.candidate
        || entry.candidate != state.backends.features.active_candidate
      {
        True ->
          Some(
            receipts.ReceiptEntry(
              ..entry,
              state: receipts.OutcomeCommitted(
                types.Refused(private_error(
                  "CANDIDATE_EVIDENCE_MISMATCH",
                  "Retained observation receipt candidate does not match the active candidate",
                )),
              ),
            ),
          )
        False ->
          case outcome {
            types.Complete(_, _) ->
              case
                route_convergence.verify_outcome_candidate(
                  state.pool,
                  state.backends.features,
                  call.spec.route,
                  call.spec.name,
                  outcome,
                )
              {
                types.Refused(_) as refused ->
                  Some(
                    receipts.ReceiptEntry(
                      ..entry,
                      state: receipts.OutcomeCommitted(refused),
                    ),
                  )
                _ -> {
                  // Match the normalized outcome stored by mark_complete,
                  // without re-entering the authenticated execution path.
                  let live_outcome = case call.spec.family {
                    "feature_evidence" ->
                      features.execute(
                        state.backends.features,
                        call.spec.name,
                        call.arguments,
                      )
                    "vault_metadata" ->
                      vault_metadata.execute(state.backends.vault, call)
                    "planning_read" ->
                      planning_read.execute(
                        state.backends.planning_read,
                        call.spec.name,
                        call.arguments,
                      )
                    _ -> outcome
                  }
                  let live_outcome =
                    route_convergence.verify_outcome_candidate(
                      state.pool,
                      state.backends.features,
                      call.spec.route,
                      call.spec.name,
                      live_outcome,
                    )
                  case live_outcome == outcome {
                    True -> Some(entry)
                    False -> None
                  }
                }
              }
            types.Refused(_) -> None
            types.Uncertain(_) -> Some(entry)
          }
      }
    _ -> cached
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
    planning_read.AvailableStore(_, rows)
    | planning_read.MultiPlanStore(_, _, rows, _, _, _, _) ->
      list.find(rows, fn(row) {
        row.plan_id == plan_id
        && row.task_id == task_id
        && row.state == "executing"
      })
      |> option.from_result
    planning_read.UnavailableStore(_) | planning_read.UnknownPlanStore(_) ->
      None
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
  let profile =
    profile_for(
      http_auth.header(headers, "mcp-protocol-version") |> result.unwrap(""),
    )
  let route =
    http_auth.header(headers, "uos-mcp-route")
    |> result.unwrap(
      http_auth.header(headers, "x-uos-mcp-route") |> result.unwrap("public"),
    )
  let request = http.HttpRequest(method, path, headers, body)
  let response = case method == "POST" && path == "/mcp" {
    False ->
      http.handle(
        request,
        config,
        profile,
        now_ms,
        config.expected_audience,
        [config.expected_issuer],
        fn(_, _, _) { refuse("METHOD_NOT_FOUND", "No POST dispatch") },
      )
    True ->
      case http.prepare_standard(request, config, profile, now_ms) {
        Error(response) -> response
        Ok(#(p, _, sse)) -> {
          let permitted = case route {
            "development" ->
              http_auth.token_has_scope(
                config,
                headers,
                "mcp:development",
                now_ms,
              )
            "successor" ->
              http_auth.token_has_scope(
                config,
                headers,
                "mcp:successor",
                now_ms,
              )
            _ -> True
          }
          let reply = case permitted {
            True -> standard_raw(p, profile, route, body, now_ms, "HTTP")
            False ->
              Some(standard_response(
                original_request_id(body),
                "",
                refuse("HTTP_ROUTE_SCOPE_FORBIDDEN", "Token lacks route scope"),
              ))
          }
          case reply {
            None -> http.HttpResponse(202, http.security_headers(), "")
            Some(frame) -> {
              let frame = http_compatibility_result(frame)
              let status = case
                permitted,
                json.parse(frame, decode.at(["error", "code"], decode.int))
              {
                True, Ok(-32_700) | True, Ok(-32_600) -> 400
                _, _ -> 200
              }
              case sse {
                True ->
                  http.HttpResponse(
                    status,
                    [
                      #("Content-Type", "text/event-stream"),
                      ..http.security_headers()
                    ],
                    "event: message\ndata: " <> frame <> "\n\n",
                  )
                False ->
                  http.HttpResponse(
                    status,
                    [
                      #("Content-Type", "application/json"),
                      ..http.security_headers()
                    ],
                    frame,
                  )
              }
            }
          }
        }
      }
  }
  let response = http.with_cors(response, config, headers)
  #(response.status, response.headers, response.body)
}

// Older UOS HTTP clients consume result.value. Preserve that additive field
// alongside native MCP structured fields, without adding a second envelope.
fn http_compatibility_result(raw: String) -> String {
  case json.parse(raw, value.decoder()) {
    Ok(value.Array(items)) ->
      json.to_string(
        json.array(items, fn(item) {
          case
            json.parse(
              http_compatibility_result(json.to_string(value.encode(item))),
              value.decoder(),
            )
          {
            Ok(v) -> value.encode(v)
            _ -> value.encode(item)
          }
        }),
      )
    Ok(document) ->
      case value.get(document, "result") {
        Ok(value.Object(_) as result_value) -> {
          let payload = case value.get(result_value, "content") {
            Ok(value.Array([first, ..])) ->
              case value.get(first, "text") {
                Ok(value.Text(t)) -> t
                _ -> json.to_string(value.encode(result_value))
              }
            _ -> json.to_string(value.encode(result_value))
          }
          value.set(
            document,
            "result",
            value.set(result_value, "value", value.Text(payload)),
          )
          |> value.encode
          |> json.to_string
        }
        _ -> raw
      }
    _ -> raw
  }
}

pub fn handle_zenoh_with_secret(
  shared_secret: String,
  expected_client_id: String,
  profile: types.ProtocolProfile,
  envelope: zenoh_transport.SignedZenohEnvelope,
  now_ms: Int,
) -> Result(Option(#(String, String)), types.ToolError) {
  let observed =
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
  case observed {
    Error(types.ToolError("MALFORMED_JSONRPC", _, _)) ->
      case public_wire_projection(envelope.payload) {
        None -> observed
        Some(projected) -> {
          // The original envelope already passed HMAC, topic, byte, NUL and depth gates.
          // Authenticate only this deterministic local projection; identity fields never change.
          let signature =
            zenoh_transport.compute_signature(
              shared_secret,
              envelope.topic,
              envelope.reply_topic,
              envelope.sender_actor,
              envelope.client_name,
              envelope.workspace_root,
              envelope.session_id,
              projected,
            )
          zenoh_transport.handle_envelope(
            shared_secret,
            True,
            profile,
            expected_client_id,
            zenoh_transport.SignedZenohEnvelope(
              ..envelope,
              payload: projected,
              signature: signature,
            ),
            fn(p, msg) {
              dispatch_actor(
                p,
                profile,
                "public",
                envelope.payload,
                msg,
                now_ms,
              )
            },
          )
        }
      }
    _ -> observed
  }
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
      let projection = case rest {
        [_, ..] -> wire_projection(route, raw)
        _ -> None
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

fn request_id_json(id: wire.WireId) -> json.Json {
  case id {
    wire.IntId(n) -> json.int(n)
    wire.StringId(s) -> json.string(s)
    wire.NoIdNotification -> json.null()
  }
}

fn standard_error_code(code: String) -> Int {
  case code {
    "INVALID_JSON_SYNTAX" | "STDIO_INVALID_UTF8" | "HTTP_INVALID_UTF8" ->
      -32_700
    "METHOD_NOT_FOUND" -> -32_601
    "MISSING_URI"
    | "INVALID_CURSOR"
    | "MISSING_PROMPT_NAME"
    | "INVALID_PARAMS"
    | "UNSUPPORTED_PROTOCOL_VERSION"
    | "MISSING_RESOURCE_URI"
    | "EMPTY_RESOURCE_URI"
    | "RESOURCE_URI_REQUIRED"
    | "INVALID_RESOURCE_URI" -> -32_602
    "RESOURCE_NOT_FOUND" | "UNKNOWN_RESOURCE_URI" -> -32_002
    "GATEWAY_OVERLOADED"
    | "RECEIPT_LEDGER_CAPACITY_EXCEEDED"
    | "GATEWAY_TIMEOUT" -> -32_001
    "INTERNAL_ERROR" -> -32_603
    _ -> -32_600
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
          json.object(
            list.append(
              case json.parse(text, value.decoder()) {
                Ok(value.Object(_) as object) -> [
                  #("structuredContent", value.encode(object)),
                ]
                _ -> []
              },
              [
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
              ],
            ),
          )
        _ ->
          case json.parse(text, value.decoder()) {
            Ok(v) -> value.encode(v)
            _ -> json.string(text)
          }
      }
      #("result", payload)
    }
    types.Refused(error) ->
      case method, standard_error_code(error.code) {
        "tools/call", code if code != -32_001 -> #(
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
        _, _ -> #(
          "error",
          json.object([
            #(
              "data",
              json.object([
                #(
                  "retryable",
                  json.bool(
                    standard_error_code(error.code) == -32_001
                    || error.retryability == types.Retryable,
                  ),
                ),
                #("code", json.string(error.code)),
              ]),
            ),
            #("code", json.int(standard_error_code(error.code))),
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
  let raw =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", request_id_json(id)),
      response,
    ])
    |> json.to_string
  case json_guard.native_inspect(raw, 32) {
    Ok(value.Object(fields)) ->
      json_guard.encode_checked(fields)
      |> result.unwrap(
        "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"INVALID_OUTBOUND_ENVELOPE\"}}",
      )
    _ ->
      "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"INVALID_OUTBOUND_ENVELOPE\"}}"
  }
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

fn standard_document(
  p: principal.Principal,
  profile: types.ProtocolProfile,
  route: String,
  document: value.Value,
  now: Int,
) -> Option(String) {
  case document {
    value.Array(items) -> {
      let count = list.length(items)
      case items {
        [] ->
          Some(standard_response(
            wire.NoIdNotification,
            "",
            refuse("MALFORMED_JSONRPC", "empty batch"),
          ))
        _ if count > 64 ->
          Some(standard_response(
            wire.NoIdNotification,
            "",
            refuse("BATCH_TOO_LARGE", "Batch exceeds64items"),
          ))
        _ -> {
          let replies =
            list.filter_map(items, fn(item) {
              case item {
                value.Array(_) ->
                  Ok(
                    json.object([
                      #("jsonrpc", json.string("2.0")),
                      #("id", json.null()),
                      #(
                        "error",
                        json.object([
                          #("code", json.int(-32_600)),
                          #(
                            "message",
                            json.string(
                              "MALFORMED_JSONRPC: batch item must be a request object",
                            ),
                          ),
                        ]),
                      ),
                    ]),
                  )
                _ ->
                  case standard_document(p, profile, route, item, now) {
                    Some(reply) ->
                      json.parse(reply, value.decoder())
                      |> result.map(value.encode)
                      |> result.map_error(fn(_) { Nil })
                    None -> Error(Nil)
                  }
              }
            })
          case replies {
            [] -> None
            _ -> Some(json.to_string(json.preprocessed_array(replies)))
          }
        }
      }
    }
    value.Object(_) -> {
      let has_id = case value.get(document, "id") {
        Ok(_) -> True
        Error(_) -> False
      }
      let method = value.get(document, "method")
      // Absence and explicit null are distinct. Every method-bearing notification
      // is silent, including invalid params and unknown future notification names.
      case has_id, method {
        False, Ok(value.Text(_)) -> None
        _, _ -> {
          let id = case value.get(document, "id") {
            Ok(value.Integer(n)) -> wire.IntId(n)
            Ok(value.Text(s)) -> wire.StringId(s)
            _ -> wire.NoIdNotification
          }
          let valid_id = case value.get(document, "id") {
            Ok(value.Integer(_))
            | Ok(value.Text(_))
            | Ok(value.Null)
            | Error(_) -> True
            _ -> False
          }
          let raw = json.to_string(value.encode(document))
          case valid_id {
            False ->
              Some(standard_response(
                wire.NoIdNotification,
                "",
                refuse(
                  "MALFORMED_JSONRPC",
                  "id must be integer, string or null",
                ),
              ))
            True ->
              case validate_standard_document(document, raw, profile, route) {
                Error(error) ->
                  Some(standard_response(id, "", types.Refused(error)))
                Ok(msg) ->
                  Some(standard_response(
                    id,
                    msg.method,
                    dispatch_actor(p, profile, route, raw, msg, now),
                  ))
              }
          }
        }
      }
    }
    _ ->
      Some(standard_response(
        wire.NoIdNotification,
        "",
        refuse("MALFORMED_JSONRPC", "Request must be an object"),
      ))
  }
}

fn validate_standard_document(
  document: value.Value,
  raw: String,
  profile: types.ProtocolProfile,
  route: String,
) -> Result(wire.NormalizedMessage, types.ToolError) {
  use _ <- result.try(case value.get(document, "jsonrpc") {
    Ok(value.Text("2.0")) -> Ok(Nil)
    _ -> Error(private_error("MALFORMED_JSONRPC", "jsonrpc must be2.0"))
  })
  use _ <- result.try(case value.get(document, "method") {
    Ok(value.Text(_)) -> Ok(Nil)
    _ -> Error(private_error("MALFORMED_JSONRPC", "method must be a string"))
  })
  use _ <- result.try(case value.get(document, "params") {
    Error(_) -> Ok(Nil)
    Ok(value.Null) ->
      case value.get(document, "method") {
        Ok(value.Text(method)) ->
          case
            list.contains(
              ["tools/list", "resources/list", "prompts/list", "ping"],
              method,
            )
          {
            True -> Ok(Nil)
            False ->
              Error(private_error(
                "INVALID_PARAMS",
                "method requires object params",
              ))
          }
        _ -> Error(private_error("INVALID_PARAMS", "params must be an object"))
      }
    Ok(value.Object(_) as params) ->
      case value.get(params, "arguments") {
        Error(_) | Ok(value.Object(_)) | Ok(value.Null) -> Ok(Nil)
        _ ->
          Error(private_error("INVALID_PARAMS", "arguments must be an object"))
      }
    _ -> Error(private_error("INVALID_PARAMS", "params must be an object"))
  })
  use _ <- result.try(
    case value.get(document, "method"), value.get(document, "params") {
      Ok(value.Text("tools/call")), Ok(params) ->
        case value.get(params, "name") {
          Ok(value.Text(name)) if name != "" -> Ok(Nil)
          _ ->
            Error(private_error("INVALID_PARAMS", "tools/call requires name"))
        }
      Ok(value.Text("tools/call")), Error(_) ->
        Error(private_error("INVALID_PARAMS", "tools/call requires params"))
      _, _ -> Ok(Nil)
    },
  )
  let projected = option.unwrap(wire_projection(route, raw), raw)
  wire.decode_request(profile, projected)
  |> result.map_error(fn(error) { private_error(error.code, error.reason) })
}

fn standard_raw(
  p: principal.Principal,
  profile: types.ProtocolProfile,
  route: String,
  raw: String,
  now: Int,
  transport: String,
) -> Option(String) {
  case string.byte_size(raw) > 1_048_576 {
    True ->
      Some(standard_response(
        wire.NoIdNotification,
        "",
        refuse(
          transport <> "_FRAME_TOO_LARGE",
          "Frame exceeds1048576-byte limit",
        ),
      ))
    False ->
      case
        string.contains(raw, "\u{0000}")
        || string.contains(string.lowercase(raw), "\\u0000")
      {
        True ->
          Some(standard_response(
            original_request_id(raw),
            "",
            refuse(
              transport <> "_NUL_BYTE_FORBIDDEN",
              "NUL bytes are forbidden",
            ),
          ))
        False ->
          case json_guard.inspect(raw, transport) {
            Error(error) ->
              Some(standard_response(
                original_request_id(raw),
                "",
                types.Refused(error),
              ))
            Ok(document) -> standard_document(p, profile, route, document, now)
          }
      }
  }
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
      actor_id,
      types.ClientProfile(client_name),
      workspace_root,
      session_id,
    )
  standard_raw(p, profile, route, raw_line, now_ms, "STDIO")
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
    ReadError(reason) -> {
      io.println_error("MCP stdin: " <> reason)
      io.println(standard_response(
        wire.NoIdNotification,
        "",
        refuse(reason, "stdin frame rejected"),
      ))
      standard_loop(actor_id, client, root, session_id, route, profile)
    }
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
    ReadError(reason) -> {
      io.println_error(reason)
      io.println(standard_response(
        wire.NoIdNotification,
        "",
        refuse(reason, "stdin frame rejected"),
      ))
      canonical_loop(session, route)
    }
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

// Synchronous write-ahead mirror: a killed owner can never blindly replay an
// effect whose outcome was not acknowledged. Capacity refuses before execution.
fn reserve_call(
  state: GatewayState,
  call: admission.ValidatedCall,
) -> Result(GatewayState, types.ToolError) {
  let id = private_ledger_intent_id(call)
  let fresh = !dict.has_key(state.pool.ledger.entries, id)
  let readonly_keys = readonly_receipt_keys()
  let effects =
    list.count(dict.values(state.pool.ledger.entries), fn(entry) {
      case entry.state {
        receipts.OutcomeCommitted(_) -> !readonly_receipt(entry, readonly_keys)
        _ -> False
      }
    })
  use _ <- result.try(
    case
      fresh
      && {
        string.byte_size(id) > 1024
        || stored_bytes(state.pool.ledger) + 20_480 > 16_777_216
        || {
          call.spec.effect_class != types.ReadOnly
          && effects >= max_committed_receipts
        }
      }
    {
      True ->
        Error(types.ToolError(
          "RECEIPT_LEDGER_CAPACITY_EXCEEDED",
          "Receipt byte or effect-retention capacity exceeded before execution; reconcile retained effects",
          types.Retryable,
        ))
      False -> Ok(Nil)
    },
  )
  let unresolved =
    list.count(dict.values(state.pool.ledger.entries), fn(entry) {
      case entry.state {
        receipts.OutcomeCommitted(_) -> False
        _ -> True
      }
    })
  case
    !dict.has_key(state.pool.ledger.entries, id)
    && unresolved >= max_unresolved_receipts
  {
    True ->
      Error(types.ToolError(
        "RECEIPT_LEDGER_CAPACITY_EXCEEDED",
        "Unresolved receipt capacity exceeded; reconcile before new work",
        types.Retryable,
      ))
    False ->
      receipts.record_intent(
        state.pool.ledger,
        id,
        call.spec.route,
        call.spec.name,
        receipts.hash_payload(call.spec.name, dict.to_list(call.arguments)),
      )
      |> result.map(fn(ledger) {
        checkpoint_state(
          GatewayState(
            ..state,
            pool: supervisor.WorkerPool(..state.pool, ledger: ledger),
          ),
        )
      })
  }
}

// Ingress callers monitor the owner, so queued requests follow a replacement
// without a 15-second black hole. Re-admission always consults the rehydrated
// write-ahead ledger; uncertain effects refuse reconciliation instead of replay.
type PublicWait {
  PublicReply(types.Outcome)
  PublicOwnerDown
}

fn await_public_dispatch(
  subject: process.Subject(Message),
  request: Message,
  reply: process.Subject(types.Outcome),
  retries: Int,
) -> types.Outcome {
  case process.subject_owner(subject) {
    Error(_) -> refuse("GATEWAY_UNAVAILABLE", "Gateway subject has no owner")
    Ok(pid) -> {
      let monitor = process.monitor(pid)
      process.send(subject, request)
      let selected =
        process.new_selector()
        |> process.select_map(reply, PublicReply)
        |> process.select_specific_monitor(monitor, fn(_) { PublicOwnerDown })
        |> process.selector_receive(15_000)
      process.demonitor_process(monitor)
      case selected {
        Ok(PublicReply(outcome)) -> outcome
        Ok(PublicOwnerDown) if retries > 0 ->
          case wait_replacement_subject(50) {
            Some(next) ->
              await_public_dispatch(next, request, reply, retries - 1)
            None ->
              types.Refused(types.ToolError(
                "GATEWAY_RESTARTING",
                "Gateway is recovering; retry with backoff",
                types.Retryable,
              ))
          }
        _ ->
          types.Refused(types.ToolError(
            "GATEWAY_TIMEOUT",
            "MCP gateway call timed out",
            types.Retryable,
          ))
      }
    }
  }
}

fn wait_replacement_subject(
  remaining: Int,
) -> Option(process.Subject(Message)) {
  case stored_subject(gateway_key(), None) {
    Some(subject) ->
      case subject_alive(subject) {
        True -> Some(subject)
        False if remaining > 0 -> {
          process.sleep(1)
          wait_replacement_subject(remaining - 1)
        }
        False -> None
      }
    None if remaining > 0 -> {
      process.sleep(1)
      wait_replacement_subject(remaining - 1)
    }
    None -> None
  }
}

@external(erlang, "mcp_stdio_ffi", "gateway_supervisor_running")
fn gateway_supervisor_running() -> Bool

fn start_gateway_owner_supervisor() -> Bool {
  let root = workspace_root()
  let cand = candidate_id.from_root(root)
  case candidate_id.is_sha256_digest(cand) {
    False -> False
    True -> {
      // The state owner is a real supervisor child, with its subject
      // refreshed in persistent_term on every OTP restart.
      let box = owner_box_new()
      let child =
        supervision.worker(fn() {
          case
            cached_supervised_gateway(
              root <> ":" <> cand,
              supervisor.start_supervised_gateway,
            ),
            supervisor.start_worker_pool_for_candidate(size: 4, candidate: cand)
          {
            Ok(gateway), Ok(pool) -> {
              let state =
                durable_initial(root <> ":" <> cand, fn() {
                  process.unlink(gateway.supervisor_pid)
                  // Planning tools/tasks-create prefetch their real rows in
                  // ingress callers. Initialize/ping/list need no database IO.
                  new_state_with_planning(
                    root,
                    cand,
                    pool,
                    gateway,
                    planning_read.unavailable_store(
                      "Planning is prefetched per admitted request",
                    ),
                  )
                })
              let state = rehydrate_state(root <> ":" <> cand, state)
              case start_state_owner(state) {
                Ok(started) -> {
                  owner_box_set(box, Some(started.data))
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
        |> otp_supervisor.restart_tolerance(intensity: 20, period: 60)
        |> otp_supervisor.add(child)
        |> otp_supervisor.start
      {
        Ok(started) -> {
          process.unlink(started.pid)
          case register_or_stop_supervisor(started.pid) {
            True -> {
              owner_box_register(started.pid, box)
              is_running()
            }
            False -> is_running()
          }
        }
        Error(_) -> False
      }
    }
  }
}

type SnapshotWait {
  SnapshotReply(PrivateSnapshot)
  SnapshotOwnerDown
}

fn private_snapshot_with_recovery(
  subject: process.Subject(Message),
  p: principal.Principal,
  timeout: Int,
  retries: Int,
) -> Result(#(process.Subject(Message), PrivateSnapshot), Nil) {
  case process.subject_owner(subject) {
    Error(_) -> Error(Nil)
    Ok(pid) -> {
      let canonical_owner = stored_subject(gateway_key(), None) == Some(subject)
      let monitor = process.monitor(pid)
      let reply = new_reply_subject()
      process.send(subject, Snapshot(p, reply))
      let observed =
        process.new_selector()
        |> process.select_map(reply, SnapshotReply)
        |> process.select_specific_monitor(monitor, fn(_) { SnapshotOwnerDown })
        |> process.selector_receive(timeout)
      process.demonitor_process(monitor)
      close_reply_subject(reply)
      case observed {
        Ok(SnapshotReply(snapshot)) -> Ok(#(subject, snapshot))
        Ok(SnapshotOwnerDown) if retries > 0 && canonical_owner ->
          case wait_replacement_subject(100) {
            Some(next) ->
              private_snapshot_with_recovery(next, p, timeout, retries - 1)
            None -> Error(Nil)
          }
        _ -> Error(Nil)
      }
    }
  }
}

fn live_resource_uri(uri: String) -> Bool {
  list.any(
    ["uos://km/", "uos://wiki/", "uos://zk/", "uos://sop/", "uos://docs/"],
    fn(p) { string.starts_with(uri, p) },
  )
}

fn live_resource(root: String, uri: String) -> Option(String) {
  let target = case uri {
    "uos://km/triad" -> live_corpus.triad_manifest
    "uos://wiki/index" -> live_corpus.wiki_index
    "uos://zk/master-moc" -> live_corpus.zk_index
    "uos://sop/fractal-system-prompt" -> live_corpus.system_prompt
    "uos://wiki/" <> slug -> "docs/wiki/" <> slug
    "uos://zk/" <> slug -> "docs/zk/" <> slug
    "uos://sop/" <> slug -> "docs/sop/" <> slug
    "uos://docs/" <> slug ->
      case string.starts_with(slug, "docs/") {
        True -> slug
        False ->
          case live_corpus.stat(root, "docs/" <> slug) {
            Ok(_) -> "docs/" <> slug
            Error(_) ->
              case live_corpus.stat(root, slug) {
                Ok(_) -> slug
                Error(_) -> "docs/" <> slug
              }
          }
      }
    "uos://km/" <> path -> path
    _ -> ""
  }
  let candidates = case uri {
    "uos://wiki/" <> slug if slug != "index" ->
      live_corpus.resolve(live_corpus.children(root, "docs/wiki"), slug)
    "uos://zk/" <> slug if slug != "master-moc" ->
      live_corpus.resolve(live_corpus.children(root, "docs/zk"), slug)
    _ ->
      case live_corpus.stat(root, target) {
        Ok(e) -> [e]
        Error(_) ->
          case live_corpus.stat(root, target <> ".md") {
            Ok(e) -> [e]
            Error(_) -> []
          }
      }
  }
  case candidates {
    [entry] ->
      case live_corpus.brain_file(entry.path) {
        False -> None
        True ->
          case live_corpus.read(root, entry.path, 1_048_576) {
            Ok(text) -> Some(text)
            Error(_) -> None
          }
      }
    _ -> None
  }
}
