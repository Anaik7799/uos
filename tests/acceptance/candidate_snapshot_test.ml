#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup,yojson";;

open Bos

let fail message =
  failwith ("FAIL candidate_snapshot: " ^ message)

let check condition message = if not condition then fail message

let run argv =
  match OS.Cmd.(run_out ~err:err_run_out (Cmd.of_list argv) |> out_string ~trim:false) with
  | Error (`Msg message) -> fail ("could not run candidate snapshot: " ^ message)
  | Ok (stdout, (_, status)) -> (stdout, status)

let exited expected = function
  | `Exited actual -> actual = expected
  | `Signaled _ -> false

let show_status = function
  | `Exited code -> Printf.sprintf "exit %d" code
  | `Signaled signal -> Printf.sprintf "signal %d" signal

let member name json = Yojson.Basic.Util.member name json
let string name json = member name json |> Yojson.Basic.Util.to_string
let bool name json = member name json |> Yojson.Basic.Util.to_bool
let int name json = member name json |> Yojson.Basic.Util.to_int
let list name json = member name json |> Yojson.Basic.Util.to_list

let has_assoc name = function
  | `Assoc fields -> List.mem_assoc name fields
  | _ -> false

let assert_required_records json =
  let records = member "records" json in
  List.iter
    (fun name -> check (has_assoc name records) ("missing observed record " ^ name))
    [ "change_id"; "commit_id"; "dirty_manifest"; "served_build";
      "tool_versions"; "clock_receipt" ]

let assert_claims_are_classified json =
  let allowed = [ "current-supported"; "stale"; "unrun"; "contradicted" ] in
  let claims = list "claims" json in
  check (List.length claims >= 6) "reviewed inherited claims were omitted";
  List.iter
    (fun claim ->
      let classification = string "classification" claim in
      check (List.mem classification allowed)
        ("invalid claim classification " ^ classification);
      check (String.length (string "locator" claim) > 0)
        "claim lacks an evidence locator")
    claims

let assert_reviewed_claim_set json =
  let ids =
    list "claims" json |> List.map (string "id")
  in
  List.iter
    (fun required ->
      check (List.mem required ids) ("reviewed claim omitted: " ^ required))
    [ "standalone-jj-candidate-identity"; "inherited-all-passed";
      "new-fpp-code-operational"; "agent-factory-clock-current";
      "tcm-clock-current"; "cli-checks-verified";
      "simulated-ocaml-ingestion"; "constant-metrics";
      "system-ratification-signature"; "handover-tag-current";
      "zero-warning-test-run"; "dry-run-census-admitted";
      "nine-modality-browser-coverage"; "rust-storage-validator-covered";
      "evolutionary-cycles-ratified" ]

let assert_review_binding json =
  check (has_assoc "review_binding" json) "forensic review binding was omitted";
  let binding = member "review_binding" json in
  check (string "status" binding = "bound")
    "forensic review receipt was not revision-bound";
  check
    (string "receipt_sha256" binding
    = "191dae268e3a95c4df1aae660a7243d3b975f78f6f6fc9cab918629d104542b4")
    "forensic review receipt digest changed without invalidating the binding";
  check
    (string "receipt_candidate_commit_id" binding
    = "53308442c6ef81c509abbf402e9b44f58801f6d1")
    "forensic review candidate revision was not retained";
  list "claims" json
  |> List.iter (fun claim ->
         check (has_assoc "locator_state" claim)
           ("claim lacks inspected locator state: " ^ string "id" claim);
         check (has_assoc "review_revision" claim)
           ("claim lacks source review revision: " ^ string "id" claim))

let assert_quarantines_are_presence_only json =
  let quarantines = list "quarantines" json in
  check (List.length quarantines = 2) "known quarantine records were omitted";
  List.iter
    (fun record ->
      check (string "inspection" record = "presence_only")
        "quarantine inspection was not presence-only";
      check (bool "secret_bytes_read" record = false)
        "quarantine record says secret bytes were read";
      check (not (has_assoc "digest" record))
        "quarantine record must never contain a digest";
      check (not (has_assoc "content" record))
        "quarantine record must never contain content")
    quarantines

let assert_metadata_allowlist json =
  let metadata = list "source_metadata" json in
  metadata
  |> List.iter (fun record ->
         let path = string "path" record in
         check
           (String.starts_with ~prefix:"governance/sources/" path)
           ("source metadata escaped allowlist: " ^ path));
  let review =
    List.find
      (fun record ->
        string "path" record
        = "governance/sources/20260906-1620-codex-review-agy-forensic-reconciliation-receipt.json")
      metadata
  in
  check (bool "content_read" review) "read forensic receipt was reported unread";
  check (bool "digest_computed" review) "hashed forensic receipt was reported unhashed";
  check
    (string "observed_sha256" review
    = "191dae268e3a95c4df1aae660a7243d3b975f78f6f6fc9cab918629d104542b4")
    "forensic receipt metadata omitted its observed digest"

let valid_snapshot_args evidence_candidate =
  [ "timeout"; "20s"; "opam"; "exec"; "--"; "ocaml";
    "tools/verification/candidate_snapshot.ml"; "snapshot"; "--candidate";
    "current-jj"; "--evidence-candidate"; evidence_candidate; "--source-mode";
    "read_only"; "--clock-source"; "chrony"; "--inherited-claim";
    "all_passed"; "--served-url"; "http://127.0.0.1:9/unavailable" ]

let jj_summary () =
  let stdout, status =
    run [ "timeout"; "10s"; "jj"; "diff"; "--summary"; "--no-pager" ]
  in
  check (exited 0 status) "could not observe Jujutsu diff summary";
  stdout

let write_file path content =
  match OS.File.write (Fpath.v path) content with
  | Ok () -> ()
  | Error (`Msg message) -> fail ("fixture write failed: " ^ message)

let compile_fixture name source =
  let stem =
    Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "e01-%d-%s" (Unix.getpid ()) name)
  in
  let source_path = stem ^ ".ml" in
  write_file source_path source;
  let _, status =
    run [ "timeout"; "20s"; "ocamlc"; "unix.cma"; "-o"; stem; source_path ]
  in
  check (exited 0 status) ("could not compile fixture " ^ name);
  (stem, source_path)

let remove_if_present path =
  try if Sys.file_exists path then Sys.remove path with Sys_error _ -> ()

let process_is_running pid =
  let path = Printf.sprintf "/proc/%d/stat" pid in
  try
    let channel = open_in path in
    let line =
      Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () -> input_line channel)
    in
    match String.rindex_opt line ')' with
    | Some index when index + 2 < String.length line -> line.[index + 2] <> 'Z'
    | _ -> true
  with Sys_error _ -> false

let with_probe_fixtures body =
  let closed_pid_file =
    Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "e01-%d-closed-descendant.pid" (Unix.getpid ()))
  in
  let timeout_pid_file = closed_pid_file ^ ".timeout" in
  let closed_exe, closed_source =
    compile_fixture "closed-descendant"
      (Printf.sprintf
         "let () = match Unix.fork () with 0 -> Unix.close Unix.stdout; Unix.close Unix.stderr; Sys.set_signal Sys.sigterm Sys.Signal_ignore; Unix.sleep 30 | child -> let c = open_out %S in Printf.fprintf c \"%%d\\n\" child; close_out c; Printf.printf \"%%d\\n%%!\" child\n"
         closed_pid_file)
  in
  let overflow_exe, overflow_source =
    compile_fixture "overflow"
      "let () = print_string (String.make 200000 'x'); flush stdout\n"
  in
  let timeout_exe, timeout_source =
    compile_fixture "timeout"
      (Printf.sprintf
         "let () = match Unix.fork () with 0 -> Unix.sleep 30 | child -> let c = open_out %S in Printf.fprintf c \"%%d\\n\" child; close_out c; Printf.printf \"%%d\\n%%!\" child; Unix.sleep 30\n"
         timeout_pid_file)
  in
  let served_exe, served_source =
    compile_fixture "served-version"
      "let () = print_string \"{\\\"version\\\":\\\"1.0.0\\\",\\\"zenoh_connected\\\":false}\\n__UOS_HTTP__200 application/json\"\n"
  in
  let served_array_exe, served_array_source =
    compile_fixture "served-array"
      "let () = print_string \"[]\\n__UOS_HTTP__200 application/json\"\n"
  in
  let counter = overflow_exe ^ ".counter" in
  let changing_source =
    Printf.sprintf
      "let has x = Array.exists ((=) x) Sys.argv\nlet () = if has \"log\" then begin let second = Sys.file_exists %S in if second then print_endline \"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\n2222222222222222222222222222222222222222\" else begin let c = open_out %S in close_out c; print_endline \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\n1111111111111111111111111111111111111111\" end end else if has \"--version\" then print_endline \"jj fake-1\"\n"
      counter counter
  in
  let changing_exe, changing_file = compile_fixture "changing-jj" changing_source in
  Fun.protect
    ~finally:(fun () ->
      (* Independent of snapshot parsing/assertions: never leave the fixture alive. *)
      List.iter (fun path ->
        try
          let c = open_in path in
          let pid = Fun.protect ~finally:(fun () -> close_in_noerr c)
              (fun () -> input_line c |> int_of_string) in
          if process_is_running pid then Unix.kill pid Sys.sigkill
        with Sys_error _ | Failure _ | Unix.Unix_error _ -> ())
        [ closed_pid_file; timeout_pid_file ];
      let compiled_artifacts executable source =
        [ executable; source; executable ^ ".cmi"; executable ^ ".cmo" ]
      in
      List.iter remove_if_present
        (List.concat_map
           (fun (executable, source) -> compiled_artifacts executable source)
           [ (overflow_exe, overflow_source); (timeout_exe, timeout_source);
             (closed_exe, closed_source);
             (served_exe, served_source);
             (served_array_exe, served_array_source);
             (changing_exe, changing_file) ]
        @ [ counter; closed_pid_file; timeout_pid_file ]))
    (fun () ->
      body overflow_exe timeout_exe served_exe served_array_exe changing_exe closed_exe)

let () =
  let source_before = jj_summary () in
  let stdout, status = run (valid_snapshot_args "older-jj") in
  check (exited 0 status) "valid read-only snapshot did not exit zero";
  check (String.length stdout <= 131_072) "snapshot exceeded its output quota";
  let json = Yojson.Basic.from_string stdout in
  check (string "operation" json = "candidate.snapshot") "wrong operation";
  check (has_assoc "status" json) "snapshot status was omitted";
  check (string "status" json = "SNAPSHOT_CAPTURED_NONPASSING")
    "snapshot availability was reported as a passing verification";
  check (has_assoc "admitted" json) "candidate admission state was omitted";
  check (bool "admitted" json = false)
    "snapshot operation granted candidate admission";
  check (string "inherited_credit" json = "STALE")
    "current candidate versus older evidence did not become STALE";
  check (int "source_writes" json = 0) "read-only snapshot wrote source";
  check (has_assoc "source_write_observation" json)
    "zero source writes lacked a workspace observation";
  let source_observation = member "source_write_observation" json in
  check (string "method" source_observation = "jj_diff_summary_before_after")
    "zero source writes lacked a before/after workspace observation";
  check (bool "workspace_state_unchanged" source_observation)
    "source workspace changed during the snapshot";
  check (bool "signature_credit" json = false)
    "unauthenticated signature received credit";
  assert_required_records json;
  let candidate = member "candidate" json in
  check (String.length (string "change_id" candidate) >= 32)
    "actual Jujutsu change id was not recorded";
  check (String.length (string "commit_id" candidate) = 40)
    "actual Jujutsu commit id was not recorded";
  assert_claims_are_classified json;
  assert_reviewed_claim_set json;
  assert_review_binding json;
  assert_quarantines_are_presence_only json;
  assert_metadata_allowlist json;
  let envelope = member "resource_envelope" json in
  check (string "operational_status" envelope = "implemented_unavailable")
    "unavailable Resource_envelope substrate was hidden";
  check (bool "credit" envelope = false)
    "unavailable Resource_envelope substrate received credit";
  let served = member "served_build" (member "records" json) in
  check (string "build_identity_status" served = "UNKNOWN")
    "HTTP reachability was mistaken for a served build identity";
  check (jj_summary () = source_before)
    "candidate snapshot changed the Jujutsu source diff";

  let current_stdout, current_status =
    run (valid_snapshot_args (string "change_id" candidate))
  in
  check (exited 0 current_status) "current-evidence snapshot did not exit zero";
  let current_json = Yojson.Basic.from_string current_stdout in
  check (string "inherited_credit" current_json = "UNRUN")
    "matching candidate without a receipt received inherited credit";

  let _, bad_status =
    run
      [ "timeout"; "20s"; "opam"; "exec"; "--"; "ocaml";
        "tools/verification/candidate_snapshot.ml"; "snapshot"; "--candidate";
        "current-jj"; "--evidence-candidate"; "older-jj"; "--source-mode";
        "writable"; "--clock-source"; "chrony"; "--inherited-claim";
        "all_passed" ]
  in
  check (exited 2 bad_status) "non-read-only source mode did not fail closed";

  let _, bad_clock_source =
    run
      [ "timeout"; "20s"; "opam"; "exec"; "--"; "ocaml";
        "tools/verification/candidate_snapshot.ml"; "snapshot"; "--candidate";
        "current-jj"; "--evidence-candidate"; "older-jj"; "--source-mode";
        "read_only"; "--clock-source"; "system-clock"; "--inherited-claim";
        "all_passed" ]
  in
  check (exited 2 bad_clock_source) "non-Chrony clock input did not fail closed";

  let _, missing_jj_status =
    run
      (valid_snapshot_args "older-jj"
      @ [ "--jj-bin"; "/tmp/e01-definitely-missing-jj" ])
  in
  check (exited 1 missing_jj_status) "missing Jujutsu did not fail the snapshot";

  let missing_clock_stdout, missing_clock_status =
    run
      (valid_snapshot_args "older-jj"
      @ [ "--clock-bin"; "/tmp/e01-definitely-missing-chronyc" ])
  in
  check (exited 0 missing_clock_status)
    "missing clock prevented recording an unavailable receipt";
  let missing_clock_json = Yojson.Basic.from_string missing_clock_stdout in
  let missing_clock = member "clock_receipt" (member "records" missing_clock_json) in
  check (string "status" missing_clock = "unavailable")
    "missing clock was not explicit";
  check (bool "credit" missing_clock = false) "missing clock received credit";

  with_probe_fixtures
    (fun overflow_exe timeout_exe served_exe served_array_exe changing_jj_exe closed_exe ->
      let closed_stdout, closed_status =
        run (valid_snapshot_args "older-jj" @ [ "--clock-bin"; closed_exe ])
      in
      check (exited 0 closed_status) "normally exited probe crashed snapshot";
      let closed_record =
        member "clock_receipt" (member "records" (Yojson.Basic.from_string closed_stdout))
      in
      let descendant_pid = string "output" closed_record |> int_of_string in
      check (not (process_is_running descendant_pid))
        "normally exited probe left a live descendant with closed output descriptors";
      check (int "exit_code" closed_record = 0 && not (bool "timed_out" closed_record))
        "normally exited probe lost its original status";
      check (bool "direct_child_reaped" closed_record)
        "normally exited probe did not reap its direct child";
      check (bool "process_group_termination_attempted" closed_record)
        "normally exited probe did not attempt process-group cleanup";
      check (not (has_assoc "children_reaped" closed_record))
        "normally exited probe claimed unobserved descendant reaping";
      let served_stdout, served_status =
        run
          (valid_snapshot_args "older-jj"
          @ [ "--curl-bin"; served_exe ])
      in
      check (exited 0 served_status)
        ("served-version fixture crashed snapshot: " ^ show_status served_status ^ " "
       ^ String.trim served_stdout);
      let served_json = Yojson.Basic.from_string served_stdout in
      let served_record = member "served_build" (member "records" served_json) in
      check (string "status" served_record = "reachable")
        "reachable served endpoint was not recorded";
      check (string "served_version" served_record = "1.0.0")
        "served version was not observed";
      check (string "build_identity_status" served_record = "UNKNOWN")
        "version-only endpoint was mistaken for a candidate identity";
      check (bool "identity_credit" served_record = false)
        "version-only endpoint received identity credit";
      let source_observation = member "source_write_observation" served_json in
      check (has_assoc "external_probe_side_effects" source_observation)
        "external probe trust boundary was omitted";
      check (string "external_probe_side_effects" source_observation = "UNKNOWN")
        "caller-supplied executable received source-preservation trust";

      let served_array_stdout, served_array_status =
        run
          (valid_snapshot_args "older-jj"
          @ [ "--curl-bin"; served_array_exe ])
      in
      check (exited 0 served_array_status)
        ("non-object served JSON crashed snapshot: "
       ^ show_status served_array_status ^ " " ^ String.trim served_array_stdout);
      let served_array_json = Yojson.Basic.from_string served_array_stdout in
      let served_array_record =
        member "served_build" (member "records" served_array_json)
      in
      check (string "status" served_array_record = "reachable")
        "non-object JSON endpoint was not recorded as reachable";
      check (string "build_identity_status" served_array_record = "UNKNOWN")
        "non-object JSON endpoint supplied a candidate identity";
      check (bool "identity_credit" served_array_record = false)
        "non-object JSON endpoint received identity credit";

      let overflow_stdout, overflow_status =
        run
          (valid_snapshot_args "older-jj"
          @ [ "--clock-bin"; overflow_exe ])
      in
      check (exited 0 overflow_status) "output quota probe crashed snapshot";
      let overflow_json = Yojson.Basic.from_string overflow_stdout in
      let overflow = member "clock_receipt" (member "records" overflow_json) in
      check (bool "output_overflow" overflow)
        "streaming probe did not enforce output quota";
      check (String.length (string "output" overflow) <= 65_536)
        "overflow observation retained bytes above the quota";
      check (bool "credit" overflow = false) "overflow probe received credit";

      let started = Unix.gettimeofday () in
      let timeout_stdout, timeout_status =
        run
          (valid_snapshot_args "older-jj"
          @ [ "--clock-bin"; timeout_exe ])
      in
      let elapsed = Unix.gettimeofday () -. started in
      check (exited 0 timeout_status) "timed-out clock crashed snapshot";
      check (elapsed < 10.) "probe timeout did not bound wall-clock execution";
      let timeout_json = Yojson.Basic.from_string timeout_stdout in
      let timeout_record = member "clock_receipt" (member "records" timeout_json) in
      check (bool "timed_out" timeout_record) "probe timeout was not recorded";
      check (bool "direct_child_reaped" timeout_record = true)
        "timed-out probe did not reap its direct child";
      check (bool "process_group_termination_attempted" timeout_record = true)
        "timed-out probe did not attempt process-group cleanup";
      check (not (has_assoc "children_reaped" timeout_record))
        "snapshot claimed unobserved descendant reaping";
      let descendant_pid = string "output" timeout_record |> int_of_string in
      check (not (process_is_running descendant_pid))
        "timed-out probe left a live descendant process";
      check (bool "credit" timeout_record = false) "timeout received credit";

      let _, changed_status =
        run
          (valid_snapshot_args "older-jj"
          @ [ "--jj-bin"; changing_jj_exe ])
      in
      check (exited 1 changed_status)
        "candidate identity change during capture did not fail closed");

  let fixture_path =
    Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "e01-%d-fixture.json" (Unix.getpid ()))
  in
  let bad_fixture_path = fixture_path ^ ".bad" in
  Fun.protect
    ~finally:(fun () ->
      remove_if_present fixture_path;
      remove_if_present bad_fixture_path)
    (fun () ->
      write_file fixture_path
        {|{"candidate":"current-jj","evidence_candidate":"older-jj","source_mode":"read_only","clock_source":"chrony","inherited_claim":"all_passed"}|};
      let fixture_stdout, fixture_status =
        run
          [ "timeout"; "20s"; "opam"; "exec"; "--"; "ocaml";
            "tools/verification/candidate_snapshot.ml"; "snapshot"; "--fixture";
            fixture_path; "--served-url"; "http://127.0.0.1:9/unavailable" ]
      in
      check (exited 0 fixture_status) "strict E01 fixture was not accepted";
      let fixture_json = Yojson.Basic.from_string fixture_stdout in
      check (string "inherited_credit" fixture_json = "STALE")
        "fixture inputs were not used";
      write_file bad_fixture_path
        {|{"candidate":"current-jj","evidence_candidate":"older-jj","source_mode":"read_only","clock_source":"chrony","inherited_claim":"all_passed","expect":{"signature_credit":true}}|};
      let _, bad_fixture_status =
        run
          [ "timeout"; "20s"; "opam"; "exec"; "--"; "ocaml";
            "tools/verification/candidate_snapshot.ml"; "snapshot"; "--fixture";
            bad_fixture_path ]
      in
      check (exited 2 bad_fixture_status)
        "fixture containing expected values did not fail closed");
  print_endline "PASS candidate_snapshot: 14 cases"
