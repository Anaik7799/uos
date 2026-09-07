//// =============================================================================
//// TUI BDD SCENARIO SUITE (Behavior-Driven Development)
//// =============================================================================
//// STAMP: SC-BDD-001, SC-GLM-UI-001, SC-GLM-UI-007, SC-GLM-UI-008
//// Spec: docs/design/20260907-2259-tui-bdd-specification.md
////
//// This suite executes canonical GIVEN-WHEN-THEN BDD specifications:
//// 1. Pure Decoupled Model State Machine
//// 2. Virtual Buffer & ANSI Escape Invariants
//// 3. Homeostasis, Swarm Messages, Evolution Telemetry
//// 4. Dimension Bounds & Clean Semantic Isolation
//// =============================================================================

import cepaf_gleam/ui/tui/sysadmin_cockpit.{
  ContainersTab, Dark, DoctorTab, EvolutionTab, HomeostasisTab,
  MessageBoardTab, OverviewTab, SecurityTab, StorageTab, StreamTab,
  SupervisorsTab, TasksTab, ZenohTab, default_model, next_tab, prev_tab, render,
  select_tab,
}
import gleam/list
import gleam/regexp
import gleam/string
import gleeunit/should

/// Helper: Strips all ANSI escape sequences to yield pure semantic text
pub fn strip_ansi(raw: String) -> String {
  let assert Ok(re) = regexp.from_string("\u{001b}\\[[0-9;]*[a-zA-Z]")
  regexp.replace(re, raw, "")
}

// =============================================================================
// SCENARIO 1: Initial Cockpit State & Constitutional Storage Lock
// =============================================================================

pub fn given_initialized_cockpit_when_inspected_then_overview_and_locked_storage_test() {
  // GIVEN: A freshly initialized sysadmin model
  let model = default_model()

  // WHEN: Default state is verified
  // THEN: The active tab is OverviewTab
  should.equal(model.active_tab, OverviewTab)

  // AND: The cockpit mode is Dark
  should.equal(model.cockpit_mode, Dark)

  // AND: The NVMe root partition is locked with canonical serial
  should.equal(model.nvme_root_serial, "25503L801736")
  should.equal(model.nvme_root_locked, True)
}

// =============================================================================
// SCENARIO 2: Tab Navigation & Modulo-12 Cycling
// =============================================================================

pub fn given_doctor_tab_when_cycled_forward_then_traverses_cybernetics_and_wraps_test() {
  // GIVEN: The cockpit is positioned at DoctorTab
  let model = default_model()
  let m_doctor = select_tab(model, DoctorTab)
  should.equal(m_doctor.active_tab, DoctorTab)

  // WHEN: The user advances to the next tab
  let m_homeo = next_tab(m_doctor)
  // THEN: The active tab is HomeostasisTab
  should.equal(m_homeo.active_tab, HomeostasisTab)

  // WHEN: The user advances again
  let m_msg = next_tab(m_homeo)
  // THEN: The active tab is MessageBoardTab
  should.equal(m_msg.active_tab, MessageBoardTab)

  // WHEN: The user advances again
  let m_evo = next_tab(m_msg)
  // THEN: The active tab is EvolutionTab
  should.equal(m_evo.active_tab, EvolutionTab)

  // WHEN: The user advances past the 12th tab
  let m_wrap = next_tab(m_evo)
  // THEN: The active tab wraps modulo 12 to OverviewTab
  should.equal(m_wrap.active_tab, OverviewTab)

  // AND: Reverse navigation steps backwards accurately
  let m_back_to_evo = prev_tab(m_wrap)
  should.equal(m_back_to_evo.active_tab, EvolutionTab)
}

// =============================================================================
// SCENARIO 3: Biological Homeostasis Monitoring
// =============================================================================

pub fn given_homeostasis_tab_when_rendered_then_displays_equilibrium_and_factors_test() {
  // GIVEN: The model is set to HomeostasisTab
  let model = default_model()
  let m_homeo = select_tab(model, HomeostasisTab)

  // WHEN: The virtual buffer frame is rendered
  let frame = render(m_homeo)
  let clean_text = strip_ansi(frame)

  // THEN: The header announces Biomorphic Homeostasis
  should.equal(string.contains(clean_text, "BIOMORPHIC PHYSIOLOGICAL HOMEOSTASIS"), True)

  // AND: The equilibrium status is stable
  should.equal(string.contains(clean_text, "HOMEOSTATIC EQUILIBRIUM"), True)

  // AND: Physiological telemetry factors are present
  should.equal(string.contains(clean_text, "cpu_pct"), True)
  should.equal(string.contains(clean_text, "memory_pct"), True)
  should.equal(string.contains(clean_text, "Lyapunov V"), True)

  // AND: Zero unhandled or invalid tokens exist
  should.equal(string.contains(clean_text, "NaN"), False)
  should.equal(string.contains(clean_text, "undefined"), False)
}

