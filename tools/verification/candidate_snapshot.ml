#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup,cmdliner,digestif.ocaml,mtime.clock.os,yojson";;

(** @agent_intent Freeze an honest, bounded, read-only review-candidate snapshot.
    @laws Source trees are never written; quarantine targets are presence-only;
    unavailable probes and inherited evidence never receive admission credit. *)

open Bos
open Cmdliner

let default_output_limit = 65_536

type termination = Exited of int | Signaled of int

type probe = {
  output : string;
  status : termination;
  timed_out : bool;
  output_overflow : bool;
  direct_child_reaped : bool;
  process_group_termination_attempted : bool;
  duration_ms : int;
}

let status_code = function
  | Exited code -> code
  | Signaled signal -> 128 + signal

let close_noerr descriptor = try Unix.close descriptor with Unix.Unix_error _ -> ()

let rec kill_group pid signal =
  try Unix.kill (-pid) signal; true with
  | Unix.Unix_error (Unix.ESRCH, _, _) -> false
  | Unix.Unix_error (Unix.EPERM, _, _) -> true
  | Unix.Unix_error (Unix.EINTR, _, _) -> kill_group pid signal

let rec waitpid_nointr flags pid =
  try Unix.waitpid flags pid with
  | Unix.Unix_error (Unix.EINTR, _, _) -> waitpid_nointr flags pid

let termination_of_status = function
  | Unix.WEXITED code -> Exited code
  | Unix.WSIGNALED signal -> Signaled signal
  | Unix.WSTOPPED signal -> Signaled signal

let nanoseconds_per_second = 1_000_000_000L

let add_seconds timestamp seconds =
  Int64.add timestamp (Int64.mul (Int64.of_int seconds) nanoseconds_per_second)

let seconds_until deadline now =
  if Int64.compare deadline now <= 0 then 0.
  else Int64.to_float (Int64.sub deadline now) /. 1_000_000_000.

let run_bounded ~seconds ~max_bytes argv =
  if seconds <= 0 then Error "probe timeout must be positive"
  else if max_bytes <= 0 || max_bytes > 1_048_576 then
    Error "probe output quota must be within 1..1048576 bytes"
  else
    match argv with
    | [] -> Error "empty probe command"
    | executable :: _ -> (
        try
          let read_end, write_end = Unix.pipe ~cloexec:true () in
          let pid =
            try Unix.fork () with exn ->
              close_noerr read_end; close_noerr write_end; raise exn
          in
          match pid with
          | 0 ->
              (try
              close_noerr read_end;
              (try ignore (Unix.setsid ()) with Unix.Unix_error _ -> Unix._exit 126);
              Unix.dup2 write_end Unix.stdout;
              close_noerr write_end;
              let null = Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0 in
              Unix.dup2 null Unix.stderr;
              close_noerr null;
              Unix.execvp executable (Array.of_list argv)
               with _ -> Unix._exit 127)
          | pid ->
              close_noerr write_end;
              let started = Mtime_clock.elapsed_ns () in
              let deadline = add_seconds started seconds in
              let buffer = Buffer.create (min max_bytes 4096) in
              let output_overflow = ref false in
              let timed_out = ref false in
              let eof = ref false in
              let child_status = ref None in
              let terminated = ref false in
              let terminate_group () =
                if not !terminated then begin
                  terminated := true;
                  (* Stop immediately on ESRCH: waiting would only enlarge the
                     post-waitpid PGID-reuse window. Group signals are best effort,
                     not proof about escaped descendants or group identity. *)
                  if kill_group pid Sys.sigterm then begin
                    let grace = Int64.add (Mtime_clock.elapsed_ns ()) 50_000_000L in
                    let rec await_group () =
                      if kill_group pid 0 then
                        let remaining = seconds_until grace (Mtime_clock.elapsed_ns ()) in
                        if remaining <= 0. then ignore (kill_group pid Sys.sigkill)
                        else begin
                          (try ignore (Unix.select [] [] [] (min 0.01 remaining))
                           with Unix.Unix_error (Unix.EINTR, _, _) -> ());
                          await_group ()
                        end
                    in
                    await_group ()
                  end;
                  (* An exception may reach cleanup before the child setsid.
                     An unreaped child still owns its PID, so this fallback is safe. *)
                  if Option.is_none !child_status then
                    (try Unix.kill pid Sys.sigkill
                     with Unix.Unix_error (Unix.ESRCH, _, _) -> ())
                end
              in
              let chunk = Bytes.create 4096 in
              let rec drain () =
                if not !eof && not !output_overflow then
                  try
                    match Unix.read read_end chunk 0 (Bytes.length chunk) with
                    | 0 -> eof := true
                    | count ->
                        let remaining = max_bytes - Buffer.length buffer in
                        if count > remaining then begin
                          if remaining > 0 then
                            Buffer.add_subbytes buffer chunk 0 remaining;
                          output_overflow := true;
                          terminate_group ()
                        end
                        else begin
                          Buffer.add_subbytes buffer chunk 0 count;
                          drain ()
                        end
                  with
                  | Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) -> ()
                  | Unix.Unix_error (Unix.EINTR, _, _) -> drain ()
              in
              let poll_child () =
                if Option.is_none !child_status then
                  match waitpid_nointr [ Unix.WNOHANG ] pid with
                  | 0, _ -> ()
                  | _, status -> child_status := Some status
              in
              let rec supervise () =
                drain ();
                poll_child ();
                let now = Mtime_clock.elapsed_ns () in
                if Option.is_none !child_status && Int64.compare now deadline >= 0 then begin
                  timed_out := true;
                  terminate_group ();
                  let _, status = waitpid_nointr [] pid in
                  child_status := Some status
                end;
                match (!child_status, !eof, !output_overflow) with
                | Some _, true, _ | Some _, _, true -> ()
                | Some _, false, false ->
                    terminate_group ();
                    ignore (Unix.select [ read_end ] [] [] 0.05);
                    drain ()
                | None, _, true ->
                    let _, status = waitpid_nointr [] pid in
                    child_status := Some status
                | None, _, false ->
                    let remaining = min 0.05 (seconds_until deadline now) in
                    ignore (Unix.select [ read_end ] [] [] remaining);
                    supervise ()
              in
              let cleanup () =
                Fun.protect ~finally:(fun () -> close_noerr read_end) (fun () ->
                  terminate_group ();
                  if Option.is_none !child_status then begin
                    let _, status = waitpid_nointr [] pid in
                    child_status := Some status
                  end)
              in
              Fun.protect ~finally:cleanup (fun () ->
                Unix.set_nonblock read_end;
                supervise ());
              let status =
                match !child_status with
                | Some status -> termination_of_status status
                | None -> Signaled Sys.sigkill
              in
              let duration_ms =
                Int64.sub (Mtime_clock.elapsed_ns ()) started
                |> fun elapsed -> Int64.div elapsed 1_000_000L
                |> Int64.to_int
              in
              Ok
                { output = Buffer.contents buffer |> String.trim; status;
                  timed_out = !timed_out; output_overflow = !output_overflow;
                  direct_child_reaped = Option.is_some !child_status;
                  process_group_termination_attempted = !terminated; duration_ms }
        with
        | Unix.Unix_error (error, operation, _) ->
            Error (operation ^ ": " ^ Unix.error_message error)
        | Sys_error message -> Error message)

