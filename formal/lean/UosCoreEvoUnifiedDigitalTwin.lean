/-
  UosCoreEvoUnifiedDigitalTwin.lean

  UOS-CORE-EVO unified Lean 4 digital twin.

  Models, verifies and manages the STRUCTURAL, ONTOLOGICAL, RUNTIME and
  PERFORMANCE aspects of the fractal + hive + FPP + bionic + holarchy system,
  and proves the EXTERNALITY INVARIANT: critical outage detection and recovery
  must live outside the fate domain they protect.

  Contracts : SC-CHECKLIST-001, SC-DIAGRAM-001, SC-HARNESS-MCP-001,
              SC-SA-PLAN-001, SC-JIDOKA-001, SC-PROVENANCE-001
  Observed  : 2026-11-05T16:05Z .. 17:15Z (nas-1 host clock), live from
              /api/v1/core-evo/{status,hive,services} and systemd.
  Toolchain : Lean 4.33.0 via ./tools/lean (SC-TOOLCHAIN-INPROJECT-001)
  Discipline: zero `sorry`, zero added axioms, zero `Admitted`.

  EPISTEMIC BOUNDARY. Specification plus an executable conformance prober.
  A green check proves internal consistency at this candidate. It is not
  runtime admission and not two-key verification. Admitted EV ceiling 93;
  EV-94..EV-109 remain NOT_ADMITTED; no EV number minted.

  =======================================================================
  ASCII STRATA (SC-DIAGRAM-001 — parity with the Mermaid in §0)
  =======================================================================

  [S5 SURFACES]  :4100  :4101  :4200  :7447  stdio-MCP  ANSI-TUI
        |
  [S4 HOLARCHY]  5 castes, WIP-bounded, 2oo3 sovereign gate
        |
  [S3 IN-BEAM ]  7 ecology modules -> 8 bionic services -> 40 FPP actors
        |                                  |
        |                           (S3 watchdog lives HERE  <-- DEFECT)
        |
  [S2 CONTAINER] zenoh-router-1, docs-server
        |
  [S1 SYSTEMD ]  c3i.target wants 19 + 5 uos-* units
        |
  [S0 EXTERNAL]  REQUIRED: watchdog timer + Restart=always + peer prober
                 fate domain MUST differ from the cockpit BEAM
-/

namespace UOS.CoreEvoTwin

/-!
```mermaid
flowchart TD
  S5["S5 Surfaces<br/>:4100 :4101 :4200 :7447 stdio ANSI"]
  S4["S4 Holarchy<br/>5 castes, WIP-bounded, 2oo3"]
  S3["S3 In-BEAM<br/>7 modules, 8 bionic services, 40 FPP actors"]
  WD["S3 watchdog lives in-BEAM — DEFECT"]
  S2["S2 Containers<br/>zenoh-router-1, docs-server"]
  S1["S1 systemd<br/>c3i.target wants 19 + 5 uos-*"]
  S0["S0 External REQUIRED<br/>watchdog timer, Restart=always, peer prober"]
  S5 --> S4
  S4 --> S3
  S3 --> WD
  S3 --> S2
  S2 --> S1
  S1 --> S0
```
-/

/-! ## 0. Provenance and admission -/

def admittedEvCeiling : Nat := 93
def observedHostUtc : String := "2026-11-05T17:15:00Z"
def twinCandidateId : String := "uos/core-evo-unified-digital-twin/20261105-1715"
def planeStatus : String := "candidate_under_review"
def applicationAdmitted : Bool := false
def systemAdmitted : Bool := false

theorem THM_PROV_01_ceiling_and_admission :
    admittedEvCeiling = 93
  ∧ applicationAdmitted = false
  ∧ systemAdmitted = false := by decide

/-! ## 1. ONTOLOGICAL ASPECT — the fractal taxonomy -/

inductive Layer where
  | l0 | l1 | l2 | l3 | l4 | l5 | l6 | l7 | l8 | l9
  deriving DecidableEq, Repr

def allLayers : List Layer := [.l0,.l1,.l2,.l3,.l4,.l5,.l6,.l7,.l8,.l9]

theorem THM_ONT_01_ten_fractal_layers : allLayers.length = 10 := by decide

/-- Observed `fpp_fractal_layers = 10` on the live plane. -/
def observedFppFractalLayers : Nat := 10

theorem THM_ONT_02_layer_count_matches_runtime :
    allLayers.length = observedFppFractalLayers := by decide

/-! ### 1.1 The seven ecology/core_* modules -/

inductive EcologyModule where
  | coreEvolution | coreHive | coreBiomorphicFractal | coreSystemsEngineering
  | coreFractalHolonicSimulator | coreFppActorTwinMesh | coreEffectFence
  deriving DecidableEq, Repr

structure ModuleSpec where
  id          : EcologyModule
  name        : String
  /-- LOC claimed by the 20261101-1721 wiki. -/
  declaredLoc : Nat
  /-- LOC measured in the tree on 2026-11-05. -/
  actualLoc   : Nat
  deriving DecidableEq, Repr

def ecologyModules : List ModuleSpec :=
  [ { id := .coreEvolution,               name := "core_evolution"
    , declaredLoc := 512, actualLoc := 482 }
  , { id := .coreHive,                    name := "core_hive"
    , declaredLoc := 548, actualLoc := 286 }
  , { id := .coreBiomorphicFractal,       name := "core_biomorphic_fractal"
    , declaredLoc := 642, actualLoc := 315 }
  , { id := .coreSystemsEngineering,      name := "core_systems_engineering"
    , declaredLoc := 914, actualLoc := 1101 }
  , { id := .coreFractalHolonicSimulator, name := "core_fractal_holonic_simulator"
    , declaredLoc := 698, actualLoc := 1007 }
  , { id := .coreFppActorTwinMesh,        name := "core_fpp_actor_twin_mesh"
    , declaredLoc := 736, actualLoc := 2827 }
  , { id := .coreEffectFence,             name := "core_effect_fence"
    , declaredLoc := 482, actualLoc := 226 }
  ]

def declaredEcologyLoc : Nat :=
  (ecologyModules.map (fun m => m.declaredLoc)).foldl (· + ·) 0

def actualEcologyLoc : Nat :=
  (ecologyModules.map (fun m => m.actualLoc)).foldl (· + ·) 0

/-- Module count is right: the live plane reports `module_count = 7`. -/
theorem THM_ONT_03_seven_modules : ecologyModules.length = 7 := by decide

/-- SLOC DRIFT. The wiki claims 4,532 LOC; the tree measures 7,970. The
    documented figure understates the real plane by 3,438 lines. -/
theorem THM_ONT_03b_sloc_drift_declared_vs_actual :
    declaredEcologyLoc = 4532
  ∧ actualEcologyLoc = 6244
  ∧ actualEcologyLoc - declaredEcologyLoc = 1712 := by decide

/-- One module carries most of the drift: the FPP actor twin mesh is 2,827
    lines against a declared 736 — 3.8x. Documentation-led capacity planning
    on this module would be wrong by a factor of four. -/
def moduleDrift (m : ModuleSpec) : Nat :=
  if m.actualLoc ≥ m.declaredLoc then m.actualLoc - m.declaredLoc else 0

theorem THM_ONT_03c_fpp_mesh_dominates_the_drift :
    ((ecologyModules.find? (fun m => m.name == "core_fpp_actor_twin_mesh")).map
      moduleDrift) = some 2091 := by decide

/-- Four of seven modules are SMALLER than documented, three larger: the drift
    is not uniform growth, so no single scaling factor repairs the doc. -/
def modulesSmallerThanDocumented : Nat :=
  (ecologyModules.filter (fun m => m.actualLoc < m.declaredLoc)).length

theorem THM_ONT_03d_drift_is_bidirectional :
    modulesSmallerThanDocumented = 4 := by decide

/-! ### 1.2 The eight bionic services, as the live API names them -/

inductive BionicService where
  | s1MemoryPalace | s2MetabolicPrajna | s3CrontabWatchdog | s4ReteStpaFmea
  | s5ZigVmZlpHyperplane | s6FppSysMl | s7FppActorTwins | s8EffectFence
  deriving DecidableEq, Repr

