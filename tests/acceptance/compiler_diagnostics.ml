#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "yojson";;
#use "./tests/acceptance/run.ml";;

(* @agent_intent: Execute Q01 compiler and affected-test evidence in an
   isolated Gleam cwd without a shell.  Descriptor reads bind reviewed bytes
   before and after execution; every mismatch is non-passing. *)

type source_requirement = { path : string; expected : string }
type source_snapshot = { required : source_requirement; actual : string option; error : string option }
type stage = { name : string; argv : string list; result : process_result }
type operation_result = { passed : bool; json : Yojson.Basic.t }

let actor = { path = "apps/cepaf_gleam/test/c3i_knowledge_actor_test.gleam";
              expected = "75ed46fd40733b2b0ce71078e02b938f0cc373551d9d49797c26f7ba502cbaf0" }
let runtime = { path = "apps/cepaf_gleam/test/c3i_knowledge_runtime_test.gleam";
                expected = "2f92ffbc11929d78b59b85ce61124942f8e453b44a3e0a55322decb23b8e8670" }
let requirements = [actor; runtime]
let source_maximum_bytes = 1_048_576
let total_budget_ms = 1_200_000

let termination_json = function
  | Exited code -> `Assoc [("kind", `String "exited"); ("code", `Int code)]
  | Signaled signal -> `Assoc [("kind", `String "signaled"); ("signal", `Int signal)]
  | Timed_out -> `Assoc [("kind", `String "timed_out")]
  | Output_limit -> `Assoc [("kind", `String "output_limit")]

let stage_json stage =
  let result = stage.result in
  `Assoc [ ("name", `String stage.name); ("argv", `List (List.map (fun s -> `String s) stage.argv));
    ("termination", termination_json result.termination); ("stdout", `String result.stdout);
    ("stderr", `String result.stderr); ("duration_ms", `Float result.duration_ms);
    ("stdout_truncated", `Bool result.stdout_truncated); ("stderr_truncated", `Bool result.stderr_truncated);
    ("children_reaped", `Bool result.children_reaped) ]

let succeeded result = match result.termination with
  | Exited 0 -> not result.stdout_truncated && not result.stderr_truncated && result.children_reaped
  | Signaled _ | Exited _ | Timed_out | Output_limit -> false

let count_substring needle haystack =
  let rec loop offset count = match String.index_from_opt haystack offset needle.[0] with
    | None -> count
    | Some index when index + String.length needle <= String.length haystack
                      && String.sub haystack index (String.length needle) = needle ->
        loop (index + String.length needle) (count + 1)
    | Some index -> loop (index + 1) count
  in if needle = "" then 0 else loop 0 0

let targeted_unused_warnings stages =
  let diagnostic = stages |> List.filter (fun stage -> stage.name = "gleam_build" || stage.name = "gleam_check")
    |> List.map (fun stage -> stage.result.stdout ^ "\n" ^ stage.result.stderr) |> String.concat "\n" in
  let has file warning = count_substring file diagnostic > 0 && count_substring warning diagnostic > 0 in
  (if has "c3i_knowledge_actor_test.gleam" "Unused imported type" then 1 else 0)
  + (if has "c3i_knowledge_runtime_test.gleam" "Unused variable" then 1 else 0)

let test_eval =
  "c3i_knowledge_actor_test:start_and_query_knowledge_actor_test(), " ^
  "c3i_knowledge_actor_test:ingest_new_item_actor_test(), " ^
  "c3i_knowledge_actor_test:cited_recall_actor_test(), " ^
  "c3i_knowledge_actor_test:apply_decay_actor_test(), " ^
  "c3i_knowledge_actor_test:ingestion_actor_zero_trust_filter_test(), " ^
  "c3i_knowledge_runtime_test:compute_decayed_trust_nominal_test(), " ^
  "c3i_knowledge_runtime_test:create_envelope_and_port_call_ok_test(), " ^
  "c3i_knowledge_runtime_test:create_envelope_and_port_call_traps_test(), " ^
  "c3i_knowledge_runtime_test:ingest_c3i_inventory_and_query_recall_test(), " ^
  "c3i_knowledge_runtime_test:detect_anti_patterns_test(), " ^
  "c3i_knowledge_runtime_test:get_c3i_knowledge_runtime_status_test(), halt(0)."

let ebin_arguments app =
  let root = Filename.concat app "build/dev/erlang" in
  Sys.readdir root |> Array.to_list |> List.sort String.compare |> List.fold_left (fun args name ->
    let ebin = Filename.concat (Filename.concat root name) "ebin" in
    if Sys.file_exists ebin then args @ ["-pa"; ebin] else args) []

let limits = { timeout_ms = 600_000; stdout_limit = 4 * 1024 * 1024;
               stderr_limit = 4 * 1024 * 1024; term_grace_ms = 1_000 }
let cleanup_reserve_ms = (4 * limits.term_grace_ms) + 2_000

let failed_result started message =
  { termination = Exited 127; stdout = ""; stderr = message;
    duration_ms = (monotonic_now () -. started) *. 1000.; stdout_truncated = false;
    stderr_truncated = false; children_reaped = false; pid = 0 }

let run_stage ~deadline name argv =
  let started = monotonic_now () in
  let remaining_ms = int_of_float ((deadline -. started) *. 1000.) in
  let result =
    if remaining_ms <= cleanup_reserve_ms then failed_result started "total Q01 budget lacks E02 cleanup reserve"
    else let execution_ms = min limits.timeout_ms (remaining_ms - cleanup_reserve_ms) in
      try run_bounded { limits with timeout_ms = execution_ms } argv
      with exn -> failed_result started ("stage setup failure: " ^ Printexc.to_string exn)
  in { name; argv; result }

