(* Parity_Lattice.v — machine-checkable proofs of the Hermes configuration
   algebra: the verdict join lattice, the credit rule, and the Gate combinator.

   Mirrors the zigvm Decision_Calculus.v discipline (R14): the OCaml laws'
   ORACLE is this proof; the proof gate is executed wherever a Rocq/Coq
   toolchain exists and is DISCLOSED as skipped where it does not
   (coqc_available=false — the zigvm --verify-formal convention).

   The definitions transcribe hermes_harness/parity_algebra.ml (rank semantics)
   and harness_config.ml (gate_verdict, value level). The OCaml transcription of
   THESE definitions lives in rocq_lattice.ml and is differentially compared
   against the live algebra over the whole finite domain on every test run;
   this file is the artifact a coqc host checks and extracts.

   Checked with: coqc Parity_Lattice.v   (expected: exit 0, no admits) *)

Require Import List PeanoNat.
Import ListNotations.

Inductive verdict : Type :=
  | Unmapped
  | Blocked
  | Verified
  | Divergent.

(* parity_algebra.ml: Verified 0 < Unmapped 1 < Blocked 2 < Divergent 3;
   combine keeps the higher rank (ties keep the left, which equals the right). *)
Definition rank (v : verdict) : nat :=
  match v with
  | Verified => 0
  | Unmapped => 1
  | Blocked => 2
  | Divergent => 3
  end.

Definition combine (a b : verdict) : verdict :=
  if Nat.leb (rank b) (rank a) then a else b.

Definition grants_credit (v : verdict) : bool :=
  match v with Verified => true | _ => false end.

(* harness_config.ml gate_verdict, at value level (laziness is behavioural,
   proven by the OCaml chaos tests; the VALUE law is what is proved here). *)
Definition gate (a b : verdict) : verdict :=
  if grants_credit a then combine a b else a.

(* ------------------------------------------------------------ the laws *)

Theorem combine_comm : forall a b, combine a b = combine b a.
Proof. intros [] []; reflexivity. Qed.

Theorem combine_assoc : forall a b c,
  combine (combine a b) c = combine a (combine b c).
Proof. intros [] [] []; reflexivity. Qed.

Theorem combine_idem : forall a, combine a a = a.
Proof. intros []; reflexivity. Qed.

Theorem divergent_absorbs : forall a,
  combine Divergent a = Divergent /\ combine a Divergent = Divergent.
Proof. intros []; split; reflexivity. Qed.

Theorem verified_identity : forall a, combine Verified a = a /\ combine a Verified = a.
Proof. intros []; split; reflexivity. Qed.

Theorem credit_only_verified : forall v,
  grants_credit v = true <-> v = Verified.
Proof. intros []; split; intro H; (reflexivity || discriminate). Qed.

Theorem combine_credit_conjunction : forall a b,
  grants_credit (combine a b) = andb (grants_credit a) (grants_credit b).
Proof. intros [] []; reflexivity. Qed.

(* Gate fail-closure: exactly the z3-discharged config-gate-fail-closed spec,
   now as theorems over the inductive domain. *)
Theorem gate_no_credit_stands : forall a b,
  grants_credit a = false -> gate a b = a.
Proof. intros a b H. unfold gate. rewrite H. reflexivity. Qed.

Theorem gate_credit_folds : forall a b,
  grants_credit a = true -> gate a b = combine a b.
Proof. intros a b H. unfold gate. rewrite H. reflexivity. Qed.

Theorem gate_never_grants_uncredited : forall a b,
  grants_credit (gate a b) = true -> grants_credit a = true.
Proof. intros [] [] H; (exact H || discriminate). Qed.

(* -------------------------------------------------------- the roll-up fold *)
(* parity_algebra.roll_up ~required:true: an empty required node is Unmapped (the
   vacuous-truth guard -- returning the fold identity Verified would be the bug),
   else a left-fold of combine from Verified. This is the fold the family-level
   evidence roll-up (Evidence_rollup.family_verdicts) rests on: a family is
   Verified only when every slice is, because combine keeps the higher rank. The
   theorems below machine-check that behaviour. (List/PeanoNat are imported at
   the top so this file's own [combine] shadows [List.combine].) *)

Definition roll_up_required (vs : list verdict) : verdict :=
  match vs with
  | [] => Unmapped
  | _ => fold_left combine vs Verified
  end.

(* combine is the rank-max: this is the bridge from the verdict lattice to nat. *)
Lemma combine_rank_max : forall a b, rank (combine a b) = Nat.max (rank a) (rank b).
Proof. intros [] []; reflexivity. Qed.

(* The fold's rank is the max of the accumulator's and every member's rank --
   so the roll-up is exactly the highest-rank (worst) verdict present. *)
Lemma fold_combine_rank : forall vs a,
  rank (fold_left combine vs a) = fold_left Nat.max (map rank vs) (rank a).
Proof.
  induction vs as [| x xs IH]; intros a; simpl.
  - reflexivity.
  - rewrite IH. rewrite combine_rank_max. reflexivity.
Qed.

(* The family-scale vacuous-truth guard: an empty required roll-up is Unmapped,
   never Verified. *)
Theorem rollup_empty_unmapped : roll_up_required [] = Unmapped.
Proof. reflexivity. Qed.

(* A single child's verdict is carried unchanged (Verified is the fold identity). *)
Theorem rollup_singleton : forall v, roll_up_required [v] = v.
Proof. intros []; reflexivity. Qed.

(* A Divergent child absorbs: any list containing Divergent rolls up to Divergent
   (rank 3 is maximal). Shown for the two-child shape the family roll-up uses. *)
Theorem rollup_divergent_absorbs_left : forall v,
  roll_up_required [Divergent; v] = Divergent.
Proof. intros []; reflexivity. Qed.

Theorem rollup_divergent_absorbs_right : forall v,
  roll_up_required [v; Divergent] = Divergent.
Proof. intros []; reflexivity. Qed.

(* And the guard at family scale: an Unmapped (uncovered) child keeps a two-child
   required roll-up from ever reading Verified -- one missing slice is enough. *)
Theorem rollup_unmapped_blocks_left : forall v,
  roll_up_required [Unmapped; v] <> Verified.
Proof. intros []; discriminate. Qed.

Theorem rollup_unmapped_blocks_right : forall v,
  roll_up_required [v; Unmapped] <> Verified.
Proof. intros []; discriminate. Qed.

(* -------------------------------------------------------------- extraction *)
(* On a coqc host, extraction regenerates the OCaml encoding; the committed
   rocq_lattice.ml transcription is then byte-pinned against it (the zigvm
   generated/rocq freshness law). Uncomment on such a host:

   Require Extraction.
   Extraction Language OCaml.
   Extraction "parity_lattice_extracted.ml" verdict combine grants_credit gate.
*)
