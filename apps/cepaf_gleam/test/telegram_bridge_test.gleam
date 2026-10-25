import cepaf_gleam/harness/telegram_bridge as bridge
import cepaf_gleam/harness/telegram_store_transport as transport
import cepaf_gleam/harness/files
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should

fn request() {
  let assert Ok(r) =
    bridge.new(
      "mapping-1",
      "fence",
      "controller",
      "owner",
      1,
      "runtime-bridge",
      1000,
    )
  r
}

fn body(historical, found, lease) {
  json.object([
    #("schema", json.string("uos.telegram.cancel-transport-response.v1")),
    #("status", json.string("ok")),
    #("error", json.null()),
    #(
      "result",
      json.object([
        #("schema", json.string("uos.sa-plan.bridge-bind-response.v1")),
        #("found", json.bool(found)),
        #("historical", json.bool(historical)),
        #("observed_at_ns", json.int(100)),
        #("lease", lease),
      ]),
    ),
  ])
  |> json.to_string
}

fn lease() {
  json.object([
    #("mapping_id", json.string("mapping-1")),
    #("plan_id", json.string("fence")),
    #("task_id", json.string("controller")),
    #("owner", json.string("owner")),
    #("task_attempt", json.int(1)),
    #("lease_id", json.string("runtime-bridge")),
    #("fencing_token", json.int(7)),
    #("expires_at_ns", json.int(1000)),
  ])
}

pub fn request_bounds_test() {
  list.each(
    ["", " ", "../bad", "a..b", "x\\n", "é", string.repeat("a", 241)],
    fn(value) {
      bridge.new(
        value,
        "fence",
        "controller",
        "owner",
        1,
        "runtime-bridge",
        1000,
      )
      |> result.is_error
      |> should.be_true
    },
  )
  list.each([0, -1, 2_147_483_648], fn(attempt) {
    bridge.new(
      "mapping-1",
      "fence",
      "controller",
      "owner",
      attempt,
      "lease",
      1000,
    )
    |> result.is_error
    |> should.be_true
  })
  list.each([0, -1, 9_223_372_036_854_775_808], fn(expiry) {
    bridge.new("mapping-1", "fence", "controller", "owner", 1, "lease", expiry)
    |> result.is_error
    |> should.be_true
  })
}

pub fn request_envelope_test() {
  bridge.envelope(request(), bridge.Bind)
  |> string.contains(bridge.request_json(request()))
  |> should.be_true
  bridge.envelope(request(), bridge.Lookup)
  |> string.contains("controller-bridge-result")
  |> should.be_true
}

pub fn found_bind_and_expired_history_test() {
  bridge.decode_response(
    request(),
    bridge.Bind,
    body(False, True, lease()),
    101,
  )
  |> should.equal(Ok(bridge.Found(7, 1000, 100, False)))
  bridge.decode_response(
    request(),
    bridge.Lookup,
    body(True, True, lease()),
    2000,
  )
  |> should.equal(Ok(bridge.Found(7, 1000, 100, True)))
}

pub fn exact_binding_test() {
  list.each(
    [
      #("mapping-1", "mapping-2"),
      #("fence", "other-plan"),
      #("controller", "other-task"),
      #("\"owner\":\"owner\"", "\"owner\":\"other\""),
      #("\"task_attempt\":1", "\"task_attempt\":2"),
      #("runtime-bridge", "other-lease"),
      #("\"expires_at_ns\":1000", "\"expires_at_ns\":1001"),
      #("\"fencing_token\":7", "\"fencing_token\":0"),
      #("\"fencing_token\":7", "\"fencing_token\":9223372036854775808"),
    ],
    fn(change) {
      body(False, True, lease())
      |> string.replace(change.0, change.1)
      |> bridge.decode_response(request(), bridge.Bind, _, 101)
      |> result.is_error
      |> should.be_true
    },
  )
}

pub fn strict_closed_response_test() {
  let good = body(False, True, lease())
  list.each(
    [
      "",
      "{}",
      "[]",
      string.repeat("x", 16_385),
      good |> string.replace("\"found\":true", "\"found\":true,\"found\":true"),
      good |> string.replace("\"found\":true", "\"found\":true,\"extra\":false"),
      good |> string.replace("\"task_attempt\":1", "\"task_attempt\":1.0"),
      good |> string.replace("\"fencing_token\":7", "\"fencing_token\":\"7\""),
      good |> string.replace("\"observed_at_ns\":100", "\"observed_at_ns\":-1"),
      good |> string.replace("\"observed_at_ns\":100", "\"observed_at_ns\":102"),
    ],
    fn(raw) {
      bridge.decode_response(request(), bridge.Bind, raw, 101)
      |> result.is_error
      |> should.be_true
    },
  )
}

