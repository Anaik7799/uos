//// =============================================================================
//// [C3I-SIL6-ASPECT-AGENTS] FRACTAL ASPECT AGENT ECOSYSTEM COORDINATOR
//// =============================================================================
//// Canonical agent ecosystem coverage engine mapping the 256 sovereign aerospace
//// agents across all 14 fractal architecture aspects and 104 features of UOS.
////
//// Enforces:
//// 1. 14 Fractal Aspects taxonomy with 104 discrete features
//// 2. 100% Agent-to-Aspect squad assignment across the 4 pillars (SDLC, SRE, Verif, Intel)
//// 3. Formal verification & governance contract bindings
//// 4. Typed JSON serialization for REST API and AG-UI event feeds
//// =============================================================================

import gleam/json
import gleam/list
import gleam/string

pub type FractalAspect {
  AspectComponentPacket
  AspectVerticalLadder
  AspectOrthogonalPlanes
  AspectSemanticStrata
  AspectHorizontalSubsystems
  AspectCodeSurfaces
  AspectInteractionPaths
  AspectDesignLattice
  AspectOntologyFaculties
  AspectCompletenessCriteria
  AspectWikiPipeline
  AspectProductionConjunction
  AspectCapabilityPoset
  AspectSaPlanDurability
}

pub type AspectCoverage {
  AspectCoverage(
    aspect: FractalAspect,
    name: String,
    pillar: String,
    primary_agent_kind: String,
    squad_size: Int,
    governing_contract: String,
    formal_verification_method: String,
  )
}

pub type AspectFeatureDetail {
  AspectFeatureDetail(
    aspect: FractalAspect,
    aspect_name: String,
    pillar: String,
    features: List(String),
    squad_agents: List(String),
    governing_contract: String,
    formal_verification_method: String,
  )
}

pub fn get_all_fractal_aspects() -> List(FractalAspect) {
  [
    AspectComponentPacket,
    AspectVerticalLadder,
    AspectOrthogonalPlanes,
    AspectSemanticStrata,
    AspectHorizontalSubsystems,
    AspectCodeSurfaces,
    AspectInteractionPaths,
    AspectDesignLattice,
    AspectOntologyFaculties,
    AspectCompletenessCriteria,
    AspectWikiPipeline,
    AspectProductionConjunction,
    AspectCapabilityPoset,
    AspectSaPlanDurability,
  ]
}

