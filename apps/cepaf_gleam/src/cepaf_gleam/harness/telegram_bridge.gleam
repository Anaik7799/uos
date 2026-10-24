//// Pure provisioning wire codec; only the supervised caller chooses artifacts,
//// database, authentic profile and current authority. Found is an observation,
//// never a signing, job execution or production admission grant.

import cepaf_gleam/harness/telegram_store_codec as codec
import gleam/json
import gleam/list
import gleam/result
import gleam/string

const max_ns = 9_223_372_036_854_775_807

const max_lifetime_ns = 300_000_000_000

const invalid_response = "invalid_bridge_response"

pub opaque type Request {
  Request(
    mapping: String,
    plan: String,
    task: String,
    owner: String,
    attempt: Int,
    lease: String,
    expiry: Int,
  )
}

pub type Operation {
  Bind
  Lookup
}

pub type Outcome {
  Found(
    fencing_token: Int,
    expires_at_ns: Int,
    observed_at_ns: Int,
    historical: Bool,
  )
  Absent
  Rejected
}

pub fn new(
  mapping: String,
  plan: String,
  task: String,
  owner: String,
  attempt: Int,
  lease: String,
  expiry: Int,
) -> Result(Request, String) {
  case
    list.all([mapping, plan, task, owner, lease], token)
    && attempt > 0
    && attempt <= 2_147_483_647
    && expiry > 0
    && expiry <= max_ns
  {
    True -> Ok(Request(mapping, plan, task, owner, attempt, lease, expiry))
    False -> Error("invalid_bridge_request")
  }
}

fn token(value: String) -> Bool {
  string.byte_size(value) > 0
  && string.byte_size(value) <= 240
  && !string.contains(value, "..")
  && list.all(string.to_utf_codepoints(value), fn(c) {
    let n = string.utf_codepoint_to_int(c)
    n >= 48
    && n <= 57
    || n >= 65
    && n <= 90
    || n >= 97
    && n <= 122
    || list.contains([45, 95, 46, 47, 58], n)
  })
}

pub fn request_json(r: Request) -> String {
  json.object([
    #("schema", json.string("uos.sa-plan.bridge-bind-request.v1")),
    #("mapping_id", json.string(r.mapping)),
    #("plan_id", json.string(r.plan)),
    #("task_id", json.string(r.task)),
    #("owner", json.string(r.owner)),
    #("task_attempt", json.int(r.attempt)),
    #("lease_id", json.string(r.lease)),
    #("expires_at_ns", json.int(r.expiry)),
  ])
  |> json.to_string
}

pub fn envelope(r: Request, operation: Operation) -> String {
  let name = case operation {
    Bind -> "bind-controller-bridge"
    Lookup -> "controller-bridge-result"
  }
  "{\"schema\":\"uos.telegram.cancel-transport.v1\",\"operation\":"
  <> json.to_string(json.string(name))
  <> ",\"request\":"
  <> request_json(r)
  <> "}"
}

/// The caller must supply its current trusted observation after transport.
/// Lookup may describe an expired original lease and never renews it.
pub fn decode_response(
  r: Request,
  operation: Operation,
  raw: String,
  now_ns: Int,
) -> Result(Outcome, String) {
  use _ <- result.try(require(
    string.byte_size(raw) > 0
      && string.byte_size(raw) <= 16_384
      && now_ns >= 0
      && now_ns <= max_ns,
    invalid_response,
  ))
  use root <- result.try(case codec.parse_strict_json(raw) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(invalid_response)
  })
  use outer <- result.try(
    expect_exact_object(root, ["schema", "status", "result", "error"]),
  )
  use schema <- result.try(get_string(outer, "schema"))
  use _ <- result.try(require(
    schema == "uos.telegram.cancel-transport-response.v1",
    invalid_response,
  ))
  use status <- result.try(get_string(outer, "status"))
  case status {
    "rejected" -> {
      use _ <- result.try(expect_null(outer, "result"))
      use error <- result.try(get_string(outer, "error"))
      use _ <- result.try(require(
        error == "cancel_request_rejected",
        invalid_response,
      ))
      Ok(Rejected)
    }
    "ok" -> {
      use _ <- result.try(expect_null(outer, "error"))
      use value <- result.try(get_field(outer, "result"))
      decode_result(r, operation, value, now_ns)
    }
    _ -> Error(invalid_response)
  }
}

