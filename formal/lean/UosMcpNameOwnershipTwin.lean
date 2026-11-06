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

/-! ## 2. OWNERSHIP — format-indexed, because the writer is

    `tools/ecology_pin_edit.ml` carries TWO allowlists, one per config
    dialect, and this matters:

      `let json ~servers ...` (line 97)
        `bindings ["uos-gleam";"uos-harness";"uos-harness-dev"]`
      `let toml ~servers ...` (line 261)
        `bindings ["uos-harness";"uos-harness-dev";"uos_gleam";"uos_development"]`

    and the two inspectors mirror them: `inspect_all_json` (line 325) filters
    to the JSON list, `inspect_all_toml` (line 336) to the TOML list.

    CORRECTION, `20261106-0108`. Until this revision this section modelled
    ownership as a single predicate `ownedByWriter : ServerName → Bool`
    reading only the JSON allowlist, and concluded that the two underscore
    spellings were UNOWNED — "THE ROOT CAUSE OF DRIFT", with four of eleven
    slots "structurally stale" and a rename needed to close the class.

    That was wrong. `uos_gleam` and `uos_development` are the TOML bare-key
    spellings and are owned by the TOML path. There is no unowned name. The
    error came from transcribing one allowlist into Lean by hand and then
    transcribing the same mistake into the Mojo oracle, where both agreed and
    neither observed. Sovereign review (Codex) named exactly that failure
    mode — "a shared wrong mapping can pass both languages" — and the fix was
    to make `formal/mojo/mcp_name_ownership_oracle.mojo` DERIVE both
    allowlists from the writer instead of restating them. It read 3 and 4 on
    its first run.

    Ownership is therefore a relation on (format, name), never a predicate on
    a name alone. -/

inductive ConfigFormat
  | json
  | toml
  deriving DecidableEq, Repr

def allFormats : List ConfigFormat := [ConfigFormat.json, ConfigFormat.toml]

/-- Mirrors the two `bindings [...]` lists in the writer, by format. -/
def ownedBy : ConfigFormat → ServerName → Bool
  | ConfigFormat.json, ServerName.uosHarness         => true
  | ConfigFormat.json, ServerName.uosHarnessDev      => true
  | ConfigFormat.json, ServerName.uosGleam           => true
  | ConfigFormat.json, _                             => false
  | ConfigFormat.toml, ServerName.uosHarness         => true
  | ConfigFormat.toml, ServerName.uosHarnessDev      => true
  | ConfigFormat.toml, ServerName.uosGleamUnderscore => true
  | ConfigFormat.toml, ServerName.uosDevelopment     => true
  | ConfigFormat.toml, _                             => false

def ownedIn (f : ConfigFormat) : List ServerName :=
  allServerNames.filter (ownedBy f)

/-- Owned by at least one writer path. -/
def ownedSomewhere (n : ServerName) : Bool :=
  ownedBy ConfigFormat.json n || ownedBy ConfigFormat.toml n

theorem THM_OWN_01_json_owns_three_toml_owns_four :
    (ownedIn ConfigFormat.json).length = 3
  ∧ (ownedIn ConfigFormat.toml).length = 4 := by decide

/-- THE RETRACTION. There is no unowned name: every spelling in the domain is
    owned by the writer path for its own dialect. This replaces the withdrawn
    `THM_OWN_02_unowned_names_cannot_converge`, which asserted the opposite
    from a half-read authority. -/
theorem THM_OWN_02_no_unowned_name_exists :
    allServerNames.all ownedSomewhere = true := by decide

/-- A registration is auto-maintainable when its name is owned by the path for
    its own format — not by some other format's path. -/
def autoMaintainable (f : ConfigFormat) (n : ServerName) : Bool := ownedBy f n

/-- What makes the canonical names canonical: both dialects own them, so they
    are writable in a JSON config and a TOML config alike. -/
theorem THM_OWN_03_canonical_owned_by_both_paths :
    ownedBy ConfigFormat.json ServerName.uosHarness = true
  ∧ ownedBy ConfigFormat.toml ServerName.uosHarness = true
  ∧ ownedBy ConfigFormat.json ServerName.uosHarnessDev = true
  ∧ ownedBy ConfigFormat.toml ServerName.uosHarnessDev = true := by decide

/-- The dialects genuinely differ, which is why one flat allowlist cannot
    model this: `uos-gleam` is JSON-only, `uos_gleam` is TOML-only. A model
    that cannot express this distinction will mistake a dialect for drift —
    and one did. -/
