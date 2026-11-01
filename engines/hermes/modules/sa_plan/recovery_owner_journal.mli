(* Bounded factual recovery-owner journal. No task tables, signing, grants,
    production initializer, automatic migration or effect authorization. The
    local locator and process lifecycle must be owned by an admitted launcher;
    caller strings/metadata alone establish no such trust. *)
(** Pure schema specification; tests initialize EMPTY PRIVATE databases only. *)
val schema_statements : string list

(** One strict bounded canonical request. Existing exact schema and WAL/FULL
    durability required for append. A missing/ambiguous COMMIT is UNKNOWN,
    requiring lookup; no automatic retry/rotation or task effects. *)
val handle : database:string -> string -> string
