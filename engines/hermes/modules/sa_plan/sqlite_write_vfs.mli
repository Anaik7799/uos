(** Development-only writable descriptor-bound SQLite session. No production
    Store mutator, general SQL callback, authority/grant or signer is exported.
    Expected resource identities are DATA. Existing main/WAL/SHM must be private
    distinct regular files; all three descriptors are read-write. The private
    compiled fixture adapter may borrow the SAME public OCaml SQLite handle.
    Fresh exclusive native process, sole owner thread, no other SQLite handle,
    no same-inode closes/global-hook edits/live fork are required premises.
    Main/WAL never shrink. Pinned Unix SHM may reset to exactly 3 bytes once,
    during construction under observed exclusive DMS, before mapping/payload
    writes. Zero append growth requires active xShmMap extent, DMS plus WAL
    write lock and exact byte/EOF/range/count guards. Partial SHM is UNREADY
    until exclusive rebuild and full mapping. No new inode/incarnation.
    Bounded files, persistent WAL, FULL sync, no automatic/close
    checkpoint. fsync success/process-crash tests do NOT prove power-loss safety.
    Critical setting PRAGMAs are refused after readiness; only explicit PASSIVE
    checkpoint is allowed by the fixed SQL guard. Hostile native callbacks or
    replacement of that guard remain outside the trusted private-callee model.
    Any unknown cleanup/commit requires worker exit and fresh reconciliation. *)
type identity={device:int64;inode:int64}
type resources={main:identity;wal:identity;shm:identity}
type error=Refused|Unsupported|Ownership|Closed|Poisoned|Io|Runtime|Invalid_input
             |Unknown_outcome
type session
type observation
val open_existing : directory:string -> basename:string -> expected:resources ->
  (session,error)result
val snapshot : session -> (observation,error)result
val diagnostics : observation -> Yojson.Safe.t
val identities : observation -> resources
val close : session -> (unit,error)result
val process_poisoned : unit -> bool
val error_label : error -> string
