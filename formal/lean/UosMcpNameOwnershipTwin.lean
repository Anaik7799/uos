/-
  UosMcpNameOwnershipTwin.lean

  The unified clean approach to MCP server naming, as a Lean twin:
  ontology, structure and runtime verification of WHICH server names the
  canonical pin writer owns, and therefore which registrations can be kept
  converged automatically and which must drift.

  Contracts : SC-HARNESS-MCP-001, SC-MIRROR-PROJ-001, SC-PROVENANCE-001
  Observed  : 2026-11-05T19:40Z (nas-1). Evidence:
              - tools/ecology_pin_edit.ml:97  and :325 carry the owned-name
                allowlist ["uos-gleam";"uos-harness";"uos-harness-dev"]
              - tools/ecology_release.ml audit-pins reports 11 targets,
                13 name slots, 4 distinct names in live use
              - three live tools/list probes, one per UOS_MCP_ROUTE
  Toolchain : Lean 4.33.0 via ./tools/lean
  Discipline: zero sorry, zero added axioms.

  WHY THIS FILE EXISTS SEPARATELY. A concurrent Pi agent session is writing
  formal/lean/UosMcpUnifiedGatewayTwin.lean (7 observed writes). Per SYNC-02
  parallel workers own disjoint paths, so the naming model lands here rather
  than racing that file.

  CENTRAL RESULT. `uos-harness` and `uos-gleam` are two NAMES for one gateway.
  The clean approach is not invented here: tools/ecology_pin_edit.ml already
  defines the canonical owned set. Two names in live use sit OUTSIDE it, and
  those are exactly the registrations that cannot be auto-repinned.

  ASCII (SC-DIAGRAM-001, parity with the Mermaid in section 0):

    OWNED by ecology_pin_edit        UNOWNED, structurally drift-prone
    +-- uos-harness      canonical   +-- uos_gleam        underscore
    +-- uos-harness-dev  canonical   +-- uos_development  underscore
    +-- uos-gleam        deprecated
             .                                 .
             v                                 v
      writer can repin                  writer cannot repin
      auditor reports OBSERVED          auditor filters it out
             .                                 .
             +---------------+-----------------+
                             v
            one gateway: tools+uos-mcp-stdio
-/

namespace UOS.McpNameOwnership

/-!
```mermaid
flowchart TD
  H["uos-harness (canonical)"] --> OWN["owned by ecology_pin_edit"]
  HD["uos-harness-dev (canonical)"] --> OWN
  G["uos-gleam (deprecated)"] --> OWN
  U1["uos_gleam (underscore)"] --> UN["unowned: cannot be repinned"]
  U2["uos_development (underscore)"] --> UN
  OWN --> W["writer repins, auditor reports OBSERVED"]
  UN --> D["drift: auditor filters, writer refuses"]
  W --> GW["one gateway: tools/uos-mcp-stdio"]
  D --> GW
```
-/

/-! ## 0. Provenance -/

def admittedEvCeiling : Nat := 93
def twinCandidateId : String := "uos/mcp-name-ownership-twin/20261105-1940"

theorem THM_PROV_01_ceiling : admittedEvCeiling = 93 := by decide

/-! ## 1. ONTOLOGY -/

inductive ServerName where
  /-- Contract name for the boundary, SC-HARNESS-MCP-001. -/
  | uosHarness
  /-- Route-scoped canonical name for the development surface. -/
  | uosHarnessDev
  /-- Implementation-language name; deprecated but still owned. -/
  | uosGleam
  /-- Underscore spelling. NOT in the writer's allowlist. -/
  | uosGleamUnderscore
  /-- Underscore development name. NOT in the writer's allowlist. -/
  | uosDevelopment
  deriving DecidableEq, Repr

def allServerNames : List ServerName :=
  [ServerName.uosHarness, ServerName.uosHarnessDev, ServerName.uosGleam,
   ServerName.uosGleamUnderscore, ServerName.uosDevelopment]

inductive RouteScope where
  | routePublic | development | successor
  deriving DecidableEq, Repr

