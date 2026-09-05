(** Narrow SQLite lifetime effects governed by {!Sqlite_lifecycle_model}.

    A database is opened from an opaque registered location and owned here.
    Physical location resolution and the lifetime-global close authority are
    internal and cannot be recreated or reset by callers.  Each quiescence
    generation admits at most one native close attempt. *)

type owned_database
type close_generation
type quiescence_witness

(** Closed projection of the native SQLite step result.  Native return-code
    constructors never leave the SQLite owner. *)
type step_outcome = Row | Done

val string_of_step_outcome : step_outcome -> string

type database_state =
  | Database_open
  (** The installed sqlite3-ocaml binding accepted [sqlite3_close_v2], so no
      further database operation or close generation is admissible.  A
      retained statement still needs a successfully observed finalization
      before this authority may claim physical release. *)
  | Database_close_v2_deferred
  | Database_released

(** Closed durability projection derived from the opaque location identity.
    It permits owners to select compatible SQLite policy without revealing a
    path or physical target. *)
type storage_posture = Durable_registered | Volatile_test

type native_close_observation =
  | Native_close_reported_busy
  | Native_close_v2_deferred
  | Native_close_immediate

type finalize_error =
  | Finalize_rc of string
  | Finalize_exception of string
  | Finalize_already_consumed
  | Finalize_wrong_database

type finalize_interval_outcome =
  | Finalize_interval_succeeded
  | Finalize_interval_failed of finalize_error

type finalize_interval_observation = {
  database_identity : int;
  statement_identity : int;
  interval_identity : int;
  live_statements_at_enter : int;
  live_statements_at_exit : int;
  finalize_interval_outcome : finalize_interval_outcome;
}

type statement_error =
  | Prepare_failed of string
  | Body_failed of string
  | Statement_finalize_failed of finalize_error
  | Body_and_finalize_failed of string * finalize_error

type statement_use_error =
  | Statement_scope_closed
  | Statement_step_failed of string
  | Statement_step_raised of string
  | Statement_bind_failed of {
      index : int;
      binding : string;
      rc : string;
    }
  | Statement_bind_raised of {
      index : int;
      binding : string;
      detail : string;
    }
  | Statement_column_without_row of int
  | Statement_column_type_mismatch of {
      column : int;
      expected : string;
      actual : string;
    }
  | Statement_column_raised of {
      column : int;
      projection : string;
      detail : string;
    }

type transaction_status =
  | Transaction_idle
  | Transaction_active
  | Transaction_indeterminate

type database_error =
  | Database_operation_not_open of database_state
  | Invalid_schema_statement of string
  | Database_exec_failed of { operation : string; rc : string }
  | Database_exec_raised of { operation : string; detail : string }
  | Database_changes_raised of string
  | Database_transaction_active
  | Database_transaction_indeterminate

type 'body transaction_error =
  | Transaction_unavailable of database_error
  | Transaction_already_active
  | Transaction_poisoned
  | Transaction_begin_failed of database_error
  | Transaction_body_failed of 'body
  | Transaction_body_and_rollback_failed of 'body * database_error
  | Transaction_body_raised of string
  | Transaction_exception_and_rollback_failed of string * database_error
  | Transaction_commit_failed of database_error
  | Transaction_commit_and_rollback_failed of database_error * database_error

type close_error =
  | Invalid_close_budget of int
  | Database_location_released
  | Database_open_failed of string
  | Database_already_released
  | Lifetime_close_budget_exhausted of { attempts : int; maximum : int }
  | Close_generation_still_active of int
  | Terminal_close_generation of int
  | Superseded_close_generation of { observed : int; active : int }
  | Invalid_quiescence_witness of string
  | Wrong_close_generation of { observed : int; expected : int }
  | Database_busy of { attempts : int; remaining : int }
  | Database_close_raised of string

val open_database :
  location:Dependability_sqlite_location.reference ->
  maximum_total_attempts:int ->
  (owned_database, close_error) result
(** The location reference is resolved only by this owner.  No filename, path,
    native handle, SQL statement, or finalizer crosses the open boundary. *)

val database_state : owned_database -> database_state
val storage_posture : owned_database -> storage_posture
val database_identity : owned_database -> int
val live_statement_count : owned_database -> int
val finalize_interval_active : owned_database -> bool
val finalize_interval_observations :
  owned_database -> finalize_interval_observation list
val transaction_status : owned_database -> transaction_status

val begin_generation :
  owned_database ->
  (close_generation, close_error) result

