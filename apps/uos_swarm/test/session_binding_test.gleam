import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleeunit/should
import uos_swarm/herdr
import uos_swarm/session_binding as binding
import uos_swarm/session_sync as sync

fn live() -> herdr.Agent {
  herdr.Agent(
    "codex",
    "w2:p4",
    Some(herdr.Session("codex", "id", "herdr:codex", "actual-uuid")),
    herdr.Working,
    herdr.canonical_cwd,
    Some(herdr.canonical_cwd),
  )
}

fn target() -> herdr.Target {
  herdr.Target("w2:p4", "actual-uuid")
}

fn member() -> sync.Session {
  sync.Session(
    "actual-uuid",
    "codex",
    herdr.canonical_cwd,
    "candidate-1",
    [],
    "boot-1",
    100,
    False,
  )
}

fn state(member: sync.Session) -> sync.State {
  sync.State(..sync.empty(), sessions: dict.from_list([#(member.id, member)]))
}

fn validate(member: sync.Session) -> Result(Nil, String) {
  binding.validate(
    state(member),
    target(),
    live(),
    herdr.strict_scope(),
    "candidate-1",
    "boot-1",
    101,
  )
}

pub fn actual_member_matches_test() {
  validate(member()) |> should.equal(Ok(Nil))
}

pub fn alias_is_not_live_membership_test() {
  validate(sync.Session(..member(), id: "Codex-Astra"))
  |> should.equal(Error("peer_not_registered"))
}

pub fn retired_and_wrong_provider_denied_test() {
  validate(sync.Session(..member(), retired: True))
  |> should.equal(Error("peer_retired"))
  validate(sync.Session(..member(), provider: "claude"))
  |> should.equal(Error("peer_provider_mismatch"))
}

pub fn clock_domain_and_future_heartbeat_denied_test() {
  validate(sync.Session(..member(), boot_id: "other-boot"))
  |> should.equal(Error("peer_registry_stale"))
  validate(sync.Session(..member(), heartbeat_us: 102))
  |> should.equal(Error("peer_registry_stale"))
}

pub fn exact_freshness_boundary_test() {
  binding.validate(
    state(member()),
    target(),
    live(),
    herdr.strict_scope(),
    "candidate-1",
    "boot-1",
    100 + sync.freshness_us - 1,
  )
  |> should.equal(Ok(Nil))
  binding.validate(
    state(member()),
    target(),
    live(),
    herdr.strict_scope(),
    "candidate-1",
    "boot-1",
    100 + sync.freshness_us,
  )
  |> should.equal(Error("peer_registry_stale"))
}

pub fn candidate_and_registered_workspace_checked_test() {
  validate(sync.Session(..member(), revision: "old"))
  |> should.equal(Error("peer_candidate_mismatch"))
  validate(sync.Session(..member(), workspace: "/home/an/NAS-setup/uos-evil"))
  |> should.equal(Error("peer_workspace_outside_uos"))
}

pub fn unsafe_or_replaced_transport_denied_test() {
  list.each([herdr.Blocked, herdr.Unknown("unknown")], fn(status) {
    binding.validate(
      state(member()),
      target(),
      herdr.Agent(..live(), status: status),
      herdr.strict_scope(),
      "candidate-1",
      "boot-1",
      101,
    )
    |> should.equal(Error("blocked_or_unknown_status"))
  })
  binding.validate(
    state(member()),
    target(),
    herdr.Agent(
      ..live(),
      session: Some(herdr.Session("codex", "id", "herdr:codex", "replacement")),
    ),
    herdr.strict_scope(),
    "candidate-1",
    "boot-1",
    101,
  )
  |> should.equal(Error("session_changed"))
}

pub fn pane_resolution_is_unique_test() {
  binding.select([live()], "w2:p4") |> should.equal(Ok(live()))
  binding.select([], "w2:p4") |> should.equal(Error("peer_pane_absent"))
  binding.select([live(), live()], "w2:p4")
  |> should.equal(Error("peer_pane_ambiguous"))
}
