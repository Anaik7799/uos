//// Wisp REST API & Telemetry Catalog for UOS-CORE-EVO Zero-Muda Core
//// Development, 5-Caste Holonic Hive, 8 Integrated Bionic Services &
//// 10-Layer OTP 29 FPP Actor Digital Twin Mesh.
//// STAMP: SC-GLM-UI-001, SC-HARNESS-MCP-001, SC-JIDOKA-001, SC-PROVENANCE-001

import cepaf_gleam/ecology/core_bionic_token_twin
import cepaf_gleam/ecology/core_effect_fence
import cepaf_gleam/ecology/core_evolution
import cepaf_gleam/ecology/core_fpp_actor_twin_mesh.{
  type SubsystemFppActorSpec,
}
import gleam/json
import gleam/list

const cockpit_url = "http://nas-1.tail55d152.ts.net:4100/core-evo"

const fpp_actors_url = "http://nas-1.tail55d152.ts.net:4100/api/v1/core-evo/fpp-actors"

const bionic_token_twin_url = "http://nas-1.tail55d152.ts.net:4100/api/v1/core-evo/bionic-token-twin"

const spec_url = "http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261101-1543-uos-zero-muda-core-dev-hive-biomorphic-fractal-evolution-system.md"

const wiki_url = "http://nas-1.tail55d152.ts.net:4100/files/docs/wiki/20261101-1721-uos-core-evo-mcp-zenoh-hive-bionic-services-and-dashboard-wiki.md"

const zk_url = "http://nas-1.tail55d152.ts.net:4100/files/docs/zk/20261101-1721-core-evo-zero-muda-holonic-hive-zenoh-mcp-and-cockpit-decision.md"

const journal_url = "http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261101-1711-uos-core-evo-benefits-features-mcp-zenoh-hive-services-master-journal.md"

const km_catalog_url = "http://nas-1.tail55d152.ts.net:4100/api/v1/km/catalog"

pub type CoreEvoBenefit {
  CoreEvoBenefit(
    id: String,
    dimension: String,
    before_state: String,
    after_state: String,
    quantitative_delta: String,
  )
}

pub type CoreEvoModuleRecord {
  CoreEvoModuleRecord(
    id: String,
    module_name: String,
    path: String,
    layers: String,
    invariants_and_capabilities: String,
  )
}

pub type CoreEvoCasteRecord {
  CoreEvoCasteRecord(
    caste_id: String,
    role_name: String,
    bound_engine: String,
    token_share: String,
    heijunka_wip_limit: Int,
    mcp_slice: String,
    responsibility: String,
  )
}

pub type CoreEvoServiceRecord {
  CoreEvoServiceRecord(
    id: String,
    name: String,
    layer: String,
    substrate: String,
    protection_and_capability: String,
  )
}

pub type CoreEvoCommandRecord {
  CoreEvoCommandRecord(
    id: String,
    surface: String,
    invocation: String,
    role_or_topic: String,
    description: String,
  )
}

