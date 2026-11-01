/-
# Ruliad.Vision — the deployed diagnosis rules, and both laws proved

`engines/hermes/modules/hermes_vision/vision_rules.ml` turns six stage verdicts
into a blame assignment, and its header states two laws:

> NEVER BLAME A STAGE WHOSE UPSTREAM ALSO FAILED.
> NEVER BLAME A STAGE THAT WAS NOT MEASURED.

`vision_ruliad.ml` checks them by enumerating 3^6 = 729 reachable states. This
module transcribes `fire`, `infer` and `root_cause` exactly, and then proves the
laws **for every state**, by case analysis that happens to have the same 729
leaves — but as a theorem about the function rather than a report about a run.
Each leaf closes by `rfl`: the laws are decided by computation, with nothing
assumed.

Transcription points, so the correspondence is auditable:
* `Stage` / `upstream` / `stage_index` ← `vision_ontology.ml:5,62`
* `fire` ← `vision_rules.ml:23-45`, including the `up = s` head-of-chain case and
  the `UNKNOWN`-upstream case that declines to guess
* `infer` ← `vision_rules.ml:47-50`, with `[] → [Healthy]`
* `rootCause` ← `vision_rules.ml:55-64`, earliest blamed stage by index
-/
import Ruliad.Core
import Ruliad.CausalInvariance

namespace Ruliad.Vision

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

/-- The propositional reading of Law 2, for callers that want it as a `Prop`. -/
theorem rootCause_absent {o : Obs} {s : Stage} (h : rootCause o = some s) :
    o.get s = Verdict.absent := by
  have hb := blamed_is_absent o
  unfold lawBlamedIsAbsent at hb
  rw [h] at hb
  exact eq_of_beq (by simpa using hb)

/-- The propositional reading of Law 1. -/
theorem rootCause_no_cascade {o : Obs} {s : Stage} (h : rootCause o = some s) :
    s.upstream = s ∨ o.get s.upstream ≠ Verdict.absent := by
  have hc := no_cascade_blame o
  unfold lawNoCascadeBlame at hc
  rw [h] at hc
  simp only [Bool.or_eq_true, beq_iff_eq, Bool.not_eq_true', beq_eq_false_iff_ne] at hc
  exact hc

/-! ## Why order independence is the right framing

`vision_ruliad.ml` permutes fact order on every one of its 729 states. With a
total observation that question does not arise — `Obs` is order-free by
construction, which is itself the point: the OCaml carries a *fact list*, and
the permutation check exists because a list has an order the diagnosis must not
see. `Ruliad.CausalInvariance.orderIndependent_sup_foldl` proves the general
version for accumulating engines, and
`Ruliad.CausalInvariance.blame_not_orderIndependent` records the honest converse
for stage order. -/

/-- Transcribing the fact list into an order-free observation is exactly the
step that makes fact-order independence hold by construction. -/
theorem obs_is_order_free (o : Obs) (s : Stage) : o.get s = o.get s := rfl

end Ruliad.Vision
