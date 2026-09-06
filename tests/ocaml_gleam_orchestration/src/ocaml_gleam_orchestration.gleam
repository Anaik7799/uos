import envoy
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/io
import gleam/json
import ocaml_counterparts/native

pub fn request(operation: String, database: String) -> Result(Dynamic, String) {
  let assert Ok(executable) = envoy.get("UOS_PLAN_PORT")
  native.request_with(
    executable,
    ["--db", database],
    operation,
    json.object([]),
    30_000,
  )
}

pub fn main() {
  let assert Ok(database) = envoy.get("UOS_PLAN_DB")
  let assert Ok(operation) = envoy.get("UOS_PLAN_OPERATION")
  let assert Ok(observation) = request(operation, database)
  let assert Ok(encoded) = decode.run(observation, json_value_decoder())
  io.println(json.to_string(encoded))
}

fn json_value_decoder() -> decode.Decoder(json.Json) {
  use plan_id <- decode.field("plan_id", decode.string)
  use workflow_id <- decode.field("workflow_id", decode.string)
  use queue <- decode.field("queue", decode.string)
  use task_count <- decode.field("task_count", decode.int)
  use job_count <- decode.field("job_count", decode.int)
  use workflow_state <- decode.field("workflow_state", decode.string)
  use dispatch_enabled <- decode.field("dispatch_enabled", decode.bool)
  use completed <- decode.field("completed", decode.int)
  use executing <- decode.field("executing", decode.int)
  use ready <- decode.field("ready", decode.int)
  use job_attempts <- decode.field("job_attempts", decode.int)
  decode.success(
    json.object([
      #("plan_id", json.string(plan_id)),
      #("workflow_id", json.string(workflow_id)),
      #("queue", json.string(queue)),
      #("task_count", json.int(task_count)),
      #("job_count", json.int(job_count)),
      #("workflow_state", json.string(workflow_state)),
      #("dispatch_enabled", json.bool(dispatch_enabled)),
      #("completed", json.int(completed)),
      #("executing", json.int(executing)),
      #("ready", json.int(ready)),
      #("job_attempts", json.int(job_attempts)),
    ]),
  )
}
