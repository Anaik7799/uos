import gleam/dict
import gleam/list
import gleam/string
import gleeunit/should
import prng
import uos_swarm/agent_runtime as rt
import uos_swarm/board.{Agent}
import uos_swarm/coord

fn policy() -> coord.Policy {
  coord.default_policy(
    [
      Agent("L0-fable", "L0", "fable"),
      Agent("uos-coord", "L1", "system"),
      Agent("W01", "L2", "sonnet"),
      Agent("W02", "L2", "sonnet"),
      Agent("V1", "L3", "haiku"),
    ],
    4,
  )
}

/// A fixed clock so grant expiry math is deterministic across tests.
const now = 1_700_000_000_000_000

/// Issue a live, unscoped MemoryCap grant to every agent in `agents`, folded into one list.
fn grant_memory_to(agents: List(String)) -> rt.Grants {
  list.fold(agents, [], fn(acc, agent) {
    case
      rt.grant(
        policy(),
        acc,
        "uos-coord",
        agent,
        rt.MemoryCap,
        now,
        60_000_000,
        "*",
      )
    {
      Ok(next) -> next
      Error(_) -> acc
    }
  })
}

pub fn memory_owner_write_and_supervisor_read_test() {
  let m = case rt.open_memory("W01") {
    Ok(m) -> m
    Error(_) -> fallback_memory()
  }
  let grants = grant_memory_to(["W01", "W02", "L0-fable"])

  // Default deny: no grant at all is refused, even for the owner.
  rt.remember(m, [], now, "W01", "working/x", "1")
  |> should.equal(
    Error(rt.NotGranted("W01", rt.capability_label(rt.MemoryCap))),
  )

  // A grant does not bypass ownership: W02 holds a valid grant but still can't write W01's memory.
  rt.remember(m, grants, now, "W02", "working/x", "1")
  |> should.equal(Error(rt.NotOwner("W02", "W01")))

  let m = case rt.remember(m, grants, now, "W01", "working/x", "1") {
    Ok(m) -> m
    Error(_) -> fallback_memory()
  }
  rt.recall(m, policy(), grants, now, "W01", "working/x")
  |> should.equal(Ok("1"))
  rt.recall(m, policy(), grants, now, "L0-fable", "working/x")
  |> should.equal(Ok("1"))
  rt.recall(m, policy(), grants, now, "W02", "working/x")
  |> should.equal(Error(rt.NotOwner("W02", "W01")))
  rt.recall(m, policy(), grants, now, "W01", "working/none")
  |> should.equal(Error(rt.NoSuchKey("working/none")))
  let _ = rt.remember_episode(m, grants, now, "W01", "msg-1", "posted report")
  rt.slots(m, policy(), "W01", grants, now, "episodic/")
  |> list.length
  |> should.equal(1)
}

pub fn lifecycle_machine_total_test() {
  rt.transition(rt.Idle, rt.Claim) |> should.equal(Ok(rt.Claimed))
  rt.transition(rt.Claimed, rt.Start) |> should.equal(Ok(rt.Working))
  rt.transition(rt.Working, rt.Submit) |> should.equal(Ok(rt.Verifying))
  rt.transition(rt.Verifying, rt.Pass) |> should.equal(Ok(rt.Done))
  rt.transition(rt.Verifying, rt.Fail) |> should.equal(Ok(rt.Failed))
  rt.transition(rt.Failed, rt.Retry) |> should.equal(Ok(rt.Working))
  rt.transition(rt.Idle, rt.Pass)
  |> fn(r) {
    case r {
      Error(e) -> string.contains(e, "no transition")
      Ok(_) -> False
    }
  }
  |> should.be_true
  rt.parent(rt.Working) |> should.equal("Active")
  rt.parent(rt.Done) |> should.equal("Root")
}

pub fn rete_rules_derive_acts_test() {
  let facts = [
    rt.Fact("audit_failed", ["5"]),
    rt.Fact("stale", ["W02"]),
    rt.Fact("verdict", ["W01", "FAIL"]),
    rt.Fact("intent", ["W01", "restart", "db-prod"]),
    rt.Fact("wip", ["6"]),
    rt.Fact("wip_limit", ["4"]),
  ]
  let derived = rt.run(facts, rt.default_rules(), 8)
  let acts =
    derived
    |> list.filter(fn(f) { f.name == "act" })
    |> list.map(fn(f) { f.args })
  list.contains(acts, ["jidoka", "audit failures 5"]) |> should.be_true
  list.contains(acts, ["andon", "stale W02"]) |> should.be_true
  list.contains(acts, ["rework", "W01"]) |> should.be_true
  list.contains(acts, ["policy_review", "W01:restart:db-prod"])
  |> should.be_true
  list.contains(acts, ["block_pull", "wip 6 > 4"]) |> should.be_true
  // fixpoint: running again derives nothing new
  rt.run(list.append(facts, derived), rt.default_rules(), 8) |> should.equal([])
}

