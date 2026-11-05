//// Exact-purpose recovery signing PREPARATION, not a trusted provider.
//// Public ConfigurationData/keys/clocks remain DATA. This adapter creates no
//// authenticated principal, managed key, signer custody, review truth, grant,
//// task effect or provisioning. No callback/raw-message signer is exported.
//// The separate accepted recovery_envelope/wire dependencies must be integrated
//// and independently admitted before any future production owner can use them.
//// Production signing is unavailable. Only a compile-time private fixture
//// extension can invoke a fixed public-test-vector provider behind a guardian.
import cepaf_gleam/harness/files
import cepaf_gleam/harness/recovery_envelope as e
import cepaf_gleam/harness/value as v
import cepaf_gleam/mcp/json_guard
import gleam/bit_array
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub opaque type Prepared {
 Prepared(body: String, request_id: String, key_reference: String,
   header: String, payload: String, jwks: String)
}
pub opaque type SignedUnderData { SignedUnderData(token: String, request_id: String) }
pub type Error { Unavailable InvalidData CleanupUnknown }
@external(erlang,"oidc_jwt_ffi","validate_jwks_snapshot")
fn valid_keys(raw: String) -> Result(Nil,String)
@external(erlang,"oidc_jwt_ffi","verify_ed25519_jwt")
fn verify_jwt(token: String,jwks: String) -> Result(String,String)
fn need(ok: Bool) -> Result(Nil,Error) { case ok { True->Ok(Nil) False->Error(InvalidData) } }
fn text(value: v.Value,k: String) -> Result(String,Error) {
 case v.get(value,k) { Ok(v.Text(s))->Ok(s) _->Error(InvalidData) }
}
fn closed(value: v.Value, keys: List(String)) -> Bool {
 case value { v.Object(fields)->list.length(fields)==list.length(keys)
  && list.all(fields,fn(p){list.contains(keys,p.0)}) _->False }
}
/// A logical role reference is not an observed/provisioned managed key ID.
pub fn prepare(c: e.ConfigurationData, context: e.Context, purpose: e.Purpose,
  review: String, public_key: String) -> Result(Prepared, Error) {
 use payload <- result.try(e.signing_payload(c,context,purpose,review) |> result.map_error(fn(_){InvalidData}))
 let header=e.header_bytes(c,purpose)
 use hv <- result.try(json_guard.native_inspect(header,4) |> result.map_error(fn(_){InvalidData}))
 use kid <- result.try(text(hv,"kid"))
 use _ <- result.try(need(string.byte_size(public_key)==43))
 let jwks=json.to_string(json.object([#("keys",json.array([public_key],fn(key){json.object([
  #("kty",json.string("OKP")),#("crv",json.string("Ed25519")),#("kid",json.string(kid)),#("alg",json.string("EdDSA")),#("use",json.string("sig")),#("x",json.string(key))])}))]))
 use _ <- result.try(valid_keys(jwks) |> result.map_error(fn(_){InvalidData}))
 let #(reference,name)=case purpose {
  e.IndependentReview -> #("uos-recovery-reviewer-v1",e.review_purpose)
  e.TaskRecoveryIssuer -> #("uos-recovery-issuer-v1",e.issuer_purpose)
 }
 let cfg=e.configuration_sha256(c)
 let context_sha=e.context_sha256(context)
 let native_sha=e.request_sha256(context)
 let id=files.digest(json.to_string(json.array([reference,name,header,payload,review,cfg,context_sha,native_sha],json.string)))
 let body=json.to_string(json.object([
  #("schema",json.string("uos.recovery.signing-request.v1")),#("profile",json.string(e.profile)),
  #("request_id",json.string(id)),#("key_reference",json.string(reference)),#("purpose",json.string(name)),
  #("header",json.string(header)),#("payload",json.string(payload)),#("review_token",json.string(review)),
  #("configuration_sha256",json.string(cfg)),#("context_sha256",json.string(context_sha)),#("native_request_sha256",json.string(native_sha))]))
 use _ <- result.try(need(string.byte_size(body)<=32768))
 Ok(Prepared(body,id,reference,header,payload,jwks))
}
pub fn request_bytes(request: Prepared) -> String { request.body }
/// There is deliberately no production provider constructor/configuration
/// fallback. A valid Prepared value or fixture transport is not permission.
pub fn sign(_request: Prepared) -> Result(SignedUnderData, Error) { Error(Unavailable) }
/// Verifies cryptographic response under explicitly supplied PUBLIC DATA only.
/// The final two-party envelope verifier must also match its own configuration.
pub fn verify_response(request: Prepared, raw: String) -> Result(SignedUnderData,Error) {
 use _ <- result.try(need(string.byte_size(raw)>0&&string.byte_size(raw)<=16384))
 use value <- result.try(json_guard.native_inspect(raw,8) |> result.map_error(fn(_){InvalidData}))
 use _ <- result.try(need(closed(value,["schema","request_id","key_reference","token","authority","admitted"])))
 use schema <- result.try(text(value,"schema"))
 use id <- result.try(text(value,"request_id"))
 use reference <- result.try(text(value,"key_reference"))
 use authority <- result.try(text(value,"authority"))
 use token <- result.try(text(value,"token"))
 use _ <- result.try(need(schema=="uos.recovery.signing-response.v1"&&id==request.request_id
  &&reference==request.key_reference&&authority=="NONE"&&v.get(value,"admitted")==Ok(v.Boolean(False))
  &&string.byte_size(token)>0&&string.byte_size(token)<=8192))
 let expected=request.header |> bit_array.from_string |> bit_array.base64_url_encode(False)
 use _ <- result.try(need(case string.split(token,".") { [header,_,_] ->header==expected _->False }))
 use payload <- result.try(verify_jwt(token,request.jwks) |> result.map_error(fn(_){InvalidData}))
 use _ <- result.try(need(payload==request.payload))
 Ok(SignedUnderData(token,id))
}
pub fn token(signed: SignedUnderData) -> String { signed.token }
pub fn authority(_signed: SignedUnderData) -> String { "NONE" }
