//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/iam/supervisor</module>
////     <fsharp-lineage>New</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-CPIG-011, SC-FERRISKEY-NIF-001..010, SC-GCP-IAM-001..020</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Two-level OTP supervisor ↪ multilayer IAM topology.
////       Root supervisor → IamSupervisor (one_for_all) → 6 worker actors.
////       Crash isolation per SC-FERRISKEY-NIF-009.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// LIVE multilayer IAM supervisor. Spawns child workers under
//// `gleam/otp/static_supervisor` with `OneForAll` strategy + intensity=3 /
//// period=60s — matches the `.claude/rules/iam-ferriskey-nif.md` topology.
////
//// Why OneForAll: a JWKS cache crash invalidates the STS cache (a token
//// signed under a now-removed kid is unusable), so the entire IAM tree
//// restarts atomically.
////
//// Workers (each is a real OTP actor with its own message queue):
////   * NifManager — owns ferriskey_nif liveness state
////   * FreshnessMonitor — Andon escalation on stale JWKS / STS / queue lag
////
//// Phase 7 will add: JwksCacheActor, StsTokenCache, ScimOutboundQueue,
//// KeyRotationActor as separate worker modules. Substrate is proven here.

import cepaf_gleam/iam/freshness_monitor
import cepaf_gleam/iam/jwks_cache_actor
import cepaf_gleam/iam/key_rotation_actor
import cepaf_gleam/iam/nif_manager
import cepaf_gleam/iam/scim_outbound_actor
import cepaf_gleam/iam/sts_token_cache_actor
import gleam/otp/actor
import gleam/otp/static_supervisor as sup

/// Specification metadata — the typed declarative form retained for
/// inspection by tests + dashboards.
pub type SupervisorSpec {
  SupervisorSpec(
    name: String,
    strategy: Strategy,
    intensity: Int,
    period_seconds: Int,
    children: List(ChildSpec),
  )
}

pub type Strategy {
  OneForOne
  OneForAll
  RestForOne
}

pub type ChildSpec {
  ChildSpec(id: String, description: String, fractal_layer: String)
}

/// Declarative spec — the source of truth for the topology. Tests assert
/// on this; the LIVE `start` function is built from it.
pub fn iam_supervisor() -> SupervisorSpec {
  SupervisorSpec(
    name: "IamSupervisor",
    strategy: OneForAll,
    intensity: 3,
    period_seconds: 60,
    children: [
      ChildSpec(
        id: "NifManager",
        description: "Process-wide NIF state owner",
        fractal_layer: "L1_ATOMIC_DEBUG",
      ),
      ChildSpec(
        id: "FreshnessMonitor",
        description: "Andon escalation on stale JWKS / STS / queue lag",
        fractal_layer: "L5_COGNITIVE",
      ),
      ChildSpec(
        id: "JwksCacheActor",
        description: "Refreshes JWKS at 80% TTL (Phase 7 worker)",
        fractal_layer: "L0_CONSTITUTIONAL",
      ),
      ChildSpec(
        id: "StsTokenCache",
        description: "GCP STS access-token cache (Phase 7 worker)",
        fractal_layer: "L7_FEDERATION",
      ),
      ChildSpec(
        id: "ScimOutboundQueue",
        description: "Drains SCIM outbound queue (Phase 7 worker)",
        fractal_layer: "L7_FEDERATION",
      ),
      ChildSpec(
        id: "KeyRotationActor",
        description: "Schedules signing-key rotation (Phase 7 worker)",
        fractal_layer: "L0_CONSTITUTIONAL",
      ),
    ],
  )
}

/// Validate the spec against SC-CPIG-011 invariants.
pub fn validate(spec: SupervisorSpec) -> Result(Int, String) {
  case spec.children {
    [] -> Error("supervisor_must_have_children")
    children -> {
      case spec.intensity > 0 && spec.period_seconds > 0 {
        False -> Error("intensity_and_period_must_be_positive")
        True -> Ok(list_length(children))
      }
    }
  }
}

/// Start the LIVE IAM supervisor tree. Returns the supervisor handle on
/// success. The caller (typically the application root supervisor) MUST
/// link this into its own tree via `sup.add(.., iam_supervisor.supervised())`
/// for full two-level supervision per SC-CPIG-011.
///
/// Phase 7.5: 4 of 6 workers wired live (NifManager + FreshnessMonitor +
/// JwksCacheActor + StsTokenCacheActor). Remaining 2 (ScimOutboundQueue,
/// KeyRotationActor) ship in subsequent passes.
pub fn start() -> Result(actor.Started(sup.Supervisor), actor.StartError) {
  sup.new(sup.OneForAll)
  |> sup.restart_tolerance(intensity: 3, period: 60)
  |> sup.add(nif_manager.supervised())
  |> sup.add(freshness_monitor.supervised())
  |> sup.add(jwks_cache_actor.supervised())
  |> sup.add(sts_token_cache_actor.supervised())
  |> sup.add(scim_outbound_actor.supervised())
  |> sup.add(key_rotation_actor.supervised())
  |> sup.start
}

fn list_length(xs: List(ChildSpec)) -> Int {
  case xs {
    [] -> 0
    [_, ..rest] -> 1 + list_length(rest)
  }
}
