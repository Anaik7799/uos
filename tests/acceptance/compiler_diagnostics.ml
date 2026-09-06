#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "digestif.ocaml,yojson";;
#use "./tests/acceptance/process_supervisor.ml";;

(* @agent_intent: Execute Q01's compiler and affected-test evidence in an
   isolated Gleam cwd without a shell.  @laws: source binding mismatch or any
   stage failure yields a non-passing JSON result; no stage is omitted. *)

type binding = { path : string; expected : string }
type stage = { name : string; argv : string list; result : process_result }

let actor = {
  path = "apps/cepaf_gleam/test/c3i_knowledge_actor_test.gleam";
  expected = "75ed46fd40733b2b0ce71078e02b938f0cc373551d9d49797c26f7ba502cbaf0";
}
let runtime = {
  path = "apps/cepaf_gleam/test/c3i_knowledge_runtime_test.gleam";
  expected = "2f92ffbc11929d78b59b85ce61124942f8e453b44a3e0a55322decb23b8e8670";
}
let bindings = [actor; runtime]

let sha256_file path =
  In_channel.with_open_bin path In_channel.input_all
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let termination_json = function
  | Exited code -> `Assoc [("kind", `String "exited"); ("code", `Int code)]
  | Signaled signal -> `Assoc [("kind", `String "signaled"); ("signal", `Int signal)]
  | Timed_out -> `Assoc [("kind", `String "timed_out")]
  | Output_limit -> `Assoc [("kind", `String "output_limit")]

let stage_json stage =
  let result = stage.result in
  `Assoc [
    ("name", `String stage.name); ("argv", `List (List.map (fun s -> `String s) stage.argv));
    ("termination", termination_json result.termination); ("stdout", `String result.stdout);
    ("stderr", `String result.stderr); ("duration_ms", `Float result.duration_ms);
    ("stdout_truncated", `Bool result.stdout_truncated);
    ("stderr_truncated", `Bool result.stderr_truncated);
    ("children_reaped", `Bool result.children_reaped);
  ]

let succeeded result = match result.termination with
  | Exited 0 -> not result.stdout_truncated && not result.stderr_truncated && result.children_reaped
  | Signaled _ | Exited _ | Timed_out | Output_limit -> false

let count_substring needle haystack =
  let rec loop offset count =
    match String.index_from_opt haystack offset needle.[0] with
    | None -> count
    | Some index when index + String.length needle <= String.length haystack
                      && String.sub haystack index (String.length needle) = needle ->
        loop (index + String.length needle) (count + 1)
    | Some index -> loop (index + 1) count
  in if needle = "" then 0 else loop 0 0

let targeted_unused_warnings result =
  let diagnostic = result.stdout ^ "\n" ^ result.stderr in
  let has file warning = count_substring file diagnostic > 0
                         && count_substring warning diagnostic > 0 in
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
  Sys.readdir root |> Array.to_list |> List.sort String.compare
  |> List.fold_left (fun args name ->
       let ebin = Filename.concat (Filename.concat root name) "ebin" in
       if Sys.file_exists ebin then args @ ["-pa"; ebin] else args) []

let limits = { timeout_ms = 600_000; stdout_limit = 4 * 1024 * 1024;
               stderr_limit = 4 * 1024 * 1024; term_grace_ms = 1_000 }

let budget_failure started = {
  termination = Timed_out; stdout = ""; stderr = "total Q01 budget exhausted";
  duration_ms = (monotonic_now () -. started) *. 1000.;
  stdout_truncated = false; stderr_truncated = false; children_reaped = false; pid = 0;
}

let run_stage ~deadline name argv =
  let started = monotonic_now () in
  let remaining_ms = int_of_float ((deadline -. started) *. 1000.) in
  let result =
    if remaining_ms <= 0 then budget_failure started
    else run_bounded { limits with timeout_ms = min limits.timeout_ms remaining_ms } argv
  in
  { name; argv; result }

let bindings_json root checks =
  `List (List.map2 (fun binding check ->
    let actual = try Some (sha256_file (Filename.concat root binding.path)) with _ -> None in
    `Assoc [("path", `String binding.path); ("expected_sha256", `String binding.expected);
            ("actual_sha256", match actual with Some value -> `String value | None -> `Null);
            ("matched", `Bool check)]) bindings checks)

let output_path () =
  if Array.length Sys.argv = 3 && Sys.argv.(1) = "--output" then Some Sys.argv.(2)
  else None

let emit json = match output_path () with
  | None -> print_endline (Yojson.Basic.pretty_to_string json)
  | Some path -> Yojson.Basic.to_file path json

let () =
  let root = Sys.getcwd () in
  let checks = List.map (fun binding ->
    try sha256_file (Filename.concat root binding.path) = binding.expected with _ -> false) bindings in
  if not (List.for_all Fun.id checks) then emit (`Assoc [
    ("operation", `String "compiler.check_affected_tests"); ("passed", `Bool false);
    ("failure", `String "reviewed source bytes differ");
    ("assertions_removed", `Null); ("targeted_unused_warnings", `Null);
    ("source_bindings", bindings_json root checks)])
  else begin
    let app = Filename.concat root "apps/cepaf_gleam" in
    let original = Sys.getcwd () in
    let deadline = monotonic_now () +. 1_200. in
    let stages = Fun.protect ~finally:(fun () -> Sys.chdir original) (fun () ->
      Sys.chdir app;
      let build = run_stage ~deadline "gleam_build" ["gleam"; "build"] in
      let check = run_stage ~deadline "gleam_check" ["gleam"; "check"] in
      let tests = run_stage ~deadline "affected_11_erlang_functions"
        (["erl"; "-noshell"] @ ebin_arguments "." @ ["-eval"; test_eval]) in
      [build; check; tests]) in
    let check = List.nth stages 1 in
    let passed = List.for_all (fun stage -> succeeded stage.result) stages
                 && targeted_unused_warnings check.result = 0 in
    emit (`Assoc [
      ("operation", `String "compiler.check_affected_tests"); ("passed", `Bool passed);
      ("assertions_removed", `Int 0);
      ("assertions_removed_basis", `String "exact reviewed post-fix source SHA-256 bindings only; not an AST proof");
      ("targeted_unused_warnings", `Int (targeted_unused_warnings check.result));
      ("total_budget_ms", `Int 1_200_000); ("source_bindings", bindings_json root checks);
      ("dependencies", `List [`String "gleam"; `String "erl"; `String "E02 run_bounded"]);
      ("stages", `List (List.map stage_json stages))])
  end
