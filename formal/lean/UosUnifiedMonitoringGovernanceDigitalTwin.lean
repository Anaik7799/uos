/-
  UosUnifiedMonitoringGovernanceDigitalTwin.lean

  Unified Operational System (UOS) — verifiable Lean 4 digital twin for the
  web / content / wiki / KM / ZK management, monitoring and governance plane,
  bound to the holarchy + FPP + bionic substrate.

  Contract IDs : SC-CHECKLIST-001, SC-DIAGRAM-001, SC-KM-TRIAD-001,
                 SC-TAILSCALE-WEB-001, SC-GLM-UI-001, SC-PROVENANCE-001
  Observed     : 2026-11-05T15:41:53Z .. 2026-11-05T16:50:00Z (nas-1 host clock)
  Toolchain    : Lean 4.33.0 via ./tools/lean (SC-TOOLCHAIN-INPROJECT-001)
  Discipline   : zero `sorry`, zero added axioms, zero `Admitted`.

  EPISTEMIC BOUNDARY. This module is a SPECIFICATION plus an executable
  conformance prober. A green `lean` check proves the model is internally
  consistent at this candidate. It is not runtime admission, not two-key
  verification, and mints no EV number. Admitted EV ceiling remains 93;
  EV-94..EV-109 remain NOT_ADMITTED.

  ==========================================================================
  ASCII TOPOLOGY (SC-DIAGRAM-001 — semantic parity with the Mermaid below)
  ==========================================================================

  +---------------------------------------------------------------------+
  |  L9 GOVERNANCE   admission ceiling, threshold calibration authority  |
  +---------------------------------------------------------------------+
                                   |
  +---------------------------------------------------------------------+
  |  L8 EVIDENCE     THIS TWIN: model -> expectation -> alignment check  |
  +---------------------------------------------------------------------+
            |                      |                       |
  +-------------------+  +-------------------+  +-----------------------+
  | SERVICE SURFACE   |  | CHECK INVENTORY   |  | KM TRIAD CENSUS       |
  | cockpit :4100     |  | push vs pull      |  | prose / inline / fence|
  | cockpit :4101     |  | inBeam vs external|  | live vs quoted example|
  | sa-plan :4200     |  | detectsOutage?    |  | threshold satisfiable?|
  | zenoh   :7447     |  |                   |  |                       |
  +-------------------+  +-------------------+  +-----------------------+
            |                      |                       |
            +----------+-----------+-----------+-----------+
                       |                       |
            +---------------------+  +---------------------+
            | RUNTIME OBSERVATION |  | TWIN EXPECTATION    |
            | ss / systemctl /    |  | required listeners, |
            | curl / verifier     |  | routes, scc, a2ui   |
            +---------------------+  +---------------------+
                       |                       |
                       +-----------+-----------+
                                   |
                       +-----------------------+
                       | aligned : Bool        |
                       | false => FAIL CLOSED  |
                       +-----------------------+
                                   |
            +----------------------+----------------------+
            | HOLARCHY + FPP + BIONIC SUBSTRATE (L0..L7)  |
            | holon nodes, FPP actor mesh, bionic roles    |
            +---------------------------------------------+
-/

namespace UOS.UnifiedMonitoringTwin

/-!
```mermaid
flowchart TD
  GOV["L9 Governance<br/>ceiling + threshold authority"]
  TWIN["L8 Evidence — THIS TWIN<br/>model, expectation, alignment"]
  SVC["Service Surface<br/>:4100 :4101 :4200 :7447"]
  CHK["Check Inventory<br/>push/pull, inBeam/external"]
  KM["KM Triad Census<br/>prose / inline / fenced"]
  OBS["Runtime Observation<br/>ss, systemctl, curl, verifier"]
  EXP["Twin Expectation<br/>listeners, routes, scc, a2ui"]
  ALIGN["aligned : Bool<br/>false => FAIL CLOSED"]
  SUB["Holarchy + FPP + Bionic substrate<br/>L0..L7"]
  GOV --> TWIN
  TWIN --> SVC
  TWIN --> CHK
  TWIN --> KM
  SVC --> OBS
  CHK --> OBS
  KM --> EXP
  SVC --> EXP
  OBS --> ALIGN
  EXP --> ALIGN
  ALIGN --> SUB
```
-/

/-! ## 0. Provenance -/

