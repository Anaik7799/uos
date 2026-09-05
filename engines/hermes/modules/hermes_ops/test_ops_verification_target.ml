open Ops_verification_target

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.printf "FAILED: %s\n" name
  end

let result_or_fail label = function
  | Ok value -> value
  | Error _ -> failwith label

let sha256 text =
  text |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let canonical json = result_or_fail "canonical request" (Run_model.canonical_string json)

let string_of_effect_kind = Run_topology.effect_kind_id

let canonical_activity =
  result_or_fail "admit repository activity"
    (Run_topology.admit_activity ~stable_id:"activity.verify-repository")

let canonical_actions = Run_topology.admitted_actions canonical_activity

let build_action =
  match List.find_opt
      (fun (action : Run_topology.declarative_action) ->
        match action.work with Run_topology.Repository_build _ -> true
        | _ -> false)
      canonical_actions with
  | Some action -> action
  | None -> failwith "repository activity has no build action"

let suite_action =
  match List.find_opt
      (fun (action : Run_topology.declarative_action) ->
        match action.work with
        | Run_topology.Repository_verification_suite _ -> true
        | _ -> false)
      canonical_actions with
  | Some action -> action
  | None -> failwith "repository activity has no suite action"

type request_mutation =
  | Exact
  | Action_id of string
  | Action_digest of string
  | Command_id of string
  | Preparation_id of string
  | Target_component_id of string
  | Effect_kind of string
  | Version of string

