//// Concrete bounded native transport. Reuses framing/process-group guardian,
//// never Telegram domain data. A response is evidence, never authorization.

import cepaf_gleam/ecology/cutover_protocol as p
import cepaf_gleam/harness/telegram_store_transport as framed
import cepaf_gleam/harness/value as v
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/json_guard
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, Some}
import gleam/result
import gleam/string

pub type Binding {
  Binding(
    transaction_id: String,
    candidate: String,
    manifest: String,
    epoch: Int,
    generation: Int,
  )
}

pub type Edit {
  Edit(relative: String, replacement_relative: String)
}

pub type Cleanup {
  Confirmed(exit_status: Int, observed_utc_us: Int)
  Unconfirmed
}

pub type LogRecord {
  LogRecord(
    operation: String,
    epoch: Int,
    generation: Int,
    payload: v.Value,
    status: String,
  )
}

pub type Reply {
  Reply(
    status: String,
    code: String,
    binding: Binding,
    operation: String,
    prepared: Bool,
    count: Int,
    images: List(String),
    records: List(LogRecord),
    cleanup: Cleanup,
  )
}

pub type Exchange {
  Exchange(result: Result(Reply, String), cleanup: Cleanup)
}

@external(erlang, "telegram_store_transport_ffi", "request_config_with_cleanup")
fn native_request(
  config: framed.LocalConfiguration,
  body: String,
) -> #(Result(String, String), Option(#(Int, Int)))

pub fn local_configuration(
  guardian: String,
  guardian_sha256: String,
  worker: String,
  worker_sha256: String,
  private_configuration: String,
) -> framed.LocalConfiguration {
  framed.reviewed_local_configuration(
    guardian,
    guardian_sha256,
    worker,
    worker_sha256,
    private_configuration,
  )
}

fn object(fields: List(#(String, v.Value))) -> v.Value {
  v.Object(fields)
}

fn null_or_index(command: p.Command) -> v.Value {
  case command {
    p.ReplaceFile(i) | p.RestoreFile(i) -> v.Integer(i)
    _ -> v.Null
  }
}

pub fn command_value(command: p.Command) -> v.Value {
  object([
    #(
      "kind",
      v.Text(case command {
        p.StageFiles -> "stage_files"
        p.FenceReaders -> "fence_readers"
        p.ReplaceFile(_) -> "replace_file"
        p.VerifyCandidate -> "verify_candidate"
        p.RestoreFile(_) -> "restore_file"
        p.VerifyPrevious -> "verify_previous"
        p.ResumeReaders -> "resume_readers"
      }),
    ),
    #("index", null_or_index(command)),
  ])
}

pub fn observation_value(observation: p.Observation) -> v.Value {
  let #(kind, candidate, manifest, count) = case observation {
    p.Succeeded -> #("succeeded", v.Null, v.Null, v.Null)
    p.Failed -> #("failed", v.Null, v.Null, v.Null)
    p.Prepared(manifest, count) -> #(
      "prepared",
      v.Null,
      v.Text(manifest),
      v.Integer(count),
    )
    p.Verified(candidate) -> #("verified", v.Text(candidate), v.Null, v.Null)
  }
  object([
    #("kind", v.Text(kind)),
    #("candidate", candidate),
    #("manifest", manifest),
    #("physical_count", count),
  ])
}

