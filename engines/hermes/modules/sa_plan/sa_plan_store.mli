open Core

(** Durable Sa-plan state. Claims are at-least-once leases; callers obtain
    exactly-once observable effects only by using [complete_activity] with a
    stable workflow/activity key. *)

type t

(** Durable bridge carrier: one OODA mapping, immutable provenance, ordered
    events, and delivery receipts. Commands are effectively-once by stable id
    plus request hash; external delivery remains at-least-once. *)
type bridge_domain = Sa_plan_control_plane.domain =
  | Otp_parity
  | Sa_plan
  | Infranodus
  | Documentation
  | Fdc

type bridge_mapping_request = {
  domain : bridge_domain;
  ooda_slice_id : string;
  idempotency_key : string;
  source_fingerprint : string;
  dependency_snapshot : string;
  prompt_ledger_hash : string;
  safety_packet_hash : string;
  formal_evidence_hash : string;
  sa_plan_id : string option;
  sa_task_id : string option;
  lifecycle_state : string;
  created_at_ns : int64;
}

type bridge_mapping = {
  id : string;
  domain : bridge_domain;
  ooda_slice_id : string;
  idempotency_key : string;
  source_fingerprint : string;
  dependency_snapshot : string;
  prompt_ledger_hash : string;
  safety_packet_hash : string;
  formal_evidence_hash : string;
  sa_plan_id : string option;
  sa_task_id : string option;
  lifecycle_state : string;
  version : int64;
}

type bridge_command_receipt = {
  mapping_id : string;
  command_id : string;
  request_hash : string;
  result : string;
  replayed : bool;
  recorded_at_ns : int64;
}

type bridge_event = {
  mapping_id : string;
  sequence : int64;
  version : int64;
  kind : string;
  payload : string;
  occurred_at_ns : int64;
}

type outbox_state = Outbox_pending | Outbox_delivered

type bridge_outbox = {
  id : string;
  mapping_id : string;
  command_id : string;
  event_sequence : int64;
  endpoint : string;
  state : outbox_state;
}

type bridge_ack = {
  consumer : string;
  outbox_id : string;
  replayed : bool;
  outbox : bridge_outbox;
}

type bridge_atomic_enqueue = {
  receipt : bridge_command_receipt;
  event : bridge_event;
  outbox : bridge_outbox;
}

(** A durable, fenced lease.  [fencing_token] is monotone per mapping; an
    external side effect still needs its own idempotency key. *)
type bridge_lease = {
  mapping_id : string;
  owner : string;
  lease_id : string;
  fencing_token : int64;
  expires_at_ns : int64;
  task_attempt : int option;
}

type summary = { total : int; completed : int; ready : int; executing : int }
type claim = { task_id : string; attempt : int; lease_until_ns : int64 }
type plan_view = { id : string; name : string; title : string }

type task_view = {
  plan_id : string;
  id : string;
  name : string;
  title : string;
  parent_id : string option;
  state : string;
  priority : int;
  worker : string option;
  attempt : int;
}

type job_state =
  | Job_available
  | Job_executing
  | Job_retry
  | Job_completed
  | Job_discarded
  | Job_cancelled

type job_view = {
  id : string;
  name : string;
  queue : string;
  worker : string;
  args : string;
  state : job_state;
  attempt : int;
  max_attempts : int;
  available_at_ns : int64;
  lease_owner : string option;
  lease_until_ns : int64 option;
  result : string option;
}

type workflow_event = {
  sequence : int;
  kind : string;
  payload : string;
  occurred_at_ns : int64;
}

type selection_factors = {
  stpa : int;
  fema : int;
  criticality : int;
  dependency : int;
  standards : int;
  agent_fit : int;
}

type selection_evidence = {
  actor : string;
  old_priority : int option;
  new_priority : int;
  factors : selection_factors;
  rationale : string;
  recorded_at_ns : int64;
}

type task_observation = {
  task : task_view;
  estimate_points : int option;
  lease_until_ns : int64 option;
  dependencies : string list;
  selection : selection_evidence option;
}

type workflow_view = {
  id : string;
  name : string;
  kind : string;
  input : string;
  state : string;
  result : string option;
  created_at_ns : int64;
  completed_at_ns : int64 option;
  events : workflow_event list;
}

(** Persistent interpretation of one normalized session observation. *)
type session_observation_row = {
  hermes_sequence : int64;
  source_journal_ref : string;
  host_boot_id : string;
  event_id : string;
  payload_hash : string;
  local_sequence : int64;
  session_ref : string;
  resource_ref : string;
  epoch : int64;
  candidate_ref : string;
}

type session_observation_write = {
  source_journal_ref : string;
  host_boot_id : string;
  event_id : string;
  declared_payload_hash : string;
  computed_payload_hash : string;
  local_sequence : int64;
  session_ref : string;
  resource_ref : string;
  epoch : int64;
  candidate_ref : string;
}