let request_bytes ?(mutation = Exact)
    (action : Run_topology.declarative_action) =
  let action_id =
    match mutation with Action_id value -> value | _ -> action.stable_id in
  let action_digest =
    match mutation with
    | Action_digest value -> value
    | _ -> Run_topology.action_digest_of action
  in
  let command_id =
    match mutation with Command_id value -> value | _ -> action.command_id in
  let preparation_id =
    match mutation with
    | Preparation_id value -> value
    | _ -> action.preparation_id
  in
  let target_component_id =
    match mutation with
    | Target_component_id value -> value
    | _ -> action.target_component_id
  in
  let effect_kind =
    match mutation with
    | Effect_kind value -> value
    | _ -> string_of_effect_kind action.effect_kind
  in
  let version =
    match mutation with Version value -> value | _ -> "run-swarm-preparation-v3"
  in
  let work_fields = match action.work with
    | Run_topology.Repository_build { profile; build_command } ->
        [ ("work_kind", `String "repository-build");
          ("profile_id", `String
             (match profile with Verification_fast -> "fast"
             | Verification_full -> "full"));
          ("build_command", `String build_command) ]
    | Repository_verification_suite { profile; suite_id; executable } ->
        [ ("work_kind", `String "repository-verification-suite");
          ("profile_id", `String
             (match profile with Verification_fast -> "fast"
             | Verification_full -> "full"));
          ("suite_id", `String suite_id); ("executable", `String executable) ]
    | work ->
        [ ("work_kind", `String "closed-task7a-work");
          ("work_id", `String (Run_topology.action_work_id work)) ]
  in
  canonical
    (`Assoc
      ([ ("activity_id", `String
            (Run_topology.admitted_declaration canonical_activity).stable_id);
        ("activity_digest", `String
           (Run_topology.admitted_activity_digest canonical_activity));
        ("topology_authority_digest", `String
           (Run_topology.admitted_activity_authority_digest canonical_activity));
        ("action_id", `String action_id);
        ("assigned_agent_id", `String action.assigned_agent_id);
        ("command_id", `String command_id);
        ("dependency_ids",
         `List (List.map (fun value -> `String value) action.dependency_ids));
        ("dependency_input_digest", `String (String.make 64 'd'));
        ("execution_identity", `String (String.make 64 'e'));
        ("action_digest", `String action_digest);
        ("preparation_id", `String preparation_id);
        ("target_component_id", `String target_component_id);
        ("effect_kind", `String effect_kind);
        ("version", `String version) ] @ work_fields))

let effect_request ?mutation (action : Run_topology.declarative_action) =
  result_or_fail "make effect request"
    (Run_effect_authority.make_request
       ~effect_kind:Run_topology.Verification_suite_execution
       ~request_bytes:(request_bytes ?mutation action))

let coordinate =
  { Ops_capability.level = Ops_capability.L2; phase = Ops_capability.Act }

let fixture_or_fail label = function
  | Ok value -> value
  | Error issue ->
      failwith
        (label ^ ": "
         ^ Dependability_sqlite_test_protocol.string_of_error issue)

let with_location body =
  let registry =
    fixture_or_fail "create SQLite fixture registry"
      (Dependability_sqlite_test_protocol.create ~maximum_live:1)
  in
  let registry, lease =
    fixture_or_fail "acquire in-memory SQLite fixture"
      (Dependability_sqlite_test_protocol.acquire registry
         Dependability_sqlite_test_protocol.In_memory)
  in
  let location =
    fixture_or_fail "resolve opaque SQLite fixture reference"
      (Dependability_sqlite_test_protocol.reference registry lease)
  in
  Fun.protect
    ~finally:(fun () ->
      let registry, _ =
        fixture_or_fail "release SQLite fixture lease"
          (Dependability_sqlite_test_protocol.release registry lease)
      in
      ignore
        (fixture_or_fail "clean SQLite fixture registry"
           (Dependability_sqlite_test_protocol.cleanup registry)))
    (fun () -> body location)

let with_database body =
  with_location (fun location ->
    let database =
      result_or_fail "open effect database"
        (Dependability_sqlite.open_database ~location ~maximum_total_attempts:1)
    in
    Fun.protect
      ~finally:(fun () ->
        ignore (Dependability_sqlite.For_test.dispose database))
      (fun () -> body database))

let with_interpreter registration body =
  with_database (fun database ->
    let interpreter =
      result_or_fail "open admitted verification interpreter"
        (Run_effect_authority.open_admitted_interpreter ~database
           ~registry:(target_registry registration) ~coordinate)
    in
    Fun.protect
      ~finally:(fun () -> Run_effect_authority.close interpreter)
      (fun () -> body interpreter))

let is_request_refusal = function
  | Error _ -> true
  | Ok _ -> false

let apply interpreter ~key ?mutation
    (action : Run_topology.declarative_action) =
  Run_effect_authority.apply_once interpreter ~idempotency_key:key
    (effect_request ?mutation action)

let exact_build_work = function
  | Run_topology.Repository_build
      { profile = Run_topology.Verification_full;
        build_command = "dune build --pkg=disabled 2>&1" } -> true
  | _ -> false

let exact_suite_work (expected : Run_topology.declarative_action) = function
  | Run_topology.Repository_verification_suite
      { profile = Run_topology.Verification_full; suite_id; executable } ->
      begin match expected.Run_topology.work with
      | Run_topology.Repository_verification_suite expected_work ->
          String.equal suite_id expected_work.suite_id
          && String.equal executable expected_work.executable
      | _ -> false
      end
  | _ -> false

let status_of_receipt registration receipt =
  match observation_of_receipt registration receipt with
  | Ok observation ->
      Some
        (observation.status, observation.availability, observation.exit_code,
         observation.output, observation.output_bytes,
         observation.output_digest, observation.output_truncated)
  | Error _ -> None

let registry_or_fail run_capture =
  result_or_fail "register verification target"
    (make_registry ~activity:canonical_activity ~run_capture)

let () =
  Printf.printf "[tdd] closed repository verification target\n";
  let sqlite_activity =
    result_or_fail "admit sqlite activity"
      (Run_topology.admit_activity
         ~stable_id:"activity.verify-sqlite-dependability")
  in
  check "V01 foreign admitted activity cannot register the repository target"
    (Result.is_error
       (make_registry ~activity:sqlite_activity
          ~run_capture:(fun _ -> Executed { exit_code = 0; output = "" })));

  let baseline_calls = ref [] in
  let baseline_registry =
    registry_or_fail (fun work ->
      baseline_calls := work :: !baseline_calls;
      Executed { exit_code = 0; output = "build ok" })
  in
  with_interpreter baseline_registry (fun interpreter ->
    let result = apply interpreter ~key:"verification-build-pass" build_action in
    check "V02 exact prepared build executes only the typed Repository_build"
      (match result, !baseline_calls with
       | Ok receipt, [ work ] ->
           let foreign_registration =
             registry_or_fail (fun _ ->
               Executed { exit_code = 0; output = "foreign" })
           in
           exact_build_work work
           && begin match status_of_receipt baseline_registry receipt with
              | Some (Passed, Available, Some 0, "build ok", 8, digest, false) ->
                  String.equal digest (sha256 "build ok")
                  && Result.is_error
                       (observation_of_receipt foreign_registration receipt)
              | _ -> false
              end
       | _ -> false));

  let suite_calls = ref [] in
  let suite_registry =
    registry_or_fail (fun work ->
      suite_calls := work :: !suite_calls;
      Executed { exit_code = 0; output = "219 checks" })
  in
  with_interpreter suite_registry (fun interpreter ->
    let result = apply interpreter ~key:"verification-suite-pass" suite_action in
    check
      "V03 exact prepared suite retains canonical profile executable and digest"
      (match result, !suite_calls with
       | Ok receipt, [ work ] ->
           exact_suite_work suite_action work
           && begin match status_of_receipt suite_registry receipt with
              | Some (Passed, Available, Some 0, "219 checks", 10, digest, false) ->
                  String.equal digest (sha256 "219 checks")
              | _ -> false
              end
       | _ -> false));

  let mutation_cases =
    [ ("V04 action substitution", Action_id suite_action.stable_id);
      ("V05 action digest substitution", Action_digest (String.make 64 'a'));
      ("V06 command substitution", Command_id "InvokeAnything");
      ("V07 preparation substitution", Preparation_id "prepare.foreign");
      ("V08 target substitution", Target_component_id "foreignWorker");
      ("V09 effect substitution", Effect_kind "durable-artifact-publication");
      ("V10 version substitution", Version "run-swarm-preparation-v2") ]
  in
  List.iteri
    (fun index (name, mutation) ->
      let calls = ref 0 in
      let registry =
        registry_or_fail (fun _ ->
          incr calls; Executed { exit_code = 0; output = "must not run" })
      in
      with_interpreter registry (fun interpreter ->
        check name
          (is_request_refusal
             (apply interpreter
                ~key:(Printf.sprintf "verification-mutant-%d" index)
                ~mutation build_action)
           && !calls = 0)))
    mutation_cases;

  let nonzero_registry =
    registry_or_fail (fun _ ->
      Executed { exit_code = 23; output = "suite failed loudly" })
  in
  with_interpreter nonzero_registry (fun interpreter ->
    check "V11 nonzero execution is a Failed observation and never green"
      (match apply interpreter ~key:"verification-nonzero" suite_action with
       | Ok receipt ->
           begin match status_of_receipt nonzero_registry receipt with
           | Some (Failed, Available, Some 23, "suite failed loudly", 19,
                   digest, false) ->
               String.equal digest (sha256 "suite failed loudly")
           | _ -> false
           end
       | Error _ -> false));

  let absent_registry =
    registry_or_fail (fun work ->
      match work with
      | Run_topology.Repository_verification_suite { executable; _ } ->
          Executable_unavailable { executable; reason = "not built" }
      | _ -> Executable_unavailable { executable = "dune"; reason = "absent" })
  in
  with_interpreter absent_registry (fun interpreter ->
    check "V12 absent executable is Skipped/Unavailable and never green"
      (match apply interpreter ~key:"verification-absent" suite_action with
       | Ok receipt ->
           begin match status_of_receipt absent_registry receipt with
           | Some (Skipped, Unavailable, None, "not built", 9, digest, false) ->
               String.equal digest (sha256 "not built")
           | _ -> false
           end
       | Error _ -> false));

  let query_calls = ref 0 in
  let query_registry =
    registry_or_fail (fun _ ->
      incr query_calls; Executed { exit_code = 0; output = "stable" })
  in
  with_interpreter query_registry (fun interpreter ->
    let key = "verification-query-replay" in
    let first = apply interpreter ~key build_action in
    let queried = Run_effect_authority.query interpreter ~idempotency_key:key in
    let replay = apply interpreter ~key build_action in
    check
      "V13 query-after-apply and duplicate delivery reconcile one exact receipt"
      (match first, queried, replay with
       | Ok first_receipt,
         Ok (Some (Run_effect_authority.Applied queried_receipt)),
         Ok replay_receipt ->
           !query_calls = 1
           && String.equal first_receipt.receipt_digest queried_receipt.receipt_digest
           && String.equal first_receipt.receipt_digest replay_receipt.receipt_digest
       | _ -> false));

  let oversized = String.make (maximum_observation_output_bytes + 73) 'x' in
  let oversized_registry =
    registry_or_fail (fun _ -> Executed { exit_code = 9; output = oversized })
  in
  with_interpreter oversized_registry (fun interpreter ->
    check "V14 oversized output is bounded while full bytes and digest remain bound"
      (match apply interpreter ~key:"verification-oversized" suite_action with
       | Ok receipt ->
           begin match status_of_receipt oversized_registry receipt with
           | Some (Failed, Available, Some 9, output, output_bytes, digest, true) ->
               String.length output = maximum_observation_output_bytes
               && output_bytes = String.length oversized
               && String.equal digest (sha256 oversized)
           | _ -> false
           end
       | Error _ -> false));

  Printf.printf "ops_verification_target: %d passed, %d failed\n"
    !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_ops_verification_target"
      ~passed:!passed ~failed:!failed ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self
       ~targets:[ Stanza.hermes_ops; Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code self)
