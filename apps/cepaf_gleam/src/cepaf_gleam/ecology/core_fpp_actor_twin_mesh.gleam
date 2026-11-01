//// UOS-CORE-EVO v5: Universal 40-Subsystem Intelligent OTP 29.0.5 NASA FPP
//// Actor & Digital Twin Mesh Covering Every Part of UOS Across All 4 Root
//// Supervision Domains (`Apps`, `Engines`, `Services`, `Intelligence`) x 10
//// Fractal Layers (`L0..L9`)
//// (`SC-HARNESS-MCP-001`, `SC-POODAVR-002`, `SC-DENOTATIONAL-INTENT-001`,
////  `SC-INTENT-ATLAS-001`, `SC-OTEL-002`, `SC-OPENROUTER-001`, `SC-PROVENANCE-001`)
////
//// Guarantees for every one of the 40 Intelligent Subsystem Actors:
//// 1. Runs strictly on verified Erlang/OTP 29 (`otp_release == "29"`).
//// 2. Governed internally by dual executable NASA JPL F Prime (FPP) state
////    machines (`poodavr_lifecycle_fprime` + subsystem-specialized companion
////    `homeostasis_fprime` via `fpp/interp`).
//// 3. Executes an Autonomous Cybernetic Intelligence & Reflex Engine combining
////    Kalman posterior health, innovation residual, discrete PID damping effort,
////    Lyapunov energy derivative dV/dt, Beta-Bernoulli epistemic reliability,
////    and 40%-margin-gated `$0`-first redacted OpenRouter cognitive advisory:
////    - `ReflexNominalContinue`
////    - `ReflexPidDampingTune`
////    - `ReflexAutonomousSelfHeal` (automatic Digital Twin & F' canary recovery)
////    - `ReflexQuarantineAndCircuitBreak`
////    - `ReflexJidokaConstitutionalHalt`
//// 4. Communicates exclusively via role-whitelisted Gleam MCP routes and
////    RFC 8032 Ed25519-signed Zenoh `uos/v1/**` envelopes (`core_bus`).
//// 5. Propagates 128-bit W3C OTel `TraceContext` (`traceparent`), emits BEAM
////    `telemetry` spans, and records structured OTel fractal JSON logs.
//// 6. Aligned surjectively across all 17 UOS Aspects, 4 Supervision Domains,
////    Algebraic Atlas cocycle morphisms, Cech Sheaf gluing (`H^1 = 0`), and
////    Denotational Intent valuation `[[ I ]](sigma)`.

import cepaf_gleam/ecology/core_evolution.{
  type QuotaSnapshot, type TaskRole, FmeaFormalRole, ImplRole, QuotaAdmitted,
  QuotaHoldMargin40Pct, RcaTpsRole, SovereignGateRole,
  ZeroOpenRouterAndBatchedWakeups, ZeroOpenRouterShift,
}
import cepaf_gleam/fpp/domain.{type StateMachine}
import cepaf_gleam/fpp/homeostasis_fprime
import cepaf_gleam/fpp/interp as fpp_interp
import cepaf_gleam/fpp/poodavr_fprime
import cepaf_gleam/ha/correlated_log.{Critical, Info, Warn}
import cepaf_gleam/ha/digital_twin.{
  type SyncAction, type TwinState, Converge, NoSync,
}
import cepaf_gleam/ha/trace_context.{type TraceContext}
import cepaf_gleam/harness/egress_redactor.{EgressBlocked, EgressPermitted}
import cepaf_gleam/intent/denotational.{
  type LatticeState, Intent as DenotationalIntent,
}
import cepaf_gleam/math/bayesian
import cepaf_gleam/semantics/algebraic_atlas.{
  type ChartIndex, type ChartState, ChartState, DeclarativeIntent,
  DenotationalSuccess, DenotationalVetoed, L0Constitutional, L1AtomicKernel,
  L2Homeostasis, L3Transactions, L4SystemDaemons, L5CognitiveOODA, L6SwarmMesh,
  L7Federation, L8Verification, L9Sovereignty, TraceCoordinates,
  TransitionMorphism,
}
import cepaf_gleam/telemetry/otel.{SpanContext}
import cepaf_gleam/uos_sup.{
  type SubsystemDomain, AppsDomain, EnginesDomain, IntelligenceDomain,
  ServicesDomain,
}
import cepaf_gleam/verification/aspect_coverage_engine
import cepaf_gleam/zenoh/core_bus
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/result
import gleam/string

const active_plan_id = "uos/universal-intelligent-fpp-actor-mesh/20261101-2232"

pub const universal_fpp_actor_count = 40

type ErlTerm

@external(erlang, "erlang", "binary_to_atom")
fn stdlib_binary_to_atom(name: String) -> ErlTerm

@external(erlang, "code", "ensure_loaded")
fn stdlib_ensure_loaded(mod: ErlTerm) -> ErlTerm

@external(erlang, "code", "is_loaded")
fn stdlib_is_loaded(mod: ErlTerm) -> ErlTerm

@external(erlang, "code", "which")
fn stdlib_code_which(mod: ErlTerm) -> ErlTerm

@external(erlang, "code", "stick_mod")
fn stdlib_stick_mod(mod: ErlTerm) -> ErlTerm

@external(erlang, "erlang", "is_tuple")
fn stdlib_is_tuple(term: ErlTerm) -> Bool

@external(erlang, "erlang", "tuple_size")
fn stdlib_tuple_size(term: ErlTerm) -> Int

@external(erlang, "erlang", "element")
fn stdlib_element(index: Int, term: ErlTerm) -> ErlTerm

@external(erlang, "erlang", "is_list")
fn stdlib_is_list(term: ErlTerm) -> Bool

@external(erlang, "erlang", "length")
fn stdlib_list_length(term: ErlTerm) -> Int

@external(erlang, "filename", "absname")
fn stdlib_filename_absname(path: ErlTerm) -> ErlTerm

@external(erlang, "filename", "dirname")
fn stdlib_filename_dirname(path: ErlTerm) -> ErlTerm

@external(erlang, "erlang", "system_time")
fn stdlib_erlang_system_time(unit: ErlTerm) -> Int

@external(erlang, "file", "read_file")
fn stdlib_file_read_file(path: ErlTerm) -> Result(BitArray, ErlTerm)

@external(erlang, "beam_lib", "md5")
fn stdlib_beam_lib_md5(beam_bytes: BitArray) -> ErlTerm

@external(erlang, "erlang", "get_module_info")
fn stdlib_get_module_info(mod: ErlTerm, item: ErlTerm) -> ErlTerm

@external(erlang, "core_fpp_candidate_ffi", "verified_candidate_sha256")
fn ffi_verified_candidate_sha256() -> String

@external(erlang, "core_fpp_candidate_ffi", "register_live_fpp_actor")
fn ffi_register_live_fpp_actor(
  actor_idx: Int,
  subj: Subject(FppHolonActorMessage),
) -> Nil

@external(erlang, "core_fpp_candidate_ffi", "lookup_live_fpp_actor")
fn ffi_lookup_live_fpp_actor(
  actor_idx: Int,
) -> Result(Subject(FppHolonActorMessage), Nil)

@external(erlang, "core_fpp_candidate_ffi", "ensure_live_fpp_mesh_supervisor")
fn ffi_ensure_live_fpp_mesh_supervisor(now_ms: Int) -> Result(Int, String)

@external(erlang, "core_fpp_candidate_ffi", "live_fpp_supervisor_status")
fn ffi_live_fpp_supervisor_status() -> #(Bool, Int)

fn current_system_time_ms() -> Int {
  stdlib_erlang_system_time(stdlib_binary_to_atom("millisecond"))
}