val close_attempts : close_generation -> int
val close_maximum : close_generation -> int
val remaining_close_attempts : close_generation -> int
val close_generation : close_generation -> int
val total_close_attempts : owned_database -> int
val remaining_total_close_attempts : owned_database -> int

val observe_quiescence :
  close_generation ->
  epoch:int ->
  live_statements:int ->
  active_handlers:int ->
  queued_requests:int ->
  (quiescence_witness, close_error) result
(** An epoch is lifetime-monotone, not generation-local.  A close attempt
    consumes it even when the injected/native result is Busy or raises. *)

val observe_internal_quiescence :
  close_generation ->
  epoch:int ->
  active_handlers:int ->
  queued_requests:int ->
  (quiescence_witness, close_error) result
(** Uses the authority's live-statement count and refuses an active or
    indeterminate transaction; callers cannot self-report quiescence. *)

val string_of_finalize_error : finalize_error -> string
val string_of_statement_error : statement_error -> string
val string_of_statement_use_error : statement_use_error -> string
val string_of_database_error : database_error -> string
val string_of_transaction_error :
  ('body -> string) -> 'body transaction_error -> string
val string_of_close_error : close_error -> string

(** Additive closed-operation boundary.  This first atom closes the complete
    completion-history statement denominator and one lifecycle observation
    used to prove family separation.  It exposes no SQL, table/column name,
    bind/column ordinal, statement, native result code, path, or handle. *)
module Closed_operation : sig
  type family =
    | Authority_store
    | Completion_history
    | Completion_store
    | Dispatch_store
    | Effect_ledger
    | Event_store
    | Lifecycle_test
  type mode = Read_only | Read_write
  type transaction_scope

  type completion_verdict = Succeeded | Blocked
  type completion_receipt = {
    receipt_digest : string;
    request_id : string;
    action : string;
    scope : string;
    verdict : completion_verdict;
    output : string;
    source_revision : string;
    source_clean : bool;
    configuration_digest : string;
    authority_digest : string;
    run_id : string;
    recorded_at_ns : int64;
  }

  type completion_observation = {
    receipt_digest : string;
    surface : string;
    plane : string;
    fractal_coordinate : string;
    ooda_phase : string;
    rca_origin : string option;
    mediation : string;
    resource : string;
    duration_ns : int64;
    observed_at_ns : int64;
    event_json : string;
  }

  type completion_interaction_kind =
    | Prompt
    | Agent_message
    | Command
    | Decision
    | Residual

  type completion_interaction = {
    interaction_id : string;
    run_id : string;
    actor : string;
    kind : completion_interaction_kind;
    body : string;
    body_digest : string;
    recorded_at_ns : int64;
  }

  type current_source = {
    source_revision : string;
    source_clean : bool;
    configuration_digest : string;
    authority_digest : string;
  }

  type completion_counts = {
    receipts : int;
    observations : int;
    interactions : int;
  }

  (** Neutral persistence row for the effect ledger.  Its string fields are
      opaque to this lower owner; effect-kind, state, digest, and receipt
      semantics remain owned and validated by the upper effect authority. *)
  type effect_row = {
    schema_version : int;
    stored_key : string;
    stored_request_digest : string;
    stored_target_digest : string;
    stored_target_authority_digest : string;
    stored_effect_kind : string;
    stored_state : string;
    stored_disposition : string option;
    stored_output : string option;
    stored_output_digest : string option;
    stored_receipt_digest : string option;
    stored_diagnostic : string option;
    stored_no_replay : bool;
    stored_row_digest : string;
  }

  type effect_cas = {
    expected : effect_row;
    replacement : effect_row;
  }

  type event_row = {
    run_id : string;
    sequence : int64;
    event_id : string;
    event_digest : string;
    event_json : string;
  }

  type event_conflict = {
    conflict_run_id : string;
    conflict_sequence : int64;
    conflict_event_id : string;
  }

  type completion_store_owner = {
    completion_owner_session : string;
    completion_store_epoch : string;
    completion_authority_session : string;
    completion_authority_epoch : string;
    completion_opened_time_digest : string;
  }

  type completion_store_row = {
    completion_row_id : string;
    completion_row_state : string;
    completion_reservation_payload_digest : string;
    completion_reserve_request_digest : string;
    completion_reserve_time_digest : string;
    completion_reserve_receipt_digest : string;
    completion_finalize_request_digest : string option;
    completion_finalize_time_digest : string option;
    completion_finalize_receipt_digest : string option;
    completion_conflict_digest : string option;
  }

  type completion_store_conflict = {
    completion_conflict_id : string;
    completion_conflict_value : string;
  }

  type completion_store_finalize = {
    completion_finalize_id : string;
    completion_finalize_reservation_payload_digest : string;
    completion_finalize_request_value : string;
    completion_finalize_time_value : string;
    completion_finalize_receipt_value : string;
  }

  type completion_store_owner_cas = {
    completion_owner_from_state : string;
    completion_owner_to_state : string;
    completion_owner_cas_session : string;
    completion_owner_cas_epoch : string;
  }

  type dispatch_store_initial_owner = {
    dispatch_initial_session : string;
    dispatch_initial_recovery_attempt : int;
    dispatch_initial_store_epoch : string;
    dispatch_initial_bootstrap_digest : string;
    dispatch_initial_time_digest : string;
    dispatch_initial_transition_id : string;
  }

  type dispatch_store_pointer = {
    dispatch_pointer_key : string;
    dispatch_pointer_ordinal : int;
    dispatch_pointer_session : string;
    dispatch_pointer_attempt : int;
  }

  type dispatch_store_lookup = {
    dispatch_lookup_key : string;
    dispatch_lookup_ordinal : int;
  }

  type dispatch_store_row = {
    dispatch_row_key : string;
    dispatch_row_ordinal : int;
    dispatch_row_status : string;
    dispatch_row_transition_id : string;
    dispatch_row_request_digest : string;
    dispatch_row_time_digest : string;
    dispatch_row_owner_session : string;
    dispatch_row_recovery_attempt : int;
  }

  type dispatch_store_decision = {
    dispatch_decision_key : string;
    dispatch_decision_status : string;
    dispatch_decision_id : string;
    dispatch_decision_plan_digest : string;
    dispatch_decision_time_digest : string;
    dispatch_decision_owner_session : string;
    dispatch_decision_recovery_attempt : int;
  }

  type dispatch_store_pointer_cas = {
    dispatch_pointer_cas_key : string;
    dispatch_pointer_expected_ordinal : int;
    dispatch_pointer_replacement_ordinal : int;
    dispatch_pointer_cas_session : string;
    dispatch_pointer_cas_attempt : int;
  }

  type dispatch_store_abandonment = {
    dispatch_abandonment_commitment_id : string;
    dispatch_abandonment_evidence_digest : string;
  }

  type dispatch_store_inventory = {
    dispatch_inventory_owner_rows : string list;
    dispatch_inventory_transition_rows : string list;
    dispatch_inventory_decision_rows : string list;
    dispatch_inventory_abandonment_rows : string list;
  }

  type dispatch_store_owner_transition = {
    dispatch_owner_transition_ordinal : int;
    dispatch_owner_transition_state : string;
    dispatch_owner_transition_session : string;
    dispatch_owner_transition_attempt : int;
    dispatch_owner_transition_epoch : string;
    dispatch_owner_transition_bootstrap_digest : string;
    dispatch_owner_transition_time_digest : string;
    dispatch_owner_transition_id : string;
  }

  type authority_store_initial_owner = {
    authority_initial_session : string;
    authority_initial_epoch : string;
    authority_initial_bootstrap_digest : string;
    authority_initial_time_digest : string;
    authority_initial_transition_id : string;
  }

  type authority_store_pointer = {
    authority_pointer_generation : int;
    authority_pointer_ordinal : int;
  }

  type authority_store_lookup = {
    authority_lookup_key : string;
    authority_lookup_generation : int;
    authority_lookup_ordinal : int;
  }

  type authority_store_transition = {
    authority_transition_key : string;
    authority_transition_generation : int;
    authority_transition_ordinal : int;
    authority_transition_status : string;
    authority_transition_id : string;
    authority_transition_request_digest : string;
    authority_transition_evidence_digest : string;
    authority_transition_context_digest : string;
    authority_transition_time_digest : string;
  }

  type authority_store_campaign = {
    authority_campaign_key : string;
    authority_campaign_approval_identity : string;
    authority_campaign_plan_digest : string;
    authority_campaign_request_digest : string;
    authority_campaign_verification_digest : string;
    authority_campaign_denominator_digest : string;
    authority_campaign_occurrence_count : int;
    authority_campaign_session : string;
    authority_campaign_epoch : string;
    authority_campaign_time_digest : string;
    authority_campaign_registration_id : string;
  }

  type authority_store_nonce = {
    authority_nonce_key : string;
    authority_nonce_occurrence_ordinal : int;
    authority_nonce_occurrence_identity : string;
    authority_nonce_identity : string;
    authority_nonce_transition_ordinal : int;
    authority_nonce_state : string;
    authority_nonce_request_digest : string;
    authority_nonce_verification_digest : string;
    authority_nonce_session : string;
    authority_nonce_epoch : string;
    authority_nonce_time_digest : string;
    authority_nonce_transition_id : string;
  }

  type authority_store_nonce_lookup = {
    authority_nonce_lookup_key : string;
    authority_nonce_lookup_identity : string;
  }

  type authority_store_pointer_cas = {
    authority_pointer_cas_key : string;
    authority_pointer_cas_generation : int;
    authority_pointer_expected_ordinal : int;
    authority_pointer_replacement_ordinal : int;
  }

  type authority_store_owner_transition = {
    authority_owner_transition_generation : int;
    authority_owner_transition_ordinal : int;
    authority_owner_transition_state : string;
    authority_owner_transition_session : string;
    authority_owner_transition_epoch : string;
    authority_owner_transition_bootstrap_digest : string;
    authority_owner_transition_time_digest : string;
    authority_owner_transition_id : string;
  }

  type authority_store_owner_cas = {
    authority_owner_cas_generation : int;
    authority_owner_cas_expected_ordinal : int;
    authority_owner_cas_replacement_ordinal : int;
    authority_owner_cas_state : string;
    authority_owner_cas_session : string;
    authority_owner_cas_epoch : string;
  }

  type lifecycle_scoped_input = {
    lifecycle_literal_key : string;
    lifecycle_literal_blob : string;
    lifecycle_literal_wide : int64;
    lifecycle_literal_small : int;
  }

  type lifecycle_scoped_observation = {
    lifecycle_selected_key : string;
    lifecycle_selected_blob : string;
    lifecycle_selected_wide : int64;
    lifecycle_selected_small : int;
    lifecycle_change_count : int;
    lifecycle_column_before_row_rejected : bool;
    lifecycle_type_mismatch_rejected : bool;
    lifecycle_invalid_column_rejected : bool;
    lifecycle_escaped_bind_rejected : bool;
    lifecycle_escaped_column_rejected : bool;
  }

  type lifecycle_composition_observation = {
    lifecycle_scope_closed : bool;
    lifecycle_finalize_failure_composed : bool;
    lifecycle_body_and_finalize_failure_composed : bool;
  }

  type lifecycle_live_observation = {
    lifecycle_live_count : int;
    lifecycle_quiescence_refused : bool;
  }

  type write_outcome = Inserted | Replayed

  type error =
    | Family_mismatch of {
        operation_family : family;
        registered_location : Dependability_sqlite_location.registration option;
        claimed_family : family option;
      }
    | Transaction_scope_closed
    | Write_in_read_only_scope
    | Divergent_replay
    | Operation_failed of string

  type _ t =
    | Authority_store_initialize_v1 : unit t
    | Authority_store_insert_initial_owner : authority_store_initial_owner -> unit t
    | Authority_store_read_pointer : string -> authority_store_pointer option t
    | Authority_store_read_transition : authority_store_lookup -> authority_store_transition option t
    | Authority_store_insert_transition : authority_store_transition -> unit t
    | Authority_store_insert_pointer : string -> unit t
    | Authority_store_read_campaign : string -> authority_store_campaign option t
    | Authority_store_read_nonces : string -> authority_store_nonce list t
    | Authority_store_insert_campaign : authority_store_campaign -> unit t
    | Authority_store_insert_nonce : authority_store_nonce -> unit t
    | Authority_store_read_current_nonce : authority_store_nonce_lookup -> authority_store_nonce option t
    | Authority_store_pointer_cas : authority_store_pointer_cas -> bool t
    | Authority_store_inventory_ids : string list t
    | Authority_store_insert_owner_transition : authority_store_owner_transition -> unit t
    | Authority_store_owner_pointer_cas : authority_store_owner_cas -> bool t
    | Completion_initialize_v1 : unit t
    | Completion_record :
        completion_receipt * completion_observation -> write_outcome t
    | Completion_append_interaction :
        completion_interaction -> write_outcome t
    | Completion_counts : completion_counts t
    | Completion_receipt_current : current_source * string -> bool t
    | Completion_has_current_success :
        current_source * string * string -> bool t
    | Completion_store_initialize_v1 : unit t
    | Completion_store_insert_owner : completion_store_owner -> unit t
    | Completion_store_read : string -> completion_store_row option t
    | Completion_store_insert_reservation : completion_store_row -> unit t
    | Completion_store_mark_conflict : completion_store_conflict -> bool t
    | Completion_store_finalize : completion_store_finalize -> bool t
    | Completion_store_all_rows : completion_store_row list t
    | Completion_store_owner_cas : completion_store_owner_cas -> bool t
    | Dispatch_store_initialize_v1 : unit t
    | Dispatch_store_insert_initial_owner : dispatch_store_initial_owner -> unit t
    | Dispatch_store_read_pointer : string -> dispatch_store_pointer option t
    | Dispatch_store_read_transition :
        dispatch_store_lookup -> dispatch_store_row option t
    | Dispatch_store_read_decision : string -> dispatch_store_decision option t
    | Dispatch_store_insert_transition : dispatch_store_row -> unit t
    | Dispatch_store_insert_pointer : dispatch_store_pointer -> unit t
    | Dispatch_store_insert_decision : dispatch_store_decision -> unit t
    | Dispatch_store_pointer_cas : dispatch_store_pointer_cas -> bool t
    | Dispatch_store_read_abandonment :
        string -> dispatch_store_abandonment option t
    | Dispatch_store_inventory_ids : dispatch_store_inventory t
    | Dispatch_store_owner_transition :
        dispatch_store_owner_transition -> bool t
    | Effect_initialize_v1 : unit t
    | Effect_read : string -> effect_row option t
    | Effect_insert_pending : effect_row -> effect_row t
    | Effect_cas_pending : effect_cas -> effect_row t
    | Event_configure : unit t
    | Event_verify_configuration : unit t
    | Event_initialize_v1 : unit t
    | Event_read_stream : string -> event_row list t
    | Event_conflicts : event_conflict -> event_row list t
    | Event_insert : event_row -> unit t
    | Event_run_ids : int -> string list t
    | Event_test_initialize_unsupported_schema : unit t
    | Event_test_finalize_failure : unit t
    | Event_test_insert_malformed : string -> unit t
    | Event_test_verify_append_only : unit t
    | Lifecycle_observe_changes : int t
    | Lifecycle_setup_finalize_failure : unit t
    | Lifecycle_statement_composition : lifecycle_composition_observation t
    | Lifecycle_scoped_data_contract : lifecycle_scoped_input -> lifecycle_scoped_observation t
    | Lifecycle_schema_rejection_contract : bool t
    | Lifecycle_transaction_initialize : unit t
    | Lifecycle_transaction_insert : string -> unit t
    | Lifecycle_transaction_count : int t
    | Lifecycle_live_statement_observation : close_generation -> lifecycle_live_observation t

  val execute : owned_database -> 'a t -> ('a, error) result
  val execute_in : transaction_scope -> 'a t -> ('a, error) result
  val with_transaction :
    owned_database ->
    mode:mode ->
    (transaction_scope -> ('a, error) result) ->
    ('a, error) result

  val string_of_error : error -> string
  val source_digest : string

  module For_test : sig
    type mutation =
      | Drop_completion_counts
      | Drop_effect_cas_pending
      | Drop_event_insert
      | Drop_completion_store_owner_cas
      | Drop_dispatch_store_pointer_cas
      | Drop_authority_store_pointer_cas
    val source_digest_with_mutation : mutation -> string
  end
end

val close_database :
  generation:close_generation ->
  witness:quiescence_witness ->
  (close_generation, close_error * close_generation) result
(*@ result = close_database ~generation ~witness
    ensures match result with
      | Ok consumed -> close_attempts consumed = 1
      | Error (_, consumed) -> close_attempts consumed >= 0 *)

(** Closed native probes used only by the lifecycle regression executable.
    They expose neither the raw database handle nor authority construction. *)
module For_test : sig
  type retained_statement
  type retained_statement_kind =
    | Retain_select_one
    | Retain_select_two
    | Retain_duplicate_failure
  type transaction_fault =
    | Fail_transaction_begin
    | Fail_transaction_commit
    | Fail_transaction_rollback
    | Fail_transaction_commit_and_rollback

  val prepare :
    owned_database -> retained_statement_kind ->
    (retained_statement, statement_error) result

  val step :
    retained_statement -> (step_outcome, statement_use_error) result

  val finalize :
    owned_database -> retained_statement -> (unit, finalize_error) result

  val native_close_probe :
    owned_database -> (native_close_observation, string) result

  val close_as_busy :
    generation:close_generation ->
    witness:quiescence_witness ->
    (close_generation, close_error * close_generation) result

  val with_transaction_fault :
    transaction_fault ->
    owned_database ->
    (Closed_operation.transaction_scope -> ('a, 'body) result) ->
    ('a, 'body transaction_error) result

  val dispose : owned_database -> bool
end
