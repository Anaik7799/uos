/- Planning model, 2026-10-27. No runtime-refinement or system-admission claim.
   The finite Task graph is copied from the canonical Sa-plan observation in
   var/harness/20261027-0634-prechange-risk-observation.json.
   Safety conclusions are conditional on actual dispatch implementing these gates.
-/
namespace UOS.DevelopmentCore

structure Gate where
  paused : Bool
  coreHealthy : Bool
  authorityCurrent : Bool
  evidenceFresh : Bool
  policyLoaded : Bool
  isolationBounded : Bool
  rollbackVerified : Bool
deriving Repr

def normalPermitted (g : Gate) : Bool :=
  !g.paused && g.coreHealthy && g.authorityCurrent && g.evidenceFresh &&
  g.policyLoaded && g.isolationBounded && g.rollbackVerified

theorem normal_requires_healthy_core (g : Gate) (h : normalPermitted g = true) :
    g.coreHealthy = true := by
  cases hc : g.coreHealthy <;> simp_all [normalPermitted]

theorem failing_core_blocks_normal (g : Gate) (h : g.coreHealthy = false) :
    normalPermitted g = false := by
  simp [normalPermitted, h]

theorem pause_blocks_normal (g : Gate) (h : g.paused = true) :
    normalPermitted g = false := by
  simp [normalPermitted, h]

theorem stale_authority_blocks_normal (g : Gate) (h : g.authorityCurrent = false) :
    normalPermitted g = false := by
  simp [normalPermitted, h]

theorem stale_evidence_blocks_normal (g : Gate) (h : g.evidenceFresh = false) :
    normalPermitted g = false := by
  simp [normalPermitted, h]

theorem unloaded_policy_blocks_normal (g : Gate) (h : g.policyLoaded = false) :
    normalPermitted g = false := by
  simp [normalPermitted, h]

theorem unbounded_isolation_blocks_normal (g : Gate) (h : g.isolationBounded = false) :
    normalPermitted g = false := by
  simp [normalPermitted, h]

theorem unverified_rollback_blocks_normal (g : Gate) (h : g.rollbackVerified = false) :
    normalPermitted g = false := by
  simp [normalPermitted, h]

def recoveryPermitted (g : Gate) (repairOnly : Bool) : Bool :=
  !g.paused && g.authorityCurrent && g.evidenceFresh && g.policyLoaded &&
  g.isolationBounded && g.rollbackVerified && repairOnly

theorem recovery_requires_repair_scope (g : Gate) (r : Bool)
    (h : recoveryPermitted g r = true) : r = true := by
  cases hr : r <;> simp_all [recoveryPermitted]

theorem pause_blocks_recovery (g : Gate) (r : Bool) (h : g.paused = true) :
    recoveryPermitted g r = false := by
  simp [recoveryPermitted, h]

structure State where
  baselineId : Nat
  baselineHealthy : Bool
  candidateId : Nat
deriving Repr

def candidateEdit (s : State) : State :=
  { s with candidateId := s.candidateId + 1 }

def NormalStep (s t : State) (g : Gate) : Prop :=
  normalPermitted g = true ∧ s.baselineHealthy = g.coreHealthy ∧ t = candidateEdit s

theorem normal_step_starts_with_healthy_baseline (s t : State) (g : Gate)
    (h : NormalStep s t g) : s.baselineHealthy = true := by
  rcases h with ⟨hg, hb, _⟩
  exact hb.trans (normal_requires_healthy_core g hg)

theorem candidate_edit_preserves_baseline_identity (s : State) :
    (candidateEdit s).baselineId = s.baselineId := by
  rfl

theorem candidate_edit_preserves_baseline_health (s : State) :
    (candidateEdit s).baselineHealthy = s.baselineHealthy := by
  rfl

def promotionPermitted (g : Gate) (candidateGreen independentlyReviewed repairOnly : Bool) : Bool :=
  !g.paused && g.authorityCurrent && g.evidenceFresh && g.policyLoaded &&
  g.isolationBounded && g.rollbackVerified && candidateGreen &&
  independentlyReviewed && (g.coreHealthy || repairOnly)

