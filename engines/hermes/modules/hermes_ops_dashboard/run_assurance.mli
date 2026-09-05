(** Pure pre-dispatch assurance foundation over context-bound gate receipts. *)

type decision = Admit | Block of string list

val required_gates : Run_safety.gate list
(** The denominator is STPA/FMEA, Rete_UL, Raven_matrix, Ruliad, Stan, and Z3.
    Ruliad and Stan remain analysis-only but their current completeness
    evidence is mandatory. *)

val evaluate_inputs :
  Run_safety.gate_context -> Run_safety.receipt list ->
  ((decision * Run_safety.receipt), Run_safety.gate_error list) result
(** Invalid, duplicate, or cross-context receipts are typed errors before a
    decision. A complete set of satisfied load-bearing receipts admits;
    missing, rejected, or unavailable required evidence returns an honest Block
    receipt. Analysis-only receipts never select or promote the decision. *)

(** One typed source/receipt pair for each exact assurance gate.  The
    unavailable Z3 form is a first-class deferred observation, never solver
    authority and never sufficient for [admit]. *)
type gate_input =
  | Safety_input of Run_safety.model * Run_safety.receipt
  | Rete_input of
      Run_intelligence.Rete_ul.network *
      Run_intelligence.Rete_ul.fact list *
      Run_intelligence.Rete_ul.dispatch_receipt
  | Raven_input of
      Run_intelligence.Raven_matrix.matrix *
      Run_intelligence.Raven_matrix.receipt
  | Ruliad_input of
      Run_analysis.Ruliad.system * Run_analysis.Ruliad.bounds *
      Run_analysis.Ruliad.receipt
  | Stan_input of Run_analysis.Stan_model.input * Run_analysis.Stan_model.receipt
  | Z3_input of
      Run_analysis.Z3.campaign_envelope *
      Run_analysis.Z3.cli_configuration * Run_analysis.Z3.receipt
  | Z3_unavailable_input of Run_safety.receipt

type inputs

type receipt = private {
  context_digest : string;
  current_head_digest : string;
  current_at_ns : int64;
  safety_receipt_digest : string;
  rete_receipt_digest : string;
  raven_receipt_digest : string;
  ruliad_receipt_digest : string;
  stan_receipt_digest : string;
  z3_receipt_digest : string;
  load_bearing_digest : string;
  completeness_digest : string;
  receipt_digest : string;
}
(** Collection identity only.  It grants no dispatch authority.  The
    load-bearing digest contains exactly STPA/FMEA, Rete, Raven, and Z3; the
    completeness digest additionally binds Ruliad and Stan. *)

type admitted_bundle = private {
  authority : Run_safety.authority;
  context_digest : string;
  current_head_digest : string;
  current_at_ns : int64;
  inputs : inputs;
  receipt : receipt;
  bundle_digest : string;
}

val make_inputs :
  context:Run_safety.gate_context -> gate_input list ->
  (inputs, Run_safety.gate_error list) result
(** Accepts exactly the canonical six-gate order with no missing or duplicate
    slot and validates every exact source/receipt pairing.  A validated
    unavailable-Z3 slot constructs only a deferred [inputs] value. *)

val receipt : inputs -> receipt
(** Returns the non-authoritative exact collection receipt. *)

val admit :
  context:Run_safety.gate_context -> inputs ->
  (admitted_bundle, Run_safety.gate_error list) result
(** Requires satisfied STPA/FMEA, exact accepting Rete dispatch, exact Raven
    selection, complete Ruliad and Stan evidence, and an exact Task-3 Z3
    receipt whose admission is [Admitted]. *)

val validate_bundle :
  context:Run_safety.gate_context -> admitted_bundle ->
  (unit, Run_safety.gate_error list) result
(** Recomputes the closed bundle identity and rejects foreign context/head,
    stale time, authority inversion, or any digest mutation. *)

module For_test : sig
  type bundle_mutation =
    | Context_digest
    | Current_head_digest
    | Current_at_ns
    | Authority
    | Receipt_digest
    | Load_bearing_digest
    | Completeness_digest
    | Bundle_digest

  val mutate_bundle : bundle_mutation -> admitted_bundle -> admitted_bundle
  (** Corrupts one field of an already-admitted private carrier.  It cannot
      construct a bundle or solver receipt and grants no production authority. *)
end
