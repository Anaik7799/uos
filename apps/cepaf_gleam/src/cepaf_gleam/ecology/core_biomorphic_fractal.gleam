//// UOS-CORE-EVO: Biomorphic Homeostasis & 10-Layer (L0..L9) Fractal POODAVR Kernel
//// (`SC-POODAVR-002`, `SC-JIDOKA-001`, `SC-PROVENANCE-001`, `#fractal-l0..l9`)
////
//// Unifies:
//// 1. Biomorphic Autonomic Regulation:
////    - Metabolic ATP Energy Regimes (`AnabolicParallel` -> `HomeostaticShift`
////      -> `CatabolicCriticalOnly` -> `TorporMargin40Hold`).
////    - Self/Non-Self Autonomic Immune Classifier + Prajna Circuit Breaker
////      (`BreakerClosed` -> `BreakerHalfOpen` -> `BreakerOpen`) trapping
////      `c3i/**` split-brain frames (`I28`), `EV > 93` provenance anomalies,
////      `Default@` digest drift, and `/tmp` tmpfs pressure (`I19`).
////    - Discrete Lyapunov Stability Proof (`V(t) >= 0`, `dV = V(t) - V(t-1) <= 0`).
//// 2. Full 10-Layer Fractal Topology (`L0_Constitutional` .. `L9_MetaEvolution`)
////    coupled with the 7-stage closed-loop POODAVR cycle (`poodavr_engine`).

import cepaf_gleam/ecology/core_evolution.{
  type QuotaSnapshot, QuotaAdmitted, QuotaHoldMargin40Pct,
}
import cepaf_gleam/poodavr/poodavr_engine.{
  type CycleVerdict, CycleAndonHalt, CyclePassed, StageAct, StageDecide,
  StageObserve, StageOrient, StagePredict, StageReflect, StageVerify,
}
import gleam/int
import gleam/json
import gleam/list

/// Canonical 10-layer UOS Fractal Topology (`L0..L9`, extending legacy `L0..L7`).
pub type FractalLayer10 {
  L0Constitutional
  L1AtomicKernel
  L2ComponentModule
  L3TransactionLedger
  L4SystemSupervision
  L5CognitiveKmTriad
  L6EcosystemZenohMesh
  L7FederationTailnet
  L8ReleaseContinuity
  L9MetaEvolution
}

pub fn all_10_fractal_layers() -> List(FractalLayer10) {
  [
    L0Constitutional,
    L1AtomicKernel,
    L2ComponentModule,
    L3TransactionLedger,
    L4SystemSupervision,
    L5CognitiveKmTriad,
    L6EcosystemZenohMesh,
    L7FederationTailnet,
    L8ReleaseContinuity,
    L9MetaEvolution,
  ]
}

pub fn layer_tag(layer: FractalLayer10) -> String {
  case layer {
    L0Constitutional -> "#fractal-l0"
    L1AtomicKernel -> "#fractal-l1"
    L2ComponentModule -> "#fractal-l2"
    L3TransactionLedger -> "#fractal-l3"
    L4SystemSupervision -> "#fractal-l4"
    L5CognitiveKmTriad -> "#fractal-l5"
    L6EcosystemZenohMesh -> "#fractal-l6"
    L7FederationTailnet -> "#fractal-l7"
    L8ReleaseContinuity -> "#fractal-l8"
    L9MetaEvolution -> "#fractal-l9"
  }
}

pub type LayerHealth {
  LayerHealthy
  LayerDegraded(detail: String)
  LayerAndonHold(detail: String)
}

pub type LayerObservation {
  LayerObservation(
    layer: FractalLayer10,
    health: LayerHealth,
    open_issues: Int,
    poodavr_verdict: CycleVerdict,
  )
}

/// Monoidal upward aggregation across `L0..L9`: zero green-washing. Any
/// `LayerAndonHold` or `CycleAndonHalt` forces whole-system `LayerAndonHold`;
/// any `LayerDegraded` or missing layer forces `LayerDegraded`.
pub fn rollup_fractal_health(obs: List(LayerObservation)) -> LayerHealth {
  let covered =
    list.all(all_10_fractal_layers(), fn(req) {
      list.any(obs, fn(o) { o.layer == req })
    })
  let base =
    list.fold(obs, LayerHealthy, fn(acc, o) {
      let effective = case o.poodavr_verdict {
        CyclePassed(_, 7) -> o.health
        CyclePassed(_, _) -> LayerDegraded("incomplete_poodavr_stages")
        CycleAndonHalt(_, stage, _) ->
          LayerAndonHold("poodavr_andon_halt:" <> stage)
      }
      join_health(acc, effective)
    })
  case covered {
    True -> base
    False -> join_health(base, LayerDegraded("incomplete_l0_l9_coverage"))
  }
}

