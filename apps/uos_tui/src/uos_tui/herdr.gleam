//// Bounded Herdr adapter. Herdr is a terminal transport, not the UOS authority.
////
//// Target validation denotes the conjunction of pane equality, observed session
//// equality, identifiable session, safe lifecycle state and explicit cwd scope.
//// Strengthening any one constraint can only remove permission. The test oracle
//// evaluates the constraint AST independently of the short-circuit validator.
////
//// Every operation checks HERDR_ENV=1 in the OTP interpreter. Read/prompt use
//// fresh observations before and after the operation. Herdr's installed CLI has
//// no atomic expected-session argument: a prompt can race a replacement between
//// observations. Such a detected outcome is uncertain, never retried or called
//// an ACK. These metadata checks are not a filesystem sandbox or cryptographic
//// identity proof. Board authorization, leases and actual peer ACKs remain UOS
//// responsibilities.

import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const canonical_cwd = "/home/an/NAS-setup/uos"

pub const parent_cwd = "/home/an/NAS-setup"

pub const agy_runtime_cwd = "/home/an/dev/ver/zigvm"

pub const max_message_bytes = 4096

pub const max_output_bytes = 65_536

pub type Status {
  Idle
  Working
  Done
  Blocked
  Unknown(String)
}

pub type Session {
  Session(agent: String, kind: String, source: String, id: String)
}

pub type Agent {
  Agent(
    agent: String,
    pane_id: String,
    session: Option(Session),
    status: Status,
    cwd: String,
    foreground_cwd: Option(String),
  )
}

pub type Target {
  Target(pane_id: String, session_id: String)
}

pub type Scope {
  Scope(allow_parent: Bool, allow_agy_runtime: Bool)
}

pub fn strict_scope() -> Scope {
  Scope(False, False)
}

pub type ValidationError {
  InvalidTarget
  PaneChanged
  SessionUnavailable
  SessionChanged
  UnsafeStatus
  OutsideScope
  InvalidMessage
}

pub type Outcome {
  NotDispatched
  ReadFailed
  DispatchUncertain
}

pub type Failure {
  Failure(stage: String, reason: String, outcome: Outcome)
}

pub type Receipt {
  Receipt(agent: Agent, operation: String, output: String, scope: Scope)
}

@external(erlang, "uos_herdr_ffi", "run")
fn run_herdr(arguments: List(String)) -> Result(String, String)

pub fn status_from_string(value: String) -> Status {
  case value {
    "idle" -> Idle
    "working" -> Working
    "done" -> Done
    "blocked" -> Blocked
    other -> Unknown(other)
  }
}

pub fn status_to_string(value: Status) -> String {
  case value {
    Idle -> "idle"
    Working -> "working"
    Done -> "done"
    Blocked -> "blocked"
    Unknown(raw) -> raw
  }
}

pub fn safe_status(value: Status) -> Bool {
  case value {
    Idle | Working | Done -> True
    Blocked | Unknown(_) -> False
  }
}

fn printable_bytes(bytes: BitArray, multiline: Bool) -> Bool {
  case bytes {
    <<>> -> True
    <<byte:8, rest:bytes>> ->
      case byte < 32 || byte == 127 {
        True ->
          multiline
          && { byte == 9 || byte == 10 }
          && printable_bytes(rest, multiline)
        False -> printable_bytes(rest, multiline)
      }
    _ -> False
  }
}

fn identifier(value: String) -> Bool {
  value != ""
  && string.byte_size(value) <= 256
  && !string.starts_with(value, "-")
  && !string.contains(value, " ")
  && printable_bytes(<<value:utf8>>, False)
}

pub fn valid_target(target: Target) -> Bool {
  identifier(target.pane_id) && identifier(target.session_id)
}

pub fn validate_message(message: String) -> Result(Nil, ValidationError) {
  case
    string.trim(message) != ""
    && string.byte_size(message) <= max_message_bytes
    && printable_bytes(<<message:utf8>>, True)
  {
    True -> Ok(Nil)
    False -> Error(InvalidMessage)
  }
}

fn plain_absolute_path(path: String) -> Bool {
  string.starts_with(path, "/")
  && printable_bytes(<<path:utf8>>, False)
  && !list.any(string.split(path, "/"), fn(part) { part == "." || part == ".." })
  && !string.contains(path, "//")
}

pub fn within_uos(path: String) -> Bool {
  plain_absolute_path(path)
  && { path == canonical_cwd || string.starts_with(path, canonical_cwd <> "/") }
}

