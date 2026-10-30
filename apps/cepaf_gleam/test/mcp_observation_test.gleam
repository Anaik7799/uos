import cepaf_gleam/mcp/adapters/system_observation
import cepaf_gleam/mcp/types.{Complete, Refused, Retryable}
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

fn fresh_snapshot(candidate: String) -> system_observation.ObservationBackend {
  system_observation.ObservedSnapshot(
    candidate: candidate,
    backend_name: "fixture-observation",
    observed_at_ms: 1000,
    max_age_ms: 5000,
    containers: Some([]),
    metrics: dict.from_list([#("status", "healthy")]),
  )
}

pub fn missing_backend_is_unknown_not_healthy_test() {
  let backend =
    system_observation.MissingBackend("system_immune", "unix socket refused")
  let outcome =
    system_observation.observe(backend, 1000, "system_immune", dict.new())
  case outcome {
    Refused(error) -> {
      error.code |> should.equal("OBSERVATION_BACKEND_UNAVAILABLE")
      error.retryability |> should.equal(Retryable)
      string.contains(error.reason, "state=unknown") |> should.be_true()
    }
    Complete(payload, _) -> {
      string.contains(payload, "healthy") |> should.be_false()
      should.fail()
    }
    _ -> should.fail()
  }
}

pub fn zero_containers_requires_successful_probe_test() {
  let no_probe =
    system_observation.ObservedSnapshot(
      candidate: "uos-mcp",
      backend_name: "podman",
      observed_at_ms: 1000,
      max_age_ms: 5000,
      containers: None,
      metrics: dict.new(),
    )
  case
    system_observation.observe(no_probe, 1000, "podman_containers", dict.new())
  {
    Refused(error) -> error.code |> should.equal("CONTAINER_PROBE_MISSING")
    _ -> should.fail()
  }

  let empty_probe =
    system_observation.ObservedSnapshot(
      candidate: "uos-mcp",
      backend_name: "podman",
      observed_at_ms: 1000,
      max_age_ms: 5000,
      containers: Some([]),
      metrics: dict.new(),
    )
  case
    system_observation.observe(
      empty_probe,
      1000,
      "podman_containers",
      dict.new(),
    )
  {
    Complete(payload, _) -> {
      let decoder = {
        use count <- decode.field("container_count", decode.int)
        decode.success(count)
      }
      case json.parse(payload, decoder) {
        Ok(0) -> Nil
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}

pub fn stale_sample_cannot_pass_health_test() {
  let stale =
    system_observation.ObservedSnapshot(
      candidate: "uos-mcp",
      backend_name: "system_immune",
      observed_at_ms: 1000,
      max_age_ms: 100,
      containers: Some([]),
      metrics: dict.new(),
    )
  case system_observation.observe(stale, 5000, "system_health", dict.new()) {
    Refused(error) -> error.code |> should.equal("STALE_OBSERVATION_SAMPLE")
    _ -> should.fail()
  }

  let future =
    system_observation.ObservedSnapshot(
      candidate: "uos-mcp",
      backend_name: "system_immune",
      observed_at_ms: 9000,
      max_age_ms: 5000,
      containers: Some([]),
      metrics: dict.new(),
    )
  case system_observation.observe(future, 1000, "system_health", dict.new()) {
    Refused(error) -> error.code |> should.equal("STALE_OBSERVATION_SAMPLE")
    _ -> should.fail()
  }
}

pub fn unhealthy_observed_snapshot_never_renders_healthy_test() {
  let backend =
    system_observation.ObservedSnapshot(
      candidate: "uos-mcp",
      backend_name: "fixture-observation",
      observed_at_ms: 1000,
      max_age_ms: 5000,
      containers: Some([]),
      metrics: dict.from_list([#("status", "unhealthy")]),
    )

  case system_observation.observe(backend, 1000, "system_health", dict.new()) {
    Complete(payload, _) -> {
      string.contains(payload, "\"status\":\"unhealthy\"") |> should.be_true()
      string.contains(payload, "\"healthy\"") |> should.be_false()
    }
    _ -> should.fail()
  }

  case system_observation.observe(backend, 1000, "system_zenoh", dict.new()) {
    Complete(payload, _) -> {
      string.contains(payload, "\"status\":\"unhealthy\"") |> should.be_true()
      string.contains(payload, "\"connected\":false") |> should.be_true()
      string.contains(payload, "\"healthy\"") |> should.be_false()
    }
    _ -> should.fail()
  }
}

pub fn missing_probe_metric_refuses_rather_than_synthesising_test() {
  let backend =
    system_observation.ObservedSnapshot(
      candidate: "uos-mcp",
      backend_name: "fixture-observation",
      observed_at_ms: 1000,
      max_age_ms: 5000,
      containers: Some([]),
      metrics: dict.new(),
    )
  case system_observation.observe(backend, 1000, "system_health", dict.new()) {
    Refused(error) -> error.code |> should.equal("OBSERVATION_PROBE_MISSING")
    _ -> should.fail()
  }
}

pub fn all_19_observation_tools_carry_freshness_and_preview_bounds_test() {
  let tools = [
    "system_health", "system_dashboard", "system_immune", "system_zenoh",
    "system_verification", "podman_containers", "metabolic_state", "ooda_phase",
    "fractal_status", "prajna_health", "dark_cockpit_mode", "integrity_check",
    "evolution_metrics", "mesh_topology", "ooda_decide", "kms_catalog",
    "holon_status", "swarm_status", "agent_hierarchy",
  ]
  tools |> list.length |> should.equal(19)
  list.each(tools, fn(tool_name) {
    case
      system_observation.observe(
        fresh_snapshot("uos-mcp"),
        1000,
        tool_name,
        dict.new(),
      )
    {
      Complete(payload, _) -> {
        string.contains(payload, "\"observed_at_ms\":1000")
        |> should.be_true()
        string.contains(payload, "\"max_age_ms\":5000")
        |> should.be_true()
        string.contains(payload, "\"effect_authority\":false")
        |> should.be_true()
        string.contains(payload, "\"preview_bounds\"") |> should.be_true()
      }
      _ -> should.fail()
    }
  })
}
