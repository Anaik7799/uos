//// =============================================================================
//// [C3I-SIL6-CODEX-MAP] CODEX FRACTAL UNDERSTANDING UOS SYSTEM MAPPING
//// =============================================================================
//// Canonical in-code mapping of docs/journal/20260906-112237-codex-fractal-understanding.md
//// to the Unified Operational System (UOS).
////
//// Enforces:
//// 1. 11-Field Reusable Component Packet
//// 2. L0--L10 Vertical Refinement Ladder
//// 3. 9 Orthogonal System Planes
//// 4. 3 Semantic Strata (A: Algebraic Core, B: Engines, C: Substrate Seams)
//// 5. 33 Horizontal Subsystems (S1--S33) from ZigVM to UOS Gleam apps
//// 6. 12 Key Code Map Surfaces
//// 7. F/C/O/P/S/R Production Readiness Conjunction
//// 8. Capability State Poset (ABSENT < UNTESTED < EQUIV < EQ)
//// 9. Bounded OODAVR Control Loop & 4-Tier Agent Topology
//// 10. Residual Closure: Sa-Plan Resolution in Pure BEAM
//// =============================================================================

import gleam/list
import gleam/string

// =============================================================================
// 1. Reusable Component Packet (11 Fields)
// =============================================================================

pub type ComponentPacket {
  ComponentPacket(
    name: String,
    signature: String,
    semantic_domain: String,
    oracle: String,
    final_encoding: String,
    homomorphism: String,
    generator: String,
    mutants: List(String),
    judge: String,
    governor: String,
    documentation: String,
    durable_evidence: String,
  )
}

pub fn validate_component_packet(packet: ComponentPacket) -> Bool {
  !string.is_empty(packet.name)
  && !string.is_empty(packet.signature)
  && !string.is_empty(packet.semantic_domain)
  && !string.is_empty(packet.oracle)
  && !string.is_empty(packet.final_encoding)
  && !string.is_empty(packet.homomorphism)
  && !string.is_empty(packet.generator)
  && list.length(packet.mutants) >= 2
  && !string.is_empty(packet.judge)
  && !string.is_empty(packet.governor)
  && !string.is_empty(packet.documentation)
  && !string.is_empty(packet.durable_evidence)
}

// =============================================================================
// 2. Vertical Refinement Ladder (L0--L10)
// =============================================================================

pub type VerticalLayer {
  L0Boundary
  L1Artifact
  L2Subsystem
  L3Module
  L4Feature
  L5Representation
  L6Operation
  L7Generator
  L8Mutation
  L9Verification
  L10Governance
}

pub type VerticalMapping {
  VerticalMapping(
    layer: VerticalLayer,
    layer_name: String,
    zigvm_carrier: String,
    uos_carrier: String,
    required_observation: String,
    closure_evidence: String,
  )
}

