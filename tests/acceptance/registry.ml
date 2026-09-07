#use "topfind";;
#require "yojson";;

#use "./tests/acceptance/contract.ml";;
#use "./tests/acceptance/process_supervisor.ml";;

(** Typed, allowlisted production adapter registry for acceptance operations.
    Expected observations are deliberately absent from every adapter interface. *)

let default_process_limits =
  { timeout_ms = 120_000; stdout_limit = 131_072; stderr_limit = 65_536;
    term_grace_ms = 100 }

let error_observation ?(operation_supported = true) ?(adapter_registered = false)
    ?(built = true) ?(executed = true) ?(children_reaped = true) ?(exit_code = 2)
    message =
  { operation_supported; adapter_registered; built; executed; passed = false;
    exit_code; status = Status_error; passing_tests = 0; children_reaped;
    timed_out = false; stdout_overflow = false; stderr_overflow = false;
    stdout = ""; stderr = message; duration_ms = 0.; data = None;
    applied_limits = no_process_limits }

let fail_observation ?(operation_supported = true) ?(adapter_registered = true)
    ?(built = true) ?(executed = true) ?(children_reaped = true) ?(exit_code = 1)
    message =
  { operation_supported; adapter_registered; built; executed; passed = false;
    exit_code; status = Status_fail; passing_tests = 0; children_reaped;
    timed_out = false; stdout_overflow = false; stderr_overflow = false;
    stdout = ""; stderr = message; duration_ms = 0.; data = None;
    applied_limits = no_process_limits }

let termination_exit_code = function
  | Exited code -> Ok code
  | Signaled signal ->
      if Sys.os_type <> "Unix" || not (Sys.file_exists "/proc/self/stat") then
        Error "signal normalization is supported only on Linux"
      else
        let linux_signal = Sys.signal_to_int signal in
        if linux_signal < 1 || linux_signal > 64 then
          Error
            (Printf.sprintf
               "unmapped Linux signal: portable=%d converted=%d"
               signal linux_signal)
        else Ok (128 + linux_signal)
  | Timed_out -> Ok 124
  | Output_limit -> Ok 125

let receipt_limits_of_process limits =
  { receipt_timeout_ms = limits.timeout_ms;
    receipt_stdout_bytes = limits.stdout_limit;
    receipt_stderr_bytes = limits.stderr_limit;
    receipt_term_grace_ms = limits.term_grace_ms }

