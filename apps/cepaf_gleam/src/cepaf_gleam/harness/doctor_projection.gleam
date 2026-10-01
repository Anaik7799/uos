//// apps/cepaf_gleam/src/cepaf_gleam/harness/doctor_projection.gleam
//// Truthful Doctor & EV-Cycle Diagnostic Pure Projection
//// Contract Reference: SC-PROVENANCE-001, SC-CHECKLIST-001, SC-COG-001

import cepaf_gleam/intent/denotational
import gleam/int
import gleam/json

pub type DoctorProjection {
  DoctorProjection(
    admitted_ev_ceiling: Int,
    unadmitted_range: String,
    admission_status: String,
    test_state: String,
    checklist_gate_state: String,
    zero_muda_compliance: String,
    vcs_architecture: String,
    doctor_status: String,
    observed_in_query: Bool,
  )
}

pub fn project() -> DoctorProjection {
  DoctorProjection(
    admitted_ev_ceiling: denotational.admitted_ev_ceiling,
    unadmitted_range: "EV-94..EV-109",
    admission_status: "NOT_ADMITTED (pending sovereign review; INV-PROV-05)",
    test_state: "UNOBSERVED (requires candidate-bound execution; no ad-hoc green)",
    checklist_gate_state: "UNOBSERVED (requires explicit G-CHECKLIST run)",
    zero_muda_compliance: "UNOBSERVED (requires candidate-bound G-MUDA gate run)",
    vcs_architecture: "Standalone Jujutsu Monorepo (`.jj/`)",
    doctor_status: "UNOBSERVED_RUNTIME",
    observed_in_query: False,
  )
}

pub fn to_markdown(p: DoctorProjection) -> String {
  "🩺 *UOS Doctor & EV-Cycle Diagnostics*\n\n"
  <> "• *Admitted EV Ceiling:* EV-"
  <> int.to_string(p.admitted_ev_ceiling)
  <> " (SC-PROVENANCE-001)\n"
  <> "• *Unadmitted Cycles:* "
  <> p.unadmitted_range
  <> " ("
  <> p.admission_status
  <> ")\n"
  <> "• *Verified Cycles:* UNOBSERVED (runtime verified count unobserved in query)\n"
  <> "• *Test Suite Results:* "
  <> p.test_state
  <> "\n"
  <> "• *Checklist Gate (G-CHECKLIST):* "
  <> p.checklist_gate_state
  <> "\n"
  <> "• *Zero-Muda Compliance:* "
  <> p.zero_muda_compliance
  <> "\n"
  <> "• *VCS Architecture:* "
  <> p.vcs_architecture
  <> "\n"
  <> "• *Runtime Assessment:* "
  <> p.doctor_status
}

pub fn to_json(p: DoctorProjection) -> String {
  json.object([
    #("doctor_status", json.string(p.doctor_status)),
    #("admitted_ev_ceiling", json.int(p.admitted_ev_ceiling)),
    #("ev_cycles_verified", json.null()),
    #("unadmitted_range", json.string(p.unadmitted_range)),
    #("admission_status", json.string("NOT_ADMITTED")),
    #("checks_passed", json.string("UNOBSERVED")),
    #("gate", json.string("UNOBSERVED")),
    #("test_state", json.string(p.test_state)),
    #("zero_muda", json.null()),
    #("observed_in_query", json.bool(p.observed_in_query)),
  ])
  |> json.to_string
}