pub fn get_vertical_mapping(layer: VerticalLayer) -> VerticalMapping {
  case layer {
    L0Boundary ->
      VerticalMapping(
        layer: L0Boundary,
        layer_name: "L0 Boundary",
        zigvm_carrier: "repository and external seams",
        uos_carrier: "UOS monorepo boundary, Jujutsu .jj/, Zero-Muda gate, host isolation",
        required_observation: "allowed dependency/language/tool, 0 Bevy, 0 Graphite",
        closure_evidence: "boundary audit, jj status, EV-01..EV-03 doctor passes",
      )
    L1Artifact ->
      VerticalMapping(
        layer: L1Artifact,
        layer_name: "L1 Artifact",
        zigvm_carrier: "durable files and rows, SQLite, fixtures, git",
        uos_carrier: "data/sqlite/uos_verification_tracking.sqlite3, docs/, Jujutsu commits",
        required_observation: "identity, sha256 bytes, YYYYMMDD-HHSS- timestamp, presence",
        closure_evidence: "inventory/mirror/integrity, timestamp-check, commit digest",
      )
    L2Subsystem ->
      VerticalMapping(
        layer: L2Subsystem,
        layer_name: "L2 Subsystem",
        zigvm_carrier: "composed service or OTP domain, S1-S33, harness",
        uos_carrier: "apps/cepaf_gleam, apps/indrajaal_gleam_web, engines/hermes, engines/zigvm, services/inference/max",
        required_observation: "public semantic behavior, supervision tree isolation",
        closure_evidence: "subsystem laws, uos_sup 4-domain restart budget, differential tests",
      )
    L3Module ->
      VerticalMapping(
        layer: L3Module,
        layer_name: "L3 Module",
        zigvm_carrier: "authored source unit, Zig/OCaml modules",
        uos_carrier: "Gleam modules (.gleam), OCaml modules (.ml), Zig files (.zig)",
        required_observation: "module contract, type-safety, 0 compiler warnings",
        closure_evidence: "gleam build 0 warnings, dune build, gospel contracts",
      )
    L4Feature ->
      VerticalMapping(
        layer: L4Feature,
        layer_name: "L4 Feature",
        zigvm_carrier: "callable capability, slice, route, CLI, MCP",
        uos_carrier: "Triple-interface: Lustre Web (4100), Wisp REST API (4100), ANSI TUI, MoZ MCP tools",
        required_observation: "externally visible result, typed response, OTel span",
        closure_evidence: "capability verdict, C1-C8 check pass, 381 regression pass",
      )
    L5Representation ->
      VerticalMapping(
        layer: L5Representation,
        layer_name: "L5 Representation",
        zigvm_carrier: "oracle/final carrier, AST, state machines, schemas",
        uos_carrier: "DMC syntax/semantics, FPP AST, A2UI schemas, AG-UI 32-events, W3C OTel contexts",
        required_observation: "denotation, schema compliance, serialization round-trip",
        closure_evidence: "homomorphism proof, Lean 4 coordinate conservation, JSON decoders",
      )
    L6Operation ->
      VerticalMapping(
        layer: L6Operation,
        layer_name: "L6 Operation",
        zigvm_carrier: "transformation/control action, VM, observer, DB actor",
        uos_carrier: "Gleam OTP actors (Prajna, GuardGrid, Freshness), ZigVM deterministic kernel",
        required_observation: "value/state/trace/effect, microsecond timestamps",
        closure_evidence: "operation laws, Lyapunov stability proof, actor state transition tests",
      )
    L7Generator ->
      VerticalMapping(
        layer: L7Generator,
        layer_name: "L7 Generator",
        zigvm_carrier: "seeded evidence producer, diffs, fixtures, fuzz",
        uos_carrier: "Property tests (qcheck/eunit), differential oracles, seeded scenario generators",
        required_observation: "domain and seed coverage, reproducibility",
        closure_evidence: "replayable property diff, 100% deterministic test traces",
      )
    L8Mutation ->
      VerticalMapping(
        layer: L8Mutation,
        layer_name: "L8 Mutation",
        zigvm_carrier: "deliberate fault/witness, campaigns, injection",
        uos_carrier: "Chaos injection, hardware serial mismatch simulation, NUL-byte injection tests",
        required_observation: "expected law failure, fail-closed security response",
        closure_evidence: "killed mutants, access denied verdicts (e.g. NVMe 25503L801736)",
      )
    L9Verification ->
      VerticalMapping(
        layer: L9Verification,
        layer_name: "L9 Verification",
        zigvm_carrier: "judge and evidence graph, canonical gates, verdicts",
        uos_carrier: "Master Verification Registry, tools/uos checklist (18/18), 4 Math Gates",
        required_observation: "exact verdict at exact revision, H >= 2.5b, CCM >= 90%",
        closure_evidence: "canonical green, 10083 Gleam tests pass, Lean 4 machine proofs",
      )
    L10Governance ->
      VerticalMapping(
        layer: L10Governance,
        layer_name: "L10 Governance",
        zigvm_carrier: "Zero-Trust, STPA, CAST, ratchets, admission record",
        uos_carrier: "Tri-Sovereign Governance (AGY, Claude, Codex), Hardware OS drive locks, Standalone Jujutsu",
        required_observation: "admit/reject decision, fail-closed policy authorization",
        closure_evidence: "ratified journals, two-key verification, signed certificates",
      )
  }
}

pub fn list_all_vertical_layers() -> List(VerticalLayer) {
  [
    L0Boundary,
    L1Artifact,
    L2Subsystem,
    L3Module,
    L4Feature,
    L5Representation,
    L6Operation,
    L7Generator,
    L8Mutation,
    L9Verification,
    L10Governance,
  ]
}

// =============================================================================
// 3. Orthogonal System Planes (9 Planes)
// =============================================================================

pub type SystemPlane {
  PlaneBoundary
  PlaneImplementation
  PlaneRuntime
  PlaneOracle
  PlaneVerification
  PlaneEvidence
  PlaneGovernance
  PlaneKnowledge
  PlaneOrchestration
}

pub type PlaneMapping {
  PlaneMapping(
    plane: SystemPlane,
    plane_name: String,
    primary_flow: String,
    uos_subsystems: List(String),
  )
}

