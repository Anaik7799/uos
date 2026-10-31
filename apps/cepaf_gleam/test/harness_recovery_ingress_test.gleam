import cepaf_gleam/harness/recovery_ingress as ingress
import cepaf_gleam/harness/recovery_model as model
import cepaf_gleam/harness/value
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import harness_recovery_model_test as fixture

pub fn wire(operation: String, payload: json.Json) -> String {
  json.to_string(
    json.object([
      #("schema_version", json.int(1)),
      #("operation", json.string(operation)),
      #("payload", payload),
    ]),
  )
}

pub fn field(reply: String, key: String) -> value.Value {
  let assert Ok(v) = json.parse(reply, value.decoder())
  let assert Ok(v) = value.get(v, key)
  v
}

pub fn prepare_wire() -> String {
  wire("prepare", model.proposal_json(fixture.proposal()))
}

pub fn bound_wire(operation: String) -> String {
  wire(
    operation,
    json.object([
      #("request_id", json.string(fixture.proposal().request_id)),
      #(
        "candidate_digest",
        json.string(model.proposal_digest(fixture.proposal())),
      ),
    ]),
  )
}

pub fn preparation_is_data_only_and_commit_has_no_worker_test() {
  let #(state, prepared) =
    ingress.handle_candidate_json(
      ingress.initial(),
      prepare_wire(),
      fixture.context(),
    )
  field(prepared, "code") |> should.equal(value.Text("CANDIDATE_DATA_PREPARED"))
  field(prepared, "authority") |> should.equal(value.Text("NONE"))
  field(prepared, "new_effect_permission") |> should.equal(value.Boolean(False))
  let #(_, committed) =
    ingress.handle_candidate_json(
      state,
      bound_wire("commit_set"),
      fixture.context(),
    )
  field(committed, "code") |> should.equal(value.Text("WORKER_UNAVAILABLE"))
  field(committed, "new_effect_permission")
  |> should.equal(value.Boolean(False))
}

fn code(state: ingress.State, raw: String, c: model.SuppliedContext) -> String {
  let #(_, reply) = ingress.handle_candidate_json(state, raw, c)
  let assert value.Text(code) = field(reply, "code")
  code
}

fn proposal_value() -> value.Value {
  let assert Ok(v) =
    json.parse(
      json.to_string(model.proposal_json(fixture.proposal())),
      value.decoder(),
    )
  v
}

pub fn supported_surface_is_closed_and_has_no_ordinary_tools_test() {
  ingress.supported_operations()
  |> should.equal(["status", "prepare", "commit_set", "inspect"])
  list.each(
    ["sa_task_claim", "harness_finish", "harness_build", "revoke", "reset"],
    fn(name) {
      code(ingress.initial(), wire(name, json.object([])), fixture.context())
      |> should.equal("UNKNOWN_OPERATION")
    },
  )
}

pub fn status_is_explicitly_not_runtime_or_authority_evidence_test() {
  let #(_, reply) =
    ingress.handle_candidate_json(
      ingress.initial(),
      wire("status", json.object([])),
      fixture.context(),
    )
  field(reply, "code") |> should.equal(value.Text("CANDIDATE_INTERFACE_ONLY"))
  list.each(
    [
      "new_effect_permission",
      "mutation_attempted",
      "runtime_activation",
      "context_authenticated",
      "independent_review_authenticated",
    ],
    fn(key) { field(reply, key) |> should.equal(value.Boolean(False)) },
  )
  field(reply, "worker_status") |> should.equal(value.Text("UNIMPLEMENTED"))
  field(reply, "native_outcome") |> should.equal(value.Text("UNOBSERVED"))
}

pub fn caller_privilege_booleans_never_create_authority_test() {
  list.each(
    [
      "authorized",
      "approved",
      "worker_authenticated",
      "cleanup_confirmed",
      "effect_permission",
    ],
    fn(key) {
      let payload = value.set(proposal_value(), key, value.Boolean(True))
      code(
        ingress.initial(),
        wire("prepare", value.encode(payload)),
        fixture.context(),
      )
      |> should.equal("INVALID_WIRE")
    },
  )
  let raw =
    "{\"schema_version\":1,\"operation\":\"status\",\"payload\":{},\"authorized\":true}"
  code(ingress.initial(), raw, fixture.context())
  |> should.equal("INVALID_WIRE")
}

