//// =============================================================================
//// [UOS-C3I-AGENT-TAXONOMY] C3I SDLC, SRE, Verification & Intelligence Ecology
//// =============================================================================
//// Formal specification of all 256 canonical sovereign agent types created via
//// the FPP pure BEAM substrate across all 4 C3I pillars (SDLC, SRE, Verification,
//// Intelligence) and fractal layers (L0..L7), components, SRE tiers, and evidence.
//// =============================================================================

import cepaf_gleam/fpp/domain.{
  type ComponentKind, type QueueFull, type SignalDef, type StateMachine, Active,
  Assert, Block, Drop, HierarchicalMachine, HierarchicalState, Queued, SignalDef,
  ToState, Transition,
}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}

fn make_signals(names: List(String)) -> List(SignalDef) {
  list.map(names, fn(n) { SignalDef(signal_name: n, signal_type: None) })
}

// =============================================================================
// C3I Subsystem Classification Pillar (4 Symmetrical Pillars of 64 Agents)
// =============================================================================

pub type C3iSystem {
  C3iSdlc
  C3iSre
  C3iVerification
  C3iIntelligence
}

pub fn c3i_system_to_string(sys: C3iSystem) -> String {
  case sys {
    C3iSdlc -> "C3I-SDLC"
    C3iSre -> "C3I-SRE"
    C3iVerification -> "C3I-VERIFICATION"
    C3iIntelligence -> "C3I-INTELLIGENCE"
  }
}

pub fn string_to_c3i_system(s: String) -> Result(C3iSystem, Nil) {
  case s {
    "C3I-SDLC" -> Ok(C3iSdlc)
    "C3I-SRE" -> Ok(C3iSre)
    "C3I-VERIFICATION" -> Ok(C3iVerification)
    "C3I-INTELLIGENCE" -> Ok(C3iIntelligence)
    _ -> Error(Nil)
  }
}

// =============================================================================
// Agent Kind Enumeration (256 Sovereign Agent Kinds)
// =============================================================================

pub type AgentKind {
  SdlcArchitectureSynthesizer
  SdlcHitlGatekeeper
  SdlcConstitutionalSpecifier
  SdlcPolicyRuleCompiler
  SdlcTwoKeyAuthorization
  SdlcGovernanceCharterAuditor
  SdlcLicenseComplianceChecker
  SdlcMonorepoBoundaryEnforcer
  SdlcContractCodeGenerator
  SdlcOpenApiSchemaGenerator
  SdlcGospelOrtacSpecification
  SdlcAstTransformer
  SdlcTypeInferenceBridge
  SdlcLexerParserGenerator
  SdlcBytecodeInstructionEmitter
  SdlcSymbolTableManager
  ParameterDatabase
  SdlcStaticAnalysisAuditor
  SdlcDesignSystemFigmaBridge
  SdlcComponentSchemaSynthesizer
  SdlcPropBindingValidator
  SdlcWidgetPaletteRegistry
  SdlcDataModelNormalizer
  SdlcInterfaceContractBinder
  MissionPhaseHsm
  PayloadScience
  SdlcToolRegistryMcpBridge
  SdlcHierarchicalStateComposer
  SdlcLcaTransitionResolver
  SdlcGuardActionSynthesizer
  SdlcOrthogonalRegionCoordinator
  SdlcSignalDispatchMatrix
  AppupHotReloadCoordinator
  SdlcReleasePackagingOrchestrator
  SdlcSessionMemoryReplay
  SdlcForkJoinParallelBranch
  SdlcFeatureSliceComposer
  SdlcApiEndpointPackager
  SdlcArtifactTarballBundler
  SdlcSemanticVersionManager
  KmSync
  SlmBifInference
  FastPatternFilter
  SdlcGraphWorkflowOrchestrator
  SdlcPromptTemplateInjector
  SdlcStateGraphCycleResolver
  SdlcDenotationalSemanticsMapper
  SdlcTemplateRenderer
  SdlcDocumentationTransclusionSync
  SdlcA2aMultiAgentDelegation
  SdlcNotionLivingOntology
  SdlcSwarmWorkflowScheduler
  SdlcAgentInterchangeProtocol
  SdlcDialogueTurnOrchestrator
  SdlcContextWindowManager
  SdlcCollaborativeTaskRouter
  SdlcAlgebraicAtlasRouter
  SdlcRouteTableHtmlAlgebra
  LivingMetaEvolution
  DynamicAgentBytecodeSynthesizer
  SdlcEvolutionaryLoopGovernor
  SdlcCrossRepositorySynchronizer
  SdlcContinuousDeploymentPipeline
  SdlcArtifactRegistryMirror
  SrePluginPolicyGuardrail
  SreReteFailClosedAdmission
  SreStpaSafetyController
  SreContentSafetySanitizer
  SreEmergencyJidokaInterlock
  SreConstitutionalQuorumWatcher
  SreFailClosedCircuitGovernor
  SreZeroTrustAdmissionFilter
  StorageCustodian
  DeterministicReductionScheduler
  LinearArenaReclaimer
  SreCpuBudgetGovernor
  SreSandboxedToolIsolation
  SreMemoryLeakDetector
  SrePageFaultRateController
  SreGarbageCollectionPacer
  LocklessHamtStorage
  TaggedPointerGuard
  HierarchicalTimerWheel
  SreFreshnessMonitor
  SreOpenTelemetrySpanTracer
  SreDeadMansSwitchWatchdog
  SreHeartbeatLivenessCluster
  SreHealthEntropyAggregator
  CrashWalReplay
  SreSaPlanTaskLeaser
  SreDatabaseActorWalSerializer
  SreMailboxBackpressureController
  SreActorDeadlockResolver
  SreMessageQueueDrainer
  SrePriorityQueueFairScheduler
  SreTransactionSagaCompensator
  SreSentinel
  CyberneticImmune
  SreLyapunovTrendDetector
  SreChaosFaultInjector
  SreRunnerLifecycleHookSupervisor
  SreTimeTravelStateRollback
  SreTokenQuotaRateLimiter
  SreCephOsdDiskSafetyGuard
  SreForecastPredictivePreflight
  SreEndocrineHormoneBalancer
  SreAdaptiveRateController
  SreWindowedTrendAnalyzer
  SreDynamicCapacityPlanner
  SreMetabolicGovernor
  SreDegradedModeOrchestrator
  SreLoadSheddingGovernor
  SwarmMesh
  EpidemicGossip
  SreSessionShardRebalancer
  SrePrajnaCircuitBreaker
  SreMeshPartitionHealer
  SreCascadingFailureShield
  SreGossipMembershipCluster
  SreConsensusConsulElector
  GroundGateway
  SreCrdtVersionVectorSync
  SreCastIncidentInvestigator
  SrePostMortemRcaSynthesizer
  SreFederationGatewayProxy
  SreTelemetryBackplanePublisher
  SreDisasterRecoverySequencer
  SreAuditTrailLedgerSigner
  ConstitutionalGuardian
  FormalOracle
  HardwareDriveInterlock
  RochaSemioticCutGuard
  VerificationChecklistAuditor
  VerificationMathGateCertifier
  VerificationTcmCoordinateProtector
  VerificationZeroMudaPurityEnforcer
  DeterministicFlightController
  SubstrateReactor
  VerificationPinnedOtpDifferential
  VerificationGospelOrtacRuntimeMonitor
  VerificationSmtNegationAuditor
  VerificationZ3UnsatValidator
  VerificationNegativeControlVerifier
  VerificationTypestateInvariantChecker
  AvionicsTelemetry
  CockpitTelemetry
  VerificationBrowserMatrixTester
  VerificationMutationAdequacyKiller
  VerificationTddLawEnforcer
  VerificationRedGreenRevertJudge
  VerificationFlaccidLawDetector
  VerificationFixtureTotalityAuditor
  McdcAvionicsTap
  DifferentialBisimulation
  VerificationNineModalityExecutor
  VerificationToolSchemaConformance
  VerificationBddScenarioRunner
  VerificationStateTransitionAsserter
  VerificationTraceEquivalenceJudge
  VerificationMcdcBranchCoverageAuditor
  VerificationPlaywrightControlAuditor
  VerificationMultiTurnDialogueVerifier
  VerificationPropertyGeneratorFuzzer
  VerificationGenerativeShrinkEngine
  VerificationBoundaryValueTester
  VerificationSeededRandomReplayer
  VerificationCorpusModuleExecutor
  VerificationAstMutantSynthesizer
  VerificationAdkEvalBenchmark
  VerificationTrajectoryReplayCertifier
  VerificationHallucinationScorer
  VerificationEntropyCalculator
  VerificationDivergenceMetricScorer
  VerificationFactualGroundingAuditor
  VerificationReasoningStepValidator
  VerificationContextRetentionVerifier
  VerificationSimulationEnvironment
  VerificationActorBisimulationTester
  VerificationConcurrencyRaceDetector
  VerificationModelCheckerBridge
  VerificationLinearizabilityOracle
  VerificationDistributedPartitionTester
  VerificationMessageLossSimulator
  VerificationClockDriftChaosTester
  VerificationSheafGluingHarmonizer
  VerificationLeanFormalProofOracle
  VerificationQuintParityFrontierOracle
  VerificationMasterChecklistGatekeeper
  VerificationParityRatchetEnforcer
  VerificationBaselineReleaseGatekeeper
  VerificationFormalEvidenceArchiver
  VerificationSovereignConsensusRatifier
  IntelligenceRochaCutValidator
  IntelligenceCodeBiologyBoundaryGuard
  IntelligenceSymbolMatterDecoupler
  IntelligenceSemioticClosureAuditor
  IntelligenceSemanticAnchorProtector
  IntelligenceBiomorphicMorphogenRouter
  IntelligenceCyberneticFeedbackHarmonizer
  IntelligenceMetabolicHomeostasisTracker
  IntelligenceSheafCohomologyEngine
  IntelligenceLocalSectionExtractor
  IntelligencePresheafFunctorMapper
  IntelligenceGluingMorphismSynthesizer
  IntelligenceRestrictionMapValidator
  IntelligenceCechComplexBuilder
  IntelligenceSpectralSequenceAnalyzer
  IntelligenceCategoryTheoryBridge
  VerificationZkKmKnowledgeCurrency
  IntelligenceZettelkastenLibrarian
  IntelligencePermanentAdrCustodian
  IntelligenceMapOfContentCurator
  IntelligenceEpisodicMemoryIndexer
  IntelligenceBidirectionalLinkResolver
  IntelligenceFractalTagTaxonomist
  IntelligenceKnowledgeDecayDetector
  SdlcOntologyInfranodusSynthesizer
  VerificationInfranodusCentralityAuditor
  SdlcSemanticVectorEmbedding
  IntelligenceRdfOwlOntologyBuilder
  IntelligenceKnowledgeGraphHarmonizer
  IntelligenceConceptLatticeMiner
  IntelligenceSemanticTriplestoreCustodian
  IntelligenceTaxonomyGraphTraverser
  CognitiveOodaIntent
  IntelligenceOodaLoopOrchestrator
  IntelligenceObserveSensorAggregator
  IntelligenceOrientContextSynthesizer
  IntelligenceDecideStrategySelector
  IntelligenceActuatorTaskDispatcher
  IntelligenceReasoningGraphExpander
  IntelligenceHypothesisTestingAgent
  IntelligenceMaxDaemonSupervisor
  IntelligenceMojoKernelOptimizer
  IntelligenceJsonRpcStdioPipeBridge
  IntelligenceProcessIsolationEnforcer
  IntelligenceBatchInferenceDispatcher
  IntelligenceTokenStreamingPacer
  IntelligenceModelWeightQuarantine
  IntelligenceSlmLocalCacheCustodian
  IntelligenceSwarmConsensusDirector
  IntelligenceRoleSpecializationMatcher
  IntelligenceTaskDecompositionPlanner
  IntelligenceAgentPeerMessenger
  IntelligenceSwarmConflictMediator
  IntelligenceCollectiveMemorySync
  IntelligenceAutonomousNegotiationBroker
  IntelligenceFederatedPromptOrchestrator
  IntelligenceMasterEncyclopediaIndexer
  IntelligenceCorpusTransclusionEngine
  IntelligenceLivingCatalogPublisher
  IntelligenceCrossPlatformKnowledgeMirror
  IntelligenceSovereignReviewSynthesizer
  IntelligenceKnowledgeArchivalVault
  IntelligenceEpistemicCertaintyEvaluator
  IntelligenceUnifiedSiteNavigationCurator
}

pub fn agent_kind_to_string(kind: AgentKind) -> String {
  case kind {
    SdlcArchitectureSynthesizer -> "SdlcArchitectureSynthesizer"
    SdlcHitlGatekeeper -> "SdlcHitlGatekeeper"
    SdlcConstitutionalSpecifier -> "SdlcConstitutionalSpecifier"
    SdlcPolicyRuleCompiler -> "SdlcPolicyRuleCompiler"
    SdlcTwoKeyAuthorization -> "SdlcTwoKeyAuthorization"
    SdlcGovernanceCharterAuditor -> "SdlcGovernanceCharterAuditor"
    SdlcLicenseComplianceChecker -> "SdlcLicenseComplianceChecker"
    SdlcMonorepoBoundaryEnforcer -> "SdlcMonorepoBoundaryEnforcer"
    SdlcContractCodeGenerator -> "SdlcContractCodeGenerator"
    SdlcOpenApiSchemaGenerator -> "SdlcOpenApiSchemaGenerator"
    SdlcGospelOrtacSpecification -> "SdlcGospelOrtacSpecification"
    SdlcAstTransformer -> "SdlcAstTransformer"
    SdlcTypeInferenceBridge -> "SdlcTypeInferenceBridge"
    SdlcLexerParserGenerator -> "SdlcLexerParserGenerator"
    SdlcBytecodeInstructionEmitter -> "SdlcBytecodeInstructionEmitter"
    SdlcSymbolTableManager -> "SdlcSymbolTableManager"
    ParameterDatabase -> "ParameterDatabase"
    SdlcStaticAnalysisAuditor -> "SdlcStaticAnalysisAuditor"
    SdlcDesignSystemFigmaBridge -> "SdlcDesignSystemFigmaBridge"
    SdlcComponentSchemaSynthesizer -> "SdlcComponentSchemaSynthesizer"
    SdlcPropBindingValidator -> "SdlcPropBindingValidator"
    SdlcWidgetPaletteRegistry -> "SdlcWidgetPaletteRegistry"
    SdlcDataModelNormalizer -> "SdlcDataModelNormalizer"
    SdlcInterfaceContractBinder -> "SdlcInterfaceContractBinder"
    MissionPhaseHsm -> "MissionPhaseHsm"
    PayloadScience -> "PayloadScience"
    SdlcToolRegistryMcpBridge -> "SdlcToolRegistryMcpBridge"
    SdlcHierarchicalStateComposer -> "SdlcHierarchicalStateComposer"
    SdlcLcaTransitionResolver -> "SdlcLcaTransitionResolver"
    SdlcGuardActionSynthesizer -> "SdlcGuardActionSynthesizer"
    SdlcOrthogonalRegionCoordinator -> "SdlcOrthogonalRegionCoordinator"
    SdlcSignalDispatchMatrix -> "SdlcSignalDispatchMatrix"
    AppupHotReloadCoordinator -> "AppupHotReloadCoordinator"
    SdlcReleasePackagingOrchestrator -> "SdlcReleasePackagingOrchestrator"
    SdlcSessionMemoryReplay -> "SdlcSessionMemoryReplay"
    SdlcForkJoinParallelBranch -> "SdlcForkJoinParallelBranch"
    SdlcFeatureSliceComposer -> "SdlcFeatureSliceComposer"
    SdlcApiEndpointPackager -> "SdlcApiEndpointPackager"
    SdlcArtifactTarballBundler -> "SdlcArtifactTarballBundler"
    SdlcSemanticVersionManager -> "SdlcSemanticVersionManager"
    KmSync -> "KmSync"
    SlmBifInference -> "SlmBifInference"
    FastPatternFilter -> "FastPatternFilter"
    SdlcGraphWorkflowOrchestrator -> "SdlcGraphWorkflowOrchestrator"
    SdlcPromptTemplateInjector -> "SdlcPromptTemplateInjector"
    SdlcStateGraphCycleResolver -> "SdlcStateGraphCycleResolver"
    SdlcDenotationalSemanticsMapper -> "SdlcDenotationalSemanticsMapper"
    SdlcTemplateRenderer -> "SdlcTemplateRenderer"
    SdlcDocumentationTransclusionSync -> "SdlcDocumentationTransclusionSync"
    SdlcA2aMultiAgentDelegation -> "SdlcA2aMultiAgentDelegation"
    SdlcNotionLivingOntology -> "SdlcNotionLivingOntology"
    SdlcSwarmWorkflowScheduler -> "SdlcSwarmWorkflowScheduler"
    SdlcAgentInterchangeProtocol -> "SdlcAgentInterchangeProtocol"
    SdlcDialogueTurnOrchestrator -> "SdlcDialogueTurnOrchestrator"
    SdlcContextWindowManager -> "SdlcContextWindowManager"
    SdlcCollaborativeTaskRouter -> "SdlcCollaborativeTaskRouter"
    SdlcAlgebraicAtlasRouter -> "SdlcAlgebraicAtlasRouter"
    SdlcRouteTableHtmlAlgebra -> "SdlcRouteTableHtmlAlgebra"
    LivingMetaEvolution -> "LivingMetaEvolution"
    DynamicAgentBytecodeSynthesizer -> "DynamicAgentBytecodeSynthesizer"
    SdlcEvolutionaryLoopGovernor -> "SdlcEvolutionaryLoopGovernor"
    SdlcCrossRepositorySynchronizer -> "SdlcCrossRepositorySynchronizer"
    SdlcContinuousDeploymentPipeline -> "SdlcContinuousDeploymentPipeline"
    SdlcArtifactRegistryMirror -> "SdlcArtifactRegistryMirror"
    SrePluginPolicyGuardrail -> "SrePluginPolicyGuardrail"
    SreReteFailClosedAdmission -> "SreReteFailClosedAdmission"
    SreStpaSafetyController -> "SreStpaSafetyController"
    SreContentSafetySanitizer -> "SreContentSafetySanitizer"
    SreEmergencyJidokaInterlock -> "SreEmergencyJidokaInterlock"
    SreConstitutionalQuorumWatcher -> "SreConstitutionalQuorumWatcher"
    SreFailClosedCircuitGovernor -> "SreFailClosedCircuitGovernor"
    SreZeroTrustAdmissionFilter -> "SreZeroTrustAdmissionFilter"
    StorageCustodian -> "StorageCustodian"
    DeterministicReductionScheduler -> "DeterministicReductionScheduler"
    LinearArenaReclaimer -> "LinearArenaReclaimer"
    SreCpuBudgetGovernor -> "SreCpuBudgetGovernor"
    SreSandboxedToolIsolation -> "SreSandboxedToolIsolation"
    SreMemoryLeakDetector -> "SreMemoryLeakDetector"
    SrePageFaultRateController -> "SrePageFaultRateController"
    SreGarbageCollectionPacer -> "SreGarbageCollectionPacer"
    LocklessHamtStorage -> "LocklessHamtStorage"
    TaggedPointerGuard -> "TaggedPointerGuard"
    HierarchicalTimerWheel -> "HierarchicalTimerWheel"
    SreFreshnessMonitor -> "SreFreshnessMonitor"
    SreOpenTelemetrySpanTracer -> "SreOpenTelemetrySpanTracer"
    SreDeadMansSwitchWatchdog -> "SreDeadMansSwitchWatchdog"
    SreHeartbeatLivenessCluster -> "SreHeartbeatLivenessCluster"
    SreHealthEntropyAggregator -> "SreHealthEntropyAggregator"
    CrashWalReplay -> "CrashWalReplay"
    SreSaPlanTaskLeaser -> "SreSaPlanTaskLeaser"
    SreDatabaseActorWalSerializer -> "SreDatabaseActorWalSerializer"
    SreMailboxBackpressureController -> "SreMailboxBackpressureController"
    SreActorDeadlockResolver -> "SreActorDeadlockResolver"
    SreMessageQueueDrainer -> "SreMessageQueueDrainer"
    SrePriorityQueueFairScheduler -> "SrePriorityQueueFairScheduler"
    SreTransactionSagaCompensator -> "SreTransactionSagaCompensator"
    SreSentinel -> "SreSentinel"
    CyberneticImmune -> "CyberneticImmune"
    SreLyapunovTrendDetector -> "SreLyapunovTrendDetector"
    SreChaosFaultInjector -> "SreChaosFaultInjector"
    SreRunnerLifecycleHookSupervisor -> "SreRunnerLifecycleHookSupervisor"
    SreTimeTravelStateRollback -> "SreTimeTravelStateRollback"
    SreTokenQuotaRateLimiter -> "SreTokenQuotaRateLimiter"
    SreCephOsdDiskSafetyGuard -> "SreCephOsdDiskSafetyGuard"
    SreForecastPredictivePreflight -> "SreForecastPredictivePreflight"
    SreEndocrineHormoneBalancer -> "SreEndocrineHormoneBalancer"
    SreAdaptiveRateController -> "SreAdaptiveRateController"
    SreWindowedTrendAnalyzer -> "SreWindowedTrendAnalyzer"
    SreDynamicCapacityPlanner -> "SreDynamicCapacityPlanner"
    SreMetabolicGovernor -> "SreMetabolicGovernor"
    SreDegradedModeOrchestrator -> "SreDegradedModeOrchestrator"
    SreLoadSheddingGovernor -> "SreLoadSheddingGovernor"
    SwarmMesh -> "SwarmMesh"
    EpidemicGossip -> "EpidemicGossip"
    SreSessionShardRebalancer -> "SreSessionShardRebalancer"
    SrePrajnaCircuitBreaker -> "SrePrajnaCircuitBreaker"
    SreMeshPartitionHealer -> "SreMeshPartitionHealer"
    SreCascadingFailureShield -> "SreCascadingFailureShield"
    SreGossipMembershipCluster -> "SreGossipMembershipCluster"
    SreConsensusConsulElector -> "SreConsensusConsulElector"
    GroundGateway -> "GroundGateway"
    SreCrdtVersionVectorSync -> "SreCrdtVersionVectorSync"
    SreCastIncidentInvestigator -> "SreCastIncidentInvestigator"
    SrePostMortemRcaSynthesizer -> "SrePostMortemRcaSynthesizer"
    SreFederationGatewayProxy -> "SreFederationGatewayProxy"
    SreTelemetryBackplanePublisher -> "SreTelemetryBackplanePublisher"
    SreDisasterRecoverySequencer -> "SreDisasterRecoverySequencer"
    SreAuditTrailLedgerSigner -> "SreAuditTrailLedgerSigner"
    ConstitutionalGuardian -> "ConstitutionalGuardian"
    FormalOracle -> "FormalOracle"
    HardwareDriveInterlock -> "HardwareDriveInterlock"
    RochaSemioticCutGuard -> "RochaSemioticCutGuard"
    VerificationChecklistAuditor -> "VerificationChecklistAuditor"
    VerificationMathGateCertifier -> "VerificationMathGateCertifier"
    VerificationTcmCoordinateProtector -> "VerificationTcmCoordinateProtector"
    VerificationZeroMudaPurityEnforcer -> "VerificationZeroMudaPurityEnforcer"
    DeterministicFlightController -> "DeterministicFlightController"
    SubstrateReactor -> "SubstrateReactor"
    VerificationPinnedOtpDifferential -> "VerificationPinnedOtpDifferential"
    VerificationGospelOrtacRuntimeMonitor ->
      "VerificationGospelOrtacRuntimeMonitor"
    VerificationSmtNegationAuditor -> "VerificationSmtNegationAuditor"
    VerificationZ3UnsatValidator -> "VerificationZ3UnsatValidator"
    VerificationNegativeControlVerifier -> "VerificationNegativeControlVerifier"
    VerificationTypestateInvariantChecker ->
      "VerificationTypestateInvariantChecker"
    AvionicsTelemetry -> "AvionicsTelemetry"
    CockpitTelemetry -> "CockpitTelemetry"
    VerificationBrowserMatrixTester -> "VerificationBrowserMatrixTester"
    VerificationMutationAdequacyKiller -> "VerificationMutationAdequacyKiller"
    VerificationTddLawEnforcer -> "VerificationTddLawEnforcer"
    VerificationRedGreenRevertJudge -> "VerificationRedGreenRevertJudge"
    VerificationFlaccidLawDetector -> "VerificationFlaccidLawDetector"
    VerificationFixtureTotalityAuditor -> "VerificationFixtureTotalityAuditor"
    McdcAvionicsTap -> "McdcAvionicsTap"
    DifferentialBisimulation -> "DifferentialBisimulation"
    VerificationNineModalityExecutor -> "VerificationNineModalityExecutor"
    VerificationToolSchemaConformance -> "VerificationToolSchemaConformance"
    VerificationBddScenarioRunner -> "VerificationBddScenarioRunner"
    VerificationStateTransitionAsserter -> "VerificationStateTransitionAsserter"
    VerificationTraceEquivalenceJudge -> "VerificationTraceEquivalenceJudge"
    VerificationMcdcBranchCoverageAuditor ->
      "VerificationMcdcBranchCoverageAuditor"
    VerificationPlaywrightControlAuditor ->
      "VerificationPlaywrightControlAuditor"
    VerificationMultiTurnDialogueVerifier ->
      "VerificationMultiTurnDialogueVerifier"
    VerificationPropertyGeneratorFuzzer -> "VerificationPropertyGeneratorFuzzer"
    VerificationGenerativeShrinkEngine -> "VerificationGenerativeShrinkEngine"
    VerificationBoundaryValueTester -> "VerificationBoundaryValueTester"
    VerificationSeededRandomReplayer -> "VerificationSeededRandomReplayer"
    VerificationCorpusModuleExecutor -> "VerificationCorpusModuleExecutor"
    VerificationAstMutantSynthesizer -> "VerificationAstMutantSynthesizer"
    VerificationAdkEvalBenchmark -> "VerificationAdkEvalBenchmark"
    VerificationTrajectoryReplayCertifier ->
      "VerificationTrajectoryReplayCertifier"
    VerificationHallucinationScorer -> "VerificationHallucinationScorer"
    VerificationEntropyCalculator -> "VerificationEntropyCalculator"
    VerificationDivergenceMetricScorer -> "VerificationDivergenceMetricScorer"
    VerificationFactualGroundingAuditor -> "VerificationFactualGroundingAuditor"
    VerificationReasoningStepValidator -> "VerificationReasoningStepValidator"
    VerificationContextRetentionVerifier ->
      "VerificationContextRetentionVerifier"
    VerificationSimulationEnvironment -> "VerificationSimulationEnvironment"
    VerificationActorBisimulationTester -> "VerificationActorBisimulationTester"
    VerificationConcurrencyRaceDetector -> "VerificationConcurrencyRaceDetector"
    VerificationModelCheckerBridge -> "VerificationModelCheckerBridge"
    VerificationLinearizabilityOracle -> "VerificationLinearizabilityOracle"
    VerificationDistributedPartitionTester ->
      "VerificationDistributedPartitionTester"
    VerificationMessageLossSimulator -> "VerificationMessageLossSimulator"
    VerificationClockDriftChaosTester -> "VerificationClockDriftChaosTester"
    VerificationSheafGluingHarmonizer -> "VerificationSheafGluingHarmonizer"
    VerificationLeanFormalProofOracle -> "VerificationLeanFormalProofOracle"
    VerificationQuintParityFrontierOracle ->
      "VerificationQuintParityFrontierOracle"
    VerificationMasterChecklistGatekeeper ->
      "VerificationMasterChecklistGatekeeper"
    VerificationParityRatchetEnforcer -> "VerificationParityRatchetEnforcer"
    VerificationBaselineReleaseGatekeeper ->
      "VerificationBaselineReleaseGatekeeper"
    VerificationFormalEvidenceArchiver -> "VerificationFormalEvidenceArchiver"
    VerificationSovereignConsensusRatifier ->
      "VerificationSovereignConsensusRatifier"
    IntelligenceRochaCutValidator -> "IntelligenceRochaCutValidator"
    IntelligenceCodeBiologyBoundaryGuard ->
      "IntelligenceCodeBiologyBoundaryGuard"
    IntelligenceSymbolMatterDecoupler -> "IntelligenceSymbolMatterDecoupler"
    IntelligenceSemioticClosureAuditor -> "IntelligenceSemioticClosureAuditor"
    IntelligenceSemanticAnchorProtector -> "IntelligenceSemanticAnchorProtector"
    IntelligenceBiomorphicMorphogenRouter ->
      "IntelligenceBiomorphicMorphogenRouter"
    IntelligenceCyberneticFeedbackHarmonizer ->
      "IntelligenceCyberneticFeedbackHarmonizer"
    IntelligenceMetabolicHomeostasisTracker ->
      "IntelligenceMetabolicHomeostasisTracker"
    IntelligenceSheafCohomologyEngine -> "IntelligenceSheafCohomologyEngine"
    IntelligenceLocalSectionExtractor -> "IntelligenceLocalSectionExtractor"
    IntelligencePresheafFunctorMapper -> "IntelligencePresheafFunctorMapper"
    IntelligenceGluingMorphismSynthesizer ->
      "IntelligenceGluingMorphismSynthesizer"
    IntelligenceRestrictionMapValidator -> "IntelligenceRestrictionMapValidator"
    IntelligenceCechComplexBuilder -> "IntelligenceCechComplexBuilder"
    IntelligenceSpectralSequenceAnalyzer ->
      "IntelligenceSpectralSequenceAnalyzer"
    IntelligenceCategoryTheoryBridge -> "IntelligenceCategoryTheoryBridge"
    VerificationZkKmKnowledgeCurrency -> "VerificationZkKmKnowledgeCurrency"
    IntelligenceZettelkastenLibrarian -> "IntelligenceZettelkastenLibrarian"
    IntelligencePermanentAdrCustodian -> "IntelligencePermanentAdrCustodian"
    IntelligenceMapOfContentCurator -> "IntelligenceMapOfContentCurator"
    IntelligenceEpisodicMemoryIndexer -> "IntelligenceEpisodicMemoryIndexer"
    IntelligenceBidirectionalLinkResolver ->
      "IntelligenceBidirectionalLinkResolver"
    IntelligenceFractalTagTaxonomist -> "IntelligenceFractalTagTaxonomist"
    IntelligenceKnowledgeDecayDetector -> "IntelligenceKnowledgeDecayDetector"
    SdlcOntologyInfranodusSynthesizer -> "SdlcOntologyInfranodusSynthesizer"
    VerificationInfranodusCentralityAuditor ->
      "VerificationInfranodusCentralityAuditor"
    SdlcSemanticVectorEmbedding -> "SdlcSemanticVectorEmbedding"
    IntelligenceRdfOwlOntologyBuilder -> "IntelligenceRdfOwlOntologyBuilder"
    IntelligenceKnowledgeGraphHarmonizer ->
      "IntelligenceKnowledgeGraphHarmonizer"
    IntelligenceConceptLatticeMiner -> "IntelligenceConceptLatticeMiner"
    IntelligenceSemanticTriplestoreCustodian ->
      "IntelligenceSemanticTriplestoreCustodian"
    IntelligenceTaxonomyGraphTraverser -> "IntelligenceTaxonomyGraphTraverser"
    CognitiveOodaIntent -> "CognitiveOodaIntent"
    IntelligenceOodaLoopOrchestrator -> "IntelligenceOodaLoopOrchestrator"
    IntelligenceObserveSensorAggregator -> "IntelligenceObserveSensorAggregator"
    IntelligenceOrientContextSynthesizer ->
      "IntelligenceOrientContextSynthesizer"
    IntelligenceDecideStrategySelector -> "IntelligenceDecideStrategySelector"
    IntelligenceActuatorTaskDispatcher -> "IntelligenceActuatorTaskDispatcher"
    IntelligenceReasoningGraphExpander -> "IntelligenceReasoningGraphExpander"
    IntelligenceHypothesisTestingAgent -> "IntelligenceHypothesisTestingAgent"
    IntelligenceMaxDaemonSupervisor -> "IntelligenceMaxDaemonSupervisor"
    IntelligenceMojoKernelOptimizer -> "IntelligenceMojoKernelOptimizer"
    IntelligenceJsonRpcStdioPipeBridge -> "IntelligenceJsonRpcStdioPipeBridge"
    IntelligenceProcessIsolationEnforcer ->
      "IntelligenceProcessIsolationEnforcer"
    IntelligenceBatchInferenceDispatcher ->
      "IntelligenceBatchInferenceDispatcher"
    IntelligenceTokenStreamingPacer -> "IntelligenceTokenStreamingPacer"
    IntelligenceModelWeightQuarantine -> "IntelligenceModelWeightQuarantine"
    IntelligenceSlmLocalCacheCustodian -> "IntelligenceSlmLocalCacheCustodian"
    IntelligenceSwarmConsensusDirector -> "IntelligenceSwarmConsensusDirector"
    IntelligenceRoleSpecializationMatcher ->
      "IntelligenceRoleSpecializationMatcher"
    IntelligenceTaskDecompositionPlanner ->
      "IntelligenceTaskDecompositionPlanner"
    IntelligenceAgentPeerMessenger -> "IntelligenceAgentPeerMessenger"
    IntelligenceSwarmConflictMediator -> "IntelligenceSwarmConflictMediator"
    IntelligenceCollectiveMemorySync -> "IntelligenceCollectiveMemorySync"
    IntelligenceAutonomousNegotiationBroker ->
      "IntelligenceAutonomousNegotiationBroker"
    IntelligenceFederatedPromptOrchestrator ->
      "IntelligenceFederatedPromptOrchestrator"
    IntelligenceMasterEncyclopediaIndexer ->
      "IntelligenceMasterEncyclopediaIndexer"
    IntelligenceCorpusTransclusionEngine ->
      "IntelligenceCorpusTransclusionEngine"
    IntelligenceLivingCatalogPublisher -> "IntelligenceLivingCatalogPublisher"
    IntelligenceCrossPlatformKnowledgeMirror ->
      "IntelligenceCrossPlatformKnowledgeMirror"
    IntelligenceSovereignReviewSynthesizer ->
      "IntelligenceSovereignReviewSynthesizer"
    IntelligenceKnowledgeArchivalVault -> "IntelligenceKnowledgeArchivalVault"
    IntelligenceEpistemicCertaintyEvaluator ->
      "IntelligenceEpistemicCertaintyEvaluator"
    IntelligenceUnifiedSiteNavigationCurator ->
      "IntelligenceUnifiedSiteNavigationCurator"
  }
}