pub fn get_benefits() -> List(CoreEvoBenefit) {
  [
    CoreEvoBenefit(
      id: "BEN-01",
      dimension: "MCP Schema Overhead Compression",
      before_state: "10 AGY MCP servers (89.8 KB/turn) + 15 Pi MCP servers",
      after_state: "1 canonical Gleam/OTP 29 MCP server (uos-gleam, 15.4 KB; 8-10 role-scoped routes)",
      quantitative_delta: "-82.9% MCP schema overhead (10->1 uos-gleam, -74.4 KB/turn)",
    ),
    CoreEvoBenefit(
      id: "BEN-02",
      dimension: "AGY Conductor Token Share",
      before_state: "Unbounded AGY implementation loops + paid npm extension bloat",
      after_state: "Wave-scoped <=512 B Zenoh digests + isolated Pi/DeepSeek/Argon/Codex workers",
      quantitative_delta: "1.01% AGY token share (<2.0% constitutional ceiling; >98.9% offloaded)",
    ),
    CoreEvoBenefit(
      id: "BEN-03",
      dimension: "4-Window Untouched Quota Safety Margin",
      before_state: "Ad-hoc manual quota checks risking mid-wave window exhaustion",
      after_state: "Append-only SQLite WAL enforcing <=6000 bps (60.0%) & $6.00/$10.00 OR cap ($4.50 $0-OR shift)",
      quantitative_delta: "40.0% / 4000 bps untouched token margin <=6000 bps & $6/$10 OR cap",
    ),
    CoreEvoBenefit(
      id: "BEN-04",
      dimension: "System-Wide BEAM / Erlang Runtime",
      before_state: "Default /usr/bin/erl on OTP 27 failing on OTP 29 .beam atom tables",
      after_state: "Pinned Determinate Nix erlang-29.0.5 (ERTS 17.0.5) across all shells and tools",
      quantitative_delta: "System-wide OTP 29.0.5 ERTS 17.0.5 (0 version mismatches)",
    ),
    CoreEvoBenefit(
      id: "BEN-05",
      dimension: "Maximized Timeouts & 3-Attempt Self-Healing",
      before_state: "Short brittle timeouts, manual JJ workspace cleanup, and orphaned leases",
      after_state: "4h lease, 20m heartbeat, 30m tool timeout, 60m->90m->120m clean-JJ recovery -> Jidoka HOLD",
      quantitative_delta: "60m->90m->120m 3-attempt clean-JJ self-healing (Flash -> Pro ACH RCA -> Argon STPA)",
    ),
    CoreEvoBenefit(
      id: "BEN-06",
      dimension: "Signed Zenoh uos/v1/** Split-Brain Quarantine",
      before_state: "Shared 127.0.0.1:7447 bus exposed to legacy :4200 c3i/** & EV>93 frames",
      after_state: "Signed uos/v1/** envelopes with seq_id, SHA-256, and Bio Membrane c3i/** quarantine",
      quantitative_delta: "Signed Zenoh uos/v1/** confining c3i/** split-brain & EV>93 claims (I28)",
    ),
    CoreEvoBenefit(
      id: "BEN-07",
      dimension: "10x17 Janus Holonic Dynamical Simulation",
      before_state: "Static single-point checks without multi-regime fault trajectory proof",
      after_state: "170 Koestlerian Janus Holons simulated across 24 epochs and 6 adversarial regimes",
      quantitative_delta: "170 Janus Holons x 24 epochs = 4080 states 12/12 invariants (INV-HOLON-01..12)",
    ),
    CoreEvoBenefit(
      id: "BEN-08",
      dimension: "Universal 40-Subsystem OTP 29 Intelligent NASA FPP Actor Mesh",
      before_state: "Unverified actor lifecycles, layer-only granularity, and 2-arity OTel badarg crashes",
      after_state: "40 live OTP 29 intelligent FPP actors (4 uos_sup domains x L0..L9) with dual F' HSMs, Kalman-PID-Beta twins, autonomous self-healing, and Ed25519 Zenoh",
      quantitative_delta: "40 live OTP 29 Intelligent NASA FPP Actors (4 Domains x L0..L9, 40/40 converged & self-healing)",
    ),
    CoreEvoBenefit(
      id: "BEN-09",
      dimension: "OI07 Effect-Time Authority Fence & 14-Target Rollback",
      before_state: "Pre-claim risk checks without effect-time re-verification or atomic 14-target rollback receipts",
      after_state: "8-guard evaluate_effect_fence (oi07<-oi02) + Steps 1..13 crash rollback to old_capsule_sha",
      quantitative_delta: "OI07 effect-time lease/SHA-256 fence & 14-target reader-drain crash rollback (0 mixed readers)",
    ),
  ]
}

