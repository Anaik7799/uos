let failures = ref 0
let checks = ref 0

let check name condition =
  incr checks;
  if condition then Printf.printf "  [PASS] %s\n%!" name
  else begin
    incr failures;
    Printf.printf "  [FAIL] %s\n%!" name
  end

let env = Datarhei_intent.default_hardened_envelope

let require_ok label = function
  | Ok value -> value
  | Error errors ->
      let detail =
        errors
        |> List.map Vision_swarm_adapter.string_of_error
        |> String.concat "; "
      in
      failwith (label ^ ": " ^ detail)

let test_typed_projection () =
  let request =
    Vision_swarm_adapter.prepare ~request_id:"vision-request-1" env
    |> require_ok "valid request"
  in
  check "request keeps its caller-supplied identity"
    (request.request_id = "vision-request-1");
  check "request retains the complete declarative envelope"
    (request.envelope = env);
  check "projection maps the source and host without executing them"
    (match request.intent with
    | Ffmpeg_intent.Transmux_Stream { source; sink } ->
        source = env.source.endpoint
        && sink = "webrtc://" ^ env.host
    | _ -> false)

let test_projection_is_deterministic () =
  let first = Vision_swarm_adapter.intent_of_envelope env in
  let second = Vision_swarm_adapter.intent_of_envelope env in
  check "equal envelopes produce equal typed intents" (first = second);
  let first_request =
    Vision_swarm_adapter.prepare ~request_id:"stable" env
    |> require_ok "first deterministic request"
  in
  let second_request =
    Vision_swarm_adapter.prepare ~request_id:"stable" env
    |> require_ok "second deterministic request"
  in
  check "equal admitted inputs produce equal requests"
    (first_request = second_request)

let test_validation_is_total_and_ordered () =
  let invalid_source = { env.source with endpoint = "  " } in
  let invalid =
    { env with
      host = "";
      source = invalid_source;
      max_retry = -1;
      connection_timeout_ms = 0 }
  in
  let expected =
    [ Vision_swarm_adapter.Empty_request_id;
      Vision_swarm_adapter.Empty_source_endpoint;
      Vision_swarm_adapter.Empty_host;
      Vision_swarm_adapter.Invalid_retry_budget (-1);
      Vision_swarm_adapter.Invalid_connection_timeout 0 ]
  in
  check "all invalid fields are returned in stable field order"
    (Vision_swarm_adapter.prepare ~request_id:" \t" invalid = Error expected)

let test_single_boundary_values () =
  check "zero retries is a valid no-retry declaration"
    (match
       Vision_swarm_adapter.prepare ~request_id:"zero-retry"
         { env with max_retry = 0 }
     with
    | Ok _ -> true
    | Error _ -> false);
  check "one millisecond is the smallest admitted timeout"
    (match
       Vision_swarm_adapter.prepare ~request_id:"one-ms"
         { env with connection_timeout_ms = 1 }
     with
    | Ok _ -> true
    | Error _ -> false)

let test_error_rendering () =
  check "retry error rendering preserves the rejected value"
    (Vision_swarm_adapter.string_of_error
       (Vision_swarm_adapter.Invalid_retry_budget (-7))
     = "retry budget must be nonnegative (got -7)");
  check "timeout error rendering preserves the rejected value"
    (Vision_swarm_adapter.string_of_error
       (Vision_swarm_adapter.Invalid_connection_timeout 0)
     = "connection timeout must be positive (got 0)")

let () =
  print_endline "Vision_swarm_adapter — pure typed vision request preparation";
  test_typed_projection ();
  test_projection_is_deterministic ();
  test_validation_is_total_and_ordered ();
  test_single_boundary_values ();
  test_error_rendering ();
  Printf.printf "\n%d/%d checks passed\n" (!checks - !failures) !checks;
  let self =
    Suite_telemetry.observe ~suite:"test_vision_swarm_adapter"
      ~passed:(!checks - !failures) ~failed:!failures ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_sop_execution; Stanza.hermes_harness_swarm_algebra ]);
  exit (Suite_telemetry.exit_code self)
