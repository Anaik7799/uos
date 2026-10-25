//// Development-only Mini logger control. Production listener never starts this actor.
//// Durable Sa-plan request identity prevents replay; ambiguous effects are never retried.
//// Cross-store fencing is cooperative. Logger read/set is not a global atomic CAS.

import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
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
  )
}

pub opaque type Intent {
  Intent(
    user: Int,
    chat: Option(Int),
    nonce: String,
    expected: String,
    target: String,
  )
}

pub type Outcome {
  Applied(String, String)
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
  use _ <- result.try(require(
    api.page(read) == types.MiniTelemetry,
    "invalid_page",
  ))
  let decoder = {
    use action <- decode.field("action", decode.string)
    use nonce <- decode.field("request_id", decode.string)
    use expected <- decode.field("expected_level", decode.string)
    use target <- decode.field("target_level", decode.string)
    decode.success(#(action, nonce, expected, target))
  }
  use #(action, nonce, expected, target) <- result.try(
    json.parse(body, decoder)
    |> result.map_error(fn(_) { "invalid_request" }),
  )
  use fields <- result.try(
    json.parse(body, decode.dict(decode.string, decode.dynamic))
    |> result.map_error(fn(_) { "invalid_request" }),
  )
  use _ <- result.try(require(
    dict.size(fields) == 6
      && list.all(dict.keys(fields), fn(k) {
      list.contains(
        [
          "init_data",
          "path",
          "action",
          "request_id",
          "expected_level",
          "target_level",
        ],
        k,
      )
    })
      && action == "set_vm_logger_level"
      && hex(nonce, 32)
      && level(expected)
      && level(target)
      && expected != target,
    "invalid_request",
  ))
  Ok(Intent(api.user_id(read), api.chat_id(read), nonce, expected, target))
}

pub fn request_key(bot: String, intent: Intent) -> String {
  "mini-control/"
  <> files.digest(
    json.to_string(json.array(
      [bot, int.to_string(intent.user), "set_vm_logger_level", intent.nonce],
      json.string,
    )),
  )
}

fn arguments(p: Profile, i: Intent) -> String {
  json.to_string(
    json.object([
      #("schema", json.string("uos.mini.control.v1")),
      #("profile_sha256", json.string(p.digest)),
      #("candidate", json.string(p.candidate)),
      #("boot", json.string(p.boot)),
      #("user", json.int(i.user)),
      #("chat", case i.chat {
        None -> json.null()
        Some(id) -> json.int(id)
      }),
      #("expected", json.string(i.expected)),
      #("target", json.string(i.target)),
    ]),
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
    Ok(Some(job)) if job.args != bound_args ->
      reply(409, "request_id_conflict", id, json.int(0), json.null())
    Ok(Some(job)) -> {
      let receipt = case job.receipt {
        Some(raw) -> json.string(raw)
        None -> json.null()
      }
      let status = case job.state {
        "completed" | "discarded" -> "terminal_receipt"
        "available" -> "unclaimed_no_replay"
        _ -> "uncertain_no_replay"
      }
      reply(200, status, id, json.int(0), receipt)
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
    Applied(_, _) -> "OK"
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
        Applied(_, _) -> reply(200, "applied", id, json.int(1), payload)
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
                                  case
                                    change_logger(
                                      intent.expected,
                                      intent.target,
                                    )
                                  {
                                    Ok(#(before, after)) ->
                                      finish(p, id, Applied(before, after))
                                    Error("level_mismatch") ->
                                      finish(p, id, Refused("level_mismatch"))
                                    Error(_) -> finish(p, id, Uncertain)
                                  }
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
  let p =
    Profile(config, binding, candidate, boot, host, expires, expected, bot)
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
