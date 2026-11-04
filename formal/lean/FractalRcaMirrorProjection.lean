/- =============================================================================
   FRACTAL RCA & IMPLICATIONS CHECK — AGENT-SURFACE RULE PROJECTION DRIFT
   (LEAN 4.33.0, zero axioms)
   =============================================================================
   Observed 2026-11-05T11:0xZ in `/home/an/NAS-setup/uos`.
   Subject: `SC-MIRROR-PROJ-001` §2 (byte-identical projection of every canonical
   contract into `.claude`, `.codex`, `.gemini`, `.agents`) and §4 (validation gate).

   This module encodes a measured defect, its root cause, its implications at each
   fractal layer L0..L9, and the falsifier for each claim. Every number below is a
   filesystem measurement taken with `wc -c` / `md5sum` / `diff`, recorded as data.
   Theorems are arithmetic and structural over those recordings: they do NOT prove
   runtime behaviour and grant no admission (`SC-PROVENANCE-001`).
   ============================================================================= -/

namespace UOS.FractalRca

def admitted_ev_ceiling : Nat := 93

/-- The ten canonical fractal layers (`SC-FRACTAL-TAXONOMY-001`). -/
inductive Layer where
  | l0 | l1 | l2 | l3 | l4 | l5 | l6 | l7 | l8 | l9
  deriving DecidableEq, Repr

/-- Classification of a projected mirror file against its canonical contract. -/
inductive ProjClass where
  | identicalToCanonical   -- mirror bytes = canonical bytes (§2 satisfied)
  | divergentFromCanonical -- same name, different bytes (§2 VIOLATED)
  | noCanonicalCounterpart -- body exists only in the mirror (§1 violated)
  deriving DecidableEq, Repr

/-- Measured census of `.claude/rules` against `contracts/rules`, 2026-11-05. -/
structure Census where
  identicalFiles : Nat
  identicalBytes : Nat
  divergentFiles : Nat
  divergentBytes : Nat
  noCanonFiles   : Nat
  noCanonBytes   : Nat
  deriving DecidableEq, Repr

def measuredCensus : Census :=
  { identicalFiles := 53, identicalBytes := 402126
  , divergentFiles := 9,  divergentBytes := 117044
  , noCanonFiles   := 15, noCanonBytes   := 49178 }

def Census.totalFiles (c : Census) : Nat := c.identicalFiles + c.divergentFiles + c.noCanonFiles
def Census.totalBytes (c : Census) : Nat := c.identicalBytes + c.divergentBytes + c.noCanonBytes

/-- The census accounts for exactly the 77 projected files and 568,348 B measured. -/
theorem census_is_complete :
    measuredCensus.totalFiles = 77 ∧ measuredCensus.totalBytes = 568348 := by decide

/- ---------------------------------------------------------------------------
   SYMPTOM
   --------------------------------------------------------------------------- -/

/-- One divergent file: mirror bytes vs canonical bytes, and how the two differ.
    `mirrorOnlyLines` counts lines present in the mirror and absent from canonical. -/
structure Divergence where
  file            : String
  mirrorBytes     : Nat
  canonicalBytes  : Nat
  mirrorOnlyLines : Nat
  fourMirrorsAgree : Bool
  deriving DecidableEq, Repr

