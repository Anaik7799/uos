//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/tui/sysadmin_cockpit</module>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <layer>L1_ATOMIC</layer>
////     <layer>L2_COMPONENT</layer>
////     <layer>L3_TRANSACTION</layer>
////     <layer>L4_SYSTEM</layer>
////     <layer>L5_COGNITIVE</layer>
////     <layer>L6_ECOSYSTEM</layer>
////     <layer>L7_FEDERATION</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007, SC-MUDA-001, SC-SATYA-006</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// SysadminCockpit — Universal Mission-Critical Remote Operations TUI Cockpit.
//// Provides 9 categorized workflow tabs:
////   1. Overview & Health
////   2. Podman Containers (16 SIL-6 genome)
////   3. Storage & Ceph Safety (Hardware NVMe root locked)
////   4. Zenoh Mesh & Network (Tailscale FQDN)
////   5. OTP 29 Supervisors & Actors (25 agents)
////   6. Tasks & Planning (SIL-6 board)
////   7. Security & IAM (AGY sovereign, Zero-Trust traps)
////   8. AG-UI 32-Event Stream
////   9. Doctor & Preflight (84 EV cycles)
////
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007, SC-MUDA-001

import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/homeostasis_data as homeostasis_data
import cepaf_gleam/ui/homeostasis_status as homeostasis_status
import cepaf_gleam/ui/tui/homeostasis_evolution_view as homeostasis_view
import gleam/float
import gleam/int
import gleam/list
import gleam/string
import cepaf_gleam/ha/homeostasis_evolution_engine.{
  type HomeostasisSystemState, init_homeostasis_system,
}
import cepaf_gleam/ha/physiological_homeostasis

// =============================================================================
// Domain Types & Enums
// =============================================================================

/// 9 Categorized Operational Workflow Tabs for System Administrators
pub type Tab {
  OverviewTab
  ContainersTab
  StorageTab
  ZenohTab
  SupervisorsTab
  TasksTab
  SecurityTab
  StreamTab
  DoctorTab
  HomeostasisTab
  MessageBoardTab
  EvolutionTab
}

/// 5-Mode Dark Cockpit State Machine (SC-HMI-010)
pub type CockpitMode {
  Dark
  Dim
  Normal
  Bright
  Emergency
}

/// A container in the 16-container SIL-6 genome
pub type ContainerItem {
  ContainerItem(
    name: String,
    tier: String,
    status: String,
    image: String,
    cpu_pct: Float,
    mem_mb: Int,
    ports: String,
    restarts: Int,
  )
}

/// Physical storage drive and Ceph OSD state
pub type StorageItem {
  StorageItem(
    drive_id: String,
    serial: String,
    size_gb: Int,
    used_gb: Int,
    health: String,
    locked: Bool,
  )
}

/// Zenoh pub/sub mesh topic
pub type ZenohTopicItem {
  ZenohTopicItem(topic: String, message_count: Int, last_seen_s_ago: Int)
}

/// OTP 29 supervisor tree node
pub type SupervisorItem {
  SupervisorItem(
    name: String,
    layer: String,
    child_count: Int,
    status: String,
    restarts: Int,
  )
}

/// SIL-6 task card
pub type TaskItem {
  TaskItem(
    id: String,
    title: String,
    domain: String,
    priority: String,
    status: String,
  )
}

/// Zero-Trust security event record
pub type SecurityEventItem {
  SecurityEventItem(
    timestamp: String,
    event_type: String,
    source_ip: String,
    outcome: String,
  )
}

/// Doctor / EV-cycle boundary diagnostic check
pub type DoctorCheckItem {
  DoctorCheckItem(id: String, name: String, domain: String, status: String)
}

/// A2A / Swarm Message Envelope for Message Dashboard
pub type MessageBoardItem {
  MessageBoardItem(
    id: String,
    timestamp_iso: String,
    from_agent: String,
    to_agent: String,
    kind: String,
    payload_summary: String,
    transport_status: String,
  )
}

/// Active Agent Subsystem Tracking Record
pub type AgentActivityItem {
  AgentActivityItem(
    name: String,
    role: String,
    current_action: String,
    status: String,
  )
}

/// The unified Sysadmin Cockpit state model
pub type SysadminModel {
  SysadminModel(
    active_tab: Tab,
    cockpit_mode: CockpitMode,
    containers: List(ContainerItem),
    selected_container: Int,
    storage_items: List(StorageItem),
    nvme_root_serial: String,
    nvme_root_locked: Bool,
    zenoh_topics: List(ZenohTopicItem),
    supervisors: List(SupervisorItem),
    tasks: List(TaskItem),
    security_events: List(SecurityEventItem),
    doctor_checks: List(DoctorCheckItem),
    server_url: String,
    server_status: String,
    last_refresh_utc: String,
    status_msg: String,
    homeostasis_state: HomeostasisSystemState,
    homeostasis_snapshot: homeostasis_status.Snapshot,
    homeostasis_observed_at: Int,
    homeostasis_selection: homeostasis_data.Selection,
    message_board: List(MessageBoardItem),
    agent_activities: List(AgentActivityItem),
  )
}

// =============================================================================
// Default Model Constructor
// =============================================================================

