let checks = ref 0
let failures = ref 0

let check name condition =
  incr checks;
  if not condition then begin
    incr failures;
    Printf.eprintf "FAIL: %s\n" name
  end

let expect_error name = function Ok _ -> check name false | Error _ -> check name true

let provenance : Run_model.provenance =
  { source_revision = "80f93278"; source_clean = true;
    configuration_digest = String.make 64 'a'; authority_digest = String.make 64 'b';
    executable_digest = String.make 64 'c' }

let coordinate : Ops_capability.coordinate =
  { level = Ops_capability.L2; phase = Ops_capability.Observe }

let make ?(sequence = 0L) ?(event_id = "event-0") ?(kind = Run_model.Run_declared)
    ?(subject = Run_model.Run) ?(payload = `Assoc [ ("intent", `String "verify") ])
    ?previous_digest ?(provenance = provenance) () =
  Run_model.make ~run_id:"run-1" ~sequence ~event_id ~kind ~subject
    ~plane:Ops_capability.Control_plane ~coordinate
    ~rca_origin:Ops_capability.Control ~occurred_at_ns:100L
    ~monotonic_at_ns:50L ~provenance ~payload ~previous_digest

let event_exn result = match result with Ok event -> event | Error error -> failwith error

let replace_field name value = function
  | `Assoc fields -> `Assoc (List.map (fun (key, old) -> if key = name then (key, value) else (key, old)) fields)
  | json -> json

