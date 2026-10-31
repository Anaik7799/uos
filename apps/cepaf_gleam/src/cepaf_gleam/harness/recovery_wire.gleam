//// Pure factual adapter to existing native Store v1 request bytes. NO authority,
//// clock observation, capability, storage, process or effect interface.
//// Standalone closed input avoids an import of the unmerged recovery_model.
//// Candidate identifiers may allow colon, but native v1 does not: REFUSE it.
//// Native v1 does NOT bind proposal/review/portfolio/capability. A future native
//// effect path needs a separately reviewed authenticated envelope. Clock values
//// here are supplied data. Candidate digest and native request digest differ.

import cepaf_gleam/harness/value
import cepaf_gleam/mcp/json_guard
import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub opaque type FactualRequest {
  FactualRequest(bytes: String, digest: String)
}

pub type WireError {
  InvalidInput
}

type Member {
  Member(
    task: String,
    worker: String,
    attempt: Int,
    lease: String,
    duration: Int,
  )
}

fn ensure(ok: Bool) -> Result(Nil, WireError) {
  case ok {
    True -> Ok(Nil)
    False -> Error(InvalidInput)
  }
}

fn token(s: String) -> Bool {
  string.byte_size(s) > 0
  && string.byte_size(s) <= 160
  && list.all(string.to_graphemes(s), fn(c) {
    string.byte_size(c) == 1
    && string.contains(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./",
      c,
    )
  })
}

fn object(
  v: value.Value,
  keys: List(String),
) -> Result(value.Value, WireError) {
  case v {
    value.Object(fields) -> {
      use _ <- result.try(ensure(
        list.sort(list.map(fields, fn(p) { p.0 }), string.compare)
        == list.sort(keys, string.compare),
      ))
      Ok(v)
    }
    _ -> Error(InvalidInput)
  }
}

fn field(v: value.Value, key: String) -> Result(value.Value, WireError) {
  value.get(v, key) |> result.map_error(fn(_) { InvalidInput })
}

fn text(v: value.Value, key: String) -> Result(String, WireError) {
  use x <- result.try(field(v, key))
  case x {
    value.Text(s) -> Ok(s)
    _ -> Error(InvalidInput)
  }
}

fn integer(v: value.Value, key: String) -> Result(Int, WireError) {
  use x <- result.try(field(v, key))
  case x {
    value.Integer(n) -> Ok(n)
    _ -> Error(InvalidInput)
  }
}

fn member(v: value.Value) -> Result(Member, WireError) {
  use v <- result.try(
    object(v, ["task_id", "worker", "old_attempt", "old_lease_ns", "lease_ms"]),
  )
  use task <- result.try(text(v, "task_id"))
  use worker <- result.try(text(v, "worker"))
  use attempt <- result.try(integer(v, "old_attempt"))
  use lease <- result.try(text(v, "old_lease_ns"))
  use duration <- result.try(integer(v, "lease_ms"))
  use _ <- result.try(ensure(
    token(task)
    && token(worker)
    && attempt > 0
    && attempt < 1_000_000
    && duration > 0
    && duration <= 3_600_000
    && string.byte_size(lease) <= 19,
  ))
  use n <- result.try(
    int.parse(lease) |> result.map_error(fn(_) { InvalidInput }),
  )
  use _ <- result.try(ensure(
    n > 0 && n <= 9_223_372_036_854_775_807 && int.to_string(n) == lease,
  ))
  Ok(Member(task, worker, attempt, lease, duration))
}

fn member_json(m: Member) -> json.Json {
  json.object([
    #("task", json.string(m.task)),
    #("worker", json.string(m.worker)),
    #("attempt", json.int(m.attempt)),
    #("lease", json.string(m.lease)),
  ])
}

/// Decode plain factual input. Nanoseconds remain canonical decimal STRINGS;
/// exact integer milliseconds are converted only after checked Int64 bounds.
/// Each of three members supplies duration; unequal values are rejected.
pub fn decode(raw: String) -> Result(FactualRequest, WireError) {
  use _ <- result.try(ensure(
    string.byte_size(raw) > 0 && string.byte_size(raw) <= 32_768,
  ))
  use v <- result.try(
    json_guard.native_inspect(raw, 8)
    |> result.map_error(fn(_) { InvalidInput }),
  )
  use v <- result.try(
    object(v, [
      "request_id",
      "plan",
      "snapshot_sha256",
      "members",
      "deadline_utc_ms",
    ]),
  )
  use request <- result.try(text(v, "request_id"))
  use plan <- result.try(text(v, "plan"))
  use tagged <- result.try(text(v, "snapshot_sha256"))
  use _ <- result.try(ensure(
    token(request)
    && token(plan)
    && string.byte_size(tagged) == 71
    && string.starts_with(tagged, "sha256:"),
  ))
  let snapshot = string.drop_start(tagged, 7)
  use _ <- result.try(
    ensure(
      list.all(string.to_graphemes(snapshot), fn(c) {
        string.byte_size(c) == 1 && string.contains("0123456789abcdef", c)
      }),
    ),
  )
  use deadline <- result.try(integer(v, "deadline_utc_ms"))
  use _ <- result.try(ensure(deadline > 0 && deadline <= 9_223_372_036_854))
  use raw_members <- result.try(field(v, "members"))
  use raw_members <- result.try(case raw_members {
    value.Array([a, b, c]) -> Ok([a, b, c])
    _ -> Error(InvalidInput)
  })
  use members <- result.try(list.try_map(raw_members, member))
  let members = list.sort(members, fn(a, b) { string.compare(a.task, b.task) })
  use _ <- result.try(ensure(
    list.length(list.unique(list.map(members, fn(m) { m.task }))) == 3,
  ))
  use duration <- result.try(case members {
    [m, ..] -> Ok(m.duration)
    _ -> Error(InvalidInput)
  })
  use _ <- result.try(
    ensure(list.all(members, fn(m) { m.duration == duration })),
  )
  let bytes =
    json.object([
      #("domain", json.string("uos.sa-plan.reclaim-three.v1")),
      #("request_id", json.string(request)),
      #("plan", json.string(plan)),
      #("snapshot", json.string(snapshot)),
      #("old", json.array(members, member_json)),
      #("duration", json.string(int.to_string(duration * 1_000_000))),
      #("deadline", json.string(int.to_string(deadline * 1_000_000))),
    ])
    |> json.to_string
  let digest =
    bytes
    |> bit_array.from_string
    |> crypto.hash(crypto.Sha256, _)
    |> bit_array.base16_encode
    |> string.lowercase
  Ok(FactualRequest(bytes, digest))
}

pub fn canonical_bytes(request: FactualRequest) -> String {
  request.bytes
}

pub fn request_sha256(request: FactualRequest) -> String {
  request.digest
}

pub fn tagged_request_sha256(request: FactualRequest) -> String {
  "sha256:" <> request.digest
}
