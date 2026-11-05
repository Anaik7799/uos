
// COMPILE-TIME PRIVATE TEST EXTENSION. Never part of production source.
// LocalConfiguration is fixture DATA, not a trusted owner/provider constructor.
// No callback, key material, arbitrary message or automatic retry is accepted.
@external(erlang,"telegram_store_transport_ffi","request_config_with_cleanup")
fn fixture_native(config: FixtureLocalConfiguration,body: String) -> #(Result(String,String),FixtureWitness)
type FixtureWitness { None Some(#(Int,Int)) }
pub type FixtureLocalConfiguration {
 LocalConfiguration(guardian: String,guardian_sha256: String,worker: String,worker_sha256: String,database: String)
}
pub fn fixture_sign(request: Prepared, config: FixtureLocalConfiguration) -> Result(SignedUnderData,Error) {
 let #(reply,cleanup)=fixture_native(config,request.body)
 use _ <- result.try(case cleanup {
  Some(#(0,utc)) if utc>0 ->Ok(Nil)
  Some(_)->Error(CleanupUnknown)
  None->Error(CleanupUnknown)
 })
 use raw <- result.try(reply |> result.map_error(fn(_){Unavailable}))
 verify_response(request,raw)
}

// PRIVATE_TESTS_BEGIN
// This second section is appended ONLY to the private test-module copy.
fn provider() {
 let get=fn(k){let assert Ok(v)=envoy.get("UOS_SIGNER_FIXTURE_"<>k) v}
 s.LocalConfiguration(get("GUARDIAN"),get("GUARDIAN_SHA"),get("WORKER"),get("WORKER_SHA"),get("MARKER"))
}
pub fn actual_guarded_two_role_signing_and_verification_test() {
 let #(c,context)=fixture()
 let assert Ok(review_request)=s.prepare(c,context,e.IndependentReview,"",key("REVIEWER"))
 let assert Ok(review)=s.fixture_sign(review_request,provider())
 s.authority(review) |> should.equal("NONE")
 let assert Ok(issuer_request)=s.prepare(c,context,e.TaskRecoveryIssuer,s.token(review),key("ISSUER"))
 let assert Ok(issuer)=s.fixture_sign(issuer_request,provider())
 let now=e.Observation("nas-1.tail55d152.ts.net","boot-fixture","beam-vm-fixture",1030000,-70000)
 let assert Ok(evidence)=e.verify(c,context,now,s.token(review),s.token(issuer))
 e.authority(evidence) |> should.equal("NONE")
 e.verified_request_sha256(evidence) |> should.equal(e.request_sha256(context))
 e.still_valid(evidence,c,context,now) |> should.be_true()
 s.sign(issuer_request) |> should.equal(Error(s.Unavailable))
}