pub fn string_to_agent_kind(s: String) -> Result(AgentKind, Nil) {
  case s {
    "SdlcArchitectureSynthesizer" -> Ok(SdlcArchitectureSynthesizer)
    "SdlcHitlGatekeeper" -> Ok(SdlcHitlGatekeeper)
    "SdlcConstitutionalSpecifier" -> Ok(SdlcConstitutionalSpecifier)
    "SdlcPolicyRuleCompiler" -> Ok(SdlcPolicyRuleCompiler)
    "SdlcTwoKeyAuthorization" -> Ok(SdlcTwoKeyAuthorization)
    "SdlcGovernanceCharterAuditor" -> Ok(SdlcGovernanceCharterAuditor)
    "SdlcLicenseComplianceChecker" -> Ok(SdlcLicenseComplianceChecker)
    "SdlcMonorepoBoundaryEnforcer" -> Ok(SdlcMonorepoBoundaryEnforcer)
    "SdlcContractCodeGenerator" -> Ok(SdlcContractCodeGenerator)
    "SdlcOpenApiSchemaGenerator" -> Ok(SdlcOpenApiSchemaGenerator)
    "SdlcGospelOrtacSpecification" -> Ok(SdlcGospelOrtacSpecification)
    "SdlcAstTransformer" -> Ok(SdlcAstTransformer)
    "SdlcTypeInferenceBridge" -> Ok(SdlcTypeInferenceBridge)
    "SdlcLexerParserGenerator" -> Ok(SdlcLexerParserGenerator)
    "SdlcBytecodeInstructionEmitter" -> Ok(SdlcBytecodeInstructionEmitter)
    "SdlcSymbolTableManager" -> Ok(SdlcSymbolTableManager)
    "ParameterDatabase" -> Ok(ParameterDatabase)
    "SdlcStaticAnalysisAuditor" -> Ok(SdlcStaticAnalysisAuditor)
    "SdlcDesignSystemFigmaBridge" -> Ok(SdlcDesignSystemFigmaBridge)
    "SdlcComponentSchemaSynthesizer" -> Ok(SdlcComponentSchemaSynthesizer)
    "SdlcPropBindingValidator" -> Ok(SdlcPropBindingValidator)
    "SdlcWidgetPaletteRegistry" -> Ok(SdlcWidgetPaletteRegistry)
    "SdlcDataModelNormalizer" -> Ok(SdlcDataModelNormalizer)
    "SdlcInterfaceContractBinder" -> Ok(SdlcInterfaceContractBinder)
    "MissionPhaseHsm" -> Ok(MissionPhaseHsm)
    "PayloadScience" -> Ok(PayloadScience)
    "SdlcToolRegistryMcpBridge" -> Ok(SdlcToolRegistryMcpBridge)
    "SdlcHierarchicalStateComposer" -> Ok(SdlcHierarchicalStateComposer)
    "SdlcLcaTransitionResolver" -> Ok(SdlcLcaTransitionResolver)
    "SdlcGuardActionSynthesizer" -> Ok(SdlcGuardActionSynthesizer)
    "SdlcOrthogonalRegionCoordinator" -> Ok(SdlcOrthogonalRegionCoordinator)
    "SdlcSignalDispatchMatrix" -> Ok(SdlcSignalDispatchMatrix)
    "AppupHotReloadCoordinator" -> Ok(AppupHotReloadCoordinator)
    "SdlcReleasePackagingOrchestrator" -> Ok(SdlcReleasePackagingOrchestrator)
    "SdlcSessionMemoryReplay" -> Ok(SdlcSessionMemoryReplay)
    "SdlcForkJoinParallelBranch" -> Ok(SdlcForkJoinParallelBranch)
    "SdlcFeatureSliceComposer" -> Ok(SdlcFeatureSliceComposer)
    "SdlcApiEndpointPackager" -> Ok(SdlcApiEndpointPackager)
    "SdlcArtifactTarballBundler" -> Ok(SdlcArtifactTarballBundler)
    "SdlcSemanticVersionManager" -> Ok(SdlcSemanticVersionManager)
    "KmSync" -> Ok(KmSync)
    "SlmBifInference" -> Ok(SlmBifInference)
    "FastPatternFilter" -> Ok(FastPatternFilter)
    "SdlcGraphWorkflowOrchestrator" -> Ok(SdlcGraphWorkflowOrchestrator)
    "SdlcPromptTemplateInjector" -> Ok(SdlcPromptTemplateInjector)
    "SdlcStateGraphCycleResolver" -> Ok(SdlcStateGraphCycleResolver)
    "SdlcDenotationalSemanticsMapper" -> Ok(SdlcDenotationalSemanticsMapper)
    "SdlcTemplateRenderer" -> Ok(SdlcTemplateRenderer)
    "SdlcDocumentationTransclusionSync" -> Ok(SdlcDocumentationTransclusionSync)
    "SdlcA2aMultiAgentDelegation" -> Ok(SdlcA2aMultiAgentDelegation)
    "SdlcNotionLivingOntology" -> Ok(SdlcNotionLivingOntology)
    "SdlcSwarmWorkflowScheduler" -> Ok(SdlcSwarmWorkflowScheduler)
    "SdlcAgentInterchangeProtocol" -> Ok(SdlcAgentInterchangeProtocol)
    "SdlcDialogueTurnOrchestrator" -> Ok(SdlcDialogueTurnOrchestrator)
    "SdlcContextWindowManager" -> Ok(SdlcContextWindowManager)
    "SdlcCollaborativeTaskRouter" -> Ok(SdlcCollaborativeTaskRouter)
    "SdlcAlgebraicAtlasRouter" -> Ok(SdlcAlgebraicAtlasRouter)
    "SdlcRouteTableHtmlAlgebra" -> Ok(SdlcRouteTableHtmlAlgebra)
    "LivingMetaEvolution" -> Ok(LivingMetaEvolution)
    "DynamicAgentBytecodeSynthesizer" -> Ok(DynamicAgentBytecodeSynthesizer)
    "SdlcEvolutionaryLoopGovernor" -> Ok(SdlcEvolutionaryLoopGovernor)
    "SdlcCrossRepositorySynchronizer" -> Ok(SdlcCrossRepositorySynchronizer)
    "SdlcContinuousDeploymentPipeline" -> Ok(SdlcContinuousDeploymentPipeline)
    "SdlcArtifactRegistryMirror" -> Ok(SdlcArtifactRegistryMirror)
    "SrePluginPolicyGuardrail" -> Ok(SrePluginPolicyGuardrail)
    "SreReteFailClosedAdmission" -> Ok(SreReteFailClosedAdmission)
    "SreStpaSafetyController" -> Ok(SreStpaSafetyController)
    "SreContentSafetySanitizer" -> Ok(SreContentSafetySanitizer)
    "SreEmergencyJidokaInterlock" -> Ok(SreEmergencyJidokaInterlock)
    "SreConstitutionalQuorumWatcher" -> Ok(SreConstitutionalQuorumWatcher)
    "SreFailClosedCircuitGovernor" -> Ok(SreFailClosedCircuitGovernor)
    "SreZeroTrustAdmissionFilter" -> Ok(SreZeroTrustAdmissionFilter)
    "StorageCustodian" -> Ok(StorageCustodian)
    "DeterministicReductionScheduler" -> Ok(DeterministicReductionScheduler)
    "LinearArenaReclaimer" -> Ok(LinearArenaReclaimer)
    "SreCpuBudgetGovernor" -> Ok(SreCpuBudgetGovernor)
    "SreSandboxedToolIsolation" -> Ok(SreSandboxedToolIsolation)
    "SreMemoryLeakDetector" -> Ok(SreMemoryLeakDetector)
    "SrePageFaultRateController" -> Ok(SrePageFaultRateController)
    "SreGarbageCollectionPacer" -> Ok(SreGarbageCollectionPacer)
    "LocklessHamtStorage" -> Ok(LocklessHamtStorage)
    "TaggedPointerGuard" -> Ok(TaggedPointerGuard)
    "HierarchicalTimerWheel" -> Ok(HierarchicalTimerWheel)
    "SreFreshnessMonitor" -> Ok(SreFreshnessMonitor)
    "SreOpenTelemetrySpanTracer" -> Ok(SreOpenTelemetrySpanTracer)
    "SreDeadMansSwitchWatchdog" -> Ok(SreDeadMansSwitchWatchdog)
    "SreHeartbeatLivenessCluster" -> Ok(SreHeartbeatLivenessCluster)
    "SreHealthEntropyAggregator" -> Ok(SreHealthEntropyAggregator)
    "CrashWalReplay" -> Ok(CrashWalReplay)
    "SreSaPlanTaskLeaser" -> Ok(SreSaPlanTaskLeaser)
    "SreDatabaseActorWalSerializer" -> Ok(SreDatabaseActorWalSerializer)
    "SreMailboxBackpressureController" -> Ok(SreMailboxBackpressureController)
    "SreActorDeadlockResolver" -> Ok(SreActorDeadlockResolver)
    "SreMessageQueueDrainer" -> Ok(SreMessageQueueDrainer)
    "SrePriorityQueueFairScheduler" -> Ok(SrePriorityQueueFairScheduler)
    "SreTransactionSagaCompensator" -> Ok(SreTransactionSagaCompensator)
    "SreSentinel" -> Ok(SreSentinel)
    "CyberneticImmune" -> Ok(CyberneticImmune)
    "SreLyapunovTrendDetector" -> Ok(SreLyapunovTrendDetector)
    "SreChaosFaultInjector" -> Ok(SreChaosFaultInjector)
    "SreRunnerLifecycleHookSupervisor" -> Ok(SreRunnerLifecycleHookSupervisor)
    "SreTimeTravelStateRollback" -> Ok(SreTimeTravelStateRollback)
    "SreTokenQuotaRateLimiter" -> Ok(SreTokenQuotaRateLimiter)
    "SreCephOsdDiskSafetyGuard" -> Ok(SreCephOsdDiskSafetyGuard)
    "SreForecastPredictivePreflight" -> Ok(SreForecastPredictivePreflight)
    "SreEndocrineHormoneBalancer" -> Ok(SreEndocrineHormoneBalancer)
    "SreAdaptiveRateController" -> Ok(SreAdaptiveRateController)
    "SreWindowedTrendAnalyzer" -> Ok(SreWindowedTrendAnalyzer)
    "SreDynamicCapacityPlanner" -> Ok(SreDynamicCapacityPlanner)
    "SreMetabolicGovernor" -> Ok(SreMetabolicGovernor)
    "SreDegradedModeOrchestrator" -> Ok(SreDegradedModeOrchestrator)
    "SreLoadSheddingGovernor" -> Ok(SreLoadSheddingGovernor)
    "SwarmMesh" -> Ok(SwarmMesh)
    "EpidemicGossip" -> Ok(EpidemicGossip)
    "SreSessionShardRebalancer" -> Ok(SreSessionShardRebalancer)
    "SrePrajnaCircuitBreaker" -> Ok(SrePrajnaCircuitBreaker)
    "SreMeshPartitionHealer" -> Ok(SreMeshPartitionHealer)
    "SreCascadingFailureShield" -> Ok(SreCascadingFailureShield)
    "SreGossipMembershipCluster" -> Ok(SreGossipMembershipCluster)
    "SreConsensusConsulElector" -> Ok(SreConsensusConsulElector)
    "GroundGateway" -> Ok(GroundGateway)
    "SreCrdtVersionVectorSync" -> Ok(SreCrdtVersionVectorSync)
    "SreCastIncidentInvestigator" -> Ok(SreCastIncidentInvestigator)
    "SrePostMortemRcaSynthesizer" -> Ok(SrePostMortemRcaSynthesizer)
    "SreFederationGatewayProxy" -> Ok(SreFederationGatewayProxy)
    "SreTelemetryBackplanePublisher" -> Ok(SreTelemetryBackplanePublisher)
    "SreDisasterRecoverySequencer" -> Ok(SreDisasterRecoverySequencer)
    "SreAuditTrailLedgerSigner" -> Ok(SreAuditTrailLedgerSigner)
    "ConstitutionalGuardian" -> Ok(ConstitutionalGuardian)
    "FormalOracle" -> Ok(FormalOracle)
    "HardwareDriveInterlock" -> Ok(HardwareDriveInterlock)
    "RochaSemioticCutGuard" -> Ok(RochaSemioticCutGuard)
    "VerificationChecklistAuditor" -> Ok(VerificationChecklistAuditor)
    "VerificationMathGateCertifier" -> Ok(VerificationMathGateCertifier)
    "VerificationTcmCoordinateProtector" ->
      Ok(VerificationTcmCoordinateProtector)
    "VerificationZeroMudaPurityEnforcer" ->
      Ok(VerificationZeroMudaPurityEnforcer)
    "DeterministicFlightController" -> Ok(DeterministicFlightController)
    "SubstrateReactor" -> Ok(SubstrateReactor)
    "VerificationPinnedOtpDifferential" -> Ok(VerificationPinnedOtpDifferential)
    "VerificationGospelOrtacRuntimeMonitor" ->
      Ok(VerificationGospelOrtacRuntimeMonitor)
    "VerificationSmtNegationAuditor" -> Ok(VerificationSmtNegationAuditor)
    "VerificationZ3UnsatValidator" -> Ok(VerificationZ3UnsatValidator)
    "VerificationNegativeControlVerifier" ->
      Ok(VerificationNegativeControlVerifier)
    "VerificationTypestateInvariantChecker" ->
      Ok(VerificationTypestateInvariantChecker)
    "AvionicsTelemetry" -> Ok(AvionicsTelemetry)
    "CockpitTelemetry" -> Ok(CockpitTelemetry)
    "VerificationBrowserMatrixTester" -> Ok(VerificationBrowserMatrixTester)
    "VerificationMutationAdequacyKiller" ->
      Ok(VerificationMutationAdequacyKiller)
    "VerificationTddLawEnforcer" -> Ok(VerificationTddLawEnforcer)
    "VerificationRedGreenRevertJudge" -> Ok(VerificationRedGreenRevertJudge)
    "VerificationFlaccidLawDetector" -> Ok(VerificationFlaccidLawDetector)
    "VerificationFixtureTotalityAuditor" ->
      Ok(VerificationFixtureTotalityAuditor)
    "McdcAvionicsTap" -> Ok(McdcAvionicsTap)
    "DifferentialBisimulation" -> Ok(DifferentialBisimulation)
    "VerificationNineModalityExecutor" -> Ok(VerificationNineModalityExecutor)
    "VerificationToolSchemaConformance" -> Ok(VerificationToolSchemaConformance)
    "VerificationBddScenarioRunner" -> Ok(VerificationBddScenarioRunner)
    "VerificationStateTransitionAsserter" ->
      Ok(VerificationStateTransitionAsserter)
    "VerificationTraceEquivalenceJudge" -> Ok(VerificationTraceEquivalenceJudge)
    "VerificationMcdcBranchCoverageAuditor" ->
      Ok(VerificationMcdcBranchCoverageAuditor)
    "VerificationPlaywrightControlAuditor" ->
      Ok(VerificationPlaywrightControlAuditor)
    "VerificationMultiTurnDialogueVerifier" ->
      Ok(VerificationMultiTurnDialogueVerifier)
    "VerificationPropertyGeneratorFuzzer" ->
      Ok(VerificationPropertyGeneratorFuzzer)
    "VerificationGenerativeShrinkEngine" ->
      Ok(VerificationGenerativeShrinkEngine)
    "VerificationBoundaryValueTester" -> Ok(VerificationBoundaryValueTester)
    "VerificationSeededRandomReplayer" -> Ok(VerificationSeededRandomReplayer)
    "VerificationCorpusModuleExecutor" -> Ok(VerificationCorpusModuleExecutor)
    "VerificationAstMutantSynthesizer" -> Ok(VerificationAstMutantSynthesizer)
    "VerificationAdkEvalBenchmark" -> Ok(VerificationAdkEvalBenchmark)
    "VerificationTrajectoryReplayCertifier" ->
      Ok(VerificationTrajectoryReplayCertifier)
    "VerificationHallucinationScorer" -> Ok(VerificationHallucinationScorer)
    "VerificationEntropyCalculator" -> Ok(VerificationEntropyCalculator)
    "VerificationDivergenceMetricScorer" ->
      Ok(VerificationDivergenceMetricScorer)
    "VerificationFactualGroundingAuditor" ->
      Ok(VerificationFactualGroundingAuditor)
    "VerificationReasoningStepValidator" ->
      Ok(VerificationReasoningStepValidator)
    "VerificationContextRetentionVerifier" ->
      Ok(VerificationContextRetentionVerifier)
    "VerificationSimulationEnvironment" -> Ok(VerificationSimulationEnvironment)
    "VerificationActorBisimulationTester" ->
      Ok(VerificationActorBisimulationTester)
    "VerificationConcurrencyRaceDetector" ->
      Ok(VerificationConcurrencyRaceDetector)
    "VerificationModelCheckerBridge" -> Ok(VerificationModelCheckerBridge)
    "VerificationLinearizabilityOracle" -> Ok(VerificationLinearizabilityOracle)
    "VerificationDistributedPartitionTester" ->
      Ok(VerificationDistributedPartitionTester)
    "VerificationMessageLossSimulator" -> Ok(VerificationMessageLossSimulator)
    "VerificationClockDriftChaosTester" -> Ok(VerificationClockDriftChaosTester)
    "VerificationSheafGluingHarmonizer" -> Ok(VerificationSheafGluingHarmonizer)
    "VerificationLeanFormalProofOracle" -> Ok(VerificationLeanFormalProofOracle)
    "VerificationQuintParityFrontierOracle" ->
      Ok(VerificationQuintParityFrontierOracle)
    "VerificationMasterChecklistGatekeeper" ->
      Ok(VerificationMasterChecklistGatekeeper)
    "VerificationParityRatchetEnforcer" -> Ok(VerificationParityRatchetEnforcer)
    "VerificationBaselineReleaseGatekeeper" ->
      Ok(VerificationBaselineReleaseGatekeeper)
    "VerificationFormalEvidenceArchiver" ->
      Ok(VerificationFormalEvidenceArchiver)
    "VerificationSovereignConsensusRatifier" ->
      Ok(VerificationSovereignConsensusRatifier)
    "IntelligenceRochaCutValidator" -> Ok(IntelligenceRochaCutValidator)
    "IntelligenceCodeBiologyBoundaryGuard" ->
      Ok(IntelligenceCodeBiologyBoundaryGuard)
    "IntelligenceSymbolMatterDecoupler" -> Ok(IntelligenceSymbolMatterDecoupler)
    "IntelligenceSemioticClosureAuditor" ->
      Ok(IntelligenceSemioticClosureAuditor)
    "IntelligenceSemanticAnchorProtector" ->
      Ok(IntelligenceSemanticAnchorProtector)
    "IntelligenceBiomorphicMorphogenRouter" ->
      Ok(IntelligenceBiomorphicMorphogenRouter)
    "IntelligenceCyberneticFeedbackHarmonizer" ->
      Ok(IntelligenceCyberneticFeedbackHarmonizer)
    "IntelligenceMetabolicHomeostasisTracker" ->
      Ok(IntelligenceMetabolicHomeostasisTracker)
    "IntelligenceSheafCohomologyEngine" -> Ok(IntelligenceSheafCohomologyEngine)
    "IntelligenceLocalSectionExtractor" -> Ok(IntelligenceLocalSectionExtractor)
    "IntelligencePresheafFunctorMapper" -> Ok(IntelligencePresheafFunctorMapper)
    "IntelligenceGluingMorphismSynthesizer" ->
      Ok(IntelligenceGluingMorphismSynthesizer)
    "IntelligenceRestrictionMapValidator" ->
      Ok(IntelligenceRestrictionMapValidator)
    "IntelligenceCechComplexBuilder" -> Ok(IntelligenceCechComplexBuilder)
    "IntelligenceSpectralSequenceAnalyzer" ->
      Ok(IntelligenceSpectralSequenceAnalyzer)
    "IntelligenceCategoryTheoryBridge" -> Ok(IntelligenceCategoryTheoryBridge)
    "VerificationZkKmKnowledgeCurrency" -> Ok(VerificationZkKmKnowledgeCurrency)
    "IntelligenceZettelkastenLibrarian" -> Ok(IntelligenceZettelkastenLibrarian)
    "IntelligencePermanentAdrCustodian" -> Ok(IntelligencePermanentAdrCustodian)
    "IntelligenceMapOfContentCurator" -> Ok(IntelligenceMapOfContentCurator)
    "IntelligenceEpisodicMemoryIndexer" -> Ok(IntelligenceEpisodicMemoryIndexer)
    "IntelligenceBidirectionalLinkResolver" ->
      Ok(IntelligenceBidirectionalLinkResolver)
    "IntelligenceFractalTagTaxonomist" -> Ok(IntelligenceFractalTagTaxonomist)
    "IntelligenceKnowledgeDecayDetector" ->
      Ok(IntelligenceKnowledgeDecayDetector)
    "SdlcOntologyInfranodusSynthesizer" -> Ok(SdlcOntologyInfranodusSynthesizer)
    "VerificationInfranodusCentralityAuditor" ->
      Ok(VerificationInfranodusCentralityAuditor)
    "SdlcSemanticVectorEmbedding" -> Ok(SdlcSemanticVectorEmbedding)
    "IntelligenceRdfOwlOntologyBuilder" -> Ok(IntelligenceRdfOwlOntologyBuilder)
    "IntelligenceKnowledgeGraphHarmonizer" ->
      Ok(IntelligenceKnowledgeGraphHarmonizer)
    "IntelligenceConceptLatticeMiner" -> Ok(IntelligenceConceptLatticeMiner)
    "IntelligenceSemanticTriplestoreCustodian" ->
      Ok(IntelligenceSemanticTriplestoreCustodian)
    "IntelligenceTaxonomyGraphTraverser" ->
      Ok(IntelligenceTaxonomyGraphTraverser)
    "CognitiveOodaIntent" -> Ok(CognitiveOodaIntent)
    "IntelligenceOodaLoopOrchestrator" -> Ok(IntelligenceOodaLoopOrchestrator)
    "IntelligenceObserveSensorAggregator" ->
      Ok(IntelligenceObserveSensorAggregator)
    "IntelligenceOrientContextSynthesizer" ->
      Ok(IntelligenceOrientContextSynthesizer)
    "IntelligenceDecideStrategySelector" ->
      Ok(IntelligenceDecideStrategySelector)
    "IntelligenceActuatorTaskDispatcher" ->
      Ok(IntelligenceActuatorTaskDispatcher)
    "IntelligenceReasoningGraphExpander" ->
      Ok(IntelligenceReasoningGraphExpander)
    "IntelligenceHypothesisTestingAgent" ->
      Ok(IntelligenceHypothesisTestingAgent)
    "IntelligenceMaxDaemonSupervisor" -> Ok(IntelligenceMaxDaemonSupervisor)
    "IntelligenceMojoKernelOptimizer" -> Ok(IntelligenceMojoKernelOptimizer)
    "IntelligenceJsonRpcStdioPipeBridge" ->
      Ok(IntelligenceJsonRpcStdioPipeBridge)
    "IntelligenceProcessIsolationEnforcer" ->
      Ok(IntelligenceProcessIsolationEnforcer)
    "IntelligenceBatchInferenceDispatcher" ->
      Ok(IntelligenceBatchInferenceDispatcher)
    "IntelligenceTokenStreamingPacer" -> Ok(IntelligenceTokenStreamingPacer)
    "IntelligenceModelWeightQuarantine" -> Ok(IntelligenceModelWeightQuarantine)
    "IntelligenceSlmLocalCacheCustodian" ->
      Ok(IntelligenceSlmLocalCacheCustodian)
    "IntelligenceSwarmConsensusDirector" ->
      Ok(IntelligenceSwarmConsensusDirector)
    "IntelligenceRoleSpecializationMatcher" ->
      Ok(IntelligenceRoleSpecializationMatcher)
    "IntelligenceTaskDecompositionPlanner" ->
      Ok(IntelligenceTaskDecompositionPlanner)
    "IntelligenceAgentPeerMessenger" -> Ok(IntelligenceAgentPeerMessenger)
    "IntelligenceSwarmConflictMediator" -> Ok(IntelligenceSwarmConflictMediator)
    "IntelligenceCollectiveMemorySync" -> Ok(IntelligenceCollectiveMemorySync)
    "IntelligenceAutonomousNegotiationBroker" ->
      Ok(IntelligenceAutonomousNegotiationBroker)
    "IntelligenceFederatedPromptOrchestrator" ->
      Ok(IntelligenceFederatedPromptOrchestrator)
    "IntelligenceMasterEncyclopediaIndexer" ->
      Ok(IntelligenceMasterEncyclopediaIndexer)
    "IntelligenceCorpusTransclusionEngine" ->
      Ok(IntelligenceCorpusTransclusionEngine)
    "IntelligenceLivingCatalogPublisher" ->
      Ok(IntelligenceLivingCatalogPublisher)
    "IntelligenceCrossPlatformKnowledgeMirror" ->
      Ok(IntelligenceCrossPlatformKnowledgeMirror)
    "IntelligenceSovereignReviewSynthesizer" ->
      Ok(IntelligenceSovereignReviewSynthesizer)
    "IntelligenceKnowledgeArchivalVault" ->
      Ok(IntelligenceKnowledgeArchivalVault)
    "IntelligenceEpistemicCertaintyEvaluator" ->
      Ok(IntelligenceEpistemicCertaintyEvaluator)
    "IntelligenceUnifiedSiteNavigationCurator" ->
      Ok(IntelligenceUnifiedSiteNavigationCurator)
    _ -> Error(Nil)
  }
}

