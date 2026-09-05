//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/holon/identity</module>
////     <fsharp-lineage>Cepaf.Holon.Identity.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>Universal Holon Identification</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / CRITICAL</criticality>
////     <stamp-controls>SC-GLM-CORE-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/dict.{type Dict}
import gleam/json
import gleam/result
import gleam/string

// =============================================================================
// Type Definitions
// =============================================================================

/// Runtime substrate for a holon.
pub type Runtime {
  Gleam
  Elixir
  FSharp
  Rust
}

/// Fractal layer in the mesh hierarchy (L0..L7).
pub type FractalLayer {
  L0Constitutional
  L1AtomicDebug
  L2Component
  L3Transaction
  L4System
  L5Cognitive
  L6Ecosystem
  L7Federation
}

/// Domain classification for holons across all 16 mesh domains.
pub type HolonDomain {
  DomainCore
  DomainPlanning
  DomainZenoh
  DomainPodman
  DomainTelemetry
  DomainKnowledge
  DomainImmune
  DomainMetabolic
  DomainSubstrate
  DomainVerification
  DomainSecurity
  DomainUI
  DomainGit
  DomainMcp
  DomainAgui
  DomainKms
}

/// Functional role of a holon within the mesh.
pub type HolonType {
  Agent
  Supervisor
  Worker
  Coordinator
  Guardian
  Oracle
  Sensor
  Effector
}

/// Database backend type.
pub type DatabaseType {
  SQLite
  DuckDB
  Postgres
  InMemory
  ZenohKV
}

/// Universal Holon Identifier — uniquely addresses any holon in the mesh.
pub type UHI {
  UHI(
    runtime: Runtime,
    layer: FractalLayer,
    domain: HolonDomain,
    holon_type: HolonType,
    instance: String,
  )
}

/// Fully Qualified Domain Name for mesh-level routing.
pub type FQDN {
  FQDN(mesh_id: String, uhi: UHI)
}

/// Manifest describing a holon's capabilities and metadata.
pub type HolonManifest {
  HolonManifest(
    uhi: UHI,
    version: String,
    databases: List(DatabaseType),
    description: String,
    dependencies: List(String),
  )
}

// =============================================================================
// Functions (19)
// =============================================================================

/// Create a UHI from its constituent parts.
pub fn create_uhi(
  runtime: Runtime,
  layer: FractalLayer,
  domain: HolonDomain,
  holon_type: HolonType,
  instance: String,
) -> UHI {
  UHI(
    runtime: runtime,
    layer: layer,
    domain: domain,
    holon_type: holon_type,
    instance: instance,
  )
}

/// Serialize a UHI to its canonical string form.
pub fn uhi_to_string(uhi: UHI) -> String {
  string.join(
    [
      runtime_to_string(uhi.runtime),
      layer_to_string(uhi.layer),
      domain_to_string(uhi.domain),
      holon_type_to_string(uhi.holon_type),
      uhi.instance,
    ],
    with: ":",
  )
}

/// Parse a UHI from its canonical string form.
pub fn parse_uhi(input: String) -> Result(UHI, String) {
  case string.split(input, on: ":") {
    [rt_str, layer_str, domain_str, type_str, instance] -> {
      use rt <- result.try(parse_runtime(rt_str))
      use layer <- result.try(parse_layer(layer_str))
      use domain <- result.try(parse_domain(domain_str))
      use ht <- result.try(parse_holon_type(type_str))
      Ok(UHI(
        runtime: rt,
        layer: layer,
        domain: domain,
        holon_type: ht,
        instance: instance,
      ))
    }
    _ -> Error("Invalid UHI format: expected 5 colon-separated segments")
  }
}

/// Create an FQDN from a mesh ID and UHI.
pub fn create_fqdn(mesh_id: String, uhi: UHI) -> FQDN {
  FQDN(mesh_id: mesh_id, uhi: uhi)
}

/// Serialize an FQDN to string.
pub fn fqdn_to_string(fqdn: FQDN) -> String {
  fqdn.mesh_id <> "/" <> uhi_to_string(fqdn.uhi)
}

/// Parse an FQDN from string.
pub fn parse_fqdn(input: String) -> Result(FQDN, String) {
  case string.split(input, on: "/") {
    [mesh_id, rest] -> {
      use uhi <- result.try(parse_uhi(rest))
      Ok(FQDN(mesh_id: mesh_id, uhi: uhi))
    }
    _ -> Error("Invalid FQDN format: expected mesh_id/uhi")
  }
}

/// Resolve a UHI to its Zenoh topic path.
pub fn resolve(uhi: UHI) -> String {
  zenoh_topic(uhi)
}

/// Generate the Zenoh topic for a UHI.
pub fn zenoh_topic(uhi: UHI) -> String {
  string.join(
    [
      "indrajaal",
      runtime_to_string(uhi.runtime),
      layer_to_string(uhi.layer),
      domain_to_string(uhi.domain),
      holon_type_to_string(uhi.holon_type),
      uhi.instance,
    ],
    with: "/",
  )
}

/// Convert runtime to string.
pub fn runtime_to_string(rt: Runtime) -> String {
  case rt {
    Gleam -> "gleam"
    Elixir -> "elixir"
    FSharp -> "fsharp"
    Rust -> "rust"
  }
}