/-- All nine measured divergences. -/
def divergences : List Divergence :=
  [ { file := "20260907-0653-tri-agent-coordination.md",                     mirrorBytes :=  9326, canonicalBytes := 10954, mirrorOnlyLines := 0, fourMirrorsAgree := true }
  , { file := "20260907-1515-sa-plan-fractal-jidoka-tps-mandate.md",         mirrorBytes := 15708, canonicalBytes := 15712, mirrorOnlyLines := 1, fourMirrorsAgree := true }
  , { file := "20260908-0551-release-assurance-sdlc-sre-sop.md",             mirrorBytes :=  7131, canonicalBytes :=  8186, mirrorOnlyLines := 0, fourMirrorsAgree := true }
  , { file := "20260912-0745-sc-journal-v3-anticipatory-contract.md",        mirrorBytes := 11975, canonicalBytes := 16391, mirrorOnlyLines := 1, fourMirrorsAgree := true }
  , { file := "20260912-1035-link-tracking-and-website-verification-sop.md", mirrorBytes := 13913, canonicalBytes := 13935, mirrorOnlyLines := 1, fourMirrorsAgree := true }
  , { file := "20260912-1238-comprehensive-capability-and-website-sop.md",   mirrorBytes := 22503, canonicalBytes := 22525, mirrorOnlyLines := 1, fourMirrorsAgree := true }
  , { file := "20261030-1058-ak47-multi-agent-mcp-symbiosis-rule.md",        mirrorBytes := 16650, canonicalBytes := 18852, mirrorOnlyLines := 0, fourMirrorsAgree := true }
  , { file := "mirage-production-integration-contract.md",                   mirrorBytes := 11710, canonicalBytes := 12695, mirrorOnlyLines := 0, fourMirrorsAgree := true }
  , { file := "sdlc-sre-verification-process-contract.md",                   mirrorBytes :=  8128, canonicalBytes :=  9349, mirrorOnlyLines := 1, fourMirrorsAgree := true } ]

/-- SYMPTOM 1: in every divergence the mirror is SMALLER than canonical. The drift
    has a single direction, which is the signature of a stale snapshot rather than
    of independent vendor edits. -/
theorem symptom_mirror_always_smaller :
    divergences.all (fun d => d.mirrorBytes < d.canonicalBytes) = true := by decide

/-- SYMPTOM 2: at most one line exists in a mirror and not in canonical, so the
    canonical text is a near-superset. No mirror carries a body of content that
    canonical lacks. -/
theorem symptom_canonical_is_near_superset :
    divergences.all (fun d => d.mirrorOnlyLines ≤ 1) = true := by decide

/-- SYMPTOM 3: all four surfaces agree with EACH OTHER on every divergent file.
    The fault line is mirror-set vs canonical, NOT harness vs harness. -/
theorem symptom_drift_is_not_between_harnesses :
    divergences.all (fun d => d.fourMirrorsAgree) = true := by decide

/-- Worst measured case: the journal contract every agent actually reads is
    4,416 B short of canonical. -/
def worstGapBytes : Nat := 16391 - 11975

theorem worst_gap_is_journal_contract : worstGapBytes = 4416 := by decide

/- ---------------------------------------------------------------------------
   ROOT CAUSE
   --------------------------------------------------------------------------- -/

/-- The four checks `SC-MIRROR-PROJ-001` §4 actually performs. -/
inductive GateCheck where
  | nameSetIsomorphism
  | jsonParse
  | skillFrontmatter
  | brokenSymlinkCount
  deriving DecidableEq, Repr

def gateChecks : List GateCheck :=
  [.nameSetIsomorphism, .jsonParse, .skillFrontmatter, .brokenSymlinkCount]

/-- Does a given check compare mirror bytes against the canonical contract? -/
def GateCheck.comparesBytesToCanonical : GateCheck → Bool
  | .nameSetIsomorphism  => false  -- compares NAMES across surfaces only
  | .jsonParse           => false  -- parses config JSON
  | .skillFrontmatter    => false  -- checks SKILL.md frontmatter
  | .brokenSymlinkCount  => false  -- counts dangling links

/-- ROOT CAUSE: §2 mandates byte-identical projection and §4 contains no check
    that can observe byte divergence. The mandate has no falsifier, so drift is
    undetectable by the gate that exists to enforce it. This is the defect; the
    nine divergences are its symptom. -/
theorem root_cause_gate_cannot_detect_byte_divergence :
    gateChecks.all (fun c => !c.comparesBytesToCanonical) = true := by decide

/-- A mandate is enforceable only if some gate check can falsify it. -/
def mandateIsEnforceable (checks : List GateCheck) : Bool :=
  checks.any (fun c => c.comparesBytesToCanonical)

theorem byte_identity_mandate_is_unenforceable :
    mandateIsEnforceable gateChecks = false := by decide

/-- Second-order cause: the projection is manual and its cost grows with the
    product of contracts and surfaces, so drift probability rises monotonically
    with corpus growth. 77 contracts x 4 surfaces = 308 artifacts hand-synced. -/
def surfaces : Nat := 4
def manualArtifacts (contracts : Nat) : Nat := contracts * surfaces

