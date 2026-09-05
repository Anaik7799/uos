import cepaf_gleam/verification/algebraic_sheaf_harmonizer.{
  GluingInconsistency, GluingSuccess, LocalSection, check_pairwise_agreement,
  glue_sections,
}
import gleeunit/should

pub fn pairwise_section_agreement_test() {
  let s1 = LocalSection(page_route: "/dashboard", shared_state_digest: "sha256-state-alpha")
  let s2 = LocalSection(page_route: "/settings", shared_state_digest: "sha256-state-alpha")
  check_pairwise_agreement(s1, s2)
  |> should.be_true
}

pub fn pairwise_section_disagreement_test() {
  let s1 = LocalSection(page_route: "/dashboard", shared_state_digest: "sha256-state-alpha")
  let s2 = LocalSection(page_route: "/telemetry", shared_state_digest: "sha256-state-beta")
  check_pairwise_agreement(s1, s2)
  |> should.be_false
}

pub fn glue_consistent_sections_test() {
  let sections = [
    LocalSection(page_route: "/dashboard", shared_state_digest: "canonical-hash-xyz"),
    LocalSection(page_route: "/telemetry", shared_state_digest: "canonical-hash-xyz"),
    LocalSection(page_route: "/controls", shared_state_digest: "canonical-hash-xyz"),
  ]
  glue_sections(sections)
  |> should.equal(GluingSuccess("canonical-hash-xyz"))
}

pub fn glue_inconsistent_sections_test() {
  let sections = [
    LocalSection(page_route: "/dashboard", shared_state_digest: "canonical-hash-xyz"),
    LocalSection(page_route: "/telemetry", shared_state_digest: "divergent-hash-123"),
  ]
  glue_sections(sections)
  |> should.equal(GluingInconsistency("Sections disagree on mutual boundary"))
}

pub fn glue_empty_sections_test() {
  glue_sections([])
  |> should.equal(GluingInconsistency("Empty section list"))
}
