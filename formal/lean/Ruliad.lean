import Std
/-!
Ruliad.lean: ruliology core — abstract rewriting, Newman's lemma, causal
invariance as confluence, the 2.50-bit entropy gate as integer arithmetic, and
the deployed vision diagnosis rules with both of their stated laws proved.

This file is the **Mathlib-free subset**, so `tools/lean-offline-gate` can check
it with the pinned Lean 4.33.0 alone and no dependency tree. The full library is the
Lake package at `formal/lean/ruliad/`, which requires Mathlib `v4.33.0`:

  `.Core`            rewriting, Newman, confluence
  `.Diagrams`        the confluence lattice, in cslib's vocabulary
  `.Rulial`          the stratified ruliad, emulation, no universal type
  `.Multiway`        verified model of `ecology/multiway.gleam`
  `.Hypergraph`      Wolfram-model hypergraph rewriting
  `.Branchial`       branchial space; the Mojo distance kernel's formula
  `.Causal`          runs, foliations, well-defined cosmological time
  `.Entropy`         real-valued Shannon entropy; the 2.50-bit gate
  `.CausalInvariance` order independence; blame laws
  `.Vision`          the deployed diagnosis rules
  `.Irreducibility`  bounded search; no uniform step bound
  `.Service`         the deployed service surface

Identification that makes the Wolfram-model vocabulary provable rather than
evocative: a rule system is a relation, a multiway graph is its
reflexive-transitive closure, and **causal invariance is exactly confluence**.

Newman's lemma is proved here because **Mathlib does not have it**: Mathlib's
`Relation.church_rosser` requires the *strong* diamond property, which is
strictly stronger than local confluence, and local confluence is the condition a
bounded per-rule-pair check can actually discharge. `leanprover/cslib` does have
it (`LocallyConfluent.terminating_toConfluent`), but pins Lean 4.36.0-rc2
against this repository's 4.33.0, and a Lake workspace has one toolchain.

Zero `sorry`, zero added axioms. CANDIDATE formal model, REPORT_ONLY: it proves
statements about models, is not runtime evidence, and grants no admission.
EV ceiling 93; EV-94..109 remain NOT_ADMITTED; no EV number minted.

References: Newman (1942); Huet, *Confluent Reductions* (1980); Baader & Nipkow,
*Term Rewriting and All That* (1998). Lean 4 precedent, surveyed and read for
comparison, none vendored (all pin a different toolchain — see
`governance/sources/*-lean-ruliad-mathlib-dependency-ingestion.json`):
`leanprover/cslib` (Apache-2.0), `Arthur742Ramos/Metatheory` (MIT),
`codyroux/traat-lean` (MIT), `nomeata/lean-simplc` (Apache-2.0),
`svkampen/msc-thesis` (no licence file, so read-only).
-/

namespace Ruliad

/-! ### 1. Abstract rewriting: the only honest core of "the ruliad" -/

abbrev Rel (α : Type) := α → α → Prop

/-- Reflexive-transitive closure. Mathlib's `Relation.ReflTransGen` is unavailable
    in this standalone toolchain, so it is rebuilt here. -/
inductive Steps {α : Type} (R : Rel α) : α → α → Prop where
  | refl (a : α) : Steps R a a
  | tail {a b c : α} : Steps R a b → R b c → Steps R a c

theorem Steps.single {α : Type} {R : Rel α} {a b : α} (h : R a b) : Steps R a b :=
  Steps.tail (Steps.refl a) h

theorem Steps.trans {α : Type} {R : Rel α} {a b c : α}
    (hab : Steps R a b) (hbc : Steps R b c) : Steps R a c := by
  induction hbc with
  | refl => exact hab
  | tail _ hr ih => exact Steps.tail ih hr

theorem Steps.head {α : Type} {R : Rel α} {a b c : α}
    (h : R a b) (hbc : Steps R b c) : Steps R a c :=
  Steps.trans (Steps.single h) hbc

def Joinable {α : Type} (R : Rel α) (a b : α) : Prop :=
  ∃ d, Steps R a d ∧ Steps R b d

theorem Joinable.refl {α : Type} {R : Rel α} (a : α) : Joinable R a a :=
  ⟨a, Steps.refl a, Steps.refl a⟩

theorem Joinable.symm {α : Type} {R : Rel α} {a b : α}
    (h : Joinable R a b) : Joinable R b a :=
  let ⟨d, ha, hb⟩ := h; ⟨d, hb, ha⟩

