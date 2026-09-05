(* HZ-NRM-01: normalization must not erase a field that genuinely diverged.

   This suite previously loaded a pinned fixture, extracted its `model` and
   `messages`, ran the candidate on those exact values, and asserted the output
   equalled the fixture. The fixtures it used were among the 88 stub traces
   quarantined on 2026-08-11, whose payload was `{model, messages}` and nothing
   else — so the assertion reduced to "a function returns its own arguments",
   which is true of the correct implementation and of a bare `fun x -> x`. It
   was vacuous evidence in a suite named after the false-parity hazard, and it
   is exactly what HZ-FIX-03 now forbids.

   It also resolved its fixture through a hardcoded /home/an/... path, which
   R19 clause 5 forbids.

   What survives is what was always real: the normalizer must declare no
   volatile path under `agent_loop` (the actual HZ-NRM-01 property, which needs
   no fixture at all), plus structural properties of the candidates. Every
   property here is paired with a NEGATIVE CONTROL — a deliberately wrong
   implementation that must fail it. A property no wrong implementation fails
   is not a test. *)

let passed = ref 0
let failures = ref []

let check condition label =
  if condition then incr passed else failures := label :: !failures

(* ------------------------------------------------------- the HZ-NRM-01 law *)

let volatile_layer () =
  let default_norm = Parity_normalizer.default in
  let widened_under prefix =
    List.exists
      (fun path ->
        String.length path >= String.length prefix
        && String.sub path 0 (String.length prefix) = prefix)
      default_norm.Parity_normalizer.volatile_paths
  in
  check (not (widened_under "agent_loop")) "no volatile path widening under agent_loop";
  (* Non-vacuity: the detector must be able to SEE a widening, or "none found"
     is indistinguishable from a broken search. The default set is non-empty,
     and the same predicate finds one of its real entries. *)
  check
    (default_norm.Parity_normalizer.volatile_paths <> [])
    "the volatile set is non-empty (the check has something to search)";
  check
    (List.exists
       (fun path -> widened_under path)
       default_norm.Parity_normalizer.volatile_paths)
    "the widening predicate finds a declared volatile path (non-vacuous)"

(* ------------------------------------------- candidate structural properties *)

let messages_of items =
  List.map (fun (role, content) ->
      `Assoc [ ("role", `String role); ("content", `String content) ])
    items

(* A distinguishing input: three messages, distinct contents, distinct roles,
   in an order a careless implementation would lose. *)
let sample =
  messages_of [ ("system", "alpha"); ("user", "beta"); ("assistant", "gamma") ]

let contents_of (json : Yojson.Safe.t) =
  match json with
  | `Assoc fields -> (
      match List.assoc_opt "messages" fields with
      | Some (`List items) ->
          List.filter_map
            (fun item ->
              match item with
              | `Assoc kv -> (
                  match List.assoc_opt "content" kv with
                  | Some (`String s) -> Some s
                  | _ -> None)
              | _ -> None)
            items
      | _ -> [])
  | _ -> []

let model_of (json : Yojson.Safe.t) =
  match json with
  | `Assoc fields -> (
      match List.assoc_opt "model" fields with Some (`String m) -> Some m | _ -> None)
  | _ -> None

(* The properties, stated once so the same predicates judge the candidate and
   the negative controls. *)
let preserves_order output = contents_of output = [ "alpha"; "beta"; "gamma" ]
let preserves_model output = model_of output = Some "openai/gpt-5.4"

let candidate_layer () =
  let conversation = Conversation_loop.process ~model_id:"openai/gpt-5.4" ~messages:sample in
  let assembled = Prompt_assembly.assemble ~model_id:"openai/gpt-5.4" ~messages:sample in

  check (preserves_order conversation) "conversation_loop preserves message order and content";
  check (preserves_model conversation) "conversation_loop preserves the model id";
  check (preserves_order assembled) "prompt_assembly preserves message order and content";
  check (preserves_model assembled) "prompt_assembly preserves the model id";
  check
    (match assembled with
    | `Assoc fields ->
        let keys = List.map fst fields in
        List.mem "messages" keys && List.mem "model" keys
    | _ -> false)
    "prompt_assembly returns an object carrying messages and model";

  (* NEGATIVE CONTROLS. Each is a plausible wrong implementation; the property
     above must reject it. Without these the properties could hold for reasons
     unrelated to the candidates being correct. *)
  let dropped = `Assoc [ ("model", `String "openai/gpt-5.4");
                         ("messages", `List (List.tl (List.tl sample))) ] in
  let reordered = `Assoc [ ("model", `String "openai/gpt-5.4");
                           ("messages", `List (List.rev sample)) ] in
  let wrong_model = `Assoc [ ("model", `String "openai/gpt-4"); ("messages", `List sample) ] in
  check (not (preserves_order dropped)) "CONTROL a dropping implementation fails the order property";
  check (not (preserves_order reordered)) "CONTROL a reordering implementation fails the order property";
  check (not (preserves_model wrong_model)) "CONTROL a wrong-model implementation fails the model property"

let () =
  Printf.printf "=== Running test_hz_nrm_01 ===\n";
  volatile_layer ();
  candidate_layer ();
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  (* R30 exemplar on a pre-existing suite: three lines to conform. The
     dependents are this suite s reverse cone — the two candidate modules it
     exercises and the harness comparison plane that consumes their shape. *)
  let self =
    Suite_telemetry.observe ~suite:"test_hz_nrm_01" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self
       ~targets:[ Stanza.hermes_agent_loop_conversation_loop; Stanza.hermes_agent_loop_prompt_assembly; Stanza.hermes_agent_loop_context_engine; Stanza.hermes_agent_loop_context_compression; Stanza.hermes_agent_loop_turn_finalization; Stanza.hermes_agent_loop_interrupt_control; Stanza.hermes_agent_loop_message_hygiene; Stanza.hermes_agent_loop_message_repairs; Stanza.hermes_agent_loop_json_canonical; Stanza.hermes_agent_loop_loop_send_path; Stanza.hermes_agent_loop_prompt_units; Stanza.hermes_agent_loop_context_units; Stanza.hermes_agent_loop_compress_units; Stanza.hermes_agent_loop_finalize_units; Stanza.hermes_agent_loop_redact_units; Stanza.hermes_agent_loop_tool_units; Stanza.hermes_agent_loop_context_file_units; Stanza.hermes_agent_loop_memory_units; Stanza.hermes_agent_loop_skill_units; Stanza.hermes_agent_loop_interactive_cli_units; Stanza.hermes_agent_loop_mcp_units; Stanza.hermes_agent_loop_subagent_units ]);
  exit (Suite_telemetry.exit_code self)