pub fn pending_payload(command: p.Command) -> v.Value {
  object([#("command", command_value(command))])
}

pub fn result_payload(
  command: p.Command,
  observation: p.Observation,
) -> v.Value {
  object([
    #("command", command_value(command)),
    #("observation", observation_value(observation)),
  ])
}

pub fn empty_payload() -> v.Value {
  object([])
}

pub fn index_payload(index: Int) -> v.Value {
  object([#("index", v.Integer(index))])
}

pub fn stage_payload(edits: List(Edit)) -> v.Value {
  object([
    #(
      "edits",
      v.Array(
        list.map(edits, fn(e) {
          object([
            #("relative", v.Text(e.relative)),
            #("replacement_relative", v.Text(e.replacement_relative)),
          ])
        }),
      ),
    ),
  ])
}

pub fn request_body(
  binding: Binding,
  operation: String,
  payload: v.Value,
) -> Result(String, String) {
  use _ <- result.try(
    case
      candidate_id.is_sha256_digest(binding.transaction_id)
      && candidate_id.is_sha256_digest(binding.candidate)
      && candidate_id.is_sha256_digest(binding.manifest)
      && binding.epoch > 0
      && binding.generation >= 0
      && list.contains(
        [
          "stage",
          "replace_one",
          "restore_one",
          "verify_new",
          "verify_old",
          "close",
          "inspect",
          "checkpoint_pending",
          "checkpoint_result",
          "recovery_epoch",
        ],
        operation,
      )
    {
      True -> Ok(Nil)
      False -> Error("INVALID_NATIVE_REQUEST_BINDING")
    },
  )
  let body =
    object([
      #("schema_version", v.Integer(1)),
      #("transaction_id", v.Text(binding.transaction_id)),
      #("candidate", v.Text(binding.candidate)),
      #("manifest", v.Text(binding.manifest)),
      #("epoch", v.Integer(binding.epoch)),
      #("generation", v.Integer(binding.generation)),
      #("operation", v.Text(operation)),
      #("payload", payload),
    ])
    |> v.encode
    |> json.to_string
  case string.byte_size(body) <= 262_144 {
    True -> Ok(body)
    False -> Error("NATIVE_REQUEST_BOUND")
  }
}

pub fn closed(value: v.Value, keys: List(String)) -> Result(Nil, String) {
  case value {
    v.Object(fields) ->
      case
        list.length(fields) == list.length(keys)
        && list.all(keys, fn(k) { list.count(fields, fn(f) { f.0 == k }) == 1 })
      {
        True -> Ok(Nil)
        False -> Error("CLOSED_OBJECT_REQUIRED")
      }
    _ -> Error("CLOSED_OBJECT_REQUIRED")
  }
}

pub fn text(value: v.Value, key: String) -> Result(String, String) {
  use field <- result.try(v.get(value, key))
  case field {
    v.Text(s) -> Ok(s)
    _ -> Error("TEXT_FIELD_REQUIRED")
  }
}

pub fn integer(value: v.Value, key: String) -> Result(Int, String) {
  use field <- result.try(v.get(value, key))
  case field {
    v.Integer(n) -> Ok(n)
    _ -> Error("INTEGER_FIELD_REQUIRED")
  }
}

fn boolean(value: v.Value, key: String) -> Result(Bool, String) {
  use field <- result.try(v.get(value, key))
  case field {
    v.Boolean(b) -> Ok(b)
    _ -> Error("BOOLEAN_FIELD_REQUIRED")
  }
}

fn array(value: v.Value, key: String) -> Result(List(v.Value), String) {
  use field <- result.try(v.get(value, key))
  case field {
    v.Array(xs) -> Ok(xs)
    _ -> Error("ARRAY_FIELD_REQUIRED")
  }
}

pub fn decode_command(value: v.Value) -> Result(p.Command, String) {
  use _ <- result.try(closed(value, ["kind", "index"]))
  use kind <- result.try(text(value, "kind"))
  use index <- result.try(v.get(value, "index"))
  case kind, index {
    "stage_files", v.Null -> Ok(p.StageFiles)
    "fence_readers", v.Null -> Ok(p.FenceReaders)
    "verify_candidate", v.Null -> Ok(p.VerifyCandidate)
    "verify_previous", v.Null -> Ok(p.VerifyPrevious)
    "resume_readers", v.Null -> Ok(p.ResumeReaders)
    "replace_file", v.Integer(i) if i >= 0 && i < 15 -> Ok(p.ReplaceFile(i))
    "restore_file", v.Integer(i) if i >= 0 && i < 15 -> Ok(p.RestoreFile(i))
    _, _ -> Error("INVALID_CHECKPOINT_COMMAND")
  }
}

pub fn decode_observation(value: v.Value) -> Result(p.Observation, String) {
  use _ <- result.try(
    closed(value, ["kind", "candidate", "manifest", "physical_count"]),
  )
  use kind <- result.try(text(value, "kind"))
  use c <- result.try(v.get(value, "candidate"))
  use m <- result.try(v.get(value, "manifest"))
  use n <- result.try(v.get(value, "physical_count"))
  case kind, c, m, n {
    "succeeded", v.Null, v.Null, v.Null -> Ok(p.Succeeded)
    "failed", v.Null, v.Null, v.Null -> Ok(p.Failed)
    "prepared", v.Null, v.Text(manifest), v.Integer(count) ->
      case
        candidate_id.is_sha256_digest(manifest)
        && { count == 14 || count == 15 }
      {
        True -> Ok(p.Prepared(manifest, count))
        False -> Error("INVALID_PREPARED_CHECKPOINT")
      }
    "verified", v.Text(candidate), v.Null, v.Null ->
      case candidate_id.is_sha256_digest(candidate) {
        True -> Ok(p.Verified(candidate))
        False -> Error("INVALID_VERIFIED_CHECKPOINT")
      }
    _, _, _, _ -> Error("INVALID_CHECKPOINT_OBSERVATION")
  }
}

pub fn record_ack(
  binding: Binding,
  record: LogRecord,
) -> Result(p.Acknowledgement, String) {
  use _ <- result.try(
    case record.operation == "checkpoint_result" && record.status == "result" {
      True -> Ok(Nil)
      False -> Error("NOT_PROTOCOL_ACK_RECORD")
    },
  )
  use _ <- result.try(closed(record.payload, ["command", "observation"]))
  use command <- result.try(
    v.get(record.payload, "command") |> result.try(decode_command),
  )
  use observation <- result.try(
    v.get(record.payload, "observation") |> result.try(decode_observation),
  )
  Ok(p.Acknowledgement(
    binding.transaction_id,
    binding.manifest,
    record.epoch,
    record.generation,
    command,
    observation,
  ))
}

fn record(value: v.Value) -> Result(LogRecord, String) {
  use _ <- result.try(
    closed(value, ["operation", "epoch", "generation", "payload", "status"]),
  )
  use operation <- result.try(text(value, "operation"))
  use epoch <- result.try(integer(value, "epoch"))
  use generation <- result.try(integer(value, "generation"))
  use payload <- result.try(v.get(value, "payload"))
  use status <- result.try(text(value, "status"))
  case
    epoch > 0
    && generation >= 0
    && { status == "pending" || status == "result" }
    && list.contains(
      [
        "stage",
        "replace_one",
        "restore_one",
        "verify_new",
        "verify_old",
        "close",
        "checkpoint_pending",
        "checkpoint_result",
        "recovery_epoch",
      ],
      operation,
    )
  {
    True -> Ok(LogRecord(operation, epoch, generation, payload, status))
    False -> Error("INVALID_DURABLE_RECORD")
  }
}

pub fn decode_reply(
  raw: String,
  binding: Binding,
  operation: String,
) -> Result(Reply, String) {
  use _ <- result.try(case string.byte_size(raw) <= 524_288 {
    True -> Ok(Nil)
    False -> Error("NATIVE_REPLY_BOUND")
  })
  use value <- result.try(
    json_guard.native_inspect(raw, 12)
    |> result.replace_error("INVALID_NATIVE_REPLY_JSON"),
  )
  use _ <- result.try(case closed(value, ["schema_version", "status", "code"]) {
    Ok(_) -> {
      use schema <- result.try(integer(value, "schema_version"))
      use status <- result.try(text(value, "status"))
      use code <- result.try(text(value, "code"))
      case
        schema == 1
        && { status == "hold" || status == "unknown" }
        && string.byte_size(code) <= 128
      {
        True -> Error("NATIVE_REFUSAL:" <> status <> ":" <> code)
        False -> Error("INVALID_NATIVE_REFUSAL")
      }
    }
    Error(_) -> Ok(Nil)
  })
  use _ <- result.try(
    closed(value, [
      "schema_version",
      "status",
      "code",
      "transaction_id",
      "candidate",
      "manifest",
      "epoch",
      "generation",
      "operation",
      "prepared",
      "count",
      "images",
      "records",
    ]),
  )
  use schema <- result.try(integer(value, "schema_version"))
  use tx <- result.try(text(value, "transaction_id"))
  use candidate <- result.try(text(value, "candidate"))
  use manifest <- result.try(text(value, "manifest"))
  use epoch <- result.try(integer(value, "epoch"))
  use generation <- result.try(integer(value, "generation"))
  use returned_operation <- result.try(text(value, "operation"))
  use status <- result.try(text(value, "status"))
  use code <- result.try(text(value, "code"))
  use prepared <- result.try(boolean(value, "prepared"))
  use count <- result.try(integer(value, "count"))
  use image_values <- result.try(array(value, "images"))
  use images <- result.try(
    list.try_map(image_values, fn(image) {
      case image {
        v.Text(s)
          if s == "old" || s == "new" || s == "both" || s == "unknown"
        -> Ok(s)
        _ -> Error("INVALID_IMAGE_STATE")
      }
    }),
  )
  use values <- result.try(array(value, "records"))
  use records <- result.try(case list.length(list.take(values, 257)) <= 256 {
    True -> list.try_map(values, record)
    False -> Error("DURABLE_RECORD_BOUND")
  })
  case
    schema == 1
    && tx == binding.transaction_id
    && candidate == binding.candidate
    && manifest == binding.manifest
    && epoch == binding.epoch
    && generation == binding.generation
    && returned_operation == operation
    && list.contains(["ok", "hold", "unknown"], status)
    && string.byte_size(code) <= 128
    && count >= 0
    && count <= 15
    && list.length(images) <= 15
    && case prepared {
      True -> { count == 14 || count == 15 } && list.length(images) == count
      False -> count == 0 && images == []
    }
  {
    True ->
      Ok(Reply(
        status,
        code,
        binding,
        operation,
        prepared,
        count,
        images,
        records,
        Unconfirmed,
      ))
    False -> Error("NATIVE_REPLY_BINDING_OR_SHAPE")
  }
}

pub fn exchange(
  config: framed.LocalConfiguration,
  binding: Binding,
  operation: String,
  payload: v.Value,
) -> Exchange {
  case request_body(binding, operation, payload) {
    Error(reason) -> Exchange(Error(reason), Unconfirmed)
    Ok(body) -> {
      let #(response, witness) = native_request(config, body)
      let cleanup = case witness {
        Some(#(status, utc))
          if { status == 0 || status == 124 || status == 125 } && utc > 0
        -> Confirmed(status, utc)
        _ -> Unconfirmed
      }
      Exchange(
        response
          |> result.try(fn(raw) { decode_reply(raw, binding, operation) })
          |> result.map(fn(reply) { Reply(..reply, cleanup: cleanup) }),
        cleanup,
      )
    }
  }
}

pub fn record_key(record: LogRecord) -> String {
  int.to_string(record.epoch)
  <> ":"
  <> int.to_string(record.generation)
  <> ":"
  <> record.operation
  <> ":"
  <> record.status
}
