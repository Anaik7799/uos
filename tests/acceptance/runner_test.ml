#!/usr/bin/env -S opam exec -- ocaml
#use "./tests/acceptance/run.ml";;

let checks = ref 0
let check name condition =
  incr checks;
  if not condition then failwith ("runner test failed: " ^ name)

let field name fields = List.assoc name fields

let make_case case_id adapter expected_exit fixture expect =
  { case_id;
    given =
      `Assoc
        [ ("adapter", `String adapter); ("required", `Bool true);
          ("expected_exit", `Int expected_exit); ("fixture", `String fixture) ];
    actions = [ { op = "runner.verify" } ];
    expect }

let expected ~exit_code ~status ~passing_tests ~children_reaped =
  `Assoc
    [ ("exit_code", `Int exit_code); ("status", `String status);
      ("passing_tests", `Int passing_tests);
      ("children_reaped", `Bool children_reaped) ]

let test_e02_regression () =
  let execution =
    execute_case
      (make_case "E02-regression" "missing_adapter" 0 "temporary_isolated"
        (expected ~exit_code:2 ~status:"ERROR" ~passing_tests:0 ~children_reaped:true))
  in
  check "E02 assertion passes" execution.assertion_passed;
  check "E02 underlying adapter gets no pass" (not execution.observation.passed);
  check "E02 operation is supported" execution.observation.operation_supported;
  check "E02 missing adapter is distinct" (not execution.observation.adapter_registered);
  check "E02 underlying passing count zero" (execution.observation.passing_tests = 0)

let test_known_pass () =
  let execution =
    execute_case
      (make_case "known-pass" "runner.control.pass.v1" 0 "temporary_isolated"
        (expected ~exit_code:0 ~status:"PASS" ~passing_tests:1 ~children_reaped:true))
  in
  check "known pass assertion" execution.assertion_passed;
  check "known pass underlying" execution.observation.passed;
  check "known pass registered" execution.observation.adapter_registered;
  let mutated =
    dispatch_operation "runner.verify"
      (`Assoc
        [ ("adapter", `String "runner.control.pass.v1"); ("required", `Bool true);
          ("expected_exit", `Int 7); ("fixture", `String "temporary_isolated") ])
  in
  check "expected exit cannot manufacture observed exit" (mutated.exit_code = 0);
  check "expected exit is compared to observation" (not mutated.passed)

let test_deliberate_assertion_failure () =
  let execution =
    execute_case
      (make_case "assertion-failure" "runner.control.pass.v1" 0 "temporary_isolated"
        (expected ~exit_code:99 ~status:"PASS" ~passing_tests:1 ~children_reaped:true))
  in
  check "deliberate assertion is nonpassing" (not execution.assertion_passed);
  check "deliberate assertion reports exact path"
    (List.exists (fun item -> item.mismatch_path = "$.exit_code") execution.mismatches)

let control_observation adapter =
  dispatch_operation "runner.verify"
    (`Assoc
      [ ("adapter", `String adapter); ("required", `Bool true);
        ("expected_exit", `Int 0); ("fixture", `String "temporary_isolated") ])

let test_missing_executable () =
  let observation = control_observation "runner.control.missing-executable.v1" in
  check "missing executable registered" observation.adapter_registered;
  check "missing executable nonpassing" (not observation.passed);
  check "missing executable error" (observation.status = Status_error);
  check "missing executable executed" observation.executed;
  check "missing executable exit" (observation.exit_code = 127);
  check "missing executable cleanup proof" observation.children_reaped

let test_timeout () =
  let observation = control_observation "runner.control.timeout.v1" in
  check "timeout is named" observation.timed_out;
  check "timeout nonpassing" (not observation.passed);
  check "timeout no passing tests" (observation.passing_tests = 0);
  check "timeout cleanup proof follows supervisor" observation.children_reaped;
  check "timeout actual limit recorded"
    (observation.applied_limits.receipt_timeout_ms = 100)

let test_normal_exit_closed_descendant () =
  let observation = control_observation "runner.control.closed-descendant.v1" in
  check "closed descendant adapter executed" observation.executed;
  check "closed descendant exits zero" (observation.exit_code = 0);
  check "closed descendant cleanup proved" observation.children_reaped;
  check "closed descendant control passes" observation.passed

let test_output_quotas () =
  let stdout = control_observation "runner.control.stdout-overflow.v1" in
  check "stdout quota named" stdout.stdout_overflow;
  check "stdout quota bounded" (String.length stdout.stdout = 64);
  check "stdout quota nonpassing" (not stdout.passed);
  check "stdout quota cleanup proof" stdout.children_reaped;
  let stderr = control_observation "runner.control.stderr-overflow.v1" in
  check "stderr quota named" stderr.stderr_overflow;
  check "stderr quota bounded" (String.length stderr.stderr = 64);
  check "stderr quota nonpassing" (not stderr.passed);
  check "stderr quota cleanup proof" stderr.children_reaped

let test_real_signal_normalization () =
  let observation =
    dispatch_operation "runner.verify"
      (`Assoc
        [ ("adapter", `String "runner.control.signal-term.v1");
          ("required", `Bool true); ("expected_exit", `Int 143);
          ("fixture", `String "temporary_isolated") ])
  in
  check "real SIGTERM normalizes to shell status 143"
    (observation.exit_code = 143);
  check "real SIGTERM expected status passes" observation.passed;
  check "real SIGTERM descendants reaped" observation.children_reaped;
  check "real SIGTERM adapter registered" observation.adapter_registered;
  let limits = { default_process_limits with timeout_ms = 1_000 } in
  let real = run_bounded limits [ "/bin/sh"; "-c"; "exit 0" ] in
  let unknown =
    command_observation ~limits ~expected_exit:0
      { real with termination = Signaled 999 }
  in
  check "unknown signal normalization is rejected"
    (Result.is_error (termination_exit_code (Signaled 999)));
  check "unknown signal cannot pass" (not unknown.passed);
  check "unknown signal becomes explicit harness error"
    (unknown.exit_code = 2 && unknown.status = Status_error);
  check "unknown raw portable signal retained"
    (match unknown.data with
     | Some (`Assoc fields) ->
         List.assoc_opt "raw_portable_signal" fields = Some (`Int 999)
     | _ -> false)

let test_missing_fixture_and_skipped_required () =
  let missing_fixture =
    dispatch_operation "runner.verify"
      (`Assoc
        [ ("adapter", `String "runner.control.timeout.v1"); ("required", `Bool true);
          ("expected_exit", `Int 0); ("fixture", `String "not_registered") ])
  in
  check "missing fixture nonpassing" (not missing_fixture.passed);
  check "missing fixture did not execute" (not missing_fixture.executed);
  check "missing fixture adapter known" missing_fixture.adapter_registered;
  let skipped = control_observation "runner.control.not-registered.v1" in
  check "required adapter cannot skip to pass" (not skipped.passed);
  check "required skipped has zero passes" (skipped.passing_tests = 0);
  check "required skipped is unregistered" (not skipped.adapter_registered)

let test_unknown_operation_cannot_match_error () =
  let case =
    { case_id = "unknown-operation"; given = `Assoc [];
      actions = [ { op = "unknown.operation" } ];
      expect = `Assoc [ ("status", `String "ERROR"); ("exit_code", `Int 2) ] }
  in
  let execution = execute_case case in
  check "unknown operation status really errors"
    (execution.observation.status = Status_error);
  check "unknown operation expectation cannot confer pass"
    (not execution.assertion_passed);
  check "unknown operation marked unsupported"
    (not execution.observation.operation_supported);
  let empty_expect =
    execute_case
      { case_id = "empty-expect"; given =
          `Assoc [ ("adapter", `String "missing_adapter"); ("required", `Bool true);
                    ("expected_exit", `Int 0); ("fixture", `String "temporary_isolated") ];
        actions = [ { op = "runner.verify" } ]; expect = `Assoc [] }
  in
  check "empty expectation cannot pass supported negative"
    (not empty_expect.assertion_passed);
  check "empty expectation has named mismatch"
    (List.exists (fun item -> item.mismatch_path = "$.expect") empty_expect.mismatches)

let with_temp_manifest bytes f =
  let path = Filename.temp_file "uos-e02-manifest-" ".json" in
  let channel = open_out_bin path in
  output_string channel bytes;
  close_out channel;
  Fun.protect ~finally:(fun () -> try Unix.unlink path with Unix.Unix_error _ -> ())
    (fun () -> f path)

let test_malformed_inputs () =
  with_temp_manifest "{" (fun path ->
    let digest = sha256_string "{" in
    check "malformed manifest rejected after binding"
      (Result.is_error (load_acceptance_case ~expected_manifest_sha256:digest path "E02")));
  let wrong_type =
    "{\"tasks\":[{\"id\":\"E02\",\"acceptance_case\":"
    ^ "{\"id\":\"bad\",\"given\":{},\"when\":[{\"op\":2}],\"expect\":{}}}]}"
  in
  with_temp_manifest wrong_type (fun path ->
    check "wrong action type rejected"
      (Result.is_error
        (load_acceptance_case ~expected_manifest_sha256:(sha256_string wrong_type) path "E02")));
  let duplicate =
    "{\"tasks\":[{\"id\":\"E02\",\"id\":\"E02\",\"acceptance_case\":"
    ^ "{\"id\":\"bad\",\"given\":{},\"when\":[{\"op\":\"runner.verify\"}],\"expect\":{}}}]}"
  in
  with_temp_manifest duplicate (fun path ->
    check "duplicate task key rejected"
      (Result.is_error
        (load_acceptance_case ~expected_manifest_sha256:(sha256_string duplicate) path "E02")));
  let target = Filename.temp_file "uos-e02-target-" ".json" in
  let link = target ^ ".link" in
  Fun.protect
    ~finally:(fun () ->
      List.iter (fun path -> try Unix.unlink path with Unix.Unix_error _ -> ())
        [ link; target ])
    (fun () ->
      Unix.symlink target link;
      check "symlink input rejected before read"
        (Result.is_error (read_checked_file ~maximum:1024 link)));
  let fifo = Filename.temp_file "uos-e02-fifo-" ".pipe" in
  Unix.unlink fifo;
  Fun.protect
    ~finally:(fun () -> try Unix.unlink fifo with Unix.Unix_error _ -> ())
    (fun () ->
      Unix.mkfifo fifo 0o600;
      check "FIFO input rejected without blocking"
        (Result.is_error (read_checked_file ~maximum:1024 fifo)))

let canonical_manifest =
  "governance/planning/20260906-1655-uos-sa-plan-execution-manifest.json"

let test_source_and_revision_binding () =
  check "source manifest digest mismatch rejected"
    (Result.is_error
      (run_task ~emit_receipt:false ~expected_manifest_sha256:(String.make 64 '0')
        canonical_manifest "E02"));
  check "candidate revision mismatch rejected"
    (Result.is_error
      (run_task ~emit_receipt:false ~expected_candidate_commit:(String.make 40 '0')
        canonical_manifest "E02"));
  let path = Filename.temp_file "uos-e02-binding-" ".ml" in
  Fun.protect
    ~finally:(fun () -> try Unix.unlink path with Unix.Unix_error _ -> ())
    (fun () ->
      let write bytes =
        let channel = open_out_bin path in
        output_string channel bytes;
        close_out channel
      in
      write "before";
      let before =
        match read_checked_file ~maximum:1024 path with
        | Ok checked -> [ checked.checked_binding ]
        | Error message -> failwith message
      in
      write "after";
      let after =
        match read_checked_file ~maximum:1024 path with
        | Ok checked -> [ checked.checked_binding ]
        | Error message -> failwith message
      in
      check "source mutation invalidates binding"
        (not (binding_sets_equal before after)))

let test_atomic_receipt () =
  let directory =
    Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "uos-e02-receipts-%d" (Unix.getpid ()))
  in
  Fun.protect
    ~finally:(fun () ->
      if Sys.file_exists directory then begin
        Array.iter
          (fun name -> try Unix.unlink (Filename.concat directory name)
                       with Unix.Unix_error _ -> ())
          (Sys.readdir directory);
        try Unix.rmdir directory with Unix.Unix_error _ -> ()
      end)
    (fun () ->
      match run_task ~receipt_dir:directory canonical_manifest "E02" with
      | Error message -> failwith ("atomic receipt setup failed: " ^ message)
      | Ok result ->
          check "atomic receipt assertion" result.execution.assertion_passed;
          let path = Option.get result.receipt_path in
          check "timestamped receipt name"
            (String.length (Filename.basename path) > 14
             && (Filename.basename path).[8] = '-');
          let files = Sys.readdir directory |> Array.to_list in
          check "no temporary receipt files"
            (List.for_all (fun name -> not (String.ends_with ~suffix:".tmp" name)
                                       && not (String.ends_with ~suffix:".calibration" name)) files);
          match read_regular_bounded ~maximum:1_048_576 path with
          | Error message -> failwith message
          | Ok bytes ->
              match parse_json_strict bytes with
              | Error error -> failwith (string_of_contract_error error)
              | Ok json ->
                  check "receipt schema version"
                    (Yojson.Basic.Util.member "schema" json |> Yojson.Basic.Util.to_string
                     = "uos.acceptance-receipt.v3");
                  let states = Yojson.Basic.Util.member "states" json in
                  check "underlying pass remains false"
                    (not (Yojson.Basic.Util.member "passed" states |> Yojson.Basic.Util.to_bool));
                  check "assertion pass recorded separately"
                    (Yojson.Basic.Util.member "assertion" json
                     |> Yojson.Basic.Util.member "passed" |> Yojson.Basic.Util.to_bool);
                  check "no-process limits are recorded"
                    (result.receipt.limits = no_process_limits);
                  check "all production inputs are bound"
                    (List.length result.receipt.sources = List.length bound_source_paths);
                  check "atomic write calibration measured"
                    (result.receipt.receipt_write_calibration_ms > 0.);
                  match run_task ~receipt_dir:directory canonical_manifest "E02" with
                  | Error message -> failwith message
                  | Ok second ->
                      check "invocation nonce prevents receipt overwrite"
                        (second.receipt_path <> result.receipt_path))

let tests =
  [ test_e02_regression; test_known_pass; test_deliberate_assertion_failure;
    test_missing_executable; test_timeout; test_normal_exit_closed_descendant;
    test_output_quotas; test_real_signal_normalization;
    test_missing_fixture_and_skipped_required;
    test_unknown_operation_cannot_match_error; test_malformed_inputs;
    test_source_and_revision_binding; test_atomic_receipt ]

let () =
  List.iter (fun test -> test ()) tests;
  Printf.printf "runner_test: %d checks passed\n" !checks