theorem promotion_requires_green_candidate (g : Gate) (green peer repair : Bool)
    (h : promotionPermitted g green peer repair = true) : green = true := by
  cases hc : green <;> simp_all [promotionPermitted]

theorem promotion_requires_independent_review (g : Gate) (green peer repair : Bool)
    (h : promotionPermitted g green peer repair = true) : peer = true := by
  cases hp : peer <;> simp_all [promotionPermitted]

theorem failed_baseline_requires_repair_promotion (g : Gate) (green peer repair : Bool)
    (hb : g.coreHealthy = false)
    (h : promotionPermitted g green peer repair = true) : repair = true := by
  cases hr : repair <;> simp_all [promotionPermitted]

inductive Task where
  | ACTIVATE_REVIEW
  | AGENT_PARITY
  | BOOTSTRAP
  | CAPABILITY_PARITY
  | CONTROL_ACCEPT
  | CONTROL_RECOVERY
  | COST_EFFICIENCY
  | DEV_INTEGRATE
  | DEV_READY_REVIEW
  | FAULT_RECOVERY
  | FORMAL_EVIDENCE
  | GRANT_REVIEW
  | HIVE_VERIFY
  | KNOWLEDGE_SYNC
  | MCP_ACTIVATE
  | NATIVE_BOUNDARY_REPAIR
  | OPERATOR_RESUME
  | OPERATOR_SURFACES
  | PERF_SCALE
  | PLANNING_MCP
  | READINESS_CENSUS
  | RECEIPT_FIX
  | RECEIPT_GRANT_REBIND
  | RECEIPT_GRANT_REVIEW
  | SCHEDULER_GATES
  | SERVICE_VERIFY
  | TELEGRAM_ACCEPT
deriving Repr, DecidableEq

def dependencies : Task → List Task
  | .ACTIVATE_REVIEW => []
  | .AGENT_PARITY => [.MCP_ACTIVATE]
  | .BOOTSTRAP => []
  | .CAPABILITY_PARITY => [.AGENT_PARITY, .NATIVE_BOUNDARY_REPAIR, .OPERATOR_RESUME, .PLANNING_MCP, .READINESS_CENSUS, .SERVICE_VERIFY]
  | .CONTROL_ACCEPT => [.CONTROL_RECOVERY, .MCP_ACTIVATE, .OPERATOR_RESUME, .RECEIPT_FIX]
  | .CONTROL_RECOVERY => [.OPERATOR_RESUME]
  | .COST_EFFICIENCY => [.AGENT_PARITY, .OPERATOR_RESUME, .PERF_SCALE]
  | .DEV_INTEGRATE => [.DEV_READY_REVIEW, .OPERATOR_RESUME]
  | .DEV_READY_REVIEW => [.CAPABILITY_PARITY, .COST_EFFICIENCY, .FAULT_RECOVERY, .FORMAL_EVIDENCE, .HIVE_VERIFY, .KNOWLEDGE_SYNC, .NATIVE_BOUNDARY_REPAIR, .OPERATOR_RESUME, .OPERATOR_SURFACES, .PERF_SCALE, .PLANNING_MCP, .SCHEDULER_GATES, .TELEGRAM_ACCEPT]
  | .FAULT_RECOVERY => [.AGENT_PARITY, .OPERATOR_RESUME, .SCHEDULER_GATES, .SERVICE_VERIFY]
  | .FORMAL_EVIDENCE => [.CAPABILITY_PARITY, .FAULT_RECOVERY, .OPERATOR_RESUME, .SCHEDULER_GATES]
  | .GRANT_REVIEW => [.BOOTSTRAP]
  | .HIVE_VERIFY => [.AGENT_PARITY, .SERVICE_VERIFY]
  | .KNOWLEDGE_SYNC => [.FORMAL_EVIDENCE, .OPERATOR_RESUME, .OPERATOR_SURFACES, .READINESS_CENSUS]
  | .MCP_ACTIVATE => [.GRANT_REVIEW]
  | .NATIVE_BOUNDARY_REPAIR => [.OPERATOR_RESUME, .READINESS_CENSUS]
  | .OPERATOR_RESUME => []
  | .OPERATOR_SURFACES => [.CAPABILITY_PARITY, .OPERATOR_RESUME, .SCHEDULER_GATES]
  | .PERF_SCALE => [.CAPABILITY_PARITY, .FAULT_RECOVERY, .OPERATOR_RESUME, .OPERATOR_SURFACES]
  | .PLANNING_MCP => [.CONTROL_ACCEPT, .OPERATOR_RESUME]
  | .READINESS_CENSUS => [.CONTROL_ACCEPT, .OPERATOR_RESUME]
  | .RECEIPT_FIX => [.RECEIPT_GRANT_REVIEW]
  | .RECEIPT_GRANT_REBIND => [.RECEIPT_GRANT_REVIEW]
  | .RECEIPT_GRANT_REVIEW => [.ACTIVATE_REVIEW]
  | .SCHEDULER_GATES => [.OPERATOR_RESUME, .PLANNING_MCP, .READINESS_CENSUS]
  | .SERVICE_VERIFY => [.MCP_ACTIVATE]
  | .TELEGRAM_ACCEPT => [.CAPABILITY_PARITY, .FAULT_RECOVERY, .OPERATOR_RESUME]

