import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleeunit/should
import prng
import uos_tui/herdr

fn agent() -> herdr.Agent {
  herdr.Agent(
    "codex",
    "w2:p4",
    Some(herdr.Session("codex", "id", "herdr:codex", "session-1")),
    herdr.Working,
    herdr.canonical_cwd,
    Some(herdr.canonical_cwd),
  )
}

fn target() -> herdr.Target {
  herdr.Target("w2:p4", "session-1")
}

pub fn live_target_allowed_test() {
  herdr.validate_target(target(), agent(), herdr.strict_scope())
  |> should.equal(Ok(agent()))
}

pub fn stale_session_denied_test() {
  herdr.validate_target(
    herdr.Target("w2:p4", "previous"),
    agent(),
    herdr.strict_scope(),
  )
  |> should.equal(Error(herdr.SessionChanged))
}

pub fn replacement_pane_denied_test() {
  herdr.validate_target(
    herdr.Target("w2:p3", "session-1"),
    agent(),
    herdr.strict_scope(),
  )
  |> should.equal(Error(herdr.PaneChanged))
}

pub fn unavailable_identity_denied_test() {
  list.each(
    [
      None,
      Some(herdr.Session("codex", "heuristic", "herdr:codex", "session-1")),
      Some(herdr.Session("claude", "id", "herdr:codex", "session-1")),
      Some(herdr.Session("codex", "id", "", "session-1")),
    ],
    fn(session) {
      herdr.validate_target(
        target(),
        herdr.Agent(..agent(), session: session),
        herdr.strict_scope(),
      )
      |> should.equal(Error(herdr.SessionUnavailable))
    },
  )
}

pub fn blocked_unknown_future_statuses_denied_test() {
  list.each(
    [herdr.Blocked, herdr.Unknown("unknown"), herdr.Unknown("future")],
    fn(status) {
      herdr.validate_target(
        target(),
        herdr.Agent(..agent(), status: status),
        herdr.strict_scope(),
      )
      |> should.equal(Error(herdr.UnsafeStatus))
    },
  )
}

pub fn parent_is_explicit_and_exact_test() {
  let at_parent =
    herdr.Agent(
      ..agent(),
      cwd: herdr.parent_cwd,
      foreground_cwd: Some(herdr.parent_cwd),
    )
  herdr.cwd_allowed(at_parent, herdr.strict_scope()) |> should.be_false
  herdr.cwd_allowed(at_parent, herdr.Scope(True, False)) |> should.be_true
  herdr.cwd_allowed(
    herdr.Agent(..at_parent, foreground_cwd: Some(herdr.parent_cwd <> "/other")),
    herdr.Scope(True, False),
  )
  |> should.be_false
}

pub fn agy_runtime_exception_is_narrow_test() {
  let agy =
    herdr.Agent(
      ..agent(),
      agent: "agy",
      foreground_cwd: Some(herdr.agy_runtime_cwd),
    )
  herdr.cwd_allowed(agy, herdr.strict_scope()) |> should.be_false
  herdr.cwd_allowed(agy, herdr.Scope(False, True)) |> should.be_true
  herdr.cwd_allowed(
    herdr.Agent(..agy, agent: "codex"),
    herdr.Scope(False, True),
  )
  |> should.be_false
  herdr.cwd_allowed(
    herdr.Agent(..agy, cwd: herdr.parent_cwd),
    herdr.Scope(True, True),
  )
  |> should.be_false
  herdr.cwd_allowed(
    herdr.Agent(..agy, foreground_cwd: Some(herdr.agy_runtime_cwd <> "/other")),
    herdr.Scope(False, True),
  )
  |> should.be_false
}

pub fn malformed_path_and_foreground_unknown_denied_test() {
  list.each(
    [
      "/home/an/NAS-setup/uos-evil", "/home/an/NAS-setup/uos/../k8s-lab",
      "/home/an/NAS-setup/uos/./apps", "/home/an/NAS-setup/uos//apps",
      "relative", "/home/an/NAS-setup/uos\n",
    ],
    fn(path) { herdr.within_uos(path) |> should.be_false },
  )
  herdr.cwd_allowed(
    herdr.Agent(..agent(), foreground_cwd: None),
    herdr.strict_scope(),
  )
  |> should.be_false
}

