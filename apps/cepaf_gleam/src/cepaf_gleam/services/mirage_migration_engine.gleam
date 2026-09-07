// Unified Operational System (UOS) - MirageOS Subsystem Migration Projections
// Authority: contracts/rules/mirage-migration-policy.md - SC-MIRAGE-MIGRATE-001

import gleam/list
import gleam/string

/// Catalog progress stops at Mapped until an external evidence authority exists.
/// This module does not mint verification or admission authority.
pub type MigrationStage {
  Discovered
  Classified
  Mapped
}

/// Every value in the built-in catalog is a planning projection. It is not a
/// runtime measurement or an admission receipt.
pub type EstimateBasis {
  ConfiguredProjection(reason: String)
}

pub type AdmissionStatus {
  AdmissionUnverified(reason: String)
}

pub type MigrationCandidate {
  MigrationCandidate(
    id: String,
    name: String,
    layer: String,
    current_tech: String,
    mirage_target: String,
    target_sil_level: Int,
    projected_ram_saving_mb: Int,
    projected_speedup_pct: Float,
    status: MigrationStage,
    estimate_basis: EstimateBasis,
    admission: AdmissionStatus,
  )
}

const projection_reason = "Configured planning estimate; no runtime benchmark receipt is attached"

const admission_reason = "No empirical benchmark and formal conformance receipts are attached"

pub fn stage_to_string(stage: MigrationStage) -> String {
  case stage {
    Discovered -> "Discovered"
    Classified -> "Classified"
    Mapped -> "Mapped"
  }
}

pub fn estimate_basis_to_string(basis: EstimateBasis) -> String {
  case basis {
    ConfiguredProjection(_) -> "configured_projection"
  }
}

pub fn estimate_basis_reason(basis: EstimateBasis) -> String {
  case basis {
    ConfiguredProjection(reason) -> reason
  }
}

pub fn admission_status_to_string(status: AdmissionStatus) -> String {
  case status {
    AdmissionUnverified(_) -> "unverified"
  }
}

pub fn admission_status_reason(status: AdmissionStatus) -> String {
  case status {
    AdmissionUnverified(reason) -> reason
  }
}

pub fn get_migration_candidates() -> List(MigrationCandidate) {
  [
    projection(
      "MIG-01-INGRESS",
      "Edge HTTP/TLS Ingress Proxy",
      "L4",
      "Mist HTTP / External Nginx Reverse Proxy",
      "Solo5-SPT + paf / ocaml-tls / mirage-crypto-rng",
      5,
      168,
      99.4,
    ),
    projection(
      "MIG-02-SANDBOX",
      "Isolated Ephemeral Tool Sandbox",
      "L3",
      "Podman Rootless OCI Container",
      "Solo5-SPT Ephemeral Unikernel (Micro-Sandbox)",
      6,
      234,
      99.1,
    ),
    projection(
      "MIG-03-DNS",
      "Deterministic DNS Recursive Resolver",
      "L2",
      "Host Glibc getaddrinfo / /etc/resolv.conf",
      "Solo5-SPT + mirage-dns / DNS-over-TLS (DoT)",
      5,
      56,
      98.3,
    ),
    projection(
      "MIG-04-CRYPTO",
      "Cryptographic Token & Receipt Authority",
      "L1",
      "C-NIF / Rust OpenSSL Bindings",
      "Hermes mirage-crypto / mirage-crypto-ec (Pure OCaml)",
      6,
      28,
      100.0,
    ),
    projection(
      "MIG-05-LEDGER",
      "Immutable Merkle DAG Evidence Store",
      "L5",
      "SQLite WAL Files + Raw JSONL Ledgers",
      "Irmin Merkle DAG / Wodan Block Engine",
      6,
      96,
      88.0,
    ),
    projection(
      "MIG-06-FORWARD",
      "Zenoh Micro-Packet Forwarder",
      "L6",
      "Zenoh Rust Daemon (Port 7447)",
      "Solo5-SPT Flow-Forwarder Enclave (Pure OCaml)",
      4,
      74,
      98.2,
    ),
    projection(
      "MIG-07-SOLVER",
      "Bounded Z3 Gospel Verification Sandbox",
      "L0",
      "Host OS Subprocess Fork with Timeout",
      "Solo5-SPT Memory-Capped Micro-Sandbox (64MB Hard Cap)",
      5,
      436,
      95.7,
    ),
  ]
}

fn projection(
  id: String,
  name: String,
  layer: String,
  current_tech: String,
  mirage_target: String,
  target_sil_level: Int,
  projected_ram_saving_mb: Int,
  projected_speedup_pct: Float,
) -> MigrationCandidate {
  MigrationCandidate(
    id: id,
    name: name,
    layer: layer,
    current_tech: current_tech,
    mirage_target: mirage_target,
    target_sil_level: target_sil_level,
    projected_ram_saving_mb: projected_ram_saving_mb,
    projected_speedup_pct: projected_speedup_pct,
    status: Mapped,
    estimate_basis: ConfiguredProjection(projection_reason),
    admission: AdmissionUnverified(admission_reason),
  )
}

pub fn total_projected_ram_savings(
  candidates: List(MigrationCandidate),
) -> Int {
  list.fold(candidates, 0, fn(acc, candidate) {
    acc + candidate.projected_ram_saving_mb
  })
}

/// The configured catalog contains no admission receipts, so it cannot report
/// any verified admissions.
pub fn verified_admitted_count(candidates: List(MigrationCandidate)) -> Int {
  list.count(candidates, fn(candidate) {
    case candidate.admission {
      AdmissionUnverified(_) -> False
    }
  })
}

pub fn find_candidate(
  candidates: List(MigrationCandidate),
  id: String,
) -> Result(MigrationCandidate, Nil) {
  list.find(candidates, fn(candidate) { candidate.id == id })
}

/// Discovery and classification may advance to a mapping. Evidence-dependent
/// implementation, verification, and admission are deliberately unavailable.
pub fn advance_stage(stage: MigrationStage) -> MigrationStage {
  case stage {
    Discovered -> Classified
    Classified -> Mapped
    Mapped -> Mapped
  }
}

pub fn advance_candidate(candidate: MigrationCandidate) -> MigrationCandidate {
  MigrationCandidate(..candidate, status: advance_stage(candidate.status))
}

pub fn evaluate_non_negotiable_safety(
  target: String,
) -> Result(String, String) {
  let lower = string.lowercase(target)
  case
    string.contains(lower, "beam")
    || string.contains(lower, "supervisor")
    || string.contains(lower, "uos_sup")
    || string.contains(lower, "max")
    || string.contains(lower, "25503l801736")
    || string.contains(lower, "jujutsu")
  {
    True ->
      Error(
        "CONSTITUTIONAL VIOLATION: Target subsystem is permanently non-negotiable",
      )
    False ->
      Ok(
        "Boundary screen passed; migration still requires empirical and formal evidence",
      )
  }
}