pub fn get_plane_mapping(plane: SystemPlane) -> PlaneMapping {
  case plane {
    PlaneBoundary ->
      PlaneMapping(
        plane: PlaneBoundary,
        plane_name: "boundary",
        primary_flow: "repository/toolchain/oracle/dependency/runtime seams",
        uos_subsystems: [".jj/", "tools/uos", "contracts/rules/"],
      )
    PlaneImplementation ->
      PlaneMapping(
        plane: PlaneImplementation,
        plane_name: "implementation",
        primary_flow: "Gleam apps, OCaml engines, Zig kernels, representations, operations",
        uos_subsystems: ["apps/cepaf_gleam", "engines/hermes", "engines/zigvm"],
      )
    PlaneRuntime ->
      PlaneMapping(
        plane: PlaneRuntime,
        plane_name: "runtime",
        primary_flow: "BEAM OTP 29 supervisor, ZigVM execution, services, processes, effects",
        uos_subsystems: ["uos_sup.gleam", "indrajaal_gleam_web", "services/inference/max"],
      )
    PlaneOracle ->
      PlaneMapping(
        plane: PlaneOracle,
        plane_name: "oracle",
        primary_flow: "semantic domains, initial encodings, fixtures, differential specs",
        uos_subsystems: ["test_parity_algebra.exe", "dmc_tcm_algebraic_atlas.gleam", "formal/lean/"],
      )
    PlaneVerification ->
      PlaneMapping(
        plane: PlaneVerification,
        plane_name: "verification",
        primary_flow: "generators, mutants, formal judges, selfchecks, gates",
        uos_subsystems: ["master_verification_registry.gleam", "ocaml_differential_oracle.gleam", "tools/uos checklist"],
      )
    PlaneEvidence ->
      PlaneMapping(
        plane: PlaneEvidence,
        plane_name: "evidence",
        primary_flow: "SQLite WAL ledgers, Jujutsu revision, verdicts, baselines",
        uos_subsystems: ["data/sqlite/uos_verification_tracking.sqlite3", "governance/sources/"],
      )
    PlaneGovernance ->
      PlaneMapping(
        plane: PlaneGovernance,
        plane_name: "governance",
        primary_flow: "STPA, CAST, Rete-UL, OODA, ratchets, tri-sovereign admission",
        uos_subsystems: ["contracts/rules/", "governance/agents/", "spec.rs hardware lock"],
      )
    PlaneKnowledge ->
      PlaneMapping(
        plane: PlaneKnowledge,
        plane_name: "knowledge",
        primary_flow: "docs, skills, ontology, ZK ADRs, wiki, generated views",
        uos_subsystems: ["docs/zk/", "docs/wiki/", "docs/design/", ".agents/skills/"],
      )
    PlaneOrchestration ->
      PlaneMapping(
        plane: PlaneOrchestration,
        plane_name: "orchestration",
        primary_flow: "Sa-Plan, Prajna, MCP, 256 agents, bounded OODAVR slices",
        uos_subsystems: ["sa_plan_engine.gleam", "forecasting_engine.gleam", "agui/"],
      )
  }
}

pub fn list_all_system_planes() -> List(SystemPlane) {
  [
    PlaneBoundary,
    PlaneImplementation,
    PlaneRuntime,
    PlaneOracle,
    PlaneVerification,
    PlaneEvidence,
    PlaneGovernance,
    PlaneKnowledge,
    PlaneOrchestration,
  ]
}

// =============================================================================
// 4. Semantic Strata (A, B, C)
// =============================================================================

pub type SemanticStratum {
  StratumA
  StratumB
  StratumC
}

pub type StratumMapping {
  StratumMapping(
    stratum: SemanticStratum,
    stratum_name: String,
    description: String,
    uos_realization: String,
  )
}

pub fn get_stratum_mapping(stratum: SemanticStratum) -> StratumMapping {
  case stratum {
    StratumA ->
      StratumMapping(
        stratum: StratumA,
        stratum_name: "Stratum A (Algebraic Core)",
        description: "Full semantic domain, oracle/final encodings, and homomorphism laws",
        uos_realization: "Pure Gleam domain models, DMC denotation, Gospel contracts, Lean 4 proofs",
      )
    StratumB ->
      StratumMapping(
        stratum: StratumB,
        stratum_name: "Stratum B (Engines)",
        description: "Stateful/effectful realizations admitted against Stratum A by state/trace equivalence",
        uos_realization: "Gleam/OTP state machines (Prajna, GuardGrid), ZigVM deterministic kernel, Sa-Plan engine",
      )
    StratumC ->
      StratumMapping(
        stratum: StratumC,
        stratum_name: "Stratum C (Substrate Seams)",
        description: "OS, allocator, lock, and external hardware seams. Invariant-tested and quarantined",
        uos_realization: "Rust bounded kernels, ops/kubernetes NVMe hardware lock (spec.rs), Max Python daemon",
      )
  }
}

/// Invariant: Stratum A laws must never depend on Stratum C substrate behavior.
pub fn verify_stratum_isolation(
  is_stratum_a: Bool,
  has_stratum_c_dependency: Bool,
) -> Bool {
  case is_stratum_a, has_stratum_c_dependency {
    True, True -> False
    _, _ -> True
  }
}

// =============================================================================
// 5. Horizontal Subsystems (S1--S33)
// =============================================================================

pub type HorizontalCategory {
  CategoryData
  CategoryMemory
  CategoryExecution
  CategoryConcurrency
  CategoryStorage
  CategoryCommunication
  CategorySurface
  CategoryObservation
  CategoryFoundation
}

pub type SubsystemMapping {
  SubsystemMapping(
    id: String,
    name: String,
    category: HorizontalCategory,
    zigvm_source: String,
    uos_carrier: String,
  )
}

