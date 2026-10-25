//// Development-only Mini logger control. Production listener never starts this actor.
//// Durable Sa-plan request identity prevents replay; ambiguous effects are never retried.
//// Cross-store fencing is cooperative. Logger read/set is not a global atomic CAS.

import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/telegram_conversation_model as chat_model
import uos_swarm/openrouter_worker as model
import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_store as history_store
import cepaf_gleam/telegram/mini_memory
import cepaf_gleam/planning/sa_plan_bridge as ledger
import cepaf_gleam/telegram/mini_api as api
import cepaf_gleam/telegram/types
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor as sup
import gleam/otp/supervision
import gleam/result
import gleam/string

pub const action_path = "/mini-app/api/action"

pub const receipt_path = "/mini-app/api/action-receipt"

type Unit {
  Millisecond
  Second
}

type Name {
  UosMiniDevelopmentControl
}

pub type Message {
  Execute(String, Bool, Int, process.Subject(response.Response(String)))
}

type Profile {
  Profile(
    config: api.Configuration,
    binding: dev.Binding,
    candidate: String,
    boot: String,
    host: String,
    expires: Int,
    digest: String,
    bot: String,
    memory: Option(mini_memory.Configuration),
    chat: Option(#(Int,Int)),
    io: model.Io,
  )
}

pub opaque type Intent {
  Intent(
    action: String,
    user: Int,
    chat: Option(Int),
    nonce: String,
    expected: String,
    target: String,
    prompt: String,
  )
}

pub type Outcome {
  Applied(String, String)
  Cleared(String)
  Chatted(String)
  Refused(String)
  Uncertain
}

type Job {
  Job(
    id: String,
    state: String,
    attempt: Int,
    args: String,
    owner: Option(String),
    deadline: Option(Int),
    receipt: Option(String),
  )
}

@external(erlang, "gleam_erlang_ffi", "identity")
fn name(value: Name) -> process.Name(Message)

@external(erlang, "erlang", "monotonic_time")
fn mono(unit: Unit) -> Int

@external(erlang, "erlang", "system_time")
fn wall(unit: Unit) -> Int

@external(erlang, "cepaf_gleam_ffi", "get_env")
fn env(key: String) -> Result(String, Nil)

@external(erlang, "mini_control_ffi", "safe_call")
fn safe_call(call: fn() -> a) -> Result(a, Nil)

@external(erlang, "mini_control_ffi", "change_logger")
fn change_logger(
  expected: String,
  target: String,
) -> Result(#(String, String), String)

pub fn owns(path: String) -> Bool {
  path == action_path || path == receipt_path
}

fn require(value: Bool, reason: String) -> Result(Nil, String) {
  case value {
    True -> Ok(Nil)
    False -> Error(reason)
  }
}

pub fn hex(text: String, size: Int) -> Bool {
  string.byte_size(text) == size
  && list.all(string.to_graphemes(text), fn(c) {
    string.contains("0123456789abcdef", c)
  })
}

pub fn level(text: String) -> Bool {
  list.contains(
    [
      "emergency",
      "alert",
      "critical",
      "error",
      "warning",
      "notice",
      "info",
      "debug",
      "all",
      "none",
    ],
    text,
  )
}

pub fn parse(
  body: String,
  config: api.Configuration,
  now: Int,
) -> Result(Intent, String) {
  use read <- result.try(
    api.authorize(body, config, now)
    |> result.map_error(fn(_) { "unauthorized" }),
  )
  use action <- result.try(json.parse(body,{ use a <- decode.field("action",decode.string) decode.success(a) })
    |> result.replace_error("invalid_request"))
  let memory = action == "clear_history" || action == "reset_history" || action == "send_message" || action == "abandon_message"
  use _ <- result.try(require(
    case memory { True -> api.page(read) == types.MiniConversation
      False -> api.page(read) == types.MiniTelemetry && action == "set_vm_logger_level" },
    "invalid_page_or_action"))
  let decoder = {
    use nonce <- decode.field("request_id",decode.string)
    use expected <- decode.field(
      case memory { True -> "expected_version" False -> "expected_level" },
      case memory { True -> decode.map(decode.int,int.to_string) False -> decode.string })
    use target <- decode.field(case memory { True -> "expected_sha256" False -> "target_level" },decode.string)
    decode.success(#(nonce,expected,target))
  }
  use #(nonce,expected,target) <- result.try(json.parse(body,decoder)
    |> result.replace_error("invalid_request"))
  use fields <- result.try(json.parse(body,decode.dict(decode.string,decode.dynamic))
    |> result.replace_error("invalid_request"))
  let base_keys = case memory {
    True -> ["init_data","path","action","request_id","expected_version","expected_sha256"]
    False -> ["init_data","path","action","request_id","expected_level","target_level"]
  }
  let keys = case action { "send_message" | "abandon_message" -> ["prompt",..base_keys] _ -> base_keys }
  use prompt <- result.try(case action {
    "send_message" | "abandon_message" -> json.parse(body,{ use p <- decode.field("prompt",decode.string) decode.success(p) }) |> result.replace_error("invalid_prompt")
    _ -> Ok("")
  })
  use _ <- result.try(require(dict.size(fields) == list.length(keys)
    && case action { "send_message" | "abandon_message" -> string.byte_size(prompt) > 0 && string.byte_size(prompt) <= 4096 _ -> True }
    && list.all(dict.keys(fields),fn(k) { list.contains(keys,k) }) && hex(nonce,32)
    && case memory {
      True -> case int.parse(expected) {
        Ok(0) -> target == ""
        Ok(v) if v > 0 && v <= 9_007_199_254_740_991 -> hex(target,64)
        _ -> False
      }
      False -> level(expected) && level(target) && expected != target
    }, "invalid_request"))
  Ok(Intent(action,api.user_id(read),api.chat_id(read),nonce,expected,target,prompt))
}

pub fn request_key(bot: String, intent: Intent) -> String {
  "mini-control/"
  <> files.digest(
    json.to_string(json.array(
      case intent.action {
        "set_vm_logger_level" -> [bot,int.to_string(intent.user),intent.action,intent.nonce]
        _ -> [bot,int.to_string(intent.user),intent.action,intent.nonce,case intent.chat { None -> int.to_string(intent.user) Some(c) -> int.to_string(c) }]
      },
      json.string,
    )),
  )
}

fn arguments(p: Profile, i: Intent) -> String {
  json.to_string(
    json.object(list.append([
      #("schema", json.string("uos.mini.control.v1")),
      #("profile_sha256", json.string(p.digest)),
      #("candidate", json.string(p.candidate)),
      #("boot", json.string(p.boot)),
      #("user", json.int(i.user)),
      #("action", json.string(i.action)),
      #("chat", case i.chat {
        None -> json.null()
        Some(id) -> json.int(id)
      }),
      #("expected", json.string(i.expected)),
      #("target", json.string(i.target)),
    ],case i.action {
      "send_message" | "abandon_message" -> [#("prompt_sha256",json.string(files.digest(i.prompt))),#("storage_binding",json.string(case p.memory {Some(c) -> mini_memory.storage_binding(c) None -> ""}))]
      _ -> []
    })),
  )
}

fn worker(p: Profile) -> String {
  "mini-control-" <> string.slice(p.digest, 0, 24)
}

fn read_job(id: String) -> Result(Option(Job), String) {
  use _ <- result.try(require(
    string.starts_with(id, "mini-control/")
      && hex(string.drop_start(id, 13), 64),
    "invalid_job",
  ))
  use raw <- result.try(dev.bounded(
    "/usr/bin/sqlite3",
    [
      "-readonly",
      "-json",
      dev.root <> "/var/sa-plan/uos.sqlite3",
      "SELECT id,state,attempt,args,lease_owner,lease_until_ns,result FROM sa_plan_job WHERE id='"
        <> id
        <> "';",
    ],
    3000,
  ))
  let decoder = {
    use id <- decode.field("id", decode.string)
    use state <- decode.field("state", decode.string)
    use attempt <- decode.field("attempt", decode.int)
    use args <- decode.field("args", decode.string)
    use owner <- decode.field("lease_owner", decode.optional(decode.string))
    use deadline <- decode.field("lease_until_ns", decode.optional(decode.int))
    use receipt <- decode.field("result", decode.optional(decode.string))
    decode.success(Job(id, state, attempt, args, owner, deadline, receipt))
  }
  case string.trim(raw) {
    "" -> Ok(None)
    _ ->
      case json.parse(raw, decode.list(decoder)) {
        Ok([]) -> Ok(None)
        Ok([job]) -> Ok(Some(job))
        _ -> Error("invalid_job_observation")
      }
  }
}

fn reply(
  code: Int,
  status: String,
  id: String,
  effect: json.Json,
  receipt: json.Json,
) -> response.Response(String) {
  response.new(code)
  |> response.set_body(
    json.to_string(
      json.object([
        #("status", json.string(status)),
        #("job_id", json.string(id)),
        #("effects_this_request", effect),
        #("retryable", json.bool(False)),
        #("receipt", receipt),
        #("scope", json.string("development_fixture_vm")),
      ]),
    ),
  )
  |> response.set_header("content-type", "application/json; charset=utf-8")
  |> response.set_header("cache-control", "no-store")
  |> response.set_header("x-content-type-options", "nosniff")
}

fn refused(code: Int, reason: String) -> response.Response(String) {
  reply(code, reason, "", json.int(0), json.null())
}

pub fn outcome_json(outcome: Outcome) -> json.Json {
  case outcome {
    Applied(before, after) ->
      json.object([
        #("status", json.string("applied")),
        #("prior_level", json.string(before)),
        #("observed_level", json.string(after)),
        #("effect_count", json.int(1)),
      ])
    Chatted(raw) -> json.object([#("status",json.string("chat_terminal")),#("native_receipt",json.string(raw))])
    Cleared(raw) -> json.object([#("status",json.string("history_cleared")),#("effect_count",json.int(1)),#("native_receipt",json.string(raw))])
    Refused(reason) ->
      json.object([
        #("status", json.string(reason)),
        #("effect_count", json.int(0)),
      ])
    Uncertain ->
      json.object([
        #("status", json.string("uncertain")),
        #("effect_count", json.null()),
      ])
  }
}

fn existing(
  p: Profile,
  intent: Intent,
  id: String,
) -> response.Response(String) {
  let bound_args = arguments(p, intent)
  case read_job(id) {
    Ok(Some(job)) if job.args != bound_args && intent.action != "send_message" && intent.action != "abandon_message" ->
      reply(409, "request_id_conflict", id, json.int(0), json.null())
    Ok(Some(job)) -> {
      case {intent.action == "send_message" || intent.action == "abandon_message"} && { !same_chat_arguments(job.args,bound_args) || case p.memory { None -> True Some(c) -> mini_memory.scope(c,intent.user,intent.chat) |> result.is_error } } {
        True -> reply(409,"request_id_conflict",id,json.int(0),json.null())
        False -> {
      let receipt = case job.receipt {
        Some(raw) -> json.string(raw)
        None -> json.null()
      }
      let recovered = case p.memory, intent.action {
        Some(c), "send_message" | Some(c), "abandon_message" ->
          case mini_memory.chat_receipt(c,intent.user,intent.chat,intent.nonce,original_chat_job(p,intent),intent.prompt,
            int.parse(intent.expected) |> result.unwrap(-1),intent.target) {
            Ok(Some(raw)) -> Some(json.to_string(outcome_json(Chatted(raw))))
            _ -> None
          }
        Some(c), action if action != "set_vm_logger_level" ->
          case mini_memory.receipt(c,intent.user,intent.chat,id,
            int.parse(intent.expected) |> result.unwrap(-1),intent.target) {
            Ok(Some(raw)) -> Some(raw)
            _ -> None
          }
        _, _ -> None
      }
      let receipt = case recovered { Some(raw) -> json.string(raw) None -> receipt }
      let status = case recovered { Some(_) -> "terminal_receipt" None -> case job.state {
        "completed" | "discarded" -> "terminal_receipt"
        "available" -> "unclaimed_no_replay"
        _ -> "uncertain_no_replay"
      }}
      reply(200, status, id, json.int(0), receipt)
      }
      }
    }
    Ok(None) -> reply(404, "receipt_not_found", id, json.int(0), json.null())
    Error(_) -> reply(503, "receipt_unavailable", id, json.int(0), json.null())
  }
}

fn fresh(p: Profile, body: String, deadline: Int) -> Result(Intent, String) {
  use fence <- result.try(dev.fence_for(p.binding, 25_000))
  let now = fence.clock.sample.observed.utc_us / 1_000_000
  use _ <- result.try(require(
    fence.clock.sample.observed.domain.boot_id == p.boot
      && fence.clock.sample.observed.domain.host_id == p.host
      && p.expires > now + 25
      && mono(Millisecond) < deadline,
    "fixture_clock_or_lease_expired",
  ))
  parse(body, p.config, now)
}

fn finish(
  p: Profile,
  id: String,
  outcome: Outcome,
) -> response.Response(String) {
  let payload = outcome_json(outcome)
  let code = case outcome {
    Applied(_, _) | Cleared(_) | Chatted(_) -> "OK"
    _ -> "ERROR"
  }
  case
    ledger.run_sa_plan_cli([
      "--job-complete",
      id,
      worker(p),
      "1",
      code,
      json.to_string(payload),
    ])
  {
    Ok(_) ->
      case outcome {
        Applied(_, _) | Cleared(_) | Chatted(_) -> reply(200, "applied", id, json.int(1), payload)
        Refused(reason) -> reply(409, reason, id, json.int(0), payload)
        Uncertain -> reply(202, "uncertain_no_replay", id, json.null(), payload)
      }
    Error(_) ->
      reply(202, "receipt_write_uncertain", id, json.null(), json.null())
  }
}

fn execute(
  p: Profile,
  body: String,
  receipt_only: Bool,
  deadline: Int,
) -> response.Response(String) {
  case parse(body, p.config, wall(Second)) {
    Error(reason) -> refused(401, reason)
    Ok(intent) -> {
      let id = request_key(p.bot, intent)
      case receipt_only {
        True -> existing(p, intent, id)
        False ->
          case fresh(p, body, deadline) {
            Error(reason) -> refused(403, reason)
            Ok(_) -> {
              let args = arguments(p, intent)
              let owner = Some(worker(p))
              // Only the process that observed successful INSERT may ever claim.
              // A timeout or duplicate goes to receipt lookup, never job-claim.
              case
                ledger.run_sa_plan_cli([
                  "--job-enqueue",
                  id,
                  id,
                  id,
                  worker(p),
                  args,
                  "1",
                ])
              {
                Error(_) -> existing(p, intent, id)
                Ok(_) -> {
                  let claim =
                    ledger.run_sa_plan_cli([
                      "--format",
                      "json",
                      "--job-claim",
                      id,
                      worker(p),
                      "60000000000",
                    ])
                  case claim {
                    Error(_) ->
                      reply(
                        202,
                        "claim_uncertain",
                        id,
                        json.null(),
                        json.null(),
                      )
                    Ok(_) ->
                      case read_job(id) {
                        Ok(Some(job))
                          if job.state == "executing"
                          && job.attempt == 1
                          && job.owner == owner
                          && job.args == args
                        -> {
                          case fresh(p, body, deadline) {
                            Error(reason) -> finish(p, id, Refused(reason))
                            Ok(current) -> {
                              // No blocking adapter between the final auth check and effect.
                              case
                                current == intent
                                && case job.deadline {
                                  Some(until) ->
                                    until
                                    > { wall(Second) + 25 } * 1_000_000_000
                                  None -> False
                                }
                              {
                                False ->
                                  finish(p, id, Refused("identity_changed"))
                                True ->
                                  apply_effect(p,intent,id,body,deadline)
                              }
                            }
                          }
                        }
                        _ ->
                          reply(
                            202,
                            "claim_not_verified",
                            id,
                            json.null(),
                            json.null(),
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
}

fn memory_job_current(p: Profile, id: String, deadline: Int) -> Bool {
  case read_job(id) {
    Ok(Some(j)) -> j.state == "executing" && j.attempt == 1 && j.owner == Some(worker(p))
      && mono(Millisecond) < deadline && case j.deadline {
        Some(until) -> until > {wall(Second) + 10} * 1_000_000_000
        None -> False
      }
    _ -> False
  }
}

fn apply_effect(p: Profile, intent: Intent, id: String, body: String, deadline: Int) -> response.Response(String) {
  case intent.action {
    "send_message" -> apply_chat(p,intent,id,body,deadline)
    "abandon_message" -> apply_chat_abandon(p,intent,id,body,deadline)
    "set_vm_logger_level" -> case change_logger(intent.expected,intent.target) {
      Ok(#(before,after)) -> finish(p,id,Applied(before,after))
      Error("level_mismatch") -> finish(p,id,Refused("level_mismatch"))
      Error(_) -> finish(p,id,Uncertain)
    }
    _ -> case p.memory {
      None -> finish(p,id,Refused("history_control_unavailable"))
      Some(c) -> case mini_memory.prepare(c,intent.user,intent.chat,id,
        int.parse(intent.expected) |> result.unwrap(-1),intent.target) {
        Error(reason) -> finish(p,id,Refused(reason))
        Ok(reservation) -> case fresh(p,body,deadline) {
          Error(reason) -> finish(p,id,Refused(reason))
          Ok(current) -> case current == intent {
            False -> finish(p,id,Refused("identity_changed"))
            True -> case memory_job_current(p,id,deadline) {
              False -> finish(p,id,Refused("job_lease_expired"))
              True -> case history_store.commit_mini_clear(reservation) {
              Ok(r) -> finish(p,id,Cleared(r.receipt.summary_json))
              Error(history_store.StoreBackendError(_)) ->
                finish(p,id,Refused("history_store_refused"))
              Error(_) -> finish(p,id,Uncertain)
              }
            }
          }
        }
      }
    }
  }
}

fn receive(p: Profile, message: Message) -> actor.Next(Profile, Message) {
  let Execute(body, receipt_only, deadline, to) = message
  let response = case mono(Millisecond) >= deadline {
    True -> refused(503, "request_deadline_before_admission")
    False -> execute(p, body, receipt_only, deadline)
  }
  process.send(to, response)
  actor.continue(p)
}

pub fn handle(req: request.Request(String)) -> response.Response(String) {
  case
    owns(req.path)
    && req.method == http.Post
    && string.byte_size(req.body) <= api.max_body_bytes
  {
    False -> refused(400, "invalid_request")
    True ->
      case
        request.get_header(req, "content-type")
        |> result.map(fn(s) {
          string.lowercase(string.trim(
            string.split(s, ";") |> list.first |> result.unwrap(""),
          ))
        })
      {
        Ok("application/json") -> {
          let deadline = mono(Millisecond) + 45_000
          safe_call(fn() {
            process.call(
              process.named_subject(name(UosMiniDevelopmentControl)),
              50_000,
              fn(to) {
                Execute(req.body, req.path == receipt_path, deadline, to)
              },
            )
          })
          |> result.unwrap(reply(
            503,
            "control_unavailable_or_uncertain",
            "",
            json.null(),
            json.null(),
          ))
        }
        _ -> refused(415, "json_required")
      }
  }
}

pub fn start_development_fixture() -> Result(Nil, String) {
  start_development_fixture_with_io(chat_model.live_io())
}

/// Dependency injection for private development. Production never starts this actor.
pub fn start_development_fixture_with_io(io: model.Io) -> Result(Nil,String) {
  use raw <- result.try(
    env("UOS_MINI_CONTROL_FIXTURE_PROFILE")
    |> result.map_error(fn(_) { "fixture_profile_missing" }),
  )
  use expected <- result.try(
    env("UOS_MINI_CONTROL_FIXTURE_SHA256")
    |> result.map_error(fn(_) { "fixture_profile_digest_missing" }),
  )
  use _ <- result.try(require(
    string.byte_size(raw) <= 8192
      && hex(expected, 64)
      && files.digest(raw) == expected,
    "fixture_profile_digest",
  ))
  let decoder = {
    use candidate <- decode.field("candidate", decode.string)
    use boot <- decode.field("boot", decode.string)
    use host <- decode.field("host", decode.string)
    use expires <- decode.field("expires", decode.int)
    use plan <- decode.field("plan", decode.string)
    use task <- decode.field("task", decode.string)
    use worker <- decode.field("worker", decode.string)
    use attempt <- decode.field("attempt", decode.int)
    use session <- decode.field("session", decode.string)
    use epoch <- decode.field("epoch", decode.int)
    use users <- decode.field("control_users", decode.list(decode.int))
    decode.success(#(
      candidate,
      boot,
      host,
      expires,
      dev.Binding("development", plan, task, worker, attempt, session, epoch),
      users,
    ))
  }
  use #(candidate, boot, host, expires, binding, users) <- result.try(
    json.parse(raw, decoder)
    |> result.map_error(fn(_) { "fixture_profile_invalid" }),
  )
  use _ <- result.try(require(
    hex(candidate, 40)
      && expires > wall(Second)
      && expires <= wall(Second) + 600,
    "fixture_profile_scope",
  ))
  use token <- result.try(
    env("UOS_TELEGRAM_MINI_BOT_TOKEN")
    |> result.map_error(fn(_) { "fixture_token_missing" }),
  )
  use bot <- result.try(
    string.split(token, ":")
    |> list.first
    |> result.map_error(fn(_) { "fixture_bot_missing" }),
  )
  use config <- result.try(
    api.configuration(
      token,
      list.map(users, fn(id) { api.AllowedIdentity(id, None) }),
      300,
    )
    |> result.map_error(fn(_) { "fixture_control_grants" }),
  )
  use memory <- result.try(mini_memory.configuration(raw,token))
  let chat_decoder = {
    use limit <- decode.field("daily_limit",decode.int)
    use timeout <- decode.field("timeout_ms",decode.int)
    decode.success(#(limit,timeout))
  }
  use chat <- result.try(json.parse(raw,{
    use chat <- decode.optional_field("chat",None,decode.optional(chat_decoder))
    decode.success(chat)
  }) |> result.replace_error("chat_profile_invalid"))
  use _ <- result.try(require(case chat {
    None -> True
    Some(#(limit,timeout)) -> limit > 0 && limit <= 1000 && timeout >= 100 && timeout <= 15_000 && memory != None
  },"chat_profile_bounds"))
  let p =
    Profile(config, binding, candidate, boot, host, expires, expected, bot, memory, chat, io)
  use fence <- result.try(dev.fence_for(binding, 25_000))
  use _ <- result.try(require(
    fence.clock.sample.observed.domain.boot_id == boot
      && fence.clock.sample.observed.domain.host_id == host,
    "fixture_host_boot",
  ))
  sup.new(sup.OneForOne)
  |> sup.add(
    supervision.worker(fn() {
      actor.new(p)
      |> actor.named(name(UosMiniDevelopmentControl))
      |> actor.on_message(receive)
      |> actor.start
    })
    |> supervision.restart(supervision.Temporary),
  )
  |> sup.start
  |> result.map(fn(_) { Nil })
  |> result.map_error(fn(_) { "fixture_control_start_failed" })
}

fn same_chat_arguments(old: String,current: String) -> Bool {
  let semantic = {
    use schema <- decode.field("schema",decode.string)
    use user <- decode.field("user",decode.int)
    use action <- decode.field("action",decode.string)
    use chat <- decode.field("chat",decode.optional(decode.int))
    use expected <- decode.field("expected",decode.string)
    use target <- decode.field("target",decode.string)
    use prompt <- decode.field("prompt_sha256",decode.string)
    use binding <- decode.field("storage_binding",decode.string)
    decode.success(#(schema,user,action,chat,expected,target,prompt,binding))
  }
  case json.parse(old,semantic),json.parse(current,semantic) {
    Ok(a),Ok(b) -> a == b
    _,_ -> False
  }
}
fn chat_authority(p: Profile,i: Intent,id: String,body: String,deadline: Int) -> Result(Int,String) {
  use current <- result.try(fresh(p,body,deadline))
  use _ <- result.try(require(current == i && memory_job_current(p,id,deadline),"chat_authority_expired"))
  Ok(int.min(15_000,deadline-mono(Millisecond)))
}
fn apply_chat(p: Profile,i: Intent,id: String,body: String,deadline: Int) -> response.Response(String) {
  case p.memory,p.chat {
    Some(c),Some(#(limit,timeout)) -> {
      let outcome = {
        use draft <- result.try(mini_memory.prepare_chat(c,i.user,i.chat,i.nonce,id,i.prompt,
          int.parse(i.expected) |> result.unwrap(-1),i.target,wall(Second) / 86_400,limit)
          |> result.map_error(Refused))
        use _ <- result.try(chat_authority(p,i,id,body,deadline) |> result.map_error(Refused))
        use reserved <- result.try(history_store.commit_mini_chat_reservation(draft)
          |> result.map_error(fn(_) { Uncertain }))
        let model_result = chat_model.run_mini(reserved,p.io,
          fn() { chat_authority(p,i,id,body,deadline) },timeout)
        // A model failure can be an uncertain remote outcome. Never resend it.
        use _ <- result.try(chat_authority(p,i,id,body,deadline) |> result.map_error(fn(_) { Uncertain }))
        use completed <- result.try(history_store.complete_mini_chat(reserved,
          case model_result { Ok(r) -> Some(r.reply) Error(_) -> None })
          |> result.map_error(fn(_) { Uncertain }))
        Ok(Chatted(completed.receipt.summary_json))
      }
      finish(p,id,case outcome { Ok(o) -> o Error(o) -> o })
    }
    _,_ -> finish(p,id,Refused("chat_control_unavailable"))
  }
}

fn original_chat_job(p: Profile,i: Intent) -> String {
  request_key(p.bot,Intent(..i,action:"send_message"))
}
fn apply_chat_abandon(p: Profile,i: Intent,id: String,body: String,deadline: Int) -> response.Response(String) {
  case p.memory {
    None -> finish(p,id,Refused("chat_control_unavailable"))
    Some(c) -> {
      let outcome = {
        use draft <- result.try(mini_memory.prepare_chat_abandon(c,i.user,i.chat,i.nonce,
          original_chat_job(p,i),i.prompt,int.parse(i.expected) |> result.unwrap(-1),i.target)
          |> result.map_error(Refused))
        use _ <- result.try(chat_authority(p,i,id,body,deadline) |> result.map_error(Refused))
        use done <- result.try(history_store.commit_mini_chat_abandon(draft)
          |> result.map_error(fn(_) { Uncertain }))
        Ok(Chatted(done.receipt.summary_json))
      }
      finish(p,id,case outcome { Ok(o) -> o Error(o) -> o })
    }
  }
}