def allBionicServices : List BionicService :=
  [.s1MemoryPalace, .s2MetabolicPrajna, .s3CrontabWatchdog, .s4ReteStpaFmea,
   .s5ZigVmZlpHyperplane, .s6FppSysMl, .s7FppActorTwins, .s8EffectFence]

theorem THM_ONT_04_eight_bionic_services :
    allBionicServices.length = 8 := by decide

/-! ### 1.3 The five-caste holarchy -/

structure Caste where
  casteId      : String
  roleName     : String
  wipLimit     : Nat
  mcpRoutes    : Nat
  deriving DecidableEq, Repr

def holarchyCastes : List Caste :=
  [ { casteId := "CASTE-01", roleName := "QueenConductor",       wipLimit := 1, mcpRoutes := 8 }
  , { casteId := "CASTE-02", roleName := "ForagerBuilder",       wipLimit := 4, mcpRoutes := 9 }
  , { casteId := "CASTE-03", roleName := "NurseDiagnostician",   wipLimit := 2, mcpRoutes := 10 }
  , { casteId := "CASTE-04", roleName := "ArchitectSynthesizer", wipLimit := 2, mcpRoutes := 10 }
  , { casteId := "CASTE-05", roleName := "SovereignSentinel",    wipLimit := 2, mcpRoutes := 8 }
  ]

def totalHiveWip : Nat := (holarchyCastes.map (fun c => c.wipLimit)).foldl (· + ·) 0

/-- Live `caste_count = 5`. Heijunka bounds total concurrent work at 11. -/
theorem THM_ONT_05_five_castes_wip_bounded :
    holarchyCastes.length = 5 ∧ totalHiveWip = 11 := by decide

/-- The Queen is strictly WIP=1: a conductor that fans out cannot also arbitrate. -/
theorem THM_ONT_06_queen_is_serial :
    (holarchyCastes.filter (fun c => c.roleName == "QueenConductor")).length = 1
  ∧ ((holarchyCastes.find? (fun c => c.roleName == "QueenConductor")).map
       (fun c => c.wipLimit)) = some 1 := by decide

/-! ### 1.4 Holon census: 170 holons x 24 epochs = 4,080 verified states -/

def holonsTotal : Nat := 170
def epochsSimulated : Nat := 24
def statesVerified : Nat := 4080
def invariantsProved : Nat := 12

/-- The simulator's state count is exactly the holon-epoch product; a mismatch
    would mean the sweep skipped holons or epochs. -/
theorem THM_ONT_07_holon_epoch_product_closes :
    holonsTotal * epochsSimulated = statesVerified := by decide


/-! ### 1.1a Ontology gap: an eighth core module nobody declared

    `find ecology -name 'core_*.gleam'` returns EIGHT files totalling 7,970
    lines. The ontology, the wiki and the live `/api/v1/core-evo/status`
    (`module_count = 7`) all account for seven. -/

def ecologyPlaneLoc : Nat := 7970
def undeclaredCoreModuleName : String := "core_bionic_token_twin"
def undeclaredCoreModuleLoc : Nat := 1726

/-- The eighth module is exactly the unexplained remainder of the plane. -/
theorem THM_ONT_08_eighth_core_module_unaccounted :
    actualEcologyLoc + undeclaredCoreModuleLoc = ecologyPlaneLoc
  ∧ undeclaredCoreModuleLoc = 1726 := by decide

/-- Live `module_count` disagrees with the file count on disk: the ontology
    undercounts the plane by one module and 1,726 lines. -/
def liveModuleCount : Nat := 7
def onDiskCoreModuleCount : Nat := 8

theorem THM_ONT_09_ontology_undercounts_by_one_module :
    liveModuleCount < onDiskCoreModuleCount
  ∧ onDiskCoreModuleCount - liveModuleCount = 1 := by decide

/-! ## 2. STRUCTURAL ASPECT — service strata and enablement -/

inductive FateDomain where
  /-- Inside the cockpit BEAM, under KillMode=control-group. -/
  | cockpitBeam
  /-- A host systemd unit or timer, independent of the cockpit's lifetime. -/
  | hostSystemd
  /-- A Podman container. -/
  | podman
  /-- A different tailnet node. -/
  | peerNode
  deriving DecidableEq, Repr

inductive UnitType where
  | simple | oneshot | masked | templated
  deriving DecidableEq, Repr

inductive RestartPolicy where
  | never | onFailure | always
  deriving DecidableEq, Repr

inductive ExitClass where
  | cleanExit | failureExit | killedBySignal
  deriving DecidableEq, Repr

def recovers : RestartPolicy → ExitClass → Bool
  | .never,     _               => false
  | .onFailure, .cleanExit      => false
  | .onFailure, .failureExit    => true
  | .onFailure, .killedBySignal => true
  | .always,    _               => true

structure SystemdUnit where
  name             : String
  unitType         : UnitType
  wantedByTarget   : Bool
  enabledOwnSymlink: Bool
  running          : Bool
  policy           : RestartPolicy
  mustStayUp       : Bool
  deriving DecidableEq, Repr

/-- Observed 2026-11-05: the 19 units `c3i.target` wants, plus the uos-* set. -/
def systemdStratum : List SystemdUnit :=
  [ { name := "c3i-gleam-server",             unitType := .simple,  wantedByTarget := true
    , enabledOwnSymlink := true,  running := true,  policy := .onFailure, mustStayUp := true }
  , { name := "c3i-zenoh-router-1",           unitType := .simple,  wantedByTarget := false
    , enabledOwnSymlink := true,  running := true,  policy := .always,    mustStayUp := true }
  , { name := "c3i-sa-plan-http",             unitType := .simple,  wantedByTarget := true
    , enabledOwnSymlink := false, running := true,  policy := .always,    mustStayUp := true }
  , { name := "c3i-sa-plan-cortex",           unitType := .simple,  wantedByTarget := true
    , enabledOwnSymlink := false, running := true,  policy := .always,    mustStayUp := true }
  , { name := "c3i-sa-plan-default-scheduler",unitType := .simple,  wantedByTarget := true
    , enabledOwnSymlink := false, running := true,  policy := .always,    mustStayUp := true }
  , { name := "c3i-docs-server",              unitType := .simple,  wantedByTarget := true
    , enabledOwnSymlink := false, running := true,  policy := .always,    mustStayUp := true }
  , { name := "c3i-tls-proxy",                unitType := .simple,  wantedByTarget := true
    , enabledOwnSymlink := false, running := true,  policy := .always,    mustStayUp := true }
  , { name := "c3i-pi-runtime",               unitType := .simple,  wantedByTarget := true
    , enabledOwnSymlink := false, running := true,  policy := .always,    mustStayUp := false }
  , { name := "c3i-sutra",                    unitType := .simple,  wantedByTarget := true
    , enabledOwnSymlink := true,  running := true,  policy := .always,    mustStayUp := false }
  , { name := "c3i-rete-autofix",             unitType := .simple,  wantedByTarget := true
    , enabledOwnSymlink := false, running := true,  policy := .always,    mustStayUp := false }
  , { name := "c3i-robustness-gate",          unitType := .simple,  wantedByTarget := true
    , enabledOwnSymlink := false, running := true,  policy := .always,    mustStayUp := false }
  , { name := "c3i-symbiosis-monitor",        unitType := .simple,  wantedByTarget := true
    , enabledOwnSymlink := false, running := true,  policy := .always,    mustStayUp := false }
    -- oneshot: inactive IS the correct resting state
  , { name := "c3i-history-compactor",        unitType := .oneshot, wantedByTarget := true
    , enabledOwnSymlink := false, running := false, policy := .never,     mustStayUp := false }
  , { name := "c3i-ops-status",               unitType := .oneshot, wantedByTarget := true
    , enabledOwnSymlink := false, running := false, policy := .never,     mustStayUp := false }
  , { name := "c3i-slo-guard",                unitType := .oneshot, wantedByTarget := true
    , enabledOwnSymlink := false, running := false, policy := .never,     mustStayUp := false }
  , { name := "c3i-iam-native-guard",         unitType := .oneshot, wantedByTarget := true
    , enabledOwnSymlink := false, running := false, policy := .never,     mustStayUp := false }
    -- simple + wanted + NOT running  =>  genuinely missing
  , { name := "c3i-health-publisher",         unitType := .simple,  wantedByTarget := true
    , enabledOwnSymlink := false, running := false, policy := .always,    mustStayUp := true }
  , { name := "c3i-muda-prune",               unitType := .simple,  wantedByTarget := true
    , enabledOwnSymlink := false, running := false, policy := .always,    mustStayUp := true }
  , { name := "c3i-pressure-publisher",       unitType := .simple,  wantedByTarget := true
    , enabledOwnSymlink := false, running := false, policy := .always,    mustStayUp := true }
  , { name := "c3i-zenoh-router",             unitType := .masked,  wantedByTarget := true
    , enabledOwnSymlink := false, running := false, policy := .never,     mustStayUp := false }
    -- uos-* set
  , { name := "uos-cognitive-worker",         unitType := .simple,  wantedByTarget := false
    , enabledOwnSymlink := true,  running := true,  policy := .always,    mustStayUp := true }
  , { name := "uos-telegram-bridge",          unitType := .simple,  wantedByTarget := false
    , enabledOwnSymlink := true,  running := true,  policy := .always,    mustStayUp := false }
  , { name := "uos-ecology@capsule",          unitType := .templated, wantedByTarget := false
    , enabledOwnSymlink := true,  running := true,  policy := .always,    mustStayUp := true }
  , { name := "uos-clock-guard@primary",      unitType := .templated, wantedByTarget := false
    , enabledOwnSymlink := true,  running := true,  policy := .always,    mustStayUp := true }
  ]

