(** L3 contract candidate: Codex Responses-API message shaping for
    [model_routing.codex_runtime].

    Reference capability: [model_routing.codex_runtime]
    Frozen anchor: [agent/codex_responses_adapter.py]

    Three pure JSON transforms, faithful to the frozen source:
    - [chat_content_to_responses_parts]: chat content -> Responses parts;
      text_type is output_text iff role = "assistant"; strings and text-typed
      dicts become text parts (non-empty only); image-typed dicts become
      input_image parts (dropped when the url is not a non-empty string), with
      an optional stripped detail (dict image_url overrides detail by key
      presence, even to null).
    - [normalize_responses_message_status]: strip+lower, then '-' and ' ' -> '_';
      returns the value iff it is completed/incomplete/in_progress, else default.
    - [summarize_user_message_for_log]: null -> ""; a string is returned
      unchanged; a list joins non-empty text bits with sep, strips the join, and
      prefixes "[N image(s)]" (singular "[1 image]") when image-typed parts are
      present; other scalars via Python str().

    Shared [type] coercion is Python [str(x or "").strip().lower()], ASCII-scoped
    (the corpus keeps tokens ASCII; container/float coercion is out of scope,
    documented). Proven by the captured fixture, not hand-derived expectations. *)

val chat_content_to_responses_parts : content:Yojson.Safe.t -> role:string -> Yojson.Safe.t
val normalize_responses_message_status : Yojson.Safe.t -> default:string -> string
val summarize_user_message_for_log : content:Yojson.Safe.t -> sep:string -> string
