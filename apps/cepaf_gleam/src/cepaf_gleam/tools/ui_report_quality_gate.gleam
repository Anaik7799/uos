//// Comprehensive UI report quality gate.
//// This module gives hooks and operators a stable entry point while delegating
//// the current closure-bundle implementation to ui_diagram_quality_gate.
//// Run from lib/cepaf_gleam with:
////   gleam run -m cepaf_gleam/tools/ui_report_quality_gate

import cepaf_gleam/tools/ui_diagram_quality_gate

pub fn main() {
  ui_diagram_quality_gate.main()
}
