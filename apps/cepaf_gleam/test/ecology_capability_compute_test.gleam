//// Scoped runtime regressions for bounded ecology computations.
//// No production lease, external model request or admission occurs here.

import cepaf_gleam/ecology/capability_compute as compute
import cepaf_gleam/ecology/capability_port as port
import cepaf_gleam/ecology/capability_twin as twin
import cepaf_gleam/ecology/multiway
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should

fn string_field(c: compute.Computation, key: String) -> String {
  let decoder = {
    use x <- decode.field(key, decode.string)
    decode.success(x)
  }
  let assert Ok(value) = json.parse(json.to_string(c.detail), decoder)
  value
}

fn bool_field(c: compute.Computation, key: String) -> Bool {
  let decoder = {
    use x <- decode.field(key, decode.bool)
    decode.success(x)
  }
  let assert Ok(value) = json.parse(json.to_string(c.detail), decoder)
  value
}

pub fn bounded_local_diagnostic_inputs_compute_test() {
  list.each(
    [
      "fprime",
      "bayesian",
      "rete_ul",
      "stm",
      "formal_twin",
      "ruliad",
      "denotational",
      "algebraic_atlas",
    ],
    fn(c) { compute.run(c, port.default_input(c)) |> should.be_ok },
  )
}

pub fn bayesian_observation_history_and_whitespace_test() {
  let assert Ok(value) = compute.run("bayesian", "ok\npass\tfail ok")
  value.evidence |> should.equal("posterior mean 0.6666666666666666")
  compute.run("bayesian", "") |> should.be_error
  compute.run("bayesian", "no evidence") |> should.be_error
}

pub fn fpp_interprets_watchdog_and_guarded_recovery_test() {
  let assert Ok(dead) =
    compute.run(
      "fprime",
      "{\"machine\":\"watchdog\",\"signals\":[\"warning_timeout\",\"stale_timeout\",\"dead_timeout\",\"heartbeat_tick\"]}",
    )
  string_field(dead, "final") |> should.equal("Dead")
  let assert Ok(fresh) =
    compute.run(
      "fprime",
      "{\"machine\":\"watchdog\",\"signals\":[\"warning_timeout\",\"stale_timeout\",\"dead_timeout\",\"heartbeat_tick\"],\"guards\":[{\"name\":\"handshake_revalidated\",\"holds\":true}]}",
    )
  string_field(fresh, "final") |> should.equal("Fresh")
}

pub fn fpp_rejects_unknown_signals_and_duplicate_guards_test() {
  compute.run("fprime", "{\"machine\":\"watchdog\",\"signals\":[\"invented\"]}")
  |> should.be_error
  compute.run(
    "fprime",
    "{\"machine\":\"watchdog\",\"signals\":[\"heartbeat_tick\"],\"guards\":[{\"name\":\"handshake_revalidated\",\"holds\":true},{\"name\":\"handshake_revalidated\",\"holds\":false}]}",
  )
  |> should.be_error
}

pub fn rule_decisions_depend_on_actual_facts_test() {
  let assert Ok(stop) =
    compute.run(
      "rete_ul",
      "{\"domain\":\"ooda\",\"facts\":[{\"key\":\"mesh_running\",\"value\":\"true\"},{\"key\":\"missing_critical\",\"value\":\"true\"}]}",
    )
  string_field(stop, "decision") |> should.equal("EmergencyStop")
  bool_field(stop, "effect_authority") |> should.be_false
  let assert Ok(none) = compute.run("rete_ul", port.default_input("rete_ul"))
  string_field(none, "decision") |> should.equal("NoAction")
}

pub fn duplicate_rule_facts_fail_closed_test() {
  compute.run(
    "rete_ul",
    "{\"domain\":\"ooda\",\"facts\":[{\"key\":\"mesh_running\",\"value\":\"true\"},{\"key\":\"mesh_running\",\"value\":\"false\"}]}",
  )
  |> should.be_error
}

pub fn transaction_advances_once_and_rejects_replay_test() {
  let s = twin.Snapshot(3, "old", 2, 4, 10, 9)
  let tx = twin.Transaction(2, 4, 3, 9, "new")
  let assert Ok(next) = twin.commit(s, tx)
  next |> should.equal(twin.Snapshot(4, "new", 0, 4, 10, 9))
  twin.commit(next, tx) |> should.equal(Error(twin.WrongOwner))
}

pub fn transaction_fences_expiry_and_stale_snapshot_test() {
  let s = twin.Snapshot(3, "old", 2, 4, 10, 9)
  twin.commit(s, twin.Transaction(2, 3, 3, 9, "bad"))
  |> should.equal(Error(twin.StaleFence))
  twin.commit(s, twin.Transaction(2, 4, 3, 10, "bad"))
  |> should.equal(Error(twin.Expired))
  twin.commit(s, twin.Transaction(2, 4, 2, 9, "bad"))
  |> should.equal(Error(twin.SnapshotConflict))
  twin.commit(s, twin.Transaction(1, 4, 3, 9, "bad"))
  |> should.equal(Error(twin.WrongOwner))
}

pub fn transaction_reference_agrees_across_320_requests_test() {
  let s = twin.Snapshot(2, "old", 2, 2, 3, 5)
  list.each([0, 1, 2, 3], fn(actor) {
    list.each([0, 1, 2, 3], fn(token) {
      list.each([0, 1, 2, 3], fn(snapshot) {
        list.each([0, 1, 2, 3, 4], fn(now) {
          let tx = twin.Transaction(actor, token, snapshot, now, "new")
          result.unwrap(twin.commit(s, tx), s)
          |> should.equal(twin.reference(s, tx))
        })
      })
    })
  })
}