def coreTasks : List Task :=
  [.HIVE_VERIFY, .AGENT_PARITY, .MCP_ACTIVATE, .GRANT_REVIEW, .BOOTSTRAP, .SERVICE_VERIFY, .PLANNING_MCP, .CONTROL_ACCEPT, .CONTROL_RECOVERY, .OPERATOR_RESUME, .RECEIPT_FIX, .RECEIPT_GRANT_REVIEW, .ACTIVATE_REVIEW]

def deferredTasks : List Task :=
  [.READINESS_CENSUS, .NATIVE_BOUNDARY_REPAIR, .SCHEDULER_GATES, .CAPABILITY_PARITY, .FAULT_RECOVERY, .OPERATOR_SURFACES, .PERF_SCALE, .FORMAL_EVIDENCE, .TELEGRAM_ACCEPT, .COST_EFFICIENCY, .KNOWLEDGE_SYNC, .DEV_READY_REVIEW, .DEV_INTEGRATE]

def dependencyClosed (ts : List Task) : Bool :=
  ts.all (fun t => (dependencies t).all (fun d => ts.contains d))

theorem frozen_core_is_dependency_closed : dependencyClosed coreTasks = true := by
  decide

theorem frozen_core_excludes_deferred_tasks :
    coreTasks.all (fun t => !(deferredTasks.contains t)) = true := by
  decide

theorem existing_hive_workflow_is_in_core : coreTasks.contains .HIVE_VERIFY = true := by
  decide

theorem missing_planning_capability_is_in_core :
    coreTasks.contains .PLANNING_MCP = true := by
  decide

inductive Needed : Task → Prop where
  | hive : Needed .HIVE_VERIFY
  | planning : Needed .PLANNING_MCP
  | dependency {parent child : Task} :
      Needed parent → child ∈ dependencies parent → Needed child

theorem closed_sets_contain_needed (S : Task → Prop)
    (hHive : S .HIVE_VERIFY) (hPlanning : S .PLANNING_MCP)
    (hClosed : ∀ parent child, S parent → child ∈ dependencies parent → S child)
    {t : Task} (h : Needed t) : S t := by
  induction h with
  | hive => exact hHive
  | planning => exact hPlanning
  | dependency _ hDep ih => exact hClosed _ _ ih hDep

