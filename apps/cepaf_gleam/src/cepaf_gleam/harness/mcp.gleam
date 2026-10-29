//// Finite MCP development transport, UTF-8 JSON-RPC over bounded stdio frames.
//// Notifications never dispatch operational tools. MCP session lifecycle and
//// launcher binding precede all resources. No legacy fall-through.

import cepaf_gleam/harness/development as dev
import cepaf_gleam/harness/files
import cepaf_gleam/harness/peers
import cepaf_gleam/harness/system_feature_api
import cepaf_gleam/harness/system_feature_intent
import cepaf_gleam/harness/system_feature_store
import cepaf_gleam/harness/tracking
import cepaf_gleam/harness/value
import cepaf_gleam/mcp/protocol.{type ToolDefinition, ToolDefinition}
import cepaf_gleam/planning/execution_observer
import gleam/bit_array
import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/process
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

@external(erlang, "io", "setopts")
fn set_stdio_options(
  device: atom.Atom,
  options: List(#(atom.Atom, atom.Atom)),
) -> dynamic.Dynamic

/// Set the JSON-RPC output device to UTF-8 before emitting any protocol bytes.
/// `io:setopts/2` returns raw Erlang `ok | {error, reason}`; inspect the raw
/// value rather than relying on a guessed Result representation.
pub fn configure_stdout_utf8() -> Result(Nil, String) {
  let response = set_stdio_options(atom.create("standard_io"), [#(
    atom.create("encoding"),
    atom.create("unicode"),
  )])
  case response == atom.to_dynamic(atom.create("ok")) {
    True -> Ok(Nil)
    False -> Error("stdout_unicode_setup_failed")
  }
}

pub type State {
  State(initialized: Bool, closed: Bool)
}

pub const initial = State(False, False)

pub const frame_limit = 524_288

pub const frame_timeout_ms = 5000

pub fn tool_definitions() -> List(ToolDefinition) {
  list.append(
    [
      "harness_execution_progress",
      "harness_system_feature_catalog",
      "harness_system_feature_observations",
      "harness_system_feature_intent",
      ..dev.tool_names()
    ],
    list.append(peers.names(), tracking.names()),
  )
  |> list.map(fn(name) {
    ToolDefinition(
      name,
      "Finite task-bound UOS development service: " <> name,
      schema(name),
    )
  })
}

// A bounded protocol error precedes closure. Never drain an unbounded hostile
// frame, and never dispatch a handler for an oversized request. The client must
// reconnect and reconcile canonical task state; EOF does not grant a retry.
fn refuse_frame(reason: String) {
  io.println(error(json.null(), -32_600, reason))
  io.println_error("harness: " <> reason)
  halt(1)
}

// Emitted when the frame is recoverable: the client sent one oversized request
// and then a delimiter within budget, so the SESSION survives. `id` is null
// because a rejected frame never yielded a trustworthy request id.
fn reject_frame(reason: String) {
  io.println(error(json.null(), -32_600, reason))
}

pub type DrainOutcome {
  Drained
  DrainFailed(String)
}

// B4: the -32600 branch in the handler was unreachable -- serve_loop matches the
// newline FIRST, so exactly `frame_limit` payload bytes followed by LF are
// ACCEPTED, and the next NON-LF byte is the overflow. Reaching that byte used to
// halt the process, so one oversized request destroyed the session and its
// in-memory execution state.
//
// The drain is BOUNDED in both dimensions, because an unbounded drain is a
// denial of service: at most `frame_limit` further bytes (counting the offending
// byte and any terminating LF), and the frame's EXISTING absolute deadline,
// which is deliberately never reset -- resetting it on progress would let a
// trickling client hold the transport open forever, which is the same attack
// wearing a slower coat.
fn drain_overflow(
  input: Input,
  started: Option(Int),
  drained: Int,
) -> DrainOutcome {
  case next_byte(input, started) {
    Ok(Some(<<10>>)) -> Drained
    Ok(Some(_)) ->
      case drained + 1 < frame_limit {
        True -> drain_overflow(input, started, drained + 1)
        False -> DrainFailed("frame_bound_unrecoverable:drain_byte_budget")
      }
    Ok(None) -> DrainFailed("frame_bound_unrecoverable:eof_during_drain")
    Error(_) -> DrainFailed("frame_bound_unrecoverable:drain_deadline")
  }
}

