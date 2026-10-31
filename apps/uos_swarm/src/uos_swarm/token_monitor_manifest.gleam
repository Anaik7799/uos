//// Local read-only adapter over explicit registered invocation receipt paths.
//// No corpus crawling, transcript publication, watches, task or budget writes.

import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import uos_swarm/board
import uos_swarm/token_monitor as monitor
import uos_swarm/token_monitor_native as native

@external(erlang, "token_monitor_json_ffi", "valid_object")
fn strict_object(text: String) -> Bool

@external(erlang, "token_monitor_json_ffi", "read_receipt")
fn read_receipt(path: String) -> Result(#(String, String, String), String)

fn bind_source(
  seen: dict.Dict(String, #(String, String)),
  key: String,
  id: #(String, String),
) -> Result(dict.Dict(String, #(String, String)), String) {
  case dict.get(seen, key) {
    Ok(previous) ->
      case previous == id {
        True -> Ok(seen)
        False -> Error("ambiguous_receipt_source_alias")
      }
    Error(_) -> Ok(dict.insert(seen, key, id))
  }
}

type Source {
  Source(
    format: String,
    provider: String,
    id: String,
    agent: String,
    model: String,
    path: String,
  )
}

fn source() -> decode.Decoder(Source) {
  use f <- decode.field("format", decode.string)
  use p <- decode.field("provider", decode.string)
  use id <- decode.field("request_id", decode.string)
  use a <- decode.field("agent", decode.string)
  use m <- decode.field("model", decode.string)
  use path <- decode.field("path", decode.string)
  decode.success(Source(f, p, id, a, m, path))
}

pub fn report(text: String) -> Result(json.Json, String) {
  use _ <- result.try(case strict_object(text) {
    True -> Ok(Nil)
    False -> Error("invalid_bounded_manifest_json")
  })
  let decoder = {
    use s <- decode.field("schema_version", decode.int)
    use rows <- decode.field("sources", decode.list(source()))
    use mt <- decode.field("max_tokens", decode.int)
    use mc <- decode.field("max_calls", decode.int)
    decode.success(#(s, rows, monitor.Policy(mt, mc)))
  }
  use data <- result.try(
    json.parse(text, decoder) |> result.replace_error("invalid_manifest"),
  )
  use _ <- result.try(case data.0 == 1 && list.length(data.1) <= 256 {
    True -> Ok(Nil)
    False -> Error("manifest_schema_or_source_limit")
  })
  use accumulated <- result.try(
    list.try_fold(data.1, #([], [], dict.new()), fn(acc, s) {
      let loaded = read_receipt(s.path)
      use seen <- result.try(case loaded {
        Error(_) -> Ok(acc.2)
        Ok(raw) -> {
          use by_inode <- result.try(
            bind_source(acc.2, "inode:" <> raw.1, #(s.provider, s.id)),
          )
          bind_source(by_inode, "digest:" <> raw.2, #(s.provider, s.id))
        }
      })
      let read = {
        use raw <- result.try(loaded)
        native.parse(s.format, s.provider, s.id, s.agent, s.model, raw.0)
      }
      case read {
        Ok(row) -> Ok(#([row, ..acc.0], acc.1, seen))
        Error(reason) ->
          Ok(#(
            [
              monitor.Receipt(s.provider, s.id, None, None, None, False),
              ..acc.0
            ],
            [
              json.object([
                #("provider", json.string(s.provider)),
                #("request_id", json.string(s.id)),
                #("reason", json.string(reason)),
              ]),
              ..acc.1
            ],
            seen,
          ))
      }
    }),
  )
  use m <- result.try(monitor.collect(accumulated.0))
  use r <- result.try(monitor.report(m, data.2))
  Ok(
    json.object([
      #("observed_at_unix_us", json.int(board.system_time_us())),
      #("scope", json.string("selected_registered_final_invocations_only")),
      #("coverage_complete", json.bool(False)),
      #(
        "supervisor_accounting",
        json.string("separate_goal_metrics_overlap_unknown_do_not_add"),
      ),
      #(
        "liability",
        json.string("read_canonical_daily_ledger_separately_no_refunds"),
      ),
      #("adapter_errors", json.array(list.reverse(accumulated.1), fn(x) { x })),
      #("report", r),
    ]),
  )
}