let command_observation ~limits ~expected_exit result =
  match termination_exit_code result.termination with
  | Error normalization_error ->
      let raw_signal =
        match result.termination with Signaled signal -> `Int signal | _ -> `Null
      in
      { operation_supported = true; adapter_registered = true; built = true;
        executed = true; passed = false; exit_code = 2; status = Status_error;
        passing_tests = 0; children_reaped = result.children_reaped;
        timed_out = false; stdout_overflow = result.stdout_truncated;
        stderr_overflow = result.stderr_truncated; stdout = result.stdout;
        stderr = normalization_error; duration_ms = result.duration_ms;
        data =
          Some
            (`Assoc
              [ ("termination", `String "UNMAPPED_SIGNAL");
                ("raw_portable_signal", raw_signal);
                ("normalization_error", `String normalization_error) ]);
        applied_limits = receipt_limits_of_process limits }
  | Ok code ->
      let timed_out = result.termination = Timed_out in
      let output_limit = result.termination = Output_limit in
      let process_terminated =
        match result.termination with Exited _ | Signaled _ -> true | _ -> false
      in
      let succeeded =
        process_terminated
        && code = expected_exit
        && not result.stdout_truncated
        && not result.stderr_truncated
        && result.children_reaped
      in
      { operation_supported = true; adapter_registered = true; built = true;
        executed = true; passed = succeeded; exit_code = code;
        status =
          (if succeeded then Status_pass
           else if timed_out || output_limit || code = 127
           then Status_error else Status_fail);
        passing_tests = (if succeeded then 1 else 0);
        children_reaped = result.children_reaped; timed_out;
        stdout_overflow = result.stdout_truncated;
        stderr_overflow = result.stderr_truncated;
        stdout = result.stdout; stderr = result.stderr;
        duration_ms = result.duration_ms; data = None;
        applied_limits = receipt_limits_of_process limits }

type command_id =
  | Candidate_snapshot_command
  | Compiler_diagnostics_command
  | Missing_executable_control
  | Timeout_control
  | Stdout_overflow_control
  | Stderr_overflow_control
  | Closed_descendant_control
  | Signal_term_control

let command_argv = function
  | Candidate_snapshot_command -> [ "opam" ]
  | Compiler_diagnostics_command -> [ "ocaml"; "tests/acceptance/compiler_diagnostics.ml" ]
  | Missing_executable_control -> [ "/definitely/missing/uos-acceptance-command" ]
  | Timeout_control -> [ "/bin/sh"; "-c"; "sleep 30" ]
  | Stdout_overflow_control -> [ "/bin/sh"; "-c"; "head -c 4096 /dev/zero" ]
  | Stderr_overflow_control -> [ "/bin/sh"; "-c"; "head -c 4096 /dev/zero >&2" ]
  | Closed_descendant_control ->
      [ "/bin/sh"; "-c"; "(exec 1>&- 2>&-; sleep 30) & exit 0" ]
  | Signal_term_control -> [ "/bin/sh"; "-c"; "kill -TERM $$" ]

let command_dependencies = function
  | Candidate_snapshot_command -> [ "opam"; "ocaml"; "jj"; "chronyc"; "curl" ]
  | Compiler_diagnostics_command -> [ "ocaml"; "gleam"; "erl" ]
  | Missing_executable_control -> []
  | Timeout_control | Closed_descendant_control -> [ "/bin/sh"; "sleep" ]
  | Signal_term_control -> [ "/bin/sh" ]
  | Stdout_overflow_control | Stderr_overflow_control -> [ "/bin/sh"; "head" ]

let allowed_dependencies =
  [ "opam"; "ocaml"; "jj"; "chronyc"; "curl"; "/bin/sh"; "sleep"; "head"; "gleam"; "erl" ]

let command_allowed id =
  let argv = command_argv id in
  let executable_allowed =
    match argv with
    | "opam" :: _ | "ocaml" :: _ | "/bin/sh" :: _ | "/definitely/missing/uos-acceptance-command" :: _ -> true
    | _ -> false
  in
  executable_allowed
  && List.for_all (fun dependency -> List.mem dependency allowed_dependencies)
       (command_dependencies id)

let run_command ?(limits = default_process_limits) ~expected_exit id =
  if not (command_allowed id) then
    error_observation ~adapter_registered:true ~executed:false
      "command or dependency is outside the registry allowlist"
  else
    run_bounded limits (command_argv id)
    |> command_observation ~limits ~expected_exit

type runner_adapter =
  | Internal_pass
  | Command_control of command_id * process_limits

let runner_adapters =
  [ ("runner.control.pass.v1", Internal_pass);
    ("runner.control.missing-executable.v1",
      Command_control (Missing_executable_control, { default_process_limits with timeout_ms = 1_000 }));
    ("runner.control.timeout.v1",
      Command_control (Timeout_control, { default_process_limits with timeout_ms = 100 }));
    ("runner.control.stdout-overflow.v1",
      Command_control (Stdout_overflow_control,
        { default_process_limits with timeout_ms = 1_000; stdout_limit = 64 }));
    ("runner.control.stderr-overflow.v1",
      Command_control (Stderr_overflow_control,
        { default_process_limits with timeout_ms = 1_000; stderr_limit = 64 }));
    ("runner.control.closed-descendant.v1",
      Command_control (Closed_descendant_control,
        { default_process_limits with timeout_ms = 1_000 }));
    ("runner.control.signal-term.v1",
      Command_control (Signal_term_control,
        { default_process_limits with timeout_ms = 1_000 })) ]

let dispatch_runner_adapter fixture =
  match List.assoc_opt fixture.adapter runner_adapters with
  | None ->
      error_observation
        (Printf.sprintf "required=%b: adapter is not registered: %s"
           fixture.required fixture.adapter)
  | Some _ when fixture.fixture <> "temporary_isolated" ->
      error_observation ~adapter_registered:true ~executed:false
        ("fixture is not registered: " ^ fixture.fixture)
  | Some Internal_pass ->
      let measured_exit = 0 in
      let succeeded = measured_exit = fixture.expected_exit in
      { operation_supported = true; adapter_registered = true; built = true;
        executed = true; passed = succeeded; exit_code = measured_exit;
        status = (if succeeded then Status_pass else Status_fail);
        passing_tests = (if succeeded then 1 else 0); children_reaped = true;
        timed_out = false; stdout_overflow = false; stderr_overflow = false;
        stdout = "runner control measured exit 0"; stderr = ""; duration_ms = 0.;
        data = None; applied_limits = no_process_limits }
  | Some (Command_control (command, limits)) ->
      run_command ~limits ~expected_exit:fixture.expected_exit command

let runner_verify given =
  match decode_runner_fixture given with
  | Error error ->
      error_observation ~executed:false (string_of_contract_error error)
  | Ok fixture -> dispatch_runner_adapter fixture

let decode_candidate_fixture json =
  let path = "$.given" in
  match first_duplicate_or_nested path json with
  | Error _ as error -> error
  | Ok () ->
      match assoc_at path json with
      | Error _ as error -> error
      | Ok fields ->
          match exact_fields path
                  [ "candidate"; "evidence_candidate"; "source_mode";
                    "clock_source"; "inherited_claim" ] fields with
          | Error _ as error -> error
          | Ok () ->
              let get name = required_field path name fields string_at in
              match get "candidate", get "evidence_candidate", get "source_mode",
                    get "clock_source", get "inherited_claim" with
              | Ok candidate, Ok evidence_candidate, Ok source_mode,
                Ok clock_source, Ok inherited_claim ->
                  Ok (candidate, evidence_candidate, source_mode, clock_source, inherited_claim)
              | Error error, _, _, _, _ | _, Error error, _, _, _
              | _, _, Error error, _, _ | _, _, _, Error error, _
              | _, _, _, _, Error error -> Error error

let candidate_projection raw =
  try
    let json = Yojson.Basic.from_string raw in
    match json with
    | `Assoc fields ->
        let required name = List.assoc name fields in
        let observed_record_names =
          match required "records" with
          | `Assoc records -> List.map fst records
          | _ -> raise Exit
        in
        let projected_record_names =
          [ "change_id"; "commit_id"; "dirty_manifest"; "served_build";
            "tool_versions"; "clock_receipt" ]
        in
        if not
             (List.for_all
                (fun name -> List.mem name observed_record_names)
                projected_record_names)
        then raise Exit;
        Ok (`Assoc
          [ ("inherited_credit", required "inherited_credit");
            ("source_writes", required "source_writes");
            ("records",
              `List
                (List.map (fun name -> `String name) projected_record_names));
            ("signature_credit", required "signature_credit") ])
    | _ -> Error "candidate snapshot output is not an object"
  with
  | Yojson.Json_error message -> Error ("candidate snapshot emitted malformed JSON: " ^ message)
  | Not_found | Exit -> Error "candidate snapshot output lacks required fields"

