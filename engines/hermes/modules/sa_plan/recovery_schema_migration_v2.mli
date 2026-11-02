(** Versioned DATA specification for the task resource-binding extension.
    V1 request/schema bytes remain unchanged. No production interpreter,
    locator/identity authentication, migration authority or signer is supplied. *)
type predecessor = Legacy_six | V1_with_receipts
(** [base.before_schema_sha256] binds the COMPLETE predecessor DDL in this
    v2 domain, not v1's core-only DDL. [base.source_sha256] binds v2 source.
    The generic v1 migration receipt table/triggers are reused without altering
    old rows; old v1-only interpreters may refuse the new layout. *)
type request = { base : Recovery_schema_migration.request; predecessor : predecessor }
type error = Recovery_schema_migration.error =
  Authority_unavailable | Refused of string | Commit_unknown
val resource_schema : (string * string) list
val schema : (string * string) list
val receipt_schema : (string * string) list
val predecessor_schema : predecessor -> (string * string) list
val request_bytes : request -> string
val validate : request -> (unit,error) result
val migrate : request -> (Yojson.Basic.t,error) result
