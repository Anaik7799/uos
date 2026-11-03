import Std

/-!
Bounded development schema for the content of an SC-JOURNAL-v3 completion
journal.  This is distinct from `UOS.AgenticJournal`, which models durable
coordinator operations (claims, ACKs, recovery, leases and effects), not the
thirteen-section journal content contract.

The schema below captures section/engine ordering, typed scope and provenance,
an admissibility condition for passing evidence, and basic forecast/Brier
well-formedness.  It does NOT establish actual source reliability, full journal
correctness, parser/linter equivalence, numerical calibration, hypothesis truth,
Lyapunov stability, real control, or live enforcement.  UNKNOWN is a first-class
value; this model does not synthesize missing observations. Candidate revisions,
scopes and second-count timestamps are supplied, unauthenticated data; the model
does not parse ISO-8601 or authenticate a host clock. Section-specific content
obligations such as ACH matrix depth, diagram topology, STPA UCA coverage,
Bayesian calculations, Lyapunov derivatives, redaction and linter behavior
remain UNMODELED. Evidence scope here is only `SectionId`, not Sa-plan task scope;
candidate IDs and timestamps are caller-supplied. A supplied observation time is
not authenticated and does not prove freshness. Verified engines are required to
have nonempty, resolvable evidence references, but the schema does not require
those referenced records to be passing/admissible or prove that an engine ran.
The predicates below check structural consistency of supplied values, not
empirical authenticity, observation truth, or full SC-JOURNAL-v3 compliance.
-/

namespace UOS.SCJournalV3Model

inductive SectionId where
  | scopeTrigger
  | preStateAssessment
  | executionDetail
  | rootCauseAnalysis
  | fixTaxonomy
  | patternsAndAntiPatterns
  | verificationMatrix
  | filesModified
  | architecturalObservations
  | remainingGaps
  | metricsSummary
  | stampConstitutionalAlignment
  | conclusion
deriving DecidableEq, Repr

def canonicalSections : List SectionId := [
  SectionId.scopeTrigger,
  SectionId.preStateAssessment,
  SectionId.executionDetail,
  SectionId.rootCauseAnalysis,
  SectionId.fixTaxonomy,
  SectionId.patternsAndAntiPatterns,
  SectionId.verificationMatrix,
  SectionId.filesModified,
  SectionId.architecturalObservations,
  SectionId.remainingGaps,
  SectionId.metricsSummary,
  SectionId.stampConstitutionalAlignment,
  SectionId.conclusion
]

inductive EngineId where
  | achDisconfirmation
  | admiraltyEvidence
  | bayesianDecay
  | devilsAdvocate
  | formalGateways
  | reteInvariantRules
  | predictiveForecasting
deriving DecidableEq, Repr

def canonicalEngines : List EngineId := [
  EngineId.achDisconfirmation,
  EngineId.admiraltyEvidence,
  EngineId.bayesianDecay,
  EngineId.devilsAdvocate,
  EngineId.formalGateways,
  EngineId.reteInvariantRules,
  EngineId.predictiveForecasting
]

/-! Section-to-engine focus follows the contract:
1→5, 2→7, 3→6, 4→1, 5→6, 6→4, 7→2, 8→6, 9→5, 10→4,
11→3, 12→6, 13→7.  A focus mapping is a schema label, not proof that an
engine ran or that its output is correct.
-/
def primaryEngine : SectionId → EngineId
  | .scopeTrigger => .formalGateways
  | .preStateAssessment => .predictiveForecasting
  | .executionDetail => .reteInvariantRules
  | .rootCauseAnalysis => .achDisconfirmation
  | .fixTaxonomy => .reteInvariantRules
  | .patternsAndAntiPatterns => .devilsAdvocate
  | .verificationMatrix => .admiraltyEvidence
  | .filesModified => .reteInvariantRules
  | .architecturalObservations => .formalGateways
  | .remainingGaps => .devilsAdvocate
  | .metricsSummary => .bayesianDecay
  | .stampConstitutionalAlignment => .reteInvariantRules
  | .conclusion => .predictiveForecasting

inductive RecordStatus where
  | unknown
  | draft (content : String)
  | recorded (content : String)