pub fn get_aspect_coverage(aspect: FractalAspect) -> AspectCoverage {
  case aspect {
    AspectComponentPacket ->
      AspectCoverage(
        aspect: AspectComponentPacket,
        name: "11-Field Reusable Component Packet",
        pillar: "C3I-SDLC",
        primary_agent_kind: "SdlcComponentPacketSynthesizer",
        squad_size: 18,
        governing_contract: "SC-COMP-PACKET-001",
        formal_verification_method: "Property-based generation with >= 2 killed mutants",
      )
    AspectVerticalLadder ->
      AspectCoverage(
        aspect: AspectVerticalLadder,
        name: "L0-L10 Vertical Refinement Ladder",
        pillar: "C3I-SDLC",
        primary_agent_kind: "SdlcVerticalRefinementGovernor",
        squad_size: 18,
        governing_contract: "SC-VERT-LADDER-001",
        formal_verification_method: "Exact revision boundary audit and EV-cycle gating",
      )
    AspectOrthogonalPlanes ->
      AspectCoverage(
        aspect: AspectOrthogonalPlanes,
        name: "9 Orthogonal Interaction Planes",
        pillar: "C3I-SDLC",
        primary_agent_kind: "SdlcPlaneHarmonizerAgent",
        squad_size: 18,
        governing_contract: "SC-PLANES-001",
        formal_verification_method: "Plane boundary isolation and non-bypass proofs",
      )
    AspectSemanticStrata ->
      AspectCoverage(
        aspect: AspectSemanticStrata,
        name: "3 Semantic Strata (A / B / C)",
        pillar: "C3I-VERIFICATION",
        primary_agent_kind: "VerifStrataIsolationAuditor",
        squad_size: 18,
        governing_contract: "SC-STRATA-001",
        formal_verification_method: "Stratum A independence from Stratum C hardware proofs",
      )
    AspectHorizontalSubsystems ->
      AspectCoverage(
        aspect: AspectHorizontalSubsystems,
        name: "33 Horizontal OTP Subsystems (S1-S33)",
        pillar: "C3I-SDLC",
        primary_agent_kind: "SdlcSubsystemDomainGovernor",
        squad_size: 33,
        governing_contract: "SC-SUBSYS-001",
        formal_verification_method: "100% Gleam/BEAM file-level mapping and unit suite",
      )
    AspectCodeSurfaces ->
      AspectCoverage(
        aspect: AspectCodeSurfaces,
        name: "12 Key Code Map Surfaces",
        pillar: "C3I-SRE",
        primary_agent_kind: "SreCodeSurfaceMonitorAgent",
        squad_size: 18,
        governing_contract: "SC-SURF-001",
        formal_verification_method: "Zero-Trust dispatch hook and Cryptokit SHA-256 digests",
      )
    AspectInteractionPaths ->
      AspectCoverage(
        aspect: AspectInteractionPaths,
        name: "7 Critical System Paths (5-Stage Flows)",
        pillar: "C3I-SRE",
        primary_agent_kind: "SreInteractionPathSentinel",
        squad_size: 18,
        governing_contract: "SC-FLOW-001",
        formal_verification_method: "Source->Interface->Transformation->Observer->Governor sequence check",
      )
    AspectDesignLattice ->
      AspectCoverage(
        aspect: AspectDesignLattice,
        name: "10-Stage Design Lattice (W0-W9) & 4 UCA Types",
        pillar: "C3I-SDLC",
        primary_agent_kind: "SdlcDesignLatticeGovernor",
        squad_size: 18,
        governing_contract: "SC-DESIGN-001",
        formal_verification_method: "STPA UCA hazard trapping (Not performed, Wrong, Out of order, Duration)",
      )
    AspectOntologyFaculties ->
      AspectCoverage(
        aspect: AspectOntologyFaculties,
        name: "Living Ontology 10 Faculties",
        pillar: "C3I-INTELLIGENCE",
        primary_agent_kind: "IntelOntologyCognitiveHolon",
        squad_size: 20,
        governing_contract: "SC-ONTO-001",
        formal_verification_method: "Cognitive feedback loop with 13D TCM conservation",
      )
    AspectCompletenessCriteria ->
      AspectCoverage(
        aspect: AspectCompletenessCriteria,
        name: "Six Fractal Completeness Criteria (CC1-CC6)",
        pillar: "C3I-VERIFICATION",
        primary_agent_kind: "VerifCompletenessAuditor",
        squad_size: 16,
        governing_contract: "SC-COMPL-001",
        formal_verification_method: "Conjunctive boolean audit across all live subsystems",
      )
    AspectWikiPipeline ->
      AspectCoverage(
        aspect: AspectWikiPipeline,
        name: "Wiki/ZK Pipeline Recursion & Aho-Corasick Search",
        pillar: "C3I-INTELLIGENCE",
        primary_agent_kind: "IntelKnowledgePipelineAgent",
        squad_size: 16,
        governing_contract: "SC-WIKI-001",
        formal_verification_method: "Backlink inversion and lossless Markdown-to-HTML projection",
      )
    AspectProductionConjunction ->
      AspectCoverage(
        aspect: AspectProductionConjunction,
        name: "Production Conjunction (F / C / O / P / S / R)",
        pillar: "C3I-VERIFICATION",
        primary_agent_kind: "VerifProductionConjunctionJudge",
        squad_size: 15,
        governing_contract: "SC-FCOPSR-001",
        formal_verification_method: "6-axis boolean conjunction with zero false-green tolerance",
      )
    AspectCapabilityPoset ->
      AspectCoverage(
        aspect: AspectCapabilityPoset,
        name: "Capability State Poset Lattice (ABSENT < UNTESTED < EQUIV < EQ)",
        pillar: "C3I-VERIFICATION",
        primary_agent_kind: "VerifPosetLatticeGuardian",
        squad_size: 15,
        governing_contract: "SC-POSET-001",
        formal_verification_method: "Meet semilattice ordering preventing unverified promotion",
      )
    AspectSaPlanDurability ->
      AspectCoverage(
        aspect: AspectSaPlanDurability,
        name: "Pure BEAM Sa-Plan Durability & Lease Claim",
        pillar: "C3I-SRE",
        primary_agent_kind: "SreSaPlanLeaseManagerAgent",
        squad_size: 15,
        governing_contract: "SC-SA-PLAN-001",
        formal_verification_method: "Append-only activity logs and worker lease re-claim checks",
      )
  }
}