/-- One step from each side can be joined. -/
def LocallyConfluent {α : Type} (R : Rel α) : Prop :=
  ∀ a b c, R a b → R a c → Joinable R b c

/-- Any two computations from a common state can be brought back together.
    This IS Wolfram's causal invariance, stated as classical confluence. -/
def Confluent {α : Type} (R : Rel α) : Prop :=
  ∀ a b c, Steps R a b → Steps R a c → Joinable R b c

/-- No infinite forward rewriting chain. -/
def Terminating {α : Type} (R : Rel α) : Prop :=
  WellFounded (fun x y => R y x)

def NormalForm {α : Type} (R : Rel α) (a : α) : Prop := ∀ b, ¬ R a b

theorem Steps.eq_of_normalForm {α : Type} {R : Rel α} {a b : α}
    (hn : NormalForm R a) (h : Steps R a b) : a = b := by
  induction h with
  | refl => rfl
  | tail _ hr ih => subst ih; exact absurd hr (hn _)

/-- Confluence gives uniqueness of normal forms: the observer-independent
    "answer" of a rule system, if it has one. -/
theorem unique_normalForm {α : Type} {R : Rel α} (hc : Confluent R) {a b c : α}
    (hab : Steps R a b) (hac : Steps R a c)
    (hb : NormalForm R b) (hcnf : NormalForm R c) : b = c := by
  have ⟨d, hbd, hcd⟩ := hc a b c hab hac
  have h1 : b = d := Steps.eq_of_normalForm hb hbd
  have h2 : c = d := Steps.eq_of_normalForm hcnf hcd
  exact h1.trans h2.symm

/-! ### 2. Newman's lemma: local confluence + termination ⇒ causal invariance

    This is the load-bearing theorem. Local confluence is a finite, per-rule-pair
    check; confluence is a statement about the whole infinite computation space.
    Newman's lemma is what lets a bounded check license the global claim. -/

/-- Head decomposition. `Steps` is built tail-first, so this is the lemma that
    makes induction from the front possible. -/
theorem Steps.cases_head {α : Type} {R : Rel α} {a c : α} (h : Steps R a c) :
    a = c ∨ ∃ b, R a b ∧ Steps R b c := by
  induction h with
  | refl => exact Or.inl rfl
  | tail hs hr ih =>
    cases ih with
    | inl heq => subst heq; exact Or.inr ⟨_, hr, Steps.refl _⟩
    | inr hex =>
      let ⟨m, ham, hmb⟩ := hex
      exact Or.inr ⟨m, ham, Steps.tail hmb hr⟩

theorem newman {α : Type} {R : Rel α}
    (ht : Terminating R) (hlc : LocallyConfluent R) : Confluent R := by
  intro a
  refine WellFounded.induction ht
    (C := fun x => ∀ b c, Steps R x b → Steps R x c → Joinable R b c) a ?_
  intro x ih b c hxb hxc
  cases Steps.cases_head hxb with
  | inl hxb_eq => subst hxb_eq; exact ⟨c, hxc, Steps.refl c⟩
  | inr hb =>
    let ⟨x1, hx1, h1b⟩ := hb
    cases Steps.cases_head hxc with
    | inl hxc_eq => subst hxc_eq; exact ⟨b, Steps.refl b, hxb⟩
    | inr hc =>
      let ⟨x2, hx2, h2c⟩ := hc
      let ⟨d, h1d, h2d⟩ := hlc x x1 x2 hx1 hx2
      let ⟨e, hbe, hde⟩ := ih x1 hx1 b d h1b h1d
      let ⟨f, hcf, hef⟩ := ih x2 hx2 c e h2c (Steps.trans h2d hde)
      exact ⟨f, Steps.trans hbe hef, hcf⟩

/-- Church-Rosser: convertibility collapses under confluence. -/
inductive Conv {α : Type} (R : Rel α) : α → α → Prop where
  | refl (a : α) : Conv R a a
  | fwd {a b c : α} : Conv R a b → R b c → Conv R a c
  | bwd {a b c : α} : Conv R a b → R c b → Conv R a c


theorem church_rosser {α : Type} {R : Rel α} (hc : Confluent R) {a b : α}
    (h : Conv R a b) : Joinable R a b := by
  induction h with
  | refl => exact Joinable.refl _
  | fwd _ hr ih =>
    let ⟨d, had, hbd⟩ := ih
    let ⟨e, hde, hce⟩ := hc _ _ _ hbd (Steps.single hr)
    exact ⟨e, Steps.trans had hde, hce⟩
  | bwd _ hr ih =>
    let ⟨d, had, hbd⟩ := ih
    exact ⟨d, had, Steps.head hr hbd⟩

