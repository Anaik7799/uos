//// Public, nonsecret fixture keys. No production provider or role is asserted.
import cepaf_gleam/harness/recovery_envelope as e
import cepaf_gleam/harness/recovery_signer as s
import cepaf_gleam/harness/recovery_wire as wire
import envoy
import gleam/json
import gleam/string
import gleeunit/should

fn key(role) {
 // Fixed public test vectors also let the ordinary public tests run without
 // provisioning/configuration. These are not claimed real managed identities.
 case envoy.get("UOS_SIGNER_FIXTURE_"<>role<>"_PUBLIC") {
  Ok(key)->key
  Error(_)->case role {
   "REVIEWER"->"IBLLkMpg6OXY2vZuInLSIz4EhtVX6MZhQe2JIBd9frc"
   _->"dyyKRCt9sG4WbPvBzLy83m8-unak6Y7z_8UZUCI31u8"
  }
 }
}
fn d(c) { string.repeat(c,64) }
fn signer(role,key) { e.Signer(role<>"-subject",role<>"-session",role<>"-actor",role<>"-key",key) }
fn fixture() {
 let assert Ok(c)=e.configuration_data(signer("reviewer",key("REVIEWER")),signer("issuer",key("ISSUER")),900_000,1_200_000,d("a"))
 let members=[#("OI02B_ALL_AGENT_SYMBIOSIS_PREFLIGHT","codex-symbiosis-preflight-20261031"),#("OI02E_RELEASE_AUTHORITY_PREPARATION","codex-release-authority-20261031"),#("OI02_ATOMIC_11_TARGET_CAPSULE_CUTOVER","codex-hive-cutover-20261031")]
 let raw=json.to_string(json.object([#("request_id",json.string("signer-fixture")),#("plan",json.string(e.fixed_plan)),#("snapshot_sha256",json.string("sha256:"<>d("0"))),#("members",json.array(members,fn(m){json.object([#("task_id",json.string(m.0)),#("worker",json.string(m.1)),#("old_attempt",json.int(1)),#("old_lease_ns",json.string("900000000000")),#("lease_ms",json.int(60000))])})),#("deadline_utc_ms",json.int(1060000))]))
 let assert Ok(r)=wire.decode(raw)
 let bindings=e.Bindings(d("1"),d("2"),d("3"),d("4"),"reviewer-actor",["codex-hive-cutover-20261031","codex-release-authority-20261031","codex-symbiosis-preflight-20261031"],d("5"),d("6"),d("7"),d("8"))
 let assert Ok(context)=e.context_data(c,r,bindings,e.Window(1000000,1060000,-100000,-40000,1100000,1070000),e.Runtime("nas-1.tail55d152.ts.net","boot-fixture","beam-vm-fixture","sa-plan-recovery","fixture-holder",109))
 #(c,context)
}
pub fn prepares_exact_reviewer_request_test() {
 let #(c,context)=fixture()
 let assert Ok(request)=s.prepare(c,context,e.IndependentReview,"",key("REVIEWER"))
 string.contains(s.request_bytes(request),e.review_purpose) |> should.be_true()
 s.sign(request) |> should.equal(Error(s.Unavailable))
}
pub fn repeated_preparation_has_stable_identity_test() {
 let #(c,context)=fixture()
 let assert Ok(first)=s.prepare(c,context,e.IndependentReview,"",key("REVIEWER"))
 let assert Ok(second)=s.prepare(c,context,e.IndependentReview,"",key("REVIEWER"))
 s.request_bytes(first) |> should.equal(s.request_bytes(second))
}