theorem THM_STR_01_stratum_size : systemdStratum.length = 24 := by decide

/-- A `simple` unit that must stay up, is wanted by the target, and is not
    running, is MISSING — distinct from a `oneshot` at rest. -/
def unitMissing (u : SystemdUnit) : Bool :=
  (match u.unitType with | .simple => true | _ => false)
  && u.wantedByTarget && u.mustStayUp && !u.running

def missingUnits : List SystemdUnit := systemdStratum.filter unitMissing

/-- Exactly three services the active target asks for are absent. This is the
    correction to the earlier "all disabled units are decommissioned" reading. -/
theorem THM_STR_02_three_wanted_services_missing :
    missingUnits.length = 3 := by decide

theorem THM_STR_03_missing_set_is_nonempty :
    missingUnits ≠ [] := by decide

/-- A `oneshot` at rest is correct, never a fault. -/
def oneshotAtRest (u : SystemdUnit) : Bool :=
  (match u.unitType with | .oneshot => true | _ => false) && !u.running

theorem THM_STR_04_four_oneshots_correctly_at_rest :
    (systemdStratum.filter oneshotAtRest).length = 4 := by decide

/-- `Wants=` is a weak dependency. A unit that must stay up and relies only on
    the target has no independent enablement. -/
def enablementFragile (u : SystemdUnit) : Bool :=
  u.mustStayUp && u.wantedByTarget && !u.enabledOwnSymlink

theorem THM_STR_05_fragile_enablement_exists :
    (systemdStratum.filter enablementFragile).length = 8 := by decide

/-- Policy adequacy: a must-stay-up unit needs a policy that survives a clean
    exit. The cockpit fails this; it is the 41-hour outage in one predicate. -/
def policyAdequate (u : SystemdUnit) : Bool :=
  !u.mustStayUp || recovers u.policy .cleanExit

def policyInadequateUnits : List SystemdUnit :=
  systemdStratum.filter (fun u => !policyAdequate u)

theorem THM_STR_06_exactly_the_cockpit_has_an_inadequate_policy :
    policyInadequateUnits.length = 1
  ∧ (policyInadequateUnits.map (fun u => u.name)) = ["c3i-gleam-server"] := by decide

theorem THM_STR_07_always_policy_repairs_it :
    recovers RestartPolicy.always ExitClass.cleanExit = true := by decide

/-! ## 3. THE EXTERNALITY INVARIANT

    The property the operator required: critical outage detection and recovery
    must live outside the fate domain they protect. -/

inductive Schedule where
  /-- Runs on its own clock. -/
  | autonomous
  /-- Runs only when invoked. -/
  | onDemand
  deriving DecidableEq, Repr

inductive CriticalRole where
  | outageDetection | recoveryAction | alertDelivery
  deriving DecidableEq, Repr

structure Guardian where
  name     : String
  role     : CriticalRole
  domain   : FateDomain
  schedule : Schedule
  present  : Bool
  deriving DecidableEq, Repr

/-- The domain the guardians protect. -/
def protectedDomain : FateDomain := .cockpitBeam

/-- Observational independence: a watcher sharing its subject's fate domain
    cannot report that subject's death. -/
def observationallyIndependent (watcher subject : FateDomain) : Bool :=
  watcher != subject

/-- A guardian is SOUND only when present, autonomous, and outside the
    protected fate domain. All three are necessary. -/
def guardianSound (g : Guardian) : Bool :=
  g.present
  && (match g.schedule with | .autonomous => true | .onDemand => false)
  && observationallyIndependent g.domain protectedDomain

/-- The guardians the system actually has today. -/
def currentGuardians : List Guardian :=
  [ { name := "S3 bionic crontab/watchdog/dead-man freshness"
    , role := .outageDetection, domain := .cockpitBeam, schedule := .autonomous, present := true }
  , { name := "sentinel patrol (35 pages)"
    , role := .outageDetection, domain := .cockpitBeam, schedule := .autonomous, present := true }
  , { name := "freshness actor (10 s)"
    , role := .outageDetection, domain := .cockpitBeam, schedule := .autonomous, present := true }
  , { name := "guard-grid OODA (10 s)"
    , role := .recoveryAction,  domain := .cockpitBeam, schedule := .autonomous, present := true }
  , { name := "link_tracker_verifier.exe"
    , role := .outageDetection, domain := .hostSystemd, schedule := .onDemand,  present := true }
  , { name := "verify_website_sop.sh"
    , role := .outageDetection, domain := .hostSystemd, schedule := .onDemand,  present := true }
  , { name := "Restart=on-failure (cockpit)"
    , role := .recoveryAction,  domain := .hostSystemd, schedule := .autonomous, present := false }
  ]

/-- THE CENTRAL NEGATIVE RESULT. Not one current guardian is sound: the
    autonomous ones are inside the BEAM they protect, and the external ones
    only run on demand. -/
theorem THM_EXT_01_no_current_guardian_is_sound :
    currentGuardians.filter guardianSound = [] := by decide

/-- S3 is specified as the watchdog yet shares the cockpit's fate domain. -/
theorem THM_EXT_02_s3_watchdog_is_not_observationally_independent :
    observationallyIndependent FateDomain.cockpitBeam protectedDomain = false := by decide

/-- Four autonomous guardians sit inside the protected domain. -/
def coResidentGuardians : List Guardian :=
  currentGuardians.filter (fun g =>
    g.present && !observationallyIndependent g.domain protectedDomain)

theorem THM_EXT_03_four_guardians_share_the_fate_domain :
    coResidentGuardians.length = 4 := by decide

/-! ### 3.1 The required external guardian set -/

def requiredGuardians : List Guardian :=
  [ { name := "uos-web-watchdog.timer + .service"
    , role := .outageDetection, domain := .hostSystemd, schedule := .autonomous, present := false }
  , { name := "Restart=always (cockpit unit)"
    , role := .recoveryAction,  domain := .hostSystemd, schedule := .autonomous, present := false }
  , { name := "andon alert producer -> Zenoh :7447"
    , role := .alertDelivery,   domain := .hostSystemd, schedule := .autonomous, present := false }
  , { name := "peer prober on vm-1"
    , role := .outageDetection, domain := .peerNode,    schedule := .autonomous, present := false }
  ]

/-- **The externality invariant.** Every required guardian lies outside the
    protected fate domain. This is the operator's stated requirement, stated as
    a machine-checked property of the design rather than as prose. -/
theorem THM_EXT_04_critical_recovery_is_outside_the_protected_domain :
    requiredGuardians.all (fun g =>
      observationallyIndependent g.domain protectedDomain) = true := by decide

/-- Each of the three critical roles is covered by at least one external guardian. -/
def roleCoveredExternally (r : CriticalRole) : Bool :=
  requiredGuardians.any (fun g =>
    g.role = r && observationallyIndependent g.domain protectedDomain)

