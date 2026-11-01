/-
# Ruliad.Render — a visualization proved to be a faithful picture

Lean has exactly one graphics stack: **ProofWidgets4** (`Data/Svg.lean`,
`Component/ForceGraphDisplay.lean`, `GraphvizDisplay`, `PenroseDiagram`,
`InteractiveSvg`). It arrives transitively with Mathlib, so no extra dependency
is needed. There is no Lean plotting library; this is the whole landscape.

What makes this module worth having is not that it draws a graph. It is that
the drawing is **proved to be a faithful picture of the object it claims to
depict**:

* `vertices_card` / `edges_card` — the rendering invents nothing and drops
  nothing: one vertex per state, one edge per transition.
* `vertex_ids_nodup` — vertex identifiers are unique, which
  `ForceGraphDisplay.Vertex.id` *requires*. The obligation is discharged by
  `Ruliad.Multiway.explore_states_nodup`, not assumed.
* `rendered_edge_is_real_rewrite` — every drawn edge corresponds to an actual
  one-step rewrite. Composed with `Multiway.explore_edges_sound`, a line in the
  picture is a theorem about the rule set, not an artefact of the layout.

The UOS SciViz contracts (`SC-SCIVIZ-*`) require visualizations and verify them
by browser screenshot. A screenshot shows that *something* rendered. These
theorems show that what rendered is *correct*. They are complementary, and only
the second kind survives a change to the data.
-/
import Ruliad.Multiway
import Ruliad.Branchial
import ProofWidgets.Component.ForceGraphDisplay
import ProofWidgets.Data.Svg

namespace Ruliad.Render

open Ruliad Ruliad.Multiway ProofWidgets

/-! ## Words as vertex identifiers -/

/-- A state's identifier in the rendered graph. -/
def wordId (w : Word) : String := String.ofList w

theorem wordId_injective : Function.Injective wordId := by
  intro a b h
  exact String.ofList_inj.mp h

/-! ## Mapping a multiway graph to ProofWidgets -/

def toVertices (g : Graph) : Array ForceGraphDisplay.Vertex :=
  (g.states.map fun w => ({ id := wordId w } : ForceGraphDisplay.Vertex)).toArray

def toEdges (g : Graph) : Array ForceGraphDisplay.Edge :=
  (g.edges.map fun e =>
    ({ source := wordId e.source, target := wordId e.target } :
      ForceGraphDisplay.Edge)).toArray

/-- The rendered graph, ready for `<ForceGraphDisplay .../>`. -/
def render (g : Graph) : Array ForceGraphDisplay.Vertex × Array ForceGraphDisplay.Edge :=
  (toVertices g, toEdges g)

/-! ## Faithfulness -/

/-- One vertex per state: nothing invented, nothing dropped. -/
theorem vertices_card (g : Graph) : (toVertices g).size = g.states.length := by
  simp [toVertices]

/-- One edge per transition. -/
theorem edges_card (g : Graph) : (toEdges g).size = g.edges.length := by
  simp [toEdges]

/-- Every state appears, identified by its own word. -/
theorem vertex_of_state {g : Graph} {w : Word} (h : w ∈ g.states) :
    ({ id := wordId w } : ForceGraphDisplay.Vertex) ∈ toVertices g := by
  simp only [toVertices, List.mem_toArray, List.mem_map]
  exact ⟨w, h, rfl⟩

/-- **The renderer's precondition, discharged.** `ForceGraphDisplay` requires
unique vertex identifiers; `explore` guarantees them. -/
theorem vertex_ids_nodup {seed : Word} {rs : List Rule} {steps : Nat} {g : Graph}
    (h : explore seed rs steps = .ok g) :
    (g.states.map wordId).Nodup :=
  (explore_states_nodup h).map wordId_injective

/-- **Every drawn edge is a real rewrite.** The picture cannot show a transition
the rule set does not permit. -/
theorem rendered_edge_is_real_rewrite {seed : Word} {rs : List Rule} {steps : Nat}
    {g : Graph} (h : explore seed rs steps = .ok g) :
    ∀ e ∈ g.edges, StepRel rs e.source e.target ∧
      ({ source := wordId e.source, target := wordId e.target } :
        ForceGraphDisplay.Edge) ∈ toEdges g := by
  intro e he
  refine ⟨explore_edges_sound h e he, ?_⟩
  simp only [toEdges, List.mem_toArray, List.mem_map]
  exact ⟨e, he, rfl⟩

/-- And every state drawn is genuinely reachable from the seed, so the picture
has no orphan nodes. -/
theorem rendered_vertex_is_reachable {seed : Word} {rs : List Rule} {steps : Nat}
    {g : Graph} (h : explore seed rs steps = .ok g) :
    ∀ w ∈ g.states, Steps (StepRel rs) seed w := explore_states_reachable h

/-! ## A concrete rendering

The `aa → aba` rule on seed `aa`, two steps. `#html` renders it in the
infoview; the theorems above apply to exactly this graph. -/

def demoRules : List Rule := [{ lhs := "aa".toList, rhs := "aba".toList }]

def demoGraph : Except String Graph := explore "aa".toList demoRules 2

/-- The demo really is a successful exploration, so the faithfulness theorems
are not vacuous here. -/
theorem demoGraph_ok : ∃ g, demoGraph = .ok g := by
  unfold demoGraph explore
  split
  · exact ⟨_, rfl⟩
  · rename_i hb
    exact absurd (by
      refine ⟨by simp, by decide, by omega, by omega,
        by simp [demoRules], by simp [demoRules], ?_⟩
      intro r hr
      simp only [demoRules, List.mem_singleton] at hr
      subst hr
      exact ⟨by simp, by decide, by decide⟩) hb

def demoRendered : Array ForceGraphDisplay.Vertex × Array ForceGraphDisplay.Edge :=
  match demoGraph with
  | .ok g => render g
  | .error _ => (#[], #[])

/-! ## Branchial scatter as SVG

`ProofWidgets.Svg` draws the branchial layer directly: one circle per state,
placed by (step, index). The deployed Mojo kernel's distance formula is
`Ruliad.Branchial.bdist`, with bounds and monotonicity already proved. -/

private def frame : Svg.Frame where
  xmin := 0
  ymin := 0
  xSize := 10
  width := 400
  height := 300

/-- One circle per state, laid out on a row. Positions are presentational; the
*content* — which states exist and which transitions connect them — is the part
carrying theorems. -/
def branchialScatter (g : Graph) : Svg frame :=
  { elements :=
      (g.states.zipIdx.map fun si =>
        (Svg.circle (f := frame)
            (.abs (1.0 + 0.8 * si.2.toFloat) 1.5)
            (.abs 0.25)).setFill ⟨0.0, 0.83, 0.67⟩).toArray }

end Ruliad.Render