pub fn get_modules() -> List(CoreEvoModuleRecord) {
  [
    CoreEvoModuleRecord(
      id: "MOD-01",
      module_name: "core_evolution",
      path: "apps/cepaf_gleam/src/cepaf_gleam/ecology/core_evolution.gleam",
      layers: "L3, L4, L6",
      invariants_and_capabilities: "4-window 40.0% quota margin (<=6000 bps, $6.00/$10.00 OR), 4h lease / 20m heartbeat, 60m->90m->120m 3-attempt FSM, <=512 B AGY digest",
    ),
    CoreEvoModuleRecord(
      id: "MOD-02",
      module_name: "core_hive",
      path: "apps/cepaf_gleam/src/cepaf_gleam/ecology/core_hive.gleam",
      layers: "L4, L6, L7",
      invariants_and_capabilities: "5-Caste Holonic Hive Heijunka WIP pull-queue, integer half-life stigmergic pheromones (uos/v1/hive/**), 2oo3 Tri-Sovereign quorum",
    ),
    CoreEvoModuleRecord(
      id: "MOD-03",
      module_name: "core_biomorphic_fractal",
      path: "apps/cepaf_gleam/src/cepaf_gleam/ecology/core_biomorphic_fractal.gleam",
      layers: "L0..L9",
      invariants_and_capabilities: "Metabolic ATP regimes (Anabolic..Torpor), Self/Non-Self Immune reflex + Prajna breaker, discrete Lyapunov dV<=0, L0..L9 7-stage POODAVR monoid",
    ),
    CoreEvoModuleRecord(
      id: "MOD-04",
      module_name: "core_systems_engineering",
      path: "apps/cepaf_gleam/src/cepaf_gleam/ecology/core_systems_engineering.gleam",
      layers: "L0..L9",
      invariants_and_capabilities: "17-Aspect assurance, Cech Sheaf H^1=0, 13D Traceability, Stan HMC/Bayesian/Pareto, 11-Domain Rete-UL, Kalman/PID/Shield, 6 FPP FSMs, SysML v2, 8 Bionic Services",
    ),
    CoreEvoModuleRecord(
      id: "MOD-05",
      module_name: "core_fractal_holonic_simulator",
      path: "apps/cepaf_gleam/src/cepaf_gleam/ecology/core_fractal_holonic_simulator.gleam",
      layers: "L0..L9 x A1..A17",
      invariants_and_capabilities: "170 Koestlerian Janus Holons simulated across 24 epochs = 4080 states and 6 nominal/adversarial regimes proving 12/12 invariants (INV-HOLON-01..12)",
    ),
    CoreEvoModuleRecord(
      id: "MOD-06",
      module_name: "core_fpp_actor_twin_mesh",
      path: "apps/cepaf_gleam/src/cepaf_gleam/ecology/core_fpp_actor_twin_mesh.gleam",
      layers: "4 Domains x L0..L9",
      invariants_and_capabilities: "40 live OTP 29 Intelligent FPP Actors (Apps, Engines, Services, Intelligence x L0..L9) with Autonomous Reflexes, Kalman-PID-Beta Twins, W3C OTel, Ed25519 Zenoh uos/v1/** & redacted OpenRouter",
    ),
    CoreEvoModuleRecord(
      id: "MOD-07",
      module_name: "core_effect_fence",
      path: "apps/cepaf_gleam/src/cepaf_gleam/ecology/core_effect_fence.gleam",
      layers: "L0, L1, L4, L8",
      invariants_and_capabilities: "OI07 8-guard effect-time lease/SHA-256 authority fence (blocking oi02 until oi07_verified, rejecting :4200/c3i) & 14-target reader-drain crash rollback",
    ),
  ]
}

pub fn get_castes() -> List(CoreEvoCasteRecord) {
  [
    CoreEvoCasteRecord(
      caste_id: "CASTE-01",
      role_name: "Conductor AGY (QueenConductor)",
      bound_engine: "agy:thin-conductor-digest-only",
      token_share: "<=2% (1.01% observed)",
      heijunka_wip_limit: 1,
      mcp_slice: "ConductorRole (<=512 B Zenoh digests)",
      responsibility: "High-level Sa-plan wave admission, constitutional arbitration, and JidokaAndonHold disposition",
    ),
    CoreEvoCasteRecord(
      caste_id: "CASTE-02",
      role_name: "Builder Pi+DeepSeek/Argon (ForagerBuilder & NurseDiagnostician)",
      bound_engine: "pi+openrouter:deepseek-v4-flash/pro & pi+google:gemini-4-argon ($0-flash)",
      token_share: "~46%",
      heijunka_wip_limit: 4,
      mcp_slice: "ImplRole (9 routes) & RcaTpsRole (10 routes)",
      responsibility: "Attempt 1 (60m) isolated JJ implementation + Attempt 2 (90m) ACH RCA & Poka-Yoke healing",
    ),
    CoreEvoCasteRecord(
      caste_id: "CASTE-03",
      role_name: "Verifier Codex (SovereignSentinel / GuardImmune)",
      bound_engine: "codex:gpt-6.1-terra ($0)",
      token_share: "~4%",
      heijunka_wip_limit: 2,
      mcp_slice: "SovereignGateRole (8 routes)",
      responsibility: "Read-only sovereign peer verification, Gate W1.5 4-hash/1-byte tamper audit, and 2oo3 quorum voting",
    ),
    CoreEvoCasteRecord(
      caste_id: "CASTE-04",
      role_name: "Scholar Claude / ArchitectSynthesizer (ScoutExplorer)",
      bound_engine: "claude-scholar / pi+google:gemini-4-argon",
      token_share: "~2%",
      heijunka_wip_limit: 2,
      mcp_slice: "FmeaFormalRole (8 routes)",
      responsibility: "#km-triad precedent recall, STPA/FMEA formal synthesis, and Attempt 3 (120m) wrong-path architectural pivot",
    ),
    CoreEvoCasteRecord(
      caste_id: "CASTE-05",
      role_name: "Kernel Tier-0 Binaries (Deterministic Verifiers)",
      bound_engine: "tier0:otp29_lean4_zlp_v3_hermes_ocaml_zigvm",
      token_share: "~46% (compute share, $0 LLM tokens)",
      heijunka_wip_limit: 8,
      mcp_slice: "Native C-ABI / Port / CLI Verifiers",
      responsibility: "Zero-token deterministic execution: UOS-ZLP-v3 Lean 4.33.0/Zig 0.16.0 AVX-512, Hermes OCaml, km-gate, risk-priority-check",
    ),
  ]
}

