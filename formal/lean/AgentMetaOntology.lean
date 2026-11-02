import Std

/-!
# AgentMetaOntology

Bounded Lean model corresponding to the four-agent registry and pure metadata
policy in `agent_capabilities.gleam` and `agent_meta_policy.gleam`.

This is an ABSTRACT SERIAL PURE-DATA model. The 17 aspects are vocabulary only.
It proves no Gleam refinement, authentic identity, actual runtime/model choice,
authorization, liveness, concurrency safety, provider custody, or system-wide
properties. In particular, requested identity and source-declared metadata are
not runtime observations or grants. Authority has only the source-defined
`AdmissionRequired` state. Capacity is counted from the phases in a retained
local node list. The concrete witness below satisfies selected typed vocabulary
constraints; it is not a proof of whole-source or system consistency. Cleanup
and reservation are pure data projections; no effects are represented.
-/

namespace AgentMetaOntology

inductive Agent where
  | pi | claude | agy | codex
  deriving DecidableEq, Repr

inductive Runtime where
  | piRuntime | claudeRuntime | agyRuntime | codexRuntime
  deriving DecidableEq, Repr

def runtimeOf : Agent → Runtime
  | .pi => .piRuntime
  | .claude => .claudeRuntime
  | .agy => .agyRuntime
  | .codex => .codexRuntime

theorem agent_runtime_injective (a b : Agent) (h : runtimeOf a = runtimeOf b) : a = b := by
  cases a <;> cases b <;> cases h <;> rfl

inductive Provider where
  | openRouter | google | anthropic | openAI | unspecified
  deriving DecidableEq, Repr

inductive ModelNamespace where
  | openRouterCatalog
  | nativeCatalog (runtime : Runtime)
  deriving DecidableEq, Repr

structure ModelRef where
  provider : Provider
  modelNamespace : ModelNamespace
  id : String
  deriving DecidableEq, Repr

structure RequestedInference where
  runtime : Runtime
  model : ModelRef
  deriving DecidableEq, Repr

def namespaceMatches (r : RequestedInference) : Prop :=
  match r.model.modelNamespace with
  | .openRouterCatalog => r.model.provider = .openRouter
  | .nativeCatalog expected => expected = r.runtime

theorem native_request_is_runtime_scoped (r : RequestedInference) (h : namespaceMatches r)
    (expected : Runtime) (hn : r.model.modelNamespace = .nativeCatalog expected) :
    expected = r.runtime := by
  unfold namespaceMatches at h
  rw [hn] at h
  exact h

inductive SourceInference where
  | unspecified (runtime : Runtime)
  | declared (runtime : Runtime) (model : ModelRef) (source : String)
  | legacyDeclared (runtime : Runtime) (model : ModelRef) (source : String)
  deriving DecidableEq, Repr

inductive SystemAspect where
  | a01SubstrateHardwareSafety | a02VersionControlDiscipline
  | a03ZeroMudaPurity | a04SupervisionActorHierarchy
  | a05DeterministicRuntimeEngine | a06FormalEvidenceAnalysis
  | a07MathematicalAuthority | a08FeedbackSemioticsHomeostasis
  | a09QuarantinedAIInference | a10MeshTelemetryObservability
  | a11AgentEventBusProtocol | a12DeclarativeUIComponentCatalog
  | a13MultiInterfaceAccessibility | a14UniversalTailscaleWebNavigation
  | a15ComprehensiveVerificationChecklist | a16KnowledgeManagementTriad
  | a17DurableExecutionWorkflow
  deriving DecidableEq, Repr

