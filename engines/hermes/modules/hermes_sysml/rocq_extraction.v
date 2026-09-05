Require Import Coq.Strings.String.
Require Import Coq.Bool.Bool.

Inductive ooda_state : Type :=
  | Idle
  | Observe
  | Orient
  | Decide
  | Act.

Record context : Type := mk_context {
  anomaly_detected : bool;
  data_ready : bool;
  decision_made : bool;
  action_complete : bool
}.

Definition next_state (s : ooda_state) (ctx : context) : ooda_state :=
  if anomaly_detected ctx then
    Observe
  else
    match s with
    | Idle => if data_ready ctx then Observe else Idle
    | Observe => if data_ready ctx then Orient else Observe
    | Orient => if decision_made ctx then Decide else Orient
    | Decide => if decision_made ctx then Act else Decide
    | Act => if action_complete ctx then Idle else Act
    end.

(* Full Envelope Verification *)

Theorem anomaly_always_overrides : forall s ctx,
  anomaly_detected ctx = true ->
  next_state s ctx = Observe.
Proof.
  intros s ctx H.
  unfold next_state.
  rewrite H.
  reflexivity.
Qed.

Theorem normal_transition_idle_observe : forall ctx,
  anomaly_detected ctx = false ->
  data_ready ctx = true ->
  next_state Idle ctx = Observe.
Proof.
  intros ctx H1 H2; unfold next_state; rewrite H1, H2; reflexivity.
Qed.

Theorem normal_transition_idle_stuck : forall ctx,
  anomaly_detected ctx = false ->
  data_ready ctx = false ->
  next_state Idle ctx = Idle.
Proof.
  intros ctx H1 H2; unfold next_state; rewrite H1, H2; reflexivity.
Qed.

Theorem normal_transition_observe_orient : forall ctx,
  anomaly_detected ctx = false ->
  data_ready ctx = true ->
  next_state Observe ctx = Orient.
Proof.
  intros ctx H1 H2; unfold next_state; rewrite H1, H2; reflexivity.
Qed.

Theorem normal_transition_observe_stuck : forall ctx,
  anomaly_detected ctx = false ->
  data_ready ctx = false ->
  next_state Observe ctx = Observe.
Proof.
  intros ctx H1 H2; unfold next_state; rewrite H1, H2; reflexivity.
Qed.

Theorem normal_transition_orient_decide : forall ctx,
  anomaly_detected ctx = false ->
  decision_made ctx = true ->
  next_state Orient ctx = Decide.
Proof.
  intros ctx H1 H2; unfold next_state; rewrite H1, H2; reflexivity.
Qed.

Theorem normal_transition_orient_stuck : forall ctx,
  anomaly_detected ctx = false ->
  decision_made ctx = false ->
  next_state Orient ctx = Orient.
Proof.
  intros ctx H1 H2; unfold next_state; rewrite H1, H2; reflexivity.
Qed.

Theorem normal_transition_decide_act : forall ctx,
  anomaly_detected ctx = false ->
  decision_made ctx = true ->
  next_state Decide ctx = Act.
Proof.
  intros ctx H1 H2; unfold next_state; rewrite H1, H2; reflexivity.
Qed.

Theorem normal_transition_decide_stuck : forall ctx,
  anomaly_detected ctx = false ->
  decision_made ctx = false ->
  next_state Decide ctx = Decide.
Proof.
  intros ctx H1 H2; unfold next_state; rewrite H1, H2; reflexivity.
Qed.

Theorem normal_transition_act_idle : forall ctx,
  anomaly_detected ctx = false ->
  action_complete ctx = true ->
  next_state Act ctx = Idle.
Proof.
  intros ctx H1 H2; unfold next_state; rewrite H1, H2; reflexivity.
Qed.

Theorem normal_transition_act_stuck : forall ctx,
  anomaly_detected ctx = false ->
  action_complete ctx = false ->
  next_state Act ctx = Act.
Proof.
  intros ctx H1 H2; unfold next_state; rewrite H1, H2; reflexivity.
Qed.

(* Prove that the transition is completely determined for any state and context *)
Theorem exhaustiveness_check : forall s ctx,
  next_state s ctx = Observe \/
  next_state s ctx = Orient \/
  next_state s ctx = Decide \/
  next_state s ctx = Act \/
  next_state s ctx = Idle.
Proof.
  intros s ctx.
  unfold next_state.
  destruct (anomaly_detected ctx).
  - left; reflexivity.
  - destruct s.
    + destruct (data_ready ctx).
      * left; reflexivity.
      * right; right; right; right; reflexivity.
    + destruct (data_ready ctx).
      * right; left; reflexivity.
      * left; reflexivity.
    + destruct (decision_made ctx).
      * right; right; left; reflexivity.
      * right; left; reflexivity.
    + destruct (decision_made ctx).
      * right; right; right; left; reflexivity.
      * right; right; left; reflexivity.
    + destruct (action_complete ctx).
      * right; right; right; right; reflexivity.
      * right; right; right; left; reflexivity.
Qed.

Require Import Extraction.
Extraction Language OCaml.
Extract Inductive bool => "bool" [ "true" "false" ].
Extract Inductive string => "string" [ "EmptyString" "String" ].
(* Extraction "ooda_extracted.ml" ooda_state context next_state. *)
