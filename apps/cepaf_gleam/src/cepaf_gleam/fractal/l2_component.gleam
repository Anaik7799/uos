//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/fractal/l2_component</module></identity>
////   <fractal-topology><layer>L2_COMPONENT</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GRID-001, SC-COMONAD-001</stamp-controls></compliance>
//// </c3i-module>
////
//// L2 Component: reusable UI widgets — badges, data grids, form elements.

import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}

/// Badge severity for status indicators.
pub type BadgeSeverity {
  Healthy
  Degraded
  BadgeCritical
  Unknown
  Info
}

pub type Badge {
  Badge(label: String, severity: BadgeSeverity, tooltip: Option(String))
}

/// Data grid column definition.
pub type Column {
  Column(key: String, label: String, sortable: Bool, width: Option(Int))
}

/// Data grid row — key-value pairs.
pub type Row {
  Row(id: String, cells: List(#(String, String)))
}

/// Data grid state.
pub type DataGridState {
  DataGridState(
    columns: List(Column),
    rows: List(Row),
    sort_column: Option(String),
    sort_ascending: Bool,
    selected_row: Option(String),
    page: Int,
    page_size: Int,
  )
}

pub fn initial_grid(columns: List(Column)) -> DataGridState {
  DataGridState(
    columns: columns,
    rows: [],
    sort_column: None,
    sort_ascending: True,
    selected_row: None,
    page: 0,
    page_size: 25,
  )
}

pub fn set_rows(state: DataGridState, rows: List(Row)) -> DataGridState {
  DataGridState(..state, rows: rows)
}

pub fn select_row(state: DataGridState, row_id: String) -> DataGridState {
  DataGridState(..state, selected_row: Some(row_id))
}

pub fn sort_by(state: DataGridState, column_key: String) -> DataGridState {
  let ascending = case state.sort_column {
    Some(k) if k == column_key -> !state.sort_ascending
    _ -> True
  }
  DataGridState(
    ..state,
    sort_column: Some(column_key),
    sort_ascending: ascending,
  )
}

pub fn total_pages(state: DataGridState) -> Int {
  let total = list.length(state.rows)
  case state.page_size > 0 {
    True -> { total + state.page_size - 1 } / state.page_size
    False -> 1
  }
}

pub fn severity_to_string(sev: BadgeSeverity) -> String {
  case sev {
    Healthy -> "healthy"
    Degraded -> "degraded"
    BadgeCritical -> "critical"
    Unknown -> "unknown"
    Info -> "info"
  }
}

pub fn badge_to_json(badge: Badge) -> json.Json {
  json.object([
    #("label", json.string(badge.label)),
    #("severity", json.string(severity_to_string(badge.severity))),
    #("tooltip", case badge.tooltip {
      Some(t) -> json.string(t)
      None -> json.null()
    }),
  ])
}