pub fn message_byte_limit_and_control_sequences_test() {
  herdr.validate_message(string.repeat("x", 4096)) |> should.equal(Ok(Nil))
  herdr.validate_message(string.repeat("x", 4097))
  |> should.equal(Error(herdr.InvalidMessage))
  herdr.validate_message(string.repeat("🙂", 1025))
  |> should.equal(Error(herdr.InvalidMessage))
  list.each(
    ["", " \n\t", "yes\r", "\u{001b}[201~", "\u{0000}", "\u{0003}"],
    fn(message) {
      herdr.validate_message(message)
      |> should.equal(Error(herdr.InvalidMessage))
    },
  )
  herdr.validate_message("Read UOS; $(no shell) `literal`\nNext step\tplease.")
  |> should.equal(Ok(Nil))
}

pub fn option_like_and_control_targets_denied_test() {
  list.each(
    ["", "--current", "w2:p4\n", "w2:p4 extra", string.repeat("x", 257)],
    fn(pane) {
      herdr.valid_target(herdr.Target(pane, "session-1")) |> should.be_false
    },
  )
}

pub fn observed_schema_is_decoded_test() {
  let body =
    "{\"result\":{\"agents\":[{\"agent\":\"codex\",\"pane_id\":\"w2:p4\",\"agent_session\":{\"agent\":\"codex\",\"kind\":\"id\",\"source\":\"herdr:codex\",\"value\":\"session-1\"},\"agent_status\":\"working\",\"cwd\":\"/home/an/NAS-setup/uos\",\"foreground_cwd\":\"/home/an/NAS-setup/uos\"}]}}"
  herdr.decode_agents(body) |> should.equal(Ok([agent()]))
  herdr.decode_agents("{\"result\":{}}")
  |> should.equal(Error("invalid_agent_list"))
  herdr.decode_agents("not json") |> should.equal(Error("invalid_agent_list"))
}

// Initial interpretation of the deny-overrides conjunction. The production
// validator short-circuits to a reason; the observation here is permission only.
type Constraint {
  Fact(Bool)
  All(List(Constraint))
}

fn denote(rule: Constraint) -> Bool {
  case rule {
    Fact(value) -> value
    All(rules) -> list.all(rules, denote)
  }
}

fn oracle(target: herdr.Target, live: herdr.Agent, scope: herdr.Scope) -> Bool {
  let identity = case live.session {
    Some(session) ->
      session.agent == live.agent
      && session.kind == "id"
      && session.id == target.session_id
      && session.source != ""
    None -> False
  }
  denote(
    All([
      Fact(live.pane_id == target.pane_id),
      Fact(identity),
      Fact(herdr.safe_status(live.status)),
      Fact(herdr.cwd_allowed(live, scope)),
    ]),
  )
}

pub fn validation_denotation_and_scope_monotonicity_test() {
  // Fixed reproducible seeds cover combinations of stale identity, lifecycle,
  // canonical/parent/external paths and explicit scope strengthening.
  list.each(prng.seeds(300), fn(seed) {
    let #(n, _) = prng.int_between(seed, 0, 1023)
    let live =
      herdr.Agent(
        ..agent(),
        pane_id: case n % 2 {
          0 -> "w2:p4"
          _ -> "w2:p3"
        },
        session: case n / 2 % 2 {
          0 -> agent().session
          _ -> None
        },
        status: case n / 4 % 5 {
          0 -> herdr.Idle
          1 -> herdr.Working
          2 -> herdr.Done
          3 -> herdr.Blocked
          _ -> herdr.Unknown("future")
        },
        foreground_cwd: Some(case n / 20 % 3 {
          0 -> herdr.canonical_cwd
          1 -> herdr.parent_cwd
          _ -> "/tmp"
        }),
      )
    list.each(
      [
        herdr.Scope(False, False),
        herdr.Scope(True, False),
        herdr.Scope(True, True),
      ],
      fn(scope) {
        result.is_ok(herdr.validate_target(target(), live, scope))
        |> should.equal(oracle(target(), live, scope))
      },
    )
    case herdr.cwd_allowed(live, herdr.strict_scope()) {
      True -> herdr.cwd_allowed(live, herdr.Scope(True, True)) |> should.be_true
      False -> Nil
    }
  })
}