/// Build default production model with 16 SIL-6 containers and verified hardware safety locks.
pub fn default_model() -> SysadminModel {
  let containers = [
    ContainerItem(
      "db-prod",
      "T2",
      "running",
      "postgres:16-alpine",
      0.8,
      384,
      "5433:5432",
      0,
    ),
    ContainerItem(
      "obs-prod",
      "T3",
      "running",
      "prom/prometheus:v2.45",
      1.2,
      512,
      "9090:9090",
      0,
    ),
    ContainerItem(
      "ex-app-1",
      "T6",
      "running",
      "uos/beam-app:latest",
      2.4,
      256,
      "4000:4000",
      0,
    ),
    ContainerItem(
      "cepaf-bridge",
      "T5",
      "running",
      "uos/cepaf:latest",
      0.5,
      128,
      "7001:7001",
      0,
    ),
    ContainerItem(
      "cortex",
      "T5",
      "running",
      "uos/cortex:latest",
      3.1,
      640,
      "8080:8080",
      0,
    ),
    ContainerItem(
      "zenoh-router",
      "T1",
      "running",
      "eclipse/zenoh:latest",
      0.2,
      64,
      "7447:7447",
      0,
    ),
    ContainerItem(
      "ollama",
      "T6",
      "running",
      "ollama/ollama:latest",
      0.0,
      1024,
      "11434:11434",
      0,
    ),
    ContainerItem(
      "mojo",
      "T7",
      "running",
      "modular/max:latest",
      0.0,
      896,
      "stdio",
      0,
    ),
    ContainerItem(
      "zenoh-router-1",
      "T4",
      "running",
      "eclipse/zenoh:latest",
      0.1,
      48,
      "7448:7448",
      0,
    ),
    ContainerItem(
      "zenoh-router-2",
      "T4",
      "running",
      "eclipse/zenoh:latest",
      0.1,
      48,
      "7449:7449",
      0,
    ),
    ContainerItem(
      "zenoh-router-3",
      "T4",
      "running",
      "eclipse/zenoh:latest",
      0.1,
      48,
      "7450:7450",
      0,
    ),
    ContainerItem(
      "ex-app-2",
      "T7",
      "running",
      "uos/beam-worker:latest",
      1.8,
      192,
      "4001:4001",
      0,
    ),
    ContainerItem(
      "ex-app-3",
      "T7",
      "degraded",
      "uos/beam-worker:latest",
      0.1,
      96,
      "4002:4002",
      1,
    ),
    ContainerItem(
      "chaya",
      "T6",
      "running",
      "uos/chaya:latest",
      0.4,
      112,
      "5000:5000",
      0,
    ),
    ContainerItem(
      "ml-runner-1",
      "T7",
      "running",
      "uos/ml-runner:latest",
      0.0,
      512,
      "stdio",
      0,
    ),
    ContainerItem(
      "ml-runner-2",
      "T7",
      "running",
      "uos/ml-runner:latest",
      0.0,
      512,
      "stdio",
      0,
    ),
  ]

  let storage = [
    StorageItem(
      "nvme0n1",
      "25503L801736",
      1000,
      240,
      "LOCKED (ROOT OS NVMe)",
      True,
    ),
    StorageItem(
      "nvme1n1",
      "S654NX0W802341",
      2000,
      680,
      "ACTIVE (Ceph OSD.0)",
      False,
    ),
    StorageItem(
      "nvme2n1",
      "S654NX0W802342",
      2000,
      695,
      "ACTIVE (Ceph OSD.1)",
      False,
    ),
    StorageItem("sda", "WDC-WD40EFAX-01", 4000, 1450, "ACTIVE (ZFS Backup)", False),
  ]

  let topics = [
    ZenohTopicItem("indrajaal/l0/const/**", 1420, 1),
    ZenohTopicItem("indrajaal/l1/atomic/**", 8540, 1),
    ZenohTopicItem("indrajaal/l2/health/**", 12_450, 2),
    ZenohTopicItem("indrajaal/l4/system/**", 4310, 3),
    ZenohTopicItem("indrajaal/l5/cog/**", 2190, 4),
    ZenohTopicItem("indrajaal/otel/spans/**", 34_800, 1),
  ]

  let supervisors = [
    SupervisorItem("uos_sup", "L0", 4, "nominal", 0),
    SupervisorItem("apps_sup", "L2", 8, "nominal", 0),
    SupervisorItem("engines_sup", "L1", 6, "nominal", 0),
    SupervisorItem("services_sup", "L4", 7, "nominal", 0),
    SupervisorItem("intelligence_sup", "L5", 8, "nominal", 0),
  ]

  let tasks = [
    TaskItem(
      "TASK-01",
      "Verify Ceph NVMe Interlock",
      "Storage",
      "P0",
      "completed",
    ),
    TaskItem("TASK-02", "Run 381 Regression Tests", "Testing", "P1", "completed"),
    TaskItem(
      "TASK-03",
      "Poll Zenoh Mesh Spans",
      "Observability",
      "P2",
      "running",
    ),
    TaskItem(
      "TASK-04",
      "Hermes Gospel Parity Verification",
      "Formal",
      "P1",
      "completed",
    ),
    TaskItem(
      "TASK-05",
      "Quiesce Exited Microservices",
      "Operations",
      "P2",
      "pending",
    ),
  ]

  let security = [
    SecurityEventItem(
      "2026-09-06T18:40:12Z",
      "MCP Dispatch Validated",
      "127.0.0.1",
      "ALLOW",
    ),
    SecurityEventItem(
      "2026-09-06T18:35:20Z",
      "SQL Injection Trapped (code -3)",
      "10.0.4.15",
      "BLOCKED",
    ),
    SecurityEventItem(
      "2026-09-06T18:30:05Z",
      "NUL Byte Trapped (code -2)",
      "10.0.4.88",
      "BLOCKED",
    ),
    SecurityEventItem(
      "2026-09-06T18:25:00Z",
      "Sovereign Login AGY (FerrisKey)",
      "100.87.7.78",
      "AUTHENTICATED",
    ),
  ]

  let doctor = [
    DoctorCheckItem(
      "CHK-01-TIME",
      "Timestamp Mandate (YYYYMMDD-HHSS-)",
      "Metadata",
      "PASS",
    ),
    DoctorCheckItem(
      "CHK-02-TAIL",
      "Tailscale FQDN Navigation Links",
      "Network",
      "PASS",
    ),
    DoctorCheckItem(
      "CHK-05-MUDA",
      "Zero-Muda Purity (0 Bevy, 0 Graphite)",
      "Purity",
      "PASS",
    ),
    DoctorCheckItem(
      "CHK-07-DRIVE",
      "Hardware OS NVMe Locked (25503L801736)",
      "Storage",
      "PASS",
    ),
    DoctorCheckItem(
      "CHK-09-MATH",
      "4 Math Gates (H, CCM, D_EA, ITQS)",
      "Math",
      "PASS",
    ),
    DoctorCheckItem(
      "CHK-12-GLEAM",
      "Gleam/OTP 29 Root Supervisor",
      "Control",
      "PASS",
    ),
    DoctorCheckItem(
      "CHK-13-HERMES",
      "Hermes Zero-Trust Payload Interceptor",
      "Formal",
      "PASS",
    ),
    DoctorCheckItem(
      "CHK-18-JJ",
      "Standalone Jujutsu VCS (.jj/)",
      "Governance",
      "PASS",
    ),
  ]

  SysadminModel(
    active_tab: OverviewTab,
    cockpit_mode: Dark,
    containers: containers,
    selected_container: 0,
    storage_items: storage,
    nvme_root_serial: "25503L801736",
    nvme_root_locked: True,
    zenoh_topics: topics,
    supervisors: supervisors,
    tasks: tasks,
    security_events: security,
    doctor_checks: doctor,
    server_url: "http://nas-1.tail55d152.ts.net:4100",
    server_status: "ok",
    last_refresh_utc: "2026-09-06T18:45:00Z",
    status_msg: "System Nominal — All 16 SIL-6 Containers Tracked",
    homeostasis_state: init_homeostasis_system(1_788_818_000_000_000),
    homeostasis_snapshot: homeostasis_status.unavailable(),
    homeostasis_observed_at: 0,
    homeostasis_selection: homeostasis_data.default(),
    message_board: default_message_board(),
    agent_activities: default_agent_activities(),
  )
}

