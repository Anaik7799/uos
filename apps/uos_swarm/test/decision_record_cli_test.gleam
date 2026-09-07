import gleam/int
import gleam/list
import gleam/string
import gleeunit/should
import uos_swarm/board
import uos_swarm/decision_record_cli as cli

@external(erlang, "uos_swarm_ffi", "ensure_dir")
fn ensure_dir(path: String) -> Result(Nil, String)

/// Scratch root for this test module: `UOS_DR_TEST_ROOT` when set, else
/// `build/decision_record_cli_test`. Never under `generated/`.
fn test_root() -> String {
  cli.getenv("UOS_DR_TEST_ROOT", "build/decision_record_cli_test")
}

/// Idempotent multi-level `mkdir -p`-style creation (`file:make_dir/1` is not
/// recursive), so the root works whether it is one segment or several.
fn ensure_tree(path: String) -> Result(Nil, String) {
  let is_abs = string.starts_with(path, "/")
  let parts = path |> string.split("/") |> list.filter(fn(s) { s != "" })
  let start = case is_abs {
    True -> "/"
    False -> ""
  }
  ensure_parts(parts, start)
}

fn ensure_parts(parts: List(String), acc: String) -> Result(Nil, String) {
  case parts {
    [] -> Ok(Nil)
    [p, ..rest] -> {
      let next = case acc {
        "" -> p
        "/" -> "/" <> p
        _ -> acc <> "/" <> p
      }
      case ensure_dir(next) {
        Ok(_) -> ensure_parts(rest, next)
        Error(e) -> Error(e)
      }
    }
  }
}

fn root() -> String {
  let r = test_root()
  let assert Ok(_) = ensure_tree(r)
  r
}

fn write(name: String, content: String) -> String {
  let path = root() <> "/" <> name
  let assert Ok(_) = board.file_write(path, content)
  path
}

const valid_spec = "{
  \"task\": \"run a bounded dry-run merge check\",
  \"resource\": \"integration/main\",
  \"proposed_action\": \"two-parent merge onto main after gates pass\",
  \"policy_refs\": [\"SYNC-03 lease at action time\", \"jj discipline D3/D4/D7\"],
  \"authorization\": \"operator: proceed with the dry-run\",
  \"observations\": [
    {\"source\": \"jj (read-only)\", \"value\": \"bookmark integration/x -> y\", \"grade\": \"Measured\"}
  ],
  \"alternatives\": [
    {\"option\": \"merge now\", \"tradeoff\": \"skips review window\"},
    {\"option\": \"wait for review\", \"tradeoff\": \"delay only\"}
  ],
  \"selected\": \"wait for review\",
  \"rationale\": \"review window has not elapsed\",
  \"risks\": [\"reviewer unavailable\"],
  \"unresolved\": [\"exact review window length\"],
  \"steps\": [\"gate\", \"review\", \"merge\"],
  \"rollback\": \"abandon the merge change\",
  \"escalation\": \"operator\",
  \"forecast\": {
    \"horizon_minutes\": 30,
    \"predicted_outcome\": \"merge succeeds cleanly\",
    \"probability\": 0.7,
    \"basis\": \"no known conflicts\",
    \"unknowns\": [\"reviewer availability\"]
  },
  \"unexpected_extra_key\": \"ignored\"
}"

const spec_missing_task = "{
  \"resource\": \"integration/main\",
  \"proposed_action\": \"two-parent merge onto main after gates pass\",
  \"policy_refs\": [],
  \"authorization\": \"operator\",
  \"observations\": [],
  \"alternatives\": [{\"option\": \"a\", \"tradeoff\": \"b\"}],
  \"selected\": \"a\",
  \"rationale\": \"r\",
  \"risks\": [],
  \"unresolved\": [],
  \"steps\": [\"s\"],
  \"rollback\": \"r\",
  \"escalation\": \"operator\",
  \"forecast\": {
    \"horizon_minutes\": 30,
    \"predicted_outcome\": \"o\",
    \"probability\": 0.5,
    \"basis\": \"b\",
    \"unknowns\": []
  }
}"

const valid_completion = "{
  \"observed_actions\": [\"merged cleanly\", \"gates passed\"],
  \"outcome\": \"succeeded\",
  \"forecast_resolution\": \"p=0.7 realized\",
  \"consumed\": {\"tokens\": \"0 for deterministic steps\", \"usd\": 0.0}
}"

fn prepared_path(slug: String) -> String {
  let spec_path = write(slug <> "-spec.json", valid_spec)
  let assert Ok(path) = cli.write_prepared(root(), slug, spec_path)
  path
}

// ---- pure helpers, tied to the canonical wire examples ----

pub fn stamp_from_iso_matches_the_canonical_example_test() {
  cli.stamp_from_iso("2026-09-07T11:20:00.000000Z")
  |> should.equal("20260907-1120")
  cli.stamp_from_iso("2026-09-07T12:05:00.000000Z")
  |> should.equal("20260907-1205")
}

pub fn decision_id_matches_the_canonical_example_test() {
  cli.decision_id(
    "L0-fable",
    "candidate-integration-5-mirage-queued",
    "20260907-1120",
  )
  |> should.equal(
    "DR-20260907-1120-L0FABLE-CANDIDATE-INTEGRATION-5-MIRAGE-QUEUED",
  )
}

pub fn horizon_label_matches_the_canonical_example_test() {
  cli.horizon_label(30) |> should.equal("30 min")
  cli.horizon_label(45) |> should.equal("45 min")
}