deriving DecidableEq, Repr

structure SectionRecord where
  sectionId : SectionId
  status : RecordStatus
deriving DecidableEq, Repr

inductive EngineStatus where
  | unknown
  | notRun
  | ranUnverified
  | verified
deriving DecidableEq, Repr

structure EngineRecord where
  engine : EngineId
  status : EngineStatus
  evidenceRefs : List Nat
deriving Repr

inductive EvidenceStatus where
  | unknown
  | unrun
  | stale
  | quarantined
  | excluded
  | failed
  | passed
  | verified
deriving DecidableEq, Repr

def IsPassing : EvidenceStatus → Prop
  | .passed => True
  | .verified => True
  | _ => False

inductive SourceReliability where
  | A | B | C | D | E | F
deriving DecidableEq, Repr

inductive InformationCredibility where
  | one | two | three | four | five | six
deriving DecidableEq, Repr

structure AdmiraltyGrade where
  source : SourceReliability
  information : InformationCredibility
deriving DecidableEq, Repr

def AdmissibleGrade (grade : AdmiraltyGrade) : Prop :=
  (grade.source = .A ∨ grade.source = .B) ∧
  (grade.information = .one ∨ grade.information = .two)

inductive Provenance where
  | observedRuntime
  | machineReceipt
  | formalArtifact
  | modelSelfAttestation
  | historicalRecord
  | unknownSource
deriving DecidableEq, Repr

structure EvidenceRecord where
  id : Nat
  scope : SectionId
  candidateRevision : Option Nat
  observedAtSeconds : Option Nat
  status : EvidenceStatus
  provenance : Provenance
  grade : Option AdmiraltyGrade
deriving Repr

def PassingEvidenceAdmissible (e : EvidenceRecord) : Prop :=
  IsPassing e.status →
    e.observedAtSeconds.isSome = true ∧
    e.provenance ≠ .modelSelfAttestation ∧
    e.provenance ≠ .unknownSource ∧
    ∃ grade, e.grade = some grade ∧ AdmissibleGrade grade

theorem unknown_is_never_passing : ¬ IsPassing .unknown := by
  simp [IsPassing]

theorem unrun_is_never_passing : ¬ IsPassing .unrun := by
  simp [IsPassing]

theorem stale_is_never_passing : ¬ IsPassing .stale := by
  simp [IsPassing]

theorem quarantined_is_never_passing : ¬ IsPassing .quarantined := by
  simp [IsPassing]

theorem excluded_is_never_passing : ¬ IsPassing .excluded := by
  simp [IsPassing]

theorem failed_is_never_passing : ¬ IsPassing .failed := by
  simp [IsPassing]

theorem passing_evidence_requires_admissible_grade (e : EvidenceRecord)
    (valid : PassingEvidenceAdmissible e) (passing : IsPassing e.status) :
    ∃ grade, e.grade = some grade ∧ AdmissibleGrade grade :=
  (valid passing).2.2.2

structure Probability where
  numerator : Nat
  denominator : Nat
  denominatorPositive : 0 < denominator
  numeratorAtMostDenominator : numerator ≤ denominator
deriving Repr

def ProbabilityInUnitInterval (p : Probability) : Prop :=
  p.numerator ≤ p.denominator ∧ 0 < p.denominator

theorem every_probability_is_in_unit_interval (p : Probability) :
    ProbabilityInUnitInterval p :=
  ⟨p.numeratorAtMostDenominator, p.denominatorPositive⟩

structure Forecast where
  probability : Probability
  falsificationCriterion : Option String
  precommittedAtSeconds : Option Nat
  horizonSeconds : Nat
  observation : Option Bool
  observedAtSeconds : Option Nat
deriving Repr

def brierNumerator (p : Probability) (outcome : Bool) : Nat :=
  if outcome then
    (p.denominator - p.numerator) * (p.denominator - p.numerator)
  else p.numerator * p.numerator

def brierDenominator (p : Probability) : Nat :=
  p.denominator * p.denominator