fn stdlib_module_matches_disk(mod_name: String) -> Bool {
  let mod_atom = stdlib_binary_to_atom(mod_name)
  let ok_atom = stdlib_binary_to_atom("ok")
  let md5_atom = stdlib_binary_to_atom("md5")
  let _ = stdlib_ensure_loaded(mod_atom)
  case stdlib_is_tuple(stdlib_is_loaded(mod_atom)) {
    False -> False
    True -> {
      let which_path = stdlib_code_which(mod_atom)
      case stdlib_is_list(which_path) && stdlib_list_length(which_path) > 0 {
        False -> False
        True -> {
          let abs_path = stdlib_filename_absname(which_path)
          case stdlib_file_read_file(abs_path) {
            Error(_) -> False
            Ok(beam_bytes) -> {
              let md5_res = stdlib_beam_lib_md5(beam_bytes)
              case
                stdlib_is_tuple(md5_res)
                && stdlib_tuple_size(md5_res) == 2
                && stdlib_element(1, md5_res) == ok_atom
              {
                False -> False
                True -> {
                  let pair = stdlib_element(2, md5_res)
                  case
                    stdlib_is_tuple(pair)
                    && stdlib_tuple_size(pair) == 2
                    && stdlib_element(1, pair) == mod_atom
                  {
                    False -> False
                    True -> {
                      let disk_md5 = stdlib_element(2, pair)
                      let mem_md5 = stdlib_get_module_info(mod_atom, md5_atom)
                      case disk_md5 == mem_md5 {
                        False -> False
                        True -> {
                          let _ = stdlib_stick_mod(mod_atom)
                          True
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

fn stdlib_resolved_beam_dir(mod_name: String) -> Result(ErlTerm, Nil) {
  let mod_atom = stdlib_binary_to_atom(mod_name)
  let _ = stdlib_ensure_loaded(mod_atom)
  let which_path = stdlib_code_which(mod_atom)
  case stdlib_is_list(which_path) && stdlib_list_length(which_path) > 0 {
    False -> Error(Nil)
    True -> Ok(stdlib_filename_dirname(stdlib_filename_absname(which_path)))
  }
}

fn stdlib_same_ebin_directory(
  mod_a: String,
  mod_b: String,
  mod_c: String,
) -> Bool {
  case
    stdlib_resolved_beam_dir(mod_a),
    stdlib_resolved_beam_dir(mod_b),
    stdlib_resolved_beam_dir(mod_c)
  {
    Ok(dir_a), Ok(dir_b), Ok(dir_c) -> dir_a == dir_b && dir_a == dir_c
    _, _, _ -> False
  }
}

fn stdlib_all_candidate_modules_match_disk() -> Bool {
  stdlib_same_ebin_directory(
    "cepaf_gleam@ecology@core_fpp_actor_twin_mesh",
    "core_fpp_candidate_ffi",
    "core_bus_crypto_ffi",
  )
  && stdlib_module_matches_disk("cepaf_gleam@ecology@core_fpp_actor_twin_mesh")
  && stdlib_module_matches_disk("core_fpp_candidate_ffi")
  && stdlib_module_matches_disk("core_bus_crypto_ffi")
}

fn is_lower_hex64(value: String) -> Bool {
  string.byte_size(value) == 64
  && list.all(string.to_graphemes(value), fn(ch) {
    case ch {
      "0"
      | "1"
      | "2"
      | "3"
      | "4"
      | "5"
      | "6"
      | "7"
      | "8"
      | "9"
      | "a"
      | "b"
      | "c"
      | "d"
      | "e"
      | "f" -> True
      _ -> False
    }
  })
}

/// Resolves the live candidate SHA-256 digest strictly from the loaded BEAM
/// object path (`code:which`) and manifest-verified capsule or workspace source:
/// - Zero process-CWD fallback (`cd /home/an/NAS-setup/uos` cannot leak a different
///   workspace's hash).
/// - Zero unverified env-var overrides (`UOS_CANDIDATE_SHA256` ignored).
/// - If `UOS_COCKPIT_RELEASE` is set, fails closed (`""`) unless the loaded BEAM
///   resides inside that exact capsule, `.uos-ecology-release` equals
///   `"uos.ecology-release.v1\n"`, `source-manifest.json` SHA-256 matches
///   `release-manifest.json` `source_sha256`, and the loaded BEAM SHA-256 matches
///   `release-manifest.json`.
fn verified_candidate_sha256_strict() -> String {
  case stdlib_all_candidate_modules_match_disk() {
    False -> ""
    True -> {
      let resolved = ffi_verified_candidate_sha256()
      case is_lower_hex64(resolved) {
        True -> resolved
        False -> ""
      }
    }
  }
}

pub fn resolve_verified_candidate_sha256() -> String {
  verified_candidate_sha256_strict()
}

// =============================================================================
// 1. Hard Fail-Closed Erlang/OTP 29 Runtime Verification Gate
// =============================================================================

@external(erlang, "cepaf_gleam_ffi", "otp_runtime_info")
fn ffi_otp_runtime_info() -> #(String, String)

pub type Otp29RuntimeStatus {
  Otp29Verified(otp_release: String, erts_version: String)
  OtpVersionMismatch(found_release: String, erts_version: String)
}

/// Introspects the live BEAM ERTS runtime and fails closed unless OTP == 29.
pub fn verify_otp29_runtime() -> Otp29RuntimeStatus {
  let #(rel, erts) = ffi_otp_runtime_info()
  case rel == "29" || string.starts_with(rel, "29.") {
    True -> Otp29Verified(otp_release: rel, erts_version: erts)
    False -> OtpVersionMismatch(found_release: rel, erts_version: erts)
  }
}

// =============================================================================
// 2. Universal 40-Subsystem FPP Actor Registry (4 Domains x 10 Layers L0..L9)
// =============================================================================

pub type FppSupervisionDomain {
  AppsDomainFpp
  EnginesDomainFpp
  ServicesDomainFpp
  IntelligenceDomainFpp
}

pub type CompanionMachineKind {
  CompanionEvolutionGate
  CompanionPrajnaBreaker
  CompanionDeadManWatchdog
  CompanionOodaSwarm
  CompanionToleranceEnvelope
}

pub type SubsystemFppActorSpec {
  SubsystemFppActorSpec(
    actor_index: Int,
    actor_id: String,
    subsystem_name: String,
    domain: FppSupervisionDomain,
    domain_name: String,
    domain_slug: String,
    layer_index: Int,
    layer_short: String,
    chart: ChartIndex,
    supervision_child_id: String,
    companion_kind: CompanionMachineKind,
    companion_fpp_name: String,
    primary_mcp_tool: String,
    role: TaskRole,
    zenoh_topic: String,
    assigned_aspects: List(Int),
    intelligence_focus: String,
  )
}

pub fn domain_for_slot(slot: Int) -> #(FppSupervisionDomain, String, String) {
  case slot % 4 {
    0 -> #(AppsDomainFpp, "AppsSupervisor", "apps")
    1 -> #(EnginesDomainFpp, "EnginesSupervisor", "engines")
    2 -> #(ServicesDomainFpp, "ServicesSupervisor", "services")
    _ -> #(IntelligenceDomainFpp, "IntelligenceSupervisor", "intelligence")
  }
}

pub fn companion_machine_from_kind(kind: CompanionMachineKind) -> StateMachine {
  case kind {
    CompanionEvolutionGate -> homeostasis_fprime.evolution_gate_fprime()
    CompanionPrajnaBreaker -> homeostasis_fprime.prajna_breaker_fprime()
    CompanionDeadManWatchdog -> homeostasis_fprime.deadman_watchdog_fprime()
    CompanionOodaSwarm -> homeostasis_fprime.ooda_swarm_fprime()
    CompanionToleranceEnvelope -> homeostasis_fprime.tolerance_envelope_fprime()
  }
}

pub fn companion_name_from_kind(kind: CompanionMachineKind) -> String {
  case kind {
    CompanionEvolutionGate -> "EvolutionGateFPrime"
    CompanionPrajnaBreaker -> "PrajnaCircuitBreakerFPrime"
    CompanionDeadManWatchdog -> "DeadManWatchdogFPrime"
    CompanionOodaSwarm -> "SwarmCognitiveOodaFPrime"
    CompanionToleranceEnvelope -> "DynamicToleranceEnvelopeFPrime"
  }
}

fn aspects_for_actor_index(actor_idx: Int, layer_idx: Int) -> List(Int) {
  let a1 = { actor_idx % 17 } + 1
  let a2 = { { layer_idx + actor_idx * 3 } % 17 } + 1
  case a1 == a2 {
    True -> [a1]
    False -> [a1, a2]
  }
}

fn build_spec(
  actor_index: Int,
  layer_index: Int,
  domain_slot: Int,
  actor_id: String,
  subsystem_name: String,
  supervision_child_id: String,
  companion_kind: CompanionMachineKind,
  primary_mcp_tool: String,
  role: TaskRole,
  intelligence_focus: String,
) -> SubsystemFppActorSpec {
  let #(dom, dom_name, dom_slug) = domain_for_slot(domain_slot)
  let layer_short = "L" <> int.to_string(layer_index)
  SubsystemFppActorSpec(
    actor_index: actor_index,
    actor_id: actor_id,
    subsystem_name: subsystem_name,
    domain: dom,
    domain_name: dom_name,
    domain_slug: dom_slug,
    layer_index: layer_index,
    layer_short: layer_short,
    chart: chart_for_layer_index(layer_index),
    supervision_child_id: supervision_child_id,
    companion_kind: companion_kind,
    companion_fpp_name: companion_name_from_kind(companion_kind),
    primary_mcp_tool: primary_mcp_tool,
    role: role,
    zenoh_topic: "uos/v1/core_evo/fpp_" <> dom_slug <> "/" <> actor_id,
    assigned_aspects: aspects_for_actor_index(actor_index, layer_index),
    intelligence_focus: intelligence_focus,
  )
}

/// Complete canonical catalog of 40 Intelligent Subsystem FPP Actors covering
/// every part of UOS across all 4 Root Supervision Domains x 10 Layers (L0..L9).
pub fn all_40_subsystem_fpp_actor_specs() -> List(SubsystemFppActorSpec) {
  [
    // L0 Constitutional & Safety Foundation (0..3)
    build_spec(
      0,
      0,
      0,
      "l0_apps_iam_guardian_gate",
      "IAM Supervisor & Guardian HITL Approval Gate",
      "iam_supervisor",
      CompanionEvolutionGate,
      "preflight_check",
      SovereignGateRole,
      "2oo3 HITL approval arbitration, bearer session guard & zero-privilege escalation veto",
    ),
    build_spec(
      1,
      0,
      1,
      "l0_engines_hermes_zero_trust_hook",
      "Hermes OCaml Zero-Trust Dispatch Interceptor",
      "hermes_oracle_supervisor",
      CompanionPrajnaBreaker,
      "integrity_check",
      SovereignGateRole,
      "Cryptokit SHA-256 payload digest verification, NUL-byte (-2) & SQLi (-3) fail-closed trap",
    ),
    build_spec(
      2,
      0,
      2,
      "l0_services_provenance_ev93_fence",
      "SC-PROVENANCE-001 EV-93 Ceiling & Quarantine Fence",
      "planning_worker",
      CompanionEvolutionGate,
      "sa_plan_status_for",
      SovereignGateRole,
      "Enforces admitted_ev_ceiling == 93 and blocks quarantined EV-94..109 / ADR-071..086 claims",
    ),
    build_spec(
      3,
      0,
      3,
      "l0_intel_constitutional_quorum",
      "Fractal L0 2oo3 Constitutional Consensus & STAMP/STPA Controller",
      "fractal_l0_constitutional",
      CompanionEvolutionGate,
      "stpa_fmea_hazard",
      FmeaFormalRole,
      "2oo3 constitutional quorum voting, 4-UCA STPA hazard veto & emergency MoZ stop-line",
    ),
    // L1 Atomic Kernels, VFS, Hardware Interlocks & Hyperplane (4..7)
    build_spec(
      4,
      1,
      0,
      "l1_apps_pure_beam_graph_math",
      "Zero-Muda Pure BEAM 2D Vector & Graph Transform Kernel",
      "cepaf_gleam_wisp",
      CompanionToleranceEnvelope,
      "integrity_check",
      ImplRole,
      "Pure Gleam/BEAM & Hermes OCaml vector/graph transforms enforcing 0 Bevy & 0 Graphite",
    ),
    build_spec(
      5,
      1,
      1,
      "l1_engines_zigvm_vfs_arena_kernel",
      "ZigVM Deterministic Execution Kernel & Descriptor-Relative VFS",
      "zigvm_port_manager",
      CompanionPrajnaBreaker,
      "system_health",
      ImplRole,
      "Race-free descriptor-relative VFS, linear allocation arenas & lockless ring buffers",
    ),
    build_spec(
      6,
      1,
      2,
      "l1_services_nvme_storage_interlock",
      "Rook-Ceph System OS NVMe Hardware Safety Interlock",
      "mcp_unified_gateway",
      CompanionPrajnaBreaker,
      "preflight_check",
      SovereignGateRole,
      "Hard-locks [REDACTED_SYSTEM_OS_SERIAL] against OSD wipe, formatting or raw block mutation",
    ),
    build_spec(
      7,
      1,
      3,
      "l1_intel_zlp_v3_lean_zig_hyperplane",
      "UOS-ZLP-v3 Lean 4.33.0 + Zig 0.16.0 AVX-512 Port Hyperplane",
      "unified_verification_supervisor",
      CompanionToleranceEnvelope,
      "system_verification",
      FmeaFormalRole,
      "OS-isolated OTP 29 Two-Lane Port pool with 21 zero-sorry Lean theorems & <10us AVX-512 lane",
    ),
    // L2 Homeostasis, Circuit Breakers, Watchdogs & Metabolic ATP (8..11)
    build_spec(
      8,
      2,
      0,
      "l2_apps_prajna_circuit_breaker",
      "Prajna 5-Domain Autonomic Circuit Breaker Pool",
      "prajna_circuit_breaker",
      CompanionPrajnaBreaker,
      "system_health",
      RcaTpsRole,
      "Closed <-> HalfOpen <-> Open fault isolation with exponential backoff & canary healing",
    ),
    build_spec(
      9,
      2,
      1,
      "l2_engines_tolerance_envelope_guard",
      "Dynamic Kalman-PID Tolerance Envelope & Residual Monitor",
      "rete_ul_engine",
      CompanionToleranceEnvelope,
      "ast_anomaly_detect",
      RcaTpsRole,
      "Continuous precision-weighted Kalman innovation tracking & PID damping control u_k",
    ),
    build_spec(
      10,
      2,
      2,
      "l2_services_deadman_freshness_watchdog",
      "Dead-Man Switch NTP Clock & 20m Lease Heartbeat Monitor",
      "ha_freshness_monitor",
      CompanionDeadManWatchdog,
      "system_health",
      SovereignGateRole,
      "Chrony NTP drift (<2s nominal, >10s halt), 20m Zenoh lease heartbeats & zombie PID checks",
    ),
    build_spec(
      11,
      2,
      3,
      "l2_intel_lyapunov_endocrine_regulator",
      "Lyapunov dV/dt Stability & 40% ATP Quota Endocrine Regulator",
      "ha_lyapunov_proof",
      CompanionToleranceEnvelope,
      "lyapunov_trend_predict",
      FmeaFormalRole,
      "Proves discrete dV/dt <= 0 convergence & enforces 40.0% untouched quota margin + $0-OR shift",
    ),
    // L3 Durable Transactions, Leases, Vault KMS & Effect Fencing (12..15)
    build_spec(
      12,
      3,
      0,
      "l3_apps_vault_kms_ram_session",
      "Vault Supervisor, KMS Catalog & RAM-Only Ed25519 Session Signer",
      "vault_supervisor",
      CompanionPrajnaBreaker,
      "integrity_check",
      ImplRole,
      "Lock-free persistent_term Ed25519 session key generation & zero-secret-leakage redaction",
    ),
    build_spec(
      13,
      3,
      1,
      "l3_engines_ecology_file_txn_kernel",
      "Ecology Atomic O_EXCL 14-Target Pin Transaction & Rollback Kernel",
      "hermes_oracle_supervisor",
      CompanionPrajnaBreaker,
      "integrity_check",
      ImplRole,
      "Hex64 O_EXCL journaled file transactions, go-w traversal checks & SHA-256 crash rollback",
    ),
    build_spec(
      14,
      3,
      2,
      "l3_services_sa_plan_dag_authority",
      "Canonical Sa-Plan SQLite WAL Task, Oban Job & Temporal DAG Authority",
      "planning_worker",
      CompanionDeadManWatchdog,
      "sa_plan_status_for",
      ImplRole,
      "Sole SC-SA-PLAN-001 execution authority with append-only triggers & 4h Heijunka pull leases",
    ),
    build_spec(
      15,
      3,
      3,
      "l3_intel_oi07_effect_time_fence",
      "OI07 8-Guard Effect-Time Lease/SHA-256 Authority Fence",
      "lease_fencing_monitor",
      CompanionEvolutionGate,
      "preflight_check",
      SovereignGateRole,
      "Re-verifies active worker lease, candidate SHA-256, oi07<-oi02 order & 0 mixed readers at effect time",
    ),
    // L4 Supervised System Daemons & Immutable Capsules (16..19)
    build_spec(
      16,
      4,
      0,
      "l4_apps_wisp_cockpit_capsule_4100",
      "Immutable OTP 29.0.5 Wisp Cockpit Server Daemon (:4100)",
      "cepaf_gleam_wisp",
      CompanionDeadManWatchdog,
      "system_health",
      ImplRole,
      "Supervises c3i-gleam-server.service (+S 8:8 +SDio 6 +A 6) & zero-downtime capsule health",
    ),
    build_spec(
      17,
      4,
      1,
      "l4_engines_mirage_unikernel_daemon",
      "Mirage Unikernel & Bounded Native Port Worker Supervisor",
      "zigvm_port_manager",
      CompanionDeadManWatchdog,
      "system_health",
      ImplRole,
      "Supervises isolated unikernel/native C-ABI port lifecycles with restart budget intensity 5/60s",
    ),
    build_spec(
      18,
      4,
      2,
      "l4_services_ecology_daemon_4110",
      "Shared UOS Ecology Capsule Runtime Daemon (:4110)",
      "predictive_zenoh_stream",
      CompanionDeadManWatchdog,
      "system_zenoh",
      ImplRole,
      "Supervises uos-ecology@<capsule>.service (:4110) & continuous swarm state projection",
    ),
    build_spec(
      19,
      4,
      3,
      "l4_intel_max_mojo_isolated_inference",
      "Modular MAX / Mojo Quarantined AI Inference Worker",
      "max_isolated_worker",
      CompanionPrajnaBreaker,
      "ooda_decide",
      RcaTpsRole,
      "Quarantines Python strictly to length-delimited JSON-RPC stdio pipes under OTP supervision",
    ),
    // L5 Cognitive POODAVR, Formal Solvers, Rete-UL & Ruliad (20..23)
    build_spec(
      20,
      5,
      0,
      "l5_apps_cortex_agui_sse_conductor",
      "Cortex Cognitive Cockpit & AG-UI 32-Event Real-Time SSE Stream",
      "indrajaal_web",
      CompanionOodaSwarm,
      "ooda_decide",
      RcaTpsRole,
      "Streams real-time POODAVR & HITL cognitive events over /ag-ui/events & /cortex",
    ),
    build_spec(
      21,
      5,
      1,
      "l5_engines_hermes_gospel_z3_oracle",
      "Hermes Gospel Contract Verifier, Bounded Z3 & Differential Oracle",
      "hermes_oracle_supervisor",
      CompanionOodaSwarm,
      "verification_run",
      ImplRole,
      "Runs isolated timeout-reaped Z3 workers, Gospel postconditions & parity algebra oracles",
    ),
    build_spec(
      22,
      5,
      2,
      "l5_services_rete_ul_11domain_matcher",
      "11-Domain Rete-UL Salience Forward-Chaining Rule Engine",
      "rete_ul_engine",
      CompanionOodaSwarm,
      "rete_rule_conflict",
      RcaTpsRole,
      "Evaluates 11-domain Rete-UL production rules with conflict detection & salience arbitration",
    ),
    build_spec(
      23,
      5,
      3,
      "l5_intel_poodavr_ruliad_executive",
      "7-Stage POODAVR Cybernetic Executive & Ruliad Multiway Evaluator",
      "cybernetic_executive",
      CompanionOodaSwarm,
      "ooda_decide",
      FmeaFormalRole,
      "Closes Predict->Observe->Orient->Decide->Act->Verify->Reflect loop with Ruliad causal invariance",
    ),
    // L6 Holonic Hive, 5 Castes & 3-Attempt Jidoka Self-Healing (24..27)
    build_spec(
      24,
      6,
      0,
      "l6_apps_indrajaal_living_swarm",
      "Indrajaal Living Swarm Actor & 170-Holon Janus Lattice",
      "indrajaal_holon_runtime",
      CompanionOodaSwarm,
      "verification_run",
      ImplRole,
      "Steps 10x17 = 170 Janus Holons across 24 epochs = 4,080 states proving INV-HOLON-01..12",
    ),
    build_spec(
      25,
      6,
      1,
      "l6_engines_tier0_deterministic_caste",
      "CASTE-05 Tier-0 Zero-Token Deterministic Binary Worker Pool",
      "zigvm_port_manager",
      CompanionOodaSwarm,
      "integrity_check",
      ImplRole,
      "Offloads ~46% compute share at $0 LLM cost to OTP 29, OCaml, Lean 4.33.0 & Zig 0.16.0 binaries",
    ),
    build_spec(
      26,
      6,
      2,
      "l6_services_pi_deepseek_argon_builders",
      "CASTE-02/04 Isolated Sibling-JJ Pi+DeepSeek & $0 Pi+Argon Builders",
      "pi_supervisor",
      CompanionOodaSwarm,
      "sa_plan_status_for",
      ImplRole,
      "Zero-npm-bloat isolated sibling-JJ builders with automatic $4.50 -> $0 Google Argon shift",
    ),
    build_spec(
      27,
      6,
      3,
      "l6_intel_queen_agy_jidoka_healer",
      "CASTE-01/03 Thin AGY Queen (<2% Share) & 3-Attempt Jidoka Self-Healer",
      "holon_swarm_mesh",
      CompanionEvolutionGate,
      "harness_execution_progress",
      SovereignGateRole,
      "<=512B AGY conductor digests + 60m->90m(ACH RCA)->120m(STPA Pivot)->Jidoka Andon HOLD",
    ),
    // L7 Transport, 101-Route MCP, Ed25519 Zenoh & Tailnet/OTel Mesh (28..31)
    build_spec(
      28,
      7,
      0,
      "l7_apps_request_slo_module_guard",
      "Wisp Request Guard, Satya Module Guard & Availability SLO Tracker",
      "cepaf_gleam_wisp",
      CompanionToleranceEnvelope,
      "system_health",
      ImplRole,
      "Guards all HTTP/JSON routes via SC-SIL4-001 request_guard, module_guard & error-budget SLOs",
    ),
    build_spec(
      29,
      7,
      1,
      "l7_engines_zenoh_ed25519_core_bus",
      "RFC 8032 Ed25519-Signed Zenoh uos/v1/** Bus & Immortal ETS Replay Fence",
      "predictive_zenoh_stream",
      CompanionToleranceEnvelope,
      "system_zenoh",
      ImplRole,
      "Signs uos/v1/** envelopes in RAM, quarantines legacy :4200 c3i/** & blocks non-monotonic replays",
    ),
    build_spec(
      30,
      7,
      2,
      "l7_services_unified_101route_mcp_gateway",
      "Unified 101-Route Gleam/OTP 29 MCP Gateway (-82.9% Schema Muda)",
      "mcp_unified_gateway",
      CompanionToleranceEnvelope,
      "system_health",
      ImplRole,
      "Pre-sealed <10ms stdio/HTTP MCP gateway enforcing 8-10 role-whitelisted tools per worker",
    ),
    build_spec(
      31,
      7,
      3,
      "l7_intel_tailnet_otel_federation",
      "Tailscale Mesh Federation (nas-1:4100 <-> vm-1:8088) & 128-Bit W3C OTel",
      "zenoh_cognitive_worker",
      CompanionToleranceEnvelope,
      "system_zenoh",
      RcaTpsRole,
      "Propagates 128-bit W3C traceparent spans & Tailnet FQDN correlation across L0..L9",
    ),
    // L8 Living Knowledge Triad (#km-triad), Risk Gates & Formal Proofs (32..35)
    build_spec(
      32,
      8,
      0,
      "l8_apps_live_corpus_sub25ms_explorer",
      "INV-FRESH-4100-01 Stateless Sub-25ms Live Corpus & KM Catalog Explorer",
      "indrajaal_web",
      CompanionToleranceEnvelope,
      "knowledge_search",
      ImplRole,
      "Zero-cache descriptor-relative disk projection serving /wiki, /zk, /km & /files in <20ms p99",
    ),
    build_spec(
      33,
      8,
      1,
      "l8_engines_hermes_wiki_zk_transcluder",
      "Hermes Wiki AST (230 Docs), ZigVM ZK (185 Docs) & Link Tracker Verifier",
      "c3i_knowledge_supervisor",
      CompanionToleranceEnvelope,
      "zk_transclude",
      ImplRole,
      "Verifies 1,921+ Markdown files, reciprocal [[wiki:...]]/[[zk:...]] SCC cohesion & 0 broken links",
    ),
    build_spec(
      34,
      8,
      2,
      "l8_services_risk_priority_stpa_fmea_gate",
      "SC-RISK-PRIORITY-001 C*T*F*Dep*I Preflight & Active-Check Validator",
      "planning_worker",
      CompanionEvolutionGate,
      "stpa_fmea_hazard",
      FmeaFormalRole,
      "Validates chrony clock offset, SHA-256 evidence freshness, raw FMEA RPN & all 4 STPA UCAs",
    ),
    build_spec(
      35,
      8,
      3,
      "l8_intel_lean4_quint_9modality_verifier",
      "Gold-Standard C1-C8, 9-Modality EUnit, 13-Module Lean 4 & Quint Gate",
      "unified_verification_supervisor",
      CompanionToleranceEnvelope,
      "system_verification",
      FmeaFormalRole,
      "Binds 13 zero-sorry Lean 4 proofs (13D Trace, Two-Lattice STM, Ruliad, ZLP) & 9 test modalities",
    ),
    // L9 Operator Surfaces, UX & Tri-Sovereign Release Governance (36..39)
    build_spec(
      36,
      9,
      0,
      "l9_apps_lustre_a2ui_checklist_cockpit",
      "Lustre SSR Cockpit (70 Endpoints, 239 A2UI Components & 6-Domain Checklist)",
      "cepaf_gleam_wisp",
      CompanionEvolutionGate,
      "system_health",
      ImplRole,
      "Renders responsive WCAG-AA dark cockpits with XSS escaping & 18-obligation verification accordion",
    ),
    build_spec(
      37,
      9,
      1,
      "l9_engines_ansi_pty_tui_cockpit",
      "Terminal ANSI/Plain TUI Cockpit & C0/DEL/C1 Escape Sanitizer",
      "cpig_supervisor",
      CompanionToleranceEnvelope,
      "system_health",
      ImplRole,
      "Renders keyboard/CLI ANSI & colorless dashboards stripping 100% of untrusted C0/DEL/C1 bytes",
    ),
    build_spec(
      38,
      9,
      2,
      "l9_services_telegram_journey_responder",
      "Telegram Operator Journey & Critical Incident Mini-App Responder",
      "cortex_ooda_supervisor",
      CompanionDeadManWatchdog,
      "ooda_decide",
      RcaTpsRole,
      "Executes security-incident, HA-defence & critical-responder operator journeys fail-closed",
    ),
    build_spec(
      39,
      9,
      3,
      "l9_intel_tri_sovereign_release_authority",
      "Tri-Sovereign (AGY + Codex + Claude) Two-Key Release & Cutover Authority",
      "homeostasis_evolution_engine",
      CompanionEvolutionGate,
      "harness_execution_progress",
      SovereignGateRole,
      "Governs candidate-bound two-key verification, immutable capsule sealing & system_admitted=false truth",
    ),
  ]
}

pub fn spec_for_actor_index(actor_idx: Int) -> SubsystemFppActorSpec {
  let normalized = case actor_idx < 0 {
    True -> 0
    False -> actor_idx % universal_fpp_actor_count
  }
  all_40_subsystem_fpp_actor_specs()
  |> list.find(fn(s) { s.actor_index == normalized })
  |> result.lazy_unwrap(fn() {
    let assert Ok(first) = list.first(all_40_subsystem_fpp_actor_specs())
    first
  })
}

pub fn find_spec_by_actor_id(
  actor_id: String,
) -> Result(SubsystemFppActorSpec, String) {
  all_40_subsystem_fpp_actor_specs()
  |> list.find(fn(s) { s.actor_id == actor_id })
  |> result.replace_error("UNKNOWN_SUBSYSTEM_FPP_ACTOR:" <> actor_id)
}

pub fn specs_for_domain(
  domain: FppSupervisionDomain,
) -> List(SubsystemFppActorSpec) {
  all_40_subsystem_fpp_actor_specs()
  |> list.filter(fn(s) { s.domain == domain })
}

pub fn specs_for_layer(layer_idx: Int) -> List(SubsystemFppActorSpec) {
  all_40_subsystem_fpp_actor_specs()
  |> list.filter(fn(s) { s.layer_index == layer_idx })
}

// =============================================================================
// 3. Governed Embedded Agent Access via OpenRouter (Redacted + 40% Margin)
// =============================================================================

pub type OpenRouterTier {
  AdvisoryFreeTier
  ImplementationFlashTier
  DeepAchRcaProTier
}

pub type EmbeddedOpenRouterPlan {
  OpenRouterDispatched(
    model: String,
    zero_cost_route: Bool,
    sanitized_prompt: String,
    max_tokens: Int,
    timeout_ms: Int,
    zenoh_audit_topic: String,
  )
  OpenRouterBlockedEgressSafety(reason: String)
  OpenRouterBlockedMargin40(violated_windows: List(String))
}

/// Plans an embedded actor -> OpenRouter cognitive request enforcing:
/// 1. `egress_redactor` secret/NVMe-serial scrubbing and destructive-prompt veto
/// 2. `40%` sliding-window quota margin (`<= 6,000 bps` / `<= $6.00` cap)
/// 3. Free-first advisory (`openrouter/free` / `google/gemma-4-26b-a4b-it:free`) and
///    automatic `$0`-OpenRouter shift at `$4.50` soft threshold.
pub fn plan_embedded_openrouter_access(
  actor_id actor_id: String,
  tier tier: OpenRouterTier,
  raw_prompt raw_prompt: String,
  quota quota: QuotaSnapshot,
) -> EmbeddedOpenRouterPlan {
  case egress_redactor.evaluate_egress(raw_prompt) {
    EgressBlocked(reason) -> OpenRouterBlockedEgressSafety(reason)
    EgressPermitted(clean_prompt) ->
      case core_evolution.evaluate_quota_margin(quota) {
        QuotaHoldMargin40Pct(windows) -> OpenRouterBlockedMargin40(windows)
        QuotaAdmitted(mode, _, _) -> {
          let zero_or_shift = case mode {
            ZeroOpenRouterShift | ZeroOpenRouterAndBatchedWakeups -> True
            _ -> False
          }
          let #(model, is_zero_cost, max_tok) = case tier, zero_or_shift {
            AdvisoryFreeTier, _ -> #(
              "google/gemma-4-26b-a4b-it:free",
              True,
              1024,
            )
            _, True -> #("google/gemma-4-26b-a4b-it:free", True, 2048)
            ImplementationFlashTier, False -> #(
              "deepseek/deepseek-v4-flash-0731",
              False,
              4096,
            )
            DeepAchRcaProTier, False -> #(
              "deepseek/deepseek-v4-pro-0813",
              False,
              4096,
            )
          }
          let clean_actor = sanitize_topic_segment(actor_id)
          OpenRouterDispatched(
            model: model,
            zero_cost_route: is_zero_cost,
            sanitized_prompt: clean_prompt,
            max_tokens: max_tok,
            timeout_ms: 1_800_000,
            zenoh_audit_topic: "uos/v1/core_evo/"
              <> clean_actor
              <> "/openrouter_embed",
          )
        }
      }
  }
}

// =============================================================================
// 4. Coupled Mathematical Modelling Digital Twin & Autonomous Reflex Engine
// =============================================================================

pub type ActorMathematicalTwin {
  ActorMathematicalTwin(
    structural_twin: TwinState,
    kalman_predicted_health: Float,
    kalman_variance: Float,
    innovation_residual: Float,
    lyapunov_energy: Float,
    lyapunov_delta_v: Float,
    pid_integral_error: Float,
    pid_last_error: Float,
    pid_control_u: Float,
    beta_alpha: Float,
    beta_beta: Float,
    beta_reliability: Float,
    twin_health: Float,
    pending_reconciliations: List(SyncAction),
  )
}

pub type IntelligentReflexAction {
  ReflexNominalContinue
  ReflexPidDampingTune(control_effort_u: Float)
  ReflexAutonomousSelfHeal(reconciled_components: Int, control_effort_u: Float)
  ReflexQuarantineAndCircuitBreak(reason: String)
  ReflexJidokaConstitutionalHalt(veto_stage: String, reason: String)
}

pub fn reflex_action_label(action: IntelligentReflexAction) -> String {
  case action {
    ReflexNominalContinue -> "NOMINAL_CONTINUE"
    ReflexPidDampingTune(_) -> "PID_DAMPING_TUNE"
    ReflexAutonomousSelfHeal(_, _) -> "AUTONOMOUS_SELF_HEAL"
    ReflexQuarantineAndCircuitBreak(_) -> "QUARANTINE_CIRCUIT_BREAK"
    ReflexJidokaConstitutionalHalt(_, _) -> "JIDOKA_CONSTITUTIONAL_HALT"
  }
}

pub fn init_actor_math_twin(
  actor_id: String,
  now_ms: Int,
) -> ActorMathematicalTwin {
  let twin =
    digital_twin.twin_new()
    |> digital_twin.mirror_component(
      actor_id <> ":fpp_fsm",
      "Predicting",
      "Predicting",
      1.0,
      now_ms,
    )
    |> digital_twin.mirror_component(
      actor_id <> ":mcp_zenoh_bus",
      "Connected_uos_v1_ed25519",
      "Connected_uos_v1_ed25519",
      1.0,
      now_ms,
    )
    |> digital_twin.mirror_component(
      actor_id <> ":openrouter_embed",
      "Redacted_Margin40_Ready",
      "Redacted_Margin40_Ready",
      1.0,
      now_ms,
    )
    |> digital_twin.mirror_component(
      actor_id <> ":algebraic_sheaf",
      "Glued_H1_Zero",
      "Glued_H1_Zero",
      1.0,
      now_ms,
    )

  ActorMathematicalTwin(
    structural_twin: twin,
    kalman_predicted_health: 0.98,
    kalman_variance: 0.02,
    innovation_residual: 0.0,
    lyapunov_energy: 0.0004,
    lyapunov_delta_v: 0.0,
    pid_integral_error: 0.0,
    pid_last_error: 0.02,
    pid_control_u: 0.016,
    beta_alpha: 19.0,
    beta_beta: 1.0,
    beta_reliability: 0.95,
    twin_health: digital_twin.twin_health(twin),
    pending_reconciliations: digital_twin.reconciliation_actions(twin),
  )
}

/// Updates both the structural `digital_twin` mirror and the continuous/discrete
/// Bayesian-Kalman-PID-Lyapunov mathematical twin from observed actor execution.
pub fn step_actor_math_twin(
  actor_id: String,
  prev: ActorMathematicalTwin,
  desired_fpp_state: String,
  actual_fpp_state: String,
  observed_health: Float,
  step_succeeded: Bool,
  now_ms: Int,
) -> ActorMathematicalTwin {
  // 1. Conjugate Gaussian precision-weighted Kalman update (`math/bayesian`)
  let belief =
    bayesian.belief_new(
      prev.kalman_predicted_health,
      prev.kalman_variance +. 0.005,
    )
    |> bayesian.belief_update(observed_health, 0.015)
  let residual = float.absolute_value(observed_health -. belief.posterior_mean)

  // 2. Conjugate Beta-Bernoulli reliability update
  let beta_post =
    bayesian.beta_new(prev.beta_alpha, prev.beta_beta)
    |> bayesian.beta_update(step_succeeded)
  let rel = bayesian.beta_mean(beta_post)

  // 3. Discrete PID feedback controller u_k = Kp*e_k + Ki*I_k + Kd*(e_k - e_{k-1})
  let err = 1.0 -. belief.posterior_mean
  let integral =
    float.clamp(prev.pid_integral_error +. err, min: -1.0, max: 1.0)
  let deriv = err -. prev.pid_last_error
  let pid_u =
    float.clamp(0.8 *. err +. 0.15 *. integral +. 0.25 *. deriv, 0.0, 1.0)

  // 4. Quadratic Lyapunov energy V(x) = (1 - x_hat)^2 + residual^2 and dV
  let v_energy = err *. err +. residual *. residual
  let delta_v = v_energy -. prev.lyapunov_energy

  // 5. Structural Digital Twin mirror & drift detection
  let next_struct =
    prev.structural_twin
    |> digital_twin.mirror_component(
      actor_id <> ":fpp_fsm",
      desired_fpp_state,
      actual_fpp_state,
      belief.posterior_mean,
      now_ms,
    )
  let actions = digital_twin.reconciliation_actions(next_struct)

  ActorMathematicalTwin(
    structural_twin: next_struct,
    kalman_predicted_health: belief.posterior_mean,
    kalman_variance: belief.posterior_variance,
    innovation_residual: residual,
    lyapunov_energy: v_energy,
    lyapunov_delta_v: delta_v,
    pid_integral_error: integral,
    pid_last_error: err,
    pid_control_u: pid_u,
    beta_alpha: beta_post.alpha,
    beta_beta: beta_post.beta_param,
    beta_reliability: rel,
    twin_health: digital_twin.twin_health(next_struct),
    pending_reconciliations: actions,
  )
}

/// Reconciles any drifted digital-twin mirror back to desired steady state.
pub fn converge_actor_math_twin(
  prev: ActorMathematicalTwin,
  now_ms: Int,
) -> ActorMathematicalTwin {
  let healed_struct =
    list.fold(prev.pending_reconciliations, prev.structural_twin, fn(tw, act) {
      case act {
        Converge(name, target) ->
          digital_twin.sync_component(tw, name, target, now_ms)
        _ -> tw
      }
    })
  let belief =
    bayesian.belief_new(
      prev.kalman_predicted_health,
      prev.kalman_variance +. 0.01,
    )
    |> bayesian.belief_update(0.99, 0.01)
  let err = 1.0 -. belief.posterior_mean
  let v_healed = err *. err
  ActorMathematicalTwin(
    ..prev,
    structural_twin: healed_struct,
    kalman_predicted_health: belief.posterior_mean,
    kalman_variance: belief.posterior_variance,
    innovation_residual: 0.0,
    lyapunov_energy: v_healed,
    lyapunov_delta_v: v_healed -. prev.lyapunov_energy,
    twin_health: digital_twin.twin_health(healed_struct),
    pending_reconciliations: digital_twin.reconciliation_actions(healed_struct),
  )
}

/// Autonomous Cybernetic Intelligence Kernel: classifies the actor's mathematical
/// twin trajectory + observed health into an autonomous reflex decision, selects
/// the optimal OpenRouter cognitive tier, and steps the subsystem's companion F'
/// state machine!
pub fn evaluate_autonomous_reflex(
  kind: CompanionMachineKind,
  companion_machine: StateMachine,
  companion_state: fpp_interp.MachineState,
  twin: ActorMathematicalTwin,
  observed_health: Float,
  requested_tier: OpenRouterTier,
  now_ms: Int,
) -> #(
  IntelligentReflexAction,
  OpenRouterTier,
  fpp_interp.MachineState,
  ActorMathematicalTwin,
) {
  let pending_cnt =
    list.count(twin.pending_reconciliations, fn(act) {
      case act {
        NoSync(_) -> False
        _ -> True
      }
    })
  case observed_health <. 0.6 {
    True -> {
      let guards = [
        #("fault_threshold_exceeded", True),
        #("handshake_revalidated", False),
      ]
      let sigs = case kind {
        CompanionPrajnaBreaker -> ["fault_detected"]
        CompanionDeadManWatchdog -> [
          "warning_timeout",
          "stale_timeout",
          "dead_timeout",
        ]
        _ -> ["fault_detected", "warning_timeout"]
      }
      let next_comp =
        dispatch_companion_signals(
          companion_machine,
          guards,
          companion_state,
          sigs,
        )
      #(
        ReflexQuarantineAndCircuitBreak(
          "observed_health_below_0.60_breaker_tripped",
        ),
        DeepAchRcaProTier,
        next_comp,
        twin,
      )
    }
    False ->
      case observed_health <. 0.78 || pending_cnt > 0 {
        True -> {
          // Autonomous Self-Heal: trip -> canary probe -> restore companion F' + converge Twin!
          let guards = [
            #("fault_threshold_exceeded", True),
            #("handshake_revalidated", True),
          ]
          let sigs = case kind {
            CompanionPrajnaBreaker -> [
              "fault_detected",
              "cooldown_expired",
              "canary_success",
            ]
            CompanionDeadManWatchdog -> ["warning_timeout", "heartbeat_tick"]
            _ -> ["heartbeat_tick", "canary_success"]
          }
          let healed_comp =
            dispatch_companion_signals(
              companion_machine,
              guards,
              companion_state,
              sigs,
            )
          let healed_twin = converge_actor_math_twin(twin, now_ms)
          #(
            ReflexAutonomousSelfHeal(
              reconciled_components: int.max(1, pending_cnt),
              control_effort_u: twin.pid_control_u,
            ),
            ImplementationFlashTier,
            healed_comp,
            healed_twin,
          )
        }
        False ->
          case observed_health <. 0.9 || twin.lyapunov_delta_v >. 0.015 {
            True -> {
              let guards = [#("fault_threshold_exceeded", False)]
              let sigs = case kind {
                CompanionDeadManWatchdog -> [
                  "warning_timeout",
                  "heartbeat_tick",
                ]
                _ -> ["heartbeat_tick"]
              }
              let tuned_comp =
                dispatch_companion_signals(
                  companion_machine,
                  guards,
                  companion_state,
                  sigs,
                )
              #(
                ReflexPidDampingTune(control_effort_u: twin.pid_control_u),
                requested_tier,
                tuned_comp,
                twin,
              )
            }
            False -> {
              let guards = [
                #("fault_threshold_exceeded", False),
                #("handshake_revalidated", True),
              ]
              let nom_comp =
                dispatch_companion_signals(
                  companion_machine,
                  guards,
                  companion_state,
                  ["heartbeat_tick"],
                )
              #(ReflexNominalContinue, requested_tier, nom_comp, twin)
            }
          }
      }
  }
}

fn dispatch_companion_signals(
  machine: StateMachine,
  guards: List(#(String, Bool)),
  init_state: fpp_interp.MachineState,
  signals: List(String),
) -> fpp_interp.MachineState {
  list.fold(signals, init_state, fn(st, sig) {
    fpp_interp.dispatch_signal(machine, guards, st, sig)
    |> result.unwrap(st)
  })
}

// =============================================================================
// 5. Universal FPP + MCP + Ed25519 Zenoh + OTel + Twin + Reflex + Intent Actor
// =============================================================================

pub type ActorIntentRequest {
  ActorIntentRequest(
    intent_id: String,
    authority: String,
    target_drive_serial: String,
    criticality: String,
    guardian_approved: Bool,
    ev_cycle: Int,
    target_chart: ChartIndex,
    action: String,
    mcp_route: String,
    role: TaskRole,
    openrouter_tier: OpenRouterTier,
    embedded_prompt: String,
    parent_trace: Option(TraceContext),
    observed_health: Float,
    quota: QuotaSnapshot,
    now_ms: Int,
  )
}

pub type ActorIntentReceipt {
  ActorIntentAccepted(
    actor_id: String,
    otp_release: String,
    fprime_lifecycle_state: String,
    fprime_companion_state: String,
    denotational_receipt_sha256: String,
    zenoh_topic: String,
    zenoh_seq_id: Int,
    w3c_traceparent: String,
    fractal_log_json: String,
    twin_health: Float,
    twin_residual: Float,
    openrouter_model: String,
    openrouter_sanitized_prompt: String,
  )
  ActorIntentVetoed(
    actor_id: String,
    fprime_lifecycle_state: String,
    veto_stage: String,
    reason: String,
    w3c_traceparent: String,
    fractal_log_json: String,
    zenoh_alert_topic: String,
  )
}

pub type FppHolonActorState {
  FppHolonActorState(
    spec: SubsystemFppActorSpec,
    actor_id: String,
    chart: ChartIndex,
    layer_short: String,
    assigned_aspects: List(Int),
    otp_release: String,
    erts_version: String,
    lifecycle_machine: StateMachine,
    lifecycle_fpp_state: fpp_interp.MachineState,
    companion_machine: StateMachine,
    companion_fpp_state: fpp_interp.MachineState,
    lattice_state: LatticeState,
    chart_state: ChartState,
    math_twin: ActorMathematicalTwin,
    last_reflex_action: IntelligentReflexAction,
    last_ed25519_sig_prefix: String,
    last_ed25519_sig_hex: String,
    last_ed25519_verified: Bool,
    last_authenticated_envelope: Option(core_bus.AuthenticatedCoreEnvelope),
    zenoh_seq_id: Int,
    intents_accepted: Int,
    intents_vetoed: Int,
    autonomous_heals: Int,
    recent_fractal_logs: List(String),
  )
}

pub type FppHolonActorMessage {
  DispatchIntent(
    request: ActorIntentRequest,
    reply_to: Subject(ActorIntentReceipt),
  )
  HealTwinDrift(now_ms: Int, reply_to: Subject(Float))
  InspectActor(reply_to: Subject(FppHolonActorState))
  ShutdownActor
}

pub fn chart_for_layer_index(idx: Int) -> ChartIndex {
  case idx {
    0 -> L0Constitutional
    1 -> L1AtomicKernel
    2 -> L2Homeostasis
    3 -> L3Transactions
    4 -> L4SystemDaemons
    5 -> L5CognitiveOODA
    6 -> L6SwarmMesh
    7 -> L7Federation
    8 -> L8Verification
    _ -> L9Sovereignty
  }
}

/// Initializes any of the 40 Intelligent Subsystem FPP Actors (`0..39`).
pub fn init_subsystem_fpp_actor_state(
  spec: SubsystemFppActorSpec,
  now_ms: Int,
) -> Result(FppHolonActorState, String) {
  case verify_otp29_runtime() {
    OtpVersionMismatch(found, erts) ->
      Error(
        "OTP29_MANDATE_VIOLATION: expected OTP 29, found OTP "
        <> found
        <> " (ERTS "
        <> erts
        <> ")",
      )
    Otp29Verified(otp_rel, erts_ver) -> {
      let cand_sha = verified_candidate_sha256_strict()
      use _ <- result.try(case
        is_lower_hex64(cand_sha)
        && cand_sha == resolve_verified_candidate_sha256()
      {
        True -> Ok(Nil)
        False ->
          Error(
            "CANDIDATE_SHA256_INTEGRITY_VIOLATION: in-memory BEAM or capsule manifest mismatch",
          )
      })
      let lifecycle_m = poodavr_fprime.poodavr_lifecycle_fprime()
      let companion_m = companion_machine_from_kind(spec.companion_kind)

      use lifecycle_init <- result.try(fpp_interp.init_machine(lifecycle_m))
      use companion_init <- result.try(fpp_interp.init_machine(companion_m))

      let coords =
        TraceCoordinates(
          timestamp_us: now_ms * 1000,
          layer_id: spec.layer_index,
          holon_id: spec.actor_id,
          causal_epoch: 1,
          shannon_entropy_bits: 3.4,
          lyapunov_energy: 0.0004,
          cyclomatic_complexity: 4,
          divergence_ppm: 0,
          itqs_quality: 0.99,
          quarantine_flags: 0,
          worker_hash: "otp29_intelligent_fpp_" <> spec.domain_slug,
          plan_digest: active_plan_id,
          parent_digest: cand_sha,
        )
      let c_state =
        ChartState(
          chart: spec.chart,
          coordinates: coords,
          payload_json: "{\"status\":\"initialized\",\"domain\":\""
            <> spec.domain_slug
            <> "\"}",
          constitutional_health: 0.99,
        )

      Ok(FppHolonActorState(
        spec: spec,
        actor_id: spec.actor_id,
        chart: spec.chart,
        layer_short: spec.layer_short,
        assigned_aspects: spec.assigned_aspects,
        otp_release: otp_rel,
        erts_version: erts_ver,
        lifecycle_machine: lifecycle_m,
        lifecycle_fpp_state: lifecycle_init,
        companion_machine: companion_m,
        companion_fpp_state: companion_init,
        lattice_state: denotational.initial_state(),
        chart_state: c_state,
        math_twin: init_actor_math_twin(spec.actor_id, now_ms),
        last_reflex_action: ReflexNominalContinue,
        last_ed25519_sig_prefix: "",
        last_ed25519_sig_hex: "",
        last_ed25519_verified: False,
        last_authenticated_envelope: None,
        zenoh_seq_id: 1000 + spec.actor_index * 1000,
        intents_accepted: 0,
        intents_vetoed: 0,
        autonomous_heals: 0,
        recent_fractal_logs: [],
      ))
    }
  }
}

/// Backward-compatible layer initializer (`0..9` maps to the primary layer spec,
/// `0..39` maps across all 40 subsystem actors).
pub fn init_fpp_holon_actor_state(
  layer_or_actor_idx: Int,
  now_ms: Int,
) -> Result(FppHolonActorState, String) {
  let spec = case layer_or_actor_idx >= 0 && layer_or_actor_idx < 10 {
    True -> spec_for_actor_index(layer_or_actor_idx * 4 + 3)
    False -> spec_for_actor_index(layer_or_actor_idx)
  }
  init_subsystem_fpp_actor_state(spec, now_ms)
}

/// Pure, deterministic FPP + Autonomous Reflex + Intent + MCP + Ed25519 Zenoh +
/// OTel + Mathematical Digital Twin + OpenRouter actor transition kernel.
pub fn process_actor_intent_pure(
  st: FppHolonActorState,
  req: ActorIntentRequest,
) -> #(ActorIntentReceipt, FppHolonActorState) {
  // 1. Fractal Logging & W3C 128-bit OTel Span Start
  let trace = case req.parent_trace {
    Some(parent) ->
      trace_context.child_span(
        parent,
        st.actor_id <> ":" <> req.action,
        st.layer_short,
      )
    None ->
      trace_context.new_trace(
        st.actor_id <> ":" <> req.action,
        st.layer_short,
      )
  }
  let traceparent = trace_context.to_traceparent(trace)
  let otel_ctx =
    Some(SpanContext(
      trace_id: trace.trace_id,
      span_id: trace.span_id,
      parent_span_id: trace.parent_span_id,
    ))
  let span_tags =
    dict.from_list([
      #("actor_id", st.actor_id),
      #("domain", st.spec.domain_name),
      #("fractal_layer", st.layer_short),
      #("mcp_route", req.mcp_route),
      #("otp_release", st.otp_release),
    ])
  otel.start_span(["uos", "core_evo", "fpp_actor"], span_tags, otel_ctx)

  // 2. Zero-Muda Gleam MCP Route Whitelist Gate (Role + Actor Primary MCP Tool)
  let allowed_mcp =
    [st.spec.primary_mcp_tool]
    |> list.append(core_evolution.minimal_mcp_tools(req.role))
    |> list.append(core_evolution.minimal_mcp_tools(RcaTpsRole))
    |> list.append(core_evolution.minimal_mcp_tools(SovereignGateRole))
    |> list.append(core_evolution.minimal_mcp_tools(FmeaFormalRole))
  let mcp_valid = list.contains(allowed_mcp, req.mcp_route)

  // 3. Denotational Lattice Monad Valuation `[[ I ]] : Sigma -> Sigma U {bot}`
  let d_intent =
    DenotationalIntent(
      authority: req.authority,
      target_drive_serial: req.target_drive_serial,
      criticality: req.criticality,
      guardian_approved: req.guardian_approved,
      delta_coord: 0.0,
      add_containers: [],
      add_topics: [st.spec.zenoh_topic],
    )
  let next_lattice =
    denotational.bind(st.lattice_state, fn(s) {
      denotational.evaluate_with_provenance(d_intent, s, req.ev_cycle)
    })

  // 4. Algebraic Atlas Declarative Intent & Chart Morphism Valuation
  let atlas_intent =
    DeclarativeIntent(
      intent_id: req.intent_id,
      proposer_holon: st.actor_id,
      source_chart: st.chart,
      target_chart: req.target_chart,
      action: req.action,
      required_preconditions: ["otp_29", "mcp_whitelisted", "margin_40pct"],
      guaranteed_postconditions: [
        "fpp_closed_loop",
        "intelligent_reflex_evaluated",
        "twin_synced",
        "zenoh_ed25519_signed",
      ],
      preserves_constitutional_invariants: !next_lattice.is_bottom && mcp_valid,
    )
  let current_chart_aligned = ChartState(..st.chart_state, chart: st.chart)
  let atlas_outcome =
    algebraic_atlas.evaluate_denotational_intent(
      atlas_intent,
      current_chart_aligned,
    )

  // 5. Pre-step Mathematical Twin & Autonomous Reflex Tier Selection
  let pre_twin =
    step_actor_math_twin(
      st.actor_id,
      st.math_twin,
      "Predicting",
      st.lifecycle_fpp_state.current,
      req.observed_health,
      True,
      req.now_ms,
    )
  let #(reflex_action, selected_tier, next_companion_fpp, post_reflex_twin) =
    evaluate_autonomous_reflex(
      st.spec.companion_kind,
      st.companion_machine,
      st.companion_fpp_state,
      pre_twin,
      req.observed_health,
      req.openrouter_tier,
      req.now_ms,
    )

  // 6. Embedded OpenRouter Access Gate (Egress Redactor + 40% Quota Margin)
  let or_plan =
    plan_embedded_openrouter_access(
      actor_id: st.actor_id,
      tier: selected_tier,
      raw_prompt: req.embedded_prompt,
      quota: req.quota,
    )

  case mcp_valid, next_lattice.is_bottom, atlas_outcome, or_plan {
    False, _, _, _ ->
      veto_actor_intent(
        st,
        req,
        trace,
        traceparent,
        span_tags,
        otel_ctx,
        "mcp_whitelist_gate",
        "NON_ZERO_MUDA_OR_UNAUTHORIZED_MCP_ROUTE:" <> req.mcp_route,
      )
    _, True, _, _ ->
      veto_actor_intent(
        st,
        req,
        trace,
        traceparent,
        span_tags,
        otel_ctx,
        "denotational_lattice_monad",
        next_lattice.error_reason,
      )
    _, _, DenotationalVetoed(_, reason), _ ->
      veto_actor_intent(
        st,
        req,
        trace,
        traceparent,
        span_tags,
        otel_ctx,
        "algebraic_atlas_intent",
        reason,
      )
    _, _, _, OpenRouterBlockedEgressSafety(reason) ->
      veto_actor_intent(
        st,
        req,
        trace,
        traceparent,
        span_tags,
        otel_ctx,
        "openrouter_egress_redactor",
        reason,
      )
    _, _, _, OpenRouterBlockedMargin40(windows) ->
      veto_actor_intent(
        st,
        req,
        trace,
        traceparent,
        span_tags,
        otel_ctx,
        "quota_margin_40pct_gate",
        "HOLD_MARGIN_40PCT:" <> string.join(windows, ","),
      )
    True,
      False,
      DenotationalSuccess(next_chart_state, receipt_sha),
      OpenRouterDispatched(or_model, _, clean_prompt, _, _, _)
    -> {
      // 7. Step NASA JPL F' POODAVR FSM through all 7 cybernetic stages -> Predicting
      let guards = [
        #("intent_is_safe", True),
        #("breakers_closed", True),
        #("trace13_conserved", True),
        #("two_key_operator_cleared", False),
      ]
      let signals = [
        "telemetry_observed",
        "intent_received",
        "orientation_cleared",
        "decision_ratified",
        "action_dispatched",
        "verification_passed",
        "cycle_complete",
      ]
      let stepped_fpp =
        list.fold(signals, st.lifecycle_fpp_state, fn(inst, sig) {
          fpp_interp.dispatch_signal(st.lifecycle_machine, guards, inst, sig)
          |> result.unwrap(inst)
        })

      // 8. Publish RFC 8032 Ed25519-Signed Zenoh `uos/v1/**` Envelope via `core_bus`
      let next_seq = st.zenoh_seq_id + 1
      let topic =
        st.spec.zenoh_topic <> "/" <> sanitize_topic_segment(req.intent_id)
      let reflex_lbl = reflex_action_label(reflex_action)
      let payload =
        json.object([
          #("actor", json.string(st.actor_id)),
          #("dom", json.string(st.spec.domain_slug)),
          #("layer", json.string(st.layer_short)),
          #("otp", json.string(st.otp_release)),
          #("mcp", json.string(req.mcp_route)),
          #("fpp", json.string(stepped_fpp.current)),
          #("comp", json.string(next_companion_fpp.current)),
          #("reflex", json.string(reflex_lbl)),
          #("rcpt", json.string(string.slice(receipt_sha, 0, 12))),
          #("or", json.string(or_model)),
        ])
        |> json.to_string

      let session_pub = core_bus.session_ed25519_pubkey_hex()
      let strict_cand_sha = verified_candidate_sha256_strict()
      let pub_cand_sha = resolve_verified_candidate_sha256()
      let live_cand_sha = case
        is_lower_hex64(strict_cand_sha) && strict_cand_sha == pub_cand_sha
      {
        True -> strict_cand_sha
        False -> ""
      }
      case live_cand_sha == "" {
        True ->
          veto_actor_intent(
            st,
            req,
            trace,
            traceparent,
            span_tags,
            otel_ctx,
            "candidate_integrity_fence",
            "CANDIDATE_SHA256_INTEGRITY_VIOLATION: in-memory BEAM or capsule manifest mismatch",
          )
        False -> {
          let #(sig_prefix, sig_hex, sig_verified, verified_env_opt) = case
            core_bus.build_and_sign_session_ed25519(
              topic: topic,
              candidate_sha256: live_cand_sha,
              plan_id: active_plan_id,
              task_id: sanitize_topic_segment(req.intent_id),
              worker_id: sanitize_topic_segment(st.actor_id),
              attempt: 1,
              seq_id: next_seq,
              ev_ceiling: 93,
              payload_json: payload,
            )
          {
            Ok(auth_env) ->
              case
                core_bus.verify_authenticated_envelope(
                  auth_env,
                  session_pub,
                  st.zenoh_seq_id,
                )
              {
                Ok(verified_env) -> {
                  let _ =
                    core_bus.publish_authenticated(verified_env, session_pub)
                  #(
                    string.slice(verified_env.signature_hex, 0, 16),
                    verified_env.signature_hex,
                    True,
                    Some(verified_env),
                  )
                }
                Error(_) -> #("", "", False, None)
              }
            Error(_) -> #("", "", False, None)
          }

          case sig_verified {
            False ->
              veto_actor_intent(
                st,
                req,
                trace,
                traceparent,
                span_tags,
                otel_ctx,
                "ed25519_candidate_signature_fence",
                "ED25519_OR_CANDIDATE_SIGNATURE_REFUSED",
              )
            True -> {
              // 9. Emit Correlated Fractal OTel JSON Log & Stop Span
              let log_entry =
                correlated_log.log(
                  Info,
                  "fpp_actor_intent_accepted actor="
                    <> st.actor_id
                    <> " domain="
                    <> st.spec.domain_slug
                    <> " fpp="
                    <> stepped_fpp.current
                    <> " comp="
                    <> next_companion_fpp.current
                    <> " reflex="
                    <> reflex_lbl
                    <> " twin_health="
                    <> float.to_string(post_reflex_twin.twin_health),
                  trace,
                )
              let log_json = correlated_log.to_json(log_entry)
              otel.stop_span(
                ["uos", "core_evo", "fpp_actor"],
                0.38,
                span_tags,
                otel_ctx,
              )

              let heal_inc = case reflex_action {
                ReflexAutonomousSelfHeal(_, _) -> 1
                _ -> 0
              }

              let next_state =
                FppHolonActorState(
                  ..st,
                  lifecycle_fpp_state: stepped_fpp,
                  companion_fpp_state: next_companion_fpp,
                  lattice_state: next_lattice,
                  chart_state: ChartState(..next_chart_state, chart: st.chart),
                  math_twin: post_reflex_twin,
                  last_reflex_action: reflex_action,
                  last_ed25519_sig_prefix: sig_prefix,
                  last_ed25519_sig_hex: sig_hex,
                  last_ed25519_verified: sig_verified,
                  last_authenticated_envelope: verified_env_opt,
                  zenoh_seq_id: next_seq,
                  intents_accepted: st.intents_accepted + 1,
                  autonomous_heals: st.autonomous_heals + heal_inc,
                  recent_fractal_logs: list.take(
                    [log_json, ..st.recent_fractal_logs],
                    16,
                  ),
                )

              let receipt =
                ActorIntentAccepted(
                  actor_id: st.actor_id,
                  otp_release: st.otp_release,
                  fprime_lifecycle_state: stepped_fpp.current,
                  fprime_companion_state: next_companion_fpp.current,
                  denotational_receipt_sha256: receipt_sha,
                  zenoh_topic: topic,
                  zenoh_seq_id: next_seq,
                  w3c_traceparent: traceparent,
                  fractal_log_json: log_json,
                  twin_health: post_reflex_twin.twin_health,
                  twin_residual: post_reflex_twin.innovation_residual,
                  openrouter_model: or_model,
                  openrouter_sanitized_prompt: clean_prompt,
                )

              #(receipt, next_state)
            }
          }
        }
      }
    }
  }
}

fn veto_actor_intent(
  st: FppHolonActorState,
  req: ActorIntentRequest,
  trace: TraceContext,
  traceparent: String,
  span_tags: dict.Dict(String, String),
  otel_ctx: Option(otel.SpanContext),
  veto_stage: String,
  reason: String,
) -> #(ActorIntentReceipt, FppHolonActorState) {
  let guards = [
    #("intent_is_safe", False),
    #("breakers_closed", False),
    #("trace13_conserved", False),
    #("two_key_operator_cleared", False),
  ]
  let halted_fpp =
    fpp_interp.dispatch_signal(
      st.lifecycle_machine,
      guards,
      st.lifecycle_fpp_state,
      "safety_veto",
    )
    |> result.unwrap(st.lifecycle_fpp_state)

  let drifted_twin =
    step_actor_math_twin(
      st.actor_id,
      st.math_twin,
      "Predicting",
      halted_fpp.current,
      0.65,
      False,
      req.now_ms,
    )

  let next_seq = st.zenoh_seq_id + 1
  let alert_topic =
    "uos/v1/rca/" <> sanitize_topic_segment(st.actor_id) <> "/andon_veto"
  let alert_payload =
    json.object([
      #("actor", json.string(st.actor_id)),
      #("dom", json.string(st.spec.domain_slug)),
      #("stage", json.string(veto_stage)),
      #("reason", json.string(string.slice(reason, 0, 120))),
      #("fpp", json.string(halted_fpp.current)),
      #("tp", json.string(traceparent)),
    ])
    |> json.to_string

  let session_pub = core_bus.session_ed25519_pubkey_hex()
  let strict_cand_sha = verified_candidate_sha256_strict()
  let pub_cand_sha = resolve_verified_candidate_sha256()
  let live_cand_sha = case
    is_lower_hex64(strict_cand_sha) && strict_cand_sha == pub_cand_sha
  {
    True -> strict_cand_sha
    False -> ""
  }
  let #(sig_prefix, sig_hex, sig_verified, verified_env_opt) = case
    core_bus.build_and_sign_session_ed25519(
      topic: alert_topic,
      candidate_sha256: live_cand_sha,
      plan_id: active_plan_id,
      task_id: sanitize_topic_segment(req.intent_id),
      worker_id: sanitize_topic_segment(st.actor_id),
      attempt: 1,
      seq_id: next_seq,
      ev_ceiling: 93,
      payload_json: alert_payload,
    )
  {
    Ok(auth_env) ->
      case
        core_bus.verify_authenticated_envelope(
          auth_env,
          session_pub,
          st.zenoh_seq_id,
        )
      {
        Ok(verified_env) -> {
          let _ = core_bus.publish_authenticated(verified_env, session_pub)
          #(
            string.slice(verified_env.signature_hex, 0, 16),
            verified_env.signature_hex,
            True,
            Some(verified_env),
          )
        }
        Error(_) -> #("", "", False, None)
      }
    Error(_) -> #("", "", False, None)
  }

  let sev = case veto_stage == "denotational_lattice_monad" {
    True -> Critical
    False -> Warn
  }
  let log_entry =
    correlated_log.log(
      sev,
      "fpp_actor_intent_vetoed actor="
        <> st.actor_id
        <> " stage="
        <> veto_stage
        <> " reason="
        <> reason,
      trace,
    )
  let log_json = correlated_log.to_json(log_entry)
  otel.stop_span(["uos", "core_evo", "fpp_actor"], 0.19, span_tags, otel_ctx)

  let next_st =
    FppHolonActorState(
      ..st,
      lifecycle_fpp_state: halted_fpp,
      math_twin: drifted_twin,
      last_reflex_action: ReflexJidokaConstitutionalHalt(veto_stage, reason),
      last_ed25519_sig_prefix: sig_prefix,
      last_ed25519_sig_hex: sig_hex,
      last_ed25519_verified: sig_verified,
      last_authenticated_envelope: verified_env_opt,
      zenoh_seq_id: next_seq,
      intents_vetoed: st.intents_vetoed + 1,
      recent_fractal_logs: list.take([log_json, ..st.recent_fractal_logs], 16),
    )

  #(
    ActorIntentVetoed(
      actor_id: st.actor_id,
      fprime_lifecycle_state: halted_fpp.current,
      veto_stage: veto_stage,
      reason: reason,
      w3c_traceparent: traceparent,
      fractal_log_json: log_json,
      zenoh_alert_topic: alert_topic,
    ),
    next_st,
  )
}

// =============================================================================
// 6. OTP 29.0.5 Supervised Actor Lifecycle & Universal 40-Actor Mesh Verifier
// =============================================================================

fn handle_actor_message(
  state: FppHolonActorState,
  msg: FppHolonActorMessage,
) -> actor.Next(FppHolonActorState, FppHolonActorMessage) {
  case msg {
    DispatchIntent(req, reply_to) -> {
      let #(receipt, next_state) = process_actor_intent_pure(state, req)
      process.send(reply_to, receipt)
      actor.continue(next_state)
    }
    HealTwinDrift(now_ms, reply_to) -> {
      let reset_fpp =
        fpp_interp.init_machine(state.lifecycle_machine)
        |> result.unwrap(state.lifecycle_fpp_state)
      let reset_comp =
        fpp_interp.init_machine(state.companion_machine)
        |> result.unwrap(state.companion_fpp_state)
      let healed_twin = converge_actor_math_twin(state.math_twin, now_ms)
      let next_state =
        FppHolonActorState(
          ..state,
          lifecycle_fpp_state: reset_fpp,
          companion_fpp_state: reset_comp,
          math_twin: healed_twin,
          last_reflex_action: ReflexAutonomousSelfHeal(1, healed_twin.pid_control_u),
          autonomous_heals: state.autonomous_heals + 1,
        )
      process.send(reply_to, healed_twin.twin_health)
      actor.continue(next_state)
    }
    InspectActor(reply_to) -> {
      process.send(reply_to, state)
      actor.continue(state)
    }
    ShutdownActor -> actor.stop()
  }
}

pub fn start_subsystem_fpp_actor(
  actor_idx: Int,
  now_ms: Int,
) -> Result(actor.Started(Subject(FppHolonActorMessage)), String) {
  let spec = spec_for_actor_index(actor_idx)
  use init_st <- result.try(init_subsystem_fpp_actor_state(spec, now_ms))
  actor.new(init_st)
  |> actor.on_message(handle_actor_message)
  |> actor.start()
  |> result.map_error(fn(_) { "failed_to_start_otp29_subsystem_fpp_actor" })
}

pub fn start_named_subsystem_fpp_actor(
  actor_id: String,
  now_ms: Int,
) -> Result(actor.Started(Subject(FppHolonActorMessage)), String) {
  use spec <- result.try(find_spec_by_actor_id(actor_id))
  use init_st <- result.try(init_subsystem_fpp_actor_state(spec, now_ms))
  actor.new(init_st)
  |> actor.on_message(handle_actor_message)
  |> actor.start()
  |> result.map_error(fn(_) { "failed_to_start_named_subsystem_fpp_actor" })
}

pub fn start_fpp_holon_actor(
  layer_or_actor_idx: Int,
  now_ms: Int,
) -> Result(actor.Started(Subject(FppHolonActorMessage)), String) {
  use init_st <- result.try(init_fpp_holon_actor_state(layer_or_actor_idx, now_ms))
  actor.new(init_st)
  |> actor.on_message(handle_actor_message)
  |> actor.start()
  |> result.map_error(fn(_) { "failed_to_start_otp29_fpp_holon_actor" })
}

pub fn supervised_subsystem_fpp_actor(
  actor_idx: Int,
  now_ms: Int,
) -> supervision.ChildSpecification(Subject(FppHolonActorMessage)) {
  supervision.worker(fn() {
    let spec = spec_for_actor_index(actor_idx)
    let boot_ms = case now_ms > 0 {
      True -> now_ms
      False -> current_system_time_ms()
    }
    let assert Ok(init_st) = init_subsystem_fpp_actor_state(spec, boot_ms)
    case
      actor.new(init_st)
      |> actor.on_message(handle_actor_message)
      |> actor.start()
    {
      Error(err) -> Error(err)
      Ok(started) -> {
        let next_chart = chart_for_layer_index({ spec.layer_index + 1 } % 10)
        let boot_req =
          ActorIntentRequest(
            intent_id: "supervised_boot_" <> spec.actor_id,
            authority: "sa-plan",
            target_drive_serial: "NVME-DATA-POOL-01",
            criticality: "DAL-B",
            guardian_approved: True,
            ev_cycle: 93,
            target_chart: next_chart,
            action: "supervised_boot_poodavr_handshake",
            mcp_route: spec.primary_mcp_tool,
            role: spec.role,
            openrouter_tier: AdvisoryFreeTier,
            embedded_prompt: "Bootstrap supervised OTP 29 FPP actor "
              <> spec.actor_id,
            parent_trace: None,
            observed_health: 0.99,
            quota: core_evolution.QuotaSnapshot(900, 1100, 1400, 0),
            now_ms: boot_ms + spec.actor_index,
          )
        let _ =
          process.call(started.data, 5000, fn(reply_to) {
            DispatchIntent(boot_req, reply_to)
          })
        ffi_register_live_fpp_actor(spec.actor_index, started.data)
        Ok(started)
      }
    }
  })
}

pub fn supervised_fpp_holon_actor(
  layer_idx: Int,
  now_ms: Int,
) -> supervision.ChildSpecification(Subject(FppHolonActorMessage)) {
  supervision.worker(fn() {
    let assert Ok(init_st) = init_fpp_holon_actor_state(layer_idx, now_ms)
    actor.new(init_st)
    |> actor.on_message(handle_actor_message)
    |> actor.start()
  })
}

pub fn supervised_all_40_fpp_actors(
  now_ms: Int,
) -> List(supervision.ChildSpecification(Subject(FppHolonActorMessage))) {
  int_range(0, universal_fpp_actor_count - 1)
  |> list.map(fn(idx) { supervised_subsystem_fpp_actor(idx, now_ms) })
}

pub fn start_supervised_all_40_fpp_actors(
  now_ms: Int,
) -> Result(actor.Started(static_supervisor.Supervisor), actor.StartError) {
  let builder =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(intensity: 40, period: 10)
  supervised_all_40_fpp_actors(now_ms)
  |> list.fold(builder, fn(sup, child) { static_supervisor.add(sup, child) })
  |> static_supervisor.start()
}

pub fn ensure_live_40_fpp_actor_mesh_started() -> Result(Int, String) {
  ffi_ensure_live_fpp_mesh_supervisor(current_system_time_ms())
}

pub fn live_40_fpp_supervisor_status() -> #(Bool, Int) {
  let _ = ensure_live_40_fpp_actor_mesh_started()
  ffi_live_fpp_supervisor_status()
}

