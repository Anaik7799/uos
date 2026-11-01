(* Bounded factual recovery-owner journal. No task tables, signing, grants,
    production initializer, automatic migration or effect authorization. The
    local locator and process lifecycle must be owned by an admitted launcher;
    caller strings/metadata alone establish no such trust. *)
(** Legacy three-object schema specification. Validator also accepts ONLY the
    exact six-object v2 layout with recovery migration receipt table/triggers.
    This module never creates, upgrades or normalizes either layout. *)
val schema_statements : string list

(** One strict bounded canonical request. Existing exact schema and WAL/FULL
    durability required for append. A missing/ambiguous COMMIT is UNKNOWN,
    requiring lookup; no automatic retry/rotation or task effects. *)
val handle : database:string -> string -> string