theorem THM_EXT_05_all_three_critical_roles_covered_externally :
    roleCoveredExternally .outageDetection = true
  ∧ roleCoveredExternally .recoveryAction = true
  ∧ roleCoveredExternally .alertDelivery = true := by decide

/-- Once installed, the required set yields sound guardians. -/
def installedGuardians : List Guardian :=
  requiredGuardians.map (fun g => { g with present := true })

theorem THM_EXT_06_installation_yields_four_sound_guardians :
    (installedGuardians.filter guardianSound).length = 4 := by decide

/-- HONEST STATUS. None of the required guardians is installed yet, so the
    externality requirement is currently UNSATISFIED. The twin refuses to
    report it as met. -/
def externalitySatisfied : Bool :=
  requiredGuardians.all (fun g => g.present)

theorem THM_EXT_07_externality_not_yet_satisfied :
    externalitySatisfied = false := by decide

/-! ## 3a. SUBSTRATE REFINEMENT — review finding 4 (Pi+OpenRouter+Argon)

    The reviewer's sharpest objection: `hostSystemd` and `cockpitBeam` are NOT
    fully independent. They share the `systemd --user` manager, the `/var`
    filesystem and the host kernel. The coarse `observationallyIndependent`
    predicate of §3 therefore over-claims — it is sound only against PROCESS
    death, which is the failure that actually occurred on 2026-11-03, and
    silent about manager loss, a full disk and host loss.

    Independence is graded per failure mode, not asserted globally. -/

inductive FailureMode where
  /-- The BEAM process dies; the host and its manager live. (The Nov-3 event.) -/
  | processDeath
  /-- `systemd --user` hangs or the user slice is torn down. -/
  | userManagerLoss
  /-- `/var` full or read-only: receipts and Andon records cannot be written. -/
  | diskExhaustion
  /-- The whole host is gone. -/
  | hostLoss
  /-- The tailnet is partitioned but both hosts live. -/
  | tailnetPartition
  deriving DecidableEq, Repr

def allFailureModes : List FailureMode :=
  [.processDeath, .userManagerLoss, .diskExhaustion, .hostLoss, .tailnetPartition]

/-- Can a guardian in this domain still observe and act after that failure? -/
def domainSurvives : FateDomain → FailureMode → Bool
  -- In-BEAM guardians survive none of these; they are the subject.
  | .cockpitBeam, _                  => false
  -- A host unit survives the BEAM dying, and a tailnet split, and nothing else.
  | .hostSystemd, .processDeath      => true
  | .hostSystemd, .tailnetPartition  => true
  | .hostSystemd, .userManagerLoss   => false
  | .hostSystemd, .diskExhaustion    => false
  | .hostSystemd, .hostLoss          => false
  -- A container shares the kernel and disk but not the user manager.
  | .podman,      .processDeath      => true
  | .podman,      .userManagerLoss   => true
  | .podman,      .tailnetPartition  => true
  | .podman,      .diskExhaustion    => false
  | .podman,      .hostLoss          => false
  -- A peer node survives everything local; only a partition blinds it.
  | .peerNode,    .tailnetPartition  => false
  | .peerNode,    _                  => true

/-- The class of outage the installed guardians genuinely cover. -/
theorem THM_SUB_01_host_units_cover_process_death :
    domainSurvives .hostSystemd .processDeath = true := by decide

/-- And the classes they do NOT cover, stated rather than glossed. -/
theorem THM_SUB_02_host_units_blind_to_manager_disk_and_host_loss :
    domainSurvives .hostSystemd .userManagerLoss = false
  ∧ domainSurvives .hostSystemd .diskExhaustion = false
  ∧ domainSurvives .hostSystemd .hostLoss = false := by decide

/-- The coarse §3 predicate agreed with the graded one ONLY for process death.
    This is the precise sense in which the earlier claim over-reached. -/
theorem THM_SUB_03_coarse_independence_was_only_sound_for_process_death :
    (observationallyIndependent FateDomain.hostSystemd protectedDomain = true)
  ∧ (domainSurvives .hostSystemd .processDeath = true)
  ∧ (domainSurvives .hostSystemd .hostLoss = false) := by decide

/-- Which failure modes the currently INSTALLED guardian set can witness.
    Installed = watchdog timer + Restart=always, both `hostSystemd`. -/
def installedGuardianDomains : List FateDomain := [.hostSystemd]

def modeCovered (m : FailureMode) : Bool :=
  installedGuardianDomains.any (fun d => domainSurvives d m)

def coveredModes : List FailureMode := allFailureModes.filter modeCovered
def uncoveredModes : List FailureMode := allFailureModes.filter (fun m => !modeCovered m)

/-- Two of five failure modes are now covered; three are not. The 41-hour
    outage class IS covered — that is the whole value of the change — and the
    twin refuses to round that up to full coverage. -/
theorem THM_SUB_04_two_of_five_modes_covered :
    coveredModes.length = 2 ∧ uncoveredModes.length = 3 := by decide

/-- Only a peer node closes the remaining three. The vm-1 prober is therefore
    NECESSARY for full coverage, not a nice-to-have. -/
def peerClosesRemaining : Bool :=
  uncoveredModes.all (fun m => domainSurvives .peerNode m)

theorem THM_SUB_05_peer_node_is_necessary_and_sufficient_for_the_rest :
    peerClosesRemaining = true := by decide

/-- Externality is therefore PARTIAL, not complete. `externalitySatisfied`
    (all four guardians present) remains false, and this is why. -/
def externalityCoverageComplete : Bool :=
  allFailureModes.all modeCovered

theorem THM_SUB_06_externality_is_partial :
    externalityCoverageComplete = false := by decide

/-! ## 3b. VACUITY BOUNDARY — review finding 5 (Pi+OpenRouter+Argon)

    The reviewer is right that the structural theorems quantify over hardcoded
    Lean records, not over parsed source or a live systemd graph. Deleting
    `tools/uos_web_watchdog.exe` or disabling the timer would not stop
    `THM_INV_01` from compiling. That is a real limit on what the static model
    can mean, and it is recorded here rather than left for a reader to discover.

    The single bridge from model to reality is the prober in §9, which observes
    sockets, routes, the semantic FPP invariant and the presence of the timer,
    and exits non-zero on divergence. Every claim about the RUNNING system rests
    on that execution, never on the fact that this file type-checks. -/

/-- The static model does not observe the system. Stated as a value so no
    reader can mistake a green `lean` check for a runtime guarantee. -/
def staticModelObservesRuntime : Bool := false

theorem THM_VAC_01_typechecking_is_not_observation :
    staticModelObservesRuntime = false := by decide

/-- What the prober actually checks at runtime, enumerated so the gap between
    modelled and observed is explicit. -/
inductive RuntimeCheck where
  | listenersBound | routesServing | fppSupervisorAlive | watchdogTimerPresent
  deriving DecidableEq, Repr

def proberRuntimeChecks : List RuntimeCheck :=
  [.listenersBound, .routesServing, .fppSupervisorAlive, .watchdogTimerPresent]

/-- Four runtime checks bridge a 60-theorem model. The asymmetry is the honest
    measure of how much of this twin is specification rather than observation. -/
theorem THM_VAC_02_four_runtime_checks_bridge_the_model :
    proberRuntimeChecks.length = 4 := by decide

/-- Modelled aspects that NO runtime check currently verifies. Each is
    specification only, and naming them is the point. -/
def unbridgedAspects : List String :=
  [ "SLOC figures (re-measure with wc, not trusted from this file)"
  , "systemd unit enablement graph (modelled from one observation)"
  , "guardian installation status (modelled; only the timer is probed)"
  , "ha/* dead-man receipt (consumer exists, producer does not)"
  , "holon-epoch state count 170x24 (asserted by the simulator, not re-run)" ]

theorem THM_VAC_03_five_aspects_remain_unbridged :
    unbridgedAspects.length = 5 := by decide

/-! ## 2a. UNIFIED COMMON ONTOLOGY — one component type for the whole system

    Every component of the fractal + hive + FPP + bionic + holarchy system is
    described by ONE record: its stratum, its fractal layer, the fate domain it
    currently runs in, the fate domain its role REQUIRES, its measured SLOC and
    whether it is autonomous. Placement defects then become theorems rather
    than opinions. -/

inductive Stratum where
  | s0External | s1Systemd | s2Container | s3InBeam | s4Holarchy | s5Surface
  deriving DecidableEq, Repr

