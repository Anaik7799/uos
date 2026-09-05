(* OpenAI -> Bedrock Converse request shaping: candidate for
   model_routing.cloud_vendor_adapters, faithful to frozen agent/bedrock_adapter.py
   (+ _forbids_sampling_params from anthropic_adapter.py). Yojson Assoc preserves
   insertion order, matching Python dicts. *)

let low = String.lowercase_ascii

let contains_sub hay needle =
  let hl = String.length hay and nl = String.length needle in
  if nl = 0 then true
  else
    let rec loop i = i + nl <= hl && (String.sub hay i nl = needle || loop (i + 1)) in
    loop 0

let any_sub model subs = let l = low model in List.exists (fun s -> contains_sub l s) subs

let starts_with ~prefix s =
  String.length s >= String.length prefix && String.sub s 0 (String.length prefix) = prefix

(* -------------------------------------------- Python json.dumps (defaults) *)
(* Keys in input order; comma-space between items and colon-space between key and
   value; lowercase true/false/null. ASCII corpus: escape quote, backslash and
   control chars. *)
let py_str_lit s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\t' -> Buffer.add_string b "\\t"
      | '\r' -> Buffer.add_string b "\\r"
      | c when Char.code c < 0x20 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

let rec python_json (v : Yojson.Safe.t) : string =
  match v with
  | `Null -> "null"
  | `Bool b -> if b then "true" else "false"
  | `Int n -> string_of_int n
  | `Intlit s -> s
  | `Float f -> Printf.sprintf "%g" f (* corpus avoids embedded floats *)
  | `String s -> py_str_lit s
  | `List xs -> "[" ^ String.concat ", " (List.map python_json xs) ^ "]"
  | `Assoc kvs ->
      "{" ^ String.concat ", " (List.map (fun (k, v) -> py_str_lit k ^ ": " ^ python_json v) kvs)
      ^ "}"

(* --------------------------------------------------- model-family predicates *)

let forbids_sampling_params model =
  let l = low model in
  if not (contains_sub l "claude") then false
  else if
    any_sub model
      [ "claude-opus-4-6"; "claude-opus-4.6"; "claude-sonnet-4-6"; "claude-sonnet-4.6" ]
  then false
  else
    let legacy =
      [ "claude-3"; "claude-opus-4-0"; "claude-opus-4.0"; "claude-opus-4-1"; "claude-opus-4.1";
        "claude-sonnet-4-0"; "claude-sonnet-4.0"; "claude-opus-4-2025"; "claude-sonnet-4-2025";
        "claude-opus-4-5"; "claude-opus-4.5"; "claude-sonnet-4-5"; "claude-sonnet-4.5";
        "claude-haiku-4-5"; "claude-haiku-4.5" ]
    in
    not (any_sub model legacy)

let cache_enabled model = any_sub model [ "anthropic.claude"; "amazon.nova" ]
let tool_use_supported model =
  not (any_sub model [ "deepseek.r1"; "deepseek-r1"; "stability."; "cohere.embed"; "amazon.titan-embed" ])

let is_anthropic_bedrock_model model_id =
  let l = low model_id in
  let prefixes =
    [ "global."; "us."; "eu."; "apac."; "ap."; "au."; "jp."; "ca."; "sa."; "me."; "af." ]
  in
  let stripped =
    let rec strip = function
      | [] -> l
      | p :: rest -> if starts_with ~prefix:p l then String.sub l (String.length p) (String.length l - String.length p) else strip rest
    in
    strip prefixes
  in
  starts_with ~prefix:"anthropic.claude" stripped

(* --------------------------------------------------------------- content *)

