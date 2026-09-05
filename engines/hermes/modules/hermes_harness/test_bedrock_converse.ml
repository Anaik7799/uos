(* Unit guards for the Bedrock Converse shaper. The captured fixture PROVES
   faithfulness end to end; these pin the load-bearing predicates and the
   Python-json embedder. *)

let json = Yojson.Safe.from_string
let s v = Yojson.Safe.to_string v

let () =
  let open Bedrock_converse in
  (* sampling-param policy across Claude families *)
  assert (forbids_sampling_params "anthropic.claude-opus-4-7-v1:0");
  assert (not (forbids_sampling_params "eu.anthropic.claude-opus-4-6-v1"));
  assert (not (forbids_sampling_params "us.anthropic.claude-sonnet-4-5-20250929-v1:0"));
  assert (not (forbids_sampling_params "meta.llama3-70b"));

  (* routing predicate: at most one region prefix stripped *)
  assert (is_anthropic_bedrock_model "global.anthropic.claude-sonnet-4-5");
  assert (is_anthropic_bedrock_model "jp.anthropic.claude-haiku-4-5");
  assert (not (is_anthropic_bedrock_model "us.eu.anthropic.claude-x"));
  assert (not (is_anthropic_bedrock_model "us.amazon.nova-pro-v1:0"));

  (* Python json.dumps: input key order, ", "/": " separators, lowercase bool *)
  assert (python_json (json {|{"ok":true,"n":2}|}) = {|{"ok": true, "n": 2}|});

  (* safe_text: null/blank -> "(empty)"; non-blank unchanged *)
  assert (safe_text `Null = "(empty)");
  assert (safe_text (`String "   ") = "(empty)");
  assert (safe_text (`String " keep ") = " keep ");

  (* build: opus-4-7 drops sampling; single message, no cachePoint *)
  (match build_converse_kwargs ~model:"anthropic.claude-opus-4-7-v1:0"
           ~messages:[ json {|{"role":"user","content":"x"}|} ] ~temperature:0.9 ~top_p:0.5 () with
  | `Assoc kv ->
      (match List.assoc_opt "inferenceConfig" kv with
      | Some (`Assoc ic) ->
          assert (List.assoc_opt "maxTokens" ic = Some (`Int 4096));
          assert (List.assoc_opt "temperature" ic = None);
          assert (List.assoc_opt "topP" ic = None)
      | _ -> failwith "inferenceConfig missing");
      assert (List.assoc_opt "system" kv = None)
  | _ -> failwith "build did not return an object");

  (* empty messages -> no first/last fixes *)
  assert (
    s (build_converse_kwargs ~model:"amazon.titan-text-express-v1" ~messages:[] ())
    = {|{"modelId":"amazon.titan-text-express-v1","messages":[],"inferenceConfig":{"maxTokens":4096}}|});

  print_endline "bedrock_converse: ok"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_bedrock_converse" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_bedrock_converse ]);
  exit (Suite_telemetry.exit_code self)