theorem core_nodes_are_needed (t : Task) (h : t ∈ coreTasks) : Needed t := by
  cases t with
  | ACTIVATE_REVIEW => exact (Needed.dependency (parent := .RECEIPT_GRANT_REVIEW) (child := .ACTIVATE_REVIEW) (Needed.dependency (parent := .RECEIPT_FIX) (child := .RECEIPT_GRANT_REVIEW) (Needed.dependency (parent := .CONTROL_ACCEPT) (child := .RECEIPT_FIX) (Needed.dependency (parent := .PLANNING_MCP) (child := .CONTROL_ACCEPT) Needed.planning (by decide)) (by decide)) (by decide)) (by decide))
  | AGENT_PARITY => exact (Needed.dependency (parent := .HIVE_VERIFY) (child := .AGENT_PARITY) Needed.hive (by decide))
  | BOOTSTRAP => exact (Needed.dependency (parent := .GRANT_REVIEW) (child := .BOOTSTRAP) (Needed.dependency (parent := .MCP_ACTIVATE) (child := .GRANT_REVIEW) (Needed.dependency (parent := .AGENT_PARITY) (child := .MCP_ACTIVATE) (Needed.dependency (parent := .HIVE_VERIFY) (child := .AGENT_PARITY) Needed.hive (by decide)) (by decide)) (by decide)) (by decide))
  | CAPABILITY_PARITY => simp [coreTasks] at h
  | CONTROL_ACCEPT => exact (Needed.dependency (parent := .PLANNING_MCP) (child := .CONTROL_ACCEPT) Needed.planning (by decide))
  | CONTROL_RECOVERY => exact (Needed.dependency (parent := .CONTROL_ACCEPT) (child := .CONTROL_RECOVERY) (Needed.dependency (parent := .PLANNING_MCP) (child := .CONTROL_ACCEPT) Needed.planning (by decide)) (by decide))
  | COST_EFFICIENCY => simp [coreTasks] at h
  | DEV_INTEGRATE => simp [coreTasks] at h
  | DEV_READY_REVIEW => simp [coreTasks] at h
  | FAULT_RECOVERY => simp [coreTasks] at h
  | FORMAL_EVIDENCE => simp [coreTasks] at h
  | GRANT_REVIEW => exact (Needed.dependency (parent := .MCP_ACTIVATE) (child := .GRANT_REVIEW) (Needed.dependency (parent := .AGENT_PARITY) (child := .MCP_ACTIVATE) (Needed.dependency (parent := .HIVE_VERIFY) (child := .AGENT_PARITY) Needed.hive (by decide)) (by decide)) (by decide))
  | HIVE_VERIFY => exact Needed.hive
  | KNOWLEDGE_SYNC => simp [coreTasks] at h
  | MCP_ACTIVATE => exact (Needed.dependency (parent := .AGENT_PARITY) (child := .MCP_ACTIVATE) (Needed.dependency (parent := .HIVE_VERIFY) (child := .AGENT_PARITY) Needed.hive (by decide)) (by decide))
  | NATIVE_BOUNDARY_REPAIR => simp [coreTasks] at h
  | OPERATOR_RESUME => exact (Needed.dependency (parent := .CONTROL_RECOVERY) (child := .OPERATOR_RESUME) (Needed.dependency (parent := .CONTROL_ACCEPT) (child := .CONTROL_RECOVERY) (Needed.dependency (parent := .PLANNING_MCP) (child := .CONTROL_ACCEPT) Needed.planning (by decide)) (by decide)) (by decide))
  | OPERATOR_SURFACES => simp [coreTasks] at h
  | PERF_SCALE => simp [coreTasks] at h
  | PLANNING_MCP => exact Needed.planning
  | READINESS_CENSUS => simp [coreTasks] at h
  | RECEIPT_FIX => exact (Needed.dependency (parent := .CONTROL_ACCEPT) (child := .RECEIPT_FIX) (Needed.dependency (parent := .PLANNING_MCP) (child := .CONTROL_ACCEPT) Needed.planning (by decide)) (by decide))
  | RECEIPT_GRANT_REBIND => simp [coreTasks] at h
  | RECEIPT_GRANT_REVIEW => exact (Needed.dependency (parent := .RECEIPT_FIX) (child := .RECEIPT_GRANT_REVIEW) (Needed.dependency (parent := .CONTROL_ACCEPT) (child := .RECEIPT_FIX) (Needed.dependency (parent := .PLANNING_MCP) (child := .CONTROL_ACCEPT) Needed.planning (by decide)) (by decide)) (by decide))
  | SCHEDULER_GATES => simp [coreTasks] at h
  | SERVICE_VERIFY => exact (Needed.dependency (parent := .HIVE_VERIFY) (child := .SERVICE_VERIFY) Needed.hive (by decide))
  | TELEGRAM_ACCEPT => simp [coreTasks] at h