let safe_text x =
  let s =
    match x with
    | `Null -> None
    | `String s -> Some s
    | `Int n -> Some (string_of_int n)
    | `Bool b -> Some (if b then "True" else "False")
    | `Float f -> Some (Printf.sprintf "%g" f)
    | other -> Some (python_json other) (* str(dict/list) is Python repr; corpus avoids *)
  in
  match s with None -> "(empty)" | Some str -> if String.trim str = "" then "(empty)" else str

let text_block t : Yojson.Safe.t = `Assoc [ ("text", `String t) ]

let convert_content_to_converse content =
  let blocks =
    match content with
    | `Null -> [ text_block "(empty)" ]
    | `String _ -> [ text_block (safe_text content) ]
    | `List parts ->
        List.filter_map
          (fun part ->
            match part with
            | `String _ -> Some (text_block (safe_text part))
            | `Assoc kv -> (
                let ptype = match List.assoc_opt "type" kv with Some (`String t) -> t | _ -> "" in
                if ptype = "text" then
                  Some (text_block (safe_text (match List.assoc_opt "text" kv with Some v -> v | None -> `String "")))
                else if ptype = "image_url" then
                  let url =
                    match List.assoc_opt "image_url" kv with
                    | Some (`Assoc iu) -> (match List.assoc_opt "url" iu with Some (`String u) -> u | _ -> "")
                    | _ -> ""
                  in
                  if starts_with ~prefix:"data:" url then None (* raw bytes: excluded from corpus *)
                  else Some (text_block ("[Image: " ^ url ^ "]"))
                else None)
            | _ -> None)
          parts
    | _ -> [ text_block (safe_text content) ]
  in
  match blocks with [] -> [ text_block "(empty)" ] | _ -> blocks

(* ----------------------------------------------------------------- tools *)

