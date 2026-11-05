//// Finite integration prerequisite: move an EXISTING main to an already
//// assembled, reviewed, conflict-free descendant. This does not merge divergent
//// work, push remotely, deploy, admit code or complete the all-code goal.
//// Public construction is DATA. No admitted issuer/integration owner exists;
//// production integrate always refuses before I/O. Private fixtures append a
//// separately compiled interpreter, never an environment/boolean trust switch.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_store_transport as transport
import cepaf_gleam/harness/value as v
import cepaf_gleam/mcp/json_guard
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub type BindingData {
  BindingData(plan: String, task: String, worker: String, attempt: Int,
    integration_owner: String, integration_epoch: Int)
}
pub type CandidateData {
  CandidateData(expected_main: String, candidate: String, expected_operation: String,
    manifest_sha256: String, review_sha256: String, tests_sha256: String)
}
pub opaque type Intent {
  Intent(bytes: String, sha256: String, binding: BindingData, candidate: CandidateData)
}
/// A transport locator is DATA, not a trusted launcher or effect permission.
pub opaque type ConnectionData { ConnectionData(transport.LocalConfiguration) }
pub fn connection_data(local: transport.LocalConfiguration) -> ConnectionData { ConnectionData(local) }
pub type Outcome {
  IntegratedFact(String)
  HistoricalFact(String)
  Refused(String)
  ReconcileOnly
  CleanupUnconfirmed
}
fn hex(s: String, n: Int) -> Bool {
  string.byte_size(s) == n && list.all(string.to_graphemes(s), fn(c) {
    string.byte_size(c) == 1 && string.contains("0123456789abcdef", c)
  })
}
fn id(s: String) -> Bool {
  string.byte_size(s) > 0 && string.byte_size(s) <= 160
  && list.all(string.to_graphemes(s), fn(c) {
    string.byte_size(c) == 1 && string.contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./", c)
  })
}
pub fn prepare(logical_id: String, binding: BindingData, candidate: CandidateData) -> Result(Intent, String) {
  case id(logical_id) && id(binding.plan) && id(binding.task) && id(binding.worker)
    && id(binding.integration_owner) && binding.attempt > 0 && binding.attempt <= 1_000_000
    && binding.integration_epoch > 0 && binding.integration_epoch <= 1_000_000
    && hex(candidate.expected_main, 40) && hex(candidate.candidate, 40)
    && candidate.expected_main != candidate.candidate && hex(candidate.expected_operation, 128)
    && hex(candidate.manifest_sha256, 64) && hex(candidate.review_sha256, 64) && hex(candidate.tests_sha256, 64) {
    False -> Error("INVALID_BOUNDED_INTEGRATION_DATA")
    True -> {
      let bytes = json.to_string(json.object([
        #("domain", json.string("uos.jj.fast-forward-integration-data.v1")),
        #("logical_id", json.string(logical_id)), #("plan", json.string(binding.plan)),
        #("task", json.string(binding.task)), #("worker", json.string(binding.worker)),
        #("attempt", json.int(binding.attempt)), #("integration_owner", json.string(binding.integration_owner)),
        #("integration_epoch", json.int(binding.integration_epoch)),
        #("expected_main", json.string(candidate.expected_main)), #("candidate", json.string(candidate.candidate)),
        #("expected_operation", json.string(candidate.expected_operation)),
        #("manifest_sha256", json.string(candidate.manifest_sha256)),
        #("review_sha256", json.string(candidate.review_sha256)), #("tests_sha256", json.string(candidate.tests_sha256)),
      ]))
      Ok(Intent(bytes, files.digest(bytes), binding, candidate))
    }
  }
}
pub fn intent_sha256(intent: Intent) -> String { intent.sha256 }
pub fn intent_bytes(intent: Intent) -> String { intent.bytes }

/// Caller identities/digests/paths are never permission; no public native
/// executor or callback constructor can change this production refusal.
pub fn integrate(_intent: Intent) -> Result(Outcome, String) {
  Error("PRODUCTION_INTEGRATION_AUTHORITY_UNAVAILABLE")
}

fn text(j: v.Value, key: String) -> Result(String, String) {
  case v.get(j, key) { Ok(v.Text(s)) -> Ok(s) _ -> Error("REPLY_TEXT") }
}
fn closed(j: v.Value, keys: List(String)) -> Bool {
  case j {
    v.Object(fs) -> list.length(fs) == list.length(keys)
      && list.length(list.unique(list.map(fs, fn(kv) { kv.0 }))) == list.length(keys)
      && list.all(fs, fn(kv) { list.contains(keys, kv.0) })
    _ -> False
  }
}
pub fn decode_reply_data(raw: String, intent: Intent) -> Result(#(String, String), String) {
  use reply <- result.try(json_guard.native_inspect(raw, 5) |> result.map_error(fn(_) { "NATIVE_JSON" }))
  case closed(reply, ["schema", "code", "intent_sha256", "fact", "authority"])
    && v.get(reply, "schema") == Ok(v.Text("uos.jj.integration-fixture-reply.v1"))
    && v.get(reply, "intent_sha256") == Ok(v.Text(intent.sha256))
    && v.get(reply, "authority") == Ok(v.Text("NONE")) {
    False -> Error("NATIVE_REPLY_BINDING")
    True -> {
      use code <- result.try(text(reply, "code"))
      use fact <- result.try(text(reply, "fact"))
      case string.byte_size(fact) <= 4096 { True -> Ok(#(code, fact)) False -> Error("FACT_BOUND") }
    }
  }
}

// Kept private for the fixture extension. These imports/helpers are part of
// the closed native reply codec, not an implementation of runtime authority.
pub fn data_summary(intent: Intent) -> String {
  intent.binding.plan <> "/" <> intent.binding.task <> "@" <> int.to_string(intent.binding.attempt)
}