pub fn supplied_runtime_context_on_wire_is_refused_test() {
  let raw =
    "{\"schema_version\":1,\"operation\":\"status\",\"payload\":{},\"context\":{\"authenticated\":true}}"
  code(ingress.initial(), raw, fixture.context())
  |> should.equal("INVALID_WIRE")
}

pub fn strict_json_duplicate_nul_depth_and_syntax_controls_test() {
  list.each(
    [
      "{\"schema_version\":1,\"schema_version\":1,\"operation\":\"status\",\"payload\":{}}",
      "{\"schema_version\":1,\"operation\":\"status\\u0000\",\"payload\":{}}",
      "{\"schema_version\":1.0,\"operation\":\"status\",\"payload\":{}}",
      "{broken",
      "{\"schema_version\":1,\"operation\":\"status\",\"payload\":{}} trailing",
    ],
    fn(raw) {
      let got = code(ingress.initial(), raw, fixture.context())
      { got == "INVALID_JSON" || got == "INVALID_WIRE" } |> should.be_true()
    },
  )
  let nested = string.repeat("[", 13) <> "0" <> string.repeat("]", 13)
  code(ingress.initial(), nested, fixture.context())
  |> should.equal("INVALID_JSON")
}

pub fn exact_input_byte_cap_accepts_then_refuses_overflow_test() {
  let raw = wire("status", json.object([]))
  let at_cap = raw <> string.repeat(" ", 32_768 - string.byte_size(raw))
  code(ingress.initial(), at_cap, fixture.context())
  |> should.equal("CANDIDATE_INTERFACE_ONLY")
  code(ingress.initial(), at_cap <> " ", fixture.context())
  |> should.equal("INPUT_BOUND")
}

pub fn integer_and_nanosecond_wire_forms_are_strict_test() {
  let p = proposal_value()
  let assert Ok(value.Array([first, second, third])) = value.get(p, "members")
  list.each(
    [
      value.set(first, "old_attempt", value.Number(2.0)),
      value.set(first, "old_lease_ns", value.Integer(90_000_000)),
      value.set(first, "old_lease_ns", value.Text("090000000")),
      value.set(first, "old_lease_ns", value.Text("-1")),
      value.set(first, "old_lease_ns", value.Text("9000000000000000001")),
    ],
    fn(member) {
      let changed =
        value.set(p, "members", value.Array([member, second, third]))
      code(
        ingress.initial(),
        wire("prepare", value.encode(changed)),
        fixture.context(),
      )
      |> should.equal("INVALID_WIRE")
    },
  )
}

pub fn incomplete_three_task_set_cannot_prepare_test() {
  let p = proposal_value()
  let assert Ok(value.Array(ms)) = value.get(p, "members")
  let changed = value.set(p, "members", value.Array(list.take(ms, 2)))
  code(
    ingress.initial(),
    wire("prepare", value.encode(changed)),
    fixture.context(),
  )
  |> should.equal("INVALID_WIRE")
}

pub fn no_candidate_or_wrong_binding_cannot_commit_or_inspect_test() {
  code(ingress.initial(), bound_wire("commit_set"), fixture.context())
  |> should.equal("NOT_PREPARED")
  let #(state, _) =
    ingress.handle_candidate_json(
      ingress.initial(),
      prepare_wire(),
      fixture.context(),
    )
  list.each(["commit_set", "inspect"], fn(operation) {
    let wrong =
      wire(
        operation,
        json.object([
          #("request_id", json.string("different-request")),
          #(
            "candidate_digest",
            json.string(model.proposal_digest(fixture.proposal())),
          ),
        ]),
      )
    code(state, wrong, fixture.context())
    |> should.equal("CANDIDATE_BINDING_MISMATCH")
  })
}

