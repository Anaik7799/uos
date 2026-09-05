(** L3 contract: idempotent OpenAI-format message sanitization before a
    transport boundary.

    Reference capability: [agent_loop.message_hygiene]
    Frozen anchors: [agent/message_sanitization.py], [agent/message_content.py]

    The Gospel specifications below are the contract obligation. A checked
    contract still grants no parity credit on its own; that requires L4
    fixtures, L5 normalized traces, and an L6 verifier receipt.

    Three Gospel limits shape what is written here. [model] is a reserved
    keyword, which is why the sanitizing entry points take [~model_id] rather
    than [~model]. A function is not in scope inside its own specification, so
    idempotence is stated as a following axiom rather than as an [ensures].
    Gospel's term language cannot apply a labelled function at all, so the
    labelled entry points carry no idempotence axiom here; that obligation is
    carried by L4 fixtures instead. *)

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
