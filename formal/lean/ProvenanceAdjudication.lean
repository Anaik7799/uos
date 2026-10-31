import Std
/-!
ProvenanceAdjudication.lean: CANDIDATE formal model, REPORT_ONLY forensic recommendation model.
Scope: Sa-plan uos/codex-handover-open-items-fractal-plan/20261031-1240
OI01_EV94_109_SOVEREIGN_AUDIT, worker pi-hive-execution-20261031, attempt1, ACTIVE_OBSERVATION_PASS current.
This model is NOT executable source/runtime conformance. It proves nothing about deployed code.
No general deployment or system admission follows from any theorem here.
EV94..109 (ADR71..86) remain NOT_ADMITTED. Raw clock equality only flags invalid clock evidence;
it never selects a recommendation (including fabrication) and never changes historical status.
-/

namespace ProvenanceAdjudication

inductive Recommendation where
  | rejectedFabrication
  | codePresentRequiresFreshTwoKeyRebind
  | supersededBySaPlan
  deriving DecidableEq, Repr

/-- Only one constructor: there is deliberately no admission constructor. -/
inductive HistoricalStatus where
  | notAdmitted
  deriving DecidableEq, Repr

def HistoricalStatus.label : HistoricalStatus → String
  | .notAdmitted => "NOT_ADMITTED"

theorem historical_status_unique (s : HistoricalStatus) : s = HistoricalStatus.notAdmitted := by
  cases s; rfl

/-- Validated claim: EV in 94..109, proofs carried in the value. -/
structure Claim where
  ev : Nat
  lo : 94 ≤ ev
  hi : ev ≤ 109

/-- Derived ADR = EV - 23 (so ADR is in 71..86). -/
def Claim.adr (c : Claim) : Nat := c.ev - 23

/-- Raw smart constructor: invalid EVs are rejected with none. -/
def mkClaim? (n : Nat) : Option Claim :=
  if h : 94 ≤ n ∧ n ≤ 109 then some ⟨n, h.1, h.2⟩ else none

theorem mkClaim_rejects (n : Nat) (h : n < 94 ∨ 109 < n) : mkClaim? n = none := by
  have hn : ¬ (94 ≤ n ∧ n ≤ 109) := by omega
  unfold mkClaim?
  exact dif_neg hn

theorem mkClaim_accepts (n : Nat) (h1 : 94 ≤ n) (h2 : n ≤ 109) :
    ∃ c, mkClaim? n = some c ∧ c.ev = n := by
  unfold mkClaim?
  exact ⟨⟨n, h1, h2⟩, dif_pos ⟨h1, h2⟩, rfl⟩

/-- Total constructor from an index; out-of-range indices fall back to EV94. -/
def claimOf (i : Nat) : Claim :=
  if h : i < 16 then ⟨94 + i, by omega, by omega⟩ else ⟨94, by omega, by omega⟩

def allClaims : List Claim := (List.range 16).map claimOf

def ev94 : Claim := claimOf 0
def ev109 : Claim := claimOf 15

theorem ev94_mem : ev94 ∈ allClaims :=
  List.mem_map.mpr ⟨0, List.mem_range.mpr (by decide), rfl⟩
theorem ev109_mem : ev109 ∈ allClaims :=
  List.mem_map.mpr ⟨15, List.mem_range.mpr (by decide), rfl⟩

/-! Distinct typed clock domains: they cannot be mixed by the type checker. -/
structure UTC where
  raw : Nat
  deriving Repr
structure Monotonic where
  raw : Nat
  deriving Repr
structure ClockEvidence where
  utc : UTC
  mono : Monotonic
  deriving Repr

inductive ClockStatus where
  | valid
  | invalidClockEvidence
  deriving DecidableEq, Repr

def ClockEvidence.rawEqual (e : ClockEvidence) : Bool := e.utc.raw == e.mono.raw

/-- Clock validation only; it is independent of recommendation selection. -/
def ClockEvidence.status (e : ClockEvidence) : ClockStatus :=
  if e.rawEqual then ClockStatus.invalidClockEvidence else ClockStatus.valid

