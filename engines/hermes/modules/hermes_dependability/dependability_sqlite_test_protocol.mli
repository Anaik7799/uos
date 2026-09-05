(** Finite test-only SQLite location fixtures.

    This protocol neither resolves a filename nor exposes a raw location.  Its
    library is test-only; production code must use
    [Dependability_sqlite_location.registered]. *)

type fault = Open_failure | Close_failure | Busy_once
type fixture = In_memory | Temporary_file | Fault_injection of fault
type registry
type lease
type release_outcome
type cleanup_outcome
type error

val all : fixture list
val create : maximum_live:int -> (registry, error) result
val maximum_live : registry -> int
val active_count : registry -> int
val acquire : registry -> fixture -> (registry * lease, error) result
val reference :
  registry -> lease -> (Dependability_sqlite_location.reference, error) result
val replay :
  registry -> lease -> (Dependability_sqlite_location.reference, error) result
val release :
  registry -> lease -> (registry * release_outcome, error) result
val cleanup : registry -> (registry * cleanup_outcome, error) result

val lease_digest : lease -> string
val release_replayed : release_outcome -> bool
val release_receipt_digest : release_outcome -> string
val cleanup_replayed : cleanup_outcome -> bool
val cleanup_released_count : cleanup_outcome -> int
val cleanup_receipt_digest : cleanup_outcome -> string
val string_of_error : error -> string