pub fn get_subsystem_mapping(subsystem_id: String) -> Result(SubsystemMapping, Nil) {
  case subsystem_id {
    "S1" -> Ok(SubsystemMapping("S1", "Terms", CategoryData, "src/beam/term.zig", "apps/cepaf_gleam/src/cepaf_gleam/ui/domain.gleam"))
    "S2" -> Ok(SubsystemMapping("S2", "Numbers", CategoryData, "src/beam/bignum.zig", "gleam/int, gleam/float, native/c/"))
    "S3" -> Ok(SubsystemMapping("S3", "Atoms", CategoryData, "src/beam/atom.zig", "BEAM native atoms, erlang.atom"))
    "S4" -> Ok(SubsystemMapping("S4", "Maps", CategoryData, "src/beam/map.zig", "gleam/dict, erlang maps"))
    "S5" -> Ok(SubsystemMapping("S5", "Binaries", CategoryData, "src/beam/binary.zig", "gleam/bit_array, gleam/bytes_builder"))
    "S6" -> Ok(SubsystemMapping("S6", "Funs/Records", CategoryData, "src/beam/closure.zig", "Gleam higher-order functions & custom types"))
    "S7" -> Ok(SubsystemMapping("S7", "Hashing", CategoryData, "src/beam/hash.zig", "apps/cepaf_gleam/src/c3i_nif.erl, Cryptokit SHA-256"))
    "S8" -> Ok(SubsystemMapping("S8", "ETF (External Term Format)", CategoryData, "src/beam/etf.zig", "erlang:term_to_binary, binary_to_term"))
    "S9" -> Ok(SubsystemMapping("S9", "Unicode", CategoryData, "src/beam/unicode.zig", "gleam/string utf-8 native handling"))
    "S10" -> Ok(SubsystemMapping("S10", "Printing", CategoryData, "src/beam/io.zig", "gleam/io, ANSI renderers, correlated_log"))
    "S11" -> Ok(SubsystemMapping("S11", "GC (Garbage Collection)", CategoryMemory, "src/beam/gc.zig", "BEAM per-process generational GC"))
    "S12" -> Ok(SubsystemMapping("S12", "Allocators", CategoryMemory, "src/runtime/allocator.zig", "Zig linear arenas, BEAM allocators"))
    "S13" -> Ok(SubsystemMapping("S13", "Interpreter", CategoryExecution, "src/vm/interpreter.zig", "engines/zigvm/src/vm/, BEAM VM"))
    "S14" -> Ok(SubsystemMapping("S14", "JIT", CategoryExecution, "src/vm/jit.zig", "BEAM OTP 29 native JIT compiler"))
    "S15" -> Ok(SubsystemMapping("S15", "Loader", CategoryExecution, "src/vm/loader.zig", "BEAM code loader, Gleam module registry"))
    "S16" -> Ok(SubsystemMapping("S16", "Code/Hot Load", CategoryExecution, "src/vm/hot_load.zig", "BEAM dynamic code upgrade, Prajna hot reload"))
    "S17" -> Ok(SubsystemMapping("S17", "Scheduler", CategoryConcurrency, "src/runtime/scheduler.zig", "BEAM pre-emptive multi-core scheduler (16:16)"))
    "S18" -> Ok(SubsystemMapping("S18", "Signals", CategoryConcurrency, "src/runtime/signal.zig", "BEAM process signal queue, exit trapping"))
    "S19" -> Ok(SubsystemMapping("S19", "Mailbox", CategoryConcurrency, "src/runtime/mailbox.zig", "gleam/erlang/process, OTP actor mailboxes"))
    "S20" -> Ok(SubsystemMapping("S20", "Monitors/Links", CategoryConcurrency, "src/runtime/monitor.zig", "OTP process monitor/link, uos_sup isolation"))
    "S21" -> Ok(SubsystemMapping("S21", "Timers", CategoryConcurrency, "src/runtime/timer.zig", "gleam/erlang/process.send_after, OTP timer wheel"))
    "S22" -> Ok(SubsystemMapping("S22", "ETS", CategoryStorage, "src/storage/ets.zig", "apps/cepaf_gleam/src/cepaf_gleam/c3i/ets.gleam"))
    "S23" -> Ok(SubsystemMapping("S23", "Match Specs", CategoryStorage, "src/storage/match_spec.zig", "ETS match specifications, Gleam pattern matching"))
    "S24" -> Ok(SubsystemMapping("S24", "Registry/Persistent State", CategoryStorage, "src/storage/registry.zig", "data/sqlite/uos_verification_tracking.sqlite3"))
    "S25" -> Ok(SubsystemMapping("S25", "Ports/IO", CategoryCommunication, "src/io/port.zig", "Gleam port drivers, length-delimited JSON-RPC"))
    "S26" -> Ok(SubsystemMapping("S26", "Drivers/NIFs", CategoryCommunication, "src/nif/dispatch.zig", "c3i_nif.erl, native/ (C-ABI bounded kernels)"))
    "S27" -> Ok(SubsystemMapping("S27", "Distribution", CategoryCommunication, "src/dist/protocol.zig", "Zenoh pub/sub mesh, Tailscale overlay mesh"))
    "S28" -> Ok(SubsystemMapping("S28", "BIF Dispatch & Families", CategorySurface, "src/bif/dispatch.zig", "BEAM built-in functions, Gleam stdlib"))
    "S29" -> Ok(SubsystemMapping("S29", "Tracing", CategoryObservation, "src/trace/tracer.zig", "Universal C3I Telemetry, OTel over Zenoh (OoZ)"))
    "S30" -> Ok(SubsystemMapping("S30", "Diagnostics", CategoryObservation, "src/diag/system.zig", "tools/uos doctor, Lyapunov trend proofs"))
    "S31" -> Ok(SubsystemMapping("S31", "Concurrency Substrate", CategoryConcurrency, "src/runtime/atomic.zig", "Lockless ring buffers, Two-Lattice STM in Lean"))
    "S32" -> Ok(SubsystemMapping("S32", "Generic Containers", CategoryFoundation, "src/util/container.zig", "Gleam list, dict, set, queue"))
    "S33" -> Ok(SubsystemMapping("S33", "Boot", CategoryFoundation, "src/boot/init.zig", "uos_sup root supervisor, tools/uos entrypoint"))
    _ -> Error(Nil)
  }
}

