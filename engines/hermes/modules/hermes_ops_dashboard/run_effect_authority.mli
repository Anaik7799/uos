(** Durable, apply-once authority for closed Task 7 effects.

    The interpreter accepts one caller-owned {!Dependability_sqlite.owned_database}
    and never acquires native SQLite, finalization, close, process, or Domain
    authority.  A target declares the closed effect kinds it accepts.  Success
    is creditable only through a target-native receipt that echoes the stable
    key, request digest, target authority digest, and bounded redacted evidence
    identity. *)

type effect_kind = Run_topology.effect_kind =
  | Dependability_process_attempt
  | Verification_suite_execution
  | Durable_artifact_publication
  | External_resource_observation
  | Repository_source_observation
  | Approval_nonce_consumption
  | Writer_lease_transition
  | Production_activation_transition
  | Network_scope_transition
  | Credential_lease_transition
  | Controlled_filesystem_materialization
  | Candidate_tree_verification
  | Jujutsu_observation
  | Jujutsu_local_mutation
  | Jujutsu_history_rewrite
  | Jujutsu_recovery
  | Jujutsu_remote_synchronization
  | Jujutsu_remote_publish
  | Formal_oracle_execution

type diagnostic_code =
  | Invalid_effect_request
  | Invalid_effect_target
  | Effect_kind_not_accepted
  | Invalid_idempotency_key
  | Effect_key_conflict
  | Effect_target_failure
  | Effect_receipt_invalid
  | Effect_ledger_unavailable
  | Effect_interpreter_closed
  | Invalid_target_registry_schema
  | Target_registry_schema_conflict

type hazard =
  | Effect_request_invalid
  | Effect_target_invalid
  | Effect_kind_unauthorized
  | Effect_identity_conflict
  | Effect_outcome_uncertain
  | Effect_ledger_corrupt

type diagnostic = private {
  code : diagnostic_code;
  bytes : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  hazard : hazard;
}

type request = private {
  effect_kind : effect_kind;
  request_bytes : string;
  request_digest : string;
}

val make_request :
  effect_kind:effect_kind -> request_bytes:string ->
  (request, diagnostic) result
(** Rejects empty bytes and derives a lowercase SHA-256 over the closed kind and
    length-framed request bytes. *)

type disposition = First_applied | Replayed

type evidence_disposition = Evidence_succeeded | Evidence_unavailable

type redacted_evidence = private {
  evidence_receipt_id : string;
  evidence_digest : string;
  evidence_disposition : evidence_disposition;
}

val make_redacted_evidence :
  receipt_id:string -> evidence_digest:string ->
  disposition:evidence_disposition -> (redacted_evidence, diagnostic) result
(** Nonauthorizing audit evidence only.  It contains no payload, capability,
    handle, callback, source bytes, or reconstructible target output. *)

type target_receipt = private {
  idempotency_key : string;
  request_digest : string;
  target_authority_digest : string;
  disposition : disposition;
  evidence : redacted_evidence;
  receipt_digest : string;
}

val make_target_receipt :
  idempotency_key:string -> request:request ->
  target_authority_digest:string -> disposition:disposition ->
  evidence:redacted_evidence -> (target_receipt, diagnostic) result
(** The receipt digest binds every field; callers cannot supply any digest. *)

val target_receipt_evidence : target_receipt -> redacted_evidence
val evidence_receipt_id : redacted_evidence -> string
val evidence_digest : redacted_evidence -> string
val evidence_disposition : redacted_evidence -> evidence_disposition
val redacted_evidence_json : redacted_evidence -> Yojson.Safe.t

type target

val make_target :
  target_id:string -> authority_digest:string ->
  accepted_kinds:effect_kind list ->
  apply_once:(idempotency_key:string -> request ->
    (target_receipt, string) result) ->
  query:(idempotency_key:string ->
    (target_receipt option, string) result) ->
  (target, diagnostic) result
(** The accepted-kind set must be nonempty and duplicate-free.  It is part of
    the target identity; no generic string action exists.  This is a low-level
    test/adapter foundation and is not Task-7 topology admission. *)

type target_registry

type target_authority_status = Concrete_target_authority_unavailable

type action_target_binding = private {
  binding_activity_id : string;
  binding_action_id : string;
  binding_target_component_id : string;
  binding_effect_kind : effect_kind;
  binding_target_authority_digest : string option;
  binding_target_authority_status : target_authority_status;
  binding_dependency_schema_id : string;
}

type jj_target_registry_schema

(** Immutable schema derived from the exact currently constructible Task-7A
    action denominator.  Target authority is explicitly unavailable rather
    than represented by a caller digest. *)
val canonical_jj_target_registry_schema : unit -> jj_target_registry_schema
val jj_target_registry_bindings :
  jj_target_registry_schema -> action_target_binding list
val jj_target_registry_schema_digest : jj_target_registry_schema -> string
val validate_jj_target_registry_schema_exact :
  jj_target_registry_schema -> (unit, diagnostic list) result

type jj_target_registry

type target_schema_receipt = private {
  target_schema_digest : string;
  target_schema_binding_count : int;
  target_schema_receipt_digest : string;
  target_schema_was_replayed : bool;
}

