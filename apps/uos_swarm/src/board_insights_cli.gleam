//// Explicit read-only input files: bounded live snapshots can be supplied by
//// supervised collectors. No automatic fetch, model call, ACK or publication.

import argv
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import uos_swarm/board
import uos_swarm/board_insights as insights
import uos_swarm/board_reader as reader

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

pub fn run(arguments: List(String), now_us: Int) -> Result(String, String) {
  case arguments {
    [format, input_kind, path, telemetry_path, hive, tenant, scope_mode] -> {
      use text <- result.try(reader.read_file(path, reader.max_bytes))
      use input <- result.try(case input_kind {
        "jsonl" -> reader.from_jsonl(text)
        "zenoh" -> reader.from_zenoh(text)
        _ -> Error("input kind must be jsonl or zenoh")
      })
      use samples <- result.try(case telemetry_path {
        "-" -> Ok(reader.Input([], 0))
        _ -> {
          use text <- result.try(reader.read_file(
            telemetry_path,
            reader.max_bytes,
          ))
          reader.telemetry_jsonl(text)
        }
      })
      use legacy <- result.try(case scope_mode {
        "strict" -> Ok(False)
        "bind-legacy-snapshot" -> Ok(True)
        _ -> Error("scope mode must be strict or bind-legacy-snapshot")
      })
      use report <- result.try(insights.analyse(
        input.events,
        samples.events,
        insights.Query(
          insights.Scope(hive, tenant, legacy),
          now_us,
          120_000_000,
          86_400_000_000,
          10,
        ),
        None,
      ))
      let report =
        insights.Report(
          ..report,
          findings: list.append(report.findings, [
            insights.Finding(
              "reader_counts",
              "input",
              "Malformed board rows="
                <> int.to_string(input.malformed_count)
                <> "; malformed telemetry rows="
                <> int.to_string(samples.malformed_count)
                <> ". Raw malformed content is withheld.",
            ),
          ]),
        )
      case format {
        "json" ->
          Ok(
            json.to_string(
              json.object([
                #("board_malformed", json.int(input.malformed_count)),
                #("telemetry_malformed", json.int(samples.malformed_count)),
                #("report", insights.to_json(report)),
              ]),
            ),
          )
        "text" -> Ok(insights.to_text(report))
        _ -> Error("format must be json or text")
      }
    }
    _ ->
      Error(
        "usage: <json|text> <jsonl|zenoh> BOARD_SNAPSHOT TELEMETRY_JSONL|- HIVE TENANT <strict|bind-legacy-snapshot>",
      )
  }
}

pub fn main() -> Nil {
  case run(argv.load().arguments, board.system_time_us()) {
    Ok(output) -> io.println(output)
    Error(error) -> {
      io.println(
        json.to_string(
          json.object([
            #("ok", json.bool(False)),
            #("error", json.string(error)),
          ]),
        ),
      )
      halt(1)
    }
  }
}