pub type AgentTypeSpec {
  AgentTypeSpec(
    kind: AgentKind,
    name: String,
    c3i_system: C3iSystem,
    fractal_layer: Int,
    fractal_tag: String,
    fpp_component_kind: ComponentKind,
    base_id: Int,
    id_span: Int,
    queue_policy: QueueFull,
    description: String,
    operational_domain: String,
    sdlc_phase: String,
    sre_resilience_tier: String,
    evidence_contracts: List(String),
    hsm_machine: StateMachine,
  )
}

fn build_guardian_hsm() -> StateMachine {
  let standby =
    HierarchicalState(
      name: "Standby",
      parent: Some("Operational"),
      entry: ["guardian_standby_entered"],
      exit: ["guardian_standby_exited"],
      transitions: [
        Transition(
          on_signal: "evaluate_intent",
          guard: None,
          do_actions: ["verify_safety_invariants"],
          target: ToState("Verifying"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let verifying =
    HierarchicalState(
      name: "Verifying",
      parent: Some("Operational"),
      entry: ["guardian_verifying_entered"],
      exit: ["guardian_verifying_exited"],
      transitions: [
        Transition(
          on_signal: "consensus_pass",
          guard: None,
          do_actions: ["grant_authorization"],
          target: ToState("Approved"),
        ),
        Transition(
          on_signal: "violation_detected",
          guard: None,
          do_actions: ["trip_safety_veto"],
          target: ToState("VetoTripped"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let approved =
    HierarchicalState(
      name: "Approved",
      parent: Some("Operational"),
      entry: ["guardian_approved_entered"],
      exit: ["guardian_approved_exited"],
      transitions: [
        Transition(
          on_signal: "cycle_complete",
          guard: None,
          do_actions: ["reset_evaluator"],
          target: ToState("Standby"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let operational =
    HierarchicalState(
      name: "Operational",
      parent: None,
      entry: ["guardian_operational_entered"],
      exit: ["guardian_operational_exited"],
      transitions: [
        Transition(
          on_signal: "fatal_hardware_violation",
          guard: None,
          do_actions: ["emergency_lockdown"],
          target: ToState("VetoTripped"),
        ),
      ],
      sub_states: [standby, verifying, approved],
      initial_sub_state: Some("Standby"),
    )

  let veto_tripped =
    HierarchicalState(
      name: "VetoTripped",
      parent: None,
      entry: ["fail_closed_halt"],
      exit: ["operator_override_exit"],
      transitions: [
        Transition(
          on_signal: "operator_reset",
          guard: None,
          do_actions: ["clear_veto"],
          target: ToState("Standby"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  HierarchicalMachine(
    machine_name: "GuardianHSM",
    signals: make_signals([
      "evaluate_intent",
      "consensus_pass",
      "violation_detected",
      "cycle_complete",
      "fatal_hardware_violation",
      "operator_reset",
    ]),
    guards: ["is_two_key_approved", "is_os_nvme_target"],
    actions: [
      "verify_safety_invariants",
      "grant_authorization",
      "trip_safety_veto",
      "reset_evaluator",
      "emergency_lockdown",
      "clear_veto",
    ],
    root_states: [operational, veto_tripped],
    choices: [],
    initial: #([], "Operational"),
  )
}

fn build_flight_controller_hsm() -> StateMachine {
  let disarmed =
    HierarchicalState(
      name: "Disarmed",
      parent: Some("FlightState"),
      entry: ["controller_disarmed"],
      exit: ["controller_arming"],
      transitions: [
        Transition(
          on_signal: "arm_controller",
          guard: None,
          do_actions: ["enable_actuators"],
          target: ToState("Armed"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let armed =
    HierarchicalState(
      name: "Armed",
      parent: Some("FlightState"),
      entry: ["controller_armed"],
      exit: ["controller_launching"],
      transitions: [
        Transition(
          on_signal: "engage_trajectory",
          guard: None,
          do_actions: ["execute_rate_group"],
          target: ToState("TrajectoryActive"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let trajectory_active =
    HierarchicalState(
      name: "TrajectoryActive",
      parent: Some("FlightState"),
      entry: ["controller_tracking"],
      exit: ["controller_stopping"],
      transitions: [
        Transition(
          on_signal: "disengage",
          guard: None,
          do_actions: ["standby_actuators"],
          target: ToState("Disarmed"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let flight_state =
    HierarchicalState(
      name: "FlightState",
      parent: None,
      entry: ["flight_subsystem_init"],
      exit: ["flight_subsystem_shutdown"],
      transitions: [
        Transition(
          on_signal: "emergency_stop",
          guard: None,
          do_actions: ["cut_power"],
          target: ToState("EmergencyHalt"),
        ),
      ],
      sub_states: [disarmed, armed, trajectory_active],
      initial_sub_state: Some("Disarmed"),
    )

  let emergency_halt =
    HierarchicalState(
      name: "EmergencyHalt",
      parent: None,
      entry: ["halt_controller"],
      exit: ["reboot_controller"],
      transitions: [
        Transition(
          on_signal: "reboot",
          guard: None,
          do_actions: ["warm_boot"],
          target: ToState("FlightState"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  HierarchicalMachine(
    machine_name: "FlightControllerHSM",
    signals: make_signals([
      "arm_controller",
      "engage_trajectory",
      "disengage",
      "emergency_stop",
      "reboot",
    ]),
    guards: ["actuators_nominal"],
    actions: [
      "enable_actuators",
      "execute_rate_group",
      "standby_actuators",
      "cut_power",
      "warm_boot",
    ],
    root_states: [flight_state, emergency_halt],
    choices: [],
    initial: #([], "FlightState"),
  )
}

fn build_mission_phase_hsm() -> StateMachine {
  let pre_launch =
    HierarchicalState(
      name: "PreLaunch",
      parent: Some("MissionLifecycle"),
      entry: ["prelaunch_checks"],
      exit: ["countdown_complete"],
      transitions: [
        Transition(
          on_signal: "launch",
          guard: None,
          do_actions: ["ignite_ascent"],
          target: ToState("Ascent"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let ascent =
    HierarchicalState(
      name: "Ascent",
      parent: Some("MissionLifecycle"),
      entry: ["ascent_guidance"],
      exit: ["meco_achieved"],
      transitions: [
        Transition(
          on_signal: "meco",
          guard: None,
          do_actions: ["stage_separation"],
          target: ToState("NominalScience"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let nominal_science =
    HierarchicalState(
      name: "NominalScience",
      parent: Some("MissionLifecycle"),
      entry: ["deploy_instruments"],
      exit: ["stow_instruments"],
      transitions: [
        Transition(
          on_signal: "anomaly",
          guard: None,
          do_actions: ["enter_safe_hold"],
          target: ToState("SafeHold"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let mission_lifecycle =
    HierarchicalState(
      name: "MissionLifecycle",
      parent: None,
      entry: ["mission_clock_start"],
      exit: ["mission_end"],
      transitions: [],
      sub_states: [pre_launch, ascent, nominal_science],
      initial_sub_state: Some("PreLaunch"),
    )

  let safe_hold =
    HierarchicalState(
      name: "SafeHold",
      parent: None,
      entry: ["sun_point_panels"],
      exit: ["telemetry_diagnostics_cleared"],
      transitions: [
        Transition(
          on_signal: "recovery_pass",
          guard: None,
          do_actions: ["resume_mission"],
          target: ToState("NominalScience"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  HierarchicalMachine(
    machine_name: "MissionPhaseHSM",
    signals: make_signals(["launch", "meco", "anomaly", "recovery_pass"]),
    guards: ["orbit_stable"],
    actions: [
      "ignite_ascent",
      "stage_separation",
      "enter_safe_hold",
      "resume_mission",
    ],
    root_states: [mission_lifecycle, safe_hold],
    choices: [],
    initial: #([], "MissionLifecycle"),
  )
}

fn build_cognitive_ooda_hsm() -> StateMachine {
  let observe =
    HierarchicalState(
      name: "Observe",
      parent: None,
      entry: ["ingest_telemetry_sheaf"],
      exit: ["sheaf_ready"],
      transitions: [
        Transition(
          on_signal: "orient",
          guard: None,
          do_actions: ["evaluate_rete_rules"],
          target: ToState("Orient"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let orient =
    HierarchicalState(
      name: "Orient",
      parent: None,
      entry: ["knowledge_lookup"],
      exit: ["context_bound"],
      transitions: [
        Transition(
          on_signal: "decide",
          guard: None,
          do_actions: ["formulate_intent"],
          target: ToState("Decide"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let decide =
    HierarchicalState(
      name: "Decide",
      parent: None,
      entry: ["intent_generation"],
      exit: ["intent_sealed"],
      transitions: [
        Transition(
          on_signal: "act",
          guard: None,
          do_actions: ["dispatch_flight_intent"],
          target: ToState("Observe"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  HierarchicalMachine(
    machine_name: "CognitiveOodaHSM",
    signals: make_signals(["orient", "decide", "act"]),
    guards: [],
    actions: [
      "evaluate_rete_rules",
      "formulate_intent",
      "dispatch_flight_intent",
    ],
    root_states: [observe, orient, decide],
    choices: [],
    initial: #([], "Observe"),
  )
}

fn build_hardware_drive_interlock_hsm() -> StateMachine {
  let active_guard =
    HierarchicalState(
      name: "Guarding",
      parent: None,
      entry: ["drive_guard_armed"],
      exit: ["drive_guard_standdown"],
      transitions: [
        Transition(
          on_signal: "probe_target",
          guard: None,
          do_actions: ["verify_nvme_serial"],
          target: ToState("Guarding"),
        ),
        Transition(
          on_signal: "denied_serial_detected",
          guard: None,
          do_actions: ["trip_hardware_fault_lock"],
          target: ToState("LockedOut"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let locked_out =
    HierarchicalState(
      name: "LockedOut",
      parent: None,
      entry: ["halt_controller_io"],
      exit: ["cold_reboot_required"],
      transitions: [],
      sub_states: [],
      initial_sub_state: None,
    )

  HierarchicalMachine(
    machine_name: "HardwareDriveInterlockHSM",
    signals: make_signals([
      "probe_target",
      "denied_serial_detected",
      "system_reboot",
    ]),
    guards: ["is_hard_denied_serial"],
    actions: [
      "verify_nvme_serial",
      "trip_hardware_fault_lock",
      "halt_controller_io",
    ],
    root_states: [active_guard, locked_out],
    choices: [],
    initial: #([], "Guarding"),
  )
}

fn build_reduction_scheduler_hsm() -> StateMachine {
  let running =
    HierarchicalState(
      name: "Executing",
      parent: None,
      entry: ["reset_reduction_counter"],
      exit: ["yield_cpu_slice"],
      transitions: [
        Transition(
          on_signal: "reduction_exhausted",
          guard: None,
          do_actions: ["suspend_and_enqueue"],
          target: ToState("Yielded"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let yielded =
    HierarchicalState(
      name: "Yielded",
      parent: None,
      entry: ["schedule_next_process"],
      exit: ["resume_process_context"],
      transitions: [
        Transition(
          on_signal: "timeslice_granted",
          guard: None,
          do_actions: ["load_registers"],
          target: ToState("Executing"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  HierarchicalMachine(
    machine_name: "ReductionSchedulerHSM",
    signals: make_signals([
      "reduction_exhausted",
      "timeslice_granted",
      "priority_bump",
    ]),
    guards: ["is_budget_exceeded"],
    actions: [
      "reset_reduction_counter",
      "suspend_and_enqueue",
      "schedule_next_process",
      "load_registers",
    ],
    root_states: [running, yielded],
    choices: [],
    initial: #([], "Executing"),
  )
}

fn build_substrate_reactor_hsm() -> StateMachine {
  let polling =
    HierarchicalState(
      name: "Polling",
      parent: None,
      entry: ["arm_epoll_wait"],
      exit: ["disarm_epoll_wait"],
      transitions: [
        Transition(
          on_signal: "io_event_ready",
          guard: None,
          do_actions: ["dispatch_row_event"],
          target: ToState("Dispatching"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let dispatching =
    HierarchicalState(
      name: "Dispatching",
      parent: None,
      entry: ["propagate_actor_effect"],
      exit: ["complete_dispatch"],
      transitions: [
        Transition(
          on_signal: "dispatch_complete",
          guard: None,
          do_actions: ["rearm_interest"],
          target: ToState("Polling"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  HierarchicalMachine(
    machine_name: "SubstrateReactorHSM",
    signals: make_signals([
      "io_event_ready",
      "dispatch_complete",
      "timeout_tick",
    ]),
    guards: ["has_ready_events"],
    actions: [
      "arm_epoll_wait",
      "dispatch_row_event",
      "propagate_actor_effect",
      "rearm_interest",
    ],
    root_states: [polling, dispatching],
    choices: [],
    initial: #([], "Polling"),
  )
}

fn build_lockless_hamt_hsm() -> StateMachine {
  let serving =
    HierarchicalState(
      name: "Serving",
      parent: None,
      entry: ["init_root_trie"],
      exit: ["quiesce_trie"],
      transitions: [
        Transition(
          on_signal: "atomic_cas_update",
          guard: None,
          do_actions: ["commit_hamt_node"],
          target: ToState("Serving"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  HierarchicalMachine(
    machine_name: "LocklessHamtStorageHSM",
    signals: make_signals(["atomic_cas_update", "compact_tree"]),
    guards: ["cas_matches_current"],
    actions: ["init_root_trie", "commit_hamt_node", "quiesce_trie"],
    root_states: [serving],
    choices: [],
    initial: #([], "Serving"),
  )
}

fn build_crash_wal_hsm() -> StateMachine {
  let appending =
    HierarchicalState(
      name: "Appending",
      parent: None,
      entry: ["open_wal_file_descriptor"],
      exit: ["sync_and_close_fd"],
      transitions: [
        Transition(
          on_signal: "log_event_entry",
          guard: None,
          do_actions: ["append_with_crc32"],
          target: ToState("Appending"),
        ),
        Transition(
          on_signal: "reboot_recovery_requested",
          guard: None,
          do_actions: ["scan_and_replay_log"],
          target: ToState("Replaying"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let replaying =
    HierarchicalState(
      name: "Replaying",
      parent: None,
      entry: ["verify_log_crc32"],
      exit: ["mark_replay_complete"],
      transitions: [
        Transition(
          on_signal: "replay_done",
          guard: None,
          do_actions: ["resume_append_mode"],
          target: ToState("Appending"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  HierarchicalMachine(
    machine_name: "CrashWalReplayHSM",
    signals: make_signals([
      "log_event_entry",
      "reboot_recovery_requested",
      "replay_done",
    ]),
    guards: ["is_wal_crc_valid"],
    actions: [
      "open_wal_file_descriptor",
      "append_with_crc32",
      "scan_and_replay_log",
      "verify_log_crc32",
      "resume_append_mode",
    ],
    root_states: [appending, replaying],
    choices: [],
    initial: #([], "Appending"),
  )
}

fn build_sdlc_arch_synth_hsm() -> StateMachine {
  let modeling =
    HierarchicalState(
      name: "Modeling",
      parent: None,
      entry: ["arch_modeling_init"],
      exit: ["arch_model_ready"],
      transitions: [
        Transition(
          on_signal: "start_decomposition",
          guard: None,
          do_actions: ["decompose_fractal_layers"],
          target: ToState("Decomposing"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let decomposing =
    HierarchicalState(
      name: "Decomposing",
      parent: None,
      entry: ["arch_decomposition_active"],
      exit: ["arch_decomposition_done"],
      transitions: [
        Transition(
          on_signal: "verify_invariants",
          guard: None,
          do_actions: ["validate_ast_invariants"],
          target: ToState("Synthesized"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let synthesized =
    HierarchicalState(
      name: "Synthesized",
      parent: None,
      entry: ["arch_spec_sealed"],
      exit: ["arch_spec_reopened"],
      transitions: [
        Transition(
          on_signal: "synthesis_complete",
          guard: None,
          do_actions: ["publish_architecture_spec"],
          target: ToState("Modeling"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  HierarchicalMachine(
    machine_name: "SdlcArchSynthHSM",
    signals: make_signals([
      "start_decomposition",
      "verify_invariants",
      "synthesis_complete",
    ]),
    guards: ["is_valid_fractal_topology"],
    actions: [
      "decompose_fractal_layers",
      "validate_ast_invariants",
      "publish_architecture_spec",
    ],
    root_states: [modeling, decomposing, synthesized],
    choices: [],
    initial: #([], "Modeling"),
  )
}

fn build_sre_lyapunov_detector_hsm() -> StateMachine {
  let sampling =
    HierarchicalState(
      name: "WindowSampling",
      parent: None,
      entry: ["sampling_telemetry_window"],
      exit: ["telemetry_window_full"],
      transitions: [
        Transition(
          on_signal: "sample_tick",
          guard: None,
          do_actions: ["compute_trajectory_drift"],
          target: ToState("EvaluatingLambda"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let evaluating =
    HierarchicalState(
      name: "EvaluatingLambda",
      parent: None,
      entry: ["solving_least_squares_lambda"],
      exit: ["lambda_computed_exit"],
      transitions: [
        Transition(
          on_signal: "lambda_computed",
          guard: None,
          do_actions: ["verify_negative_exponent"],
          target: ToState("TrendStable"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let stable =
    HierarchicalState(
      name: "TrendStable",
      parent: None,
      entry: ["asymptotically_stable_state"],
      exit: ["new_window_started"],
      transitions: [
        Transition(
          on_signal: "sample_tick",
          guard: None,
          do_actions: ["shift_sample_window"],
          target: ToState("WindowSampling"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  HierarchicalMachine(
    machine_name: "SreLyapunovTrendHSM",
    signals: make_signals(["sample_tick", "lambda_computed"]),
    guards: ["is_lambda_negative"],
    actions: [
      "compute_trajectory_drift",
      "verify_negative_exponent",
      "shift_sample_window",
    ],
    root_states: [sampling, evaluating, stable],
    choices: [],
    initial: #([], "WindowSampling"),
  )
}

fn build_verification_checklist_auditor_hsm() -> StateMachine {
  let scanning =
    HierarchicalState(
      name: "ScanningChecklist",
      parent: None,
      entry: ["evaluating_18_checkpoints"],
      exit: ["checkpoint_batch_done"],
      transitions: [
        Transition(
          on_signal: "audit_check",
          guard: None,
          do_actions: ["evaluate_single_checkpoint"],
          target: ToState("DomainEvaluated"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let domain_eval =
    HierarchicalState(
      name: "DomainEvaluated",
      parent: None,
      entry: ["aggregating_5_domains"],
      exit: ["all_domains_tallied"],
      transitions: [
        Transition(
          on_signal: "all_domains_pass",
          guard: None,
          do_actions: ["ratify_18_18_checklist"],
          target: ToState("Checklist18Green"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  let green =
    HierarchicalState(
      name: "Checklist18Green",
      parent: None,
      entry: ["checklist_gate_ratified"],
      exit: ["recheck_triggered"],
      transitions: [
        Transition(
          on_signal: "checklist_reset",
          guard: None,
          do_actions: ["clear_checklist_cache"],
          target: ToState("ScanningChecklist"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  HierarchicalMachine(
    machine_name: "VerificationChecklistHSM",
    signals: make_signals(["audit_check", "all_domains_pass", "checklist_reset"]),
    guards: ["is_18_of_18_passing"],
    actions: [
      "evaluate_single_checkpoint",
      "ratify_18_18_checklist",
      "clear_checklist_cache",
    ],
    root_states: [scanning, domain_eval, green],
    choices: [],
    initial: #([], "ScanningChecklist"),
  )
}

fn build_agent_hsm_for_kind(kind: AgentKind, name: String) -> StateMachine {
  case kind {
    ConstitutionalGuardian -> build_guardian_hsm()
    DeterministicFlightController -> build_flight_controller_hsm()
    MissionPhaseHsm -> build_mission_phase_hsm()
    CognitiveOodaIntent -> build_cognitive_ooda_hsm()
    HardwareDriveInterlock -> build_hardware_drive_interlock_hsm()
    DeterministicReductionScheduler -> build_reduction_scheduler_hsm()
    SubstrateReactor -> build_substrate_reactor_hsm()
    LocklessHamtStorage -> build_lockless_hamt_hsm()
    CrashWalReplay -> build_crash_wal_hsm()
    SdlcArchitectureSynthesizer -> build_sdlc_arch_synth_hsm()
    SreLyapunovTrendDetector -> build_sre_lyapunov_detector_hsm()
    VerificationChecklistAuditor -> build_verification_checklist_auditor_hsm()
    _ -> build_agent_hsm(name)
  }
}

fn build_agent_hsm(machine_name: String) -> StateMachine {
  let active_state =
    HierarchicalState(
      name: "Active",
      parent: None,
      entry: ["init_" <> machine_name],
      exit: ["stop_" <> machine_name],
      transitions: [
        Transition(
          on_signal: "tick",
          guard: None,
          do_actions: ["execute_cycle"],
          target: ToState("Active"),
        ),
      ],
      sub_states: [],
      initial_sub_state: None,
    )

  HierarchicalMachine(
    machine_name: machine_name,
    signals: make_signals(["tick", "command", "fault"]),
    guards: [],
    actions: ["execute_cycle"],
    root_states: [active_state],
    choices: [],
    initial: #([], "Active"),
  )
}

fn build_spec_record(
  kind: AgentKind,
  name: String,
  sys: C3iSystem,
  layer: Int,
  tag: String,
  comp_kind: ComponentKind,
  base_id: Int,
  span: Int,
  qpol: QueueFull,
  desc: String,
  domain: String,
  phase: String,
  tier: String,
  contracts: List(String),
) -> AgentTypeSpec {
  AgentTypeSpec(
    kind: kind,
    name: name,
    c3i_system: sys,
    fractal_layer: layer,
    fractal_tag: tag,
    fpp_component_kind: comp_kind,
    base_id: base_id,
    id_span: span,
    queue_policy: qpol,
    description: desc,
    operational_domain: domain,
    sdlc_phase: phase,
    sre_resilience_tier: tier,
    evidence_contracts: contracts,
    hsm_machine: build_agent_hsm_for_kind(
      kind,
      agent_kind_to_string(kind) <> "HSM",
    ),
  )
}

pub fn build_sdlc_architecture_synthesizer_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcArchitectureSynthesizer,
    "C3I SDLC Architecture Synthesizer Agent",
    C3iSdlc,
    0,
    "#fractal-l0",
    Active,
    4096,
    32,
    Assert,
    "Synthesizes system architectures using ADD and fractal rules",
    "Architecture Synthesis",
    "System Design",
    "SIL-5 / Safety Critical",
    ["SC-SDLC-001"],
  )
}

pub fn build_sdlc_hitl_gatekeeper_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcHitlGatekeeper,
    "C3I SDLC HITL Gatekeeper Agent",
    C3iSdlc,
    0,
    "#fractal-l0",
    Active,
    4128,
    32,
    Assert,
    "Human-In-The-Loop gatekeeper enforcing operator intervention pauses",
    "Constitutional Governance",
    "HITL Authorization",
    "SIL-6 / Sovereign Core",
    ["SC-SDLC-002"],
  )
}

pub fn build_sdlc_constitutional_specifier_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcConstitutionalSpecifier,
    "C3I SDLC Constitutional Specifier Agent",
    C3iSdlc,
    0,
    "#fractal-l0",
    Active,
    4160,
    32,
    Assert,
    "Formal constitutional rules and governance policy specification",
    "Constitutional Synthesis",
    "Governance Specification",
    "SIL-6 / Sovereign Core",
    ["SC-SDLC-003"],
  )
}

pub fn build_sdlc_policy_rule_compiler_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcPolicyRuleCompiler,
    "C3I SDLC Policy Rule Compiler Agent",
    C3iSdlc,
    0,
    "#fractal-l0",
    Active,
    4192,
    32,
    Assert,
    "Compiles superset TOML governance policies into typed rules",
    "Policy Compilation",
    "Policy Generation",
    "SIL-5 / Safety Critical",
    ["SC-SDLC-004"],
  )
}

pub fn build_sdlc_two_key_authorization_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcTwoKeyAuthorization,
    "C3I SDLC Two Key Authorization Agent",
    C3iSdlc,
    0,
    "#fractal-l0",
    Active,
    4224,
    32,
    Assert,
    "Two-key human-agent cryptographic authorization gating",
    "Authorization Gates",
    "Two-Key Review",
    "SIL-6 / Sovereign Core",
    ["SC-SDLC-005"],
  )
}

pub fn build_sdlc_governance_charter_auditor_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcGovernanceCharterAuditor,
    "C3I SDLC Governance Charter Auditor Agent",
    C3iSdlc,
    0,
    "#fractal-l0",
    Active,
    4256,
    32,
    Assert,
    "Audits monorepo commit charters against EV-cycle mandates",
    "Governance Audit",
    "Charter Audit",
    "SIL-5 / Safety Critical",
    ["SC-SDLC-006"],
  )
}

pub fn build_sdlc_license_compliance_checker_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcLicenseComplianceChecker,
    "C3I SDLC License Compliance Checker Agent",
    C3iSdlc,
    0,
    "#fractal-l0",
    Active,
    4288,
    32,
    Assert,
    "Verifies Zero-Muda and dependency license compatibility",
    "License Compliance",
    "Dependency Verification",
    "SIL-4 / High Availability",
    ["SC-MUDA-001"],
  )
}

pub fn build_sdlc_monorepo_boundary_enforcer_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcMonorepoBoundaryEnforcer,
    "C3I SDLC Monorepo Boundary Enforcer Agent",
    C3iSdlc,
    0,
    "#fractal-l0",
    Active,
    4320,
    32,
    Assert,
    "Enforces standalone Jujutsu monorepo structure and boundaries",
    "Monorepo Governance",
    "VCS Boundary Control",
    "SIL-5 / Safety Critical",
    ["SC-JJ-001"],
  )
}

pub fn build_sdlc_contract_code_generator_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcContractCodeGenerator,
    "C3I SDLC Contract Code Generator Agent",
    C3iSdlc,
    1,
    "#fractal-l1",
    Active,
    4352,
    32,
    Block,
    "Generates pure Gleam code with Gospel/Ortac invariants",
    "Contract Codegen",
    "Type Generation",
    "SIL-5 / Safety Critical",
    ["SC-SDLC-007"],
  )
}

pub fn build_sdlc_open_api_schema_generator_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcOpenApiSchemaGenerator,
    "C3I SDLC OpenAPI Schema Generator Agent",
    C3iSdlc,
    1,
    "#fractal-l1",
    Active,
    4384,
    32,
    Block,
    "Generates OpenAPI v3 specifications from Gleam API routes",
    "API Schema",
    "Interface Specification",
    "SIL-4 / High Availability",
    ["SC-SDLC-008"],
  )
}

pub fn build_sdlc_gospel_ortac_specification_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcGospelOrtacSpecification,
    "C3I SDLC Gospel Ortac Specification Agent",
    C3iSdlc,
    1,
    "#fractal-l1",
    Active,
    4416,
    32,
    Block,
    "Synthesizes Gospel contract specifications for OCaml",
    "Formal Contracts",
    "Contract Authoring",
    "SIL-5 / Safety Critical",
    ["SC-GOSPEL-001"],
  )
}

pub fn build_sdlc_ast_transformer_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcAstTransformer,
    "C3I SDLC AST Transformer Agent",
    C3iSdlc,
    1,
    "#fractal-l1",
    Active,
    4448,
    32,
    Block,
    "Transforms and normalizes Gleam/Erlang abstract syntax trees",
    "AST Transformation",
    "Compilation Stage",
    "SIL-4 / High Availability",
    ["SC-SDLC-009"],
  )
}

pub fn build_sdlc_type_inference_bridge_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcTypeInferenceBridge,
    "C3I SDLC Type Inference Bridge Agent",
    C3iSdlc,
    1,
    "#fractal-l1",
    Active,
    4480,
    32,
    Block,
    "Typechecks cross-language message boundaries",
    "Type Inference",
    "Cross-Language Boundary",
    "SIL-5 / Safety Critical",
    ["SC-SDLC-010"],
  )
}

pub fn build_sdlc_lexer_parser_generator_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcLexerParserGenerator,
    "C3I SDLC Lexer Parser Generator Agent",
    C3iSdlc,
    1,
    "#fractal-l1",
    Active,
    4512,
    32,
    Block,
    "Generates lexers and parsers for domain specific notations",
    "Parsing Synthesis",
    "Grammar Compilation",
    "SIL-4 / High Availability",
    ["SC-SDLC-011"],
  )
}

pub fn build_sdlc_bytecode_instruction_emitter_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcBytecodeInstructionEmitter,
    "C3I SDLC Bytecode Instruction Emitter Agent",
    C3iSdlc,
    1,
    "#fractal-l1",
    Active,
    4544,
    32,
    Block,
    "Emits deterministic ZigVM and BEAM instructions",
    "Bytecode Emission",
    "Codegen Runtime",
    "SIL-5 / Safety Critical",
    ["SC-SDLC-012"],
  )
}

pub fn build_sdlc_symbol_table_manager_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcSymbolTableManager,
    "C3I SDLC Symbol Table Manager Agent",
    C3iSdlc,
    1,
    "#fractal-l1",
    Active,
    4576,
    32,
    Block,
    "Manages scoped symbol tables and module resolutions",
    "Symbol Management",
    "Symbol Resolution",
    "SIL-4 / High Availability",
    ["SC-SDLC-013"],
  )
}

pub fn build_parameter_database_spec() -> AgentTypeSpec {
  build_spec_record(
    ParameterDatabase,
    "C3I SDLC Parameter Database Custodian Agent",
    C3iSdlc,
    2,
    "#fractal-l2",
    Queued,
    4608,
    32,
    Block,
    "Parameter updates and non-volatile slot commits",
    "Parameter Management",
    "Configuration & Storage",
    "SIL-3 / ACID Persistent",
    ["SC-FPP-004"],
  )
}

pub fn build_sdlc_static_analysis_auditor_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcStaticAnalysisAuditor,
    "C3I SDLC Static Analysis Auditor Agent",
    C3iSdlc,
    2,
    "#fractal-l2",
    Active,
    4640,
    32,
    Block,
    "Lints Gleam and Erlang code with zero warning policy",
    "Static Analysis",
    "Code Quality Linting",
    "SIL-4 / High Availability",
    ["SC-MUDA-001"],
  )
}

pub fn build_sdlc_design_system_figma_bridge_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcDesignSystemFigmaBridge,
    "C3I SDLC Design System Figma Bridge Agent",
    C3iSdlc,
    2,
    "#fractal-l2",
    Active,
    4672,
    32,
    Block,
    "Translates design tokens into pure Lustre components",
    "Design System",
    "UI Component Tokenization",
    "SIL-4 / High Availability",
    ["SC-UI-001"],
  )
}

pub fn build_sdlc_component_schema_synthesizer_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcComponentSchemaSynthesizer,
    "C3I SDLC Component Schema Synthesizer Agent",
    C3iSdlc,
    2,
    "#fractal-l2",
    Active,
    4704,
    32,
    Block,
    "Synthesizes A2UI component schemas",
    "Component Synthesis",
    "Schema Validation",
    "SIL-4 / High Availability",
    ["SC-A2UI-001"],
  )
}

pub fn build_sdlc_prop_binding_validator_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcPropBindingValidator,
    "C3I SDLC Prop Binding Validator Agent",
    C3iSdlc,
    2,
    "#fractal-l2",
    Active,
    4736,
    32,
    Block,
    "Validates component property bindings against domain models",
    "Property Validation",
    "Binding Verification",
    "SIL-4 / High Availability",
    ["SC-A2UI-002"],
  )
}

pub fn build_sdlc_widget_palette_registry_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcWidgetPaletteRegistry,
    "C3I SDLC Widget Palette Registry Agent",
    C3iSdlc,
    2,
    "#fractal-l2",
    Active,
    4768,
    32,
    Block,
    "Maintains registry of 233 trusted A2UI components",
    "Widget Registry",
    "Catalog Governance",
    "SIL-4 / High Availability",
    ["SC-A2UI-003"],
  )
}

pub fn build_sdlc_data_model_normalizer_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcDataModelNormalizer,
    "C3I SDLC Data Model Normalizer Agent",
    C3iSdlc,
    2,
    "#fractal-l2",
    Active,
    4800,
    32,
    Block,
    "Normalizes relational and graph data models into 3NF",
    "Data Modeling",
    "Schema Normalization",
    "SIL-4 / High Availability",
    ["SC-SDLC-014"],
  )
}

pub fn build_sdlc_interface_contract_binder_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcInterfaceContractBinder,
    "C3I SDLC Interface Contract Binder Agent",
    C3iSdlc,
    2,
    "#fractal-l2",
    Active,
    4832,
    32,
    Block,
    "Binds Wisp REST and Lustre WebUI to domain types",
    "Interface Binding",
    "Triple Interface Integration",
    "SIL-4 / High Availability",
    ["SC-GLM-UI-001"],
  )
}

pub fn build_mission_phase_hsm_spec() -> AgentTypeSpec {
  build_spec_record(
    MissionPhaseHsm,
    "C3I SDLC Mission Phase Orchestrator Agent",
    C3iSdlc,
    3,
    "#fractal-l3",
    Active,
    4864,
    32,
    Assert,
    "Spacecraft operational phase management via David Harel HSM",
    "Mission Phase Autonomy",
    "Phase Orchestration",
    "SIL-5 / Safety Critical",
    ["SC-FPP-003"],
  )
}

pub fn build_payload_science_spec() -> AgentTypeSpec {
  build_spec_record(
    PayloadScience,
    "C3I SDLC Payload Science Controller Agent",
    C3iSdlc,
    3,
    "#fractal-l3",
    Active,
    4896,
    32,
    Block,
    "Coordinates scientific instrument observation loops",
    "Payload Operations",
    "Instrument Scheduling",
    "SIL-4 / High Availability",
    ["SC-FPP-006"],
  )
}

pub fn build_sdlc_tool_registry_mcp_bridge_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcToolRegistryMcpBridge,
    "C3I SDLC Tool Registry MCP Bridge Agent",
    C3iSdlc,
    3,
    "#fractal-l3",
    Active,
    4928,
    32,
    Block,
    "Exposes Gleam functions as Model Context Protocol tools",
    "Tool Integration",
    "MCP Registry",
    "SIL-5 / Safety Critical",
    ["SC-MCP-001"],
  )
}

pub fn build_sdlc_hierarchical_state_composer_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcHierarchicalStateComposer,
    "C3I SDLC Hierarchical State Composer Agent",
    C3iSdlc,
    3,
    "#fractal-l3",
    Active,
    4960,
    32,
    Block,
    "Composes David Harel nested state charts",
    "State Machine Design",
    "HSM Composition",
    "SIL-5 / Safety Critical",
    ["SC-FPP-007"],
  )
}

pub fn build_sdlc_lca_transition_resolver_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcLcaTransitionResolver,
    "C3I SDLC LCA Transition Resolver Agent",
    C3iSdlc,
    3,
    "#fractal-l3",
    Active,
    4992,
    32,
    Block,
    "Calculates Lowest Common Ancestor state transitions",
    "State Machine Math",
    "LCA Resolution",
    "SIL-5 / Safety Critical",
    ["SC-FPP-008"],
  )
}

pub fn build_sdlc_guard_action_synthesizer_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcGuardActionSynthesizer,
    "C3I SDLC Guard Action Synthesizer Agent",
    C3iSdlc,
    3,
    "#fractal-l3",
    Active,
    5024,
    32,
    Block,
    "Synthesizes pure guard predicates and entry/exit actions",
    "Action Synthesis",
    "Guard Logic",
    "SIL-5 / Safety Critical",
    ["SC-FPP-009"],
  )
}

pub fn build_sdlc_orthogonal_region_coordinator_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcOrthogonalRegionCoordinator,
    "C3I SDLC Orthogonal Region Coordinator Agent",
    C3iSdlc,
    3,
    "#fractal-l3",
    Active,
    5056,
    32,
    Block,
    "Coordinates concurrent orthogonal state machine regions",
    "Concurrency Modeling",
    "Region Synchronization",
    "SIL-5 / Safety Critical",
    ["SC-FPP-010"],
  )
}

pub fn build_sdlc_signal_dispatch_matrix_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcSignalDispatchMatrix,
    "C3I SDLC Signal Dispatch Matrix Agent",
    C3iSdlc,
    3,
    "#fractal-l3",
    Active,
    5088,
    32,
    Block,
    "Compiles event signal dispatch lookup tables",
    "Signal Dispatch",
    "Event Routing",
    "SIL-4 / High Availability",
    ["SC-FPP-011"],
  )
}

pub fn build_appup_hot_reload_coordinator_spec() -> AgentTypeSpec {
  build_spec_record(
    AppupHotReloadCoordinator,
    "C3I SDLC Appup Hot Reload Coordinator Agent",
    C3iSdlc,
    4,
    "#fractal-l4",
    Active,
    5120,
    32,
    Assert,
    "Orchestrates BEAM appup instruction sets and state upgrades",
    "Runtime Upgrades",
    "Hot Code Reload",
    "SIL-5 / Safety Critical",
    ["SC-OTP-001"],
  )
}

pub fn build_sdlc_release_packaging_orchestrator_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcReleasePackagingOrchestrator,
    "C3I SDLC Release Packaging Orchestrator Agent",
    C3iSdlc,
    4,
    "#fractal-l4",
    Active,
    5152,
    32,
    Assert,
    "Builds standalone reproducible releases",
    "Packaging & Release",
    "Artifact Assembly",
    "SIL-5 / Safety Critical",
    ["SC-SDLC-015"],
  )
}

pub fn build_sdlc_session_memory_replay_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcSessionMemoryReplay,
    "C3I SDLC Session Memory Replay Agent",
    C3iSdlc,
    4,
    "#fractal-l4",
    Active,
    5184,
    32,
    Block,
    "Replays agent session interactions from SQLite",
    "Session Memory",
    "Interaction Replay",
    "SIL-4 / High Availability",
    ["SC-SDLC-016"],
  )
}

pub fn build_sdlc_fork_join_parallel_branch_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcForkJoinParallelBranch,
    "C3I SDLC Fork Join Parallel Branch Agent",
    C3iSdlc,
    4,
    "#fractal-l4",
    Active,
    5216,
    32,
    Block,
    "Orchestrates parallel workflow branches with barriers",
    "Workflow Parallelism",
    "Fork-Join Execution",
    "SIL-4 / High Availability",
    ["SC-ADK-011"],
  )
}

pub fn build_sdlc_feature_slice_composer_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcFeatureSliceComposer,
    "C3I SDLC Feature Slice Composer Agent",
    C3iSdlc,
    4,
    "#fractal-l4",
    Active,
    5248,
    32,
    Block,
    "Composes atomic feature slices with named laws",
    "Feature Slicing",
    "Algebraic Slices",
    "SIL-5 / Safety Critical",
    ["SC-SDLC-017"],
  )
}

pub fn build_sdlc_api_endpoint_packager_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcApiEndpointPackager,
    "C3I SDLC API Endpoint Packager Agent",
    C3iSdlc,
    4,
    "#fractal-l4",
    Active,
    5280,
    32,
    Block,
    "Packages Wisp REST endpoints with OTel span contexts",
    "API Packaging",
    "Endpoint Serialization",
    "SIL-4 / High Availability",
    ["SC-SDLC-018"],
  )
}

pub fn build_sdlc_artifact_tarball_bundler_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcArtifactTarballBundler,
    "C3I SDLC Artifact Tarball Bundler Agent",
    C3iSdlc,
    4,
    "#fractal-l4",
    Active,
    5312,
    32,
    Block,
    "Bundles deterministic binaries with SHA-256 digests",
    "Artifact Bundling",
    "Digest Verification",
    "SIL-5 / Safety Critical",
    ["SC-SDLC-019"],
  )
}

pub fn build_sdlc_semantic_version_manager_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcSemanticVersionManager,
    "C3I SDLC Semantic Version Manager Agent",
    C3iSdlc,
    4,
    "#fractal-l4",
    Active,
    5344,
    32,
    Block,
    "Calculates semver bumps based on API signature diffs",
    "Version Governance",
    "Semver Calculation",
    "SIL-4 / High Availability",
    ["SC-SDLC-020"],
  )
}

pub fn build_km_sync_spec() -> AgentTypeSpec {
  build_spec_record(
    KmSync,
    "C3I SDLC Knowledge Management Sync Agent",
    C3iSdlc,
    5,
    "#fractal-l5",
    Active,
    5376,
    32,
    Drop,
    "Synchronizes documentation, wiki articles, and ZK records",
    "Knowledge Management",
    "KM Sync",
    "SIL-4 / High Availability",
    ["SC-KM-001"],
  )
}

pub fn build_slm_bif_inference_spec() -> AgentTypeSpec {
  build_spec_record(
    SlmBifInference,
    "C3I SDLC Small Language Model BIF Inference Agent",
    C3iSdlc,
    5,
    "#fractal-l5",
    Active,
    5408,
    32,
    Block,
    "Runs deterministic local SLM inference over BIF interfaces",
    "Inference BIF",
    "Local SLM Dispatch",
    "SIL-4 / High Availability",
    ["SC-MAX-001"],
  )
}

pub fn build_fast_pattern_filter_spec() -> AgentTypeSpec {
  build_spec_record(
    FastPatternFilter,
    "C3I SDLC Fast Pattern Filter Agent",
    C3iSdlc,
    5,
    "#fractal-l5",
    Active,
    5440,
    32,
    Drop,
    "Evaluates high-speed regex and bitstring match patterns",
    "Pattern Matching",
    "Bitstring Filter",
    "SIL-4 / High Availability",
    ["SC-SDLC-021"],
  )
}

pub fn build_sdlc_graph_workflow_orchestrator_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcGraphWorkflowOrchestrator,
    "C3I SDLC Graph Workflow Orchestrator Agent",
    C3iSdlc,
    5,
    "#fractal-l5",
    Active,
    5472,
    32,
    Assert,
    "Executes DAG and cyclical agent workflows",
    "Graph Execution",
    "Workflow Coordination",
    "SIL-5 / Safety Critical",
    ["SC-ADK-001"],
  )
}

pub fn build_sdlc_prompt_template_injector_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcPromptTemplateInjector,
    "C3I SDLC Prompt Template Injector Agent",
    C3iSdlc,
    5,
    "#fractal-l5",
    Active,
    5504,
    32,
    Block,
    "Injects system instructions and dynamic variables into prompts",
    "Prompt Templates",
    "Instruction Composition",
    "SIL-4 / High Availability",
    ["SC-ADK-009"],
  )
}

pub fn build_sdlc_state_graph_cycle_resolver_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcStateGraphCycleResolver,
    "C3I SDLC State Graph Cycle Resolver Agent",
    C3iSdlc,
    5,
    "#fractal-l5",
    Active,
    5536,
    32,
    Assert,
    "Resolves recursion limits and termination conditions",
    "Graph Resolution",
    "Cycle Resolution",
    "SIL-5 / Safety Critical",
    ["SC-ADK-010"],
  )
}

pub fn build_sdlc_denotational_semantics_mapper_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcDenotationalSemanticsMapper,
    "C3I SDLC Denotational Semantics Mapper Agent",
    C3iSdlc,
    5,
    "#fractal-l5",
    Active,
    5568,
    32,
    Block,
    "Maps intent payloads into mathematical semantics",
    "Denotational Design",
    "Intent Semantics",
    "SIL-5 / Safety Critical",
    ["SC-DMC-002"],
  )
}

pub fn build_sdlc_template_renderer_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcTemplateRenderer,
    "C3I SDLC Template Renderer Agent",
    C3iSdlc,
    5,
    "#fractal-l5",
    Active,
    5600,
    32,
    Block,
    "Renders isomorphic HTML, JSON, and ANSI text templates",
    "Template Rendering",
    "Isomorphic Views",
    "SIL-4 / High Availability",
    ["SC-UI-002"],
  )
}

pub fn build_sdlc_documentation_transclusion_sync_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcDocumentationTransclusionSync,
    "C3I SDLC Documentation Transclusion Sync Agent",
    C3iSdlc,
    6,
    "#fractal-l6",
    Active,
    5632,
    32,
    Block,
    "Enforces [[wiki:...]] and [[zk:...]] transclusion links",
    "Documentation Sync",
    "Transclusion Linking",
    "SIL-4 / High Availability",
    ["SC-KM-002"],
  )
}

pub fn build_sdlc_a2a_multi_agent_delegation_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcA2aMultiAgentDelegation,
    "C3I SDLC A2A Multi Agent Delegation Agent",
    C3iSdlc,
    6,
    "#fractal-l6",
    Active,
    5664,
    32,
    Block,
    "Manages agent-to-agent delegation protocols",
    "Multi-Agent Delegation",
    "A2A Messaging",
    "SIL-5 / Safety Critical",
    ["SC-ADK-003"],
  )
}

pub fn build_sdlc_notion_living_ontology_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcNotionLivingOntology,
    "C3I SDLC Notion Living Ontology Agent",
    C3iSdlc,
    6,
    "#fractal-l6",
    Active,
    5696,
    32,
    Block,
    "Synchronizes AST property schemas with Notion databases",
    "Living Ontology",
    "External Sync",
    "SIL-4 / High Availability",
    ["SC-ONTO-003"],
  )
}

pub fn build_sdlc_swarm_workflow_scheduler_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcSwarmWorkflowScheduler,
    "C3I SDLC Swarm Workflow Scheduler Agent",
    C3iSdlc,
    6,
    "#fractal-l6",
    Active,
    5728,
    32,
    Assert,
    "Schedules cooperative multi-agent task pipelines",
    "Swarm Scheduling",
    "Workflow Allocation",
    "SIL-5 / Safety Critical",
    ["SC-SDLC-022"],
  )
}

pub fn build_sdlc_agent_interchange_protocol_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcAgentInterchangeProtocol,
    "C3I SDLC Agent Interchange Protocol Agent",
    C3iSdlc,
    6,
    "#fractal-l6",
    Active,
    5760,
    32,
    Block,
    "Serializes typed JSON-RPC messages across agent boundaries",
    "Agent Protocols",
    "Message Serialization",
    "SIL-5 / Safety Critical",
    ["SC-SDLC-023"],
  )
}

pub fn build_sdlc_dialogue_turn_orchestrator_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcDialogueTurnOrchestrator,
    "C3I SDLC Dialogue Turn Orchestrator Agent",
    C3iSdlc,
    6,
    "#fractal-l6",
    Active,
    5792,
    32,
    Block,
    "Manages conversation turns, context windows, and backoff",
    "Dialogue Management",
    "Turn Orchestration",
    "SIL-4 / High Availability",
    ["SC-SDLC-024"],
  )
}

pub fn build_sdlc_context_window_manager_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcContextWindowManager,
    "C3I SDLC Context Window Manager Agent",
    C3iSdlc,
    6,
    "#fractal-l6",
    Active,
    5824,
    32,
    Drop,
    "Prunes and summarizes long conversation trajectories",
    "Context Management",
    "Token Pruning",
    "SIL-4 / High Availability",
    ["SC-SDLC-025"],
  )
}

pub fn build_sdlc_collaborative_task_router_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcCollaborativeTaskRouter,
    "C3I SDLC Collaborative Task Router Agent",
    C3iSdlc,
    6,
    "#fractal-l6",
    Active,
    5856,
    32,
    Assert,
    "Routes specialized coding tasks to optimal agent roles",
    "Task Routing",
    "Role Dispatch",
    "SIL-5 / Safety Critical",
    ["SC-SDLC-026"],
  )
}

pub fn build_sdlc_algebraic_atlas_router_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcAlgebraicAtlasRouter,
    "C3I SDLC Algebraic Atlas Router Agent",
    C3iSdlc,
    7,
    "#fractal-l7",
    Active,
    5888,
    32,
    Assert,
    "Routes architectural morphisms across atlas layers",
    "Algebraic Atlas",
    "Category Morphisms",
    "SIL-5 / Safety Critical",
    ["SC-ATLAS-001"],
  )
}

pub fn build_sdlc_route_table_html_algebra_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcRouteTableHtmlAlgebra,
    "C3I SDLC Route Table HTML Algebra Agent",
    C3iSdlc,
    7,
    "#fractal-l7",
    Active,
    5920,
    32,
    Block,
    "Maintains top-level HTML route tables and navigation",
    "Web Navigation",
    "Route Algebra",
    "SIL-4 / High Availability",
    ["SC-ROUTE-001"],
  )
}

pub fn build_living_meta_evolution_spec() -> AgentTypeSpec {
  build_spec_record(
    LivingMetaEvolution,
    "C3I SDLC Living Meta Evolution Agent",
    C3iSdlc,
    7,
    "#fractal-l7",
    Active,
    5952,
    32,
    Assert,
    "Governs continuous biomorphic adaptation loops",
    "Meta Evolution",
    "Adaptive Loops",
    "SIL-6 / Sovereign Core",
    ["SC-FPP-012"],
  )
}

pub fn build_dynamic_agent_bytecode_synthesizer_spec() -> AgentTypeSpec {
  build_spec_record(
    DynamicAgentBytecodeSynthesizer,
    "C3I SDLC Dynamic Agent Bytecode Synthesizer Agent",
    C3iSdlc,
    7,
    "#fractal-l7",
    Active,
    5984,
    32,
    Assert,
    "Compiles dynamic agent logic directly to BEAM bytecode",
    "Bytecode Synthesis",
    "Dynamic Compilation",
    "SIL-5 / Safety Critical",
    ["SC-FPP-013"],
  )
}

pub fn build_sdlc_evolutionary_loop_governor_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcEvolutionaryLoopGovernor,
    "C3I SDLC Evolutionary Loop Governor Agent",
    C3iSdlc,
    7,
    "#fractal-l7",
    Active,
    6016,
    32,
    Assert,
    "Governs the 5-tier fractal lifecycle (Operation to Pin)",
    "Lifecycle Governance",
    "OODA Lifecycle",
    "SIL-6 / Sovereign Core",
    ["SC-SDLC-SRE-001"],
  )
}

pub fn build_sdlc_cross_repository_synchronizer_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcCrossRepositorySynchronizer,
    "C3I SDLC Cross Repository Synchronizer Agent",
    C3iSdlc,
    7,
    "#fractal-l7",
    Active,
    6048,
    32,
    Assert,
    "Synchronizes pinned dependencies across external sources",
    "Repository Sync",
    "Pin Verification",
    "SIL-5 / Safety Critical",
    ["SC-SDLC-027"],
  )
}

pub fn build_sdlc_continuous_deployment_pipeline_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcContinuousDeploymentPipeline,
    "C3I SDLC Continuous Deployment Pipeline Agent",
    C3iSdlc,
    7,
    "#fractal-l7",
    Active,
    6080,
    32,
    Assert,
    "Executes zero-downtime rolling upgrades on Kubernetes",
    "Deployment Pipeline",
    "Cluster Rolling Updates",
    "SIL-5 / Safety Critical",
    ["SC-OPS-001"],
  )
}

pub fn build_sdlc_artifact_registry_mirror_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcArtifactRegistryMirror,
    "C3I SDLC Artifact Registry Mirror Agent",
    C3iSdlc,
    7,
    "#fractal-l7",
    Active,
    6112,
    32,
    Assert,
    "Maintains immutable checksum mirrors of all release artifacts",
    "Artifact Mirror",
    "Immutable Storage",
    "SIL-5 / Safety Critical",
    ["SC-SDLC-028"],
  )
}

pub fn build_sre_plugin_policy_guardrail_spec() -> AgentTypeSpec {
  build_spec_record(
    SrePluginPolicyGuardrail,
    "C3I SRE Plugin Policy Guardrail Agent",
    C3iSre,
    0,
    "#fractal-l0",
    Active,
    6144,
    32,
    Assert,
    "Prevents unauthorized tool additions or schema mutations",
    "Policy Enforcement",
    "Plugin Security",
    "SIL-6 / Sovereign Core",
    ["SC-SRE-001"],
  )
}

pub fn build_sre_rete_fail_closed_admission_spec() -> AgentTypeSpec {
  build_spec_record(
    SreReteFailClosedAdmission,
    "C3I SRE Rete Fail Closed Admission Agent",
    C3iSre,
    0,
    "#fractal-l0",
    Active,
    6176,
    32,
    Assert,
    "Rete-UL forward chaining rule engine with fail-closed veto",
    "Rule Inference",
    "Admission Control",
    "SIL-6 / Sovereign Core",
    ["SC-RETE-001"],
  )
}

pub fn build_sre_stpa_safety_controller_spec() -> AgentTypeSpec {
  build_spec_record(
    SreStpaSafetyController,
    "C3I SRE STPA Safety Controller Agent",
    C3iSre,
    0,
    "#fractal-l0",
    Active,
    6208,
    32,
    Assert,
    "Monitors STPA safety control structure and prevents UCAs",
    "STPA Safety",
    "Safety Control Structure",
    "SIL-6 / Sovereign Core",
    ["SC-STPA-001"],
  )
}

pub fn build_sre_content_safety_sanitizer_spec() -> AgentTypeSpec {
  build_spec_record(
    SreContentSafetySanitizer,
    "C3I SRE Content Safety Sanitizer Agent",
    C3iSre,
    0,
    "#fractal-l0",
    Active,
    6240,
    32,
    Assert,
    "Prompt injection scrubber, PII redactor, and secret byte filter",
    "Security & Safety",
    "Zero-Trust Content Scrubbing",
    "SIL-6 / Sovereign Core",
    ["SC-ADK-018"],
  )
}

pub fn build_sre_emergency_jidoka_interlock_spec() -> AgentTypeSpec {
  build_spec_record(
    SreEmergencyJidokaInterlock,
    "C3I SRE Emergency Jidoka Interlock Agent",
    C3iSre,
    0,
    "#fractal-l0",
    Active,
    6272,
    32,
    Assert,
    "Toyota Jidoka auto-stop trigger halting execution upon defect",
    "Operational Safety",
    "Emergency Stop",
    "SIL-6 / Sovereign Core",
    ["SC-SRE-002"],
  )
}

pub fn build_sre_constitutional_quorum_watcher_spec() -> AgentTypeSpec {
  build_spec_record(
    SreConstitutionalQuorumWatcher,
    "C3I SRE Constitutional Quorum Watcher Agent",
    C3iSre,
    0,
    "#fractal-l0",
    Active,
    6304,
    32,
    Assert,
    "Enforces 2oo3 constitutional multi-vendor agent consensus",
    "Consensus Quorum",
    "Constitutional Consensus",
    "SIL-6 / Sovereign Core",
    ["SC-SRE-003"],
  )
}

pub fn build_sre_fail_closed_circuit_governor_spec() -> AgentTypeSpec {
  build_spec_record(
    SreFailClosedCircuitGovernor,
    "C3I SRE Fail Closed Circuit Governor Agent",
    C3iSre,
    0,
    "#fractal-l0",
    Active,
    6336,
    32,
    Assert,
    "Trips master circuit breakers when anomaly rates exceed threshold",
    "Circuit Governance",
    "Fail-Closed Protection",
    "SIL-6 / Sovereign Core",
    ["SC-SRE-004"],
  )
}

pub fn build_sre_zero_trust_admission_filter_spec() -> AgentTypeSpec {
  build_spec_record(
    SreZeroTrustAdmissionFilter,
    "C3I SRE Zero Trust Admission Filter Agent",
    C3iSre,
    0,
    "#fractal-l0",
    Active,
    6368,
    32,
    Assert,
    "Traps NUL bytes and raw SQL injections at the ingress port",
    "Zero-Trust Security",
    "Payload Sanitization",
    "SIL-6 / Sovereign Core",
    ["SC-HERMES-001"],
  )
}

pub fn build_storage_custodian_spec() -> AgentTypeSpec {
  build_spec_record(
    StorageCustodian,
    "C3I SRE Storage Custodian Agent",
    C3iSre,
    1,
    "#fractal-l1",
    Active,
    6400,
    32,
    Block,
    "Guards non-volatile persistent storage sectors",
    "Storage Custody",
    "Persistence Integrity",
    "SIL-4 / High Availability",
    ["SC-FPP-014"],
  )
}

pub fn build_deterministic_reduction_scheduler_spec() -> AgentTypeSpec {
  build_spec_record(
    DeterministicReductionScheduler,
    "C3I SRE Deterministic Reduction Scheduler Agent",
    C3iSre,
    1,
    "#fractal-l1",
    Active,
    6432,
    32,
    Block,
    "Allocates deterministic BEAM reduction budgets per turn",
    "Scheduler Control",
    "Reduction Budgeting",
    "SIL-5 / Safety Critical",
    ["SC-SRE-005"],
  )
}

pub fn build_linear_arena_reclaimer_spec() -> AgentTypeSpec {
  build_spec_record(
    LinearArenaReclaimer,
    "C3I SRE Linear Arena Reclaimer Agent",
    C3iSre,
    1,
    "#fractal-l1",
    Active,
    6464,
    32,
    Block,
    "Reclaims temporary arena allocators without memory leaks",
    "Memory Management",
    "Arena Reclamation",
    "SIL-5 / Safety Critical",
    ["SC-SRE-006"],
  )
}

pub fn build_sre_cpu_budget_governor_spec() -> AgentTypeSpec {
  build_spec_record(
    SreCpuBudgetGovernor,
    "C3I SRE CPU Budget Governor Agent",
    C3iSre,
    1,
    "#fractal-l1",
    Active,
    6496,
    32,
    Block,
    "Enforces bounded CPU time per agent execution slice",
    "Resource Management",
    "CPU Budgeting",
    "SIL-5 / Safety Critical",
    ["SC-SRE-007"],
  )
}

pub fn build_sre_sandboxed_tool_isolation_spec() -> AgentTypeSpec {
  build_spec_record(
    SreSandboxedToolIsolation,
    "C3I SRE Sandboxed Tool Isolation Agent",
    C3iSre,
    1,
    "#fractal-l1",
    Active,
    6528,
    32,
    Block,
    "Sandboxes external tool invocations in isolated OS processes",
    "Process Isolation",
    "Sandboxed Execution",
    "SIL-6 / Sovereign Core",
    ["SC-ADK-019"],
  )
}

pub fn build_sre_memory_leak_detector_spec() -> AgentTypeSpec {
  build_spec_record(
    SreMemoryLeakDetector,
    "C3I SRE Memory Leak Detector Agent",
    C3iSre,
    1,
    "#fractal-l1",
    Active,
    6560,
    32,
    Block,
    "Detects monotonic memory growth and actor heap expansion",
    "Heap Monitoring",
    "Memory Leak Prevention",
    "SIL-5 / Safety Critical",
    ["SC-SRE-008"],
  )
}

pub fn build_sre_page_fault_rate_controller_spec() -> AgentTypeSpec {
  build_spec_record(
    SrePageFaultRateController,
    "C3I SRE Page Fault Rate Controller Agent",
    C3iSre,
    1,
    "#fractal-l1",
    Active,
    6592,
    32,
    Drop,
    "Monitors OS virtual memory page fault rates and thrashing",
    "VFS Monitoring",
    "Page Fault Control",
    "SIL-4 / High Availability",
    ["SC-SRE-009"],
  )
}

pub fn build_sre_garbage_collection_pacer_spec() -> AgentTypeSpec {
  build_spec_record(
    SreGarbageCollectionPacer,
    "C3I SRE Garbage Collection Pacer Agent",
    C3iSre,
    1,
    "#fractal-l1",
    Active,
    6624,
    32,
    Drop,
    "Paces BEAM major GC sweeps to avoid latency spikes",
    "GC Optimization",
    "Latency Pacing",
    "SIL-4 / High Availability",
    ["SC-SRE-010"],
  )
}

pub fn build_lockless_hamt_storage_spec() -> AgentTypeSpec {
  build_spec_record(
    LocklessHamtStorage,
    "C3I SRE Lockless HAMT Storage Agent",
    C3iSre,
    2,
    "#fractal-l2",
    Active,
    6656,
    32,
    Drop,
    "Maintains lockless Hash Array Mapped Trie storage structures",
    "Storage Structures",
    "HAMT Management",
    "SIL-4 / High Availability",
    ["SC-SRE-011"],
  )
}

pub fn build_tagged_pointer_guard_spec() -> AgentTypeSpec {
  build_spec_record(
    TaggedPointerGuard,
    "C3I SRE Tagged Pointer Guard Agent",
    C3iSre,
    2,
    "#fractal-l2",
    Active,
    6688,
    32,
    Assert,
    "Enforces strict term representation tag bits in BEAM VM",
    "Memory Safety",
    "Tagged Pointer Audit",
    "SIL-6 / Sovereign Core",
    ["SC-SRE-012"],
  )
}

pub fn build_hierarchical_timer_wheel_spec() -> AgentTypeSpec {
  build_spec_record(
    HierarchicalTimerWheel,
    "C3I SRE Hierarchical Timer Wheel Agent",
    C3iSre,
    2,
    "#fractal-l2",
    Active,
    6720,
    32,
    Drop,
    "Sub-millisecond cascaded timer wheel scheduler",
    "Timer Scheduling",
    "Hierarchical Wheels",
    "SIL-4 / High Availability",
    ["SC-SRE-013"],
  )
}

pub fn build_sre_freshness_monitor_spec() -> AgentTypeSpec {
  build_spec_record(
    SreFreshnessMonitor,
    "C3I SRE Freshness Monitor Agent",
    C3iSre,
    2,
    "#fractal-l2",
    Active,
    6752,
    32,
    Drop,
    "Verifies dead-mans-switch freshness across all 35 telemetry tabs",
    "Freshness Monitoring",
    "Liveness Detection",
    "SIL-5 / Safety Critical",
    ["SC-SRE-014"],
  )
}

pub fn build_sre_open_telemetry_span_tracer_spec() -> AgentTypeSpec {
  build_spec_record(
    SreOpenTelemetrySpanTracer,
    "C3I SRE OpenTelemetry Span Tracer Agent",
    C3iSre,
    2,
    "#fractal-l2",
    Active,
    6784,
    32,
    Drop,
    "Publishes 128-bit W3C OTel spans over Zenoh mesh",
    "Distributed Tracing",
    "OTel Span Emission",
    "SIL-4 / High Availability",
    ["SC-OTEL-001"],
  )
}

pub fn build_sre_dead_mans_switch_watchdog_spec() -> AgentTypeSpec {
  build_spec_record(
    SreDeadMansSwitchWatchdog,
    "C3I SRE Dead Mans Switch Watchdog Agent",
    C3iSre,
    2,
    "#fractal-l2",
    Active,
    6816,
    32,
    Assert,
    "Dead-mans-switch freshness heartbeat monitor and failover trigger",
    "Liveness & Health",
    "Dead-Mans Switch",
    "SIL-5 / Safety Critical",
    ["SC-SRE-002"],
  )
}

pub fn build_sre_heartbeat_liveness_cluster_spec() -> AgentTypeSpec {
  build_spec_record(
    SreHeartbeatLivenessCluster,
    "C3I SRE Heartbeat Liveness Cluster Agent",
    C3iSre,
    2,
    "#fractal-l2",
    Active,
    6848,
    32,
    Drop,
    "Monitors node heartbeat clusters across the Tailnet",
    "Cluster Liveness",
    "Heartbeat Tracking",
    "SIL-4 / High Availability",
    ["SC-SRE-015"],
  )
}

pub fn build_sre_health_entropy_aggregator_spec() -> AgentTypeSpec {
  build_spec_record(
    SreHealthEntropyAggregator,
    "C3I SRE Health Entropy Aggregator Agent",
    C3iSre,
    2,
    "#fractal-l2",
    Active,
    6880,
    32,
    Drop,
    "Calculates whole-system Shannon entropy H >= 2.5b",
    "Entropy Aggregation",
    "Health Statistics",
    "SIL-5 / Safety Critical",
    ["SC-MATH-001"],
  )
}

pub fn build_crash_wal_replay_spec() -> AgentTypeSpec {
  build_spec_record(
    CrashWalReplay,
    "C3I SRE Crash WAL Replay Agent",
    C3iSre,
    3,
    "#fractal-l3",
    Active,
    6912,
    32,
    Assert,
    "Recovers state from SQLite Write-Ahead Log after abnormal exit",
    "State Recovery",
    "Crash WAL Replay",
    "SIL-5 / Safety Critical",
    ["SC-SRE-016"],
  )
}

pub fn build_sre_sa_plan_task_leaser_spec() -> AgentTypeSpec {
  build_spec_record(
    SreSaPlanTaskLeaser,
    "C3I SRE SA Plan Task Leaser Agent",
    C3iSre,
    3,
    "#fractal-l3",
    Active,
    6944,
    32,
    Block,
    "Manages atomic plan task leases with single-writer invariants",
    "Task Leasing",
    "Single-Writer Leases",
    "SIL-5 / Safety Critical",
    ["SC-SRE-017"],
  )
}

pub fn build_sre_database_actor_wal_serializer_spec() -> AgentTypeSpec {
  build_spec_record(
    SreDatabaseActorWalSerializer,
    "C3I SRE Database Actor WAL Serializer Agent",
    C3iSre,
    3,
    "#fractal-l3",
    Active,
    6976,
    32,
    Block,
    "Serializes ledger transactions to SQLite WAL with fsync",
    "Persistence Engine",
    "WAL Serialization",
    "SIL-5 / Safety Critical",
    ["SC-SRE-018"],
  )
}

pub fn build_sre_mailbox_backpressure_controller_spec() -> AgentTypeSpec {
  build_spec_record(
    SreMailboxBackpressureController,
    "C3I SRE Mailbox Backpressure Controller Agent",
    C3iSre,
    3,
    "#fractal-l3",
    Active,
    7008,
    32,
    Drop,
    "Monitors actor mailbox depths and signals upstream backpressure",
    "Backpressure Control",
    "Mailbox Regulation",
    "SIL-5 / Safety Critical",
    ["SC-SRE-019"],
  )
}

pub fn build_sre_actor_deadlock_resolver_spec() -> AgentTypeSpec {
  build_spec_record(
    SreActorDeadlockResolver,
    "C3I SRE Actor Deadlock Resolver Agent",
    C3iSre,
    3,
    "#fractal-l3",
    Active,
    7040,
    32,
    Assert,
    "Detects cyclical message waiting loops and resolves deadlocks",
    "Deadlock Resolution",
    "Cycle Breaking",
    "SIL-5 / Safety Critical",
    ["SC-SRE-020"],
  )
}

pub fn build_sre_message_queue_drainer_spec() -> AgentTypeSpec {
  build_spec_record(
    SreMessageQueueDrainer,
    "C3I SRE Message Queue Drainer Agent",
    C3iSre,
    3,
    "#fractal-l3",
    Active,
    7072,
    32,
    Drop,
    "Safely drains overflowing message queues during shutdown",
    "Queue Draining",
    "Orderly Teardown",
    "SIL-4 / High Availability",
    ["SC-SRE-021"],
  )
}

pub fn build_sre_priority_queue_fair_scheduler_spec() -> AgentTypeSpec {
  build_spec_record(
    SrePriorityQueueFairScheduler,
    "C3I SRE Priority Queue Fair Scheduler Agent",
    C3iSre,
    3,
    "#fractal-l3",
    Active,
    7104,
    32,
    Block,
    "Ensures fair starvation-free scheduling of priority tasks",
    "Priority Scheduling",
    "Fair Execution",
    "SIL-4 / High Availability",
    ["SC-SRE-022"],
  )
}

pub fn build_sre_transaction_saga_compensator_spec() -> AgentTypeSpec {
  build_spec_record(
    SreTransactionSagaCompensator,
    "C3I SRE Transaction Saga Compensator Agent",
    C3iSre,
    3,
    "#fractal-l3",
    Active,
    7136,
    32,
    Assert,
    "Executes compensation actions for aborted multi-step sagas",
    "Saga Compensation",
    "Transaction Recovery",
    "SIL-5 / Safety Critical",
    ["SC-SRE-023"],
  )
}

pub fn build_sre_sentinel_spec() -> AgentTypeSpec {
  build_spec_record(
    SreSentinel,
    "C3I SRE Sentinel Health & Circuit Breaker Agent",
    C3iSre,
    4,
    "#fractal-l4",
    Active,
    7168,
    32,
    Assert,
    "Continuous 35-page health sentinel with auto-quarantine",
    "Health Sentinel",
    "Quarantine Supervision",
    "SIL-5 / Safety Critical",
    ["SC-SRE-024"],
  )
}

pub fn build_cybernetic_immune_spec() -> AgentTypeSpec {
  build_spec_record(
    CyberneticImmune,
    "C3I SRE Cybernetic Immune Self-Healing Agent",
    C3iSre,
    4,
    "#fractal-l4",
    Active,
    7200,
    32,
    Assert,
    "Synthesizes antibodies and triggers hot-code patch applications",
    "Cybernetic Immunity",
    "Autonomous Healing",
    "SIL-5 / Safety Critical",
    ["SC-SRE-025"],
  )
}

pub fn build_sre_lyapunov_trend_detector_spec() -> AgentTypeSpec {
  build_spec_record(
    SreLyapunovTrendDetector,
    "C3I SRE Lyapunov Trend Detector Agent",
    C3iSre,
    4,
    "#fractal-l4",
    Active,
    7232,
    32,
    Drop,
    "Evaluates windowed Lyapunov stability d(H)/dt to detect cascades",
    "Stability Analysis",
    "Cascade Detection",
    "SIL-5 / Safety Critical",
    ["SC-SRE-026"],
  )
}

pub fn build_sre_chaos_fault_injector_spec() -> AgentTypeSpec {
  build_spec_record(
    SreChaosFaultInjector,
    "C3I SRE Chaos Fault Injector Agent",
    C3iSre,
    4,
    "#fractal-l4",
    Active,
    7264,
    32,
    Assert,
    "Injects controlled network drops and actor crashes to test resilience",
    "Chaos Engineering",
    "Fault Injection",
    "SIL-5 / Safety Critical",
    ["SC-SRE-027"],
  )
}

pub fn build_sre_runner_lifecycle_hook_supervisor_spec() -> AgentTypeSpec {
  build_spec_record(
    SreRunnerLifecycleHookSupervisor,
    "C3I SRE Runner Lifecycle Hook Supervisor Agent",
    C3iSre,
    4,
    "#fractal-l4",
    Active,
    7296,
    32,
    Assert,
    "Supervises agent pre-execution and post-execution lifecycle hooks",
    "Lifecycle Hooks",
    "Hook Supervision",
    "SIL-5 / Safety Critical",
    ["SC-SRE-028"],
  )
}

pub fn build_sre_time_travel_state_rollback_spec() -> AgentTypeSpec {
  build_spec_record(
    SreTimeTravelStateRollback,
    "C3I SRE Time Travel State Rollback Agent",
    C3iSre,
    4,
    "#fractal-l4",
    Active,
    7328,
    32,
    Assert,
    "RFC-6902 reverse patch generator restoring exact state snapshots",
    "State Rollback",
    "Time-Travel Recovery",
    "SIL-5 / Safety Critical",
    ["SC-ADK-015"],
  )
}

pub fn build_sre_token_quota_rate_limiter_spec() -> AgentTypeSpec {
  build_spec_record(
    SreTokenQuotaRateLimiter,
    "C3I SRE Token Quota Rate Limiter Agent",
    C3iSre,
    4,
    "#fractal-l4",
    Active,
    7360,
    32,
    Block,
    "Token consumption budget limiter and sliding window throttler",
    "Quota Limiting",
    "Token Throttling",
    "SIL-5 / Safety Critical",
    ["SC-ADK-017"],
  )
}

pub fn build_sre_ceph_osd_disk_safety_guard_spec() -> AgentTypeSpec {
  build_spec_record(
    SreCephOsdDiskSafetyGuard,
    "C3I SRE Ceph OSD Disk Safety Guard Agent",
    C3iSre,
    4,
    "#fractal-l4",
    Active,
    7392,
    32,
    Assert,
    "Locks root OS NVMe 25503L801736 against Ceph OSD formatting",
    "Storage Safety",
    "NVMe Hardware Lock",
    "SIL-6 / Sovereign Core",
    ["SC-STORAGE-001"],
  )
}

pub fn build_sre_forecast_predictive_preflight_spec() -> AgentTypeSpec {
  build_spec_record(
    SreForecastPredictivePreflight,
    "C3I SRE Forecast Predictive Preflight Agent",
    C3iSre,
    5,
    "#fractal-l5",
    Active,
    7424,
    32,
    Assert,
    "Bayesian duration/cost forecasting before starting tasks",
    "Predictive SRE",
    "Bayesian Preflight",
    "SIL-5 / Safety Critical",
    ["SC-SRE-029"],
  )
}

pub fn build_sre_endocrine_hormone_balancer_spec() -> AgentTypeSpec {
  build_spec_record(
    SreEndocrineHormoneBalancer,
    "C3I SRE Endocrine Hormone Balancer Agent",
    C3iSre,
    5,
    "#fractal-l5",
    Active,
    7456,
    32,
    Drop,
    "Cybernetic endocrine hormone modulator balancing exploration rates",
    "Endocrine Modulation",
    "Hormonal Balance",
    "SIL-5 / Safety Critical",
    ["SC-CYBER-001"],
  )
}

pub fn build_sre_adaptive_rate_controller_spec() -> AgentTypeSpec {
  build_spec_record(
    SreAdaptiveRateController,
    "C3I SRE Adaptive Rate Controller Agent",
    C3iSre,
    5,
    "#fractal-l5",
    Active,
    7488,
    32,
    Block,
    "Dynamically adjusts task concurrency based on system load",
    "Rate Control",
    "Concurrency Tuning",
    "SIL-4 / High Availability",
    ["SC-SRE-030"],
  )
}

pub fn build_sre_windowed_trend_analyzer_spec() -> AgentTypeSpec {
  build_spec_record(
    SreWindowedTrendAnalyzer,
    "C3I SRE Windowed Trend Analyzer Agent",
    C3iSre,
    5,
    "#fractal-l5",
    Active,
    7520,
    32,
    Drop,
    "Analyzes sliding window metric trends for early degradation",
    "Trend Analysis",
    "Early Warning",
    "SIL-4 / High Availability",
    ["SC-SRE-031"],
  )
}

pub fn build_sre_dynamic_capacity_planner_spec() -> AgentTypeSpec {
  build_spec_record(
    SreDynamicCapacityPlanner,
    "C3I SRE Dynamic Capacity Planner Agent",
    C3iSre,
    5,
    "#fractal-l5",
    Active,
    7552,
    32,
    Block,
    "Forecasts storage and memory capacity limits over time",
    "Capacity Planning",
    "Resource Forecasting",
    "SIL-4 / High Availability",
    ["SC-SRE-032"],
  )
}

pub fn build_sre_metabolic_governor_spec() -> AgentTypeSpec {
  build_spec_record(
    SreMetabolicGovernor,
    "C3I SRE Metabolic Governor Agent",
    C3iSre,
    5,
    "#fractal-l5",
    Active,
    7584,
    32,
    Block,
    "Regulates agent metabolic tick rate during low activity periods",
    "Metabolic Governance",
    "Energy Optimization",
    "SIL-4 / High Availability",
    ["SC-SRE-033"],
  )
}

pub fn build_sre_degraded_mode_orchestrator_spec() -> AgentTypeSpec {
  build_spec_record(
    SreDegradedModeOrchestrator,
    "C3I SRE Degraded Mode Orchestrator Agent",
    C3iSre,
    5,
    "#fractal-l5",
    Active,
    7616,
    32,
    Assert,
    "Manages graceful system degradation when subsystems fail",
    "Degraded Modes",
    "Graceful Degradation",
    "SIL-5 / Safety Critical",
    ["SC-SRE-034"],
  )
}

pub fn build_sre_load_shedding_governor_spec() -> AgentTypeSpec {
  build_spec_record(
    SreLoadSheddingGovernor,
    "C3I SRE Load Shedding Governor Agent",
    C3iSre,
    5,
    "#fractal-l5",
    Active,
    7648,
    32,
    Assert,
    "Sheds non-essential telemetry and background batch jobs under stress",
    "Load Shedding",
    "Stress Relief",
    "SIL-5 / Safety Critical",
    ["SC-SRE-035"],
  )
}

pub fn build_swarm_mesh_spec() -> AgentTypeSpec {
  build_spec_record(
    SwarmMesh,
    "C3I SRE Swarm Mesh Topology Coordinator Agent",
    C3iSre,
    6,
    "#fractal-l6",
    Active,
    7680,
    32,
    Assert,
    "Manages peer discovery, routing, and heartbeats across Zenoh",
    "Mesh Networking",
    "Topology Management",
    "SIL-4 / High Availability",
    ["SC-FPP-015"],
  )
}

pub fn build_epidemic_gossip_spec() -> AgentTypeSpec {
  build_spec_record(
    EpidemicGossip,
    "C3I SRE Epidemic Gossip Disseminator Agent",
    C3iSre,
    6,
    "#fractal-l6",
    Active,
    7712,
    32,
    Drop,
    "Disseminates state snapshots over Zenoh peer gossip protocol",
    "Gossip Protocols",
    "Epidemic Dissemination",
    "SIL-4 / High Availability",
    ["SC-FPP-016"],
  )
}

pub fn build_sre_session_shard_rebalancer_spec() -> AgentTypeSpec {
  build_spec_record(
    SreSessionShardRebalancer,
    "C3I SRE Session Shard Rebalancer Agent",
    C3iSre,
    6,
    "#fractal-l6",
    Active,
    7744,
    32,
    Assert,
    "Consistent hashing actor router and cluster mesh leaser",
    "Session Sharding",
    "Shard Rebalancing",
    "SIL-4 / High Availability",
    ["SC-ADK-016"],
  )
}

pub fn build_sre_prajna_circuit_breaker_spec() -> AgentTypeSpec {
  build_spec_record(
    SrePrajnaCircuitBreaker,
    "C3I SRE Prajna Circuit Breaker Agent",
    C3iSre,
    6,
    "#fractal-l6",
    Active,
    7776,
    32,
    Assert,
    "Functional Gleam Prajna circuit breaker with closed/open/half-open states",
    "Circuit Breakers",
    "Fault Isolation",
    "SIL-5 / Safety Critical",
    ["SC-SRE-036"],
  )
}

pub fn build_sre_mesh_partition_healer_spec() -> AgentTypeSpec {
  build_spec_record(
    SreMeshPartitionHealer,
    "C3I SRE Mesh Partition Healer Agent",
    C3iSre,
    6,
    "#fractal-l6",
    Active,
    7808,
    32,
    Assert,
    "Detects network split-brain and reconciles partitioned nodes",
    "Partition Healing",
    "Split-Brain Resolution",
    "SIL-5 / Safety Critical",
    ["SC-SRE-037"],
  )
}

pub fn build_sre_cascading_failure_shield_spec() -> AgentTypeSpec {
  build_spec_record(
    SreCascadingFailureShield,
    "C3I SRE Cascading Failure Shield Agent",
    C3iSre,
    6,
    "#fractal-l6",
    Active,
    7840,
    32,
    Assert,
    "Isolates failing actor supervisor branches to prevent propagation",
    "Cascade Shielding",
    "Failure Containment",
    "SIL-5 / Safety Critical",
    ["SC-SRE-038"],
  )
}

pub fn build_sre_gossip_membership_cluster_spec() -> AgentTypeSpec {
  build_spec_record(
    SreGossipMembershipCluster,
    "C3I SRE Gossip Membership Cluster Agent",
    C3iSre,
    6,
    "#fractal-l6",
    Active,
    7872,
    32,
    Drop,
    "Tracks live peer membership lists and churn rates across nodes",
    "Cluster Membership",
    "Peer Tracking",
    "SIL-4 / High Availability",
    ["SC-SRE-039"],
  )
}

pub fn build_sre_consensus_consul_elector_spec() -> AgentTypeSpec {
  build_spec_record(
    SreConsensusConsulElector,
    "C3I SRE Consensus Consul Elector Agent",
    C3iSre,
    6,
    "#fractal-l6",
    Active,
    7904,
    32,
    Assert,
    "Conducts raft-like leader election for cluster singleton duties",
    "Leader Election",
    "Consensus Governance",
    "SIL-5 / Safety Critical",
    ["SC-SRE-040"],
  )
}

pub fn build_ground_gateway_spec() -> AgentTypeSpec {
  build_spec_record(
    GroundGateway,
    "C3I SRE Ground Uplink & Downlink Gateway Agent",
    C3iSre,
    7,
    "#fractal-l7",
    Active,
    7936,
    32,
    Block,
    "Manages ground station command uplinks and telemetry downlinks",
    "Gateway Operations",
    "Ground Uplink/Downlink",
    "SIL-5 / Safety Critical",
    ["SC-FPP-017"],
  )
}

pub fn build_sre_crdt_version_vector_sync_spec() -> AgentTypeSpec {
  build_spec_record(
    SreCrdtVersionVectorSync,
    "C3I SRE CRDT Version Vector Sync Agent",
    C3iSre,
    7,
    "#fractal-l7",
    Active,
    7968,
    32,
    Block,
    "State-based CRDT delta synchronizer with vector clocks",
    "Federation Sync",
    "CRDT Merging",
    "SIL-5 / Safety Critical",
    ["SC-CRDT-001"],
  )
}

pub fn build_sre_cast_incident_investigator_spec() -> AgentTypeSpec {
  build_spec_record(
    SreCastIncidentInvestigator,
    "C3I SRE CAST Incident Investigator Agent",
    C3iSre,
    7,
    "#fractal-l7",
    Active,
    8000,
    32,
    Assert,
    "Conducts STPA causal analysis for unexpected gate trips",
    "Incident Analysis",
    "CAST Root Cause",
    "SIL-6 / Sovereign Core",
    ["SC-CAST-001"],
  )
}

pub fn build_sre_post_mortem_rca_synthesizer_spec() -> AgentTypeSpec {
  build_spec_record(
    SrePostMortemRcaSynthesizer,
    "C3I SRE Post Mortem RCA Synthesizer Agent",
    C3iSre,
    7,
    "#fractal-l7",
    Active,
    8032,
    32,
    Block,
    "Generates structured 13-section incident post-mortems",
    "Post Mortem",
    "RCA Synthesis",
    "SIL-5 / Safety Critical",
    ["SC-CAST-002"],
  )
}

pub fn build_sre_federation_gateway_proxy_spec() -> AgentTypeSpec {
  build_spec_record(
    SreFederationGatewayProxy,
    "C3I SRE Federation Gateway Proxy Agent",
    C3iSre,
    7,
    "#fractal-l7",
    Active,
    8064,
    32,
    Block,
    "Proxies inter-cluster requests across Tailnet boundaries",
    "Gateway Proxy",
    "Federation Routing",
    "SIL-5 / Safety Critical",
    ["SC-SRE-041"],
  )
}

pub fn build_sre_telemetry_backplane_publisher_spec() -> AgentTypeSpec {
  build_spec_record(
    SreTelemetryBackplanePublisher,
    "C3I SRE Telemetry Backplane Publisher Agent",
    C3iSre,
    7,
    "#fractal-l7",
    Active,
    8096,
    32,
    Drop,
    "Streams high-frequency metrics to central time-series stores",
    "Telemetry Publishing",
    "Metrics Streaming",
    "SIL-4 / High Availability",
    ["SC-SRE-042"],
  )
}

pub fn build_sre_disaster_recovery_sequencer_spec() -> AgentTypeSpec {
  build_spec_record(
    SreDisasterRecoverySequencer,
    "C3I SRE Disaster Recovery Sequencer Agent",
    C3iSre,
    7,
    "#fractal-l7",
    Active,
    8128,
    32,
    Assert,
    "Sequences full site restoration from cold backups",
    "Disaster Recovery",
    "Site Restoration",
    "SIL-6 / Sovereign Core",
    ["SC-SRE-043"],
  )
}

pub fn build_sre_audit_trail_ledger_signer_spec() -> AgentTypeSpec {
  build_spec_record(
    SreAuditTrailLedgerSigner,
    "C3I SRE Audit Trail Ledger Signer Agent",
    C3iSre,
    7,
    "#fractal-l7",
    Active,
    8160,
    32,
    Assert,
    "Cryptographically signs audit trail ledgers with host keys",
    "Audit Signing",
    "Ledger Integrity",
    "SIL-6 / Sovereign Core",
    ["SC-SRE-044"],
  )
}

pub fn build_constitutional_guardian_spec() -> AgentTypeSpec {
  build_spec_record(
    ConstitutionalGuardian,
    "C3I Verification Constitutional Guardian Agent",
    C3iVerification,
    0,
    "#fractal-l0",
    Active,
    8192,
    32,
    Assert,
    "Enforces Psi-0..5 invariants, DAL-A hardware interlock, and 2oo3 consensus",
    "Constitutional Safety",
    "Verification & Gatekeeping",
    "SIL-6 / Fail-Closed",
    ["SC-CHECKLIST-001", "SC-STORAGE-001"],
  )
}

pub fn build_formal_oracle_spec() -> AgentTypeSpec {
  build_spec_record(
    FormalOracle,
    "C3I Verification Formal Oracle Agent",
    C3iVerification,
    0,
    "#fractal-l0",
    Active,
    8224,
    32,
    Assert,
    "Coordinates Gospel contracts, Lean 4 proofs, and Z3 queries",
    "Formal Methods",
    "Proof & Contract Checking",
    "SIL-6 / Sovereign Core",
    ["SC-FPP-018"],
  )
}

pub fn build_hardware_drive_interlock_spec() -> AgentTypeSpec {
  build_spec_record(
    HardwareDriveInterlock,
    "C3I Verification Hardware Drive Safety Interlock Agent",
    C3iVerification,
    0,
    "#fractal-l0",
    Active,
    8256,
    32,
    Assert,
    "Enforces hardware disk safety interlock rejecting root NVMe 25503L801736",
    "Hardware Safety",
    "Storage Gatekeeping",
    "SIL-6 / Sovereign Core",
    ["SC-STORAGE-001"],
  )
}

pub fn build_rocha_semiotic_cut_guard_spec() -> AgentTypeSpec {
  build_spec_record(
    RochaSemioticCutGuard,
    "C3I Verification Rocha Semiotic Cut Guard Agent",
    C3iVerification,
    0,
    "#fractal-l0",
    Active,
    8288,
    32,
    Assert,
    "Enforces biosemiotic code-biology boundary decoupling",
    "Biosemiotics",
    "Semiotic Boundary Audit",
    "SIL-6 / Sovereign Core",
    ["SC-ROCHA-001"],
  )
}

pub fn build_verification_checklist_auditor_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationChecklistAuditor,
    "C3I Verification Checklist Auditor Agent",
    C3iVerification,
    0,
    "#fractal-l0",
    Active,
    8320,
    32,
    Assert,
    "Audits 5-domain 18-checkpoint verification checklist",
    "Verification Checklist",
    "Checklist Certification",
    "SIL-6 / Sovereign Core",
    ["SC-CHECKLIST-001"],
  )
}

pub fn build_verification_math_gate_certifier_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationMathGateCertifier,
    "C3I Verification Math Gate Certifier Agent",
    C3iVerification,
    0,
    "#fractal-l0",
    Active,
    8352,
    32,
    Assert,
    "Certifies 4 mathematical gates (H>=2.5b, CCM>=90%, D_EA<=10%, ITQS>=0.85)",
    "Mathematical Gates",
    "Formal Metric Certification",
    "SIL-6 / Sovereign Core",
    ["SC-MATH-001"],
  )
}

pub fn build_verification_tcm_coordinate_protector_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationTcmCoordinateProtector,
    "C3I Verification TCM Coordinate Protector Agent",
    C3iVerification,
    0,
    "#fractal-l0",
    Active,
    8384,
    32,
    Assert,
    "Proves 13D spacetime coordinate conservation Delta T_13 = 0",
    "TCM Space-Time",
    "Coordinate Conservation",
    "SIL-6 / Sovereign Core",
    ["SC-TCM-001"],
  )
}

pub fn build_verification_zero_muda_purity_enforcer_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationZeroMudaPurityEnforcer,
    "C3I Verification Zero Muda Purity Enforcer Agent",
    C3iVerification,
    0,
    "#fractal-l0",
    Active,
    8416,
    32,
    Assert,
    "Enforces Zero-Muda purity (0 Bevy, 0 Graphite, pure Erlang vector math)",
    "Zero Muda Purity",
    "Purity Gatekeeping",
    "SIL-6 / Sovereign Core",
    ["SC-MUDA-001"],
  )
}

pub fn build_deterministic_flight_controller_spec() -> AgentTypeSpec {
  build_spec_record(
    DeterministicFlightController,
    "C3I Verification Deterministic Flight Controller Agent",
    C3iVerification,
    1,
    "#fractal-l1",
    Active,
    8448,
    32,
    Block,
    "Sub-millisecond periodic command execution and actuator dispatching",
    "Avionics Real-Time",
    "Flight Execution Runtime",
    "SIL-4 / Real-Time Bounded",
    ["SC-FPP-002"],
  )
}

pub fn build_substrate_reactor_spec() -> AgentTypeSpec {
  build_spec_record(
    SubstrateReactor,
    "C3I Verification Substrate Reactor Agent",
    C3iVerification,
    1,
    "#fractal-l1",
    Active,
    8480,
    32,
    Assert,
    "Monitors deterministic ZigVM execution substrate kernel",
    "Execution Substrate",
    "Kernel Verification",
    "SIL-6 / Sovereign Core",
    ["SC-ZIGVM-001"],
  )
}

pub fn build_verification_pinned_otp_differential_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationPinnedOtpDifferential,
    "C3I Verification Pinned OTP Differential Agent",
    C3iVerification,
    1,
    "#fractal-l1",
    Active,
    8512,
    32,
    Assert,
    "Executes differential parity suites against pinned Erlang/OTP 30",
    "Differential Parity",
    "Parity Oracle Verification",
    "SIL-6 / Sovereign Core",
    ["SC-OTP-002"],
  )
}

pub fn build_verification_gospel_ortac_runtime_monitor_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationGospelOrtacRuntimeMonitor,
    "C3I Verification Gospel Ortac Runtime Monitor Agent",
    C3iVerification,
    1,
    "#fractal-l1",
    Active,
    8544,
    32,
    Assert,
    "Gospel precondition/postcondition dynamic monitor via Ortac",
    "Formal Monitoring",
    "Dynamic Contract Validation",
    "SIL-6 / Sovereign Core",
    ["SC-GOSPEL-002"],
  )
}

pub fn build_verification_smt_negation_auditor_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationSmtNegationAuditor,
    "C3I Verification SMT Negation Auditor Agent",
    C3iVerification,
    1,
    "#fractal-l1",
    Active,
    8576,
    32,
    Assert,
    "Ensures SMT obligations assert negation and require Unsat",
    "SMT Verification",
    "Negation Proof Checking",
    "SIL-6 / Sovereign Core",
    ["SC-SMT-001"],
  )
}

pub fn build_verification_z3_unsat_validator_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationZ3UnsatValidator,
    "C3I Verification Z3 Unsat Validator Agent",
    C3iVerification,
    1,
    "#fractal-l1",
    Active,
    8608,
    32,
    Assert,
    "Dispatches normalized queries to bounded Z3 solver worker",
    "SMT Solver",
    "Unsat Validation",
    "SIL-6 / Sovereign Core",
    ["SC-Z3-001"],
  )
}

pub fn build_verification_negative_control_verifier_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationNegativeControlVerifier,
    "C3I Verification Negative Control Verifier Agent",
    C3iVerification,
    1,
    "#fractal-l1",
    Active,
    8640,
    32,
    Assert,
    "Requires non-trivial negative controls returning Sat to detect vacuity",
    "Control Verification",
    "Vacuity Detection",
    "SIL-6 / Sovereign Core",
    ["SC-SMT-002"],
  )
}

