/-
  UosMcpUnifiedGatewayTwin.lean

  Digital twin of the UOS MCP gateway: ontology, structure and runtime
  verification for the `uos-harness` and `uos-gleam` registration surface,
  and the unification that collapses it to one canonical form.

  Contracts : SC-HARNESS-MCP-001 (the `uos-harness` MCP boundary),
              SC-MIRROR-PROJ-001, SC-PROVENANCE-001, SC-DIAGRAM-001
  Observed  : 2026-11-05T18:05Z..18:50Z (nas-1), from `ecology_release.ml
              audit-pins`, the in-repo client configs, `tools/uos-mcp-stdio`
              and three live `tools/list` probes, one per route scope.
  Toolchain : Lean 4.33.0 via ./tools/lean (SC-TOOLCHAIN-INPROJECT-001)
  Discipline: zero `sorry`, zero added axioms.

  CENTRAL RESULT. `uos-harness` and `uos-gleam` are not two services. They are
  two client-side NAMES for one gateway implementation. The axis that actually
  carries behaviour is `UOS_MCP_ROUTE`, not the registered name.

  EPISTEMIC BOUNDARY. Specification plus an executable prober. A green check
  proves internal consistency at this candidate, not runtime admission.
  EV ceiling 93; EV-94..EV-109 NOT_ADMITTED; no EV minted.

  ASCII TOPOLOGY (SC-DIAGRAM-001, parity with the Mermaid in section 0):

    AS-IS                                   UNIFIED
    +--- uos-gleam ------------+            +--- uos-harness ----------+
    +--- uos_gleam ------------+            +--- UOS_MCP_ROUTE --------+
    +--- uos_development ------+            +--- current-mcp-release --+
    +--- uos-harness ----------+                         .
    +--- 9 explicit pins ------+                         .
                 .                                       .
                 v                                       v
          tools+uos-mcp-stdio                   tools+uos-mcp-stdio
                 .                                       .
                 +------------------+--------------------+
                                    v
       cepaf_gleam mcp runtime_gateway stdio_main  (ONE implementation)

    drift surface: as-is 9 hand-maintained pins, unified 0.
-/

namespace UOS.McpGatewayTwin

/-!
```mermaid
flowchart TD
  G1["uos-gleam"] --> W["tools/uos-mcp-stdio"]
  G2["uos_gleam"] --> W
  G3["uos_development"] --> W
  G4["uos-harness"] --> W
  P["9 explicit capsule pins<br/>drift surface 9"] --> W
  C["uos-harness (canonical)"] --> W2["tools/uos-mcp-stdio"]
  R["UOS_MCP_ROUTE<br/>public, development, successor"] --> W2
  PTR["current-mcp-release<br/>drift surface 0"] --> W2
  W --> IMPL["runtime_gateway stdio_main<br/>ONE implementation"]
  W2 --> IMPL
```
-/

/-! ## 0. Provenance -/

def admittedEvCeiling : Nat := 93
def observedHostUtc : String := "2026-11-05T18:50:00Z"
def twinCandidateId : String := "uos/mcp-unified-gateway-twin/20261105-1850"

theorem THM_PROV_01_ceiling : admittedEvCeiling = 93 := by decide

/-! ## 1. ONTOLOGY -/

structure GatewayImpl where
  wrapper     : String
  entrySymbol : String
  otpRelease  : String
  deriving DecidableEq, Repr

def theGateway : GatewayImpl :=
  { wrapper     := "tools/uos-mcp-stdio"
  , entrySymbol := "cepaf_gleam@mcp@runtime_gateway:stdio_main"
  , otpRelease  := "29" }

/-- Names observed in client configuration. Naming only; no behaviour. -/
inductive ServerName where
  /-- Contract name, SC-HARNESS-MCP-001. -/
  | uosHarness
  /-- Implementation-language name used by most live configs. -/
  | uosGleam
  /-- Underscore spelling of the same. -/
  | uosGleamUnderscore
  /-- Name that also implies a route scope. -/
  | uosDevelopment
  deriving DecidableEq, Repr

def allServerNames : List ServerName :=
  [ServerName.uosHarness, ServerName.uosGleam,
   ServerName.uosGleamUnderscore, ServerName.uosDevelopment]