pub fn get_aspect_features(aspect: FractalAspect) -> List(String) {
  case aspect {
    AspectComponentPacket -> [
      "F01_COMPONENT_SPEC: Active, Passive, Queued, Singleton FPP component declaration",
      "F02_PORT_INTERFACES: Typed sync/async port connections with directionality (Input/Output)",
      "F03_COMMAND_DISPATCH: Opcode-based opcode decoding and telemetry channel multiplexing",
      "F04_PARAM_DB_SYNC: Parameter table sync with default PRM fallbacks",
      "F05_TELEMETRY_CHANNELS: Low/high-water telemetry channels with rate decimation",
      "F06_EVENT_LOG_BUFFER: Severity-indexed event emission (Diagnostic, Warning, Fatal)",
      "F07_HSM_INTEGRATION: State machine state vector hook with LCA transition dispatch",
      "F08_HEALTH_PING: Watchdog ping/reply dead-man freshness monitoring",
      "F09_ZERO_MUDA_VFS: Descriptor-relative memory mapped zero-copy I/O",
      "F10_13D_TCM_COORDINATE: Coordinate vector T_13 tag conservation",
      "F11_OTEL_TRACE_ATTACHMENT: W3C 128-bit trace context attachment",
    ]
    AspectVerticalLadder -> [
      "F12_L0_CONSTITUTIONAL: 2oo3 constitutional veto and emergency Jidoka halt",
      "F13_L1_ATOMIC_NIF: Safe C-ABI non-blocking deterministic micro-kernels",
      "F14_L2_QUORUM_HEALTH: Distributed Raft/Paxos consensus health monitoring",
      "F15_L3_TRANSACTION_WAL: SQLite append-only WAL transaction ledger",
      "F16_L4_SUPERVISION_OTP: 4-domain BEAM supervisor tree (uos_sup.gleam)",
      "F17_L5_COGNITIVE_OODA: 4-stage OODA loop with loss-bounded context compression",
      "F18_L6_ECOSYSTEM_MESH: Zenoh distributed pub/sub mesh routing",
      "F19_L7_FEDERATION_SIL6: Tri-sovereign multi-node federation protocol",
      "F20_L8_META_EVOLUTION: Monotonic bytecode and rule synthesizer",
      "F21_L9_RULIAD_FRONTIER: Mathematical theorem proving and frontier search",
      "F22_L10_TRANSCENDENT: Infinite-horizon invariant preservation",
    ]
    AspectOrthogonalPlanes -> [
      "F23_PLANE_CONTROL: Pure state machine transition and dispatch control plane",
      "F24_PLANE_DATA: High-throughput binary packet transfer plane",
      "F25_PLANE_TELEMETRY: Continuous metric streaming and decimation plane",
      "F26_PLANE_OBSERVABILITY: Universal structured C3I JSON logging and spans",
      "F27_PLANE_GOVERNANCE: Policy validation, license, and charter enforcement",
      "F28_PLANE_EVIDENCE: Gospel contracts, Z3 queries, and test ledgers",
      "F29_PLANE_SAFETY: Hardware NVMe drive interlock and SIL-6 fail-closed trip",
      "F30_PLANE_KNOWLEDGE: Hermes wiki AST, ZigVM ZK, and living ontology",
      "F31_PLANE_INTERACTION: Tailscale Web cockpit, Wisp REST API, and ANSI TUI",
    ]
    AspectSemanticStrata -> [
      "F32_STRATUM_A_SPEC: Denotational gospel and quint formal intent specifications",
      "F33_STRATUM_B_KERNEL: Pure functional Gleam/OTP state machines and supervisors",
      "F34_STRATUM_C_HARDWARE: Physical host NVMe, OS kernel, and network interface",
      "F35_STRATA_A_B_ISOMORPHISM: Formal bisimulation between Stratum A and B",
      "F36_STRATA_B_C_INTERLOCK: Hardware isolation preventing Stratum C bypass",
      "F37_STRATA_VERIFICATION: Continuous differential oracle checking parity",
    ]
    AspectHorizontalSubsystems -> [
      "F38_S1_S8_CORE_APPS: Supervision, agents, domain types, and web cockpits",
      "F39_S9_S16_ENGINES: ZigVM kernel, Hermes formal engine, and MAX inference",
      "F40_S17_S24_VERIFICATION: 9-dimension testing, differential parity, and oracles",
      "F41_S25_S33_GOVERNANCE: Standalone Jujutsu, Tailscale web, and ZK/Wiki KM",
    ]
    AspectCodeSurfaces -> [
      "F42_SURF_FPP_MODELS: FPP model definitions and component packets",
      "F43_SURF_GLEAM_OTP: Root supervisor, actors, and state machines",
      "F44_SURF_HERMES_OCAML: Parity algebra, Gospel specs, and Zero-Trust hook",
      "F45_SURF_ZIGVM_VFS: Deterministic bytecode kernel and race-free VFS",
      "F46_SURF_RUST_K8S: Kubernetes Rook-Ceph storage controller locking OS NVMe",
      "F47_SURF_MAX_MOJO: Quarantined Python length-delimited JSON-RPC daemon",
      "F48_SURF_LEAN_PROOFS: Traceability.lean and TwoLattice_STM.lean proofs",
      "F49_SURF_QUINT_PARITY: parity_frontier.qnt intent closure simulation",
      "F50_SURF_SQLITE_WAL: Append-only living catalog and test tracking databases",
      "F51_SURF_LUSTRE_UI: Server-rendered MVU HTML web cockpit without client JS",
      "F52_SURF_WISP_API: Strongly typed JSON REST API endpoints",
      "F53_SURF_ANSI_TUI: Split-screen terminal dashboard with ANSI sparklines",
    ]
    AspectInteractionPaths -> [
      "F54_PATH_COMMAND_INTENT: Command ingestion -> guard check -> dispatch",
      "F55_PATH_TELEMETRY_PIPELINE: Sample generation -> rate decimate -> publish",
      "F56_PATH_OODA_COGNITION: Observe -> Orient -> Decide -> Act loop",
      "F57_PATH_SAFETY_INTERLOCK: Device serial check -> fail-closed trip -> halt",
      "F58_PATH_WIKI_TRANSCLUSION: AST parse -> backlink invert -> TyXML render",
      "F59_PATH_DIFF_PARITY: Digest calculation -> oracle compare -> ledger write",
      "F60_PATH_SA_PLAN_LEASE: Task claim -> WAL log -> heartbeat -> commit",
    ]
    AspectDesignLattice -> [
      "F61_STAGE_W0_W3_FOUNDATION: Concept, requirement, architecture, and formal spec",
      "F62_STAGE_W4_W6_CONSTRUCTION: Implementation, unit verification, and integration",
      "F63_STAGE_W7_W9_RELEASE: Parity audit, field soak, and admission sign-off",
      "F64_UCA1_NOT_PERFORMED: Traps missing safety command during critical transition",
      "F65_UCA2_WRONG_ACTION: Traps incorrect action execution under valid context",
      "F66_UCA3_OUT_OF_ORDER: Traps sequence inversion in 5-stage flows",
      "F67_UCA4_DURATION_HAZARD: Traps command execution timeout or premature abort",
    ]
    AspectOntologyFaculties -> [
      "F68_FACULTY_PERCEPTION: Sensory and telemetry feature extraction",
      "F69_FACULTY_ATTENTION: Priority weighting and focus allocation",
      "F70_FACULTY_MEMORY: Episodic and semantic ZK/Wiki graph storage",
      "F71_FACULTY_REASONING: Forward-chaining Rete-UL rule evaluation",
      "F72_FACULTY_LEARNING: Continuous weight and Bayesian prior updating",
      "F73_FACULTY_DECISION: 2oo3 consensus and denotational intent emission",
      "F74_FACULTY_EXPRESSION: Lustre HTML, Wisp JSON, and ANSI TUI rendering",
      "F75_FACULTY_ACTION: Bounded deterministic native kernel execution",
      "F76_FACULTY_META_COGNITION: Self-evaluating error bounds and entropy tracking",
      "F77_FACULTY_FRACTAL_RESONANCE: Sheaf gluing across all 11 hierarchical layers",
    ]
    AspectCompletenessCriteria -> [
      "F78_CC1_FORMAL_PROOFS: Every theorem proved without sorry or Admitted",
      "F79_CC2_ZERO_MUDA: 0 Bevy, 0 Graphite, 0 foreign NIF shared libraries",
      "F80_CC3_GOLD_STANDARD: Full C1-C8 testing gold standard with >= 90% CCM",
      "F81_CC4_STORAGE_LOCK: NVMe serial 25503L801736 locked in spec.rs:192",
      "F82_CC5_TRIPLE_INTERFACE: Lustre Web, Wisp API, ANSI TUI for all features",
      "F83_CC6_TIMESTAMP_MANDATE: All docs carry YYYYMMDD-HHSS- timestamp prefix",
    ]
    AspectWikiPipeline -> [
      "F84_WIKI_AST_PARSER: TyXML-compliant Markdown AST syntax validation",
      "F85_ZK_TRANSCLUSION: Bidirectional [[wiki:...]] and [[zk:...]] resolver",
      "F86_AHO_CORASICK_SEARCH: Multi-pattern substring search across knowledge corpus",
      "F87_BACKLINK_INVERSION: Automatic backlink graph extraction and linking",
      "F88_TAG_TAXONOMY_INDEX: Standardization of #fractal-l0..l9, #zero-muda",
    ]
    AspectProductionConjunction -> [
      "F89_PHI_F_FUNCTIONALITY: All functional acceptance requirements satisfied",
      "F90_PHI_C_CONCURRENCY: Race-free lockless execution on BEAM OTP 29",
      "F91_PHI_O_OBSERVABILITY: Universal C3I microsecond UTC ISO 8601 logging",
      "F92_PHI_P_PERFORMANCE: Shannon entropy H >= 2.5b, roundtrip < 100us",
      "F93_PHI_S_SAFETY: STPA safety constraints and OS NVMe lock enforced",
      "F94_PHI_R_RESILIENCE: Multi-layer supervisor restart budgets and recovery",
    ]
    AspectCapabilityPoset -> [
      "F95_POSET_ABSENT: Initial state - capability is unmapped and absent",
      "F96_POSET_UNTESTED: Capability implemented in code but lacking test proof",
      "F97_POSET_EQUIV: Capability verified against differential reference oracle",
      "F98_POSET_EQ: Sovereign admission - 100% formal proof, tested, and sealed",
      "F99_POSET_TRANSITION_GUARD: Strictly monotonic promotion preventing regression",
    ]
    AspectSaPlanDurability -> [
      "F100_SA_PLAN_ACTIVITY_WAL: Append-only SQLite WAL activity ledger",
      "F101_SA_PLAN_WORKER_LEASE: Exclusive single-writer timed lease claim",
      "F102_SA_PLAN_IDEMPOTENT_EXEC: Exactly-once execution semantics",
      "F103_SA_PLAN_FORECAST_MEET: Meet semilattice bounded forecast calculations",
      "F104_SA_PLAN_SWARM_OFFLOAD: Dynamic task delegation across agent squads",
    ]
  }
}