theorem THM_OWN_04_dialects_are_not_identical :
    ownedBy ConfigFormat.json ServerName.uosGleam = true
  ∧ ownedBy ConfigFormat.toml ServerName.uosGleam = false
  ∧ ownedBy ConfigFormat.toml ServerName.uosGleamUnderscore = true
  ∧ ownedBy ConfigFormat.json ServerName.uosGleamUnderscore = false := by decide

/-- A name owned by the wrong dialect is a real defect, distinct from an
    unowned name: it is a DIALECT LEAK. Stated for every format and name. -/
def dialectLeak (f : ConfigFormat) (n : ServerName) : Bool :=
  ownedSomewhere n && !ownedBy f n

theorem THM_OWN_05_dialect_leak_is_not_auto_maintainable
    (f : ConfigFormat) (n : ServerName) (h : dialectLeak f n = true) :
    autoMaintainable f n = false := by
  simp [dialectLeak, autoMaintainable] at *
  exact h.2

/-! ## 3. THE UNIFIED CLEAN APPROACH

    Canonical = one name per route scope, owned by BOTH dialects. The
    underscore spellings are not errors to be renamed away — they are the
    TOML dialect — but the canonical names are preferable precisely because
    they need no dialect-specific handling at all. -/

def canonicalFor : RouteScope → ServerName
  | RouteScope.routePublic => ServerName.uosHarness
  | RouteScope.development => ServerName.uosHarnessDev
  | RouteScope.successor   => ServerName.uosHarness

def canonicalNames : List ServerName :=
  [ServerName.uosHarness, ServerName.uosHarnessDev]

def deprecatedButOwned : List ServerName := [ServerName.uosGleam]

/-- The canonical set is owned in every format, so adopting it needs no change
    to the writer AND no dialect-specific branch anywhere. -/
theorem THM_UNI_01_canonical_is_owned_in_every_format :
    allFormats.all (fun f => canonicalNames.all (ownedBy f)) = true := by decide

/-- The canonical name follows the contract, not the implementation language. -/
theorem THM_UNI_02_contract_name_wins :
    canonicalFor RouteScope.routePublic = ServerName.uosHarness
  ∧ canonicalFor RouteScope.development = ServerName.uosHarnessDev := by decide

/-- Normalisation map: every spelling goes to its canonical, dialect-free
    form. This is a simplification, not a drift repair — the inputs were
    already owned. -/
def normalise : ServerName → ServerName
  | ServerName.uosGleamUnderscore => ServerName.uosHarness
  | ServerName.uosDevelopment     => ServerName.uosHarnessDev
  | ServerName.uosGleam           => ServerName.uosHarness
  | n                             => n

/-- After normalisation every name is owned in EVERY format, so no
    registration depends on which dialect its file happens to use. That is
    the actual gain, and it is weaker than the "closes the drift class" claim
    this theorem replaces. -/
theorem THM_UNI_03_normalisation_removes_dialect_dependence :
    allFormats.all (fun f => (allServerNames.map normalise).all (ownedBy f))
      = true := by decide

/-- Normalisation is idempotent, so it is safe to run repeatedly from the
    release flow. -/
theorem THM_UNI_04_normalise_idempotent :
    allServerNames.map (fun n => normalise (normalise n))
      = allServerNames.map normalise := by decide

/-- Normalisation must not collapse route scope: the development surface keeps
    a distinct canonical name rather than folding into public. -/
theorem THM_UNI_05_route_scope_not_collapsed :
    canonicalFor RouteScope.development ≠ canonicalFor RouteScope.routePublic
  ∧ normalise ServerName.uosDevelopment ≠ normalise ServerName.uosGleamUnderscore
    := by decide

/-- Normalisation eliminates dialect leaks for every format. -/
theorem THM_UNI_06_normalisation_eliminates_leaks :
    allFormats.all (fun f =>
      (allServerNames.map normalise).all (fun n => !dialectLeak f n)) = true
    := by decide

/-! ## 4. STRUCTURE — stated as a predicate, not a recorded census

    The previous revision carried `liveSlots`, a hardcoded census — 11 slots,
    4 names, "4 structurally stale" — and proved theorems about it. Two
    problems, both fatal to the claim: the staleness followed from the
    half-read allowlist above, and a recorded census is a frozen observation
    that the kernel re-checks forever while never re-reading the configs.
    Sovereign review flagged both. The census is gone; the live count is taken
    by the Mojo oracle.

    What stays is what a well-formed registration MEANS. -/

/-- A registration is well formed when its name is owned by the writer path
    for its own file format. Decidable, so the oracle evaluates the same
    relation against the real files. -/
def registrationWellFormed (f : ConfigFormat) (n : ServerName) : Bool :=
  ownedBy f n

