//// Private output only: includes account metadata. No HTTP or inference.

import argv
import gleam/io
import gleam/json
import gleam/result
import uos_swarm/token_monitor_billing as billing

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

pub fn main() {
  let report = case argv.load().arguments {
    [path] -> {
      use raw <- result.try(
        billing.read_receipt(path)
        |> result.replace_error("billing_manifest_unavailable"),
      )
      billing.report(raw.0)
    }
    _ -> Error("expected_one_private_billing_manifest_path")
  }
  case report {
    Ok(out) -> io.println(json.to_string(out))
    Error(reason) -> {
      io.println(
        json.to_string(
          json.object([
            #("decision", json.string("HOLD")),
            #("authority", json.string("NONE")),
            #("reason", json.string(reason)),
            #("ledger_mutated", json.bool(False)),
            #("inference_dispatched", json.bool(False)),
          ]),
        ),
      )
      halt(2)
    }
  }
}