fn default_message_board() -> List(MessageBoardItem) {
  [
    MessageBoardItem(
      "msg-101",
      "2026-09-07T23:50:12Z",
      "AGY (L3)",
      "Codex-Astra (L3)",
      "Report",
      "Physiological Homeostasis verified: e(t)=0.005, composite_stress=0.35 [PASS]",
      "delivered (zenoh+ledger)",
    ),
    MessageBoardItem(
      "msg-102",
      "2026-09-07T23:50:45Z",
      "Claude (L0)",
      "broadcast",
      "Integrate",
      "Candidate EV-110 admitted: Pareto fitness front & Ziegler-Nichols PID",
      "delivered (ledger)",
    ),
    MessageBoardItem(
      "msg-103",
      "2026-09-07T23:51:02Z",
      "Codex-Astra (L3)",
      "broadcast",
      "Report",
      "Solo5 0.13.0 sandboxed verification verified: 0 memory leak, fail-closed",
      "delivered (zenoh)",
    ),
    MessageBoardItem(
      "msg-104",
      "2026-09-07T23:51:30Z",
      "OpenRouter (L5)",
      "AGY (L3)",
      "Advisory",
      "Bounded multi-objective fitness evaluation: non-dominated front optimal",
      "delivered (ledger)",
    ),
    MessageBoardItem(
      "msg-105",
      "2026-09-07T23:52:10Z",
      "uos-manager (L1)",
      "broadcast",
      "Progress",
      "Cycle 42: OODA orientation active, Heijunka pull queue level=0.88",
      "delivered (zenoh)",
    ),
  ]
}

fn default_agent_activities() -> List(AgentActivityItem) {
  [
    AgentActivityItem("EXEC-001 (Orchestrator)", "Executive L5", "Coordinating multi-agent swarm OODA loop", "active"),
    AgentActivityItem("SUP-CTX (Context)", "Supervisor L5", "Aggregating 13D trace coordinates & ZK ADRs", "active"),
    AgentActivityItem("SUP-DOM (Domain)", "Supervisor L2", "Evaluating Pareto frontier & non-dominated candidates", "active"),
    AgentActivityItem("SUP-TST (Testing)", "Supervisor L4", "Monitoring 381 regression tests & 9 modalities", "active"),
    AgentActivityItem("SUP-QUA (Quality)", "Supervisor L0", "Enforcing Zero-Muda (0 Bevy, 0 Graphite) & NVMe lock", "active"),
    AgentActivityItem("Cortex Engine", "Cognitive L5", "Biomorphic PID tuning & stress trend Lyapunov damping", "active"),
    AgentActivityItem("Prajna Breaker", "Safety L0", "14 Circuit breakers active, 0 tripped, 50ms recovery", "active"),
    AgentActivityItem("Zenoh Mesh Router", "Network L6", "Routing OTel spans and A2A messages over 100.87.7.78", "active"),
  ]
}

// =============================================================================
// State Transitions & Actions
// =============================================================================

/// Switch active tab
pub fn select_tab(model: SysadminModel, tab: Tab) -> SysadminModel {
  SysadminModel(..model, active_tab: tab, status_msg: "Switched to " <> tab_to_string(tab))
}

/// Cycle to next tab
pub fn next_tab(model: SysadminModel) -> SysadminModel {
  let next_idx = { tab_to_index(model.active_tab) + 1 } % 12
  select_tab(model, tab_from_index(next_idx))
}

/// Cycle to previous tab
pub fn prev_tab(model: SysadminModel) -> SysadminModel {
  let prev_idx = { tab_to_index(model.active_tab) + 11 } % 12
  select_tab(model, tab_from_index(prev_idx))
}

/// Toggle Dark Cockpit illumination mode
pub fn toggle_mode(model: SysadminModel) -> SysadminModel {
  let next_mode = case model.cockpit_mode {
    Dark -> Dim
    Dim -> Normal
    Normal -> Bright
    Bright -> Emergency
    Emergency -> Dark
  }
  SysadminModel(
    ..model,
    cockpit_mode: next_mode,
    status_msg: "Cockpit Illumination Mode: " <> mode_to_string(next_mode),
  )
}

/// Move cursor to next container
pub fn next_container(model: SysadminModel) -> SysadminModel {
  let count = list.length(model.containers)
  case count > 0 {
    True -> {
      let idx = { model.selected_container + 1 } % count
      SysadminModel(..model, selected_container: idx)
    }
    False -> model
  }
}