let snapshot root = List.map (fun required ->
  match read_checked_file ~maximum:source_maximum_bytes (Filename.concat root required.path) with
  | Ok checked -> { required; actual = Some checked.checked_binding.binding_sha256; error = None }
  | Error message -> { required; actual = None; error = Some message }) requirements

let snapshot_matches values = List.for_all (fun value -> value.actual = Some value.required.expected && value.error = None) values
let snapshots_equal left right = List.length left = List.length right && List.for_all2 (fun a b ->
  a.required.path = b.required.path && a.actual = b.actual && a.error = b.error) left right

let snapshot_json before after = `List (List.map2 (fun first second -> `Assoc [
  ("path", `String first.required.path); ("expected_sha256", `String first.required.expected);
  ("before_sha256", match first.actual with Some value -> `String value | None -> `Null);
  ("after_sha256", match second.actual with Some value -> `String value | None -> `Null);
  ("before_error", match first.error with Some value -> `String value | None -> `Null);
  ("after_error", match second.error with Some value -> `String value | None -> `Null);
  ("matched_before", `Bool (first.actual = Some first.required.expected && first.error = None));
  ("matched_after", `Bool (second.actual = Some second.required.expected && second.error = None));
  ("stable", `Bool (first.actual = second.actual && first.error = second.error)) ]) before after)

let result_json ~passed ~failure ~before ~after ~stages =
  let warnings = targeted_unused_warnings stages in
  `Assoc ([ ("operation", `String "compiler.check_affected_tests"); ("passed", `Bool passed);
    ("assertions_removed", if snapshot_matches before && snapshot_matches after then `Int 0 else `Null);
    ("assertions_removed_basis", `String "exact reviewed post-fix source SHA-256 bindings before and after execution only; not an AST proof");
    ("targeted_unused_warnings", `Int warnings); ("total_budget_ms", `Int total_budget_ms);
    ("cleanup_reserve_ms", `Int cleanup_reserve_ms); ("source_bindings", snapshot_json before after);
    ("dependencies", `List [`String "gleam"; `String "erl"; `String "E02 run_bounded"]);
    ("stages", `List (List.map stage_json stages)) ] @
    match failure with None -> [] | Some message -> [("failure", `String message)])

let run_operation ?(run = run_stage) ?(after_stages = fun () -> ()) root =
  let before = snapshot root in
  if not (snapshot_matches before) then
    { passed = false; json = result_json ~passed:false ~failure:(Some "reviewed source bytes differ before execution") ~before ~after:before ~stages:[] }
  else
    let original = Sys.getcwd () in
    let deadline = monotonic_now () +. (float_of_int total_budget_ms /. 1000.) in
    let stages, stage_failure = try
      let app = Filename.concat root "apps/cepaf_gleam" in
      let values = Fun.protect ~finally:(fun () -> Sys.chdir original) (fun () ->
        Sys.chdir app;
        let build = run ~deadline "gleam_build" ["gleam"; "build"] in
        let check = run ~deadline "gleam_check" ["gleam"; "check"] in
        let tests = run ~deadline "affected_11_erlang_functions"
          (["erl"; "-noshell"] @ ebin_arguments "." @ ["-eval"; test_eval]) in [build; check; tests]) in
      (values, None)
    with exn -> ([], Some ("operation setup failure: " ^ Printexc.to_string exn)) in
    after_stages ();
    let after = snapshot root in
    let stable = snapshots_equal before after in
    let passed = stage_failure = None && List.for_all (fun stage -> succeeded stage.result) stages
                 && targeted_unused_warnings stages = 0 && snapshot_matches after && stable in
    let failure = match stage_failure with
      | Some _ as value -> value
      | None when not (snapshot_matches after) -> Some "reviewed source bytes differ after execution"
      | None when not stable -> Some "reviewed source bytes changed during execution"
      | None when targeted_unused_warnings stages <> 0 -> Some "targeted compiler warning observed"
      | None when not (List.for_all (fun stage -> succeeded stage.result) stages) -> Some "compiler or affected-test stage failed"
      | None -> None in
    { passed; json = result_json ~passed ~failure ~before ~after ~stages }

type cli_output = Stdout | File of string
let known_output_path path = Filename.is_relative path && Filename.dirname path = "governance/testing/ocaml_gleam"
  && Filename.check_suffix path ".json" && Filename.basename path <> ".json"
let parse_cli argv = match Array.to_list argv with
  | [_] -> Ok Stdout
  | [_; "--output"; path] when known_output_path path -> Ok (File path)
  | _ -> Error "usage: compiler_diagnostics.ml [--output governance/testing/ocaml_gleam/NAME.json]"
let emit output json = try match output with
  | Stdout -> print_endline (Yojson.Basic.pretty_to_string json); Ok ()
  | File path -> Yojson.Basic.to_file path json; Ok ()
  with exn -> Error ("output write failed: " ^ Printexc.to_string exn)
let main argv = match parse_cli argv with
  | Error message -> prerr_endline message; 2
  | Ok output -> let operation = run_operation (Sys.getcwd ()) in
    match emit output operation.json with Error message -> prerr_endline message; 2 | Ok () -> if operation.passed then 0 else 1
let direct_invocation () = Filename.basename Sys.argv.(0) = "compiler_diagnostics.ml"
let () = if direct_invocation () then exit (main Sys.argv)
