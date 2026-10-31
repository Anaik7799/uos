(** Storage of sanitized observations only. Stored/Replayed is neither receipt
    authentication nor task, spend, deployment or EV admission authority.
    This owner uses an existing Evidence_store connection, not another task DB.
    Physical paths are reviewed local launcher configuration, never wire input.
    An external bounded OS guardian is required for native-call deadlines.
    One isolated caller owns each handle; handles are not shared across domains. *)
type error = Invalid_json | Invalid_receipt | Invalid_request | Invalid_path
  | Schema_mismatch | Nested_transaction | Store_unavailable | Resource_bound
  | Conflict | Stale_epoch | Out_of_order | Commit_unknown | Rollback_failed | Closed
val error_code : error -> string
type limits = { max_rows : int; max_db_bytes : int; max_payload_bytes : int }
val default_limits : limits
val max_request_bytes : int
val max_response_bytes : int
type receipt
type latest_key
type request
type t
type stored
type append_outcome = Stored of stored | Replayed of stored
val parse_json : string -> (Yojson.Safe.t, error) result
val receipt_of_json : Yojson.Safe.t -> (receipt, error) result
val receipt_json : receipt -> Yojson.Safe.t
val receipt_id : receipt -> string
val payload_sha256 : receipt -> string
val latest_key_of_json : Yojson.Safe.t -> (latest_key, error) result
val decode_request : string -> (request, error) result
val open_store : ?limits:limits -> path:string -> unit -> (t, error) result
val close : t -> (unit, error) result
val append : t -> receipt -> (append_outcome, error) result
val get : t -> receipt_id:string -> (stored option, error) result
val latest : t -> latest_key -> (stored option, error) result
val stored_json : stored -> Yojson.Safe.t
val execute : t -> request -> (Yojson.Safe.t, error) result
val hold_json : error -> Yojson.Safe.t
(* Resource holds preserve existing rows. A post-COMMIT/ACK failure is uncertain;
    reconcile by exact receipt ID, never by repeating a probe or an effect.
    Main-file logical pages and observed DB/WAL/SHM byte bounds are checked;
    hostile concurrent same-UID filesystem writers are outside this boundary. *)
module For_test : sig
  type stage = After_insert | Before_commit | Commit_error | After_commit
  val attach : limits:limits -> Evidence_store.t -> (t, error) result
  val on_stage : t -> (stage -> unit) -> unit
end
