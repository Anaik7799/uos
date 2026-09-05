let has_prefix prefix value =
  let length = String.length prefix in
  String.length value >= length && String.sub value 0 length = prefix

let model_consumes_thought_signature name =
  let lower = String.lowercase_ascii name in
  let contains sub =
    let sub_len = String.length sub in
    let s_len = String.length lower in
    let rec check i =
      if i + sub_len > s_len then false
      else if String.sub lower i sub_len = sub then true
      else check (i + 1)
    in
    check 0
  in
  contains "gemma" || contains "gemini"

let replace_surrogate_utf8 text =
  let len = String.length text in
  let buf = Buffer.create len in
  let rec aux i =
    if i >= len then Buffer.contents buf
    else
      let b1 = Char.code text.[i] in
      if b1 = 0xED && i + 2 < len then
        let b2 = Char.code text.[i + 1] in
        let b3 = Char.code text.[i + 2] in
        if b2 >= 0xA0 && b2 <= 0xBF && b3 >= 0x80 && b3 <= 0xBF then begin
          Buffer.add_string buf "\xEF\xBF\xBD";
          aux (i + 3)
        end else begin
          Buffer.add_char buf text.[i];
          aux (i + 1)
        end
      else begin
        Buffer.add_char buf text.[i];
        aux (i + 1)
      end
  in
  aux 0

let rec sanitize_value (value : Yojson.Safe.t) : Yojson.Safe.t =
  match value with
  | `String text -> `String (replace_surrogate_utf8 text)
  | `Assoc fields -> `Assoc (List.map (fun (key, val_) -> (key, sanitize_value val_)) fields)
  | `List values -> `List (List.map sanitize_value values)
  | (`Null | `Bool _ | `Int _ | `Intlit _ | `Float _) as v -> v

let sanitize_tool_call ~keep_thought_signature = function
  | `Assoc fields ->
      fields
      |> List.filter (fun (key, _) ->
             key <> "call_id"
             && key <> "response_item_id"
             && (keep_thought_signature || (key <> "extra_content" && key <> "thought_signature")))
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
             && key <> "codex_message_items"
             && (keep_thought_signature || key <> "thought_signature"))
      |> List.map (fun (key, value) ->
             if key = "tool_calls" then
               match value with
               | `List calls ->
                   (key, `List (List.map (sanitize_tool_call ~keep_thought_signature) calls))
               | _ -> (key, sanitize_value value)
             else (key, sanitize_value value))
      |> fun fields -> `Assoc fields
  | value -> sanitize_value value

let sanitize_messages ~model_id messages =
  List.map (sanitize_message ~model_id) messages

let process ~model_id ~messages =
  let sanitized = sanitize_messages ~model_id messages in
  (`Assoc [
    ("model_id", `String model_id);
    ("messages", `List sanitized)
  ] : Yojson.Safe.t)
