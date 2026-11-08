/-!
  FormalModelEvaluationSuite.lean
  =============================================================================
  Canonical Reusable Formal Specification & Algebraic Verification Library
  for Local & Remote LLM Serving, Parameter Optimization & Dual-Plane Telemetry.

  Authority: NONE (EV ceiling 93, EV-94..109 NOT_ADMITTED, SC-PROVENANCE-001)
  Safety   : HARD_DENIED_SYSTEM_OS_SERIAL = "25503L801736"
  Architecture:
    - Pure Lean 4 algebra: Decidable types, strict bounded bounds, objective functions.
    - Zero IO, zero sockets, zero side effects (all empirical observation in Mojo).
    - 0 sorry, 0 Admitted, 0 axioms.
  =============================================================================
-/

namespace UOS.ModelEvaluation

/-- Admitted EV ceiling per SC-PROVENANCE-001 -/
def admittedEvCeiling : Nat := 93

/-- System OS NVMe serial lock to prevent storage mutation -/
def hardDeniedSystemOsSerial : String := "25503L801736"

/-! ### 1. Model Deployment Target & Hardware Boundary -/

inductive ModelTargetType where
  | localGpuCuda        -- Local NVIDIA Turing sm_75 / Ampere / etc.
  | localCpuAvx         -- Local AVX2 / AVX-512 CPU execution
  | remoteTailnetPeer   -- Tailnet peer worker (e.g. vm-1, razr15-1)
  | remoteGatewayApi    -- Remote API gateway (OpenRouter, Anthropic, Gemini)
deriving DecidableEq, Repr

structure ModelEndpointSpec where
  targetType      : ModelTargetType
  endpointFqdn    : String
  port            : Nat
  modelId         : String
  contextPhysical : Nat  -- Physical context window supported by server
  contextClient   : Nat  -- Client-configured context window limit
  maxTokens       : Nat  -- Safe generation budget
  deriving DecidableEq, Repr

/-- Invariant: client contextWindow must NEVER exceed physical backend contextWindow -/
def isContextWindowSafe (spec : ModelEndpointSpec) : Bool :=
  spec.contextClient ≤ spec.contextPhysical ∧
  spec.maxTokens ≤ spec.contextClient ∧
  spec.maxTokens > 0

/-! ### 2. Parameter Tuning Space & Generation Hyperparameters -/

structure TuningHyperparameters where
  temperature       : Nat   -- Scaled by 100 (e.g. 20 => 0.20, 80 => 0.80)
  topP              : Nat   -- Scaled by 100 (e.g. 90 => 0.90, 95 => 0.95)
  topK              : Nat   -- Integer K (e.g. 40)
  repeatPenalty     : Nat   -- Scaled by 100 (e.g. 100 => 1.00, 110 => 1.10)
  presencePenalty   : Nat   -- Scaled by 100
  frequencyPenalty  : Nat   -- Scaled by 100
  deriving DecidableEq, Repr

/-- Invariant bounds for deterministic vs exploratory generation -/
def isHyperparameterValid (p : TuningHyperparameters) : Bool :=
  p.temperature ≤ 200 ∧
  p.topP ≤ 100 ∧ p.topP > 0 ∧
  p.topK ≤ 100 ∧
  p.repeatPenalty ≥ 100 ∧ p.repeatPenalty ≤ 200

/-- Standard Deterministic Code Profile (optimal for Lean, Gleam, OCaml, Mojo syntax) -/
def deterministicCodeProfile : TuningHyperparameters := {
  temperature      := 20,  -- 0.20
  topP             := 90,  -- 0.90
  topK             := 40,
  repeatPenalty    := 105, -- 1.05
  presencePenalty  := 0,
  frequencyPenalty := 0
}

/-- Standard Mathematical / Formal Proof Profile (strictly greedy/minimal entropy) -/
def formalProofProfile : TuningHyperparameters := {
  temperature      := 0,   -- 0.00
  topP             := 95,  -- 0.95
  topK             := 20,
  repeatPenalty    := 100, -- 1.00
  presencePenalty  := 0,
  frequencyPenalty := 0
}

