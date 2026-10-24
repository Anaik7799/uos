import gleam/option.{None}
import cepaf_gleam/harness/telegram_operational_status as status
import gleam/dynamic/decode
import gleam/json
import gleam/result
import gleam/string
import gleeunit/should

fn local() -> status.LocalState {
  status.LocalState(1_700_000_000_000_000, 2, 7, 8002, False, False,
    json.string("not_probed"), json.string("not_probed"))
}
fn io(reply: Result(Int, String)) -> status.Io {
  status.Io(fn(_, t) { t |> should.equal(1200) reply }, fn() { -1000 })
}
fn authority() -> Result(Int, String) { Ok(10_000) }

pub fn reports_actual_codes_without_health_claim_test() {
  let assert Ok(raw) = status.observe(local(), io(Ok(200)), authority, 6000)
  json.parse(raw, decode.field("global_healthy", decode.optional(decode.bool), fn(value) { decode.success(value) }))
    |> should.equal(Ok(None))
  string.contains(raw, "\"observation\":\"responding\"") |> should.be_true
  string.contains(raw, "\"runtime_admission\":\"NOT_GRANTED\"") |> should.be_true
  string.contains(raw, "\"next_update_offset\":8002") |> should.be_true
  string.contains(raw, "\"model_connectivity\":\"not_probed\"") |> should.be_true
  string.contains(raw, "\"clock_synchronization\":\"not_probed\"") |> should.be_true
}

pub fn redirects_and_error_status_are_not_health_test() {
  let assert Ok(redirect) = status.observe(local(), io(Ok(302)), authority, 6000)
  string.contains(redirect, "redirect_not_followed") |> should.be_true
  let assert Ok(denied) = status.observe(local(), io(Ok(403)), authority, 6000)
  string.contains(denied, "authentication_required") |> should.be_true
  let assert Ok(failed) = status.observe(local(), io(Ok(503)), authority, 6000)
  string.contains(failed, "\"observation\":\"http_error\"") |> should.be_true
}
pub fn transport_errors_redacted_test() {
  let assert Ok(raw) = status.observe(local(), io(Error("CANARY_PRIVATE")), authority, 6000)
  string.contains(raw,"CANARY") |> should.be_false
  string.contains(raw,"unreachable_or_refused") |> should.be_true
  string.contains(raw,"\"http_status\":null") |> should.be_true
}
pub fn malformed_codes_do_not_become_success_test() {
  let assert Ok(raw) = status.observe(local(), io(Ok(999)), authority, 6000)
  string.contains(raw,"invalid_response") |> should.be_true
  string.contains(raw,"999") |> should.be_false
}
pub fn invalid_budget_or_authority_prevents_probe_test() {
  let never = status.Io(fn(_,_) { panic as "probe should not execute" }, fn(){0})
  status.observe(local(), never, authority, 6001) |> result.is_error |> should.be_true
  status.observe(local(), never, fn(){ Error("private") }, 6000)
    |> should.equal(Error("status_authority_refused"))
  status.observe(local(), never, fn(){ Ok(99) }, 6000) |> result.is_error |> should.be_true
}
pub fn lease_clamps_probe_timeout_test() {
  let bounded = status.Io(fn(_,t){ t |> should.equal(200) Ok(200) },fn(){0})
  status.observe(local(), bounded, fn(){Ok(200)}, 6000)
    |> result.is_ok |> should.be_true
}

@external(erlang, "telegram_status_test_io", "reset")
fn reset(times: List(Int), leases: List(Result(Int, String))) -> Nil
@external(erlang, "telegram_status_test_io", "now")
fn now() -> Int
@external(erlang, "telegram_status_test_io", "authorize")
fn authorize() -> Result(Int, String)
@external(erlang, "telegram_status_test_io", "probe")
fn probe(name: String, timeout_ms: Int) -> Result(Int, String)
@external(erlang, "telegram_status_test_io", "calls")
fn calls() -> Int

pub fn authority_loss_stops_further_probes_test() {
  reset([0], [Ok(10000), Error("revoked")])
  status.observe(local(), status.Io(probe, now), authorize, 6000)
    |> should.equal(Error("status_authority_refused"))
  calls() |> should.equal(1)
}
pub fn elapsed_budget_stops_further_probes_test() {
  reset([0, 0, 0, 6000], [Ok(10000)])
  status.observe(local(), status.Io(probe, now), authorize, 6000)
    |> result.is_error |> should.be_true
  calls() |> should.equal(1)
}
pub fn clock_regression_stops_further_probes_test() {
  reset([1000, 999], [Ok(10000)])
  status.observe(local(), status.Io(probe, now), authorize, 6000)
    |> result.is_error |> should.be_true
  calls() |> should.equal(0)
}
