/- =============================================================================
   UOS STARTUP & PER-TRANSACTION TOKEN BUDGET ACCOUNTING (LEAN 4.33.0)
   =============================================================================
   Observed 2026-11-05T10:45:02Z. Caste04 (Claude) harness context budget.

   Companion to `FiveHarnessUnifiedAndCorePolicyEquivalence.lean`, which models
   the *inline harness file* reduction only (Pi: 15,861 B -> 1,902 B). That model
   says nothing about the actual startup prompt, so its "88.0% startup prompt
   reduction" is a statement about one file, NOT about the startup budget. This
   module supplies the missing accounting and keeps the two claims separable.

   EPISTEMIC BOUNDARY (`SC-PROVENANCE-001`, DMC two-key rule):
   - `Observed`  : read from the harness token counter during the live session.
   - `Measured`  : byte counts read from the filesystem with `wc -c`.
   - `Derived`   : arithmetic over Observed/Measured values inside this module.
   - `Estimated` : byte->token conversion using a declared ratio band. NO Claude
                   tokenizer exists on this host, so every token figure that is
                   not `Observed` is `Estimated` and carries a band, never a point.
   A theorem here proves arithmetic over recorded constants. It does NOT prove
   anything about runtime behaviour, and it grants no admission.
   ============================================================================= -/

namespace UOS.TokenBudget

/-- Provenance grade of a recorded quantity. Fail-closed: `estimated` never
    upgrades to `observed` by passing through arithmetic. -/
inductive Provenance where
  | observed
  | measured
  | derived
  | estimated
  deriving DecidableEq, Repr

/-- Admitted EV cycle ceiling (`SC-PROVENANCE-001`). Unchanged by this module. -/
def admitted_ev_ceiling : Nat := 93

/- ---------------------------------------------------------------------------
   1. MEASURED ALWAYS-ON COMPONENTS (bytes, `wc -c`)
   --------------------------------------------------------------------------- -/

/-- One always-on context component and its byte size. -/
structure Component where
  name        : String
  bytes       : Nat
  provenance  : Provenance
  deriving DecidableEq, Repr

/-- Session-start state, 2026-11-05 before any compaction pass. -/
def uosClaudeMd_before      : Component := { name := "uos/CLAUDE.md (symlink -> AGENTS.md)", bytes := 34939, provenance := .measured }
def uosRules_before         : Component := { name := "uos/.claude/rules (79 files)",          bytes := 584422, provenance := .measured }
def parentRules_before      : Component := { name := "NAS-setup/.claude/rules (7 files)",     bytes := 19521, provenance := .measured }
def parentClaudeMd          : Component := { name := "NAS-setup/CLAUDE.md (stale EV-99/EV-108 claims)", bytes := 18745, provenance := .measured }

/-- State after the four 2026-11-05 passes. `parentClaudeMd_after` replaced the
    stale root policy with a pointer; the three names `CLAUDE.md`, `AGENTS.md`
    and `.agents/AGENTS.md` at that root resolve to this one physical file. -/
def parentClaudeMd_after    : Component := { name := "NAS-setup/CLAUDE.md (pointer)",         bytes := 3018, provenance := .measured }
def uosClaudeMd_after       : Component := { name := "uos/CLAUDE.md (Lean-generated Caste04 profile)", bytes := 8146, provenance := .measured }
def uosRules_after          : Component := { name := "uos/.claude/rules (77 generated pointers + 24 refused bodies)", bytes := 224880, provenance := .measured }
def parentRules_after       : Component := { name := "NAS-setup/.claude/rules (1 pointer)",     bytes := 1160, provenance := .measured }

/-- Non-policy always-on components that are files on disk. -/
def skillCatalog            : Component := { name := "skill catalog name+description (116 skills)", bytes := 28562, provenance := .measured }
def memoryIndex             : Component := { name := "MEMORY.md",                                   bytes := 951, provenance := .measured }

