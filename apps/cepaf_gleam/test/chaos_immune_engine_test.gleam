//// =============================================================================
//// [C3I-SIL6-MSTS] BIOMORPHIC CHAOS IMMUNE ENGINE TEST CONTRACT
//// =============================================================================

import cepaf_gleam/immune/chaos_immune_engine.{
  AntibodyNeutralized, AndonEmergencyHalt, HeartbeatJitter, HotReloadTriggered,
  PacketLoss, WorkerOom, compute_metabolic_health, init_immune_engine,
  inject_fault, is_containment_preserved, synthesize_antibody,
}
import gleam/list
import gleeunit/should

pub fn immune_init_test() {
  let engine = init_immune_engine()
  list.length(engine.antibodies) |> should.equal(4)
  engine.is_andon_tripped |> should.equal(False)
  should.be_true(engine.lyapunov_exponent <. 0.0)
}

pub fn immune_packet_loss_neutralize_test() {
  let engine = init_immune_engine()
  let #(s, resp) = inject_fault(engine, PacketLoss(0.2))
  s.total_faults_injected |> should.equal(1)
  s.total_neutralized |> should.equal(1)
  case resp {
    AntibodyNeutralized(id, _) -> id |> should.equal("AB-NET-01")
    _ -> panic as "Expected antibody neutralization"
  }
}

pub fn immune_catastrophic_packet_loss_andon_test() {
  let engine = init_immune_engine()
  let #(s, resp) = inject_fault(engine, PacketLoss(0.85))
  s.is_andon_tripped |> should.equal(True)
  case resp {
    AndonEmergencyHalt(_) -> should.be_true(True)
    _ -> panic as "Expected Andon halt"
  }
}

pub fn immune_worker_oom_hot_reload_test() {
  let engine = init_immune_engine()
  let #(s, resp) = inject_fault(engine, WorkerOom("1"))
  s.total_neutralized |> should.equal(1)
  case resp {
    HotReloadTriggered(comp) -> comp |> should.equal("worker_pool_1")
    _ -> panic as "Expected hot reload"
  }
}

pub fn immune_synthesize_antibody_test() {
  let engine = init_immune_engine()
  let updated = synthesize_antibody(engine, "packet_loss")
  case list.find(updated.antibodies, fn(ab) { ab.target_fault == "packet_loss" }) {
    Ok(ab) -> {
      ab.generation |> should.equal(2)
      should.be_true(ab.potency >=. 0.95)
    }
    Error(_) -> panic as "Expected synthesized antibody"
  }
}

pub fn immune_metabolic_health_test() {
  let engine = init_immune_engine()
  let health = compute_metabolic_health(engine)
  should.be_true(health >=. 0.8)
  should.be_true(is_containment_preserved(engine))
}
