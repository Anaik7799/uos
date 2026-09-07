//// FMEA (Failure Mode and Effects Analysis) model for the uos_tui app and
//// its build swarm: failure modes with severity/occurrence/detection
//// scoring, risk priority number (RPN), and markdown export.
////
//// Reference: FMEA scoring per AIAG-VDA convention (1..10 scales).
//// STAMP id: SC-TUI-W07-001

import gleam/int
import gleam/list
import gleam/string

pub type FailureMode {
  FailureMode(
    id: String,
    item: String,
    mode: String,
    effect: String,
    cause: String,
    severity: Int,
    occurrence: Int,
    detection: Int,
    mitigation: String,
    status: String,
  )
}

pub fn rpn(f: FailureMode) -> Int {
  f.severity * f.occurrence * f.detection
}

pub fn model() -> List(FailureMode) {
  [
    FailureMode(
      "FM-01",
      "uos_tui/frame",
      "Frame overflow",
      "Blit writes cells outside the frame region, corrupting output",
      "Region math not clamped before blit",
      7,
      3,
      4,
      "frame.blit clamps write region to frame bounds",
      "mitigated",
    ),
    FailureMode(
      "FM-02",
      "uos_tui/event",
      "Key parser unknown sequence",
      "Unrecognized escape sequence dropped or misparsed as a wrong key",
      "Terminal emits a vendor-specific CSI sequence",
      4,
      5,
      5,
      "parse_keys falls back to a raw Key on unknown sequence",
      "mitigated",
    ),
    FailureMode(
      "FM-03",
      "uos_tui/live",
      "Raw mode not restored",
      "Terminal left in raw mode after crash or signal, unusable shell",
      "restore_terminal not called on all exit paths",
      8,
      2,
      3,
      "signal-safe teardown registered before enter_raw",
      "mitigated",
    ),
    FailureMode(
      "FM-04",
      "uos_tui/app",
      "Focus lost after screen pop",
      "No widget focused after Screen pop, keys silently dropped",
      "focus_chain not recomputed on screen stack change",
      5,
      4,
      6,
      "app.step recomputes focus_chain after every screen transition",
      "open",
    ),
    FailureMode(
      "FM-05",
      "uos_tui/app",
      "Intent emitted twice",
      "A single key event dispatches the same intent twice",
      "Both key-down and repeat handlers fire emit_intent",
      6,
      3,
      5,
      "dedupe intents by event sequence number",
      "open",
    ),
    FailureMode(
      "FM-06",
      "uos_tui/live",
      "Telemetry id zero",
      "trace_id defaults to 0, breaking correlation across spans",
      "monotonic_micros seeded before clock sync",
      3,
      2,
      6,
      "utc_now / monotonic_micros validated non-zero at start",
      "mitigated",
    ),
    FailureMode(
      "FM-07",
      "uos_tui/cockpit",
      "Ledger decode failure",
      "Malformed JSON from ledger crashes the decode path",
      "Upstream writer emits partial or truncated JSON",
      6,
      3,
      4,
      "json.parse failure returns Result Error, never let assert",
      "mitigated",
    ),
    FailureMode(
      "FM-08",
      "swarm/verifier",
      "Verifier false green",
      "Verifier reports PASS while gleam test actually failed",
      "Exit code of a piped command not checked",
      9,
      2,
      3,
      "verifier checks the exact process exit code, not stdout text",
      "mitigated",
    ),
    FailureMode(
      "FM-09",
      "swarm/worker",
      "Worker edits shared module",
      "Two workers write to the same file, one overwrite lost",
      "Worker ownership boundary not enforced before write",
      7,
      3,
      3,
      "verifier checks jj diff --summary against declared ownership",
      "mitigated",
    ),
    FailureMode(
      "FM-10",
      "swarm/workspace",
      "Stale jj workspace",
      "Worker operates on a workspace pointer behind the shared repo",
      "Sibling workspace not synced before slice starts",
      5,
      4,
      5,
      "workspace update-stale run before each slice dispatch",
      "open",
    ),
    FailureMode(
      "FM-11",
      "swarm/L0",
      "Token budget overrun",
      "Worker exceeds token budget mid-slice, output truncated",
      "Slice scope too broad for a single-pass worker",
      4,
      5,
      6,
      "L0 supervisor caps slice scope before dispatch",
      "open",
    ),
    FailureMode(
      "FM-12",
      "swarm/L0",
      "Integration conflict",
      "Two verified slices conflict on merge, integration blocked",
      "Slices not serialized through the integration gate",
      6,
      3,
      4,
      "integration gates are strictly serialized per L0 policy",
      "mitigated",
    ),
  ]
}

fn unique_strings(xs: List(String)) -> Bool {
  list.length(xs) == list.length(list.unique(xs))
}

pub fn validate(rows: List(FailureMode)) -> Result(Nil, String) {
  let ids = list.map(rows, fn(f) { f.id })
  case unique_strings(ids) {
    False -> Error("duplicate failure mode id")
    True -> {
      let scores_ok =
        list.all(rows, fn(f) {
          f.severity >= 1
          && f.severity <= 10
          && f.occurrence >= 1
          && f.occurrence <= 10
          && f.detection >= 1
          && f.detection <= 10
        })
      case scores_ok {
        False -> Error("severity/occurrence/detection out of 1..10 range")
        True -> Ok(Nil)
      }
    }
  }
}

pub fn top(rows: List(FailureMode), n: Int) -> List(FailureMode) {
  rows
  |> list.sort(fn(a, b) { int.compare(rpn(b), rpn(a)) })
  |> list.take(n)
}

pub fn to_markdown(rows: List(FailureMode)) -> String {
  let header =
    "## FMEA\n"
    <> "| id | item | mode | effect | cause | s | o | d | rpn | mitigation | status |\n"
    <> "|---|---|---|---|---|---|---|---|---|---|---|\n"

  let body =
    string.join(
      list.map(rows, fn(f) {
        "| "
        <> f.id
        <> " | "
        <> f.item
        <> " | "
        <> f.mode
        <> " | "
        <> f.effect
        <> " | "
        <> f.cause
        <> " | "
        <> int.to_string(f.severity)
        <> " | "
        <> int.to_string(f.occurrence)
        <> " | "
        <> int.to_string(f.detection)
        <> " | "
        <> int.to_string(rpn(f))
        <> " | "
        <> f.mitigation
        <> " | "
        <> f.status
        <> " |"
      }),
      "\n",
    )

  header <> body
}