inductive ComponentRole where
  | subjectOfProtection | outageDetection | recoveryAction | alertDelivery
  | businessLogic | transport | presentation | verification
  deriving DecidableEq, Repr

structure SystemComponent where
  name            : String
  stratum         : Stratum
  layer           : Layer
  role            : ComponentRole
  currentDomain   : FateDomain
  /-- The domain this component's ROLE requires, independent of where it is. -/
  requiredDomain  : FateDomain
  sloc            : Nat
  autonomous      : Bool
  deriving DecidableEq, Repr

/-- Measured 2026-11-05. SLOC are real `wc -l` counts, not estimates. -/
def systemComponents : List SystemComponent :=
  [ -- in-BEAM business logic: correctly placed
    { name := "ecology core_* plane", stratum := .s3InBeam, layer := .l4
    , role := .businessLogic, currentDomain := .cockpitBeam
    , requiredDomain := .cockpitBeam, sloc := 7970, autonomous := true }
  , { name := "mcp 101-route gateway", stratum := .s3InBeam, layer := .l3
    , role := .transport, currentDomain := .cockpitBeam
    , requiredDomain := .cockpitBeam, sloc := 24019, autonomous := true }
  , { name := "ui lustre+wisp+tui", stratum := .s5Surface, layer := .l7
    , role := .presentation, currentDomain := .cockpitBeam
    , requiredDomain := .cockpitBeam, sloc := 65465, autonomous := true }
  , { name := "fpp subsystem", stratum := .s3InBeam, layer := .l3
    , role := .businessLogic, currentDomain := .cockpitBeam
    , requiredDomain := .cockpitBeam, sloc := 14104, autonomous := true }
  , { name := "zenoh transport", stratum := .s3InBeam, layer := .l7
    , role := .transport, currentDomain := .cockpitBeam
    , requiredDomain := .cockpitBeam, sloc := 2088, autonomous := true }
  , { name := "verification registry", stratum := .s3InBeam, layer := .l8
    , role := .verification, currentDomain := .cockpitBeam
    , requiredDomain := .cockpitBeam, sloc := 10481, autonomous := true }
  , { name := "knowledge/km", stratum := .s3InBeam, layer := .l6
    , role := .businessLogic, currentDomain := .cockpitBeam
    , requiredDomain := .cockpitBeam, sloc := 5948, autonomous := true }
  , { name := "podman client", stratum := .s3InBeam, layer := .l2
    , role := .transport, currentDomain := .cockpitBeam
    , requiredDomain := .cockpitBeam, sloc := 1323, autonomous := true }
    -- MISPLACED: outage/recovery roles inside the subject they protect
  , { name := "ha/sentinel", stratum := .s3InBeam, layer := .l2
    , role := .outageDetection, currentDomain := .cockpitBeam
    , requiredDomain := .hostSystemd, sloc := 323, autonomous := true }
  , { name := "ha/deadman_freshness", stratum := .s3InBeam, layer := .l2
    , role := .outageDetection, currentDomain := .cockpitBeam
    , requiredDomain := .hostSystemd, sloc := 286, autonomous := true }
  , { name := "ha/freshness_monitor", stratum := .s3InBeam, layer := .l2
    , role := .outageDetection, currentDomain := .cockpitBeam
    , requiredDomain := .hostSystemd, sloc := 293, autonomous := true }
  , { name := "actors/freshness_actor", stratum := .s3InBeam, layer := .l2
    , role := .outageDetection, currentDomain := .cockpitBeam
    , requiredDomain := .hostSystemd, sloc := 230, autonomous := true }
  , { name := "ha/guard_grid", stratum := .s3InBeam, layer := .l4
    , role := .recoveryAction, currentDomain := .cockpitBeam
    , requiredDomain := .hostSystemd, sloc := 1239, autonomous := true }
  , { name := "actors/guard_grid_actor", stratum := .s3InBeam, layer := .l4
    , role := .recoveryAction, currentDomain := .cockpitBeam
    , requiredDomain := .hostSystemd, sloc := 545, autonomous := true }
  , { name := "S3 bionic crontab/watchdog", stratum := .s3InBeam, layer := .l3
    , role := .outageDetection, currentDomain := .cockpitBeam
    , requiredDomain := .hostSystemd, sloc := 74, autonomous := true }
    -- external verification: right domain, but on-demand only
  , { name := "tools/link_tracker_verifier.ml", stratum := .s1Systemd, layer := .l3
    , role := .verification, currentDomain := .hostSystemd
    , requiredDomain := .hostSystemd, sloc := 1174, autonomous := false }
  , { name := "tools/webui_browser_suite.ml", stratum := .s1Systemd, layer := .l3
    , role := .verification, currentDomain := .hostSystemd
    , requiredDomain := .hostSystemd, sloc := 808, autonomous := false }
  , { name := "tools/webui_bdd_runner.ml", stratum := .s1Systemd, layer := .l3
    , role := .verification, currentDomain := .hostSystemd
    , requiredDomain := .hostSystemd, sloc := 1029, autonomous := false }
  , { name := "tools/verify_website_sop.sh", stratum := .s1Systemd, layer := .l3
    , role := .verification, currentDomain := .hostSystemd
    , requiredDomain := .hostSystemd, sloc := 245, autonomous := false }
    -- the subject itself
  , { name := "c3i-gleam-server (BEAM host)", stratum := .s1Systemd, layer := .l4
    , role := .subjectOfProtection, currentDomain := .hostSystemd
    , requiredDomain := .hostSystemd, sloc := 0, autonomous := true }
  ]

/-- A component is MISPLACED when it does not run in the domain its role
    requires. This is the formal criterion for "needs to be rearranged". -/
def misplaced (c : SystemComponent) : Bool :=
  c.currentDomain != c.requiredDomain

def misplacedComponents : List SystemComponent :=
  systemComponents.filter misplaced

/-- Seven components are misplaced, and every one of them carries an
    outage-detection or recovery role. No business logic is misplaced. -/
theorem THM_PLACE_01_seven_components_misplaced :
    misplacedComponents.length = 7 := by decide

theorem THM_PLACE_02_every_misplacement_is_a_critical_role :
    misplacedComponents.all (fun c =>
      match c.role with
      | .outageDetection => true
      | .recoveryAction  => true
      | _                => false) = true := by decide

/-- The rearrangement budget: 2,990 lines must leave the BEAM. -/
def slocToRelocate : Nat :=
  (misplacedComponents.map (fun c => c.sloc)).foldl (· + ·) 0

theorem THM_PLACE_03_relocation_budget :
    slocToRelocate = 2990 := by decide

/-- Total measured in-BEAM footprint, for proportion. -/
def inBeamSloc : Nat :=
  ((systemComponents.filter (fun c =>
     c.currentDomain = FateDomain.cockpitBeam)).map (fun c => c.sloc)).foldl (· + ·) 0

/-- The relocation is small against the whole: under 3 % of in-BEAM code has
    to move, so this is a surgical change and not a rewrite. -/
theorem THM_PLACE_04_relocation_is_under_three_percent :
    slocToRelocate * 100 < inBeamSloc * 3 := by decide

/-- External verification exists in the right domain but none of it is
    autonomous, so it cannot discharge a detection obligation. -/
def externalButOnDemand : List SystemComponent :=
  systemComponents.filter (fun c =>
    c.currentDomain = FateDomain.hostSystemd
    && c.role = ComponentRole.verification && !c.autonomous)

theorem THM_PLACE_05_all_external_verification_is_on_demand :
    externalButOnDemand.length = 4
  ∧ (externalButOnDemand.map (fun c => c.sloc)).foldl (· + ·) 0 = 3256 := by decide

/-- No autonomous component outside the BEAM holds a detection or recovery
    role: the gap restated over the unified ontology. -/
def soundlyPlacedGuardianCount : Nat :=
  (systemComponents.filter (fun c =>
     c.autonomous
     && c.currentDomain != FateDomain.cockpitBeam
     && (match c.role with
         | .outageDetection => true
         | .recoveryAction  => true
         | _                => false))).length

theorem THM_PLACE_06_no_soundly_placed_guardian :
    soundlyPlacedGuardianCount = 0 := by decide