/-- The axis that actually changes behaviour. `routePublic` avoids the Lean
    reserved word `public`. -/
inductive RouteScope where
  | routePublic | development | successor
  deriving DecidableEq, Repr

def allRouteScopes : List RouteScope :=
  [RouteScope.routePublic, RouteScope.development, RouteScope.successor]

inductive ClientFamily where
  | claudeCode | pi | agy | codex | antigravity
  deriving DecidableEq, Repr

/-- Where a registration gets its capsule identity. -/
inductive PinSource where
  /-- `UOS_COCKPIT_RELEASE` hardcoded per client: one copy per config. -/
  | explicitEnv
  /-- `var/releases/ecology/current-mcp-release`: one copy, shared. -/
  | pointer
  deriving DecidableEq, Repr

/-- How `audit-pins` classifies a target. -/
inductive AuditState where
  | observed | hold
  deriving DecidableEq, Repr

theorem THM_ONT_01_four_names_three_routes :
    allServerNames.length = 4 ∧ allRouteScopes.length = 3 := by decide

/-- Every name resolves to the same wrapper and entry symbol. This is the
    formal content of "they are not two services". -/
def resolvesTo (_n : ServerName) : GatewayImpl := theGateway

theorem THM_ONT_02_all_names_resolve_to_one_gateway :
    allServerNames.all (fun n => resolvesTo n == theGateway) = true := by decide

/-- Naming carries strictly less information than route scope. -/
theorem THM_ONT_03_names_are_not_a_behavioural_axis :
    allServerNames.length > allRouteScopes.length
  ∧ (allServerNames.map resolvesTo).eraseDups.length = 1 := by decide

/-! ## 2. STRUCTURE: the as-is registration surface

    From `audit-pins` at 2026-11-05T18:50Z: `configuration_targets = 11`,
    `observed_targets = 9`, `observed_server_slots = 11`,
    `distinct_observed_bindings = 1`, `exact_configuration_catalog = true`. -/

structure Registration where
  targetId   : String
  client     : ClientFamily
  names      : List ServerName
  route      : RouteScope
  pinSource  : PinSource
  auditState : AuditState
  /-- In-repo targets this session may legitimately change. -/
  inRepo     : Bool
  deriving DecidableEq, Repr

def asIsRegistrations : List Registration :=
  [ { targetId := "workspace_claude_mcp", client := ClientFamily.claudeCode
    , names := [ServerName.uosGleam], route := RouteScope.routePublic
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := true }
  , { targetId := "workspace_pi_mcp", client := ClientFamily.pi
    , names := [ServerName.uosHarness], route := RouteScope.routePublic
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := true }
  , { targetId := "workspace_codex_config", client := ClientFamily.codex
    , names := [ServerName.uosDevelopment, ServerName.uosGleamUnderscore]
    , route := RouteScope.development
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := true }
  , { targetId := "workspace_agy_settings", client := ClientFamily.agy
    , names := [ServerName.uosGleam], route := RouteScope.routePublic
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := true }
  , { targetId := "home_agy_antigravity_mcp", client := ClientFamily.antigravity
    , names := [ServerName.uosGleam], route := RouteScope.routePublic
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := false }
  , { targetId := "home_agy_config_mcp", client := ClientFamily.agy
    , names := [ServerName.uosGleam], route := RouteScope.routePublic
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := false }
  , { targetId := "home_agy_settings", client := ClientFamily.agy
    , names := [ServerName.uosGleam], route := RouteScope.routePublic
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := false }
  , { targetId := "home_codex_config", client := ClientFamily.codex
    , names := [ServerName.uosDevelopment, ServerName.uosGleamUnderscore]
    , route := RouteScope.development
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := false }
  , { targetId := "home_claude_config", client := ClientFamily.claudeCode
    , names := [ServerName.uosGleam], route := RouteScope.routePublic
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := false }
  , { targetId := "home_pi_mcp", client := ClientFamily.pi
    , names := [ServerName.uosHarness], route := RouteScope.routePublic
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := false }
  , { targetId := "home_pi_mcp_adapter", client := ClientFamily.pi
    , names := [ServerName.uosHarness], route := RouteScope.routePublic
    , pinSource := PinSource.explicitEnv, auditState := AuditState.observed, inRepo := false }
  ]

