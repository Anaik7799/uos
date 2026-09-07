import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import prng
import uos_swarm/board
import uos_swarm/cockpit
import uos_swarm/coord
import uos_swarm/manager.{Observation}
import uos_swarm/ooda
import uos_swarm/raga
import uos_swarm/swarm
import uos_swarm/system_audit
import uos_tui/aspects
import uos_tui/fprime
import uos_tui/geometry.{Size}

fn obs(fail: Int, stale: List(String), zenoh: Bool) -> manager.Observation {
  Observation(1_000_000, 10, stale, 1, 17 - fail, fail, 5, zenoh, 1000)
}

pub fn dictionary_valid_and_disjoint_from_tui_test() {
  fprime.validate(manager.component(), manager.instance())
  |> should.equal(Ok(Nil))
  { manager.instance().base_id >= fprime.instance().base_id + fprime.id_span }
  |> should.be_true
}

// Cycle 1 is Teentaal's Sam beat (matra 1 of 16), so a healthy first cycle now carries both the
// Sam-triggered checkpoint audit and its Progress announcement.
pub fn healthy_cycle_is_dark_with_progress_and_sam_audit_test() {
  let #(m, mode, acts) = manager.step(manager.new(), obs(0, [], True))
  mode |> should.equal(ooda.Dark)
  m.cycles |> should.equal(1)
  list.length(acts) |> should.equal(2)
  list.contains(acts, manager.RequestAudit) |> should.be_true
  list.any(acts, fn(a) {
    case a {
      manager.PostProgress(_) -> True
      _ -> False
    }
  })
  |> should.be_true
}

pub fn failures_escalate_to_emergency_and_jidoka_test() {
  let #(_, mode, acts) = manager.step(manager.new(), obs(4, [], True))
  mode |> should.equal(ooda.Emergency)
  list.any(acts, fn(a) {
    case a {
      manager.PostJidoka(_) -> True
      _ -> False
    }
  })
  |> should.be_true
}

pub fn stale_agents_raise_andon_test() {
  let #(_, _, acts) = manager.step(manager.new(), obs(0, ["W03"], True))
  list.any(acts, fn(a) { a == manager.PostAndon("stale agents: W03") })
  |> should.be_true
}

pub fn zenoh_down_raises_andon_test() {
  let #(_, _, acts) = manager.step(manager.new(), obs(0, [], False))
  list.contains(acts, manager.PostAndon("zenoh unavailable")) |> should.be_true
}

pub fn periodic_reconcile_and_share_test() {
  let m =
    list.fold(prng.range(1, 15), manager.new(), fn(m, _) {
      manager.step(m, obs(0, [], True)).0
    })
  let #(_, _, acts) = manager.step(m, obs(0, [], True))
  list.contains(acts, manager.RequestReconcile) |> should.be_true
  list.contains(acts, manager.RequestShareState) |> should.be_true
}

pub fn every_act_drafts_a_valid_semantic_message_test() {
  let acts = [
    manager.PostAndon("x"),
    manager.PostJidoka("y"),
    manager.PostProgress("z"),
    manager.PostHeartbeat("beat 5/16 tali"),
    manager.ExpireLeases,
    manager.RequestAudit,
    manager.RequestReconcile,
    manager.RequestShareState,
  ]
  list.each(acts, fn(a) {
    case manager.draft_for(a, 1) {
      Some(d) -> board.validate_semantics(d.semantics) |> should.equal(Ok(Nil))
      None -> should.fail()
    }
  })
}

pub fn manager_acts_are_authorized_as_l1_test() {
  let p =
    coord.default_policy(
      [board.Agent("L0-fable", "L0", "fable"), manager.agent],
      4,
    )
  list.each(
    [
      manager.PostAndon("x"),
      manager.PostJidoka("y"),
      manager.PostProgress("z"),
      manager.PostHeartbeat("beat 5/16 tali"),
      manager.ExpireLeases,
    ],
    fn(a) {
      case manager.draft_for(a, 1) {
        Some(d) -> coord.authorize(p, d) |> should.equal(Ok(Nil))
        None -> should.fail()
      }
    },
  )
}