theorem equal_raw_flags_invalid (e : ClockEvidence) (h : e.utc.raw = e.mono.raw) :
    e.status = ClockStatus.invalidClockEvidence := by
  simp [ClockEvidence.status, ClockEvidence.rawEqual, h]

theorem different_raw_valid (e : ClockEvidence) (h : e.utc.raw ≠ e.mono.raw) :
    e.status = ClockStatus.valid := by
  simp [ClockEvidence.status, ClockEvidence.rawEqual, h]

structure Dossier where
  ceiling : Nat
  applicationAdmitted : Bool
  systemAdmitted : Bool
  history : HistoricalStatus
  claims : List Claim
  recs : List (Claim × Recommendation)
  clocks : List (Claim × ClockEvidence)

def initial : Dossier :=
  { ceiling := 93, applicationAdmitted := false, systemAdmitted := false,
    history := HistoricalStatus.notAdmitted, claims := allClaims, recs := [], clocks := [] }

/-- Pure, total, report-only: appends a recommendation for an existing claim. -/
def Dossier.addRecommendation (d : Dossier) (c : Claim) (_h : c ∈ d.claims)
    (r : Recommendation) : Dossier :=
  { d with recs := d.recs ++ [(c, r)] }

/-- Records clock evidence only; never touches recs, ceiling, history or admission flags. -/
def Dossier.recordClock (d : Dossier) (c : Claim) (e : ClockEvidence) : Dossier :=
  { d with clocks := d.clocks ++ [(c, e)] }

structure Inv (d : Dossier) : Prop where
  ceiling : d.ceiling = 93
  app : d.applicationAdmitted = false
  sys : d.systemAdmitted = false
  hist : d.history = HistoricalStatus.notAdmitted
  recsKnown : ∀ p, p ∈ d.recs → p.1 ∈ d.claims

theorem initial_inv : Inv initial := by
  refine ⟨rfl, rfl, rfl, rfl, ?_⟩
  intro p hp
  simp [initial] at hp

theorem inv_addRec {d : Dossier} (h : Inv d) (c : Claim) (hc : c ∈ d.claims)
    (r : Recommendation) : Inv (d.addRecommendation c hc r) := by
  refine ⟨h.ceiling, h.app, h.sys, h.hist, ?_⟩
  intro p hp
  have hp' : p ∈ d.recs ++ [(c, r)] := hp
  rcases List.mem_append.mp hp' with h1 | h1
  · exact h.recsKnown p h1
  · have e : p = (c, r) := List.mem_singleton.mp h1
    subst e
    exact hc

theorem inv_recordClock {d : Dossier} (h : Inv d) (c : Claim) (e : ClockEvidence) :
    Inv (d.recordClock c e) :=
  ⟨h.ceiling, h.app, h.sys, h.hist, h.recsKnown⟩

/-- Generated-history builder: every dossier is built from the seed by total steps. -/
inductive Reachable : Dossier → Prop where
  | init : Reachable initial
  | addRec (d : Dossier) (h : Reachable d) (c : Claim) (hc : c ∈ d.claims)
      (r : Recommendation) : Reachable (d.addRecommendation c hc r)
  | recClock (d : Dossier) (h : Reachable d) (c : Claim) (e : ClockEvidence) :
      Reachable (d.recordClock c e)

theorem reachable_inv {d : Dossier} (h : Reachable d) : Inv d := by
  induction h with
  | init => exact initial_inv
  | addRec d h c hc r ih => exact inv_addRec ih c hc r
  | recClock d h c e ih => exact inv_recordClock ih c e

theorem no_unilateral_promotion {d : Dossier} (h : Reachable d) (c : Claim)
    (hc : c ∈ d.claims) (r : Recommendation) :
    (d.addRecommendation c hc r).applicationAdmitted = false ∧
    (d.addRecommendation c hc r).systemAdmitted = false ∧
    (d.addRecommendation c hc r).history = HistoricalStatus.notAdmitted := by
  have i := inv_addRec (reachable_inv h) c hc r
  exact ⟨i.app, i.sys, i.hist⟩