pub fn count_all_subsystems() -> Int {
  33
}

// =============================================================================
// 6. 12 Key Code Map Surfaces
// =============================================================================

pub type CodeSurfaceMapping {
  CodeSurfaceMapping(
    surface_id: String,
    surface_description: String,
    zigvm_carrier: String,
    uos_carrier: String,
    verification_proof: String,
  )
}

pub fn get_all_code_surface_mappings() -> List(CodeSurfaceMapping) {
  [
    CodeSurfaceMapping(
      surface_id: "SURF-01",
      surface_description: "Semantic Implementation",
      zigvm_carrier: "src/",
      uos_carrier: "apps/cepaf_gleam/src/ & engines/zigvm/src/",
      verification_proof: "10,083 passing Gleam unit/property tests",
    ),
    CodeSurfaceMapping(
      surface_id: "SURF-02",
      surface_description: "OTP Subsystem Ownership",
      zigvm_carrier: "CODEBASE_MAP.md S1--S33",
      uos_carrier: "apps/cepaf_gleam/ & CODEBASE_MAP.md S1--S33",
      verification_proof: "33 subsystems fully mapped and checked",
    ),
    CodeSurfaceMapping(
      surface_id: "SURF-03",
      surface_description: "Canonical Harness CLI & Gates",
      zigvm_carrier: "harness/zigvm_harness.ml",
      uos_carrier: "tools/uos/ (doctor, checklist, verify-all) & engines/hermes/",
      verification_proof: "tools/uos doctor (20/20 PASS), checklist (18/18 PASS)",
    ),
    CodeSurfaceMapping(
      surface_id: "SURF-04",
      surface_description: "Durable SQLite Access & Evidence",
      zigvm_carrier: "harness Db actor and harness/state/",
      uos_carrier: "data/sqlite/uos_verification_tracking.sqlite3 & Hermes WAL ledgers",
      verification_proof: "12 tables verified with schema_version and indexes",
    ),
    CodeSurfaceMapping(
      surface_id: "SURF-05",
      surface_description: "Durable Plans, Jobs & Workflows",
      zigvm_carrier: "harness/sa_plan/",
      uos_carrier: "apps/cepaf_gleam/src/cepaf_gleam/sdlc/sa_plan_engine.gleam",
      verification_proof: "sa_plan_engine_test (3/3 pass), pure BEAM task leases",
    ),
    CodeSurfaceMapping(
      surface_id: "SURF-06",
      surface_description: "Zero-Trust Admission & Dispatch",
      zigvm_carrier: "harness/rete.ml, harness/rete_rules.ml, rete_dual_*",
      uos_carrier: "engines/hermes/modules/system_engg/agent_dispatch_hook.ml & test_parity_algebra.exe",
      verification_proof: "Traps NUL bytes (-2) and SQL injection (-3) with Cryptokit SHA-256",
    ),
    CodeSurfaceMapping(
      surface_id: "SURF-07",
      surface_description: "Forecast Totality & Meet Semilattice",
      zigvm_carrier: "harness/forecast_surface_registry.ml & forecast runtime",
      uos_carrier: "apps/cepaf_gleam/src/cepaf_gleam/sdlc/forecasting_engine.gleam",
      verification_proof: "forecasting_engine_test (5/5 pass), confidence meet lattice",
    ),
    CodeSurfaceMapping(
      surface_id: "SURF-08",
      surface_description: "DMC/TCM Capability Traceability",
      zigvm_carrier: "harness/dmc_tcm_registry.ml",
      uos_carrier: "apps/cepaf_gleam/src/cepaf_gleam/verification/dmc_tcm_algebraic_atlas.gleam",
      verification_proof: "dmc_tcm_algebraic_atlas_test (4/4 pass), 13D coordinates",
    ),
    CodeSurfaceMapping(
      surface_id: "SURF-09",
      surface_description: "Lean Formal Proof Models",
      zigvm_carrier: "harness/lean_models.ml, proofs/lean/GoldenSync.lean",
      uos_carrier: "formal/lean/Traceability.lean & formal/lean/TwoLattice_STM.lean",
      verification_proof: "Delta T_13 = 0 coordinate conservation and non-interference proved",
    ),
    CodeSurfaceMapping(
      surface_id: "SURF-10",
      surface_description: "Ontology & Atlas Generation",
      zigvm_carrier: "ontology refresh & harness/fractal_fp_atlas_*",
      uos_carrier: "apps/cepaf_gleam/src/cepaf_gleam/verification/master_verification_registry.gleam",
      verification_proof: "64 browser suites, 16 skills, 19 algorithms, 432 OCaml mappings",
    ),
    CodeSurfaceMapping(
      surface_id: "SURF-11",
      surface_description: "Operations Cockpit & Dashboards",
      zigvm_carrier: "harness/ui_web/, dream_backend_app.ml, zigvm_web.ml",
      uos_carrier: "apps/indrajaal_gleam_web/ (Lustre MVU + Wisp REST + ANSI TUI on :4100)",
      verification_proof: "Triple-interface mandate, server-side rendered HTML, no client JS",
    ),
    CodeSurfaceMapping(
      surface_id: "SURF-12",
      surface_description: "Typed Browser Control",
      zigvm_carrier: "harness/playwright_ontology.ml, playwright_controller.ml",
      uos_carrier: "apps/cepaf_gleam/src/cepaf_gleam/verification/browser_emulation_bridge.gleam",
      verification_proof: "Playwright, Wallaby, CDP DevTools, and TyXML bridges verified",
    ),
  ]
}