pub fn build_verification_typestate_invariant_checker_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationTypestateInvariantChecker,
    "C3I Verification Typestate Invariant Checker Agent",
    C3iVerification,
    1,
    "#fractal-l1",
    Active,
    8672,
    32,
    Assert,
    "Verifies compile-time typestate state machine transitions",
    "Typestate Safety",
    "Compile-Time Invariant Proof",
    "SIL-6 / Sovereign Core",
    ["SC-VER-001"],
  )
}

pub fn build_avionics_telemetry_spec() -> AgentTypeSpec {
  build_spec_record(
    AvionicsTelemetry,
    "C3I Verification Avionics Telemetry Stream Agent",
    C3iVerification,
    2,
    "#fractal-l2",
    Active,
    8704,
    32,
    Drop,
    "Aggregates channel samples and generates CCSDS-compatible packets",
    "Telemetry Streaming",
    "Telemetry Aggregation",
    "SIL-2 / Non-Blocking",
    ["SC-FPP-005"],
  )
}

pub fn build_cockpit_telemetry_spec() -> AgentTypeSpec {
  build_spec_record(
    CockpitTelemetry,
    "C3I Verification Cockpit Telemetry Bridge Agent",
    C3iVerification,
    2,
    "#fractal-l2",
    Active,
    8736,
    32,
    Drop,
    "Bridges telemetry streams to web cockpit and terminal TUIs",
    "Cockpit Streaming",
    "UI Telemetry Feed",
    "SIL-3 / Monitored",
    ["SC-GLM-UI-002"],
  )
}