theorem core_is_least_closed_required_set (S : Task → Prop)
    (hHive : S .HIVE_VERIFY) (hPlanning : S .PLANNING_MCP)
    (hClosed : ∀ parent child, S parent → child ∈ dependencies parent → S child)
    {t : Task} (h : t ∈ coreTasks) : S t := by
  exact closed_sets_contain_needed S hHive hPlanning hClosed (core_nodes_are_needed t h)

#print axioms closed_sets_contain_needed
#print axioms core_nodes_are_needed
#print axioms core_is_least_closed_required_set


#print axioms normal_requires_healthy_core
#print axioms failing_core_blocks_normal
#print axioms pause_blocks_normal
#print axioms stale_authority_blocks_normal
#print axioms stale_evidence_blocks_normal
#print axioms unloaded_policy_blocks_normal
#print axioms unbounded_isolation_blocks_normal
#print axioms unverified_rollback_blocks_normal
#print axioms recovery_requires_repair_scope
#print axioms pause_blocks_recovery
#print axioms normal_step_starts_with_healthy_baseline
#print axioms candidate_edit_preserves_baseline_identity
#print axioms candidate_edit_preserves_baseline_health
#print axioms promotion_requires_green_candidate
#print axioms promotion_requires_independent_review
#print axioms failed_baseline_requires_repair_promotion
#print axioms frozen_core_is_dependency_closed
#print axioms frozen_core_excludes_deferred_tasks
#print axioms existing_hive_workflow_is_in_core
#print axioms missing_planning_capability_is_in_core


/- Typed fencing: owner, attempt, epoch and boot domain are distinct fields. -/
structure Lease where
  owner : Nat
  attempt : Nat
  epoch : Nat
  bootId : Nat
  hostId : Nat
  expiresMono : Nat

structure Binding where
  worker : Nat
  attempt : Nat
  epoch : Nat
  bootId : Nat
  hostId : Nat

def fenced (lease : Lease) (binding : Binding) (now horizon : Nat) : Prop :=
  binding.worker = lease.owner ∧ binding.attempt = lease.attempt ∧
  binding.epoch = lease.epoch ∧ binding.bootId = lease.bootId ∧
  binding.hostId = lease.hostId ∧
  now + horizon < lease.expiresMono

theorem stale_owner_is_refused (l : Lease) (b : Binding) (now horizon : Nat)
    (bad : b.worker ≠ l.owner) : ¬ fenced l b now horizon := by
  intro h
  exact bad h.1

theorem stale_attempt_is_refused (l : Lease) (b : Binding) (now horizon : Nat)
    (bad : b.attempt ≠ l.attempt) : ¬ fenced l b now horizon := by
  intro h
  exact bad h.2.1

theorem stale_epoch_is_refused (l : Lease) (b : Binding) (now horizon : Nat)
    (bad : b.epoch ≠ l.epoch) : ¬ fenced l b now horizon := by
  intro h
  exact bad h.2.2.1

theorem wrong_boot_is_refused (l : Lease) (b : Binding) (now horizon : Nat)
    (bad : b.bootId ≠ l.bootId) : ¬ fenced l b now horizon := by
  intro h
  exact bad h.2.2.2.1

theorem full_effect_horizon_is_fenced (l : Lease) (b : Binding) (now horizon : Nat)
    (h : fenced l b now horizon) : now + horizon < l.expiresMono := by
  exact h.2.2.2.2.2

theorem wrong_host_is_refused (l : Lease) (b : Binding) (now horizon : Nat)
    (bad : b.hostId ≠ l.hostId) : ¬ fenced l b now horizon := by
  intro h
  exact bad h.2.2.2.2.1

/- Stable logical IDs are not derived from attempt numbers. A durable reservation
   must precede an external dispatch. Unknown outcome never grants blind retry.
   These are dispatch/model laws, not a claim of physical exactly-once delivery. -/
