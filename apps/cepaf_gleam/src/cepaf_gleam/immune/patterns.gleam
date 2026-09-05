import gleam/list
import gleam/string

pub type FailurePattern {
  FailurePattern(id: String, match_string: String, severity: Int)
}

pub fn detect_anomalies(
  log_line: String,
  patterns: List(FailurePattern),
) -> List(FailurePattern) {
  list.filter(patterns, fn(p) { string.contains(log_line, p.match_string) })
}

pub fn default_patterns() -> List(FailurePattern) {
  [
    FailurePattern("P-001", "Segmentation fault", 10),
    FailurePattern("P-002", "Connection refused", 5),
    FailurePattern("P-003", "Out of memory", 8),
    FailurePattern("P-004", "Safety kernel violation", 10),
  ]
}
