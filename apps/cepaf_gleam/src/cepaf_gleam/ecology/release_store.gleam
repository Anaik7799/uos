//// Native ledger facts, never release authority or a deployment permission.
//// One genuine Gleam owner must retain Client. Immutable aliases are not linear
//// capabilities. Unknown consume ACKs cannot be resent or promoted by lookup.
//// Every production exchange uses the SAME framed invocation/cleanup witness.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_store_transport as transport
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const max_request_bytes = 8192

pub const max_response_bytes = 65_536

pub type Binding {
  Binding(
    grant_id: String,
    intent_digest: String,
    approval_digest: String,
    owner_binding_digest: String,
    expires_utc_ms: Int,
  )
}

pub type Command {
  Stage
  FenceReaders
  Replace(index: Int)
  VerifyCandidate
  Restore(index: Int)
  VerifyPrevious
  ResumeReaders
}

pub type RevokeReason {
  OperatorRevoked
  OwnerChanged
  CandidateChanged
  EvidenceStale
  RevokeExpired
  Cancelled
  Containment
}

pub type Request {
  Issue(request_id: String)
  Consume(
    request_id: String,
    step_digest: String,
    epoch: Int,
    generation: Int,
    command: Command,
  )
  Revoke(request_id: String, reason: RevokeReason)
  Lookup(step_digest: Option(String))
}

pub type RequestError {
  InvalidBinding
  InvalidRequest
  InvalidDigest
}

pub type Phase {
  Ready
  NeedsReconciliation
  UnconfirmedCleanup
}

pub opaque type Client {
  Client(
    config: transport.LocalConfiguration,
    binding: Binding,
    phase: Phase,
    pending: Option(Request),
    cleanup: Cleanup,
  )
}

pub type EventIdentity {
  EventIdentity(request_id: String, request_digest: String, event_index: Int)
}

pub type RevocationFact {
  RevocationFact(reason: RevokeReason, utc_ms: Int, event: EventIdentity)
}

pub type GrantFact {
  GrantFact(
    binding: Binding,
    issued_utc_ms: Int,
    issue: EventIdentity,
    revocation: Option(RevocationFact),
    expired: Bool,
  )
}

pub type StepFact {
  StepFact(
    event: EventIdentity,
    step_digest: String,
    epoch: Int,
    generation: Int,
    command: Command,
    consumed_utc_ms: Int,
  )
}

pub type NativeCode {
  InvalidJson
  InvalidNativeRequest
  InvalidLocalPath
  SchemaMismatch
  NestedTransaction
  StoreUnavailable
  ResourceBound
  ConflictingReplay
  MissingGrant
  RevokedGrant
  ExpiredGrant
  InvalidClock
  ClockRollback
  CommitUnknown
  RollbackFailed
  Closed
}

/// Fresh means a new ledger row with an exact current-request ACK. It never
/// means a fresh deployment permission. Expired/revoked facts remain facts.
pub type FactResult {
  Issued(grant: GrantFact, observed_utc_ms: Int)
  IssueReplayed(grant: GrantFact, observed_utc_ms: Int)
  Consumed(grant: GrantFact, step: StepFact, observed_utc_ms: Int)
  AlreadyConsumed(grant: GrantFact, step: StepFact, observed_utc_ms: Int)
  Revoked(grant: GrantFact, observed_utc_ms: Int)
  AlreadyRevoked(grant: GrantFact, observed_utc_ms: Int)
  Found(grant: GrantFact, step: Option(StepFact), observed_utc_ms: Int)
  Absent(observed_utc_ms: Int)
  Held(code: NativeCode)
  NativeUnknown(code: NativeCode)
  ProtocolUncertain
  TransportUncertain
  CleanupFenced
  RequestBlocked
  RequestInvalid(error: RequestError)
}

pub type Transition {
  Transition(client: Client, result: FactResult)
}

pub type Cleanup {
  NotStarted
  Reaped(exit_code: Int, observed_utc_us: Int)
  Unconfirmed
}

/// Trusted TEST/adapter injection only; the pair must describe one invocation.
/// External JSON cannot supply this witness. request() uses the native FFI pair.
pub type Exchange {
  Exchange(result: Result(String, transport.TransportError), cleanup: Cleanup)
}

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

