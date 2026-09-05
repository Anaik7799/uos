(** L3 contract: Turn finalization and receipt generation.

    Reference capability: [agent_loop.turn_finalization]
    Frozen anchor: [agent_loop.turn_finalization.70b2efe95be5.json]
*)

type turn_receipt = {
  turn_id : string;
  status : string;
  turns_executed : int;
  total_tokens_used : int;
  final_output : string option;
}

type finalizer_summary = {
  receipt : turn_receipt;
  metadata : (string * Yojson.Safe.t) list;
}

(*@ predicate valid_turn_receipt (r: turn_receipt) =
      r.turns_executed >= 0 &&
      r.total_tokens_used >= 0 &&
      r.turn_id <> "" *)

val create_receipt :
  turn_id:string ->
  status:string ->
  turns:int ->
  tokens:int ->
  final_output:string option ->
  turn_receipt
(*@ r = create_receipt ~turn_id ~status ~turns ~tokens ~final_output
    pure
    ensures valid_turn_receipt r
    ensures r.status = status
    ensures r.final_output = final_output
    ensures turn_id = "" -> r.turn_id = "unknown"
    ensures turn_id <> "" -> r.turn_id = turn_id
    ensures turns < 0 -> r.turns_executed = 0
    ensures turns >= 0 -> r.turns_executed = turns
    ensures tokens < 0 -> r.total_tokens_used = 0
    ensures tokens >= 0 -> r.total_tokens_used = tokens *)

val summarize : turn_receipt -> metadata:(string * Yojson.Safe.t) list -> finalizer_summary
(*@ s = summarize r ~metadata
    pure
    ensures s.receipt = r
    ensures s.metadata = metadata *)

val finalize : model_id:string -> messages:Yojson.Safe.t list -> Yojson.Safe.t
(*@ res = finalize ~model_id ~messages
    pure *)