def resolvedBrier (forecast : Forecast) : Option (Nat × Nat) :=
  match forecast.observation, forecast.precommittedAtSeconds,
      forecast.observedAtSeconds with
  | some outcome, some precommittedAt, some observedAt =>
      if precommittedAt < forecast.horizonSeconds ∧
          precommittedAt ≤ observedAt ∧ forecast.horizonSeconds ≤ observedAt then
        some (brierNumerator forecast.probability outcome,
              brierDenominator forecast.probability)
      else none
  | _, _, _ => none

theorem no_brier_before_observation (forecast : Forecast)
    (unobserved : forecast.observation = none) :
    resolvedBrier forecast = none := by
  simp [resolvedBrier, unobserved]

theorem no_brier_before_horizon (forecast : Forecast) (observedAt : Nat)
    (observationTime : forecast.observedAtSeconds = some observedAt)
    (beforeHorizon : observedAt < forecast.horizonSeconds) :
    resolvedBrier forecast = none := by
  cases outcome : forecast.observation with
  | none => simp [resolvedBrier, outcome]
  | some outcome =>
      cases precommit : forecast.precommittedAtSeconds with
      | none => simp [resolvedBrier, outcome, precommit]
      | some precommitAt =>
          simp [resolvedBrier, outcome, precommit, observationTime]
          omega

theorem no_brier_if_precommit_is_at_or_after_horizon (forecast : Forecast)
    (precommittedAt : Nat)
    (precommitTime : forecast.precommittedAtSeconds = some precommittedAt)
    (invalidOrder : forecast.horizonSeconds ≤ precommittedAt) :
    resolvedBrier forecast = none := by
  cases outcome : forecast.observation with
  | none => simp [resolvedBrier, outcome]
  | some outcome =>
      cases observedAt : forecast.observedAtSeconds with
      | none => simp [resolvedBrier, outcome, observedAt]
      | some observedAt =>
          have noPrecommitBeforeHorizon :
              ¬ precommittedAt < forecast.horizonSeconds := by omega
          simp [resolvedBrier, outcome, precommitTime, observedAt,
            noPrecommitBeforeHorizon]

theorem brier_result_requires_observation (forecast : Forecast)
    (hasResult : ∃ score, resolvedBrier forecast = some score) :
    ∃ outcome, forecast.observation = some outcome := by
  rcases hasResult with ⟨score, result⟩
  cases observed : forecast.observation with
  | none => simp [resolvedBrier, observed] at result
  | some outcome => exact ⟨outcome, rfl⟩

structure Journal where
  sections : List SectionRecord
  engines : List EngineRecord
  evidence : List EvidenceRecord
  forecast : Forecast
  candidateRevision : Option Nat
  scopeLabel : Option String
  clockSeconds : Option Nat

def SectionOrderCorrect (journal : Journal) : Prop :=
  journal.sections.map SectionRecord.sectionId = canonicalSections

def EngineOrderCorrect (journal : Journal) : Prop :=
  journal.engines.map EngineRecord.engine = canonicalEngines

def VerifiedEngineHasEvidenceReferences (engine : EngineRecord) : Prop :=
  engine.status = .verified → engine.evidenceRefs ≠ []

def EvidenceObservationsNotAfterJournalClock (journal : Journal) : Prop :=
  ∀ evidence ∈ journal.evidence, ∀ observedAt,
    evidence.observedAtSeconds = some observedAt →
      ∃ clock, journal.clockSeconds = some clock ∧ observedAt ≤ clock

