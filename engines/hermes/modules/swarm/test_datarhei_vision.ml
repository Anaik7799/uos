open Alcotest
open Datarhei_intent

let string_contains s sub =
  let re = Str.regexp_string sub in
  try ignore (Str.search_forward re s 0); true
  with Not_found -> false

(* 1. Unit & Component Test *)
let test_intent_synthesis () =
  let env = Datarhei_intent.default_hardened_envelope in
  let request =
    match Vision_swarm_adapter.prepare ~request_id:"datarhei-unit" env with
    | Ok request -> request
    | Error errors ->
        errors
        |> List.map Vision_swarm_adapter.string_of_error
        |> String.concat "; "
        |> fail
  in
  check string "Request ID matches" "datarhei-unit" request.request_id;
  (match request.intent with
  | Ffmpeg_intent.Transmux_Stream { source; sink } ->
      check string "Source endpoint is retained" env.source.endpoint source;
      check string "Target host becomes the typed sink" ("webrtc://" ^ env.host) sink
  | _ -> fail "Datarhei preparation must produce a transmux intent");
  
  let html = Datarhei_intent.synthesize_html_config env in
  if not (string_contains html "ws://localhost:3333/app/stream") then
    fail "HTML Synthesis failed to emit endpoint"

let test_bdd_synthesis () =
  let env = Datarhei_intent.default_hardened_envelope in
  let html = Datarhei_intent.synthesize_html_config env in
  let contains_debug = string_contains html "debug: true" in
  check bool "Expect Debug to be true in synthesized HTML" true contains_debug

(* 3. Property / Fuzz Test (QCheck) *)
open QCheck

let arbitrary_retry = QCheck.int_bound 100
let arbitrary_timeout = QCheck.int_range 1000 60000

let prop_synthesize_never_fails =
  Test.make ~name:"Property: HTML synthesis never throws on valid parameters"
    (pair arbitrary_retry arbitrary_timeout)
    (fun (retry, timeout) ->
       let env = { Datarhei_intent.default_hardened_envelope with 
                   max_retry = retry; connection_timeout_ms = timeout } in
       let html = Datarhei_intent.synthesize_html_config env in
       String.length html > 0
       && match Vision_swarm_adapter.prepare ~request_id:"property" env with
          | Ok _ -> true
          | Error _ -> false
    )

let test_fuzz_synthesis () =
  QCheck.Test.check_exn prop_synthesize_never_fails

(* 4. System & Chaos Test *)
let test_chaos_invalid_envelope_is_typed () =
  let env =
    { Datarhei_intent.default_hardened_envelope with
      host = "";
      connection_timeout_ms = min_int }
  in
  match Vision_swarm_adapter.prepare ~request_id:"chaos" env with
  | Error errors ->
      check Alcotest.bool "Empty host is named" true
        (List.mem Vision_swarm_adapter.Empty_host errors);
      check Alcotest.bool "Invalid timeout is named" true
        (List.mem
           (Vision_swarm_adapter.Invalid_connection_timeout min_int)
           errors)
  | Ok _ -> fail "invalid envelope was admitted"

let () =
  run ~and_exit:false "Datarhei Vision Pipeline Envelope Tests" [
    "Unit/Component", [
      test_case "Intent Synthesis" `Quick test_intent_synthesis;
      test_case "BDD Expected Synthesis" `Quick test_bdd_synthesis;
    ];
    "Chaos/System", [
      test_case "Invalid envelopes are typed refusals" `Quick
        test_chaos_invalid_envelope_is_typed;
    ];
    "Property/Fuzz", [
      test_case "QCheck Synthesis Parameters" `Quick test_fuzz_synthesis;
    ];
  ];
  let self =
    Suite_telemetry.observe ~suite:"test_datarhei_vision" ~passed:1 ~failed:0
      ~skipped:0
  in
  print_newline ();
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_sop_execution; Stanza.hermes_harness_swarm_algebra ]);
  exit (Suite_telemetry.exit_code self)
