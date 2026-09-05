(** Pure opaque SQLite-location authority.

    A production caller can name only a member of the closed registry and
    receives an opaque reference.  It never receives a pathname, filename,
    SQLite handle, SQL statement, or resolved native location.  Resolution is
    an owner-only operation deferred to the SQLite owner. *)

type registration =
  | Event_store
  | Effect_store
  | Jujutsu_authority_store
  | Dispatch_store
  | Completion_store
  | Completion_history_store

type reference

val all_registered : registration list
val registered : registration -> reference
val registration : reference -> registration option
val reference_digest : reference -> string

val source_digest : string

module For_sqlite_owner : sig
  (** Closed logical identities are the most this boundary reveals.  The
      SQLite owner privately maps them to physical targets; no path, filename,
      SQL, statement, finalizer, or native database handle crosses here. *)
  type fixture_profile =
    | In_memory
    | Temporary_file
    | Fault_open
    | Fault_close
    | Fault_busy_once

  type fixture_identity

  type resolved_identity =
    | Production of registration
    | Test_fixture of fixture_identity

  type resolution_error = Released_test_fixture

  val resolve :
    reference -> (resolved_identity, resolution_error) result
  val fixture_profile : fixture_identity -> fixture_profile
  val fixture_identity_digest : fixture_identity -> string
end

module For_test : sig
  (** The test-support library is the only permitted consumer of this bounded
      lease protocol.  Leases never resolve to or expose a path. *)
  type fixture_tag =
    | In_memory
    | Temporary_file
    | Fault_open
    | Fault_close
    | Fault_busy_once

  type registry
  type lease
  type release_outcome
  type cleanup_outcome
  type error

  val create : maximum_live:int -> (registry, error) result
  val maximum_live : registry -> int
  val active_count : registry -> int
  val acquire : registry -> fixture_tag -> (registry * lease, error) result
  val reference : registry -> lease -> (reference, error) result
  val replay : registry -> lease -> (reference, error) result
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

  type mutation =
    | Drop_registration
    | Duplicate_registration
    | Promote_test_fixture
    | Permit_raw_location
    | Reuse_fixture_identity
    | Permit_released_reference
    | Unbounded_fixture_registry

  val source_digest_with_mutation : mutation -> string
end