theorem ceiling_conservation {d : Dossier} (h : Reachable d) (c : Claim)
    (hc : c ∈ d.claims) (r : Recommendation) :
    d.ceiling = 93 ∧ (d.addRecommendation c hc r).ceiling = d.ceiling :=
  ⟨(reachable_inv h).ceiling, rfl⟩

theorem claim_range_preserved {d : Dossier} (c0 : Claim) (hc : c0 ∈ d.claims)
    (r : Recommendation) :
    (d.addRecommendation c0 hc r).claims = d.claims ∧
    ∀ c, c ∈ (d.addRecommendation c0 hc r).claims → 94 ≤ c.ev ∧ c.ev ≤ 109 :=
  ⟨rfl, fun c _ => ⟨c.lo, c.hi⟩⟩

theorem adr_mapping_preserved {d : Dossier} (c0 : Claim) (hc : c0 ∈ d.claims)
    (r : Recommendation) :
    ∀ c, c ∈ (d.addRecommendation c0 hc r).claims →
      c.adr = c.ev - 23 ∧ 71 ≤ c.adr ∧ c.adr ≤ 86 := by
  intro c _
  have h1 := c.lo
  have h2 := c.hi
  unfold Claim.adr
  omega

theorem clock_anomaly_cannot_promote {d : Dossier} (h : Reachable d) (c : Claim)
    (e : ClockEvidence) (_hbad : e.status = ClockStatus.invalidClockEvidence) :
    (d.recordClock c e).ceiling = 93 ∧
    (d.recordClock c e).applicationAdmitted = false ∧
    (d.recordClock c e).systemAdmitted = false ∧
    (d.recordClock c e).history = HistoricalStatus.notAdmitted ∧
    (d.recordClock c e).recs = d.recs := by
  have i := inv_recordClock (reachable_inv h) c e
  exact ⟨i.ceiling, i.app, i.sys, i.hist, rfl⟩

/-- Recommendations do not depend on clock evidence at all. -/
theorem clock_evidence_does_not_select (d : Dossier) (c : Claim) (e1 e2 : ClockEvidence) :
    (d.recordClock c e1).recs = (d.recordClock c e2).recs := rfl

theorem no_application_system_admission {d : Dossier} (h : Reachable d) :
    d.applicationAdmitted = false ∧ d.systemAdmitted = false :=
  ⟨(reachable_inv h).app, (reachable_inv h).sys⟩

/-! Concrete checked examples (report-only; not conformance evidence). -/
example : (mkClaim? 94).isSome = true := by decide
example : (mkClaim? 109).isSome = true := by decide
example : (mkClaim? 93).isNone = true := by decide
example : (mkClaim? 110).isNone = true := by decide
example : ev94.ev = 94 ∧ ev94.adr = 71 := ⟨rfl, rfl⟩
example : ev109.ev = 109 ∧ ev109.adr = 86 := ⟨rfl, rfl⟩

def sameStamp : ClockEvidence := ⟨UTC.mk 5, Monotonic.mk 5⟩
def diffStamp : ClockEvidence := ⟨UTC.mk 5, Monotonic.mk 7⟩
example : sameStamp.status = ClockStatus.invalidClockEvidence := by decide
example : diffStamp.status = ClockStatus.valid := by decide

theorem ev94_mem_initial : ev94 ∈ initial.claims := ev94_mem

def sample : Dossier :=
  (initial.addRecommendation ev94 ev94_mem_initial
    Recommendation.codePresentRequiresFreshTwoKeyRebind).recordClock ev94 sameStamp

example : sample.recs.length = 1 := rfl
example : sample.recs = initial.recs ++ [(ev94, Recommendation.codePresentRequiresFreshTwoKeyRebind)] := rfl
example : sample.ceiling = 93 ∧ sample.applicationAdmitted = false ∧
    sample.systemAdmitted = false := ⟨rfl, rfl, rfl⟩
example : Reachable sample :=
  Reachable.recClock _
    (Reachable.addRec _ Reachable.init ev94 ev94_mem_initial
      Recommendation.codePresentRequiresFreshTwoKeyRebind) ev94 sameStamp

/- Kernel-checked expected values replace demonstration-only evaluation compilation.
   No theorem or model obligation is removed; runtime conformance is separate. -/