pub fn get_aspect_squad_agents(aspect: FractalAspect) -> List(String) {
  case aspect {
    AspectComponentPacket -> [
      "SdlcComponentPacketSynthesizer",
      "SdlcPortInterfaceBinder",
      "SdlcCommandDispatchRouter",
      "SdlcParamDbSynchronizer",
      "SdlcTelemetryChannelDemux",
      "SdlcEventLogBufferManager",
      "SdlcHsmIntegrationComposer",
      "SdlcWatchdogHealthPing",
      "SdlcZeroMudaVfsAccessor",
      "Sdlc13DCoordinateAttacher",
      "SdlcOtelTracePropagator",
      "SdlcComponentSchemaValidator",
      "SdlcPassivePortBridge",
      "SdlcActiveQueueEnforcer",
      "SdlcSingletonInstanceGovernor",
      "SdlcMutantTestGenerator",
      "SdlcPacketizerStreamEngine",
      "SdlcComponentLifecycleSupervisor",
    ]
    AspectVerticalLadder -> [
      "SdlcVerticalRefinementGovernor",
      "SdlcL0ConstitutionalConsensusAgent",
      "SdlcL1AtomicNifGovernor",
      "SdlcL2QuorumHealthAgent",
      "SdlcL3TransactionWalAgent",
      "SdlcL4SupervisionOtpAgent",
      "SdlcL5CognitiveOodaAgent",
      "SdlcL6EcosystemMeshAgent",
      "SdlcL7FederationSil6Agent",
      "SdlcL8MetaEvolutionAgent",
      "SdlcL9RuliadFrontierAgent",
      "SdlcL10TranscendentInvariantAgent",
      "SdlcLadderRefinementProver",
      "SdlcCrossLayerBoundaryAuditor",
      "SdlcHolonHierarchySupervisor",
      "SdlcEvCycleMilestoneGatingAgent",
      "SdlcVerticalParityAssuranceAgent",
      "SdlcUniversalLadderCoordinator",
    ]
    AspectOrthogonalPlanes -> [
      "SdlcPlaneHarmonizerAgent",
      "SdlcControlPlaneSentinel",
      "SdlcDataPlaneThroughputGovernor",
      "SdlcTelemetryPlaneDecimator",
      "SdlcObservabilityPlaneCorrelator",
      "SdlcGovernancePlaneAuditor",
      "SdlcEvidencePlaneLedgerKeeper",
      "SdlcSafetyPlaneInterlockAgent",
      "SdlcKnowledgePlaneTransclusionAgent",
      "SdlcInteractionPlaneUxRouter",
      "SdlcPlaneIsolationProofAgent",
      "SdlcZeroInterferenceValidator",
      "SdlcCrossPlaneContractVerifier",
      "SdlcOrthogonalRegionResolver",
      "SdlcPlaneSynchronizerAgent",
      "SdlcPlaneTelemetryMirror",
      "SdlcPlaneSecurityBoundaryKeeper",
      "SdlcMultiPlaneSupervisor",
    ]
    AspectSemanticStrata -> [
      "VerifStrataIsolationAuditor",
      "VerifStratumADenotationalSpecifier",
      "VerifStratumBKernelAuditor",
      "VerifStratumCHardwareInterlock",
      "VerifStrataBisimulationProver",
      "VerifStratumANegationTester",
      "VerifStratumBStateParityChecker",
      "VerifStratumCDeviceSerialLocker",
      "VerifStrataRefinementOracle",
      "VerifStrataDifferentialComparer",
      "VerifStrataGospelContractChecker",
      "VerifStrataTypePreservationAgent",
      "VerifStrataAlgebraicAtlasBridge",
      "VerifStrataIsolationSentinel",
      "VerifStrataProofExtractionAgent",
      "VerifStrataBoundarySanitizer",
      "VerifStrataConformanceReporter",
      "VerifStrataMasterCoordinator",
    ]
    AspectHorizontalSubsystems -> [
      "SdlcSubsystemDomainGovernor",
      "SdlcSubsystemS1AppsCepaf",
      "SdlcSubsystemS2AppsIndrajaal",
      "SdlcSubsystemS3AppsAdminUi",
      "SdlcSubsystemS4AppsTuiConsole",
      "SdlcSubsystemS5AppsRestApi",
      "SdlcSubsystemS6AppsEventStream",
      "SdlcSubsystemS7AppsMobileAdaptive",
      "SdlcSubsystemS8AppsVoiceAgent",
      "SdlcSubsystemS9EnginesZigvmKernel",
      "SdlcSubsystemS10EnginesHermesOracle",
      "SdlcSubsystemS11EnginesMaxInference",
      "SdlcSubsystemS12EnginesGrapheneErlang",
      "SdlcSubsystemS13EnginesMojoAccelerate",
      "SdlcSubsystemS14EnginesZ3SolverWorker",
      "SdlcSubsystemS15EnginesReteForwardChain",
      "SdlcSubsystemS16EnginesAhoCorasickSearch",
      "SdlcSubsystemS17VerifNineModality",
      "SdlcSubsystemS18VerifDmcTcmAtlas",
      "SdlcSubsystemS19VerifDiffParity",
      "SdlcSubsystemS20VerifStpaSafety",
      "SdlcSubsystemS21VerifGospelOrtac",
      "SdlcSubsystemS22VerifLeanProofs",
      "SdlcSubsystemS23VerifQuintParity",
      "SdlcSubsystemS24VerifChecklistDoctor",
      "SdlcSubsystemS25GovJujutsuMonorepo",
      "SdlcSubsystemS26GovTailscaleWeb",
      "SdlcSubsystemS27GovWikiEngine",
      "SdlcSubsystemS28GovZkDecisionRecords",
      "SdlcSubsystemS29GovLivingOntology",
      "SdlcSubsystemS30GovCapabilityInventory",
      "SdlcSubsystemS31GovTimestampMandate",
      "SdlcSubsystemS32GovZeroMudaPurity",
    ]
    AspectCodeSurfaces -> [
      "SreCodeSurfaceMonitorAgent",
      "SreFppModelsSurfaceWatcher",
      "SreGleamOtpSurfaceWatcher",
      "SreHermesOcamlSurfaceWatcher",
      "SreZigvmVfsSurfaceWatcher",
      "SreRustK8sSurfaceWatcher",
      "SreMaxMojoSurfaceWatcher",
      "SreLeanProofsSurfaceWatcher",
      "SreQuintParitySurfaceWatcher",
      "SreSqliteWalSurfaceWatcher",
      "SreLustreUiSurfaceWatcher",
      "SreWispApiSurfaceWatcher",
      "SreAnsiTuiSurfaceWatcher",
      "SreSurfaceDriftDetector",
      "SreZeroTrustPayloadInterceptor",
      "SreCryptokitSha256Validator",
      "SreBoundaryViolationAlerter",
      "SreSurfaceHealthSynthesizer",
    ]
    AspectInteractionPaths -> [
      "SreInteractionPathSentinel",
      "SreCommandIntentPathGovernor",
      "SreTelemetryPipelinePathGovernor",
      "SreOodaCognitionPathGovernor",
      "SreSafetyInterlockPathGovernor",
      "SreWikiTransclusionPathGovernor",
      "SreDiffParityPathGovernor",
      "SreSaPlanLeasePathGovernor",
      "SrePathLatencyBenchmarkAgent",
      "SrePathFlowStageValidator",
      "SreSourceInterfaceStageAuditor",
      "SreTransformStageAuditor",
      "SreObserverStageAuditor",
      "SreGovernorStageAuditor",
      "SreDeadlockDetectionAgent",
      "SreQueueBackpressureAlerter",
      "SreCircuitBreakerPathGovernor",
      "SrePathOrchestrationSupervisor",
    ]
    AspectDesignLattice -> [
      "SdlcDesignLatticeGovernor",
      "SdlcStageW0ConceptGovernor",
      "SdlcStageW1ReqSpecifier",
      "SdlcStageW2ArchDesigner",
      "SdlcStageW3FormalProver",
      "SdlcStageW4CodeImplementer",
      "SdlcStageW5UnitTestGovernor",
      "SdlcStageW6IntegrationGovernor",
      "SdlcStageW7ParityAuditor",
      "SdlcStageW8FieldSoakGovernor",
      "SdlcStageW9AdmissionGovernor",
      "SdlcUca1NotPerformedHazardSentinel",
      "SdlcUca2WrongActionHazardSentinel",
      "SdlcUca3OutOfOrderHazardSentinel",
      "SdlcUca4DurationHazardSentinel",
      "SdlcStpaConstraintSynthesizer",
      "SdlcGateAdvancementAuditor",
      "SdlcLatticeLifecycleSupervisor",
    ]
    AspectOntologyFaculties -> [
      "IntelOntologyCognitiveHolon",
      "IntelFacultyPerceptionAgent",
      "IntelFacultyAttentionAgent",
      "IntelFacultyMemoryAgent",
      "IntelFacultyReasoningAgent",
      "IntelFacultyLearningAgent",
      "IntelFacultyDecisionAgent",
      "IntelFacultyExpressionAgent",
      "IntelFacultyActionAgent",
      "IntelFacultyMetaCognitionAgent",
      "IntelFacultyFractalResonanceAgent",
      "IntelLivingOntologySyncAgent",
      "IntelEpisodicClusterUpdater",
      "IntelSemanticRelationExtractor",
      "IntelPriorBeliefUpdater",
      "IntelHypothesisGenerationAgent",
      "IntelOntologyValidationSentinel",
      "IntelCrossSubsystemSemanticsAgent",
      "IntelOntologyQueryDispatcher",
      "IntelOntologyEcosystemGovernor",
    ]
    AspectCompletenessCriteria -> [
      "VerifCompletenessAuditor",
      "VerifCc1FormalProofAuditor",
      "VerifCc2ZeroMudaAuditor",
      "VerifCc3GoldStandardAuditor",
      "VerifCc4StorageSafetyAuditor",
      "VerifCc5TripleInterfaceAuditor",
      "VerifCc6TimestampMandateAuditor",
      "VerifCompletenessConjunctionEngine",
      "VerifProofWithoutSorryChecker",
      "VerifNoForeignNifChecker",
      "VerifMathGatesAssuranceAgent",
      "VerifNvmeSerialLockChecker",
      "VerifTripleUiParityChecker",
      "VerifDocTimestampRegexChecker",
      "VerifCompletenessGatekeeper",
      "VerifCompletenessRatifier",
    ]
    AspectWikiPipeline -> [
      "IntelKnowledgePipelineAgent",
      "IntelWikiAstParserAgent",
      "IntelZkTransclusionResolver",
      "IntelAhoCorasickSearchWorker",
      "IntelBacklinkInversionEngine",
      "IntelTagTaxonomyStandardizer",
      "IntelMarkdownLosslessConverter",
      "IntelTyxmlHtmlRenderer",
      "IntelWikiCorpusIndexer",
      "IntelZkMocConsistencyChecker",
      "IntelAdrNumberingAuditor",
      "IntelWikiVectorSimilarityWorker",
      "IntelKnowledgeGraphBuilder",
      "IntelWikiIntegritySentinel",
      "IntelKnowledgeSyncSupervisor",
      "IntelKnowledgeEcosystemGovernor",
    ]
    AspectProductionConjunction -> [
      "VerifProductionConjunctionJudge",
      "VerifPhiFunctionalityAuditor",
      "VerifPhiConcurrencyAuditor",
      "VerifPhiObservabilityAuditor",
      "VerifPhiPerformanceAuditor",
      "VerifPhiSafetyAuditor",
      "VerifPhiResilienceAuditor",
      "VerifConjunctionTruthEvaluator",
      "VerifZeroFalseGreenEnforcer",
      "VerifStrictConjunctionGate",
      "VerifConjunctionTelemetryReporter",
      "VerifConjunctionCircuitTripper",
      "VerifConjunctionPreflightChecker",
      "VerifConjunctionPostflightAuditor",
      "VerifConjunctionSupervisor",
    ]
    AspectCapabilityPoset -> [
      "VerifPosetLatticeGuardian",
      "VerifPosetAbsentStateMonitor",
      "VerifPosetUntestedStateMonitor",
      "VerifPosetEquivStateMonitor",
      "VerifPosetEqStateMonitor",
      "VerifPosetMonotonicityEnforcer",
      "VerifPosetMeetSemilatticeProver",
      "VerifPosetAntiSymmetryChecker",
      "VerifPosetReflexivityChecker",
      "VerifPosetTransitivityChecker",
      "VerifPosetPromotionGatekeeper",
      "VerifPosetDemotionCircuitBreaker",
      "VerifPosetAuditReporter",
      "VerifPosetRegistrySynchronizer",
      "VerifPosetEcosystemGovernor",
    ]
    AspectSaPlanDurability -> [
      "SreSaPlanLeaseManagerAgent",
      "SreSaPlanActivityWalLogger",
      "SreSaPlanWorkerLeaseClaimer",
      "SreSaPlanIdempotentExecutor",
      "SreSaPlanForecastMeetCalculator",
      "SreSaPlanSwarmOffloadRouter",
      "SreSaPlanHeartbeatMonitor",
      "SreSaPlanLeaseExpiryReclaimer",
      "SreSaPlanTransactionRollbackAgent",
      "SreSaPlanStateCompactor",
      "SreSaPlanDurabilityAuditor",
      "SreSaPlanParityChecker",
      "SreSaPlanResilienceGovernor",
      "SreSaPlanRecoveryCoordinator",
      "SreSaPlanEcosystemSupervisor",
    ]
  }
}