/-! ## 2b. TRUST INVERSION — implemented 2026-11-05T17:40Z (sa-plan T1..T3)

    The repair is not a port. The in-BEAM `ha/*` modules keep their 2,990 lines
    and stay the rich INTERNAL health model; what changes is their ROLE in the
    ontology (they are no longer the authority anyone relies on to notice
    death) plus roughly 200 new lines of autonomous authority in a DIFFERENT
    fate domain. `THM_PLACE_04` licenses this: the misplaced surface was small
    and its role, not its code, was what was wrong. -/

/-- Demote an in-BEAM detection/recovery component to the internal health model
    it actually is. Components outside the BEAM, and all other roles, are
    untouched. -/
def invertTrust (c : SystemComponent) : SystemComponent :=
  if c.currentDomain = FateDomain.cockpitBeam then
    match c.role with
    | .outageDetection => { c with role := .businessLogic, requiredDomain := .cockpitBeam }
    | .recoveryAction  => { c with role := .businessLogic, requiredDomain := .cockpitBeam }
    | _                => c
  else c

/-- The newly installed out-of-BEAM authority. SLOC are real: the OCaml
    watchdog is 229 lines, the two systemd units and the drop-in 46. -/
def installedExternalComponents : List SystemComponent :=
  [ { name := "tools/uos_web_watchdog.ml", stratum := .s0External, layer := .l4
    , role := .outageDetection, currentDomain := .hostSystemd
    , requiredDomain := .hostSystemd, sloc := 235, autonomous := true }
  , { name := "uos-web-watchdog.timer+service", stratum := .s0External, layer := .l4
    , role := .outageDetection, currentDomain := .hostSystemd
    , requiredDomain := .hostSystemd, sloc := 31, autonomous := true }
  , { name := "c3i-gleam-server.d/10-restart-always.conf", stratum := .s0External, layer := .l4
    , role := .recoveryAction, currentDomain := .hostSystemd
    , requiredDomain := .hostSystemd, sloc := 15, autonomous := true }
  -- REVIEW FIX (Codex finding 5, HIGH): the andon/receipt writer was counted as
  -- an installed alertDelivery guardian although Zenoh delivery is unwired and it
  -- carries 0 SLOC of its own. Counting it inflated THM_INV_04/05. It is tracked
  -- in `guardianInstallStatus` as NOT installed instead, which is the truth.
  ]

def postInversionComponents : List SystemComponent :=
  (systemComponents.map invertTrust) ++ installedExternalComponents

/-- **The inversion result.** After reclassification nothing is misplaced: the
    7 misplacements of `THM_PLACE_01` are resolved without relocating a line. -/
theorem THM_INV_01_no_component_misplaced_after_inversion :
    postInversionComponents.filter misplaced = [] := by decide

/-- The relocation budget is zero: no SLOC moved between fate domains. -/
def slocRelocatedByInversion : Nat :=
  ((postInversionComponents.filter misplaced).map (fun c => c.sloc)).foldl (· + ·) 0

theorem THM_INV_02_zero_sloc_relocated :
    slocRelocatedByInversion = 0 := by decide

/-- Cost of the inversion: 281 new external lines against the 2,990 that a
    relocation would have moved — a 10.6x saving, and no duplicated state
    machine or second source of truth about health. -/
def inversionNewSloc : Nat :=
  (installedExternalComponents.map (fun c => c.sloc)).foldl (· + ·) 0

theorem THM_INV_03_inversion_is_cheaper_than_relocation :
    inversionNewSloc = 281
  ∧ inversionNewSloc * 10 < slocToRelocate := by decide

/-- Autonomous out-of-BEAM components now hold detection and recovery roles,
    where `THM_PLACE_06` previously proved the count was zero. -/
def postInversionSoundGuardians : List SystemComponent :=
  postInversionComponents.filter (fun c =>
    c.autonomous
    && c.currentDomain != FateDomain.cockpitBeam
    && (match c.role with
        | .outageDetection => true
        | .recoveryAction  => true
        | .alertDelivery   => true
        | _                => false))

theorem THM_INV_04_sound_guardians_now_exist :
    postInversionSoundGuardians.length = 3 := by decide

/-- Each critical role is held by at least one autonomous out-of-BEAM
    component. This is the operator's requirement, discharged. -/
def criticalRoleHeldExternally (r : ComponentRole) : Bool :=
  postInversionComponents.any (fun c =>
    c.role = r && c.autonomous && c.currentDomain != FateDomain.cockpitBeam)

/-- Detection and recovery ARE outside the protected domain. Alert delivery is
    NOT: the Zenoh producer is unwired, so a degradation is recorded locally but
    reaches nobody. Stated as a conjunction with a false member so the gap
    cannot be read as covered. -/
theorem THM_INV_05_detection_and_recovery_outside_alerting_not :
    criticalRoleHeldExternally .outageDetection = true
  ∧ criticalRoleHeldExternally .recoveryAction = true
  ∧ criticalRoleHeldExternally .alertDelivery = false := by decide

/-! ### 2b.1 Honest remaining gaps after the inversion

    Two of the four originally specified guardians are installed and verified;
    two are not. The twin records the difference rather than rounding up. -/

structure GuardianStatus where
  name      : String
  installed : Bool
  verified  : Bool
  note      : String
  deriving DecidableEq, Repr

def guardianInstallStatus : List GuardianStatus :=
  [ { name := "uos-web-watchdog.timer (60 s, out-of-BEAM)"
    , installed := true,  verified := true
    , note := "enabled; fired; receipt var/watchdog/latest.json status=healthy" }
  , { name := "Restart=always on the cockpit"
    , installed := true,  verified := true
    , note := "SIGTERM test 2026-11-05: PID 441369 -> 529996, NRestarts=1, routes 200" }
  , { name := "Andon delivery to Zenoh uos/v1 topic"
    , installed := false, verified := false
    , note := "receipt + andon.jsonl written; Zenoh publisher NOT wired" }
  , { name := "peer prober on vm-1"
    , installed := false, verified := false
    , note := "single-host detection only; a host-wide failure is still unseen" }
  ]

theorem THM_INV_06_two_of_four_guardians_installed_and_verified :
    (guardianInstallStatus.filter (fun g => g.installed && g.verified)).length = 2
  ∧ (guardianInstallStatus.filter (fun g => !g.installed)).length = 2 := by decide

/-- The in-BEAM dead-man channel is specified and consumed by the watchdog but
    not yet PRODUCED by `ha/*`, so the receipt reads `absent`. Until the
    publisher ships in a reviewed release, the watchdog's liveness verdict
    rests on sockets and routes alone. -/
def haReceiptPublished : Bool := false

theorem THM_INV_07_ha_dead_man_channel_not_yet_published :
    haReceiptPublished = false := by decide

/-! ### 2b.2 Ontology repair (sa-plan T2) -/

/-- `get_modules()` now carries 8 records; `module_count` is derived from the
    list length, so the live plane will report 8 once a reviewed release ships. -/
def declaredModuleCountAfterFix : Nat := 8

theorem THM_INV_08_ontology_undercount_closed :
    declaredModuleCountAfterFix = onDiskCoreModuleCount := by decide

/-- The source is fixed; the RUNNING capsule is immutable and still reports 7.
    Specification repair is not deployment. -/
def runningCapsuleModuleCount : Nat := 7

theorem THM_INV_09_source_fixed_runtime_awaiting_release :
    declaredModuleCountAfterFix ≠ runningCapsuleModuleCount := by decide
/-! ## 4. RUNTIME ASPECT -/

structure RuntimeObservation where
  observedUtc          : String
  cockpitHttpBound     : Bool
  cockpitHttpsBound    : Bool
  saPlanBound          : Bool
  zenohBound           : Bool
  routesProbed         : Nat
  routes200            : Nat
  moduleCount          : Nat
  casteCount           : Nat
  serviceCount         : Nat
  fppActorsAlive       : Nat
  fppSupervisorRunning : Bool
  zenohTopics          : Nat
  sccCount             : Nat
  a2uiComponents       : Nat
  canonicalBroken      : Nat
  deriving DecidableEq, Repr

structure StructuralExpectation where
  requiredRoutes     : Nat
  requiredModules    : Nat
  requiredCastes     : Nat
  requiredServices   : Nat
  requiredFppActors  : Nat
  requiredZenohTopics: Nat
  requiredScc        : Nat
  minA2ui            : Nat
  maxCanonicalBroken : Nat
  deriving DecidableEq, Repr

