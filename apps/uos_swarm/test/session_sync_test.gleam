import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should
import uos_swarm/board
import uos_swarm/coord
import uos_swarm/session_sync as sync

@external(erlang, "session_sync_ffi", "unique_id")
fn unique_id() -> String

const host = "host-a"

const boot = "boot-a"

const now = 1_000_000

fn invoke(
  state: sync.State,
  command: sync.Command,
  id: String,
  tick: Int,
) -> Result(#(sync.State, sync.Receipt, Bool), String) {
  sync.apply(state, command, id, host, boot, tick, tick + 1_000_000_000)
}

fn registered() -> sync.State {
  list.fold(
    [#("codex", "codex"), #("claude", "claude"), #("agy", "agy")],
    sync.empty(),
    fn(s, pair) {
      let assert Ok(#(next, _, False)) =
        invoke(
          s,
          sync.Register(pair.0, pair.1, "/uos", "revision-a", [
            "herdr:pane=" <> pair.0,
          ]),
          "register-" <> pair.0,
          now,
        )
      next
    },
  )
}

fn state_dir() -> String {
  "/tmp/uos-session-sync-test-" <> unique_id()
}

pub fn registration_is_idempotent_only_for_exact_command_test() {
  let command = sync.Register("codex", "codex", "/uos", "revision-a", [])
  let assert Ok(#(state, receipt, False)) =
    invoke(sync.empty(), command, "registration", now)
  let assert Ok(#(repeated, replayed, True)) =
    invoke(state, command, "registration", now + 1)
  replayed |> should.equal(receipt)
  repeated.sequence |> should.equal(1)
  invoke(
    state,
    sync.Register("codex", "codex", "/uos", "revision-b", []),
    "registration",
    now,
  )
  |> should.be_error
}

pub fn no_unregistered_actor_or_unsupported_resource_test() {
  invoke(
    sync.empty(),
    sync.Claim("ghost", "integration/main", 10_000_000),
    "x",
    now,
  )
  |> should.be_error
  invoke(registered(), sync.Claim("codex", "shell:rm", 10_000_000), "x", now)
  |> should.be_error
  sync.valid_resource("workspace:/uos/../other") |> should.be_false
  sync.valid_resource("integration/main") |> should.be_true
  sync.valid_resource("runtime:cockpit") |> should.be_true
}

pub fn competing_claims_have_one_owner_and_independent_scopes_test() {
  let assert Ok(#(s1, grant, False)) =
    invoke(
      registered(),
      sync.Claim("codex", "integration/main", 30_000_000),
      "c1",
      now,
    )
  grant.epoch |> should.equal(1)
  invoke(s1, sync.Claim("claude", "integration/main", 30_000_000), "c2", now)
  |> should.be_error
  let assert Ok(#(s2, _, False)) =
    invoke(s1, sync.Claim("claude", "runtime:cockpit", 30_000_000), "c3", now)
  coord.live_leases(s2.coordinator, now) |> list.length |> should.equal(2)
  sync.check(s2, "claude", "integration/main", 1, boot, now) |> should.be_error
  sync.check(s2, "codex", "integration/main", 1, boot, now)
  |> should.equal(Ok(Nil))
}

pub fn expired_fence_cannot_renew_or_authorize_test() {
  let assert Ok(#(s1, _, _)) =
    invoke(
      registered(),
      sync.Claim("codex", "runtime:wiki", 1_000_000),
      "c1",
      now,
    )
  sync.check(s1, "codex", "runtime:wiki", 1, boot, now + 1_000_000)
  |> should.be_error
  invoke(
    s1,
    sync.Renew("codex", "runtime:wiki", 1, 2_000_000),
    "r1",
    now + 1_000_000,
  )
  |> should.be_error
  let assert Ok(#(s2, grant, _)) =
    invoke(
      s1,
      sync.Claim("claude", "runtime:wiki", 2_000_000),
      "c2",
      now + 1_000_000,
    )
  grant.epoch |> should.equal(2)
  sync.check(s2, "codex", "runtime:wiki", 1, boot, now + 1_000_000)
  |> should.be_error
}

pub fn release_preserves_epoch_and_stale_release_cannot_remove_successor_test() {
  let assert Ok(#(s1, _, _)) =
    invoke(
      registered(),
      sync.Claim("codex", "task:test", 10_000_000),
      "c1",
      now,
    )
  let assert Ok(#(s2, _, _)) =
    invoke(s1, sync.Release("codex", "task:test", 1), "r1", now)
  let assert Ok(#(s3, grant, _)) =
    invoke(s2, sync.Claim("claude", "task:test", 10_000_000), "c2", now)
  grant.epoch |> should.equal(2)
  invoke(s3, sync.Release("codex", "task:test", 1), "r2", now)
  |> should.be_error
  dict.get(s3.coordinator.epochs, "task:test") |> should.equal(Ok(2))
}

pub fn lease_ttl_is_bounded_test() {
  let s = registered()
  [-1, 0, 999_999, sync.max_ttl_us + 1]
  |> list.each(fn(ttl) {
    invoke(s, sync.Claim("codex", "task:bounded", ttl), "bounded", now)
    |> should.be_error
  })
}

pub fn stale_session_requires_heartbeat_before_new_claim_test() {
  let s = registered()
  let later = now + sync.freshness_us + 1
  invoke(s, sync.Claim("codex", "task:fresh", 1_000_000), "claim", later)
  |> should.be_error
  let assert Ok(#(fresh, _, _)) =
    invoke(
      s,
      sync.Heartbeat("codex", "revision-b", ["herdr:session=live-id"]),
      "beat",
      later,
    )
  invoke(fresh, sync.Claim("codex", "task:fresh", 1_000_000), "claim", later)
  |> should.be_ok
  let assert Ok(session) = dict.get(fresh.sessions, "codex")
  session.revision |> should.equal("revision-b")
}

pub fn reboot_invalidates_lease_but_keeps_epoch_counter_test() {
  let assert Ok(#(s1, _, _)) =
    invoke(
      registered(),
      sync.Claim("codex", "integration/main", 30_000_000),
      "c1",
      now,
    )
  let assert Ok(#(s2, _, _)) =
    sync.apply(
      s1,
      sync.Heartbeat("codex", "revision-b", []),
      "beat",
      host,
      "boot-b",
      100,
      200,
    )
  sync.check(s2, "codex", "integration/main", 1, "boot-b", 100)
  |> should.be_error
  let assert Ok(#(_, grant, _)) =
    sync.apply(
      s2,
      sync.Claim("codex", "integration/main", 30_000_000),
      "c2",
      host,
      "boot-b",
      100,
      200,
    )
  grant.epoch |> should.equal(2)
}

pub fn wrong_host_and_monotonic_regression_fail_closed_test() {
  let s = registered()
  sync.apply(
    s,
    sync.Heartbeat("codex", "r", []),
    "x",
    "other-host",
    boot,
    now,
    now,
  )
  |> should.be_error
  invoke(s, sync.Heartbeat("codex", "r", []), "x", now - 1) |> should.be_error
}

pub fn recipient_only_ack_and_broadcast_delivery_are_distinct_test() {
  let assert Ok(#(s1, msg, _)) =
    invoke(
      registered(),
      sync.Send("codex", "claude", board.Question, "Review the candidate", [
        "jj:change=abc",
      ]),
      "message-one",
      now,
    )
  sync.inbox(s1, "claude") |> list.length |> should.equal(1)
  invoke(s1, sync.Ack("agy", msg.message_id), "wrong-ack", now)
  |> should.be_error
  invoke(s1, sync.Ack("codex", msg.message_id), "self-ack", now)
  |> should.be_error
  let assert Ok(#(s2, _, _)) =
    invoke(s1, sync.Ack("claude", msg.message_id), "claude-ack", now)
  sync.inbox(s2, "claude") |> should.equal([])
  dict.get(s2.acknowledgements, msg.message_id) |> should.equal(Ok(["claude"]))
  let assert Ok(#(s3, _, _)) =
    invoke(
      s2,
      sync.Send("codex", "broadcast", board.Report, "Candidate ready", []),
      "broadcast",
      now,
    )
  let assert Ok(#(s4, _, _)) =
    invoke(s3, sync.Ack("claude", "broadcast"), "ack-broadcast", now)
  sync.inbox(s4, "agy") |> list.length |> should.equal(1)
}

pub fn control_messages_cannot_become_execution_authority_test() {
  [board.Dispatch, board.Integrate, board.Intent, board.LeaseGrant, board.Ack]
  |> list.each(fn(kind) {
    invoke(
      registered(),
      sync.Send("codex", "claude", kind, "execute", []),
      "control",
      now,
    )
    |> should.be_error
  })
  let assert Ok(#(state, _, _)) =
    invoke(
      registered(),
      sync.Send("codex", "claude", board.Report, "looks approved", []),
      "report",
      now,
    )
  dict.size(state.coordinator.leases) |> should.equal(0)
  let assert Ok(message) = dict.get(state.messages, "report")
  board.digest_ok(message) |> should.be_true
}

pub fn retired_session_cannot_reenter_with_old_identity_test() {
  let assert Ok(#(s, _, _)) =
    invoke(registered(), sync.Retire("codex"), "retire", now)
  invoke(s, sync.Heartbeat("codex", "r", []), "beat", now) |> should.be_error
  invoke(s, sync.Send("codex", "claude", board.Report, "x", []), "send", now)
  |> should.be_error
}

pub fn generated_release_acquire_trace_matches_independent_epoch_oracle_test() {
  // The reference denotation for a released resource is (no owner, last epoch).
  // Every next acquisition increments that independent integer exactly once.
  let #(final, expected_epoch) =
    int.range(1, 65, #(registered(), 0), fn(acc, i) {
      let #(state, epoch) = acc
      let holder = case i % 2 {
        0 -> "claude"
        _ -> "codex"
      }
      let other = case holder {
        "claude" -> "codex"
        _ -> "claude"
      }
      let assert Ok(#(claimed, receipt, _)) =
        invoke(
          state,
          sync.Claim(holder, "task:oracle", 5_000_000),
          "claim-" <> int.to_string(i),
          now,
        )
      receipt.epoch |> should.equal(epoch + 1)
      invoke(
        claimed,
        sync.Claim(other, "task:oracle", 5_000_000),
        "rival-" <> int.to_string(i),
        now,
      )
      |> should.be_error
      sync.check(claimed, holder, "task:oracle", epoch, boot, now)
      |> should.be_error
      let assert Ok(#(released, _, _)) =
        invoke(
          claimed,
          sync.Release(holder, "task:oracle", epoch + 1),
          "release-" <> int.to_string(i),
          now,
        )
      coord.live_leases(released.coordinator, now) |> should.equal([])
      #(released, epoch + 1)
    })
  dict.get(final.coordinator.epochs, "task:oracle")
  |> should.equal(Ok(expected_epoch))
}

pub fn journal_interpretation_matches_direct_observations_test() {
  let commands = [
    sync.Register("codex", "codex", "/uos", "r", []),
    sync.Register("claude", "claude", "/uos", "r", []),
    sync.Claim("codex", "integration/main", 10_000_000),
    sync.Send("codex", "claude", board.Question, "Review", []),
    sync.Ack("claude", "op-4"),
    sync.Release("codex", "integration/main", 1),
    sync.Claim("claude", "integration/main", 10_000_000),
  ]
  let #(direct, lines, _) =
    list.fold(commands, #(sync.empty(), [], 1), fn(acc, command) {
      let #(state, lines, index) = acc
      let id = "op-" <> int.to_string(index)
      let event = sync.make_event(state, command, id, host, boot, now, now)
      let assert Ok(#(next, _, _)) =
        sync.apply(state, command, id, host, boot, now, now)
      #(
        sync.State(..next, digest: event.digest),
        [sync.event_string(event), ..lines],
        index + 1,
      )
    })
  let assert Ok(restored) =
    sync.replay(lines |> list.reverse |> string.join("\n"))
  restored.coordinator.epochs |> should.equal(direct.coordinator.epochs)
  coord.live_leases(restored.coordinator, now)
  |> should.equal(coord.live_leases(direct.coordinator, now))
  sync.inbox(restored, "claude") |> should.equal(sync.inbox(direct, "claude"))
  restored.acknowledgements |> should.equal(direct.acknowledgements)
}

pub fn malformed_or_digest_changed_journal_is_not_silently_dropped_test() {
  let event =
    sync.make_event(
      sync.empty(),
      sync.Register("codex", "codex", "/uos", "r", []),
      "r",
      host,
      boot,
      now,
      now,
    )
  let text = sync.event_string(event)
  sync.replay(text <> "\nnot-json") |> should.be_error
  sync.replay(string.replace(text, "codex", "claude")) |> should.be_error
  sync.replay(text <> "\n" <> text) |> should.be_error
}

pub fn durable_restart_replay_and_duplicate_append_suppression_test() {
  let root = state_dir()
  let command = sync.Register("codex", "codex", "/uos", "r", [])
  sync.execute(root, command, "registration") |> should.be_ok
  sync.execute(root, command, "registration") |> should.be_ok
  sync.execute(
    root,
    sync.Claim("codex", "integration/main", 60_000_000),
    "claim",
  )
  |> should.be_ok
  let assert Ok(journal) = sync.read_journal(root)
  let assert Ok(state) = sync.replay(journal)
  state.sequence |> should.equal(2)
  dict.get(state.coordinator.epochs, "integration/main") |> should.equal(Ok(1))
  sync.execute(root, sync.Release("codex", "integration/main", 1), "release")
  |> should.be_ok
  sync.execute(
    root,
    sync.Claim("codex", "integration/main", 60_000_000),
    "claim2",
  )
  |> should.be_ok
  let assert Ok(next_journal) = sync.read_journal(root)
  let assert Ok(next) = sync.replay(next_journal)
  dict.get(next.coordinator.epochs, "integration/main") |> should.equal(Ok(2))
}

pub fn actual_concurrent_process_claims_have_single_winner_test() {
  let root = state_dir()
  [#("codex", "codex"), #("claude", "claude")]
  |> list.each(fn(pair) {
    sync.execute(
      root,
      sync.Register(pair.0, pair.1, "/uos", "r", []),
      "register-" <> pair.0,
    )
    |> should.be_ok
  })
  let replies = process.new_subject()
  ["codex", "claude"]
  |> list.each(fn(id) {
    process.spawn(fn() {
      let result =
        sync.execute(
          root,
          sync.Claim(id, "integration/main", 60_000_000),
          "claim-" <> id,
        )
      process.send(replies, result.is_ok(result))
    })
  })
  let assert Ok(first) = process.receive(replies, 3000)
  let assert Ok(second) = process.receive(replies, 3000)
  [first, second] |> list.filter(fn(x) { x }) |> list.length |> should.equal(1)
  let assert Ok(journal) = sync.read_journal(root)
  let assert Ok(state) = sync.replay(journal)
  dict.size(state.coordinator.leases) |> should.equal(1)
  state.sequence |> should.equal(3)
}

pub fn modified_event_fails_closed_without_regenerating_authority_test() {
  let root = state_dir()
  sync.execute(
    root,
    sync.Register("codex", "codex", "/uos", "r", []),
    "registration",
  )
  |> should.be_ok
  board.file_write(root <> "/events/0000000001.json", "invalid") |> should.be_ok
  sync.execute(root, sync.Heartbeat("codex", "r", []), "beat")
  |> should.be_error
  board.file_read(root <> "/events/0000000001.json")
  |> should.equal(Ok("invalid"))
}
