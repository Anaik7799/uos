(** Pure OpenRouter request shaping.

    This module deliberately has no network, environment, filesystem, or
    persistence dependency.  The caller supplies credential candidates and
    receives a request description that can be inspected before transport. *)

let default_base_url = "https://openrouter.ai/api/v1"
let default_models_url = default_base_url ^ "/models"

type credentials = {
  supplied_key : string option;
  openrouter_key : string option;
  openai_key : string option;
  base_url_override : string option;
}

type resolved_credentials = { base_url : string; api_key : string option }

type reasoning = Unspecified | Disabled | Effort of string

type request = {
  endpoint : string;
  api_key : string option;
  body : Yojson.Safe.t;
}

let nonempty = function
  | Some value when String.trim value <> "" -> Some (String.trim value)
  | Some _ | None -> None

let host_of_url value =
  let without_scheme =
    match String.index_opt value ':' with
    | Some index when index + 2 < String.length value && value.[index + 1] = '/' && value.[index + 2] = '/' ->
        String.sub value (index + 3) (String.length value - index - 3)
    | _ -> value
  in
  let end_index =
    match String.index_opt without_scheme '/' with
    | Some index -> index
    | None -> String.length without_scheme
  in
  let authority = String.sub without_scheme 0 end_index in
  match String.index_opt authority ':' with
  | Some index -> String.lowercase_ascii (String.sub authority 0 index)
  | None -> String.lowercase_ascii authority

let is_openrouter_url url =
  let host = host_of_url url in
  host = "openrouter.ai"
  || (String.length host > String.length ".openrouter.ai"
      && String.ends_with ~suffix:".openrouter.ai" host)

let first_key candidates = List.find_map nonempty candidates

let resolve_credentials credentials =
  let base_url =
    match nonempty credentials.base_url_override with
    | Some value -> value
    | None -> default_base_url
  in
  let api_key =
    if is_openrouter_url base_url then
      first_key [ credentials.supplied_key; credentials.openrouter_key; credentials.openai_key ]
    else first_key [ credentials.supplied_key; credentials.openai_key; credentials.openrouter_key ]
  in
  { base_url; api_key }

let valid_efforts = [ "minimal"; "low"; "medium"; "high"; "xhigh"; "max"; "ultra" ]

let parse_reasoning value =
  match String.lowercase_ascii (String.trim value) with
  | "none" | "false" | "disabled" -> Disabled
  | effort when List.mem effort valid_efforts -> Effort effort
  | _ -> Unspecified

let anthropic_reasoning_optional =
  [ "claude-3"; "claude-opus-4-0"; "claude-opus-4.0"; "claude-opus-4-1";
    "claude-opus-4.1"; "claude-sonnet-4-0"; "claude-sonnet-4.0";
    "claude-opus-4-2025"; "claude-sonnet-4-2025"; "claude-opus-4-5";
    "claude-opus-4.5"; "claude-sonnet-4-5"; "claude-sonnet-4.5";
    "claude-haiku-4-5"; "claude-haiku-4.5" ]

let contains value fragment =
  let value_length = String.length value and fragment_length = String.length fragment in
  let rec loop index =
    index + fragment_length <= value_length
    && (String.sub value index fragment_length = fragment || loop (index + 1))
  in
  fragment_length = 0 || loop 0

let anthropic_reasoning_mandatory model =
  let normalized = String.lowercase_ascii model in
  (String.starts_with ~prefix:"anthropic/" normalized
   || String.starts_with ~prefix:"claude" normalized
   || contains normalized "claude")
  && not (List.exists (contains normalized) anthropic_reasoning_optional)

let assoc_if_nonempty fields = if fields = [] then [] else [ ("extra_body", `Assoc fields) ]

(* Models whose leading system message is rewritten to the developer role.
   Faithful to the frozen reference: agent/prompt_builder.py defines
   DEVELOPER_ROLE_MODELS = ("gpt-5", "codex"), and chat_completions.build_kwargs
   applies the swap to sanitized[0] when its role is "system" and the model name
   contains one of these markers. *)
let developer_role_models = [ "gpt-5"; "codex" ]

let model_uses_developer_role model_id =
  let normalized = String.lowercase_ascii model_id in
  List.exists (fun marker -> contains normalized marker) developer_role_models

(* Rewrite the FIRST message's role from "system" to "developer" when the model
   family requires it. Only the first message, and only when it is a system
   message, exactly as the reference does. *)
let apply_developer_role model_id messages =
  if not (model_uses_developer_role model_id) then messages
  else
    match messages with
    | (`Assoc fields as first) :: rest -> (
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
        | _ -> ignore first; messages)
    | _ -> messages

(* The label is [model_id], not [model]: [model] is a Gospel keyword and a value
   carrying it can never be given a specification. [tools] defaults to the empty
   list so existing callers are unaffected; when non-empty the tools appear in
   the request body, matching the reference. *)
let build ~credentials ~model_id ~messages ?(tools = []) ?max_tokens ~reasoning ~supports_reasoning
    ~session_id ~provider_preferences ~pareto_min_coding_score () =
  let resolved = resolve_credentials credentials in
  let messages = apply_developer_role model_id messages in
  let extra_body = ref [] in
  (match nonempty session_id with Some value -> extra_body := ("session_id", `String value) :: !extra_body | None -> ());
  (match provider_preferences with
  | Some (`Assoc _ as preferences) -> extra_body := ("provider", preferences) :: !extra_body
  | Some _ | None -> ());
  if model_id = "openrouter/pareto-code" then (
    match pareto_min_coding_score with
    | Some score when score >= 0. && score <= 1. ->
        extra_body := ("plugins", `List [ `Assoc [ ("id", `String "pareto-router"); ("min_coding_score", `Float score) ] ]) :: !extra_body
    | Some _ | None -> ());
  let top_level = ref [ ("model", `String model_id); ("messages", `List messages) ] in
  (match max_tokens with Some tokens -> top_level := ("max_tokens", `Int tokens) :: !top_level | None -> ());
  (* Tools appear in the body when present, matching the reference's
     api_kwargs["tools"] = tools. Moonshot's stricter tool schema is not yet
     reproduced -- no moonshot scenario is under test, and pretending otherwise
     would be tuning; that gap is left explicit for when one is added. *)
  if tools <> [] then top_level := ("tools", `List tools) :: !top_level;
  if supports_reasoning then (
    if anthropic_reasoning_mandatory model_id then
      match reasoning with
      | Effort effort -> top_level := ("verbosity", `String effort) :: !top_level
      | Unspecified | Disabled -> ()
    else
      let configured =
        match reasoning with
        | Unspecified -> `Assoc [ ("enabled", `Bool true); ("effort", `String "medium") ]
        | Disabled -> `Assoc [ ("enabled", `Bool false) ]
        | Effort effort -> `Assoc [ ("enabled", `Bool true); ("effort", `String effort) ]
      in
      extra_body := ("reasoning", configured) :: !extra_body);
  let sticky = nonempty session_id in
  if String.starts_with ~prefix:"x-ai/grok-" model_id || String.starts_with ~prefix:"xai/grok-" model_id then (
    match sticky with
    | Some value -> top_level := ("extra_headers", `Assoc [ ("x-grok-conv-id", `String value) ]) :: !top_level
    | None -> ());
  let body = `Assoc (List.rev_append (assoc_if_nonempty (List.rev !extra_body)) (List.rev !top_level)) in
  { endpoint = resolved.base_url ^ "/chat/completions"; api_key = resolved.api_key; body }