example : (mkClaim? 94).map (·.adr) = some 71 := rfl
example : (mkClaim? 109).map (·.adr) = some 86 := rfl
example : (mkClaim? 93).map (·.ev) = none := rfl
example : (mkClaim? 110).map (·.ev) = none := rfl
example : (sameStamp.rawEqual, sameStamp.status) = (true, .invalidClockEvidence) := rfl
example : (diffStamp.rawEqual, diffStamp.status) = (false, .valid) := rfl
example : sample.recs.map (fun p => (p.1.ev, p.1.adr, p.2)) =
    [(94, 71, .codePresentRequiresFreshTwoKeyRebind)] := rfl
example : (sample.ceiling, sample.applicationAdmitted, sample.systemAdmitted, sample.history) =
    (93, false, false, .notAdmitted) := rfl

/-! OI01B_FORMAL_GATEWAY: CODEX RELAY local extension. The model and existing
proof examples above remain unchanged. Demonstration evaluations were replaced
by kernel-checked expected values for the fast gate. Eligibility is NOT admission;
it addresses non-vacuous gate conditions separately from the fixed EV93 ceiling.
Signing/origin/observation flags are trusted external predicates, not verified
cryptography or native source/runtime I/O. No OCaml/Gleam refinement is proved. -/

theorem recommendation_total (r : Recommendation) :
    r = .rejectedFabrication ∨ r = .codePresentRequiresFreshTwoKeyRebind ∨
      r = .supersededBySaPlan := by cases r <;> simp
theorem recommendations_disjoint :
    Recommendation.rejectedFabrication ≠ .codePresentRequiresFreshTwoKeyRebind ∧
    Recommendation.rejectedFabrication ≠ .supersededBySaPlan ∧
    Recommendation.codePresentRequiresFreshTwoKeyRebind ≠ .supersededBySaPlan := by decide

/-- Exactly five information elements: pending bottom, THREE incomparable
singleton recommendations, and conflicting top. This is not a claim that three
unordered atoms alone form a lattice; distributivity is not claimed. -/
inductive EvidenceInfo where
  | pending | rejected | rebind | superseded | conflict
  deriving DecidableEq, Repr
namespace EvidenceInfo
def singleton : Recommendation → EvidenceInfo
  | .rejectedFabrication => .rejected
  | .codePresentRequiresFreshTwoKeyRebind => .rebind
  | .supersededBySaPlan => .superseded
def le (a b : EvidenceInfo) : Prop := a = .pending ∨ b = .conflict ∨ a = b
instance (a b : EvidenceInfo) : Decidable (le a b) := by unfold le; infer_instance
def join (a b : EvidenceInfo) : EvidenceInfo :=
  if a = .pending then b else if b = .pending then a
  else if a = .conflict ∨ b = .conflict then .conflict
  else if a = b then a else .conflict
def meet (a b : EvidenceInfo) : EvidenceInfo :=
  if a = .conflict then b else if b = .conflict then a
  else if a = .pending ∨ b = .pending then .pending
  else if a = b then a else .pending
def elements : List EvidenceInfo := [.pending, .rejected, .rebind, .superseded, .conflict]
theorem exactly_five : elements.length = 5 := rfl
theorem elements_distinct : elements.Nodup := by decide
theorem exhaustive (a : EvidenceInfo) : a ∈ elements := by cases a <;> decide
theorem singleton_injective (a b : Recommendation) : singleton a = singleton b ↔ a = b := by
  cases a <;> cases b <;> decide
theorem order_refl (a : EvidenceInfo) : le a a := by cases a <;> decide
theorem order_antisymm (a b : EvidenceInfo) : le a b → le b a → a = b := by
  cases a <;> cases b <;> decide
theorem order_trans (a b c : EvidenceInfo) : le a b → le b c → le a c := by
  cases a <;> cases b <;> cases c <;> decide
theorem join_comm (a b : EvidenceInfo) : join a b = join b a := by
  cases a <;> cases b <;> decide
theorem join_assoc (a b c : EvidenceInfo) : join (join a b) c = join a (join b c) := by
  cases a <;> cases b <;> cases c <;> decide