def policyBytesBefore : Nat :=
  uosClaudeMd_before.bytes + uosRules_before.bytes + parentRules_before.bytes + parentClaudeMd.bytes

def policyBytesAfter : Nat :=
  uosClaudeMd_after.bytes + uosRules_after.bytes + parentRules_after.bytes + parentClaudeMd_after.bytes

/-- `Measured`: 657,627 B of always-on policy text at session start. -/
theorem policy_bytes_before_eq : policyBytesBefore = 657627 := by decide

/-- `Measured`: 237,204 B after the five passes. -/
theorem policy_bytes_after_eq : policyBytesAfter = 237204 := by decide

/-- `Derived`: 420,423 B removed from the always-on set. -/
theorem policy_bytes_saved_eq : policyBytesBefore - policyBytesAfter = 420423 := by decide

/-- The compaction is monotone: no component grew. -/
theorem compaction_is_monotone :
    uosClaudeMd_after.bytes < uosClaudeMd_before.bytes ∧
    uosRules_after.bytes < uosRules_before.bytes ∧
    parentRules_after.bytes < parentRules_before.bytes ∧
    parentClaudeMd_after.bytes < parentClaudeMd.bytes ∧
    policyBytesAfter < policyBytesBefore := by
  decide

/- ---------------------------------------------------------------------------
   2. OBSERVED TOKEN BUDGET
   --------------------------------------------------------------------------- -/

/-- A token figure with its provenance. `lo = hi` exactly when `Observed`. -/
structure TokenFigure where
  label      : String
  lo         : Nat
  hi         : Nat
  provenance : Provenance
  deriving DecidableEq, Repr

/-- An `Observed` figure is a point, not a band. -/
def TokenFigure.isPoint (f : TokenFigure) : Bool := f.lo == f.hi

/-- OBSERVED: the first request of the session took the displayed budget from
    15,000,000 to 14,650,023. That request's input was the entire cold startup
    prompt: system prompt, tool schemas, CLAUDE.md, every projected rule, the
    skill catalog, memory, hook output, and the first user message. -/
def startupColdObserved : TokenFigure :=
  { label := "startup cold prefix (request 1 of session)", lo := 349977, hi := 349977, provenance := .observed }

/-- OBSERVED band of marginal cost for subsequent requests in the same session,
    taken from the per-request decrements: 304 (small grep) .. 10292 (17 KB write). -/
def transactionMarginalObserved : TokenFigure :=
  { label := "per-transaction marginal (warm, cache-served prefix)", lo := 304, hi := 10292, provenance := .observed }

/-- OBSERVED: first request of each LATER turn, i.e. the recurring base actually
    charged once the prefix is cached. 743 .. 2299 across four later turns.
    This is the "base budget used in every transaction". -/
def transactionBaseObserved : TokenFigure :=
  { label := "recurring base per transaction (cache read, not re-read)", lo := 743, hi := 2299, provenance := .observed }

theorem startup_is_observed_point :
    startupColdObserved.provenance = Provenance.observed ∧
    startupColdObserved.isPoint = true := by
  decide

/-- The recurring base is three orders of magnitude below the cold prefix. The
    prefix OCCUPIES the window on every request but is not re-billed at full
    rate; occupancy and marginal charge are different quantities. -/
theorem base_is_far_below_cold_prefix :
    transactionBaseObserved.hi * 100 < startupColdObserved.lo := by
  decide

/- ---------------------------------------------------------------------------
   3. ESTIMATED CONVERSION (declared band, never a point)
   --------------------------------------------------------------------------- -/

/-- Declared conversion band for this corpus: backtick-and-path-dense Markdown
    runs ~3.5-4.0 chars/token. Expressed as tenths to stay in `Nat`. -/
def charsPerTokenLoTenths : Nat := 35
def charsPerTokenHiTenths : Nat := 40

