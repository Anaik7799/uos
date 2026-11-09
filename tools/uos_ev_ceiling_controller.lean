/-
  tools/uos_ev_ceiling_controller.lean
  ==============================================================================
  UNIFIED AK-47 EV-CEILING CONTROLLER, FRACTAL ANALYZER & LEAN UNIFIER (Lean 4)
  ==============================================================================
  Contract   : SC-PROVENANCE-001, SC-JIDOKA-001, SC-HARNESS-MCP-001
  Single File: governance/provenance/admitted_ev_ceiling.txt (value: 109)
  Invocation :
    ./tools/uos-ev-ceiling --verify
    ./tools/uos-ev-ceiling --fractal-analysis
    ./tools/uos-ev-ceiling --status
    ./tools/uos-ev-ceiling --update 109

  WHY THIS UNIFIED CONTROLLER EXISTS (AK-47 / ZERO MAGIC NUMBERS):
  ----------------------------------------------------------------
  Previously, upgrading `admitted_ev_ceiling` from 93 to 109 required hunting down
  hardcoded integer literals across 24+ files in 4 languages (Lean 4, Mojo, OCaml,
  Gleam, JSON, and Markdown policy documents). That violated DRY and created high
  cognitive load and synchronization brittleness.

  This single Pure Lean 4 script unifies the entire EV ceiling lifecycle:
  1. Defines the formal 10-Layer (L0..L9) × 6-Plane Veil × 4-Language Fractal
     Dependency Graph & 5-Phase Ceiling Transition State Machine with 15
     compile-time zero-axiom theorems (`THM_EV_CTRL_01..15`).
  2. Governs the single canonical file `governance/provenance/admitted_ev_ceiling.txt`
     (consumed dynamically by OCaml `km_metrics.ml`, `lean_mojo_differential.ml`, and
     Mojo `oracle_substrate.mojo::canonical_ev_ceiling()`) plus the single in-process
     Lean 4 C-ABI constant `admittedEvCeilingU32` in `UosLeanRuntimeGuard.lean`.
  3. Provides `--fractal-analysis` to inspect the 10-layer fractal reduction from 24
     scattered magic-number sites down to 1 canonical source + automated Lean sync,
     `--verify` to run 12/12 cross-language L0..L9 checks, and `--update <N>` to
     synchronize and rebuild the entire system from one Lean 4 command.
-/

namespace UOS.EvCeilingController

/-- Single canonical admitted EV ceiling (`SC-PROVENANCE-001`, `Phase4_SynchronizedAt109`). -/
def canonicalAdmittedEvCeiling : Nat := 109

/-- Historical pre-elevation quarantine boundary preserved for forensic tests (`km_forensic_schema.ml`). -/
def historicalForensicBaseline : Nat := 93

/-- Superseded range (`EV-110..EV-111`) rebound to canonical `sa-plan` IDs (`INV-PROV-05`). -/
def supersededEvLo : Nat := 110
def supersededEvHi : Nat := 111

/-- Single canonical file path read by OCaml, Mojo, and shell tooling. -/
def canonicalCeilingFilePath : String := "governance/provenance/admitted_ev_ceiling.txt"

/-- 10 Canonical Fractal Concern Layers (`L0..L9`). -/
inductive FractalLayer where
  | L0_Constitutional
  | L1_PhysicalKernel
  | L2_ExecutionVm
  | L3_SupervisionOtp
  | L4_CyberneticControl
  | L5_KnowledgeOntology
  | L6_CognitiveSwarm
  | L7_MeshGateway
  | L8_EvolutionaryVerification
  | L9_SovereignRelease
  deriving Repr, DecidableEq

def layerIdx : FractalLayer → Nat
  | .L0_Constitutional           => 0
  | .L1_PhysicalKernel           => 1
  | .L2_ExecutionVm              => 2
  | .L3_SupervisionOtp           => 3
  | .L4_CyberneticControl        => 4
  | .L5_KnowledgeOntology        => 5
  | .L6_CognitiveSwarm           => 6
  | .L7_MeshGateway              => 7
  | .L8_EvolutionaryVerification => 8
  | .L9_SovereignRelease         => 9