pub fn build_verification_browser_matrix_tester_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationBrowserMatrixTester,
    "C3I Verification Browser Matrix Tester Agent",
    C3iVerification,
    2,
    "#fractal-l2",
    Active,
    8768,
    32,
    Block,
    "Executes automated Playwright/Wallaby browser test matrix",
    "Browser Testing",
    "E2E Web Verification",
    "SIL-4 / High Availability",
    ["SC-UI-003"],
  )
}

pub fn build_verification_mutation_adequacy_killer_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationMutationAdequacyKiller,
    "C3I Verification Mutation Adequacy Killer Agent",
    C3iVerification,
    2,
    "#fractal-l2",
    Active,
    8800,
    32,
    Assert,
    "Injects semantic defects to maintain >=90% mutant kill score",
    "Mutation Testing",
    "Defect Kill Certification",
    "SIL-5 / Safety Critical",
    ["SC-MUT-001"],
  )
}

pub fn build_verification_tdd_law_enforcer_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationTddLawEnforcer,
    "C3I Verification TDD Law Enforcer Agent",
    C3iVerification,
    2,
    "#fractal-l2",
    Active,
    8832,
    32,
    Assert,
    "Enforces failing law test before implementation code is written",
    "TDD Discipline",
    "Micro-Cycle Enforcement",
    "SIL-5 / Safety Critical",
    ["SC-TDD-001"],
  )
}

