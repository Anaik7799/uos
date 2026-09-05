(* R31 controlled external-access lifecycle and bounded-runtime theorems.
   This artifact is an independent Rocq projection of External_access_runtime.
   A compiled proof is required for credit; source presence is not a receipt. *)

From Coq Require Import Arith Bool Lia List.
Import ListNotations.

Inductive phase : Type :=
| Declared | Validated | Admitted | Prepared | Executed | Current | Refused.

Inductive step : phase -> phase -> Prop :=
| validate_ok : step Declared Validated
| validate_refuse : step Declared Refused
| admit_ok : step Validated Admitted
| admit_refuse : step Validated Refused
| prepare_ok : step Admitted Prepared
| prepare_refuse : step Admitted Refused
| execute_ok : step Prepared Executed
| execute_refuse : step Prepared Refused
| current_ok : step Executed Current
| current_refuse : step Executed Refused.

Theorem executed_has_only_prepared_predecessor :
  forall p, step p Executed -> p = Prepared.
Proof. intros p H; inversion H; reflexivity. Qed.

Theorem prepared_has_only_admitted_predecessor :
  forall p, step p Prepared -> p = Admitted.
Proof. intros p H; inversion H; reflexivity. Qed.

Theorem current_has_only_executed_predecessor :
  forall p, step p Current -> p = Executed.
Proof. intros p H; inversion H; reflexivity. Qed.

Definition enqueue (depth capacity : nat) : nat :=
  if Nat.ltb depth capacity then S depth else depth.

Theorem enqueue_preserves_capacity :
  forall depth capacity,
    depth <= capacity -> enqueue depth capacity <= capacity.
Proof.
  intros depth capacity Hbound.
  unfold enqueue.
  destruct (Nat.ltb depth capacity) eqn:Hlt.
  - apply Nat.ltb_lt in Hlt. lia.
  - exact Hbound.
Qed.

Definition restart_allowed (failures maximum : nat) : bool :=
  Nat.ltb failures maximum.

Theorem restart_storm_escalates :
  forall failures maximum,
    maximum <= failures -> restart_allowed failures maximum = false.
Proof.
  intros failures maximum Hstorm.
  unfold restart_allowed.
  apply Nat.ltb_ge. exact Hstorm.
Qed.

Definition prediction_effect_authority (_recommendation : bool) : bool := false.

Theorem prediction_is_recommendation_only :
  forall recommendation,
    prediction_effect_authority recommendation = false.
Proof. intros recommendation; reflexivity. Qed.

Inductive credit : Type := No_credit | Structural | Behavioral | Differential.

Definition external_success_credit (semantic : credit) (_transport : bool) := semantic.

Theorem transport_cannot_escalate_credit :
  forall semantic transport,
    external_success_credit semantic transport = semantic.
Proof. intros semantic transport; reflexivity. Qed.