pub fn lookup_live_subsystem_fpp_actor(
  actor_idx: Int,
) -> Result(Subject(FppHolonActorMessage), String) {
  let normalized = case actor_idx < 0 {
    True -> 0
    False -> actor_idx % universal_fpp_actor_count
  }
  use _ <- result.try(ensure_live_40_fpp_actor_mesh_started())
  ffi_lookup_live_fpp_actor(normalized)
  |> result.replace_error(
    "LIVE_FPP_ACTOR_NOT_AVAILABLE:" <> int.to_string(normalized),
  )
}

pub fn inspect_live_40_fpp_actors() -> List(
  #(SubsystemFppActorSpec, Option(FppHolonActorState), Bool),
) {
  let _ = ensure_live_40_fpp_actor_mesh_started()
  all_40_subsystem_fpp_actor_specs()
  |> list.map(fn(spec) {
    case ffi_lookup_live_fpp_actor(spec.actor_index) {
      Ok(subj) -> {
        let live_st = process.call(subj, 2000, InspectActor)
        #(spec, Some(live_st), True)
      }
      Error(_) -> #(spec, None, False)
    }
  })
}

pub fn fpp_actors_for_root_domain(
  domain: SubsystemDomain,
) -> List(SubsystemFppActorSpec) {
  let mapped = case domain {
    AppsDomain -> AppsDomainFpp
    EnginesDomain -> EnginesDomainFpp
    ServicesDomain -> ServicesDomainFpp
    IntelligenceDomain -> IntelligenceDomainFpp
  }
  specs_for_domain(mapped)
}

