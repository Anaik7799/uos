/- Preflight_Verdict_Algebra.lean — Lean 4 proofs for the UOS toolchain
   preflight's denotational semantics (SC-NIX-DEVENV-001).

   Companion to:
   - engines/hermes/modules/hermes_toolchain/preflight_algebra.{ml,mli}
   - tools/preflight  (the effectful shell that supplies observations)
   - formal/quint/preflight_receipt.qnt  (temporal receipt model)

   What is proved here, and what is NOT:

   PROVED — the verdict algebra is a bounded commutative idempotent monoid with
   an absorbing element, so "fail closed" is a CONSEQUENCE of absorption rather
   than a discipline re-applied at each call site; findings accumulate, so a
   composite failure names every failing arm; a composite passes iff every
   component does; and receipt validity is antitone in age and destroyed by any
   digest change.

   NOT PROVED — that the shell observes correctly. Whether `erl` really ran, or
   what it printed, is empirical evidence from tools/preflight, not a theorem.
   The split is deliberate: this file is about MEANING, and only meaning is
   provable. Per canonical policy section 7 a formal result that oversteps its
   invocation carries no authority, so the boundary is stated rather than
   blurred.

   No `sorry`, no `axiom`, no Mathlib dependency.
-/

namespace UOS.Preflight

/-- A finding names the arm and entrypoint that failed. Its payload is opaque
    here; only its identity matters to the algebra. -/
structure Finding where
  arm : String
  name : String
  detail : String
  deriving DecidableEq, Repr

/-- The verdict domain: a two-point lattice ordered `fail < pass`, with failures
    carrying an accumulating list of findings. There is deliberately NO
    `unknown` constructor — an unrepresentable third state cannot be silently
    treated as success. -/
inductive Verdict where
  | pass : Verdict
  | fail : List Finding → Verdict
  deriving Repr

namespace Verdict

/-- Meet: conjunction of arms. `pass` is the identity, `fail` absorbs, and
    findings concatenate. -/
def meet : Verdict → Verdict → Verdict
  | pass,    pass    => pass
  | pass,    fail f  => fail f
  | fail f,  pass    => fail f
  | fail f,  fail g  => fail (f ++ g)

def isPass : Verdict → Bool
  | pass   => true
  | fail _ => false

def findings : Verdict → List Finding
  | pass   => []
  | fail f => f

def meetAll (vs : List Verdict) : Verdict :=
  vs.foldl meet pass

/-! ### The semilattice laws -/

theorem meet_pass_right (a : Verdict) : meet a pass = a := by
  cases a <;> rfl

theorem meet_pass_left (a : Verdict) : meet pass a = a := by
  cases a <;> rfl

/-- Associativity holds ON THE NOSE, because list append is associative. -/
theorem meet_assoc (a b c : Verdict) :
    meet (meet a b) c = meet a (meet b c) := by
  cases a <;> cases b <;> cases c <;> simp [meet, List.append_assoc]

/-- Commutativity holds up to the ORDER of accumulated findings, so it is stated
    on the observable verdict. This mirrors the OCaml law exactly: swapping two
    arms cannot change whether the run passed, only the order in which the
    failures are reported. -/
theorem meet_comm_isPass (a b : Verdict) :
    isPass (meet a b) = isPass (meet b a) := by
  cases a <;> cases b <;> rfl

theorem meet_idem_isPass (a : Verdict) : isPass (meet a a) = isPass a := by
  cases a <;> rfl

/-- `fail` is absorbing: this single theorem is why the whole preflight is
    fail-closed. Every arm that cannot produce positive evidence denotes `fail`,
    and one `fail` anywhere drags the composite down, regardless of position. -/
theorem fail_absorbs_left (fs : List Finding) (a : Verdict) :
    isPass (meet (fail fs) a) = false := by
  cases a <;> rfl

theorem fail_absorbs_right (fs : List Finding) (a : Verdict) :
    isPass (meet a (fail fs)) = false := by
  cases a <;> rfl

/-- A composite passes iff both components do. -/
theorem meet_isPass_iff (a b : Verdict) :
    isPass (meet a b) = (isPass a && isPass b) := by
  cases a <;> cases b <;> rfl

/-! ### Composition over a list of arms -/

theorem meetAll_nil : meetAll [] = pass := rfl

