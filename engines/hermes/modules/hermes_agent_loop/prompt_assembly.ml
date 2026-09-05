let developer_role_models = [ "gpt-5"; "codex" ]

let contains s sub =
  let len_s = String.length s in
  let len_sub = String.length sub in
  if len_sub > len_s then false
  else
    let found = ref false in
    for i = 0 to len_s - len_sub do
      if String.sub s i len_sub = sub then found := true
    done;
    !found

let model_uses_developer_role model_id =
  let normalized = String.lowercase_ascii model_id in
  List.exists (fun marker -> contains normalized marker) developer_role_models

let apply_developer_role ~model_id messages =
  if not (model_uses_developer_role model_id) then messages
  else
    match messages with
    | (`Assoc fields as _first) :: rest -> (
        match List.assoc_opt "role" fields with
        | Some (`String "system") ->
            let rewritten =
              `Assoc
                (List.map
                   (fun (key, value) ->
                     if key = "role" then (key, `String "developer") else (key, value))
                   fields)
            in
            rewritten :: rest
        | _ -> messages)
    | _ -> messages

let assemble ~model_id ~messages =
  let sanitized = Message_hygiene.sanitize_messages ~model_id messages in
  let formatted = apply_developer_role ~model_id sanitized in
  `Assoc [ ("messages", `List formatted); ("model", `String model_id) ]