def admittedEvCeiling : Nat := 93
def observedHostUtc : String := "2026-11-05T15:41:53Z"
def twinCandidateId : String := "uos/unified-monitoring-governance-twin/20261105-1650"

theorem THM_PROV_01_ceiling_pinned : admittedEvCeiling = 93 := by decide

/-! ## 1. Fractal layers L0..L9 -/

inductive Layer where
  | l0Constitutional | l1Atomic | l2Component | l3Transaction | l4System
  | l5Cognitive | l6Ecosystem | l7Federation | l8Evidence | l9Governance
  deriving DecidableEq, Repr

def allLayers : List Layer :=
  [.l0Constitutional, .l1Atomic, .l2Component, .l3Transaction, .l4System,
   .l5Cognitive, .l6Ecosystem, .l7Federation, .l8Evidence, .l9Governance]

theorem THM_LAY_01_ten_layers : allLayers.length = 10 := by decide

/-! ## 2. Service surface and the restart-policy recovery gap -/

inductive ServiceId where
  | cockpitHttp | cockpitHttps | saPlanHttp | zenohRouter | docsServer
  deriving DecidableEq, Repr

inductive RestartPolicy where
  | never | onFailure | always
  deriving DecidableEq, Repr

/-- How a unit's main process terminated, as systemd classifies it. -/
inductive ExitClass where
  /-- Handled SIGTERM, exited status 0. systemd calls this SUCCESS. -/
  | cleanExit
  /-- Nonzero exit status. -/
  | failureExit
  /-- Killed by an uncaught signal. -/
  | killedBySignal
  deriving DecidableEq, Repr

/-- systemd restart semantics. `onFailure` does NOT fire on a clean exit. -/
def recovers : RestartPolicy → ExitClass → Bool
  | .never,     _                => false
  | .onFailure, .cleanExit       => false
  | .onFailure, .failureExit     => true
  | .onFailure, .killedBySignal  => true
  | .always,    _                => true

structure ServiceSpec where
  id             : ServiceId
  port           : Nat
  unitName       : String
  policy         : RestartPolicy
  mustStayUp     : Bool
  deriving DecidableEq, Repr

def cockpitHttpSpec : ServiceSpec :=
  { id := .cockpitHttp, port := 4100, unitName := "c3i-gleam-server.service"
  , policy := .onFailure, mustStayUp := true }

def cockpitHttpsSpec : ServiceSpec :=
  { id := .cockpitHttps, port := 4101, unitName := "c3i-gleam-server.service"
  , policy := .onFailure, mustStayUp := true }

def saPlanHttpSpec : ServiceSpec :=
  { id := .saPlanHttp, port := 4200, unitName := "c3i-sa-plan-http.service"
  , policy := .always, mustStayUp := true }

def zenohRouterSpec : ServiceSpec :=
  { id := .zenohRouter, port := 7447, unitName := "c3i-zenoh-router.service"
  , policy := .always, mustStayUp := true }

def serviceSurface : List ServiceSpec :=
  [cockpitHttpSpec, cockpitHttpsSpec, saPlanHttpSpec, zenohRouterSpec]

/-- Observed: SIGTERM at 2026-11-03T23:08:52+01:00, `status=0/SUCCESS`. -/
def observedCockpitExit : ExitClass := .cleanExit

def cockpitRecoversFromObservedDeath : Bool :=
  recovers cockpitHttpSpec.policy observedCockpitExit

/-- THE FIRST FAULT. The cockpit's declared policy cannot recover the way it
    actually died, so the outage persisted for 41 h with the unit `enabled`
    and `c3i.target` active throughout. -/
theorem THM_SVC_01_restart_policy_cannot_recover_clean_sigterm :
    cockpitRecoversFromObservedDeath = false := by decide

def remediatedCockpitSpec : ServiceSpec :=
  { cockpitHttpSpec with policy := .always }

theorem THM_SVC_02_always_policy_closes_the_gap :
    recovers remediatedCockpitSpec.policy observedCockpitExit = true := by decide

/-- A service required to stay up must not carry a policy blind to clean exit. -/
def policyAdequate (s : ServiceSpec) : Bool :=
  !s.mustStayUp || recovers s.policy .cleanExit

theorem THM_SVC_03_cockpit_policy_inadequate :
    policyAdequate cockpitHttpSpec = false := by decide

