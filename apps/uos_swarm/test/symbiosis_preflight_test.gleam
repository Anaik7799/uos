import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import uos_swarm/symbiosis_preflight as p

fn binding(session: String) {
  p.Binding(string.repeat("a", 40), string.repeat("b", 64), session)
}

fn bindings() {
  [
    #(p.Claude, binding("claude-private")),
    #(p.Pi, binding("pi-private")),
    #(p.Agy, binding("agy-private")),
    #(p.Codex, binding("codex-private")),
  ]
}

fn initial() {
  let assert Ok(s) = p.new(bindings(), p.defaults(), 0)
  s
}

fn yes() {
  p.Results(Some(True), Some(True), Some(True))
}

fn observation(r: p.Request, results: p.Results, now: Int) {
  p.Observation(
    r.seq,
    r.binding,
    now,
    now - r.started_ms,
    results,
    p.ProbeFailed,
  )
}

fn complete(s: p.State, r: p.Request, results: p.Results, now: Int) {
  let assert Ok(s) = p.record(s, r, observation(r, results, now), now)
  s
}

fn target(
  s: p.State,
  a: p.Agent,
  probe: p.Probe,
  now: Int,
  left: Int,
) -> #(p.State, p.Request, Int) {
  let assert True = left > 0
  let assert Ok(#(s, request)) = p.poll(s, now)
  case request {
    Some(r) if r.agent == a && r.probe == probe -> #(s, r, now)
    Some(r) ->
      target(complete(s, r, yes(), now), a, probe, now + 1000, left - 1)
    None -> target(s, a, probe, now + 1000, left - 1)
  }
}

fn get_cap(s: p.State, a: p.Agent, c: p.Capability, now: Int) {
  target(s, a, p.CapabilityProbe(c), now, 1000)
}

pub fn registry_exact_four_agents_eight_capabilities_test() {
  list.length(p.agents()) |> should.equal(4)
  list.length(p.capabilities()) |> should.equal(8)
  list.each(p.agents(), fn(a) {
    list.each(p.capabilities(), fn(c) {
      list.each([p.Function, p.Performance, p.Operation], fn(d) {
        p.status(initial(), a, c, d, 0) |> should.equal(p.Unknown)
      })
    })
  })
}

pub fn invalid_bindings_config_and_negative_monotonic_origin_test() {
  p.new(bindings(), p.defaults(), -576_460_000_000) |> should.be_ok
  p.new([], p.defaults(), 0) |> should.be_error
  p.new(
    [
      #(p.Pi, binding("one")),
      #(p.Pi, binding("two")),
      #(p.Agy, binding("three")),
      #(p.Codex, binding("four")),
    ],
    p.defaults(),
    0,
  )
  |> should.be_error
  let bad = p.Binding(string.repeat("A", 40), string.repeat("b", 64), "session")
  p.new(
    [
      #(p.Claude, bad),
      #(p.Pi, binding("pi")),
      #(p.Agy, binding("agy")),
      #(p.Codex, binding("codex")),
    ],
    p.defaults(),
    0,
  )
  |> should.be_error
  p.new(bindings(), p.Config(..p.defaults(), minimum_spacing_ms: 0), 0)
  |> should.be_error
  p.new(bindings(), p.Config(..p.defaults(), jitter_ms: 10_001), 0)
  |> should.be_error
  p.new(bindings(), p.Config(..p.defaults(), timeout_ms: 30_001), 0)
  |> should.be_error
}

