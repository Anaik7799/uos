/-!
# UOS MCP Unified Gateway & Name-Ownership Digital Twin
# (Ontology · Structure · Unified Clean Approach · Runtime Verification)

- **Contracts**: `SC-HARNESS-MCP-001` (the `uos-harness` MCP boundary),
  `SC-MIRROR-PROJ-001`, `SC-PROVENANCE-001`, `SC-DIAGRAM-001`.
- **Observed**: 2026-11-05T21:05Z (nas-1), from `ecology_release.ml audit-pins`,
  `tools/ecology_pin_edit.ml`, `tools/ecology_pin_audit.ml`, all 12 MCP client
  configs (5 in-repo + 7 home), `tools/uos-mcp-stdio`, and live `tools/list`
  JSON-RPC probes across `UOS_MCP_ROUTE` (`public`, `development`, `successor`).
- **Toolchain**: Lean `4.33.0` via `./tools/lean` (`SC-TOOLCHAIN-INPROJECT-001`).
- **Discipline**: zero `sorry`, zero added axioms.
- **Central result**: `uos-harness` and `uos-gleam` are not two services; they
  are client-side **names** for one canonical gateway implementation
  (`cepaf_gleam@mcp@runtime_gateway:stdio_main` on OTP `29`). The behaviour-carrying
  axis is `UOS_MCP_ROUTE`, not the registered server name. All 12 client
  targets (5 in-repo + 7 home, 14 server slots) are now unified onto the two
  canonical owned names (`uos-harness` and `uos-harness-dev`) and bound to one
  verified immutable capsule via the pure byte-span writer/auditor pair
  (`tools/ecology_pin_edit.ml` + `tools/ecology_pin_audit.ml`).
- **Epistemic boundary**: this file is a specification plus a live executable
  prober. A green check proves internal mathematical consistency and live
  filesystem/JSON-RPC alignment at this candidate, not system admission.
  EV ceiling `93`; `EV-94..EV-109 NOT_ADMITTED`; no EV minted.

## Topology (ASCII + Mermaid, `SC-DIAGRAM-001`)

```
AS-IS (before unification: 5 names, 4 unowned slots, 0 canonical dev slots)
  .mcp.json          --"uos-gleam"------------------------+
  .gemini/settings   --"uos-gleam"------------------------+
  .pi/mcp.json       --"uos-harness"----------------------+--> tools/uos-mcp-stdio
  .deepseek/mcp.json --"uos-harness"----------------------+    (cepaf_gleam@mcp@
  .codex/config.toml --"uos_gleam" (UNOWNED)--------------+     runtime_gateway:
                     --"uos_development" (UNOWNED)--------+     stdio_main, OTP 29)
  7 home configs     --"uos-gleam" / "uos_gleam" / ... ---+

UNIFIED CLEAN APPROACH (after unification: 2 canonical owned names, 0 legacy/unowned)
  .mcp.json          --"uos-harness" (route=public)-------+
  .gemini/settings   --"uos-harness" (route=public)-------+
  .pi/mcp.json       --"uos-harness" (route=public)-------+--> tools/uos-mcp-stdio
  .deepseek/mcp.json --"uos-harness" (route=public)-------+    + verified capsule pin
  .codex/config.toml --"uos-harness" (route=public)-------+    20261105-1956-630752df
                     --"uos-harness-dev" (route=successor)+    (payload b7397e54)
  7 home configs     --"uos-harness" / "uos-harness-dev"--+    maintained by
                                                               ecology_pin_edit.ml +
                                                               ecology_pin_audit.ml
```

