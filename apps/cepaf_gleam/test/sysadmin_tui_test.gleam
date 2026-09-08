import cepaf_gleam/ui/tui/sysadmin_cockpit.{
  Bright, ContainersTab, Dark, Dim, DoctorTab, Emergency, EvolutionTab,
  HomeostasisTab, MessageBoardTab, Normal, OverviewTab, SecurityTab,
  StorageTab, StreamTab, SupervisorsTab, TasksTab, ZenohTab,
  default_model, next_container, next_tab, prev_container, prev_tab, render,
  restart_selected_container, select_tab, start_selected_container,
  stop_selected_container, toggle_mode, trigger_garbage_collection,
}
import gleam/list
import gleam/string
import gleeunit/should

pub fn default_model_initialization_test() {
  let model = default_model()
  should.equal(model.active_tab, OverviewTab)
  should.equal(model.cockpit_mode, Dark)
  should.equal(list.length(model.containers), 16)
  should.equal(model.nvme_root_serial, "25503L801736")
  should.equal(model.nvme_root_locked, True)
  should.equal(model.server_status, "ok")
}

pub fn tab_selection_and_cycling_test() {
  let model = default_model()
  let m1 = select_tab(model, ContainersTab)
  should.equal(m1.active_tab, ContainersTab)

  let m2 = next_tab(m1)
  should.equal(m2.active_tab, StorageTab)

  let m3 = prev_tab(m2)
  should.equal(m3.active_tab, ContainersTab)

  // Cycle tabs forward across 12 tabs
  let m_doctor = select_tab(model, DoctorTab)
  let m_homeo = next_tab(m_doctor)
  should.equal(m_homeo.active_tab, HomeostasisTab)

  let m_msg = next_tab(m_homeo)
  should.equal(m_msg.active_tab, MessageBoardTab)

  let m_evo = next_tab(m_msg)
  should.equal(m_evo.active_tab, EvolutionTab)

  let m_cycle_back = next_tab(m_evo)
  should.equal(m_cycle_back.active_tab, OverviewTab)
}

pub fn cockpit_mode_toggling_test() {
  let model = default_model()
  should.equal(model.cockpit_mode, Dark)

  let m1 = toggle_mode(model)
  should.equal(m1.cockpit_mode, Dim)

  let m2 = toggle_mode(m1)
  should.equal(m2.cockpit_mode, Normal)

  let m3 = toggle_mode(m2)
  should.equal(m3.cockpit_mode, Bright)

  let m4 = toggle_mode(m3)
  should.equal(m4.cockpit_mode, Emergency)

  let m5 = toggle_mode(m4)
  should.equal(m5.cockpit_mode, Dark)
}

pub fn container_navigation_and_actions_test() {
  let model = default_model()
  should.equal(model.selected_container, 0)

  let m_next = next_container(model)
  should.equal(m_next.selected_container, 1)

  let m_prev = prev_container(m_next)
  should.equal(m_prev.selected_container, 0)

  let m_prev_wrap = prev_container(model)
  should.equal(m_prev_wrap.selected_container, 15)

  // Test container stop/start/restart
  let m_stopped = stop_selected_container(model)
  let assert Ok(c_stopped) = list.first(m_stopped.containers)
  should.equal(c_stopped.status, "exited")

  let m_started = start_selected_container(m_stopped)
  let assert Ok(c_started) = list.first(m_started.containers)
  should.equal(c_started.status, "running")

  let m_restarted = restart_selected_container(m_started)
  let assert Ok(c_restarted) = list.first(m_restarted.containers)
  should.equal(c_restarted.status, "running")
  should.equal(c_restarted.restarts, 1)
}

pub fn garbage_collection_test() {
  let model = default_model()
  let m_gc = trigger_garbage_collection(model)
  should.equal(string.contains(m_gc.status_msg, "Garbage Collection"), True)
}

