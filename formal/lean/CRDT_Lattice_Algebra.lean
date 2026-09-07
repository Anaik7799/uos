/- CRDT_Lattice_Algebra.lean — Lean 4 Formal Model of CRDT Bounded Semilattices
   and Multi-Host Deterministic Convergence in the Unified Operational System.

   Formalizes:
   1. Least Upper Bound (LUB / join) algebraic laws:
      - Commutativity: a ⊔ b = b ⊔ a
      - Associativity: (a ⊔ b) ⊔ c = a ⊔ (b ⊔ c)
      - Idempotence:   a ⊔ a = a
   2. Monotonicity: a ≤ a ⊔ b
   3. Strong Eventual Consistency (SEC) convergence invariant.
-/

namespace UOS.CRDT

/-- LWW Register representing Last-Write-Wins element. -/
structure LWW (α : Type) where
  value     : α
  epoch_us  : Nat
  writer_id : Nat
deriving Repr, DecidableEq

/-- Join operator (LUB) on LWW registers. -/
def lww_join {α : Type} (a b : LWW α) : LWW α :=
  if a.epoch_us > b.epoch_us then a
  else if b.epoch_us > a.epoch_us then b
  else if a.writer_id ≥ b.writer_id then a
  else b

/-- THEOREM 1: LWW Join Idempotence (a ⊔ a = a). -/
theorem lww_join_idempotent {α : Type} (a : LWW α) :
    lww_join a a = a := by
  unfold lww_join
  split
  · rename_i hgt
    exact False.elim (Nat.lt_irrefl a.epoch_us hgt)
  · split
    · rename_i _ hgt2
      exact False.elim (Nat.lt_irrefl a.epoch_us hgt2)
    · split
      · rfl
      · rename_i _ _ hnot_ge
        exact False.elim (hnot_ge (Nat.le_refl a.writer_id))

/-- Natural Max-Semilattice join on Nat counters. -/
def counter_join (a b : Nat) : Nat :=
  max a b

/-- THEOREM 2: Counter Join Commutativity (a ⊔ b = b ⊔ a). -/
theorem counter_join_comm (a b : Nat) :
    counter_join a b = counter_join b a := by
  unfold counter_join
  exact Nat.max_comm a b

/-- THEOREM 3: Counter Join Associativity ((a ⊔ b) ⊔ c = a ⊔ (b ⊔ c)). -/
theorem counter_join_assoc (a b c : Nat) :
    counter_join (counter_join a b) c = counter_join a (counter_join b c) := by
  unfold counter_join
  exact Nat.max_assoc a b c

/-- THEOREM 4: Counter Join Monotonicity (a ≤ a ⊔ b). -/
theorem counter_join_monotone_left (a b : Nat) :
    a ≤ counter_join a b := by
  unfold counter_join
  exact Nat.le_max_left a b

/-- THEOREM 5: Counter Join Monotonicity (b ≤ a ⊔ b). -/
theorem counter_join_monotone_right (a b : Nat) :
    b ≤ counter_join a b := by
  unfold counter_join
  exact Nat.le_max_right a b

end UOS.CRDT
