//// =============================================================================
//// [C3I-BOUNDED-ECOLOGY] UOS PARTICIPANT MODELS & CAPABILITY RUNNER
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ecology/living_swarm</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE through L6_ECOSYSTEM</layer>
////     <mesh-domain>Living Swarm Mesh, Biological Holons & Cybernetic Singing</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>BOUNDED LOCAL STATE; NOT SYSTEM ADMISSION</criticality>
////     <stamp-controls>
////       SC-HOLON-001, SC-BIO-EVO-001, SC-BIO-HARMONY-001, SC-ZERO-MUDA-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// Local agentic participant models hosted in one ecology actor across seven
//// systemic planes. Names do not establish live external system bindings:
////   Plane 1 (Cognitive Cortex / Dha): hive-mind-decider, hermes-rete-ul, lean4-oracle, openrouter-advisory, max-simd-tensor
////   Plane 2 (Autonomic Nervous System / Sa): prajna-homeostasis, lyapunov-monitor, freshness-bayan, circuit-breaker
////   Plane 3 (Sensory Mesh / Pa): zenoh-mesh, coordination-board, agui-event-stream
////   Plane 4 (Immune Core / Re): constitution, km-gate, coord
////   Plane 5 (Epistemic Substrate / Ma): km-corpus, sa-plan-db, events-store
////   Plane 6 (Execution Actuators / Ni): max-inference-daemon, solo5-sandbox, work-stealing-pool
////   Plane 7 (Meta-Sovereign Quorum / Om): agy-agent, claude-agent, codex-agent
////
//// STAMP: SC-HOLON-001, SC-BIO-EVO-001, SC-BIO-HARMONY-001, SC-ZERO-MUDA-001.

import cepaf_gleam/ecology/andon
import cepaf_gleam/ecology/capability_port.{
  type Outcome, Engaged, Masked, Unavailable,
}
import cepaf_gleam/ecology/harmonic_song.{
  type SwarmSong, HolonVoice, compose_swarm_song, compute_voice_consonance,
  plane_to_shruti, song_to_json,
}
import cepaf_gleam/ecology/super_agent.{
  type OperationalMode, type SuperAgentHolon, Active, Autonomous, Awakening,
  Deliberative, Healing, Reflex, SovereignEvolution, Stressed, awaken,
  create_super_agent, execute_autonomic_pulse, set_mode, to_json,
}
import gleam/float
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}

// =============================================================================
// 1. Swarm Ecology State
// =============================================================================

pub type SwarmEcology {
  SwarmEcology(
    epoch_us: Int,
    cycle_counter: Int,
    beat_number: Int,
    holons: List(SuperAgentHolon),
    current_song: SwarmSong,
    collective_energy: Float,
    lyapunov_exponent: Float,
    shannon_entropy: Float,
    is_harmonic: Bool,
    invocation_sequence: Int,
    receipts: List(CapabilityReceipt),
    service_andon: List(andon.Service),
  )
}

pub type CapabilityReceipt {
  CapabilityReceipt(
    sequence: Int,
    holon_id: String,
    cycle: Int,
    observed_at_us: Int,
    input_kind: String,
    outcome: Outcome,
  )
}

pub const receipt_limit = 128

type ClockUnit {
  Microsecond
}

@external(erlang, "erlang", "system_time")
fn system_time(unit: ClockUnit) -> Int

pub fn observed_epoch_us() -> Int {
  system_time(Microsecond)
}

// =============================================================================
// 2. Participating Holon Model Definitions
// =============================================================================

pub type HolonSpec {
  HolonSpec(
    id: String,
    name: String,
    plane: String,
    level: Int,
    mode: OperationalMode,
  )
}

pub fn all_21_holon_specs() -> List(HolonSpec) {
  all_holon_specs()
}