/-- Standard Exploratory Synthesis Profile -/
def exploratoryProfile : TuningHyperparameters := {
  temperature      := 70,  -- 0.70
  topP             := 95,  -- 0.95
  topK             := 50,
  repeatPenalty    := 110, -- 1.10
  presencePenalty  := 10,
  frequencyPenalty := 10
}

/-! ### 3. Objective Scoring Function & Utility Formulation -/

/-- Weights for multi-criteria optimization:
    Speed (prompt + gen throughput), Latency (TTFT), Syntactic Validity, Token Cost.
    Weights sum to 100. -/
structure ObjectiveWeights where
  throughputWeight : Nat := 35
  latencyWeight    : Nat := 25
  syntaxWeight     : Nat := 30
  costWeight       : Nat := 10
  deriving DecidableEq, Repr

def ObjectiveWeights.isValid (w : ObjectiveWeights) : Bool :=
  w.throughputWeight + w.latencyWeight + w.syntaxWeight + w.costWeight == 100

/-- Normalized empirical performance measurements supplied by the Mojo oracle -/
structure EmpiricalMetrics where
  promptTokPerSec : Nat  -- Measured prompt processing tokens / sec
  genTokPerSec    : Nat  -- Measured generation tokens / sec
  latencyMs       : Nat  -- Round-trip time in milliseconds
  syntaxValid     : Bool -- Code parsed cleanly without syntax errors
  remoteCostBilled: Nat  -- In micro-cents (0 for local)
  -- `costMeasured` added 20261108-0702, finding F-W-25. The Mojo mirror
  -- declared `remote_tokens_billed`, initialised it to 0, read it three
  -- times in `calculate_utility_score`, and NEVER ASSIGNED it, so
  -- `c_score = 100 if remote_billed == 0` was the constant 100 on every
  -- probe ever run. That arm scores the zero-burn invariant of
  -- SC-MODEL-ROLE-TWIN-001 §1.4, and it scored it with a tautology.
  --
  -- The repair cannot be done by a value alone: this field is a `Nat`, so it
  -- cannot carry -1, and 0 is the very value under test -- making it also the
  -- absence sentinel would restore the defect in a new costume. Hence an
  -- explicit measurement bit, mirroring `remote_billed_measured` on the Mojo
  -- side. An unmeasured cost is not a zero cost, exactly as an unmeasured
  -- latency is not an instantaneous one (F-W-22, this file, one week).
  costMeasured    : Bool -- False = never observed, NOT "observed as zero"
  deriving DecidableEq, Repr

/-- Computes an integer scalar score [0..1000] based on empirical measurements -/
def computeUtilityScore (w : ObjectiveWeights) (m : EmpiricalMetrics) : Nat :=
  let tScore := (m.promptTokPerSec + m.genTokPerSec * 2) * w.throughputWeight / 10
  -- `0 < m.latencyMs` added 20261107-2353, finding F-W-22. The Mojo mirror
  -- (model_evaluation_suite_lib.mojo:72) guards with
  -- `if latency_ms < 2000 and latency_ms > 0`, this side guarded only on
  -- `< 2000`, and the two therefore DISAGREED at exactly latencyMs = 0:
  -- Lean awarded (2000-0)*25/20 = 2500, Mojo awarded 0.
  --
  -- latencyMs = 0 is not a hypothetical boundary. It is the value every
  -- FAILED probe carries, because `total_time_ms` is only assigned when the
  -- response actually contains a timing field. So the two implementations
  -- diverged precisely on the degenerate input, and the divergence paid out
  -- its single largest term -- 2500 of a nominal 1000-point scale -- for a
  -- request that never completed. Lean is corrected to the Mojo semantics
  -- rather than the reverse: a zero round-trip was not measured, and an
  -- unmeasured latency is not an instantaneous one.
  let lScore := if 0 < m.latencyMs && m.latencyMs < 2000 then
                  (2000 - m.latencyMs) * w.latencyWeight / 20 else 0
  let sScore := if m.syntaxValid then w.syntaxWeight * 10 else 0
  -- `m.costMeasured &&` added 20261108-0702, finding F-W-25. See the field's
  -- note above. THM_COST_03 is the control: a MEASURED zero still earns the
  -- full weight, so this is a guard against unmeasured credit, not a penalty.
  let cScore := if m.costMeasured && m.remoteCostBilled == 0 then
                  w.costWeight * 10 else 0
  tScore + lScore + sScore + cScore

