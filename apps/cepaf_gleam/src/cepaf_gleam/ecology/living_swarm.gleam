//// =============================================================================
//// [C3I-SIL6-MSTS] UOS LIVING 21-HOLON SWARM ECOLOGY & MULTI-CAPABILITY RUNNER
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
////     <criticality>DAL-A / SIL-6 / AUTONOMIC-LIVING</criticality>
////     <stamp-controls>
////       SC-HOLON-001, SC-BIO-EVO-001, SC-BIO-HARMONY-001, SC-ZERO-MUDA-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// Live instantiation and autonomic execution engine for the 21 participating
//// holons across the 7 systemic planes of the Unified Operational System:
////   Plane 1 (Cognitive Cortex / Dha): hive-mind-decider, hermes-rete-ul, lean4-oracle, openrouter-advisory, max-simd-tensor
////   Plane 2 (Autonomic Nervous System / Sa): prajna-homeostasis, lyapunov-monitor, freshness-bayan, circuit-breaker
////   Plane 3 (Sensory Mesh / Pa): zenoh-mesh, coordination-board, agui-event-stream
////   Plane 4 (Immune Core / Re): constitution, km-gate, coord
////   Plane 5 (Epistemic Substrate / Ma): km-corpus, sa-plan-db, events-store
////   Plane 6 (Execution Actuators / Ni): max-inference-daemon, solo5-sandbox, work-stealing-pool
////   Plane 7 (Meta-Sovereign Quorum / Om): agy-agent, claude-agent, codex-agent
////
//// STAMP: SC-HOLON-001, SC-BIO-EVO-001, SC-BIO-HARMONY-001, SC-ZERO-MUDA-001.

import cepaf_gleam/ecology/harmonic_song.{
  type SwarmSong, HolonVoice, compose_swarm_song,
  compute_voice_consonance, plane_to_shruti, song_to_json,
}
import cepaf_gleam/ecology/super_agent.{
  type OperationalMode, type SuperAgentHolon, Active, Autonomous, Awakening,
  Deliberative, Healing, Reflex, SovereignEvolution, Stressed, awaken,
  create_super_agent, execute_autonomic_pulse, set_mode, to_json,
}
import gleam/float
import gleam/json.{type Json}
import gleam/list

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
  )
}

// =============================================================================
// 2. The 21 Participating Holon Definitions
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
  [
    // Plane 1: Cognitive Cortex (Dha)
    HolonSpec("hive-mind-decider", "Hive Mind Decider", "cognitive", 5, Autonomous),
    HolonSpec("hermes-rete-ul", "Hermes Rete-UL Forward Chainer", "cognitive", 5, Deliberative),
    HolonSpec("lean4-oracle", "Lean 4 Formal Verification Oracle", "cognitive", 5, SovereignEvolution),
    HolonSpec("openrouter-advisory", "OpenRouter Free-Tier Advisory", "cognitive", 5, Autonomous),
    HolonSpec("max-simd-tensor", "Modular MAX SIMD Tensor Kernel", "cognitive", 5, Autonomous),

    // Plane 2: Autonomic Nervous System (Sa)
    HolonSpec("prajna-homeostasis", "Prajna Homeostasis PID Engine", "autonomic", 2, Reflex),
    HolonSpec("lyapunov-monitor", "Lyapunov Stability Monitor", "autonomic", 2, Reflex),
    HolonSpec("freshness-bayan", "Dead-Man Freshness Bayan", "autonomic", 2, Reflex),
    HolonSpec("circuit-breaker", "Biomorphic Circuit Breaker", "autonomic", 2, Reflex),

    // Plane 3: Sensory & Circulatory Mesh (Pa)
    HolonSpec("zenoh-mesh", "Zenoh Pub/Sub Telemetry Mesh", "sensory", 3, Reflex),
    HolonSpec("coordination-board", "Tri-Agent Coordination Board", "sensory", 3, Deliberative),
    HolonSpec("agui-event-stream", "AG-UI 32-Event SSE Stream", "sensory", 3, Reflex),

    // Plane 4: Immune & Constitutional Core (Re)
    HolonSpec("constitution", "L0 Constitutional Guardian", "immune", 0, Deliberative),
    HolonSpec("km-gate", "Knowledge Management Provenance Gate", "immune", 0, Deliberative),
    HolonSpec("coord", "Durable Session Coordinator", "immune", 0, Deliberative),

    // Plane 5: Epistemic Substrate (Ma)
    HolonSpec("km-corpus", "ZK & Wiki Living Ontology Corpus", "epistemic", 4, Deliberative),
    HolonSpec("sa-plan-db", "Sa-Plan Canonical SQLite Store", "epistemic", 4, Deliberative),
    HolonSpec("events-store", "Coordination Events Append Store", "epistemic", 4, Deliberative),

    // Plane 6: Execution Actuators (Ni)
    HolonSpec("max-inference-daemon", "Isolated MAX Inference Daemon", "actuator", 6, Autonomous),
    HolonSpec("solo5-sandbox", "Solo5 Unikernel Execution Sandbox", "actuator", 6, Autonomous),
    HolonSpec("work-stealing-pool", "Decentralized Work Stealing Pool", "actuator", 6, Autonomous),

    // Plane 7: Meta-Sovereign Quorum (Om)
    HolonSpec("agy-agent", "AGY Sovereign Autonomous Agent", "sovereign", 7, SovereignEvolution),
    HolonSpec("claude-agent", "Claude Sovereign Reviewer", "sovereign", 7, SovereignEvolution),
    HolonSpec("codex-agent", "Codex Sovereign Verification Agent", "sovereign", 7, SovereignEvolution),
  ]
}

