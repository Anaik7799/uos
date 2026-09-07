import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import prng
import uos_tui/board.{Agent, Causality, Draft, Semantics}
import uos_tui/coord

fn roster() -> List(board.Agent) {
  [
    Agent("L0-fable", "L0", "fable"),
    Agent("uos-coord", "L1", "system"),
    Agent("W01", "L2", "sonnet"),
    Agent("W02", "L2", "sonnet"),
    Agent("V1", "L3", "haiku"),
  ]
}

fn policy() -> coord.Policy {
  coord.default_policy(roster(), 2)
}

fn d(from: board.Agent, to: String, kind: board.Kind) -> board.Draft {
  Draft(
    from,
    to,
    kind,
    [],
    Semantics([], [], [], [], 2),
    Causality(None, []),
    None,
    None,
  )
}

fn a(id: String) -> board.Agent {
  roster()
  |> list.find(fn(x) { x.id == id })
  |> fn(r) {
    case r {
      Ok(x) -> x
      Error(_) -> Agent(id, "L3", "?")
    }
  }
}

pub fn authority_matrix_test() {
  let p = policy()
  coord.authorize(p, d(a("L0-fable"), "broadcast", board.Plan))
  |> should.equal(Ok(Nil))
  coord.authorize(p, d(a("W01"), "L0-fable", board.Report))
  |> should.equal(Ok(Nil))
  coord.authorize(p, d(a("W01"), "broadcast", board.Plan))
  |> should.equal(Error(coord.KindNotAllowed(board.Plan, coord.L2)))
  coord.authorize(p, d(a("W01"), "broadcast", board.Dispatch))
  |> should.equal(Error(coord.KindNotAllowed(board.Dispatch, coord.L2)))
  coord.authorize(p, d(a("V1"), "L0-fable", board.Verdict))
  |> should.equal(Ok(Nil))
  coord.authorize(p, d(a("V1"), "W01", board.Integrate))
  |> should.equal(Error(coord.KindNotAllowed(board.Integrate, coord.L3)))
  coord.authorize(p, d(Agent("ghost", "L0", "x"), "broadcast", board.Plan))
  |> should.equal(Error(coord.UnknownAgent("ghost")))
  coord.authorize(p, d(a("W01"), "nobody", board.Report))
  |> should.equal(Error(coord.TargetNotAllowed("W01", "nobody")))
}

pub fn intent_only_upward_test() {
  let p = policy()
  coord.authorize(p, d(a("W01"), "L0-fable", board.Intent))
  |> should.equal(Ok(Nil))
  coord.authorize(p, d(a("W01"), "W02", board.Intent))
  |> should.equal(Error(coord.IntentMustGoUpward("W01", "W02")))
  coord.authorize(p, d(a("W01"), "broadcast", board.Intent))
  |> should.equal(Error(coord.IntentMustGoUpward("W01", "broadcast")))
}

pub fn control_keys_l0_l1_only_test() {
  let p = policy()
  let ctrl =
    Draft(
      a("W01"),
      "L0-fable",
      board.Report,
      [#("key", "uos/tui/control/leases")],
      Semantics([], [], [], [], 2),
      Causality(None, []),
      None,
      None,
    )
  coord.authorize(p, ctrl)
  |> should.equal(Error(coord.ControlKeyForbidden("W01")))
  coord.authorize(p, Draft(..ctrl, from: a("uos-coord")))
  |> should.equal(Ok(Nil))
}

pub fn fenced_lease_lifecycle_test() {
  let c = coord.new(policy())
  let #(c, l1) = case coord.acquire(c, "integration", "L0-fable", 100, 50) {
    Ok(v) -> v
    Error(_) -> #(c, coord.Lease("", "", 0, 0, 0))
  }
  l1.epoch |> should.equal(1)
  coord.acquire(c, "integration", "W01", 120, 50)
  |> should.equal(Error(coord.LeaseHeldByOther("integration", "L0-fable", 1)))
  coord.renew(c, "integration", "L0-fable", 7, 130, 50)
  |> should.equal(Error(coord.WrongEpoch("integration", 1, 7)))
  coord.release(c, "integration", "W01", 1)
  |> should.equal(Error(coord.LeaseHeldByOther("integration", "L0-fable", 1)))
  let c = case coord.release(c, "integration", "L0-fable", 1) {
    Ok(c) -> c
    Error(_) -> c
  }
  coord.release(c, "integration", "L0-fable", 1)
  |> should.equal(Error(coord.NoSuchLease("integration")))
  // expired lease can be taken by another holder with a higher epoch
  let #(c, _) = case coord.acquire(c, "r", "W01", 0, 10) {
    Ok(v) -> v
    Error(_) -> #(c, coord.Lease("", "", 0, 0, 0))
  }
  case coord.acquire(c, "r", "W02", 11, 10) {
    Ok(#(_, l)) -> l.epoch
    Error(_) -> -1
  }
  |> should.equal(2)
}

