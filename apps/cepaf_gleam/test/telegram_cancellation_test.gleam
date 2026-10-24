//// Test-only ephemeral approval fixture; no production signer or recipient.

import cepaf_gleam/harness/telegram_action_intent as action
import cepaf_gleam/harness/telegram_approval as approval
import cepaf_gleam/harness/telegram_cancellation as cancel
import cepaf_gleam/harness/telegram_store_transport as transport
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should

pub fn fixture(
  binding: action.Binding,
  target: action.Target,
  created: Int,
  expires: Int,
  reason: String,
) {
  let assert Ok(intent) =
    action.new(
      binding,
      target,
      action.Window(created, 20_000, created + 60_000, 80_000),
      reason,
      string.repeat("b", 64),
    )
  let signers =
    list.map([approval.Codex, approval.Agy, approval.Operator], fn(role) {
      let name = approval.role_name(role)
      approval.Signer(
        role,
        name <> "-subject",
        name <> "-key",
        public_key(name),
      )
    })
  let assert Ok(roster) =
    approval.new_roster(signers, created - 1, created + 120_000)
  let receipts =
    list.map([approval.Codex, approval.Agy, approval.Operator], fn(role) {
      let name = approval.role_name(role)
      let payload =
        json.object([
          #("version", json.string("uos.telegram.approval.v1")),
          #("purpose", json.string("cancel_job_lease")),
          #("role", json.string(name)),
          #("subject", json.string(name <> "-subject")),
          #("decision", json.string("approve")),
          #("intent_digest", json.string(action.digest(intent))),
          #("effect_id", json.string(action.effect_id(intent))),
          #("iat_ms", json.int(created)),
          #("nbf_ms", json.int(created)),
          #("exp_ms", json.int(expires)),
          #("roster_digest", json.string(approval.roster_digest(roster))),
        ])
        |> json.to_string
      approval.Receipt(role, sign(name, payload))
    })
  let observed =
    cancel.Observation(binding.host, binding.boot_id, created, 20_000)
  let assert Ok(evidence) =
    approval.verify(
      roster,
      intent,
      binding.host,
      binding.boot_id,
      created,
      20_000,
      receipts,
    )
  let assert Ok(prepared) =
    cancel.prepare(intent, evidence, roster, binding, target, observed)
  #(prepared, intent, roster, evidence, observed)
}

fn binding() {
  action.Binding(
    7,
    -11,
    13,
    19,
    "cancel-plan",
    "controller",
    "controller",
    1,
    1,
    string.repeat("a", 64),
    "nas-1.tail55d152.ts.net",
    "test-boot",
    action.Execution("mapping-1", "control-lease", 1, string.repeat("d", 64)),
  )
}

fn target() {
  action.Target("cancel-plan/job1", "job-worker", 1, 2_000_000_000_000)
}

fn setup() {
  fixture(
    binding(),
    target(),
    1_000_000,
    1_030_000,
    "Operator requested cancellation",
  )
}

pub fn receipt(p, i, historical) {
  json.object([
    #("schema", json.string("uos.telegram.cancel-transport-response.v1")),
    #("status", json.string("ok")),
    #("error", json.null()),
    #(
      "result",
      json.object([
        #("schema", json.string("uos.sa-plan.cancel-job-response.v1")),
        #("found", json.bool(True)),
        #("historical", json.bool(historical)),
        #(
          "receipt",
          json.object([
            #("mapping_id", json.string("mapping-1")),
            #("command_id", json.string("cancel-job:" <> action.effect_id(i))),
            #("request_hash", json.string(cancel.request_hash(p))),
            #("recorded_at_ns", json.int(1_010_000_000_000)),
            #("replayed", json.bool(historical)),
            #(
              "result",
              json.object([
                #(
                  "schema",
                  json.string("uos.sa-plan.cancel-job-once.receipt.v1"),
                ),
                #("operation", json.string("cancel_job_lease")),
                #("status", json.string("job_lease_revoked")),
                #("effect_id", json.string(action.effect_id(i))),
                #("intent_sha256", json.string(action.digest(i))),
                #("job_id", json.string("cancel-plan/job1")),
                #("matched_attempt", json.int(1)),
                #("job_lease_cleared", json.bool(True)),
                #("task_cancelled", json.bool(False)),
                #("process_quiesced", json.bool(False)),
              ]),
            ),
          ]),
        ),
      ]),
    ),
  ])
  |> json.to_string
}