pub fn operation_expiry_and_absence_test() {
  bridge.decode_response(request(), bridge.Bind, body(True, True, lease()), 101)
  |> result.is_error
  |> should.be_true
  bridge.decode_response(
    request(),
    bridge.Lookup,
    body(False, True, lease()),
    101,
  )
  |> result.is_error
  |> should.be_true
  bridge.decode_response(
    request(),
    bridge.Bind,
    body(False, True, lease()),
    1000,
  )
  |> result.is_error
  |> should.be_true
  bridge.decode_response(
    request(),
    bridge.Lookup,
    body(True, False, json.null()),
    101,
  )
  |> should.equal(Ok(bridge.Absent))
  bridge.decode_response(
    request(),
    bridge.Bind,
    body(False, False, json.null()),
    101,
  )
  |> result.is_error
  |> should.be_true
  let assert Ok(long) =
    bridge.new(
      "mapping-1",
      "fence",
      "controller",
      "owner",
      1,
      "runtime-bridge",
      300_000_000_101,
    )
  let raw =
    body(False, True, lease())
    |> string.replace(
      "\"expires_at_ns\":1000",
      "\"expires_at_ns\":300000000101",
    )
  bridge.decode_response(long, bridge.Bind, raw, 101)
  |> result.is_error
  |> should.be_true
}

pub fn rejection_is_not_success_test() {
  let raw =
    "{\"schema\":\"uos.telegram.cancel-transport-response.v1\",\"status\":\"rejected\",\"result\":null,\"error\":\"cancel_request_rejected\"}"
  bridge.decode_response(request(), bridge.Bind, raw, 101)
  |> should.equal(Ok(bridge.Rejected))
  raw
  |> string.replace("cancel_request_rejected", "private-details")
  |> bridge.decode_response(request(), bridge.Bind, _, 101)
  |> result.is_error
  |> should.be_true
}

type TimeUnit {
  Nanosecond
}

@external(erlang, "erlang", "system_time")
fn time(unit: TimeUnit) -> Int

/// Actual isolated native transport fixture; never a live service entrypoint.
pub fn run_native(
  config: transport.LocalConfiguration,
  mapping: String,
  expiry: Int,
) {
  let assert Ok(r) =
    bridge.new(
      mapping,
      "fence",
      "controller",
      "owner",
      1,
      "runtime-bridge",
      expiry,
    )
  let assert Ok(raw) =
    transport.exchange(config, bridge.envelope(r, bridge.Lookup))
  bridge.decode_response(r, bridge.Lookup, raw, time(Nanosecond))
  |> should.equal(Ok(bridge.Absent))
  let assert Ok(raw) =
    transport.exchange(config, bridge.envelope(r, bridge.Bind))
  let assert Ok(bridge.Found(1, saved_expiry, _, False)) =
    bridge.decode_response(r, bridge.Bind, raw, time(Nanosecond))
  saved_expiry |> should.equal(expiry)
  let assert Ok(raw) =
    transport.exchange(config, bridge.envelope(r, bridge.Bind))
  bridge.decode_response(r, bridge.Bind, raw, time(Nanosecond))
  |> should.equal(Ok(bridge.Rejected))
  let assert Ok(raw) =
    transport.exchange(config, bridge.envelope(r, bridge.Lookup))
  let assert Ok(bridge.Found(1, recovered_expiry, _, True)) =
    bridge.decode_response(r, bridge.Lookup, raw, time(Nanosecond))
  recovered_expiry |> should.equal(expiry)
  "bridge_bound_and_reconciled"
}

pub fn durable_exact_request_restoration_test() {
  let original = bridge.request_json(request())
  let assert Ok(restored) = bridge.restore(original)
  bridge.request_json(restored) |> should.equal(original)
  bridge.matches_context(restored, "fence", "controller", "owner", 1)
  |> should.be_true
  bridge.matches_context(restored, "fence", "controller", "owner", 2)
  |> should.be_false
  bridge.expires_at_ns(restored) |> should.equal(1000)
}