/// Participant identities are local agentic models of these systems. They do
/// not impersonate sovereign sessions or acquire the underlying service's authority.
pub fn all_holon_specs() -> List(HolonSpec) {
  [
    HolonSpec("ucon", "Ucon Agentic Console", "cognitive", 5, Autonomous),
    HolonSpec(
      "indrajaal",
      "Indrajaal Ecology Observer",
      "cognitive",
      5,
      Autonomous,
    ),
    // Plane 1: Cognitive Cortex (Dha)
    HolonSpec(
      "hive-mind-decider",
      "Hive Mind Decider",
      "cognitive",
      5,
      Autonomous,
    ),
    HolonSpec(
      "hermes-rete-ul",
      "Hermes Rete-UL Forward Chainer",
      "cognitive",
      5,
      Deliberative,
    ),
    HolonSpec(
      "lean4-oracle",
      "Lean 4 Formal Verification Oracle",
      "cognitive",
      5,
      SovereignEvolution,
    ),
    HolonSpec(
      "openrouter-advisory",
      "OpenRouter Free-Tier Advisory",
      "cognitive",
      5,
      Autonomous,
    ),
    HolonSpec(
      "max-simd-tensor",
      "Modular MAX SIMD Tensor Kernel",
      "cognitive",
      5,
      Autonomous,
    ),

    // Plane 2: Autonomic Nervous System (Sa)
    HolonSpec(
      "prajna-homeostasis",
      "Prajna Homeostasis PID Engine",
      "autonomic",
      2,
      Reflex,
    ),
    HolonSpec(
      "lyapunov-monitor",
      "Lyapunov Stability Monitor",
      "autonomic",
      2,
      Reflex,
    ),
    HolonSpec(
      "freshness-bayan",
      "Dead-Man Freshness Bayan",
      "autonomic",
      2,
      Reflex,
    ),
    HolonSpec(
      "circuit-breaker",
      "Biomorphic Circuit Breaker",
      "autonomic",
      2,
      Reflex,
    ),

    // Plane 3: Sensory & Circulatory Mesh (Pa)
    HolonSpec(
      "zenoh-mesh",
      "Zenoh Pub/Sub Telemetry Mesh",
      "sensory",
      3,
      Reflex,
    ),
    HolonSpec(
      "coordination-board",
      "Tri-Agent Coordination Board",
      "sensory",
      3,
      Deliberative,
    ),
    HolonSpec(
      "agui-event-stream",
      "AG-UI 32-Event SSE Stream",
      "sensory",
      3,
      Reflex,
    ),

    // Plane 4: Immune & Constitutional Core (Re)
    HolonSpec(
      "constitution",
      "L0 Constitutional Guardian",
      "immune",
      0,
      Deliberative,
    ),
    HolonSpec(
      "km-gate",
      "Knowledge Management Provenance Gate",
      "immune",
      0,
      Deliberative,
    ),
    HolonSpec("coord", "Durable Session Coordinator", "immune", 0, Deliberative),

    // Plane 5: Epistemic Substrate (Ma)
    HolonSpec(
      "km-corpus",
      "ZK & Wiki Living Ontology Corpus",
      "epistemic",
      4,
      Deliberative,
    ),
    HolonSpec(
      "sa-plan-db",
      "Sa-Plan Canonical SQLite Store",
      "epistemic",
      4,
      Deliberative,
    ),
    HolonSpec(
      "events-store",
      "Coordination Events Append Store",
      "epistemic",
      4,
      Deliberative,
    ),

    // Plane 6: Execution Actuators (Ni)
    HolonSpec(
      "max-inference-daemon",
      "Isolated MAX Inference Daemon",
      "actuator",
      6,
      Autonomous,
    ),
    HolonSpec(
      "solo5-sandbox",
      "Solo5 Unikernel Execution Sandbox",
      "actuator",
      6,
      Autonomous,
    ),
    HolonSpec(
      "work-stealing-pool",
      "Decentralized Work Stealing Pool",
      "actuator",
      6,
      Autonomous,
    ),

    // Plane 7: Meta-Sovereign Quorum (Om)
    HolonSpec(
      "agy-agent",
      "AGY Sovereign Autonomous Agent",
      "sovereign",
      7,
      SovereignEvolution,
    ),
    HolonSpec(
      "claude-agent",
      "Claude Sovereign Reviewer",
      "sovereign",
      7,
      SovereignEvolution,
    ),
    HolonSpec(
      "codex-agent",
      "Codex Sovereign Verification Agent",
      "sovereign",
      7,
      SovereignEvolution,
    ),
  ]
}

// =============================================================================
// 3. Ecology Initialization
// =============================================================================

pub fn init_living_swarm() -> SwarmEcology {
  let specs = all_holon_specs()
  let holons =
    list.map(specs, fn(spec) {
      let h = create_super_agent(spec.id, spec.name, spec.plane, spec.level)
      // Awaken holon twice: Dormant -> Awakening -> Active
      let awakened = case awaken(h) {
        Ok(a) ->
          case awaken(a) {
            Ok(active) -> active
            Error(_) -> a
          }
        Error(_) -> h
      }
      set_mode(awakened, spec.mode)
    })

  let epoch = observed_epoch_us()
  let initial_song = compose_swarm_song(epoch, 1, [], 0.0, 0.0)

  SwarmEcology(
    epoch_us: epoch,
    cycle_counter: 0,
    beat_number: 1,
    holons: holons,
    current_song: initial_song,
    collective_energy: 0.0,
    lyapunov_exponent: 0.0,
    shannon_entropy: 0.0,
    is_harmonic: False,
    invocation_sequence: 0,
    receipts: [],
    service_andon: andon.initial(),
  )
}