pub fn single_global_flight_and_minimum_spacing_test() {
  let assert Ok(#(s, Some(r))) = p.poll(initial(), 0)
  let assert Ok(#(_, next)) = p.poll(s, 1000)
  next |> should.equal(None)
  let s = complete(s, r, yes(), 1000)
  let assert Ok(#(s, next)) = p.poll(s, 1000)
  // Spacing is measured between dispatches, not completions.
  next |> should.be_some
  let assert Some(r) = next
  let s = complete(s, r, yes(), 1000)
  let assert Ok(#(_, next)) = p.poll(s, 1001)
  next |> should.equal(None)
}

pub fn independent_dimensions_one_observation_test() {
  let #(s, r, now) = get_cap(initial(), p.Claude, p.KnowledgeRead, 0)
  let s = complete(s, r, p.Results(Some(True), None, Some(False)), now)
  p.status(s, p.Claude, p.KnowledgeRead, p.Function, now)
  |> should.equal(p.Ready)
  p.status(s, p.Claude, p.KnowledgeRead, p.Performance, now)
  |> should.equal(p.Unknown)
  p.status(s, p.Claude, p.KnowledgeRead, p.Operation, now)
  |> should.equal(p.Stopped)
  p.status(s, p.Pi, p.KnowledgeRead, p.Function, now) |> should.equal(p.Unknown)
}

pub fn pending_binding_sequence_and_clock_guards_test() {
  let assert Ok(#(s, Some(r))) = p.poll(initial(), 0)
  let o = observation(r, yes(), 1)
  p.record(s, r, p.Observation(..o, seq: r.seq + 1), 1) |> should.be_error
  p.record(s, r, p.Observation(..o, binding: binding("different")), 1)
  |> should.be_error
  p.record(s, r, p.Observation(..o, observed_ms: 2), 1) |> should.be_error
  p.record(s, r, p.Observation(..o, elapsed_ms: 999), 1) |> should.be_error
  p.record(s, r, o, 10_001) |> should.be_error
  let s = complete(s, r, yes(), 1)
  p.record(s, r, o, 1) |> should.be_error
  p.poll(s, 0) |> should.be_error
}

pub fn heartbeat_cannot_clear_functional_failure_test() {
  let #(s, r, now) = get_cap(initial(), p.Claude, p.KnowledgeRead, 0)
  let s = complete(s, r, p.Results(Some(False), Some(False), Some(False)), now)
  let #(s, hb, later) = target(s, p.Claude, p.HeartbeatProbe, now + 1000, 1000)
  let s = complete(s, hb, yes(), later)
  p.status(s, p.Claude, p.KnowledgeRead, p.Function, later)
  |> should.equal(p.Stopped)
}

pub fn recovery_needs_two_fresh_distinct_capability_probes_test() {
  let #(s, r, now) = get_cap(initial(), p.Claude, p.KnowledgeRead, 0)
  let s = complete(s, r, p.Results(Some(False), Some(False), Some(False)), now)
  let #(s, first, at) = get_cap(s, p.Claude, p.KnowledgeRead, now + 1000)
  let s = complete(s, first, yes(), at)
  p.status(s, p.Claude, p.KnowledgeRead, p.Function, at)
  |> should.equal(p.Stopped)
  p.record(s, first, observation(first, yes(), at), at) |> should.be_error
  let #(s, second, later) = get_cap(s, p.Claude, p.KnowledgeRead, at + 1000)
  { second.seq > first.seq } |> should.be_true
  let s = complete(s, second, yes(), later)
  p.status(s, p.Claude, p.KnowledgeRead, p.Function, later)
  |> should.equal(p.Ready)
}

pub fn expired_first_recovery_probe_does_not_clear_failure_test() {
  let #(s, r, now) = get_cap(initial(), p.Claude, p.KnowledgeRead, 0)
  let s = complete(s, r, p.Results(Some(False), Some(False), Some(False)), now)
  let #(s, first, at) = get_cap(s, p.Claude, p.KnowledgeRead, now + 1000)
  let s = complete(s, first, yes(), at)
  let #(s, second, later) = get_cap(s, p.Claude, p.KnowledgeRead, at + 300_001)
  let s = complete(s, second, yes(), later)
  p.status(s, p.Claude, p.KnowledgeRead, p.Function, later)
  |> should.equal(p.Stopped)
}

pub fn candidate_config_or_session_change_invalidates_only_agent_test() {
  let #(s, r, now) = get_cap(initial(), p.Claude, p.KnowledgeRead, 0)
  let s = complete(s, r, yes(), now)
  let #(s, r, later) = get_cap(s, p.Pi, p.KnowledgeRead, now + 1000)
  let s = complete(s, r, yes(), later)
  list.each(
    [
      p.Binding(..binding("claude-private"), candidate: string.repeat("c", 40)),
      p.Binding(..binding("claude-private"), config: string.repeat("d", 64)),
      binding("new-session"),
    ],
    fn(b) {
      let assert Ok(changed) = p.rebind(s, p.Claude, b, later)
      p.status(changed, p.Claude, p.KnowledgeRead, p.Function, later)
      |> should.equal(p.Unknown)
      p.status(changed, p.Pi, p.KnowledgeRead, p.Function, later)
      |> should.equal(p.Ready)
    },
  )
}

pub fn rebind_cancels_old_pending_and_duplicate_success_test() {
  let assert Ok(#(s, Some(r))) = p.poll(initial(), 0)
  let assert Ok(s) = p.rebind(s, p.Claude, binding("changed"), 1)
  p.record(s, r, observation(r, yes(), 1), 1) |> should.be_error
}

pub fn stale_cache_and_demand_coalescing_test() {
  let #(s, r, now) = get_cap(initial(), p.Claude, p.KnowledgeRead, 0)
  let s = complete(s, r, yes(), now)
  let assert Ok(s) =
    p.demand(s, p.Claude, p.CapabilityProbe(p.KnowledgeRead), now)
  p.status(s, p.Claude, p.KnowledgeRead, p.Function, now + 300_000)
  |> should.equal(p.Ready)
  p.status(s, p.Claude, p.KnowledgeRead, p.Function, now + 300_001)
  |> should.equal(p.Unknown)
  p.status(s, p.Claude, p.KnowledgeRead, p.Function, now - 1)
  |> should.equal(p.Stopped)
}

pub fn timeout_and_missing_results_fail_closed_test() {
  let #(s, r, now) = get_cap(initial(), p.Claude, p.KnowledgeRead, 0)
  let assert Ok(#(s, _)) = p.poll(s, now + 10_001)
  p.status(s, p.Claude, p.KnowledgeRead, p.Function, now + 10_001)
  |> should.equal(p.Stopped)
  p.record(s, r, observation(r, yes(), now + 10_001), now + 10_001)
  |> should.be_error
  let #(s, r, at) = get_cap(s, p.Pi, p.ModelBudget, now + 11_001)
  let s = complete(s, r, p.Results(None, None, None), at)
  p.status(s, p.Pi, p.ModelBudget, p.Function, at) |> should.equal(p.Unknown)
}

fn failures(
  s: p.State,
  n: Int,
  now: Int,
  seen: List(p.Agent),
) -> #(p.State, List(p.Agent), Int) {
  case n {
    0 -> #(s, seen, now)
    _ -> {
      let assert Ok(#(s, Some(r))) = p.poll(s, now)
      let assert Ok(s) = p.record_failure(s, r, p.ProbeUnavailable, now)
      failures(s, n - 1, now + 1000, [r.agent, ..seen])
    }
  }
}

pub fn fair_due_order_and_bounded_privacy_safe_rca_test() {
  let #(s, seen, now) = failures(initial(), 80, 0, [])
  list.each(p.agents(), fn(a) { list.contains(seen, a) |> should.be_true })
  let text = json.to_string(p.to_json(s, now))
  string.contains(text, "\"history_retained\":32") |> should.be_true
  string.contains(text, "UNKNOWN_EXACT_SERVICE_REGISTRY_NOT_PROVEN")
  |> should.be_true
  string.contains(text, "\"fixed_probe_keys\":40") |> should.be_true
  list.each(
    [
      "claude-private",
      "pi-private",
      string.repeat("a", 40),
      string.repeat("b", 64),
    ],
    fn(secret) { string.contains(text, secret) |> should.be_false },
  )
}

pub fn coverage_boolean_never_claims_all_services_test() {
  let #(s, r, now) = target(initial(), p.Claude, p.CoverageProbe, 0, 1000)
  let s = complete(s, r, yes(), now)
  let text = json.to_string(p.to_json(s, now))
  string.contains(text, "UNKNOWN_EXACT_SERVICE_REGISTRY_NOT_PROVEN")
  |> should.be_true
}

pub fn tier_mapping_test() {
  let b = binding("session")
  p.request_check(p.Request(1, p.Codex, p.HeartbeatProbe, b, 0))
  |> should.equal(p.Heartbeat)
  p.request_check(p.Request(2, p.Codex, p.CapabilityProbe(p.Verification), b, 0))
  |> should.equal(p.Functional)
  p.request_check(p.Request(3, p.Codex, p.CoverageProbe, b, 0))
  |> should.equal(p.FullCoverage)
}

fn healthy_simulation(
  s: p.State,
  now: Int,
  remaining: Int,
  seen: List(#(p.Agent, p.Probe)),
) -> #(p.State, List(#(p.Agent, p.Probe)), Int) {
  case remaining {
    0 -> #(s, seen, now)
    _ -> {
      // Startup cannot have evidence before the first four real probes finish.
      case now >= 4000 {
        True ->
          list.each(p.agents(), fn(a) {
            p.heartbeat_health(s, a, now) |> should.equal(p.Ready)
          })
        False -> Nil
      }
      let assert Ok(#(s, request)) = p.poll(s, now)
      let #(s, seen, finished) = case request {
        None -> #(s, seen, now)
        Some(r) -> {
          // Deterministic latency varies from50..200ms, rather than zero-time mocks.
          let finish = now + 50 + { r.seq % 151 }
          let key = #(r.agent, r.probe)
          let seen = case list.contains(seen, key) {
            True -> seen
            False -> [key, ..seen]
          }
          #(complete(s, r, yes(), finish), seen, finish)
        }
      }
      case now >= 4000 {
        True ->
          list.each(p.agents(), fn(a) {
            p.heartbeat_health(s, a, finished) |> should.equal(p.Ready)
          })
        False -> Nil
      }
      healthy_simulation(s, now + 1000, remaining - 1, seen)
    }
  }
}

pub fn healthy_default_bootstrap_and_later_cycles_keep_all_heartbeats_fresh_test() {
  // 2001seconds includes bootstrap, many300s functional cycles and1800s coverage.
  let #(s, seen, now) = healthy_simulation(initial(), 0, 2001, [])
  list.length(seen) |> should.equal(40)
  list.each(p.agents(), fn(a) {
    list.contains(seen, #(a, p.CoverageProbe)) |> should.be_true
    list.each(p.capabilities(), fn(c) {
      list.contains(seen, #(a, p.CapabilityProbe(c))) |> should.be_true
    })
    p.heartbeat_health(s, a, now) |> should.equal(p.Ready)
  })
}

fn overloaded_simulation(
  s: p.State,
  now: Int,
  remaining: Int,
  seen: List(#(p.Agent, p.Probe)),
) -> #(p.State, List(#(p.Agent, p.Probe)), Int) {
  case remaining {
    0 -> #(s, seen, now)
    _ -> {
      let assert Ok(#(s, Some(r))) = p.poll(s, now)
      let key = #(r.agent, r.probe)
      let seen = case list.contains(seen, key) {
        True -> seen
        False -> [key, ..seen]
      }
      overloaded_simulation(
        complete(s, r, yes(), now + 50),
        now + 1000,
        remaining - 1,
        seen,
      )
    }
  }
}

pub fn overloaded_heartbeat_lane_still_reserves_deep_progress_without_availability_claim_test() {
  // Four1000ms heartbeat cadences cannot fit one1000ms-spaced global flight.
  let c = p.Config(..p.defaults(), heartbeat_ms: 1000, timeout_ms: 100)
  let assert Ok(s) = p.new(bindings(), c, 0)
  let #(s, seen, now) = overloaded_simulation(s, 0, 220, [])
  list.length(seen) |> should.equal(40)
  list.any(p.agents(), fn(a) { p.heartbeat_health(s, a, now) != p.Ready })
  |> should.be_true
  json.to_string(p.to_json(s, now))
  |> string.contains("NONE_CAPACITY_AND_COLLECTOR_LATENCY_DEPENDENT")
  |> should.be_true
}

pub fn freshness_report_exposes_cadence_age_due_sequence_without_bindings_test() {
  let assert Ok(#(s, Some(r))) = p.poll(initial(), 0)
  let s = complete(s, r, yes(), 50)
  let text = json.to_string(p.to_json(s, 1050))
  list.each(
    [
      "\"heartbeat\":30000",
      "\"functional\":300000",
      "\"coverage\":1800000",
      "\"age_ms\":1000",
      "\"last_seq\":1",
      "function_age_ms",
      "performance_age_ms",
      "operation_age_ms",
      "next_due_in_ms",
    ],
    fn(field) { string.contains(text, field) |> should.be_true },
  )
  string.contains(text, "claude-private") |> should.be_false
}

pub fn advancing_expired_time_never_reserves_next_probe_test() {
  let #(s, _, now) = get_cap(initial(), p.Claude, p.KnowledgeRead, 0)
  let assert Ok(s) = p.advance_time(s, now + 10_001)
  p.status(s, p.Claude, p.KnowledgeRead, p.Function, now + 10_001)
  |> should.equal(p.Stopped)
  json.to_string(p.to_json(s, now + 10_001))
  |> string.contains("\"in_flight\":0")
  |> should.be_true
}

fn registered() {
  let assert Ok(s) =
    p.new_with_registry(
      bindings(),
      p.defaults(),
      [
        p.Registry(p.Claude, binding("claude-private"), [
          "service-a",
          "service-b",
        ]),
      ],
      0,
    )
  s
}

fn service(id: String, b: p.Binding, at: Int) {
  p.ServiceObservation(
    p.Claude,
    id,
    b,
    p.ServiceDimension(True, at),
    p.ServiceDimension(True, at),
    p.ServiceDimension(True, at),
  )
}

fn proof(r: p.Request, at: Int) {
  p.CoverageEvidence(r.agent, r.binding, [
    service("service-a", r.binding, at),
    service("service-b", r.binding, at),
  ])
}

fn coverage_request(s: p.State, now: Int) {
  target(s, p.Claude, p.CoverageProbe, now, 3000)
}

fn covered(s: p.State, r: p.Request, at: Int) {
  let assert Ok(s) =
    p.record_coverage(s, r, observation(r, yes(), at), proof(r, at), at)
  s
}

pub fn exact_registry_positive_is_scoped_and_order_independent_test() {
  let #(s, r, now) = coverage_request(registered(), 0)
  let evidence = proof(r, now)
  let reversed =
    p.CoverageEvidence(..evidence, services: list.reverse(evidence.services))
  let assert Ok(s) =
    p.record_coverage(s, r, observation(r, yes(), now), reversed, now)
  p.coverage_health(s, p.Claude, now) |> should.equal(p.Ready)
  p.coverage_health(s, p.Pi, now) |> should.equal(p.Unknown)
  let text = json.to_string(p.to_json(s, now))
  string.contains(text, "READY_SCOPED_REGISTRY_OBSERVATION") |> should.be_true
  string.contains(text, "OFFICIAL_CATALOG_COMPLETENESS_UNVERIFIED")
  |> should.be_true
  string.contains(text, "service-a") |> should.be_false
  p.coverage_health(s, p.Claude, now + 1_800_001) |> should.equal(p.Unknown)
}

pub fn manifest_duplicate_agent_ids_bindings_and_exact_bounds_test() {
  let r = p.Registry(p.Claude, binding("claude-private"), ["service-a"])
  list.each(
    [
      [p.Registry(..r, required_services: [])],
      [p.Registry(..r, required_services: ["service-a", "service-a"])],
      [p.Registry(..r, required_services: ["service-秘密"])],
      [p.Registry(..r, binding: binding("not-current"))],
      [r, r],
    ],
    fn(registries) {
      p.new_with_registry(bindings(), p.defaults(), registries, 0)
      |> should.be_error
    },
  )
  let ids =
    list.repeat(Nil, 256)
    |> list.index_map(fn(_, i) { "service-" <> int.to_string(i) })
  let registries =
    list.map(bindings(), fn(pair) { p.Registry(pair.0, pair.1, ids) })
  p.new_with_registry(bindings(), p.defaults(), registries, 0) |> should.be_ok
  p.new_with_registry(
    bindings(),
    p.defaults(),
    [p.Registry(..r, required_services: ["extra", ..ids])],
    0,
  )
  |> should.be_error
}

pub fn coverage_exact_sets_reject_missing_duplicate_unexpected_and_count_substitute_test() {
  let #(s, r, now) = coverage_request(registered(), 0)
  let a = service("service-a", r.binding, now)
  let b = service("service-b", r.binding, now)
  list.each(
    [
      [],
      [a],
      [a, a],
      [a, service("unexpected", r.binding, now)],
      [a, b, service("extra", r.binding, now)],
      list.repeat(a, 257),
    ],
    fn(services) {
      p.record_coverage(
        s,
        r,
        observation(r, yes(), now),
        p.CoverageEvidence(r.agent, r.binding, services),
        now,
      )
      |> should.be_error
    },
  )
}

pub fn coverage_independent_dimensions_bindings_and_timestamps_fail_closed_test() {
  let #(s, r, now) = coverage_request(registered(), 0)
  let evidence = proof(r, now)
  let assert [a, b] = evidence.services
  let bad = binding("different-session")
  let no = p.ServiceDimension(False, now)
  list.each(
    [
      p.CoverageEvidence(..evidence, binding: bad),
      p.CoverageEvidence(..evidence, services: [
        p.ServiceObservation(..a, binding: bad),
        b,
      ]),
      p.CoverageEvidence(..evidence, services: [
        p.ServiceObservation(..a, function: no),
        b,
      ]),
      p.CoverageEvidence(..evidence, services: [
        p.ServiceObservation(..a, performance: no),
        b,
      ]),
      p.CoverageEvidence(..evidence, services: [
        p.ServiceObservation(..a, operation: no),
        b,
      ]),
      p.CoverageEvidence(..evidence, services: [
        p.ServiceObservation(..a, function: p.ServiceDimension(True, now + 1)),
        b,
      ]),
      p.CoverageEvidence(..evidence, services: [
        p.ServiceObservation(
          ..a,
          performance: p.ServiceDimension(True, now - 1_800_001),
        ),
        b,
      ]),
    ],
    fn(e) {
      p.record_coverage(s, r, observation(r, yes(), now), e, now)
      |> should.be_error
    },
  )
  p.record_coverage(
    s,
    r,
    observation(r, p.Results(Some(True), None, Some(True)), now),
    evidence,
    now,
  )
  |> should.be_error
  p.record_coverage(
    s,
    r,
    observation(r, p.Results(Some(True), Some(True), Some(False)), now),
    evidence,
    now,
  )
  |> should.be_error
}

pub fn coverage_failed_collection_needs_two_new_distinct_service_proofs_test() {
  let #(s, r, now) = coverage_request(registered(), 0)
  let assert Ok(s) = p.record_failure(s, r, p.ProbeFailed, now)
  p.coverage_health(s, p.Claude, now) |> should.equal(p.Stopped)
  let #(s, first, at) = coverage_request(s, now + 1000)
  let s = covered(s, first, at)
  p.coverage_health(s, p.Claude, at) |> should.equal(p.Stopped)
  let #(s, second, later) = coverage_request(s, at + 1000)
  // A new request number carrying the same underlying service observations is
  // not a second independent functional recovery probe.
  let assert Ok(s) =
    p.record_coverage(
      s,
      second,
      observation(second, yes(), later),
      proof(second, at),
      later,
    )
  p.coverage_health(s, p.Claude, later) |> should.equal(p.Stopped)
  let #(s, third, final_at) = coverage_request(s, later + 1000)
  let s = covered(s, third, final_at)
  p.coverage_health(s, p.Claude, final_at) |> should.equal(p.Ready)
}

pub fn coverage_heartbeat_does_not_recover_failure_and_rebind_drops_manifest_test() {
  let #(s, r, now) = coverage_request(registered(), 0)
  let s = covered(s, r, now)
  let assert Ok(unchanged) = p.rebind(s, p.Claude, r.binding, now)
  p.coverage_health(unchanged, p.Claude, now) |> should.equal(p.Ready)
  let assert Ok(changed) = p.rebind(s, p.Claude, binding("changed"), now)
  p.coverage_health(changed, p.Claude, now) |> should.equal(p.Unknown)
  let #(s, r, at) = coverage_request(registered(), 0)
  let assert Ok(s) = p.record_failure(s, r, p.ProbeFailed, at)
  let #(s, hb, later) = target(s, p.Claude, p.HeartbeatProbe, at + 1000, 1000)
  let s = complete(s, hb, yes(), later)
  p.coverage_health(s, p.Claude, later) |> should.equal(p.Stopped)
}

pub fn legacy_coverage_without_explicit_registry_never_promotes_test() {
  let #(s, r, now) = coverage_request(initial(), 0)
  p.record_coverage(s, r, observation(r, yes(), now), proof(r, now), now)
  |> should.be_error
  let s = complete(s, r, yes(), now)
  p.coverage_health(s, p.Claude, now) |> should.equal(p.Unknown)
}

pub fn coverage_proof_errors_are_recorded_explicitly_by_observer_test() {
  let #(s, r, now) = coverage_request(registered(), 0)
  let malformed = p.CoverageEvidence(r.agent, r.binding, [])
  p.record_coverage(s, r, observation(r, yes(), now), malformed, now)
  |> should.be_error
  let assert Ok(s) = p.record_failure(s, r, p.ProbeFailed, now)
  p.coverage_health(s, p.Claude, now) |> should.equal(p.Stopped)
}

pub fn cross_agent_service_proof_replay_refused_even_with_identical_bindings_and_ids_test() {
  let b = binding("shared-binding")
  let shared = list.map(p.agents(), fn(agent) { #(agent, b) })
  let registries =
    list.map([p.Claude, p.Pi], fn(agent) {
      p.Registry(agent, b, ["service-a", "service-b"])
    })
  let assert Ok(s) = p.new_with_registry(shared, p.defaults(), registries, 0)
  let #(s, claude, now) = target(s, p.Claude, p.CoverageProbe, 0, 1000)
  let evidence = proof(claude, now)
  let assert Ok(s) =
    p.record_coverage(s, claude, observation(claude, yes(), now), evidence, now)
  p.coverage_health(s, p.Claude, now) |> should.equal(p.Ready)
  let #(s, pi, later) = target(s, p.Pi, p.CoverageProbe, now + 1000, 1000)
  // Same candidate/config/session and exact same service identifiers do not
  // make one agent's observed service probes observations of another agent.
  p.record_coverage(s, pi, observation(pi, yes(), later), evidence, later)
  |> should.be_error
  let relabeled_header = p.CoverageEvidence(..evidence, agent: p.Pi)
  p.record_coverage(
    s,
    pi,
    observation(pi, yes(), later),
    relabeled_header,
    later,
  )
  |> should.be_error
  p.coverage_health(s, p.Pi, later) |> should.equal(p.Unknown)
  let proper =
    p.CoverageEvidence(
      p.Pi,
      b,
      list.map(evidence.services, fn(service) {
        p.ServiceObservation(..service, agent: p.Pi)
      }),
    )
  p.record_coverage(s, pi, observation(pi, yes(), later), proper, later)
  |> should.be_ok
}