type Unit {
  Millisecond
}

@external(erlang, "erlang", "monotonic_time")
fn monotonic_time(unit: Unit) -> Int

@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil

type ByteResult =
  Result(Option(BitArray), String)

type Input =
  process.Subject(process.Subject(ByteResult))

pub fn frame_budget(start_ms: Int, now_ms: Int) -> Result(Int, String) {
  let remaining = frame_timeout_ms - { now_ms - start_ms }
  case now_ms >= start_ms && remaining > 0 {
    True -> Ok(remaining)
    False -> Error("frame_deadline")
  }
}

fn reader(input: files.Device, requests: Input) {
  let reply = process.receive_forever(requests)
  let outcome = files.next_byte(input)
  process.send(reply, outcome)
  case outcome {
    Ok(Some(_)) -> reader(input, requests)
    _ -> Nil
  }
}

fn start_reader() -> Result(Input, String) {
  let ready = process.new_subject()
  let _ =
    process.spawn(fn() {
      case files.stdin() {
        Ok(input) -> {
          let requests = process.new_subject()
          process.send(ready, Ok(requests))
          reader(input, requests)
        }
        Error(e) -> process.send(ready, Error(e))
      }
    })
  case process.receive(ready, 3000) {
    Ok(value) -> value
    Error(_) -> Error("stdin_start_timeout")
  }
}

fn next_byte(input: Input, started: Option(Int)) -> ByteResult {
  let reply = process.new_subject()
  process.send(input, reply)
  case started {
    None -> process.receive_forever(reply)
    Some(start) ->
      case frame_budget(start, monotonic_time(Millisecond)) {
        Error(e) -> Error(e)
        Ok(remaining) ->
          case process.receive(reply, remaining) {
            Ok(value) -> value
            Error(_) -> Error("frame_deadline")
          }
      }
  }
}

pub fn main() {
  case configure_stdout_utf8() {
    Error(reason) -> {
      io.println_error("harness: " <> reason)
      halt(1)
    }
    Ok(Nil) ->
      case dev.load_binding(), start_reader() {
        Ok(binding), Ok(input) -> loop(binding, initial, input, [], 0, None)
        _, _ -> io.println_error(
          "harness: trusted development binding or stdin unavailable",
        )
      }
  }
}

fn loop(
  binding: dev.Binding,
  state: State,
  input: Input,
  chunks: List(BitArray),
  size: Int,
  started: Option(Int),
) {
  case next_byte(input, started) {
    Ok(Some(<<10>>)) -> {
      let bytes = chunks |> list.reverse |> bit_array.concat
      case bit_array.to_string(bytes) {
        Ok(line) -> {
          let #(next, reply) = handle(binding, state, line)
          case reply {
            Some(text) -> io.println(text)
            None -> Nil
          }
          case next.closed {
            True -> Nil
            False -> loop(binding, next, input, [], 0, None)
          }
        }
        Error(_) ->
          io.println_error("harness: invalid UTF-8 frame; transport closed")
      }
    }
    Ok(Some(byte)) ->
      case size < frame_limit {
        True ->
          loop(binding, state, input, [byte, ..chunks], size + 1, case started {
            Some(_) -> started
            None -> Some(monotonic_time(Millisecond))
          })
        False -> io.println_error("harness: frame bound; transport closed")
      }
    Ok(None) -> Nil
    Error(reason) -> {
      io.println_error("harness: " <> reason <> "; transport closed")
      halt(1)
    }
  }
}

fn response(id: json.Json, result: json.Json) -> String {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", id),
    #("result", result),
  ])
  |> json.to_string
}