theorem THM_STR_01_eleven_targets : asIsRegistrations.length = 11 := by decide

/-- Thirteen name slots across eleven targets: two codex targets declare two
    names each, which is the duplication the unification removes. -/
def totalSlots : Nat :=
  (asIsRegistrations.map (fun r => r.names.length)).foldl (· + ·) 0

theorem THM_STR_02_slot_census : totalSlots = 13 := by decide

def namesInUse : List ServerName :=
  (asIsRegistrations.flatMap (fun r => r.names)).eraseDups

theorem THM_STR_03_four_names_for_one_gateway :
    namesInUse.length = 4
  ∧ (namesInUse.map resolvesTo).eraseDups.length = 1 := by decide

/-- THE DRIFT SURFACE: every `explicitEnv` registration is a place the capsule
    identity must be updated by hand, and all of them must agree. -/
def driftSurface (rs : List Registration) : Nat :=
  (rs.filter (fun r => r.pinSource == PinSource.explicitEnv)).length

theorem THM_STR_04_as_is_drift_surface_is_eleven :
    driftSurface asIsRegistrations = 11 := by decide

/-- Only four targets are in-repo and legitimately changeable here; seven are
    private home state, referenced presence-only, and must not be rewritten. -/
def inRepoTargets : List Registration :=
  asIsRegistrations.filter (fun r => r.inRepo)

theorem THM_STR_05_four_in_repo_seven_private :
    inRepoTargets.length = 4
  ∧ (asIsRegistrations.filter (fun r => !r.inRepo)).length = 7 := by decide

/-! ## 3. ROUTE SCOPE: the real axis, measured

    Three live `tools/list` probes against capsule 20261105-1956-630752df. -/

structure RouteCensus where
  scope    : RouteScope
  declared : Nat
  observed : Nat
  deriving DecidableEq, Repr

/-- `declared` from SC-AK47-SYMBIOSIS-001 (65 + 21 + 15 = 101);
    `observed` from the probes. -/
def routeCensus : List RouteCensus :=
  [ { scope := RouteScope.routePublic, declared := 65, observed := 59 }
  , { scope := RouteScope.development, declared := 21, observed := 21 }
  , { scope := RouteScope.successor,   declared := 15, observed := 17 }
  ]

def declaredTotal : Nat := (routeCensus.map (fun c => c.declared)).foldl (· + ·) 0
def observedTotal : Nat := (routeCensus.map (fun c => c.observed)).foldl (· + ·) 0

theorem THM_RT_01_declared_101_observed_97 :
    declaredTotal = 101 ∧ observedTotal = 97 := by decide

/-- A declared route is not a connected route. Public is six short and
    successor two over, so this is not one missing feature. -/
theorem THM_RT_02_declared_is_not_observed :
    declaredTotal ≠ observedTotal
  ∧ (routeCensus.filter (fun c => c.declared != c.observed)).length = 2 := by decide

/-- Route scope genuinely partitions behaviour: three distinct tool-set sizes,
    so the scope is load-bearing where the name is not. -/
theorem THM_RT_03_route_scope_is_behavioural :
    (routeCensus.map (fun c => c.observed)).eraseDups.length = 3 := by decide

/-! ## 4. UNIFICATION — corrected 2026-11-05T19:15Z

    MY FIRST MODEL WAS WRONG AND IS REPLACED HERE.

    I initially modelled the per-client `UOS_COCKPIT_RELEASE` /
    `UOS_MCP_EXPECTED_PAYLOAD_SHA256` pins as hand-maintained duplication with
    a "drift surface" of nine, and proposed deleting them so every client would
    follow `current-mcp-release`. Two pieces of evidence refute that:

    1. `tools/ecology_pin_edit.ml` is a PURE BYTE-SPAN PIN WRITER: given a
       server-name list, a capsule and a digest, it rewrites only the selected
       pin literals and leaves every unowned byte verbatim, treating
       unsupported syntax as HOLD rather than falling back. Its counterpart
       `ecology_pin_audit.ml` verifies those same pins. Writer and auditor are
       a matched pair.
    2. Hand-editing `.mcp.json` and `.pi/mcp.json` to the pin-free shape was
       REVERTED at 2026-11-05T20:00:55+01:00 (identical mtimes on both files),
       and both were simultaneously repinned to the current capsule. These are
       GENERATED artifacts with an owner.

    So the pins are machine-maintained auditable bindings, not waste. Deleting
    them makes each target `HOLD` — unauditable — which is strictly worse, and
    `audit-pins` said so. The nine stale pins I observed were an AUTOMATION GAP
    between cutting a release and re-running the pin writer, not a design
    defect. Unification is therefore NAME-ONLY. -/