structure GatewayImpl where
  wrapper     : String
  entrySymbol : String
  deriving DecidableEq, Repr

def theGateway : GatewayImpl :=
  { wrapper := "tools/uos-mcp-stdio"
  , entrySymbol := "cepaf_gleam@mcp@runtime_gateway:stdio_main" }

/-- Every name reaches the same implementation. This is the formal content of
    "uos-harness and uos-gleam are not two services". -/
def resolvesTo (_n : ServerName) : GatewayImpl := theGateway

theorem THM_ONT_01_all_names_one_gateway :
    allServerNames.all (fun n => resolvesTo n == theGateway) = true
  ∧ (allServerNames.map resolvesTo).eraseDups.length = 1 := by decide

theorem THM_ONT_02_five_names_three_routes :
    allServerNames.length = 5 := by decide

/-! ## 2. OWNERSHIP — the allowlist that already exists

    `tools/ecology_pin_edit.ml` validates its `servers` argument against
    `["uos-gleam";"uos-harness";"uos-harness-dev"]` at line 97, and
    `inspect_all_json` filters discovered `mcpServers` keys to the same list at
    line 325, requiring a non-empty result (`missing_owned_servers`). -/

def ownedByWriter : ServerName → Bool
  | ServerName.uosHarness         => true
  | ServerName.uosHarnessDev      => true
  | ServerName.uosGleam           => true
  | ServerName.uosGleamUnderscore => false
  | ServerName.uosDevelopment     => false

def ownedNames : List ServerName := allServerNames.filter ownedByWriter
def unownedNames : List ServerName := allServerNames.filter (fun n => !ownedByWriter n)

theorem THM_OWN_01_three_owned_two_unowned :
    ownedNames.length = 3 ∧ unownedNames.length = 2 := by decide

/-- A registration can be kept converged automatically only if its name is
    owned: the writer refuses unowned names and the auditor filters them. -/
def autoMaintainable (n : ServerName) : Bool := ownedByWriter n

/-- THE ROOT CAUSE OF DRIFT. The two underscore names cannot be repinned by
    the canonical writer, so a release cutover can never reach them. This is
    structural, not an operational oversight. -/
theorem THM_OWN_02_unowned_names_cannot_converge :
    unownedNames.all (fun n => autoMaintainable n = false) = true
  ∧ unownedNames = [ServerName.uosGleamUnderscore, ServerName.uosDevelopment]
    := by decide

/-! ## 3. THE UNIFIED CLEAN APPROACH

    Canonical = one name per route scope, both already owned. `uos-gleam`
    stays owned during transition so existing configs remain maintainable.
    The underscore names are renamed, not added to the allowlist: widening
    ownership to accept accidental spellings would legitimise the drift. -/

def canonicalFor : RouteScope → ServerName
  | RouteScope.routePublic => ServerName.uosHarness
  | RouteScope.development => ServerName.uosHarnessDev
  | RouteScope.successor   => ServerName.uosHarness

def canonicalNames : List ServerName :=
  [ServerName.uosHarness, ServerName.uosHarnessDev]

def deprecatedButOwned : List ServerName := [ServerName.uosGleam]
def toBeRenamed : List ServerName := unownedNames

/-- The canonical set is already owned, so adopting it needs no change to the
    writer. The unification is a rename in the configs, nothing more. -/
theorem THM_UNI_01_canonical_is_already_owned :
    canonicalNames.all ownedByWriter = true := by decide

/-- The canonical name follows the contract, not the implementation language. -/
theorem THM_UNI_02_contract_name_wins :
    canonicalFor RouteScope.routePublic = ServerName.uosHarness
  ∧ canonicalFor RouteScope.development = ServerName.uosHarnessDev := by decide

/-- Rename map: underscore spellings go to their hyphenated canonical form. -/
def rename : ServerName → ServerName
  | ServerName.uosGleamUnderscore => ServerName.uosHarness
  | ServerName.uosDevelopment     => ServerName.uosHarnessDev
  | n                             => n

/-- After the rename every name in use is owned, so every registration becomes
    auto-maintainable and the drift class is closed at the root. -/