/// Convert fractal layer to string.
pub fn layer_to_string(layer: FractalLayer) -> String {
  case layer {
    L0Constitutional -> "L0"
    L1AtomicDebug -> "L1"
    L2Component -> "L2"
    L3Transaction -> "L3"
    L4System -> "L4"
    L5Cognitive -> "L5"
    L6Ecosystem -> "L6"
    L7Federation -> "L7"
  }
}

/// Convert domain to string.
pub fn domain_to_string(domain: HolonDomain) -> String {
  case domain {
    DomainCore -> "core"
    DomainPlanning -> "planning"
    DomainZenoh -> "zenoh"
    DomainPodman -> "podman"
    DomainTelemetry -> "telemetry"
    DomainKnowledge -> "knowledge"
    DomainImmune -> "immune"
    DomainMetabolic -> "metabolic"
    DomainSubstrate -> "substrate"
    DomainVerification -> "verification"
    DomainSecurity -> "security"
    DomainUI -> "ui"
    DomainGit -> "git"
    DomainMcp -> "mcp"
    DomainAgui -> "agui"
    DomainKms -> "kms"
  }
}

/// Convert holon type to string.
pub fn holon_type_to_string(ht: HolonType) -> String {
  case ht {
    Agent -> "agent"
    Supervisor -> "supervisor"
    Worker -> "worker"
    Coordinator -> "coordinator"
    Guardian -> "guardian"
    Oracle -> "oracle"
    Sensor -> "sensor"
    Effector -> "effector"
  }
}

/// Convert database type to string.
pub fn database_type_to_string(db: DatabaseType) -> String {
  case db {
    SQLite -> "sqlite"
    DuckDB -> "duckdb"
    Postgres -> "postgres"
    InMemory -> "in_memory"
    ZenohKV -> "zenoh_kv"
  }
}

/// Check if a UHI represents a Gleam holon.
pub fn is_gleam_holon(uhi: UHI) -> Bool {
  uhi.runtime == Gleam
}

/// Check if a UHI represents an F# holon.
pub fn is_fsharp_holon(uhi: UHI) -> Bool {
  uhi.runtime == FSharp
}

/// List all supported database types.
pub fn all_databases() -> List(DatabaseType) {
  [SQLite, DuckDB, Postgres, InMemory, ZenohKV]
}

/// Return a registry mapping domain names to HolonDomain values.
pub fn domain_registry() -> Dict(String, HolonDomain) {
  dict.from_list([
    #("core", DomainCore),
    #("planning", DomainPlanning),
    #("zenoh", DomainZenoh),
    #("podman", DomainPodman),
    #("telemetry", DomainTelemetry),
    #("knowledge", DomainKnowledge),
    #("immune", DomainImmune),
    #("metabolic", DomainMetabolic),
    #("substrate", DomainSubstrate),
    #("verification", DomainVerification),
    #("security", DomainSecurity),
    #("ui", DomainUI),
    #("git", DomainGit),
    #("mcp", DomainMcp),
    #("agui", DomainAgui),
    #("kms", DomainKms),
  ])
}

/// Create a holon manifest.
pub fn create_manifest(
  uhi: UHI,
  version: String,
  databases: List(DatabaseType),
  description: String,
  dependencies: List(String),
) -> HolonManifest {
  HolonManifest(
    uhi: uhi,
    version: version,
    databases: databases,
    description: description,
    dependencies: dependencies,
  )
}

/// Serialize a HolonManifest to JSON.
pub fn manifest_to_json(m: HolonManifest) -> json.Json {
  json.object([
    #("uhi", json.string(uhi_to_string(m.uhi))),
    #("version", json.string(m.version)),
    #(
      "databases",
      json.array(m.databases, fn(db) {
        json.string(database_type_to_string(db))
      }),
    ),
    #("description", json.string(m.description)),
    #("dependencies", json.array(m.dependencies, fn(d) { json.string(d) })),
  ])
}

// =============================================================================
// Private parsing helpers (exhaustive pattern matching per SC-GLM-CORE-003)
// =============================================================================

fn parse_runtime(s: String) -> Result(Runtime, String) {
  case s {
    "gleam" -> Ok(Gleam)
    "elixir" -> Ok(Elixir)
    "fsharp" -> Ok(FSharp)
    "rust" -> Ok(Rust)
    _ -> Error("Unknown runtime: " <> s)
  }
}

fn parse_layer(s: String) -> Result(FractalLayer, String) {
  case s {
    "L0" -> Ok(L0Constitutional)
    "L1" -> Ok(L1AtomicDebug)
    "L2" -> Ok(L2Component)
    "L3" -> Ok(L3Transaction)
    "L4" -> Ok(L4System)
    "L5" -> Ok(L5Cognitive)
    "L6" -> Ok(L6Ecosystem)
    "L7" -> Ok(L7Federation)
    _ -> Error("Unknown layer: " <> s)
  }
}

fn parse_domain(s: String) -> Result(HolonDomain, String) {
  case dict.get(domain_registry(), s) {
    Ok(d) -> Ok(d)
    Error(_) -> Error("Unknown domain: " <> s)
  }
}

fn parse_holon_type(s: String) -> Result(HolonType, String) {
  case s {
    "agent" -> Ok(Agent)
    "supervisor" -> Ok(Supervisor)
    "worker" -> Ok(Worker)
    "coordinator" -> Ok(Coordinator)
    "guardian" -> Ok(Guardian)
    "oracle" -> Ok(Oracle)
    "sensor" -> Ok(Sensor)
    "effector" -> Ok(Effector)
    _ -> Error("Unknown holon type: " <> s)
  }
}