fn ordinary_cwd(path: String, scope: Scope) -> Bool {
  within_uos(path) || { scope.allow_parent && path == parent_cwd }
}

/// Scope checks both declared project cwd and observed foreground cwd. An AGY
/// daemon may run from its existing installation only with the explicit flag;
/// the project cwd must still be in UOS. Missing foreground metadata fails closed.
pub fn cwd_allowed(agent: Agent, scope: Scope) -> Bool {
  case agent.foreground_cwd {
    None -> False
    Some(foreground) ->
      { ordinary_cwd(agent.cwd, scope) && ordinary_cwd(foreground, scope) }
      || {
        scope.allow_agy_runtime
        && agent.agent == "agy"
        && within_uos(agent.cwd)
        && foreground == agy_runtime_cwd
      }
  }
}

pub fn validate_target(
  target: Target,
  live: Agent,
  scope: Scope,
) -> Result(Agent, ValidationError) {
  case valid_target(target), live.pane_id == target.pane_id {
    False, _ -> Error(InvalidTarget)
    True, False -> Error(PaneChanged)
    True, True -> {
      use session <- result.try(case live.session {
        Some(session) if session.kind == "id" && session.agent == live.agent ->
          case identifier(session.id) && identifier(session.source) {
            True -> Ok(session)
            False -> Error(SessionUnavailable)
          }
        _ -> Error(SessionUnavailable)
      })
      case
        session.id == target.session_id,
        safe_status(live.status),
        cwd_allowed(live, scope)
      {
        False, _, _ -> Error(SessionChanged)
        True, False, _ -> Error(UnsafeStatus)
        True, True, False -> Error(OutsideScope)
        True, True, True -> Ok(live)
      }
    }
  }
}

pub fn validation_reason(error: ValidationError) -> String {
  case error {
    InvalidTarget -> "invalid_target"
    PaneChanged -> "pane_changed"
    SessionUnavailable -> "session_unavailable"
    SessionChanged -> "session_changed"
    UnsafeStatus -> "blocked_or_unknown_status"
    OutsideScope -> "cwd_outside_explicit_scope"
    InvalidMessage -> "empty_oversized_or_control_message"
  }
}

fn session_decoder() -> decode.Decoder(Session) {
  use agent <- decode.field("agent", decode.string)
  use kind <- decode.field("kind", decode.string)
  use source <- decode.field("source", decode.string)
  use id <- decode.field("value", decode.string)
  decode.success(Session(agent, kind, source, id))
}

fn agent_decoder() -> decode.Decoder(Agent) {
  use agent <- decode.field("agent", decode.string)
  use pane <- decode.field("pane_id", decode.string)
  use session <- decode.optional_field(
    "agent_session",
    None,
    decode.optional(session_decoder()),
  )
  use status <- decode.field("agent_status", decode.string)
  use cwd <- decode.field("cwd", decode.string)
  use foreground <- decode.optional_field(
    "foreground_cwd",
    None,
    decode.optional(decode.string),
  )
  decode.success(Agent(
    agent,
    pane,
    session,
    status_from_string(status),
    cwd,
    foreground,
  ))
}

pub fn decode_agents(body: String) -> Result(List(Agent), String) {
  let decoder = {
    use agents <- decode.subfield(
      ["result", "agents"],
      decode.list(agent_decoder()),
    )
    decode.success(agents)
  }
  json.parse(body, decoder) |> result.replace_error("invalid_agent_list")
}

pub fn decode_agent(body: String) -> Result(Agent, String) {
  let decoder = {
    use agent <- decode.subfield(["result", "agent"], agent_decoder())
    decode.success(agent)
  }
  json.parse(body, decoder) |> result.replace_error("invalid_agent_info")
}

pub fn discover() -> Result(List(Agent), Failure) {
  use body <- result.try(
    run_herdr(["agent", "list"])
    |> result.map_error(fn(reason) {
      Failure("discover", reason, NotDispatched)
    }),
  )
  decode_agents(body)
  |> result.map_error(fn(reason) { Failure("discover", reason, NotDispatched) })
}