pub fn telemetry_observation_does_not_change_transaction_state_test() {
  let s = twin.Snapshot(7, "preserve", 2, 8, 10, 5)
  twin.observe(s) |> should.equal(twin.Snapshot(7, "preserve", 2, 8, 10, 6))
}

pub fn formal_twin_is_request_specific_and_expiry_sensitive_test() {
  let assert Ok(valid) =
    compute.run("formal_twin", port.default_input("formal_twin"))
  bool_field(valid, "reference_agrees") |> should.be_true
  bool_field(valid, "committed") |> should.be_true
  let expired_request =
    port.default_input("formal_twin")
    |> string.replace("\"now\":0", "\"now\":10")
  let assert Ok(expired) = compute.run("formal_twin", expired_request)
  string_field(expired, "decision") |> should.equal("expired")
  bool_field(expired, "committed") |> should.be_false
}

pub fn multiway_replaces_one_occurrence_per_edge_test() {
  let assert Ok(g) = multiway.explore("aa", [multiway.Rule("a", "b")], 1)
  list.sort(g.frontier, string.compare) |> should.equal(["ab", "ba"])
  list.length(g.edges) |> should.equal(2)
  list.all(g.edges, fn(e) { e.source == "aa" }) |> should.be_true
}

pub fn multiway_deduplicates_convergent_states_test() {
  let assert Ok(g) = multiway.explore("aa", [multiway.Rule("a", "b")], 2)
  g.frontier |> should.equal(["bb"])
  list.length(g.states) |> should.equal(4)
  list.length(g.edges) |> should.equal(4)
}

pub fn multiway_rewrites_only_complete_graphemes_test() {
  let assert Ok(g) = multiway.explore("á", [multiway.Rule("a", "b")], 1)
  g.states |> should.equal(["á"])
  g.edges |> should.equal([])
  let assert Ok(matched) = multiway.explore("á", [multiway.Rule("á", "b")], 1)
  matched.frontier |> should.equal(["b"])
}

pub fn multiway_invalid_and_exhausted_budgets_are_errors_test() {
  multiway.explore("a", [multiway.Rule("", "a")], 1) |> should.be_error
  multiway.explore("a", [multiway.Rule("a", "aa")], 5) |> should.be_error
  multiway.explore(string.repeat("a", 100), [multiway.Rule("a", "b")], 1)
  |> should.be_error
}

pub fn denotation_preserves_storage_interlock_and_provenance_test() {
  let forbidden =
    port.default_input("denotational")
    |> string.replace("model-only", "25503L801736")
  let assert Ok(os_veto) = compute.run("denotational", forbidden)
  string_field(os_veto, "reason")
  |> should.equal("ROOT_OS_DRIVE_MUTATION_HARD_DENIED")
  let assert Ok(ev_veto) =
    compute.run(
      "denotational",
      "{\"authority\":\"sa-plan\",\"target_drive_serial\":\"model\",\"ev_cycle\":94}",
    )
  string_field(ev_veto, "reason")
  |> should.equal("UNADMITTED_EV_CYCLE_ABOVE_CEILING_93")
}

pub fn denotation_rejects_trace_drift_and_unauthorized_intent_test() {
  let assert Ok(drift) =
    compute.run(
      "denotational",
      "{\"authority\":\"sa-plan\",\"target_drive_serial\":\"model\",\"delta_coord\":1.0}",
    )
  string_field(drift, "reason") |> should.equal("TRACE_COORDINATE_DRIFT")
  let assert Ok(unauthorized) =
    compute.run(
      "denotational",
      "{\"authority\":\"model-says-so\",\"target_drive_serial\":\"model\"}",
    )
  bool_field(unauthorized, "is_bottom") |> should.be_true
}

pub fn atlas_reports_actual_overlap_disagreement_test() {
  let request =
    "{\"sections\":[{\"chart\":0,\"value\":\"a\"},{\"chart\":1,\"value\":\"b\"}],\"overlaps\":[{\"source\":0,\"target\":1,\"value\":\"a\"}],\"path\":[0,1,2]}"
  let assert Ok(computed) = compute.run("algebraic_atlas", request)
  bool_field(computed, "compatible") |> should.be_false
  bool_field(computed, "composition_compatible") |> should.be_true
}

pub fn atlas_rejects_duplicate_sections_and_unknown_charts_test() {
  let duplicate =
    "{\"sections\":[{\"chart\":0,\"value\":\"a\"},{\"chart\":0,\"value\":\"a\"}],\"overlaps\":[],\"path\":[0,1]}"
  compute.run("algebraic_atlas", duplicate) |> should.be_error
  let bad_chart =
    port.default_input("algebraic_atlas") |> string.replace("[0,1,2]", "[0,10]")
  compute.run("algebraic_atlas", bad_chart) |> should.be_error
}

pub fn invalid_schemas_and_byte_limits_never_compute_test() {
  list.each(
    [
      "fprime",
      "rete_ul",
      "stm",
      "formal_twin",
      "denotational",
      "algebraic_atlas",
    ],
    fn(c) {
      compute.run(c, "ok") |> should.be_error
      compute.run(c, "{}") |> should.be_error
    },
  )
  compute.run("bayesian", string.repeat("å", 8193)) |> should.be_error
}