inductive Outcome where
  | prepared | unknown | succeeded | failed
deriving DecidableEq, Repr

structure EffectRecord where
  logicalId : Nat
  outcome : Outcome
deriving Repr

def hasLogicalId (id : Nat) (records : List EffectRecord) : Bool :=
  records.any (fun r => r.logicalId == id)

def prepare (records : List EffectRecord) (id : Nat) : Option (List EffectRecord) :=
  if hasLogicalId id records then none
  else some ({ logicalId := id, outcome := .prepared } :: records)

theorem duplicate_logical_id_cannot_prepare (records : List EffectRecord) (id : Nat)
    (present : hasLogicalId id records = true) : prepare records id = none := by
  simp [prepare, present]

def reserveDispatch (r : EffectRecord) : Option EffectRecord :=
  match r.outcome with
  | .prepared => some { r with outcome := .unknown }
  | _ => none

theorem unknown_outcome_cannot_redispatch (id : Nat) :
    reserveDispatch { logicalId := id, outcome := .unknown } = none := by
  rfl

theorem completed_outcome_cannot_redispatch (id : Nat) :
    reserveDispatch { logicalId := id, outcome := .succeeded } = none := by
  rfl

theorem reservation_preserves_logical_identity (r next : EffectRecord)
    (h : reserveDispatch r = some next) : next.logicalId = r.logicalId := by
  cases r with
  | mk id outcome =>
    cases outcome <;> simp [reserveDispatch] at h
    cases h
    rfl

theorem reserved_record_cannot_redispatch (r next : EffectRecord)
    (h : reserveDispatch r = some next) : reserveDispatch next = none := by
  cases r with
  | mk id outcome =>
    cases outcome <;> simp [reserveDispatch] at h
    cases h
    rfl

inductive Reconciliation where
  | confirmedNoEffect | confirmedEffect | undetermined
deriving Repr

/- Reconciliation is a TRUSTED observed input, never caller text or model advice.
   The runtime obligation is to establish that observation independently. -/
def reconcileOutcome (r : EffectRecord) (e : Reconciliation) : EffectRecord :=
  match r.outcome, e with
  | .unknown, .confirmedNoEffect => { r with outcome := .prepared }
  | .unknown, .confirmedEffect => { r with outcome := .succeeded }
  | _, _ => r

theorem undetermined_observation_preserves_stop (id : Nat) :
    (reconcileOutcome { logicalId := id, outcome := .unknown } .undetermined).outcome
      = .unknown := by
  rfl

theorem confirmed_effect_remains_nonrepeatable (id : Nat) :
    reserveDispatch
      (reconcileOutcome { logicalId := id, outcome := .unknown } .confirmedEffect)
      = none := by
  rfl

/- Fractal health applies at every depth of a finite required-capability tree.
   A healthy ancestor cannot hide an unknown or failed required descendant. -/
inductive Health where
  | healthy | unknown | failed
deriving DecidableEq, Repr

inductive Holon where
  | leaf (localHealth : Health)
  | join (localHealth : Health) (left right : Holon)
deriving Repr

def allHealthy : Holon → Bool
  | .leaf status => status == .healthy
  | .join status left right =>
      status == .healthy && allHealthy left && allHealthy right

theorem unknown_leaf_cannot_pass : allHealthy (.leaf .unknown) = false := by
  rfl

theorem failed_leaf_cannot_pass : allHealthy (.leaf .failed) = false := by
  rfl

theorem healthy_join_requires_healthy_children (status : Health) (left right : Holon)
    (h : allHealthy (.join status left right) = true) :
    allHealthy left = true ∧ allHealthy right = true := by
  constructor
  · cases hl : allHealthy left <;> simp_all [allHealthy]
  · cases hr : allHealthy right <;> simp_all [allHealthy]

inductive Descendant : Holon → Holon → Prop where
  | here (h : Holon) : Descendant h h
  | left {status : Health} {l r child : Holon} :
      Descendant l child → Descendant (.join status l r) child
  | right {status : Health} {l r child : Holon} :
      Descendant r child → Descendant (.join status l r) child