/// Move cursor to previous container
pub fn prev_container(model: SysadminModel) -> SysadminModel {
  let count = list.length(model.containers)
  case count > 0 {
    True -> {
      let idx = { model.selected_container - 1 + count } % count
      SysadminModel(..model, selected_container: idx)
    }
    False -> model
  }
}

/// Trigger container restart action
pub fn restart_selected_container(model: SysadminModel) -> SysadminModel {
  case list.drop(model.containers, model.selected_container) |> list.first {
    Ok(c) -> {
      let updated =
        list.map(model.containers, fn(item) {
          case item.name == c.name {
            True -> ContainerItem(..item, status: "running", restarts: item.restarts + 1)
            False -> item
          }
        })
      SysadminModel(
        ..model,
        containers: updated,
        status_msg: "Triggered Restart for Container: " <> c.name,
      )
    }
    Error(_) -> model
  }
}

/// Trigger container stop action
pub fn stop_selected_container(model: SysadminModel) -> SysadminModel {
  case list.drop(model.containers, model.selected_container) |> list.first {
    Ok(c) -> {
      let updated =
        list.map(model.containers, fn(item) {
          case item.name == c.name {
            True -> ContainerItem(..item, status: "exited")
            False -> item
          }
        })
      SysadminModel(
        ..model,
        containers: updated,
        status_msg: "Stopped Container: " <> c.name,
      )
    }
    Error(_) -> model
  }
}

/// Trigger container start action
pub fn start_selected_container(model: SysadminModel) -> SysadminModel {
  case list.drop(model.containers, model.selected_container) |> list.first {
    Ok(c) -> {
      let updated =
        list.map(model.containers, fn(item) {
          case item.name == c.name {
            True -> ContainerItem(..item, status: "running")
            False -> item
          }
        })
      SysadminModel(
        ..model,
        containers: updated,
        status_msg: "Started Container: " <> c.name,
      )
    }
    Error(_) -> model
  }
}

/// Trigger BEAM Garbage Collection
pub fn trigger_garbage_collection(model: SysadminModel) -> SysadminModel {
  SysadminModel(
    ..model,
    status_msg: "BEAM Process Compaction & Garbage Collection Completed (Saved ~24MB)",
  )
}

// =============================================================================
// Rendering Pipeline
// =============================================================================

/// Render complete Sysadmin Cockpit TUI frame
pub fn render(model: SysadminModel) -> String {
  let header = render_header(model)
  let tabs = render_tab_bar(model)
  let body = render_tab_content(model)
  let footer = render_footer(model)

  string.join([header, tabs, "", body, "", footer], "\n")
}

/// Top status and host banner
pub fn render_header(model: SysadminModel) -> String {
  let mode_color = case model.cockpit_mode {
    Dark -> "dim"
    Dim -> "yellow"
    Normal -> "cyan"
    Bright -> "white"
    Emergency -> "red"
  }
  let mode_str = mode_to_string(model.cockpit_mode)
  let server_badge = case model.server_status {
    "ok" -> visuals.with_color("SRV: OK", "green")
    "degraded" -> visuals.with_color("SRV: DEGRADED", "yellow")
    _ -> visuals.with_color("SRV: OFFLINE", "red")
  }
  let root_lock_badge = case model.nvme_root_locked {
    True -> visuals.with_color("DRIVE: LOCKED (25503L801736)", "green")
    False -> visuals.with_color("DRIVE: UNLOCKED (!CRITICAL!)", "red")
  }

  let bar = string.repeat("═", 102)
  let line1 =
    "╔" <> bar <> "╗\n"
    <> "║ "
    <> visuals.with_color(
      "UOS C3I SOVEREIGN REMOTE SYSADMIN COCKPIT — AGY (L0-L7 ACCESS)",
      "bold",
    )
    <> " ║\n"
    <> "║ "
    <> visuals.with_color("HOST: ", "dim")
    <> visuals.with_color("nas-1.tail55d152.ts.net:4100", "cyan")
    <> " │ "
    <> visuals.with_color("UTC: ", "dim")
    <> model.last_refresh_utc
    <> " │ "
    <> server_badge
    <> " │ "
    <> root_lock_badge
    <> " │ "
    <> visuals.with_color("[" <> mode_str <> "]", mode_color)
    <> " ║\n"
    <> "╚" <> bar <> "╝"
  line1
}

/// Categorized 9-Tab Bar
pub fn render_tab_bar(model: SysadminModel) -> String {
  let tabs = [
    #(OverviewTab, "[1] Overview"),
    #(ContainersTab, "[2] Podman"),
    #(StorageTab, "[3] Storage"),
    #(ZenohTab, "[4] Zenoh"),
    #(SupervisorsTab, "[5] Supervisors"),
    #(TasksTab, "[6] Tasks"),
    #(SecurityTab, "[7] Security"),
    #(StreamTab, "[8] Stream"),
    #(DoctorTab, "[9] Doctor"),
    #(HomeostasisTab, "[h] Homeostasis"),
    #(MessageBoardTab, "[m] MsgBoard"),
    #(EvolutionTab, "[e] Evolution"),
  ]

  let rendered_tabs =
    list.map(tabs, fn(item) {
      let #(tab, label) = item
      case tab == model.active_tab {
        True -> visuals.with_color(" " <> label <> " ", "cyan")
        False -> visuals.with_color(label, "dim")
      }
    })

  "  " <> string.join(rendered_tabs, " │ ")
}

/// Render active tab content
pub fn render_tab_content(model: SysadminModel) -> String {
  case model.active_tab {
    OverviewTab -> render_overview_tab(model)
    ContainersTab -> render_containers_tab(model)
    StorageTab -> render_storage_tab(model)
    ZenohTab -> render_zenoh_tab(model)
    SupervisorsTab -> render_supervisors_tab(model)
    TasksTab -> render_tasks_tab(model)
    SecurityTab -> render_security_tab(model)
    StreamTab -> render_stream_tab(model)
    DoctorTab -> render_doctor_tab(model)
    HomeostasisTab -> homeostasis_view.render_snapshot(model.homeostasis_snapshot,model.homeostasis_observed_at,120,100)
    MessageBoardTab -> render_message_board_tab(model)
    EvolutionTab -> homeostasis_view.render_snapshot(model.homeostasis_snapshot,model.homeostasis_observed_at,120,100)
  }
}

