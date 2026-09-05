let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; Printf.printf "FAILED: %s\n" name
  | exception exn ->
      incr failed;
      Printf.printf "FAILED: %s (raised %s)\n" name (Printexc.to_string exn)

let digest path =
  In_channel.with_open_bin path In_channel.input_all
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let snapshot paths =
  List.map
    (fun path ->
      if Sys.file_exists path then (path, Some (digest path)) else (path, None))
    paths

let gospel_spec =
  List.find (fun (service : Ops_formal.service) -> service.sname = "gospel-spec")
    Ops_formal.services

let () =
  let untracked_interface = "modules/hermes_harness/retry_utils.mli" in
  let forbidden_sidecar = "modules/hermes_harness/retry_utils.gospel" in
  check "GF1 Gospel checks never create a sidecar beside an interface" (fun () ->
      not (Sys.file_exists forbidden_sidecar)
      && let result = Ops_formal.check_artifact gospel_spec untracked_interface in
         not (Sys.file_exists forbidden_sidecar)
         && if Ops_formal.tool_available gospel_spec then
              match result.verdict with Ops_formal.Unavailable _ -> false | _ -> true
            else match result.verdict with Ops_formal.Unavailable _ -> true | _ -> false);
  check "GF2 checking a contract cannot rewrite an existing tracked sidecar" (fun () ->
      let interface = "modules/hermes_harness/message_hygiene.mli" in
      let sidecar = "modules/hermes_harness/message_hygiene.gospel" in
      let before = digest sidecar in
      ignore (Ops_formal.check_artifact gospel_spec interface);
      Sys.file_exists sidecar && digest sidecar = before);
  check "GF3 Rocq compilation and extraction products stay inside the private stage" (fun () ->
      let artifact = "modules/hermes_harness/proofs/Parity_Lattice.v" in
      let generated =
        [ "modules/hermes_harness/proofs/Parity_Lattice.vo";
          "modules/hermes_harness/proofs/Parity_Lattice.vos";
          "modules/hermes_harness/proofs/Parity_Lattice.vok";
          "modules/hermes_harness/proofs/Parity_Lattice.glob" ]
      in
      let before = snapshot generated in
      let service =
        List.find (fun (item : Ops_formal.service) -> item.sname = "rocq")
          Ops_formal.services
      in
      let result = Ops_formal.check_artifact service artifact in
      before = snapshot generated
      && if Ops_formal.tool_available service then result.verdict = Ops_formal.Discharged
         else match result.verdict with Ops_formal.Unavailable _ -> true | _ -> false);
  Printf.printf "ops_formal_staging: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_ops_formal_staging" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability; Stanza.hermes_ops_governance; Stanza.hermes_ops_topology; Stanza.hermes_ops_completion_topology; Stanza.hermes_ops ]);
  exit (Suite_telemetry.exit_code self)