def allAspects : List SystemAspect := [
  .a01SubstrateHardwareSafety, .a02VersionControlDiscipline,
  .a03ZeroMudaPurity, .a04SupervisionActorHierarchy,
  .a05DeterministicRuntimeEngine, .a06FormalEvidenceAnalysis,
  .a07MathematicalAuthority, .a08FeedbackSemioticsHomeostasis,
  .a09QuarantinedAIInference, .a10MeshTelemetryObservability,
  .a11AgentEventBusProtocol, .a12DeclarativeUIComponentCatalog,
  .a13MultiInterfaceAccessibility, .a14UniversalTailscaleWebNavigation,
  .a15ComprehensiveVerificationChecklist, .a16KnowledgeManagementTriad,
  .a17DurableExecutionWorkflow]

theorem aspects_have_vocabulary_cardinality : allAspects.length = 17 := by decide
theorem aspects_have_no_duplicates : allAspects.Nodup := by decide

inductive Capability where
  | configureMcp | knowledgeRead | advisoryCompletion | toolExecution
  | taskLifecycle | evolutionProposal | releaseDeployment
  deriving DecidableEq, Repr

/-- A concept is an intensional predicate on a typed domain. -/
def Concept (α : Type) := α → Prop

def subclass {α : Type} (a b : Concept α) : Prop := ∀ x, a x → b x
def intersection {α : Type} (a b : Concept α) : Concept α :=
  fun x => a x ∧ b x

def agentConcept (a : Agent) : Concept Agent := fun x => x = a
def capabilityConcept (c : Capability) : Concept Capability := fun x => x = c

theorem subclass_refl {α : Type} (a : Concept α) : subclass a a := by
  intro x hx
  exact hx

theorem subclass_trans {α : Type} (a b c : Concept α)
    (hab : subclass a b) (hbc : subclass b c) : subclass a c := by
  intro x hx
  exact hbc x (hab x hx)

theorem intersection_subclass_left {α : Type} (a b : Concept α) :
    subclass (intersection a b) a := by
  intro x hx
  exact hx.1

theorem intersection_subclass_right {α : Type} (a b : Concept α) :
    subclass (intersection a b) b := by
  intro x hx
  exact hx.2

theorem intersection_is_greatest_lower_bound {α : Type}
    (a b lower : Concept α) (ha : subclass lower a) (hb : subclass lower b) :
    subclass lower (intersection a b) := by
  intro x hx
  exact ⟨ha x hx, hb x hx⟩

/-- Requested scope is immutable intent DATA, distinct from permission. -/
structure ScopeData where
  plan : String
  task : String
  worker : String
  session : String
  attempt : Nat
  candidate : String
  capabilities : List Capability
  layers : List (Fin 10)
  expiresUtc : Int
  expiresMono : Int
  deriving DecidableEq, Repr

def requestedCapability (s : ScopeData) : Concept Capability :=
  fun c => c ∈ s.capabilities

inductive Vertex where
  | agent (value : Agent)
  | runtime (value : Runtime)
  | capability (value : Capability)
  | scope (value : ScopeData)
  deriving DecidableEq, Repr

/-- Edges carry only source-corresponding identity/request data. -/
inductive Edge : Vertex → Vertex → Prop where
  | agentRuntime (a : Agent) : Edge (.agent a) (.runtime (runtimeOf a))
  | scopeRequestsCapability (s : ScopeData) (c : Capability)
      (membership : c ∈ s.capabilities) :
      Edge (.scope s) (.capability c)

inductive Path : Vertex → Vertex → Prop where
  | edge {src dst : Vertex} : Edge src dst → Path src dst
  | refl (vertex : Vertex) : Path vertex vertex
  | compose {src middle dst : Vertex} :
      Path src middle → Path middle dst → Path src dst

theorem path_composition {src middle dst : Vertex}
    (first : Path src middle) (second : Path middle dst) : Path src dst :=
  Path.compose first second

theorem agent_runtime_edge_exists (a : Agent) :
    Edge (.agent a) (.runtime (runtimeOf a)) := Edge.agentRuntime a