type session_reconciliation_kind =
  | Payload_hash_mismatch
  | Body_conflict
  | Sequence_conflict
  | Sequence_gap
  | Out_of_order

type session_reconciliation = {
  reconciliation_sequence : int64;
  kind : session_reconciliation_kind;
  source_journal_ref : string;
  host_boot_id : string;
  event_id : string;
  declared_payload_hash : string;
  computed_payload_hash : string;
  local_sequence : int64;
  expected_sequence : int64 option;
}

type session_observation_store_outcome =
  | Observation_stored of {
      observation : session_observation_row;
      replayed : bool;
    }
  | Observation_reconciliation of session_reconciliation

val open_db : string -> (t, string) Result.t
val close : t -> unit
val schema_version : t -> int

(** [with_transaction store body] runs [body] under one [BEGIN IMMEDIATE].
    Store operations called by [body] join that transaction instead of opening
    nested transactions.  [Error] or an exception rolls the whole body back;
    callers must propagate nested operation errors rather than suppress them.
    One store connection remains single-owner while the callback is active. *)
val with_transaction :
  t -> (unit -> ('a, string) Result.t) -> ('a, string) Result.t

(** Atomically validates the declared/computed hash pair, global event
    idempotency and contiguous order in the stable journal namespace.
    A matching retry returns the original row. A refusal appends a durable
    reconciliation record and inserts no inbox row. This operation has no SQL
    path to plans, tasks, leases, workflows, dispatch, approval, or budgets. *)
val ingest_session_observation :
  t ->
  session_observation_write ->
  (session_observation_store_outcome, string) Result.t

(** Read-only, ordered reconciliation observation used by recovery tooling. *)
val list_session_reconciliations :
  t ->
  source_journal_ref:string ->
  (session_reconciliation list, string) Result.t

val ensure_bridge_mapping :
  t -> bridge_mapping_request -> (bridge_mapping, string) Result.t

val find_bridge_mapping : t -> id:string -> (bridge_mapping option, string) Result.t

val record_bridge_command :
  t ->
  mapping_id:string ->
  command_id:string ->
  request_hash:string ->
  result:string ->
  recorded_at_ns:int64 ->
  (bridge_command_receipt, string) Result.t

val find_bridge_command :
  t ->
  mapping_id:string ->
  command_id:string ->
  (bridge_command_receipt option, string) Result.t

val append_bridge_event :
  t ->
  mapping_id:string ->
  kind:string ->
  payload:string ->
  occurred_at_ns:int64 ->
  (bridge_event, string) Result.t

val record_command_and_enqueue_outbox :
  t ->
  mapping_id:string ->
  command_id:string ->
  request_hash:string ->
  result:string ->
  event_kind:string ->
  event_payload:string ->
  endpoint:string ->
  outbox_id:string ->
  recorded_at_ns:int64 ->
  (bridge_atomic_enqueue, string) Result.t

val ack_bridge_outbox :
  t ->
  consumer:string ->
  outbox_id:string ->
  acknowledged_at_ns:int64 ->
  (bridge_ack, string) Result.t

(** cp-27: rows with no ack row for [consumer], in deterministic
    (mapping, event sequence, id) order. Read-only. *)
val list_pending_bridge_outbox :
  t -> consumer:string -> (bridge_outbox list, string) Result.t

val record_bridge_preflight :
  t ->
  mapping_id:string ->
  packet_hash:string ->
  decision:string ->
  recorded_at_ns:int64 ->
  (unit, string) Result.t

val record_bridge_reconciliation :
  t ->
  mapping_id:string ->
  kind:string ->
  outcome:string ->
  recorded_at_ns:int64 ->
  (unit, string) Result.t

val claim_bridge_lease :
  t ->
  mapping_id:string ->
  owner:string ->
  lease_id:string ->
  now_ns:int64 ->
  lease_ns:int64 ->
  (bridge_lease, string) Result.t

val find_bridge_lease :
  t -> mapping_id:string -> (bridge_lease option, string) Result.t

(** Completes the mapped task only if [owner], [lease_id], and
    [fencing_token] describe the current durable lease AND its recorded task
    attempt still owns the task. Both leases must expire strictly after [now_ns].
    Schema-v6 leases migrate with [task_attempt = None] and cannot complete;
    expiry and a fresh claim establish a binding, never a lookup at completion. *)
val complete_bridge_task :
  t ->
  mapping_id:string ->
  owner:string ->
  lease_id:string ->
  fencing_token:int64 ->
  result:string ->
  now_ns:int64 ->
  (unit, string) Result.t

val register_plan :
  t ->
  id:string ->
  title:string ->
  nodes:Sa_plan_management.plan_node list ->
  (unit, string) Result.t

val create_plan :
  t ->
  id:string ->
  name:string ->
  title:string ->
  now_ns:int64 ->
  (unit, string) Result.t

val find_plan : t -> id_or_name:string -> (plan_view option, string) Result.t

val rename_plan :
  t ->
  id_or_name:string ->
  new_name:string ->
  now_ns:int64 ->
  (unit, string) Result.t

val create_task :
  t ->
  plan_id:string ->
  id:string ->
  name:string ->
  title:string ->
  parent_id:string option ->
  dependencies:string list ->
  priority:int ->
  now_ns:int64 ->
  (unit, string) Result.t

val find_task :
  t ->
  plan_id:string ->
  id_or_name:string ->
  (task_view option, string) Result.t

val list_tasks : t -> plan_id:string -> (task_view list, string) Result.t

val rename_task :
  t ->
  plan_id:string ->
  id_or_name:string ->
  new_name:string ->
  now_ns:int64 ->
  (unit, string) Result.t

val summary : t -> plan_id:string -> (summary, string) Result.t

(** Claims require a non-empty worker, non-negative observed time, positive
    duration and representable deadline/next attempt. Expiry is exclusive:
    a lease is reclaimable at [now_ns = lease_until_ns]. Dependencies must be
    completed. The returned attempt must be retained by the original caller. *)
val claim_next :
  t ->
  plan_id:string ->
  worker:string ->
  now_ns:int64 ->
  lease_ns:int64 ->
  (claim option, string) Result.t

val claim_task :
  t ->
  plan_id:string ->
  task_id:string ->
  worker:string ->
  now_ns:int64 ->
  lease_ns:int64 ->
  (claim, string) Result.t

(** Finalization law: only the caller's original [expected_attempt], current
    worker, executing state and strictly unexpired lease permit a transition.
    Empty worker, non-positive attempt or negative time is rejected. Rejection
    changes no state, including when a worker name is reused after takeover.
    The store trusts [now_ns] supplied by its supervised local clock adapter;
    this is a concurrency fence, not authentication or remote-effect authority. *)
val release_task :
  t ->
  plan_id:string ->
  task_id:string ->
  worker:string ->
  expected_attempt:int ->
  now_ns:int64 ->
  (unit, string) Result.t

val complete_task :
  t ->
  plan_id:string ->
  task_id:string ->
  worker:string ->
  expected_attempt:int ->
  result:string ->
  now_ns:int64 ->
  (unit, string) Result.t

val complete_activity :
  t ->
  workflow_id:string ->
  activity_id:string ->
  result:string ->
  now_ns:int64 ->
  (string, string) Result.t

val record_selection :
  t ->
  plan_id:string ->
  task_id:string ->
  actor:string ->
  old_priority:int option ->
  new_priority:int ->
  factors:selection_factors ->
  rationale:string ->
  now_ns:int64 ->
  (unit, string) Result.t

val latest_selection :
  t ->
  plan_id:string ->
  task_id:string ->
  (selection_evidence option, string) Result.t

val list_task_observations :
  t -> plan_id:string -> (task_observation list, string) Result.t

val enqueue_job :
  t ->
  id:string ->
  name:string ->
  queue:string ->
  worker:string ->
  args:string ->
  max_attempts:int ->
  now_ns:int64 ->
  (job_view, string) Result.t

val claim_job :
  t ->
  queue:string ->
  worker:string ->
  now_ns:int64 ->
  lease_ns:int64 ->
  (job_view option, string) Result.t

val retry_delay_ns : attempt:int -> int64
(** C3I/Oban retry class: 15 seconds times [2^attempt], capped at one hour. *)

(** Same finalization law as [release_task], for success and error/retry alike.
    The original job claim attempt is required, never inferred from a live row.
    Retry deadline overflow is rejected without modifying the job. *)
val complete_job :
  t ->
  id_or_name:string ->
  worker:string ->
  expected_attempt:int ->
  outcome:[ `Ok of string | `Error of string ] ->
  now_ns:int64 ->
  (job_view, string) Result.t

(** Irreversibly marks an available, retrying, or executing job cancelled.
    Terminal jobs refuse the transition. *)
val cancel_job :
  t ->
  id_or_name:string ->
  reason:string ->
  now_ns:int64 ->
  (job_view, string) Result.t

val list_jobs : t -> queue:string option -> (job_view list, string) Result.t

val start_workflow :
  t -> id:string -> name:string -> now_ns:int64 -> (unit, string) Result.t

val start_workflow_with_input :
  t ->
  id:string ->
  name:string ->
  kind:string ->
  input:string ->
  now_ns:int64 ->
  (unit, string) Result.t

val complete_workflow :
  t ->
  id_or_name:string ->
  result:string ->
  now_ns:int64 ->
  (unit, string) Result.t

val fail_workflow :
  t ->
  id_or_name:string ->
  error:string ->
  now_ns:int64 ->
  (unit, string) Result.t

val complete_workflow_activity :
  t ->
  workflow_id_or_name:string ->
  id:string ->
  name:string ->
  idempotency_key:string ->
  result:string ->
  now_ns:int64 ->
  (string, string) Result.t

val workflow_history :
  t -> id_or_name:string -> (workflow_event list, string) Result.t

val list_workflows : t -> (workflow_view list, string) Result.t
