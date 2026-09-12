// STAMP: SC-GLM-UI-001, SC-FMEA-001
import cepaf_gleam/ui/lustre/fmea_report.{type FmeaEntry, type FmeaReportModel}
import gleam/list
import gleam/string

pub fn render(model: FmeaReportModel) -> String {
  let header = "\u{001b}[1;36m▌ FMEA Report\u{001b}[0m  Total RPN: " <> int_str(model.total_rpn) <> " | Critical: " <> int_str(model.critical_count)
  let table_hdr = "\u{001b}[90m  Mode                      S  O  D  RPN   Band      Mitigation\u{001b}[0m"
  let entries = fmea_report.filtered_entries(model)
  let rows = list.map(entries, render_entry) |> string.join("\n")
  string.join([header, "", table_hdr, rows], "\n")
}

fn render_entry(e: FmeaEntry) -> String {
  let color = case e.rpn >= 200 {
    True -> "\u{001b}[31m"
    False -> case e.rpn >= 100 {
      True -> "\u{001b}[33m"
      False -> "\u{001b}[0m"
    }
  }
  color <> "  " <> pad(e.mode, 26) <> pad(int_str(e.severity), 3) <> pad(int_str(e.occurrence), 3) <> pad(int_str(e.detection), 3) <> pad(int_str(e.rpn), 6) <> pad(fmea_report.rpn_band(e.rpn), 10) <> e.mitigation <> "\u{001b}[0m"
}

fn pad(s: String, w: Int) -> String {
  let l = string.length(s)
  case l >= w {
    True -> s
    False -> s <> string.repeat(" ", w - l)
  }
}

@external(erlang, "erlang", "integer_to_binary")
fn int_str(i: Int) -> String
