open Core

(** A cooperative session-journal event presented to the Hermes authority.
    [payload_hash] is a claim: [make] recomputes it over the normalized actual
    fields and ingestion rejects a mismatch. *)
type session_observation

(** Journal identity is outside the seven-field observation carrier because it
    defines the ordering namespace. [host_boot_id] is body-bound provenance;
    reboot does not reset the stable journal's local sequence. *)
type source_journal

type observation_accepted = {
  event_id : string;
  payload_hash : string;
  hermes_sequence : int64;
  replayed : bool;
}

type reconciliation_kind =
  | Payload_hash_mismatch
  | Body_conflict
  | Sequence_conflict
  | Sequence_gap
  | Out_of_order

type reconciliation_required = {
  kind : reconciliation_kind;
  event_id : string;
  payload_hash : string;
  expected_sequence : int64 option;
  actual_sequence : int64;
}

type outcome =
  | Observation_accepted of observation_accepted
  | Reconciliation_required of reconciliation_required

(** Smart construction is total. References are non-empty, bounded strings
    without NUL bytes; sequences are positive and epochs non-negative.
    The declared hash must be canonical lowercase SHA-256. *)
val make :
  source_journal_ref:string ->
  host_boot_id:string ->
  event_id:string ->
  payload_hash:string ->
  local_sequence:int64 ->
  session_ref:string ->
  resource_ref:string ->
  epoch:int64 ->
  candidate_ref:string ->
  ((source_journal * session_observation), string) Result.t

(** The canonical hash is SHA-256 over an ordered compact JSON object containing
    the journal identity and every actual observation field except
    [payload_hash]. It is independent of client JSON member order. *)
val computed_payload_hash :
  source_journal -> session_observation -> string

(** Idempotence law: ingesting the same normalized event twice yields the same
    [event_id], [payload_hash], and [hermes_sequence], with [replayed=true] on
    the retry. Conflict and ordering refusals commit only a reconciliation row;
    they never insert an inbox row or mutate workflow authority state. *)
val ingest :
  Sa_plan_store.t ->
  source_journal ->
  session_observation ->
  (outcome, string) Result.t

(** The JSON codec accepts exactly the CLI envelope fields documented by
    [make]. Unknown fields are rejected so they cannot escape hash binding. *)
val of_yojson :
  Yojson.Safe.t ->
  ((source_journal * session_observation), string) Result.t

(** Source-side helper used by the CLI. Its object has the same exact fields as
    [of_yojson] except [payload_hash], which must be absent. *)
val computed_payload_hash_of_yojson :
  Yojson.Safe.t -> (string, string) Result.t

val outcome_to_yojson : outcome -> Yojson.Safe.t
val reconciliation_kind_to_string : reconciliation_kind -> string
