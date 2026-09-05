//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/testing/rca</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-RCA-001, SC-OBS-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Automated 5-Level RCA (Root Cause Analysis) Template Generator.
//// Hooks into build failures to provide deep diagnostic context.

import gleam/io
import gleam/string

pub type RcaLevel {
  SurfaceIssue
  ProximateCause
  ContributingFactor
  SystemicIssue
  RootCause
}

pub type RcaTemplate {
  RcaTemplate(
    error_id: String,
    level1: String,
    level2: String,
    level3: String,
    level4: String,
    level5: String,
  )
}

/// Generate a blank 5-Level RCA template for a specific error.
pub fn generate_rca_template(error_id: String, summary: String) -> RcaTemplate {
  RcaTemplate(
    error_id: error_id,
    level1: "Surface: " <> summary,
    level2: "Proximate: [Pending Agent Analysis]",
    level3: "Contributing: [Pending Fractal Search]",
    level4: "Systemic: [Pending Pattern Recognition]",
    level5: "Root: [Pending Semantic Inference]",
  )
}

/// Emit the RCA template as a formatted diagnostic block.
pub fn format_rca(template: RcaTemplate) -> String {
  string.join(
    [
      "--- FRACTAL RCA: " <> template.error_id <> " ---",
      "L1: " <> template.level1,
      "L2: " <> template.level2,
      "L3: " <> template.level3,
      "L4: " <> template.level4,
      "L5: " <> template.level5,
      "-----------------------------------",
    ],
    "\n",
  )
}

/// Log the RCA to standard output for the TUI dashboard.
pub fn log_rca(template: RcaTemplate) {
  io.println(format_rca(template))
}