let () =
  Printf.printf "[unit] run-event codec and validation\n";
  let event = event_exn (make ()) in
  check "codec round-trip is canonical"
    (match Run_model.of_json (Run_model.to_json event) with
     | Ok decoded -> Yojson.Safe.to_string (Run_model.to_json decoded)
                     = Yojson.Safe.to_string (Run_model.to_json event)
     | Error _ -> false);
  check "digest is recomputed over every authored value"
    (String.length event.digest = 64 && event.digest = Run_model.digest event);
  let payload_left =
    `Assoc [ ("z", `Int 1); ("nested", `Assoc [ ("b", `Int 2); ("a", `Int 1) ]);
             ("array", `List [ `Assoc [ ("d", `Int 4); ("c", `Int 3) ]; `Int 7 ]) ]
  in
  let payload_right =
    `Assoc [ ("array", `List [ `Assoc [ ("c", `Int 3); ("d", `Int 4) ]; `Int 7 ]);
             ("nested", `Assoc [ ("a", `Int 1); ("b", `Int 2) ]); ("z", `Int 1) ]
  in
  let left = event_exn (make ~payload:payload_left ()) in
  let right = event_exn (make ~payload:payload_right ()) in
  check "canonicalization sorts objects recursively and preserves arrays" (left.digest = right.digest);
  let swapped_array =
    `Assoc [ ("z", `Int 1); ("nested", `Assoc [ ("a", `Int 1); ("b", `Int 2) ]);
             ("array", `List [ `Int 7; `Assoc [ ("c", `Int 3); ("d", `Int 4) ] ]) ]
  in
  check "array order remains digest-significant"
    (left.digest <> (event_exn (make ~payload:swapped_array ())).digest);
  expect_error "empty provenance digest is rejected"
    (make ~provenance:{ provenance with authority_digest = "" } ());
  expect_error "negative sequence is rejected" (make ~sequence:(-1L) ());
  expect_error "non-canonical integer literal is rejected"
    (make ~payload:(`Assoc [ ("integer", `Intlit "01") ]) ());
  expect_error "negative zero integer literal is rejected"
    (make ~payload:(`Assoc [ ("integer", `Intlit "-0") ]) ());
  let tampered = Run_model.to_json event |> replace_field "digest" (`String (String.make 64 '0')) in
  expect_error "decoded digest is recomputed and tampering is rejected" (Run_model.of_json tampered);
  let unknown =
    match Run_model.to_json event with `Assoc fields -> `Assoc (("unknown", `Null) :: fields) | json -> json
  in
  expect_error "unknown event field is rejected" (Run_model.of_json unknown);
  let missing =
    match Run_model.to_json event with `Assoc fields -> `Assoc (List.remove_assoc "event_id" fields) | json -> json
  in
  expect_error "missing event field is rejected" (Run_model.of_json missing);
  let duplicate =
    match Run_model.to_json event with `Assoc fields -> `Assoc (("run_id", `String "shadow") :: fields) | json -> json
  in
  expect_error "duplicate event field is rejected" (Run_model.of_json duplicate);
  let bad_kind = Run_model.to_json event |> replace_field "kind" (`String "invented") in
  expect_error "invalid closed enum is rejected" (Run_model.of_json bad_kind);
  let nested_duplicate =
    make ~payload:(`Assoc [ ("outer", `Assoc [ ("x", `Int 1); ("x", `Int 2) ]) ]) ()
  in
  expect_error "duplicate fields in authored payload are rejected" nested_duplicate;

  Printf.printf "[feature] complete closed carrier\n";
  let phases =
    [ Run_model.Admission; Authority_preflight; Discovery; Build; Dispatch;
      Suite_execution; Aggregation; Completion_admission; Publication ]
  in
  let subjects =
    Run_model.Run
    :: List.map (fun p -> Run_model.Phase p) phases
    @ [ Suite "suite"; Attempt ("attempt", 2); Resource "cpu"; Safety_gate "stpa";
        Intelligence_gate "raven"; Analysis "ruliad"; Trace_span "span";
        Profile "heap"; Command "verify"; Receipt "receipt"; Residual "residual" ]
  in
  List.iteri
    (fun index subject ->
      let candidate = event_exn (make ~event_id:("subject-" ^ string_of_int index) ~subject ()) in
      check ("subject round-trip " ^ string_of_int index)
        (match Run_model.of_json (Run_model.to_json candidate) with Ok _ -> true | Error _ -> false))
    subjects;
  let kinds =
    [ Run_model.Run_declared; Run_started; Run_finished; Phase_started; Phase_finished;
      Suite_discovered; Suite_started; Suite_finished; Swarm_step_ready;
      Swarm_step_running; Swarm_step_terminal; Resource_sampled; Diagnostic_emitted;
      Safety_evaluated; Intelligence_evaluated; Analysis_recorded; Trace_recorded;
      Profile_recorded; Fast_path_selected; Command_observed; Receipt_admitted;
      Residual_recorded; Heartbeat ]
  in
  List.iteri
    (fun index kind ->
      let candidate = event_exn (make ~event_id:("kind-" ^ string_of_int index) ~kind ()) in
      check ("event-kind round-trip " ^ string_of_int index)
        (match Run_model.of_json (Run_model.to_json candidate) with Ok _ -> true | Error _ -> false))
    kinds;

  Printf.printf "[property] seeded canonical permutation repetition\n";
  let random = Random.State.make [| 0x484552; 0x4d4553 |] in
  for index = 0 to 499 do
    let a = Random.State.int random 100_000 in
    let b = Random.State.int random 100_000 in
    let p1 = `Assoc [ ("b", `Int b); ("a", `Int a) ] in
    let p2 = `Assoc [ ("a", `Int a); ("b", `Int b) ] in
    let e1 = event_exn (make ~event_id:("property-" ^ string_of_int index) ~payload:p1 ()) in
    let e2 = event_exn (make ~event_id:("property-" ^ string_of_int index) ~payload:p2 ()) in
    check ("canonical property " ^ string_of_int index) (e1.digest = e2.digest)
  done;
  Printf.printf "run_model: %d checks, %d failures\n" !checks !failures;
  let self =
    Suite_telemetry.observe ~suite:"test_run_model"
      ~passed:(!checks - !failures) ~failed:!failures ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code self)