pub fn restoration_refuses_noncanonical_or_unknown_fields_test() {
  let raw = bridge.request_json(request())
  list.each(
    [
      " " <> raw,
      raw <> " ",
      raw
        |> string.replace(
          "\"task_attempt\":1",
          "\"task_attempt\":1,\"extra\":true",
        ),
      raw
        |> string.replace(
          "\"owner\":\"owner\"",
          "\"owner\":\"owner\",\"owner\":\"owner\"",
        ),
      raw |> string.replace("\"task_attempt\":1", "\"task_attempt\":1.0"),
    ],
    fn(value) { bridge.restore(value) |> result.is_error |> should.be_true },
  )
}

fn target_response() -> String {
 json.object([
  #("schema",json.string("uos.telegram.cancel-transport-response.v1")),
  #("status",json.string("ok")), #("error",json.null()),
  #("result",json.object([
   #("schema",json.string("uos.sa-plan.cancel-target-response.v1")),
   #("controller_sha256",json.string(files.digest(bridge.request_json(request())))),
   #("fencing_token",json.int(7)), #("observed_at_ns",json.int(100)),
   #("target",json.object([
     #("job_id",json.string("fence/job-1")),#("worker",json.string("job-worker")),
     #("attempt",json.int(2)),#("lease_until_ns",json.int(900))
   ]))
  ]))
 ]) |> json.to_string
}
pub fn target_request_scope_test() {
 let assert Ok(raw)=bridge.target_envelope(request(),7,"fence/job-1")
 string.contains(raw,"inspect-cancellation-target") |> should.be_true
 list.each(["fence/","foreign/job","fence/../job","fence/job;DROP"],fn(job){
  bridge.target_envelope(request(),7,job) |> should.be_error
 })
 list.each([0,-1,9223372036854775808],fn(fence){
  bridge.target_envelope(request(),fence,"fence/job-1") |> should.be_error
 })
}
pub fn target_exact_response_test() {
 bridge.decode_target_response(request(),7,"fence/job-1",target_response(),101)
 |> should.equal(Ok(bridge.TargetObservation("fence/job-1","job-worker",2,900,100)))
}
pub fn target_misbound_or_malformed_response_test() {
 let raw=target_response()
 list.each([
  #("cancel-target-response.v1","cancel-target-response.future"),
  #(files.digest(bridge.request_json(request())),string.repeat("0",64)),
  #("\"fencing_token\":7","\"fencing_token\":8"),
  #("\"observed_at_ns\":100","\"observed_at_ns\":102"),
  #("fence/job-1","fence/job-2"),
  #("job-worker","bad worker"),
  #("\"attempt\":2","\"attempt\":0"),
  #("\"lease_until_ns\":900","\"lease_until_ns\":101"),
  #("\"attempt\":2","\"attempt\":2,\"secret\":true"),
  #("\"attempt\":2","\"attempt\":2,\"attempt\":2"),
  #("\"attempt\":2","\"attempt\":2.0"),
  #("\"status\":\"ok\"","\"status\":\"rejected\""),
 ],fn(pair){
  bridge.decode_target_response(request(),7,"fence/job-1",
    string.replace(raw,pair.0,pair.1),101)
    |> should.equal(Error("invalid_target_response"))
 })
 list.each(["","{}","[]",raw <> "x",string.repeat("x",16385)],fn(s){
  bridge.decode_target_response(request(),7,"fence/job-1",s,101) |> should.be_error
 })
}
pub fn target_expiry_and_clock_test() {
 list.each([-1,99,900,1000,9223372036854775808],fn(now){
  bridge.decode_target_response(request(),7,"fence/job-1",target_response(),now)
   |> should.be_error
 })
}

pub fn inspect_native(config:transport.LocalConfiguration,mapping:String,
 expiry:Int,target_expiry:Int) {
 let assert Ok(r)=bridge.new(mapping,"cancel-plan","controller","controller",1,"control-lease",expiry)
 let assert Ok(envelope)=bridge.target_envelope(r,1,"cancel-plan/job1")
 let assert Ok(raw)=transport.exchange(config,envelope)
 let assert Ok(bridge.TargetObservation(job,worker,attempt,lease,_))=
  bridge.decode_target_response(r,1,"cancel-plan/job1",raw,time(Nanosecond))
 job |> should.equal("cancel-plan/job1")
 worker |> should.equal("job-worker")
 attempt |> should.equal(1)
 lease |> should.equal(target_expiry)
 let assert Ok(wrong)=bridge.target_envelope(r,2,"cancel-plan/job1")
 let assert Ok(raw)=transport.exchange(config,wrong)
 bridge.decode_target_response(r,2,"cancel-plan/job1",raw,time(Nanosecond)) |> should.be_error
 "exact_target_observed_no_mutation"
}
