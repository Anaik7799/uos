/// TUI view for Planning Dashboard — 8-panel compact ANSI cockpit (SC-GLM-UI-001, SC-GLM-UI-004).
/// Renders all 8 panels: Tasks, OODA, Safety, Enforcer, Services, Chaya, Startup, Mode.
/// Same domain types as Lustre (SC-GLM-UI-009). Renders via cockpit/visuals.gleam.
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007, SC-GLM-UI-008
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/planning_dashboard.{
  type CockpitMode, type ContainerWave, type DashboardModel,
  type SafetyCheckResult, type ServiceNode, type SyncPhaseResult, Bright,
  CheckFail, CheckNotRun, CheckPass, CheckWarn, Dark, Dim, EmergencyMode, Normal,
}
import gleam/int
import gleam/list
import gleam/string

// =============================================================================
// Main render
// =============================================================================

pub fn render(model: DashboardModel) -> String {
  let mode_color = cockpit_mode_color(model.cockpit_mode)
  let mode_str = cockpit_mode_to_display(model.cockpit_mode)

  let header =
    visuals.with_color(
      "═══ C3I PLANNING COCKPIT [" <> mode_str <> "] ═══",
      mode_color,
    )
    <> "\n"

  let tasks_section = render_tasks(model)
  let ooda_section = render_ooda(model)
  let safety_section = render_safety(model)
  let enforcer_section = render_enforcer(model)
  let services_section = render_services(model)
  let chaya_section = render_chaya(model)
  let startup_section = render_startup(model)

  header
  <> tasks_section
  <> ooda_section
  <> safety_section
  <> enforcer_section
  <> services_section
  <> chaya_section
  <> startup_section
}

// =============================================================================
// Panel 1: Tasks
// =============================================================================

fn render_tasks(model: DashboardModel) -> String {
  let total = list.length(model.tasks)
  let pending =
    list.filter(model.tasks, fn(t: planning_dashboard.TaskCard) {
      t.status == "pending"
    })
    |> list.length
  let in_progress =
    list.filter(model.tasks, fn(t: planning_dashboard.TaskCard) {
      t.status == "in_progress"
    })
    |> list.length
  let completed =
    list.filter(model.tasks, fn(t: planning_dashboard.TaskCard) {
      t.status == "completed"
    })
    |> list.length
  let blocked =
    list.filter(model.tasks, fn(t: planning_dashboard.TaskCard) {
      t.status == "blocked"
    })
    |> list.length

  visuals.with_color("── TASKS", "cyan")
  <> " [filter: "
  <> model.task_filter
  <> "]\n"
  <> "  "
  <> visuals.with_color("P:" <> int.to_string(pending), "yellow")
  <> " "
  <> visuals.with_color("IP:" <> int.to_string(in_progress), "blue")
  <> " "
  <> visuals.with_color("C:" <> int.to_string(completed), "green")
  <> " "
  <> visuals.with_color("B:" <> int.to_string(blocked), "red")
  <> "  Total: "
  <> int.to_string(total)
  <> "\n"
}

// =============================================================================
// Panel 2: OODA
// =============================================================================

fn render_ooda(model: DashboardModel) -> String {
  let phase_str = case model.ooda_phase {
    planning_dashboard.Idle -> "IDLE"
    planning_dashboard.ObservePhase -> "OBSERVE"
    planning_dashboard.OrientPhase -> "ORIENT"
    planning_dashboard.DecidePhase -> "DECIDE"
    planning_dashboard.ActPhase -> "ACT"
  }

  visuals.with_color("── OODA", "cyan")
  <> "\n"
  <> "  Cycles: "
  <> int.to_string(model.ooda_cycle_count)
  <> "  Latency: "
  <> int.to_string(model.last_cycle_ms)
  <> "ms  Phase: "
  <> phase_str
  <> "\n"
}

// =============================================================================
// Panel 3: Safety
// =============================================================================

fn render_safety(model: DashboardModel) -> String {
  let check_count = list.length(model.safety_checks)
  let pass_count =
    list.filter(model.safety_checks, fn(c: SafetyCheckResult) {
      case c {
        CheckPass(_) -> True
        _ -> False
      }
    })
    |> list.length
  let fail_count = check_count - pass_count
  let active_str = case model.safety_active {
    True -> visuals.with_color("ACTIVE", "green")
    False -> visuals.with_color("INACTIVE", "red")
  }

  visuals.with_color("── SAFETY", "cyan")
  <> "\n"
  <> "  Status: "
  <> active_str
  <> "  Checks: "
  <> int.to_string(pass_count)
  <> "/"
  <> int.to_string(check_count)
  <> " pass"
  <> case fail_count > 0 {
    True ->
      "  " <> visuals.with_color("FAIL:" <> int.to_string(fail_count), "red")
    False -> ""
  }
  <> "\n"
  <> render_safety_checks(model.safety_checks)
}

fn render_safety_checks(checks: List(SafetyCheckResult)) -> String {
  checks
  |> list.take(5)
  |> list.map(fn(c: SafetyCheckResult) {
    case c {
      CheckPass(name) ->
        "    " <> name <> ": " <> visuals.with_color("PASS", "green")
      CheckFail(name, reason) ->
        "    "
        <> name
        <> ": "
        <> visuals.with_color("FAIL", "red")
        <> " "
        <> reason
      CheckWarn(name) ->
        "    " <> name <> ": " <> visuals.with_color("WARN", "yellow")
      CheckNotRun(name) ->
        "    " <> name <> ": " <> visuals.with_color("NOT_RUN", "dim")
    }
  })
  |> string.join("\n")
  |> fn(s) {
    case s {
      "" -> ""
      _ -> s <> "\n"
    }
  }
}