/-! ### 4. Formal Verification Theorems -/

/-- Theorem 1: Deterministic Code Profile hyperparameter validity -/
theorem thm_deterministic_code_profile_valid :
  isHyperparameterValid deterministicCodeProfile = true := by
  decide

/-- Theorem 2: Formal Proof Profile hyperparameter validity -/
theorem thm_formal_proof_profile_valid :
  isHyperparameterValid formalProofProfile = true := by
  decide

/-- Theorem 3: Exploratory Profile hyperparameter validity -/
theorem thm_exploratory_profile_valid :
  isHyperparameterValid exploratoryProfile = true := by
  decide

/-- Theorem 4: Standard Objective Weights are normalized to 100 -/
theorem thm_standard_weights_valid :
  (ObjectiveWeights.mk 35 25 30 10).isValid = true := by
  decide

/-- Canonical Razr15 Local Qwen Endpoint Specification -/
def canonicalRazr15LocalSpec : ModelEndpointSpec := {
  targetType      := ModelTargetType.localGpuCuda,
  endpointFqdn    := "razr15-1.tail55d152.ts.net",
  port            := 8000,
  modelId         := "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF",
  -- 8192 -> 16384 on 20261108-0702, finding F-W-28. MEASURED, not chosen:
  -- the llama.cpp backend at razr15-1:8081 reports `"n_ctx": 16384` with
  -- `"n_ctx_train": 131072` in its /v1/models metadata, observed
  -- 20261108-0702Z. The 8192 here was a constant on the authority side of a
  -- safety invariant, understating the real window twofold. A stale bound in
  -- the checker can miss a violation or invent one; this one missed, because
  -- the paired oracle also only asked whether SOME client entry matched 8192.
  -- The oracle now reads `n_ctx` from the backend instead of trusting either
  -- number, so this field records what was observed rather than defining it.
  contextPhysical := 16384,
  contextClient   := 8192,
  maxTokens       := 2048
}

/-- Theorem 5: The canonical Razr15 configuration satisfies the context safety invariant -/
theorem thm_razr15_context_safety_verified :
  isContextWindowSafe canonicalRazr15LocalSpec = true := by
  decide

/-- Theorem 6: A client context window exceeding physical backend length fails closed -/
theorem thm_oversized_client_context_rejected :
  let unsafeSpec : ModelEndpointSpec := {
    targetType      := ModelTargetType.localGpuCuda,
    endpointFqdn    := "razr15-1.tail55d152.ts.net",
    port            := 8000,
    modelId         := "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF",
    -- 8192 -> 16384 on 20261108-0702 so this counterexample is the one
    -- actually on disk, not a smaller hypothetical: ~/.pi/agent/models.json
    -- declares contextWindow 32768 against this backend's measured 16384.
    contextPhysical := 16384,
    contextClient   := 32768,
    maxTokens       := 4096
  }
  isContextWindowSafe unsafeSpec = false := by
  decide

/-! ### 5. Zero-burn cost scoring: measured, unmeasured, billed (F-W-25) -/

/-- A probe that reached a local endpoint and read a zero remote-token count. -/
def metricsMeasuredZero : EmpiricalMetrics :=
  { promptTokPerSec := 40, genTokPerSec := 25, latencyMs := 300,
    syntaxValid := true, remoteCostBilled := 0, costMeasured := true }

