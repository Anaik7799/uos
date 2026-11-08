/-
# Ruliad — a formal library for ruliology in the Unified Operational System

```text
  Ruliad.Core               abstract rewriting; Newman; causal invariance = confluence
    |
    +-- Ruliad.Diagrams         the confluence lattice (cslib-aligned names)
    +-- Ruliad.Rulial           the stratified ruliad; emulation; no universal type
    +-- Ruliad.Multiway         verified model of ecology/multiway.gleam (strings)
    +-- Ruliad.Hypergraph       Wolfram-model hypergraph rewriting
    +-- Ruliad.Branchial        branchial relation; the Mojo distance formula
    +-- Ruliad.Causal           runs; foliations; well-defined cosmological time
    +-- Ruliad.CausalGraph      tokenized events; the causal graph is a DAG
    +-- Ruliad.ListDiff         the length_diff lemma Mathlib lacks
    +-- Ruliad.Entropy          Shannon entropy; the 2.50-bit gate
    +-- Ruliad.CausalInvariance order independence; blame laws
    +-- Ruliad.Vision           the deployed diagnosis rules, both laws proved
    +-- Ruliad.Irreducibility   bounded search; no uniform step bound
    +-- Ruliad.Bridge           cslib: definitions coincide; Hindley-Rosen (terminating)
    +-- Ruliad.Render           ProofWidgets: a visualization proved faithful
          |
          +-- Ruliad.Service    the deployed service surface
```

```mermaid
graph TD
  Core["Ruliad.Core<br/>rewriting, Newman, confluence"]
  DG["Ruliad.Diagrams<br/>confluence lattice"]
  RL["Ruliad.Rulial<br/>stratified ruliad, emulation"]
  MW["Ruliad.Multiway<br/>model of multiway.gleam"]
  HG["Ruliad.Hypergraph<br/>Wolfram-model hypergraphs"]
  BR["Ruliad.Branchial<br/>branchial space, Mojo distance"]
  CA["Ruliad.Causal<br/>runs, foliations, time"]
  CG["Ruliad.CausalGraph<br/>tokenized events, causal DAG"]
  LD["Ruliad.ListDiff<br/>length_diff lemma"]
  EN["Ruliad.Entropy<br/>Shannon entropy, 2.50-bit gate"]
  CI["Ruliad.CausalInvariance<br/>order independence, blame laws"]
  VS["Ruliad.Vision<br/>deployed diagnosis laws"]
  IR["Ruliad.Irreducibility<br/>bounded search, no uniform bound"]
  BG["Ruliad.Bridge<br/>cslib alignment, Hindley-Rosen"]
  RN["Ruliad.Render<br/>ProofWidgets, proved-faithful picture"]
  SV["Ruliad.Service<br/>deployed service surface"]
  Core --> DG
  Core --> RL
  Core --> MW
  Core --> HG
  Core --> BR
  Core --> EN
  Core --> CI
  BR --> CA
  CI --> VS
  CA --> IR
  HG --> CG
  LD --> HG
  DG --> BG
  MW --> RN
  MW --> SV
  BR --> SV
  EN --> SV
  CI --> SV
```

Status: candidate formal model. No proof placeholders and no project-declared axioms. It proves things
about models of the deployed code; it is **not** runtime evidence, and it grants
no admission. EV ceiling 93; EV-94..109 remain NOT_ADMITTED; no EV number minted.
-/
import Ruliad.Core
import Ruliad.Diagrams
import Ruliad.Rulial
import Ruliad.Multiway
import Ruliad.Hypergraph
import Ruliad.Branchial
import Ruliad.Causal
import Ruliad.CausalGraph
import Ruliad.ListDiff
import Ruliad.Entropy
import Ruliad.CausalInvariance
import Ruliad.Vision
import Ruliad.Irreducibility
import Ruliad.Bridge
import Ruliad.Render
import Ruliad.Service
import Ruliad.UosCslibSystemWideIntegration

namespace Ruliad

/-! ## The through-line

Local confluence is finitely checkable. Newman upgrades it to causal invariance
over the whole unbounded computation space. Causal invariance gives unique
normal forms, which is the only thing that makes a "collapse path" or a merge
verdict mean anything. Each arrow below is a theorem in this library. -/

/-- The composite claim, end to end: a bounded per-rule-pair check on a
terminating system licenses an observer-independent outcome. Instantiated for
strings (`Ruliad.Multiway.StepRel`) and for Wolfram-model hypergraphs
(`Ruliad.Hypergraph.hypergraph_unique_normal`) without special-casing. -/
theorem ruliology_through_line {α : Type*} {R : α → α → Prop}
    (ht : Terminating R) (hlc : LocallyConfluent R) {a b c : α}
    (hab : Steps R a b) (hac : Steps R a c)
    (hb : NormalForm R b) (hc : NormalForm R c) : b = c :=
  unique_normalForm_of_newman ht hlc hab hac hb hc

end Ruliad
