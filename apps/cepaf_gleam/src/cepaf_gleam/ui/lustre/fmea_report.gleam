//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/ui/lustre/fmea_report</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-FMEA-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Lustre page: FMEA report display — failure modes with RPN scoring.

import gleam/list
import gleam/option.{type Option, None, Some}

pub type FmeaEntry {
  FmeaEntry(
    mode: String,
    severity: Int,
    occurrence: Int,
    detection: Int,
    rpn: Int,
    mitigation: String,
    category: String,
  )
}

pub type FmeaReportModel {
  FmeaReportModel(
    entries: List(FmeaEntry),
    sort_by: String,
    filter_category: Option(String),
    total_rpn: Int,
    critical_count: Int,
    loading: Bool,
    error: Option(String),
  )
}

pub type FmeaReportMsg {
  EntriesLoaded(List(FmeaEntry))
  SortBy(String)
  FilterCategory(Option(String))
  RefreshFmea
  ErrorReceived(String)
}

pub fn init() -> FmeaReportModel {
  FmeaReportModel(
    entries: [],
    sort_by: "rpn",
    filter_category: None,
    total_rpn: 0,
    critical_count: 0,
    loading: False,
    error: None,
  )
}

pub fn update(model: FmeaReportModel, msg: FmeaReportMsg) -> FmeaReportModel {
  case msg {
    EntriesLoaded(entries) -> {
      let total = list.fold(entries, 0, fn(acc, e) { acc + e.rpn })
      let critical = list.count(entries, fn(e) { e.rpn >= 200 })
      FmeaReportModel(..model, entries: entries, total_rpn: total,
        critical_count: critical, loading: False)
    }
    SortBy(field) -> FmeaReportModel(..model, sort_by: field)
    FilterCategory(cat) -> FmeaReportModel(..model, filter_category: cat)
    RefreshFmea -> FmeaReportModel(..model, loading: True)
    ErrorReceived(e) -> FmeaReportModel(..model, error: Some(e), loading: False)
  }
}

pub fn rpn_band(rpn: Int) -> String {
  case rpn >= 200 {
    True -> "CRITICAL"
    False -> case rpn >= 100 {
      True -> "HIGH"
      False -> case rpn >= 50 {
        True -> "MODERATE"
        False -> "LOW"
      }
    }
  }
}

pub fn filtered_entries(model: FmeaReportModel) -> List(FmeaEntry) {
  case model.filter_category {
    None -> model.entries
    Some(cat) -> list.filter(model.entries, fn(e) { e.category == cat })
  }
}

// =============================================================================
// NIF-backed data loading (SC-WIRE-001: real ops data)
// =============================================================================

import cepaf_gleam/c3i/nif
import gleam/dynamic/decode
import gleam/json

/// Load real FMEA report from NIF → Rust → TransactionSummary failure analysis
pub fn load_from_nif() -> FmeaReportModel {
  let raw = nif.fmea_report()
  let decoder = {
    use total <- decode.field("total_failures", decode.int)
    use rate <- decode.field("failure_rate", decode.float)
    decode.success(#(total, rate))
  }
  let #(total, _rate) = case json.parse(raw, decoder) {
    Ok(t) -> t
    Error(_) -> #(0, 0.0)
  }
  let model = init()
  FmeaReportModel(..model, total_rpn: total, loading: False)
}