/-! ### 4. The 2.50-bit entropy gate, as integer arithmetic

The system gates branchial / fractal-layer entropy at `H ≥ 2.50 bits`
(`CHK-09-MATH`, `KMP-ENTROPY` in `tools/km-gate`). Without Mathlib there are no
reals here, so the threshold is carried by the equivalent integer statement:
`log₂ k ≥ 5/2` iff `2^5 ≤ k^2`. The whole gate turns on `25 < 32`.

The real-valued development, with Shannon entropy, Gibbs' inequality and the
maximum-entropy bound, is in `formal/lean/ruliad/Ruliad/Entropy.lean`. -/

/-- `log₂ k ≥ 5/2`, stated without reals: `2^5 ≤ k^2`. -/
def Log2AtLeastFiveHalves (k : Nat) : Prop := 2 ^ 5 ≤ k ^ 2

instance (k : Nat) : Decidable (Log2AtLeastFiveHalves k) := by
  unfold Log2AtLeastFiveHalves; infer_instance

/-- **The 2.50-bit floor forces at least six occupied branches.** Five or fewer
classes cannot reach the threshold however the mass is arranged, so a failing
`KMP-ENTROPY` over a five-way split cannot be fixed by reweighting. -/
theorem six_branches_of_gate {k : Nat} (h : Log2AtLeastFiveHalves k) : 6 ≤ k := by
  match Nat.lt_or_ge k 6 with
  | Or.inr hge => exact hge
  | Or.inl hlt =>
    have hk : k ≤ 5 := by omega
    have hsq : k ^ 2 ≤ 5 ^ 2 := Nat.pow_le_pow_left hk 2
    have h32 : (32 : Nat) ≤ 25 :=
      calc (32 : Nat) = 2 ^ 5 := by decide
        _ ≤ k ^ 2 := h
        _ ≤ 5 ^ 2 := hsq
        _ = 25 := by decide
    omega

/-- Contrapositive, in the form a gate implementation uses. -/
theorem gate_fails_of_few_branches {k : Nat} (hk : k ≤ 5) : ¬ Log2AtLeastFiveHalves k :=
  fun h => absurd (six_branches_of_gate h) (by omega)

/-- Sanity: a uniform distribution over 8 branches clears the floor (`log₂ 8 = 3`). -/
theorem gate_holds_at_eight : Log2AtLeastFiveHalves 8 := by decide

/-- And 5 does not. -/
theorem gate_fails_at_five : ¬ Log2AtLeastFiveHalves 5 := by decide

/-! ### 5. The deployed vision diagnosis rules, with both laws proved

`engines/hermes/modules/hermes_vision/vision_rules.ml` turns six stage verdicts
into a blame assignment under two stated laws, and `vision_ruliad.ml` checks
them by enumerating 3^6 = 729 states. Transcribed below, with both laws proved
for **every** observation — the case analysis has the same 729 leaves, each
closed by `rfl`, but the conclusion is a universally quantified theorem rather
than a report about one run.

Correspondence: `Stage`/`upstream`/`index` from `vision_ontology.ml:5,62`;
`fire` from `vision_rules.ml:23-45`; `infer` from `:47-50`; `rootCause` from
`:55-64` (earliest blamed stage by index). -/

namespace Vision

/-- The six pipeline stages, in ontology order. -/
inductive Stage where
  | source | encode | package | serve | play | observe
  deriving DecidableEq, Repr

/-- `vision_ontology.ml` `stage_index`. -/
def Stage.index : Stage → Nat
  | .source => 0 | .encode => 1 | .package => 2
  | .serve => 3 | .play => 4 | .observe => 5

/-- `vision_ontology.ml:62` `upstream`. `Source` is its own upstream: the head
of the chain has nothing to inherit a failure from. -/
def Stage.upstream : Stage → Stage
  | .source => .source | .encode => .source | .package => .encode
  | .serve => .package | .play => .serve | .observe => .play

/-- `vision_ontology.ml:5` `stages`, in pipeline order. -/
def stages : List Stage := [.source, .encode, .package, .serve, .play, .observe]