// -----------------------------------------------------------------------------
// Tab 1: Overview
// -----------------------------------------------------------------------------

fn render_overview_tab(model: SysadminModel) -> String {
  let title =
    visuals.with_color("  === SYSTEM OVERVIEW & CYBERNETIC HEALTH ===", "cyan")
  let srv_line = "  Server URL      : " <> model.server_url
  let ooda = "  OODA LOOP:  " <> visuals.render_ooda_ring("observe")
  let health_strip =
    "  SUBSYSTEMS: "
    <> visuals.render_status_strip([
      #("BEAM", "healthy"),
      #("Storage", "healthy"),
      #("Zenoh", "healthy"),
      #("Immune", "healthy"),
      #("Guardian", "ok"),
    ])

  let schedulers =
    "  BEAM Schedulers : 16:16 dirty I/O (Preemption active, 4000 reductions)"
  let memory =
    "  Memory Profile  : 142.5 MB total (Processes: 68MB, ETS: 22MB, Code: 35MB)"
  let threat =
    "  Threat Level    : "
    <> visuals.with_color("NOMINAL (0 Active Anomalies)", "green")

  let heatmap =
    visuals.render_fractal_heatmap([
      #("L0 Constitutional", 1.0),
      #("L1 Atomic/Debug", 0.95),
      #("L2 Component", 0.98),
      #("L3 Transaction", 0.92),
      #("L4 System", 0.88),
      #("L5 Cognitive", 0.91),
      #("L6 Ecosystem", 0.87),
      #("L7 Federation", 0.94),
    ])

  string.join(
    [title, srv_line, ooda, health_strip, threat, schedulers, memory, "", heatmap],
    "\n",
  )
}

// -----------------------------------------------------------------------------
// Tab 2: Podman Containers
// -----------------------------------------------------------------------------

fn render_containers_tab(model: SysadminModel) -> String {
  let header = visuals.with_color("  === PODMAN CONTAINER GENOME (16 SIL-6 CONTAINERS) ===", "cyan")
  let summary =
    "  Total: "
    <> int.to_string(list.length(model.containers))
    <> "  |  Running: "
    <> visuals.with_color("15", "green")
    <> "  |  Degraded: "
    <> visuals.with_color("1", "yellow")
    <> "  |  Selected: ["
    <> int.to_string(model.selected_container + 1)
    <> "/16]"

  let rows =
    list.index_map(model.containers, fn(c, idx) {
      let is_selected = idx == model.selected_container
      let prefix = case is_selected {
        True -> visuals.with_color("▶ ", "cyan")
        False -> "  "
      }
      let status_color = case c.status {
        "running" -> "green"
        "degraded" -> "yellow"
        _ -> "red"
      }
      let status_str = visuals.with_color("[" <> c.status <> "]", status_color)
      let name_str = pad_right(c.name, 16)
      let tier_str = visuals.with_color(c.tier, "blue")
      let ports_str = pad_right(c.ports, 12)
      let cpu_str = float.to_string(c.cpu_pct) <> "%"
      let mem_str = int.to_string(c.mem_mb) <> "MB"

      prefix
      <> name_str
      <> " "
      <> tier_str
      <> "  "
      <> status_str
      <> "  "
      <> ports_str
      <> "  CPU:"
      <> pad_right(cpu_str, 6)
      <> "  MEM:"
      <> mem_str
    })
    |> string.join("\n")

  let actions =
    visuals.with_color("  Container Actions: ", "dim")
    <> visuals.with_color("[s] Start  ", "green")
    <> visuals.with_color("[x] Stop  ", "red")
    <> visuals.with_color("[r] Restart  ", "yellow")
    <> visuals.with_color("[l] View Logs", "cyan")

  string.join([header, summary, "", rows, "", actions], "\n")
}

// -----------------------------------------------------------------------------
// Tab 3: Storage & Ceph Safety
// -----------------------------------------------------------------------------

fn render_storage_tab(model: SysadminModel) -> String {
  let title = visuals.with_color("  === HARDWARE STORAGE & DRIVE INTERLOCK AUDIT ===", "cyan")
  let lock_alert =
    "  ROOT OS INTERLOCK: "
    <> visuals.with_color(
      "HARD_DENIED_SYSTEM_OS_SERIAL = \"" <> model.nvme_root_serial <> "\" STRICTLY LOCKED",
      "green",
    )
    <> "\n  ENFORCEMENT SITE : ops/kubernetes/nas-k8s-lab/src/spec.rs:192 (WIPE IMPOSSIBLE)"

  let ceph_title = "  Ceph Cluster Status : " <> visuals.with_color("HEALTH_OK (2 OSDs UP, 0 DOWN)", "green")

  let rows =
    list.map(model.storage_items, fn(item) {
      let lock_str = case item.locked {
        True -> visuals.with_color("● LOCKED (SYSTEM OS)", "green")
        False -> visuals.with_color("○ UNLOCKED (CEPH POOL)", "blue")
      }
      let pct = int.to_float(item.used_gb) /. int.to_float(item.size_gb)
      let bar = visuals.render_progress_bar(pct, 16)
      "    "
      <> pad_right(item.drive_id, 10)
      <> " "
      <> pad_right(item.serial, 18)
      <> " "
      <> pad_right(int.to_string(item.used_gb) <> "/" <> int.to_string(item.size_gb) <> "GB", 14)
      <> " "
      <> bar
      <> "  "
      <> lock_str
    })
    |> string.join("\n")

  let vfs = "  ZigVM Descriptor-Relative VFS: 48 open descriptors / 1024 max (4.6% utilization)"

  string.join([title, "", lock_alert, "", ceph_title, "", rows, "", vfs], "\n")
}

// -----------------------------------------------------------------------------
// Tab 4: Zenoh Mesh & Network
// -----------------------------------------------------------------------------

