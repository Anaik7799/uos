(** Authority-preserving intelligence gates. Rete_UL and deterministic MCDA
    are pure bounded evaluators; their evidence grants no parity credit and is
    not live Task 7/Swarm admission. *)

type engine = Rete_ul | Raven_matrix

val gate : engine -> Run_safety.gate
val authority : engine -> Run_safety.authority

val unavailable_receipt :
  Run_safety.gate_context -> engine:engine -> reason:string ->
  (Run_safety.receipt, Run_safety.gate_error) result
(** A missing live intelligence adapter can produce only a context-bound
    [Unavailable_observed] gate receipt. Pure structural evaluator receipts do
    not silently become live admission evidence. *)

(** A bounded, persistent Rete_UL carrier. The public values are declarative;
    compilation and execution remain context-bound and return typed errors. *)
module Rete_ul : sig
  type value = Int of int | String of string | Bool of bool

  type budgets = {
    max_facts : int;
    max_alpha_entries : int;
    max_beta_tokens : int;
    max_agenda : int;
    max_firings : int;
    max_trace_entries : int;
  }

  type condition =
    | Field_eq of string * value
    | Join_eq of string * string
    | Bind of string * string

  type pattern = {
    pattern_id : string;
    fact_kind : string;
    conditions : condition list;
  }

  type value_expr = Literal of value | Variable of string
  type rhs_template = {
    fact_id : string;
    fact_kind : string;
    attrs : (string * value_expr) list;
  }
  type rhs_action =
    | Assert_rhs of rhs_template
    | Update_rhs of rhs_template
    | Retract_rhs of string
    | Block_rhs of string

  type rule = {
    rule_id : string;
    salience : int;
    patterns : pattern list;
    actions : rhs_action list;
  }
  type network = { network_id : string; budgets : budgets; rules : rule list }

  type fact = private {
    fact_id : string;
    fact_kind : string;
    attrs : (string * value) list;
    fact_digest : string;
  }
  type compiled
  type session
  type delta = Assert_fact of fact | Update_fact of fact | Retract_fact of string

  type snapshot = private {
    fact_count : int;
    alpha_entry_count : int;
    beta_token_count : int;
    agenda_count : int;
    session_digest : string;
  }
  type trace_entry = private {
    ordinal : int;
    rule_id : string;
    activation_digest : string;
    outcome : string;
  }
  type partial_trace = private {
    entries : trace_entry list;
    truncated : bool;
    trace_digest : string;
  }
  type delta_receipt = private {
    changed : bool;
    delta_digest : string;
    receipt_digest : string;
  }
  type rete_receipt = private {
    authority : Run_safety.authority;
    context_digest : string;
    current_head_digest : string;
    current_at_ns : int64;
    network_digest : string;
    input_fact_digest : string;
    session_digest : string;
    fixed_point : bool;
    empty_agenda : bool;
    firing_count : int;
    output_fact_digest : string;
    trace_digest : string;
    receipt_digest : string;
  }
  type static_outcome = Static_accept | Static_block

  type dispatch_receipt = private {
    authority : Run_safety.authority;
    context_digest : string;
    current_head_digest : string;
    current_at_ns : int64;
    network_digest : string;
    input_fact_digest : string;
    static_outcome : static_outcome;
    fixed_point : bool;
    empty_agenda : bool;
    rete_receipt_digest : string;
    receipt_digest : string;
  }

  val make_fact :
    fact_id:string -> fact_kind:string -> attrs:(string * value) list ->
    (fact, string) result
  val compile :
    Run_safety.gate_context -> network ->
    (compiled, Run_safety.gate_error) result
  val compiled_digest : compiled -> string
  val create :
    Run_safety.gate_context -> compiled ->
    (session, Run_safety.gate_error) result
  val assert_fact :
    Run_safety.gate_context -> fact -> session ->
    (session * delta_receipt,
     Run_safety.gate_error * session * partial_trace) result
  val update_fact :
    Run_safety.gate_context -> fact -> session ->
    (session * delta_receipt,
     Run_safety.gate_error * session * partial_trace) result
  val retract_fact :
    Run_safety.gate_context -> fact_id:string -> session ->
    (session * delta_receipt,
     Run_safety.gate_error * session * partial_trace) result
  val run_to_fixed_point :
    Run_safety.gate_context -> session ->
    (session * rete_receipt,
     Run_safety.gate_error * session * partial_trace) result
  val validate_receipt :
    context:Run_safety.gate_context -> rete_receipt ->
    (unit, Run_safety.gate_error) result
  val snapshot : session -> snapshot
  val replay :
    Run_safety.gate_context -> compiled -> delta list ->
    (session * rete_receipt,
     Run_safety.gate_error * session * partial_trace) result

  val static_outcome :
    Run_safety.gate_context -> network -> fact list ->
    (static_outcome, Run_safety.gate_error) result

  (** Constructs an exact private dispatch authority only when the canonical
      network and fact set agree with the fixed-point receipt and the
      recomputed static outcome is [Static_accept]. *)
  val admit_dispatch :
    Run_safety.gate_context -> network:network -> facts:fact list ->
    rete_receipt -> (dispatch_receipt, Run_safety.gate_error) result

  (** Recomputes the canonical network, facts, static outcome, and carrier
      digest.  A coherent receipt from another input or context is refused. *)
  val validate_dispatch :
    context:Run_safety.gate_context -> network:network -> facts:fact list ->
    dispatch_receipt -> (unit, Run_safety.gate_error) result

  val hermes_rete_static_outcome :
    network -> fact list -> (static_outcome, string) result
  val differential_oracle_authority : Run_safety.authority

  module For_test : sig
    type receipt_mutation =
      | Authority
      | Context_digest
      | Current_head_digest
      | Current_at_ns
      | Network_digest
      | Input_fact_digest
      | Session_digest
      | Output_fact_digest
      | Trace_digest
      | Fixed_point
      | Empty_agenda
      | Firing_count
      | Receipt_digest

    val mutate_receipt : rete_receipt -> receipt_mutation -> rete_receipt
  end