/-- A stage's measured verdict. -/
inductive Verdict where
  | live | absent | unknown
  deriving DecidableEq, Repr

/-- A complete observation of the pipeline: the 3^6 state space
`vision_ruliad.ml` enumerates. -/
structure Obs where
  source : Verdict
  encode : Verdict
  package : Verdict
  serve : Verdict
  play : Verdict
  observe : Verdict
  deriving DecidableEq, Repr

def Obs.get (o : Obs) : Stage → Verdict
  | .source => o.source | .encode => o.encode | .package => o.package
  | .serve => o.serve | .play => o.play | .observe => o.observe

/-- `vision_rules.mli` `conclusion`. -/
inductive Conclusion where
  | blame (s : Stage)
  | cascade (s : Stage) (from_ : Stage)
  | unmeasured (s : Stage)
  | healthy
  deriving DecidableEq, Repr

/-- `vision_rules.ml:23` `fire`, transcribed. -/
def fire (o : Obs) (s : Stage) : List Conclusion :=
  let up := s.upstream
  match o.get s with
  | .unknown => [.unmeasured s]
  | .live => []
  | .absent =>
    if up = s then [.blame s]
    else
      match o.get up with
      | .absent => [.cascade s up]
      | .unknown => [.unmeasured s]
      | .live => [.blame s]

/-- `vision_rules.ml:47` `infer`. A total observation always yields facts, so
the empty conclusion set means healthy. -/
def infer (o : Obs) : List Conclusion :=
  match stages.flatMap (fire o) with
  | [] => [.healthy]
  | cs => cs

/-- `vision_rules.ml:55` `root_cause`: the earliest blamed stage by index. -/
def rootCause (o : Obs) : Option Stage :=
  (infer o).foldl
    (fun acc c =>
      match acc, c with
      | none, .blame s => some s
      | some a, .blame s => if s.index < a.index then some s else some a
      | _, _ => acc)
    none

/-! ## The two laws

Both are stated as decidable predicates and proved for **every** observation.
The case analysis has 3^6 = 729 leaves — the same space `vision_ruliad.ml`
enumerates — but the conclusion is a universally quantified theorem. -/

/-- Law 2: never blame a stage that was not measured. Strengthened to what the
code actually guarantees: a blamed stage is `ABSENT`, so neither `LIVE` nor
`UNKNOWN` is ever accused. -/
def lawBlamedIsAbsent (o : Obs) : Bool :=
  match rootCause o with
  | none => true
  | some s => o.get s == Verdict.absent

/-- Law 1, the cascade law: never blame a stage whose upstream also failed. The
head of the chain is exempt, because it has no upstream. -/
def lawNoCascadeBlame (o : Obs) : Bool :=
  match rootCause o with
  | none => true
  | some s => (s.upstream == s) || !(o.get s.upstream == Verdict.absent)

/-- A fully healthy pipeline blames nobody. -/
def lawHealthyBlamesNobody (o : Obs) : Bool :=
  if (stages.all fun s => o.get s == Verdict.live) then rootCause o == none else true

/-- A failed head of chain is always the root cause: nothing upstream can
explain it away. -/
def lawAbsentSourceIsRoot (o : Obs) : Bool :=
  if o.get .source == Verdict.absent then rootCause o == some Stage.source else true

/-- **Law 2 holds for every observation.** -/
theorem blamed_is_absent (o : Obs) : lawBlamedIsAbsent o = true := by
  obtain ⟨a, b, c, d, e, f⟩ := o
  cases a <;> cases b <;> cases c <;> cases d <;> cases e <;> cases f <;> rfl

/-- **Law 1, the cascade law, holds for every observation.** -/
theorem no_cascade_blame (o : Obs) : lawNoCascadeBlame o = true := by
  obtain ⟨a, b, c, d, e, f⟩ := o
  cases a <;> cases b <;> cases c <;> cases d <;> cases e <;> cases f <;> rfl

theorem healthy_blames_nobody (o : Obs) : lawHealthyBlamesNobody o = true := by
  obtain ⟨a, b, c, d, e, f⟩ := o
  cases a <;> cases b <;> cases c <;> cases d <;> cases e <;> cases f <;> rfl

theorem absent_source_is_root (o : Obs) : lawAbsentSourceIsRoot o = true := by
  obtain ⟨a, b, c, d, e, f⟩ := o
  cases a <;> cases b <;> cases c <;> cases d <;> cases e <;> cases f <;> rfl


end Vision

end Ruliad
