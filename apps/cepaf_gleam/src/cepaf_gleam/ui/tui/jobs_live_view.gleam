/// TUI ANSI renderer for the /jobs/live page (SC-GLM-UI-007).
/// Triple-interface sibling of `ui/lustre/jobs_live.gleam`.
///
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-007, SC-SCHED-TELE-005
import cepaf_gleam/ui/lustre/jobs_live.{type JobRow, type JobsLiveModel}
import gleam/list
import gleam/string

pub fn render(m: JobsLiveModel) -> String {
  let header =
    "══ /jobs/live ══ "
    <> jobs_live.headline(m)
    <> "\n"
    <> "URN                                         QUEUE        STATE       WORKER\n"
    <> "──────────────────────────────────────────  ───────────  ──────────  ──────────────\n"
  let body =
    m.rows
    |> list.map(render_row)
    |> string.concat
  header <> body
}

fn render_row(r: JobRow) -> String {
  let state_c = colorize(r.state)
  pad(r.urn, 44)
  <> "  "
  <> pad(r.queue, 11)
  <> "  "
  <> state_c
  <> "  "
  <> r.worker
  <> "\n"
}

fn colorize(state: String) -> String {
  case state {
    "completed" -> "\u{001b}[32m" <> pad(state, 10) <> "\u{001b}[0m"
    "failed" -> "\u{001b}[31m" <> pad(state, 10) <> "\u{001b}[0m"
    "timeout" -> "\u{001b}[35m" <> pad(state, 10) <> "\u{001b}[0m"
    "cancelled" -> "\u{001b}[33m" <> pad(state, 10) <> "\u{001b}[0m"
    "executing" -> "\u{001b}[36m" <> pad(state, 10) <> "\u{001b}[0m"
    _ -> pad(state, 10)
  }
}

fn pad(s: String, width: Int) -> String {
  let n = string.length(s)
  case n >= width {
    True -> string.slice(s, 0, width)
    False -> s <> string.repeat(" ", width - n)
  }
}