type target_schema_state =
  | Target_schema_uninitialized
  | Target_schema_prepared
  | Target_schema_conflict

val create_jj_target_registry : unit -> jj_target_registry
val prepare_jj_target_registry_schema_once :
  jj_target_registry ->
  (target_schema_receipt, diagnostic list) result
val jj_target_registry_schema_state :
  jj_target_registry -> target_schema_state

type target_registry_prerequisite =
  | Concrete_target_authority_digests
  | Task9_target_current_views
  | Request_bound_phase_action_registry
  | Conditional_action_control_registry

type target_registry_unavailable = private {
  target_registry_unavailable_operation : string;
  target_registry_missing_prerequisites : target_registry_prerequisite list;
}

type jj_target_registry_current

val jj_target_registry_current_posture : [ `Implemented_unavailable ]
val target_registry_prerequisites : target_registry_prerequisite list
val close_jj_target_registry_current_unavailable :
  jj_target_registry -> target_schema_receipt ->
  (jj_target_registry_current, target_registry_unavailable) result

val expected_target_authority_digest :
  activity:Run_topology.admitted_activity -> target_id:string ->
  accepted_kinds:Run_topology.effect_kind list -> string
(** Binds the current topology authority, admitted activity digest, target id,
    and ordered closed effect-kind denominator. *)

val register_target :
  activity:Run_topology.admitted_activity ->
  target_id:string -> authority_digest:string ->
  accepted_kinds:Run_topology.effect_kind list ->
  apply_once:(idempotency_key:string -> request ->
    (target_receipt, string) result) ->
  query:(idempotency_key:string ->
    (target_receipt option, string) result) ->
  (target_registry, diagnostic list) result
(** Admits only the target and effect denominator declared by the topology;
    [authority_digest] must equal {!expected_target_authority_digest}. *)

type pending = private {
  idempotency_key : string;
  request_digest : string;
  target_authority_digest : string;
}

type indeterminate = private {
  idempotency_key : string;
  request_digest : string;
  target_authority_digest : string;
  diagnostic_bytes : string;
  no_replay : bool;
}

type state =
  | Pending of pending
  | Applied of target_receipt
  | Indeterminate_effect of indeterminate

type key_conflict = private {
  idempotency_key : string;
  persisted_digest : string;
  observed_digest : string;
  diagnostic : diagnostic;
}

type error =
  | Invalid_request of diagnostic
  | Key_reused_with_different_request of key_conflict
  | Target_unavailable of diagnostic
  | Indeterminate of state * diagnostic
  | Ledger_failure of diagnostic

type receipt = target_receipt
type interpreter

val open_interpreter :
  database:Dependability_sqlite.owned_database -> target:target ->
  coordinate:Ops_capability.coordinate -> (interpreter, error) result
(** The caller retains the only database close authority.  The interpreter
    owns one mutex and initializes/validates its v1 ledger schema. *)

val open_admitted_interpreter :
  database:Dependability_sqlite.owned_database ->
  registry:target_registry -> coordinate:Ops_capability.coordinate ->
  (interpreter, error) result
(** The only topology-admitted opening surface.  It revalidates the registry
    before delegating to the low-level apply-once interpreter exactly once. *)

val validate_admitted_interpreter :
  activity:Run_topology.admitted_activity -> interpreter ->
  (unit, diagnostic list) result
(** Revalidates that the interpreter retains the exact admitted activity,
    topology, target, target-authority, and ordered effect-kind identities.
    A low-level interpreter returned by {!open_interpreter} is never admitted. *)

val apply_once :
  interpreter -> idempotency_key:string -> request ->
  (receipt, error) result
(** Persists [Pending] before querying the target exactly once.  A valid
    target-native receipt is atomically persisted as [Applied].  A raise or
    receipt mismatch after possible actuation is persisted as
    [Indeterminate_effect { no_replay = true; _ }] and is never retried.  A
    reused key with a different request digest is a permanent conflict. *)

val query :
  interpreter -> idempotency_key:string -> (state option, error) result
(** Reads only the authoritative ledger; it never invokes the target. *)

val close : interpreter -> unit
(** Closes only this scoped interpreter.  It does not close or finalize the
    caller-owned database. *)

val string_of_effect_kind : effect_kind -> string
val string_of_diagnostic_code : diagnostic_code -> string
val string_of_hazard : hazard -> string

module For_test : sig
  type admitted_identity_mutation =
    | Activity_digest
    | Topology_authority_digest
    | Target_digest
    | Effect_kinds_digest

  val mutate_admitted_identity :
    admitted_identity_mutation -> interpreter -> interpreter
  (** Narrow carrier mutation seam.  It cannot create admission identity for a
      low-level interpreter and grants no target or effect authority. *)

  type target_schema_mutation =
    | Drop_action_binding
    | Add_action_binding
    | Duplicate_action_binding
    | Reorder_action_bindings
    | Cross_activity_binding
    | Swap_target_component
    | Swap_effect_kind
    | Change_dependency_schema
    | Forge_target_authority

  val mutate_jj_target_registry_schema :
    target_schema_mutation -> jj_target_registry_schema
  val prepare_jj_target_registry_schema_with_mutation :
    jj_target_registry -> target_schema_mutation ->
    (target_schema_receipt, diagnostic list) result
end
