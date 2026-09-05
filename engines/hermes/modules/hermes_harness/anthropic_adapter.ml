(* Anthropic tool/model shaping: candidate for model_routing.anthropic_adapter,
   faithful to frozen agent/anthropic_adapter.py + tools/schema_sanitizer.py.
   Yojson Assoc is an ordered assoc list, matching Python dict insertion order. *)

let starts_with_ci ~prefix s =
  String.starts_with ~prefix (String.lowercase_ascii s)

let is_bedrock_model_id m =
  let l = String.lowercase_ascii m in
  List.exists (fun p -> String.starts_with ~prefix:p l)
    [ "global."; "us."; "eu."; "apac."; "ap."; "au."; "jp."; "ca."; "sa."; "me."; "af.";
      "anthropic." ]

let normalize_model_name model =
  let model =
    if starts_with_ci ~prefix:"anthropic/" model then
      String.sub model 10 (String.length model - 10) (* drop "anthropic/" (10) *)
    else model
  in
  (* preserve_dots = false *)
  if is_bedrock_model_id model then model
  else if starts_with_ci ~prefix:"claude-" model || starts_with_ci ~prefix:"anthropic/" model then
    String.map (fun c -> if c = '.' then '-' else c) model
  else model

(* ASCII-scoped: Python replaces per Unicode codepoint; multibyte input is
   outside the corpus (documented in the .mli). *)
let sanitize_tool_id tool_id =
  if tool_id = "" then "tool_0"
  else
    String.map
      (fun c ->
        match c with
        | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '-' -> c
        | _ -> '_')
      tool_id

(* ------------------------------------------------------- schema_sanitizer *)

let is_null_variant = function
  | `Assoc kv -> List.assoc_opt "type" kv = Some (`String "null")
  | _ -> false

let rec strip_nullable_unions (x : Yojson.Safe.t) : Yojson.Safe.t =
  match x with
  | `List items -> `List (List.map strip_nullable_unions items)
  | `Assoc kvs ->
      (* children stripped first, in insertion order *)
      let stripped = List.map (fun (k, v) -> (k, strip_nullable_unions v)) kvs in
      collapse stripped [ "anyOf"; "oneOf" ]
  | other -> other

and collapse stripped keys =
  match keys with
  | [] -> `Assoc stripped
  | key :: rest -> (
      match List.assoc_opt key stripped with
      | Some (`List variants) ->
          let non_null = List.filter (fun v -> not (is_null_variant v)) variants in
          if List.length non_null = 1 && List.length non_null <> List.length variants then begin
            let survivor = match non_null with [ s ] -> s | _ -> `Assoc [] in
            let replacement = match survivor with `Assoc kv -> kv | _ -> [] in
            (* keep_nullable_hint = false: no "nullable" added. Carry the four
               metadata keys from the outer node when absent from the survivor. *)
            let replacement =
              List.fold_left
                (fun acc meta_key ->
                  if List.mem_assoc meta_key stripped && not (List.mem_assoc meta_key acc) then
                    if meta_key = "default" && List.mem_assoc "$ref" acc then acc
                    else acc @ [ (meta_key, List.assoc meta_key stripped) ]
                  else acc)
                replacement
                [ "title"; "description"; "default"; "examples" ]
            in
            strip_nullable_unions (`Assoc replacement)
          end
          else collapse stripped rest
      | _ -> collapse stripped rest)

let default_object = `Assoc [ ("type", `String "object"); ("properties", `Assoc []) ]

let normalize_tool_input_schema schema =
  let falsy =
    match schema with
    | `Null | `Assoc [] | `List [] | `String "" | `Int 0 | `Bool false -> true
    | _ -> false
  in
  if falsy then default_object
  else
    match strip_nullable_unions schema with
    | `Assoc kvs ->
        (* top-level banned keys stripped; type appended if the remainder lacks it *)
        let banned = [ "oneOf"; "allOf"; "anyOf" ] in
        let kvs =
          if List.exists (fun (k, _) -> List.mem k banned) kvs then
            let kept = List.filter (fun (k, _) -> not (List.mem k banned)) kvs in
            if List.mem_assoc "type" kept then kept else kept @ [ ("type", `String "object") ]
          else kvs
        in
        (* type:object with non-dict properties -> properties repaired to {} *)
        let kvs =
          let props_is_dict =
            match List.assoc_opt "properties" kvs with Some (`Assoc _) -> true | _ -> false
          in
          if List.assoc_opt "type" kvs = Some (`String "object") && not props_is_dict then
            if List.mem_assoc "properties" kvs then
              List.map (fun (k, v) -> if k = "properties" then (k, `Assoc []) else (k, v)) kvs
            else kvs @ [ ("properties", `Assoc []) ]
          else kvs
        in
        `Assoc kvs
    | _ -> default_object

let convert_tools_to_anthropic tools =
  match tools with
  | `Null | `List [] -> `List []
  | `List entries ->
      let seen = Hashtbl.create 16 in
      let out =
        List.filter_map
          (fun entry ->
            match entry with
            | `Assoc fields ->
                let fn = match List.assoc_opt "function" fields with Some (`Assoc f) -> f | _ -> [] in
                let name = match List.assoc_opt "name" fn with Some (`String n) -> n | _ -> "" in
                if name <> "" && Hashtbl.mem seen name then None
                else begin
                  if name <> "" then Hashtbl.add seen name ();
                  let description =
                    match List.assoc_opt "description" fn with Some d -> d | None -> `String ""
                  in
                  let parameters =
                    match List.assoc_opt "parameters" fn with Some p -> p | None -> default_object
                  in
                  let base =
                    [ ("name", `String name); ("description", description);
                      ("input_schema", normalize_tool_input_schema parameters) ]
                  in
                  let cache_control =
                    match List.assoc_opt "cache_control" fields with
                    | Some (`Assoc cc) -> [ ("cache_control", `Assoc cc) ]
                    | _ -> []
                  in
                  Some (`Assoc (base @ cache_control))
                end
            | _ -> None)
          entries
      in
      `List out
  | _ -> `List []
