//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/agents/cybernetic</module>
////   <fsharp-lineage>Cepaf.Agents.Cybernetic</fsharp-lineage></identity>
////   <fractal-topology><layer>L7_FEDERATION</layer></fractal-topology></c3i-module>

import cepaf_gleam/agents/briefing
import cepaf_gleam/agents/cortex
import cepaf_gleam/agents/leadership
import cepaf_gleam/agents/skill_loader
import cepaf_gleam/agents/workspace
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/list
import gleam/option.{type Option}
import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision

// =============================================================================
// Type Definitions — Autonomous Agents
// =============================================================================

pub type AgentLevel {
  Executive
  DomainSupervisor
  FunctionalSupervisor
  Worker
}

pub type ServiceRole {
  Cortex
  Prajna
  Smriti
  CEPAF
  Planning
  Chaya
  Guardian
  GenericWorker
}

pub type AgentStatus {
  Idle
  AgentActive(task: String)
  AgentBlocked(reason: String)
}

pub type AgentState {
  AgentState(
    id: String,
    name: String,
    level: AgentLevel,
    role: ServiceRole,
    domain: String,
    status: AgentStatus,
  )
}

pub type Message {
  UpdateStatus(AgentStatus)
  GetState(Subject(AgentState))
}

// =============================================================================
// Agent Registry (Executive L5/L6)
// =============================================================================

pub type AgentRegistry =
  Dict(String, Subject(Message))

pub fn monitor_hierarchy(registry: AgentRegistry) -> Nil {
  list.each(dict.to_list(registry), fn(pair) {
    let #(id, _subject) = pair
    io.println("L5_Executive: Monitoring service agent: " <> id)
  })
}

// =============================================================================
// Worker Actor (L1/L2)
// =============================================================================

pub fn start_worker(
  id: String,
  name: String,
  domain: String,
  role: ServiceRole,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  let initial_state =
    AgentState(
      id: id,
      name: name,
      level: Worker,
      role: role,
      domain: domain,
      status: Idle,
    )

  actor.new(initial_state)
  |> actor.on_message(handle_message)
  |> actor.start()
}

fn handle_message(
  state: AgentState,
  msg: Message,
) -> actor.Next(AgentState, Message) {
  case msg {
    UpdateStatus(status) -> actor.continue(AgentState(..state, status: status))
    GetState(reply_to) -> {
      process.send(reply_to, state)
      actor.continue(state)
    }
  }
}

// =============================================================================
// Domain Supervisor (L3/L4)
// =============================================================================

pub fn start_domain_supervisor(
  domain: String,
  role: ServiceRole,
  worker_count: Int,
) -> Result(actor.Started(supervisor.Supervisor), actor.StartError) {
  supervisor.new(supervisor.OneForOne)
  |> add_workers(domain, role, worker_count)
  |> supervisor.start()
}

fn add_workers(
  builder: supervisor.Builder,
  domain: String,
  role: ServiceRole,
  count: Int,
) -> supervisor.Builder {
  int_range_fold(1, count, builder, fn(acc, i) {
    let id = domain <> "-worker-" <> int_to_string(i)
    let name = domain <> " Service Worker " <> int_to_string(i)
    supervisor.add(
      acc,
      supervision.worker(fn() { start_worker(id, name, domain, role) }),
    )
  })
}

fn int_range_fold(from: Int, to: Int, acc: t, f: fn(t, Int) -> t) -> t {
  case from > to {
    True -> acc
    False -> int_range_fold(from + 1, to, f(acc, from), f)
  }
}

@external(erlang, "erlang", "integer_to_binary")
fn int_to_string(i: Int) -> String

// =============================================================================
// Executive Supervisor (L5/L6)
// =============================================================================

pub fn start_executive_supervisor() -> Result(
  actor.Started(supervisor.Supervisor),
  actor.StartError,
) {
  supervisor.new(supervisor.OneForAll)
  |> supervisor.add(supervision.worker(fn() { cortex.start("Cortex-Alpha") }))
  |> supervisor.add(
    supervision.worker(fn() { briefing.start("Briefing-Alpha") }),
  )
  |> supervisor.add(
    supervision.worker(fn() {
      workspace.start("Workspace-Alpha", "abhijit.naik@boutytek.com")
    }),
  )
  |> supervisor.add(
    supervision.worker(fn() { skill_loader.start("SkillLoader-Alpha") }),
  )
  |> supervisor.add(
    supervision.worker(fn() { leadership.start("Leadership-Monitor") }),
  )
  |> supervisor.add(
    supervision.supervisor(fn() { start_domain_supervisor("Prajna", Prajna, 3) }),
  )
  |> supervisor.add(
    supervision.supervisor(fn() { start_domain_supervisor("CEPAF", CEPAF, 3) }),
  )
  |> supervisor.add(
    supervision.supervisor(fn() {
      start_domain_supervisor("Planning", Planning, 3)
    }),
  )
  |> supervisor.add(
    supervision.supervisor(fn() { start_domain_supervisor("Chaya", Chaya, 3) }),
  )
  |> supervisor.add(
    supervision.supervisor(fn() {
      start_domain_supervisor("Guardian", Guardian, 1)
    }),
  )
  |> supervisor.start()
}

// =============================================================================
// LEGACY DATA-ONLY SUPPORT (SC-AG-LEGACY)
// =============================================================================

pub type CyberAgent {
  CyberAgent(
    id: String,
    name: String,
    level: AgentLevel,
    domain: String,
    status: AgentStatus,
    efficiency: Float,
    parent_id: Option(String),
  )
}

pub type AgentHierarchy {
  AgentHierarchy(agents: Dict(String, CyberAgent), root_id: String)
}

pub fn initialize_hierarchy() -> AgentHierarchy {
  AgentHierarchy(agents: dict.new(), root_id: "none")
}

pub fn get_all_agents(_h: AgentHierarchy) -> List(CyberAgent) {
  []
}

pub fn verify_executive_authority(_h: AgentHierarchy) -> Bool {
  True
}

pub fn check_efficiency_compliance(_h: AgentHierarchy) -> Bool {
  True
}

pub fn detect_deadlock(_h: AgentHierarchy) -> Bool {
  False
}

pub fn get_count_by_level(_h: AgentHierarchy, _l: AgentLevel) -> Int {
  0
}
