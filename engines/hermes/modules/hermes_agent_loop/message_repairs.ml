(* The list-level pre-call sanitizer: a faithful OCaml reproduction of the
   frozen agent.agent_runtime_helpers.sanitize_api_messages (read completely
   before this was written; parity is measured differentially by the
   hygiene.list_repairs scenario, never assumed from this comment).

   Six passes, in the frozen order — the order is load-bearing and one
   scenario case pins it (an empty-content assistant whose tool_calls is []
   is HEALED first, then loses the empty array):

     1. role allowlist        drop roles outside the six the API accepts
     2. empty-non-final heal  substitute "[response interrupted]" for a
                              payload-less non-final user/assistant turn
     3. empty tool_calls      drop a tool_calls key that is [] or not a list
     4. empty function.name   rename to the "invalid_tool_call" sentinel,
                              keeping the call/result PAIRED
     5. orphan repair         drop tool results with no surviving call;
                              inject a stub result after the assistant turn
                              for calls whose result vanished
     6. dedup                 first occurrence wins for duplicate call ids,
                              across calls and results alike *)

let valid_api_roles = [ "system"; "user"; "assistant"; "tool"; "function"; "developer" ]
let interrupted_placeholder = "[response interrupted]"
let empty_name_sentinel = "invalid_tool_call"
let stub_result_content = "[Result unavailable — see context summary above]"

let field name = function `Assoc fields -> List.assoc_opt name fields | _ -> None

let string_field name message =
  match field name message with Some (`String value) -> Some value | _ -> None

let role message = Option.value (string_field "role" message) ~default:""

let is_blank text = String.trim text = ""

(* The frozen coalesce_tool_call_id: call_id or id, stripped, "" when neither. *)
let tool_call_id tool_call =
  let get name =
    match field name tool_call with Some (`String value) -> String.trim value | _ -> ""
  in
  match get "call_id" with "" -> get "id" | call_id -> call_id

(* The frozen _get_tool_call_name_static: best-effort, "" elsewhere. *)
let tool_call_name tool_call =
  match field "function" tool_call with
  | Some (`Assoc _ as fn) -> Option.value (string_field "name" fn) ~default:""
  | _ -> ""

let tool_calls_list message =
  match field "tool_calls" message with Some (`List calls) -> calls | _ -> []

(* Python truthiness over a JSON value — the frozen predicate leans on it for
   every structural check, so the reproduction must too. *)
let truthy = function
  | `Null | `Bool false | `String "" | `List [] | `Assoc [] | `Int 0 | `Intlit "0" -> false
  | `Float f -> f <> 0.0
  | _ -> true

(* The frozen _msg_has_payload, clause for clause. *)
let has_payload message =
  let content_payload =
    match field "content" message with
    | Some (`String text) -> not (is_blank text)
    | Some (`List blocks) ->
        List.exists
          (fun block ->
            match block with
            | `Assoc _ -> (
                match string_field "type" block with
                | Some "text" -> (
                    match string_field "text" block with
                    | Some text -> not (is_blank text)
                    | None -> false)
                | _ -> true)
            | other -> truthy other)
          blocks
    | Some `Null | None -> false
    | Some other -> truthy other
  in
  content_payload
  || (match field "tool_calls" message with Some value -> truthy value | None -> false)
  || (match string_field "reasoning_content" message with
     | Some text -> not (is_blank text)
     | None -> false)
  || (match field "reasoning" message with Some value -> truthy value | None -> false)
  || (match field "reasoning_details" message with
     | Some value -> truthy value
     | None -> false)
  || (match field "codex_message_items" message with
     | Some value -> truthy value
     | None -> false)
  || (match field "codex_reasoning_items" message with
     | Some value -> truthy value
     | None -> false)

let set_field name value message =
  match message with
  | `Assoc fields ->
      let replaced = ref false in
      let fields =
        List.map
          (fun (key, existing) ->
            if key = name then (replaced := true; (key, value)) else (key, existing))
          fields
      in
      `Assoc (if !replaced then fields else fields @ [ (name, value) ])
  | other -> other

let drop_field name = function
  | `Assoc fields -> `Assoc (List.filter (fun (key, _) -> key <> name) fields)
  | other -> other

(* Pass 1: role allowlist. *)
let allowlist_roles messages =
  List.filter (fun message -> List.mem (role message) valid_api_roles) messages

(* Pass 2: heal payload-less non-final user/assistant turns. *)
let repair_empty_non_final messages =
  let final_index = List.length messages - 1 in
  if final_index < 1 then messages
  else
    List.mapi
      (fun index message ->
        if
          index <> final_index
          && (match role message with "assistant" | "user" -> true | _ -> false)
          && not (has_payload message)
        then set_field "content" (`String interrupted_placeholder) message
        else message)
      messages