fn decode_result(
  r: Request,
  operation: Operation,
  value: codec.StrictJsonValue,
  now_ns: Int,
) -> Result(Outcome, String) {
  use body <- result.try(
    expect_exact_object(value, [
      "schema",
      "found",
      "historical",
      "observed_at_ns",
      "lease",
    ]),
  )
  use schema <- result.try(get_string(body, "schema"))
  use historical <- result.try(get_bool(body, "historical"))
  use observed <- result.try(get_int(body, "observed_at_ns"))
  use _ <- result.try(require(
    schema == "uos.sa-plan.bridge-bind-response.v1"
      && historical == { operation == Lookup }
      && observed >= 0
      && observed <= now_ns,
    invalid_response,
  ))
  use found <- result.try(get_bool(body, "found"))
  case found {
    False -> {
      use _ <- result.try(require(operation == Lookup, invalid_response))
      use _ <- result.try(expect_null(body, "lease"))
      Ok(Absent)
    }
    True -> {
      use value <- result.try(get_field(body, "lease"))
      use lease <- result.try(
        expect_exact_object(value, [
          "mapping_id",
          "plan_id",
          "task_id",
          "owner",
          "task_attempt",
          "lease_id",
          "fencing_token",
          "expires_at_ns",
        ]),
      )
      use mapping <- result.try(get_string(lease, "mapping_id"))
      use plan <- result.try(get_string(lease, "plan_id"))
      use task <- result.try(get_string(lease, "task_id"))
      use owner <- result.try(get_string(lease, "owner"))
      use attempt <- result.try(get_int(lease, "task_attempt"))
      use lease_id <- result.try(get_string(lease, "lease_id"))
      use fence <- result.try(get_int(lease, "fencing_token"))
      use expiry <- result.try(get_int(lease, "expires_at_ns"))
      use _ <- result.try(require(
        mapping == r.mapping
          && plan == r.plan
          && task == r.task
          && owner == r.owner
          && attempt == r.attempt
          && lease_id == r.lease
          && expiry == r.expiry
          && fence > 0
          && fence <= max_ns,
        invalid_response,
      ))
      use _ <- result.try(require(
        operation == Lookup
          || expiry > now_ns
          && expiry - observed <= max_lifetime_ns,
        invalid_response,
      ))
      Ok(Found(fence, expiry, observed, historical))
    }
  }
}

fn expect_exact_object(
  value: codec.StrictJsonValue,
  expected_keys: List(String),
) -> Result(List(#(String, codec.StrictJsonValue)), String) {
  case value {
    codec.JsonObject(fields) -> {
      let same_length = list.length(fields) == list.length(expected_keys)
      let all_present =
        list.all(expected_keys, fn(key) { has_key(fields, key) })
      use _ <- result.try(require(same_length && all_present, invalid_response))
      Ok(fields)
    }
    _ -> Error(invalid_response)
  }
}

fn has_key(
  fields: List(#(String, codec.StrictJsonValue)),
  key: String,
) -> Bool {
  case list.find(fields, fn(entry) { entry.0 == key }) {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn get_field(
  fields: List(#(String, codec.StrictJsonValue)),
  key: String,
) -> Result(codec.StrictJsonValue, String) {
  case list.find(fields, fn(entry) { entry.0 == key }) {
    Ok(#(_, value)) -> Ok(value)
    Error(_) -> Error(invalid_response)
  }
}

fn get_string(
  fields: List(#(String, codec.StrictJsonValue)),
  key: String,
) -> Result(String, String) {
  use value <- result.try(get_field(fields, key))
  case value {
    codec.JsonString(text) -> Ok(text)
    _ -> Error(invalid_response)
  }
}

fn get_int(
  fields: List(#(String, codec.StrictJsonValue)),
  key: String,
) -> Result(Int, String) {
  use value <- result.try(get_field(fields, key))
  case value {
    codec.JsonInt(number) -> Ok(number)
    _ -> Error(invalid_response)
  }
}

fn get_bool(
  fields: List(#(String, codec.StrictJsonValue)),
  key: String,
) -> Result(Bool, String) {
  use value <- result.try(get_field(fields, key))
  case value {
    codec.JsonBool(flag) -> Ok(flag)
    _ -> Error(invalid_response)
  }
}

fn expect_null(
  fields: List(#(String, codec.StrictJsonValue)),
  key: String,
) -> Result(Nil, String) {
  use value <- result.try(get_field(fields, key))
  case value {
    codec.JsonNull -> Ok(Nil)
    _ -> Error(invalid_response)
  }
}

fn require(condition: Bool, message: String) -> Result(Nil, String) {
  case condition {
    True -> Ok(Nil)
    False -> Error(message)
  }
}
