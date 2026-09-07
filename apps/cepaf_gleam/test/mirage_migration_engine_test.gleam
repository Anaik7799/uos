import cepaf_gleam/services/mirage_migration_engine.{
  Classified, Discovered, Mapped, admission_status_to_string, advance_candidate,
  advance_stage, estimate_basis_to_string, evaluate_non_negotiable_safety,
  find_candidate, get_migration_candidates, stage_to_string,
  total_projected_ram_savings, verified_admitted_count,
}
import gleam/list
import gleeunit/should

pub fn migration_candidates_count_test() {
  get_migration_candidates()
  |> list.length
  |> should.equal(7)
}

pub fn total_ram_value_is_explicitly_projected_test() {
  get_migration_candidates()
  |> total_projected_ram_savings
  |> should.equal(1092)
}

pub fn candidate_fields_are_declared_projections_test() {
  let assert Ok(candidate) =
    get_migration_candidates()
    |> find_candidate("MIG-01-INGRESS")

  candidate.name |> should.equal("Edge HTTP/TLS Ingress Proxy")
  candidate.target_sil_level |> should.equal(5)
  candidate.projected_ram_saving_mb |> should.equal(168)
  candidate.estimate_basis
  |> estimate_basis_to_string
  |> should.equal("configured_projection")
  candidate.admission
  |> admission_status_to_string
  |> should.equal("unverified")
}

pub fn candidate_lookup_rejects_unknown_id_test() {
  get_migration_candidates()
  |> find_candidate("MIG-NONEXISTENT")
  |> should.be_error()
}

pub fn stage_progression_fails_closed_at_mapping_test() {
  advance_stage(Discovered) |> should.equal(Classified)
  advance_stage(Classified) |> should.equal(Mapped)
  advance_stage(Mapped) |> should.equal(Mapped)
  stage_to_string(Mapped) |> should.equal("Mapped")
}

pub fn configured_candidate_cannot_self_admit_test() {
  let assert Ok(candidate) =
    get_migration_candidates()
    |> find_candidate("MIG-06-FORWARD")
  candidate.status |> should.equal(Mapped)
  advance_candidate(candidate).status |> should.equal(Mapped)
}

pub fn non_negotiable_safety_test() {
  [
    "BEAM OTP Supervisor",
    "uos_sup.gleam root",
    "Modular MAX inference",
    "Root NVMe 25503L801736",
    "Standalone Jujutsu (.jj/)",
  ]
  |> list.each(fn(target) {
    target
    |> evaluate_non_negotiable_safety
    |> should.be_error()
  })

  "Mirage-DNS Recursive Resolver"
  |> evaluate_non_negotiable_safety
  |> should.be_ok()
}

pub fn configured_catalog_has_zero_verified_admissions_test() {
  get_migration_candidates()
  |> verified_admitted_count
  |> should.equal(0)
}