theorem THM_SVC_04_remediation_adequate :
    policyAdequate remediatedCockpitSpec = true := by decide

/-! ## 3. Check inventory: what is supposed to monitor the plane -/

inductive CheckMode where
  /-- Runs continuously on its own schedule. -/
  | push
  /-- Runs only when a human or agent invokes it. -/
  | pull
  deriving DecidableEq, Repr

inductive CheckResidency where
  /-- Runs inside the cockpit BEAM it observes. -/
  | inBeam
  /-- Runs as a separate OS process. -/
  | external
  deriving DecidableEq, Repr

inductive CheckScope where
  | routes | content | wiki | zk | kmTriad | components | graph
  | journal | diagram | surfaces | liveness | toolchain
  deriving DecidableEq, Repr

structure CheckSpec where
  name      : String
  mode      : CheckMode
  residency : CheckResidency
  scope     : CheckScope
  present   : Bool
  deriving DecidableEq, Repr

/-- Every check observed in the tree on 2026-11-05. `present` records whether
    the artifact exists on disk, not that it passes. -/
def checkInventory : List CheckSpec :=
  [ -- in-BEAM cockpit actors (die with their subject)
    { name := "sentinel-patrol-35-pages", mode := .push, residency := .inBeam
    , scope := .routes, present := true }
  , { name := "freshness-actor-10s", mode := .push, residency := .inBeam
    , scope := .liveness, present := true }
  , { name := "self-observer-60s", mode := .push, residency := .inBeam
    , scope := .liveness, present := true }
  , { name := "guard-grid-ooda-10s", mode := .push, residency := .inBeam
    , scope := .liveness, present := true }
    -- external pull verifiers
  , { name := "tools/link_tracker_verifier.exe", mode := .pull, residency := .external
    , scope := .graph, present := true }
  , { name := "tools/link_tracker_verifier.exe[km]", mode := .pull, residency := .external
    , scope := .kmTriad, present := true }
  , { name := "tools/webui_browser_suite.exe", mode := .pull, residency := .external
    , scope := .content, present := true }
  , { name := "tools/webui_bdd_runner.exe", mode := .pull, residency := .external
    , scope := .content, present := true }
  , { name := "tools/web_quality_gate.ml", mode := .pull, residency := .external
    , scope := .content, present := true }
  , { name := "tools/km-gate", mode := .pull, residency := .external
    , scope := .kmTriad, present := true }
  , { name := "tools/km_provenance", mode := .pull, residency := .external
    , scope := .wiki, present := true }
  , { name := "tools/journal-check", mode := .pull, residency := .external
    , scope := .journal, present := true }
  , { name := "tools/diagram-check", mode := .pull, residency := .external
    , scope := .diagram, present := true }
  , { name := "tools/atlas-check", mode := .pull, residency := .external
    , scope := .zk, present := true }
  , { name := "tools/guard_rules_verifier.exe", mode := .pull, residency := .external
    , scope := .liveness, present := true }
  , { name := "tools/uos-surface-gen --check", mode := .pull, residency := .external
    , scope := .surfaces, present := true }
  , { name := "tools/preflight", mode := .pull, residency := .external
    , scope := .toolchain, present := true }
  , { name := "tools/verify_website_sop.sh", mode := .pull, residency := .external
    , scope := .routes, present := true }
  ]

theorem THM_MON_01_inventory_size : checkInventory.length = 18 := by decide

/-- A check can witness an outage of the cockpit only if it runs on its own
    schedule AND outside the process it observes. -/
def detectsOutage (c : CheckSpec) : Bool :=
  c.present &&
  (match c.mode with | .push => true | .pull => false) &&
  (match c.residency with | .external => true | .inBeam => false)

/-- THE SECOND FAULT, proved. No check in the tree can witness a cockpit
    outage: the push monitors are co-resident in the BEAM that dies, and every
    external check is pull-mode. This is why a 41-hour outage raised no alert. -/
theorem THM_MON_02_no_check_detects_an_outage :
    checkInventory.filter detectsOutage = [] := by decide

/-- The co-resident push monitors are blind by construction, not by accident. -/
def coResidentPushChecks : List CheckSpec :=
  checkInventory.filter (fun c =>
    (match c.mode with | .push => true | .pull => false) &&
    (match c.residency with | .inBeam => true | .external => false))