/-- For any declared scope membership proof, the corresponding typed edge exists. -/
theorem scope_capability_edge_exists (s : ScopeData) (c : Capability)
    (h : c ∈ s.capabilities) : Edge (.scope s) (.capability c) :=
  Edge.scopeRequestsCapability s c h

/-- There is deliberately no conversion from scope to authorization. -/
inductive AuthorityState where
  | admissionRequired
  deriving DecidableEq, Repr

def scopeAloneAuthorizes (_ : ScopeData) : AuthorityState := .admissionRequired

theorem scope_does_not_change_admission_state (s : ScopeData) :
    scopeAloneAuthorizes s = .admissionRequired := rfl

inductive Phase where
  | reserved | starting | running | cancelling | cleanupUnknown | released
  deriving DecidableEq, Repr

def active : Phase → Bool
  | .reserved => true
  | .starting => true
  | .running => true
  | .cancelling => true
  | .cleanupUnknown => true
  | .released => false

inductive Liability where
  | noneRecorded
  | recorded (reference : String) (amount : Nat)
  | costUnknown (reference : String) (amount : Nat)
  deriving DecidableEq, Repr

def liabilityAmount : Liability → Nat
  | .noneRecorded => 0
  | .recorded _ n => n
  | .costUnknown _ n => n

structure NodeData where
  phase : Phase
  liability : Liability
  deriving DecidableEq, Repr

structure LocalPool where
  capacity : Nat
  nodes : List NodeData
  deriving Repr

def phaseOccupancy : Phase → Nat
  | .reserved => 1
  | .starting => 1
  | .running => 1
  | .cancelling => 1
  | .cleanupUnknown => 1
  | .released => 0

def usedNodes : List NodeData → Nat
  | [] => 0
  | n :: rest => usedNodes rest + phaseOccupancy n.phase

def used (p : LocalPool) : Nat := usedNodes p.nodes
def canReserve (p : LocalPool) : Prop := used p < p.capacity
instance (p : LocalPool) : Decidable (canReserve p) := by
  unfold canReserve
  infer_instance

def reserve (p : LocalPool) (n : NodeData) : LocalPool :=
  ⟨p.capacity, n :: p.nodes⟩

def reserveWhenAvailable (p : LocalPool) (n : NodeData) : Option Nat :=
  if used p < p.capacity then some (used (reserve p n)) else none

theorem phase_occupancy_at_most_one (phase : Phase) : phaseOccupancy phase ≤ 1 := by
  cases phase with
  | reserved => exact Nat.le_refl 1
  | starting => exact Nat.le_refl 1
  | running => exact Nat.le_refl 1
  | cancelling => exact Nat.le_refl 1
  | cleanupUnknown => exact Nat.le_refl 1
  | released => exact Nat.zero_le 1

theorem reservation_count_increases (p : LocalPool) (n : NodeData)
    (hOccupancy : phaseOccupancy n.phase = 1) :
    used (reserve p n) = used p + 1 := by
  change usedNodes p.nodes + phaseOccupancy n.phase = usedNodes p.nodes + 1
  exact congrArg (fun count => usedNodes p.nodes + count) hOccupancy

theorem reservation_count_never_increases_by_more_than_one
    (p : LocalPool) (n : NodeData) :
    used (reserve p n) ≤ used p + 1 := by
  have hOccupancy := phase_occupancy_at_most_one n.phase
  change usedNodes p.nodes + phaseOccupancy n.phase ≤ usedNodes p.nodes + 1
  exact Nat.add_le_add_left hOccupancy (usedNodes p.nodes)

theorem guarded_reservation_preserves_capacity (p : LocalPool) (n : NodeData) :
    ∀ q, reserveWhenAvailable p n = some q → q ≤ p.capacity := by
  intro q h
  unfold reserveWhenAvailable at h
  split at h
  · rename_i hAvail
    injection h with hq
    subst q
    exact Nat.le_trans (reservation_count_never_increases_by_more_than_one p n)
      (Nat.succ_le_of_lt hAvail)
  · contradiction

