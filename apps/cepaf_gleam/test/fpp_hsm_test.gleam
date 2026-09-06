//// =============================================================================
//// [UOS-FPP-HSM-TEST] NASA JPL F Prime Hierarchical State Machine Test Suite
//// =============================================================================
//// Formally tests the Hierarchical State Machine (HSM) interpreter in Gleam:
//// 1. Deep initial hierarchical state entry (Root -> Composite -> Leaf)
//// 2. Intra-composite peer state transition with LCA exit/entry ordering
//// 3. Multi-level signal bubbling from leaf to root ancestor
//// 4. Nested recovery transition with recursive initial sub-state resolution
//// 5. Unhandled signal drop without state corruption
//// =============================================================================

import cepaf_gleam/fpp/domain.{
  HierarchicalMachine, HierarchicalState, ToState, Transition,
}
import cepaf_gleam/fpp/interp.{dispatch_hsm_signal, init_hsm}
import gleam/option.{None, Some}
import gleeunit/should

fn spacecraft_flight_hsm() -> domain.StateMachine {
  let cruise_state =
    HierarchicalState(
      name: "Cruise",
      parent: Some("Flight"),
      entry: ["enter_cruise"],
      exit: ["exit_cruise"],
      transitions: [
        Transition(
          on_signal: "approach",
          guard: None,
          do_actions: ["prepare_gear"],
          target: ToState("Landing"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let landing_state =
    HierarchicalState(
      name: "Landing",
      parent: Some("Flight"),
      entry: ["enter_landing"],
      exit: ["exit_landing"],
      transitions: [
        Transition(
          on_signal: "touchdown",
          guard: None,
          do_actions: ["cut_engines"],
          target: ToState("SurfaceOps"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let surface_state =
    HierarchicalState(
      name: "SurfaceOps",
      parent: Some("Operational"),
      entry: ["enter_surface"],
      exit: ["exit_surface"],
      transitions: [],
      sub_states: [],
      initial_sub_state: None,
    )

  let flight_state =
    HierarchicalState(
      name: "Flight",
      parent: Some("Operational"),
      entry: ["enter_flight"],
      exit: ["exit_flight"],
      transitions: [
        Transition(
          on_signal: "anomaly",
          guard: None,
          do_actions: ["alert_operator"],
          target: ToState("SafeMode"),
        ),
      ],
      sub_states: [cruise_state, landing_state],
      initial_sub_state: Some("Cruise"),
    )

  let operational_state =
    HierarchicalState(
      name: "Operational",
      parent: None,
      entry: ["enter_operational"],
      exit: ["exit_operational"],
      transitions: [
        Transition(
          on_signal: "solar_storm",
          guard: None,
          do_actions: ["power_down_payload"],
          target: ToState("SafeMode"),
        ),
      ],
      sub_states: [flight_state, surface_state],
      initial_sub_state: Some("Flight"),
    )

  let safemode_state =
    HierarchicalState(
      name: "SafeMode",
      parent: None,
      entry: ["enter_safemode"],
      exit: ["exit_safemode"],
      transitions: [
        Transition(
          on_signal: "reset",
          guard: None,
          do_actions: ["system_reboot"],
          target: ToState("Operational"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  HierarchicalMachine(
    machine_name: "SpacecraftFlightHSM",
    signals: [],
    guards: [],
    actions: [],
    root_states: [operational_state, safemode_state],
    choices: [],
    initial: #(["power_on"], "Operational"),
  )
}

// ----------------------------------------------------------- 1. Initial Entry

pub fn hsm_initial_hierarchical_entry_test() {
  let sm = spacecraft_flight_hsm()
  let init_res = init_hsm(sm)
  init_res |> should.be_ok

  let assert Ok(s0) = init_res
  s0.active_path
  |> should.equal(["Operational", "Flight", "Cruise"])

  s0.log
  |> should.equal([
    "power_on",
    "enter_operational",
    "enter_flight",
    "enter_cruise",
  ])
}

// ----------------------------------------------------- 2. Peer LCA Transition

pub fn hsm_peer_leaf_transition_test() {
  let sm = spacecraft_flight_hsm()
  let assert Ok(s0) = init_hsm(sm)

  // Cruise -> Landing via "approach"
  let res = dispatch_hsm_signal(sm, [], s0, "approach")
  res |> should.be_ok

  let assert Ok(s1) = res
  s1.active_path
  |> should.equal(["Operational", "Flight", "Landing"])

  // Exit Cruise (leaf first), do prepare_gear, enter Landing
  s1.log
  |> should.equal([
    "power_on",
    "enter_operational",
    "enter_flight",
    "enter_cruise",
    "exit_cruise",
    "prepare_gear",
    "enter_landing",
  ])
}

// ------------------------------------------------------- 3. Signal Bubbling

pub fn hsm_signal_bubbling_to_root_test() {
  let sm = spacecraft_flight_hsm()
  let assert Ok(s0) = init_hsm(sm)
  let assert Ok(s1) = dispatch_hsm_signal(sm, [], s0, "approach")

  // Currently in Landing. Landing doesn't handle "solar_storm", Flight doesn't handle it,
  // bubbles up to Operational which transitions to SafeMode.
  let res = dispatch_hsm_signal(sm, [], s1, "solar_storm")
  res |> should.be_ok

  let assert Ok(s2) = res
  s2.active_path
  |> should.equal(["SafeMode"])

  // Exits must fire in order from leaf up to root: Landing -> Flight -> Operational
  s2.log
  |> should.equal([
    "power_on",
    "enter_operational",
    "enter_flight",
    "enter_cruise",
    "exit_cruise",
    "prepare_gear",
    "enter_landing",
    "exit_landing",
    "exit_flight",
    "exit_operational",
    "power_down_payload",
    "enter_safemode",
  ])
}

// -------------------------------------------- 4. Recursive Target Resolution

pub fn hsm_nested_recovery_transition_test() {
  let sm = spacecraft_flight_hsm()
  let assert Ok(s0) = init_hsm(sm)
  let assert Ok(s1) = dispatch_hsm_signal(sm, [], s0, "approach")
  let assert Ok(s2) = dispatch_hsm_signal(sm, [], s1, "solar_storm")

  // Now in SafeMode. SafeMode receives "reset" -> target is "Operational"
  // Operational must recursively enter Flight and then Cruise.
  let res = dispatch_hsm_signal(sm, [], s2, "reset")
  res |> should.be_ok

  let assert Ok(s3) = res
  s3.active_path
  |> should.equal(["Operational", "Flight", "Cruise"])

  s3.log
  |> should.equal([
    "power_on",
    "enter_operational",
    "enter_flight",
    "enter_cruise",
    "exit_cruise",
    "prepare_gear",
    "enter_landing",
    "exit_landing",
    "exit_flight",
    "exit_operational",
    "power_down_payload",
    "enter_safemode",
    "exit_safemode",
    "system_reboot",
    "enter_operational",
    "enter_flight",
    "enter_cruise",
  ])
}

// ------------------------------------------------- 5. Unhandled Signal Drop

pub fn hsm_unhandled_signal_drop_test() {
  let sm = spacecraft_flight_hsm()
  let assert Ok(s0) = init_hsm(sm)

  // Dispatch unknown signal "warp_drive"
  let res = dispatch_hsm_signal(sm, [], s0, "warp_drive")
  res |> should.be_ok

  let assert Ok(s1) = res
  // Path and log must remain untouched
  s1.active_path |> should.equal(s0.active_path)
  s1.log |> should.equal(s0.log)
}