pub fn rete_bounded_and_variables_unify_test() {
  let r =
    rt.Rule(
      "R-SELF",
      [rt.Pattern("p", ["?x"])],
      fn(env) { rt.Fact("p", [result_or(dict.get(env, "x")) <> "!"]) },
      "grows forever",
    )
  let out = rt.run([rt.Fact("p", ["a"])], [r], 3)
  list.length(out) |> should.equal(3)
  let r2 =
    rt.Rule(
      "R-EQ",
      [rt.Pattern("edge", ["?a", "?b"]), rt.Pattern("edge", ["?b", "?a"])],
      fn(env) { rt.Fact("mutual", [result_or(dict.get(env, "a"))]) },
      "x",
    )
  rt.run(
    [
      rt.Fact("edge", ["1", "2"]),
      rt.Fact("edge", ["2", "1"]),
      rt.Fact("edge", ["2", "3"]),
    ],
    [r2],
    4,
  )
  |> list.map(fn(f) { f.args })
  |> list.sort(fn(a, b) { string.compare(string.concat(a), string.concat(b)) })
  |> should.equal([["1"], ["2"]])
}

fn result_or(r: Result(String, Nil)) -> String {
  case r {
    Ok(v) -> v
    Error(_) -> "?"
  }
}

pub fn bayes_updates_and_cheapest_adequate_test() {
  let b = rt.prior("W01", "haiku")
  rt.mean(b) |> should.equal(0.5)
  let b = list.fold(prng.range(1, 8), b, fn(b, _) { rt.update(b, True) })
  { rt.mean(b) >. 0.85 } |> should.be_true
  let good_haiku = [b, rt.prior("W01", "sonnet")]
  rt.choose_model(good_haiku, rt.default_tiers, 0.6, 7).model
  |> should.equal("haiku")
  let bad_haiku = [
    list.fold(prng.range(1, 8), rt.prior("W01", "haiku"), fn(b, _) {
      rt.update(b, False)
    }),
    list.fold(prng.range(1, 8), rt.prior("W01", "sonnet"), fn(b, _) {
      rt.update(b, True)
    }),
  ]
  rt.choose_model(bad_haiku, rt.default_tiers, 0.6, 7).model
  |> should.equal("sonnet")
  // determinism
  rt.choose_model(bad_haiku, rt.default_tiers, 0.6, 7)
  |> should.equal(rt.choose_model(bad_haiku, rt.default_tiers, 0.6, 7))
}

pub fn capabilities_default_deny_and_l0_l1_grant_test() {
  let p = policy()
  rt.allowed([], "W01", rt.MaxInferenceCap, now, "*") |> should.be_false
  rt.grant(p, [], "W02", "W01", rt.MaxInferenceCap, now, 60_000_000, "*")
  |> should.equal(Error(coord.ControlKeyForbidden("W02")))
  rt.grant(p, [], "ghost", "W01", rt.LeanCap, now, 60_000_000, "*")
  |> should.equal(Error(coord.UnknownAgent("ghost")))
  let gs = case
    rt.grant(
      p,
      [],
      "uos-coord",
      "W01",
      rt.MaxInferenceCap,
      now,
      60_000_000,
      "*",
    )
  {
    Ok(gs) -> gs
    Error(_) -> []
  }
  rt.allowed(gs, "W01", rt.MaxInferenceCap, now, "anything") |> should.be_true
  rt.allowed(gs, "W02", rt.MaxInferenceCap, now, "anything") |> should.be_false
  case gs {
    [g, ..] -> {
      let d = rt.grant_draft(g)
      board.validate_semantics(d.semantics) |> should.equal(Ok(Nil))
      coord.authorize(p, d) |> should.equal(Ok(Nil))
    }
    [] -> should.fail()
  }
  // MAX access is an Intent upward, authorized by policy, never a call
  let req = rt.max_request_draft(Agent("W01", "L2", "sonnet"), "abc")
  req.kind |> should.equal(board.Intent)
  coord.authorize(p, req) |> should.equal(Ok(Nil))
}