fn error(id: json.Json, code: Int, message: String) -> String {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", id),
    #(
      "error",
      json.object([
        #("code", json.int(code)),
        #("message", json.string(message)),
      ]),
    ),
  ])
  |> json.to_string
}

fn schema(name: String) -> json.Json {
  let fields = case name {
    "harness_system_feature_catalog" -> ["catalog_sha256", "offset"]
    "harness_system_feature_observations" -> [
      "catalog_sha256",
      "ledger_sha256",
      "offset",
    ]
    "harness_system_feature_intent" -> [
      "intent",
      "catalog_sha256",
      "ledger_sha256",
      "offset",
    ]
    "harness_read_file" -> ["path"]
    "harness_write_file" -> ["intent_id", "path", "content", "expected_sha256"]
    "harness_build" | "harness_test" -> ["intent_id"]
    "harness_finish" -> ["journal_path", "build_intent_id", "test_intent_id"]
    "harness_peer_read" -> ["pane_id", "session_id"]
    "harness_peer_review" -> [
      "pane_id",
      "session_id",
      "review_id",
      "packet_path",
    ]
    "harness_peer_note" -> ["pane_id", "session_id", "review_id", "note"]
    "harness_feature_sync" -> ["feature_id"]
    _ -> []
  }
  json.object([
    #("type", json.string("object")),
    #(
      "properties",
      json.object(
        list.map(fields, fn(field) {
          #(field, json.object([#("type", json.string("string"))]))
        }),
      ),
    ),
    #("required", json.array(fields, json.string)),
    #("additionalProperties", json.bool(False)),
  ])
}

