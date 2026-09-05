(* Capture pinned ROUTE-RESOLUTION traces for model_routing.route_resolution.
   Offline: the frozen get_fallback_chain is a pure config transform (no clock,
   env, net, fs). Deliberate and explicit -- it writes evidence. The captured
   fixture, not the probe's hand-derived expectations, is the proof. *)

let git_revision root =
  let command = "git -C " ^ Filename.quote root ^ " rev-parse HEAD" in
  try
    let channel = Unix.open_process_in command in
    Fun.protect
      ~finally:(fun () -> ignore (Unix.close_process_in channel))
      (fun () -> Ok (String.trim (input_line channel)))
  with End_of_file -> Error "cannot determine reference revision"
     | Unix.Unix_error (_, _, message) -> Error message

let () =
  let root = if Array.length Sys.argv > 1 then Sys.argv.(1) else "." in
  let reference_root = Bootstrap.reference_root root in
  match Inventory.scan ~root:reference_root with
  | Error message -> prerr_endline message; exit 1
  | Ok entries -> (
      let snapshot_digest = Inventory.snapshot_digest entries in
      match git_revision reference_root with
      | Error message -> prerr_endline message; exit 1
      | Ok reference_revision ->
          let normalizer = Parity_normalizer.default in
          Printf.printf "snapshot: %s\nreference: %s\n\n" snapshot_digest reference_revision;
          let failures = ref 0 in
          List.iter
            (fun (scenario_id, params_json) ->
              let params = match params_json with `Assoc fields -> fields | _ -> [] in
              let scenario : Reference_capture.scenario =
                { id = scenario_id; model = ""; messages = []; tools = None; params }
              in
              match
                Reference_capture.capture ~adapter_basename:"route_resolution_adapter.py" ~root
                  ~snapshot_digest ~reference_revision ~normalizer scenario
              with
              | Error failure ->
                  incr failures;
                  Printf.printf "  %-22s FAILED %s\n" scenario_id
                    (Reference_capture.describe failure)
              | Ok capture ->
                  (match Reference_capture.save ~root capture with | Error refusal -> incr failures; Printf.printf "  REFUSED %s\n" refusal | Ok path ->
                  Printf.printf "  %-22s %s\n    %s\n" scenario_id capture.normalized_digest
                    (Filename.basename path)))
            Parity_compare.route_scenarios;
          Printf.printf "\ncaptured %d/%d route scenarios\n"
            (List.length Parity_compare.route_scenarios - !failures)
            (List.length Parity_compare.route_scenarios);
          if !failures > 0 then exit 1)