(* Pass 3: drop an empty or non-list tool_calls on an assistant turn. *)
let drop_empty_tool_calls messages =
  List.map
    (fun message ->
      if role message = "assistant" then
        match field "tool_calls" message with
        | Some (`List (_ :: _)) | None -> message
        | Some _ -> drop_field "tool_calls" message
      else message)
    messages

(* Pass 4: rename an empty function.name to the sentinel, preserving pairing. *)
let repair_empty_names messages =
  let repair_call tool_call =
    match tool_call with
    | `Assoc _ -> (
        let named =
          match field "function" tool_call with
          | Some (`Assoc _ as fn) -> (
              match string_field "name" fn with
              | Some name when not (is_blank name) -> None
              | _ -> Some (set_field "function" (set_field "name" (`String empty_name_sentinel) fn) tool_call))
          | Some _ ->
              (* a non-dict function value: the frozen repair has no settable
                 name and no dict to rebuild, so it leaves the call untouched *)
              None
          | None ->
              Some
                (set_field "function"
                   (`Assoc [ ("name", `String empty_name_sentinel); ("arguments", `String "{}") ])
                   tool_call)
        in
        Option.value named ~default:tool_call)
    | other -> other
  in
  List.map
    (fun message ->
      if role message = "assistant" && tool_calls_list message <> [] then
        set_field "tool_calls" (`List (List.map repair_call (tool_calls_list message))) message
      else message)
    messages

(* Pass 5: orphan repair — drop results without calls, stub results for calls
   without results. *)
let repair_orphans messages =
  let surviving_call_ids =
    List.concat_map
      (fun message ->
        if role message = "assistant" then
          List.filter_map
            (fun tool_call ->
              match tool_call_id tool_call with "" -> None | id -> Some id)
            (tool_calls_list message)
        else [])
      messages
  in
  let result_id message =
    if role message = "tool" then
      match string_field "tool_call_id" message with
      | Some id when String.trim id <> "" -> Some (String.trim id)
      | _ -> None
    else None
  in
  let result_call_ids = List.filter_map result_id messages in
  let orphaned =
    List.filter (fun id -> not (List.mem id surviving_call_ids)) result_call_ids
  in
  let messages =
    if orphaned = [] then messages
    else
      List.filter
        (fun message ->
          match result_id message with
          | Some id -> not (List.mem id orphaned)
          | None -> true)
        messages
  in
  let missing =
    List.filter (fun id -> not (List.mem id result_call_ids)) surviving_call_ids
  in
  if missing = [] then messages
  else
    List.concat_map
      (fun message ->
        if role message = "assistant" then
          message
          :: List.filter_map
               (fun tool_call ->
                 let id = tool_call_id tool_call in
                 if id <> "" && List.mem id missing then
                   Some
                     (`Assoc
                       [ ("role", `String "tool");
                         ("name", `String (tool_call_name tool_call));
                         ("content", `String stub_result_content);
                         ("tool_call_id", `String id) ])
                 else None)
               (tool_calls_list message)
        else [ message ])
      messages

(* Pass 6: dedup — first occurrence wins, for calls and results alike. *)
let dedup_call_ids messages =
  let seen_calls = Hashtbl.create 8 and seen_results = Hashtbl.create 8 in
  List.filter_map
    (fun message ->
      match role message with
      | "assistant" when tool_calls_list message <> [] ->
          let kept =
            List.filter
              (fun tool_call ->
                match tool_call_id tool_call with
                | "" -> true
                | id ->
                    if Hashtbl.mem seen_calls id then false
                    else (Hashtbl.add seen_calls id (); true))
              (tool_calls_list message)
          in
          Some
            (if List.length kept <> List.length (tool_calls_list message) then
               set_field "tool_calls" (`List kept) message
             else message)
      | "tool" -> (
          match string_field "tool_call_id" message with
          | Some raw when String.trim raw <> "" ->
              let id = String.trim raw in
              if Hashtbl.mem seen_results id then None
              else (Hashtbl.add seen_results id (); Some message)
          | _ -> Some message)
      | _ -> Some message)
    messages

let sanitize_api_messages messages =
  messages |> allowlist_roles |> repair_empty_non_final |> drop_empty_tool_calls
  |> repair_empty_names |> repair_orphans |> dedup_call_ids