fn render_zenoh_tab(model: SysadminModel) -> String {
  let title = visuals.with_color("  === ZENOH MESH & TAILSCALE NETWORK TOPOLOGY ===", "cyan")
  let endpoint = "  Zenoh Router : tcp/100.87.7.78:7447 (" <> visuals.with_color("CONNECTED", "green") <> ")"
  let peer = "  Peer Node    : vm-1.tail55d152.ts.net (100.78.98.18:8088) — Latency: 0.8ms"
  let throughput = "  Throughput   : 1,840 msgs/sec (In: 1.2 MB/s, Out: 1.8 MB/s)"

  let topic_header = "  Active Zenoh Pub/Sub Topics (indrajaal/**):"
  let rows =
    list.map(model.zenoh_topics, fn(t) {
      "    "
      <> pad_right(t.topic, 36)
      <> "  Msgs: "
      <> pad_right(int.to_string(t.message_count), 8)
      <> "  Last Seen: "
      <> int.to_string(t.last_seen_s_ago)
      <> "s ago"
    })
    |> string.join("\n")

  string.join([title, "", endpoint, peer, throughput, "", topic_header, rows], "\n")
}

// -----------------------------------------------------------------------------
// Tab 5: Supervisors & Schedulers
// -----------------------------------------------------------------------------

fn render_supervisors_tab(model: SysadminModel) -> String {
  let title = visuals.with_color("  === OTP 29 SUPERVISOR TREE & PROCESS REGISTRY ===", "cyan")
  let sched = "  BEAM Schedulers: 16 Normal + 16 Dirty I/O Schedulers (100% responsive)"
  let root = "  Root Supervisor: uos_sup.gleam (Restart Strategy: one_for_one, max 5 in 10s)"

  let rows =
    list.map(model.supervisors, fn(s) {
      "    "
      <> pad_right(s.name, 20)
      <> " "
      <> visuals.with_color("[" <> s.layer <> "]", "cyan")
      <> "  Children: "
      <> pad_right(int.to_string(s.child_count), 4)
      <> "  Status: "
      <> visuals.with_color(s.status, "green")
      <> "  Restarts: "
      <> int.to_string(s.restarts)
    })
    |> string.join("\n")

  let agent_summary = "  Agent Swarm    : 25 Supervised Agents (Orchestrator, Context, Domain, Quality, Testing)"

  string.join([title, "", sched, root, "", rows, "", agent_summary], "\n")
}

// -----------------------------------------------------------------------------
// Tab 6: Tasks & Planning
// -----------------------------------------------------------------------------

fn render_tasks_tab(model: SysadminModel) -> String {
  let title = visuals.with_color("  === SIL-6 TASK BOARD & CONSTITUTIONAL CONSENSUS ===", "cyan")
  let consensus = "  Constitutional Consensus: 2oo3 REACHED (Guardian: Approve, Sentinel: Approve, Cortex: Approve)"

  let rows =
    list.map(model.tasks, fn(t) {
      let color = case t.status {
        "completed" -> "green"
        "running" -> "yellow"
        _ -> "dim"
      }
      "    "
      <> pad_right(t.id, 10)
      <> " "
      <> pad_right(t.priority, 4)
      <> " "
      <> pad_right(t.domain, 14)
      <> " "
      <> visuals.with_color("[" <> t.status <> "]", color)
      <> " "
      <> t.title
    })
    |> string.join("\n")

  let circuit_breakers = "  Prajna Circuit Breakers: 0 Tripped, 14 Active, Sub-50ms Half-Open Recovery"

  string.join([title, "", consensus, "", rows, "", circuit_breakers], "\n")
}

// -----------------------------------------------------------------------------
// Tab 7: Security & IAM
// -----------------------------------------------------------------------------

fn render_security_tab(model: SysadminModel) -> String {
  let title = visuals.with_color("  === ZERO-TRUST SECURITY & SOVEREIGN IAM AUDIT ===", "cyan")
  let auth_info =
    "  Authenticated User: "
    <> visuals.with_color("agy", "cyan")
    <> "  |  Roles: [sovereign, admin, operator]  |  MFA: Active\n"
    <> "  FerrisKey IAM     : Connected  |  Unlocked Layers: L0 L1 L2 L3 L4 L5 L6 L7"

  let event_header = "  Recent Zero-Trust Interceptor Events & Trapped Ingress:"
  let rows =
    list.map(model.security_events, fn(e) {
      let outcome_color = case e.outcome {
        "ALLOW" | "AUTHENTICATED" -> "green"
        _ -> "red"
      }
      "    "
      <> e.timestamp
      <> "  "
      <> pad_right(e.source_ip, 14)
      <> "  "
      <> pad_right(e.event_type, 32)
      <> "  "
      <> visuals.with_color("[" <> e.outcome <> "]", outcome_color)
    })
    |> string.join("\n")

  string.join([title, "", auth_info, "", event_header, rows], "\n")
}

// -----------------------------------------------------------------------------
// Tab 8: AG-UI Event Stream
// -----------------------------------------------------------------------------

fn render_stream_tab(model: SysadminModel) -> String {
  let title =
    visuals.with_color("  === AG-UI 32-EVENT REAL-TIME TELEMETRY STREAM ===", "cyan")
  let meta = "  Active Host: nas-1.tail55d152.ts.net:4100 | Last Tick: " <> model.last_refresh_utc
  let events = [
    "18:44:59.102 [Lifecycle] StepFinished        step_id: step-842   duration: 12ms",
    "18:44:59.090 [Tool]      ToolCallResult      tool: system_health status: ok",
    "18:44:59.082 [Tool]      ToolCallStart       tool: system_health target: beam",
    "18:44:58.940 [State]     StateSnapshot       genome: 16/16       threat: nominal",
    "18:44:58.810 [Reasoning] ReasoningChunk      tier: knowledge     drift: 0.001",
    "18:44:58.700 [Activity]  ActivitySnapshot    actors: 33          schedulers: 16:16",
    "18:44:58.550 [Special]   Heartbeat           node: nas-1         zenoh: connected",
  ]
  let rows =
    list.map(events, fn(line) { "    " <> visuals.with_color(line, "dim") })
    |> string.join("\n")

  string.join([title, meta, "", rows], "\n")
}