/// `Grant` is `pub opaque type`: this module has no constructor for it and can only obtain one
/// through `rt.grant` (which enforces the L0/L1 grantor rule), reading it back only through the
/// accessor functions below — there is no way to forge a `Grant` from outside `agent_runtime`.
pub fn grant_is_opaque_and_accessors_reflect_state_test() {
  let p = policy()
  let gs = case
    rt.grant(p, [], "uos-coord", "W01", rt.LeanCap, now, 30, "working/")
  {
    Ok(gs) -> gs
    Error(_) -> []
  }
  case gs {
    [g, ..] -> {
      rt.grant_agent(g) |> should.equal("W01")
      rt.grant_capability(g) |> should.equal(rt.LeanCap)
      rt.grant_grantor(g) |> should.equal("uos-coord")
      rt.grant_expires_us(g) |> should.equal(now + 30)
    }
    [] -> should.fail()
  }
}

pub fn expired_grant_is_refused_test() {
  let p =
    coord.default_policy(
      [Agent("uos-coord", "L1", "system"), Agent("EXP1", "L2", "sonnet")],
      4,
    )
  let m = case rt.open_memory("EXP1") {
    Ok(m) -> m
    Error(_) -> fallback_memory()
  }
  let gs = case
    rt.grant(p, [], "uos-coord", "EXP1", rt.MemoryCap, now, 5, "*")
  {
    Ok(gs) -> gs
    Error(_) -> []
  }
  // still live one microsecond before expiry
  rt.remember(m, gs, now + 4, "EXP1", "working/a", "1") |> should.be_ok
  // expired the instant now_us reaches expires_us
  rt.remember(m, gs, now + 5, "EXP1", "working/b", "2")
  |> should.equal(
    Error(rt.NotGranted("EXP1", rt.capability_label(rt.MemoryCap))),
  )
}

pub fn grant_scope_does_not_cover_unrelated_prefix_test() {
  let p = policy()
  let gs = case
    rt.grant(
      p,
      [],
      "uos-coord",
      "W01",
      rt.MemoryCap,
      now,
      60_000_000,
      "working/",
    )
  {
    Ok(gs) -> gs
    Error(_) -> []
  }
  rt.allowed(gs, "W01", rt.MemoryCap, now, "working/x") |> should.be_true
  rt.allowed(gs, "W01", rt.MemoryCap, now, "belief/x") |> should.be_false
}

pub fn slots_refused_for_non_owner_l2_allowed_for_l1_test() {
  let p =
    coord.default_policy(
      [
        Agent("L0-fable", "L0", "fable"),
        Agent("uos-coord", "L1", "system"),
        Agent("SO1", "L2", "sonnet"),
        Agent("SO2", "L2", "sonnet"),
      ],
      4,
    )
  let m = case rt.open_memory("SO1") {
    Ok(m) -> m
    Error(_) -> fallback_memory()
  }
  let gs =
    list.fold(["SO1", "SO2", "uos-coord"], [], fn(acc, agent) {
      case
        rt.grant(p, acc, "uos-coord", agent, rt.MemoryCap, now, 60_000_000, "*")
      {
        Ok(next) -> next
        Error(_) -> acc
      }
    })
  let m = case rt.remember(m, gs, now, "SO1", "working/a", "1") {
    Ok(m) -> m
    Error(_) -> fallback_memory()
  }
  // SO2 is a non-owner L2 requester: refused even though it holds a valid grant.
  rt.slots(m, p, "SO2", gs, now, "working/") |> should.equal([])
  // uos-coord is L1 and holds a valid grant: the owner/L0/L1 exception applies.
  rt.slots(m, p, "uos-coord", gs, now, "working/")
  |> list.length
  |> should.equal(1)
}

pub fn remember_without_grant_refused_test() {
  let m = case rt.open_memory("no-grant-owner") {
    Ok(m) -> m
    Error(_) -> fallback_memory()
  }
  rt.remember(m, [], now, "no-grant-owner", "working/x", "1")
  |> should.equal(
    Error(rt.NotGranted("no-grant-owner", rt.capability_label(rt.MemoryCap))),
  )
}

pub fn revoke_removes_access_test() {
  let p = policy()
  let gs = case
    rt.grant(p, [], "uos-coord", "W01", rt.MemoryCap, now, 60_000_000, "*")
  {
    Ok(gs) -> gs
    Error(_) -> []
  }
  rt.allowed(gs, "W01", rt.MemoryCap, now, "working/x") |> should.be_true
  let revoked = rt.revoke(gs, "W01", rt.MemoryCap)
  rt.allowed(revoked, "W01", rt.MemoryCap, now, "working/x") |> should.be_false
}