pub fn approval_preparation_and_deadline_test() {
  let #(p, i, r, e, o) = setup()
  cancel.deadline_ms(p) |> should.equal(1_030_000)
  action.native_request(i, 1_030_000)
  |> should.equal(Ok(cancel.request_json(p)))
  cancel.ready(p, r, binding(), target(), o) |> should.be_true
  cancel.ready(
    p,
    r,
    binding(),
    target(),
    cancel.Observation(..o, utc_ms: 1_030_000, boot_ms: 50_000),
  )
  |> should.be_false
  let b = binding()
  let t = target()
  list.each(
    [
      action.Binding(..b, user_id: 14),
      action.Binding(..b, attempt: 2),
      action.Binding(
        ..b,
        execution: action.Execution(
          "other",
          "control-lease",
          1,
          string.repeat("d", 64),
        ),
      ),
    ],
    fn(changed) {
      cancel.prepare(i, e, r, changed, t, o)
      |> result.is_error
      |> should.be_true
      cancel.ready(p, r, changed, t, o) |> should.be_false
    },
  )
  cancel.ready(p, r, b, t, cancel.Observation(..o, boot: "other"))
  |> should.be_false
  cancel.ready(p, r, b, action.Target(..t, attempt: 2), o) |> should.be_false
}

pub fn exact_response_and_historical_recovery_test() {
  let #(p, i, _, _, _) = setup()
  cancel.decode_response(p, cancel.Cancel, receipt(p, i, False), 1_020_000)
  |> should.equal(Ok(cancel.LeaseRevoked(1_010_000_000_000, False, False)))
  cancel.decode_response(p, cancel.Lookup, receipt(p, i, True), 1_090_000)
  |> should.equal(Ok(cancel.LeaseRevoked(1_010_000_000_000, True, True)))
  cancel.decode_response(p, cancel.Cancel, receipt(p, i, True), 1_020_000)
  |> result.is_error
  |> should.be_true
  cancel.decode_response(p, cancel.Lookup, receipt(p, i, False), 1_020_000)
  |> result.is_error
  |> should.be_true
}

pub fn malformed_or_misbound_response_never_confirms_effect_test() {
  let #(p, i, _, _, _) = setup()
  let good = receipt(p, i, False)
  list.each(
    [
      "",
      "{}",
      "[]",
      string.repeat("x", 16_385),
      string.replace(
        good,
        "\"status\":\"ok\"",
        "\"status\":\"ok\",\"status\":\"ok\"",
      ),
      string.replace(
        good,
        "\"mapping_id\":\"mapping-1\"",
        "\"mapping_id\":\"other\"",
      ),
      string.replace(good, action.digest(i), string.repeat("f", 64)),
      string.replace(good, cancel.request_hash(p), string.repeat("f", 64)),
      string.replace(good, "\"matched_attempt\":1", "\"matched_attempt\":2"),
      string.replace(
        good,
        "\"job_lease_cleared\":true",
        "\"job_lease_cleared\":false",
      ),
      string.replace(
        good,
        "\"task_cancelled\":false",
        "\"task_cancelled\":true",
      ),
      string.replace(
        good,
        "\"process_quiesced\":false",
        "\"process_quiesced\":true",
      ),
      string.replace(good, "1010000000000", "1030000000000"),
      string.replace(good, "\"replayed\":false", "\"replayed\":0"),
      string.replace(good, "\"error\":null", "\"error\":null,\"extra\":0"),
    ],
    fn(raw) {
      cancel.decode_response(p, cancel.Cancel, raw, 1_020_000)
      |> result.is_error
      |> should.be_true
    },
  )
  cancel.decode_response(p, cancel.Cancel, good, 1_009_999)
  |> result.is_error
  |> should.be_true
  cancel.decode_response(p, cancel.Cancel, good, -1)
  |> result.is_error
  |> should.be_true
}