let json_status probe =
  if probe.timed_out || probe.output_overflow then "unavailable"
  else if status_code probe.status = 0 then "observed"
  else "unavailable"

let probe_json ~locator = function
  | Error message ->
      `Assoc
        [ ("status", `String "unavailable"); ("locator", `String locator);
          ("reason", `String message); ("credit", `Bool false) ]
  | Ok probe ->
      `Assoc
        [ ("status", `String (json_status probe));
          ("locator", `String locator);
          ("exit_code", `Int (status_code probe.status));
          ("output", `String probe.output);
          ("timed_out", `Bool probe.timed_out);
          ("output_overflow", `Bool probe.output_overflow);
          ("direct_child_reaped", `Bool probe.direct_child_reaped);
          ( "process_group_termination_attempted",
            `Bool probe.process_group_termination_attempted );
          ("duration_ms", `Int probe.duration_ms);
          ("credit", `Bool false) ]

let successful_output label = function
  | Error message -> Error (label ^ " probe failed: " ^ message)
  | Ok probe when probe.output_overflow -> Error (label ^ " exceeded output quota")
  | Ok probe when probe.timed_out -> Error (label ^ " timed out")
  | Ok probe when status_code probe.status <> 0 ->
      Error
        (Printf.sprintf "%s probe exited %d" label (status_code probe.status))
  | Ok probe -> Ok probe.output

let nonempty_lines text =
  text |> String.split_on_char '\n' |> List.map String.trim
  |> List.filter (fun line -> line <> "")

let observe_identity ~jj_bin ~max_bytes () =
  let template = "change_id ++ \"\\n\" ++ commit_id ++ \"\\n\"" in
  match
    run_bounded ~seconds:5 ~max_bytes
      [ jj_bin; "log"; "-r"; "@"; "--no-graph"; "-T"; template;
        "--no-pager" ]
    |> successful_output "Jujutsu identity"
  with
  | Error _ as error -> error
  | Ok output -> (
      match nonempty_lines output with
      | change_id :: commit_id :: _ -> Ok (change_id, commit_id)
      | _ -> Error "Jujutsu identity probe returned fewer than two ids")

let observe_dirty_manifest ~jj_bin ~max_bytes () =
  run_bounded ~seconds:5 ~max_bytes
    [ jj_bin; "diff"; "--summary"; "--no-pager" ]

let observe_served_build ~curl_bin ~max_bytes url =
  run_bounded ~seconds:4 ~max_bytes
    [ curl_bin; "--silent"; "--show-error"; "--connect-timeout"; "1";
      "--max-time"; "3"; "--write-out";
      "\n__UOS_HTTP__%{http_code} %{content_type}"; url ]

let tool_probe ~max_bytes (name, argv) =
  let observation = run_bounded ~seconds:3 ~max_bytes argv in
  `Assoc
    [ ("tool", `String name);
      ("observation", probe_json ~locator:("path://" ^ name) observation) ]