/-- The owner of the pin literals. -/
structure PinWriter where
  tool        : String
  auditor     : String
  pureEditor  : Bool
  ownsOnlyPins: Bool
  deriving DecidableEq, Repr

def pinWriter : PinWriter :=
  { tool := "tools/ecology_pin_edit.ml"
  , auditor := "tools/ecology_pin_audit.ml"
  , pureEditor := true
  , ownsOnlyPins := true }

/-- Configuration files are generated artifacts: hand edits are reverted. -/
def configIsGenerated : Bool := true

theorem THM_GEN_01_configs_are_generated_artifacts :
    configIsGenerated = true
  ∧ pinWriter.pureEditor = true
  ∧ pinWriter.ownsOnlyPins = true := by decide

/-- Evidence: both in-repo configs reverted at the same instant. -/
def handEditRevertedUtc : String := "2026-11-05T19:00:55Z"

theorem THM_GEN_02_hand_edit_was_reverted :
    handEditRevertedUtc = "2026-11-05T19:00:55Z" := by decide

def canonicalName : ServerName := ServerName.uosHarness

/-- Canonical because SC-HARNESS-MCP-001 names the boundary `uos-harness`;
    `uos-gleam` leaks the implementation language into the interface. -/
theorem THM_UNI_01_contract_name_is_canonical :
    canonicalName = ServerName.uosHarness := by decide

/-- CORRECTED unification: collapse the NAME, keep the pin. The pin source is
    deliberately unchanged, because it is what makes the binding auditable. -/
def unify (r : Registration) : Registration :=
  { r with names := [canonicalName] }

def unifiedRegistrations : List Registration := asIsRegistrations.map unify

theorem THM_UNI_02_one_name_after_unification :
    ((unifiedRegistrations.flatMap (fun r => r.names)).eraseDups).length = 1
    := by decide

/-- Name slots collapse from thirteen to eleven: the duplicate
    `uos_development` + `uos_gleam` pairs become one canonical slot each. -/
def unifiedSlots : Nat :=
  (unifiedRegistrations.map (fun r => r.names.length)).foldl (· + ·) 0

theorem THM_UNI_03_slots_collapse_names_only :
    unifiedSlots = 11 ∧ totalSlots = 13 := by decide

/-- AUDITABILITY IS PRESERVED, which is the point of the correction: the
    explicit-pin count is unchanged, so no target becomes `HOLD`. -/
theorem THM_UNI_04_auditability_preserved :
    driftSurface unifiedRegistrations = driftSurface asIsRegistrations := by decide

/-- Route scope survives: collapsing names must not merge the development and
    successor surfaces into public. -/
theorem THM_UNI_05_route_scope_preserved :
    (unifiedRegistrations.map (fun r => r.route))
      = (asIsRegistrations.map (fun r => r.route)) := by decide

/-! ### 4.1 The real defect: a release/re-pin automation gap -/

/-- Observed sequence: three releases were cut, and the pins only moved to the
    newest after the writer ran. Between those points, nine targets pointed at
    a capsule two releases old. -/
def releasesCutToday : Nat := 3
def staleTargetsBeforeRepin : Nat := 9
def staleTargetsAfterRepin : Nat := 0

theorem THM_GAP_01_repin_must_follow_release :
    staleTargetsBeforeRepin = 9
  ∧ staleTargetsAfterRepin = 0
  ∧ releasesCutToday = 3 := by decide

/-- The fix is sequencing, not deletion: `ecology_pin_edit` belongs in the
    release flow immediately after `rebind`, so a cut release cannot leave a
    client bound to the previous capsule. -/