fn identifier(value: String) -> Bool {
  string.byte_size(value) > 0
  && string.byte_size(value) <= 128
  && list.all(string.to_graphemes(value), fn(c) {
    string.byte_size(c) == 1
    && string.contains(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.:/-",
      c,
    )
  })
}

fn hex64(value: String) -> Bool {
  string.byte_size(value) == 64
  && list.all(string.to_graphemes(value), fn(c) {
    string.byte_size(c) == 1 && string.contains("0123456789abcdef", c)
  })
}

fn digest(value: String) -> Bool {
  string.starts_with(value, "sha256:") && hex64(string.drop_start(value, 7))
}

/// Intent.digest is bare hex; native wire digests are explicitly tagged.
/// Uppercase, wrong algorithms and malformed tags are refused, not normalized.
pub fn tag_digest(value: String) -> Result(String, RequestError) {
  case hex64(value), digest(value) {
    True, _ -> Ok("sha256:" <> value)
    _, True -> Ok(value)
    _, _ -> Error(InvalidDigest)
  }
}

fn utc(value: Int) -> Bool {
  value > 0 && value <= 8_000_000_000_000
}

fn bounded(value: Int) -> Bool {
  value >= 0 && value <= 9_000_000_000_000
}

fn valid_binding(binding: Binding) -> Bool {
  identifier(binding.grant_id)
  && digest(binding.intent_digest)
  && digest(binding.approval_digest)
  && digest(binding.owner_binding_digest)
  && utc(binding.expires_utc_ms)
}

pub fn new_client(
  config: transport.LocalConfiguration,
  binding: Binding,
) -> Result(Client, RequestError) {
  case valid_binding(binding) {
    True -> Ok(Client(config, binding, Ready, None, NotStarted))
    False -> Error(InvalidBinding)
  }
}

pub fn phase(client: Client) -> Phase {
  client.phase
}

pub fn binding(client: Client) -> Binding {
  client.binding
}

pub fn cleanup(client: Client) -> Cleanup {
  client.cleanup
}

fn command_text(command: Command) -> String {
  case command {
    Stage -> "stage"
    FenceReaders -> "fence_readers"
    Replace(i) -> "replace:" <> int.to_string(i)
    VerifyCandidate -> "verify_candidate"
    Restore(i) -> "restore:" <> int.to_string(i)
    VerifyPrevious -> "verify_previous"
    ResumeReaders -> "resume_readers"
  }
}

fn valid_command(command: Command) -> Bool {
  case command {
    Replace(i) | Restore(i) -> i >= 0 && i <= 14
    _ -> True
  }
}

fn reason_text(reason: RevokeReason) -> String {
  case reason {
    OperatorRevoked -> "operator_revoked"
    OwnerChanged -> "owner_changed"
    CandidateChanged -> "candidate_changed"
    EvidenceStale -> "evidence_stale"
    RevokeExpired -> "expired"
    Cancelled -> "cancelled"
    Containment -> "containment"
  }
}

fn valid_request(request: Request) -> Bool {
  case request {
    Issue(id) | Revoke(id, _) -> identifier(id)
    Consume(id, step, epoch, generation, command) ->
      identifier(id)
      && digest(step)
      && epoch > 0
      && bounded(epoch)
      && bounded(generation)
      && valid_command(command)
    Lookup(None) -> True
    Lookup(Some(step)) -> digest(step)
  }
}

fn ordered(fields: List(#(String, json.Json))) -> json.Json {
  json.object(list.sort(fields, fn(a, b) { string.compare(a.0, b.0) }))
}

pub fn canonical_request(
  binding: Binding,
  request: Request,
) -> Result(String, RequestError) {
  case valid_binding(binding), valid_request(request) {
    False, _ -> Error(InvalidBinding)
    _, False -> Error(InvalidRequest)
    True, True -> {
      let common = [
        #("schema_version", json.int(1)),
        #("grant_id", json.string(binding.grant_id)),
      ]
      let fields = case request {
        Issue(id) -> [
          #("operation", json.string("issue")),
          #("request_id", json.string(id)),
          #("intent_digest", json.string(binding.intent_digest)),
          #("approval_digest", json.string(binding.approval_digest)),
          #("owner_binding_digest", json.string(binding.owner_binding_digest)),
          #("expires_utc_ms", json.int(binding.expires_utc_ms)),
        ]
        Consume(id, step, epoch, generation, command) -> [
          #("operation", json.string("consume")),
          #("request_id", json.string(id)),
          #("step_digest", json.string(step)),
          #("epoch", json.int(epoch)),
          #("generation", json.int(generation)),
          #("command", json.string(command_text(command))),
        ]
        Revoke(id, reason) -> [
          #("operation", json.string("revoke")),
          #("request_id", json.string(id)),
          #("reason", json.string(reason_text(reason))),
        ]
        Lookup(step) -> [
          #("operation", json.string("lookup")),
          #("step_digest", case step {
            None -> json.null()
            Some(step) -> json.string(step)
          }),
        ]
      }
      let body = ordered(list.append(common, fields)) |> json.to_string
      case string.byte_size(body) <= max_request_bytes {
        True -> Ok(body)
        False -> Error(InvalidRequest)
      }
    }
  }
}