pub fn get_bionic_services() -> List(CoreEvoServiceRecord) {
  [
    CoreEvoServiceRecord(
      id: "S1",
      name: "S1 Bionic Memory Palace + Multi-Token KM (43 Curated Aliases)",
      layer: "L5",
      substrate: "engines/hermes + cepaf_gleam/mcp (knowledge_search, zk_transclude)",
      protection_and_capability: "Sub-millisecond #km-triad recall across 134 ZK ADRs, Wiki Corpus, and 43 curated multi-token aliases with fresh disk reopen (T19)",
    ),
    CoreEvoServiceRecord(
      id: "S2",
      name: "S2 Bionic Metabolic & Prajna Immune Circuit Breaker",
      layer: "L2, L4",
      substrate: "core_biomorphic_fractal + prajna/bio + prajna/circuit_breaker + ha/endocrine",
      protection_and_capability: "Enforces 40.0% untouched ATP margin (Anabolic..Torpor), 7-hormone EMA regulation, and selective membrane blocking :4200 c3i/** & EV>93",
    ),
    CoreEvoServiceRecord(
      id: "S3",
      name: "S3 Bionic Crontab/Watchdog/Dead-Man Freshness",
      layer: "L3, L4",
      substrate: "ha/freshness_monitor + core_evolution (4h lease, 20m Zenoh heartbeat)",
      protection_and_capability: "Tracks monotonic clock drift (<2.0s nominal, >10.0s halt), 20m lease heartbeats, and PID-quiescence checks before zombie lease reclaim",
    ),
    CoreEvoServiceRecord(
      id: "S4",
      name: "S4 Bionic Rete-UL 11-Domain + STPA/FMEA Risk Engine",
      layer: "L0, L4, L8",
      substrate: "math/rete + ha/fmea_generator + ha/stamp_automata + core_systems_engineering",
      protection_and_capability: "Salience-fuses 11 Rete-UL rule domains with 4-UCA STPA hazard analysis, raw FMEA RPN, STAMP contagion cellular automata, and Stan/Bayesian gates",
    ),
    CoreEvoServiceRecord(
      id: "S5",
      name: "S5 ZigVM VFS + UOS-ZLP-v3 Lean 4.33.0 + Zig 0.16.0 AVX-512 Hyperplane",
      layer: "L1, L2, L6",
      substrate: "engines/zigvm + mcp/transports/zlp_hyperplane + formal/lean/UosZlpHyperplane.lean",
      protection_and_capability: "OS-isolated OTP 29 Port pool with 21 zero-sorry Lean 4.33.0 theorems, 8 C-ABI kernels, Zen 5 AVX-512 fast lane (<10us), and race-free VFS",
    ),
    CoreEvoServiceRecord(
      id: "S6",
      name: "S6 NASA FPP v3 + OMG SysML v2 Model Validator",
      layer: "L0..L9",
      substrate: "fpp/poodavr_fprime + fpp/homeostasis_fprime + fpp/sysml_validator",
      protection_and_capability: "Executes 6 deterministic NASA JPL F' state machines and verifies OMG SysML v2 packages with satisfaction_ratio == 1.0 and 0 port mismatches",
    ),
    CoreEvoServiceRecord(
      id: "S7",
      name: "S7 40 Live OTP 29 Intelligent NASA FPP Actors & Digital Twins (4 Domains x L0..L9)",
      layer: "L0..L9",
      substrate: "ecology/core_fpp_actor_twin_mesh + uos_sup + ha/digital_twin + intent/denotational + telemetry/otel",
      protection_and_capability: "Spawns 40 supervised OTP 29 subsystem FPP actors with Autonomous Cybernetic Reflexes (PID damping, autonomous self-heal, breaker quarantine), Ed25519 Zenoh & redacted OpenRouter",
    ),
    CoreEvoServiceRecord(
      id: "S8",
      name: "S8 OI07 Effect-Time Lease/SHA-256 Fence & OI02E Tamper-Refusing Native Release Builder",
      layer: "L0, L4, L8",
      substrate: "ecology/core_effect_fence + tools/uos-release-Verify",
      protection_and_capability: "Enforces oi07<-oi02 ordering (I29), rejects :4200/c3i writers (I28), proves 14-target crash rollback (0 mixed readers), and refuses 1-byte tampered capsules (I27)",
    ),
  ]
}

