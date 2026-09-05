(** Exhaustive finite authority for the SQLite statement and actor lifecycles.

    The transition tables in this module are pure.  The OCaml explorer and the
    SMT-LIB projection consume the same tables; neither claims that an
    exhaustive model proves the native C binding or the OCaml garbage
    collector. *)

type wrapper_reachability = Live | Collectible
type native_statement = Prepared | Finalizing | Finalized
type runtime_ownership = Held | Released_for_finalize
type finalize_outcome = Not_finished | Finalize_succeeded | Finalize_failed_reported

type statement_state = {
  wrapper : wrapper_reachability;
  native : native_statement;
  runtime : runtime_ownership;
  explicit_finalize_count : int;
  custom_finalize_count : int;
  outcome : finalize_outcome;
}

type statement_event =
  | Begin_explicit_finalize
  | Explicit_finalize_succeeded
  | Explicit_finalize_failed
  | Become_collectible
  | Begin_custom_finalize
  | Custom_finalize_returned

type close_v2_release =
  | Close_v2_handle_open
  | Close_v2_deferred_release
  | Close_v2_physical_release

type close_v2_state = {
  close_v2_release : close_v2_release;
  retained_statements : int;
  close_authority_terminal : bool;
  native_close_calls : int;
  finalize_failure_observed : bool;
  finalize_failure_reported : bool;
}

type close_v2_event =
  | Retain_statement
  | Accept_close_v2
  | Finalize_retained_succeeded
  | Finalize_retained_failed
  | Retry_close_v2

type actor_lifecycle = Open | Closing | Closed | Failed
type database_ownership = Owned_open | Owned_busy | Released
type writer_state = Not_spawned | Running | Joined
type stop_acknowledgement = No_ack | Success_ack | Failure_ack of string

type cleanup_origin =
  | No_cleanup
  | Configure_cleanup
  | Schema_cleanup
  | Spawn_cleanup
  | Enqueue_cleanup
  | Failure_drain_cleanup
  | Close_busy_cleanup

type cleanup_owner =
  | No_cleanup_owner
  | Opening_domain_owner
  | Writer_generation_owner of int

type quiescence_freshness =
  | No_quiescence_receipt
  | Strictly_newer_quiescence
  | Stale_or_older_quiescence

type actor_state = {
  lifecycle : actor_lifecycle;
  database : database_ownership;
  writer : writer_state;
  acknowledgement : stop_acknowledgement;
  close_attempts : int;
  remaining_global_budget : int;
  remaining_generation_budget : int;
  close_owner_count : int;
  elected_generation : int;
  generation_quiescence_epoch : int;
  generation_quiescence_freshness : quiescence_freshness;
  quiescence_epoch : int;
  authorized_quiescence_epoch : int;
  terminal_generation_receipt : int;
  writer_terminal_receipt : stop_acknowledgement;
  writer_terminal : bool;
  external_join_observed : bool;
  followers_waiting : int;
  followers_receipted : int;
  follower_acknowledgement : stop_acknowledgement;
  admitted : int;
  current : int;
  queued : int;
  results : int;
  late_admissions : int;
  retry_budget_resets : int;
  cleanup_obligation : cleanup_origin;
  cleanup_owner : cleanup_owner;
}

type actor_event =
  | Spawn_writer
  | Configure_failed_released
  | Configure_failed_retained
  | Schema_failed_released
  | Schema_failed_retained
  | Spawn_failed
  | Post_spawn_failed_released
  | Post_spawn_failed_retained
  | Enqueue_request
  | Enqueue_failed_released
  | Enqueue_failed_retained
  | Start_request
  | Complete_request
  | Fail_request
  | Failure_drain_failed_released
  | Failure_drain_failed_retained
  | Observe_quiescence
  | Authorize_close
  | Elect_close_owner
  | Observe_competing_close
  | Close_reported_busy
  | Close_succeeded
  | Join_writer

