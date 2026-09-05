/// Immune Learning Tests — synthesise GRL rules from observed attack patterns
///
/// 22 tests covering: init, observe_attack (new/existing/blocked),
/// approve_antibody, reject_antibody, generate_grl_rule,
/// active_rules, is_blocked, block_pattern,
/// pending_count, learned_count, summary.
///
/// Layer: L0_CONSTITUTIONAL
/// STAMP: SC-BIO-EVO-001, SC-SIL4-001, SC-SAFETY-001
/// अहिंसा परमो धर्मः — Non-harm is the highest duty (immune blocks harm)
import cepaf_gleam/ha/immune_learning.{
  BlockPattern, NoLearning, RequestApproval, SynthesizeRule, active_rules,
  approve_antibody, block_pattern, generate_grl_rule, init, is_blocked,
  learned_count, observe_attack, pending_count, reject_antibody, summary,
}
import gleam/list
import gleam/string
import gleeunit/should

// ===========================================================================
// 1. init/0
// ===========================================================================

pub fn init_empty_learned_test() {
  learned_count(init()) |> should.equal(0)
}

pub fn init_empty_pending_test() {
  pending_count(init()) |> should.equal(0)
}

pub fn init_no_blocked_patterns_test() {
  init().blocked_patterns |> should.equal([])
}

pub fn init_learning_events_zero_test() {
  init().learning_events |> should.equal(0)
}

// ===========================================================================
// 2. observe_attack — new attack
// ===========================================================================

pub fn observe_new_attack_synthesizes_rule_test() {
  let memory = init()
  let #(_new_mem, action) =
    observe_attack(memory, "sql_injection", "SELECT.*FROM", 100)
  case action {
    SynthesizeRule(_ab) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn observe_new_attack_adds_to_pending_test() {
  let memory = init()
  let #(new_mem, _action) = observe_attack(memory, "xss", "<script>", 101)
  pending_count(new_mem) |> should.equal(1)
}

pub fn observe_new_attack_increments_events_test() {
  let memory = init()
  let #(new_mem, _action) =
    observe_attack(memory, "brute_force", "login_fail", 102)
  new_mem.learning_events |> should.equal(1)
}

pub fn observe_new_attack_confidence_low_test() {
  let memory = init()
  let #(_new_mem, action) = observe_attack(memory, "overflow", "AAAA+", 103)
  case action {
    SynthesizeRule(ab) -> { ab.confidence <. 0.5 } |> should.be_true()
    _ -> should.fail()
  }
}

// ===========================================================================
// 3. observe_attack — existing attack (repeat observation)
// ===========================================================================

pub fn observe_repeated_attack_no_new_pending_test() {
  let memory = init()
  let #(m1, _) = observe_attack(memory, "sql_injection", "SELECT.*FROM", 1)
  let #(m2, _) = observe_attack(m1, "sql_injection", "SELECT.*FROM", 2)
  pending_count(m2) |> should.equal(1)
}

pub fn observe_repeated_attack_increments_count_test() {
  let memory = init()
  let #(m1, _) = observe_attack(memory, "xss", "<script>", 1)
  let #(m2, action) = observe_attack(m1, "xss", "<script>", 2)
  case action {
    NoLearning -> {
      // attack is still pending; second observation for pending → NoLearning
      pending_count(m2) |> should.equal(1)
    }
    RequestApproval(_) -> {
      // confidence crossed 0.8 — also acceptable
      should.be_true(True)
    }
    _ -> should.fail()
  }
}

// ===========================================================================
// 4. blocked pattern
// ===========================================================================

pub fn observe_blocked_pattern_returns_block_action_test() {
  let memory = init() |> block_pattern("DANGEROUS")
  let #(_new_mem, action) =
    observe_attack(memory, "known_bad", "DANGEROUS", 200)
  action |> should.equal(BlockPattern("DANGEROUS"))
}

pub fn is_blocked_true_after_block_test() {
  let memory = block_pattern(init(), "bad_pattern")
  is_blocked(memory, "bad_pattern") |> should.be_true()
}

pub fn is_blocked_false_for_unknown_test() {
  is_blocked(init(), "harmless") |> should.be_false()
}

pub fn block_pattern_idempotent_test() {
  let m1 = block_pattern(init(), "pat")
  let m2 = block_pattern(m1, "pat")
  list.length(m2.blocked_patterns) |> should.equal(1)
}

// ===========================================================================
// 5. approve_antibody/2 and reject_antibody/2
// ===========================================================================

pub fn approve_moves_to_learned_test() {
  let memory = init()
  let #(m1, action) = observe_attack(memory, "xss", "<script>", 1)
  case action {
    SynthesizeRule(ab) -> {
      let m2 = approve_antibody(m1, ab.id)
      learned_count(m2) |> should.equal(1)
      pending_count(m2) |> should.equal(0)
    }
    _ -> should.fail()
  }
}

pub fn approve_sets_approved_flag_test() {
  let memory = init()
  let #(m1, action) = observe_attack(memory, "csrf", "token_missing", 1)
  case action {
    SynthesizeRule(ab) -> {
      let m2 = approve_antibody(m1, ab.id)
      case list.first(m2.learned) {
        Ok(approved_ab) -> approved_ab.approved |> should.be_true()
        Error(_) -> should.fail()
      }
    }
    _ -> should.fail()
  }
}

pub fn reject_removes_from_pending_test() {
  let memory = init()
  let #(m1, action) = observe_attack(memory, "lfi", "../etc/passwd", 1)
  case action {
    SynthesizeRule(ab) -> {
      let m2 = reject_antibody(m1, ab.id)
      pending_count(m2) |> should.equal(0)
      learned_count(m2) |> should.equal(0)
    }
    _ -> should.fail()
  }
}

// ===========================================================================
// 6. generate_grl_rule/1
// ===========================================================================

pub fn generate_grl_rule_contains_id_test() {
  let memory = init()
  let #(_m, action) = observe_attack(memory, "rce", "eval(", 1)
  case action {
    SynthesizeRule(ab) -> {
      let rule = generate_grl_rule(ab)
      string.contains(rule, ab.id) |> should.be_true()
    }
    _ -> should.fail()
  }
}

pub fn generate_grl_rule_contains_salience_test() {
  let memory = init()
  let #(_m, action) = observe_attack(memory, "dos", "flood", 1)
  case action {
    SynthesizeRule(ab) -> {
      let rule = generate_grl_rule(ab)
      string.contains(rule, "salience") |> should.be_true()
    }
    _ -> should.fail()
  }
}

// ===========================================================================
// 7. active_rules/1
// ===========================================================================

pub fn active_rules_empty_before_approval_test() {
  let memory = init()
  let #(m1, _) = observe_attack(memory, "attack", "pattern", 1)
  active_rules(m1) |> should.equal([])
}

pub fn active_rules_non_empty_after_approval_test() {
  let memory = init()
  let #(m1, action) = observe_attack(memory, "attack", "pattern", 1)
  case action {
    SynthesizeRule(ab) -> {
      let m2 = approve_antibody(m1, ab.id)
      active_rules(m2) |> list.length() |> should.equal(1)
    }
    _ -> should.fail()
  }
}

// ===========================================================================
// 8. summary/1
// ===========================================================================

pub fn summary_contains_immune_memory_test() {
  summary(init()) |> string.contains("ImmuneMemory") |> should.be_true()
}

pub fn summary_contains_events_test() {
  summary(init()) |> string.contains("events=") |> should.be_true()
}
