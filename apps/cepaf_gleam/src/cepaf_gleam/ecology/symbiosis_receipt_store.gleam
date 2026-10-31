//// Sanitized raw-observation storage, not policy acceptance or effect authority.
//// One local owner must retain the returned opaque intent: immutable aliases
//// are not linear capabilities. Native idempotency protects rows, not resubmits.
//// Invoke bounded exchange from an isolated collector, never a root actor loop.
//// CleanupUnconfirmed is terminal here: row readback cannot prove process reaping.
//// No public reset exists; a future genuine owner-reaping adapter is separate.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_store_transport as transport
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import uos_swarm/symbiosis_preflight as policy

pub const max_request_bytes = 262_144

pub const max_response_bytes = 524_288

pub type Context {
  Context(
    receipt_id: String,
    operation_id: String,
    owner_id: String,
    owner_epoch: Int,
    clock_domain: String,
    observed_utc_us: Int,
    expires_mono_ms: Int,
  )
}

pub type Error {
  InvalidContext
  InvalidObservation
  InvalidCoverage
  RequestBound
}

pub type Phase {
  Prepared
  NeedsReconciliation
  ReapingUnconfirmed
  Acknowledged
}

pub type Cleanup {
  NotStarted
  Reaped(guardian_exit_code: Int, observed_utc_us: Int)
  Unconfirmed
}

/// Trusted injected IO must bind result and cleanup to the SAME invocation.
/// This record is a test/adapter boundary, not authenticated external evidence.
pub type Exchange {
  Exchange(result: Result(String, transport.TransportError), cleanup: Cleanup)
}

pub type NativeCode {
  InvalidJson
  InvalidReceipt
  InvalidRequest
  InvalidPath
  SchemaMismatch
  NestedTransaction
  StoreUnavailable
  ResourceBound
  Conflict
  StaleEpoch
  OutOfOrder
  CommitUnknown
  RollbackFailed
  Closed
}

pub type Outcome {
  Stored
  Replayed
  Reconciled
  NativeHold(NativeCode)
  UnknownOutcome
  ProtocolUncertain
  CleanupUnconfirmed
  SubmitBlocked
}

pub type Acknowledgement {
  Acknowledgement(
    record_index: Int,
    receipt_id: String,
    payload_sha256: String,
    bound_sequence: Int,
  )
}

pub opaque type Intent {
  Intent(
    context: Context,
    sequence: Int,
    canonical_receipt: String,
    sha256: String,
    phase: Phase,
    ack: Option(Acknowledgement),
    cleanup: Cleanup,
  )
}

pub type Transition {
  Transition(intent: Intent, outcome: Outcome)
}