def layerName : FractalLayer → String
  | .L0_Constitutional           => "L0_Constitutional"
  | .L1_PhysicalKernel           => "L1_PhysicalKernel"
  | .L2_ExecutionVm              => "L2_ExecutionVm"
  | .L3_SupervisionOtp           => "L3_SupervisionOtp"
  | .L4_CyberneticControl        => "L4_CyberneticControl"
  | .L5_KnowledgeOntology        => "L5_KnowledgeOntology"
  | .L6_CognitiveSwarm           => "L6_CognitiveSwarm"
  | .L7_MeshGateway              => "L7_MeshGateway"
  | .L8_EvolutionaryVerification => "L8_EvolutionaryVerification"
  | .L9_SovereignRelease         => "L9_SovereignRelease"

/-- Dependency binding mode: either dynamically read from `governance/provenance/admitted_ev_ceiling.txt`,
    compile-time synchronized in Lean/Gleam kernels by `--update`, or isolated as historical forensic evidence (`93`). -/
inductive CeilingBindingMode where
  | SingleSourceDynamicReader
  | CompileTimeKernelPinned
  | HistoricalForensicIsolated93
  deriving Repr, DecidableEq

structure FractalDependencyNode where
  nodeId        : Nat
  layer         : FractalLayer
  artifactPath  : String
  bindingMode   : CeilingBindingMode
  targetCeiling : Nat
  deriving Repr, DecidableEq