let tool_versions ~jj_bin ~max_bytes () =
  [ ("jj", [ jj_bin; "--version" ]); ("ocamlc", [ "ocamlc"; "-version" ]);
    ("dune", [ "dune"; "--version" ]); ("gleam", [ "gleam"; "--version" ]);
    ("zig", [ "zig"; "version" ]) ]
  |> List.map (tool_probe ~max_bytes)

let observe_clock ~clock_bin ~max_bytes () =
  run_bounded ~seconds:3 ~max_bytes [ clock_bin; "tracking" ]

let unique_sorted strings = List.sort_uniq String.compare strings

let observe_process_names ~max_bytes () =
  match run_bounded ~seconds:3 ~max_bytes [ "ps"; "-eo"; "comm=" ] with
  | Error message ->
      `Assoc
        [ ("status", `String "unavailable"); ("reason", `String message);
          ("writer_quiescence", `String "not_established");
          ("credit", `Bool false) ]
  | Ok probe
    when status_code probe.status <> 0 || probe.output_overflow || probe.timed_out ->
      `Assoc
        [ ("status", `String "unavailable");
          ("exit_code", `Int (status_code probe.status));
          ("output_overflow", `Bool probe.output_overflow);
          ("timed_out", `Bool probe.timed_out);
          ("writer_quiescence", `String "not_established");
          ("credit", `Bool false) ]
  | Ok probe ->
      let relevant name =
        List.exists
          (fun prefix -> String.starts_with ~prefix name)
          [ "agy"; "beam"; "claude"; "codex"; "dune"; "erl"; "gleam";
            "jj" ]
      in
      let names = nonempty_lines probe.output |> List.filter relevant |> unique_sorted in
      `Assoc
        [ ("status", `String "observed_process_names_only");
          ("process_names", `List (List.map (fun x -> `String x) names));
          ("writer_quiescence", `String "not_established");
          ("credit", `Bool false) ]

let metadata_allowlist =
  [ "governance/sources/20260906-0606-agy-handover-source-receipt.json";
    "governance/sources/20260906-1620-codex-review-agy-forensic-reconciliation-receipt.json";
    "governance/sources/20260906-1655-uos-sa-plan-registration-receipt.json";
    "governance/sources/20260906-1930-c3i-vm1-artifacts-ingestion-receipt.json" ]

let metadata_record ?content_digest path =
  let content_read = Option.is_some content_digest in
  let access_fields =
    [ ("content_read", `Bool content_read);
      ("digest_computed", `Bool content_read);
      ( "observed_sha256",
        match content_digest with None -> `Null | Some digest -> `String digest ) ]
  in
  try
    let stat = Unix.lstat path in
    `Assoc
      ([ ("path", `String path); ("present", `Bool true);
         ("bytes", `Int stat.Unix.st_size);
         ("modified_unix_seconds", `Float stat.Unix.st_mtime);
         ( "inspection",
           `String
             (if content_read then "allowlisted_bound_receipt"
              else "allowlisted_metadata_only") ) ]
      @ access_fields)
  with
  | Unix.Unix_error ((Unix.ENOENT | Unix.ENOTDIR), _, _) ->
      `Assoc
        ([ ("path", `String path); ("present", `Bool false);
           ("inspection", `String "allowlisted_metadata_only") ]
        @ access_fields)
  | Unix.Unix_error (error, operation, _) ->
      `Assoc
        ([ ("path", `String path); ("present", `Bool false);
           ("inspection", `String "allowlisted_metadata_only");
           ("error", `String (operation ^ ": " ^ Unix.error_message error)) ]
        @ access_fields)

let source_root_present path =
  try Sys.file_exists path with Sys_error _ -> false

let quarantine_record incident source_root =
  `Assoc
    [ ("incident", `String incident); ("source_root", `String source_root);
      ("source_root_present", `Bool (source_root_present source_root));
      ("material_presence", `String "not_observed_by_policy");
      ("inspection", `String "presence_only");
      ("secret_bytes_read", `Bool false) ]

let review_receipt_path =
  "governance/sources/20260906-1620-codex-review-agy-forensic-reconciliation-receipt.json"

let pinned_review_sha256 =
  "191dae268e3a95c4df1aae660a7243d3b975f78f6f6fc9cab918629d104542b4"

let pinned_review_change_id = "tvkzvzkszursuknruwvyuklwqntluzpq"
let pinned_review_commit_id = "53308442c6ef81c509abbf402e9b44f58801f6d1"

type review_binding = {
  bound : bool;
  observed_sha256 : string option;
  candidate_change_id : string option;
  candidate_commit_id : string option;
  reason : string;
}

let read_file_bounded ~max_bytes path =
  try
    let channel = open_in_bin path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr channel)
      (fun () ->
        let length = in_channel_length channel in
        if length > max_bytes then Error "file exceeds review input quota"
        else Ok (really_input_string channel length))
  with
  | Sys_error message -> Error message
  | End_of_file -> Error "file changed while it was being read"