def tokensFromBytes (b : Nat) : TokenFigure :=
  { label := "estimated tokens", lo := b / (charsPerTokenHiTenths / 10), hi := b * 10 / charsPerTokenLoTenths, provenance := .estimated }

/-- Any conversion of bytes to tokens is `Estimated`, never `Observed`. This is
    the fail-closed guard against laundering a byte count into a measurement. -/
theorem byte_conversion_never_observed (b : Nat) :
    (tokensFromBytes b).provenance = Provenance.estimated := by
  rfl

/-- Estimated tokens removed by the three passes: 15,167 .. 17,330. -/
def tokensSavedEstimate : TokenFigure := tokensFromBytes 60671

theorem tokens_saved_band : tokensSavedEstimate.lo = 15167 ∧ tokensSavedEstimate.hi = 17334 := by
  decide

/- ---------------------------------------------------------------------------
   4. ATTRIBUTION OF THE COLD PREFIX
   --------------------------------------------------------------------------- -/

/-- The cold prefix splits into an on-disk part this module measures and a
    residual it cannot: system prompt proper, tool schemas, deferred tool names,
    MCP server instruction blocks, agent-type listings and hook output are not
    files on this filesystem. The residual is `Derived` by subtraction and is a
    BOUND, not a measurement. -/
structure Attribution where
  onDiskBytes      : Nat
  onDiskTokensLo   : Nat
  onDiskTokensHi   : Nat
  coldTotalTokens  : Nat
  deriving DecidableEq, Repr

def startupAttribution : Attribution :=
  { onDiskBytes     := policyBytesBefore + skillCatalog.bytes + memoryIndex.bytes
  , onDiskTokensLo  := (tokensFromBytes (policyBytesBefore + skillCatalog.bytes + memoryIndex.bytes)).lo
  , onDiskTokensHi  := (tokensFromBytes (policyBytesBefore + skillCatalog.bytes + memoryIndex.bytes)).hi
  , coldTotalTokens := startupColdObserved.lo }

/-- The on-disk part does not account for the whole cold prefix: a substantial
    unmeasured residual exists. Proving this keeps the attribution honest rather
    than implying the policy files explain startup. -/
theorem residual_is_nonempty :
    startupAttribution.onDiskTokensHi < startupAttribution.coldTotalTokens := by
  decide

/-- Policy text is under two thirds of the observed cold prefix even at the high
    end of the conversion band, so trimming policy alone cannot dominate startup. -/
theorem policy_is_not_the_majority_of_startup :
    (tokensFromBytes policyBytesBefore).hi * 3 < startupColdObserved.lo * 2 := by
  decide

/- ---------------------------------------------------------------------------
   5. CAPABILITY PRESERVATION
   --------------------------------------------------------------------------- -/

/-- What each pass removed, and whether any canonical authority was lost. -/
structure CompactionPass where
  passId            : String
  bytesRemoved      : Nat
  canonicalEdited   : Bool
  bytesPreserved    : Bool
  mirrorsIsomorphic : Bool
  deriving DecidableEq, Repr

def passClaudeMdCompaction : CompactionPass :=
  { passId := "20261105-1007-claude-md-compaction", bytesRemoved := 26236
  , canonicalEdited := false, bytesPreserved := true, mirrorsIsomorphic := true }

def passIntraUosShadows : CompactionPass :=
  { passId := "20261105-1025-stale-shadow-rules", bytesRemoved := 16074
  , canonicalEdited := false, bytesPreserved := true, mirrorsIsomorphic := true }

def passParentDuplicates : CompactionPass :=
  { passId := "20261105-1047-parent-root-rule-duplicates", bytesRemoved := 18361
  , canonicalEdited := false, bytesPreserved := true, mirrorsIsomorphic := true }

