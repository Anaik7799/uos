import cepaf_gleam/harness/telegram_host_observation as host
import cepaf_gleam/harness/clock as clock
import cepaf_gleam/harness/observer_policy as obs
import uos_swarm/clock_contract as contract
import uos_swarm/clock_guard
import gleam/bit_array
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

fn receipt(raw: String) -> obs.Observation {
  obs.Observation("child_exited", "confirmed", 0, bit_array.from_string(raw))
}
pub fn valid_version_test() {
  host.version_payload(Ok(receipt("zigvm 0.1.0\n"))) |> should.equal(Ok("0.1.0"))
  host.version_payload(Ok(receipt(" zigvm 123456.0.999999 \n"))) |> should.equal(Ok("123456.0.999999"))
}
pub fn version_grammar_refuses_ambiguity_test() {
  list.each(["zigvm 1.2","zigvm 1.2.3.4","zigvm +1.2.3","zigvm 1.-2.3",
    "zigvm 1..3","zigvm 1000000.2.3","zigvm １.2.3","zigvm 1.2.3-rc",
    "zigvm  1.2.3","zigvm\t1.2.3","other 1.2.3","zigvm 1.2.3\nSECRET",
    "zigvm 1.2.3\u{0}", string.repeat("x",257)], fn(raw) {
    host.version_payload(Ok(receipt(raw))) |> should.equal(Error("kernel_version_unavailable"))
  })
}
pub fn receipt_requires_exit_cleanup_and_utf8_test() {
  let good = receipt("zigvm 0.1.0")
  list.each([
    obs.Observation(..good, guardian_result:"deadline"),
    obs.Observation(..good, cleanup:"unconfirmed"),
    obs.Observation(..good, child_exit:1),
    obs.Observation(..good, payload:<<255>>),
  ], fn(value) { host.version_payload(Ok(value)) |> should.equal(Error("kernel_version_unavailable")) })
  host.version_payload(Error("CANARY_SECRET")) |> should.equal(Error("kernel_version_unavailable"))
}
pub fn clock_projection_is_scoped_and_redacted_test() {
  let domain = contract.Domain("PRIVATE_HOST","PRIVATE_BOOT")
  let before = contract.Reading(domain,10_000_000,1_000_000)
  let now = contract.Reading(domain,10_000_050,1_000_050)
  let value = clock.Observation(clock_guard.Sample(
    contract.Evidence(before,"PRIVATE_SOURCE",True,-12,100,0),now),70,9_000_000)
  let raw = host.clock_result(Ok(value)) |> json.to_string
  list.each(["\"status\":\"observed\"","\"reference_age_us\":1000050",
    "\"receipt_age_us\":50","\"offset_us\":-12","\"delivery_us\":70",
    "development_reference_1h_observation_only","NOT_GRANTED"],fn(part) {
    string.contains(raw,part) |> should.be_true
  })
  string.contains(raw,"PRIVATE") |> should.be_false
}
pub fn clock_failure_redacted_test() {
  let raw = host.clock_result(Error("CANARY_SECRET")) |> json.to_string
  string.contains(raw,"unavailable") |> should.be_true
  string.contains(raw,"NOT_GRANTED") |> should.be_true
  string.contains(raw,"CANARY") |> should.be_false
}