theorem join_idempotent (a : EvidenceInfo) : join a a = a := by cases a <;> decide
theorem join_lub (a b c : EvidenceInfo) : le (join a b) c ↔ le a c ∧ le b c := by
  cases a <;> cases b <;> cases c <;> decide
theorem meet_glb (a b c : EvidenceInfo) : le c (meet a b) ↔ le c a ∧ le c b := by
  cases a <;> cases b <;> cases c <;> decide
def resolved (a : EvidenceInfo) : Bool := a != .pending && a != .conflict
end EvidenceInfo

namespace Gateway
structure Candidate where
  digest : Nat
  source : Nat
  target : Nat
  deriving Repr
/-- Validity flags represent an independently established signature, origin
and runtime/formal observation. They are NOT caller strings or crypto proofs. -/
structure Key where
  candidate : Nat
  source : Nat
  signer : Nat
  confirmed : Bool
  signed : Bool
  originVerified : Bool
  deriving Repr
structure Receipt where
  ev : Nat
  runtimeKey : Option Key
  formalKey : Option Key
  clock : ClockEvidence
  observed : UTC
  expires : UTC
  information : EvidenceInfo
  deriving Repr
inductive Reviewer | codex | agy | other deriving DecidableEq, Repr
structure Review where
  candidate : Nat
  source : Nat
  target : Nat
  reviewer : Reviewer
  signer : Nat
  recorded : Bool
  signed : Bool
  originVerified : Bool
  observed : UTC
  expires : UTC
  deriving Repr
def fresh (now observed expires : UTC) : Bool :=
  decide (observed.raw ≤ now.raw ∧ now.raw < expires.raw)
def keyValid (p : Candidate) (k : Key) : Bool :=
  (k.candidate == p.digest) && (k.source == p.source) &&
  k.confirmed && k.signed && k.originVerified && decide (0 < k.signer)
def receiptValid (p : Candidate) (now : UTC) (ev : Nat) (r : Receipt) : Bool :=
  match r.runtimeKey, r.formalKey with
  | some rk, some fk =>
    (r.ev == ev) && keyValid p rk && keyValid p fk && (rk.signer != fk.signer) &&
    (r.clock.utc.raw != r.clock.mono.raw) && (r.clock.utc.raw == r.observed.raw) &&
    fresh now r.observed r.expires && (r.information == .rebind)
  | _, _ => false
def reviewValid (p : Candidate) (now : UTC) (who : Reviewer) (r : Review) : Bool :=
  (r.candidate == p.digest) && (r.source == p.source) && (r.target == p.target) &&
  (r.reviewer == who) && decide (0 < r.signer) && r.recorded && r.signed &&
  r.originVerified && fresh now r.observed r.expires
def jointValid (p : Candidate) (now : UTC) (codex agy : Review) : Bool :=
  reviewValid p now .codex codex && reviewValid p now .agy agy &&
  (codex.signer != agy.signer)
/-- Inclusive EV94..target. Range guard is separate, so an out-of-range target
does not become eligible merely because a truncated list is empty. -/
def requiredEVs (target : Nat) : List Nat :=
  (List.range (target - 93)).map (fun i => 94 + i)
def oneReceipt (p : Candidate) (now : UTC) (receipts : Nat → Option Receipt) (ev : Nat) : Bool :=
  match receipts ev with | none => false | some r => receiptValid p now ev r
def eligible (p : Candidate) (now : UTC) (receipts : Nat → Option Receipt)
    (codex agy : Review) : Bool :=
  decide (94 ≤ p.target ∧ p.target ≤ 109) && jointValid p now codex agy &&
    (requiredEVs p.target).all (oneReceipt p now receipts)

/-- This is a PROPOSED ceiling only. Constructing this record is not evidence;
the `propose` result and its soundness theorem carry the gateway statement. -/
structure Proposal where
  candidate : Candidate
  deriving Repr
def Proposal.canonicalCeiling (_ : Proposal) : Nat := 93
def Proposal.historicalStatus (_ : Proposal) : HistoricalStatus := .notAdmitted
def propose (p : Candidate) (now : UTC) (receipts : Nat → Option Receipt)
    (codex agy : Review) : Option Proposal :=
  if eligible p now receipts codex agy then some ⟨p⟩ else none