pub fn get_aspect_feature_detail(aspect: FractalAspect) -> AspectFeatureDetail {
  let cov = get_aspect_coverage(aspect)
  let features = get_aspect_features(aspect)
  let squad = get_aspect_squad_agents(aspect)
  AspectFeatureDetail(
    aspect: aspect,
    aspect_name: cov.name,
    pillar: cov.pillar,
    features: features,
    squad_agents: squad,
    governing_contract: cov.governing_contract,
    formal_verification_method: cov.formal_verification_method,
  )
}

pub fn get_all_aspect_feature_details() -> List(AspectFeatureDetail) {
  list.map(get_all_fractal_aspects(), get_aspect_feature_detail)
}

pub fn get_all_features() -> List(String) {
  get_all_fractal_aspects()
  |> list.map(get_aspect_features)
  |> list.flatten
}

pub fn get_total_aspect_squad_agents() -> Int {
  get_all_fractal_aspects()
  |> list.map(fn(a) { get_aspect_coverage(a).squad_size })
  |> list.fold(0, fn(acc, count) { acc + count })
}

pub fn verify_full_aspect_coverage() -> Bool {
  let aspects = get_all_fractal_aspects()
  list.length(aspects) == 14
  && list.all(aspects, fn(a) {
    let cov = get_aspect_coverage(a)
    cov.squad_size > 0
    && !string.is_empty(cov.name)
    && !string.is_empty(cov.pillar)
    && !string.is_empty(cov.primary_agent_kind)
    && !string.is_empty(cov.governing_contract)
    && !string.is_empty(cov.formal_verification_method)
  })
  && get_total_aspect_squad_agents() == 256
}

