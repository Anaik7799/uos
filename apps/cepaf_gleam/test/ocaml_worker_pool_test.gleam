import cepaf_gleam/services/ocaml_worker_pool.{
  EvaluateGospel, OcamlSuccess, OcamlTimeout, OcamlTrapNulByte,
  OcamlTrapSqlInjection, SolveZ3Bounded, dispatch_request, init_pool,
  pool_state_to_json, render_ansi, validate_payload,
}
import gleam/json
import gleeunit/should

pub fn init_pool_test() {
  let pool = init_pool("hermes-primary", 4)
  pool.pool_id |> should.equal("hermes-primary")
  pool.zero_trust_traps_total |> should.equal(0)
  pool.successful_dispatches_total |> should.equal(0)
}

pub fn zero_trust_nul_byte_test() {
  let res = validate_payload("hello\u{0000}world")
  case res {
    Error(OcamlTrapNulByte(code, msg)) -> {
      code |> should.equal(-2)
      should.be_true(msg != "")
    }
    _ -> should.fail()
  }
}

pub fn zero_trust_sql_injection_test() {
  let res = validate_payload("SELECT * FROM users WHERE 1=1 OR '1'='1'")
  case res {
    Error(OcamlTrapSqlInjection(code, _)) -> code |> should.equal(-3)
    _ -> should.fail()
  }
}

pub fn dispatch_gospel_success_test() {
  let pool = init_pool("hermes-primary", 2)
  let #(updated, resp) =
    dispatch_request(
      pool,
      EvaluateGospel("sa_plan_control_plane", "ensures result >= 0"),
    )
  updated.successful_dispatches_total |> should.equal(1)
  case resp {
    OcamlSuccess(_, verdict, _, _) ->
      should.be_true(verdict == "gospel_admitted:sa_plan_control_plane")
    _ -> should.fail()
  }
}

pub fn dispatch_z3_bounded_test() {
  let pool = init_pool("hermes-primary", 2)
  let #(updated, resp) =
    dispatch_request(
      pool,
      SolveZ3Bounded("(assert (> x 0))", 1000),
    )
  updated.successful_dispatches_total |> should.equal(1)
  case resp {
    OcamlSuccess(_, verdict, _, _) -> verdict |> should.equal("z3_sat_provable")
    _ -> should.fail()
  }
}

pub fn dispatch_z3_timeout_test() {
  let pool = init_pool("hermes-primary", 2)
  let #(updated, resp) =
    dispatch_request(
      pool,
      SolveZ3Bounded("(assert (> x 0))", 0),
    )
  updated.successful_dispatches_total |> should.equal(0)
  case resp {
    OcamlTimeout(t) -> t |> should.equal(0)
    _ -> should.fail()
  }
}

pub fn serialization_and_ansi_test() {
  let pool = init_pool("hermes-primary", 2)
  let json_val = pool_state_to_json(pool)
  should.be_true(json_val != json.null())
  let ansi = render_ansi(pool)
  should.be_true(ansi != "")
}