// =============================================================================
// Panel 4: Enforcer (Circuit Breaker)
// =============================================================================

fn render_enforcer(model: DashboardModel) -> String {
  let circuit_count = list.length(model.open_circuits)
  let status = case circuit_count {
    0 -> visuals.with_color("ALL CLOSED", "green")
    _ -> visuals.with_color(int.to_string(circuit_count) <> " OPEN", "red")
  }

  visuals.with_color("── ENFORCER", "cyan")
  <> "\n"
  <> "  Violations: "
  <> int.to_string(model.total_violations)
  <> "  Circuits: "
  <> status
  <> case circuit_count > 0 {
    True ->
      "\n  Open: "
      <> string.join(
        list.take(model.open_circuits, 5)
          |> list.map(fn(c) { visuals.with_color(c, "red") }),
        ", ",
      )
    False -> ""
  }
  <> "\n"
}

// =============================================================================
// Panel 5: Services
// =============================================================================

fn render_services(model: DashboardModel) -> String {
  let total = list.length(model.services)
  let online =
    list.filter(model.services, fn(s: ServiceNode) { s.health >=. 0.8 })
    |> list.length

  visuals.with_color("── SERVICES", "cyan")
  <> "\n"
  <> "  Healthy: "
  <> int.to_string(online)
  <> "/"
  <> int.to_string(total)
  <> "  Quorum: "
  <> case model.quorum {
    True -> visuals.with_color("MET", "green")
    False -> visuals.with_color("LOST", "red")
  }
  <> "\n"
  <> render_service_list(model.services)
}

fn render_service_list(services: List(ServiceNode)) -> String {
  services
  |> list.take(8)
  |> list.map(fn(s: ServiceNode) {
    let color = case s.status {
      "online" -> "green"
      "offline" -> "red"
      "degraded" -> "yellow"
      _ -> "dim"
    }
    "    " <> visuals.with_color(s.name, color)
  })
  |> string.join("\n")
  |> fn(s) {
    case s {
      "" -> ""
      _ -> s <> "\n"
    }
  }
}

// =============================================================================
// Panel 6: Chaya Sync
// =============================================================================

fn render_chaya(model: DashboardModel) -> String {
  let phase_count = list.length(model.sync_phases)
  let success_count =
    list.filter(model.sync_phases, fn(p: SyncPhaseResult) { p.success })
    |> list.length

  visuals.with_color("── CHAYA SYNC", "cyan")
  <> "\n"
  <> "  Phases: "
  <> int.to_string(success_count)
  <> "/"
  <> int.to_string(phase_count)
  <> " complete  Orphans: "
  <> int.to_string(model.orphan_count)
  <> "  Mismatches: "
  <> int.to_string(model.mismatch_count)
  <> "\n"
  <> render_sync_phases(model.sync_phases)
}

fn render_sync_phases(phases: List(SyncPhaseResult)) -> String {
  phases
  |> list.take(6)
  |> list.map(fn(p: SyncPhaseResult) {
    let status_color = case p.success {
      True -> "green"
      False -> "red"
    }
    let status_icon = case p.success {
      True -> "OK"
      False -> "FAIL"
    }
    "    "
    <> visuals.with_color(status_icon, status_color)
    <> " "
    <> p.phase
    <> " (count:"
    <> int.to_string(p.count)
    <> " errors:"
    <> int.to_string(p.errors)
    <> ")"
  })
  |> string.join("\n")
  |> fn(s) {
    case s {
      "" -> ""
      _ -> s <> "\n"
    }
  }
}

// =============================================================================
// Panel 7: Startup Waves
// =============================================================================

fn render_startup(model: DashboardModel) -> String {
  let wave_count = list.length(model.waves)

  visuals.with_color("── STARTUP WAVES", "cyan")
  <> "\n"
  <> "  Waves: "
  <> int.to_string(wave_count)
  <> "  Critical Path: "
  <> int.to_string(list.length(model.critical_path))
  <> " nodes  Total: "
  <> int.to_string(model.total_startup_ms)
  <> "ms"
  <> "\n"
  <> render_waves(model.waves)
}

fn render_waves(waves: List(ContainerWave)) -> String {
  waves
  |> list.take(5)
  |> list.map(fn(w: ContainerWave) {
    "    W"
    <> int.to_string(w.wave)
    <> " ("
    <> int.to_string(list.length(w.containers))
    <> " containers, "
    <> int.to_string(w.duration_ms)
    <> "ms)"
  })
  |> string.join("\n")
  |> fn(s) {
    case s {
      "" -> ""
      _ -> s <> "\n"
    }
  }
}

// =============================================================================
// Helpers
// =============================================================================

fn cockpit_mode_color(mode: CockpitMode) -> String {
  case mode {
    Dark -> "green"
    Dim -> "yellow"
    Normal -> ""
    Bright -> "yellow"
    EmergencyMode -> "red"
  }
}

fn cockpit_mode_to_display(mode: CockpitMode) -> String {
  case mode {
    Dark -> "DARK"
    Dim -> "DIM"
    Normal -> "NORMAL"
    Bright -> "BRIGHT"
    EmergencyMode -> "EMERGENCY"
  }
}
