(** L3 contract: Context engine for managing context references and tool context injection.

    Reference capability: [agent_loop.context_engine]
    Frozen anchor: [agent_loop.context_engine.70b2efe95be5.json]
*)

type context_reference = {
  ref_id : string;
  kind : string;
  uri : string;
  content : string;
  token_count : int;
}

type context_state = {
  active_references : context_reference list;
  total_tokens : int;
  max_context_tokens : int;
}

(*@ predicate valid_context_state (st: context_state) =
      st.total_tokens >= 0 && st.max_context_tokens >= 0 *)

val create : max_context_tokens:int -> context_state
(*@ st = create ~max_context_tokens
    pure
    ensures valid_context_state st
    ensures st.total_tokens = 0
    ensures st.active_references = []
    ensures max_context_tokens < 0 -> st.max_context_tokens = 0
    ensures max_context_tokens >= 0 -> st.max_context_tokens = max_context_tokens *)

val add_reference : context_state -> context_reference -> context_state
(*@ st' = add_reference st ref_item
    pure
    requires valid_context_state st
    ensures valid_context_state st'
    ensures st'.max_context_tokens = st.max_context_tokens
    ensures st'.total_tokens >= 0 *)

val remove_reference : context_state -> ref_id:string -> context_state
(*@ st' = remove_reference st ~ref_id
    pure
    requires valid_context_state st
    ensures valid_context_state st'
    ensures st'.max_context_tokens = st.max_context_tokens
    ensures st'.total_tokens >= 0 *)

val process : model_id:string -> messages:Yojson.Safe.t list -> Yojson.Safe.t
(*@ res = process ~model_id ~messages
    pure *)