pub fn request_digest(
  binding: Binding,
  request: Request,
) -> Result(String, RequestError) {
  canonical_request(binding, request)
  |> result.map(fn(body) { "sha256:" <> files.digest(body) })
}

pub fn pending_lookup(client: Client) -> Option(Request) {
  case client.pending {
    None -> None
    Some(Consume(_, step, _, _, _)) -> Some(Lookup(Some(step)))
    Some(Lookup(step)) -> Some(Lookup(step))
    Some(_) -> Some(Lookup(None))
  }
}

fn exact(
  value: Value,
  keys: List(String),
) -> Result(List(#(String, Value)), Nil) {
  case value {
    JsonObject(fields) ->
      case
        list.length(fields) == list.length(keys)
        && list.all(keys, fn(k) { list.count(fields, fn(f) { f.0 == k }) == 1 })
      {
        True -> Ok(fields)
        False -> Error(Nil)
      }
    JsonArray(_) | JsonFloat(_) -> Error(Nil)
    _ -> Error(Nil)
  }
}

fn field(fields: List(#(String, Value)), key: String) -> Value {
  case list.key_find(fields, key) {
    Ok(value) -> value
    Error(_) -> JsonNull
  }
}

fn text(value: Value) -> Result(String, Nil) {
  case value {
    JsonString(value) -> Ok(value)
    _ -> Error(Nil)
  }
}

fn integer(value: Value) -> Result(Int, Nil) {
  case value {
    JsonInt(value) -> Ok(value)
    _ -> Error(Nil)
  }
}

fn check(condition: Bool) -> Result(Nil, Nil) {
  case condition {
    True -> Ok(Nil)
    False -> Error(Nil)
  }
}

fn decode_reason(value: String) -> Result(RevokeReason, Nil) {
  case value {
    "operator_revoked" -> Ok(OperatorRevoked)
    "owner_changed" -> Ok(OwnerChanged)
    "candidate_changed" -> Ok(CandidateChanged)
    "evidence_stale" -> Ok(EvidenceStale)
    "expired" -> Ok(RevokeExpired)
    "cancelled" -> Ok(Cancelled)
    "containment" -> Ok(Containment)
    _ -> Error(Nil)
  }
}

fn decode_command(value: String) -> Result(Command, Nil) {
  case value {
    "stage" -> Ok(Stage)
    "fence_readers" -> Ok(FenceReaders)
    "verify_candidate" -> Ok(VerifyCandidate)
    "verify_previous" -> Ok(VerifyPrevious)
    "resume_readers" -> Ok(ResumeReaders)
    _ ->
      case string.split(value, ":") {
        [kind, index] -> {
          use index <- result.try(int.parse(index) |> result.replace_error(Nil))
          use command <- result.try(case kind {
            "replace" -> Ok(Replace(index))
            "restore" -> Ok(Restore(index))
            _ -> Error(Nil)
          })
          use _ <- result.try(check(
            valid_command(command) && command_text(command) == value,
          ))
          Ok(command)
        }
        _ -> Error(Nil)
      }
  }
}

fn identity(
  id: Value,
  digest_value: Value,
  event_index: Value,
) -> Result(EventIdentity, Nil) {
  use id <- result.try(text(id))
  use digest_value <- result.try(text(digest_value))
  use event_index <- result.try(integer(event_index))
  use _ <- result.try(check(
    identifier(id)
    && digest(digest_value)
    && event_index > 0
    && bounded(event_index),
  ))
  Ok(EventIdentity(id, digest_value, event_index))
}

fn request_matches(
  binding: Binding,
  request: Request,
  event: EventIdentity,
) -> Bool {
  request_digest(binding, request) == Ok(event.request_digest)
}

fn decode_grant(
  value: Value,
  binding: Binding,
  observed: Int,
) -> Result(GrantFact, Nil) {
  use fields <- result.try(
    exact(value, [
      "grant_id", "intent_digest", "approval_digest", "owner_binding_digest",
      "issued_utc_ms", "expires_utc_ms", "issue_request_id",
      "issue_request_digest", "issue_event_index", "revoked", "revoked_reason",
      "revoked_utc_ms", "revoke_request_id", "revoke_event_index", "expired",
    ]),
  )
  use issued <- result.try(integer(field(fields, "issued_utc_ms")))
  use event <- result.try(identity(
    field(fields, "issue_request_id"),
    field(fields, "issue_request_digest"),
    field(fields, "issue_event_index"),
  ))
  use _ <- result.try(check(
    field(fields, "grant_id") == JsonString(binding.grant_id)
    && field(fields, "intent_digest") == JsonString(binding.intent_digest)
    && field(fields, "approval_digest") == JsonString(binding.approval_digest)
    && field(fields, "owner_binding_digest")
    == JsonString(binding.owner_binding_digest)
    && field(fields, "expires_utc_ms") == JsonInt(binding.expires_utc_ms)
    && utc(issued)
    && issued <= observed
    && issued < binding.expires_utc_ms
    && binding.expires_utc_ms - issued <= 3_600_000
    && request_matches(binding, Issue(event.request_id), event)
    && field(fields, "expired") == JsonBool(observed >= binding.expires_utc_ms),
  ))
  use revocation <- result.try(case field(fields, "revoked") {
    JsonBool(False) -> {
      use _ <- result.try(
        check(
          list.all(
            [
              "revoked_reason", "revoked_utc_ms", "revoke_request_id",
              "revoke_event_index",
            ],
            fn(k) { field(fields, k) == JsonNull },
          ),
        ),
      )
      Ok(None)
    }
    JsonBool(True) -> {
      use reason <- result.try(text(field(fields, "revoked_reason")))
      use reason <- result.try(decode_reason(reason))
      use at <- result.try(integer(field(fields, "revoked_utc_ms")))
      use id <- result.try(text(field(fields, "revoke_request_id")))
      use index <- result.try(integer(field(fields, "revoke_event_index")))
      use _ <- result.try(check(
        utc(at)
        && at >= issued
        && at <= observed
        && identifier(id)
        && index > event.event_index
        && bounded(index),
      ))
      use hash <- result.try(
        request_digest(binding, Revoke(id, reason)) |> result.replace_error(Nil),
      )
      Ok(Some(RevocationFact(reason, at, EventIdentity(id, hash, index))))
    }
    _ -> Error(Nil)
  })
  Ok(GrantFact(
    binding,
    issued,
    event,
    revocation,
    observed >= binding.expires_utc_ms,
  ))
}

fn decode_step(
  value: Value,
  grant: GrantFact,
  observed: Int,
) -> Result(StepFact, Nil) {
  use fields <- result.try(
    exact(value, [
      "request_id", "request_digest", "event_index", "step_digest", "epoch",
      "generation", "command", "consumed_utc_ms",
    ]),
  )
  use event <- result.try(identity(
    field(fields, "request_id"),
    field(fields, "request_digest"),
    field(fields, "event_index"),
  ))
  use step <- result.try(text(field(fields, "step_digest")))
  use epoch <- result.try(integer(field(fields, "epoch")))
  use generation <- result.try(integer(field(fields, "generation")))
  use command <- result.try(text(field(fields, "command")))
  use command <- result.try(decode_command(command))
  use at <- result.try(integer(field(fields, "consumed_utc_ms")))
  use _ <- result.try(check(
    digest(step)
    && epoch > 0
    && bounded(epoch)
    && bounded(generation)
    && event.event_index > grant.issue.event_index
    && utc(at)
    && at >= grant.issued_utc_ms
    && at < grant.binding.expires_utc_ms
    && at <= observed
    && request_matches(
      grant.binding,
      Consume(event.request_id, step, epoch, generation, command),
      event,
    )
    && case grant.revocation {
      None -> True
      Some(revocation) ->
        at <= revocation.utc_ms
        && event.event_index < revocation.event.event_index
    },
  ))
  Ok(StepFact(event, step, epoch, generation, command, at))
}

fn decode_code(value: String) -> Result(NativeCode, Nil) {
  case value {
    "invalid_json" -> Ok(InvalidJson)
    "invalid_request" -> Ok(InvalidNativeRequest)
    "invalid_local_path" -> Ok(InvalidLocalPath)
    "schema_mismatch" -> Ok(SchemaMismatch)
    "nested_transaction" -> Ok(NestedTransaction)
    "store_unavailable" -> Ok(StoreUnavailable)
    "resource_bound" -> Ok(ResourceBound)
    "conflicting_replay" -> Ok(ConflictingReplay)
    "missing_grant" -> Ok(MissingGrant)
    "revoked" -> Ok(RevokedGrant)
    "expired" -> Ok(ExpiredGrant)
    "invalid_clock" -> Ok(InvalidClock)
    "clock_rollback" -> Ok(ClockRollback)
    "commit_unknown" -> Ok(CommitUnknown)
    "rollback_failed" -> Ok(RollbackFailed)
    "closed" -> Ok(Closed)
    _ -> Error(Nil)
  }
}

fn decode(
  raw: String,
  binding: Binding,
  request: Request,
) -> Result(FactResult, Nil) {
  use _ <- result.try(check(
    string.byte_size(raw) > 0 && string.byte_size(raw) <= max_response_bytes,
  ))
  use value <- result.try(parse_strict(raw) |> result.replace_error(Nil))
  use fields <- result.try(
    exact(value, [
      "schema_version", "authority", "authorized", "admitted",
      "new_effect_permission", "status", "request_id", "request_digest",
      "event_index", "observed_utc_ms", "grant", "step", "reason",
    ]),
  )
  use _ <- result.try(check(
    field(fields, "schema_version") == JsonInt(1)
    && field(fields, "authority") == JsonString("NONE")
    && field(fields, "authorized") == JsonBool(False)
    && field(fields, "admitted") == JsonBool(False)
    && field(fields, "new_effect_permission") == JsonBool(False),
  ))
  use status <- result.try(text(field(fields, "status")))
  case status {
    "hold" | "unknown" -> {
      use _ <- result.try(
        check(
          list.all(
            [
              "request_id", "request_digest", "event_index", "observed_utc_ms",
              "grant", "step",
            ],
            fn(k) { field(fields, k) == JsonNull },
          ),
        ),
      )
      use code <- result.try(text(field(fields, "reason")))
      use code <- result.try(decode_code(code))
      case status, code {
        "unknown", CommitUnknown | "unknown", RollbackFailed ->
          Ok(NativeUnknown(code))
        "hold", CommitUnknown | "hold", RollbackFailed -> Error(Nil)
        "hold", _ -> Ok(Held(code))
        _, _ -> Error(Nil)
      }
    }
    _ -> {
      use _ <- result.try(check(field(fields, "reason") == JsonNull))
      use observed <- result.try(integer(field(fields, "observed_utc_ms")))
      use _ <- result.try(check(utc(observed)))
      case request, status {
        Lookup(step), "found" | Lookup(step), "absent" -> {
          use _ <- result.try(
            check(
              list.all(["request_id", "request_digest", "event_index"], fn(k) {
                field(fields, k) == JsonNull
              }),
            ),
          )
          case status {
            "absent" -> {
              use _ <- result.try(check(
                field(fields, "grant") == JsonNull
                && field(fields, "step") == JsonNull,
              ))
              Ok(Absent(observed))
            }
            _ -> {
              use grant <- result.try(decode_grant(
                field(fields, "grant"),
                binding,
                observed,
              ))
              use found_step <- result.try(case field(fields, "step") {
                JsonNull -> Ok(None)
                value -> decode_step(value, grant, observed) |> result.map(Some)
              })
              use _ <- result.try(
                check(case step, found_step {
                  None, None | Some(_), None -> True
                  Some(expected), Some(actual) -> expected == actual.step_digest
                  _, _ -> False
                }),
              )
              Ok(Found(grant, found_step, observed))
            }
          }
        }
        _, _ -> {
          use event <- result.try(identity(
            field(fields, "request_id"),
            field(fields, "request_digest"),
            field(fields, "event_index"),
          ))
          use grant <- result.try(decode_grant(
            field(fields, "grant"),
            binding,
            observed,
          ))
          case request, status {
            Issue(id), "issued" | Issue(id), "issue_replayed" -> {
              use _ <- result.try(check(
                field(fields, "step") == JsonNull
                && event == grant.issue
                && event.request_id == id,
              ))
              case status {
                "issued" -> Ok(Issued(grant, observed))
                _ -> Ok(IssueReplayed(grant, observed))
              }
            }
            Consume(id, step, epoch, generation, command), "consumed"
            | Consume(id, step, epoch, generation, command), "already_consumed"
            -> {
              use actual <- result.try(decode_step(
                field(fields, "step"),
                grant,
                observed,
              ))
              use _ <- result.try(check(
                actual.event == event
                && actual.step_digest == step
                && actual.epoch == epoch
                && actual.generation == generation
                && actual.command == command
                && { status != "consumed" || event.request_id == id },
              ))
              case status {
                "consumed" -> Ok(Consumed(grant, actual, observed))
                _ -> Ok(AlreadyConsumed(grant, actual, observed))
              }
            }
            Revoke(id, reason), "revoked"
            | Revoke(id, reason), "already_revoked"
            -> {
              use revocation <- result.try(case grant.revocation {
                None -> Error(Nil)
                Some(revocation) -> Ok(revocation)
              })
              use _ <- result.try(check(
                field(fields, "step") == JsonNull
                && event == revocation.event
                && {
                  status != "revoked"
                  || { event.request_id == id && revocation.reason == reason }
                },
              ))
              case status {
                "revoked" -> Ok(Revoked(grant, observed))
                _ -> Ok(AlreadyRevoked(grant, observed))
              }
            }
            _, _ -> Error(Nil)
          }
        }
      }
    }
  }
}

fn native_exchange(
  config: transport.LocalConfiguration,
  body: String,
) -> Exchange {
  let #(response, witness) = request_with_cleanup(config, body)
  Exchange(
    response
      |> result.map_error(fn(code) {
        case code {
          "transport_input_bound" -> transport.InputBound
          "transport_configuration_or_spawn" -> transport.ConfigurationOrSpawn
          "transport_cleanup_unknown" -> transport.CleanupUnknown
          _ -> transport.Uncertain
        }
      }),
    case witness {
      Some(#(code, at)) -> Reaped(code, at)
      None -> Unconfirmed
    },
  )
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

/// Only the matching read-only lookup is allowed after an uncertain invocation.
/// Successful lookup retains NeedsReconciliation and never rearms mutations.
pub fn request_with(
  client: Client,
  request: Request,
  exchange: fn(String) -> Exchange,
) -> Transition {
  let allowed = case client.phase {
    Ready -> True
    NeedsReconciliation -> pending_lookup(client) == Some(request)
    UnconfirmedCleanup -> False
  }
  case allowed {
    False -> Transition(client, RequestBlocked)
    True ->
      case canonical_request(client.binding, request) {
        Error(error) -> Transition(client, RequestInvalid(error))
        Ok(body) -> {
          let observed = exchange(body)
          case cleanup_confirmed(observed) {
            False ->
              Transition(
                Client(
                  ..client,
                  phase: UnconfirmedCleanup,
                  pending: Some(request),
                  cleanup: Unconfirmed,
                ),
                CleanupFenced,
              )
            True -> {
              let client = Client(..client, cleanup: observed.cleanup)
              let uncertain =
                Client(
                  ..client,
                  phase: NeedsReconciliation,
                  pending: Some(request),
                )
              case observed.result {
                Error(_) -> Transition(uncertain, TransportUncertain)
                Ok(raw) ->
                  case decode(raw, client.binding, request) {
                    Error(_) -> Transition(uncertain, ProtocolUncertain)
                    Ok(NativeUnknown(_) as outcome) ->
                      Transition(uncertain, outcome)
                    Ok(outcome) -> Transition(client, outcome)
                  }
              }
            }
          }
        }
      }
  }
}

pub fn request(client: Client, request: Request) -> Transition {
  request_with(client, request, fn(body) {
    native_exchange(client.config, body)
  })
}