def cleanupUnknown (n : NodeData) : NodeData := ⟨.cleanupUnknown, n.liability⟩
def recordCleanupObservation (n : NodeData) : NodeData := ⟨.released, n.liability⟩

theorem unknown_cleanup_reservation_increments (p : LocalPool) (n : NodeData) :
    used (reserve p (cleanupUnknown n)) = used p + 1 :=
  reservation_count_increases p (cleanupUnknown n) rfl

theorem unknown_cleanup_marker_is_retained (n : NodeData) :
    (cleanupUnknown n).phase = Phase.cleanupUnknown := rfl

theorem unknown_cleanup_remains_active (n : NodeData) :
    active (cleanupUnknown n).phase = true := rfl

theorem cleanup_preserves_liability (n : NodeData) :
    (recordCleanupObservation n).liability = n.liability := rfl

def sampleScope : ScopeData := {
  plan := "demo-plan",
  task := "demo-task",
  worker := "demo-worker",
  session := "demo-session",
  attempt := 1,
  -- Format-compatible fixture data; Lean does not implement `valid_scope`.
  candidate := "sha256:5fb7a77609e9f41f8368fc5a761435dec6519736a00f4642d6e986ca3e8e1663",
  capabilities := [.knowledgeRead],
  layers := [0],
  expiresUtc := 1,
  expiresMono := 1
}

def sampleVertices : List Vertex := [
  .agent .codex,
  .runtime .codexRuntime,
  .scope sampleScope,
  .capability .knowledgeRead
]

theorem agent_concept_has_concrete_witness :
    ∃ a, agentConcept .codex a := ⟨.codex, rfl⟩

theorem sample_scope_requests_knowledge_read :
    requestedCapability sampleScope .knowledgeRead :=
  List.Mem.head _

theorem sample_scope_has_typed_capability_edge :
    Edge (.scope sampleScope) (.capability .knowledgeRead) :=
  scope_capability_edge_exists sampleScope .knowledgeRead
    sample_scope_requests_knowledge_read

theorem sample_graph_is_nonempty : sampleVertices ≠ [] := by
  intro h
  cases h

theorem sample_agent_has_runtime_edge :
    Edge (.agent .codex) (.runtime .codexRuntime) := by
  exact agent_runtime_edge_exists .codex

def sampleEdges : List (Vertex × Vertex) := [
  (.agent .codex, .runtime .codexRuntime),
  (.scope sampleScope, .capability .knowledgeRead)
]

structure FiniteInterpretation where
  vertices : List Vertex
  edges : List (Vertex × Vertex)

def sampleInterpretation : FiniteInterpretation :=
  ⟨sampleVertices, sampleEdges⟩

/--
Selected finite fragment only: nonempty domain; four named vertices; the Codex
singleton concept and requested KnowledgeRead concept are inhabited; and both
the runtime and scope-capability edges occur in this same interpretation.
This predicate deliberately enumerates these constraints and no others.
-/
def SelectedOntologyConstraints (i : FiniteInterpretation) : Prop :=
  i.vertices ≠ [] ∧
  Vertex.agent .codex ∈ i.vertices ∧
  Vertex.runtime .codexRuntime ∈ i.vertices ∧
  Vertex.scope sampleScope ∈ i.vertices ∧
  Vertex.capability .knowledgeRead ∈ i.vertices ∧
  agentConcept .codex .codex ∧
  requestedCapability sampleScope .knowledgeRead ∧
  (Vertex.agent .codex, Vertex.runtime .codexRuntime) ∈ i.edges ∧
  Edge (.agent .codex) (.runtime .codexRuntime) ∧
  (Vertex.scope sampleScope, Vertex.capability .knowledgeRead) ∈ i.edges ∧
  Edge (.scope sampleScope) (.capability .knowledgeRead)