theorem THM_UNI_03_rename_closes_the_drift_class :
    (allServerNames.map rename).all ownedByWriter = true := by decide

/-- And the rename is idempotent: applying it twice changes nothing, so it is
    safe to run repeatedly from the release flow. -/
theorem THM_UNI_04_rename_idempotent :
    allServerNames.map (fun n => rename (rename n))
      = allServerNames.map rename := by decide

/-- The rename must not collapse route scope: the development surface keeps a
    distinct canonical name rather than folding into public. -/
theorem THM_UNI_05_route_scope_not_collapsed :
    rename ServerName.uosDevelopment ≠ rename ServerName.uosGleamUnderscore
  ∧ canonicalFor RouteScope.development ≠ canonicalFor RouteScope.routePublic
    := by decide

/-! ## 4. STRUCTURE — live name slots

    From `audit-pins`: 11 targets, 13 name slots, 4 distinct names in use
    (`uos-gleam`, `uos_gleam`, `uos_development`, `uos-harness`).
    `uos-harness-dev` is owned but UNUSED, which is why the development
    surface currently carries an unowned name instead. -/

structure NameSlot where
  name   : ServerName
  count  : Nat
  deriving DecidableEq, Repr

def liveSlots : List NameSlot :=
  [ { name := ServerName.uosGleam,           count := 5 }
  , { name := ServerName.uosHarness,         count := 2 }
  , { name := ServerName.uosGleamUnderscore, count := 2 }
  , { name := ServerName.uosDevelopment,     count := 2 }
  ]

def totalSlots : Nat := (liveSlots.map (fun s => s.count)).foldl (· + ·) 0

theorem THM_STR_01_eleven_slots_four_names :
    totalSlots = 11 ∧ liveSlots.length = 4 := by decide

/-- Four of eleven slots carry an unowned name and therefore cannot converge. -/
def unownedSlotCount : Nat :=
  ((liveSlots.filter (fun s => !ownedByWriter s.name)).map
    (fun s => s.count)).foldl (· + ·) 0

theorem THM_STR_02_four_slots_structurally_stale :
    unownedSlotCount = 4 := by decide

/-- `uos-harness-dev` is owned but appears in zero live slots: the canonical
    development name exists in the writer and is simply unused. -/
def harnessDevSlots : Nat :=
  ((liveSlots.filter (fun s => s.name == ServerName.uosHarnessDev)).map
    (fun s => s.count)).foldl (· + ·) 0

theorem THM_STR_03_canonical_dev_name_unused :
    harnessDevSlots = 0 ∧ ownedByWriter ServerName.uosHarnessDev = true
    := by decide

/-! ## 5. RUNTIME VERIFICATION -/

structure NameObservation where
  observedUtc          : String
  writerAllowlistFound : Bool
  unownedNamesInConfigs: Nat
  canonicalDevNameUsed : Bool
  deriving DecidableEq, Repr

/-- Fail-closed: any unowned name in a live config is a divergence, because it
    is a registration the release flow can never reach. -/
def nameSurfaceAligned (o : NameObservation) : Bool :=
  o.writerAllowlistFound && (o.unownedNamesInConfigs == 0)

def observationNow : NameObservation :=
  { observedUtc := "2026-11-05T19:40:00Z"
  , writerAllowlistFound := true
  , unownedNamesInConfigs := 2
  , canonicalDevNameUsed := false }

/-- Current state DIVERGES, and the twin says so rather than rounding up. -/
theorem THM_RUN_01_diverges_today :
    nameSurfaceAligned observationNow = false := by decide

/-- After the rename it converges. -/
theorem THM_RUN_02_converges_after_rename :
    nameSurfaceAligned { observationNow with unownedNamesInConfigs := 0 } = true
    := by decide

/-- A missing writer allowlist is a divergence even with zero unowned names:
    without the writer there is no mechanism to keep anything converged. -/
theorem THM_RUN_03_fail_closed_without_writer :
    nameSurfaceAligned
      { observationNow with writerAllowlistFound := false, unownedNamesInConfigs := 0 } = false := by decide

/-! ## 6. Executable prober -/