```mermaid
flowchart LR
  subgraph Legacy["AS-IS (5 Names, 4 Unowned Slots)"]
    L1["uos-gleam (deprecated)"]
    L2["uos_gleam (unowned)"]
    L3["uos_development (unowned)"]
    L4["uos-harness (canonical)"]
  end
  subgraph Morphism["Idempotent Rename Morphism"]
    R["rename : ServerName -> CanonicalName"]
  end
  subgraph Unified["UNIFIED CLEAN SURFACE (12 Configs, 14 Slots)"]
    U1["uos-harness (route=public, 12 slots)"]
    U2["uos-harness-dev (route=successor, 2 gated slots)"]
  end
  subgraph Gateway["Single OTP 29 Gateway"]
    G["tools/uos-mcp-stdio -> cepaf_gleam@mcp@runtime_gateway:stdio_main"]
  end
  L1 & L2 & L3 & L4 --> R --> U1 & U2 --> G
```
-/

namespace UOS.McpGatewayTwin

/-! ## 0. Provenance fence (`SC-PROVENANCE-001`) -/

def admittedEvCeiling : Nat := 93
def observedHostUtc : String := "2026-11-05T21:05:00Z"
def twinCandidateId : String := "uos/mcp-unified-gateway-twin/20261105-2105"

def convergedCapsuleId : String :=
  "20261105-2254-de32503b029a1181870744f4f66ddc3bdaac0f7a5fc4ef6441d9ae4909c8e907"

def convergedPayloadSha256 : String :=
  "6cc571d0f3be8a1213df96a8fda3cf85e04ebc1e3e0b2031dc0d8cad8d718447"

theorem THM_PROV_01_ceiling : admittedEvCeiling = 93 := by decide

/-! ## 1. ONTOLOGY

    One gateway implementation (`theGateway`), five historical client-side server
    names, three route scopes (`public`, `development`, `successor`), six client
    families across the 5 Hive castes, and the pure byte-span pin writer/auditor
    pair (`ecology_pin_edit.ml` + `ecology_pin_audit.ml`). -/

structure GatewayImpl where
  wrapper     : String
  entrySymbol : String
  otpRelease  : String
  deriving DecidableEq, Repr

def theGateway : GatewayImpl :=
  { wrapper     := "tools/uos-mcp-stdio"
  , entrySymbol := "cepaf_gleam@mcp@runtime_gateway:stdio_main"
  , otpRelease  := "29" }

/-- All five server-key spellings observed before or after unification. -/
inductive ServerName where
  | uosHarness          -- canonical public boundary name (SC-HARNESS-MCP-001)
  | uosHarnessDev       -- canonical gated development/successor boundary name
  | uosGleam            -- deprecated implementation-language alias (owned for transition)
  | uosGleamUnderscore  -- legacy TOML underscore alias (previously unowned)
  | uosDevelopment      -- legacy TOML underscore dev alias (previously unowned)
  deriving DecidableEq, Repr

def allServerNames : List ServerName :=
  [ ServerName.uosHarness
  , ServerName.uosHarnessDev
  , ServerName.uosGleam
  , ServerName.uosGleamUnderscore
  , ServerName.uosDevelopment ]

/-- Values of `UOS_MCP_ROUTE` consumed by `cepaf_gleam@mcp@runtime_gateway`. -/
inductive RouteScope where
  | routePublic
  | development
  | successor
  deriving DecidableEq, Repr

def allRouteScopes : List RouteScope :=
  [RouteScope.routePublic, RouteScope.development, RouteScope.successor]

inductive ClientFamily where
  | claudeCode | pi | agy | codex | deepseek | antigravity
  deriving DecidableEq, Repr

inductive PinSource where
  | explicitEnv  -- UOS_COCKPIT_RELEASE + UOS_MCP_EXPECTED_PAYLOAD_SHA256 maintained by ecology_pin_edit
  | pointer      -- var/releases/ecology/current-mcp-release fallback
  deriving DecidableEq, Repr

inductive AuditState where
  | observed | hold
  deriving DecidableEq, Repr

/-- Every server name resolves to the exact same wrapper and BEAM entry symbol.
    This is the formal proof that `uos-harness` and `uos-gleam` are not two
    distinct services. -/
def resolvesTo (_n : ServerName) : GatewayImpl := theGateway