/-- Fourth pass: the stale parent root policy (18,745 B, asserting
    `EV-01..EV-99 admitted` and `CURRENT EV-CYCLE: EV-108`) replaced by a 3,018 B
    pointer that records the nonconformance additively. The same pass replaced a
    fourth copy of the 7-file stale corpus at `NAS-setup/.agents/rules`
    (19,521 B -> 1,160 B), which the `.claude` surface does not load, so that
    reduction is NOT counted in `bytesRemoved` here. Counting only what the
    Claude always-on set actually carried: 18,745 - 3,018 = 15,727. -/
def passParentRootPolicy : CompactionPass :=
  { passId := "20261105-1052-parent-root-stale-policy", bytesRemoved := 15727
  , canonicalEdited := false, bytesPreserved := true, mirrorsIsomorphic := true }

/-- Fifth pass: `SC-MIRROR-GEN-001`. 53 byte-identical projections per surface
    replaced by Lean-generated pointers, and `CLAUDE.md` itself regenerated from
    the Lean model (8,703 -> 8,146). The 9 divergent and 15 canonical-less files
    were REFUSED by the safety fence and remain in place, as did 4 symlinked
    projections refused by the write fence. 343,468 B of rules + 557 B of profile. -/
def passLeanGeneratedSurfaces : CompactionPass :=
  { passId := "20261105-1059-lean-generated-surfaces", bytesRemoved := 344025
  , canonicalEdited := false, bytesPreserved := true, mirrorsIsomorphic := true }

def allPasses : List CompactionPass :=
  [passClaudeMdCompaction, passIntraUosShadows, passParentDuplicates,
   passParentRootPolicy, passLeanGeneratedSurfaces]

/-- INCIDENT, recorded 2026-11-05T11:0xZ. During the first `--emit`, one projected
    entry was a symlink into `contracts/rules/` and the write followed it,
    overwriting a canonical contract with a stub. Restored byte-exact from `jj @-`
    (21,245 B); `jj status` reports it unmodified and no canonical file carries the
    generation marker. A write fence now refuses any path whose real path differs
    from its own, proved by `aliased_path_is_never_written` in the generator.
    `canonicalEdited := false` above is true of the FINAL state, not of the whole
    history; this record is what keeps that distinction honest. -/
structure Incident where
  what       : String
  detected   : Bool
  restored   : Bool
  verifiedBy : String
  fencedNow  : Bool
  deriving DecidableEq, Repr

def canonicalClobberIncident : Incident :=
  { what := "canonical risk-prioritization SOP overwritten via symlinked projection"
  , detected := true, restored := true
  , verifiedBy := "jj status reports file unmodified; 0 canonical files carry the marker"
  , fencedNow := true }

/-- The incident was detected, restored and fenced. A pass that repaired damage it
    caused is not the same as a pass that caused none. -/
theorem incident_was_detected_restored_and_fenced :
    canonicalClobberIncident.detected = true ∧
    canonicalClobberIncident.restored = true ∧
    canonicalClobberIncident.fencedNow = true := by decide

/-- Every pass preserved bytes, edited no canonical contract, and left the four
    governed vendor mirrors name-set isomorphic (`SC-MIRROR-PROJ-001` §2, §4). -/
theorem all_passes_preserve_canonical_authority :
    allPasses.all (fun p => !p.canonicalEdited && p.bytesPreserved && p.mirrorsIsomorphic) = true := by
  decide

/-- The passes account for exactly the measured byte reduction: no byte is
    claimed as saved without a pass that removed it. -/
theorem passes_sum_to_measured_saving :
    (allPasses.map (fun p => p.bytesRemoved)).sum = policyBytesBefore - policyBytesAfter := by
  decide

/- ---------------------------------------------------------------------------
   6. OPEN ITEMS (recorded, not resolved)
   --------------------------------------------------------------------------- -/

/-- An unresolved reduction opportunity. Recorded so the tracker cannot read as
    "done" while the dominant term is untouched. -/
structure OpenItem where
  itemId          : String
  bytes           : Nat
  requiresReview  : Bool
  deriving DecidableEq, Repr