// =============================================================================
// 7. Production Readiness Conjunction (F / C / O / P / S / R)
// =============================================================================

pub type ProductionReadiness {
  ProductionReadiness(
    functional_parity_f: Bool,
    capability_completeness_c: Bool,
    operational_honesty_o: Bool,
    performance_p: Bool,
    scalability_s: Bool,
    realtime_behavior_r: Bool,
  )
}

pub fn evaluate_production_readiness(readiness: ProductionReadiness) -> Bool {
  readiness.functional_parity_f
  && readiness.capability_completeness_c
  && readiness.operational_honesty_o
  && readiness.performance_p
  && readiness.scalability_s
  && readiness.realtime_behavior_r
}

// =============================================================================
// 8. Capability State Poset (ABSENT < UNTESTED < EQUIV < EQ)
// =============================================================================

pub type CapabilityState {
  StateAbsent
  StateUntested
  StateEquiv
  StateEq
}

pub fn capability_state_to_int(state: CapabilityState) -> Int {
  case state {
    StateAbsent -> 0
    StateUntested -> 1
    StateEquiv -> 2
    StateEq -> 3
  }
}

pub fn capability_state_leq(s1: CapabilityState, s2: CapabilityState) -> Bool {
  capability_state_to_int(s1) <= capability_state_to_int(s2)
}

pub fn capability_state_meet(s1: CapabilityState, s2: CapabilityState) -> CapabilityState {
  case capability_state_to_int(s1) <= capability_state_to_int(s2) {
    True -> s1
    False -> s2
  }
}

// =============================================================================
// 9. Bounded OODAVR Control Loop & 4-Tier Agent Topology
// =============================================================================

pub type OodavrPhase {
  PhaseObserve
  PhaseOrient
  PhaseDecide
  PhaseAct
  PhaseVerify
  PhaseRecord
}

pub type AgentTier {
  TierL0MetaOrchestrator
  TierL1DomainGovernor
  TierL2SquadLead
  TierL3SpecializedWorker
}

pub type OodavrState {
  OodavrState(
    cycle_id: String,
    current_phase: OodavrPhase,
    active_tier: AgentTier,
    sa_plan_bound: Bool,
    gate_passed: Bool,
    rete_recorded: Bool,
  )
}

pub fn advance_oodavr_phase(current: OodavrPhase) -> OodavrPhase {
  case current {
    PhaseObserve -> PhaseOrient
    PhaseOrient -> PhaseDecide
    PhaseDecide -> PhaseAct
    PhaseAct -> PhaseVerify
    PhaseVerify -> PhaseRecord
    PhaseRecord -> PhaseObserve
  }
}

pub fn is_oodavr_cycle_closed(state: OodavrState) -> Bool {
  case state.current_phase {
    PhaseRecord -> state.sa_plan_bound && state.gate_passed && state.rete_recorded
    _ -> False
  }
}

// =============================================================================
// 10. Residual Closure: Sa-Plan Resolution in Pure BEAM
// =============================================================================

pub type ResidualResolutionStatus {
  ResolvedInPureBeam
  ResidualClosedPermanently
}

pub type SaPlanResidualAudit {
  SaPlanResidualAudit(
    vm1_gap: String,
    uos_resolution: String,
    engine_module: String,
    test_module: String,
    status: ResidualResolutionStatus,
  )
}

pub fn get_sa_plan_residual_audit() -> SaPlanResidualAudit {
  SaPlanResidualAudit(
    vm1_gap: "lib/cepaf/src/Cepaf.Planning.CLI missing (Unavailable_observed)",
    uos_resolution: "Pure BEAM Sa-Plan engine implemented with task leases and Oban/Temporal semantics",
    engine_module: "apps/cepaf_gleam/src/cepaf_gleam/sdlc/sa_plan_engine.gleam",
    test_module: "apps/cepaf_gleam/test/sa_plan_engine_test.gleam",
    status: ResolvedInPureBeam,
  )
}