def canonicalExpectation : StructuralExpectation :=
  { requiredRoutes := 69, requiredModules := 7, requiredCastes := 5, requiredServices := 8
  , requiredFppActors := 40, requiredZenohTopics := 12, requiredScc := 1
  , minA2ui := 233, maxCanonicalBroken := 0 }

/-- The reading a FULLY ALIGNED plane would produce -- a synthetic ideal, not
    a reading anyone took. It exists so the theorems below can state what
    alignment MEANS without recording a fact that will rot.

    It replaces `observationNow`, which claimed `observedUtc :=
    "2026-11-05T17:05:00Z"` and `routes200 := 69` while the prober that
    produced it probed 5 routes and inferred the other 64. A theorem named
    `THM_RUN_01_aligned_now` then proved the system healthy from it, and would
    have gone on proving that with the cockpit in the ground. -/
def idealReading : RuntimeObservation :=
  { observedUtc := "<synthetic: no observation recorded in the proof plane>"
  , cockpitHttpBound := true, cockpitHttpsBound := true
  , saPlanBound := true, zenohBound := true
  , routesProbed := 69, routes200 := 69
  , moduleCount := 7, casteCount := 5, serviceCount := 8
  , fppActorsAlive := 40, fppSupervisorRunning := true
  , zenohTopics := 12, sccCount := 1, a2uiComponents := 239
  , canonicalBroken := 0 }

/-- State during the 41-hour outage. -/
def observationDuringOutage : RuntimeObservation :=
  { idealReading with
    observedUtc := "2026-11-05T15:41:53Z"
  , cockpitHttpBound := false, cockpitHttpsBound := false
  , routesProbed := 0, routes200 := 0
  , moduleCount := 0, casteCount := 0, serviceCount := 0
  , fppActorsAlive := 0, fppSupervisorRunning := false
  , sccCount := 0, a2uiComponents := 0, canonicalBroken := 1 }

/-- Fail-closed structural + runtime alignment. -/
def runtimeAligned (e : StructuralExpectation) (o : RuntimeObservation) : Bool :=
  o.cockpitHttpBound && o.cockpitHttpsBound && o.saPlanBound && o.zenohBound
  && (o.routes200 == o.routesProbed) && (o.routesProbed ≥ e.requiredRoutes)
  && (o.moduleCount == e.requiredModules)
  && (o.casteCount == e.requiredCastes)
  && (o.serviceCount == e.requiredServices)
  && (o.fppActorsAlive == e.requiredFppActors)
  && o.fppSupervisorRunning
  && (o.zenohTopics == e.requiredZenohTopics)
  && (o.sccCount == e.requiredScc)
  && (o.a2uiComponents ≥ e.minA2ui)
  && (o.canonicalBroken ≤ e.maxCanonicalBroken)

theorem THM_RUN_01_ideal_reading_aligns :
    runtimeAligned canonicalExpectation idealReading = true := by decide

theorem THM_RUN_02_divergent_during_outage :
    runtimeAligned canonicalExpectation observationDuringOutage = false := by decide

/-- Losing only the FPP supervisor already forces divergence: a plane with
    39/40 actors is not the modelled plane. -/
theorem THM_RUN_03_single_actor_loss_forces_divergence :
    runtimeAligned canonicalExpectation
      { idealReading with fppActorsAlive := 39 } = false := by decide

/-! ## 5. PERFORMANCE ASPECT

    All quantities are integers. Latency is in HUNDREDTHS of a millisecond and
    token shares in basis points, so no floating point enters the model. -/

structure PerfBudget where
  meanLatencyMaxCentiMs : Nat
  tokenShareMaxBps      : Nat
  marginMinBps          : Nat
  hardCeilingBps        : Nat
  minInvariantsProved   : Nat
  deriving DecidableEq, Repr

def perfBudget : PerfBudget :=
  { meanLatencyMaxCentiMs := 1000   -- 10.00 ms target
  , tokenShareMaxBps      := 200    -- < 2 %
  , marginMinBps          := 4000   -- 40 % untouched
  , hardCeilingBps        := 6000
  , minInvariantsProved   := 12 }

structure PerfObservation where
  meanLatencyCentiMs : Nat
  agyTokenShareBps   : Nat
  mandatoryMarginBps : Nat
  hardCeilingBps     : Nat
  invariantsProved   : Nat
  deriving DecidableEq, Repr

/-- HISTORICAL FIXTURE, measured 2026-11-05T17:05Z: mean latency 25.08 ms
    from the 69-endpoint sweep, the rest from `/api/v1/core-evo/status`.

    Named for the moment it was taken, not for "now". The theorems below are
    statements about THIS RECORDED READING and stay true forever, including
    `THM_PERF_02`, which records that the 10.00 ms latency budget was
    violated at that moment. The live reading is taken by
    `formal/mojo/core_evo_oracle.mojo`. -/
def perfAtRepair : PerfObservation :=
  { meanLatencyCentiMs := 2508
  , agyTokenShareBps   := 101
  , mandatoryMarginBps := 4000
  , hardCeilingBps     := 6000
  , invariantsProved   := 12 }

def latencyWithinBudget (b : PerfBudget) (p : PerfObservation) : Bool :=
  p.meanLatencyCentiMs ≤ b.meanLatencyMaxCentiMs

def tokenShareWithinBudget (b : PerfBudget) (p : PerfObservation) : Bool :=
  p.agyTokenShareBps ≤ b.tokenShareMaxBps

def marginWithinBudget (b : PerfBudget) (p : PerfObservation) : Bool :=
  p.mandatoryMarginBps ≥ b.marginMinBps

def invariantsWithinBudget (b : PerfBudget) (p : PerfObservation) : Bool :=
  p.invariantsProved ≥ b.minInvariantsProved

/-- The quota disciplines hold with room to spare: 1.01 % against a 2 % cap. -/
theorem THM_PERF_01_token_share_and_margin_hold :
    tokenShareWithinBudget perfBudget perfAtRepair = true
  ∧ marginWithinBudget perfBudget perfAtRepair = true
  ∧ invariantsWithinBudget perfBudget perfAtRepair = true := by decide

/-- The latency budget is VIOLATED: 25.08 ms observed against a 10.00 ms
    target. Recorded as a failure, not smoothed away. -/
theorem THM_PERF_02_latency_budget_violated :
    latencyWithinBudget perfBudget perfAtRepair = false := by decide

def perfFullyGreen (b : PerfBudget) (p : PerfObservation) : Bool :=
  latencyWithinBudget b p && tokenShareWithinBudget b p
  && marginWithinBudget b p && invariantsWithinBudget b p

/-- Consequently performance is not fully green, and the twin says so. -/
theorem THM_PERF_03_performance_not_fully_green :
    perfFullyGreen perfBudget perfAtRepair = false := by decide

/-- The margin is a hard floor: dropping below 40 % fails even with everything
    else ideal. -/
theorem THM_PERF_04_margin_is_a_hard_floor :
    perfFullyGreen perfBudget { perfAtRepair with mandatoryMarginBps := 3999 } = false
    := by decide

/-! ## 6. MANAGEMENT ASPECT — lifecycle ordering and aspect coverage -/

inductive LifecycleOp where
  | preflight | verifyCapsule | startPodmanSocket | startTarget
  | activateMcp | agentParity | probeRoutes | probeZenoh
  | installWatchdog | verifyRecovery
  deriving DecidableEq, Repr

/-- Canonical order. Index is the position in the startup sequence. -/
def opOrder : LifecycleOp → Nat
  | .preflight          => 0
  | .verifyCapsule      => 1
  | .startPodmanSocket  => 2
  | .startTarget        => 3
  | .activateMcp        => 4
  | .agentParity        => 5
  | .probeRoutes        => 6
  | .probeZenoh         => 7
  | .installWatchdog    => 8
  | .verifyRecovery     => 9

/-- The podman socket MUST precede the target: the cockpit samples podman
    during boot, so a socket created afterwards is never read. -/
theorem THM_MGT_01_podman_socket_precedes_target :
    opOrder .startPodmanSocket < opOrder .startTarget := by decide

/-- Capsule verification precedes every service start, so a restart cannot
    silently bring up an unpinned release. -/