/-! This predicate checks only the fields named below. It does not assert that
section contents are complete, engines ran, evidence is true/reliable, or the
full external contract was satisfied. -/
structure JournalSchemaValid (journal : Journal) : Prop where
  sectionsOrdered : SectionOrderCorrect journal
  enginesOrdered : EngineOrderCorrect journal
  sectionEngineCoverage :
    ∀ sectionRecord ∈ journal.sections,
      primaryEngine sectionRecord.sectionId ∈ journal.engines.map EngineRecord.engine
  evidenceCandidateBound :
    ∀ evidence ∈ journal.evidence,
      evidence.candidateRevision = journal.candidateRevision
  evidenceScopeBound :
    ∀ evidence ∈ journal.evidence,
      evidence.scope ∈ journal.sections.map SectionRecord.sectionId
  engineEvidenceRefsBound :
    ∀ engine ∈ journal.engines, ∀ evidenceId ∈ engine.evidenceRefs,
      ∃ evidence ∈ journal.evidence, evidence.id = evidenceId
  verifiedEnginesHaveEvidenceRefs :
    ∀ engine ∈ journal.engines, VerifiedEngineHasEvidenceReferences engine
  passingEvidenceAdmissible :
    ∀ evidence ∈ journal.evidence, PassingEvidenceAdmissible evidence
  evidenceIdsUnique : (journal.evidence.map EvidenceRecord.id).Nodup
  evidenceNotLaterThanJournalClock : EvidenceObservationsNotAfterJournalClock journal
  forecastCriterionPresent : journal.forecast.falsificationCriterion.isSome = true
  forecastPrecommitted : journal.forecast.precommittedAtSeconds.isSome = true
  forecastHorizonAfterPrecommit :
    journal.forecast.precommittedAtSeconds.getD 0 < journal.forecast.horizonSeconds
  candidateBound : journal.candidateRevision.isSome = true
  scopePresent : journal.scopeLabel.isSome = true
  timestamped : journal.clockSeconds.isSome = true
  probabilityBounded : ProbabilityInUnitInterval journal.forecast.probability

theorem valid_journal_has_all_ordered_sections (journal : Journal)
    (valid : JournalSchemaValid journal) :
    SectionOrderCorrect journal := valid.sectionsOrdered

theorem valid_journal_has_all_ordered_engines (journal : Journal)
    (valid : JournalSchemaValid journal) :
    EngineOrderCorrect journal := valid.enginesOrdered

theorem primary_engine_is_in_canonical_engine_set (sectionId : SectionId) :
    primaryEngine sectionId ∈ canonicalEngines := by
  cases sectionId <;> simp [primaryEngine, canonicalEngines]

theorem valid_journal_section_engine_coverage (journal : Journal)
    (valid : JournalSchemaValid journal) :
    ∀ sectionRecord ∈ journal.sections,
      primaryEngine sectionRecord.sectionId ∈ journal.engines.map EngineRecord.engine :=
  valid.sectionEngineCoverage

theorem valid_journal_evidence_is_candidate_bound (journal : Journal)
    (valid : JournalSchemaValid journal) :
    ∀ evidence ∈ journal.evidence,
      evidence.candidateRevision = journal.candidateRevision :=
  valid.evidenceCandidateBound

theorem valid_journal_evidence_scope_is_present (journal : Journal)
    (valid : JournalSchemaValid journal) :
    ∀ evidence ∈ journal.evidence,
      evidence.scope ∈ journal.sections.map SectionRecord.sectionId :=
  valid.evidenceScopeBound

theorem valid_journal_engine_evidence_refs_exist (journal : Journal)
    (valid : JournalSchemaValid journal) :
    ∀ engine ∈ journal.engines, ∀ evidenceId ∈ engine.evidenceRefs,
      ∃ evidence ∈ journal.evidence, evidence.id = evidenceId :=
  valid.engineEvidenceRefsBound

theorem valid_journal_verified_engines_have_evidence_refs (journal : Journal)
    (valid : JournalSchemaValid journal) :
    ∀ engine ∈ journal.engines, VerifiedEngineHasEvidenceReferences engine :=
  valid.verifiedEnginesHaveEvidenceRefs

theorem valid_journal_evidence_ids_are_unique (journal : Journal)
    (valid : JournalSchemaValid journal) :
    (journal.evidence.map EvidenceRecord.id).Nodup :=
  valid.evidenceIdsUnique

theorem valid_journal_evidence_observations_do_not_exceed_clock
    (journal : Journal) (valid : JournalSchemaValid journal) :
    EvidenceObservationsNotAfterJournalClock journal :=
  valid.evidenceNotLaterThanJournalClock

theorem valid_journal_forecast_probability_is_bounded (journal : Journal)
    (valid : JournalSchemaValid journal) :
    ProbabilityInUnitInterval journal.forecast.probability := valid.probabilityBounded

def exampleEvidence : EvidenceRecord := {
  id := 1
  scope := .verificationMatrix
  candidateRevision := some 1
  observedAtSeconds := some 2
  status := .passed
  provenance := .machineReceipt
  grade := some ⟨.B, .two⟩
}