pub fn controls_report_test() {
  let cs = rt.controls("/home/an/NAS-setup/uos", True)
  { list.length(cs) >= 20 } |> should.be_true
  list.each(["operational", "security", "observability", "formal"], fn(d) {
    list.any(cs, fn(c) { c.domain == d }) |> should.be_true
  })
  let down = rt.controls("/home/an/NAS-setup/uos", False)
  rt.controls_ok(down) |> should.be_false
  string.contains(rt.controls_markdown(cs), "SEC-2") |> should.be_true
  // The memory-security probes (SEC-12..SEC-16) are proved by exercising the code inside
  // `controls`, not declared: they must all come back ENFORCED.
  list.each(["SEC-12", "SEC-13", "SEC-14", "SEC-15", "SEC-16"], fn(id) {
    case list.find(cs, fn(c) { c.id == id }) {
      Ok(c) -> c.status |> should.equal("ENFORCED")
      Error(_) -> should.fail()
    }
  })
}

// Fuzz: rete unify/run never crash on random facts; transition total on random signals.
pub fn fuzz_rete_and_fsm_test() {
  list.each(prng.seeds(100), fn(seed) {
    let #(t, seed) = prng.text(seed, 6)
    let #(k, _) = prng.int_between(seed, 0, 6)
    let facts = [
      rt.Fact(t, [t]),
      rt.Fact("audit_failed", [t]),
      rt.Fact("wip", [t]),
      rt.Fact("wip_limit", ["4"]),
    ]
    let _ = rt.run(facts, rt.default_rules(), 4)
    let sig = case k {
      0 -> rt.Claim
      1 -> rt.Start
      2 -> rt.Submit
      3 -> rt.Pass
      4 -> rt.Fail
      5 -> rt.Retry
      _ -> rt.Release
    }
    list.each(
      [rt.Idle, rt.Claimed, rt.Working, rt.Verifying, rt.Done, rt.Failed],
      fn(s) {
        let _ = rt.transition(s, sig)
        Nil
      },
    )
  })
}

fn fallback_memory() -> rt.Memory {
  case rt.open_memory("fallback") {
    Ok(m) -> m
    Error(_) -> fallback_memory()
  }
}

pub fn beta_sampler_is_a_real_variate_test() {
  // Many draws from Beta(20,2) concentrate near 0.9; from Beta(2,20) near 0.1; deterministic per seed.
  let hi = rt.Belief("x", "m", 20.0, 2.0)
  let lo = rt.Belief("x", "m", 2.0, 20.0)
  let draws_hi = list.map(prng.range(1, 200), fn(i) { rt.sample(hi, i * 7919) })
  let draws_lo = list.map(prng.range(1, 200), fn(i) { rt.sample(lo, i * 7919) })
  let mean = fn(xs: List(Float)) {
    list.fold(xs, 0.0, fn(a, x) { a +. x }) /. 200.0
  }
  { mean(draws_hi) >. 0.8 && mean(draws_hi) <. 0.98 } |> should.be_true
  { mean(draws_lo) <. 0.2 && mean(draws_lo) >. 0.02 } |> should.be_true
  rt.sample(hi, 42) |> should.equal(rt.sample(hi, 42))
  list.all(draws_hi, fn(x) { x >=. 0.0 && x <=. 1.0 }) |> should.be_true
}

// ---------------------------------------------------------------------------
// Hindu thinking-and-memory mirror: Vritti, Antahkarana, Guna, pramāṇa.
// ---------------------------------------------------------------------------

pub fn classify_slot_belief_verified_is_pramana_test() {
  rt.classify_slot("belief/x", "verified pass") |> should.equal(rt.Pramana)
  rt.classify_slot("belief/x", "confirmed") |> should.equal(rt.Pramana)
  // A belief slot with no matching keyword defaults to Pramana (an
  // asserted, not yet contradicted, cognition).
  rt.classify_slot("belief/x", "seen twice") |> should.equal(rt.Pramana)
}

pub fn classify_slot_belief_contradicted_is_viparyaya_test() {
  rt.classify_slot("belief/x", "contradicted by V2")
  |> should.equal(rt.Viparyaya)
  rt.classify_slot("belief/x", "refuted") |> should.equal(rt.Viparyaya)
  rt.classify_slot("belief/x", "FAIL") |> should.equal(rt.Viparyaya)
}