theorem accepted_holon_has_only_healthy_required_descendants
    {root child : Holon} (path : Descendant root child) :
    allHealthy root = true → allHealthy child = true := by
  induction path with
  | here _ => intro h; exact h
  | left _ ih =>
      intro h
      exact ih (healthy_join_requires_healthy_children _ _ _ h).1
  | right _ ih =>
      intro h
      exact ih (healthy_join_requires_healthy_children _ _ _ h).2

/- Zero-Muda cost law: under NONNEGATIVE ADDITIVE task costs, including an
   unnecessary task cannot reduce total cost. Real utility, shared setup costs,
   hidden dependencies and risk pricing still require measurement. -/
def selectionCost (taskUniverse : List Task) (selected : Task → Bool)
    (cost : Task → Nat) : Nat :=
  match taskUniverse with
  | [] => 0
  | t :: rest => (if selected t then cost t else 0) + selectionCost rest selected cost

theorem subset_cannot_cost_more (taskUniverse : List Task)
    (small large : Task → Bool) (cost : Task → Nat)
    (contained : ∀ t, small t = true → large t = true) :
    selectionCost taskUniverse small cost ≤ selectionCost taskUniverse large cost := by
  induction taskUniverse with
  | nil => exact Nat.le_refl 0
  | cons t rest ih =>
      have firstCost : (if small t then cost t else 0) ≤
          (if large t then cost t else 0) := by
        by_cases hs : small t = true
        · have hl := contained t hs
          simp [hs, hl]
        · have hf : small t = false := by
            cases hx : small t <;> simp_all
          simp [hf]
      exact Nat.add_le_add firstCost ih

#print axioms stale_owner_is_refused
#print axioms stale_attempt_is_refused
#print axioms stale_epoch_is_refused
#print axioms wrong_boot_is_refused
#print axioms full_effect_horizon_is_fenced
#print axioms wrong_host_is_refused
#print axioms duplicate_logical_id_cannot_prepare
#print axioms unknown_outcome_cannot_redispatch
#print axioms completed_outcome_cannot_redispatch
#print axioms reservation_preserves_logical_identity
#print axioms reserved_record_cannot_redispatch
#print axioms undetermined_observation_preserves_stop
#print axioms confirmed_effect_remains_nonrepeatable
#print axioms unknown_leaf_cannot_pass
#print axioms failed_leaf_cannot_pass
#print axioms healthy_join_requires_healthy_children
#print axioms accepted_holon_has_only_healthy_required_descendants
#print axioms subset_cannot_cost_more


/- Capability growth restricts authority; it cannot enlarge a parent's scope. -/
def childScope (parent declared : Nat → Prop) : Nat → Prop :=
  fun operation => parent operation ∧ declared operation

theorem child_cannot_escalate_authority (parent declared : Nat → Prop)
    (operation : Nat) (h : childScope parent declared operation) : parent operation := by
  exact h.1

def restrictAlong (parent : Nat → Prop) : List (Nat → Prop) → Nat → Prop
  | [] => parent
  | declared :: rest => restrictAlong (childScope parent declared) rest

theorem arbitrary_depth_growth_cannot_escalate (declared : List (Nat → Prop)) :
    ∀ (parent : Nat → Prop) operation,
      restrictAlong parent declared operation → parent operation := by
  induction declared with
  | nil => intro parent operation h; exact h
  | cons scope rest ih =>
      intro parent operation h
      exact (ih (childScope parent scope) operation h).1

def healthyGate : Gate := {
  paused := false, coreHealthy := true, authorityCurrent := true,
  evidenceFresh := true, policyLoaded := true, isolationBounded := true,
  rollbackVerified := true
}

-- Satisfiable controls: the gates permit valid work and isolated repair.
example : normalPermitted healthyGate = true := by decide
example : recoveryPermitted { healthyGate with coreHealthy := false } true = true := by decide
example : normalPermitted { healthyGate with coreHealthy := false } = false := by decide
example : fenced
    { owner := 7, attempt := 1, epoch := 3, bootId := 9, hostId := 42, expiresMono := 100 }
    { worker := 7, attempt := 1, epoch := 3, bootId := 9, hostId := 42 } 10 20 := by
  unfold fenced
  decide