/-- The SAME probe, except the cost field was never observed. This is the
    state every probe was in before 20261108-0702: the field sat at its
    initial 0 because no code path ever wrote it. -/
def metricsUnmeasured : EmpiricalMetrics :=
  { metricsMeasuredZero with costMeasured := false }

/-- A probe that observed a genuine remote burn. -/
def metricsBilled : EmpiricalMetrics :=
  { metricsMeasuredZero with remoteCostBilled := 1200 }

/-- The defective scoring rule as it stood: cost credit on the value alone. -/
def cScoreOld (w : ObjectiveWeights) (m : EmpiricalMetrics) : Nat :=
  if m.remoteCostBilled == 0 then w.costWeight * 10 else 0

/-- The corrected rule: credit requires that the zero was actually observed. -/
def cScoreNew (w : ObjectiveWeights) (m : EmpiricalMetrics) : Nat :=
  if m.costMeasured && m.remoteCostBilled == 0 then w.costWeight * 10 else 0

/-- THM_COST_01 — the defect, stated. The old rule pays full cost credit for
    a measurement that never happened, which is why the Mojo arm could not
    fail: `remote_tokens_billed` defaulted to 0 and was never assigned. -/
theorem THM_COST_01_old_rule_pays_for_an_unmeasured_cost :
    cScoreOld (ObjectiveWeights.mk 35 25 30 10) metricsUnmeasured = 100 := by
  decide

/-- THM_COST_02 — the correction. No measurement, no credit. -/
theorem THM_COST_02_new_rule_withholds_credit_when_unmeasured :
    cScoreNew (ObjectiveWeights.mk 35 25 30 10) metricsUnmeasured = 0 := by
  decide

/-- THM_COST_03 — THE CONTROL THAT MATTERS. A measured zero still earns the
    full weight, so the fix cannot be mistaken for a blanket penalty that
    makes the zero-burn invariant unprovable instead of merely unasserted.
    Without this theorem, THM_COST_02 would be satisfied by a rule that
    always returns 0, which would be a second tautology facing the other way. -/
theorem THM_COST_03_measured_zero_still_earns_full_credit :
    cScoreNew (ObjectiveWeights.mk 35 25 30 10) metricsMeasuredZero = 100 := by
  decide

/-- THM_COST_04 — a measured nonzero burn earns nothing, under both rules.
    The correction narrows exactly one case and leaves the real failure
    detectable. -/
theorem THM_COST_04_measured_burn_earns_nothing :
    cScoreNew (ObjectiveWeights.mk 35 25 30 10) metricsBilled = 0 ∧
    cScoreOld (ObjectiveWeights.mk 35 25 30 10) metricsBilled = 0 := by
  decide

/-- THM_COST_05 — non-vacuity: the two rules genuinely disagree, and they
    disagree precisely on the state every historical probe was in. A fix that
    changed no verdict would be no fix at all. -/
theorem THM_COST_05_old_and_new_disagree_on_the_unmeasured_case :
    cScoreOld (ObjectiveWeights.mk 35 25 30 10) metricsUnmeasured ≠
    cScoreNew (ObjectiveWeights.mk 35 25 30 10) metricsUnmeasured := by
  decide

/-- THM_COST_06 — the new rule never awards MORE than the old one, so no
    configuration can gain score from this change. The correction is
    monotonically conservative. -/
theorem THM_COST_06_new_rule_never_awards_more (w : ObjectiveWeights)
    (m : EmpiricalMetrics) : cScoreNew w m ≤ cScoreOld w m := by
  unfold cScoreNew cScoreOld
  -- `cases h : ...` rewrites the scrutinee in the goal itself, so passing `h`
  -- to `simp` afterwards is redundant and the linter says so.
  cases m.costMeasured <;> cases m.remoteCostBilled == 0 <;> simp

/-! ### 6. Context-window safety is UNIVERSAL, not existential (F-W-28) -/

/-- Every declared client window must fit its physical backend. -/
def allContextWindowsSafe (specs : List ModelEndpointSpec) : Bool :=
  specs.all isContextWindowSafe

