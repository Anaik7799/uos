//// =============================================================================
//// [UOS-FPP-AGENT-FACTORY] NASA JPL F Prime / FPP Aerospace Agent Factory
//// =============================================================================
//// Runtime agent instantiation, Hierarchical State Machine execution,
//// telemetry sampling, and denotational intent gatekeeping on BEAM OTP 29.
//// =============================================================================

import cepaf_gleam/fpp/agent_taxonomy.{
  type AgentKind, type AgentTypeSpec, agent_kind_to_string, find_agent_type_spec,
}
import cepaf_gleam/fpp/dmc_tcm.{type Tcm13DVector, canonical_fpp_tcm_vector}
import cepaf_gleam/fpp/intent.{
  type FlightVerb, type IntentVerdict, FlightIntent, evaluate_flight_intent,
}
import cepaf_gleam/fpp/interp.{
  type HierarchicalMachineState, dispatch_hsm_signal, init_hsm,
}
import gleam/int
import gleam/json
import gleam/list

// =============================================================================
// Agent State Types
// =============================================================================

pub type AgentStatus {
  AgentNominal
  AgentDegraded
  AgentTripped
  AgentSafeHold
}

pub fn agent_status_to_string(status: AgentStatus) -> String {
  case status {
    AgentNominal -> "NOMINAL"
    AgentDegraded -> "DEGRADED"
    AgentTripped -> "TRIPPED"
    AgentSafeHold -> "SAFE_HOLD"
  }
}

pub type AgentTelemetrySample {
  AgentTelemetrySample(
    channel_id: Int,
    channel_name: String,
    value: Float,
    timestamp_utc: String,
  )
}

pub type AgentInstance {
  AgentInstance(
    id: String,
    kind: AgentKind,
    spec: AgentTypeSpec,
    hsm_state: HierarchicalMachineState,
    telemetry_samples: List(AgentTelemetrySample),
    tcm_vector: Tcm13DVector,
    created_at_utc: String,
    heartbeat_count: Int,
    status: AgentStatus,
  )
}

// =============================================================================
// Factory Functions
// =============================================================================

pub fn instantiate_agent(
  kind: AgentKind,
  instance_id: String,
) -> Result(AgentInstance, String) {
  case find_agent_type_spec(kind) {
    Error(_) -> Error("Unknown agent kind: " <> agent_kind_to_string(kind))
    Ok(spec) -> {
      case init_hsm(spec.hsm_machine) {
        Error(err) ->
          Error("Failed to initialize HSM for " <> spec.name <> ": " <> err)
        Ok(initial_hsm) -> {
          let tcm = canonical_fpp_tcm_vector(instance_id, 0)
          Ok(AgentInstance(
            id: instance_id,
            kind: kind,
            spec: spec,
            hsm_state: initial_hsm,
            telemetry_samples: [],
            tcm_vector: tcm,
            created_at_utc: "2026-09-06T09:45:00.000000Z",
            heartbeat_count: 0,
            status: AgentNominal,
          ))
        }
      }
    }
  }
}

pub fn dispatch_signal(
  agent: AgentInstance,
  signal: String,
) -> Result(AgentInstance, String) {
  case
    dispatch_hsm_signal(agent.spec.hsm_machine, [], agent.hsm_state, signal)
  {
    Error(err) -> Error(err)
    Ok(new_hsm) -> {
      let new_step = agent.tcm_vector.c_causality + 1
      let updated_tcm = canonical_fpp_tcm_vector(agent.id, new_step)
      Ok(AgentInstance(..agent, hsm_state: new_hsm, tcm_vector: updated_tcm))
    }
  }
}

pub fn emit_telemetry(
  agent: AgentInstance,
  channel_name: String,
  value: Float,
) -> AgentInstance {
  let sample_id = agent.spec.base_id + list.length(agent.telemetry_samples)
  let sample =
    AgentTelemetrySample(
      channel_id: sample_id,
      channel_name: channel_name,
      value: value,
      timestamp_utc: "2026-09-06T09:45:00.000000Z",
    )
  let updated_samples = list.append(agent.telemetry_samples, [sample])
  AgentInstance(..agent, telemetry_samples: updated_samples)
}

pub fn execute_agent_intent(
  agent: AgentInstance,
  verb: FlightVerb,
  target_device_serial: String,
) -> IntentVerdict {
  let fl_intent =
    FlightIntent(
      intent_id: "INT-"
        <> agent.id
        <> "-"
        <> int.to_string(agent.heartbeat_count),
      actor: agent.spec.name,
      verb: verb,
      target_instance: agent.id,
      target_device_serial: target_device_serial,
      precondition_guard: True,
      formal_proof_ref: "PROOF-FPP-AGT-" <> agent.id,
    )

  evaluate_flight_intent(fl_intent)
}

pub fn heartbeat(agent: AgentInstance) -> AgentInstance {
  let next_count = agent.heartbeat_count + 1
  let next_causality = agent.tcm_vector.c_causality + 1
  let updated_tcm = canonical_fpp_tcm_vector(agent.id, next_causality)
  AgentInstance(..agent, heartbeat_count: next_count, tcm_vector: updated_tcm)
}

// =============================================================================
// JSON Encoding
// =============================================================================

fn encode_telemetry_sample_json(sample: AgentTelemetrySample) -> json.Json {
  json.object([
    #("channel_id", json.int(sample.channel_id)),
    #("channel_name", json.string(sample.channel_name)),
    #("value", json.float(sample.value)),
    #("timestamp_utc", json.string(sample.timestamp_utc)),
  ])
}

pub fn encode_agent_instance_json(agent: AgentInstance) -> String {
  json.object([
    #("id", json.string(agent.id)),
    #("kind", json.string(agent_kind_to_string(agent.kind))),
    #("name", json.string(agent.spec.name)),
    #("fractal_layer", json.int(agent.spec.fractal_layer)),
    #("fractal_tag", json.string(agent.spec.fractal_tag)),
    #("base_id", json.int(agent.spec.base_id)),
    #("status", json.string(agent_status_to_string(agent.status))),
    #("heartbeat_count", json.int(agent.heartbeat_count)),
    #(
      "active_hsm_path",
      json.array(agent.hsm_state.active_path, of: json.string),
    ),
    #(
      "telemetry_samples",
      json.array(agent.telemetry_samples, of: encode_telemetry_sample_json),
    ),
    #("created_at_utc", json.string(agent.created_at_utc)),
    #("contract", json.string("SC-FPP-AGENT-FACTORY-001")),
  ])
  |> json.to_string
}