pub fn build_verification_red_green_revert_judge_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationRedGreenRevertJudge,
    "C3I Verification Red Green Revert Judge Agent",
    C3iVerification,
    2,
    "#fractal-l2",
    Active,
    8864,
    32,
    Assert,
    "Verifies red-green-revert progression for each planted mutant",
    "Mutation Verification",
    "Kill Proof Inspection",
    "SIL-5 / Safety Critical",
    ["SC-MUT-002"],
  )
}

pub fn build_verification_flaccid_law_detector_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationFlaccidLawDetector,
    "C3I Verification Flaccid Law Detector Agent",
    C3iVerification,
    2,
    "#fractal-l2",
    Active,
    8896,
    32,
    Assert,
    "Detects flaccid assertions that pass even when logic is deleted",
    "Law Hardening",
    "Assertion Strength Audit",
    "SIL-5 / Safety Critical",
    ["SC-VER-002"],
  )
}

pub fn build_verification_fixture_totality_auditor_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationFixtureTotalityAuditor,
    "C3I Verification Fixture Totality Auditor Agent",
    C3iVerification,
    2,
    "#fractal-l2",
    Active,
    8928,
    32,
    Assert,
    "Enforces symmetric operand testing over asymmetric codegen",
    "Fixture Totality",
    "Asymmetry Verification",
    "SIL-5 / Safety Critical",
    ["SC-TEST-001"],
  )
}

pub fn build_mcdc_avionics_tap_spec() -> AgentTypeSpec {
  build_spec_record(
    McdcAvionicsTap,
    "C3I Verification MC/DC Avionics Tap Agent",
    C3iVerification,
    3,
    "#fractal-l3",
    Active,
    8960,
    32,
    Assert,
    "Records modified condition/decision coverage traces for DO-178C",
    "MCDC Coverage",
    "Avionics Trace Recording",
    "SIL-6 / Sovereign Core",
    ["SC-FPP-019"],
  )
}

pub fn build_differential_bisimulation_spec() -> AgentTypeSpec {
  build_spec_record(
    DifferentialBisimulation,
    "C3I Verification Differential Bisimulation Agent",
    C3iVerification,
    3,
    "#fractal-l3",
    Active,
    8992,
    32,
    Assert,
    "Evaluates behavioral equivalence between Erlang and ZigVM",
    "Bisimulation",
    "Equivalence Checking",
    "SIL-6 / Sovereign Core",
    ["SC-FPP-020"],
  )
}

pub fn build_verification_nine_modality_executor_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationNineModalityExecutor,
    "C3I Verification Nine Modality Executor Agent",
    C3iVerification,
    3,
    "#fractal-l3",
    Active,
    9024,
    32,
    Assert,
    "Executes full 9-modality test protocol across the entire system",
    "Nine Modality",
    "Comprehensive Test Protocol",
    "SIL-6 / Sovereign Core",
    ["SC-9MOD-001"],
  )
}

pub fn build_verification_tool_schema_conformance_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationToolSchemaConformance,
    "C3I Verification Tool Schema Conformance Agent",
    C3iVerification,
    3,
    "#fractal-l3",
    Active,
    9056,
    32,
    Assert,
    "Validates MCP tool payloads against JSON Schema 2020-12",
    "Schema Validation",
    "Tool Contract Conformance",
    "SIL-5 / Safety Critical",
    ["SC-ADK-022"],
  )
}

pub fn build_verification_bdd_scenario_runner_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationBddScenarioRunner,
    "C3I Verification BDD Scenario Runner Agent",
    C3iVerification,
    3,
    "#fractal-l3",
    Active,
    9088,
    32,
    Block,
    "Executes Gherkin/BDD scenarios asserting behavioral contracts",
    "BDD Scenarios",
    "Behavior Verification",
    "SIL-4 / High Availability",
    ["SC-BDD-001"],
  )
}

pub fn build_verification_state_transition_asserter_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationStateTransitionAsserter,
    "C3I Verification State Transition Asserter Agent",
    C3iVerification,
    3,
    "#fractal-l3",
    Active,
    9120,
    32,
    Assert,
    "Asserts state reachability and valid sequence paths in HSMs",
    "State Transition",
    "Reachability Checking",
    "SIL-5 / Safety Critical",
    ["SC-FPP-021"],
  )
}

pub fn build_verification_trace_equivalence_judge_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationTraceEquivalenceJudge,
    "C3I Verification Trace Equivalence Judge Agent",
    C3iVerification,
    3,
    "#fractal-l3",
    Active,
    9152,
    32,
    Assert,
    "Compares execution traces for observational equivalence",
    "Trace Equivalence",
    "Behavioral Equivalence",
    "SIL-5 / Safety Critical",
    ["SC-VER-003"],
  )
}

pub fn build_verification_mcdc_branch_coverage_auditor_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationMcdcBranchCoverageAuditor,
    "C3I Verification MCDC Branch Coverage Auditor Agent",
    C3iVerification,
    3,
    "#fractal-l3",
    Active,
    9184,
    32,
    Assert,
    "Proves 100% MC/DC branch coverage on critical control kernels",
    "Branch Coverage",
    "MCDC Certification",
    "SIL-6 / Sovereign Core",
    ["SC-VER-004"],
  )
}

pub fn build_verification_playwright_control_auditor_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationPlaywrightControlAuditor,
    "C3I Verification Playwright Control Auditor Agent",
    C3iVerification,
    4,
    "#fractal-l4",
    Active,
    9216,
    32,
    Block,
    "Audits headless browser automation sessions and CDP devtools",
    "Browser Automation",
    "Playwright Verification",
    "SIL-4 / High Availability",
    ["SC-UI-004"],
  )
}

pub fn build_verification_multi_turn_dialogue_verifier_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationMultiTurnDialogueVerifier,
    "C3I Verification Multi Turn Dialogue Verifier Agent",
    C3iVerification,
    4,
    "#fractal-l4",
    Active,
    9248,
    32,
    Block,
    "Evaluates conversation coherence and context retention",
    "Dialogue Audit",
    "Multi-Turn Coherence",
    "SIL-4 / High Availability",
    ["SC-ADK-023"],
  )
}

pub fn build_verification_property_generator_fuzzer_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationPropertyGeneratorFuzzer,
    "C3I Verification Property Generator Fuzzer Agent",
    C3iVerification,
    4,
    "#fractal-l4",
    Active,
    9280,
    32,
    Block,
    "Generates pseudo-random property test cases with seeds",
    "Property Fuzzing",
    "Generative Testing",
    "SIL-5 / Safety Critical",
    ["SC-PROP-001"],
  )
}

pub fn build_verification_generative_shrink_engine_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationGenerativeShrinkEngine,
    "C3I Verification Generative Shrink Engine Agent",
    C3iVerification,
    4,
    "#fractal-l4",
    Active,
    9312,
    32,
    Block,
    "Shrinks failing property test cases to minimal counterexamples",
    "Test Shrinking",
    "Counterexample Minimization",
    "SIL-5 / Safety Critical",
    ["SC-PROP-002"],
  )
}

pub fn build_verification_boundary_value_tester_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationBoundaryValueTester,
    "C3I Verification Boundary Value Tester Agent",
    C3iVerification,
    4,
    "#fractal-l4",
    Active,
    9344,
    32,
    Block,
    "Tests numeric boundaries (INT_MAX, zero, NaN, empty bitstrings)",
    "Boundary Testing",
    "Edge Case Fuzzing",
    "SIL-4 / High Availability",
    ["SC-TEST-002"],
  )
}

pub fn build_verification_seeded_random_replayer_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationSeededRandomReplayer,
    "C3I Verification Seeded Random Replayer Agent",
    C3iVerification,
    4,
    "#fractal-l4",
    Active,
    9376,
    32,
    Assert,
    "Replays failing property tests deterministically using stored seeds",
    "Deterministic Replay",
    "Seed Replay",
    "SIL-5 / Safety Critical",
    ["SC-TEST-003"],
  )
}

pub fn build_verification_corpus_module_executor_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationCorpusModuleExecutor,
    "C3I Verification Corpus Module Executor Agent",
    C3iVerification,
    4,
    "#fractal-l4",
    Active,
    9408,
    32,
    Assert,
    "Executes real compiled BEAM and Zig modules end-to-end",
    "Corpus Testing",
    "Real Module Execution",
    "SIL-5 / Safety Critical",
    ["SC-CORPUS-001"],
  )
}

pub fn build_verification_ast_mutant_synthesizer_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationAstMutantSynthesizer,
    "C3I Verification AST Mutant Synthesizer Agent",
    C3iVerification,
    4,
    "#fractal-l4",
    Active,
    9440,
    32,
    Block,
    "Generates semantic AST mutations for automated mutation sweeps",
    "AST Mutation",
    "Mutant Synthesis",
    "SIL-5 / Safety Critical",
    ["SC-MUT-003"],
  )
}

pub fn build_verification_adk_eval_benchmark_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationAdkEvalBenchmark,
    "C3I Verification ADK Eval Benchmark Agent",
    C3iVerification,
    5,
    "#fractal-l5",
    Active,
    9472,
    32,
    Assert,
    "Benchmarks ADK agent capabilities against evaluation harness",
    "ADK Evaluation",
    "Agent Benchmarking",
    "SIL-5 / Safety Critical",
    ["SC-ADK-004"],
  )
}

pub fn build_verification_trajectory_replay_certifier_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationTrajectoryReplayCertifier,
    "C3I Verification Trajectory Replay Certifier Agent",
    C3iVerification,
    5,
    "#fractal-l5",
    Active,
    9504,
    32,
    Assert,
    "Replays agent reasoning trajectories against golden baselines",
    "Trajectory Replay",
    "Golden Replay Certification",
    "SIL-5 / Safety Critical",
    ["SC-ADK-020"],
  )
}

pub fn build_verification_hallucination_scorer_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationHallucinationScorer,
    "C3I Verification Hallucination Scorer Agent",
    C3iVerification,
    5,
    "#fractal-l5",
    Active,
    9536,
    32,
    Assert,
    "Calculates expected vs actual divergence (D_EA <= 10%)",
    "Truthfulness",
    "Hallucination Scoring",
    "SIL-5 / Safety Critical",
    ["SC-ADK-021"],
  )
}

pub fn build_verification_entropy_calculator_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationEntropyCalculator,
    "C3I Verification Entropy Calculator Agent",
    C3iVerification,
    5,
    "#fractal-l5",
    Active,
    9568,
    32,
    Assert,
    "Verifies Shannon entropy H >= 2.5 bits across state spaces",
    "Entropy Math",
    "Shannon Entropy Gate",
    "SIL-5 / Safety Critical",
    ["SC-MATH-002"],
  )
}

pub fn build_verification_divergence_metric_scorer_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationDivergenceMetricScorer,
    "C3I Verification Divergence Metric Scorer Agent",
    C3iVerification,
    5,
    "#fractal-l5",
    Active,
    9600,
    32,
    Assert,
    "Computes divergence metrics between candidate and oracle states",
    "Divergence Scoring",
    "Parity Metric Evaluation",
    "SIL-5 / Safety Critical",
    ["SC-MATH-003"],
  )
}

pub fn build_verification_factual_grounding_auditor_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationFactualGroundingAuditor,
    "C3I Verification Factual Grounding Auditor Agent",
    C3iVerification,
    5,
    "#fractal-l5",
    Active,
    9632,
    32,
    Assert,
    "Verifies citations and facts against SQLite knowledge bases",
    "Factual Grounding",
    "Citation Verification",
    "SIL-5 / Safety Critical",
    ["SC-FACT-001"],
  )
}

pub fn build_verification_reasoning_step_validator_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationReasoningStepValidator,
    "C3I Verification Reasoning Step Validator Agent",
    C3iVerification,
    5,
    "#fractal-l5",
    Active,
    9664,
    32,
    Assert,
    "Audits multi-step reasoning steps for logical coherence",
    "Reasoning Audit",
    "Step Coherence",
    "SIL-5 / Safety Critical",
    ["SC-REASON-001"],
  )
}

pub fn build_verification_context_retention_verifier_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationContextRetentionVerifier,
    "C3I Verification Context Retention Verifier Agent",
    C3iVerification,
    5,
    "#fractal-l5",
    Active,
    9696,
    32,
    Assert,
    "Verifies key information retention across 50+ dialogue turns",
    "Context Retention",
    "Long-Context Audit",
    "SIL-4 / High Availability",
    ["SC-CONTEXT-001"],
  )
}

pub fn build_verification_simulation_environment_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationSimulationEnvironment,
    "C3I Verification Simulation Environment Agent",
    C3iVerification,
    6,
    "#fractal-l6",
    Active,
    9728,
    32,
    Block,
    "Simulates distributed mesh topologies and edge devices",
    "Simulation",
    "Swarm Simulation",
    "SIL-4 / High Availability",
    ["SC-SIM-001"],
  )
}