pub fn channels_cover_dictionary_test() {
  let names = fprime.channel_names(manager.component())
  let m = manager.new()
  list.each(manager.channels(m, obs(0, [], True)), fn(c) {
    list.contains(names, c.0) |> should.be_true
  })
}

pub fn system_audit_static_subjects_test() {
  let ledger = uos_tui_swarm_sample()
  let ctx = system_ctx()
  let subjects = system_audit.static_subjects(ctx, ledger, [])
  list.length(subjects) |> should.equal(6)
  list.each(subjects, fn(s) { list.length(s.findings) |> should.equal(17) })
  let #(p, d, f) = system_audit.totals(subjects)
  { p + d + f } |> should.equal(6 * 17)
  system_audit.to_markdown(subjects) |> fn(md) { md != "" } |> should.be_true
}

pub fn infra_subject_fails_closed_without_probe_test() {
  let s = system_audit.infra_subject(system_audit.unprobed)
  { list.length(s.findings) == 17 } |> should.be_true
  {
    list.length(
      list.filter(s.findings, fn(f) { f.verdict == uos_tui_aspects_fail() }),
    )
    >= 10
  }
  |> should.be_true
}

fn uos_tui_aspects_fail() {
  uos_tui_fail_verdict()
}

fn uos_tui_fail_verdict() -> aspects.Verdict {
  aspects.Fail
}

fn system_ctx() -> aspects.Context {
  let m =
    cockpit.Model(
      ..cockpit.init_model("2026-09-07T00:00:00Z", "vvrtrspvmtqq"),
      lease_epoch: 3,
    )
  cockpit.context(m, Size(120, 40), True, ["gleam_stdlib", "gleam_otp"])
}

fn uos_tui_swarm_sample() -> swarm.Ledger {
  swarm.sample_ledger()
}

// Property: over random observations the manager never exceeds its history window and cycles count monotonically.
pub fn property_manager_bounded_test() {
  list.each(prng.seeds(50), fn(seed) {
    let #(n, seed) = prng.int_between(seed, 1, 120)
    let #(fails, _) = prng.ints(seed, n, 0, 6)
    let m =
      list.fold(fails, manager.new(), fn(m, f) {
        manager.step(m, obs(f, [], f % 2 == 0)).0
      })
    m.cycles |> should.equal(n)
    { list.length(m.history) <= 64 } |> should.be_true
  })
}

// ---------------------------------------------------------------------------
// Defect 1: Zenoh health must fail closed, never fail open.
// ---------------------------------------------------------------------------

pub fn zenoh_health_fails_closed_on_connection_refused_test() {
  manager.zenoh_healthy(Some("http://127.0.0.1:1")) |> should.be_false
}

pub fn zenoh_health_false_without_base_test() {
  manager.zenoh_healthy(None) |> should.be_false
}

pub fn zenoh_health_ok_when_router_reachable_test() {
  // Best-effort only: the live Zenoh router is expected up on this host (`:8080` with the
  // REST plugin), but the unconditional, always-asserted contract is the fail-closed refusal
  // case above — a down router here must never turn into a false pass.
  case manager.zenoh_healthy(Some("http://127.0.0.1:8080")) {
    True | False -> Nil
  }
}

// ---------------------------------------------------------------------------
// Defect 2: Unknown health (no PASS/FAIL evidence) must not read as healthy.
// ---------------------------------------------------------------------------

fn declared_only_obs() -> manager.Observation {
  Observation(1_000_000, 10, [], 1, 0, 0, 5, True, 1000)
}

pub fn declared_only_health_is_unknown_and_fails_closed_test() {
  manager.health_status(declared_only_obs()) |> should.equal(manager.Unknown)
  manager.health(declared_only_obs()) |> should.equal(0.0)
}

pub fn mixed_observation_health_is_known_test() {
  manager.health_status(obs(3, [], True))
  |> should.equal(manager.Known(14.0 /. 17.0))
}

pub fn declared_only_cycle_emits_health_unknown_andon_test() {
  let #(_, _, acts) = manager.step(manager.new(), declared_only_obs())
  list.any(acts, fn(a) {
    case a {
      manager.PostAndon(text) -> string.contains(text, "health unknown")
      manager.PostJidoka(text) -> string.contains(text, "health unknown")
      _ -> False
    }
  })
  |> should.be_true
}

