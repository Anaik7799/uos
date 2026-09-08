//// Live verification of the honest capability boundary
//// (SC-HOLON-001, SC-TOOLCHAIN-INPROJECT-001).
////
//// These tests deliberately assert BEHAVIOUR, not availability: a machine
//// without the Lean toolchain must still pass, by reporting Unavailable rather
//// than by pretending. What is asserted is the invariant that makes the
//// substrate trustworthy -- every outcome is one of Engaged / Unavailable /
//// Masked, a masked capability never touches its backend, and an Engaged
//// outcome always carries observed evidence.

import cepaf_gleam/ecology/capability_port.{
  type Outcome, Engaged, Masked, Unavailable,
}
import cepaf_gleam/ecology/super_agent
import gleeunit/should
import gleam/list
import gleam/string

fn full_mask() -> super_agent.CapabilityMask {
  super_agent.mask_for_mode(super_agent.SovereignEvolution)
}

fn reflex_mask() -> super_agent.CapabilityMask {
  super_agent.mask_for_mode(super_agent.Reflex)
}

/// Every capability resolves to a declared backend. No capability is orphaned.
pub fn every_capability_has_a_backend_test() {
  list.each(capability_port.all_capabilities, fn(c) {
    capability_port.backend_for(c)
    |> should.be_ok
  })
}

/// An unknown capability is rejected, never silently accepted.
pub fn unknown_capability_is_rejected_test() {
  capability_port.backend_for("telepathy")
  |> should.be_error
}

/// A capability switched off in the mask reports Masked and MUST NOT reach its
/// backend. In Reflex mode only ets and fprime are active, so a Lean subprocess
/// must never be spawned -- this is what keeps reflex latency bounded.
pub fn masked_capability_does_not_touch_backend_test() {
  capability_port.invoke(reflex_mask(), "formal_twin", "x")
  |> should.equal(Masked("formal_twin"))

  capability_port.invoke(reflex_mask(), "rete_ul", "x")
  |> should.equal(Masked("rete_ul"))
}

/// Reflex mode keeps its own capabilities live.
pub fn reflex_keeps_its_own_capabilities_test() {
  let outcome = capability_port.invoke(reflex_mask(), "ets", "x")
  case outcome {
    Engaged("ets", _, _, _) -> Nil
    other -> should.equal(describe(other), "expected Engaged")
  }
}

/// The Bayesian capability performs real conjugate arithmetic on real input:
/// 3 successes and 1 failure give Beta(4,2), posterior mean 4/6 = 0.666...
/// A counter-bumping stub cannot produce this number.
pub fn bayesian_computes_real_posterior_test() {
  let outcome = capability_port.invoke(full_mask(), "bayesian", "ok ok fail ok")
  case outcome {
    Engaged(_, _, evidence, _) ->
      string.starts_with(evidence, "posterior mean 0.66")
      |> should.be_true
    other -> should.equal(describe(other), "expected Engaged")
  }
}

/// Distinct inputs must produce distinct results. This is the specific property
/// a counter fails: incrementing `rules_fired` is identical regardless of input.
pub fn capability_is_input_sensitive_test() {
  let a = capability_port.invoke(full_mask(), "bayesian", "ok ok ok")
  let b = capability_port.invoke(full_mask(), "bayesian", "fail fail fail")
  should.be_false(a == b)
}

/// The ruliad capability really rewrites: branchial width tracks the input.
pub fn ruliad_width_tracks_input_test() {
  let outcome = capability_port.invoke(full_mask(), "ruliad", "a b c")
  case outcome {
    Engaged(_, _, evidence, _) ->
      evidence |> should.equal("branchial width 3")
    other -> should.equal(describe(other), "expected Engaged")
  }
}

/// Every outcome is total: exactly one of the three constructors, always.
pub fn outcomes_are_total_test() {
  list.each(capability_port.all_capabilities, fn(c) {
    case capability_port.invoke(full_mask(), c, "ok") {
      Engaged(cap, _, evidence, _) -> {
        // An Engaged outcome must carry non-empty observed evidence.
        should.equal(cap, c)
        should.be_true(string.length(evidence) > 0)
      }
      Unavailable(cap, reason) -> {
        // An Unavailable outcome must say why. "Unavailable" with no reason
        // would be as useless as a fabricated success.
        should.equal(cap, c)
        should.be_true(string.length(reason) > 0)
      }
      Masked(cap) -> should.equal(cap, c)
    }
  })
}

/// openrouter_free must NOT report Engaged merely because a credential exists.
/// Holding an API key is not the same as having asked a model anything.
pub fn credential_presence_is_not_an_answer_test() {
  case capability_port.invoke(full_mask(), "openrouter_free", "q") {
    Unavailable(_, reason) ->
      string.contains(reason, "dispatch not wired") |> should.be_true
    other -> should.equal(describe(other), "expected Unavailable")
  }
}

fn describe(o: Outcome) -> String {
  case o {
    Engaged(c, b, e, _) -> "Engaged(" <> c <> "," <> b <> "," <> e <> ")"
    Unavailable(c, r) -> "Unavailable(" <> c <> "," <> r <> ")"
    Masked(c) -> "Masked(" <> c <> ")"
  }
}
