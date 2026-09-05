let member name = function `Assoc fields -> List.assoc_opt name fields | _ -> None

let () =
  let open Turn_preflight in
  let without_key = Openrouter_contract.{ supplied_key = None; openrouter_key = None; openai_key = None; base_url_override = None } in
  let initial = Turn_budget.create 1 in
  assert (prepare ~budget:initial ~credentials:without_key ~model:"openai/gpt-5.4" ~messages:[]
            ~reasoning:Openrouter_contract.Unspecified ~supports_reasoning:true ~session_id:None
            ~provider_preferences:None ~pareto_min_coding_score:None = Rejected (Missing_credentials, initial));
  let with_key = { without_key with Openrouter_contract.openrouter_key = Some "key" } in
  let exhausted = Turn_budget.create 0 in
  assert (prepare ~budget:exhausted ~credentials:with_key ~model:"openai/gpt-5.4" ~messages:[]
            ~reasoning:Openrouter_contract.Unspecified ~supports_reasoning:true ~session_id:None
            ~provider_preferences:None ~pareto_min_coding_score:None = Rejected (Exhausted, exhausted));
  match prepare ~budget:initial ~credentials:with_key ~model:"openai/gpt-5.4"
          ~messages:[ `Assoc [ ("role", `String "user"); ("_internal", `Bool true) ] ]
          ~reasoning:Openrouter_contract.Disabled ~supports_reasoning:true ~session_id:None
          ~provider_preferences:None ~pareto_min_coding_score:None with
  | Rejected _ -> failwith "expected a ready request"
  | Ready { budget; request } ->
      assert (Turn_budget.used budget = 1);
      let messages = match member "messages" request.body with Some (`List [ message ]) -> message | _ -> failwith "missing messages" in
      assert (member "_internal" messages = None)

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_turn_preflight" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_turn_preflight ]);
  exit (Suite_telemetry.exit_code self)