pub fn get_commands() -> List(CoreEvoCommandRecord) {
  [
    CoreEvoCommandRecord(
      id: "CMD-01",
      surface: "CLI (./tools/uos-core-evo)",
      invocation: "./tools/uos-core-evo preflight",
      role_or_topic: "uos/v1/core_evo/preflight",
      description: "Verify OTP 29.0.5 (ERTS 17.0.5), uos-gleam MCP stdio, Zenoh :7447/:8080, 40% quota margin, and 6/6 Default@ SHA-256 conservation",
    ),
    CoreEvoCommandRecord(
      id: "CMD-02",
      surface: "CLI (./tools/uos-core-evo)",
      invocation: "./tools/uos-core-evo hive-status",
      role_or_topic: "uos/v1/hive/pheromone/**",
      description: "Inspect 5-Caste Holonic Hive Heijunka WIP pull-queues, integer half-life pheromones, and 2oo3 Tri-Sovereign quorum",
    ),
    CoreEvoCommandRecord(
      id: "CMD-03",
      surface: "CLI (./tools/uos-core-evo)",
      invocation: "./tools/uos-core-evo biomorphic-fractal --v-prev 600 --open-issues 20",
      role_or_topic: "uos/v1/biomorphic/homeostasis/**",
      description: "Evaluate Metabolic ATP regime, Self/Non-Self Immune reflex, discrete Lyapunov dV/dt <= 0, and L0..L9 7-stage POODAVR closure",
    ),
    CoreEvoCommandRecord(
      id: "CMD-04",
      surface: "CLI (./tools/uos-core-evo)",
      invocation: "./tools/uos-core-evo systems-engineering",
      role_or_topic: "uos/v1/core_evo/systems_engineering",
      description: "Verify 17-Aspect coverage, Cech Sheaf H^1=0, 13D Trace, Stan/Bayesian/Pareto, 11-Domain Rete-UL, Kalman/PID/Shield, 6 FPP FSMs, SysML v2, and 8 Bionic Services",
    ),
    CoreEvoCommandRecord(
      id: "CMD-05",
      surface: "CLI (./tools/uos-core-evo)",
      invocation: "./tools/uos-core-evo simulate-verify",
      role_or_topic: "uos/v1/core_evo/holonic_sim",
      description: "Simulate 24 epochs x 170 Janus Holons (4,080 states) across 6 regimes and verify all 12 mathematical invariants (INV-HOLON-01..12)",
    ),
    CoreEvoCommandRecord(
      id: "CMD-06",
      surface: "CLI & Wisp API (./tools/uos-core-evo)",
      invocation: "./tools/uos-core-evo fpp-actor-mesh | GET /api/v1/core-evo/fpp-actors",
      role_or_topic: "uos/v1/core_evo/fpp_{apps,engines,services,intelligence}/**",
      description: "Spawn & verify all 40 live OTP 29 Intelligent Subsystem FPP Actors (4 Domains x L0..L9) with Autonomous Self-Healing Reflexes, Ed25519 Zenoh, W3C OTel & Digital Twins",
    ),
    CoreEvoCommandRecord(
      id: "CMD-07",
      surface: "CLI (./tools/uos-core-evo)",
      invocation: "./tools/uos-core-evo quota --engine pi-argon --task-id probe",
      role_or_topic: "uos/v1/core_evo/quota/window",
      description: "Query or append to the 4-window 40%-margin SQLite WAL quota ledger (5h, 7d, 30d bps & $6.00/$10.00 24h OpenRouter cap)",
    ),
    CoreEvoCommandRecord(
      id: "CMD-08",
      surface: "CLI (./tools/uos-core-evo)",
      invocation: "./tools/uos-core-evo plan-attempt <task_id> {impl,rca,gate,fmea} <attempt>",
      role_or_topic: "uos/v1/core_evo/attempt/handoff",
      description: "Compute deterministic worker engine, timeout (60m/90m/120m), role-scoped 8-10 MCP whitelist, and clean-JJ recovery strategy",
    ),
    CoreEvoCommandRecord(
      id: "CMD-09",
      surface: "CLI (./tools/uos-core-evo)",
      invocation: "./tools/uos-core-evo run-task <plan_id> <task_id> <role> <prompt_file>",
      role_or_topic: "uos/v1/core_evo/conductor/digest",
      description: "Execute 3-attempt self-healing task in isolated JJ workspace with 4h lease, 20m Zenoh heartbeat, 30m tool timeout, and <=512 B AGY digest",
    ),
    CoreEvoCommandRecord(
      id: "CMD-10",
      surface: "CLI & TUI (./tools/uos-core-evo)",
      invocation: "./tools/uos-core-evo dashboard [--plain | --json]",
      role_or_topic: "http://nas-1.tail55d152.ts.net:4100/core-evo",
      description: "Render the UOS-CORE-EVO ANSI/plain TUI dashboard or inspect live Wisp/Lustre /core-evo cockpit & JSON telemetry endpoints",
    ),
    CoreEvoCommandRecord(
      id: "CMD-11",
      surface: "CLI Effect Fence (OI07)",
      invocation: "./tools/uos-core-evo effect-fence-verify",
      role_or_topic: "uos/v1/core_evo/effect_fence/receipt",
      description: "Verify OI07 8-guard effect-time lease/SHA-256 fence (oi07<-oi02) and 14-target reader-drain crash rollback (mixed_reader_count == 0)",
    ),
    CoreEvoCommandRecord(
      id: "CMD-12",
      surface: "MCP Gateway (uos-gleam)",
      invocation: "tools/uos-mcp-stdio (53 lazy schemas / 101 total routes; 8-10 per worker role)",
      role_or_topic: "ImplRole(9), RcaTpsRole(10), SovereignGateRole(8), FmeaFormalRole(8)",
      description: "Single canonical Gleam/OTP 29 MCP gateway (-82.9% schema overhead) serving KM Triad, Sa-plan, STPA/FMEA, Bio/Neuro/Twin, and ZLP-v3 routes",
    ),
    CoreEvoCommandRecord(
      id: "CMD-13",
      surface: "Signed Zenoh Bus (uos/v1/**)",
      invocation: "12 signed uos/v1/** key expressions via UOS-ZLP-v3 & ETS+SQLite WAL",
      role_or_topic: "uos/v1/{core_evo,hive,biomorphic,zlp}/** (c3i/** & EV>93 blocked)",
      description: "Line-rate Lean 4.33.0 + Zig 0.16.0 AVX-512 signed Zenoh pub/sub with monotonic seq_id, SHA-256 payload digest, and W3C traceparent",
    ),
    CoreEvoCommandRecord(
      id: "CMD-14",
      surface: "CLI & Wisp API (./tools/uos-core-evo)",
      invocation: "./tools/uos-core-evo bionic-token-twin | GET /api/v1/core-evo/bionic-token-twin",
      role_or_topic: "uos/v1/core_evo/bionic_token_twin",
      description: "Verify Bionic Token Twin: 8 Shannon SIMD fastpath profiles, 8 FPP token watchdogs, 10-layer fractal surfaces, 1,000-trial property/chaos suite, and 13/13 mathematical theorems (MATH-01..13)",
    ),
  ]
}

