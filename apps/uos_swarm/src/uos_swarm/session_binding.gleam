//// C03: bind cooperative registry records to fresh Herdr observations.
//// These checks establish observed metadata agreement, not cryptographic IAM.
//// Prompt is advisory-only; no privileged action, terminal approval or retry.
//// The Herdr CLI has no atomic session fence. Independent peer ACK is required.

import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/result
import uos_swarm/herdr
import uos_swarm/session_sync as sync

@external(erlang, "uos_herdr_ffi", "current_pane")
fn current_pane() -> Result(String, String)

fn require(condition: Bool, reason: String) -> Result(Nil, String) {
  case condition {
    True -> Ok(Nil)
    False -> Error(reason)
  }
}

pub fn select(
  agents: List(herdr.Agent),
  pane: String,
) -> Result(herdr.Agent, String) {
  case list.filter(agents, fn(a) { a.pane_id == pane }) {
    [agent] -> Ok(agent)
    [] -> Error("peer_pane_absent")
    _ -> Error("peer_pane_ambiguous")
  }
}

pub fn validate(
  state: sync.State,
  target: herdr.Target,
  live: herdr.Agent,
  scope: herdr.Scope,
  expected_revision: String,
  boot: String,
  now: Int,
) -> Result(Nil, String) {
  use _ <- result.try(
    herdr.validate_target(target, live, scope)
    |> result.map_error(herdr.validation_reason),
  )
  use member <- result.try(
    dict.get(state.sessions, target.session_id)
    |> result.replace_error("peer_not_registered"),
  )
  use _ <- result.try(require(!member.retired, "peer_retired"))
  use _ <- result.try(require(
    member.provider == live.agent,
    "peer_provider_mismatch",
  ))
  use _ <- result.try(require(
    member.boot_id == boot
      && now >= member.heartbeat_us
      && now - member.heartbeat_us < sync.freshness_us,
    "peer_registry_stale",
  ))
  use _ <- result.try(require(
    expected_revision != "" && member.revision == expected_revision,
    "peer_candidate_mismatch",
  ))
  require(herdr.within_uos(member.workspace), "peer_workspace_outside_uos")
}

fn discover() -> Result(List(herdr.Agent), String) {
  herdr.discover() |> result.map_error(fn(f) { f.stage <> ":" <> f.reason })
}

pub fn inspect(
  root: String,
  target: herdr.Target,
  scope: herdr.Scope,
  expected_revision: String,
) -> Result(String, String) {
  use agents <- result.try(discover())
  use live <- result.try(select(agents, target.pane_id))
  sync.observe(root, fn(state, boot, now) {
    use _ <- result.try(validate(
      state,
      target,
      live,
      scope,
      expected_revision,
      boot,
      now,
    ))
    Ok(
      json.object([
        #("ok", json.bool(True)),
        #("binding", json.string("observed_metadata_agreement")),
        #("session", json.string(target.session_id)),
        #("candidate", json.string(expected_revision)),
        #("journal_sequence", json.int(state.sequence)),
        #("agent", herdr.agent_to_json(live)),
        #("atomic_session_fence", json.bool(False)),
        #("peer_ack", json.bool(False)),
        #("privileged_execution_authorized", json.bool(False)),
      ]),
    )
  })
}

/// Validation and Herdr each observe current identity. Their gap is disclosed;
/// only bounded advisory text crosses it, never an executable authority token.
pub fn prompt_advisory(
  root: String,
  target: herdr.Target,
  scope: herdr.Scope,
  expected_revision: String,
  message: String,
) -> Result(String, String) {
  use _ <- result.try(
    herdr.validate_message(message)
    |> result.map_error(herdr.validation_reason),
  )
  use observation <- result.try(inspect(root, target, scope, expected_revision))
  use receipt <- result.try(
    herdr.prompt(target, message, scope)
    |> result.map_error(fn(f) { f.stage <> ":" <> f.reason }),
  )
  Ok(
    json.to_string(
      json.object([
        #("registry_check", json.string(observation)),
        #("transport", herdr.receipt_to_json(receipt)),
        #("peer_ack", json.bool(False)),
        #("privileged_execution_authorized", json.bool(False)),
      ]),
    ),
  )
}

fn self(scope: herdr.Scope) -> Result(#(herdr.Agent, String), String) {
  use pane <- result.try(current_pane())
  use agents <- result.try(discover())
  use live <- result.try(select(agents, pane))
  case live.session {
    Some(session) -> {
      use _ <- result.try(
        herdr.validate_target(herdr.Target(pane, session.id), live, scope)
        |> result.map_error(herdr.validation_reason),
      )
      Ok(#(live, session.id))
    }
    _ -> Error("caller_session_unavailable")
  }
}

pub fn register_self(
  root: String,
  workspace: String,
  revision: String,
  refs: List(String),
  operation_id: String,
  scope: herdr.Scope,
) -> Result(String, String) {
  use _ <- result.try(require(
    herdr.within_uos(workspace),
    "caller_workspace_outside_uos",
  ))
  use #(live, id) <- result.try(self(scope))
  sync.execute(
    root,
    sync.Register(id, live.agent, workspace, revision, [
      "herdr:pane=" <> live.pane_id,
      "binding:observed-herdr-metadata",
      ..refs
    ]),
    operation_id,
  )
}

pub fn heartbeat_self(
  root: String,
  revision: String,
  refs: List(String),
  operation_id: String,
  scope: herdr.Scope,
) -> Result(String, String) {
  use #(live, id) <- result.try(self(scope))
  sync.execute(
    root,
    sync.Heartbeat(id, revision, [
      "herdr:pane=" <> live.pane_id,
      "binding:observed-herdr-metadata",
      ..refs
    ]),
    operation_id,
  )
}