// Generic bounded strict JSON FFI only; no Telegram domain codec is used.
type Value {
  JsonObject(List(#(String, Value)))
  JsonArray(List(Value))
  JsonString(String)
  JsonInt(Int)
  JsonFloat(Float)
  JsonBool(Bool)
  JsonNull
}

@external(erlang, "telegram_store_codec_ffi", "parse_strict")
fn parse_strict(text: String) -> Result(Value, String)

@external(erlang, "telegram_store_transport_ffi", "request_config_with_cleanup")
fn request_with_cleanup(
  config: transport.LocalConfiguration,
  body: String,
) -> #(Result(String, String), Option(#(Int, Int)))

fn native_exchange(
  config: transport.LocalConfiguration,
  body: String,
) -> Exchange {
  let #(response, witness) = request_with_cleanup(config, body)
  let cleanup = case witness {
    Some(#(code, at)) -> Reaped(code, at)
    None -> Unconfirmed
  }
  let response =
    response
    |> result.map_error(fn(code) {
      case code {
        "transport_input_bound" -> transport.InputBound
        "transport_configuration_or_spawn" -> transport.ConfigurationOrSpawn
        "transport_cleanup_unknown" -> transport.CleanupUnknown
        _ -> transport.Uncertain
      }
    })
  Exchange(response, cleanup)
}

fn cleanup_confirmed(exchange: Exchange) -> Bool {
  case exchange.result, exchange.cleanup {
    Ok(_), Reaped(0, at) -> at > 0 && at <= 9_000_000_000_000_000
    Error(transport.Uncertain), Reaped(code, at) ->
      { code == 0 || code == 124 || code == 125 }
      && at > 0
      && at <= 9_000_000_000_000_000
    _, _ -> False
  }
}

fn reaping_unconfirmed(i: Intent) -> Transition {
  Transition(
    Intent(..i, phase: ReapingUnconfirmed, ack: None, cleanup: Unconfirmed),
    CleanupUnconfirmed,
  )
}

fn ordered(fields: List(#(String, json.Json))) -> json.Json {
  json.object(list.sort(fields, fn(a, b) { string.compare(a.0, b.0) }))
}

fn agent(a: policy.Agent) -> String {
  case a {
    policy.Claude -> "claude"
    policy.Pi -> "pi"
    policy.Agy -> "agy"
    policy.Codex -> "codex"
  }
}

fn capability(c: policy.Capability) -> String {
  case c {
    policy.KnowledgeSearch -> "knowledge_search"
    policy.KnowledgeRead -> "knowledge_read"
    policy.KnowledgeWriteback -> "knowledge_writeback"
    policy.TaskAuthority -> "task_authority"
    policy.TaskExecution -> "task_execution"
    policy.Verification -> "verification"
    policy.ModelBudget -> "model_budget"
    policy.Transport -> "transport"
  }
}

fn probe(p: policy.Probe) -> String {
  case p {
    policy.HeartbeatProbe -> "heartbeat"
    policy.CapabilityProbe(_) -> "functional"
    policy.CoverageProbe -> "coverage"
  }
}

fn service(p: policy.Probe) -> String {
  case p {
    policy.HeartbeatProbe -> "heartbeat"
    policy.CapabilityProbe(c) -> capability(c)
    policy.CoverageProbe -> "required_service_coverage"
  }
}

fn identifier(s: String, cap: Int) -> Bool {
  string.byte_size(s) > 0
  && string.byte_size(s) <= cap
  && list.all(string.to_graphemes(s), fn(c) {
    string.byte_size(c) == 1
    && string.contains(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.:/-",
      c,
    )
  })
}

fn hex(s: String, n: Int) -> Bool {
  string.byte_size(s) == n
  && list.all(string.to_graphemes(s), fn(c) {
    string.byte_size(c) == 1 && string.contains("0123456789abcdef", c)
  })
}

fn time(n: Int) -> Bool {
  n >= -9_000_000_000_000 && n <= 9_000_000_000_000
}

fn binding(b: policy.Binding) -> Bool {
  hex(b.candidate, 40) && hex(b.config, 64) && identifier(b.session, 256)
}

fn optional_bool(b: Option(Bool)) -> json.Json {
  case b {
    None -> json.null()
    Some(v) -> json.bool(v)
  }
}

fn binding_json(b: policy.Binding) -> json.Json {
  ordered([
    #("candidate", json.string(b.candidate)),
    #("config_digest", json.string(b.config)),
    #("session", json.string(b.session)),
  ])
}

fn dimension_json(d: policy.ServiceDimension) -> json.Json {
  ordered([
    #("observed_mono_ms", json.int(d.observed_ms)),
    #("passed", json.bool(d.passed)),
  ])
}

fn coverage_json(c: Option(policy.CoverageEvidence)) -> json.Json {
  case c {
    None -> json.null()
    Some(c) ->
      ordered([
        #("agent", json.string(agent(c.agent))),
        #("binding", binding_json(c.binding)),
        #(
          "services",
          json.array(
            list.sort(c.services, fn(a, b) {
              string.compare(a.service_id, b.service_id)
            }),
            fn(s) {
              ordered([
                #("agent", json.string(agent(s.agent))),
                #("binding", binding_json(s.binding)),
                #("function", dimension_json(s.function)),
                #("operation", dimension_json(s.operation)),
                #("performance", dimension_json(s.performance)),
                #("service_id", json.string(s.service_id)),
              ])
            },
          ),
        ),
      ])
  }
}

fn valid_coverage(
  r: policy.Request,
  o: policy.Observation,
  c: Option(policy.CoverageEvidence),
) -> Bool {
  case r.probe, c {
    _, None -> True
    policy.CoverageProbe, Some(c) ->
      c.agent == r.agent
      && c.binding == r.binding
      && c.services != []
      && list.length(list.take(c.services, 257)) <= 256
      && list.all(c.services, fn(s) {
        s.agent == r.agent
        && s.binding == r.binding
        && identifier(s.service_id, 128)
        && list.count(c.services, fn(other) { other.service_id == s.service_id })
        == 1
        && list.all([s.function, s.performance, s.operation], fn(d) {
          time(d.observed_ms) && d.observed_ms <= o.observed_ms
        })
      })
    _, _ -> False
  }
}

fn has_false(r: policy.Results, c: Option(policy.CoverageEvidence)) -> Bool {
  r.function == Some(False)
  || r.performance == Some(False)
  || r.operation == Some(False)
  || case c {
    None -> False
    Some(c) ->
      list.any(c.services, fn(s) {
        !s.function.passed || !s.performance.passed || !s.operation.passed
      })
  }
}

fn reason(r: policy.Reason) -> String {
  case r {
    policy.ProbeFailed -> "probe_failed"
    policy.ProbeUnavailable -> "unavailable"
    policy.TimedOut -> "timed_out"
    policy.MissingDimension -> "missing_dimension"
  }
}

pub fn prepare(
  c: Context,
  r: policy.Request,
  o: policy.Observation,
  coverage: Option(policy.CoverageEvidence),
) -> Result(Intent, Error) {
  use _ <- result.try(
    case
      identifier(c.receipt_id, 256)
      && identifier(c.operation_id, 256)
      && identifier(c.owner_id, 256)
      && identifier(c.clock_domain, 256)
      && c.owner_epoch >= 0
      && c.owner_epoch <= 9_000_000_000_000
      && c.observed_utc_us > 0
      && c.observed_utc_us <= 9_000_000_000_000_000
      && time(c.expires_mono_ms)
      && binding(r.binding)
    {
      True -> Ok(Nil)
      False -> Error(InvalidContext)
    },
  )
  use _ <- result.try(
    case
      r.seq > 0
      && r.seq <= 9_000_000_000_000
      && r.seq == o.seq
      && r.binding == o.binding
      && time(r.started_ms)
      && time(o.observed_ms)
      && o.observed_ms >= r.started_ms
      && o.elapsed_ms == o.observed_ms - r.started_ms
      && c.expires_mono_ms >= r.started_ms
    {
      True -> Ok(Nil)
      False -> Error(InvalidObservation)
    },
  )
  use _ <- result.try(case valid_coverage(r, o, coverage) {
    True -> Ok(Nil)
    False -> Error(InvalidCoverage)
  })
  let failed = has_false(o.results, coverage)
  let expired = o.observed_ms > c.expires_mono_ms
  let status = case failed || expired {
    True -> "stop"
    False -> "unknown"
  }
  let why = case expired, failed, o.results {
    True, _, _ -> "stale"
    _, True, _ -> reason(o.reason)
    _, _, policy.Results(Some(True), Some(True), Some(True)) -> "none"
    _, _, _ -> "missing_dimension"
  }
  let payload =
    ordered([
      #("agent", json.string(agent(r.agent))),
      #("candidate", json.string(r.binding.candidate)),
      #("clock_domain", json.string(c.clock_domain)),
      #("config_digest", json.string(r.binding.config)),
      #("coverage", coverage_json(coverage)),
      #("expires_mono_ms", json.int(c.expires_mono_ms)),
      #("observed_mono_ms", json.int(o.observed_ms)),
      #("observed_utc_us", json.int(c.observed_utc_us)),
      #("operation_id", json.string(c.operation_id)),
      #("owner_epoch", json.int(c.owner_epoch)),
      #("owner_id", json.string(c.owner_id)),
      #("probe", json.string(probe(r.probe))),
      #("reason", json.string(why)),
      #("receipt_id", json.string(c.receipt_id)),
      #(
        "results",
        ordered([
          #("function", optional_bool(o.results.function)),
          #("operation", optional_bool(o.results.operation)),
          #("performance", optional_bool(o.results.performance)),
        ]),
      ),
      #("sequence", json.int(r.seq)),
      #("service_id", json.string(service(r.probe))),
      #("session", json.string(r.binding.session)),
      #("started_mono_ms", json.int(r.started_ms)),
      #("status", json.string(status)),
    ])
    |> json.to_string
  let intent =
    Intent(c, r.seq, payload, files.digest(payload), Prepared, None, NotStarted)
  case string.byte_size(append_request(intent)) <= max_request_bytes {
    True -> Ok(intent)
    False -> Error(RequestBound)
  }
}

pub fn phase(i: Intent) -> Phase {
  i.phase
}

pub fn receipt_id(i: Intent) -> String {
  i.context.receipt_id
}

pub fn payload_sha256(i: Intent) -> String {
  i.sha256
}

pub fn bound_sequence(i: Intent) -> Int {
  i.sequence
}

pub fn canonical_receipt(i: Intent) -> String {
  i.canonical_receipt
}

pub fn acknowledgement(i: Intent) -> Option(Acknowledgement) {
  i.ack
}

pub fn cleanup(i: Intent) -> Cleanup {
  i.cleanup
}

// Embed only the internally constructed canonical object; no caller JSON is accepted.
fn append_request(i: Intent) -> String {
  "{\"operation\":\"append\",\"receipt\":"
  <> i.canonical_receipt
  <> ",\"schema_version\":1}"
}

fn get_request(i: Intent) -> String {
  ordered([
    #("operation", json.string("get")),
    #("receipt_id", json.string(i.context.receipt_id)),
    #("schema_version", json.int(1)),
  ])
  |> json.to_string
}

fn exact(v: Value, keys: List(String)) -> Result(List(#(String, Value)), Nil) {
  case v {
    JsonObject(fields) ->
      case
        list.length(fields) == list.length(keys)
        && list.all(keys, fn(k) { list.count(fields, fn(f) { f.0 == k }) == 1 })
      {
        True -> Ok(fields)
        False -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn field(fields: List(#(String, Value)), key: String) -> Value {
  let assert Ok(v) = list.key_find(fields, key)
  v
}

fn parse(raw: String) -> Result(Value, Nil) {
  case
    string.byte_size(raw) > 0 && string.byte_size(raw) <= max_response_bytes
  {
    True -> parse_strict(raw) |> result.replace_error(Nil)
    False -> Error(Nil)
  }
}

fn canonical(v: Value) -> Result(json.Json, Nil) {
  case v {
    JsonObject(fields) -> {
      use fields <- result.try(
        list.try_map(fields, fn(f) {
          use value <- result.try(canonical(f.1))
          Ok(#(f.0, value))
        }),
      )
      Ok(ordered(fields))
    }
    JsonArray(xs) -> {
      use xs <- result.try(list.try_map(xs, canonical))
      Ok(json.array(xs, fn(v) { v }))
    }
    JsonString(s) -> Ok(json.string(s))
    JsonInt(n)
      if n >= -9_223_372_036_854_775_808 && n <= 9_223_372_036_854_775_807
    -> Ok(json.int(n))
    JsonBool(b) -> Ok(json.bool(b))
    JsonNull -> Ok(json.null())
    JsonFloat(_) -> Error(Nil)
    _ -> Error(Nil)
  }
}

fn base(fields: List(#(String, Value))) -> Bool {
  field(fields, "schema_version") == JsonInt(1)
  && field(fields, "authority") == JsonString("NONE")
  && field(fields, "admitted") == JsonBool(False)
}

fn native_code(s: String) -> Option(NativeCode) {
  case s {
    "invalid_json" -> Some(InvalidJson)
    "invalid_receipt" -> Some(InvalidReceipt)
    "invalid_request" -> Some(InvalidRequest)
    "invalid_local_path" -> Some(InvalidPath)
    "schema_mismatch" -> Some(SchemaMismatch)
    "nested_transaction" -> Some(NestedTransaction)
    "store_unavailable" -> Some(StoreUnavailable)
    "resource_bound" -> Some(ResourceBound)
    "conflicting_replay" -> Some(Conflict)
    "stale_epoch" -> Some(StaleEpoch)
    "out_of_order" -> Some(OutOfOrder)
    "commit_unknown" -> Some(CommitUnknown)
    "rollback_failed" -> Some(RollbackFailed)
    "closed" -> Some(Closed)
    _ -> None
  }
}

fn held(v: Value) -> Option(NativeCode) {
  case
    exact(v, ["schema_version", "authority", "admitted", "status", "reason"])
  {
    Ok(f) ->
      case base(f) && field(f, "status") == JsonString("hold") {
        True ->
          case field(f, "reason") {
            JsonString(s) -> native_code(s)
            _ -> None
          }
        False -> None
      }
    _ -> None
  }
}

fn ack(i: Intent, record: Value) -> Result(Acknowledgement, Nil) {
  case record {
    JsonInt(n) if n > 0 && n <= 100_000 ->
      Ok(Acknowledgement(n, i.context.receipt_id, i.sha256, i.sequence))
    _ -> Error(Nil)
  }
}

fn decode_append(
  i: Intent,
  v: Value,
) -> Result(#(Acknowledgement, Outcome), Nil) {
  use f <- result.try(
    exact(v, [
      "schema_version",
      "authority",
      "admitted",
      "status",
      "record_index",
      "receipt_id",
      "payload_sha256",
    ]),
  )
  case
    base(f)
    && field(f, "receipt_id") == JsonString(i.context.receipt_id)
    && field(f, "payload_sha256") == JsonString(i.sha256)
  {
    False -> Error(Nil)
    True -> {
      use a <- result.try(ack(i, field(f, "record_index")))
      case field(f, "status") {
        JsonString("stored") -> Ok(#(a, Stored))
        JsonString("replayed") -> Ok(#(a, Replayed))
        _ -> Error(Nil)
      }
    }
  }
}

fn decode_found(i: Intent, v: Value) -> Result(Acknowledgement, Nil) {
  use f <- result.try(
    exact(v, ["schema_version", "authority", "admitted", "status", "stored"]),
  )
  use _ <- result.try(
    case base(f) && field(f, "status") == JsonString("found") {
      True -> Ok(Nil)
      False -> Error(Nil)
    },
  )
  use s <- result.try(
    exact(field(f, "stored"), [
      "record_index",
      "receipt_id",
      "payload_sha256",
      "receipt",
    ]),
  )
  use payload <- result.try(canonical(field(s, "receipt")))
  let payload = json.to_string(payload)
  case
    field(s, "receipt_id") == JsonString(i.context.receipt_id)
    && field(s, "payload_sha256") == JsonString(i.sha256)
    && payload == i.canonical_receipt
    && files.digest(payload) == i.sha256
  {
    True -> ack(i, field(s, "record_index"))
    False -> Error(Nil)
  }
}

fn uncertain(i: Intent, o: Outcome) -> Transition {
  Transition(Intent(..i, phase: NeedsReconciliation, ack: None), o)
}

fn accepted(i: Intent, a: Acknowledgement, o: Outcome) -> Transition {
  Transition(Intent(..i, phase: Acknowledged, ack: Some(a)), o)
}

pub fn submit_with(i: Intent, exchange: fn(String) -> Exchange) -> Transition {
  case i.phase {
    Prepared -> {
      let observed = exchange(append_request(i))
      case cleanup_confirmed(observed) {
        False -> reaping_unconfirmed(i)
        True -> {
          let i = Intent(..i, cleanup: observed.cleanup)
          case observed.result {
            Error(_) -> uncertain(i, UnknownOutcome)
            Ok(raw) ->
              case parse(raw) {
                Error(_) -> uncertain(i, ProtocolUncertain)
                Ok(v) ->
                  case decode_append(i, v) {
                    Ok(#(a, o)) -> accepted(i, a, o)
                    Error(_) ->
                      case held(v) {
                        Some(code) -> uncertain(i, NativeHold(code))
                        None -> uncertain(i, ProtocolUncertain)
                      }
                  }
              }
          }
        }
      }
    }
    _ -> Transition(i, SubmitBlocked)
  }
}

pub fn submit(config: transport.LocalConfiguration, i: Intent) -> Transition {
  submit_with(i, fn(body) { native_exchange(config, body) })
}

pub fn reconcile_with(
  i: Intent,
  exchange: fn(String) -> Exchange,
) -> Transition {
  case i.phase {
    NeedsReconciliation -> {
      let observed = exchange(get_request(i))
      case cleanup_confirmed(observed) {
        False -> reaping_unconfirmed(i)
        True -> {
          let i = Intent(..i, cleanup: observed.cleanup)
          case observed.result {
            Error(_) -> uncertain(i, UnknownOutcome)
            Ok(raw) ->
              case parse(raw) {
                Error(_) -> uncertain(i, ProtocolUncertain)
                Ok(v) ->
                  case decode_found(i, v) {
                    Ok(a) -> accepted(i, a, Reconciled)
                    Error(_) ->
                      case held(v) {
                        Some(code) -> uncertain(i, NativeHold(code))
                        None ->
                          case
                            exact(v, [
                              "schema_version",
                              "authority",
                              "admitted",
                              "status",
                            ])
                          {
                            Ok(f) ->
                              case
                                base(f)
                                && field(f, "status") == JsonString("absent")
                              {
                                True -> uncertain(i, UnknownOutcome)
                                False -> uncertain(i, ProtocolUncertain)
                              }
                            _ -> uncertain(i, ProtocolUncertain)
                          }
                      }
                  }
              }
          }
        }
      }
    }
    _ -> Transition(i, SubmitBlocked)
  }
}

pub fn reconcile(
  config: transport.LocalConfiguration,
  i: Intent,
) -> Transition {
  reconcile_with(i, fn(body) { native_exchange(config, body) })
}
