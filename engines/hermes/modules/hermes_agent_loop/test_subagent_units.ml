(* Hand-written invariants over the subagents units -- the backstop the
   parity fixtures cannot be. Every law carries a negative control where
   the gotcha has one. *)

let passed = ref 0
let failures = ref []

let check condition label =
  if condition then incr passed else failures := label :: !failures

let () =
  (* ---- subagent_lifecycle ---- *)
  let full_handle =
    `Assoc
      [ ("contract_version", `Int 1); ("subagent_id", `String "sa1"); ("parent_session_id", `Null);
        ("correlation_id", `Null); ("created_at", `Float 1.5); ("provider", `Null); ("model", `Null);
        ("role", `String "leaf"); ("depth", `Int 0); ("capability", `String "x") ]
  in
  check
    (match Subagent_units.subagent_handle_from_dict full_handle with Ok _ -> true | Error _ -> false)
    "LIFECYCLE subagent_handle_from_dict accepts a key-complete handle";
  check
    (match Subagent_units.subagent_handle_from_dict (`Assoc [ ("subagent_id", `String "sa1") ]) with
     | Error "Malformed subagent handle." -> true
     | _ -> false)
    "CONTROL subagent_handle_from_dict rejects a handle missing required keys";
  check
    (match Subagent_units.subagent_handle_from_dict (`Assoc (("extra_field", `Int 1) :: (match full_handle with `Assoc f -> f | _ -> []))) with
     | Error "Malformed subagent handle." -> true
     | _ -> false)
    "CONTROL subagent_handle_from_dict rejects a handle with an unexpected extra key (Python's dataclass ctor errors on unknown kwargs too)";
  check
    (match Subagent_units.subagent_handle_from_dict full_handle with
     | Ok h -> Subagent_units.subagent_handle_to_dict h = h
     | Error _ -> false)
    "LIFECYCLE to_dict/from_dict round-trips a valid handle in canonical field order";

  check
    (match
       Subagent_units.validate_request ~goal:"do it" ~context:None ~role:"leaf" ~timeout_seconds:None
         ~working_directory:None ~blocked_tools:[] ~metadata:(`Assoc []) ~allowed_toolsets:[] ~known_toolsets:[]
         ~parent_enabled_toolsets:None
     with
     | Ok () -> true
     | Error _ -> false)
    "LIFECYCLE validate_request accepts a minimal valid request";
  check
    (match
       Subagent_units.validate_request ~goal:"   " ~context:None ~role:"leaf" ~timeout_seconds:None
         ~working_directory:None ~blocked_tools:[] ~metadata:(`Assoc []) ~allowed_toolsets:[] ~known_toolsets:[]
         ~parent_enabled_toolsets:None
     with
     | Error _ -> true
     | Ok () -> false)
    "CONTROL validate_request rejects a whitespace-only goal";
  check
    (match
       Subagent_units.validate_request ~goal:"g" ~context:None ~role:"leaf" ~timeout_seconds:(Some 5.0)
         ~working_directory:None ~blocked_tools:[] ~metadata:(`Assoc []) ~allowed_toolsets:[] ~known_toolsets:[]
         ~parent_enabled_toolsets:None
     with
     | Error msg -> Subagent_units.contains ~needle:"Per-launch timeout" msg
     | Ok () -> false)
    "LIFECYCLE validate_request refuses any explicit per-launch timeout";
  check
    (match
       Subagent_units.validate_request ~goal:"g" ~context:None ~role:"leaf" ~timeout_seconds:None
         ~working_directory:None ~blocked_tools:[] ~metadata:(`Assoc []) ~allowed_toolsets:[ "web" ]
         ~known_toolsets:[ "fs" ] ~parent_enabled_toolsets:None
     with
     | Error msg -> Subagent_units.contains ~needle:"Unknown toolsets: web." msg
     | Ok () -> false)
    "LIFECYCLE validate_request rejects an allowed_toolset outside the known set";
  check
    (match
       Subagent_units.validate_request ~goal:"g" ~context:None ~role:"leaf" ~timeout_seconds:None
         ~working_directory:None ~blocked_tools:[] ~metadata:(`Assoc []) ~allowed_toolsets:[ "web" ]
         ~known_toolsets:[ "web" ] ~parent_enabled_toolsets:(Some [ "fs" ])
     with
     | Error msg -> Subagent_units.contains ~needle:"broaden parent" msg
     | Ok () -> false)
    "LIFECYCLE validate_request rejects a toolset that would broaden parent permissions";

  check
    (let a = Subagent_units.capability ~secret:"k" ~subagent_id:"sa1" ~parent_session_id:None ~created_at:1.5 in
     let b = Subagent_units.capability ~secret:"k" ~subagent_id:"sa1" ~parent_session_id:(Some "") ~created_at:1.5 in
     a = b)
    "LIFECYCLE capability: None and Some \"\" parent_session_id sign identically (both fold to '')";
  check
    (Subagent_units.capability ~secret:"k1" ~subagent_id:"sa1" ~parent_session_id:None ~created_at:1.0
    <> Subagent_units.capability ~secret:"k2" ~subagent_id:"sa1" ~parent_session_id:None ~created_at:1.0)
    "CONTROL capability differs under a different secret";

  (* ---- delegation ---- *)
  check
    (let out = Subagent_units.build_child_system_prompt ~goal:"g" ~context:None ~workspace_path:None ~role:"leaf" ~max_spawn_depth:2 ~child_depth:0 in
     Subagent_units.contains ~needle:"YOUR TASK:\ng" out && not (Subagent_units.contains ~needle:"Subagent Spawning" out))
    "DELEGATION build_child_system_prompt omits the orchestrator block for a leaf";
  check
    (let out = Subagent_units.build_child_system_prompt ~goal:"g" ~context:None ~workspace_path:None ~role:"orchestrator" ~max_spawn_depth:2 ~child_depth:1 in
     Subagent_units.contains ~needle:"MUST be leaves" out)
    "DELEGATION build_child_system_prompt: child_depth+1 >= max_spawn_depth forces the depth-floor note";
  check
    (let out = Subagent_units.build_child_system_prompt ~goal:"g" ~context:None ~workspace_path:None ~role:"orchestrator" ~max_spawn_depth:3 ~child_depth:0 in
     Subagent_units.contains ~needle:"can themselves be orchestrators" out)
    "CONTROL build_child_system_prompt: below the depth floor, children may still orchestrate";

  check
    (Subagent_units.stringify_tool_content (`List [ `Assoc [ ("type", `String "text"); ("text", `String "hi") ] ]) = "hi")
    "DELEGATION stringify_tool_content extracts text from a content-block list";
  check (Subagent_units.stringify_tool_content `Null = "") "CONTROL stringify_tool_content on None is empty";
  check
    (Subagent_units.looks_like_error_output "{\"error\": true}")
    "DELEGATION looks_like_error_output flags structured JSON with a truthy error key";
  check
    (not (Subagent_units.looks_like_error_output "{\"error\": 0}"))
    "CONTROL looks_like_error_output: error=0 is Python-falsy, not flagged";
  check
    (Subagent_units.looks_like_error_output "Traceback (most recent call last):")
    "DELEGATION looks_like_error_output flags a traceback first-line marker";

  check
    (let result =
       `Assoc
         [ ( "messages",
             `List
               [ `Assoc [ ("role", `String "assistant"); ("tool_calls", `List [ `Assoc [ ("id", `String "c1"); ("function", `Assoc [ ("name", `String "search") ]) ] ]) ];
                 `Assoc [ ("role", `String "tool"); ("tool_call_id", `String "c1"); ("content", `String "result text") ] ] ) ]
     in
     match Subagent_units.extract_output_tail result ~max_entries:12 ~max_chars:8000 with
     | [ `Assoc f ] -> List.assoc_opt "tool" f = Some (`String "search")
     | _ -> false)
    "DELEGATION extract_output_tail maps a tool result back to its calling tool name";

  check
    (Subagent_units.scrub_kanban_env [ ("HERMES_KANBAN_TASK", "x"); ("OTHER", "y") ] = [ ("OTHER", "y"); ("HERMES_DELEGATED_CHILD_CONTEXT", "1") ])
    "DELEGATION scrub_kanban_env drops dispatcher-only keys and appends the child marker last";
  check (Subagent_units.normalize_role (Some "WEIRD") = "leaf") "DELEGATION normalize_role coerces an unknown role to leaf";
  check (Subagent_units.normalize_role None = "leaf") "CONTROL normalize_role on None is leaf";
  check (Subagent_units.normalized_runtime_url (Some "http://x///") = "http://x") "DELEGATION normalized_runtime_url strips ALL trailing slashes";

  (* ---- async_delegation ---- *)
  check
    (match Subagent_units.children_activity_from_token (Some [ `List [ `Int 3; `String "grep" ] ]) ~now:100.0 with
     | Some (`List [ `Assoc f ]) -> List.assoc_opt "api_calls" f = Some (`Int 3) && not (List.mem_assoc "seconds_since_activity" f)
     | _ -> false)
    "ASYNC children_activity_from_token: a 2-tuple part has no seconds_since_activity";
  check (Subagent_units.children_activity_from_token None ~now:1.0 = None) "CONTROL children_activity_from_token on a non-list token";
  check (Subagent_units.round1 0.25 = 0.2) "ASYNC round1 is round-half-to-even, not round-half-up (0.25 -> 0.2)";

  check (Subagent_units.one_line (`Int 0) ~limit:10 = "") "ASYNC one_line: falsy 0 collapses to \"\", not \"0\" (str(text or \"\"))";
  check (Subagent_units.one_line (`String "a   b\nc") ~limit:10 = "a b c") "ASYNC one_line collapses whitespace runs to a single space";
  check
    (Subagent_units.contains ~needle:"\xe2\x80\xa6(+2 chars)" (Subagent_units.one_line (`String "abcdefgh") ~limit:6))
    "ASYNC one_line's truncation marker uses the Unicode ellipsis character, not three periods";

  check
    (Subagent_units.matches_session_selectors ~record:(`Assoc [ ("session_key", `String "k1") ]) ~session_key:"k1" ~origin_ui_session_id:"" ~parent_session_id:"" = `Bool true)
    "ASYNC matches_session_selectors: `X and (a==b)` returns the boolean COMPARISON, not the string X, once X is truthy";
  check
    (Subagent_units.matches_session_selectors ~record:(`Assoc [ ("session_key", `String "other") ]) ~session_key:"k1" ~origin_ui_session_id:"" ~parent_session_id:"" = `String "")
    "CONTROL matches_session_selectors: a non-matching truthy selector (Bool false) does not short-circuit the or-chain -- it falls through to the next clause, here the falsy final default";
  check
    (Subagent_units.matches_session_selectors ~record:(`Assoc []) ~session_key:"k1" ~origin_ui_session_id:"" ~parent_session_id:"p1" = `Bool false)
    "ASYNC matches_session_selectors: when the LAST clause is reached, its own boolean outcome is returned as-is even when False (the or-chain's final operand, not a short-circuit result)";
  check
    (Subagent_units.matches_session_selectors ~record:(`Assoc []) ~session_key:"" ~origin_ui_session_id:"" ~parent_session_id:"" = `String "")
    "CONTROL matches_session_selectors with every selector at its default returns the string \"\", not false (and/or return operands)";

  (* ---- mixture_of_agents ---- *)
  check
    (Subagent_units.flatten_message_text (`List [ `Assoc [ ("type", `String "text"); ("text", `String "hi") ]; `Assoc [ ("type", `String "image_url") ] ]) = "hi")
    "MOA flatten_message_text skips non-text part types";
  check
    (let messages =
       [ `Assoc [ ("role", `String "user"); ("content", `String "hello") ] ]
     in
     match Subagent_units.reference_messages ~tool_result_budget:100 messages with
     | [ `Assoc f ] -> List.assoc_opt "content" f = Some (`String "hello")
     | _ -> false)
    "MOA reference_messages: a lone user turn is echoed through";
  check
    (let messages = [ `Assoc [ ("role", `String "assistant"); ("content", `String "done") ] ] in
     match Subagent_units.reference_messages ~tool_result_budget:100 messages with
     | [ _; `Assoc last ] -> List.assoc_opt "content" last = Some (`String Subagent_units.advisory_instruction)
     | _ -> false)
    "MOA reference_messages appends the advisory instruction when the last rendered turn is assistant";
  check
    (let out = Subagent_units.peel_reference_guidance ~guidance:(`String "g") [ `Assoc [ ("role", `String "user"); ("content", `String "g") ] ] in
     out = [])
    "MOA peel_reference_guidance drops a message that was ONLY the appended guidance (attach shape c)";
  check
    (let msgs = [ `Assoc [ ("role", `String "user"); ("content", `String "base\n\ng") ] ] in
     match Subagent_units.peel_reference_guidance ~guidance:(`String "g") msgs with
     | [ `Assoc f ] -> List.assoc_opt "content" f = Some (`String "base")
     | _ -> false)
    "MOA peel_reference_guidance un-merges a trailing string-append (attach shape a)";

  check (Subagent_units.is_failed_reference "[FAILED: timeout]") "MOA is_failed_reference is case-insensitive on the sentinel";
  check
    (Subagent_units.degraded_notice [ "a"; "b" ] "SILENT" = "")
    "CONTROL degraded_notice with policy=silent (any case) never emits a notice even with failures";
  check (Subagent_units.preset_temperature (`Assoc [ ("t", `Int 0) ]) "t" = Some 0.0) "MOA preset_temperature: explicit 0 is a real value, not treated as absent";
  check (Subagent_units.preset_temperature (`Assoc []) "t" = None) "CONTROL preset_temperature on an absent key is None";
  check (Subagent_units.slot_label (`Assoc [ ("provider", `String " p "); ("model", `String " m ") ]) = "p:m") "MOA slot_label strips provider/model";
  check
    (Subagent_units.merge_slot_extra_body (`Assoc [ ("a", `Int 1) ]) (`Assoc [ ("a", `Int 2); ("b", `Int 3) ])
    = `Assoc [ ("a", `Int 2); ("b", `Int 3) ])
    "MOA merge_slot_extra_body: caller overrides slot on key collision, position preserved";
  check (Subagent_units.sanitize_session_id (Some "a b!") = "a_b_") "MOA sanitize_session_id replaces non-alnum/-/./_ chars";
  check (Subagent_units.sanitize_session_id None = "unknown-session") "CONTROL sanitize_session_id on None";

  (* ---- kanban_swarm ---- *)
  check
    (match Subagent_units.parse_worker_arg "researcher:Find bugs:python,testing" with
     | Ok (`Assoc f) -> List.assoc_opt "profile" f = Some (`String "researcher") && List.assoc_opt "skills" f = Some (`List [ `String "python"; `String "testing" ])
     | _ -> false)
    "KANBAN parse_worker_arg parses profile:title:skill,skill";
  check
    (match Subagent_units.parse_worker_arg "a:b" with
     | Ok (`Assoc f) -> List.assoc_opt "priority" f = Some (`Int 0) && List.assoc_opt "max_runtime_seconds" f = Some `Null
     | _ -> false)
    "KANBAN parse_worker_arg includes SwarmWorkerSpec's un-set dataclass defaults (priority=0, max_runtime_seconds=None) -- dataclasses.asdict serializes them too";
  check
    (match Subagent_units.parse_worker_arg "a:b:c:d" with
     | Ok (`Assoc f) -> List.assoc_opt "skills" f = Some (`List [ `String "c:d" ])
     | _ -> false)
    "KANBAN parse_worker_arg: maxsplit=2 glues a stray colon into the skills blob, not a 4th field";
  check (match Subagent_units.parse_worker_arg "solo" with Error _ -> true | Ok _ -> false) "CONTROL parse_worker_arg rejects a single-field spec";

  check (match Subagent_units.require_text "  " "goal" with Error _ -> true | Ok _ -> false) "KANBAN require_text rejects whitespace-only input";
  check (Subagent_units.swarm_context ~root_id:"r1" ~goal:" g " = "\n\n## Swarm protocol\n- Swarm root / shared blackboard: `r1`.\n- Read sibling/parent handoffs from Kanban context before working.\n- Put machine-readable facts in completion metadata.\n- Put cross-worker notes on the root task using structured comments.\n- Goal: g\n") "KANBAN swarm_context exact template";

  check (Subagent_units.parse_bool_arg (`Assoc [ ("x", `String "YES") ]) "x" ~default:false = (true, None)) "KANBAN parse_bool_arg accepts case-insensitive 'yes'";
  check (Subagent_units.parse_bool_arg (`Assoc [ ("x", `Int 1) ]) "x" ~default:false = (true, None)) "KANBAN parse_bool_arg: int 1 matches the true set";
  check
    (match Subagent_units.parse_bool_arg (`Assoc [ ("x", `Float 1.0) ]) "x" ~default:false with false, Some _ -> true | _ -> false)
    "CONTROL parse_bool_arg: float 1.0 does NOT match (str(1.0)==\"1.0\", in neither set) -- falls to the error branch";
  check
    (match Subagent_units.parse_bool_arg (`Assoc [ ("x", `Bool true) ]) "x" ~default:false with true, None -> true | _ -> false)
    "KANBAN parse_bool_arg: a real bool is checked before the string membership test";

  check (Subagent_units.normalize_profile (`String "none") = None) "KANBAN normalize_profile folds the 'none' sentinel (case-insensitive)";
  check (Subagent_units.normalize_profile (`String "alice") = Some "alice") "CONTROL normalize_profile passes through a real value";

  Printf.printf "subagents units: %d passed, %d failed\n" !passed (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self = Suite_telemetry.observe ~suite:"test_subagent_units" ~passed:!passed ~failed:(List.length !failures) ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_agent_loop_subagent_units ]);
  exit (Suite_telemetry.exit_code self)
