(** No-effect main-file mapping observation, not FD identity, all-SQLite IO,
    WAL/SHM binding, future reopen or task/effect authority. Linux x86_64 only.
    Module owns an opaque READONLY FULLMUTEX/private-cache connection and its
    SQL-function registry; there is no raw DB/SQL/function replacement API.
    Caller retains its independent regular FD for the observation call.
    Default Unix VFS/proc/immutable pinned runtime and
    cooperative local FS assumptions remain. No supplied path/proc fallback. *)
(* No-effect means no task or SQL mutation API: SQLite READONLY may still
   interact with WAL/SHM locking/metadata. Not filesystem-readonly evidence.
   Native retained-FD fstat supplies signed64 identity without tagged-int
   projection; larger unsigned device/inode values refuse before comparison. *)
type error = Unsupported_runtime | Registration_failed | Retained_changed
  | Mapping_unavailable | Identity_mismatch | Unsupported_connection | Query_refused
  | Closed_connection | Ownership_mismatch | Close_failed
type runtime = { version:string; source_id:string; dso_path:string }
type observation
type connection
val register : unit -> (runtime,error) result
val open_readonly : ?mmap:bool -> string -> (connection,error) result
(* Fixed bounded mmap setting, BEGIN/read-schema only. mmap=false can only
    produce a later HOLD. No caller SQL or VFS/mutex override is accepted. *)
val observe_main : connection -> retained:Unix.file_descr -> (observation,error) result
(* Operations/close serialized; inherited child-process aliases refuse without
    touching the parent's state. Explicit close is required by the worker.
    Close failure is terminal/unknown, never a retry or effect permission. *)
(* Fork refusal covers explicit API calls only. Child GC/finalizer/SQLite
   sidecar behavior after inheriting a live connection remains unverified;
   worker must not fork a live module-owned connection. *)
val close : connection -> (unit,error) result
val device : observation -> int64
val inode : observation -> int64
val observed_bytes : observation -> int
val error_label : error -> string