// =============================================================================
// 4. Autonomic Swarm Cycle Runner ("It Must Sing")
// =============================================================================

pub fn step_swarm_cycle(ecology: SwarmEcology) -> SwarmEcology {
  step_swarm_cycle_observed(ecology, observed_epoch_us(), 100.0, 100.0)
}

/// Runtime callers supply actual monotonic elapsed time and configured cadence.
/// The compatibility helper above supplies a nominal interval for local simulation.
pub fn step_swarm_cycle_observed(
  ecology: SwarmEcology,
  epoch_us: Int,
  observed_interval_ms: Float,
  target_interval_ms: Float,
) -> SwarmEcology {
  let next_cycle = ecology.cycle_counter + 1
  let next_beat = { ecology.beat_number % 16 } + 1

  // 1. Advance each holon through its autonomic heartbeat
  let updated_holons =
    list.map(ecology.holons, fn(h) {
      let #(pulsed, _report) =
        execute_autonomic_pulse(h, observed_interval_ms, target_interval_ms)
      pulsed
    })

  // 2. Synthesize voices of all active holons
  let voices =
    list.filter_map(updated_holons, fn(h) {
      case h.lifecycle {
        Active | Awakening | Healing | Stressed -> {
          let shruti = plane_to_shruti(h.plane)
          let consonance =
            compute_voice_consonance(shruti, ecology.lyapunov_exponent)
          let amp = float.max(0.1, 1.0 -. h.homeostatic_error)
          let pan = case h.plane {
            "cognitive" -> -0.6
            "autonomic" -> 0.0
            "sensory" -> -0.3
            "immune" -> 0.3
            "epistemic" -> 0.6
            "actuator" -> 0.8
            "sovereign" -> 0.0
            _ -> 0.0
          }
          Ok(HolonVoice(
            holon_id: h.id,
            plane: h.plane,
            swara: shruti.swara,
            shruti_name: shruti.name,
            frequency_hz: shruti.frequency_hz,
            amplitude: amp,
            pan: pan,
            consonance: consonance,
          ))
        }
        _ -> Error(Nil)
      }
    })

  let energy =
    list.fold(updated_holons, 0.0, fn(sum, h) { sum +. h.lyapunov_energy })
  let energy_delta = energy -. ecology.collective_energy
  let entropy = plane_entropy(updated_holons)

  // The song describes measured participant distribution and latency energy.
  // It is not evidence of service availability, proof admission or intelligence.
  let song =
    compose_swarm_song(epoch_us, next_beat, voices, energy_delta, entropy)

  let is_harmonic =
    song.harmonic_consonance >=. 0.4
    && song.lyapunov_exponent <=. 0.0
    && song.shannon_entropy_bits >=. 2.5

  SwarmEcology(
    epoch_us: epoch_us,
    cycle_counter: next_cycle,
    beat_number: next_beat,
    holons: updated_holons,
    current_song: song,
    collective_energy: energy,
    lyapunov_exponent: energy_delta,
    shannon_entropy: entropy,
    is_harmonic: is_harmonic,
    invocation_sequence: ecology.invocation_sequence,
    receipts: ecology.receipts,
    service_andon: ecology.service_andon,
  )
}

fn plane_entropy(holons: List(SuperAgentHolon)) -> Float {
  let count = list.length(holons) |> int_to_float
  let planes = list.map(holons, fn(h) { h.plane }) |> list.unique
  list.fold(planes, 0.0, fn(sum, plane) {
    let matching =
      list.count(holons, fn(h) { h.plane == plane }) |> int_to_float
    let p = matching /. count
    case float.logarithm(p) {
      Ok(log_p) -> sum -. p *. log_p /. 0.6931471805599453
      Error(_) -> sum
    }
  })
}

@external(erlang, "erlang", "float")
fn int_to_float(value: Int) -> Float

// =============================================================================
// 5. Multi-Capability Direct Invocation
// =============================================================================

pub fn invoke_capability(
  holon: SuperAgentHolon,
  capability_name: String,
) -> Result(SuperAgentHolon, String) {
  let outcome = case andon.shared(capability_name) {
    True ->
      Unavailable(capability_name, "shared_service_requires_actor_dispatch")
    False ->
      capability_port.invoke(
        holon.mask,
        capability_name,
        capability_port.default_input(capability_name),
      )
  }
  case outcome {
    Engaged(..) -> Ok(apply_outcome(holon, outcome))
    Unavailable(_, why) -> Error(why)
    Masked(name) -> Error("capability_masked: " <> name)
  }
}