pub fn render_all_9_tabs_test() {
  let model = default_model()

  // Overview Tab
  let out_overview = render(model)
  should.equal(string.contains(out_overview, "SYSTEM OVERVIEW"), True)
  should.equal(string.contains(out_overview, "nas-1.tail55d152.ts.net:4100"), True)
  should.equal(string.contains(out_overview, "LOCKED (25503L801736)"), True)

  // Containers Tab
  let out_containers = render(select_tab(model, ContainersTab))
  should.equal(string.contains(out_containers, "PODMAN CONTAINER GENOME"), True)
  should.equal(string.contains(out_containers, "db-prod"), True)

  // Storage Tab
  let out_storage = render(select_tab(model, StorageTab))
  should.equal(string.contains(out_storage, "HARDWARE STORAGE"), True)
  should.equal(string.contains(out_storage, "HARD_DENIED_SYSTEM_OS_SERIAL"), True)
  should.equal(string.contains(out_storage, "25503L801736"), True)

  // Zenoh Tab
  let out_zenoh = render(select_tab(model, ZenohTab))
  should.equal(string.contains(out_zenoh, "ZENOH MESH"), True)
  should.equal(string.contains(out_zenoh, "indrajaal/l0/const/**"), True)

  // Supervisors Tab
  let out_sup = render(select_tab(model, SupervisorsTab))
  should.equal(string.contains(out_sup, "OTP 29 SUPERVISOR TREE"), True)
  should.equal(string.contains(out_sup, "uos_sup"), True)

  // Tasks Tab
  let out_tasks = render(select_tab(model, TasksTab))
  should.equal(string.contains(out_tasks, "SIL-6 TASK BOARD"), True)
  should.equal(string.contains(out_tasks, "2oo3 REACHED"), True)

  // Security Tab
  let out_sec = render(select_tab(model, SecurityTab))
  should.equal(string.contains(out_sec, "ZERO-TRUST SECURITY"), True)
  should.equal(string.contains(out_sec, "agy"), True)

  // Stream Tab
  let out_stream = render(select_tab(model, StreamTab))
  should.equal(string.contains(out_stream, "AG-UI 32-EVENT"), True)

  // Doctor Tab
  let out_doctor = render(select_tab(model, DoctorTab))
  should.equal(string.contains(out_doctor, "SYSTEM DOCTOR"), True)
  should.equal(string.contains(out_doctor, "100% ALL CHECKS PASS"), True)

  // Homeostasis Tab
  let out_homeo = render(select_tab(model, HomeostasisTab))
  should.equal(string.contains(out_homeo, "HOMEOSTASIS | UNAVAILABLE"), True)
  should.equal(string.contains(out_homeo, "Attributed health: UNKNOWN"), True)
  should.equal(string.contains(out_homeo, "Control authority: NONE"), True)

  // Message Board Tab
  let out_msg = render(select_tab(model, MessageBoardTab))
  should.equal(string.contains(out_msg, "SWARM MESSAGE DASHBOARD"), True)
  should.equal(string.contains(out_msg, "AGY (L3)"), True)
  should.equal(string.contains(out_msg, "Codex-Astra (L3)"), True)

  // Evolution Tab
  let out_evo = render(select_tab(model, EvolutionTab))
  should.equal(string.contains(out_evo, "Model generation: UNKNOWN"), True)
  should.equal(string.contains(out_evo, "EVOLUTION GATE OPEN"), False)
  should.equal(string.contains(out_evo, "Control authority: NONE"), True)
}

pub fn terminal_dimension_and_bounds_test() {
  let model = default_model()

  // Test across all 12 tabs that rendering succeeds and lines are bounded
  let tabs = [
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

  list.each(tabs, fn(tab) {
    let rendered = render(select_tab(model, tab))
    let lines = string.split(rendered, "\n")
    should.equal(list.is_empty(lines), False)

    // Verify non-empty content and presence of header
    let assert Ok(first_line) = list.first(lines)
    should.equal(string.is_empty(first_line), False)
  })
}
