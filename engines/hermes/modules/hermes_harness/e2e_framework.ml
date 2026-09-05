type tier =
  | Tier1_Feature
  | Tier2_Boundary
  | Tier3_Pairwise
  | Tier4_Application

type test_result =
  | Pass
  | Fail of string
  | Skip of string

type test_case = {
  id : string;
  name : string;
  tier : tier;
  feature : string;
  run : unit -> test_result;
}

let registry : test_case list ref = ref []

let register_test tc =
  registry := !registry @ [tc]

let clear_registry () =
  registry := []

let get_all_tests () =
  !registry

let string_of_tier = function
  | Tier1_Feature -> "Tier1_Feature"
  | Tier2_Boundary -> "Tier2_Boundary"
  | Tier3_Pairwise -> "Tier3_Pairwise"
  | Tier4_Application -> "Tier4_Application"

let string_of_result = function
  | Pass -> "PASS"
  | Fail msg -> "FAIL: " ^ msg
  | Skip msg -> "SKIP: " ^ msg

let default_envelope () =
  let root = Sys.getcwd () in
  let state_dir = Filename.concat root "state" in
  Resource_envelope.[
    Disk_space { path = root; bytes_needed = 64 * 1024 * 1024; margin = default_margin };
    Temp_space { bytes_needed = 32 * 1024 * 1024; margin = default_margin };
    Writable (if Sys.file_exists state_dir then state_dir else root)
  ]

let run_preflight () =
  let envelope = default_envelope () in
  let checks = Resource_envelope.preflight envelope in
  if not (Resource_envelope.satisfied checks) then begin
    Printf.eprintf "[E2E Preflight] REFUSED: %d of %d resource requirements unsatisfied\n"
      (List.length (Resource_envelope.unmet_checks checks))
      (List.length checks);
    List.iter
      (fun d -> prerr_endline (Fractal_diagnostic.render d))
      (Resource_envelope.to_diagnostics checks);
    false
  end else begin
    Printf.printf "[E2E Preflight] OK: %d resources satisfied (floor_bytes=%d)\n"
      (List.length checks) Resource_envelope.floor_bytes;
    true
  end

let run_suite () =
  if not (run_preflight ()) then
    (0, 1, 0)
  else
    let tests = get_all_tests () in
    Printf.printf "\n==================================================\n";
    Printf.printf "  HERMES E2E REQUIREMENT-DRIVEN TEST SUITE\n";
    Printf.printf "==================================================\n";
    Printf.printf "Total Registered Tests: %d\n\n" (List.length tests);
    let pass_count = ref 0 in
    let fail_count = ref 0 in
    let skip_count = ref 0 in
    List.iter
      (fun tc ->
        Printf.printf "[%s] [%s] [%s] %s ... "
          (string_of_tier tc.tier) tc.id tc.feature tc.name;
        flush stdout;
        let result =
          try tc.run ()
          with exn -> Fail (Printf.sprintf "Uncaught exception: %s" (Printexc.to_string exn))
        in
        match result with
        | Pass ->
            incr pass_count;
            Printf.printf "PASS\n"
        | Fail msg ->
            incr fail_count;
            Printf.printf "FAIL: %s\n" msg
        | Skip msg ->
            incr skip_count;
            Printf.printf "SKIP: %s\n" msg)
      tests;
    Printf.printf "--------------------------------------------------\n";
    Printf.printf "Summary: %d Passed, %d Failed, %d Skipped (Total %d)\n"
      !pass_count !fail_count !skip_count (List.length tests);
    Printf.printf "==================================================\n\n";
    (!pass_count, !fail_count, !skip_count)

let run_all () =
  let (_pass, fail, _skip) = run_suite () in
  if fail > 0 then 1 else 0
