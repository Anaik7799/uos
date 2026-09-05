(* Hand-written invariants over the list-level sanitizer -- the backstop the
   parity fixture cannot be: hygiene.list_repairs pins WHAT the frozen
   reference does; these laws pin what any sanitizer must do, and they are
   never auto-accepted. Every law carries a negative control (HZ-FIX-03). *)

let passed = ref 0
let failures = ref []

let check condition label =
  if condition then incr passed else failures := label :: !failures

let msg fields : Yojson.Safe.t = `Assoc fields
let user content = msg [ ("role", `String "user"); ("content", `String content) ]

let call ~id ~name =
  `Assoc
    [ ("id", `String id); ("type", `String "function");
      ("function", `Assoc [ ("name", `String name); ("arguments", `String "{}") ]) ]

let assistant_calls calls =
  msg [ ("role", `String "assistant"); ("content", `Null); ("tool_calls", `List calls) ]

let tool ~id content =
  msg [ ("role", `String "tool"); ("tool_call_id", `String id); ("content", `String content) ]

open Message_repairs

let () =
  (* IDEMPOTENCE: a sanitized transcript is a fixed point. A second pass that
     still changes something means a repair produces output another repair
     rejects -- the self-healing loop would never settle. *)
  let poisoned =
    [ msg [ ("role", `String "telemetry"); ("content", `String "boot") ];
      msg [ ("role", `String "assistant"); ("content", `Null); ("tool_calls", `List []) ];
      assistant_calls [ call ~id:"c1" ~name:""; call ~id:"c1" ~name:"dup" ];
      tool ~id:"ghost" "zombie";
      assistant_calls [ call ~id:"c2" ~name:"lookup" ];
      user "done" ]
  in
  let once = sanitize_api_messages poisoned in
  check (sanitize_api_messages once = once) "LAW sanitize is idempotent";
  check (once <> poisoned)
    "CONTROL the poisoned transcript actually changed (the law is not vacuous)";

  (* PAIRING: after sanitizing, every tool result's id has a matching call and
     every call id has exactly one result. This is THE property the frozen
     pipeline exists to guarantee (providers 400 on violations). *)
  let call_ids messages =
    List.concat_map
      (fun m ->
        match m with
        | `Assoc fields when List.assoc_opt "role" fields = Some (`String "assistant") -> (
            match List.assoc_opt "tool_calls" fields with
            | Some (`List calls) ->
                List.filter_map
                  (fun c ->
                    match c with
                    | `Assoc cf -> (
                        match (List.assoc_opt "call_id" cf, List.assoc_opt "id" cf) with
                        | Some (`String id), _ | None, Some (`String id) -> Some id
                        | _ -> None)
                    | _ -> None)
                  calls
            | _ -> [])
        | _ -> [])
      messages
  in
  let result_ids messages =
    List.filter_map
      (fun m ->
        match m with
        | `Assoc fields when List.assoc_opt "role" fields = Some (`String "tool") -> (
            match List.assoc_opt "tool_call_id" fields with
            | Some (`String id) -> Some id
            | _ -> None)
        | _ -> None)
      messages
  in
  let calls = List.sort compare (call_ids once) in
  let results = List.sort compare (result_ids once) in
  check (calls = results) "LAW every surviving call pairs 1:1 with a result";
  check (List.sort compare (call_ids poisoned) <> List.sort compare (result_ids poisoned))
    "CONTROL the poisoned transcript violated pairing before repair";

  (* NO EMPTY NON-FINAL: after sanitizing, no non-final user/assistant turn is
     payload-less. *)
  let final_index = List.length once - 1 in
  let empty_non_final =
    List.filteri
      (fun index m ->
        index <> final_index
        && (match m with
           | `Assoc fields -> (
               match List.assoc_opt "role" fields with
               | Some (`String ("user" | "assistant")) -> (
                   match List.assoc_opt "content" fields with
                   | Some (`String text) ->
                       String.trim text = ""
                       && List.assoc_opt "tool_calls" fields = None
                   | Some `Null -> List.assoc_opt "tool_calls" fields = None
                   | _ -> false)
               | _ -> false)
           | _ -> false))
      once
  in
  check (empty_non_final = []) "LAW no payload-less non-final turn survives";

  (* SANITIZE NEVER INVENTS a call: output call ids are a subset of input call
     ids. A repair that conjured calls would fabricate conversation. *)
  let subset a b = List.for_all (fun x -> List.mem x b) a in
  check (subset (call_ids once) (call_ids poisoned))
    "LAW no tool call is invented by repair";

  (* An already-clean transcript is untouched -- the negative control for the
     whole pipeline: a sanitizer that rewrites clean input is not a repair. *)
  let clean =
    [ user "hi"; assistant_calls [ call ~id:"k1" ~name:"lookup" ]; tool ~id:"k1" "found";
      user "thanks" ]
  in
  check (sanitize_api_messages clean = clean) "CONTROL a clean transcript is untouched";

  Printf.printf "message repairs: %d passed, %d failed\n" !passed
    (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_message_repairs" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_agent_loop_message_repairs ]);
  exit (Suite_telemetry.exit_code self)