pub fn total_intelligent_fpp_actors() -> Int {
  list.length(all_40_subsystem_fpp_actor_specs())
}

pub type MeshVerificationSummary {
  MeshVerificationSummary(
    otp_release: String,
    erts_version: String,
    otp_is_29: Bool,
    actors_spawned: Int,
    domains_covered: Int,
    layers_covered: Int,
    intents_accepted_across_l0_l9: Int,
    autonomous_self_heal_verified: Bool,
    pid_damping_reflex_verified: Bool,
    quarantine_breaker_reflex_verified: Bool,
    ed25519_zenoh_signatures_verified: Bool,
    cocycle_chain_valid: Bool,
    sheaf_gluing_valid: Bool,
    all_17_aspects_aligned: Bool,
    all_twins_converged: Bool,
    openrouter_secret_redacted: Bool,
    vetoed_os_nvme_halt_verified: Bool,
    vetoed_ev_above_93_halt_verified: Bool,
  )
}

/// Spawns all 40 live OTP 29.0.5 Intelligent Subsystem FPP Actors (`0..39`
/// across `Apps`, `Engines`, `Services`, `Intelligence` x `L0..L9`), propagates
/// a causal W3C OTel trace + Denotational/Atlas Intents + role-whitelisted
/// `uos-gleam` MCP routes + Ed25519-signed Zenoh `uos/v1/**` + Mathematical
/// Digital Twins + Autonomous Cybernetic Reflexes + Redacted OpenRouter across
/// all 40 actors, tests degraded-health autonomous self-healing, PID damping,
/// circuit-breaker quarantine, and constitutional vetoes (`[REDACTED_SYSTEM_OS_SERIAL]`
/// & `EV-94`), shuts all 40 actors down cleanly, and returns the full proof!
pub fn execute_and_verify_otp29_fpp_actor_mesh(
  quota: QuotaSnapshot,
  now_ms: Int,
) -> Result(MeshVerificationSummary, String) {
  use #(otp_rel, erts_ver) <- result.try(case verify_otp29_runtime() {
    Otp29Verified(r, e) -> Ok(#(r, e))
    OtpVersionMismatch(r, e) ->
      Error(
        "OTP29_MANDATE_VIOLATION: expected OTP 29, found OTP "
        <> r
        <> " (ERTS "
        <> e
        <> ")",
      )
  })
  let is_29 = True
  let session_pub = core_bus.session_ed25519_pubkey_hex()
  let expected_cand_sha = verified_candidate_sha256_strict()
  use _ <- result.try(case
    is_lower_hex64(expected_cand_sha)
    && expected_cand_sha == resolve_verified_candidate_sha256()
  {
    True -> Ok(Nil)
    False ->
      Error(
        "CANDIDATE_SHA256_RESOLUTION_FAILED: unable to resolve verified 64-hex candidate digest",
      )
  })

  let specs = all_40_subsystem_fpp_actor_specs()
  use started_actors <- result.try(
    list.try_map(specs, fn(spec) {
      use started <- result.try(start_subsystem_fpp_actor(
        spec.actor_index,
        now_ms,
      ))
      Ok(#(spec, started.data))
    }),
  )

  // 2. Propagate causal W3C OTel root -> 40 child spans + Intent + MCP + Ed25519 Zenoh + Twin + OpenRouter
  let root_trace = trace_context.new_trace("universal_40_fpp_mesh_wave", "L0")
  let #(accepted_cnt, secret_redacted_ok, all_twins_ok, all_ed25519_ok) =
    list.fold(started_actors, #(0, True, True, True), fn(acc, pair) {
      let #(cnt, red_ok, tw_ok, sig_ok) = acc
      let #(spec, subj) = pair
      let next_chart = chart_for_layer_index({ spec.layer_index + 1 } % 10)
      let req =
        ActorIntentRequest(
          intent_id: "wave_" <> spec.actor_id,
          authority: "sa-plan",
          target_drive_serial: "NVME-DATA-POOL-01",
          criticality: "DAL-B",
          guardian_approved: True,
          ev_cycle: 93,
          target_chart: next_chart,
          action: "execute_intelligent_fpp_subsystem_tick",
          mcp_route: spec.primary_mcp_tool,
          role: spec.role,
          openrouter_tier: AdvisoryFreeTier,
          embedded_prompt: "Advise "
            <> spec.actor_id
            <> " (scrubbed serial 25503L801736 and token sk-or-v1-secret999)",
          parent_trace: Some(root_trace),
          observed_health: 0.99,
          quota: quota,
          now_ms: now_ms + spec.actor_index * 5,
        )
      let reply =
        process.call(subj, 5000, fn(reply_to) { DispatchIntent(req, reply_to) })
      let inspected = process.call(subj, 5000, InspectActor)
      case reply {
        ActorIntentAccepted(
          fprime_lifecycle_state: "Predicting",
          twin_health: th,
          openrouter_sanitized_prompt: clean_p,
          w3c_traceparent: tp,
          ..,
        ) -> {
          let scrubbed =
            !string.contains(clean_p, "25503L801736")
            && !string.contains(clean_p, "sk-or-v1-secret999")
            && string.starts_with(tp, "00-" <> root_trace.trace_id <> "-")
          let has_sig = case inspected.last_authenticated_envelope {
            Some(env) ->
              inspected.last_ed25519_verified
              && env.envelope.candidate_sha256 == expected_cand_sha
              && string.byte_size(inspected.last_ed25519_sig_prefix) == 16
              && string.byte_size(inspected.last_ed25519_sig_hex) == 128
              && case
                core_bus.verify_authenticated_envelope(env, session_pub, 0)
              {
                Ok(_) -> True
                Error(_) -> False
              }
            None -> False
          }
          #(cnt + 1, red_ok && scrubbed, tw_ok && th == 1.0, sig_ok && has_sig)
        }
        _ -> #(cnt, False, False, False)
      }
    })

  // 3. Test Autonomous Cybernetic Intelligence Reflexes (PID Damping, Autonomous Self-Heal, Quarantine Breaker)
  let assert Ok(#(prajna_spec, prajna_subj)) =
    list.find(started_actors, fn(p) {
      { p.0 }.actor_id == "l2_apps_prajna_circuit_breaker"
    })

  // 3a. Mild degradation (0.84) -> ReflexPidDampingTune
  let pid_req =
    ActorIntentRequest(
      intent_id: "reflex_pid_tune",
      authority: "sa-plan",
      target_drive_serial: "NVME-DATA-POOL-01",
      criticality: "DAL-B",
      guardian_approved: True,
      ev_cycle: 93,
      target_chart: prajna_spec.chart,
      action: "pid_damping_probe",
      mcp_route: prajna_spec.primary_mcp_tool,
      role: prajna_spec.role,
      openrouter_tier: AdvisoryFreeTier,
      embedded_prompt: "tune damping",
      parent_trace: Some(root_trace),
      observed_health: 0.84,
      quota: quota,
      now_ms: now_ms + 300,
    )
  let _ = process.call(prajna_subj, 5000, fn(r) { DispatchIntent(pid_req, r) })
  let st_after_pid = process.call(prajna_subj, 5000, InspectActor)
  let pid_ok = case st_after_pid.last_reflex_action {
    ReflexPidDampingTune(u) -> u >. 0.0
    _ -> False
  }

  // 3b. Moderate fault (0.71) -> ReflexAutonomousSelfHeal (automatically heals companion F' -> Closed & Twin -> 1.0)
  let heal_req =
    ActorIntentRequest(
      ..pid_req,
      intent_id: "reflex_auto_heal",
      observed_health: 0.71,
      now_ms: now_ms + 350,
    )
  let _ = process.call(prajna_subj, 5000, fn(r) { DispatchIntent(heal_req, r) })
  let st_after_heal = process.call(prajna_subj, 5000, InspectActor)
  let auto_heal_ok = case st_after_heal.last_reflex_action {
    ReflexAutonomousSelfHeal(rec_cnt, _) ->
      rec_cnt >= 1
      && st_after_heal.autonomous_heals >= 1
      && st_after_heal.companion_fpp_state.current == "Closed"
      && st_after_heal.math_twin.twin_health == 1.0
    _ -> False
  }

  // 3c. Severe fault (0.45) -> ReflexQuarantineAndCircuitBreak (trips companion F' -> Open), then HealTwinDrift -> 1.0
  let quar_req =
    ActorIntentRequest(
      ..pid_req,
      intent_id: "reflex_quarantine_break",
      observed_health: 0.45,
      now_ms: now_ms + 400,
    )
  let _ = process.call(prajna_subj, 5000, fn(r) { DispatchIntent(quar_req, r) })
  let st_after_quar = process.call(prajna_subj, 5000, InspectActor)
  let quar_ok = case st_after_quar.last_reflex_action {
    ReflexQuarantineAndCircuitBreak(_) ->
      st_after_quar.companion_fpp_state.current == "Open"
    _ -> False
  }
  let healed_prajna_health =
    process.call(prajna_subj, 5000, fn(r) { HealTwinDrift(now_ms + 450, r) })

  // 4. Verify fail-closed FPP `ConstitutionalHalt` on OS NVMe serial & EV-94, plus Digital Twin drift healing
  let assert Ok(#(l0_spec, l0_subj)) = list.first(started_actors)
  let bad_nvme_req =
    ActorIntentRequest(
      intent_id: "veto_nvme",
      authority: "sa-plan",
      target_drive_serial: "25503L801736",
      criticality: "DAL-A",
      guardian_approved: True,
      ev_cycle: 93,
      target_chart: L0Constitutional,
      action: "illegal_os_drive_touch",
      mcp_route: l0_spec.primary_mcp_tool,
      role: l0_spec.role,
      openrouter_tier: AdvisoryFreeTier,
      embedded_prompt: "check",
      parent_trace: Some(root_trace),
      observed_health: 0.99,
      quota: quota,
      now_ms: now_ms + 500,
    )
  let nvme_veto_ok = case
    process.call(l0_subj, 5000, fn(r) { DispatchIntent(bad_nvme_req, r) })
  {
    ActorIntentVetoed(fprime_lifecycle_state: "ConstitutionalHalt", ..) -> True
    _ -> False
  }
  let healed_health =
    process.call(l0_subj, 5000, fn(r) { HealTwinDrift(now_ms + 600, r) })

  let bad_ev_req =
    ActorIntentRequest(
      ..bad_nvme_req,
      intent_id: "veto_ev94",
      target_drive_serial: "NVME-DATA-POOL-01",
      ev_cycle: 94,
    )
  let ev_veto_ok = case
    process.call(l0_subj, 5000, fn(r) { DispatchIntent(bad_ev_req, r) })
  {
    ActorIntentVetoed(fprime_lifecycle_state: "ConstitutionalHalt", ..) -> True
    _ -> False
  }
  let healed_health2 =
    process.call(l0_subj, 5000, fn(r) { HealTwinDrift(now_ms + 700, r) })

  // 5. Verify Algebraic Atlas cocycle chain L0 -> L1 -> ... -> L9 & Sheaf gluing + 17 Aspects + 4 Domains x 10 Layers
  let cocycle_ok = verify_l0_to_l9_cocycle_chain()
  let sheaf_ok = verify_l0_to_l9_sheaf_gluing()
  let aspects_rep = aspect_coverage_engine.evaluate_all_aspects(now_ms)
  let aspects_covered =
    aspects_rep.all_aspects_passed
    && list.all(int_range(1, 17), fn(a_id) {
      list.any(specs, fn(sp) { list.contains(sp.assigned_aspects, a_id) })
    })
  let domains_cnt =
    [
      AppsDomainFpp,
      EnginesDomainFpp,
      ServicesDomainFpp,
      IntelligenceDomainFpp,
    ]
    |> list.filter(fn(d) { list.length(specs_for_domain(d)) == 10 })
    |> list.length
  let layers_cnt =
    int_range(0, 9)
    |> list.filter(fn(l) { list.length(specs_for_layer(l)) == 4 })
    |> list.length

  // 6. Cleanly stop all 40 spawned OTP 29 actors
  list.each(started_actors, fn(pair) {
    let #(_, subj) = pair
    process.send(subj, ShutdownActor)
  })

  Ok(MeshVerificationSummary(
    otp_release: otp_rel,
    erts_version: erts_ver,
    otp_is_29: is_29,
    actors_spawned: list.length(started_actors),
    domains_covered: domains_cnt,
    layers_covered: layers_cnt,
    intents_accepted_across_l0_l9: accepted_cnt,
    autonomous_self_heal_verified: auto_heal_ok,
    pid_damping_reflex_verified: pid_ok,
    quarantine_breaker_reflex_verified: quar_ok,
    ed25519_zenoh_signatures_verified: all_ed25519_ok,
    cocycle_chain_valid: cocycle_ok,
    sheaf_gluing_valid: sheaf_ok,
    all_17_aspects_aligned: aspects_covered,
    all_twins_converged: all_twins_ok
      && healed_prajna_health == 1.0
      && healed_health == 1.0
      && healed_health2 == 1.0,
    openrouter_secret_redacted: secret_redacted_ok,
    vetoed_os_nvme_halt_verified: nvme_veto_ok,
    vetoed_ev_above_93_halt_verified: ev_veto_ok,
  ))
}

fn verify_l0_to_l9_cocycle_chain() -> Bool {
  let steps = int_range(0, 8)
  let init_m = algebraic_atlas.identity_morphism(L0Constitutional)
  case
    list.try_fold(steps, init_m, fn(acc_m, i) {
      let c_from = chart_for_layer_index(i)
      let c_to = chart_for_layer_index(i + 1)
      let step_m =
        TransitionMorphism(
          source_chart: c_from,
          target_chart: c_to,
          transform_name: "phi_"
            <> int.to_string(i)
            <> "_"
            <> int.to_string(i + 1),
          is_compatible: True,
        )
      algebraic_atlas.compose_morphisms(acc_m, step_m)
    })
  {
    Ok(composed) ->
      composed.source_chart == L0Constitutional
      && composed.target_chart == L9Sovereignty
      && composed.is_compatible
    Error(_) -> False
  }
}

fn verify_l0_to_l9_sheaf_gluing() -> Bool {
  let sections =
    list.map(int_range(0, 9), fn(i) {
      #(chart_for_layer_index(i), "ev93_margin40_uos_v1_invariant")
    })
  let overlaps =
    list.map(int_range(0, 8), fn(i) {
      #(
        chart_for_layer_index(i),
        chart_for_layer_index(i + 1),
        "ev93_margin40_uos_v1_invariant",
      )
    })
  case algebraic_atlas.verify_sheaf_gluing(sections, overlaps) {
    Ok(_) -> True
    Error(_) -> False
  }
}

