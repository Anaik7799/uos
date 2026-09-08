import cepaf_gleam/ecology/super_agent.{
  Active, Awakening, Deliberative, Dormant, Reflex, SovereignEvolution,
  active_capability_count, awaken, create_super_agent, execute_autonomic_pulse,
  set_mode, to_json, toggle_capability,
}
import gleam/json
import gleam/result
import gleam/string
import gleeunit/should

pub fn create_super_agent_defaults_test() {
  let holon =
    create_super_agent(
      "hive-mind-decider",
      "Hive Mind Decider Super-Agent",
      "intelligence",
      5,
    )

  holon.id |> should.equal("hive-mind-decider")
  holon.lifecycle |> should.equal(Dormant)
  holon.mode |> should.equal(Reflex)
  active_capability_count(holon.mask) |> should.equal(2)
  holon.mask.fprime |> should.be_true
  holon.mask.ets |> should.be_true
  holon.mask.bayesian |> should.be_false
  holon.mask.ruliad |> should.be_false
}

pub fn awaken_lifecycle_transition_test() {
  let holon0 =
    create_super_agent(
      "prajna-homeostasis",
      "Prajna Homeostasis Engine",
      "control",
      2,
    )

  let assert Ok(holon1) = awaken(holon0)
  holon1.lifecycle |> should.equal(Awakening)

  let assert Ok(holon2) = awaken(holon1)
  holon2.lifecycle |> should.equal(Active)
}

pub fn operational_mode_transitions_test() {
  let holon =
    create_super_agent(
      "universal-super-agent",
      "Universal Holon",
      "structure",
      1,
    )

  // Reflex mode: 2 capabilities
  let h_reflex = set_mode(holon, Reflex)
  active_capability_count(h_reflex.mask) |> should.equal(2)

  // Deliberative mode: 5 capabilities
  let h_delib = set_mode(holon, Deliberative)
  active_capability_count(h_delib.mask) |> should.equal(5)
  h_delib.mask.bayesian |> should.be_true
  h_delib.mask.rete_ul |> should.be_true
  h_delib.mask.stm |> should.be_true

  // Autonomous mode: 7 capabilities
  let h_auto = set_mode(holon, super_agent.Autonomous)
  active_capability_count(h_auto.mask) |> should.equal(7)
  h_auto.mask.modular_max |> should.be_true
  h_auto.mask.openrouter_free |> should.be_true

  // Sovereign Evolution mode: All 11 capabilities active
  let h_sov = set_mode(holon, SovereignEvolution)
  active_capability_count(h_sov.mask) |> should.equal(11)
  h_sov.mask.ruliad |> should.be_true
  h_sov.mask.formal_twin |> should.be_true
  h_sov.mask.denotational |> should.be_true
  h_sov.mask.algebraic_atlas |> should.be_true
}

pub fn custom_selective_capability_toggle_test() {
  let holon =
    create_super_agent(
      "custom-agent",
      "Custom Tuned Agent",
      "data",
      3,
    )

  // Start with Reflex (2 capabilities: fprime, ets)
  active_capability_count(holon.mask) |> should.equal(2)

  // Selectively activate only Ruliad without entering full SovereignEvolution
  let assert Ok(h_ruliad) = toggle_capability(holon, "ruliad", True)
  active_capability_count(h_ruliad.mask) |> should.equal(3)
  h_ruliad.mask.ruliad |> should.be_true

  // Selectively activate Lean 4 Formal Twin
  let assert Ok(h_twin) = toggle_capability(h_ruliad, "formal_twin", True)
  active_capability_count(h_twin.mask) |> should.equal(4)
  h_twin.mask.formal_twin |> should.be_true

  // Unknown capability error check
  let res_err = toggle_capability(h_twin, "non_existent_capability", True)
  res_err |> should.be_error
}

pub fn autonomic_pulse_ooda_loop_test() {
  let holon0 =
    create_super_agent(
      "lyapunov-sentinel",
      "Lyapunov Sentinel",
      "runtime",
      2,
    )
    |> set_mode(Deliberative)

  let assert Ok(awakened) = awaken(holon0)
  let assert Ok(active_holon) = awaken(awakened)
  active_holon.lifecycle |> should.equal(Active)

  // Pulse 1: Target latency 10.0ms, observed 10.1ms -> Homeostatic error is small (1%), stable
  let #(holon1, report1) =
    execute_autonomic_pulse(active_holon, 10.1, 10.0)

  report1.is_stable |> should.be_true
  report1.action_taken |> should.equal("equilibrium_maintained")
  holon1.bayesian.alpha_health |> should.equal(101.0)
  holon1.rete_ul.tokens_evaluated |> should.equal(1)

  // Pulse 2: Latency spike: Target 10.0ms, observed 20.0ms -> 100% error -> Lyapunov energy > 0.05 -> Stressed
  let #(holon2, report2) =
    execute_autonomic_pulse(holon1, 20.0, 10.0)

  report2.is_stable |> should.be_false
  report2.action_taken |> should.equal("lyapunov_damping_engaged")
  holon2.lifecycle |> should.equal(super_agent.Stressed)
}

pub fn json_serialization_test() {
  let holon =
    create_super_agent(
      "json-agent",
      "JSON Serialization Test Agent",
      "messaging",
      4,
    )
    |> set_mode(SovereignEvolution)

  let json_obj = to_json(holon)
  let json_str = json.to_string(json_obj)
  json_str |> string.contains("json-agent") |> should.be_true
  json_str |> string.contains("sovereign_evolution") |> should.be_true
  json_str |> string.contains("\"active_capabilities\":11") |> should.be_true
}
