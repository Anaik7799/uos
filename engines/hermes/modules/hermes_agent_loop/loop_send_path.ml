(* Send-path units of the conversation loop, reproduced faithfully from the
   frozen agent/conversation_loop.py (read completely before writing; parity
   is measured by the loop.* scenarios, never assumed).

   Scope: the HAPPY canonicalization path. The frozen fallback for malformed
   argument strings (_repair_tool_call_arguments) is a separate deep unit
   this module deliberately does not model — a malformed-arguments case
   would diverge, correctly, as unimplemented. The frozen pass also crashes
   outright on a function dict with no "arguments" key (the repair
   expression re-raises inside the except handler); that shape is outside
   any faithful transcript and outside the scenario domain. *)

(* _get_continuation_prompt, branch for branch, byte for byte. *)
let continuation_prompt ~is_partial_stub ~dropped_tools =
  if is_partial_stub && dropped_tools <> [] then
    let rec take n = function
      | [] -> []
      | _ when n = 0 -> []
      | x :: rest -> x :: take (n - 1) rest
    in
    let tool_list = String.concat ", " (take 3 dropped_tools) in
    "[System: Your previous tool call (" ^ tool_list
    ^ ") was too large and the stream timed out before it could be delivered. \
       Do NOT retry the same tool call with the same large content. Instead, \
       break the content into multiple smaller tool calls (e.g. use multiple \
       patch calls or write smaller files). Each tool call's arguments must \
       be under ~8K tokens to avoid stream timeouts.]"
  else if is_partial_stub then
    "[System: The previous response was cut off by a network error \
     mid-stream. Continue exactly where you left off. Do not restart or \
     repeat prior text. Finish the answer directly.]"
  else
    "[System: Your previous response was truncated by the output length \
     limit. Continue exactly where you left off. Do not restart or repeat \
     prior text. Finish the answer directly.]"

let field name = function `Assoc fields -> List.assoc_opt name fields | _ -> None

let set_field name value = function
  | `Assoc fields ->
      `Assoc
        (List.map
           (fun (key, existing) -> if key = name then (key, value) else (key, existing))
           fields)
  | other -> other

(* _canonicalize_api_tool_calls, on the send-path copy: every dict tool_call
   carrying a function dict with a string arguments gets the canonical wire
   form; every other entry is kept as-is. A message whose tool_calls is
   missing, empty, or not a non-empty list is untouched (the frozen guard is
   `if not tcs: continue`). *)
let canonicalize_api_tool_calls messages =
  List.map
    (fun message ->
      match field "tool_calls" message with
      | Some (`List (_ :: _ as calls)) ->
          let canonicalize call =
            match field "function" call with
            | Some (`Assoc _ as fn) -> (
                match field "arguments" fn with
                | Some (`String arg_str) ->
                    set_field "function"
                      (set_field "arguments"
                         (`String (Json_canonical.canonicalize_arguments arg_str))
                         fn)
                      call
                | _ -> call)
            | _ -> call
          in
          set_field "tool_calls" (`List (List.map canonicalize calls)) message
      | _ -> message)
    messages