pub fn build_verification_actor_bisimulation_tester_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationActorBisimulationTester,
    "C3I Verification Actor Bisimulation Tester Agent",
    C3iVerification,
    6,
    "#fractal-l6",
    Active,
    9760,
    32,
    Assert,
    "Tests weak and strong bisimulation between actor state machines",
    "Bisimulation Testing",
    "Actor Equivalence",
    "SIL-5 / Safety Critical",
    ["SC-VER-005"],
  )
}

pub fn build_verification_concurrency_race_detector_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationConcurrencyRaceDetector,
    "C3I Verification Concurrency Race Detector Agent",
    C3iVerification,
    6,
    "#fractal-l6",
    Active,
    9792,
    32,
    Assert,
    "Detects data races and message order violations under SMP",
    "Race Detection",
    "Concurrency Safety",
    "SIL-5 / Safety Critical",
    ["SC-SMP-001"],
  )
}

pub fn build_verification_model_checker_bridge_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationModelCheckerBridge,
    "C3I Verification Model Checker Bridge Agent",
    C3iVerification,
    6,
    "#fractal-l6",
    Active,
    9824,
    32,
    Assert,
    "Bridges Gleam models to TLC and Quint model checkers",
    "Model Checking",
    "State Space Exploration",
    "SIL-6 / Sovereign Core",
    ["SC-MC-001"],
  )
}

pub fn build_verification_linearizability_oracle_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationLinearizabilityOracle,
    "C3I Verification Linearizability Oracle Agent",
    C3iVerification,
    6,
    "#fractal-l6",
    Active,
    9856,
    32,
    Assert,
    "Verifies linearizable histories for concurrent register operations",
    "Linearizability",
    "History Verification",
    "SIL-5 / Safety Critical",
    ["SC-VER-006"],
  )
}

pub fn build_verification_distributed_partition_tester_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationDistributedPartitionTester,
    "C3I Verification Distributed Partition Tester Agent",
    C3iVerification,
    6,
    "#fractal-l6",
    Active,
    9888,
    32,
    Assert,
    "Tests system invariants during simulated network partitions",
    "Partition Testing",
    "Network Chaos",
    "SIL-5 / Safety Critical",
    ["SC-CHAOS-001"],
  )
}

pub fn build_verification_message_loss_simulator_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationMessageLossSimulator,
    "C3I Verification Message Loss Simulator Agent",
    C3iVerification,
    6,
    "#fractal-l6",
    Active,
    9920,
    32,
    Assert,
    "Simulates packet loss, corruption, and duplicate delivery",
    "Fault Simulation",
    "Transport Robustness",
    "SIL-5 / Safety Critical",
    ["SC-CHAOS-002"],
  )
}

pub fn build_verification_clock_drift_chaos_tester_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationClockDriftChaosTester,
    "C3I Verification Clock Drift Chaos Tester Agent",
    C3iVerification,
    6,
    "#fractal-l6",
    Active,
    9952,
    32,
    Assert,
    "Injects simulated clock drift to verify SC-TIME robustness",
    "Clock Chaos",
    "Time Drift Verification",
    "SIL-5 / Safety Critical",
    ["SC-TIME-002"],
  )
}

pub fn build_verification_sheaf_gluing_harmonizer_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationSheafGluingHarmonizer,
    "C3I Verification Sheaf Gluing Harmonizer Agent",
    C3iVerification,
    7,
    "#fractal-l7",
    Active,
    9984,
    32,
    Assert,
    "Verifies sheaf gluing consistency across page boundaries",
    "Sheaf Theory",
    "Gluing Harmonization",
    "SIL-5 / Safety Critical",
    ["SC-SHEAF-001"],
  )
}

pub fn build_verification_lean_formal_proof_oracle_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationLeanFormalProofOracle,
    "C3I Verification Lean Formal Proof Oracle Agent",
    C3iVerification,
    7,
    "#fractal-l7",
    Active,
    10_016,
    32,
    Assert,
    "Verifies mathematical theorem closures in Lean 4",
    "Lean 4 Proofs",
    "Mathematical Authority",
    "SIL-6 / Sovereign Core",
    ["SC-LEAN-001"],
  )
}

pub fn build_verification_quint_parity_frontier_oracle_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationQuintParityFrontierOracle,
    "C3I Verification Quint Parity Frontier Oracle Agent",
    C3iVerification,
    7,
    "#fractal-l7",
    Active,
    10_048,
    32,
    Assert,
    "Simulates intent closure invariants in Quint temporal logic",
    "Quint Models",
    "Parity Frontier Checking",
    "SIL-6 / Sovereign Core",
    ["SC-QUINT-001"],
  )
}

pub fn build_verification_master_checklist_gatekeeper_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationMasterChecklistGatekeeper,
    "C3I Verification Master Checklist Gatekeeper Agent",
    C3iVerification,
    7,
    "#fractal-l7",
    Active,
    10_080,
    32,
    Assert,
    "Blocks non-compliant commits lacking 18/18 checklist pass",
    "Gatekeeper",
    "Master Checklist Gate",
    "SIL-6 / Sovereign Core",
    ["SC-CHECKLIST-002"],
  )
}

pub fn build_verification_parity_ratchet_enforcer_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationParityRatchetEnforcer,
    "C3I Verification Parity Ratchet Enforcer Agent",
    C3iVerification,
    7,
    "#fractal-l7",
    Active,
    10_112,
    32,
    Assert,
    "Prevents downgrading of EQ entries in DIVERGENCE_LOG",
    "Ratchet Enforcer",
    "Parity Preservation",
    "SIL-6 / Sovereign Core",
    ["SC-DIVERGE-001"],
  )
}

pub fn build_verification_baseline_release_gatekeeper_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationBaselineReleaseGatekeeper,
    "C3I Verification Baseline Release Gatekeeper Agent",
    C3iVerification,
    7,
    "#fractal-l7",
    Active,
    10_144,
    32,
    Assert,
    "Authorizes baseline acceptance and release promotion",
    "Release Gate",
    "Baseline Acceptance",
    "SIL-6 / Sovereign Core",
    ["SC-RELEASE-001"],
  )
}

pub fn build_verification_formal_evidence_archiver_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationFormalEvidenceArchiver,
    "C3I Verification Formal Evidence Archiver Agent",
    C3iVerification,
    7,
    "#fractal-l7",
    Active,
    10_176,
    32,
    Assert,
    "Archives cryptographic proof receipts into append-only SQLite",
    "Evidence Archival",
    "Proof Retention",
    "SIL-6 / Sovereign Core",
    ["SC-EVID-001"],
  )
}

pub fn build_verification_sovereign_consensus_ratifier_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationSovereignConsensusRatifier,
    "C3I Verification Sovereign Consensus Ratifier Agent",
    C3iVerification,
    7,
    "#fractal-l7",
    Active,
    10_208,
    32,
    Assert,
    "Collects and verifies tri-sovereign signatures (AGY, Claude, Codex)",
    "Sovereign Ratification",
    "Tri-Sovereign Consensus",
    "SIL-6 / Sovereign Core",
    ["SC-SOV-001"],
  )
}

pub fn build_intelligence_rocha_cut_validator_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceRochaCutValidator,
    "C3I Intelligence Rocha Cut Validator Agent",
    C3iIntelligence,
    0,
    "#fractal-l0",
    Active,
    10_240,
    32,
    Assert,
    "Enforces Rocha biosemiotics code-biology decoupling cut",
    "Biosemiotics",
    "Rocha Cut Validation",
    "SIL-6 / Sovereign Core",
    ["SC-ROCHA-002"],
  )
}

pub fn build_intelligence_code_biology_boundary_guard_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceCodeBiologyBoundaryGuard,
    "C3I Intelligence Code Biology Boundary Guard Agent",
    C3iIntelligence,
    0,
    "#fractal-l0",
    Active,
    10_272,
    32,
    Assert,
    "Guards the metabolic boundary between symbolic and physical state",
    "Metabolic Boundary",
    "Boundary Protection",
    "SIL-6 / Sovereign Core",
    ["SC-ROCHA-003"],
  )
}

pub fn build_intelligence_symbol_matter_decoupler_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceSymbolMatterDecoupler,
    "C3I Intelligence Symbol Matter Decoupler Agent",
    C3iIntelligence,
    0,
    "#fractal-l0",
    Active,
    10_304,
    32,
    Assert,
    "Decouples symbolic intent representation from physical actuation",
    "Symbolic Decoupling",
    "Matter Decoupling",
    "SIL-6 / Sovereign Core",
    ["SC-ROCHA-004"],
  )
}

pub fn build_intelligence_semiotic_closure_auditor_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceSemioticClosureAuditor,
    "C3I Intelligence Semiotic Closure Auditor Agent",
    C3iIntelligence,
    0,
    "#fractal-l0",
    Active,
    10_336,
    32,
    Assert,
    "Audits complete semiotic triads (sign, object, interpretant)",
    "Semiotic Closure",
    "Triad Verification",
    "SIL-6 / Sovereign Core",
    ["SC-ROCHA-005"],
  )
}

pub fn build_intelligence_semantic_anchor_protector_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceSemanticAnchorProtector,
    "C3I Intelligence Semantic Anchor Protector Agent",
    C3iIntelligence,
    0,
    "#fractal-l0",
    Active,
    10_368,
    32,
    Assert,
    "Protects ground truth invariants from semantic drift",
    "Semantic Anchoring",
    "Invariance Protection",
    "SIL-6 / Sovereign Core",
    ["SC-ROCHA-006"],
  )
}

pub fn build_intelligence_biomorphic_morphogen_router_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceBiomorphicMorphogenRouter,
    "C3I Intelligence Biomorphic Morphogen Router Agent",
    C3iIntelligence,
    0,
    "#fractal-l0",
    Active,
    10_400,
    32,
    Block,
    "Routes simulated morphogen signals across cognitive layers",
    "Biomorphic Routing",
    "Morphogen Diffusion",
    "SIL-5 / Safety Critical",
    ["SC-BIOMORPH-001"],
  )
}

pub fn build_intelligence_cybernetic_feedback_harmonizer_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceCyberneticFeedbackHarmonizer,
    "C3I Intelligence Cybernetic Feedback Harmonizer Agent",
    C3iIntelligence,
    0,
    "#fractal-l0",
    Active,
    10_432,
    32,
    Drop,
    "Harmonizes second-order cybernetic feedback loops",
    "Cybernetic Feedback",
    "Feedback Harmonization",
    "SIL-5 / Safety Critical",
    ["SC-CYBER-002"],
  )
}

pub fn build_intelligence_metabolic_homeostasis_tracker_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceMetabolicHomeostasisTracker,
    "C3I Intelligence Metabolic Homeostasis Tracker Agent",
    C3iIntelligence,
    0,
    "#fractal-l0",
    Active,
    10_464,
    32,
    Drop,
    "Maintains operational homeostasis across memory and CPU usage",
    "Metabolic Homeostasis",
    "Homeostatic Regulation",
    "SIL-5 / Safety Critical",
    ["SC-CYBER-003"],
  )
}

pub fn build_intelligence_sheaf_cohomology_engine_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceSheafCohomologyEngine,
    "C3I Intelligence Sheaf Cohomology Engine Agent",
    C3iIntelligence,
    1,
    "#fractal-l1",
    Active,
    10_496,
    32,
    Assert,
    "Calculates H^0 and H^1 sheaf cohomology groups over knowledge spaces",
    "Sheaf Theory",
    "Cohomology Calculation",
    "SIL-6 / Sovereign Core",
    ["SC-SHEAF-002"],
  )
}

pub fn build_intelligence_local_section_extractor_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceLocalSectionExtractor,
    "C3I Intelligence Local Section Extractor Agent",
    C3iIntelligence,
    1,
    "#fractal-l1",
    Active,
    10_528,
    32,
    Block,
    "Extracts local sections and restriction morphisms from documents",
    "Local Sections",
    "Restriction Morphisms",
    "SIL-5 / Safety Critical",
    ["SC-SHEAF-003"],
  )
}

pub fn build_intelligence_presheaf_functor_mapper_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligencePresheafFunctorMapper,
    "C3I Intelligence Presheaf Functor Mapper Agent",
    C3iIntelligence,
    1,
    "#fractal-l1",
    Active,
    10_560,
    32,
    Block,
    "Maps presheaf contravariant functors across topological spaces",
    "Presheaf Functors",
    "Functor Mapping",
    "SIL-5 / Safety Critical",
    ["SC-SHEAF-004"],
  )
}

pub fn build_intelligence_gluing_morphism_synthesizer_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceGluingMorphismSynthesizer,
    "C3I Intelligence Gluing Morphism Synthesizer Agent",
    C3iIntelligence,
    1,
    "#fractal-l1",
    Active,
    10_592,
    32,
    Block,
    "Synthesizes gluing morphisms on intersecting open covers",
    "Gluing Morphisms",
    "Intersection Synthesis",
    "SIL-5 / Safety Critical",
    ["SC-SHEAF-005"],
  )
}

pub fn build_intelligence_restriction_map_validator_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceRestrictionMapValidator,
    "C3I Intelligence Restriction Map Validator Agent",
    C3iIntelligence,
    1,
    "#fractal-l1",
    Active,
    10_624,
    32,
    Assert,
    "Validates restriction map commutativity across open sets",
    "Restriction Validation",
    "Diagram Commutativity",
    "SIL-5 / Safety Critical",
    ["SC-SHEAF-006"],
  )
}

pub fn build_intelligence_cech_complex_builder_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceCechComplexBuilder,
    "C3I Intelligence Cech Complex Builder Agent",
    C3iIntelligence,
    1,
    "#fractal-l1",
    Active,
    10_656,
    32,
    Block,
    "Constructs Cech nerve complexes from open covers",
    "Cech Complexes",
    "Nerve Construction",
    "SIL-5 / Safety Critical",
    ["SC-SHEAF-007"],
  )
}

pub fn build_intelligence_spectral_sequence_analyzer_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceSpectralSequenceAnalyzer,
    "C3I Intelligence Spectral Sequence Analyzer Agent",
    C3iIntelligence,
    1,
    "#fractal-l1",
    Active,
    10_688,
    32,
    Assert,
    "Analyzes spectral sequences for topological convergence",
    "Spectral Sequences",
    "Topological Convergence",
    "SIL-5 / Safety Critical",
    ["SC-SHEAF-008"],
  )
}

pub fn build_intelligence_category_theory_bridge_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceCategoryTheoryBridge,
    "C3I Intelligence Category Theory Bridge Agent",
    C3iIntelligence,
    1,
    "#fractal-l1",
    Active,
    10_720,
    32,
    Block,
    "Binds category-theoretic monoids, adjunctions, and limits",
    "Category Theory",
    "Categorical Bindings",
    "SIL-5 / Safety Critical",
    ["SC-SHEAF-009"],
  )
}

pub fn build_verification_zk_km_knowledge_currency_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationZkKmKnowledgeCurrency,
    "C3I Intelligence ZK KM Knowledge Currency Agent",
    C3iIntelligence,
    2,
    "#fractal-l2",
    Active,
    10_752,
    32,
    Drop,
    "Monitors token costs, cache hits, and ZK currency KPIs in smriti.db",
    "Cost & Currency",
    "ZK Economics",
    "SIL-4 / High Availability",
    ["SC-ZK-001"],
  )
}

pub fn build_intelligence_zettelkasten_librarian_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceZettelkastenLibrarian,
    "C3I Intelligence Zettelkasten Librarian Agent",
    C3iIntelligence,
    2,
    "#fractal-l2",
    Active,
    10_784,
    32,
    Block,
    "Maintains permanent ZK note index and cross-references",
    "ZK Library",
    "Zettelkasten Governance",
    "SIL-4 / High Availability",
    ["SC-ZK-002"],
  )
}

pub fn build_intelligence_permanent_adr_custodian_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligencePermanentAdrCustodian,
    "C3I Intelligence Permanent ADR Custodian Agent",
    C3iIntelligence,
    2,
    "#fractal-l2",
    Active,
    10_816,
    32,
    Assert,
    "Guards permanent Architecture Decision Records (ADR-001..029)",
    "ADR Governance",
    "Decision Archival",
    "SIL-6 / Sovereign Core",
    ["SC-ZK-003"],
  )
}

pub fn build_intelligence_map_of_content_curator_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceMapOfContentCurator,
    "C3I Intelligence Map Of Content Curator Agent",
    C3iIntelligence,
    2,
    "#fractal-l2",
    Active,
    10_848,
    32,
    Block,
    "Curates Maps of Content (MOCs) unifying knowledge clusters",
    "MOC Curation",
    "Knowledge Clustering",
    "SIL-4 / High Availability",
    ["SC-ZK-004"],
  )
}

pub fn build_intelligence_episodic_memory_indexer_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceEpisodicMemoryIndexer,
    "C3I Intelligence Episodic Memory Indexer Agent",
    C3iIntelligence,
    2,
    "#fractal-l2",
    Active,
    10_880,
    32,
    Block,
    "Indexes episodic conversation transcripts and task journals",
    "Episodic Memory",
    "Transcript Indexing",
    "SIL-4 / High Availability",
    ["SC-ZK-005"],
  )
}

pub fn build_intelligence_bidirectional_link_resolver_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceBidirectionalLinkResolver,
    "C3I Intelligence Bidirectional Link Resolver Agent",
    C3iIntelligence,
    2,
    "#fractal-l2",
    Active,
    10_912,
    32,
    Drop,
    "Resolves bidirectional [[zk:...]] and [[wiki:...]] links",
    "Link Resolution",
    "Graph Connectivity",
    "SIL-4 / High Availability",
    ["SC-ZK-006"],
  )
}

pub fn build_intelligence_fractal_tag_taxonomist_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceFractalTagTaxonomist,
    "C3I Intelligence Fractal Tag Taxonomist Agent",
    C3iIntelligence,
    2,
    "#fractal-l2",
    Active,
    10_944,
    32,
    Drop,
    "Enforces standardized fractal tags (#fractal-l0..#fractal-l9)",
    "Tag Taxonomy",
    "Fractal Classification",
    "SIL-4 / High Availability",
    ["SC-ZK-007"],
  )
}

pub fn build_intelligence_knowledge_decay_detector_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceKnowledgeDecayDetector,
    "C3I Intelligence Knowledge Decay Detector Agent",
    C3iIntelligence,
    2,
    "#fractal-l2",
    Active,
    10_976,
    32,
    Drop,
    "Detects stale documentation and unverified claims over time",
    "Knowledge Hygiene",
    "Decay Detection",
    "SIL-4 / High Availability",
    ["SC-ZK-008"],
  )
}

pub fn build_sdlc_ontology_infranodus_synthesizer_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcOntologyInfranodusSynthesizer,
    "C3I Intelligence Ontology Infranodus Synthesizer Agent",
    C3iIntelligence,
    3,
    "#fractal-l3",
    Active,
    11_008,
    32,
    Block,
    "Synthesizes RDF/OWL ontological graphs and text networks",
    "Ontology Synthesis",
    "Infranodus Graphs",
    "SIL-5 / Safety Critical",
    ["SC-ONTO-001"],
  )
}

pub fn build_verification_infranodus_centrality_auditor_spec() -> AgentTypeSpec {
  build_spec_record(
    VerificationInfranodusCentralityAuditor,
    "C3I Intelligence Infranodus Centrality Auditor Agent",
    C3iIntelligence,
    3,
    "#fractal-l3",
    Active,
    11_040,
    32,
    Assert,
    "Knowledge graph network centrality and structural gap detection",
    "Graph Topology",
    "Centrality & Gaps",
    "SIL-5 / Safety Critical",
    ["SC-ONTO-004"],
  )
}

pub fn build_sdlc_semantic_vector_embedding_spec() -> AgentTypeSpec {
  build_spec_record(
    SdlcSemanticVectorEmbedding,
    "C3I Intelligence Semantic Vector Embedding Agent",
    C3iIntelligence,
    3,
    "#fractal-l3",
    Active,
    11_072,
    32,
    Drop,
    "Dense vector embedding and semantic retrieval over knowledge",
    "Vector Search",
    "Dense Embeddings",
    "SIL-4 / High Availability",
    ["SC-ADK-013"],
  )
}

pub fn build_intelligence_rdf_owl_ontology_builder_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceRdfOwlOntologyBuilder,
    "C3I Intelligence RDF OWL Ontology Builder Agent",
    C3iIntelligence,
    3,
    "#fractal-l3",
    Active,
    11_104,
    32,
    Block,
    "Compiles living ontologies into W3C RDF/OWL schemas",
    "RDF/OWL Ontologies",
    "Ontology Engineering",
    "SIL-5 / Safety Critical",
    ["SC-ONTO-002"],
  )
}

pub fn build_intelligence_knowledge_graph_harmonizer_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceKnowledgeGraphHarmonizer,
    "C3I Intelligence Knowledge Graph Harmonizer Agent",
    C3iIntelligence,
    3,
    "#fractal-l3",
    Active,
    11_136,
    32,
    Block,
    "Harmonizes entity relationships and eliminates semantic cycles",
    "Knowledge Graphs",
    "Graph Harmonization",
    "SIL-5 / Safety Critical",
    ["SC-ONTO-005"],
  )
}

pub fn build_intelligence_concept_lattice_miner_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceConceptLatticeMiner,
    "C3I Intelligence Concept Lattice Miner Agent",
    C3iIntelligence,
    3,
    "#fractal-l3",
    Active,
    11_168,
    32,
    Block,
    "Mines formal concept analysis (FCA) Galois lattices",
    "Formal Concept Analysis",
    "Lattice Mining",
    "SIL-5 / Safety Critical",
    ["SC-ONTO-006"],
  )
}

pub fn build_intelligence_semantic_triplestore_custodian_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceSemanticTriplestoreCustodian,
    "C3I Intelligence Semantic Triplestore Custodian Agent",
    C3iIntelligence,
    3,
    "#fractal-l3",
    Active,
    11_200,
    32,
    Block,
    "Manages SQLite-backed immutable triple storage",
    "Triplestore",
    "Knowledge Storage",
    "SIL-4 / High Availability",
    ["SC-ONTO-007"],
  )
}

pub fn build_intelligence_taxonomy_graph_traverser_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceTaxonomyGraphTraverser,
    "C3I Intelligence Taxonomy Graph Traverser Agent",
    C3iIntelligence,
    3,
    "#fractal-l3",
    Active,
    11_232,
    32,
    Drop,
    "Executes sub-millisecond SPARQL-like queries over taxonomy",
    "Graph Traversals",
    "Query Execution",
    "SIL-4 / High Availability",
    ["SC-ONTO-008"],
  )
}

pub fn build_cognitive_ooda_intent_spec() -> AgentTypeSpec {
  build_spec_record(
    CognitiveOodaIntent,
    "C3I Intelligence Cognitive OODA Intent Arbiter Agent",
    C3iIntelligence,
    4,
    "#fractal-l4",
    Active,
    11_264,
    32,
    Assert,
    "Executes high-level Observe-Orient-Decide-Act intent calculus",
    "Cognitive Architecture",
    "OODA Intent Loop",
    "SIL-5 / Safety Critical",
    ["SC-FPP-022"],
  )
}

pub fn build_intelligence_ooda_loop_orchestrator_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceOodaLoopOrchestrator,
    "C3I Intelligence OODA Loop Orchestrator Agent",
    C3iIntelligence,
    4,
    "#fractal-l4",
    Active,
    11_296,
    32,
    Assert,
    "Orchestrates multi-layer OODA loops across the entire swarm",
    "OODA Orchestration",
    "Cognitive Loops",
    "SIL-5 / Safety Critical",
    ["SC-OODA-001"],
  )
}

pub fn build_intelligence_observe_sensor_aggregator_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceObserveSensorAggregator,
    "C3I Intelligence Observe Sensor Aggregator Agent",
    C3iIntelligence,
    4,
    "#fractal-l4",
    Active,
    11_328,
    32,
    Drop,
    "Aggregates multi-source sensory and telemetry observations",
    "Observation",
    "Sensor Aggregation",
    "SIL-4 / High Availability",
    ["SC-OODA-002"],
  )
}

pub fn build_intelligence_orient_context_synthesizer_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceOrientContextSynthesizer,
    "C3I Intelligence Orient Context Synthesizer Agent",
    C3iIntelligence,
    4,
    "#fractal-l4",
    Active,
    11_360,
    32,
    Block,
    "Synthesizes situational models and contextual frames",
    "Orientation",
    "Context Framing",
    "SIL-5 / Safety Critical",
    ["SC-OODA-003"],
  )
}

pub fn build_intelligence_decide_strategy_selector_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceDecideStrategySelector,
    "C3I Intelligence Decide Strategy Selector Agent",
    C3iIntelligence,
    4,
    "#fractal-l4",
    Active,
    11_392,
    32,
    Assert,
    "Selects optimal operational strategies under Pareto constraints",
    "Decision Making",
    "Strategy Selection",
    "SIL-5 / Safety Critical",
    ["SC-OODA-004"],
  )
}

pub fn build_intelligence_actuator_task_dispatcher_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceActuatorTaskDispatcher,
    "C3I Intelligence Actuator Task Dispatcher Agent",
    C3iIntelligence,
    4,
    "#fractal-l4",
    Active,
    11_424,
    32,
    Block,
    "Dispatches chosen actions to concrete actor mailboxes",
    "Actuation",
    "Task Dispatching",
    "SIL-5 / Safety Critical",
    ["SC-OODA-005"],
  )
}

pub fn build_intelligence_reasoning_graph_expander_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceReasoningGraphExpander,
    "C3I Intelligence Reasoning Graph Expander Agent",
    C3iIntelligence,
    4,
    "#fractal-l4",
    Active,
    11_456,
    32,
    Block,
    "Expands tree-of-thought and graph-of-thought search spaces",
    "Reasoning Trees",
    "Search Expansion",
    "SIL-5 / Safety Critical",
    ["SC-REASON-002"],
  )
}

pub fn build_intelligence_hypothesis_testing_agent_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceHypothesisTestingAgent,
    "C3I Intelligence Hypothesis Testing Agent",
    C3iIntelligence,
    4,
    "#fractal-l4",
    Active,
    11_488,
    32,
    Assert,
    "Evaluates and disproves competing explanatory hypotheses",
    "Hypothesis Testing",
    "Epistemic Evaluation",
    "SIL-5 / Safety Critical",
    ["SC-REASON-003"],
  )
}

pub fn build_intelligence_max_daemon_supervisor_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceMaxDaemonSupervisor,
    "C3I Intelligence MAX Daemon Supervisor Agent",
    C3iIntelligence,
    5,
    "#fractal-l5",
    Active,
    11_520,
    32,
    Assert,
    "Supervises isolated Modular MAX Python inference daemon",
    "MAX Supervision",
    "Inference Process Isolation",
    "SIL-5 / Safety Critical",
    ["SC-MAX-002"],
  )
}

pub fn build_intelligence_mojo_kernel_optimizer_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceMojoKernelOptimizer,
    "C3I Intelligence Mojo Kernel Optimizer Agent",
    C3iIntelligence,
    5,
    "#fractal-l5",
    Active,
    11_552,
    32,
    Block,
    "Compiles accelerated SIMD/GPU kernels in Modular Mojo",
    "Mojo Acceleration",
    "Kernel Optimization",
    "SIL-5 / Safety Critical",
    ["SC-MAX-003"],
  )
}

pub fn build_intelligence_json_rpc_stdio_pipe_bridge_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceJsonRpcStdioPipeBridge,
    "C3I Intelligence JSON RPC Stdio Pipe Bridge Agent",
    C3iIntelligence,
    5,
    "#fractal-l5",
    Active,
    11_584,
    32,
    Block,
    "Length-delimited JSON-RPC pipe bridge across OTP and MAX",
    "RPC IPC Bridge",
    "Stdio Serialization",
    "SIL-5 / Safety Critical",
    ["SC-MAX-004"],
  )
}

