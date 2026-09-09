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

import cepaf_gleam/ha/homeostasis_evolution_engine
import cepaf_gleam/ha/predictive_zenoh_stream
import cepaf_gleam/ecology/living_swarm_actor
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
        description: "Control plane UI, Wisp REST API, IAM guard, vault, and Indrajaal actor cluster",
        strategy: OneForOne,
        children: [
          "cepaf_gleam_wisp",
          "indrajaal_holon_runtime",
          "indrajaal_web",
          "iam_supervisor",
          "vault_supervisor",
          "prajna_circuit_breaker",
        ],
      ),
      DomainSpec(
        domain: EnginesDomain,
        name: "EnginesSupervisor",
        description: "ZigVM deterministic runtime, Hermes formal evidence engine, and Rete-UL matcher",
        strategy: RestForOne,
        children: [
          "zigvm_port_manager",
          "hermes_oracle_supervisor",
          "rete_ul_engine",
        ],
      ),
      DomainSpec(
        domain: ServicesDomain,
        name: "ServicesSupervisor",
        description: "Modular MAX isolated inference, unified MCP gateway, planning worker, and telemetry",
        strategy: OneForOne,
        children: [
          "max_isolated_worker",
          "mcp_unified_gateway",
          "planning_worker",
          "predictive_zenoh_stream",
          "ha_freshness_monitor",
        ],
      ),
      DomainSpec(
        domain: IntelligenceDomain,
        name: "IntelligenceSupervisor",
        description: "Swarming holon actor mesh, lease fencing, cybernetic executive, and L0 constitution",
        strategy: OneForAll,
        children: [
          "holon_swarm_mesh",
          "lease_fencing_monitor",
          "cybernetic_executive",
          "unified_verification_supervisor",
          "c3i_knowledge_supervisor",
          "pi_supervisor",
          "cpig_supervisor",
          "fractal_l0_constitutional",
          "ha_lyapunov_proof",
          "homeostasis_evolution_engine",
        ],
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
pub fn start_root_supervisor() -> Result(
  actor.Started(sup.Supervisor),
  actor.StartError,
) {
  sup.new(sup.RestForOne)
  |> sup.restart_tolerance(intensity: 5, period: 60)
  |> sup.add(predictive_zenoh_stream.supervised())
  |> sup.add(homeostasis_evolution_engine.supervised(0))
  |> sup.add(living_swarm_actor.runtime_supervised(1000))
  |> sup.start
}