let inspect_review_binding () =
  match read_file_bounded ~max_bytes:262_144 review_receipt_path with
  | Error reason ->
      { bound = false; observed_sha256 = None; candidate_change_id = None;
        candidate_commit_id = None; reason }
  | Ok bytes ->
      let digest =
        bytes |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
      in
      if digest <> pinned_review_sha256 then
        { bound = false; observed_sha256 = Some digest; candidate_change_id = None;
          candidate_commit_id = None;
          reason = "review receipt digest differs from the pinned receipt" }
      else
        try
          let json = Yojson.Basic.from_string bytes in
          let open Yojson.Basic.Util in
          let schema = member "schema" json |> to_string in
          let candidate = member "candidate" json in
          let change_id = member "change_id" candidate |> to_string in
          let commit_id = member "commit_id" candidate |> to_string in
          let bound =
            schema = "uos.codex-handover-review.v1"
            && change_id = pinned_review_change_id
            && commit_id = pinned_review_commit_id
          in
          { bound; observed_sha256 = Some digest;
            candidate_change_id = Some change_id;
            candidate_commit_id = Some commit_id;
            reason =
              if bound then "receipt digest, schema, change and commit are pinned"
              else "review receipt candidate identity differs from the pin" }
        with
        | Yojson.Json_error message ->
            { bound = false; observed_sha256 = Some digest;
              candidate_change_id = None; candidate_commit_id = None;
              reason = "invalid review JSON: " ^ message }
        | Yojson.Basic.Util.Type_error (message, _) ->
            { bound = false; observed_sha256 = Some digest;
              candidate_change_id = None; candidate_commit_id = None;
              reason = "invalid review schema: " ^ message }

let option_json = function None -> `Null | Some value -> `String value

let review_binding_json binding =
  `Assoc
    [ ("status", `String (if binding.bound then "bound" else "unbound"));
      ("receipt_path", `String review_receipt_path);
      ("receipt_sha256", option_json binding.observed_sha256);
      ("expected_receipt_sha256", `String pinned_review_sha256);
      ("receipt_candidate_change_id", option_json binding.candidate_change_id);
      ("receipt_candidate_commit_id", option_json binding.candidate_commit_id);
      ("reason", `String binding.reason); ("credit", `Bool false) ]

type locator_state = Matches_review | Changed_since_review | Locator_unavailable

let locator_state_string = function
  | Matches_review -> "matches_reviewed_finding"
  | Changed_since_review -> "changed_since_review"
  | Locator_unavailable -> "unavailable"

let line_at path wanted =
  match read_file_bounded ~max_bytes:1_048_576 path with
  | Error _ -> None
  | Ok bytes -> (
      match List.nth_opt (String.split_on_char '\n' bytes) (wanted - 1) with
      | None -> None
      | Some line -> Some (String.trim line))

let inspect_exact_lines specifications =
  let observations =
    List.map
      (fun (path, line, expected) ->
        match line_at path line with
        | None -> Locator_unavailable
        | Some actual when actual = expected -> Matches_review
        | Some _ -> Changed_since_review)
      specifications
  in
  if List.exists (( = ) Locator_unavailable) observations then Locator_unavailable
  else if List.for_all (( = ) Matches_review) observations then Matches_review
  else Changed_since_review

let review_revision binding =
  match binding.candidate_commit_id with
  | Some revision -> revision
  | None -> "unbound"