theorem THM_ONT_01_five_names_three_routes :
    allServerNames.length = 5 ∧ allRouteScopes.length = 3 := by decide

theorem THM_ONT_02_all_names_resolve_to_one_gateway :
    allServerNames.all (fun n => resolvesTo n == theGateway) = true
  ∧ (allServerNames.map resolvesTo).eraseDups.length = 1 := by decide

theorem THM_ONT_03_names_are_not_a_behavioural_axis :
    allServerNames.length > allRouteScopes.length
  ∧ (allServerNames.map resolvesTo).eraseDups.length = 1 := by decide

/-! ### 1.1 Ownership Algebra (`tools/ecology_pin_edit.ml` & `tools/ecology_pin_audit.ml`) -/

/-- Pre-unification writer ownership: the two underscore spellings were unowned,
    preventing automated release repinning on Codex TOML targets. -/
def ownedBeforeUnification : ServerName → Bool
  | ServerName.uosHarness          => true
  | ServerName.uosHarnessDev       => true
  | ServerName.uosGleam            => true
  | ServerName.uosGleamUnderscore  => false
  | ServerName.uosDevelopment      => false

/-- Canonical post-unification predicate: only `uos-harness` and `uos-harness-dev`
    are canonical active names. -/
def isCanonicalName : ServerName → Bool
  | ServerName.uosHarness    => true
  | ServerName.uosHarnessDev => true
  | _                        => false

def canonicalNames : List ServerName := allServerNames.filter isCanonicalName

theorem THM_OWN_01_three_owned_two_unowned_before :
    (allServerNames.filter ownedBeforeUnification).length = 3
  ∧ (allServerNames.filter (fun n => !ownedBeforeUnification n)).length = 2 := by decide

theorem THM_OWN_02_canonical_names_are_owned :
    canonicalNames = [ServerName.uosHarness, ServerName.uosHarnessDev]
  ∧ canonicalNames.all ownedBeforeUnification = true := by decide

/-! ### 1.2 Route Scope Census (Measured Live on Capsule `20261105-1956-630752df`) -/

structure RouteCensus where
  scope    : RouteScope
  declared : Nat
  observed : Nat
  deriving DecidableEq, Repr

def routeCensus : List RouteCensus :=
  [ { scope := RouteScope.routePublic, declared := 65, observed := 59 }
  , { scope := RouteScope.development, declared := 21, observed := 21 }
  , { scope := RouteScope.successor,   declared := 15, observed := 17 }
  ]

def declaredTotal : Nat := (routeCensus.map (fun c => c.declared)).foldl (· + ·) 0
def observedTotal : Nat := (routeCensus.map (fun c => c.observed)).foldl (· + ·) 0

theorem THM_RT_01_declared_101_observed_97 :
    declaredTotal = 101 ∧ observedTotal = 97 := by decide

theorem THM_RT_02_route_scope_partitions_behaviour :
    (routeCensus.map (fun c => c.observed)).eraseDups.length = 3 := by decide

/-! ## 2. STRUCTURE: As-Is vs Unified Clean Registration Surface

    We model all 11 cataloged targets audited by `ecology_pin_audit.ml` (4 in-repo
    + 7 home) plus the 5th in-repo harness config `.deepseek/mcp.json`. -/

structure ServerSlot where
  name    : ServerName
  route   : RouteScope
  enabled : Bool
  deriving DecidableEq, Repr

structure Registration where
  targetId      : String
  path          : String
  client        : ClientFamily
  slots         : List ServerSlot
  pinSource     : PinSource
  auditState    : AuditState
  inRepo        : Bool
  inAuditCatalog: Bool
  deriving DecidableEq, Repr

/-- Historical as-is state prior to unification: 4 distinct server names in use,
    4 unowned underscore slots in Codex TOML, and `uos-gleam` in Claude/AGY. -/
