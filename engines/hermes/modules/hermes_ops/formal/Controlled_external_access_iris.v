(* Iris separation-logic obligations for the R31 resource scope. These prove
   generic ownership algebra only. Linking them to the OCaml interpreter needs
   a semantic refinement proof and remains a separate required receipt. *)

From iris.proofmode Require Import proofmode.
From iris.base_logic Require Import base_logic.

Section external_access_resource_scope.
  Context {M : ucmra}.

  Lemma resource_scope_reorders_without_duplication
      (database statement socket : uPred M) :
    database ∗ statement ∗ socket ⊢ socket ∗ (statement ∗ database).
  Proof. iIntros "(Hdb & Hstmt & Hsocket)". iFrame. Qed.

  Lemma owned_cleanup_consumes_obligation
      (resource closed : uPred M) :
    resource ∗ (resource -∗ closed) ⊢ closed.
  Proof. iIntros "[Hresource Hclose]". iApply "Hclose". iFrame. Qed.

  Lemma readback_preserves_independent_authority
      (effect_receipt readback policy : uPred M) :
    effect_receipt ∗ readback ∗ policy ⊢ policy ∗ readback ∗ effect_receipt.
  Proof. iIntros "(Heffect & Hreadback & Hpolicy)". iFrame. Qed.
End external_access_resource_scope.