fn output_schema(name: String) -> json.Json {
  let fields = case name {
    "harness_system_feature_catalog" -> [
      #("schema", "string"),
      #("catalog_sha256", "string"),
      #("candidate", "string"),
      #("count", "integer"),
      #("offset", "integer"),
      #("next_offset", "integer_or_null"),
      #("features", "array"),
      #("metadata_only", "boolean"),
      #("inventory_complete", "boolean"),
      #("effect_authority", "boolean"),
      #("system_admission", "boolean"),
    ]
    "harness_system_feature_observations" -> [
      #("schema", "string"),
      #("catalog_sha256", "string"),
      #("ledger_sha256", "string"),
      #("count", "integer"),
      #("offset", "integer"),
      #("next_offset", "integer_or_null"),
      #("observations", "array"),
      #("availability", "string"),
      #("effect_authority", "boolean"),
      #("system_admission", "boolean"),
    ]
    "harness_system_feature_intent" -> [
      #("schema", "string"),
      #("intent", "string"),
      #("operation", "string"),
      #("catalog_sha256", "string"),
      #("ledger_sha256", "string"),
      #("offset", "integer"),
      #("effects", "array"),
      #("effect_authority", "boolean"),
      #("system_admission", "boolean"),
    ]
    "harness_execution_progress" -> [
      #("status", "string"),
      #("authority", "string"),
      #("task_snapshot_sha256", "string"),
      #("risk_snapshot_sha256", "string"),
      #("summary_raw", "string"),
      #("pending_raw", "string"),
      #("tasks", "array"),
      #("effect_authority", "boolean"),
      #("system_admission", "boolean"),
      #("progress", "object_or_null"),
    ]
    _ -> []
  }
  json.object([
    #("type", json.string("object")),
    #(
      "properties",
      json.object(
        list.map(fields, fn(field) {
          let field_type = case field.1 {
            "integer" -> json.object([#("type", json.string("integer"))])
            "boolean" -> json.object([#("type", json.string("boolean"))])
            "array" -> json.object([#("type", json.string("array"))])
            "object_or_null" ->
              json.object([
                #("type", json.string("object")),
                #("nullable", json.bool(True)),
              ])
            "integer_or_null" ->
              json.object([
                #("type", json.string("integer")),
                #("nullable", json.bool(True)),
              ])
            _ -> json.object([#("type", json.string("string"))])
          }
          #(field.0, field_type)
        }),
      ),
    ),
    #("additionalProperties", json.bool(False)),
  ])
}

fn refusal_schema(_name: String) -> json.Json {
  json.object([
    #("type", json.string("object")),
    #(
      "properties",
      json.object([
        #("isError", json.object([#("type", json.string("boolean"))])),
        #("content", json.object([#("type", json.string("array"))])),
      ]),
    ),
    #("required", json.array(["isError", "content"], json.string)),
    #("additionalProperties", json.bool(False)),
  ])
}

pub fn handle(
  binding: dev.Binding,
  state: State,
  line: String,
) -> #(State, Option(String)) {
  let id_decoder =
    decode.one_of(decode.map(decode.string, json.string), [
      decode.map(decode.int, json.int),
    ])
  let decoder = {
    use version <- decode.field("jsonrpc", decode.string)
    use method <- decode.field("method", decode.string)
    use id <- decode.optional_field("id", None, decode.map(id_decoder, Some))
    decode.success(#(version, method, id))
  }
  case
    bit_array.byte_size(bit_array.from_string(line)) <= frame_limit,
    json.parse(line, decoder)
  {
    False, _ -> #(state, Some(error(json.null(), -32_600, "frame_bound")))
    _, Error(_) -> #(
      state,
      Some(error(json.null(), -32_600, "invalid_request")),
    )
    True, Ok(#("2.0", "notifications/initialized", None)) -> #(state, None)
    True, Ok(#("2.0", _, None)) -> #(state, None)
    True, Ok(#("2.0", method, Some(id))) -> {
      case method {
        "initialize" -> #(
          State(True, False),
          Some(response(
            id,
            json.object([
              #("protocolVersion", json.string("2024-11-05")),
              #("capabilities", json.object([#("tools", json.object([]))])),
              #(
                "serverInfo",
                json.object([
                  #("name", json.string("uos-gleam-development-harness")),
                  #("version", json.string("0.1.0")),
                ]),
              ),
            ]),
          )),
        )
        _ if !state.initialized -> #(
          state,
          Some(error(id, -32_002, "initialize_required")),
        )
        "ping" -> #(state, Some(response(id, json.object([]))))
        "shutdown" -> #(State(True, True), Some(response(id, json.object([]))))
        "tools/list" -> #(
          state,
          Some(response(
            id,
            json.object([
              #(
                "tools",
                json.array(tool_definitions(), fn(tool) {
                  json.object([
                    #("name", json.string(tool.name)),
                    #("description", json.string(tool.description)),
                    #("inputSchema", tool.input_schema),
                    #("outputSchema", output_schema(tool.name)),
                    #("errorSchema", refusal_schema(tool.name)),
                  ])
                }),
              ),
            ]),
          )),
        )
        "tools/call" -> {
          let call_decoder = {
            use name <- decode.subfield(["params", "name"], decode.string)
            use args <- decode.subfield(
              ["params", "arguments"],
              value.decoder(),
            )
            decode.success(#(name, args))
          }
          let reply = case json.parse(line, call_decoder) {
            Error(_) -> error(id, -32_602, "tool_arguments_invalid")
            Ok(#(name, args)) ->
              case call_tool(binding, name, args) {
                Ok(result) ->
                  response(
                    id,
                    json.object([
                      #("isError", json.bool(False)),
                      #(
                        "content",
                        json.array(
                          [
                            json.object([
                              #("type", json.string("text")),
                              #("text", json.string(json.to_string(result))),
                            ]),
                          ],
                          fn(x) { x },
                        ),
                      ),
                    ]),
                  )
                Error(reason) ->
                  response(
                    id,
                    json.object([
                      #("isError", json.bool(True)),
                      #(
                        "content",
                        json.array(
                          [
                            json.object([
                              #("type", json.string("text")),
                              #("text", json.string(reason)),
                            ]),
                          ],
                          fn(x) { x },
                        ),
                      ),
                    ]),
                  )
              }
          }
          #(state, Some(reply))
        }
        _ -> #(state, Some(error(id, -32_601, "unknown_method")))
      }
    }
    _, _ -> #(state, Some(error(json.null(), -32_600, "jsonrpc_version")))
  }
}

fn call_tool(
  binding: dev.Binding,
  name: String,
  args: value.Value,
) -> Result(json.Json, String) {
  case name {
    "harness_system_feature_catalog" -> {
      let runtime = system_feature_store.canonical_runtime(binding)
      system_feature_api.query(args, runtime.fence, fn(digest) {
        system_feature_store.load(runtime, digest)
      })
    }
    "harness_system_feature_observations" -> {
      let runtime = system_feature_store.canonical_runtime(binding)
      system_feature_api.observations(
        args,
        runtime.fence,
        fn(digest) { system_feature_store.load(runtime, digest) },
        fn(catalog, digest) {
          system_feature_store.load_ledger(runtime, catalog, digest)
        },
      )
    }
    "harness_system_feature_intent" -> {
      use _ <- result.try(dev.fence(binding))
      use decision <- result.try(system_feature_intent.decide(args))
      Ok(system_feature_intent.encode(decision))
    }
    "harness_execution_progress" ->
      execution_observer.query(
        args,
        fn() { dev.fence(binding) |> result.map(fn(_) { Nil }) },
        execution_observer.observe,
      )
    _ ->
      case
        list.contains(peers.names(), name),
        list.contains(tracking.names(), name)
      {
        True, _ -> peers.call(binding, name, args)
        _, True -> tracking.call(binding, name, args)
        _, _ -> dev.call(binding, name, args)
      }
  }
}

/// Dispatches the declarative feature APIs only after the environment-bound
/// Gleam harness admission is present. The main stdio MCP server uses this
/// entry point; no synthetic binding is accepted.
pub fn call_task_bound(
  name: String,
  args: value.Value,
) -> Result(json.Json, String) {
  use binding <- result.try(dev.load_binding())
  call_tool(binding, name, args)
}

/// Reuse the bounded transport for a successor application state machine.
/// The supplied handler is trusted Gleam code; request data cannot choose it.
pub fn serve(
  context: state,
  handler: fn(state, String) -> #(state, Option(String), Bool),
) {
  case configure_stdout_utf8() {
    Error(reason) -> {
      io.println_error("harness: " <> reason)
      halt(1)
    }
    Ok(Nil) -> case start_reader() {
      Ok(input) -> serve_loop(context, handler, input, [], 0, None)
      Error(reason) -> {
        io.println_error("harness: " <> reason)
        halt(1)
      }
    }
  }
}

fn serve_loop(
  context: state,
  handler: fn(state, String) -> #(state, Option(String), Bool),
  input: Input,
  chunks: List(BitArray),
  size: Int,
  started: Option(Int),
) {
  case next_byte(input, started) {
    Ok(Some(<<10>>)) -> {
      case chunks |> list.reverse |> bit_array.concat |> bit_array.to_string {
        Ok(line) -> {
          let #(next, reply, closed) = handler(context, line)
          case reply {
            Some(text) -> io.println(text)
            None -> Nil
          }
          case closed {
            True -> Nil
            False -> serve_loop(next, handler, input, [], 0, None)
          }
        }
        Error(_) -> {
          io.println_error("harness: invalid UTF-8 frame")
          halt(1)
        }
      }
    }
    Ok(Some(byte)) ->
      case size < frame_limit {
        True ->
          serve_loop(
            context,
            handler,
            input,
            [byte, ..chunks],
            size + 1,
            case started {
              Some(_) -> started
              None -> Some(monotonic_time(Millisecond))
            },
          )
        // The offending byte is already consumed, so it counts against the budget.
        False ->
          case drain_overflow(input, started, 1) {
            Drained -> {
              reject_frame("frame_bound")
              serve_loop(context, handler, input, [], 0, None)
            }
            DrainFailed(reason) -> refuse_frame(reason)
          }
      }
    Ok(None) -> Nil
    Error(reason) -> {
      io.println_error("harness: " <> reason)
      halt(1)
    }
  }
}
