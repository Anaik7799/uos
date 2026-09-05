(** Append-only run-event authority over one actor-owned SQLite connection. *)

type t

val open_store : Dependability_sqlite_location.reference -> (t, string) result
val close : t -> unit
val append : t -> Run_model.event -> (unit, string) result

val events : t -> run_id:string -> (Run_model.event list, string) result

val events_after :
  t -> run_id:string -> sequence:int64 -> (Run_model.event list, string) result

val snapshot : t -> run_id:string -> (Run_snapshot.t, string) result
val runs : t -> limit:int -> (Run_snapshot.summary list, string) result

(** Native event-prefix read-only owner boundary.

    The exact admitted-plan and typed prefix-denominator carriers do not yet
    exist.  This foundation consequently accepts no string substitute and
    returns no event list, payload, store handle, digest input, or callback.
    The actor-owned [t] is retained only so the future constructor cannot query
    outside its owning ledger. *)

type prefix_rca_origin =
  | Prefix_specification
  | Prefix_implementation
  | Prefix_environment
  | Prefix_evidence
  | Prefix_control

type prefix_prerequisite =
  | Typed_execution_identity_current_carrier
  | Admitted_plan_current_carrier
  | Typed_prefix_denominator_current_carrier
  | Dispatch_claim_current_carrier
  | Owner_session_current_carrier
  | Terminal_target_disposition_current_carrier

type prefix_diagnostic

val prefix_prerequisite_id : prefix_prerequisite -> string
val prefix_prerequisite_status :
  prefix_prerequisite -> (unit, prefix_diagnostic) result
val prefix_diagnostic_code : prefix_diagnostic -> string
val prefix_diagnostic_prerequisite : prefix_diagnostic -> prefix_prerequisite
val prefix_diagnostic_coordinate : prefix_diagnostic -> string
val prefix_diagnostic_origin : prefix_diagnostic -> prefix_rca_origin

type event_prefix_current

val prepare_event_prefix : t -> (event_prefix_current, prefix_diagnostic) result
(** Fails before ledger query with [Admitted_plan_current_carrier].  No
    overload accepting an execution string, plan digest, prefix list, event
    list, payload, callback, or caller-computed digest exists. *)

val event_prefix_production_posture : [ `Implemented_unavailable ]
val event_prefix_source_digest : string

(** Narrow native-test seam. This injects a terminal writer failure through
    the typed actor protocol; it is not an operational control surface. *)
module For_test : sig
  type prefix_source_mutation =
    | Drop_execution_binding
    | Drop_plan_binding
    | Drop_prefix_denominator
    | Drop_owner_session_binding
    | Drop_event_identity
    | Drop_sequence_binding
    | Drop_previous_digest_binding
    | Accept_gap
    | Accept_duplicate
    | Accept_noncontiguous_prefix
    | Accept_running_target
    | Accept_cross_context
    | Accept_stale_owner
    | Expose_event_list
    | Expose_event_payload
    | Expose_store_handle
    | Add_caller_digest
    | Add_callback
    | Construct_current_without_readback

  val event_prefix_source_digest_with_mutation :
    prefix_source_mutation -> string

  type lifecycle_observation =
    | Observed_open
    | Observed_closing
    | Observed_failed
    | Observed_close_failed
    | Observed_closed

  type fault =
    | Drop_next_reply
    | Fail_next_failure_drain

  type open_fault =
    | Fail_after_spawn_before_registration
    | Unsupported_schema

  type history_fault =
    | Malformed_stored_event of string

  type finalize_summary = {
    intervals : int;
    succeeded : int;
    failed : int;
    active : bool;
  }

  type finalize_interval = {
    database_identity : int;
    statement_identity : int;
    interval_identity : int;
    outcome : Dependability_sqlite.finalize_interval_outcome;
  }

  type active_finalize_interval = {
    active_database_identity : int;
    active_interval_identity : int;
  }

  (** Return the internal typed close outcome without weakening the legacy
      production [close] signature. Repeated and concurrent callers observe the
      same terminal result. *)
  val close_result : t -> (unit, string) result

  (** Arm one explicitly injected policy-Busy close result.  This is mutant and
      recovery evidence only; it is never described as native SQLite behavior. *)
  val install_close_blocker : t -> (unit, string) result

  (** Clear the injected policy-Busy fixture after its failed-close receipt,
      restoring the pre-close lifecycle so a fresh generation can be elected. *)
  val release_close_blocker : t -> (unit, string) result

  val arm_fault : t -> fault -> (unit, string) result

  val open_store_with_fault :
    open_fault -> Dependability_sqlite_location.reference -> (t, string) result

  (** Closed actor-owned adversarial seams.  Callers can provide typed events
      and run identifiers, never SQL, a native handle, or a location. *)
  val inject_history : t -> Run_model.event -> (unit, string) result
  val inject_history_fault : t -> history_fault -> (unit, string) result
  val verify_append_only_guards : t -> (unit, string) result

  val lifecycle : t -> lifecycle_observation
  val writer_joined : t -> bool
  val close_attempts : t -> int
  val authority_state : t -> Dependability_sqlite.database_state
  val finalize_summary : t -> finalize_summary
  val finalize_interval_active : t -> bool
  val finalize_intervals : t -> finalize_interval list

  (** Returns an identity only when one exact interval is observed between two
      identical completed-history snapshots. *)
  val active_finalize_interval : t -> active_finalize_interval option

  (** Exercise a real constraint/finalize failure wholly on the actor-owned
      scoped connection and return its typed rendering. *)
  val exercise_finalize_failure : t -> (unit, string) result

  (** Test-process cleanup only after an intentionally exhausted lifetime close
      budget.  It does not reset or retry the operational close authority, and
      publishes [Observed_closed] only after forced physical release and join. *)
  val force_cleanup : t -> (unit, string) result

  val fail_writer : t -> string -> (unit, string) result
end