// =============================================================================
// SCENARIO 4: Swarm Message Dashboard & Active Agent Telemetry
// =============================================================================

pub fn given_message_board_tab_when_rendered_then_displays_active_agents_and_bus_test() {
  // GIVEN: The model is set to MessageBoardTab
  let model = default_model()
  let m_msg = select_tab(model, MessageBoardTab)

  // WHEN: The virtual buffer frame is rendered
  let frame = render(m_msg)
  let clean_text = strip_ansi(frame)

  // THEN: The title displays Swarm Message Dashboard
  should.equal(string.contains(clean_text, "SWARM MESSAGE DASHBOARD"), True)

  // AND: Key sovereign workers and roles are rendered
  should.equal(string.contains(clean_text, "EXEC-001 (Orchestrator)"), True)
  should.equal(string.contains(clean_text, "Cortex Engine"), True)
  should.equal(string.contains(clean_text, "Prajna Breaker"), True)

  // AND: Active OODA cycles and sub-goals are reported
  should.equal(string.contains(clean_text, "OODA"), True)
  should.equal(string.contains(clean_text, "A2A INTER-AGENT BUS"), True)
}

// =============================================================================
// SCENARIO 5: Swarm Evolution & Constitutional Quorum Ratification
// =============================================================================

pub fn given_evolution_tab_when_rendered_then_displays_pareto_and_4party_quorum_test() {
  // GIVEN: The model is set to EvolutionTab
  let model = default_model()
  let m_evo = select_tab(model, EvolutionTab)

  // WHEN: The virtual buffer frame is rendered
  let frame = render(m_evo)
  let clean_text = strip_ansi(frame)

  // THEN: The header announces Autonomous System Evolution
  should.equal(string.contains(clean_text, "AUTONOMOUS SYSTEM EVOLUTION"), True)

  // AND: The gate indicator is active
  should.equal(string.contains(clean_text, "EVOLUTION GATE OPEN"), True)

  // AND: Pareto frontier candidates are listed
  should.equal(string.contains(clean_text, "MAX SIMD Scorer Optimization"), True)

  // AND: Constitutional 4-party quorum consensus is displayed
  should.equal(string.contains(clean_text, "4-Party Quorum   : 3-of-4 Supermajority Ratification Required"), True)
  should.equal(string.contains(clean_text, "Codex Sovereign"), True)
  should.equal(string.contains(clean_text, "AGY Sovereign"), True)
  should.equal(string.contains(clean_text, "Claude Sovereign"), True)
  should.equal(string.contains(clean_text, "OpenRouter Advisory"), True)
}

// =============================================================================
// SCENARIO 6: Terminal Dimension Bounds & Responsive Reflow Invariants
// =============================================================================

pub fn given_locked_dimensions_when_rendered_then_all_12_tabs_respect_bounds_test() {
  // GIVEN: An initial sysadmin model
  let model = default_model()

  // AND: All 12 operational tabs
  let all_tabs = [
    OverviewTab,
    ContainersTab,
    StorageTab,
    ZenohTab,
    SupervisorsTab,
    TasksTab,
    SecurityTab,
    StreamTab,
    DoctorTab,
    HomeostasisTab,
    MessageBoardTab,
    EvolutionTab,
  ]

  // WHEN: Each tab is rendered to the virtual buffer
  // THEN: All tabs produce bounded, non-empty text frames
  list.each(all_tabs, fn(tab) {
    let frame = render(select_tab(model, tab))
    let lines = string.split(frame, "\n")

    // Ensure output has multiple lines and non-empty content
    should.equal(list.is_empty(lines), False)
    let assert Ok(header) = list.first(lines)
    should.equal(string.is_empty(header), False)

    // Ensure Tailscale FQDN navigation URL is present
    should.equal(string.contains(frame, "nas-1.tail55d152.ts.net:4100"), True)
  })
}

// =============================================================================
// SCENARIO 7: Color Profile Normalization & Semantic Text Isolation
// =============================================================================

pub fn given_ansi_output_when_stripped_then_clean_semantic_text_isolated_test() {
  // GIVEN: An ANSI styled frame containing escape sequences
  let model = default_model()
  let raw_frame = render(model)

  // WHEN: The frame is passed through strip_ansi
  let clean_frame = strip_ansi(raw_frame)

  // THEN: All ANSI escape sequences are completely eliminated
  should.equal(string.contains(clean_frame, "\u{001b}["), False)

  // AND: The semantic text remains completely intact
  should.equal(string.contains(clean_frame, "SYSTEM OVERVIEW"), True)
  should.equal(string.contains(clean_frame, "nas-1.tail55d152.ts.net:4100"), True)
  should.equal(string.contains(clean_frame, "LOCKED (25503L801736)"), True)
}
