//// Track A live MCP ingress. The OTP owner serializes every transport's state.
//// Transport identity never supplies task/grant authority. EV ceiling stays 93.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/mcp as launcher
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
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/resources
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
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/atom
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
    supervised_gateway: supervisor.SupervisedGateway,
  )
}

type Message {
  Ping(process.Subject(Bool))
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

@external(erlang, "mcp_stdio_ffi", "register_or_stop_supervisor")
fn register_or_stop_supervisor(pid: process.Pid) -> Bool

@external(erlang, "mcp_stdio_ffi", "loaded_mcp_beams_digest")
fn loaded_mcp_beams_digest() -> String

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

fn gateway_alive(gateway: supervisor.SupervisedGateway) -> Bool {
  case
    process.is_alive(gateway.supervisor_pid)
    && subject_alive(gateway.gateway_subject)
  {
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
                    case
                      actor.new(state)
                      |> actor.on_message(handle_message)
                      |> actor.start
                    {
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
      observation: observation(cand, now_ms(), gateway),
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
  gateway: supervisor.SupervisedGateway,
) -> system_observation.ObservationBackend {
  let alive = gateway_alive(gateway)
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
        "gateway_ping; container names are configured inventory",
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
    Ping(reply) -> {
      process.send(reply, gateway_alive(state.supervised_gateway))
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
        dispatch_normalized(state, p, profile, route, raw, msg, now)
      process.send(reply, outcome)
      actor.continue(next)
    }
  }
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
      let #(prefetched_doc, prefetched_plan, prefetched_check) = case
        msg.method
      {
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
              Some(load_planning(
                root,
                argument(args, "plan_id", completion_plan),
              ))
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
            types.Modern20260728 ->
              Some(load_planning(workspace_root(), plan_id))
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
    _, _ -> refuse("GATEWAY_UNAVAILABLE", "OTP gateway could not start")
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
  let args = dict.from_list(msg.args)
  case msg.method {
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
            state.supervised_gateway,
          ),
        )
      // Caller fence/grant strings are bindings, not evidence of a live lease
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
          fn(_, _) { Error("Private live backend not bound") },
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
  let response =
    http.handle(
      http.HttpRequest(method, path, headers, body),
      config,
      profile,
      now_ms,
      config.expected_audience,
      [config.expected_issuer],
      fn(p, _clean, msg) {
        case route {
          "public" -> dispatch_actor(p, profile, route, body, msg, now_ms)
          "development" ->
            case
              http_auth.token_has_scope(
                config,
                headers,
                "mcp:development",
                now_ms,
              )
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
              http_auth.token_has_scope(
                config,
                headers,
                "mcp:successor",
                now_ms,
              )
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
      },
    )
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
  case string.byte_size(payload) <= 1_048_576, string.split(topic, "/") {
    True, ["indrajaal", "mcp", "request", client_id, _] ->
      case json.parse(payload, envelope_decoder(topic)) {
        Ok(envelope) if envelope.topic == topic ->
          handle_zenoh_with_secret(
            env("UOS_MCP_ZENOH_SHARED_SECRET", ""),
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
    _, _ -> None
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
  wire.decode_request(profile, raw)
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

fn standard_response(
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
  case validate_standard_line(raw_line, profile, p, now_ms) {
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
  let actor_id = env("UOS_MCP_ACTOR_ID", env("USER", "local-stdio-operator"))
  let client = env("UOS_MCP_CLIENT_NAME", "uos-stdio-client")
  let root = workspace_root()
  let session_id = env("UOS_MCP_SESSION_ID", "stdio-session-1")
  let route = env("UOS_MCP_ROUTE", "public")
  let profile = profile_for(env("UOS_MCP_PROTOCOL_VERSION", "2026-07-28"))
  let _ = ensure_started()
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