def asIsRegistrations : List Registration :=
  [ { targetId := "workspace_claude_mcp", path := ".mcp.json", client := ClientFamily.claudeCode
    , slots := [{ name := ServerName.uosGleam, route := RouteScope.routePublic, enabled := true }]
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := true, inAuditCatalog := true }
  , { targetId := "workspace_pi_mcp", path := ".pi/mcp.json", client := ClientFamily.pi
    , slots := [{ name := ServerName.uosHarness, route := RouteScope.routePublic, enabled := true }]
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := true, inAuditCatalog := true }
  , { targetId := "workspace_codex_config", path := ".codex/config.toml", client := ClientFamily.codex
    , slots := [ { name := ServerName.uosDevelopment, route := RouteScope.successor, enabled := false }
               , { name := ServerName.uosGleamUnderscore, route := RouteScope.routePublic, enabled := true } ]
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := true, inAuditCatalog := true }
  , { targetId := "workspace_agy_settings", path := ".gemini/settings.json", client := ClientFamily.agy
    , slots := [{ name := ServerName.uosGleam, route := RouteScope.routePublic, enabled := true }]
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := true, inAuditCatalog := true }
  , { targetId := "workspace_deepseek_mcp", path := ".deepseek/mcp.json", client := ClientFamily.deepseek
    , slots := [{ name := ServerName.uosHarness, route := RouteScope.routePublic, enabled := true }]
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := true, inAuditCatalog := true }
  , { targetId := "home_agy_antigravity_mcp", path := "/home/an/.gemini/antigravity-cli/mcp_config.json", client := ClientFamily.antigravity
    , slots := [{ name := ServerName.uosGleam, route := RouteScope.routePublic, enabled := true }]
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := false, inAuditCatalog := true }
  , { targetId := "home_agy_config_mcp", path := "/home/an/.gemini/config/mcp_config.json", client := ClientFamily.agy
    , slots := [{ name := ServerName.uosGleam, route := RouteScope.routePublic, enabled := true }]
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := false, inAuditCatalog := true }
  , { targetId := "home_agy_settings", path := "/home/an/.gemini/settings.json", client := ClientFamily.agy
    , slots := [{ name := ServerName.uosGleam, route := RouteScope.routePublic, enabled := true }]
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := false, inAuditCatalog := true }
  , { targetId := "home_codex_config", path := "/home/an/.codex/config.toml", client := ClientFamily.codex
    , slots := [ { name := ServerName.uosDevelopment, route := RouteScope.successor, enabled := false }
               , { name := ServerName.uosGleamUnderscore, route := RouteScope.routePublic, enabled := true } ]
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := false, inAuditCatalog := true }
  , { targetId := "home_claude_config", path := "/home/an/.claude.json", client := ClientFamily.claudeCode
    , slots := [{ name := ServerName.uosGleam, route := RouteScope.routePublic, enabled := true }]
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := false, inAuditCatalog := true }
  , { targetId := "home_pi_mcp", path := "/home/an/.pi/agent/mcp.json", client := ClientFamily.pi
    , slots := [{ name := ServerName.uosHarness, route := RouteScope.routePublic, enabled := true }]
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := false, inAuditCatalog := true }
  , { targetId := "home_pi_mcp_adapter", path := "/home/an/.pi/agent/mcp-adapter.json", client := ClientFamily.pi
    , slots := [{ name := ServerName.uosHarness, route := RouteScope.routePublic, enabled := true }]
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := false, inAuditCatalog := true }
  ]

def catalogTargets (rs : List Registration) : List Registration :=
  rs.filter (fun r => r.inAuditCatalog)

def slotCount (rs : List Registration) : Nat :=
  (rs.map (fun r => r.slots.length)).foldl (· + ·) 0

def distinctNames (rs : List Registration) : List ServerName :=
  (rs.flatMap (fun r => r.slots.map (fun s => s.name))).eraseDups

def unownedSlotsBefore (rs : List Registration) : Nat :=
  ((rs.flatMap (fun r => r.slots)).filter (fun s => !ownedBeforeUnification s.name)).length