theorem one_interpretation_satisfies_selected_fragment :
    ∃ i : FiniteInterpretation, SelectedOntologyConstraints i := by
  refine ⟨sampleInterpretation, ?_⟩
  unfold SelectedOntologyConstraints sampleInterpretation
  constructor
  · exact sample_graph_is_nonempty
  constructor
  · decide
  constructor
  · decide
  constructor
  · decide
  constructor
  · decide
  constructor
  · rfl
  constructor
  · exact sample_scope_requests_knowledge_read
  constructor
  · decide
  constructor
  · exact sample_agent_has_runtime_edge
  constructor
  · decide
  · exact sample_scope_has_typed_capability_edge

theorem negative_control_unrequested_release_capability :
    ¬ requestedCapability sampleScope .releaseDeployment := by
  change ¬ Capability.releaseDeployment ∈ [Capability.knowledgeRead]
  simp

def sampleNode : NodeData := ⟨.cleanupUnknown, .noneRecorded⟩
def samplePool : LocalPool := ⟨1, []⟩

theorem sample_node_is_counted_as_occupying :
    usedNodes [sampleNode] = 1 := rfl

/-- Concrete local capacity example; separate from ontology satisfiability. -/
theorem sample_pool_guarded_reservation_succeeds :
    ∃ q, reserveWhenAvailable samplePool sampleNode = some q ∧ q = 1 := by
  exact ⟨1, by decide⟩

theorem sample_edge_interpretation_is_nonempty : sampleEdges ≠ [] := by
  intro h
  cases h

theorem liability_unknown_preserves_amount (ref : String) (amount : Nat) :
    liabilityAmount (.costUnknown ref amount) = amount := rfl

end AgentMetaOntology

#print axioms AgentMetaOntology.agent_runtime_injective
#print axioms AgentMetaOntology.native_request_is_runtime_scoped
#print axioms AgentMetaOntology.aspects_have_vocabulary_cardinality
#print axioms AgentMetaOntology.aspects_have_no_duplicates
#print axioms AgentMetaOntology.scope_does_not_change_admission_state
#print axioms AgentMetaOntology.reservation_count_increases
#print axioms AgentMetaOntology.unknown_cleanup_reservation_increments
#print axioms AgentMetaOntology.reservation_count_never_increases_by_more_than_one
#print axioms AgentMetaOntology.guarded_reservation_preserves_capacity
#print axioms AgentMetaOntology.unknown_cleanup_marker_is_retained
#print axioms AgentMetaOntology.cleanup_preserves_liability
#print axioms AgentMetaOntology.liability_unknown_preserves_amount
#print axioms AgentMetaOntology.subclass_refl
#print axioms AgentMetaOntology.subclass_trans
#print axioms AgentMetaOntology.intersection_subclass_left
#print axioms AgentMetaOntology.intersection_subclass_right
#print axioms AgentMetaOntology.intersection_is_greatest_lower_bound
#print axioms AgentMetaOntology.path_composition
#print axioms AgentMetaOntology.agent_runtime_edge_exists
#print axioms AgentMetaOntology.scope_capability_edge_exists
#print axioms AgentMetaOntology.unknown_cleanup_remains_active
#print axioms AgentMetaOntology.agent_concept_has_concrete_witness
#print axioms AgentMetaOntology.sample_scope_requests_knowledge_read
#print axioms AgentMetaOntology.sample_scope_has_typed_capability_edge
#print axioms AgentMetaOntology.sample_graph_is_nonempty
#print axioms AgentMetaOntology.sample_agent_has_runtime_edge
#print axioms AgentMetaOntology.sample_edge_interpretation_is_nonempty
#print axioms AgentMetaOntology.one_interpretation_satisfies_selected_fragment
#print axioms AgentMetaOntology.negative_control_unrequested_release_capability
#print axioms AgentMetaOntology.sample_node_is_counted_as_occupying
#print axioms AgentMetaOntology.sample_pool_guarded_reservation_succeeds