/-- The defective reading: SOME entry is safe. This is what the Mojo arm
    computed, via `contains(models_json, "\"contextWindow\": 8192")` -- a
    substring search that stops at the first compliant entry. -/
def someContextWindowSafe (specs : List ModelEndpointSpec) : Bool :=
  specs.any isContextWindowSafe

private def piSpec (client maxTok : Nat) : ModelEndpointSpec :=
  { targetType := ModelTargetType.localGpuCuda,
    endpointFqdn := "razr15-1.tail55d152.ts.net", port := 8000,
    modelId := "qwen2.5-coder-7b-instruct",
    contextPhysical := 16384, contextClient := client, maxTokens := maxTok }

/-- The configuration observed in ~/.pi/agent/models.json at 20261108-0702Z:
    3 model entries across 2 providers, all pointing at the same
    razr15-1:8000/v1, declaring contextWindow 32768, 8192 and 32768 against a
    backend whose measured `n_ctx` is 16384. -/
def observedPiClientConfig : List ModelEndpointSpec :=
  [piSpec 32768 4096, piSpec 8192 2048, piSpec 32768 4096]

/-- THM_CTX_01 — the defect, stated. The existential reading PASSES the
    observed configuration, on the strength of its single compliant entry. -/
theorem THM_CTX_01_existential_reading_passes_the_observed_config :
    someContextWindowSafe observedPiClientConfig = true := by
  decide

/-- THM_CTX_02 — the universal reading REFUSES the same configuration. Two of
    its three entries declare four times the window the backend serves. -/
theorem THM_CTX_02_universal_reading_refuses_the_observed_config :
    allContextWindowsSafe observedPiClientConfig = false := by
  decide

/-- THM_CTX_03 — non-vacuity: the two readings disagree on real data, so
    replacing one with the other changes a live verdict. -/
theorem THM_CTX_03_the_two_readings_disagree_on_observed_data :
    someContextWindowSafe observedPiClientConfig ≠
    allContextWindowsSafe observedPiClientConfig := by
  decide

/-- THM_CTX_04 — the control. The universal reading is not a constant `false`:
    it accepts a configuration in which every entry fits. Without this, the
    fix could be a check that fails everything, which detects nothing. -/
theorem THM_CTX_04_universal_reading_accepts_an_all_safe_config :
    allContextWindowsSafe [piSpec 8192 2048, piSpec 16384 4096] = true := by
  decide

/-- THM_CTX_05 — the EMPTY-SUBJECT TRAP, proved rather than assumed.
    `List.all` on an empty list is `true`, so a universal check over a config
    that could not be read reports a PASS: an absent subject satisfies it
    best of all. This is the F-W-26 pathology (`tools/lean` on an empty file
    prints nothing and exits 0) in a second location.

    This theorem is why the Mojo arm carries `declared > 0` as a PRESENCE
    condition in `world_or_blind` rather than folding it into the value: with
    it, an unreadable or emptied models.json is BLIND, which is nonpassing,
    instead of green. The guard is not defensive habit; it discharges a
    proved hole. -/
theorem THM_CTX_05_empty_config_passes_vacuously :
    allContextWindowsSafe [] = true ∧ someContextWindowSafe [] = false := by
  decide

/-- THM_CTX_06 — on a NON-EMPTY config the universal implies the existential,
    so the universal is strictly the stronger claim. The non-emptiness
    hypothesis is not decoration: THM_CTX_05 shows it fails on `[]`, where
    `all` holds and `any` does not. -/
theorem THM_CTX_06_universal_implies_existential_when_nonempty
    (s : ModelEndpointSpec) (rest : List ModelEndpointSpec)
    (h : allContextWindowsSafe (s :: rest) = true) :
    someContextWindowSafe (s :: rest) = true := by
  unfold allContextWindowsSafe someContextWindowSafe at *
  simp [List.all_cons, List.any_cons] at h ⊢
  exact Or.inl h.1

end UOS.ModelEvaluation