fn inspect(
  target: Target,
  scope: Scope,
  stage: String,
  outcome: Outcome,
) -> Result(Agent, Failure) {
  use _ <- result.try(case valid_target(target) {
    True -> Ok(Nil)
    False -> Error(Failure(stage, "invalid_target", outcome))
  })
  use body <- result.try(
    run_herdr(["agent", "get", target.pane_id])
    |> result.map_error(fn(reason) { Failure(stage, reason, outcome) }),
  )
  use live <- result.try(
    decode_agent(body)
    |> result.map_error(fn(reason) { Failure(stage, reason, outcome) }),
  )
  validate_target(target, live, scope)
  |> result.map_error(fn(reason) {
    Failure(stage, validation_reason(reason), outcome)
  })
}

pub fn read(target: Target, scope: Scope) -> Result(Receipt, Failure) {
  use before <- result.try(inspect(target, scope, "before_read", NotDispatched))
  use output <- result.try(
    run_herdr([
      "agent", "read", target.pane_id, "--source", "recent-unwrapped", "--lines",
      "80",
    ])
    |> result.map_error(fn(reason) { Failure("read", reason, ReadFailed) }),
  )
  use after <- result.try(inspect(target, scope, "after_read", ReadFailed))
  case before.agent == after.agent && before.session == after.session {
    True -> Ok(Receipt(after, "read", output, scope))
    False -> Error(Failure("after_read", "identity_changed", ReadFailed))
  }
}

pub fn prompt(
  target: Target,
  message: String,
  scope: Scope,
) -> Result(Receipt, Failure) {
  use _ <- result.try(
    validate_message(message)
    |> result.map_error(fn(reason) {
      Failure("message", validation_reason(reason), NotDispatched)
    }),
  )
  use before <- result.try(inspect(
    target,
    scope,
    "before_prompt",
    NotDispatched,
  ))
  use _ <- result.try(
    run_herdr(["agent", "prompt", target.pane_id, message])
    |> result.map_error(fn(reason) {
      Failure("prompt", reason, DispatchUncertain)
    }),
  )
  use after <- result.try(inspect(
    target,
    scope,
    "after_prompt",
    DispatchUncertain,
  ))
  case before.agent == after.agent && before.session == after.session {
    True -> Ok(Receipt(after, "prompt", "", scope))
    False ->
      Error(Failure("after_prompt", "identity_changed", DispatchUncertain))
  }
}

fn optional_string(value: Option(String)) -> json.Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

pub fn agent_to_json(agent: Agent) -> json.Json {
  let #(session_id, session_source, session_kind) = case agent.session {
    Some(session) -> #(
      Some(session.id),
      Some(session.source),
      Some(session.kind),
    )
    None -> #(None, None, None)
  }
  json.object([
    #("agent", json.string(agent.agent)),
    #("pane_id", json.string(agent.pane_id)),
    #("session_id", optional_string(session_id)),
    #("session_source", optional_string(session_source)),
    #("session_kind", optional_string(session_kind)),
    #("status", json.string(status_to_string(agent.status))),
    #("cwd", json.string(agent.cwd)),
    #("foreground_cwd", optional_string(agent.foreground_cwd)),
    #("scope_allowed_by_default", json.bool(cwd_allowed(agent, strict_scope()))),
  ])
}

pub fn receipt_to_json(receipt: Receipt) -> json.Json {
  json.object([
    #("ok", json.bool(True)),
    #("operation", json.string(receipt.operation)),
    #("agent", agent_to_json(receipt.agent)),
    #("output", json.string(receipt.output)),
    #(
      "dispatch",
      json.string(case receipt.operation {
        "prompt" -> "cli_returned_success"
        _ -> "not_dispatched"
      }),
    ),
    #("peer_acknowledged", json.bool(False)),
    #("binding", json.string("before_and_after_observation")),
    #("atomic_session_fence", json.bool(False)),
    #("allow_parent", json.bool(receipt.scope.allow_parent)),
    #("allow_agy_runtime", json.bool(receipt.scope.allow_agy_runtime)),
    #("automatic_retry", json.bool(False)),
  ])
}

pub fn failure_to_json(failure: Failure) -> json.Json {
  json.object([
    #("ok", json.bool(False)),
    #("stage", json.string(failure.stage)),
    #("reason", json.string(failure.reason)),
    #(
      "dispatch",
      json.string(case failure.outcome {
        NotDispatched -> "not_dispatched"
        ReadFailed -> "read_failed_output_discarded"
        DispatchUncertain -> "uncertain_do_not_retry"
      }),
    ),
    #("peer_acknowledged", json.bool(False)),
    #("automatic_retry", json.bool(False)),
  ])
}
