// Unified Operational System (UOS) - MirageOS Subsystem Migration Engine
// Authority: contracts/rules/mirage-migration-policy.md - SC-MIRAGE-MIGRATE-001

import gleam/list
import gleam/string

pub type MigrationStage {
  Discovered
  Classified
  Mapped
  Implemented
  Verified
  Admitted
}

pub type MigrationCandidate {
  MigrationCandidate(
    id: String,
    name: String,
    layer: String,
    current_tech: String,
    mirage_target: String,
    sil_level: Int,
    ram_saving_mb: Int,
    speedup_pct: Float,
    status: MigrationStage,
  )
}

pub fn stage_to_string(stage: MigrationStage) -> String {
  case stage {
    Discovered -> "Discovered"
    Classified -> "Classified"
    Mapped -> "Mapped"
    Implemented -> "Implemented"
    Verified -> "Verified"
    Admitted -> "Admitted"
  }
}

pub fn get_migration_candidates() -> List(MigrationCandidate) {
  [
    MigrationCandidate(
      id: "MIG-01-INGRESS",
      name: "Edge HTTP/TLS Ingress Proxy",
      layer: "L4",
      current_tech: "Mist HTTP / External Nginx Reverse Proxy",
      mirage_target: "Solo5-SPT + paf / ocaml-tls / mirage-crypto-rng",
      sil_level: 5,
      ram_saving_mb: 168,
      speedup_pct: 99.4,
      status: Implemented,
    ),
    MigrationCandidate(
      id: "MIG-02-SANDBOX",
      name: "Isolated Ephemeral Tool Sandbox",
      layer: "L3",
      current_tech: "Podman Rootless OCI Container",
      mirage_target: "Solo5-SPT Ephemeral Unikernel (Micro-Sandbox)",
      sil_level: 6,
      ram_saving_mb: 234,
      speedup_pct: 99.1,
      status: Admitted,
    ),
    MigrationCandidate(
      id: "MIG-03-DNS",
      name: "Deterministic DNS Recursive Resolver",
      layer: "L2",
      current_tech: "Host Glibc getaddrinfo / /etc/resolv.conf",
      mirage_target: "Solo5-SPT + mirage-dns / DNS-over-TLS (DoT)",
      sil_level: 5,
      ram_saving_mb: 56,
      speedup_pct: 98.3,
      status: Implemented,
    ),
    MigrationCandidate(
      id: "MIG-04-CRYPTO",
      name: "Cryptographic Token & Receipt Authority",
      layer: "L1",
      current_tech: "C-NIF / Rust OpenSSL Bindings",
      mirage_target: "Hermes mirage-crypto / mirage-crypto-ec (Pure OCaml)",
      sil_level: 6,
      ram_saving_mb: 28,
      speedup_pct: 100.0,
      status: Admitted,
    ),
    MigrationCandidate(
      id: "MIG-05-LEDGER",
      name: "Immutable Merkle DAG Evidence Store",
      layer: "L5",
      current_tech: "SQLite WAL Files + Raw JSONL Ledgers",
      mirage_target: "Irmin Merkle DAG / Wodan Block Engine",
      sil_level: 6,
      ram_saving_mb: 96,
      speedup_pct: 88.0,
      status: Implemented,
    ),
    MigrationCandidate(
      id: "MIG-06-FORWARD",
      name: "Zenoh Micro-Packet Forwarder",
      layer: "L6",
      current_tech: "Zenoh Rust Daemon (Port 7447)",
      mirage_target: "Solo5-SPT Flow-Forwarder Enclave (Pure OCaml)",
      sil_level: 4,
      ram_saving_mb: 74,
      speedup_pct: 98.2,
      status: Mapped,
    ),
    MigrationCandidate(
      id: "MIG-07-SOLVER",
      name: "Bounded Z3 Gospel Verification Sandbox",
      layer: "L0",
      current_tech: "Host OS Subprocess Fork with Timeout",
      mirage_target: "Solo5-SPT Memory-Capped Micro-Sandbox (64MB Hard Cap)",
      sil_level: 5,
      ram_saving_mb: 436,
      speedup_pct: 95.7,
      status: Implemented,
    ),
  ]
}

pub fn total_ram_savings(candidates: List(MigrationCandidate)) -> Int {
  list.fold(candidates, 0, fn(acc, c) { acc + c.ram_saving_mb })
}

pub fn admitted_count(candidates: List(MigrationCandidate)) -> Int {
  list.count(candidates, fn(c) {
    case c.status {
      Admitted -> True
      _ -> False
    }
  })
}

pub fn find_candidate(
  candidates: List(MigrationCandidate),
  id: String,
) -> Result(MigrationCandidate, Nil) {
  list.find(candidates, fn(c) { c.id == id })
}

pub fn advance_stage(stage: MigrationStage) -> MigrationStage {
  case stage {
    Discovered -> Classified
    Classified -> Mapped
    Mapped -> Implemented
    Implemented -> Verified
    Verified -> Admitted
    Admitted -> Admitted
  }
}

pub fn advance_candidate(candidate: MigrationCandidate) -> MigrationCandidate {
  MigrationCandidate(..candidate, status: advance_stage(candidate.status))
}

pub fn evaluate_non_negotiable_safety(target: String) -> Result(String, String) {
  let lower = string.lowercase(target)
  case
    string.contains(lower, "beam")
    || string.contains(lower, "supervisor")
    || string.contains(lower, "uos_sup")
    || string.contains(lower, "max")
    || string.contains(lower, "25503l801736")
    || string.contains(lower, "jujutsu")
  {
    True -> Error("CONSTITUTIONAL VIOLATION: Target subsystem is permanently non-negotiable")
    False -> Ok("Safety check passed: Subsystem is eligible for MirageOS unikernel migration")
  }
}
