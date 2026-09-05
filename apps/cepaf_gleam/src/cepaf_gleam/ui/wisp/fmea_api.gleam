// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-FMEA-001
import cepaf_gleam/ui/lustre/fmea_report.{type FmeaEntry, type FmeaReportModel}
import gleam/json
import gleam/list

pub fn report_json(model: FmeaReportModel) -> json.Json {
  let entries = fmea_report.filtered_entries(model)
  json.object([
    #("entries", json.array(entries, entry_json)),
    #("total_rpn", json.int(model.total_rpn)),
    #("critical_count", json.int(model.critical_count)),
    #("count", json.int(list.length(entries))),
  ])
}

fn entry_json(e: FmeaEntry) -> json.Json {
  json.object([
    #("mode", json.string(e.mode)),
    #("severity", json.int(e.severity)),
    #("occurrence", json.int(e.occurrence)),
    #("detection", json.int(e.detection)),
    #("rpn", json.int(e.rpn)),
    #("band", json.string(fmea_report.rpn_band(e.rpn))),
    #("mitigation", json.string(e.mitigation)),
    #("category", json.string(e.category)),
  ])
}
