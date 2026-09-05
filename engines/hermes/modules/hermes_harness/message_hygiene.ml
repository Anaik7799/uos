(** Idempotent OpenAI-format message sanitization before a transport boundary. *)

let has_prefix prefix value =
  let length = String.length prefix in
  String.length value >= length && String.sub value 0 length = prefix

let model_consumes_thought_signature model =
  let normalized = String.lowercase_ascii model in
  let rec contains_from fragment start =
    let fragment_length = String.length fragment in
    start + fragment_length <= String.length normalized
    && (String.sub normalized start fragment_length = fragment
        || contains_from fragment (start + 1))
  in
  contains_from "gemini" 0 || contains_from "gemma" 0

let replace_surrogate_utf8 text =
  let length = String.length text in
  let buffer = Buffer.create length in
  let rec loop index =
    if index >= length then Buffer.contents buffer
    else
      let first = Char.code text.[index] in
      if index + 2 < length && first = 0xed
         && let second = Char.code text.[index + 1] in second >= 0xa0 && second <= 0xbf
         && let third = Char.code text.[index + 2] in third >= 0x80 && third <= 0xbf
      then (
        Buffer.add_string buffer "\239\191\189";
        loop (index + 3))
      else (
        Buffer.add_char buffer text.[index];
        loop (index + 1))
  in
  loop 0

let rec sanitize_value (value : Yojson.Safe.t) : Yojson.Safe.t =
  match value with
  | `String text -> `String (replace_surrogate_utf8 text)
  | `Assoc fields -> `Assoc (List.map (fun (key, value) -> (key, sanitize_value value)) fields)
  | `List values -> `List (List.map sanitize_value values)
  | (`Null | `Bool _ | `Int _ | `Intlit _ | `Float _) as value -> value

let sanitize_tool_call ~keep_thought_signature = function
  | `Assoc fields ->
      fields
      |> List.filter (fun (key, _) -> key <> "call_id" && key <> "response_item_id"
                                      && (keep_thought_signature || key <> "extra_content"))
      |> List.map (fun (key, value) -> (key, sanitize_value value))
      |> fun fields -> `Assoc fields
  | value -> sanitize_value value

let sanitize_message ~model_id = function
  | `Assoc fields ->
      let keep_thought_signature = model_consumes_thought_signature model_id in
      fields
      |> List.filter (fun (key, _) ->
             not (has_prefix "_" key)
             && key <> "tool_name"
             && key <> "codex_reasoning_items"
             && key <> "codex_message_items")
      |> List.map (fun (key, value) ->
             if key = "tool_calls" then
               match value with
               | `List calls ->
                   (key, `List (List.map (sanitize_tool_call ~keep_thought_signature) calls))
               | _ -> (key, sanitize_value value)
             else (key, sanitize_value value))
      |> fun fields -> `Assoc fields
  | value -> sanitize_value value

let sanitize_messages ~model_id messages = List.map (sanitize_message ~model_id) messages
