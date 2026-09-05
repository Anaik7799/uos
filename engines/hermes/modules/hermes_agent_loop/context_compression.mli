(** L3 contract: Conversation context compression and prompt caching strategy.

    Reference capability: [agent_loop.context_compression]
    Frozen anchor: [agent_loop.context_compression.70b2efe95be5.json]
*)

type compression_strategy =
  | Truncate_oldest of { keep_last_n : int }
  | Summarize_history of { summary_prefix : string }
  | Cache_ephemeral_prompts

type compression_result = {
  compressed_messages : Yojson.Safe.t list;
  original_count : int;
  compressed_count : int;
  tokens_saved : int;
}

val is_system_msg : Yojson.Safe.t -> bool
(*@ b = is_system_msg msg
    pure *)

val compress_history : strategy:compression_strategy -> Yojson.Safe.t list -> compression_result
(*@ res = compress_history ~strategy messages
    pure
    ensures res.original_count = List.length messages
    ensures res.compressed_count <= res.original_count
    ensures res.tokens_saved >= 0 *)

val compress : model_id:string -> messages:Yojson.Safe.t list -> Yojson.Safe.t
(*@ res = compress ~model_id ~messages
    pure *)
