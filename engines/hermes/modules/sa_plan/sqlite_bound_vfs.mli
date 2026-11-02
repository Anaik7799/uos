(** Experimental dedicated-process READONLY SQLite resource binding.
    All expected identities are DATA, not signatures, trust anchors or grants.
    Exactly one connection lifetime per process; no raw DB/SQL/registry export.
    Linux x86_64/pinned SQLite3.53.3/default Unix VFS only. Existing main/WAL/SHM
    required; main+WAL are readonly, SHM descriptor/mapping is read-write.
    No task/SQL mutation API; filesystem-readonly and no SHM writes NOT claimed.
    Exclusive trusted native process, no other SQLite connections/global VFS
    edits, and NO other closes of any of these inodes are essential premises.
    No live-connection fork or Domain/thread transfer. Not production authority. *)
(* First-owner reservation is atomic before any extension registration.
   Concurrent constructors yield at most one owner; losers perform no SQLite
   registration/open. Failed constructors consume the lifetime; no reset. *)
type identity = { device:int64; inode:int64 }
type resources = { main:identity; wal:identity; shm:identity }
type error = Refused | Unsupported | Ownership | Closed | Poisoned | Io
              | Runtime | Invalid_input
type connection
type observation
val open_readonly : directory:string -> basename:string -> expected:resources ->
  (connection,error) result
val snapshot : connection -> (observation,error) result
val identities : observation -> resources
val diagnostics : observation -> Yojson.Safe.t
val close : connection -> (unit,error) result
val process_poisoned : unit -> bool
val error_label : error -> string
(* Unknown cleanup/hook drift poisons the process permanently; caller must
   terminate its isolated worker. No retry/reset/reopen/effect permission.
   Explicit close required; no GC finalizer attempts unsafe SQLite shutdown. *)