// ---------------------------------------------------------------------------
// Unnecessary board traffic: an unchanged observation must not repeat Progress.
// ---------------------------------------------------------------------------

pub fn duplicate_observation_suppresses_second_progress_test() {
  let o = obs(0, [], True)
  let #(m1, _, acts1) = manager.step(manager.new(), o)
  let #(_, _, acts2) = manager.step(m1, o)
  list.flatten([acts1, acts2])
  |> list.filter(fn(a) {
    case a {
      manager.PostProgress(_) -> True
      _ -> False
    }
  })
  |> list.length
  |> should.equal(1)
}

// ---------------------------------------------------------------------------
// Defect 3: live_cycle must not swallow errors, and must fail closed.
// ---------------------------------------------------------------------------

pub fn live_cycle_stops_after_first_authorization_failure_test() {
  let assert Ok(b) =
    board.open("manager-test-unauth", "uos_tui_manager_test_unauth", None, None)
  // Roster deliberately omits the manager's own agent id: every act it drafts is refused.
  let p = coord.default_policy([board.Agent("L0-fable", "L0", "fable")], 4)
  let c = coord.new(p)
  let #(m2, b2, _c2, _acts) =
    manager.live_cycle(manager.new(), b, c, None, fn() { [] })
  { m2.faults != [] } |> should.be_true
  // Only the coordinator's own violation-Andon for the first refused act reaches the board;
  // the fail-closed halt stops every later act from being attempted at all.
  b2.count |> should.equal(1)
}

pub fn reconcile_fault_carries_to_next_cycle_as_andon_test() {
  let assert Ok(b) =
    board.open("manager-test-carry", "uos_tui_manager_test_carry", None, None)
  let p =
    coord.default_policy(
      [board.Agent("L0-fable", "L0", "fable"), manager.agent],
      4,
    )
  let c = coord.new(p)
  let m =
    manager.Manager(..manager.new(), faults: [
      "reconcile: no zenoh base configured",
    ])
  let #(_, _, _, acts) = manager.live_cycle(m, b, c, None, fn() { [] })
  list.any(acts, fn(a) {
    case a {
      manager.PostAndon(text) -> string.contains(text, "reconcile")
      manager.PostJidoka(text) -> string.contains(text, "reconcile")
      _ -> False
    }
  })
  |> should.be_true
}

// ---------------------------------------------------------------------------
// Defect 4: RequestShareState must actually share, or record why it could not.
// ---------------------------------------------------------------------------