def unknownExampleForecast : Forecast := {
  probability := ⟨3, 4, by decide, by decide⟩
  falsificationCriterion := some "Resolve the named check by its recorded horizon"
  precommittedAtSeconds := some 1
  horizonSeconds := 3600
  observation := none
  observedAtSeconds := none
}

def resolvedExampleForecast : Forecast := {
  probability := ⟨3, 4, by decide, by decide⟩
  falsificationCriterion := some "Observed outcome at or after the declared horizon"
  precommittedAtSeconds := some 1
  horizonSeconds := 3600
  observation := some true
  observedAtSeconds := some 3600
}

def invalidPostHorizonPrecommitForecast : Forecast := {
  resolvedExampleForecast with
  precommittedAtSeconds := some 3600
}

theorem resolved_example_forecast_has_brier_1_over_16 :
    resolvedBrier resolvedExampleForecast = some (1, 16) := by
  decide

theorem post_horizon_precommit_example_has_no_brier :
    resolvedBrier invalidPostHorizonPrecommitForecast = none := by
  decide

def exampleJournal : Journal := {
  sections := [
    ⟨SectionId.scopeTrigger, .recorded "bounded development example"⟩,
    ⟨SectionId.preStateAssessment, .unknown⟩,
    ⟨SectionId.executionDetail, .recorded "schema demonstration only"⟩,
    ⟨SectionId.rootCauseAnalysis, .unknown⟩,
    ⟨SectionId.fixTaxonomy, .unknown⟩,
    ⟨SectionId.patternsAndAntiPatterns, .unknown⟩,
    ⟨SectionId.verificationMatrix, .recorded "one typed sample receipt"⟩,
    ⟨SectionId.filesModified, .unknown⟩,
    ⟨SectionId.architecturalObservations, .unknown⟩,
    ⟨SectionId.remainingGaps, .unknown⟩,
    ⟨SectionId.metricsSummary, .unknown⟩,
    ⟨SectionId.stampConstitutionalAlignment, .unknown⟩,
    ⟨SectionId.conclusion, .recorded "Forecast remains unresolved"⟩
  ]
  engines := [
    ⟨EngineId.achDisconfirmation, .unknown, []⟩,
    ⟨EngineId.admiraltyEvidence, .ranUnverified, [1]⟩,
    ⟨EngineId.bayesianDecay, .unknown, []⟩,
    ⟨EngineId.devilsAdvocate, .unknown, []⟩,
    ⟨EngineId.formalGateways, .unknown, []⟩,
    ⟨EngineId.reteInvariantRules, .unknown, []⟩,
    ⟨EngineId.predictiveForecasting, .ranUnverified, []⟩
  ]
  evidence := [exampleEvidence]
  forecast := unknownExampleForecast
  candidateRevision := some 1
  scopeLabel := some "abstract SC-JOURNAL-v3 schema example"
  clockSeconds := some 2
}