pub fn rejection_and_absence_are_not_success_test() {
  let #(p, _, _, _, _) = setup()
  let rejected =
    "{\"schema\":\"uos.telegram.cancel-transport-response.v1\",\"status\":\"rejected\",\"result\":null,\"error\":\"cancel_request_rejected\"}"
  cancel.decode_response(p, cancel.Cancel, rejected, 1_020_000)
  |> should.equal(Ok(cancel.Rejected))
  let missing =
    "{\"schema\":\"uos.telegram.cancel-transport-response.v1\",\"status\":\"ok\",\"error\":null,\"result\":{\"schema\":\"uos.sa-plan.cancel-job-response.v1\",\"found\":false,\"historical\":true,\"receipt\":null}}"
  cancel.decode_response(p, cancel.Lookup, missing, 1_090_000)
  |> should.equal(Ok(cancel.Absent))
  cancel.decode_response(p, cancel.Cancel, missing, 1_020_000)
  |> result.is_error
  |> should.be_true
}

pub fn envelope_keeps_exact_native_request_test() {
  let #(p, _, _, _, _) = setup()
  let a = cancel.envelope(p, cancel.Cancel)
  let b = cancel.envelope(p, cancel.Lookup)
  string.contains(a, cancel.request_json(p)) |> should.be_true
  string.contains(b, cancel.request_json(p)) |> should.be_true
  string.replace(a, "cancel-once", "cancellation-result") |> should.equal(b)
}

@external(erlang, "telegram_approval_test_crypto", "public_key")
fn public_key(role: String) -> String

@external(erlang, "telegram_approval_test_crypto", "sign")
fn sign(role: String, payload: String) -> String

type TimeUnit {
  Millisecond
}

@external(erlang, "erlang", "system_time")
fn time(unit: TimeUnit) -> Int

/// Called by the OCaml isolated-store test, never a production runtime entry.
pub fn run_native(
  config: transport.LocalConfiguration,
  mapping: String,
  fence: Int,
  target_lease_ns: Int,
  artifact: String,
) {
  let created = time(Millisecond)
  let b =
    action.Binding(
      ..binding(),
      candidate_sha256: artifact,
      execution: action.Execution(
        mapping,
        "control-lease",
        fence,
        string.repeat("d", 64),
      ),
    )
  let t = action.Target(..target(), lease_until_ns: target_lease_ns)
  let #(p, i, r, _, o) =
    fixture(b, t, created, created + 30_000, "Cancellation é \"quote\" \\ path")
  cancel.ready(p, r, b, t, o) |> should.be_true
  let exact = cancel.request_json(p)
  let assert Ok(first) =
    transport.exchange(config, cancel.envelope(p, cancel.Cancel))
  let assert Ok(cancel.LeaseRevoked(_, False, False)) =
    cancel.decode_response(p, cancel.Cancel, first, time(Millisecond))
  let assert Ok(recovered) =
    transport.exchange(config, cancel.envelope(p, cancel.Lookup))
  let assert Ok(cancel.LeaseRevoked(_, _, True)) =
    cancel.decode_response(p, cancel.Lookup, recovered, time(Millisecond))
  cancel.request_json(p) |> should.equal(exact)
  json.object([
    #("schema", json.string("uos.telegram.signed-native-test.v1")),
    #("status", json.string("passed")),
    #("intent_sha256", json.string(action.digest(i))),
    #("effect_id", json.string(action.effect_id(i))),
    #("request_hash", json.string(cancel.request_hash(p))),
    #("request_json", json.string(exact)),
  ])
  |> json.to_string
}