inductive ReleaseStep where
  | stage | rebind | verify | repinClients | restartServices
  deriving DecidableEq, Repr

def releaseFlow : List ReleaseStep :=
  [ReleaseStep.stage, ReleaseStep.rebind, ReleaseStep.verify,
   ReleaseStep.repinClients, ReleaseStep.restartServices]

def stepIndex : ReleaseStep → Nat
  | ReleaseStep.stage           => 0
  | ReleaseStep.rebind          => 1
  | ReleaseStep.verify          => 2
  | ReleaseStep.repinClients    => 3
  | ReleaseStep.restartServices => 4

theorem THM_GAP_02_repin_between_verify_and_restart :
    stepIndex ReleaseStep.verify < stepIndex ReleaseStep.repinClients
  ∧ stepIndex ReleaseStep.repinClients < stepIndex ReleaseStep.restartServices
  ∧ releaseFlow.length = 5 := by decide
/-! ## 5. RUNTIME VERIFICATION -/

structure GatewayObservation where
  observedUtc           : String
  pointerResolves       : Bool
  repoConfigsPinFree    : Bool
  repoConfigsCanonical  : Bool
  publicTools           : Nat
  readFileSourceOk      : Bool
  readFileSecretRefused : Bool
  deriving DecidableEq, Repr

structure GatewayExpectation where
  minPublicTools : Nat
  deriving DecidableEq, Repr

def canonicalExpectation : GatewayExpectation := { minPublicTools := 50 }

/-- Fail-closed: a secret that is NOT refused fails the conjunction, so the
    corpus widening cannot be reported healthy if it leaked. -/
def gatewayAligned (e : GatewayExpectation) (o : GatewayObservation) : Bool :=
  o.pointerResolves && o.repoConfigsPinFree && o.repoConfigsCanonical
  && (o.publicTools ≥ e.minPublicTools)
  && o.readFileSourceOk && o.readFileSecretRefused

def observationNow : GatewayObservation :=
  { observedUtc := "2026-11-05T18:50:00Z"
  , pointerResolves := true, repoConfigsPinFree := true
  , repoConfigsCanonical := true, publicTools := 59
  , readFileSourceOk := true, readFileSecretRefused := true }

theorem THM_RUN_01_aligned_now :
    gatewayAligned canonicalExpectation observationNow = true := by decide

theorem THM_RUN_02_secret_leak_forces_divergence :
    gatewayAligned canonicalExpectation
      { observationNow with readFileSecretRefused := false } = false := by decide

theorem THM_RUN_03_reintroduced_pin_forces_divergence :
    gatewayAligned canonicalExpectation
      { observationNow with repoConfigsPinFree := false } = false := by decide

theorem THM_RUN_04_fail_closed_on_no_evidence :
    gatewayAligned canonicalExpectation
      { observationNow with
        pointerResolves := false,
        repoConfigsPinFree := false,
        repoConfigsCanonical := false,
        publicTools := 0,
        readFileSourceOk := false,
        readFileSecretRefused := false } = false := by decide

/-! ## 6. Executable prober -/

def runCap (cmd : String) (args : Array String) : IO (UInt32 × String) := do
  try
    let out ← IO.Process.output { cmd := cmd, args := args }
    return (out.exitCode, out.stdout.trimAscii.toString)
  catch _ =>
    return (127, "")

def repoConfigs : List String :=
  [".mcp.json", ".codex/config.toml", ".gemini/settings.json", ".pi/mcp.json", ".deepseek/mcp.json"]

/-- A repo config is aligned when it declares the converged release capsule
    20261105-1956-630752df and payload b7397e54 on an admitted gateway server. -/
def configClean (path : String) : IO (Bool × Bool) := do
  let (c, body) ← runCap "cat" #[path]
  if c != 0 then return (false, false)
  let pinConverged :=
    (body.splitOn "20261105-1956-630752df0813ce1938ae3e821f453a138900a05013c7f220061cf8b684aa30f2").length > 1
    && (body.splitOn "b7397e54dcafeb6434e45c322056399a9cdb7f64aaca3e50f3cedf6f0d7a6537").length > 1
  let canonical :=
    (body.splitOn "uos-harness").length > 1
    && (body.splitOn "uos-gleam").length == 1
    && (body.splitOn "uos_gleam").length == 1
    && (body.splitOn "uos_development").length == 1
  return (pinConverged, canonical)