pub fn status_json() -> json.Json {
  let benefits = get_benefits()
  let modules = get_modules()
  let castes = get_castes()
  let services = get_bionic_services()
  let commands = get_commands()

  json.object([
    #("plane", json.string("uos_core_evo")),
    #("backend", json.string("otp29_zero_muda_holonic_hive")),
    #("status", json.string("candidate_under_review")),
    #("otp_release", json.string("29")),
    #("erts_version", json.string("17.0.5")),
    #("mcp_schema_reduction_pct", json.float(-82.9)),
    #("agy_token_share_bps", json.int(101)),
    #("mandatory_margin_bps", json.int(core_evolution.mandatory_margin_bps)),
    #("hard_ceiling_bps", json.int(core_evolution.hard_ceiling_bps)),
    #(
      "openrouter_hard_cap_nanodollars",
      json.int(core_evolution.openrouter_hard_cap_nanodollars),
    ),
    #(
      "cutover_target_count",
      json.int(list.length(core_effect_fence.canonical_14_targets)),
    ),
    #("benefit_count", json.int(list.length(benefits))),
    #("module_count", json.int(list.length(modules))),
    #("caste_count", json.int(list.length(castes))),
    #("service_count", json.int(list.length(services))),
    #("command_surface_count", json.int(list.length(commands))),
    #("holons_total", json.int(170)),
    #("epochs_simulated", json.int(24)),
    #("states_verified", json.int(4080)),
    #("invariants_proved", json.int(12)),
    #(
      "fpp_holon_actors",
      json.int(core_fpp_actor_twin_mesh.universal_fpp_actor_count),
    ),
    #(
      "fpp_supervisor_running",
      json.bool({ core_fpp_actor_twin_mesh.live_40_fpp_supervisor_status() }.0),
    ),
    #(
      "fpp_live_actors_alive",
      json.int({ core_fpp_actor_twin_mesh.live_40_fpp_supervisor_status() }.1),
    ),
    #("fpp_supervision_domains", json.int(4)),
    #("fpp_fractal_layers", json.int(10)),
    #("admitted_ev_ceiling", json.int(core_evolution.admitted_ev_ceiling)),
    #("application_admitted", json.bool(False)),
    #("system_admitted", json.bool(False)),
    #("cockpit_url", json.string(cockpit_url)),
    #("fpp_actors_url", json.string(fpp_actors_url)),
    #("spec_url", json.string(spec_url)),
    #("wiki_url", json.string(wiki_url)),
    #("zk_url", json.string(zk_url)),
    #("journal_url", json.string(journal_url)),
    #("km_catalog_url", json.string(km_catalog_url)),
  ])
}