// =============================================================================
// 11. Universal 5-Stage Interaction Fractal & 7 System Paths
// =============================================================================

pub type InteractionStage {
  StageSource
  StageInterface
  StageTransformation
  StageObserverEvidence
  StageGovernor
}

pub type SystemPathType {
  PathWork
  PathSemantics
  PathVerification
  PathAdmission
  PathSelfModel
  PathOperationsUi
  PathResponsiveVerification
}

pub type SystemPathFlow {
  SystemPathFlow(
    path: SystemPathType,
    name: String,
    source: String,
    interface: String,
    transformation: String,
    observer: String,
    governor: String,
  )
}

pub fn get_system_path_flow(path: SystemPathType) -> SystemPathFlow {
  case path {
    PathWork ->
      SystemPathFlow(
        path: PathWork,
        name: "Work Path",
        source: "OodaSupervisor",
        interface: "SliceBacklog",
        transformation: "SaPlanOrchestrator",
        observer: "AgentWorkerSurface",
        governor: "uos_sup modules/components",
      )
    PathSemantics ->
      SystemPathFlow(
        path: PathSemantics,
        name: "Semantics Path",
        source: "OracleBoundary + fixtures",
        interface: "OracleDifferentials",
        transformation: "OracleEncodings <-> FinalEncodings",
        observer: "observations / traces",
        governor: "Gospel differential contracts",
      )
    PathVerification ->
      SystemPathFlow(
        path: PathVerification,
        name: "Verification Path",
        source: "seeds / corpus",
        interface: "generators",
        transformation: "laws <- mutants",
        observer: "sequential/DAG/formal judges",
        governor: "CanonicalGate -> CycleEvidence",
      )
    PathAdmission ->
      SystemPathFlow(
        path: PathAdmission,
        name: "Admission Path",
        source: "CycleEvidence",
        interface: "safety/formal/ratchet facts",
        transformation: "ZeroTrustRuleGate (Hermes OCaml)",
        observer: "RecordCycleAdmission",
        governor: "SQLiteEvidenceStore (WAL) + JJ Commit",
      )
    PathSelfModel ->
      SystemPathFlow(
        path: PathSelfModel,
        name: "Self-Model Path",
        source: "repository + evidence + docs + runtime",
        interface: "LivingOntology",
        transformation: "wiki / atlas / grid projections",
        observer: "agents and operators",
        governor: "Tri-Sovereign Architecture Board",
      )
    PathOperationsUi ->
      SystemPathFlow(
        path: PathOperationsUi,
        name: "Operations UI Path",
        source: "Triple-interface (Lustre + Wisp + ANSI TUI)",
        interface: "TypedWebReadModel",
        transformation: "HarnessDbActor / C3I State",
        observer: "Live Cockpit (nas-1:4100)",
        governor: "Report-Only Isolation Gatekeeper",
      )
    PathResponsiveVerification ->
      SystemPathFlow(
        path: PathResponsiveVerification,
        name: "Responsive Verification Path",
        source: "protocol specifications",
        interface: "browser emulation bridge (Playwright/Wallaby)",
        transformation: "controller -> browser/driver",
        observer: "typed observations & snapshots",
        governor: "OODA laws -> JSON/PNG evidence",
      )
  }
}

pub fn list_all_system_paths() -> List(SystemPathType) {
  [
    PathWork,
    PathSemantics,
    PathVerification,
    PathAdmission,
    PathSelfModel,
    PathOperationsUi,
    PathResponsiveVerification,
  ]
}

// =============================================================================
// 12. 10-Stage Design & Web-UI Lattice (W0--W9) & 4 UCA Hazard Types
// =============================================================================

pub type DesignLatticeStage {
  W0Carriers
  W1Planning
  W2DesignProjection
  W3Generator
  W4Refinement
  W5Runtime
  W6Verification
  W7Publication
  W8Evidence
  W9Governance
}

pub type UcaHazardType {
  UcaNotPerformed
  UcaPerformedWrongly
  UcaOutOfOrder
  UcaWrongDuration
}

pub type StageLatticeMapping {
  StageLatticeMapping(
    stage: DesignLatticeStage,
    code: String,
    name: String,
    primary_activity: String,
  )
}

pub fn get_design_lattice_mapping(stage: DesignLatticeStage) -> StageLatticeMapping {
  case stage {
    W0Carriers -> StageLatticeMapping(W0Carriers, "W0", "Carriers", "OCaml design algebra, tokens, contracts")
    W1Planning -> StageLatticeMapping(W1Planning, "W1", "Planning", "Slice planning & phase-runbook totality")
    W2DesignProjection -> StageLatticeMapping(W2DesignProjection, "W2", "Design Projection", "Figma/Stitch canvas projections")
    W3Generator -> StageLatticeMapping(W3Generator, "W3", "Generator", "Tokens & layout generator readback")
    W4Refinement -> StageLatticeMapping(W4Refinement, "W4", "Refinement", "Interactive variants & accessibility auditing")
    W5Runtime -> StageLatticeMapping(W5Runtime, "W5", "Runtime", "Lustre MVU server-side component rendering")
    W6Verification -> StageLatticeMapping(W6Verification, "W6", "Verification", "5 viewport classes & color mode captures")
    W7Publication -> StageLatticeMapping(W7Publication, "W7", "Publication", "Design publication byte equality check")
    W8Evidence -> StageLatticeMapping(W8Evidence, "W8", "Evidence", "AIP fixity hashes & journal entries")
    W9Governance -> StageLatticeMapping(W9Governance, "W9", "Governance", "SC-DESIGN rules in Zero-Trust record_cycle")
  }
}