pub fn expire_drops_only_expired_test() {
  let c = coord.new(policy())
  let c = case coord.acquire(c, "a", "W01", 0, 10) {
    Ok(#(c, _)) -> c
    Error(_) -> c
  }
  let c = case coord.acquire(c, "b", "W02", 0, 100) {
    Ok(#(c, _)) -> c
    Error(_) -> c
  }
  let #(c, expired) = coord.expire(c, 50)
  list.map(expired, fn(l) { l.resource }) |> should.equal(["a"])
  list.map(coord.live_leases(c, 50), fn(l) { l.resource })
  |> should.equal(["b"])
}

pub fn claims_respect_wip_limit_test() {
  let c = coord.new(policy())
  let c = case coord.claim(c, "t1", "W01", 0, 100) {
    Ok(#(c, _)) -> c
    Error(_) -> c
  }
  let c = case coord.claim(c, "t2", "W02", 0, 100) {
    Ok(#(c, _)) -> c
    Error(_) -> c
  }
  coord.claim(c, "t3", "V1", 0, 100)
  |> should.equal(Error(coord.WipLimitReached(2)))
  // same agent re-claiming does not count against itself
  case coord.claim(c, "t4", "W01", 0, 100) {
    Ok(_) -> True
    Error(_) -> False
  }
  |> should.be_true
}

pub fn heartbeat_freshness_test() {
  let c =
    coord.new(policy()) |> coord.beat("W01", 1000) |> coord.beat("V1", 1500)
  coord.stale(c, 2000, 600)
  |> should.equal(["L0-fable", "uos-coord", "W01", "W02"])
  coord.stale(c, 2000, 2000) |> should.equal(["L0-fable", "uos-coord", "W02"])
  coord.stale(
    c
      |> coord.beat("L0-fable", 1999)
      |> coord.beat("uos-coord", 1999)
      |> coord.beat("W02", 1999),
    2000,
    600,
  )
  |> should.equal(["W01"])
}

pub fn lamport_merge_test() {
  let c = coord.new(policy())
  let #(c, one) = coord.tick(c)
  one |> should.equal(1)
  let c = coord.merge_clock(c, 10)
  let #(_, next) = coord.tick(c)
  next |> should.equal(11)
}

pub fn usage_accumulates_and_costs_test() {
  let c = coord.new(policy())
  let c =
    coord.record_usage(
      c,
      coord.Usage("W01", "sonnet", 100, 10, 1000, 0, 3, 5000),
    )
  let c =
    coord.record_usage(c, coord.Usage("W01", "sonnet", 50, 5, 500, 0, 2, 1000))
  let c =
    coord.record_usage(c, coord.Usage("V1", "haiku", 10, 1, 100, 0, 1, 500))
  let g = coord.global_usage(c)
  g.input_tokens |> should.equal(160)
  g.output_tokens |> should.equal(16)
  g.tool_uses |> should.equal(6)
  dict.size(c.usage) |> should.equal(2)
  {
    coord.weighted_cost(
      coord.Usage("x", "sonnet", 100, 0, 0, 0, 0, 0),
      coord.default_weights,
    )
    >. coord.weighted_cost(
      coord.Usage("x", "haiku", 100, 0, 0, 0, 0, 0),
      coord.default_weights,
    )
  }
  |> should.be_true
  list.length(coord.usage_rows(c)) |> should.equal(2)
}

pub fn guarded_post_records_violation_and_andon_test() {
  let b = case board.open("coord-test", "uos_tui_coord_test_1", None, None) {
    Ok(b) -> b
    Error(_) -> panic_free()
  }
  let c = coord.new(policy())
  let #(b, c, r) = coord.post(b, c, d(a("W01"), "broadcast", board.Plan))
  r |> should.equal(Error(coord.KindNotAllowed(board.Plan, coord.L2)))
  list.length(c.violations) |> should.equal(1)
  board.timeline(b)
  |> board.by_kind(board.Andon)
  |> list.length
  |> fn(n) { n >= 1 }
  |> should.be_true
  let #(_, _, ok) = coord.post(b, c, d(a("W01"), "L0-fable", board.Report))
  case ok {
    Ok(m) -> m.kind == board.Report
    Error(_) -> False
  }
  |> should.be_true
}

fn panic_free() -> board.Board {
  case board.open("coord-fallback", "uos_tui_coord_test_fallback", None, None) {
    Ok(b) -> b
    Error(_) -> panic_free()
  }
}

pub fn diff_sets_test() {
  let mk = fn(i: Int, prev: String) {
    board.seal(
      d(a("L0-fable"), "broadcast", board.Progress),
      "s",
      i,
      i,
      "0123456789abcde"
        <> case i {
        1 -> "1"
        2 -> "2"
        _ -> "3"
      },
      prev,
    )
  }
  let m1 = mk(1, board.genesis_digest)
  let m2 = mk(2, m1.digest)
  let m3 = mk(3, m2.digest)
  let tampered = board.Message(..m3, to: "W01")
  let #(pull, push, rejected) =
    coord.diff_sets([m1, m2], [
      m2,
      m3,
      tampered |> fn(t) { board.Message(..t, id: "zzz") },
    ])
  list.map(pull, fn(m) { m.id }) |> should.equal([m3.id])
  list.map(push, fn(m) { m.id }) |> should.equal([m1.id])
  rejected |> should.equal(["zzz"])
}

pub fn reconcile_without_base_errors_test() {
  let b = case board.open("coord-test", "uos_tui_coord_test_2", None, None) {
    Ok(b) -> b
    Error(_) -> panic_free()
  }
  coord.reconcile(b, coord.new(policy()))
  |> should.equal(Error("no zenoh base configured"))
}

// Property: under random acquire/expire sequences, at most one live holder per resource and epochs strictly increase.
pub fn property_single_writer_test() {
  list.each(prng.seeds(100), fn(seed) {
    let #(ops, _) = prng.ints(seed, 40, 0, 99)
    let #(c, max_epoch, _) =
      list.index_fold(ops, #(coord.new(policy()), 0, 0), fn(acc, op, i) {
        let #(c, max_epoch, _) = acc
        let holder = case op % 3 {
          0 -> "W01"
          1 -> "W02"
          _ -> "V1"
        }
        let now = i * 10
        case op % 4 {
          3 -> {
            let #(c, _) = coord.expire(c, now)
            #(c, max_epoch, now)
          }
          _ ->
            case coord.acquire(c, "res", holder, now, 25) {
              Ok(#(c, l)) -> {
                { l.epoch > max_epoch } |> should.be_true
                #(c, l.epoch, now)
              }
              Error(_) -> #(c, max_epoch, now)
            }
        }
      })
    { list.length(coord.live_leases(c, 400)) <= 1 } |> should.be_true
    { max_epoch >= 1 } |> should.be_true
  })
}

// Fuzz: authorize never crashes on random ids/kinds.
pub fn fuzz_authorize_test() {
  list.each(prng.seeds(200), fn(seed) {
    let #(f, seed) = prng.text(seed, 6)
    let #(t, seed) = prng.text(seed, 6)
    let #(k, _) = prng.int_between(seed, 0, 14)
    let kind =
      board.kinds
      |> list.drop(k)
      |> list.first
      |> fn(r) {
        case r {
          Ok(x) -> x
          Error(_) -> board.Progress
        }
      }
    let _ = coord.authorize(policy(), d(Agent(f, "L2", "x"), t, kind))
    Nil
  })
}

pub fn design_authority_is_fable_only_test() {
  let p =
    coord.default_policy(
      [
        Agent("L0-fable", "L0", "fable"),
        Agent("L0-cheap", "L0", "haiku"),
        Agent("uos-manager", "L1", "fprime-active"),
      ],
      4,
    )
  coord.authorize(
    p,
    d(Agent("L0-fable", "L0", "fable"), "broadcast", board.Plan),
  )
  |> should.equal(Ok(Nil))
  coord.authorize(
    p,
    d(Agent("L0-cheap", "L0", "haiku"), "broadcast", board.Plan),
  )
  |> should.equal(
    Error(coord.DesignAuthorityRequired("L0-cheap", "haiku", board.Plan)),
  )
  coord.authorize(
    p,
    d(Agent("uos-manager", "L1", "fprime-active"), "broadcast", board.Integrate),
  )
  |> should.equal(
    Error(coord.DesignAuthorityRequired(
      "uos-manager",
      "fprime-active",
      board.Integrate,
    )),
  )
  // runtime intelligence (cheapest) still runs the line
  coord.authorize(
    p,
    d(Agent("uos-manager", "L1", "fprime-active"), "broadcast", board.Andon),
  )
  |> should.equal(Ok(Nil))
  coord.authorize(
    p,
    d(Agent("L0-cheap", "L0", "haiku"), "broadcast", board.Progress),
  )
  |> should.equal(Ok(Nil))
}

pub fn retired_agents_are_never_stale_and_posts_beat_test() {
  let c =
    coord.new(policy())
    |> coord.retire("W01")
    |> coord.retire("W02")
    |> coord.retire("V1")
  coord.stale(c, 10_000, 1) |> should.equal(["L0-fable", "uos-coord"])
  let b = case board.open("coord-test", "uos_tui_coord_test_3", None, None) {
    Ok(b) -> b
    Error(_) -> panic_free()
  }
  let #(_, c, _) = coord.post(b, c, d(a("L0-fable"), "broadcast", board.Plan))
  {
    list.contains(
      coord.stale(c, board.system_time_us() + 1, 60_000_000),
      "L0-fable",
    )
  }
  |> should.be_false
}

pub fn reconcile_refuses_forged_authority_test() {
  // Pure part: a remote message claiming L0 from an L2-rostered id fails policy.
  let p = policy()
  let forged =
    board.seal(
      board.Draft(
        Agent("W01", "L0", "fable"),
        "broadcast",
        board.Dispatch,
        [],
        Semantics([], [], [], [], 0),
        Causality(None, []),
        None,
        None,
      ),
      "s",
      1,
      1,
      "0123456789abcdef",
      board.genesis_digest,
    )
  // W01 is rostered as L2/sonnet; the forged header claims L0/fable but the roster decides.
  coord.authorize_message(p, forged)
  |> should.equal(Error(coord.KindNotAllowed(board.Dispatch, coord.L2)))
  let ghost = board.Message(..forged, from: Agent("L0-forged", "L0", "fable"))
  coord.authorize_message(p, ghost)
  |> should.equal(Error(coord.UnknownAgent("L0-forged")))
}

pub fn claim_requires_matching_live_lease_test() {
  let b = case
    board.open("claim-test", "uos_tui_coord_test_claim", None, None)
  {
    Ok(b) -> b
    Error(_) -> panic_free()
  }
  let c = coord.new(policy())
  let claim = fn(epoch) {
    board.Draft(
      a("W01"),
      "L0-fable",
      board.Claim,
      [#("resource", "task:t1"), #("epoch", epoch)],
      Semantics([], [], [], [], 2),
      Causality(None, []),
      None,
      None,
    )
  }
  let #(b, c, r) = coord.post(b, c, claim("1"))
  r |> should.equal(Error(coord.NoSuchLease("task:t1")))
  let #(c, lease) = case coord.claim(c, "t1", "W01", 0, 1000) {
    Ok(v) -> v
    Error(_) -> #(c, coord.Lease("", "", 0, 0, 0))
  }
  let #(b, c, r) = coord.post(b, c, claim("9"))
  r |> should.equal(Error(coord.WrongEpoch("task:t1", lease.epoch, 9)))
  let #(_, _, r) = coord.post(b, c, claim(string_of(lease.epoch)))
  case r {
    Ok(m) -> m.kind == board.Claim
    Error(_) -> False
  }
  |> should.be_true
}

pub fn intent_strictly_upward_test() {
  let p = policy()
  // L2 -> L1: upward, ok.
  coord.authorize(p, d(a("W01"), "uos-coord", board.Intent))
  |> should.equal(Ok(Nil))
  // L1 -> L0: upward, ok.
  coord.authorize(p, d(a("uos-coord"), "L0-fable", board.Intent))
  |> should.equal(Ok(Nil))
  // L0 -> L1: downward (L0 already outranks L1), refused.
  coord.authorize(p, d(a("L0-fable"), "uos-coord", board.Intent))
  |> should.equal(Error(coord.IntentMustGoUpward("L0-fable", "uos-coord")))
  // L1 -> L1 (even the same agent to itself): same rank, not strictly upward, refused.
  coord.authorize(p, d(a("uos-coord"), "uos-coord", board.Intent))
  |> should.equal(Error(coord.IntentMustGoUpward("uos-coord", "uos-coord")))
  // L3 -> L2: upward, ok.
  coord.authorize(p, d(a("V1"), "W01", board.Intent))
  |> should.equal(Ok(Nil))
}

pub fn duplicate_payload_key_refused_test() {
  let p = policy()
  let draft =
    Draft(
      a("W01"),
      "L0-fable",
      board.Report,
      [#("k", "v1"), #("k", "v2")],
      Semantics([], [], [], [], 2),
      Causality(None, []),
      None,
      None,
    )
  coord.authorize(p, draft)
  |> should.equal(Error(coord.DuplicatePayloadKey("k")))
  // Distinct keys are unaffected.
  coord.authorize(p, Draft(..draft, payload: [#("k1", "v1"), #("k2", "v2")]))
  |> should.equal(Ok(Nil))
}

pub fn renew_refuses_expired_lease_test() {
  let c = coord.new(policy())
  let #(c, l1) = case coord.acquire(c, "r", "W01", 0, 10) {
    Ok(v) -> v
    Error(_) -> #(c, coord.Lease("", "", 0, 0, 0))
  }
  // expires_us = 0 + max(10, 1) = 10; at now_us = 10 the lease has already expired.
  coord.renew(c, "r", "W01", l1.epoch, 10, 50)
  |> should.equal(Error(coord.LeaseExpired("r", 10)))
  // Strictly before expiry, renewal still succeeds.
  case coord.renew(c, "r", "W01", l1.epoch, 9, 50) {
    Ok(_) -> True
    Error(_) -> False
  }
  |> should.be_true
}

pub fn count_conflicts_detects_tampered_existing_id_test() {
  let mk = fn(i: Int, prev: String) {
    board.seal(
      d(a("L0-fable"), "broadcast", board.Progress),
      "s",
      i,
      i,
      "0123456789abcde"
        <> case i {
        1 -> "1"
        2 -> "2"
        _ -> "3"
      },
      prev,
    )
  }
  let m1 = mk(1, board.genesis_digest)
  let m2 = mk(2, m1.digest)
  let m3 = mk(3, m2.digest)
  let local = [m1, m2]
  // A forged remote copy of m2's id carrying a different digest: a conflict, quarantined by
  // refusal — never absorbed, the local copy stays authoritative.
  let forged = board.Message(..m2, digest: m2.digest <> "-forged")
  coord.count_conflicts(local, [m1, forged]) |> should.equal(1)
  // A byte-identical remote copy of an existing id is not a conflict.
  coord.count_conflicts(local, [m1, m2]) |> should.equal(0)
  // A remote message whose id is absent locally is simply new, not a conflict.
  coord.count_conflicts(local, [m3]) |> should.equal(0)
}

pub fn seed_epochs_recovers_after_restart_test() {
  let path =
    "/tmp/claude-1000/-home-an-NAS-setup/656f0d2c-6019-4d9e-b0ce-b9e39b240047/scratchpad/coord_test_seed_epochs_"
    <> string_of(board.system_time_us())
    <> ".jsonl"
  let ba = case
    board.open("seed-epochs-a", "uos_tui_coord_test_seed_a", Some(path), None)
  {
    Ok(b) -> b
    Error(_) -> panic_free()
  }
  let ca = coord.new(policy())
  let lease = case coord.acquire(ca, "task:x", "W01", 0, 10) {
    Ok(#(_, l)) -> l
    Error(_) -> coord.Lease("", "", 0, 0, 0)
  }
  lease.epoch |> should.equal(1)
  let grant =
    Draft(
      coord.system_agent,
      "W01",
      board.LeaseGrant,
      [#("resource", "task:x"), #("epoch", string_of(lease.epoch))],
      Semantics([], [], [], [], 1),
      Causality(None, []),
      None,
      None,
    )
  let #(_, _) = board.post(ba, grant)
  // A fresh coordinator B on a fresh board that only replays the same ledger — it never saw
  // the acquire directly and must not be able to hand out epoch 1 again.
  let bb = case
    board.open("seed-epochs-b", "uos_tui_coord_test_seed_b", Some(path), None)
  {
    Ok(b) -> b
    Error(_) -> panic_free()
  }
  let cb = coord.new(policy()) |> coord.seed_epochs(board.timeline(bb))
  case coord.acquire(cb, "task:x", "W02", 100, 10) {
    Ok(#(_, l)) -> l.epoch
    Error(_) -> -1
  }
  |> should.equal(2)
}

pub fn start_actor_pid_matches_subject_owner_test() {
  let b = case
    board.open("coord-test", "uos_tui_coord_test_actor_pid", None, None)
  {
    Ok(b) -> b
    Error(_) -> panic_free()
  }
  let started =
    coord.start_actor(b, coord.new(policy()), 1_000_000)
    |> should.be_ok
  { started.pid == process.self() } |> should.be_false
  case process.subject_owner(started.data) {
    Ok(owner) -> owner == started.pid
    Error(_) -> False
  }
  |> should.be_true
  process.send(started.data, coord.Stop)
}

pub fn start_actor_tick_advances_and_stop_kills_process_test() {
  let b = case
    board.open("coord-test", "uos_tui_coord_test_actor_tick", None, None)
  {
    Ok(b) -> b
    Error(_) -> panic_free()
  }
  let c0 = coord.new(policy())
  let c0 = case coord.acquire(c0, "r", "W01", board.system_time_us(), 1) {
    Ok(#(c, _)) -> c
    Error(_) -> c0
  }
  // A large tick_ms keeps the actor's own background tick from firing during the test; the
  // Tick sent below is driven manually to prove the actor still handles it.
  let started = coord.start_actor(b, c0, 1_000_000) |> should.be_ok
  process.sleep(5)
  process.send(started.data, coord.Tick)
  process.sleep(30)
  let reply = process.new_subject()
  process.send(started.data, coord.Snapshot(reply))
  let snap_c = case process.receive(reply, 1000) {
    Ok(#(_, c)) -> c
    Error(_) -> c0
  }
  list.length(coord.live_leases(snap_c, board.system_time_us()))
  |> should.equal(0)
  process.send(started.data, coord.Stop)
  process.sleep(30)
  process.is_alive(started.pid) |> should.be_false
}

fn string_of(i: Int) -> String {
  gleam_int_to_string(i)
}

@external(erlang, "erlang", "integer_to_binary")
fn gleam_int_to_string(i: Int) -> String