theorem THM_STR_01_canonical_registration_is_well_formed_everywhere :
    allFormats.all (fun f =>
      canonicalNames.all (registrationWellFormed f)) = true := by decide

/-- A dialect leak is never well formed, in any format. -/
theorem THM_STR_02_dialect_leak_is_never_well_formed
    (f : ConfigFormat) (n : ServerName) (h : dialectLeak f n = true) :
    registrationWellFormed f n = false := by
  simp [dialectLeak, registrationWellFormed] at *
  exact h.2

/-- Well-formedness is decidable for every format and name, which is what
    lets the oracle check the live files against this exact relation. -/
theorem THM_STR_03_well_formedness_decidable
    (f : ConfigFormat) (n : ServerName) :
    registrationWellFormed f n = true ∨ registrationWellFormed f n = false := by
  cases registrationWellFormed f n <;> simp

/-! ## 5. RUNTIME DECISION FUNCTION

    NO OBSERVATION LIVES IN THIS FILE.

    Until `20261106-0108` this section carried `observationNow`, a record with
    `observedUtc := "2026-11-05T19:40:00Z"` and `unownedNamesInConfigs := 2`,
    and a theorem `THM_RUN_01_diverges_today` proving divergence `by decide`.

    The rename landed at `2026-11-05T22:20Z`. Every live client config now
    carries zero unowned names. The theorem did not notice, and could not:
    a hardcoded constant cannot go stale in the kernel's eyes, so the proof
    stayed green while its subject became false. The differential oracle
    (`formal/mojo/mcp_name_ownership_oracle.mojo`) reported CONVERGED on its
    first run against the same algebra, and that disagreement is what
    surfaced the drift.

    The boundary this file now holds: Lean proves properties of the DECISION
    FUNCTION, universally quantified over every possible observation. Those
    statements are eternally true and cannot rot. What the world actually is
    gets observed in Mojo, at the moment of asking, and never recorded here.
-/

structure NameObservation where
  observedUtc          : String
  writerAllowlistFound : Bool
  dialectLeaksInConfigs : Nat
  canonicalDevNameUsed : Bool
  deriving DecidableEq, Repr

/-- Fail-closed: any DIALECT LEAK in a live config is a divergence -- a name
    owned by some other format.s writer path, which the path for this file
    will refuse. Note what changed: the earlier formulation said "any unowned
    name", and there are no unowned names. The defect is real but it is a
    mismatch, not an absence. -/
def nameSurfaceAligned (o : NameObservation) : Bool :=
  o.writerAllowlistFound && (o.dialectLeaksInConfigs == 0)

/-- Any dialect leak at all diverges — for EVERY observation, not merely the
    one someone wrote down. This replaces `THM_RUN_01_diverges_today`. -/
theorem THM_RUN_01_any_dialect_leak_diverges
    (o : NameObservation) (h : o.dialectLeaksInConfigs ≠ 0) :
    nameSurfaceAligned o = false := by
  simp [nameSurfaceAligned, h]

/-- Convergence is exactly: the writer is present AND nothing unowned remains.
    An iff, so neither direction can be weakened without breaking the proof. -/
theorem THM_RUN_02_converges_iff_writer_and_zero_leaks (o : NameObservation) :
    nameSurfaceAligned o = true
      ↔ (o.writerAllowlistFound = true ∧ o.dialectLeaksInConfigs = 0) := by
  simp [nameSurfaceAligned]

/-- A missing writer allowlist is a divergence even with zero unowned names:
    without the writer there is no mechanism to keep anything converged. -/
theorem THM_RUN_03_fail_closed_without_writer
    (o : NameObservation) (h : o.writerAllowlistFound = false) :
    nameSurfaceAligned o = false := by
  simp [nameSurfaceAligned, h]

/-- The decision function is total and decidable, which is what makes the Mojo
    oracle able to evaluate the identical algebra concretely. -/
theorem THM_RUN_04_decidable (o : NameObservation) :
    nameSurfaceAligned o = true ∨ nameSurfaceAligned o = false := by
  cases nameSurfaceAligned o <;> simp

/-! ## 6. OBSERVATION PLANE — deliberately absent

    This file has no `def main`, no `IO.Process`, and no `IO.FS`. The prober
    that used to sit here lives at
    `formal/mojo/mcp_name_ownership_oracle.mojo`
    and is run by `tools/lean_mojo_differential.ml`.

    A `lean` exit code from this file means the algebra is consistent. It is
    not an observation of the system, and nothing in this file may be read as
    one (`THM_VAC_01_typechecking_is_not_observation`, stated in
    `UosCoreEvoUnifiedDigitalTwin.lean`).
-/

end UOS.McpNameOwnership