pub fn expires_at_iso_is_observed_at_plus_horizon_test() {
  cli.expires_at_iso(0, 30) |> should.equal("1970-01-01T00:30:00.000000Z")
}

// ---- prepare ----

pub fn prepare_writes_a_file_named_and_shaped_like_the_examples_test() {
  let slug = "cli-test-prepare-" <> int.to_string(board.system_time_us())
  let spec_path = write(slug <> "-spec.json", valid_spec)
  let assert Ok(path) = cli.write_prepared(root(), slug, spec_path)

  // The decision_id embeds the same stamp the filename does; deriving the
  // expected filename from the written decision_id ties the two together
  // without racing the host clock.
  let assert Ok(text) = board.file_read(path)
  let decision_id = decision_id_from_text(text)
  let stamp = string.slice(decision_id, 3, 13)

  string.length(stamp) |> should.equal(13)
  string.slice(stamp, 8, 1) |> should.equal("-")
  string.replace(stamp, "-", "") |> int_parses |> should.be_true

  path
  |> should.equal(
    root() <> "/" <> stamp <> "-uos-decision-record-" <> slug <> ".json",
  )
  decision_id
  |> should.equal("DR-" <> stamp <> "-L0FABLE-" <> string.uppercase(slug))

  cli.read_phase(path) |> should.equal(Ok("prepared"))
  let assert Ok(forecast) = cli.read_forecast(path)
  forecast.horizon |> should.equal("30 min")
  forecast.predicted_outcome |> should.equal("merge succeeds cleanly")
  forecast.probability |> should.equal(0.7)
}

fn int_parses(s: String) -> Bool {
  case int.parse(s) {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn decision_id_from_text(text: String) -> String {
  let assert Ok(#(_, after)) = string.split_once(text, "\"decision_id\":\"")
  let assert Ok(#(id, _)) = string.split_once(after, "\"")
  id
}

pub fn prepare_defaults_lease_epoch_when_absent_from_spec_test() {
  let path =
    prepared_path(
      "cli-test-lease-default-" <> int.to_string(board.system_time_us()),
    )
  let assert Ok(text) = board.file_read(path)
  string.contains(text, "\"lease_epoch\":\"not claimed\"") |> should.be_true
}

pub fn prepare_missing_required_field_is_a_clear_error_test() {
  let slug = "cli-test-missing-field-" <> int.to_string(board.system_time_us())
  let spec_path = write(slug <> "-spec.json", spec_missing_task)
  let assert Error(message) = cli.write_prepared(root(), slug, spec_path)
  string.contains(message, "spec error") |> should.be_true
  string.contains(message, spec_path) |> should.be_true
}

pub fn prepare_missing_spec_file_is_a_clear_error_test() {
  let slug =
    "cli-test-missing-spec-file-" <> int.to_string(board.system_time_us())
  let assert Error(message) =
    cli.write_prepared(root(), slug, root() <> "/does-not-exist.json")
  string.contains(message, "spec read error") |> should.be_true
}

// ---- complete ----

pub fn complete_flips_phase_adds_completed_and_preserves_forecast_test() {
  let slug = "cli-test-complete-" <> int.to_string(board.system_time_us())
  let path = prepared_path(slug)
  let assert Ok(before) = cli.read_forecast(path)

  let completion_path = write(slug <> "-completion.json", valid_completion)
  let assert Ok(record) = board.file_read(path)
  let decision_id_before = decision_id_from_text(record)

  let assert Ok(returned_id) = cli.complete_record(path, completion_path)
  returned_id |> should.equal(decision_id_before)

  cli.read_phase(path) |> should.equal(Ok("completed"))

  let assert Ok(completed) = cli.read_completed(path)
  completed.outcome |> should.equal("succeeded")
  completed.forecast_resolution |> should.equal("p=0.7 realized")
  completed.observed_actions
  |> should.equal(["merged cleanly", "gates passed"])
  completed.consumed_tokens |> should.equal("0 for deterministic steps")
  completed.consumed_usd |> should.equal(0.0)

  let assert Ok(after) = cli.read_forecast(path)
  after |> should.equal(before)
}

pub fn complete_refuses_a_record_that_is_already_completed_test() {
  let slug =
    "cli-test-already-completed-" <> int.to_string(board.system_time_us())
  let path = prepared_path(slug)
  let completion_path = write(slug <> "-completion.json", valid_completion)
  let assert Ok(_) = cli.complete_record(path, completion_path)

  let assert Error(message) = cli.complete_record(path, completion_path)
  string.contains(message, "already completed") |> should.be_true
  // Refusal does not disturb the already-completed record.
  cli.read_phase(path) |> should.equal(Ok("completed"))
}

pub fn complete_refuses_a_file_that_is_not_a_decision_record_test() {
  let slug = "cli-test-wrong-carrier-" <> int.to_string(board.system_time_us())
  let bad_path =
    write(
      slug <> "-not-a-record.json",
      "{\"carrier\": \"something-else/v1\", \"phase\": \"prepared\"}",
    )
  let completion_path = write(slug <> "-completion.json", valid_completion)
  let assert Error(message) = cli.complete_record(bad_path, completion_path)
  string.contains(message, "not a uos-decision-record/v1") |> should.be_true
}

pub fn complete_missing_completion_file_is_a_clear_error_test() {
  let slug =
    "cli-test-missing-completion-" <> int.to_string(board.system_time_us())
  let path = prepared_path(slug)
  let assert Error(message) =
    cli.complete_record(path, root() <> "/does-not-exist-completion.json")
  string.contains(message, "completion read error") |> should.be_true
}