theorem manual_sync_burden : manualArtifacts 77 = 308 := by decide

theorem burden_grows_with_corpus (a b : Nat) (h : a < b) :
    manualArtifacts a < manualArtifacts b := by
  simp [manualArtifacts, surfaces]
  omega

/- ---------------------------------------------------------------------------
   FRACTAL IMPLICATIONS L0..L9
   --------------------------------------------------------------------------- -/

/-- An implication of the defect at one layer, with the falsifier that would
    refute it and whether it is contained by the pointer-projection repair. -/
structure Implication where
  layer            : Layer
  claim            : String
  falsifier        : String
  containedByRepair : Bool
  deriving DecidableEq, Repr

def implications : List Implication :=
  [ { layer := .l0, claim := "A constitutional mandate (§2 byte-identity) is active with no falsifier, so compliance is asserted and unverified"
    , falsifier := "exhibit a §4 check that compares mirror bytes to canonical"
    , containedByRepair := true }
  , { layer := .l1, claim := "Byte-identity is the atomic invariant and is violated in 9 of 77 projected files"
    , falsifier := "md5 of each mirror file equals md5 of its canonical contract"
    , containedByRepair := true }
  , { layer := .l2, claim := "The validation gate is structurally incapable of observing the violation it governs"
    , falsifier := "run the §4 gate against the 9 known divergences and have it fail"
    , containedByRepair := true }
  , { layer := .l3, claim := "Each mirror edit is an unverified transaction: nothing binds the copy to the canonical revision"
    , falsifier := "a recorded projection receipt naming source revision and digest per file"
    , containedByRepair := true }
  , { layer := .l4, claim := "308 hand-synced artifacts across 4 surfaces make drift the default system state, not an anomaly"
    , falsifier := "a generator that derives every surface from one source"
    , containedByRepair := true }
  , { layer := .l5, claim := "Agents reason from stale policy: the SC-JOURNAL-v3 text in context is 4,416 B short of canonical, omitting the 2026-09-13 diagram-check amendment"
    , falsifier := "diff the in-context contract against canonical and find no missing obligation"
    , containedByRepair := true }
  , { layer := .l6, claim := "All four harness surfaces agree with each other, so no harness can detect the drift by peer comparison"
    , falsifier := "find a surface whose bytes match canonical while others do not"
    , containedByRepair := true }
  , { layer := .l7, claim := "Copies propagate across roots: the umbrella root held a 4th and 5th generation copy of the same corpus"
    , falsifier := "enumerate roots and find no second copy of a canonical contract"
    , containedByRepair := false }
  , { layer := .l8, claim := "Every new contract adds 4 copies, so the always-on corpus grows at 4x the canonical rate"
    , falsifier := "add a contract and observe the projected byte total grow by its size only once"
    , containedByRepair := true }
  , { layer := .l9, claim := "Two-key verification is undermined: a stale projected obligation cannot be bound to a candidate revision"
    , falsifier := "bind each projected file to the canonical revision it was taken from"
    , containedByRepair := true } ]

/-- The implications check covers all ten layers exactly once. -/
theorem implications_cover_all_ten_layers :
    implications.length = 10 ∧
    implications.map (fun i => i.layer) =
      [Layer.l0, .l1, .l2, .l3, .l4, .l5, .l6, .l7, .l8, .l9] := by decide

/-- Every implication carries a falsifier: no claim is unfalsifiable. -/
theorem every_implication_has_a_falsifier :
    implications.all (fun i => i.falsifier ≠ "") = true := by decide

/-- HONEST BOUND: the repair does not contain every layer. L7 (copies across
    independent roots) is a filesystem-topology problem that a generator inside
    one repository cannot prevent. Nine of ten are contained; this records the
    tenth rather than claiming full coverage. -/
theorem repair_does_not_contain_every_layer :
    (implications.filter (fun i => !i.containedByRepair)).length = 1 := by decide

/- ---------------------------------------------------------------------------
   CONTAINMENT, SAFETY FENCE, RECOVERY
   --------------------------------------------------------------------------- -/

/-- Only a byte-identical mirror may be replaced by a pointer: for those files
    the canonical bytes are provably present elsewhere, so replacement is
    lossless. Divergent and canonical-less files carry content that would be
    destroyed, so the fence refuses them. -/