pub fn build_intelligence_process_isolation_enforcer_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceProcessIsolationEnforcer,
    "C3I Intelligence Process Isolation Enforcer Agent",
    C3iIntelligence,
    5,
    "#fractal-l5",
    Active,
    11_616,
    32,
    Assert,
    "Quarantines Python runtime crashes from BEAM crash domains",
    "Crash Quarantine",
    "Fault Boundary Enforcer",
    "SIL-6 / Sovereign Core",
    ["SC-MAX-005"],
  )
}

pub fn build_intelligence_batch_inference_dispatcher_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceBatchInferenceDispatcher,
    "C3I Intelligence Batch Inference Dispatcher Agent",
    C3iIntelligence,
    5,
    "#fractal-l5",
    Active,
    11_648,
    32,
    Block,
    "Batches concurrent agent embedding and completion requests",
    "Inference Batching",
    "Throughput Optimization",
    "SIL-4 / High Availability",
    ["SC-MAX-006"],
  )
}

pub fn build_intelligence_token_streaming_pacer_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceTokenStreamingPacer,
    "C3I Intelligence Token Streaming Pacer Agent",
    C3iIntelligence,
    5,
    "#fractal-l5",
    Active,
    11_680,
    32,
    Drop,
    "Paces token streaming events to Lustre WebUI and TUI",
    "Token Streaming",
    "Event Pacing",
    "SIL-4 / High Availability",
    ["SC-UI-005"],
  )
}

pub fn build_intelligence_model_weight_quarantine_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceModelWeightQuarantine,
    "C3I Intelligence Model Weight Quarantine Agent",
    C3iIntelligence,
    5,
    "#fractal-l5",
    Active,
    11_712,
    32,
    Assert,
    "Verifies SHA-256 digests and integrity of local model weights",
    "Weight Verification",
    "Model Integrity",
    "SIL-6 / Sovereign Core",
    ["SC-MAX-007"],
  )
}

pub fn build_intelligence_slm_local_cache_custodian_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceSlmLocalCacheCustodian,
    "C3I Intelligence SLM Local Cache Custodian Agent",
    C3iIntelligence,
    5,
    "#fractal-l5",
    Active,
    11_744,
    32,
    Drop,
    "Caches frequently computed inference embeddings in RAM",
    "Inference Cache",
    "Embedding Retention",
    "SIL-4 / High Availability",
    ["SC-MAX-008"],
  )
}

pub fn build_intelligence_swarm_consensus_director_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceSwarmConsensusDirector,
    "C3I Intelligence Swarm Consensus Director Agent",
    C3iIntelligence,
    6,
    "#fractal-l6",
    Active,
    11_776,
    32,
    Assert,
    "Coordinates multi-agent consensus protocols across swarms",
    "Swarm Consensus",
    "Director Orchestration",
    "SIL-5 / Safety Critical",
    ["SC-SWARM-001"],
  )
}

pub fn build_intelligence_role_specialization_matcher_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceRoleSpecializationMatcher,
    "C3I Intelligence Role Specialization Matcher Agent",
    C3iIntelligence,
    6,
    "#fractal-l6",
    Active,
    11_808,
    32,
    Block,
    "Matches complex task requirements to specialized agent skills",
    "Role Matching",
    "Skill Allocation",
    "SIL-4 / High Availability",
    ["SC-SWARM-002"],
  )
}

pub fn build_intelligence_task_decomposition_planner_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceTaskDecompositionPlanner,
    "C3I Intelligence Task Decomposition Planner Agent",
    C3iIntelligence,
    6,
    "#fractal-l6",
    Active,
    11_840,
    32,
    Block,
    "Decomposes broad human directives into atomic agent work slices",
    "Task Planning",
    "Decomposition Synthesis",
    "SIL-5 / Safety Critical",
    ["SC-SWARM-003"],
  )
}

pub fn build_intelligence_agent_peer_messenger_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceAgentPeerMessenger,
    "C3I Intelligence Agent Peer Messenger Agent",
    C3iIntelligence,
    6,
    "#fractal-l6",
    Active,
    11_872,
    32,
    Drop,
    "Routes peer-to-peer asynchronous messages across agent mailboxes",
    "A2A Messaging",
    "Peer Dispatch",
    "SIL-4 / High Availability",
    ["SC-SWARM-004"],
  )
}

pub fn build_intelligence_swarm_conflict_mediator_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceSwarmConflictMediator,
    "C3I Intelligence Swarm Conflict Mediator Agent",
    C3iIntelligence,
    6,
    "#fractal-l6",
    Active,
    11_904,
    32,
    Assert,
    "Resolves contradictory recommendations between specialized agents",
    "Conflict Mediation",
    "Arbitration Protocol",
    "SIL-5 / Safety Critical",
    ["SC-SWARM-005"],
  )
}

pub fn build_intelligence_collective_memory_sync_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceCollectiveMemorySync,
    "C3I Intelligence Collective Memory Sync Agent",
    C3iIntelligence,
    6,
    "#fractal-l6",
    Active,
    11_936,
    32,
    Block,
    "Synchronizes shared blackboard working memory across agents",
    "Collective Memory",
    "Shared Blackboard",
    "SIL-5 / Safety Critical",
    ["SC-SWARM-006"],
  )
}

pub fn build_intelligence_autonomous_negotiation_broker_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceAutonomousNegotiationBroker,
    "C3I Intelligence Autonomous Negotiation Broker Agent",
    C3iIntelligence,
    6,
    "#fractal-l6",
    Active,
    11_968,
    32,
    Block,
    "Brokers resource negotiation between competing background tasks",
    "Task Negotiation",
    "Resource Allocation",
    "SIL-4 / High Availability",
    ["SC-SWARM-007"],
  )
}

pub fn build_intelligence_federated_prompt_orchestrator_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceFederatedPromptOrchestrator,
    "C3I Intelligence Federated Prompt Orchestrator Agent",
    C3iIntelligence,
    6,
    "#fractal-l6",
    Active,
    12_000,
    32,
    Block,
    "Orchestrates multi-agent prompts across vendor platforms",
    "Prompt Federation",
    "Multi-Agent Orchestration",
    "SIL-5 / Safety Critical",
    ["SC-SWARM-008"],
  )
}

pub fn build_intelligence_master_encyclopedia_indexer_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceMasterEncyclopediaIndexer,
    "C3I Intelligence Master Encyclopedia Indexer Agent",
    C3iIntelligence,
    7,
    "#fractal-l7",
    Active,
    12_032,
    32,
    Block,
    "Indexes the master encyclopedia tome across wiki and ZK",
    "Encyclopedia Index",
    "Master Knowledge Tome",
    "SIL-4 / High Availability",
    ["SC-KM-003"],
  )
}

pub fn build_intelligence_corpus_transclusion_engine_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceCorpusTransclusionEngine,
    "C3I Intelligence Corpus Transclusion Engine Agent",
    C3iIntelligence,
    7,
    "#fractal-l7",
    Active,
    12_064,
    32,
    Block,
    "Transcludes documentation fragments across the KM triad",
    "Transclusion Engine",
    "Corpus Integration",
    "SIL-4 / High Availability",
    ["SC-KM-004"],
  )
}

pub fn build_intelligence_living_catalog_publisher_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceLivingCatalogPublisher,
    "C3I Intelligence Living Catalog Publisher Agent",
    C3iIntelligence,
    7,
    "#fractal-l7",
    Active,
    12_096,
    32,
    Block,
    "Publishes living SQLite catalogs to web views and Markdown docs",
    "Catalog Publishing",
    "Living Documentation",
    "SIL-4 / High Availability",
    ["SC-KM-005"],
  )
}

pub fn build_intelligence_cross_platform_knowledge_mirror_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceCrossPlatformKnowledgeMirror,
    "C3I Intelligence Cross Platform Knowledge Mirror Agent",
    C3iIntelligence,
    7,
    "#fractal-l7",
    Active,
    12_128,
    32,
    Block,
    "Mirrors knowledge artifacts to brain directories and remote peers",
    "Artifact Mirroring",
    "Peer Synchronization",
    "SIL-4 / High Availability",
    ["SC-KM-006"],
  )
}

pub fn build_intelligence_sovereign_review_synthesizer_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceSovereignReviewSynthesizer,
    "C3I Intelligence Sovereign Review Synthesizer Agent",
    C3iIntelligence,
    7,
    "#fractal-l7",
    Active,
    12_160,
    32,
    Assert,
    "Synthesizes review certificates for AGY, Claude, and Codex",
    "Sovereign Synthesis",
    "Review Ratification",
    "SIL-6 / Sovereign Core",
    ["SC-SOV-002"],
  )
}

pub fn build_intelligence_knowledge_archival_vault_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceKnowledgeArchivalVault,
    "C3I Intelligence Knowledge Archival Vault Agent",
    C3iIntelligence,
    7,
    "#fractal-l7",
    Active,
    12_192,
    32,
    Assert,
    "Secures immutable historical snapshots with cryptographic seals",
    "Knowledge Vault",
    "Immutable Archival",
    "SIL-6 / Sovereign Core",
    ["SC-KM-007"],
  )
}

pub fn build_intelligence_epistemic_certainty_evaluator_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceEpistemicCertaintyEvaluator,
    "C3I Intelligence Epistemic Certainty Evaluator Agent",
    C3iIntelligence,
    7,
    "#fractal-l7",
    Active,
    12_224,
    32,
    Assert,
    "Evaluates epistemic confidence and flags uncertain assertions",
    "Epistemic Safety",
    "Certainty Calibration",
    "SIL-5 / Safety Critical",
    ["SC-FACT-002"],
  )
}

pub fn build_intelligence_unified_site_navigation_curator_spec() -> AgentTypeSpec {
  build_spec_record(
    IntelligenceUnifiedSiteNavigationCurator,
    "C3I Intelligence Unified Site Navigation Curator Agent",
    C3iIntelligence,
    7,
    "#fractal-l7",
    Active,
    12_256,
    32,
    Block,
    "Curates uniform cohesive navigation across all 35 web screens",
    "Site Navigation",
    "Uniform Navigation",
    "SIL-4 / High Availability",
    ["SC-ROUTE-002"],
  )
}

pub fn all_agent_types() -> List(AgentTypeSpec) {
  [
    build_sdlc_architecture_synthesizer_spec(),
    build_sdlc_hitl_gatekeeper_spec(),
    build_sdlc_constitutional_specifier_spec(),
    build_sdlc_policy_rule_compiler_spec(),
    build_sdlc_two_key_authorization_spec(),
    build_sdlc_governance_charter_auditor_spec(),
    build_sdlc_license_compliance_checker_spec(),
    build_sdlc_monorepo_boundary_enforcer_spec(),
    build_sdlc_contract_code_generator_spec(),
    build_sdlc_open_api_schema_generator_spec(),
    build_sdlc_gospel_ortac_specification_spec(),
    build_sdlc_ast_transformer_spec(),
    build_sdlc_type_inference_bridge_spec(),
    build_sdlc_lexer_parser_generator_spec(),
    build_sdlc_bytecode_instruction_emitter_spec(),
    build_sdlc_symbol_table_manager_spec(),
    build_parameter_database_spec(),
    build_sdlc_static_analysis_auditor_spec(),
    build_sdlc_design_system_figma_bridge_spec(),
    build_sdlc_component_schema_synthesizer_spec(),
    build_sdlc_prop_binding_validator_spec(),
    build_sdlc_widget_palette_registry_spec(),
    build_sdlc_data_model_normalizer_spec(),
    build_sdlc_interface_contract_binder_spec(),
    build_mission_phase_hsm_spec(),
    build_payload_science_spec(),
    build_sdlc_tool_registry_mcp_bridge_spec(),
    build_sdlc_hierarchical_state_composer_spec(),
    build_sdlc_lca_transition_resolver_spec(),
    build_sdlc_guard_action_synthesizer_spec(),
    build_sdlc_orthogonal_region_coordinator_spec(),
    build_sdlc_signal_dispatch_matrix_spec(),
    build_appup_hot_reload_coordinator_spec(),
    build_sdlc_release_packaging_orchestrator_spec(),
    build_sdlc_session_memory_replay_spec(),
    build_sdlc_fork_join_parallel_branch_spec(),
    build_sdlc_feature_slice_composer_spec(),
    build_sdlc_api_endpoint_packager_spec(),
    build_sdlc_artifact_tarball_bundler_spec(),
    build_sdlc_semantic_version_manager_spec(),
    build_km_sync_spec(),
    build_slm_bif_inference_spec(),
    build_fast_pattern_filter_spec(),
    build_sdlc_graph_workflow_orchestrator_spec(),
    build_sdlc_prompt_template_injector_spec(),
    build_sdlc_state_graph_cycle_resolver_spec(),
    build_sdlc_denotational_semantics_mapper_spec(),
    build_sdlc_template_renderer_spec(),
    build_sdlc_documentation_transclusion_sync_spec(),
    build_sdlc_a2a_multi_agent_delegation_spec(),
    build_sdlc_notion_living_ontology_spec(),
    build_sdlc_swarm_workflow_scheduler_spec(),
    build_sdlc_agent_interchange_protocol_spec(),
    build_sdlc_dialogue_turn_orchestrator_spec(),
    build_sdlc_context_window_manager_spec(),
    build_sdlc_collaborative_task_router_spec(),
    build_sdlc_algebraic_atlas_router_spec(),
    build_sdlc_route_table_html_algebra_spec(),
    build_living_meta_evolution_spec(),
    build_dynamic_agent_bytecode_synthesizer_spec(),
    build_sdlc_evolutionary_loop_governor_spec(),
    build_sdlc_cross_repository_synchronizer_spec(),
    build_sdlc_continuous_deployment_pipeline_spec(),
    build_sdlc_artifact_registry_mirror_spec(),
    build_sre_plugin_policy_guardrail_spec(),
    build_sre_rete_fail_closed_admission_spec(),
    build_sre_stpa_safety_controller_spec(),
    build_sre_content_safety_sanitizer_spec(),
    build_sre_emergency_jidoka_interlock_spec(),
    build_sre_constitutional_quorum_watcher_spec(),
    build_sre_fail_closed_circuit_governor_spec(),
    build_sre_zero_trust_admission_filter_spec(),
    build_storage_custodian_spec(),
    build_deterministic_reduction_scheduler_spec(),
    build_linear_arena_reclaimer_spec(),
    build_sre_cpu_budget_governor_spec(),
    build_sre_sandboxed_tool_isolation_spec(),
    build_sre_memory_leak_detector_spec(),
    build_sre_page_fault_rate_controller_spec(),
    build_sre_garbage_collection_pacer_spec(),
    build_lockless_hamt_storage_spec(),
    build_tagged_pointer_guard_spec(),
    build_hierarchical_timer_wheel_spec(),
    build_sre_freshness_monitor_spec(),
    build_sre_open_telemetry_span_tracer_spec(),
    build_sre_dead_mans_switch_watchdog_spec(),
    build_sre_heartbeat_liveness_cluster_spec(),
    build_sre_health_entropy_aggregator_spec(),
    build_crash_wal_replay_spec(),
    build_sre_sa_plan_task_leaser_spec(),
    build_sre_database_actor_wal_serializer_spec(),
    build_sre_mailbox_backpressure_controller_spec(),
    build_sre_actor_deadlock_resolver_spec(),
    build_sre_message_queue_drainer_spec(),
    build_sre_priority_queue_fair_scheduler_spec(),
    build_sre_transaction_saga_compensator_spec(),
    build_sre_sentinel_spec(),
    build_cybernetic_immune_spec(),
    build_sre_lyapunov_trend_detector_spec(),
    build_sre_chaos_fault_injector_spec(),
    build_sre_runner_lifecycle_hook_supervisor_spec(),
    build_sre_time_travel_state_rollback_spec(),
    build_sre_token_quota_rate_limiter_spec(),
    build_sre_ceph_osd_disk_safety_guard_spec(),
    build_sre_forecast_predictive_preflight_spec(),
    build_sre_endocrine_hormone_balancer_spec(),
    build_sre_adaptive_rate_controller_spec(),
    build_sre_windowed_trend_analyzer_spec(),
    build_sre_dynamic_capacity_planner_spec(),
    build_sre_metabolic_governor_spec(),
    build_sre_degraded_mode_orchestrator_spec(),
    build_sre_load_shedding_governor_spec(),
    build_swarm_mesh_spec(),
    build_epidemic_gossip_spec(),
    build_sre_session_shard_rebalancer_spec(),
    build_sre_prajna_circuit_breaker_spec(),
    build_sre_mesh_partition_healer_spec(),
    build_sre_cascading_failure_shield_spec(),
    build_sre_gossip_membership_cluster_spec(),
    build_sre_consensus_consul_elector_spec(),
    build_ground_gateway_spec(),
    build_sre_crdt_version_vector_sync_spec(),
    build_sre_cast_incident_investigator_spec(),
    build_sre_post_mortem_rca_synthesizer_spec(),
    build_sre_federation_gateway_proxy_spec(),
    build_sre_telemetry_backplane_publisher_spec(),
    build_sre_disaster_recovery_sequencer_spec(),
    build_sre_audit_trail_ledger_signer_spec(),
    build_constitutional_guardian_spec(),
    build_formal_oracle_spec(),
    build_hardware_drive_interlock_spec(),
    build_rocha_semiotic_cut_guard_spec(),
    build_verification_checklist_auditor_spec(),
    build_verification_math_gate_certifier_spec(),
    build_verification_tcm_coordinate_protector_spec(),
    build_verification_zero_muda_purity_enforcer_spec(),
    build_deterministic_flight_controller_spec(),
    build_substrate_reactor_spec(),
    build_verification_pinned_otp_differential_spec(),
    build_verification_gospel_ortac_runtime_monitor_spec(),
    build_verification_smt_negation_auditor_spec(),
    build_verification_z3_unsat_validator_spec(),
    build_verification_negative_control_verifier_spec(),
    build_verification_typestate_invariant_checker_spec(),
    build_avionics_telemetry_spec(),
    build_cockpit_telemetry_spec(),
    build_verification_browser_matrix_tester_spec(),
    build_verification_mutation_adequacy_killer_spec(),
    build_verification_tdd_law_enforcer_spec(),
    build_verification_red_green_revert_judge_spec(),
    build_verification_flaccid_law_detector_spec(),
    build_verification_fixture_totality_auditor_spec(),
    build_mcdc_avionics_tap_spec(),
    build_differential_bisimulation_spec(),
    build_verification_nine_modality_executor_spec(),
    build_verification_tool_schema_conformance_spec(),
    build_verification_bdd_scenario_runner_spec(),
    build_verification_state_transition_asserter_spec(),
    build_verification_trace_equivalence_judge_spec(),
    build_verification_mcdc_branch_coverage_auditor_spec(),
    build_verification_playwright_control_auditor_spec(),
    build_verification_multi_turn_dialogue_verifier_spec(),
    build_verification_property_generator_fuzzer_spec(),
    build_verification_generative_shrink_engine_spec(),
    build_verification_boundary_value_tester_spec(),
    build_verification_seeded_random_replayer_spec(),
    build_verification_corpus_module_executor_spec(),
    build_verification_ast_mutant_synthesizer_spec(),
    build_verification_adk_eval_benchmark_spec(),
    build_verification_trajectory_replay_certifier_spec(),
    build_verification_hallucination_scorer_spec(),
    build_verification_entropy_calculator_spec(),
    build_verification_divergence_metric_scorer_spec(),
    build_verification_factual_grounding_auditor_spec(),
    build_verification_reasoning_step_validator_spec(),
    build_verification_context_retention_verifier_spec(),
    build_verification_simulation_environment_spec(),
    build_verification_actor_bisimulation_tester_spec(),
    build_verification_concurrency_race_detector_spec(),
    build_verification_model_checker_bridge_spec(),
    build_verification_linearizability_oracle_spec(),
    build_verification_distributed_partition_tester_spec(),
    build_verification_message_loss_simulator_spec(),
    build_verification_clock_drift_chaos_tester_spec(),
    build_verification_sheaf_gluing_harmonizer_spec(),
    build_verification_lean_formal_proof_oracle_spec(),
    build_verification_quint_parity_frontier_oracle_spec(),
    build_verification_master_checklist_gatekeeper_spec(),
    build_verification_parity_ratchet_enforcer_spec(),
    build_verification_baseline_release_gatekeeper_spec(),
    build_verification_formal_evidence_archiver_spec(),
    build_verification_sovereign_consensus_ratifier_spec(),
    build_intelligence_rocha_cut_validator_spec(),
    build_intelligence_code_biology_boundary_guard_spec(),
    build_intelligence_symbol_matter_decoupler_spec(),
    build_intelligence_semiotic_closure_auditor_spec(),
    build_intelligence_semantic_anchor_protector_spec(),
    build_intelligence_biomorphic_morphogen_router_spec(),
    build_intelligence_cybernetic_feedback_harmonizer_spec(),
    build_intelligence_metabolic_homeostasis_tracker_spec(),
    build_intelligence_sheaf_cohomology_engine_spec(),
    build_intelligence_local_section_extractor_spec(),
    build_intelligence_presheaf_functor_mapper_spec(),
    build_intelligence_gluing_morphism_synthesizer_spec(),
    build_intelligence_restriction_map_validator_spec(),
    build_intelligence_cech_complex_builder_spec(),
    build_intelligence_spectral_sequence_analyzer_spec(),
    build_intelligence_category_theory_bridge_spec(),
    build_verification_zk_km_knowledge_currency_spec(),
    build_intelligence_zettelkasten_librarian_spec(),
    build_intelligence_permanent_adr_custodian_spec(),
    build_intelligence_map_of_content_curator_spec(),
    build_intelligence_episodic_memory_indexer_spec(),
    build_intelligence_bidirectional_link_resolver_spec(),
    build_intelligence_fractal_tag_taxonomist_spec(),
    build_intelligence_knowledge_decay_detector_spec(),
    build_sdlc_ontology_infranodus_synthesizer_spec(),
    build_verification_infranodus_centrality_auditor_spec(),
    build_sdlc_semantic_vector_embedding_spec(),
    build_intelligence_rdf_owl_ontology_builder_spec(),
    build_intelligence_knowledge_graph_harmonizer_spec(),
    build_intelligence_concept_lattice_miner_spec(),
    build_intelligence_semantic_triplestore_custodian_spec(),
    build_intelligence_taxonomy_graph_traverser_spec(),
    build_cognitive_ooda_intent_spec(),
    build_intelligence_ooda_loop_orchestrator_spec(),
    build_intelligence_observe_sensor_aggregator_spec(),
    build_intelligence_orient_context_synthesizer_spec(),
    build_intelligence_decide_strategy_selector_spec(),
    build_intelligence_actuator_task_dispatcher_spec(),
    build_intelligence_reasoning_graph_expander_spec(),
    build_intelligence_hypothesis_testing_agent_spec(),
    build_intelligence_max_daemon_supervisor_spec(),
    build_intelligence_mojo_kernel_optimizer_spec(),
    build_intelligence_json_rpc_stdio_pipe_bridge_spec(),
    build_intelligence_process_isolation_enforcer_spec(),
    build_intelligence_batch_inference_dispatcher_spec(),
    build_intelligence_token_streaming_pacer_spec(),
    build_intelligence_model_weight_quarantine_spec(),
    build_intelligence_slm_local_cache_custodian_spec(),
    build_intelligence_swarm_consensus_director_spec(),
    build_intelligence_role_specialization_matcher_spec(),
    build_intelligence_task_decomposition_planner_spec(),
    build_intelligence_agent_peer_messenger_spec(),
    build_intelligence_swarm_conflict_mediator_spec(),
    build_intelligence_collective_memory_sync_spec(),
    build_intelligence_autonomous_negotiation_broker_spec(),
    build_intelligence_federated_prompt_orchestrator_spec(),
    build_intelligence_master_encyclopedia_indexer_spec(),
    build_intelligence_corpus_transclusion_engine_spec(),
    build_intelligence_living_catalog_publisher_spec(),
    build_intelligence_cross_platform_knowledge_mirror_spec(),
    build_intelligence_sovereign_review_synthesizer_spec(),
    build_intelligence_knowledge_archival_vault_spec(),
    build_intelligence_epistemic_certainty_evaluator_spec(),
    build_intelligence_unified_site_navigation_curator_spec(),
  ]
}

pub fn find_agent_type_spec(kind: AgentKind) -> Result(AgentTypeSpec, Nil) {
  let all = all_agent_types()
  list.find(all, fn(spec) { spec.kind == kind })
}

pub fn sdlc_agents() -> List(AgentTypeSpec) {
  list.filter(all_agent_types(), fn(s) { s.c3i_system == C3iSdlc })
}

pub fn sre_agents() -> List(AgentTypeSpec) {
  list.filter(all_agent_types(), fn(s) { s.c3i_system == C3iSre })
}

pub fn verification_agents() -> List(AgentTypeSpec) {
  list.filter(all_agent_types(), fn(s) { s.c3i_system == C3iVerification })
}

pub fn intelligence_agents() -> List(AgentTypeSpec) {
  list.filter(all_agent_types(), fn(s) { s.c3i_system == C3iIntelligence })
}

pub fn filter_by_c3i_system(
  specs: List(AgentTypeSpec),
  sys: C3iSystem,
) -> List(AgentTypeSpec) {
  list.filter(specs, fn(s) { s.c3i_system == sys })
}

pub fn verify_agent_base_id_disjointness(specs: List(AgentTypeSpec)) -> Bool {
  let intervals =
    list.map(specs, fn(s) { #(s.name, s.base_id, s.base_id + s.id_span) })

  check_pairwise_intervals(intervals)
}

fn check_pairwise_intervals(intervals: List(#(String, Int, Int))) -> Bool {
  case intervals {
    [] -> True
    [_] -> True
    [#(_name1, low1, high1), ..rest] -> {
      let overlaps =
        list.any(rest, fn(pair) {
          let #(_name2, low2, high2) = pair
          let max_low = int.max(low1, low2)
          let min_high = int.min(high1, high2)
          max_low < min_high
        })
      case overlaps {
        True -> False
        False -> check_pairwise_intervals(rest)
      }
    }
  }
}

pub fn encode_agent_type_spec_json(spec: AgentTypeSpec) -> json.Json {
  json.object([
    #("kind", json.string(agent_kind_to_string(spec.kind))),
    #("name", json.string(spec.name)),
    #("c3i_system", json.string(c3i_system_to_string(spec.c3i_system))),
    #("fractal_layer", json.int(spec.fractal_layer)),
    #("fractal_tag", json.string(spec.fractal_tag)),
    #("base_id", json.int(spec.base_id)),
    #("id_span", json.int(spec.id_span)),
    #("description", json.string(spec.description)),
    #("operational_domain", json.string(spec.operational_domain)),
    #("sdlc_phase", json.string(spec.sdlc_phase)),
    #("sre_resilience_tier", json.string(spec.sre_resilience_tier)),
    #(
      "evidence_contracts",
      json.array(spec.evidence_contracts, of: json.string),
    ),
  ])
}

pub fn encode_agent_catalog_json(specs: List(AgentTypeSpec)) -> String {
  let sdlc_count = list.count(specs, fn(s) { s.c3i_system == C3iSdlc })
  let sre_count = list.count(specs, fn(s) { s.c3i_system == C3iSre })
  let ver_count = list.count(specs, fn(s) { s.c3i_system == C3iVerification })
  let intel_count = list.count(specs, fn(s) { s.c3i_system == C3iIntelligence })

  json.object([
    #("status", json.string("ok")),
    #("total_agent_types", json.int(list.length(specs))),
    #("sdlc_agents_count", json.int(sdlc_count)),
    #("sre_agents_count", json.int(sre_count)),
    #("verification_agents_count", json.int(ver_count)),
    #("intelligence_agents_count", json.int(intel_count)),
    #("contract", json.string("SC-FPP-AGENT-TAXONOMY-001")),
    #("agents", json.array(specs, of: encode_agent_type_spec_json)),
  ])
  |> json.to_string
}