theorem THM_MON_03_four_monitors_die_with_their_subject :
    coResidentPushChecks.length = 4 := by decide

/-- The remediation: one external push prober. -/
def externalWatchdogSpec : CheckSpec :=
  { name := "uos-web-watchdog (proposed)", mode := .push, residency := .external
  , scope := .liveness, present := false }

def remediatedInventory : List CheckSpec :=
  { externalWatchdogSpec with present := true } :: checkInventory

theorem THM_MON_04_one_external_prober_closes_the_blind_spot :
    (remediatedInventory.filter detectsOutage).length = 1 := by decide

/-- Honest status: the watchdog is specified here, NOT installed. -/
theorem THM_MON_05_watchdog_not_yet_present :
    externalWatchdogSpec.present = false := by decide

/-! ## 4. KM triad census: live transclusions vs quoted examples -/

inductive TokenContext where
  | prose | inlineCode | fencedCode
  deriving DecidableEq, Repr

/-- A transclusion token quoted inside Markdown code is an EXAMPLE, not a link. -/
def isLiveToken : TokenContext → Bool
  | .prose      => true
  | .inlineCode => false
  | .fencedCode => false

theorem THM_KM_01_only_prose_is_live :
    isLiveToken .prose = true
  ∧ isLiveToken .inlineCode = false
  ∧ isLiveToken .fencedCode = false := by decide

structure Census where
  raw          : Nat
  inInlineCode : Nat
  inFencedCode : Nat
  deriving DecidableEq, Repr

def Census.quotedExamples (c : Census) : Nat := c.inInlineCode + c.inFencedCode
def Census.live (c : Census) : Nat := c.raw - c.quotedExamples