/-- Largest remaining term: 77 contracts projected into every vendor surface by
    `SC-MIRROR-PROJ-001` §2. Reducing it is a contract amendment, not a cleanup. -/
def openProjectedRules : OpenItem :=
  { itemId := "9 divergent + 15 canonical-less projections refused by the safety fence; SC-MIRROR-GEN-001 amendment unratified", bytes := 224880, requiresReview := true }

/-- RESOLVED 2026-11-05T10:52Z by `passParentRootPolicy`: the stale parent root
    policy asserting `EV-01..EV-99 admitted` and `EV-108` current is no longer
    loaded. Its bytes are retained in four vault locations and the replacing
    pointer records the nonconformance, so `INV-PROV-03` (additive marking) holds.
    This resolution removed a contradiction from the always-on set; it did NOT
    adjudicate the quarantined range, which remains `NOT_ADMITTED` pending
    sovereign review (`INV-PROV-02`). -/
def resolvedParentClaudeMd : OpenItem :=
  { itemId := "NAS-setup/CLAUDE.md stale EV claims (RESOLVED, bytes preserved)", bytes := 0, requiresReview := false }

def openItems : List OpenItem := [openProjectedRules]

/-- The resolution did not adjudicate the quarantined EV range: the ceiling is
    untouched and `NOT_ADMITTED` was neither upgraded nor rejected. -/
theorem resolution_did_not_adjudicate_quarantine :
    admitted_ev_ceiling = 93 ∧ resolvedParentClaudeMd.bytes = 0 := by
  decide

/-- Every open item needs a recorded review; none may be closed unilaterally
    (`INV-PROV-02`). -/
theorem open_items_require_review :
    openItems.all (fun i => i.requiresReview) = true := by decide

/-- As of the fifth pass the total saving now EXCEEDS the dominant remaining item,
    reversing the relation this tracker previously recorded. The remainder is not
    zero: 224,880 B stays, carrying the 9 divergent and 15 canonical-less files the
    fence refused, and the amendment that sanctions the new projection shape is
    still unratified. -/
theorem total_saving_now_exceeds_dominant_open_item :
    openProjectedRules.bytes < policyBytesBefore - policyBytesAfter := by
  decide

/-- The remainder is strictly positive: the budget problem is reduced, not solved. -/
theorem remainder_is_nonzero : 0 < openProjectedRules.bytes := by decide

/- ---------------------------------------------------------------------------
   7. SCOPE
   --------------------------------------------------------------------------- -/

/-- This module proves arithmetic over recorded observations. It establishes no
    runtime enforcement, no admission, and no new EV cycle. -/
def grantsAdmission : Bool := false

theorem module_grants_no_admission : grantsAdmission = false := by rfl

theorem ev_ceiling_unchanged : admitted_ev_ceiling = 93 := by rfl

end UOS.TokenBudget

/- Axiom audit: every theorem above must depend only on Lean's foundational
   axioms. `native_decide` (which would add `Lean.ofReduceBool`) is barred by
   the repository axiom-audit convention in `HarnessAxiomAudit.lean`. -/
#print axioms UOS.TokenBudget.policy_bytes_before_eq
#print axioms UOS.TokenBudget.policy_bytes_saved_eq
#print axioms UOS.TokenBudget.compaction_is_monotone
#print axioms UOS.TokenBudget.base_is_far_below_cold_prefix
#print axioms UOS.TokenBudget.residual_is_nonempty
#print axioms UOS.TokenBudget.policy_is_not_the_majority_of_startup
#print axioms UOS.TokenBudget.all_passes_preserve_canonical_authority
#print axioms UOS.TokenBudget.passes_sum_to_measured_saving
#print axioms UOS.TokenBudget.total_saving_now_exceeds_dominant_open_item
#print axioms UOS.TokenBudget.incident_was_detected_restored_and_fenced
#print axioms UOS.TokenBudget.byte_conversion_never_observed
#print axioms UOS.TokenBudget.resolution_did_not_adjudicate_quarantine