type law_result = {
  id : string;
  premise_reachable : bool;
  premise_witness : string option;
  holds : bool;
  counterexample : string option;
}

type mutant_result = {
  id : string;
  premise_reachable : bool;
  premise_witness : string option;
  killed : bool;
  witness : string option;
}

type report = {
  statement_states : int;
  close_v2_states : int;
  actor_states : int;
  healthy_statement_trace : bool;
  healthy_close_v2_trace : bool;
  healthy_close_trace : bool;
  laws : law_result list;
  mutants : mutant_result list;
}

type solver_answer = Sat | Unsat
type verdict = Proved | Refuted of string | Unavailable of string
type obligation_kind =
  | Theorem_negation
  | Premise_control
  | Healthy_control
  | Mutant_witness

type obligation = {
  id : string;
  kind : obligation_kind;
  expected : solver_answer;
}

type relation_metric = {
  relation_id : string;
  relation_states : int;
  relation_edges : int;
  relation_path_bound : int;
}

type smt_metrics = {
  script_bytes : int;
  path_assertions : int;
  obligation_count : int;
  relations : relation_metric list;
}

type smt_batch = {
  batch_id : string;
  batch_digest : string;
  batch_obligations : obligation list;
  batch_script : string;
  batch_relation : relation_metric;
}

exception Smt_script_limit_exceeded of int * int

val initial_statement : statement_state
val statement_events : statement_event list
val statement_step : statement_state -> statement_event -> statement_state option
val close_v2_events : close_v2_event list
val close_v2_step : close_v2_state -> close_v2_event -> close_v2_state option
(*@ next = statement_step state event
    ensures match next with
      | None -> true
      | Some state' -> state'.explicit_finalize_count >= 0 &&
                       state'.custom_finalize_count >= 0 *)

val initial_actor : actor_state
val actor_events : actor_event list
val actor_step : actor_state -> actor_event -> actor_state option
(*@ next = actor_step state event
    ensures match next with
      | None -> true
      | Some state' -> state'.close_attempts >= 0 &&
                       state'.admitted >= 0 && state'.results >= 0 *)

val explore : unit -> report
(*@ result = explore ()
    ensures result.statement_states > 1
    ensures result.actor_states > 1 *)

val obligations : obligation list
val transition_table_digest : unit -> string
val sha256 : string -> string
val bfs_certificates_valid : unit -> bool
val bfs_certificate_mutant_results : unit -> (string * bool) list
val bfs_certificate_mutants_rejected : unit -> bool
val progress_certificate_valid : unit -> bool
(*@ valid = progress_certificate_valid ()
    ensures valid *)
val progress_certificate_mutant_results : unit -> (string * bool) list
(*@ results = progress_certificate_mutant_results ()
    ensures List.length results = 3 *)
val progress_certificate_mutants_rejected : unit -> bool
(*@ rejected = progress_certificate_mutants_rejected ()
    ensures rejected *)
val raw_cleanup_encodings_valid : unit -> bool
(*@ valid = raw_cleanup_encodings_valid ()
    ensures valid *)
val raw_cleanup_encoding_mutant_results : unit -> (string * bool) list
(*@ results = raw_cleanup_encoding_mutant_results ()
    ensures List.length results = 3 *)
val raw_cleanup_encoding_mutants_rejected : unit -> bool
(*@ rejected = raw_cleanup_encoding_mutants_rejected ()
    ensures rejected *)
val mutant_prefixes_closed : report -> bool
val smt_batches_with_metrics : report -> smt_batch list * smt_metrics
val batch_is_canonical : smt_batch -> bool
val batch_manifest_complete : smt_batch list -> bool
val validate_batch_output : smt_batch -> string -> verdict
val expected_solver_output : unit -> string
val mutate_expected_output : id:string -> actual:solver_answer -> (string, string) result
val validate_solver_output : string -> verdict
val smt2 : report -> string
val smt2_with_metrics : report -> string * smt_metrics