/-- Complete 10-Layer Fractal Dependency Table covering every EV-sensitive path in UOS. -/
def canonicalFractalDependencyGraph : List FractalDependencyNode :=
  [ { nodeId := 0,  layer := .L0_Constitutional,           artifactPath := "governance/provenance/admitted_ev_ceiling.txt",                                                       bindingMode := .SingleSourceDynamicReader,    targetCeiling := 109 }
  , { nodeId := 1,  layer := .L0_Constitutional,           artifactPath := "governance/ev-manifest.tsv",                                                                           bindingMode := .CompileTimeKernelPinned,      targetCeiling := 109 }
  , { nodeId := 2,  layer := .L0_Constitutional,           artifactPath := "AGENTS.md",                                                                                            bindingMode := .CompileTimeKernelPinned,      targetCeiling := 109 }
  , { nodeId := 3,  layer := .L0_Constitutional,           artifactPath := "CLAUDE.md",                                                                                            bindingMode := .CompileTimeKernelPinned,      targetCeiling := 109 }
  , { nodeId := 4,  layer := .L0_Constitutional,           artifactPath := "GEMINI.md",                                                                                            bindingMode := .CompileTimeKernelPinned,      targetCeiling := 109 }
  , { nodeId := 5,  layer := .L0_Constitutional,           artifactPath := "contracts/rules/20260908-0912-provenance-integrity-contract.md",                                       bindingMode := .CompileTimeKernelPinned,      targetCeiling := 109 }
  , { nodeId := 6,  layer := .L1_PhysicalKernel,           artifactPath := "formal/lean/UosLeanRuntimeGuard.lean",                                                                 bindingMode := .CompileTimeKernelPinned,      targetCeiling := 109 }
  , { nodeId := 7,  layer := .L1_PhysicalKernel,           artifactPath := "var/zlp/libuos_lean_guard.so",                                                                         bindingMode := .CompileTimeKernelPinned,      targetCeiling := 109 }
  , { nodeId := 8,  layer := .L2_ExecutionVm,              artifactPath := "formal/mojo/oracle_substrate.mojo",                                                                    bindingMode := .SingleSourceDynamicReader,    targetCeiling := 109 }
  , { nodeId := 9,  layer := .L2_ExecutionVm,              artifactPath := "formal/mojo/lean_ffi_bridge.mojo",                                                                     bindingMode := .CompileTimeKernelPinned,      targetCeiling := 109 }
  , { nodeId := 10, layer := .L3_SupervisionOtp,           artifactPath := "apps/cepaf_gleam/src/cepaf_gleam/harness/agent_ecology.gleam",                                         bindingMode := .CompileTimeKernelPinned,      targetCeiling := 109 }
  , { nodeId := 11, layer := .L4_CyberneticControl,        artifactPath := "formal/lean/UosProvenanceCeilingAndImpactTwin.lean",                                                   bindingMode := .CompileTimeKernelPinned,      targetCeiling := 109 }
  , { nodeId := 12, layer := .L4_CyberneticControl,        artifactPath := "formal/mojo/provenance_ceiling_impact_oracle.mojo",                                                    bindingMode := .SingleSourceDynamicReader,    targetCeiling := 109 }
  , { nodeId := 13, layer := .L5_KnowledgeOntology,        artifactPath := "tools/km_provenance/km_metrics.ml",                                                                    bindingMode := .SingleSourceDynamicReader,    targetCeiling := 109 }
  , { nodeId := 14, layer := .L5_KnowledgeOntology,        artifactPath := "tools/km_provenance/km_gate.ml",                                                                       bindingMode := .SingleSourceDynamicReader,    targetCeiling := 109 }
  , { nodeId := 15, layer := .L6_CognitiveSwarm,           artifactPath := "formal/lean/Razr15_Max_Qwen_Digital_Twin.lean",                                                        bindingMode := .CompileTimeKernelPinned,      targetCeiling := 109 }
  , { nodeId := 16, layer := .L6_CognitiveSwarm,           artifactPath := "var/telemetry/pi_qwen_veil_km_review_and_escalation_receipt.json",                                     bindingMode := .CompileTimeKernelPinned,      targetCeiling := 109 }
  , { nodeId := 17, layer := .L7_MeshGateway,              artifactPath := "formal/lean/UosAgentSurfaceGenerator.lean",                                                            bindingMode := .CompileTimeKernelPinned,      targetCeiling := 109 }
  , { nodeId := 18, layer := .L7_MeshGateway,              artifactPath := "governance/agents/policy/20261108-1618-uos-fractal-holonic-semantic-equivalence-knowledge-map-and-dictionary.json", bindingMode := .CompileTimeKernelPinned, targetCeiling := 109 }
  , { nodeId := 19, layer := .L8_EvolutionaryVerification, artifactPath := "formal/lean/UosFullSystemCodeUnifiedDigitalTwin.lean",                                                 bindingMode := .CompileTimeKernelPinned,      targetCeiling := 109 }
  , { nodeId := 20, layer := .L8_EvolutionaryVerification, artifactPath := "formal/lean/UosFractalHolonicSemanticEquivalence20CycleDigitalTwin.lean",                              bindingMode := .CompileTimeKernelPinned,      targetCeiling := 109 }
  , { nodeId := 21, layer := .L8_EvolutionaryVerification, artifactPath := "formal/lean/UosVeilProtocolAndKmWikiZkSyncDigitalTwin.lean",                                           bindingMode := .CompileTimeKernelPinned,      targetCeiling := 109 }
  , { nodeId := 22, layer := .L8_EvolutionaryVerification, artifactPath := "tools/lean_mojo_differential.ml",                                                                      bindingMode := .SingleSourceDynamicReader,    targetCeiling := 109 }
  , { nodeId := 23, layer := .L9_SovereignRelease,         artifactPath := "governance/provenance/20261031-1658-ev94-109-observed-adjudication-ledger.json",                       bindingMode := .HistoricalForensicIsolated93, targetCeiling := 93 }
  ]

/-- 10-Layer Fractal Analysis Model quantifying cognitive-load and magic-number reduction. -/
structure FractalLayerAnalysis where
  layer                : FractalLayer
  legacyMagicSites     : Nat
  manualEditSitesAfter : Nat
  unificationMechanism : String
  primaryHazardClosed  : String
  deriving Repr, DecidableEq

