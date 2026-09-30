//// Immutable worker entrypoint. Logs loaded diagnostic/control identities before
//// consuming existing intents. Startup observation performs no test messages.
import cepaf_gleam/harness/cognitive_worker
import cepaf_gleam/harness/doctor_projection
import gleam/bit_array
import gleam/erlang/atom
import gleam/io
import gleam/json
import gleam/list
import gleam/string

@external(erlang, "erlang", "apply")
fn metadata(module: atom.Atom, function: atom.Atom, args: List(atom.Atom)) -> BitArray

pub fn identity() -> String {
  json.object([
    #("schema", json.string("uos.cognitive-runtime-observation.v1")),
    #("modules", json.object(list.map([
      "cognitive_runtime_cli", "cepaf_gleam@harness@cognitive_worker",
      "cepaf_gleam@harness@doctor_projection", "cepaf_gleam@harness@tool_fenced_dispatcher",
    ], fn(name) {
      #(name, json.string(metadata(atom.create(name), atom.create("module_info"), [atom.create("md5")])
        |> bit_array.base16_encode |> string.lowercase))
    }))),
    #("doctor", json.string(doctor_projection.to_json(doctor_projection.project()))),
    #("admission", json.string("NOT_GRANTED_BY_STARTUP_OBSERVATION")),
  ]) |> json.to_string
}

pub fn main() {
  io.println(identity())
  cognitive_worker.run_loop("http://nas-1.tail55d152.ts.net:8080", 1000)
}