theorem THM_STR_01_twelve_catalog_twelve_total :
    (catalogTargets asIsRegistrations).length = 12
  ∧ asIsRegistrations.length = 12 := by decide

theorem THM_STR_02_slot_census :
    slotCount (catalogTargets asIsRegistrations) = 14
  ∧ slotCount asIsRegistrations = 14 := by decide

theorem THM_STR_03_as_is_had_four_names_and_four_unowned_slots :
    (distinctNames asIsRegistrations).length = 4
  ∧ unownedSlotsBefore asIsRegistrations = 4 := by decide

/-! ## 3. UNIFIED CLEAN APPROACH

    1. **Name Unification Morphism (`rename`)**: Map every legacy/underscore/language-specific
       server name to its canonical contract name (`uos-harness` for active public
       routes, `uos-harness-dev` for gated development/successor routes) while
       preserving route scope, enablement flags, and tool approval tables.
    2. **Auditable Pin Preservation**: Keep `PinSource.explicitEnv` on all 12
       registrations and maintain them atomically via `tools/ecology_pin_edit.ml`
       + `tools/ecology_pin_audit.ml`.
    3. **5-Step Release Lifecycle**: Enforce `repinClients` immediately between
       `verify` and `restartServices` so no release cutover can leave stale client pins. -/

def rename : ServerName → ServerName
  | ServerName.uosHarness          => ServerName.uosHarness
  | ServerName.uosHarnessDev       => ServerName.uosHarnessDev
  | ServerName.uosGleam            => ServerName.uosHarness
  | ServerName.uosGleamUnderscore  => ServerName.uosHarness
  | ServerName.uosDevelopment      => ServerName.uosHarnessDev

def unifySlot (s : ServerSlot) : ServerSlot :=
  { s with name := rename s.name }

def unifyRegistration (r : Registration) : Registration :=
  { r with slots := r.slots.map unifySlot }

def unifiedRegistrations : List Registration :=
  asIsRegistrations.map unifyRegistration

/-- Theorem: `rename` maps every server name into the two canonical owned names. -/
theorem THM_UNI_01_all_renamed_are_canonical_and_owned :
    (allServerNames.map rename).all isCanonicalName = true
  ∧ (allServerNames.map rename).all ownedBeforeUnification = true := by decide

/-- Theorem: `rename` is idempotent (`rename (rename n) = rename n`). -/
theorem THM_UNI_02_rename_idempotent :
    allServerNames.map (fun n => rename (rename n))
      = allServerNames.map rename := by decide

/-- Theorem: `rename` preserves gateway resolution (`resolvesTo (rename n) = resolvesTo n`). -/
theorem THM_UNI_03_rename_preserves_gateway :
    allServerNames.all (fun n => resolvesTo (rename n) == resolvesTo n) = true := by decide

/-- Theorem: `rename` does not collapse the development surface into the public surface. -/
theorem THM_UNI_04_route_scope_not_collapsed :
    rename ServerName.uosDevelopment ≠ rename ServerName.uosGleamUnderscore
  ∧ (unifiedRegistrations.flatMap (fun r => r.slots.map (fun s => (s.route, s.enabled))))
      = (asIsRegistrations.flatMap (fun r => r.slots.map (fun s => (s.route, s.enabled)))) := by decide

/-- Theorem: After unification, all 14 server slots across all 12 targets use only
    `uos-harness` (12 public slots) and `uos-harness-dev` (2 gated dev slots), with
    zero legacy/unowned names and 100% auditability preserved. -/
theorem THM_UNI_05_unified_surface_converged :
    distinctNames unifiedRegistrations = [ServerName.uosHarness, ServerName.uosHarnessDev]
  ∧ unownedSlotsBefore unifiedRegistrations = 0
  ∧ ((unifiedRegistrations.flatMap (fun r => r.slots)).filter (fun s => !isCanonicalName s.name)).length = 0
  ∧ (catalogTargets unifiedRegistrations).all (fun r => r.auditState == AuditState.observed) = true := by decide