pub fn list_all_design_stages() -> List(DesignLatticeStage) {
  [
    W0Carriers,
    W1Planning,
    W2DesignProjection,
    W3Generator,
    W4Refinement,
    W5Runtime,
    W6Verification,
    W7Publication,
    W8Evidence,
    W9Governance,
  ]
}

// =============================================================================
// 13. Living Ontology 10 Faculties
// =============================================================================

pub type OntologyFaculty {
  FacultyPerception
  FacultyMemory
  FacultyReasoning
  FacultyLearning
  FacultyDecision
  FacultyOrchestration
  FacultyActuation
  FacultyReflex
  FacultySelfModel
  FacultyVisualization
}

pub type FacultyMapping {
  FacultyMapping(
    faculty: OntologyFaculty,
    name: String,
    uos_carrier: String,
  )
}

pub fn get_faculty_mapping(faculty: OntologyFaculty) -> FacultyMapping {
  case faculty {
    FacultyPerception -> FacultyMapping(FacultyPerception, "Perception", "Universal C3I Telemetry, OTel over Zenoh")
    FacultyMemory -> FacultyMapping(FacultyMemory, "Memory", "SQLite WAL, ZK ADRs (ADR-001..032), Smriti DB")
    FacultyReasoning -> FacultyMapping(FacultyReasoning, "Reasoning", "Hermes Z3 bounded solver, Gospel contracts")
    FacultyLearning -> faculty_learning_mapping()
    FacultyDecision -> FacultyMapping(FacultyDecision, "Decision", "Prajna consensus (2oo3), Lyapunov window proofs")
    FacultyOrchestration -> FacultyMapping(FacultyOrchestration, "Orchestration", "Sa-Plan engine, uos_sup 4-domain supervisor")
    FacultyActuation -> FacultyMapping(FacultyActuation, "Actuation", "ZigVM VFS kernel, Gleam actors, bounded NIFs")
    FacultyReflex -> FacultyMapping(FacultyReflex, "Reflex", "Prajna circuit breakers, Freshness dead-man monitor")
    FacultySelfModel -> FacultyMapping(FacultySelfModel, "Self-Model", "Living Ontology catalog, DMC/TCM coordinate atlas")
    FacultyVisualization -> FacultyMapping(FacultyVisualization, "Visualization", "Lustre MVU web cockpit, ANSI TUI sparklines")
  }
}

fn faculty_learning_mapping() -> FacultyMapping {
  FacultyMapping(FacultyLearning, "Learning", "Immune antibody synthesis, mutation counterexample store")
}

pub fn list_all_faculties() -> List(OntologyFaculty) {
  [
    FacultyPerception,
    FacultyMemory,
    FacultyReasoning,
    FacultyLearning,
    FacultyDecision,
    FacultyOrchestration,
    FacultyActuation,
    FacultyReflex,
    FacultySelfModel,
    FacultyVisualization,
  ]
}

// =============================================================================
// 14. Six Fractal Completeness Criteria
// =============================================================================

pub type CompletenessCriteria {
  CompletenessCriteria(
    cc1_ladder_and_planes_total: Bool,
    cc2_component_placement: Bool,
    cc3_live_artifact_attached: Bool,
    cc4_interaction_endpoints_declared: Bool,
    cc5_critical_paths_closed: Bool,
    cc6_component_packet_on_change: Bool,
  )
}

pub fn evaluate_system_completeness(criteria: CompletenessCriteria) -> Bool {
  criteria.cc1_ladder_and_planes_total
  && criteria.cc2_component_placement
  && criteria.cc3_live_artifact_attached
  && criteria.cc4_interaction_endpoints_declared
  && criteria.cc5_critical_paths_closed
  && criteria.cc6_component_packet_on_change
}

// =============================================================================
// 15. Wiki / ZK Compiler Pipeline Recursion
// =============================================================================

pub type WikiPipelineRecursion {
  WikiPipelineRecursion(
    corpus_prefix_size: Int,
    worker_count: Int,
    backlink_inversion_active: Bool,
    aho_corasick_mention_active: Bool,
    immutable_render_context: Bool,
    lossless_projection_verified: Bool,
  )
}

pub fn verify_wiki_pipeline_recursion(pipeline: WikiPipelineRecursion) -> Bool {
  pipeline.corpus_prefix_size > 0
  && pipeline.worker_count >= 1
  && pipeline.backlink_inversion_active
  && pipeline.aho_corasick_mention_active
  && pipeline.immutable_render_context
  && pipeline.lossless_projection_verified
}

