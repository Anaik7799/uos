(* Unit cases for the fallback-chain resolver. The captured differential fixture
   is what PROVES faithfulness against the frozen source; these guard the load-
   bearing branches: order preservation, case-insensitive first-wins dedup,
   skipping invalid entries with whitespace stripping, falsy base_url survival,
   and Python str() scalar coercion. *)

let json = Yojson.Safe.from_string
let chain s = Yojson.Safe.to_string (Route_resolution.get_fallback_chain (json s))

let () =
  (* S1/S2: null and {} -> [] *)
  assert (chain "null" = "[]");
  assert (chain "{}" = "[]");

  (* S3: order preserved across two providers *)
  assert (
    chain {|{"fallback_providers":[{"provider":"openrouter","model":"a"},{"provider":"nous","model":"b"}]}|}
    = {|[{"provider":"openrouter","model":"a"},{"provider":"nous","model":"b"}]|});

  (* S4: legacy single-dict form + trailing-slash normalization *)
  assert (
    chain {|{"fallback_model":{"provider":"ollama","model":"m","base_url":"http://h:11434/v1/"}}|}
    = {|[{"provider":"ollama","model":"m","base_url":"http://h:11434/v1"}]|});

  (* S5: cross-key case-insensitive dedup, first casing wins *)
  assert (
    chain
      {|{"fallback_providers":[{"provider":"OpenRouter","model":"GPT","base_url":"https://O.ai/v1/"}],"fallback_model":[{"provider":"openrouter","model":"gpt","base_url":"https://o.ai/v1"},{"provider":"zai","model":"glm"}]}|}
    = {|[{"provider":"OpenRouter","model":"GPT","base_url":"https://O.ai/v1"},{"provider":"zai","model":"glm"}]|});

  (* S6: invalid entries skipped, whitespace stripped *)
  assert (
    chain
      {|{"fallback_providers":[{"provider":"  ","model":"m"},{"provider":"p"},"nd",42,null,{"provider":" p2 ","model":"  m2  "}]}|}
    = {|[{"provider":"p2","model":"m2"}]|});

  (* S8: falsy base_url survives untouched (empty string and null kept) *)
  assert (
    chain {|{"fallback_providers":[{"provider":"a","model":"b","base_url":""},{"provider":"c","model":"d","base_url":null}]}|}
    = {|[{"provider":"a","model":"b","base_url":""},{"provider":"c","model":"d","base_url":null}]|});

  (* S9: same provider/model, different base_url -> both kept *)
  assert (
    chain {|{"fallback_providers":[{"provider":"l","model":"m","base_url":"http://x:1"},{"provider":"l","model":"m","base_url":"http://x:2"}]}|}
    = {|[{"provider":"l","model":"m","base_url":"http://x:1"},{"provider":"l","model":"m","base_url":"http://x:2"}]|});

  (* S11: Python str() scalar coercion; 0 is falsy -> entry skipped *)
  assert (
    chain {|{"fallback_providers":[{"provider":123,"model":456},{"provider":0,"model":"m"},{"provider":true,"model":"m"}]}|}
    = {|[{"provider":"123","model":"456"},{"provider":"True","model":"m"}]|});

  (* S12: fallback_providers as a single dict is accepted *)
  assert (
    chain {|{"fallback_providers":{"provider":"g","model":"m"}}|} = {|[{"provider":"g","model":"m"}]|});

  (* S7: extra keys pass through verbatim in original order *)
  assert (
    chain {|{"fallback_providers":[{"provider":" c ","model":"x","api_key":"sk","tag":null}]}|}
    = {|[{"provider":"c","model":"x","api_key":"sk","tag":null}]|});

  print_endline "route_resolution: ok"

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_route_resolution" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_route_resolution ]);
  exit (Suite_telemetry.exit_code self)