/-! ### 3.1 Release / Re-Pin Lifecycle Invariant -/

inductive ReleaseStep where
  | stage | rebind | verify | repinClients | restartServices
  deriving DecidableEq, Repr

def releaseFlow : List ReleaseStep :=
  [ ReleaseStep.stage
  , ReleaseStep.rebind
  , ReleaseStep.verify
  , ReleaseStep.repinClients
  , ReleaseStep.restartServices ]

def stepIndex : ReleaseStep → Nat
  | ReleaseStep.stage           => 0
  | ReleaseStep.rebind          => 1
  | ReleaseStep.verify          => 2
  | ReleaseStep.repinClients    => 3
  | ReleaseStep.restartServices => 4

theorem THM_GAP_01_repin_between_verify_and_restart :
    stepIndex ReleaseStep.verify < stepIndex ReleaseStep.repinClients
  ∧ stepIndex ReleaseStep.repinClients < stepIndex ReleaseStep.restartServices
  ∧ releaseFlow.length = 5 := by decide

/-! ## 4. RUNTIME VERIFICATION MODEL -/

structure UnifiedGatewayObservation where
  observedUtc             : String
  pointerMatchesCapsule   : Bool
  writerAllowlistOk       : Bool
  allTwelveConfigsAligned : Bool
  legacyNamesFound        : Nat
  auditCatalogObserved    : Nat
  auditDistinctBindings   : Nat
  gatewayHandshakeOk      : Bool
  publicTools             : Nat
  readFileSourceOk        : Bool
  readFileSecretRefused   : Bool
  deriving DecidableEq, Repr

structure GatewayExpectation where
  expectedCatalogTargets : Nat
  expectedBindings       : Nat
  minPublicTools         : Nat
  deriving DecidableEq, Repr

def canonicalExpectation : GatewayExpectation :=
  { expectedCatalogTargets := 12
  , expectedBindings       := 1
  , minPublicTools         := 50 }

/-- Fail-closed conjunction over all ontology, structure, ownership, pin-audit,
    and live JSON-RPC runtime invariants. -/
def gatewayAligned (e : GatewayExpectation) (o : UnifiedGatewayObservation) : Bool :=
  o.pointerMatchesCapsule
  && o.writerAllowlistOk
  && o.allTwelveConfigsAligned
  && (o.legacyNamesFound == 0)
  && (o.auditCatalogObserved == e.expectedCatalogTargets)
  && (o.auditDistinctBindings == e.expectedBindings)
  && o.gatewayHandshakeOk
  && (o.publicTools ≥ e.minPublicTools)
  && o.readFileSourceOk
  && o.readFileSecretRefused

/-- The reading a FULLY ALIGNED gateway would produce -- a synthetic ideal,
    not a reading anyone took.

    It replaces `observationNow`, which carried `observedUtc :=
    "2026-11-05T21:05:00Z"` and `publicTools := 59`, with a theorem
    `THM_RUN_01_aligned_now` proving the gateway healthy from it `by decide`.
    A hardcoded constant cannot go stale in the kernel.s eyes, so that proof
    would have stayed green through any outage. The companion file
    `UosMcpNameOwnershipTwin.lean` carried the same shape and its subject went
    false at 2026-11-05T22:20Z while the theorem stayed green.

    The claim about the present is now made by
    `formal/mojo/mcp_gateway_oracle.mojo`, at the moment of asking. -/
def idealReading : UnifiedGatewayObservation :=
  { observedUtc             := "<synthetic: no observation recorded in the proof plane>"
  , pointerMatchesCapsule   := true
  , writerAllowlistOk       := true
  , allTwelveConfigsAligned := true
  , legacyNamesFound        := 0
  , auditCatalogObserved    := 12
  , auditDistinctBindings   := 1
  , gatewayHandshakeOk      := true
  , publicTools             := 59
  , readFileSourceOk        := true
  , readFileSecretRefused   := true }