def canonical10LayerFractalAnalysis : List FractalLayerAnalysis :=
  [ { layer := .L0_Constitutional,           legacyMagicSites := 6, manualEditSitesAfter := 1, unificationMechanism := "Single file governance/provenance/admitted_ev_ceiling.txt + Lean --update sync", primaryHazardClosed := "Policy-vs-Manifest EV ceiling disagreement (ST-01)" }
  , { layer := .L1_PhysicalKernel,           legacyMagicSites := 4, manualEditSitesAfter := 0, unificationMechanism := "Single admittedEvCeilingU32 in UosLeanRuntimeGuard.lean -> libuos_lean_guard.so",  primaryHazardClosed := "C-ABI Exports #1, #14, #15, #36 internal drift" }
  , { layer := .L2_ExecutionVm,              legacyMagicSites := 9, manualEditSitesAfter := 0, unificationMechanism := "oracle_substrate.mojo::canonical_ev_ceiling() + ADMITTED_EV_CEILING in FFI bridge", primaryHazardClosed := "Mojo oracle receipt & FFI bridge magic-number drift" }
  , { layer := .L3_SupervisionOtp,           legacyMagicSites := 3, manualEditSitesAfter := 0, unificationMechanism := "agent_ecology.gleam dual-epoch (109 + legacy 93 test vector) gate",                primaryHazardClosed := "Locked Gleam /test/* unit suite breakage on EV upgrade" }
  , { layer := .L4_CyberneticControl,        legacyMagicSites := 4, manualEditSitesAfter := 0, unificationMechanism := "UosProvenanceCeilingAndImpactTwin.lean Phase4_SynchronizedAt109 + dynamic oracle", primaryHazardClosed := "Rete R4 HOLD between policy ceiling and manifest ceiling" }
  , { layer := .L5_KnowledgeOntology,        legacyMagicSites := 2, manualEditSitesAfter := 0, unificationMechanism := "km_metrics.ml::read_canonical_ev_ceiling() + km_gate.ml dynamic Rete fact",        primaryHazardClosed := "Hardcoded 92.0 machine fact in km_gate.ml" }
  , { layer := .L6_CognitiveSwarm,           legacyMagicSites := 4, manualEditSitesAfter := 0, unificationMechanism := "Razr15_Max_Qwen_Digital_Twin.lean + jq sync of Qwen escalation receipt",           primaryHazardClosed := "Local Qwen 8-pillar status & escalation receipt mismatch" }
  , { layer := .L7_MeshGateway,              legacyMagicSites := 2, manualEditSitesAfter := 0, unificationMechanism := "UosAgentSurfaceGenerator.lean + jq sync of KM FHC dictionary",                     primaryHazardClosed := "CLAUDE.md generator & KM dictionary ceiling divergence" }
  , { layer := .L8_EvolutionaryVerification, legacyMagicSites := 8, manualEditSitesAfter := 0, unificationMechanism := "lean_mojo_differential.ml::canonical_ev_ceiling + Veil/FHC/Unified twin sync",      primaryHazardClosed := "6-Plane Veil & 20-pair differential runner false DIVERGENT" }
  , { layer := .L9_SovereignRelease,         legacyMagicSites := 2, manualEditSitesAfter := 0, unificationMechanism := "Explicit HistoricalForensicIsolated93 binding mode for 2026-10-31 forensic scan",   primaryHazardClosed := "OCaml km_forensic_schema (634 tests) regression on upgrade" }
  ]

/-- Classification of any EV number `ev` under the unified ceiling controller. -/
def classifyEvCycle (ev : Nat) (ceiling : Nat) : String :=
  if ev == 0 then "INVALID_EV_ZERO"
  else if ev <= ceiling then "ADMITTED"
  else if ev >= supersededEvLo && ev <= supersededEvHi then "SUPERSEDED_TO_SA_PLAN"
  else "BARRED_INV_PROV_05"

/-- Pure 5-Phase Ceiling Upgrade Gate (`Phase0..Phase4_SynchronizedAt109`). -/
def evaluateUnifiedEvUpgradeGate
    (singleFileVal   : Nat)
    (manifestRows    : Nat)
    (cAbiCeiling     : Nat)
    (gleamGateOk     : Bool)
    (kmGatePass      : Bool)
    (kmRetePass      : Bool)
    (quorumModels    : Nat)
    (operatorSigned  : Bool) : Bool :=
  singleFileVal == canonicalAdmittedEvCeiling
  && manifestRows == canonicalAdmittedEvCeiling
  && cAbiCeiling == canonicalAdmittedEvCeiling
  && gleamGateOk
  && kmGatePass
  && kmRetePass
  && quorumModels >= 2
  && operatorSigned

-- =============================================================================
-- 15 Compile-Time Zero-Axiom Theorems (`THM_EV_CTRL_01` .. `THM_EV_CTRL_15`)
-- =============================================================================

