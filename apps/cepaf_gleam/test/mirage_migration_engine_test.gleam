// Unified Operational System (UOS) - MirageOS Subsystem Migration Engine Tests
// Authority: contracts/rules/mirage-migration-policy.md - SC-MIRAGE-MIGRATE-001

import cepaf_gleam/services/mirage_migration_engine.{
  Admitted, Classified, Discovered, Implemented, Mapped, Verified,
  advance_candidate, advance_stage, admitted_count,
  evaluate_non_negotiable_safety, find_candidate, get_migration_candidates,
  stage_to_string, total_ram_savings,
}
import gleeunit/should

pub fn migration_candidates_count_test() {
  let candidates = get_migration_candidates()
  list_length(candidates) |> should.equal(7)
}

pub fn total_ram_savings_test() {
  let candidates = get_migration_candidates()
  let savings = total_ram_savings(candidates)
  // 168 + 234 + 56 + 28 + 96 + 74 + 436 = 1092 MB
  savings |> should.equal(1092)
}

pub fn candidate_lookup_test() {
  let candidates = get_migration_candidates()
  case find_candidate(candidates, "MIG-01-INGRESS") {
    Ok(c) -> {
      c.name |> should.equal("Edge HTTP/TLS Ingress Proxy")
      c.sil_level |> should.equal(5)
      c.ram_saving_mb |> should.equal(168)
    }
    Error(_) -> should.fail()
  }

  case find_candidate(candidates, "MIG-NONEXISTENT") {
    Ok(_) -> should.fail()
    Error(_) -> Nil
  }
}

pub fn stage_progression_test() {
  advance_stage(Discovered) |> should.equal(Classified)
  advance_stage(Classified) |> should.equal(Mapped)
  advance_stage(Mapped) |> should.equal(Implemented)
  advance_stage(Implemented) |> should.equal(Verified)
  advance_stage(Verified) |> should.equal(Admitted)
  advance_stage(Admitted) |> should.equal(Admitted)

  stage_to_string(Discovered) |> should.equal("Discovered")
  stage_to_string(Admitted) |> should.equal("Admitted")
}

pub fn advance_candidate_test() {
  let candidates = get_migration_candidates()
  case find_candidate(candidates, "MIG-06-FORWARD") {
    Ok(c) -> {
      c.status |> should.equal(Mapped)
      let advanced = advance_candidate(c)
      advanced.status |> should.equal(Implemented)
    }
    Error(_) -> should.fail()
  }
}

pub fn non_negotiable_safety_test() {
  // Forbidden targets must return Error
  evaluate_non_negotiable_safety("BEAM OTP Supervisor")
  |> should.be_error()

  evaluate_non_negotiable_safety("uos_sup.gleam root")
  |> should.be_error()

  evaluate_non_negotiable_safety("Modular MAX inference")
  |> should.be_error()

  evaluate_non_negotiable_safety("Root NVMe 25503L801736")
  |> should.be_error()

  evaluate_non_negotiable_safety("Standalone Jujutsu (.jj/)")
  |> should.be_error()

  // Allowed candidate targets must return Ok
  evaluate_non_negotiable_safety("Solo5-SPT Ingress Proxy")
  |> should.be_ok()

  evaluate_non_negotiable_safety("Mirage-DNS Recursive Resolver")
  |> should.be_ok()
}

pub fn admitted_count_test() {
  let candidates = get_migration_candidates()
  let admitted = admitted_count(candidates)
  // MIG-02-SANDBOX and MIG-04-CRYPTO are already Admitted
  admitted |> should.equal(2)
}

fn list_length(l: List(a)) -> Int {
  case l {
    [] -> 0
    [_, ..rest] -> 1 + list_length(rest)
  }
}