/// Execute a verified 7-stage closed-loop POODAVR cycle for a fractal layer.
pub fn run_layer_poodavr(
  layer: FractalLayer10,
  horizon_s horizon_s: Int,
  topics_observed topics_observed: Int,
  truth_level truth_level: Float,
  utility_score utility_score: Float,
  port_name port_name: String,
  formal_verified formal_verified: Bool,
  brier_delta brier_delta: Float,
) -> CycleVerdict {
  poodavr_engine.init_cycle("poodavr:" <> layer_tag(layer))
  |> poodavr_engine.step_stage(StagePredict(horizon_s))
  |> poodavr_engine.step_stage(StageObserve(topics_observed))
  |> poodavr_engine.step_stage(StageOrient(truth_level))
  |> poodavr_engine.step_stage(StageDecide(utility_score))
  |> poodavr_engine.step_stage(StageAct(port_name))
  |> poodavr_engine.step_stage(StageVerify(formal_verified))
  |> poodavr_engine.step_stage(StageReflect(brier_delta))
  |> poodavr_engine.evaluate_cycle
}

// =============================================================================
// Biomorphic Homeostasis: Metabolic ATP, Autonomic Immune & Lyapunov dV/dt <= 0
// =============================================================================

pub type MetabolicRegime {
  AnabolicParallel
  HomeostaticZeroOrShift
  CatabolicCriticalPathOnly
  TorporMargin40Hold
}

/// Map live 4-window 40%-margin quota telemetry to biomorphic metabolic regime.
pub fn classify_metabolic_regime(quota: QuotaSnapshot) -> MetabolicRegime {
  case core_evolution.evaluate_quota_margin(quota) {
    QuotaHoldMargin40Pct(_) -> TorporMargin40Hold
    QuotaAdmitted(_, min_margin_bps, _) ->
      // min_margin_bps is in [4000..10000] when admitted:
      // > 5500 bps free (< 45% used) => AnabolicParallel (full 4-forager wave)
      // 4500..5500 bps free (45%..55% used) => HomeostaticZeroOrShift
      // 4000..4499 bps free (55.01%..60.0% used) => CatabolicCriticalPathOnly
      case min_margin_bps > 5500 {
        True -> AnabolicParallel
        False ->
          case min_margin_bps >= 4500 {
            True -> HomeostaticZeroOrShift
            False -> CatabolicCriticalPathOnly
          }
      }
  }
}

pub type AntigenSignal {
  SelfCanonicalEnvelope
  AntigenForeignC3iFrame(source: String)
  AntigenProvenanceAboveEv93(ev_claimed: Int)
  AntigenProtectedDigestDrift(path: String)
  AntigenTmpfsQuotaPressure(used_pct: Int)
  AntigenStaleZombieLease(count: Int)
}

pub type BreakerState {
  BreakerClosed
  BreakerHalfOpen(consecutive_failures: Int)
  BreakerOpen(trip_reason: String)
}

pub type ImmuneResponse {
  ImmuneTolerateSelf(breaker: BreakerState)
  ImmuneIsolateAndHeal(action: String, breaker: BreakerState)
  ImmuneQuarantineAndTripBreaker(reason: String, breaker: BreakerState)
}