theorem required_contains (lo : 94 ≤ ev) (hi : ev ≤ target) : ev ∈ requiredEVs target := by
  apply List.mem_map.mpr
  refine ⟨ev - 94, List.mem_range.mpr ?_, ?_⟩ <;> omega
theorem eligible_range (h : eligible p now receipts codex agy = true) :
    94 ≤ p.target ∧ p.target ≤ 109 := by
  simp only [eligible, Bool.and_eq_true, decide_eq_true_eq] at h
  exact h.1.1
theorem eligible_joint (h : eligible p now receipts codex agy = true) :
    jointValid p now codex agy = true := by
  simp only [eligible, Bool.and_eq_true] at h
  exact h.1.2
theorem eligible_every_intermediate (h : eligible p now receipts codex agy = true)
    (lo : 94 ≤ ev) (hi : ev ≤ p.target) :
    ∃ r, receipts ev = some r ∧ receiptValid p now ev r = true := by
  simp only [eligible, Bool.and_eq_true] at h
  have hall := h.2
  have hr := List.all_eq_true.mp hall ev (required_contains lo hi)
  cases he : receipts ev with
  | none => simp [oneReceipt, he] at hr
  | some r => exact ⟨r, rfl, by simpa [oneReceipt, he] using hr⟩
theorem proposal_sound (h : propose p now receipts codex agy = some out) :
    eligible p now receipts codex agy = true ∧ out.candidate = p := by
  unfold propose at h
  split at h
  · cases h; exact ⟨by assumption, rfl⟩
  · cases h
theorem proposal_all_intermediates (h : propose p now receipts codex agy = some out)
    (lo : 94 ≤ ev) (hi : ev ≤ p.target) :
    ∃ r, receipts ev = some r ∧ receiptValid p now ev r = true :=
  eligible_every_intermediate (proposal_sound h).1 lo hi
theorem proposal_never_admits (out : Proposal) :
    out.canonicalCeiling = 93 ∧ out.historicalStatus = .notAdmitted := ⟨rfl, rfl⟩

theorem aliased_clock_rejected (p : Candidate) (now : UTC) (ev : Nat) (r : Receipt)
    (he : r.clock.utc.raw = r.clock.mono.raw) : receiptValid p now ev r = false := by
  cases h1 : r.runtimeKey <;> cases h2 : r.formalKey <;> simp [receiptValid, h1, h2, he]
theorem missing_runtime_key_rejected (h : r.runtimeKey = none) :
    receiptValid p now ev r = false := by simp [receiptValid, h]
theorem missing_formal_key_rejected (h : r.formalKey = none) :
    receiptValid p now ev r = false := by cases h1 : r.runtimeKey <;> simp [receiptValid, h1, h]
theorem stale_receipt_rejected (h : r.expires.raw ≤ now.raw) :
    receiptValid p now ev r = false := by
  have hf : fresh now r.observed r.expires = false := by simp [fresh]; omega
  cases h1 : r.runtimeKey <;> cases h2 : r.formalKey <;> simp [receiptValid, h1, h2, hf]
/- Negative/superseded opinions remain meaningful lattice information, but
cannot satisfy positive contiguous-range readiness. Even rebind needs ALL keys
and joint review: the opinion is not a verified native observation. -/
theorem non_rebind_rejected (h : r.information ≠ .rebind) :
    receiptValid p now ev r = false := by
  cases h1 : r.runtimeKey <;> cases h2 : r.formalKey <;> simp [receiptValid, h1, h2, h]

/-! Genuine abstract positive and negative controls. No corresponding native
receipts are asserted to exist. Digest/source IDs are uninterpreted identifiers;
the provenance, signature and clock-oracle claims remain explicit premises. -/
def demoCandidate : Candidate := ⟨101, 202, 95⟩
def demoNow : UTC := ⟨5⟩
def demoKey (signer : Nat) : Key := ⟨101, 202, signer, true, true, true⟩
def demoReceipt (ev : Nat) : Receipt :=
  ⟨ev, some (demoKey 1), some (demoKey 2), ⟨⟨5⟩, ⟨7⟩⟩, ⟨5⟩, ⟨10⟩, .rebind⟩
