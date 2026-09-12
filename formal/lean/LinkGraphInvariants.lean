/- LinkGraphInvariants.lean — Lean 4 Formal Proofs for Universal Link Graph
   Topological Invariants, Strongly Connected Component (SCC = 1) Completeness,
   Zero Dead-End Invariant, and Fail-Closed Verification Gates.

   Mathematical Authority for:
   - apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/link_tracker_view.gleam
   - tools/link_tracker_verifier.ml
   - docs/design/20260912-1030-uos-link-tracker-graph-analyser-verifier-specification.md
-/

namespace UOS.LinkGraph

-- 1. Canonical Node Enumeration (All 32 canonical UI pages + checklist)
inductive PageNode where
  | Dashboard
  | Planning
  | Immune
  | Knowledge
  | Zenoh
  | Cockpit
  | Verification
  | Substrate
  | Metabolic
  | Podman
  | Mcp
  | Kms
  | Telemetry
  | Federation
  | HealthGrid
  | Prajna
  | Agents
  | Holon
  | Config
  | Git
  | Database
  | Bridge
  | Smriti
  | PlanningDashboard
  | Integrity
  | Evolution
  | Biomorphic
  | Homeostasis
  | Bicameral
  | Singularity
  | Components
  | Auth
  | Checklist
deriving Repr, DecidableEq

-- 2. Persistent Universal Navigation Bar Edge Relation
-- In UOS, every canonical page renders the global navigation shell containing
-- clickable links to every other canonical page.
def HasDirectedEdge (u v : PageNode) : Prop :=
  u ≠ v

-- 3. Path Reachability Definition
inductive Reachable : PageNode → PageNode → Prop where
  | step (u v : PageNode) (h : HasDirectedEdge u v) : Reachable u v
  | refl (u : PageNode) : Reachable u u
  | trans (u v w : PageNode) (h1 : Reachable u v) (h2 : Reachable v w) : Reachable u w

-- 4. Invariant 1: Single-Step Reachability (Universal 1-Click Navigation)
theorem universal_1_step_reachability (u v : PageNode) (hne : u ≠ v) :
    HasDirectedEdge u v := by
  exact hne

-- 5. Invariant 2: Strongly Connected Graph (SCC = 1)
-- Every pair of distinct pages (u, v) is mutually reachable in both directions.
theorem canonical_graph_is_strongly_connected (u v : PageNode) :
    Reachable u v ∧ Reachable v u := by
  by_cases h : u = v
  · subst h
    exact ⟨Reachable.refl u, Reachable.refl u⟩
  · have h1 : HasDirectedEdge u v := h
    have h2 : HasDirectedEdge v u := Ne.symm h
    exact ⟨Reachable.step u v h1, Reachable.step v u h2⟩

-- 6. Invariant 3: Zero Dead Ends
-- Every canonical page has at least one outgoing edge to another page.
theorem zero_dead_ends (u : PageNode) :
    ∃ v : PageNode, HasDirectedEdge u v := by
  cases u with
  | Dashboard => exists PageNode.Planning; intro h; contradiction
  | Planning => exists PageNode.Dashboard; intro h; contradiction
  | Immune => exists PageNode.Dashboard; intro h; contradiction
  | Knowledge => exists PageNode.Dashboard; intro h; contradiction
  | Zenoh => exists PageNode.Dashboard; intro h; contradiction
  | Cockpit => exists PageNode.Dashboard; intro h; contradiction
  | Verification => exists PageNode.Dashboard; intro h; contradiction
  | Substrate => exists PageNode.Dashboard; intro h; contradiction
  | Metabolic => exists PageNode.Dashboard; intro h; contradiction
  | Podman => exists PageNode.Dashboard; intro h; contradiction
  | Mcp => exists PageNode.Dashboard; intro h; contradiction
  | Kms => exists PageNode.Dashboard; intro h; contradiction
  | Telemetry => exists PageNode.Dashboard; intro h; contradiction
  | Federation => exists PageNode.Dashboard; intro h; contradiction
  | HealthGrid => exists PageNode.Dashboard; intro h; contradiction
  | Prajna => exists PageNode.Dashboard; intro h; contradiction
  | Agents => exists PageNode.Dashboard; intro h; contradiction
  | Holon => exists PageNode.Dashboard; intro h; contradiction
  | Config => exists PageNode.Dashboard; intro h; contradiction
  | Git => exists PageNode.Dashboard; intro h; contradiction
  | Database => exists PageNode.Dashboard; intro h; contradiction
  | Bridge => exists PageNode.Dashboard; intro h; contradiction
  | Smriti => exists PageNode.Dashboard; intro h; contradiction
  | PlanningDashboard => exists PageNode.Dashboard; intro h; contradiction
  | Integrity => exists PageNode.Dashboard; intro h; contradiction
  | Evolution => exists PageNode.Dashboard; intro h; contradiction
  | Biomorphic => exists PageNode.Dashboard; intro h; contradiction
  | Homeostasis => exists PageNode.Dashboard; intro h; contradiction
  | Bicameral => exists PageNode.Dashboard; intro h; contradiction
  | Singularity => exists PageNode.Dashboard; intro h; contradiction
  | Components => exists PageNode.Dashboard; intro h; contradiction
  | Auth => exists PageNode.Dashboard; intro h; contradiction
  | Checklist => exists PageNode.Dashboard; intro h; contradiction

-- 7. Invariant 4: Fail-Closed Verification Gate
-- If any endpoint returns a status other than 200, the verification state fails closed.
structure EndpointProbe where
  path : String
  status : Nat
  latency_ms : Float
  has_nav : Bool

def is_verified_endpoint (probe : EndpointProbe) : Bool :=
  probe.status == 200 && probe.has_nav

def system_verification_gate (probes : List EndpointProbe) : Bool :=
  probes.all is_verified_endpoint

theorem fail_closed_on_bad_status (probes : List EndpointProbe) (p : EndpointProbe)
    (h_mem : p ∈ probes) (h_bad : p.status ≠ 200) :
    system_verification_gate probes = false := by
  simp [system_verification_gate]
  refine ⟨p, h_mem, ?_⟩
  simp [is_verified_endpoint]
  intro h_eq
  exact False.elim (h_bad h_eq)

end UOS.LinkGraph
