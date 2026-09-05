(** Closed Task 6 gate foundation.

    A context is admitted only when its exact run head is valid and its
    coordinate and plane are authored by the named [Ops_capability.Activity].
    Every receipt is immutable, repeats the canonical context digest, carries
    an RCA coordinate and analysed hazards, and has no parity-credit authority. *)

type authority = Load_bearing_dispatch_gate | Analysis_only

type gate =
  | Stpa_fmea
  | Rete_ul
  | Raven_matrix
  | Ruliad
  | Stan_model
  | Z3
  | Assurance

type receipt_outcome =
  | Satisfied
  | Rejected of string list
  | Unavailable_observed of string

type error_code =
  | Invalid_context
  | Context_mismatch
  | Invalid_receipt
  | Invalid_model
  | Duplicate_receipt

type gate_error = private {
  code : error_code;
  message : string;
  context_digest : string option;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  hazard_id : string;
}

type current_head_source

type current_head_receipt = private {
  run_id : string;
  provenance : Run_model.provenance;
  head_sequence : int64;
  head_event_digest : string;
  observed_at_ns : int64;
  current_at_ns : int64;
  expires_at_ns : int64;
  observed_monotonic_ns : int64;
  expires_monotonic_ns : int64;
  authority_digest : string;
  receipt_digest : string;
  source : current_head_source;
}
(** Immutable identity evidence bound to one exact append-only store head. *)

val observe_current_head :
  store:Run_event_store.t -> run_id:string -> lifetime_ns:int64 ->
  (current_head_receipt, gate_error) result
(** Reads and revalidates the complete authoritative run stream, requires an
    active Dispatch or Suite_execution phase, samples production wall and
    monotonic clocks, and binds the exact terminal sequence and event digest.
    It performs no Git, filesystem-head, or process observation. *)

type gate_context = private {
  run_id : string;
  request_id : string;
  activity_id : string;
  provenance : Run_model.provenance;
  coordinate : Ops_capability.coordinate;
  plane : Ops_capability.plane;
  current_head_digest : string;
  current_at_ns : int64;
  context_digest : string;
  current_head : current_head_receipt;
}

val revalidate_gate_context_current_head :
  store:Run_event_store.t -> gate_context -> (unit, gate_error) result
(** Revalidates the retained production current-head receipt against the exact
    actor-owned store identity and current clocks.  Test-only sources,
    equivalent bytes from another store, expiry, stream advancement, phase or
    provenance drift, and carrier digest mutation all fail closed. *)

type receipt = private {
  gate : gate;
  authority : authority;
  outcome : receipt_outcome;
  context_digest : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  hazard_ids : string list;
  evidence_digest : string;
  receipt_digest : string;
}

type uca_kind =
  | Not_provided
  | Provided_unsafe
  | Wrong_timing
  | Applied_too_long

type risk = { severity : int; occurrence : int; detectability : int }
type loss = { stable_id : string; edge_id : string; description : string }
type hazard = {
  stable_id : string;
  edge_id : string;
  description : string;
  loss_ids : string list;
}
type causal_scenario = {
  stable_id : string;
  edge_id : string;
  hazard_ids : string list;
  description : string;
}
type unsafe_control_action = {
  stable_id : string;
  edge_id : string;
  kind : uca_kind;
  hazard_ids : string list;
  causal_scenario_ids : string list;
  constraint_ids : string list;
}
type safety_constraint = {
  stable_id : string;
  edge_id : string;
  uca_ids : string list;
  statement : string;
  control : string;
  owner : string;
  verifier_id : string;
}
type control_evidence = private {
  failure_mode_id : string;
  control_ids : string list;
  verifier_id : string;
  original_risk_digest : string;
  residual_risk_digest : string;
  model_authority_digest : string;
  context_digest : string;
  current_head_digest : string;
  observed_at_ns : int64;
  evidence_digest : string;
}
type residual_acceptance = private {
  failure_mode_id : string;
  requirement_id : string;
  owner : string;
  rationale : string;
  context_digest : string;
  current_head_digest : string;
  authority_digest : string;
  original_risk_digest : string;
  residual_risk_digest : string;
  model_authority_digest : string;
  accepted_at_ns : int64;
  expires_at_ns : int64;
  acceptance_digest : string;
}
type failure_mode = {
  stable_id : string;
  edge_id : string;
  requirement_id : string;
  hazard_ids : string list;
  failure_effect : string;
  cause : string;
  control_ids : string list;
  owner : string;
  initial_risk : risk;
  residual_risk : risk;
  verifier_id : string;
  control_evidence : control_evidence option;
  acceptance : residual_acceptance option;
}
type path_analysis = {
  edge_id : string;
  loss_ids : string list;
  hazard_ids : string list;
  uca_ids : string list;
  causal_scenario_ids : string list;
  constraint_ids : string list;
  failure_mode_ids : string list;
}
type model = {
  topology_digest : string;
  evaluated_at_ns : int64;
  residual_rpn_threshold : int;
  losses : loss list;
  hazards : hazard list;
  causal_scenarios : causal_scenario list;
  unsafe_control_actions : unsafe_control_action list;
  constraints : safety_constraint list;
  failure_modes : failure_mode list;
  paths : path_analysis list;
}
type decision = Admit | Block of string list