let claim ~binding id classification locator locator_state rationale =
  `Assoc
    [ ("id", `String id); ("classification", `String classification);
      ("locator", `String locator);
      ("locator_state", `String locator_state);
      ("review_revision", `String (review_revision binding));
      ("rationale", `String rationale) ]

let inspected_classification binding state =
  if not binding.bound then "unrun"
  else
    match state with
    | Matches_review -> "contradicted"
    | Changed_since_review -> "stale"
    | Locator_unavailable -> "unrun"

let inspected_claim ~binding id locator specifications rationale =
  let state = inspect_exact_lines specifications in
  claim ~binding id (inspected_classification binding state) locator
    (locator_state_string state) rationale

let reviewed_claims ~binding ~evidence_matches =
  [ claim ~binding "standalone-jj-candidate-identity" "current-supported" "jj://@"
      "observed_current_candidate"
      "the current change and commit identifiers were observed from Jujutsu";
    claim ~binding "inherited-all-passed"
      (if evidence_matches then "unrun" else "stale")
      "HANDOVER_TO_CODEX.md:30" "receipt_candidate_comparison"
      (if evidence_matches then
         "the advertised total has no current invocation-bound receipt"
       else "the advertised receipt is bound to a different candidate");
    claim ~binding "new-fpp-code-operational" "unrun"
      "apps/cepaf_gleam/src/cepaf_gleam/fpp/agent_factory.gleam:68"
      "source_only_no_runtime_receipt"
      "source presence does not demonstrate current runtime behavior";
    inspected_claim ~binding "agent-factory-clock-current"
      "apps/cepaf_gleam/src/cepaf_gleam/fpp/agent_factory.gleam:88"
      [ ("apps/cepaf_gleam/src/cepaf_gleam/fpp/agent_factory.gleam", 88,
          "created_at_utc: \"2026-09-06T09:45:00.000000Z\",");
        ("apps/cepaf_gleam/src/cepaf_gleam/fpp/agent_factory.gleam", 125,
          "timestamp_utc: \"2026-09-06T09:45:00.000000Z\",") ]
      "agent creation and telemetry use fixed timestamp literals";
    inspected_claim ~binding "tcm-clock-current"
      "apps/cepaf_gleam/src/cepaf_gleam/fpp/dmc_tcm.gleam:245"
      [ ("apps/cepaf_gleam/src/cepaf_gleam/fpp/dmc_tcm.gleam", 245,
          "\"2026-09-06T09:40:\"") ]
      "the timestamp formatter embeds a fixed calendar date and hour";
    inspected_claim ~binding "cli-checks-verified" "tools/uos/src/main.gleam:220"
      [ ("tools/uos/src/main.gleam", 220,
          "io.println(\"UOS Doctor: All 84 EV-cycle boundaries operational (EV-01..EV-84 100% Green).\")");
        ("tools/uos/src/main.gleam", 662,
          "io.println(\"Summary: 18/18 Checks Passed (100% Green)\")") ]
      "doctor and checklist print constant passing summaries";
    inspected_claim ~binding "simulated-ocaml-ingestion"
      "apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_knowledge_runtime.gleam:126"
      [ ("apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_knowledge_runtime.gleam",
          126,
          "let payload_digest = \"sha256:\" <> int.to_string(string.length(payload_json))");
        ("apps/cepaf_gleam/src/cepaf_gleam/knowledge/c3i_knowledge_runtime.gleam",
          196, "status: \"COMMITTED\",") ]
      "the reviewed knowledge path simulates worker execution and ingestion";
    inspected_claim ~binding "constant-metrics"
      "apps/cepaf_gleam/src/cepaf_gleam/verification/omni_fractal_matrix_engine.gleam:412"
      [ ("apps/cepaf_gleam/src/cepaf_gleam/verification/omni_fractal_matrix_engine.gleam",
          413, "let entropy = 2.74");
        ("apps/cepaf_gleam/src/cepaf_gleam/verification/omni_fractal_matrix_engine.gleam",
          416, "let itqs = 0.91") ]
      "fixed metrics and model claims are not invocation-bound measurements";
    claim ~binding "system-ratification-signature" "unrun"
      "governance/sources/20260906-1620-codex-review-agy-forensic-reconciliation-receipt.json#findings/F04"
      "bound_review_finding_no_current_signature"
      "the advertised independent system ratification is not authenticated";
    claim ~binding "handover-tag-current" "stale"
      "tag/20260906-1649-single-file-session-handover-to-codex-ratified"
      "bound_review_candidate_is_older"
      "the advertised tag predates the implementation-backlog reconciliation";
    claim ~binding "zero-warning-test-run" "stale"
      "governance/sources/20260906-1620-codex-review-agy-forensic-reconciliation-receipt.json#commands/gleam-tests"
      "bound_to_review_candidate"
      "the recorded completed run reports two compiler warnings";
    claim ~binding "dry-run-census-admitted" "unrun"
      "governance/sources/20260906-1930-c3i-vm1-artifacts-ingestion-receipt.json"
      "no_current_admission_receipt"
      "a dry-run census does not establish sanitized candidate ingestion";
    claim ~binding "nine-modality-browser-coverage" "unrun" "HANDOVER_TO_CODEX.md:60"
      "no_current_execution_receipts"
      "test totals and HTTP probes do not execute the advertised modalities";
    inspected_claim ~binding "rust-storage-validator-covered"
      "ops/kubernetes/nas-k8s-lab/tests/hardware_identity_test.rs:8"
      [ ("ops/kubernetes/nas-k8s-lab/tests/hardware_identity_test.rs", 8,
          "pub fn validate_osd_candidate(serial: &str, device_path: &str) -> Result<(), &'static str> {") ]
      "three reviewed tests exercise a test-local helper instead of production validation";
    inspected_claim ~binding "evolutionary-cycles-ratified"
      "apps/cepaf_gleam/src/cepaf_gleam/fpp/evolutionary_cycles.gleam:377"
      [ ("apps/cepaf_gleam/src/cepaf_gleam/fpp/evolutionary_cycles.gleam", 377,
          "CycleRatified,");
        ("apps/cepaf_gleam/src/cepaf_gleam/fpp/evolutionary_cycles.gleam", 379,
          "\"sha256-c27-zk-knowledge-graph-zigvm-extraction\",") ]
      "cycle status and digest-like evidence are constants, not receipts" ]

let resource_envelope_record =
  `Assoc
    [ ("module", `String "engines/hermes/modules/hermes_harness/resource_envelope.mli");
      ("operational_status", `String "implemented_unavailable");
      ( "reason",
        `String
          "controlled external-resource observation owner injection is not implemented" );
      ("receipt_bound", `Bool false); ("credit", `Bool false) ]

let rec find_substring_from text pattern index =
  let text_length = String.length text in
  let pattern_length = String.length pattern in
  if index + pattern_length > text_length then None
  else if String.sub text index pattern_length = pattern then Some index
  else find_substring_from text pattern (index + 1)

let json_string_member name json =
  match json with
  | `Assoc fields -> (
      match List.assoc_opt name fields with
      | Some (`String value) when value <> "" -> Some value
      | _ -> None)
  | _ -> None

let first_some values = List.find_map Fun.id values

let served_build_json ~change_id ~commit_id ~url observation =
  let unknown_fields =
    [ ("build_identity_status", `String "UNKNOWN");
      ("served_candidate", `Null); ("identity_credit", `Bool false);
      ("admission_credit", `Bool false) ]
  in
  match observation with
  | Error _ as error -> (
      match probe_json ~locator:url error with
      | `Assoc fields -> `Assoc (fields @ unknown_fields)
      | _ -> assert false)
  | Ok probe
    when status_code probe.status <> 0 || probe.timed_out || probe.output_overflow -> (
      match probe_json ~locator:url (Ok probe) with
      | `Assoc fields -> `Assoc (fields @ unknown_fields)
      | _ -> assert false)
  | Ok probe ->
      let marker = "\n__UOS_HTTP__" in
      let body, http_metadata =
        match find_substring_from probe.output marker 0 with
        | None -> (probe.output, "")
        | Some index ->
            ( String.sub probe.output 0 index,
              String.sub probe.output (index + String.length marker)
                (String.length probe.output - index - String.length marker) )
      in
      let http_status =
        match String.split_on_char ' ' (String.trim http_metadata) with
        | code :: _ -> int_of_string_opt code
        | [] -> None
      in
      let parsed =
        try Some (Yojson.Basic.from_string body) with Yojson.Json_error _ -> None
      in
      let version =
        match parsed with
        | None -> None
        | Some json ->
            first_some
              [ json_string_member "version" json;
                json_string_member "build_version" json ]
      in
      let served_candidate =
        match parsed with
        | None -> None
        | Some json ->
            let build =
              match json with
              | `Assoc fields -> Option.value ~default:`Null (List.assoc_opt "build" fields)
              | _ -> `Null
            in
            first_some
              [ json_string_member "commit_id" json;
                json_string_member "change_id" json;
                json_string_member "build_revision" json;
                json_string_member "revision" json;
                json_string_member "commit_id" build;
                json_string_member "change_id" build ]
      in
      let identity_status =
        match served_candidate with
        | None -> "UNKNOWN"
        | Some candidate when candidate = commit_id || candidate = change_id -> "CURRENT"
        | Some _ -> "DIFFERENT"
      in
      `Assoc
        [ ("status", `String "reachable"); ("locator", `String url);
          ("exit_code", `Int (status_code probe.status));
          ("http_status", (match http_status with None -> `Null | Some x -> `Int x));
          ("response_bytes", `Int (String.length body));
          ( "response_sha256",
            `String
              (body |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex) );
          ("served_version", option_json version);
          ( "served_version_status",
            `String (if Option.is_some version then "observed" else "unknown") );
          ("served_candidate", option_json served_candidate);
          ("build_identity_status", `String identity_status);
          ("timed_out", `Bool false); ("output_overflow", `Bool false);
          ("direct_child_reaped", `Bool probe.direct_child_reaped);
          ( "process_group_termination_attempted",
            `Bool probe.process_group_termination_attempted );
          ("duration_ms", `Int probe.duration_ms);
          ("identity_credit", `Bool false); ("admission_credit", `Bool false);
          ("credit", `Bool false) ]

let dirty_json observation =
  match observation with
  | Error _ as error -> probe_json ~locator:"jj://@/diff-summary" error
  | Ok probe ->
      let base =
        [ ("status", `String (json_status probe));
          ("locator", `String "jj://@/diff-summary");
          ("exit_code", `Int (status_code probe.status));
          ("entries", `String probe.output);
          ("clean", `Bool (status_code probe.status = 0 && probe.output = ""));
          ("timed_out", `Bool probe.timed_out);
          ("output_overflow", `Bool probe.output_overflow);
          ("direct_child_reaped", `Bool probe.direct_child_reaped);
          ( "process_group_termination_attempted",
            `Bool probe.process_group_termination_attempted );
          ("duration_ms", `Int probe.duration_ms); ("credit", `Bool false) ]
      in
      `Assoc base

let identity_record locator value =
  `Assoc
    [ ("status", `String "observed"); ("locator", `String locator);
      ("value", `String value); ("credit", `Bool false) ]

type fixture_inputs = {
  fixture_candidate : string;
  fixture_evidence_candidate : string;
  fixture_source_mode : string;
  fixture_clock_source : string;
  fixture_inherited_claim : string;
}

let parse_fixture path =
  let required_keys =
    [ "candidate"; "clock_source"; "evidence_candidate"; "inherited_claim";
      "source_mode" ]
  in
  let string_field fields name =
    match List.assoc_opt name fields with
    | Some (`String value) when value <> "" -> Ok value
    | Some _ -> Error ("fixture field " ^ name ^ " must be a non-empty string")
    | None -> Error ("fixture field " ^ name ^ " is required")
  in
  match read_file_bounded ~max_bytes:65_536 path with
  | Error reason -> Error ("could not read fixture: " ^ reason)
  | Ok bytes -> (
      try
        let json = Yojson.Basic.from_string bytes in
        let given =
          match json with
          | `Assoc [ ("given", value) ] -> value
          | value -> value
        in
        match given with
        | `Assoc fields ->
            let keys = List.map fst fields |> List.sort String.compare in
            if keys <> required_keys then
              Error
                "fixture must contain exactly candidate, evidence_candidate, source_mode, clock_source and inherited_claim"
            else
              let ( let* ) = Result.bind in
              let* fixture_candidate = string_field fields "candidate" in
              let* fixture_evidence_candidate =
                string_field fields "evidence_candidate"
              in
              let* fixture_source_mode = string_field fields "source_mode" in
              let* fixture_clock_source = string_field fields "clock_source" in
              let* fixture_inherited_claim =
                string_field fields "inherited_claim"
              in
              Ok
                { fixture_candidate; fixture_evidence_candidate;
                  fixture_source_mode; fixture_clock_source;
                  fixture_inherited_claim }
        | _ -> Error "fixture root or given field must be a JSON object"
      with Yojson.Json_error message -> Error ("invalid fixture JSON: " ^ message))

let snapshot candidate evidence_candidate source_mode clock_source inherited_claim
    served_url jj_bin clock_bin curl_bin probe_output_bytes fixture =
  let candidate, evidence_candidate, source_mode, clock_source, inherited_claim =
    match fixture with
    | None ->
        (candidate, evidence_candidate, source_mode, clock_source, inherited_claim)
    | Some path -> (
        match parse_fixture path with
        | Error message ->
            prerr_endline ("candidate.snapshot: " ^ message);
            exit 2
        | Ok inputs ->
            ( inputs.fixture_candidate, inputs.fixture_evidence_candidate,
              inputs.fixture_source_mode, inputs.fixture_clock_source,
              inputs.fixture_inherited_claim ))
  in
  if candidate <> "current-jj" then begin
    prerr_endline "candidate.snapshot: --candidate must be current-jj";
    exit 2
  end;
  if source_mode <> "read_only" then begin
    prerr_endline "candidate.snapshot: --source-mode must be read_only";
    exit 2
  end;
  if clock_source <> "chrony" then begin
    prerr_endline "candidate.snapshot: --clock-source must be chrony";
    exit 2
  end;
  if inherited_claim <> "all_passed" then begin
    prerr_endline "candidate.snapshot: --inherited-claim must be all_passed";
    exit 2
  end;
  if jj_bin = "" || clock_bin = "" || curl_bin = "" then begin
    prerr_endline "candidate.snapshot: executable names must not be empty";
    exit 2
  end;
  if probe_output_bytes <= 0 || probe_output_bytes > 1_048_576 then begin
    prerr_endline "candidate.snapshot: --probe-output-bytes must be within 1..1048576";
    exit 2
  end;
  match observe_identity ~jj_bin ~max_bytes:probe_output_bytes () with
  | Error message ->
      prerr_endline ("candidate.snapshot: " ^ message);
      exit 1
  | Ok (change_id, commit_id) ->
      let evidence_matches =
        evidence_candidate = "current-jj" || evidence_candidate = change_id
        || evidence_candidate = commit_id
      in
      let dirty = observe_dirty_manifest ~jj_bin ~max_bytes:probe_output_bytes () in
      let served =
        observe_served_build ~curl_bin ~max_bytes:probe_output_bytes served_url
      in
      let versions = tool_versions ~jj_bin ~max_bytes:probe_output_bytes () in
      let clock = observe_clock ~clock_bin ~max_bytes:probe_output_bytes () in
      let writers = observe_process_names ~max_bytes:probe_output_bytes () in
      let binding = inspect_review_binding () in
      let claims = reviewed_claims ~binding ~evidence_matches in
      let sources =
        List.map
          (fun path ->
            if path = review_receipt_path then
              metadata_record ?content_digest:binding.observed_sha256 path
            else metadata_record path)
          metadata_allowlist
      in
      let quarantines =
        [ quarantine_record "Harness SSH injector" "/home/an/dev/ver/harness-bionic";
          quarantine_record "ZigVM OAuth secret" "/home/an/dev/ver/zigvm" ]
      in
      let final_dirty =
        observe_dirty_manifest ~jj_bin ~max_bytes:probe_output_bytes ()
      in
      let initial_dirty_text, final_dirty_text =
        match
          ( successful_output "initial Jujutsu dirty manifest" dirty,
            successful_output "final Jujutsu dirty manifest" final_dirty )
        with
        | Ok initial, Ok final -> (initial, final)
        | Error message, _ | _, Error message ->
            prerr_endline ("candidate.snapshot: " ^ message);
            exit 1
      in
      if initial_dirty_text <> final_dirty_text then begin
        prerr_endline
          "candidate.snapshot: workspace source state changed while snapshot probes ran";
        exit 1
      end;
      let final_change_id, final_commit_id =
        match observe_identity ~jj_bin ~max_bytes:probe_output_bytes () with
        | Error message ->
            prerr_endline
              ("candidate.snapshot: final Jujutsu stability check failed: " ^ message);
            exit 1
        | Ok identity -> identity
      in
      if final_change_id <> change_id || final_commit_id <> commit_id then begin
        prerr_endline
          "candidate.snapshot: candidate identity changed while snapshot probes ran";
        exit 1
      end;
      let external_probe_side_effects =
        if jj_bin = "jj" && clock_bin = "chronyc" && curl_bin = "curl" then
          "not_observed_beyond_workspace_delta"
        else "UNKNOWN"
      in
      let json =
        `Assoc
          [ ("schema", `String "uos.candidate-snapshot.v1");
            ("operation", `String "candidate.snapshot");
            ("status", `String "SNAPSHOT_CAPTURED_NONPASSING");
            ("admitted", `Bool false);
            ( "candidate",
              `Assoc
                [ ("alias", `String candidate); ("workspace", `String (Sys.getcwd ()));
                  ("change_id", `String change_id); ("commit_id", `String commit_id) ] );
            ("evidence_candidate", `String evidence_candidate);
            ( "inherited_credit",
              `String (if evidence_matches then "UNRUN" else "STALE") );
            ("source_mode", `String source_mode); ("source_writes", `Int 0);
            ( "source_write_observation",
              `Assoc
                [ ("method", `String "jj_diff_summary_before_after");
                  ( "source_writes_scope",
                    `String "candidate_snapshot_internal_requested_writes" );
                  ("workspace_state_unchanged", `Bool true);
                  ("net_source_changes_observed", `Int 0);
                  ("external_probe_side_effects", `String external_probe_side_effects);
                  ( "limitation",
                    `String
                      "ignored paths and transient writes reverted between observations are not detectable" );
                  ("source_preservation_credit", `Bool false);
                  ("credit", `Bool false) ] );
            ("signature_credit", `Bool false);
            ( "records",
              `Assoc
                [ ("change_id", identity_record "jj://@/change-id" change_id);
                  ("commit_id", identity_record "jj://@/commit-id" commit_id);
                  ("dirty_manifest", dirty_json dirty);
                  ( "served_build",
                    served_build_json ~change_id ~commit_id ~url:served_url served );
                  ("tool_versions", `List versions);
                  ( "clock_receipt",
                    probe_json ~locator:"chrony://tracking" clock );
                  ("writer_inventory", writers);
                  ( "candidate_stability",
                    `Assoc
                      [ ("status", `String "stable");
                        ("start_change_id", `String change_id);
                        ("end_change_id", `String final_change_id);
                        ("start_commit_id", `String commit_id);
                        ("end_commit_id", `String final_commit_id);
                        ("credit", `Bool false) ] ) ] );
            ("review_binding", review_binding_json binding);
            ("claims", `List claims); ("source_metadata", `List sources);
            ("quarantines", `List quarantines);
            ("resource_envelope", resource_envelope_record);
            ( "execution_bounds",
              `Assoc
                [ ("outer_timeout_seconds", `Int 1200);
                  ("probe_timeout_seconds_max", `Int 5);
                  ("probe_output_bytes_max", `Int probe_output_bytes);
                  ("termination_grace_ms", `Int 50) ] ) ]
      in
      print_endline (Yojson.Basic.to_string json)

let candidate =
  Arg.(value & opt string "current-jj" & info [ "candidate" ] ~docv:"ALIAS")

let evidence_candidate =
  Arg.(value & opt string "older-jj" & info [ "evidence-candidate" ] ~docv:"JJ_ID")

let source_mode =
  Arg.(value & opt string "read_only" & info [ "source-mode" ] ~docv:"MODE")

let clock_source =
  Arg.(value & opt string "chrony" & info [ "clock-source" ] ~docv:"SOURCE")

let inherited_claim =
  Arg.(value & opt string "all_passed" & info [ "inherited-claim" ] ~docv:"CLAIM")

let served_url =
  Arg.(
    value
    & opt string "http://nas-1.tail55d152.ts.net:4100/api/health"
    & info [ "served-url" ] ~docv:"URL")

let jj_bin = Arg.(value & opt string "jj" & info [ "jj-bin" ] ~docv:"PATH")

let clock_bin =
  Arg.(value & opt string "chronyc" & info [ "clock-bin" ] ~docv:"PATH")

let curl_bin =
  Arg.(value & opt string "curl" & info [ "curl-bin" ] ~docv:"PATH")

let probe_output_bytes =
  Arg.(
    value & opt int default_output_limit
    & info [ "probe-output-bytes" ] ~docv:"BYTES")

let fixture =
  Arg.(
    value & opt (some string) None
    & info [ "fixture" ] ~docv:"JSON_FILE"
        ~doc:"Strict E01 given-object fixture; expected values are rejected.")

let snapshot_command =
  let term =
    Term.(
      const snapshot $ candidate $ evidence_candidate $ source_mode $ clock_source
      $ inherited_claim $ served_url $ jj_bin $ clock_bin $ curl_bin
      $ probe_output_bytes $ fixture)
  in
  Cmd.v
    (Cmd.info "snapshot" ~doc:"capture a bounded read-only review candidate")
    term

let () =
  let command =
    Cmd.group (Cmd.info "candidate_snapshot" ~version:"1") [ snapshot_command ]
  in
  exit (Cmd.eval command)