example : reserveDispatch { logicalId := 42, outcome := .prepared } =
    some { logicalId := 42, outcome := .unknown } := by rfl
example : allHealthy (.join .healthy (.leaf .healthy) (.leaf .healthy)) = true := by decide
example : allHealthy (.join .healthy (.leaf .healthy) (.leaf .unknown)) = false := by decide

#print axioms child_cannot_escalate_authority
#print axioms arbitrary_depth_growth_cannot_escalate


/- Concrete correspondence target: admission.grant_budget_valid/3, with Int
   arithmetic matching BEAM integers and milliseconds explicitly converted. -/
def grantBudgetValid (expires now requiredMs : Int) : Bool :=
  decide (0 ≤ now ∧ 0 ≤ requiredMs ∧ requiredMs ≤ 70000 ∧
    now + requiredMs * 1000 < expires ∧ expires - now ≤ 86400000000)

theorem grant_budget_limits_horizon (expires now requiredMs : Int)
    (h : grantBudgetValid expires now requiredMs = true) : requiredMs ≤ 70000 := by
  unfold grantBudgetValid at h
  exact (of_decide_eq_true h).2.2.1

theorem grant_budget_requires_strict_deadline (expires now requiredMs : Int)
    (h : grantBudgetValid expires now requiredMs = true) :
    now + requiredMs * 1000 < expires := by
  unfold grantBudgetValid at h
  exact (of_decide_eq_true h).2.2.2.1

example : grantBudgetValid 1001 0 1 = true := by decide
example : grantBudgetValid 1000 0 1 = false := by decide
example : grantBudgetValid 86400000001 0 0 = false := by decide
example : grantBudgetValid 100000000 0 70001 = false := by decide
example : grantBudgetValid 1000 (-1) 0 = false := by decide

def emitBudgetCases : IO Unit := do
  for now in [(-1 : Int), 0, 1000000] do
    for required in [(-1 : Int), 0, 1, 69999, 70000, 70001] do
      for delta in [(-1 : Int), 0, 1, 999, 1000, 1001, 69999000,
          69999001, 70000000, 70000001, 86400000000, 86400000001] do
        let expires := now + delta
        IO.println ("CASE|" ++ toString expires ++ "|" ++ toString now ++ "|" ++
          toString required ++ "|" ++ toString (grantBudgetValid expires now required))

#print axioms grant_budget_limits_horizon
#print axioms grant_budget_requires_strict_deadline


/- Concrete replay acceptance corresponds to operations.replay/2 after parsing.
   Malformed/missing JSON fields remain a separate runtime parser obligation. -/
def replayAllowed (schemaOK kindOK signatureOK executed : Bool) : Bool :=
  schemaOK && kindOK && signatureOK && executed

theorem replay_requires_matching_signature (schemaOK kindOK signatureOK executed : Bool)
    (h : replayAllowed schemaOK kindOK signatureOK executed = true) :
    signatureOK = true := by
  cases hs : signatureOK <;> simp_all [replayAllowed]

theorem failed_or_unverified_receipt_cannot_replay (schemaOK kindOK signatureOK : Bool) :
    replayAllowed schemaOK kindOK signatureOK false = false := by
  simp [replayAllowed]

def emitReplayCases : IO Unit := do
  for schemaOK in [false, true] do
    for kindOK in [false, true] do
      for signatureOK in [false, true] do
        for executed in [false, true] do
          IO.println ("REPLAY|" ++ toString schemaOK ++ "|" ++ toString kindOK ++ "|" ++
            toString signatureOK ++ "|" ++ toString executed ++ "|" ++
            toString (replayAllowed schemaOK kindOK signatureOK executed))

#print axioms replay_requires_matching_signature
#print axioms failed_or_unverified_receipt_cannot_replay

end UOS.DevelopmentCore

def main : IO Unit := do
  UOS.DevelopmentCore.emitBudgetCases
  UOS.DevelopmentCore.emitReplayCases

