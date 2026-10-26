//// Unique durable reservation of one /verify job per Telegram inbox request.
//// The reservation file is named by the digest of the inbox identity and is
//// created exclusively and fsynced, so a second request for the same inbox
//// message can never mint a second job. Replaying the identical binding
//// returns the stored one; any other binding for that request is a conflict.
//// Recovery reloads the reservation instead of re-resolving a profile.
//// A reservation is not a lease, a job or an authorization.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_verify_contract as v
import gleam/dynamic/decode
import gleam/json
import gleam/result

pub const schema = "uos.telegram.verify-reservation.v1"

pub type Reserved {
  /// This call created the reservation.
  Created(v.Binding)
  /// An identical reservation already existed (idempotent replay).
  Existing(v.Binding)
}

fn path(dir: String, request_id: String) -> String {
  dir <> "/" <> files.digest(request_id) <> ".json"
}

pub fn encode(b: v.Binding) -> String {
  json.object([
    #("schema", json.string(schema)),
    #("request_id", json.string(b.request_id)),
    #("job_id", json.string(b.job_id)),
    #("attempt", json.int(b.attempt)),
    #("profile_sha256", json.string(b.profile_sha256)),
    #("candidate", json.string(b.candidate)),
    #("source_closure_sha256", json.string(b.source_closure_sha256)),
  ])
  |> json.to_string
}

fn decoder() {
  use s <- decode.field("schema", decode.string)
  use request <- decode.field("request_id", decode.string)
  use job <- decode.field("job_id", decode.string)
  use attempt <- decode.field("attempt", decode.int)
  use digest <- decode.field("profile_sha256", decode.string)
  use candidate <- decode.field("candidate", decode.string)
  use closure <- decode.field("source_closure_sha256", decode.string)
  decode.success(#(
    s,
    v.Binding(request, job, attempt, digest, candidate, closure),
  ))
}

/// The binding must come from `telegram_verify_contract.binding` for the
/// loaded profile; this module persists it and does not re-derive it.
pub fn reserve(
  root: String,
  dir: String,
  b: v.Binding,
) -> Result(Reserved, String) {
  let content = encode(b)
  case files.create(root, path(dir, b.request_id), content) {
    Ok(Nil) -> Ok(Created(b))
    Error(created) ->
      case files.read(root, path(dir, b.request_id)) {
        Ok(existing) if existing == content -> Ok(Existing(b))
        Ok(_) -> Error("reservation_conflict")
        Error(_) -> Error("reservation_unavailable:" <> created)
      }
  }
}

/// Loads the stored binding for an inbox request; the stored bytes must be
/// this module's exact encoding of a binding for that request.
pub fn load(
  root: String,
  dir: String,
  request_id: String,
) -> Result(v.Binding, String) {
  use raw <- result.try(
    files.read(root, path(dir, request_id))
    |> result.map_error(fn(r) { "reservation_unavailable:" <> r }),
  )
  use b <- result.try(decode(raw))
  case b.request_id == request_id {
    True -> Ok(b)
    False -> Error("reservation_not_canonical")
  }
}

/// Strict decode of this module's exact encoding; any other byte string for
/// the same binding is refused.
pub fn decode(raw: String) -> Result(v.Binding, String) {
  use #(s, b) <- result.try(
    json.parse(raw, decoder())
    |> result.map_error(fn(_) { "reservation_malformed" }),
  )
  case s == schema && encode(b) == raw {
    True -> Ok(b)
    False -> Error("reservation_not_canonical")
  }
}
