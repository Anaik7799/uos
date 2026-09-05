(** Pure, non-authorizing process declaration protocol.

    A declaration binds closed roles and obligations only.  It contains no
    executable, argv, environment value, path, clock, SQLite value, callback,
    effect function, or execution capability. *)

type process_role = Jujutsu_process | Candidate_process | Formal_process

type obligation =
  | Exact_source
  | Exact_configuration
  | Approval_required
  | Writer_lease_required
  | Resource_preflight_required
  | Bridge_admission_required
  | Apply_once_receipt_required
  | Readback_required
  | Remote_publication_cas_required

type availability =
  | Bridge_unavailable
  | Formal_oracle_unavailable
  | Remote_publication_unavailable_without_cas

type declaration

type projection = private {
  request_id : Jj_id.Request.t;
  kind : Jj_process_protocol.request_kind;
  process_role : process_role;
  target : Jj_target_protocol.t;
  budget : Jj_budget.t;
  recovery : Jj_operation.recovery_policy;
  obligations : obligation list;
  availability : availability;
  digest : string;
}

type reconciliation = Stable_replay | Identity_conflict | Different_request

val schema_id : string
val all_kinds : Jj_process_protocol.request_kind list

val declare :
  request_id:Jj_id.Request.t -> Jj_process_protocol.request_kind -> declaration

val projection : declaration -> projection
val digest : declaration -> string
val reconcile : declaration -> declaration -> reconciliation

(** Digest of the exact kind denominator and every derived declaration row. *)
val source_digest : string

module For_test : sig
  type mutation =
    | Drop_row
    | Duplicate_row
    | Swap_target
    | Widen_budget
    | Remove_recovery
    | Promote_availability
    | Drop_obligation
    | Add_candidate_writer_lease
    | Add_formal_writer_lease

  val source_digest_with_mutation : mutation -> string
end
