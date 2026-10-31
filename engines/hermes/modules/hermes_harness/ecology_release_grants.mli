(** Factual release-grant event ledger, NOT signature verification, a bearer
    permit, ReleaseAuthority, Sa-plan, or physical-dispatch atomicity. One owner
    per handle; trusted local DB locator, cooperative frozen filesystem and an
    external bounded guardian/cgroup are required. No caller clock on the wire.
    All replies keep authority=NONE, authorized/admitted/new_effect_permission=false. *)
type error = Invalid_json | Invalid_request | Invalid_path | Schema_mismatch
  | Nested_transaction | Store_unavailable | Resource_bound | Conflict
  | Missing_grant | Revoked | Expired | Invalid_clock | Clock_rollback
  | Commit_unknown | Rollback_failed | Closed
val error_code : error -> string
type limits = { max_grants:int; max_events:int; max_db_bytes:int }
val default_limits : limits
val max_request_bytes : int
val max_response_bytes : int
type request
type t
val decode_request : string -> (request,error) result
val request_json : request -> Yojson.Safe.t
val request_digest : request -> string option
val open_store : ?limits:limits -> path:string -> unit -> (t,error) result
val close : t -> (unit,error) result
val execute : t -> request -> (Yojson.Safe.t,error) result
val hold_json : error -> Yojson.Safe.t
(* UNIQUE intent_digest prevents reissue with a different grant ID after revoke.
    Exact request replay is historical. Already_consumed never means a new permit.
    Fresh consumes are checked under BEGIN IMMEDIATE, with native host UTC sampled
    just before insert and before COMMIT request. Physical commit can cross expiry;
    the Gleam owner must revalidate before dispatch and serialize revoke/dispatch.
    Unknown ACKs require lookup, not automatic mutation retry. Forward appends
    reserve one revoke row and256KiB per unrevoked grant plus256KiB current-write
    allowance at page_size<=4096, checked before write and COMMIT request.
    This is a conservative finite headroom policy, not universal SQLite growth,
    disk-full, hostile-writer or physical power-loss recovery assurance. *)
module For_test : sig
  type stage = After_insert | Before_commit | Commit_error | After_commit
  val open_with_clock : ?limits:limits -> path:string -> now_ms:(unit->int64) -> unit -> (t,error) result
  val on_stage : t -> (stage->unit) -> unit
end