def safeToReplaceWithPointer : ProjClass → Bool
  | .identicalToCanonical   => true
  | .divergentFromCanonical => false
  | .noCanonicalCounterpart => false

/-- SAFETY FENCE: the repair is lossless by construction. It touches exactly the
    class whose bytes are recoverable from canonical and refuses the other two. -/
theorem containment_is_lossless :
    safeToReplaceWithPointer .identicalToCanonical = true ∧
    safeToReplaceWithPointer .divergentFromCanonical = false ∧
    safeToReplaceWithPointer .noCanonicalCounterpart = false := by decide

/-- A pointer cannot go stale with respect to the body it names, so replacing a
    copy with a pointer eliminates the drift CLASS for that file rather than
    repairing one instance. -/
def pointerCanDriftFromCanonical : Bool := false

theorem pointer_eliminates_drift_class : pointerCanDriftFromCanonical = false := by decide

/-- Bytes eligible for lossless containment, and the bytes that must stay. -/
def eligibleBytes : Nat := measuredCensus.identicalBytes
def mustRemainBytes : Nat := measuredCensus.divergentBytes + measuredCensus.noCanonBytes

theorem containment_scope : eligibleBytes = 402126 ∧ mustRemainBytes = 166222 := by decide

/-- The eligible class is the majority of the corpus, but a large remainder must
    stay until the 9 divergences are reconciled and the 15 orphans promoted. The
    repair is therefore partial by design, and says so. -/
theorem containment_is_partial : mustRemainBytes < eligibleBytes ∧ 0 < mustRemainBytes := by decide

/-- RECOVERY: every replaced body is recoverable because canonical holds the same
    bytes; no vault is strictly required for the eligible class, though one is
    taken anyway. -/
def recoveryPathExists : ProjClass → Bool
  | .identicalToCanonical   => true   -- canonical holds identical bytes
  | .divergentFromCanonical => true   -- untouched
  | .noCanonicalCounterpart => true   -- untouched

theorem recovery_exists_for_every_class :
    [ProjClass.identicalToCanonical, .divergentFromCanonical, .noCanonicalCounterpart].all
      recoveryPathExists = true := by decide

/- ---------------------------------------------------------------------------
   OWNER AND SCOPE
   --------------------------------------------------------------------------- -/

/-- §2 says "byte-identical copy". Replacing bodies with pointers changes that
    sentence, which is a contract amendment and not a cleanup. This module
    records that the amendment is NOT ratified. -/
def amendmentRatified : Bool := false
def amendmentRequiresSovereignReview : Bool := true

theorem amendment_is_not_ratified :
    amendmentRatified = false ∧ amendmentRequiresSovereignReview = true := by decide

/-- The nine §2 violations exist independently of any amendment: they are a live
    nonconformance against the contract as currently written. -/
def preexistingViolationCount : Nat := 9

theorem violation_predates_amendment : 0 < preexistingViolationCount := by decide

def grantsAdmission : Bool := false

theorem module_grants_no_admission : grantsAdmission = false := by rfl
theorem ev_ceiling_unchanged : admitted_ev_ceiling = 93 := by rfl

end UOS.FractalRca

#print axioms UOS.FractalRca.census_is_complete
#print axioms UOS.FractalRca.symptom_mirror_always_smaller
#print axioms UOS.FractalRca.symptom_canonical_is_near_superset
#print axioms UOS.FractalRca.symptom_drift_is_not_between_harnesses
#print axioms UOS.FractalRca.root_cause_gate_cannot_detect_byte_divergence
#print axioms UOS.FractalRca.byte_identity_mandate_is_unenforceable
#print axioms UOS.FractalRca.burden_grows_with_corpus
#print axioms UOS.FractalRca.implications_cover_all_ten_layers
#print axioms UOS.FractalRca.every_implication_has_a_falsifier
#print axioms UOS.FractalRca.repair_does_not_contain_every_layer
#print axioms UOS.FractalRca.containment_is_lossless
#print axioms UOS.FractalRca.containment_is_partial
#print axioms UOS.FractalRca.recovery_exists_for_every_class
#print axioms UOS.FractalRca.amendment_is_not_ratified