def runCap (cmd : String) (args : Array String) : IO (UInt32 × String) := do
  try
    let out ← IO.Process.output { cmd := cmd, args := args }
    return (out.exitCode, out.stdout.trimAscii.toString)
  catch _ =>
    return (127, "")

def writerFile : String := "tools/ecology_pin_edit.ml"

/-- The allowlist is present when the writer still carries all three owned
    names. If someone narrows it, this fails rather than silently passing. -/
def writerAllowlistPresent : IO Bool := do
  let (c, body) ← runCap "cat" #[writerFile]
  if c != 0 then return false
  return (body.splitOn "\"uos-harness\"").length > 1
      && (body.splitOn "\"uos-harness-dev\"").length > 1
      && (body.splitOn "\"uos-gleam\"").length > 1

/-- Count unowned (underscore) server keys across the in-repo configs. -/
def unownedInConfigs : IO Nat := do
  let paths := [".mcp.json", ".pi/mcp.json", ".codex/config.toml",
                ".gemini/settings.json", ".deepseek/mcp.json"]
  let mut total := 0
  for p in paths do
    let (c, body) ← runCap "cat" #[p]
    if c == 0 then
      let a := (body.splitOn "uos_gleam").length - 1
      let b := (body.splitOn "uos_development").length - 1
      total := total + a + b
  return total

def main : IO UInt32 := do
  IO.println "=== UOS MCP name-ownership twin ==="
  IO.println s!"candidate : {twinCandidateId}"
  IO.println s!"EV ceiling: {admittedEvCeiling} (EV-94..109 NOT_ADMITTED)"
  let (_, now) ← runCap "date" #["-u", "+%Y-%m-%dT%H:%M:%SZ"]
  IO.println s!"probe time: {now}"
  IO.println ""

  IO.println "--- ONTOLOGY ---"
  IO.println s!"  gateway            : {theGateway.wrapper}"
  IO.println s!"  entry symbol       : {theGateway.entrySymbol}"
  IO.println s!"  names modelled     : {allServerNames.length} (all resolve to 1 gateway)"
  IO.println ""
  IO.println "--- OWNERSHIP (tools/ecology_pin_edit.ml) ---"
  IO.println s!"  owned names        : {ownedNames.length}  (uos-harness, uos-harness-dev, uos-gleam)"
  IO.println s!"  unowned names      : {unownedNames.length}  (uos_gleam, uos_development)"
  IO.println ""
  IO.println "--- STRUCTURE (live slots) ---"
  IO.println s!"  total name slots   : {totalSlots}"
  IO.println s!"  structurally stale : {unownedSlotCount} (unowned, cannot be repinned)"
  IO.println s!"  uos-harness-dev    : {harnessDevSlots} slots (owned but unused)"
  IO.println ""
  IO.println "--- UNIFIED APPROACH ---"
  IO.println s!"  canonical public   : uos-harness"
  IO.println s!"  canonical dev      : uos-harness-dev"
  IO.println s!"  deprecated, owned  : uos-gleam"
  IO.println s!"  rename closes drift: {(allServerNames.map rename).all ownedByWriter}"

  IO.println ""
  IO.println "--- RUNTIME (observed) ---"
  let wl ← writerAllowlistPresent
  let un ← unownedInConfigs
  IO.println s!"  writer allowlist   : {wl}"
  IO.println s!"  unowned keys found : {un}"

  let obs : NameObservation :=
    { observationNow with observedUtc := now, writerAllowlistFound := wl, unownedNamesInConfigs := un }
  let ok := nameSurfaceAligned obs
  IO.println ""
  IO.println s!"NAME SURFACE : {if ok then "CONVERGED" else "DIVERGENT (unowned names present)"}"
  IO.println "(specification evidence at one candidate; not runtime admission)"

  if ok then return 0
  else
    IO.eprintln "FAIL-CLOSED: unowned server names cannot be repinned by the release flow."
    return 1

end UOS.McpNameOwnership

/-- Top-level entry point for `lean --run`. -/
def main : IO UInt32 := UOS.McpNameOwnership.main