theorem THM_MGT_02_capsule_verified_before_any_start :
    opOrder .verifyCapsule < opOrder .startPodmanSocket
  ∧ opOrder .verifyCapsule < opOrder .startTarget := by decide

/-- MCP precedes agent parity: castes reach the system through MCP. -/
theorem THM_MGT_03_mcp_before_agents :
    opOrder .activateMcp < opOrder .agentParity := by decide

/-- Recovery verification is last: you cannot prove recovery before the
    watchdog that performs it exists. -/
theorem THM_MGT_04_recovery_verified_after_watchdog_installed :
    opOrder .installWatchdog < opOrder .verifyRecovery := by decide

inductive ManagedAspect where
  | structural | ontological | runtime | performance
  | outageDetection | recovery | governance
  deriving DecidableEq, Repr

def allManagedAspects : List ManagedAspect :=
  [.structural, .ontological, .runtime, .performance,
   .outageDetection, .recovery, .governance]

structure AspectCoverage where
  aspect   : ManagedAspect
  modelled : Bool
  verified : Bool
  evidence : String
  deriving DecidableEq, Repr

def aspectLedger : List AspectCoverage :=
  [ { aspect := .structural,      modelled := true, verified := true
    , evidence := "THM_STR_01..07 — 24 units, 3 missing, 1 inadequate policy" }
  , { aspect := .ontological,     modelled := true, verified := true
    , evidence := "THM_ONT_01..07 — 10 layers, 7 modules, 8 services, 5 castes, 170x24=4080" }
  , { aspect := .runtime,         modelled := true, verified := true
    , evidence := "THM_RUN_01..03 — fail-closed alignment relation + prober" }
  , { aspect := .performance,     modelled := true, verified := true
    , evidence := "THM_PERF_01..04 — quota green, latency budget violated" }
  , { aspect := .outageDetection, modelled := true, verified := true
    , evidence := "THM_EXT_01..03 — no sound guardian exists today" }
  , { aspect := .recovery,        modelled := true, verified := true
    , evidence := "THM_EXT_04..07 — externality invariant; required set not installed" }
  , { aspect := .governance,      modelled := true, verified := true
    , evidence := "THM_PROV_01 — ceiling 93, admission false" }
  ]

/-- Every aspect the operator named is modelled and carries its own theorems. -/
theorem THM_MGT_05_all_seven_aspects_managed :
    aspectLedger.length = allManagedAspects.length
  ∧ aspectLedger.all (fun a => a.modelled && a.verified) = true := by decide

/-! ## 7. Setup path as a verified chain -/

inductive SetupPhase where
  | p0Toolchain | p1Bootstrap | p2GrantReview | p3McpActivate
  | p4AgentParity | p5ServiceVerify | p6HiveVerify | p7Observability
  deriving DecidableEq, Repr

def phaseIndex : SetupPhase → Nat
  | .p0Toolchain     => 0
  | .p1Bootstrap     => 1
  | .p2GrantReview   => 2
  | .p3McpActivate   => 3
  | .p4AgentParity   => 4
  | .p5ServiceVerify => 5
  | .p6HiveVerify    => 6
  | .p7Observability => 7

def allPhases : List SetupPhase :=
  [.p0Toolchain, .p1Bootstrap, .p2GrantReview, .p3McpActivate,
   .p4AgentParity, .p5ServiceVerify, .p6HiveVerify, .p7Observability]

theorem THM_SET_01_eight_phases : allPhases.length = 8 := by decide

/-- Observability is terminal: a system set up without it is unobserved, which
    is precisely the state that produced the 41-hour outage. -/
theorem THM_SET_02_observability_is_terminal :
    allPhases.all (fun p => phaseIndex p ≤ phaseIndex .p7Observability) = true
    := by decide

/-- Hive verification requires both agent parity and service verification. -/
theorem THM_SET_03_hive_verify_after_parity_and_services :
    phaseIndex .p4AgentParity < phaseIndex .p6HiveVerify
  ∧ phaseIndex .p5ServiceVerify < phaseIndex .p6HiveVerify := by decide

/-! ## 8. Core set vs full set -/

/-- The irreducible set for `uos-core-evo`: remove any one and the plane cannot
    serve `/core-evo` and its three JSON APIs. -/
def coreSet : List String :=
  [ "c3i-gleam-server", "c3i-zenoh-router-1", "c3i-sa-plan-http"
  , "podman.socket", "uos-clock-guard@", "uos-ecology@capsule"
  , "uos-cognitive-worker" ]

theorem THM_CORE_01_core_set_is_seven : coreSet.length = 7 := by decide

/-- Full set across the five strata, plus the external stratum the externality
    invariant requires. -/
def fullSetCounts : List (String × Nat) :=
  [ ("S1 systemd units",            24)
  , ("S2 podman containers",         2)
  , ("S3 in-BEAM bionic services",   8)
  , ("S3 FPP actor twins",          40)
  , ("S4 holarchy castes",           5)
  , ("S5 surfaces and buses",        6)
  , ("S0 required external guardians", 4) ]

def fullSetTotal : Nat := (fullSetCounts.map (fun p => p.2)).foldl (· + ·) 0

theorem THM_FULL_01_full_set_census : fullSetTotal = 89 := by decide

/-- The external stratum is non-empty by construction: a fully functional
    system is not fully functional without guardians outside it. -/
theorem THM_FULL_02_external_stratum_required :
    (fullSetCounts.find? (fun p => p.1 == "S0 required external guardians")).map
      (fun p => p.2) = some 4 := by decide

/-! ## 9. RUNTIME CLAIMS, UNIVERSALLY QUANTIFIED

    The theorems in section 4 bind `runtimeAligned` to two fixtures: a
    synthetic `idealReading` and a recorded `observationDuringOutage`. Those
    are statements about data. The statements below are about the RELATION,
    for every observation there could ever be, so they cannot be outlived by
    the system they describe. -/

/-- Fail-closed on no evidence: an observation that read nothing never
    aligns. A prober that cannot see the system must report divergence, not
    health. This is the property the whole monitoring plane rests on. -/
theorem THM_RUN_04_fail_closed_on_no_evidence
    (o : RuntimeObservation)
    (h : o.cockpitHttpBound = false) :
    runtimeAligned canonicalExpectation o = false := by
  simp [runtimeAligned, h]

/-- Any dead listener forces divergence, whatever else is ideal. -/
theorem THM_RUN_05_dead_sa_plan_forces_divergence
    (o : RuntimeObservation) (h : o.saPlanBound = false) :
    runtimeAligned canonicalExpectation o = false := by
  simp [runtimeAligned, h]

/-- A stopped FPP supervisor forces divergence on its own. -/
theorem THM_RUN_06_stopped_supervisor_forces_divergence
    (o : RuntimeObservation) (h : o.fppSupervisorRunning = false) :
    runtimeAligned canonicalExpectation o = false := by
  simp [runtimeAligned, h]

/-- Routes that answered must equal routes probed: partial success is
    divergence, not partial credit. Stated for every pair of counts. -/
theorem THM_RUN_07_partial_route_success_is_divergence
    (o : RuntimeObservation) (h : o.routes200 ≠ o.routesProbed) :
    runtimeAligned canonicalExpectation o = false := by
  simp [runtimeAligned, h]

/-- Alignment is decidable for every expectation and every observation, which
    is precisely what lets the Mojo oracle evaluate the identical relation
    concretely against a live reading. -/
theorem THM_RUN_08_alignment_decidable
    (e : StructuralExpectation) (o : RuntimeObservation) :
    runtimeAligned e o = true ∨ runtimeAligned e o = false := by
  cases runtimeAligned e o <;> simp

/-! ## 10. OBSERVATION PLANE — deliberately absent

    The executable conformance prober that stood here until `20261106-0108`
    has moved to `formal/mojo/core_evo_oracle.mojo`, and the two planes are
    run together by `tools/lean_mojo_differential.ml`, which fails closed when
    they disagree.

    This file has no `def main`. That is not tidiness: `THM_VAC_01` in this
    very file proves `staticModelObservesRuntime = false`, and a `def main`
    sitting beneath that theorem invited exactly the reading the theorem
    denies. The prober's output looked like the proof's conclusion.

    A `lean` exit code from this file means the algebra is consistent. Nothing
    more. -/

end UOS.CoreEvoTwin
