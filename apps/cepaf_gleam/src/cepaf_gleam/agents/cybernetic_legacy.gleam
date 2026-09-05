//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/agents/cybernetic</module>
////   <fsharp-lineage>Cepaf.Agents.Cybernetic</fsharp-lineage></identity>
////   <fractal-topology><layer>L7_FEDERATION</layer></fractal-topology></c3i-module>

import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}

pub type AgentLevel {
  Executive
  DomainSupervisor
  FunctionalSupervisor
  Worker
}

pub type AgentStatus {
  Idle
  AgentActive(task: String)
  AgentBlocked(reason: String)
}

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

pub fn create_agent(
  id: String,
  name: String,
  level: AgentLevel,
  domain: String,
  parent_id: Option(String),
) -> CyberAgent {
  CyberAgent(
    id: id,
    name: name,
    level: level,
    domain: domain,
    status: Idle,
    efficiency: 1.0,
    parent_id: parent_id,
  )
}

pub fn initialize_hierarchy() -> AgentHierarchy {
  let executive =
    create_agent("exec-001", "MasterSupervisor", Executive, "system", None)
  let initial = dict.from_list([#("exec-001", executive)])

  let domains = [
    "planning", "podman", "zenoh", "immune", "telemetry", "verification",
    "substrate", "knowledge", "metabolic", "ui",
  ]

  // Create domain supervisors (10)
  let with_domain_sups =
    list.index_fold(domains, initial, fn(acc, domain, idx) {
      let id = "dsup-" <> int.to_string(idx + 1)
      let agent =
        create_agent(
          id,
          domain <> "-supervisor",
          DomainSupervisor,
          domain,
          Some("exec-001"),
        )
      dict.insert(acc, id, agent)
    })

  // Create functional supervisors (10) and workers (29) = total 50
  let with_func_sups =
    list.index_fold(domains, with_domain_sups, fn(acc, domain, idx) {
      let parent_id = "dsup-" <> int.to_string(idx + 1)
      let fsup_id = "fsup-" <> int.to_string(idx + 1)
      let fsup =
        create_agent(
          fsup_id,
          domain <> "-func-sup",
          FunctionalSupervisor,
          domain,
          Some(parent_id),
        )
      dict.insert(acc, fsup_id, fsup)
    })

  // Create 29 workers spread across domains
  let with_workers =
    int.range(from: 1, to: 29, with: with_func_sups, run: fn(acc, i) {
      let domain_idx = { i - 1 } % list.length(domains)
      let domain = case list.drop(domains, domain_idx) {
        [d, ..] -> d
        [] -> "system"
      }
      let parent_id = "fsup-" <> int.to_string(domain_idx + 1)
      let worker_id = "worker-" <> int.to_string(i)
      let worker =
        create_agent(
          worker_id,
          domain <> "-worker-" <> int.to_string(i),
          Worker,
          domain,
          Some(parent_id),
        )
      dict.insert(acc, worker_id, worker)
    })

  AgentHierarchy(agents: with_workers, root_id: "exec-001")
}

pub fn register_agent(
  hierarchy: AgentHierarchy,
  agent: CyberAgent,
) -> AgentHierarchy {
  AgentHierarchy(
    ..hierarchy,
    agents: dict.insert(hierarchy.agents, agent.id, agent),
  )
}

pub fn get_agent(hierarchy: AgentHierarchy, id: String) -> Option(CyberAgent) {
  case dict.get(hierarchy.agents, id) {
    Ok(agent) -> Some(agent)
    Error(_) -> None
  }
}

pub fn update_agent_status(
  hierarchy: AgentHierarchy,
  id: String,
  status: AgentStatus,
) -> AgentHierarchy {
  case dict.get(hierarchy.agents, id) {
    Ok(agent) -> {
      let updated = CyberAgent(..agent, status: status)
      AgentHierarchy(
        ..hierarchy,
        agents: dict.insert(hierarchy.agents, id, updated),
      )
    }
    Error(_) -> hierarchy
  }
}

pub fn update_agent_efficiency(
  hierarchy: AgentHierarchy,
  id: String,
  efficiency: Float,
) -> AgentHierarchy {
  case dict.get(hierarchy.agents, id) {
    Ok(agent) -> {
      let clamped = float.min(1.0, float.max(0.0, efficiency))
      let updated = CyberAgent(..agent, efficiency: clamped)
      AgentHierarchy(
        ..hierarchy,
        agents: dict.insert(hierarchy.agents, id, updated),
      )
    }
    Error(_) -> hierarchy
  }
}

pub fn get_all_agents(hierarchy: AgentHierarchy) -> List(CyberAgent) {
  dict.values(hierarchy.agents)
}

pub fn get_agents_by_domain(
  hierarchy: AgentHierarchy,
  domain: String,
) -> List(CyberAgent) {
  dict.values(hierarchy.agents)
  |> list.filter(fn(a) { a.domain == domain })
}

pub fn get_count_by_level(hierarchy: AgentHierarchy, level: AgentLevel) -> Int {
  dict.values(hierarchy.agents)
  |> list.filter(fn(a) { a.level == level })
  |> list.length
}

pub fn check_efficiency_compliance(hierarchy: AgentHierarchy) -> Bool {
  let agents = dict.values(hierarchy.agents)
  let total = list.length(agents)
  case total {
    0 -> True
    _ -> {
      let compliant =
        list.filter(agents, fn(a) { a.efficiency >=. 0.9 })
        |> list.length
      let pct = int.to_float(compliant * 100) /. int.to_float(total)
      pct >=. 90.0
    }
  }
}

pub fn detect_deadlock(hierarchy: AgentHierarchy) -> Bool {
  let agents = dict.values(hierarchy.agents)
  let total = list.length(agents)
  case total {
    0 -> False
    _ -> {
      let blocked_count =
        list.filter(agents, fn(a) {
          case a.status {
            AgentBlocked(_) -> True
            _ -> False
          }
        })
        |> list.length
      let pct = int.to_float(blocked_count * 100) /. int.to_float(total)
      pct >. 50.0
    }
  }
}

pub fn verify_executive_authority(hierarchy: AgentHierarchy) -> Bool {
  get_count_by_level(hierarchy, Executive) == 1
}

pub fn get_metrics(hierarchy: AgentHierarchy) -> #(Int, Int, Int, Float) {
  let agents = dict.values(hierarchy.agents)
  let total = list.length(agents)
  let active =
    list.filter(agents, fn(a) {
      case a.status {
        AgentActive(_) -> True
        _ -> False
      }
    })
    |> list.length
  let blocked =
    list.filter(agents, fn(a) {
      case a.status {
        AgentBlocked(_) -> True
        _ -> False
      }
    })
    |> list.length
  let avg_eff = case total {
    0 -> 0.0
    _ -> {
      let sum = list.fold(agents, 0.0, fn(acc, a) { acc +. a.efficiency })
      sum /. int.to_float(total)
    }
  }
  #(total, active, blocked, avg_eff)
}

pub fn classify_agent_status(agent: CyberAgent) -> String {
  case agent.status {
    Idle -> "idle"
    AgentActive(_) -> "active"
    AgentBlocked(_) -> "blocked"
  }
}

pub fn classify_efficiency(efficiency: Float) -> String {
  case efficiency {
    e if e >=. 0.9 -> "optimal"
    e if e >=. 0.7 -> "acceptable"
    e if e >=. 0.5 -> "degraded"
    _ -> "critical"
  }
}

pub fn get_efficiency_status(agent: CyberAgent) -> String {
  classify_efficiency(agent.efficiency)
}

pub fn agent_to_json(agent: CyberAgent) -> Json {
  json.object([
    #("id", json.string(agent.id)),
    #("name", json.string(agent.name)),
    #("level", json.string(level_to_string(agent.level))),
    #("domain", json.string(agent.domain)),
    #("status", json.string(classify_agent_status(agent))),
    #("efficiency", json.float(agent.efficiency)),
    #("parent_id", case agent.parent_id {
      Some(pid) -> json.string(pid)
      None -> json.null()
    }),
  ])
}

pub fn hierarchy_to_json(hierarchy: AgentHierarchy) -> Json {
  let #(total, active, blocked, avg_eff) = get_metrics(hierarchy)
  json.object([
    #("root_id", json.string(hierarchy.root_id)),
    #("total_agents", json.int(total)),
    #("active_agents", json.int(active)),
    #("blocked_agents", json.int(blocked)),
    #("avg_efficiency", json.float(avg_eff)),
    #("agents", json.array(dict.values(hierarchy.agents), agent_to_json)),
  ])
}

fn level_to_string(level: AgentLevel) -> String {
  case level {
    Executive -> "executive"
    DomainSupervisor -> "domain_supervisor"
    FunctionalSupervisor -> "functional_supervisor"
    Worker -> "worker"
  }
}