pub fn verify_all_features_covered() -> Bool {
  let details = get_all_aspect_feature_details()
  let all_features = get_all_features()
  list.length(details) == 14
  && list.length(all_features) == 104
  && list.all(details, fn(d) {
    let squad_match =
      list.length(d.squad_agents)
      == list.length(get_aspect_squad_agents(d.aspect))
    d.features != [] && squad_match
  })
  && get_total_aspect_squad_agents() == 256
}

pub fn lookup_aspect_by_feature(
  feature_keyword: String,
) -> Result(AspectFeatureDetail, Nil) {
  let details = get_all_aspect_feature_details()
  list.find(details, fn(d) {
    list.any(d.features, fn(f) { string.contains(f, feature_keyword) })
  })
}

pub fn lookup_aspect_by_agent(
  agent_name: String,
) -> Result(AspectFeatureDetail, Nil) {
  let details = get_all_aspect_feature_details()
  list.find(details, fn(d) { list.contains(d.squad_agents, agent_name) })
}

pub fn encode_aspect_coverage_json(aspects: List(AspectCoverage)) -> String {
  let items =
    list.map(aspects, fn(cov) {
      json.object([
        #("name", json.string(cov.name)),
        #("pillar", json.string(cov.pillar)),
        #("primary_agent_kind", json.string(cov.primary_agent_kind)),
        #("squad_size", json.int(cov.squad_size)),
        #("governing_contract", json.string(cov.governing_contract)),
        #(
          "formal_verification_method",
          json.string(cov.formal_verification_method),
        ),
      ])
    })

  json.object([
    #("status", json.string("ok")),
    #("total_aspects", json.int(list.length(aspects))),
    #("total_agents_deployed", json.int(get_total_aspect_squad_agents())),
    #("full_coverage_verified", json.bool(verify_full_aspect_coverage())),
    #("aspects", json.array(items, fn(x) { x })),
  ])
  |> json.to_string
}

pub fn encode_aspect_features_json(
  details: List(AspectFeatureDetail),
) -> String {
  let items =
    list.map(details, fn(d) {
      json.object([
        #("aspect_name", json.string(d.aspect_name)),
        #("pillar", json.string(d.pillar)),
        #("squad_size", json.int(list.length(d.squad_agents))),
        #("features", json.array(d.features, json.string)),
        #("squad_agents", json.array(d.squad_agents, json.string)),
        #("governing_contract", json.string(d.governing_contract)),
        #(
          "formal_verification_method",
          json.string(d.formal_verification_method),
        ),
      ])
    })

  json.object([
    #("status", json.string("ok")),
    #("total_aspects", json.int(list.length(details))),
    #("total_features", json.int(list.length(get_all_features()))),
    #("total_agents_deployed", json.int(get_total_aspect_squad_agents())),
    #("all_features_covered", json.bool(verify_all_features_covered())),
    #("aspect_details", json.array(items, fn(x) { x })),
  ])
  |> json.to_string
}