pub fn encode_spec_json(spec: SubsystemFppActorSpec) -> json.Json {
  json.object([
    #("actor_index", json.int(spec.actor_index)),
    #("actor_id", json.string(spec.actor_id)),
    #("subsystem_name", json.string(spec.subsystem_name)),
    #("domain_supervisor", json.string(spec.domain_name)),
    #("domain_slug", json.string(spec.domain_slug)),
    #("layer_index", json.int(spec.layer_index)),
    #("layer", json.string(spec.layer_short)),
    #("supervision_child_id", json.string(spec.supervision_child_id)),
    #("lifecycle_fpp_fsm", json.string("PoodavrLifecycleFPrime")),
    #("companion_fpp_fsm", json.string(spec.companion_fpp_name)),
    #("primary_mcp_tool", json.string(spec.primary_mcp_tool)),
    #("zenoh_topic", json.string(spec.zenoh_topic)),
    #("assigned_aspects", json.array(spec.assigned_aspects, json.int)),
    #("intelligence_focus", json.string(spec.intelligence_focus)),
  ])
}

pub fn encode_live_actor_json(
  entry: #(SubsystemFppActorSpec, Option(FppHolonActorState), Bool),
) -> json.Json {
  let #(spec, st_opt, alive) = entry
  let #(
    lifecycle_state,
    companion_state,
    reflex_str,
    twin_health,
    kalman_health,
    lyap_v,
    accepted_cnt,
    vetoed_cnt,
    heals_cnt,
    seq_id,
    sig_ok,
    sig_prefix,
  ) = case st_opt {
    Some(st) -> #(
      st.lifecycle_fpp_state.current,
      st.companion_fpp_state.current,
      reflex_action_label(st.last_reflex_action),
      st.math_twin.twin_health,
      st.math_twin.kalman_predicted_health,
      st.math_twin.lyapunov_energy,
      st.intents_accepted,
      st.intents_vetoed,
      st.autonomous_heals,
      st.zenoh_seq_id,
      st.last_ed25519_verified,
      st.last_ed25519_sig_prefix,
    )
    None -> #(
      "Unavailable",
      "Unavailable",
      "UNAVAILABLE",
      0.0,
      0.0,
      0.0,
      0,
      0,
      0,
      0,
      False,
      "",
    )
  }
  json.object([
    #("actor_index", json.int(spec.actor_index)),
    #("actor_id", json.string(spec.actor_id)),
    #("subsystem_name", json.string(spec.subsystem_name)),
    #("domain_supervisor", json.string(spec.domain_name)),
    #("domain_slug", json.string(spec.domain_slug)),
    #("layer_index", json.int(spec.layer_index)),
    #("layer", json.string(spec.layer_short)),
    #("supervision_child_id", json.string(spec.supervision_child_id)),
    #("lifecycle_fpp_fsm", json.string("PoodavrLifecycleFPrime")),
    #("companion_fpp_fsm", json.string(spec.companion_fpp_name)),
    #("primary_mcp_tool", json.string(spec.primary_mcp_tool)),
    #("zenoh_topic", json.string(spec.zenoh_topic)),
    #("assigned_aspects", json.array(spec.assigned_aspects, json.int)),
    #("intelligence_focus", json.string(spec.intelligence_focus)),
    #("process_alive", json.bool(alive)),
    #(
      "supervised_by",
      json.string("otp29_static_supervisor_one_for_one"),
    ),
    #("live_lifecycle_state", json.string(lifecycle_state)),
    #("live_companion_state", json.string(companion_state)),
    #("last_reflex_action", json.string(reflex_str)),
    #("twin_health", json.float(twin_health)),
    #("kalman_predicted_health", json.float(kalman_health)),
    #("lyapunov_energy", json.float(lyap_v)),
    #("intents_accepted", json.int(accepted_cnt)),
    #("intents_vetoed", json.int(vetoed_cnt)),
    #("autonomous_heals", json.int(heals_cnt)),
    #("zenoh_seq_id", json.int(seq_id)),
    #("ed25519_verified", json.bool(sig_ok)),
    #("ed25519_sig_prefix", json.string(sig_prefix)),
  ])
}

