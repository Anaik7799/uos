(* Iris_Smoke.v — proves the Iris installation genuinely works (jidoka: the
   line runs, not just "the package installed"). Loading iris.proofmode pulls
   the whole stack (stdpp, base_logic, proofmode); the lemma exercises a real
   iProp entailment through the Iris proof mode, so a broken install cannot
   pass. Deeper Iris use (separation-logic proofs over harness concurrency
   invariants) is a later leg; this gate is deliberately minimal and honest
   about that. Checked with: coqc Iris_Smoke.v on the rocq-iris side switch. *)

From iris.proofmode Require Import proofmode.
From iris.base_logic Require Import base_logic.

Section smoke.
  Context {M : ucmra}.

  Lemma iris_smoke (P Q : uPred M) : P ∗ Q ⊢ Q ∗ P.
  Proof. iIntros "[HP HQ]". iFrame. Qed.
End smoke.