theorem example_journal_is_schema_valid : JournalSchemaValid exampleJournal := by
  refine {
    sectionsOrdered := rfl
    enginesOrdered := rfl
    sectionEngineCoverage := by
      intro sectionRecord _
      rw [show exampleJournal.engines.map EngineRecord.engine = canonicalEngines by rfl]
      exact primary_engine_is_in_canonical_engine_set sectionRecord.sectionId
    evidenceCandidateBound := ?_
    evidenceScopeBound := ?_
    engineEvidenceRefsBound := ?_
    verifiedEnginesHaveEvidenceRefs := ?_
    passingEvidenceAdmissible := ?_
    evidenceIdsUnique := by simp [exampleJournal, exampleEvidence]
    evidenceNotLaterThanJournalClock := ?_
    forecastCriterionPresent := rfl
    forecastPrecommitted := rfl
    forecastHorizonAfterPrecommit := by decide
    candidateBound := rfl
    scopePresent := rfl
    timestamped := rfl
    probabilityBounded := every_probability_is_in_unit_interval _
  }
  · intro evidence member
    simp only [exampleJournal, List.mem_singleton] at member
    subst evidence
    rfl
  · intro evidence member
    simp only [exampleJournal, List.mem_singleton] at member
    subst evidence
    simp [exampleJournal, exampleEvidence]
  · intro engine member evidenceId idMember
    simp [exampleJournal] at member
    rcases member with h | h | h | h | h | h | h
    · subst engine; simp at idMember
    · subst engine
      simp at idMember
      subst evidenceId
      exact ⟨exampleEvidence, by simp [exampleJournal], by rfl⟩
    · subst engine; simp at idMember
    · subst engine; simp at idMember
    · subst engine; simp at idMember
    · subst engine; simp at idMember
    · subst engine; simp at idMember
  · intro engine member
    simp [exampleJournal] at member
    rcases member with h | h | h | h | h | h | h <;>
      subst engine <;> simp [VerifiedEngineHasEvidenceReferences]
  · intro evidence member
    simp only [exampleJournal, List.mem_singleton] at member
    subst evidence
    simp [PassingEvidenceAdmissible, exampleEvidence, IsPassing, AdmissibleGrade]
  · intro evidence member observedAt observationTime
    simp only [exampleJournal, List.mem_singleton] at member
    subst evidence
    simp [exampleEvidence] at observationTime
    subst observedAt
    exact ⟨2, rfl, by decide⟩

def invalidPassingEvidence : EvidenceRecord := {
  id := 2
  scope := .verificationMatrix
  candidateRevision := some 1
  observedAtSeconds := some 2
  status := .passed
  provenance := .observedRuntime
  grade := some ⟨.E, .three⟩
}

theorem low_grade_passing_evidence_is_rejected :
    ¬ PassingEvidenceAdmissible invalidPassingEvidence := by
  intro valid
  have required := valid trivial
  rcases required.2.2.2 with ⟨grade, gradeEq, admissible⟩
  simp [invalidPassingEvidence] at gradeEq
  subst grade
  simp [AdmissibleGrade] at admissible

def falseHighGradeSelfAttestation : EvidenceRecord := {
  id := 3
  scope := .verificationMatrix
  candidateRevision := some 1
  observedAtSeconds := some 2
  status := .verified
  provenance := .modelSelfAttestation
  grade := some ⟨.B, .two⟩
}

theorem self_attestation_cannot_certify_passing :
    ¬ PassingEvidenceAdmissible falseHighGradeSelfAttestation := by
  intro valid
  have requirements := valid trivial
  exact requirements.2.1 rfl

def passingEvidenceWithoutObservationTime : EvidenceRecord := {
  exampleEvidence with
  id := 5
  observedAtSeconds := none
}

theorem passing_evidence_without_observation_time_is_rejected :
    ¬ PassingEvidenceAdmissible passingEvidenceWithoutObservationTime := by
  intro admissible
  have observedTimeRequired := admissible trivial
  simp [passingEvidenceWithoutObservationTime, exampleEvidence] at observedTimeRequired

def unknownSourcePassingEvidence : EvidenceRecord := {
  exampleEvidence with
  id := 4
  provenance := .unknownSource
}

theorem machine_receipt_passing_evidence_is_structurally_allowed :
    PassingEvidenceAdmissible exampleEvidence := by
  intro _
  simp [exampleEvidence, AdmissibleGrade]

theorem unknown_source_passing_evidence_is_rejected :
    ¬ PassingEvidenceAdmissible unknownSourcePassingEvidence := by
  intro admissible
  have constraints := admissible trivial
  exact constraints.2.2.1 rfl

def verifiedEngineWithReference : EngineRecord := {
  engine := .admiraltyEvidence
  status := .verified
  evidenceRefs := [1]
}

theorem verified_engine_with_reference_satisfies_guard :
    VerifiedEngineHasEvidenceReferences verifiedEngineWithReference := by
  intro _
  simp [verifiedEngineWithReference]

def verifiedEngineWithoutReference : EngineRecord := {
  engine := .admiraltyEvidence
  status := .verified
  evidenceRefs := []
}

theorem verified_engine_without_reference_is_rejected :
    ¬ VerifiedEngineHasEvidenceReferences verifiedEngineWithoutReference := by
  simp [VerifiedEngineHasEvidenceReferences, verifiedEngineWithoutReference]