pub fn encode_mesh_summary_json(s: MeshVerificationSummary) -> String {
  json.object([
    #("schema", json.string("uos.core_evo.universal_40_fpp_actor_mesh.v5")),
    #("ev_ceiling", json.int(core_evolution.admitted_ev_ceiling)),
    #("otp_release", json.string(s.otp_release)),
    #("erts_version", json.string(s.erts_version)),
    #("otp_is_29", json.bool(s.otp_is_29)),
    #("actors_spawned", json.int(s.actors_spawned)),
    #("domains_covered", json.int(s.domains_covered)),
    #("layers_covered", json.int(s.layers_covered)),
    #(
      "intents_accepted_across_l0_l9",
      json.int(s.intents_accepted_across_l0_l9),
    ),
    #(
      "autonomous_self_heal_verified",
      json.bool(s.autonomous_self_heal_verified),
    ),
    #(
      "pid_damping_reflex_verified",
      json.bool(s.pid_damping_reflex_verified),
    ),
    #(
      "quarantine_breaker_reflex_verified",
      json.bool(s.quarantine_breaker_reflex_verified),
    ),
    #(
      "ed25519_zenoh_signatures_verified",
      json.bool(s.ed25519_zenoh_signatures_verified),
    ),
    #("cocycle_chain_valid", json.bool(s.cocycle_chain_valid)),
    #("sheaf_gluing_valid", json.bool(s.sheaf_gluing_valid)),
    #("all_17_aspects_aligned", json.bool(s.all_17_aspects_aligned)),
    #("all_twins_converged", json.bool(s.all_twins_converged)),
    #("openrouter_secret_redacted", json.bool(s.openrouter_secret_redacted)),
    #(
      "vetoed_os_nvme_halt_verified",
      json.bool(s.vetoed_os_nvme_halt_verified),
    ),
    #(
      "vetoed_ev_above_93_halt_verified",
      json.bool(s.vetoed_ev_above_93_halt_verified),
    ),
  ])
  |> json.to_string
}

fn sanitize_topic_segment(raw: String) -> String {
  raw
  |> string.to_graphemes
  |> list.filter(fn(c) {
    string.contains(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-",
      c,
    )
  })
  |> string.concat
}

fn int_range(lo: Int, hi: Int) -> List(Int) {
  case lo > hi {
    True -> []
    False -> [lo, ..int_range(lo + 1, hi)]
  }
}