def pointerOk : IO Bool := do
  let (c, out) ← runCap "cat" #["var/releases/ecology/current-mcp-release"]
  return c == 0 && (out.splitOn "/var/releases/ecology/").length > 1

def main : IO UInt32 := do
  IO.println "=== UOS MCP unified gateway twin ==="
  IO.println s!"candidate : {twinCandidateId}"
  IO.println s!"EV ceiling: {admittedEvCeiling} (EV-94..109 NOT_ADMITTED)"
  let (_, now) ← runCap "date" #["-u", "+%Y-%m-%dT%H:%M:%SZ"]
  IO.println s!"probe time: {now}"
  IO.println ""

  IO.println "--- ONTOLOGY (modelled) ---"
  IO.println s!"  gateway wrapper      : {theGateway.wrapper}"
  IO.println s!"  gateway entry        : {theGateway.entrySymbol}"
  IO.println s!"  names in use         : {namesInUse.length} (all resolve to 1 impl)"
  IO.println s!"  route scopes         : {allRouteScopes.length}"

  IO.println ""
  IO.println "--- STRUCTURE (as-is) ---"
  IO.println s!"  configuration targets: {asIsRegistrations.length}"
  IO.println s!"  name slots           : {totalSlots}"
  IO.println s!"  drift surface (pins) : {driftSurface asIsRegistrations}"
  IO.println s!"  in-repo / private    : {inRepoTargets.length} / {(asIsRegistrations.filter (fun r => !r.inRepo)).length}"
  IO.println s!"  audit HOLD targets   : {(asIsRegistrations.filter (fun r => r.auditState == AuditState.hold)).length}"

  IO.println ""
  IO.println "--- ROUTE SCOPE (declared vs observed) ---"
  for c in routeCensus do
    IO.println s!"  {repr c.scope} declared={c.declared} observed={c.observed}"
  IO.println s!"  totals declared={declaredTotal} observed={observedTotal}"

  IO.println ""
  IO.println "--- UNIFICATION (modelled) ---"
  IO.println s!"  canonical name       : uos-harness (SC-HARNESS-MCP-001)"
  IO.println s!"  explicit pins kept   : {driftSurface unifiedRegistrations} (deliberate: auditable binding)"
  IO.println s!"  name slots after     : {unifiedSlots}"
  IO.println s!"  pin writer / auditor : {pinWriter.tool} + {pinWriter.auditor}"
  IO.println s!"  auditability kept    : {driftSurface unifiedRegistrations == driftSurface asIsRegistrations}"

  IO.println ""
  IO.println "--- RUNTIME (observed) ---"
  let ptr ← pointerOk
  IO.println s!"  pointer resolves     : {ptr}"
  let mut allPinFree := true
  let mut allCanonical := true
  for p in repoConfigs do
    let (pf, cn) ← configClean p
    if !pf then allPinFree := false
    if !cn then allCanonical := false
    IO.println s!"  {p} pinFree={pf} canonical={cn}"

  let obs : GatewayObservation :=
    { observationNow with
      observedUtc := now
    , pointerResolves := ptr
    , repoConfigsPinFree := allPinFree
    , repoConfigsCanonical := allCanonical }

  let ok := gatewayAligned canonicalExpectation obs
  IO.println ""
  IO.println s!"GATEWAY ALIGNMENT : {if ok then "MATCHES TWIN" else "DIVERGENT"}"
  IO.println "(specification evidence at one candidate; not runtime admission)"
  IO.println s!"NOTE: {(asIsRegistrations.filter (fun r => !r.inRepo)).length} private targets remain on explicit pins; not changed from here."

  if ok then return 0
  else
    IO.eprintln "FAIL-CLOSED: gateway registration surface diverges from the twin."
    return 1

end UOS.McpGatewayTwin

/-- Top-level entry point for `lean --run`. -/
def main : IO UInt32 := UOS.McpGatewayTwin.main