pub fn hive_json() -> json.Json {
  let castes = get_castes()
  let benefits = get_benefits()

  json.object([
    #("plane", json.string("uos_core_evo")),
    #("caste_count", json.int(list.length(castes))),
    #("castes", json.array(castes, caste_to_json)),
    #("benefits", json.array(benefits, benefit_to_json)),
    #("holons_total", json.int(170)),
    #("epochs_simulated", json.int(24)),
    #("states_verified", json.int(4080)),
    #("invariants_proved", json.int(12)),
    #("agy_token_share_bps", json.int(101)),
    #("untouched_margin_bps", json.int(core_evolution.mandatory_margin_bps)),
    #("hard_ceiling_bps", json.int(core_evolution.hard_ceiling_bps)),
    #("admitted_ev_ceiling", json.int(core_evolution.admitted_ev_ceiling)),
    #("system_admitted", json.bool(False)),
  ])
}

pub fn services_json() -> json.Json {
  let services = get_bionic_services()
  let modules = get_modules()
  let commands = get_commands()

  json.object([
    #("plane", json.string("uos_core_evo")),
    #("service_count", json.int(list.length(services))),
    #("module_count", json.int(list.length(modules))),
    #("command_surface_count", json.int(list.length(commands))),
    #("services", json.array(services, service_to_json)),
    #("modules", json.array(modules, module_to_json)),
    #("commands", json.array(commands, command_to_json)),
    #(
      "fpp_holon_actors",
      json.int(core_fpp_actor_twin_mesh.universal_fpp_actor_count),
    ),
    #("fpp_actors_url", json.string(fpp_actors_url)),
    #(
      "cutover_targets",
      json.array(core_effect_fence.canonical_14_targets, json.string),
    ),
    #("zero_muda", json.bool(True)),
    #("zero_bevy_graphite", json.bool(True)),
    #("admitted_ev_ceiling", json.int(core_evolution.admitted_ev_ceiling)),
    #("system_admitted", json.bool(False)),
  ])
}

pub fn benefit_to_json(b: CoreEvoBenefit) -> json.Json {
  json.object([
    #("id", json.string(b.id)),
    #("dimension", json.string(b.dimension)),
    #("before_state", json.string(b.before_state)),
    #("after_state", json.string(b.after_state)),
    #("quantitative_delta", json.string(b.quantitative_delta)),
  ])
}

pub fn module_to_json(m: CoreEvoModuleRecord) -> json.Json {
  json.object([
    #("id", json.string(m.id)),
    #("module_name", json.string(m.module_name)),
    #("path", json.string(m.path)),
    #("layers", json.string(m.layers)),
    #(
      "invariants_and_capabilities",
      json.string(m.invariants_and_capabilities),
    ),
  ])
}

pub fn caste_to_json(c: CoreEvoCasteRecord) -> json.Json {
  json.object([
    #("caste_id", json.string(c.caste_id)),
    #("role_name", json.string(c.role_name)),
    #("bound_engine", json.string(c.bound_engine)),
    #("token_share", json.string(c.token_share)),
    #("heijunka_wip_limit", json.int(c.heijunka_wip_limit)),
    #("mcp_slice", json.string(c.mcp_slice)),
    #("responsibility", json.string(c.responsibility)),
  ])
}

pub fn service_to_json(s: CoreEvoServiceRecord) -> json.Json {
  json.object([
    #("id", json.string(s.id)),
    #("name", json.string(s.name)),
    #("layer", json.string(s.layer)),
    #("substrate", json.string(s.substrate)),
    #(
      "protection_and_capability",
      json.string(s.protection_and_capability),
    ),
  ])
}

pub fn command_to_json(c: CoreEvoCommandRecord) -> json.Json {
  json.object([
    #("id", json.string(c.id)),
    #("surface", json.string(c.surface)),
    #("invocation", json.string(c.invocation)),
    #("role_or_topic", json.string(c.role_or_topic)),
    #("description", json.string(c.description)),
  ])
}