let candidate_snapshot given =
  match decode_candidate_fixture given with
  | Error error -> error_observation ~executed:false (string_of_contract_error error)
  | Ok (candidate, evidence_candidate, source_mode, clock_source, inherited_claim) ->
      let command =
        [ "opam"; "exec"; "--"; "ocaml"; "tools/verification/candidate_snapshot.ml";
          "snapshot"; "--candidate"; candidate; "--evidence-candidate"; evidence_candidate;
          "--source-mode"; source_mode; "--clock-source"; clock_source;
          "--inherited-claim"; inherited_claim; "--served-url";
          "http://127.0.0.1:9/unavailable" ]
      in
      let base =
        if not (command_allowed Candidate_snapshot_command) then
          error_observation ~adapter_registered:true ~executed:false
            "candidate snapshot dependencies are outside the allowlist"
        else
          run_bounded default_process_limits command
          |> command_observation ~limits:default_process_limits ~expected_exit:0
      in
      if base.exit_code <> 0 || base.timed_out || base.stdout_overflow
         || base.stderr_overflow
      then base
      else
        match candidate_projection base.stdout with
        | Error message -> { base with passed = false; status = Status_error;
                                       passing_tests = 0; stderr = message; data = None }
        | Ok projection -> { base with data = Some projection }

let compiler_check_affected_tests given =
  match first_duplicate_or_nested "$.given" given with
  | Error e -> error_observation ~executed:false (string_of_contract_error e)
  | Ok () ->
      match assoc_at "$.given" given with
      | Error e -> error_observation ~executed:false (string_of_contract_error e)
      | Ok fields ->
          match exact_fields "$.given" ["prior_warning_count"] fields,
                required_field "$.given" "prior_warning_count" fields int_at with
          | Error e, _ | _, Error e ->
              error_observation ~executed:false (string_of_contract_error e)
          | Ok (), Ok prior when prior < 0 ->
              error_observation ~executed:false "prior_warning_count must be nonnegative"
          | Ok (), Ok _ ->
              let limits = { default_process_limits with timeout_ms = 1_190_000;
                stdout_limit = 4 * 1024 * 1024; stderr_limit = 131_072 } in
              let observed = run_command ~limits ~expected_exit:0 Compiler_diagnostics_command in
              if not observed.passed then observed
              else match parse_json_strict observed.stdout with
              | Error e -> { observed with passed=false; passing_tests=0; status=Status_error;
                                           stderr=string_of_contract_error e }
              | Ok (`Assoc result) ->
                  (match List.assoc_opt "passed" result,
                         List.assoc_opt "targeted_unused_warnings" result,
                         List.assoc_opt "assertions_removed" result with
                   | Some (`Bool true), Some (`Int warnings), Some (`Int removed)
                     when warnings >= 0 && removed >= 0 ->
                       { observed with data=Some (`Assoc [
                           "targeted_unused_warnings", `Int warnings;
                           "assertions_removed", `Int removed;
                           "compiler_diagnostics", `Assoc result ]) }
                   | _ -> { observed with passed=false; passing_tests=0; status=Status_error;
                             stderr="compiler driver lacks passing observed diagnostic fields" })
              | Ok _ -> { observed with passed=false; passing_tests=0; status=Status_error;
                                       stderr="compiler driver output must be an object" }

let supported_operations =
  [ ("runner.verify", runner_verify);
    ("candidate.snapshot", candidate_snapshot);
    ("compiler.check_affected_tests", compiler_check_affected_tests) ]

let dispatch_operation operation given =
  match List.assoc_opt operation supported_operations with
  | None ->
      error_observation ~operation_supported:false ~built:false ~executed:false
        ("operation is not registered: " ^ operation)
  | Some handler -> handler given
