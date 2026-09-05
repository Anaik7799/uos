(** L3 contract: Message hygiene and sanitization.

    Reference capability: [agent_loop.message_hygiene]
    Frozen anchor: [agent_loop.message_hygiene.70b2efe95be5.json]
*)

val model_consumes_thought_signature : string -> bool
(*@ keep = model_consumes_thought_signature name
    pure *)

val replace_surrogate_utf8 : string -> string
(*@ clean = replace_surrogate_utf8 text
    pure *)

(*@ axiom replace_surrogate_utf8_idempotent:
      forall text: string.
        replace_surrogate_utf8 (replace_surrogate_utf8 text)
        = replace_surrogate_utf8 text *)

val sanitize_value : Yojson.Safe.t -> Yojson.Safe.t
(*@ clean = sanitize_value value
    pure *)

(*@ axiom sanitize_value_idempotent:
      forall value: Yojson.Safe.t.
        sanitize_value (sanitize_value value) = sanitize_value value *)

val sanitize_tool_call : keep_thought_signature:bool -> Yojson.Safe.t -> Yojson.Safe.t
(*@ clean = sanitize_tool_call ~keep_thought_signature value
    pure *)

val sanitize_message : model_id:string -> Yojson.Safe.t -> Yojson.Safe.t
(*@ clean = sanitize_message ~model_id value
    pure *)

val sanitize_messages : model_id:string -> Yojson.Safe.t list -> Yojson.Safe.t list
(*@ clean = sanitize_messages ~model_id messages
    pure *)

val process : model_id:string -> messages:Yojson.Safe.t list -> Yojson.Safe.t
(*@ res = process ~model_id ~messages
    pure *)
