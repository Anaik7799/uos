(** Injectable OpenRouter chat-completions transport.

    The executor is intentionally supplied by a higher layer.  This keeps the
    protocol decoder deterministic and prevents bootstrap/tests from creating
    network traffic. *)

type tool_call = { id : string; name : string; arguments : string }
type usage = { prompt_tokens : int option; completion_tokens : int option; total_tokens : int option }

type response = {
  id : string option;
  content : string option;
  finish_reason : string;
  tool_calls : tool_call list;
  usage : usage option;
}

type error = Missing_credentials | Transport_error of string | Http_error of int | Malformed_response

type executor = endpoint:string -> api_key:string -> body:string -> (int * string, string) result

let member name (value : Yojson.Safe.t) =
  match value with `Assoc fields -> List.assoc_opt name fields | _ -> None

let string (value : Yojson.Safe.t option) =
  match value with Some (`String text) -> Some text | Some _ | None -> None

let integer (value : Yojson.Safe.t option) =
  match value with Some (`Int number) -> Some number | Some _ | None -> None

let decode_tool_call (value : Yojson.Safe.t) =
  match value with
  | `Assoc fields ->
      let id = string (List.assoc_opt "id" fields) in
      let function_data = List.assoc_opt "function" fields in
      let name = Option.bind function_data (fun value -> string (member "name" value)) in
      let arguments = Option.bind function_data (fun value -> string (member "arguments" value)) in
      (match id, name, arguments with
      | Some id, Some name, Some arguments -> Some { id; name; arguments }
      | None, _, _ | _, None, _ | _, _, None -> None)
  | _ -> None

let decode_usage (value : Yojson.Safe.t option) =
  match value with
  | Some (`Assoc _ as value) ->
      (* total_tokens is the provider's figure passed through, faithful to the
         frozen getattr(u, "total_tokens", 0) -- not a computed prompt+completion. *)
      Some { prompt_tokens = integer (member "prompt_tokens" value); completion_tokens = integer (member "completion_tokens" value); total_tokens = integer (member "total_tokens" value) }
  | Some _ | None -> None

let decode (json : Yojson.Safe.t) =
  let id = string (member "id" json) in
  match member "choices" json with
  | Some (`List (`Assoc choice_fields :: _)) ->
      (match string (List.assoc_opt "finish_reason" choice_fields), List.assoc_opt "message" choice_fields with
      | Some finish_reason, Some (`Assoc _ as message) ->
          let content = string (member "content" message) in
          let tool_calls =
            match member "tool_calls" message with
            | Some (`List values) -> List.filter_map decode_tool_call values
            | Some _ | None -> []
          in
          (* Refusal promotion, faithful to chat_completions.normalize_response:
             a non-empty refusal that is the SOLE payload -- no visible text and
             no tool calls -- is adopted as content, and a "stop" finish becomes
             content_filter so the loop's refusal handler surfaces it. A refusal
             alongside real content or tool calls is a normal turn, left as is. *)
          let has_text = match content with Some text -> String.trim text <> "" | None -> false in
          let content, finish_reason =
            match string (member "refusal" message) with
            | Some refusal when String.trim refusal <> "" && (not has_text) && tool_calls = [] ->
                (Some refusal, if finish_reason = "stop" then "content_filter" else finish_reason)
            | Some _ | None -> (content, finish_reason)
          in
          Some { id; content; finish_reason; tool_calls; usage = decode_usage (member "usage" json) }
      | None, _ | _, None | _, Some _ -> None)
  | Some _ | None -> None

let submit ~execute request =
  match request.Openrouter_contract.api_key with
  | None -> Error Missing_credentials
  | Some api_key ->
      let body = Yojson.Safe.to_string request.body in
      (match execute ~endpoint:request.endpoint ~api_key ~body with
      | Error message -> Error (Transport_error message)
      | Ok (status, _) when status < 200 || status >= 300 -> Error (Http_error status)
      | Ok (_, raw) ->
          try
            match decode (Yojson.Safe.from_string raw) with
            | Some response -> Ok response
            | None -> Error Malformed_response
          with Yojson.Json_error _ -> Error Malformed_response)