/// Receipt counters describe invocation outcomes only. They never synthesize
/// theorem counts, model tokens, Rete firings or system admission.
pub fn apply_outcome(
  holon: SuperAgentHolon,
  outcome: Outcome,
) -> SuperAgentHolon {
  case outcome {
    Engaged(name, _, _, _) ->
      super_agent.SuperAgentHolon(
        ..holon,
        successful_invocations: holon.successful_invocations + 1,
        last_capability: name,
        last_outcome: "engaged",
      )
    Unavailable(name, _) ->
      super_agent.SuperAgentHolon(
        ..holon,
        unavailable_invocations: holon.unavailable_invocations + 1,
        last_capability: name,
        last_outcome: "unavailable",
      )
    Masked(name) ->
      super_agent.SuperAgentHolon(
        ..holon,
        masked_invocations: holon.masked_invocations + 1,
        last_capability: name,
        last_outcome: "masked",
      )
  }
}

pub fn record_outcome(
  ecology: SwarmEcology,
  holon_id: String,
  outcome: Outcome,
) -> SwarmEcology {
  record_outcome_kind(ecology, holon_id, "requested", outcome)
}

pub fn record_outcome_kind(
  ecology: SwarmEcology,
  holon_id: String,
  input_kind: String,
  outcome: Outcome,
) -> SwarmEcology {
  let sequence = ecology.invocation_sequence + 1
  SwarmEcology(
    ..ecology,
    holons: list.map(ecology.holons, fn(h) {
      case h.id == holon_id {
        True -> apply_outcome(h, outcome)
        False -> h
      }
    }),
    invocation_sequence: sequence,
    receipts: [
        CapabilityReceipt(
          sequence,
          holon_id,
          ecology.cycle_counter,
          observed_epoch_us(),
          input_kind,
          outcome,
        ),
        ..ecology.receipts
      ]
      |> list.take(receipt_limit),
  )
}

/// Exactly one selected local capability per heartbeat, with round-robin
/// participation across every holon. No subprocess/network call enters this path.
pub fn next_local_invocation(
  ecology: SwarmEcology,
) -> Option(#(SuperAgentHolon, String)) {
  let count = list.length(ecology.holons)
  case count {
    0 -> None
    _ -> {
      let index = { ecology.cycle_counter - 1 } % count
      let selected = list.drop(ecology.holons, index) |> list.first
      case selected {
        Error(_) -> None
        Ok(holon) -> {
          let local =
            [
              "bayesian",
              "fprime",
              "ets",
              "stm",
              "rete_ul",
              "ruliad",
              "formal_twin",
              "denotational",
              "algebraic_atlas",
            ]
            |> list.filter(fn(c) { capability_port.mask_allows(holon.mask, c) })
          case list.length(local) {
            0 -> None
            n -> {
              let round = { ecology.cycle_counter - 1 } / count
              case list.drop(local, round % n) |> list.first {
                Ok(capability) -> Some(#(holon, capability))
                Error(_) -> None
              }
            }
          }
        }
      }
    }
  }
}

// =============================================================================
// 6. JSON Serialization
// =============================================================================

pub fn swarm_to_json(ecology: SwarmEcology) -> Json {
  json.object([
    #("epoch_us", json.int(ecology.epoch_us)),
    #("cycle_counter", json.int(ecology.cycle_counter)),
    #("beat_number", json.int(ecology.beat_number)),
    #("total_holons", json.int(list.length(ecology.holons))),
    #("participant_kind", json.string("local_agentic_model")),
    #("hosting", json.string("one_shared_ecology_actor")),
    #("external_system_binding", json.bool(False)),
    #("collective_energy", json.float(ecology.collective_energy)),
    #("lyapunov_exponent", json.null()),
    #("latency_energy_delta", json.float(ecology.lyapunov_exponent)),
    #("shannon_entropy", json.float(ecology.shannon_entropy)),
    #("is_harmonic", json.bool(ecology.is_harmonic)),
    #(
      "metric_scope",
      json.string(
        "participant plane entropy and observed heartbeat latency energy; no service admission",
      ),
    ),
    #("invocation_sequence", json.int(ecology.invocation_sequence)),
    #("receipt_limit", json.int(receipt_limit)),
    #("service_andon", json.array(ecology.service_andon, andon.to_json)),
    #(
      "receipts",
      json.array(ecology.receipts, fn(r) {
        json.object([
          #("sequence", json.int(r.sequence)),
          #("holon_id", json.string(r.holon_id)),
          #("cycle", json.int(r.cycle)),
          #("observed_at_us", json.int(r.observed_at_us)),
          #("input_kind", json.string(r.input_kind)),
          #("outcome", capability_port.outcome_to_json(r.outcome)),
        ])
      }),
    ),
    #("song", song_to_json(ecology.current_song)),
    #("holons", json.array(ecology.holons, to_json)),
  ])
}
