import cepaf_gleam/harness/jj_integration as j
import gleam/string
import gleeunit/should

fn binding() { j.BindingData("uos/private", "INTEGRATE", "fixture-worker", 1, "fixture-owner", 1) }
fn candidate() { j.CandidateData(string.repeat("a", 40), string.repeat("b", 40), string.repeat("c", 128), string.repeat("d", 64), string.repeat("e", 64), string.repeat("f", 64)) }
pub fn public_integration_is_unavailable_test() {
  let assert Ok(intent) = j.prepare("integration-1", binding(), candidate())
  j.integrate(intent) |> should.equal(Error("PRODUCTION_INTEGRATION_AUTHORITY_UNAVAILABLE"))
}
pub fn exact_request_binding_and_no_argv_surface_test() {
  let assert Ok(a) = j.prepare("integration-1", binding(), candidate())
  let assert Ok(b) = j.prepare("integration-2", binding(), candidate())
  { j.intent_sha256(a) == j.intent_sha256(b) } |> should.be_false()
  j.prepare("bad;command", binding(), candidate()) |> should.be_error()
  j.prepare("x", j.BindingData("uos/private", "INTEGRATE", "fixture-worker", 0, "fixture-owner", 1), candidate()) |> should.be_error()
}