let convert_tools_to_converse tools =
  List.filter_map
    (fun t ->
      match t with
      | `Assoc _ ->
          let fn = match t with `Assoc kv -> (match List.assoc_opt "function" kv with Some (`Assoc f) -> f | _ -> []) | _ -> [] in
          let get k default = match List.assoc_opt k fn with Some v -> v | None -> default in
          Some
            (`Assoc
              [ ( "toolSpec",
                  `Assoc
                    [ ("name", get "name" (`String ""));
                      ("description", get "description" (`String ""));
                      ( "inputSchema",
                        `Assoc
                          [ ( "json",
                              get "parameters"
                                (`Assoc [ ("type", `String "object"); ("properties", `Assoc []) ]) ) ] ) ] ) ])
      | _ -> None)
    tools

(* -------------------------------------------------------------- messages *)

let cache_point : Yojson.Safe.t = `Assoc [ ("cachePoint", `Assoc [ ("type", `String "default") ]) ]

let convert_messages_to_converse messages =
  let system = ref [] (* reversed *) in
  let msgs = ref [] (* reversed: head is the most recent message; each is (role, blocks) *) in
  let system_add block = system := block :: !system in
  let push role blocks = msgs := (role, blocks) :: !msgs in
  let merge_or_push role blocks =
    match !msgs with
    | (lrole, lblocks) :: rest when lrole = role -> msgs := (lrole, lblocks @ blocks) :: rest
    | _ -> push role blocks
  in
  List.iter
    (fun msg ->
      match msg with
      | `Assoc kv -> (
          let role = match List.assoc_opt "role" kv with Some (`String r) -> r | _ -> "" in
          let content = match List.assoc_opt "content" kv with Some c -> c | None -> `Null in
          match role with
          | "system" -> (
              match content with
              | `String s when String.trim s <> "" -> system_add (text_block s)
              | `List parts ->
                  List.iter
                    (fun part ->
                      match part with
                      | `Assoc pkv when List.assoc_opt "type" pkv = Some (`String "text") -> (
                          match List.assoc_opt "text" pkv with
                          | Some (`String t) when String.trim t <> "" -> system_add (text_block t)
                          | _ -> ())
                      | `String s when String.trim s <> "" -> system_add (text_block s)
                      | _ -> ())
                    parts
              | _ -> ())
          | "tool" ->
              let id = match List.assoc_opt "tool_call_id" kv with Some (`String i) -> i | _ -> "" in
              let result =
                match content with `String s -> s | other -> python_json other
              in
              let block =
                `Assoc
                  [ ( "toolResult",
                      `Assoc
                        [ ("toolUseId", `String id);
                          ("content", `List [ text_block (safe_text (`String result)) ]) ] ) ]
              in
              (match !msgs with
              | ("user", lblocks) :: rest -> msgs := ("user", lblocks @ [ block ]) :: rest
              | _ -> push "user" [ block ])
          | "assistant" ->
              let base =
                match content with
                | `String s when String.trim s <> "" -> [ text_block s ]
                | `List _ -> convert_content_to_converse content
                | _ -> []
              in
              let tool_calls =
                match List.assoc_opt "tool_calls" kv with Some (`List tcs) -> tcs | _ -> []
              in
              let tool_blocks =
                List.filter_map
                  (fun tc ->
                    match tc with
                    | `Assoc tckv ->
                        let fn = match List.assoc_opt "function" tckv with Some (`Assoc f) -> f | _ -> [] in
                        let args = match List.assoc_opt "arguments" fn with Some v -> v | None -> `String "{}" in
                        let input =
                          match args with
                          | `String s -> (try Yojson.Safe.from_string s with _ -> `Assoc [])
                          | other -> other
                        in
                        let id = match List.assoc_opt "id" tckv with Some (`String i) -> i | _ -> "" in
                        let name = match List.assoc_opt "name" fn with Some (`String n) -> n | _ -> "" in
                        Some
                          (`Assoc
                            [ ( "toolUse",
                                `Assoc
                                  [ ("toolUseId", `String id); ("name", `String name);
                                    ("input", input) ] ) ])
                    | _ -> None)
                  tool_calls
              in
              let blocks = base @ tool_blocks in
              let blocks = if blocks = [] then [ text_block "(empty)" ] else blocks in
              merge_or_push "assistant" blocks
          | "user" -> merge_or_push "user" (convert_content_to_converse content)
          | _ -> () (* unknown role dropped *))
      | _ -> ())
    messages;
  let ordered = List.rev !msgs in
  (* leading/trailing placeholder fixes, only on a non-empty list *)
  let ordered =
    match ordered with
    | [] -> []
    | (first_role, _) :: _ ->
        let with_lead =
          if first_role <> "user" then ("user", [ text_block "(empty)" ]) :: ordered else ordered
        in
        let last_role = fst (List.nth with_lead (List.length with_lead - 1)) in
        if last_role <> "user" then with_lead @ [ ("user", [ text_block "(empty)" ]) ] else with_lead
  in
  let to_json (role, blocks) = `Assoc [ ("role", `String role); ("content", `List blocks) ] in
  let system_json = match List.rev !system with [] -> None | s -> Some s in
  (system_json, List.map to_json ordered)

(* ------------------------------------------------------------- assembly *)

(* append a cachePoint into the content list of the JSON message at [index]. *)
let append_cache_point_to msgs index =
  List.mapi
    (fun i m ->
      if i <> index then m
      else
        match m with
        | `Assoc kv ->
            `Assoc
              (List.map
                 (fun (k, v) ->
                   if k = "content" then
                     match v with `List blocks -> (k, `List (blocks @ [ cache_point ])) | _ -> (k, v)
                   else (k, v))
                 kv)
        | other -> other)
    msgs

let build_converse_kwargs ~model ~messages ?(tools = []) ?(max_tokens = 4096) ?temperature ?top_p
    ?stop_sequences ?guardrail_config () =
  let system_blocks, msgs = convert_messages_to_converse messages in
  let cache = cache_enabled model in
  let msgs = ref msgs in
  (* inferenceConfig *)
  let inference = ref [ ("maxTokens", `Int max_tokens) ] in
  if not (forbids_sampling_params model) then begin
    (match temperature with Some t -> inference := !inference @ [ ("temperature", `Float t) ] | None -> ());
    (match top_p with Some p -> inference := !inference @ [ ("topP", `Float p) ] | None -> ())
  end;
  (match stop_sequences with
  | Some (_ :: _ as ss) -> inference := !inference @ [ ("stopSequences", `List (List.map (fun s -> `String s) ss)) ]
  | _ -> ());
  let kwargs = ref [ ("modelId", `String model); ("messages", `List !msgs); ("inferenceConfig", `Assoc !inference) ] in
  (* system *)
  (match system_blocks with
  | Some blocks ->
      let blocks = if cache then blocks @ [ cache_point ] else blocks in
      kwargs := !kwargs @ [ ("system", `List blocks) ]
  | None -> ());
  (* tools *)
  (match tools with
  | [] -> ()
  | _ ->
      let ct = convert_tools_to_converse tools in
      if ct <> [] && tool_use_supported model then begin
        let ct = if cache then ct @ [ cache_point ] else ct in
        kwargs := !kwargs @ [ ("toolConfig", `Assoc [ ("tools", `List ct) ]) ]
      end);
  (* message cachePoint on msgs[-2] *)
  (if cache && List.length !msgs >= 2 then begin
     let msgs_json = append_cache_point_to !msgs (List.length !msgs - 2) in
     kwargs :=
       List.map (fun (k, v) -> if k = "messages" then (k, `List msgs_json) else (k, v)) !kwargs
   end);
  (* guardrail *)
  (match guardrail_config with
  | Some g when g <> `Null -> kwargs := !kwargs @ [ ("guardrailConfig", g) ]
  | _ -> ());
  `Assoc !kwargs