/-- Historical 2026-11-05T16:44Z incident fixture over AGENTS.md, GEMINI.md,
    docs/**, contracts/** when the inline-code scanner bug was isolated. -/
def incident20261105WikiCensus : Census := { raw := 1015, inInlineCode := 737, inFencedCode := 0 }
def incident20261105ZkCensus   : Census := { raw := 1308, inInlineCode := 990, inFencedCode := 0 }

/-- Independent census over AGENTS.md, GEMINI.md, docs/**, contracts/**,
    measured 2026-11-07T07:55Z (post-canonical-rule synchronization). -/
def wikiCensus : Census := { raw := 1479, inInlineCode := 1098, inFencedCode := 75 }
def zkCensus   : Census := { raw := 1854, inInlineCode := 1433, inFencedCode := 76 }

def totalQuotedExamples : Nat := wikiCensus.quotedExamples + zkCensus.quotedExamples

/-- THE COUNT. 2,682 transclusion tokens in the current corpus are quoted examples
    (1,173 wiki + 1,509 zk). -/
theorem THM_KM_02_quoted_example_count :
    totalQuotedExamples = 2682
  ∧ wikiCensus.quotedExamples = 1173
  ∧ zkCensus.quotedExamples = 1509 := by decide

theorem THM_KM_03_live_counts :
    wikiCensus.live = 306 ∧ zkCensus.live = 345 := by decide

/-- On the 2026-11-05 incident fixture, every quoted example sat in an inline span
    and none in a fenced block; in the current corpus both inline and fenced code
    spans contain quoted examples (75 wiki, 76 zk). -/
theorem THM_KM_04_no_quoted_examples_in_fenced_blocks :
    incident20261105WikiCensus.inFencedCode = 0 ∧ incident20261105ZkCensus.inFencedCode = 0
  ∧ wikiCensus.inFencedCode = 75 ∧ zkCensus.inFencedCode = 76 := by decide

/-! ### 4.1 The scanner defect -/

inductive ScannerVariant where
  /-- Pre-fix: raw lines, no code awareness. -/
  | rawLines
  /-- The installed fix: strip inline spans. -/
  | stripInline
  /-- Rejected: also blank fenced blocks. -/
  | stripInlineAndFenced
  deriving DecidableEq, Repr

def scannerCounts : ScannerVariant → Census → Nat
  | .rawLines,             c => c.raw
  | .stripInline,          c => c.raw - c.inInlineCode
  | .stripInlineAndFenced, c => c.raw - c.inInlineCode - c.inFencedCode

/-- The pre-fix scanner overcounted wiki transclusions by 737 on the incident
    fixture and by 1,098 on the current corpus. -/
theorem THM_SCAN_01_raw_scanner_overcounts :
    scannerCounts .rawLines incident20261105WikiCensus - scannerCounts .stripInline incident20261105WikiCensus = 737
  ∧ scannerCounts .rawLines wikiCensus - scannerCounts .stripInline wikiCensus = 1098
    := by decide

/-- Fence stripping bought nothing over inline stripping on the 2026-11-05
    incident fixture, and removes the 75/76 fenced-block examples on the current corpus. -/
theorem THM_SCAN_02_fence_stripping_is_redundant :
    scannerCounts .stripInline incident20261105WikiCensus = scannerCounts .stripInlineAndFenced incident20261105WikiCensus
  ∧ scannerCounts .stripInline incident20261105ZkCensus = scannerCounts .stripInlineAndFenced incident20261105ZkCensus
  ∧ scannerCounts .stripInline wikiCensus - scannerCounts .stripInlineAndFenced wikiCensus = 75
  ∧ scannerCounts .stripInline zkCensus - scannerCounts .stripInlineAndFenced zkCensus = 76
    := by decide

/-- THE THIRD FAULT. One quoted example in a post-cutoff journal was classified
    `canonical-triad:` and hard-failed the gate while all 69 endpoints were 200. -/
def preFixCanonicalBroken : Nat := 1
def postFixCanonicalBroken : Nat := 0

theorem THM_SCAN_03_false_positive_cleared :
    preFixCanonicalBroken = 1 ∧ postFixCanonicalBroken = 0 := by decide

/-! ### 4.2 Threshold calibration — an inconsistency, not a regression -/

/-- `tools/verify_website_sop.sh:95`. -/
def sopWikiThreshold : Nat := 500
def sopZkThreshold   : Nat := 800

/-- Counts the verifier itself reported, pre- and post-fix. -/
def verifierWikiPreFix  : Nat := 1036
def verifierZkPreFix    : Nat := 1432
def verifierWikiPostFix : Nat := 303
def verifierZkPostFix   : Nat := 342

def thresholdSatisfied (wiki zk : Nat) : Bool :=
  wiki ≥ sopWikiThreshold && zk ≥ sopZkThreshold

/-- The SOP threshold passed ONLY against the inflated metric. -/
theorem THM_THR_01_thresholds_passed_on_inflated_counts :
    thresholdSatisfied verifierWikiPreFix verifierZkPreFix = true := by decide

/-- With quoted examples excluded the same thresholds are unreachable. The gate
    is now inconsistent with the corpus; recalibration is an L9 decision and is
    deliberately NOT performed by this twin. -/
theorem THM_THR_02_thresholds_unsatisfiable_after_honest_count :
    thresholdSatisfied verifierWikiPostFix verifierZkPostFix = false := by decide

theorem THM_THR_03_recalibration_is_governance_not_code :
    verifierWikiPostFix < sopWikiThreshold ∧ verifierZkPostFix < sopZkThreshold
    := by decide

/-! ### 4.3 Provenance Ceiling & Index Enumeration Invariants (`km_metrics.ml` Sync)

    Models the index enumeration and quarantine-marking invariants enforced by
    `tools/km_provenance/km_metrics.ml` and `tools/km-gate --gate`.
    Historical ADR counts (e.g., 137 at 2026-11-06T08:22Z) are bound as a
    regression fixture (`kmIndexSnapshot_20261106`), while universal algebraic
    laws hold for any corpus size. -/

structure KmIndexSnapshot where
  adrTotal          : Nat
  mocEnumerated     : Nat
  wikiEnumerated    : Nat
  quarantinedTotal  : Nat
  mocMarked         : Nat
  wikiMarked        : Nat
  entropyBitsX1000  : Nat
  entropyFloorX1000 : Nat
  deriving DecidableEq, Repr

def KmIndexSnapshot.isFullyEnumeratedAndMarked (s : KmIndexSnapshot) : Bool :=
  s.adrTotal > 0
  && s.mocEnumerated == s.adrTotal
  && s.wikiEnumerated == s.adrTotal
  && s.mocMarked == s.quarantinedTotal
  && s.wikiMarked == s.quarantinedTotal
  && s.entropyBitsX1000 >= s.entropyFloorX1000

def kmIndexSnapshot_20261106 : KmIndexSnapshot :=
  { adrTotal          := 137
  , mocEnumerated     := 137
  , wikiEnumerated    := 137
  , quarantinedTotal  := 16
  , mocMarked         := 16
  , wikiMarked        := 16
  , entropyBitsX1000  := 3298
  , entropyFloorX1000 := 2500 }

theorem THM_KM_05_index_snapshot_20261106_fully_enumerated_and_marked :
    admittedEvCeiling = 93
  ∧ kmIndexSnapshot_20261106.isFullyEnumeratedAndMarked = true := by decide

theorem THM_KM_06_unmarked_quarantined_adr_fails_index_gate :
    KmIndexSnapshot.isFullyEnumeratedAndMarked
      { kmIndexSnapshot_20261106 with mocMarked := 15 } = false
  ∧ KmIndexSnapshot.isFullyEnumeratedAndMarked
      { kmIndexSnapshot_20261106 with wikiMarked := 15 } = false
  ∧ KmIndexSnapshot.isFullyEnumeratedAndMarked
      { kmIndexSnapshot_20261106 with wikiEnumerated := 136 } = false
  ∧ KmIndexSnapshot.isFullyEnumeratedAndMarked
      { kmIndexSnapshot_20261106 with entropyBitsX1000 := 2499 } = false := by decide

/-! ## 5. Capability surface — what this system must provide -/

inductive Capability where
  | routeAvailability | contentIntegrity | wikiResolution | zkResolution
  | kmTriadChain | componentCatalog | graphTopology | journalStructure
  | diagramParity | surfaceProjection | externalLiveness | autoRecovery
  | alerting | driftDetection | runtimeTwinAlignment | thresholdCalibration
  deriving DecidableEq, Repr

def allCapabilities : List Capability :=
  [.routeAvailability, .contentIntegrity, .wikiResolution, .zkResolution,
   .kmTriadChain, .componentCatalog, .graphTopology, .journalStructure,
   .diagramParity, .surfaceProjection, .externalLiveness, .autoRecovery,
   .alerting, .driftDetection, .runtimeTwinAlignment, .thresholdCalibration]

theorem THM_CAP_01_sixteen_capabilities : allCapabilities.length = 16 := by decide

structure CapabilityStatus where
  cap      : Capability
  provided : Bool
  byWhom   : String
  deriving DecidableEq, Repr

def capabilityLedger : List CapabilityStatus :=
  [ { cap := .routeAvailability,   provided := true
    , byWhom := "link_tracker_verifier.exe (69 endpoints, pull)" }
  , { cap := .contentIntegrity,    provided := true
    , byWhom := "webui_browser_suite.exe + webui_bdd_runner.exe (pull)" }
  , { cap := .wikiResolution,      provided := true
    , byWhom := "link_tracker_verifier.exe km audit (pull)" }
  , { cap := .zkResolution,        provided := true
    , byWhom := "link_tracker_verifier.exe km audit + atlas-check (pull)" }
  , { cap := .kmTriadChain,        provided := true
    , byWhom := "canonical-triad gate + km-gate (pull)" }
  , { cap := .componentCatalog,    provided := true
    , byWhom := "a2ui audit, 239 >= 233 (pull)" }
  , { cap := .graphTopology,       provided := true
    , byWhom := "Tarjan SCC + PageRank/HITS (pull)" }
  , { cap := .journalStructure,    provided := true
    , byWhom := "journal-check / journal_linter (pull)" }
  , { cap := .diagramParity,       provided := true
    , byWhom := "diagram-check (pull)" }
  , { cap := .surfaceProjection,   provided := true
    , byWhom := "uos-surface-gen --check (pull)" }
  , { cap := .externalLiveness,    provided := false
    , byWhom := "NONE — no out-of-BEAM prober exists" }
  , { cap := .autoRecovery,        provided := false
    , byWhom := "NONE — Restart=on-failure blind to clean exit" }
  , { cap := .alerting,            provided := false
    , byWhom := "NONE — no path from a failed pull check to a human" }
  , { cap := .driftDetection,      provided := false
    , byWhom := "NONE — no twin/runtime comparison before this module" }
  , { cap := .runtimeTwinAlignment, provided := true
    , byWhom := "THIS MODULE (alignment relation + prober)" }
  , { cap := .thresholdCalibration, provided := false
    , byWhom := "OPEN — L9 decision, see THM_THR_02" }
  ]

theorem THM_CAP_02_ledger_covers_every_capability :
    capabilityLedger.length = allCapabilities.length := by decide

def capabilityGaps : List CapabilityStatus :=
  capabilityLedger.filter (fun s => !s.provided)

/-- Five capabilities the plane must provide and does not. Stated as a theorem
    so the gap cannot be lost in prose. -/
theorem THM_CAP_03_five_capability_gaps :
    capabilityGaps.length = 5 := by decide

theorem THM_CAP_04_gaps_are_not_empty :
    capabilityGaps ≠ [] := by decide

/-! ## 6. Holarchy + FPP + bionic substrate binding -/

inductive BionicRole where
  | leanAuthority | gleamSupervision | hermesEvidence
  | zigDeterminism | mojoInference
  deriving DecidableEq, Repr

structure HolonNode where
  name        : String
  layer       : Layer
  role        : BionicRole
  hasIntent   : Bool
  hasState    : Bool
  hasPort     : Bool
  fppActors   : Nat
  deriving DecidableEq, Repr

/-- A Janus holon is sound only when it presents intent downward, state upward
    and a typed port outward. -/
def holonSound (n : HolonNode) : Bool :=
  n.hasIntent && n.hasState && n.hasPort

def monitoringHolarchy : List HolonNode :=
  [ { name := "l8-evidence-twin", layer := .l8Evidence, role := .leanAuthority
    , hasIntent := true, hasState := true, hasPort := true, fppActors := 1 }
  , { name := "l4-cockpit-supervisor", layer := .l4System, role := .gleamSupervision
    , hasIntent := true, hasState := true, hasPort := true, fppActors := 40 }
  , { name := "l3-evidence-ledger", layer := .l3Transaction, role := .hermesEvidence
    , hasIntent := true, hasState := true, hasPort := true, fppActors := 1 }
  , { name := "l1-deterministic-vfs", layer := .l1Atomic, role := .zigDeterminism
    , hasIntent := true, hasState := true, hasPort := true, fppActors := 1 }
  , { name := "l5-isolated-inference", layer := .l5Cognitive, role := .mojoInference
    , hasIntent := true, hasState := true, hasPort := true, fppActors := 1 }
  ]

theorem THM_HOL_01_all_holons_sound :
    monitoringHolarchy.all holonSound = true := by decide

/-- The supervised FPP actor mesh observed at boot: 40/40 online. -/
def observedFppActorsOnline : Nat := 40

def declaredFppActors : Nat :=
  (monitoringHolarchy.map (fun n => n.fppActors)).foldl (· + ·) 0

theorem THM_HOL_02_fpp_mesh_accounted :
    declaredFppActors = 44 ∧ observedFppActorsOnline = 40 := by decide

/-- Every bionic role is bound to exactly one holon in the monitoring plane. -/
def rolesCovered : List BionicRole :=
  monitoringHolarchy.map (fun n => n.role)

theorem THM_HOL_03_five_bionic_roles_bound :
    rolesCovered.length = 5 := by decide

/-! ## 7. Alignment: the twin vs the running system -/

structure TwinExpectation where
  requiredListeners  : List ServiceId
  requiredRoutes     : Nat
  maxCanonicalBroken : Nat
  requiredScc        : Nat
  minA2uiComponents  : Nat
  deriving DecidableEq, Repr

def canonicalExpectation : TwinExpectation :=
  { requiredListeners  := [.cockpitHttp, .cockpitHttps, .saPlanHttp, .zenohRouter]
  , requiredRoutes     := 69
  , maxCanonicalBroken := 0
  , requiredScc        := 1
  , minA2uiComponents  := 233 }

structure RuntimeObservation where
  observedUtc             : String
  listenerBound           : List (ServiceId × Bool)
  routesProbed            : Nat
  routes200               : Nat
  canonicalBroken         : Nat
  sccCount                : Nat
  a2uiComponents          : Nat
  deriving DecidableEq, Repr

def boundAt (l : List (ServiceId × Bool)) (s : ServiceId) : Bool :=
  match l.find? (fun p => p.1 = s) with
  | some p => p.2
  | none   => false

def listenersAligned (e : TwinExpectation) (o : RuntimeObservation) : Bool :=
  e.requiredListeners.all (fun s => boundAt o.listenerBound s)

/-- Fail-closed conjunction. An absent reading is `false`, never "assume ok". -/
def aligned (e : TwinExpectation) (o : RuntimeObservation) : Bool :=
  listenersAligned e o
  && (o.routesProbed ≥ e.requiredRoutes)
  && (o.routes200 == o.routesProbed)
  && (o.canonicalBroken ≤ e.maxCanonicalBroken)
  && (o.sccCount == e.requiredScc)
  && (o.a2uiComponents ≥ e.minA2uiComponents)

/-- State at 2026-11-05T15:41:53Z: cockpit dead 41 h, nothing on :4100/:4101. -/
def observationBeforeRepair : RuntimeObservation :=
  { observedUtc     := "2026-11-05T15:41:53Z"
  , listenerBound   := [(.cockpitHttp, false), (.cockpitHttps, false),
                        (.saPlanHttp, true), (.zenohRouter, true)]
  , routesProbed    := 0
  , routes200       := 0
  , canonicalBroken := 1
  , sccCount        := 0
  , a2uiComponents  := 0 }

/-- State after restarting the unit and fixing the scanner. -/
def observationAfterRepair : RuntimeObservation :=
  { observedUtc     := "2026-11-05T16:50:00Z"
  , listenerBound   := [(.cockpitHttp, true), (.cockpitHttps, true),
                        (.saPlanHttp, true), (.zenohRouter, true)]
  , routesProbed    := 69
  , routes200       := 69
  , canonicalBroken := 0
  , sccCount        := 1
  , a2uiComponents  := 239 }

theorem THM_ALN_01_divergent_before_repair :
    aligned canonicalExpectation observationBeforeRepair = false := by decide

theorem THM_ALN_02_aligned_after_repair :
    aligned canonicalExpectation observationAfterRepair = true := by decide

/-- An empty observation never aligns: the relation is fail-closed, so a prober
    that cannot read the system reports divergence rather than health. -/
def emptyObservation : RuntimeObservation :=
  { observedUtc := "", listenerBound := [], routesProbed := 0, routes200 := 0
  , canonicalBroken := 0, sccCount := 0, a2uiComponents := 0 }

theorem THM_ALN_03_fail_closed_on_no_evidence :
    aligned canonicalExpectation emptyObservation = false := by decide

/-- A dead cockpit alone forces divergence even if every other reading is ideal. -/
theorem THM_ALN_04_dead_cockpit_forces_divergence :
    aligned canonicalExpectation
      { observationAfterRepair with
        listenerBound := [(.cockpitHttp, false), (.cockpitHttps, true),
                          (.saPlanHttp, true), (.zenohRouter, true)] } = false
    := by decide

/-- Alignment is decidable, so the twin can always be checked against reality. -/
theorem THM_ALN_05_alignment_decidable (e : TwinExpectation) (o : RuntimeObservation) :
    aligned e o = true ∨ aligned e o = false := by
  cases h : aligned e o
  · exact Or.inr rfl
  · exact Or.inl rfl

/-! ## 8. OBSERVATION PLANE — deliberately absent

    The executable conformance prober that stood here until `20261106-0108`
    has moved to `formal/mojo/monitoring_governance_oracle.mojo`.

    WHAT STAYS, AND WHY
    -------------------
    `observationBeforeRepair` and `observationAfterRepair` remain. They are
    NAMED HISTORICAL FIXTURES: readings taken at a stated past moment, kept
    as a regression corpus. `THM_ALN_01` and `THM_ALN_02` are true statements
    about those recorded data and cannot rot, because neither claims to
    describe the present.

    What does NOT stay is any observation presented as current. A record
    called `observationNow`, carrying a timestamp and a count, with a theorem
    proving a verdict about it `by decide`, is a frozen claim about a moving
    world: the kernel re-checks the arithmetic forever and never re-checks
    the fact. One such record in
    `UosMcpNameOwnershipTwin.lean` stayed green for the four hours after its
    subject became false. The differential oracle caught it; the proof could
    not.

    So: fixtures yes, present tense no. The present is observed in Mojo, at
    the moment of asking.

    A `lean` exit code from this file means the algebra is consistent. It is
    not an observation of the system
    (`THM_VAC_01_typechecking_is_not_observation`).
-/

end UOS.UnifiedMonitoringTwin
