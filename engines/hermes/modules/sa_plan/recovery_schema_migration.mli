(** Development migration specification. Public values are DATA, not trusted
    launcher configuration, keys, clock observations or migration authority.
    The production entry performs no filesystem/SQLite operation and always
    refuses. The effectful interpreter is compiled ONLY into the private test. *)
type target = Task_store | Owner_journal
type request = {
  migration_id : string;
  resource_id : string;
  database : string;
  device : int;
  inode : int;
  target : target;
  source_sha256 : string;
  before_schema_sha256 : string;
  expires_utc_ns : int64;
  expires_mono_ns : int64;
}
type error = Authority_unavailable | Refused of string | Commit_unknown
val schema : target -> (string * string) list
val receipt_schema : target -> (string * string) list
val request_bytes : request -> string
val validate : request -> (unit, error) result
val migrate : request -> (Yojson.Basic.t, error) result