pub fn replay_is_historical_and_conflict_does_not_replace_candidate_test() {
  let #(state, prepared) =
    ingress.handle_candidate_json(
      ingress.initial(),
      prepare_wire(),
      fixture.context(),
    )
  code(state, prepare_wire(), fixture.context())
  |> should.equal("HISTORICAL_CANDIDATE_DATA")
  let p = fixture.proposal()
  let changed = model.Proposal(..p, issuer_session: "other-session")
  let #(after, refused) =
    ingress.handle_candidate_json(
      state,
      wire("prepare", model.proposal_json(changed)),
      fixture.context(),
    )
  field(refused, "code") |> should.equal(value.Text("CONFLICTING_REPLAY"))
  let #(_, status) =
    ingress.handle_candidate_json(
      after,
      wire("status", json.object([])),
      fixture.context(),
    )
  field(status, "candidate_digest")
  |> should.equal(field(prepared, "candidate_digest"))
}

pub fn expired_or_regressed_context_refuses_before_unavailable_worker_test() {
  let c = fixture.context()
  let #(state, _) =
    ingress.handle_candidate_json(ingress.initial(), prepare_wire(), c)
  code(
    state,
    bound_wire("commit_set"),
    model.SuppliedContext(..c, mono_ms: 800),
  )
  |> should.equal("EXPIRED")
  code(state, bound_wire("commit_set"), model.SuppliedContext(..c, utc_ms: 99))
  |> should.equal("CLOCK_REGRESSION")
  code(state, bound_wire("commit_set"), c) |> should.equal("WORKER_UNAVAILABLE")
}

pub fn inspect_only_describes_local_candidate_never_native_outcome_test() {
  let #(state, _) =
    ingress.handle_candidate_json(
      ingress.initial(),
      prepare_wire(),
      fixture.context(),
    )
  let #(_, reply) =
    ingress.handle_candidate_json(
      state,
      bound_wire("inspect"),
      fixture.context(),
    )
  field(reply, "code") |> should.equal(value.Text("LOCAL_CANDIDATE_ONLY"))
  field(reply, "native_outcome") |> should.equal(value.Text("UNOBSERVED"))
  field(reply, "new_effect_permission") |> should.equal(value.Boolean(False))
}

pub fn every_prepared_operation_retains_clock_high_water_test() {
  let c = fixture.context()
  list.each(["inspect", "prepare", "status", "commit_set"], fn(operation) {
    let #(state, _) =
      ingress.handle_candidate_json(ingress.initial(), prepare_wire(), c)
    let request = case operation {
      "prepare" -> prepare_wire()
      "status" -> wire("status", json.object([]))
      _ -> bound_wire(operation)
    }
    let #(advanced, seen) =
      ingress.handle_candidate_json(
        state,
        request,
        model.SuppliedContext(..c, utc_ms: 110, mono_ms: -90),
      )
    let expected = case operation {
      "prepare" -> "HISTORICAL_CANDIDATE_DATA"
      "status" -> "CANDIDATE_INTERFACE_ONLY"
      "commit_set" -> "WORKER_UNAVAILABLE"
      _ -> "LOCAL_CANDIDATE_ONLY"
    }
    field(seen, "code") |> should.equal(value.Text(expected))
    code(
      advanced,
      bound_wire("inspect"),
      model.SuppliedContext(..c, utc_ms: 105, mono_ms: -80),
    )
    |> should.equal("CLOCK_REGRESSION")
    code(
      advanced,
      bound_wire("inspect"),
      model.SuppliedContext(..c, utc_ms: 120, mono_ms: -95),
    )
    |> should.equal("CLOCK_REGRESSION")
  })
}

pub fn clock_advance_and_replay_never_extend_original_deadline_test() {
  let c = fixture.context()
  let #(state, before) =
    ingress.handle_candidate_json(ingress.initial(), prepare_wire(), c)
  let #(advanced, after) =
    ingress.handle_candidate_json(
      state,
      prepare_wire(),
      model.SuppliedContext(..c, utc_ms: 110, mono_ms: -90),
    )
  field(after, "candidate_digest")
  |> should.equal(field(before, "candidate_digest"))
  code(
    advanced,
    bound_wire("inspect"),
    model.SuppliedContext(..c, utc_ms: 1000, mono_ms: 799),
  )
  |> should.equal("EXPIRED")
  code(
    advanced,
    bound_wire("inspect"),
    model.SuppliedContext(..c, utc_ms: 999, mono_ms: 800),
  )
  |> should.equal("EXPIRED")
}