end

(** Closed deterministic multi-criteria decision analysis. The public matrix
    is declarative input; only [decide] can construct the private receipt.
    This is not the repository Raven/Rune ML substrate. *)
module Raven_matrix : sig
  type engine = Deterministic_mcda_v1
  type direction = Maximize | Minimize

  type budgets = {
    max_alternatives : int;
    max_criteria : int;
    max_cells : int;
    max_constraints : int;
    max_trace_entries : int;
    max_abs_value : int64;
  }

  type criterion = {
    criterion_id : string;
    direction : direction;
    weight_ppm : int;
    scale_min : int64;
    scale_max : int64;
  }

  type alternative = {
    alternative_id : string;
    prohibited : bool;
  }

  type cell = {
    alternative_id : string;
    criterion_id : string;
    value : int64;
    evidence_digest : string;
  }

  type relation = At_least | At_most
  type hard_constraint = {
    constraint_id : string;
    alternative_id : string;
    criterion_id : string;
    relation : relation;
    threshold : int64;
    evidence_digest : string;
  }

  type selection_policy =
    | Require_stable
    | Force_if_feasible of string

  type matrix = {
    matrix_id : string;
    criteria : criterion list;
    alternatives : alternative list;
    cells : cell list;
    constraints : hard_constraint list;
    tie_order : string list;
    selection_policy : selection_policy;
    min_sensitivity_ppm : int;
    budgets : budgets;
  }

  type contribution = private {
    alternative_id : string;
    criterion_id : string;
    normalized_ppm : int;
    weighted_ppm : int;
    evidence_digest : string;
  }

  type ranked_alternative = private {
    rank : int;
    alternative_id : string;
    score_ppm : int;
    dominated_by : string list;
  }

  type exclusion_reason = Prohibited | Constraint_failed of string list
  type exclusion = private {
    alternative_id : string;
    reason : exclusion_reason;
  }

  type receipt = private {
    engine : engine;
    authority : Run_safety.authority;
    context_digest : string;
    matrix_digest : string;
    ranking : ranked_alternative list;
    contributions : contribution list;
    dominance : (string * string) list;
    exclusions : exclusion list;
    sensitivity_margin_ppm : int;
    stable : bool;
    selected_alternative : string;
    forced : bool;
    decision_trace : string list;
    trace_digest : string;
    receipt_digest : string;
  }

  val decide :
    Run_safety.gate_context -> matrix ->
    (receipt, Run_safety.gate_error) result
  val validate_receipt :
    context:Run_safety.gate_context -> matrix:matrix -> receipt ->
    (unit, Run_safety.gate_error) result
end
