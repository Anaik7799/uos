//// Emit validated observation JSONL for the native Hermes ingestion boundary.
//// This CLI never marks tasks complete or acknowledges an ingestion it did not observe.

import argv
import gleam/io
import gleam/json
import uos_swarm/session_observation

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

pub fn main() -> Nil {
  let outcome = case argv.load().arguments {
    ["export", root, source_ref] -> session_observation.export(root, source_ref)
    _ ->
      Error("usage: export ABSOLUTE_STATE_DIRECTORY STABLE_SOURCE_JOURNAL_REF")
  }
  case outcome {
    Ok(rows) -> io.println(rows)
    Error(reason) -> {
      io.println(
        json.to_string(
          json.object([
            #("ok", json.bool(False)),
            #("error", json.string(reason)),
          ]),
        ),
      )
      halt(1)
    }
  }
}