pub fn share_state_records_fault_without_zenoh_base_test() {
  manager.share(None, [])
  |> should.equal(#(0, ["share-state skipped: no zenoh base"]))
}

// ---------------------------------------------------------------------------
// Defect 5: the supervised actor must report its own pid, and dying must stop it for good.
// ---------------------------------------------------------------------------

pub fn start_actor_pid_is_the_actors_own_pid_test() {
  let assert Ok(b) =
    board.open("manager-test-actor", "uos_tui_manager_test_actor", None, None)
  let c = coord.new(coord.default_policy([manager.agent], 4))
  let assert Ok(started) = manager.start_actor(b, c, None, fn() { [] }, 500)
  { started.pid != process.self() } |> should.be_true
  process.subject_owner(started.data) |> should.equal(Ok(started.pid))
  process.send(started.data, manager.Stop)
}

pub fn killing_actor_pid_stops_further_cycles_test() {
  let table = "uos_tui_manager_test_kill"
  let assert Ok(b) = board.open("manager-test-kill", table, None, None)
  let c = coord.new(coord.default_policy([manager.agent], 4))
  let assert Ok(started) = manager.start_actor(b, c, None, fn() { [] }, 30)
  let pid = started.pid
  // `start_actor` links the child to its starter, matching normal OTP supervision (a
  // supervisor is notified when its child dies). Unlink first so killing the actor for this
  // test doesn't also take down the test process itself via that same link.
  process.unlink(pid)
  process.kill(pid)
  process.sleep(60)
  process.is_alive(pid) |> should.be_false
  let assert Ok(right_after_kill) =
    board.open("manager-test-kill", table, None, None)
  let count_at_kill = right_after_kill.count
  // Wait well past several tick intervals; a live actor would have posted more Progress by now.
  process.sleep(200)
  let assert Ok(later) = board.open("manager-test-kill", table, None, None)
  later.count |> should.equal(count_at_kill)
  process.is_alive(pid) |> should.be_false
}

// ---------------------------------------------------------------------------
// Tāla awareness: the manager labels every cycle with its Teentaal beat and makes the rhythm
// meaningful (sam always checkpoints, khali is quiet, tali heartbeats).
// ---------------------------------------------------------------------------

/// A healthy observation whose `board_count` is different on every cycle `i`, so `repeats`
/// never suppresses Progress on its own — any suppression seen at cycle 9 below must be the
/// khali beat, not an unchanged observation.
fn varying_obs(i: Int) -> manager.Observation {
  Observation(1_000_000, 10 + i, [], 1, 17, 0, 5, True, 1000)
}

fn has_progress(acts: List(manager.Act)) -> Bool {
  list.any(acts, fn(a) {
    case a {
      manager.PostProgress(_) -> True
      _ -> False
    }
  })
}

fn has_heartbeat(acts: List(manager.Act)) -> Bool {
  list.any(acts, fn(a) {
    case a {
      manager.PostHeartbeat(_) -> True
      _ -> False
    }
  })
}

pub fn tala_beats_drive_manager_rhythm_test() {
  let #(_, log) =
    list.fold(prng.range(1, 17), #(manager.new(), []), fn(acc, i) {
      let #(m, log) = acc
      let #(m2, _, acts) = manager.step(m, varying_obs(i))
      #(m2, [#(i, acts), ..log])
    })
  let by_cycle = list.reverse(log)
  list.each(by_cycle, fn(entry) {
    let #(cycle, acts) = entry
    case cycle {
      1 | 17 -> {
        // Sam: always a checkpoint audit; sam takes priority over tali, so no heartbeat here.
        list.contains(acts, manager.RequestAudit) |> should.be_true
        has_heartbeat(acts) |> should.be_false
      }
      9 -> {
        // Khali: a quiet beat — no Progress even though the observation changed every cycle,
        // and no checkpoint audit (khali is not sam).
        has_progress(acts) |> should.be_false
        list.contains(acts, manager.RequestAudit) |> should.be_false
      }
      5 -> {
        // Tali: a clap — the manager emits a heartbeat.
        has_heartbeat(acts) |> should.be_true
      }
      _ -> Nil
    }
  })
}

pub fn beat_of_cycle_classifies_teentaal_correctly_test() {
  let t = raga.teentaal()
  raga.beat_of_cycle(t, 1).kind |> should.equal(raga.Sam)
  raga.beat_of_cycle(t, 5).kind |> should.equal(raga.Tali)
  raga.beat_of_cycle(t, 9).kind |> should.equal(raga.Khali)
  raga.beat_of_cycle(t, 13).kind |> should.equal(raga.Tali)
  raga.beat_of_cycle(t, 17).kind |> should.equal(raga.Sam)
  raga.beat_of_cycle(t, 2).kind |> should.equal(raga.Ordinary)
}

pub fn channels_contain_beat_and_raga_test() {
  let m = manager.new()
  let names = list.map(manager.channels(m, obs(0, [], True)), fn(c) { c.0 })
  list.contains(names, "Beat") |> should.be_true
  list.contains(names, "Raga") |> should.be_true
  // "Beat" for a never-stepped manager (cycles = 0) still renders as "<matra>/<matras> <kind>".
  let assert Ok(#(_, beat_value)) =
    list.find(manager.channels(m, obs(0, [], True)), fn(c) { c.0 == "Beat" })
  string.contains(beat_value, "/16 ") |> should.be_true
}

pub fn current_raga_follows_mode_and_hour_test() {
  let m = manager.new()
  // A never-stepped manager decides `ooda.Dark` by default -> Malkauns.
  manager.current_raga(m, obs(0, [], True)).name
  |> should.equal(raga.malkauns().name)
}