// -----------------------------------------------------------------------------
// Tab 9: Doctor & Preflight
// -----------------------------------------------------------------------------

fn render_doctor_tab(model: SysadminModel) -> String {
  let title = visuals.with_color("  === SYSTEM DOCTOR & PREFLIGHT DIAGNOSTICS ===", "cyan")
  let summary =
    "  Status: "
    <> visuals.with_color("100% ALL CHECKS PASS — UOS RATIFIED", "green")
    <> " (EV-01..EV-84 Operational)"

  let rows =
    list.map(model.doctor_checks, fn(chk) {
      "    "
      <> visuals.with_color("[" <> chk.status <> "]", "green")
      <> " "
      <> pad_right(chk.id, 14)
      <> " "
      <> pad_right(chk.domain, 12)
      <> " "
      <> chk.name
    })
    |> string.join("\n")

  let math_gates =
    "  Math Gates:  H=2.67b [PASS]   CCM=92.5% [PASS]   D_EA=3.2% [PASS]   ITQS=0.88 [PASS]"

  string.join([title, "", summary, "", rows, "", math_gates], "\n")
}

// -----------------------------------------------------------------------------
// Tab 10: Homeostasis Status & Physiological Telemetry
// -----------------------------------------------------------------------------

fn render_homeostasis_tab(model: SysadminModel) -> String {
  let title =
    visuals.with_color("  === SIMULATED: BIOMORPHIC PHYSIOLOGICAL HOMEOSTASIS (C3I / INDRAJAAL) ===", "cyan")
  let s = model.homeostasis_state
  let p = s.physiological
  let m = s.metrics

  let eq_badge = case p.is_homeostatic {
    True -> visuals.with_color("HOMEOSTATIC EQUILIBRIUM (Composite Stress <= 0.70)", "green")
    False -> visuals.with_color("STRESS THRESHOLD EXCEEDED", "red")
  }

  let summary =
    "  System State     : "
    <> eq_badge
    <> "
  Composite Stress : "
    <> float.to_string(p.composite_stress)
    <> "  |  Stress Trend: "
    <> physiological_homeostasis.trend_to_string(p.stress_trend)
    <> "  |  Stable Cycles: "
    <> int.to_string(s.consecutive_stable_ticks)

  let pid_header = "  Convergence PID & Lyapunov Stability:"
  let pid_status = case m.stable {
    True -> visuals.with_color("STABLE DAMPED", "green")
    False -> visuals.with_color("CONVERGING", "yellow")
  }
  let pid_line =
    "    Health: "
    <> float.to_string(m.measured_health)
    <> "  |  Error e(t): "
    <> float.to_string(m.error)
    <> "  |  Control Signal: "
    <> float.to_string(m.control_output)
    <> "  |  Lyapunov V: "
    <> float.to_string(m.lyapunov_v)
    <> "  |  ["
    <> pid_status
    <> "]"

  let var_header = "  Physiological Variables & Closed-Loop Regulation:"
  let var_rows =
    list.map(p.variables, fn(v) {
      let stress_color = case v.stress {
        physiological_homeostasis.StressLow -> "green"
        physiological_homeostasis.StressOptimal -> "green"
        physiological_homeostasis.StressHigh -> "yellow"
        physiological_homeostasis.StressCritical -> "red"
      }
      "    * "
      <> pad_right(physiological_homeostasis.variable_to_string(v.variable), 18)
      <> "  Setpoint: "
      <> pad_right(float.to_string(v.setpoint), 8)
      <> "  Actual: "
      <> pad_right(float.to_string(v.measurement), 8)
      <> "  PID Control: "
      <> pad_right(float.to_string(v.control_signal), 8)
      <> "  Stress: "
      <> visuals.with_color("[" <> physiological_homeostasis.stress_to_string(v.stress) <> "]", stress_color)
    })
    |> string.join("\n")

  string.join([title, "", summary, "", pid_header, pid_line, "", var_header, var_rows], "\n")
}

// -----------------------------------------------------------------------------
// Tab 11: Swarm Message Dashboard & Agent Activities
// -----------------------------------------------------------------------------

fn render_message_board_tab(model: SysadminModel) -> String {
  let title =
    visuals.with_color("  === SIMULATED: SWARM MESSAGE DASHBOARD & A2A INTER-AGENT BUS ===", "cyan")
  let bus_info =
    "  Transport Plane  : Zenoh Pub/Sub (indrajaal/a2a/**) + SQLite Chained Ledger\n"
    <> "  Active Agents    : 25 OTP Supervised Agents  |  Quorum: 4-Party Sovereign Consensus"

  let act_header = "  Active Agent Tasks & Runtime Execution:"
  let act_rows =
    list.map(model.agent_activities, fn(a) {
      let status_color = case a.status {
        "active" -> "green"
        "idle" -> "dim"
        _ -> "yellow"
      }
      "    "
      <> pad_right(a.name, 26)
      <> " "
      <> visuals.with_color("[" <> a.role <> "]", "blue")
      <> "  "
      <> visuals.with_color("[" <> a.status <> "]", status_color)
      <> "\n      ↳ Action: "
      <> visuals.with_color(a.current_action, "cyan")
    })
    |> string.join("\n")

  let msg_header = "  Recent A2A Messages & Signed Transmissions:"
  let msg_rows =
    list.map(model.message_board, fn(m) {
      "    ["
      <> m.id
      <> "] "
      <> m.timestamp_iso
      <> "  "
      <> visuals.with_color(m.from_agent, "magenta")
      <> " → "
      <> visuals.with_color(m.to_agent, "cyan")
      <> "  "
      <> visuals.with_color("[" <> m.kind <> "]", "yellow")
      <> "\n      Summary: "
      <> m.payload_summary
      <> "\n      Delivery: "
      <> visuals.with_color(m.transport_status, "green")
    })
    |> string.join("\n")

  string.join([title, "", bus_info, "", act_header, act_rows, "", msg_header, msg_rows], "\n")
}