val make_gate_context :
  current_head:current_head_receipt -> request_id:string -> activity_id:string ->
  coordinate:Ops_capability.coordinate ->
  plane:Ops_capability.plane -> (gate_context, gate_error) result
(** Rejects a malformed/expired identity receipt, unknown/non-Activity id,
    unauthored coordinate, or wrong plane before any evaluator can run. *)

val same_context : gate_context -> gate_context -> bool
(** Equality is over the full closed carrier and its canonical digest. *)

val authority_of_gate : gate -> authority
(** Ruliad and Stan are permanently [Analysis_only]. The remaining gates are
    load-bearing dispatch gates; callers cannot supply or override authority. *)

val rete_unavailable_receipt :
  gate_context -> reason:string -> (receipt, gate_error) result
val raven_unavailable_receipt :
  gate_context -> reason:string -> (receipt, gate_error) result
val ruliad_unavailable_receipt :
  gate_context -> reason:string -> (receipt, gate_error) result
val stan_unavailable_receipt :
  gate_context -> reason:string -> (receipt, gate_error) result
val z3_unavailable_receipt :
  gate_context -> reason:string -> (receipt, gate_error) result
(** Gate-specific constructors are outcome-locked to [Unavailable_observed].
    There is no generic receipt constructor and no public Assurance mint. *)

val validate_receipt :
  context:gate_context -> receipt -> (unit, gate_error) result
(** Recomputes the closed receipt digest and rejects a context mismatch. *)

val make_gate_error :
  gate_context -> code:error_code -> message:string ->
  rca_origin:Ops_capability.rca_origin -> hazard_id:string -> gate_error
(** Narrow diagnostic constructor for sibling Task 6 validators. It always
    binds the exact context coordinate and digest. *)

val string_of_gate : gate -> string
val string_of_authority : authority -> string

val effectful_edge_ids : string list
val model : model
val rpn : risk -> (int, string) result
val validate_control_structure : model -> string list
val model_digest : model -> string
val model_authority_digest : model -> string

val evaluate :
  gate_context -> model -> ((decision * receipt), gate_error) result
(** Malformed or incomplete models are typed errors. A valid model blocks on
    every residual RPN at or above the threshold unless a current acceptance is
    bound to the exact context, authority, failure mode, and requirement. *)

type assurance_evaluation = private {
  admitted : bool;
  reasons : string list;
  receipt : receipt;
}

module Assurance_evaluator : sig
  val required_gates : gate list
  val evaluate :
    gate_context -> receipt list ->
    (assurance_evaluation, gate_error list) result
  (** The sole Assurance receipt constructor. It validates the exact six-gate
      denominator, duplicates, circular inputs, and context before minting. *)
end

module For_test : sig
  type retained_head_mutation =
    | Receipt_digest
    | Provenance
    | Store_identity of Run_event_store.t

  val current_head_receipt :
    run_id:string -> provenance:Run_model.provenance -> observed_at_ns:int64 ->
    current_at_ns:int64 -> expires_at_ns:int64 ->
    (current_head_receipt, gate_error) result
  (** Test-only identity adapter. Production code has no constructor in this
      dependency layer. *)

  val validate_current_head_at :
    wall_now_ns:int64 -> monotonic_now_ns:int64 -> current_head_receipt ->
    (unit, gate_error) result
  (** Deterministic use-time clock seam. Production context creation always
      samples the real wall and monotonic clocks. *)

  val mutate_current_head_event_digest :
    current_head_receipt -> current_head_receipt
  (** Private-carrier integrity mutant; it changes no authoritative store. *)

  val revalidate_gate_context_current_head_at :
    wall_now_ns:int64 -> monotonic_now_ns:int64 -> store:Run_event_store.t ->
    gate_context -> (unit, gate_error) result
  (** Deterministic clock seam for the production context revalidator. *)

  val mutate_retained_current_head :
    retained_head_mutation -> gate_context -> gate_context
  (** Test-only private-carrier mutant.  No production caller can replace the
      retained source, provenance, or digest. *)

  val control_evidence :
    gate_context -> model -> failure_mode_id:string -> residual_risk:risk ->
    (control_evidence, gate_error) result
  val control_evidence_at :
    gate_context -> model -> failure_mode_id:string -> residual_risk:risk ->
    observed_at_ns:int64 -> (control_evidence, gate_error) result
  val residual_acceptance :
    gate_context -> model -> failure_mode_id:string -> owner:string ->
    rationale:string -> expires_at_ns:int64 ->
    (residual_acceptance, gate_error) result
end