private theorem foldl_pass_of_all
    (vs : List Verdict) (acc : Verdict) :
    isPass (vs.foldl meet acc) = (isPass acc && vs.all isPass) := by
  induction vs generalizing acc with
  | nil => simp
  | cons v rest ih =>
      rw [List.foldl_cons, ih (meet acc v), meet_isPass_iff acc v,
        List.all_cons, Bool.and_assoc]

/-- The property the entire gate rests on: the run passes exactly when every
    arm passes. One failing arm anywhere — in any position — fails the run. -/
theorem meetAll_isPass_iff_all (vs : List Verdict) :
    isPass (meetAll vs) = vs.all isPass := by
  simpa [meetAll, isPass] using foldl_pass_of_all vs pass

/-- Corollary, in the form the shell actually needs: if any arm fails, the
    composite fails. -/
theorem meetAll_fails_of_mem_fail (vs : List Verdict) (v : Verdict)
    (hmem : v ∈ vs) (hv : isPass v = false) :
    isPass (meetAll vs) = false := by
  rw [meetAll_isPass_iff_all]
  cases h : vs.all isPass with
  | false => rfl
  | true =>
      have hv' := List.all_eq_true.mp h v hmem
      rw [hv] at hv'
      exact Bool.noConfusion hv'

/-! ### Receipts

    A cached verdict is evidence about a SPECIFIC checker reading a SPECIFIC
    resolver table. Validity conjoins four independent conditions through the
    same meet, so the absorption theorem above governs it too. -/

structure Receipt where
  status : Verdict
  epoch : Nat
  checkerDigest : String
  tableDigest : String

/-- Freshness is a Nat comparison, which makes "a receipt from the future" and
    "a stale receipt" the same refusal rather than two cases. -/
def fresh (r : Receipt) (now maxAge : Nat) : Bool :=
  now ≥ r.epoch && now - r.epoch ≤ maxAge

def receiptValid (r : Receipt) (now maxAge : Nat)
    (checker table : String) : Bool :=
  isPass r.status && fresh r now maxAge &&
    (r.checkerDigest == checker) && (r.tableDigest == table)

/-- Any change to the checker digest invalidates the receipt at EVERY age. This
    is what stops a cached PASS lending its confidence to code it never saw. -/
theorem checker_change_invalidates
    (r : Receipt) (now maxAge : Nat) (checker table : String)
    (h : (r.checkerDigest == checker) = false) :
    receiptValid r now maxAge checker table = false := by
  simp [receiptValid, h]

theorem table_change_invalidates
    (r : Receipt) (now maxAge : Nat) (checker table : String)
    (h : (r.tableDigest == table) = false) :
    receiptValid r now maxAge checker table = false := by
  simp [receiptValid, h]

/-- A cached FAIL is never valid, however fresh and however matched. -/
theorem cached_fail_never_valid
    (r : Receipt) (now maxAge : Nat) (checker table : String)
    (h : isPass r.status = false) :
    receiptValid r now maxAge checker table = false := by
  simp [receiptValid, h]

/-- Validity is antitone in age: once invalid through staleness, always invalid.
    Stated as: if the receipt is invalid at `now₁ ≤ now₂` *because of age*, it is
    invalid at `now₂`. -/
theorem fresh_antitone (r : Receipt) (maxAge now₁ now₂ : Nat)
    (hle : now₁ ≤ now₂) (h : fresh r now₂ maxAge = true) :
    fresh r now₁ maxAge = true ∨ now₁ < r.epoch := by
  by_cases hge : now₁ ≥ r.epoch
  · left
    simp only [fresh, Bool.and_eq_true, decide_eq_true_eq] at h ⊢
    refine ⟨hge, ?_⟩
    exact Nat.le_trans (Nat.sub_le_sub_right hle r.epoch) h.2
  · right
    omega

/-! ### Axiom audit

    Printed at check time so the evidence is in the run, not in a claim. A
    theorem resting on `sorryAx` carries zero authority under canonical policy
    section 7; these must show only Lean's standard axioms. -/

#print axioms meet_assoc
#print axioms meet_isPass_iff
#print axioms fail_absorbs_left
#print axioms meetAll_isPass_iff_all
#print axioms meetAll_fails_of_mem_fail
#print axioms checker_change_invalidates
#print axioms table_change_invalidates
#print axioms cached_fail_never_valid
#print axioms fresh_antitone

end Verdict
end UOS.Preflight