theorem THM_RUN_01_ideal_reading_aligns :
    gatewayAligned canonicalExpectation idealReading = true := by decide

theorem THM_RUN_02_legacy_name_forces_divergence :
    gatewayAligned canonicalExpectation
      { idealReading with legacyNamesFound := 1 } = false := by decide

theorem THM_RUN_03_pin_drift_forces_divergence :
    gatewayAligned canonicalExpectation
      { idealReading with auditDistinctBindings := 2 } = false := by decide

theorem THM_RUN_04_secret_leak_forces_divergence :
    gatewayAligned canonicalExpectation
      { idealReading with readFileSecretRefused := false } = false := by decide

theorem THM_RUN_05_fail_closed_on_no_evidence :
    gatewayAligned canonicalExpectation
      { idealReading with
        pointerMatchesCapsule   := false
      , writerAllowlistOk       := false
      , allTwelveConfigsAligned := false
      , legacyNamesFound        := 4
      , auditCatalogObserved    := 0
      , auditDistinctBindings   := 0
      , gatewayHandshakeOk      := false
      , publicTools             := 0 } = false := by decide

/-! ## 5. RUNTIME CLAIMS, UNIVERSALLY QUANTIFIED

    THM_RUN_01..05 bind `gatewayAligned` to the synthetic `idealReading`. The
    arms below are stated for EVERY observation, so no system change can
    outlive them. -/

/-- A pointer that does not match its capsule forces divergence, whatever
    else holds. This is the release-integrity arm. -/
theorem THM_RUN_06_pointer_mismatch_forces_divergence
    (o : UnifiedGatewayObservation) (h : o.pointerMatchesCapsule = false) :
    gatewayAligned canonicalExpectation o = false := by
  simp [gatewayAligned, h]

/-- Any legacy name at all forces divergence. Stated over every count, so it
    holds for the 2 underscore names the companion twin tracks and for any
    number a future config might introduce. -/
theorem THM_RUN_07_any_legacy_name_forces_divergence
    (o : UnifiedGatewayObservation) (h : o.legacyNamesFound ≠ 0) :
    gatewayAligned canonicalExpectation o = false := by
  simp [gatewayAligned, h]

/-- A refused secret read is mandatory, not incidental: if the gateway ever
    serves `var/harness/mcp-transport-secrets.env`, the twin diverges. -/
theorem THM_RUN_08_secret_must_stay_refused
    (o : UnifiedGatewayObservation) (h : o.readFileSecretRefused = false) :
    gatewayAligned canonicalExpectation o = false := by
  simp [gatewayAligned, h]

/-- A failed handshake forces divergence: a declared route is not a connected
    route (`SC-HARNESS-MCP-001`). -/
theorem THM_RUN_09_failed_handshake_forces_divergence
    (o : UnifiedGatewayObservation) (h : o.gatewayHandshakeOk = false) :
    gatewayAligned canonicalExpectation o = false := by
  simp [gatewayAligned, h]

/-- Alignment is decidable for every expectation and observation, which is
    what lets the Mojo oracle evaluate the identical relation concretely. -/
theorem THM_RUN_10_alignment_decidable
    (e : GatewayExpectation) (o : UnifiedGatewayObservation) :
    gatewayAligned e o = true ∨ gatewayAligned e o = false := by
  cases gatewayAligned e o <;> simp

/-! ## 6. OBSERVATION PLANE — deliberately absent

    The live JSON-RPC prober that stood here until `20261106-0108` has moved
    to `formal/mojo/mcp_gateway_oracle.mojo`. The two planes are run together
    by `tools/lean_mojo_differential.ml`, which fails closed when they
    disagree.

    This file has no `def main`. A `lean` exit code from it means the algebra
    is consistent; it is not an observation of the gateway. -/

end UOS.McpGatewayTwin