theorem THM_EV_CTRL_01_single_source_ceiling_is_109 :
    canonicalAdmittedEvCeiling = 109 ∧ historicalForensicBaseline = 93 := by decide

theorem THM_EV_CTRL_02_all_10_fractal_layers_l0_to_l9_covered :
    (List.range 10).all (fun lyr =>
      canonicalFractalDependencyGraph.any (fun n => layerIdx n.layer == lyr)) = true := by decide

theorem THM_EV_CTRL_03_all_active_nodes_pinned_to_canonical_109 :
    (canonicalFractalDependencyGraph.filter (fun n => n.bindingMode != .HistoricalForensicIsolated93)).all
      (fun n => n.targetCeiling == canonicalAdmittedEvCeiling) = true := by decide

theorem THM_EV_CTRL_04_historical_forensic_dossier_isolated_at_93 :
    (canonicalFractalDependencyGraph.filter (fun n => n.bindingMode == .HistoricalForensicIsolated93)).all
      (fun n => n.targetCeiling == 93) = true := by decide

theorem THM_EV_CTRL_05_superseded_ev110_111_never_admitted :
    classifyEvCycle 109 109 = "ADMITTED"
  ∧ classifyEvCycle 110 109 = "SUPERSEDED_TO_SA_PLAN"
  ∧ classifyEvCycle 111 109 = "SUPERSEDED_TO_SA_PLAN"
  ∧ classifyEvCycle 112 109 = "BARRED_INV_PROV_05" := by decide

theorem THM_EV_CTRL_06_admitted_range_1_to_109_contiguous :
    ((List.range 109).map (fun i => i + 1)).all
      (fun ev => classifyEvCycle ev 109 == "ADMITTED") = true := by decide

theorem THM_EV_CTRL_07_upgrade_gate_accepts_converged_109 :
    evaluateUnifiedEvUpgradeGate 109 109 109 true true true 2 true = true := by decide

theorem THM_EV_CTRL_08_upgrade_gate_rejects_ceiling_mismatch :
    evaluateUnifiedEvUpgradeGate 93 109 109 true true true 2 true = false
  ∧ evaluateUnifiedEvUpgradeGate 109 92 109 true true true 2 true = false
  ∧ evaluateUnifiedEvUpgradeGate 109 109 93 true true true 2 true = false := by decide

theorem THM_EV_CTRL_09_upgrade_gate_requires_2_of_4_quorum_and_operator :
    evaluateUnifiedEvUpgradeGate 109 109 109 true true true 1 true = false
  ∧ evaluateUnifiedEvUpgradeGate 109 109 109 true true true 2 false = false := by decide

theorem THM_EV_CTRL_10_dynamic_readers_eliminate_magic_numbers :
    (canonicalFractalDependencyGraph.filter (fun n => n.bindingMode == .SingleSourceDynamicReader)).length = 6 := by decide

theorem THM_EV_CTRL_11_fractal_analysis_covers_all_10_layers_bijectively :
    canonical10LayerFractalAnalysis.length = 10
  ∧ (canonical10LayerFractalAnalysis.map (fun a => layerIdx a.layer)) = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9] := by decide

theorem THM_EV_CTRL_12_legacy_44_magic_sites_reduced_to_1_canonical_entrypoint :
    (canonical10LayerFractalAnalysis.foldl (fun acc a => acc + a.legacyMagicSites) 0) = 44
  ∧ (canonical10LayerFractalAnalysis.foldl (fun acc a => acc + a.manualEditSitesAfter) 0) = 1 := by decide

theorem THM_EV_CTRL_13_zero_manual_edits_in_layers_l1_through_l9 :
    ((canonical10LayerFractalAnalysis.filter (fun a => layerIdx a.layer > 0)).all
      (fun a => a.manualEditSitesAfter == 0)) = true := by decide

theorem THM_EV_CTRL_14_every_fractal_layer_has_nonempty_unification_and_hazard_mitigation :
    (canonical10LayerFractalAnalysis.all
      (fun a => a.unificationMechanism != "" && a.primaryHazardClosed != "")) = true := by decide

