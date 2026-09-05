(** Read-only planning for immutable evidence-store imports.

    The planner never mutates either database. It compares primary-key identity
    and complete row payloads so a same-key/different-payload replay is exposed
    as a conflict rather than silently accepted. Historical verification
    verdicts remain data; this module never promotes them to current parity. *)

type table_delta = {
  source_rows : int;
  target_rows : int;
  missing_from_target : int;
  target_only : int;
  conflicts : int;
}

type plan = {
  (* Canonical digests of the import-relevant logical content, independent of
     SQLite page layout, WAL state, and filesystem metadata. *)
  source_store_digest : string;
  target_store_digest : string;
  plan_digest : string;
  snapshot_digest : string option;
  source_entry_count : int option;
  source_snapshot_consistent : bool;
  schema_compatible : bool;
  scenarios : table_delta;
  traces : table_delta;
  verifications : table_delta;
  source_passed : int;
  source_failed : int;
}

(** [analyze ~source_path ~target_path] opens both databases read-only and
    returns their immutable-row delta. Missing paths, malformed schemas, and
    SQLite failures return [Error]; they are never treated as empty stores. *)
val analyze : source_path:string -> target_path:string -> (plan, string) result

(** [admissible plan] is true only when the relevant schemas agree, the source
    is snapshot-bound, and no shared primary key carries different content. *)
val admissible : plan -> bool

(** [render plan] emits a deterministic, orientation-first read-only report.
    Its admission verdict covers planning only; it never claims that a merge
    executed or that historical verification grants current parity. *)
val render : plan -> string
