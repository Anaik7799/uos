//// =============================================================================
//// [UOS-ARCH-SUP-001] UOS MULTILAYER ROOT OTP SUPERVISOR
//// =============================================================================
//// <uos-module>
////   <identity>
////     <module>cepaf_gleam/uos_sup</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <topology>Multilayer 4-Domain Hierarchical Supervision</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-OTP-001, SC-SUP-001..004, SC-ZERO-MUDA-001</stamp-controls>
////   </compliance>
//// </uos-module>
//// =============================================================================

import gleam/list
import gleam/otp/actor
import gleam/otp/static_supervisor as sup

pub type Strategy {
  OneForOne
  OneForAll
  RestForOne
}

pub type SubsystemDomain {
  AppsDomain
  EnginesDomain
  ServicesDomain
  IntelligenceDomain
}

pub type DomainSpec {
  DomainSpec(
    domain: SubsystemDomain,
    name: String,
    description: String,
    strategy: Strategy,
    children: List(String),
  )
}

pub type RootSupervisorSpec {
  RootSupervisorSpec(
    name: String,
    version: String,
    strategy: Strategy,
    intensity: Int,
    period_seconds: Int,
    domains: List(DomainSpec),
  )
}

/// Declarative specification of the UOS Multi-Layer Supervision Tree.
pub fn uos_root_spec() -> RootSupervisorSpec {
  RootSupervisorSpec(
    name: "UOSRootSupervisor",
    version: "1.0.0",
    strategy: RestForOne,
    intensity: 5,
    period_seconds: 60,
    domains: [
      DomainSpec(
        domain: AppsDomain,
        name: "AppsSupervisor",
        description: "Control plane UI, Wisp REST API, and Indrajaal actor cluster",
        strategy: OneForOne,
        children: ["cepaf_gleam_wisp", "indrajaal_holon_runtime", "indrajaal_web"],
      ),
      DomainSpec(
        domain: EnginesDomain,
        name: "EnginesSupervisor",
        description: "ZigVM deterministic runtime & Hermes formal evidence engine",
        strategy: RestForOne,
        children: ["zigvm_port_manager", "hermes_oracle_supervisor"],
      ),
      DomainSpec(
        domain: ServicesDomain,
        name: "ServicesSupervisor",
        description: "Modular MAX isolated inference, unified MCP gateway, and planning worker",
        strategy: OneForOne,
        children: ["max_isolated_worker", "mcp_unified_gateway", "planning_worker"],
      ),
      DomainSpec(
        domain: IntelligenceDomain,
        name: "IntelligenceSupervisor",
        description: "Swarming holon actor mesh, lease generation fencing, and Rete-UL rules",
        strategy: OneForAll,
        children: ["holon_swarm_mesh", "lease_fencing_monitor", "rete_ul_engine"],
      ),
    ],
  )
}

/// Validate the root specification topology against zero-muda and OTP invariants.
pub fn validate_spec(spec: RootSupervisorSpec) -> Result(Int, String) {
  case spec.domains {
    [] -> Error("root_supervisor_must_have_domains")
    domains -> {
      case spec.intensity > 0 && spec.period_seconds > 0 {
        False -> Error("intensity_and_period_must_be_positive")
        True -> {
          let total_children =
            list.fold(domains, 0, fn(acc, d) { acc + list.length(d.children) })
          case total_children >= 8 {
            True -> Ok(total_children)
            False -> Error("insufficient_subsystem_coverage")
          }
        }
      }
    }
  }
}

/// Start declarative static supervisor for the root tree.
pub fn start_root_supervisor() -> Result(actor.Started(sup.Supervisor), actor.StartError) {
  sup.new(sup.RestForOne)
  |> sup.restart_tolerance(intensity: 5, period: 60)
  |> sup.start
}