def invalidExampleJournal : Journal := {
  exampleJournal with
  evidence := [invalidPassingEvidence]
}

theorem invalid_example_journal_fails_selected_schema_checks :
    ¬ JournalSchemaValid invalidExampleJournal := by
  intro valid
  have evidenceCheck := valid.passingEvidenceAdmissible
    invalidPassingEvidence (by simp [invalidExampleJournal])
  exact low_grade_passing_evidence_is_rejected evidenceCheck

def duplicateEvidenceJournal : Journal := {
  exampleJournal with
  evidence := [exampleEvidence, { exampleEvidence with status := .verified }]
}

theorem duplicate_evidence_ids_fail_journal_schema :
    ¬ JournalSchemaValid duplicateEvidenceJournal := by
  intro valid
  have idsUnique := valid.evidenceIdsUnique
  simp [duplicateEvidenceJournal, exampleJournal, exampleEvidence] at idsUnique

def futureDatedEvidence : EvidenceRecord := {
  exampleEvidence with
  observedAtSeconds := some 3
}

def futureDatedJournal : Journal := {
  exampleJournal with
  evidence := [futureDatedEvidence]
}

theorem example_journal_evidence_time_is_bounded :
    EvidenceObservationsNotAfterJournalClock exampleJournal := by
  exact (example_journal_is_schema_valid.evidenceNotLaterThanJournalClock)

theorem evidence_observation_after_journal_clock_fails_schema :
    ¬ JournalSchemaValid futureDatedJournal := by
  intro valid
  have timeBound := valid.evidenceNotLaterThanJournalClock
    futureDatedEvidence (by simp [futureDatedJournal]) 3 rfl
  rcases timeBound with ⟨clock, clockIsJournalTime, observedBeforeClock⟩
  simp [futureDatedJournal, exampleJournal] at clockIsJournalTime
  subst clock
  omega

theorem example_forecast_has_no_brier_before_observation :
    resolvedBrier exampleJournal.forecast = none := by
  apply no_brier_before_observation
  rfl

#print axioms unknown_is_never_passing
#print axioms unrun_is_never_passing
#print axioms stale_is_never_passing
#print axioms quarantined_is_never_passing
#print axioms excluded_is_never_passing
#print axioms failed_is_never_passing
#print axioms passing_evidence_requires_admissible_grade
#print axioms every_probability_is_in_unit_interval
#print axioms no_brier_before_observation
#print axioms no_brier_before_horizon
#print axioms no_brier_if_precommit_is_at_or_after_horizon
#print axioms brier_result_requires_observation
#print axioms resolved_example_forecast_has_brier_1_over_16
#print axioms post_horizon_precommit_example_has_no_brier
#print axioms valid_journal_has_all_ordered_sections
#print axioms valid_journal_has_all_ordered_engines
#print axioms primary_engine_is_in_canonical_engine_set
#print axioms valid_journal_section_engine_coverage
#print axioms valid_journal_evidence_is_candidate_bound
#print axioms valid_journal_evidence_scope_is_present
#print axioms valid_journal_engine_evidence_refs_exist
#print axioms valid_journal_verified_engines_have_evidence_refs
#print axioms valid_journal_evidence_ids_are_unique
#print axioms valid_journal_evidence_observations_do_not_exceed_clock
#print axioms valid_journal_forecast_probability_is_bounded
#print axioms example_journal_is_schema_valid
#print axioms low_grade_passing_evidence_is_rejected
#print axioms self_attestation_cannot_certify_passing
#print axioms invalid_example_journal_fails_selected_schema_checks
#print axioms example_forecast_has_no_brier_before_observation
#print axioms machine_receipt_passing_evidence_is_structurally_allowed
#print axioms unknown_source_passing_evidence_is_rejected
#print axioms passing_evidence_without_observation_time_is_rejected
#print axioms verified_engine_with_reference_satisfies_guard
#print axioms verified_engine_without_reference_is_rejected
#print axioms duplicate_evidence_ids_fail_journal_schema
#print axioms example_journal_evidence_time_is_bounded
#print axioms evidence_observation_after_journal_clock_fails_schema

end UOS.SCJournalV3Model
