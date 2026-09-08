//// Shared observation contract for homeostasis GUI, TUI and HTTP surfaces.
//// SC-HOMEO-UI-001: display evidence never authorizes a control action.
//// An attributed observation is not a proof, admission or deployment receipt.

import cepaf_gleam/ha/homeostasis_evolution_engine.{type HomeostasisSystemState}
import cepaf_gleam/ha/beam_metrics
import cepaf_gleam/ha/physiological_homeostasis as physiology
import gleam/json
import gleam/int
import gleam/float
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Status {
  Unavailable
  Simulated
  Observed
  Stale
}

pub opaque type Snapshot {
  Missing
  Simulation(HomeostasisSystemState)
  Observation(HomeostasisSystemState, String, Int, Int)
  RuntimeObservation(beam_metrics.BeamMetrics, Int)
}

pub fn runtime_observation(metrics: beam_metrics.BeamMetrics, now_us: Int) -> Snapshot {
  case now_us > 0 && metrics.scheduler_count > 0 && metrics.process_count > 0
    && list.all([metrics.memory_total_mb, metrics.memory_processes_mb,
      metrics.memory_ets_mb, metrics.memory_binary_mb, metrics.run_queue_length,
      metrics.uptime_seconds, metrics.io_input_mb, metrics.io_output_mb,
      metrics.atom_count, metrics.port_count], fn(value) { value >= 0 }) {
    True -> RuntimeObservation(metrics, now_us)
    False -> Missing
  }
}

pub fn runtime_metrics(snapshot: Snapshot) -> Option(beam_metrics.BeamMetrics) {
  case snapshot { RuntimeObservation(metrics, _) -> Some(metrics) _ -> None }
}

pub fn unavailable() -> Snapshot {
  Missing
}

pub fn simulated(state: HomeostasisSystemState) -> Snapshot {
  Simulation(state)
}

/// Called only by a trusted telemetry adapter, never by a browser payload.
/// Receipt time cannot stand in for the source's observation time.
/// Clock discontinuities are rejected; the TTL is capped at one minute.
pub fn observation(
  state: HomeostasisSystemState,
  source: String,
  observed_at_us: Int,
  received_at_us: Int,
  ttl_us: Int,
) -> Result(Snapshot, String) {
  case string.trim(source) == "" || string.length(source) > 200
    || observed_at_us <= 0 || received_at_us < observed_at_us
    || state.metrics.timestamp_us != observed_at_us
    || ttl_us <= 0 || ttl_us > 60_000_000
    || state.metrics.measured_health <. 0.0
    || state.metrics.measured_health >. 1.0
    || state.metrics.lyapunov_v <. 0.0 {
    True -> Error("invalid observation metadata or metrics")
    False -> Ok(Observation(state, source, observed_at_us, ttl_us))
  }
}

pub fn status(snapshot: Snapshot, now_us: Int) -> Status {
  case snapshot {
    Missing -> Unavailable
    Simulation(_) -> Simulated
    RuntimeObservation(_, at) if now_us < at -> Unavailable
    RuntimeObservation(_, at) if now_us - at >= 5_000_000 -> Stale
    RuntimeObservation(_, _) -> Observed
    Observation(_, _, at, _) if now_us < at -> Unavailable
    Observation(_, _, at, ttl) if now_us - at >= ttl -> Stale
    Observation(_, _, _, _) -> Observed
  }
}

pub fn label(value: Status) -> String {
  case value {
    Unavailable -> "UNAVAILABLE"
    Simulated -> "SIMULATED"
    Observed -> "OBSERVED"
    Stale -> "STALE"
  }
}

/// Old samples remain available for explicitly labelled inspection, never control.
pub fn state(snapshot: Snapshot) -> Option(HomeostasisSystemState) {
  case snapshot {
    Missing | RuntimeObservation(_, _) -> None
    Simulation(value) | Observation(value, _, _, _) -> Some(value)
  }
}

pub fn source(snapshot: Snapshot) -> String {
  case snapshot {
    Missing -> "No trusted homeostasis telemetry adapter is connected."
    Simulation(_) -> "Deterministic model fixture; no live health or peer presence."
    Observation(_, origin, _, _) -> origin
    RuntimeObservation(_, _) -> "Observed local BEAM counters; CPU percentage, host memory percentage, latency, error rate, PID convergence and peer quorum are unavailable."
  }
}

pub fn observed_at(snapshot: Snapshot) -> Option(Int) {
  case snapshot {
    Observation(_, _, at, _) -> Some(at)
    RuntimeObservation(_, at) -> Some(at)
    _ -> None
  }
}

