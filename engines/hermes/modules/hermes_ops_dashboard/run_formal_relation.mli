(** Canonical finite relational encodings for the seven Task5 laws. *)

type law =
  | Fpp_valid
  | Metric_total
  | Id_windows
  | Execution_bridge
  | Ui_isolation
  | Mbse_correspondence
  | Sqlite_dependability

type fact_mutant =
  | Inject_fpp_cmp_01_passive_async
  | Duplicate_metric_mapping
  | Overlap_instance_window
  | Add_execution_bypass
  | Add_ui_admission_edge
  | Drop_turtle_edge
  | Drop_sqlite_reelect_action
  | Overlap_external_window
  | Overflow_instance_window
  | Invalid_sqlite_machine_owner
  | Invalid_sqlite_initial_state
  | Invalid_sqlite_transition_target
  | Empty_sqlite_transition_signal
  | Invalid_sqlite_fault_owner
  | Invalid_sqlite_gate_intent
  | Invalid_sqlite_activity_contract
  | Mismatch_window_model_name
  | Remove_window_allocation
  | Remove_window_component
  | Change_window_observed_base
  | Include_unregistered_actual_window
  | Empty_sqlite_transition_actions
  | Empty_sqlite_fault_format
  | Invalid_sqlite_gate_owner
  | Empty_sqlite_activity_intent
  | Empty_sqlite_activity_success_criteria
  | Invalid_sqlite_activity_target_state
  | Invalid_sqlite_activity_capabilities
  | Invalid_sqlite_activity_context
  | Invalid_sqlite_activity_miq
  | Invalid_sqlite_activity_effects
  | Drop_repository_action
  | Duplicate_repository_action
  | Substitute_repository_action_work
  | Reorder_repository_actions

type polarity = Negated_law | Fact_mutant_control of fact_mutant

type query = {
  stable_id : string;
  requirement_id : string;
  statement : string;
  law : law;
  polarity : polarity;
  smt2 : string;
  facts_digest : string;
  relation_digest : string;
}

val canonical : query list
(* Diagnostic-only bounded projection of the canonical FPP law.  It requests
   only the first connection-selection carrier values and is excluded from
   [canonical] and its campaign digest. *)
val fpp_probe_smt2 : unit -> string
val law_id : law -> string
val mutant_id : fact_mutant -> string

module For_test : sig
  val sqlite_query_for_authority :
    Run_topology.authority -> polarity -> query
  (** Test-only relational projection seam. It retains every supplied
      activity as raw facts and grants no solver or execution authority. *)

  val mbse_query_for_authority :
    Run_topology.authority -> polarity -> query
  (** Test-only repository-action correspondence projection seam. *)
end

val fpp_validation_clause_ids : string list
(*@ ids = fpp_validation_clause_ids
    ensures List.length ids = 25 *)
val validate_query : query -> string list
val validate_campaign : query list -> string list
(*@ ensures result = [] -> List.length canonical = 42 *)
val campaign_digest : string
(* INVARIANT, stated but not gospel-checked: a 64-character SHA-256 hex
   digest. Gospel 0.3.1 models List but not String, so String.length does
   not resolve; expressing it as a contract makes the WHOLE file fail to
   check, which would cost the two contracts below that it can verify.
   validate_campaign enforces the digest structurally instead. *)