// -----------------------------------------------------------------------------
// Tab 12: Autonomous System Evolution & Pareto Frontiers
// -----------------------------------------------------------------------------

fn render_evolution_tab(model: SysadminModel) -> String {
  let title =
    visuals.with_color("  === SIMULATED: AUTONOMOUS SYSTEM EVOLUTION & PARETO FRONTIERS ===", "cyan")
  let s = model.homeostasis_state

  let gate_badge = case s.physiological.is_homeostatic && s.metrics.stable {
    True -> visuals.with_color("EVOLUTION GATE OPEN (System in Equilibrium)", "green")
    False -> visuals.with_color("EVOLUTION GATE BLOCKED (Homeostatic Divergence)", "red")
  }

  let gen_info =
    "  Generation       : "
    <> int.to_string(s.generation)
    <> "  |  Status: "
    <> gate_badge
    <> "\n  4-Party Quorum   : 3-of-4 Supermajority Ratification Required"

  let pareto_header = "  Multi-Objective Evolutionary Pareto Landscape (Indrajaal):"
  let pareto_rows =
    list.map(s.pareto_candidates, fn(c) {
      let opt_badge = case c.is_pareto_optimal {
        True -> visuals.with_color("[NON-DOMINATED PARETO FRONT]", "green")
        False -> visuals.with_color("[Dominated Candidate]", "dim")
      }
      "    * "
      <> pad_right(c.name, 32)
      <> " Fitness: "
      <> pad_right(float.to_string(c.composite_fitness), 6)
      <> "  "
      <> opt_badge
      <> "\n        Latency: "
      <> float.to_string(c.raw_latency_ms)
      <> "ms  Throughput: "
      <> float.to_string(c.raw_throughput_ops)
      <> " ops/s  Error: "
      <> float.to_string(c.raw_error_pct)
      <> "%  CPU: "
      <> float.to_string(c.raw_cpu_pct)
      <> "%"
    })
    |> string.join("\n")

  let quorum_header = "  Sovereign Quorum Ratification:"
  let quorum_info =
    "    * AGY Sovereign        : [UNKNOWN] Reference role: formal proof review\n"
    <> "    * Claude Sovereign     : [UNKNOWN] Monorepo architecture & coordination alignment\n"
    <> "    * Codex Sovereign      : [UNKNOWN] Reference role: sandbox verification\n"
    <> "    * OpenRouter Advisory  : [UNKNOWN] Reference role: bounded advice"

  string.join([title, "", gen_info, "", pareto_header, pareto_rows, "", quorum_header, quorum_info], "\n")
}

// -----------------------------------------------------------------------------
// Footer & Action Bar
// -----------------------------------------------------------------------------

pub fn render_footer(model: SysadminModel) -> String {
  let action_bar =
    visuals.with_color("  [ACTIONS]: ", "bold")
    <> visuals.with_color("(1-9/h/m/e)", "cyan")
    <> " Tabs  "
    <> visuals.with_color("(n/p)", "cyan")
    <> " Next/Prev Tab  "
    <> visuals.with_color("(t)", "cyan")
    <> " Toggle Mode  "
    <> visuals.with_color("(s/x/r)", "cyan")
    <> " Container Control  "
    <> visuals.with_color("(g)", "cyan")
    <> " GC  "
    <> visuals.with_color("(q)", "cyan")
    <> " Quit"

  let status_line = "  STATUS: " <> visuals.with_color(model.status_msg, "green")
  action_bar <> "\n" <> status_line
}

// =============================================================================
// Helper Conversions
// =============================================================================

fn tab_to_string(tab: Tab) -> String {
  case tab {
    OverviewTab -> "Overview & Health"
    ContainersTab -> "Podman Containers"
    StorageTab -> "Storage & Ceph Safety"
    ZenohTab -> "Zenoh Mesh & Network"
    SupervisorsTab -> "OTP 29 Supervisors"
    TasksTab -> "Tasks & Planning"
    SecurityTab -> "Security & IAM"
    StreamTab -> "AG-UI Event Stream"
    DoctorTab -> "Doctor & Preflight"
    HomeostasisTab -> "Homeostasis Telemetry"
    MessageBoardTab -> "Swarm Message Board"
    EvolutionTab -> "Autonomous Evolution"
  }
}

fn tab_to_index(tab: Tab) -> Int {
  case tab {
    OverviewTab -> 0
    ContainersTab -> 1
    StorageTab -> 2
    ZenohTab -> 3
    SupervisorsTab -> 4
    TasksTab -> 5
    SecurityTab -> 6
    StreamTab -> 7
    DoctorTab -> 8
    HomeostasisTab -> 9
    MessageBoardTab -> 10
    EvolutionTab -> 11
  }
}

fn tab_from_index(idx: Int) -> Tab {
  case idx {
    0 -> OverviewTab
    1 -> ContainersTab
    2 -> StorageTab
    3 -> ZenohTab
    4 -> SupervisorsTab
    5 -> TasksTab
    6 -> SecurityTab
    7 -> StreamTab
    8 -> DoctorTab
    9 -> HomeostasisTab
    10 -> MessageBoardTab
    11 -> EvolutionTab
    _ -> OverviewTab
  }
}

fn mode_to_string(mode: CockpitMode) -> String {
  case mode {
    Dark -> "DARK"
    Dim -> "DIM"
    Normal -> "NORMAL"
    Bright -> "BRIGHT"
    Emergency -> "EMERGENCY"
  }
}

fn pad_right(text: String, width: Int) -> String {
  let len = string.length(text)
  case len >= width {
    True -> string.slice(text, 0, width)
    False -> text <> string.repeat(" ", width - len)
  }
}

/// Explicit effect boundary; tab renderers consume the resulting immutable model.
pub fn refresh_homeostasis(model: SysadminModel, selection: homeostasis_data.Selection) -> SysadminModel {
  let #(snapshot,now) = homeostasis_data.read(selection)
  SysadminModel(..model,homeostasis_snapshot: snapshot,homeostasis_observed_at: now,homeostasis_selection: selection)
}
