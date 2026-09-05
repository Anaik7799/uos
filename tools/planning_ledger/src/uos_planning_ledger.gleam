import birl
import filepath
import gleam/int
import gleam/io
import gleam/string
import simplifile
import uos_planning_ledger/materializer

pub fn main() -> Nil {
  let assert Ok(workspace_root) = simplifile.resolve("../../..")
  let destination =
    filepath.join(
      workspace_root,
      "docs/journal/2026-09-05-uos-planning-ledger.sqlite3",
    )

  case
    materializer.materialize(
      workspace_root: workspace_root,
      destination: destination,
      observed_at: now_to_second_precision(),
    )
  {
    Ok(summary) -> {
      io.println(
        "PLANNING_SNAPSHOT_ONLY: materialized "
        <> destination
        <> " artifacts="
        <> int.to_string(summary.artifacts)
        <> " prompts="
        <> int.to_string(summary.prompts)
        <> " mandate_inputs="
        <> int.to_string(summary.mandate_inputs)
        <> " clauses="
        <> int.to_string(summary.clauses)
        <> " directives="
        <> int.to_string(summary.directives)
        <> " source_maps="
        <> int.to_string(summary.source_maps)
        <> " capabilities="
        <> int.to_string(summary.capabilities),
      )
    }
    Error(error) -> {
      io.println_error(string.inspect(error))
      panic as "UOS planning-ledger materialization failed"
    }
  }
}

fn now_to_second_precision() -> String {
  let now = birl.now()
  let birl.Day(year, month, day) = birl.get_day(now)
  let birl.TimeOfDay(hour, minute, second, _) = birl.get_time_of_day(now)
  int.to_string(year)
  <> "-"
  <> pad2(month)
  <> "-"
  <> pad2(day)
  <> "T"
  <> pad2(hour)
  <> ":"
  <> pad2(minute)
  <> ":"
  <> pad2(second)
  <> birl.get_offset(now)
}

fn pad2(value: Int) -> String {
  value
  |> int.to_string
  |> string.pad_start(to: 2, with: "0")
}