// =============================================================================
// 3. Ecology Initialization
// =============================================================================

pub fn init_living_swarm() -> SwarmEcology {
  let specs = all_21_holon_specs()
  let holons =
    list.map(specs, fn(spec) {
      let h = create_super_agent(spec.id, spec.name, spec.plane, spec.level)
      // Awaken holon twice: Dormant -> Awakening -> Active
      let awakened = case awaken(h) {
        Ok(a) -> case awaken(a) {
          Ok(active) -> active
          Error(_) -> a
        }
        Error(_) -> h
      }
      set_mode(awakened, spec.mode)
    })

  let initial_song =
    compose_swarm_song(1_788_888_000_000_000, 1, [], -3.732, 2.67)

  SwarmEcology(
    epoch_us: 1_788_888_000_000_000,
    cycle_counter: 0,
    beat_number: 1,
    holons: holons,
    current_song: initial_song,
    collective_energy: 100.0,
    lyapunov_exponent: -3.732,
    shannon_entropy: 2.67,
    is_harmonic: True,
  )
}

// =============================================================================
// 4. Autonomic Swarm Cycle Runner ("It Must Sing")
// =============================================================================

pub fn step_swarm_cycle(ecology: SwarmEcology) -> SwarmEcology {
  let next_cycle = ecology.cycle_counter + 1
  let next_beat = { ecology.beat_number % 16 } + 1
  let next_epoch = ecology.epoch_us + 100_000

  // 1. Advance each holon through its autonomic heartbeat
  let updated_holons =
    list.map(ecology.holons, fn(h) {
      let #(pulsed, _report) = execute_autonomic_pulse(h, 5.0, 5.0)
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

  // 3. Compose collective harmonic song
  let song =
    compose_swarm_song(
      next_epoch,
      next_beat,
      voices,
      ecology.lyapunov_exponent,
      ecology.shannon_entropy,
    )

  let is_harmonic =
    song.harmonic_consonance >=. 0.40
    && song.lyapunov_exponent <. 0.0
    && song.shannon_entropy_bits >=. 2.50

  SwarmEcology(
    epoch_us: next_epoch,
    cycle_counter: next_cycle,
    beat_number: next_beat,
    holons: updated_holons,
    current_song: song,
    collective_energy: float.max(50.0, 100.0 -. song.harmonic_consonance *. 10.0),
    lyapunov_exponent: ecology.lyapunov_exponent,
    shannon_entropy: ecology.shannon_entropy,
    is_harmonic: is_harmonic,
  )
}

// =============================================================================
// 5. Multi-Capability Direct Invocation
// =============================================================================

pub fn invoke_capability(
  holon: SuperAgentHolon,
  capability_name: String,
) -> Result(SuperAgentHolon, String) {
  let mask = holon.mask
  case capability_name {
    "fprime" if mask.fprime -> {
      let fp = holon.fprime
      let updated_fp = super_agent.FPrimeState(..fp, rate_group_hz: fp.rate_group_hz +. 1.0)
      Ok(super_agent.SuperAgentHolon(..holon, fprime: updated_fp))
    }
    "bayesian" if mask.bayesian -> {
      let b = holon.bayesian
      let updated_b = super_agent.BayesianState(..b, alpha_health: b.alpha_health +. 1.0)
      Ok(super_agent.SuperAgentHolon(..holon, bayesian: updated_b))
    }
    "rete_ul" if mask.rete_ul -> {
      let r = holon.rete_ul
      let updated_r = super_agent.ReteULState(..r, rules_fired: r.rules_fired + 1)
      Ok(super_agent.SuperAgentHolon(..holon, rete_ul: updated_r))
    }
    "ets" if mask.ets -> {
      let e = holon.ets
      let updated_e = super_agent.EtsState(..e, cached_entries: e.cached_entries + 1)
      Ok(super_agent.SuperAgentHolon(..holon, ets: updated_e))
    }
    "stm" if mask.stm -> {
      let s = holon.stm
      let updated_s = super_agent.StmState(..s, telemetry_snapshot_version: s.telemetry_snapshot_version + 1)
      Ok(super_agent.SuperAgentHolon(..holon, stm: updated_s))
    }
    "modular_max" if mask.modular_max -> {
      let m = holon.mojo_max
      let updated_m = super_agent.MojoMaxState(..m, cached_vectors: m.cached_vectors + 1)
      Ok(super_agent.SuperAgentHolon(..holon, mojo_max: updated_m))
    }
    "openrouter_free" if mask.openrouter_free -> {
      let o = holon.openrouter_free
      let updated_o = super_agent.OpenRouterFreeState(..o, advisory_tokens_spent: o.advisory_tokens_spent + 64)
      Ok(super_agent.SuperAgentHolon(..holon, openrouter_free: updated_o))
    }
    "ruliad" if mask.ruliad -> {
      let r = holon.ruliad
      let updated_r = super_agent.RuliadState(..r, multiway_step: r.multiway_step + 1)
      Ok(super_agent.SuperAgentHolon(..holon, ruliad: updated_r))
    }
    "formal_twin" if mask.formal_twin -> {
      let f = holon.formal_twin
      let updated_f = super_agent.FormalTwinState(..f, lean4_theorems_proved: f.lean4_theorems_proved + 1)
      Ok(super_agent.SuperAgentHolon(..holon, formal_twin: updated_f))
    }
    "denotational" if mask.denotational -> {
      let d = holon.denotational
      let updated_d = super_agent.DenotationalState(..d, aspects_satisfied: 17)
      Ok(super_agent.SuperAgentHolon(..holon, denotational: updated_d))
    }
    "algebraic_atlas" if mask.algebraic_atlas -> {
      let a = holon.algebraic_atlas
      let updated_a = super_agent.AlgebraicAtlasState(..a, charts_glued: a.charts_glued + 1)
      Ok(super_agent.SuperAgentHolon(..holon, algebraic_atlas: updated_a))
    }
    _ -> Error("Capability " <> capability_name <> " is inactive or unrecognized under current mode mask")
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
    #("collective_energy", json.float(ecology.collective_energy)),
    #("lyapunov_exponent", json.float(ecology.lyapunov_exponent)),
    #("shannon_entropy", json.float(ecology.shannon_entropy)),
    #("is_harmonic", json.bool(ecology.is_harmonic)),
    #("song", song_to_json(ecology.current_song)),
    #("holons", json.array(ecology.holons, to_json)),
  ])
}
