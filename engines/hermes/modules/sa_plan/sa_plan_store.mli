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

type job_cancellation = {
  mapping_id : string;
  effect_id : string;
  intent_sha256 : string;
  owner : string;
  lease_id : string;
  fencing_token : int64;
  target_job_id : string;
  target_worker : string;
  target_attempt : int;
  target_lease_until_ns : int64;
  reason : string;
  expires_at_ns : int64;
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

(** Open an existing exact-v7 store without creating a file, initializing DDL or
    migrating schema. Missing/old/future/corrupt stores refuse. The caller must
    protect the path and directory; this is not principal authentication. *)
val open_existing : string -> (t, string) Result.t
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

(** [bind_bridge_to_claimed_task store ~mapping_id ~owner ~expected_attempt
    ~lease_id ~now_ns ~lease_ns] binds a Telegram cancellation bridge lease to
    an already-claimed canonical [Sa_plan] task without mutating, creating,
    reclaiming, or advancing the canonical task row or its attempt counter.

    Laws:
    - Canonical task non-mutation: never creates, mutates, reclaims, or advances
      [sa_plan_task] or its [attempt]; [claim_bridge_lease] remains unchanged.
    - Atomic observation and write: executes inside [transaction store]
      ([BEGIN IMMEDIATE]), covering [mapping_id] lookup, live canonical task
      ([worker = owner], [attempt = expected_attempt], [state = 'executing'],
      [lease_until_ns]) observation, prior bridge inspection, and bridge write.
    - Preconditions: requires valid non-empty identities ([mapping_id], [owner],
      [lease_id]) without leading/trailing whitespace, [expected_attempt > 0],
      [now_ns >= 0L], and positive [lease_ns > 0L] with overflow-checked
      [expires_at_ns] via [lease_deadline ~worker:owner ~now_ns ~lease_ns].
      Mapping must exist with domain [Sa_plan] and materialized plan/task IDs.
    - Canonical task lease envelope: [sa_plan_task] must be in state
      ['executing'] for [owner] at [expected_attempt] with SQLite [INT]
      [lease_until_ns > now_ns] and [lease_until_ns >= expires_at_ns] (requested
      bridge expiry beyond the canonical task lease is rejected, never clamped;
      NULL/non-INT or stale/wrong-owner/wrong-attempt rows refuse with a named
      redacted error).
    - Bridge exclusivity and fencing: any existing live bridge row
      ([expires_at_ns > now_ns]) unconditionally refuses even for the same
      [owner] (callers resolve ambiguous prior outcomes via [find_bridge_lease]);
      missing prior starts at [fencing_token = 1L]; expired prior requires
      [0L < fencing_token < Int64.max_value] and advances to [fencing_token + 1L].
      No existing row is altered on any refusal.
    - Write effect and trust boundary: writes only [sa_plan_bridge_lease] with
      [task_attempt = Some expected_attempt]. This is a trusted bounded store
      operation, not runtime/signature admission; live callers must still hold
      current coordinator, time, and profile fences. *)
val bind_bridge_to_claimed_task
  :  t
  -> mapping_id:string
  -> owner:string
  -> expected_attempt:int
  -> lease_id:string
  -> now_ns:int64
  -> lease_ns:int64
  -> (bridge_lease, string) result

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

(** Renewal law: only the same worker and exact original attempt may renew an
    executing claim with lease_until_ns strictly greater than now_ns. Duration
    is positive and at most one hour, with checked deadline arithmetic. Renewal
    never shortens the lease or changes state, owner, or attempt. Rejection
    changes no state. BEGIN IMMEDIATE serializes renewal against reclamation. *)
(** Live callers sample their authoritative clock only after acquiring the
    immediate write transaction, so waiting for a database lock cannot revive
    a claim that expired during contention. *)
val renew_task_observed :
  t ->
  plan_id:string ->
  task_id:string ->
  worker:string ->
  expected_attempt:int ->
  observe_now:(unit -> int64) ->
  lease_ns:int64 ->
  (int64, string) Result.t

(** Deterministic clock adapter for callers that already own a sampled-time
    authority or fixtures. Live CLI renewal uses [renew_task_observed]. *)
val renew_task :
  t ->
  plan_id:string ->
  task_id:string ->
  worker:string ->
  expected_attempt:int ->
  now_ns:int64 ->
  lease_ns:int64 ->
  (int64, string) Result.t

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

(** Atomic database mechanics for a caller already authorized by the Gleam
    control plane. This function does NOT authenticate reviewer/operator
    signatures, prove synchronized time, stop processes, or cancel tasks.
    It is intentionally not exposed by the CLI or Telegram dispatcher.

    Law: within one BEGIN IMMEDIATE transaction, both the mapped task's original
    attempt and its bridge lease must still be current. The request deadline
    must be future and at most 300 seconds from supplied [now_ns]. The exact
    target id (not an alias), designated worker, lease owner, attempt and lease
    deadline must match an executing job in the mapped plan namespace.
    Only then is the job cancelled and its lease cleared, atomically with a
    durable bridge command receipt. Designated [worker] is retained.

    The namespaced command key is ["cancel-job:" ^ effect_id]. The store hashes
    all request fields plus the mapped plan/task in fixed, typed JSON order.
    Identical replay under the SAME current authority returns the original
    receipt without writing, only if the cancelled postcondition and original
    receipt payload still match. Changed request fields, missing/changed
    target state, an independently cancelled job, stale authority and malformed
    inputs return Error without a partial transition.
    Idempotency is scoped to mapping_id plus effect_id; neither hashes nor
    receipts prove approval authenticity. Expired/new-lease reconciliation
    must use a separately authorized read, not a fresh cancellation.
    All strings, counters and times are bounded before mutation. *)
val cancel_job_once :
  t -> job_cancellation -> now_ns:int64 ->
  (bridge_command_receipt, string) Result.t

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

(** Read-only historical cancellation receipt reconciliation. Matches the full
    original request digest and fixed receipt payload under its canonical mapping.
    The original request may be expired and its controller lease replaced.
    This does not authenticate a caller, observe current job/process state,
    extend authority, or authorize retrying an effect. A trusted read adapter
    must authenticate and scope the caller before invoking it. *)
val lookup_job_cancellation :
  t -> job_cancellation -> now_ns:int64 ->
  (bridge_command_receipt option, string) Result.t

(** Bounded read-only snapshot of an executing job target eligible for a
    fenced cancellation approval proposal. *)
type cancellation_target = {
  job_id : string;
  target_worker : string;
  target_attempt : int;
  target_lease_until_ns : int64;
}

(** [inspect_cancellation_target_observed store ~mapping_id ~owner ~lease_id
    ~fencing_token ~target_job_id ~observe_now] validates bounded ASCII tokens
    and a positive fence, enters an immediate SQLite transaction before calling
    [observe_now ()] once, and verifies that [mapping_id] is a canonical
    [Sa_plan] mapping whose current bridge lease and executing task match
    [owner], [lease_id], [fencing_token], and original bounded [task_attempt]
    with strictly future expiries at the observed nonnegative timestamp.
    Queries only [id, worker, attempt, lease_owner, lease_until_ns, state] for
    the exact [target_job_id] within the mapped plan prefix without loading
    private [args] or [result] columns or mutating state. Returns
    [Error "cancellation_target_refused"] on any validation, lookup, SQL, or
    exception failure. *)
val inspect_cancellation_target_observed :
  t ->
  mapping_id:string ->
  owner:string ->
  lease_id:string ->
  fencing_token:int64 ->
  target_job_id:string ->
  observe_now:(unit -> int64) ->
  (cancellation_target, string) result

(** Add one prerequisite; never remove an edge or rewrite registered provenance.
    Explicit maintenance task identity is a concurrency fence, not authentication. *)
type dependency_repair = {
  operation_id : string;
  plan_id : string;
  maintenance_task_id : string;
  worker : string;
  expected_attempt : int;
  target_task_id : string;
  prerequisite_task_id : string;
  expected_dependencies : string list;
}

type dependency_repair_receipt = {
  operation_id : string;
  plan_id : string;
  maintenance_task_id : string;
  worker : string;
  expected_attempt : int;
  target_task_id : string;
  prerequisite_task_id : string;
  request_sha256 : string;
  before_dependencies : string list;
  after_dependencies : string list;
  before_edges_sha256 : string;
  after_edges_sha256 : string;
  registered_graph_fingerprint : string;
  recorded_at_ns : int64;
  replayed : bool;
}

(** Owns one BEGIN IMMEDIATE, refuses nesting, then samples [observe_now].
    Rechecks exact plan/task/worker/attempt and exclusive lease expiry, available
    target, existing prerequisite, semantic dependency-set CAS and the actual
    bounded current graph's acyclicity. Maximum4096 tasks/16384 edges/256 expected
    and resulting dependencies; bounded ASCII identifiers. Unique operation receipts and exact
    audit-table/append-only-trigger definitions are checked in the same transaction.
    DDL is lazy and rolls back with any failure; existing v7 registration identity
    remains unchanged. Graph hashes/payloads precede a fresh prewrite clock/fence
    check immediately adjacent to INSERT. Receipt/edge/fingerprint readback and
    another clock/fence check precede the COMMIT request. Physical COMMIT latency
    or scheduling may cross expiry; no hard real-time expiry-free commit is proved.

    Replay requires the same live authority, available target, semantic request
    digest and exact recorded whole-edge postgraph. Unrelated graph drift may
    therefore HOLD; this is not universal retry idempotence. No native filesystem
    owner authentication, synchronized-clock proof or MCP authority is established. *)
val add_dependency_observed :
  t -> dependency_repair -> observe_now:(unit -> int64) ->
  (dependency_repair_receipt, string) result

(** Historical read only; absent optional audit namespace returns None. Exact
    existing schema/trigger definitions are required; no DDL or effect authority. *)
val lookup_dependency_repair :
  t -> operation_id:string -> (dependency_repair_receipt option, string) result