pub fn to_json(snapshot: Snapshot, now_us: Int) -> String {
  let current = status(snapshot, now_us)
  let #(at, age, ttl) = case snapshot {
    Observation(_, _, time, lifetime) -> #(
      json.int(time),
      case now_us >= time {
        True -> json.int(now_us - time)
        False -> json.null()
      },
      json.int(lifetime),
    )
    RuntimeObservation(_, time) -> #(json.int(time), case now_us >= time { True -> json.int(now_us - time) False -> json.null() }, json.int(5_000_000))
    _ -> #(json.null(), json.null(), json.null())
  }
  let metrics = case state(snapshot), current {
    Some(value), Observed | Some(value), Simulated -> json.object([
      #("measured_health", json.float(value.metrics.measured_health)),
      #("lyapunov_v", json.float(value.metrics.lyapunov_v)),
      #("stable", json.bool(value.metrics.stable)),
    ])
    _, _ -> json.null()
  }
  json.object([
    #("page", json.string("Homeostasis")),
    #("fields", json.array(fields(snapshot, now_us), fn(row) {
      let #(id, label, value) = row
      json.object([#("id", json.string(id)), #("label", json.string(label)), #("value", json.string(value))])
    })),
    #("schema_version", json.int(1)),
    #("status", json.string(string.lowercase(label(current)))),
    #("source", json.string(source(snapshot))),
    #("observed_at_us", at),
    #("age_us", age),
    #("ttl_us", ttl),
    #("metrics", metrics),
    #("runtime", case runtime_metrics(snapshot), current {
      Some(value), Observed -> json.object([
        #("scheduler_count", json.int(value.scheduler_count)),
        #("process_count", json.int(value.process_count)),
        #("memory_total_mib", json.int(value.memory_total_mb)),
        #("run_queue_length", json.int(value.run_queue_length)),
        #("uptime_seconds", json.int(value.uptime_seconds)),
        #("atom_count", json.int(value.atom_count)),
        #("port_count", json.int(value.port_count)),
      ])
      _, _ -> json.null()
    }),
    #("peer_presence", json.string("unknown")),
    #("verification", json.string("not_verified")),
    #("control_authority", json.string("none")),
  ])
  |> json.to_string()
}

/// A single denotation consumed by GUI cells, TUI rows and the API.
pub fn fields(snapshot: Snapshot, now_us: Int) -> List(#(String, String, String)) {
  let unknown = "UNKNOWN"
  let metrics = case state(snapshot), status(snapshot, now_us) {
    Some(s), Observed | Some(s), Simulated -> [
      #("health", "Attributed health", float.to_string(s.metrics.measured_health)),
      #("error", "Error e(t)", float.to_string(s.metrics.error)),
      #("control", "PID output", float.to_string(s.metrics.control_output)),
      #("energy", "Quadratic energy V", float.to_string(s.metrics.lyapunov_v)),
      #("energy_change", "Sampled energy change", float.to_string(s.metrics.lyapunov_dot_v)),
      #("stable", "Model stability heuristic", case s.metrics.stable { True -> "stable" False -> "unstable" }),
      #("phase", "Model phase", case s.phase {
        homeostasis_evolution_engine.Converging(_, _) -> "Converging"
        homeostasis_evolution_engine.HomeostaticEquilibrium(_, _) -> "Equilibrium"
        homeostasis_evolution_engine.AutonomousEvolutionActive(_, _) -> "Model evolution active"
        homeostasis_evolution_engine.InstabilityIntervention(_) -> "Intervention"
      }),
      #("generation", "Model generation", int.to_string(s.generation)),
      #("model_time", "Model time (microseconds)", int.to_string(s.metrics.timestamp_us)),
      #("stress", "Model composite stress", float.to_string(s.physiological.composite_stress)),
      #("candidates", "Pareto candidate count", int.to_string(list.length(s.pareto_candidates))),
      #("quorum", "Voting evidence", "SIMULATED model; no peer contact"),
      ..list.map(s.physiological.variables, fn(v) {
        let name = physiology.variable_to_string(v.variable)
        #(name, name, float.to_string(v.measurement))
      })
    ]
    _, _ -> list.map([#("health", "Attributed health"), #("error", "Error e(t)"), #("control", "PID output"), #("energy", "Quadratic energy V"), #("energy_change", "Sampled energy change"), #("stable", "Model stability heuristic"), #("phase", "Model phase"), #("generation", "Model generation"), #("model_time", "Model time (microseconds)"), #("stress", "Model composite stress"), #("cpu_pct", "CPU percentage"), #("memory_pct", "Host memory percentage"), #("latency_ms", "Request latency ms"), #("error_rate_pct", "Error rate percentage")], fn(p) { #(p.0, p.1, unknown) })
  }
  let runtime = case runtime_metrics(snapshot), status(snapshot, now_us) {
    Some(m), Observed -> [#("schedulers", "Online schedulers", int.to_string(m.scheduler_count)), #("processes", "BEAM processes", int.to_string(m.process_count)), #("vm_memory", "BEAM memory MiB", int.to_string(m.memory_total_mb)), #("run_queue", "Run queue length", int.to_string(m.run_queue_length)), #("uptime", "VM uptime seconds", int.to_string(m.uptime_seconds))]
    _, _ -> list.map([#("schedulers", "Online schedulers"), #("processes", "BEAM processes"), #("vm_memory", "BEAM memory MiB"), #("run_queue", "Run queue length"), #("uptime", "VM uptime seconds")], fn(p) { #(p.0, p.1, unknown) })
  }
  let missing_fields = case state(snapshot), status(snapshot,now_us) { Some(_), Observed | Some(_), Simulated -> [] _, _ -> [#("candidates", "Pareto candidate count", unknown), #("quorum", "Voting evidence", unknown)] }
  list.append(list.append(metrics, runtime), missing_fields)
}