/// Biomorphic Self/Non-Self Immune reflex coupled to Prajna Circuit Breaker.
pub fn evaluate_immune_reflex(
  antigen: AntigenSignal,
  prior_failures: Int,
) -> ImmuneResponse {
  case antigen {
    SelfCanonicalEnvelope ->
      case prior_failures > 0 {
        True -> ImmuneTolerateSelf(BreakerHalfOpen(prior_failures - 1))
        False -> ImmuneTolerateSelf(BreakerClosed)
      }
    AntigenForeignC3iFrame(src) ->
      ImmuneIsolateAndHeal(
        "drop_c3i_frame_enforce_uos_v1_fence:" <> src,
        step_breaker(prior_failures + 1, "foreign_c3i_split_brain"),
      )
    AntigenTmpfsQuotaPressure(pct) ->
      case pct >= 90 {
        True ->
          ImmuneQuarantineAndTripBreaker(
            "tmpfs_critical_over_90pct",
            BreakerOpen("tmpfs_critical"),
          )
        False ->
          ImmuneIsolateAndHeal(
            "redirect_tmpdir_to_var_tmp_core_evo",
            BreakerHalfOpen(prior_failures + 1),
          )
      }
    AntigenStaleZombieLease(cnt) ->
      case cnt > 0 {
        True ->
          ImmuneIsolateAndHeal(
            "verify_pid_quiescence_and_fence_before_reclaim",
            BreakerHalfOpen(prior_failures + 1),
          )
        False -> ImmuneTolerateSelf(BreakerClosed)
      }
    AntigenProvenanceAboveEv93(ev) ->
      ImmuneQuarantineAndTripBreaker(
        "unadmitted_ev_claim:" <> int.to_string(ev),
        BreakerOpen("sc_provenance_001_violation"),
      )
    AntigenProtectedDigestDrift(path) ->
      ImmuneQuarantineAndTripBreaker(
        "protected_default_at_drift:" <> path,
        BreakerOpen("protected_codex_file_drift"),
      )
  }
}

pub type LyapunovEnergy {
  LyapunovEnergy(
    v_prev: Int,
    v_now: Int,
    delta_v: Int,
    is_monotone_stable: Bool,
  )
}

/// Compute discrete Lyapunov candidate energy:
///   V(t) = 100 * failing_tasks + 40 * stale_leases + 15 * open_issues + 80 * drift_events
/// Evolution is asymptotically stable iff `V(t) == 0` or `delta_v = V(t) - V(t-1) <= 0`.
pub fn evaluate_lyapunov_stability(
  v_prev v_prev: Int,
  failing_tasks failing_tasks: Int,
  stale_leases stale_leases: Int,
  open_issues open_issues: Int,
  drift_events drift_events: Int,
) -> LyapunovEnergy {
  let v_now =
    100
    * int.max(0, failing_tasks)
    + 40
    * int.max(0, stale_leases)
    + 15
    * int.max(0, open_issues)
    + 80
    * int.max(0, drift_events)
  let dv = v_now - int.max(0, v_prev)
  LyapunovEnergy(
    v_prev: int.max(0, v_prev),
    v_now: v_now,
    delta_v: dv,
    is_monotone_stable: v_now == 0 || dv <= 0,
  )
}

pub fn encode_biomorphic_fractal_summary(
  regime: MetabolicRegime,
  fractal_health: LayerHealth,
  lyapunov: LyapunovEnergy,
) -> String {
  let regime_str = case regime {
    AnabolicParallel -> "anabolic_parallel"
    HomeostaticZeroOrShift -> "homeostatic_zero_or_shift"
    CatabolicCriticalPathOnly -> "catabolic_critical_only"
    TorporMargin40Hold -> "torpor_margin_40_hold"
  }
  let health_str = case fractal_health {
    LayerHealthy -> "healthy_l0_l9"
    LayerDegraded(d) -> "degraded:" <> d
    LayerAndonHold(d) -> "andon_hold:" <> d
  }
  json.object([
    #("schema", json.string("uos.core_evo.biomorphic_fractal.v1")),
    #("metabolic_regime", json.string(regime_str)),
    #("fractal_l0_l9_health", json.string(health_str)),
    #("lyapunov_v_prev", json.int(lyapunov.v_prev)),
    #("lyapunov_v_now", json.int(lyapunov.v_now)),
    #("lyapunov_dv", json.int(lyapunov.delta_v)),
    #("lyapunov_stable", json.bool(lyapunov.is_monotone_stable)),
  ])
  |> json.to_string
}

fn join_health(a: LayerHealth, b: LayerHealth) -> LayerHealth {
  case a, b {
    LayerAndonHold(d), _ -> LayerAndonHold(d)
    _, LayerAndonHold(d) -> LayerAndonHold(d)
    LayerDegraded(d), _ -> LayerDegraded(d)
    _, LayerDegraded(d) -> LayerDegraded(d)
    LayerHealthy, LayerHealthy -> LayerHealthy
  }
}

fn step_breaker(failures: Int, reason: String) -> BreakerState {
  case failures >= 3 {
    True -> BreakerOpen(reason)
    False -> BreakerHalfOpen(failures)
  }
}