pub fn classify_slot_hypothesis_and_dream_are_vikalpa_test() {
  rt.classify_slot("hypothesis/h1", "aspect 15 failed")
  |> should.equal(rt.Vikalpa)
  rt.classify_slot("dream/d1", "consolidated 12") |> should.equal(rt.Vikalpa)
}

pub fn classify_slot_episodic_is_smriti_test() {
  rt.classify_slot("episodic/msg-1", "posted Progress")
  |> should.equal(rt.Smriti)
}

pub fn classify_slot_other_namespace_defaults_to_smriti_test() {
  rt.classify_slot("goal/x", "ship it") |> should.equal(rt.Smriti)
}

pub fn classify_slot_empty_or_idle_value_is_nidra_test() {
  rt.classify_slot("working/x", "") |> should.equal(rt.Nidra)
  rt.classify_slot("goal/x", "idle") |> should.equal(rt.Nidra)
  rt.classify_slot("belief/x", "none") |> should.equal(rt.Nidra)
  // Idle wins over namespace even for hypothesis/dream slots.
  rt.classify_slot("hypothesis/h1", "") |> should.equal(rt.Nidra)
}

pub fn guna_of_state_mapping_test() {
  rt.guna_of_state(rt.Done) |> should.equal(rt.Sattva)
  rt.guna_of_state(rt.Verifying) |> should.equal(rt.Sattva)
  rt.guna_of_state(rt.Working) |> should.equal(rt.Rajas)
  rt.guna_of_state(rt.Claimed) |> should.equal(rt.Rajas)
  rt.guna_of_state(rt.Idle) |> should.equal(rt.Tamas)
  rt.guna_of_state(rt.Failed) |> should.equal(rt.Tamas)
}

pub fn faculty_of_mapping_test() {
  rt.faculty_of("observe") |> should.equal(rt.Manas)
  rt.faculty_of("orient") |> should.equal(rt.Manas)
  rt.faculty_of("decide") |> should.equal(rt.Buddhi)
  rt.faculty_of("act") |> should.equal(rt.Buddhi)
  rt.faculty_of("identity") |> should.equal(rt.Ahamkara)
  rt.faculty_of("self-model") |> should.equal(rt.Ahamkara)
  rt.faculty_of("memory") |> should.equal(rt.Citta)
  rt.faculty_of("something-unrecognised") |> should.equal(rt.Manas)
}

pub fn pramana_of_evidence_mapping_test() {
  rt.pramana_of_evidence("observed") |> should.equal("pratyakṣa (प्रत्यक्ष)")
  rt.pramana_of_evidence("inferred") |> should.equal("anumāna (अनुमान)")
  rt.pramana_of_evidence("reported") |> should.equal("śabda (शब्द)")
  rt.pramana_of_evidence("compared") |> should.equal("upamāna (उपमान)")
  rt.pramana_of_evidence("unknown-kind") |> should.equal("śabda (शब्द)")
}

pub fn vritti_labels_carry_devanagari_test() {
  rt.vritti_label(rt.Pramana) |> string.contains("प्रमाण") |> should.be_true
  rt.vritti_label(rt.Viparyaya)
  |> string.contains("विपर्यय")
  |> should.be_true
  rt.vritti_label(rt.Vikalpa) |> string.contains("विकल्प") |> should.be_true
  rt.vritti_label(rt.Nidra) |> string.contains("निद्रा") |> should.be_true
  rt.vritti_label(rt.Smriti) |> string.contains("स्मृति") |> should.be_true
}

pub fn antahkarana_labels_carry_devanagari_test() {
  rt.antahkarana_label(rt.Manas) |> string.contains("मनस्") |> should.be_true
  rt.antahkarana_label(rt.Buddhi) |> string.contains("बुद्धि") |> should.be_true
  rt.antahkarana_label(rt.Ahamkara)
  |> string.contains("अहंकार")
  |> should.be_true
  rt.antahkarana_label(rt.Citta) |> string.contains("चित्त") |> should.be_true
}

pub fn guna_labels_carry_devanagari_test() {
  rt.guna_label(rt.Sattva) |> string.contains("सत्त्व") |> should.be_true
  rt.guna_label(rt.Rajas) |> string.contains("रजस्") |> should.be_true
  rt.guna_label(rt.Tamas) |> string.contains("तमस्") |> should.be_true
}