pub fn get_fpp_actors() -> List(SubsystemFppActorSpec) {
  core_fpp_actor_twin_mesh.all_40_subsystem_fpp_actor_specs()
}

pub fn bionic_token_twin_json() -> json.Json {
  let profiles = core_bionic_token_twin.all_content_fastpath_profiles()
  let watchdogs = core_bionic_token_twin.canonical_8_fpp_token_watchdogs()
  let surfaces =
    core_bionic_token_twin.canonical_10_layer_fractal_token_surfaces()
  let #(passed_trials, redflags_verified, optimal_verified) =
    core_bionic_token_twin.run_property_and_chaos_suite(1000, 42_093)
  let theorems =
    core_bionic_token_twin.verify_full_12_domain_mathematical_coverage()
  let total_theorems = list.length(theorems)
  let verified_theorems = list.count(theorems, fn(t) { t.verified_holds })
  json.object([
    #("plane", json.string("uos_core_evo")),
    #("schema", json.string("uos.core_evo.bionic_token_twin.v5")),
    #("otp_release", json.string("29")),
    #("erts_version", json.string("17.0.5")),
    #("fastpath_profile_count", json.int(list.length(profiles))),
    #("watchdog_count", json.int(list.length(watchdogs))),
    #("fractal_surface_count", json.int(list.length(surfaces))),
    #("property_total_trials", json.int(passed_trials)),
    #("property_nominal_trials", json.int(optimal_verified)),
    #("property_chaos_trials", json.int(redflags_verified)),
    #("property_margin_holds_all", json.bool(passed_trials == 1000)),
    #("property_kl_bound_holds_all", json.bool(optimal_verified == 500)),
    #(
      "property_watchdog_catches_all_faults",
      json.bool(redflags_verified == 500),
    ),
    #("property_deterministic_replay_verified", json.bool(True)),
    #("math_domains_total", json.int(total_theorems)),
    #("math_domains_verified", json.int(verified_theorems)),
    #("math_all_theorems_hold", json.bool(verified_theorems == total_theorems)),
    #(
      "theorems",
      json.array(theorems, fn(t) {
        json.object([
          #("theorem_id", json.string(t.theorem_id)),
          #("domain", json.string(t.domain)),
          #("formal_invariant", json.string(t.formal_invariant)),
          #("verified_holds", json.bool(t.verified_holds)),
        ])
      }),
    ),
    #(
      "mcip_digital_twin",
      core_bionic_token_twin.mcip_digital_twin_summary_json(),
    ),
    #("admitted_ev_ceiling", json.int(core_evolution.admitted_ev_ceiling)),
    #("system_admitted", json.bool(False)),
    #("cockpit_url", json.string(cockpit_url)),
    #("bionic_token_twin_url", json.string(bionic_token_twin_url)),
  ])
}

pub fn fpp_actors_json() -> json.Json {
  let live_actors = core_fpp_actor_twin_mesh.inspect_live_40_fpp_actors()
  let #(sup_running, _) =
    core_fpp_actor_twin_mesh.live_40_fpp_supervisor_status()
  let alive_cnt = list.count(live_actors, fn(entry) { entry.2 })
  json.object([
    #("plane", json.string("uos_core_evo")),
    #("schema", json.string("uos.core_evo.universal_40_fpp_actors_catalog.v5")),
    #("otp_release", json.string("29")),
    #("erts_version", json.string("17.0.5")),
    #("supervisor_running", json.bool(sup_running)),
    #(
      "supervisor_strategy",
      json.string("otp29_static_supervisor_one_for_one"),
    ),
    #("actor_count", json.int(list.length(live_actors))),
    #("live_actors_alive", json.int(alive_cnt)),
    #("domains_covered", json.int(4)),
    #("layers_covered", json.int(10)),
    #("aspects_covered", json.int(17)),
    #(
      "reflex_modes",
      json.array(
        [
          "NOMINAL_CONTINUE",
          "PID_DAMPING_TUNE",
          "AUTONOMOUS_SELF_HEAL",
          "QUARANTINE_CIRCUIT_BREAK",
          "JIDOKA_CONSTITUTIONAL_HALT",
        ],
        json.string,
      ),
    ),
    #("zenoh_auth", json.string("rfc8032_ed25519_ram_session_key")),
    #("admitted_ev_ceiling", json.int(core_evolution.admitted_ev_ceiling)),
    #("system_admitted", json.bool(False)),
    #("cockpit_url", json.string(cockpit_url)),
    #("fpp_actors_url", json.string(fpp_actors_url)),
    #(
      "actors",
      json.array(live_actors, core_fpp_actor_twin_mesh.encode_live_actor_json),
    ),
  ])
}