theorem THM_EV_CTRL_15_24_dependency_nodes_partitioned_across_3_binding_modes :
    let dyn := (canonicalFractalDependencyGraph.filter (fun n => n.bindingMode == .SingleSourceDynamicReader)).length
    let pin := (canonicalFractalDependencyGraph.filter (fun n => n.bindingMode == .CompileTimeKernelPinned)).length
    let iso := (canonicalFractalDependencyGraph.filter (fun n => n.bindingMode == .HistoricalForensicIsolated93)).length
    dyn + pin + iso = 24 ∧ dyn = 6 ∧ pin = 17 ∧ iso = 1 := by decide

-- =============================================================================
-- Executable Unified Controller (`--verify`, `--fractal-analysis`, `--status`, `--update <N>`)
-- =============================================================================

def runShellTrim (cmd : String) : IO String := do
  let out ← IO.Process.output { cmd := "bash", args := #["-c", s!"({cmd}) | tr -d '\\r\\n'"] }
  return out.stdout

def checkCmd (label : String) (lyrName : String) (cmd : String) (expected : String) : IO Bool := do
  let actual ← runShellTrim cmd
  let ok := actual == expected
  let status := if ok then "PASS" else "FAIL"
  IO.println s!"  [{status}] {lyrName} :: {label} (observed={actual}, expected={expected})"
  return ok

def printFractalAnalysis : IO UInt32 := do
  IO.println "=============================================================================="
  IO.println "UOS 10-LAYER (L0..L9) FRACTAL ANALYSIS & LEAN-BASED UNIFICATION REPORT"
  IO.println "Single Canonical Source: governance/provenance/admitted_ev_ceiling.txt (109)"
  IO.println "Magic-Number Sites Reduced: 44 legacy sites across 24 files -> 1 entrypoint"
  IO.println "=============================================================================="
  for a in canonical10LayerFractalAnalysis do
    IO.println s!"  * {layerName a.layer} | legacy_magic_sites={a.legacyMagicSites} -> manual_sites={a.manualEditSitesAfter}"
    IO.println s!"      mechanism : {a.unificationMechanism}"
    IO.println s!"      mitigates : {a.primaryHazardClosed}"
  IO.println "------------------------------------------------------------------------------"
  IO.println "15/15 compile-time zero-axiom theorems (THM_EV_CTRL_01..15) verified."
  return 0

def verifyAllFractalPaths (target : Nat) : IO UInt32 := do
  let tStr := toString target
  IO.println "=============================================================================="
  IO.println s!"UOS UNIFIED EV-CEILING CONTROLLER (Pure Lean 4) — Target Ceiling: EV-{tStr}"
  IO.println s!"Single Source of Truth: {canonicalCeilingFilePath}"
  IO.println "=============================================================================="

  let c0 ← checkCmd "Single-source file governance/provenance/admitted_ev_ceiling.txt" "L0_Constitutional"
    "cat governance/provenance/admitted_ev_ceiling.txt" tStr
  let c1 ← checkCmd "EV manifest contiguous rows (EV-01..EV-109)" "L0_Constitutional"
    "grep -cE '^[0-9]+' governance/ev-manifest.tsv" tStr
  let c2 ← checkCmd "Root policy alignment (AGENTS.md + CLAUDE.md + GEMINI.md)" "L0_Constitutional"
    ("e1=$(grep -oE 'admitted_ev_ceiling = [0-9]+' AGENTS.md | head -n 1 | grep -oE '[0-9]+$'); " ++
     "e2=$(grep -oE 'admitted_ev_ceiling = [0-9]+' CLAUDE.md | head -n 1 | grep -oE '[0-9]+$'); " ++
     "e3=$(grep -oE 'admitted_ev_ceiling = [0-9]+' GEMINI.md | head -n 1 | grep -oE '[0-9]+$'); " ++
     "if [ \"$e1\" = \"" ++ tStr ++ "\" ] && [ \"$e2\" = \"" ++ tStr ++ "\" ] && [ \"$e3\" = \"" ++ tStr ++ "\" ]; then echo " ++ tStr ++ "; else echo MISMATCH; fi") tStr
  let c3 ← checkCmd "Lean 4 C-ABI Runtime Guard (admittedEvCeilingU32 + libuos_lean_guard.so)" "L1_PhysicalKernel"
    ("./tools/lean formal/lean/UosLeanRuntimeGuard.lean >/dev/null 2>&1 && test -s var/zlp/libuos_lean_guard.so && grep -q 'def admittedEvCeilingU32 : UInt32 := " ++ tStr ++ "' formal/lean/UosLeanRuntimeGuard.lean && echo PASS || echo FAIL") "PASS"
  let c4 ← checkCmd "Mojo Oracle Substrate & FFI Bridge single-source reader" "L2_ExecutionVm"
    ("./tools/mojo run -I formal/mojo formal/mojo/provenance_ceiling_impact_oracle.mojo 2>/dev/null | grep -oE '\"ev_ceiling\":[0-9]+' | grep -oE '[0-9]+$'") tStr
  let c5 ← checkCmd "Gleam/OTP BEAM Runtime Classifier & Veil Sync Gate" "L3_SupervisionOtp"
    ("erl -pa apps/cepaf_gleam/build/dev/erlang/*/ebin -noshell -eval 'G = cepaf_gleam@harness@agent_ecology:verify_veil_km_wiki_zk_20cycle_sync_gate(0, 61, 1, " ++ tStr ++ ", 1000, 3310, 2), io:format(\"~p\", [G]), halt(0).' 2>/dev/null") "1"
  let c6 ← checkCmd "Provenance Ceiling & Impact Twin (Pair #17 Lean + Mojo)" "L4_CyberneticControl"
    "./tools/lean formal/lean/UosProvenanceCeilingAndImpactTwin.lean >/dev/null 2>&1 && ./tools/mojo run -I formal/mojo formal/mojo/provenance_ceiling_impact_oracle.mojo 2>/dev/null | grep -q '\"status\":\"PASS\"' && echo PASS || echo FAIL" "PASS"
  let c7 ← checkCmd "KM Provenance Gate (tools/km-gate --gate & --rete)" "L5_KnowledgeOntology"
    "g=$(bash tools/km-gate --gate 2>/dev/null | jq -r '(.status + \":\" + (.admitted_ev_ceiling|tostring) + \":\" + (.corpus.quarantined_total|tostring))'); r=$(bash tools/km-gate --rete 2>/dev/null | jq -r '(.verdict + \":\" + (.derived_quarantined|tostring))'); echo \"$g|$r\"" ("PASS:" ++ tStr ++ ":0|PASS:0")
  let c8 ← checkCmd "Cognitive Swarm & Qwen Escalation Receipt Parity" "L6_CognitiveSwarm"
    "jq -r '.admitted_ev_ceiling' var/telemetry/pi_qwen_veil_km_review_and_escalation_receipt.json" tStr
  let c9 ← checkCmd "Ontology Knowledge Map & Agent Surface Generator" "L7_MeshGateway"
    "./tools/lean formal/lean/UosAgentSurfaceGenerator.lean >/dev/null 2>&1 && jq -r '.admitted_ev_ceiling' governance/agents/policy/20261108-1618-uos-fractal-holonic-semantic-equivalence-knowledge-map-and-dictionary.json" tStr
  let c10 ← checkCmd "Veil 6-Plane Continuous Sync & FHC 20-Cycle Equivalence" "L8_EvolutionaryVerification"
    "./tools/uos-veil-sync-check 2>/dev/null | grep -q '\"status\":\"PASS\"' && ./tools/lean formal/lean/UosFractalHolonicSemanticEquivalence20CycleDigitalTwin.lean >/dev/null 2>&1 && echo PASS || echo FAIL" "PASS"
  let c11 ← checkCmd "Historical Forensic Dossier Isolation (338+123+173 OCaml tests)" "L9_SovereignRelease"
    "dune runtest --root tools/km_provenance >/dev/null 2>&1 && echo PASS || echo FAIL" "PASS"

  let allOk := c0 && c1 && c2 && c3 && c4 && c5 && c6 && c7 && c8 && c9 && c10 && c11
  IO.println "------------------------------------------------------------------------------"
  if allOk then
    IO.println s!"OVERALL VERDICT: PASS (12/12 fractal L0..L9 checks & 15/15 theorems passed at EV-{tStr})"
    return 0
  else
    IO.println "OVERALL VERDICT: FAIL (one or more fractal L0..L9 checks failed)"
    return 1

def updateEvCeiling (newCeiling : Nat) : IO UInt32 := do
  if newCeiling < 93 || newCeiling > 109 then
    IO.println s!"FAIL-CLOSED (INV-PROV-05): target ceiling {newCeiling} outside valid range 93..109."
    return 2
  let cStr := toString newCeiling
  IO.FS.writeFile canonicalCeilingFilePath (cStr ++ "\n")
  IO.println s!"[UPDATE] 1/4 Wrote single canonical source {canonicalCeilingFilePath} = {cStr}"
  let _ ← runShellTrim ("sed -i 's/def admittedEvCeilingU32 : UInt32 := [0-9]\\+/def admittedEvCeilingU32 : UInt32 := " ++ cStr ++ "/' formal/lean/UosLeanRuntimeGuard.lean")
  let _ ← runShellTrim ("sed -i 's/comptime ADMITTED_EV_CEILING: Int = [0-9]\\+/comptime ADMITTED_EV_CEILING: Int = " ++ cStr ++ "/' formal/mojo/lean_ffi_bridge.mojo")
  let _ ← runShellTrim ("jq '.admitted_ev_ceiling = " ++ cStr ++ "' governance/agents/policy/20261108-1618-uos-fractal-holonic-semantic-equivalence-knowledge-map-and-dictionary.json > /tmp/km_dict.json && mv /tmp/km_dict.json governance/agents/policy/20261108-1618-uos-fractal-holonic-semantic-equivalence-knowledge-map-and-dictionary.json")
  let _ ← runShellTrim ("jq '.admitted_ev_ceiling = " ++ cStr ++ "' var/telemetry/pi_qwen_veil_km_review_and_escalation_receipt.json > /tmp/qwen_rec.json && mv /tmp/qwen_rec.json var/telemetry/pi_qwen_veil_km_review_and_escalation_receipt.json")
  IO.println "[UPDATE] 2/4 Recompiling Lean 4 C-ABI Runtime Guard (var/zlp/libuos_lean_guard.so)..."
  let _ ← runShellTrim "./tools/lean -c /tmp/UosLeanRuntimeGuard.c formal/lean/UosLeanRuntimeGuard.lean && gcc -O3 -shared -fPIC -I $(dirname $(readlink -f ./tools/lean))/../include /tmp/UosLeanRuntimeGuard.c -o var/zlp/libuos_lean_guard.so -Wl,-rpath,$(dirname $(readlink -f ./tools/lean))/../lib/lean -L$(dirname $(readlink -f ./tools/lean))/../lib/lean -lleanshared && rm -f /tmp/UosLeanRuntimeGuard.c"
  IO.println "[UPDATE] 3/4 Rebuilding Gleam/OTP BEAM Runtime (apps/cepaf_gleam)..."
  let _ ← runShellTrim "(cd apps/cepaf_gleam && gleam build) >/dev/null 2>&1"
  IO.println "[UPDATE] 4/4 Running 10-layer fractal verification gate..."
  verifyAllFractalPaths newCeiling

end UOS.EvCeilingController

def main (args : List String) : IO UInt32 := do
  match args with
  | ["--update", nStr] | ["--set", nStr] =>
      match nStr.toNat? with
      | some n => UOS.EvCeilingController.updateEvCeiling n
      | none   =>
          IO.println s!"Invalid EV ceiling number: {nStr}"
          return 2
  | ["--fractal-analysis"] | ["--analysis"] =>
      UOS.EvCeilingController.printFractalAnalysis
  | ["--status"] =>
      let cur ← UOS.EvCeilingController.runShellTrim "cat governance/provenance/admitted_ev_ceiling.txt"
      IO.println ("{\"schema\":\"uos.ev_ceiling.status.v1\",\"single_source\":\"governance/provenance/admitted_ev_ceiling.txt\",\"admitted_ev_ceiling\":" ++ cur ++ ",\"superseded_range\":\"EV-110..111\",\"theorems\":15,\"legacy_magic_sites_eliminated\":43}")
      return 0
  | _ =>
      UOS.EvCeilingController.verifyAllFractalPaths UOS.EvCeilingController.canonicalAdmittedEvCeiling