def demoReceipts (ev : Nat) : Option Receipt :=
  if ev = 94 ∨ ev = 95 then some (demoReceipt ev) else none
def demoReview (who : Reviewer) (signer : Nat) : Review :=
  ⟨101, 202, 95, who, signer, true, true, true, ⟨5⟩, ⟨10⟩⟩
def demoCodex := demoReview .codex 10
def demoAgy := demoReview .agy 11
theorem positive_eligible_proposal :
    eligible demoCandidate demoNow demoReceipts demoCodex demoAgy = true := by decide
example : (propose demoCandidate demoNow demoReceipts demoCodex demoAgy).isSome = true := by decide
example : initial.ceiling = 93 := rfl
example : eligible demoCandidate demoNow
    (fun ev => if ev = 95 then some (demoReceipt ev) else none) demoCodex demoAgy = false := by decide
example : eligible demoCandidate demoNow demoReceipts
    {demoCodex with signed := false} demoAgy = false := by decide
example : eligible demoCandidate demoNow demoReceipts demoCodex
    {demoAgy with recorded := false} = false := by decide
example : eligible demoCandidate demoNow
    (fun ev => some {demoReceipt ev with formalKey := some {demoKey 2 with candidate := 999}})
    demoCodex demoAgy = false := by decide
example : eligible demoCandidate demoNow
    (fun ev => some {demoReceipt ev with formalKey := none}) demoCodex demoAgy = false := by decide
example : eligible demoCandidate demoNow
    (fun ev => some {demoReceipt ev with expires := ⟨5⟩}) demoCodex demoAgy = false := by decide
example : eligible demoCandidate demoNow
    (fun ev => some {demoReceipt ev with clock := ⟨⟨5⟩, ⟨5⟩⟩}) demoCodex demoAgy = false := by decide
example : eligible {demoCandidate with target := 93} demoNow demoReceipts demoCodex demoAgy = false := by decide
example : eligible {demoCandidate with target := 110} demoNow demoReceipts demoCodex demoAgy = false := by decide
example : eligible demoCandidate demoNow
    (fun ev => some {demoReceipt ev with information := .conflict}) demoCodex demoAgy = false := by decide
example : eligible demoCandidate demoNow
    (fun ev => some {demoReceipt ev with information := .pending}) demoCodex demoAgy = false := by decide
example : eligible demoCandidate demoNow
    (fun ev => some {demoReceipt ev with information := .rejected}) demoCodex demoAgy = false := by decide
example : eligible demoCandidate demoNow
    (fun ev => some {demoReceipt ev with information := .superseded}) demoCodex demoAgy = false := by decide
example : eligible demoCandidate demoNow
    (fun ev => some {demoReceipt ev with runtimeKey := some {demoKey 1 with signed := false}})
    demoCodex demoAgy = false := by decide
example : eligible demoCandidate demoNow
    (fun ev => some {demoReceipt ev with formalKey := some {demoKey 2 with originVerified := false}})
    demoCodex demoAgy = false := by decide
example : eligible demoCandidate demoNow
    (fun ev => some {demoReceipt ev with runtimeKey := some {demoKey 1 with source := 999}})
    demoCodex demoAgy = false := by decide
example : eligible demoCandidate demoNow
    (fun ev => some {demoReceipt ev with formalKey := some (demoKey 1)}) demoCodex demoAgy = false := by decide
example : eligible demoCandidate demoNow demoReceipts demoCodex
    {demoAgy with signer := 10} = false := by decide
example : eligible demoCandidate demoNow demoReceipts demoCodex
    {demoAgy with reviewer := .other} = false := by decide
example : (propose demoCandidate demoNow demoReceipts demoCodex demoAgy).map
    (fun p => p.candidate.target) = some 95 := rfl
example : (propose demoCandidate demoNow demoReceipts demoCodex demoAgy).map
    Proposal.canonicalCeiling = some 93 := rfl
end Gateway

end ProvenanceAdjudication
